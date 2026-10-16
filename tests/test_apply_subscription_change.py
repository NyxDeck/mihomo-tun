#!/usr/bin/env python3
"""Regression tests for the subscription helper's group wiring.

The bug these pin down: adding a subscription used to write only the
proxy-provider. Nothing referenced it, so after the panel said "订阅已保存" the
node list did not change at all — the subscription existed in the config and
nowhere in the UI. The helper now also installs a managed select group and puts
it in the PROXY selector, and deleting the subscription takes all three back out.
"""

import importlib.util
import pathlib
import unittest

SCRIPT = pathlib.Path(__file__).resolve().parents[1] / "scripts" / "apply-subscription-change.py"
_spec = importlib.util.spec_from_file_location("apply_subscription_change", SCRIPT)
helper = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(helper)

NAME = "backup-airport"
URL = "https://example.invalid/api/v1/client/token"

HEAD = """proxies: []
proxy-providers:
proxy-groups:
  - name: PROXY
    type: select
    proxies: [DIRECT]
rules:
  - MATCH,PROXY
"""


def upsert(text, name=NAME, url=URL, original=""):
    lines = helper.upsert_provider(text.splitlines(), name, url)
    if original and original != name:
        lines = helper.remove_provider(lines, original)
        lines = helper.remove_managed_group(lines, original)
        lines = helper.set_proxy_member(lines, original, False)
    lines = helper.upsert_group(lines, name)
    return "\n".join(lines) + "\n"


def delete(text, name=NAME):
    lines = helper.remove_provider(text.splitlines(), name)
    lines = helper.remove_managed_group(lines, name)
    lines = helper.set_proxy_member(lines, name, False)
    return "\n".join(lines) + "\n"


class UpsertWiringTest(unittest.TestCase):
    def test_provider_group_and_proxy_membership_are_all_added(self):
        text = upsert(HEAD)
        self.assertIn("  %s:\n" % NAME, text)          # provider
        self.assertIn("  - name: %s\n" % NAME, text)   # managed group
        self.assertIn("    use: [%s]" % NAME, text)    # group pulls the provider
        self.assertIn("proxies: [%s, DIRECT]" % NAME, text)

    def test_second_upsert_changes_nothing(self):
        once = upsert(HEAD)
        self.assertEqual(once, upsert(once))

    def test_provider_is_declared_before_the_groups_that_use_it(self):
        text = upsert(HEAD)
        self.assertLess(text.index("  %s:" % NAME), text.index("proxy-groups:"))

    def test_rename_moves_the_group_and_the_membership(self):
        text = upsert(HEAD, original="old-name")
        text = upsert(text.replace(NAME, "old-name"), name="new-name", original="old-name")
        self.assertNotIn("old-name", text)
        self.assertIn("  - name: new-name\n", text)
        self.assertIn("proxies: [new-name, DIRECT]", text)


class RemoveWiringTest(unittest.TestCase):
    def test_delete_removes_provider_group_and_membership(self):
        text = delete(upsert(HEAD))
        self.assertNotIn(NAME, text)
        self.assertIn("proxies: [DIRECT]", text)
        self.assertEqual(text, HEAD)

    def test_delete_leaves_unmanaged_groups_alone(self):
        hand_written = HEAD.replace(
            "  - name: PROXY",
            "  - name: %s\n    type: select\n    proxies: [DIRECT]\n  - name: PROXY" % NAME,
        )
        text = delete(upsert(hand_written))
        # 手写的同名组不是我们的，删订阅时不能连它一起删
        self.assertIn("  - name: %s\n    type: select\n    proxies: [DIRECT]" % NAME, text)


class SameNamedLocalGroupTest(unittest.TestCase):
    def test_local_group_is_kept_and_not_duplicated(self):
        hand_written = HEAD.replace(
            "  - name: PROXY",
            "  - name: %s\n    type: select\n    proxies: [DIRECT]\n  - name: PROXY" % NAME,
        )
        text = upsert(hand_written)
        self.assertEqual(text.count("  - name: %s\n" % NAME), 1)
        self.assertIn("proxies: [%s, DIRECT]" % NAME, text)
        # 没有插入托管块
        self.assertNotIn(helper.GROUP_BEGIN % NAME, text)


class BlockStyleProxyListTest(unittest.TestCase):
    def test_membership_is_added_to_a_block_list(self):
        text = upsert(HEAD.replace("    proxies: [DIRECT]", "    proxies:\n      - DIRECT"))
        self.assertIn("      - %s\n      - DIRECT" % NAME, text)
        self.assertEqual(delete(text), HEAD.replace("    proxies: [DIRECT]", "    proxies:\n      - DIRECT"))


if __name__ == "__main__":
    unittest.main()
