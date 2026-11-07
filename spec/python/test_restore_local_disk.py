"""Unit tests for files/restore-local-disk.py.

Run with: python3 -m unittest discover -s spec/python -v

Every external command (virsh, rbd, qemu-img, chcon) is answered by a fake
dispatcher, and the instance directory is a temporary one, so nothing here
touches a hypervisor or a Ceph pool.
"""

import contextlib
import importlib.util
import io
import json
import os
import shutil
import stat
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

SCRIPT = Path(__file__).resolve().parents[2] / 'files' / 'restore-local-disk.py'
_spec = importlib.util.spec_from_file_location('restore_local_disk', SCRIPT)
rld = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(rld)

UUID = '11111111-1111-1111-1111-111111111111'
GIB = rld.GIB


class Fake:
    """Answers run() like a stopped instance whose 80 GiB old root is protected."""

    def __init__(self, test):
        self.test = test
        self.calls = []
        self.domstate = (0, 'shut off\n')
        self.later_domstate = None  # answers every domstate call after the first
        self.snaps = [{'id': 4, 'name': 'rt-preserve', 'size': 80 * GIB, 'protected': 'true'}]
        self.later_snaps = None  # answers every snap ls after the first
        self.rbd_info = (0, json.dumps({'name': f'{UUID}_disk', 'size': 80 * GIB}))
        self.local_info = {'format': 'qcow2', 'virtual-size': 100 * GIB}
        self.rbd_qemu_info = (0, json.dumps({'format': 'raw', 'virtual-size': 80 * GIB}))
        self.partial_info = {'format': 'qcow2', 'virtual-size': 80 * GIB}
        self.check = (0, 'No errors were found on the image.\n')
        self.resize = (0, 'Image resized.\n')
        self.chcon = (0, '')
        self.lock_error = None  # set to simulate a running qemu holding the lock

    def __call__(self, cmd):
        self.calls.append(cmd)
        tool = cmd[0]
        if tool == 'virsh':
            first = sum(c[0] == 'virsh' for c in self.calls) == 1
            return self.domstate if first or self.later_domstate is None else self.later_domstate
        if tool == 'chcon':
            return self.chcon
        if tool == 'rbd':
            if cmd[3] == 'snap':
                first = sum(c[0] == 'rbd' and c[3] == 'snap' for c in self.calls) == 1
                snaps = self.snaps if first or self.later_snaps is None else self.later_snaps
                return 0, json.dumps(snaps)
            return self.rbd_info
        if tool == 'qemu-img':
            sub, target = cmd[1], cmd[-1]
            if sub == 'info':
                if target.startswith('rbd:'):
                    return self.rbd_qemu_info
                if target.endswith('disk'):
                    if self.lock_error:
                        return 1, self.lock_error
                    return 0, json.dumps(self.local_info)
                return 0, json.dumps(self.partial_info)
            if sub == 'convert':
                Path(target).write_bytes(b'recovered')
                return 0, ''
            if sub == 'check':
                return self.check
            if sub == 'resize':
                return self.resize
        raise AssertionError(cmd)


class Base(unittest.TestCase):
    def setUp(self):
        self.root = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, str(self.root))
        self.inst = self.root / UUID
        self.inst.mkdir()
        self.disk = self.inst / 'disk'
        self.disk.write_bytes(b'current')
        self.disk.chmod(0o600)
        self.conf = self.root / 'nova.conf'
        self.conf.write_text('[libvirt]\nrbd_user = cinder\n')
        self.fake = Fake(self)
        self.patch(mock.patch.object(rld, 'run', self.fake))
        self.patch(mock.patch.object(rld, 'run_live', lambda cmd: self.fake(cmd)[0]))
        self.patch(mock.patch.object(rld.shutil, 'which', return_value='/usr/bin/x'))
        self.usage = self.patch(mock.patch.object(
            rld.shutil, 'disk_usage', return_value=os.statvfs_result((0,) * 10)))
        self.usage.return_value = mock.Mock(free=500 * GIB)
        self.chown = self.patch(mock.patch.object(rld.os, 'chown'))

    def patch(self, patcher):
        self.addCleanup(patcher.stop)
        return patcher.start()

    def args(self, *extra):
        return rld.parse_args([*extra, '--instances-dir', str(self.root),
                               '--nova-conf', str(self.conf), UUID, 'rt-preserve'])

    def job(self, *extra):
        out = io.StringIO()
        return rld.Restore(self.args(*extra), out=out), out

    def run_main(self, *extra):
        out, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            rc = rld.main([*extra, '--instances-dir', str(self.root),
                           '--nova-conf', str(self.conf), UUID, 'rt-preserve'])
        return rc, out.getvalue(), err.getvalue()

    def refused(self, *extra):
        rc, out, err = self.run_main(*extra)
        self.assertEqual(rc, 1, err)
        self.assertTrue(err.startswith('refused: '), err)
        return err

    def writes(self):
        return [c for c in self.fake.calls if c[0] == 'qemu-img' and c[1] != 'info'
                or c[0] == 'chcon']


