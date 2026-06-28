# Environment Matrix Generator (PowerShell)

Generates a GitHub Actions `strategy.matrix` from a declarative JSON
configuration. Supports cartesian expansion of arbitrary dimensions (OS,
language versions, feature flags), GitHub-accurate `include`/`exclude` rules,
`max-parallel`, `fail-fast`, and a `max-size` guard rail. Built test-first with
Pester and exercised end-to-end through a real GitHub Actions workflow via
`act`.

## Files

| File | Purpose |
| --- | --- |
| `MatrixGenerator.psm1` | Core module: `New-BuildMatrix` plus helpers (cartesian expansion, include/exclude resolution, JSON serialization). |
| `Generate-Matrix.ps1` | CLI wrapper: reads a config file, prints a summary + machine-parseable lines, and writes GitHub Actions step outputs. |
| `MatrixGenerator.Tests.ps1` | Pester unit tests (TDD red/green). Also run *inside* CI by the workflow. |
| `Workflow.Tests.ps1` | Pester structure tests: parse the YAML, assert triggers/jobs/steps, verify referenced files exist, assert `actionlint` exits 0. |
| `Run-ActTests.ps1` | Integration harness: per test case, build an isolated git repo + fixture, run `act push`, save output to `act-result.txt`, and assert exact known-good values. |
| `.github/workflows/environment-matrix-generator.yml` | The CI/CD pipeline (generate → build → summary). |
| `fixtures/*.json` | Test-case configurations. |
| `matrix-config.json` | Default config read by the workflow. |

## Configuration format

Mirrors a real GitHub `strategy` block, plus a `max-size` guard:

```json
{
  "matrix": {
    "os":   ["ubuntu-latest", "windows-latest"],
    "node": ["18", "20"],
    "include": [ { "os": "ubuntu-latest", "node": "20", "experimental": true } ],
    "exclude": [ { "os": "windows-latest", "node": "18" } ]
  },
  "max-parallel": 2,
  "fail-fast": false,
  "max-size": 50
}
```

The resolved output is shaped for `fromJson()` consumption — each fully resolved
combination becomes one matrix job:

```json
{ "matrix": { "include": [ { "os": "ubuntu-latest", "node": "18" }, ... ] },
  "size": 3, "max-parallel": 2, "fail-fast": false }
```

`include`/`exclude` follow GitHub's documented algorithm (verified against the
canonical fruit/animal example in the unit tests).

## Running

```bash
# Unit + structure tests (local, fast)
pwsh -c "Invoke-Pester -Path ./MatrixGenerator.Tests.ps1,./Workflow.Tests.ps1"

# Lint the workflow
actionlint .github/workflows/environment-matrix-generator.yml

# Full pipeline through act (one act run per fixture; output -> act-result.txt)
pwsh -File ./Run-ActTests.ps1
```
