"""Unit tests for files/fix-flavors.py.

Run with: python3 -m unittest discover -s spec/python -v

pymysql is stubbed, so the tests need only the stdlib.
"""

import importlib.util
import sys
import tempfile
import types
import unittest
from pathlib import Path
from unittest import mock

# Another suite may have stubbed pymysql first; fix-flavors only needs DictCursor
if 'pymysql' not in sys.modules:
    sys.modules['pymysql'] = types.SimpleNamespace(cursors=types.SimpleNamespace(DictCursor=object))

SCRIPT = Path(__file__).resolve().parents[2] / 'files' / 'fix-flavors.py'
_spec = importlib.util.spec_from_file_location('fix_flavors', SCRIPT)
ff = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(ff)


class DbParamsTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.conf = Path(self.tmp.name) / 'nova.conf'
        patcher = mock.patch.object(ff, 'NOVA_CONF_PATH', str(self.conf))
        self.addCleanup(patcher.stop)
        patcher.start()

    def params(self, url):
        self.conf.write_text(f'[api_database]\nconnection = {url}\n')
        return ff.get_db_params()

    def test_a_url_encoded_password_is_unquoted(self):
        # Default configparser interpolation rejected any % in the value
        p = self.params('mysql+pymysql://nova:p%40ss@db.example.org:3307/nova_api?charset=utf8')
        self.assertEqual((p['host'], p['port'], p['user'], p['password'], p['db']),
                         ('db.example.org', 3307, 'nova', 'p@ss', 'nova_api'))

    def test_a_raw_password_keeps_its_slash_hash_and_question_mark(self):
        p = self.params('mysql+pymysql://nova:a/b#c?d@db:3306/nova_api')
        self.assertEqual((p['host'], p['password'], p['db']), ('db', 'a/b#c?d', 'nova_api'))

    def test_the_port_defaults_to_3306(self):
        p = self.params('mysql+pymysql://nova:pw@db/nova_api')
        self.assertEqual((p['port'], p['db']), (3306, 'nova_api'))

    def test_a_missing_section_exits(self):
        self.conf.write_text('[database]\nconnection = mysql+pymysql://n:pw@db/nova\n')
        with self.assertRaises(SystemExit), mock.patch('builtins.print'):
            ff.get_db_params()

    def test_data_lives_outside_root(self):
        self.assertEqual(ff.BACKUP_DIR, '/var/lib/osl-openstack/flavor-fixes')
        self.assertEqual(ff.LOG_FILE, '/var/log/osl-openstack/nova-flavor-sync.log')


if __name__ == '__main__':
    unittest.main()