class ParseArgsTest(Base):
    def test_defaults(self):
        a = self.args()
        self.assertEqual((a.uuid, a.snap, a.tag, a.rbd_pool, a.size, a.run),
                         (UUID, 'rt-preserve', 'rt-preserve', 'vms', None, False))
        a = self.args('--run', '--rbd-pool', 'vms_x', '--size', '120', '--tag', 'rt1')
        self.assertEqual((a.rbd_pool, a.size, a.tag, a.run), ('vms_x', 120, 'rt1', True))


class GuardTest(Base):
    def test_missing_tool(self):
        rld.shutil.which.return_value = None
        self.assertIn('rbd is not installed', self.refused())

    def test_no_rbd_user(self):
        self.conf.write_text('[libvirt]\nvirt_type = kvm\n')
        err = self.refused()
        self.assertIn('no rbd_user in [libvirt]', err)
        self.assertIn('no Ceph key for nova', err)
        self.assertEqual(self.fake.calls, [])  # nothing was asked before the refusal

    def test_no_rbd_user_without_a_conf_at_all(self):
        self.conf.unlink()
        self.assertIn('no rbd_user in [libvirt]', self.refused())

    def test_rbd_user_is_checked_before_the_tools(self):
        # the kitchen local-storage node has neither; the config refusal is the one it asserts
        self.conf.write_text('[libvirt]\nvirt_type = kvm\n')
        rld.shutil.which.return_value = None
        self.assertIn('no rbd_user in [libvirt]', self.refused())

    def test_missing_disk(self):
        self.disk.unlink()
        self.assertIn('does not exist; is the instance on this host', self.refused())

    def test_ephemeral_disk_refuses(self):
        (self.inst / 'disk.eph0').write_bytes(b'')
        self.assertIn('also has disk.eph0; this tool restores the root disk only', self.refused())

    def test_running_domain(self):
        self.fake.domstate = (0, 'running\n')
        err = self.refused()
        self.assertIn("is 'running', not \"shut off\"", err)
        self.assertIn('openstack server stop', err)

    def test_unknown_domain(self):
        self.fake.domstate = (1, 'error: failed to get domain')
        self.assertIn('not "shut off"', self.refused())

    def test_leftovers_from_an_earlier_run(self):
        for name in ('disk.recovered.partial', 'disk.recovered', 'disk.pre-rt-preserve'):
            (self.inst / name).write_bytes(b'')
            err = self.refused()
            self.assertIn(f'{self.inst / name} already exists from an earlier run', err)
            self.assertIn(f'rm {self.inst / name} to retry', err)
            (self.inst / name).unlink()

    def test_locked_disk(self):
        self.fake.lock_error = ('qemu-img: Failed to get shared "write" lock\n'
                                'Is another process using the image?')
        err = self.refused()
        self.assertIn('qemu-img cannot open', err)
        self.assertIn('Failed to get shared "write" lock', err)

    def test_disk_not_qcow2(self):
        self.fake.local_info = {'format': 'raw', 'virtual-size': 100 * GIB}
        self.assertIn("is 'raw', not qcow2", self.refused())

    def test_unprotected_snapshot(self):
        self.fake.snaps[0]['protected'] = 'false'
        err = self.refused()
        self.assertIn(f'vms/{UUID}_disk@rt-preserve is not protected', err)
        self.assertIn(f'rbd --id cinder snap protect vms/{UUID}_disk@rt-preserve first', err)

    def test_protected_as_a_bool(self):
        self.fake.snaps[0]['protected'] = True
        rc, out, _ = self.run_main()
        self.assertEqual(rc, 0, out)

    def test_missing_snapshot(self):
        self.fake.snaps = [{'name': 'other', 'protected': 'true'}]
        self.assertIn('has no snapshot \'rt-preserve\'; protect one first', self.refused())

    def test_snapshot_listing_fails(self):
        fake = self.fake

        def failing(cmd):
            if cmd[0] == 'rbd' and cmd[3] == 'snap':
                return 2, 'rbd: error opening image'
            return fake(cmd)
        with mock.patch.object(rld, 'run', failing):
            err = self.refused()
        self.assertIn('rbd snap ls vms/', err)
        self.assertIn('rc=2', err)

    def test_rbd_source_unreadable(self):
        self.fake.rbd_qemu_info = (1, 'qemu-img: error reading header')
        err = self.refused()
        self.assertIn(f'cannot open rbd:vms/{UUID}_disk@rt-preserve:id=cinder:conf=/etc/ceph/ceph.conf',
                      err)

    def test_old_root_larger_than_the_target(self):
        self.fake.rbd_qemu_info = (0, json.dumps({'format': 'raw', 'virtual-size': 120 * GIB}))
        self.assertIn('the old root is 120 GiB but the target is 100 GiB; a disk is never shrunk',
                      self.refused())
        self.assertIn('the target is 110 GiB', self.refused('--size', '110'))

    def test_not_enough_space(self):
        self.usage.return_value = mock.Mock(free=79 * GIB)
        self.assertIn('has 79 GiB free, the image is 80 GiB; make room first', self.refused())

    def test_guards_read_only_in_the_dry_run(self):
        rc, out, err = self.run_main()
        self.assertEqual(rc, 0, err)
        self.assertEqual(self.writes(), [])
        self.assertEqual(self.disk.read_bytes(), b'current')
        self.assertEqual(sorted(p.name for p in self.inst.iterdir()), ['disk'])
        self.chown.assert_not_called()


