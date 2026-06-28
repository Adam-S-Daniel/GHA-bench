# Environment Matrix Generator (PowerShell)

Generates a GitHub Actions `strategy.matrix` from a declarative JSON config:
matrix dimensions (OS, language versions, feature flags), `include`/`exclude`
rules, `max-parallel`, `fail-fast`, and a `max-size` guard. Validates that the
expanded matrix does not exceed the maximum allowed size and outputs the
complete matrix JSON.

## Layout

| Path | Purpose |
|------|---------|
| `src/BuildMatrix.psm1` | Core logic as pure, testable functions (`Get-MatrixCombination`, `New-BuildMatrix`, `Invoke-MatrixGenerator`). |
| `src/Generate-Matrix.ps1` | CLI wrapper: `-ConfigPath <file>` → matrix JSON on stdout. |
| `fixtures/*.json` | Example/test configs (basic, include/exclude, oversize). |
| `tests/BuildMatrix.Tests.ps1` | Pester unit tests (written red→green TDD). |
| `tests/Workflow.Tests.ps1` | Workflow structure tests + `act` integration harness. |
| `.github/workflows/environment-matrix-generator.yml` | CI pipeline running the generator over every fixture. |

## Config format

```jsonc
{
  "matrix": {                       // dimensions -> arrays of values
    "os":   ["ubuntu-latest", "windows-latest"],
    "node": ["18", "20"]
  },
  "include":      [ { "os": "ubuntu-latest", "node": "20", "coverage": true } ],
  "exclude":      [ { "os": "windows-latest", "node": "18" } ],
  "fail-fast":    false,            // default: true
  "max-parallel": 3,                // omitted from output when unset
  "max-size":     20                // validation guard (optional)
}
```

Output:

```json
{
  "strategy": {
    "fail-fast": false,
    "max-parallel": 3,
    "matrix": { "os": [...], "node": [...], "include": [...], "exclude": [...] }
  },
  "jobCount": 6
}
```

Include/exclude follow GitHub Actions' documented algorithm: excludes drop
matching combinations (unspecified keys act as wildcards); includes merge into
combinations that don't overwrite an original matrix value, otherwise become a
new standalone combination.

## Running

```bash
# CLI
pwsh ./src/Generate-Matrix.ps1 -ConfigPath fixtures/include-exclude.json

# All tests (unit + workflow structure + act pipeline)
pwsh -c 'Invoke-Pester ./tests'
```

The `act` integration suite builds an isolated temp git repo, runs the workflow
with `act push --rm --pull=false`, writes the full log to `act-result.txt`, and
asserts exact per-fixture values plus `Job succeeded`.
