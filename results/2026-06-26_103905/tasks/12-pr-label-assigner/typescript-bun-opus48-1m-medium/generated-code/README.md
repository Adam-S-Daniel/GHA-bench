# PR Label Assigner (TypeScript + Bun)

Given a list of changed file paths (a mocked PR diff), apply labels based on
configurable path-to-label glob rules. Supports glob patterns, multiple labels
per file, and priority ordering when rules conflict.

## Layout

| File | Purpose |
| --- | --- |
| `src/glob.ts` | Glob → RegExp matcher (`*`, `?`, `**`, basename matching) |
| `src/label-assigner.ts` | Core: map changed files → ordered, deduped label set |
| `src/config.ts` | Parse/validate rules JSON and the changed-files list |
| `src/render.ts` | Deterministic, machine-parseable report (`LABELS=` markers) |
| `src/cli.ts` | CLI entrypoint, error handling, `$GITHUB_OUTPUT` integration |
| `label-config.json` | Default path → label rules with priorities |
| `tests/fixtures/*.txt` | Mocked changed-file lists per test case |
| `.github/workflows/pr-label-assigner.yml` | CI pipeline that runs the script |
| `tests/workflow.test.ts` | Runs every case through the workflow via `act` |

## Usage

```bash
bun run src/cli.ts --config label-config.json --files changed-files.txt
```

Output includes stable marker lines (`LABELS=`, `LABEL_COUNT=`, `UNMATCHED=`)
that both the workflow and the act harness assert on.

## Rules

Each rule maps a glob `pattern` to a `label` with an optional `priority`
(default `0`). A file may match several rules and receive several labels. The
final set is deduplicated and ordered by descending priority; declaration order
breaks ties. Bare patterns (no `/`, e.g. `*.test.*`) match a file's basename at
any depth.

## Testing (TDD)

Built red/green: each unit was driven by a failing test first (see
`src/*.test.ts`). Run them with:

```bash
bun test src           # fast unit tests
bun test tests/        # end-to-end: every case runs through act
```

The end-to-end suite builds an isolated temp git repo per case, runs
`act push --rm`, appends output to `act-result.txt`, asserts `act` exited 0,
that every job reports "Job succeeded", and that the exact computed label set
matches the known-good value for that fixture.
