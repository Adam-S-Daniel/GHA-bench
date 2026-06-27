# PR Label Assigner (PowerShell)

Assigns labels to a pull request based on its changed files, using a
configurable set of glob-pattern → label rules. Built with red/green TDD and
Pester, and wired into a GitHub Actions pipeline that is exercised end-to-end
with [`act`](https://github.com/nektos/act).

## What it does

Given a list of changed file paths and a rules config, it computes the final,
de-duplicated label set:

- **Glob patterns** — `**` (matches across `/`), `*` (within a path segment),
  `?` (single char), `.` is literal. Patterns *without* a `/` match against the
  file **basename** (so `*.test.*` matches `src/api/users.test.js`); patterns
  *with* a `/` match the **full path** (so `src/api/**` matches `src/api/...`).
- **Multiple labels per file** — a single rule may carry several labels, and a
  file may match several rules; all matching labels accumulate.
- **Priority ordering** — each rule has a priority; the final set is ordered by
  descending priority, then by name, so the most significant labels come first.
- **Conflict resolution** — `-FirstMatchWins` keeps only the highest-priority
  matching rule per file (exclusive labelling).

## Files

| File | Purpose |
|------|---------|
| `PRLabelAssigner.psm1` | Core module: glob→regex, path matching, rule validation, label computation, JSON config loading. |
| `Invoke-LabelAssigner.ps1` | CLI entry point used by CI: reads the changed-file list + rules, prints a delimited label block, writes `$GITHUB_OUTPUT`. |
| `config/label-rules.json` | Default path→label rules. |
| `fixtures/changed-files.txt` | Default mock list of changed files. |
| `.github/workflows/pr-label-assigner.yml` | CI workflow (test job + assign-labels job). |
| `tests/PRLabelAssigner.Tests.ps1` | Unit tests (TDD). |
| `tests/Workflow.Tests.ps1` | Workflow-structure + actionlint tests. |
| `tests/Act.Tests.ps1` | End-to-end tests that run the pipeline through `act`. |
| `act-result.txt` | Captured `act` output for every integration case. |

## Running the tests

```powershell
# Unit + workflow-structure tests (fast):
Invoke-Pester -Path ./tests/PRLabelAssigner.Tests.ps1,./tests/Workflow.Tests.ps1

# Full end-to-end through GitHub Actions via act (slower; runs `act push`):
Invoke-Pester -Path ./tests/Act.Tests.ps1

# Everything:
Invoke-Pester -Path ./tests
```

## Running the script directly

```powershell
./Invoke-LabelAssigner.ps1 -ChangedFilesPath fixtures/changed-files.txt -RulesPath config/label-rules.json
```

Inputs resolve from parameters → environment variables
(`CHANGED_FILES_FILE`, `LABEL_RULES_FILE`, `FIRST_MATCH_WINS`) → defaults, so the
same script works locally and in CI.
