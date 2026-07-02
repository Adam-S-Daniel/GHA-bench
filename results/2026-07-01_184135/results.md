# Benchmark Results: Language Comparison

**Last updated:** 2026-07-01 09:05:29 PM ET — 14/28 runs completed, 14 remaining; total cost $55.02; total agent time 143.2 min.
**Claude Code versions used:** v2.1.198 (14 runs). Each link goes to a per-version snapshot of the system prompt, default-tool descriptions, and the chronological Anthropic changelog up to that version. Regenerate with `python3 version_docs.py`.

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
| bash | fable5-medium | A+ (7.8min) | A+ ($3.70) | — | — |
| default | fable5-medium | A+ (8.1min) | B- ($3.86) | — | — |
| typescript-bun | fable5-medium | B (10.0min) | D ($4.03) | — | — |
| powershell | fable5-medium | D- (14.4min) | D- ($4.10) | — | — |


<details>
<summary>Sorted by Duration tier (best-first), then avg of Cost/Tests/Workflow Craft tiers</summary>

| Language | Model | Duration | Cost | Tests Quality | Workflow Craft |
|----------|-------|----------|------|-----------|-------------|
| bash | fable5-medium | A+ (7.8min) | A+ ($3.70) | — | — |
| default | fable5-medium | A+ (8.1min) | B- ($3.86) | — | — |
| typescript-bun | fable5-medium | B (10.0min) | D ($4.03) | — | — |
| powershell | fable5-medium | D- (14.4min) | D- ($4.10) | — | — |

</details>

<details>
<summary>Sorted by Cost tier (best-first), then avg of Duration/Tests/Workflow Craft tiers</summary>

| Language | Model | Duration | Cost | Tests Quality | Workflow Craft |
|----------|-------|----------|------|-----------|-------------|
| bash | fable5-medium | A+ (7.8min) | A+ ($3.70) | — | — |
| default | fable5-medium | A+ (8.1min) | B- ($3.86) | — | — |
| typescript-bun | fable5-medium | B (10.0min) | D ($4.03) | — | — |
| powershell | fable5-medium | D- (14.4min) | D- ($4.10) | — | — |

</details>

<details>
<summary>Sorted by Tests Quality tier (best-first; no-data last), then avg of other tiers</summary>

| Language | Model | Duration | Cost | Tests Quality | Workflow Craft |
|----------|-------|----------|------|-----------|-------------|
| bash | fable5-medium | A+ (7.8min) | A+ ($3.70) | — | — |
| default | fable5-medium | A+ (8.1min) | B- ($3.86) | — | — |
| typescript-bun | fable5-medium | B (10.0min) | D ($4.03) | — | — |
| powershell | fable5-medium | D- (14.4min) | D- ($4.10) | — | — |

</details>

<details>
<summary>Sorted by Workflow Craft tier (best-first; no-data last), then avg of other tiers</summary>

| Language | Model | Duration | Cost | Tests Quality | Workflow Craft |
|----------|-------|----------|------|-----------|-------------|
| bash | fable5-medium | A+ (7.8min) | A+ ($3.70) | — | — |
| default | fable5-medium | A+ (8.1min) | B- ($3.86) | — | — |
| typescript-bun | fable5-medium | B (10.0min) | D ($4.03) | — | — |
| powershell | fable5-medium | D- (14.4min) | D- ($4.10) | — | — |

</details>

- **Estimated time remaining:** 143.2min
- **Estimated total cost:** $110.04

