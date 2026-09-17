#!/usr/bin/env python3
"""Draft a maintenance notice for everyone affected by taking compute hosts down.

Finds the instances on one or more hypervisors, works out who should hear about
it (instance owners plus the members of the affected projects, with Keystone
groups expanded), and renders a notice from a template. It only prints; nothing
is ever sent.

Usage:
    maintenance-notice.py [options] --date DATE HOST [HOST ...]

Requires admin OpenStack credentials in the environment (OS_* or OS_CLOUD).
"""

import argparse
import csv
import datetime
import os
import string
import sys
import textwrap

import openstack
from keystoneauth1 import exceptions as ks_exc
from openstack import exceptions as os_exc

DEFAULT_TEMPLATE_DIR = '/root/nova-maintenance-templates'
DEFAULT_TEMPLATE = 'reboot'
DEFAULT_MEMBER_ROLES = ('member', '_member_')
DEFAULT_IGNORED_USERS = ('admin',)
DEFAULT_IGNORED_PROJECTS = ('test-kitchen', 'osl', 'admin', 'OSL PowerCI')
DEFAULT_WINDOW = '8:00 AM - 5:00 PM Pacific'
DEFAULT_SUPPORT_EMAIL = 'support@osuosl.org'

DATE_FORMATS = ('%m/%d/%Y', '%m/%d/%y', '%Y-%m-%d', '%B %d, %Y', '%b %d, %Y',
                '%B %d %Y', '%b %d %Y')
DATE_FORMATS_NO_YEAR = ('%m/%d', '%B %d', '%b %d')


class NoticeError(Exception):
    """Anything that should end the run with a message rather than a traceback."""


# --------------------------------------------------------------------- input

def parse_args(argv=None):
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('hosts', nargs='*', metavar='HOST',
                    help='one or more hypervisor hostnames going down')
    ap.add_argument('-d', '--date', help='date of the maintenance, e.g. "2026-02-05" or "Feb 5"')
    ap.add_argument('-w', '--window', default=DEFAULT_WINDOW,
                    help='maintenance window text (default: %(default)s)')
    ap.add_argument('-t', '--template', default=DEFAULT_TEMPLATE,
                    help='template name or path to a template file (default: %(default)s)')
    ap.add_argument('--template-dir', default=os.environ.get('MAINTENANCE_TEMPLATE_DIR',
                                                             DEFAULT_TEMPLATE_DIR),
                    help='directory holding the .txt templates (default: %(default)s)')
    ap.add_argument('--list-templates', action='store_true',
                    help='list the available templates and exit')
    ap.add_argument('--set', action='append', default=[], metavar='KEY=VALUE',
                    dest='extra_vars',
                    help='extra template placeholder, repeatable, e.g. --set ticket=RT12345')
    ap.add_argument('--support-email', default=DEFAULT_SUPPORT_EMAIL,
                    help='support address used by the templates (default: %(default)s)')

    out = ap.add_mutually_exclusive_group()
    out.add_argument('--emails-only', action='store_true',
                     help='print one address per line, for piping into a mail client')
    out.add_argument('--csv', action='store_true', dest='as_csv',
                     help='print a CSV of recipients and affected instances')
    out.add_argument('--details', action='store_true',
                     help='print a contact breakdown instead of the drafted notice')

    ap.add_argument('--no-project-members', action='store_true',
                    help='notify only instance owners, not everyone on the project')
    ap.add_argument('--no-groups', action='store_true',
                    help='do not expand Keystone group role assignments into their members')
    ap.add_argument('--member-role', action='append', default=None, metavar='ROLE',
                    help='project role that counts as a member, repeatable (default: %s)'
                         % ', '.join(DEFAULT_MEMBER_ROLES))
    ap.add_argument('--ignore-user', action='append', default=None, metavar='NAME',
                    help='skip this username, repeatable (default: %s)'
                         % ', '.join(DEFAULT_IGNORED_USERS))
    ap.add_argument('--ignore-project', action='append', default=None, metavar='NAME',
                    help='skip instances and members of this project, repeatable (default: %s)'
                         % ', '.join(DEFAULT_IGNORED_PROJECTS))
    ap.add_argument('--ignore-domain', action='append', default=[], metavar='DOMAIN',
                    help='skip addresses in this email domain, repeatable')
    ap.add_argument('--include-no-email', action='store_true',
                    help='also report users who have no address on file')

    args = ap.parse_args(argv)
    # argparse 'append' extends the default rather than replacing it, which
    # would make the defaults impossible to switch off; apply them by hand.
    if args.member_role is None:
        args.member_role = list(DEFAULT_MEMBER_ROLES)
    if args.ignore_user is None:
        args.ignore_user = list(DEFAULT_IGNORED_USERS)
    if args.ignore_project is None:
        args.ignore_project = list(DEFAULT_IGNORED_PROJECTS)
    if not args.list_templates:
        if not args.hosts:
            ap.error('at least one HOST is required')
        if not args.date:
            ap.error('--date is required')
    return args


