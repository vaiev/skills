#!/usr/bin/env bash
# Step 3c: pinned ci-local gate, isolated env, fail closed.
set -euo pipefail
D=$(cd "$(dirname "$0")" && pwd)
LOOP="$D/../tdd-loop.sh"
pass=0; fail=0
ok() { echo "PASS $1"; pass=$((pass+1)); }
bad() { echo "FAIL $1"; shift; printf '%s\n' "$@" | tail -30; fail=$((fail+1)); }

ROOT=$(mktemp -d); trap 'rm -rf "$ROOT"' EXIT
REPO="$ROOT/repo"; BARE="$ROOT/bare.git"
git init -q --bare "$BARE"
git init -q "$REPO"; git -C "$REPO" config user.email t@t; git -C "$REPO" config user.name t
mkdir -p "$REPO/runtime" "$REPO/scripts"
printf '[workspace]\nmembers = []\n' > "$REPO/runtime/Cargo.toml"
# Fake ci-local: records the env it sees, then passes.
cat > "$REPO/scripts/ci-local.sh" <<'S'
#!/usr/bin/env bash
{
  echo "HOME=$HOME"
  for v in CI_LOCAL_SKIP CI_LOCAL_BASE GH_TOKEN GITHUB_TOKEN VAIEV_GH_TOKEN VAIEV_ROOT SSH_AUTH_SOCK; do
    echo "$v=${!v+SET}${!v-UNSET}"
  done
  echo "GIT_CONFIG_GLOBAL=${GIT_CONFIG_GLOBAL-}"
} > "${TMPDIR:-/tmp}/ci-local-env.$PPID.txt"
cp "${TMPDIR:-/tmp}/ci-local-env.$PPID.txt" "$(git rev-parse --show-toplevel)/.tdd/ci-env.txt"
exit 0
S
chmod +x "$REPO/scripts/ci-local.sh"
git -C "$REPO" config branch.autoSetupMerge false
git -C "$REPO" add -A; git -C "$REPO" commit -qm init
git -C "$REPO" remote add origin "$BARE"; git -C "$REPO" push -q origin HEAD:main; git -C "$REPO" fetch -q origin
echo "# inv" > "$ROOT/INV.md"

