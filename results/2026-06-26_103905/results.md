# Benchmark Results: Language Comparison

**Last updated:** 2026-06-26 11:22:27 PM ET — 27/34 runs completed, 7 remaining; total cost $56.34; total agent time 275.0 min.
**Claude Code versions used:** v2.1.193 (23 runs), v2.1.195 (4 runs). Each link goes to a per-version snapshot of the system prompt, default-tool descriptions, and the chronological Anthropic changelog up to that version. Regenerate with `python3 version_docs.py`.

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

Judges: panel of LLM-as-judge models — `haiku-4-5` (via Claude CLI) and `gemini-3.1-pro-preview` (via Gemini CLI). Each run's quality score is the mean of both judges, cached per-run so numbers are deterministic across regenerations. Known bias caveats live in the [Judge Consistency Summary](#judge-consistency-summary).

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
| default | opus48-1m-medium | A+ (7.7min) | A+ ($1.92) | — | — |
| powershell | opus48-1m-medium | A- (8.3min) | A+ ($1.97) | — | — |
| bash | opus48-1m-medium | C- (10.1min) | A ($2.03) | — | — |
| powershell-tool | opus48-1m-medium | C+ (9.6min) | C ($2.34) | — | — |
| typescript-bun | opus48-1m-medium* | D- (11.2min) | D- ($2.68) | — | — |


<details>
<summary>Sorted by Duration tier (best-first), then avg of Cost/Tests/Workflow Craft tiers</summary>

| Language | Model | Duration | Cost | Tests Quality | Workflow Craft |
|----------|-------|----------|------|-----------|-------------|
| default | opus48-1m-medium | A+ (7.7min) | A+ ($1.92) | — | — |
| powershell | opus48-1m-medium | A- (8.3min) | A+ ($1.97) | — | — |
| powershell-tool | opus48-1m-medium | C+ (9.6min) | C ($2.34) | — | — |
| bash | opus48-1m-medium | C- (10.1min) | A ($2.03) | — | — |
| typescript-bun | opus48-1m-medium* | D- (11.2min) | D- ($2.68) | — | — |

</details>

<details>
<summary>Sorted by Cost tier (best-first), then avg of Duration/Tests/Workflow Craft tiers</summary>

| Language | Model | Duration | Cost | Tests Quality | Workflow Craft |
|----------|-------|----------|------|-----------|-------------|
| default | opus48-1m-medium | A+ (7.7min) | A+ ($1.92) | — | — |
| powershell | opus48-1m-medium | A- (8.3min) | A+ ($1.97) | — | — |
| bash | opus48-1m-medium | C- (10.1min) | A ($2.03) | — | — |
| powershell-tool | opus48-1m-medium | C+ (9.6min) | C ($2.34) | — | — |
| typescript-bun | opus48-1m-medium* | D- (11.2min) | D- ($2.68) | — | — |

</details>

<details>
<summary>Sorted by Tests Quality tier (best-first; no-data last), then avg of other tiers</summary>

| Language | Model | Duration | Cost | Tests Quality | Workflow Craft |
|----------|-------|----------|------|-----------|-------------|
| default | opus48-1m-medium | A+ (7.7min) | A+ ($1.92) | — | — |
| powershell | opus48-1m-medium | A- (8.3min) | A+ ($1.97) | — | — |
| bash | opus48-1m-medium | C- (10.1min) | A ($2.03) | — | — |
| powershell-tool | opus48-1m-medium | C+ (9.6min) | C ($2.34) | — | — |
| typescript-bun | opus48-1m-medium* | D- (11.2min) | D- ($2.68) | — | — |

</details>

<details>
<summary>Sorted by Workflow Craft tier (best-first; no-data last), then avg of other tiers</summary>

| Language | Model | Duration | Cost | Tests Quality | Workflow Craft |
|----------|-------|----------|------|-----------|-------------|
| default | opus48-1m-medium | A+ (7.7min) | A+ ($1.92) | — | — |
| powershell | opus48-1m-medium | A- (8.3min) | A+ ($1.97) | — | — |
| bash | opus48-1m-medium | C- (10.1min) | A ($2.03) | — | — |
| powershell-tool | opus48-1m-medium | C+ (9.6min) | C ($2.34) | — | — |
| typescript-bun | opus48-1m-medium* | D- (11.2min) | D- ($2.68) | — | — |

</details>

- **Estimated time remaining:** 30.6min
- **Estimated total cost:** $70.94

## Failed / Timed-Out Runs

| Task | Language | Model | Duration | Reason | Lines | actionlint | act-result.txt |
|------|------|-------|----------|--------|-------|------------|----------------|
| Environment Matrix Generator | typescript-bun | opus48-1m-medium | 32.5min | timeout | 1006 | pass | yes |

*1 run(s) excluded from averages below.*

