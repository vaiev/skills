#!/usr/bin/env bash
# M3: no-push — isolated CLI HOME, ls-remote snapshot (+ EXIT trap), hook defense.
set -euo pipefail
D=$(cd "$(dirname "$0")" && pwd)
LOOP="$D/../tdd-loop.sh"
pass=0; fail=0
ok() { echo "PASS $1"; pass=$((pass+1)); }
bad() { echo "FAIL $1"; shift; printf '%s\n' "$@" | tail -40; fail=$((fail+1)); }

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

# Fake "real" HOME with git credentials that MUST NOT reach the CLI,
# plus whitelisted CLI auth dirs that MUST be copied.
FAKE_HOME="$ROOT/fake-home"
mkdir -p "$FAKE_HOME/.codex" "$FAKE_HOME/.grok" "$FAKE_HOME/.agy" \
  "$FAKE_HOME/.config/gh" "$FAKE_HOME/.ssh" "$FAKE_HOME/.config/agy"
echo 'https://x-access-token:LEAKED_GIT_CRED@github.com' > "$FAKE_HOME/.git-credentials"
echo 'LEAKED_GH_CONFIG' > "$FAKE_HOME/.config/gh/hosts.yml"
echo 'LEAKED_SSH_KEY' > "$FAKE_HOME/.ssh/id_ed25519"
echo 'CODEX_AUTH_OK' > "$FAKE_HOME/.codex/auth.json"
echo 'GROK_AUTH_OK' > "$FAKE_HOME/.grok/auth.json"
echo 'AGY_AUTH_OK' > "$FAKE_HOME/.agy/auth.json"
echo 'AGY_XDG_OK' > "$FAKE_HOME/.config/agy/auth.json"
chmod 600 "$FAKE_HOME/.git-credentials" "$FAKE_HOME/.ssh/id_ed25519"

# Fake CLI that records HOME / credential visibility
BIN="$ROOT/bin"
mkdir -p "$BIN"
cat > "$BIN/codex" << 'FAKE'
#!/usr/bin/env bash
wt=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --cd) wt="$2"; shift 2 ;;
    -) break ;;
    *) shift ;;
  esac
done
mkdir -p "$wt/.tdd"
{
  echo "HOME=$HOME"
  echo "XDG_CONFIG_HOME=${XDG_CONFIG_HOME-}"
  echo "GH_CONFIG_DIR=${GH_CONFIG_DIR-}"
  echo "GIT_CONFIG_GLOBAL=${GIT_CONFIG_GLOBAL-}"
  echo "GIT_CONFIG_NOSYSTEM=${GIT_CONFIG_NOSYSTEM-}"
  echo "GIT_SSH_COMMAND=${GIT_SSH_COMMAND-}"
  echo "GH_TOKEN=${GH_TOKEN+SET}${GH_TOKEN-UNSET}"
  echo "GITHUB_TOKEN=${GITHUB_TOKEN+SET}${GITHUB_TOKEN-UNSET}"
  echo "VAIEV_GH_TOKEN=${VAIEV_GH_TOKEN+SET}${VAIEV_GH_TOKEN-UNSET}"
  echo "SSH_AUTH_SOCK=${SSH_AUTH_SOCK+SET}${SSH_AUTH_SOCK-UNSET}"
  echo "GIT_ASKPASS=${GIT_ASKPASS-}"
  echo "GIT_TERMINAL_PROMPT=${GIT_TERMINAL_PROMPT-}"
  echo "GIT_CONFIG_KEY_0=${GIT_CONFIG_KEY_0-}"
  if [ -f "$HOME/.git-credentials" ]; then echo HAS_GIT_CREDENTIALS=YES; else echo HAS_GIT_CREDENTIALS=NO; fi
  if [ -f "${GH_CONFIG_DIR:-/no}/hosts.yml" ]; then echo HAS_GH_HOSTS=YES; else echo HAS_GH_HOSTS=NO; fi
  if [ -f "$HOME/.ssh/id_ed25519" ]; then echo HAS_SSH_KEY=YES; else echo HAS_SSH_KEY=NO; fi
  if [ -f "$HOME/.codex/auth.json" ]; then echo HAS_CODEX=YES; else echo HAS_CODEX=NO; fi
  if [ -f "$HOME/.grok/auth.json" ]; then echo HAS_GROK=YES; else echo HAS_GROK=NO; fi
  if [ -f "$HOME/.agy/auth.json" ]; then echo HAS_AGY=YES; else echo HAS_AGY=NO; fi
  if [ -f "${XDG_CONFIG_HOME:-/no}/agy/auth.json" ]; then echo HAS_AGY_XDG=YES; else echo HAS_AGY_XDG=NO; fi
  echo "CODEX_BODY=$(cat "$HOME/.codex/auth.json" 2>/dev/null || true)"
} > "$wt/.tdd/cli-env.txt"
cat > "$wt/.tdd/plan.md" <<'P'
# plan
ok
P
exit 0
FAKE
chmod 755 "$BIN/codex"
cat > "$BIN/cargo" << 'C'
#!/usr/bin/env bash
exit 0
C
chmod 755 "$BIN/cargo"

