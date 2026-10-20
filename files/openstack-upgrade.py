#!/usr/bin/python3
"""Drive one cloud through an OpenStack release upgrade window, a phase at a time.

Each phase runs openstack-node-upgrade (or cinc-client) on the right hosts over
ssh as root, and records a marker so the window can stop and resume. Hosts come
from /etc/openstack-upgrade/<cloud>.json, which Chef writes from node search.
Every run but status keeps its full output in /var/log/openstack-upgrade/<cloud>-<UTC>.log.

Phases, in order (docs/RELEASE_UPGRADES.md has the runbook):

  precheck       every node has staged the target; the DB controller passes precheck
  stop           stop both controllers (cold control plane)
  backup         dump every service database on the DB controller
  controller-db  install and converge the DB controller: runs the db syncs and
                 starts its APIs. Points of no return 1 and 2: from here a
                 rollback needs the dumps and loses every write since backup
  controller     install and converge the other controller(s)
  verify         upgrade checks and the service lists, from the DB controller
  computes       canaries one at a time, then the rest in batches of --batch
  finalize       restart nova on the controllers, run online migrations, check,
                 and converge the controllers

  upgrade        stop through finalize in one run, pausing before controller-db,
                 after the canaries and after verify (-y skips the pauses)
  status         every node's state and the phase markers (any time)
  rollback       undo the installed release where it was installed; see --help-rollback
"""

import argparse
import concurrent.futures
import ctypes
import json
import logging
import os
import shutil
import signal
import subprocess
import sys
import threading
import time

INVENTORY_DIR = '/etc/openstack-upgrade'
STATE_DIR = '/var/lib/openstack-upgrade'
LOG_DIR = '/var/log/openstack-upgrade'
SSH = ['ssh', '-o', 'BatchMode=yes', '-o', 'ConnectTimeout=15']
SSH_KEYS = ['/root/.ssh/id_rsa', '/root/.ssh/id_ecdsa', '/root/.ssh/id_ed25519']
AGENT_DIR = '/run/openstack-upgrade'
PR_SET_PDEATHSIG = 1
PHASES = ['precheck', 'stop', 'backup', 'controller-db', 'controller', 'verify', 'computes', 'finalize']
# What `upgrade` runs; precheck stays a separate step before the window
UPGRADE = PHASES[1:]
ROLLBACK_HELP = """Rollback, in this order:
  1. If controller-db started (points of no return 1 and 2), run
     openstack-node-upgrade stop  on every controller that ran install, then
     openstack-node-upgrade restore --yes  on the DB controller. Writes since
     backup are lost.
  2. openstack-upgrade <cloud> rollback --restored   undoes each host's dnf
     transaction (plain  rollback  when controller-db never started), then
     moves this window's phase markers aside
  3. Set release back in the cloud's openstack data bag item. Chef raises on a
     node whose installed release is newer than the bag, so undo comes first.
  4. openstack-upgrade <cloud> rollback --converge   runs cinc-client everywhere
"""

log = logging.getLogger('openstack-upgrade')


class RunnerError(Exception):
    pass


class Transcript:
    """One run's full output; a failed write warns once and stops, so the screen and ssh carry on."""

    def __init__(self, path):
        self.path = path
        self.file = open(os.open(path, os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o600), 'a',
                         encoding='utf-8', errors='replace')
        self.lock = threading.Lock()
        self.broken = False

    def write(self, s):
        if self.broken:
            return
        try:
            self.file.write(s)
            self.file.flush()
        except (OSError, ValueError) as e:
            self.broken = True
            sys.__stderr__.write(f'{self.path}: no longer written: {e}\n')


class Tee:
    """A stream that also writes to the transcript; the lock keeps both in the same order."""

    def __init__(self, stream, transcript):
        self.stream = stream
        self.transcript = transcript

    def write(self, s):
        with self.transcript.lock:
            self.stream.write(s)
            self.stream.flush()
            self.transcript.write(s)
        return len(s)

    def flush(self):
        self.stream.flush()


