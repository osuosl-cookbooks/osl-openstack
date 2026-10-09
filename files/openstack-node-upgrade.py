#!/usr/bin/python3
"""One node's part of an OpenStack release upgrade window.

The jumphost runner (openstack-upgrade) calls these over ssh in order; each can
also be run by hand. Chef writes /etc/osl-openstack/release.json with the
installed and target releases; nothing here changes the data bag.

  status        JSON summary of this node
  stop          remove the cinc cron and stop every OpenStack unit
  install       install the staged target release, recording the dnf transaction
  undo          roll the recorded transaction back
  precheck      (DB controller, before the window) gate the upgrade on yoga state
  backup        (DB controller, services stopped) dump every service database
  restore       (DB controller) load those dumps back; needs --yes
  check         run every *-status upgrade check
  migrate       (DB controller) run online data migrations to completion
  restart-nova  (controllers) restart nova so it drops its RPC version caps
"""

import argparse
import configparser
import glob
import gzip
import json
import logging
import os
import re
import shutil
import subprocess
import sys
import tempfile
from urllib.parse import unquote, urlparse

RELEASE_JSON = '/etc/osl-openstack/release.json'
STATE_DIR = '/var/lib/osl-openstack'
BACKUP_DIR = '/root/openstack-upgrade-backup'
CRON = '/etc/cron.d/chef-client'
NOVA_PY = '/opt/openstack/nova-controller/bin/python'
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

log = logging.getLogger('openstack-node-upgrade')


class UpgradeError(Exception):
    pass


def run(cmd, check=True, capture=False, user=None, env=None):
    if user:
        cmd = ['runuser', '-u', user, '--'] + cmd
    log.debug('running: %s', ' '.join(cmd))
    res = subprocess.run(cmd, check=False, text=True, env=env,
                         stdout=subprocess.PIPE if capture else None,
                         stderr=subprocess.PIPE if capture else None)
    if check and res.returncode != 0:
        raise UpgradeError(f'{cmd[0] if not user else cmd[3]} exited {res.returncode}')
    return res


def release_state():
    try:
        with open(RELEASE_JSON) as f:
            return json.load(f)
    except FileNotFoundError:
        raise UpgradeError(f'{RELEASE_JSON} is missing; run cinc-client first')


def installed_markers():
    out = run(['rpm', '-qa', '--qf', '[%{PROVIDENAME}\n]', 'osuosl-openstack-*'], capture=True).stdout
    return sorted(set(re.findall(r'^osuosl-openstack-release\((\S+)\)$', out, re.M)))


def venv_packages():
    out = run(['rpm', '-qa', '--qf', '%{NAME}\n', 'osuosl-openstack-*'], capture=True).stdout.split()
    return [p for p in out if p not in ('osuosl-openstack-selinux', 'osuosl-openstack-cli')]


def openstack_units():
    pkgs = venv_packages()
    if not pkgs:
        return []
    files = run(['rpm', '-ql'] + pkgs, capture=True).stdout.split()
    return sorted({os.path.basename(f) for f in files
                   if f.startswith('/usr/lib/systemd/system/') and f.endswith('.service')})


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


def cmd_stop(args):
    if os.path.exists(CRON):
        os.remove(CRON)
        log.info('removed %s; the next cinc-client run restores it', CRON)
    units = openstack_units() + (['httpd.service'] if is_controller() else [])
    log.info('stopping %s', ' '.join(units))
    if units:
        run(['systemctl', 'stop'] + units)


def cmd_install(args):
    state = release_state()
    target = state['target']
    if installed_markers() == [target]:
        log.info('%s is already installed', target)
        return
    if not os.path.exists(staged_marker(target)):
        raise UpgradeError(f'{target} is not staged here; run cinc-client and check the repo is published')
    run(['dnf', '-y', f'--enablerepo=OSL-openstack-{target}', 'upgrade', 'osuosl-openstack-*'])
    out = run(['dnf', 'history', 'info', 'last'], capture=True).stdout
    m = re.search(r'^Transaction ID\s*:\s*(\d+)', out, re.M)
    if not m:
        raise UpgradeError('could not read the dnf transaction id')
    with open(txn_file(target), 'w') as f:
        f.write(m.group(1) + '\n')
    log.info('installed %s in dnf transaction %s; markers now %s', target, m.group(1), installed_markers())
    # Staging kept its download (keepcache); the transaction is done with it
    run(['dnf', 'clean', 'packages'])


