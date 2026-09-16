"""Unit tests for files/resize-debris-check.py.

Run with: python3 -m unittest discover -s spec/python -v

openstacksdk, keystoneauth1 and pymysql are stubbed; subprocess and
shutil.which are patched, so nothing here touches a real cloud.
"""

import contextlib
import datetime
import importlib.util
import io
import os
import shutil
import sys
import tempfile
import types
import unittest
from pathlib import Path
from unittest import mock

SCRIPT = Path(__file__).resolve().parents[2] / 'files' / 'resize-debris-check.py'


def _stub_modules():
    exc = types.ModuleType('openstack.exceptions')

    class SDKException(Exception):
        pass

    class HttpException(SDKException):
        pass

    exc.SDKException, exc.HttpException = SDKException, HttpException
    exc.raise_from_response = mock.Mock()
    pkg = types.ModuleType('openstack')
    pkg.exceptions, pkg.connect = exc, mock.Mock()
    sys.modules['openstack'], sys.modules['openstack.exceptions'] = pkg, exc

    ks = types.ModuleType('keystoneauth1')
    ks_exc = types.ModuleType('keystoneauth1.exceptions')

    class ClientException(Exception):
        pass

    ks_exc.ClientException = ClientException
    ks.exceptions = ks_exc
    sys.modules['keystoneauth1'], sys.modules['keystoneauth1.exceptions'] = ks, ks_exc

    pm = types.ModuleType('pymysql')

    class MySQLError(Exception):
        pass

    pm.MySQLError, pm.connect = MySQLError, mock.Mock()
    sys.modules['pymysql'] = pm
    return pkg, ks_exc, pm


OPENSTACK, KS_EXC, PYMYSQL = _stub_modules()
EXC = OPENSTACK.exceptions
_spec = importlib.util.spec_from_file_location('resize_debris_check', SCRIPT)
rdc = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(rdc)

NOW = datetime.datetime(2026, 9, 16, 12, 0, 0, tzinfo=datetime.timezone.utc)


def ago(**kw):
    return (NOW - datetime.timedelta(**kw)).strftime('%Y-%m-%dT%H:%M:%SZ')


def server(id, name='vm', updated_at=None):
    return types.SimpleNamespace(id=id, name=name, updated_at=updated_at)


def vol(id, name='vol', status='attaching', updated_at=None, attachments=None, **extra):
    d = {'id': id, 'name': name, 'status': status, 'updated_at': updated_at,
         'attachments': attachments or []}
    d.update(extra)
    return d


def response(body):
    return types.SimpleNamespace(json=lambda: body)


class Base(unittest.TestCase):
    def setUp(self):
        EXC.raise_from_response = mock.Mock()
        self.out = io.StringIO()
        self.rep = rdc.Report(out=self.out)
        self.conn = mock.Mock()
        self.conn.compute.servers.return_value = []
        self.conn.block_storage.get.return_value = response({'volumes': []})
        self.db = mock.Mock(spec=rdc.NovaDB)
        self.db.available = True
        self.db.cli.return_value = 'MYSQL_PWD=... mysql -h dbhost -P 3306 -u nova nova_cell'
        self.db.query.return_value = []
        self.args = self.make_args()
        self.ctx = rdc.Context(self.args, self.conn, self.db)
        self.ctx.now = NOW
        self.which = self.enter_patch(mock.patch.object(rdc.shutil, 'which', return_value='/usr/bin/x'))
        self.run = self.enter_patch(mock.patch.object(rdc, 'run', return_value=(0, '')))

    def enter_patch(self, patcher):
        self.addCleanup(patcher.stop)
        return patcher.start()

    @staticmethod
    def make_args(*extra):
        with mock.patch.object(sys, 'argv', ['resize-debris-check', *extra]), \
                mock.patch.dict(os.environ, {}, clear=True):
            return rdc.parse_args()

    def text(self):
        return self.out.getvalue()


