#!/usr/bin/env python3
"""Atomically replace the SideComputer bot key in authorized_keys.

An admin runs this as root after the owner approves. It refuses to run as
the sidecomputer user, so the bot key cannot rewrite its own credentials.
There is no gate tool and no keep-line list.

The new line keeps the option prefix bootstrap writes:

- strict: command="/usr/local/bin/sidecomputer-gate",restrict
- open: restrict,pty

The temp file is chowned to the sidecomputer user and mode 0600 before
rename, so sshd StrictModes accepts it. A failure before rename leaves the
previous file in place.
"""

from __future__ import annotations

import argparse
import base64
import os
import pwd
import sys
import tempfile
from pathlib import Path

BOT_USER = "sidecomputer"
STRICT_OPTIONS = 'command="/usr/local/bin/sidecomputer-gate",restrict'
OPEN_OPTIONS = "restrict,pty"
STRICT_COMMENT = "sidecomputer-bot"
OPEN_COMMENT = "sidecomputer-bot-open"
_ED25519_TYPE = b"ssh-ed25519"

_MODES = {
    "strict": (STRICT_OPTIONS, STRICT_COMMENT),
    "open": (OPEN_OPTIONS, OPEN_COMMENT),
}


class RotationError(Exception):
    """The keys file was left unchanged."""


def public_key_material(text: str) -> str:
    """Return the raw ssh-ed25519 blob from a line or a bare key."""
    if "\n" in text or "\r" in text or "\x00" in text:
        raise RotationError("public key must be a single line")
    stripped = text.strip()
    if not stripped:
        raise RotationError("public key is empty")
    parts = stripped.split()
    if parts[0] == "ssh-ed25519":
        if len(parts) < 2:
            raise RotationError("public key is missing key material")
        material = parts[1]
    elif len(parts) == 1:
        material = parts[0]
    else:
        raise RotationError("public key must be one ssh-ed25519 key")
    _validate_ed25519_material(material)
    return material


def _validate_ed25519_material(material: str) -> None:
    if any(character.isspace() for character in material):
        raise RotationError("public key material contains whitespace")
    try:
        blob = base64.b64decode(material.encode("ascii"), validate=True)
    except (ValueError, UnicodeEncodeError) as exc:
        raise RotationError("public key material is not valid base64") from exc
    if len(blob) < 4:
        raise RotationError("public key blob is too short")
    type_len = int.from_bytes(blob[0:4], "big")
    type_end = 4 + type_len
    if type_len != len(_ED25519_TYPE) or blob[4:type_end] != _ED25519_TYPE:
        raise RotationError("public key is not ssh-ed25519")
    if len(blob) < type_end + 4:
        raise RotationError("public key blob is truncated")
    key_len = int.from_bytes(blob[type_end : type_end + 4], "big")
    key_end = type_end + 4 + key_len
    if key_len != 32 or key_end != len(blob):
        raise RotationError("public key has unexpected length")


def key_material(line: str) -> str | None:
    """Return ssh-ed25519 material from a line, including an option prefix."""
    parts = line.split()
    for index, part in enumerate(parts):
        if part == "ssh-ed25519" and index + 1 < len(parts):
            return parts[index + 1]
    return None


def format_bot_line(mode: str, material: str) -> str:
    """Return one authorized_keys line with the exact bootstrap prefix for ``mode``."""
    try:
        options, comment = _MODES[mode]
    except KeyError as exc:
        raise RotationError("unknown mode; pass strict or open") from exc
    _validate_ed25519_material(material)
    return f"{options} ssh-ed25519 {material} {comment}"


def _mode_of_options(options: str) -> str | None:
    for mode, (required, _comment) in _MODES.items():
        if options == required or options.startswith(required + ","):
            return mode
    return None


def _require_admin() -> None:
    if os.geteuid() != 0:
        raise RotationError(
            "rotation runs only as root from an admin session; "
            "the bot key cannot change its own credentials"
        )
    if os.environ.get("SUDO_USER") == BOT_USER:
        raise RotationError("the sidecomputer user cannot rotate its own key")


def _bot_user_ids() -> tuple[int, int]:
    try:
        user = pwd.getpwnam(BOT_USER)
    except KeyError as exc:
        raise RotationError(f"user {BOT_USER} does not exist") from exc
    return user.pw_uid, user.pw_gid


def _line_options(line: str) -> str:
    parts = line.split()
    for index, part in enumerate(parts):
        if part == "ssh-ed25519":
            return " ".join(parts[:index])
    return ""


