# Benchmark Results: Language Comparison

**Last updated:** 2026-06-26 12:34:32 PM ET — 13/35 runs completed, 22 remaining; total cost $24.67; total agent time 105.1 min.
**Claude Code versions used:** v2.1.193 (13 runs). Each link goes to a per-version snapshot of the system prompt, default-tool descriptions, and the chronological Anthropic changelog up to that version. Regenerate with `python3 version_docs.py`.

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

| Language | Model | Duration | Cost | Tests Quality | Workflow Craft |
|----------|-------|----------|------|-----------|-------------|
| bash | opus48-1m-medium | A+ (5.8min) | A+ ($1.40) | — | — |
| default | opus48-1m-medium | B- (7.8min) | C+ ($1.89) | — | — |
| powershell | opus48-1m-medium | B- (8.0min) | C+ ($1.93) | — | — |
| powershell-tool | opus48-1m-medium | C- (9.1min) | C ($2.02) | — | — |
| typescript-bun | opus48-1m-medium | D- (11.2min) | D- ($2.48) | — | — |


<details>
<summary>Sorted by Duration tier (best-first), then avg of Cost/Tests/Workflow Craft tiers</summary>

| Language | Model | Duration | Cost | Tests Quality | Workflow Craft |
|----------|-------|----------|------|-----------|-------------|
| bash | opus48-1m-medium | A+ (5.8min) | A+ ($1.40) | — | — |
| default | opus48-1m-medium | B- (7.8min) | C+ ($1.89) | — | — |
| powershell | opus48-1m-medium | B- (8.0min) | C+ ($1.93) | — | — |
| powershell-tool | opus48-1m-medium | C- (9.1min) | C ($2.02) | — | — |
| typescript-bun | opus48-1m-medium | D- (11.2min) | D- ($2.48) | — | — |

</details>

<details>
<summary>Sorted by Cost tier (best-first), then avg of Duration/Tests/Workflow Craft tiers</summary>

| Language | Model | Duration | Cost | Tests Quality | Workflow Craft |
|----------|-------|----------|------|-----------|-------------|
| bash | opus48-1m-medium | A+ (5.8min) | A+ ($1.40) | — | — |
| default | opus48-1m-medium | B- (7.8min) | C+ ($1.89) | — | — |
| powershell | opus48-1m-medium | B- (8.0min) | C+ ($1.93) | — | — |
| powershell-tool | opus48-1m-medium | C- (9.1min) | C ($2.02) | — | — |
| typescript-bun | opus48-1m-medium | D- (11.2min) | D- ($2.48) | — | — |

</details>

<details>
<summary>Sorted by Tests Quality tier (best-first; no-data last), then avg of other tiers</summary>

| Language | Model | Duration | Cost | Tests Quality | Workflow Craft |
|----------|-------|----------|------|-----------|-------------|
| bash | opus48-1m-medium | A+ (5.8min) | A+ ($1.40) | — | — |
| default | opus48-1m-medium | B- (7.8min) | C+ ($1.89) | — | — |
| powershell | opus48-1m-medium | B- (8.0min) | C+ ($1.93) | — | — |
| powershell-tool | opus48-1m-medium | C- (9.1min) | C ($2.02) | — | — |
| typescript-bun | opus48-1m-medium | D- (11.2min) | D- ($2.48) | — | — |

</details>

<details>
<summary>Sorted by Workflow Craft tier (best-first; no-data last), then avg of other tiers</summary>

| Language | Model | Duration | Cost | Tests Quality | Workflow Craft |
|----------|-------|----------|------|-----------|-------------|
| bash | opus48-1m-medium | A+ (5.8min) | A+ ($1.40) | — | — |
| default | opus48-1m-medium | B- (7.8min) | C+ ($1.89) | — | — |
| powershell | opus48-1m-medium | B- (8.0min) | C+ ($1.93) | — | — |
| powershell-tool | opus48-1m-medium | C- (9.1min) | C ($2.02) | — | — |
| typescript-bun | opus48-1m-medium | D- (11.2min) | D- ($2.48) | — | — |

</details>

- **Estimated time remaining:** 177.8min
- **Estimated total cost:** $66.43

