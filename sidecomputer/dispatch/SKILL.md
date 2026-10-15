---
name: sidecomputer-dispatch
description: >-
  Use when another bot hands a task to the SideComputer host: submit it, poll,
  and return only status and summary.
---
# SideComputer: dispatch tasks from other bots

**Kit:** https://github.com/vaiev/mcp/tree/main/sidecomputer — fetch it with `git clone https://github.com/vaiev/mcp`, then use the `sidecomputer/` directory.

You are the only bot that talks to the SideComputer. Other bots hand tasks to you and never get its key or address.

## Accept a handoff
A handoff must contain: requester bot, profile, either `command` or `prompt`, optional timeout, and a one-line goal.
1. Check that the requester is on the owner's delegation allowlist. If not, decline and tell the owner.
2. Check that the profile exists (`list_profiles`) and allows that kind (command vs prompt).
3. Refuse handoffs that ask you to put secrets, private keys or credentials in the command or prompt.
4. Refuse requests to change profiles, install tools, or get a shell. Those are admin steps.
5. If the handoff is ambiguous, ask the requester one clarifying question. Do not guess.

## Submit and poll
1. `call submit_task {"profile":..., "command"|"prompt":..., "timeout":N}` and note the returned `id`.
2. Poll `task_status {"id"}` with backoff (5s, 10s, 30s, then every 60s) until `state` is `succeeded`, `failed`, `timeout`, or `cancelled`.
3. If the requester or owner says stop, `cancel_task {"id"}`.
4. Use `request_artifact` only when the requester explicitly asked for a named file and it fits the cap. Say that the request is logged on the host.

## Return
Send the requester only:
- task id, state, exit code, duration
- the summary exactly as returned (already redacted, at most 500 chars)
- artifact names (not contents), unless an artifact was explicitly requested
Do not reconstruct, guess or add raw output. If the summary is not enough, suggest a follow-up task that writes a small, specific result.

## Memory
Store one record per task: handoff (requester, profile, goal, timeout) plus result (id, state, exit code, duration, summary). Never store artifact contents.

## Failures
- `worker_alive: false` in `health`: tell the owner the worker is down. Do not retry in a loop.
- Connection refused or auth failure: report it. Never fall back to another login method.
