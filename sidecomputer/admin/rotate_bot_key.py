#!/usr/bin/env python3
"""Atomically replace the SideComputer bot key in an authorized_keys file.

The new file is written in full, fsynced, and renamed over the destination.
A failure before that rename leaves the original file in place, so the
previous bot key stays the only bot key from that file. There is no step
where the old key and the new key are both authorized.

Use ``--replace-all`` for rotation and removal. That mode does not copy
lines out of the old file, so an unmarked key left behind by bootstrap
cannot remain valid.
"""

from __future__ import annotations

import argparse
import base64
import os
import sys
import tempfile
from pathlib import Path

BOT_MARKER = "sidecomputer-bot"
_ED25519_TYPE = b"ssh-ed25519"
_ED25519_PREFIX = "ssh-ed25519 "


class RotationError(Exception):
    """The keys file was left unchanged."""


def parse_bot_pubkey(text: str) -> str:
    """Return one authorized_keys line for the new bot key."""
    material = public_key_material(text)
    return f"{_ED25519_PREFIX}{material} {BOT_MARKER}"


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
    """Return ssh-ed25519 material from a line, including option-prefixed lines."""
    parts = line.split()
    for index, part in enumerate(parts):
        if part == "ssh-ed25519" and index + 1 < len(parts):
            return parts[index + 1]
    return None


def build_authorized_keys(
    existing: str,
    *,
    bot_line: str | None,
    retire_materials: set[str],
    keep_lines: list[str],
    replace_all: bool,
) -> str:
    """Return the full authorized_keys body that should replace the file."""
    kept: list[str] = []
    if not replace_all:
        for raw in existing.splitlines():
            line = raw.strip()
            if not line:
                continue
            if BOT_MARKER in line:
                continue
            material = key_material(line)
            if material is not None and material in retire_materials:
                continue
            kept.append(line)

    new_material = key_material(bot_line) if bot_line is not None else None
    for raw in keep_lines:
        if "\n" in raw or "\r" in raw or "\x00" in raw:
            raise RotationError("keep line must be a single line")
        line = raw.strip()
        if not line:
            raise RotationError("keep line is empty")
        if BOT_MARKER in line:
            raise RotationError("keep line cannot carry the bot marker")
        material = key_material(line)
        if material is not None and material in retire_materials:
            raise RotationError("keep line contains a retired key")
        if new_material is not None and material == new_material:
            raise RotationError("keep line duplicates the new bot key")
        if line not in kept:
            kept.append(line)

    if bot_line is not None:
        if new_material is None:
            raise RotationError("bot line is not an ssh-ed25519 key")
        if new_material in retire_materials:
            raise RotationError("new bot key is also listed for retirement")
        kept.append(bot_line)

    for line in kept:
        material = key_material(line)
        if material is not None and material in retire_materials:
            raise RotationError("retired key would remain authorized")
        if BOT_MARKER in line and line != bot_line:
            raise RotationError("an old bot key would remain authorized")

    if bot_line is not None:
        copies = [line for line in kept if key_material(line) == new_material]
        if copies != [bot_line]:
            raise RotationError("new bot key must appear exactly once")

    body = "\n".join(kept)
    if body:
        body += "\n"
    return body


def rotate_bot_key(
    keys_file: Path,
    *,
    bot_pubkey: str | None,
    retire_pubkeys: list[str],
    keep_lines: list[str],
    replace_all: bool,
    remove_bot: bool,
    abort_before_rename: bool = False,
) -> None:
    """Replace ``keys_file`` in one rename, or leave it untouched on failure."""
    if remove_bot and bot_pubkey:
        raise RotationError("pass either a new bot key or --remove-bot")
    if not remove_bot and not bot_pubkey:
        raise RotationError("pass a new bot key or --remove-bot")
    if not replace_all and not retire_pubkeys:
        raise RotationError("pass --replace-all or at least one --retire-pubkey")

    bot_line = None if remove_bot else parse_bot_pubkey(bot_pubkey or "")
    retire_materials = {public_key_material(pubkey) for pubkey in retire_pubkeys}
    keys_path = Path(keys_file)
    if keys_path.is_symlink():
        raise RotationError("refusing to replace a symlink")

    existing = ""
    if keys_path.exists():
        existing = keys_path.read_text(encoding="utf-8")
    elif not replace_all:
        raise RotationError("keys file does not exist; use --replace-all to create it")

    content = build_authorized_keys(
        existing,
        bot_line=bot_line,
        retire_materials=retire_materials,
        keep_lines=keep_lines,
        replace_all=replace_all,
    )
    _commit(keys_path, content.encode("utf-8"), abort_before_rename)


def _write_all(descriptor: int, content: bytes) -> None:
    view = memoryview(content)
    while view:
        written = os.write(descriptor, view)
        if written <= 0:
            raise RotationError("failed to write the new keys file")
        view = view[written:]


def _commit(path: Path, content: bytes, abort_before_rename: bool) -> None:
    directory = path.parent
    if not directory.is_dir():
        raise RotationError("keys directory does not exist")
    descriptor, tmp_name = tempfile.mkstemp(prefix=".authorized_keys.", dir=directory)
    tmp_path: Path | None = Path(tmp_name)
    closed = False
    try:
        os.fchmod(descriptor, 0o600)
        _write_all(descriptor, content)
        os.fsync(descriptor)
        os.close(descriptor)
        closed = True
        if abort_before_rename:
            raise RotationError("aborted before rename")
        os.replace(tmp_path, path)
        tmp_path = None
        # The rename has committed. A later directory fsync failure must not
        # look like a failed rotation, or the caller would discard the new key
        # while the host already trusts it.
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
        description="Atomically replace the SideComputer bot key in authorized_keys."
    )
    parser.add_argument("--keys-file", required=True, type=Path)
    parser.add_argument("--bot-pubkey", default=None)
    parser.add_argument("--retire-pubkey", action="append", default=[])
    parser.add_argument("--keep-line", action="append", default=[])
    parser.add_argument("--replace-all", action="store_true")
    parser.add_argument("--remove-bot", action="store_true")
    args = parser.parse_args(argv)
    try:
        rotate_bot_key(
            args.keys_file,
            bot_pubkey=args.bot_pubkey,
            retire_pubkeys=args.retire_pubkey,
            keep_lines=args.keep_line,
            replace_all=args.replace_all,
            remove_bot=args.remove_bot,
        )
    except RotationError as exc:
        print(f"rotate_bot_key: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
