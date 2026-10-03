"""Unit tests of the Python helpers in steamify-cachyos/patches (stdlib only).

Run through tests/python-test.sh (REPO = the Steamify checkout), or:
    REPO=../steamify-cachyos python3 -m unittest tests/patches_test.py -v
"""
import contextlib
import importlib.util
import io
import os
import struct
import tempfile
import unittest
from unittest import mock

REPO = os.environ.get("REPO") or os.path.join(os.path.dirname(__file__), "..", "..", "steamify-cachyos")


def load(name, filename):
    spec = importlib.util.spec_from_file_location(name, os.path.join(REPO, "patches", filename))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


shortcuts = load("steam_shortcuts", "steam-shortcuts.py")
notifier = load("steamify_notifier", "steamify-notifier.py")


class VdfTests(unittest.TestCase):
    def test_roundtrip(self):
        root = [("shortcuts", [("0", [("appid", 123), ("AppName", "A"), ("tags", [])])])]
        self.assertEqual(shortcuts.parse(shortcuts.dump(root)), root)

    def test_empty_data_is_an_empty_list(self):
        self.assertEqual(shortcuts.parse(b""), [("shortcuts", [])])

    def test_unknown_type_is_an_error(self):
        with self.assertRaises(ValueError):
            shortcuts.parse(b"\x07key\0")

    def test_ints_are_unsigned_32_bit(self):
        data = shortcuts.dump([("n", -1)])
        self.assertEqual(struct.unpack_from("<I", data, 3)[0], 0xFFFFFFFF)

    def test_keys_match_regardless_of_case(self):
        entry = [("AppName", "x")]
        self.assertEqual(shortcuts.get(entry, "appname"), "x")
        shortcuts.put(entry, "APPNAME", "y")
        self.assertEqual(entry, [("AppName", "y")])

    def test_ours(self):
        exe = "/home/u/.local/share/steamify/bin/run-app"
        self.assertTrue(shortcuts.ours([("Exe", f'"{exe}"')], exe))
        # An older install's start script counts as ours: updated, not doubled.
        self.assertTrue(shortcuts.ours([("Exe", '"/home/u/.local/share/cachyos-gamescope-boot/bin/run-app"')], exe))
        self.assertFalse(shortcuts.ours([("Exe", '"/usr/bin/other"')], exe))
        self.assertFalse(shortcuts.ours([("Exe", '"/home/u/games/run-app"')], exe))


class ShortcutsCommandTests(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.addCleanup(self.dir.cleanup)
        self.vdf = os.path.join(self.dir.name, "userdata", "1", "config", "shortcuts.vdf")
        self.exe = "/home/u/.local/share/steamify/bin/run-app"

    def run_cmd(self, *args):
        out = io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(io.StringIO()):
            rc = shortcuts.main(["steam-shortcuts.py", *args])
        return rc, out.getvalue().strip()

    def entries(self):
        return shortcuts.shortcuts(shortcuts.load(self.vdf))

    def test_add_creates_the_file_and_an_entry(self):
        rc, out = self.run_cmd("add", self.vdf, "Steamify", self.exe, "/icon.png", "steamify.desktop")
        self.assertEqual(rc, 0)
        self.assertTrue(out.startswith("added "))
        (_, entry), = self.entries()
        self.assertEqual(shortcuts.get(entry, "AppName"), "Steamify")
        self.assertEqual(shortcuts.get(entry, "Exe"), f'"{self.exe}"')
        # Steam's id for a shortcut has the top bit set.
        self.assertGreaterEqual(shortcuts.get(entry, "appid"), 0x80000000)
        self.assertEqual(out, f"added {shortcuts.get(entry, 'appid')}")

    def test_add_twice_updates_instead_of_doubling(self):
        self.run_cmd("add", self.vdf, "Steamify", self.exe, "/a.png", "a.desktop")
        rc, out = self.run_cmd("add", self.vdf, "Steamify 2", self.exe, "/b.png", "b.desktop")
        self.assertTrue(out.startswith("updated "))
        entries = self.entries()
        self.assertEqual(len(entries), 1)
        self.assertEqual(shortcuts.get(entries[0][1], "AppName"), "Steamify 2")
        self.assertEqual(shortcuts.get(entries[0][1], "icon"), "/b.png")

    def test_other_entries_are_kept(self):
        self.run_cmd("add", self.vdf, "Other", "/usr/bin/other", "", "")
        self.run_cmd("add", self.vdf, "Steamify", self.exe, "", "")
        self.assertEqual(len(self.entries()), 2)
        self.assertEqual([k for k, _ in self.entries()], ["0", "1"])

    def test_find(self):
        self.assertEqual(self.run_cmd("find", self.vdf, self.exe)[0], 1)
        _, out = self.run_cmd("add", self.vdf, "Steamify", self.exe, "", "")
        rc, found = self.run_cmd("find", self.vdf, self.exe)
        self.assertEqual((rc, found), (0, out.split()[1]))

    def test_remove_by_appid_renumbers(self):
        self.run_cmd("add", self.vdf, "Other", "/usr/bin/other", "", "")
        _, out = self.run_cmd("add", self.vdf, "Steamify", self.exe, "", "")
        self.assertEqual(self.run_cmd("remove", self.vdf, out.split()[1])[0], 0)
        entries = self.entries()
        self.assertEqual([k for k, _ in entries], ["0"])
        self.assertEqual(shortcuts.get(entries[0][1], "AppName"), "Other")

    def test_remove_of_nothing_leaves_the_file_alone(self):
        self.run_cmd("add", self.vdf, "Steamify", self.exe, "", "")
        with open(self.vdf, "rb") as f:
            before = f.read()
        self.assertEqual(self.run_cmd("remove", self.vdf, "999")[0], 0)
        with open(self.vdf, "rb") as f:
            self.assertEqual(f.read(), before)

    def test_unknown_command(self):
        self.assertEqual(self.run_cmd("bogus", self.vdf)[0], 2)


class NotifierTests(unittest.TestCase):
    def test_version(self):
        self.assertEqual(notifier.version("v2.11.1"), (2, 11, 1))
        self.assertEqual(notifier.version("2.9.0"), (2, 9, 0))
        self.assertIsNone(notifier.version("nightly"))

    def test_versions_compare_as_numbers(self):
        self.assertGreater(notifier.version("2.10.0"), notifier.version("2.9.0"))

    def pending(self, new, seen="", skipped=""):
        values = {"seen": seen, "skipped": skipped}
        with mock.patch.object(notifier, "state", lambda key: values[key]):
            return notifier.pending(new)

    def test_newer_than_seen(self):
        self.assertTrue(self.pending("2.12.0", seen="2.11.1"))

    def test_same_or_older_is_not_pending(self):
        self.assertFalse(self.pending("2.11.1", seen="2.11.1"))
        self.assertFalse(self.pending("2.9.0", seen="2.11.1"))

    def test_skipped_version_is_not_pending(self):
        self.assertFalse(self.pending("2.12.0", seen="2.11.1", skipped="2.12.0"))

    def test_nothing_seen_yet(self):
        self.assertTrue(self.pending("2.12.0", seen=""))

    def test_unparsable_tag_is_not_pending(self):
        # A release tag like "nightly" must not crash the daily check.
        self.assertFalse(self.pending("nightly", seen="2.11.1"))


if __name__ == "__main__":
    unittest.main()
