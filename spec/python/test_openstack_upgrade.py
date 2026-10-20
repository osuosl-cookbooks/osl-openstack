"""Unit tests for files/openstack-upgrade.py.

Run with: python3 -m unittest discover -s spec/python -v

ssh is replaced by a fake that answers status per host and records every
call; the inventory and phase markers live in a tempdir.
"""

import argparse
import importlib.util
import json
import os
import tempfile
import unittest
from pathlib import Path
from unittest import mock

SCRIPT = Path(__file__).resolve().parents[2] / 'files' / 'openstack-upgrade.py'
_spec = importlib.util.spec_from_file_location('openstack_upgrade', SCRIPT)
ou = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(ou)

CONTROLLERS = ['c1', 'c2']
HYPERVISORS = ['h1', 'h2', 'h3', 'h4', 'h5']


def node_status(target='zed', markers=('yoga',), units=None, transaction=None):
    return {
        'release': {'installed': 'yoga', 'target': target, 'staged': True},
        'markers': list(markers), 'units': units or {'openstack-nova-api.service': 'inactive'},
        'transaction': transaction, 'cron': True,
    }


class Base(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        root = Path(self.tmp.name)
        (root / 'inv').mkdir()
        (root / 'inv' / 'ppc64.json').write_text(json.dumps({
            'cloud': 'ppc64', 'controllers': CONTROLLERS, 'db_node': 'c1', 'canaries': ['h1'],
            'hypervisors': [{'fqdn': h} for h in HYPERVISORS],
        }))
        self.state_root = root / 'state'
        for name, value in (('INVENTORY_DIR', root / 'inv'), ('STATE_DIR', self.state_root)):
            patcher = mock.patch.object(ou, name, str(value))
            self.addCleanup(patcher.stop)
            patcher.start()
        self.status = {h: node_status() for h in CONTROLLERS + HYPERVISORS}
        self.fail = set()
        self.calls = []

    def fake_ssh(self, host, *args, capture=False):
        self.calls.append((host,) + args)
        if (host,) + args in self.fail or (host, '*') in self.fail:
            raise ou.RunnerError(f'{host}: {" ".join(args)} exited 255')
        if args[-1] == 'status':
            return json.dumps(self.status[host])
        return ''

    def runner(self, dry_run=False):
        r = ou.Runner('ppc64', dry_run=dry_run)
        patcher = mock.patch.object(r, 'ssh', self.fake_ssh)
        self.addCleanup(patcher.stop)
        patcher.start()
        return r

    def args(self, **kw):
        return argparse.Namespace(**{'converge': False, 'restored': False, 'batch': 2, 'yes': True, **kw})

    def state(self, target='zed'):
        return self.state_root / f'ppc64-{target}'

    def mark_done(self, *phases):
        self.state().mkdir(parents=True, exist_ok=True)
        for phase in phases:
            (self.state() / f'{phase}.done').touch()

    def ran(self, host, *args):
        return (host,) + args in self.calls


class DefaultsTest(unittest.TestCase):
    def test_markers_live_under_var_lib(self):
        self.assertEqual(ou.STATE_DIR, '/var/lib/openstack-upgrade')


class PhaseOrderTest(Base):
    def test_refuses_a_phase_before_its_predecessors(self):
        with self.assertRaisesRegex(ou.RunnerError, 'backup needs precheck, stop first'):
            self.runner().run_phase('backup', self.args())

    def test_skips_a_phase_already_done(self):
        self.mark_done('precheck', 'stop', 'backup')
        self.runner().run_phase('backup', self.args())
        self.assertFalse(self.ran('c1', 'openstack-node-upgrade', 'backup'))

    def test_marks_a_phase_started_and_done(self):
        self.runner().run_phase('precheck', self.args())
        self.assertTrue((self.state() / 'precheck.started').exists())
        self.assertTrue((self.state() / 'precheck.done').exists())

    def test_dry_run_writes_no_markers(self):
        self.runner(dry_run=True).run_phase('precheck', self.args())
        self.assertEqual(os.listdir(self.state()), [])


class PrecheckTest(Base):
    def test_refuses_a_cloud_already_on_the_target(self):
        self.status = {h: node_status(markers=('zed',)) for h in self.status}
        with self.assertRaisesRegex(ou.RunnerError, 'every node already runs zed'):
            self.runner().run_phase('precheck', self.args())
        self.assertFalse(self.ran('c1', 'openstack-node-upgrade', 'precheck'))


class BackupTest(Base):
    def test_refuses_while_a_controller_unit_is_not_stopped(self):
        self.mark_done('precheck', 'stop')
        for state in ('active', 'activating'):
            with self.subTest(state=state):
                self.status['c2'] = node_status(units={'neutron-server.service': state})
                with self.assertRaisesRegex(ou.RunnerError, f'c2 neutron-server.service \\({state}\\)'):
                    self.runner().run_phase('backup', self.args())
        self.assertFalse(self.ran('c1', 'openstack-node-upgrade', 'backup'))

    def test_backs_up_once_every_unit_is_down(self):
        self.mark_done('precheck', 'stop')
        self.status['c2'] = node_status(units={'neutron-server.service': 'failed'})
        self.runner().run_phase('backup', self.args())
        self.assertTrue(self.ran('c1', 'openstack-node-upgrade', 'backup'))


class ComputesTest(Base):
    def setUp(self):
        super().setUp()
        self.mark_done('precheck', 'stop', 'backup', 'controller-db', 'controller', 'verify')

    def test_stops_after_a_failed_batch(self):
        self.fail.add(('h2', 'openstack-node-upgrade', 'install'))
        with self.assertRaisesRegex(ou.RunnerError, 'h2'):
            self.runner().run_phase('computes', self.args())
        self.assertTrue(self.ran('h3', 'cinc-client'))
        for host in ('h4', 'h5'):
            self.assertFalse(self.ran(host, 'openstack-node-upgrade', 'stop'))
        done = os.listdir(self.state() / 'computes')
        self.assertEqual(sorted(done), ['h1', 'h3'])


class UpgradeTest(Base):
    def setUp(self):
        super().setUp()
        self.mark_done('precheck')
        self.answers = []
        self.prompts = []
        self.patch_input()
        tty = mock.patch.object(ou.sys.stdin, 'isatty', return_value=True)
        self.addCleanup(tty.stop)
        tty.start()

    def patch_input(self):
        def fake_input(prompt):
            self.prompts.append(prompt)
            if not self.answers:
                raise EOFError
            return self.answers.pop(0)
        patcher = mock.patch('builtins.input', fake_input)
        self.addCleanup(patcher.stop)
        patcher.start()

    def upgrade(self, dry_run=False, **kw):
        r = self.runner(dry_run=dry_run)
        r.run_phase('upgrade', self.args(**kw))
        return r

    def test_runs_every_phase_in_order(self):
        self.upgrade(yes=True)
        for phase in ou.UPGRADE:
            self.assertTrue((self.state() / f'{phase}.done').exists(), phase)
        steps = [c for c in self.calls if c[-1] in ('stop', 'backup', 'install', 'check', 'restart-nova', 'migrate')]
        self.assertEqual(steps[:3], [('c1', 'openstack-node-upgrade', 'stop'), ('c2', 'openstack-node-upgrade', 'stop'),
                                     ('c1', 'openstack-node-upgrade', 'backup')])
        self.assertEqual(self.prompts, [])

    def test_needs_precheck(self):
        (self.state() / 'precheck.done').unlink()
        with self.assertRaisesRegex(ou.RunnerError, 'stop needs precheck first'):
            self.upgrade(yes=True)

    def test_refuses_without_a_terminal_before_any_ssh(self):
        with mock.patch.object(ou.sys.stdin, 'isatty', return_value=False):
            with self.assertRaisesRegex(ou.RunnerError, 'run it in tmux, or pass -y'):
                self.upgrade(yes=False)
        self.assertEqual(self.calls, [])

    def test_stops_before_controller_db_without_yes(self):
        self.answers = ['no']
        r = self.runner()
        with self.assertRaisesRegex(ou.RunnerError, 'pause before controller-db'):
            r.run_phase('upgrade', self.args(yes=False))
        self.assertFalse(self.ran('c1', 'openstack-node-upgrade', 'install'))
        self.assertFalse((self.state() / 'controller-db.started').exists())
        self.assertIn('nothing has run on c1', r.resume_hint())

    def test_pauses_at_all_three_gates(self):
        self.answers = ['yes', '', '']
        self.upgrade(yes=False)
        self.assertEqual(len(self.prompts), 3)
        self.assertIn('Type yes', self.prompts[0])
        self.assertIn('verify passed', self.prompts[1])
        self.assertIn('Canaries h1', self.prompts[2])

    def test_a_started_controller_db_says_so(self):
        self.mark_done('stop', 'backup')
        (self.state() / 'controller-db.started').touch()
        self.answers = []
        with self.assertRaises(ou.RunnerError):
            self.upgrade(yes=False)
        self.assertIn('already started on c1', self.prompts[0])

    def test_a_no_after_controller_db_started_does_not_say_nothing_ran(self):
        self.mark_done('stop', 'backup')
        (self.state() / 'controller-db.started').touch()
        self.answers = ['no']
        r = self.runner()
        with self.assertRaises(ou.RunnerError):
            r.run_phase('upgrade', self.args(yes=False))
        self.assertNotIn('nothing has run', r.resume_hint())
        self.assertIn('--help-rollback', r.resume_hint())

    def test_stopping_at_the_verify_pause_offers_rollback(self):
        self.mark_done('stop', 'backup', 'controller-db', 'controller', 'verify')
        r = self.runner()
        with self.assertRaises(ou.RunnerError):
            r.run_phase('upgrade', self.args(yes=False))
        self.assertIn('no hypervisor has moved', r.resume_hint())
        self.assertNotIn('fix forward', r.resume_hint())

    def test_no_resume_hint_before_any_upgrade_phase_began(self):
        (self.state() / 'precheck.done').unlink()
        r = self.runner()
        with self.assertRaises(ou.RunnerError):
            r.run_phase('upgrade', self.args(yes=True))
        self.assertFalse(r.entered or r.gating)

    def test_resume_after_controller_db_asks_nothing_for_it(self):
        self.mark_done('stop', 'backup', 'controller-db')
        self.answers = ['', '']
        self.upgrade(yes=False)
        self.assertFalse(any('Type yes' in p for p in self.prompts))
        self.assertFalse(self.ran('c1', 'openstack-node-upgrade', 'backup'))

    def test_resume_with_computes_done_skips_it_and_its_pauses(self):
        self.mark_done('stop', 'backup', 'controller-db', 'controller', 'verify', 'computes')
        self.upgrade(yes=False)
        self.assertEqual(self.prompts, [])
        self.assertFalse(any(c[0] in HYPERVISORS for c in self.calls if c[-1] != 'status'))
        self.assertTrue((self.state() / 'finalize.done').exists())

    def test_resume_inside_computes_skips_the_verify_pause(self):
        self.mark_done('stop', 'backup', 'controller-db', 'controller', 'verify')
        (self.state() / 'computes.started').touch()
        self.answers = ['']
        self.upgrade(yes=False)
        self.assertEqual(len(self.prompts), 1)
        self.assertIn('Canaries', self.prompts[0])

    def test_a_controller_failure_stops_before_verify(self):
        self.fail.add(('c2', 'cinc-client'))
        r = self.runner()
        with self.assertRaises(ou.RunnerError):
            r.run_phase('upgrade', self.args(yes=True))
        self.assertFalse((self.state() / 'verify.started').exists())
        self.assertIn('rerun upgrade', r.resume_hint())
        self.assertIn('--help-rollback', r.resume_hint())

    def test_a_finalize_failure_says_fix_forward(self):
        self.fail.add(('c1', 'openstack-node-upgrade', 'migrate'))
        r = self.runner()
        with self.assertRaises(ou.RunnerError):
            r.run_phase('upgrade', self.args(yes=True))
        self.assertEqual(r.current, 'finalize')
        self.assertIn('fix forward', r.resume_hint())

    def test_eof_at_the_canary_pause_is_a_clean_error(self):
        self.mark_done('stop', 'backup', 'controller-db', 'controller', 'verify')
        (self.state() / 'computes.started').touch()
        with self.assertRaisesRegex(ou.RunnerError, 'no terminal to answer the pause'):
            self.upgrade(yes=False)

    def test_dry_run_walks_every_phase_and_writes_nothing(self):
        self.status['c2'] = node_status(units={'neutron-server.service': 'active'})
        with mock.patch('builtins.print') as out:
            self.upgrade(dry_run=True, yes=False)
        printed = ' '.join(str(c.args) for c in out.call_args_list)
        self.assertIn('would refuse', printed)
        # The fake ssh stands in for the dry run's printing; every phase still reached its hosts
        self.assertTrue(self.ran('c1', 'openstack-node-upgrade', 'restart-nova'))
        self.assertEqual(sorted(os.listdir(self.state())), ['precheck.done'])
        self.assertEqual(self.prompts, [])


class RollbackTest(Base):
    def setUp(self):
        super().setUp()
        self.mark_done('precheck', 'stop', 'backup')
        for host in ('c1', 'c2', 'h1'):
            self.status[host]['transaction'] = '42'

    def test_requires_restored_once_controller_db_started(self):
        (self.state() / 'controller-db.started').touch()
        self.status['c1']['transaction'] = None
        with self.assertRaisesRegex(ou.RunnerError, 'restore the databases first'):
            self.runner().run_phase('rollback', self.args())
        self.assertFalse(any('undo' in c for c in self.calls))

    def test_requires_restored_when_the_db_node_installed(self):
        with self.assertRaisesRegex(ou.RunnerError, 'restore the databases first'):
            self.runner().run_phase('rollback', self.args())

    def test_undoes_and_moves_the_markers_aside(self):
        self.runner().run_phase('rollback', self.args(restored=True))
        for host in ('c1', 'c2', 'h1'):
            self.assertTrue(self.ran(host, 'openstack-node-upgrade', 'undo'))
        self.assertFalse(self.ran('h2', 'openstack-node-upgrade', 'undo'))
        self.assertFalse(self.state().exists())
        moved = [p for p in os.listdir(self.state_root) if p.startswith('ppc64-zed.rolled-back-')]
        self.assertEqual(len(moved), 1)

    def test_dry_run_keeps_the_markers(self):
        self.runner(dry_run=True).run_phase('rollback', self.args(restored=True))
        self.assertTrue((self.state() / 'backup.done').exists())

    def test_takes_the_target_from_the_controllers(self):
        for host in HYPERVISORS:
            self.status[host]['release']['target'] = 'yoga'
        self.runner().run_phase('rollback', self.args(restored=True))
        self.assertTrue(self.ran('h1', 'openstack-node-upgrade', 'undo'))

    def test_lists_an_unreachable_hypervisor(self):
        self.fail.add(('h3', '*'))
        r = self.runner()
        r.run_phase('rollback', self.args(restored=True))
        self.assertEqual(r.unreachable, ['h3'])
        self.assertTrue(self.ran('c1', 'openstack-node-upgrade', 'undo'))

    def test_an_unreachable_controller_stops_it(self):
        self.fail.add(('c2', '*'))
        with self.assertRaises(ou.RunnerError):
            self.runner().run_phase('rollback', self.args(restored=True))
        self.assertFalse(any('undo' in c for c in self.calls))

    def test_converge_needs_no_agreement_and_keeps_going(self):
        self.status['h1']['release']['target'] = 'yoga'
        self.fail.add(('h2', 'cinc-client'))
        with self.assertRaisesRegex(ou.RunnerError, 'cinc-client failed on h2'):
            self.runner().run_phase('rollback', self.args(converge=True))
        for host in CONTROLLERS + HYPERVISORS:
            self.assertTrue(self.ran(host, 'cinc-client'))
        self.assertFalse(any(c[-1] == 'status' for c in self.calls))


if __name__ == '__main__':
    unittest.main()
