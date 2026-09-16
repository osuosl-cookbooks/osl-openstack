"""Unit tests for files/cold-migrate-host.py.

Run with: python3 -m unittest discover -s spec/python -v

openstacksdk is stubbed so the tests need nothing beyond the stdlib.
"""

import contextlib
import importlib.util
import io
import sys
import tempfile
import types
import unittest
from pathlib import Path
from unittest import mock

SCRIPT = Path(__file__).resolve().parents[2] / 'files' / 'cold-migrate-host.py'


def _stub_openstack():
    exc = types.ModuleType('openstack.exceptions')

    class SDKException(Exception):
        pass

    class HttpException(SDKException):
        pass

    class ResourceFailure(SDKException):
        pass

    class ResourceTimeout(SDKException):
        pass

    class ConfigException(SDKException):
        pass

    exc.SDKException = SDKException
    exc.HttpException = HttpException
    exc.ResourceFailure = ResourceFailure
    exc.ResourceTimeout = ResourceTimeout
    exc.ConfigException = ConfigException
    exc.raise_from_response = mock.Mock()
    pkg = types.ModuleType('openstack')
    pkg.exceptions = exc
    pkg.connect = mock.Mock()
    sys.modules['openstack'] = pkg
    sys.modules['openstack.exceptions'] = exc

    ks = types.ModuleType('keystoneauth1')
    ks_exc = types.ModuleType('keystoneauth1.exceptions')

    class ClientException(Exception):
        pass

    class MissingRequiredOptions(ClientException):
        pass

    class Unauthorized(ClientException):
        pass

    ks_exc.ClientException = ClientException
    ks_exc.MissingRequiredOptions = MissingRequiredOptions
    ks_exc.Unauthorized = Unauthorized
    ks.exceptions = ks_exc
    sys.modules['keystoneauth1'] = ks
    sys.modules['keystoneauth1.exceptions'] = ks_exc
    return pkg


OPENSTACK = _stub_openstack()
EXC = OPENSTACK.exceptions
KS_EXC = sys.modules['keystoneauth1.exceptions']
_spec = importlib.util.spec_from_file_location('cold_migrate_host', SCRIPT)
cmh = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(cmh)

UUID = '11111111-1111-1111-1111-111111111111'


def server(id=UUID, name='web 1', status='ACTIVE', host='src', task_state=None):
    return types.SimpleNamespace(id=id, name=name, status=status,
                                 compute_host=host, task_state=task_state)


def service(host, status='enabled', state='up'):
    return types.SimpleNamespace(host=host, binary='nova-compute',
                                 status=status, state=state)


def response(body):
    return types.SimpleNamespace(json=lambda: body)


def make_args(*extra, src='src', dst='dst'):
    with mock.patch.object(sys, 'argv', ['cold-migrate-host', src, dst, *extra]):
        return cmh.parse_args()


class Base(unittest.TestCase):
    def setUp(self):
        EXC.raise_from_response = mock.Mock()
        self.conn = mock.Mock()
        self.tmp = tempfile.TemporaryDirectory()
        self.log = str(Path(self.tmp.name) / 'test.log')
        # no real sleeping or clock in unit tests
        self.sleep = self.enter_patch(mock.patch.object(cmh.time, 'sleep'))
        self.clock = self.enter_patch(mock.patch.object(cmh.time, 'monotonic', return_value=0.0))

    def enter_patch(self, patcher):
        self.addCleanup(patcher.stop)
        return patcher.start()

    def tearDown(self):
        for handler in cmh.log.handlers:
            handler.close()
        cmh.log.handlers.clear()
        self.tmp.cleanup()

    def log_text(self):
        return Path(self.log).read_text()

    def set_fault(self, message):
        self.conn.compute.get.return_value = response({'server': {'fault': {'message': message}}})


class ParseArgsTest(Base):
    def test_defaults(self):
        a = make_args()
        self.assertEqual((a.src, a.dst, a.instances), ('src', 'dst', []))
        self.assertEqual((a.timeout, a.interval, a.pause), (1800, 10, 0))
        self.assertFalse(a.dry_run or a.keep_going or a.no_confirm)
        self.assertIsNone(a.log)

    def test_flags_and_uuids(self):
        a = make_args('-n', '-k', '-c', '-t', '60', '-i', '2', '-p', '5',
                      '-l', '/tmp/x.log', 'u1', 'u2')
        self.assertTrue(a.dry_run and a.keep_going and a.no_confirm)
        self.assertEqual((a.timeout, a.interval, a.pause), (60, 2, 5))
        self.assertEqual(a.log, '/tmp/x.log')
        self.assertEqual(a.instances, ['u1', 'u2'])


