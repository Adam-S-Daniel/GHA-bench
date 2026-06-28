# PR Label Assigner (PowerShell)

Apply labels to a pull request based on its changed files, using a configurable
list of glob-pattern → label rules. Built test-first with Pester and wired into
a GitHub Actions pipeline that is exercised end-to-end with [`act`](https://github.com/nektos/act).

## What it does

Given a list of changed file paths and a rule config, it computes the final,
de-duplicated set of labels. Features:

- **Glob patterns** — `*`, `?`, `**`, plus gitignore-style basename matching
  (a slash-free pattern like `*.test.*` matches the basename at any depth).
- **Multiple labels per file** — a rule may emit several labels, and several
  rules may match one file.
- **Priority ordering** — higher-priority rules order the output (descending
  priority, then alphabetically).
- **Conflict resolution** — a matching rule with `"stop": true` short-circuits
  the remaining (lower-priority) rules for that file, so the higher-priority
  rule wins.

## Files

| File | Purpose |
|------|---------|
| `PrLabelAssigner.psm1` | Core module: glob matching, rule loading, resolution. |
| `Invoke-PrLabelAssigner.ps1` | CLI entry point used by the workflow; prints `LABELS=...`. |
| `config/labels.json` | The path-glob → label rules (priority, stop). |
| `fixtures/changed-files.txt` | Mock PR file list (one path per line). |
| `PrLabelAssigner.Tests.ps1` | Pester unit tests (TDD). |
| `Workflow.Tests.ps1` | Workflow structure tests + `act` end-to-end harness. |
| `.github/workflows/pr-label-assigner.yml` | The CI pipeline. |
| `act-result.txt` | Captured `act` output for every test case (generated). |

## Rule config format

```jsonc
{
  "rules": [
    { "pattern": "docs/**",      "labels": ["documentation"],  "priority": 10 },
    { "pattern": "src/api/**",   "labels": ["api", "backend"], "priority": 30 },
    { "pattern": "*.test.*",     "labels": ["tests"],          "priority": 40 },
    { "pattern": "package.json", "labels": ["dependencies"],   "priority": 50, "stop": true }
  ]
}
```

`priority` defaults to `0`; `stop` defaults to `false`.

## Run it locally

```powershell
# Resolve labels for a changed-file list
pwsh ./Invoke-PrLabelAssigner.ps1 -ChangedFilesPath fixtures/changed-files.txt -ConfigPath config/labels.json
# -> LABELS=tests,source,documentation

# Unit tests
Invoke-Pester ./PrLabelAssigner.Tests.ps1

# Workflow structure tests only (no Docker)
Invoke-Pester ./Workflow.Tests.ps1 -ExcludeTagFilter act

# Full pipeline tests via act (requires Docker + act)
Invoke-Pester ./Workflow.Tests.ps1
```

## CI pipeline

`pr-label-assigner.yml` runs two jobs on `push` / `pull_request` /
`workflow_dispatch` / `schedule`:

1. **test** — runs the Pester unit tests.
2. **assign-labels** — (`needs: test`) resolves and prints the label set,
   exposing it as a step output and a job summary.

The `Workflow.Tests.ps1` harness builds a throwaway git repo per test case,
runs `act push --rm`, and asserts the exact `LABELS=` output and that every job
succeeded — saving everything to `act-result.txt`.
