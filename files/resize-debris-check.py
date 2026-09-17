#!/usr/bin/env python3
"""Read-only sweep for leftover state from failed or unfinished nova resizes
and migrations (the c24a44da incident taxonomy):

  1. stale nova-resize RBD snapshots         -> next resize fails ImageExists
  2. stale migration_context on instances    -> resource tracker kills new migrations
  3. cinder volumes stuck in transient state -> resize can't reserve volumes
  4. instances parked in VERIFY_RESIZE       -> double allocations, future leaks
  5. dead in-progress migration records
  6. recently errored migrations (debris signal; instance may need recovery)
  7. placement allocation orphans (via nova-manage)
  8. cinder volumes carrying more than one attachment

Reports findings with suggested fix commands and changes nothing by default.
--dry-run previews the fixes it could apply, --fix applies them. Only pure
leftover state is ever touched: stale snapshots, stale rows, dead records and
orphaned allocations. Anything involving a live instance or volume stays
advisory.
Run on a controller with admin OpenStack credentials sourced. RBD checks
need ceph admin access. DB checks read the connection URL from nova.conf's
[database] section and need the pymysql module.
"""

import argparse
import configparser
import datetime
import os
import shutil
import subprocess
import sys
import urllib.parse

import openstack
from keystoneauth1 import exceptions as ks_exc
from openstack import exceptions as os_exc

try:
    import pymysql
    DB_ERRORS = (pymysql.MySQLError,)
except ImportError:  # DB checks are skipped without it
    pymysql = None
    DB_ERRORS = ()

STUCK_VOLUME_STATES = ('attaching', 'detaching', 'reserved', 'creating', 'deleting',
                       'error_deleting', 'maintenance', 'downloading')
# Every non-terminal migration.status nova sets: live migrations go
# accepted -> queued -> preparing -> running, cold/resize go pre-migrating ->
# migrating -> post-migrating -> finished -> confirming/reverting.
LIVE_MIGRATION_STATES = ('accepted', 'queued', 'preparing', 'running', 'pre-migrating',
                         'migrating', 'post-migrating', 'confirming', 'reverting')
# Terminal failure statuses: 'error' for cold/resize and conductor failures,
# 'failed' for live migrations rolled back on the compute side.
FAILED_MIGRATION_STATES = ('error', 'failed')
ATTACHMENT_MICROVERSION = '3.27'
TIMESTAMP_FORMATS = ('%Y-%m-%dT%H:%M:%SZ', '%Y-%m-%dT%H:%M:%S.%fZ',
                     '%Y-%m-%dT%H:%M:%S', '%Y-%m-%dT%H:%M:%S.%f')


def parse_args(argv=None):
    env = os.environ.get
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--rbd-pool', default=None,
                    help='RBD pool holding instance disks '
                         '(default: [libvirt] images_rbd_pool from nova.conf, else vms)')
    ap.add_argument('--ceph-user', default=None, metavar='NAME',
                    help='Ceph client to run rbd as, without the "client." prefix '
                         '(default: [libvirt] rbd_user from nova.conf, else cinder)')
    ap.add_argument('--nova-conf', default=env('NOVA_CONF', '/etc/nova/nova.conf'),
                    help='nova.conf to read the [database] and [libvirt] sections from')
    ap.add_argument('--stale-hours', type=int, default=int(env('STALE_HOURS', 1)),
                    help='min age before a transient volume state counts as stuck (default 1)')
    ap.add_argument('--verify-days', type=int, default=int(env('VERIFY_DAYS', 2)),
                    help='min age before VERIFY_RESIZE counts as parked (default 2)')
    ap.add_argument('--error-days', type=int, default=int(env('ERROR_DAYS', 7)),
                    help='how far back to surface errored migrations (default 7)')
    ap.add_argument('-x', '--exit-code', action='store_true',
                    help='exit 2 when there are findings (for cron/NRPE)')
    ap.add_argument('-n', '--dry-run', action='store_true',
                    help='show exactly what --fix would do, without doing it')
    ap.add_argument('--fix', action='store_true',
                    help='apply the safe fixes: stale nova-resize snapshots, stale '
                         'migration_context rows, dead migration records and placement '
                         'orphans. Stuck volumes, parked resizes and ERROR instances are '
                         'never touched.')
    args = ap.parse_args(argv)
    # controllers have no client.admin keyring, so take the pool and client
    # nova itself uses rather than rbd's admin defaults
    libvirt = libvirt_settings(args.nova_conf)
    if args.rbd_pool is None:
        args.rbd_pool = env('RBD_POOL') or libvirt.get('pool') or 'vms'
    if args.ceph_user is None:
        args.ceph_user = env('CEPH_USER') or libvirt.get('user') or 'cinder'
    return args


