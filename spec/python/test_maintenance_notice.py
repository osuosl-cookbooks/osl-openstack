"""Unit tests for files/maintenance-notice.py.

Run with: python3 -m unittest discover -s spec/python -v

openstacksdk and keystoneauth1 are stubbed, so the tests need nothing beyond
the standard library.
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

REPO = Path(__file__).resolve().parents[2]
SCRIPT = REPO / 'files' / 'maintenance-notice.py'
TEMPLATE_DIR = REPO / 'files' / 'default' / 'maintenance-templates'


def _stub_modules():
    exc = types.ModuleType('openstack.exceptions')

    class SDKException(Exception):
        pass

    class ResourceNotFound(SDKException):
        pass

    class ForbiddenException(SDKException):
        pass

    exc.SDKException = SDKException
    exc.ResourceNotFound = ResourceNotFound
    exc.ForbiddenException = ForbiddenException
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
    return pkg, ks_exc


OPENSTACK, KS_EXC = _stub_modules()
EXC = OPENSTACK.exceptions
_spec = importlib.util.spec_from_file_location('maintenance_notice', SCRIPT)
mn = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(mn)


def server(id='s1', name='vm1', status='ACTIVE', user_id='u1', project_id='p1'):
    return types.SimpleNamespace(id=id, name=name, status=status,
                                 user_id=user_id, project_id=project_id)


def user(id='u1', name='alice', email='alice@example.com', enabled=True):
    return types.SimpleNamespace(id=id, name=name, email=email, is_enabled=enabled)


def assignment(user_id=None, group_id=None, role='member'):
    a = types.SimpleNamespace(role={'name': role}, scope={'project': {'id': 'p1'}})
    a.user = {'id': user_id} if user_id else None
    a.group = {'id': group_id} if group_id else None
    return a


class Base(unittest.TestCase):
    def setUp(self):
        self.conn = mock.Mock()
        self.conn.identity.role_assignments.return_value = []
        self.conn.identity.find_project.return_value = None

    def tmpdir(self):
        d = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, d)
        return d

    def args(self, *extra):
        with mock.patch.dict(os.environ, {}, clear=True):
            return mn.parse_args(list(extra))


class ParseArgsTest(Base):
    def test_defaults_replace_rather_than_extend(self):
        a = self.args('host1', '-d', '2026-02-05')
        self.assertEqual(a.ignore_user, ['admin'])
        self.assertEqual(a.member_role, ['member', '_member_'])
        self.assertEqual(a.ignore_project, list(mn.DEFAULT_IGNORED_PROJECTS))
        # the old script appended to the default, so admin could never be dropped
        a = self.args('host1', '-d', '2026-02-05', '--ignore-user', 'bob')
        self.assertEqual(a.ignore_user, ['bob'])
        a = self.args('host1', '-d', '2026-02-05', '--ignore-project', 'only-this')
        self.assertEqual(a.ignore_project, ['only-this'])

    def test_multiple_hosts_and_flags(self):
        a = self.args('h1', 'h2', 'h3', '-d', 'Feb 5', '-w', '9-5', '-t', 'hardware',
                      '--no-groups', '--no-project-members')
        self.assertEqual(a.hosts, ['h1', 'h2', 'h3'])
        self.assertEqual((a.window, a.template), ('9-5', 'hardware'))
        self.assertTrue(a.no_groups and a.no_project_members)

    def test_host_and_date_required_unless_listing_templates(self):
        for argv in (['-d', '2026-02-05'], ['host1']):
            with self.assertRaises(SystemExit), contextlib.redirect_stderr(io.StringIO()):
                self.args(*argv)
        a = self.args('--list-templates')
        self.assertTrue(a.list_templates)

    def test_output_modes_are_mutually_exclusive(self):
        with self.assertRaises(SystemExit), contextlib.redirect_stderr(io.StringIO()):
            self.args('h', '-d', '2026-02-05', '--csv', '--emails-only')


class DateTest(Base):
    def test_formats_with_year(self):
        for text in ('2026-02-05', '02/05/2026', '2/5/2026', 'February 5, 2026',
                     'Feb 5, 2026', 'February 5 2026'):
            self.assertEqual(mn.parse_date(text), 'Thu, February 5, 2026', text)

    def test_year_defaults_to_this_year(self):
        this_year = datetime.date.today().year
        self.assertTrue(mn.parse_date('2/5').endswith(', %d' % this_year))
        self.assertTrue(mn.parse_date('February 5').endswith(', %d' % this_year))

    def test_unparsable_date_is_an_error_not_passed_through(self):
        for text in ('Feburary 5', 'next tuesday', '', '2026-02-31'):
            with self.assertRaises(mn.NoticeError):
                mn.parse_date(text)

    def test_day_is_not_zero_padded(self):
        self.assertEqual(mn.parse_date('2026-02-05'), 'Thu, February 5, 2026')


class ExtraVarsTest(Base):
    def test_parse(self):
        self.assertEqual(mn.parse_extra_vars(['ticket=RT123', 'note=a=b']),
                         {'ticket': 'RT123', 'note': 'a=b'})

    def test_rejects_bad_input(self):
        for bad in (['nope'], ['1bad=x'], ['has space=x']):
            with self.assertRaises(mn.NoticeError):
                mn.parse_extra_vars(bad)


class TemplateTest(Base):
    def write(self, name, body):
        d = getattr(self, '_tdir', None) or self.tmpdir()
        self._tdir = d
        Path(d, name).write_text(body)
        return d

    def test_resolution_by_name_filename_and_path(self):
        d = self.write('reboot.txt', 'Subject: s\n\nbody')
        self.assertEqual(mn.template_path('reboot', d), os.path.join(d, 'reboot.txt'))
        self.assertEqual(mn.template_path('reboot.txt', d), os.path.join(d, 'reboot.txt'))
        self.assertEqual(mn.template_path(os.path.join(d, 'reboot.txt'), 'ignored'),
                         os.path.join(d, 'reboot.txt'))

    def test_missing_template_names_the_directory(self):
        d = self.tmpdir()
        with self.assertRaisesRegex(mn.NoticeError, 'no template .nope. in %s' % d):
            mn.template_path('nope', d)

    def test_available_templates(self):
        d = self.write('b.txt', 'x')
        Path(d, 'a.txt').write_text('x')
        Path(d, 'README').write_text('x')
        self.assertEqual(mn.available_templates(d), ['a', 'b'])
        self.assertEqual(mn.available_templates('/nonexistent'), [])

    def test_subject_split_from_body(self):
        d = self.write('t.txt', 'Subject: Hi $date\n\nHello,\n\nbye\n')
        subject, body = mn.load_template(os.path.join(d, 't.txt'))
        self.assertEqual(subject, 'Hi $date')
        self.assertEqual(body, 'Hello,\n\nbye')

    def test_body_only_template(self):
        d = self.write('n.txt', 'just a body\n')
        subject, body = mn.load_template(os.path.join(d, 'n.txt'))
        self.assertIsNone(subject)
        self.assertEqual(body, 'just a body')

    def test_render_substitutes_and_reports_typos(self):
        self.assertEqual(mn.render('a $x b', {'x': 'Y'}, 'tmpl'), 'a Y b')
        self.assertIsNone(mn.render(None, {}, 'tmpl'))
        with self.assertRaisesRegex(mn.NoticeError, r'unknown placeholder \$nope'):
            mn.render('$nope', {'x': 'Y'}, 'tmpl')
        with self.assertRaisesRegex(mn.NoticeError, 'malformed placeholder'):
            mn.render('100$ off', {'x': 'Y'}, 'tmpl')

    def test_shipped_templates_render_with_the_variables_the_script_supplies(self):
        variables = {'date': 'Thu, February 5, 2026', 'window': 'w', 'hosts': 'h1',
                     'host_label': 'hypervisor node h1', 'instance_list': '  p:\n    - vm1',
                     'instance_count': '1', 'project_count': '1',
                     'support_email': 'support@osuosl.org'}
        names = mn.available_templates(str(TEMPLATE_DIR))
        self.assertIn('reboot', names)
        for name in names:
            subject, body = mn.load_template(mn.template_path(name, str(TEMPLATE_DIR)))
            self.assertIsNotNone(subject, name)
            rendered = mn.render(body, variables, name)
            self.assertNotIn('$', rendered, name)
            self.assertIn('support@osuosl.org', rendered, name)


class WrapBodyTest(Base):
    def test_long_line_is_split_not_joined(self):
        text = ('a sentence that runs past the limit because a long host list '
                'was substituted into it openpower4, openpower5, openpower6.')
        out = mn.wrap_body(text, width=40)
        self.assertTrue(all(len(line) <= 40 for line in out.split('\n')), out)
        self.assertEqual(' '.join(out.split()), ' '.join(text.split()))

    def test_short_lines_are_never_merged(self):
        text = 'Scheduled Date: Thu, February 5, 2026\nMaintenance Window: 8am-5pm'
        self.assertEqual(mn.wrap_body(text), text)

    def test_indented_blocks_are_left_alone(self):
        text = '  openpower4:\n    webteam:\n      - a-very-long-instance-name-here (ACTIVE)'
        self.assertEqual(mn.wrap_body(text, width=20), text)

    def test_long_url_is_not_broken(self):
        url = 'https://osuosl.org/blog/osl-moving-to-state-data-center/'
        self.assertEqual(mn.wrap_body(url, width=20), url)


class LookupUserTest(Base):
    def test_caches_and_normalizes(self):
        cache = {}
        self.conn.identity.get_user.return_value = user(email='  Alice@Example.com ')
        info = mn.lookup_user(self.conn, 'u1', cache)
        self.assertEqual(info['email'], 'Alice@Example.com')
        self.assertTrue(info['enabled'])
        mn.lookup_user(self.conn, 'u1', cache)
        self.assertEqual(self.conn.identity.get_user.call_count, 1)

    def test_blank_email_becomes_none(self):
        self.conn.identity.get_user.return_value = user(email='   ')
        self.assertIsNone(mn.lookup_user(self.conn, 'u1', {})['email'])

    def test_missing_and_forbidden_users_are_not_enabled(self):
        self.conn.identity.get_user.side_effect = EXC.ResourceNotFound('gone')
        info = mn.lookup_user(self.conn, 'u9', {})
        self.assertFalse(info['enabled'])
        self.assertIn('Unknown', info['name'])
        self.conn.identity.get_user.side_effect = EXC.ForbiddenException('no')
        self.assertIn('Access denied', mn.lookup_user(self.conn, 'u8', {})['name'])

    def test_disabled_user(self):
        self.conn.identity.get_user.return_value = user(enabled=False)
        self.assertFalse(mn.lookup_user(self.conn, 'u1', {})['enabled'])


class ProjectMemberTest(Base):
    def test_effective_expands_groups(self):
        self.conn.identity.role_assignments.return_value = [assignment(user_id='u1')]
        ids = mn.project_member_ids(self.conn, 'p1', ['member'])
        self.assertEqual(ids, {'u1'})
        self.conn.identity.role_assignments.assert_called_once_with(
            scope_project_id='p1', include_names=True, effective=True)

    def test_no_groups_drops_the_effective_flag_and_skips_group_rows(self):
        self.conn.identity.role_assignments.return_value = [
            assignment(user_id='u1'), assignment(group_id='g1')]
        ids = mn.project_member_ids(self.conn, 'p1', ['member'], expand_groups=False)
        self.assertEqual(ids, {'u1'})
        self.assertEqual(self.conn.identity.role_assignments.call_args.kwargs,
                         {'scope_project_id': 'p1', 'include_names': True})

    def test_role_filter(self):
        self.conn.identity.role_assignments.return_value = [
            assignment(user_id='u1', role='member'),
            assignment(user_id='u2', role='admin'),
            assignment(user_id='u3', role='reader')]
        self.assertEqual(mn.project_member_ids(self.conn, 'p1', ['member']), {'u1'})
        self.assertEqual(mn.project_member_ids(self.conn, 'p1', ['member', 'reader']),
                         {'u1', 'u3'})

    def test_a_deleted_project_is_skipped_not_raised(self):
        # the SDK hands back a lazy generator, so keystone's 404 for a project
        # that no longer exists surfaces on iteration, not on the call
        def lazy(**kwargs):
            raise EXC.ResourceNotFound('Could not find project: 483844b1')
            yield  # pragma: no cover

        self.conn.identity.role_assignments.side_effect = lazy
        self.assertEqual(mn.project_member_ids(self.conn, 'gone', ['member']), set())

    def test_api_errors_yield_nothing(self):
        self.conn.identity.role_assignments.side_effect = EXC.ForbiddenException('no')
        self.assertEqual(mn.project_member_ids(self.conn, 'p1', ['member']), set())


class CollectRecipientsTest(Base):
    def setUp(self):
        super().setUp()
        self.users = {'u1': user('u1', 'alice', 'alice@example.com'),
                      'u2': user('u2', 'bob', 'bob@example.com'),
                      'u3': user('u3', 'carol', 'carol@osuosl.org'),
                      'dis': user('dis', 'dave', 'dave@example.com', enabled=False),
                      'noem': user('noem', 'erin', None),
                      'admin': user('admin', 'admin', 'admin@osuosl.org')}
        self.conn.identity.get_user.side_effect = lambda uid: self.users[uid]

    def collect(self, servers, *flags):
        a = self.args('h', '-d', '2026-02-05', *flags)
        return mn.collect_recipients(self.conn, servers, a, {})

    def test_owner_becomes_a_recipient_with_their_instances(self):
        recipients, skipped = self.collect([server(user_id='u1'),
                                            server(id='s2', name='vm2', user_id='u1')],
                                           '--no-project-members')
        self.assertEqual(set(recipients), {'u1'})
        self.assertTrue(recipients['u1']['owner'])
        self.assertEqual(len(recipients['u1']['servers']), 2)
        self.assertEqual(recipients['u1']['projects'], {'p1'})
        self.assertEqual(skipped, [])

    def test_disabled_owner_is_not_a_recipient_but_their_project_still_is(self):
        # the old script dropped the whole project, so nobody was told about a
        # VM whose only owner was disabled
        self.conn.identity.role_assignments.return_value = [assignment(user_id='u2')]
        recipients, skipped = self.collect([server(user_id='dis', project_id='p1')])
        self.assertNotIn('dis', recipients)
        self.assertIn('u2', recipients)
        self.assertEqual(recipients['u2']['projects'], {'p1'})
        self.assertFalse(recipients['u2']['owner'])
        # and the unreachable owner is reported, with the instance that has no
        # contact of its own
        self.assertEqual([(s['name'], s['reason']) for s in skipped],
                         [('dave', 'account disabled or unresolvable')])
        self.assertEqual([s['name'] for s in skipped[0]['servers']], ['vm1'])

    def test_disabled_owner_of_several_instances_is_reported_once(self):
        recipients, skipped = self.collect(
            [server(user_id='dis'), server(id='s2', name='vm2', user_id='dis')],
            '--no-project-members')
        self.assertEqual(recipients, {})
        self.assertEqual(len(skipped), 1)
        self.assertEqual(len(skipped[0]['servers']), 2)

    def test_project_members_merge_with_owners(self):
        self.conn.identity.role_assignments.return_value = [
            assignment(user_id='u1'), assignment(user_id='u2')]
        recipients, _ = self.collect([server(user_id='u1')])
        self.assertEqual(set(recipients), {'u1', 'u2'})
        self.assertTrue(recipients['u1']['owner'])
        self.assertFalse(recipients['u2']['owner'])

    def test_members_are_skipped_entirely_with_no_project_members(self):
        self.conn.identity.role_assignments.return_value = [assignment(user_id='u2')]
        recipients, _ = self.collect([server(user_id='u1')], '--no-project-members')
        self.assertEqual(set(recipients), {'u1'})
        self.conn.identity.role_assignments.assert_not_called()

    def test_ignored_user_is_dropped_not_just_blanked(self):
        recipients, skipped = self.collect([server(user_id='admin')], '--no-project-members')
        self.assertEqual(recipients, {})
        self.assertEqual([(s['name'], s['reason']) for s in skipped],
                         [('admin', 'ignored user')])

    def test_ignored_domain_is_dropped_with_its_own_reason(self):
        recipients, skipped = self.collect(
            [server(user_id='u1'), server(id='s2', user_id='u3')],
            '--no-project-members', '--ignore-domain', 'OSUOSL.ORG')
        self.assertEqual(set(recipients), {'u1'})
        self.assertEqual([(s['name'], s['reason']) for s in skipped],
                         [('carol', 'ignored domain')])

    def test_user_without_email_is_reported_separately(self):
        recipients, skipped = self.collect([server(user_id='noem')], '--no-project-members')
        self.assertEqual(recipients, {})
        self.assertEqual(skipped[0]['reason'], 'no email address on file')

    def test_one_lookup_per_user(self):
        self.collect([server(user_id='u1'), server(id='s2', user_id='u1')],
                     '--no-project-members')
        self.assertEqual(self.conn.identity.get_user.call_count, 1)


class HelpersTest(Base):
    def test_host_label(self):
        self.assertEqual(mn.host_label(['a']), 'hypervisor node a')
        self.assertEqual(mn.host_label(['a', 'b']), 'hypervisor nodes a and b')
        self.assertEqual(mn.host_label(['a', 'b', 'c']), 'hypervisor nodes a, b and c')

    def test_sorted_emails_dedupes_case_insensitively(self):
        recipients = {'1': {'email': 'B@x.com'}, '2': {'email': 'b@x.com'},
                      '3': {'email': 'a@x.com'}, '4': {'email': None}}
        self.assertEqual(mn.sorted_emails(recipients), ['a@x.com', 'B@x.com'])

    def test_instance_list_single_host_has_no_host_heading(self):
        out = mn.format_instance_list(
            {'h1': [server(name='vm2', project_id='p1'), server(name='vm1', project_id='p2')]},
            {'p1': 'proj-a', 'p2': 'proj-b'})
        self.assertEqual(out, '  proj-a:\n    - vm2 (ACTIVE)\n\n  proj-b:\n    - vm1 (ACTIVE)')

    def test_instance_list_groups_by_host_when_several(self):
        out = mn.format_instance_list(
            {'h1': [server(name='vm1')], 'h2': [server(name='vm2', project_id='p2')]},
            {'p1': 'proj-a', 'p2': 'proj-b'})
        self.assertIn('  h1:\n    proj-a:\n      - vm1 (ACTIVE)', out)
        self.assertIn('  h2:\n    proj-b:\n      - vm2 (ACTIVE)', out)

    def test_host_with_no_instances_is_left_out(self):
        out = mn.format_instance_list({'h1': [server()], 'h2': []}, {'p1': 'proj-a'})
        self.assertNotIn('h2', out)
        self.assertNotIn('h1:', out)  # only one host has instances, so no host heading


class CsvTest(Base):
    def test_one_row_per_instance_not_a_cartesian_product(self):
        recipients = {'u1': {'email': 'a@x.com', 'name': 'alice', 'user_id': 'u1',
                             'owner': True, 'projects': {'p1', 'p2'},
                             'servers': [{'name': 'vm1', 'id': '1', 'status': 'ACTIVE',
                                          'project': 'p1'},
                                         {'name': 'vm2', 'id': '2', 'status': 'SHUTOFF',
                                          'project': 'p2'}]}}
        buf = io.StringIO()
        mn.print_csv(recipients, {'p1': 'proj-a', 'p2': 'proj-b'}, out=buf)
        rows = buf.getvalue().strip().splitlines()
        self.assertEqual(len(rows), 3)  # header plus one row per instance
        self.assertIn('a@x.com,alice,u1,owner,proj-a,vm1,1,ACTIVE', rows[1])
        self.assertIn('a@x.com,alice,u1,owner,proj-b,vm2,2,SHUTOFF', rows[2])

    def test_project_members_without_instances_still_get_a_row(self):
        recipients = {'u2': {'email': 'b@x.com', 'name': 'bob', 'user_id': 'u2',
                             'owner': False, 'projects': {'p1'}, 'servers': []}}
        buf = io.StringIO()
        mn.print_csv(recipients, {'p1': 'proj-a'}, out=buf)
        rows = buf.getvalue().strip().splitlines()
        self.assertEqual(len(rows), 2)
        self.assertIn('b@x.com,bob,u2,member,proj-a,,,', rows[1])

    def test_fields_with_commas_are_quoted(self):
        recipients = {'u1': {'email': 'a@x.com', 'name': 'alice', 'user_id': 'u1',
                             'owner': True, 'projects': {'p1'},
                             'servers': [{'name': 'vm1', 'id': '1', 'status': 'ACTIVE',
                                          'project': 'p1'}]}}
        buf = io.StringIO()
        mn.print_csv(recipients, {'p1': 'Foo, Inc'}, out=buf)
        self.assertIn('"Foo, Inc"', buf.getvalue())


class RunTest(Base):
    def setUp(self):
        super().setUp()
        OPENSTACK.connect = mock.Mock(return_value=self.conn)
        self.conn.compute.services.return_value = [
            types.SimpleNamespace(host='h1'), types.SimpleNamespace(host='h2')]
        self.servers = {'h1': [server(user_id='u1', project_id='p1')]}
        self.conn.compute.servers.side_effect = (
            lambda details, all_projects, compute_host: list(self.servers.get(compute_host, [])))
        self.conn.identity.get_user.return_value = user()
        self.conn.identity.get_project.return_value = types.SimpleNamespace(name='proj-a')
        self.conn.identity.role_assignments.return_value = []

    def run_main(self, *argv):
        out, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err), \
                mock.patch.dict(os.environ, {}, clear=True):
            rc = mn.run(mn.parse_args(list(argv) + ['--template-dir', str(TEMPLATE_DIR)]))
        return rc, out.getvalue(), err.getvalue()

    def test_list_templates_needs_no_cloud(self):
        rc, out, _ = self.run_main('--list-templates')
        self.assertEqual(rc, 0)
        self.assertIn('reboot', out)
        OPENSTACK.connect.assert_not_called()

    def test_unknown_host_is_an_error(self):
        with self.assertRaisesRegex(mn.NoticeError, 'no nova-compute service for: nope'):
            self.run_main('nope', '-d', '2026-02-05')

    def test_notice_contains_recipients_subject_and_rendered_body(self):
        rc, out, err = self.run_main('h1', '-d', '2026-02-05')
        self.assertEqual(rc, 0)
        self.assertIn('alice@example.com', out)
        self.assertIn('Scheduled Maintenance - Thu, February 5, 2026 - h1', out)
        self.assertIn('hypervisor node h1', out)
        self.assertIn('proj-a:', out)
        self.assertIn('- vm1 (ACTIVE)', out)
        self.assertNotIn('$', out)
        self.assertIn('Found 1 instance(s) on 1 host(s)', err)

    def test_rendered_body_stays_within_80_columns_even_with_many_hosts(self):
        for n in range(2, 7):
            host = 'openpower%d' % n
            self.conn.compute.services.return_value.append(types.SimpleNamespace(host=host))
            self.servers[host] = [server(id='s%d' % n, name='vm%d' % n)]
        hosts = ['h1'] + ['openpower%d' % n for n in range(2, 7)]
        rc, out, _ = self.run_main(*(hosts + ['-d', '2026-02-05']))
        self.assertEqual(rc, 0)
        body = out.split('EMAIL BODY')[1]
        long_lines = [line for line in body.split('\n') if len(line) > 80]
        self.assertEqual(long_lines, [])

    def test_template_selection(self):
        rc, out, _ = self.run_main('h1', '-d', '2026-02-05', '-t', 'hardware')
        self.assertIn('Scheduled Hardware Maintenance', out)
        self.assertIn('involves physical hardware', out)
        rc, out, _ = self.run_main('h1', '-d', '2026-02-05', '-t', 'upgrade-migrate')
        self.assertIn('Scheduled Host Upgrade', out)
        self.assertIn('moved to another host', out)
        rc, out, _ = self.run_main('h1', '-d', '2026-02-05', '-t', 'upgrade-in-place')
        self.assertIn('Scheduled Host Upgrade', out)
        self.assertIn('cannot be moved elsewhere', out)
        self.assertIn('unavailable for the whole window', out)

    def test_shipped_templates_are_not_rewrapped_by_rendering(self):
        # the templates are hand-wrapped, so rendering must leave their prose
        # alone and only split lines a substitution made too long
        for name in mn.available_templates(str(TEMPLATE_DIR)):
            _, body = mn.load_template(mn.template_path(name, str(TEMPLATE_DIR)))
            prose = [ln for ln in body.split('\n') if '$' not in ln]
            for line in prose:
                self.assertEqual(mn.wrap_body(line), line, '%s: %r' % (name, line))

    def test_ignored_project_removes_instances_and_their_owner(self):
        # the old script kept the user on the recipient line even though none of
        # their instances were listed
        self.conn.identity.find_project.side_effect = (
            lambda name, ignore_missing=True:
            types.SimpleNamespace(id='p1') if name == 'skipme' else None)
        rc, out, err = self.run_main('h1', '-d', '2026-02-05', '--ignore-project', 'skipme')
        self.assertEqual(rc, 0)
        self.assertIn('No instances found on h1', err)
        self.assertNotIn('alice@example.com', out)

    def test_multiple_hosts_are_merged(self):
        self.servers['h2'] = [server(id='s2', name='vm2', user_id='u1', project_id='p1')]
        rc, out, err = self.run_main('h1', 'h2', '-d', '2026-02-05')
        self.assertIn('Found 2 instance(s) on 2 host(s)', err)
        self.assertIn('hypervisor nodes h1 and h2', out)
        self.assertIn('h1:', out)
        self.assertIn('h2:', out)

    def test_duplicate_hosts_are_collapsed(self):
        rc, out, err = self.run_main('h1', 'h1', '-d', '2026-02-05')
        self.assertIn('Found 1 instance(s) on 1 host(s)', err)

    def test_emails_only_and_csv_and_details(self):
        rc, out, _ = self.run_main('h1', '-d', '2026-02-05', '--emails-only')
        self.assertEqual(out.strip(), 'alice@example.com')
        rc, out, _ = self.run_main('h1', '-d', '2026-02-05', '--csv')
        self.assertTrue(out.startswith('email,username,user_id,role,project'))
        self.assertIn('alice@example.com,alice,u1,owner,proj-a,vm1,s1,ACTIVE', out)
        rc, out, _ = self.run_main('h1', '-d', '2026-02-05', '--details')
        self.assertIn('Recipients: 1', out)
        self.assertIn('instance owner', out)

    def test_no_instances_exits_zero_without_drafting(self):
        self.servers = {}
        rc, out, err = self.run_main('h1', '-d', '2026-02-05')
        self.assertEqual(rc, 0)
        self.assertEqual(out, '')
        self.assertIn('No instances found', err)


class MainTest(Base):
    def test_notice_error_exits_with_a_message(self):
        with mock.patch.object(mn, 'run', side_effect=mn.NoticeError('bad date')), \
                self.assertRaises(SystemExit) as cm:
            mn.main(['h', '-d', 'x'])
        self.assertEqual(str(cm.exception.code), 'error: bad date')

    def test_api_error_exits_with_a_message(self):
        with mock.patch.object(mn, 'run', side_effect=KS_EXC.ClientException('nope')), \
                self.assertRaises(SystemExit) as cm:
            mn.main(['h', '-d', '2026-02-05'])
        self.assertIn('OpenStack API error', str(cm.exception.code))


if __name__ == '__main__':
    unittest.main()