def parse_date(text):
    """Parse a date written any reasonable way into 'Mon, February 9, 2026'.

    Raises NoticeError rather than passing an unparsable string through to a
    notice that goes out to customers.
    """
    text = (text or '').strip()
    for fmt in DATE_FORMATS:
        try:
            return format_date(datetime.datetime.strptime(text, fmt))
        except ValueError:
            continue
    year = datetime.date.today().year
    for fmt in DATE_FORMATS_NO_YEAR:
        try:
            return format_date(datetime.datetime.strptime(
                '%s %d' % (text, year), '%s %%Y' % fmt))
        except ValueError:
            continue
    raise NoticeError(
        "could not read the date %r; try 2026-02-05, 2/5/2026 or 'February 5, 2026'" % text)


def format_date(dt):
    # built by hand because strftime's %-d is a glibc extension
    return '%s, %s %d, %d' % (dt.strftime('%a'), dt.strftime('%B'), dt.day, dt.year)


def parse_extra_vars(pairs):
    extra = {}
    for pair in pairs:
        if '=' not in pair:
            raise NoticeError('--set expects KEY=VALUE, got %r' % pair)
        key, _, value = pair.partition('=')
        key = key.strip()
        if not key.isidentifier():
            raise NoticeError('--set key %r is not a valid placeholder name' % key)
        extra[key] = value
    return extra


# ----------------------------------------------------------------- templates

def template_path(name, template_dir):
    """Resolve a template name or path to a readable file."""
    for candidate in (name, os.path.join(template_dir, name),
                      os.path.join(template_dir, '%s.txt' % name)):
        if os.path.isfile(candidate):
            return candidate
    raise NoticeError('no template %r in %s (use --list-templates to see what is there)'
                      % (name, template_dir))


def available_templates(template_dir):
    try:
        names = sorted(f[:-4] for f in os.listdir(template_dir) if f.endswith('.txt'))
    except OSError:
        return []
    return names


def load_template(path):
    """Split a template file into (subject, body).

    A leading 'Subject:' line is taken as the subject and removed from the body.
    """
    with open(path) as fh:
        text = fh.read()
    subject = None
    lines = text.splitlines()
    if lines and lines[0].lower().startswith('subject:'):
        subject = lines[0].split(':', 1)[1].strip()
        lines = lines[1:]
        while lines and not lines[0].strip():
            lines.pop(0)
    return subject, '\n'.join(lines).strip('\n')


def wrap_body(text, width=79):
    """Split over-long lines after substitution, without joining any.

    A long host list can push a template line well past 80 columns. Lines are
    only ever split, never merged, so field lists and indented blocks such as
    the instance listing survive untouched, and a template hand-wrapped at the
    usual width passes through unchanged.
    """
    out = []
    for line in text.split('\n'):
        if len(line) <= width or line[:1].isspace():
            out.append(line)
            continue
        out.extend(textwrap.wrap(line, width=width, break_long_words=False,
                                 break_on_hyphens=False) or [line])
    return '\n'.join(out)


