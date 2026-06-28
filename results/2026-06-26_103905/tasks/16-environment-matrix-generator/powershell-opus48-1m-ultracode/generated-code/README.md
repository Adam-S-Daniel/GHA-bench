# Environment Matrix Generator (PowerShell)

Generates a GitHub Actions build matrix (`strategy.matrix` JSON) from a
configuration describing OS options, language versions and feature flags.
Supports `include` / `exclude` rules, `max-parallel`, `fail-fast`, and validates
the matrix against a maximum size before emitting it.

## Files

| File | Purpose |
|------|---------|
| `MatrixGenerator.psm1` | Core, side-effect-free logic (cartesian product, include/exclude, validation, JSON shaping). |
| `Invoke-MatrixGenerator.ps1` | CLI wrapper: reads config, expands the matrix, writes JSON, handles exit codes. |
| `MatrixGenerator.Tests.ps1` | Pester unit tests for the module + CLI. |
| `Workflow.Tests.ps1` | Workflow structure tests, actionlint, and the `act` pipeline integration test. |
| `fixtures/*.config.json` | Example configurations / test fixtures. |
| `.github/workflows/environment-matrix-generator.yml` | CI pipeline: generate matrix -> consume it in a fan-out build job. |

## Configuration schema

The configuration mirrors a GitHub Actions `strategy` block, plus a `max-size`
validation knob:

```jsonc
{
  "matrix": {
    "os":   ["ubuntu-latest", "windows-latest"],  // any number of named axes
    "node": [18, 20],
    "exclude": [ { "os": "macos-latest", "node": 18 } ],   // optional
    "include": [ { "coverage": true } ]                    // optional
  },
  "fail-fast": false,      // optional, default true
  "max-parallel": 4,       // optional, omitted from output when unset
  "max-size": 256          // optional, default 256 (GitHub's hard limit)
}
```

Axes are every key under `matrix` except the reserved `include` / `exclude`.
`include` / `exclude` follow GitHub's documented semantics: excludes remove
matching base combinations; includes extend compatible combinations (without
overwriting original axis values) or are appended as new standalone combinations.

## Usage

```powershell
# Print the complete strategy JSON to stdout
./Invoke-MatrixGenerator.ps1 -ConfigPath fixtures/basic.config.json

# Compact JSON + CI-grep-able MATRIX_COUNT / MATRIX_INCLUDE markers
./Invoke-MatrixGenerator.ps1 -ConfigPath fixtures/basic.config.json -Summary -Compress

# In a workflow step: publish matrix/count as job outputs for downstream jobs
./Invoke-MatrixGenerator.ps1 -ConfigPath config.json -GitHubOutput
```

Output (basic fixture):

```json
{"fail-fast":false,"max-parallel":2,"matrix":{"include":[
  {"os":"ubuntu-latest","node":20},{"os":"windows-latest","node":20}]}}
```

The `matrix` object is consumed directly downstream via
`strategy.matrix: ${{ fromJSON(needs.generate-matrix.outputs.matrix) }}`.

On validation failure (oversized matrix, empty matrix, bad config) the CLI prints
a meaningful `ERROR (<id>): ...` message to stderr and exits non-zero.

## Running the tests

```powershell
Invoke-Pester            # runs unit + workflow + act integration tests
```

`Workflow.Tests.ps1` runs the pipeline once through `act push`, writes the full
output to `act-result.txt`, and asserts exact expected values for every fixture
case. It requires `act` + Docker (those tests self-skip if unavailable).