class DryRunTest(Base):
    def test_prints_the_whole_plan(self):
        rc, out, _ = self.run_main()
        self.assertEqual(rc, 0)
        rbd = f'rbd:vms/{UUID}_disk@rt-preserve:id=cinder:conf=/etc/ceph/ceph.conf'
        partial, recovered = self.inst / 'disk.recovered.partial', self.inst / 'disk.recovered'
        kept = self.inst / 'disk.pre-rt-preserve'
        expected = [
            f'DRY RUN: restore vms/{UUID}_disk@rt-preserve (80 GiB) onto {self.disk} as a 100 GiB '
            f'qcow2, keeping the current disk as {kept}',
            f'would run> qemu-img convert -p -f raw -O qcow2 {rbd} {partial}',
            f'would run> qemu-img info --output=json {partial}   # must be qcow2 with no backing file',
            f'would run> qemu-img check {partial}',
            f'would run> mv {partial} {recovered}',
            f'would run> qemu-img resize {recovered} {100 * GIB}',
            f'would: chown {os.getuid()}:{os.getgid()}, chmod 0600, chcon --reference '
            f'{self.disk} {recovered}',
            f'would run> mv {self.disk} {kept}',
            f'would run> mv {recovered} {self.disk}',
            f'rollback would be: mv {self.disk} {recovered} && mv {kept} {self.disk}',
            'dry run clean; add --run to do it',
            f'then, on a controller: openstack server start {UUID}',
        ]
        self.assertEqual(out.splitlines(), expected)

    def test_size_and_tag_flags(self):
        _, out, _ = self.run_main('--size', '150', '--tag', 'rt1')
        self.assertIn(f'qemu-img resize {self.inst / "disk.recovered"} {150 * GIB}', out)
        self.assertIn(f'mv {self.disk} {self.inst / "disk.pre-rt1"}', out)

    def test_no_resize_when_sizes_match(self):
        _, out, _ = self.run_main('--size', '80')
        self.assertNotIn('qemu-img resize', out)


