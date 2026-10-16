# Safe merge

Requires Bash, Python 3, GitHub CLI (`gh`), and optionally `hub` for review notes.
Authenticate the CLI with access to the repositories being reviewed.

Copy `safe-merge.conf.example` to `~/.config/lead-kit/safe-merge.conf`, or set
`SAFE_MERGE_ALLOWED_REPOS` to space/comma separated `owner/repo` names.
An environment value takes precedence, including an empty value (which refuses
all merges). `SAFE_MERGE_CONFIG` overrides the config path. The config file is
trusted shell code defining `ALLOWED_REPOS` and `REVIEWER_LOGINS`.

Set `SAFE_MERGE_REVIEWER_LOGINS` to comma/space separated GitHub author logins,
or define `REVIEWER_LOGINS` in the config file. The environment takes precedence,
including an empty value. An empty reviewer allowlist refuses all merges.
Only reviews and PR comments whose `user.login` is allowlisted count as approval
or blocking evidence. If all bots share one GitHub account, author checks only stop outsiders, not bot impersonation.

Run:

```sh
SAFE_MERGE_ALLOWED_REPOS=example/project SAFE_MERGE_REVIEWER_LOGINS=reviewer-bot ./safe-merge.sh example/project 123 --dry-run
```

Bare repository names require `SAFE_MERGE_DEFAULT_OWNER`. `GH_BIN` and `HUB_BIN`
select executables (defaults: `gh` and `hub` on PATH).
`SAFE_MERGE_REVIEWER` selects the bot display name (default: `Review Bot`),
including the author of hub notes. GitHub verdict messages retain support for
the existing `Verdict: APPROVE` format; the display name is not an identity
authentication mechanism.

The guard requires approval bound to the current head, refuses outstanding
change requests and blocking bot verdicts, and checks CI. It squash-merges with
`--match-head-commit`. `--allow-unverified-ci` permits missing/unreadable Actions
results, but does not bypass reported failures. Hub notes are advisory: notes
from the selected reviewer bot can add BLOCK evidence, but never approval.
Missing hub notes are tolerated.

Run mocked tests with `bash lead-kit/review/tests/test-safe-merge.sh` from the
repository root.

## TDD loop

`tdd-loop.sh` is a worktree-per-task TDD helper for Sidged implementation work.
Codex is the default backend; `grok` and `agy` are optional. It never pushes or
merges: after RED → GREEN → REFACTOR and a DCO-signed local commit it hands the
branch to WOUFbot / `safe-merge.sh`. The agent prompt requires reading
`INVARIANTS.md`.

```sh
./tdd-loop.sh [--dry-run] [--backend codex|grok|agy] <TASK_ID> "<TASK_DESCRIPTION>"
```

Primary no-push controls: the CLI runs in a fresh empty `HOME` with empty `XDG_CONFIG_HOME`/`GH_CONFIG_DIR`, `GIT_CONFIG_GLOBAL=/dev/null`, `GIT_CONFIG_NOSYSTEM=1`, SSH blocked (`GIT_SSH_COMMAND=/bin/false`, no `SSH_AUTH_SOCK`), tokens unset, and empty `credential.helper`. Only whitelisted CLI auth dirs (`.codex` / `.grok` / `.agy`, plus `.config/agy` into the temp XDG) are copied in — never `.git-credentials`, `.config/gh`, or `.ssh`. After each step and on `EXIT` (timeout/quota/auth), `git ls-remote` is compared to a pre-step snapshot (fail-closed). A worktree-local `core.hooksPath` pre-push hook remains as defense in depth only.
Run `bash lead-kit/review/tests/test-tdd-loop-no-push.sh` from the repository root (also in CI).