class Agent:
    """This run's own ssh-agent, so keychain's 10-minute key timeout can't stop a window midway."""

    def __init__(self):
        self.proc = None
        self.dir = None

    def start(self):
        keys = [k for k in SSH_KEYS if os.path.exists(k)]
        if not keys:
            log.warning('no key at %s; ssh uses the agent this shell already has', ', '.join(SSH_KEYS))
            return
        self.dir = os.path.join(AGENT_DIR, f'agent-{os.getpid()}')
        os.makedirs(self.dir, mode=0o700, exist_ok=True)
        sock = os.path.join(self.dir, 'sock')
        if os.path.exists(sock):
            os.unlink(sock)
        prctl = ctypes.CDLL(None, use_errno=True).prctl
        # PDEATHSIG fires when the starting thread exits, so this runs on the main thread only
        self.proc = subprocess.Popen(['ssh-agent', '-D', '-a', sock], stdout=subprocess.DEVNULL,
                                     stderr=subprocess.DEVNULL,
                                     preexec_fn=lambda: prctl(PR_SET_PDEATHSIG, signal.SIGTERM))
        for _ in range(50):
            if os.path.exists(sock):
                break
            if self.proc.poll() is not None:
                raise RunnerError(f'ssh-agent exited {self.proc.returncode} before it started')
            time.sleep(0.1)
        else:
            raise RunnerError('ssh-agent did not start within 5 seconds')
        os.environ['SSH_AUTH_SOCK'] = sock
        os.environ.pop('SSH_AGENT_PID', None)
        stdin = None if sys.stdin.isatty() else subprocess.DEVNULL
        if subprocess.run(['ssh-add'] + keys, stdin=stdin, check=False).returncode != 0:
            raise RunnerError(f"could not load {', '.join(keys)} into this run's ssh agent; "
                              "a changing run needs a terminal for the key's passphrase")
        log.info("loaded %s into this run's own ssh agent; keychain's timeout no longer applies", ', '.join(keys))

    def stop(self):
        if self.proc and self.proc.poll() is None:
            self.proc.terminate()
            self.proc.wait(timeout=5)
            log.info("stopped this run's ssh agent")
        if self.dir:
            shutil.rmtree(self.dir, ignore_errors=True)


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
        self.unreachable = []
        # upgrade state: the phase running, a pause in progress, and dry-run's pretend-done phases
        self.upgrading = False
        self.current = None
        self.gating = None
        self.entered = False
        self.assume_done = set()
        if not self.db:
            raise RunnerError(f'no DB controller in {path}; has every controller converged this release-switch cookbook?')

    def ssh(self, host, *args, capture=False):
        cmd = SSH + [f'root@{host}'] + list(args)
        # One write per line, so hosts running in parallel never split each other's lines
        if self.dry_run and not capture:
            sys.stdout.write(f'{host}: would run: {" ".join(cmd)}\n')
            return ''
        log.info('%s: %s', host, ' '.join(args))
        if capture:
            proc = subprocess.run(cmd, text=True, errors='replace', capture_output=True, check=False)
            for line in proc.stderr.splitlines():
                sys.stderr.write(f'{host}: {line}\n')
        else:
            with subprocess.Popen(cmd, text=True, errors='replace', stdout=subprocess.PIPE,
                                  stderr=subprocess.STDOUT) as proc:
                for line in proc.stdout:
                    line = line.rstrip('\n')
                    sys.stdout.write(f'{host}: {line}\n')
        if proc.returncode != 0:
            raise RunnerError(f'{host}: {" ".join(args)} exited {proc.returncode}')
        return proc.stdout if capture else ''

    def node(self, host, *args):
        return self.ssh(host, 'openstack-node-upgrade', *args)

    def statuses(self, tolerant=False):
        """Every node's status; with tolerant, an unreachable hypervisor is skipped and listed."""
        def one(host):
            try:
                return host, json.loads(self.ssh(host, 'openstack-node-upgrade', 'status', capture=True))
            except RunnerError as e:
                if not tolerant or host in self.controllers:
                    raise
                log.warning('skipping %s: %s', host, e)
                return host, None

        with concurrent.futures.ThreadPoolExecutor(max_workers=16) as pool:
            results = dict(pool.map(one, self.controllers + self.hypervisors))
        self.unreachable = sorted(h for h, s in results.items() if s is None)
        return {h: s for h, s in results.items() if s is not None}

    def target(self, statuses):
        targets = {s['release']['target'] for s in statuses.values()}
        if len(targets) != 1:
            raise RunnerError(f'nodes disagree on the target release: {sorted(targets)}; converge them all first')
        return targets.pop()

    def state_dir(self, target):
        path = os.path.join(STATE_DIR, f'{self.cloud}-{target}')
        os.makedirs(path, exist_ok=True)
        return path

    def done(self, target, phase, state='done'):
        return os.path.exists(os.path.join(self.state_dir(target), f'{phase}.{state}'))

    def mark(self, target, phase, state='done'):
        if not self.dry_run:
            open(os.path.join(self.state_dir(target), f'{phase}.{state}'), 'w').close()

    def run_phase(self, phase, args):
        if phase == 'upgrade':
            return self.run_upgrade(args)
        if phase == 'rollback' and args.converge:
            return self.rollback_converge()
        rollback = phase == 'rollback'
        statuses = self.statuses(tolerant=rollback)
        if phase == 'status':
            targets = sorted({s['release']['target'] for s in statuses.values()})
            return self.phase_status(targets[0] if len(targets) == 1 else None, statuses, args)
        # Hypervisors flip to the reverted bag on their own cron; controllers stopped theirs
        target = self.target({h: statuses[h] for h in self.controllers} if rollback else statuses)
        if phase in PHASES:
            missing = [p for p in PHASES[:PHASES.index(phase)] if not self.done(target, p) and p not in self.assume_done]
            if missing:
                raise RunnerError(f'{phase} needs {", ".join(missing)} first')
            # Standalone computes re-enters for new hypervisors; a resumed upgrade does not
            if self.done(target, phase) and (phase != 'computes' or self.upgrading):
                log.info('%s already done for %s %s', phase, self.cloud, target)
                return
            if self.upgrading:
                self.upgrade_gate(phase, target, args)
                self.entered = True
            self.mark(target, phase, 'started')
        getattr(self, 'phase_' + phase.replace('-', '_'))(target, statuses, args)
        if phase in PHASES:
            self.mark(target, phase)
            log.info('%s done', phase)

    def require_terminal(self, args):
        if not args.yes and not self.dry_run and not sys.stdin.isatty():
            raise RunnerError('upgrade pauses for confirmation; run it in tmux, or pass -y '
                              "(a root key with a passphrase needs the terminal even then)")

    def run_upgrade(self, args):
        self.require_terminal(args)
        self.upgrading = True
        for phase in UPGRADE:
            self.current = phase
            self.run_phase(phase, args)
            if self.dry_run:
                self.assume_done.add(phase)
        self.current = None
        log.info('upgrade finished for %s', self.cloud)

    def upgrade_gate(self, phase, target, args):
        if phase == 'controller-db':
            if self.done(target, 'controller-db', 'started'):
                text = (f'controller-db already started on {self.db}: the schema may be synced. Going on is forward; '
                        'a rollback now needs a restore (openstack-upgrade --help-rollback).')
                guarding = 'controller-db (started)'
            else:
                text = (f'Next, controller-db installs {target} on {self.db} and runs the db syncs, and users reach '
                        'the APIs again. From here a rollback restores the backup and loses every write since.')
                guarding = phase
            self.gate(args, text, confirm='yes', guarding=guarding)
        elif phase == 'computes' and not self.done(target, 'computes', 'started'):
            self.gate(args, f'verify passed. Check the APIs (boot a test instance) before the hypervisors move to {target}.',
                      guarding=phase)

    def gate(self, args, prompt, confirm=None, guarding=None):
        """Pause for the operator; -y and --dry-run print the pause instead."""
        log.info('pause: %s', prompt)
        if args.yes or self.dry_run:
            log.info('not pausing (%s)', '-y' if args.yes else 'dry run')
            return
        self.gating = guarding
        try:
            answer = input(f'{prompt} ' + ('Type yes to continue: ' if confirm else 'Press Enter to continue. '))
        except EOFError:
            raise RunnerError('no terminal to answer the pause; run it in tmux, or pass -y')
        log.info('answer: %r', answer)
        if confirm and answer.strip() != confirm:
            raise RunnerError(f'stopped at the pause before {guarding}: the answer was not {confirm}')
        self.gating = None

    def resume_hint(self):
        """What to do after upgrade stopped in self.current."""
        if self.gating == 'controller-db':
            return (f'nothing has run on {self.db} yet; rerun upgrade when ready, '
                    'or roll back with openstack-upgrade --help-rollback')
        if self.gating == 'computes':
            return ('verify passed and no hypervisor has moved; rerun upgrade to resume, '
                    'or roll back (openstack-upgrade --help-rollback)')
        if self.current in ('computes', 'finalize'):
            return f'{self.current} stopped: fix the host and rerun upgrade to resume (fix forward)'
        return f'{self.current} stopped: rerun upgrade to resume, or see openstack-upgrade --help-rollback'

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
        if all(s['markers'] == [target] for s in statuses.values()):
            raise RunnerError(f'every node already runs {target}; set release to the next one and let them stage')
        unstaged = [h for h, s in statuses.items() if not s['release']['staged']]
        if unstaged:
            raise RunnerError(f'not staged for {target}: {", ".join(sorted(unstaged))}')
        self.node(self.db, 'precheck')

    def phase_stop(self, target, statuses, args):
        print(f'Set Nagios downtime for the {self.cloud} API checks and novnc now, and post the status.io notice.')
        for host in self.controllers:
            self.node(host, 'stop')

    def phase_backup(self, target, statuses, args):
        running = [f'{h} {u} ({state})' for h in self.controllers
                   for u, state in sorted(statuses[h]['units'].items()) if state not in ('inactive', 'failed')]
        if running:
            msg = 'OpenStack units are not stopped; rerun stop first:\n  ' + '\n  '.join(running)
            # A dry run stopped nothing, so the refusal is expected there
            if not self.dry_run:
                raise RunnerError(msg)
            print('would refuse:', msg)
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
        if not self.dry_run:
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
        if canaries and any(not os.path.exists(os.path.join(state, h)) for h in rest):
            self.gate(args, f'Canaries {", ".join(canaries)} are on {target}. Check them before the rest.',
                      guarding='the remaining hypervisors')
        batch = max(1, args.batch)
        for i in range(0, len(rest), batch):
            with concurrent.futures.ThreadPoolExecutor(max_workers=batch) as pool:
                futures = {h: pool.submit(one, h) for h in rest[i:i + batch]}
            failed = [f'{h} ({f.exception()})' for h, f in futures.items() if f.exception()]
            if failed:
                raise RunnerError(f'stopped after this batch failed: {", ".join(failed)}; fix them and rerun computes')

    def phase_finalize(self, target, statuses, args):
        for host in self.controllers:
            self.node(host, 'restart-nova')
        self.node(self.db, 'migrate')
        self.node(self.db, 'check')
        for host in self.controllers:
            self.ssh(host, 'cinc-client')

    def phase_rollback(self, target, statuses, args):
        # started, not done: a controller-db that failed part way may have synced the schema
        if (self.done(target, 'controller-db', 'started') or statuses[self.db]['transaction']) and not args.restored:
            print(ROLLBACK_HELP)
            raise RunnerError('controller-db started: restore the databases first, then rerun with --restored')
        touched = sorted(h for h, s in statuses.items() if s['transaction'])
        for host in touched:
            self.node(host, 'undo')
        self.retire_state(target)
        if self.unreachable:
            print(f'Not reached, so not undone: {", ".join(self.unreachable)}. Run openstack-node-upgrade undo '
                  'on each by hand; until then Chef refuses to converge them on the reverted bag.')
        print(f'Undone on {", ".join(touched) or "no host"}. Now set release back in the {self.cloud} '
              f'data bag item, then run: openstack-upgrade {self.cloud} rollback --converge')

    def retire_state(self, target):
        """Move this window's markers aside, so a retry starts again at precheck."""
        path = self.state_dir(target)
        dest = f'{path}.rolled-back-{time.strftime("%Y%m%dT%H%M%SZ", time.gmtime())}'
        if not os.listdir(path):
            os.rmdir(path)
            return
        if self.dry_run:
            print(f'would move {path} to {dest}')
            return
        os.rename(path, dest)
        log.info('moved the phase markers to %s', dest)

    def rollback_converge(self):
        # No status or target here: nodes disagree until this converge finishes
        failed = []
        for host in self.controllers + self.hypervisors:
            try:
                self.ssh(host, 'cinc-client')
            except RunnerError as e:
                log.error('%s', e)
                failed.append(host)
        if failed:
            raise RunnerError(f'cinc-client failed on {", ".join(failed)}; fix and converge them by hand')


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('cloud', help='the cloud, as its openstack data bag item (x86, arm, ppc64)')
    parser.add_argument('phase', choices=['status', 'rollback', 'upgrade'] + PHASES)
    parser.add_argument('-n', '--dry-run', action='store_true', help='print what would run on each host')
    parser.add_argument('--batch', type=int, default=2, help='hypervisors upgraded at once after the canaries')
    parser.add_argument('-y', '--yes', action='store_true', help="skip every pause: upgrade's gates and the canary check")
    parser.add_argument('--restored', action='store_true', help='rollback: the databases are already restored')
    parser.add_argument('--converge', action='store_true', help='rollback: the bag is reverted; run cinc-client')
    parser.add_argument('--help-rollback', action='store_true', help='print the rollback procedure and exit')
    if '--help-rollback' in sys.argv:
        print(ROLLBACK_HELP)
        return 0
    args = parser.parse_args()

    os.makedirs(LOG_DIR, exist_ok=True)
    transcript = None
    # status is read-only and run often; every other run keeps its whole output
    if args.phase != 'status':
        stamp = time.strftime('%Y%m%dT%H%M%SZ', time.gmtime())
        transcript = Transcript(os.path.join(LOG_DIR, f'{args.cloud}-{stamp}.log'))
        sys.stdout, sys.stderr = Tee(sys.stdout, transcript), Tee(sys.stderr, transcript)
    logging.basicConfig(level=logging.INFO, format='%(asctime)s %(levelname)s %(message)s', force=True,
                        handlers=[logging.StreamHandler(sys.stdout),
                                  logging.FileHandler(os.path.join(LOG_DIR, f'{args.cloud}.log'))])
    if transcript:
        log.info('full output: %s', transcript.path)
    runner = None
    agent = Agent()
    try:
        runner = Runner(args.cloud, dry_run=args.dry_run)
        # status and dry runs are short, so they keep the login's agent
        if args.phase != 'status' and not args.dry_run:
            if args.phase == 'upgrade':
                runner.require_terminal(args)
            agent.start()
        runner.run_phase(args.phase, args)
        return 0
    except KeyboardInterrupt:
        if runner and runner.upgrading and (runner.entered or runner.gating):
            log.error('interrupted: %s', runner.resume_hint())
        else:
            log.error('interrupted; rerun the same phase to resume')
        return 130
    except RunnerError as e:
        log.error('%s', e)
    except Exception:
        log.exception('unexpected error')
    finally:
        agent.stop()
    # No hint before an upgrade phase began: a missing precheck is its own whole answer
    if runner and runner.upgrading and (runner.entered or runner.gating):
        log.error('%s', runner.resume_hint())
    return 1


if __name__ == '__main__':
    sys.exit(main())
