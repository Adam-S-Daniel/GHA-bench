---
name: act-pull-false-gotcha
description: In this benchmark, act invocations must pass --pull=false or they fail at image pull
metadata:
  type: project
---

When running `act` in this GHA-bench environment, the workflow image
(`act-ubuntu-pwsh:latest`, set via the auto-injected `.actrc` `-P` mapping) is
present **locally only**. `act`'s default `--pull=true` makes it force-pull that
tag from a registry, which fails instantly with
`Error response from daemon: authentication required - incorrect username or password`
and "Job failed" before any step runs.

**Why:** the custom image is never published to a registry; `.actrc` only maps
the platform, it does not disable pulling.

**How to apply:** always invoke `act push --rm --pull=false` (the image is
already local). This avoids burning your limited act-run budget on instant
pull-auth failures. Validate the workflow with `actionlint` (instant) before any
act run.