## Comparison by Language/Model/Effort
*See [Notes](#notes) for scoring rubric and CLI version legend.*

| Language | Model | Runs | Avg Duration | Avg Duration Net of Traps | Avg Errors | Avg Turns | Avg Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| bash | fable5-medium | 3 | 7.8min | 5.9min | 1.3 | 40 | $3.70 | $11.09 | — | — |
| default | fable5-medium | 4 | 8.1min | 7.7min | 1.5 | 36 | $3.86 | $15.46 | — | — |
| powershell | fable5-medium | 4 | 14.4min | 14.4min | 3.0 | 32 | $4.10 | $16.38 | — | — |
| typescript-bun | fable5-medium | 3 | 10.0min | 7.3min | 0.0 | 43 | $4.03 | $12.09 | — | — |


<details>
<summary>Sorted by avg cost (cheapest first)</summary>

| Language | Model | Runs | Avg Duration | Avg Duration Net of Traps | Avg Errors | Avg Turns | Avg Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| bash | fable5-medium | 3 | 7.8min | 5.9min | 1.3 | 40 | $3.70 | $11.09 | — | — |
| default | fable5-medium | 4 | 8.1min | 7.7min | 1.5 | 36 | $3.86 | $15.46 | — | — |
| typescript-bun | fable5-medium | 3 | 10.0min | 7.3min | 0.0 | 43 | $4.03 | $12.09 | — | — |
| powershell | fable5-medium | 4 | 14.4min | 14.4min | 3.0 | 32 | $4.10 | $16.38 | — | — |

</details>

<details>
<summary>Sorted by avg duration (fastest first)</summary>

| Language | Model | Runs | Avg Duration | Avg Duration Net of Traps | Avg Errors | Avg Turns | Avg Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| bash | fable5-medium | 3 | 7.8min | 5.9min | 1.3 | 40 | $3.70 | $11.09 | — | — |
| default | fable5-medium | 4 | 8.1min | 7.7min | 1.5 | 36 | $3.86 | $15.46 | — | — |
| typescript-bun | fable5-medium | 3 | 10.0min | 7.3min | 0.0 | 43 | $4.03 | $12.09 | — | — |
| powershell | fable5-medium | 4 | 14.4min | 14.4min | 3.0 | 32 | $4.10 | $16.38 | — | — |

</details>

<details>
<summary>Sorted by avg duration net of traps (fastest first)</summary>

| Language | Model | Runs | Avg Duration | Avg Duration Net of Traps | Avg Errors | Avg Turns | Avg Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| bash | fable5-medium | 3 | 7.8min | 5.9min | 1.3 | 40 | $3.70 | $11.09 | — | — |
| typescript-bun | fable5-medium | 3 | 10.0min | 7.3min | 0.0 | 43 | $4.03 | $12.09 | — | — |
| default | fable5-medium | 4 | 8.1min | 7.7min | 1.5 | 36 | $3.86 | $15.46 | — | — |
| powershell | fable5-medium | 4 | 14.4min | 14.4min | 3.0 | 32 | $4.10 | $16.38 | — | — |

</details>

<details>
<summary>Sorted by avg errors (fewest first)</summary>

| Language | Model | Runs | Avg Duration | Avg Duration Net of Traps | Avg Errors | Avg Turns | Avg Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| typescript-bun | fable5-medium | 3 | 10.0min | 7.3min | 0.0 | 43 | $4.03 | $12.09 | — | — |
| bash | fable5-medium | 3 | 7.8min | 5.9min | 1.3 | 40 | $3.70 | $11.09 | — | — |
| default | fable5-medium | 4 | 8.1min | 7.7min | 1.5 | 36 | $3.86 | $15.46 | — | — |
| powershell | fable5-medium | 4 | 14.4min | 14.4min | 3.0 | 32 | $4.10 | $16.38 | — | — |

</details>

<details>
<summary>Sorted by avg turns (fewest first)</summary>

| Language | Model | Runs | Avg Duration | Avg Duration Net of Traps | Avg Errors | Avg Turns | Avg Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| powershell | fable5-medium | 4 | 14.4min | 14.4min | 3.0 | 32 | $4.10 | $16.38 | — | — |
| default | fable5-medium | 4 | 8.1min | 7.7min | 1.5 | 36 | $3.86 | $15.46 | — | — |
| bash | fable5-medium | 3 | 7.8min | 5.9min | 1.3 | 40 | $3.70 | $11.09 | — | — |
| typescript-bun | fable5-medium | 3 | 10.0min | 7.3min | 0.0 | 43 | $4.03 | $12.09 | — | — |

</details>

<details>
<summary>Sorted by LLM-as-judge score (best first)</summary>

| Language | Model | Runs | Avg Duration | Avg Duration Net of Traps | Avg Errors | Avg Turns | Avg Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| bash | fable5-medium | 3 | 7.8min | 5.9min | 1.3 | 40 | $3.70 | $11.09 | — | — |
| default | fable5-medium | 4 | 8.1min | 7.7min | 1.5 | 36 | $3.86 | $15.46 | — | — |
| powershell | fable5-medium | 4 | 14.4min | 14.4min | 3.0 | 32 | $4.10 | $16.38 | — | — |
| typescript-bun | fable5-medium | 3 | 10.0min | 7.3min | 0.0 | 43 | $4.03 | $12.09 | — | — |

</details>

<details>
<summary>Sorted by deliverable-quality score (best first)</summary>

| Language | Model | Runs | Avg Duration | Avg Duration Net of Traps | Avg Errors | Avg Turns | Avg Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| bash | fable5-medium | 3 | 7.8min | 5.9min | 1.3 | 40 | $3.70 | $11.09 | — | — |
| default | fable5-medium | 4 | 8.1min | 7.7min | 1.5 | 36 | $3.86 | $15.46 | — | — |
| powershell | fable5-medium | 4 | 14.4min | 14.4min | 3.0 | 32 | $4.10 | $16.38 | — | — |
| typescript-bun | fable5-medium | 3 | 10.0min | 7.3min | 0.0 | 43 | $4.03 | $12.09 | — | — |

</details>

## Savings Analysis

### Hook Savings by Language/Model/Effort

Each hook-caught error avoids one test run that would otherwise have been needed to discover it.
Every hook fire (hit or miss) costs execution time for the syntax/type checker.

*`% of Test Time Saved` = `net / (net + test_time) × 100` — the share of total (would-have-been + actually-spent) test time that hooks eliminated. Bounded in (-∞, 100%) without an artificial cap; near 100% means hooks substituted for almost all of the hypothetical test work.*

| Language | Model | Fires | Caught | Rate | Gross Saved | % of Time | Overhead | % of Time | Net Saved | % of Time | Test Run Time | % of Test Time Saved |
|------|-------|-------|--------|------|------------|-----------|----------|-----------|-----------|-----------|---------------|----------------------|
| bash | fable5-medium-cli2.1.198 | 57 | 2 | 3.5% | 0.4min | 0.3% | 0.0min | 0.0% | 0.4min | 0.2% | 3.9min | 8.2% |
| default | fable5-medium-cli2.1.198 | 71 | 0 | 0.0% | 0.0min | 0.0% | 0.1min | 0.1% | -0.1min | -0.1% | 3.1min | -4.7% |
| powershell | fable5-medium-cli2.1.198 | 69 | 8 | 11.6% | 4.7min | 3.3% | 9.9min | 6.9% | -5.2min | -3.6% | 3.7min | 339.3% |
| typescript-bun | fable5-medium-cli2.1.198 | 74 | 34 | 45.9% | 4.5min | 3.2% | 3.0min | 2.1% | 1.5min | 1.1% | 4.5min | 25.7% |


<details>
<summary>Sorted by net saved (most first)</summary>

| Language | Model | Fires | Caught | Rate | Gross Saved | % of Time | Overhead | % of Time | Net Saved | % of Time | Test Run Time | % of Test Time Saved |
|------|-------|-------|--------|------|------------|-----------|----------|-----------|-----------|-----------|---------------|----------------------|
| typescript-bun | fable5-medium-cli2.1.198 | 74 | 34 | 45.9% | 4.5min | 3.2% | 3.0min | 2.1% | 1.5min | 1.1% | 4.5min | 25.7% |
| bash | fable5-medium-cli2.1.198 | 57 | 2 | 3.5% | 0.4min | 0.3% | 0.0min | 0.0% | 0.4min | 0.2% | 3.9min | 8.2% |
| default | fable5-medium-cli2.1.198 | 71 | 0 | 0.0% | 0.0min | 0.0% | 0.1min | 0.1% | -0.1min | -0.1% | 3.1min | -4.7% |
| powershell | fable5-medium-cli2.1.198 | 69 | 8 | 11.6% | 4.7min | 3.3% | 9.9min | 6.9% | -5.2min | -3.6% | 3.7min | 339.3% |

</details>

<details>
<summary>Sorted by net % of test time saved (most first)</summary>

| Language | Model | Fires | Caught | Rate | Gross Saved | % of Time | Overhead | % of Time | Net Saved | % of Time | Test Run Time | % of Test Time Saved |
|------|-------|-------|--------|------|------------|-----------|----------|-----------|-----------|-----------|---------------|----------------------|
| powershell | fable5-medium-cli2.1.198 | 69 | 8 | 11.6% | 4.7min | 3.3% | 9.9min | 6.9% | -5.2min | -3.6% | 3.7min | 339.3% |
| typescript-bun | fable5-medium-cli2.1.198 | 74 | 34 | 45.9% | 4.5min | 3.2% | 3.0min | 2.1% | 1.5min | 1.1% | 4.5min | 25.7% |
| bash | fable5-medium-cli2.1.198 | 57 | 2 | 3.5% | 0.4min | 0.3% | 0.0min | 0.0% | 0.4min | 0.2% | 3.9min | 8.2% |
| default | fable5-medium-cli2.1.198 | 71 | 0 | 0.0% | 0.0min | 0.0% | 0.1min | 0.1% | -0.1min | -0.1% | 3.1min | -4.7% |

</details>

<details>
<summary>Sorted by catch rate (highest first)</summary>

| Language | Model | Fires | Caught | Rate | Gross Saved | % of Time | Overhead | % of Time | Net Saved | % of Time | Test Run Time | % of Test Time Saved |
|------|-------|-------|--------|------|------------|-----------|----------|-----------|-----------|-----------|---------------|----------------------|
| typescript-bun | fable5-medium-cli2.1.198 | 74 | 34 | 45.9% | 4.5min | 3.2% | 3.0min | 2.1% | 1.5min | 1.1% | 4.5min | 25.7% |
| powershell | fable5-medium-cli2.1.198 | 69 | 8 | 11.6% | 4.7min | 3.3% | 9.9min | 6.9% | -5.2min | -3.6% | 3.7min | 339.3% |
| bash | fable5-medium-cli2.1.198 | 57 | 2 | 3.5% | 0.4min | 0.3% | 0.0min | 0.0% | 0.4min | 0.2% | 3.9min | 8.2% |
| default | fable5-medium-cli2.1.198 | 71 | 0 | 0.0% | 0.0min | 0.0% | 0.1min | 0.1% | -0.1min | -0.1% | 3.1min | -4.7% |

</details>

### Trap Analysis by Language/Model/Effort/Category

| Trap | Language | Model | Fell In | Time Lost | % of Time | $ Lost | % of $ |
|------|------|-------|---------|-----------|-----------|--------|--------|
| repeated-test-reruns | bash | fable5-medium-cli2.1.198 | 3 | 5.7min | 4.0% | $2.69 | 4.90% |
| repeated-test-reruns | default | fable5-medium-cli2.1.198 | 1 | 1.0min | 0.7% | $0.45 | 0.82% |
| repeated-test-reruns | typescript-bun | fable5-medium-cli2.1.198 | 1 | 1.3min | 0.9% | $0.51 | 0.92% |
| ts-type-error-fix-cycles | typescript-bun | fable5-medium-cli2.1.198 | 3 | 6.8min | 4.7% | $2.81 | 5.11% |
| fixture-rework | default | fable5-medium-cli2.1.198 | 1 | 0.8min | 0.5% | $0.35 | 0.63% |


<details>
<summary>Sorted by time lost (least first)</summary>

| Trap | Language | Model | Fell In | Time Lost | % of Time | $ Lost | % of $ |
|------|------|-------|---------|-----------|-----------|--------|--------|
| fixture-rework | default | fable5-medium-cli2.1.198 | 1 | 0.8min | 0.5% | $0.35 | 0.63% |
| repeated-test-reruns | default | fable5-medium-cli2.1.198 | 1 | 1.0min | 0.7% | $0.45 | 0.82% |
| repeated-test-reruns | typescript-bun | fable5-medium-cli2.1.198 | 1 | 1.3min | 0.9% | $0.51 | 0.92% |
| repeated-test-reruns | bash | fable5-medium-cli2.1.198 | 3 | 5.7min | 4.0% | $2.69 | 4.90% |
| ts-type-error-fix-cycles | typescript-bun | fable5-medium-cli2.1.198 | 3 | 6.8min | 4.7% | $2.81 | 5.11% |

</details>

<details>
<summary>Sorted by $ lost (least first)</summary>

| Trap | Language | Model | Fell In | Time Lost | % of Time | $ Lost | % of $ |
|------|------|-------|---------|-----------|-----------|--------|--------|
| fixture-rework | default | fable5-medium-cli2.1.198 | 1 | 0.8min | 0.5% | $0.35 | 0.63% |
| repeated-test-reruns | default | fable5-medium-cli2.1.198 | 1 | 1.0min | 0.7% | $0.45 | 0.82% |
| repeated-test-reruns | typescript-bun | fable5-medium-cli2.1.198 | 1 | 1.3min | 0.9% | $0.51 | 0.92% |
| repeated-test-reruns | bash | fable5-medium-cli2.1.198 | 3 | 5.7min | 4.0% | $2.69 | 4.90% |
| ts-type-error-fix-cycles | typescript-bun | fable5-medium-cli2.1.198 | 3 | 6.8min | 4.7% | $2.81 | 5.11% |

</details>

<details>
<summary>Sorted by fell-in count (fewest first)</summary>

| Trap | Language | Model | Fell In | Time Lost | % of Time | $ Lost | % of $ |
|------|------|-------|---------|-----------|-----------|--------|--------|
| repeated-test-reruns | default | fable5-medium-cli2.1.198 | 1 | 1.0min | 0.7% | $0.45 | 0.82% |
| repeated-test-reruns | typescript-bun | fable5-medium-cli2.1.198 | 1 | 1.3min | 0.9% | $0.51 | 0.92% |
| fixture-rework | default | fable5-medium-cli2.1.198 | 1 | 0.8min | 0.5% | $0.35 | 0.63% |
| repeated-test-reruns | bash | fable5-medium-cli2.1.198 | 3 | 5.7min | 4.0% | $2.69 | 4.90% |
| ts-type-error-fix-cycles | typescript-bun | fable5-medium-cli2.1.198 | 3 | 6.8min | 4.7% | $2.81 | 5.11% |

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
| bash | fable5-medium-cli2.1.198 | 3 | 3 | 5.7min | 4.0% | $2.69 | 4.90% |
| default | fable5-medium-cli2.1.198 | 4 | 2 | 1.8min | 1.2% | $0.80 | 1.45% |
| powershell | fable5-medium-cli2.1.198 | 4 | 0 | 0.0min | 0.0% | $0.00 | 0.00% |
| typescript-bun | fable5-medium-cli2.1.198 | 3 | 4 | 8.1min | 5.7% | $3.32 | 6.03% |


<details>
<summary>Sorted by time lost (least first)</summary>

| Language | Model | Runs | Traps | Time Lost | % of Time | $ Lost | % of $ |
|------|-------|------|-------|-----------|-----------|--------|--------|
| powershell | fable5-medium-cli2.1.198 | 4 | 0 | 0.0min | 0.0% | $0.00 | 0.00% |
| default | fable5-medium-cli2.1.198 | 4 | 2 | 1.8min | 1.2% | $0.80 | 1.45% |
| bash | fable5-medium-cli2.1.198 | 3 | 3 | 5.7min | 4.0% | $2.69 | 4.90% |
| typescript-bun | fable5-medium-cli2.1.198 | 3 | 4 | 8.1min | 5.7% | $3.32 | 6.03% |

</details>

<details>
<summary>Sorted by $ lost (least first)</summary>

| Language | Model | Runs | Traps | Time Lost | % of Time | $ Lost | % of $ |
|------|-------|------|-------|-----------|-----------|--------|--------|
| powershell | fable5-medium-cli2.1.198 | 4 | 0 | 0.0min | 0.0% | $0.00 | 0.00% |
| default | fable5-medium-cli2.1.198 | 4 | 2 | 1.8min | 1.2% | $0.80 | 1.45% |
| bash | fable5-medium-cli2.1.198 | 3 | 3 | 5.7min | 4.0% | $2.69 | 4.90% |
| typescript-bun | fable5-medium-cli2.1.198 | 3 | 4 | 8.1min | 5.7% | $3.32 | 6.03% |

</details>

### Prompt Cache Savings

| Status | Runs | $ Saved | % of $ |
|--------|------|---------|--------|
| Full hit (100%) | 0 | $0.00 | 0.00% |
| Partial | 13 | $2.74 | 4.98% |
| Miss | 1 | $0.00 | 0.00% |

## Test Quality Evaluation

### Structural Metrics by Language/Model/Effort

Automated analysis of test files: test count, assertion count, and test-to-code line ratio.

| Language | Model | Avg Tests | Avg Assertions | Avg Assert/Test | Avg Test:Code Ratio |
|------|-------|-----------|----------------|-----------------|---------------------|
| bash | fable5-medium | 25.3 | 44.0 | 1.7 | 0.79 |
| default | fable5-medium | 19.5 | 34.2 | 1.8 | 0.91 |
| powershell | fable5-medium | 40.2 | 69.2 | 1.7 | 6.46 |
| typescript-bun | fable5-medium | 35.7 | 63.0 | 1.8 | 1.31 |


<details>
<summary>Sorted by avg tests (most first)</summary>

| Language | Model | Avg Tests | Avg Assertions | Avg Assert/Test | Avg Test:Code Ratio |
|------|-------|-----------|----------------|-----------------|---------------------|
| powershell | fable5-medium | 40.2 | 69.2 | 1.7 | 6.46 |
| typescript-bun | fable5-medium | 35.7 | 63.0 | 1.8 | 1.31 |
| bash | fable5-medium | 25.3 | 44.0 | 1.7 | 0.79 |
| default | fable5-medium | 19.5 | 34.2 | 1.8 | 0.91 |

</details>

<details>
<summary>Sorted by avg assertions (most first)</summary>

| Language | Model | Avg Tests | Avg Assertions | Avg Assert/Test | Avg Test:Code Ratio |
|------|-------|-----------|----------------|-----------------|---------------------|
| powershell | fable5-medium | 40.2 | 69.2 | 1.7 | 6.46 |
| typescript-bun | fable5-medium | 35.7 | 63.0 | 1.8 | 1.31 |
| bash | fable5-medium | 25.3 | 44.0 | 1.7 | 0.79 |
| default | fable5-medium | 19.5 | 34.2 | 1.8 | 0.91 |

</details>

<details>
<summary>Sorted by avg test:code ratio (highest first)</summary>

| Language | Model | Avg Tests | Avg Assertions | Avg Assert/Test | Avg Test:Code Ratio |
|------|-------|-----------|----------------|-----------------|---------------------|
| powershell | fable5-medium | 40.2 | 69.2 | 1.7 | 6.46 |
| typescript-bun | fable5-medium | 35.7 | 63.0 | 1.8 | 1.31 |
| default | fable5-medium | 19.5 | 34.2 | 1.8 | 0.91 |
| bash | fable5-medium | 25.3 | 44.0 | 1.7 | 0.79 |

</details>


<details>
<summary>Per-run structural metrics</summary>

| Task | Language | Model | Tests | Assertions | Assert/Test | Test Lines | Impl Lines | Test:Code |
|------|------|-------|-------|------------|-------------|------------|------------|-----------|
| Semantic Version Bumper | default | fable5-medium | 0 | 0 | 0.0 | 95 | 0 | 0.00 |
| Semantic Version Bumper | powershell | fable5-medium | 43 | 79 | 1.8 | 471 | 45 | 10.47 |
| Semantic Version Bumper | bash | fable5-medium | 32 | 57 | 1.8 | 269 | 274 | 0.98 |
| Semantic Version Bumper | typescript-bun | fable5-medium | 41 | 66 | 1.6 | 365 | 504 | 0.72 |
| PR Label Assigner | default | fable5-medium | 28 | 45 | 1.6 | 314 | 163 | 1.93 |
| PR Label Assigner | powershell | fable5-medium | 37 | 47 | 1.3 | 299 | 170 | 1.76 |
| PR Label Assigner | bash | fable5-medium | 25 | 39 | 1.6 | 215 | 276 | 0.78 |
| PR Label Assigner | typescript-bun | fable5-medium | 32 | 73 | 2.3 | 511 | 214 | 2.39 |
| Dependency License Checker | default | fable5-medium | 24 | 33 | 1.4 | 312 | 360 | 0.87 |
| Dependency License Checker | powershell | fable5-medium | 38 | 65 | 1.7 | 480 | 79 | 6.08 |
| Dependency License Checker | bash | fable5-medium | 19 | 36 | 1.9 | 158 | 257 | 0.61 |
| Dependency License Checker | typescript-bun | fable5-medium | 34 | 50 | 1.5 | 422 | 510 | 0.83 |
| Test Results Aggregator | default | fable5-medium | 26 | 59 | 2.3 | 345 | 420 | 0.82 |
| Test Results Aggregator | powershell | fable5-medium | 43 | 86 | 2.0 | 497 | 66 | 7.53 |

</details>

## Per-Run Results

*Tests Quality = Overall (1-5) from LLM-as-judge of generated test code (dimensions: coverage, rigor, design). `—` = no judge data.*

| Task | Language | Model | Duration | Turns | Errors | Cost | Tests Quality | Chosen | Status |
|------|----------|-------|----------|-------|--------|------|-----------|--------|--------|
| Dependency License Checker | bash | fable5-medium | 6.3min | 36 | 1 | $2.95 | — | bash | ok |
| Dependency License Checker | default | fable5-medium | 6.8min | 29 | 2 | $2.90 | — | python | ok |
| Dependency License Checker | powershell | fable5-medium | 11.2min | 20 | 2 | $3.23 | — | powershell | ok |
| Dependency License Checker | typescript-bun | fable5-medium | 9.2min | 46 | 0 | $4.24 | — | typescript | ok |
| PR Label Assigner | bash | fable5-medium | 8.6min | 46 | 2 | $4.15 | — | bash | ok |
| PR Label Assigner | default | fable5-medium | 6.8min | 35 | 1 | $3.04 | — | python | ok |
| PR Label Assigner | powershell | fable5-medium | 12.0min | 32 | 1 | $3.41 | — | powershell | ok |
| PR Label Assigner | typescript-bun | fable5-medium | 11.9min | 46 | 0 | $4.46 | — | typescript | ok |
| Semantic Version Bumper | bash | fable5-medium | 8.4min | 39 | 1 | $3.99 | — | bash | ok |
| Semantic Version Bumper | default | fable5-medium | 9.1min | 35 | 2 | $4.21 | — | javascript | ok |
| Semantic Version Bumper | powershell | fable5-medium | 19.0min | 36 | 4 | $4.65 | — | powershell | ok |
| Semantic Version Bumper | typescript-bun | fable5-medium | 8.9min | 36 | 0 | $3.39 | — | typescript | ok |
| Test Results Aggregator | default | fable5-medium | 9.8min | 47 | 1 | $5.30 | — | python | ok |
| Test Results Aggregator | powershell | fable5-medium | 15.2min | 40 | 5 | $5.09 | — | powershell | ok |


<details>
<summary>Sorted by cost (cheapest first)</summary>

| Task | Language | Model | Duration | Turns | Errors | Cost | Tests Quality | Chosen | Status |
|------|----------|-------|----------|-------|--------|------|-----------|--------|--------|
| Dependency License Checker | default | fable5-medium | 6.8min | 29 | 2 | $2.90 | — | python | ok |
| Dependency License Checker | bash | fable5-medium | 6.3min | 36 | 1 | $2.95 | — | bash | ok |
| PR Label Assigner | default | fable5-medium | 6.8min | 35 | 1 | $3.04 | — | python | ok |
| Dependency License Checker | powershell | fable5-medium | 11.2min | 20 | 2 | $3.23 | — | powershell | ok |
| Semantic Version Bumper | typescript-bun | fable5-medium | 8.9min | 36 | 0 | $3.39 | — | typescript | ok |
| PR Label Assigner | powershell | fable5-medium | 12.0min | 32 | 1 | $3.41 | — | powershell | ok |
| Semantic Version Bumper | bash | fable5-medium | 8.4min | 39 | 1 | $3.99 | — | bash | ok |
| PR Label Assigner | bash | fable5-medium | 8.6min | 46 | 2 | $4.15 | — | bash | ok |
| Semantic Version Bumper | default | fable5-medium | 9.1min | 35 | 2 | $4.21 | — | javascript | ok |
| Dependency License Checker | typescript-bun | fable5-medium | 9.2min | 46 | 0 | $4.24 | — | typescript | ok |
| PR Label Assigner | typescript-bun | fable5-medium | 11.9min | 46 | 0 | $4.46 | — | typescript | ok |
| Semantic Version Bumper | powershell | fable5-medium | 19.0min | 36 | 4 | $4.65 | — | powershell | ok |
| Test Results Aggregator | powershell | fable5-medium | 15.2min | 40 | 5 | $5.09 | — | powershell | ok |
| Test Results Aggregator | default | fable5-medium | 9.8min | 47 | 1 | $5.30 | — | python | ok |

</details>

<details>
<summary>Sorted by duration (fastest first)</summary>

| Task | Language | Model | Duration | Turns | Errors | Cost | Tests Quality | Chosen | Status |
|------|----------|-------|----------|-------|--------|------|-----------|--------|--------|
| Dependency License Checker | bash | fable5-medium | 6.3min | 36 | 1 | $2.95 | — | bash | ok |
| PR Label Assigner | default | fable5-medium | 6.8min | 35 | 1 | $3.04 | — | python | ok |
| Dependency License Checker | default | fable5-medium | 6.8min | 29 | 2 | $2.90 | — | python | ok |
| Semantic Version Bumper | bash | fable5-medium | 8.4min | 39 | 1 | $3.99 | — | bash | ok |
| PR Label Assigner | bash | fable5-medium | 8.6min | 46 | 2 | $4.15 | — | bash | ok |
| Semantic Version Bumper | typescript-bun | fable5-medium | 8.9min | 36 | 0 | $3.39 | — | typescript | ok |
| Semantic Version Bumper | default | fable5-medium | 9.1min | 35 | 2 | $4.21 | — | javascript | ok |
| Dependency License Checker | typescript-bun | fable5-medium | 9.2min | 46 | 0 | $4.24 | — | typescript | ok |
| Test Results Aggregator | default | fable5-medium | 9.8min | 47 | 1 | $5.30 | — | python | ok |
| Dependency License Checker | powershell | fable5-medium | 11.2min | 20 | 2 | $3.23 | — | powershell | ok |
| PR Label Assigner | typescript-bun | fable5-medium | 11.9min | 46 | 0 | $4.46 | — | typescript | ok |
| PR Label Assigner | powershell | fable5-medium | 12.0min | 32 | 1 | $3.41 | — | powershell | ok |
| Test Results Aggregator | powershell | fable5-medium | 15.2min | 40 | 5 | $5.09 | — | powershell | ok |
| Semantic Version Bumper | powershell | fable5-medium | 19.0min | 36 | 4 | $4.65 | — | powershell | ok |

</details>

<details>
<summary>Sorted by errors (fewest first)</summary>

| Task | Language | Model | Duration | Turns | Errors | Cost | Tests Quality | Chosen | Status |
|------|----------|-------|----------|-------|--------|------|-----------|--------|--------|
| Semantic Version Bumper | typescript-bun | fable5-medium | 8.9min | 36 | 0 | $3.39 | — | typescript | ok |
| PR Label Assigner | typescript-bun | fable5-medium | 11.9min | 46 | 0 | $4.46 | — | typescript | ok |
| Dependency License Checker | typescript-bun | fable5-medium | 9.2min | 46 | 0 | $4.24 | — | typescript | ok |
| Semantic Version Bumper | bash | fable5-medium | 8.4min | 39 | 1 | $3.99 | — | bash | ok |
| PR Label Assigner | default | fable5-medium | 6.8min | 35 | 1 | $3.04 | — | python | ok |
| PR Label Assigner | powershell | fable5-medium | 12.0min | 32 | 1 | $3.41 | — | powershell | ok |
| Dependency License Checker | bash | fable5-medium | 6.3min | 36 | 1 | $2.95 | — | bash | ok |
| Test Results Aggregator | default | fable5-medium | 9.8min | 47 | 1 | $5.30 | — | python | ok |
| Semantic Version Bumper | default | fable5-medium | 9.1min | 35 | 2 | $4.21 | — | javascript | ok |
| PR Label Assigner | bash | fable5-medium | 8.6min | 46 | 2 | $4.15 | — | bash | ok |
| Dependency License Checker | default | fable5-medium | 6.8min | 29 | 2 | $2.90 | — | python | ok |
| Dependency License Checker | powershell | fable5-medium | 11.2min | 20 | 2 | $3.23 | — | powershell | ok |
| Semantic Version Bumper | powershell | fable5-medium | 19.0min | 36 | 4 | $4.65 | — | powershell | ok |
| Test Results Aggregator | powershell | fable5-medium | 15.2min | 40 | 5 | $5.09 | — | powershell | ok |

</details>

<details>
<summary>Sorted by turns (fewest first)</summary>

| Task | Language | Model | Duration | Turns | Errors | Cost | Tests Quality | Chosen | Status |
|------|----------|-------|----------|-------|--------|------|-----------|--------|--------|
| Dependency License Checker | powershell | fable5-medium | 11.2min | 20 | 2 | $3.23 | — | powershell | ok |
| Dependency License Checker | default | fable5-medium | 6.8min | 29 | 2 | $2.90 | — | python | ok |
| PR Label Assigner | powershell | fable5-medium | 12.0min | 32 | 1 | $3.41 | — | powershell | ok |
| Semantic Version Bumper | default | fable5-medium | 9.1min | 35 | 2 | $4.21 | — | javascript | ok |
| PR Label Assigner | default | fable5-medium | 6.8min | 35 | 1 | $3.04 | — | python | ok |
| Semantic Version Bumper | powershell | fable5-medium | 19.0min | 36 | 4 | $4.65 | — | powershell | ok |
| Semantic Version Bumper | typescript-bun | fable5-medium | 8.9min | 36 | 0 | $3.39 | — | typescript | ok |
| Dependency License Checker | bash | fable5-medium | 6.3min | 36 | 1 | $2.95 | — | bash | ok |
| Semantic Version Bumper | bash | fable5-medium | 8.4min | 39 | 1 | $3.99 | — | bash | ok |
| Test Results Aggregator | powershell | fable5-medium | 15.2min | 40 | 5 | $5.09 | — | powershell | ok |
| PR Label Assigner | bash | fable5-medium | 8.6min | 46 | 2 | $4.15 | — | bash | ok |
| PR Label Assigner | typescript-bun | fable5-medium | 11.9min | 46 | 0 | $4.46 | — | typescript | ok |
| Dependency License Checker | typescript-bun | fable5-medium | 9.2min | 46 | 0 | $4.24 | — | typescript | ok |
| Test Results Aggregator | default | fable5-medium | 9.8min | 47 | 1 | $5.30 | — | python | ok |

</details>

<details>
<summary>Sorted by LLM-as-judge score (best first)</summary>

| Task | Language | Model | Duration | Turns | Errors | Cost | Tests Quality | Chosen | Status |
|------|----------|-------|----------|-------|--------|------|-----------|--------|--------|
| Semantic Version Bumper | default | fable5-medium | 9.1min | 35 | 2 | $4.21 | — | javascript | ok |
| Semantic Version Bumper | powershell | fable5-medium | 19.0min | 36 | 4 | $4.65 | — | powershell | ok |
| Semantic Version Bumper | bash | fable5-medium | 8.4min | 39 | 1 | $3.99 | — | bash | ok |
| Semantic Version Bumper | typescript-bun | fable5-medium | 8.9min | 36 | 0 | $3.39 | — | typescript | ok |
| PR Label Assigner | default | fable5-medium | 6.8min | 35 | 1 | $3.04 | — | python | ok |
| PR Label Assigner | powershell | fable5-medium | 12.0min | 32 | 1 | $3.41 | — | powershell | ok |
| PR Label Assigner | bash | fable5-medium | 8.6min | 46 | 2 | $4.15 | — | bash | ok |
| PR Label Assigner | typescript-bun | fable5-medium | 11.9min | 46 | 0 | $4.46 | — | typescript | ok |
| Dependency License Checker | default | fable5-medium | 6.8min | 29 | 2 | $2.90 | — | python | ok |
| Dependency License Checker | powershell | fable5-medium | 11.2min | 20 | 2 | $3.23 | — | powershell | ok |
| Dependency License Checker | bash | fable5-medium | 6.3min | 36 | 1 | $2.95 | — | bash | ok |
| Dependency License Checker | typescript-bun | fable5-medium | 9.2min | 46 | 0 | $4.24 | — | typescript | ok |
| Test Results Aggregator | default | fable5-medium | 9.8min | 47 | 1 | $5.30 | — | python | ok |
| Test Results Aggregator | powershell | fable5-medium | 15.2min | 40 | 5 | $5.09 | — | powershell | ok |

</details>

## Notes

### Tiers

- **Duration bands:** **A+** ≤1.05×, **A** ≤1.11×, **A-** ≤1.17×, **B+** ≤1.23×, **B** ≤1.29×, **B-** ≤1.36×, **C+** ≤1.43×, **C** ≤1.51×, **C-** ≤1.59×, **D+** ≤1.67×, **D** ≤1.76×, **D-** ≤1.85×, **F** >1.85×
- **Cost bands:** **A+** ≤1.01×, **A** ≤1.02×, **A-** ≤1.03×, **B+** ≤1.03×, **B** ≤1.04×, **B-** ≤1.05×, **C+** ≤1.06×, **C** ≤1.07×, **C-** ≤1.08×, **D+** ≤1.09×, **D** ≤1.10×, **D-** ≤1.11×, **F** >1.11×

*Tests/Workflow Craft bands are absolute Overall score bands:* **A+** ≥4.7, **A** ≥4.4, **A-** ≥4.1, **B+** ≥3.8, **B** ≥3.5, **B-** ≥3.2, **C+** ≥2.9, **C** ≥2.6, **C-** ≥2.3, **D+** ≥2.0, **D** ≥1.7, **D-** ≥1.4, **F** <1.4, `—` = no data.*

### CLI Version Legend

| Variant label | CLI version | Tasks | Languages |
|---------------|-------------|-------|-----------|
| fable5-medium | 2.1.198 | All | All |

---
*Generated by generate_results.py — benchmark instructions v4*