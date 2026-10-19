"""Guard against referencing SDK exceptions that do not exist on the controllers.

The other suites stub openstacksdk and keystoneauth1, so a name that exists in
a newer SDK but not in the cli venv's passes every test and then raises
AttributeError in production, from inside the except clause meant to handle the
error. That is exactly how os_exc.ForbiddenException reached a controller.

These allowlists are names present in the cli venv's openstacksdk on both
release lines: 0.62.0 (yoga) and 0.101.0 (zed), with keystoneauth1 4.5.0 and
5.0.1. Adding a name means checking it in both locks first, not against
whatever is installed on a developer's machine.
"""

import ast
import unittest
from pathlib import Path

FILES = ('cold-migrate-host.py', 'resize-debris-check.py', 'maintenance-notice.py')
SCRIPT_DIR = Path(__file__).resolve().parents[2] / 'files'

# openstack/exceptions.py classes and helpers present in 0.62.0 and 0.101.0;
# ForbiddenException is in neither.
SDK_NAMES = {
    'SDKException', 'EndpointNotFound', 'InvalidResponse', 'InvalidRequest',
    'HttpException', 'BadRequestException', 'ConflictException',
    'PreconditionFailedException', 'MethodNotSupported', 'DuplicateResource',
    'ResourceNotFound', 'ResourceTimeout', 'ResourceFailure',
    'InvalidResourceQuery', 'ConfigException', 'NotSupported',
    'ValidationException', 'TaskManagerStopped', 'ServiceDisabledException',
    'ServiceDiscoveryException', 'raise_from_response',
}

# keystoneauth1.exceptions re-exports its submodules; these are the ones used.
KS_NAMES = {'ClientException', 'MissingRequiredOptions', 'Unauthorized',
            'HttpError', 'AuthPluginException', 'ConnectionError'}

ALLOWED = {'os_exc': SDK_NAMES, 'ks_exc': KS_NAMES}


def referenced_names(path):
    """Every os_exc.X / ks_exc.X attribute the file reads, as (alias, name)."""
    tree = ast.parse(path.read_text(), filename=str(path))
    found = set()
    for node in ast.walk(tree):
        if (isinstance(node, ast.Attribute) and isinstance(node.value, ast.Name)
                and node.value.id in ALLOWED):
            found.add((node.value.id, node.attr))
    return found


class SdkExceptionNamesTest(unittest.TestCase):
    def test_scripts_only_use_names_that_exist_on_the_controllers(self):
        for name in FILES:
            path = SCRIPT_DIR / name
            self.assertTrue(path.is_file(), 'missing script: %s' % path)
            for alias, attr in sorted(referenced_names(path)):
                self.assertIn(
                    attr, ALLOWED[alias],
                    '%s uses %s.%s, which does not exist in the SDK release the '
                    'controllers run. Check the name against that release, not '
                    'against your locally installed version.' % (name, alias, attr))

    def test_every_script_is_actually_scanned(self):
        # a rename would otherwise turn this guard into a silent no-op
        for name in FILES:
            self.assertTrue((SCRIPT_DIR / name).is_file(), name)
        self.assertTrue(any(referenced_names(SCRIPT_DIR / n) for n in FILES))

    def test_the_guard_catches_a_bogus_name(self):
        bogus = ast.parse('os_exc.ForbiddenException')
        attrs = {n.attr for n in ast.walk(bogus) if isinstance(n, ast.Attribute)}
        self.assertNotIn(attrs.pop(), SDK_NAMES)


if __name__ == '__main__':
    unittest.main()