def parse_timestamp(value):
    """ISO timestamp as the OpenStack APIs return it -> aware UTC datetime, or None."""
    if not value:
        return None
    for fmt in TIMESTAMP_FORMATS:
        try:
            return datetime.datetime.strptime(value, fmt).replace(tzinfo=datetime.timezone.utc)
        except ValueError:
            continue
    return None


def libvirt_settings(nova_conf):
    """rbd_user and images_rbd_pool from nova.conf's [libvirt] section."""
    cfg = configparser.ConfigParser(interpolation=None, strict=False)
    try:
        if not cfg.read(nova_conf):
            return {}
    except configparser.Error:
        return {}
    return {'user': cfg.get('libvirt', 'rbd_user', fallback=None),
            'pool': cfg.get('libvirt', 'images_rbd_pool', fallback=None)}


def ceph_keyring_users(ceph_dir='/etc/ceph'):
    """Client names this host holds a keyring for, e.g. ['cinder', 'glance']."""
    prefix, suffix = 'ceph.client.', '.keyring'
    try:
        names = os.listdir(ceph_dir)
    except OSError:
        return []
    return sorted(n[len(prefix):-len(suffix)] for n in names
                  if n.startswith(prefix) and n.endswith(suffix))


class Report:
    """Collects findings and prints them as it goes, like the shell version."""

    def __init__(self, out=None):
        self.findings = 0
        self.fixes = 0
        self.fix_failures = 0
        self.out = out or sys.stdout

    def section(self, title):
        print(f'\n=== {title} ===', file=self.out)

    def finding(self, msg):
        self.findings += 1
        print(f'FINDING: {msg}', file=self.out)

    def suggest(self, cmd):
        print(f'  fix> {cmd}', file=self.out)

    def note(self, msg):
        print(msg, file=self.out)

    def would(self, cmd):
        print(f'  would run> {cmd}', file=self.out)

    def fixed(self, msg):
        self.fixes += 1
        print(f'  FIXED: {msg}', file=self.out)

    def fix_failed(self, msg):
        self.fix_failures += 1
        print(f'  FIX FAILED: {msg}', file=self.out)


class NovaDB:
    """Read-only access to the nova cell DB named in nova.conf.

    nova stores naive UTC timestamps, so age windows compare against
    UTC_TIMESTAMP() rather than NOW(), which follows the DB server's zone.
    """

    def __init__(self, nova_conf):
        self.params = self._parse(nova_conf)

    @staticmethod
    def _parse(nova_conf):
        # oslo.config tolerates repeated keys and % in values; so must we
        cfg = configparser.ConfigParser(interpolation=None, strict=False)
        if not cfg.read(nova_conf):
            return None
        url = cfg.get('database', 'connection', fallback=None)
        if not url:
            return None
        p = urllib.parse.urlsplit(url)  # mysql+pymysql://user:pass@host:port/db?charset=...
        if not p.hostname:
            return None
        return {'host': p.hostname, 'port': p.port or 3306,
                'user': urllib.parse.unquote(p.username or ''),
                'password': urllib.parse.unquote(p.password or ''),
                'database': p.path.lstrip('/').split('?')[0]}

    @property
    def available(self):
        return bool(self.params) and pymysql is not None

    def describe(self):
        if not self.params:
            return 'unavailable (no [database] connection in nova.conf)'
        if pymysql is None:
            return 'unavailable (python3 pymysql module missing)'
        p = self.params
        return f"{p['database']} on {p['host']}:{p['port']} as {p['user']}"

    def cli(self):
        """Printable mysql command for fix suggestions (password kept out of argv)."""
        p = self.params
        return f"MYSQL_PWD=... mysql -h {p['host']} -P {p['port']} -u {p['user']} {p['database']}"

    def execute(self, sql, params=()):
        """Run a write, return the number of rows it changed."""
        conn = pymysql.connect(connect_timeout=10, **self.params)
        try:
            with conn.cursor() as cur:
                changed = cur.execute(sql, params)
            conn.commit()
            return changed
        finally:
            conn.close()

    def query(self, sql, params=()):
        conn = pymysql.connect(connect_timeout=10, **self.params)
        try:
            with conn.cursor() as cur:
                cur.execute(sql, params)
                return cur.fetchall()
        finally:
            conn.close()


