#!/usr/bin/env python3
"""Cold-migrate nova instances from one compute host to a specific destination.

Cold migration shuts the guest down, rebuilds its domain XML on the
destination and boots it there, so it sidesteps the live-migration blockers
between differing qemu/libvirt versions (e.g. AlmaLinux 8 -> 9 on POWER9).
With RBD-backed instances no disk data is copied.

Instances are migrated one at a time and each resize is confirmed before the
next one starts. Run on a controller with admin OpenStack credentials
sourced. Run nova-resize-debris-check.py first: stale nova-resize snapshots,
migration contexts or stuck volumes make the resize path fail.
"""

import argparse
import datetime
import logging
import sys
import time

import openstack
from keystoneauth1 import exceptions as ks_exc
from openstack import exceptions as os_exc

MIGRATABLE = ('ACTIVE', 'SHUTOFF')
# First compute API microversion that accepts a target host on a cold migration
MIGRATE_MICROVERSION = '2.56'

log = logging.getLogger('cold-migrate')


class MigrationFailed(Exception):
    pass


def parse_args():
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('src', help='source compute host')
    ap.add_argument('dst', help='destination compute host')
    ap.add_argument('instances', nargs='*', metavar='UUID',
                    help='instances to migrate (default: all ACTIVE/SHUTOFF on SRC)')
    ap.add_argument('-n', '--dry-run', action='store_true',
                    help='list what would be migrated and exit')
    ap.add_argument('-k', '--keep-going', action='store_true',
                    help='continue after a failed instance (default: stop)')
    ap.add_argument('-c', '--no-confirm', action='store_true',
                    help='leave instances in VERIFY_RESIZE instead of confirming')
    ap.add_argument('-t', '--timeout', type=int, default=1800, metavar='SEC',
                    help='per-instance timeout for each state change (default 1800)')
    ap.add_argument('-i', '--interval', type=int, default=10, metavar='SEC',
                    help='status poll interval (default 10)')
    ap.add_argument('-p', '--pause', type=int, default=0, metavar='SEC',
                    help='pause between instances (default 0)')
    ap.add_argument('-l', '--log', metavar='FILE',
                    help='log file (default /root/cold-migrate-SRC-DST-DATE.log)')
    return ap.parse_args()


def setup_logging(path):
    fmt = logging.Formatter('%(asctime)s %(message)s', '%Y-%m-%dT%H:%M:%SZ')
    fmt.converter = time.gmtime
    for handler in (logging.StreamHandler(sys.stdout), logging.FileHandler(path)):
        handler.setFormatter(fmt)
        log.addHandler(handler)
    log.setLevel(logging.INFO)


def compute_service(conn, host):
    return next(iter(conn.compute.services(binary='nova-compute', host=host)), None)


def fault_message(conn, server_id):
    """Nova's recorded fault for an instance.

    The SDK's Server model at the version RDO ships has no fault field, so
    read it from the raw API response.
    """
    try:
        body = conn.compute.get(f'/servers/{server_id}').json()
        return body['server']['fault']['message']
    except (KeyError, TypeError, ValueError, os_exc.SDKException, ks_exc.ClientException):
        return 'no fault recorded'


def wait_for(conn, server_id, status, args, reverted_to=None):
    """Poll until the instance reaches status; raise MigrationFailed otherwise.

    ERROR always fails. If reverted_to is given, landing back in that status
    with no task_state also fails: that is what nova does when the scheduler
    rejects the requested host (NoValidHost), instead of going to ERROR.
    """
    deadline = time.monotonic() + args.timeout
    while True:
        server = conn.compute.get_server(server_id)
        if server.status == status:
            return server
        if server.status == 'ERROR':
            raise MigrationFailed(f'went to ERROR: {fault_message(conn, server_id)}')
        if reverted_to and server.status == reverted_to and server.task_state is None:
            raise MigrationFailed(
                f'nova reverted the migration: {fault_message(conn, server_id)}')
        if time.monotonic() >= deadline:
            raise MigrationFailed(
                f'still {server.status} after {args.timeout}s; check manually')
        time.sleep(args.interval)


def cold_migrate(conn, server, dst):
    # openstacksdk's migrate_server() has no host argument at the version
    # RDO ships, so post the action directly.
    resp = conn.compute.post(
        f'/servers/{server.id}/action', json={'migrate': {'host': dst}},
        microversion=MIGRATE_MICROVERSION)
    os_exc.raise_from_response(resp, error_message='migrate request rejected')


