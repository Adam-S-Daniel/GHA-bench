# Benchmark Results: Language Comparison

**Last updated:** 2026-07-01 04:58:21 AM ET — 28/35 runs completed, 7 remaining; total cost $107.41; total agent time 578.1 min.
**Claude Code versions used:** v2.1.197 (28 runs). Each link goes to a per-version snapshot of the system prompt, default-tool descriptions, and the chronological Anthropic changelog up to that version. Regenerate with `python3 version_docs.py`.

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
| default | sonnet5 | A+ (13.5min) | A+ ($3.54) | — | — |
| bash | sonnet5* | B (16.9min) | D+ ($5.08) | — | — |
| powershell-tool | sonnet5* | D- (23.2min) | C ($4.63) | — | — |
| powershell | sonnet5* | D- (23.2min) | C- ($4.89) | — | — |
| typescript-bun | sonnet5 | C- (20.1min) | D- ($5.52) | — | — |


<details>
<summary>Sorted by Duration tier (best-first), then avg of Cost/Tests/Workflow Craft tiers</summary>

| Language | Model | Duration | Cost | Tests Quality | Workflow Craft |
|----------|-------|----------|------|-----------|-------------|
| default | sonnet5 | A+ (13.5min) | A+ ($3.54) | — | — |
| bash | sonnet5* | B (16.9min) | D+ ($5.08) | — | — |
| typescript-bun | sonnet5 | C- (20.1min) | D- ($5.52) | — | — |
| powershell-tool | sonnet5* | D- (23.2min) | C ($4.63) | — | — |
| powershell | sonnet5* | D- (23.2min) | C- ($4.89) | — | — |

</details>

<details>
<summary>Sorted by Cost tier (best-first), then avg of Duration/Tests/Workflow Craft tiers</summary>

| Language | Model | Duration | Cost | Tests Quality | Workflow Craft |
|----------|-------|----------|------|-----------|-------------|
| default | sonnet5 | A+ (13.5min) | A+ ($3.54) | — | — |
| powershell-tool | sonnet5* | D- (23.2min) | C ($4.63) | — | — |
| powershell | sonnet5* | D- (23.2min) | C- ($4.89) | — | — |
| bash | sonnet5* | B (16.9min) | D+ ($5.08) | — | — |
| typescript-bun | sonnet5 | C- (20.1min) | D- ($5.52) | — | — |

</details>

<details>
<summary>Sorted by Tests Quality tier (best-first; no-data last), then avg of other tiers</summary>

| Language | Model | Duration | Cost | Tests Quality | Workflow Craft |
|----------|-------|----------|------|-----------|-------------|
| default | sonnet5 | A+ (13.5min) | A+ ($3.54) | — | — |
| bash | sonnet5* | B (16.9min) | D+ ($5.08) | — | — |
| powershell-tool | sonnet5* | D- (23.2min) | C ($4.63) | — | — |
| powershell | sonnet5* | D- (23.2min) | C- ($4.89) | — | — |
| typescript-bun | sonnet5 | C- (20.1min) | D- ($5.52) | — | — |

</details>

<details>
<summary>Sorted by Workflow Craft tier (best-first; no-data last), then avg of other tiers</summary>

| Language | Model | Duration | Cost | Tests Quality | Workflow Craft |
|----------|-------|----------|------|-----------|-------------|
| default | sonnet5 | A+ (13.5min) | A+ ($3.54) | — | — |
| bash | sonnet5* | B (16.9min) | D+ ($5.08) | — | — |
| powershell-tool | sonnet5* | D- (23.2min) | C ($4.63) | — | — |
| powershell | sonnet5* | D- (23.2min) | C- ($4.89) | — | — |
| typescript-bun | sonnet5 | C- (20.1min) | D- ($5.52) | — | — |

</details>

- **Estimated time remaining:** 144.5min
- **Estimated total cost:** $134.27

## Failed / Timed-Out Runs

| Task | Language | Model | Duration | Reason | Lines | actionlint | act-result.txt |
|------|------|-------|----------|--------|-------|------------|----------------|
| Semantic Version Bumper | powershell | sonnet5 | 30.0min | timeout | 667 | pass | yes |
| PR Label Assigner | powershell | sonnet5 | 30.0min | timeout | 806 | pass | yes |
| PR Label Assigner | bash | sonnet5 | 30.0min | timeout | 1034 | pass | yes |
| PR Label Assigner | powershell-tool | sonnet5 | 30.0min | timeout | 621 | pass | no |
| Test Results Aggregator | powershell | sonnet5 | 30.0min | timeout | 824 | pass | yes |

*5 run(s) excluded from averages below.*

