#!/usr/bin/env python3
"""Regression tests for the node list the panel renders.

Two bugs live here:

* `group_snapshot()` returned a list of bare strings while `status` returned
  `{name, delay}` objects. The QML delegate reads `modelData.name`, so after
  switching the policy-group chip the node rows were blank — the panel looked
  like it had no node switching at all.
* the members list dropped everything that was itself a group, so a subscription
  that is reached through a sub-group (the common shape: PROXY → BV → node) could
  never be selected as the exit, no matter what the chip said.
"""

import importlib.util
import pathlib
import unittest

SCRIPT = pathlib.Path(__file__).resolve().parents[1] / "scripts" / "mihomo-ctl.py"
_spec = importlib.util.spec_from_file_location("mihomo_ctl", SCRIPT)
ctl = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(ctl)

PROXIES = {
    "PROXY": {"type": "Selector", "all": ["BV", "AUTO", "DIRECT", "hk-01"], "now": "BV"},
    "BV": {"type": "Selector", "all": ["BV自动", "DIRECT", "us-01"], "now": "BV自动"},
    "BV自动": {"type": "URLTest", "all": ["us-01", "tw-01"], "now": "tw-01"},
    "AUTO": {"type": "URLTest", "all": ["hk-01"], "now": "hk-01"},
    "hk-01": {"type": "Shadowsocks"},
    "us-01": {"type": "Hysteria2"},
    "tw-01": {"type": "Hysteria2"},
    "REJECT": {"type": "Reject"},
    "PASS": {"type": "Pass"},
}


class MembersTest(unittest.TestCase):
    def test_subgroups_are_selectable(self):
        members = ctl.group_members(PROXIES["PROXY"], PROXIES)
        self.assertIn("BV", members)
        self.assertIn("AUTO", members)

    def test_direct_stays_but_junk_builtins_are_hidden(self):
        members = ctl.group_members(PROXIES["PROXY"], PROXIES)
        self.assertIn("DIRECT", members)

        junk = {"type": "Selector", "all": ["REJECT", "PASS", "PASS-RULE", "hk-01"]}
        self.assertEqual(ctl.group_members(junk, PROXIES), ["hk-01"])


class KindTest(unittest.TestCase):
    def test_kinds_are_labelled(self):
        self.assertEqual(ctl.node_kind("BV", PROXIES), "group")
        self.assertEqual(ctl.node_kind("BV自动", PROXIES), "group")
        self.assertEqual(ctl.node_kind("hk-01", PROXIES), "node")
        self.assertEqual(ctl.node_kind("DIRECT", PROXIES), "direct")


class EntryShapeTest(unittest.TestCase):
    def test_entries_match_the_shape_the_panel_reads(self):
        entries = ctl.node_entries(["BV", "DIRECT", "hk-01"], PROXIES)
        self.assertEqual(
            entries,
            [{"name": "BV", "kind": "group", "delay": None},
             {"name": "DIRECT", "kind": "direct", "delay": None},
             {"name": "hk-01", "kind": "node", "delay": None}],
        )
        for entry in entries:
            self.assertIn("name", entry)      # QML: modelData.name
            self.assertIn("kind", entry)      # QML: 组/直连 角标


if __name__ == "__main__":
    unittest.main()