class ParseArgsTest(Base):
    def test_defaults(self):
        a = self.make_args()
        self.assertEqual((a.rbd_pool, a.nova_conf), ('vms', '/etc/nova/nova.conf'))
        self.assertEqual((a.stale_hours, a.verify_days, a.error_days), (1, 2, 7))
        self.assertFalse(a.exit_code)

    def test_flags(self):
        a = self.make_args('--rbd-pool', 'p', '--stale-hours', '3', '--verify-days', '9',
                           '--error-days', '30', '--nova-conf', '/x', '-x')
        self.assertEqual((a.rbd_pool, a.nova_conf), ('p', '/x'))
        self.assertEqual((a.stale_hours, a.verify_days, a.error_days), (3, 9, 30))
        self.assertTrue(a.exit_code)

    def test_env_defaults_like_the_shell_version(self):
        with mock.patch.dict(os.environ, {'RBD_POOL': 'other', 'STALE_HOURS': '4',
                                          'VERIFY_DAYS': '1', 'ERROR_DAYS': '2'}), \
                mock.patch.object(sys, 'argv', ['x']):
            a = rdc.parse_args()
        self.assertEqual((a.rbd_pool, a.stale_hours, a.verify_days, a.error_days),
                         ('other', 4, 1, 2))


class TimestampTest(Base):
    def test_formats(self):
        for s in ('2026-09-16T10:00:00Z', '2026-09-16T10:00:00.123456Z',
                  '2026-09-16T10:00:00', '2026-09-16T10:00:00.000001'):
            t = rdc.parse_timestamp(s)
            self.assertEqual((t.year, t.hour, t.tzinfo), (2026, 10, datetime.timezone.utc), s)

    def test_garbage(self):
        for s in (None, '', 'yesterday', '2026-09-16'):
            self.assertIsNone(rdc.parse_timestamp(s), s)


class NovaDBTest(Base):
    def write_conf(self, body):
        d = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, d)
        p = Path(d) / 'nova.conf'
        p.write_text(body)
        return str(p)

    def test_parses_connection_url(self):
        conf = self.write_conf('[DEFAULT]\nfoo=bar\n[database]\n'
                               'connection = mysql+pymysql://nova:p%40ss@db.example:3307/nova_x86?charset=utf8\n')
        db = rdc.NovaDB(conf)
        self.assertEqual(db.params, {'host': 'db.example', 'port': 3307, 'user': 'nova',
                                     'password': 'p@ss', 'database': 'nova_x86'})
        self.assertTrue(db.available)
        self.assertIn('nova_x86 on db.example:3307 as nova', db.describe())
        self.assertEqual(db.cli(), 'MYSQL_PWD=... mysql -h db.example -P 3307 -u nova nova_x86')
        self.assertNotIn('p@ss', db.cli())

    def test_default_port_and_interpolation_safe(self):
        conf = self.write_conf('[database]\nconnection = mysql+pymysql://u:100%25@h/d\n')
        db = rdc.NovaDB(conf)
        self.assertEqual((db.params['port'], db.params['password']), (3306, '100%'))

    def test_tolerates_oslo_style_duplicate_keys_and_percent_values(self):
        conf = self.write_conf('[DEFAULT]\nforce_raw_images = true\nforce_raw_images = false\n'
                               'log_format = %(asctime)s\n'
                               '[database]\nconnection = mysql+pymysql://u:p@h/d\n')
        self.assertTrue(rdc.NovaDB(conf).available)

    def test_missing_conf_or_section(self):
        self.assertFalse(rdc.NovaDB('/nonexistent/nova.conf').available)
        self.assertFalse(rdc.NovaDB(self.write_conf('[DEFAULT]\n')).available)
        self.assertIn('no [database] connection', rdc.NovaDB(self.write_conf('[DEFAULT]\n')).describe())

    def test_missing_pymysql(self):
        conf = self.write_conf('[database]\nconnection = mysql+pymysql://u:p@h/d\n')
        with mock.patch.object(rdc, 'pymysql', None):
            db = rdc.NovaDB(conf)
            self.assertFalse(db.available)
            self.assertIn('pymysql module missing', db.describe())

    def test_query_uses_params_and_closes(self):
        conf = self.write_conf('[database]\nconnection = mysql+pymysql://u:p@h/d\n')
        db = rdc.NovaDB(conf)
        cur = mock.MagicMock()
        cur.fetchall.return_value = [('row',)]
        connection = mock.Mock()
        connection.cursor.return_value.__enter__ = mock.Mock(return_value=cur)
        connection.cursor.return_value.__exit__ = mock.Mock(return_value=False)
        PYMYSQL.connect.return_value = connection
        self.assertEqual(db.query('SELECT %s', (1,)), [('row',)])
        PYMYSQL.connect.assert_called_once_with(connect_timeout=10, host='h', port=3306,
                                                user='u', password='p', database='d')
        cur.execute.assert_called_once_with('SELECT %s', (1,))
        connection.close.assert_called_once()


