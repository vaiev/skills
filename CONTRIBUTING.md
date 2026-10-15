# Contributing

## Add a skill

Create `<family>/<skill>/SKILL.md` with YAML frontmatter:

```yaml
---
name: skill-name
description: >-
  When to use this skill.
---
```

`name` is the skill id. `description` says when a bot should pick the skill. Keep the playbook short enough that a bot can follow it on one read.

Link the skill from the root `README.md` and from the family README with the same path. The canonical form other repositories should use is `vaiev/skills/<family>/<skill>/SKILL.md`.

## Checks

```bash
python3 -m unittest discover -s tests -v
```

GitHub Actions runs that command on every push and pull request. The tests cover the atomic key replace, the SideComputer playbook contracts, frontmatter, and a scan for committed secrets.

## Secrets

Do not commit private keys, passwords, tokens, host addresses, or `.env` files. Connection details belong in the owner's secret store. Tests that need key material should generate it in memory.

## SideComputer playbooks

Changes to dispatch, setup, or keys keep these rules:

- The shared hub is cooperative and advisory. `HUB_BOT` is self-asserted. Do not use it for security decisions. The owner approves a handoff before submit.
- Owner approval for consequential or networked commands (invariant 4).
- A temporary admin key arrives through a secure secret input. Passwords pasted into chat are refused.
- Do not describe host output as redacted. `stdout.log` and `stderr.log` stay unfetched unless `health` reports `artifact_redaction` as `all`, meaning every artifact is redacted on fetch.
- Key rotation is an admin session with the owner's approval. There is no gate rotate tool. `sidecomputer/admin/rotate_bot_key.py` keeps the bootstrap `command=` and `restrict` prefix, and a half-finished run must leave only the previous bot key valid.

## Pull requests

Open a pull request against `main`. Describe the behavior change and the test you ran. Security-sensitive SideComputer changes stay open until Review Bot approves them.

## License

By contributing, you agree that your contributions are licensed under the Apache License, Version 2.0. See [LICENSE](LICENSE).
