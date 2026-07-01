# Benchmark Results: Language Comparison

**Last updated:** 2026-06-30 11:58:41 PM ET — 14/35 runs completed, 21 remaining; total cost $39.09; total agent time 278.1 min.
**Claude Code versions used:** v2.1.197 (14 runs). Each link goes to a per-version snapshot of the system prompt, default-tool descriptions, and the chronological Anthropic changelog up to that version. Regenerate with `python3 version_docs.py`.

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
| default | sonnet5 | A+ (11.3min) | A+ ($3.05) | — | — |
| powershell | sonnet5* | C (16.8min) | A+ ($3.03) | — | — |
| bash | sonnet5* | B- (14.6min) | C ($4.21) | — | — |
| powershell-tool | sonnet5* | D- (20.6min) | C+ ($4.11) | — | — |
| typescript-bun | sonnet5 | D+ (18.5min) | D- ($5.15) | — | — |


<details>
<summary>Sorted by Duration tier (best-first), then avg of Cost/Tests/Workflow Craft tiers</summary>

| Language | Model | Duration | Cost | Tests Quality | Workflow Craft |
|----------|-------|----------|------|-----------|-------------|
| default | sonnet5 | A+ (11.3min) | A+ ($3.05) | — | — |
| bash | sonnet5* | B- (14.6min) | C ($4.21) | — | — |
| powershell | sonnet5* | C (16.8min) | A+ ($3.03) | — | — |
| typescript-bun | sonnet5 | D+ (18.5min) | D- ($5.15) | — | — |
| powershell-tool | sonnet5* | D- (20.6min) | C+ ($4.11) | — | — |

</details>

<details>
<summary>Sorted by Cost tier (best-first), then avg of Duration/Tests/Workflow Craft tiers</summary>

| Language | Model | Duration | Cost | Tests Quality | Workflow Craft |
|----------|-------|----------|------|-----------|-------------|
| default | sonnet5 | A+ (11.3min) | A+ ($3.05) | — | — |
| powershell | sonnet5* | C (16.8min) | A+ ($3.03) | — | — |
| powershell-tool | sonnet5* | D- (20.6min) | C+ ($4.11) | — | — |
| bash | sonnet5* | B- (14.6min) | C ($4.21) | — | — |
| typescript-bun | sonnet5 | D+ (18.5min) | D- ($5.15) | — | — |

</details>

<details>
<summary>Sorted by Tests Quality tier (best-first; no-data last), then avg of other tiers</summary>

| Language | Model | Duration | Cost | Tests Quality | Workflow Craft |
|----------|-------|----------|------|-----------|-------------|
| default | sonnet5 | A+ (11.3min) | A+ ($3.05) | — | — |
| powershell | sonnet5* | C (16.8min) | A+ ($3.03) | — | — |
| bash | sonnet5* | B- (14.6min) | C ($4.21) | — | — |
| powershell-tool | sonnet5* | D- (20.6min) | C+ ($4.11) | — | — |
| typescript-bun | sonnet5 | D+ (18.5min) | D- ($5.15) | — | — |

</details>

<details>
<summary>Sorted by Workflow Craft tier (best-first; no-data last), then avg of other tiers</summary>

| Language | Model | Duration | Cost | Tests Quality | Workflow Craft |
|----------|-------|----------|------|-----------|-------------|
| default | sonnet5 | A+ (11.3min) | A+ ($3.05) | — | — |
| powershell | sonnet5* | C (16.8min) | A+ ($3.03) | — | — |
| bash | sonnet5* | B- (14.6min) | C ($4.21) | — | — |
| powershell-tool | sonnet5* | D- (20.6min) | C+ ($4.11) | — | — |
| typescript-bun | sonnet5 | D+ (18.5min) | D- ($5.15) | — | — |

</details>

- **Estimated time remaining:** 417.2min
- **Estimated total cost:** $97.71

## Failed / Timed-Out Runs

| Task | Language | Model | Duration | Reason | Lines | actionlint | act-result.txt |
|------|------|-------|----------|--------|-------|------------|----------------|
| Semantic Version Bumper | powershell | sonnet5 | 30.0min | timeout | 667 | pass | yes |
| PR Label Assigner | powershell | sonnet5 | 30.0min | timeout | 806 | pass | yes |
| PR Label Assigner | bash | sonnet5 | 30.0min | timeout | 1034 | pass | yes |
| PR Label Assigner | powershell-tool | sonnet5 | 30.0min | timeout | 621 | pass | no |

*4 run(s) excluded from averages below.*

