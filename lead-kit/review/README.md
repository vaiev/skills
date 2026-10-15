# Safe merge

Requires Bash, Python 3, GitHub CLI (`gh`), and optionally `hub` for review notes.
Authenticate the CLI with access to the repositories being reviewed.

Copy `safe-merge.conf.example` to `~/.config/lead-kit/safe-merge.conf`, or set
`SAFE_MERGE_ALLOWED_REPOS` to space/comma separated `owner/repo` names.
An environment value takes precedence, including an empty value (which refuses
all merges). `SAFE_MERGE_CONFIG` overrides the config path. The config file is
trusted shell code defining `ALLOWED_REPOS`.

Run:

```sh
SAFE_MERGE_ALLOWED_REPOS=example/project ./safe-merge.sh example/project 123 --dry-run
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
results, but does not bypass reported failures. Missing hub notes are tolerated.

Run mocked tests with `bash lead-kit/review/tests/test-safe-merge.sh` from the
repository root.
