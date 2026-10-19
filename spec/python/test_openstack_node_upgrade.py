"""Unit tests for files/openstack-node-upgrade.py.

Run with: python3 -m unittest discover -s spec/python -v

Commands go through a fake run() and every path points into a tempdir, so
the tests need nothing beyond the stdlib and change nothing on the host.
"""

import configparser
import fcntl
import importlib.util
import json
import os
import tempfile
import types
import unittest
from pathlib import Path
from unittest import mock

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
    """Stands in for run(): records each command and answers the few that are read."""

    def __init__(self, markers=('yoga',), rcs=None):
        self.calls = []
        self.markers = list(markers)
        self.rcs = rcs
        self.on_upgrade = None

    def __call__(self, cmd, check=True, capture=False, user=None, env=None):
        self.calls.append(cmd)
        out, rc = '', 0
        if cmd[:2] == ['rpm', '-qa']:
            out = ''.join(f'osuosl-openstack-release({m})\n' for m in self.markers)
        elif cmd[:4] == ['dnf', 'history', 'info', 'last']:
            out = 'Transaction ID : 42\nCommand Line   : upgrade osuosl-openstack-*\n'
        elif 'upgrade' in cmd and self.on_upgrade:
            self.on_upgrade()
        elif 'online_data_migrations' in cmd:
            rc = next(self.rcs)
        return types.SimpleNamespace(stdout=out, returncode=rc)


class Base(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        root = Path(self.tmp.name)
        self.repos = root / 'yum.repos.d'
        self.state = root / 'state'
        self.proc = root / 'proc'
        for d in (self.repos, self.state, self.proc):
            d.mkdir()
        self.release = root / 'release.json'
        self.cron = root / 'chef-client'
        self.lock = root / 'chef-client.lock'
        for name, value in (('REPO_DIR', self.repos), ('STATE_DIR', self.state), ('PROC', self.proc),
                            ('RELEASE_JSON', self.release), ('CRON', self.cron), ('CHEF_LOCK', self.lock)):
            self.patch(mock.patch.object(nu, name, str(value)))
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
        self.assertIn(['dnf', 'clean', 'packages'], self.run.calls)

    def test_an_installed_node_keeps_its_rollback_repo(self):
        self.run.markers = ['zed']
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
        self.patch(mock.patch.object(nu, 'openstack_units', return_value=['openstack-nova-compute.service']))
        self.kills = []
        self.patch(mock.patch.object(nu.os, 'kill', lambda pid, sig: self.kills.append(pid)))
        self.cron.write_text('cron')

    def add_proc(self, pid, comm, ppid, cmdline):
        d = self.proc / str(pid)
        d.mkdir()
        (d / 'stat').write_text(f'{pid} ({comm}) S {ppid} {pid} {pid} 0 -1\n')
        (d / 'cmdline').write_bytes(b'\0'.join(a.encode() for a in cmdline) + b'\0')

    def stopped(self):
        return ['systemctl', 'stop', 'openstack-nova-compute.service'] in self.run.calls

    def test_kills_only_the_cron_sleeper_shell_first(self):
        self.add_proc(100, 'sh', 1, ['/bin/sh', '-c', f'/bin/sleep 300; /usr/bin/flock -n {self.lock} cinc-client'])
        self.add_proc(101, 'sleep', 100, ['/bin/sleep', '300'])
        self.add_proc(199, 'bash', 1, ['bash'])
        self.add_proc(200, 'sleep', 199, ['sleep', '60'])
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


class NovaVenvTest(Base):
    def setUp(self):
        super().setUp()
        conf = Path(self.tmp.name) / 'keystone.conf'
        conf.write_text('[database]\nconnection = mysql+pymysql://ks:pw@db:3306/keystone_x86\n')
        self.patch(mock.patch.object(nu, 'DB_OPTIONS', [(str(conf), 'database', 'connection')]))
        self.nova_py = Path(self.tmp.name) / 'nova-python'
        self.patch(mock.patch.object(nu, 'NOVA_PY', str(self.nova_py)))
        self.cells = self.patch(mock.patch.object(
            nu, 'nova_cell_urls', return_value={'cell1': 'mysql+pymysql://n:pw@db:3306/nova_cell1'}))
        self.write_release(installed='yoga', target='zed', db_node=True)

    def test_backup_skips_the_cells_without_nova(self):
        self.assertEqual(list(nu.service_db_urls()), ['keystone_x86'])
        self.cells.assert_not_called()

    def test_backup_adds_the_cells_with_nova(self):
        self.nova_py.touch()
        self.assertEqual(sorted(nu.service_db_urls()), ['keystone_x86', 'nova_cell1'])

    def test_precheck_refuses_without_nova(self):
        with self.assertRaisesRegex(nu.UpgradeError, 'needs the nova-controller venv'):
            nu.cmd_precheck(None)
        self.cells.assert_not_called()
        self.assertEqual(self.run.calls, [])


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
