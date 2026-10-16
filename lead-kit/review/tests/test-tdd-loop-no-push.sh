#!/usr/bin/env bash
# M3: worktree hooksPath blocks git push <url>; shared remotes untouched.
set -euo pipefail
D=$(cd "$(dirname "$0")" && pwd)
LOOP="$D/../tdd-loop.sh"
pass=0; fail=0
ok() { echo "PASS $1"; pass=$((pass+1)); }
bad() { echo "FAIL $1"; shift; printf '%s\n' "$@" | tail -20; fail=$((fail+1)); }

ROOT=$(mktemp -d)
trap 'rm -rf "$ROOT"' EXIT
git -C "$ROOT" init -q
git -C "$ROOT" config user.email t@t
git -C "$ROOT" config user.name t
echo hi > "$ROOT/README"
git -C "$ROOT" add README
git -C "$ROOT" commit -qm init
BARE=$(mktemp -d)
git -C "$BARE" init --bare -q
git -C "$ROOT" remote add origin "$BARE"
git -C "$ROOT" push -u origin HEAD:main >/dev/null 2>&1

INV="$ROOT/INVARIANTS.md"
echo "# invariants" > "$INV"
WTROOT="$ROOT/wt"
mkdir -p "$WTROOT" "$ROOT/runtime"
printf '[workspace]\nmembers = []\n' > "$ROOT/runtime/Cargo.toml"

set +e
INVARIANTS="$INV" SIDGED_REPO="$ROOT" WT_ROOT="$WTROOT" BASE_REF=HEAD CLI_TIMEOUT=1 \
  "$LOOP" --backend codex m3np 'block push' >"$ROOT/loop.log" 2>&1
set -e

WT="$WTROOT/m3np"
if [[ ! -d "$WT" ]]; then
  bad "no-worktree" "$(tail -30 "$ROOT/loop.log")"
  echo "RESULT pass=$pass fail=$fail"
  exit 1
fi

pushurl=$(git -C "$ROOT" remote get-url --push origin)
fetchurl=$(git -C "$WT" remote get-url origin)
if [[ "$pushurl" == "$BARE" ]]; then ok shared-pushurl-untouched; else bad shared-pushurl-untouched "got=$pushurl"; fi
if [[ "$fetchurl" == "$BARE" ]]; then ok worktree-fetchurl-shared; else bad worktree-fetchurl "got=$fetchurl"; fi

hp=$(git -C "$WT" config --get --worktree core.hooksPath || true)
if [[ -n "$hp" && -x "$hp/pre-push" ]]; then ok worktree-hooksPath; else bad worktree-hooksPath "hp=$hp"; fi

main_hp=$(git -C "$ROOT" config --get core.hooksPath || true)
if [[ -z "$main_hp" ]]; then ok main-no-hooksPath; else bad main-no-hooksPath "hp=$main_hp"; fi

set +e
git -C "$WT" commit --allow-empty -qm 'empty for push test' 2>/dev/null
out=$(git -C "$WT" push "$BARE" HEAD:refs/heads/should-fail 2>&1)
rc=$?
set -e
if [[ $rc -ne 0 ]] && echo "$out" | grep -Eqi 'push forbidden|pre-push|hook'; then
  ok worktree-push-url-blocked
else
  bad worktree-push-url-blocked "rc=$rc" "$out"
fi

set +e
git -C "$ROOT" commit --allow-empty -qm 'main still pushes'
out=$(git -C "$ROOT" push origin HEAD:refs/heads/main-ok 2>&1)
rc=$?
set -e
if [[ $rc -eq 0 ]]; then ok main-repo-push-unaffected; else bad main-repo-push-unaffected "rc=$rc" "$out"; fi

echo "RESULT pass=$pass fail=$fail"
[[ "$fail" -eq 0 ]]