class ListVolumesTest(Base):
    def test_query_params_and_pagination(self):
        page1 = {'volumes': [vol('v1')],
                 'volumes_links': [{'rel': 'next', 'href': 'http://c/v3/volumes/detail?marker=v1'}]}
        page2 = {'volumes': [vol('v2')]}
        self.conn.block_storage.get.side_effect = [response(page1), response(page2)]
        got = rdc.list_volumes(self.conn, 'attaching')
        self.assertEqual([v['id'] for v in got], ['v1', 'v2'])
        calls = self.conn.block_storage.get.call_args_list
        self.assertEqual(calls[0], mock.call('/volumes/detail',
                                             params={'all_tenants': 'True', 'status': 'attaching'}))
        self.assertEqual(calls[1], mock.call('http://c/v3/volumes/detail?marker=v1', params=None))
        self.assertEqual(EXC.raise_from_response.call_count, 2)

    def test_http_error_propagates(self):
        EXC.raise_from_response.side_effect = EXC.HttpException('403')
        with self.assertRaises(EXC.HttpException):
            rdc.list_volumes(self.conn, 'attaching')


class ResizingTest(Base):
    def test_collects_both_states_and_keeps_verify_resize_servers(self):
        vr = [server('aaaa', 'a'), server('bbbb', 'b')]
        self.conn.compute.servers.side_effect = [vr, [server('cccc')]]
        rdc.check_resizing(self.ctx, self.rep)
        self.assertEqual(self.ctx.resizing, {'aaaa', 'bbbb', 'cccc'})
        self.assertIs(self.ctx.verify_resize, self.ctx.verify_resize)
        self.assertEqual([s.id for s in self.ctx.verify_resize], ['aaaa', 'bbbb'])
        self.assertEqual(self.conn.compute.servers.call_args_list, [
            mock.call(details=True, all_projects=True, status='VERIFY_RESIZE'),
            mock.call(details=False, all_projects=True, status='RESIZE')])
        self.assertIn('aaaa\nbbbb\ncccc', self.text())

    def test_none(self):
        rdc.check_resizing(self.ctx, self.rep)
        self.assertIn('none', self.text())


class RbdSnapsTest(Base):
    LS = ('NAME                                                 SIZE   PARENT  FMT  PROT  LOCK\n'
          '11111111-1111-1111-1111-111111111111_disk            20 GiB          2       excl\n'
          '11111111-1111-1111-1111-111111111111_disk@nova-resize 20 GiB          2  yes\n'
          '22222222-2222-2222-2222-222222222222_disk@nova-resize 20 GiB          2  yes\n'
          '33333333-3333-3333-3333-333333333333_disk@snapshot-x  20 GiB          2  yes\n')

    def test_stale_vs_legit(self):
        self.run.return_value = (0, self.LS)
        self.ctx.resizing = {'22222222-2222-2222-2222-222222222222'}
        rdc.check_rbd_snaps(self.ctx, self.rep)
        self.run.assert_called_once_with(['rbd', '-p', 'vms', 'ls', '-l'])
        self.assertEqual(self.rep.findings, 1)
        t = self.text()
        self.assertIn('FINDING: stale nova-resize snap on 11111111-1111-1111-1111-111111111111', t)
        self.assertIn('fix> rbd snap rm vms/11111111-1111-1111-1111-111111111111_disk@nova-resize', t)
        self.assertIn('ok: 22222222-2222-2222-2222-222222222222 has a snap but is mid-resize', t)
        self.assertNotIn('33333333', t)

    def test_rbd_missing_or_failing(self):
        self.which.return_value = None
        rdc.check_rbd_snaps(self.ctx, self.rep)
        self.assertIn('skipped: rbd not available', self.text())
        self.which.return_value = '/usr/bin/rbd'
        self.run.return_value = (1, 'error connecting to the cluster')
        rdc.check_rbd_snaps(self.ctx, self.rep)
        self.assertIn('skipped: rbd ls failed (rc=1): error connecting', self.text())
        self.assertEqual(self.rep.findings, 0)


