# Platform skills

Playbooks for running a small sovereign platform with coding agents: cloud, name servers, backups, secrets and project start. They come from a production setup and use placeholders (`<project>`, `<zone>`, documentation IP ranges) instead of real values.

| Skill | Canonical path | Use when |
| --- | --- | --- |
| openstack-cloud | `vaiev/skills/platform/openstack-cloud/SKILL.md` | Servers, networks, volumes or object storage on an OpenStack cloud with OpenTofu |
| knot-dnssec | `vaiev/skills/platform/knot-dnssec/SKILL.md` | Own authoritative name servers with Knot DNS and automatic DNSSEC |
| dns-cutover | `vaiev/skills/platform/dns-cutover/SKILL.md` | Moving a zone to new name servers without SERVFAIL (glue, DS, NS order) |
| postgres-dual-backup | `vaiev/skills/platform/postgres-dual-backup/SKILL.md` | pgBackRest PITR plus age-encrypted dumps, pruning, restore drill |
| sops-secrets | `vaiev/skills/platform/sops-secrets/SKILL.md` | Any work that touches secrets: store, SOPS + age, wrappers, rotation |
| project-starter | `vaiev/skills/platform/project-starter/SKILL.md` | Starting a project with `vaiev/guardrails`, stack evaluation, setup order |

The agent rules these playbooks assume (one task per session, plan gate, test first, secrets only through wrappers) are in [vaiev/guardrails](https://github.com/vaiev/guardrails).
