---
name: sidecomputer-admin
description: >-
  Use when the SideComputer host needs a new tool or MCP, a key rotation, or an
  unlock or relock.
---
# SideComputer: admin tasks

**Kit:** https://github.com/vaiev/mcp/tree/main/sidecomputer — fetch it with `git clone https://github.com/vaiev/mcp`, then use the `sidecomputer/` directory.

These change the host and always need the owner's explicit approval. Profile installs and mode changes also need an admin session (temporary admin key, or open mode). The bot's strict key cannot install packages or change mode, by design.

Bot-key removal and rotation do not need provider console, rescue mode, or an SSH admin key. They use one atomic replace, including on a locked host.

## Add a tool or MCP (profile update)
1. Never install ad hoc. Edit or add `profiles/<name>.json` in the kit: `packages` (apt), `mcps` (npm specs), `prompt_runner` (argv with `{prompt}`), limits (`max_timeout`, `memory_max`, `cpu_quota`, `artifact_max_bytes`), optional `env` without secrets.
2. Validate locally with the kit's tests.
3. Show the owner the diff and get approval.
4. Through the admin session, re-run `sudo ./bootstrap.sh --profile <all profiles> --bot-pubkey <current pubkey> --mode <mode>`.
5. Confirm with `list_profiles` and `health` over the gate.

## Rotate or remove the bot key
Run `sidecomputer/admin/rotate_bot_key.py` (on the host: `/usr/local/lib/sidecomputer/rotate_bot_key.py`) through the gate tool `rotate_bot_key`. The script writes the whole `authorized_keys` file and renames it into place. A half-finished rotation leaves the previous file untouched, so only the previous bot key stays valid. Both keys are never valid together.

Do this with the current bot key, through the gate. Console access is not part of the procedure.

Re-running bootstrap is not a rotation. Bootstrap keeps old keys, so a follow-up delete can fail and leave both keys valid. Do not append a key, and do not edit `authorized_keys` a line at a time.

The keys file is the sidecomputer user's `authorized_keys`, typically `/home/sidecomputer/.ssh/authorized_keys`.

### Replace the key
1. Generate a new ed25519 key pair. Store the private key in the secret store as pending. Keep the current key active.
2. Ask the owner to approve the rotation.
3. Call `rotate_bot_key` once. The gate runs:
   `python3 /usr/local/lib/sidecomputer/rotate_bot_key.py --keys-file /home/sidecomputer/.ssh/authorized_keys --replace-all --retire-pubkey "<current pubkey>" --bot-pubkey "<new pubkey>"`
   Add one `--keep-line` for each admin line that must remain in that file. On a locked host there is no admin line, so pass only the new bot key. Do not pass the current bot key as a keep line. `--replace-all` does not copy the old file, and `--retire-pubkey` makes the script refuse a result that still contains the current key.
4. Continue only when the tool exits 0. Otherwise stop, delete the pending private key, and keep using the current key. The failed attempt has not authorized the new key.
5. Verify `tools` with the new key, then confirm the old key is refused.
6. After that confirmation, delete the old private key everywhere it was stored and mark the new key active.

### Remove the key
To decommission the bot key, get the owner's approval and call `rotate_bot_key` once:
`python3 /usr/local/lib/sidecomputer/rotate_bot_key.py --keys-file /home/sidecomputer/.ssh/authorized_keys --replace-all --remove-bot --retire-pubkey "<current pubkey>"`
Pass `--keep-line` for each admin line that must remain. With no keep line, the file has no keys. This is one replace, with no console step. Confirm the old key is refused before deleting its private key from the secret store.

## Unlock (temporarily)
- When locked, no SSH admin key remains. Profile and package changes need an admin session restored by provider console, rescue mode, or cloud-init. A backup of the admin authorized_keys is left on the host.
- Bot-key rotation and removal stay on the atomic path above and do not use that console path.
- Or re-run bootstrap with `--mode open` for debugging. Tell the owner this is less safe and set a time limit.

## Relock
1. Re-run bootstrap with `--mode strict --lock`.
2. Check the JSON summary shows strict mode and locked.
3. Verify the gate rejects other commands and that `health` is ok. Confirm `tools` still lists `rotate_bot_key`.
4. Update memory: mode and lock state only.

## Always
- Record what changed, when, and who approved it. Do not record IPs or keys.
- Never widen a profile to `allow_command: true` without stating that it means arbitrary shell as the worker user, and that a task can also tamper with the spool and the audit log.