class MigrationContextTest(Base):
    def test_finding_with_sql_fix(self):
        self.db.query.return_value = [('u-1', 'web1', 'active', '4918')]
        rdc.check_migration_context(self.ctx, self.rep)
        self.assertEqual(self.rep.findings, 1)
        t = self.text()
        self.assertIn('FINDING: u-1 (web1, active) holds migration_context for migration 4918', t)
        self.assertIn("UPDATE instance_extra SET migration_context = NULL WHERE instance_uuid = 'u-1';", t)
        sql = self.db.query.call_args.args[0]
        self.assertIn("i.vm_state NOT IN ('resized')", sql)
        self.assertIn('i.task_state IS NULL', sql)

    def test_skipped_without_db(self):
        self.db.available = False
        rdc.check_migration_context(self.ctx, self.rep)
        self.assertIn('skipped: no DB access', self.text())
        self.db.query.assert_not_called()


class StuckVolumesTest(Base):
    def volumes_by_state(self, mapping):
        def get(url, params=None):
            return response({'volumes': mapping.get(params['status'], [])})
        self.conn.block_storage.get.side_effect = get

    def test_queries_every_transient_state(self):
        rdc.check_stuck_volumes(self.ctx, self.rep)
        states = [c.kwargs['params']['status'] for c in self.conn.block_storage.get.call_args_list]
        self.assertEqual(tuple(states), rdc.STUCK_VOLUME_STATES)

    def test_age_threshold_and_suggestions(self):
        self.volumes_by_state({
            'attaching': [vol('fresh', updated_at=ago(minutes=20)),
                          vol('old-empty', 'swap', updated_at=ago(hours=5)),
                          vol('old-attached', updated_at=ago(hours=70),
                              attachments=[{'server_id': 's'}])],
            'deleting': [vol('del', status='deleting', updated_at=ago(days=3))],
        })
        rdc.check_stuck_volumes(self.ctx, self.rep)
        self.assertEqual(self.rep.findings, 3)
        t = self.text()
        self.assertNotIn('fresh', t)
        self.assertIn("FINDING: volume old-empty (swap) stuck in 'attaching' for 5h, attachments: empty", t)
        self.assertIn('fix> openstack volume set --state available old-empty', t)
        self.assertIn("stuck in 'attaching' for 70h, attachments: present", t)
        self.assertIn('fix> openstack volume set --state in-use old-attached   # attachments exist', t)
        self.assertIn('fix> openstack volume set --state error del && openstack volume delete del', t)
        self.assertIn('then reconcile with: openstack server volume list <owner-instance>', t)

    def test_falls_back_to_created_at_and_flags_unparsable(self):
        self.volumes_by_state({
            'reserved': [vol('c', status='reserved', updated_at=None, created_at=ago(hours=2)),
                         vol('bad', status='reserved', updated_at='???')]})
        rdc.check_stuck_volumes(self.ctx, self.rep)
        self.assertEqual(self.rep.findings, 1)
        self.assertIn("volume c (vol) stuck in 'reserved' for 2h", self.text())
        self.assertIn("note: volume bad in 'reserved' has no parsable timestamp", self.text())

    def test_custom_threshold(self):
        self.ctx.args = self.make_args('--stale-hours', '6')
        self.volumes_by_state({'attaching': [vol('v', updated_at=ago(hours=5))]})
        rdc.check_stuck_volumes(self.ctx, self.rep)
        self.assertEqual(self.rep.findings, 0)

    def test_cinder_unavailable_skips_section_only(self):
        self.conn.block_storage.get.side_effect = EXC.SDKException(
            'Could not find requested endpoint in Service Catalog.')
        rdc.check_stuck_volumes(self.ctx, self.rep)
        self.assertEqual(self.rep.findings, 0)
        self.assertIn('skipped: block storage API unavailable: Could not find', self.text())
        self.assertEqual(self.conn.block_storage.get.call_count, 1)


class ParkedVerifyResizeTest(Base):
    def test_threshold(self):
        self.ctx.verify_resize = [server('new', 'n', ago(hours=30)),
                                  server('old', 'opf3', ago(days=95)),
                                  server('odd', 'o', None)]
        rdc.check_parked_verify_resize(self.ctx, self.rep)
        self.assertEqual(self.rep.findings, 1)
        t = self.text()
        self.assertIn('FINDING: opf3 (old) unconfirmed for 95d', t)
        self.assertIn("fix> openstack server resize confirm old   # (or 'resize revert')", t)
        self.assertNotIn('resize confirm new', t)
        self.assertIn('note: o (odd) has no parsable updated timestamp', t)


