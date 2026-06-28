# PR Label Assigner

Assign labels to a pull request based on its **changed file paths** and a set of
**configurable glob-based path-to-label rules**. Built with **TypeScript on the
Bun runtime**, developed with red/green TDD.

## What it does

Given a list of changed file paths (the mock "PR") and a config of rules, it:

- matches each file against glob patterns (`docs/**`, `src/api/**`, `*.test.*`, …),
- lets a single file produce **multiple labels**,
- takes the **union** of labels across all files (deduplicated),
- and orders the final label set by **priority** (the meaning of "priority
  ordering when rules conflict").

### Glob semantics

| Pattern | Matches |
| ------- | ------- |
| `**` | any characters, including `/` (crosses directories) |
| `*` | any characters except `/` (stays within a path segment) |
| `?` | exactly one non-`/` character |
| slash-less pattern (e.g. `*.test.*`) | matched against the file **basename**, so it hits at any depth |
| pattern with a `/` (e.g. `docs/**`) | matched against the **full path** |

See `src/labeler.ts` for the fully-commented implementation.

## Config format

`examples/labeler.config.json` (either `{ "rules": [...] }` or a bare array):

```json
{
  "rules": [
    { "label": "documentation", "patterns": ["docs/**", "*.md"], "priority": 1 },
    { "label": "api",           "patterns": ["src/api/**"],       "priority": 10 },
    { "label": "tests",         "patterns": ["*.test.*", "**/*.spec.ts"], "priority": 5 }
  ]
}
```

A rule fires when **any** of its patterns matches **any** changed file. Higher
`priority` labels are listed first. `priority` defaults to `0`.

## Usage

```bash
# Either a JSON array of paths, or a newline-separated list (# comments allowed)
bun run src/cli.ts --config examples/labeler.config.json \
                   --files  examples/changed-files.json [--format text|json|csv]
```

The first stdout line is always a stable, machine-readable marker:

```
__PR_LABELS__=api,tests,frontend,documentation
```

When run inside GitHub Actions the CLI also writes a `labels` / `count` step
output (`$GITHUB_OUTPUT`) and a Markdown job summary (`$GITHUB_STEP_SUMMARY`).

## Project layout

| Path | Purpose |
| ---- | ------- |
| `src/labeler.ts` | Core logic: glob matching, rule evaluation, config validation |
| `src/cli.ts` | CLI entry point + GitHub Actions integration |
| `examples/` | Default config + changed-files fixture used by the workflow |
| `tests/labeler.test.ts` | Unit tests for the core logic (TDD) |
| `tests/cli.test.ts` | End-to-end CLI tests (spawns the real process) |
| `tests/workflow.test.ts` | Static workflow-structure tests + actionlint check |
| `tests/act-harness.ts` | Integration harness — runs every case through `act` |
| `.github/workflows/pr-label-assigner.yml` | The CI/CD workflow |

## Testing

```bash
bun test                     # fast unit + workflow-structure tests (47 tests)
bun run tests/act-harness.ts # integration: runs the workflow through act
```

### Integration via `act`

`tests/act-harness.ts` is the integration layer required by the task: every test
case is executed through the **real workflow** with `act push --rm` (not by
calling the script directly). For each case it builds a throwaway git repo with
that case's fixture, runs the workflow, appends the full output to
`act-result.txt`, and asserts on **exact** expected values:

| Case | Changed files | Expected labels |
| ---- | ------------- | --------------- |
| `multi-label-priority` | docs + api + api test + web | `api,tests,frontend,documentation` |
| `docs-and-ci` | docs + README + workflow file | `ci,documentation` |
| `no-matches` | LICENSE, Makefile, src/core | _(empty)_ |

Each case asserts: `act` exit code `0`, both jobs report **Job succeeded**, the
exact `__PR_LABELS__=` line, and the exact `Label count` (round-tripped through
`$GITHUB_OUTPUT`).

## Workflow

`.github/workflows/pr-label-assigner.yml` triggers on `push`, `pull_request`,
and `workflow_dispatch` (with overridable `config`/`files` inputs). It has two
jobs with a dependency: `test` (runs the unit tests) → `assign-labels` (computes
and publishes the label set). It installs Bun in the runner and passes
`actionlint` cleanly.