def run(cmd):
    """Run a command, return (rc, combined output)."""
    proc = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                          universal_newlines=True)
    return proc.returncode, proc.stdout


def run_fix(ctx, rep, cmd, what, ok_codes=(0,)):
    """Run a shell fix, or print it under --dry-run."""
    printable = ' '.join(cmd)
    if not ctx.applying:
        rep.would(printable)
        return
    rc, out = run(cmd)
    if rc in ok_codes:
        rep.fixed(what)
    else:
        rep.fix_failed(f'{printable} (rc={rc}): {out.strip()}')


def sql_fix(ctx, rep, sql, params, printable, what):
    """Apply a DB fix, or print it under --dry-run.

    Every statement repeats the scan's own guards in its WHERE clause, so an
    instance that started moving since the scan simply matches no rows.
    """
    if not ctx.applying:
        rep.would(printable)
        return
    try:
        changed = ctx.db.execute(sql, params)
    except DB_ERRORS as e:
        rep.fix_failed(f'{what}: {e}')
        return
    if changed:
        rep.fixed(f'{what} ({changed} row)')
    else:
        rep.fix_failed(f'{what}: matched no rows, the state changed since the scan')


def paginated(conn, url, params, key, microversion=None):
    """Follow cinder's pagination links and return every item.

    Raw dicts because the SDK models at the version RDO ships are missing
    fields we need, such as a volume's updated_at.
    """
    items = []
    while url:
        kwargs = {'params': params}
        if microversion:
            kwargs['microversion'] = microversion
        resp = conn.block_storage.get(url, **kwargs)
        os_exc.raise_from_response(resp, error_message=f'{key} list failed')
        body = resp.json()
        items.extend(body.get(key, []))
        nxt = [l['href'] for l in body.get(f'{key}_links', []) if l.get('rel') == 'next']
        url, params = (nxt[0], None) if nxt else (None, None)
    return items


def list_volumes(conn, status):
    return paginated(conn, '/volumes/detail',
                     {'all_tenants': 'True', 'status': status}, 'volumes')


def list_attachments(conn):
    # /attachments arrived in microversion 3.27
    return paginated(conn, '/attachments/detail', {'all_tenants': 'True'},
                     'attachments', microversion=ATTACHMENT_MICROVERSION)


def get_volume(conn, volume_id):
    resp = conn.block_storage.get(f'/volumes/{volume_id}')
    os_exc.raise_from_response(resp, error_message='volume fetch failed')
    return resp.json().get('volume', {})


def nova_attachment_ids(db):
    """volume_id -> the attachment id nova actually uses, from its BDMs."""
    rows = db.query('SELECT volume_id, attachment_id FROM block_device_mapping '
                    'WHERE deleted = 0 AND attachment_id IS NOT NULL')
    return {volume_id: attachment_id for volume_id, attachment_id in rows}


# ------------------------------------------------------------------ checks

