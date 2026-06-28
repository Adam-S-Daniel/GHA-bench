# PR Label Assigner (PowerShell)

Applies labels to a pull request by matching its **changed file paths** against a
configurable set of **glob → label** rules. Supports glob patterns, multiple
labels per file, and priority ordering / exclusive groups when rules conflict.

## Layout

| Path | Purpose |
|------|---------|
| `src/LabelAssigner.psm1` | Core module: glob matching + rule resolution |
| `Assign-Labels.ps1` | CLI wrapper used by CI; prints `LABELS=` / `LABEL_COUNT=` |
| `rules.json` | Default path-to-label mapping rules |
| `fixtures/changed-files.txt` | Default mocked PR changed-file list |
| `tests/LabelAssigner.Tests.ps1` | Pester unit tests (built via red/green TDD) |
| `tests/Workflow.Tests.ps1` | Workflow structure tests + `act` end-to-end harness |
| `.github/workflows/pr-label-assigner.yml` | CI pipeline that runs the script |
| `act-result.txt` | Captured `act` output (one delimited block per test case) |

## Rule model

Each rule in `rules.json`:

```json
{ "pattern": "src/api/**", "labels": ["api", "backend"], "priority": 40, "exclusiveGroup": "area" }
```

* **pattern** – glob. `**` crosses `/`, `*` and `?` do not; a slash-less pattern
  (e.g. `*.test.*`) matches the file **basename** at any depth.
* **labels** – one or more labels contributed when the pattern matches.
* **priority** *(default 0)* – higher wins; used to order the final label set.
* **exclusiveGroup** *(optional)* – within one group, only the highest-priority
  matching rule's labels are kept. This is how conflicts are arbitrated
  (e.g. `src/api/**` vs `src/**` both in group `area` → API wins).

The final label set is the de-duplicated union across all changed files, ordered
by descending priority then alphabetically.

## Running the tests

```pwsh
# Fast: unit tests + workflow structure checks
Invoke-Pester -Path tests/ -ExcludeTag act

# End-to-end: every case through the real workflow via nektos/act
Invoke-Pester -Path tests/Workflow.Tests.ps1 -Tag act
```

The `act` harness builds an isolated temp git repo per test case, swaps in that
case's `fixtures/changed-files.txt`, runs `act push --rm --pull=false`, appends
the output to `act-result.txt`, and asserts on the **exact** labels produced.
