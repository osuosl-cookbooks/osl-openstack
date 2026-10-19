"""Unit tests for files/openstack-node-upgrade.py.

Run with: python3 -m unittest discover -s spec/python -v

rpm, dnf and psutil are stubbed in sys.modules, pymysql is patched onto the
module, commands go through a fake run() and every path points into a
tempdir, so the tests need only the stdlib and change nothing on the host.
"""

import configparser
import fcntl
import fnmatch
import importlib.util
import json
import os
import sys
import tempfile
import types
import unittest
from pathlib import Path
from unittest import mock

NAME, PROVIDENAME, FILENAMES = 1000, 1047, 5000


class FakeRpmDb:
    """The installed osuosl-openstack-* packages, as rpm headers keyed by tag."""

    def __init__(self):
        self.packages = []

    def install(self, name, release=None, files=()):
        provides = [name] + ([f'osuosl-openstack-release({release})'] if release else [])
        self.packages.append({NAME: name, PROVIDENAME: provides, FILENAMES: list(files)})

    def TransactionSet(self):
        db = self

        class Match:
            def __init__(self):
                self.headers = list(db.packages)

            def pattern(self, tag, mode, glob):
                assert (tag, mode) == ('name', 'glob')
                self.headers = [h for h in self.headers if fnmatch.fnmatch(h[NAME], glob)]

            def __iter__(self):
                return iter(self.headers)

        return types.SimpleNamespace(dbMatch=Match)


class FakeHistory:
    """dnf's history database: the newest transaction id, or None."""

    def __init__(self):
        self.tid = 41
        self.closed = 0

    def Base(self):
        hist = self

        class Base:
            history = types.SimpleNamespace(
                last=lambda: types.SimpleNamespace(tid=hist.tid) if hist.tid else None)

            def close(self):
                hist.closed += 1

        return Base()


RPMDB, HISTORY = FakeRpmDb(), FakeHistory()
PROCS = []
sys.modules['rpm'] = types.SimpleNamespace(
    TransactionSet=lambda: RPMDB.TransactionSet(), RPMMIRE_GLOB='glob',
    RPMTAG_NAME=NAME, RPMTAG_PROVIDENAME=PROVIDENAME, RPMTAG_FILENAMES=FILENAMES)
sys.modules['dnf'] = types.SimpleNamespace(Base=lambda: HISTORY.Base())


def process_iter(attrs):
    # Real psutil raises on an unknown attribute; a typo here must fail too
    assert sorted(attrs) == ['cmdline', 'name', 'pid', 'ppid'], attrs
    return [types.SimpleNamespace(info=dict(p)) for p in PROCS]


sys.modules['psutil'] = types.SimpleNamespace(process_iter=process_iter)

SCRIPT = Path(__file__).resolve().parents[2] / 'files' / 'openstack-node-upgrade.py'
_spec = importlib.util.spec_from_file_location('openstack_node_upgrade', SCRIPT)
nu = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(nu)
# Base patches nu.run; RunTest needs the real one
REAL_RUN = nu.run

REPO = """[OSL-openstack]
name=OSL-openstack
baseurl=https://ftp.osuosl.org/pub/osl/repos/yum/$releasever/openstack/{release}/$basearch/
enabled=1
gpgcheck=1
gpgkey=https://ftp.osuosl.org/pub/osl/repos/yum/RPM-GPG-KEY-osuosl
priority=10
"""


class FakeRun:
    """Stands in for run(): records each command; dnf upgrade adds a transaction."""

    def __init__(self, rcs=None):
        self.calls = []
        self.rcs = rcs
        self.on_upgrade = None
        self.upgrade_changes = True

    def __call__(self, cmd, check=True, capture=False, user=None, env=None):
        self.calls.append(cmd)
        out, rc = '', 0
        if cmd[:3] == ['dnf', 'history', 'info']:
            out = f'Transaction ID : {cmd[3]}\n'
        elif 'upgrade' in cmd and cmd[0] == 'dnf':
            if self.on_upgrade:
                self.on_upgrade()
            if self.upgrade_changes:
                HISTORY.tid += 1
        elif 'online_data_migrations' in cmd:
            rc = next(self.rcs)
        return types.SimpleNamespace(stdout=out, returncode=rc)


class FakeMySQL:
    """pymysql with canned rows per database name; records every connect."""

    class MySQLError(Exception):
        pass

    def __init__(self, rows):
        self.rows = rows
        self.connects = []

    def connect(self, **kw):
        self.connects.append(kw)
        rows = self.rows[kw['database']]
        cur = mock.MagicMock()
        cur.__enter__.return_value.fetchall.return_value = rows
        return mock.Mock(cursor=mock.Mock(return_value=cur))


