#!/usr/bin/env bash
# tdd-loop.sh — worktree-scoped TDD template (replaces agy-superpowers-loop.sh)
# Usage: tdd-loop.sh [--dry-run] [--backend codex|grok|agy] <TASK_ID> "<TASK_DESCRIPTION>"
#
# Rules (enforced / instructed):
#   * One git worktree per task: /workspace/vaiev/wt/<TASK_ID>
#   * Tests first: RED -> GREEN -> REFACTOR
#   * Agent must check its work against /workspace/vaiev/INVARIANTS.md
#   * Step 1 plan is written to a file and passed as a file into step 2
#   * NEVER push, merge or force-push. Handover to WOUFbot / safe-merge only.
#   * No skip-permissions flags. No secrets in logs (env is never echoed).
set -euo pipefail

REPO="${SIDGED_REPO:-/workspace/vaiev/sidged}"
WT_ROOT="/workspace/vaiev/wt"
INVARIANTS="/workspace/vaiev/INVARIANTS.md"
BASE_REF="${BASE_REF:-origin/main}"
DRY_RUN=0
BACKEND="codex"

usage() { echo "Usage: $0 [--dry-run] [--backend codex|grok|agy] <TASK_ID> <TASK_DESCRIPTION>" >&2; exit 2; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    --backend) BACKEND="${2:?}"; shift 2 ;;
    -h|--help) usage ;;
    --) shift; break ;;
    -*) usage ;;
    *) break ;;
  esac
done

TASK_ID="${1:-}"; TASK_DESC="${2:-}"
[[ -n "$TASK_ID" && -n "$TASK_DESC" ]] || usage
[[ "$TASK_ID" =~ ^[A-Za-z0-9._-]+$ ]] || { echo "TASK_ID must match [A-Za-z0-9._-]+" >&2; exit 2; }
case "$BACKEND" in codex|grok|agy) ;; *) usage ;; esac

WT="$WT_ROOT/$TASK_ID"
BRANCH="tdd/$TASK_ID"
ART="$WT/.tdd"
PLAN="$ART/plan.md"
LOG="$ART/run.log"

# run: print the command; execute only when not dry-run. Never prints env.
run() {
  printf '+'; printf ' %q' "$@"; printf '\n'
  if [[ $DRY_RUN -eq 0 ]]; then "$@"; fi
}

# Redact anything resembling a token before it reaches the log.
redact() { sed -E 's/(gh[pousr]_[A-Za-z0-9]{20,}|sk-[A-Za-z0-9_-]{20,}|xai-[A-Za-z0-9]{20,}|(api[_-]?key|token|secret|password)["=: ]+[^ "]+)/[REDACTED]/Ig'; }

agent() { # agent <prompt-file> : non-interactive CLI call, no permission bypass
  local pf="$1"
  case "$BACKEND" in
    codex) run codex exec --sandbox workspace-write --cd "$WT" - < "$pf" ;;
    grok)  run grok --cwd "$WT" --prompt-file "$pf" ;;
    agy)   run env -C "$WT" agy --sandbox --print "$(cat "$pf")" ;;
  esac
}

guard_no_push() { # fail if anything left the worktree
  if [[ $DRY_RUN -eq 0 ]] && git -C "$WT" rev-parse --abbrev-ref "@{u}" >/dev/null 2>&1; then
    echo "ABORT: branch $BRANCH has an upstream; pushing is forbidden in this loop." >&2; exit 1
  fi
}

echo "=== tdd-loop: task=$TASK_ID backend=$BACKEND dry_run=$DRY_RUN ==="
[[ -f "$INVARIANTS" ]] || echo "WARN: $INVARIANTS not found" >&2

echo "=== [0] Worktree ($WT, branch $BRANCH from $BASE_REF) ==="
run mkdir -p "$WT_ROOT"
if [[ -d "$WT" ]]; then echo "worktree exists, reusing"; else
  run git -C "$REPO" worktree add -b "$BRANCH" "$WT" "$BASE_REF"
fi
run mkdir -p "$ART"

PROMPT1="$(mktemp)"; PROMPT2="$(mktemp)"; trap 'rm -f "$PROMPT1" "$PROMPT2"' EXIT
cat > "$PROMPT1" <<P1
[PLAN ONLY — do not modify source files]
Task $TASK_ID: $TASK_DESC
Scope: only the worktree $WT.
1. Read $INVARIANTS and list each invariant this task touches and how it stays satisfied.
2. Specify the failing tests to write FIRST (RED), file paths and test names.
3. Minimal single-concern implementation plan (GREEN), then REFACTOR notes.
4. DoD checklist (see below).
Write the result as markdown to $PLAN. Never push, merge or force-push.
P1
cat > "$PROMPT2" <<P2
[IMPLEMENT] Task $TASK_ID in worktree $WT only.
Input plan file: $PLAN (follow it; read $INVARIANTS again before finishing).
Order: RED (write tests, run, confirm they fail) -> GREEN (minimal code, tests pass) -> REFACTOR (keep green).
Run: cargo fmt --check; cargo clippy --workspace -- -D warnings; cargo test --workspace.
Commit locally with DCO sign-off (git commit -s). NEVER git push / merge / force-push.
Do not print environment variables or secrets.
P2

echo "=== [1] Plan + invariant check (output -> $PLAN) ==="
agent "$PROMPT1" 2>&1 | redact | { if [[ $DRY_RUN -eq 0 ]]; then tee -a "$LOG"; else cat; fi; }
if [[ $DRY_RUN -eq 0 && ! -s "$PLAN" ]]; then echo "ABORT: step 1 produced no plan at $PLAN" >&2; exit 1; fi

echo "=== [2] Implement (plan file passed in: $PLAN) ==="
agent "$PROMPT2" 2>&1 | redact | { if [[ $DRY_RUN -eq 0 ]]; then tee -a "$LOG"; else cat; fi; }

echo "=== [3] Local verification ==="
run git -C "$WT" status --short
( if [[ $DRY_RUN -eq 0 ]]; then cd "$WT"; fi
  run cargo fmt --all -- --check
  run cargo clippy --workspace -- -D warnings
  run cargo test --workspace )
guard_no_push

cat <<DOD
=== [4] DoD checklist (verify manually before handover) ===
[ ] Tests written first and seen failing (RED)
[ ] All tests green (cargo test --workspace)
[ ] fmt + clippy -D warnings clean
[ ] Checked against $INVARIANTS (all 9), deviations listed in $PLAN
[ ] Single concern, commits DCO-signed (-s)
[ ] No secrets in diff or $LOG
[ ] Nothing pushed / merged / force-pushed
=== [5] Handover ===
Hand over to WOUFbot (safe-merge): worktree=$WT branch=$BRANCH head=\$(git -C $WT rev-parse HEAD)
This script never pushes or merges.
DOD
