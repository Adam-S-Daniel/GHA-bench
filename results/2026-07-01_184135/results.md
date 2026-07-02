# Benchmark Results: Language Comparison

**Last updated:** 2026-07-01 11:02:04 PM ET — 25/28 runs completed, 3 remaining; total cost $105.19; total agent time 259.0 min.
**Claude Code versions used:** v2.1.198 (25 runs). Each link goes to a per-version snapshot of the system prompt, default-tool descriptions, and the chronological Anthropic changelog up to that version. Regenerate with `python3 version_docs.py`.

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
| bash | fable5-medium | A+ (7.7min) | A+ ($3.58) | — | — |
| default | fable5-medium | A- (8.9min) | B- ($4.05) | — | — |
| typescript-bun | fable5-medium | B- (10.5min) | D- ($4.62) | — | — |
| powershell | fable5-medium | D- (14.5min) | D- ($4.60) | — | — |


<details>
<summary>Sorted by Duration tier (best-first), then avg of Cost/Tests/Workflow Craft tiers</summary>

| Language | Model | Duration | Cost | Tests Quality | Workflow Craft |
|----------|-------|----------|------|-----------|-------------|
| bash | fable5-medium | A+ (7.7min) | A+ ($3.58) | — | — |
| default | fable5-medium | A- (8.9min) | B- ($4.05) | — | — |
| typescript-bun | fable5-medium | B- (10.5min) | D- ($4.62) | — | — |
| powershell | fable5-medium | D- (14.5min) | D- ($4.60) | — | — |

</details>

<details>
<summary>Sorted by Cost tier (best-first), then avg of Duration/Tests/Workflow Craft tiers</summary>

| Language | Model | Duration | Cost | Tests Quality | Workflow Craft |
|----------|-------|----------|------|-----------|-------------|
| bash | fable5-medium | A+ (7.7min) | A+ ($3.58) | — | — |
| default | fable5-medium | A- (8.9min) | B- ($4.05) | — | — |
| typescript-bun | fable5-medium | B- (10.5min) | D- ($4.62) | — | — |
| powershell | fable5-medium | D- (14.5min) | D- ($4.60) | — | — |

</details>

<details>
<summary>Sorted by Tests Quality tier (best-first; no-data last), then avg of other tiers</summary>

| Language | Model | Duration | Cost | Tests Quality | Workflow Craft |
|----------|-------|----------|------|-----------|-------------|
| bash | fable5-medium | A+ (7.7min) | A+ ($3.58) | — | — |
| default | fable5-medium | A- (8.9min) | B- ($4.05) | — | — |
| typescript-bun | fable5-medium | B- (10.5min) | D- ($4.62) | — | — |
| powershell | fable5-medium | D- (14.5min) | D- ($4.60) | — | — |

</details>

<details>
<summary>Sorted by Workflow Craft tier (best-first; no-data last), then avg of other tiers</summary>

| Language | Model | Duration | Cost | Tests Quality | Workflow Craft |
|----------|-------|----------|------|-----------|-------------|
| bash | fable5-medium | A+ (7.7min) | A+ ($3.58) | — | — |
| default | fable5-medium | A- (8.9min) | B- ($4.05) | — | — |
| typescript-bun | fable5-medium | B- (10.5min) | D- ($4.62) | — | — |
| powershell | fable5-medium | D- (14.5min) | D- ($4.60) | — | — |

</details>

- **Estimated time remaining:** 31.1min
- **Estimated total cost:** $117.82

