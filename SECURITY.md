# Security policy

## Reporting a vulnerability

Contact the vaiev organization owners at https://github.com/vaiev. Do not include a private key, password, token, host address, or a log that might contain one of those. If a secret was already pasted somewhere public, revoke it before reporting.

GitHub private vulnerability reporting for this repository is https://github.com/vaiev/skills/security/advisories/new. That page works only after the feature is enabled in the repository settings. Until then, use the organization contact above. Do not open a public issue with the report.

The SideComputer host and gate live in the kit at https://github.com/vaiev/mcp/tree/main/sidecomputer. A playbook bug that tells a bot to fetch raw logs, treat a self-asserted hub name as authority, accept a password in chat, or rotate keys in two steps is in scope for this repository.

## Rules the playbooks enforce

- The shared hub is cooperative and advisory. It runs as a shared Unix user, and `HUB_BOT` or `--bot` is self-asserted. Do not use it for security decisions. The owner approves a handoff before submit.
- Do not describe the summary or any artifact as redacted. Dispatch fetches an artifact, including `stdout.log` and `stderr.log`, only when `health` reports `artifact_redaction` as `all`. That value means the mcp gate redacts every artifact on fetch. Otherwise every artifact stays unfetched, and artifact contents are not forwarded.
- Consequential or networked commands are called out to the owner before submit (invariant 4).
- Setup secrets come from a secure secret input. A password, token, or private key pasted into chat is refused.
- There is no gate rotate tool. Bot-key rotation is an admin session with the owner's approval. `sidecomputer/admin/rotate_bot_key.py` runs as root, refuses the sidecomputer user, and keeps the bootstrap `command="/usr/local/bin/sidecomputer-gate",restrict` or `restrict,pty` prefix. A half-finished run leaves the previous key as the only bot key. Admin keys live in the admin user's `authorized_keys`.
- `allow_command: true` means arbitrary shell as the worker user, and a task can also tamper with the spool and the audit log.

## Supported versions

Fixes land on `main`. Use the latest `main`.
