# Semantic Version Bumper

Reads a semantic version (from a `VERSION` file or `package.json`), inspects a
log of [conventional commits](https://www.conventionalcommits.org/), decides
the next version, writes it back, prepends a grouped changelog entry, and
prints the result. Built test-first (red/green TDD) and wired into a GitHub
Actions pipeline that is exercised end-to-end with [`act`](https://github.com/nektos/act).

## Bump rules

| Commit signal | Bump | Example |
| --- | --- | --- |
| Breaking change (`type!:` header or `BREAKING CHANGE:` footer) | **major** | `2.0.0` |
| `feat:` | **minor** | `1.2.0` |
| `fix:` | **patch** | `1.1.1` |
| only `chore`/`docs`/`ci`/... | **none** (version unchanged) | `1.1.0` |

Precedence is highest-wins: a single breaking change forces a major bump even
if `feat`/`fix` commits are also present.

## Files

| Path | Purpose |
| --- | --- |
| `semver_bumper.py` | The tool: parsing, bump decision, changelog, file I/O, CLI. |
| `tests/test_semver_bumper.py` | TDD unit suite (version math, commit parsing, bump decision, changelog, I/O, CLI). |
| `tests/test_workflow_structure.py` | Static checks on the workflow (triggers, jobs, deps, actionlint). |
| `tests/fixtures/*.log` | Mock conventional-commit logs used as test fixtures. |
| `VERSION` | Current version source (plain text). |
| `package.json` | Demonstrates the alternative `package.json` version source. |
| `CHANGELOG.md` | Changelog; new entries are prepended below the title. |
| `commits.log` | Default commit log the workflow analyzes. |
| `.github/workflows/semantic-version-bumper.yml` | CI/CD pipeline (`bump` job → `verify` job). |
| `run_act_tests.py` | Integration harness: runs the workflow through `act` per case. |
| `act-result.txt` | Captured `act` output for every case (generated artifact). |

## Commit log format

Commits are separated by a line containing exactly `--END--`. The first line of
each block is the conventional-commit header; remaining lines are the body
(scanned for a `BREAKING CHANGE:` footer). The same format is produced from a
real repository with:

```bash
git log --pretty=format:'%B%n--END--' v1.0.0..HEAD > commits.log
```

so the parser handles both fixtures and live git history.

## Usage

```bash
# From a committed commit log (deterministic; used in CI):
python3 semver_bumper.py --version-file VERSION --commits-file commits.log

# Directly from git history (real-world use):
python3 semver_bumper.py --version-file package.json --git-range v1.0.0..HEAD

# Preview without writing any files:
python3 semver_bumper.py --commits-file commits.log --dry-run
```

The tool prints a machine-readable contract on stdout that the workflow parses:

```
PREVIOUS_VERSION=1.1.0
BUMP_TYPE=minor
NEW_VERSION=1.2.0
```

## Testing

```bash
# Unit + workflow-structure tests (fast, no Docker):
python3 -m pytest -q

# Validate the workflow:
actionlint .github/workflows/semantic-version-bumper.yml

# Integration: run the workflow through act for every case and write act-result.txt:
python3 run_act_tests.py
```

`run_act_tests.py` builds an isolated temp git repo per case (patch / minor /
major), runs `act push --rm`, asserts act exited 0, asserts the output contains
the **exact** expected `NEW_VERSION`/`BUMP_TYPE`, and asserts both jobs report
`Job succeeded`. All output is saved to `act-result.txt`.

## TDD approach

The suite was grown in red/green cycles — each block of tests was written and
seen failing before the corresponding code was added:

1. Version string parse/format/arithmetic.
2. Conventional-commit parsing and the bump decision.
3. Changelog generation, version-file/changelog I/O, and the end-to-end CLI.

## Workflow design

- **Triggers:** `push`, `pull_request`, `workflow_dispatch` (with an optional
  `commits_file` input), and a weekly `schedule`.
- **Permissions:** `contents: read` (least privilege — the pipeline computes a
  version, it does not push commits or tags).
- **Jobs:** `bump` computes and exposes the version as job outputs; `verify`
  (`needs: bump`) consumes those outputs and validates the result — exercising
  job dependencies and cross-job data flow.
- **Container-friendly:** uses `actions/checkout@v4` and the system `python3`
  already present in the runner image — no external services or secrets.