class DeadMigrationsTest(Base):
    def test_finding(self):
        self.db.query.return_value = [(9028, 'u-9', 'confirming', 'oprod6', 'oprod3', '2024-11-01 10:00:00')]
        rdc.check_dead_migrations(self.ctx, self.rep)
        self.assertEqual(self.rep.findings, 1)
        t = self.text()
        self.assertIn("FINDING: migration 9028 (u-9) stuck in 'confirming' since 2024-11-01 10:00:00 (oprod6 -> oprod3)", t)
        self.assertIn("UPDATE migrations SET status='error' WHERE id=9028 AND status='confirming';", t)
        self.assertIn("status 'finished' = awaiting confirm", t)
        sql, params = self.db.query.call_args.args
        self.assertEqual(params, rdc.LIVE_MIGRATION_STATES)
        self.assertEqual(sql.count('%s'), len(rdc.LIVE_MIGRATION_STATES))
        # nova stores naive UTC; NOW() would drift with the DB server's zone
        self.assertIn('UTC_TIMESTAMP() - INTERVAL 1 DAY', sql)
        self.assertNotIn('NOW()', sql)

    def test_skipped_without_db(self):
        self.db.available = False
        rdc.check_dead_migrations(self.ctx, self.rep)
        self.assertIn('skipped: no DB access', self.text())


class ErroredMigrationsTest(Base):
    def test_error_instance_is_finding_others_are_notes(self):
        self.db.query.return_value = [
            (1, 'u-err', 'migration', 'error', 'a', 'b', 'error', '2026-09-15 01:00:00'),
            (2, 'u-ok', 'resize', 'error', 'a', 'b', 'active', '2026-09-14 01:00:00'),
            (3, 'u-lm', 'live-migration', 'failed', 'a', 'b', 'active', '2026-09-13 01:00:00')]
        self.ctx.args = self.make_args('--error-days', '3')
        rdc.check_errored_migrations(self.ctx, self.rep)
        self.assertEqual(self.rep.findings, 1)
        t = self.text()
        self.assertIn('FINDING: migration migration 1 of u-err error 2026-09-15 01:00:00 AND instance is still in ERROR', t)
        self.assertIn('fix> recover: openstack server reboot --hard u-err', t)
        self.assertIn('note: resize migration 2 of u-ok error 2026-09-14 01:00:00 (instance now active)', t)
        self.assertIn('note: live-migration migration 3 of u-lm failed 2026-09-13 01:00:00 (instance now active)', t)
        sql, params = self.db.query.call_args.args
        # both terminal failure statuses, then the day window, all parameterised
        self.assertEqual(params, ('error', 'failed', 3))
        self.assertIn('m.status IN (%s, %s)', sql)
        self.assertIn('UTC_TIMESTAMP() - INTERVAL %s DAY', sql)
        self.assertNotIn('NOW()', sql)

    def test_live_states_cover_every_in_progress_status(self):
        # nova Yoga: live migrations accepted->queued->preparing->running,
        # cold/resize pre-migrating->migrating->post-migrating->confirming/reverting
        for st in ('accepted', 'queued', 'preparing', 'running', 'pre-migrating',
                   'migrating', 'post-migrating', 'confirming', 'reverting'):
            self.assertIn(st, rdc.LIVE_MIGRATION_STATES)
        for st in ('finished', 'completed', 'confirmed', 'reverted', 'error', 'failed',
                   'cancelled', 'done'):
            self.assertNotIn(st, rdc.LIVE_MIGRATION_STATES)


