#!/usr/bin/env python3
"""Regression test for binary discovery in mihomo-ctl.py.

The bug: the pkexec subscription helper and the DIRECT-rule setup command
hardcoded /usr/bin/mihomo. Package managers put mihomo there, but the upstream
release tarballs install to /usr/local/bin, so on those systems a subscription
add/edit/delete was validated with a missing binary and rolled back. Resolve it
through MIHOMO_BIN, then PATH, and only then fall back.
"""

import importlib.util
import pathlib
import unittest
from unittest import mock

SCRIPT = pathlib.Path(__file__).resolve().parents[1] / "scripts" / "mihomo-ctl.py"
_spec = importlib.util.spec_from_file_location("mihomo_ctl", SCRIPT)
ctl = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(ctl)


class MihomoBinaryTest(unittest.TestCase):
    def test_env_override_wins(self):
        with mock.patch.dict(ctl.os.environ, {"MIHOMO_BIN": "/opt/mihomo"}):
            self.assertEqual(ctl.mihomo_binary(), "/opt/mihomo")

    def test_path_lookup_used(self):
        with mock.patch.dict(ctl.os.environ, {}, clear=False):
            ctl.os.environ.pop("MIHOMO_BIN", None)
            with mock.patch.object(ctl.shutil, "which", return_value="/usr/local/bin/mihomo"):
                self.assertEqual(ctl.mihomo_binary(), "/usr/local/bin/mihomo")

    def test_last_resort(self):
        with mock.patch.dict(ctl.os.environ, {}, clear=False):
            ctl.os.environ.pop("MIHOMO_BIN", None)
            with mock.patch.object(ctl.shutil, "which", return_value=None):
                self.assertEqual(ctl.mihomo_binary(), "/usr/bin/mihomo")


if __name__ == "__main__":
    unittest.main()