## Comparison by Language/Model/Effort
*See [Notes](#notes) for scoring rubric and CLI version legend.*

| Language | Model | Runs | Avg Duration | Avg Duration Net of Traps | Avg Errors | Avg Turns | Avg Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| bash | opus48-1m-medium | 3 | 5.8min | 4.8min | 0.0 | 22 | $1.40 | $4.21 | — | — |
| default | opus48-1m-medium | 3 | 7.8min | 6.5min | 0.3 | 32 | $1.89 | $5.68 | — | — |
| powershell | opus48-1m-medium | 3 | 8.0min | 7.3min | 0.0 | 30 | $1.93 | $5.78 | — | — |
| powershell-tool | opus48-1m-medium | 2 | 9.1min | 7.8min | 1.0 | 34 | $2.02 | $4.04 | — | — |
| typescript-bun | opus48-1m-medium | 2 | 11.2min | 8.4min | 1.0 | 46 | $2.48 | $4.96 | — | — |


<details>
<summary>Sorted by avg cost (cheapest first)</summary>

| Language | Model | Runs | Avg Duration | Avg Duration Net of Traps | Avg Errors | Avg Turns | Avg Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| bash | opus48-1m-medium | 3 | 5.8min | 4.8min | 0.0 | 22 | $1.40 | $4.21 | — | — |
| default | opus48-1m-medium | 3 | 7.8min | 6.5min | 0.3 | 32 | $1.89 | $5.68 | — | — |
| powershell | opus48-1m-medium | 3 | 8.0min | 7.3min | 0.0 | 30 | $1.93 | $5.78 | — | — |
| powershell-tool | opus48-1m-medium | 2 | 9.1min | 7.8min | 1.0 | 34 | $2.02 | $4.04 | — | — |
| typescript-bun | opus48-1m-medium | 2 | 11.2min | 8.4min | 1.0 | 46 | $2.48 | $4.96 | — | — |

</details>

<details>
<summary>Sorted by avg duration (fastest first)</summary>

| Language | Model | Runs | Avg Duration | Avg Duration Net of Traps | Avg Errors | Avg Turns | Avg Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| bash | opus48-1m-medium | 3 | 5.8min | 4.8min | 0.0 | 22 | $1.40 | $4.21 | — | — |
| default | opus48-1m-medium | 3 | 7.8min | 6.5min | 0.3 | 32 | $1.89 | $5.68 | — | — |
| powershell | opus48-1m-medium | 3 | 8.0min | 7.3min | 0.0 | 30 | $1.93 | $5.78 | — | — |
| powershell-tool | opus48-1m-medium | 2 | 9.1min | 7.8min | 1.0 | 34 | $2.02 | $4.04 | — | — |
| typescript-bun | opus48-1m-medium | 2 | 11.2min | 8.4min | 1.0 | 46 | $2.48 | $4.96 | — | — |

</details>

<details>
<summary>Sorted by avg duration net of traps (fastest first)</summary>

| Language | Model | Runs | Avg Duration | Avg Duration Net of Traps | Avg Errors | Avg Turns | Avg Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| bash | opus48-1m-medium | 3 | 5.8min | 4.8min | 0.0 | 22 | $1.40 | $4.21 | — | — |
| default | opus48-1m-medium | 3 | 7.8min | 6.5min | 0.3 | 32 | $1.89 | $5.68 | — | — |
| powershell | opus48-1m-medium | 3 | 8.0min | 7.3min | 0.0 | 30 | $1.93 | $5.78 | — | — |
| powershell-tool | opus48-1m-medium | 2 | 9.1min | 7.8min | 1.0 | 34 | $2.02 | $4.04 | — | — |
| typescript-bun | opus48-1m-medium | 2 | 11.2min | 8.4min | 1.0 | 46 | $2.48 | $4.96 | — | — |

</details>

<details>
<summary>Sorted by avg errors (fewest first)</summary>

| Language | Model | Runs | Avg Duration | Avg Duration Net of Traps | Avg Errors | Avg Turns | Avg Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| bash | opus48-1m-medium | 3 | 5.8min | 4.8min | 0.0 | 22 | $1.40 | $4.21 | — | — |
| powershell | opus48-1m-medium | 3 | 8.0min | 7.3min | 0.0 | 30 | $1.93 | $5.78 | — | — |
| default | opus48-1m-medium | 3 | 7.8min | 6.5min | 0.3 | 32 | $1.89 | $5.68 | — | — |
| powershell-tool | opus48-1m-medium | 2 | 9.1min | 7.8min | 1.0 | 34 | $2.02 | $4.04 | — | — |
| typescript-bun | opus48-1m-medium | 2 | 11.2min | 8.4min | 1.0 | 46 | $2.48 | $4.96 | — | — |

</details>

<details>
<summary>Sorted by avg turns (fewest first)</summary>

| Language | Model | Runs | Avg Duration | Avg Duration Net of Traps | Avg Errors | Avg Turns | Avg Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| bash | opus48-1m-medium | 3 | 5.8min | 4.8min | 0.0 | 22 | $1.40 | $4.21 | — | — |
| powershell | opus48-1m-medium | 3 | 8.0min | 7.3min | 0.0 | 30 | $1.93 | $5.78 | — | — |
| default | opus48-1m-medium | 3 | 7.8min | 6.5min | 0.3 | 32 | $1.89 | $5.68 | — | — |
| powershell-tool | opus48-1m-medium | 2 | 9.1min | 7.8min | 1.0 | 34 | $2.02 | $4.04 | — | — |
| typescript-bun | opus48-1m-medium | 2 | 11.2min | 8.4min | 1.0 | 46 | $2.48 | $4.96 | — | — |

</details>

<details>
<summary>Sorted by LLM-as-judge score (best first)</summary>

| Language | Model | Runs | Avg Duration | Avg Duration Net of Traps | Avg Errors | Avg Turns | Avg Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| bash | opus48-1m-medium | 3 | 5.8min | 4.8min | 0.0 | 22 | $1.40 | $4.21 | — | — |
| default | opus48-1m-medium | 3 | 7.8min | 6.5min | 0.3 | 32 | $1.89 | $5.68 | — | — |
| powershell | opus48-1m-medium | 3 | 8.0min | 7.3min | 0.0 | 30 | $1.93 | $5.78 | — | — |
| powershell-tool | opus48-1m-medium | 2 | 9.1min | 7.8min | 1.0 | 34 | $2.02 | $4.04 | — | — |
| typescript-bun | opus48-1m-medium | 2 | 11.2min | 8.4min | 1.0 | 46 | $2.48 | $4.96 | — | — |

</details>

<details>
<summary>Sorted by deliverable-quality score (best first)</summary>

| Language | Model | Runs | Avg Duration | Avg Duration Net of Traps | Avg Errors | Avg Turns | Avg Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| bash | opus48-1m-medium | 3 | 5.8min | 4.8min | 0.0 | 22 | $1.40 | $4.21 | — | — |
| default | opus48-1m-medium | 3 | 7.8min | 6.5min | 0.3 | 32 | $1.89 | $5.68 | — | — |
| powershell | opus48-1m-medium | 3 | 8.0min | 7.3min | 0.0 | 30 | $1.93 | $5.78 | — | — |
| powershell-tool | opus48-1m-medium | 2 | 9.1min | 7.8min | 1.0 | 34 | $2.02 | $4.04 | — | — |
| typescript-bun | opus48-1m-medium | 2 | 11.2min | 8.4min | 1.0 | 46 | $2.48 | $4.96 | — | — |

</details>

## Savings Analysis

### Hook Savings by Language/Model/Effort

Each hook-caught error avoids one test run that would otherwise have been needed to discover it.
Every hook fire (hit or miss) costs execution time for the syntax/type checker.

*`% of Test Time Saved` = `net / (net + test_time) × 100` — the share of total (would-have-been + actually-spent) test time that hooks eliminated. Bounded in (-∞, 100%) without an artificial cap; near 100% means hooks substituted for almost all of the hypothetical test work.*

| Language | Model | Fires | Caught | Rate | Gross Saved | % of Time | Overhead | % of Time | Net Saved | % of Time | Test Run Time | % of Test Time Saved |
|------|-------|-------|--------|------|------------|-----------|----------|-----------|-----------|-----------|---------------|----------------------|
| bash | opus48-1m-medium-cli2.1.193 | 27 | 0 | 0.0% | 0.0min | 0.0% | 0.0min | 0.0% | -0.0min | -0.0% | 0.5min | -2.0% |
| default | opus48-1m-medium-cli2.1.193 | 42 | 0 | 0.0% | 0.0min | 0.0% | 0.1min | 0.1% | -0.1min | -0.1% | 2.2min | -5.1% |
| powershell | opus48-1m-medium-cli2.1.193 | 41 | 0 | 0.0% | 0.0min | 0.0% | 0.2min | 0.2% | -0.2min | -0.2% | 2.1min | -8.9% |
| powershell-tool | opus48-1m-medium-cli2.1.193 | 30 | 0 | 0.0% | 0.0min | 0.0% | 0.2min | 0.2% | -0.2min | -0.2% | 2.4min | -7.4% |
| typescript-bun | opus48-1m-medium-cli2.1.193 | 45 | 11 | 24.4% | 1.5min | 1.4% | 1.1min | 1.1% | 0.3min | 0.3% | 2.8min | 11.0% |


<details>
<summary>Sorted by net saved (most first)</summary>

| Language | Model | Fires | Caught | Rate | Gross Saved | % of Time | Overhead | % of Time | Net Saved | % of Time | Test Run Time | % of Test Time Saved |
|------|-------|-------|--------|------|------------|-----------|----------|-----------|-----------|-----------|---------------|----------------------|
| typescript-bun | opus48-1m-medium-cli2.1.193 | 45 | 11 | 24.4% | 1.5min | 1.4% | 1.1min | 1.1% | 0.3min | 0.3% | 2.8min | 11.0% |
| bash | opus48-1m-medium-cli2.1.193 | 27 | 0 | 0.0% | 0.0min | 0.0% | 0.0min | 0.0% | -0.0min | -0.0% | 0.5min | -2.0% |
| default | opus48-1m-medium-cli2.1.193 | 42 | 0 | 0.0% | 0.0min | 0.0% | 0.1min | 0.1% | -0.1min | -0.1% | 2.2min | -5.1% |
| powershell-tool | opus48-1m-medium-cli2.1.193 | 30 | 0 | 0.0% | 0.0min | 0.0% | 0.2min | 0.2% | -0.2min | -0.2% | 2.4min | -7.4% |
| powershell | opus48-1m-medium-cli2.1.193 | 41 | 0 | 0.0% | 0.0min | 0.0% | 0.2min | 0.2% | -0.2min | -0.2% | 2.1min | -8.9% |

</details>

<details>
<summary>Sorted by net % of test time saved (most first)</summary>

| Language | Model | Fires | Caught | Rate | Gross Saved | % of Time | Overhead | % of Time | Net Saved | % of Time | Test Run Time | % of Test Time Saved |
|------|-------|-------|--------|------|------------|-----------|----------|-----------|-----------|-----------|---------------|----------------------|
| typescript-bun | opus48-1m-medium-cli2.1.193 | 45 | 11 | 24.4% | 1.5min | 1.4% | 1.1min | 1.1% | 0.3min | 0.3% | 2.8min | 11.0% |
| bash | opus48-1m-medium-cli2.1.193 | 27 | 0 | 0.0% | 0.0min | 0.0% | 0.0min | 0.0% | -0.0min | -0.0% | 0.5min | -2.0% |
| default | opus48-1m-medium-cli2.1.193 | 42 | 0 | 0.0% | 0.0min | 0.0% | 0.1min | 0.1% | -0.1min | -0.1% | 2.2min | -5.1% |
| powershell-tool | opus48-1m-medium-cli2.1.193 | 30 | 0 | 0.0% | 0.0min | 0.0% | 0.2min | 0.2% | -0.2min | -0.2% | 2.4min | -7.4% |
| powershell | opus48-1m-medium-cli2.1.193 | 41 | 0 | 0.0% | 0.0min | 0.0% | 0.2min | 0.2% | -0.2min | -0.2% | 2.1min | -8.9% |

</details>

<details>
<summary>Sorted by catch rate (highest first)</summary>

| Language | Model | Fires | Caught | Rate | Gross Saved | % of Time | Overhead | % of Time | Net Saved | % of Time | Test Run Time | % of Test Time Saved |
|------|-------|-------|--------|------|------------|-----------|----------|-----------|-----------|-----------|---------------|----------------------|
| typescript-bun | opus48-1m-medium-cli2.1.193 | 45 | 11 | 24.4% | 1.5min | 1.4% | 1.1min | 1.1% | 0.3min | 0.3% | 2.8min | 11.0% |
| bash | opus48-1m-medium-cli2.1.193 | 27 | 0 | 0.0% | 0.0min | 0.0% | 0.0min | 0.0% | -0.0min | -0.0% | 0.5min | -2.0% |
| default | opus48-1m-medium-cli2.1.193 | 42 | 0 | 0.0% | 0.0min | 0.0% | 0.1min | 0.1% | -0.1min | -0.1% | 2.2min | -5.1% |
| powershell | opus48-1m-medium-cli2.1.193 | 41 | 0 | 0.0% | 0.0min | 0.0% | 0.2min | 0.2% | -0.2min | -0.2% | 2.1min | -8.9% |
| powershell-tool | opus48-1m-medium-cli2.1.193 | 30 | 0 | 0.0% | 0.0min | 0.0% | 0.2min | 0.2% | -0.2min | -0.2% | 2.4min | -7.4% |

</details>

### Trap Analysis by Language/Model/Effort/Category

| Trap | Language | Model | Fell In | Time Lost | % of Time | $ Lost | % of $ |
|------|------|-------|---------|-----------|-----------|--------|--------|
| repeated-test-reruns | bash | opus48-1m-medium-cli2.1.193 | 2 | 2.0min | 1.9% | $0.48 | 1.95% |
| repeated-test-reruns | default | opus48-1m-medium-cli2.1.193 | 3 | 3.7min | 3.5% | $0.89 | 3.59% |
| repeated-test-reruns | powershell | opus48-1m-medium-cli2.1.193 | 1 | 1.7min | 1.6% | $0.42 | 1.70% |
| repeated-test-reruns | powershell-tool | opus48-1m-medium-cli2.1.193 | 1 | 2.7min | 2.5% | $0.60 | 2.44% |
| repeated-test-reruns | typescript-bun | opus48-1m-medium-cli2.1.193 | 2 | 3.3min | 3.2% | $0.81 | 3.28% |
| ts-type-error-fix-cycles | typescript-bun | opus48-1m-medium-cli2.1.193 | 1 | 2.2min | 2.1% | $0.58 | 2.37% |
| fixture-rework | bash | opus48-1m-medium-cli2.1.193 | 1 | 0.8min | 0.7% | $0.19 | 0.77% |
| fixture-rework | powershell | opus48-1m-medium-cli2.1.193 | 1 | 0.5min | 0.5% | $0.12 | 0.47% |


<details>
<summary>Sorted by time lost (least first)</summary>

| Trap | Language | Model | Fell In | Time Lost | % of Time | $ Lost | % of $ |
|------|------|-------|---------|-----------|-----------|--------|--------|
| fixture-rework | powershell | opus48-1m-medium-cli2.1.193 | 1 | 0.5min | 0.5% | $0.12 | 0.47% |
| fixture-rework | bash | opus48-1m-medium-cli2.1.193 | 1 | 0.8min | 0.7% | $0.19 | 0.77% |
| repeated-test-reruns | powershell | opus48-1m-medium-cli2.1.193 | 1 | 1.7min | 1.6% | $0.42 | 1.70% |
| repeated-test-reruns | bash | opus48-1m-medium-cli2.1.193 | 2 | 2.0min | 1.9% | $0.48 | 1.95% |
| ts-type-error-fix-cycles | typescript-bun | opus48-1m-medium-cli2.1.193 | 1 | 2.2min | 2.1% | $0.58 | 2.37% |
| repeated-test-reruns | powershell-tool | opus48-1m-medium-cli2.1.193 | 1 | 2.7min | 2.5% | $0.60 | 2.44% |
| repeated-test-reruns | typescript-bun | opus48-1m-medium-cli2.1.193 | 2 | 3.3min | 3.2% | $0.81 | 3.28% |
| repeated-test-reruns | default | opus48-1m-medium-cli2.1.193 | 3 | 3.7min | 3.5% | $0.89 | 3.59% |

</details>

<details>
<summary>Sorted by $ lost (least first)</summary>

| Trap | Language | Model | Fell In | Time Lost | % of Time | $ Lost | % of $ |
|------|------|-------|---------|-----------|-----------|--------|--------|
| fixture-rework | powershell | opus48-1m-medium-cli2.1.193 | 1 | 0.5min | 0.5% | $0.12 | 0.47% |
| fixture-rework | bash | opus48-1m-medium-cli2.1.193 | 1 | 0.8min | 0.7% | $0.19 | 0.77% |
| repeated-test-reruns | powershell | opus48-1m-medium-cli2.1.193 | 1 | 1.7min | 1.6% | $0.42 | 1.70% |
| repeated-test-reruns | bash | opus48-1m-medium-cli2.1.193 | 2 | 2.0min | 1.9% | $0.48 | 1.95% |
| ts-type-error-fix-cycles | typescript-bun | opus48-1m-medium-cli2.1.193 | 1 | 2.2min | 2.1% | $0.58 | 2.37% |
| repeated-test-reruns | powershell-tool | opus48-1m-medium-cli2.1.193 | 1 | 2.7min | 2.5% | $0.60 | 2.44% |
| repeated-test-reruns | typescript-bun | opus48-1m-medium-cli2.1.193 | 2 | 3.3min | 3.2% | $0.81 | 3.28% |
| repeated-test-reruns | default | opus48-1m-medium-cli2.1.193 | 3 | 3.7min | 3.5% | $0.89 | 3.59% |

</details>

<details>
<summary>Sorted by fell-in count (fewest first)</summary>

| Trap | Language | Model | Fell In | Time Lost | % of Time | $ Lost | % of $ |
|------|------|-------|---------|-----------|-----------|--------|--------|
| repeated-test-reruns | powershell | opus48-1m-medium-cli2.1.193 | 1 | 1.7min | 1.6% | $0.42 | 1.70% |
| repeated-test-reruns | powershell-tool | opus48-1m-medium-cli2.1.193 | 1 | 2.7min | 2.5% | $0.60 | 2.44% |
| ts-type-error-fix-cycles | typescript-bun | opus48-1m-medium-cli2.1.193 | 1 | 2.2min | 2.1% | $0.58 | 2.37% |
| fixture-rework | bash | opus48-1m-medium-cli2.1.193 | 1 | 0.8min | 0.7% | $0.19 | 0.77% |
| fixture-rework | powershell | opus48-1m-medium-cli2.1.193 | 1 | 0.5min | 0.5% | $0.12 | 0.47% |
| repeated-test-reruns | bash | opus48-1m-medium-cli2.1.193 | 2 | 2.0min | 1.9% | $0.48 | 1.95% |
| repeated-test-reruns | typescript-bun | opus48-1m-medium-cli2.1.193 | 2 | 3.3min | 3.2% | $0.81 | 3.28% |
| repeated-test-reruns | default | opus48-1m-medium-cli2.1.193 | 3 | 3.7min | 3.5% | $0.89 | 3.59% |

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
| bash | opus48-1m-medium-cli2.1.193 | 3 | 3 | 2.8min | 2.6% | $0.67 | 2.73% |
| default | opus48-1m-medium-cli2.1.193 | 3 | 3 | 3.7min | 3.5% | $0.89 | 3.59% |
| powershell | opus48-1m-medium-cli2.1.193 | 3 | 2 | 2.2min | 2.1% | $0.54 | 2.17% |
| powershell-tool | opus48-1m-medium-cli2.1.193 | 2 | 1 | 2.7min | 2.5% | $0.60 | 2.44% |
| typescript-bun | opus48-1m-medium-cli2.1.193 | 2 | 3 | 5.5min | 5.3% | $1.39 | 5.65% |


<details>
<summary>Sorted by time lost (least first)</summary>

| Language | Model | Runs | Traps | Time Lost | % of Time | $ Lost | % of $ |
|------|-------|------|-------|-----------|-----------|--------|--------|
| powershell | opus48-1m-medium-cli2.1.193 | 3 | 2 | 2.2min | 2.1% | $0.54 | 2.17% |
| powershell-tool | opus48-1m-medium-cli2.1.193 | 2 | 1 | 2.7min | 2.5% | $0.60 | 2.44% |
| bash | opus48-1m-medium-cli2.1.193 | 3 | 3 | 2.8min | 2.6% | $0.67 | 2.73% |
| default | opus48-1m-medium-cli2.1.193 | 3 | 3 | 3.7min | 3.5% | $0.89 | 3.59% |
| typescript-bun | opus48-1m-medium-cli2.1.193 | 2 | 3 | 5.5min | 5.3% | $1.39 | 5.65% |

</details>

<details>
<summary>Sorted by $ lost (least first)</summary>

| Language | Model | Runs | Traps | Time Lost | % of Time | $ Lost | % of $ |
|------|-------|------|-------|-----------|-----------|--------|--------|
| powershell | opus48-1m-medium-cli2.1.193 | 3 | 2 | 2.2min | 2.1% | $0.54 | 2.17% |
| powershell-tool | opus48-1m-medium-cli2.1.193 | 2 | 1 | 2.7min | 2.5% | $0.60 | 2.44% |
| bash | opus48-1m-medium-cli2.1.193 | 3 | 3 | 2.8min | 2.6% | $0.67 | 2.73% |
| default | opus48-1m-medium-cli2.1.193 | 3 | 3 | 3.7min | 3.5% | $0.89 | 3.59% |
| typescript-bun | opus48-1m-medium-cli2.1.193 | 2 | 3 | 5.5min | 5.3% | $1.39 | 5.65% |

</details>

### Prompt Cache Savings

| Status | Runs | $ Saved | % of $ |
|--------|------|---------|--------|
| Full hit (100%) | 0 | $0.00 | 0.00% |
| Partial | 12 | $1.21 | 4.89% |
| Miss | 1 | $0.00 | 0.00% |

## Test Quality Evaluation

### Structural Metrics by Language/Model/Effort

Automated analysis of test files: test count, assertion count, and test-to-code line ratio.

| Language | Model | Avg Tests | Avg Assertions | Avg Assert/Test | Avg Test:Code Ratio |
|------|-------|-----------|----------------|-----------------|---------------------|
| bash | opus48-1m-medium | 22.0 | 32.0 | 1.5 | 1.22 |
| default | opus48-1m-medium | 29.0 | 44.7 | 1.5 | 0.88 |
| powershell | opus48-1m-medium | 35.0 | 55.0 | 1.6 | 4.37 |
| powershell-tool | opus48-1m-medium | 30.5 | 51.5 | 1.7 | 2.02 |
| typescript-bun | opus48-1m-medium | 31.5 | 64.5 | 2.0 | 0.90 |


<details>
<summary>Sorted by avg tests (most first)</summary>

| Language | Model | Avg Tests | Avg Assertions | Avg Assert/Test | Avg Test:Code Ratio |
|------|-------|-----------|----------------|-----------------|---------------------|
| powershell | opus48-1m-medium | 35.0 | 55.0 | 1.6 | 4.37 |
| typescript-bun | opus48-1m-medium | 31.5 | 64.5 | 2.0 | 0.90 |
| powershell-tool | opus48-1m-medium | 30.5 | 51.5 | 1.7 | 2.02 |
| default | opus48-1m-medium | 29.0 | 44.7 | 1.5 | 0.88 |
| bash | opus48-1m-medium | 22.0 | 32.0 | 1.5 | 1.22 |

</details>

<details>
<summary>Sorted by avg assertions (most first)</summary>

| Language | Model | Avg Tests | Avg Assertions | Avg Assert/Test | Avg Test:Code Ratio |
|------|-------|-----------|----------------|-----------------|---------------------|
| typescript-bun | opus48-1m-medium | 31.5 | 64.5 | 2.0 | 0.90 |
| powershell | opus48-1m-medium | 35.0 | 55.0 | 1.6 | 4.37 |
| powershell-tool | opus48-1m-medium | 30.5 | 51.5 | 1.7 | 2.02 |
| default | opus48-1m-medium | 29.0 | 44.7 | 1.5 | 0.88 |
| bash | opus48-1m-medium | 22.0 | 32.0 | 1.5 | 1.22 |

</details>

<details>
<summary>Sorted by avg test:code ratio (highest first)</summary>

| Language | Model | Avg Tests | Avg Assertions | Avg Assert/Test | Avg Test:Code Ratio |
|------|-------|-----------|----------------|-----------------|---------------------|
| powershell | opus48-1m-medium | 35.0 | 55.0 | 1.6 | 4.37 |
| powershell-tool | opus48-1m-medium | 30.5 | 51.5 | 1.7 | 2.02 |
| bash | opus48-1m-medium | 22.0 | 32.0 | 1.5 | 1.22 |
| typescript-bun | opus48-1m-medium | 31.5 | 64.5 | 2.0 | 0.90 |
| default | opus48-1m-medium | 29.0 | 44.7 | 1.5 | 0.88 |

</details>


<details>
<summary>Per-run structural metrics</summary>

| Task | Language | Model | Tests | Assertions | Assert/Test | Test Lines | Impl Lines | Test:Code |
|------|------|-------|-------|------------|-------------|------------|------------|-----------|
| Semantic Version Bumper | default | opus48-1m-medium | 38 | 61 | 1.6 | 498 | 312 | 1.60 |
| Semantic Version Bumper | powershell | opus48-1m-medium | 39 | 62 | 1.6 | 359 | 53 | 6.77 |
| Semantic Version Bumper | bash | opus48-1m-medium | 24 | 34 | 1.4 | 286 | 275 | 1.04 |
| Semantic Version Bumper | powershell-tool | opus48-1m-medium | 35 | 57 | 1.6 | 380 | 118 | 3.22 |
| Semantic Version Bumper | typescript-bun | opus48-1m-medium | 38 | 76 | 2.0 | 462 | 558 | 0.83 |
| PR Label Assigner | default | opus48-1m-medium | 30 | 36 | 1.2 | 222 | 407 | 0.55 |
| PR Label Assigner | powershell | opus48-1m-medium | 32 | 47 | 1.5 | 261 | 393 | 0.66 |
| PR Label Assigner | bash | opus48-1m-medium | 18 | 10 | 0.6 | 171 | 198 | 0.86 |
| PR Label Assigner | powershell-tool | opus48-1m-medium | 26 | 46 | 1.8 | 210 | 253 | 0.83 |
| PR Label Assigner | typescript-bun | opus48-1m-medium | 25 | 53 | 2.1 | 362 | 372 | 0.97 |
| Dependency License Checker | default | opus48-1m-medium | 19 | 37 | 1.9 | 212 | 433 | 0.49 |
| Dependency License Checker | powershell | opus48-1m-medium | 34 | 56 | 1.6 | 386 | 68 | 5.68 |
| Dependency License Checker | bash | opus48-1m-medium | 24 | 52 | 2.2 | 334 | 191 | 1.75 |

</details>

## Per-Run Results

*Tests Quality = Overall (1-5) from LLM-as-judge of generated test code (dimensions: coverage, rigor, design). `—` = no judge data.*

| Task | Language | Model | Duration | Turns | Errors | Cost | Tests Quality | Chosen | Status |
|------|----------|-------|----------|-------|--------|------|-----------|--------|--------|
| Dependency License Checker | bash | opus48-1m-medium | 5.7min | 24 | 0 | $1.45 | — | bash | ok |
| Dependency License Checker | default | opus48-1m-medium | 7.9min | 33 | 0 | $1.94 | — | python | ok |
| Dependency License Checker | powershell | opus48-1m-medium | 7.7min | 33 | 0 | $1.93 | — | powershell | ok |
| PR Label Assigner | bash | opus48-1m-medium | 4.8min | 20 | 0 | $1.22 | — | bash | ok |
| PR Label Assigner | default | opus48-1m-medium | 8.2min | 36 | 1 | $1.91 | — | powershell | ok |
| PR Label Assigner | powershell | opus48-1m-medium | 6.3min | 23 | 0 | $1.52 | — | powershell | ok |
| PR Label Assigner | powershell-tool | opus48-1m-medium | 7.6min | 27 | 1 | $1.66 | — | powershell | ok |
| PR Label Assigner | typescript-bun | opus48-1m-medium | 13.1min | 44 | 0 | $2.48 | — | typescript | ok |
| Semantic Version Bumper | bash | opus48-1m-medium | 6.8min | 22 | 0 | $1.55 | — | bash | ok |
| Semantic Version Bumper | default | opus48-1m-medium | 7.2min | 27 | 0 | $1.83 | — | python | ok |
| Semantic Version Bumper | powershell | opus48-1m-medium | 10.0min | 34 | 0 | $2.33 | — | powershell | ok |
| Semantic Version Bumper | powershell-tool | opus48-1m-medium | 10.6min | 40 | 1 | $2.39 | — | powershell | ok |
| Semantic Version Bumper | typescript-bun | opus48-1m-medium | 9.3min | 47 | 2 | $2.47 | — | typescript | ok |


<details>
<summary>Sorted by cost (cheapest first)</summary>

| Task | Language | Model | Duration | Turns | Errors | Cost | Tests Quality | Chosen | Status |
|------|----------|-------|----------|-------|--------|------|-----------|--------|--------|
| PR Label Assigner | bash | opus48-1m-medium | 4.8min | 20 | 0 | $1.22 | — | bash | ok |
| Dependency License Checker | bash | opus48-1m-medium | 5.7min | 24 | 0 | $1.45 | — | bash | ok |
| PR Label Assigner | powershell | opus48-1m-medium | 6.3min | 23 | 0 | $1.52 | — | powershell | ok |
| Semantic Version Bumper | bash | opus48-1m-medium | 6.8min | 22 | 0 | $1.55 | — | bash | ok |
| PR Label Assigner | powershell-tool | opus48-1m-medium | 7.6min | 27 | 1 | $1.66 | — | powershell | ok |
| Semantic Version Bumper | default | opus48-1m-medium | 7.2min | 27 | 0 | $1.83 | — | python | ok |
| PR Label Assigner | default | opus48-1m-medium | 8.2min | 36 | 1 | $1.91 | — | powershell | ok |
| Dependency License Checker | powershell | opus48-1m-medium | 7.7min | 33 | 0 | $1.93 | — | powershell | ok |
| Dependency License Checker | default | opus48-1m-medium | 7.9min | 33 | 0 | $1.94 | — | python | ok |
| Semantic Version Bumper | powershell | opus48-1m-medium | 10.0min | 34 | 0 | $2.33 | — | powershell | ok |
| Semantic Version Bumper | powershell-tool | opus48-1m-medium | 10.6min | 40 | 1 | $2.39 | — | powershell | ok |
| Semantic Version Bumper | typescript-bun | opus48-1m-medium | 9.3min | 47 | 2 | $2.47 | — | typescript | ok |
| PR Label Assigner | typescript-bun | opus48-1m-medium | 13.1min | 44 | 0 | $2.48 | — | typescript | ok |

</details>

<details>
<summary>Sorted by duration (fastest first)</summary>

| Task | Language | Model | Duration | Turns | Errors | Cost | Tests Quality | Chosen | Status |
|------|----------|-------|----------|-------|--------|------|-----------|--------|--------|
| PR Label Assigner | bash | opus48-1m-medium | 4.8min | 20 | 0 | $1.22 | — | bash | ok |
| Dependency License Checker | bash | opus48-1m-medium | 5.7min | 24 | 0 | $1.45 | — | bash | ok |
| PR Label Assigner | powershell | opus48-1m-medium | 6.3min | 23 | 0 | $1.52 | — | powershell | ok |
| Semantic Version Bumper | bash | opus48-1m-medium | 6.8min | 22 | 0 | $1.55 | — | bash | ok |
| Semantic Version Bumper | default | opus48-1m-medium | 7.2min | 27 | 0 | $1.83 | — | python | ok |
| PR Label Assigner | powershell-tool | opus48-1m-medium | 7.6min | 27 | 1 | $1.66 | — | powershell | ok |
| Dependency License Checker | powershell | opus48-1m-medium | 7.7min | 33 | 0 | $1.93 | — | powershell | ok |
| Dependency License Checker | default | opus48-1m-medium | 7.9min | 33 | 0 | $1.94 | — | python | ok |
| PR Label Assigner | default | opus48-1m-medium | 8.2min | 36 | 1 | $1.91 | — | powershell | ok |
| Semantic Version Bumper | typescript-bun | opus48-1m-medium | 9.3min | 47 | 2 | $2.47 | — | typescript | ok |
| Semantic Version Bumper | powershell | opus48-1m-medium | 10.0min | 34 | 0 | $2.33 | — | powershell | ok |
| Semantic Version Bumper | powershell-tool | opus48-1m-medium | 10.6min | 40 | 1 | $2.39 | — | powershell | ok |
| PR Label Assigner | typescript-bun | opus48-1m-medium | 13.1min | 44 | 0 | $2.48 | — | typescript | ok |

</details>

<details>
<summary>Sorted by errors (fewest first)</summary>

| Task | Language | Model | Duration | Turns | Errors | Cost | Tests Quality | Chosen | Status |
|------|----------|-------|----------|-------|--------|------|-----------|--------|--------|
| Semantic Version Bumper | default | opus48-1m-medium | 7.2min | 27 | 0 | $1.83 | — | python | ok |
| Semantic Version Bumper | powershell | opus48-1m-medium | 10.0min | 34 | 0 | $2.33 | — | powershell | ok |
| Semantic Version Bumper | bash | opus48-1m-medium | 6.8min | 22 | 0 | $1.55 | — | bash | ok |
| PR Label Assigner | powershell | opus48-1m-medium | 6.3min | 23 | 0 | $1.52 | — | powershell | ok |
| PR Label Assigner | bash | opus48-1m-medium | 4.8min | 20 | 0 | $1.22 | — | bash | ok |
| PR Label Assigner | typescript-bun | opus48-1m-medium | 13.1min | 44 | 0 | $2.48 | — | typescript | ok |
| Dependency License Checker | default | opus48-1m-medium | 7.9min | 33 | 0 | $1.94 | — | python | ok |
| Dependency License Checker | powershell | opus48-1m-medium | 7.7min | 33 | 0 | $1.93 | — | powershell | ok |
| Dependency License Checker | bash | opus48-1m-medium | 5.7min | 24 | 0 | $1.45 | — | bash | ok |
| Semantic Version Bumper | powershell-tool | opus48-1m-medium | 10.6min | 40 | 1 | $2.39 | — | powershell | ok |
| PR Label Assigner | default | opus48-1m-medium | 8.2min | 36 | 1 | $1.91 | — | powershell | ok |
| PR Label Assigner | powershell-tool | opus48-1m-medium | 7.6min | 27 | 1 | $1.66 | — | powershell | ok |
| Semantic Version Bumper | typescript-bun | opus48-1m-medium | 9.3min | 47 | 2 | $2.47 | — | typescript | ok |

</details>

<details>
<summary>Sorted by turns (fewest first)</summary>

| Task | Language | Model | Duration | Turns | Errors | Cost | Tests Quality | Chosen | Status |
|------|----------|-------|----------|-------|--------|------|-----------|--------|--------|
| PR Label Assigner | bash | opus48-1m-medium | 4.8min | 20 | 0 | $1.22 | — | bash | ok |
| Semantic Version Bumper | bash | opus48-1m-medium | 6.8min | 22 | 0 | $1.55 | — | bash | ok |
| PR Label Assigner | powershell | opus48-1m-medium | 6.3min | 23 | 0 | $1.52 | — | powershell | ok |
| Dependency License Checker | bash | opus48-1m-medium | 5.7min | 24 | 0 | $1.45 | — | bash | ok |
| Semantic Version Bumper | default | opus48-1m-medium | 7.2min | 27 | 0 | $1.83 | — | python | ok |
| PR Label Assigner | powershell-tool | opus48-1m-medium | 7.6min | 27 | 1 | $1.66 | — | powershell | ok |
| Dependency License Checker | default | opus48-1m-medium | 7.9min | 33 | 0 | $1.94 | — | python | ok |
| Dependency License Checker | powershell | opus48-1m-medium | 7.7min | 33 | 0 | $1.93 | — | powershell | ok |
| Semantic Version Bumper | powershell | opus48-1m-medium | 10.0min | 34 | 0 | $2.33 | — | powershell | ok |
| PR Label Assigner | default | opus48-1m-medium | 8.2min | 36 | 1 | $1.91 | — | powershell | ok |
| Semantic Version Bumper | powershell-tool | opus48-1m-medium | 10.6min | 40 | 1 | $2.39 | — | powershell | ok |
| PR Label Assigner | typescript-bun | opus48-1m-medium | 13.1min | 44 | 0 | $2.48 | — | typescript | ok |
| Semantic Version Bumper | typescript-bun | opus48-1m-medium | 9.3min | 47 | 2 | $2.47 | — | typescript | ok |

</details>

<details>
<summary>Sorted by LLM-as-judge score (best first)</summary>

| Task | Language | Model | Duration | Turns | Errors | Cost | Tests Quality | Chosen | Status |
|------|----------|-------|----------|-------|--------|------|-----------|--------|--------|
| Semantic Version Bumper | default | opus48-1m-medium | 7.2min | 27 | 0 | $1.83 | — | python | ok |
| Semantic Version Bumper | powershell | opus48-1m-medium | 10.0min | 34 | 0 | $2.33 | — | powershell | ok |
| Semantic Version Bumper | bash | opus48-1m-medium | 6.8min | 22 | 0 | $1.55 | — | bash | ok |
| Semantic Version Bumper | powershell-tool | opus48-1m-medium | 10.6min | 40 | 1 | $2.39 | — | powershell | ok |
| Semantic Version Bumper | typescript-bun | opus48-1m-medium | 9.3min | 47 | 2 | $2.47 | — | typescript | ok |
| PR Label Assigner | default | opus48-1m-medium | 8.2min | 36 | 1 | $1.91 | — | powershell | ok |
| PR Label Assigner | powershell | opus48-1m-medium | 6.3min | 23 | 0 | $1.52 | — | powershell | ok |
| PR Label Assigner | bash | opus48-1m-medium | 4.8min | 20 | 0 | $1.22 | — | bash | ok |
| PR Label Assigner | powershell-tool | opus48-1m-medium | 7.6min | 27 | 1 | $1.66 | — | powershell | ok |
| PR Label Assigner | typescript-bun | opus48-1m-medium | 13.1min | 44 | 0 | $2.48 | — | typescript | ok |
| Dependency License Checker | default | opus48-1m-medium | 7.9min | 33 | 0 | $1.94 | — | python | ok |
| Dependency License Checker | powershell | opus48-1m-medium | 7.7min | 33 | 0 | $1.93 | — | powershell | ok |
| Dependency License Checker | bash | opus48-1m-medium | 5.7min | 24 | 0 | $1.45 | — | bash | ok |

</details>

## Notes

### Tiers

- **Duration bands:** **A+** ≤1.06×, **A** ≤1.12×, **A-** ≤1.18×, **B+** ≤1.25×, **B** ≤1.32×, **B-** ≤1.40×, **C+** ≤1.47×, **C** ≤1.56×, **C-** ≤1.65×, **D+** ≤1.74×, **D** ≤1.84×, **D-** ≤1.95×, **F** >1.95×
- **Cost bands:** **A+** ≤1.05×, **A** ≤1.10×, **A-** ≤1.15×, **B+** ≤1.21×, **B** ≤1.27×, **B-** ≤1.33×, **C+** ≤1.39×, **C** ≤1.46×, **C-** ≤1.53×, **D+** ≤1.61×, **D** ≤1.68×, **D-** ≤1.76×, **F** >1.76×

*Tests/Workflow Craft bands are absolute Overall score bands:* **A+** ≥4.7, **A** ≥4.4, **A-** ≥4.1, **B+** ≥3.8, **B** ≥3.5, **B-** ≥3.2, **C+** ≥2.9, **C** ≥2.6, **C-** ≥2.3, **D+** ≥2.0, **D** ≥1.7, **D-** ≥1.4, **F** <1.4, `—` = no data.*

### CLI Version Legend

| Variant label | CLI version | Tasks | Languages |
|---------------|-------------|-------|-----------|
| opus48-1m-medium | 2.1.193 | All | All |

---
*Generated by generate_results.py — benchmark instructions v4*