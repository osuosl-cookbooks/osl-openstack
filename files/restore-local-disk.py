#!/usr/bin/python3
"""Restore an instance's old Ceph root disk onto its local-storage compute.

A resize or cold migration from a Ceph flavor to a local-storage flavor does
not move the root disk: the guest comes back on a fresh disk built from its
image and the old root is left behind in the Ceph pool as <uuid>_disk. This
converts a protected snapshot of that image onto the instance's local qcow2
disk, in place.

Usage, as root on the local-storage compute that now runs the instance:
    nova-restore-local-disk [--run] UUID SNAP

Dry run by default: every guard runs and every command is printed, nothing
is written. Stop the instance through nova first (openstack server stop UUID
on a controller, wait for SHUTOFF) and start it again afterwards. Root disk
only. docs/CROSS_STORAGE_RESIZE.md in osl-openstack has the whole procedure.

Exit codes: 0 done or dry run clean, 1 a guard refused, 2 a step failed
(what is left on disk and how to roll back is printed).
"""

import argparse
import configparser
import glob
import json
import os
import shutil
import stat
import subprocess
import sys

GIB = 1024 ** 3
CHECK_OK = (0, 3)  # 3 is leaked clusters, reported but not corruption


class Refused(Exception):
    pass


class StepFailed(Exception):
    pass


def parse_args(argv=None):
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('uuid', help='instance uuid; its directory under --instances-dir')
    ap.add_argument('snap', help='protected snapshot of <uuid>_disk to convert from')
    ap.add_argument('--run', action='store_true', help='do it (default: dry run)')
    ap.add_argument('--rbd-pool', default='vms', metavar='POOL',
                    help='Ceph pool holding the old root (default vms; a local compute\'s '
                         'nova.conf does not name it)')
    ap.add_argument('--size', type=int, metavar='GIB',
                    help='grow the recovered disk to this size (default: the current '
                         'local disk\'s virtual size, which nova built at the new flavor)')
    ap.add_argument('--tag', metavar='TAG',
                    help='suffix for the kept current disk, disk.pre-TAG (default: SNAP)')
    ap.add_argument('--instances-dir', default='/var/lib/nova/instances', metavar='DIR')
    ap.add_argument('--nova-conf', default='/etc/nova/nova.conf', metavar='FILE',
                    help='read [libvirt] rbd_user from here')
    args = ap.parse_args(argv)
    args.tag = args.tag or args.snap
    return args


def run(cmd):
    """Run a command, return (rc, combined output)."""
    proc = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                          universal_newlines=True)
    return proc.returncode, proc.stdout


def run_live(cmd):
    """Run a command on the terminal (for the convert's progress), return rc."""
    return subprocess.run(cmd).returncode


def rbd_user(nova_conf):
    cfg = configparser.ConfigParser(interpolation=None, strict=False)
    try:
        cfg.read(nova_conf)
    except configparser.Error:
        return None
    return cfg.get('libvirt', 'rbd_user', fallback=None)


def qemu_img_info(path):
    """Parsed `qemu-img info` JSON, or a Refused naming the reason (no -U: a lock refuses)."""
    rc, out = run(['qemu-img', 'info', '--output=json', path])
    if rc != 0:
        raise Refused(f'qemu-img cannot open {path} (locked by a running qemu, or unreadable):\n'
                      f'  {out.strip()}')
    try:
        return json.loads(out)
    except ValueError:
        raise Refused(f'qemu-img info on {path} returned no JSON: {out.strip()}')


def snapshot_protected(user, image, snap):
    rc, out = run(['rbd', '--id', user, 'snap', 'ls', image, '--format', 'json'])
    if rc != 0:
        raise Refused(f'rbd snap ls {image} failed (rc={rc}): {out.strip()}')
    try:
        snaps = json.loads(out)
    except ValueError:
        raise Refused(f'rbd snap ls {image} returned no JSON: {out.strip()}')
    for s in snaps:
        if s.get('name') == snap:
            return str(s.get('protected', '')).lower() == 'true'
    raise Refused(f'{image} has no snapshot {snap!r}; protect one first')