class HelpersTest(Base):
    def test_compute_service_found(self):
        self.conn.compute.services.return_value = iter([service('h1')])
        self.assertEqual(cmh.compute_service(self.conn, 'h1').host, 'h1')
        self.conn.compute.services.assert_called_once_with(binary='nova-compute', host='h1')

    def test_compute_service_missing(self):
        self.conn.compute.services.return_value = iter([])
        self.assertIsNone(cmh.compute_service(self.conn, 'nope'))

    def test_fault_message_reads_raw_server_body(self):
        self.set_fault('No valid host was found')
        self.assertEqual(cmh.fault_message(self.conn, UUID), 'No valid host was found')
        self.conn.compute.get.assert_called_once_with(f'/servers/{UUID}')

    def test_fault_message_without_fault(self):
        for body in ({'server': {}}, {'server': {'fault': {}}}, {'itemNotFound': {}}, []):
            self.conn.compute.get.return_value = response(body)
            self.assertEqual(cmh.fault_message(self.conn, UUID), 'no fault recorded')

    def test_fault_message_tolerates_api_errors(self):
        self.conn.compute.get.side_effect = EXC.HttpException('503')
        self.assertEqual(cmh.fault_message(self.conn, UUID), 'no fault recorded')
        self.conn.compute.get.side_effect = KS_EXC.ClientException('connection refused')
        self.assertEqual(cmh.fault_message(self.conn, UUID), 'no fault recorded')
        self.conn.compute.get.side_effect = None
        self.conn.compute.get.return_value = types.SimpleNamespace(
            json=mock.Mock(side_effect=ValueError('not json')))
        self.assertEqual(cmh.fault_message(self.conn, UUID), 'no fault recorded')


class WaitForTest(Base):
    def test_returns_once_status_reached(self):
        args = make_args('-i', '3')
        polls = [server(status='RESIZE', task_state='resize_prep'),
                 server(status='RESIZE', task_state='resize_migrating'),
                 server(status='VERIFY_RESIZE', host='dst')]
        self.conn.compute.get_server.side_effect = polls
        got = cmh.wait_for(self.conn, UUID, 'VERIFY_RESIZE', args, reverted_to='ACTIVE')
        self.assertIs(got, polls[-1])
        self.assertEqual(self.conn.compute.get_server.call_count, 3)
        self.assertEqual(self.sleep.call_args_list, [mock.call(3), mock.call(3)])

    def test_immediate_match_does_not_sleep(self):
        self.conn.compute.get_server.return_value = server(status='ACTIVE')
        cmh.wait_for(self.conn, UUID, 'ACTIVE', make_args())
        self.sleep.assert_not_called()

    def test_error_state_reports_fault(self):
        self.conn.compute.get_server.return_value = server(status='ERROR')
        self.set_fault('No valid host')
        with self.assertRaisesRegex(cmh.MigrationFailed, 'went to ERROR: No valid host'):
            cmh.wait_for(self.conn, UUID, 'VERIFY_RESIZE', make_args())

    def test_revert_to_original_status_is_a_failure(self):
        # nova's conductor puts the instance back to its old vm_state with no
        # task_state when the scheduler rejects the host, instead of ERROR
        self.conn.compute.get_server.side_effect = [
            server(status='RESIZE', task_state='resize_prep'),
            server(status='ACTIVE', task_state=None)]
        self.set_fault('No valid host was found. There are not enough hosts available.')
        with self.assertRaisesRegex(cmh.MigrationFailed,
                                    'nova reverted the migration: No valid host'):
            cmh.wait_for(self.conn, UUID, 'VERIFY_RESIZE', make_args(), reverted_to='ACTIVE')

    def test_original_status_with_task_state_keeps_waiting(self):
        # right after the request nova may still report ACTIVE + resize_prep
        self.conn.compute.get_server.side_effect = [
            server(status='ACTIVE', task_state='resize_prep'),
            server(status='VERIFY_RESIZE', host='dst')]
        got = cmh.wait_for(self.conn, UUID, 'VERIFY_RESIZE', make_args(), reverted_to='ACTIVE')
        self.assertEqual(got.status, 'VERIFY_RESIZE')

    def test_no_revert_check_without_reverted_to(self):
        self.conn.compute.get_server.side_effect = [
            server(status='VERIFY_RESIZE', task_state=None),
            server(status='ACTIVE', task_state=None)]
        got = cmh.wait_for(self.conn, UUID, 'ACTIVE', make_args())
        self.assertEqual(got.status, 'ACTIVE')

    def test_timeout_reports_current_status(self):
        args = make_args('-t', '5')
        self.conn.compute.get_server.return_value = server(status='RESIZE', task_state='resize_migrating')
        self.clock.side_effect = [0.0, 1.0, 6.0]  # deadline computed at 0, checks at 1 and 6
        with self.assertRaisesRegex(cmh.MigrationFailed, 'still RESIZE after 5s'):
            cmh.wait_for(self.conn, UUID, 'VERIFY_RESIZE', args)
        self.assertEqual(self.conn.compute.get_server.call_count, 2)


