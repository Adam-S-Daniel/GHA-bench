# PR Label Assigner

Assigns labels to a PR based on its changed file paths, driven by a
configurable rules file. Built test-first (red/green TDD) with bats-core.

## Files

| Path | Purpose |
| --- | --- |
| `label-assigner.sh` | The labeler: changed-file list + rules → final label set |
| `fixtures/labels.conf` | Default rules (mocked PR config) |
| `fixtures/changed_files.txt` | Default changed-file list (mocked PR diff) |
| `tests/label_assigner.bats` | Unit tests (run inside the workflow via act) |
| `tests/workflow_structure.bats` | Workflow structure tests (run on the host) |
| `.github/workflows/pr-label-assigner.yml` | CI pipeline: bats suite, then the labeler |
| `run-act-tests.sh` | End-to-end harness: every case runs through `act push` |
| `act-result.txt` | Captured act output for all cases (generated) |

## Rules format

One rule per line; `#` comments and blank lines are ignored:

```
priority|glob-pattern|label1[,label2,...][|stop]
```

- **priority** — integer; lower number = higher priority (evaluated first).
- **glob-pattern** — `**` crosses directories, `*`/`?` do not; a pattern
  without `/` matches the basename (gitignore-style), e.g. `*.test.*`.
- **labels** — comma-separated labels applied when the pattern matches.
- **stop** — optional conflict resolver: when a `stop` rule matches a file,
  lower-priority rules are skipped for that file.

By default all matching rules contribute labels; the output is the sorted,
deduplicated union across all changed files, one label per line.

## Usage

```sh
./label-assigner.sh -r fixtures/labels.conf -f fixtures/changed_files.txt
git diff --name-only origin/main | ./label-assigner.sh -r fixtures/labels.conf
```

Exit codes: `0` success (even when nothing matched — a notice goes to
stderr), `2` usage/config error (missing files, malformed rules).

## Testing

```sh
bats tests/                # unit + workflow structure tests
./run-act-tests.sh         # all cases end-to-end through act → act-result.txt
actionlint .github/workflows/pr-label-assigner.yml
shellcheck label-assigner.sh run-act-tests.sh
```
