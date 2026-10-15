---
name: bot-teamwork
description: >-
  Use at the start and end of every task on a shared box to coordinate with
  other bots: hub ask/brief, claim work, hand off, respect the review gate,
  log results and back up.
---
# Bot teamwork on a shared box

`hub` = the hub CLI from `vaiev/mcp` `lead-kit/` (installed by `lead-kit/install.sh`). Set `HUB_BOT="<Your Bot>"`.

## Start of a task
1. `hub brief "<Your Bot>"` – your open work, handoffs, PRs, decisions.
2. `hub ask "<question>"` – results with citations; read the cited source before relying on it. `hub search "<repo>#<n>"` for prior findings on a PR.
3. Claim: `hub work claim "<task>" --project <p> [--branch <branch|PR URL>]`. If the claim fails, someone owns it – coordinate via handoff.

## During
- Route coding/writing through the CLIs per skill `bot-cli-routing`.
- Blocked? `hub work update <id> --status blocked --notes "<why>"`.
- Need another bot? `hub handoff add "<Other Bot>" "<concrete ask, links>" --project <p>`.

## Review gate
- Open/update a PR, then hand off to the reviewer bot. Merge only when it approved the current head SHA. On BLOCK: fix test-first on the same branch, push, add a hub note with the new SHA.
- No force-push except `--force-with-lease` on your own bot-owned PR branches.

## End of a task
1. `hub note add "<result>" --project <p> --kind fact|decision|lesson|link --body "<PR URL @sha, tests, open points>"` (no secrets/IPs).
2. `hub work release <id> --notes "<outcome>"`; `hub handoff done <id>`; new handoffs for leftovers.
3. Docs changed? `hub ingest <path> --project <p>` (or `hub ingest --refresh`).
4. `$LEAD_KIT/persist/backup.sh`.
5. Report: done, verified, blocked.

## Merge rule
- ALL merges go through `$LEAD_KIT/review/safe-merge.sh <repo> <pr> [--dry-run] [--allow-unverified-ci]`. Never call `gh pr merge` directly.
- Guard: no latest CHANGES_REQUESTED; latest reviewer verdict not BLOCK; an APPROVED review or reviewer `Verdict: APPROVE` bound to the head SHA; all Actions runs for the head SHA green; merges with `--squash --match-head-commit <sha>`.
- Always commit with `git commit -s` (DCO sign-off).
