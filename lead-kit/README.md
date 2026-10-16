# Lead kit

Tools and rules for the bots working on `vaiev/sidged`. Details per tool live in
`review/README.md` (`safe-merge.sh`, `tdd-loop.sh`).

## Pre-push flow (mandatory)

1. **Worktree.** One worktree per task or bot, branched from current `origin/main`.
   Never work on `main` directly. On the VPS each bot has its own worktree under
   `/srv/vaiev` (see below); on a box use `git worktree add`.
2. **ci-local GREEN.** Run `scripts/ci-local.sh` in the worktree (VPS:
   `/srv/vaiev/bin/ci-local`). It mirrors CI (`rust-ci.yml`, `validate.yml`):
   `cargo fmt --check`, `cargo test --workspace`, `cargo clippy --all-targets -D warnings`,
   schema validation + unittest, static musl build, gitleaks on `origin/main..HEAD`,
   DCO check, and actionlint if installed. Any failure exits non-zero. `tdd-loop.sh`
   enforces this gate (step 3c) and refuses handover when it is RED.
3. **DCO.** Every commit carries `Signed-off-by:` (`git commit -s`).
4. **Hand the SHA to WOUFbot.** Report branch, base SHA and head SHA. Bots never
   push, merge or force-push; WOUFbot pushes.
5. **Review Bot APPROVE of the exact head SHA.** Any new commit needs a new review.
6. **Merge only via `safe-merge.sh`** (approval bound to the head, CI checked,
   `--match-head-commit`).

## Shared VPS workspace

- Root: `/srv/vaiev` (`root:vaiev-bots`, `2770`, setgid). Bare repo `sidged.git`,
  worktrees `wt-sidged`, `wt-exec`, `wt-review`, `wt-status`, `wt-lead`.
- Toolchain: `/opt/vaiev-tools` (rustup 1.89.0 + clippy/rustfmt + musl targets,
  pinned gitleaks), group `vaiev-bots`, not world-readable.
- Strictly separate from the CI runner (`ghrunner`, own home, not in `vaiev-bots`),
  from `/run/sidged` and from the approver. CI checks out fresh from GitHub and
  never uses `/srv/vaiev`.
- No GitHub token on the VPS. Code arrives as a git bundle from a box clone.
- Keep load low: the runner shares the CPU. `ci-local` runs under `nice`/`ionice`
  with `CI_LOCAL_JOBS=2` by default. No training on the VPS or the box.
- codex/agy logins and credentials live per bot in that bot's own home, never in
  `/srv/vaiev`.
