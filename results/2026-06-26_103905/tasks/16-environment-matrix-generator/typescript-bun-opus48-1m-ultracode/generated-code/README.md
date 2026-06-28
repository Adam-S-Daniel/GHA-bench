# Environment Matrix Generator

Generate a GitHub Actions `strategy.matrix` build matrix (as JSON) from a
configuration of **OS options, language versions, and feature flags**. Supports
`include`/`exclude` rules, `max-parallel`/`fail-fast` settings, and validates
that the matrix does not exceed a maximum size.

Implemented in **TypeScript** and run with **[Bun](https://bun.sh)**.

## Quick start

```bash
# From a file
bun run matrix-generator.ts fixtures/exclude-include.config.json

# From stdin
cat fixtures/basic.config.json | bun run matrix-generator.ts -

# Fail the process (exit 2) if the matrix exceeds max-size
bun run matrix-generator.ts fixtures/over-limit.config.json --strict

# Single-line output
bun run matrix-generator.ts fixtures/basic.config.json --compact
```

## Configuration schema

The input mirrors a GitHub Actions `strategy` block, plus a `max-size` knob:

```jsonc
{
  "fail-fast": false,        // optional, default true (GitHub's default)
  "max-parallel": 4,         // optional, omitted from output if unset
  "max-size": 100,           // optional, default 256 (GitHub's hard limit)
  "matrix": {
    "os": ["ubuntu-latest", "windows-latest"],   // a dimension/axis
    "node": ["18", "20", "22"],                  // another dimension
    "feature": ["minimal", "full"],              // another dimension
    "exclude": [                                  // partial-match removal
      { "os": "windows-latest", "node": "18" }
    ],
    "include": [                                  // GitHub merge/append rules
      { "os": "macos-latest", "node": "22", "feature": "full", "experimental": true }
    ]
  }
}
```

`camelCase` aliases (`failFast`, `maxParallel`, `maxSize`) are also accepted.

### Expansion semantics

The generator follows GitHub's documented algorithm exactly:

1. **Cartesian product** of every non-reserved key in `matrix` (the first
   dimension varies slowest, the last fastest).
2. **`exclude`** — drop any combination that *partially* matches an exclude
   entry (only the listed keys need to match).
3. **`include`** — for each entry, merge its keys into existing combinations
   where it does not overwrite an original matrix value; if it matches none, it
   is appended as a brand-new combination. Newly appended combinations are not
   themselves merge targets for later include entries.

## Output

The fully-expanded matrix is emitted as an "include only" matrix, which GitHub
runs verbatim with no further expansion:

```json
{
  "strategy": {
    "fail-fast": false,
    "matrix": { "include": [ { "os": "ubuntu-latest", "node": "20" }, ... ] },
    "max-parallel": 4
  },
  "size": 10,
  "max-size": 100,
  "within-limit": true
}
```

`within-limit` is `false` when `size > max-size`. By default this is reported
(exit 0) so callers can decide what to do; `--strict` turns it into a hard
failure (exit 2).

## Exit codes

| Code | Meaning |
| ---- | ------- |
| 0 | Success |
| 1 | Invalid configuration / I/O / JSON error |
| 2 | Matrix exceeds `max-size` (only with `--strict`) |

## Project layout

| File | Purpose |
| ---- | ------- |
| `matrix-generator.ts` | Library (pure expansion functions) **and** CLI |
| `matrix-generator.test.ts` | Red/green TDD unit tests for the logic + CLI |
| `workflow.test.ts` | Workflow structure tests + the `act` end-to-end harness |
| `fixtures/*.config.json` | Test-case configurations |
| `.github/workflows/environment-matrix-generator.yml` | The CI pipeline |
| `act-result.txt` | Captured output of every `act` run (generated artifact) |

## Testing

```bash
bun test                       # everything (unit + structure + act harness)
bun test matrix-generator.test.ts            # fast unit tests only
bun test workflow.test.ts -t "Workflow structure"   # offline structure checks
bun test workflow.test.ts -t "act integration"      # the act harness (slow)
```

The **act harness** builds a throwaway git repo per fixture, runs the workflow
with `act push --rm`, appends the full output to `act-result.txt`, and asserts
on the exact known-good values for each fixture (size, within-limit, fail-fast,
max-parallel, and the complete expanded `include` array), plus that every job
reports `Job succeeded`.

## The workflow

`.github/workflows/environment-matrix-generator.yml` runs on `push`,
`pull_request`, `workflow_dispatch` (with a `config` input), and a weekly
`schedule`. The `generate-matrix` job checks out the repo, installs Bun, runs
the generator against `$CONFIG_FILE` (selectable per test case via `act --env`),
and exposes the matrix as a job output. The dependent `report` job consumes that
output via `fromJSON`/`jq` — exactly how a real dynamic-matrix pipeline feeds a
generated matrix into downstream jobs. It passes `actionlint` cleanly.