def check_resizing(ctx, rep):
    rep.section('Instances currently mid-resize (context for later checks)')
    ctx.verify_resize = list(ctx.conn.compute.servers(
        details=True, all_projects=True, status='VERIFY_RESIZE'))
    ctx.resizing = {s.id for s in ctx.verify_resize}
    ctx.resizing.update(s.id for s in ctx.conn.compute.servers(
        details=False, all_projects=True, status='RESIZE'))
    rep.note('\n'.join(sorted(ctx.resizing)) if ctx.resizing else 'none')


def check_rbd_snaps(ctx, rep):
    pool, user = ctx.args.rbd_pool, ctx.args.ceph_user
    rep.section(f'1. Stale nova-resize RBD snapshots (pool: {pool}, client.{user})')
    if not shutil.which('rbd'):
        rep.note('skipped: rbd not available on this host')
        return
    rc, out = run(['rbd', '--id', user, '-p', pool, 'ls', '-l'])
    if rc != 0:
        rep.note(f'skipped: rbd ls failed (rc={rc}): {out.strip()}')
        have = ceph_keyring_users()
        if have and user not in have:
            rep.note(f'  no keyring for client.{user}; this host has: {", ".join(have)}')
            rep.note(f'  re-run with --ceph-user {have[0]}')
        return
    for line in out.splitlines():
        name = line.split()[0] if line.split() else ''
        if not name.endswith('_disk@nova-resize'):
            continue
        uuid = name[:-len('_disk@nova-resize')]
        if uuid in ctx.resizing:
            rep.note(f'ok: {uuid} has a snap but is mid-resize (legit)')
        else:
            rep.finding(f'stale nova-resize snap on {uuid}')
            cmd = ['rbd', '--id', user, 'snap', 'rm', f'{pool}/{uuid}_disk@nova-resize']
            if ctx.fixing:
                run_fix(ctx, rep, cmd, f'removed the nova-resize snap on {uuid}')
            else:
                rep.suggest(' '.join(cmd))


def check_migration_context(ctx, rep):
    rep.section('2. Instances carrying a migration_context while not mid-move')
    # vm_state 'resized' (VERIFY_RESIZE) legitimately holds one; so does any
    # instance with a task_state set. Anything else is debris that gets new
    # migrations killed by the resource tracker.
    if not ctx.db.available:
        rep.note('skipped: no DB access')
        return
    rows = ctx.db.query("""
        SELECT i.uuid, i.hostname, i.vm_state,
               JSON_UNQUOTE(JSON_EXTRACT(ie.migration_context,
                 '$."nova_object.data".migration_id'))
          FROM instance_extra ie
          JOIN instances i ON i.uuid = ie.instance_uuid
         WHERE ie.migration_context IS NOT NULL
           AND i.deleted = 0
           AND i.task_state IS NULL
           AND i.vm_state NOT IN ('resized')""")
    for uuid, hostname, vm_state, mig_id in rows:
        rep.finding(f'{uuid} ({hostname}, {vm_state}) holds migration_context '
                    f'for migration {mig_id}')
        printable = (f'{ctx.db.cli()} -e "UPDATE instance_extra SET migration_context = NULL '
                     f"WHERE instance_uuid = '{uuid}';\"")
        if ctx.fixing:
            # the join repeats the scan's guards, so an instance that started
            # moving in the meantime matches nothing
            sql_fix(ctx, rep,
                    'UPDATE instance_extra ie JOIN instances i ON i.uuid = ie.instance_uuid '
                    'SET ie.migration_context = NULL '
                    'WHERE ie.instance_uuid = %s AND i.deleted = 0 AND i.task_state IS NULL '
                    "AND i.vm_state NOT IN ('resized')",
                    (uuid,), printable, f'cleared the migration_context on {uuid}')
        else:
            rep.suggest('verify no migration in flight, then:')
            rep.suggest(printable)


