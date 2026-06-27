# Environment Matrix Generator

Generates a [GitHub Actions `strategy.matrix`](https://docs.github.com/actions/using-jobs/using-a-matrix-for-your-jobs)
build matrix (as JSON) from a small declarative config. Supports
`include`/`exclude` rules, `max-parallel`, `fail-fast`, and validates that the
expanded matrix does not exceed a maximum size.

Built with **TypeScript + Bun**, test-first (red/green TDD).

## Files

| File | Purpose |
| --- | --- |
| `matrix-generator.ts` | Core library: axis expansion, exclude/include rules, size validation, strategy assembly. |
| `cli.ts` | CLI entry point. Reads a config JSON (file arg or stdin), prints the matrix with parseable `MTX_*` markers. |
| `matrix-generator.test.ts` | Unit tests for the core library. |
| `cli.test.ts` | Unit tests for the CLI rendering layer. |
| `workflow-structure.test.ts` | Static checks of the workflow YAML + actionlint. |
| `act-harness.test.ts` | End-to-end: runs the workflow through `act` over every fixture and asserts exact results. |
| `fixtures/*.json` | Example matrix configs (also the act test cases). |
| `.github/workflows/environment-matrix-generator.yml` | CI pipeline that runs the generator. |

## Config schema

```jsonc
{
  "os":       ["ubuntu-latest", "windows-latest"], // axis
  "language": ["18", "20"],                          // axis
  "features": ["minimal", "full"],                   // axis
  "include":  [{ "os": "macos-latest", "language": "22" }],
  "exclude":  [{ "os": "windows-latest", "language": "18" }],
  "maxParallel": 4,        // -> strategy.max-parallel
  "failFast":    false,    // -> strategy.fail-fast (default true)
  "maxSize":     256       // hard cap on expanded combinations (default 256)
}
```

Expansion order matches GitHub Actions: the cartesian product of the axes,
then `exclude` (partial match removal), then `include` (extend matching
combinations, or append as a new combination when it cannot extend any).

## Usage

```bash
bun run cli.ts fixtures/02-exclude.json     # from a file
cat fixtures/02-exclude.json | bun run cli.ts -   # from stdin
```

The CLI prints marker lines for machine parsing plus a pretty strategy block:

```
MTX_COUNT=5
MTX_STRATEGY={"fail-fast":false,"max-parallel":3,"matrix":{...}}
MTX_JSON=[{"os":"ubuntu-latest","language":"18"}, ...]
```

(Markers deliberately avoid the `::name::value` syntax, which GitHub Actions /
`act` would interpret as workflow commands and swallow.)

## Testing

```bash
bun test                       # everything (unit + structure + act e2e)
bun test matrix-generator.test.ts cli.test.ts   # fast unit tests only
```

The act end-to-end suite builds a temp git repo, runs `act push --rm` once
(the workflow loops over all fixtures), writes the full log to
`act-result.txt`, and asserts exact combination counts and JSON content for
every fixture, plus that each job reports `Job succeeded`.
