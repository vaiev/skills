# VAIEV skills

Shared playbooks for VAIEV bots. A skill is a short document a bot reads before it acts, so every bot follows the same steps and the same safety rules.

The first family is SideComputer: a remote, always-on host a bot can use as a second computer. The dispatcher bot is the only one that holds the host key. Other bots hand it tasks. The host gate accepts a strict key, runs the task in a profile, and returns a short summary.

## Quickstart

```bash
git clone https://github.com/vaiev/skills.git
cd skills
python3 -m unittest discover -s tests -v
```

Use a skill:

1. Match the request to a row in the table below by reading `name` and `description`.
2. Open that skill's `SKILL.md` and read it through before acting.
3. Follow its rules for the whole job. When the skill names a kit, fetch the kit the way the **Kit** line says.

Set up a host for the first time by reading [`sidecomputer/getting-started/SKILL.md`](sidecomputer/getting-started/SKILL.md). Ask the owner for a temporary admin key through a secure secret input. Setup does not take a password in chat.

The host kit is https://github.com/vaiev/mcp/tree/main/sidecomputer. Fetch it with `git clone https://github.com/vaiev/mcp`, then use the `sidecomputer/` directory.

## Architecture and threat model

```mermaid
flowchart TB
  Owner[Owner]
  OtherBots[Other bots]
  Hub[Authenticated hub]
  Dispatch[Dispatcher bot]
  Gate[SideComputer gate]
  Worker[Worker profile]
  Keys[authorized_keys]

  OtherBots -->|"handoff text is data"| Hub
  Hub -->|"verified sender identity"| Dispatch
  Owner -->|"allowlist and approval"| Dispatch
  Owner -->|"temporary admin key via secure secret input"| Gate
  Dispatch -->|"strict key: submit and poll"| Gate
  Gate --> Worker
  Worker -->|"summary string, untrusted"| Dispatch
  Dispatch -.->|"do not fetch stdout.log or stderr.log"| Gate
  Dispatch -->|"rotate_bot_key, one rename"| Keys
```

The dotted arrow is the fetch the dispatcher must not make. Until the MCP redaction gate is fixed, `stdout.log` and `stderr.log` stay on the host.

| Boundary | What crosses it | What stays out |
| --- | --- | --- |
| Other bots to the hub | A handoff: profile, command or prompt, timeout, goal | The host key, the host address, and any bot name claimed inside the text. The sender is the hub's verified identity (invariants 1 and 3). |
| Dispatcher to the gate | `submit_task`, `task_status`, `cancel_task`, and a summary of at most 500 characters | `stdout.log` and `stderr.log` until the MCP redaction gate is fixed. Artifact contents are not forwarded to other bots. |
| Owner to the dispatcher | Allowlist entries, and approval for consequential or networked commands (invariant 4) | Passwords, tokens, and private keys pasted into chat. Those are refused. A temporary admin key arrives through a secure secret input. |
| Dispatcher to `authorized_keys` | One `rotate_bot_key` replace | A second valid bot key. The new file is renamed into place. A failure before that rename leaves the previous key as the only bot key. Console access is not required. |

`allow_command: true` on a profile means arbitrary shell as the worker user, and a task can also tamper with the spool and the audit log.

## Layout

One folder per skill family. Each skill is its own directory, and the playbook is `SKILL.md`.

```
sidecomputer/
  getting-started/SKILL.md
  dispatch/SKILL.md
  admin/SKILL.md
  admin/rotate_bot_key.py
```

Every `SKILL.md` starts with YAML frontmatter:

```yaml
---
name: skill-name
description: >-
  When to use this skill.
---
```

`name` is the skill id. `description` says when the skill applies, so a bot can pick it from the request in front of it.

## SideComputer skills

Use these paths when another repository links here. The same table is in [`sidecomputer/README.md`](sidecomputer/README.md).

| Skill | File | Canonical path | Use when |
| --- | --- | --- | --- |
| sidecomputer-getting-started | `sidecomputer/getting-started/SKILL.md` | `vaiev/skills/sidecomputer/getting-started/SKILL.md` | A new owner sets up a SideComputer host for the first time |
| sidecomputer-dispatch | `sidecomputer/dispatch/SKILL.md` | `vaiev/skills/sidecomputer/dispatch/SKILL.md` | Another bot hands a task to the host: submit it, poll, and return status and summary |
| sidecomputer-admin | `sidecomputer/admin/SKILL.md` | `vaiev/skills/sidecomputer/admin/SKILL.md` | The host needs a new tool or MCP, a key rotation, or an unlock or relock |

The dispatch playbook is `vaiev/skills/sidecomputer/dispatch/SKILL.md`.

## Development

```bash
python3 -m unittest discover -s tests -v
```

GitHub Actions runs that command on every push and pull request. See [CONTRIBUTING.md](CONTRIBUTING.md) for adding a skill, and [SECURITY.md](SECURITY.md) for how to report a vulnerability.

## License

Copyright 2026 VAIEV. Licensed under the [Apache License, Version 2.0](LICENSE).