class ColdMigrateTest(Base):
    def test_posts_migrate_action_with_host_at_microversion_256(self):
        s = server(id='abc')
        resp = object()
        self.conn.compute.post.return_value = resp
        cmh.cold_migrate(self.conn, s, 'dst')
        self.conn.compute.post.assert_called_once_with(
            '/servers/abc/action', json={'migrate': {'host': 'dst'}}, microversion='2.56')
        EXC.raise_from_response.assert_called_once_with(
            resp, error_message='migrate request rejected')

    def test_http_error_propagates(self):
        EXC.raise_from_response.side_effect = EXC.HttpException('HTTP 409')
        with self.assertRaises(EXC.HttpException):
            cmh.cold_migrate(self.conn, server(), 'dst')


class MigrateOneTest(Base):
    def setUp(self):
        super().setUp()
        # bind the console handler to a throwaway stream so tests stay quiet
        with contextlib.redirect_stdout(io.StringIO()):
            cmh.setup_logging(self.log)

    def test_active_instance_round_trip(self):
        self.conn.compute.get_server.side_effect = [
            server(status='RESIZE', task_state='resize_migrating'),
            server(status='VERIFY_RESIZE', host='dst'),
            server(status='VERIFY_RESIZE', host='dst', task_state='resize_confirming'),
            server(status='ACTIVE', host='dst')]
        cmh.migrate_one(self.conn, server(), make_args(), '[1/1]')
        self.conn.compute.post.assert_called_once()
        self.conn.compute.confirm_server_resize.assert_called_once()
        self.assertEqual(self.conn.compute.get_server.call_count, 4)
        self.assertIn(f'OK   {UUID} on dst, ACTIVE', self.log_text())

    def test_shutoff_instance_returns_to_shutoff(self):
        self.conn.compute.get_server.side_effect = [
            server(status='VERIFY_RESIZE', host='dst'),
            server(status='ACTIVE', host='dst', task_state='resize_confirming'),
            server(status='SHUTOFF', host='dst')]
        cmh.migrate_one(self.conn, server(status='SHUTOFF'), make_args(), '[1/1]')
        self.assertIn(f'OK   {UUID} on dst, SHUTOFF', self.log_text())

    def test_no_confirm_leaves_verify_resize(self):
        self.conn.compute.get_server.return_value = server(status='VERIFY_RESIZE', host='dst')
        cmh.migrate_one(self.conn, server(), make_args('-c'), '[1/1]')
        self.conn.compute.confirm_server_resize.assert_not_called()
        self.assertEqual(self.conn.compute.get_server.call_count, 1)
        self.assertIn('left in VERIFY_RESIZE', self.log_text())

    def test_wrong_destination_is_not_confirmed(self):
        self.conn.compute.get_server.return_value = server(
            status='VERIFY_RESIZE', host='somewhere-else')
        with self.assertRaisesRegex(cmh.MigrationFailed, "landed on 'somewhere-else', not dst"):
            cmh.migrate_one(self.conn, server(), make_args(), '[1/1]')
        self.conn.compute.confirm_server_resize.assert_not_called()

    def test_rejected_migrate_request(self):
        EXC.raise_from_response.side_effect = EXC.HttpException('HTTP 409 conflict')
        with self.assertRaisesRegex(cmh.MigrationFailed, 'HTTP 409 conflict'):
            cmh.migrate_one(self.conn, server(), make_args(), '[1/1]')
        self.conn.compute.get_server.assert_not_called()

    def test_scheduler_rejection_reverts_and_fails_fast(self):
        self.conn.compute.get_server.side_effect = [
            server(status='RESIZE', task_state='resize_prep'),
            server(status='ACTIVE', task_state=None)]
        self.set_fault('No valid host was found')
        with self.assertRaisesRegex(cmh.MigrationFailed, 'reverted the migration: No valid host'):
            cmh.migrate_one(self.conn, server(), make_args(), '[1/1]')
        self.conn.compute.confirm_server_resize.assert_not_called()

    def test_rejected_confirm(self):
        self.conn.compute.get_server.return_value = server(status='VERIFY_RESIZE', host='dst')
        self.conn.compute.confirm_server_resize.side_effect = EXC.HttpException('nope')
        with self.assertRaisesRegex(cmh.MigrationFailed, 'resize confirm rejected.*VERIFY_RESIZE'):
            cmh.migrate_one(self.conn, server(), make_args(), '[1/1]')

    def test_error_during_migration(self):
        self.conn.compute.get_server.return_value = server(status='ERROR')
        self.set_fault('oops')
        with self.assertRaisesRegex(cmh.MigrationFailed, 'went to ERROR: oops'):
            cmh.migrate_one(self.conn, server(), make_args(), '[1/1]')
        self.conn.compute.confirm_server_resize.assert_not_called()