def migrate_one(conn, server, args, position):
    before = server.status
    log.info('%s %s (%s) %s: migrate %s -> %s', position, server.id, server.name,
             before, args.src, args.dst)
    try:
        cold_migrate(conn, server, args.dst)
    except os_exc.HttpException as e:
        raise MigrationFailed(str(e))

    # The API sets task_state before returning 202, so a poll that finds the
    # original status with no task_state means nova already gave up.
    server = wait_for(conn, server.id, 'VERIFY_RESIZE', args, reverted_to=before)
    if server.compute_host != args.dst:
        raise MigrationFailed(
            f'landed on {server.compute_host!r}, not {args.dst}; left in VERIFY_RESIZE')

    if args.no_confirm:
        log.info('OK   %s on %s, left in VERIFY_RESIZE', server.id, args.dst)
        return

    try:
        conn.compute.confirm_server_resize(server)
    except os_exc.HttpException as e:
        raise MigrationFailed(
            f'resize confirm rejected; instance is on {args.dst} in VERIFY_RESIZE: {e}')
    wait_for(conn, server.id, before, args)
    log.info('OK   %s on %s, %s', server.id, args.dst, before)


def main():
    args = parse_args()
    if args.src == args.dst:
        sys.exit('source and destination host are the same')
    if not args.log:
        stamp = datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%d-%H%M%S')
        args.log = f'/root/cold-migrate-{args.src}-{args.dst}-{stamp}.log'
    setup_logging(args.log)

    # --- preflight
    # Credential problems surface either at connect() (missing options) or on
    # the first API call (bad password); keystoneauth raises its own classes.
    try:
        conn = openstack.connect()
        src_svc = compute_service(conn, args.src)
    except (os_exc.SDKException, ks_exc.ClientException) as e:
        sys.exit(f'cannot talk to OpenStack (is an admin openrc sourced?): {e}')
    if src_svc is None:
        sys.exit(f'no nova-compute service registered for host {args.src}')
    dst_svc = compute_service(conn, args.dst)
    if dst_svc is None:
        sys.exit(f'no nova-compute service registered for host {args.dst}')
    if (dst_svc.status, dst_svc.state) != ('enabled', 'up'):
        sys.exit(f'destination {args.dst} nova-compute is '
                 f'{dst_svc.status}/{dst_svc.state} (need enabled/up)')

    on_src = {s.id: s for s in conn.compute.servers(
        details=True, all_projects=True, compute_host=args.src)}
    if not on_src:
        sys.exit(f'no instances found on {args.src}')

    if args.instances:
        wanted = list(dict.fromkeys(args.instances))  # dedupe, keep order
        missing = [i for i in wanted if i not in on_src]
        if missing:
            sys.exit(f'not on {args.src}: {", ".join(missing)}')
        todo = [on_src[i] for i in wanted]
    else:
        todo = sorted(on_src.values(), key=lambda s: (s.name, s.id))

    queue = [s for s in todo if s.status in MIGRATABLE]
    skipped = [s for s in todo if s.status not in MIGRATABLE]
    print(f'Plan: {args.src} -> {args.dst} ({len(queue)} instance(s)), log {args.log}')
    for s in todo:
        note = '' if s.status in MIGRATABLE else '  (skipped: not ACTIVE/SHUTOFF)'
        print(f'  {s.id:36}  {s.status:14} {s.name}{note}')
    if not queue:
        sys.exit('nothing to migrate')
    if args.dry_run:
        return 0

    # --- migrate
    done, failed = [], []
    for n, server in enumerate(queue, 1):
        try:
            migrate_one(conn, server, args, f'[{n}/{len(queue)}]')
            done.append(server)
        except (MigrationFailed, os_exc.SDKException, ks_exc.ClientException) as e:
            failed.append(server)
            if isinstance(e, MigrationFailed):
                log.error('FAIL %s: %s', server.id, e)
            else:
                # API/transport error mid-flight: nova may still be working on
                # it, so leave the instance alone and report it
                log.error('FAIL %s: API error, check the instance by hand: %s',
                          server.id, e)
            if not args.keep_going:
                log.error('stopping after first failure (use -k to keep going)')
                break
        if args.pause and n < len(queue):
            time.sleep(args.pause)

    log.info('done: %d migrated, %d failed, %d skipped',
             len(done), len(failed), len(skipped))
    for s in failed:
        log.info('  failed:  %s (%s)', s.id, s.name)
    for s in skipped:
        log.info('  skipped: %s (%s, %s)', s.id, s.name, s.status)
    return 1 if failed else 0


if __name__ == '__main__':
    sys.exit(main())
