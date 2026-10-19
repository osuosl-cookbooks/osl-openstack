#!/usr/bin/python3
"""One node's part of an OpenStack release upgrade window.

The jumphost runner (openstack-upgrade) calls these over ssh in order; each can
also be run by hand. Chef writes /etc/osl-openstack/release.json with the
installed and target releases; nothing here changes the data bag.

  status        JSON summary of this node
  stop          remove the cinc cron, wait out a running converge, stop every OpenStack unit
  install       save the running release's repo for undo, install the staged target
                release, recording the dnf transaction
  undo          roll the recorded transaction back from the saved repo
  precheck      (DB controller, before the window) gate the upgrade on yoga state
  backup        (DB controller, services stopped) dump every service database
  restore       (DB controller) load those dumps back; needs --yes
  check         run every *-status upgrade check
  migrate       (DB controller) run online data migrations to completion
  restart-nova  (controllers) restart nova so it drops its RPC version caps
"""

import argparse
import configparser
import fcntl
import glob
import gzip
import json
import logging
import os
import re
import shutil
import signal
import subprocess
import sys
import tempfile
import time
from urllib.parse import unquote

import dnf
import psutil
import rpm

try:
    import pymysql
except ImportError:  # only controllers get python3-PyMySQL
    pymysql = None

RELEASE_JSON = '/etc/osl-openstack/release.json'
STATE_DIR = '/var/lib/osl-openstack'
BACKUP_DIR = '/var/lib/osl-openstack/upgrade-backup'
CRON = '/etc/cron.d/chef-client'
# base's chef_client_cron runs cinc-client under `flock -n` on this lock
CHEF_LOCK = '/tmp/chef-client.lock'
CHEF_LOCK_WAIT = 3600
CHEF_LOCK_POLL = 10
REPO_DIR = '/etc/yum.repos.d'
ROLLBACK_REPO = 'OSL-openstack-rollback'
MAX_MIGRATION_BATCHES = 1000
NOVA_CONF = '/etc/nova/nova.conf'
# The yoga floor zed's nova refuses to start below (nova/objects/service.py:233-240)
MIN_COMPUTE_VERSION = 61

# Service, its status tool, and the user it runs as
STATUS_TOOLS = [
    ('keystone-status', 'keystone'), ('glance-status', 'glance'), ('placement-status', 'placement'),
    ('nova-status', 'nova'), ('cinder-status', 'cinder'), ('neutron-status', 'neutron'), ('heat-status', 'heat'),
]
MIGRATIONS = [('nova-manage', 'nova'), ('cinder-manage', 'cinder'), ('placement-manage', 'placement')]
# Config file, section and option naming each service database
DB_OPTIONS = [
    ('/etc/keystone/keystone.conf', 'database', 'connection'),
    ('/etc/glance/glance-api.conf', 'database', 'connection'),
    ('/etc/placement/placement.conf', 'placement_database', 'connection'),
    ('/etc/nova/nova.conf', 'api_database', 'connection'),
    ('/etc/nova/nova.conf', 'database', 'connection'),
    ('/etc/cinder/cinder.conf', 'database', 'connection'),
    ('/etc/neutron/neutron.conf', 'database', 'connection'),
    ('/etc/heat/heat.conf', 'database', 'connection'),
]
NOVA_RESTART = [
    ['openstack-nova-conductor'], ['openstack-nova-scheduler'],
    ['openstack-nova-api', 'openstack-nova-metadata'],
]

# SQLAlchemy 1.4's make_url pattern (engine/url.py); the cookbook writes raw passwords,
# which may hold / ? # that urllib.parse misreads
DB_URL = re.compile(r'''(?P<name>[\w\+]+)://
    (?:(?P<username>[^:/]*)(?::(?P<password>[^@]*))?@)?
    (?:(?:\[(?P<ipv6host>[^/\?]+)\]|(?P<ipv4host>[^/:\?]+))?(?::(?P<port>[^/\?]*))?)?
    (?:/(?P<database>[^\?]*))?(?:\?(?P<query>.*))?''', re.X)

log = logging.getLogger('openstack-node-upgrade')


class UpgradeError(Exception):
    pass


