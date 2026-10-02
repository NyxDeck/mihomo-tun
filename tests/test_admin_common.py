#!/usr/bin/env python3
"""Tests for the root helpers' mihomo resolution.

The security property: the helpers run as root through pkexec/sudo, and the
caller is unprivileged, so a caller-supplied --mihomo-bin or MIHOMO_BIN must
not be able to name an arbitrary (user-writable) binary for root to execute.
"""

import importlib.util
import os
import pathlib
import stat
import unittest
from unittest import mock

SCRIPT = pathlib.Path(__file__).resolve().parents[1] / "scripts" / "admin_common.py"
_spec = importlib.util.spec_from_file_location("admin_common", SCRIPT)
ac = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(ac)


def fake_info(mode, uid=0):
    info = mock.Mock()
    info.st_mode = mode
    info.st_uid = uid
    return info


def stat_map(mapping):
    def fake(path):
        try:
            return mapping[path]
        except KeyError:
            raise FileNotFoundError(path)

    return fake


class TrustedExecutableTest(unittest.TestCase):
    def test_root_owned_executable_is_trusted(self):
        with mock.patch.object(ac.os, "stat", return_value=fake_info(stat.S_IFREG | 0o755)):
            self.assertTrue(ac.trusted_executable("/usr/bin/mihomo"))

    def test_user_owned_is_rejected(self):
        with mock.patch.object(ac.os, "stat", return_value=fake_info(stat.S_IFREG | 0o755, uid=1000)):
            self.assertFalse(ac.trusted_executable("/home/u/.local/bin/mihomo"))

    def test_group_or_world_writable_is_rejected(self):
        for mode in (stat.S_IFREG | 0o775, stat.S_IFREG | 0o757):
            with mock.patch.object(ac.os, "stat", return_value=fake_info(mode)):
                self.assertFalse(ac.trusted_executable("/usr/bin/mihomo"))

    def test_non_regular_is_rejected(self):
        with mock.patch.object(ac.os, "stat", return_value=fake_info(stat.S_IFDIR | 0o755)):
            self.assertFalse(ac.trusted_executable("/usr/bin/mihomo"))

    def test_missing_path_is_rejected(self):
        with mock.patch.object(ac.os, "stat", side_effect=FileNotFoundError):
            self.assertFalse(ac.trusted_executable("/nope"))


class ResolveMihomoBinTest(unittest.TestCase):
    def test_untrusted_explicit_falls_back_to_root_candidate(self):
        root = fake_info(stat.S_IFREG | 0o755)
        evil = fake_info(stat.S_IFREG | 0o755, uid=1000)
        with mock.patch.dict(os.environ, {}, clear=False):
            os.environ.pop("MIHOMO_BIN", None)
            with mock.patch.object(ac, "TRUSTED_CANDIDATES", ("/usr/bin/mihomo",)), \
                 mock.patch.object(ac.shutil, "which", return_value=None), \
                 mock.patch.object(ac.os, "stat", side_effect=stat_map({
                     "/tmp/evil": evil,
                     "/usr/bin/mihomo": root,
                 })):
                self.assertEqual(ac.resolve_mihomo_bin("/tmp/evil"), "/usr/bin/mihomo")

    def test_trusted_explicit_is_used(self):
        good = fake_info(stat.S_IFREG | 0o755)
        with mock.patch.object(ac.os, "stat", return_value=good):
            self.assertEqual(ac.resolve_mihomo_bin("/usr/local/bin/mihomo"), "/usr/local/bin/mihomo")

    def test_nothing_trusted_raises(self):
        with mock.patch.dict(os.environ, {}, clear=False):
            os.environ.pop("MIHOMO_BIN", None)
            with mock.patch.object(ac, "TRUSTED_CANDIDATES", ("/usr/bin/mihomo",)), \
                 mock.patch.object(ac.shutil, "which", return_value=None), \
                 mock.patch.object(ac.os, "stat", side_effect=FileNotFoundError):
                with self.assertRaises(SystemExit):
                    ac.resolve_mihomo_bin()


if __name__ == "__main__":
    unittest.main()