def rbd_size(user, image):
    rc, out = run(['rbd', '--id', user, 'info', image, '--format', 'json'])
    if rc != 0:
        raise Refused(f'rbd info {image} failed (rc={rc}): {out.strip()}')
    try:
        return int(json.loads(out)['size'])
    except (ValueError, KeyError, TypeError):
        raise Refused(f'rbd info {image} returned no size: {out.strip()}')


class Restore:
    def __init__(self, args, out=None):
        self.args = args
        self.out = out or sys.stdout
        self.dir = os.path.join(args.instances_dir, args.uuid)
        self.disk = os.path.join(self.dir, 'disk')
        self.partial = os.path.join(self.dir, 'disk.recovered.partial')
        self.recovered = os.path.join(self.dir, 'disk.recovered')
        self.kept = os.path.join(self.dir, f'disk.pre-{args.tag}')
        self.image = f'{args.rbd_pool}/{args.uuid}_disk'
        self.user = None
        self.source = None  # the rbd: URL qemu reads
        self.target_bytes = None
        self.source_bytes = None

    def say(self, msg):
        print(msg, file=self.out, flush=True)  # stays ahead of the convert's own output

    # ------------------------------------------------------------ guards

    def ensure_stopped(self):
        """The domain is shut off and nothing holds the disk; checked again before the swap."""
        rc, out = run(['virsh', 'domstate', self.args.uuid])
        state = out.strip()
        if rc != 0 or state != 'shut off':
            raise Refused(f'domain {self.args.uuid} is {state or "unknown"!r}, not "shut off"; '
                          'stop it through nova first (openstack server stop)')
        info = qemu_img_info(self.disk)  # without -U, a running qemu's lock refuses
        if info.get('format') != 'qcow2':
            raise Refused(f'{self.disk} is {info.get("format")!r}, not qcow2; not the '
                          'layout this tool expects')
        return int(info['virtual-size'])

    def ensure_protected(self):
        if not snapshot_protected(self.user, self.image, self.args.snap):
            raise Refused(f'{self.image}@{self.args.snap} is not protected; '
                          f'rbd --id {self.user} snap protect {self.image}@{self.args.snap} first')

    def check(self):
        """Every precondition, read-only; raises Refused on the first that fails."""
        self.user = rbd_user(self.args.nova_conf)
        if not self.user:
            raise Refused(f'no rbd_user in [libvirt] of {self.args.nova_conf}: this host has '
                          'no Ceph key for nova, so it cannot read the pool')
        for tool in ('rbd', 'qemu-img', 'virsh', 'chcon'):
            if not shutil.which(tool):
                raise Refused(f'{tool} is not installed on this host')
        if not os.path.isfile(self.disk):
            raise Refused(f'{self.disk} does not exist; is the instance on this host?')
        eph = glob.glob(os.path.join(self.dir, 'disk.eph*'))
        if eph:
            raise Refused(f'{self.dir} also has {", ".join(sorted(os.path.basename(e) for e in eph))}; '
                          'this tool restores the root disk only')
        for path in (self.partial, self.recovered, self.kept):
            if os.path.exists(path):
                raise Refused(f'{path} already exists from an earlier run; inspect it, then '
                              f'rm {path} to retry')
        current_bytes = self.ensure_stopped()
        self.ensure_protected()
        self.source = (f'rbd:{self.image}@{self.args.snap}:id={self.user}'
                       ':conf=/etc/ceph/ceph.conf')
        src = qemu_img_info(self.source)  # proves the rbd driver and the parent read
        self.source_bytes = int(src['virtual-size'])
        self.target_bytes = self.args.size * GIB if self.args.size else current_bytes
        if self.source_bytes > self.target_bytes:
            raise Refused(f'the old root is {self.source_bytes // GIB} GiB but the target is '
                          f'{self.target_bytes // GIB} GiB; a disk is never shrunk')
        need = rbd_size(self.user, self.image)
        free = shutil.disk_usage(self.dir).free
        if free < need:
            raise Refused(f'{self.dir} has {free // GIB} GiB free, the image is '
                          f'{need // GIB} GiB; make room first')

    # ------------------------------------------------------------- steps

    def cmd(self, argv, ok=(0,), live=False):
        printable = ' '.join(argv)
        if not self.args.run:
            self.say(f'would run> {printable}')
            return ''
        self.say(f'run> {printable}')
        if live:
            rc, out = run_live(argv), ''
        else:
            rc, out = run(argv)
        if rc not in ok:
            raise StepFailed(f'{printable} failed (rc={rc}):\n  {out.strip()}')
        return out

    def convert(self):
        if self.args.run:
            self.ensure_protected()  # the stop window is long enough for someone to unprotect
        self.cmd(['qemu-img', 'convert', '-p', '-f', 'raw', '-O', 'qcow2', self.source,
                  self.partial], live=True)
        if not self.args.run:
            self.say(f'would run> qemu-img info --output=json {self.partial}'
                     '   # must be qcow2 with no backing file')
        else:
            info = qemu_img_info(self.partial)
            if info.get('format') != 'qcow2' or info.get('backing-filename'):
                raise StepFailed(f'{self.partial} is not a standalone qcow2: {info}')
        out = self.cmd(['qemu-img', 'check', self.partial], ok=CHECK_OK)
        if 'leaked' in out:
            self.say(f'  (leaked clusters reported, harmless)\n  {out.strip()}')
        self.rename(self.partial, self.recovered)
        if self.source_bytes < self.target_bytes:
            self.cmd(['qemu-img', 'resize', self.recovered, str(self.target_bytes)])

    def copy_metadata(self):
        """Owner, mode and SELinux context from the stopped disk; libvirt expects them."""
        st = os.stat(self.disk)
        mode = f'{stat.S_IMODE(st.st_mode):04o}'
        if not self.args.run:
            self.say(f'would: chown {st.st_uid}:{st.st_gid}, chmod {mode}, chcon --reference '
                     f'{self.disk} {self.recovered}')
            return
        self.say(f'chown {st.st_uid}:{st.st_gid} and chmod {mode} on {self.recovered}')
        os.chown(self.recovered, st.st_uid, st.st_gid)
        os.chmod(self.recovered, stat.S_IMODE(st.st_mode))
        self.cmd(['chcon', '--reference', self.disk, self.recovered])

    def rename(self, src, dst):
        if not self.args.run:
            self.say(f'would run> mv {src} {dst}')
            return
        self.say(f'run> mv {src} {dst}')
        os.rename(src, dst)

    def swap(self):
        """The two renames, last; from the first one on, the rollback is printed."""
        if self.args.run:
            self.ensure_stopped()  # the convert took a while; nova may have started the guest
        swapped = 0
        try:
            self.rename(self.disk, self.kept)
            swapped = 1
            self.rename(self.recovered, self.disk)
            swapped = 2
        finally:
            if self.args.run and swapped:
                self.say('rollback:')
                if swapped == 2:
                    self.say(f'  mv {self.disk} {self.recovered} && mv {self.kept} {self.disk}')
                else:
                    self.say(f'  mv {self.kept} {self.disk}')
            elif not self.args.run:
                self.say(f'rollback would be: mv {self.disk} {self.recovered} && '
                         f'mv {self.kept} {self.disk}')

    def go(self):
        self.check()
        self.say(f'{"RUN" if self.args.run else "DRY RUN"}: restore {self.image}@{self.args.snap} '
                 f'({self.source_bytes // GIB} GiB) onto {self.disk} as a '
                 f'{self.target_bytes // GIB} GiB qcow2, keeping the current disk as {self.kept}')
        self.convert()
        self.copy_metadata()
        self.swap()
        self.say('done' if self.args.run else 'dry run clean; add --run to do it')
        self.say(f'then, on a controller: openstack server start {self.args.uuid}')


def leftovers(job):
    return [os.path.basename(p) for p in (job.partial, job.recovered, job.kept, job.disk)
            if os.path.exists(p)]


def main(argv=None):
    args = parse_args(argv)
    job = Restore(args)
    try:
        job.go()
    except Refused as e:
        print(f'refused: {e}', file=sys.stderr)
        if args.run:  # a refusal after the convert leaves the recovered disk behind
            print('left on disk: ' + ', '.join(leftovers(job)), file=sys.stderr)
        return 1
    except StepFailed as e:
        print(f'FAILED: {e}', file=sys.stderr)
        print('left on disk: ' + ', '.join(leftovers(job)), file=sys.stderr)
        return 2
    return 0


if __name__ == '__main__':
    sys.exit(main())