def run(cmd, check=True, capture=False, user=None, env=None):
    if user:
        cmd = ['runuser', '-u', user, '--'] + cmd
    log.debug('running: %s', ' '.join(cmd))
    try:
        res = subprocess.run(cmd, check=False, text=True, env=env,
                             stdout=subprocess.PIPE if capture else None,
                             stderr=subprocess.PIPE if capture else None)
    except FileNotFoundError:
        raise UpgradeError(f'{cmd[0]} is not installed')
    if check and res.returncode != 0:
        raise UpgradeError(f'{cmd[0] if not user else cmd[3]} exited {res.returncode}')
    return res


def release_state():
    try:
        with open(RELEASE_JSON) as f:
            return json.load(f)
    except FileNotFoundError:
        raise UpgradeError(f'{RELEASE_JSON} is missing; run cinc-client first')


def openstack_headers():
    """rpm headers of every installed osuosl-openstack-* package."""
    match = rpm.TransactionSet().dbMatch()
    match.pattern('name', rpm.RPMMIRE_GLOB, 'osuosl-openstack-*')
    return list(match)


def installed_markers():
    provides = (p for h in openstack_headers() for p in h[rpm.RPMTAG_PROVIDENAME])
    return sorted({m.group(1) for m in map(re.compile(r'^osuosl-openstack-release\((\S+)\)$').match, provides) if m})


def venv_headers():
    return [h for h in openstack_headers()
            if h[rpm.RPMTAG_NAME] not in ('osuosl-openstack-selinux', 'osuosl-openstack-cli')]


def venv_packages():
    return [h[rpm.RPMTAG_NAME] for h in venv_headers()]


def openstack_units():
    files = (f for h in venv_headers() for f in h[rpm.RPMTAG_FILENAMES])
    return sorted({os.path.basename(f) for f in files
                   if f.startswith('/usr/lib/systemd/system/') and f.endswith('.service')})


def last_transaction():
    """The newest dnf history id, or None on a node with no history."""
    base = dnf.Base()
    try:
        last = base.history.last()
        return last.tid if last else None
    finally:
        base.close()


def is_controller():
    return release_state().get('node_type') == 'controller'


def txn_file(target):
    return os.path.join(STATE_DIR, f'upgrade-{target}.txn')


def staged_marker(target):
    return os.path.join(STATE_DIR, f'staged-{target}')


def require_db_node():
    if not release_state().get('db_node'):
        raise UpgradeError('this is not the DB controller (release.json db_node is false)')


def openrc_env():
    env = dict(os.environ)
    with open('/root/openrc') as f:
        for line in f:
            m = re.match(r'\s*export\s+(OS_\w+)=(.*)$', line)
            if m:
                env[m.group(1)] = m.group(2).strip().strip('"\'')
    return env


def cmd_status(args):
    state = release_state()
    units = openstack_units()
    active = run(['systemctl', 'is-active'] + units, check=False, capture=True).stdout.split() if units else []
    txn = None
    if os.path.exists(txn_file(state['target'])):
        with open(txn_file(state['target'])) as f:
            txn = f.read().strip()
    print(json.dumps({
        'host': os.uname().nodename, 'release': state, 'markers': installed_markers(),
        'units': dict(zip(units, active)), 'transaction': txn,
        'cron': os.path.exists(CRON),
    }, indent=2, sort_keys=True))


def remove_cron():
    if os.path.exists(CRON):
        os.remove(CRON)
        log.info('removed %s; the next cinc-client run restores it', CRON)


def kill_cron_sleepers():
    """Kill a cron run still in its splay sleep, before it reaches cinc-client."""
    procs = {p.info['pid']: p.info for p in psutil.process_iter(['pid', 'ppid', 'name', 'cmdline'])}
    for pid, info in sorted(procs.items()):
        parent = procs.get(info['ppid'])
        # cmdline is None for a process psutil may not read
        if info['name'] != 'sleep' or not parent or CHEF_LOCK not in ' '.join(parent['cmdline'] or []):
            continue
        # The shell goes first: killing only the sleep lets it run cinc-client
        for victim in (info['ppid'], pid):
            try:
                os.kill(victim, signal.SIGTERM)
            except ProcessLookupError:
                pass
        log.info('killed a pending cinc cron run (shell %s, sleep %s)', info['ppid'], pid)


def hold_chef_lock():
    """Take the cron's cinc-client lock, waiting out a converge; return the fd holding it."""
    fd = os.open(CHEF_LOCK, os.O_RDWR | os.O_CREAT, 0o644)
    deadline = time.monotonic() + CHEF_LOCK_WAIT
    while True:
        try:
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
            return fd
        except BlockingIOError:
            if time.monotonic() >= deadline:
                os.close(fd)
                raise UpgradeError(f'cinc-client still holds {CHEF_LOCK} after {CHEF_LOCK_WAIT}s; nothing was stopped')
            log.info('waiting for the running cinc-client to finish')
            time.sleep(CHEF_LOCK_POLL)


