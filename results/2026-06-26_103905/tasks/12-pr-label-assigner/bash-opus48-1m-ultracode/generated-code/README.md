# PR Label Assigner

A small, dependency-free Bash tool that assigns labels to a pull request based
on the set of files it changes, using configurable glob-pattern rules. Built
test-first with [bats-core](https://github.com/bats-core/bats-core) and wired
into a GitHub Actions workflow that is exercised end-to-end with
[`act`](https://github.com/nektos/act).

## What it does

Given a list of changed paths and a rules file, it computes the final set of
labels:

* **Glob patterns** — `*` stays within a path segment, `**` crosses `/`, `?` is
  a single non-`/` char, and a pattern with no `/` matches the file's basename
  (so `*.test.*` matches `src/components/Button.test.tsx`).
* **Multiple labels per file** — one rule may list several labels, and several
  rules may match one file; the results are unioned and de-duplicated.
* **Priority ordering / conflict resolution** — every rule carries an integer
  priority. Output is sorted by priority (highest first), ties broken
  alphabetically. When two rules assign the same label, it keeps its highest
  priority.
* **Exclusions** — a pattern beginning with `!` removes the listed labels from
  matching files (`*` suppresses every label for that file).

## Usage

```bash
# From a file list (one path per line):
./pr-label-assigner.sh --rules config/label-rules.conf --files changed.txt

# From positional arguments:
./pr-label-assigner.sh --rules config/label-rules.conf src/api/users.js docs/x.md

# From stdin, as CSV:
git diff --name-only origin/main | ./pr-label-assigner.sh --rules config/label-rules.conf --format csv
```

Exit codes: `0` success (empty label set is still success), `2` usage / missing
input file, `3` malformed rules file.

## Rules format

```
<glob-pattern> | <comma-separated-labels> | <priority>
```

`#` starts a comment, blank lines are ignored, whitespace around fields is
trimmed, and the priority field defaults to `0`. See
[`config/label-rules.conf`](config/label-rules.conf).

## Layout

| Path | Purpose |
|------|---------|
| `pr-label-assigner.sh` | the tool |
| `config/label-rules.conf` | path→label rules |
| `tests/fixtures/*.files` | mock changed-file lists per test case |
| `tests/pr-label-assigner.bats` | unit suite (red/green TDD) |
| `tests/act-integration.bats` | drives the workflow through `act`, asserts exact labels |
| `tests/run-act.sh` | builds an isolated repo and runs `act push --rm` |
| `tests/check-workflow.py` | static workflow-structure validation |
| `.github/workflows/pr-label-assigner.yml` | CI pipeline (matrix over every fixture) |

## Running the tests

```bash
# Unit tests (fast, no Docker):
bats tests/pr-label-assigner.bats

# Full suite incl. the act pipeline (reuses act-result.txt if already good;
# FORCE_ACT=1 forces a fresh act run):
bats tests/
```

The integration suite writes the full act log plus a per-case parsed summary to
`act-result.txt`, then asserts that act exited 0, every job succeeded, and each
fixture produced its exact known-good label set.