class RunTest(Base):
    def test_full_run(self):
        rc, out, err = self.run_main('--run')
        self.assertEqual(rc, 0, err)
        partial, recovered = self.inst / 'disk.recovered.partial', self.inst / 'disk.recovered'
        kept = self.inst / 'disk.pre-rt-preserve'
        # the swap happened, the old disk is kept, nothing partial is left
        self.assertEqual(self.disk.read_bytes(), b'recovered')
        self.assertEqual(kept.read_bytes(), b'current')
        self.assertFalse(partial.exists())
        self.assertFalse(recovered.exists())
        # the convert, check and resize ran in order, then the metadata copy before the swap
        writes = self.writes()
        self.assertEqual([c[1] if c[0] == 'qemu-img' else c[0] for c in writes],
                         ['convert', 'check', 'resize', 'chcon'])
        self.assertEqual(writes[0][-2:], [f'rbd:vms/{UUID}_disk@rt-preserve:id=cinder:'
                                          'conf=/etc/ceph/ceph.conf', str(partial)])
        self.assertEqual(writes[2], ['qemu-img', 'resize', str(recovered), str(100 * GIB)])
        self.assertEqual(writes[3], ['chcon', '--reference', str(self.disk), str(recovered)])
        self.chown.assert_called_once_with(str(recovered), os.getuid(), os.getgid())
        self.assertEqual(stat.S_IMODE(self.disk.stat().st_mode), 0o600)
        self.assertIn(f'rollback:\n  mv {self.disk} {recovered} && mv {kept} {self.disk}', out)
        self.assertIn(f'then, on a controller: openstack server start {UUID}', out)

    def test_guest_started_during_the_convert_stops_the_swap(self):
        self.fake.later_domstate = (0, 'running\n')
        rc, out, err = self.run_main('--run')
        self.assertEqual(rc, 1)
        self.assertIn("refused: domain", err)
        self.assertIn("is 'running', not \"shut off\"", err)
        self.assertIn('left on disk: disk.recovered, disk', err)
        self.assertEqual(self.disk.read_bytes(), b'current')
        self.assertEqual((self.inst / 'disk.recovered').read_bytes(), b'recovered')
        self.assertNotIn('rollback', out)

    def test_snapshot_unprotected_before_the_convert(self):
        self.fake.later_snaps = [{'name': 'rt-preserve', 'protected': 'false'}]
        rc, _, err = self.run_main('--run')
        self.assertEqual(rc, 1)
        self.assertIn('is not protected', err)
        self.assertEqual(self.writes(), [])
        self.assertEqual(sorted(p.name for p in self.inst.iterdir()), ['disk'])

    def test_leaked_clusters_are_accepted(self):
        self.fake.check = (3, '12 leaked clusters were found on the image.\n')
        rc, out, _ = self.run_main('--run')
        self.assertEqual(rc, 0)
        self.assertIn('(leaked clusters reported, harmless)', out)

    def test_corrupt_image_stops_before_the_swap(self):
        self.fake.check = (2, 'ERROR cluster 5 refcount=0 reference=1\n')
        rc, out, err = self.run_main('--run')
        self.assertEqual(rc, 2)
        self.assertIn('FAILED: qemu-img check', err)
        self.assertIn('rc=2', err)
        self.assertIn('left on disk: disk.recovered.partial, disk', err)
        self.assertEqual(self.disk.read_bytes(), b'current')
        self.assertNotIn('rollback', out)

    def test_backing_file_stops_before_the_swap(self):
        self.fake.partial_info = {'format': 'qcow2', 'virtual-size': 80 * GIB,
                                  'backing-filename': '/x/base'}
        rc, _, err = self.run_main('--run')
        self.assertEqual(rc, 2)
        self.assertIn('is not a standalone qcow2', err)
        self.assertEqual(self.disk.read_bytes(), b'current')

    def test_chcon_failure_leaves_the_current_disk_in_place(self):
        self.fake.chcon = (1, 'chcon: failed to change context')
        rc, out, err = self.run_main('--run')
        self.assertEqual(rc, 2)
        self.assertIn('FAILED: chcon', err)
        self.assertEqual(self.disk.read_bytes(), b'current')
        self.assertTrue((self.inst / 'disk.recovered').exists())
        self.assertIn('left on disk: disk.recovered, disk', err)
        self.assertNotIn('rollback', out)

    def test_second_rename_failure_prints_the_half_rollback(self):
        kept = self.inst / 'disk.pre-rt-preserve'
        real_rename = os.rename

        def rename(src, dst):
            if dst == str(self.disk):
                raise OSError('disk full')
            real_rename(src, dst)
        with mock.patch.object(rld.os, 'rename', rename):
            with self.assertRaises(OSError):
                job, out = self.job('--run')
                job.go()
        self.assertIn(f'rollback:\n  mv {kept} {self.disk}', out.getvalue())
        self.assertEqual(kept.read_bytes(), b'current')


if __name__ == '__main__':
    unittest.main()
