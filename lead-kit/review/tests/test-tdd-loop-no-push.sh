#!/usr/bin/env bash
# M3: no-push — credential-stripped CLI, ls-remote snapshot, hook as defense in depth.
set -euo pipefail
D=$(cd "$(dirname "$0")" && pwd)
LOOP="$D/../tdd-loop.sh"
pass=0; fail=0
ok() { echo "PASS $1"; pass=$((pass+1)); }
bad() { echo "FAIL $1"; shift; printf '%s\n' "$@" | tail -30; fail=$((fail+1)); }

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

# Fake CLI that records its env (proves credential strip) and writes a plan.
BIN="$ROOT/bin"
mkdir -p "$BIN"
cat > "$BIN/codex" << 'FAKE'
#!/usr/bin/env bash
# codex exec --sandbox workspace-write --cd <wt> -
# Dump selected env keys (values only as present/absent) to .tdd/cli-env.txt
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
  echo "GH_TOKEN=${GH_TOKEN+SET}${GH_TOKEN-UNSET}"
  echo "GITHUB_TOKEN=${GITHUB_TOKEN+SET}${GITHUB_TOKEN-UNSET}"
  echo "VAIEV_GH_TOKEN=${VAIEV_GH_TOKEN+SET}${VAIEV_GH_TOKEN-UNSET}"
  echo "SSH_AUTH_SOCK=${SSH_AUTH_SOCK+SET}${SSH_AUTH_SOCK-UNSET}"
  echo "GIT_ASKPASS=${GIT_ASKPASS-}"
  echo "GIT_TERMINAL_PROMPT=${GIT_TERMINAL_PROMPT-}"
  echo "GIT_CONFIG_COUNT=${GIT_CONFIG_COUNT-}"
  echo "GIT_CONFIG_KEY_0=${GIT_CONFIG_KEY_0-}"
  echo "GIT_CONFIG_VALUE_0=${GIT_CONFIG_VALUE_0-EMPTY}"
} > "$wt/.tdd/cli-env.txt"
# If stdin is a plan-only prompt, write plan.md
cat > "$wt/.tdd/plan.md" <<'P'
# plan
ok
P
exit 0
FAKE
chmod 755 "$BIN/codex"
# Also stub cargo so step 3 can proceed if we get that far
cat > "$BIN/cargo" << 'C'
#!/usr/bin/env bash
exit 0
C
chmod 755 "$BIN/cargo"

export PATH="$BIN:$PATH"
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

# Shared remotes untouched
pushurl=$(git -C "$ROOT" remote get-url --push origin)
if [[ "$pushurl" == "$BARE" ]]; then ok shared-pushurl-untouched; else bad shared-pushurl-untouched "got=$pushurl"; fi

# Hook still installed (defense in depth)
hp=$(git -C "$WT" config --get --worktree core.hooksPath || true)
if [[ -n "$hp" && -x "$hp/pre-push" ]]; then ok worktree-hooksPath; else bad worktree-hooksPath "hp=$hp"; fi

# CLI env stripped
if [[ -f "$WT/.tdd/cli-env.txt" ]]; then
  if grep -q 'GH_TOKEN=UNSET' "$WT/.tdd/cli-env.txt" \
    && grep -q 'GITHUB_TOKEN=UNSET' "$WT/.tdd/cli-env.txt" \
    && grep -q 'VAIEV_GH_TOKEN=UNSET' "$WT/.tdd/cli-env.txt" \
    && grep -q 'SSH_AUTH_SOCK=UNSET' "$WT/.tdd/cli-env.txt" \
    && grep -q 'GIT_ASKPASS=/bin/false' "$WT/.tdd/cli-env.txt" \
    && grep -q 'GIT_TERMINAL_PROMPT=0' "$WT/.tdd/cli-env.txt" \
    && grep -q 'GIT_CONFIG_KEY_0=credential.helper' "$WT/.tdd/cli-env.txt"; then
    ok cli-env-stripped
  else
    bad cli-env-stripped "$(cat "$WT/.tdd/cli-env.txt")"
  fi
else
  bad cli-env-stripped "missing cli-env.txt" "$(tail -40 "$ROOT/loop.log")"
fi

# Snapshot exists
if [[ -f "$WT/.tdd/remote-refs.snap" ]]; then ok remote-refs-snap; else bad remote-refs-snap; fi

# Changing remote refs must be detected (fail-closed)
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
if cmp -s "$REFS_SNAP" "$now"; then
  det_rc=0
  det_out=SAME
else
  det_rc=1
  det_out=CHANGED
fi
rm -f "$now"
set -e
if [[ $det_rc -ne 0 && "$det_out" == CHANGED ]]; then ok ls-remote-detects-push; else bad ls-remote-detects-push "rc=$det_rc out=$det_out"; fi

# Main repo still pushes
set +e
git -C "$ROOT" commit --allow-empty -qm 'main ok'
out=$(git -C "$ROOT" push origin HEAD:refs/heads/main-ok 2>&1)
rc=$?
set -e
if [[ $rc -eq 0 ]]; then ok main-repo-push-unaffected; else bad main-repo-push-unaffected "rc=$rc" "$out"; fi

# Hook still blocks git push <url> from worktree (defense in depth)
set +e
git -C "$WT" commit --allow-empty -qm 'wt push attempt' 2>/dev/null
out=$(git -C "$WT" push "$BARE" HEAD:refs/heads/should-fail 2>&1)
rc=$?
set -e
if [[ $rc -ne 0 ]]; then ok worktree-push-url-blocked; else bad worktree-push-url-blocked "rc=$rc" "$out"; fi

echo "RESULT pass=$pass fail=$fail loop_rc=$loop_rc"
[[ "$fail" -eq 0 ]]
