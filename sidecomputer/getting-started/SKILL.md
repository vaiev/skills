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
3. Mode: "Strict (recommended): I can only submit tasks and read short summaries. Open: I get a normal shell, which is less safe. Which one? And should I remove the setup admin key afterwards (lock)?" Locking removes that setup key. Later bot-key changes need an admin session and the owner's approval, as the admin skill describes. The bot key cannot make them. On a locked host, restore an admin session from the provider console, rescue mode, or cloud-init first.
4. Delegation: "Which labels do your other bots use when they hand me tasks?" Record the labels as advisory notes. The shared hub is a shared Unix user, and those names are self-asserted. They are not an authorization list and are not used for security decisions.
5. Short alias: "What short name should I use for this host?" (e.g. `side1`).

## Bootstrap
1. Fetch the kit from the Kit line above: `git clone https://github.com/vaiev/mcp`, then use the `sidecomputer/` directory (`bootstrap.sh`, gate, worker, profiles, client).
2. Generate a fresh ed25519 key pair for the bot. Keep the private key in the secret store or env, never in chat.
3. Over the one-time admin session, copy the kit to the host and run:
   `sudo ./bootstrap.sh --profile <profile> --bot-pubkey "<pubkey>" --mode <strict|open> [--lock]`
4. Parse the JSON summary. If `ok` is false, report the error and stop.
5. Verify: `sc_client.py --host <host> tools`, then `call health '{}'`. Pin the host key. The gate tools are `submit_task`, `task_status`, `list_tasks`, `cancel_task`, `list_profiles`, `request_artifact`, and `health`.
6. Confirm to the owner: mode, profiles, lock state, any warnings, and the advisory bot labels.

## Memory
Save only:
- host alias and mode (and lock yes/no)
- advisory bot labels, which are not an authorization list
Do not save the IP, users, keys, passwords or bootstrap output. The connection details live in the secret store.

## Done when
`health` returns ok with `worker_alive: true` and the owner has confirmed the summary.