## Comparison by Language/Model/Effort
*(averages exclude failed/timed-out runs)*
*See [Notes](#notes) for scoring rubric and CLI version legend.*

| Language | Model | Runs | Avg Duration | Avg Duration Net of Traps | Avg Errors | Avg Turns | Avg Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| bash | sonnet5* | 5 | 16.9min | 14.1min | 5.0 | 96 | $5.08 | $25.38 | — | — |
| default | sonnet5 | 6 | 13.5min | 12.0min | 1.0 | 71 | $3.54 | $21.24 | — | — |
| powershell | sonnet5* | 3 | 23.2min | 12.1min | 1.0 | 94 | $4.89 | $14.67 | — | — |
| powershell-tool | sonnet5* | 4 | 23.2min | 19.1min | 1.2 | 84 | $4.63 | $18.51 | — | — |
| typescript-bun | sonnet5 | 5 | 20.1min | 14.1min | 4.4 | 118 | $5.52 | $27.62 | — | — |


<details>
<summary>Sorted by avg cost (cheapest first)</summary>

| Language | Model | Runs | Avg Duration | Avg Duration Net of Traps | Avg Errors | Avg Turns | Avg Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| default | sonnet5 | 6 | 13.5min | 12.0min | 1.0 | 71 | $3.54 | $21.24 | — | — |
| powershell-tool | sonnet5* | 4 | 23.2min | 19.1min | 1.2 | 84 | $4.63 | $18.51 | — | — |
| powershell | sonnet5* | 3 | 23.2min | 12.1min | 1.0 | 94 | $4.89 | $14.67 | — | — |
| bash | sonnet5* | 5 | 16.9min | 14.1min | 5.0 | 96 | $5.08 | $25.38 | — | — |
| typescript-bun | sonnet5 | 5 | 20.1min | 14.1min | 4.4 | 118 | $5.52 | $27.62 | — | — |

</details>

<details>
<summary>Sorted by avg duration (fastest first)</summary>

| Language | Model | Runs | Avg Duration | Avg Duration Net of Traps | Avg Errors | Avg Turns | Avg Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| default | sonnet5 | 6 | 13.5min | 12.0min | 1.0 | 71 | $3.54 | $21.24 | — | — |
| bash | sonnet5* | 5 | 16.9min | 14.1min | 5.0 | 96 | $5.08 | $25.38 | — | — |
| typescript-bun | sonnet5 | 5 | 20.1min | 14.1min | 4.4 | 118 | $5.52 | $27.62 | — | — |
| powershell-tool | sonnet5* | 4 | 23.2min | 19.1min | 1.2 | 84 | $4.63 | $18.51 | — | — |
| powershell | sonnet5* | 3 | 23.2min | 12.1min | 1.0 | 94 | $4.89 | $14.67 | — | — |

</details>

<details>
<summary>Sorted by avg duration net of traps (fastest first)</summary>

| Language | Model | Runs | Avg Duration | Avg Duration Net of Traps | Avg Errors | Avg Turns | Avg Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| default | sonnet5 | 6 | 13.5min | 12.0min | 1.0 | 71 | $3.54 | $21.24 | — | — |
| powershell | sonnet5* | 3 | 23.2min | 12.1min | 1.0 | 94 | $4.89 | $14.67 | — | — |
| typescript-bun | sonnet5 | 5 | 20.1min | 14.1min | 4.4 | 118 | $5.52 | $27.62 | — | — |
| bash | sonnet5* | 5 | 16.9min | 14.1min | 5.0 | 96 | $5.08 | $25.38 | — | — |
| powershell-tool | sonnet5* | 4 | 23.2min | 19.1min | 1.2 | 84 | $4.63 | $18.51 | — | — |

</details>

<details>
<summary>Sorted by avg errors (fewest first)</summary>

| Language | Model | Runs | Avg Duration | Avg Duration Net of Traps | Avg Errors | Avg Turns | Avg Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| default | sonnet5 | 6 | 13.5min | 12.0min | 1.0 | 71 | $3.54 | $21.24 | — | — |
| powershell | sonnet5* | 3 | 23.2min | 12.1min | 1.0 | 94 | $4.89 | $14.67 | — | — |
| powershell-tool | sonnet5* | 4 | 23.2min | 19.1min | 1.2 | 84 | $4.63 | $18.51 | — | — |
| typescript-bun | sonnet5 | 5 | 20.1min | 14.1min | 4.4 | 118 | $5.52 | $27.62 | — | — |
| bash | sonnet5* | 5 | 16.9min | 14.1min | 5.0 | 96 | $5.08 | $25.38 | — | — |

</details>

<details>
<summary>Sorted by avg turns (fewest first)</summary>

| Language | Model | Runs | Avg Duration | Avg Duration Net of Traps | Avg Errors | Avg Turns | Avg Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| default | sonnet5 | 6 | 13.5min | 12.0min | 1.0 | 71 | $3.54 | $21.24 | — | — |
| powershell-tool | sonnet5* | 4 | 23.2min | 19.1min | 1.2 | 84 | $4.63 | $18.51 | — | — |
| powershell | sonnet5* | 3 | 23.2min | 12.1min | 1.0 | 94 | $4.89 | $14.67 | — | — |
| bash | sonnet5* | 5 | 16.9min | 14.1min | 5.0 | 96 | $5.08 | $25.38 | — | — |
| typescript-bun | sonnet5 | 5 | 20.1min | 14.1min | 4.4 | 118 | $5.52 | $27.62 | — | — |

</details>

<details>
<summary>Sorted by LLM-as-judge score (best first)</summary>

| Language | Model | Runs | Avg Duration | Avg Duration Net of Traps | Avg Errors | Avg Turns | Avg Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| bash | sonnet5* | 5 | 16.9min | 14.1min | 5.0 | 96 | $5.08 | $25.38 | — | — |
| default | sonnet5 | 6 | 13.5min | 12.0min | 1.0 | 71 | $3.54 | $21.24 | — | — |
| powershell | sonnet5* | 3 | 23.2min | 12.1min | 1.0 | 94 | $4.89 | $14.67 | — | — |
| powershell-tool | sonnet5* | 4 | 23.2min | 19.1min | 1.2 | 84 | $4.63 | $18.51 | — | — |
| typescript-bun | sonnet5 | 5 | 20.1min | 14.1min | 4.4 | 118 | $5.52 | $27.62 | — | — |

</details>

<details>
<summary>Sorted by deliverable-quality score (best first)</summary>

| Language | Model | Runs | Avg Duration | Avg Duration Net of Traps | Avg Errors | Avg Turns | Avg Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| bash | sonnet5* | 5 | 16.9min | 14.1min | 5.0 | 96 | $5.08 | $25.38 | — | — |
| default | sonnet5 | 6 | 13.5min | 12.0min | 1.0 | 71 | $3.54 | $21.24 | — | — |
| powershell | sonnet5* | 3 | 23.2min | 12.1min | 1.0 | 94 | $4.89 | $14.67 | — | — |
| powershell-tool | sonnet5* | 4 | 23.2min | 19.1min | 1.2 | 84 | $4.63 | $18.51 | — | — |
| typescript-bun | sonnet5 | 5 | 20.1min | 14.1min | 4.4 | 118 | $5.52 | $27.62 | — | — |

</details>

## Savings Analysis

### Hook Savings by Language/Model/Effort

Each hook-caught error avoids one test run that would otherwise have been needed to discover it.
Every hook fire (hit or miss) costs execution time for the syntax/type checker.

*`% of Test Time Saved` = `net / (net + test_time) × 100` — the share of total (would-have-been + actually-spent) test time that hooks eliminated. Bounded in (-∞, 100%) without an artificial cap; near 100% means hooks substituted for almost all of the hypothetical test work.*

| Language | Model | Fires | Caught | Rate | Gross Saved | % of Time | Overhead | % of Time | Net Saved | % of Time | Test Run Time | % of Test Time Saved |
|------|-------|-------|--------|------|------------|-----------|----------|-----------|-----------|-----------|---------------|----------------------|
| bash | sonnet5-cli2.1.197 | 153 | 14 | 9.2% | 2.8min | 0.5% | 0.5min | 0.1% | 2.3min | 0.4% | 21.2min | 9.9% |
| default | sonnet5-cli2.1.197 | 133 | 4 | 3.0% | 0.5min | 0.1% | 2.7min | 0.5% | -2.2min | -0.4% | 11.8min | -22.4% |
| powershell | sonnet5-cli2.1.197 | 177 | 24 | 13.6% | 14.0min | 2.4% | 25.8min | 4.5% | -11.8min | -2.0% | 24.9min | -90.1% |
| powershell-tool | sonnet5-cli2.1.197 | 128 | 23 | 18.0% | 13.4min | 2.3% | 20.1min | 3.5% | -6.7min | -1.2% | 18.7min | -56.0% |
| typescript-bun | sonnet5-cli2.1.197 | 197 | 86 | 43.7% | 11.5min | 2.0% | 10.1min | 1.8% | 1.3min | 0.2% | 10.2min | 11.6% |


<details>
<summary>Sorted by net saved (most first)</summary>

| Language | Model | Fires | Caught | Rate | Gross Saved | % of Time | Overhead | % of Time | Net Saved | % of Time | Test Run Time | % of Test Time Saved |
|------|-------|-------|--------|------|------------|-----------|----------|-----------|-----------|-----------|---------------|----------------------|
| bash | sonnet5-cli2.1.197 | 153 | 14 | 9.2% | 2.8min | 0.5% | 0.5min | 0.1% | 2.3min | 0.4% | 21.2min | 9.9% |
| typescript-bun | sonnet5-cli2.1.197 | 197 | 86 | 43.7% | 11.5min | 2.0% | 10.1min | 1.8% | 1.3min | 0.2% | 10.2min | 11.6% |
| default | sonnet5-cli2.1.197 | 133 | 4 | 3.0% | 0.5min | 0.1% | 2.7min | 0.5% | -2.2min | -0.4% | 11.8min | -22.4% |
| powershell-tool | sonnet5-cli2.1.197 | 128 | 23 | 18.0% | 13.4min | 2.3% | 20.1min | 3.5% | -6.7min | -1.2% | 18.7min | -56.0% |
| powershell | sonnet5-cli2.1.197 | 177 | 24 | 13.6% | 14.0min | 2.4% | 25.8min | 4.5% | -11.8min | -2.0% | 24.9min | -90.1% |

</details>

<details>
<summary>Sorted by net % of test time saved (most first)</summary>

| Language | Model | Fires | Caught | Rate | Gross Saved | % of Time | Overhead | % of Time | Net Saved | % of Time | Test Run Time | % of Test Time Saved |
|------|-------|-------|--------|------|------------|-----------|----------|-----------|-----------|-----------|---------------|----------------------|
| typescript-bun | sonnet5-cli2.1.197 | 197 | 86 | 43.7% | 11.5min | 2.0% | 10.1min | 1.8% | 1.3min | 0.2% | 10.2min | 11.6% |
| bash | sonnet5-cli2.1.197 | 153 | 14 | 9.2% | 2.8min | 0.5% | 0.5min | 0.1% | 2.3min | 0.4% | 21.2min | 9.9% |
| default | sonnet5-cli2.1.197 | 133 | 4 | 3.0% | 0.5min | 0.1% | 2.7min | 0.5% | -2.2min | -0.4% | 11.8min | -22.4% |
| powershell-tool | sonnet5-cli2.1.197 | 128 | 23 | 18.0% | 13.4min | 2.3% | 20.1min | 3.5% | -6.7min | -1.2% | 18.7min | -56.0% |
| powershell | sonnet5-cli2.1.197 | 177 | 24 | 13.6% | 14.0min | 2.4% | 25.8min | 4.5% | -11.8min | -2.0% | 24.9min | -90.1% |

</details>

<details>
<summary>Sorted by catch rate (highest first)</summary>

| Language | Model | Fires | Caught | Rate | Gross Saved | % of Time | Overhead | % of Time | Net Saved | % of Time | Test Run Time | % of Test Time Saved |
|------|-------|-------|--------|------|------------|-----------|----------|-----------|-----------|-----------|---------------|----------------------|
| typescript-bun | sonnet5-cli2.1.197 | 197 | 86 | 43.7% | 11.5min | 2.0% | 10.1min | 1.8% | 1.3min | 0.2% | 10.2min | 11.6% |
| powershell-tool | sonnet5-cli2.1.197 | 128 | 23 | 18.0% | 13.4min | 2.3% | 20.1min | 3.5% | -6.7min | -1.2% | 18.7min | -56.0% |
| powershell | sonnet5-cli2.1.197 | 177 | 24 | 13.6% | 14.0min | 2.4% | 25.8min | 4.5% | -11.8min | -2.0% | 24.9min | -90.1% |
| bash | sonnet5-cli2.1.197 | 153 | 14 | 9.2% | 2.8min | 0.5% | 0.5min | 0.1% | 2.3min | 0.4% | 21.2min | 9.9% |
| default | sonnet5-cli2.1.197 | 133 | 4 | 3.0% | 0.5min | 0.1% | 2.7min | 0.5% | -2.2min | -0.4% | 11.8min | -22.4% |

</details>

### Trap Analysis by Language/Model/Effort/Category

| Trap | Language | Model | Fell In | Time Lost | % of Time | $ Lost | % of $ |
|------|------|-------|---------|-----------|-----------|--------|--------|
| repeated-test-reruns | bash | sonnet5-cli2.1.197 | 4 | 5.3min | 0.9% | $1.63 | 1.52% |
| repeated-test-reruns | default | sonnet5-cli2.1.197 | 3 | 7.0min | 1.2% | $1.79 | 1.67% |
| repeated-test-reruns | powershell | sonnet5-cli2.1.197 | 11 | 25.3min | 4.4% | $2.11 | 1.97% |
| repeated-test-reruns | powershell-tool | sonnet5-cli2.1.197 | 6 | 12.3min | 2.1% | $1.75 | 1.63% |
| repeated-test-reruns | typescript-bun | sonnet5-cli2.1.197 | 2 | 6.0min | 1.0% | $1.39 | 1.29% |
| fixture-rework | bash | sonnet5-cli2.1.197 | 5 | 6.8min | 1.2% | $1.89 | 1.76% |
| fixture-rework | default | sonnet5-cli2.1.197 | 4 | 2.0min | 0.3% | $0.51 | 0.47% |
| fixture-rework | powershell | sonnet5-cli2.1.197 | 3 | 2.8min | 0.5% | $0.12 | 0.11% |
| fixture-rework | powershell-tool | sonnet5-cli2.1.197 | 1 | 2.0min | 0.3% | $0.37 | 0.34% |
| fixture-rework | typescript-bun | sonnet5-cli2.1.197 | 5 | 5.2min | 0.9% | $1.49 | 1.39% |
| ts-type-error-fix-cycles | typescript-bun | sonnet5-cli2.1.197 | 5 | 17.2min | 3.0% | $4.86 | 4.53% |
| act-push-debug-loops | bash | sonnet5-cli2.1.197 | 1 | 0.8min | 0.1% | $0.24 | 0.22% |
| act-push-debug-loops | powershell | sonnet5-cli2.1.197 | 1 | 1.7min | 0.3% | $0.35 | 0.33% |
| act-push-debug-loops | powershell-tool | sonnet5-cli2.1.197 | 1 | 2.0min | 0.3% | $0.40 | 0.37% |
| docker-pwsh-install | powershell | sonnet5-cli2.1.197 | 2 | 3.8min | 0.6% | $0.72 | 0.67% |
| actionlint-fix-cycles | typescript-bun | sonnet5-cli2.1.197 | 2 | 1.7min | 0.3% | $0.39 | 0.36% |
| bats-setup-issues | bash | sonnet5-cli2.1.197 | 1 | 0.8min | 0.1% | $0.23 | 0.21% |


<details>
<summary>Sorted by time lost (least first)</summary>

| Trap | Language | Model | Fell In | Time Lost | % of Time | $ Lost | % of $ |
|------|------|-------|---------|-----------|-----------|--------|--------|
| bats-setup-issues | bash | sonnet5-cli2.1.197 | 1 | 0.8min | 0.1% | $0.23 | 0.21% |
| act-push-debug-loops | bash | sonnet5-cli2.1.197 | 1 | 0.8min | 0.1% | $0.24 | 0.22% |
| act-push-debug-loops | powershell | sonnet5-cli2.1.197 | 1 | 1.7min | 0.3% | $0.35 | 0.33% |
| actionlint-fix-cycles | typescript-bun | sonnet5-cli2.1.197 | 2 | 1.7min | 0.3% | $0.39 | 0.36% |
| act-push-debug-loops | powershell-tool | sonnet5-cli2.1.197 | 1 | 2.0min | 0.3% | $0.40 | 0.37% |
| fixture-rework | default | sonnet5-cli2.1.197 | 4 | 2.0min | 0.3% | $0.51 | 0.47% |
| fixture-rework | powershell-tool | sonnet5-cli2.1.197 | 1 | 2.0min | 0.3% | $0.37 | 0.34% |
| fixture-rework | powershell | sonnet5-cli2.1.197 | 3 | 2.8min | 0.5% | $0.12 | 0.11% |
| docker-pwsh-install | powershell | sonnet5-cli2.1.197 | 2 | 3.8min | 0.6% | $0.72 | 0.67% |
| fixture-rework | typescript-bun | sonnet5-cli2.1.197 | 5 | 5.2min | 0.9% | $1.49 | 1.39% |
| repeated-test-reruns | bash | sonnet5-cli2.1.197 | 4 | 5.3min | 0.9% | $1.63 | 1.52% |
| repeated-test-reruns | typescript-bun | sonnet5-cli2.1.197 | 2 | 6.0min | 1.0% | $1.39 | 1.29% |
| fixture-rework | bash | sonnet5-cli2.1.197 | 5 | 6.8min | 1.2% | $1.89 | 1.76% |
| repeated-test-reruns | default | sonnet5-cli2.1.197 | 3 | 7.0min | 1.2% | $1.79 | 1.67% |
| repeated-test-reruns | powershell-tool | sonnet5-cli2.1.197 | 6 | 12.3min | 2.1% | $1.75 | 1.63% |
| ts-type-error-fix-cycles | typescript-bun | sonnet5-cli2.1.197 | 5 | 17.2min | 3.0% | $4.86 | 4.53% |
| repeated-test-reruns | powershell | sonnet5-cli2.1.197 | 11 | 25.3min | 4.4% | $2.11 | 1.97% |

</details>

<details>
<summary>Sorted by $ lost (least first)</summary>

| Trap | Language | Model | Fell In | Time Lost | % of Time | $ Lost | % of $ |
|------|------|-------|---------|-----------|-----------|--------|--------|
| fixture-rework | powershell | sonnet5-cli2.1.197 | 3 | 2.8min | 0.5% | $0.12 | 0.11% |
| bats-setup-issues | bash | sonnet5-cli2.1.197 | 1 | 0.8min | 0.1% | $0.23 | 0.21% |
| act-push-debug-loops | bash | sonnet5-cli2.1.197 | 1 | 0.8min | 0.1% | $0.24 | 0.22% |
| act-push-debug-loops | powershell | sonnet5-cli2.1.197 | 1 | 1.7min | 0.3% | $0.35 | 0.33% |
| fixture-rework | powershell-tool | sonnet5-cli2.1.197 | 1 | 2.0min | 0.3% | $0.37 | 0.34% |
| actionlint-fix-cycles | typescript-bun | sonnet5-cli2.1.197 | 2 | 1.7min | 0.3% | $0.39 | 0.36% |
| act-push-debug-loops | powershell-tool | sonnet5-cli2.1.197 | 1 | 2.0min | 0.3% | $0.40 | 0.37% |
| fixture-rework | default | sonnet5-cli2.1.197 | 4 | 2.0min | 0.3% | $0.51 | 0.47% |
| docker-pwsh-install | powershell | sonnet5-cli2.1.197 | 2 | 3.8min | 0.6% | $0.72 | 0.67% |
| repeated-test-reruns | typescript-bun | sonnet5-cli2.1.197 | 2 | 6.0min | 1.0% | $1.39 | 1.29% |
| fixture-rework | typescript-bun | sonnet5-cli2.1.197 | 5 | 5.2min | 0.9% | $1.49 | 1.39% |
| repeated-test-reruns | bash | sonnet5-cli2.1.197 | 4 | 5.3min | 0.9% | $1.63 | 1.52% |
| repeated-test-reruns | powershell-tool | sonnet5-cli2.1.197 | 6 | 12.3min | 2.1% | $1.75 | 1.63% |
| repeated-test-reruns | default | sonnet5-cli2.1.197 | 3 | 7.0min | 1.2% | $1.79 | 1.67% |
| fixture-rework | bash | sonnet5-cli2.1.197 | 5 | 6.8min | 1.2% | $1.89 | 1.76% |
| repeated-test-reruns | powershell | sonnet5-cli2.1.197 | 11 | 25.3min | 4.4% | $2.11 | 1.97% |
| ts-type-error-fix-cycles | typescript-bun | sonnet5-cli2.1.197 | 5 | 17.2min | 3.0% | $4.86 | 4.53% |

</details>

<details>
<summary>Sorted by fell-in count (fewest first)</summary>

| Trap | Language | Model | Fell In | Time Lost | % of Time | $ Lost | % of $ |
|------|------|-------|---------|-----------|-----------|--------|--------|
| fixture-rework | powershell-tool | sonnet5-cli2.1.197 | 1 | 2.0min | 0.3% | $0.37 | 0.34% |
| act-push-debug-loops | bash | sonnet5-cli2.1.197 | 1 | 0.8min | 0.1% | $0.24 | 0.22% |
| act-push-debug-loops | powershell | sonnet5-cli2.1.197 | 1 | 1.7min | 0.3% | $0.35 | 0.33% |
| act-push-debug-loops | powershell-tool | sonnet5-cli2.1.197 | 1 | 2.0min | 0.3% | $0.40 | 0.37% |
| bats-setup-issues | bash | sonnet5-cli2.1.197 | 1 | 0.8min | 0.1% | $0.23 | 0.21% |
| repeated-test-reruns | typescript-bun | sonnet5-cli2.1.197 | 2 | 6.0min | 1.0% | $1.39 | 1.29% |
| docker-pwsh-install | powershell | sonnet5-cli2.1.197 | 2 | 3.8min | 0.6% | $0.72 | 0.67% |
| actionlint-fix-cycles | typescript-bun | sonnet5-cli2.1.197 | 2 | 1.7min | 0.3% | $0.39 | 0.36% |
| repeated-test-reruns | default | sonnet5-cli2.1.197 | 3 | 7.0min | 1.2% | $1.79 | 1.67% |
| fixture-rework | powershell | sonnet5-cli2.1.197 | 3 | 2.8min | 0.5% | $0.12 | 0.11% |
| repeated-test-reruns | bash | sonnet5-cli2.1.197 | 4 | 5.3min | 0.9% | $1.63 | 1.52% |
| fixture-rework | default | sonnet5-cli2.1.197 | 4 | 2.0min | 0.3% | $0.51 | 0.47% |
| fixture-rework | bash | sonnet5-cli2.1.197 | 5 | 6.8min | 1.2% | $1.89 | 1.76% |
| fixture-rework | typescript-bun | sonnet5-cli2.1.197 | 5 | 5.2min | 0.9% | $1.49 | 1.39% |
| ts-type-error-fix-cycles | typescript-bun | sonnet5-cli2.1.197 | 5 | 17.2min | 3.0% | $4.86 | 4.53% |
| repeated-test-reruns | powershell-tool | sonnet5-cli2.1.197 | 6 | 12.3min | 2.1% | $1.75 | 1.63% |
| repeated-test-reruns | powershell | sonnet5-cli2.1.197 | 11 | 25.3min | 4.4% | $2.11 | 1.97% |

</details>

#### Trap Descriptions

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
| bash | sonnet5-cli2.1.197 | 6 | 11 | 13.6min | 2.4% | $3.99 | 3.72% |
| default | sonnet5-cli2.1.197 | 6 | 7 | 9.0min | 1.6% | $2.30 | 2.15% |
| powershell | sonnet5-cli2.1.197 | 6 | 17 | 33.5min | 5.8% | $3.30 | 3.07% |
| powershell-tool | sonnet5-cli2.1.197 | 5 | 8 | 16.3min | 2.8% | $2.52 | 2.35% |
| typescript-bun | sonnet5-cli2.1.197 | 5 | 14 | 30.1min | 5.2% | $8.13 | 7.57% |


<details>
<summary>Sorted by time lost (least first)</summary>

| Language | Model | Runs | Traps | Time Lost | % of Time | $ Lost | % of $ |
|------|-------|------|-------|-----------|-----------|--------|--------|
| default | sonnet5-cli2.1.197 | 6 | 7 | 9.0min | 1.6% | $2.30 | 2.15% |
| bash | sonnet5-cli2.1.197 | 6 | 11 | 13.6min | 2.4% | $3.99 | 3.72% |
| powershell-tool | sonnet5-cli2.1.197 | 5 | 8 | 16.3min | 2.8% | $2.52 | 2.35% |
| typescript-bun | sonnet5-cli2.1.197 | 5 | 14 | 30.1min | 5.2% | $8.13 | 7.57% |
| powershell | sonnet5-cli2.1.197 | 6 | 17 | 33.5min | 5.8% | $3.30 | 3.07% |

</details>

<details>
<summary>Sorted by $ lost (least first)</summary>

| Language | Model | Runs | Traps | Time Lost | % of Time | $ Lost | % of $ |
|------|-------|------|-------|-----------|-----------|--------|--------|
| default | sonnet5-cli2.1.197 | 6 | 7 | 9.0min | 1.6% | $2.30 | 2.15% |
| powershell-tool | sonnet5-cli2.1.197 | 5 | 8 | 16.3min | 2.8% | $2.52 | 2.35% |
| powershell | sonnet5-cli2.1.197 | 6 | 17 | 33.5min | 5.8% | $3.30 | 3.07% |
| bash | sonnet5-cli2.1.197 | 6 | 11 | 13.6min | 2.4% | $3.99 | 3.72% |
| typescript-bun | sonnet5-cli2.1.197 | 5 | 14 | 30.1min | 5.2% | $8.13 | 7.57% |

</details>

### Prompt Cache Savings

| Status | Runs | $ Saved | % of $ |
|--------|------|---------|--------|
| Full hit (100%) | 0 | $0.00 | 0.00% |
| Partial | 28 | $2.53 | 2.36% |
| Miss | 0 | $0.00 | 0.00% |

## Test Quality Evaluation

### Structural Metrics by Language/Model/Effort

Automated analysis of test files: test count, assertion count, and test-to-code line ratio.

| Language | Model | Avg Tests | Avg Assertions | Avg Assert/Test | Avg Test:Code Ratio |
|------|-------|-----------|----------------|-----------------|---------------------|
| bash | sonnet5 | 28.5 | 55.2 | 1.9 | 0.78 |
| default | sonnet5 | 23.5 | 40.0 | 1.7 | 0.81 |
| powershell | sonnet5 | 52.3 | 95.2 | 1.8 | 4.96 |
| powershell-tool | sonnet5 | 42.6 | 74.2 | 1.7 | 5.38 |
| typescript-bun | sonnet5 | 40.0 | 73.0 | 1.8 | 1.56 |


<details>
<summary>Sorted by avg tests (most first)</summary>

| Language | Model | Avg Tests | Avg Assertions | Avg Assert/Test | Avg Test:Code Ratio |
|------|-------|-----------|----------------|-----------------|---------------------|
| powershell | sonnet5 | 52.3 | 95.2 | 1.8 | 4.96 |
| powershell-tool | sonnet5 | 42.6 | 74.2 | 1.7 | 5.38 |
| typescript-bun | sonnet5 | 40.0 | 73.0 | 1.8 | 1.56 |
| bash | sonnet5 | 28.5 | 55.2 | 1.9 | 0.78 |
| default | sonnet5 | 23.5 | 40.0 | 1.7 | 0.81 |

</details>

<details>
<summary>Sorted by avg assertions (most first)</summary>

| Language | Model | Avg Tests | Avg Assertions | Avg Assert/Test | Avg Test:Code Ratio |
|------|-------|-----------|----------------|-----------------|---------------------|
| powershell | sonnet5 | 52.3 | 95.2 | 1.8 | 4.96 |
| powershell-tool | sonnet5 | 42.6 | 74.2 | 1.7 | 5.38 |
| typescript-bun | sonnet5 | 40.0 | 73.0 | 1.8 | 1.56 |
| bash | sonnet5 | 28.5 | 55.2 | 1.9 | 0.78 |
| default | sonnet5 | 23.5 | 40.0 | 1.7 | 0.81 |

</details>

<details>
<summary>Sorted by avg test:code ratio (highest first)</summary>

| Language | Model | Avg Tests | Avg Assertions | Avg Assert/Test | Avg Test:Code Ratio |
|------|-------|-----------|----------------|-----------------|---------------------|
| powershell-tool | sonnet5 | 42.6 | 74.2 | 1.7 | 5.38 |
| powershell | sonnet5 | 52.3 | 95.2 | 1.8 | 4.96 |
| typescript-bun | sonnet5 | 40.0 | 73.0 | 1.8 | 1.56 |
| default | sonnet5 | 23.5 | 40.0 | 1.7 | 0.81 |
| bash | sonnet5 | 28.5 | 55.2 | 1.9 | 0.78 |

</details>


<details>
<summary>Per-run structural metrics</summary>

| Task | Language | Model | Tests | Assertions | Assert/Test | Test Lines | Impl Lines | Test:Code |
|------|------|-------|-------|------------|-------------|------------|------------|-----------|
| Semantic Version Bumper | default | sonnet5 | 38 | 60 | 1.6 | 438 | 336 | 1.30 |
| Semantic Version Bumper | powershell | sonnet5 | 43 | 87 | 2.0 | 514 | 89 | 5.78 |
| Semantic Version Bumper | bash | sonnet5 | 7 | 20 | 2.9 | 77 | 238 | 0.32 |
| Semantic Version Bumper | powershell-tool | sonnet5 | 51 | 88 | 1.7 | 649 | 72 | 9.01 |
| Semantic Version Bumper | typescript-bun | sonnet5 | 51 | 88 | 1.7 | 869 | 470 | 1.85 |
| PR Label Assigner | default | sonnet5 | 30 | 57 | 1.9 | 323 | 319 | 1.01 |
| PR Label Assigner | powershell | sonnet5 | 58 | 77 | 1.3 | 504 | 215 | 2.34 |
| PR Label Assigner | bash | sonnet5 | 52 | 100 | 1.9 | 517 | 447 | 1.16 |
| PR Label Assigner | powershell-tool | sonnet5 | 59 | 92 | 1.6 | 472 | 71 | 6.65 |
| PR Label Assigner | typescript-bun | sonnet5 | 35 | 40 | 1.1 | 317 | 404 | 0.78 |
| Dependency License Checker | default | sonnet5 | 8 | 30 | 3.8 | 218 | 274 | 0.80 |
| Dependency License Checker | powershell | sonnet5 | 37 | 52 | 1.4 | 384 | 181 | 2.12 |
| Dependency License Checker | bash | sonnet5 | 39 | 95 | 2.4 | 521 | 395 | 1.32 |
| Dependency License Checker | powershell-tool | sonnet5 | 31 | 58 | 1.9 | 340 | 87 | 3.91 |
| Dependency License Checker | typescript-bun | sonnet5 | 40 | 65 | 1.6 | 579 | 385 | 1.50 |
| Test Results Aggregator | default | sonnet5 | 12 | 28 | 2.3 | 317 | 430 | 0.74 |
| Test Results Aggregator | powershell | sonnet5 | 72 | 128 | 1.8 | 597 | 173 | 3.45 |
| Test Results Aggregator | bash | sonnet5 | 24 | 30 | 1.2 | 221 | 578 | 0.38 |
| Test Results Aggregator | powershell-tool | sonnet5 | 23 | 30 | 1.3 | 292 | 51 | 5.73 |
| Test Results Aggregator | typescript-bun | sonnet5 | 34 | 96 | 2.8 | 661 | 456 | 1.45 |
| Environment Matrix Generator | default | sonnet5 | 43 | 43 | 1.0 | 433 | 422 | 1.03 |
| Environment Matrix Generator | powershell | sonnet5 | 47 | 110 | 2.3 | 467 | 41 | 11.39 |
| Environment Matrix Generator | bash | sonnet5 | 27 | 73 | 2.7 | 263 | 327 | 0.80 |
| Environment Matrix Generator | powershell-tool | sonnet5 | 49 | 103 | 2.1 | 531 | 332 | 1.60 |
| Environment Matrix Generator | typescript-bun | sonnet5 | 40 | 76 | 1.9 | 630 | 287 | 2.20 |
| Artifact Cleanup Script | default | sonnet5 | 10 | 22 | 2.2 | 103 | 0 | 0.00 |
| Artifact Cleanup Script | powershell | sonnet5 | 57 | 117 | 2.1 | 570 | 122 | 4.67 |
| Artifact Cleanup Script | bash | sonnet5 | 22 | 13 | 0.6 | 209 | 293 | 0.71 |

</details>

## Per-Run Results

*Tests Quality = Overall (1-5) from LLM-as-judge of generated test code (dimensions: coverage, rigor, design). `—` = no judge data.*

| Task | Language | Model | Duration | Turns | Errors | Cost | Tests Quality | Chosen | Status |
|------|----------|-------|----------|-------|--------|------|-----------|--------|--------|
| Artifact Cleanup Script | bash | sonnet5 | 11.8min | 59 | 4 | $3.37 | — | bash | ok |
| Artifact Cleanup Script | default | sonnet5 | 18.0min | 76 | 1 | $3.61 | — | powershell | ok |
| Artifact Cleanup Script | powershell | sonnet5 | 23.4min | 98 | 3 | $5.42 | — | powershell | ok |
| Dependency License Checker | bash | sonnet5 | 17.4min | 105 | 3 | $5.57 | — | bash | ok |
| Dependency License Checker | default | sonnet5 | 9.9min | 39 | 1 | $1.99 | — | python | ok |
| Dependency License Checker | powershell | sonnet5 | 16.8min | 80 | 0 | $3.03 | — | powershell | ok |
| Dependency License Checker | powershell-tool | sonnet5 | 14.6min | 58 | 1 | $2.80 | — | powershell | ok |
| Dependency License Checker | typescript-bun | sonnet5 | 18.4min | 137 | 11 | $5.28 | — | typescript | ok |
| Environment Matrix Generator | bash | sonnet5 | 26.2min | 150 | 9 | $8.03 | — | bash | ok |
| Environment Matrix Generator | default | sonnet5 | 16.4min | 94 | 2 | $5.01 | — | python | ok |
| Environment Matrix Generator | powershell | sonnet5 | 29.5min | 103 | 0 | $6.22 | — | powershell | ok |
| Environment Matrix Generator | powershell-tool | sonnet5 | 25.4min | 82 | 0 | $5.48 | — | powershell | ok |
| Environment Matrix Generator | typescript-bun | sonnet5 | 19.7min | 75 | 1 | $4.76 | — | typescript | ok |
| PR Label Assigner | bash | sonnet5 | 30.0min | 0 | 2 | $0.00 | — | bash | timeout |
| PR Label Assigner | default | sonnet5 | 11.6min | 80 | 0 | $3.61 | — | python | ok |
| PR Label Assigner | powershell | sonnet5 | 30.0min | 0 | 1 | $0.00 | — | powershell | timeout |
| PR Label Assigner | powershell-tool | sonnet5 | 30.0min | 0 | 4 | $0.00 | — | powershell | timeout |
| PR Label Assigner | typescript-bun | sonnet5 | 18.3min | 106 | 0 | $4.13 | — | typescript | ok |
| Semantic Version Bumper | bash | sonnet5 | 11.8min | 57 | 3 | $2.84 | — | bash | ok |
| Semantic Version Bumper | default | sonnet5 | 12.5min | 80 | 2 | $3.54 | — | python | ok |
| Semantic Version Bumper | powershell | sonnet5 | 30.0min | 0 | 1 | $0.00 | — | powershell | timeout |
| Semantic Version Bumper | powershell-tool | sonnet5 | 26.7min | 111 | 0 | $5.41 | — | powershell | ok |
| Semantic Version Bumper | typescript-bun | sonnet5 | 18.6min | 127 | 8 | $6.16 | — | typescript | ok |
| Test Results Aggregator | bash | sonnet5 | 17.1min | 108 | 6 | $5.57 | — | bash | ok |
| Test Results Aggregator | default | sonnet5 | 12.7min | 59 | 0 | $3.47 | — | python | ok |
| Test Results Aggregator | powershell | sonnet5 | 30.0min | 0 | 0 | $0.00 | — | powershell | timeout |
| Test Results Aggregator | powershell-tool | sonnet5 | 26.0min | 87 | 4 | $4.82 | — | powershell | ok |
| Test Results Aggregator | typescript-bun | sonnet5 | 25.3min | 143 | 2 | $7.29 | — | typescript | ok |


<details>
<summary>Sorted by cost (cheapest first)</summary>

| Task | Language | Model | Duration | Turns | Errors | Cost | Tests Quality | Chosen | Status |
|------|----------|-------|----------|-------|--------|------|-----------|--------|--------|
| Semantic Version Bumper | powershell | sonnet5 | 30.0min | 0 | 1 | $0.00 | — | powershell | timeout |
| PR Label Assigner | powershell | sonnet5 | 30.0min | 0 | 1 | $0.00 | — | powershell | timeout |
| PR Label Assigner | bash | sonnet5 | 30.0min | 0 | 2 | $0.00 | — | bash | timeout |
| PR Label Assigner | powershell-tool | sonnet5 | 30.0min | 0 | 4 | $0.00 | — | powershell | timeout |
| Test Results Aggregator | powershell | sonnet5 | 30.0min | 0 | 0 | $0.00 | — | powershell | timeout |
| Dependency License Checker | default | sonnet5 | 9.9min | 39 | 1 | $1.99 | — | python | ok |
| Dependency License Checker | powershell-tool | sonnet5 | 14.6min | 58 | 1 | $2.80 | — | powershell | ok |
| Semantic Version Bumper | bash | sonnet5 | 11.8min | 57 | 3 | $2.84 | — | bash | ok |
| Dependency License Checker | powershell | sonnet5 | 16.8min | 80 | 0 | $3.03 | — | powershell | ok |
| Artifact Cleanup Script | bash | sonnet5 | 11.8min | 59 | 4 | $3.37 | — | bash | ok |
| Test Results Aggregator | default | sonnet5 | 12.7min | 59 | 0 | $3.47 | — | python | ok |
| Semantic Version Bumper | default | sonnet5 | 12.5min | 80 | 2 | $3.54 | — | python | ok |
| PR Label Assigner | default | sonnet5 | 11.6min | 80 | 0 | $3.61 | — | python | ok |
| Artifact Cleanup Script | default | sonnet5 | 18.0min | 76 | 1 | $3.61 | — | powershell | ok |
| PR Label Assigner | typescript-bun | sonnet5 | 18.3min | 106 | 0 | $4.13 | — | typescript | ok |
| Environment Matrix Generator | typescript-bun | sonnet5 | 19.7min | 75 | 1 | $4.76 | — | typescript | ok |
| Test Results Aggregator | powershell-tool | sonnet5 | 26.0min | 87 | 4 | $4.82 | — | powershell | ok |
| Environment Matrix Generator | default | sonnet5 | 16.4min | 94 | 2 | $5.01 | — | python | ok |
| Dependency License Checker | typescript-bun | sonnet5 | 18.4min | 137 | 11 | $5.28 | — | typescript | ok |
| Semantic Version Bumper | powershell-tool | sonnet5 | 26.7min | 111 | 0 | $5.41 | — | powershell | ok |
| Artifact Cleanup Script | powershell | sonnet5 | 23.4min | 98 | 3 | $5.42 | — | powershell | ok |
| Environment Matrix Generator | powershell-tool | sonnet5 | 25.4min | 82 | 0 | $5.48 | — | powershell | ok |
| Test Results Aggregator | bash | sonnet5 | 17.1min | 108 | 6 | $5.57 | — | bash | ok |
| Dependency License Checker | bash | sonnet5 | 17.4min | 105 | 3 | $5.57 | — | bash | ok |
| Semantic Version Bumper | typescript-bun | sonnet5 | 18.6min | 127 | 8 | $6.16 | — | typescript | ok |
| Environment Matrix Generator | powershell | sonnet5 | 29.5min | 103 | 0 | $6.22 | — | powershell | ok |
| Test Results Aggregator | typescript-bun | sonnet5 | 25.3min | 143 | 2 | $7.29 | — | typescript | ok |
| Environment Matrix Generator | bash | sonnet5 | 26.2min | 150 | 9 | $8.03 | — | bash | ok |

</details>

<details>
<summary>Sorted by duration (fastest first)</summary>

| Task | Language | Model | Duration | Turns | Errors | Cost | Tests Quality | Chosen | Status |
|------|----------|-------|----------|-------|--------|------|-----------|--------|--------|
| Dependency License Checker | default | sonnet5 | 9.9min | 39 | 1 | $1.99 | — | python | ok |
| PR Label Assigner | default | sonnet5 | 11.6min | 80 | 0 | $3.61 | — | python | ok |
| Semantic Version Bumper | bash | sonnet5 | 11.8min | 57 | 3 | $2.84 | — | bash | ok |
| Artifact Cleanup Script | bash | sonnet5 | 11.8min | 59 | 4 | $3.37 | — | bash | ok |
| Semantic Version Bumper | default | sonnet5 | 12.5min | 80 | 2 | $3.54 | — | python | ok |
| Test Results Aggregator | default | sonnet5 | 12.7min | 59 | 0 | $3.47 | — | python | ok |
| Dependency License Checker | powershell-tool | sonnet5 | 14.6min | 58 | 1 | $2.80 | — | powershell | ok |
| Environment Matrix Generator | default | sonnet5 | 16.4min | 94 | 2 | $5.01 | — | python | ok |
| Dependency License Checker | powershell | sonnet5 | 16.8min | 80 | 0 | $3.03 | — | powershell | ok |
| Test Results Aggregator | bash | sonnet5 | 17.1min | 108 | 6 | $5.57 | — | bash | ok |
| Dependency License Checker | bash | sonnet5 | 17.4min | 105 | 3 | $5.57 | — | bash | ok |
| Artifact Cleanup Script | default | sonnet5 | 18.0min | 76 | 1 | $3.61 | — | powershell | ok |
| PR Label Assigner | typescript-bun | sonnet5 | 18.3min | 106 | 0 | $4.13 | — | typescript | ok |
| Dependency License Checker | typescript-bun | sonnet5 | 18.4min | 137 | 11 | $5.28 | — | typescript | ok |
| Semantic Version Bumper | typescript-bun | sonnet5 | 18.6min | 127 | 8 | $6.16 | — | typescript | ok |
| Environment Matrix Generator | typescript-bun | sonnet5 | 19.7min | 75 | 1 | $4.76 | — | typescript | ok |
| Artifact Cleanup Script | powershell | sonnet5 | 23.4min | 98 | 3 | $5.42 | — | powershell | ok |
| Test Results Aggregator | typescript-bun | sonnet5 | 25.3min | 143 | 2 | $7.29 | — | typescript | ok |
| Environment Matrix Generator | powershell-tool | sonnet5 | 25.4min | 82 | 0 | $5.48 | — | powershell | ok |
| Test Results Aggregator | powershell-tool | sonnet5 | 26.0min | 87 | 4 | $4.82 | — | powershell | ok |
| Environment Matrix Generator | bash | sonnet5 | 26.2min | 150 | 9 | $8.03 | — | bash | ok |
| Semantic Version Bumper | powershell-tool | sonnet5 | 26.7min | 111 | 0 | $5.41 | — | powershell | ok |
| Environment Matrix Generator | powershell | sonnet5 | 29.5min | 103 | 0 | $6.22 | — | powershell | ok |
| Test Results Aggregator | powershell | sonnet5 | 30.0min | 0 | 0 | $0.00 | — | powershell | timeout |
| Semantic Version Bumper | powershell | sonnet5 | 30.0min | 0 | 1 | $0.00 | — | powershell | timeout |
| PR Label Assigner | powershell-tool | sonnet5 | 30.0min | 0 | 4 | $0.00 | — | powershell | timeout |
| PR Label Assigner | bash | sonnet5 | 30.0min | 0 | 2 | $0.00 | — | bash | timeout |
| PR Label Assigner | powershell | sonnet5 | 30.0min | 0 | 1 | $0.00 | — | powershell | timeout |

</details>

<details>
<summary>Sorted by errors (fewest first)</summary>

| Task | Language | Model | Duration | Turns | Errors | Cost | Tests Quality | Chosen | Status |
|------|----------|-------|----------|-------|--------|------|-----------|--------|--------|
| Semantic Version Bumper | powershell-tool | sonnet5 | 26.7min | 111 | 0 | $5.41 | — | powershell | ok |
| PR Label Assigner | default | sonnet5 | 11.6min | 80 | 0 | $3.61 | — | python | ok |
| PR Label Assigner | typescript-bun | sonnet5 | 18.3min | 106 | 0 | $4.13 | — | typescript | ok |
| Dependency License Checker | powershell | sonnet5 | 16.8min | 80 | 0 | $3.03 | — | powershell | ok |
| Test Results Aggregator | default | sonnet5 | 12.7min | 59 | 0 | $3.47 | — | python | ok |
| Test Results Aggregator | powershell | sonnet5 | 30.0min | 0 | 0 | $0.00 | — | powershell | timeout |
| Environment Matrix Generator | powershell | sonnet5 | 29.5min | 103 | 0 | $6.22 | — | powershell | ok |
| Environment Matrix Generator | powershell-tool | sonnet5 | 25.4min | 82 | 0 | $5.48 | — | powershell | ok |
| Semantic Version Bumper | powershell | sonnet5 | 30.0min | 0 | 1 | $0.00 | — | powershell | timeout |
| PR Label Assigner | powershell | sonnet5 | 30.0min | 0 | 1 | $0.00 | — | powershell | timeout |
| Dependency License Checker | default | sonnet5 | 9.9min | 39 | 1 | $1.99 | — | python | ok |
| Dependency License Checker | powershell-tool | sonnet5 | 14.6min | 58 | 1 | $2.80 | — | powershell | ok |
| Environment Matrix Generator | typescript-bun | sonnet5 | 19.7min | 75 | 1 | $4.76 | — | typescript | ok |
| Artifact Cleanup Script | default | sonnet5 | 18.0min | 76 | 1 | $3.61 | — | powershell | ok |
| Semantic Version Bumper | default | sonnet5 | 12.5min | 80 | 2 | $3.54 | — | python | ok |
| PR Label Assigner | bash | sonnet5 | 30.0min | 0 | 2 | $0.00 | — | bash | timeout |
| Test Results Aggregator | typescript-bun | sonnet5 | 25.3min | 143 | 2 | $7.29 | — | typescript | ok |
| Environment Matrix Generator | default | sonnet5 | 16.4min | 94 | 2 | $5.01 | — | python | ok |
| Semantic Version Bumper | bash | sonnet5 | 11.8min | 57 | 3 | $2.84 | — | bash | ok |
| Dependency License Checker | bash | sonnet5 | 17.4min | 105 | 3 | $5.57 | — | bash | ok |
| Artifact Cleanup Script | powershell | sonnet5 | 23.4min | 98 | 3 | $5.42 | — | powershell | ok |
| PR Label Assigner | powershell-tool | sonnet5 | 30.0min | 0 | 4 | $0.00 | — | powershell | timeout |
| Test Results Aggregator | powershell-tool | sonnet5 | 26.0min | 87 | 4 | $4.82 | — | powershell | ok |
| Artifact Cleanup Script | bash | sonnet5 | 11.8min | 59 | 4 | $3.37 | — | bash | ok |
| Test Results Aggregator | bash | sonnet5 | 17.1min | 108 | 6 | $5.57 | — | bash | ok |
| Semantic Version Bumper | typescript-bun | sonnet5 | 18.6min | 127 | 8 | $6.16 | — | typescript | ok |
| Environment Matrix Generator | bash | sonnet5 | 26.2min | 150 | 9 | $8.03 | — | bash | ok |
| Dependency License Checker | typescript-bun | sonnet5 | 18.4min | 137 | 11 | $5.28 | — | typescript | ok |

</details>

<details>
<summary>Sorted by turns (fewest first)</summary>

| Task | Language | Model | Duration | Turns | Errors | Cost | Tests Quality | Chosen | Status |
|------|----------|-------|----------|-------|--------|------|-----------|--------|--------|
| Semantic Version Bumper | powershell | sonnet5 | 30.0min | 0 | 1 | $0.00 | — | powershell | timeout |
| PR Label Assigner | powershell | sonnet5 | 30.0min | 0 | 1 | $0.00 | — | powershell | timeout |
| PR Label Assigner | bash | sonnet5 | 30.0min | 0 | 2 | $0.00 | — | bash | timeout |
| PR Label Assigner | powershell-tool | sonnet5 | 30.0min | 0 | 4 | $0.00 | — | powershell | timeout |
| Test Results Aggregator | powershell | sonnet5 | 30.0min | 0 | 0 | $0.00 | — | powershell | timeout |
| Dependency License Checker | default | sonnet5 | 9.9min | 39 | 1 | $1.99 | — | python | ok |
| Semantic Version Bumper | bash | sonnet5 | 11.8min | 57 | 3 | $2.84 | — | bash | ok |
| Dependency License Checker | powershell-tool | sonnet5 | 14.6min | 58 | 1 | $2.80 | — | powershell | ok |
| Test Results Aggregator | default | sonnet5 | 12.7min | 59 | 0 | $3.47 | — | python | ok |
| Artifact Cleanup Script | bash | sonnet5 | 11.8min | 59 | 4 | $3.37 | — | bash | ok |
| Environment Matrix Generator | typescript-bun | sonnet5 | 19.7min | 75 | 1 | $4.76 | — | typescript | ok |
| Artifact Cleanup Script | default | sonnet5 | 18.0min | 76 | 1 | $3.61 | — | powershell | ok |
| Semantic Version Bumper | default | sonnet5 | 12.5min | 80 | 2 | $3.54 | — | python | ok |
| PR Label Assigner | default | sonnet5 | 11.6min | 80 | 0 | $3.61 | — | python | ok |
| Dependency License Checker | powershell | sonnet5 | 16.8min | 80 | 0 | $3.03 | — | powershell | ok |
| Environment Matrix Generator | powershell-tool | sonnet5 | 25.4min | 82 | 0 | $5.48 | — | powershell | ok |
| Test Results Aggregator | powershell-tool | sonnet5 | 26.0min | 87 | 4 | $4.82 | — | powershell | ok |
| Environment Matrix Generator | default | sonnet5 | 16.4min | 94 | 2 | $5.01 | — | python | ok |
| Artifact Cleanup Script | powershell | sonnet5 | 23.4min | 98 | 3 | $5.42 | — | powershell | ok |
| Environment Matrix Generator | powershell | sonnet5 | 29.5min | 103 | 0 | $6.22 | — | powershell | ok |
| Dependency License Checker | bash | sonnet5 | 17.4min | 105 | 3 | $5.57 | — | bash | ok |
| PR Label Assigner | typescript-bun | sonnet5 | 18.3min | 106 | 0 | $4.13 | — | typescript | ok |
| Test Results Aggregator | bash | sonnet5 | 17.1min | 108 | 6 | $5.57 | — | bash | ok |
| Semantic Version Bumper | powershell-tool | sonnet5 | 26.7min | 111 | 0 | $5.41 | — | powershell | ok |
| Semantic Version Bumper | typescript-bun | sonnet5 | 18.6min | 127 | 8 | $6.16 | — | typescript | ok |
| Dependency License Checker | typescript-bun | sonnet5 | 18.4min | 137 | 11 | $5.28 | — | typescript | ok |
| Test Results Aggregator | typescript-bun | sonnet5 | 25.3min | 143 | 2 | $7.29 | — | typescript | ok |
| Environment Matrix Generator | bash | sonnet5 | 26.2min | 150 | 9 | $8.03 | — | bash | ok |

</details>

<details>
<summary>Sorted by LLM-as-judge score (best first)</summary>

| Task | Language | Model | Duration | Turns | Errors | Cost | Tests Quality | Chosen | Status |
|------|----------|-------|----------|-------|--------|------|-----------|--------|--------|
| Semantic Version Bumper | default | sonnet5 | 12.5min | 80 | 2 | $3.54 | — | python | ok |
| Semantic Version Bumper | powershell | sonnet5 | 30.0min | 0 | 1 | $0.00 | — | powershell | timeout |
| Semantic Version Bumper | bash | sonnet5 | 11.8min | 57 | 3 | $2.84 | — | bash | ok |
| Semantic Version Bumper | powershell-tool | sonnet5 | 26.7min | 111 | 0 | $5.41 | — | powershell | ok |
| Semantic Version Bumper | typescript-bun | sonnet5 | 18.6min | 127 | 8 | $6.16 | — | typescript | ok |
| PR Label Assigner | default | sonnet5 | 11.6min | 80 | 0 | $3.61 | — | python | ok |
| PR Label Assigner | powershell | sonnet5 | 30.0min | 0 | 1 | $0.00 | — | powershell | timeout |
| PR Label Assigner | bash | sonnet5 | 30.0min | 0 | 2 | $0.00 | — | bash | timeout |
| PR Label Assigner | powershell-tool | sonnet5 | 30.0min | 0 | 4 | $0.00 | — | powershell | timeout |
| PR Label Assigner | typescript-bun | sonnet5 | 18.3min | 106 | 0 | $4.13 | — | typescript | ok |
| Dependency License Checker | default | sonnet5 | 9.9min | 39 | 1 | $1.99 | — | python | ok |
| Dependency License Checker | powershell | sonnet5 | 16.8min | 80 | 0 | $3.03 | — | powershell | ok |
| Dependency License Checker | bash | sonnet5 | 17.4min | 105 | 3 | $5.57 | — | bash | ok |
| Dependency License Checker | powershell-tool | sonnet5 | 14.6min | 58 | 1 | $2.80 | — | powershell | ok |
| Dependency License Checker | typescript-bun | sonnet5 | 18.4min | 137 | 11 | $5.28 | — | typescript | ok |
| Test Results Aggregator | default | sonnet5 | 12.7min | 59 | 0 | $3.47 | — | python | ok |
| Test Results Aggregator | powershell | sonnet5 | 30.0min | 0 | 0 | $0.00 | — | powershell | timeout |
| Test Results Aggregator | bash | sonnet5 | 17.1min | 108 | 6 | $5.57 | — | bash | ok |
| Test Results Aggregator | powershell-tool | sonnet5 | 26.0min | 87 | 4 | $4.82 | — | powershell | ok |
| Test Results Aggregator | typescript-bun | sonnet5 | 25.3min | 143 | 2 | $7.29 | — | typescript | ok |
| Environment Matrix Generator | default | sonnet5 | 16.4min | 94 | 2 | $5.01 | — | python | ok |
| Environment Matrix Generator | powershell | sonnet5 | 29.5min | 103 | 0 | $6.22 | — | powershell | ok |
| Environment Matrix Generator | bash | sonnet5 | 26.2min | 150 | 9 | $8.03 | — | bash | ok |
| Environment Matrix Generator | powershell-tool | sonnet5 | 25.4min | 82 | 0 | $5.48 | — | powershell | ok |
| Environment Matrix Generator | typescript-bun | sonnet5 | 19.7min | 75 | 1 | $4.76 | — | typescript | ok |
| Artifact Cleanup Script | default | sonnet5 | 18.0min | 76 | 1 | $3.61 | — | powershell | ok |
| Artifact Cleanup Script | powershell | sonnet5 | 23.4min | 98 | 3 | $5.42 | — | powershell | ok |
| Artifact Cleanup Script | bash | sonnet5 | 11.8min | 59 | 4 | $3.37 | — | bash | ok |

</details>

## Notes

### Tiers

- **Duration bands:** **A+** ≤1.05×, **A** ≤1.09×, **A-** ≤1.15×, **B+** ≤1.20×, **B** ≤1.25×, **B-** ≤1.31×, **C+** ≤1.37×, **C** ≤1.44×, **C-** ≤1.50×, **D+** ≤1.57×, **D** ≤1.65×, **D-** ≤1.72×, **F** >1.72×
- **Cost bands:** **A+** ≤1.04×, **A** ≤1.08×, **A-** ≤1.12×, **B+** ≤1.16×, **B** ≤1.20×, **B-** ≤1.25×, **C+** ≤1.30×, **C** ≤1.35×, **C-** ≤1.40×, **D+** ≤1.45×, **D** ≤1.50×, **D-** ≤1.56×, **F** >1.56×

*Tests/Workflow Craft bands are absolute Overall score bands:* **A+** ≥4.7, **A** ≥4.4, **A-** ≥4.1, **B+** ≥3.8, **B** ≥3.5, **B-** ≥3.2, **C+** ≥2.9, **C** ≥2.6, **C-** ≥2.3, **D+** ≥2.0, **D** ≥1.7, **D-** ≥1.4, **F** <1.4, `—` = no data.*

### CLI Version Legend

| Variant label | CLI version | Tasks | Languages |
|---------------|-------------|-------|-----------|
| sonnet5 | 2.1.197 | All | All |

---
*Generated by generate_results.py — benchmark instructions v4*