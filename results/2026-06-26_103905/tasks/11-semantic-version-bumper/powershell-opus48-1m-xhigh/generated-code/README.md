# Semantic Version Bumper (PowerShell)

Reads a semantic version from a `VERSION` file (or `package.json`), inspects
[Conventional Commit](https://www.conventionalcommits.org) messages to decide
the next version, writes the new version back, prepends a
[Keep a Changelog](https://keepachangelog.com) entry, and prints the result.

```
breaking change  -> major   (X+1.0.0)
feat             -> minor   (X.Y+1.0)
fix              -> patch   (X.Y.Z+1)
anything else    -> no bump
```

The highest-precedence change across all commits wins.

## Layout

| Path | Purpose |
| --- | --- |
| `SemanticVersionBumper.psm1` | Pure, unit-tested library functions |
| `Invoke-VersionBump.ps1` | CLI entry point used by the workflow |
| `tests/SemanticVersionBumper.Tests.ps1` | Pester unit + end-to-end tests |
| `fixtures/<case>/` | Mock commit logs + version files + `expected.json` |
| `.github/workflows/semantic-version-bumper.yml` | CI/CD pipeline |
| `harness/Run-ActTests.ps1` | Runs the workflow through `act` per fixture |
| `harness/WorkflowStructure.Tests.ps1` | Static checks of the workflow YAML |
| `act-result.txt` | Captured `act` output for every fixture (generated) |

## Conventional commit input format

`commits.txt` holds the commit log. Two layouts are accepted:

* **one commit per line** (matches `git log --format=%s`), or
* **multi-line records** separated by a line containing only `---`, which lets
  a commit carry a body and a `BREAKING CHANGE:` footer.

Breaking changes are detected by a `!` after the type/scope (e.g. `feat!:`) or a
`BREAKING CHANGE:` footer.

## Running the tests

This project was built red/green with TDD. All tests run with Pester:

```pwsh
Invoke-Pester -Path .        # unit + end-to-end + workflow-structure tests
```

The full pipeline is exercised through real GitHub Actions runs via `act`:

```pwsh
./harness/Run-ActTests.ps1   # one `act push` per fixture -> act-result.txt
```

Each `act` run is asserted against the known-good values in the fixture's
`expected.json` (exact new version, bump type, previous version, changelog
content) and every job is checked for `Job succeeded`.

## Running the bumper directly

```pwsh
./Invoke-VersionBump.ps1 -VersionFile VERSION -CommitsFile commits.txt -ChangelogFile CHANGELOG.md
```

It prints `PREVIOUS_VERSION=`, `BUMP_TYPE=`, `NEW_VERSION=` and `CHANGED=` and,
when running under GitHub Actions, also writes step outputs
(`new-version`, `previous-version`, `bump-type`, `changed`) and a step summary.
Pass `-NoWrite` for a dry run.
