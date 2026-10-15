---
name: bot-cli-routing
description: >-
  Use before any coding, writing or repo task: which CLI to route to (Claude
  CLI, agy, codex), timeouts and quota checks, repo allowlist, review-gated
  merges, secret rules, optional remote computer, hub logging.
---
# CLI routing and autonomy rules

Make sure user-space tools are on PATH (e.g. `export PATH="$HOME/.local/bin:$PATH"`).
Language and timezone conventions come from your owner's project brief (`hub brief`).

## 1. Model routing
| Work | First choice | Fallback 1 | Fallback 2 |
|---|---|---|---|
| Writing (specs, docs, PR text) | `timeout 600 claude -p "<prompt>" </dev/null` | `timeout 600 agy -p "<prompt>" --model <strong-model> </dev/null` | do it yourself |
| Coding (edits, tests, refactors) | `timeout 1500 codex exec --skip-git-repo-check -C <repo> "<prompt>" </dev/null` | `agy -p ... --model <strong-model>` | do it yourself |
| Quick/cheap checks | `agy -p ... --model <fast-model>` | codex | yourself |
| Browser / web | browser + web fetch/search tools | — | — |

- `codex exec` needs `</dev/null` and `--skip-git-repo-check`, otherwise it may hang.
- Prompts to CLIs state: repo, files, TDD ("write the failing test first"), test command, "do not commit". Then YOU review the diff, run tests and commit (`git commit -s`).
- If a CLI fails (not logged in, quota, timeout, garbage): do it yourself and say so in the report.

## 2. Usage / failure checks
- Wrap every CLI call in `timeout N`; exit 124 = timeout -> retry once smaller, then fall back.
- Grep output for `rate limit|quota|usage limit|429|insufficient|not logged in|unauthorized|login` -> unavailable, fall back, note it.
- Never log in interactively on the owner's behalf. Long jobs run in background with logs under `<workdir>/log-*.txt`.

## 3. Guardrails
- Write/push only to repos in the allowlist (`SAFE_MERGE_ALLOWED_REPOS` / safe-merge config). Everything else is read-only.
- Merge only via `$LEAD_KIT/review/safe-merge.sh` after the reviewer bot approved the current head SHA. List PRs awaiting review in your report.
- No secrets anywhere (output, logs, hub, commits, PR text, templates): no keys, tokens, auth files, IP addresses, passphrases. Redact as `<redacted>`.
- No publishing, messaging, posting, visibility changes, purchases or deletions outside the box without explicit owner approval for that exact action.
- No destructive git (force push, reset --hard on pushed work) without owner confirmation.
- No GitHub write access? Prepare `git format-patch` output and report "blocked: no write path".

## 4. Remote computer (optional)
- Use `$LEAD_KIT/persist/vps.py run|push|pull|ls` (paramiko; host/user/key/known_hosts only from env or `~/.config/lead-kit/persist.env`).
- Never print the key or host address. Work only in your own dirs; no `sudo` changes without approval.

## 5. Hub coordination
- `HUB_BOT="<Your Bot>" hub status` before starting; `hub search <topic>` to avoid duplicate work.
- Claim with `hub work claim`, record outcomes with `hub note add ... --kind fact|decision|approach|lesson|question|link`, hand over with `hub handoff add`.
- One note per meaningful result; reference PR numbers and SHAs, never secrets.

## 6. Persistence
- After meaningful changes: `$LEAD_KIT/persist/backup.sh`. Fresh box: `$LEAD_KIT/persist/restore.sh`.

## 7. Repo template
Put `AGENTS.md` (and `CLAUDE.md` containing `@AGENTS.md`) at the root of each repo you work on.
