# PR Label Assigner (TypeScript + Bun)

Given a list of a PR's changed file paths, assign labels using a configurable
set of **glob path-to-label rules** (e.g. `docs/** -> documentation`,
`src/api/** -> api`, `*.test.* -> tests`). Supports glob patterns, multiple
labels per file, and **priority-based conflict resolution**, then emits the
final label set.

Built with **TypeScript** and the **Bun** runtime/test-runner, developed
red/green TDD-style, and wired into a real CI/CD pipeline (GitHub Actions)
that is validated end-to-end with `act`.

## Layout

| Path | Purpose |
| --- | --- |
| `src/labeler.ts` | Core logic: glob matching, rule application, config validation, I/O loaders. |
| `cli.ts` | CLI entrypoint the workflow drives. Prints `RESULT_LABELS=` / `RESULT_COUNT=` markers. |
| `labeler.config.json` | Default path-to-label rules (demonstrates priority + groups). |
| `changed-files.txt` | Default mocked "PR changed files" list. |
| `tests/labeler.test.ts` | Unit tests for the core logic (hermetic). |
| `tests/cli.test.ts` | Subprocess tests locking the CLI output contract. |
| `tests/workflow.test.ts` | Structural tests of the workflow YAML + `actionlint`. |
| `fixtures/<case>/` | act test cases: `changed-files.txt` + `expected.json`. |
| `act-runner.ts` | End-to-end harness: runs each fixture through the workflow via `act`. |
| `.github/workflows/pr-label-assigner.yml` | The CI/CD pipeline. |
| `act-result.txt` | Captured `act` output for every test case (generated artifact). |

## How labels are resolved

1. **Match** every changed file against every rule's glob patterns
   (`Bun.Glob`). A slash-free pattern such as `*.test.*` also matches a file's
   *basename*, so it labels test files anywhere in the tree.
2. **Multiple labels per file**: ungrouped rules are additive — one file can
   collect several labels.
3. **Conflict resolution**: rules that share a `group` are mutually exclusive;
   for a given file only the highest-`priority` rule in that group wins (ties
   broken by declaration order).
4. **Order** the final, de-duplicated label set by priority (descending) then
   alphabetically for stable, predictable output.

### Rule shape (`labeler.config.json`)

```json
{
  "rules": [
    { "label": "documentation", "patterns": ["docs/**", "*.md"], "priority": 1 },
    { "label": "api",           "patterns": ["src/api/**"],       "priority": 30 },
    { "label": "tests",         "patterns": ["*.test.*"],         "priority": 10 },

    { "label": "area/api",   "patterns": ["src/api/**"], "group": "area", "priority": 100 },
    { "label": "area/other", "patterns": ["**"],         "group": "area", "priority": 1 }
  ]
}
```

## Running

```bash
# Unit tests (fast, hermetic)
bun test

# Assign labels using the defaults (labeler.config.json + changed-files.txt)
bun run cli.ts

# Or point at explicit inputs
bun run cli.ts path/to/config.json path/to/changed-files.txt

# End-to-end pipeline tests through act (Docker required)
bun run act-runner.ts            # all fixture cases
bun run act-runner.ts case-multi # a single case
```

Inputs are resolved as: positional args → `LABELER_CONFIG` /
`CHANGED_FILES_FILE` env vars → defaults. Errors (missing/invalid config,
missing files, bad rules) are reported to stderr with a non-zero exit code.

## CI/CD pipeline

`.github/workflows/pr-label-assigner.yml` runs on `push`, `pull_request`,
`workflow_dispatch`, and a nightly `schedule`. It has two jobs:

* **test** — installs Bun and runs the unit suite.
* **assign-labels** — `needs: test`; computes the label set and, on real
  `pull_request` events only, applies the labels via the `gh` CLI. Everything
  else (push/schedule/dispatch and `act`) runs without secrets or network calls
  to GitHub, so the pipeline is fully exercisable locally.

The workflow passes `actionlint` cleanly and runs successfully under `act`; see
`act-runner.ts` and the captured `act-result.txt`.