export PATH="$BIN:$PATH"
export HOME="$FAKE_HOME"
export GH_TOKEN=fake-gh-token-should-be-stripped
export GITHUB_TOKEN=fake-github-token-should-be-stripped
export VAIEV_GH_TOKEN=fake-vaiev-token-should-be-stripped
export SSH_AUTH_SOCK=/tmp/fake-ssh-agent.sock

set +e
INVARIANTS="$INV" SIDGED_REPO="$ROOT" WT_ROOT="$WTROOT" BASE_REF=HEAD CLI_TIMEOUT=30 \
  "$LOOP" --backend codex m3np 'block push' >"$ROOT/loop.log" 2>&1
loop_rc=$?
set -e

WT="$WTROOT/m3np"
if [[ ! -d "$WT" ]]; then
  bad "no-worktree" "$(tail -40 "$ROOT/loop.log")"
  echo "RESULT pass=$pass fail=$fail"
  exit 1
fi

pushurl=$(git -C "$ROOT" remote get-url --push origin)
if [[ "$pushurl" == "$BARE" ]]; then ok shared-pushurl-untouched; else bad shared-pushurl-untouched "got=$pushurl"; fi

hp=$(git -C "$WT" config --get --worktree core.hooksPath || true)
if [[ -n "$hp" && -x "$hp/pre-push" ]]; then ok worktree-hooksPath; else bad worktree-hooksPath "hp=$hp"; fi

