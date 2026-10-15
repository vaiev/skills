"""Atomic bot-key replacement. A failed run must not authorize both keys."""

from __future__ import annotations

import base64
import importlib.util
import struct
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "sidecomputer" / "admin" / "rotate_bot_key.py"


def _load():
    spec = importlib.util.spec_from_file_location("rotate_bot_key", SCRIPT)
    if spec is None or spec.loader is None:
        raise RuntimeError("could not load rotate_bot_key")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


ROTATE = _load()


def _pubkey(seed: int) -> str:
    key = bytes((seed + index) % 256 for index in range(32))
    blob = struct.pack(">I", len(b"ssh-ed25519")) + b"ssh-ed25519"
    blob += struct.pack(">I", len(key)) + key
    material = base64.b64encode(blob).decode("ascii")
    return f"ssh-ed25519 {material}"


OLD = _pubkey(1)
NEW = _pubkey(2)
ADMIN = _pubkey(3)


class RotateBotKeyTest(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.directory = Path(self._tmp.name)
        self.keys = self.directory / "authorized_keys"

    def tearDown(self) -> None:
        self._tmp.cleanup()

    def _write(self, text: str, mode: int = 0o600) -> None:
        self.keys.write_text(text, encoding="utf-8")
        self.keys.chmod(mode)

    def test_replace_all_drops_unmarked_old_key(self) -> None:
        self._write(f"{OLD} sidecomputer-bot\n{ADMIN} admin\n")
        ROTATE.rotate_bot_key(
            self.keys,
            bot_pubkey=NEW,
            retire_pubkeys=[],
            keep_lines=[f"{ADMIN} admin"],
            replace_all=True,
            remove_bot=False,
        )
        body = self.keys.read_text(encoding="utf-8")
        self.assertNotIn(OLD.split()[1], body)
        self.assertIn(NEW.split()[1], body)
        self.assertIn(f"{ADMIN} admin", body)
        self.assertEqual(body.count("sidecomputer-bot"), 1)
        self.assertEqual(self.keys.stat().st_mode & 0o777, 0o600)

    def test_abort_before_rename_leaves_only_the_old_key(self) -> None:
        original = f"{OLD} sidecomputer-bot\n"
        self._write(original)
        with self.assertRaises(ROTATE.RotationError):
            ROTATE.rotate_bot_key(
                self.keys,
                bot_pubkey=NEW,
                retire_pubkeys=[],
                keep_lines=[],
                replace_all=True,
                remove_bot=False,
                abort_before_rename=True,
            )
        self.assertEqual(self.keys.read_text(encoding="utf-8"), original)
        self.assertFalse(list(self.directory.glob(".authorized_keys.*")))
        body = self.keys.read_text(encoding="utf-8")
        self.assertNotIn(NEW.split()[1], body)
        self.assertIn(OLD.split()[1], body)

    def test_invalid_key_does_not_change_the_file(self) -> None:
        original = f"{OLD} sidecomputer-bot\n"
        self._write(original)
        with self.assertRaises(ROTATE.RotationError):
            ROTATE.rotate_bot_key(
                self.keys,
                bot_pubkey="ssh-ed25519 not-a-key",
                retire_pubkeys=[],
                keep_lines=[],
                replace_all=True,
                remove_bot=False,
            )
        self.assertEqual(self.keys.read_text(encoding="utf-8"), original)

    def test_newline_in_pubkey_is_rejected(self) -> None:
        self._write(f"{OLD}\n")
        with self.assertRaises(ROTATE.RotationError):
            ROTATE.rotate_bot_key(
                self.keys,
                bot_pubkey=f"{NEW}\n{OLD}",
                retire_pubkeys=[],
                keep_lines=[],
                replace_all=True,
                remove_bot=False,
            )
        self.assertNotIn(NEW.split()[1], self.keys.read_text(encoding="utf-8"))

    def test_refuse_append_without_replace_or_retire(self) -> None:
        original = f"{OLD} unmarked\n"
        self._write(original)
        with self.assertRaises(ROTATE.RotationError):
            ROTATE.rotate_bot_key(
                self.keys,
                bot_pubkey=NEW,
                retire_pubkeys=[],
                keep_lines=[],
                replace_all=False,
                remove_bot=False,
            )
        self.assertEqual(self.keys.read_text(encoding="utf-8"), original)

    def test_remove_bot_without_console_clears_the_key(self) -> None:
        self._write(f"{OLD} sidecomputer-bot\n{ADMIN} admin\n")
        ROTATE.rotate_bot_key(
            self.keys,
            bot_pubkey=None,
            retire_pubkeys=[],
            keep_lines=[f"{ADMIN} admin"],
            replace_all=True,
            remove_bot=True,
        )
        body = self.keys.read_text(encoding="utf-8")
        self.assertNotIn(OLD.split()[1], body)
        self.assertNotIn("sidecomputer-bot", body)
        self.assertEqual(body, f"{ADMIN} admin\n")

    def test_symlink_is_refused(self) -> None:
        target = self.directory / "real_keys"
        target.write_text(f"{OLD}\n", encoding="utf-8")
        self.keys.symlink_to(target)
        with self.assertRaises(ROTATE.RotationError):
            ROTATE.rotate_bot_key(
                self.keys,
                bot_pubkey=NEW,
                retire_pubkeys=[],
                keep_lines=[],
                replace_all=True,
                remove_bot=False,
            )
        self.assertIn(OLD.split()[1], target.read_text(encoding="utf-8"))
        self.assertNotIn(NEW.split()[1], target.read_text(encoding="utf-8"))

    def test_retired_key_cannot_ride_along_as_a_keep_line(self) -> None:
        original = f"{OLD} sidecomputer-bot\n"
        self._write(original)
        with self.assertRaises(ROTATE.RotationError):
            ROTATE.rotate_bot_key(
                self.keys,
                bot_pubkey=NEW,
                retire_pubkeys=[OLD],
                keep_lines=[f"{OLD} admin"],
                replace_all=True,
                remove_bot=False,
            )
        self.assertEqual(self.keys.read_text(encoding="utf-8"), original)
        body = self.keys.read_text(encoding="utf-8")
        self.assertIn(OLD.split()[1], body)
        self.assertNotIn(NEW.split()[1], body)

    def test_cli_replace_all(self) -> None:
        self._write(f"{OLD} old\n")
        completed = subprocess.run(
            [
                sys.executable,
                str(SCRIPT),
                "--keys-file",
                str(self.keys),
                "--replace-all",
                "--bot-pubkey",
                NEW,
            ],
            check=False,
            capture_output=True,
            text=True,
        )
        self.assertEqual(completed.returncode, 0, completed.stderr)
        body = self.keys.read_text(encoding="utf-8")
        self.assertIn(NEW.split()[1], body)
        self.assertNotIn(OLD.split()[1], body)
        self.assertTrue(body.endswith("sidecomputer-bot\n"))


class SkillContractTest(unittest.TestCase):
    def test_dispatch_forbids_raw_logs_and_requires_verified_identity(self) -> None:
        text = (ROOT / "sidecomputer" / "dispatch" / "SKILL.md").read_text(encoding="utf-8")
        lowered = text.lower()
        self.assertNotIn("already redacted", lowered)
        self.assertIn("stdout.log", text)
        self.assertIn("stderr.log", text)
        self.assertIn("do not fetch", lowered)
        self.assertIn("redaction gate", lowered)
        self.assertIn("verified identity", lowered)
        self.assertIn("invariants 1 and 3", lowered)
        self.assertIn("invariant 4", lowered)
        self.assertIn("owner's approval", lowered)
        self.assertIn("consequential", lowered)
        self.assertIn("authenticated channel", lowered)
        self.assertIn("Never forward artifact contents", text)

    def test_setup_uses_secure_secret_input(self) -> None:
        text = (ROOT / "sidecomputer" / "getting-started" / "SKILL.md").read_text(encoding="utf-8")
        lowered = text.lower()
        self.assertIn("secure secret input", lowered)
        self.assertIn("pasted into chat", lowered)
        self.assertNotIn("if the owner gives a password", lowered)
        self.assertNotIn("ask the owner where to get it", lowered)
        self.assertIn("git clone https://github.com/vaiev/mcp", text)
        self.assertIn("rotate_bot_key", text)

    def test_admin_rotation_is_atomic_and_needs_no_console(self) -> None:
        text = (ROOT / "sidecomputer" / "admin" / "SKILL.md").read_text(encoding="utf-8")
        lowered = text.lower()
        self.assertIn("rotate_bot_key.py", text)
        self.assertIn("--replace-all", text)
        self.assertIn("--remove-bot", text)
        self.assertIn("atomic", lowered)
        self.assertIn("do not need provider console", lowered)
        self.assertIn("half-finished rotation", lowered)
        self.assertIn("spool and the audit log", text)
        self.assertNotIn("then remove the old key line", lowered)

    def test_readmes_share_canonical_paths(self) -> None:
        root = (ROOT / "README.md").read_text(encoding="utf-8")
        family = (ROOT / "sidecomputer" / "README.md").read_text(encoding="utf-8")
        canonical = [
            "vaiev/skills/sidecomputer/getting-started/SKILL.md",
            "vaiev/skills/sidecomputer/dispatch/SKILL.md",
            "vaiev/skills/sidecomputer/admin/SKILL.md",
        ]
        relative = [
            "sidecomputer/getting-started/SKILL.md",
            "sidecomputer/dispatch/SKILL.md",
            "sidecomputer/admin/SKILL.md",
        ]
        for path in canonical + relative:
            self.assertIn(path, root)
            self.assertIn(path, family)
        self.assertNotIn("skills/sidecomputer-dispatch.md", root)
        self.assertNotIn("skills/sidecomputer-dispatch.md", family)


if __name__ == "__main__":
    unittest.main()
