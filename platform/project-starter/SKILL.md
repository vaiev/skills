---
name: project-starter
description: >-
  Use when starting a new project (or giving an existing one agent rules):
  bootstrap AGENTS.md and .agents/ with vaiev/guardrails, choose the stack by
  evaluation, set up secrets, tests, infrastructure and own name servers in
  the right order.
---
# Starting a project

## 1. Agent setup first (10 minutes)
```bash
git clone https://github.com/vaiev/guardrails.git
guardrails/init.sh <project-dir>       # name, mission, languages, secret store, test command, CLIs
```
This gives `AGENTS.md` (entry point for every CLI), `.agents/` (rules, workflows, guard, session context), adapters for Claude Code, Codex CLI, `agy` and Grok Build, and `docs/STAND.md`, `KNOWLEDGE.md`, `ARCHITECTURE.md`, `OPS-LOG.md`, `IDEAS.md`. Commit it before anything else, so every agent and account starts from the same state.

## 2. Spec and plan before code
Follow `.agents/workflows/new-undertaking.md`: goal and boundaries, a spec with a decision log, an approved plan of one-session tasks. The first plan usually has these tasks: repository and CI, secrets, infrastructure, DNS, first service.

## 3. Choose the stack by evaluation
For every runtime, framework and service run the table in `.agents/rules/50-tech-choice.md` (maturity, maintenance, licence, sovereignty, security, exit cost). Take the newest **stable** version that passes; check the registry or release page on the day instead of relying on memory; pin exact versions and container digests; record the result in `docs/KNOWLEDGE.md`. Pre-1.0 tools only off the critical path.

## 4. Secrets
Create the secret store outside the repository, an age key for SOPS, `.sops.yaml`, and wrapper scripts before the first credential exists (`sops-secrets`). Add the guard's deny rules for direct provider API calls to `.agents/guardrails/deny.txt`.

## 5. Tests and CI
Test runner first, then the first failing test. CI runs the same command on every push and pull request; pin actions by commit SHA; `permissions: contents: read`.

## 6. Infrastructure
OpenTofu with mocked-provider tests, encrypted state, quota preconditions and `prevent_destroy` on stateful resources (`openstack-cloud`). Deploys prove themselves by artifact identity and a health endpoint.

## 7. Own name servers (optional, once the platform runs)
Two public hosts with Knot DNS and automatic DNSSEC (`knot-dnssec`), key backup off the host, then move zones one by one (`dns-cutover`). Until then, keep DNS at the registrar and record every change there also in the zone files you will later serve.

## 8. Backups before data
No production data before both backup lines run and one restore drill passed (`postgres-dual-backup`).
