#!/usr/bin/python3
"""Drive one cloud through an OpenStack release upgrade window, a phase at a time.

Each phase runs openstack-node-upgrade (or cinc-client) on the right hosts over
ssh as root, and records a marker so the window can stop and resume. Hosts come
from /etc/openstack-upgrade/<cloud>.json, which Chef writes from node search.

Phases, in order (docs/RELEASE_UPGRADES.md has the runbook):

  precheck       every node has staged the target; the DB controller passes precheck
  stop           stop both controllers (cold control plane)
  backup         dump every service database on the DB controller
  controller-db  install and converge the DB controller: runs the db syncs.
                 Point of no return 1: from here a rollback needs the dumps
  controller     install and converge the other controller(s)
  verify         upgrade checks and the service lists, from the DB controller
  computes       canaries one at a time, then the rest in batches of --batch
  finalize       restart nova on the controllers, run online migrations, check,
                 and converge the controllers so their cinc cron comes back

  status         every node's state and the phase markers (any time)
  rollback       undo the installed release where it was installed; see --help-rollback
"""

import argparse
import concurrent.futures
import json
import logging
import os
import subprocess
import sys

INVENTORY_DIR = '/etc/openstack-upgrade'
STATE_DIR = '/root/openstack-upgrade'
LOG_DIR = '/var/log/openstack-upgrade'
PHASES = ['precheck', 'stop', 'backup', 'controller-db', 'controller', 'verify', 'computes', 'finalize']
ROLLBACK_HELP = """Rollback, in this order:
  1. If controller-db ran (point of no return 1), stop both controllers and
     restore the databases first:  openstack-node-upgrade restore --yes  on the
     DB controller. This prints the restore commands and runs them.
  2. openstack-upgrade <cloud> rollback      undoes each host's dnf transaction
  3. Set release back in the cloud's openstack data bag item. Chef raises on a
     node whose installed release is newer than the bag, so undo comes first.
  4. openstack-upgrade <cloud> rollback --converge   runs cinc-client on them
"""

log = logging.getLogger('openstack-upgrade')


class RunnerError(Exception):
    pass


