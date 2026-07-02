# Artifact Cleanup Script

Plans (and optionally applies) retention cleanup for CI artifacts given a
mock inventory (name, size, creation date, workflow run id) and a retention
policy. Built test-first in Python (stdlib only — nothing to install in CI).

## Retention policy

`fixtures/policy.json` may set any of (omit or `null` disables a rule):

| Rule                   | Meaning                                                          |
|------------------------|------------------------------------------------------------------|
| `max_age_days`         | delete artifacts strictly older than this many days              |
| `keep_latest_n`        | per workflow run, keep only the N newest artifacts               |
| `max_total_size_bytes` | evict the oldest *retained* artifacts until the total fits       |

Rules apply in that fixed order; when several rules would delete the same
artifact, the first rule's reason is reported. Output is deterministic:
decisions are listed oldest-first, and the reference time can be pinned
with `--now` for reproducible plans.

## Usage

```bash
# Dry run (default): prints the plan + summary, deletes nothing
python3 artifact_cleanup.py --artifacts fixtures/artifacts.json \
    --policy fixtures/policy.json --now "$(cat fixtures/now.txt)"

# Apply mode: drives the deleter (a no-op mock for this fixture data;
# a real artifact-API client plugs into the same one-method interface)
python3 artifact_cleanup.py --artifacts ... --policy ... --apply
```

Exit codes: `0` success, `2` input/validation error (message on stderr).

## Tests

- `tests/test_artifact_cleanup.py` — unit suite, written red/green TDD
  (loading/validation, each policy rule, report rendering, dry-run vs apply
  with a recording mock deleter, CLI). Runs **through the workflow via act**.
- `test_workflow_structure.py` — parses the workflow YAML (triggers, jobs,
  `needs`, checkout steps), verifies referenced paths exist, asserts
  actionlint passes. Runs on the host (the act container has no PyYAML).
- `run_act_tests.py` — end-to-end harness: for each of 3 fixture cases it
  builds a temp git repo, runs `act push --rm`, appends output to
  `act-result.txt`, and asserts act exit 0, both jobs "Job succeeded", and
  exact expected plan values (hand-derived from each case's inputs).

```bash
python3 run_act_tests.py        # structure tests + all cases through act
```

## CI

`.github/workflows/artifact-cleanup-script.yml` — `push`, `workflow_dispatch`
and a daily `schedule`; least-privilege `permissions: contents: read`.
Job `unit-tests` runs the suite; job `cleanup-plan` (`needs: unit-tests`)
prints the dry-run plan, then runs the mock apply step.
