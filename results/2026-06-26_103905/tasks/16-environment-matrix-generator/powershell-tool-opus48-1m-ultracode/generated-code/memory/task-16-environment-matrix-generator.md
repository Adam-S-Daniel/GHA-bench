---
name: task-16-environment-matrix-generator
description: Benchmark task 16 — PowerShell GHA build-matrix generator, constraints and environment
metadata:
  type: project
---

Benchmark task 16 (PowerShell mode): generate a GitHub Actions `strategy.matrix` JSON from a config (OS/version/feature axes + include/exclude/max-parallel/fail-fast/max-size). TDD with Pester, plus a `.github/workflows/environment-matrix-generator.yml` that runs via `act push`.

**Environment** (verified 2026-06-28): pwsh 7.6.3, Pester 5.7.1, actionlint 1.7.12, act 0.2.87, Docker present. `.actrc` maps `-P ubuntu-latest=act-ubuntu-pwsh:latest` (image EXISTS locally, has pwsh+Pester pre-installed). Worktree is its own git repo (branch master, no commits, no remote).

**Hard constraints / traps**:
- Use `shell: pwsh` on workflow run steps (never `pwsh -File` from bash).
- At most 3 `act push` runs total during dev — run actionlint first (instant), reason before re-running.
- ALL test cases must execute THROUGH act → batch all fixtures into ONE act run (a generate job loops over `fixtures/*.json`, prints delimited blocks). The oversize/error fixture must be tolerated by the loop so the job still exits 0.
- act output → `act-result.txt` (required artifact). Assert EXACT expected values + "Job succeeded" + exit 0.
- PostToolUse hooks: Invoke-ScriptAnalyzer on .ps1, actionlint on workflow yml — keep clean (approved verbs, no Write-Host).

GHA matrix include/exclude algorithm follows the official docs fruit/animal example exactly (include extends only ORIGINAL post-exclude combos, protecting axis keys; unmatched include → new combo). [[matrix-include-exclude-algorithm]]
