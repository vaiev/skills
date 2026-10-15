---
name: sidecomputer-getting-started
description: >-
  Use the first time a new owner wants to set up a remote always-on SideComputer
  host for their bots.
---
# SideComputer: getting started

**Kit:** https://github.com/vaiev/mcp/tree/main/sidecomputer — fetch it with `git clone https://github.com/vaiev/mcp`, then use the `sidecomputer/` directory.

Use this the first time a new owner wants a remote always-on "second computer" for their bots.

## Rules
- Ask one question at a time. Wait for the answer before you ask the next one.
- Never echo or store passwords, private keys, or full host addresses in memory.
- Explain strict vs open in one plain sentence each before asking.
- Setup secrets go through a secure secret input. Refuse a password, token, or private key pasted into chat, and tell the owner to revoke anything they already pasted.

## Conversation
1. Purpose: "What should the SideComputer mostly do?" Map the answer to a profile:
   - running CLI coding agents: `worker-cli-agents`
   - cloning, building and testing repos: `repo-bridge`
   - scripts and heavy computation: `compute`
   - anything else: `custom` (the admin edits it first)
2. Host: "What is the host's IP or hostname, and which admin user should the one-time setup use?" Ask for a temporary admin key through the client's secure secret input, the secret request that stays out of the chat transcript. Refuse a password. Setup has no password login.
3. Mode: "Strict (recommended): I can only submit tasks and read short summaries. Open: I get a normal shell, which is less safe. Which one? And should I remove the setup admin key afterwards (lock)?" Locking removes that setup key. Later bot-key removal uses the atomic replace in the admin skill and does not need the console. Profile and package changes still need an admin session.
4. Delegation: "Which of your other bots may hand me tasks for the SideComputer?" Record the identities the hub can verify, as the allowlist. A name a bot claims in a message is not an allowlist entry.
5. Short alias: "What short name should I use for this host?" (e.g. `side1`).

## Bootstrap
1. Fetch the kit from the Kit line above: `git clone https://github.com/vaiev/mcp`, then use the `sidecomputer/` directory (`bootstrap.sh`, gate, worker, profiles, client).
2. Generate a fresh ed25519 key pair for the bot. Keep the private key in the secret store or env, never in chat.
3. Over the one-time admin session, copy the kit to the host and run bootstrap without locking yet:
   `sudo ./bootstrap.sh --profile <profile> --bot-pubkey "<pubkey>" --mode <strict|open>`
4. Parse the JSON summary. If `ok` is false, report the error and stop.
5. Copy `sidecomputer/admin/rotate_bot_key.py` from this skill library to `/usr/local/lib/sidecomputer/rotate_bot_key.py` on the host, mode `0755`, root-owned. The gate tool `rotate_bot_key` must run that script with `--replace-all`. Confirm `tools` lists `rotate_bot_key`. If it does not, stop. Do not lock a host that can only drop its bot key from the console.
6. If the owner asked to lock, re-run bootstrap with `--mode strict --lock` only after `rotate_bot_key` is listed.
7. Verify: `sc_client.py --host <host> tools`, then `call health '{}'`. Pin the host key.
8. Confirm to the owner: mode, profiles, lock state, any warnings, and the delegating bots.

## Memory
Save only:
- host alias and mode (and lock yes/no)
- the allowlist of verified bot identities that may delegate
Do not save the IP, users, keys, passwords or bootstrap output. The connection details live in the secret store.

## Done when
`health` returns ok with `worker_alive: true`, `tools` lists `rotate_bot_key`, and the owner has confirmed the summary.
