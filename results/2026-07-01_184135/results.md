# Benchmark Results: Language Comparison

**Last updated:** 2026-07-02 05:52:33 AM ET — 56/56 runs completed, 0 remaining; total cost $284.77; total agent time 668.9 min.
**Claude Code versions used:** v2.1.198 (56 runs). Each link goes to a per-version snapshot of the system prompt, default-tool descriptions, and the chronological Anthropic changelog up to that version. Regenerate with `python3 version_docs.py`.

## Table of Contents

- [Scoring](#scoring)
  - [Duration columns](#duration-columns)
- [Tiers by Language/Model/Effort](#tiers-by-languagemodeleffort)
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

| Language | Model | Duration | Cost | Tests Quality | Workflow Craft |
|----------|-------|----------|------|-----------|-------------|
| bash | fable5-medium | A+ (8.0min) | A+ ($3.63) | — | — |
| default | fable5-medium | A (8.9min) | A- ($4.05) | — | — |
| typescript-bun | fable5-medium | B (10.8min) | B- ($4.65) | — | — |
| powershell | fable5-medium | D+ (15.0min) | B- ($4.70) | — | — |
| bash | fable5-high | C+ (11.8min) | D+ ($5.52) | — | — |
| default | fable5-high | B- (11.5min) | D- ($5.97) | — | — |
| typescript-bun | fable5-high | C+ (12.3min) | D- ($6.14) | — | — |
| powershell | fable5-high | D- (17.2min) | D- ($6.01) | — | — |


<details>
<summary>Sorted by Duration tier (best-first), then avg of Cost/Tests/Workflow Craft tiers</summary>

| Language | Model | Duration | Cost | Tests Quality | Workflow Craft |
|----------|-------|----------|------|-----------|-------------|
| bash | fable5-medium | A+ (8.0min) | A+ ($3.63) | — | — |
| default | fable5-medium | A (8.9min) | A- ($4.05) | — | — |
| typescript-bun | fable5-medium | B (10.8min) | B- ($4.65) | — | — |
| default | fable5-high | B- (11.5min) | D- ($5.97) | — | — |
| bash | fable5-high | C+ (11.8min) | D+ ($5.52) | — | — |
| typescript-bun | fable5-high | C+ (12.3min) | D- ($6.14) | — | — |
| powershell | fable5-medium | D+ (15.0min) | B- ($4.70) | — | — |
| powershell | fable5-high | D- (17.2min) | D- ($6.01) | — | — |

</details>

<details>
<summary>Sorted by Cost tier (best-first), then avg of Duration/Tests/Workflow Craft tiers</summary>

| Language | Model | Duration | Cost | Tests Quality | Workflow Craft |
|----------|-------|----------|------|-----------|-------------|
| bash | fable5-medium | A+ (8.0min) | A+ ($3.63) | — | — |
| default | fable5-medium | A (8.9min) | A- ($4.05) | — | — |
| typescript-bun | fable5-medium | B (10.8min) | B- ($4.65) | — | — |
| powershell | fable5-medium | D+ (15.0min) | B- ($4.70) | — | — |
| bash | fable5-high | C+ (11.8min) | D+ ($5.52) | — | — |
| default | fable5-high | B- (11.5min) | D- ($5.97) | — | — |
| typescript-bun | fable5-high | C+ (12.3min) | D- ($6.14) | — | — |
| powershell | fable5-high | D- (17.2min) | D- ($6.01) | — | — |

</details>

<details>
<summary>Sorted by Tests Quality tier (best-first; no-data last), then avg of other tiers</summary>

| Language | Model | Duration | Cost | Tests Quality | Workflow Craft |
|----------|-------|----------|------|-----------|-------------|
| bash | fable5-medium | A+ (8.0min) | A+ ($3.63) | — | — |
| default | fable5-medium | A (8.9min) | A- ($4.05) | — | — |
| typescript-bun | fable5-medium | B (10.8min) | B- ($4.65) | — | — |
| powershell | fable5-medium | D+ (15.0min) | B- ($4.70) | — | — |
| bash | fable5-high | C+ (11.8min) | D+ ($5.52) | — | — |
| default | fable5-high | B- (11.5min) | D- ($5.97) | — | — |
| typescript-bun | fable5-high | C+ (12.3min) | D- ($6.14) | — | — |
| powershell | fable5-high | D- (17.2min) | D- ($6.01) | — | — |

</details>

<details>
<summary>Sorted by Workflow Craft tier (best-first; no-data last), then avg of other tiers</summary>

| Language | Model | Duration | Cost | Tests Quality | Workflow Craft |
|----------|-------|----------|------|-----------|-------------|
| bash | fable5-medium | A+ (8.0min) | A+ ($3.63) | — | — |
| default | fable5-medium | A (8.9min) | A- ($4.05) | — | — |
| typescript-bun | fable5-medium | B (10.8min) | B- ($4.65) | — | — |
| powershell | fable5-medium | D+ (15.0min) | B- ($4.70) | — | — |
| bash | fable5-high | C+ (11.8min) | D+ ($5.52) | — | — |
| default | fable5-high | B- (11.5min) | D- ($5.97) | — | — |
| typescript-bun | fable5-high | C+ (12.3min) | D- ($6.14) | — | — |
| powershell | fable5-high | D- (17.2min) | D- ($6.01) | — | — |

</details>

## Comparison by Language/Model/Effort
*See [Notes](#notes) for scoring rubric and CLI version legend.*

| Language | Model | Runs | Avg Duration | Avg Duration Net of Traps | Avg Errors | Avg Turns | Avg Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| bash | fable5-high | 7 | 11.8min | 9.4min | 1.3 | 49 | $5.52 | $38.62 | — | — |
| bash | fable5-medium | 7 | 8.0min | 6.9min | 1.9 | 37 | $3.63 | $25.42 | — | — |
| default | fable5-high | 7 | 11.5min | 9.0min | 0.7 | 53 | $5.97 | $41.81 | — | — |
| default | fable5-medium | 7 | 8.9min | 7.6min | 1.1 | 40 | $4.05 | $28.38 | — | — |
| powershell | fable5-high | 7 | 17.2min | 16.1min | 4.1 | 44 | $6.01 | $42.05 | — | — |
| powershell | fable5-medium | 7 | 15.0min | 14.7min | 3.4 | 34 | $4.70 | $32.90 | — | — |
| typescript-bun | fable5-high | 7 | 12.3min | 7.7min | 1.3 | 52 | $6.14 | $43.01 | — | — |
| typescript-bun | fable5-medium | 7 | 10.8min | 8.1min | 0.4 | 43 | $4.65 | $32.58 | — | — |


<details>
<summary>Sorted by avg cost (cheapest first)</summary>

| Language | Model | Runs | Avg Duration | Avg Duration Net of Traps | Avg Errors | Avg Turns | Avg Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| bash | fable5-medium | 7 | 8.0min | 6.9min | 1.9 | 37 | $3.63 | $25.42 | — | — |
| default | fable5-medium | 7 | 8.9min | 7.6min | 1.1 | 40 | $4.05 | $28.38 | — | — |
| typescript-bun | fable5-medium | 7 | 10.8min | 8.1min | 0.4 | 43 | $4.65 | $32.58 | — | — |
| powershell | fable5-medium | 7 | 15.0min | 14.7min | 3.4 | 34 | $4.70 | $32.90 | — | — |
| bash | fable5-high | 7 | 11.8min | 9.4min | 1.3 | 49 | $5.52 | $38.62 | — | — |
| default | fable5-high | 7 | 11.5min | 9.0min | 0.7 | 53 | $5.97 | $41.81 | — | — |
| powershell | fable5-high | 7 | 17.2min | 16.1min | 4.1 | 44 | $6.01 | $42.05 | — | — |
| typescript-bun | fable5-high | 7 | 12.3min | 7.7min | 1.3 | 52 | $6.14 | $43.01 | — | — |

</details>

<details>
<summary>Sorted by avg duration (fastest first)</summary>

| Language | Model | Runs | Avg Duration | Avg Duration Net of Traps | Avg Errors | Avg Turns | Avg Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| bash | fable5-medium | 7 | 8.0min | 6.9min | 1.9 | 37 | $3.63 | $25.42 | — | — |
| default | fable5-medium | 7 | 8.9min | 7.6min | 1.1 | 40 | $4.05 | $28.38 | — | — |
| typescript-bun | fable5-medium | 7 | 10.8min | 8.1min | 0.4 | 43 | $4.65 | $32.58 | — | — |
| default | fable5-high | 7 | 11.5min | 9.0min | 0.7 | 53 | $5.97 | $41.81 | — | — |
| bash | fable5-high | 7 | 11.8min | 9.4min | 1.3 | 49 | $5.52 | $38.62 | — | — |
| typescript-bun | fable5-high | 7 | 12.3min | 7.7min | 1.3 | 52 | $6.14 | $43.01 | — | — |
| powershell | fable5-medium | 7 | 15.0min | 14.7min | 3.4 | 34 | $4.70 | $32.90 | — | — |
| powershell | fable5-high | 7 | 17.2min | 16.1min | 4.1 | 44 | $6.01 | $42.05 | — | — |

</details>

<details>
<summary>Sorted by avg duration net of traps (fastest first)</summary>

| Language | Model | Runs | Avg Duration | Avg Duration Net of Traps | Avg Errors | Avg Turns | Avg Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| bash | fable5-medium | 7 | 8.0min | 6.9min | 1.9 | 37 | $3.63 | $25.42 | — | — |
| default | fable5-medium | 7 | 8.9min | 7.6min | 1.1 | 40 | $4.05 | $28.38 | — | — |
| typescript-bun | fable5-high | 7 | 12.3min | 7.7min | 1.3 | 52 | $6.14 | $43.01 | — | — |
| typescript-bun | fable5-medium | 7 | 10.8min | 8.1min | 0.4 | 43 | $4.65 | $32.58 | — | — |
| default | fable5-high | 7 | 11.5min | 9.0min | 0.7 | 53 | $5.97 | $41.81 | — | — |
| bash | fable5-high | 7 | 11.8min | 9.4min | 1.3 | 49 | $5.52 | $38.62 | — | — |
| powershell | fable5-medium | 7 | 15.0min | 14.7min | 3.4 | 34 | $4.70 | $32.90 | — | — |
| powershell | fable5-high | 7 | 17.2min | 16.1min | 4.1 | 44 | $6.01 | $42.05 | — | — |

</details>

<details>
<summary>Sorted by avg errors (fewest first)</summary>

| Language | Model | Runs | Avg Duration | Avg Duration Net of Traps | Avg Errors | Avg Turns | Avg Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| typescript-bun | fable5-medium | 7 | 10.8min | 8.1min | 0.4 | 43 | $4.65 | $32.58 | — | — |
| default | fable5-high | 7 | 11.5min | 9.0min | 0.7 | 53 | $5.97 | $41.81 | — | — |
| default | fable5-medium | 7 | 8.9min | 7.6min | 1.1 | 40 | $4.05 | $28.38 | — | — |
| bash | fable5-high | 7 | 11.8min | 9.4min | 1.3 | 49 | $5.52 | $38.62 | — | — |
| typescript-bun | fable5-high | 7 | 12.3min | 7.7min | 1.3 | 52 | $6.14 | $43.01 | — | — |
| bash | fable5-medium | 7 | 8.0min | 6.9min | 1.9 | 37 | $3.63 | $25.42 | — | — |
| powershell | fable5-medium | 7 | 15.0min | 14.7min | 3.4 | 34 | $4.70 | $32.90 | — | — |
| powershell | fable5-high | 7 | 17.2min | 16.1min | 4.1 | 44 | $6.01 | $42.05 | — | — |

</details>

<details>
<summary>Sorted by avg turns (fewest first)</summary>

| Language | Model | Runs | Avg Duration | Avg Duration Net of Traps | Avg Errors | Avg Turns | Avg Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| powershell | fable5-medium | 7 | 15.0min | 14.7min | 3.4 | 34 | $4.70 | $32.90 | — | — |
| bash | fable5-medium | 7 | 8.0min | 6.9min | 1.9 | 37 | $3.63 | $25.42 | — | — |
| default | fable5-medium | 7 | 8.9min | 7.6min | 1.1 | 40 | $4.05 | $28.38 | — | — |
| typescript-bun | fable5-medium | 7 | 10.8min | 8.1min | 0.4 | 43 | $4.65 | $32.58 | — | — |
| powershell | fable5-high | 7 | 17.2min | 16.1min | 4.1 | 44 | $6.01 | $42.05 | — | — |
| bash | fable5-high | 7 | 11.8min | 9.4min | 1.3 | 49 | $5.52 | $38.62 | — | — |
| typescript-bun | fable5-high | 7 | 12.3min | 7.7min | 1.3 | 52 | $6.14 | $43.01 | — | — |
| default | fable5-high | 7 | 11.5min | 9.0min | 0.7 | 53 | $5.97 | $41.81 | — | — |

</details>

<details>
<summary>Sorted by LLM-as-judge score (best first)</summary>

| Language | Model | Runs | Avg Duration | Avg Duration Net of Traps | Avg Errors | Avg Turns | Avg Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| bash | fable5-high | 7 | 11.8min | 9.4min | 1.3 | 49 | $5.52 | $38.62 | — | — |
| bash | fable5-medium | 7 | 8.0min | 6.9min | 1.9 | 37 | $3.63 | $25.42 | — | — |
| default | fable5-high | 7 | 11.5min | 9.0min | 0.7 | 53 | $5.97 | $41.81 | — | — |
| default | fable5-medium | 7 | 8.9min | 7.6min | 1.1 | 40 | $4.05 | $28.38 | — | — |
| powershell | fable5-high | 7 | 17.2min | 16.1min | 4.1 | 44 | $6.01 | $42.05 | — | — |
| powershell | fable5-medium | 7 | 15.0min | 14.7min | 3.4 | 34 | $4.70 | $32.90 | — | — |
| typescript-bun | fable5-high | 7 | 12.3min | 7.7min | 1.3 | 52 | $6.14 | $43.01 | — | — |
| typescript-bun | fable5-medium | 7 | 10.8min | 8.1min | 0.4 | 43 | $4.65 | $32.58 | — | — |

</details>

<details>
<summary>Sorted by deliverable-quality score (best first)</summary>

| Language | Model | Runs | Avg Duration | Avg Duration Net of Traps | Avg Errors | Avg Turns | Avg Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| bash | fable5-high | 7 | 11.8min | 9.4min | 1.3 | 49 | $5.52 | $38.62 | — | — |
| bash | fable5-medium | 7 | 8.0min | 6.9min | 1.9 | 37 | $3.63 | $25.42 | — | — |
| default | fable5-high | 7 | 11.5min | 9.0min | 0.7 | 53 | $5.97 | $41.81 | — | — |
| default | fable5-medium | 7 | 8.9min | 7.6min | 1.1 | 40 | $4.05 | $28.38 | — | — |
| powershell | fable5-high | 7 | 17.2min | 16.1min | 4.1 | 44 | $6.01 | $42.05 | — | — |
| powershell | fable5-medium | 7 | 15.0min | 14.7min | 3.4 | 34 | $4.70 | $32.90 | — | — |
| typescript-bun | fable5-high | 7 | 12.3min | 7.7min | 1.3 | 52 | $6.14 | $43.01 | — | — |
| typescript-bun | fable5-medium | 7 | 10.8min | 8.1min | 0.4 | 43 | $4.65 | $32.58 | — | — |

</details>

## Savings Analysis

### Hook Savings by Language/Model/Effort

Each hook-caught error avoids one test run that would otherwise have been needed to discover it.
Every hook fire (hit or miss) costs execution time for the syntax/type checker.

*`% of Test Time Saved` = `net / (net + test_time) × 100` — the share of total (would-have-been + actually-spent) test time that hooks eliminated. Bounded in (-∞, 100%) without an artificial cap; near 100% means hooks substituted for almost all of the hypothetical test work.*

| Language | Model | Fires | Caught | Rate | Gross Saved | % of Time | Overhead | % of Time | Net Saved | % of Time | Test Run Time | % of Test Time Saved |
|------|-------|-------|--------|------|------------|-----------|----------|-----------|-----------|-----------|---------------|----------------------|
| bash | fable5-high-cli2.1.198 | 176 | 15 | 8.5% | 3.0min | 0.4% | 0.2min | 0.0% | 2.8min | 0.4% | 5.5min | 33.2% |
| bash | fable5-medium-cli2.1.198 | 130 | 8 | 6.2% | 1.6min | 0.2% | 0.1min | 0.0% | 1.5min | 0.2% | 8.7min | 14.5% |
| default | fable5-high-cli2.1.198 | 197 | 1 | 0.5% | 0.1min | 0.0% | 0.3min | 0.0% | -0.1min | -0.0% | 1.9min | -8.2% |
| default | fable5-medium-cli2.1.198 | 140 | 0 | 0.0% | 0.0min | 0.0% | 0.3min | 0.1% | -0.3min | -0.1% | 8.0min | -4.5% |
| powershell | fable5-high-cli2.1.198 | 166 | 34 | 20.5% | 19.8min | 3.0% | 22.4min | 3.4% | -2.6min | -0.4% | 9.2min | -38.7% |
| powershell | fable5-medium-cli2.1.198 | 129 | 20 | 15.5% | 11.7min | 1.7% | 18.6min | 2.8% | -7.0min | -1.0% | 5.9min | 652.9% |
| typescript-bun | fable5-high-cli2.1.198 | 185 | 102 | 55.1% | 13.6min | 2.0% | 3.1min | 0.5% | 10.5min | 1.6% | 0.8min | 92.9% |
| typescript-bun | fable5-medium-cli2.1.198 | 159 | 68 | 42.8% | 9.1min | 1.4% | 10.6min | 1.6% | -1.5min | -0.2% | 8.4min | -22.0% |


<details>
<summary>Sorted by net saved (most first)</summary>

| Language | Model | Fires | Caught | Rate | Gross Saved | % of Time | Overhead | % of Time | Net Saved | % of Time | Test Run Time | % of Test Time Saved |
|------|-------|-------|--------|------|------------|-----------|----------|-----------|-----------|-----------|---------------|----------------------|
| typescript-bun | fable5-high-cli2.1.198 | 185 | 102 | 55.1% | 13.6min | 2.0% | 3.1min | 0.5% | 10.5min | 1.6% | 0.8min | 92.9% |
| bash | fable5-high-cli2.1.198 | 176 | 15 | 8.5% | 3.0min | 0.4% | 0.2min | 0.0% | 2.8min | 0.4% | 5.5min | 33.2% |
| bash | fable5-medium-cli2.1.198 | 130 | 8 | 6.2% | 1.6min | 0.2% | 0.1min | 0.0% | 1.5min | 0.2% | 8.7min | 14.5% |
| default | fable5-high-cli2.1.198 | 197 | 1 | 0.5% | 0.1min | 0.0% | 0.3min | 0.0% | -0.1min | -0.0% | 1.9min | -8.2% |
| default | fable5-medium-cli2.1.198 | 140 | 0 | 0.0% | 0.0min | 0.0% | 0.3min | 0.1% | -0.3min | -0.1% | 8.0min | -4.5% |
| typescript-bun | fable5-medium-cli2.1.198 | 159 | 68 | 42.8% | 9.1min | 1.4% | 10.6min | 1.6% | -1.5min | -0.2% | 8.4min | -22.0% |
| powershell | fable5-high-cli2.1.198 | 166 | 34 | 20.5% | 19.8min | 3.0% | 22.4min | 3.4% | -2.6min | -0.4% | 9.2min | -38.7% |
| powershell | fable5-medium-cli2.1.198 | 129 | 20 | 15.5% | 11.7min | 1.7% | 18.6min | 2.8% | -7.0min | -1.0% | 5.9min | 652.9% |

</details>

<details>
<summary>Sorted by net % of test time saved (most first)</summary>

| Language | Model | Fires | Caught | Rate | Gross Saved | % of Time | Overhead | % of Time | Net Saved | % of Time | Test Run Time | % of Test Time Saved |
|------|-------|-------|--------|------|------------|-----------|----------|-----------|-----------|-----------|---------------|----------------------|
| powershell | fable5-medium-cli2.1.198 | 129 | 20 | 15.5% | 11.7min | 1.7% | 18.6min | 2.8% | -7.0min | -1.0% | 5.9min | 652.9% |
| typescript-bun | fable5-high-cli2.1.198 | 185 | 102 | 55.1% | 13.6min | 2.0% | 3.1min | 0.5% | 10.5min | 1.6% | 0.8min | 92.9% |
| bash | fable5-high-cli2.1.198 | 176 | 15 | 8.5% | 3.0min | 0.4% | 0.2min | 0.0% | 2.8min | 0.4% | 5.5min | 33.2% |
| bash | fable5-medium-cli2.1.198 | 130 | 8 | 6.2% | 1.6min | 0.2% | 0.1min | 0.0% | 1.5min | 0.2% | 8.7min | 14.5% |
| default | fable5-medium-cli2.1.198 | 140 | 0 | 0.0% | 0.0min | 0.0% | 0.3min | 0.1% | -0.3min | -0.1% | 8.0min | -4.5% |
| default | fable5-high-cli2.1.198 | 197 | 1 | 0.5% | 0.1min | 0.0% | 0.3min | 0.0% | -0.1min | -0.0% | 1.9min | -8.2% |
| typescript-bun | fable5-medium-cli2.1.198 | 159 | 68 | 42.8% | 9.1min | 1.4% | 10.6min | 1.6% | -1.5min | -0.2% | 8.4min | -22.0% |
| powershell | fable5-high-cli2.1.198 | 166 | 34 | 20.5% | 19.8min | 3.0% | 22.4min | 3.4% | -2.6min | -0.4% | 9.2min | -38.7% |

</details>

<details>
<summary>Sorted by catch rate (highest first)</summary>

| Language | Model | Fires | Caught | Rate | Gross Saved | % of Time | Overhead | % of Time | Net Saved | % of Time | Test Run Time | % of Test Time Saved |
|------|-------|-------|--------|------|------------|-----------|----------|-----------|-----------|-----------|---------------|----------------------|
| typescript-bun | fable5-high-cli2.1.198 | 185 | 102 | 55.1% | 13.6min | 2.0% | 3.1min | 0.5% | 10.5min | 1.6% | 0.8min | 92.9% |
| typescript-bun | fable5-medium-cli2.1.198 | 159 | 68 | 42.8% | 9.1min | 1.4% | 10.6min | 1.6% | -1.5min | -0.2% | 8.4min | -22.0% |
| powershell | fable5-high-cli2.1.198 | 166 | 34 | 20.5% | 19.8min | 3.0% | 22.4min | 3.4% | -2.6min | -0.4% | 9.2min | -38.7% |
| powershell | fable5-medium-cli2.1.198 | 129 | 20 | 15.5% | 11.7min | 1.7% | 18.6min | 2.8% | -7.0min | -1.0% | 5.9min | 652.9% |
| bash | fable5-high-cli2.1.198 | 176 | 15 | 8.5% | 3.0min | 0.4% | 0.2min | 0.0% | 2.8min | 0.4% | 5.5min | 33.2% |
| bash | fable5-medium-cli2.1.198 | 130 | 8 | 6.2% | 1.6min | 0.2% | 0.1min | 0.0% | 1.5min | 0.2% | 8.7min | 14.5% |
| default | fable5-high-cli2.1.198 | 197 | 1 | 0.5% | 0.1min | 0.0% | 0.3min | 0.0% | -0.1min | -0.0% | 1.9min | -8.2% |
| default | fable5-medium-cli2.1.198 | 140 | 0 | 0.0% | 0.0min | 0.0% | 0.3min | 0.1% | -0.3min | -0.1% | 8.0min | -4.5% |

</details>

### Trap Analysis by Language/Model/Effort/Category

| Trap | Language | Model | Fell In | Time Lost | % of Time | $ Lost | % of $ |
|------|------|-------|---------|-----------|-----------|--------|--------|
| repeated-test-reruns | bash | fable5-high-cli2.1.198 | 7 | 16.3min | 2.4% | $7.68 | 2.70% |
| repeated-test-reruns | bash | fable5-medium-cli2.1.198 | 4 | 6.7min | 1.0% | $3.11 | 1.09% |
| repeated-test-reruns | default | fable5-high-cli2.1.198 | 5 | 17.3min | 2.6% | $9.15 | 3.21% |
| repeated-test-reruns | default | fable5-medium-cli2.1.198 | 4 | 8.3min | 1.2% | $3.61 | 1.27% |
| repeated-test-reruns | powershell | fable5-high-cli2.1.198 | 3 | 7.3min | 1.1% | $2.76 | 0.97% |
| repeated-test-reruns | powershell | fable5-medium-cli2.1.198 | 1 | 2.7min | 0.4% | $1.07 | 0.38% |
| repeated-test-reruns | typescript-bun | fable5-high-cli2.1.198 | 6 | 12.0min | 1.8% | $6.01 | 2.11% |
| repeated-test-reruns | typescript-bun | fable5-medium-cli2.1.198 | 3 | 5.3min | 0.8% | $2.04 | 0.72% |
| ts-type-error-fix-cycles | typescript-bun | fable5-high-cli2.1.198 | 7 | 20.4min | 3.0% | $10.26 | 3.60% |
| ts-type-error-fix-cycles | typescript-bun | fable5-medium-cli2.1.198 | 7 | 13.6min | 2.0% | $5.75 | 2.02% |
| fixture-rework | bash | fable5-high-cli2.1.198 | 1 | 0.5min | 0.1% | $0.21 | 0.07% |
| fixture-rework | bash | fable5-medium-cli2.1.198 | 1 | 0.5min | 0.1% | $0.21 | 0.07% |
| fixture-rework | default | fable5-high-cli2.1.198 | 1 | 0.5min | 0.1% | $0.23 | 0.08% |
| fixture-rework | default | fable5-medium-cli2.1.198 | 1 | 0.8min | 0.1% | $0.35 | 0.12% |


<details>
<summary>Sorted by time lost (least first)</summary>

| Trap | Language | Model | Fell In | Time Lost | % of Time | $ Lost | % of $ |
|------|------|-------|---------|-----------|-----------|--------|--------|
| fixture-rework | bash | fable5-high-cli2.1.198 | 1 | 0.5min | 0.1% | $0.21 | 0.07% |
| fixture-rework | bash | fable5-medium-cli2.1.198 | 1 | 0.5min | 0.1% | $0.21 | 0.07% |
| fixture-rework | default | fable5-high-cli2.1.198 | 1 | 0.5min | 0.1% | $0.23 | 0.08% |
| fixture-rework | default | fable5-medium-cli2.1.198 | 1 | 0.8min | 0.1% | $0.35 | 0.12% |
| repeated-test-reruns | powershell | fable5-medium-cli2.1.198 | 1 | 2.7min | 0.4% | $1.07 | 0.38% |
| repeated-test-reruns | typescript-bun | fable5-medium-cli2.1.198 | 3 | 5.3min | 0.8% | $2.04 | 0.72% |
| repeated-test-reruns | bash | fable5-medium-cli2.1.198 | 4 | 6.7min | 1.0% | $3.11 | 1.09% |
| repeated-test-reruns | powershell | fable5-high-cli2.1.198 | 3 | 7.3min | 1.1% | $2.76 | 0.97% |
| repeated-test-reruns | default | fable5-medium-cli2.1.198 | 4 | 8.3min | 1.2% | $3.61 | 1.27% |
| repeated-test-reruns | typescript-bun | fable5-high-cli2.1.198 | 6 | 12.0min | 1.8% | $6.01 | 2.11% |
| ts-type-error-fix-cycles | typescript-bun | fable5-medium-cli2.1.198 | 7 | 13.6min | 2.0% | $5.75 | 2.02% |
| repeated-test-reruns | bash | fable5-high-cli2.1.198 | 7 | 16.3min | 2.4% | $7.68 | 2.70% |
| repeated-test-reruns | default | fable5-high-cli2.1.198 | 5 | 17.3min | 2.6% | $9.15 | 3.21% |
| ts-type-error-fix-cycles | typescript-bun | fable5-high-cli2.1.198 | 7 | 20.4min | 3.0% | $10.26 | 3.60% |

</details>

<details>
<summary>Sorted by $ lost (least first)</summary>

| Trap | Language | Model | Fell In | Time Lost | % of Time | $ Lost | % of $ |
|------|------|-------|---------|-----------|-----------|--------|--------|
| fixture-rework | bash | fable5-high-cli2.1.198 | 1 | 0.5min | 0.1% | $0.21 | 0.07% |
| fixture-rework | bash | fable5-medium-cli2.1.198 | 1 | 0.5min | 0.1% | $0.21 | 0.07% |
| fixture-rework | default | fable5-high-cli2.1.198 | 1 | 0.5min | 0.1% | $0.23 | 0.08% |
| fixture-rework | default | fable5-medium-cli2.1.198 | 1 | 0.8min | 0.1% | $0.35 | 0.12% |
| repeated-test-reruns | powershell | fable5-medium-cli2.1.198 | 1 | 2.7min | 0.4% | $1.07 | 0.38% |
| repeated-test-reruns | typescript-bun | fable5-medium-cli2.1.198 | 3 | 5.3min | 0.8% | $2.04 | 0.72% |
| repeated-test-reruns | powershell | fable5-high-cli2.1.198 | 3 | 7.3min | 1.1% | $2.76 | 0.97% |
| repeated-test-reruns | bash | fable5-medium-cli2.1.198 | 4 | 6.7min | 1.0% | $3.11 | 1.09% |
| repeated-test-reruns | default | fable5-medium-cli2.1.198 | 4 | 8.3min | 1.2% | $3.61 | 1.27% |
| ts-type-error-fix-cycles | typescript-bun | fable5-medium-cli2.1.198 | 7 | 13.6min | 2.0% | $5.75 | 2.02% |
| repeated-test-reruns | typescript-bun | fable5-high-cli2.1.198 | 6 | 12.0min | 1.8% | $6.01 | 2.11% |
| repeated-test-reruns | bash | fable5-high-cli2.1.198 | 7 | 16.3min | 2.4% | $7.68 | 2.70% |
| repeated-test-reruns | default | fable5-high-cli2.1.198 | 5 | 17.3min | 2.6% | $9.15 | 3.21% |
| ts-type-error-fix-cycles | typescript-bun | fable5-high-cli2.1.198 | 7 | 20.4min | 3.0% | $10.26 | 3.60% |

</details>

<details>
<summary>Sorted by fell-in count (fewest first)</summary>

| Trap | Language | Model | Fell In | Time Lost | % of Time | $ Lost | % of $ |
|------|------|-------|---------|-----------|-----------|--------|--------|
| repeated-test-reruns | powershell | fable5-medium-cli2.1.198 | 1 | 2.7min | 0.4% | $1.07 | 0.38% |
| fixture-rework | bash | fable5-high-cli2.1.198 | 1 | 0.5min | 0.1% | $0.21 | 0.07% |
| fixture-rework | bash | fable5-medium-cli2.1.198 | 1 | 0.5min | 0.1% | $0.21 | 0.07% |
| fixture-rework | default | fable5-high-cli2.1.198 | 1 | 0.5min | 0.1% | $0.23 | 0.08% |
| fixture-rework | default | fable5-medium-cli2.1.198 | 1 | 0.8min | 0.1% | $0.35 | 0.12% |
| repeated-test-reruns | powershell | fable5-high-cli2.1.198 | 3 | 7.3min | 1.1% | $2.76 | 0.97% |
| repeated-test-reruns | typescript-bun | fable5-medium-cli2.1.198 | 3 | 5.3min | 0.8% | $2.04 | 0.72% |
| repeated-test-reruns | bash | fable5-medium-cli2.1.198 | 4 | 6.7min | 1.0% | $3.11 | 1.09% |
| repeated-test-reruns | default | fable5-medium-cli2.1.198 | 4 | 8.3min | 1.2% | $3.61 | 1.27% |
| repeated-test-reruns | default | fable5-high-cli2.1.198 | 5 | 17.3min | 2.6% | $9.15 | 3.21% |
| repeated-test-reruns | typescript-bun | fable5-high-cli2.1.198 | 6 | 12.0min | 1.8% | $6.01 | 2.11% |
| repeated-test-reruns | bash | fable5-high-cli2.1.198 | 7 | 16.3min | 2.4% | $7.68 | 2.70% |
| ts-type-error-fix-cycles | typescript-bun | fable5-high-cli2.1.198 | 7 | 20.4min | 3.0% | $10.26 | 3.60% |
| ts-type-error-fix-cycles | typescript-bun | fable5-medium-cli2.1.198 | 7 | 13.6min | 2.0% | $5.75 | 2.02% |

</details>

#### Trap Descriptions

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
| bash | fable5-high-cli2.1.198 | 7 | 8 | 16.8min | 2.5% | $7.89 | 2.77% |
| bash | fable5-medium-cli2.1.198 | 7 | 5 | 7.2min | 1.1% | $3.32 | 1.17% |
| default | fable5-high-cli2.1.198 | 7 | 6 | 17.8min | 2.7% | $9.38 | 3.29% |
| default | fable5-medium-cli2.1.198 | 7 | 5 | 9.1min | 1.4% | $3.96 | 1.39% |
| powershell | fable5-high-cli2.1.198 | 7 | 3 | 7.3min | 1.1% | $2.76 | 0.97% |
| powershell | fable5-medium-cli2.1.198 | 7 | 1 | 2.7min | 0.4% | $1.07 | 0.38% |
| typescript-bun | fable5-high-cli2.1.198 | 7 | 13 | 32.4min | 4.8% | $16.27 | 5.71% |
| typescript-bun | fable5-medium-cli2.1.198 | 7 | 10 | 18.9min | 2.8% | $7.79 | 2.74% |


<details>
<summary>Sorted by time lost (least first)</summary>

| Language | Model | Runs | Traps | Time Lost | % of Time | $ Lost | % of $ |
|------|-------|------|-------|-----------|-----------|--------|--------|
| powershell | fable5-medium-cli2.1.198 | 7 | 1 | 2.7min | 0.4% | $1.07 | 0.38% |
| bash | fable5-medium-cli2.1.198 | 7 | 5 | 7.2min | 1.1% | $3.32 | 1.17% |
| powershell | fable5-high-cli2.1.198 | 7 | 3 | 7.3min | 1.1% | $2.76 | 0.97% |
| default | fable5-medium-cli2.1.198 | 7 | 5 | 9.1min | 1.4% | $3.96 | 1.39% |
| bash | fable5-high-cli2.1.198 | 7 | 8 | 16.8min | 2.5% | $7.89 | 2.77% |
| default | fable5-high-cli2.1.198 | 7 | 6 | 17.8min | 2.7% | $9.38 | 3.29% |
| typescript-bun | fable5-medium-cli2.1.198 | 7 | 10 | 18.9min | 2.8% | $7.79 | 2.74% |
| typescript-bun | fable5-high-cli2.1.198 | 7 | 13 | 32.4min | 4.8% | $16.27 | 5.71% |

</details>

<details>
<summary>Sorted by $ lost (least first)</summary>

| Language | Model | Runs | Traps | Time Lost | % of Time | $ Lost | % of $ |
|------|-------|------|-------|-----------|-----------|--------|--------|
| powershell | fable5-medium-cli2.1.198 | 7 | 1 | 2.7min | 0.4% | $1.07 | 0.38% |
| powershell | fable5-high-cli2.1.198 | 7 | 3 | 7.3min | 1.1% | $2.76 | 0.97% |
| bash | fable5-medium-cli2.1.198 | 7 | 5 | 7.2min | 1.1% | $3.32 | 1.17% |
| default | fable5-medium-cli2.1.198 | 7 | 5 | 9.1min | 1.4% | $3.96 | 1.39% |
| typescript-bun | fable5-medium-cli2.1.198 | 7 | 10 | 18.9min | 2.8% | $7.79 | 2.74% |
| bash | fable5-high-cli2.1.198 | 7 | 8 | 16.8min | 2.5% | $7.89 | 2.77% |
| default | fable5-high-cli2.1.198 | 7 | 6 | 17.8min | 2.7% | $9.38 | 3.29% |
| typescript-bun | fable5-high-cli2.1.198 | 7 | 13 | 32.4min | 4.8% | $16.27 | 5.71% |

</details>

### Prompt Cache Savings

| Status | Runs | $ Saved | % of $ |
|--------|------|---------|--------|
| Full hit (100%) | 0 | $0.00 | 0.00% |
| Partial | 54 | $11.38 | 4.00% |
| Miss | 2 | $0.00 | 0.00% |

## Test Quality Evaluation

### Structural Metrics by Language/Model/Effort

Automated analysis of test files: test count, assertion count, and test-to-code line ratio.

| Language | Model | Avg Tests | Avg Assertions | Avg Assert/Test | Avg Test:Code Ratio |
|------|-------|-----------|----------------|-----------------|---------------------|
| bash | fable5-high | 29.0 | 70.0 | 2.4 | 0.80 |
| bash | fable5-medium | 22.6 | 46.3 | 2.1 | 0.69 |
| default | fable5-high | 27.4 | 50.6 | 1.8 | 0.95 |
| default | fable5-medium | 22.9 | 43.7 | 1.9 | 0.96 |
| powershell | fable5-high | 41.9 | 77.9 | 1.9 | 3.58 |
| powershell | fable5-medium | 36.9 | 69.1 | 1.9 | 5.45 |
| typescript-bun | fable5-high | 39.6 | 75.1 | 1.9 | 0.84 |
| typescript-bun | fable5-medium | 34.4 | 67.1 | 2.0 | 1.17 |


<details>
<summary>Sorted by avg tests (most first)</summary>

| Language | Model | Avg Tests | Avg Assertions | Avg Assert/Test | Avg Test:Code Ratio |
|------|-------|-----------|----------------|-----------------|---------------------|
| powershell | fable5-high | 41.9 | 77.9 | 1.9 | 3.58 |
| typescript-bun | fable5-high | 39.6 | 75.1 | 1.9 | 0.84 |
| powershell | fable5-medium | 36.9 | 69.1 | 1.9 | 5.45 |
| typescript-bun | fable5-medium | 34.4 | 67.1 | 2.0 | 1.17 |
| bash | fable5-high | 29.0 | 70.0 | 2.4 | 0.80 |
| default | fable5-high | 27.4 | 50.6 | 1.8 | 0.95 |
| default | fable5-medium | 22.9 | 43.7 | 1.9 | 0.96 |
| bash | fable5-medium | 22.6 | 46.3 | 2.1 | 0.69 |

</details>

<details>
<summary>Sorted by avg assertions (most first)</summary>

| Language | Model | Avg Tests | Avg Assertions | Avg Assert/Test | Avg Test:Code Ratio |
|------|-------|-----------|----------------|-----------------|---------------------|
| powershell | fable5-high | 41.9 | 77.9 | 1.9 | 3.58 |
| typescript-bun | fable5-high | 39.6 | 75.1 | 1.9 | 0.84 |
| bash | fable5-high | 29.0 | 70.0 | 2.4 | 0.80 |
| powershell | fable5-medium | 36.9 | 69.1 | 1.9 | 5.45 |
| typescript-bun | fable5-medium | 34.4 | 67.1 | 2.0 | 1.17 |
| default | fable5-high | 27.4 | 50.6 | 1.8 | 0.95 |
| bash | fable5-medium | 22.6 | 46.3 | 2.1 | 0.69 |
| default | fable5-medium | 22.9 | 43.7 | 1.9 | 0.96 |

</details>

<details>
<summary>Sorted by avg test:code ratio (highest first)</summary>

| Language | Model | Avg Tests | Avg Assertions | Avg Assert/Test | Avg Test:Code Ratio |
|------|-------|-----------|----------------|-----------------|---------------------|
| powershell | fable5-medium | 36.9 | 69.1 | 1.9 | 5.45 |
| powershell | fable5-high | 41.9 | 77.9 | 1.9 | 3.58 |
| typescript-bun | fable5-medium | 34.4 | 67.1 | 2.0 | 1.17 |
| default | fable5-medium | 22.9 | 43.7 | 1.9 | 0.96 |
| default | fable5-high | 27.4 | 50.6 | 1.8 | 0.95 |
| typescript-bun | fable5-high | 39.6 | 75.1 | 1.9 | 0.84 |
| bash | fable5-high | 29.0 | 70.0 | 2.4 | 0.80 |
| bash | fable5-medium | 22.6 | 46.3 | 2.1 | 0.69 |

</details>


<details>
<summary>Per-run structural metrics</summary>

| Task | Language | Model | Tests | Assertions | Assert/Test | Test Lines | Impl Lines | Test:Code |
|------|------|-------|-------|------------|-------------|------------|------------|-----------|
| Semantic Version Bumper | bash | fable5-medium | 32 | 57 | 1.8 | 269 | 274 | 0.98 |
| Semantic Version Bumper | default | fable5-medium | 0 | 0 | 0.0 | 95 | 0 | 0.00 |
| Semantic Version Bumper | powershell | fable5-medium | 43 | 79 | 1.8 | 471 | 45 | 10.47 |
| Semantic Version Bumper | typescript-bun | fable5-medium | 41 | 66 | 1.6 | 365 | 504 | 0.72 |
| PR Label Assigner | bash | fable5-medium | 25 | 39 | 1.6 | 215 | 276 | 0.78 |
| PR Label Assigner | default | fable5-medium | 28 | 45 | 1.6 | 314 | 163 | 1.93 |
| PR Label Assigner | powershell | fable5-medium | 37 | 47 | 1.3 | 299 | 170 | 1.76 |
| PR Label Assigner | typescript-bun | fable5-medium | 32 | 73 | 2.3 | 511 | 214 | 2.39 |
| Dependency License Checker | bash | fable5-medium | 19 | 36 | 1.9 | 158 | 257 | 0.61 |
| Dependency License Checker | default | fable5-medium | 24 | 33 | 1.4 | 312 | 360 | 0.87 |
| Dependency License Checker | powershell | fable5-medium | 38 | 65 | 1.7 | 480 | 79 | 6.08 |
| Dependency License Checker | typescript-bun | fable5-medium | 34 | 50 | 1.5 | 422 | 510 | 0.83 |
| Test Results Aggregator | bash | fable5-medium | 26 | 60 | 2.3 | 240 | 327 | 0.73 |
| Test Results Aggregator | default | fable5-medium | 26 | 59 | 2.3 | 345 | 420 | 0.82 |
| Test Results Aggregator | powershell | fable5-medium | 43 | 86 | 2.0 | 497 | 66 | 7.53 |
| Test Results Aggregator | typescript-bun | fable5-medium | 33 | 70 | 2.1 | 661 | 487 | 1.36 |
| Environment Matrix Generator | bash | fable5-medium | 16 | 23 | 1.4 | 138 | 233 | 0.59 |
| Environment Matrix Generator | default | fable5-medium | 25 | 53 | 2.1 | 279 | 377 | 0.74 |
| Environment Matrix Generator | powershell | fable5-medium | 31 | 63 | 2.0 | 399 | 42 | 9.50 |
| Environment Matrix Generator | typescript-bun | fable5-medium | 27 | 50 | 1.9 | 384 | 422 | 0.91 |
| Artifact Cleanup Script | bash | fable5-medium | 18 | 50 | 2.8 | 185 | 335 | 0.55 |
| Artifact Cleanup Script | default | fable5-medium | 25 | 54 | 2.2 | 337 | 441 | 0.76 |
| Artifact Cleanup Script | powershell | fable5-medium | 27 | 65 | 2.4 | 348 | 298 | 1.17 |
| Artifact Cleanup Script | typescript-bun | fable5-medium | 33 | 75 | 2.3 | 579 | 437 | 1.32 |
| Secret Rotation Validator | bash | fable5-medium | 22 | 59 | 2.7 | 205 | 355 | 0.58 |
| Secret Rotation Validator | default | fable5-medium | 32 | 62 | 1.9 | 370 | 233 | 1.59 |
| Secret Rotation Validator | powershell | fable5-medium | 39 | 79 | 2.0 | 460 | 279 | 1.65 |
| Secret Rotation Validator | typescript-bun | fable5-medium | 41 | 86 | 2.1 | 496 | 733 | 0.68 |
| Semantic Version Bumper | default | fable5-high | 0 | 0 | 0.0 | 80 | 0 | 0.00 |
| Semantic Version Bumper | powershell | fable5-high | 41 | 78 | 1.9 | 521 | 54 | 9.65 |
| Semantic Version Bumper | bash | fable5-high | 31 | 86 | 2.8 | 316 | 357 | 0.89 |
| Semantic Version Bumper | typescript-bun | fable5-high | 54 | 93 | 1.7 | 547 | 571 | 0.96 |
| PR Label Assigner | default | fable5-high | 31 | 43 | 1.4 | 302 | 326 | 0.93 |
| PR Label Assigner | powershell | fable5-high | 44 | 49 | 1.1 | 338 | 211 | 1.60 |
| PR Label Assigner | bash | fable5-high | 26 | 58 | 2.2 | 327 | 309 | 1.06 |
| PR Label Assigner | typescript-bun | fable5-high | 37 | 59 | 1.6 | 385 | 432 | 0.89 |
| Dependency License Checker | default | fable5-high | 19 | 26 | 1.4 | 239 | 214 | 1.12 |
| Dependency License Checker | powershell | fable5-high | 48 | 80 | 1.7 | 593 | 73 | 8.12 |
| Dependency License Checker | bash | fable5-high | 25 | 74 | 3.0 | 244 | 349 | 0.70 |
| Dependency License Checker | typescript-bun | fable5-high | 28 | 50 | 1.8 | 460 | 544 | 0.85 |
| Test Results Aggregator | default | fable5-high | 20 | 65 | 3.2 | 320 | 523 | 0.61 |
| Test Results Aggregator | powershell | fable5-high | 43 | 72 | 1.7 | 340 | 229 | 1.48 |
| Test Results Aggregator | bash | fable5-high | 25 | 64 | 2.6 | 250 | 416 | 0.60 |
| Test Results Aggregator | typescript-bun | fable5-high | 42 | 71 | 1.7 | 503 | 661 | 0.76 |
| Environment Matrix Generator | default | fable5-high | 38 | 64 | 1.7 | 441 | 216 | 2.04 |
| Environment Matrix Generator | powershell | fable5-high | 51 | 112 | 2.2 | 586 | 353 | 1.66 |
| Environment Matrix Generator | bash | fable5-high | 41 | 71 | 1.7 | 300 | 354 | 0.85 |
| Environment Matrix Generator | typescript-bun | fable5-high | 32 | 69 | 2.2 | 403 | 553 | 0.73 |
| Artifact Cleanup Script | default | fable5-high | 43 | 87 | 2.0 | 571 | 578 | 0.99 |
| Artifact Cleanup Script | powershell | fable5-high | 30 | 68 | 2.3 | 376 | 282 | 1.33 |
| Artifact Cleanup Script | bash | fable5-high | 24 | 58 | 2.4 | 226 | 327 | 0.69 |
| Artifact Cleanup Script | typescript-bun | fable5-high | 39 | 90 | 2.3 | 563 | 795 | 0.71 |
| Secret Rotation Validator | default | fable5-high | 41 | 69 | 1.7 | 487 | 519 | 0.94 |
| Secret Rotation Validator | powershell | fable5-high | 36 | 86 | 2.4 | 387 | 316 | 1.22 |
| Secret Rotation Validator | bash | fable5-high | 31 | 79 | 2.5 | 268 | 322 | 0.83 |
| Secret Rotation Validator | typescript-bun | fable5-high | 45 | 94 | 2.1 | 569 | 596 | 0.95 |

</details>

## Per-Run Results

*Tests Quality = Overall (1-5) from LLM-as-judge of generated test code (dimensions: coverage, rigor, design). `—` = no judge data.*

| Task | Language | Model | Duration | Turns | Errors | Cost | Tests Quality | Chosen | Status |
|------|----------|-------|----------|-------|--------|------|-----------|--------|--------|
| Artifact Cleanup Script | bash | fable5-high | 11.8min | 49 | 0 | $5.55 | — | bash | ok |
| Artifact Cleanup Script | bash | fable5-medium | 7.7min | 31 | 5 | $3.53 | — | bash | ok |
| Artifact Cleanup Script | default | fable5-high | 15.1min | 71 | 0 | $8.50 | — | python | ok |
| Artifact Cleanup Script | default | fable5-medium | 12.1min | 52 | 0 | $5.22 | — | python | ok |
| Artifact Cleanup Script | powershell | fable5-high | 17.6min | 46 | 0 | $6.49 | — | powershell | ok |
| Artifact Cleanup Script | powershell | fable5-medium | 17.1min | 46 | 1 | $6.86 | — | powershell | ok |
| Artifact Cleanup Script | typescript-bun | fable5-high | 15.2min | 62 | 1 | $9.45 | — | typescript | ok |
| Artifact Cleanup Script | typescript-bun | fable5-medium | 14.5min | 51 | 0 | $5.68 | — | typescript | ok |
| Dependency License Checker | bash | fable5-high | 9.9min | 46 | 0 | $4.58 | — | bash | ok |
| Dependency License Checker | bash | fable5-medium | 6.3min | 36 | 1 | $2.95 | — | bash | ok |
| Dependency License Checker | default | fable5-high | 9.6min | 46 | 1 | $4.49 | — | javascript | ok |
| Dependency License Checker | default | fable5-medium | 6.8min | 29 | 2 | $2.90 | — | python | ok |
| Dependency License Checker | powershell | fable5-high | 16.8min | 41 | 6 | $5.67 | — | powershell | ok |
| Dependency License Checker | powershell | fable5-medium | 11.2min | 20 | 2 | $3.23 | — | powershell | ok |
| Dependency License Checker | typescript-bun | fable5-high | 11.7min | 46 | 0 | $4.49 | — | typescript | ok |
| Dependency License Checker | typescript-bun | fable5-medium | 9.2min | 46 | 0 | $4.24 | — | typescript | ok |
| Environment Matrix Generator | bash | fable5-high | 11.2min | 45 | 1 | $6.86 | — | bash | ok |
| Environment Matrix Generator | bash | fable5-medium | 7.5min | 37 | 1 | $3.41 | — | bash | ok |
| Environment Matrix Generator | default | fable5-high | 13.5min | 65 | 1 | $6.97 | — | python | ok |
| Environment Matrix Generator | default | fable5-medium | 10.6min | 47 | 2 | $4.57 | — | python | ok |
| Environment Matrix Generator | powershell | fable5-high | 21.5min | 45 | 8 | $7.73 | — | powershell | ok |
| Environment Matrix Generator | powershell | fable5-medium | 12.6min | 34 | 6 | $4.34 | — | powershell | ok |
| Environment Matrix Generator | typescript-bun | fable5-high | 15.1min | 55 | 4 | $6.33 | — | typescript | ok |
| Environment Matrix Generator | typescript-bun | fable5-medium | 7.9min | 36 | 3 | $5.00 | — | typescript | ok |
| PR Label Assigner | bash | fable5-high | 11.7min | 46 | 2 | $4.85 | — | bash | ok |
| PR Label Assigner | bash | fable5-medium | 8.6min | 46 | 2 | $4.15 | — | bash | ok |
| PR Label Assigner | default | fable5-high | 9.0min | 41 | 1 | $3.87 | — | python | ok |
| PR Label Assigner | default | fable5-medium | 6.8min | 35 | 1 | $3.04 | — | python | ok |
| PR Label Assigner | powershell | fable5-high | 12.5min | 43 | 1 | $5.49 | — | powershell | ok |
| PR Label Assigner | powershell | fable5-medium | 12.0min | 32 | 1 | $3.41 | — | powershell | ok |
| PR Label Assigner | typescript-bun | fable5-high | 9.8min | 47 | 0 | $4.64 | — | typescript | ok |
| PR Label Assigner | typescript-bun | fable5-medium | 11.9min | 46 | 0 | $4.46 | — | typescript | ok |
| Secret Rotation Validator | bash | fable5-high | 12.5min | 48 | 3 | $5.19 | — | bash | ok |
| Secret Rotation Validator | bash | fable5-medium | 9.4min | 37 | 0 | $3.92 | — | bash | ok |
| Secret Rotation Validator | default | fable5-high | 12.3min | 58 | 1 | $7.27 | — | python | ok |
| Secret Rotation Validator | default | fable5-medium | 7.3min | 32 | 0 | $3.13 | — | python | ok |
| Secret Rotation Validator | powershell | fable5-high | 17.4min | 37 | 6 | $5.79 | — | powershell | ok |
| Secret Rotation Validator | powershell | fable5-medium | 18.0min | 30 | 5 | $5.33 | — | powershell | ok |
| Secret Rotation Validator | typescript-bun | fable5-high | 11.5min | 51 | 1 | $5.95 | — | typescript | ok |
| Secret Rotation Validator | typescript-bun | fable5-medium | 12.7min | 42 | 0 | $4.84 | — | typescript | ok |
| Semantic Version Bumper | bash | fable5-high | 12.0min | 55 | 1 | $5.33 | — | bash | ok |
| Semantic Version Bumper | bash | fable5-medium | 8.4min | 39 | 1 | $3.99 | — | bash | ok |
| Semantic Version Bumper | default | fable5-high | 12.9min | 52 | 1 | $6.53 | — | javascript | ok |
| Semantic Version Bumper | default | fable5-medium | 9.1min | 35 | 2 | $4.21 | — | javascript | ok |
| Semantic Version Bumper | powershell | fable5-high | 19.3min | 47 | 2 | $5.82 | — | powershell | ok |
| Semantic Version Bumper | powershell | fable5-medium | 19.0min | 36 | 4 | $4.65 | — | powershell | ok |
| Semantic Version Bumper | typescript-bun | fable5-high | 11.2min | 48 | 1 | $6.25 | — | typescript | ok |
| Semantic Version Bumper | typescript-bun | fable5-medium | 8.9min | 36 | 0 | $3.39 | — | typescript | ok |
| Test Results Aggregator | bash | fable5-high | 13.7min | 52 | 2 | $6.27 | — | bash | ok |
| Test Results Aggregator | bash | fable5-medium | 7.8min | 34 | 3 | $3.46 | — | bash | ok |
| Test Results Aggregator | default | fable5-high | 8.4min | 39 | 0 | $4.18 | — | python | ok |
| Test Results Aggregator | default | fable5-medium | 9.8min | 47 | 1 | $5.30 | — | python | ok |
| Test Results Aggregator | powershell | fable5-high | 15.0min | 46 | 6 | $5.05 | — | powershell | ok |
| Test Results Aggregator | powershell | fable5-medium | 15.2min | 40 | 5 | $5.09 | — | powershell | ok |
| Test Results Aggregator | typescript-bun | fable5-high | 11.7min | 55 | 2 | $5.91 | — | typescript | ok |
| Test Results Aggregator | typescript-bun | fable5-medium | 10.7min | 46 | 0 | $4.98 | — | typescript | ok |


<details>
<summary>Sorted by cost (cheapest first)</summary>

| Task | Language | Model | Duration | Turns | Errors | Cost | Tests Quality | Chosen | Status |
|------|----------|-------|----------|-------|--------|------|-----------|--------|--------|
| Dependency License Checker | default | fable5-medium | 6.8min | 29 | 2 | $2.90 | — | python | ok |
| Dependency License Checker | bash | fable5-medium | 6.3min | 36 | 1 | $2.95 | — | bash | ok |
| PR Label Assigner | default | fable5-medium | 6.8min | 35 | 1 | $3.04 | — | python | ok |
| Secret Rotation Validator | default | fable5-medium | 7.3min | 32 | 0 | $3.13 | — | python | ok |
| Dependency License Checker | powershell | fable5-medium | 11.2min | 20 | 2 | $3.23 | — | powershell | ok |
| Semantic Version Bumper | typescript-bun | fable5-medium | 8.9min | 36 | 0 | $3.39 | — | typescript | ok |
| Environment Matrix Generator | bash | fable5-medium | 7.5min | 37 | 1 | $3.41 | — | bash | ok |
| PR Label Assigner | powershell | fable5-medium | 12.0min | 32 | 1 | $3.41 | — | powershell | ok |
| Test Results Aggregator | bash | fable5-medium | 7.8min | 34 | 3 | $3.46 | — | bash | ok |
| Artifact Cleanup Script | bash | fable5-medium | 7.7min | 31 | 5 | $3.53 | — | bash | ok |
| PR Label Assigner | default | fable5-high | 9.0min | 41 | 1 | $3.87 | — | python | ok |
| Secret Rotation Validator | bash | fable5-medium | 9.4min | 37 | 0 | $3.92 | — | bash | ok |
| Semantic Version Bumper | bash | fable5-medium | 8.4min | 39 | 1 | $3.99 | — | bash | ok |
| PR Label Assigner | bash | fable5-medium | 8.6min | 46 | 2 | $4.15 | — | bash | ok |
| Test Results Aggregator | default | fable5-high | 8.4min | 39 | 0 | $4.18 | — | python | ok |
| Semantic Version Bumper | default | fable5-medium | 9.1min | 35 | 2 | $4.21 | — | javascript | ok |
| Dependency License Checker | typescript-bun | fable5-medium | 9.2min | 46 | 0 | $4.24 | — | typescript | ok |
| Environment Matrix Generator | powershell | fable5-medium | 12.6min | 34 | 6 | $4.34 | — | powershell | ok |
| PR Label Assigner | typescript-bun | fable5-medium | 11.9min | 46 | 0 | $4.46 | — | typescript | ok |
| Dependency License Checker | typescript-bun | fable5-high | 11.7min | 46 | 0 | $4.49 | — | typescript | ok |
| Dependency License Checker | default | fable5-high | 9.6min | 46 | 1 | $4.49 | — | javascript | ok |
| Environment Matrix Generator | default | fable5-medium | 10.6min | 47 | 2 | $4.57 | — | python | ok |
| Dependency License Checker | bash | fable5-high | 9.9min | 46 | 0 | $4.58 | — | bash | ok |
| PR Label Assigner | typescript-bun | fable5-high | 9.8min | 47 | 0 | $4.64 | — | typescript | ok |
| Semantic Version Bumper | powershell | fable5-medium | 19.0min | 36 | 4 | $4.65 | — | powershell | ok |
| Secret Rotation Validator | typescript-bun | fable5-medium | 12.7min | 42 | 0 | $4.84 | — | typescript | ok |
| PR Label Assigner | bash | fable5-high | 11.7min | 46 | 2 | $4.85 | — | bash | ok |
| Test Results Aggregator | typescript-bun | fable5-medium | 10.7min | 46 | 0 | $4.98 | — | typescript | ok |
| Environment Matrix Generator | typescript-bun | fable5-medium | 7.9min | 36 | 3 | $5.00 | — | typescript | ok |
| Test Results Aggregator | powershell | fable5-high | 15.0min | 46 | 6 | $5.05 | — | powershell | ok |
| Test Results Aggregator | powershell | fable5-medium | 15.2min | 40 | 5 | $5.09 | — | powershell | ok |
| Secret Rotation Validator | bash | fable5-high | 12.5min | 48 | 3 | $5.19 | — | bash | ok |
| Artifact Cleanup Script | default | fable5-medium | 12.1min | 52 | 0 | $5.22 | — | python | ok |
| Test Results Aggregator | default | fable5-medium | 9.8min | 47 | 1 | $5.30 | — | python | ok |
| Secret Rotation Validator | powershell | fable5-medium | 18.0min | 30 | 5 | $5.33 | — | powershell | ok |
| Semantic Version Bumper | bash | fable5-high | 12.0min | 55 | 1 | $5.33 | — | bash | ok |
| PR Label Assigner | powershell | fable5-high | 12.5min | 43 | 1 | $5.49 | — | powershell | ok |
| Artifact Cleanup Script | bash | fable5-high | 11.8min | 49 | 0 | $5.55 | — | bash | ok |
| Dependency License Checker | powershell | fable5-high | 16.8min | 41 | 6 | $5.67 | — | powershell | ok |
| Artifact Cleanup Script | typescript-bun | fable5-medium | 14.5min | 51 | 0 | $5.68 | — | typescript | ok |
| Secret Rotation Validator | powershell | fable5-high | 17.4min | 37 | 6 | $5.79 | — | powershell | ok |
| Semantic Version Bumper | powershell | fable5-high | 19.3min | 47 | 2 | $5.82 | — | powershell | ok |
| Test Results Aggregator | typescript-bun | fable5-high | 11.7min | 55 | 2 | $5.91 | — | typescript | ok |
| Secret Rotation Validator | typescript-bun | fable5-high | 11.5min | 51 | 1 | $5.95 | — | typescript | ok |
| Semantic Version Bumper | typescript-bun | fable5-high | 11.2min | 48 | 1 | $6.25 | — | typescript | ok |
| Test Results Aggregator | bash | fable5-high | 13.7min | 52 | 2 | $6.27 | — | bash | ok |
| Environment Matrix Generator | typescript-bun | fable5-high | 15.1min | 55 | 4 | $6.33 | — | typescript | ok |
| Artifact Cleanup Script | powershell | fable5-high | 17.6min | 46 | 0 | $6.49 | — | powershell | ok |
| Semantic Version Bumper | default | fable5-high | 12.9min | 52 | 1 | $6.53 | — | javascript | ok |
| Environment Matrix Generator | bash | fable5-high | 11.2min | 45 | 1 | $6.86 | — | bash | ok |
| Artifact Cleanup Script | powershell | fable5-medium | 17.1min | 46 | 1 | $6.86 | — | powershell | ok |
| Environment Matrix Generator | default | fable5-high | 13.5min | 65 | 1 | $6.97 | — | python | ok |
| Secret Rotation Validator | default | fable5-high | 12.3min | 58 | 1 | $7.27 | — | python | ok |
| Environment Matrix Generator | powershell | fable5-high | 21.5min | 45 | 8 | $7.73 | — | powershell | ok |
| Artifact Cleanup Script | default | fable5-high | 15.1min | 71 | 0 | $8.50 | — | python | ok |
| Artifact Cleanup Script | typescript-bun | fable5-high | 15.2min | 62 | 1 | $9.45 | — | typescript | ok |

</details>

<details>
<summary>Sorted by duration (fastest first)</summary>

| Task | Language | Model | Duration | Turns | Errors | Cost | Tests Quality | Chosen | Status |
|------|----------|-------|----------|-------|--------|------|-----------|--------|--------|
| Dependency License Checker | bash | fable5-medium | 6.3min | 36 | 1 | $2.95 | — | bash | ok |
| PR Label Assigner | default | fable5-medium | 6.8min | 35 | 1 | $3.04 | — | python | ok |
| Dependency License Checker | default | fable5-medium | 6.8min | 29 | 2 | $2.90 | — | python | ok |
| Secret Rotation Validator | default | fable5-medium | 7.3min | 32 | 0 | $3.13 | — | python | ok |
| Environment Matrix Generator | bash | fable5-medium | 7.5min | 37 | 1 | $3.41 | — | bash | ok |
| Artifact Cleanup Script | bash | fable5-medium | 7.7min | 31 | 5 | $3.53 | — | bash | ok |
| Test Results Aggregator | bash | fable5-medium | 7.8min | 34 | 3 | $3.46 | — | bash | ok |
| Environment Matrix Generator | typescript-bun | fable5-medium | 7.9min | 36 | 3 | $5.00 | — | typescript | ok |
| Test Results Aggregator | default | fable5-high | 8.4min | 39 | 0 | $4.18 | — | python | ok |
| Semantic Version Bumper | bash | fable5-medium | 8.4min | 39 | 1 | $3.99 | — | bash | ok |
| PR Label Assigner | bash | fable5-medium | 8.6min | 46 | 2 | $4.15 | — | bash | ok |
| Semantic Version Bumper | typescript-bun | fable5-medium | 8.9min | 36 | 0 | $3.39 | — | typescript | ok |
| PR Label Assigner | default | fable5-high | 9.0min | 41 | 1 | $3.87 | — | python | ok |
| Semantic Version Bumper | default | fable5-medium | 9.1min | 35 | 2 | $4.21 | — | javascript | ok |
| Dependency License Checker | typescript-bun | fable5-medium | 9.2min | 46 | 0 | $4.24 | — | typescript | ok |
| Secret Rotation Validator | bash | fable5-medium | 9.4min | 37 | 0 | $3.92 | — | bash | ok |
| Dependency License Checker | default | fable5-high | 9.6min | 46 | 1 | $4.49 | — | javascript | ok |
| Test Results Aggregator | default | fable5-medium | 9.8min | 47 | 1 | $5.30 | — | python | ok |
| PR Label Assigner | typescript-bun | fable5-high | 9.8min | 47 | 0 | $4.64 | — | typescript | ok |
| Dependency License Checker | bash | fable5-high | 9.9min | 46 | 0 | $4.58 | — | bash | ok |
| Environment Matrix Generator | default | fable5-medium | 10.6min | 47 | 2 | $4.57 | — | python | ok |
| Test Results Aggregator | typescript-bun | fable5-medium | 10.7min | 46 | 0 | $4.98 | — | typescript | ok |
| Environment Matrix Generator | bash | fable5-high | 11.2min | 45 | 1 | $6.86 | — | bash | ok |
| Dependency License Checker | powershell | fable5-medium | 11.2min | 20 | 2 | $3.23 | — | powershell | ok |
| Semantic Version Bumper | typescript-bun | fable5-high | 11.2min | 48 | 1 | $6.25 | — | typescript | ok |
| Secret Rotation Validator | typescript-bun | fable5-high | 11.5min | 51 | 1 | $5.95 | — | typescript | ok |
| Test Results Aggregator | typescript-bun | fable5-high | 11.7min | 55 | 2 | $5.91 | — | typescript | ok |
| Dependency License Checker | typescript-bun | fable5-high | 11.7min | 46 | 0 | $4.49 | — | typescript | ok |
| PR Label Assigner | bash | fable5-high | 11.7min | 46 | 2 | $4.85 | — | bash | ok |
| Artifact Cleanup Script | bash | fable5-high | 11.8min | 49 | 0 | $5.55 | — | bash | ok |
| PR Label Assigner | typescript-bun | fable5-medium | 11.9min | 46 | 0 | $4.46 | — | typescript | ok |
| Semantic Version Bumper | bash | fable5-high | 12.0min | 55 | 1 | $5.33 | — | bash | ok |
| PR Label Assigner | powershell | fable5-medium | 12.0min | 32 | 1 | $3.41 | — | powershell | ok |
| Artifact Cleanup Script | default | fable5-medium | 12.1min | 52 | 0 | $5.22 | — | python | ok |
| Secret Rotation Validator | default | fable5-high | 12.3min | 58 | 1 | $7.27 | — | python | ok |
| Secret Rotation Validator | bash | fable5-high | 12.5min | 48 | 3 | $5.19 | — | bash | ok |
| PR Label Assigner | powershell | fable5-high | 12.5min | 43 | 1 | $5.49 | — | powershell | ok |
| Environment Matrix Generator | powershell | fable5-medium | 12.6min | 34 | 6 | $4.34 | — | powershell | ok |
| Secret Rotation Validator | typescript-bun | fable5-medium | 12.7min | 42 | 0 | $4.84 | — | typescript | ok |
| Semantic Version Bumper | default | fable5-high | 12.9min | 52 | 1 | $6.53 | — | javascript | ok |
| Environment Matrix Generator | default | fable5-high | 13.5min | 65 | 1 | $6.97 | — | python | ok |
| Test Results Aggregator | bash | fable5-high | 13.7min | 52 | 2 | $6.27 | — | bash | ok |
| Artifact Cleanup Script | typescript-bun | fable5-medium | 14.5min | 51 | 0 | $5.68 | — | typescript | ok |
| Test Results Aggregator | powershell | fable5-high | 15.0min | 46 | 6 | $5.05 | — | powershell | ok |
| Environment Matrix Generator | typescript-bun | fable5-high | 15.1min | 55 | 4 | $6.33 | — | typescript | ok |
| Artifact Cleanup Script | default | fable5-high | 15.1min | 71 | 0 | $8.50 | — | python | ok |
| Artifact Cleanup Script | typescript-bun | fable5-high | 15.2min | 62 | 1 | $9.45 | — | typescript | ok |
| Test Results Aggregator | powershell | fable5-medium | 15.2min | 40 | 5 | $5.09 | — | powershell | ok |
| Dependency License Checker | powershell | fable5-high | 16.8min | 41 | 6 | $5.67 | — | powershell | ok |
| Artifact Cleanup Script | powershell | fable5-medium | 17.1min | 46 | 1 | $6.86 | — | powershell | ok |
| Secret Rotation Validator | powershell | fable5-high | 17.4min | 37 | 6 | $5.79 | — | powershell | ok |
| Artifact Cleanup Script | powershell | fable5-high | 17.6min | 46 | 0 | $6.49 | — | powershell | ok |
| Secret Rotation Validator | powershell | fable5-medium | 18.0min | 30 | 5 | $5.33 | — | powershell | ok |
| Semantic Version Bumper | powershell | fable5-medium | 19.0min | 36 | 4 | $4.65 | — | powershell | ok |
| Semantic Version Bumper | powershell | fable5-high | 19.3min | 47 | 2 | $5.82 | — | powershell | ok |
| Environment Matrix Generator | powershell | fable5-high | 21.5min | 45 | 8 | $7.73 | — | powershell | ok |

</details>

<details>
<summary>Sorted by errors (fewest first)</summary>

| Task | Language | Model | Duration | Turns | Errors | Cost | Tests Quality | Chosen | Status |
|------|----------|-------|----------|-------|--------|------|-----------|--------|--------|
| Semantic Version Bumper | typescript-bun | fable5-medium | 8.9min | 36 | 0 | $3.39 | — | typescript | ok |
| PR Label Assigner | typescript-bun | fable5-medium | 11.9min | 46 | 0 | $4.46 | — | typescript | ok |
| Dependency License Checker | typescript-bun | fable5-medium | 9.2min | 46 | 0 | $4.24 | — | typescript | ok |
| Test Results Aggregator | typescript-bun | fable5-medium | 10.7min | 46 | 0 | $4.98 | — | typescript | ok |
| Artifact Cleanup Script | default | fable5-medium | 12.1min | 52 | 0 | $5.22 | — | python | ok |
| Artifact Cleanup Script | typescript-bun | fable5-medium | 14.5min | 51 | 0 | $5.68 | — | typescript | ok |
| Secret Rotation Validator | bash | fable5-medium | 9.4min | 37 | 0 | $3.92 | — | bash | ok |
| Secret Rotation Validator | default | fable5-medium | 7.3min | 32 | 0 | $3.13 | — | python | ok |
| Secret Rotation Validator | typescript-bun | fable5-medium | 12.7min | 42 | 0 | $4.84 | — | typescript | ok |
| PR Label Assigner | typescript-bun | fable5-high | 9.8min | 47 | 0 | $4.64 | — | typescript | ok |
| Dependency License Checker | bash | fable5-high | 9.9min | 46 | 0 | $4.58 | — | bash | ok |
| Dependency License Checker | typescript-bun | fable5-high | 11.7min | 46 | 0 | $4.49 | — | typescript | ok |
| Test Results Aggregator | default | fable5-high | 8.4min | 39 | 0 | $4.18 | — | python | ok |
| Artifact Cleanup Script | default | fable5-high | 15.1min | 71 | 0 | $8.50 | — | python | ok |
| Artifact Cleanup Script | powershell | fable5-high | 17.6min | 46 | 0 | $6.49 | — | powershell | ok |
| Artifact Cleanup Script | bash | fable5-high | 11.8min | 49 | 0 | $5.55 | — | bash | ok |
| Semantic Version Bumper | bash | fable5-medium | 8.4min | 39 | 1 | $3.99 | — | bash | ok |
| PR Label Assigner | default | fable5-medium | 6.8min | 35 | 1 | $3.04 | — | python | ok |
| PR Label Assigner | powershell | fable5-medium | 12.0min | 32 | 1 | $3.41 | — | powershell | ok |
| Dependency License Checker | bash | fable5-medium | 6.3min | 36 | 1 | $2.95 | — | bash | ok |
| Test Results Aggregator | default | fable5-medium | 9.8min | 47 | 1 | $5.30 | — | python | ok |
| Environment Matrix Generator | bash | fable5-medium | 7.5min | 37 | 1 | $3.41 | — | bash | ok |
| Artifact Cleanup Script | powershell | fable5-medium | 17.1min | 46 | 1 | $6.86 | — | powershell | ok |
| Semantic Version Bumper | default | fable5-high | 12.9min | 52 | 1 | $6.53 | — | javascript | ok |
| Semantic Version Bumper | bash | fable5-high | 12.0min | 55 | 1 | $5.33 | — | bash | ok |
| Semantic Version Bumper | typescript-bun | fable5-high | 11.2min | 48 | 1 | $6.25 | — | typescript | ok |
| PR Label Assigner | default | fable5-high | 9.0min | 41 | 1 | $3.87 | — | python | ok |
| PR Label Assigner | powershell | fable5-high | 12.5min | 43 | 1 | $5.49 | — | powershell | ok |
| Dependency License Checker | default | fable5-high | 9.6min | 46 | 1 | $4.49 | — | javascript | ok |
| Environment Matrix Generator | default | fable5-high | 13.5min | 65 | 1 | $6.97 | — | python | ok |
| Environment Matrix Generator | bash | fable5-high | 11.2min | 45 | 1 | $6.86 | — | bash | ok |
| Artifact Cleanup Script | typescript-bun | fable5-high | 15.2min | 62 | 1 | $9.45 | — | typescript | ok |
| Secret Rotation Validator | default | fable5-high | 12.3min | 58 | 1 | $7.27 | — | python | ok |
| Secret Rotation Validator | typescript-bun | fable5-high | 11.5min | 51 | 1 | $5.95 | — | typescript | ok |
| Semantic Version Bumper | default | fable5-medium | 9.1min | 35 | 2 | $4.21 | — | javascript | ok |
| PR Label Assigner | bash | fable5-medium | 8.6min | 46 | 2 | $4.15 | — | bash | ok |
| Dependency License Checker | default | fable5-medium | 6.8min | 29 | 2 | $2.90 | — | python | ok |
| Dependency License Checker | powershell | fable5-medium | 11.2min | 20 | 2 | $3.23 | — | powershell | ok |
| Environment Matrix Generator | default | fable5-medium | 10.6min | 47 | 2 | $4.57 | — | python | ok |
| Semantic Version Bumper | powershell | fable5-high | 19.3min | 47 | 2 | $5.82 | — | powershell | ok |
| PR Label Assigner | bash | fable5-high | 11.7min | 46 | 2 | $4.85 | — | bash | ok |
| Test Results Aggregator | bash | fable5-high | 13.7min | 52 | 2 | $6.27 | — | bash | ok |
| Test Results Aggregator | typescript-bun | fable5-high | 11.7min | 55 | 2 | $5.91 | — | typescript | ok |
| Test Results Aggregator | bash | fable5-medium | 7.8min | 34 | 3 | $3.46 | — | bash | ok |
| Environment Matrix Generator | typescript-bun | fable5-medium | 7.9min | 36 | 3 | $5.00 | — | typescript | ok |
| Secret Rotation Validator | bash | fable5-high | 12.5min | 48 | 3 | $5.19 | — | bash | ok |
| Semantic Version Bumper | powershell | fable5-medium | 19.0min | 36 | 4 | $4.65 | — | powershell | ok |
| Environment Matrix Generator | typescript-bun | fable5-high | 15.1min | 55 | 4 | $6.33 | — | typescript | ok |
| Test Results Aggregator | powershell | fable5-medium | 15.2min | 40 | 5 | $5.09 | — | powershell | ok |
| Artifact Cleanup Script | bash | fable5-medium | 7.7min | 31 | 5 | $3.53 | — | bash | ok |
| Secret Rotation Validator | powershell | fable5-medium | 18.0min | 30 | 5 | $5.33 | — | powershell | ok |
| Environment Matrix Generator | powershell | fable5-medium | 12.6min | 34 | 6 | $4.34 | — | powershell | ok |
| Dependency License Checker | powershell | fable5-high | 16.8min | 41 | 6 | $5.67 | — | powershell | ok |
| Test Results Aggregator | powershell | fable5-high | 15.0min | 46 | 6 | $5.05 | — | powershell | ok |
| Secret Rotation Validator | powershell | fable5-high | 17.4min | 37 | 6 | $5.79 | — | powershell | ok |
| Environment Matrix Generator | powershell | fable5-high | 21.5min | 45 | 8 | $7.73 | — | powershell | ok |

</details>

<details>
<summary>Sorted by turns (fewest first)</summary>

| Task | Language | Model | Duration | Turns | Errors | Cost | Tests Quality | Chosen | Status |
|------|----------|-------|----------|-------|--------|------|-----------|--------|--------|
| Dependency License Checker | powershell | fable5-medium | 11.2min | 20 | 2 | $3.23 | — | powershell | ok |
| Dependency License Checker | default | fable5-medium | 6.8min | 29 | 2 | $2.90 | — | python | ok |
| Secret Rotation Validator | powershell | fable5-medium | 18.0min | 30 | 5 | $5.33 | — | powershell | ok |
| Artifact Cleanup Script | bash | fable5-medium | 7.7min | 31 | 5 | $3.53 | — | bash | ok |
| PR Label Assigner | powershell | fable5-medium | 12.0min | 32 | 1 | $3.41 | — | powershell | ok |
| Secret Rotation Validator | default | fable5-medium | 7.3min | 32 | 0 | $3.13 | — | python | ok |
| Test Results Aggregator | bash | fable5-medium | 7.8min | 34 | 3 | $3.46 | — | bash | ok |
| Environment Matrix Generator | powershell | fable5-medium | 12.6min | 34 | 6 | $4.34 | — | powershell | ok |
| Semantic Version Bumper | default | fable5-medium | 9.1min | 35 | 2 | $4.21 | — | javascript | ok |
| PR Label Assigner | default | fable5-medium | 6.8min | 35 | 1 | $3.04 | — | python | ok |
| Semantic Version Bumper | powershell | fable5-medium | 19.0min | 36 | 4 | $4.65 | — | powershell | ok |
| Semantic Version Bumper | typescript-bun | fable5-medium | 8.9min | 36 | 0 | $3.39 | — | typescript | ok |
| Dependency License Checker | bash | fable5-medium | 6.3min | 36 | 1 | $2.95 | — | bash | ok |
| Environment Matrix Generator | typescript-bun | fable5-medium | 7.9min | 36 | 3 | $5.00 | — | typescript | ok |
| Environment Matrix Generator | bash | fable5-medium | 7.5min | 37 | 1 | $3.41 | — | bash | ok |
| Secret Rotation Validator | bash | fable5-medium | 9.4min | 37 | 0 | $3.92 | — | bash | ok |
| Secret Rotation Validator | powershell | fable5-high | 17.4min | 37 | 6 | $5.79 | — | powershell | ok |
| Semantic Version Bumper | bash | fable5-medium | 8.4min | 39 | 1 | $3.99 | — | bash | ok |
| Test Results Aggregator | default | fable5-high | 8.4min | 39 | 0 | $4.18 | — | python | ok |
| Test Results Aggregator | powershell | fable5-medium | 15.2min | 40 | 5 | $5.09 | — | powershell | ok |
| PR Label Assigner | default | fable5-high | 9.0min | 41 | 1 | $3.87 | — | python | ok |
| Dependency License Checker | powershell | fable5-high | 16.8min | 41 | 6 | $5.67 | — | powershell | ok |
| Secret Rotation Validator | typescript-bun | fable5-medium | 12.7min | 42 | 0 | $4.84 | — | typescript | ok |
| PR Label Assigner | powershell | fable5-high | 12.5min | 43 | 1 | $5.49 | — | powershell | ok |
| Environment Matrix Generator | powershell | fable5-high | 21.5min | 45 | 8 | $7.73 | — | powershell | ok |
| Environment Matrix Generator | bash | fable5-high | 11.2min | 45 | 1 | $6.86 | — | bash | ok |
| PR Label Assigner | bash | fable5-medium | 8.6min | 46 | 2 | $4.15 | — | bash | ok |
| PR Label Assigner | typescript-bun | fable5-medium | 11.9min | 46 | 0 | $4.46 | — | typescript | ok |
| Dependency License Checker | typescript-bun | fable5-medium | 9.2min | 46 | 0 | $4.24 | — | typescript | ok |
| Test Results Aggregator | typescript-bun | fable5-medium | 10.7min | 46 | 0 | $4.98 | — | typescript | ok |
| Artifact Cleanup Script | powershell | fable5-medium | 17.1min | 46 | 1 | $6.86 | — | powershell | ok |
| PR Label Assigner | bash | fable5-high | 11.7min | 46 | 2 | $4.85 | — | bash | ok |
| Dependency License Checker | default | fable5-high | 9.6min | 46 | 1 | $4.49 | — | javascript | ok |
| Dependency License Checker | bash | fable5-high | 9.9min | 46 | 0 | $4.58 | — | bash | ok |
| Dependency License Checker | typescript-bun | fable5-high | 11.7min | 46 | 0 | $4.49 | — | typescript | ok |
| Test Results Aggregator | powershell | fable5-high | 15.0min | 46 | 6 | $5.05 | — | powershell | ok |
| Artifact Cleanup Script | powershell | fable5-high | 17.6min | 46 | 0 | $6.49 | — | powershell | ok |
| Test Results Aggregator | default | fable5-medium | 9.8min | 47 | 1 | $5.30 | — | python | ok |
| Environment Matrix Generator | default | fable5-medium | 10.6min | 47 | 2 | $4.57 | — | python | ok |
| Semantic Version Bumper | powershell | fable5-high | 19.3min | 47 | 2 | $5.82 | — | powershell | ok |
| PR Label Assigner | typescript-bun | fable5-high | 9.8min | 47 | 0 | $4.64 | — | typescript | ok |
| Semantic Version Bumper | typescript-bun | fable5-high | 11.2min | 48 | 1 | $6.25 | — | typescript | ok |
| Secret Rotation Validator | bash | fable5-high | 12.5min | 48 | 3 | $5.19 | — | bash | ok |
| Artifact Cleanup Script | bash | fable5-high | 11.8min | 49 | 0 | $5.55 | — | bash | ok |
| Artifact Cleanup Script | typescript-bun | fable5-medium | 14.5min | 51 | 0 | $5.68 | — | typescript | ok |
| Secret Rotation Validator | typescript-bun | fable5-high | 11.5min | 51 | 1 | $5.95 | — | typescript | ok |
| Artifact Cleanup Script | default | fable5-medium | 12.1min | 52 | 0 | $5.22 | — | python | ok |
| Semantic Version Bumper | default | fable5-high | 12.9min | 52 | 1 | $6.53 | — | javascript | ok |
| Test Results Aggregator | bash | fable5-high | 13.7min | 52 | 2 | $6.27 | — | bash | ok |
| Semantic Version Bumper | bash | fable5-high | 12.0min | 55 | 1 | $5.33 | — | bash | ok |
| Test Results Aggregator | typescript-bun | fable5-high | 11.7min | 55 | 2 | $5.91 | — | typescript | ok |
| Environment Matrix Generator | typescript-bun | fable5-high | 15.1min | 55 | 4 | $6.33 | — | typescript | ok |
| Secret Rotation Validator | default | fable5-high | 12.3min | 58 | 1 | $7.27 | — | python | ok |
| Artifact Cleanup Script | typescript-bun | fable5-high | 15.2min | 62 | 1 | $9.45 | — | typescript | ok |
| Environment Matrix Generator | default | fable5-high | 13.5min | 65 | 1 | $6.97 | — | python | ok |
| Artifact Cleanup Script | default | fable5-high | 15.1min | 71 | 0 | $8.50 | — | python | ok |

</details>

<details>
<summary>Sorted by LLM-as-judge score (best first)</summary>

| Task | Language | Model | Duration | Turns | Errors | Cost | Tests Quality | Chosen | Status |
|------|----------|-------|----------|-------|--------|------|-----------|--------|--------|
| Semantic Version Bumper | bash | fable5-medium | 8.4min | 39 | 1 | $3.99 | — | bash | ok |
| Semantic Version Bumper | default | fable5-medium | 9.1min | 35 | 2 | $4.21 | — | javascript | ok |
| Semantic Version Bumper | powershell | fable5-medium | 19.0min | 36 | 4 | $4.65 | — | powershell | ok |
| Semantic Version Bumper | typescript-bun | fable5-medium | 8.9min | 36 | 0 | $3.39 | — | typescript | ok |
| PR Label Assigner | bash | fable5-medium | 8.6min | 46 | 2 | $4.15 | — | bash | ok |
| PR Label Assigner | default | fable5-medium | 6.8min | 35 | 1 | $3.04 | — | python | ok |
| PR Label Assigner | powershell | fable5-medium | 12.0min | 32 | 1 | $3.41 | — | powershell | ok |
| PR Label Assigner | typescript-bun | fable5-medium | 11.9min | 46 | 0 | $4.46 | — | typescript | ok |
| Dependency License Checker | bash | fable5-medium | 6.3min | 36 | 1 | $2.95 | — | bash | ok |
| Dependency License Checker | default | fable5-medium | 6.8min | 29 | 2 | $2.90 | — | python | ok |
| Dependency License Checker | powershell | fable5-medium | 11.2min | 20 | 2 | $3.23 | — | powershell | ok |
| Dependency License Checker | typescript-bun | fable5-medium | 9.2min | 46 | 0 | $4.24 | — | typescript | ok |
| Test Results Aggregator | bash | fable5-medium | 7.8min | 34 | 3 | $3.46 | — | bash | ok |
| Test Results Aggregator | default | fable5-medium | 9.8min | 47 | 1 | $5.30 | — | python | ok |
| Test Results Aggregator | powershell | fable5-medium | 15.2min | 40 | 5 | $5.09 | — | powershell | ok |
| Test Results Aggregator | typescript-bun | fable5-medium | 10.7min | 46 | 0 | $4.98 | — | typescript | ok |
| Environment Matrix Generator | bash | fable5-medium | 7.5min | 37 | 1 | $3.41 | — | bash | ok |
| Environment Matrix Generator | default | fable5-medium | 10.6min | 47 | 2 | $4.57 | — | python | ok |
| Environment Matrix Generator | powershell | fable5-medium | 12.6min | 34 | 6 | $4.34 | — | powershell | ok |
| Environment Matrix Generator | typescript-bun | fable5-medium | 7.9min | 36 | 3 | $5.00 | — | typescript | ok |
| Artifact Cleanup Script | bash | fable5-medium | 7.7min | 31 | 5 | $3.53 | — | bash | ok |
| Artifact Cleanup Script | default | fable5-medium | 12.1min | 52 | 0 | $5.22 | — | python | ok |
| Artifact Cleanup Script | powershell | fable5-medium | 17.1min | 46 | 1 | $6.86 | — | powershell | ok |
| Artifact Cleanup Script | typescript-bun | fable5-medium | 14.5min | 51 | 0 | $5.68 | — | typescript | ok |
| Secret Rotation Validator | bash | fable5-medium | 9.4min | 37 | 0 | $3.92 | — | bash | ok |
| Secret Rotation Validator | default | fable5-medium | 7.3min | 32 | 0 | $3.13 | — | python | ok |
| Secret Rotation Validator | powershell | fable5-medium | 18.0min | 30 | 5 | $5.33 | — | powershell | ok |
| Secret Rotation Validator | typescript-bun | fable5-medium | 12.7min | 42 | 0 | $4.84 | — | typescript | ok |
| Semantic Version Bumper | default | fable5-high | 12.9min | 52 | 1 | $6.53 | — | javascript | ok |
| Semantic Version Bumper | powershell | fable5-high | 19.3min | 47 | 2 | $5.82 | — | powershell | ok |
| Semantic Version Bumper | bash | fable5-high | 12.0min | 55 | 1 | $5.33 | — | bash | ok |
| Semantic Version Bumper | typescript-bun | fable5-high | 11.2min | 48 | 1 | $6.25 | — | typescript | ok |
| PR Label Assigner | default | fable5-high | 9.0min | 41 | 1 | $3.87 | — | python | ok |
| PR Label Assigner | powershell | fable5-high | 12.5min | 43 | 1 | $5.49 | — | powershell | ok |
| PR Label Assigner | bash | fable5-high | 11.7min | 46 | 2 | $4.85 | — | bash | ok |
| PR Label Assigner | typescript-bun | fable5-high | 9.8min | 47 | 0 | $4.64 | — | typescript | ok |
| Dependency License Checker | default | fable5-high | 9.6min | 46 | 1 | $4.49 | — | javascript | ok |
| Dependency License Checker | powershell | fable5-high | 16.8min | 41 | 6 | $5.67 | — | powershell | ok |
| Dependency License Checker | bash | fable5-high | 9.9min | 46 | 0 | $4.58 | — | bash | ok |
| Dependency License Checker | typescript-bun | fable5-high | 11.7min | 46 | 0 | $4.49 | — | typescript | ok |
| Test Results Aggregator | default | fable5-high | 8.4min | 39 | 0 | $4.18 | — | python | ok |
| Test Results Aggregator | powershell | fable5-high | 15.0min | 46 | 6 | $5.05 | — | powershell | ok |
| Test Results Aggregator | bash | fable5-high | 13.7min | 52 | 2 | $6.27 | — | bash | ok |
| Test Results Aggregator | typescript-bun | fable5-high | 11.7min | 55 | 2 | $5.91 | — | typescript | ok |
| Environment Matrix Generator | default | fable5-high | 13.5min | 65 | 1 | $6.97 | — | python | ok |
| Environment Matrix Generator | powershell | fable5-high | 21.5min | 45 | 8 | $7.73 | — | powershell | ok |
| Environment Matrix Generator | bash | fable5-high | 11.2min | 45 | 1 | $6.86 | — | bash | ok |
| Environment Matrix Generator | typescript-bun | fable5-high | 15.1min | 55 | 4 | $6.33 | — | typescript | ok |
| Artifact Cleanup Script | default | fable5-high | 15.1min | 71 | 0 | $8.50 | — | python | ok |
| Artifact Cleanup Script | powershell | fable5-high | 17.6min | 46 | 0 | $6.49 | — | powershell | ok |
| Artifact Cleanup Script | bash | fable5-high | 11.8min | 49 | 0 | $5.55 | — | bash | ok |
| Artifact Cleanup Script | typescript-bun | fable5-high | 15.2min | 62 | 1 | $9.45 | — | typescript | ok |
| Secret Rotation Validator | default | fable5-high | 12.3min | 58 | 1 | $7.27 | — | python | ok |
| Secret Rotation Validator | powershell | fable5-high | 17.4min | 37 | 6 | $5.79 | — | powershell | ok |
| Secret Rotation Validator | bash | fable5-high | 12.5min | 48 | 3 | $5.19 | — | bash | ok |
| Secret Rotation Validator | typescript-bun | fable5-high | 11.5min | 51 | 1 | $5.95 | — | typescript | ok |

</details>

## Notes

### Tiers

- **Duration bands:** **A+** ≤1.07×, **A** ≤1.14×, **A-** ≤1.21×, **B+** ≤1.29×, **B** ≤1.38×, **B-** ≤1.47×, **C+** ≤1.56×, **C** ≤1.67×, **C-** ≤1.78×, **D+** ≤1.90×, **D** ≤2.02×, **D-** ≤2.15×, **F** >2.15×
- **Cost bands:** **A+** ≤1.04×, **A** ≤1.09×, **A-** ≤1.14×, **B+** ≤1.19×, **B** ≤1.25×, **B-** ≤1.30×, **C+** ≤1.36×, **C** ≤1.42×, **C-** ≤1.48×, **D+** ≤1.55×, **D** ≤1.62×, **D-** ≤1.69×, **F** >1.69×

*Tests/Workflow Craft bands are absolute Overall score bands:* **A+** ≥4.7, **A** ≥4.4, **A-** ≥4.1, **B+** ≥3.8, **B** ≥3.5, **B-** ≥3.2, **C+** ≥2.9, **C** ≥2.6, **C-** ≥2.3, **D+** ≥2.0, **D** ≥1.7, **D-** ≥1.4, **F** <1.4, `—` = no data.*

### CLI Version Legend

| Variant label | CLI version | Tasks | Languages |
|---------------|-------------|-------|-----------|
| fable5-high | 2.1.198 | All | All |
| fable5-medium | 2.1.198 | All | All |

---
*Generated by generate_results.py — benchmark instructions v4*