## Comparison by Language/Model/Effort
*(averages exclude failed/timed-out runs)*
*See [Notes](#notes) for scoring rubric and CLI version legend.*

| Language | Model | Runs | Avg Duration | Avg Duration Net of Traps | Avg Errors | Avg Turns | Avg Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| bash | sonnet5* | 2 | 14.6min | 13.6min | 3.0 | 81 | $4.21 | $8.41 | — | — |
| default | sonnet5 | 3 | 11.3min | 9.6min | 1.0 | 66 | $3.05 | $9.14 | — | — |
| powershell | sonnet5* | 1 | 16.8min | 2.7min | 0.0 | 80 | $3.03 | $3.03 | — | — |
| powershell-tool | sonnet5* | 2 | 20.6min | 14.3min | 0.5 | 84 | $4.11 | $8.21 | — | — |
| typescript-bun | sonnet5 | 2 | 18.5min | 11.4min | 4.0 | 116 | $5.15 | $10.29 | — | — |


<details>
<summary>Sorted by avg cost (cheapest first)</summary>

| Language | Model | Runs | Avg Duration | Avg Duration Net of Traps | Avg Errors | Avg Turns | Avg Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| powershell | sonnet5* | 1 | 16.8min | 2.7min | 0.0 | 80 | $3.03 | $3.03 | — | — |
| default | sonnet5 | 3 | 11.3min | 9.6min | 1.0 | 66 | $3.05 | $9.14 | — | — |
| powershell-tool | sonnet5* | 2 | 20.6min | 14.3min | 0.5 | 84 | $4.11 | $8.21 | — | — |
| bash | sonnet5* | 2 | 14.6min | 13.6min | 3.0 | 81 | $4.21 | $8.41 | — | — |
| typescript-bun | sonnet5 | 2 | 18.5min | 11.4min | 4.0 | 116 | $5.15 | $10.29 | — | — |

</details>

<details>
<summary>Sorted by avg duration (fastest first)</summary>

| Language | Model | Runs | Avg Duration | Avg Duration Net of Traps | Avg Errors | Avg Turns | Avg Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| default | sonnet5 | 3 | 11.3min | 9.6min | 1.0 | 66 | $3.05 | $9.14 | — | — |
| bash | sonnet5* | 2 | 14.6min | 13.6min | 3.0 | 81 | $4.21 | $8.41 | — | — |
| powershell | sonnet5* | 1 | 16.8min | 2.7min | 0.0 | 80 | $3.03 | $3.03 | — | — |
| typescript-bun | sonnet5 | 2 | 18.5min | 11.4min | 4.0 | 116 | $5.15 | $10.29 | — | — |
| powershell-tool | sonnet5* | 2 | 20.6min | 14.3min | 0.5 | 84 | $4.11 | $8.21 | — | — |

</details>

<details>
<summary>Sorted by avg duration net of traps (fastest first)</summary>

| Language | Model | Runs | Avg Duration | Avg Duration Net of Traps | Avg Errors | Avg Turns | Avg Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| powershell | sonnet5* | 1 | 16.8min | 2.7min | 0.0 | 80 | $3.03 | $3.03 | — | — |
| default | sonnet5 | 3 | 11.3min | 9.6min | 1.0 | 66 | $3.05 | $9.14 | — | — |
| typescript-bun | sonnet5 | 2 | 18.5min | 11.4min | 4.0 | 116 | $5.15 | $10.29 | — | — |
| bash | sonnet5* | 2 | 14.6min | 13.6min | 3.0 | 81 | $4.21 | $8.41 | — | — |
| powershell-tool | sonnet5* | 2 | 20.6min | 14.3min | 0.5 | 84 | $4.11 | $8.21 | — | — |

</details>

<details>
<summary>Sorted by avg errors (fewest first)</summary>

| Language | Model | Runs | Avg Duration | Avg Duration Net of Traps | Avg Errors | Avg Turns | Avg Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| powershell | sonnet5* | 1 | 16.8min | 2.7min | 0.0 | 80 | $3.03 | $3.03 | — | — |
| powershell-tool | sonnet5* | 2 | 20.6min | 14.3min | 0.5 | 84 | $4.11 | $8.21 | — | — |
| default | sonnet5 | 3 | 11.3min | 9.6min | 1.0 | 66 | $3.05 | $9.14 | — | — |
| bash | sonnet5* | 2 | 14.6min | 13.6min | 3.0 | 81 | $4.21 | $8.41 | — | — |
| typescript-bun | sonnet5 | 2 | 18.5min | 11.4min | 4.0 | 116 | $5.15 | $10.29 | — | — |

</details>

<details>
<summary>Sorted by avg turns (fewest first)</summary>

| Language | Model | Runs | Avg Duration | Avg Duration Net of Traps | Avg Errors | Avg Turns | Avg Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| default | sonnet5 | 3 | 11.3min | 9.6min | 1.0 | 66 | $3.05 | $9.14 | — | — |
| powershell | sonnet5* | 1 | 16.8min | 2.7min | 0.0 | 80 | $3.03 | $3.03 | — | — |
| bash | sonnet5* | 2 | 14.6min | 13.6min | 3.0 | 81 | $4.21 | $8.41 | — | — |
| powershell-tool | sonnet5* | 2 | 20.6min | 14.3min | 0.5 | 84 | $4.11 | $8.21 | — | — |
| typescript-bun | sonnet5 | 2 | 18.5min | 11.4min | 4.0 | 116 | $5.15 | $10.29 | — | — |

</details>

<details>
<summary>Sorted by LLM-as-judge score (best first)</summary>

| Language | Model | Runs | Avg Duration | Avg Duration Net of Traps | Avg Errors | Avg Turns | Avg Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| bash | sonnet5* | 2 | 14.6min | 13.6min | 3.0 | 81 | $4.21 | $8.41 | — | — |
| default | sonnet5 | 3 | 11.3min | 9.6min | 1.0 | 66 | $3.05 | $9.14 | — | — |
| powershell | sonnet5* | 1 | 16.8min | 2.7min | 0.0 | 80 | $3.03 | $3.03 | — | — |
| powershell-tool | sonnet5* | 2 | 20.6min | 14.3min | 0.5 | 84 | $4.11 | $8.21 | — | — |
| typescript-bun | sonnet5 | 2 | 18.5min | 11.4min | 4.0 | 116 | $5.15 | $10.29 | — | — |

</details>

<details>
<summary>Sorted by deliverable-quality score (best first)</summary>

| Language | Model | Runs | Avg Duration | Avg Duration Net of Traps | Avg Errors | Avg Turns | Avg Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| bash | sonnet5* | 2 | 14.6min | 13.6min | 3.0 | 81 | $4.21 | $8.41 | — | — |
| default | sonnet5 | 3 | 11.3min | 9.6min | 1.0 | 66 | $3.05 | $9.14 | — | — |
| powershell | sonnet5* | 1 | 16.8min | 2.7min | 0.0 | 80 | $3.03 | $3.03 | — | — |
| powershell-tool | sonnet5* | 2 | 20.6min | 14.3min | 0.5 | 84 | $4.11 | $8.21 | — | — |
| typescript-bun | sonnet5 | 2 | 18.5min | 11.4min | 4.0 | 116 | $5.15 | $10.29 | — | — |

</details>

## Savings Analysis

### Hook Savings by Language/Model/Effort

Each hook-caught error avoids one test run that would otherwise have been needed to discover it.
Every hook fire (hit or miss) costs execution time for the syntax/type checker.

*`% of Test Time Saved` = `net / (net + test_time) × 100` — the share of total (would-have-been + actually-spent) test time that hooks eliminated. Bounded in (-∞, 100%) without an artificial cap; near 100% means hooks substituted for almost all of the hypothetical test work.*

| Language | Model | Fires | Caught | Rate | Gross Saved | % of Time | Overhead | % of Time | Net Saved | % of Time | Test Run Time | % of Test Time Saved |
|------|-------|-------|--------|------|------------|-----------|----------|-----------|-----------|-----------|---------------|----------------------|
| bash | sonnet5-cli2.1.197 | 62 | 7 | 11.3% | 1.4min | 0.5% | 0.3min | 0.1% | 1.1min | 0.4% | 18.6min | 5.5% |
| default | sonnet5-cli2.1.197 | 68 | 0 | 0.0% | 0.0min | 0.0% | 0.2min | 0.1% | -0.2min | -0.1% | 4.9min | -4.0% |
| powershell | sonnet5-cli2.1.197 | 83 | 2 | 2.4% | 1.2min | 0.4% | 12.6min | 4.5% | -11.4min | -4.1% | 13.1min | -667.1% |
| powershell-tool | sonnet5-cli2.1.197 | 83 | 18 | 21.7% | 10.5min | 3.8% | 13.4min | 4.8% | -2.9min | -1.1% | 14.6min | -25.1% |
| typescript-bun | sonnet5-cli2.1.197 | 75 | 34 | 45.3% | 4.5min | 1.6% | 5.2min | 1.9% | -0.7min | -0.3% | 3.2min | -28.0% |


<details>
<summary>Sorted by net saved (most first)</summary>

| Language | Model | Fires | Caught | Rate | Gross Saved | % of Time | Overhead | % of Time | Net Saved | % of Time | Test Run Time | % of Test Time Saved |
|------|-------|-------|--------|------|------------|-----------|----------|-----------|-----------|-----------|---------------|----------------------|
| bash | sonnet5-cli2.1.197 | 62 | 7 | 11.3% | 1.4min | 0.5% | 0.3min | 0.1% | 1.1min | 0.4% | 18.6min | 5.5% |
| default | sonnet5-cli2.1.197 | 68 | 0 | 0.0% | 0.0min | 0.0% | 0.2min | 0.1% | -0.2min | -0.1% | 4.9min | -4.0% |
| typescript-bun | sonnet5-cli2.1.197 | 75 | 34 | 45.3% | 4.5min | 1.6% | 5.2min | 1.9% | -0.7min | -0.3% | 3.2min | -28.0% |
| powershell-tool | sonnet5-cli2.1.197 | 83 | 18 | 21.7% | 10.5min | 3.8% | 13.4min | 4.8% | -2.9min | -1.1% | 14.6min | -25.1% |
| powershell | sonnet5-cli2.1.197 | 83 | 2 | 2.4% | 1.2min | 0.4% | 12.6min | 4.5% | -11.4min | -4.1% | 13.1min | -667.1% |

</details>

<details>
<summary>Sorted by net % of test time saved (most first)</summary>

| Language | Model | Fires | Caught | Rate | Gross Saved | % of Time | Overhead | % of Time | Net Saved | % of Time | Test Run Time | % of Test Time Saved |
|------|-------|-------|--------|------|------------|-----------|----------|-----------|-----------|-----------|---------------|----------------------|
| bash | sonnet5-cli2.1.197 | 62 | 7 | 11.3% | 1.4min | 0.5% | 0.3min | 0.1% | 1.1min | 0.4% | 18.6min | 5.5% |
| default | sonnet5-cli2.1.197 | 68 | 0 | 0.0% | 0.0min | 0.0% | 0.2min | 0.1% | -0.2min | -0.1% | 4.9min | -4.0% |
| powershell-tool | sonnet5-cli2.1.197 | 83 | 18 | 21.7% | 10.5min | 3.8% | 13.4min | 4.8% | -2.9min | -1.1% | 14.6min | -25.1% |
| typescript-bun | sonnet5-cli2.1.197 | 75 | 34 | 45.3% | 4.5min | 1.6% | 5.2min | 1.9% | -0.7min | -0.3% | 3.2min | -28.0% |
| powershell | sonnet5-cli2.1.197 | 83 | 2 | 2.4% | 1.2min | 0.4% | 12.6min | 4.5% | -11.4min | -4.1% | 13.1min | -667.1% |

</details>

<details>
<summary>Sorted by catch rate (highest first)</summary>

| Language | Model | Fires | Caught | Rate | Gross Saved | % of Time | Overhead | % of Time | Net Saved | % of Time | Test Run Time | % of Test Time Saved |
|------|-------|-------|--------|------|------------|-----------|----------|-----------|-----------|-----------|---------------|----------------------|
| typescript-bun | sonnet5-cli2.1.197 | 75 | 34 | 45.3% | 4.5min | 1.6% | 5.2min | 1.9% | -0.7min | -0.3% | 3.2min | -28.0% |
| powershell-tool | sonnet5-cli2.1.197 | 83 | 18 | 21.7% | 10.5min | 3.8% | 13.4min | 4.8% | -2.9min | -1.1% | 14.6min | -25.1% |
| bash | sonnet5-cli2.1.197 | 62 | 7 | 11.3% | 1.4min | 0.5% | 0.3min | 0.1% | 1.1min | 0.4% | 18.6min | 5.5% |
| powershell | sonnet5-cli2.1.197 | 83 | 2 | 2.4% | 1.2min | 0.4% | 12.6min | 4.5% | -11.4min | -4.1% | 13.1min | -667.1% |
| default | sonnet5-cli2.1.197 | 68 | 0 | 0.0% | 0.0min | 0.0% | 0.2min | 0.1% | -0.2min | -0.1% | 4.9min | -4.0% |

</details>

### Trap Analysis by Language/Model/Effort/Category

| Trap | Language | Model | Fell In | Time Lost | % of Time | $ Lost | % of $ |
|------|------|-------|---------|-----------|-----------|--------|--------|
| repeated-test-reruns | bash | sonnet5-cli2.1.197 | 1 | 0.7min | 0.2% | $0.21 | 0.55% |
| repeated-test-reruns | default | sonnet5-cli2.1.197 | 2 | 4.0min | 1.4% | $1.19 | 3.05% |
| repeated-test-reruns | powershell | sonnet5-cli2.1.197 | 5 | 11.3min | 4.1% | $0.48 | 1.23% |
| repeated-test-reruns | powershell-tool | sonnet5-cli2.1.197 | 5 | 10.7min | 3.8% | $1.39 | 3.56% |
| repeated-test-reruns | typescript-bun | sonnet5-cli2.1.197 | 1 | 4.0min | 1.4% | $0.91 | 2.32% |
| ts-type-error-fix-cycles | typescript-bun | sonnet5-cli2.1.197 | 2 | 6.8min | 2.4% | $2.00 | 5.11% |
| fixture-rework | bash | sonnet5-cli2.1.197 | 2 | 1.2min | 0.4% | $0.18 | 0.46% |
| fixture-rework | default | sonnet5-cli2.1.197 | 2 | 1.0min | 0.4% | $0.26 | 0.66% |
| fixture-rework | powershell | sonnet5-cli2.1.197 | 1 | 0.5min | 0.2% | $0.00 | 0.00% |
| fixture-rework | typescript-bun | sonnet5-cli2.1.197 | 2 | 2.2min | 0.8% | $0.67 | 1.70% |
| docker-pwsh-install | powershell | sonnet5-cli2.1.197 | 1 | 2.2min | 0.8% | $0.41 | 1.04% |
| act-push-debug-loops | powershell-tool | sonnet5-cli2.1.197 | 1 | 2.0min | 0.7% | $0.40 | 1.02% |
| actionlint-fix-cycles | typescript-bun | sonnet5-cli2.1.197 | 1 | 1.0min | 0.4% | $0.23 | 0.58% |


<details>
<summary>Sorted by time lost (least first)</summary>

| Trap | Language | Model | Fell In | Time Lost | % of Time | $ Lost | % of $ |
|------|------|-------|---------|-----------|-----------|--------|--------|
| fixture-rework | powershell | sonnet5-cli2.1.197 | 1 | 0.5min | 0.2% | $0.00 | 0.00% |
| repeated-test-reruns | bash | sonnet5-cli2.1.197 | 1 | 0.7min | 0.2% | $0.21 | 0.55% |
| fixture-rework | default | sonnet5-cli2.1.197 | 2 | 1.0min | 0.4% | $0.26 | 0.66% |
| actionlint-fix-cycles | typescript-bun | sonnet5-cli2.1.197 | 1 | 1.0min | 0.4% | $0.23 | 0.58% |
| fixture-rework | bash | sonnet5-cli2.1.197 | 2 | 1.2min | 0.4% | $0.18 | 0.46% |
| act-push-debug-loops | powershell-tool | sonnet5-cli2.1.197 | 1 | 2.0min | 0.7% | $0.40 | 1.02% |
| fixture-rework | typescript-bun | sonnet5-cli2.1.197 | 2 | 2.2min | 0.8% | $0.67 | 1.70% |
| docker-pwsh-install | powershell | sonnet5-cli2.1.197 | 1 | 2.2min | 0.8% | $0.41 | 1.04% |
| repeated-test-reruns | default | sonnet5-cli2.1.197 | 2 | 4.0min | 1.4% | $1.19 | 3.05% |
| repeated-test-reruns | typescript-bun | sonnet5-cli2.1.197 | 1 | 4.0min | 1.4% | $0.91 | 2.32% |
| ts-type-error-fix-cycles | typescript-bun | sonnet5-cli2.1.197 | 2 | 6.8min | 2.4% | $2.00 | 5.11% |
| repeated-test-reruns | powershell-tool | sonnet5-cli2.1.197 | 5 | 10.7min | 3.8% | $1.39 | 3.56% |
| repeated-test-reruns | powershell | sonnet5-cli2.1.197 | 5 | 11.3min | 4.1% | $0.48 | 1.23% |

</details>

<details>
<summary>Sorted by $ lost (least first)</summary>

| Trap | Language | Model | Fell In | Time Lost | % of Time | $ Lost | % of $ |
|------|------|-------|---------|-----------|-----------|--------|--------|
| fixture-rework | powershell | sonnet5-cli2.1.197 | 1 | 0.5min | 0.2% | $0.00 | 0.00% |
| fixture-rework | bash | sonnet5-cli2.1.197 | 2 | 1.2min | 0.4% | $0.18 | 0.46% |
| repeated-test-reruns | bash | sonnet5-cli2.1.197 | 1 | 0.7min | 0.2% | $0.21 | 0.55% |
| actionlint-fix-cycles | typescript-bun | sonnet5-cli2.1.197 | 1 | 1.0min | 0.4% | $0.23 | 0.58% |
| fixture-rework | default | sonnet5-cli2.1.197 | 2 | 1.0min | 0.4% | $0.26 | 0.66% |
| act-push-debug-loops | powershell-tool | sonnet5-cli2.1.197 | 1 | 2.0min | 0.7% | $0.40 | 1.02% |
| docker-pwsh-install | powershell | sonnet5-cli2.1.197 | 1 | 2.2min | 0.8% | $0.41 | 1.04% |
| repeated-test-reruns | powershell | sonnet5-cli2.1.197 | 5 | 11.3min | 4.1% | $0.48 | 1.23% |
| fixture-rework | typescript-bun | sonnet5-cli2.1.197 | 2 | 2.2min | 0.8% | $0.67 | 1.70% |
| repeated-test-reruns | typescript-bun | sonnet5-cli2.1.197 | 1 | 4.0min | 1.4% | $0.91 | 2.32% |
| repeated-test-reruns | default | sonnet5-cli2.1.197 | 2 | 4.0min | 1.4% | $1.19 | 3.05% |
| repeated-test-reruns | powershell-tool | sonnet5-cli2.1.197 | 5 | 10.7min | 3.8% | $1.39 | 3.56% |
| ts-type-error-fix-cycles | typescript-bun | sonnet5-cli2.1.197 | 2 | 6.8min | 2.4% | $2.00 | 5.11% |

</details>

<details>
<summary>Sorted by fell-in count (fewest first)</summary>

| Trap | Language | Model | Fell In | Time Lost | % of Time | $ Lost | % of $ |
|------|------|-------|---------|-----------|-----------|--------|--------|
| repeated-test-reruns | bash | sonnet5-cli2.1.197 | 1 | 0.7min | 0.2% | $0.21 | 0.55% |
| repeated-test-reruns | typescript-bun | sonnet5-cli2.1.197 | 1 | 4.0min | 1.4% | $0.91 | 2.32% |
| fixture-rework | powershell | sonnet5-cli2.1.197 | 1 | 0.5min | 0.2% | $0.00 | 0.00% |
| docker-pwsh-install | powershell | sonnet5-cli2.1.197 | 1 | 2.2min | 0.8% | $0.41 | 1.04% |
| act-push-debug-loops | powershell-tool | sonnet5-cli2.1.197 | 1 | 2.0min | 0.7% | $0.40 | 1.02% |
| actionlint-fix-cycles | typescript-bun | sonnet5-cli2.1.197 | 1 | 1.0min | 0.4% | $0.23 | 0.58% |
| repeated-test-reruns | default | sonnet5-cli2.1.197 | 2 | 4.0min | 1.4% | $1.19 | 3.05% |
| ts-type-error-fix-cycles | typescript-bun | sonnet5-cli2.1.197 | 2 | 6.8min | 2.4% | $2.00 | 5.11% |
| fixture-rework | bash | sonnet5-cli2.1.197 | 2 | 1.2min | 0.4% | $0.18 | 0.46% |
| fixture-rework | default | sonnet5-cli2.1.197 | 2 | 1.0min | 0.4% | $0.26 | 0.66% |
| fixture-rework | typescript-bun | sonnet5-cli2.1.197 | 2 | 2.2min | 0.8% | $0.67 | 1.70% |
| repeated-test-reruns | powershell | sonnet5-cli2.1.197 | 5 | 11.3min | 4.1% | $0.48 | 1.23% |
| repeated-test-reruns | powershell-tool | sonnet5-cli2.1.197 | 5 | 10.7min | 3.8% | $1.39 | 3.56% |

</details>

#### Trap Descriptions

- **act-push-debug-loops**: Agent ran `act push` more than twice, indicating repeated workflow debugging.
- **actionlint-fix-cycles**: Workflow YAML required 3+ actionlint runs and 2+ fixes to pass.
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
| bash | sonnet5-cli2.1.197 | 3 | 3 | 1.9min | 0.7% | $0.39 | 1.01% |
| default | sonnet5-cli2.1.197 | 3 | 4 | 5.0min | 1.8% | $1.45 | 3.71% |
| powershell | sonnet5-cli2.1.197 | 3 | 7 | 14.1min | 5.1% | $0.89 | 2.27% |
| powershell-tool | sonnet5-cli2.1.197 | 3 | 6 | 12.6min | 4.5% | $1.79 | 4.58% |
| typescript-bun | sonnet5-cli2.1.197 | 2 | 6 | 14.1min | 5.1% | $3.79 | 9.71% |


<details>
<summary>Sorted by time lost (least first)</summary>

| Language | Model | Runs | Traps | Time Lost | % of Time | $ Lost | % of $ |
|------|-------|------|-------|-----------|-----------|--------|--------|
| bash | sonnet5-cli2.1.197 | 3 | 3 | 1.9min | 0.7% | $0.39 | 1.01% |
| default | sonnet5-cli2.1.197 | 3 | 4 | 5.0min | 1.8% | $1.45 | 3.71% |
| powershell-tool | sonnet5-cli2.1.197 | 3 | 6 | 12.6min | 4.5% | $1.79 | 4.58% |
| typescript-bun | sonnet5-cli2.1.197 | 2 | 6 | 14.1min | 5.1% | $3.79 | 9.71% |
| powershell | sonnet5-cli2.1.197 | 3 | 7 | 14.1min | 5.1% | $0.89 | 2.27% |

</details>

<details>
<summary>Sorted by $ lost (least first)</summary>

| Language | Model | Runs | Traps | Time Lost | % of Time | $ Lost | % of $ |
|------|-------|------|-------|-----------|-----------|--------|--------|
| bash | sonnet5-cli2.1.197 | 3 | 3 | 1.9min | 0.7% | $0.39 | 1.01% |
| powershell | sonnet5-cli2.1.197 | 3 | 7 | 14.1min | 5.1% | $0.89 | 2.27% |
| default | sonnet5-cli2.1.197 | 3 | 4 | 5.0min | 1.8% | $1.45 | 3.71% |
| powershell-tool | sonnet5-cli2.1.197 | 3 | 6 | 12.6min | 4.5% | $1.79 | 4.58% |
| typescript-bun | sonnet5-cli2.1.197 | 2 | 6 | 14.1min | 5.1% | $3.79 | 9.71% |

</details>

### Prompt Cache Savings

| Status | Runs | $ Saved | % of $ |
|--------|------|---------|--------|
| Full hit (100%) | 0 | $0.00 | 0.00% |
| Partial | 14 | $1.27 | 3.24% |
| Miss | 0 | $0.00 | 0.00% |

## Test Quality Evaluation

### Structural Metrics by Language/Model/Effort

Automated analysis of test files: test count, assertion count, and test-to-code line ratio.

| Language | Model | Avg Tests | Avg Assertions | Avg Assert/Test | Avg Test:Code Ratio |
|------|-------|-----------|----------------|-----------------|---------------------|
| bash | sonnet5 | 32.7 | 71.7 | 2.2 | 0.93 |
| default | sonnet5 | 25.3 | 49.0 | 1.9 | 1.04 |
| powershell | sonnet5 | 46.0 | 72.0 | 1.6 | 3.41 |
| powershell-tool | sonnet5 | 47.0 | 79.3 | 1.7 | 6.52 |
| typescript-bun | sonnet5 | 43.0 | 64.0 | 1.5 | 1.31 |


<details>
<summary>Sorted by avg tests (most first)</summary>

| Language | Model | Avg Tests | Avg Assertions | Avg Assert/Test | Avg Test:Code Ratio |
|------|-------|-----------|----------------|-----------------|---------------------|
| powershell-tool | sonnet5 | 47.0 | 79.3 | 1.7 | 6.52 |
| powershell | sonnet5 | 46.0 | 72.0 | 1.6 | 3.41 |
| typescript-bun | sonnet5 | 43.0 | 64.0 | 1.5 | 1.31 |
| bash | sonnet5 | 32.7 | 71.7 | 2.2 | 0.93 |
| default | sonnet5 | 25.3 | 49.0 | 1.9 | 1.04 |

</details>

<details>
<summary>Sorted by avg assertions (most first)</summary>

| Language | Model | Avg Tests | Avg Assertions | Avg Assert/Test | Avg Test:Code Ratio |
|------|-------|-----------|----------------|-----------------|---------------------|
| powershell-tool | sonnet5 | 47.0 | 79.3 | 1.7 | 6.52 |
| powershell | sonnet5 | 46.0 | 72.0 | 1.6 | 3.41 |
| bash | sonnet5 | 32.7 | 71.7 | 2.2 | 0.93 |
| typescript-bun | sonnet5 | 43.0 | 64.0 | 1.5 | 1.31 |
| default | sonnet5 | 25.3 | 49.0 | 1.9 | 1.04 |

</details>

<details>
<summary>Sorted by avg test:code ratio (highest first)</summary>

| Language | Model | Avg Tests | Avg Assertions | Avg Assert/Test | Avg Test:Code Ratio |
|------|-------|-----------|----------------|-----------------|---------------------|
| powershell-tool | sonnet5 | 47.0 | 79.3 | 1.7 | 6.52 |
| powershell | sonnet5 | 46.0 | 72.0 | 1.6 | 3.41 |
| typescript-bun | sonnet5 | 43.0 | 64.0 | 1.5 | 1.31 |
| default | sonnet5 | 25.3 | 49.0 | 1.9 | 1.04 |
| bash | sonnet5 | 32.7 | 71.7 | 2.2 | 0.93 |

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

</details>

## Per-Run Results

*Tests Quality = Overall (1-5) from LLM-as-judge of generated test code (dimensions: coverage, rigor, design). `—` = no judge data.*

| Task | Language | Model | Duration | Turns | Errors | Cost | Tests Quality | Chosen | Status |
|------|----------|-------|----------|-------|--------|------|-----------|--------|--------|
| Dependency License Checker | bash | sonnet5 | 17.4min | 105 | 3 | $5.57 | — | bash | ok |
| Dependency License Checker | default | sonnet5 | 9.9min | 39 | 1 | $1.99 | — | python | ok |
| Dependency License Checker | powershell | sonnet5 | 16.8min | 80 | 0 | $3.03 | — | powershell | ok |
| Dependency License Checker | powershell-tool | sonnet5 | 14.6min | 58 | 1 | $2.80 | — | powershell | ok |
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


<details>
<summary>Sorted by cost (cheapest first)</summary>

| Task | Language | Model | Duration | Turns | Errors | Cost | Tests Quality | Chosen | Status |
|------|----------|-------|----------|-------|--------|------|-----------|--------|--------|
| Semantic Version Bumper | powershell | sonnet5 | 30.0min | 0 | 1 | $0.00 | — | powershell | timeout |
| PR Label Assigner | powershell | sonnet5 | 30.0min | 0 | 1 | $0.00 | — | powershell | timeout |
| PR Label Assigner | bash | sonnet5 | 30.0min | 0 | 2 | $0.00 | — | bash | timeout |
| PR Label Assigner | powershell-tool | sonnet5 | 30.0min | 0 | 4 | $0.00 | — | powershell | timeout |
| Dependency License Checker | default | sonnet5 | 9.9min | 39 | 1 | $1.99 | — | python | ok |
| Dependency License Checker | powershell-tool | sonnet5 | 14.6min | 58 | 1 | $2.80 | — | powershell | ok |
| Semantic Version Bumper | bash | sonnet5 | 11.8min | 57 | 3 | $2.84 | — | bash | ok |
| Dependency License Checker | powershell | sonnet5 | 16.8min | 80 | 0 | $3.03 | — | powershell | ok |
| Semantic Version Bumper | default | sonnet5 | 12.5min | 80 | 2 | $3.54 | — | python | ok |
| PR Label Assigner | default | sonnet5 | 11.6min | 80 | 0 | $3.61 | — | python | ok |
| PR Label Assigner | typescript-bun | sonnet5 | 18.3min | 106 | 0 | $4.13 | — | typescript | ok |
| Semantic Version Bumper | powershell-tool | sonnet5 | 26.7min | 111 | 0 | $5.41 | — | powershell | ok |
| Dependency License Checker | bash | sonnet5 | 17.4min | 105 | 3 | $5.57 | — | bash | ok |
| Semantic Version Bumper | typescript-bun | sonnet5 | 18.6min | 127 | 8 | $6.16 | — | typescript | ok |

</details>

<details>
<summary>Sorted by duration (fastest first)</summary>

| Task | Language | Model | Duration | Turns | Errors | Cost | Tests Quality | Chosen | Status |
|------|----------|-------|----------|-------|--------|------|-----------|--------|--------|
| Dependency License Checker | default | sonnet5 | 9.9min | 39 | 1 | $1.99 | — | python | ok |
| PR Label Assigner | default | sonnet5 | 11.6min | 80 | 0 | $3.61 | — | python | ok |
| Semantic Version Bumper | bash | sonnet5 | 11.8min | 57 | 3 | $2.84 | — | bash | ok |
| Semantic Version Bumper | default | sonnet5 | 12.5min | 80 | 2 | $3.54 | — | python | ok |
| Dependency License Checker | powershell-tool | sonnet5 | 14.6min | 58 | 1 | $2.80 | — | powershell | ok |
| Dependency License Checker | powershell | sonnet5 | 16.8min | 80 | 0 | $3.03 | — | powershell | ok |
| Dependency License Checker | bash | sonnet5 | 17.4min | 105 | 3 | $5.57 | — | bash | ok |
| PR Label Assigner | typescript-bun | sonnet5 | 18.3min | 106 | 0 | $4.13 | — | typescript | ok |
| Semantic Version Bumper | typescript-bun | sonnet5 | 18.6min | 127 | 8 | $6.16 | — | typescript | ok |
| Semantic Version Bumper | powershell-tool | sonnet5 | 26.7min | 111 | 0 | $5.41 | — | powershell | ok |
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
| Semantic Version Bumper | powershell | sonnet5 | 30.0min | 0 | 1 | $0.00 | — | powershell | timeout |
| PR Label Assigner | powershell | sonnet5 | 30.0min | 0 | 1 | $0.00 | — | powershell | timeout |
| Dependency License Checker | default | sonnet5 | 9.9min | 39 | 1 | $1.99 | — | python | ok |
| Dependency License Checker | powershell-tool | sonnet5 | 14.6min | 58 | 1 | $2.80 | — | powershell | ok |
| Semantic Version Bumper | default | sonnet5 | 12.5min | 80 | 2 | $3.54 | — | python | ok |
| PR Label Assigner | bash | sonnet5 | 30.0min | 0 | 2 | $0.00 | — | bash | timeout |
| Semantic Version Bumper | bash | sonnet5 | 11.8min | 57 | 3 | $2.84 | — | bash | ok |
| Dependency License Checker | bash | sonnet5 | 17.4min | 105 | 3 | $5.57 | — | bash | ok |
| PR Label Assigner | powershell-tool | sonnet5 | 30.0min | 0 | 4 | $0.00 | — | powershell | timeout |
| Semantic Version Bumper | typescript-bun | sonnet5 | 18.6min | 127 | 8 | $6.16 | — | typescript | ok |

</details>

<details>
<summary>Sorted by turns (fewest first)</summary>

| Task | Language | Model | Duration | Turns | Errors | Cost | Tests Quality | Chosen | Status |
|------|----------|-------|----------|-------|--------|------|-----------|--------|--------|
| Semantic Version Bumper | powershell | sonnet5 | 30.0min | 0 | 1 | $0.00 | — | powershell | timeout |
| PR Label Assigner | powershell | sonnet5 | 30.0min | 0 | 1 | $0.00 | — | powershell | timeout |
| PR Label Assigner | bash | sonnet5 | 30.0min | 0 | 2 | $0.00 | — | bash | timeout |
| PR Label Assigner | powershell-tool | sonnet5 | 30.0min | 0 | 4 | $0.00 | — | powershell | timeout |
| Dependency License Checker | default | sonnet5 | 9.9min | 39 | 1 | $1.99 | — | python | ok |
| Semantic Version Bumper | bash | sonnet5 | 11.8min | 57 | 3 | $2.84 | — | bash | ok |
| Dependency License Checker | powershell-tool | sonnet5 | 14.6min | 58 | 1 | $2.80 | — | powershell | ok |
| Semantic Version Bumper | default | sonnet5 | 12.5min | 80 | 2 | $3.54 | — | python | ok |
| PR Label Assigner | default | sonnet5 | 11.6min | 80 | 0 | $3.61 | — | python | ok |
| Dependency License Checker | powershell | sonnet5 | 16.8min | 80 | 0 | $3.03 | — | powershell | ok |
| Dependency License Checker | bash | sonnet5 | 17.4min | 105 | 3 | $5.57 | — | bash | ok |
| PR Label Assigner | typescript-bun | sonnet5 | 18.3min | 106 | 0 | $4.13 | — | typescript | ok |
| Semantic Version Bumper | powershell-tool | sonnet5 | 26.7min | 111 | 0 | $5.41 | — | powershell | ok |
| Semantic Version Bumper | typescript-bun | sonnet5 | 18.6min | 127 | 8 | $6.16 | — | typescript | ok |

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

</details>

## Notes

### Tiers

- **Duration bands:** **A+** ≤1.05×, **A** ≤1.11×, **A-** ≤1.16×, **B+** ≤1.22×, **B** ≤1.28×, **B-** ≤1.35×, **C+** ≤1.42×, **C** ≤1.49×, **C-** ≤1.57×, **D+** ≤1.65×, **D** ≤1.73×, **D-** ≤1.82×, **F** >1.82×
- **Cost bands:** **A+** ≤1.05×, **A** ≤1.09×, **A-** ≤1.14×, **B+** ≤1.19×, **B** ≤1.25×, **B-** ≤1.30×, **C+** ≤1.36×, **C** ≤1.42×, **C-** ≤1.49×, **D+** ≤1.55×, **D** ≤1.62×, **D-** ≤1.70×, **F** >1.70×

*Tests/Workflow Craft bands are absolute Overall score bands:* **A+** ≥4.7, **A** ≥4.4, **A-** ≥4.1, **B+** ≥3.8, **B** ≥3.5, **B-** ≥3.2, **C+** ≥2.9, **C** ≥2.6, **C-** ≥2.3, **D+** ≥2.0, **D** ≥1.7, **D-** ≥1.4, **F** <1.4, `—` = no data.*

### CLI Version Legend

| Variant label | CLI version | Tasks | Languages |
|---------------|-------------|-------|-----------|
| sonnet5 | 2.1.197 | All | All |

---
*Generated by generate_results.py — benchmark instructions v4*