def check_stuck_volumes(ctx, rep):
    rep.section(f'3. Cinder volumes stuck in transient states > {ctx.args.stale_hours}h')
    for state in STUCK_VOLUME_STATES:
        try:
            volumes = list_volumes(ctx.conn, state)
        except (os_exc.SDKException, ks_exc.ClientException) as e:
            # no cinder in the catalog, or it is down: not a reason to lose
            # the rest of the audit
            rep.note(f'skipped: block storage API unavailable: {e}')
            return
        for vol in volumes:
            vid, vname, vstatus = vol.get('id'), vol.get('name'), vol.get('status')
            updated = parse_timestamp(vol.get('updated_at')) or parse_timestamp(vol.get('created_at'))
            if updated is None:
                rep.note(f'note: volume {vid} in {vstatus!r} has no parsable timestamp; check by hand')
                continue
            age_h = int((ctx.now - updated).total_seconds() // 3600)
            if age_h < ctx.args.stale_hours:
                continue
            attach = 'present' if vol.get('attachments') else 'empty'
            rep.finding(f"volume {vid} ({vname}) stuck in '{vstatus}' for {age_h}h, "
                        f'attachments: {attach}')
            if vstatus in ('deleting', 'error_deleting'):
                rep.suggest(f'openstack volume set --state error {vid} && '
                            f'openstack volume delete {vid}   # was mid-delete; retry it')
            else:
                if attach == 'empty':
                    rep.suggest(f'openstack volume set --state available {vid}')
                else:
                    rep.suggest(f'openstack volume set --state in-use {vid}   '
                                '# attachments exist; verify guest first')
                rep.suggest('then reconcile with: openstack server volume list <owner-instance>')


def check_parked_verify_resize(ctx, rep):
    rep.section(f'4. Instances parked in VERIFY_RESIZE > {ctx.args.verify_days}d')
    for s in ctx.verify_resize:
        updated = parse_timestamp(s.updated_at)
        if updated is None:
            rep.note(f'note: {s.name} ({s.id}) has no parsable updated timestamp; check by hand')
            continue
        age_d = int((ctx.now - updated).total_seconds() // 86400)
        if age_d >= ctx.args.verify_days:
            rep.finding(f'{s.name} ({s.id}) unconfirmed for {age_d}d, '
                        'double allocations, leak risk')
            rep.suggest(f"openstack server resize confirm {s.id}   # (or 'resize revert')")


def check_dead_migrations(ctx, rep):
    rep.section('5. Migration records in live states with no recent activity (>1d)')
    if not ctx.db.available:
        rep.note('skipped: no DB access')
        return
    placeholders = ', '.join(['%s'] * len(LIVE_MIGRATION_STATES))
    rows = ctx.db.query(f"""
        SELECT id, instance_uuid, status, source_compute, dest_compute, updated_at
          FROM migrations
         WHERE deleted = 0
           AND status IN ({placeholders})
           AND updated_at < UTC_TIMESTAMP() - INTERVAL 1 DAY""", LIVE_MIGRATION_STATES)
    for mid, uuid, mstatus, src, dst, upd in rows:
        rep.finding(f"migration {mid} ({uuid}) stuck in '{mstatus}' since {upd} ({src} -> {dst})")
        printable = (f"{ctx.db.cli()} -e \"UPDATE migrations SET status='error' "
                     f"WHERE id={mid} AND status='{mstatus}';\"")
        if ctx.fixing:
            sql_fix(ctx, rep,
                    "UPDATE migrations SET status='error' "
                    'WHERE id = %s AND status = %s AND deleted = 0 '
                    'AND updated_at < UTC_TIMESTAMP() - INTERVAL 1 DAY',
                    (mid, mstatus), printable, f'marked migration record {mid} dead')
        else:
            rep.suggest('verify the instance is healthy and NOT actually moving, '
                        'then mark the record dead:')
            rep.suggest(printable)
    rep.note("(note: status 'finished' = awaiting confirm; covered by check 4)")


def check_errored_migrations(ctx, rep):
    rep.section(f'6. Migrations that errored in the last {ctx.args.error_days}d')
    # An error record is terminal and harmless by itself, but a recent one is
    # the strongest signal that debris exists for that instance, and if the
    # instance is still in ERROR it needs recovery now.
    if not ctx.db.available:
        rep.note('skipped: no DB access')
        return
    placeholders = ', '.join(['%s'] * len(FAILED_MIGRATION_STATES))
    rows = ctx.db.query(f"""
        SELECT m.id, m.instance_uuid, m.migration_type, m.status,
               m.source_compute, m.dest_compute, i.vm_state, m.updated_at
          FROM migrations m
          JOIN instances i ON i.uuid = m.instance_uuid
         WHERE m.deleted = 0 AND i.deleted = 0
           AND m.status IN ({placeholders})
           AND m.updated_at > UTC_TIMESTAMP() - INTERVAL %s DAY""",
        FAILED_MIGRATION_STATES + (ctx.args.error_days,))
    for mid, uuid, mtype, mstatus, src, dst, vm_state, upd in rows:
        if vm_state == 'error':
            rep.finding(f'{mtype} record {mid} for {uuid} {mstatus} {upd} '
                        'AND instance is still in ERROR')
            rep.suggest(f'recover: openstack server reboot --hard {uuid}   '
                        '# (or reset-state --active, stop, start)')
            rep.suggest('then check this instance against sections 1-3 before retrying the move')
        else:
            rep.note(f'note: {mtype} record {mid} for {uuid} {mstatus} {upd} '
                     f'(instance now {vm_state}), cross-check sections 1-3 for its debris')


def check_duplicate_attachments(ctx, rep):
    rep.section('8. Cinder volumes carrying more than one attachment')
    # a volume can sit healthily in 'in-use' with a leftover attachment, which
    # section 3 cannot see; cinder then refuses the next cold migration with
    # "duplicate connectors detected"
    try:
        attachments = list_attachments(ctx.conn)
    except (os_exc.SDKException, ks_exc.ClientException) as e:
        rep.note(f'skipped: could not list attachments: {e}')
        return
    by_volume = {}
    for attachment in attachments:
        by_volume.setdefault(attachment.get('volume_id'), []).append(attachment)
    suspects = sorted(v for v, rows in by_volume.items() if v and len(rows) > 1)
    if not suspects:
        return

    live = {}
    if ctx.db.available:
        try:
            live = nova_attachment_ids(ctx.db)
        except DB_ERRORS as e:
            rep.note(f'note: could not read nova BDMs, cannot tell which is live: {e}')
    else:
        rep.note('note: no DB access, so which attachment nova uses is unknown')

    for volume_id in suspects:
        rows = by_volume[volume_id]
        try:
            volume = get_volume(ctx.conn, volume_id)
        except (os_exc.SDKException, ks_exc.ClientException) as e:
            rep.note(f'note: could not fetch volume {volume_id}: {e}')
            continue
        if volume.get('multiattach'):
            continue  # many attachments are the whole point of a multiattach volume
        status = volume.get('status')
        keep = live.get(volume_id)
        keep_row = next((a for a in rows if a.get('id') == keep), None)
        serving = [a for a in rows if a.get('status') == 'attached']
        # a reserved attachment carries no connection info, so it cannot be the
        # one serving a running disk. nova pointing at one while another is
        # attached means the two sides disagree, and neither is safe to delete.
        disagree = bool(keep_row and keep_row.get('status') != 'attached' and serving)

        if keep_row is None:
            rep.finding(f'volume {volume_id} ({status}) has {len(rows)} attachments and nova '
                        'has no BDM for it')
        elif disagree:
            rep.finding(f'volume {volume_id} ({status}) has {len(rows)} attachments and nova '
                        f"points at a {keep_row.get('status')} one; do NOT delete anything here")
        else:
            orphans = [a for a in rows if a.get('id') != keep]
            rep.finding(f'volume {volume_id} ({status}) has {len(rows)} attachments, '
                        f'{len(orphans)} orphaned; the next cold migration of it will fail')

        for attachment in rows:
            if attachment.get('id') == keep:
                role = "nova's BDM points here"
            elif attachment.get('status') == 'attached':
                role = 'carries the live connection'
            else:
                role = 'orphan' if keep_row else 'unverified'
            rep.note(f"    {attachment.get('id')}  {attachment.get('status')}  "
                     f"instance={attachment.get('instance')}  {role}")

        if keep_row is None:
            rep.suggest('confirm the volume is unused before deleting any attachment')
        elif disagree:
            rep.suggest('nova and cinder disagree, so deleting either one risks detaching a '
                        'live disk. Repair it instead, with the instance stopped:')
            rep.suggest('nova-manage volume_attachment get_connector   # on the compute host')
            rep.suggest(f"nova-manage volume_attachment refresh {keep_row.get('instance')} "
                        f'{volume_id} <connector.json>')
        else:
            for attachment in rows:
                if attachment.get('id') != keep:
                    rep.suggest(f'openstack --os-volume-api-version {ATTACHMENT_MICROVERSION} '
                                f"volume attachment delete {attachment.get('id')}")


def check_placement(ctx, rep):
    rep.section('7. Placement allocation audit')
    if not shutil.which('nova-manage'):
        rep.note('skipped: nova-manage not available on this host')
        return
    # nova-manage return codes: 0 clean, 3 orphans found, 1 unexpected
    # error, 127 placement not reachable
    rc, out = run(['nova-manage', 'placement', 'audit', '--verbose'])
    lines = [l for l in out.splitlines() if 'eventlet monkey patching' not in l]
    if rc not in (0, 3):
        rep.note(f'skipped: nova-manage placement audit failed (rc={rc}):')
        rep.note('\n'.join(lines[-5:]))
        return
    orphans = sum('can be deleted' in l for l in lines)
    if rc == 3 and not orphans:  # message wording changed; trust the exit code
        orphans = 1
    # show everything when there are orphans, else just the tail
    rep.note('\n'.join(lines if orphans else lines[-5:]))
    if orphans:
        rep.finding(f'{orphans} orphaned placement allocation(s), details above')
        if ctx.fixing:
            # audit --delete exits 4 when it deleted something, 0 when clean
            run_fix(ctx, rep, ['nova-manage', 'placement', 'audit', '--delete'],
                    f'deleted {orphans} orphaned placement allocation(s)', ok_codes=(0, 4))
        else:
            rep.suggest('targeted: openstack resource provider allocation delete <consumer-uuid>'
                        '   # needs osc-placement plugin')
            rep.suggest('or bulk:  nova-manage placement audit --delete')


CHECKS = (check_resizing, check_rbd_snaps, check_migration_context, check_stuck_volumes,
          check_parked_verify_resize, check_dead_migrations, check_errored_migrations,
          check_placement, check_duplicate_attachments)


class Context:
    def __init__(self, args, conn, db):
        self.args, self.conn, self.db = args, conn, db
        self.fixing = args.fix or args.dry_run
        self.applying = args.fix and not args.dry_run
        self.now = datetime.datetime.now(datetime.timezone.utc)
        self.verify_resize = []
        self.resizing = set()


def main(argv=None):
    args = parse_args(argv)
    rep = Report()
    db = NovaDB(args.nova_conf)
    rep.note(f'nova DB: {db.describe()} (from {args.nova_conf})'
             if db.available else f'nova DB: {db.describe()}, DB checks will be skipped')
    try:
        conn = openstack.connect()
        ctx = Context(args, conn, db)
        for check in CHECKS:
            check(ctx, rep)
    except (os_exc.SDKException, ks_exc.ClientException) as e:
        sys.exit(f'OpenStack API error (is an admin openrc sourced?): {e}')
    except DB_ERRORS as e:
        sys.exit(f'nova DB query failed: {e}')

    rep.section('Summary')
    if rep.findings == 0:
        rep.note('No resize/migration debris found.')
    else:
        rep.note(f'{rep.findings} finding(s) above. Also run on each hypervisor:')
        rep.note('  ls -d /var/lib/nova/instances/*_resize   # leftover source dirs')
    if args.dry_run:
        rep.note('Dry run: nothing was changed. Re-run with --fix to apply.')
    elif args.fix:
        rep.note(f'{rep.fixes} fix(es) applied, {rep.fix_failures} failed.')
    if rep.fix_failures:
        return 1
    return 2 if args.exit_code and rep.findings else 0


if __name__ == '__main__':
    sys.exit(main())