def build_authorized_keys(
    existing: str,
    *,
    mode: str | None,
    bot_material: str | None,
    retire_materials: set[str],
) -> str:
    """Return the full file body: one exact bootstrap bot line, or empty."""
    for raw in existing.splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        material = key_material(line)
        if material is None:
            raise RotationError(
                "keys file contains a non-ed25519 line; admin keys belong in "
                "the admin user's authorized_keys"
            )
        if material not in retire_materials:
            raise RotationError(
                "keys file contains a key that is not being retired; "
                "admin keys belong in the admin user's authorized_keys"
            )
        options = _line_options(line)
        if options and mode is not None and _mode_of_options(options) not in (None, mode):
            raise RotationError("existing key prefix does not match the requested mode")

    if bot_material is None:
        return ""
    if mode is None:
        raise RotationError("pass --mode strict or --mode open")
    if bot_material in retire_materials:
        raise RotationError("new bot key is also listed for retirement")
    return format_bot_line(mode, bot_material) + "\n"


def rotate_bot_key(
    keys_file: Path,
    *,
    bot_pubkey: str | None,
    retire_pubkeys: list[str],
    mode: str | None,
    replace_all: bool,
    remove_bot: bool,
    abort_before_rename: bool = False,
) -> None:
    """Replace ``keys_file`` in one rename, or leave it untouched on failure."""
    _require_admin()
    if remove_bot and bot_pubkey:
        raise RotationError("pass either a new bot key or --remove-bot")
    if not remove_bot and not bot_pubkey:
        raise RotationError("pass a new bot key or --remove-bot")
    if not replace_all:
        raise RotationError("pass --replace-all; appending a key is not a rotation")
    if not remove_bot and mode not in _MODES:
        raise RotationError("unknown mode; pass strict or open")

    bot_material = None if remove_bot else public_key_material(bot_pubkey or "")
    retire_materials = {public_key_material(pubkey) for pubkey in retire_pubkeys}
    keys_path = Path(keys_file)
    if keys_path.is_symlink():
        raise RotationError("refusing to replace a symlink")

    existing = ""
    if keys_path.exists():
        existing = keys_path.read_text(encoding="utf-8")
    elif retire_pubkeys:
        raise RotationError("keys file does not exist")

    content = build_authorized_keys(
        existing,
        mode=mode,
        bot_material=bot_material,
        retire_materials=retire_materials,
    )
    owner = _bot_user_ids()
    _commit(keys_path, content.encode("utf-8"), owner, abort_before_rename)


def _write_all(descriptor: int, content: bytes) -> None:
    view = memoryview(content)
    while view:
        written = os.write(descriptor, view)
        if written <= 0:
            raise RotationError("failed to write the new keys file")
        view = view[written:]


def _commit(
    path: Path,
    content: bytes,
    owner: tuple[int, int],
    abort_before_rename: bool,
) -> None:
    directory = path.parent
    if not directory.is_dir():
        raise RotationError("keys directory does not exist")
    descriptor, tmp_name = tempfile.mkstemp(prefix=".authorized_keys.", dir=directory)
    tmp_path: Path | None = Path(tmp_name)
    closed = False
    try:
        os.fchmod(descriptor, 0o600)
        os.fchown(descriptor, owner[0], owner[1])
        _write_all(descriptor, content)
        os.fsync(descriptor)
        os.close(descriptor)
        closed = True
        if abort_before_rename:
            raise RotationError("aborted before rename")
        os.replace(tmp_path, path)
        tmp_path = None
        try:
            dir_fd = os.open(directory, os.O_RDONLY)
        except OSError:
            return
        try:
            os.fsync(dir_fd)
        except OSError:
            return
        finally:
            os.close(dir_fd)
    finally:
        if not closed:
            os.close(descriptor)
        if tmp_path is not None and tmp_path.exists():
            tmp_path.unlink()


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Atomically replace the SideComputer bot key. "
            "Admin session only. There is no keep-line list."
        )
    )
    parser.add_argument("--keys-file", required=True, type=Path)
    parser.add_argument("--bot-pubkey", default=None)
    parser.add_argument("--retire-pubkey", action="append", default=[])
    parser.add_argument("--mode", choices=sorted(_MODES))
    parser.add_argument("--replace-all", action="store_true")
    parser.add_argument("--remove-bot", action="store_true")
    args = parser.parse_args(argv)
    try:
        rotate_bot_key(
            args.keys_file,
            bot_pubkey=args.bot_pubkey,
            retire_pubkeys=args.retire_pubkey,
            mode=args.mode,
            replace_all=args.replace_all,
            remove_bot=args.remove_bot,
        )
    except RotationError as exc:
        print(f"rotate_bot_key: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
