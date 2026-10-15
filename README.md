# VAIEV skills

This repository is VAIEV's shared knowledge and skill library for AI bots. A skill is a short playbook a bot reads before it does a job, so every bot follows the same steps.

## Layout

One folder per skill family. Each skill is its own directory inside that family, and the playbook is `SKILL.md`.

```
sidecomputer/
  getting-started/SKILL.md
  dispatch/SKILL.md
  admin/SKILL.md
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

## How a bot uses a skill

1. Match the request to a skill by reading `name` and `description`.
2. Open that skill's `SKILL.md` and read it through before acting.
3. Follow its rules, conversation, and memory limits for the whole job.
4. When the skill names a kit, fetch that kit the way the **Kit** line says and work from the directory it names.

## SideComputer

Skills for a remote always-on host that bots use as a second computer. The kit they drive is at https://github.com/vaiev/mcp/tree/main/sidecomputer. Fetch it with `git clone https://github.com/vaiev/mcp`, then use the `sidecomputer/` directory.

Use these paths when another repository links here. The same table is in `sidecomputer/README.md`.

| Skill | File | Canonical path | Use when |
| --- | --- | --- | --- |
| sidecomputer-getting-started | `sidecomputer/getting-started/SKILL.md` | `vaiev/skills/sidecomputer/getting-started/SKILL.md` | A new owner sets up a SideComputer host for the first time |
| sidecomputer-dispatch | `sidecomputer/dispatch/SKILL.md` | `vaiev/skills/sidecomputer/dispatch/SKILL.md` | Another bot hands a task to the host: submit it, poll, and return status and summary |
| sidecomputer-admin | `sidecomputer/admin/SKILL.md` | `vaiev/skills/sidecomputer/admin/SKILL.md` | The host needs a new tool or MCP, a key rotation, or an unlock or relock |

The dispatch playbook is `vaiev/skills/sidecomputer/dispatch/SKILL.md`.
