# Environment Matrix Generator (PowerShell)

Generates a GitHub Actions `strategy.matrix` (as JSON) from a configuration that
describes OS options, language versions and feature flags. Supports `include` /
`exclude` rules, `max-parallel` and `fail-fast` configuration, and validates that
the matrix does not exceed a maximum size.

## Files

| File | Purpose |
| --- | --- |
| `BuildMatrix.psm1` | Pure matrix-generation logic (no I/O). Exposes `Get-CartesianProduct`, `Get-BuildMatrix`, `Import-MatrixConfig`. |
| `Invoke-MatrixGenerator.ps1` | CLI wrapper: reads a config file, prints the matrix JSON, and (optionally) publishes it to `$GITHUB_OUTPUT`. |
| `fixtures/*.json` | Input configurations / test fixtures (see below). |
| `BuildMatrix.Tests.ps1` | Fast Pester unit tests (red/green TDD) for the logic. |
| `Workflow.Tests.ps1` | Acceptance tests that drive **every** case through the real pipeline with `act`, and write `act-result.txt`. |
| `WorkflowStructure.Tests.ps1` | Static checks: `actionlint`, parsed-YAML structure, referenced files exist. |
| `.github/workflows/environment-matrix-generator.yml` | The CI/CD pipeline. |

## Configuration schema

```jsonc
{
  "matrix": {                       // axes: OS / versions / feature flags
    "os":   ["ubuntu-latest", "windows-latest"],
    "node": ["18", "20"]
  },
  "exclude": [                      // drop combinations (partial match = wildcard)
    { "os": "windows-latest", "node": "18" }
  ],
  "include": [                      // extend / append combinations (GitHub semantics)
    { "os": "ubuntu-latest", "node": "20", "experimental": true }
  ],
  "max-parallel": 2,                // optional
  "fail-fast": false,               // optional, default true
  "max-size": 256                   // optional, default 256 (GitHub's hard cap)
}
```

The `include` / `exclude` algorithm matches GitHub's documented matrix-expansion
behaviour exactly (`fixtures/b-include.json` is the official docs example):

* the cartesian product of the axes is built (first axis varies slowest);
* `exclude` entries remove every combination they partially match;
* each `include` entry is merged into every **original** combination it does not
  conflict with (original axis values are never overwritten; added keys may be).
  An include that matches no original combination is appended as a new job.

## Usage

```pwsh
./Invoke-MatrixGenerator.ps1 -ConfigPath fixtures/a-basic.json
```

The script prints the full matrix JSON between `===MATRIX-JSON-BEGIN===` /
`===MATRIX-JSON-END===` markers. With `-GitHubOutput` it also writes
`matrix=<compact json>` to `$GITHUB_OUTPUT` so a downstream job can fan out:

```yaml
strategy:
  matrix: ${{ fromJSON(needs.generate.outputs.matrix) }}
```

## Fixtures

| Fixture | Exercises | Expected |
| --- | --- | --- |
| `a-basic`    | axes + exclude + max-parallel + fail-fast | 3 jobs (windows/18 excluded) |
| `b-include`  | full GitHub include algorithm (docs example) | 6 jobs |
| `c-oversize` | `max-size` validation | rejected: limit 10, actual 27 |
| `d-features` | 3 axes incl. feature flag + include-extend + partial exclude | 3 jobs, modern flagged experimental |
| `e-partial`  | partial exclude acts as a wildcard | 6 jobs (no macos) |

## Testing

```pwsh
Invoke-Pester                     # runs all three suites
```

* **TDD / logic** — `BuildMatrix.Tests.ps1` (instant).
* **Acceptance** — `Workflow.Tests.ps1` runs the workflow once via `act push`,
  feeding all fixtures through the pipeline, and asserts on exact expected values
  (plus the live downstream build jobs). It writes `act-result.txt`.
* **Structure** — `WorkflowStructure.Tests.ps1` validates the workflow statically.