BIN="$ROOT/bin"; mkdir -p "$BIN"
printf '#!/usr/bin/env bash\nexit 0\n' > "$BIN/cargo"; chmod +x "$BIN/cargo"
# codex: writes a plan; if TAMPER=1, rewrites the worktree ci-local to exit 0 differently.
cat > "$BIN/codex" <<'C'
#!/usr/bin/env bash
wt=""; while [[ $# -gt 0 ]]; do case "$1" in --cd) wt="$2"; shift 2;; -) break;; *) shift;; esac; done
mkdir -p "$wt/.tdd"; printf '# plan\n' > "$wt/.tdd/plan.md"
if [[ "${TAMPER:-0}" == 1 ]]; then printf '#!/bin/sh\nexit 0\n' > "$wt/scripts/ci-local.sh"; fi
exit 0
C
chmod +x "$BIN/codex"
export PATH="$BIN:$PATH" TMPDIR="$ROOT/tmp"; mkdir -p "$TMPDIR"
export GH_TOKEN=x GITHUB_TOKEN=x VAIEV_GH_TOKEN=x SSH_AUTH_SOCK=/nonexistent VAIEV_ROOT=/nonexistent
export CI_LOCAL_SKIP="test clippy" CI_LOCAL_BASE=HEAD

loop() { # task, extra args...
  local t=$1; shift
  set +e
  INVARIANTS="$ROOT/INV.md" SIDGED_REPO="$REPO" WT_ROOT="$ROOT/wt" BASE_REF=origin/main CLI_TIMEOUT=30 \
    "$LOOP" --backend codex "$@" "$t" 'desc' > "$ROOT/$t.log" 2>&1
  rc=$?; set -e
}

# 1) unmodified script: GREEN, caller CI_LOCAL_*/tokens/VAIEV_* never reach ci-local
loop t1
E="$ROOT/wt/t1/.tdd/ci-env.txt"
if [[ $rc -eq 0 && -f $E ]]; then ok gate-green; else bad gate-green "rc=$rc" "$(cat "$ROOT/t1.log")"; fi
if [[ -f $E ]] && grep -q 'CI_LOCAL_SKIP=UNSET' "$E" && grep -q 'CI_LOCAL_BASE=UNSET' "$E" \
  && grep -q 'GH_TOKEN=UNSET' "$E" && grep -q 'GITHUB_TOKEN=UNSET' "$E" && grep -q 'VAIEV_GH_TOKEN=UNSET' "$E" \
  && grep -q 'VAIEV_ROOT=UNSET' "$E" && grep -q 'SSH_AUTH_SOCK=UNSET' "$E" && grep -q 'GIT_CONFIG_GLOBAL=/dev/null' "$E"; then
  ok ci-local-env-isolated
else bad ci-local-env-isolated "$(cat "$E" 2>/dev/null)"; fi
h=$(grep '^HOME=' "$E" 2>/dev/null | cut -d= -f2-)
if [[ -n $h && $h != "$HOME" && $h == "$TMPDIR"/tdd-loop-build-home.* ]]; then ok ci-local-temp-home; else bad ci-local-temp-home "HOME=$h"; fi
if grep -q '^\[x\] scripts/ci-local.sh GREEN' "$ROOT/t1.log"; then ok dod-ticked-real-run; else bad dod-ticked-real-run "$(grep ci-local "$ROOT/t1.log")"; fi

# 2) agent tampers with the worktree script: ABORT
TAMPER=1 loop t2
if [[ $rc -ne 0 ]] && grep -q 'differs from pinned' "$ROOT/t2.log"; then ok tampered-script-refused; else bad tampered-script-refused "rc=$rc" "$(tail -5 "$ROOT/t2.log")"; fi

# 3) --ci-local with a wrong sha256: ABORT
loop t3 --ci-local "$REPO/scripts/ci-local.sh" --ci-local-sha256 "$(printf '0%.0s' {1..64})"
if [[ $rc -ne 0 ]] && grep -q 'sha256 .* != expected' "$ROOT/t3.log"; then ok wrong-sha-refused; else bad wrong-sha-refused "rc=$rc" "$(tail -5 "$ROOT/t3.log")"; fi

# 4) --ci-local with the right sha256: GREEN
loop t4 --ci-local "$REPO/scripts/ci-local.sh" --ci-local-sha256 "$(sha256sum "$REPO/scripts/ci-local.sh" | cut -d' ' -f1)"
if [[ $rc -eq 0 ]]; then ok explicit-pin-green; else bad explicit-pin-green "rc=$rc" "$(tail -5 "$ROOT/t4.log")"; fi

# 5) base without ci-local.sh (sidged #74 not merged): ABORT with a clear message
git -C "$REPO" rm -q scripts/ci-local.sh; git -C "$REPO" commit -qm rm; git -C "$REPO" push -q origin HEAD:main; git -C "$REPO" fetch -q origin
loop t5
if [[ $rc -ne 0 ]] && grep -q 'has no scripts/ci-local.sh' "$ROOT/t5.log"; then ok missing-pin-refused; else bad missing-pin-refused "rc=$rc" "$(tail -5 "$ROOT/t5.log")"; fi

# 6) dry-run never pre-ticks the DoD line
loop t6 --dry-run
if grep -q '^\[ \] scripts/ci-local.sh GREEN' "$ROOT/t6.log" && ! grep -q '^\[x\]' "$ROOT/t6.log"; then ok dry-run-dod-unticked; else bad dry-run-dod-unticked "$(grep ci-local "$ROOT/t6.log")"; fi

echo "RESULT pass=$pass fail=$fail"
[[ $fail -eq 0 ]]
