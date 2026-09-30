#!/usr/bin/env python3
"""Regression tests for the direct-rule provider installer.

The bug these pin down: the managed RULE-SET line carries none of the BEGIN/END
markers the provider block has, so a config written by an older release — one
that named the provider differently — could not be recognised. install_provider()
rewrote the block to the new name while the rule kept the old one, mihomo
rejected the result with "rule set ... not found", and the script rolled back
without ever saying why.
"""

import argparse
import importlib.util
import pathlib
import shutil
import subprocess
import tempfile
import unittest

SCRIPT = pathlib.Path(__file__).resolve().parents[1] / "scripts" / "configure-direct-rules.py"
_spec = importlib.util.spec_from_file_location("configure_direct_rules", SCRIPT)
installer = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(installer)

PROVIDER = installer.PROVIDER_NAME
LEGACY = installer.LEGACY_PROVIDER_NAMES[0]
COMMENT = installer.MANAGED_RULE_COMMENT
RULES_PATH = "/etc/mihomo/direct-rules/direct-rules.yaml"

HEAD = (
    "proxies: []\n"
    "proxy-groups:\n"
    "  - name: PROXY\n"
    "    type: select\n"
    "    proxies: [DIRECT]\n"
)
PROVIDER_ENTRY = (
    "rule-providers:\n"
    "  {p}:\n"
    "    type: file\n"
    "    behavior: classical\n"
    "    format: yaml\n"
    "    path: '" + RULES_PATH + "'\n"
)
RULE = "  - RULE-SET,%s,DIRECT"


def make_config(provider=PROVIDER, block=True, rule=True, extra=(), tail=True):
    """A config with an optional managed block and an optional managed rule."""
    text = HEAD
    if block:
        text += installer.START + "\n" + PROVIDER_ENTRY.format(p=provider) + installer.END + "\n"
    text += "rules:\n"
    if rule:
        text += "  " + COMMENT + "\n" + RULE % provider + "\n"
    for line in extra:
        text += line + "\n"
    if tail:
        text += "  - GEOSITE,cn,DIRECT\n  - MATCH,PROXY\n"
    return text


class ConfigureDirectRulesTest(unittest.TestCase):
    def setUp(self):
        installer.args = argparse.Namespace(rules_path=RULES_PATH)

    def render(self, text):
        return installer.render_config(text)

    def assert_managed(self, out):
        wanted = RULE % PROVIDER
        self.assertEqual(out.count(wanted), 1, "expected exactly one managed rule")
        self.assertEqual(out.count(COMMENT), 1, "expected exactly one managed comment")
        self.assertNotIn(LEGACY, out, "the old provider name is still referenced")
        self.assertIn("  %s:\n" % PROVIDER, out, "the provider block was not rewritten")
        self.assertLess(out.index(wanted), out.index("- GEOSITE,cn,DIRECT"),
                        "the managed rule has to stay ahead of the broad CN rules")

    def test_renames_a_legacy_rule_beside_its_block(self):
        self.assert_managed(self.render(make_config(provider=LEGACY)))

    def test_renames_a_legacy_rule_whose_block_is_gone(self):
        self.assert_managed(self.render(make_config(provider=LEGACY, block=False)))

    def test_collapses_what_the_previous_release_wrote(self):
        """One managed rule too many — the state that failed validation."""
        source = make_config(extra=[RULE % LEGACY])
        self.assert_managed(self.render(source))

    def test_collapses_two_current_rules(self):
        self.assert_managed(self.render(make_config(extra=[RULE % PROVIDER])))

    def test_inserts_the_rule_when_there_is_none(self):
        self.assert_managed(self.render(make_config(block=False, rule=False)))

    def test_leaves_an_already_correct_config_alone(self):
        once = self.render(make_config())
        self.assertEqual(self.render(once), once)

    def test_keeps_a_hand_written_provider_entry(self):
        """The markers may sit inside a rule-providers section the user already had."""
        source = (
            HEAD
            + "rule-providers:\n  keep-me:\n    path: /tmp/keep.yaml\n"
            + installer.START + "\n"
            + PROVIDER_ENTRY.format(p=LEGACY).split("\n", 1)[1]
            + installer.END + "\n"
            + "rules:\n  " + COMMENT + "\n" + RULE % LEGACY + "\n"
            + "  - GEOSITE,cn,DIRECT\n"
        )
        out = self.render(source)
        self.assert_managed(out)
        self.assertIn("  keep-me:", out)

    def test_inserts_a_block_when_the_config_has_none(self):
        out = self.render(make_config(block=False, rule=False))
        self.assertIn(installer.START, out)
        self.assertIn(installer.END, out)


@unittest.skipUnless(shutil.which("mihomo"), "mihomo is not installed")
class MihomoValidationTest(unittest.TestCase):
    """Whatever the installer writes has to be a config mihomo itself accepts."""

    def test_a_migrated_legacy_config_validates(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            (root / "direct-rules").mkdir()
            (root / "direct-rules" / "direct-rules.yaml").write_text("payload: []\n")
            installer.args = argparse.Namespace(
                rules_path=str(root / "direct-rules" / "direct-rules.yaml"))
            (root / "config.yaml").write_text(installer.render_config(make_config(provider=LEGACY)))
            done = subprocess.run(["mihomo", "-t", "-d", str(root)],
                                  capture_output=True, text=True)
            self.assertEqual(done.returncode, 0, done.stderr or done.stdout)


if __name__ == "__main__":
    unittest.main(verbosity=2)