class PlacementTest(Base):
    AUDIT = ('WARNING:root:eventlet monkey patching\n'
             'Allocations were found for a non-existing consumer x on RP r; can be deleted\n'
             'Allocations were found for consumer y on RP r; can be deleted\n'
             'Processed 2 allocations.\n')

    def test_orphans(self):
        self.run.return_value = (3, self.AUDIT)
        rdc.check_placement(self.ctx, self.rep)
        self.run.assert_called_once_with(['nova-manage', 'placement', 'audit', '--verbose'])
        self.assertEqual(self.rep.findings, 1)
        t = self.text()
        self.assertIn('FINDING: 2 orphaned placement allocation(s)', t)
        self.assertIn('fix> or bulk:  nova-manage placement audit --delete', t)
        self.assertIn('consumer y', t)
        self.assertNotIn('eventlet monkey patching', t)

    def test_clean_shows_tail_only(self):
        self.run.return_value = (0, 'l1\nl2\nl3\nl4\nl5\nl6\nl7\n')
        rdc.check_placement(self.ctx, self.rep)
        self.assertEqual(self.rep.findings, 0)
        self.assertNotIn('l2\n', self.text())
        self.assertIn('l3\nl4\nl5\nl6\nl7', self.text())

    def test_missing_nova_manage(self):
        self.which.return_value = None
        rdc.check_placement(self.ctx, self.rep)
        self.assertIn('skipped: nova-manage not available', self.text())
        self.run.assert_not_called()

    def test_audit_error_codes_skip_with_output(self):
        for rc in (1, 127):
            self.run.return_value = (rc, 'x\nsomething went wrong\n')
            rdc.check_placement(self.ctx, self.rep)
        self.assertEqual(self.rep.findings, 0)
        self.assertIn('skipped: nova-manage placement audit failed (rc=1):', self.text())
        self.assertIn('skipped: nova-manage placement audit failed (rc=127):', self.text())
        self.assertIn('something went wrong', self.text())

    def test_exit_code_3_counts_even_if_wording_changes(self):
        self.run.return_value = (3, 'Allocations for consumer x on RP r look orphaned\n')
        rdc.check_placement(self.ctx, self.rep)
        self.assertEqual(self.rep.findings, 1)
        self.assertIn('FINDING: 1 orphaned placement allocation(s)', self.text())


class MainTest(Base):
    def setUp(self):
        super().setUp()
        OPENSTACK.connect = mock.Mock(return_value=self.conn)
        self.dbcls = self.enter_patch(mock.patch.object(rdc, 'NovaDB', return_value=self.db))
        self.db.describe.return_value = 'nova_cell on dbhost:3306 as nova'
        self.which.return_value = None  # no rbd / nova-manage on the test box

    def run_main(self, *extra):
        out = io.StringIO()
        with mock.patch.object(sys, 'argv', ['resize-debris-check', *extra]), \
                mock.patch.dict(os.environ, {}, clear=True), contextlib.redirect_stdout(out):
            rc = rdc.main()
        return rc, out.getvalue()

    def test_clean_run(self):
        rc, out = self.run_main()
        self.assertEqual(rc, 0)
        self.assertIn('nova DB: nova_cell on dbhost:3306 as nova (from /etc/nova/nova.conf)', out)
        for n in range(1, 8):
            self.assertIn(f'=== {n}. ', out)
        self.assertIn('No resize/migration debris found.', out)

    def test_findings_and_exit_code_flag(self):
        self.db.query.side_effect = lambda sql, params=(): (
            [('u-1', 'h', 'active', '1')] if 'instance_extra' in sql else [])
        rc, out = self.run_main()
        self.assertEqual(rc, 0)
        self.assertIn('1 finding(s) above. Also run on each hypervisor:', out)
        self.assertIn('ls -d /var/lib/nova/instances/*_resize', out)
        rc, _ = self.run_main('-x')
        self.assertEqual(rc, 2)

    def test_db_unavailable_is_reported_once(self):
        self.db.available = False
        self.db.describe.return_value = 'unavailable (python3 pymysql module missing)'
        rc, out = self.run_main()
        self.assertEqual(rc, 0)
        self.assertIn('nova DB: unavailable (python3 pymysql module missing), DB checks will be skipped', out)
        self.assertEqual(out.count('skipped: no DB access'), 3)

    def test_api_error_exits_cleanly(self):
        self.conn.compute.servers.side_effect = KS_EXC.ClientException('requires authentication')
        with self.assertRaises(SystemExit) as cm, contextlib.redirect_stdout(io.StringIO()):
            self.run_main()
        self.assertIn('OpenStack API error', str(cm.exception.code))

    def test_db_error_exits_cleanly(self):
        self.db.query.side_effect = PYMYSQL.MySQLError("Access denied for user 'nova'")
        with self.assertRaises(SystemExit) as cm, contextlib.redirect_stdout(io.StringIO()):
            self.run_main()
        self.assertIn("nova DB query failed: Access denied", str(cm.exception.code))


if __name__ == '__main__':
    unittest.main()
