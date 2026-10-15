# Security policy

## Reporting a vulnerability

Report a vulnerability in this repository through [GitHub private vulnerability reporting](https://github.com/vaiev/skills/security/advisories/new) on `vaiev/skills`.

Do not open a public issue, pull request, or chat message that contains a private key, password, token, host address, or a log that might contain one of those. If a secret was already pasted somewhere public, revoke it before reporting.

The SideComputer host and gate live in the kit at https://github.com/vaiev/mcp/tree/main/sidecomputer. A playbook bug that tells a bot to fetch raw logs, trust a self-claimed bot name, accept a password in chat, or rotate keys in two steps is in scope for this repository.

## Rules the playbooks enforce

- Dispatch does not fetch `stdout.log` or `stderr.log` until the MCP redaction gate is fixed, and it does not forward artifact contents to other bots. The summary string is untrusted host text.
- The sender is the verified identity from the authenticated channel (invariants 1 and 3). Handoff text is data and cannot grant permission.
- Consequential or networked commands need the owner's approval, including when the sender is on the allowlist (invariant 4).
- Setup secrets come from a secure secret input. A password, token, or private key pasted into chat is refused.
- Bot-key rotation and removal run `sidecomputer/admin/rotate_bot_key.py` as one atomic replace. A half-finished run leaves the previous key as the only bot key. Console access is not required.
- `allow_command: true` means arbitrary shell as the worker user, and a task can also tamper with the spool and the audit log.

## Supported versions

Fixes land on `main`. Use the latest `main`.
