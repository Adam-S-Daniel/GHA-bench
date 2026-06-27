# Environment Matrix Generator (PowerShell)

Generates a GitHub Actions `strategy.matrix` from a declarative config describing
OS options, language versions and feature flags. Supports `include`/`exclude`
rules, `max-parallel`, `fail-fast`, and validates the expanded matrix does not
exceed a maximum size.

## Files

| File | Purpose |
|------|---------|
| `BuildMatrix.psm1` | Core module: cartesian product, exclude, include, validation. |
| `New-BuildMatrix.ps1` | CLI wrapper: reads a JSON config (file / `-ConfigJson` / stdin), prints matrix JSON. |
| `BuildMatrix.Tests.ps1` | Pester **unit** tests (TDD red/green). |
| `WorkflowStructure.Tests.ps1` | Pester tests for the workflow YAML structure + actionlint. |
| `Workflow.Tests.ps1` | Pester **integration** harness — every case runs through the workflow via `act`. |
| `fixtures/*.json` | Test-case configs with known-good expected outputs. |
| `.github/workflows/environment-matrix-generator.yml` | The CI/CD pipeline. |

## Config schema

```json
{
  "matrix": {
    "os":   ["ubuntu-latest", "windows-latest"],
    "node": ["18", "20"],
    "include": [ { "os": "ubuntu-latest", "node": "20", "experimental": true } ],
    "exclude": [ { "os": "windows-latest", "node": "18" } ]
  },
  "failFast": true,
  "maxParallel": 4,
  "maxSize": 256
}
```

Any key in `matrix` other than `include`/`exclude` is a build dimension.
Expansion follows GitHub's real semantics: **cartesian product → exclude → include**
(includes merge into matching original combinations or append as new ones).

## Output

```json
{
  "fail-fast": true,
  "max-parallel": 4,
  "matrix":   { ...dimensions, include, exclude },
  "job-count": 4,
  "jobs":     [ { ...expanded combination... } ]
}
```

`job-count`/`jobs` are the fully expanded job list used to enforce `maxSize`.
An oversized matrix or invalid config fails with a meaningful message and a
non-zero exit code.

## Running

```bash
# Generate from a fixture
pwsh ./New-BuildMatrix.ps1 -ConfigPath ./fixtures/basic.json

# All tests (unit + structure + act integration)
pwsh -c "Invoke-Pester -Path . -Output Detailed"
```

## CI/CD pipeline

`.github/workflows/environment-matrix-generator.yml` runs three dependent jobs:

1. **test** — runs the Pester unit suite.
2. **generate-matrix** — verifies every fixture and exposes the chosen fixture's
   matrix dimensions as a job output (the canonical dynamic-matrix pattern).
3. **build** — consumes that output via `fromJson()` and fans out one job per
   combination, proving the generated matrix actually drives downstream jobs.

The integration harness (`Workflow.Tests.ps1`) runs the whole pipeline through
`act`, saves output to `act-result.txt`, and asserts exact expected values per
fixture plus that every job reports "Job succeeded".
