#!/usr/bin/env bash
# Restore archived absolute paths under / or an explicit dry-run directory.
set -euo pipefail
source "$(dirname "$0")/common.sh"
ROOT=/; TS=latest; FROMVPS=0; PLAIN=0
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) ROOT=${2:?directory required}; shift 2;;
    --snapshot) TS=${2:?snapshot required}; shift 2;;
    --from-vps) FROMVPS=1; shift;;
    --plain) PLAIN=1; shift;;
    --skip-install) shift;; # Compatibility: restore no longer installs software.
    *) echo "bad argument: $1" >&2; exit 2;;
  esac
done
[[ "$TS" =~ ^[A-Za-z0-9-]+$ ]] || { echo "invalid snapshot" >&2; exit 2; }
umask 077
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
if [ "$PLAIN" = 1 ]; then
  N=$("$PY" "$K/vps.py" ls plain | grep -E '^plain-[0-9-]+\.tgz$' | sort | tail -1)
  [ -n "$N" ] || { echo "no plain snapshots" >&2; exit 3; }
  "$PY" "$K/vps.py" pull "plain/$N" "$TMP/$N"
  "$PY" "$K/vps.py" pull "plain/$N.sha256" "$TMP/$N.sha256"
  (cd "$TMP" && sha256sum -c "$N.sha256")
  ARCHIVE="$TMP/$N"
else
  SRC="$STORE/snapshots/state-$TS.tgz.enc"
  if [ "$FROMVPS" = 1 ]; then
    if [ "$TS" = latest ]; then
      N=$("$PY" "$K/vps.py" ls | grep -E '^state-[0-9-]+\.tgz\.enc$' | sort | tail -1)
    else N="state-$TS.tgz.enc"; fi
    [ -n "$N" ] || { echo "no encrypted snapshots" >&2; exit 3; }
    "$PY" "$K/vps.py" pull "$N" "$TMP/state.enc"; SRC="$TMP/state.enc"
  fi
  ARCHIVE="$TMP/state.tgz"
  openssl enc -d -aes-256-cbc -pbkdf2 -iter 200000 -pass "file:$STORE/passphrase" -in "$SRC" -out "$ARCHIVE"
fi
mkdir -p "$ROOT"
# data filter rejects traversal, external links, devices and other unsafe members.
python3 - "$ARCHIVE" "$ROOT" <<'PY'
import sys, tarfile
with tarfile.open(sys.argv[1]) as archive:
    archive.extractall(sys.argv[2], filter="data")
PY
echo "restored files into $ROOT"
