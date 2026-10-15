---
name: sidecomputer-admin
description: >-
  Use when the SideComputer host needs a new tool or MCP, a key rotation, or an
  unlock or relock.
---
# SideComputer: admin tasks

**Kit:** https://github.com/vaiev/mcp/tree/main/sidecomputer — fetch it with `git clone https://github.com/vaiev/mcp`, then use the `sidecomputer/` directory.

These change the host and always need the owner's explicit approval plus an admin session (temporary admin key, open mode, or console or provider access when locked). The bot's strict key cannot do any of this, by design.

## Add a tool or MCP (profile update)
1. Never install ad hoc. Edit or add `profiles/<name>.json` in the kit: `packages` (apt), `mcps` (npm specs), `prompt_runner` (argv with `{prompt}`), limits (`max_timeout`, `memory_max`, `cpu_quota`, `artifact_max_bytes`), optional `env` without secrets.
2. Validate locally with the kit's tests.
3. Show the owner the diff and get approval.
4. Through the admin session, re-run `sudo ./bootstrap.sh --profile <all profiles> --bot-pubkey <current pubkey> --mode <mode>`.
5. Confirm with `list_profiles` and `health` over the gate.

## Rotate the bot key
1. Generate a new ed25519 key pair and store the private key in the secret store.
2. Admin session: re-run bootstrap with the new `--bot-pubkey`, then remove the old key line from the sidecomputer user's authorized_keys.
3. Verify `tools` with the new key and confirm the old key is refused.
4. Delete the old private key everywhere it was stored.

## Unlock (temporarily)
- When locked, no SSH admin key remains. Use provider console, rescue mode or cloud-init to restore an admin key. A backup of the admin authorized_keys is left on the host.
- Or re-run bootstrap with `--mode open` for debugging. Tell the owner this is less safe and set a time limit.

## Relock
1. Re-run bootstrap with `--mode strict --lock`.
2. Check the JSON summary shows strict mode and locked.
3. Verify the gate rejects other commands and that `health` is ok.
4. Update memory: mode and lock state only.

## Always
- Record what changed, when, and who approved it. Do not record IPs or keys.
- Never widen a profile to `allow_command: true` without stating that it means arbitrary shell as the worker user.
