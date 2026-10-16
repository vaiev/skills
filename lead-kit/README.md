# Lead kit

Tools and rules for the bots working on `vaiev/sidged`. Details per tool live in
`review/README.md` (`safe-merge.sh`, `tdd-loop.sh`).

## Pre-push flow (mandatory)

1. **Worktree.** One worktree per task or bot, branched from current `origin/main`.
   Never work on `main` directly (`git worktree add`).
2. **ci-local GREEN.** Run `scripts/ci-local.sh` in the worktree. It mirrors CI (`rust-ci.yml`, `validate.yml`):
   `cargo fmt --check`, `cargo test --workspace`, `cargo clippy --all-targets -D warnings`,
   schema validation + unittest, static musl build, gitleaks on `origin/main..HEAD`,
   DCO check, and actionlint if installed. Any failure exits non-zero. `tdd-loop.sh`
   enforces this gate (step 3c) with a pinned copy (from `origin/main`, or
   `--ci-local <path> --ci-local-sha256 <hex>`) in an isolated env, and refuses
   handover when it is RED or the worktree copy was changed. Until sidged #74 is
   merged, `origin/main` has no ci-local.sh and step 3c refuses unless the explicit
   pin is passed.
3. **DCO.** Every commit carries `Signed-off-by:` (`git commit -s`).
4. **Hand the SHA to WOUFbot.** Report branch, base SHA and head SHA. Bots never
   push, merge or force-push; WOUFbot pushes.
5. **Review Bot APPROVE of the exact head SHA.** Any new commit needs a new review.
6. **Merge only via `safe-merge.sh`** (approval bound to the head, CI checked,
   `--match-head-commit`).

## Shared workspace

- Bots work in their own worktrees of one shared clone, under a dedicated group.
  The CI runner is a separate, unprivileged account with no access to it; CI
  always checks out fresh from GitHub.
- No GitHub token on shared hosts. WOUFbot pushes.
- Keep load low on hosts shared with the runner (`nice`/`ionice`, low `-j`).
  No training on shared hosts.
- codex/agy logins live per bot in that bot's own home, never in the shared workspace.
- Host layout (paths, users, modes) is kept in the private ops notes, not here.
