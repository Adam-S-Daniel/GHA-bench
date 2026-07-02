# PR Label Assigner (TypeScript + Bun)

Given a mocked list of changed file paths (as from a PR), applies labels
based on configurable glob-pattern rules and prints the final label set.

## Usage

```sh
bun run src/cli.ts --files fixtures/active/changed-files.json --rules fixtures/active/rules.json
```

Output: `LABELS: a,b,c` (or `LABELS: <none>`), `LABEL_COUNT: N`, and a
`JSON: [...]` line. Invalid input exits 1 with an `error: ...` message.

## Rule semantics

- Rules are `{ pattern, labels[], priority? }` (bare array or `{ "rules": [...] }`).
- Globs: `**` crosses `/`, `*` and `?` do not; patterns without a `/`
  (e.g. `*.test.*`) match against the basename.
- One rule may apply several labels; several rules may match one file.
- **Priority** (default 0, higher wins) resolves conflicts per file: only the
  highest-priority matching rules contribute labels for that file.
- The result is the sorted, deduplicated union across all changed files.

## Layout

- `src/label-assigner.ts` — core library (glob matching, rule validation, assignment)
- `src/cli.ts` — CLI entry point
- `tests/` — bun-test suite, built with red/green TDD (one file per TDD cycle):
  glob → assignment/priority → config validation → CLI → workflow structure → act e2e
- `fixtures/caseN/` — mock changed-file lists + rule configs; `fixtures/active/`
  is what the workflow reads (the e2e harness swaps each case in)
- `.github/workflows/pr-label-assigner.yml` — CI pipeline (checkout, install Bun,
  unit tests, run the assigner)

## Testing

`bun test` runs everything. The e2e suite (`tests/act-e2e.test.ts`) copies the
project plus each case's fixtures into a temp git repo, executes the workflow
with `act push --rm --pull=false`, appends the output to `act-result.txt`, and
asserts exact label output and `Job succeeded` per case.
