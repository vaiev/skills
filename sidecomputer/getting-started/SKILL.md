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

## Conversation
1. Purpose: "What should the SideComputer mostly do?" Map the answer to a profile:
   - running CLI coding agents: `worker-cli-agents`
   - cloning, building and testing repos: `repo-bridge`
   - scripts and heavy computation: `compute`
   - anything else: `custom` (the admin edits it first)
2. Host: "What is the host's IP or hostname, and which admin user and login method can I use once for setup?" Prefer a temporary admin key, requested via a secret request. If the owner gives a password, use it only for this session.
3. Mode: "Strict (recommended): I can only submit tasks and read short summaries. Open: I get a normal shell, which is less safe. Which one? And should I remove the setup admin key afterwards (lock)? Locking means later changes need console or provider access."
4. Delegation: "Which of your other bots may hand me tasks for the SideComputer?" Record their names as the allowlist.
5. Short alias: "What short name should I use for this host?" (e.g. `side1`).

## Bootstrap
1. Make sure the SideComputer kit (bootstrap.sh, gate, worker, profiles, client) is on your computer. If it is missing, ask the owner where to get it.
2. Generate a fresh ed25519 key pair for the bot. Keep the private key in the secret store or env, never in chat.
3. Over the one-time admin session, copy the kit to the host and run:
   `sudo ./bootstrap.sh --profile <profile> --bot-pubkey "<pubkey>" --mode <strict|open> [--lock]`
4. Parse the JSON summary. If `ok` is false, report the error and stop.
5. Verify: `sc_client.py --host <host> tools`, then `call health '{}'`. Pin the host key.
6. Confirm to the owner: mode, profiles, lock state, any warnings, and the delegating bots.

## Memory
Save only:
- host alias and mode (and lock yes/no)
- the allowlist of bots that may delegate
Do not save the IP, users, keys, passwords or bootstrap output. The connection details live in the secret store.

## Done when
`health` returns ok with `worker_alive: true` and the owner has confirmed the summary.
