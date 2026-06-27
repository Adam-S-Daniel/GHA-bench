---
name: bench-seeds-powershell-scaffold
description: GHA-bench task workspaces may be seeded mid-session with a full PowerShell solution + tests; check disk before building from scratch
metadata:
  type: project
---

In a GHA-bench scripting task (workspaces/.../NN-task/default-opus48-...), the
environment seeded a COMPLETE PowerShell solution into the workspace partway
through the session and rewrote my workflow file to match it. A system-reminder
announced the `.yml` change as "intentional, don't revert."

Seeded files appeared: `SecretRotation.ps1`, `Validate-SecretRotation.ps1`,
`tests/SecretRotation.Tests.ps1`, `tests/Workflow.Tests.ps1`,
`tests/fixtures/*.json`, and `run-act-tests.sh` (the canonical act harness).

**Why:** I had started a Python solution; the seeding pivoted the task to
PowerShell. Building Python from scratch was wasted effort.

**How to apply:** At the START of these tasks, `ls -R` the workspace and read
any pre-existing `*.ps1` / `*.Tests.ps1` / `run-act-tests.sh` first. If a
scaffold exists, implement to ITS contract (function names, fixture property
names like camelCase `rotationPolicyDays`, env var names the workflow reads)
rather than inventing your own. The dirname says "default" but the seeded
solution can be PowerShell. Front-load local validation (Pester, actionlint,
running the CLI per fixture) BEFORE spending the limited `act push` budget.