def render(text, variables, what):
    if text is None:
        return None
    try:
        return string.Template(text).substitute(variables)
    except KeyError as e:
        raise NoticeError('%s uses unknown placeholder $%s; available: %s'
                          % (what, e.args[0], ', '.join(sorted(variables))))
    except ValueError as e:
        raise NoticeError('%s has a malformed placeholder: %s (use $$ for a literal $)'
                          % (what, e))


# ------------------------------------------------------------------ openstack

def known_compute_hosts(conn):
    return {svc.host for svc in conn.compute.services(binary='nova-compute')}


def find_servers(conn, hosts):
    """Return {host: [servers]} for the given hosts, in the order asked for."""
    found = {}
    for host in hosts:
        found[host] = list(conn.compute.servers(
            details=True, all_projects=True, compute_host=host))
    return found


def resolve_projects(conn, names):
    """Map project names to ids, ignoring names that do not resolve."""
    ids = set()
    for name in names:
        project = conn.identity.find_project(name, ignore_missing=True)
        if project is not None:
            ids.add(project.id)
    return ids


def project_names(conn, project_ids):
    names = {}
    for project_id in project_ids:
        try:
            names[project_id] = conn.identity.get_project(project_id).name
        except (os_exc.ResourceNotFound, os_exc.ForbiddenException):
            names[project_id] = 'Unknown (%s)' % project_id
    return names


def lookup_user(conn, user_id, cache):
    """Return {'id', 'name', 'email', 'enabled'}; cached, never raises."""
    if user_id in cache:
        return cache[user_id]
    try:
        user = conn.identity.get_user(user_id)
        info = {'id': user_id, 'name': user.name,
                'email': (getattr(user, 'email', None) or '').strip() or None,
                'enabled': bool(getattr(user, 'is_enabled', True))}
    except os_exc.ResourceNotFound:
        info = {'id': user_id, 'name': 'Unknown (%s)' % user_id, 'email': None, 'enabled': False}
    except os_exc.ForbiddenException:
        info = {'id': user_id, 'name': 'Access denied (%s)' % user_id,
                'email': None, 'enabled': False}
    cache[user_id] = info
    return info


def project_member_ids(conn, project_id, member_roles, expand_groups=True):
    """User ids holding one of member_roles on a project.

    Keystone's 'effective' mode expands group assignments into one assignment
    per group member, so groups need no extra lookup. Without it only direct
    user assignments are returned.
    """
    query = {'scope_project_id': project_id, 'include_names': True}
    if expand_groups:
        query['effective'] = True
    ids = set()
    try:
        # the SDK hands back a lazy generator, so the request only fires on
        # iteration; force it inside the guard or a deleted project escapes it
        assignments = list(conn.identity.role_assignments(**query))
    except (os_exc.ResourceNotFound, os_exc.ForbiddenException):
        return ids
    for assignment in assignments:
        user = getattr(assignment, 'user', None)
        if not user:
            continue  # a group assignment, only seen when not expanding
        role = getattr(assignment, 'role', None) or {}
        if role.get('name') not in member_roles:
            continue
        user_id = user.get('id')
        if user_id:
            ids.add(user_id)
    return ids


# ----------------------------------------------------------------- recipients

