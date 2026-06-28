# PR Label Assigner

Given a list of changed file paths (a PR's touched files), apply labels based on
configurable path-glob → label rules. Supports glob patterns, multiple labels
per file, and priority ordering when rules conflict.

## Files

| Path | Purpose |
| --- | --- |
| `pr-label-assigner.sh` | The label-assigner script (pure Bash). |
| `labels.config` | Default rules: `<glob> -> <label>[,<label>...] [ -> <priority>]`. |
| `fixtures/changed-files.txt` | Default mock changed-files list. |
| `.github/workflows/pr-label-assigner.yml` | CI pipeline that runs the script. |
| `test/unit.bats` | TDD unit tests for the script. |
| `test/workflow.bats` | Workflow structure tests + `act` end-to-end tests. |
| `act-result.txt` | Captured `act` output from the last harness run. |

## Usage

```bash
./pr-label-assigner.sh --config labels.config --files fixtures/changed-files.txt
# or pipe the changed paths in on stdin:
git diff --name-only origin/main... | ./pr-label-assigner.sh --config labels.config
```

The final, deduplicated label set is printed one per line, ordered by descending
priority with alphabetical tie-breaks.

## Rule / glob semantics

A rule line is `<glob> -> <label>[,<label>...] [ -> <priority>]`:

- `*` matches anything **except** `/` (one path segment).
- `**` matches anything **including** `/` (spans directories).
- `?` matches a single non-`/` character.
- A pattern with **no `/`** matches the basename at any depth (gitignore-style),
  so `*.test.*` matches `src/foo.test.js`.
- A rule may assign several comma-separated labels.
- `priority` is an optional integer (default `0`). When several rules assign the
  same label it keeps the highest priority; the printed set is sorted by
  priority (desc) then label (asc), so higher-priority labels win on ordering.

Lines beginning with `#` and blank lines are ignored. Malformed rules (missing
`->`, empty pattern/label, non-integer priority) fail with a clear message.

## Testing

Two layers, both runnable with `bats`:

- **`test/unit.bats`** — fast red/green/refactor TDD of the script's logic.
- **`test/workflow.bats`** — verifies the workflow's structure (triggers, jobs,
  dependencies, script references, `actionlint`) and then runs **every** test
  case through the real GitHub Actions workflow via `act push --rm`, asserting
  the exact label output and that every job reports `Job succeeded`. All `act`
  output is appended to `act-result.txt`.

```bash
bats test/unit.bats        # fast, no containers
bats test/workflow.bats    # structure tests + act (needs Docker/act)
```

> The local `act` image is built locally, so the harness (and `.actrc`) pass
> `--pull=false` to stop `act` from force-pulling it from a registry.