class Base(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        root = Path(self.tmp.name)
        self.repos = root / 'yum.repos.d'
        self.state = root / 'state'
        for d in (self.repos, self.state):
            d.mkdir()
        self.release = root / 'release.json'
        self.cron = root / 'chef-client'
        self.lock = root / 'chef-client.lock'
        self.nova_conf = root / 'nova.conf'
        for name, value in (('REPO_DIR', self.repos), ('STATE_DIR', self.state), ('RELEASE_JSON', self.release),
                            ('CRON', self.cron), ('CHEF_LOCK', self.lock), ('NOVA_CONF', self.nova_conf)):
            self.patch(mock.patch.object(nu, name, str(value)))
        RPMDB.packages = []
        RPMDB.install('osuosl-openstack-nova-compute', 'yoga',
                      ['/usr/lib/systemd/system/openstack-nova-compute.service', '/opt/openstack/nova-compute/bin/nova'])
        RPMDB.install('osuosl-openstack-cli', 'yoga', ['/usr/lib/systemd/system/not-a-venv-unit.service'])
        RPMDB.install('osuosl-openstack-selinux')
        HISTORY.tid, HISTORY.closed = 41, 0
        PROCS[:] = []
        self.run = FakeRun()
        self.patch(mock.patch.object(nu, 'run', self.run))
        self.patch(mock.patch.object(nu.time, 'sleep'))
        self.write_release(installed='yoga', target='zed')

    def patch(self, patcher):
        self.addCleanup(patcher.stop)
        return patcher.start()

    def write_release(self, **state):
        self.release.write_text(json.dumps(state))

    def write_repo(self, release):
        (self.repos / 'OSL-openstack.repo').write_text(REPO.format(release=release))

    @property
    def rollback_repo(self):
        return self.repos / 'OSL-openstack-rollback.repo'


class RpmTest(Base):
    def test_markers_come_from_the_release_provides(self):
        self.assertEqual(nu.installed_markers(), ['yoga'])

    def test_mixed_markers_are_all_reported(self):
        RPMDB.install('osuosl-openstack-keystone', 'zed')
        self.assertEqual(nu.installed_markers(), ['yoga', 'zed'])

    def test_venv_packages_leave_out_cli_and_selinux(self):
        self.assertEqual(nu.venv_packages(), ['osuosl-openstack-nova-compute'])

    def test_units_are_the_venv_packages_service_files(self):
        self.assertEqual(nu.openstack_units(), ['openstack-nova-compute.service'])

    def test_no_venv_packages_means_no_units(self):
        RPMDB.packages = [p for p in RPMDB.packages if p[NAME] == 'osuosl-openstack-selinux']
        self.assertEqual(nu.openstack_units(), [])
        self.assertEqual(nu.installed_markers(), [])


class InstallTest(Base):
    def setUp(self):
        super().setUp()
        (self.state / 'staged-zed').touch()
        self.write_repo('yoga')

    def test_saves_the_running_repo_disabled_before_upgrading(self):
        seen = []
        self.run.on_upgrade = lambda: seen.append(self.rollback_repo.exists())
        nu.cmd_install(None)
        self.assertEqual(seen, [True])
        saved = configparser.ConfigParser(interpolation=None)
        saved.read(self.rollback_repo)
        repo = saved['OSL-openstack-rollback']
        self.assertEqual(repo['enabled'], '0')
        self.assertEqual(repo['name'], 'OSL-openstack (for undo)')
        self.assertIn('/openstack/yoga/', repo['baseurl'])
        self.assertEqual(repo['priority'], '10')
        self.assertEqual((self.state / 'upgrade-zed.txn').read_text(), '42\n')
        self.assertIn(['dnf', 'history', 'info', '42'], self.run.calls)
        self.assertIn(['dnf', 'clean', 'packages'], self.run.calls)
        self.assertEqual(HISTORY.closed, 2)

    def test_an_upgrade_that_changed_nothing_records_no_transaction(self):
        self.run.upgrade_changes = False
        with self.assertRaisesRegex(nu.UpgradeError, 'recorded no transaction'):
            nu.cmd_install(None)
        self.assertFalse((self.state / 'upgrade-zed.txn').exists())

    def test_an_installed_node_keeps_its_rollback_repo(self):
        RPMDB.packages = []
        RPMDB.install('osuosl-openstack-nova-compute', 'zed')
        self.write_repo('zed')
        self.rollback_repo.write_text('yoga, from the first install')
        nu.cmd_install(None)
        self.assertEqual(self.rollback_repo.read_text(), 'yoga, from the first install')
        self.assertFalse(any('upgrade' in c for c in self.run.calls))

    def test_refuses_a_repo_for_another_release(self):
        self.write_repo('zed')
        with self.assertRaisesRegex(nu.UpgradeError, 'not the installed yoga'):
            nu.cmd_install(None)
        self.assertFalse(self.rollback_repo.exists())
        self.assertFalse(any('upgrade' in c for c in self.run.calls))

    def test_refuses_an_unstaged_release(self):
        (self.state / 'staged-zed').unlink()
        with self.assertRaisesRegex(nu.UpgradeError, 'not staged'):
            nu.cmd_install(None)
        self.assertFalse(self.rollback_repo.exists())


class UndoTest(Base):
    def setUp(self):
        super().setUp()
        (self.state / 'upgrade-zed.txn').write_text('42\n')

    def test_undoes_from_the_rollback_repo(self):
        self.rollback_repo.write_text('[OSL-openstack-rollback]\n')
        nu.cmd_undo(None)
        self.assertIn(['dnf', '-y', '--enablerepo=OSL-openstack-rollback', 'history', 'undo', '42'], self.run.calls)
        self.assertTrue((self.state / 'upgrade-zed.txn.undone').exists())

    def test_refuses_without_the_rollback_repo(self):
        with self.assertRaisesRegex(nu.UpgradeError, 'no OSL-openstack-rollback repo'):
            nu.cmd_undo(None)
        self.assertEqual(self.run.calls, [])


class StopTest(Base):
    def setUp(self):
        super().setUp()
        self.write_release(installed='yoga', target='zed', node_type='compute')
        self.kills = []
        self.patch(mock.patch.object(nu.os, 'kill', lambda pid, sig: self.kills.append(pid)))
        self.cron.write_text('cron')

    def add_proc(self, pid, name, ppid, cmdline):
        PROCS.append({'pid': pid, 'ppid': ppid, 'name': name, 'cmdline': cmdline})

    def stopped(self):
        return ['systemctl', 'stop', 'openstack-nova-compute.service'] in self.run.calls

    def test_kills_only_the_cron_sleeper_shell_first(self):
        self.add_proc(100, 'sh', 1, ['/bin/sh', '-c', f'/bin/sleep 300; /usr/bin/flock -n {self.lock} cinc-client'])
        self.add_proc(101, 'sleep', 100, ['/bin/sleep', '300'])
        self.add_proc(199, 'bash', 1, ['bash'])
        self.add_proc(200, 'sleep', 199, ['sleep', '60'])
        # psutil gives None for a process it may not read
        self.add_proc(300, 'sh', 1, None)
        self.add_proc(301, 'sleep', 300, None)
        nu.cmd_stop(None)
        # Once before taking the lock and once after
        self.assertEqual(self.kills, [100, 101, 100, 101])
        self.assertFalse(self.cron.exists())
        self.assertTrue(self.stopped())

    def test_stops_nothing_while_a_converge_holds_the_lock(self):
        fd = os.open(self.lock, os.O_RDWR | os.O_CREAT)
        self.addCleanup(os.close, fd)
        fcntl.flock(fd, fcntl.LOCK_EX)
        clock = iter([0.0, 10.0, nu.CHEF_LOCK_WAIT + 1.0])
        with mock.patch.object(nu.time, 'monotonic', lambda: next(clock)):
            with self.assertRaisesRegex(nu.UpgradeError, 'nothing was stopped'):
                nu.cmd_stop(None)
        self.assertFalse(self.stopped())

    def test_removes_the_cron_the_converge_put_back(self):
        real_hold = nu.hold_chef_lock

        def converge_finishes():
            self.cron.write_text('restored by the converge')
            return real_hold()

        with mock.patch.object(nu, 'hold_chef_lock', converge_finishes):
            nu.cmd_stop(None)
        self.assertFalse(self.cron.exists())
        self.assertTrue(self.stopped())

    def test_releases_the_lock_when_done(self):
        nu.cmd_stop(None)
        fd = os.open(self.lock, os.O_RDWR)
        self.addCleanup(os.close, fd)
        fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)


