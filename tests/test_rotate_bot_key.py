"""Atomic bot-key replacement in the bootstrap authorized_keys format."""

from __future__ import annotations

import base64
import importlib.util
import struct
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "sidecomputer" / "admin" / "rotate_bot_key.py"

STRICT_OPTIONS = 'command="/usr/local/bin/sidecomputer-gate",restrict'
OPEN_OPTIONS = "restrict,pty"


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


def _strict(pubkey: str) -> str:
    return f"{STRICT_OPTIONS} {pubkey} sidecomputer-bot"


def _open(pubkey: str) -> str:
    return f"{OPEN_OPTIONS} {pubkey} sidecomputer-bot-open"


class _User:
    pw_uid = 4242
    pw_gid = 4242


class RotateBotKeyTest(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.directory = Path(self._tmp.name)
        self.keys = self.directory / "authorized_keys"
        self._patches = [
            mock.patch.object(ROTATE.os, "geteuid", return_value=0),
            mock.patch.dict(ROTATE.os.environ, {}, clear=False),
            mock.patch.object(ROTATE.pwd, "getpwnam", return_value=_User()),
            mock.patch.object(ROTATE.os, "fchown"),
        ]
        for patch in self._patches:
            patch.start()
        ROTATE.os.environ.pop("SUDO_USER", None)

    def tearDown(self) -> None:
        for patch in reversed(self._patches):
            patch.stop()
        self._tmp.cleanup()

    def _write(self, text: str) -> None:
        self.keys.write_text(text, encoding="utf-8")
        self.keys.chmod(0o600)

    def _rotate(self, **kwargs: object) -> None:
        defaults = {
            "bot_pubkey": NEW,
            "retire_pubkeys": [OLD],
            "mode": "strict",
            "replace_all": True,
            "remove_bot": False,
        }
        defaults.update(kwargs)
        ROTATE.rotate_bot_key(self.keys, **defaults)

    def test_strict_bootstrap_line_keeps_command_and_restrict(self) -> None:
        self._write(_strict(OLD) + "\n")
        self._rotate()
        body = self.keys.read_text(encoding="utf-8")
        self.assertEqual(body, _strict(NEW) + "\n")
        self.assertIn(STRICT_OPTIONS, body)
        self.assertNotIn(OLD.split()[1], body)
        self.assertEqual(self.keys.stat().st_mode & 0o777, 0o600)

    def test_open_bootstrap_line_keeps_restrict_pty(self) -> None:
        self._write(_open(OLD) + "\n")
        self._rotate(mode="open")
        body = self.keys.read_text(encoding="utf-8")
        self.assertEqual(body, _open(NEW) + "\n")
        self.assertNotIn(OLD.split()[1], body)

    def test_unknown_mode_leaves_the_file_unchanged(self) -> None:
        original = _strict(OLD) + "\n"
        self._write(original)
        with self.assertRaises(ROTATE.RotationError):
            self._rotate(mode="custom")
        self.assertEqual(self.keys.read_text(encoding="utf-8"), original)

    def test_extra_options_are_replaced_by_the_exact_prefix(self) -> None:
        extended = (
            'command="/usr/local/bin/sidecomputer-gate",restrict,pty '
            f"{OLD} sidecomputer-bot\n"
        )
        self._write(extended)
        self._rotate()
        body = self.keys.read_text(encoding="utf-8")
        self.assertEqual(body, _strict(NEW) + "\n")
        self.assertNotIn(",restrict,pty", body)

    def test_mode_mismatch_leaves_the_file_unchanged(self) -> None:
        original = _strict(OLD) + "\n"
        self._write(original)
        with self.assertRaises(ROTATE.RotationError):
            self._rotate(mode="open")
        self.assertEqual(self.keys.read_text(encoding="utf-8"), original)

    def test_abort_before_rename_leaves_only_the_old_key(self) -> None:
        original = _strict(OLD) + "\n"
        self._write(original)
        with self.assertRaises(ROTATE.RotationError):
            self._rotate(abort_before_rename=True)
        self.assertEqual(self.keys.read_text(encoding="utf-8"), original)
        self.assertFalse(list(self.directory.glob(".authorized_keys.*")))

    def test_extra_key_is_refused(self) -> None:
        original = _strict(OLD) + f"\n{ADMIN} other\n"
        self._write(original)
        with self.assertRaises(ROTATE.RotationError):
            self._rotate()
        self.assertEqual(self.keys.read_text(encoding="utf-8"), original)
        self.assertNotIn(NEW.split()[1], original)

    def test_non_root_cannot_rotate(self) -> None:
        original = _strict(OLD) + "\n"
        self._write(original)
        with mock.patch.object(ROTATE.os, "geteuid", return_value=1000):
            with self.assertRaises(ROTATE.RotationError):
                self._rotate()
        self.assertEqual(self.keys.read_text(encoding="utf-8"), original)

    def test_sidecomputer_sudo_cannot_rotate(self) -> None:
        original = _strict(OLD) + "\n"
        self._write(original)
        with mock.patch.dict(ROTATE.os.environ, {"SUDO_USER": "sidecomputer"}):
            with self.assertRaises(ROTATE.RotationError):
                self._rotate()
        self.assertEqual(self.keys.read_text(encoding="utf-8"), original)

    def test_remove_bot_clears_only_the_bot_file(self) -> None:
        self._write(_strict(OLD) + "\n")
        admin_keys = self.directory / "admin_authorized_keys"
        admin_keys.write_text(f"{ADMIN} admin\n", encoding="utf-8")
        self._rotate(bot_pubkey=None, mode=None, remove_bot=True)
        self.assertEqual(self.keys.read_text(encoding="utf-8"), "")
        self.assertEqual(admin_keys.read_text(encoding="utf-8"), f"{ADMIN} admin\n")

    def test_cli_refuses_keep_line_and_non_root(self) -> None:
        original = _strict(OLD) + "\n"
        self._write(original)
        completed = subprocess.run(
            [
                sys.executable,
                str(SCRIPT),
                "--keys-file",
                str(self.keys),
                "--mode",
                "strict",
                "--replace-all",
                "--retire-pubkey",
                OLD,
                "--bot-pubkey",
                NEW,
                "--keep-line",
                f"{ADMIN} admin",
            ],
            check=False,
            capture_output=True,
            text=True,
        )
        self.assertNotEqual(completed.returncode, 0)
        self.assertEqual(self.keys.read_text(encoding="utf-8"), original)

    def test_fchown_happens_before_rename(self) -> None:
        self._write(_strict(OLD) + "\n")
        order: list[str] = []
        real_replace = ROTATE.os.replace

        def track_fchown(fd: int, uid: int, gid: int) -> None:
            order.append(f"chown:{uid}:{gid}")

        def track_replace(src: Path, dst: Path) -> None:
            order.append("rename")
            real_replace(src, dst)

        with mock.patch.object(ROTATE.os, "fchown", side_effect=track_fchown), mock.patch.object(
            ROTATE.os, "replace", side_effect=track_replace
        ):
            self._rotate()
        self.assertEqual(order, ["chown:4242:4242", "rename"])


class SkillContractTest(unittest.TestCase):
    def test_dispatch_hub_is_advisory_and_logs_stay_unfetched(self) -> None:
        text = (ROOT / "sidecomputer" / "dispatch" / "SKILL.md").read_text(encoding="utf-8")
        lowered = text.lower()
        self.assertNotIn("authenticated", lowered)
        self.assertNotIn("already redacted", lowered)
        self.assertIn("cooperative and advisory", lowered)
        self.assertIn("self-asserted", lowered)
        self.assertIn("HUB_BOT", text)
        self.assertIn("security decision", lowered)
        self.assertIn("stdout.log", text)
        self.assertIn("stderr.log", text)
        self.assertIn("leave every artifact unfetched", lowered)
        self.assertIn("artifact_redaction", text)
        self.assertIn("as `all`", text)
        self.assertNotIn("once that fix has landed", lowered)
        self.assertIn("owner approves the handoff", lowered)
        self.assertIn("Never forward artifact contents", text)

    def test_setup_uses_secure_secret_input_and_no_gate_rotate_tool(self) -> None:
        text = (ROOT / "sidecomputer" / "getting-started" / "SKILL.md").read_text(encoding="utf-8")
        lowered = text.lower()
        self.assertIn("secure secret input", lowered)
        self.assertIn("pasted into chat", lowered)
        self.assertNotIn("if the owner gives a password", lowered)
        self.assertNotIn("ask the owner where to get it", lowered)
        self.assertIn("git clone https://github.com/vaiev/mcp", text)
        self.assertNotIn("rotate_bot_key", text)
        self.assertNotIn("authenticated", lowered)

    def test_admin_rotation_is_admin_only_and_keeps_restrictions(self) -> None:
        text = (ROOT / "sidecomputer" / "admin" / "SKILL.md").read_text(encoding="utf-8")
        lowered = text.lower()
        self.assertIn("rotate_bot_key.py", text)
        self.assertIn('command="/usr/local/bin/sidecomputer-gate",restrict', text)
        self.assertIn("restrict,pty", text)
        self.assertIn("admin user's `authorized_keys`", text)
        self.assertIn("no `--keep-line`", lowered)
        self.assertIn("no gate rotate tool", lowered)
        self.assertIn("owner approves", lowered)
        self.assertIn("as root", lowered)
        self.assertIn("half-finished rotation", lowered)
        self.assertIn("end sessions", lowered)
        self.assertIn("spool and the audit log", text)
        self.assertNotIn("/usr/local/lib/sidecomputer/rotate_bot_key.py", text)
        self.assertNotIn("tools` lists `rotate_bot_key`", text)

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