def collect_recipients(conn, servers, args, cache):
    """Work out who to contact.

    Returns (recipients, skipped) where recipients is
    {user_id: {'name','email','servers','projects','owner'}} and skipped lists
    users deliberately left out, with the reason.
    """
    recipients = {}
    skipped = []

    def entry(info):
        return recipients.setdefault(info['id'], {
            'name': info['name'], 'email': info['email'], 'user_id': info['id'],
            'servers': [], 'projects': set(), 'owner': False})

    # Instance owners. A disabled or unresolvable owner is not a recipient, but
    # their project still counts as affected so its members are still told, and
    # they are listed as skipped so an instance with no reachable owner shows up.
    unreachable = {}
    for server in servers:
        info = lookup_user(conn, server.user_id, cache)
        if not info['enabled']:
            item = unreachable.setdefault(info['id'], {
                'name': info['name'], 'email': info['email'], 'user_id': info['id'],
                'servers': [], 'projects': set(), 'owner': True,
                'reason': 'account disabled or unresolvable'})
            item['servers'].append({'name': server.name, 'id': server.id,
                                    'status': server.status, 'project': server.project_id})
            item['projects'].add(server.project_id)
            continue
        item = entry(info)
        item['owner'] = True
        item['servers'].append({'name': server.name, 'id': server.id,
                                'status': server.status, 'project': server.project_id})
        item['projects'].add(server.project_id)

    skipped.extend(unreachable.values())

    # Everyone else on the affected projects.
    if not args.no_project_members:
        for project_id in sorted({s.project_id for s in servers}):
            for user_id in project_member_ids(conn, project_id, args.member_role,
                                              expand_groups=not args.no_groups):
                info = lookup_user(conn, user_id, cache)
                if not info['enabled']:
                    continue
                entry(info)['projects'].add(project_id)

    # Exclusions. Dropping the whole entry, not just the address, so an ignored
    # user can never reach the recipient line.
    ignored_users = set(args.ignore_user)
    ignored_domains = {d.lower().lstrip('@') for d in args.ignore_domain}
    for user_id, item in list(recipients.items()):
        reason = None
        if item['name'] in ignored_users:
            reason = 'ignored user'
        elif not item['email']:
            reason = 'no email address on file'
        elif item['email'].split('@')[-1].lower() in ignored_domains:
            reason = 'ignored domain'
        if reason:
            skipped.append(dict(item, reason=reason))
            del recipients[user_id]
    return recipients, skipped


def sorted_emails(recipients):
    seen = {}
    for item in recipients.values():
        if item['email']:
            seen.setdefault(item['email'].lower(), item['email'])
    return [seen[key] for key in sorted(seen)]


# --------------------------------------------------------------------- output

def host_label(hosts):
    if len(hosts) == 1:
        return 'hypervisor node %s' % hosts[0]
    return 'hypervisor nodes %s and %s' % (', '.join(hosts[:-1]), hosts[-1])


def format_instance_list(servers_by_host, names, indent='  '):
    """Instances grouped by project, and by host as well when there are several."""
    multi = sum(1 for items in servers_by_host.values() if items) > 1
    blocks = []
    for host, servers in servers_by_host.items():
        if not servers:
            continue
        pad = indent + ('  ' if multi else '')
        lines = ['%s%s:' % (indent, host)] if multi else []
        by_project = {}
        for server in servers:
            by_project.setdefault(names.get(server.project_id, server.project_id), []) \
                .append(server)
        for project in sorted(by_project):
            lines.append('%s%s:' % (pad, project))
            for server in sorted(by_project[project], key=lambda s: s.name or ''):
                lines.append('%s  - %s (%s)' % (pad, server.name, server.status))
            lines.append('')
        blocks.append('\n'.join(lines).rstrip())
    return '\n\n'.join(blocks)


def print_notice(recipients, subject, body):
    rule = '=' * 60
    print(rule)
    print('EMAIL RECIPIENTS')
    print(rule)
    print(', '.join(sorted_emails(recipients)))
    print()
    if subject:
        print(rule)
        print('SUGGESTED SUBJECT')
        print(rule)
        print(subject)
        print()
    print(rule)
    print('EMAIL BODY')
    print(rule)
    print()
    print(body)
    print()


def print_details(args, recipients, skipped, servers_by_host, names):
    rule = '=' * 60
    total = sum(len(v) for v in servers_by_host.values())
    print(rule)
    print('Affected instances on %s' % ', '.join(servers_by_host))
    print(rule)
    print(format_instance_list(servers_by_host, names))
    print()
    print('Recipients (%d):' % len(recipients))
    print('-' * 40)
    for item in sorted(recipients.values(), key=lambda i: (i['email'] or '').lower()):
        role = 'instance owner' if item['owner'] else 'project member'
        print('\n%s  <%s>' % (item['name'], item['email']))
        print('  role: %s' % role)
        print('  user id: %s' % item['user_id'])
        if item['servers']:
            print('  instances (%d):' % len(item['servers']))
            for server in item['servers']:
                print('    - %s (%s)' % (server['name'], server['status']))
        for project_id in sorted(item['projects']):
            print('  project: %s' % names.get(project_id, project_id))
    if skipped and args.include_no_email:
        print('\nSkipped (%d):' % len(skipped))
        print('-' * 40)
        for item in sorted(skipped, key=lambda i: i['name']):
            print('%s: %s%s' % (item['name'], item['reason'],
                                ' <%s>' % item['email'] if item['email'] else ''))
    print('\n%s\nSUMMARY\n%s' % (rule, rule))
    print('Hosts: %d' % len(servers_by_host))
    print('Instances: %d' % total)
    print('Recipients: %d' % len(recipients))
    print('Skipped: %d' % len(skipped))