class RunTest(Base):
    def test_a_missing_binary_is_a_clean_error(self):
        missing = str(Path(self.tmp.name) / 'missing')
        with self.assertRaisesRegex(nu.UpgradeError, f'{missing} is not installed'):
            REAL_RUN([missing])


class NovaDBTest(Base):
    API = 'mysql+pymysql://nova:p%40ss@db:3306/nova_api'

    def setUp(self):
        super().setUp()
        conf = Path(self.tmp.name) / 'keystone.conf'
        conf.write_text('[database]\nconnection = mysql+pymysql://ks:pw@db:3306/keystone_x86\n')
        self.patch(mock.patch.object(nu, 'DB_OPTIONS', [(str(conf), 'database', 'connection')]))
        self.write_release(installed='yoga', target='zed', db_node=True)
        self.mysql = FakeMySQL({
            'nova_api': [('cell0', 'mysql+pymysql://n:pw@db:3306/nova_cell0'), ('cell1', '{scheme}://{hostname}/x')],
            'nova_cell0': [],
            'nova': [('old-hv.example.org', 56)],
        })
        self.patch(mock.patch.object(nu, 'pymysql', self.mysql))

    def write_nova_conf(self):
        self.nova_conf.write_text(f'[api_database]\nconnection = {self.API}\n'
                                  '[database]\nconnection = mysql+pymysql://n:pw@db:3306/nova\n')

    def test_cells_come_from_the_api_database(self):
        self.write_nova_conf()
        self.assertEqual(nu.nova_cell_urls(), {
            'cell0': 'mysql+pymysql://n:pw@db:3306/nova_cell0',
            'cell1': 'mysql+pymysql://n:pw@db:3306/nova',
        })
        # The password is unquoted for the driver
        self.assertEqual(self.mysql.connects[0]['password'], 'p@ss')

    def test_old_computes_are_listed_per_cell(self):
        self.write_nova_conf()
        old = nu.old_computes(nu.nova_cell_urls())
        self.assertEqual(old, [('cell1', 'old-hv.example.org', 56)])

    def test_backup_skips_the_cells_without_nova(self):
        self.assertEqual(list(nu.service_db_urls()), ['keystone_x86'])
        self.assertEqual(self.mysql.connects, [])

    def test_backup_adds_the_cells_with_nova(self):
        self.write_nova_conf()
        self.assertEqual(sorted(nu.service_db_urls()), ['keystone_x86', 'nova', 'nova_cell0'])

    def test_precheck_refuses_without_nova(self):
        with self.assertRaisesRegex(nu.UpgradeError, 'precheck needs .*nova.conf; nova is not configured'):
            nu.cmd_precheck(None)
        self.assertEqual(self.run.calls, [])

    def test_a_missing_pymysql_is_a_clean_error(self):
        self.write_nova_conf()
        with mock.patch.object(nu, 'pymysql', None):
            with self.assertRaisesRegex(nu.UpgradeError, 'python3-PyMySQL is not installed'):
                nu.cmd_precheck(None)

    def test_a_failed_connect_names_the_database(self):
        self.write_nova_conf()
        self.mysql.connect = mock.Mock(side_effect=FakeMySQL.MySQLError('Access denied'))
        with self.assertRaisesRegex(nu.UpgradeError, 'cannot connect to db/nova_api: Access denied'):
            nu.nova_cell_urls()


