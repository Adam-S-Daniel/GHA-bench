# PR Label Assigner (PowerShell)

Given a list of changed file paths (simulating a PR's changed files), this tool
applies labels based on configurable **path-to-label glob rules**. It supports
glob patterns, multiple labels per file, and priority ordering when rules
conflict, and prints the final label set.

Built test-first (red/green TDD) with [Pester](https://pester.dev), and wired
into a GitHub Actions workflow that is exercised end-to-end with
[`act`](https://github.com/nektos/act).

## Layout

| Path | Purpose |
|------|---------|
| `src/PrLabelAssigner.psm1` | Core module: glob engine + resolver + IO + formatter |
| `Invoke-PrLabelAssigner.ps1` | CLI entry point used by the workflow |
| `fixtures/label-rules.json` | The configurable path-to-label rules |
| `fixtures/cases/*.txt` | Per-test-case changed-file manifests (the "mock file list") |
| `fixtures/changed-files.txt` | Default manifest the workflow reads |
| `tests/PrLabelAssigner.Tests.ps1` | Unit tests (run locally **and** inside the workflow) |
| `tests/Workflow.Tests.ps1` | Workflow structure / actionlint tests (local) |
| `.github/workflows/pr-label-assigner.yml` | The CI pipeline |
| `Run-ActHarness.ps1` | Runs every case through the workflow via `act`, asserts exact output |

## Rule model

Each rule in `label-rules.json`:

```json
{ "pattern": "src/api/**", "labels": ["api", "backend"], "priority": 30, "stopOnMatch": false }
```

- **pattern** — a glob (see semantics below).
- **labels** — one or more labels applied when a file matches.
- **priority** — higher wins; determines final label ordering (default `0`).
- **stopOnMatch** — if `true`, the rule is *exclusive*: once it matches a file,
  no lower-priority rule applies to that file. This is the conflict-resolution
  mechanism (e.g. a `*.generated.*` file gets *only* `generated`).

### Glob semantics (documented & intentional)

| Token | Meaning |
|-------|---------|
| `**/` | zero or more leading directory segments |
| `**`  | any characters, including `/` |
| `*`   | any characters except `/` |
| `?`   | exactly one character except `/` |

A pattern **without** a `/` is matched against the file's **basename** (so
`*.test.*` matches `src/components/Button.test.tsx`); a pattern **with** a `/`
is matched against the full path. Matching is case-insensitive.

### Resolution & output

Rules are evaluated highest-priority-first per file; labels are unioned and
de-duplicated. The final set is ordered by descending priority (ties broken
alphabetically) and printed as machine-parseable markers:

```
PR_LABELS=tests,dependencies,api,backend,source,documentation
PR_LABEL_COUNT=6
```

## Running

```bash
# Unit + structure tests
pwsh -c "Invoke-Pester -Path ./tests"

# The tool directly
pwsh -File ./Invoke-PrLabelAssigner.ps1 -ChangedFilesPath fixtures/cases/01-mixed.txt

# Full pipeline through act (writes act-result.txt)
pwsh -File ./Run-ActHarness.ps1
```