def cmd_stop(args):
    remove_cron()
    kill_cron_sleepers()
    # While this holds the lock, a cron run that wakes up fails its flock -n
    fd = hold_chef_lock()
    try:
        # The converge that just finished put the cron back
        remove_cron()
        kill_cron_sleepers()
        units = openstack_units() + (['httpd.service'] if is_controller() else [])
        log.info('stopping %s', ' '.join(units))
        if units:
            run(['systemctl', 'stop'] + units)
    finally:
        os.close(fd)


def cmd_install(args):
    state = release_state()
    target = state['target']
    if installed_markers() == [target]:
        log.info('%s is already installed', target)
        return
    if not os.path.exists(staged_marker(target)):
        raise UpgradeError(f'{target} is not staged here; run cinc-client and check the repo is published')
    save_rollback_repo(state['installed'])
    before = last_transaction()
    run(['dnf', '-y', f'--enablerepo=OSL-openstack-{target}', 'upgrade', 'osuosl-openstack-*'])
    tid = last_transaction()
    # An upgrade that changed nothing would leave someone else's transaction for undo
    if tid is None or tid == before:
        raise UpgradeError(f'dnf upgrade recorded no transaction; {target} was not installed')
    with open(txn_file(target), 'w') as f:
        f.write(f'{tid}\n')
    # undo needs every replaced version still published, OpenStack or not
    out = run(['dnf', 'history', 'info', str(tid)], capture=True).stdout
    log.info('dnf transaction %s:\n%s', tid, out)
    log.info('installed %s in dnf transaction %s; markers now %s', target, tid, installed_markers())
    # Staging kept its download (keepcache); the transaction is done with it
    run(['dnf', 'clean', 'packages'])


def save_rollback_repo(installed):
    """Copy the running release's repo, disabled, so undo still reaches it after the converge."""
    src = os.path.join(REPO_DIR, 'OSL-openstack.repo')
    live = configparser.ConfigParser(interpolation=None)
    if not live.read(src) or not live.has_section('OSL-openstack'):
        raise UpgradeError(f'{src} has no [OSL-openstack] repo')
    baseurl = live.get('OSL-openstack', 'baseurl', fallback='')
    if f'/openstack/{installed}/' not in baseurl:
        raise UpgradeError(f'{src} points at {baseurl}, not the installed {installed}')
    saved = configparser.ConfigParser(interpolation=None)
    saved[ROLLBACK_REPO] = dict(live['OSL-openstack'])
    saved[ROLLBACK_REPO]['name'] = f'{live["OSL-openstack"].get("name", "OSL-openstack")} (for undo)'
    saved[ROLLBACK_REPO]['enabled'] = '0'
    with open(os.path.join(REPO_DIR, f'{ROLLBACK_REPO}.repo'), 'w') as f:
        saved.write(f)
    log.info('saved the %s repo as %s', installed, ROLLBACK_REPO)


def cmd_undo(args):
    target = release_state()['target']
    path = txn_file(target)
    if not os.path.exists(path):
        raise UpgradeError(f'no recorded {target} transaction in {path}')
    if not os.path.exists(os.path.join(REPO_DIR, f'{ROLLBACK_REPO}.repo')):
        raise UpgradeError(f'no {ROLLBACK_REPO} repo; install saves it, so the old release has no source')
    with open(path) as f:
        txn = f.read().strip()
    run(['dnf', '-y', f'--enablerepo={ROLLBACK_REPO}', 'history', 'undo', txn])
    os.rename(path, path + '.undone')
    log.info('undid dnf transaction %s; markers now %s', txn, installed_markers())


def parse_db_url(url):
    """host, port, user, password and database of a SQLAlchemy URL, or None."""
    m = DB_URL.match(url)
    if not m or (m['port'] and not m['port'].isdigit()):
        return None
    return {'host': m['ipv4host'] or m['ipv6host'], 'port': int(m['port']) if m['port'] else 3306,
            'user': unquote(m['username'] or ''), 'password': unquote(m['password'] or ''),
            'database': m['database'] or ''}