class DbUrlTest(Base):
    def test_raw_password_characters_survive(self):
        u = nu.parse_db_url('mysql+pymysql://nova:a/b#c?d@db.example.org:3307/nova_api?charset=utf8')
        self.assertEqual(u, {'host': 'db.example.org', 'port': 3307, 'user': 'nova',
                             'password': 'a/b#c?d', 'database': 'nova_api'})

    def test_encoded_password_and_default_port(self):
        u = nu.parse_db_url('mysql+pymysql://n:p%40ss@db/nova')
        self.assertEqual((u['password'], u['port']), ('p@ss', 3306))

    def test_ipv6_host(self):
        self.assertEqual(nu.parse_db_url('mysql+pymysql://n:pw@[fd00::1]:3307/x')['host'], 'fd00::1')

    def test_a_templated_url_is_not_a_database(self):
        self.assertIsNone(nu.parse_db_url('{scheme}://{username}:{password}@{hostname}/{path}'))

    def test_option_file_quotes_what_mysql_would_cut(self):
        path, db = nu.mysql_conf('mysql+pymysql://ks:a#b c;d\\e"q@db:3306/keystone', self.tmp.name)
        lines = Path(path).read_text().splitlines()
        self.assertEqual(db, 'keystone')
        self.assertIn('user="ks"', lines)
        # Escaped as MySQL 8 reads it back: \\ for a backslash, \" for a quote
        self.assertIn('password="a#b c;d\\\\e\\"q"', lines)
        self.assertEqual(os.stat(path).st_mode & 0o777, 0o600)


class MigrationsTest(Base):
    def test_stops_at_the_batch_cap(self):
        self.run.rcs = iter([1] * (nu.MAX_MIGRATION_BATCHES + 1) + [RuntimeError('no cap')])
        with self.assertRaisesRegex(nu.UpgradeError, 'still reports work'):
            nu.run_migrations('nova-manage', 'nova')

    def test_fails_on_errors(self):
        self.run.rcs = iter([1, 2])
        with self.assertRaisesRegex(nu.UpgradeError, 'exited 2'):
            nu.run_migrations('nova-manage', 'nova')

    def test_runs_until_done(self):
        self.run.rcs = iter([1, 1, 0])
        nu.run_migrations('nova-manage', 'nova')
        self.assertEqual(sum('online_data_migrations' in c for c in self.run.calls), 3)


if __name__ == '__main__':
    unittest.main()