class MainTest(Base):
    """main() with the SDK connection mocked; migrate_one is exercised above."""

    def setUp(self):
        super().setUp()
        OPENSTACK.connect = mock.Mock(return_value=self.conn)
        self.services = {'src': service('src'), 'dst': service('dst'),
                         'down': service('down', state='down'),
                         'disabled': service('disabled', status='disabled')}
        self.conn.compute.services.side_effect = (
            lambda binary, host: iter([self.services[host]] if host in self.services else []))
        self.servers = [
            server(id='3333', name='bad'),
            server(id='2222', name='db-1', status='SHUTOFF'),
            server(id='4444', name='busy', status='RESIZE'),
            server(id='1111', name='web 1'),
        ]
        self.conn.compute.servers.return_value = list(self.servers)

    def run_main(self, *extra, src='src', dst='dst'):
        out = io.StringIO()
        with mock.patch.object(sys, 'argv',
                               ['cold-migrate-host', '-l', self.log, src, dst, *extra]), \
                contextlib.redirect_stdout(out):
            rc = cmh.main()
        return rc, out.getvalue()

    def assert_exits(self, pattern, *extra, **kw):
        with self.assertRaises(SystemExit) as cm, contextlib.redirect_stdout(io.StringIO()):
            self.run_main(*extra, **kw)
        self.assertRegex(str(cm.exception.code), pattern)

    def test_same_host_rejected_before_connecting(self):
        self.assert_exits('same', src='h', dst='h')
        OPENSTACK.connect.assert_not_called()

    def test_connect_failure_is_reported(self):
        OPENSTACK.connect.side_effect = EXC.ConfigException('Cloud envvars was not found')
        self.assert_exits('cannot talk to OpenStack.*Cloud envvars was not found')

    def test_missing_auth_options_is_reported(self):
        # keystoneauth, not the SDK, raises when the openrc is incomplete
        OPENSTACK.connect.side_effect = KS_EXC.MissingRequiredOptions(
            'Auth plugin requires parameters which were not given: auth_url')
        self.assert_exits('cannot talk to OpenStack.*auth_url')

    def test_bad_credentials_fail_on_first_call(self):
        self.conn.compute.services.side_effect = KS_EXC.Unauthorized('The request you have made requires authentication')
        self.assert_exits('cannot talk to OpenStack.*requires authentication')

    @mock.patch.object(cmh, 'migrate_one')
    def test_duplicate_uuids_migrate_once(self, migrate_one):
        rc, out = self.run_main('2222', '1111', '2222')
        self.assertEqual(rc, 0)
        self.assertEqual([c.args[1].id for c in migrate_one.call_args_list], ['2222', '1111'])
        self.assertIn('2 instance(s)', out)

    def test_missing_source_service(self):
        self.assert_exits('no nova-compute service registered for host ghost', src='ghost')

    def test_destination_must_be_enabled_and_up(self):
        self.assert_exits('enabled/down', dst='down')
        self.assert_exits('disabled/up', dst='disabled')

    def test_no_instances_on_source(self):
        self.conn.compute.servers.return_value = []
        self.assert_exits('no instances found on src')

    def test_requested_uuid_not_on_source(self):
        self.assert_exits('not on src: 9999, 8888', '1111', '9999', '8888')

    def test_nothing_migratable(self):
        self.conn.compute.servers.return_value = [server(id='4444', status='RESIZE')]
        self.assert_exits('nothing to migrate')

    @mock.patch.object(cmh, 'migrate_one')
    def test_dry_run_lists_plan_sorted_and_migrates_nothing(self, migrate_one):
        rc, out = self.run_main('-n')
        self.assertEqual(rc, 0)
        migrate_one.assert_not_called()
        self.conn.compute.servers.assert_called_once_with(
            details=True, all_projects=True, compute_host='src')
        lines = [line.split()[0] for line in out.splitlines()[1:]]
        self.assertEqual(lines, ['3333', '4444', '2222', '1111'])  # sorted by name
        self.assertIn('3 instance(s)', out)
        self.assertRegex(out, r'4444\s+RESIZE\s+busy  \(skipped: not ACTIVE/SHUTOFF\)')

    @mock.patch.object(cmh, 'migrate_one')
    def test_explicit_uuids_keep_given_order(self, migrate_one):
        rc, _ = self.run_main('1111', '2222')
        self.assertEqual(rc, 0)
        self.assertEqual([c.args[1].id for c in migrate_one.call_args_list], ['1111', '2222'])
        self.assertEqual(migrate_one.call_args_list[0].args[3], '[1/2]')

    @mock.patch.object(cmh, 'migrate_one')
    def test_stops_after_first_failure(self, migrate_one):
        migrate_one.side_effect = [cmh.MigrationFailed('bad news'), None, None]
        rc, _ = self.run_main()
        self.assertEqual(rc, 1)
        self.assertEqual(migrate_one.call_count, 1)
        text = self.log_text()
        self.assertIn('FAIL 3333: bad news', text)
        self.assertIn('stopping after first failure', text)
        self.assertIn('done: 0 migrated, 1 failed, 1 skipped', text)

    @mock.patch.object(cmh, 'migrate_one')
    def test_keep_going_migrates_the_rest(self, migrate_one):
        migrate_one.side_effect = [cmh.MigrationFailed('bad news'), None, None]
        rc, _ = self.run_main('-k')
        self.assertEqual(rc, 1)
        self.assertEqual(migrate_one.call_count, 3)
        text = self.log_text()
        self.assertIn('done: 2 migrated, 1 failed, 1 skipped', text)
        self.assertIn('failed:  3333 (bad)', text)
        self.assertIn('skipped: 4444 (busy, RESIZE)', text)

    @mock.patch.object(cmh, 'migrate_one')
    def test_api_error_mid_flight_is_a_failure_not_a_crash(self, migrate_one):
        migrate_one.side_effect = [EXC.HttpException('503 Service Unavailable'),
                                   KS_EXC.ClientException('connection reset'), None]
        rc, _ = self.run_main('-k')
        self.assertEqual(rc, 1)
        self.assertEqual(migrate_one.call_count, 3)
        text = self.log_text()
        self.assertIn('FAIL 3333: API error, check the instance by hand: 503', text)
        self.assertIn('FAIL 2222: API error, check the instance by hand: connection reset', text)
        self.assertIn('done: 1 migrated, 2 failed, 1 skipped', text)

    @mock.patch.object(cmh, 'migrate_one')
    def test_api_error_stops_without_keep_going(self, migrate_one):
        migrate_one.side_effect = EXC.HttpException('503')
        rc, _ = self.run_main()
        self.assertEqual(rc, 1)
        self.assertEqual(migrate_one.call_count, 1)
        self.assertIn('stopping after first failure', self.log_text())

    @mock.patch.object(cmh, 'migrate_one')
    def test_all_ok_exits_zero(self, migrate_one):
        rc, _ = self.run_main()
        self.assertEqual(rc, 0)
        self.assertIn('done: 3 migrated, 0 failed, 1 skipped', self.log_text())

    @mock.patch.object(cmh, 'migrate_one')
    def test_pause_between_instances_but_not_after_last(self, migrate_one):
        rc, _ = self.run_main('-p', '7')
        self.assertEqual(rc, 0)
        self.assertEqual(self.sleep.call_args_list, [mock.call(7), mock.call(7)])

    @mock.patch.object(cmh, 'migrate_one')
    def test_default_log_path(self, migrate_one):
        with mock.patch.object(cmh.logging, 'FileHandler') as fh, \
                mock.patch.object(sys, 'argv', ['x', '-n', 'src', 'dst']), \
                contextlib.redirect_stdout(io.StringIO()):
            fh.return_value = mock.Mock(level=0)
            cmh.main()
        self.assertRegex(fh.call_args.args[0], r'^/root/cold-migrate-src-dst-\d{8}-\d{6}\.log$')


if __name__ == '__main__':
    unittest.main()