def cnf_quote(value):
    # Unquoted, the option-file parser cuts a value at # and mangles \ and quotes
    return '"' + value.replace('\\', '\\\\').replace('"', '\\"') + '"'


def mysql_conf(url, directory):
    """Write a 0600 client option file for a SQLAlchemy URL; return (path, database)."""
    u = parse_db_url(url)
    if not u or not u['host']:
        raise UpgradeError(f'cannot parse a database URL for {directory}')
    fd, path = tempfile.mkstemp(prefix='.my-', suffix='.cnf', dir=directory)
    with os.fdopen(fd, 'w') as f:
        f.write('[client]\n')
        f.write(f'host={u["host"]}\nport={u["port"]}\n')
        f.write(f'user={cnf_quote(u["user"])}\npassword={cnf_quote(u["password"])}\n')
    return path, u['database']


def db_query(url, sql, params=()):
    """Rows of one query against a SQLAlchemy URL's database."""
    if pymysql is None:
        raise UpgradeError('python3-PyMySQL is not installed')
    u = parse_db_url(url)
    if not u or not u['host']:
        raise UpgradeError('cannot parse a nova database URL')
    try:
        db = pymysql.connect(host=u['host'], port=u['port'], user=u['user'],
                             password=u['password'], database=u['database'])
    except pymysql.MySQLError as e:
        raise UpgradeError(f'cannot connect to {u["host"]}/{u["database"]}: {e}')
    try:
        with db.cursor() as cur:
            cur.execute(sql, params)
            return cur.fetchall()
    finally:
        db.close()


def nova_cell_urls():
    """Cell database URLs from the nova API DB."""
    conf = configparser.ConfigParser(interpolation=None)
    if not conf.read(NOVA_CONF):
        raise UpgradeError(f'{NOVA_CONF} is missing')
    rows = db_query(conf.get('api_database', 'connection'), 'SELECT name, database_connection FROM cell_mappings')
    # A templated cell URL ({scheme}://...) means nova fills it from [database]
    return {name: (conf.get('database', 'connection') if '{' in url else url) for name, url in rows}


def old_computes(cells):
    """(cell, host, version) of every live nova-compute below MIN_COMPUTE_VERSION."""
    old = []
    for name, url in sorted(cells.items()):
        if not (parse_db_url(url) or {}).get('host'):
            continue
        rows = db_query(url, "SELECT host, version FROM services WHERE `binary`='nova-compute' "
                             "AND deleted=0 AND forced_down=0 AND version < %s", (MIN_COMPUTE_VERSION,))
        old += [(name, host, version) for host, version in rows]
    return old


def cmd_precheck(args):
    require_db_node()
    if not os.path.exists(NOVA_CONF):
        raise UpgradeError(f'precheck needs {NOVA_CONF}; nova is not configured here')
    problems = []
    for cell, host, version in old_computes(nova_cell_urls()):
        problems.append(f'nova-compute on {host} ({cell}) is at service version {version}, below {MIN_COMPUTE_VERSION}')
    log.info('running the yoga online data migrations to completion')
    for tool, user in MIGRATIONS[:2]:
        run_migrations(tool, user)
    debris = run(['/root/nova-resize-debris-check.py', '--exit-code'], check=False, env=openrc_env())
    if debris.returncode != 0:
        problems.append(f'resize-debris-check exited {debris.returncode}; clear the debris first')
    if problems:
        raise UpgradeError('precheck failed:\n  ' + '\n  '.join(problems))
    log.info('precheck passed')


def dump_flags():
    version = run(['mysqldump', '--version'], capture=True).stdout
    flags = ['--single-transaction', '--routines', '--triggers', '--add-drop-database']
    # MySQL 8's client against MariaDB or with GTIDs needs these; MariaDB's rejects them
    if 'MariaDB' not in version:
        flags += ['--column-statistics=0', '--set-gtid-purged=OFF']
    return flags


def service_db_urls():
    urls = {}
    for path, section, option in DB_OPTIONS:
        c = configparser.ConfigParser(interpolation=None)
        if c.read(path) and c.has_option(section, option):
            url = c.get(section, option)
            u = parse_db_url(url)
            if u:
                urls[u['database']] = url
    if not os.path.exists(NOVA_CONF):
        log.info('nova is not configured here; skipping the nova cell databases')
        return urls
    for url in nova_cell_urls().values():
        u = parse_db_url(url)
        if u and u['host']:
            urls[u['database']] = url
    return urls