## Comparison by Language/Model/Effort
*See [Notes](#notes) for scoring rubric and CLI version legend.*

| Language | Model | Runs | Avg Duration | Avg Duration Net of Traps | Avg Errors | Avg Turns | Avg Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| bash | fable5-medium | 6 | 7.7min | 6.8min | 2.2 | 37 | $3.58 | $21.49 | — | — |
| default | fable5-medium | 7 | 8.9min | 7.6min | 1.1 | 40 | $4.05 | $28.38 | — | — |
| powershell | fable5-medium | 6 | 14.5min | 14.1min | 3.2 | 35 | $4.60 | $27.58 | — | — |
| typescript-bun | fable5-medium | 6 | 10.5min | 8.1min | 0.5 | 44 | $4.62 | $27.74 | — | — |


<details>
<summary>Sorted by avg cost (cheapest first)</summary>

| Language | Model | Runs | Avg Duration | Avg Duration Net of Traps | Avg Errors | Avg Turns | Avg Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| bash | fable5-medium | 6 | 7.7min | 6.8min | 2.2 | 37 | $3.58 | $21.49 | — | — |
| default | fable5-medium | 7 | 8.9min | 7.6min | 1.1 | 40 | $4.05 | $28.38 | — | — |
| powershell | fable5-medium | 6 | 14.5min | 14.1min | 3.2 | 35 | $4.60 | $27.58 | — | — |
| typescript-bun | fable5-medium | 6 | 10.5min | 8.1min | 0.5 | 44 | $4.62 | $27.74 | — | — |

</details>

<details>
<summary>Sorted by avg duration (fastest first)</summary>

| Language | Model | Runs | Avg Duration | Avg Duration Net of Traps | Avg Errors | Avg Turns | Avg Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| bash | fable5-medium | 6 | 7.7min | 6.8min | 2.2 | 37 | $3.58 | $21.49 | — | — |
| default | fable5-medium | 7 | 8.9min | 7.6min | 1.1 | 40 | $4.05 | $28.38 | — | — |
| typescript-bun | fable5-medium | 6 | 10.5min | 8.1min | 0.5 | 44 | $4.62 | $27.74 | — | — |
| powershell | fable5-medium | 6 | 14.5min | 14.1min | 3.2 | 35 | $4.60 | $27.58 | — | — |

</details>

<details>
<summary>Sorted by avg duration net of traps (fastest first)</summary>

| Language | Model | Runs | Avg Duration | Avg Duration Net of Traps | Avg Errors | Avg Turns | Avg Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| bash | fable5-medium | 6 | 7.7min | 6.8min | 2.2 | 37 | $3.58 | $21.49 | — | — |
| default | fable5-medium | 7 | 8.9min | 7.6min | 1.1 | 40 | $4.05 | $28.38 | — | — |
| typescript-bun | fable5-medium | 6 | 10.5min | 8.1min | 0.5 | 44 | $4.62 | $27.74 | — | — |
| powershell | fable5-medium | 6 | 14.5min | 14.1min | 3.2 | 35 | $4.60 | $27.58 | — | — |

</details>

<details>
<summary>Sorted by avg errors (fewest first)</summary>

| Language | Model | Runs | Avg Duration | Avg Duration Net of Traps | Avg Errors | Avg Turns | Avg Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| typescript-bun | fable5-medium | 6 | 10.5min | 8.1min | 0.5 | 44 | $4.62 | $27.74 | — | — |
| default | fable5-medium | 7 | 8.9min | 7.6min | 1.1 | 40 | $4.05 | $28.38 | — | — |
| bash | fable5-medium | 6 | 7.7min | 6.8min | 2.2 | 37 | $3.58 | $21.49 | — | — |
| powershell | fable5-medium | 6 | 14.5min | 14.1min | 3.2 | 35 | $4.60 | $27.58 | — | — |

</details>

<details>
<summary>Sorted by avg turns (fewest first)</summary>

| Language | Model | Runs | Avg Duration | Avg Duration Net of Traps | Avg Errors | Avg Turns | Avg Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| powershell | fable5-medium | 6 | 14.5min | 14.1min | 3.2 | 35 | $4.60 | $27.58 | — | — |
| bash | fable5-medium | 6 | 7.7min | 6.8min | 2.2 | 37 | $3.58 | $21.49 | — | — |
| default | fable5-medium | 7 | 8.9min | 7.6min | 1.1 | 40 | $4.05 | $28.38 | — | — |
| typescript-bun | fable5-medium | 6 | 10.5min | 8.1min | 0.5 | 44 | $4.62 | $27.74 | — | — |

</details>

<details>
<summary>Sorted by LLM-as-judge score (best first)</summary>

| Language | Model | Runs | Avg Duration | Avg Duration Net of Traps | Avg Errors | Avg Turns | Avg Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| bash | fable5-medium | 6 | 7.7min | 6.8min | 2.2 | 37 | $3.58 | $21.49 | — | — |
| default | fable5-medium | 7 | 8.9min | 7.6min | 1.1 | 40 | $4.05 | $28.38 | — | — |
| powershell | fable5-medium | 6 | 14.5min | 14.1min | 3.2 | 35 | $4.60 | $27.58 | — | — |
| typescript-bun | fable5-medium | 6 | 10.5min | 8.1min | 0.5 | 44 | $4.62 | $27.74 | — | — |

</details>

<details>
<summary>Sorted by deliverable-quality score (best first)</summary>

| Language | Model | Runs | Avg Duration | Avg Duration Net of Traps | Avg Errors | Avg Turns | Avg Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| bash | fable5-medium | 6 | 7.7min | 6.8min | 2.2 | 37 | $3.58 | $21.49 | — | — |
| default | fable5-medium | 7 | 8.9min | 7.6min | 1.1 | 40 | $4.05 | $28.38 | — | — |
| powershell | fable5-medium | 6 | 14.5min | 14.1min | 3.2 | 35 | $4.60 | $27.58 | — | — |
| typescript-bun | fable5-medium | 6 | 10.5min | 8.1min | 0.5 | 44 | $4.62 | $27.74 | — | — |

</details>

## Savings Analysis

### Hook Savings by Language/Model/Effort

Each hook-caught error avoids one test run that would otherwise have been needed to discover it.
Every hook fire (hit or miss) costs execution time for the syntax/type checker.

*`% of Test Time Saved` = `net / (net + test_time) × 100` — the share of total (would-have-been + actually-spent) test time that hooks eliminated. Bounded in (-∞, 100%) without an artificial cap; near 100% means hooks substituted for almost all of the hypothetical test work.*

| Language | Model | Fires | Caught | Rate | Gross Saved | % of Time | Overhead | % of Time | Net Saved | % of Time | Test Run Time | % of Test Time Saved |
|------|-------|-------|--------|------|------------|-----------|----------|-----------|-----------|-----------|---------------|----------------------|
| bash | fable5-medium-cli2.1.198 | 111 | 7 | 6.3% | 1.4min | 0.5% | 0.1min | 0.0% | 1.3min | 0.5% | 6.9min | 15.8% |
| default | fable5-medium-cli2.1.198 | 140 | 0 | 0.0% | 0.0min | 0.0% | 0.3min | 0.1% | -0.3min | -0.1% | 8.0min | -4.5% |
| powershell | fable5-medium-cli2.1.198 | 115 | 19 | 16.5% | 11.1min | 4.3% | 16.3min | 6.3% | -5.2min | -2.0% | 5.9min | -805.5% |
| typescript-bun | fable5-medium-cli2.1.198 | 137 | 59 | 43.1% | 7.9min | 3.0% | 9.3min | 3.6% | -1.4min | -0.5% | 6.5min | -27.7% |


<details>
<summary>Sorted by net saved (most first)</summary>

| Language | Model | Fires | Caught | Rate | Gross Saved | % of Time | Overhead | % of Time | Net Saved | % of Time | Test Run Time | % of Test Time Saved |
|------|-------|-------|--------|------|------------|-----------|----------|-----------|-----------|-----------|---------------|----------------------|
| bash | fable5-medium-cli2.1.198 | 111 | 7 | 6.3% | 1.4min | 0.5% | 0.1min | 0.0% | 1.3min | 0.5% | 6.9min | 15.8% |
| default | fable5-medium-cli2.1.198 | 140 | 0 | 0.0% | 0.0min | 0.0% | 0.3min | 0.1% | -0.3min | -0.1% | 8.0min | -4.5% |
| typescript-bun | fable5-medium-cli2.1.198 | 137 | 59 | 43.1% | 7.9min | 3.0% | 9.3min | 3.6% | -1.4min | -0.5% | 6.5min | -27.7% |
| powershell | fable5-medium-cli2.1.198 | 115 | 19 | 16.5% | 11.1min | 4.3% | 16.3min | 6.3% | -5.2min | -2.0% | 5.9min | -805.5% |

</details>

<details>
<summary>Sorted by net % of test time saved (most first)</summary>

| Language | Model | Fires | Caught | Rate | Gross Saved | % of Time | Overhead | % of Time | Net Saved | % of Time | Test Run Time | % of Test Time Saved |
|------|-------|-------|--------|------|------------|-----------|----------|-----------|-----------|-----------|---------------|----------------------|
| bash | fable5-medium-cli2.1.198 | 111 | 7 | 6.3% | 1.4min | 0.5% | 0.1min | 0.0% | 1.3min | 0.5% | 6.9min | 15.8% |
| default | fable5-medium-cli2.1.198 | 140 | 0 | 0.0% | 0.0min | 0.0% | 0.3min | 0.1% | -0.3min | -0.1% | 8.0min | -4.5% |
| typescript-bun | fable5-medium-cli2.1.198 | 137 | 59 | 43.1% | 7.9min | 3.0% | 9.3min | 3.6% | -1.4min | -0.5% | 6.5min | -27.7% |
| powershell | fable5-medium-cli2.1.198 | 115 | 19 | 16.5% | 11.1min | 4.3% | 16.3min | 6.3% | -5.2min | -2.0% | 5.9min | -805.5% |

</details>

<details>
<summary>Sorted by catch rate (highest first)</summary>

| Language | Model | Fires | Caught | Rate | Gross Saved | % of Time | Overhead | % of Time | Net Saved | % of Time | Test Run Time | % of Test Time Saved |
|------|-------|-------|--------|------|------------|-----------|----------|-----------|-----------|-----------|---------------|----------------------|
| typescript-bun | fable5-medium-cli2.1.198 | 137 | 59 | 43.1% | 7.9min | 3.0% | 9.3min | 3.6% | -1.4min | -0.5% | 6.5min | -27.7% |
| powershell | fable5-medium-cli2.1.198 | 115 | 19 | 16.5% | 11.1min | 4.3% | 16.3min | 6.3% | -5.2min | -2.0% | 5.9min | -805.5% |
| bash | fable5-medium-cli2.1.198 | 111 | 7 | 6.3% | 1.4min | 0.5% | 0.1min | 0.0% | 1.3min | 0.5% | 6.9min | 15.8% |
| default | fable5-medium-cli2.1.198 | 140 | 0 | 0.0% | 0.0min | 0.0% | 0.3min | 0.1% | -0.3min | -0.1% | 8.0min | -4.5% |

</details>

### Trap Analysis by Language/Model/Effort/Category

| Trap | Language | Model | Fell In | Time Lost | % of Time | $ Lost | % of $ |
|------|------|-------|---------|-----------|-----------|--------|--------|
| repeated-test-reruns | bash | fable5-medium-cli2.1.198 | 3 | 5.7min | 2.2% | $2.69 | 2.56% |
| repeated-test-reruns | default | fable5-medium-cli2.1.198 | 4 | 8.3min | 3.2% | $3.61 | 3.43% |
| repeated-test-reruns | powershell | fable5-medium-cli2.1.198 | 1 | 2.7min | 1.0% | $1.07 | 1.02% |
| repeated-test-reruns | typescript-bun | fable5-medium-cli2.1.198 | 2 | 2.7min | 1.0% | $1.03 | 0.98% |
| ts-type-error-fix-cycles | typescript-bun | fable5-medium-cli2.1.198 | 6 | 11.8min | 4.6% | $5.07 | 4.82% |
| fixture-rework | default | fable5-medium-cli2.1.198 | 1 | 0.8min | 0.3% | $0.35 | 0.33% |


<details>
<summary>Sorted by time lost (least first)</summary>

| Trap | Language | Model | Fell In | Time Lost | % of Time | $ Lost | % of $ |
|------|------|-------|---------|-----------|-----------|--------|--------|
| fixture-rework | default | fable5-medium-cli2.1.198 | 1 | 0.8min | 0.3% | $0.35 | 0.33% |
| repeated-test-reruns | powershell | fable5-medium-cli2.1.198 | 1 | 2.7min | 1.0% | $1.07 | 1.02% |
| repeated-test-reruns | typescript-bun | fable5-medium-cli2.1.198 | 2 | 2.7min | 1.0% | $1.03 | 0.98% |
| repeated-test-reruns | bash | fable5-medium-cli2.1.198 | 3 | 5.7min | 2.2% | $2.69 | 2.56% |
| repeated-test-reruns | default | fable5-medium-cli2.1.198 | 4 | 8.3min | 3.2% | $3.61 | 3.43% |
| ts-type-error-fix-cycles | typescript-bun | fable5-medium-cli2.1.198 | 6 | 11.8min | 4.6% | $5.07 | 4.82% |

</details>

<details>
<summary>Sorted by $ lost (least first)</summary>

| Trap | Language | Model | Fell In | Time Lost | % of Time | $ Lost | % of $ |
|------|------|-------|---------|-----------|-----------|--------|--------|
| fixture-rework | default | fable5-medium-cli2.1.198 | 1 | 0.8min | 0.3% | $0.35 | 0.33% |
| repeated-test-reruns | typescript-bun | fable5-medium-cli2.1.198 | 2 | 2.7min | 1.0% | $1.03 | 0.98% |
| repeated-test-reruns | powershell | fable5-medium-cli2.1.198 | 1 | 2.7min | 1.0% | $1.07 | 1.02% |
| repeated-test-reruns | bash | fable5-medium-cli2.1.198 | 3 | 5.7min | 2.2% | $2.69 | 2.56% |
| repeated-test-reruns | default | fable5-medium-cli2.1.198 | 4 | 8.3min | 3.2% | $3.61 | 3.43% |
| ts-type-error-fix-cycles | typescript-bun | fable5-medium-cli2.1.198 | 6 | 11.8min | 4.6% | $5.07 | 4.82% |

</details>

<details>
<summary>Sorted by fell-in count (fewest first)</summary>

| Trap | Language | Model | Fell In | Time Lost | % of Time | $ Lost | % of $ |
|------|------|-------|---------|-----------|-----------|--------|--------|
| repeated-test-reruns | powershell | fable5-medium-cli2.1.198 | 1 | 2.7min | 1.0% | $1.07 | 1.02% |
| fixture-rework | default | fable5-medium-cli2.1.198 | 1 | 0.8min | 0.3% | $0.35 | 0.33% |
| repeated-test-reruns | typescript-bun | fable5-medium-cli2.1.198 | 2 | 2.7min | 1.0% | $1.03 | 0.98% |
| repeated-test-reruns | bash | fable5-medium-cli2.1.198 | 3 | 5.7min | 2.2% | $2.69 | 2.56% |
| repeated-test-reruns | default | fable5-medium-cli2.1.198 | 4 | 8.3min | 3.2% | $3.61 | 3.43% |
| ts-type-error-fix-cycles | typescript-bun | fable5-medium-cli2.1.198 | 6 | 11.8min | 4.6% | $5.07 | 4.82% |

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
| bash | fable5-medium-cli2.1.198 | 6 | 3 | 5.7min | 2.2% | $2.69 | 2.56% |
| default | fable5-medium-cli2.1.198 | 7 | 5 | 9.1min | 3.5% | $3.96 | 3.76% |
| powershell | fable5-medium-cli2.1.198 | 6 | 1 | 2.7min | 1.0% | $1.07 | 1.02% |
| typescript-bun | fable5-medium-cli2.1.198 | 6 | 8 | 14.5min | 5.6% | $6.10 | 5.79% |


<details>
<summary>Sorted by time lost (least first)</summary>

| Language | Model | Runs | Traps | Time Lost | % of Time | $ Lost | % of $ |
|------|-------|------|-------|-----------|-----------|--------|--------|
| powershell | fable5-medium-cli2.1.198 | 6 | 1 | 2.7min | 1.0% | $1.07 | 1.02% |
| bash | fable5-medium-cli2.1.198 | 6 | 3 | 5.7min | 2.2% | $2.69 | 2.56% |
| default | fable5-medium-cli2.1.198 | 7 | 5 | 9.1min | 3.5% | $3.96 | 3.76% |
| typescript-bun | fable5-medium-cli2.1.198 | 6 | 8 | 14.5min | 5.6% | $6.10 | 5.79% |

</details>

<details>
<summary>Sorted by $ lost (least first)</summary>

| Language | Model | Runs | Traps | Time Lost | % of Time | $ Lost | % of $ |
|------|-------|------|-------|-----------|-----------|--------|--------|
| powershell | fable5-medium-cli2.1.198 | 6 | 1 | 2.7min | 1.0% | $1.07 | 1.02% |
| bash | fable5-medium-cli2.1.198 | 6 | 3 | 5.7min | 2.2% | $2.69 | 2.56% |
| default | fable5-medium-cli2.1.198 | 7 | 5 | 9.1min | 3.5% | $3.96 | 3.76% |
| typescript-bun | fable5-medium-cli2.1.198 | 6 | 8 | 14.5min | 5.6% | $6.10 | 5.79% |

</details>

### Prompt Cache Savings

| Status | Runs | $ Saved | % of $ |
|--------|------|---------|--------|
| Full hit (100%) | 0 | $0.00 | 0.00% |
| Partial | 24 | $5.06 | 4.81% |
| Miss | 1 | $0.00 | 0.00% |

## Test Quality Evaluation

### Structural Metrics by Language/Model/Effort

Automated analysis of test files: test count, assertion count, and test-to-code line ratio.

| Language | Model | Avg Tests | Avg Assertions | Avg Assert/Test | Avg Test:Code Ratio |
|------|-------|-----------|----------------|-----------------|---------------------|
| bash | fable5-medium | 22.7 | 44.2 | 1.9 | 0.71 |
| default | fable5-medium | 22.9 | 43.7 | 1.9 | 0.96 |
| powershell | fable5-medium | 36.5 | 67.5 | 1.8 | 6.08 |
| typescript-bun | fable5-medium | 33.3 | 64.0 | 1.9 | 1.26 |


<details>
<summary>Sorted by avg tests (most first)</summary>

| Language | Model | Avg Tests | Avg Assertions | Avg Assert/Test | Avg Test:Code Ratio |
|------|-------|-----------|----------------|-----------------|---------------------|
| powershell | fable5-medium | 36.5 | 67.5 | 1.8 | 6.08 |
| typescript-bun | fable5-medium | 33.3 | 64.0 | 1.9 | 1.26 |
| default | fable5-medium | 22.9 | 43.7 | 1.9 | 0.96 |
| bash | fable5-medium | 22.7 | 44.2 | 1.9 | 0.71 |

</details>

<details>
<summary>Sorted by avg assertions (most first)</summary>

| Language | Model | Avg Tests | Avg Assertions | Avg Assert/Test | Avg Test:Code Ratio |
|------|-------|-----------|----------------|-----------------|---------------------|
| powershell | fable5-medium | 36.5 | 67.5 | 1.8 | 6.08 |
| typescript-bun | fable5-medium | 33.3 | 64.0 | 1.9 | 1.26 |
| bash | fable5-medium | 22.7 | 44.2 | 1.9 | 0.71 |
| default | fable5-medium | 22.9 | 43.7 | 1.9 | 0.96 |

</details>

<details>
<summary>Sorted by avg test:code ratio (highest first)</summary>

| Language | Model | Avg Tests | Avg Assertions | Avg Assert/Test | Avg Test:Code Ratio |
|------|-------|-----------|----------------|-----------------|---------------------|
| powershell | fable5-medium | 36.5 | 67.5 | 1.8 | 6.08 |
| typescript-bun | fable5-medium | 33.3 | 64.0 | 1.9 | 1.26 |
| default | fable5-medium | 22.9 | 43.7 | 1.9 | 0.96 |
| bash | fable5-medium | 22.7 | 44.2 | 1.9 | 0.71 |

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
| Test Results Aggregator | bash | fable5-medium | 26 | 60 | 2.3 | 240 | 327 | 0.73 |
| Test Results Aggregator | typescript-bun | fable5-medium | 33 | 70 | 2.1 | 661 | 487 | 1.36 |
| Environment Matrix Generator | default | fable5-medium | 25 | 53 | 2.1 | 279 | 377 | 0.74 |
| Environment Matrix Generator | powershell | fable5-medium | 31 | 63 | 2.0 | 399 | 42 | 9.50 |
| Environment Matrix Generator | bash | fable5-medium | 16 | 23 | 1.4 | 138 | 233 | 0.59 |
| Environment Matrix Generator | typescript-bun | fable5-medium | 27 | 50 | 1.9 | 384 | 422 | 0.91 |
| Artifact Cleanup Script | default | fable5-medium | 25 | 54 | 2.2 | 337 | 441 | 0.76 |
| Artifact Cleanup Script | powershell | fable5-medium | 27 | 65 | 2.4 | 348 | 298 | 1.17 |
| Artifact Cleanup Script | bash | fable5-medium | 18 | 50 | 2.8 | 185 | 335 | 0.55 |
| Artifact Cleanup Script | typescript-bun | fable5-medium | 33 | 75 | 2.3 | 579 | 437 | 1.32 |
| Secret Rotation Validator | default | fable5-medium | 32 | 62 | 1.9 | 370 | 233 | 1.59 |

</details>

## Per-Run Results

*Tests Quality = Overall (1-5) from LLM-as-judge of generated test code (dimensions: coverage, rigor, design). `—` = no judge data.*

| Task | Language | Model | Duration | Turns | Errors | Cost | Tests Quality | Chosen | Status |
|------|----------|-------|----------|-------|--------|------|-----------|--------|--------|
| Artifact Cleanup Script | bash | fable5-medium | 7.7min | 31 | 5 | $3.53 | — | bash | ok |
| Artifact Cleanup Script | default | fable5-medium | 12.1min | 52 | 0 | $5.22 | — | python | ok |
| Artifact Cleanup Script | powershell | fable5-medium | 17.1min | 46 | 1 | $6.86 | — | powershell | ok |
| Artifact Cleanup Script | typescript-bun | fable5-medium | 14.5min | 51 | 0 | $5.68 | — | typescript | ok |
| Dependency License Checker | bash | fable5-medium | 6.3min | 36 | 1 | $2.95 | — | bash | ok |
| Dependency License Checker | default | fable5-medium | 6.8min | 29 | 2 | $2.90 | — | python | ok |
| Dependency License Checker | powershell | fable5-medium | 11.2min | 20 | 2 | $3.23 | — | powershell | ok |
| Dependency License Checker | typescript-bun | fable5-medium | 9.2min | 46 | 0 | $4.24 | — | typescript | ok |
| Environment Matrix Generator | bash | fable5-medium | 7.5min | 37 | 1 | $3.41 | — | bash | ok |
| Environment Matrix Generator | default | fable5-medium | 10.6min | 47 | 2 | $4.57 | — | python | ok |
| Environment Matrix Generator | powershell | fable5-medium | 12.6min | 34 | 6 | $4.34 | — | powershell | ok |
| Environment Matrix Generator | typescript-bun | fable5-medium | 7.9min | 36 | 3 | $5.00 | — | typescript | ok |
| PR Label Assigner | bash | fable5-medium | 8.6min | 46 | 2 | $4.15 | — | bash | ok |
| PR Label Assigner | default | fable5-medium | 6.8min | 35 | 1 | $3.04 | — | python | ok |
| PR Label Assigner | powershell | fable5-medium | 12.0min | 32 | 1 | $3.41 | — | powershell | ok |
| PR Label Assigner | typescript-bun | fable5-medium | 11.9min | 46 | 0 | $4.46 | — | typescript | ok |
| Secret Rotation Validator | default | fable5-medium | 7.3min | 32 | 0 | $3.13 | — | python | ok |
| Semantic Version Bumper | bash | fable5-medium | 8.4min | 39 | 1 | $3.99 | — | bash | ok |
| Semantic Version Bumper | default | fable5-medium | 9.1min | 35 | 2 | $4.21 | — | javascript | ok |
| Semantic Version Bumper | powershell | fable5-medium | 19.0min | 36 | 4 | $4.65 | — | powershell | ok |
| Semantic Version Bumper | typescript-bun | fable5-medium | 8.9min | 36 | 0 | $3.39 | — | typescript | ok |
| Test Results Aggregator | bash | fable5-medium | 7.8min | 34 | 3 | $3.46 | — | bash | ok |
| Test Results Aggregator | default | fable5-medium | 9.8min | 47 | 1 | $5.30 | — | python | ok |
| Test Results Aggregator | powershell | fable5-medium | 15.2min | 40 | 5 | $5.09 | — | powershell | ok |
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
| Semantic Version Bumper | bash | fable5-medium | 8.4min | 39 | 1 | $3.99 | — | bash | ok |
| PR Label Assigner | bash | fable5-medium | 8.6min | 46 | 2 | $4.15 | — | bash | ok |
| Semantic Version Bumper | default | fable5-medium | 9.1min | 35 | 2 | $4.21 | — | javascript | ok |
| Dependency License Checker | typescript-bun | fable5-medium | 9.2min | 46 | 0 | $4.24 | — | typescript | ok |
| Environment Matrix Generator | powershell | fable5-medium | 12.6min | 34 | 6 | $4.34 | — | powershell | ok |
| PR Label Assigner | typescript-bun | fable5-medium | 11.9min | 46 | 0 | $4.46 | — | typescript | ok |
| Environment Matrix Generator | default | fable5-medium | 10.6min | 47 | 2 | $4.57 | — | python | ok |
| Semantic Version Bumper | powershell | fable5-medium | 19.0min | 36 | 4 | $4.65 | — | powershell | ok |
| Test Results Aggregator | typescript-bun | fable5-medium | 10.7min | 46 | 0 | $4.98 | — | typescript | ok |
| Environment Matrix Generator | typescript-bun | fable5-medium | 7.9min | 36 | 3 | $5.00 | — | typescript | ok |
| Test Results Aggregator | powershell | fable5-medium | 15.2min | 40 | 5 | $5.09 | — | powershell | ok |
| Artifact Cleanup Script | default | fable5-medium | 12.1min | 52 | 0 | $5.22 | — | python | ok |
| Test Results Aggregator | default | fable5-medium | 9.8min | 47 | 1 | $5.30 | — | python | ok |
| Artifact Cleanup Script | typescript-bun | fable5-medium | 14.5min | 51 | 0 | $5.68 | — | typescript | ok |
| Artifact Cleanup Script | powershell | fable5-medium | 17.1min | 46 | 1 | $6.86 | — | powershell | ok |

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
| Semantic Version Bumper | bash | fable5-medium | 8.4min | 39 | 1 | $3.99 | — | bash | ok |
| PR Label Assigner | bash | fable5-medium | 8.6min | 46 | 2 | $4.15 | — | bash | ok |
| Semantic Version Bumper | typescript-bun | fable5-medium | 8.9min | 36 | 0 | $3.39 | — | typescript | ok |
| Semantic Version Bumper | default | fable5-medium | 9.1min | 35 | 2 | $4.21 | — | javascript | ok |
| Dependency License Checker | typescript-bun | fable5-medium | 9.2min | 46 | 0 | $4.24 | — | typescript | ok |
| Test Results Aggregator | default | fable5-medium | 9.8min | 47 | 1 | $5.30 | — | python | ok |
| Environment Matrix Generator | default | fable5-medium | 10.6min | 47 | 2 | $4.57 | — | python | ok |
| Test Results Aggregator | typescript-bun | fable5-medium | 10.7min | 46 | 0 | $4.98 | — | typescript | ok |
| Dependency License Checker | powershell | fable5-medium | 11.2min | 20 | 2 | $3.23 | — | powershell | ok |
| PR Label Assigner | typescript-bun | fable5-medium | 11.9min | 46 | 0 | $4.46 | — | typescript | ok |
| PR Label Assigner | powershell | fable5-medium | 12.0min | 32 | 1 | $3.41 | — | powershell | ok |
| Artifact Cleanup Script | default | fable5-medium | 12.1min | 52 | 0 | $5.22 | — | python | ok |
| Environment Matrix Generator | powershell | fable5-medium | 12.6min | 34 | 6 | $4.34 | — | powershell | ok |
| Artifact Cleanup Script | typescript-bun | fable5-medium | 14.5min | 51 | 0 | $5.68 | — | typescript | ok |
| Test Results Aggregator | powershell | fable5-medium | 15.2min | 40 | 5 | $5.09 | — | powershell | ok |
| Artifact Cleanup Script | powershell | fable5-medium | 17.1min | 46 | 1 | $6.86 | — | powershell | ok |
| Semantic Version Bumper | powershell | fable5-medium | 19.0min | 36 | 4 | $4.65 | — | powershell | ok |

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
| Secret Rotation Validator | default | fable5-medium | 7.3min | 32 | 0 | $3.13 | — | python | ok |
| Semantic Version Bumper | bash | fable5-medium | 8.4min | 39 | 1 | $3.99 | — | bash | ok |
| PR Label Assigner | default | fable5-medium | 6.8min | 35 | 1 | $3.04 | — | python | ok |
| PR Label Assigner | powershell | fable5-medium | 12.0min | 32 | 1 | $3.41 | — | powershell | ok |
| Dependency License Checker | bash | fable5-medium | 6.3min | 36 | 1 | $2.95 | — | bash | ok |
| Test Results Aggregator | default | fable5-medium | 9.8min | 47 | 1 | $5.30 | — | python | ok |
| Environment Matrix Generator | bash | fable5-medium | 7.5min | 37 | 1 | $3.41 | — | bash | ok |
| Artifact Cleanup Script | powershell | fable5-medium | 17.1min | 46 | 1 | $6.86 | — | powershell | ok |
| Semantic Version Bumper | default | fable5-medium | 9.1min | 35 | 2 | $4.21 | — | javascript | ok |
| PR Label Assigner | bash | fable5-medium | 8.6min | 46 | 2 | $4.15 | — | bash | ok |
| Dependency License Checker | default | fable5-medium | 6.8min | 29 | 2 | $2.90 | — | python | ok |
| Dependency License Checker | powershell | fable5-medium | 11.2min | 20 | 2 | $3.23 | — | powershell | ok |
| Environment Matrix Generator | default | fable5-medium | 10.6min | 47 | 2 | $4.57 | — | python | ok |
| Test Results Aggregator | bash | fable5-medium | 7.8min | 34 | 3 | $3.46 | — | bash | ok |
| Environment Matrix Generator | typescript-bun | fable5-medium | 7.9min | 36 | 3 | $5.00 | — | typescript | ok |
| Semantic Version Bumper | powershell | fable5-medium | 19.0min | 36 | 4 | $4.65 | — | powershell | ok |
| Test Results Aggregator | powershell | fable5-medium | 15.2min | 40 | 5 | $5.09 | — | powershell | ok |
| Artifact Cleanup Script | bash | fable5-medium | 7.7min | 31 | 5 | $3.53 | — | bash | ok |
| Environment Matrix Generator | powershell | fable5-medium | 12.6min | 34 | 6 | $4.34 | — | powershell | ok |

</details>

<details>
<summary>Sorted by turns (fewest first)</summary>

| Task | Language | Model | Duration | Turns | Errors | Cost | Tests Quality | Chosen | Status |
|------|----------|-------|----------|-------|--------|------|-----------|--------|--------|
| Dependency License Checker | powershell | fable5-medium | 11.2min | 20 | 2 | $3.23 | — | powershell | ok |
| Dependency License Checker | default | fable5-medium | 6.8min | 29 | 2 | $2.90 | — | python | ok |
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
| Semantic Version Bumper | bash | fable5-medium | 8.4min | 39 | 1 | $3.99 | — | bash | ok |
| Test Results Aggregator | powershell | fable5-medium | 15.2min | 40 | 5 | $5.09 | — | powershell | ok |
| PR Label Assigner | bash | fable5-medium | 8.6min | 46 | 2 | $4.15 | — | bash | ok |
| PR Label Assigner | typescript-bun | fable5-medium | 11.9min | 46 | 0 | $4.46 | — | typescript | ok |
| Dependency License Checker | typescript-bun | fable5-medium | 9.2min | 46 | 0 | $4.24 | — | typescript | ok |
| Test Results Aggregator | typescript-bun | fable5-medium | 10.7min | 46 | 0 | $4.98 | — | typescript | ok |
| Artifact Cleanup Script | powershell | fable5-medium | 17.1min | 46 | 1 | $6.86 | — | powershell | ok |
| Test Results Aggregator | default | fable5-medium | 9.8min | 47 | 1 | $5.30 | — | python | ok |
| Environment Matrix Generator | default | fable5-medium | 10.6min | 47 | 2 | $4.57 | — | python | ok |
| Artifact Cleanup Script | typescript-bun | fable5-medium | 14.5min | 51 | 0 | $5.68 | — | typescript | ok |
| Artifact Cleanup Script | default | fable5-medium | 12.1min | 52 | 0 | $5.22 | — | python | ok |

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
| Test Results Aggregator | bash | fable5-medium | 7.8min | 34 | 3 | $3.46 | — | bash | ok |
| Test Results Aggregator | typescript-bun | fable5-medium | 10.7min | 46 | 0 | $4.98 | — | typescript | ok |
| Environment Matrix Generator | default | fable5-medium | 10.6min | 47 | 2 | $4.57 | — | python | ok |
| Environment Matrix Generator | powershell | fable5-medium | 12.6min | 34 | 6 | $4.34 | — | powershell | ok |
| Environment Matrix Generator | bash | fable5-medium | 7.5min | 37 | 1 | $3.41 | — | bash | ok |
| Environment Matrix Generator | typescript-bun | fable5-medium | 7.9min | 36 | 3 | $5.00 | — | typescript | ok |
| Artifact Cleanup Script | default | fable5-medium | 12.1min | 52 | 0 | $5.22 | — | python | ok |
| Artifact Cleanup Script | powershell | fable5-medium | 17.1min | 46 | 1 | $6.86 | — | powershell | ok |
| Artifact Cleanup Script | bash | fable5-medium | 7.7min | 31 | 5 | $3.53 | — | bash | ok |
| Artifact Cleanup Script | typescript-bun | fable5-medium | 14.5min | 51 | 0 | $5.68 | — | typescript | ok |
| Secret Rotation Validator | default | fable5-medium | 7.3min | 32 | 0 | $3.13 | — | python | ok |

</details>

## Notes

### Tiers

- **Duration bands:** **A+** ≤1.05×, **A** ≤1.11×, **A-** ≤1.17×, **B+** ≤1.23×, **B** ≤1.30×, **B-** ≤1.37×, **C+** ≤1.45×, **C** ≤1.52×, **C-** ≤1.61×, **D+** ≤1.69×, **D** ≤1.78×, **D-** ≤1.88×, **F** >1.88×
- **Cost bands:** **A+** ≤1.02×, **A** ≤1.04×, **A-** ≤1.07×, **B+** ≤1.09×, **B** ≤1.11×, **B-** ≤1.14×, **C+** ≤1.16×, **C** ≤1.19×, **C-** ≤1.21×, **D+** ≤1.24×, **D** ≤1.26×, **D-** ≤1.29×, **F** >1.29×

*Tests/Workflow Craft bands are absolute Overall score bands:* **A+** ≥4.7, **A** ≥4.4, **A-** ≥4.1, **B+** ≥3.8, **B** ≥3.5, **B-** ≥3.2, **C+** ≥2.9, **C** ≥2.6, **C-** ≥2.3, **D+** ≥2.0, **D** ≥1.7, **D-** ≥1.4, **F** <1.4, `—` = no data.*

### CLI Version Legend

| Variant label | CLI version | Tasks | Languages |
|---------------|-------------|-------|-----------|
| fable5-medium | 2.1.198 | All | All |

---
*Generated by generate_results.py — benchmark instructions v4*