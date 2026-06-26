# PR Label Assigner (PowerShell)

Assigns labels to a PR's changed files using configurable glob → label rules,
with multiple labels per file and priority ordering when rules conflict.

## Layout

| Path | Purpose |
|------|---------|
| `src/PRLabelAssigner.psm1` | Core module: glob→regex, matching, label resolution, rule loading |
| `src/Invoke-PRLabelAssigner.ps1` | CLI entrypoint used by CI; prints `LABELS:` / `LABEL_COUNT:` |
| `tests/PRLabelAssigner.Tests.ps1` | Pester unit + workflow-structure tests |
| `tests/Invoke-ActHarness.ps1` | End-to-end harness: runs every case through the workflow via `act` |
| `fixtures/rules.json` | Default path→label rules |
| `fixtures/changed-files.txt` | Default changed-file list (overwritten per act case) |
| `.github/workflows/pr-label-assigner.yml` | CI workflow (push / pull_request / schedule / dispatch) |

## Rule semantics

Each rule is `{ "pattern", "label", "priority" }`. Globs are gitignore-flavoured:

- `**` matches across directories; `*` stays within one path segment; `?` is one char.
- A pattern with **no `/`** matches the file's basename anywhere (e.g. `*.test.*`).
- Matching is case-insensitive.

The final label set is the de-duplicated union across all files, ordered by
**ascending priority** (lower = more important), ties broken alphabetically.

## Running

```pwsh
# Unit + structure tests
Invoke-Pester -Path ./tests

# Direct CLI
./src/Invoke-PRLabelAssigner.ps1 -RulesPath ./fixtures/rules.json -ChangedFilesPath ./fixtures/changed-files.txt

# Full end-to-end through GitHub Actions (act) — writes act-result.txt
pwsh -File ./tests/Invoke-ActHarness.ps1
```

## TDD

Built red→green: `tests/PRLabelAssigner.Tests.ps1` was written first and failed,
then the module was implemented to satisfy it. The act harness asserts exact
expected `LABELS`/`LABEL_COUNT` values per fixture and that every job succeeds.
