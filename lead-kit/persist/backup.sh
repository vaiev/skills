#!/usr/bin/env bash
# Snapshot configured paths; all local snapshots are encrypted.
set -euo pipefail
source "$(dirname "$0")/common.sh"
[[ $# -eq 0 || ( $# -eq 1 && $1 == --no-vps ) ]] || { echo "usage: $0 [--no-vps]" >&2; exit 2; }
umask 077
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
TS=$(date +%Y%m%d-%H%M%S)
if [ ! -r "$STORE/passphrase" ]; then
  [ "${1:-}" != --no-vps ] || { echo "ERROR: readable store passphrase required for local backup" >&2; exit 3; }
  T=$(python3 "$K/plain_backup.py")
  trap 'rm -rf "$TMP" "$(dirname "$T")"' EXIT
  (cd "$(dirname "$T")" && sha256sum "$(basename "$T")" > "$T.sha256")
  for file in "$T" "$T.sha256" "$T.dropped"; do "$PY" "$K/vps.py" push "$file" plain; done
  "$PY" "$K/vps.py" prune plain
  echo "plain backup uploaded (secret-scanned)"
  exit 0
fi
: "${PERSIST_INCLUDE:?PERSIST_INCLUDE is required}"
# Read shell-quoted paths without evaluating them. Preserve spaces in paths.
mapfile -d '' -t INCLUDE < <(python3 -c 'import os,shlex,sys;sys.stdout.buffer.write(b"".join(os.fsencode(os.path.abspath(os.path.expanduser(p)))+b"\0" for p in shlex.split(os.environ["PERSIST_INCLUDE"])))')
[ ${#INCLUDE[@]} -gt 0 ] || { echo "ERROR: no include paths" >&2; exit 2; }
# Store must live outside includes to avoid recursively archiving snapshots.
python3 - "${INCLUDE[@]}" <<'PY'
import os, sys
store = os.path.realpath(os.environ["PERSIST_STORE"])
for path in sys.argv[1:]:
    if os.path.commonpath([store, os.path.realpath(path)]) == os.path.realpath(path):
        sys.exit("ERROR: PERSIST_STORE must be outside included paths")
PY
ARGS=()
for path in "${INCLUDE[@]}"; do ARGS+=("${path#/}"); done
EX=(--exclude=.git --exclude=node_modules --exclude=.venv --exclude=venv --exclude=__pycache__ --exclude=target --exclude=dist --exclude=.next)
if [ -n "${HUB_DB:-}" ]; then
  python3 - "$TMP/hub.db" <<'PY'
import os, sqlite3, sys
from pathlib import Path
with sqlite3.connect(Path(os.environ["HUB_DB"]).expanduser().resolve().as_uri()+"?mode=ro", uri=True) as source:
    with sqlite3.connect(sys.argv[1]) as target:
        source.backup(target)
PY
  DB=$(python3 -c 'import os; print(os.path.abspath(os.path.expanduser(os.environ["HUB_DB"])))')
  EX+=(--exclude="${DB#/}" --exclude="${DB#/}-*")
fi
tar czf "$TMP/state.tgz" "${EX[@]}" -C / "${ARGS[@]}"
# Include a consistent DB copy at its configured archive path.
if [ -f "$TMP/hub.db" ]; then
  gzip -dc "$TMP/state.tgz" > "$TMP/state.tar"
  mkdir -p "$TMP/db/$(dirname "${DB#/}")"
  cp "$TMP/hub.db" "$TMP/db/${DB#/}"
  tar rf "$TMP/state.tar" -C "$TMP/db" "${DB#/}"
  gzip "$TMP/state.tar"; mv "$TMP/state.tar.gz" "$TMP/state.tgz"
fi
mkdir -p "$STORE/snapshots"
openssl enc -aes-256-cbc -pbkdf2 -iter 200000 -salt -pass "file:$STORE/passphrase" -in "$TMP/state.tgz" -out "$STORE/snapshots/state-$TS.tgz.enc"
cp "$STORE/snapshots/state-$TS.tgz.enc" "$STORE/snapshots/state-latest.tgz.enc"
(cd "$STORE/snapshots" && sha256sum "state-$TS.tgz.enc" > "SHA256SUMS-$TS")
find "$STORE/snapshots" -name 'state-2*.enc' -printf '%f\n' | sort -r | tail -n +6 | while IFS= read -r file; do rm -f "$STORE/snapshots/$file"; done
if [ "${1:-}" != --no-vps ]; then
  "$PY" "$K/vps.py" push "$STORE/snapshots/state-$TS.tgz.enc"
  "$PY" "$K/vps.py" prune
fi
echo "backup $TS -> $STORE/snapshots"
