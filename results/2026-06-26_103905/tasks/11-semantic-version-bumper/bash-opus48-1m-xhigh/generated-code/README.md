# Semantic Version Bumper

A small Bash tool that reads the current semantic version (from a plain `VERSION`
file **or** a `package.json`), inspects a list of [Conventional Commit][cc]
messages, computes the next version, updates the version file, prepends a
changelog entry, and prints the new version.

## Bump rules

| Commit kind | Example | Bump | `1.4.2` becomes |
| ----------- | ------- | ---- | --------------- |
| Breaking    | `feat!: ...`, `fix(x)!: ...`, or a `BREAKING CHANGE:` line | **major** | `2.0.0` |
| Feature     | `feat: ...` / `feat(scope): ...` | **minor** | `1.5.0` |
| Fix         | `fix: ...` / `fix(scope): ...`   | **patch** | `1.4.3` |
| Other       | `chore:`, `docs:`, `refactor:`, ... | none | `1.4.2` (unchanged) |

Precedence is **highest-wins**: `major > minor > patch > none`.

## Usage

```bash
./semver-bump.sh --commits commits.txt [options]
```

| Option | Default | Meaning |
| ------ | ------- | ------- |
| `--version-file <file>` | `VERSION` | Version source (plain text or `package.json`) |
| `--commits <file>` | *(required)* | One Conventional-Commit subject per line |
| `--changelog <file>` | `CHANGELOG.md` | Changelog file to prepend the entry to |
| `--date <YYYY-MM-DD>` | today | Date used in the changelog heading |
| `--dry-run` | off | Compute only; do not modify files |
| `-h`, `--help` | | Show help |

The **new version** is printed to `STDOUT` (everything else goes to `STDERR`), so
it composes cleanly in pipelines:

```bash
NEW=$(./semver-bump.sh --version-file VERSION --commits commits.txt)
```

When `$GITHUB_OUTPUT` is set the script also writes `old_version`, `new_version`
and `bump` as GitHub Actions step outputs.

### Producing a commit log from real git history

The script reads commits from a *file* so its behaviour is deterministic and
testable. In a real repo you can generate that file from git:

```bash
git log "$(git describe --tags --abbrev=0)..HEAD" --format=%s > commits.txt
```

## Files

| Path | Purpose |
| ---- | ------- |
| `semver-bump.sh` | The bumper (pure Bash; uses `jq` for `package.json`) |
| `fixtures/<scenario>/` | Mock commit logs + version files used as test fixtures |
| `.github/workflows/semantic-version-bumper.yml` | CI pipeline running the bumper |
| `test/semantic-version-bumper.bats` | bats test suite |
| `test/wf_check.py` | Workflow-structure validator used by the tests |
| `act-result.txt` | Captured output of the `act` workflow run (test artifact) |

## Testing

All behaviour is exercised **through the GitHub Actions workflow** using
[`act`][act]. The bats suite:

1. statically validates the script (`bash -n`, `shellcheck`);
2. validates the workflow structure (triggers / jobs / steps / references) and
   that it passes `actionlint`;
3. spins up a throw-away git repo with the project + fixtures, runs the workflow
   once via `act push --rm`, saves the output to `act-result.txt`, and asserts on
   the **exact** expected version for every fixture scenario plus that every job
   reports `Job succeeded`.

```bash
bats test/semantic-version-bumper.bats
```

> During local iteration, set `SEMVER_REUSE_ACT=1` to reuse an existing
> `act-result.txt` instead of re-running `act`.

[cc]: https://www.conventionalcommits.org/
[act]: https://github.com/nektos/act