class Runner:
    def __init__(self, cloud, dry_run=False):
        path = os.path.join(INVENTORY_DIR, f'{cloud}.json')
        try:
            with open(path) as f:
                self.inv = json.load(f)
        except FileNotFoundError:
            raise RunnerError(f'{path} is missing; is {cloud} a cloud this jumphost converged with?')
        self.cloud = cloud
        self.dry_run = dry_run
        self.db = self.inv['db_node']
        self.controllers = self.inv['controllers']
        self.hypervisors = [h['fqdn'] for h in self.inv['hypervisors']]
        if not self.db:
            raise RunnerError(f'no DB controller in {path}; has every controller converged this release-switch cookbook?')

    def ssh(self, host, *args, capture=False):
        cmd = ['ssh', '-o', 'BatchMode=yes', '-o', 'ConnectTimeout=15', f'root@{host}'] + list(args)
        if self.dry_run and not capture:
            print('would run:', ' '.join(cmd))
            return ''
        log.info('%s: %s', host, ' '.join(args))
        res = subprocess.run(cmd, text=True, check=False,
                             stdout=subprocess.PIPE if capture else None)
        if res.returncode != 0:
            raise RunnerError(f'{host}: {" ".join(args)} exited {res.returncode}')
        return res.stdout if capture else ''

    def node(self, host, *args):
        return self.ssh(host, 'openstack-node-upgrade', *args)

    def statuses(self):
        hosts = self.controllers + self.hypervisors
        with concurrent.futures.ThreadPoolExecutor(max_workers=16) as pool:
            results = pool.map(lambda h: (h, json.loads(self.ssh(h, 'openstack-node-upgrade', 'status', capture=True))), hosts)
        return dict(results)

    def target(self, statuses):
        targets = {s['release']['target'] for s in statuses.values()}
        if len(targets) != 1:
            raise RunnerError(f'nodes disagree on the target release: {sorted(targets)}; converge them all first')
        return targets.pop()

    def state_dir(self, target):
        path = os.path.join(STATE_DIR, f'{self.cloud}-{target}')
        os.makedirs(path, exist_ok=True)
        return path

    def done(self, target, phase):
        return os.path.exists(os.path.join(self.state_dir(target), f'{phase}.done'))

    def mark(self, target, phase):
        if not self.dry_run:
            open(os.path.join(self.state_dir(target), f'{phase}.done'), 'w').close()

    def run_phase(self, phase, args):
        statuses = self.statuses()
        if phase == 'status':
            targets = sorted({s['release']['target'] for s in statuses.values()})
            return self.phase_status(targets[0] if len(targets) == 1 else None, statuses, args)
        target = self.target(statuses)
        if phase in PHASES:
            missing = [p for p in PHASES[:PHASES.index(phase)] if not self.done(target, p)]
            if missing:
                raise RunnerError(f'{phase} needs {", ".join(missing)} first')
            if self.done(target, phase) and phase != 'computes':
                log.info('%s already done for %s %s', phase, self.cloud, target)
                return
        getattr(self, 'phase_' + phase.replace('-', '_'))(target, statuses, args)
        if phase in PHASES:
            self.mark(target, phase)
            log.info('%s done', phase)

    def phase_status(self, target, statuses, args):
        for host, s in sorted(statuses.items()):
            r = s['release']
            down = [u for u, state in s['units'].items() if state != 'active']
            print(f'{host:40} installed={",".join(s["markers"]) or "-"} target={r["target"]} '
                  f'staged={r["staged"]} cron={s["cron"]} inactive={len(down)} txn={s["transaction"] or "-"}')
        if target is None:
            print('nodes disagree on the target release; converge them all before a window')
            return
        print('phases done:', ', '.join(p for p in PHASES if self.done(target, p)) or 'none')

    def phase_precheck(self, target, statuses, args):
        unstaged = [h for h, s in statuses.items() if not s['release']['staged']]
        if unstaged:
            raise RunnerError(f'not staged for {target}: {", ".join(sorted(unstaged))}')
        self.node(self.db, 'precheck')

    def phase_stop(self, target, statuses, args):
        print(f'Set Nagios downtime for the {self.cloud} API checks and novnc now, and post the status.io notice.')
        for host in self.controllers:
            self.node(host, 'stop')

    def phase_backup(self, target, statuses, args):
        self.node(self.db, 'backup')

    def converge(self, host):
        self.node(host, 'install')
        self.ssh(host, 'cinc-client')

    def phase_controller_db(self, target, statuses, args):
        self.converge(self.db)

    def phase_controller(self, target, statuses, args):
        for host in self.controllers:
            if host != self.db:
                self.converge(host)

    def phase_verify(self, target, statuses, args):
        self.node(self.db, 'check')
        self.ssh(self.db, 'bash', '-c', "'source /root/openrc && openstack compute service list "
                 "&& openstack network agent list && openstack volume service list'")

    def phase_computes(self, target, statuses, args):
        canaries = [h for h in self.inv['canaries'] if h in self.hypervisors]
        rest = [h for h in self.hypervisors if h not in canaries]
        state = os.path.join(self.state_dir(target), 'computes')
        os.makedirs(state, exist_ok=True)

        def one(host):
            if os.path.exists(os.path.join(state, host)):
                return
            self.node(host, 'stop')
            self.converge(host)
            if not self.dry_run:
                open(os.path.join(state, host), 'w').close()

        for host in canaries:
            one(host)
        if canaries and rest and not args.yes and not self.dry_run:
            input(f'Canaries {", ".join(canaries)} are on {target}. Check them, then press Enter for the rest. ')
        with concurrent.futures.ThreadPoolExecutor(max_workers=args.batch) as pool:
            for future in [pool.submit(one, h) for h in rest]:
                future.result()

    def phase_finalize(self, target, statuses, args):
        for host in self.controllers:
            self.node(host, 'restart-nova')
        self.node(self.db, 'migrate')
        self.node(self.db, 'check')
        for host in self.controllers:
            self.ssh(host, 'cinc-client')

    def phase_rollback(self, target, statuses, args):
        touched = [h for h, s in statuses.items() if s['transaction']]
        if args.converge:
            for host in self.controllers + self.hypervisors:
                self.ssh(host, 'cinc-client')
            return
        if self.done(target, 'controller-db') and not args.restored:
            print(ROLLBACK_HELP)
            raise RunnerError('controller-db ran: restore the databases first, then rerun with --restored')
        for host in touched:
            self.node(host, 'undo')
        print(f'Undone on {", ".join(sorted(touched)) or "no host"}. Now set release back in the {self.cloud} '
              f'data bag item, then run: openstack-upgrade {self.cloud} rollback --converge')


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('cloud', help='the cloud, as its openstack data bag item (x86, arm, ppc64)')
    parser.add_argument('phase', choices=['status', 'rollback'] + PHASES)
    parser.add_argument('-n', '--dry-run', action='store_true', help='print what would run on each host')
    parser.add_argument('--batch', type=int, default=2, help='hypervisors upgraded at once after the canaries')
    parser.add_argument('-y', '--yes', action='store_true', help='do not pause after the canaries')
    parser.add_argument('--restored', action='store_true', help='rollback: the databases are already restored')
    parser.add_argument('--converge', action='store_true', help='rollback: the bag is reverted; run cinc-client')
    parser.add_argument('--help-rollback', action='store_true', help='print the rollback procedure and exit')
    if '--help-rollback' in sys.argv:
        print(ROLLBACK_HELP)
        return 0
    args = parser.parse_args()

    os.makedirs(LOG_DIR, exist_ok=True)
    logging.basicConfig(level=logging.INFO, format='%(asctime)s %(levelname)s %(message)s',
                        handlers=[logging.StreamHandler(sys.stdout),
                                  logging.FileHandler(os.path.join(LOG_DIR, f'{args.cloud}.log'))])
    try:
        Runner(args.cloud, dry_run=args.dry_run).run_phase(args.phase, args)
    except RunnerError as e:
        log.error('%s', e)
        return 1
    except KeyboardInterrupt:
        log.error('interrupted; rerun the same phase to resume')
        return 130
    return 0


if __name__ == '__main__':
    sys.exit(main())
