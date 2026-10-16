#!/usr/bin/env bash
# tdd-loop.sh — worktree-scoped TDD template (replaces agy-superpowers-loop.sh)
# Usage: tdd-loop.sh [--dry-run] [--backend codex|grok|agy]
#                    [--ci-local <path> --ci-local-sha256 <hex>] <TASK_ID> "<TASK_DESCRIPTION>"
#   ci-local gate (step 3c): runs a PINNED copy of scripts/ci-local.sh outside the
#   worktree: by default `git show $BASE_REF:scripts/ci-local.sh`; or --ci-local <path>
#   whose sha256 must equal --ci-local-sha256. The worktree's own copy must be
#   byte-identical to the pinned one. No pinned script = ABORT (fail closed).
#
# Rules (enforced / instructed):
#   * One git worktree per task: /workspace/vaiev/wt/<TASK_ID>
#   * Tests first: RED -> GREEN -> REFACTOR
#   * Agent must check its work against /workspace/vaiev/INVARIANTS.md
#   * Step 1 plan is written to a file and passed as a file into step 2
#   * NEVER push, merge or force-push. Handover to WOUFbot / safe-merge only.
#   * No skip-permissions flags. No secrets in logs (env is never echoed).
#   * CLI prompts say "do not commit"; this script commits with -s after green tests.
#   * CLI runs in a fresh HOME with only whitelisted CLI auth dirs; remote refs
#     are snapshotted and re-checked (including on EXIT).
set -euo pipefail

REPO="${SIDGED_REPO:-/workspace/vaiev/sidged}"
WT_ROOT="${WT_ROOT:-/workspace/vaiev/wt}"
INVARIANTS="${INVARIANTS:-/workspace/vaiev/INVARIANTS.md}"
BASE_REF="${BASE_REF:-origin/main}"
DRY_RUN=0
BACKEND="codex"
CLI_TIMEOUT="${CLI_TIMEOUT:-1800}"

CI_LOCAL_PATH=""; CI_LOCAL_SHA=""

usage() { echo "Usage: $0 [--dry-run] [--backend codex|grok|agy] [--ci-local <path> --ci-local-sha256 <hex>] <TASK_ID> <TASK_DESCRIPTION>" >&2; exit 2; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    --backend) BACKEND="${2:?}"; shift 2 ;;
    --ci-local) CI_LOCAL_PATH="${2:?}"; shift 2 ;;
    --ci-local-sha256) CI_LOCAL_SHA="${2:?}"; shift 2 ;;
    -h|--help) usage ;;
    --) shift; break ;;
    -*) usage ;;
    *) break ;;
  esac
done