ENVF="$WT/.tdd/cli-env.txt"
if [[ -f "$ENVF" ]]; then
  if grep -q 'GH_TOKEN=UNSET' "$ENVF" \
    && grep -q 'GITHUB_TOKEN=UNSET' "$ENVF" \
    && grep -q 'VAIEV_GH_TOKEN=UNSET' "$ENVF" \
    && grep -q 'SSH_AUTH_SOCK=UNSET' "$ENVF" \
    && grep -q 'GIT_ASKPASS=/bin/false' "$ENVF" \
    && grep -q 'GIT_SSH_COMMAND=/bin/false' "$ENVF" \
    && grep -q 'GIT_CONFIG_GLOBAL=/dev/null' "$ENVF" \
    && grep -q 'GIT_CONFIG_NOSYSTEM=1' "$ENVF" \
    && grep -q 'GIT_CONFIG_KEY_0=credential.helper' "$ENVF"; then
    ok cli-env-stripped
  else
    bad cli-env-stripped "$(cat "$ENVF")"
  fi
  # Fresh HOME (not the fake real home)
  cli_home=$(grep '^HOME=' "$ENVF" | head -1 | cut -d= -f2-)
  if [[ -n "$cli_home" && "$cli_home" != "$FAKE_HOME" && "$cli_home" == /tmp/* ]]; then
    ok cli-fresh-home
  else
    bad cli-fresh-home "HOME=$cli_home FAKE_HOME=$FAKE_HOME"
  fi
  # Real-HOME credentials must NOT work / be visible
  if grep -q 'HAS_GIT_CREDENTIALS=NO' "$ENVF" \
    && grep -q 'HAS_GH_HOSTS=NO' "$ENVF" \
    && grep -q 'HAS_SSH_KEY=NO' "$ENVF"; then
    ok real-home-creds-blocked
  else
    bad real-home-creds-blocked "$(grep '^HAS_' "$ENVF")"
  fi
  # Whitelisted CLI auth dirs copied
  if grep -q 'HAS_CODEX=YES' "$ENVF" \
    && grep -q 'HAS_GROK=YES' "$ENVF" \
    && grep -q 'HAS_AGY=YES' "$ENVF" \
    && grep -q 'HAS_AGY_XDG=YES' "$ENVF" \
    && grep -q 'CODEX_BODY=CODEX_AUTH_OK' "$ENVF"; then
    ok cli-auth-dirs-copied
  else
    bad cli-auth-dirs-copied "$(grep -E 'HAS_|CODEX_BODY' "$ENVF")"
  fi
else
  bad cli-env-file "missing" "$(tail -40 "$ROOT/loop.log")"
fi

if [[ -f "$WT/.tdd/remote-refs.snap" ]]; then ok remote-refs-snap; else bad remote-refs-snap; fi

# Changing remote refs must be detected
git -C "$ROOT" commit --allow-empty -qm 'remote moves'
git -C "$ROOT" push origin HEAD:refs/heads/sneaky >/dev/null 2>&1
set +e
export WT ART="$WT/.tdd" REFS_SNAP="$WT/.tdd/remote-refs.snap"
now=$(mktemp)
{
  out=""
  while IFS= read -r remote; do
    [[ -n "$remote" ]] || continue
    refs=$(git -C "$WT" ls-remote "$remote")
    out+=$(printf 'REMOTE %s\n%s\n' "$remote" "$(printf '%s\n' "$refs" | LC_ALL=C sort)")
    out+=$'\n'
  done < <(git -C "$WT" remote)
  printf '%s' "$out"
} > "$now"
if cmp -s "$REFS_SNAP" "$now"; then det_rc=0; det_out=SAME; else det_rc=1; det_out=CHANGED; fi
rm -f "$now"
set -e
if [[ $det_rc -ne 0 && "$det_out" == CHANGED ]]; then ok ls-remote-detects-push; else bad ls-remote-detects-push "rc=$det_rc out=$det_out"; fi

# EXIT trap: early exit (timeout) after a sneaky remote change must fail closed
# Restore snap to current, then change remote during a "timeout" agent run.
# Rebuild snap to current first for a clean trap test on a new task id.
WT2ROOT="$ROOT/wt"
# Reset remote to known state for trap test: take new snap by running loop that
# times out after we push mid-flight — use a codex that pushes then exits 124.
cat > "$BIN/codex" << FAKE2
#!/usr/bin/env bash
wt=""
while [[ \$# -gt 0 ]]; do
  case "\$1" in
    --cd) wt="\$2"; shift 2 ;;
    -) break ;;
    *) shift ;;
  esac
done
mkdir -p "\$wt/.tdd"
echo plan > "\$wt/.tdd/plan.md"
# Mutate remote using the outer test's credentials (via absolute git -C path)
git -C "$ROOT" commit --allow-empty -qm 'trap-sneak' >/dev/null 2>&1
git -C "$ROOT" push origin HEAD:refs/heads/trap-sneak >/dev/null 2>&1
# Simulate timeout
exit 124
FAKE2
chmod 755 "$BIN/codex"

set +e
INVARIANTS="$INV" SIDGED_REPO="$ROOT" WT_ROOT="$WT2ROOT" BASE_REF=HEAD CLI_TIMEOUT=30 \
  "$LOOP" --backend codex m3trap 'trap test' >"$ROOT/trap.log" 2>&1
trap_rc=$?
set -e
if [[ $trap_rc -ne 0 ]] && grep -q 'remote refs changed\|push detected\|fail-closed\|timed out' "$ROOT/trap.log"; then
  # Must specifically fail closed on refs OR at least exit non-zero after timeout+trap
  if grep -q 'remote refs changed\|push detected' "$ROOT/trap.log"; then
    ok exit-trap-ls-remote
  else
    # timeout path: trap should still have caught the push
    bad exit-trap-ls-remote "timeout without refs abort" "$(tail -30 "$ROOT/trap.log")"
  fi
else
  bad exit-trap-ls-remote "rc=$trap_rc" "$(tail -40 "$ROOT/trap.log")"
fi

set +e
git -C "$ROOT" commit --allow-empty -qm 'main ok'
out=$(git -C "$ROOT" push origin HEAD:refs/heads/main-ok 2>&1)
rc=$?
set -e
if [[ $rc -eq 0 ]]; then ok main-repo-push-unaffected; else bad main-repo-push-unaffected "rc=$rc" "$out"; fi

set +e
git -C "$WT" commit --allow-empty -qm 'wt push attempt' 2>/dev/null
out=$(git -C "$WT" push "$BARE" HEAD:refs/heads/should-fail 2>&1)
rc=$?
set -e
if [[ $rc -ne 0 ]]; then ok worktree-push-url-blocked; else bad worktree-push-url-blocked "rc=$rc" "$out"; fi

echo "RESULT pass=$pass fail=$fail loop_rc=$loop_rc trap_rc=${trap_rc:-na}"
[[ "$fail" -eq 0 ]]