def cmd_backup(args):
    require_db_node()
    target = release_state()['target']
    directory = os.path.join(BACKUP_DIR, target)
    os.makedirs(directory, mode=0o700, exist_ok=True)
    flags = dump_flags()
    for db, url in sorted(service_db_urls().items()):
        cnf, name = mysql_conf(url, directory)
        out = os.path.join(directory, f'{name}.sql.gz')
        log.info('dumping %s to %s', name, out)
        with gzip.open(out + '.part', 'wb') as gz:
            proc = subprocess.Popen(['mysqldump', f'--defaults-extra-file={cnf}'] + flags + ['--databases', name],
                                    stdout=subprocess.PIPE)
            shutil.copyfileobj(proc.stdout, gz)
            if proc.wait() != 0:
                raise UpgradeError(f'mysqldump of {name} failed')
        os.rename(out + '.part', out)
        os.rename(cnf, os.path.join(directory, f'.{name}.cnf'))
    log.info('backups are in %s', directory)


def cmd_restore(args):
    require_db_node()
    directory = os.path.join(BACKUP_DIR, release_state()['target'])
    dumps = sorted(glob.glob(os.path.join(directory, '*.sql.gz')))
    if not dumps:
        raise UpgradeError(f'no dumps in {directory}')
    for dump in dumps:
        name = os.path.basename(dump)[:-len('.sql.gz')]
        print(f'zcat {dump} | mysql --defaults-extra-file={directory}/.{name}.cnf')
    if not args.yes:
        print('These replace each database with its pre-upgrade dump. Run again with --yes once every service is stopped.')
        return
    for dump in dumps:
        name = os.path.basename(dump)[:-len('.sql.gz')]
        log.info('restoring %s', name)
        with gzip.open(dump, 'rb') as gz:
            proc = subprocess.Popen(['mysql', f'--defaults-extra-file={directory}/.{name}.cnf'], stdin=subprocess.PIPE)
            shutil.copyfileobj(gz, proc.stdin)
            proc.stdin.close()
            if proc.wait() != 0:
                raise UpgradeError(f'restoring {name} failed')


def cmd_check(args):
    failed = []
    for tool, user in STATUS_TOOLS:
        if not os.path.exists(f'/usr/bin/{tool}'):
            continue
        rc = run([tool, 'upgrade', 'check'], check=False, user=user).returncode
        # oslo.upgradecheck: 0 success, 1 warning, 2 failure, 255 crashed
        if rc >= 2:
            failed.append(f'{tool} ({rc})')
    if failed:
        raise UpgradeError('upgrade checks failed: ' + ', '.join(failed))
    log.info('upgrade checks passed')


def run_migrations(tool, user):
    for _ in range(MAX_MIGRATION_BATCHES):
        rc = run([tool, 'db', 'online_data_migrations', '--max-count', '1000'], check=False, user=user).returncode
        # 1 means a batch ran and more may remain; 0 is done; 2 is errors
        if rc == 0:
            return
        if rc != 1:
            raise UpgradeError(f'{tool} online_data_migrations exited {rc}')
    raise UpgradeError(f'{tool} online_data_migrations still reports work after {MAX_MIGRATION_BATCHES} batches')


def cmd_migrate(args):
    require_db_node()
    for tool, user in MIGRATIONS:
        log.info('%s online_data_migrations', tool)
        run_migrations(tool, user)


def cmd_restart_nova(args):
    if not is_controller():
        raise UpgradeError('restart-nova is for controllers')
    for units in NOVA_RESTART:
        log.info('restarting %s', ' '.join(units))
        run(['systemctl', 'restart'] + units)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('-v', '--verbose', action='store_true')
    sub = parser.add_subparsers(dest='command', required=True)
    for name in ('status', 'stop', 'install', 'undo', 'precheck', 'backup', 'check', 'migrate', 'restart-nova'):
        sub.add_parser(name)
    sub.add_parser('restore').add_argument('--yes', action='store_true')
    args = parser.parse_args()

    logging.basicConfig(level=logging.DEBUG if args.verbose else logging.INFO,
                        format='%(asctime)s %(levelname)s %(message)s',
                        handlers=[logging.StreamHandler(sys.stderr),
                                  logging.FileHandler('/var/log/openstack-node-upgrade.log')])
    try:
        globals()['cmd_' + args.command.replace('-', '_')](args)
    except UpgradeError as e:
        log.error('%s', e)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
