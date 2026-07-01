# Benchmark Results: Language Comparison

**Last updated:** 2026-07-01 04:18:44 PM ET — 83/100 runs completed, 17 remaining; total cost $236.32; total agent time 1245.9 min.
**Claude Code versions used:** v2.1.197 (83 runs). Each link goes to a per-version snapshot of the system prompt, default-tool descriptions, and the chronological Anthropic changelog up to that version. Regenerate with `python3 version_docs.py`.

## Table of Contents

- [Scoring](#scoring)
  - [Duration columns](#duration-columns)
- [Tiers by Language/Model/Effort](#tiers-by-languagemodeleffort)
- [Failed / Timed-Out Runs](#failed-timed-out-runs)
- [Comparison by Language/Model/Effort](#comparison-by-languagemodeleffort)
- [Savings Analysis](#savings-analysis)
  - [Hook Savings by Language/Model/Effort](#hook-savings-by-languagemodeleffort)
  - [Trap Analysis by Language/Model/Effort/Category](#trap-analysis-by-languagemodeleffortcategory)
  - [Traps by Language/Model/Effort](#traps-by-languagemodeleffort)
  - [Prompt Cache Savings](#prompt-cache-savings)
- [Test Quality Evaluation](#test-quality-evaluation)
  - [Structural Metrics by Language/Model/Effort](#structural-metrics-by-languagemodeleffort)
- [Per-Run Results](#per-run-results)
- [Notes](#notes)
  - [Tiers](#tiers)
  - [CLI Version Legend](#cli-version-legend)

## Scoring

Judges: panel of LLM-as-judge models — `haiku-4-5` (via Claude CLI) and `Gemini 3.1 Pro (High)` (via the Antigravity `agy` CLI). Each run's quality score is the mean of both judges, cached per-run so numbers are deterministic across regenerations. Known bias caveats live in the [Judge Consistency Summary](#judge-consistency-summary).

**Tests Quality** = Overall score (1-5) for the generated **test code**.

Dimensions:
- **coverage** — requirements tested
- **rigor** — edge cases + error paths
- **design** — fixture quality + independence
- **overall** — holistic

**Workflow Craft** = Overall score (1-5) for the produced **deliverable** (workflow YAML + scripts, excluding tests).

Dimensions:
- **best_practices** — language-appropriate conventions
- **conciseness** — penalizes dead code AND repetition that should be factored
- **readability** — clarity for a reader encountering it cold
- **maintainability** — modularity, error-handling, testability
- **overall** — holistic

**Duration / Cost** = ratio of each combo's average to the best combo's average on the same axis (lower is better).

Properties:
- **Scale:** ratios, not raw seconds or dollars
- **Band calibration:** auto-calibrated to the data's best-to-worst spread via log-equal division (`boundary_i = max_ratio^(i/12)`), so the best observed ratio lands at A+ and the worst at D-
- **F band:** reserved for ratios beyond the observed worst

### Duration columns

Every Duration figure in this report derives from `timing.grand_total_duration_ms` in `metrics.json` — wall-clock seconds from CLI invocation to the final assistant turn (agent thinking + tool execution + hooks).

- **Duration** (single run): that one run's wall clock. Appears in the [Failed / Timed-Out Runs](#failed--timed-out-runs) and per-run detail tables.
- **Avg Duration** (in the [Comparison by Language/Model/Effort](#comparison-by-languagemodeleffort) table; also drives the [Tiers](#tiers-by-languagemodeleffort) Duration column): arithmetic mean of `Duration` over the runs in that combo, excluding failed/timed-out runs.
- **Avg Duration Net of Traps** (in the Comparison table only): mean of (per-run `Duration` − that run's `Time Lost`), where `Time Lost` is the trap detector's estimate of seconds spent on detected anti-patterns (see [Trap Descriptions](#trap-descriptions) and the trap-table [Column Definitions](#column-definitions) for the trap list and how Time Lost is computed). Reads as a counterfactual: roughly how fast each combo would have been without the detected traps.
- The **Tier table's Duration column** shows the tier letter (A+..F) for the combo's gross **Avg Duration** ratio. Net of Traps does not feed the tier band.
## Tiers by Language/Model/Effort

*Default sort: weighted composite of tiers (40% Tests, 25% Workflow Craft, 35% split between Duration & Cost). See [Notes](#notes) for tier-band definitions and scoring rubric.*
*`*` after a Model label = this combo's aggregates exclude one or more failed/timed-out runs (see the Failed / Timed-Out Runs table).*

| Language | Model | Duration | Cost | Tests Quality | Workflow Craft |
|----------|-------|----------|------|-----------|-------------|
| default | sonnet5-low | A+ (4.2min) | A+ ($0.97) | — | — |
| typescript-bun | sonnet5-low | A- (6.3min) | A- ($1.38) | — | — |
| bash | sonnet5-low | B- (9.4min) | A+ ($1.03) | — | — |
| powershell | sonnet5-low | B (7.7min) | A ($1.19) | — | — |
| powershell-tool | sonnet5-low | B- (9.4min) | A ($1.26) | — | — |
| default | sonnet5-1m-medium | B (8.2min) | B- ($2.06) | — | — |
| powershell | sonnet5-1m-medium | C (12.4min) | B- ($2.16) | — | — |
| typescript-bun | sonnet5-1m-medium | C (13.0min) | C+ ($2.68) | — | — |
| bash | sonnet5-1m-medium* | C (12.3min) | C ($2.86) | — | — |
| powershell-tool | sonnet5-1m-medium | C- (14.1min) | C+ ($2.53) | — | — |
| default | sonnet5 | C- (13.4min) | C- ($3.55) | — | — |
| bash | sonnet5* | D+ (17.5min) | D- ($5.27) | — | — |
| powershell | sonnet5* | D- (23.2min) | D ($4.89) | — | — |
| powershell-tool | sonnet5* | D- (22.8min) | D ($4.55) | — | — |
| typescript-bun | sonnet5 | D- (21.3min) | D- ($5.71) | — | — |


<details>
<summary>Sorted by Duration tier (best-first), then avg of Cost/Tests/Workflow Craft tiers</summary>

| Language | Model | Duration | Cost | Tests Quality | Workflow Craft |
|----------|-------|----------|------|-----------|-------------|
| default | sonnet5-low | A+ (4.2min) | A+ ($0.97) | — | — |
| typescript-bun | sonnet5-low | A- (6.3min) | A- ($1.38) | — | — |
| powershell | sonnet5-low | B (7.7min) | A ($1.19) | — | — |
| default | sonnet5-1m-medium | B (8.2min) | B- ($2.06) | — | — |
| bash | sonnet5-low | B- (9.4min) | A+ ($1.03) | — | — |
| powershell-tool | sonnet5-low | B- (9.4min) | A ($1.26) | — | — |
| powershell | sonnet5-1m-medium | C (12.4min) | B- ($2.16) | — | — |
| typescript-bun | sonnet5-1m-medium | C (13.0min) | C+ ($2.68) | — | — |
| bash | sonnet5-1m-medium* | C (12.3min) | C ($2.86) | — | — |
| powershell-tool | sonnet5-1m-medium | C- (14.1min) | C+ ($2.53) | — | — |
| default | sonnet5 | C- (13.4min) | C- ($3.55) | — | — |
| bash | sonnet5* | D+ (17.5min) | D- ($5.27) | — | — |
| powershell | sonnet5* | D- (23.2min) | D ($4.89) | — | — |
| powershell-tool | sonnet5* | D- (22.8min) | D ($4.55) | — | — |
| typescript-bun | sonnet5 | D- (21.3min) | D- ($5.71) | — | — |

</details>

<details>
<summary>Sorted by Cost tier (best-first), then avg of Duration/Tests/Workflow Craft tiers</summary>

| Language | Model | Duration | Cost | Tests Quality | Workflow Craft |
|----------|-------|----------|------|-----------|-------------|
| default | sonnet5-low | A+ (4.2min) | A+ ($0.97) | — | — |
| bash | sonnet5-low | B- (9.4min) | A+ ($1.03) | — | — |
| powershell | sonnet5-low | B (7.7min) | A ($1.19) | — | — |
| powershell-tool | sonnet5-low | B- (9.4min) | A ($1.26) | — | — |
| typescript-bun | sonnet5-low | A- (6.3min) | A- ($1.38) | — | — |
| default | sonnet5-1m-medium | B (8.2min) | B- ($2.06) | — | — |
| powershell | sonnet5-1m-medium | C (12.4min) | B- ($2.16) | — | — |
| typescript-bun | sonnet5-1m-medium | C (13.0min) | C+ ($2.68) | — | — |
| powershell-tool | sonnet5-1m-medium | C- (14.1min) | C+ ($2.53) | — | — |
| bash | sonnet5-1m-medium* | C (12.3min) | C ($2.86) | — | — |
| default | sonnet5 | C- (13.4min) | C- ($3.55) | — | — |
| powershell | sonnet5* | D- (23.2min) | D ($4.89) | — | — |
| powershell-tool | sonnet5* | D- (22.8min) | D ($4.55) | — | — |
| bash | sonnet5* | D+ (17.5min) | D- ($5.27) | — | — |
| typescript-bun | sonnet5 | D- (21.3min) | D- ($5.71) | — | — |

</details>

<details>
<summary>Sorted by Tests Quality tier (best-first; no-data last), then avg of other tiers</summary>

| Language | Model | Duration | Cost | Tests Quality | Workflow Craft |
|----------|-------|----------|------|-----------|-------------|
| default | sonnet5-low | A+ (4.2min) | A+ ($0.97) | — | — |
| typescript-bun | sonnet5-low | A- (6.3min) | A- ($1.38) | — | — |
| bash | sonnet5-low | B- (9.4min) | A+ ($1.03) | — | — |
| powershell | sonnet5-low | B (7.7min) | A ($1.19) | — | — |
| powershell-tool | sonnet5-low | B- (9.4min) | A ($1.26) | — | — |
| default | sonnet5-1m-medium | B (8.2min) | B- ($2.06) | — | — |
| powershell | sonnet5-1m-medium | C (12.4min) | B- ($2.16) | — | — |
| typescript-bun | sonnet5-1m-medium | C (13.0min) | C+ ($2.68) | — | — |
| bash | sonnet5-1m-medium* | C (12.3min) | C ($2.86) | — | — |
| powershell-tool | sonnet5-1m-medium | C- (14.1min) | C+ ($2.53) | — | — |
| default | sonnet5 | C- (13.4min) | C- ($3.55) | — | — |
| bash | sonnet5* | D+ (17.5min) | D- ($5.27) | — | — |
| powershell | sonnet5* | D- (23.2min) | D ($4.89) | — | — |
| powershell-tool | sonnet5* | D- (22.8min) | D ($4.55) | — | — |
| typescript-bun | sonnet5 | D- (21.3min) | D- ($5.71) | — | — |

</details>

<details>
<summary>Sorted by Workflow Craft tier (best-first; no-data last), then avg of other tiers</summary>

| Language | Model | Duration | Cost | Tests Quality | Workflow Craft |
|----------|-------|----------|------|-----------|-------------|
| default | sonnet5-low | A+ (4.2min) | A+ ($0.97) | — | — |
| typescript-bun | sonnet5-low | A- (6.3min) | A- ($1.38) | — | — |
| bash | sonnet5-low | B- (9.4min) | A+ ($1.03) | — | — |
| powershell | sonnet5-low | B (7.7min) | A ($1.19) | — | — |
| powershell-tool | sonnet5-low | B- (9.4min) | A ($1.26) | — | — |
| default | sonnet5-1m-medium | B (8.2min) | B- ($2.06) | — | — |
| powershell | sonnet5-1m-medium | C (12.4min) | B- ($2.16) | — | — |
| typescript-bun | sonnet5-1m-medium | C (13.0min) | C+ ($2.68) | — | — |
| bash | sonnet5-1m-medium* | C (12.3min) | C ($2.86) | — | — |
| powershell-tool | sonnet5-1m-medium | C- (14.1min) | C+ ($2.53) | — | — |
| default | sonnet5 | C- (13.4min) | C- ($3.55) | — | — |
| bash | sonnet5* | D+ (17.5min) | D- ($5.27) | — | — |
| powershell | sonnet5* | D- (23.2min) | D ($4.89) | — | — |
| powershell-tool | sonnet5* | D- (22.8min) | D ($4.55) | — | — |
| typescript-bun | sonnet5 | D- (21.3min) | D- ($5.71) | — | — |

</details>

- **Estimated time remaining:** 1336.0min
- **Estimated total cost:** $284.72

## Failed / Timed-Out Runs

| Task | Language | Model | Duration | Reason | Lines | actionlint | act-result.txt |
|------|------|-------|----------|--------|-------|------------|----------------|
| Semantic Version Bumper | powershell | sonnet5 | 30.0min | timeout | 667 | pass | yes |
| PR Label Assigner | bash | sonnet5 | 30.0min | timeout | 1034 | pass | yes |
| PR Label Assigner | powershell | sonnet5 | 30.0min | timeout | 806 | pass | yes |
| PR Label Assigner | powershell-tool | sonnet5 | 30.0min | timeout | 621 | pass | no |
| Test Results Aggregator | powershell | sonnet5 | 30.0min | timeout | 824 | pass | yes |
| Secret Rotation Validator | bash | sonnet5-1m-medium | 9.3min | cli_error | 652 | pass | yes |
| Secret Rotation Validator | powershell | sonnet5 | 30.0min | timeout | 723 | pass | yes |

*7 run(s) excluded from averages below.*

## Comparison by Language/Model/Effort
*(averages exclude failed/timed-out runs)*
*See [Notes](#notes) for scoring rubric and CLI version legend.*

| Language | Model | Runs | Avg Duration | Avg Duration Net of Traps | Avg Errors | Avg Turns | Avg Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| bash | sonnet5-1m-medium* | 6 | 12.3min | 8.5min | 3.3 | 76 | $2.86 | $17.14 | — | — |
| bash | sonnet5* | 6 | 17.5min | 14.2min | 4.3 | 100 | $5.27 | $31.61 | — | — |
| bash | sonnet5-low | 3 | 9.4min | 8.5min | 1.7 | 35 | $1.03 | $3.08 | — | — |
| default | sonnet5-1m-medium | 7 | 8.2min | 6.5min | 1.3 | 59 | $2.06 | $14.44 | — | — |
| default | sonnet5 | 7 | 13.4min | 11.9min | 0.9 | 71 | $3.55 | $24.82 | — | — |
| default | sonnet5-low | 3 | 4.2min | 4.0min | 0.0 | 28 | $0.97 | $2.90 | — | — |
| powershell | sonnet5-1m-medium | 7 | 12.4min | 11.1min | 0.6 | 56 | $2.16 | $15.11 | — | — |
| powershell | sonnet5* | 3 | 23.2min | 10.6min | 1.0 | 94 | $4.89 | $14.67 | — | — |
| powershell | sonnet5-low | 3 | 7.7min | 6.8min | 0.3 | 39 | $1.19 | $3.57 | — | — |
| powershell-tool | sonnet5-1m-medium | 7 | 14.1min | 12.0min | 0.4 | 58 | $2.53 | $17.73 | — | — |
| powershell-tool | sonnet5* | 6 | 22.8min | 19.6min | 1.2 | 86 | $4.55 | $27.30 | — | — |
| powershell-tool | sonnet5-low | 2 | 9.4min | 8.0min | 1.5 | 40 | $1.26 | $2.52 | — | — |
| typescript-bun | sonnet5-1m-medium | 7 | 13.0min | 7.1min | 1.4 | 84 | $2.68 | $18.75 | — | — |
| typescript-bun | sonnet5 | 7 | 21.3min | 15.0min | 3.6 | 125 | $5.71 | $39.95 | — | — |
| typescript-bun | sonnet5-low | 2 | 6.3min | 4.2min | 0.0 | 40 | $1.38 | $2.75 | — | — |


<details>
<summary>Sorted by avg cost (cheapest first)</summary>

| Language | Model | Runs | Avg Duration | Avg Duration Net of Traps | Avg Errors | Avg Turns | Avg Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| default | sonnet5-low | 3 | 4.2min | 4.0min | 0.0 | 28 | $0.97 | $2.90 | — | — |
| bash | sonnet5-low | 3 | 9.4min | 8.5min | 1.7 | 35 | $1.03 | $3.08 | — | — |
| powershell | sonnet5-low | 3 | 7.7min | 6.8min | 0.3 | 39 | $1.19 | $3.57 | — | — |
| powershell-tool | sonnet5-low | 2 | 9.4min | 8.0min | 1.5 | 40 | $1.26 | $2.52 | — | — |
| typescript-bun | sonnet5-low | 2 | 6.3min | 4.2min | 0.0 | 40 | $1.38 | $2.75 | — | — |
| default | sonnet5-1m-medium | 7 | 8.2min | 6.5min | 1.3 | 59 | $2.06 | $14.44 | — | — |
| powershell | sonnet5-1m-medium | 7 | 12.4min | 11.1min | 0.6 | 56 | $2.16 | $15.11 | — | — |
| powershell-tool | sonnet5-1m-medium | 7 | 14.1min | 12.0min | 0.4 | 58 | $2.53 | $17.73 | — | — |
| typescript-bun | sonnet5-1m-medium | 7 | 13.0min | 7.1min | 1.4 | 84 | $2.68 | $18.75 | — | — |
| bash | sonnet5-1m-medium* | 6 | 12.3min | 8.5min | 3.3 | 76 | $2.86 | $17.14 | — | — |
| default | sonnet5 | 7 | 13.4min | 11.9min | 0.9 | 71 | $3.55 | $24.82 | — | — |
| powershell-tool | sonnet5* | 6 | 22.8min | 19.6min | 1.2 | 86 | $4.55 | $27.30 | — | — |
| powershell | sonnet5* | 3 | 23.2min | 10.6min | 1.0 | 94 | $4.89 | $14.67 | — | — |
| bash | sonnet5* | 6 | 17.5min | 14.2min | 4.3 | 100 | $5.27 | $31.61 | — | — |
| typescript-bun | sonnet5 | 7 | 21.3min | 15.0min | 3.6 | 125 | $5.71 | $39.95 | — | — |

</details>

<details>
<summary>Sorted by avg duration (fastest first)</summary>

| Language | Model | Runs | Avg Duration | Avg Duration Net of Traps | Avg Errors | Avg Turns | Avg Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| default | sonnet5-low | 3 | 4.2min | 4.0min | 0.0 | 28 | $0.97 | $2.90 | — | — |
| typescript-bun | sonnet5-low | 2 | 6.3min | 4.2min | 0.0 | 40 | $1.38 | $2.75 | — | — |
| powershell | sonnet5-low | 3 | 7.7min | 6.8min | 0.3 | 39 | $1.19 | $3.57 | — | — |
| default | sonnet5-1m-medium | 7 | 8.2min | 6.5min | 1.3 | 59 | $2.06 | $14.44 | — | — |
| bash | sonnet5-low | 3 | 9.4min | 8.5min | 1.7 | 35 | $1.03 | $3.08 | — | — |
| powershell-tool | sonnet5-low | 2 | 9.4min | 8.0min | 1.5 | 40 | $1.26 | $2.52 | — | — |
| bash | sonnet5-1m-medium* | 6 | 12.3min | 8.5min | 3.3 | 76 | $2.86 | $17.14 | — | — |
| powershell | sonnet5-1m-medium | 7 | 12.4min | 11.1min | 0.6 | 56 | $2.16 | $15.11 | — | — |
| typescript-bun | sonnet5-1m-medium | 7 | 13.0min | 7.1min | 1.4 | 84 | $2.68 | $18.75 | — | — |
| default | sonnet5 | 7 | 13.4min | 11.9min | 0.9 | 71 | $3.55 | $24.82 | — | — |
| powershell-tool | sonnet5-1m-medium | 7 | 14.1min | 12.0min | 0.4 | 58 | $2.53 | $17.73 | — | — |
| bash | sonnet5* | 6 | 17.5min | 14.2min | 4.3 | 100 | $5.27 | $31.61 | — | — |
| typescript-bun | sonnet5 | 7 | 21.3min | 15.0min | 3.6 | 125 | $5.71 | $39.95 | — | — |
| powershell-tool | sonnet5* | 6 | 22.8min | 19.6min | 1.2 | 86 | $4.55 | $27.30 | — | — |
| powershell | sonnet5* | 3 | 23.2min | 10.6min | 1.0 | 94 | $4.89 | $14.67 | — | — |

</details>

<details>
<summary>Sorted by avg duration net of traps (fastest first)</summary>

| Language | Model | Runs | Avg Duration | Avg Duration Net of Traps | Avg Errors | Avg Turns | Avg Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| default | sonnet5-low | 3 | 4.2min | 4.0min | 0.0 | 28 | $0.97 | $2.90 | — | — |
| typescript-bun | sonnet5-low | 2 | 6.3min | 4.2min | 0.0 | 40 | $1.38 | $2.75 | — | — |
| default | sonnet5-1m-medium | 7 | 8.2min | 6.5min | 1.3 | 59 | $2.06 | $14.44 | — | — |
| powershell | sonnet5-low | 3 | 7.7min | 6.8min | 0.3 | 39 | $1.19 | $3.57 | — | — |
| typescript-bun | sonnet5-1m-medium | 7 | 13.0min | 7.1min | 1.4 | 84 | $2.68 | $18.75 | — | — |
| powershell-tool | sonnet5-low | 2 | 9.4min | 8.0min | 1.5 | 40 | $1.26 | $2.52 | — | — |
| bash | sonnet5-1m-medium* | 6 | 12.3min | 8.5min | 3.3 | 76 | $2.86 | $17.14 | — | — |
| bash | sonnet5-low | 3 | 9.4min | 8.5min | 1.7 | 35 | $1.03 | $3.08 | — | — |
| powershell | sonnet5* | 3 | 23.2min | 10.6min | 1.0 | 94 | $4.89 | $14.67 | — | — |
| powershell | sonnet5-1m-medium | 7 | 12.4min | 11.1min | 0.6 | 56 | $2.16 | $15.11 | — | — |
| default | sonnet5 | 7 | 13.4min | 11.9min | 0.9 | 71 | $3.55 | $24.82 | — | — |
| powershell-tool | sonnet5-1m-medium | 7 | 14.1min | 12.0min | 0.4 | 58 | $2.53 | $17.73 | — | — |
| bash | sonnet5* | 6 | 17.5min | 14.2min | 4.3 | 100 | $5.27 | $31.61 | — | — |
| typescript-bun | sonnet5 | 7 | 21.3min | 15.0min | 3.6 | 125 | $5.71 | $39.95 | — | — |
| powershell-tool | sonnet5* | 6 | 22.8min | 19.6min | 1.2 | 86 | $4.55 | $27.30 | — | — |

</details>

<details>
<summary>Sorted by avg errors (fewest first)</summary>

| Language | Model | Runs | Avg Duration | Avg Duration Net of Traps | Avg Errors | Avg Turns | Avg Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| default | sonnet5-low | 3 | 4.2min | 4.0min | 0.0 | 28 | $0.97 | $2.90 | — | — |
| typescript-bun | sonnet5-low | 2 | 6.3min | 4.2min | 0.0 | 40 | $1.38 | $2.75 | — | — |
| powershell | sonnet5-low | 3 | 7.7min | 6.8min | 0.3 | 39 | $1.19 | $3.57 | — | — |
| powershell-tool | sonnet5-1m-medium | 7 | 14.1min | 12.0min | 0.4 | 58 | $2.53 | $17.73 | — | — |
| powershell | sonnet5-1m-medium | 7 | 12.4min | 11.1min | 0.6 | 56 | $2.16 | $15.11 | — | — |
| default | sonnet5 | 7 | 13.4min | 11.9min | 0.9 | 71 | $3.55 | $24.82 | — | — |
| powershell | sonnet5* | 3 | 23.2min | 10.6min | 1.0 | 94 | $4.89 | $14.67 | — | — |
| powershell-tool | sonnet5* | 6 | 22.8min | 19.6min | 1.2 | 86 | $4.55 | $27.30 | — | — |
| default | sonnet5-1m-medium | 7 | 8.2min | 6.5min | 1.3 | 59 | $2.06 | $14.44 | — | — |
| typescript-bun | sonnet5-1m-medium | 7 | 13.0min | 7.1min | 1.4 | 84 | $2.68 | $18.75 | — | — |
| powershell-tool | sonnet5-low | 2 | 9.4min | 8.0min | 1.5 | 40 | $1.26 | $2.52 | — | — |
| bash | sonnet5-low | 3 | 9.4min | 8.5min | 1.7 | 35 | $1.03 | $3.08 | — | — |
| bash | sonnet5-1m-medium* | 6 | 12.3min | 8.5min | 3.3 | 76 | $2.86 | $17.14 | — | — |
| typescript-bun | sonnet5 | 7 | 21.3min | 15.0min | 3.6 | 125 | $5.71 | $39.95 | — | — |
| bash | sonnet5* | 6 | 17.5min | 14.2min | 4.3 | 100 | $5.27 | $31.61 | — | — |

</details>

<details>
<summary>Sorted by avg turns (fewest first)</summary>

| Language | Model | Runs | Avg Duration | Avg Duration Net of Traps | Avg Errors | Avg Turns | Avg Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| default | sonnet5-low | 3 | 4.2min | 4.0min | 0.0 | 28 | $0.97 | $2.90 | — | — |
| bash | sonnet5-low | 3 | 9.4min | 8.5min | 1.7 | 35 | $1.03 | $3.08 | — | — |
| powershell | sonnet5-low | 3 | 7.7min | 6.8min | 0.3 | 39 | $1.19 | $3.57 | — | — |
| powershell-tool | sonnet5-low | 2 | 9.4min | 8.0min | 1.5 | 40 | $1.26 | $2.52 | — | — |
| typescript-bun | sonnet5-low | 2 | 6.3min | 4.2min | 0.0 | 40 | $1.38 | $2.75 | — | — |
| powershell | sonnet5-1m-medium | 7 | 12.4min | 11.1min | 0.6 | 56 | $2.16 | $15.11 | — | — |
| powershell-tool | sonnet5-1m-medium | 7 | 14.1min | 12.0min | 0.4 | 58 | $2.53 | $17.73 | — | — |
| default | sonnet5-1m-medium | 7 | 8.2min | 6.5min | 1.3 | 59 | $2.06 | $14.44 | — | — |
| default | sonnet5 | 7 | 13.4min | 11.9min | 0.9 | 71 | $3.55 | $24.82 | — | — |
| bash | sonnet5-1m-medium* | 6 | 12.3min | 8.5min | 3.3 | 76 | $2.86 | $17.14 | — | — |
| typescript-bun | sonnet5-1m-medium | 7 | 13.0min | 7.1min | 1.4 | 84 | $2.68 | $18.75 | — | — |
| powershell-tool | sonnet5* | 6 | 22.8min | 19.6min | 1.2 | 86 | $4.55 | $27.30 | — | — |
| powershell | sonnet5* | 3 | 23.2min | 10.6min | 1.0 | 94 | $4.89 | $14.67 | — | — |
| bash | sonnet5* | 6 | 17.5min | 14.2min | 4.3 | 100 | $5.27 | $31.61 | — | — |
| typescript-bun | sonnet5 | 7 | 21.3min | 15.0min | 3.6 | 125 | $5.71 | $39.95 | — | — |

</details>

<details>
<summary>Sorted by LLM-as-judge score (best first)</summary>

| Language | Model | Runs | Avg Duration | Avg Duration Net of Traps | Avg Errors | Avg Turns | Avg Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| bash | sonnet5-1m-medium* | 6 | 12.3min | 8.5min | 3.3 | 76 | $2.86 | $17.14 | — | — |
| bash | sonnet5* | 6 | 17.5min | 14.2min | 4.3 | 100 | $5.27 | $31.61 | — | — |
| bash | sonnet5-low | 3 | 9.4min | 8.5min | 1.7 | 35 | $1.03 | $3.08 | — | — |
| default | sonnet5-1m-medium | 7 | 8.2min | 6.5min | 1.3 | 59 | $2.06 | $14.44 | — | — |
| default | sonnet5 | 7 | 13.4min | 11.9min | 0.9 | 71 | $3.55 | $24.82 | — | — |
| default | sonnet5-low | 3 | 4.2min | 4.0min | 0.0 | 28 | $0.97 | $2.90 | — | — |
| powershell | sonnet5-1m-medium | 7 | 12.4min | 11.1min | 0.6 | 56 | $2.16 | $15.11 | — | — |
| powershell | sonnet5* | 3 | 23.2min | 10.6min | 1.0 | 94 | $4.89 | $14.67 | — | — |
| powershell | sonnet5-low | 3 | 7.7min | 6.8min | 0.3 | 39 | $1.19 | $3.57 | — | — |
| powershell-tool | sonnet5-1m-medium | 7 | 14.1min | 12.0min | 0.4 | 58 | $2.53 | $17.73 | — | — |
| powershell-tool | sonnet5* | 6 | 22.8min | 19.6min | 1.2 | 86 | $4.55 | $27.30 | — | — |
| powershell-tool | sonnet5-low | 2 | 9.4min | 8.0min | 1.5 | 40 | $1.26 | $2.52 | — | — |
| typescript-bun | sonnet5-1m-medium | 7 | 13.0min | 7.1min | 1.4 | 84 | $2.68 | $18.75 | — | — |
| typescript-bun | sonnet5 | 7 | 21.3min | 15.0min | 3.6 | 125 | $5.71 | $39.95 | — | — |
| typescript-bun | sonnet5-low | 2 | 6.3min | 4.2min | 0.0 | 40 | $1.38 | $2.75 | — | — |

</details>

<details>
<summary>Sorted by deliverable-quality score (best first)</summary>

| Language | Model | Runs | Avg Duration | Avg Duration Net of Traps | Avg Errors | Avg Turns | Avg Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| bash | sonnet5-1m-medium* | 6 | 12.3min | 8.5min | 3.3 | 76 | $2.86 | $17.14 | — | — |
| bash | sonnet5* | 6 | 17.5min | 14.2min | 4.3 | 100 | $5.27 | $31.61 | — | — |
| bash | sonnet5-low | 3 | 9.4min | 8.5min | 1.7 | 35 | $1.03 | $3.08 | — | — |
| default | sonnet5-1m-medium | 7 | 8.2min | 6.5min | 1.3 | 59 | $2.06 | $14.44 | — | — |
| default | sonnet5 | 7 | 13.4min | 11.9min | 0.9 | 71 | $3.55 | $24.82 | — | — |
| default | sonnet5-low | 3 | 4.2min | 4.0min | 0.0 | 28 | $0.97 | $2.90 | — | — |
| powershell | sonnet5-1m-medium | 7 | 12.4min | 11.1min | 0.6 | 56 | $2.16 | $15.11 | — | — |
| powershell | sonnet5* | 3 | 23.2min | 10.6min | 1.0 | 94 | $4.89 | $14.67 | — | — |
| powershell | sonnet5-low | 3 | 7.7min | 6.8min | 0.3 | 39 | $1.19 | $3.57 | — | — |
| powershell-tool | sonnet5-1m-medium | 7 | 14.1min | 12.0min | 0.4 | 58 | $2.53 | $17.73 | — | — |
| powershell-tool | sonnet5* | 6 | 22.8min | 19.6min | 1.2 | 86 | $4.55 | $27.30 | — | — |
| powershell-tool | sonnet5-low | 2 | 9.4min | 8.0min | 1.5 | 40 | $1.26 | $2.52 | — | — |
| typescript-bun | sonnet5-1m-medium | 7 | 13.0min | 7.1min | 1.4 | 84 | $2.68 | $18.75 | — | — |
| typescript-bun | sonnet5 | 7 | 21.3min | 15.0min | 3.6 | 125 | $5.71 | $39.95 | — | — |
| typescript-bun | sonnet5-low | 2 | 6.3min | 4.2min | 0.0 | 40 | $1.38 | $2.75 | — | — |

</details>

## Savings Analysis

### Hook Savings by Language/Model/Effort

Each hook-caught error avoids one test run that would otherwise have been needed to discover it.
Every hook fire (hit or miss) costs execution time for the syntax/type checker.

*`% of Test Time Saved` = `net / (net + test_time) × 100` — the share of total (would-have-been + actually-spent) test time that hooks eliminated. Bounded in (-∞, 100%) without an artificial cap; near 100% means hooks substituted for almost all of the hypothetical test work.*

| Language | Model | Fires | Caught | Rate | Gross Saved | % of Time | Overhead | % of Time | Net Saved | % of Time | Test Run Time | % of Test Time Saved |
|------|-------|-------|--------|------|------------|-----------|----------|-----------|-----------|-----------|---------------|----------------------|
| bash | sonnet5-1m-medium-cli2.1.197 | 162 | 5 | 3.1% | 1.0min | 0.1% | 0.3min | 0.0% | 0.7min | 0.1% | 20.0min | 3.5% |
| bash | sonnet5-cli2.1.197 | 184 | 14 | 7.6% | 2.8min | 0.2% | 0.5min | 0.0% | 2.3min | 0.2% | 22.4min | 9.4% |
| bash | sonnet5-low-cli2.1.197 | 36 | 0 | 0.0% | 0.0min | 0.0% | 0.0min | 0.0% | -0.0min | -0.0% | 17.4min | -0.1% |
| default | sonnet5-1m-medium-cli2.1.197 | 160 | 6 | 3.8% | 0.8min | 0.1% | 1.2min | 0.1% | -0.4min | -0.0% | 9.6min | -4.0% |
| default | sonnet5-cli2.1.197 | 145 | 4 | 2.8% | 0.5min | 0.0% | 2.7min | 0.2% | -2.2min | -0.2% | 12.6min | -21.0% |
| default | sonnet5-low-cli2.1.197 | 37 | 0 | 0.0% | 0.0min | 0.0% | 0.1min | 0.0% | -0.1min | -0.0% | 1.9min | -4.1% |
| powershell | sonnet5-1m-medium-cli2.1.197 | 160 | 37 | 23.1% | 21.6min | 1.7% | 17.7min | 1.4% | 3.9min | 0.3% | 13.5min | 22.3% |
| powershell | sonnet5-cli2.1.197 | 206 | 35 | 17.0% | 20.4min | 1.6% | 30.5min | 2.4% | -10.1min | -0.8% | 30.5min | -49.3% |
| powershell | sonnet5-low-cli2.1.197 | 54 | 11 | 20.4% | 6.4min | 0.5% | 4.1min | 0.3% | 2.4min | 0.2% | 7.3min | 24.6% |
| powershell-tool | sonnet5-1m-medium-cli2.1.197 | 154 | 31 | 20.1% | 18.1min | 1.5% | 17.3min | 1.4% | 0.8min | 0.1% | 25.2min | 3.1% |
| powershell-tool | sonnet5-cli2.1.197 | 168 | 27 | 16.1% | 15.8min | 1.3% | 24.9min | 2.0% | -9.1min | -0.7% | 27.4min | -50.1% |
| powershell-tool | sonnet5-low-cli2.1.197 | 30 | 4 | 13.3% | 2.3min | 0.2% | 3.5min | 0.3% | -1.1min | -0.1% | 5.6min | -25.3% |
| typescript-bun | sonnet5-1m-medium-cli2.1.197 | 206 | 83 | 40.3% | 11.1min | 0.9% | 13.5min | 1.1% | -2.4min | -0.2% | 7.5min | -48.1% |
| typescript-bun | sonnet5-cli2.1.197 | 279 | 120 | 43.0% | 16.0min | 1.3% | 19.8min | 1.6% | -3.8min | -0.3% | 14.8min | -34.8% |
| typescript-bun | sonnet5-low-cli2.1.197 | 31 | 9 | 29.0% | 1.2min | 0.1% | 2.0min | 0.2% | -0.8min | -0.1% | 3.0min | -33.6% |


<details>
<summary>Sorted by net saved (most first)</summary>

| Language | Model | Fires | Caught | Rate | Gross Saved | % of Time | Overhead | % of Time | Net Saved | % of Time | Test Run Time | % of Test Time Saved |
|------|-------|-------|--------|------|------------|-----------|----------|-----------|-----------|-----------|---------------|----------------------|
| powershell | sonnet5-1m-medium-cli2.1.197 | 160 | 37 | 23.1% | 21.6min | 1.7% | 17.7min | 1.4% | 3.9min | 0.3% | 13.5min | 22.3% |
| powershell | sonnet5-low-cli2.1.197 | 54 | 11 | 20.4% | 6.4min | 0.5% | 4.1min | 0.3% | 2.4min | 0.2% | 7.3min | 24.6% |
| bash | sonnet5-cli2.1.197 | 184 | 14 | 7.6% | 2.8min | 0.2% | 0.5min | 0.0% | 2.3min | 0.2% | 22.4min | 9.4% |
| powershell-tool | sonnet5-1m-medium-cli2.1.197 | 154 | 31 | 20.1% | 18.1min | 1.5% | 17.3min | 1.4% | 0.8min | 0.1% | 25.2min | 3.1% |
| bash | sonnet5-1m-medium-cli2.1.197 | 162 | 5 | 3.1% | 1.0min | 0.1% | 0.3min | 0.0% | 0.7min | 0.1% | 20.0min | 3.5% |
| bash | sonnet5-low-cli2.1.197 | 36 | 0 | 0.0% | 0.0min | 0.0% | 0.0min | 0.0% | -0.0min | -0.0% | 17.4min | -0.1% |
| default | sonnet5-low-cli2.1.197 | 37 | 0 | 0.0% | 0.0min | 0.0% | 0.1min | 0.0% | -0.1min | -0.0% | 1.9min | -4.1% |
| default | sonnet5-1m-medium-cli2.1.197 | 160 | 6 | 3.8% | 0.8min | 0.1% | 1.2min | 0.1% | -0.4min | -0.0% | 9.6min | -4.0% |
| typescript-bun | sonnet5-low-cli2.1.197 | 31 | 9 | 29.0% | 1.2min | 0.1% | 2.0min | 0.2% | -0.8min | -0.1% | 3.0min | -33.6% |
| powershell-tool | sonnet5-low-cli2.1.197 | 30 | 4 | 13.3% | 2.3min | 0.2% | 3.5min | 0.3% | -1.1min | -0.1% | 5.6min | -25.3% |
| default | sonnet5-cli2.1.197 | 145 | 4 | 2.8% | 0.5min | 0.0% | 2.7min | 0.2% | -2.2min | -0.2% | 12.6min | -21.0% |
| typescript-bun | sonnet5-1m-medium-cli2.1.197 | 206 | 83 | 40.3% | 11.1min | 0.9% | 13.5min | 1.1% | -2.4min | -0.2% | 7.5min | -48.1% |
| typescript-bun | sonnet5-cli2.1.197 | 279 | 120 | 43.0% | 16.0min | 1.3% | 19.8min | 1.6% | -3.8min | -0.3% | 14.8min | -34.8% |
| powershell-tool | sonnet5-cli2.1.197 | 168 | 27 | 16.1% | 15.8min | 1.3% | 24.9min | 2.0% | -9.1min | -0.7% | 27.4min | -50.1% |
| powershell | sonnet5-cli2.1.197 | 206 | 35 | 17.0% | 20.4min | 1.6% | 30.5min | 2.4% | -10.1min | -0.8% | 30.5min | -49.3% |

</details>

<details>
<summary>Sorted by net % of test time saved (most first)</summary>

| Language | Model | Fires | Caught | Rate | Gross Saved | % of Time | Overhead | % of Time | Net Saved | % of Time | Test Run Time | % of Test Time Saved |
|------|-------|-------|--------|------|------------|-----------|----------|-----------|-----------|-----------|---------------|----------------------|
| powershell | sonnet5-low-cli2.1.197 | 54 | 11 | 20.4% | 6.4min | 0.5% | 4.1min | 0.3% | 2.4min | 0.2% | 7.3min | 24.6% |
| powershell | sonnet5-1m-medium-cli2.1.197 | 160 | 37 | 23.1% | 21.6min | 1.7% | 17.7min | 1.4% | 3.9min | 0.3% | 13.5min | 22.3% |
| bash | sonnet5-cli2.1.197 | 184 | 14 | 7.6% | 2.8min | 0.2% | 0.5min | 0.0% | 2.3min | 0.2% | 22.4min | 9.4% |
| bash | sonnet5-1m-medium-cli2.1.197 | 162 | 5 | 3.1% | 1.0min | 0.1% | 0.3min | 0.0% | 0.7min | 0.1% | 20.0min | 3.5% |
| powershell-tool | sonnet5-1m-medium-cli2.1.197 | 154 | 31 | 20.1% | 18.1min | 1.5% | 17.3min | 1.4% | 0.8min | 0.1% | 25.2min | 3.1% |
| bash | sonnet5-low-cli2.1.197 | 36 | 0 | 0.0% | 0.0min | 0.0% | 0.0min | 0.0% | -0.0min | -0.0% | 17.4min | -0.1% |
| default | sonnet5-1m-medium-cli2.1.197 | 160 | 6 | 3.8% | 0.8min | 0.1% | 1.2min | 0.1% | -0.4min | -0.0% | 9.6min | -4.0% |
| default | sonnet5-low-cli2.1.197 | 37 | 0 | 0.0% | 0.0min | 0.0% | 0.1min | 0.0% | -0.1min | -0.0% | 1.9min | -4.1% |
| default | sonnet5-cli2.1.197 | 145 | 4 | 2.8% | 0.5min | 0.0% | 2.7min | 0.2% | -2.2min | -0.2% | 12.6min | -21.0% |
| powershell-tool | sonnet5-low-cli2.1.197 | 30 | 4 | 13.3% | 2.3min | 0.2% | 3.5min | 0.3% | -1.1min | -0.1% | 5.6min | -25.3% |
| typescript-bun | sonnet5-low-cli2.1.197 | 31 | 9 | 29.0% | 1.2min | 0.1% | 2.0min | 0.2% | -0.8min | -0.1% | 3.0min | -33.6% |
| typescript-bun | sonnet5-cli2.1.197 | 279 | 120 | 43.0% | 16.0min | 1.3% | 19.8min | 1.6% | -3.8min | -0.3% | 14.8min | -34.8% |
| typescript-bun | sonnet5-1m-medium-cli2.1.197 | 206 | 83 | 40.3% | 11.1min | 0.9% | 13.5min | 1.1% | -2.4min | -0.2% | 7.5min | -48.1% |
| powershell | sonnet5-cli2.1.197 | 206 | 35 | 17.0% | 20.4min | 1.6% | 30.5min | 2.4% | -10.1min | -0.8% | 30.5min | -49.3% |
| powershell-tool | sonnet5-cli2.1.197 | 168 | 27 | 16.1% | 15.8min | 1.3% | 24.9min | 2.0% | -9.1min | -0.7% | 27.4min | -50.1% |

</details>

<details>
<summary>Sorted by catch rate (highest first)</summary>

| Language | Model | Fires | Caught | Rate | Gross Saved | % of Time | Overhead | % of Time | Net Saved | % of Time | Test Run Time | % of Test Time Saved |
|------|-------|-------|--------|------|------------|-----------|----------|-----------|-----------|-----------|---------------|----------------------|
| typescript-bun | sonnet5-cli2.1.197 | 279 | 120 | 43.0% | 16.0min | 1.3% | 19.8min | 1.6% | -3.8min | -0.3% | 14.8min | -34.8% |
| typescript-bun | sonnet5-1m-medium-cli2.1.197 | 206 | 83 | 40.3% | 11.1min | 0.9% | 13.5min | 1.1% | -2.4min | -0.2% | 7.5min | -48.1% |
| typescript-bun | sonnet5-low-cli2.1.197 | 31 | 9 | 29.0% | 1.2min | 0.1% | 2.0min | 0.2% | -0.8min | -0.1% | 3.0min | -33.6% |
| powershell | sonnet5-1m-medium-cli2.1.197 | 160 | 37 | 23.1% | 21.6min | 1.7% | 17.7min | 1.4% | 3.9min | 0.3% | 13.5min | 22.3% |
| powershell | sonnet5-low-cli2.1.197 | 54 | 11 | 20.4% | 6.4min | 0.5% | 4.1min | 0.3% | 2.4min | 0.2% | 7.3min | 24.6% |
| powershell-tool | sonnet5-1m-medium-cli2.1.197 | 154 | 31 | 20.1% | 18.1min | 1.5% | 17.3min | 1.4% | 0.8min | 0.1% | 25.2min | 3.1% |
| powershell | sonnet5-cli2.1.197 | 206 | 35 | 17.0% | 20.4min | 1.6% | 30.5min | 2.4% | -10.1min | -0.8% | 30.5min | -49.3% |
| powershell-tool | sonnet5-cli2.1.197 | 168 | 27 | 16.1% | 15.8min | 1.3% | 24.9min | 2.0% | -9.1min | -0.7% | 27.4min | -50.1% |
| powershell-tool | sonnet5-low-cli2.1.197 | 30 | 4 | 13.3% | 2.3min | 0.2% | 3.5min | 0.3% | -1.1min | -0.1% | 5.6min | -25.3% |
| bash | sonnet5-cli2.1.197 | 184 | 14 | 7.6% | 2.8min | 0.2% | 0.5min | 0.0% | 2.3min | 0.2% | 22.4min | 9.4% |
| default | sonnet5-1m-medium-cli2.1.197 | 160 | 6 | 3.8% | 0.8min | 0.1% | 1.2min | 0.1% | -0.4min | -0.0% | 9.6min | -4.0% |
| bash | sonnet5-1m-medium-cli2.1.197 | 162 | 5 | 3.1% | 1.0min | 0.1% | 0.3min | 0.0% | 0.7min | 0.1% | 20.0min | 3.5% |
| default | sonnet5-cli2.1.197 | 145 | 4 | 2.8% | 0.5min | 0.0% | 2.7min | 0.2% | -2.2min | -0.2% | 12.6min | -21.0% |
| bash | sonnet5-low-cli2.1.197 | 36 | 0 | 0.0% | 0.0min | 0.0% | 0.0min | 0.0% | -0.0min | -0.0% | 17.4min | -0.1% |
| default | sonnet5-low-cli2.1.197 | 37 | 0 | 0.0% | 0.0min | 0.0% | 0.1min | 0.0% | -0.1min | -0.0% | 1.9min | -4.1% |

</details>

### Trap Analysis by Language/Model/Effort/Category

| Trap | Language | Model | Fell In | Time Lost | % of Time | $ Lost | % of $ |
|------|------|-------|---------|-----------|-----------|--------|--------|
| repeated-test-reruns | bash | sonnet5-1m-medium-cli2.1.197 | 6 | 7.0min | 0.6% | $1.63 | 0.69% |
| repeated-test-reruns | bash | sonnet5-cli2.1.197 | 4 | 5.3min | 0.4% | $1.63 | 0.69% |
| repeated-test-reruns | bash | sonnet5-low-cli2.1.197 | 2 | 1.7min | 0.1% | $0.23 | 0.10% |
| repeated-test-reruns | default | sonnet5-1m-medium-cli2.1.197 | 5 | 8.0min | 0.6% | $2.09 | 0.89% |
| repeated-test-reruns | default | sonnet5-cli2.1.197 | 3 | 7.0min | 0.6% | $1.79 | 0.76% |
| repeated-test-reruns | default | sonnet5-low-cli2.1.197 | 1 | 0.7min | 0.1% | $0.17 | 0.07% |
| repeated-test-reruns | powershell | sonnet5-1m-medium-cli2.1.197 | 5 | 5.0min | 0.4% | $0.93 | 0.39% |
| repeated-test-reruns | powershell | sonnet5-cli2.1.197 | 13 | 29.7min | 2.4% | $2.11 | 0.89% |
| repeated-test-reruns | powershell | sonnet5-low-cli2.1.197 | 3 | 2.7min | 0.2% | $0.41 | 0.17% |
| repeated-test-reruns | powershell-tool | sonnet5-1m-medium-cli2.1.197 | 5 | 12.7min | 1.0% | $2.39 | 1.01% |
| repeated-test-reruns | powershell-tool | sonnet5-cli2.1.197 | 7 | 14.3min | 1.2% | $2.14 | 0.91% |
| repeated-test-reruns | powershell-tool | sonnet5-low-cli2.1.197 | 1 | 2.3min | 0.2% | $0.31 | 0.13% |
| repeated-test-reruns | typescript-bun | sonnet5-1m-medium-cli2.1.197 | 7 | 12.3min | 1.0% | $2.54 | 1.08% |
| repeated-test-reruns | typescript-bun | sonnet5-cli2.1.197 | 6 | 9.7min | 0.8% | $2.32 | 0.98% |
| repeated-test-reruns | typescript-bun | sonnet5-low-cli2.1.197 | 2 | 1.7min | 0.1% | $0.36 | 0.15% |
| fixture-rework | bash | sonnet5-1m-medium-cli2.1.197 | 3 | 14.0min | 1.1% | $3.57 | 1.51% |
| fixture-rework | bash | sonnet5-cli2.1.197 | 6 | 7.5min | 0.6% | $2.12 | 0.90% |
| fixture-rework | default | sonnet5-1m-medium-cli2.1.197 | 2 | 2.0min | 0.2% | $0.55 | 0.23% |
| fixture-rework | default | sonnet5-cli2.1.197 | 4 | 2.0min | 0.2% | $0.51 | 0.22% |
| fixture-rework | powershell | sonnet5-1m-medium-cli2.1.197 | 2 | 1.8min | 0.1% | $0.28 | 0.12% |
| fixture-rework | powershell | sonnet5-cli2.1.197 | 3 | 2.8min | 0.2% | $0.12 | 0.05% |
| fixture-rework | powershell-tool | sonnet5-1m-medium-cli2.1.197 | 1 | 0.8min | 0.1% | $0.16 | 0.07% |
| fixture-rework | powershell-tool | sonnet5-cli2.1.197 | 2 | 2.8min | 0.2% | $0.52 | 0.22% |
| fixture-rework | powershell-tool | sonnet5-low-cli2.1.197 | 1 | 0.5min | 0.0% | $0.07 | 0.03% |
| fixture-rework | typescript-bun | sonnet5-1m-medium-cli2.1.197 | 3 | 2.5min | 0.2% | $0.54 | 0.23% |
| fixture-rework | typescript-bun | sonnet5-cli2.1.197 | 6 | 5.8min | 0.5% | $1.62 | 0.68% |
| fixture-rework | typescript-bun | sonnet5-low-cli2.1.197 | 1 | 0.8min | 0.1% | $0.15 | 0.06% |
| ts-type-error-fix-cycles | typescript-bun | sonnet5-1m-medium-cli2.1.197 | 7 | 16.6min | 1.3% | $3.49 | 1.48% |
| ts-type-error-fix-cycles | typescript-bun | sonnet5-cli2.1.197 | 7 | 24.0min | 1.9% | $6.58 | 2.79% |
| ts-type-error-fix-cycles | typescript-bun | sonnet5-low-cli2.1.197 | 2 | 1.8min | 0.1% | $0.39 | 0.17% |
| act-push-debug-loops | bash | sonnet5-1m-medium-cli2.1.197 | 1 | 0.7min | 0.1% | $0.14 | 0.06% |
| act-push-debug-loops | bash | sonnet5-cli2.1.197 | 2 | 5.1min | 0.4% | $1.56 | 0.66% |
| act-push-debug-loops | bash | sonnet5-low-cli2.1.197 | 2 | 0.8min | 0.1% | $0.12 | 0.05% |
| act-push-debug-loops | default | sonnet5-1m-medium-cli2.1.197 | 1 | 1.0min | 0.1% | $0.27 | 0.12% |
| act-push-debug-loops | default | sonnet5-cli2.1.197 | 1 | 1.7min | 0.1% | $0.47 | 0.20% |
| act-push-debug-loops | powershell | sonnet5-1m-medium-cli2.1.197 | 2 | 1.3min | 0.1% | $0.24 | 0.10% |
| act-push-debug-loops | powershell | sonnet5-cli2.1.197 | 1 | 1.7min | 0.1% | $0.35 | 0.15% |
| act-push-debug-loops | powershell-tool | sonnet5-1m-medium-cli2.1.197 | 2 | 1.2min | 0.1% | $0.25 | 0.10% |
| act-push-debug-loops | powershell-tool | sonnet5-cli2.1.197 | 1 | 2.0min | 0.2% | $0.40 | 0.17% |
| act-push-debug-loops | typescript-bun | sonnet5-1m-medium-cli2.1.197 | 4 | 9.7min | 0.8% | $1.89 | 0.80% |
| act-push-debug-loops | typescript-bun | sonnet5-cli2.1.197 | 1 | 2.8min | 0.2% | $0.71 | 0.30% |
| docker-pwsh-install | powershell | sonnet5-cli2.1.197 | 2 | 3.8min | 0.3% | $0.72 | 0.31% |
| bats-setup-issues | bash | sonnet5-1m-medium-cli2.1.197 | 1 | 0.8min | 0.1% | $0.23 | 0.10% |
| bats-setup-issues | bash | sonnet5-cli2.1.197 | 2 | 1.8min | 0.1% | $0.53 | 0.23% |
| actionlint-fix-cycles | powershell | sonnet5-1m-medium-cli2.1.197 | 1 | 0.7min | 0.1% | $0.13 | 0.06% |
| actionlint-fix-cycles | typescript-bun | sonnet5-cli2.1.197 | 2 | 1.7min | 0.1% | $0.39 | 0.16% |
| act-fixture-paths | default | sonnet5-1m-medium-cli2.1.197 | 1 | 1.0min | 0.1% | $0.27 | 0.11% |


<details>
<summary>Sorted by time lost (least first)</summary>

| Trap | Language | Model | Fell In | Time Lost | % of Time | $ Lost | % of $ |
|------|------|-------|---------|-----------|-----------|--------|--------|
| fixture-rework | powershell-tool | sonnet5-low-cli2.1.197 | 1 | 0.5min | 0.0% | $0.07 | 0.03% |
| repeated-test-reruns | default | sonnet5-low-cli2.1.197 | 1 | 0.7min | 0.1% | $0.17 | 0.07% |
| actionlint-fix-cycles | powershell | sonnet5-1m-medium-cli2.1.197 | 1 | 0.7min | 0.1% | $0.13 | 0.06% |
| act-push-debug-loops | bash | sonnet5-1m-medium-cli2.1.197 | 1 | 0.7min | 0.1% | $0.14 | 0.06% |
| fixture-rework | powershell-tool | sonnet5-1m-medium-cli2.1.197 | 1 | 0.8min | 0.1% | $0.16 | 0.07% |
| fixture-rework | typescript-bun | sonnet5-low-cli2.1.197 | 1 | 0.8min | 0.1% | $0.15 | 0.06% |
| bats-setup-issues | bash | sonnet5-1m-medium-cli2.1.197 | 1 | 0.8min | 0.1% | $0.23 | 0.10% |
| act-push-debug-loops | bash | sonnet5-low-cli2.1.197 | 2 | 0.8min | 0.1% | $0.12 | 0.05% |
| act-fixture-paths | default | sonnet5-1m-medium-cli2.1.197 | 1 | 1.0min | 0.1% | $0.27 | 0.11% |
| act-push-debug-loops | default | sonnet5-1m-medium-cli2.1.197 | 1 | 1.0min | 0.1% | $0.27 | 0.12% |
| act-push-debug-loops | powershell-tool | sonnet5-1m-medium-cli2.1.197 | 2 | 1.2min | 0.1% | $0.25 | 0.10% |
| act-push-debug-loops | powershell | sonnet5-1m-medium-cli2.1.197 | 2 | 1.3min | 0.1% | $0.24 | 0.10% |
| repeated-test-reruns | bash | sonnet5-low-cli2.1.197 | 2 | 1.7min | 0.1% | $0.23 | 0.10% |
| repeated-test-reruns | typescript-bun | sonnet5-low-cli2.1.197 | 2 | 1.7min | 0.1% | $0.36 | 0.15% |
| act-push-debug-loops | default | sonnet5-cli2.1.197 | 1 | 1.7min | 0.1% | $0.47 | 0.20% |
| act-push-debug-loops | powershell | sonnet5-cli2.1.197 | 1 | 1.7min | 0.1% | $0.35 | 0.15% |
| actionlint-fix-cycles | typescript-bun | sonnet5-cli2.1.197 | 2 | 1.7min | 0.1% | $0.39 | 0.16% |
| fixture-rework | powershell | sonnet5-1m-medium-cli2.1.197 | 2 | 1.8min | 0.1% | $0.28 | 0.12% |
| bats-setup-issues | bash | sonnet5-cli2.1.197 | 2 | 1.8min | 0.1% | $0.53 | 0.23% |
| ts-type-error-fix-cycles | typescript-bun | sonnet5-low-cli2.1.197 | 2 | 1.8min | 0.1% | $0.39 | 0.17% |
| act-push-debug-loops | powershell-tool | sonnet5-cli2.1.197 | 1 | 2.0min | 0.2% | $0.40 | 0.17% |
| fixture-rework | default | sonnet5-1m-medium-cli2.1.197 | 2 | 2.0min | 0.2% | $0.55 | 0.23% |
| fixture-rework | default | sonnet5-cli2.1.197 | 4 | 2.0min | 0.2% | $0.51 | 0.22% |
| repeated-test-reruns | powershell-tool | sonnet5-low-cli2.1.197 | 1 | 2.3min | 0.2% | $0.31 | 0.13% |
| fixture-rework | typescript-bun | sonnet5-1m-medium-cli2.1.197 | 3 | 2.5min | 0.2% | $0.54 | 0.23% |
| repeated-test-reruns | powershell | sonnet5-low-cli2.1.197 | 3 | 2.7min | 0.2% | $0.41 | 0.17% |
| fixture-rework | powershell | sonnet5-cli2.1.197 | 3 | 2.8min | 0.2% | $0.12 | 0.05% |
| fixture-rework | powershell-tool | sonnet5-cli2.1.197 | 2 | 2.8min | 0.2% | $0.52 | 0.22% |
| act-push-debug-loops | typescript-bun | sonnet5-cli2.1.197 | 1 | 2.8min | 0.2% | $0.71 | 0.30% |
| docker-pwsh-install | powershell | sonnet5-cli2.1.197 | 2 | 3.8min | 0.3% | $0.72 | 0.31% |
| repeated-test-reruns | powershell | sonnet5-1m-medium-cli2.1.197 | 5 | 5.0min | 0.4% | $0.93 | 0.39% |
| act-push-debug-loops | bash | sonnet5-cli2.1.197 | 2 | 5.1min | 0.4% | $1.56 | 0.66% |
| repeated-test-reruns | bash | sonnet5-cli2.1.197 | 4 | 5.3min | 0.4% | $1.63 | 0.69% |
| fixture-rework | typescript-bun | sonnet5-cli2.1.197 | 6 | 5.8min | 0.5% | $1.62 | 0.68% |
| repeated-test-reruns | bash | sonnet5-1m-medium-cli2.1.197 | 6 | 7.0min | 0.6% | $1.63 | 0.69% |
| repeated-test-reruns | default | sonnet5-cli2.1.197 | 3 | 7.0min | 0.6% | $1.79 | 0.76% |
| fixture-rework | bash | sonnet5-cli2.1.197 | 6 | 7.5min | 0.6% | $2.12 | 0.90% |
| repeated-test-reruns | default | sonnet5-1m-medium-cli2.1.197 | 5 | 8.0min | 0.6% | $2.09 | 0.89% |
| act-push-debug-loops | typescript-bun | sonnet5-1m-medium-cli2.1.197 | 4 | 9.7min | 0.8% | $1.89 | 0.80% |
| repeated-test-reruns | typescript-bun | sonnet5-cli2.1.197 | 6 | 9.7min | 0.8% | $2.32 | 0.98% |
| repeated-test-reruns | typescript-bun | sonnet5-1m-medium-cli2.1.197 | 7 | 12.3min | 1.0% | $2.54 | 1.08% |
| repeated-test-reruns | powershell-tool | sonnet5-1m-medium-cli2.1.197 | 5 | 12.7min | 1.0% | $2.39 | 1.01% |
| fixture-rework | bash | sonnet5-1m-medium-cli2.1.197 | 3 | 14.0min | 1.1% | $3.57 | 1.51% |
| repeated-test-reruns | powershell-tool | sonnet5-cli2.1.197 | 7 | 14.3min | 1.2% | $2.14 | 0.91% |
| ts-type-error-fix-cycles | typescript-bun | sonnet5-1m-medium-cli2.1.197 | 7 | 16.6min | 1.3% | $3.49 | 1.48% |
| ts-type-error-fix-cycles | typescript-bun | sonnet5-cli2.1.197 | 7 | 24.0min | 1.9% | $6.58 | 2.79% |
| repeated-test-reruns | powershell | sonnet5-cli2.1.197 | 13 | 29.7min | 2.4% | $2.11 | 0.89% |

</details>

<details>
<summary>Sorted by $ lost (least first)</summary>

| Trap | Language | Model | Fell In | Time Lost | % of Time | $ Lost | % of $ |
|------|------|-------|---------|-----------|-----------|--------|--------|
| fixture-rework | powershell-tool | sonnet5-low-cli2.1.197 | 1 | 0.5min | 0.0% | $0.07 | 0.03% |
| fixture-rework | powershell | sonnet5-cli2.1.197 | 3 | 2.8min | 0.2% | $0.12 | 0.05% |
| act-push-debug-loops | bash | sonnet5-low-cli2.1.197 | 2 | 0.8min | 0.1% | $0.12 | 0.05% |
| actionlint-fix-cycles | powershell | sonnet5-1m-medium-cli2.1.197 | 1 | 0.7min | 0.1% | $0.13 | 0.06% |
| act-push-debug-loops | bash | sonnet5-1m-medium-cli2.1.197 | 1 | 0.7min | 0.1% | $0.14 | 0.06% |
| fixture-rework | typescript-bun | sonnet5-low-cli2.1.197 | 1 | 0.8min | 0.1% | $0.15 | 0.06% |
| fixture-rework | powershell-tool | sonnet5-1m-medium-cli2.1.197 | 1 | 0.8min | 0.1% | $0.16 | 0.07% |
| repeated-test-reruns | default | sonnet5-low-cli2.1.197 | 1 | 0.7min | 0.1% | $0.17 | 0.07% |
| repeated-test-reruns | bash | sonnet5-low-cli2.1.197 | 2 | 1.7min | 0.1% | $0.23 | 0.10% |
| bats-setup-issues | bash | sonnet5-1m-medium-cli2.1.197 | 1 | 0.8min | 0.1% | $0.23 | 0.10% |
| act-push-debug-loops | powershell | sonnet5-1m-medium-cli2.1.197 | 2 | 1.3min | 0.1% | $0.24 | 0.10% |
| act-push-debug-loops | powershell-tool | sonnet5-1m-medium-cli2.1.197 | 2 | 1.2min | 0.1% | $0.25 | 0.10% |
| act-fixture-paths | default | sonnet5-1m-medium-cli2.1.197 | 1 | 1.0min | 0.1% | $0.27 | 0.11% |
| act-push-debug-loops | default | sonnet5-1m-medium-cli2.1.197 | 1 | 1.0min | 0.1% | $0.27 | 0.12% |
| fixture-rework | powershell | sonnet5-1m-medium-cli2.1.197 | 2 | 1.8min | 0.1% | $0.28 | 0.12% |
| repeated-test-reruns | powershell-tool | sonnet5-low-cli2.1.197 | 1 | 2.3min | 0.2% | $0.31 | 0.13% |
| act-push-debug-loops | powershell | sonnet5-cli2.1.197 | 1 | 1.7min | 0.1% | $0.35 | 0.15% |
| repeated-test-reruns | typescript-bun | sonnet5-low-cli2.1.197 | 2 | 1.7min | 0.1% | $0.36 | 0.15% |
| actionlint-fix-cycles | typescript-bun | sonnet5-cli2.1.197 | 2 | 1.7min | 0.1% | $0.39 | 0.16% |
| ts-type-error-fix-cycles | typescript-bun | sonnet5-low-cli2.1.197 | 2 | 1.8min | 0.1% | $0.39 | 0.17% |
| act-push-debug-loops | powershell-tool | sonnet5-cli2.1.197 | 1 | 2.0min | 0.2% | $0.40 | 0.17% |
| repeated-test-reruns | powershell | sonnet5-low-cli2.1.197 | 3 | 2.7min | 0.2% | $0.41 | 0.17% |
| act-push-debug-loops | default | sonnet5-cli2.1.197 | 1 | 1.7min | 0.1% | $0.47 | 0.20% |
| fixture-rework | default | sonnet5-cli2.1.197 | 4 | 2.0min | 0.2% | $0.51 | 0.22% |
| fixture-rework | powershell-tool | sonnet5-cli2.1.197 | 2 | 2.8min | 0.2% | $0.52 | 0.22% |
| bats-setup-issues | bash | sonnet5-cli2.1.197 | 2 | 1.8min | 0.1% | $0.53 | 0.23% |
| fixture-rework | typescript-bun | sonnet5-1m-medium-cli2.1.197 | 3 | 2.5min | 0.2% | $0.54 | 0.23% |
| fixture-rework | default | sonnet5-1m-medium-cli2.1.197 | 2 | 2.0min | 0.2% | $0.55 | 0.23% |
| act-push-debug-loops | typescript-bun | sonnet5-cli2.1.197 | 1 | 2.8min | 0.2% | $0.71 | 0.30% |
| docker-pwsh-install | powershell | sonnet5-cli2.1.197 | 2 | 3.8min | 0.3% | $0.72 | 0.31% |
| repeated-test-reruns | powershell | sonnet5-1m-medium-cli2.1.197 | 5 | 5.0min | 0.4% | $0.93 | 0.39% |
| act-push-debug-loops | bash | sonnet5-cli2.1.197 | 2 | 5.1min | 0.4% | $1.56 | 0.66% |
| fixture-rework | typescript-bun | sonnet5-cli2.1.197 | 6 | 5.8min | 0.5% | $1.62 | 0.68% |
| repeated-test-reruns | bash | sonnet5-1m-medium-cli2.1.197 | 6 | 7.0min | 0.6% | $1.63 | 0.69% |
| repeated-test-reruns | bash | sonnet5-cli2.1.197 | 4 | 5.3min | 0.4% | $1.63 | 0.69% |
| repeated-test-reruns | default | sonnet5-cli2.1.197 | 3 | 7.0min | 0.6% | $1.79 | 0.76% |
| act-push-debug-loops | typescript-bun | sonnet5-1m-medium-cli2.1.197 | 4 | 9.7min | 0.8% | $1.89 | 0.80% |
| repeated-test-reruns | default | sonnet5-1m-medium-cli2.1.197 | 5 | 8.0min | 0.6% | $2.09 | 0.89% |
| repeated-test-reruns | powershell | sonnet5-cli2.1.197 | 13 | 29.7min | 2.4% | $2.11 | 0.89% |
| fixture-rework | bash | sonnet5-cli2.1.197 | 6 | 7.5min | 0.6% | $2.12 | 0.90% |
| repeated-test-reruns | powershell-tool | sonnet5-cli2.1.197 | 7 | 14.3min | 1.2% | $2.14 | 0.91% |
| repeated-test-reruns | typescript-bun | sonnet5-cli2.1.197 | 6 | 9.7min | 0.8% | $2.32 | 0.98% |
| repeated-test-reruns | powershell-tool | sonnet5-1m-medium-cli2.1.197 | 5 | 12.7min | 1.0% | $2.39 | 1.01% |
| repeated-test-reruns | typescript-bun | sonnet5-1m-medium-cli2.1.197 | 7 | 12.3min | 1.0% | $2.54 | 1.08% |
| ts-type-error-fix-cycles | typescript-bun | sonnet5-1m-medium-cli2.1.197 | 7 | 16.6min | 1.3% | $3.49 | 1.48% |
| fixture-rework | bash | sonnet5-1m-medium-cli2.1.197 | 3 | 14.0min | 1.1% | $3.57 | 1.51% |
| ts-type-error-fix-cycles | typescript-bun | sonnet5-cli2.1.197 | 7 | 24.0min | 1.9% | $6.58 | 2.79% |

</details>

<details>
<summary>Sorted by fell-in count (fewest first)</summary>

| Trap | Language | Model | Fell In | Time Lost | % of Time | $ Lost | % of $ |
|------|------|-------|---------|-----------|-----------|--------|--------|
| repeated-test-reruns | default | sonnet5-low-cli2.1.197 | 1 | 0.7min | 0.1% | $0.17 | 0.07% |
| repeated-test-reruns | powershell-tool | sonnet5-low-cli2.1.197 | 1 | 2.3min | 0.2% | $0.31 | 0.13% |
| fixture-rework | powershell-tool | sonnet5-1m-medium-cli2.1.197 | 1 | 0.8min | 0.1% | $0.16 | 0.07% |
| fixture-rework | powershell-tool | sonnet5-low-cli2.1.197 | 1 | 0.5min | 0.0% | $0.07 | 0.03% |
| fixture-rework | typescript-bun | sonnet5-low-cli2.1.197 | 1 | 0.8min | 0.1% | $0.15 | 0.06% |
| act-push-debug-loops | bash | sonnet5-1m-medium-cli2.1.197 | 1 | 0.7min | 0.1% | $0.14 | 0.06% |
| act-push-debug-loops | default | sonnet5-1m-medium-cli2.1.197 | 1 | 1.0min | 0.1% | $0.27 | 0.12% |
| act-push-debug-loops | default | sonnet5-cli2.1.197 | 1 | 1.7min | 0.1% | $0.47 | 0.20% |
| act-push-debug-loops | powershell | sonnet5-cli2.1.197 | 1 | 1.7min | 0.1% | $0.35 | 0.15% |
| act-push-debug-loops | powershell-tool | sonnet5-cli2.1.197 | 1 | 2.0min | 0.2% | $0.40 | 0.17% |
| act-push-debug-loops | typescript-bun | sonnet5-cli2.1.197 | 1 | 2.8min | 0.2% | $0.71 | 0.30% |
| bats-setup-issues | bash | sonnet5-1m-medium-cli2.1.197 | 1 | 0.8min | 0.1% | $0.23 | 0.10% |
| actionlint-fix-cycles | powershell | sonnet5-1m-medium-cli2.1.197 | 1 | 0.7min | 0.1% | $0.13 | 0.06% |
| act-fixture-paths | default | sonnet5-1m-medium-cli2.1.197 | 1 | 1.0min | 0.1% | $0.27 | 0.11% |
| repeated-test-reruns | bash | sonnet5-low-cli2.1.197 | 2 | 1.7min | 0.1% | $0.23 | 0.10% |
| repeated-test-reruns | typescript-bun | sonnet5-low-cli2.1.197 | 2 | 1.7min | 0.1% | $0.36 | 0.15% |
| fixture-rework | default | sonnet5-1m-medium-cli2.1.197 | 2 | 2.0min | 0.2% | $0.55 | 0.23% |
| fixture-rework | powershell | sonnet5-1m-medium-cli2.1.197 | 2 | 1.8min | 0.1% | $0.28 | 0.12% |
| fixture-rework | powershell-tool | sonnet5-cli2.1.197 | 2 | 2.8min | 0.2% | $0.52 | 0.22% |
| ts-type-error-fix-cycles | typescript-bun | sonnet5-low-cli2.1.197 | 2 | 1.8min | 0.1% | $0.39 | 0.17% |
| act-push-debug-loops | bash | sonnet5-cli2.1.197 | 2 | 5.1min | 0.4% | $1.56 | 0.66% |
| act-push-debug-loops | bash | sonnet5-low-cli2.1.197 | 2 | 0.8min | 0.1% | $0.12 | 0.05% |
| act-push-debug-loops | powershell | sonnet5-1m-medium-cli2.1.197 | 2 | 1.3min | 0.1% | $0.24 | 0.10% |
| act-push-debug-loops | powershell-tool | sonnet5-1m-medium-cli2.1.197 | 2 | 1.2min | 0.1% | $0.25 | 0.10% |
| docker-pwsh-install | powershell | sonnet5-cli2.1.197 | 2 | 3.8min | 0.3% | $0.72 | 0.31% |
| bats-setup-issues | bash | sonnet5-cli2.1.197 | 2 | 1.8min | 0.1% | $0.53 | 0.23% |
| actionlint-fix-cycles | typescript-bun | sonnet5-cli2.1.197 | 2 | 1.7min | 0.1% | $0.39 | 0.16% |
| repeated-test-reruns | default | sonnet5-cli2.1.197 | 3 | 7.0min | 0.6% | $1.79 | 0.76% |
| repeated-test-reruns | powershell | sonnet5-low-cli2.1.197 | 3 | 2.7min | 0.2% | $0.41 | 0.17% |
| fixture-rework | bash | sonnet5-1m-medium-cli2.1.197 | 3 | 14.0min | 1.1% | $3.57 | 1.51% |
| fixture-rework | powershell | sonnet5-cli2.1.197 | 3 | 2.8min | 0.2% | $0.12 | 0.05% |
| fixture-rework | typescript-bun | sonnet5-1m-medium-cli2.1.197 | 3 | 2.5min | 0.2% | $0.54 | 0.23% |
| repeated-test-reruns | bash | sonnet5-cli2.1.197 | 4 | 5.3min | 0.4% | $1.63 | 0.69% |
| fixture-rework | default | sonnet5-cli2.1.197 | 4 | 2.0min | 0.2% | $0.51 | 0.22% |
| act-push-debug-loops | typescript-bun | sonnet5-1m-medium-cli2.1.197 | 4 | 9.7min | 0.8% | $1.89 | 0.80% |
| repeated-test-reruns | default | sonnet5-1m-medium-cli2.1.197 | 5 | 8.0min | 0.6% | $2.09 | 0.89% |
| repeated-test-reruns | powershell | sonnet5-1m-medium-cli2.1.197 | 5 | 5.0min | 0.4% | $0.93 | 0.39% |
| repeated-test-reruns | powershell-tool | sonnet5-1m-medium-cli2.1.197 | 5 | 12.7min | 1.0% | $2.39 | 1.01% |
| repeated-test-reruns | bash | sonnet5-1m-medium-cli2.1.197 | 6 | 7.0min | 0.6% | $1.63 | 0.69% |
| repeated-test-reruns | typescript-bun | sonnet5-cli2.1.197 | 6 | 9.7min | 0.8% | $2.32 | 0.98% |
| fixture-rework | bash | sonnet5-cli2.1.197 | 6 | 7.5min | 0.6% | $2.12 | 0.90% |
| fixture-rework | typescript-bun | sonnet5-cli2.1.197 | 6 | 5.8min | 0.5% | $1.62 | 0.68% |
| repeated-test-reruns | powershell-tool | sonnet5-cli2.1.197 | 7 | 14.3min | 1.2% | $2.14 | 0.91% |
| repeated-test-reruns | typescript-bun | sonnet5-1m-medium-cli2.1.197 | 7 | 12.3min | 1.0% | $2.54 | 1.08% |
| ts-type-error-fix-cycles | typescript-bun | sonnet5-1m-medium-cli2.1.197 | 7 | 16.6min | 1.3% | $3.49 | 1.48% |
| ts-type-error-fix-cycles | typescript-bun | sonnet5-cli2.1.197 | 7 | 24.0min | 1.9% | $6.58 | 2.79% |
| repeated-test-reruns | powershell | sonnet5-cli2.1.197 | 13 | 29.7min | 2.4% | $2.11 | 0.89% |

</details>

#### Trap Descriptions

- **act-fixture-paths**: Test fixtures not found inside the act Docker container due to path issues.
- **act-push-debug-loops**: Agent ran `act push` more than twice, indicating repeated workflow debugging.
- **actionlint-fix-cycles**: Workflow YAML required 3+ actionlint runs and 2+ fixes to pass.
- **bats-setup-issues**: Agent struggled with bats-core test framework setup or load helpers.
- **docker-pwsh-install**: Multiple Docker test runs trying to figure out how to install PowerShell in act's container.
- **fixture-rework**: Agent wrote, broke, and rewrote test fixture data (4+ fixture-related commands).
- **repeated-test-reruns**: Same test command executed 4+ times without the underlying code changing.
- **ts-type-error-fix-cycles**: TypeScript type errors caught by `tsc --noEmit` hooks; each requires a fix cycle.

#### Column Definitions

- **Fell In**: Number of runs (within that language/model) where this trap was detected.
- **Time Lost**: Estimated wall-clock seconds wasted on the trap, based on the number of
  wasted commands multiplied by a per-command cost (15–25s for typical Bash, 45s for Docker runs, 50s for act push).
- **% of Time**: Time Lost as a percentage of total benchmark duration.
- **$ Lost**: Proportional cost impact, calculated as (Time Lost / Run Duration) × Run Cost for each affected run.
- **% of $**: $ Lost as a percentage of total benchmark cost.

### Traps by Language/Model/Effort

| Language | Model | Runs | Traps | Time Lost | % of Time | $ Lost | % of $ |
|------|-------|------|-------|-----------|-----------|--------|--------|
| bash | sonnet5-1m-medium-cli2.1.197 | 7 | 11 | 22.4min | 1.8% | $5.57 | 2.35% |
| bash | sonnet5-cli2.1.197 | 7 | 14 | 19.7min | 1.6% | $5.84 | 2.47% |
| bash | sonnet5-low-cli2.1.197 | 3 | 4 | 2.5min | 0.2% | $0.35 | 0.15% |
| default | sonnet5-1m-medium-cli2.1.197 | 7 | 9 | 12.0min | 1.0% | $3.18 | 1.35% |
| default | sonnet5-cli2.1.197 | 7 | 8 | 10.7min | 0.9% | $2.77 | 1.17% |
| default | sonnet5-low-cli2.1.197 | 3 | 1 | 0.7min | 0.1% | $0.17 | 0.07% |
| powershell | sonnet5-1m-medium-cli2.1.197 | 7 | 10 | 8.8min | 0.7% | $1.59 | 0.67% |
| powershell | sonnet5-cli2.1.197 | 7 | 19 | 37.8min | 3.0% | $3.30 | 1.40% |
| powershell | sonnet5-low-cli2.1.197 | 3 | 3 | 2.7min | 0.2% | $0.41 | 0.17% |
| powershell-tool | sonnet5-1m-medium-cli2.1.197 | 7 | 8 | 14.6min | 1.2% | $2.79 | 1.18% |
| powershell-tool | sonnet5-cli2.1.197 | 7 | 10 | 19.1min | 1.5% | $3.06 | 1.30% |
| powershell-tool | sonnet5-low-cli2.1.197 | 2 | 2 | 2.8min | 0.2% | $0.38 | 0.16% |
| typescript-bun | sonnet5-1m-medium-cli2.1.197 | 7 | 21 | 41.1min | 3.3% | $8.48 | 3.59% |
| typescript-bun | sonnet5-cli2.1.197 | 7 | 22 | 43.9min | 3.5% | $11.62 | 4.92% |
| typescript-bun | sonnet5-low-cli2.1.197 | 2 | 5 | 4.2min | 0.3% | $0.90 | 0.38% |


<details>
<summary>Sorted by time lost (least first)</summary>

| Language | Model | Runs | Traps | Time Lost | % of Time | $ Lost | % of $ |
|------|-------|------|-------|-----------|-----------|--------|--------|
| default | sonnet5-low-cli2.1.197 | 3 | 1 | 0.7min | 0.1% | $0.17 | 0.07% |
| bash | sonnet5-low-cli2.1.197 | 3 | 4 | 2.5min | 0.2% | $0.35 | 0.15% |
| powershell | sonnet5-low-cli2.1.197 | 3 | 3 | 2.7min | 0.2% | $0.41 | 0.17% |
| powershell-tool | sonnet5-low-cli2.1.197 | 2 | 2 | 2.8min | 0.2% | $0.38 | 0.16% |
| typescript-bun | sonnet5-low-cli2.1.197 | 2 | 5 | 4.2min | 0.3% | $0.90 | 0.38% |
| powershell | sonnet5-1m-medium-cli2.1.197 | 7 | 10 | 8.8min | 0.7% | $1.59 | 0.67% |
| default | sonnet5-cli2.1.197 | 7 | 8 | 10.7min | 0.9% | $2.77 | 1.17% |
| default | sonnet5-1m-medium-cli2.1.197 | 7 | 9 | 12.0min | 1.0% | $3.18 | 1.35% |
| powershell-tool | sonnet5-1m-medium-cli2.1.197 | 7 | 8 | 14.6min | 1.2% | $2.79 | 1.18% |
| powershell-tool | sonnet5-cli2.1.197 | 7 | 10 | 19.1min | 1.5% | $3.06 | 1.30% |
| bash | sonnet5-cli2.1.197 | 7 | 14 | 19.7min | 1.6% | $5.84 | 2.47% |
| bash | sonnet5-1m-medium-cli2.1.197 | 7 | 11 | 22.4min | 1.8% | $5.57 | 2.35% |
| powershell | sonnet5-cli2.1.197 | 7 | 19 | 37.8min | 3.0% | $3.30 | 1.40% |
| typescript-bun | sonnet5-1m-medium-cli2.1.197 | 7 | 21 | 41.1min | 3.3% | $8.48 | 3.59% |
| typescript-bun | sonnet5-cli2.1.197 | 7 | 22 | 43.9min | 3.5% | $11.62 | 4.92% |

</details>

<details>
<summary>Sorted by $ lost (least first)</summary>

| Language | Model | Runs | Traps | Time Lost | % of Time | $ Lost | % of $ |
|------|-------|------|-------|-----------|-----------|--------|--------|
| default | sonnet5-low-cli2.1.197 | 3 | 1 | 0.7min | 0.1% | $0.17 | 0.07% |
| bash | sonnet5-low-cli2.1.197 | 3 | 4 | 2.5min | 0.2% | $0.35 | 0.15% |
| powershell-tool | sonnet5-low-cli2.1.197 | 2 | 2 | 2.8min | 0.2% | $0.38 | 0.16% |
| powershell | sonnet5-low-cli2.1.197 | 3 | 3 | 2.7min | 0.2% | $0.41 | 0.17% |
| typescript-bun | sonnet5-low-cli2.1.197 | 2 | 5 | 4.2min | 0.3% | $0.90 | 0.38% |
| powershell | sonnet5-1m-medium-cli2.1.197 | 7 | 10 | 8.8min | 0.7% | $1.59 | 0.67% |
| default | sonnet5-cli2.1.197 | 7 | 8 | 10.7min | 0.9% | $2.77 | 1.17% |
| powershell-tool | sonnet5-1m-medium-cli2.1.197 | 7 | 8 | 14.6min | 1.2% | $2.79 | 1.18% |
| powershell-tool | sonnet5-cli2.1.197 | 7 | 10 | 19.1min | 1.5% | $3.06 | 1.30% |
| default | sonnet5-1m-medium-cli2.1.197 | 7 | 9 | 12.0min | 1.0% | $3.18 | 1.35% |
| powershell | sonnet5-cli2.1.197 | 7 | 19 | 37.8min | 3.0% | $3.30 | 1.40% |
| bash | sonnet5-1m-medium-cli2.1.197 | 7 | 11 | 22.4min | 1.8% | $5.57 | 2.35% |
| bash | sonnet5-cli2.1.197 | 7 | 14 | 19.7min | 1.6% | $5.84 | 2.47% |
| typescript-bun | sonnet5-1m-medium-cli2.1.197 | 7 | 21 | 41.1min | 3.3% | $8.48 | 3.59% |
| typescript-bun | sonnet5-cli2.1.197 | 7 | 22 | 43.9min | 3.5% | $11.62 | 4.92% |

</details>

### Prompt Cache Savings

| Status | Runs | $ Saved | % of $ |
|--------|------|---------|--------|
| Full hit (100%) | 0 | $0.00 | 0.00% |
| Partial | 81 | $7.33 | 3.10% |
| Miss | 2 | $0.00 | 0.00% |

## Test Quality Evaluation

### Structural Metrics by Language/Model/Effort

Automated analysis of test files: test count, assertion count, and test-to-code line ratio.

| Language | Model | Avg Tests | Avg Assertions | Avg Assert/Test | Avg Test:Code Ratio |
|------|-------|-----------|----------------|-----------------|---------------------|
| bash | sonnet5 | 34.4 | 73.3 | 2.1 | 0.89 |
| bash | sonnet5-1m-medium | 27.6 | 71.3 | 2.6 | 1.22 |
| bash | sonnet5-low | 22.3 | 49.0 | 2.2 | 1.05 |
| default | sonnet5 | 22.0 | 41.1 | 1.9 | 0.86 |
| default | sonnet5-1m-medium | 32.9 | 56.1 | 1.7 | 1.26 |
| default | sonnet5-low | 26.0 | 37.0 | 1.4 | 0.93 |
| powershell | sonnet5 | 49.4 | 93.0 | 1.9 | 6.06 |
| powershell | sonnet5-1m-medium | 30.3 | 56.0 | 1.8 | 2.37 |
| powershell | sonnet5-low | 27.7 | 45.3 | 1.6 | 3.82 |
| powershell-tool | sonnet5 | 45.7 | 83.1 | 1.8 | 5.24 |
| powershell-tool | sonnet5-1m-medium | 34.1 | 58.3 | 1.7 | 3.50 |
| powershell-tool | sonnet5-low | 26.5 | 47.0 | 1.8 | 6.87 |
| typescript-bun | sonnet5 | 45.1 | 83.9 | 1.9 | 1.57 |
| typescript-bun | sonnet5-1m-medium | 27.3 | 51.6 | 1.9 | 1.12 |
| typescript-bun | sonnet5-low | 21.0 | 33.0 | 1.6 | 0.88 |


<details>
<summary>Sorted by avg tests (most first)</summary>

| Language | Model | Avg Tests | Avg Assertions | Avg Assert/Test | Avg Test:Code Ratio |
|------|-------|-----------|----------------|-----------------|---------------------|
| powershell | sonnet5 | 49.4 | 93.0 | 1.9 | 6.06 |
| powershell-tool | sonnet5 | 45.7 | 83.1 | 1.8 | 5.24 |
| typescript-bun | sonnet5 | 45.1 | 83.9 | 1.9 | 1.57 |
| bash | sonnet5 | 34.4 | 73.3 | 2.1 | 0.89 |
| powershell-tool | sonnet5-1m-medium | 34.1 | 58.3 | 1.7 | 3.50 |
| default | sonnet5-1m-medium | 32.9 | 56.1 | 1.7 | 1.26 |
| powershell | sonnet5-1m-medium | 30.3 | 56.0 | 1.8 | 2.37 |
| powershell | sonnet5-low | 27.7 | 45.3 | 1.6 | 3.82 |
| bash | sonnet5-1m-medium | 27.6 | 71.3 | 2.6 | 1.22 |
| typescript-bun | sonnet5-1m-medium | 27.3 | 51.6 | 1.9 | 1.12 |
| powershell-tool | sonnet5-low | 26.5 | 47.0 | 1.8 | 6.87 |
| default | sonnet5-low | 26.0 | 37.0 | 1.4 | 0.93 |
| bash | sonnet5-low | 22.3 | 49.0 | 2.2 | 1.05 |
| default | sonnet5 | 22.0 | 41.1 | 1.9 | 0.86 |
| typescript-bun | sonnet5-low | 21.0 | 33.0 | 1.6 | 0.88 |

</details>

<details>
<summary>Sorted by avg assertions (most first)</summary>

| Language | Model | Avg Tests | Avg Assertions | Avg Assert/Test | Avg Test:Code Ratio |
|------|-------|-----------|----------------|-----------------|---------------------|
| powershell | sonnet5 | 49.4 | 93.0 | 1.9 | 6.06 |
| typescript-bun | sonnet5 | 45.1 | 83.9 | 1.9 | 1.57 |
| powershell-tool | sonnet5 | 45.7 | 83.1 | 1.8 | 5.24 |
| bash | sonnet5 | 34.4 | 73.3 | 2.1 | 0.89 |
| bash | sonnet5-1m-medium | 27.6 | 71.3 | 2.6 | 1.22 |
| powershell-tool | sonnet5-1m-medium | 34.1 | 58.3 | 1.7 | 3.50 |
| default | sonnet5-1m-medium | 32.9 | 56.1 | 1.7 | 1.26 |
| powershell | sonnet5-1m-medium | 30.3 | 56.0 | 1.8 | 2.37 |
| typescript-bun | sonnet5-1m-medium | 27.3 | 51.6 | 1.9 | 1.12 |
| bash | sonnet5-low | 22.3 | 49.0 | 2.2 | 1.05 |
| powershell-tool | sonnet5-low | 26.5 | 47.0 | 1.8 | 6.87 |
| powershell | sonnet5-low | 27.7 | 45.3 | 1.6 | 3.82 |
| default | sonnet5 | 22.0 | 41.1 | 1.9 | 0.86 |
| default | sonnet5-low | 26.0 | 37.0 | 1.4 | 0.93 |
| typescript-bun | sonnet5-low | 21.0 | 33.0 | 1.6 | 0.88 |

</details>

<details>
<summary>Sorted by avg test:code ratio (highest first)</summary>

| Language | Model | Avg Tests | Avg Assertions | Avg Assert/Test | Avg Test:Code Ratio |
|------|-------|-----------|----------------|-----------------|---------------------|
| powershell-tool | sonnet5-low | 26.5 | 47.0 | 1.8 | 6.87 |
| powershell | sonnet5 | 49.4 | 93.0 | 1.9 | 6.06 |
| powershell-tool | sonnet5 | 45.7 | 83.1 | 1.8 | 5.24 |
| powershell | sonnet5-low | 27.7 | 45.3 | 1.6 | 3.82 |
| powershell-tool | sonnet5-1m-medium | 34.1 | 58.3 | 1.7 | 3.50 |
| powershell | sonnet5-1m-medium | 30.3 | 56.0 | 1.8 | 2.37 |
| typescript-bun | sonnet5 | 45.1 | 83.9 | 1.9 | 1.57 |
| default | sonnet5-1m-medium | 32.9 | 56.1 | 1.7 | 1.26 |
| bash | sonnet5-1m-medium | 27.6 | 71.3 | 2.6 | 1.22 |
| typescript-bun | sonnet5-1m-medium | 27.3 | 51.6 | 1.9 | 1.12 |
| bash | sonnet5-low | 22.3 | 49.0 | 2.2 | 1.05 |
| default | sonnet5-low | 26.0 | 37.0 | 1.4 | 0.93 |
| bash | sonnet5 | 34.4 | 73.3 | 2.1 | 0.89 |
| typescript-bun | sonnet5-low | 21.0 | 33.0 | 1.6 | 0.88 |
| default | sonnet5 | 22.0 | 41.1 | 1.9 | 0.86 |

</details>


<details>
<summary>Per-run structural metrics</summary>

| Task | Language | Model | Tests | Assertions | Assert/Test | Test Lines | Impl Lines | Test:Code |
|------|------|-------|-------|------------|-------------|------------|------------|-----------|
| Semantic Version Bumper | bash | sonnet5 | 7 | 20 | 2.9 | 77 | 238 | 0.32 |
| Semantic Version Bumper | bash | sonnet5-1m-medium | 32 | 72 | 2.2 | 349 | 240 | 1.45 |
| Semantic Version Bumper | bash | sonnet5-low | 20 | 31 | 1.6 | 201 | 260 | 0.77 |
| Semantic Version Bumper | default | sonnet5 | 38 | 60 | 1.6 | 438 | 336 | 1.30 |
| Semantic Version Bumper | default | sonnet5-1m-medium | 37 | 59 | 1.6 | 454 | 218 | 2.08 |
| Semantic Version Bumper | default | sonnet5-low | 35 | 44 | 1.3 | 282 | 223 | 1.26 |
| Semantic Version Bumper | powershell | sonnet5 | 43 | 87 | 2.0 | 514 | 89 | 5.78 |
| Semantic Version Bumper | powershell | sonnet5-1m-medium | 36 | 64 | 1.8 | 321 | 143 | 2.24 |
| Semantic Version Bumper | powershell | sonnet5-low | 35 | 52 | 1.5 | 259 | 41 | 6.32 |
| Semantic Version Bumper | powershell-tool | sonnet5 | 51 | 88 | 1.7 | 649 | 72 | 9.01 |
| Semantic Version Bumper | powershell-tool | sonnet5-1m-medium | 40 | 61 | 1.5 | 312 | 172 | 1.81 |
| Semantic Version Bumper | powershell-tool | sonnet5-low | 29 | 48 | 1.7 | 239 | 35 | 6.83 |
| Semantic Version Bumper | typescript-bun | sonnet5 | 51 | 88 | 1.7 | 869 | 470 | 1.85 |
| Semantic Version Bumper | typescript-bun | sonnet5-1m-medium | 24 | 43 | 1.8 | 391 | 272 | 1.44 |
| Semantic Version Bumper | typescript-bun | sonnet5-low | 25 | 40 | 1.6 | 272 | 386 | 0.70 |
| PR Label Assigner | bash | sonnet5 | 52 | 100 | 1.9 | 517 | 447 | 1.16 |
| PR Label Assigner | bash | sonnet5-1m-medium | 24 | 54 | 2.2 | 192 | 246 | 0.78 |
| PR Label Assigner | bash | sonnet5-low | 25 | 51 | 2.0 | 189 | 159 | 1.19 |
| PR Label Assigner | default | sonnet5 | 30 | 57 | 1.9 | 323 | 319 | 1.01 |
| PR Label Assigner | default | sonnet5-1m-medium | 23 | 43 | 1.9 | 194 | 239 | 0.81 |
| PR Label Assigner | default | sonnet5-low | 18 | 12 | 0.7 | 209 | 333 | 0.63 |
| PR Label Assigner | powershell | sonnet5 | 58 | 77 | 1.3 | 504 | 215 | 2.34 |
| PR Label Assigner | powershell | sonnet5-1m-medium | 35 | 51 | 1.5 | 277 | 180 | 1.54 |
| PR Label Assigner | powershell | sonnet5-low | 21 | 39 | 1.9 | 224 | 248 | 0.90 |
| PR Label Assigner | powershell-tool | sonnet5 | 59 | 92 | 1.6 | 472 | 71 | 6.65 |
| PR Label Assigner | powershell-tool | sonnet5-1m-medium | 28 | 37 | 1.3 | 227 | 40 | 5.67 |
| PR Label Assigner | powershell-tool | sonnet5-low | 24 | 46 | 1.9 | 242 | 35 | 6.91 |
| PR Label Assigner | typescript-bun | sonnet5 | 35 | 40 | 1.1 | 317 | 404 | 0.78 |
| PR Label Assigner | typescript-bun | sonnet5-1m-medium | 35 | 55 | 1.6 | 266 | 323 | 0.82 |
| PR Label Assigner | typescript-bun | sonnet5-low | 17 | 26 | 1.5 | 161 | 154 | 1.05 |
| Dependency License Checker | bash | sonnet5 | 39 | 95 | 2.4 | 521 | 395 | 1.32 |
| Dependency License Checker | bash | sonnet5-1m-medium | 35 | 88 | 2.5 | 337 | 334 | 1.01 |
| Dependency License Checker | bash | sonnet5-low | 22 | 65 | 3.0 | 218 | 183 | 1.19 |
| Dependency License Checker | default | sonnet5 | 8 | 30 | 3.8 | 218 | 274 | 0.80 |
| Dependency License Checker | default | sonnet5-1m-medium | 58 | 76 | 1.3 | 670 | 389 | 1.72 |
| Dependency License Checker | default | sonnet5-low | 25 | 55 | 2.2 | 294 | 324 | 0.91 |
| Dependency License Checker | powershell | sonnet5 | 37 | 52 | 1.4 | 384 | 181 | 2.12 |
| Dependency License Checker | powershell | sonnet5-1m-medium | 27 | 47 | 1.7 | 234 | 205 | 1.14 |
| Dependency License Checker | powershell | sonnet5-low | 27 | 45 | 1.7 | 220 | 52 | 4.23 |
| Dependency License Checker | powershell-tool | sonnet5 | 31 | 58 | 1.9 | 340 | 87 | 3.91 |
| Dependency License Checker | powershell-tool | sonnet5-1m-medium | 53 | 60 | 1.1 | 430 | 77 | 5.58 |
| Dependency License Checker | typescript-bun | sonnet5 | 40 | 65 | 1.6 | 579 | 385 | 1.50 |
| Dependency License Checker | typescript-bun | sonnet5-1m-medium | 29 | 60 | 2.1 | 370 | 452 | 0.82 |
| Test Results Aggregator | bash | sonnet5 | 24 | 30 | 1.2 | 221 | 578 | 0.38 |
| Test Results Aggregator | bash | sonnet5-1m-medium | 34 | 68 | 2.0 | 279 | 317 | 0.88 |
| Test Results Aggregator | default | sonnet5 | 12 | 28 | 2.3 | 317 | 430 | 0.74 |
| Test Results Aggregator | default | sonnet5-1m-medium | 26 | 56 | 2.2 | 339 | 317 | 1.07 |
| Test Results Aggregator | powershell | sonnet5 | 72 | 128 | 1.8 | 597 | 173 | 3.45 |
| Test Results Aggregator | powershell | sonnet5-1m-medium | 36 | 72 | 2.0 | 382 | 269 | 1.42 |
| Test Results Aggregator | powershell-tool | sonnet5 | 23 | 30 | 1.3 | 292 | 51 | 5.73 |
| Test Results Aggregator | powershell-tool | sonnet5-1m-medium | 30 | 69 | 2.3 | 271 | 333 | 0.81 |
| Test Results Aggregator | typescript-bun | sonnet5 | 34 | 96 | 2.8 | 661 | 456 | 1.45 |
| Test Results Aggregator | typescript-bun | sonnet5-1m-medium | 28 | 60 | 2.1 | 332 | 384 | 0.86 |
| Environment Matrix Generator | bash | sonnet5 | 27 | 73 | 2.7 | 263 | 327 | 0.80 |
| Environment Matrix Generator | bash | sonnet5-1m-medium | 22 | 32 | 1.5 | 217 | 139 | 1.56 |
| Environment Matrix Generator | default | sonnet5 | 43 | 43 | 1.0 | 433 | 422 | 1.03 |
| Environment Matrix Generator | default | sonnet5-1m-medium | 35 | 59 | 1.7 | 360 | 362 | 0.99 |
| Environment Matrix Generator | powershell | sonnet5 | 47 | 110 | 2.3 | 467 | 41 | 11.39 |
| Environment Matrix Generator | powershell | sonnet5-1m-medium | 41 | 65 | 1.6 | 406 | 55 | 7.38 |
| Environment Matrix Generator | powershell-tool | sonnet5 | 49 | 103 | 2.1 | 531 | 332 | 1.60 |
| Environment Matrix Generator | powershell-tool | sonnet5-1m-medium | 23 | 47 | 2.0 | 256 | 201 | 1.27 |
| Environment Matrix Generator | typescript-bun | sonnet5 | 40 | 76 | 1.9 | 630 | 287 | 2.20 |
| Environment Matrix Generator | typescript-bun | sonnet5-1m-medium | 16 | 30 | 1.9 | 262 | 225 | 1.16 |
| Artifact Cleanup Script | bash | sonnet5 | 22 | 13 | 0.6 | 209 | 293 | 0.71 |
| Artifact Cleanup Script | bash | sonnet5-1m-medium | 21 | 84 | 4.0 | 330 | 193 | 1.71 |
| Artifact Cleanup Script | default | sonnet5 | 10 | 22 | 2.2 | 103 | 0 | 0.00 |
| Artifact Cleanup Script | default | sonnet5-1m-medium | 21 | 48 | 2.3 | 364 | 486 | 0.75 |
| Artifact Cleanup Script | powershell | sonnet5 | 57 | 117 | 2.1 | 570 | 122 | 4.67 |
| Artifact Cleanup Script | powershell | sonnet5-1m-medium | 19 | 57 | 3.0 | 262 | 165 | 1.59 |
| Artifact Cleanup Script | powershell-tool | sonnet5 | 41 | 109 | 2.7 | 495 | 128 | 3.87 |
| Artifact Cleanup Script | powershell-tool | sonnet5-1m-medium | 32 | 68 | 2.1 | 304 | 74 | 4.11 |
| Artifact Cleanup Script | typescript-bun | sonnet5 | 53 | 107 | 2.0 | 700 | 578 | 1.21 |
| Artifact Cleanup Script | typescript-bun | sonnet5-1m-medium | 22 | 41 | 1.9 | 396 | 343 | 1.15 |
| Secret Rotation Validator | bash | sonnet5 | 70 | 182 | 2.6 | 631 | 416 | 1.52 |
| Secret Rotation Validator | bash | sonnet5-1m-medium | 25 | 101 | 4.0 | 299 | 263 | 1.14 |
| Secret Rotation Validator | default | sonnet5 | 13 | 48 | 3.7 | 326 | 280 | 1.16 |
| Secret Rotation Validator | default | sonnet5-1m-medium | 30 | 52 | 1.7 | 320 | 226 | 1.42 |
| Secret Rotation Validator | powershell | sonnet5 | 32 | 80 | 2.5 | 582 | 46 | 12.65 |
| Secret Rotation Validator | powershell | sonnet5-1m-medium | 18 | 36 | 2.0 | 189 | 147 | 1.29 |
| Secret Rotation Validator | powershell-tool | sonnet5 | 66 | 102 | 1.5 | 564 | 96 | 5.88 |
| Secret Rotation Validator | powershell-tool | sonnet5-1m-medium | 33 | 66 | 2.0 | 366 | 70 | 5.23 |
| Secret Rotation Validator | typescript-bun | sonnet5 | 63 | 115 | 1.8 | 927 | 461 | 2.01 |
| Secret Rotation Validator | typescript-bun | sonnet5-1m-medium | 37 | 72 | 1.9 | 466 | 292 | 1.60 |

</details>

## Per-Run Results

*Tests Quality = Overall (1-5) from LLM-as-judge of generated test code (dimensions: coverage, rigor, design). `—` = no judge data.*

| Task | Language | Model | Duration | Turns | Errors | Cost | Tests Quality | Chosen | Status |
|------|----------|-------|----------|-------|--------|------|-----------|--------|--------|
| Artifact Cleanup Script | bash | sonnet5 | 11.8min | 59 | 4 | $3.37 | — | bash | ok |
| Artifact Cleanup Script | bash | sonnet5-1m-medium | 16.9min | 80 | 7 | $3.35 | — | bash | ok |
| Artifact Cleanup Script | default | sonnet5 | 18.0min | 76 | 1 | $3.61 | — | powershell | ok |
| Artifact Cleanup Script | default | sonnet5-1m-medium | 11.5min | 86 | 3 | $3.10 | — | python | ok |
| Artifact Cleanup Script | powershell | sonnet5 | 23.4min | 98 | 3 | $5.42 | — | powershell | ok |
| Artifact Cleanup Script | powershell | sonnet5-1m-medium | 11.3min | 38 | 0 | $1.90 | — | powershell | ok |
| Artifact Cleanup Script | powershell-tool | sonnet5 | 21.2min | 79 | 0 | $4.33 | — | powershell | ok |
| Artifact Cleanup Script | powershell-tool | sonnet5-1m-medium | 16.6min | 64 | 2 | $3.28 | — | powershell | ok |
| Artifact Cleanup Script | typescript-bun | sonnet5 | 23.5min | 150 | 2 | $6.00 | — | typescript | ok |
| Artifact Cleanup Script | typescript-bun | sonnet5-1m-medium | 13.7min | 109 | 0 | $3.28 | — | typescript | ok |
| Dependency License Checker | bash | sonnet5 | 17.4min | 105 | 3 | $5.57 | — | bash | ok |
| Dependency License Checker | bash | sonnet5-1m-medium | 11.0min | 74 | 4 | $2.43 | — | bash | ok |
| Dependency License Checker | bash | sonnet5-low | 12.3min | 49 | 4 | $1.36 | — | bash | ok |
| Dependency License Checker | default | sonnet5 | 9.9min | 39 | 1 | $1.99 | — | python | ok |
| Dependency License Checker | default | sonnet5-1m-medium | 8.9min | 73 | 0 | $2.48 | — | python | ok |
| Dependency License Checker | default | sonnet5-low | 4.9min | 34 | 0 | $1.13 | — | python | ok |
| Dependency License Checker | powershell | sonnet5 | 16.8min | 80 | 0 | $3.03 | — | powershell | ok |
| Dependency License Checker | powershell | sonnet5-1m-medium | 13.5min | 52 | 3 | $2.14 | — | powershell | ok |
| Dependency License Checker | powershell | sonnet5-low | 7.6min | 39 | 0 | $1.17 | — | powershell | ok |
| Dependency License Checker | powershell-tool | sonnet5 | 14.6min | 58 | 1 | $2.80 | — | powershell | ok |
| Dependency License Checker | powershell-tool | sonnet5-1m-medium | 18.8min | 70 | 0 | $4.02 | — | powershell | ok |
| Dependency License Checker | typescript-bun | sonnet5 | 18.4min | 137 | 11 | $5.28 | — | typescript | ok |
| Dependency License Checker | typescript-bun | sonnet5-1m-medium | 13.6min | 93 | 1 | $2.82 | — | typescript | ok |
| Environment Matrix Generator | bash | sonnet5 | 26.2min | 150 | 9 | $8.03 | — | bash | ok |
| Environment Matrix Generator | bash | sonnet5-1m-medium | 14.2min | 67 | 0 | $2.90 | — | bash | ok |
| Environment Matrix Generator | default | sonnet5 | 16.4min | 94 | 2 | $5.01 | — | python | ok |
| Environment Matrix Generator | default | sonnet5-1m-medium | 6.9min | 59 | 0 | $1.72 | — | python | ok |
| Environment Matrix Generator | powershell | sonnet5 | 29.5min | 103 | 0 | $6.22 | — | powershell | ok |
| Environment Matrix Generator | powershell | sonnet5-1m-medium | 16.5min | 99 | 1 | $3.46 | — | powershell | ok |
| Environment Matrix Generator | powershell-tool | sonnet5 | 25.4min | 82 | 0 | $5.48 | — | powershell | ok |
| Environment Matrix Generator | powershell-tool | sonnet5-1m-medium | 15.8min | 55 | 0 | $2.82 | — | powershell | ok |
| Environment Matrix Generator | typescript-bun | sonnet5 | 19.7min | 75 | 1 | $4.76 | — | typescript | ok |
| Environment Matrix Generator | typescript-bun | sonnet5-1m-medium | 17.0min | 87 | 4 | $3.12 | — | typescript | ok |
| PR Label Assigner | bash | sonnet5 | 30.0min | 0 | 2 | $0.00 | — | bash | timeout |
| PR Label Assigner | bash | sonnet5-1m-medium | 14.3min | 101 | 5 | $3.99 | — | bash | ok |
| PR Label Assigner | bash | sonnet5-low | 3.4min | 28 | 1 | $0.76 | — | bash | ok |
| PR Label Assigner | default | sonnet5 | 11.6min | 80 | 0 | $3.61 | — | python | ok |
| PR Label Assigner | default | sonnet5-1m-medium | 9.5min | 64 | 1 | $2.04 | — | powershell | ok |
| PR Label Assigner | default | sonnet5-low | 3.7min | 24 | 0 | $0.75 | — | python | ok |
| PR Label Assigner | powershell | sonnet5 | 30.0min | 0 | 1 | $0.00 | — | powershell | timeout |
| PR Label Assigner | powershell | sonnet5-1m-medium | 9.6min | 40 | 0 | $1.58 | — | powershell | ok |
| PR Label Assigner | powershell | sonnet5-low | 6.0min | 34 | 1 | $0.96 | — | powershell | ok |
| PR Label Assigner | powershell-tool | sonnet5 | 30.0min | 0 | 4 | $0.00 | — | powershell | timeout |
| PR Label Assigner | powershell-tool | sonnet5-1m-medium | 8.7min | 27 | 1 | $1.19 | — | powershell | ok |
| PR Label Assigner | powershell-tool | sonnet5-low | 11.3min | 48 | 1 | $1.50 | — | powershell | ok |
| PR Label Assigner | typescript-bun | sonnet5 | 18.3min | 106 | 0 | $4.13 | — | typescript | ok |
| PR Label Assigner | typescript-bun | sonnet5-1m-medium | 11.0min | 63 | 2 | $2.28 | — | typescript | ok |
| PR Label Assigner | typescript-bun | sonnet5-low | 4.6min | 33 | 0 | $0.91 | — | typescript | ok |
| Secret Rotation Validator | bash | sonnet5 | 20.7min | 119 | 1 | $6.24 | — | bash | ok |
| Secret Rotation Validator | bash | sonnet5-1m-medium | 9.3min | 0 | 4 | $0.00 | — | bash | cli_error |
| Secret Rotation Validator | default | sonnet5 | 12.7min | 69 | 0 | $3.58 | — | python | ok |
| Secret Rotation Validator | default | sonnet5-1m-medium | 5.5min | 38 | 3 | $1.44 | — | python | ok |
| Secret Rotation Validator | powershell | sonnet5 | 30.0min | 0 | 0 | $0.00 | — | powershell | timeout |
| Secret Rotation Validator | powershell | sonnet5-1m-medium | 10.2min | 43 | 0 | $1.49 | — | powershell | ok |
| Secret Rotation Validator | powershell-tool | sonnet5 | 22.6min | 102 | 2 | $4.46 | — | powershell | ok |
| Secret Rotation Validator | powershell-tool | sonnet5-1m-medium | 15.4min | 83 | 0 | $2.81 | — | powershell | ok |
| Secret Rotation Validator | typescript-bun | sonnet5 | 25.3min | 136 | 1 | $6.32 | — | typescript | ok |
| Secret Rotation Validator | typescript-bun | sonnet5-1m-medium | 11.2min | 65 | 1 | $2.19 | — | typescript | ok |
| Semantic Version Bumper | bash | sonnet5 | 11.8min | 57 | 3 | $2.84 | — | bash | ok |
| Semantic Version Bumper | bash | sonnet5-1m-medium | 8.7min | 85 | 4 | $2.67 | — | bash | ok |
| Semantic Version Bumper | bash | sonnet5-low | 12.5min | 27 | 0 | $0.96 | — | bash | ok |
| Semantic Version Bumper | default | sonnet5 | 12.5min | 80 | 2 | $3.54 | — | python | ok |
| Semantic Version Bumper | default | sonnet5-1m-medium | 5.1min | 33 | 2 | $1.28 | — | python | ok |
| Semantic Version Bumper | default | sonnet5-low | 4.1min | 26 | 0 | $1.02 | — | python | ok |
| Semantic Version Bumper | powershell | sonnet5 | 30.0min | 0 | 1 | $0.00 | — | powershell | timeout |
| Semantic Version Bumper | powershell | sonnet5-1m-medium | 13.0min | 60 | 0 | $1.99 | — | powershell | ok |
| Semantic Version Bumper | powershell | sonnet5-low | 9.6min | 43 | 0 | $1.43 | — | powershell | ok |
| Semantic Version Bumper | powershell-tool | sonnet5 | 26.7min | 111 | 0 | $5.41 | — | powershell | ok |
| Semantic Version Bumper | powershell-tool | sonnet5-1m-medium | 10.2min | 40 | 0 | $1.42 | — | powershell | ok |
| Semantic Version Bumper | powershell-tool | sonnet5-low | 7.5min | 32 | 2 | $1.02 | — | powershell | ok |
| Semantic Version Bumper | typescript-bun | sonnet5 | 18.6min | 127 | 8 | $6.16 | — | typescript | ok |
| Semantic Version Bumper | typescript-bun | sonnet5-1m-medium | 11.7min | 69 | 1 | $2.15 | — | typescript | ok |
| Semantic Version Bumper | typescript-bun | sonnet5-low | 8.0min | 47 | 0 | $1.84 | — | typescript | ok |
| Test Results Aggregator | bash | sonnet5 | 17.1min | 108 | 6 | $5.57 | — | bash | ok |
| Test Results Aggregator | bash | sonnet5-1m-medium | 8.5min | 46 | 0 | $1.80 | — | bash | ok |
| Test Results Aggregator | default | sonnet5 | 12.7min | 59 | 0 | $3.47 | — | python | ok |
| Test Results Aggregator | default | sonnet5-1m-medium | 10.1min | 61 | 0 | $2.37 | — | python | ok |
| Test Results Aggregator | powershell | sonnet5 | 30.0min | 0 | 0 | $0.00 | — | powershell | timeout |
| Test Results Aggregator | powershell | sonnet5-1m-medium | 12.6min | 58 | 0 | $2.54 | — | powershell | ok |
| Test Results Aggregator | powershell-tool | sonnet5 | 26.0min | 87 | 4 | $4.82 | — | powershell | ok |
| Test Results Aggregator | powershell-tool | sonnet5-1m-medium | 13.3min | 69 | 0 | $2.19 | — | powershell | ok |
| Test Results Aggregator | typescript-bun | sonnet5 | 25.3min | 143 | 2 | $7.29 | — | typescript | ok |
| Test Results Aggregator | typescript-bun | sonnet5-1m-medium | 12.8min | 101 | 1 | $2.92 | — | typescript | ok |


<details>
<summary>Sorted by cost (cheapest first)</summary>

| Task | Language | Model | Duration | Turns | Errors | Cost | Tests Quality | Chosen | Status |
|------|----------|-------|----------|-------|--------|------|-----------|--------|--------|
| Semantic Version Bumper | powershell | sonnet5 | 30.0min | 0 | 1 | $0.00 | — | powershell | timeout |
| PR Label Assigner | bash | sonnet5 | 30.0min | 0 | 2 | $0.00 | — | bash | timeout |
| PR Label Assigner | powershell | sonnet5 | 30.0min | 0 | 1 | $0.00 | — | powershell | timeout |
| PR Label Assigner | powershell-tool | sonnet5 | 30.0min | 0 | 4 | $0.00 | — | powershell | timeout |
| Test Results Aggregator | powershell | sonnet5 | 30.0min | 0 | 0 | $0.00 | — | powershell | timeout |
| Secret Rotation Validator | bash | sonnet5-1m-medium | 9.3min | 0 | 4 | $0.00 | — | bash | cli_error |
| Secret Rotation Validator | powershell | sonnet5 | 30.0min | 0 | 0 | $0.00 | — | powershell | timeout |
| PR Label Assigner | default | sonnet5-low | 3.7min | 24 | 0 | $0.75 | — | python | ok |
| PR Label Assigner | bash | sonnet5-low | 3.4min | 28 | 1 | $0.76 | — | bash | ok |
| PR Label Assigner | typescript-bun | sonnet5-low | 4.6min | 33 | 0 | $0.91 | — | typescript | ok |
| PR Label Assigner | powershell | sonnet5-low | 6.0min | 34 | 1 | $0.96 | — | powershell | ok |
| Semantic Version Bumper | bash | sonnet5-low | 12.5min | 27 | 0 | $0.96 | — | bash | ok |
| Semantic Version Bumper | default | sonnet5-low | 4.1min | 26 | 0 | $1.02 | — | python | ok |
| Semantic Version Bumper | powershell-tool | sonnet5-low | 7.5min | 32 | 2 | $1.02 | — | powershell | ok |
| Dependency License Checker | default | sonnet5-low | 4.9min | 34 | 0 | $1.13 | — | python | ok |
| Dependency License Checker | powershell | sonnet5-low | 7.6min | 39 | 0 | $1.17 | — | powershell | ok |
| PR Label Assigner | powershell-tool | sonnet5-1m-medium | 8.7min | 27 | 1 | $1.19 | — | powershell | ok |
| Semantic Version Bumper | default | sonnet5-1m-medium | 5.1min | 33 | 2 | $1.28 | — | python | ok |
| Dependency License Checker | bash | sonnet5-low | 12.3min | 49 | 4 | $1.36 | — | bash | ok |
| Semantic Version Bumper | powershell-tool | sonnet5-1m-medium | 10.2min | 40 | 0 | $1.42 | — | powershell | ok |
| Semantic Version Bumper | powershell | sonnet5-low | 9.6min | 43 | 0 | $1.43 | — | powershell | ok |
| Secret Rotation Validator | default | sonnet5-1m-medium | 5.5min | 38 | 3 | $1.44 | — | python | ok |
| Secret Rotation Validator | powershell | sonnet5-1m-medium | 10.2min | 43 | 0 | $1.49 | — | powershell | ok |
| PR Label Assigner | powershell-tool | sonnet5-low | 11.3min | 48 | 1 | $1.50 | — | powershell | ok |
| PR Label Assigner | powershell | sonnet5-1m-medium | 9.6min | 40 | 0 | $1.58 | — | powershell | ok |
| Environment Matrix Generator | default | sonnet5-1m-medium | 6.9min | 59 | 0 | $1.72 | — | python | ok |
| Test Results Aggregator | bash | sonnet5-1m-medium | 8.5min | 46 | 0 | $1.80 | — | bash | ok |
| Semantic Version Bumper | typescript-bun | sonnet5-low | 8.0min | 47 | 0 | $1.84 | — | typescript | ok |
| Artifact Cleanup Script | powershell | sonnet5-1m-medium | 11.3min | 38 | 0 | $1.90 | — | powershell | ok |
| Dependency License Checker | default | sonnet5 | 9.9min | 39 | 1 | $1.99 | — | python | ok |
| Semantic Version Bumper | powershell | sonnet5-1m-medium | 13.0min | 60 | 0 | $1.99 | — | powershell | ok |
| PR Label Assigner | default | sonnet5-1m-medium | 9.5min | 64 | 1 | $2.04 | — | powershell | ok |
| Dependency License Checker | powershell | sonnet5-1m-medium | 13.5min | 52 | 3 | $2.14 | — | powershell | ok |
| Semantic Version Bumper | typescript-bun | sonnet5-1m-medium | 11.7min | 69 | 1 | $2.15 | — | typescript | ok |
| Test Results Aggregator | powershell-tool | sonnet5-1m-medium | 13.3min | 69 | 0 | $2.19 | — | powershell | ok |
| Secret Rotation Validator | typescript-bun | sonnet5-1m-medium | 11.2min | 65 | 1 | $2.19 | — | typescript | ok |
| PR Label Assigner | typescript-bun | sonnet5-1m-medium | 11.0min | 63 | 2 | $2.28 | — | typescript | ok |
| Test Results Aggregator | default | sonnet5-1m-medium | 10.1min | 61 | 0 | $2.37 | — | python | ok |
| Dependency License Checker | bash | sonnet5-1m-medium | 11.0min | 74 | 4 | $2.43 | — | bash | ok |
| Dependency License Checker | default | sonnet5-1m-medium | 8.9min | 73 | 0 | $2.48 | — | python | ok |
| Test Results Aggregator | powershell | sonnet5-1m-medium | 12.6min | 58 | 0 | $2.54 | — | powershell | ok |
| Semantic Version Bumper | bash | sonnet5-1m-medium | 8.7min | 85 | 4 | $2.67 | — | bash | ok |
| Dependency License Checker | powershell-tool | sonnet5 | 14.6min | 58 | 1 | $2.80 | — | powershell | ok |
| Secret Rotation Validator | powershell-tool | sonnet5-1m-medium | 15.4min | 83 | 0 | $2.81 | — | powershell | ok |
| Environment Matrix Generator | powershell-tool | sonnet5-1m-medium | 15.8min | 55 | 0 | $2.82 | — | powershell | ok |
| Dependency License Checker | typescript-bun | sonnet5-1m-medium | 13.6min | 93 | 1 | $2.82 | — | typescript | ok |
| Semantic Version Bumper | bash | sonnet5 | 11.8min | 57 | 3 | $2.84 | — | bash | ok |
| Environment Matrix Generator | bash | sonnet5-1m-medium | 14.2min | 67 | 0 | $2.90 | — | bash | ok |
| Test Results Aggregator | typescript-bun | sonnet5-1m-medium | 12.8min | 101 | 1 | $2.92 | — | typescript | ok |
| Dependency License Checker | powershell | sonnet5 | 16.8min | 80 | 0 | $3.03 | — | powershell | ok |
| Artifact Cleanup Script | default | sonnet5-1m-medium | 11.5min | 86 | 3 | $3.10 | — | python | ok |
| Environment Matrix Generator | typescript-bun | sonnet5-1m-medium | 17.0min | 87 | 4 | $3.12 | — | typescript | ok |
| Artifact Cleanup Script | typescript-bun | sonnet5-1m-medium | 13.7min | 109 | 0 | $3.28 | — | typescript | ok |
| Artifact Cleanup Script | powershell-tool | sonnet5-1m-medium | 16.6min | 64 | 2 | $3.28 | — | powershell | ok |
| Artifact Cleanup Script | bash | sonnet5-1m-medium | 16.9min | 80 | 7 | $3.35 | — | bash | ok |
| Artifact Cleanup Script | bash | sonnet5 | 11.8min | 59 | 4 | $3.37 | — | bash | ok |
| Environment Matrix Generator | powershell | sonnet5-1m-medium | 16.5min | 99 | 1 | $3.46 | — | powershell | ok |
| Test Results Aggregator | default | sonnet5 | 12.7min | 59 | 0 | $3.47 | — | python | ok |
| Semantic Version Bumper | default | sonnet5 | 12.5min | 80 | 2 | $3.54 | — | python | ok |
| Secret Rotation Validator | default | sonnet5 | 12.7min | 69 | 0 | $3.58 | — | python | ok |
| PR Label Assigner | default | sonnet5 | 11.6min | 80 | 0 | $3.61 | — | python | ok |
| Artifact Cleanup Script | default | sonnet5 | 18.0min | 76 | 1 | $3.61 | — | powershell | ok |
| PR Label Assigner | bash | sonnet5-1m-medium | 14.3min | 101 | 5 | $3.99 | — | bash | ok |
| Dependency License Checker | powershell-tool | sonnet5-1m-medium | 18.8min | 70 | 0 | $4.02 | — | powershell | ok |
| PR Label Assigner | typescript-bun | sonnet5 | 18.3min | 106 | 0 | $4.13 | — | typescript | ok |
| Artifact Cleanup Script | powershell-tool | sonnet5 | 21.2min | 79 | 0 | $4.33 | — | powershell | ok |
| Secret Rotation Validator | powershell-tool | sonnet5 | 22.6min | 102 | 2 | $4.46 | — | powershell | ok |
| Environment Matrix Generator | typescript-bun | sonnet5 | 19.7min | 75 | 1 | $4.76 | — | typescript | ok |
| Test Results Aggregator | powershell-tool | sonnet5 | 26.0min | 87 | 4 | $4.82 | — | powershell | ok |
| Environment Matrix Generator | default | sonnet5 | 16.4min | 94 | 2 | $5.01 | — | python | ok |
| Dependency License Checker | typescript-bun | sonnet5 | 18.4min | 137 | 11 | $5.28 | — | typescript | ok |
| Semantic Version Bumper | powershell-tool | sonnet5 | 26.7min | 111 | 0 | $5.41 | — | powershell | ok |
| Artifact Cleanup Script | powershell | sonnet5 | 23.4min | 98 | 3 | $5.42 | — | powershell | ok |
| Environment Matrix Generator | powershell-tool | sonnet5 | 25.4min | 82 | 0 | $5.48 | — | powershell | ok |
| Test Results Aggregator | bash | sonnet5 | 17.1min | 108 | 6 | $5.57 | — | bash | ok |
| Dependency License Checker | bash | sonnet5 | 17.4min | 105 | 3 | $5.57 | — | bash | ok |
| Artifact Cleanup Script | typescript-bun | sonnet5 | 23.5min | 150 | 2 | $6.00 | — | typescript | ok |
| Semantic Version Bumper | typescript-bun | sonnet5 | 18.6min | 127 | 8 | $6.16 | — | typescript | ok |
| Environment Matrix Generator | powershell | sonnet5 | 29.5min | 103 | 0 | $6.22 | — | powershell | ok |
| Secret Rotation Validator | bash | sonnet5 | 20.7min | 119 | 1 | $6.24 | — | bash | ok |
| Secret Rotation Validator | typescript-bun | sonnet5 | 25.3min | 136 | 1 | $6.32 | — | typescript | ok |
| Test Results Aggregator | typescript-bun | sonnet5 | 25.3min | 143 | 2 | $7.29 | — | typescript | ok |
| Environment Matrix Generator | bash | sonnet5 | 26.2min | 150 | 9 | $8.03 | — | bash | ok |

</details>

<details>
<summary>Sorted by duration (fastest first)</summary>

| Task | Language | Model | Duration | Turns | Errors | Cost | Tests Quality | Chosen | Status |
|------|----------|-------|----------|-------|--------|------|-----------|--------|--------|
| PR Label Assigner | bash | sonnet5-low | 3.4min | 28 | 1 | $0.76 | — | bash | ok |
| PR Label Assigner | default | sonnet5-low | 3.7min | 24 | 0 | $0.75 | — | python | ok |
| Semantic Version Bumper | default | sonnet5-low | 4.1min | 26 | 0 | $1.02 | — | python | ok |
| PR Label Assigner | typescript-bun | sonnet5-low | 4.6min | 33 | 0 | $0.91 | — | typescript | ok |
| Dependency License Checker | default | sonnet5-low | 4.9min | 34 | 0 | $1.13 | — | python | ok |
| Semantic Version Bumper | default | sonnet5-1m-medium | 5.1min | 33 | 2 | $1.28 | — | python | ok |
| Secret Rotation Validator | default | sonnet5-1m-medium | 5.5min | 38 | 3 | $1.44 | — | python | ok |
| PR Label Assigner | powershell | sonnet5-low | 6.0min | 34 | 1 | $0.96 | — | powershell | ok |
| Environment Matrix Generator | default | sonnet5-1m-medium | 6.9min | 59 | 0 | $1.72 | — | python | ok |
| Semantic Version Bumper | powershell-tool | sonnet5-low | 7.5min | 32 | 2 | $1.02 | — | powershell | ok |
| Dependency License Checker | powershell | sonnet5-low | 7.6min | 39 | 0 | $1.17 | — | powershell | ok |
| Semantic Version Bumper | typescript-bun | sonnet5-low | 8.0min | 47 | 0 | $1.84 | — | typescript | ok |
| Test Results Aggregator | bash | sonnet5-1m-medium | 8.5min | 46 | 0 | $1.80 | — | bash | ok |
| PR Label Assigner | powershell-tool | sonnet5-1m-medium | 8.7min | 27 | 1 | $1.19 | — | powershell | ok |
| Semantic Version Bumper | bash | sonnet5-1m-medium | 8.7min | 85 | 4 | $2.67 | — | bash | ok |
| Dependency License Checker | default | sonnet5-1m-medium | 8.9min | 73 | 0 | $2.48 | — | python | ok |
| Secret Rotation Validator | bash | sonnet5-1m-medium | 9.3min | 0 | 4 | $0.00 | — | bash | cli_error |
| PR Label Assigner | default | sonnet5-1m-medium | 9.5min | 64 | 1 | $2.04 | — | powershell | ok |
| PR Label Assigner | powershell | sonnet5-1m-medium | 9.6min | 40 | 0 | $1.58 | — | powershell | ok |
| Semantic Version Bumper | powershell | sonnet5-low | 9.6min | 43 | 0 | $1.43 | — | powershell | ok |
| Dependency License Checker | default | sonnet5 | 9.9min | 39 | 1 | $1.99 | — | python | ok |
| Test Results Aggregator | default | sonnet5-1m-medium | 10.1min | 61 | 0 | $2.37 | — | python | ok |
| Secret Rotation Validator | powershell | sonnet5-1m-medium | 10.2min | 43 | 0 | $1.49 | — | powershell | ok |
| Semantic Version Bumper | powershell-tool | sonnet5-1m-medium | 10.2min | 40 | 0 | $1.42 | — | powershell | ok |
| Dependency License Checker | bash | sonnet5-1m-medium | 11.0min | 74 | 4 | $2.43 | — | bash | ok |
| PR Label Assigner | typescript-bun | sonnet5-1m-medium | 11.0min | 63 | 2 | $2.28 | — | typescript | ok |
| Secret Rotation Validator | typescript-bun | sonnet5-1m-medium | 11.2min | 65 | 1 | $2.19 | — | typescript | ok |
| PR Label Assigner | powershell-tool | sonnet5-low | 11.3min | 48 | 1 | $1.50 | — | powershell | ok |
| Artifact Cleanup Script | powershell | sonnet5-1m-medium | 11.3min | 38 | 0 | $1.90 | — | powershell | ok |
| Artifact Cleanup Script | default | sonnet5-1m-medium | 11.5min | 86 | 3 | $3.10 | — | python | ok |
| PR Label Assigner | default | sonnet5 | 11.6min | 80 | 0 | $3.61 | — | python | ok |
| Semantic Version Bumper | typescript-bun | sonnet5-1m-medium | 11.7min | 69 | 1 | $2.15 | — | typescript | ok |
| Semantic Version Bumper | bash | sonnet5 | 11.8min | 57 | 3 | $2.84 | — | bash | ok |
| Artifact Cleanup Script | bash | sonnet5 | 11.8min | 59 | 4 | $3.37 | — | bash | ok |
| Dependency License Checker | bash | sonnet5-low | 12.3min | 49 | 4 | $1.36 | — | bash | ok |
| Semantic Version Bumper | default | sonnet5 | 12.5min | 80 | 2 | $3.54 | — | python | ok |
| Semantic Version Bumper | bash | sonnet5-low | 12.5min | 27 | 0 | $0.96 | — | bash | ok |
| Test Results Aggregator | powershell | sonnet5-1m-medium | 12.6min | 58 | 0 | $2.54 | — | powershell | ok |
| Test Results Aggregator | default | sonnet5 | 12.7min | 59 | 0 | $3.47 | — | python | ok |
| Secret Rotation Validator | default | sonnet5 | 12.7min | 69 | 0 | $3.58 | — | python | ok |
| Test Results Aggregator | typescript-bun | sonnet5-1m-medium | 12.8min | 101 | 1 | $2.92 | — | typescript | ok |
| Semantic Version Bumper | powershell | sonnet5-1m-medium | 13.0min | 60 | 0 | $1.99 | — | powershell | ok |
| Test Results Aggregator | powershell-tool | sonnet5-1m-medium | 13.3min | 69 | 0 | $2.19 | — | powershell | ok |
| Dependency License Checker | powershell | sonnet5-1m-medium | 13.5min | 52 | 3 | $2.14 | — | powershell | ok |
| Dependency License Checker | typescript-bun | sonnet5-1m-medium | 13.6min | 93 | 1 | $2.82 | — | typescript | ok |
| Artifact Cleanup Script | typescript-bun | sonnet5-1m-medium | 13.7min | 109 | 0 | $3.28 | — | typescript | ok |
| Environment Matrix Generator | bash | sonnet5-1m-medium | 14.2min | 67 | 0 | $2.90 | — | bash | ok |
| PR Label Assigner | bash | sonnet5-1m-medium | 14.3min | 101 | 5 | $3.99 | — | bash | ok |
| Dependency License Checker | powershell-tool | sonnet5 | 14.6min | 58 | 1 | $2.80 | — | powershell | ok |
| Secret Rotation Validator | powershell-tool | sonnet5-1m-medium | 15.4min | 83 | 0 | $2.81 | — | powershell | ok |
| Environment Matrix Generator | powershell-tool | sonnet5-1m-medium | 15.8min | 55 | 0 | $2.82 | — | powershell | ok |
| Environment Matrix Generator | default | sonnet5 | 16.4min | 94 | 2 | $5.01 | — | python | ok |
| Environment Matrix Generator | powershell | sonnet5-1m-medium | 16.5min | 99 | 1 | $3.46 | — | powershell | ok |
| Artifact Cleanup Script | powershell-tool | sonnet5-1m-medium | 16.6min | 64 | 2 | $3.28 | — | powershell | ok |
| Dependency License Checker | powershell | sonnet5 | 16.8min | 80 | 0 | $3.03 | — | powershell | ok |
| Artifact Cleanup Script | bash | sonnet5-1m-medium | 16.9min | 80 | 7 | $3.35 | — | bash | ok |
| Environment Matrix Generator | typescript-bun | sonnet5-1m-medium | 17.0min | 87 | 4 | $3.12 | — | typescript | ok |
| Test Results Aggregator | bash | sonnet5 | 17.1min | 108 | 6 | $5.57 | — | bash | ok |
| Dependency License Checker | bash | sonnet5 | 17.4min | 105 | 3 | $5.57 | — | bash | ok |
| Artifact Cleanup Script | default | sonnet5 | 18.0min | 76 | 1 | $3.61 | — | powershell | ok |
| PR Label Assigner | typescript-bun | sonnet5 | 18.3min | 106 | 0 | $4.13 | — | typescript | ok |
| Dependency License Checker | typescript-bun | sonnet5 | 18.4min | 137 | 11 | $5.28 | — | typescript | ok |
| Semantic Version Bumper | typescript-bun | sonnet5 | 18.6min | 127 | 8 | $6.16 | — | typescript | ok |
| Dependency License Checker | powershell-tool | sonnet5-1m-medium | 18.8min | 70 | 0 | $4.02 | — | powershell | ok |
| Environment Matrix Generator | typescript-bun | sonnet5 | 19.7min | 75 | 1 | $4.76 | — | typescript | ok |
| Secret Rotation Validator | bash | sonnet5 | 20.7min | 119 | 1 | $6.24 | — | bash | ok |
| Artifact Cleanup Script | powershell-tool | sonnet5 | 21.2min | 79 | 0 | $4.33 | — | powershell | ok |
| Secret Rotation Validator | powershell-tool | sonnet5 | 22.6min | 102 | 2 | $4.46 | — | powershell | ok |
| Artifact Cleanup Script | powershell | sonnet5 | 23.4min | 98 | 3 | $5.42 | — | powershell | ok |
| Artifact Cleanup Script | typescript-bun | sonnet5 | 23.5min | 150 | 2 | $6.00 | — | typescript | ok |
| Secret Rotation Validator | typescript-bun | sonnet5 | 25.3min | 136 | 1 | $6.32 | — | typescript | ok |
| Test Results Aggregator | typescript-bun | sonnet5 | 25.3min | 143 | 2 | $7.29 | — | typescript | ok |
| Environment Matrix Generator | powershell-tool | sonnet5 | 25.4min | 82 | 0 | $5.48 | — | powershell | ok |
| Test Results Aggregator | powershell-tool | sonnet5 | 26.0min | 87 | 4 | $4.82 | — | powershell | ok |
| Environment Matrix Generator | bash | sonnet5 | 26.2min | 150 | 9 | $8.03 | — | bash | ok |
| Semantic Version Bumper | powershell-tool | sonnet5 | 26.7min | 111 | 0 | $5.41 | — | powershell | ok |
| Environment Matrix Generator | powershell | sonnet5 | 29.5min | 103 | 0 | $6.22 | — | powershell | ok |
| Test Results Aggregator | powershell | sonnet5 | 30.0min | 0 | 0 | $0.00 | — | powershell | timeout |
| Secret Rotation Validator | powershell | sonnet5 | 30.0min | 0 | 0 | $0.00 | — | powershell | timeout |
| Semantic Version Bumper | powershell | sonnet5 | 30.0min | 0 | 1 | $0.00 | — | powershell | timeout |
| PR Label Assigner | powershell-tool | sonnet5 | 30.0min | 0 | 4 | $0.00 | — | powershell | timeout |
| PR Label Assigner | bash | sonnet5 | 30.0min | 0 | 2 | $0.00 | — | bash | timeout |
| PR Label Assigner | powershell | sonnet5 | 30.0min | 0 | 1 | $0.00 | — | powershell | timeout |

</details>

<details>
<summary>Sorted by errors (fewest first)</summary>

| Task | Language | Model | Duration | Turns | Errors | Cost | Tests Quality | Chosen | Status |
|------|----------|-------|----------|-------|--------|------|-----------|--------|--------|
| Semantic Version Bumper | bash | sonnet5-low | 12.5min | 27 | 0 | $0.96 | — | bash | ok |
| Semantic Version Bumper | default | sonnet5-low | 4.1min | 26 | 0 | $1.02 | — | python | ok |
| Semantic Version Bumper | powershell | sonnet5-1m-medium | 13.0min | 60 | 0 | $1.99 | — | powershell | ok |
| Semantic Version Bumper | powershell | sonnet5-low | 9.6min | 43 | 0 | $1.43 | — | powershell | ok |
| Semantic Version Bumper | powershell-tool | sonnet5 | 26.7min | 111 | 0 | $5.41 | — | powershell | ok |
| Semantic Version Bumper | powershell-tool | sonnet5-1m-medium | 10.2min | 40 | 0 | $1.42 | — | powershell | ok |
| Semantic Version Bumper | typescript-bun | sonnet5-low | 8.0min | 47 | 0 | $1.84 | — | typescript | ok |
| PR Label Assigner | default | sonnet5 | 11.6min | 80 | 0 | $3.61 | — | python | ok |
| PR Label Assigner | default | sonnet5-low | 3.7min | 24 | 0 | $0.75 | — | python | ok |
| PR Label Assigner | powershell | sonnet5-1m-medium | 9.6min | 40 | 0 | $1.58 | — | powershell | ok |
| PR Label Assigner | typescript-bun | sonnet5 | 18.3min | 106 | 0 | $4.13 | — | typescript | ok |
| PR Label Assigner | typescript-bun | sonnet5-low | 4.6min | 33 | 0 | $0.91 | — | typescript | ok |
| Dependency License Checker | default | sonnet5-1m-medium | 8.9min | 73 | 0 | $2.48 | — | python | ok |
| Dependency License Checker | default | sonnet5-low | 4.9min | 34 | 0 | $1.13 | — | python | ok |
| Dependency License Checker | powershell | sonnet5 | 16.8min | 80 | 0 | $3.03 | — | powershell | ok |
| Dependency License Checker | powershell | sonnet5-low | 7.6min | 39 | 0 | $1.17 | — | powershell | ok |
| Dependency License Checker | powershell-tool | sonnet5-1m-medium | 18.8min | 70 | 0 | $4.02 | — | powershell | ok |
| Test Results Aggregator | bash | sonnet5-1m-medium | 8.5min | 46 | 0 | $1.80 | — | bash | ok |
| Test Results Aggregator | default | sonnet5 | 12.7min | 59 | 0 | $3.47 | — | python | ok |
| Test Results Aggregator | default | sonnet5-1m-medium | 10.1min | 61 | 0 | $2.37 | — | python | ok |
| Test Results Aggregator | powershell | sonnet5 | 30.0min | 0 | 0 | $0.00 | — | powershell | timeout |
| Test Results Aggregator | powershell | sonnet5-1m-medium | 12.6min | 58 | 0 | $2.54 | — | powershell | ok |
| Test Results Aggregator | powershell-tool | sonnet5-1m-medium | 13.3min | 69 | 0 | $2.19 | — | powershell | ok |
| Environment Matrix Generator | bash | sonnet5-1m-medium | 14.2min | 67 | 0 | $2.90 | — | bash | ok |
| Environment Matrix Generator | default | sonnet5-1m-medium | 6.9min | 59 | 0 | $1.72 | — | python | ok |
| Environment Matrix Generator | powershell | sonnet5 | 29.5min | 103 | 0 | $6.22 | — | powershell | ok |
| Environment Matrix Generator | powershell-tool | sonnet5 | 25.4min | 82 | 0 | $5.48 | — | powershell | ok |
| Environment Matrix Generator | powershell-tool | sonnet5-1m-medium | 15.8min | 55 | 0 | $2.82 | — | powershell | ok |
| Artifact Cleanup Script | powershell | sonnet5-1m-medium | 11.3min | 38 | 0 | $1.90 | — | powershell | ok |
| Artifact Cleanup Script | powershell-tool | sonnet5 | 21.2min | 79 | 0 | $4.33 | — | powershell | ok |
| Artifact Cleanup Script | typescript-bun | sonnet5-1m-medium | 13.7min | 109 | 0 | $3.28 | — | typescript | ok |
| Secret Rotation Validator | default | sonnet5 | 12.7min | 69 | 0 | $3.58 | — | python | ok |
| Secret Rotation Validator | powershell | sonnet5 | 30.0min | 0 | 0 | $0.00 | — | powershell | timeout |
| Secret Rotation Validator | powershell | sonnet5-1m-medium | 10.2min | 43 | 0 | $1.49 | — | powershell | ok |
| Secret Rotation Validator | powershell-tool | sonnet5-1m-medium | 15.4min | 83 | 0 | $2.81 | — | powershell | ok |
| Semantic Version Bumper | powershell | sonnet5 | 30.0min | 0 | 1 | $0.00 | — | powershell | timeout |
| Semantic Version Bumper | typescript-bun | sonnet5-1m-medium | 11.7min | 69 | 1 | $2.15 | — | typescript | ok |
| PR Label Assigner | bash | sonnet5-low | 3.4min | 28 | 1 | $0.76 | — | bash | ok |
| PR Label Assigner | default | sonnet5-1m-medium | 9.5min | 64 | 1 | $2.04 | — | powershell | ok |
| PR Label Assigner | powershell | sonnet5 | 30.0min | 0 | 1 | $0.00 | — | powershell | timeout |
| PR Label Assigner | powershell | sonnet5-low | 6.0min | 34 | 1 | $0.96 | — | powershell | ok |
| PR Label Assigner | powershell-tool | sonnet5-1m-medium | 8.7min | 27 | 1 | $1.19 | — | powershell | ok |
| PR Label Assigner | powershell-tool | sonnet5-low | 11.3min | 48 | 1 | $1.50 | — | powershell | ok |
| Dependency License Checker | default | sonnet5 | 9.9min | 39 | 1 | $1.99 | — | python | ok |
| Dependency License Checker | powershell-tool | sonnet5 | 14.6min | 58 | 1 | $2.80 | — | powershell | ok |
| Dependency License Checker | typescript-bun | sonnet5-1m-medium | 13.6min | 93 | 1 | $2.82 | — | typescript | ok |
| Test Results Aggregator | typescript-bun | sonnet5-1m-medium | 12.8min | 101 | 1 | $2.92 | — | typescript | ok |
| Environment Matrix Generator | powershell | sonnet5-1m-medium | 16.5min | 99 | 1 | $3.46 | — | powershell | ok |
| Environment Matrix Generator | typescript-bun | sonnet5 | 19.7min | 75 | 1 | $4.76 | — | typescript | ok |
| Artifact Cleanup Script | default | sonnet5 | 18.0min | 76 | 1 | $3.61 | — | powershell | ok |
| Secret Rotation Validator | bash | sonnet5 | 20.7min | 119 | 1 | $6.24 | — | bash | ok |
| Secret Rotation Validator | typescript-bun | sonnet5 | 25.3min | 136 | 1 | $6.32 | — | typescript | ok |
| Secret Rotation Validator | typescript-bun | sonnet5-1m-medium | 11.2min | 65 | 1 | $2.19 | — | typescript | ok |
| Semantic Version Bumper | default | sonnet5 | 12.5min | 80 | 2 | $3.54 | — | python | ok |
| Semantic Version Bumper | default | sonnet5-1m-medium | 5.1min | 33 | 2 | $1.28 | — | python | ok |
| Semantic Version Bumper | powershell-tool | sonnet5-low | 7.5min | 32 | 2 | $1.02 | — | powershell | ok |
| PR Label Assigner | bash | sonnet5 | 30.0min | 0 | 2 | $0.00 | — | bash | timeout |
| PR Label Assigner | typescript-bun | sonnet5-1m-medium | 11.0min | 63 | 2 | $2.28 | — | typescript | ok |
| Test Results Aggregator | typescript-bun | sonnet5 | 25.3min | 143 | 2 | $7.29 | — | typescript | ok |
| Environment Matrix Generator | default | sonnet5 | 16.4min | 94 | 2 | $5.01 | — | python | ok |
| Artifact Cleanup Script | powershell-tool | sonnet5-1m-medium | 16.6min | 64 | 2 | $3.28 | — | powershell | ok |
| Artifact Cleanup Script | typescript-bun | sonnet5 | 23.5min | 150 | 2 | $6.00 | — | typescript | ok |
| Secret Rotation Validator | powershell-tool | sonnet5 | 22.6min | 102 | 2 | $4.46 | — | powershell | ok |
| Semantic Version Bumper | bash | sonnet5 | 11.8min | 57 | 3 | $2.84 | — | bash | ok |
| Dependency License Checker | bash | sonnet5 | 17.4min | 105 | 3 | $5.57 | — | bash | ok |
| Dependency License Checker | powershell | sonnet5-1m-medium | 13.5min | 52 | 3 | $2.14 | — | powershell | ok |
| Artifact Cleanup Script | default | sonnet5-1m-medium | 11.5min | 86 | 3 | $3.10 | — | python | ok |
| Artifact Cleanup Script | powershell | sonnet5 | 23.4min | 98 | 3 | $5.42 | — | powershell | ok |
| Secret Rotation Validator | default | sonnet5-1m-medium | 5.5min | 38 | 3 | $1.44 | — | python | ok |
| Semantic Version Bumper | bash | sonnet5-1m-medium | 8.7min | 85 | 4 | $2.67 | — | bash | ok |
| PR Label Assigner | powershell-tool | sonnet5 | 30.0min | 0 | 4 | $0.00 | — | powershell | timeout |
| Dependency License Checker | bash | sonnet5-1m-medium | 11.0min | 74 | 4 | $2.43 | — | bash | ok |
| Dependency License Checker | bash | sonnet5-low | 12.3min | 49 | 4 | $1.36 | — | bash | ok |
| Test Results Aggregator | powershell-tool | sonnet5 | 26.0min | 87 | 4 | $4.82 | — | powershell | ok |
| Environment Matrix Generator | typescript-bun | sonnet5-1m-medium | 17.0min | 87 | 4 | $3.12 | — | typescript | ok |
| Artifact Cleanup Script | bash | sonnet5 | 11.8min | 59 | 4 | $3.37 | — | bash | ok |
| Secret Rotation Validator | bash | sonnet5-1m-medium | 9.3min | 0 | 4 | $0.00 | — | bash | cli_error |
| PR Label Assigner | bash | sonnet5-1m-medium | 14.3min | 101 | 5 | $3.99 | — | bash | ok |
| Test Results Aggregator | bash | sonnet5 | 17.1min | 108 | 6 | $5.57 | — | bash | ok |
| Artifact Cleanup Script | bash | sonnet5-1m-medium | 16.9min | 80 | 7 | $3.35 | — | bash | ok |
| Semantic Version Bumper | typescript-bun | sonnet5 | 18.6min | 127 | 8 | $6.16 | — | typescript | ok |
| Environment Matrix Generator | bash | sonnet5 | 26.2min | 150 | 9 | $8.03 | — | bash | ok |
| Dependency License Checker | typescript-bun | sonnet5 | 18.4min | 137 | 11 | $5.28 | — | typescript | ok |

</details>

<details>
<summary>Sorted by turns (fewest first)</summary>

| Task | Language | Model | Duration | Turns | Errors | Cost | Tests Quality | Chosen | Status |
|------|----------|-------|----------|-------|--------|------|-----------|--------|--------|
| Semantic Version Bumper | powershell | sonnet5 | 30.0min | 0 | 1 | $0.00 | — | powershell | timeout |
| PR Label Assigner | bash | sonnet5 | 30.0min | 0 | 2 | $0.00 | — | bash | timeout |
| PR Label Assigner | powershell | sonnet5 | 30.0min | 0 | 1 | $0.00 | — | powershell | timeout |
| PR Label Assigner | powershell-tool | sonnet5 | 30.0min | 0 | 4 | $0.00 | — | powershell | timeout |
| Test Results Aggregator | powershell | sonnet5 | 30.0min | 0 | 0 | $0.00 | — | powershell | timeout |
| Secret Rotation Validator | bash | sonnet5-1m-medium | 9.3min | 0 | 4 | $0.00 | — | bash | cli_error |
| Secret Rotation Validator | powershell | sonnet5 | 30.0min | 0 | 0 | $0.00 | — | powershell | timeout |
| PR Label Assigner | default | sonnet5-low | 3.7min | 24 | 0 | $0.75 | — | python | ok |
| Semantic Version Bumper | default | sonnet5-low | 4.1min | 26 | 0 | $1.02 | — | python | ok |
| Semantic Version Bumper | bash | sonnet5-low | 12.5min | 27 | 0 | $0.96 | — | bash | ok |
| PR Label Assigner | powershell-tool | sonnet5-1m-medium | 8.7min | 27 | 1 | $1.19 | — | powershell | ok |
| PR Label Assigner | bash | sonnet5-low | 3.4min | 28 | 1 | $0.76 | — | bash | ok |
| Semantic Version Bumper | powershell-tool | sonnet5-low | 7.5min | 32 | 2 | $1.02 | — | powershell | ok |
| Semantic Version Bumper | default | sonnet5-1m-medium | 5.1min | 33 | 2 | $1.28 | — | python | ok |
| PR Label Assigner | typescript-bun | sonnet5-low | 4.6min | 33 | 0 | $0.91 | — | typescript | ok |
| PR Label Assigner | powershell | sonnet5-low | 6.0min | 34 | 1 | $0.96 | — | powershell | ok |
| Dependency License Checker | default | sonnet5-low | 4.9min | 34 | 0 | $1.13 | — | python | ok |
| Artifact Cleanup Script | powershell | sonnet5-1m-medium | 11.3min | 38 | 0 | $1.90 | — | powershell | ok |
| Secret Rotation Validator | default | sonnet5-1m-medium | 5.5min | 38 | 3 | $1.44 | — | python | ok |
| Dependency License Checker | default | sonnet5 | 9.9min | 39 | 1 | $1.99 | — | python | ok |
| Dependency License Checker | powershell | sonnet5-low | 7.6min | 39 | 0 | $1.17 | — | powershell | ok |
| Semantic Version Bumper | powershell-tool | sonnet5-1m-medium | 10.2min | 40 | 0 | $1.42 | — | powershell | ok |
| PR Label Assigner | powershell | sonnet5-1m-medium | 9.6min | 40 | 0 | $1.58 | — | powershell | ok |
| Semantic Version Bumper | powershell | sonnet5-low | 9.6min | 43 | 0 | $1.43 | — | powershell | ok |
| Secret Rotation Validator | powershell | sonnet5-1m-medium | 10.2min | 43 | 0 | $1.49 | — | powershell | ok |
| Test Results Aggregator | bash | sonnet5-1m-medium | 8.5min | 46 | 0 | $1.80 | — | bash | ok |
| Semantic Version Bumper | typescript-bun | sonnet5-low | 8.0min | 47 | 0 | $1.84 | — | typescript | ok |
| PR Label Assigner | powershell-tool | sonnet5-low | 11.3min | 48 | 1 | $1.50 | — | powershell | ok |
| Dependency License Checker | bash | sonnet5-low | 12.3min | 49 | 4 | $1.36 | — | bash | ok |
| Dependency License Checker | powershell | sonnet5-1m-medium | 13.5min | 52 | 3 | $2.14 | — | powershell | ok |
| Environment Matrix Generator | powershell-tool | sonnet5-1m-medium | 15.8min | 55 | 0 | $2.82 | — | powershell | ok |
| Semantic Version Bumper | bash | sonnet5 | 11.8min | 57 | 3 | $2.84 | — | bash | ok |
| Dependency License Checker | powershell-tool | sonnet5 | 14.6min | 58 | 1 | $2.80 | — | powershell | ok |
| Test Results Aggregator | powershell | sonnet5-1m-medium | 12.6min | 58 | 0 | $2.54 | — | powershell | ok |
| Test Results Aggregator | default | sonnet5 | 12.7min | 59 | 0 | $3.47 | — | python | ok |
| Environment Matrix Generator | default | sonnet5-1m-medium | 6.9min | 59 | 0 | $1.72 | — | python | ok |
| Artifact Cleanup Script | bash | sonnet5 | 11.8min | 59 | 4 | $3.37 | — | bash | ok |
| Semantic Version Bumper | powershell | sonnet5-1m-medium | 13.0min | 60 | 0 | $1.99 | — | powershell | ok |
| Test Results Aggregator | default | sonnet5-1m-medium | 10.1min | 61 | 0 | $2.37 | — | python | ok |
| PR Label Assigner | typescript-bun | sonnet5-1m-medium | 11.0min | 63 | 2 | $2.28 | — | typescript | ok |
| PR Label Assigner | default | sonnet5-1m-medium | 9.5min | 64 | 1 | $2.04 | — | powershell | ok |
| Artifact Cleanup Script | powershell-tool | sonnet5-1m-medium | 16.6min | 64 | 2 | $3.28 | — | powershell | ok |
| Secret Rotation Validator | typescript-bun | sonnet5-1m-medium | 11.2min | 65 | 1 | $2.19 | — | typescript | ok |
| Environment Matrix Generator | bash | sonnet5-1m-medium | 14.2min | 67 | 0 | $2.90 | — | bash | ok |
| Semantic Version Bumper | typescript-bun | sonnet5-1m-medium | 11.7min | 69 | 1 | $2.15 | — | typescript | ok |
| Test Results Aggregator | powershell-tool | sonnet5-1m-medium | 13.3min | 69 | 0 | $2.19 | — | powershell | ok |
| Secret Rotation Validator | default | sonnet5 | 12.7min | 69 | 0 | $3.58 | — | python | ok |
| Dependency License Checker | powershell-tool | sonnet5-1m-medium | 18.8min | 70 | 0 | $4.02 | — | powershell | ok |
| Dependency License Checker | default | sonnet5-1m-medium | 8.9min | 73 | 0 | $2.48 | — | python | ok |
| Dependency License Checker | bash | sonnet5-1m-medium | 11.0min | 74 | 4 | $2.43 | — | bash | ok |
| Environment Matrix Generator | typescript-bun | sonnet5 | 19.7min | 75 | 1 | $4.76 | — | typescript | ok |
| Artifact Cleanup Script | default | sonnet5 | 18.0min | 76 | 1 | $3.61 | — | powershell | ok |
| Artifact Cleanup Script | powershell-tool | sonnet5 | 21.2min | 79 | 0 | $4.33 | — | powershell | ok |
| Semantic Version Bumper | default | sonnet5 | 12.5min | 80 | 2 | $3.54 | — | python | ok |
| PR Label Assigner | default | sonnet5 | 11.6min | 80 | 0 | $3.61 | — | python | ok |
| Dependency License Checker | powershell | sonnet5 | 16.8min | 80 | 0 | $3.03 | — | powershell | ok |
| Artifact Cleanup Script | bash | sonnet5-1m-medium | 16.9min | 80 | 7 | $3.35 | — | bash | ok |
| Environment Matrix Generator | powershell-tool | sonnet5 | 25.4min | 82 | 0 | $5.48 | — | powershell | ok |
| Secret Rotation Validator | powershell-tool | sonnet5-1m-medium | 15.4min | 83 | 0 | $2.81 | — | powershell | ok |
| Semantic Version Bumper | bash | sonnet5-1m-medium | 8.7min | 85 | 4 | $2.67 | — | bash | ok |
| Artifact Cleanup Script | default | sonnet5-1m-medium | 11.5min | 86 | 3 | $3.10 | — | python | ok |
| Test Results Aggregator | powershell-tool | sonnet5 | 26.0min | 87 | 4 | $4.82 | — | powershell | ok |
| Environment Matrix Generator | typescript-bun | sonnet5-1m-medium | 17.0min | 87 | 4 | $3.12 | — | typescript | ok |
| Dependency License Checker | typescript-bun | sonnet5-1m-medium | 13.6min | 93 | 1 | $2.82 | — | typescript | ok |
| Environment Matrix Generator | default | sonnet5 | 16.4min | 94 | 2 | $5.01 | — | python | ok |
| Artifact Cleanup Script | powershell | sonnet5 | 23.4min | 98 | 3 | $5.42 | — | powershell | ok |
| Environment Matrix Generator | powershell | sonnet5-1m-medium | 16.5min | 99 | 1 | $3.46 | — | powershell | ok |
| PR Label Assigner | bash | sonnet5-1m-medium | 14.3min | 101 | 5 | $3.99 | — | bash | ok |
| Test Results Aggregator | typescript-bun | sonnet5-1m-medium | 12.8min | 101 | 1 | $2.92 | — | typescript | ok |
| Secret Rotation Validator | powershell-tool | sonnet5 | 22.6min | 102 | 2 | $4.46 | — | powershell | ok |
| Environment Matrix Generator | powershell | sonnet5 | 29.5min | 103 | 0 | $6.22 | — | powershell | ok |
| Dependency License Checker | bash | sonnet5 | 17.4min | 105 | 3 | $5.57 | — | bash | ok |
| PR Label Assigner | typescript-bun | sonnet5 | 18.3min | 106 | 0 | $4.13 | — | typescript | ok |
| Test Results Aggregator | bash | sonnet5 | 17.1min | 108 | 6 | $5.57 | — | bash | ok |
| Artifact Cleanup Script | typescript-bun | sonnet5-1m-medium | 13.7min | 109 | 0 | $3.28 | — | typescript | ok |
| Semantic Version Bumper | powershell-tool | sonnet5 | 26.7min | 111 | 0 | $5.41 | — | powershell | ok |
| Secret Rotation Validator | bash | sonnet5 | 20.7min | 119 | 1 | $6.24 | — | bash | ok |
| Semantic Version Bumper | typescript-bun | sonnet5 | 18.6min | 127 | 8 | $6.16 | — | typescript | ok |
| Secret Rotation Validator | typescript-bun | sonnet5 | 25.3min | 136 | 1 | $6.32 | — | typescript | ok |
| Dependency License Checker | typescript-bun | sonnet5 | 18.4min | 137 | 11 | $5.28 | — | typescript | ok |
| Test Results Aggregator | typescript-bun | sonnet5 | 25.3min | 143 | 2 | $7.29 | — | typescript | ok |
| Environment Matrix Generator | bash | sonnet5 | 26.2min | 150 | 9 | $8.03 | — | bash | ok |
| Artifact Cleanup Script | typescript-bun | sonnet5 | 23.5min | 150 | 2 | $6.00 | — | typescript | ok |

</details>

<details>
<summary>Sorted by LLM-as-judge score (best first)</summary>

| Task | Language | Model | Duration | Turns | Errors | Cost | Tests Quality | Chosen | Status |
|------|----------|-------|----------|-------|--------|------|-----------|--------|--------|
| Semantic Version Bumper | bash | sonnet5 | 11.8min | 57 | 3 | $2.84 | — | bash | ok |
| Semantic Version Bumper | bash | sonnet5-1m-medium | 8.7min | 85 | 4 | $2.67 | — | bash | ok |
| Semantic Version Bumper | bash | sonnet5-low | 12.5min | 27 | 0 | $0.96 | — | bash | ok |
| Semantic Version Bumper | default | sonnet5 | 12.5min | 80 | 2 | $3.54 | — | python | ok |
| Semantic Version Bumper | default | sonnet5-1m-medium | 5.1min | 33 | 2 | $1.28 | — | python | ok |
| Semantic Version Bumper | default | sonnet5-low | 4.1min | 26 | 0 | $1.02 | — | python | ok |
| Semantic Version Bumper | powershell | sonnet5 | 30.0min | 0 | 1 | $0.00 | — | powershell | timeout |
| Semantic Version Bumper | powershell | sonnet5-1m-medium | 13.0min | 60 | 0 | $1.99 | — | powershell | ok |
| Semantic Version Bumper | powershell | sonnet5-low | 9.6min | 43 | 0 | $1.43 | — | powershell | ok |
| Semantic Version Bumper | powershell-tool | sonnet5 | 26.7min | 111 | 0 | $5.41 | — | powershell | ok |
| Semantic Version Bumper | powershell-tool | sonnet5-1m-medium | 10.2min | 40 | 0 | $1.42 | — | powershell | ok |
| Semantic Version Bumper | powershell-tool | sonnet5-low | 7.5min | 32 | 2 | $1.02 | — | powershell | ok |
| Semantic Version Bumper | typescript-bun | sonnet5 | 18.6min | 127 | 8 | $6.16 | — | typescript | ok |
| Semantic Version Bumper | typescript-bun | sonnet5-1m-medium | 11.7min | 69 | 1 | $2.15 | — | typescript | ok |
| Semantic Version Bumper | typescript-bun | sonnet5-low | 8.0min | 47 | 0 | $1.84 | — | typescript | ok |
| PR Label Assigner | bash | sonnet5 | 30.0min | 0 | 2 | $0.00 | — | bash | timeout |
| PR Label Assigner | bash | sonnet5-1m-medium | 14.3min | 101 | 5 | $3.99 | — | bash | ok |
| PR Label Assigner | bash | sonnet5-low | 3.4min | 28 | 1 | $0.76 | — | bash | ok |
| PR Label Assigner | default | sonnet5 | 11.6min | 80 | 0 | $3.61 | — | python | ok |
| PR Label Assigner | default | sonnet5-1m-medium | 9.5min | 64 | 1 | $2.04 | — | powershell | ok |
| PR Label Assigner | default | sonnet5-low | 3.7min | 24 | 0 | $0.75 | — | python | ok |
| PR Label Assigner | powershell | sonnet5 | 30.0min | 0 | 1 | $0.00 | — | powershell | timeout |
| PR Label Assigner | powershell | sonnet5-1m-medium | 9.6min | 40 | 0 | $1.58 | — | powershell | ok |
| PR Label Assigner | powershell | sonnet5-low | 6.0min | 34 | 1 | $0.96 | — | powershell | ok |
| PR Label Assigner | powershell-tool | sonnet5 | 30.0min | 0 | 4 | $0.00 | — | powershell | timeout |
| PR Label Assigner | powershell-tool | sonnet5-1m-medium | 8.7min | 27 | 1 | $1.19 | — | powershell | ok |
| PR Label Assigner | powershell-tool | sonnet5-low | 11.3min | 48 | 1 | $1.50 | — | powershell | ok |
| PR Label Assigner | typescript-bun | sonnet5 | 18.3min | 106 | 0 | $4.13 | — | typescript | ok |
| PR Label Assigner | typescript-bun | sonnet5-1m-medium | 11.0min | 63 | 2 | $2.28 | — | typescript | ok |
| PR Label Assigner | typescript-bun | sonnet5-low | 4.6min | 33 | 0 | $0.91 | — | typescript | ok |
| Dependency License Checker | bash | sonnet5 | 17.4min | 105 | 3 | $5.57 | — | bash | ok |
| Dependency License Checker | bash | sonnet5-1m-medium | 11.0min | 74 | 4 | $2.43 | — | bash | ok |
| Dependency License Checker | bash | sonnet5-low | 12.3min | 49 | 4 | $1.36 | — | bash | ok |
| Dependency License Checker | default | sonnet5 | 9.9min | 39 | 1 | $1.99 | — | python | ok |
| Dependency License Checker | default | sonnet5-1m-medium | 8.9min | 73 | 0 | $2.48 | — | python | ok |
| Dependency License Checker | default | sonnet5-low | 4.9min | 34 | 0 | $1.13 | — | python | ok |
| Dependency License Checker | powershell | sonnet5 | 16.8min | 80 | 0 | $3.03 | — | powershell | ok |
| Dependency License Checker | powershell | sonnet5-1m-medium | 13.5min | 52 | 3 | $2.14 | — | powershell | ok |
| Dependency License Checker | powershell | sonnet5-low | 7.6min | 39 | 0 | $1.17 | — | powershell | ok |
| Dependency License Checker | powershell-tool | sonnet5 | 14.6min | 58 | 1 | $2.80 | — | powershell | ok |
| Dependency License Checker | powershell-tool | sonnet5-1m-medium | 18.8min | 70 | 0 | $4.02 | — | powershell | ok |
| Dependency License Checker | typescript-bun | sonnet5 | 18.4min | 137 | 11 | $5.28 | — | typescript | ok |
| Dependency License Checker | typescript-bun | sonnet5-1m-medium | 13.6min | 93 | 1 | $2.82 | — | typescript | ok |
| Test Results Aggregator | bash | sonnet5 | 17.1min | 108 | 6 | $5.57 | — | bash | ok |
| Test Results Aggregator | bash | sonnet5-1m-medium | 8.5min | 46 | 0 | $1.80 | — | bash | ok |
| Test Results Aggregator | default | sonnet5 | 12.7min | 59 | 0 | $3.47 | — | python | ok |
| Test Results Aggregator | default | sonnet5-1m-medium | 10.1min | 61 | 0 | $2.37 | — | python | ok |
| Test Results Aggregator | powershell | sonnet5 | 30.0min | 0 | 0 | $0.00 | — | powershell | timeout |
| Test Results Aggregator | powershell | sonnet5-1m-medium | 12.6min | 58 | 0 | $2.54 | — | powershell | ok |
| Test Results Aggregator | powershell-tool | sonnet5 | 26.0min | 87 | 4 | $4.82 | — | powershell | ok |
| Test Results Aggregator | powershell-tool | sonnet5-1m-medium | 13.3min | 69 | 0 | $2.19 | — | powershell | ok |
| Test Results Aggregator | typescript-bun | sonnet5 | 25.3min | 143 | 2 | $7.29 | — | typescript | ok |
| Test Results Aggregator | typescript-bun | sonnet5-1m-medium | 12.8min | 101 | 1 | $2.92 | — | typescript | ok |
| Environment Matrix Generator | bash | sonnet5 | 26.2min | 150 | 9 | $8.03 | — | bash | ok |
| Environment Matrix Generator | bash | sonnet5-1m-medium | 14.2min | 67 | 0 | $2.90 | — | bash | ok |
| Environment Matrix Generator | default | sonnet5 | 16.4min | 94 | 2 | $5.01 | — | python | ok |
| Environment Matrix Generator | default | sonnet5-1m-medium | 6.9min | 59 | 0 | $1.72 | — | python | ok |
| Environment Matrix Generator | powershell | sonnet5 | 29.5min | 103 | 0 | $6.22 | — | powershell | ok |
| Environment Matrix Generator | powershell | sonnet5-1m-medium | 16.5min | 99 | 1 | $3.46 | — | powershell | ok |
| Environment Matrix Generator | powershell-tool | sonnet5 | 25.4min | 82 | 0 | $5.48 | — | powershell | ok |
| Environment Matrix Generator | powershell-tool | sonnet5-1m-medium | 15.8min | 55 | 0 | $2.82 | — | powershell | ok |
| Environment Matrix Generator | typescript-bun | sonnet5 | 19.7min | 75 | 1 | $4.76 | — | typescript | ok |
| Environment Matrix Generator | typescript-bun | sonnet5-1m-medium | 17.0min | 87 | 4 | $3.12 | — | typescript | ok |
| Artifact Cleanup Script | bash | sonnet5 | 11.8min | 59 | 4 | $3.37 | — | bash | ok |
| Artifact Cleanup Script | bash | sonnet5-1m-medium | 16.9min | 80 | 7 | $3.35 | — | bash | ok |
| Artifact Cleanup Script | default | sonnet5 | 18.0min | 76 | 1 | $3.61 | — | powershell | ok |
| Artifact Cleanup Script | default | sonnet5-1m-medium | 11.5min | 86 | 3 | $3.10 | — | python | ok |
| Artifact Cleanup Script | powershell | sonnet5 | 23.4min | 98 | 3 | $5.42 | — | powershell | ok |
| Artifact Cleanup Script | powershell | sonnet5-1m-medium | 11.3min | 38 | 0 | $1.90 | — | powershell | ok |
| Artifact Cleanup Script | powershell-tool | sonnet5 | 21.2min | 79 | 0 | $4.33 | — | powershell | ok |
| Artifact Cleanup Script | powershell-tool | sonnet5-1m-medium | 16.6min | 64 | 2 | $3.28 | — | powershell | ok |
| Artifact Cleanup Script | typescript-bun | sonnet5 | 23.5min | 150 | 2 | $6.00 | — | typescript | ok |
| Artifact Cleanup Script | typescript-bun | sonnet5-1m-medium | 13.7min | 109 | 0 | $3.28 | — | typescript | ok |
| Secret Rotation Validator | bash | sonnet5 | 20.7min | 119 | 1 | $6.24 | — | bash | ok |
| Secret Rotation Validator | bash | sonnet5-1m-medium | 9.3min | 0 | 4 | $0.00 | — | bash | cli_error |
| Secret Rotation Validator | default | sonnet5 | 12.7min | 69 | 0 | $3.58 | — | python | ok |
| Secret Rotation Validator | default | sonnet5-1m-medium | 5.5min | 38 | 3 | $1.44 | — | python | ok |
| Secret Rotation Validator | powershell | sonnet5 | 30.0min | 0 | 0 | $0.00 | — | powershell | timeout |
| Secret Rotation Validator | powershell | sonnet5-1m-medium | 10.2min | 43 | 0 | $1.49 | — | powershell | ok |
| Secret Rotation Validator | powershell-tool | sonnet5 | 22.6min | 102 | 2 | $4.46 | — | powershell | ok |
| Secret Rotation Validator | powershell-tool | sonnet5-1m-medium | 15.4min | 83 | 0 | $2.81 | — | powershell | ok |
| Secret Rotation Validator | typescript-bun | sonnet5 | 25.3min | 136 | 1 | $6.32 | — | typescript | ok |
| Secret Rotation Validator | typescript-bun | sonnet5-1m-medium | 11.2min | 65 | 1 | $2.19 | — | typescript | ok |

</details>

## Notes

### Tiers

- **Duration bands:** **A+** ≤1.15×, **A** ≤1.33×, **A-** ≤1.53×, **B+** ≤1.76×, **B** ≤2.03×, **B-** ≤2.34×, **C+** ≤2.70×, **C** ≤3.11×, **C-** ≤3.58×, **D+** ≤4.13×, **D** ≤4.76×, **D-** ≤5.48×, **F** >5.48×
- **Cost bands:** **A+** ≤1.16×, **A** ≤1.34×, **A-** ≤1.56×, **B+** ≤1.81×, **B** ≤2.10×, **B-** ≤2.43×, **C+** ≤2.82×, **C** ≤3.27×, **C-** ≤3.79×, **D+** ≤4.39×, **D** ≤5.09×, **D-** ≤5.90×, **F** >5.90×

*Tests/Workflow Craft bands are absolute Overall score bands:* **A+** ≥4.7, **A** ≥4.4, **A-** ≥4.1, **B+** ≥3.8, **B** ≥3.5, **B-** ≥3.2, **C+** ≥2.9, **C** ≥2.6, **C-** ≥2.3, **D+** ≥2.0, **D** ≥1.7, **D-** ≥1.4, **F** <1.4, `—` = no data.*

### CLI Version Legend

| Variant label | CLI version | Tasks | Languages |
|---------------|-------------|-------|-----------|
| sonnet5 | 2.1.197 | All | All |
| sonnet5-1m-medium | 2.1.197 | All | All |
| sonnet5-low | 2.1.197 | 11-semantic-version-bumper, 12-pr-label-assigner, 13-dependency-license-checker | All |

---
*Generated by generate_results.py — benchmark instructions v4*