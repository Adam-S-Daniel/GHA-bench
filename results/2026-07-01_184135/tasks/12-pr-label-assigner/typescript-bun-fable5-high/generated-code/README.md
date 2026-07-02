# PR Label Assigner (TypeScript + Bun)

Assigns labels to a pull request based on its changed file paths and a
configurable set of glob rules — built test-first with Bun's test runner and
wired into a GitHub Actions pipeline that runs locally under
[`act`](https://github.com/nektos/act).

## How it works

A rules config maps glob patterns to labels:

```json
{
  "rules": [
    { "pattern": "docs/**", "labels": ["documentation"] },
    { "pattern": "docs/api/**", "labels": ["api-docs"], "priority": 10 },
    { "pattern": "src/api/**", "labels": ["api", "backend"] },
    { "pattern": "*.test.*", "labels": ["tests"] }
  ]
}
```

Semantics:

- `**` crosses directories, `*` and `?` stay within one segment; a pattern
  without `/` matches the file's **basename** at any depth (so `*.test.*`
  catches test files everywhere).
- A rule may attach **multiple labels**; a file may match multiple rules.
- **Priority** (default `0`) resolves conflicts *per file*: only the matching
  rules tied for the highest priority contribute for that file. Above,
  `docs/api/rest.md` gets `api-docs` but *not* `documentation`.
- The output is the sorted, deduplicated union across all changed files.

The PR's changed files are mocked as a JSON array (`input/changed-files.json`).

## Usage

```sh
bun run src/cli.ts --config input/rules.json --files input/changed-files.json
# ...per-file breakdown...
# FINAL LABELS: api,api-docs,backend,documentation,tests
```

## Layout

| Path | Purpose |
| --- | --- |
| `src/glob.ts` / `src/labeler.ts` | glob matcher and rule engine |
| `src/cli.ts` | CLI entry point used by CI |
| `src/*.test.ts` | unit + CLI + workflow-structure tests (`bun test`) |
| `fixtures/` | stable fixtures for unit tests |
| `input/` | the workflow's (mocked) PR inputs — swapped per act test case |
| `.github/workflows/pr-label-assigner.yml` | the pipeline (test job → label job) |
| `scripts/run-act-tests.ts` | end-to-end harness: runs every case through `act push` |

## Testing

- `bun test` — 37 unit/CLI/workflow-structure tests (also run *inside* the
  pipeline's `test` job, so they all execute through act too).
- `bun run scripts/run-act-tests.ts` — builds a temp git repo per case, runs
  `act push --rm`, appends all output to `act-result.txt`, and asserts exact
  final label sets plus `Job succeeded` for both jobs.