## Comparison by Language/Model/Effort
*(averages exclude failed/timed-out runs)*
*See [Notes](#notes) for scoring rubric and CLI version legend.*

| Language | Model | Runs | Avg Duration | Avg Duration Net of Traps | Avg Errors | Avg Turns | Avg Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| bash | opus48-1m-medium | 6 | 10.1min | 10.1min | 0.7 | 30 | $2.03 | $12.20 | — | — |
| default | opus48-1m-medium | 6 | 7.7min | 7.7min | 0.3 | 31 | $1.92 | $11.55 | — | — |
| powershell | opus48-1m-medium | 5 | 8.3min | 7.6min | 0.0 | 31 | $1.97 | $9.84 | — | — |
| powershell-tool | opus48-1m-medium | 4 | 9.6min | 8.2min | 0.5 | 36 | $2.34 | $9.35 | — | — |
| typescript-bun | opus48-1m-medium* | 5 | 11.2min | 11.2min | 0.8 | 46 | $2.68 | $13.41 | — | — |


<details>
<summary>Sorted by avg cost (cheapest first)</summary>

| Language | Model | Runs | Avg Duration | Avg Duration Net of Traps | Avg Errors | Avg Turns | Avg Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| default | opus48-1m-medium | 6 | 7.7min | 7.7min | 0.3 | 31 | $1.92 | $11.55 | — | — |
| powershell | opus48-1m-medium | 5 | 8.3min | 7.6min | 0.0 | 31 | $1.97 | $9.84 | — | — |
| bash | opus48-1m-medium | 6 | 10.1min | 10.1min | 0.7 | 30 | $2.03 | $12.20 | — | — |
| powershell-tool | opus48-1m-medium | 4 | 9.6min | 8.2min | 0.5 | 36 | $2.34 | $9.35 | — | — |
| typescript-bun | opus48-1m-medium* | 5 | 11.2min | 11.2min | 0.8 | 46 | $2.68 | $13.41 | — | — |

</details>

<details>
<summary>Sorted by avg duration (fastest first)</summary>

| Language | Model | Runs | Avg Duration | Avg Duration Net of Traps | Avg Errors | Avg Turns | Avg Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| default | opus48-1m-medium | 6 | 7.7min | 7.7min | 0.3 | 31 | $1.92 | $11.55 | — | — |
| powershell | opus48-1m-medium | 5 | 8.3min | 7.6min | 0.0 | 31 | $1.97 | $9.84 | — | — |
| powershell-tool | opus48-1m-medium | 4 | 9.6min | 8.2min | 0.5 | 36 | $2.34 | $9.35 | — | — |
| bash | opus48-1m-medium | 6 | 10.1min | 10.1min | 0.7 | 30 | $2.03 | $12.20 | — | — |
| typescript-bun | opus48-1m-medium* | 5 | 11.2min | 11.2min | 0.8 | 46 | $2.68 | $13.41 | — | — |

</details>

<details>
<summary>Sorted by avg duration net of traps (fastest first)</summary>

| Language | Model | Runs | Avg Duration | Avg Duration Net of Traps | Avg Errors | Avg Turns | Avg Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| powershell | opus48-1m-medium | 5 | 8.3min | 7.6min | 0.0 | 31 | $1.97 | $9.84 | — | — |
| default | opus48-1m-medium | 6 | 7.7min | 7.7min | 0.3 | 31 | $1.92 | $11.55 | — | — |
| powershell-tool | opus48-1m-medium | 4 | 9.6min | 8.2min | 0.5 | 36 | $2.34 | $9.35 | — | — |
| bash | opus48-1m-medium | 6 | 10.1min | 10.1min | 0.7 | 30 | $2.03 | $12.20 | — | — |
| typescript-bun | opus48-1m-medium* | 5 | 11.2min | 11.2min | 0.8 | 46 | $2.68 | $13.41 | — | — |

</details>

<details>
<summary>Sorted by avg errors (fewest first)</summary>

| Language | Model | Runs | Avg Duration | Avg Duration Net of Traps | Avg Errors | Avg Turns | Avg Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| powershell | opus48-1m-medium | 5 | 8.3min | 7.6min | 0.0 | 31 | $1.97 | $9.84 | — | — |
| default | opus48-1m-medium | 6 | 7.7min | 7.7min | 0.3 | 31 | $1.92 | $11.55 | — | — |
| powershell-tool | opus48-1m-medium | 4 | 9.6min | 8.2min | 0.5 | 36 | $2.34 | $9.35 | — | — |
| bash | opus48-1m-medium | 6 | 10.1min | 10.1min | 0.7 | 30 | $2.03 | $12.20 | — | — |
| typescript-bun | opus48-1m-medium* | 5 | 11.2min | 11.2min | 0.8 | 46 | $2.68 | $13.41 | — | — |

</details>

<details>
<summary>Sorted by avg turns (fewest first)</summary>

| Language | Model | Runs | Avg Duration | Avg Duration Net of Traps | Avg Errors | Avg Turns | Avg Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| bash | opus48-1m-medium | 6 | 10.1min | 10.1min | 0.7 | 30 | $2.03 | $12.20 | — | — |
| powershell | opus48-1m-medium | 5 | 8.3min | 7.6min | 0.0 | 31 | $1.97 | $9.84 | — | — |
| default | opus48-1m-medium | 6 | 7.7min | 7.7min | 0.3 | 31 | $1.92 | $11.55 | — | — |
| powershell-tool | opus48-1m-medium | 4 | 9.6min | 8.2min | 0.5 | 36 | $2.34 | $9.35 | — | — |
| typescript-bun | opus48-1m-medium* | 5 | 11.2min | 11.2min | 0.8 | 46 | $2.68 | $13.41 | — | — |

</details>

<details>
<summary>Sorted by LLM-as-judge score (best first)</summary>

| Language | Model | Runs | Avg Duration | Avg Duration Net of Traps | Avg Errors | Avg Turns | Avg Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| bash | opus48-1m-medium | 6 | 10.1min | 10.1min | 0.7 | 30 | $2.03 | $12.20 | — | — |
| default | opus48-1m-medium | 6 | 7.7min | 7.7min | 0.3 | 31 | $1.92 | $11.55 | — | — |
| powershell | opus48-1m-medium | 5 | 8.3min | 7.6min | 0.0 | 31 | $1.97 | $9.84 | — | — |
| powershell-tool | opus48-1m-medium | 4 | 9.6min | 8.2min | 0.5 | 36 | $2.34 | $9.35 | — | — |
| typescript-bun | opus48-1m-medium* | 5 | 11.2min | 11.2min | 0.8 | 46 | $2.68 | $13.41 | — | — |

</details>

<details>
<summary>Sorted by deliverable-quality score (best first)</summary>

| Language | Model | Runs | Avg Duration | Avg Duration Net of Traps | Avg Errors | Avg Turns | Avg Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| bash | opus48-1m-medium | 6 | 10.1min | 10.1min | 0.7 | 30 | $2.03 | $12.20 | — | — |
| default | opus48-1m-medium | 6 | 7.7min | 7.7min | 0.3 | 31 | $1.92 | $11.55 | — | — |
| powershell | opus48-1m-medium | 5 | 8.3min | 7.6min | 0.0 | 31 | $1.97 | $9.84 | — | — |
| powershell-tool | opus48-1m-medium | 4 | 9.6min | 8.2min | 0.5 | 36 | $2.34 | $9.35 | — | — |
| typescript-bun | opus48-1m-medium* | 5 | 11.2min | 11.2min | 0.8 | 46 | $2.68 | $13.41 | — | — |

</details>

## Savings Analysis

### Hook Savings by Language/Model/Effort

Each hook-caught error avoids one test run that would otherwise have been needed to discover it.
Every hook fire (hit or miss) costs execution time for the syntax/type checker.

*`% of Test Time Saved` = `net / (net + test_time) × 100` — the share of total (would-have-been + actually-spent) test time that hooks eliminated. Bounded in (-∞, 100%) without an artificial cap; near 100% means hooks substituted for almost all of the hypothetical test work.*

| Language | Model | Fires | Caught | Rate | Gross Saved | % of Time | Overhead | % of Time | Net Saved | % of Time | Test Run Time | % of Test Time Saved |
|------|-------|-------|--------|------|------------|-----------|----------|-----------|-----------|-----------|---------------|----------------------|
| bash | opus48-1m-medium-cli2.1.193 | 51 | 1 | 2.0% | 0.2min | 0.1% | 0.0min | 0.0% | 0.2min | 0.1% | 0.7min | 20.5% |
| bash | opus48-1m-medium-cli2.1.195 | 11 | 0 | 0.0% | 0.0min | 0.0% | 0.0min | 0.0% | -0.0min | -0.0% | 15.2min | -0.1% |
| default | opus48-1m-medium-cli2.1.193 | 68 | 0 | 0.0% | 0.0min | 0.0% | 0.2min | 0.1% | -0.2min | -0.1% | 4.0min | -3.9% |
| default | opus48-1m-medium-cli2.1.195 | 17 | 0 | 0.0% | 0.0min | 0.0% | 0.0min | 0.0% | -0.0min | -0.0% | 1.0min | -4.0% |
| powershell | opus48-1m-medium-cli2.1.193 | 70 | 0 | 0.0% | 0.0min | 0.0% | 0.7min | 0.3% | -0.7min | -0.3% | 4.3min | -19.8% |
| powershell-tool | opus48-1m-medium-cli2.1.193 | 62 | 0 | 0.0% | 0.0min | 0.0% | 0.3min | 0.1% | -0.3min | -0.1% | 3.6min | -8.2% |
| typescript-bun | opus48-1m-medium-cli2.1.193 | 95 | 40 | 42.1% | 5.3min | 1.9% | 1.4min | 0.5% | 3.9min | 1.4% | 4.0min | 49.5% |
| typescript-bun | opus48-1m-medium-cli2.1.195 | 23 | 0 | 0.0% | 0.0min | 0.0% | 1.3min | 0.5% | -1.3min | -0.5% | 5.5min | -30.7% |


<details>
<summary>Sorted by net saved (most first)</summary>

| Language | Model | Fires | Caught | Rate | Gross Saved | % of Time | Overhead | % of Time | Net Saved | % of Time | Test Run Time | % of Test Time Saved |
|------|-------|-------|--------|------|------------|-----------|----------|-----------|-----------|-----------|---------------|----------------------|
| typescript-bun | opus48-1m-medium-cli2.1.193 | 95 | 40 | 42.1% | 5.3min | 1.9% | 1.4min | 0.5% | 3.9min | 1.4% | 4.0min | 49.5% |
| bash | opus48-1m-medium-cli2.1.193 | 51 | 1 | 2.0% | 0.2min | 0.1% | 0.0min | 0.0% | 0.2min | 0.1% | 0.7min | 20.5% |
| bash | opus48-1m-medium-cli2.1.195 | 11 | 0 | 0.0% | 0.0min | 0.0% | 0.0min | 0.0% | -0.0min | -0.0% | 15.2min | -0.1% |
| default | opus48-1m-medium-cli2.1.195 | 17 | 0 | 0.0% | 0.0min | 0.0% | 0.0min | 0.0% | -0.0min | -0.0% | 1.0min | -4.0% |
| default | opus48-1m-medium-cli2.1.193 | 68 | 0 | 0.0% | 0.0min | 0.0% | 0.2min | 0.1% | -0.2min | -0.1% | 4.0min | -3.9% |
| powershell-tool | opus48-1m-medium-cli2.1.193 | 62 | 0 | 0.0% | 0.0min | 0.0% | 0.3min | 0.1% | -0.3min | -0.1% | 3.6min | -8.2% |
| powershell | opus48-1m-medium-cli2.1.193 | 70 | 0 | 0.0% | 0.0min | 0.0% | 0.7min | 0.3% | -0.7min | -0.3% | 4.3min | -19.8% |
| typescript-bun | opus48-1m-medium-cli2.1.195 | 23 | 0 | 0.0% | 0.0min | 0.0% | 1.3min | 0.5% | -1.3min | -0.5% | 5.5min | -30.7% |

</details>

<details>
<summary>Sorted by net % of test time saved (most first)</summary>

| Language | Model | Fires | Caught | Rate | Gross Saved | % of Time | Overhead | % of Time | Net Saved | % of Time | Test Run Time | % of Test Time Saved |
|------|-------|-------|--------|------|------------|-----------|----------|-----------|-----------|-----------|---------------|----------------------|
| typescript-bun | opus48-1m-medium-cli2.1.193 | 95 | 40 | 42.1% | 5.3min | 1.9% | 1.4min | 0.5% | 3.9min | 1.4% | 4.0min | 49.5% |
| bash | opus48-1m-medium-cli2.1.193 | 51 | 1 | 2.0% | 0.2min | 0.1% | 0.0min | 0.0% | 0.2min | 0.1% | 0.7min | 20.5% |
| bash | opus48-1m-medium-cli2.1.195 | 11 | 0 | 0.0% | 0.0min | 0.0% | 0.0min | 0.0% | -0.0min | -0.0% | 15.2min | -0.1% |
| default | opus48-1m-medium-cli2.1.193 | 68 | 0 | 0.0% | 0.0min | 0.0% | 0.2min | 0.1% | -0.2min | -0.1% | 4.0min | -3.9% |
| default | opus48-1m-medium-cli2.1.195 | 17 | 0 | 0.0% | 0.0min | 0.0% | 0.0min | 0.0% | -0.0min | -0.0% | 1.0min | -4.0% |
| powershell-tool | opus48-1m-medium-cli2.1.193 | 62 | 0 | 0.0% | 0.0min | 0.0% | 0.3min | 0.1% | -0.3min | -0.1% | 3.6min | -8.2% |
| powershell | opus48-1m-medium-cli2.1.193 | 70 | 0 | 0.0% | 0.0min | 0.0% | 0.7min | 0.3% | -0.7min | -0.3% | 4.3min | -19.8% |
| typescript-bun | opus48-1m-medium-cli2.1.195 | 23 | 0 | 0.0% | 0.0min | 0.0% | 1.3min | 0.5% | -1.3min | -0.5% | 5.5min | -30.7% |

</details>

<details>
<summary>Sorted by catch rate (highest first)</summary>

| Language | Model | Fires | Caught | Rate | Gross Saved | % of Time | Overhead | % of Time | Net Saved | % of Time | Test Run Time | % of Test Time Saved |
|------|-------|-------|--------|------|------------|-----------|----------|-----------|-----------|-----------|---------------|----------------------|
| typescript-bun | opus48-1m-medium-cli2.1.193 | 95 | 40 | 42.1% | 5.3min | 1.9% | 1.4min | 0.5% | 3.9min | 1.4% | 4.0min | 49.5% |
| bash | opus48-1m-medium-cli2.1.193 | 51 | 1 | 2.0% | 0.2min | 0.1% | 0.0min | 0.0% | 0.2min | 0.1% | 0.7min | 20.5% |
| bash | opus48-1m-medium-cli2.1.195 | 11 | 0 | 0.0% | 0.0min | 0.0% | 0.0min | 0.0% | -0.0min | -0.0% | 15.2min | -0.1% |
| default | opus48-1m-medium-cli2.1.193 | 68 | 0 | 0.0% | 0.0min | 0.0% | 0.2min | 0.1% | -0.2min | -0.1% | 4.0min | -3.9% |
| default | opus48-1m-medium-cli2.1.195 | 17 | 0 | 0.0% | 0.0min | 0.0% | 0.0min | 0.0% | -0.0min | -0.0% | 1.0min | -4.0% |
| powershell | opus48-1m-medium-cli2.1.193 | 70 | 0 | 0.0% | 0.0min | 0.0% | 0.7min | 0.3% | -0.7min | -0.3% | 4.3min | -19.8% |
| powershell-tool | opus48-1m-medium-cli2.1.193 | 62 | 0 | 0.0% | 0.0min | 0.0% | 0.3min | 0.1% | -0.3min | -0.1% | 3.6min | -8.2% |
| typescript-bun | opus48-1m-medium-cli2.1.195 | 23 | 0 | 0.0% | 0.0min | 0.0% | 1.3min | 0.5% | -1.3min | -0.5% | 5.5min | -30.7% |

</details>

### Trap Analysis by Language/Model/Effort/Category

| Trap | Language | Model | Fell In | Time Lost | % of Time | $ Lost | % of $ |
|------|------|-------|---------|-----------|-----------|--------|--------|
| repeated-test-reruns | bash | opus48-1m-medium-cli2.1.193 | 3 | 4.0min | 1.5% | $1.08 | 1.91% |
| repeated-test-reruns | bash | opus48-1m-medium-cli2.1.195 | 1 | 5.3min | 1.9% | $0.76 | 1.35% |
| repeated-test-reruns | default | opus48-1m-medium-cli2.1.193 | 4 | 5.7min | 2.1% | $1.34 | 2.38% |
| repeated-test-reruns | default | opus48-1m-medium-cli2.1.195 | 1 | 0.7min | 0.2% | $0.16 | 0.28% |
| repeated-test-reruns | powershell | opus48-1m-medium-cli2.1.193 | 2 | 2.7min | 1.0% | $0.66 | 1.18% |
| repeated-test-reruns | powershell-tool | opus48-1m-medium-cli2.1.193 | 2 | 3.3min | 1.2% | $0.78 | 1.38% |
| repeated-test-reruns | typescript-bun | opus48-1m-medium-cli2.1.193 | 4 | 8.7min | 3.2% | $2.26 | 4.01% |
| repeated-test-reruns | typescript-bun | opus48-1m-medium-cli2.1.195 | 2 | 1.7min | 0.6% | $0.15 | 0.27% |
| ts-type-error-fix-cycles | typescript-bun | opus48-1m-medium-cli2.1.193 | 3 | 8.0min | 2.9% | $2.17 | 3.85% |
| fixture-rework | bash | opus48-1m-medium-cli2.1.193 | 2 | 1.5min | 0.5% | $0.41 | 0.73% |
| fixture-rework | bash | opus48-1m-medium-cli2.1.195 | 1 | 0.8min | 0.3% | $0.11 | 0.19% |
| fixture-rework | default | opus48-1m-medium-cli2.1.193 | 1 | 0.8min | 0.3% | $0.22 | 0.40% |
| fixture-rework | powershell | opus48-1m-medium-cli2.1.193 | 1 | 0.5min | 0.2% | $0.12 | 0.21% |
| fixture-rework | powershell-tool | opus48-1m-medium-cli2.1.193 | 1 | 1.0min | 0.4% | $0.27 | 0.47% |
| actionlint-fix-cycles | powershell-tool | opus48-1m-medium-cli2.1.193 | 1 | 1.0min | 0.4% | $0.27 | 0.47% |
| act-push-debug-loops | bash | opus48-1m-medium-cli2.1.195 | 1 | 0.8min | 0.3% | $0.12 | 0.21% |


<details>
<summary>Sorted by time lost (least first)</summary>

| Trap | Language | Model | Fell In | Time Lost | % of Time | $ Lost | % of $ |
|------|------|-------|---------|-----------|-----------|--------|--------|
| fixture-rework | powershell | opus48-1m-medium-cli2.1.193 | 1 | 0.5min | 0.2% | $0.12 | 0.21% |
| repeated-test-reruns | default | opus48-1m-medium-cli2.1.195 | 1 | 0.7min | 0.2% | $0.16 | 0.28% |
| fixture-rework | bash | opus48-1m-medium-cli2.1.195 | 1 | 0.8min | 0.3% | $0.11 | 0.19% |
| fixture-rework | default | opus48-1m-medium-cli2.1.193 | 1 | 0.8min | 0.3% | $0.22 | 0.40% |
| act-push-debug-loops | bash | opus48-1m-medium-cli2.1.195 | 1 | 0.8min | 0.3% | $0.12 | 0.21% |
| fixture-rework | powershell-tool | opus48-1m-medium-cli2.1.193 | 1 | 1.0min | 0.4% | $0.27 | 0.47% |
| actionlint-fix-cycles | powershell-tool | opus48-1m-medium-cli2.1.193 | 1 | 1.0min | 0.4% | $0.27 | 0.47% |
| fixture-rework | bash | opus48-1m-medium-cli2.1.193 | 2 | 1.5min | 0.5% | $0.41 | 0.73% |
| repeated-test-reruns | typescript-bun | opus48-1m-medium-cli2.1.195 | 2 | 1.7min | 0.6% | $0.15 | 0.27% |
| repeated-test-reruns | powershell | opus48-1m-medium-cli2.1.193 | 2 | 2.7min | 1.0% | $0.66 | 1.18% |
| repeated-test-reruns | powershell-tool | opus48-1m-medium-cli2.1.193 | 2 | 3.3min | 1.2% | $0.78 | 1.38% |
| repeated-test-reruns | bash | opus48-1m-medium-cli2.1.193 | 3 | 4.0min | 1.5% | $1.08 | 1.91% |
| repeated-test-reruns | bash | opus48-1m-medium-cli2.1.195 | 1 | 5.3min | 1.9% | $0.76 | 1.35% |
| repeated-test-reruns | default | opus48-1m-medium-cli2.1.193 | 4 | 5.7min | 2.1% | $1.34 | 2.38% |
| ts-type-error-fix-cycles | typescript-bun | opus48-1m-medium-cli2.1.193 | 3 | 8.0min | 2.9% | $2.17 | 3.85% |
| repeated-test-reruns | typescript-bun | opus48-1m-medium-cli2.1.193 | 4 | 8.7min | 3.2% | $2.26 | 4.01% |

</details>

<details>
<summary>Sorted by $ lost (least first)</summary>

| Trap | Language | Model | Fell In | Time Lost | % of Time | $ Lost | % of $ |
|------|------|-------|---------|-----------|-----------|--------|--------|
| fixture-rework | bash | opus48-1m-medium-cli2.1.195 | 1 | 0.8min | 0.3% | $0.11 | 0.19% |
| fixture-rework | powershell | opus48-1m-medium-cli2.1.193 | 1 | 0.5min | 0.2% | $0.12 | 0.21% |
| act-push-debug-loops | bash | opus48-1m-medium-cli2.1.195 | 1 | 0.8min | 0.3% | $0.12 | 0.21% |
| repeated-test-reruns | typescript-bun | opus48-1m-medium-cli2.1.195 | 2 | 1.7min | 0.6% | $0.15 | 0.27% |
| repeated-test-reruns | default | opus48-1m-medium-cli2.1.195 | 1 | 0.7min | 0.2% | $0.16 | 0.28% |
| fixture-rework | default | opus48-1m-medium-cli2.1.193 | 1 | 0.8min | 0.3% | $0.22 | 0.40% |
| fixture-rework | powershell-tool | opus48-1m-medium-cli2.1.193 | 1 | 1.0min | 0.4% | $0.27 | 0.47% |
| actionlint-fix-cycles | powershell-tool | opus48-1m-medium-cli2.1.193 | 1 | 1.0min | 0.4% | $0.27 | 0.47% |
| fixture-rework | bash | opus48-1m-medium-cli2.1.193 | 2 | 1.5min | 0.5% | $0.41 | 0.73% |
| repeated-test-reruns | powershell | opus48-1m-medium-cli2.1.193 | 2 | 2.7min | 1.0% | $0.66 | 1.18% |
| repeated-test-reruns | bash | opus48-1m-medium-cli2.1.195 | 1 | 5.3min | 1.9% | $0.76 | 1.35% |
| repeated-test-reruns | powershell-tool | opus48-1m-medium-cli2.1.193 | 2 | 3.3min | 1.2% | $0.78 | 1.38% |
| repeated-test-reruns | bash | opus48-1m-medium-cli2.1.193 | 3 | 4.0min | 1.5% | $1.08 | 1.91% |
| repeated-test-reruns | default | opus48-1m-medium-cli2.1.193 | 4 | 5.7min | 2.1% | $1.34 | 2.38% |
| ts-type-error-fix-cycles | typescript-bun | opus48-1m-medium-cli2.1.193 | 3 | 8.0min | 2.9% | $2.17 | 3.85% |
| repeated-test-reruns | typescript-bun | opus48-1m-medium-cli2.1.193 | 4 | 8.7min | 3.2% | $2.26 | 4.01% |

</details>

<details>
<summary>Sorted by fell-in count (fewest first)</summary>

| Trap | Language | Model | Fell In | Time Lost | % of Time | $ Lost | % of $ |
|------|------|-------|---------|-----------|-----------|--------|--------|
| repeated-test-reruns | bash | opus48-1m-medium-cli2.1.195 | 1 | 5.3min | 1.9% | $0.76 | 1.35% |
| repeated-test-reruns | default | opus48-1m-medium-cli2.1.195 | 1 | 0.7min | 0.2% | $0.16 | 0.28% |
| fixture-rework | bash | opus48-1m-medium-cli2.1.195 | 1 | 0.8min | 0.3% | $0.11 | 0.19% |
| fixture-rework | default | opus48-1m-medium-cli2.1.193 | 1 | 0.8min | 0.3% | $0.22 | 0.40% |
| fixture-rework | powershell | opus48-1m-medium-cli2.1.193 | 1 | 0.5min | 0.2% | $0.12 | 0.21% |
| fixture-rework | powershell-tool | opus48-1m-medium-cli2.1.193 | 1 | 1.0min | 0.4% | $0.27 | 0.47% |
| actionlint-fix-cycles | powershell-tool | opus48-1m-medium-cli2.1.193 | 1 | 1.0min | 0.4% | $0.27 | 0.47% |
| act-push-debug-loops | bash | opus48-1m-medium-cli2.1.195 | 1 | 0.8min | 0.3% | $0.12 | 0.21% |
| repeated-test-reruns | powershell | opus48-1m-medium-cli2.1.193 | 2 | 2.7min | 1.0% | $0.66 | 1.18% |
| repeated-test-reruns | powershell-tool | opus48-1m-medium-cli2.1.193 | 2 | 3.3min | 1.2% | $0.78 | 1.38% |
| repeated-test-reruns | typescript-bun | opus48-1m-medium-cli2.1.195 | 2 | 1.7min | 0.6% | $0.15 | 0.27% |
| fixture-rework | bash | opus48-1m-medium-cli2.1.193 | 2 | 1.5min | 0.5% | $0.41 | 0.73% |
| repeated-test-reruns | bash | opus48-1m-medium-cli2.1.193 | 3 | 4.0min | 1.5% | $1.08 | 1.91% |
| ts-type-error-fix-cycles | typescript-bun | opus48-1m-medium-cli2.1.193 | 3 | 8.0min | 2.9% | $2.17 | 3.85% |
| repeated-test-reruns | default | opus48-1m-medium-cli2.1.193 | 4 | 5.7min | 2.1% | $1.34 | 2.38% |
| repeated-test-reruns | typescript-bun | opus48-1m-medium-cli2.1.193 | 4 | 8.7min | 3.2% | $2.26 | 4.01% |

</details>

#### Trap Descriptions

- **act-push-debug-loops**: Agent ran `act push` more than twice, indicating repeated workflow debugging.
- **actionlint-fix-cycles**: Workflow YAML required 3+ actionlint runs and 2+ fixes to pass.
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
| bash | opus48-1m-medium-cli2.1.193 | 5 | 5 | 5.5min | 2.0% | $1.49 | 2.64% |
| bash | opus48-1m-medium-cli2.1.195 | 1 | 3 | 6.9min | 2.5% | $0.98 | 1.75% |
| default | opus48-1m-medium-cli2.1.193 | 5 | 5 | 6.4min | 2.3% | $1.57 | 2.78% |
| default | opus48-1m-medium-cli2.1.195 | 1 | 1 | 0.7min | 0.2% | $0.16 | 0.28% |
| powershell | opus48-1m-medium-cli2.1.193 | 5 | 3 | 3.2min | 1.2% | $0.78 | 1.39% |
| powershell-tool | opus48-1m-medium-cli2.1.193 | 4 | 4 | 5.3min | 1.9% | $1.31 | 2.32% |
| typescript-bun | opus48-1m-medium-cli2.1.193 | 4 | 7 | 16.7min | 6.1% | $4.43 | 7.86% |
| typescript-bun | opus48-1m-medium-cli2.1.195 | 2 | 2 | 1.7min | 0.6% | $0.15 | 0.27% |


<details>
<summary>Sorted by time lost (least first)</summary>

| Language | Model | Runs | Traps | Time Lost | % of Time | $ Lost | % of $ |
|------|-------|------|-------|-----------|-----------|--------|--------|
| default | opus48-1m-medium-cli2.1.195 | 1 | 1 | 0.7min | 0.2% | $0.16 | 0.28% |
| typescript-bun | opus48-1m-medium-cli2.1.195 | 2 | 2 | 1.7min | 0.6% | $0.15 | 0.27% |
| powershell | opus48-1m-medium-cli2.1.193 | 5 | 3 | 3.2min | 1.2% | $0.78 | 1.39% |
| powershell-tool | opus48-1m-medium-cli2.1.193 | 4 | 4 | 5.3min | 1.9% | $1.31 | 2.32% |
| bash | opus48-1m-medium-cli2.1.193 | 5 | 5 | 5.5min | 2.0% | $1.49 | 2.64% |
| default | opus48-1m-medium-cli2.1.193 | 5 | 5 | 6.4min | 2.3% | $1.57 | 2.78% |
| bash | opus48-1m-medium-cli2.1.195 | 1 | 3 | 6.9min | 2.5% | $0.98 | 1.75% |
| typescript-bun | opus48-1m-medium-cli2.1.193 | 4 | 7 | 16.7min | 6.1% | $4.43 | 7.86% |

</details>

<details>
<summary>Sorted by $ lost (least first)</summary>

| Language | Model | Runs | Traps | Time Lost | % of Time | $ Lost | % of $ |
|------|-------|------|-------|-----------|-----------|--------|--------|
| typescript-bun | opus48-1m-medium-cli2.1.195 | 2 | 2 | 1.7min | 0.6% | $0.15 | 0.27% |
| default | opus48-1m-medium-cli2.1.195 | 1 | 1 | 0.7min | 0.2% | $0.16 | 0.28% |
| powershell | opus48-1m-medium-cli2.1.193 | 5 | 3 | 3.2min | 1.2% | $0.78 | 1.39% |
| bash | opus48-1m-medium-cli2.1.195 | 1 | 3 | 6.9min | 2.5% | $0.98 | 1.75% |
| powershell-tool | opus48-1m-medium-cli2.1.193 | 4 | 4 | 5.3min | 1.9% | $1.31 | 2.32% |
| bash | opus48-1m-medium-cli2.1.193 | 5 | 5 | 5.5min | 2.0% | $1.49 | 2.64% |
| default | opus48-1m-medium-cli2.1.193 | 5 | 5 | 6.4min | 2.3% | $1.57 | 2.78% |
| typescript-bun | opus48-1m-medium-cli2.1.193 | 4 | 7 | 16.7min | 6.1% | $4.43 | 7.86% |

</details>

### Prompt Cache Savings

| Status | Runs | $ Saved | % of $ |
|--------|------|---------|--------|
| Full hit (100%) | 1 | $0.12 | 0.22% |
| Partial | 25 | $2.51 | 4.46% |
| Miss | 1 | $0.00 | 0.00% |

## Test Quality Evaluation

### Structural Metrics by Language/Model/Effort

Automated analysis of test files: test count, assertion count, and test-to-code line ratio.

| Language | Model | Avg Tests | Avg Assertions | Avg Assert/Test | Avg Test:Code Ratio |
|------|-------|-----------|----------------|-----------------|---------------------|
| bash | opus48-1m-medium | 22.2 | 37.0 | 1.7 | 1.24 |
| default | opus48-1m-medium | 27.8 | 50.8 | 1.8 | 1.06 |
| powershell | opus48-1m-medium | 33.0 | 57.6 | 1.7 | 3.04 |
| powershell-tool | opus48-1m-medium | 31.0 | 53.5 | 1.7 | 2.75 |
| typescript-bun | opus48-1m-medium | 29.7 | 62.0 | 2.1 | 1.03 |


<details>
<summary>Sorted by avg tests (most first)</summary>

| Language | Model | Avg Tests | Avg Assertions | Avg Assert/Test | Avg Test:Code Ratio |
|------|-------|-----------|----------------|-----------------|---------------------|
| powershell | opus48-1m-medium | 33.0 | 57.6 | 1.7 | 3.04 |
| powershell-tool | opus48-1m-medium | 31.0 | 53.5 | 1.7 | 2.75 |
| typescript-bun | opus48-1m-medium | 29.7 | 62.0 | 2.1 | 1.03 |
| default | opus48-1m-medium | 27.8 | 50.8 | 1.8 | 1.06 |
| bash | opus48-1m-medium | 22.2 | 37.0 | 1.7 | 1.24 |

</details>

<details>
<summary>Sorted by avg assertions (most first)</summary>

| Language | Model | Avg Tests | Avg Assertions | Avg Assert/Test | Avg Test:Code Ratio |
|------|-------|-----------|----------------|-----------------|---------------------|
| typescript-bun | opus48-1m-medium | 29.7 | 62.0 | 2.1 | 1.03 |
| powershell | opus48-1m-medium | 33.0 | 57.6 | 1.7 | 3.04 |
| powershell-tool | opus48-1m-medium | 31.0 | 53.5 | 1.7 | 2.75 |
| default | opus48-1m-medium | 27.8 | 50.8 | 1.8 | 1.06 |
| bash | opus48-1m-medium | 22.2 | 37.0 | 1.7 | 1.24 |

</details>

<details>
<summary>Sorted by avg test:code ratio (highest first)</summary>

| Language | Model | Avg Tests | Avg Assertions | Avg Assert/Test | Avg Test:Code Ratio |
|------|-------|-----------|----------------|-----------------|---------------------|
| powershell | opus48-1m-medium | 33.0 | 57.6 | 1.7 | 3.04 |
| powershell-tool | opus48-1m-medium | 31.0 | 53.5 | 1.7 | 2.75 |
| bash | opus48-1m-medium | 22.2 | 37.0 | 1.7 | 1.24 |
| default | opus48-1m-medium | 27.8 | 50.8 | 1.8 | 1.06 |
| typescript-bun | opus48-1m-medium | 29.7 | 62.0 | 2.1 | 1.03 |

</details>


<details>
<summary>Per-run structural metrics</summary>

| Task | Language | Model | Tests | Assertions | Assert/Test | Test Lines | Impl Lines | Test:Code |
|------|------|-------|-------|------------|-------------|------------|------------|-----------|
| Semantic Version Bumper | bash | opus48-1m-medium | 24 | 34 | 1.4 | 286 | 275 | 1.04 |
| Semantic Version Bumper | default | opus48-1m-medium | 38 | 61 | 1.6 | 498 | 312 | 1.60 |
| Semantic Version Bumper | powershell | opus48-1m-medium | 39 | 62 | 1.6 | 359 | 53 | 6.77 |
| Semantic Version Bumper | powershell-tool | opus48-1m-medium | 35 | 57 | 1.6 | 380 | 118 | 3.22 |
| Semantic Version Bumper | typescript-bun | opus48-1m-medium | 38 | 76 | 2.0 | 462 | 558 | 0.83 |
| PR Label Assigner | bash | opus48-1m-medium | 18 | 10 | 0.6 | 171 | 198 | 0.86 |
| PR Label Assigner | default | opus48-1m-medium | 30 | 36 | 1.2 | 222 | 407 | 0.55 |
| PR Label Assigner | powershell | opus48-1m-medium | 32 | 47 | 1.5 | 261 | 393 | 0.66 |
| PR Label Assigner | powershell-tool | opus48-1m-medium | 26 | 46 | 1.8 | 210 | 253 | 0.83 |
| PR Label Assigner | typescript-bun | opus48-1m-medium | 25 | 53 | 2.1 | 362 | 372 | 0.97 |
| Dependency License Checker | bash | opus48-1m-medium | 24 | 52 | 2.2 | 334 | 191 | 1.75 |
| Dependency License Checker | default | opus48-1m-medium | 19 | 37 | 1.9 | 212 | 433 | 0.49 |
| Dependency License Checker | powershell | opus48-1m-medium | 34 | 56 | 1.6 | 386 | 68 | 5.68 |
| Dependency License Checker | powershell-tool | opus48-1m-medium | 32 | 53 | 1.7 | 388 | 60 | 6.47 |
| Dependency License Checker | typescript-bun | opus48-1m-medium | 32 | 76 | 2.4 | 548 | 358 | 1.53 |
| Test Results Aggregator | bash | opus48-1m-medium | 25 | 26 | 1.0 | 221 | 291 | 0.76 |
| Test Results Aggregator | default | opus48-1m-medium | 23 | 63 | 2.7 | 493 | 263 | 1.87 |
| Test Results Aggregator | powershell | opus48-1m-medium | 29 | 52 | 1.8 | 250 | 253 | 0.99 |
| Test Results Aggregator | powershell-tool | opus48-1m-medium | 31 | 58 | 1.9 | 269 | 568 | 0.47 |
| Test Results Aggregator | typescript-bun | opus48-1m-medium | 34 | 57 | 1.7 | 408 | 707 | 0.58 |
| Environment Matrix Generator | bash | opus48-1m-medium | 22 | 34 | 1.5 | 278 | 132 | 2.11 |
| Environment Matrix Generator | default | opus48-1m-medium | 26 | 50 | 1.9 | 350 | 356 | 0.98 |
| Environment Matrix Generator | powershell | opus48-1m-medium | 31 | 71 | 2.3 | 419 | 389 | 1.08 |
| Environment Matrix Generator | typescript-bun | opus48-1m-medium | 26 | 43 | 1.7 | 313 | 482 | 0.65 |
| Artifact Cleanup Script | bash | opus48-1m-medium | 20 | 66 | 3.3 | 357 | 384 | 0.93 |
| Artifact Cleanup Script | typescript-bun | opus48-1m-medium | 23 | 67 | 2.9 | 507 | 308 | 1.65 |
| Secret Rotation Validator | default | opus48-1m-medium | 31 | 58 | 1.9 | 250 | 291 | 0.86 |

</details>

## Per-Run Results

*Tests Quality = Overall (1-5) from LLM-as-judge of generated test code (dimensions: coverage, rigor, design). `—` = no judge data.*

| Task | Language | Model | Duration | Turns | Errors | Cost | Tests Quality | Chosen | Status |
|------|----------|-------|----------|-------|--------|------|-----------|--------|--------|
| Artifact Cleanup Script | bash | opus48-1m-medium | 31.2min | 57 | 3 | $4.44 | — | bash | ok |
| Artifact Cleanup Script | typescript-bun | opus48-1m-medium | 15.6min | 48 | 2 | $3.55 | — | typescript | ok |
| Dependency License Checker | bash | opus48-1m-medium | 5.7min | 24 | 0 | $1.45 | — | bash | ok |
| Dependency License Checker | default | opus48-1m-medium | 7.9min | 33 | 0 | $1.94 | — | python | ok |
| Dependency License Checker | powershell | opus48-1m-medium | 7.7min | 33 | 0 | $1.93 | — | powershell | ok |
| Dependency License Checker | powershell-tool | opus48-1m-medium | 12.7min | 49 | 0 | $3.35 | — | powershell | ok |
| Dependency License Checker | typescript-bun | opus48-1m-medium | 8.7min | 45 | 0 | $2.33 | — | typescript | ok |
| Environment Matrix Generator | bash | opus48-1m-medium | 5.8min | 27 | 0 | $1.72 | — | bash | ok |
| Environment Matrix Generator | default | opus48-1m-medium | 6.7min | 28 | 0 | $2.01 | — | python | ok |
| Environment Matrix Generator | powershell | opus48-1m-medium | 9.3min | 33 | 0 | $2.29 | — | powershell | ok |
| Environment Matrix Generator | typescript-bun | opus48-1m-medium | 32.5min | 0 | 3 | $0.00 | — | typescript | timeout |
| PR Label Assigner | bash | opus48-1m-medium | 4.8min | 20 | 0 | $1.22 | — | bash | ok |
| PR Label Assigner | default | opus48-1m-medium | 8.2min | 36 | 1 | $1.91 | — | powershell | ok |
| PR Label Assigner | powershell | opus48-1m-medium | 6.3min | 23 | 0 | $1.52 | — | powershell | ok |
| PR Label Assigner | powershell-tool | opus48-1m-medium | 7.6min | 27 | 1 | $1.66 | — | powershell | ok |
| PR Label Assigner | typescript-bun | opus48-1m-medium | 13.1min | 44 | 0 | $2.48 | — | typescript | ok |
| Secret Rotation Validator | default | opus48-1m-medium | 9.8min | 38 | 1 | $2.36 | — | powershell | ok |
| Semantic Version Bumper | bash | opus48-1m-medium | 6.8min | 22 | 0 | $1.55 | — | bash | ok |
| Semantic Version Bumper | default | opus48-1m-medium | 7.2min | 27 | 0 | $1.83 | — | python | ok |
| Semantic Version Bumper | powershell | opus48-1m-medium | 10.0min | 34 | 0 | $2.33 | — | powershell | ok |
| Semantic Version Bumper | powershell-tool | opus48-1m-medium | 10.6min | 40 | 1 | $2.39 | — | powershell | ok |
| Semantic Version Bumper | typescript-bun | opus48-1m-medium | 9.3min | 47 | 2 | $2.47 | — | typescript | ok |
| Test Results Aggregator | bash | opus48-1m-medium | 6.3min | 29 | 1 | $1.83 | — | bash | ok |
| Test Results Aggregator | default | opus48-1m-medium | 6.6min | 26 | 0 | $1.50 | — | python | ok |
| Test Results Aggregator | powershell | opus48-1m-medium | 8.1min | 30 | 0 | $1.77 | — | powershell | ok |
| Test Results Aggregator | powershell-tool | opus48-1m-medium | 7.4min | 29 | 0 | $1.95 | — | powershell | ok |
| Test Results Aggregator | typescript-bun | opus48-1m-medium | 9.2min | 45 | 0 | $2.57 | — | typescript | ok |


<details>
<summary>Sorted by cost (cheapest first)</summary>

| Task | Language | Model | Duration | Turns | Errors | Cost | Tests Quality | Chosen | Status |
|------|----------|-------|----------|-------|--------|------|-----------|--------|--------|
| Environment Matrix Generator | typescript-bun | opus48-1m-medium | 32.5min | 0 | 3 | $0.00 | — | typescript | timeout |
| PR Label Assigner | bash | opus48-1m-medium | 4.8min | 20 | 0 | $1.22 | — | bash | ok |
| Dependency License Checker | bash | opus48-1m-medium | 5.7min | 24 | 0 | $1.45 | — | bash | ok |
| Test Results Aggregator | default | opus48-1m-medium | 6.6min | 26 | 0 | $1.50 | — | python | ok |
| PR Label Assigner | powershell | opus48-1m-medium | 6.3min | 23 | 0 | $1.52 | — | powershell | ok |
| Semantic Version Bumper | bash | opus48-1m-medium | 6.8min | 22 | 0 | $1.55 | — | bash | ok |
| PR Label Assigner | powershell-tool | opus48-1m-medium | 7.6min | 27 | 1 | $1.66 | — | powershell | ok |
| Environment Matrix Generator | bash | opus48-1m-medium | 5.8min | 27 | 0 | $1.72 | — | bash | ok |
| Test Results Aggregator | powershell | opus48-1m-medium | 8.1min | 30 | 0 | $1.77 | — | powershell | ok |
| Semantic Version Bumper | default | opus48-1m-medium | 7.2min | 27 | 0 | $1.83 | — | python | ok |
| Test Results Aggregator | bash | opus48-1m-medium | 6.3min | 29 | 1 | $1.83 | — | bash | ok |
| PR Label Assigner | default | opus48-1m-medium | 8.2min | 36 | 1 | $1.91 | — | powershell | ok |
| Dependency License Checker | powershell | opus48-1m-medium | 7.7min | 33 | 0 | $1.93 | — | powershell | ok |
| Dependency License Checker | default | opus48-1m-medium | 7.9min | 33 | 0 | $1.94 | — | python | ok |
| Test Results Aggregator | powershell-tool | opus48-1m-medium | 7.4min | 29 | 0 | $1.95 | — | powershell | ok |
| Environment Matrix Generator | default | opus48-1m-medium | 6.7min | 28 | 0 | $2.01 | — | python | ok |
| Environment Matrix Generator | powershell | opus48-1m-medium | 9.3min | 33 | 0 | $2.29 | — | powershell | ok |
| Dependency License Checker | typescript-bun | opus48-1m-medium | 8.7min | 45 | 0 | $2.33 | — | typescript | ok |
| Semantic Version Bumper | powershell | opus48-1m-medium | 10.0min | 34 | 0 | $2.33 | — | powershell | ok |
| Secret Rotation Validator | default | opus48-1m-medium | 9.8min | 38 | 1 | $2.36 | — | powershell | ok |
| Semantic Version Bumper | powershell-tool | opus48-1m-medium | 10.6min | 40 | 1 | $2.39 | — | powershell | ok |
| Semantic Version Bumper | typescript-bun | opus48-1m-medium | 9.3min | 47 | 2 | $2.47 | — | typescript | ok |
| PR Label Assigner | typescript-bun | opus48-1m-medium | 13.1min | 44 | 0 | $2.48 | — | typescript | ok |
| Test Results Aggregator | typescript-bun | opus48-1m-medium | 9.2min | 45 | 0 | $2.57 | — | typescript | ok |
| Dependency License Checker | powershell-tool | opus48-1m-medium | 12.7min | 49 | 0 | $3.35 | — | powershell | ok |
| Artifact Cleanup Script | typescript-bun | opus48-1m-medium | 15.6min | 48 | 2 | $3.55 | — | typescript | ok |
| Artifact Cleanup Script | bash | opus48-1m-medium | 31.2min | 57 | 3 | $4.44 | — | bash | ok |

</details>

<details>
<summary>Sorted by duration (fastest first)</summary>

| Task | Language | Model | Duration | Turns | Errors | Cost | Tests Quality | Chosen | Status |
|------|----------|-------|----------|-------|--------|------|-----------|--------|--------|
| PR Label Assigner | bash | opus48-1m-medium | 4.8min | 20 | 0 | $1.22 | — | bash | ok |
| Dependency License Checker | bash | opus48-1m-medium | 5.7min | 24 | 0 | $1.45 | — | bash | ok |
| Environment Matrix Generator | bash | opus48-1m-medium | 5.8min | 27 | 0 | $1.72 | — | bash | ok |
| Test Results Aggregator | bash | opus48-1m-medium | 6.3min | 29 | 1 | $1.83 | — | bash | ok |
| PR Label Assigner | powershell | opus48-1m-medium | 6.3min | 23 | 0 | $1.52 | — | powershell | ok |
| Test Results Aggregator | default | opus48-1m-medium | 6.6min | 26 | 0 | $1.50 | — | python | ok |
| Environment Matrix Generator | default | opus48-1m-medium | 6.7min | 28 | 0 | $2.01 | — | python | ok |
| Semantic Version Bumper | bash | opus48-1m-medium | 6.8min | 22 | 0 | $1.55 | — | bash | ok |
| Semantic Version Bumper | default | opus48-1m-medium | 7.2min | 27 | 0 | $1.83 | — | python | ok |
| Test Results Aggregator | powershell-tool | opus48-1m-medium | 7.4min | 29 | 0 | $1.95 | — | powershell | ok |
| PR Label Assigner | powershell-tool | opus48-1m-medium | 7.6min | 27 | 1 | $1.66 | — | powershell | ok |
| Dependency License Checker | powershell | opus48-1m-medium | 7.7min | 33 | 0 | $1.93 | — | powershell | ok |
| Dependency License Checker | default | opus48-1m-medium | 7.9min | 33 | 0 | $1.94 | — | python | ok |
| Test Results Aggregator | powershell | opus48-1m-medium | 8.1min | 30 | 0 | $1.77 | — | powershell | ok |
| PR Label Assigner | default | opus48-1m-medium | 8.2min | 36 | 1 | $1.91 | — | powershell | ok |
| Dependency License Checker | typescript-bun | opus48-1m-medium | 8.7min | 45 | 0 | $2.33 | — | typescript | ok |
| Test Results Aggregator | typescript-bun | opus48-1m-medium | 9.2min | 45 | 0 | $2.57 | — | typescript | ok |
| Semantic Version Bumper | typescript-bun | opus48-1m-medium | 9.3min | 47 | 2 | $2.47 | — | typescript | ok |
| Environment Matrix Generator | powershell | opus48-1m-medium | 9.3min | 33 | 0 | $2.29 | — | powershell | ok |
| Secret Rotation Validator | default | opus48-1m-medium | 9.8min | 38 | 1 | $2.36 | — | powershell | ok |
| Semantic Version Bumper | powershell | opus48-1m-medium | 10.0min | 34 | 0 | $2.33 | — | powershell | ok |
| Semantic Version Bumper | powershell-tool | opus48-1m-medium | 10.6min | 40 | 1 | $2.39 | — | powershell | ok |
| Dependency License Checker | powershell-tool | opus48-1m-medium | 12.7min | 49 | 0 | $3.35 | — | powershell | ok |
| PR Label Assigner | typescript-bun | opus48-1m-medium | 13.1min | 44 | 0 | $2.48 | — | typescript | ok |
| Artifact Cleanup Script | typescript-bun | opus48-1m-medium | 15.6min | 48 | 2 | $3.55 | — | typescript | ok |
| Artifact Cleanup Script | bash | opus48-1m-medium | 31.2min | 57 | 3 | $4.44 | — | bash | ok |
| Environment Matrix Generator | typescript-bun | opus48-1m-medium | 32.5min | 0 | 3 | $0.00 | — | typescript | timeout |

</details>

<details>
<summary>Sorted by errors (fewest first)</summary>

| Task | Language | Model | Duration | Turns | Errors | Cost | Tests Quality | Chosen | Status |
|------|----------|-------|----------|-------|--------|------|-----------|--------|--------|
| Semantic Version Bumper | bash | opus48-1m-medium | 6.8min | 22 | 0 | $1.55 | — | bash | ok |
| Semantic Version Bumper | default | opus48-1m-medium | 7.2min | 27 | 0 | $1.83 | — | python | ok |
| Semantic Version Bumper | powershell | opus48-1m-medium | 10.0min | 34 | 0 | $2.33 | — | powershell | ok |
| PR Label Assigner | bash | opus48-1m-medium | 4.8min | 20 | 0 | $1.22 | — | bash | ok |
| PR Label Assigner | powershell | opus48-1m-medium | 6.3min | 23 | 0 | $1.52 | — | powershell | ok |
| PR Label Assigner | typescript-bun | opus48-1m-medium | 13.1min | 44 | 0 | $2.48 | — | typescript | ok |
| Dependency License Checker | bash | opus48-1m-medium | 5.7min | 24 | 0 | $1.45 | — | bash | ok |
| Dependency License Checker | default | opus48-1m-medium | 7.9min | 33 | 0 | $1.94 | — | python | ok |
| Dependency License Checker | powershell | opus48-1m-medium | 7.7min | 33 | 0 | $1.93 | — | powershell | ok |
| Dependency License Checker | powershell-tool | opus48-1m-medium | 12.7min | 49 | 0 | $3.35 | — | powershell | ok |
| Dependency License Checker | typescript-bun | opus48-1m-medium | 8.7min | 45 | 0 | $2.33 | — | typescript | ok |
| Test Results Aggregator | default | opus48-1m-medium | 6.6min | 26 | 0 | $1.50 | — | python | ok |
| Test Results Aggregator | powershell | opus48-1m-medium | 8.1min | 30 | 0 | $1.77 | — | powershell | ok |
| Test Results Aggregator | powershell-tool | opus48-1m-medium | 7.4min | 29 | 0 | $1.95 | — | powershell | ok |
| Test Results Aggregator | typescript-bun | opus48-1m-medium | 9.2min | 45 | 0 | $2.57 | — | typescript | ok |
| Environment Matrix Generator | bash | opus48-1m-medium | 5.8min | 27 | 0 | $1.72 | — | bash | ok |
| Environment Matrix Generator | default | opus48-1m-medium | 6.7min | 28 | 0 | $2.01 | — | python | ok |
| Environment Matrix Generator | powershell | opus48-1m-medium | 9.3min | 33 | 0 | $2.29 | — | powershell | ok |
| Semantic Version Bumper | powershell-tool | opus48-1m-medium | 10.6min | 40 | 1 | $2.39 | — | powershell | ok |
| PR Label Assigner | default | opus48-1m-medium | 8.2min | 36 | 1 | $1.91 | — | powershell | ok |
| PR Label Assigner | powershell-tool | opus48-1m-medium | 7.6min | 27 | 1 | $1.66 | — | powershell | ok |
| Test Results Aggregator | bash | opus48-1m-medium | 6.3min | 29 | 1 | $1.83 | — | bash | ok |
| Secret Rotation Validator | default | opus48-1m-medium | 9.8min | 38 | 1 | $2.36 | — | powershell | ok |
| Semantic Version Bumper | typescript-bun | opus48-1m-medium | 9.3min | 47 | 2 | $2.47 | — | typescript | ok |
| Artifact Cleanup Script | typescript-bun | opus48-1m-medium | 15.6min | 48 | 2 | $3.55 | — | typescript | ok |
| Environment Matrix Generator | typescript-bun | opus48-1m-medium | 32.5min | 0 | 3 | $0.00 | — | typescript | timeout |
| Artifact Cleanup Script | bash | opus48-1m-medium | 31.2min | 57 | 3 | $4.44 | — | bash | ok |

</details>

<details>
<summary>Sorted by turns (fewest first)</summary>

| Task | Language | Model | Duration | Turns | Errors | Cost | Tests Quality | Chosen | Status |
|------|----------|-------|----------|-------|--------|------|-----------|--------|--------|
| Environment Matrix Generator | typescript-bun | opus48-1m-medium | 32.5min | 0 | 3 | $0.00 | — | typescript | timeout |
| PR Label Assigner | bash | opus48-1m-medium | 4.8min | 20 | 0 | $1.22 | — | bash | ok |
| Semantic Version Bumper | bash | opus48-1m-medium | 6.8min | 22 | 0 | $1.55 | — | bash | ok |
| PR Label Assigner | powershell | opus48-1m-medium | 6.3min | 23 | 0 | $1.52 | — | powershell | ok |
| Dependency License Checker | bash | opus48-1m-medium | 5.7min | 24 | 0 | $1.45 | — | bash | ok |
| Test Results Aggregator | default | opus48-1m-medium | 6.6min | 26 | 0 | $1.50 | — | python | ok |
| Semantic Version Bumper | default | opus48-1m-medium | 7.2min | 27 | 0 | $1.83 | — | python | ok |
| PR Label Assigner | powershell-tool | opus48-1m-medium | 7.6min | 27 | 1 | $1.66 | — | powershell | ok |
| Environment Matrix Generator | bash | opus48-1m-medium | 5.8min | 27 | 0 | $1.72 | — | bash | ok |
| Environment Matrix Generator | default | opus48-1m-medium | 6.7min | 28 | 0 | $2.01 | — | python | ok |
| Test Results Aggregator | bash | opus48-1m-medium | 6.3min | 29 | 1 | $1.83 | — | bash | ok |
| Test Results Aggregator | powershell-tool | opus48-1m-medium | 7.4min | 29 | 0 | $1.95 | — | powershell | ok |
| Test Results Aggregator | powershell | opus48-1m-medium | 8.1min | 30 | 0 | $1.77 | — | powershell | ok |
| Dependency License Checker | default | opus48-1m-medium | 7.9min | 33 | 0 | $1.94 | — | python | ok |
| Dependency License Checker | powershell | opus48-1m-medium | 7.7min | 33 | 0 | $1.93 | — | powershell | ok |
| Environment Matrix Generator | powershell | opus48-1m-medium | 9.3min | 33 | 0 | $2.29 | — | powershell | ok |
| Semantic Version Bumper | powershell | opus48-1m-medium | 10.0min | 34 | 0 | $2.33 | — | powershell | ok |
| PR Label Assigner | default | opus48-1m-medium | 8.2min | 36 | 1 | $1.91 | — | powershell | ok |
| Secret Rotation Validator | default | opus48-1m-medium | 9.8min | 38 | 1 | $2.36 | — | powershell | ok |
| Semantic Version Bumper | powershell-tool | opus48-1m-medium | 10.6min | 40 | 1 | $2.39 | — | powershell | ok |
| PR Label Assigner | typescript-bun | opus48-1m-medium | 13.1min | 44 | 0 | $2.48 | — | typescript | ok |
| Dependency License Checker | typescript-bun | opus48-1m-medium | 8.7min | 45 | 0 | $2.33 | — | typescript | ok |
| Test Results Aggregator | typescript-bun | opus48-1m-medium | 9.2min | 45 | 0 | $2.57 | — | typescript | ok |
| Semantic Version Bumper | typescript-bun | opus48-1m-medium | 9.3min | 47 | 2 | $2.47 | — | typescript | ok |
| Artifact Cleanup Script | typescript-bun | opus48-1m-medium | 15.6min | 48 | 2 | $3.55 | — | typescript | ok |
| Dependency License Checker | powershell-tool | opus48-1m-medium | 12.7min | 49 | 0 | $3.35 | — | powershell | ok |
| Artifact Cleanup Script | bash | opus48-1m-medium | 31.2min | 57 | 3 | $4.44 | — | bash | ok |

</details>

<details>
<summary>Sorted by LLM-as-judge score (best first)</summary>

| Task | Language | Model | Duration | Turns | Errors | Cost | Tests Quality | Chosen | Status |
|------|----------|-------|----------|-------|--------|------|-----------|--------|--------|
| Semantic Version Bumper | bash | opus48-1m-medium | 6.8min | 22 | 0 | $1.55 | — | bash | ok |
| Semantic Version Bumper | default | opus48-1m-medium | 7.2min | 27 | 0 | $1.83 | — | python | ok |
| Semantic Version Bumper | powershell | opus48-1m-medium | 10.0min | 34 | 0 | $2.33 | — | powershell | ok |
| Semantic Version Bumper | powershell-tool | opus48-1m-medium | 10.6min | 40 | 1 | $2.39 | — | powershell | ok |
| Semantic Version Bumper | typescript-bun | opus48-1m-medium | 9.3min | 47 | 2 | $2.47 | — | typescript | ok |
| PR Label Assigner | bash | opus48-1m-medium | 4.8min | 20 | 0 | $1.22 | — | bash | ok |
| PR Label Assigner | default | opus48-1m-medium | 8.2min | 36 | 1 | $1.91 | — | powershell | ok |
| PR Label Assigner | powershell | opus48-1m-medium | 6.3min | 23 | 0 | $1.52 | — | powershell | ok |
| PR Label Assigner | powershell-tool | opus48-1m-medium | 7.6min | 27 | 1 | $1.66 | — | powershell | ok |
| PR Label Assigner | typescript-bun | opus48-1m-medium | 13.1min | 44 | 0 | $2.48 | — | typescript | ok |
| Dependency License Checker | bash | opus48-1m-medium | 5.7min | 24 | 0 | $1.45 | — | bash | ok |
| Dependency License Checker | default | opus48-1m-medium | 7.9min | 33 | 0 | $1.94 | — | python | ok |
| Dependency License Checker | powershell | opus48-1m-medium | 7.7min | 33 | 0 | $1.93 | — | powershell | ok |
| Dependency License Checker | powershell-tool | opus48-1m-medium | 12.7min | 49 | 0 | $3.35 | — | powershell | ok |
| Dependency License Checker | typescript-bun | opus48-1m-medium | 8.7min | 45 | 0 | $2.33 | — | typescript | ok |
| Test Results Aggregator | bash | opus48-1m-medium | 6.3min | 29 | 1 | $1.83 | — | bash | ok |
| Test Results Aggregator | default | opus48-1m-medium | 6.6min | 26 | 0 | $1.50 | — | python | ok |
| Test Results Aggregator | powershell | opus48-1m-medium | 8.1min | 30 | 0 | $1.77 | — | powershell | ok |
| Test Results Aggregator | powershell-tool | opus48-1m-medium | 7.4min | 29 | 0 | $1.95 | — | powershell | ok |
| Test Results Aggregator | typescript-bun | opus48-1m-medium | 9.2min | 45 | 0 | $2.57 | — | typescript | ok |
| Environment Matrix Generator | bash | opus48-1m-medium | 5.8min | 27 | 0 | $1.72 | — | bash | ok |
| Environment Matrix Generator | default | opus48-1m-medium | 6.7min | 28 | 0 | $2.01 | — | python | ok |
| Environment Matrix Generator | powershell | opus48-1m-medium | 9.3min | 33 | 0 | $2.29 | — | powershell | ok |
| Environment Matrix Generator | typescript-bun | opus48-1m-medium | 32.5min | 0 | 3 | $0.00 | — | typescript | timeout |
| Artifact Cleanup Script | bash | opus48-1m-medium | 31.2min | 57 | 3 | $4.44 | — | bash | ok |
| Artifact Cleanup Script | typescript-bun | opus48-1m-medium | 15.6min | 48 | 2 | $3.55 | — | typescript | ok |
| Secret Rotation Validator | default | opus48-1m-medium | 9.8min | 38 | 1 | $2.36 | — | powershell | ok |

</details>

## Notes

### Tiers

- **Duration bands:** **A+** ≤1.03×, **A** ≤1.06×, **A-** ≤1.10×, **B+** ≤1.13×, **B** ≤1.17×, **B-** ≤1.20×, **C+** ≤1.24×, **C** ≤1.28×, **C-** ≤1.32×, **D+** ≤1.36×, **D** ≤1.40×, **D-** ≤1.45×, **F** >1.45×
- **Cost bands:** **A+** ≤1.03×, **A** ≤1.06×, **A-** ≤1.09×, **B+** ≤1.12×, **B** ≤1.15×, **B-** ≤1.18×, **C+** ≤1.21×, **C** ≤1.25×, **C-** ≤1.28×, **D+** ≤1.32×, **D** ≤1.36×, **D-** ≤1.39×, **F** >1.39×

*Tests/Workflow Craft bands are absolute Overall score bands:* **A+** ≥4.7, **A** ≥4.4, **A-** ≥4.1, **B+** ≥3.8, **B** ≥3.5, **B-** ≥3.2, **C+** ≥2.9, **C** ≥2.6, **C-** ≥2.3, **D+** ≥2.0, **D** ≥1.7, **D-** ≥1.4, **F** <1.4, `—` = no data.*

### CLI Version Legend

| Variant label | CLI version | Tasks | Languages |
|---------------|-------------|-------|-----------|
| opus48-1m-medium | 2.1.193 | 11-semantic-version-bumper, 12-pr-label-assigner, 13-dependency-license-checker, 15-test-results-aggregator, 16-environment-matrix-generator | All |
| opus48-1m-medium | 2.1.195 | 17-artifact-cleanup-script, 18-secret-rotation-validator | bash, default, typescript-bun |

---
*Generated by generate_results.py — benchmark instructions v4*