def print_csv(recipients, names, out=None):
    writer = csv.writer(out or sys.stdout)
    writer.writerow(['email', 'username', 'user_id', 'role', 'project',
                     'instance', 'instance_id', 'status'])
    for item in sorted(recipients.values(), key=lambda i: (i['email'] or '').lower()):
        role = 'owner' if item['owner'] else 'member'
        if item['servers']:
            for server in sorted(item['servers'], key=lambda s: s['name'] or ''):
                writer.writerow([item['email'], item['name'], item['user_id'], role,
                                 names.get(server['project'], server['project']),
                                 server['name'], server['id'], server['status']])
        else:
            # project members hold no instances; one row each so they are not lost
            for project_id in sorted(item['projects']):
                writer.writerow([item['email'], item['name'], item['user_id'], role,
                                 names.get(project_id, project_id), '', '', ''])


# ----------------------------------------------------------------------- main

def run(args):
    if args.list_templates:
        found = available_templates(args.template_dir)
        print('\n'.join(found) if found else 'no templates in %s' % args.template_dir)
        return 0

    date = parse_date(args.date)
    extra_vars = parse_extra_vars(args.extra_vars)
    path = template_path(args.template, args.template_dir)
    subject_template, body_template = load_template(path)

    hosts = list(dict.fromkeys(args.hosts))
    conn = openstack.connect()

    known = known_compute_hosts(conn)
    unknown = [h for h in hosts if h not in known]
    if unknown:
        raise NoticeError('no nova-compute service for: %s' % ', '.join(unknown))

    servers_by_host = find_servers(conn, hosts)
    ignored_project_ids = resolve_projects(conn, args.ignore_project)
    for host, servers in servers_by_host.items():
        servers_by_host[host] = [s for s in servers
                                 if s.project_id not in ignored_project_ids]
    servers = [s for items in servers_by_host.values() for s in items]
    if not servers:
        print('No instances found on %s' % ', '.join(hosts), file=sys.stderr)
        return 0
    print('Found %d instance(s) on %d host(s)' % (len(servers), len(hosts)), file=sys.stderr)

    recipients, skipped = collect_recipients(conn, servers, args, {})
    names = project_names(conn, {s.project_id for s in servers})

    if args.emails_only:
        for email in sorted_emails(recipients):
            print(email)
        return 0
    if args.as_csv:
        print_csv(recipients, names)
        return 0
    if args.details:
        print_details(args, recipients, skipped, servers_by_host, names)
        return 0

    variables = dict(extra_vars)
    variables.update({
        'date': date,
        'window': args.window,
        'hosts': ', '.join(hosts),
        'host_label': host_label(hosts),
        'instance_list': format_instance_list(servers_by_host, names),
        'instance_count': str(len(servers)),
        'project_count': str(len({s.project_id for s in servers})),
        'support_email': args.support_email,
    })
    subject = render(subject_template, variables, 'the subject line of %s' % path)
    body = wrap_body(render(body_template, variables, path))
    print_notice(recipients, subject, body)
    return 0


def main(argv=None):
    try:
        return run(parse_args(argv))
    except NoticeError as e:
        sys.exit('error: %s' % e)
    except (os_exc.SDKException, ks_exc.ClientException) as e:
        sys.exit('OpenStack API error (is an admin openrc sourced?): %s' % e)


if __name__ == '__main__':
    sys.exit(main())