TASK_ID="${1:-}"; TASK_DESC="${2:-}"
[[ -n "$TASK_ID" && -n "$TASK_DESC" ]] || usage
[[ "$TASK_ID" =~ ^[A-Za-z0-9._-]+$ ]] || {
  echo "TASK_ID must match ^[A-Za-z0-9._-]+$" >&2
  exit 2
}
case "$TASK_ID" in
  *..*|*/*|*\\*) echo "TASK_ID must not contain '..' or path separators" >&2; exit 2 ;;
esac
[[ "$TASK_ID" != "." ]] || { echo "TASK_ID must not be '.'" >&2; exit 2; }
case "$BACKEND" in codex|grok|agy) ;; *) usage ;; esac
if [[ -n "$CI_LOCAL_PATH" || -n "$CI_LOCAL_SHA" ]]; then
  [[ -n "$CI_LOCAL_PATH" && "$CI_LOCAL_SHA" =~ ^[0-9a-f]{64}$ ]] || {
    echo "--ci-local and --ci-local-sha256 <64 hex> must be given together" >&2; exit 2; }
fi

WT="$WT_ROOT/$TASK_ID"
BRANCH="tdd/$TASK_ID"
ART="$WT/.tdd"
PLAN="$ART/plan.md"
LOG="$ART/run.log"
REFS_SNAP="$ART/remote-refs.snap"
CLI_HOME=""
PROMPT1=""; PROMPT2=""
REAL_HOME="${HOME:-}"

# run: print the command; execute only when not dry-run. Never prints env.
run() {
  printf '+'; printf ' %q' "$@"; printf '\n'
  if [[ $DRY_RUN -eq 0 ]]; then "$@"; fi
}

# Redact anything resembling a token before it reaches the log.
# Build markers without contiguous secret prefixes (tests/test_release.py).
_sk=$'sk''-'
_ghp=$'gh''p_'
_xai=$'xai''-'
redact() {
  sed -E "s/(${_ghp}[A-Za-z0-9]{20,}|gh[ousr]_[A-Za-z0-9]{20,}|${_sk}[A-Za-z0-9_-]{20,}|${_xai}[A-Za-z0-9]{20,}|(api[_-]?key|token|secret|password)[\"=: ]+[^ \"]+)/[REDACTED]/Ig"
}

# Collect ls-remote for every remote (sorted). Fail closed on ls-remote error.
collect_remote_refs() {
  local remote out refs
  out=""
  while IFS= read -r remote; do
    [[ -n "$remote" ]] || continue
    if ! refs=$(git -C "$WT" ls-remote "$remote" 2>/dev/null); then
      echo "ABORT: git ls-remote failed for remote '$remote' (fail-closed)" >&2
      return 1
    fi
    out+=$(printf 'REMOTE %s\n%s\n' "$remote" "$(printf '%s\n' "$refs" | LC_ALL=C sort)")
    out+=$'\n'
  done < <(git -C "$WT" remote)
  printf '%s' "$out"
}

snapshot_remote_refs() {
  [[ $DRY_RUN -eq 0 ]] || return 0
  mkdir -p "$ART"
  collect_remote_refs > "$REFS_SNAP"
}

# Return 0 if unchanged, 1 if changed/error (does not exit — for trap use).
assert_remote_refs_unchanged() {
  [[ $DRY_RUN -eq 0 ]] || return 0
  local now
  now=$(mktemp)
  if ! collect_remote_refs > "$now"; then
    rm -f "$now"
    return 1
  fi
  if [[ ! -f "$REFS_SNAP" ]]; then
    echo "ABORT: missing remote-refs snapshot at $REFS_SNAP" >&2
    rm -f "$now"
    return 1
  fi
  if ! cmp -s "$REFS_SNAP" "$now"; then
    echo "ABORT: remote refs changed during tdd-loop (push detected; fail-closed)" >&2
    echo "--- before ---" >&2
    cat "$REFS_SNAP" >&2 || true
    echo "--- after ---" >&2
    cat "$now" >&2 || true
    rm -f "$now"
    return 1
  fi
  rm -f "$now"
  return 0
}

# Fresh HOME for the CLI: empty XDG/GH config, no system/global git config,
# SSH blocked. Whitelist-copy only CLI auth dirs (.codex / .grok / .agy).
# Never copy ~/.git-credentials, ~/.config/gh, ~/.ssh.
prepare_cli_home() {
  local src dst old_umask
  # umask 077: copied login material must not be group/world readable.
  old_umask=$(umask); umask 077
  CLI_HOME=$(mktemp -d "${TMPDIR:-/tmp}/tdd-loop-cli-home.XXXXXX")
  mkdir -p "$CLI_HOME/.xdg-config" "$CLI_HOME/.gh-config"
  if [[ -n "$REAL_HOME" && -d "$REAL_HOME" ]]; then
    for src in .codex .grok .agy; do
      if [[ -e "$REAL_HOME/$src" ]]; then
        dst="$CLI_HOME/$src"
        cp -a "$REAL_HOME/$src" "$dst"
      fi
    done
    # agy may keep auth under XDG; copy only that subdir into the empty XDG tree.
    if [[ -e "$REAL_HOME/.config/agy" ]]; then
      mkdir -p "$CLI_HOME/.xdg-config"
      cp -a "$REAL_HOME/.config/agy" "$CLI_HOME/.xdg-config/agy"
    fi
  fi
  chmod -R go-rwx "$CLI_HOME"
  umask "$old_umask"
}

cleanup_cli_home() {
  if [[ -n "${CLI_HOME:-}" && -d "$CLI_HOME" ]]; then
    rm -rf "$CLI_HOME"
    CLI_HOME=""
  fi
}

on_exit() {
  local ec=$?
  rm -f "${PROMPT1:-}" "${PROMPT2:-}"
  if [[ $DRY_RUN -eq 0 && -n "${REFS_SNAP:-}" && -f "$REFS_SNAP" ]]; then
    if ! assert_remote_refs_unchanged; then
      cleanup_cli_home
      exit 1
    fi
  fi
  cleanup_cli_home
  cleanup_build_home
  [[ -n "${CI_PIN:-}" ]] && rm -f "$CI_PIN"
  exit "$ec"
}

# Run agent CLI with NO git credentials and an isolated HOME.
run_cli_no_git_creds() {
  [[ -n "$CLI_HOME" && -d "$CLI_HOME" ]] || prepare_cli_home
  # Never print env. Strip tokens/askpass/ssh-agent; block SSH; ignore
  # system/global git config; empty credential.helper.
  env -u GH_TOKEN -u GITHUB_TOKEN -u VAIEV_GH_TOKEN -u SSH_AUTH_SOCK -u GIT_ASKPASS \
    -u GIT_CONFIG_PARAMETERS \
    HOME="$CLI_HOME" \
    XDG_CONFIG_HOME="$CLI_HOME/.xdg-config" \
    GH_CONFIG_DIR="$CLI_HOME/.gh-config" \
    GIT_CONFIG_GLOBAL=/dev/null \
    GIT_CONFIG_NOSYSTEM=1 \
    GIT_SSH_COMMAND=/bin/false \
    GIT_TERMINAL_PROMPT=0 \
    GIT_ASKPASS=/bin/false \
    GIT_CONFIG_COUNT=1 \
    GIT_CONFIG_KEY_0=credential.helper \
    GIT_CONFIG_VALUE_0= \
    "$@"
}

# Run build/test/ci-local (agent-authored code) in a whitelisted env:
# env -i, temp HOME, no tokens/ssh-agent/askpass, no global/system git config,
# no VAIEV_* or CI_LOCAL_* from the caller. Only PATH, locale, the toolchain
# location and the explicitly resolved target dir / validator venv pass through.
BUILD_HOME=""
run_isolated() {
  [[ -n "$BUILD_HOME" && -d "$BUILD_HOME" ]] || { BUILD_HOME=$(umask 077; mktemp -d "${TMPDIR:-/tmp}/tdd-loop-build-home.XXXXXX"); }
  local rustup_home="${RUSTUP_HOME:-$REAL_HOME/.rustup}" cargo_home="${CARGO_HOME:-$REAL_HOME/.cargo}"
  local target="${CARGO_TARGET_DIR:-${VAIEV_ROOT:+$VAIEV_ROOT/target}}"
  local venv="${TDD_CI_LOCAL_VENV:-${VAIEV_TOOLS:+$VAIEV_TOOLS/venv-validate}}"
  local -a extra=()
  [[ -n "$target" ]] && extra+=("CARGO_TARGET_DIR=$target")
  [[ -n "$venv" ]] && extra+=("CI_LOCAL_VENV=$venv")
  env -i \
    PATH="$PATH" LANG="${LANG:-C.UTF-8}" TERM="${TERM:-dumb}" TMPDIR="${TMPDIR:-/tmp}" \
    HOME="$BUILD_HOME" RUSTUP_HOME="$rustup_home" CARGO_HOME="$cargo_home" \
    GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_SSH_COMMAND=/bin/false \
    GIT_TERMINAL_PROMPT=0 GIT_ASKPASS=/bin/false \
    GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=credential.helper GIT_CONFIG_VALUE_0= \
    "${extra[@]}" \
    nice -n 10 ionice -c3 "$@"
}
cleanup_build_home() { [[ -n "$BUILD_HOME" && -d "$BUILD_HOME" ]] && rm -rf "$BUILD_HOME"; BUILD_HOME=""; }

# Run agent CLI under timeout; on 429/quota/unavailable, note and exit non-zero.
# Remote-ref check also runs via EXIT trap (covers timeout/quota exits).
agent() { # agent <prompt-file>
  local pf="$1" out rc=0
  out=$(mktemp)
  case "$BACKEND" in
    codex)
      run run_cli_no_git_creds timeout "$CLI_TIMEOUT" codex exec --sandbox workspace-write --cd "$WT" - < "$pf" >"$out" 2>&1 || rc=$?
      ;;
    grok)
      run run_cli_no_git_creds timeout "$CLI_TIMEOUT" grok --cwd "$WT" --prompt-file "$pf" >"$out" 2>&1 || rc=$?
      ;;
    agy)
      run run_cli_no_git_creds timeout "$CLI_TIMEOUT" env -C "$WT" agy --sandbox --print "$(cat "$pf")" >"$out" 2>&1 || rc=$?
      ;;
  esac
  if [[ $DRY_RUN -eq 0 ]]; then
    redact < "$out" | tee -a "$LOG"
    if [[ $rc -eq 124 ]]; then
      echo "ABORT: CLI timed out after ${CLI_TIMEOUT}s (backend=$BACKEND)" >&2
      rm -f "$out"; exit 1
    fi
    if grep -Eiq 'rate limit|quota|usage limit|429|insufficient|not logged in|unauthorized|login required' "$out"; then
      echo "ABORT: CLI unavailable (429/quota/auth); fall back outside this loop (backend=$BACKEND)" >&2
      rm -f "$out"; exit 1
    fi
    rm -f "$out"
    assert_remote_refs_unchanged || exit 1
    return "$rc"
  else
    redact < "$out" || true
    rm -f "$out"
  fi
}

# Defense in depth: worktree-local pre-push hook (not the primary control).
guard_no_push_setup() {
  [[ $DRY_RUN -eq 0 ]] || return 0
  local hooks
  hooks="$ART/hooks"
  mkdir -p "$hooks"
  cat > "$hooks/pre-push" <<'HOOK'
#!/usr/bin/env bash
echo "tdd-loop: push forbidden (worktree pre-push hook)" >&2
exit 1
HOOK
  chmod 755 "$hooks/pre-push"
  git -C "$WT" config extensions.worktreeConfig true
  git -C "$WT" config --worktree core.hooksPath "$hooks"
}

guard_no_push() {
  if [[ $DRY_RUN -eq 0 ]] && git -C "$WT" rev-parse --abbrev-ref "@{u}" >/dev/null 2>&1; then
    echo "ABORT: branch $BRANCH has an upstream; pushing is forbidden in this loop." >&2; exit 1
  fi
  assert_remote_refs_unchanged || exit 1
}

echo "=== tdd-loop: task=$TASK_ID backend=$BACKEND dry_run=$DRY_RUN timeout=${CLI_TIMEOUT}s ==="
[[ -f "$INVARIANTS" ]] || { echo "ABORT: $INVARIANTS not found (fail-closed)" >&2; exit 1; }

echo "=== [0] Worktree ($WT, branch $BRANCH from $BASE_REF) ==="
run mkdir -p "$WT_ROOT"
if [[ -d "$WT" ]]; then
  echo "worktree exists, reusing"
  if [[ $DRY_RUN -eq 0 ]]; then
    cur=$(git -C "$WT" rev-parse --abbrev-ref HEAD)
    [[ "$cur" == "$BRANCH" ]] || {
      echo "ABORT: $WT is on '$cur', expected '$BRANCH'" >&2; exit 1
    }
  fi
else
  run git -C "$REPO" worktree add -b "$BRANCH" "$WT" "$BASE_REF"
fi
run mkdir -p "$ART"
if [[ $DRY_RUN -eq 0 ]]; then
  excl=$(git -C "$WT" rev-parse --git-path info/exclude)
  mkdir -p "$(dirname "$excl")"
  grep -qxF '.tdd/' "$excl" 2>/dev/null || echo '.tdd/' >> "$excl"
fi
guard_no_push_setup
snapshot_remote_refs
prepare_cli_home
trap on_exit EXIT

PROMPT1="$(mktemp)"; PROMPT2="$(mktemp)"
cat > "$PROMPT1" <<P1
[PLAN ONLY — do not modify source files]
Task $TASK_ID: $TASK_DESC
Scope: only the worktree $WT.
1. Read $INVARIANTS and list each invariant this task touches and how it stays satisfied.
2. Specify the failing tests to write FIRST (RED), file paths and test names.
3. Minimal single-concern implementation plan (GREEN), then REFACTOR notes.
4. DoD checklist (see below).
Write the result as markdown to $PLAN. Do not commit. Never push, merge or force-push.
P1
cat > "$PROMPT2" <<P2
[IMPLEMENT] Task $TASK_ID in worktree $WT only.
Input plan file: $PLAN (follow it; read $INVARIANTS again before finishing).
Order: RED (write tests, run, confirm they fail) -> GREEN (minimal code, tests pass) -> REFACTOR (keep green).
Run: cargo fmt --all --manifest-path runtime/Cargo.toml -- --check; cargo clippy --manifest-path runtime/Cargo.toml --workspace --all-targets --locked -- -D warnings; cargo test --manifest-path runtime/Cargo.toml --workspace --locked.
Do not commit. Never git push / merge / force-push.
Do not print environment variables or secrets.
P2

[[ $DRY_RUN -eq 0 && -f "$PLAN" ]] && rm -f "$PLAN"

echo "=== [1] Plan + invariant check (output -> $PLAN) ==="
agent "$PROMPT1"
if [[ $DRY_RUN -eq 0 && ! -s "$PLAN" ]]; then echo "ABORT: step 1 produced no plan at $PLAN" >&2; exit 1; fi

echo "=== [2] Implement (plan file passed in: $PLAN) ==="
agent "$PROMPT2"

echo "=== [3] Local verification ==="
run git -C "$WT" status --short
(
  if [[ $DRY_RUN -eq 0 ]]; then cd "$WT"; fi
  run run_isolated cargo fmt --all --manifest-path runtime/Cargo.toml -- --check
  run run_isolated cargo clippy --manifest-path runtime/Cargo.toml --workspace --all-targets --locked -- -D warnings
  run run_isolated cargo test --manifest-path runtime/Cargo.toml --workspace --locked
)
guard_no_push

echo "=== [3b] Local DCO commit (script-owned; CLI must not commit) ==="
if [[ $DRY_RUN -eq 0 ]]; then
  if [[ -n "$(git -C "$WT" status --porcelain)" ]]; then
    git -C "$WT" add -A
    git -C "$WT" reset -q HEAD -- .tdd 2>/dev/null || true
    git -C "$WT" commit -s -m "tdd($TASK_ID): $TASK_DESC"
  else
    echo "nothing to commit"
  fi
else
  echo "(dry-run) would git commit -s"
fi
guard_no_push

echo "=== [3c] Mandatory pre-push gate: pinned scripts/ci-local.sh (must be GREEN) ==="
# Fail closed: run a pinned copy from outside the worktree; the agent-edited
# worktree copy must be byte-identical; caller CI_LOCAL_* never reaches it.
CI_PIN=""
if [[ $DRY_RUN -eq 0 ]]; then
  CI_PIN=$(mktemp "${TMPDIR:-/tmp}/ci-local-pinned.XXXXXX")
  if [[ -n "$CI_LOCAL_PATH" ]]; then
    cp -- "$CI_LOCAL_PATH" "$CI_PIN" || { echo "ABORT: cannot read --ci-local $CI_LOCAL_PATH" >&2; exit 1; }
    pin_sha=$(sha256sum "$CI_PIN" | cut -d' ' -f1)
    [[ "$pin_sha" == "$CI_LOCAL_SHA" ]] || { echo "ABORT: --ci-local sha256 $pin_sha != expected $CI_LOCAL_SHA" >&2; exit 1; }
  elif ! git -C "$WT" show "$BASE_REF:scripts/ci-local.sh" > "$CI_PIN" 2>/dev/null; then
    echo "ABORT: $BASE_REF has no scripts/ci-local.sh (sidged #74 not merged yet)." >&2
    echo "       Pass a reviewed copy: --ci-local <path> --ci-local-sha256 <hex>. No handover without ci-local GREEN." >&2
    exit 1
  fi
  pin_sha=$(sha256sum "$CI_PIN" | cut -d' ' -f1)
  wt_sha=$(sha256sum "$WT/scripts/ci-local.sh" 2>/dev/null | cut -d' ' -f1 || true)
  if [[ "$wt_sha" != "$pin_sha" ]]; then
    echo "ABORT: worktree scripts/ci-local.sh (${wt_sha:-missing}) differs from pinned ($pin_sha)" >&2; exit 1
  fi
  echo "ci-local pinned sha256 $pin_sha"
  ( cd "$WT" && run_isolated bash "$CI_PIN" ) || { echo "ABORT: ci-local.sh RED; fix before handover" >&2; exit 1; }
else
  echo "(dry-run) would run the pinned ci-local.sh (isolated env, nice+ionice) in $WT"
fi
guard_no_push

if [[ $DRY_RUN -eq 0 ]]; then CI_DOD="[x]"; else CI_DOD="[ ]"; fi
cat <<DOD
=== [4] DoD checklist (verify manually before handover) ===
[ ] Tests written first and seen failing (RED)
[ ] All tests green (cargo test --manifest-path runtime/Cargo.toml --workspace --locked)
[ ] fmt + clippy -D warnings clean
$CI_DOD scripts/ci-local.sh GREEN on the handover SHA (step 3c)
[ ] Checked against $INVARIANTS (all 9), deviations listed in $PLAN
[ ] Single concern, commits DCO-signed (-s) by this script
[ ] No secrets in diff or $LOG
[ ] Nothing pushed / merged / force-pushed
=== [5] Handover ===
Hand over to WOUFbot (safe-merge): worktree=$WT branch=$BRANCH head=\$(git -C $WT rev-parse HEAD)
This script never pushes or merges.
DOD
