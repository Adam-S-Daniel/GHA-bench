# PR Label Assigner (PowerShell)

Assigns labels to a pull request based on which files it changed, using
configurable glob `path -> label` mapping rules. Supports glob patterns,
multiple labels per file, and priority ordering when several rules contribute
labels to the final set.

## Layout

| Path | Purpose |
|------|---------|
| `src/PRLabelAssigner.psm1` | Core module: glob→regex, path matching, config loading, and the priority-ordered label resolver. Side-effect free and unit-tested. |
| `scripts/Invoke-PRLabelAssigner.ps1` | CLI for a single PR (one changed-files list + a config). |
| `scripts/Invoke-AllFixtures.ps1` | Runs every `fixtures/case-*.txt` through the resolver; the entry point the CI workflow calls. |
| `config/labeler-config.json` | The `path-glob -> labels` rules with priorities. |
| `fixtures/case-*.txt` | Mock "PR changed files" lists, one path per line. |
| `tests/PRLabelAssigner.Tests.ps1` | Fast unit tests (the TDD red/green scaffolding). |
| `tests/Workflow.Tests.ps1` | Static workflow checks (YAML structure, referenced paths, `actionlint`). |
| `tests/Act.Integration.Tests.ps1` | Runs the workflow end-to-end through `act` in Docker and asserts exact labels per case. Writes `act-result.txt`. |
| `.github/workflows/pr-label-assigner.yml` | The CI/CD pipeline. |

## Glob semantics

| Glob | Meaning | Regex |
|------|---------|-------|
| `*`  | any chars except `/` (one path segment) | `[^/]*` |
| `**` | any chars including `/` | `.*` |
| `**/`| zero or more leading directory segments | `(?:.*/)?` |
| `?`  | exactly one char except `/` | `[^/]` |

Matching is **case-sensitive** so `*.test.*` does not also match `Foo.Tests.ps1`.

## Label resolution

Every changed file is tested against every rule. Each matching rule contributes
all its labels. A label keeps the **highest** priority of any rule that produced
it. The final, de-duplicated set is ordered by priority **descending**, then by
label name **ascending** (a deterministic tie-break).

## Running

```pwsh
# All tests (unit + workflow structure + act integration)
Invoke-Pester -Path ./tests

# Resolve labels for one mock PR
./scripts/Invoke-PRLabelAssigner.ps1 -ChangedFilesPath fixtures/case-mixed.txt -ConfigPath config/labeler-config.json
```

## How testing maps onto `act`

Every functional case is exercised through the GitHub Actions workflow via `act`.
Because each `act push` is slow (and the task caps invocations at three), the
`assign-labels` job processes **all** fixtures in a single run, emitting one
`RESULT case=<name> labels=<...>` line per case. `tests/Act.Integration.Tests.ps1`
runs `act` once in an isolated temp git repo, then asserts each case's exact label
set from that run's output and saves everything to `act-result.txt`.