def cmd_undo(args):
    target = release_state()['target']
    path = txn_file(target)
    if not os.path.exists(path):
        raise UpgradeError(f'no recorded {target} transaction in {path}')
    with open(path) as f:
        txn = f.read().strip()
    run(['dnf', 'history', 'undo', '-y', txn])
    os.rename(path, path + '.undone')
    log.info('undid dnf transaction %s; markers now %s', txn, installed_markers())


def mysql_conf(url, directory):
    """Write a 0600 client option file for a SQLAlchemy URL; return (path, database)."""
    u = urlparse(url)
    fd, path = tempfile.mkstemp(prefix='.my-', suffix='.cnf', dir=directory)
    with os.fdopen(fd, 'w') as f:
        f.write('[client]\n')
        f.write(f'host={u.hostname}\nport={u.port or 3306}\n')
        f.write(f'user={unquote(u.username or "")}\npassword={unquote(u.password or "")}\n')
    return path, u.path.lstrip('/')


def nova_cell_urls():
    """Cell database URLs from the nova API DB, read with the nova venv's pymysql."""
    code = r'''
import configparser, json, pymysql
from urllib.parse import urlparse, unquote
c = configparser.ConfigParser(interpolation=None); c.read('/etc/nova/nova.conf')
u = urlparse(c['api_database']['connection'])
db = pymysql.connect(host=u.hostname, port=u.port or 3306, user=unquote(u.username),
                     password=unquote(u.password), database=u.path.lstrip('/'))
with db.cursor() as cur:
    cur.execute("SELECT name, database_connection FROM cell_mappings")
    print(json.dumps({n: d for n, d in cur.fetchall()}))
'''
    out = run([NOVA_PY, '-c', code], capture=True).stdout
    conf = configparser.ConfigParser(interpolation=None)
    conf.read('/etc/nova/nova.conf')
    # A templated cell URL ({scheme}://...) means nova fills it from [database]
    return {name: (conf.get('database', 'connection') if '{' in url else url)
            for name, url in json.loads(out).items()}


def cmd_precheck(args):
    require_db_node()
    problems = []
    code = r'''
import json, sys, pymysql
from urllib.parse import urlparse, unquote
old = []
for name, url in json.load(sys.stdin).items():
    u = urlparse(url)
    if not u.hostname:
        continue
    db = pymysql.connect(host=u.hostname, port=u.port or 3306, user=unquote(u.username),
                         password=unquote(u.password), database=u.path.lstrip('/'))
    with db.cursor() as cur:
        cur.execute("SELECT host, version FROM services WHERE `binary`='nova-compute' "
                    "AND deleted=0 AND forced_down=0 AND version < %s", (int(sys.argv[1]),))
        old += [[name, h, v] for h, v in cur.fetchall()]
print(json.dumps(old))
'''
    cells = nova_cell_urls()
    res = subprocess.run([NOVA_PY, '-c', code, str(MIN_COMPUTE_VERSION)], input=json.dumps(cells),
                         text=True, capture_output=True, check=False)
    if res.returncode != 0:
        raise UpgradeError('the compute version query failed')
    for cell, host, version in json.loads(res.stdout):
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
            urls[urlparse(url).path.lstrip('/')] = url
    for url in nova_cell_urls().values():
        u = urlparse(url)
        if u.hostname:
            urls[u.path.lstrip('/')] = url
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
    while True:
        rc = run([tool, 'db', 'online_data_migrations', '--max-count', '1000'], check=False, user=user).returncode
        # 1 means a batch ran and more may remain; 0 is done; 2 is errors
        if rc == 0:
            return
        if rc != 1:
            raise UpgradeError(f'{tool} online_data_migrations exited {rc}')


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
