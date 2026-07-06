# Benchmark Results: Language Comparison

**Last updated:** 2026-07-06 01:10:25 PM ET — 56/56 runs completed, 0 remaining; total cost $284.77; total agent time 668.9 min.
**Claude Code versions used:** [v2.1.198](claude-code-2.1.198.md) (56 runs). Each link goes to a per-version snapshot of the system prompt, default-tool descriptions, and the chronological Anthropic changelog up to that version. Regenerate with `python3 version_docs.py`.

## Table of Contents

- [Scoring](#scoring)
  - [Duration columns](#duration-columns)
- [Tiers by Language/Model/Effort](#tiers-by-languagemodeleffort)
- [Comparison by Language/Model/Effort](#comparison-by-languagemodeleffort)
- [Savings Analysis](#savings-analysis)
  - [Trap Analysis by Language/Model/Effort/Category](#trap-analysis-by-languagemodeleffortcategory)
  - [Traps by Language/Model/Effort](#traps-by-languagemodeleffort)
  - [Prompt Cache Savings](#prompt-cache-savings)
- [Test Quality Evaluation](#test-quality-evaluation)
  - [Structural Metrics by Language/Model/Effort](#structural-metrics-by-languagemodeleffort)
  - [LLM-as-Judge Scores](#llm-as-judge-scores)
  - [Correlation: Structural Metrics vs Tests Quality](#correlation-structural-metrics-vs-tests-quality)
  - [LLM vs Structural Discrepancies](#llm-vs-structural-discrepancies)
- [Per-Run Results](#per-run-results)
- [Notes](#notes)
  - [Tiers](#tiers)
  - [CLI Version Legend](#cli-version-legend)
  - [Judge Consistency Summary](#judge-consistency-summary)

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

Every Duration figure in this report derives from `timing.grand_total_duration_ms` in `metrics.json` — wall-clock seconds from CLI invocation to the final assistant turn (agent thinking + tool execution).

- **Duration** (single run): that one run's wall clock. Appears in the [Failed / Timed-Out Runs](#failed--timed-out-runs) and per-run detail tables.
- **Geo Duration / Geo Cost / Geo Turns** (in the [Comparison by Language/Model/Effort](#comparison-by-languagemodeleffort) table; Geo Duration and Geo Cost also drive the [Tiers](#tiers-by-languagemodeleffort) Duration/Cost columns): **geometric** means (issue #33) — outlier-damped relative to a plain average, so one abnormally slow/expensive/chatty run doesn't dominate a combo's aggregate.
- The **Geo Duration pool additionally includes timed-out runs**, counted at their recorded wall clock. A timeout is right-censored — its true duration might have been longer, but is known to be AT LEAST the recorded value — so excluding it outright would effectively reward timing out with a better average.
- **Total Cost** now includes timed-out cells: the CLI-recorded cost when the stream captured a final result record, otherwise a **floor estimate recovered from the partial `cli-output.json` event stream** (see `recover_cost.py`) — input / cache-read / cache-write tokens are exact per-message usage; output tokens are estimated from visible content plus thinking-token telemetry (a lower bound: most thinking output never appears in a killed stream) and priced via `models.py`. Rows containing a timeout without CLI-recorded cost are `≥`-prefixed.
- **Geo Cost / Geo Turns still exclude every failed run, including timeouts**: a killed CLI records `cost=0`/`turns=0`, which is missing data, not a real zero, and recovered floors are estimates — pooling a known-low bound into a geometric mean would bias the ratio statistics the tiers are built from. The exact-vs-floor distinction only affects the additive Total Cost column.
- **Max Duration** is the slowest run in the Geo Duration pool for that combo, `≥`-prefixed when that run was a timeout (true duration unknown, but at least the shown value).
- **Avg Errors** remains an arithmetic mean.
- **Geo Duration Net of Traps** (in the Comparison table only): the geometric mean of (per-run `Duration` − that run's `Time Lost`), where `Time Lost` is the trap detector's estimate of seconds spent on detected anti-patterns (see [Trap Descriptions](#trap-descriptions) and the trap-table [Column Definitions](#column-definitions) for the trap list and how Time Lost is computed). Pooled over the SAME runs as Geo Duration — timed-out cells are included, with their detected traps (if any) deducted too. Reads as a counterfactual: roughly how fast each combo would have been without the detected traps.
- The **Tier table's Duration/Cost columns** show the tier letter (A+..F) for the combo's gross **Geo Duration**/**Geo Cost** ratio. Net of Traps does not feed the tier band.
## Tiers by Language/Model/Effort

*Default sort: weighted composite of tiers (40% Tests, 25% Workflow Craft, 35% split between Duration & Cost). See [Notes](#notes) for tier-band definitions and scoring rubric.*

| Language | Model | Duration | Cost | Tests Quality | Workflow Craft |
|----------|-------|----------|------|-----------|-------------|
| bash | fable5-1m-medium | A+ (7.9min) | A+ ($3.61) | A- (4.1) | B+ (4.1) |
| typescript-bun | fable5-1m-medium | B (10.6min) | B- ($4.60) | A (4.4) | A- (4.1) |
| default | fable5-1m-medium | A (8.7min) | A- ($3.94) | B- (3.2) | B+ (3.9) |
| powershell | fable5-1m-medium | D+ (14.7min) | B- ($4.57) | A (4.5) | B (3.6) |
| bash | fable5-1m-high | C+ (11.8min) | D+ ($5.47) | A- (4.3) | B+ (4.1) |
| typescript-bun | fable5-1m-high | C+ (12.2min) | D- ($5.98) | A- (4.3) | B+ (3.9) |
| default | fable5-1m-high | B- (11.3min) | D- ($5.74) | B- (3.2) | A (4.4) |
| powershell | fable5-1m-high | D- (16.9min) | D- ($5.96) | A- (4.4) | A- (4.4) |


<details>
<summary>Sorted by Duration tier (best-first), then avg of Cost/Tests/Workflow Craft tiers</summary>

| Language | Model | Duration | Cost | Tests Quality | Workflow Craft |
|----------|-------|----------|------|-----------|-------------|
| bash | fable5-1m-medium | A+ (7.9min) | A+ ($3.61) | A- (4.1) | B+ (4.1) |
| default | fable5-1m-medium | A (8.7min) | A- ($3.94) | B- (3.2) | B+ (3.9) |
| typescript-bun | fable5-1m-medium | B (10.6min) | B- ($4.60) | A (4.4) | A- (4.1) |
| default | fable5-1m-high | B- (11.3min) | D- ($5.74) | B- (3.2) | A (4.4) |
| bash | fable5-1m-high | C+ (11.8min) | D+ ($5.47) | A- (4.3) | B+ (4.1) |
| typescript-bun | fable5-1m-high | C+ (12.2min) | D- ($5.98) | A- (4.3) | B+ (3.9) |
| powershell | fable5-1m-medium | D+ (14.7min) | B- ($4.57) | A (4.5) | B (3.6) |
| powershell | fable5-1m-high | D- (16.9min) | D- ($5.96) | A- (4.4) | A- (4.4) |

</details>

<details>
<summary>Sorted by Cost tier (best-first), then avg of Duration/Tests/Workflow Craft tiers</summary>

| Language | Model | Duration | Cost | Tests Quality | Workflow Craft |
|----------|-------|----------|------|-----------|-------------|
| bash | fable5-1m-medium | A+ (7.9min) | A+ ($3.61) | A- (4.1) | B+ (4.1) |
| default | fable5-1m-medium | A (8.7min) | A- ($3.94) | B- (3.2) | B+ (3.9) |
| typescript-bun | fable5-1m-medium | B (10.6min) | B- ($4.60) | A (4.4) | A- (4.1) |
| powershell | fable5-1m-medium | D+ (14.7min) | B- ($4.57) | A (4.5) | B (3.6) |
| bash | fable5-1m-high | C+ (11.8min) | D+ ($5.47) | A- (4.3) | B+ (4.1) |
| default | fable5-1m-high | B- (11.3min) | D- ($5.74) | B- (3.2) | A (4.4) |
| typescript-bun | fable5-1m-high | C+ (12.2min) | D- ($5.98) | A- (4.3) | B+ (3.9) |
| powershell | fable5-1m-high | D- (16.9min) | D- ($5.96) | A- (4.4) | A- (4.4) |

</details>

<details>
<summary>Sorted by Tests Quality tier (best-first; no-data last), then avg of other tiers</summary>

| Language | Model | Duration | Cost | Tests Quality | Workflow Craft |
|----------|-------|----------|------|-----------|-------------|
| typescript-bun | fable5-1m-medium | B (10.6min) | B- ($4.60) | A (4.4) | A- (4.1) |
| powershell | fable5-1m-medium | D+ (14.7min) | B- ($4.57) | A (4.5) | B (3.6) |
| bash | fable5-1m-medium | A+ (7.9min) | A+ ($3.61) | A- (4.1) | B+ (4.1) |
| bash | fable5-1m-high | C+ (11.8min) | D+ ($5.47) | A- (4.3) | B+ (4.1) |
| typescript-bun | fable5-1m-high | C+ (12.2min) | D- ($5.98) | A- (4.3) | B+ (3.9) |
| powershell | fable5-1m-high | D- (16.9min) | D- ($5.96) | A- (4.4) | A- (4.4) |
| default | fable5-1m-medium | A (8.7min) | A- ($3.94) | B- (3.2) | B+ (3.9) |
| default | fable5-1m-high | B- (11.3min) | D- ($5.74) | B- (3.2) | A (4.4) |

</details>

<details>
<summary>Sorted by Workflow Craft tier (best-first; no-data last), then avg of other tiers</summary>

| Language | Model | Duration | Cost | Tests Quality | Workflow Craft |
|----------|-------|----------|------|-----------|-------------|
| default | fable5-1m-high | B- (11.3min) | D- ($5.74) | B- (3.2) | A (4.4) |
| typescript-bun | fable5-1m-medium | B (10.6min) | B- ($4.60) | A (4.4) | A- (4.1) |
| powershell | fable5-1m-high | D- (16.9min) | D- ($5.96) | A- (4.4) | A- (4.4) |
| bash | fable5-1m-medium | A+ (7.9min) | A+ ($3.61) | A- (4.1) | B+ (4.1) |
| default | fable5-1m-medium | A (8.7min) | A- ($3.94) | B- (3.2) | B+ (3.9) |
| bash | fable5-1m-high | C+ (11.8min) | D+ ($5.47) | A- (4.3) | B+ (4.1) |
| typescript-bun | fable5-1m-high | C+ (12.2min) | D- ($5.98) | A- (4.3) | B+ (3.9) |
| powershell | fable5-1m-medium | D+ (14.7min) | B- ($4.57) | A (4.5) | B (3.6) |

</details>

## Comparison by Language/Model/Effort
*See [Notes](#notes) for scoring rubric and CLI version legend.*

| Language | Model | Runs | Geo Duration | Max Duration | Geo Duration Net of Traps | Avg Errors | Geo Turns | Geo Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| bash | fable5-1m-high | 7 | 11.8min | 13.7min | 9.3min | 1.3 | 49 | $5.47 | $38.62 | 4.3 | 4.1 |
| bash | fable5-1m-medium | 7 | 7.9min | 9.4min | 6.8min | 1.9 | 37 | $3.61 | $25.42 | 4.1 | 4.1 |
| default | fable5-1m-high | 7 | 11.3min | 15.1min | 8.6min | 0.7 | 52 | $5.74 | $41.81 | 3.2 | 4.4 |
| default | fable5-1m-medium | 7 | 8.7min | 12.1min | 7.6min | 1.1 | 39 | $3.94 | $28.38 | 3.2 | 3.9 |
| powershell | fable5-1m-high | 7 | 16.9min | 21.5min | 15.7min | 4.1 | 43 | $5.96 | $42.05 | 4.4 | 4.4 |
| powershell | fable5-1m-medium | 7 | 14.7min | 19.0min | 14.4min | 3.4 | 33 | $4.57 | $32.90 | 4.5 | 3.6 |
| typescript-bun | fable5-1m-high | 7 | 12.2min | 15.2min | 10.4min | 1.3 | 52 | $5.98 | $43.01 | 4.3 | 3.9 |
| typescript-bun | fable5-1m-medium | 7 | 10.6min | 14.5min | 9.7min | 0.4 | 43 | $4.60 | $32.58 | 4.4 | 4.1 |


<details>
<summary>Sorted by cost (geomean, cheapest first)</summary>

| Language | Model | Runs | Geo Duration | Max Duration | Geo Duration Net of Traps | Avg Errors | Geo Turns | Geo Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| bash | fable5-1m-medium | 7 | 7.9min | 9.4min | 6.8min | 1.9 | 37 | $3.61 | $25.42 | 4.1 | 4.1 |
| default | fable5-1m-medium | 7 | 8.7min | 12.1min | 7.6min | 1.1 | 39 | $3.94 | $28.38 | 3.2 | 3.9 |
| powershell | fable5-1m-medium | 7 | 14.7min | 19.0min | 14.4min | 3.4 | 33 | $4.57 | $32.90 | 4.5 | 3.6 |
| typescript-bun | fable5-1m-medium | 7 | 10.6min | 14.5min | 9.7min | 0.4 | 43 | $4.60 | $32.58 | 4.4 | 4.1 |
| bash | fable5-1m-high | 7 | 11.8min | 13.7min | 9.3min | 1.3 | 49 | $5.47 | $38.62 | 4.3 | 4.1 |
| default | fable5-1m-high | 7 | 11.3min | 15.1min | 8.6min | 0.7 | 52 | $5.74 | $41.81 | 3.2 | 4.4 |
| powershell | fable5-1m-high | 7 | 16.9min | 21.5min | 15.7min | 4.1 | 43 | $5.96 | $42.05 | 4.4 | 4.4 |
| typescript-bun | fable5-1m-high | 7 | 12.2min | 15.2min | 10.4min | 1.3 | 52 | $5.98 | $43.01 | 4.3 | 3.9 |

</details>

<details>
<summary>Sorted by duration (geomean, fastest first)</summary>

| Language | Model | Runs | Geo Duration | Max Duration | Geo Duration Net of Traps | Avg Errors | Geo Turns | Geo Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| bash | fable5-1m-medium | 7 | 7.9min | 9.4min | 6.8min | 1.9 | 37 | $3.61 | $25.42 | 4.1 | 4.1 |
| default | fable5-1m-medium | 7 | 8.7min | 12.1min | 7.6min | 1.1 | 39 | $3.94 | $28.38 | 3.2 | 3.9 |
| typescript-bun | fable5-1m-medium | 7 | 10.6min | 14.5min | 9.7min | 0.4 | 43 | $4.60 | $32.58 | 4.4 | 4.1 |
| default | fable5-1m-high | 7 | 11.3min | 15.1min | 8.6min | 0.7 | 52 | $5.74 | $41.81 | 3.2 | 4.4 |
| bash | fable5-1m-high | 7 | 11.8min | 13.7min | 9.3min | 1.3 | 49 | $5.47 | $38.62 | 4.3 | 4.1 |
| typescript-bun | fable5-1m-high | 7 | 12.2min | 15.2min | 10.4min | 1.3 | 52 | $5.98 | $43.01 | 4.3 | 3.9 |
| powershell | fable5-1m-medium | 7 | 14.7min | 19.0min | 14.4min | 3.4 | 33 | $4.57 | $32.90 | 4.5 | 3.6 |
| powershell | fable5-1m-high | 7 | 16.9min | 21.5min | 15.7min | 4.1 | 43 | $5.96 | $42.05 | 4.4 | 4.4 |

</details>

<details>
<summary>Sorted by duration net of traps (geomean, fastest first)</summary>

| Language | Model | Runs | Geo Duration | Max Duration | Geo Duration Net of Traps | Avg Errors | Geo Turns | Geo Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| bash | fable5-1m-medium | 7 | 7.9min | 9.4min | 6.8min | 1.9 | 37 | $3.61 | $25.42 | 4.1 | 4.1 |
| default | fable5-1m-medium | 7 | 8.7min | 12.1min | 7.6min | 1.1 | 39 | $3.94 | $28.38 | 3.2 | 3.9 |
| default | fable5-1m-high | 7 | 11.3min | 15.1min | 8.6min | 0.7 | 52 | $5.74 | $41.81 | 3.2 | 4.4 |
| bash | fable5-1m-high | 7 | 11.8min | 13.7min | 9.3min | 1.3 | 49 | $5.47 | $38.62 | 4.3 | 4.1 |
| typescript-bun | fable5-1m-medium | 7 | 10.6min | 14.5min | 9.7min | 0.4 | 43 | $4.60 | $32.58 | 4.4 | 4.1 |
| typescript-bun | fable5-1m-high | 7 | 12.2min | 15.2min | 10.4min | 1.3 | 52 | $5.98 | $43.01 | 4.3 | 3.9 |
| powershell | fable5-1m-medium | 7 | 14.7min | 19.0min | 14.4min | 3.4 | 33 | $4.57 | $32.90 | 4.5 | 3.6 |
| powershell | fable5-1m-high | 7 | 16.9min | 21.5min | 15.7min | 4.1 | 43 | $5.96 | $42.05 | 4.4 | 4.4 |

</details>

<details>
<summary>Sorted by avg errors (fewest first)</summary>

| Language | Model | Runs | Geo Duration | Max Duration | Geo Duration Net of Traps | Avg Errors | Geo Turns | Geo Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| typescript-bun | fable5-1m-medium | 7 | 10.6min | 14.5min | 9.7min | 0.4 | 43 | $4.60 | $32.58 | 4.4 | 4.1 |
| default | fable5-1m-high | 7 | 11.3min | 15.1min | 8.6min | 0.7 | 52 | $5.74 | $41.81 | 3.2 | 4.4 |
| default | fable5-1m-medium | 7 | 8.7min | 12.1min | 7.6min | 1.1 | 39 | $3.94 | $28.38 | 3.2 | 3.9 |
| bash | fable5-1m-high | 7 | 11.8min | 13.7min | 9.3min | 1.3 | 49 | $5.47 | $38.62 | 4.3 | 4.1 |
| typescript-bun | fable5-1m-high | 7 | 12.2min | 15.2min | 10.4min | 1.3 | 52 | $5.98 | $43.01 | 4.3 | 3.9 |
| bash | fable5-1m-medium | 7 | 7.9min | 9.4min | 6.8min | 1.9 | 37 | $3.61 | $25.42 | 4.1 | 4.1 |
| powershell | fable5-1m-medium | 7 | 14.7min | 19.0min | 14.4min | 3.4 | 33 | $4.57 | $32.90 | 4.5 | 3.6 |
| powershell | fable5-1m-high | 7 | 16.9min | 21.5min | 15.7min | 4.1 | 43 | $5.96 | $42.05 | 4.4 | 4.4 |

</details>

<details>
<summary>Sorted by turns (geomean, fewest first)</summary>

| Language | Model | Runs | Geo Duration | Max Duration | Geo Duration Net of Traps | Avg Errors | Geo Turns | Geo Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| powershell | fable5-1m-medium | 7 | 14.7min | 19.0min | 14.4min | 3.4 | 33 | $4.57 | $32.90 | 4.5 | 3.6 |
| bash | fable5-1m-medium | 7 | 7.9min | 9.4min | 6.8min | 1.9 | 37 | $3.61 | $25.42 | 4.1 | 4.1 |
| default | fable5-1m-medium | 7 | 8.7min | 12.1min | 7.6min | 1.1 | 39 | $3.94 | $28.38 | 3.2 | 3.9 |
| typescript-bun | fable5-1m-medium | 7 | 10.6min | 14.5min | 9.7min | 0.4 | 43 | $4.60 | $32.58 | 4.4 | 4.1 |
| powershell | fable5-1m-high | 7 | 16.9min | 21.5min | 15.7min | 4.1 | 43 | $5.96 | $42.05 | 4.4 | 4.4 |
| bash | fable5-1m-high | 7 | 11.8min | 13.7min | 9.3min | 1.3 | 49 | $5.47 | $38.62 | 4.3 | 4.1 |
| typescript-bun | fable5-1m-high | 7 | 12.2min | 15.2min | 10.4min | 1.3 | 52 | $5.98 | $43.01 | 4.3 | 3.9 |
| default | fable5-1m-high | 7 | 11.3min | 15.1min | 8.6min | 0.7 | 52 | $5.74 | $41.81 | 3.2 | 4.4 |

</details>

<details>
<summary>Sorted by LLM-as-judge score (best first)</summary>

| Language | Model | Runs | Geo Duration | Max Duration | Geo Duration Net of Traps | Avg Errors | Geo Turns | Geo Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| powershell | fable5-1m-medium | 7 | 14.7min | 19.0min | 14.4min | 3.4 | 33 | $4.57 | $32.90 | 4.5 | 3.6 |
| typescript-bun | fable5-1m-medium | 7 | 10.6min | 14.5min | 9.7min | 0.4 | 43 | $4.60 | $32.58 | 4.4 | 4.1 |
| powershell | fable5-1m-high | 7 | 16.9min | 21.5min | 15.7min | 4.1 | 43 | $5.96 | $42.05 | 4.4 | 4.4 |
| bash | fable5-1m-high | 7 | 11.8min | 13.7min | 9.3min | 1.3 | 49 | $5.47 | $38.62 | 4.3 | 4.1 |
| typescript-bun | fable5-1m-high | 7 | 12.2min | 15.2min | 10.4min | 1.3 | 52 | $5.98 | $43.01 | 4.3 | 3.9 |
| bash | fable5-1m-medium | 7 | 7.9min | 9.4min | 6.8min | 1.9 | 37 | $3.61 | $25.42 | 4.1 | 4.1 |
| default | fable5-1m-high | 7 | 11.3min | 15.1min | 8.6min | 0.7 | 52 | $5.74 | $41.81 | 3.2 | 4.4 |
| default | fable5-1m-medium | 7 | 8.7min | 12.1min | 7.6min | 1.1 | 39 | $3.94 | $28.38 | 3.2 | 3.9 |

</details>

<details>
<summary>Sorted by deliverable-quality score (best first)</summary>

| Language | Model | Runs | Geo Duration | Max Duration | Geo Duration Net of Traps | Avg Errors | Geo Turns | Geo Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| default | fable5-1m-high | 7 | 11.3min | 15.1min | 8.6min | 0.7 | 52 | $5.74 | $41.81 | 3.2 | 4.4 |
| powershell | fable5-1m-high | 7 | 16.9min | 21.5min | 15.7min | 4.1 | 43 | $5.96 | $42.05 | 4.4 | 4.4 |
| typescript-bun | fable5-1m-medium | 7 | 10.6min | 14.5min | 9.7min | 0.4 | 43 | $4.60 | $32.58 | 4.4 | 4.1 |
| bash | fable5-1m-high | 7 | 11.8min | 13.7min | 9.3min | 1.3 | 49 | $5.47 | $38.62 | 4.3 | 4.1 |
| bash | fable5-1m-medium | 7 | 7.9min | 9.4min | 6.8min | 1.9 | 37 | $3.61 | $25.42 | 4.1 | 4.1 |
| default | fable5-1m-medium | 7 | 8.7min | 12.1min | 7.6min | 1.1 | 39 | $3.94 | $28.38 | 3.2 | 3.9 |
| typescript-bun | fable5-1m-high | 7 | 12.2min | 15.2min | 10.4min | 1.3 | 52 | $5.98 | $43.01 | 4.3 | 3.9 |
| powershell | fable5-1m-medium | 7 | 14.7min | 19.0min | 14.4min | 3.4 | 33 | $4.57 | $32.90 | 4.5 | 3.6 |

</details>

## Savings Analysis

### Trap Analysis by Language/Model/Effort/Category

| Trap | Language | Model | Fell In | Time Lost | % of Time | $ Lost | % of $ |
|------|------|-------|---------|-----------|-----------|--------|--------|
| repeated-test-reruns | bash | fable5-1m-high-cli2.1.198 | 7 | 16.3min | 2.4% | $7.68 | 2.70% |
| repeated-test-reruns | bash | fable5-1m-medium-cli2.1.198 | 4 | 7.0min | 1.0% | $3.27 | 1.15% |
| repeated-test-reruns | default | fable5-1m-high-cli2.1.198 | 5 | 17.3min | 2.6% | $9.15 | 3.21% |
| repeated-test-reruns | default | fable5-1m-medium-cli2.1.198 | 4 | 8.3min | 1.2% | $3.61 | 1.27% |
| repeated-test-reruns | powershell | fable5-1m-high-cli2.1.198 | 3 | 7.3min | 1.1% | $2.76 | 0.97% |
| repeated-test-reruns | powershell | fable5-1m-medium-cli2.1.198 | 1 | 2.7min | 0.4% | $1.07 | 0.38% |
| repeated-test-reruns | typescript-bun | fable5-1m-high-cli2.1.198 | 6 | 12.0min | 1.8% | $6.01 | 2.11% |
| repeated-test-reruns | typescript-bun | fable5-1m-medium-cli2.1.198 | 3 | 5.3min | 0.8% | $2.04 | 0.72% |
| fixture-rework | bash | fable5-1m-high-cli2.1.198 | 1 | 0.7min | 0.1% | $0.28 | 0.10% |
| fixture-rework | bash | fable5-1m-medium-cli2.1.198 | 1 | 0.7min | 0.1% | $0.28 | 0.10% |
| fixture-rework | default | fable5-1m-high-cli2.1.198 | 1 | 0.7min | 0.1% | $0.33 | 0.12% |
| fixture-rework | typescript-bun | fable5-1m-medium-cli2.1.198 | 1 | 2.0min | 0.3% | $0.78 | 0.28% |


<details>
<summary>Sorted by time lost (least first)</summary>

| Trap | Language | Model | Fell In | Time Lost | % of Time | $ Lost | % of $ |
|------|------|-------|---------|-----------|-----------|--------|--------|
| fixture-rework | bash | fable5-1m-high-cli2.1.198 | 1 | 0.7min | 0.1% | $0.28 | 0.10% |
| fixture-rework | bash | fable5-1m-medium-cli2.1.198 | 1 | 0.7min | 0.1% | $0.28 | 0.10% |
| fixture-rework | default | fable5-1m-high-cli2.1.198 | 1 | 0.7min | 0.1% | $0.33 | 0.12% |
| fixture-rework | typescript-bun | fable5-1m-medium-cli2.1.198 | 1 | 2.0min | 0.3% | $0.78 | 0.28% |
| repeated-test-reruns | powershell | fable5-1m-medium-cli2.1.198 | 1 | 2.7min | 0.4% | $1.07 | 0.38% |
| repeated-test-reruns | typescript-bun | fable5-1m-medium-cli2.1.198 | 3 | 5.3min | 0.8% | $2.04 | 0.72% |
| repeated-test-reruns | bash | fable5-1m-medium-cli2.1.198 | 4 | 7.0min | 1.0% | $3.27 | 1.15% |
| repeated-test-reruns | powershell | fable5-1m-high-cli2.1.198 | 3 | 7.3min | 1.1% | $2.76 | 0.97% |
| repeated-test-reruns | default | fable5-1m-medium-cli2.1.198 | 4 | 8.3min | 1.2% | $3.61 | 1.27% |
| repeated-test-reruns | typescript-bun | fable5-1m-high-cli2.1.198 | 6 | 12.0min | 1.8% | $6.01 | 2.11% |
| repeated-test-reruns | bash | fable5-1m-high-cli2.1.198 | 7 | 16.3min | 2.4% | $7.68 | 2.70% |
| repeated-test-reruns | default | fable5-1m-high-cli2.1.198 | 5 | 17.3min | 2.6% | $9.15 | 3.21% |

</details>

<details>
<summary>Sorted by $ lost (least first)</summary>

| Trap | Language | Model | Fell In | Time Lost | % of Time | $ Lost | % of $ |
|------|------|-------|---------|-----------|-----------|--------|--------|
| fixture-rework | bash | fable5-1m-high-cli2.1.198 | 1 | 0.7min | 0.1% | $0.28 | 0.10% |
| fixture-rework | bash | fable5-1m-medium-cli2.1.198 | 1 | 0.7min | 0.1% | $0.28 | 0.10% |
| fixture-rework | default | fable5-1m-high-cli2.1.198 | 1 | 0.7min | 0.1% | $0.33 | 0.12% |
| fixture-rework | typescript-bun | fable5-1m-medium-cli2.1.198 | 1 | 2.0min | 0.3% | $0.78 | 0.28% |
| repeated-test-reruns | powershell | fable5-1m-medium-cli2.1.198 | 1 | 2.7min | 0.4% | $1.07 | 0.38% |
| repeated-test-reruns | typescript-bun | fable5-1m-medium-cli2.1.198 | 3 | 5.3min | 0.8% | $2.04 | 0.72% |
| repeated-test-reruns | powershell | fable5-1m-high-cli2.1.198 | 3 | 7.3min | 1.1% | $2.76 | 0.97% |
| repeated-test-reruns | bash | fable5-1m-medium-cli2.1.198 | 4 | 7.0min | 1.0% | $3.27 | 1.15% |
| repeated-test-reruns | default | fable5-1m-medium-cli2.1.198 | 4 | 8.3min | 1.2% | $3.61 | 1.27% |
| repeated-test-reruns | typescript-bun | fable5-1m-high-cli2.1.198 | 6 | 12.0min | 1.8% | $6.01 | 2.11% |
| repeated-test-reruns | bash | fable5-1m-high-cli2.1.198 | 7 | 16.3min | 2.4% | $7.68 | 2.70% |
| repeated-test-reruns | default | fable5-1m-high-cli2.1.198 | 5 | 17.3min | 2.6% | $9.15 | 3.21% |

</details>

<details>
<summary>Sorted by fell-in count (fewest first)</summary>

| Trap | Language | Model | Fell In | Time Lost | % of Time | $ Lost | % of $ |
|------|------|-------|---------|-----------|-----------|--------|--------|
| repeated-test-reruns | powershell | fable5-1m-medium-cli2.1.198 | 1 | 2.7min | 0.4% | $1.07 | 0.38% |
| fixture-rework | bash | fable5-1m-high-cli2.1.198 | 1 | 0.7min | 0.1% | $0.28 | 0.10% |
| fixture-rework | bash | fable5-1m-medium-cli2.1.198 | 1 | 0.7min | 0.1% | $0.28 | 0.10% |
| fixture-rework | default | fable5-1m-high-cli2.1.198 | 1 | 0.7min | 0.1% | $0.33 | 0.12% |
| fixture-rework | typescript-bun | fable5-1m-medium-cli2.1.198 | 1 | 2.0min | 0.3% | $0.78 | 0.28% |
| repeated-test-reruns | powershell | fable5-1m-high-cli2.1.198 | 3 | 7.3min | 1.1% | $2.76 | 0.97% |
| repeated-test-reruns | typescript-bun | fable5-1m-medium-cli2.1.198 | 3 | 5.3min | 0.8% | $2.04 | 0.72% |
| repeated-test-reruns | bash | fable5-1m-medium-cli2.1.198 | 4 | 7.0min | 1.0% | $3.27 | 1.15% |
| repeated-test-reruns | default | fable5-1m-medium-cli2.1.198 | 4 | 8.3min | 1.2% | $3.61 | 1.27% |
| repeated-test-reruns | default | fable5-1m-high-cli2.1.198 | 5 | 17.3min | 2.6% | $9.15 | 3.21% |
| repeated-test-reruns | typescript-bun | fable5-1m-high-cli2.1.198 | 6 | 12.0min | 1.8% | $6.01 | 2.11% |
| repeated-test-reruns | bash | fable5-1m-high-cli2.1.198 | 7 | 16.3min | 2.4% | $7.68 | 2.70% |

</details>

#### Trap Descriptions

- **fixture-rework**: Agent rewrote or edited the same fixture file multiple times (genuine redo cycles, not one-time fixture creation).
- **repeated-test-reruns**: Same test command executed 4+ times without the underlying code changing.

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
| bash | fable5-1m-high-cli2.1.198 | 7 | 8 | 17.0min | 2.5% | $7.96 | 2.79% |
| bash | fable5-1m-medium-cli2.1.198 | 7 | 5 | 7.7min | 1.1% | $3.55 | 1.25% |
| default | fable5-1m-high-cli2.1.198 | 7 | 6 | 18.0min | 2.7% | $9.48 | 3.33% |
| default | fable5-1m-medium-cli2.1.198 | 7 | 4 | 8.3min | 1.2% | $3.61 | 1.27% |
| powershell | fable5-1m-high-cli2.1.198 | 7 | 3 | 7.3min | 1.1% | $2.76 | 0.97% |
| powershell | fable5-1m-medium-cli2.1.198 | 7 | 1 | 2.7min | 0.4% | $1.07 | 0.38% |
| typescript-bun | fable5-1m-high-cli2.1.198 | 7 | 6 | 12.0min | 1.8% | $6.01 | 2.11% |
| typescript-bun | fable5-1m-medium-cli2.1.198 | 7 | 4 | 7.3min | 1.1% | $2.83 | 0.99% |


<details>
<summary>Sorted by time lost (least first)</summary>

| Language | Model | Runs | Traps | Time Lost | % of Time | $ Lost | % of $ |
|------|-------|------|-------|-----------|-----------|--------|--------|
| powershell | fable5-1m-medium-cli2.1.198 | 7 | 1 | 2.7min | 0.4% | $1.07 | 0.38% |
| powershell | fable5-1m-high-cli2.1.198 | 7 | 3 | 7.3min | 1.1% | $2.76 | 0.97% |
| typescript-bun | fable5-1m-medium-cli2.1.198 | 7 | 4 | 7.3min | 1.1% | $2.83 | 0.99% |
| bash | fable5-1m-medium-cli2.1.198 | 7 | 5 | 7.7min | 1.1% | $3.55 | 1.25% |
| default | fable5-1m-medium-cli2.1.198 | 7 | 4 | 8.3min | 1.2% | $3.61 | 1.27% |
| typescript-bun | fable5-1m-high-cli2.1.198 | 7 | 6 | 12.0min | 1.8% | $6.01 | 2.11% |
| bash | fable5-1m-high-cli2.1.198 | 7 | 8 | 17.0min | 2.5% | $7.96 | 2.79% |
| default | fable5-1m-high-cli2.1.198 | 7 | 6 | 18.0min | 2.7% | $9.48 | 3.33% |

</details>

<details>
<summary>Sorted by $ lost (least first)</summary>

| Language | Model | Runs | Traps | Time Lost | % of Time | $ Lost | % of $ |
|------|-------|------|-------|-----------|-----------|--------|--------|
| powershell | fable5-1m-medium-cli2.1.198 | 7 | 1 | 2.7min | 0.4% | $1.07 | 0.38% |
| powershell | fable5-1m-high-cli2.1.198 | 7 | 3 | 7.3min | 1.1% | $2.76 | 0.97% |
| typescript-bun | fable5-1m-medium-cli2.1.198 | 7 | 4 | 7.3min | 1.1% | $2.83 | 0.99% |
| bash | fable5-1m-medium-cli2.1.198 | 7 | 5 | 7.7min | 1.1% | $3.55 | 1.25% |
| default | fable5-1m-medium-cli2.1.198 | 7 | 4 | 8.3min | 1.2% | $3.61 | 1.27% |
| typescript-bun | fable5-1m-high-cli2.1.198 | 7 | 6 | 12.0min | 1.8% | $6.01 | 2.11% |
| bash | fable5-1m-high-cli2.1.198 | 7 | 8 | 17.0min | 2.5% | $7.96 | 2.79% |
| default | fable5-1m-high-cli2.1.198 | 7 | 6 | 18.0min | 2.7% | $9.48 | 3.33% |

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
| bash | fable5-1m-high | 29.0 | 70.0 | 2.4 | 0.80 |
| bash | fable5-1m-medium | 22.6 | 46.3 | 2.1 | 0.69 |
| default | fable5-1m-high | 27.4 | 50.6 | 1.8 | 0.95 |
| default | fable5-1m-medium | 22.9 | 43.7 | 1.9 | 0.96 |
| powershell | fable5-1m-high | 41.9 | 77.9 | 1.9 | 3.58 |
| powershell | fable5-1m-medium | 36.9 | 69.1 | 1.9 | 5.45 |
| typescript-bun | fable5-1m-high | 39.6 | 75.1 | 1.9 | 0.84 |
| typescript-bun | fable5-1m-medium | 34.4 | 67.1 | 2.0 | 1.17 |


<details>
<summary>Sorted by avg tests (most first)</summary>

| Language | Model | Avg Tests | Avg Assertions | Avg Assert/Test | Avg Test:Code Ratio |
|------|-------|-----------|----------------|-----------------|---------------------|
| powershell | fable5-1m-high | 41.9 | 77.9 | 1.9 | 3.58 |
| typescript-bun | fable5-1m-high | 39.6 | 75.1 | 1.9 | 0.84 |
| powershell | fable5-1m-medium | 36.9 | 69.1 | 1.9 | 5.45 |
| typescript-bun | fable5-1m-medium | 34.4 | 67.1 | 2.0 | 1.17 |
| bash | fable5-1m-high | 29.0 | 70.0 | 2.4 | 0.80 |
| default | fable5-1m-high | 27.4 | 50.6 | 1.8 | 0.95 |
| default | fable5-1m-medium | 22.9 | 43.7 | 1.9 | 0.96 |
| bash | fable5-1m-medium | 22.6 | 46.3 | 2.1 | 0.69 |

</details>

<details>
<summary>Sorted by avg assertions (most first)</summary>

| Language | Model | Avg Tests | Avg Assertions | Avg Assert/Test | Avg Test:Code Ratio |
|------|-------|-----------|----------------|-----------------|---------------------|
| powershell | fable5-1m-high | 41.9 | 77.9 | 1.9 | 3.58 |
| typescript-bun | fable5-1m-high | 39.6 | 75.1 | 1.9 | 0.84 |
| bash | fable5-1m-high | 29.0 | 70.0 | 2.4 | 0.80 |
| powershell | fable5-1m-medium | 36.9 | 69.1 | 1.9 | 5.45 |
| typescript-bun | fable5-1m-medium | 34.4 | 67.1 | 2.0 | 1.17 |
| default | fable5-1m-high | 27.4 | 50.6 | 1.8 | 0.95 |
| bash | fable5-1m-medium | 22.6 | 46.3 | 2.1 | 0.69 |
| default | fable5-1m-medium | 22.9 | 43.7 | 1.9 | 0.96 |

</details>

<details>
<summary>Sorted by avg test:code ratio (highest first)</summary>

| Language | Model | Avg Tests | Avg Assertions | Avg Assert/Test | Avg Test:Code Ratio |
|------|-------|-----------|----------------|-----------------|---------------------|
| powershell | fable5-1m-medium | 36.9 | 69.1 | 1.9 | 5.45 |
| powershell | fable5-1m-high | 41.9 | 77.9 | 1.9 | 3.58 |
| typescript-bun | fable5-1m-medium | 34.4 | 67.1 | 2.0 | 1.17 |
| default | fable5-1m-medium | 22.9 | 43.7 | 1.9 | 0.96 |
| default | fable5-1m-high | 27.4 | 50.6 | 1.8 | 0.95 |
| typescript-bun | fable5-1m-high | 39.6 | 75.1 | 1.9 | 0.84 |
| bash | fable5-1m-high | 29.0 | 70.0 | 2.4 | 0.80 |
| bash | fable5-1m-medium | 22.6 | 46.3 | 2.1 | 0.69 |

</details>


<details>
<summary>Per-run structural metrics</summary>

| Task | Language | Model | Tests | Assertions | Assert/Test | Test Lines | Impl Lines | Test:Code |
|------|------|-------|-------|------------|-------------|------------|------------|-----------|
| Semantic Version Bumper | bash | fable5-1m-high | 31 | 86 | 2.8 | 316 | 357 | 0.89 |
| Semantic Version Bumper | bash | fable5-1m-medium | 32 | 57 | 1.8 | 269 | 274 | 0.98 |
| Semantic Version Bumper | default | fable5-1m-high | 0 | 0 | 0.0 | 80 | 0 | 0.00 |
| Semantic Version Bumper | default | fable5-1m-medium | 0 | 0 | 0.0 | 95 | 0 | 0.00 |
| Semantic Version Bumper | powershell | fable5-1m-high | 41 | 78 | 1.9 | 521 | 54 | 9.65 |
| Semantic Version Bumper | powershell | fable5-1m-medium | 43 | 79 | 1.8 | 471 | 45 | 10.47 |
| Semantic Version Bumper | typescript-bun | fable5-1m-high | 54 | 93 | 1.7 | 547 | 571 | 0.96 |
| Semantic Version Bumper | typescript-bun | fable5-1m-medium | 41 | 66 | 1.6 | 365 | 504 | 0.72 |
| PR Label Assigner | bash | fable5-1m-high | 26 | 58 | 2.2 | 327 | 309 | 1.06 |
| PR Label Assigner | bash | fable5-1m-medium | 25 | 39 | 1.6 | 215 | 276 | 0.78 |
| PR Label Assigner | default | fable5-1m-high | 31 | 43 | 1.4 | 302 | 326 | 0.93 |
| PR Label Assigner | default | fable5-1m-medium | 28 | 45 | 1.6 | 314 | 163 | 1.93 |
| PR Label Assigner | powershell | fable5-1m-high | 44 | 49 | 1.1 | 338 | 211 | 1.60 |
| PR Label Assigner | powershell | fable5-1m-medium | 37 | 47 | 1.3 | 299 | 170 | 1.76 |
| PR Label Assigner | typescript-bun | fable5-1m-high | 37 | 59 | 1.6 | 385 | 432 | 0.89 |
| PR Label Assigner | typescript-bun | fable5-1m-medium | 32 | 73 | 2.3 | 511 | 214 | 2.39 |
| Dependency License Checker | bash | fable5-1m-high | 25 | 74 | 3.0 | 244 | 349 | 0.70 |
| Dependency License Checker | bash | fable5-1m-medium | 19 | 36 | 1.9 | 158 | 257 | 0.61 |
| Dependency License Checker | default | fable5-1m-high | 19 | 26 | 1.4 | 239 | 214 | 1.12 |
| Dependency License Checker | default | fable5-1m-medium | 24 | 33 | 1.4 | 312 | 360 | 0.87 |
| Dependency License Checker | powershell | fable5-1m-high | 48 | 80 | 1.7 | 593 | 73 | 8.12 |
| Dependency License Checker | powershell | fable5-1m-medium | 38 | 65 | 1.7 | 480 | 79 | 6.08 |
| Dependency License Checker | typescript-bun | fable5-1m-high | 28 | 50 | 1.8 | 460 | 544 | 0.85 |
| Dependency License Checker | typescript-bun | fable5-1m-medium | 34 | 50 | 1.5 | 422 | 510 | 0.83 |
| Test Results Aggregator | bash | fable5-1m-high | 25 | 64 | 2.6 | 250 | 416 | 0.60 |
| Test Results Aggregator | bash | fable5-1m-medium | 26 | 60 | 2.3 | 240 | 327 | 0.73 |
| Test Results Aggregator | default | fable5-1m-high | 20 | 65 | 3.2 | 320 | 523 | 0.61 |
| Test Results Aggregator | default | fable5-1m-medium | 26 | 59 | 2.3 | 345 | 420 | 0.82 |
| Test Results Aggregator | powershell | fable5-1m-high | 43 | 72 | 1.7 | 340 | 229 | 1.48 |
| Test Results Aggregator | powershell | fable5-1m-medium | 43 | 86 | 2.0 | 497 | 66 | 7.53 |
| Test Results Aggregator | typescript-bun | fable5-1m-high | 42 | 71 | 1.7 | 503 | 661 | 0.76 |
| Test Results Aggregator | typescript-bun | fable5-1m-medium | 33 | 70 | 2.1 | 661 | 487 | 1.36 |
| Environment Matrix Generator | bash | fable5-1m-high | 41 | 71 | 1.7 | 300 | 354 | 0.85 |
| Environment Matrix Generator | bash | fable5-1m-medium | 16 | 23 | 1.4 | 138 | 233 | 0.59 |
| Environment Matrix Generator | default | fable5-1m-high | 38 | 64 | 1.7 | 441 | 216 | 2.04 |
| Environment Matrix Generator | default | fable5-1m-medium | 25 | 53 | 2.1 | 279 | 377 | 0.74 |
| Environment Matrix Generator | powershell | fable5-1m-high | 51 | 112 | 2.2 | 586 | 353 | 1.66 |
| Environment Matrix Generator | powershell | fable5-1m-medium | 31 | 63 | 2.0 | 399 | 42 | 9.50 |
| Environment Matrix Generator | typescript-bun | fable5-1m-high | 32 | 69 | 2.2 | 403 | 553 | 0.73 |
| Environment Matrix Generator | typescript-bun | fable5-1m-medium | 27 | 50 | 1.9 | 384 | 422 | 0.91 |
| Artifact Cleanup Script | bash | fable5-1m-high | 24 | 58 | 2.4 | 226 | 327 | 0.69 |
| Artifact Cleanup Script | bash | fable5-1m-medium | 18 | 50 | 2.8 | 185 | 335 | 0.55 |
| Artifact Cleanup Script | default | fable5-1m-high | 43 | 87 | 2.0 | 571 | 578 | 0.99 |
| Artifact Cleanup Script | default | fable5-1m-medium | 25 | 54 | 2.2 | 337 | 441 | 0.76 |
| Artifact Cleanup Script | powershell | fable5-1m-high | 30 | 68 | 2.3 | 376 | 282 | 1.33 |
| Artifact Cleanup Script | powershell | fable5-1m-medium | 27 | 65 | 2.4 | 348 | 298 | 1.17 |
| Artifact Cleanup Script | typescript-bun | fable5-1m-high | 39 | 90 | 2.3 | 563 | 795 | 0.71 |
| Artifact Cleanup Script | typescript-bun | fable5-1m-medium | 33 | 75 | 2.3 | 579 | 437 | 1.32 |
| Secret Rotation Validator | bash | fable5-1m-high | 31 | 79 | 2.5 | 268 | 322 | 0.83 |
| Secret Rotation Validator | bash | fable5-1m-medium | 22 | 59 | 2.7 | 205 | 355 | 0.58 |
| Secret Rotation Validator | default | fable5-1m-high | 41 | 69 | 1.7 | 487 | 519 | 0.94 |
| Secret Rotation Validator | default | fable5-1m-medium | 32 | 62 | 1.9 | 370 | 233 | 1.59 |
| Secret Rotation Validator | powershell | fable5-1m-high | 36 | 86 | 2.4 | 387 | 316 | 1.22 |
| Secret Rotation Validator | powershell | fable5-1m-medium | 39 | 79 | 2.0 | 460 | 279 | 1.65 |
| Secret Rotation Validator | typescript-bun | fable5-1m-high | 45 | 94 | 2.1 | 569 | 596 | 0.95 |
| Secret Rotation Validator | typescript-bun | fable5-1m-medium | 41 | 86 | 2.1 | 496 | 733 | 0.68 |

</details>

### LLM-as-Judge Scores

An LLM evaluates each test suite on four dimensions (1-5 scale):

- **Coverage** (1-5): Do tests exercise the key requirements? 1 = most untested, 5 = all covered.
- **Rigor** (1-5): Edge cases, error handling, boundary conditions? 1 = happy path only, 5 = thorough.
- **Design** (1-5): Test organization, fixtures, readability? 1 = messy/brittle, 5 = well-structured.
- **Overall** (1-5): Holistic quality — would you trust this suite to catch regressions? 1 = no, 5 = absolutely. Use this as the primary ranking metric.

| Language | Model | Avg Overall | Avg Coverage | Avg Rigor | Avg Design | Judge Cost |
|------|-------|-------------|-------------|-----------|------------|------------|
| bash | fable5-1m-high | **4.3** | 4.5 | 4.3 | 4.4 | $0.3991 |
| bash | fable5-1m-medium | **4.1** | 4.4 | 4.0 | 4.2 | $0.3756 |
| default | fable5-1m-high | **3.2** | 3.4 | 3.5 | 3.9 | $0.4114 |
| default | fable5-1m-medium | **3.2** | 3.4 | 3.5 | 4.1 | $0.3536 |
| powershell | fable5-1m-high | **4.4** | 4.5 | 4.4 | 4.6 | $0.3989 |
| powershell | fable5-1m-medium | **4.5** | 4.6 | 4.5 | 4.4 | $0.3668 |
| typescript-bun | fable5-1m-high | **4.3** | 4.4 | 4.4 | 4.4 | $0.5138 |
| typescript-bun | fable5-1m-medium | **4.4** | 4.6 | 4.4 | 4.7 | $0.5210 |
| **Total** | | | | | | **$3.3402** |


<details>
<summary>Sorted by avg overall (highest first)</summary>

| Language | Model | Avg Overall | Avg Coverage | Avg Rigor | Avg Design | Judge Cost |
|------|-------|-------------|-------------|-----------|------------|------------|
| powershell | fable5-1m-medium | **4.5** | 4.6 | 4.5 | 4.4 | $0.3668 |
| typescript-bun | fable5-1m-medium | **4.4** | 4.6 | 4.4 | 4.7 | $0.5210 |
| powershell | fable5-1m-high | **4.4** | 4.5 | 4.4 | 4.6 | $0.3989 |
| bash | fable5-1m-high | **4.3** | 4.5 | 4.3 | 4.4 | $0.3991 |
| typescript-bun | fable5-1m-high | **4.3** | 4.4 | 4.4 | 4.4 | $0.5138 |
| bash | fable5-1m-medium | **4.1** | 4.4 | 4.0 | 4.2 | $0.3756 |
| default | fable5-1m-high | **3.2** | 3.4 | 3.5 | 3.9 | $0.4114 |
| default | fable5-1m-medium | **3.2** | 3.4 | 3.5 | 4.1 | $0.3536 |

</details>

<details>
<summary>Sorted by avg coverage (highest first)</summary>

| Language | Model | Avg Overall | Avg Coverage | Avg Rigor | Avg Design | Judge Cost |
|------|-------|-------------|-------------|-----------|------------|------------|
| typescript-bun | fable5-1m-medium | **4.4** | 4.6 | 4.4 | 4.7 | $0.5210 |
| powershell | fable5-1m-medium | **4.5** | 4.6 | 4.5 | 4.4 | $0.3668 |
| bash | fable5-1m-high | **4.3** | 4.5 | 4.3 | 4.4 | $0.3991 |
| powershell | fable5-1m-high | **4.4** | 4.5 | 4.4 | 4.6 | $0.3989 |
| bash | fable5-1m-medium | **4.1** | 4.4 | 4.0 | 4.2 | $0.3756 |
| typescript-bun | fable5-1m-high | **4.3** | 4.4 | 4.4 | 4.4 | $0.5138 |
| default | fable5-1m-high | **3.2** | 3.4 | 3.5 | 3.9 | $0.4114 |
| default | fable5-1m-medium | **3.2** | 3.4 | 3.5 | 4.1 | $0.3536 |

</details>

<details>
<summary>Sorted by avg rigor (highest first)</summary>

| Language | Model | Avg Overall | Avg Coverage | Avg Rigor | Avg Design | Judge Cost |
|------|-------|-------------|-------------|-----------|------------|------------|
| powershell | fable5-1m-medium | **4.5** | 4.6 | 4.5 | 4.4 | $0.3668 |
| typescript-bun | fable5-1m-high | **4.3** | 4.4 | 4.4 | 4.4 | $0.5138 |
| powershell | fable5-1m-high | **4.4** | 4.5 | 4.4 | 4.6 | $0.3989 |
| typescript-bun | fable5-1m-medium | **4.4** | 4.6 | 4.4 | 4.7 | $0.5210 |
| bash | fable5-1m-high | **4.3** | 4.5 | 4.3 | 4.4 | $0.3991 |
| bash | fable5-1m-medium | **4.1** | 4.4 | 4.0 | 4.2 | $0.3756 |
| default | fable5-1m-high | **3.2** | 3.4 | 3.5 | 3.9 | $0.4114 |
| default | fable5-1m-medium | **3.2** | 3.4 | 3.5 | 4.1 | $0.3536 |

</details>

<details>
<summary>Sorted by avg design (highest first)</summary>

| Language | Model | Avg Overall | Avg Coverage | Avg Rigor | Avg Design | Judge Cost |
|------|-------|-------------|-------------|-----------|------------|------------|
| typescript-bun | fable5-1m-medium | **4.4** | 4.6 | 4.4 | 4.7 | $0.5210 |
| powershell | fable5-1m-high | **4.4** | 4.5 | 4.4 | 4.6 | $0.3989 |
| bash | fable5-1m-high | **4.3** | 4.5 | 4.3 | 4.4 | $0.3991 |
| powershell | fable5-1m-medium | **4.5** | 4.6 | 4.5 | 4.4 | $0.3668 |
| typescript-bun | fable5-1m-high | **4.3** | 4.4 | 4.4 | 4.4 | $0.5138 |
| bash | fable5-1m-medium | **4.1** | 4.4 | 4.0 | 4.2 | $0.3756 |
| default | fable5-1m-medium | **3.2** | 3.4 | 3.5 | 4.1 | $0.3536 |
| default | fable5-1m-high | **3.2** | 3.4 | 3.5 | 3.9 | $0.4114 |

</details>


<details>
<summary>Per-run LLM judge scores</summary>

| Task | Language | Model | Cov | Rig | Des | Ovr | Summary |
|------|------|-------|-----|-----|-----|-----|---------|
| Semantic Version Bumper | bash | fable5-1m-high | 4.5 | 4.5 | 4.5 | 4.5 |  |
| Semantic Version Bumper | bash | fable5-1m-medium | 4.5 | 4.0 | 4.5 | 4.5 |  |
| Semantic Version Bumper | default | fable5-1m-high | 1.5 | 1.5 | 2.5 | 1.5 |  |
| Semantic Version Bumper | default | fable5-1m-medium | 1.0 | 1.5 | 2.5 | 1.0 |  |
| Semantic Version Bumper | powershell | fable5-1m-high | 4.0 | 4.0 | 4.5 | 4.0 |  |
| Semantic Version Bumper | powershell | fable5-1m-medium | 4.5 | 4.5 | 4.5 | 4.5 |  |
| Semantic Version Bumper | typescript-bun | fable5-1m-high | 5.0 | 4.5 | 5.0 | 4.5 |  |
| Semantic Version Bumper | typescript-bun | fable5-1m-medium | 5.0 | 5.0 | 5.0 | 5.0 |  |
| PR Label Assigner | bash | fable5-1m-high | 4.0 | 4.0 | 4.5 | 4.0 |  |
| PR Label Assigner | bash | fable5-1m-medium | 4.5 | 4.5 | 4.5 | 4.5 |  |
| PR Label Assigner | default | fable5-1m-high | 5.0 | 4.0 | 4.5 | 4.5 |  |
| PR Label Assigner | default | fable5-1m-medium | 2.5 | 2.5 | 4.0 | 2.0 |  |
| PR Label Assigner | powershell | fable5-1m-high | 5.0 | 4.5 | 5.0 | 4.5 |  |
| PR Label Assigner | powershell | fable5-1m-medium | 4.5 | 4.5 | 4.5 | 4.5 |  |
| PR Label Assigner | typescript-bun | fable5-1m-high | 4.5 | 4.5 | 4.5 | 4.5 |  |
| PR Label Assigner | typescript-bun | fable5-1m-medium | 5.0 | 4.5 | 4.5 | 4.5 |  |
| Dependency License Checker | bash | fable5-1m-high | 4.5 | 4.0 | 4.5 | 4.0 |  |
| Dependency License Checker | bash | fable5-1m-medium | 4.5 | 3.5 | 4.5 | 4.0 |  |
| Dependency License Checker | default | fable5-1m-high | 2.0 | 2.5 | 3.5 | 2.0 |  |
| Dependency License Checker | default | fable5-1m-medium | 4.5 | 4.5 | 4.5 | 4.5 |  |
| Dependency License Checker | powershell | fable5-1m-high | 4.5 | 4.5 | 4.5 | 4.5 |  |
| Dependency License Checker | powershell | fable5-1m-medium | 4.5 | 4.5 | 4.0 | 4.5 |  |
| Dependency License Checker | typescript-bun | fable5-1m-high | 4.5 | 4.5 | 4.5 | 4.5 |  |
| Dependency License Checker | typescript-bun | fable5-1m-medium | 4.0 | 4.0 | 4.5 | 4.0 |  |
| Test Results Aggregator | bash | fable5-1m-high | 5.0 | 4.5 | 4.5 | 4.5 |  |
| Test Results Aggregator | bash | fable5-1m-medium | 4.0 | 3.5 | 4.0 | 4.0 |  |
| Test Results Aggregator | default | fable5-1m-high | 4.5 | 4.0 | 4.5 | 4.0 |  |
| Test Results Aggregator | default | fable5-1m-medium | 5.0 | 5.0 | 5.0 | 5.0 |  |
| Test Results Aggregator | powershell | fable5-1m-high | 4.0 | 4.0 | 4.5 | 4.0 |  |
| Test Results Aggregator | powershell | fable5-1m-medium | 4.5 | 4.5 | 4.5 | 4.5 |  |
| Test Results Aggregator | typescript-bun | fable5-1m-high | 3.5 | 4.0 | 4.0 | 3.5 |  |
| Test Results Aggregator | typescript-bun | fable5-1m-medium | 5.0 | 4.0 | 5.0 | 4.5 |  |
| Environment Matrix Generator | bash | fable5-1m-high | 4.0 | 4.0 | 4.0 | 4.0 |  |
| Environment Matrix Generator | bash | fable5-1m-medium | 4.5 | 4.5 | 4.5 | 4.5 |  |
| Environment Matrix Generator | default | fable5-1m-high | 2.5 | 3.5 | 3.5 | 2.0 |  |
| Environment Matrix Generator | default | fable5-1m-medium | 4.5 | 4.0 | 4.5 | 4.0 |  |
| Environment Matrix Generator | powershell | fable5-1m-high | 4.5 | 4.5 | 4.5 | 4.5 |  |
| Environment Matrix Generator | powershell | fable5-1m-medium | 4.5 | 4.5 | 4.5 | 4.5 |  |
| Environment Matrix Generator | typescript-bun | fable5-1m-high | 4.0 | 4.5 | 4.0 | 4.0 |  |
| Environment Matrix Generator | typescript-bun | fable5-1m-medium | 4.5 | 4.5 | 4.5 | 4.5 |  |
| Artifact Cleanup Script | bash | fable5-1m-high | 4.5 | 4.5 | 4.5 | 4.5 |  |
| Artifact Cleanup Script | bash | fable5-1m-medium | 4.5 | 4.0 | 3.5 | 3.5 |  |
| Artifact Cleanup Script | default | fable5-1m-high | 4.5 | 4.5 | 4.5 | 4.5 |  |
| Artifact Cleanup Script | default | fable5-1m-medium | 4.5 | 4.0 | 4.5 | 4.0 |  |
| Artifact Cleanup Script | powershell | fable5-1m-high | 4.5 | 4.5 | 4.5 | 4.5 |  |
| Artifact Cleanup Script | powershell | fable5-1m-medium | 5.0 | 4.5 | 4.5 | 4.5 |  |
| Artifact Cleanup Script | typescript-bun | fable5-1m-high | 4.5 | 4.5 | 4.5 | 4.5 |  |
| Artifact Cleanup Script | typescript-bun | fable5-1m-medium | 4.0 | 4.0 | 4.5 | 4.0 |  |
| Secret Rotation Validator | bash | fable5-1m-high | 5.0 | 4.5 | 4.5 | 4.5 |  |
| Secret Rotation Validator | bash | fable5-1m-medium | 4.5 | 4.0 | 4.0 | 4.0 |  |
| Secret Rotation Validator | default | fable5-1m-high | 4.0 | 4.5 | 4.0 | 4.0 |  |
| Secret Rotation Validator | default | fable5-1m-medium | 2.0 | 3.0 | 4.0 | 2.0 |  |
| Secret Rotation Validator | powershell | fable5-1m-high | 5.0 | 4.5 | 4.5 | 4.5 |  |
| Secret Rotation Validator | powershell | fable5-1m-medium | 4.5 | 4.5 | 4.5 | 4.5 |  |
| Secret Rotation Validator | typescript-bun | fable5-1m-high | 4.5 | 4.5 | 4.5 | 4.5 |  |
| Secret Rotation Validator | typescript-bun | fable5-1m-medium | 5.0 | 4.5 | 5.0 | 4.5 |  |

</details>

### Correlation: Structural Metrics vs Tests Quality

Spearman rank correlation between automated counts and LLM judge scores.
Values near +1.0 indicate the LLM agrees with the structural signal; near 0 means no relationship.

| Structural Metric | vs Coverage | vs Rigor | vs Design | vs Overall |
|-------------------|------------|---------|----------|-----------|
| Test count | 0.12 | 0.37 | 0.3 | 0.32 |
| Assertion count | 0.24 | 0.39 | 0.29 | 0.31 |
| Test:code ratio | -0.01 | 0.16 | 0.13 | 0.2 |

*Based on 56 runs with both structural and LLM scores.*

### LLM vs Structural Discrepancies

**Qualitative disagreements** — structural metrics look reasonable; the LLM judge is weighing factors the counters can't measure.

| Task | Language | Model | Tests | Asserts | Cov | Rig | Des | Ovr | Flag | Justification |
|------|------|-------|-------|---------|-----|-----|-----|-----|------|---------------|
| Secret Rotation Validator | default | fable5-1m-medium | 32 | 62 | 2.0 | 3.0 | 4.0 | 2.0 | LLM says low coverage (2.0/5) but 32 tests detected |  |

## Per-Run Results

*Tests Quality = Overall (1-5) from LLM-as-judge of generated test code (dimensions: coverage, rigor, design). `—` = no judge data.*

| Task | Language | Model | Duration | Turns | Errors | Cost | Tests Quality | Chosen | Status |
|------|----------|-------|----------|-------|--------|------|-----------|--------|--------|
| Artifact Cleanup Script | bash | fable5-1m-high | 11.8min | 49 | 0 | $5.55 | 4.5 | bash | ok |
| Artifact Cleanup Script | bash | fable5-1m-medium | 7.7min | 31 | 5 | $3.53 | 3.5 | bash | ok |
| Artifact Cleanup Script | default | fable5-1m-high | 15.1min | 71 | 0 | $8.50 | 4.5 | python | ok |
| Artifact Cleanup Script | default | fable5-1m-medium | 12.1min | 52 | 0 | $5.22 | 4.0 | python | ok |
| Artifact Cleanup Script | powershell | fable5-1m-high | 17.6min | 46 | 0 | $6.49 | 4.5 | powershell | ok |
| Artifact Cleanup Script | powershell | fable5-1m-medium | 17.1min | 46 | 1 | $6.86 | 4.5 | powershell | ok |
| Artifact Cleanup Script | typescript-bun | fable5-1m-high | 15.2min | 62 | 1 | $9.45 | 4.5 | typescript | ok |
| Artifact Cleanup Script | typescript-bun | fable5-1m-medium | 14.5min | 51 | 0 | $5.68 | 4.0 | typescript | ok |
| Dependency License Checker | bash | fable5-1m-high | 9.9min | 46 | 0 | $4.58 | 4.0 | bash | ok |
| Dependency License Checker | bash | fable5-1m-medium | 6.3min | 36 | 1 | $2.95 | 4.0 | bash | ok |
| Dependency License Checker | default | fable5-1m-high | 9.6min | 46 | 1 | $4.49 | 2.0 | javascript | ok |
| Dependency License Checker | default | fable5-1m-medium | 6.8min | 29 | 2 | $2.90 | 4.5 | python | ok |
| Dependency License Checker | powershell | fable5-1m-high | 16.8min | 41 | 6 | $5.67 | 4.5 | powershell | ok |
| Dependency License Checker | powershell | fable5-1m-medium | 11.2min | 20 | 2 | $3.23 | 4.5 | powershell | ok |
| Dependency License Checker | typescript-bun | fable5-1m-high | 11.7min | 46 | 0 | $4.49 | 4.5 | typescript | ok |
| Dependency License Checker | typescript-bun | fable5-1m-medium | 9.2min | 46 | 0 | $4.24 | 4.0 | typescript | ok |
| Environment Matrix Generator | bash | fable5-1m-high | 11.2min | 45 | 1 | $6.86 | 4.0 | bash | ok |
| Environment Matrix Generator | bash | fable5-1m-medium | 7.5min | 37 | 1 | $3.41 | 4.5 | bash | ok |
| Environment Matrix Generator | default | fable5-1m-high | 13.5min | 65 | 1 | $6.97 | 2.0 | python | ok |
| Environment Matrix Generator | default | fable5-1m-medium | 10.6min | 47 | 2 | $4.57 | 4.0 | python | ok |
| Environment Matrix Generator | powershell | fable5-1m-high | 21.5min | 45 | 8 | $7.73 | 4.5 | powershell | ok |
| Environment Matrix Generator | powershell | fable5-1m-medium | 12.6min | 34 | 6 | $4.34 | 4.5 | powershell | ok |
| Environment Matrix Generator | typescript-bun | fable5-1m-high | 15.1min | 55 | 4 | $6.33 | 4.0 | typescript | ok |
| Environment Matrix Generator | typescript-bun | fable5-1m-medium | 7.9min | 36 | 3 | $5.00 | 4.5 | typescript | ok |
| PR Label Assigner | bash | fable5-1m-high | 11.7min | 46 | 2 | $4.85 | 4.0 | bash | ok |
| PR Label Assigner | bash | fable5-1m-medium | 8.6min | 46 | 2 | $4.15 | 4.5 | bash | ok |
| PR Label Assigner | default | fable5-1m-high | 9.0min | 41 | 1 | $3.87 | 4.5 | python | ok |
| PR Label Assigner | default | fable5-1m-medium | 6.8min | 35 | 1 | $3.04 | 2.0 | python | ok |
| PR Label Assigner | powershell | fable5-1m-high | 12.5min | 43 | 1 | $5.49 | 4.5 | powershell | ok |
| PR Label Assigner | powershell | fable5-1m-medium | 12.0min | 32 | 1 | $3.41 | 4.5 | powershell | ok |
| PR Label Assigner | typescript-bun | fable5-1m-high | 9.8min | 47 | 0 | $4.64 | 4.5 | typescript | ok |
| PR Label Assigner | typescript-bun | fable5-1m-medium | 11.9min | 46 | 0 | $4.46 | 4.5 | typescript | ok |
| Secret Rotation Validator | bash | fable5-1m-high | 12.5min | 48 | 3 | $5.19 | 4.5 | bash | ok |
| Secret Rotation Validator | bash | fable5-1m-medium | 9.4min | 37 | 0 | $3.92 | 4.0 | bash | ok |
| Secret Rotation Validator | default | fable5-1m-high | 12.3min | 58 | 1 | $7.27 | 4.0 | python | ok |
| Secret Rotation Validator | default | fable5-1m-medium | 7.3min | 32 | 0 | $3.13 | 2.0 | python | ok |
| Secret Rotation Validator | powershell | fable5-1m-high | 17.4min | 37 | 6 | $5.79 | 4.5 | powershell | ok |
| Secret Rotation Validator | powershell | fable5-1m-medium | 18.0min | 30 | 5 | $5.33 | 4.5 | powershell | ok |
| Secret Rotation Validator | typescript-bun | fable5-1m-high | 11.5min | 51 | 1 | $5.95 | 4.5 | typescript | ok |
| Secret Rotation Validator | typescript-bun | fable5-1m-medium | 12.7min | 42 | 0 | $4.84 | 4.5 | typescript | ok |
| Semantic Version Bumper | bash | fable5-1m-high | 12.0min | 55 | 1 | $5.33 | 4.5 | bash | ok |
| Semantic Version Bumper | bash | fable5-1m-medium | 8.4min | 39 | 1 | $3.99 | 4.5 | bash | ok |
| Semantic Version Bumper | default | fable5-1m-high | 12.9min | 52 | 1 | $6.53 | 1.5 | javascript | ok |
| Semantic Version Bumper | default | fable5-1m-medium | 9.1min | 35 | 2 | $4.21 | 1.0 | javascript | ok |
| Semantic Version Bumper | powershell | fable5-1m-high | 19.3min | 47 | 2 | $5.82 | 4.0 | powershell | ok |
| Semantic Version Bumper | powershell | fable5-1m-medium | 19.0min | 36 | 4 | $4.65 | 4.5 | powershell | ok |
| Semantic Version Bumper | typescript-bun | fable5-1m-high | 11.2min | 48 | 1 | $6.25 | 4.5 | typescript | ok |
| Semantic Version Bumper | typescript-bun | fable5-1m-medium | 8.9min | 36 | 0 | $3.39 | 5.0 | typescript | ok |
| Test Results Aggregator | bash | fable5-1m-high | 13.7min | 52 | 2 | $6.27 | 4.5 | bash | ok |
| Test Results Aggregator | bash | fable5-1m-medium | 7.8min | 34 | 3 | $3.46 | 4.0 | bash | ok |
| Test Results Aggregator | default | fable5-1m-high | 8.4min | 39 | 0 | $4.18 | 4.0 | python | ok |
| Test Results Aggregator | default | fable5-1m-medium | 9.8min | 47 | 1 | $5.30 | 5.0 | python | ok |
| Test Results Aggregator | powershell | fable5-1m-high | 15.0min | 46 | 6 | $5.05 | 4.0 | powershell | ok |
| Test Results Aggregator | powershell | fable5-1m-medium | 15.2min | 40 | 5 | $5.09 | 4.5 | powershell | ok |
| Test Results Aggregator | typescript-bun | fable5-1m-high | 11.7min | 55 | 2 | $5.91 | 3.5 | typescript | ok |
| Test Results Aggregator | typescript-bun | fable5-1m-medium | 10.7min | 46 | 0 | $4.98 | 4.5 | typescript | ok |


<details>
<summary>Sorted by cost (cheapest first)</summary>

| Task | Language | Model | Duration | Turns | Errors | Cost | Tests Quality | Chosen | Status |
|------|----------|-------|----------|-------|--------|------|-----------|--------|--------|
| Dependency License Checker | default | fable5-1m-medium | 6.8min | 29 | 2 | $2.90 | 4.5 | python | ok |
| Dependency License Checker | bash | fable5-1m-medium | 6.3min | 36 | 1 | $2.95 | 4.0 | bash | ok |
| PR Label Assigner | default | fable5-1m-medium | 6.8min | 35 | 1 | $3.04 | 2.0 | python | ok |
| Secret Rotation Validator | default | fable5-1m-medium | 7.3min | 32 | 0 | $3.13 | 2.0 | python | ok |
| Dependency License Checker | powershell | fable5-1m-medium | 11.2min | 20 | 2 | $3.23 | 4.5 | powershell | ok |
| Semantic Version Bumper | typescript-bun | fable5-1m-medium | 8.9min | 36 | 0 | $3.39 | 5.0 | typescript | ok |
| Environment Matrix Generator | bash | fable5-1m-medium | 7.5min | 37 | 1 | $3.41 | 4.5 | bash | ok |
| PR Label Assigner | powershell | fable5-1m-medium | 12.0min | 32 | 1 | $3.41 | 4.5 | powershell | ok |
| Test Results Aggregator | bash | fable5-1m-medium | 7.8min | 34 | 3 | $3.46 | 4.0 | bash | ok |
| Artifact Cleanup Script | bash | fable5-1m-medium | 7.7min | 31 | 5 | $3.53 | 3.5 | bash | ok |
| PR Label Assigner | default | fable5-1m-high | 9.0min | 41 | 1 | $3.87 | 4.5 | python | ok |
| Secret Rotation Validator | bash | fable5-1m-medium | 9.4min | 37 | 0 | $3.92 | 4.0 | bash | ok |
| Semantic Version Bumper | bash | fable5-1m-medium | 8.4min | 39 | 1 | $3.99 | 4.5 | bash | ok |
| PR Label Assigner | bash | fable5-1m-medium | 8.6min | 46 | 2 | $4.15 | 4.5 | bash | ok |
| Test Results Aggregator | default | fable5-1m-high | 8.4min | 39 | 0 | $4.18 | 4.0 | python | ok |
| Semantic Version Bumper | default | fable5-1m-medium | 9.1min | 35 | 2 | $4.21 | 1.0 | javascript | ok |
| Dependency License Checker | typescript-bun | fable5-1m-medium | 9.2min | 46 | 0 | $4.24 | 4.0 | typescript | ok |
| Environment Matrix Generator | powershell | fable5-1m-medium | 12.6min | 34 | 6 | $4.34 | 4.5 | powershell | ok |
| PR Label Assigner | typescript-bun | fable5-1m-medium | 11.9min | 46 | 0 | $4.46 | 4.5 | typescript | ok |
| Dependency License Checker | typescript-bun | fable5-1m-high | 11.7min | 46 | 0 | $4.49 | 4.5 | typescript | ok |
| Dependency License Checker | default | fable5-1m-high | 9.6min | 46 | 1 | $4.49 | 2.0 | javascript | ok |
| Environment Matrix Generator | default | fable5-1m-medium | 10.6min | 47 | 2 | $4.57 | 4.0 | python | ok |
| Dependency License Checker | bash | fable5-1m-high | 9.9min | 46 | 0 | $4.58 | 4.0 | bash | ok |
| PR Label Assigner | typescript-bun | fable5-1m-high | 9.8min | 47 | 0 | $4.64 | 4.5 | typescript | ok |
| Semantic Version Bumper | powershell | fable5-1m-medium | 19.0min | 36 | 4 | $4.65 | 4.5 | powershell | ok |
| Secret Rotation Validator | typescript-bun | fable5-1m-medium | 12.7min | 42 | 0 | $4.84 | 4.5 | typescript | ok |
| PR Label Assigner | bash | fable5-1m-high | 11.7min | 46 | 2 | $4.85 | 4.0 | bash | ok |
| Test Results Aggregator | typescript-bun | fable5-1m-medium | 10.7min | 46 | 0 | $4.98 | 4.5 | typescript | ok |
| Environment Matrix Generator | typescript-bun | fable5-1m-medium | 7.9min | 36 | 3 | $5.00 | 4.5 | typescript | ok |
| Test Results Aggregator | powershell | fable5-1m-high | 15.0min | 46 | 6 | $5.05 | 4.0 | powershell | ok |
| Test Results Aggregator | powershell | fable5-1m-medium | 15.2min | 40 | 5 | $5.09 | 4.5 | powershell | ok |
| Secret Rotation Validator | bash | fable5-1m-high | 12.5min | 48 | 3 | $5.19 | 4.5 | bash | ok |
| Artifact Cleanup Script | default | fable5-1m-medium | 12.1min | 52 | 0 | $5.22 | 4.0 | python | ok |
| Test Results Aggregator | default | fable5-1m-medium | 9.8min | 47 | 1 | $5.30 | 5.0 | python | ok |
| Secret Rotation Validator | powershell | fable5-1m-medium | 18.0min | 30 | 5 | $5.33 | 4.5 | powershell | ok |
| Semantic Version Bumper | bash | fable5-1m-high | 12.0min | 55 | 1 | $5.33 | 4.5 | bash | ok |
| PR Label Assigner | powershell | fable5-1m-high | 12.5min | 43 | 1 | $5.49 | 4.5 | powershell | ok |
| Artifact Cleanup Script | bash | fable5-1m-high | 11.8min | 49 | 0 | $5.55 | 4.5 | bash | ok |
| Dependency License Checker | powershell | fable5-1m-high | 16.8min | 41 | 6 | $5.67 | 4.5 | powershell | ok |
| Artifact Cleanup Script | typescript-bun | fable5-1m-medium | 14.5min | 51 | 0 | $5.68 | 4.0 | typescript | ok |
| Secret Rotation Validator | powershell | fable5-1m-high | 17.4min | 37 | 6 | $5.79 | 4.5 | powershell | ok |
| Semantic Version Bumper | powershell | fable5-1m-high | 19.3min | 47 | 2 | $5.82 | 4.0 | powershell | ok |
| Test Results Aggregator | typescript-bun | fable5-1m-high | 11.7min | 55 | 2 | $5.91 | 3.5 | typescript | ok |
| Secret Rotation Validator | typescript-bun | fable5-1m-high | 11.5min | 51 | 1 | $5.95 | 4.5 | typescript | ok |
| Semantic Version Bumper | typescript-bun | fable5-1m-high | 11.2min | 48 | 1 | $6.25 | 4.5 | typescript | ok |
| Test Results Aggregator | bash | fable5-1m-high | 13.7min | 52 | 2 | $6.27 | 4.5 | bash | ok |
| Environment Matrix Generator | typescript-bun | fable5-1m-high | 15.1min | 55 | 4 | $6.33 | 4.0 | typescript | ok |
| Artifact Cleanup Script | powershell | fable5-1m-high | 17.6min | 46 | 0 | $6.49 | 4.5 | powershell | ok |
| Semantic Version Bumper | default | fable5-1m-high | 12.9min | 52 | 1 | $6.53 | 1.5 | javascript | ok |
| Environment Matrix Generator | bash | fable5-1m-high | 11.2min | 45 | 1 | $6.86 | 4.0 | bash | ok |
| Artifact Cleanup Script | powershell | fable5-1m-medium | 17.1min | 46 | 1 | $6.86 | 4.5 | powershell | ok |
| Environment Matrix Generator | default | fable5-1m-high | 13.5min | 65 | 1 | $6.97 | 2.0 | python | ok |
| Secret Rotation Validator | default | fable5-1m-high | 12.3min | 58 | 1 | $7.27 | 4.0 | python | ok |
| Environment Matrix Generator | powershell | fable5-1m-high | 21.5min | 45 | 8 | $7.73 | 4.5 | powershell | ok |
| Artifact Cleanup Script | default | fable5-1m-high | 15.1min | 71 | 0 | $8.50 | 4.5 | python | ok |
| Artifact Cleanup Script | typescript-bun | fable5-1m-high | 15.2min | 62 | 1 | $9.45 | 4.5 | typescript | ok |

</details>

<details>
<summary>Sorted by duration (fastest first)</summary>

| Task | Language | Model | Duration | Turns | Errors | Cost | Tests Quality | Chosen | Status |
|------|----------|-------|----------|-------|--------|------|-----------|--------|--------|
| Dependency License Checker | bash | fable5-1m-medium | 6.3min | 36 | 1 | $2.95 | 4.0 | bash | ok |
| PR Label Assigner | default | fable5-1m-medium | 6.8min | 35 | 1 | $3.04 | 2.0 | python | ok |
| Dependency License Checker | default | fable5-1m-medium | 6.8min | 29 | 2 | $2.90 | 4.5 | python | ok |
| Secret Rotation Validator | default | fable5-1m-medium | 7.3min | 32 | 0 | $3.13 | 2.0 | python | ok |
| Environment Matrix Generator | bash | fable5-1m-medium | 7.5min | 37 | 1 | $3.41 | 4.5 | bash | ok |
| Artifact Cleanup Script | bash | fable5-1m-medium | 7.7min | 31 | 5 | $3.53 | 3.5 | bash | ok |
| Test Results Aggregator | bash | fable5-1m-medium | 7.8min | 34 | 3 | $3.46 | 4.0 | bash | ok |
| Environment Matrix Generator | typescript-bun | fable5-1m-medium | 7.9min | 36 | 3 | $5.00 | 4.5 | typescript | ok |
| Test Results Aggregator | default | fable5-1m-high | 8.4min | 39 | 0 | $4.18 | 4.0 | python | ok |
| Semantic Version Bumper | bash | fable5-1m-medium | 8.4min | 39 | 1 | $3.99 | 4.5 | bash | ok |
| PR Label Assigner | bash | fable5-1m-medium | 8.6min | 46 | 2 | $4.15 | 4.5 | bash | ok |
| Semantic Version Bumper | typescript-bun | fable5-1m-medium | 8.9min | 36 | 0 | $3.39 | 5.0 | typescript | ok |
| PR Label Assigner | default | fable5-1m-high | 9.0min | 41 | 1 | $3.87 | 4.5 | python | ok |
| Semantic Version Bumper | default | fable5-1m-medium | 9.1min | 35 | 2 | $4.21 | 1.0 | javascript | ok |
| Dependency License Checker | typescript-bun | fable5-1m-medium | 9.2min | 46 | 0 | $4.24 | 4.0 | typescript | ok |
| Secret Rotation Validator | bash | fable5-1m-medium | 9.4min | 37 | 0 | $3.92 | 4.0 | bash | ok |
| Dependency License Checker | default | fable5-1m-high | 9.6min | 46 | 1 | $4.49 | 2.0 | javascript | ok |
| Test Results Aggregator | default | fable5-1m-medium | 9.8min | 47 | 1 | $5.30 | 5.0 | python | ok |
| PR Label Assigner | typescript-bun | fable5-1m-high | 9.8min | 47 | 0 | $4.64 | 4.5 | typescript | ok |
| Dependency License Checker | bash | fable5-1m-high | 9.9min | 46 | 0 | $4.58 | 4.0 | bash | ok |
| Environment Matrix Generator | default | fable5-1m-medium | 10.6min | 47 | 2 | $4.57 | 4.0 | python | ok |
| Test Results Aggregator | typescript-bun | fable5-1m-medium | 10.7min | 46 | 0 | $4.98 | 4.5 | typescript | ok |
| Environment Matrix Generator | bash | fable5-1m-high | 11.2min | 45 | 1 | $6.86 | 4.0 | bash | ok |
| Dependency License Checker | powershell | fable5-1m-medium | 11.2min | 20 | 2 | $3.23 | 4.5 | powershell | ok |
| Semantic Version Bumper | typescript-bun | fable5-1m-high | 11.2min | 48 | 1 | $6.25 | 4.5 | typescript | ok |
| Secret Rotation Validator | typescript-bun | fable5-1m-high | 11.5min | 51 | 1 | $5.95 | 4.5 | typescript | ok |
| Test Results Aggregator | typescript-bun | fable5-1m-high | 11.7min | 55 | 2 | $5.91 | 3.5 | typescript | ok |
| Dependency License Checker | typescript-bun | fable5-1m-high | 11.7min | 46 | 0 | $4.49 | 4.5 | typescript | ok |
| PR Label Assigner | bash | fable5-1m-high | 11.7min | 46 | 2 | $4.85 | 4.0 | bash | ok |
| Artifact Cleanup Script | bash | fable5-1m-high | 11.8min | 49 | 0 | $5.55 | 4.5 | bash | ok |
| PR Label Assigner | typescript-bun | fable5-1m-medium | 11.9min | 46 | 0 | $4.46 | 4.5 | typescript | ok |
| Semantic Version Bumper | bash | fable5-1m-high | 12.0min | 55 | 1 | $5.33 | 4.5 | bash | ok |
| PR Label Assigner | powershell | fable5-1m-medium | 12.0min | 32 | 1 | $3.41 | 4.5 | powershell | ok |
| Artifact Cleanup Script | default | fable5-1m-medium | 12.1min | 52 | 0 | $5.22 | 4.0 | python | ok |
| Secret Rotation Validator | default | fable5-1m-high | 12.3min | 58 | 1 | $7.27 | 4.0 | python | ok |
| Secret Rotation Validator | bash | fable5-1m-high | 12.5min | 48 | 3 | $5.19 | 4.5 | bash | ok |
| PR Label Assigner | powershell | fable5-1m-high | 12.5min | 43 | 1 | $5.49 | 4.5 | powershell | ok |
| Environment Matrix Generator | powershell | fable5-1m-medium | 12.6min | 34 | 6 | $4.34 | 4.5 | powershell | ok |
| Secret Rotation Validator | typescript-bun | fable5-1m-medium | 12.7min | 42 | 0 | $4.84 | 4.5 | typescript | ok |
| Semantic Version Bumper | default | fable5-1m-high | 12.9min | 52 | 1 | $6.53 | 1.5 | javascript | ok |
| Environment Matrix Generator | default | fable5-1m-high | 13.5min | 65 | 1 | $6.97 | 2.0 | python | ok |
| Test Results Aggregator | bash | fable5-1m-high | 13.7min | 52 | 2 | $6.27 | 4.5 | bash | ok |
| Artifact Cleanup Script | typescript-bun | fable5-1m-medium | 14.5min | 51 | 0 | $5.68 | 4.0 | typescript | ok |
| Test Results Aggregator | powershell | fable5-1m-high | 15.0min | 46 | 6 | $5.05 | 4.0 | powershell | ok |
| Environment Matrix Generator | typescript-bun | fable5-1m-high | 15.1min | 55 | 4 | $6.33 | 4.0 | typescript | ok |
| Artifact Cleanup Script | default | fable5-1m-high | 15.1min | 71 | 0 | $8.50 | 4.5 | python | ok |
| Artifact Cleanup Script | typescript-bun | fable5-1m-high | 15.2min | 62 | 1 | $9.45 | 4.5 | typescript | ok |
| Test Results Aggregator | powershell | fable5-1m-medium | 15.2min | 40 | 5 | $5.09 | 4.5 | powershell | ok |
| Dependency License Checker | powershell | fable5-1m-high | 16.8min | 41 | 6 | $5.67 | 4.5 | powershell | ok |
| Artifact Cleanup Script | powershell | fable5-1m-medium | 17.1min | 46 | 1 | $6.86 | 4.5 | powershell | ok |
| Secret Rotation Validator | powershell | fable5-1m-high | 17.4min | 37 | 6 | $5.79 | 4.5 | powershell | ok |
| Artifact Cleanup Script | powershell | fable5-1m-high | 17.6min | 46 | 0 | $6.49 | 4.5 | powershell | ok |
| Secret Rotation Validator | powershell | fable5-1m-medium | 18.0min | 30 | 5 | $5.33 | 4.5 | powershell | ok |
| Semantic Version Bumper | powershell | fable5-1m-medium | 19.0min | 36 | 4 | $4.65 | 4.5 | powershell | ok |
| Semantic Version Bumper | powershell | fable5-1m-high | 19.3min | 47 | 2 | $5.82 | 4.0 | powershell | ok |
| Environment Matrix Generator | powershell | fable5-1m-high | 21.5min | 45 | 8 | $7.73 | 4.5 | powershell | ok |

</details>

<details>
<summary>Sorted by errors (fewest first)</summary>

| Task | Language | Model | Duration | Turns | Errors | Cost | Tests Quality | Chosen | Status |
|------|----------|-------|----------|-------|--------|------|-----------|--------|--------|
| Semantic Version Bumper | typescript-bun | fable5-1m-medium | 8.9min | 36 | 0 | $3.39 | 5.0 | typescript | ok |
| PR Label Assigner | typescript-bun | fable5-1m-high | 9.8min | 47 | 0 | $4.64 | 4.5 | typescript | ok |
| PR Label Assigner | typescript-bun | fable5-1m-medium | 11.9min | 46 | 0 | $4.46 | 4.5 | typescript | ok |
| Dependency License Checker | bash | fable5-1m-high | 9.9min | 46 | 0 | $4.58 | 4.0 | bash | ok |
| Dependency License Checker | typescript-bun | fable5-1m-high | 11.7min | 46 | 0 | $4.49 | 4.5 | typescript | ok |
| Dependency License Checker | typescript-bun | fable5-1m-medium | 9.2min | 46 | 0 | $4.24 | 4.0 | typescript | ok |
| Test Results Aggregator | default | fable5-1m-high | 8.4min | 39 | 0 | $4.18 | 4.0 | python | ok |
| Test Results Aggregator | typescript-bun | fable5-1m-medium | 10.7min | 46 | 0 | $4.98 | 4.5 | typescript | ok |
| Artifact Cleanup Script | bash | fable5-1m-high | 11.8min | 49 | 0 | $5.55 | 4.5 | bash | ok |
| Artifact Cleanup Script | default | fable5-1m-high | 15.1min | 71 | 0 | $8.50 | 4.5 | python | ok |
| Artifact Cleanup Script | default | fable5-1m-medium | 12.1min | 52 | 0 | $5.22 | 4.0 | python | ok |
| Artifact Cleanup Script | powershell | fable5-1m-high | 17.6min | 46 | 0 | $6.49 | 4.5 | powershell | ok |
| Artifact Cleanup Script | typescript-bun | fable5-1m-medium | 14.5min | 51 | 0 | $5.68 | 4.0 | typescript | ok |
| Secret Rotation Validator | bash | fable5-1m-medium | 9.4min | 37 | 0 | $3.92 | 4.0 | bash | ok |
| Secret Rotation Validator | default | fable5-1m-medium | 7.3min | 32 | 0 | $3.13 | 2.0 | python | ok |
| Secret Rotation Validator | typescript-bun | fable5-1m-medium | 12.7min | 42 | 0 | $4.84 | 4.5 | typescript | ok |
| Semantic Version Bumper | bash | fable5-1m-high | 12.0min | 55 | 1 | $5.33 | 4.5 | bash | ok |
| Semantic Version Bumper | bash | fable5-1m-medium | 8.4min | 39 | 1 | $3.99 | 4.5 | bash | ok |
| Semantic Version Bumper | default | fable5-1m-high | 12.9min | 52 | 1 | $6.53 | 1.5 | javascript | ok |
| Semantic Version Bumper | typescript-bun | fable5-1m-high | 11.2min | 48 | 1 | $6.25 | 4.5 | typescript | ok |
| PR Label Assigner | default | fable5-1m-high | 9.0min | 41 | 1 | $3.87 | 4.5 | python | ok |
| PR Label Assigner | default | fable5-1m-medium | 6.8min | 35 | 1 | $3.04 | 2.0 | python | ok |
| PR Label Assigner | powershell | fable5-1m-high | 12.5min | 43 | 1 | $5.49 | 4.5 | powershell | ok |
| PR Label Assigner | powershell | fable5-1m-medium | 12.0min | 32 | 1 | $3.41 | 4.5 | powershell | ok |
| Dependency License Checker | bash | fable5-1m-medium | 6.3min | 36 | 1 | $2.95 | 4.0 | bash | ok |
| Dependency License Checker | default | fable5-1m-high | 9.6min | 46 | 1 | $4.49 | 2.0 | javascript | ok |
| Test Results Aggregator | default | fable5-1m-medium | 9.8min | 47 | 1 | $5.30 | 5.0 | python | ok |
| Environment Matrix Generator | bash | fable5-1m-high | 11.2min | 45 | 1 | $6.86 | 4.0 | bash | ok |
| Environment Matrix Generator | bash | fable5-1m-medium | 7.5min | 37 | 1 | $3.41 | 4.5 | bash | ok |
| Environment Matrix Generator | default | fable5-1m-high | 13.5min | 65 | 1 | $6.97 | 2.0 | python | ok |
| Artifact Cleanup Script | powershell | fable5-1m-medium | 17.1min | 46 | 1 | $6.86 | 4.5 | powershell | ok |
| Artifact Cleanup Script | typescript-bun | fable5-1m-high | 15.2min | 62 | 1 | $9.45 | 4.5 | typescript | ok |
| Secret Rotation Validator | default | fable5-1m-high | 12.3min | 58 | 1 | $7.27 | 4.0 | python | ok |
| Secret Rotation Validator | typescript-bun | fable5-1m-high | 11.5min | 51 | 1 | $5.95 | 4.5 | typescript | ok |
| Semantic Version Bumper | default | fable5-1m-medium | 9.1min | 35 | 2 | $4.21 | 1.0 | javascript | ok |
| Semantic Version Bumper | powershell | fable5-1m-high | 19.3min | 47 | 2 | $5.82 | 4.0 | powershell | ok |
| PR Label Assigner | bash | fable5-1m-high | 11.7min | 46 | 2 | $4.85 | 4.0 | bash | ok |
| PR Label Assigner | bash | fable5-1m-medium | 8.6min | 46 | 2 | $4.15 | 4.5 | bash | ok |
| Dependency License Checker | default | fable5-1m-medium | 6.8min | 29 | 2 | $2.90 | 4.5 | python | ok |
| Dependency License Checker | powershell | fable5-1m-medium | 11.2min | 20 | 2 | $3.23 | 4.5 | powershell | ok |
| Test Results Aggregator | bash | fable5-1m-high | 13.7min | 52 | 2 | $6.27 | 4.5 | bash | ok |
| Test Results Aggregator | typescript-bun | fable5-1m-high | 11.7min | 55 | 2 | $5.91 | 3.5 | typescript | ok |
| Environment Matrix Generator | default | fable5-1m-medium | 10.6min | 47 | 2 | $4.57 | 4.0 | python | ok |
| Test Results Aggregator | bash | fable5-1m-medium | 7.8min | 34 | 3 | $3.46 | 4.0 | bash | ok |
| Environment Matrix Generator | typescript-bun | fable5-1m-medium | 7.9min | 36 | 3 | $5.00 | 4.5 | typescript | ok |
| Secret Rotation Validator | bash | fable5-1m-high | 12.5min | 48 | 3 | $5.19 | 4.5 | bash | ok |
| Semantic Version Bumper | powershell | fable5-1m-medium | 19.0min | 36 | 4 | $4.65 | 4.5 | powershell | ok |
| Environment Matrix Generator | typescript-bun | fable5-1m-high | 15.1min | 55 | 4 | $6.33 | 4.0 | typescript | ok |
| Test Results Aggregator | powershell | fable5-1m-medium | 15.2min | 40 | 5 | $5.09 | 4.5 | powershell | ok |
| Artifact Cleanup Script | bash | fable5-1m-medium | 7.7min | 31 | 5 | $3.53 | 3.5 | bash | ok |
| Secret Rotation Validator | powershell | fable5-1m-medium | 18.0min | 30 | 5 | $5.33 | 4.5 | powershell | ok |
| Dependency License Checker | powershell | fable5-1m-high | 16.8min | 41 | 6 | $5.67 | 4.5 | powershell | ok |
| Test Results Aggregator | powershell | fable5-1m-high | 15.0min | 46 | 6 | $5.05 | 4.0 | powershell | ok |
| Environment Matrix Generator | powershell | fable5-1m-medium | 12.6min | 34 | 6 | $4.34 | 4.5 | powershell | ok |
| Secret Rotation Validator | powershell | fable5-1m-high | 17.4min | 37 | 6 | $5.79 | 4.5 | powershell | ok |
| Environment Matrix Generator | powershell | fable5-1m-high | 21.5min | 45 | 8 | $7.73 | 4.5 | powershell | ok |

</details>

<details>
<summary>Sorted by turns (fewest first)</summary>

| Task | Language | Model | Duration | Turns | Errors | Cost | Tests Quality | Chosen | Status |
|------|----------|-------|----------|-------|--------|------|-----------|--------|--------|
| Dependency License Checker | powershell | fable5-1m-medium | 11.2min | 20 | 2 | $3.23 | 4.5 | powershell | ok |
| Dependency License Checker | default | fable5-1m-medium | 6.8min | 29 | 2 | $2.90 | 4.5 | python | ok |
| Secret Rotation Validator | powershell | fable5-1m-medium | 18.0min | 30 | 5 | $5.33 | 4.5 | powershell | ok |
| Artifact Cleanup Script | bash | fable5-1m-medium | 7.7min | 31 | 5 | $3.53 | 3.5 | bash | ok |
| PR Label Assigner | powershell | fable5-1m-medium | 12.0min | 32 | 1 | $3.41 | 4.5 | powershell | ok |
| Secret Rotation Validator | default | fable5-1m-medium | 7.3min | 32 | 0 | $3.13 | 2.0 | python | ok |
| Test Results Aggregator | bash | fable5-1m-medium | 7.8min | 34 | 3 | $3.46 | 4.0 | bash | ok |
| Environment Matrix Generator | powershell | fable5-1m-medium | 12.6min | 34 | 6 | $4.34 | 4.5 | powershell | ok |
| Semantic Version Bumper | default | fable5-1m-medium | 9.1min | 35 | 2 | $4.21 | 1.0 | javascript | ok |
| PR Label Assigner | default | fable5-1m-medium | 6.8min | 35 | 1 | $3.04 | 2.0 | python | ok |
| Semantic Version Bumper | powershell | fable5-1m-medium | 19.0min | 36 | 4 | $4.65 | 4.5 | powershell | ok |
| Semantic Version Bumper | typescript-bun | fable5-1m-medium | 8.9min | 36 | 0 | $3.39 | 5.0 | typescript | ok |
| Dependency License Checker | bash | fable5-1m-medium | 6.3min | 36 | 1 | $2.95 | 4.0 | bash | ok |
| Environment Matrix Generator | typescript-bun | fable5-1m-medium | 7.9min | 36 | 3 | $5.00 | 4.5 | typescript | ok |
| Environment Matrix Generator | bash | fable5-1m-medium | 7.5min | 37 | 1 | $3.41 | 4.5 | bash | ok |
| Secret Rotation Validator | bash | fable5-1m-medium | 9.4min | 37 | 0 | $3.92 | 4.0 | bash | ok |
| Secret Rotation Validator | powershell | fable5-1m-high | 17.4min | 37 | 6 | $5.79 | 4.5 | powershell | ok |
| Semantic Version Bumper | bash | fable5-1m-medium | 8.4min | 39 | 1 | $3.99 | 4.5 | bash | ok |
| Test Results Aggregator | default | fable5-1m-high | 8.4min | 39 | 0 | $4.18 | 4.0 | python | ok |
| Test Results Aggregator | powershell | fable5-1m-medium | 15.2min | 40 | 5 | $5.09 | 4.5 | powershell | ok |
| PR Label Assigner | default | fable5-1m-high | 9.0min | 41 | 1 | $3.87 | 4.5 | python | ok |
| Dependency License Checker | powershell | fable5-1m-high | 16.8min | 41 | 6 | $5.67 | 4.5 | powershell | ok |
| Secret Rotation Validator | typescript-bun | fable5-1m-medium | 12.7min | 42 | 0 | $4.84 | 4.5 | typescript | ok |
| PR Label Assigner | powershell | fable5-1m-high | 12.5min | 43 | 1 | $5.49 | 4.5 | powershell | ok |
| Environment Matrix Generator | bash | fable5-1m-high | 11.2min | 45 | 1 | $6.86 | 4.0 | bash | ok |
| Environment Matrix Generator | powershell | fable5-1m-high | 21.5min | 45 | 8 | $7.73 | 4.5 | powershell | ok |
| PR Label Assigner | bash | fable5-1m-high | 11.7min | 46 | 2 | $4.85 | 4.0 | bash | ok |
| PR Label Assigner | bash | fable5-1m-medium | 8.6min | 46 | 2 | $4.15 | 4.5 | bash | ok |
| PR Label Assigner | typescript-bun | fable5-1m-medium | 11.9min | 46 | 0 | $4.46 | 4.5 | typescript | ok |
| Dependency License Checker | bash | fable5-1m-high | 9.9min | 46 | 0 | $4.58 | 4.0 | bash | ok |
| Dependency License Checker | default | fable5-1m-high | 9.6min | 46 | 1 | $4.49 | 2.0 | javascript | ok |
| Dependency License Checker | typescript-bun | fable5-1m-high | 11.7min | 46 | 0 | $4.49 | 4.5 | typescript | ok |
| Dependency License Checker | typescript-bun | fable5-1m-medium | 9.2min | 46 | 0 | $4.24 | 4.0 | typescript | ok |
| Test Results Aggregator | powershell | fable5-1m-high | 15.0min | 46 | 6 | $5.05 | 4.0 | powershell | ok |
| Test Results Aggregator | typescript-bun | fable5-1m-medium | 10.7min | 46 | 0 | $4.98 | 4.5 | typescript | ok |
| Artifact Cleanup Script | powershell | fable5-1m-high | 17.6min | 46 | 0 | $6.49 | 4.5 | powershell | ok |
| Artifact Cleanup Script | powershell | fable5-1m-medium | 17.1min | 46 | 1 | $6.86 | 4.5 | powershell | ok |
| Semantic Version Bumper | powershell | fable5-1m-high | 19.3min | 47 | 2 | $5.82 | 4.0 | powershell | ok |
| PR Label Assigner | typescript-bun | fable5-1m-high | 9.8min | 47 | 0 | $4.64 | 4.5 | typescript | ok |
| Test Results Aggregator | default | fable5-1m-medium | 9.8min | 47 | 1 | $5.30 | 5.0 | python | ok |
| Environment Matrix Generator | default | fable5-1m-medium | 10.6min | 47 | 2 | $4.57 | 4.0 | python | ok |
| Semantic Version Bumper | typescript-bun | fable5-1m-high | 11.2min | 48 | 1 | $6.25 | 4.5 | typescript | ok |
| Secret Rotation Validator | bash | fable5-1m-high | 12.5min | 48 | 3 | $5.19 | 4.5 | bash | ok |
| Artifact Cleanup Script | bash | fable5-1m-high | 11.8min | 49 | 0 | $5.55 | 4.5 | bash | ok |
| Artifact Cleanup Script | typescript-bun | fable5-1m-medium | 14.5min | 51 | 0 | $5.68 | 4.0 | typescript | ok |
| Secret Rotation Validator | typescript-bun | fable5-1m-high | 11.5min | 51 | 1 | $5.95 | 4.5 | typescript | ok |
| Semantic Version Bumper | default | fable5-1m-high | 12.9min | 52 | 1 | $6.53 | 1.5 | javascript | ok |
| Test Results Aggregator | bash | fable5-1m-high | 13.7min | 52 | 2 | $6.27 | 4.5 | bash | ok |
| Artifact Cleanup Script | default | fable5-1m-medium | 12.1min | 52 | 0 | $5.22 | 4.0 | python | ok |
| Semantic Version Bumper | bash | fable5-1m-high | 12.0min | 55 | 1 | $5.33 | 4.5 | bash | ok |
| Test Results Aggregator | typescript-bun | fable5-1m-high | 11.7min | 55 | 2 | $5.91 | 3.5 | typescript | ok |
| Environment Matrix Generator | typescript-bun | fable5-1m-high | 15.1min | 55 | 4 | $6.33 | 4.0 | typescript | ok |
| Secret Rotation Validator | default | fable5-1m-high | 12.3min | 58 | 1 | $7.27 | 4.0 | python | ok |
| Artifact Cleanup Script | typescript-bun | fable5-1m-high | 15.2min | 62 | 1 | $9.45 | 4.5 | typescript | ok |
| Environment Matrix Generator | default | fable5-1m-high | 13.5min | 65 | 1 | $6.97 | 2.0 | python | ok |
| Artifact Cleanup Script | default | fable5-1m-high | 15.1min | 71 | 0 | $8.50 | 4.5 | python | ok |

</details>

<details>
<summary>Sorted by LLM-as-judge score (best first)</summary>

| Task | Language | Model | Duration | Turns | Errors | Cost | Tests Quality | Chosen | Status |
|------|----------|-------|----------|-------|--------|------|-----------|--------|--------|
| Semantic Version Bumper | typescript-bun | fable5-1m-medium | 8.9min | 36 | 0 | $3.39 | 5.0 | typescript | ok |
| Test Results Aggregator | default | fable5-1m-medium | 9.8min | 47 | 1 | $5.30 | 5.0 | python | ok |
| Semantic Version Bumper | bash | fable5-1m-high | 12.0min | 55 | 1 | $5.33 | 4.5 | bash | ok |
| Semantic Version Bumper | bash | fable5-1m-medium | 8.4min | 39 | 1 | $3.99 | 4.5 | bash | ok |
| Semantic Version Bumper | powershell | fable5-1m-medium | 19.0min | 36 | 4 | $4.65 | 4.5 | powershell | ok |
| Semantic Version Bumper | typescript-bun | fable5-1m-high | 11.2min | 48 | 1 | $6.25 | 4.5 | typescript | ok |
| PR Label Assigner | bash | fable5-1m-medium | 8.6min | 46 | 2 | $4.15 | 4.5 | bash | ok |
| PR Label Assigner | default | fable5-1m-high | 9.0min | 41 | 1 | $3.87 | 4.5 | python | ok |
| PR Label Assigner | powershell | fable5-1m-high | 12.5min | 43 | 1 | $5.49 | 4.5 | powershell | ok |
| PR Label Assigner | powershell | fable5-1m-medium | 12.0min | 32 | 1 | $3.41 | 4.5 | powershell | ok |
| PR Label Assigner | typescript-bun | fable5-1m-high | 9.8min | 47 | 0 | $4.64 | 4.5 | typescript | ok |
| PR Label Assigner | typescript-bun | fable5-1m-medium | 11.9min | 46 | 0 | $4.46 | 4.5 | typescript | ok |
| Dependency License Checker | default | fable5-1m-medium | 6.8min | 29 | 2 | $2.90 | 4.5 | python | ok |
| Dependency License Checker | powershell | fable5-1m-high | 16.8min | 41 | 6 | $5.67 | 4.5 | powershell | ok |
| Dependency License Checker | powershell | fable5-1m-medium | 11.2min | 20 | 2 | $3.23 | 4.5 | powershell | ok |
| Dependency License Checker | typescript-bun | fable5-1m-high | 11.7min | 46 | 0 | $4.49 | 4.5 | typescript | ok |
| Test Results Aggregator | bash | fable5-1m-high | 13.7min | 52 | 2 | $6.27 | 4.5 | bash | ok |
| Test Results Aggregator | powershell | fable5-1m-medium | 15.2min | 40 | 5 | $5.09 | 4.5 | powershell | ok |
| Test Results Aggregator | typescript-bun | fable5-1m-medium | 10.7min | 46 | 0 | $4.98 | 4.5 | typescript | ok |
| Environment Matrix Generator | bash | fable5-1m-medium | 7.5min | 37 | 1 | $3.41 | 4.5 | bash | ok |
| Environment Matrix Generator | powershell | fable5-1m-high | 21.5min | 45 | 8 | $7.73 | 4.5 | powershell | ok |
| Environment Matrix Generator | powershell | fable5-1m-medium | 12.6min | 34 | 6 | $4.34 | 4.5 | powershell | ok |
| Environment Matrix Generator | typescript-bun | fable5-1m-medium | 7.9min | 36 | 3 | $5.00 | 4.5 | typescript | ok |
| Artifact Cleanup Script | bash | fable5-1m-high | 11.8min | 49 | 0 | $5.55 | 4.5 | bash | ok |
| Artifact Cleanup Script | default | fable5-1m-high | 15.1min | 71 | 0 | $8.50 | 4.5 | python | ok |
| Artifact Cleanup Script | powershell | fable5-1m-high | 17.6min | 46 | 0 | $6.49 | 4.5 | powershell | ok |
| Artifact Cleanup Script | powershell | fable5-1m-medium | 17.1min | 46 | 1 | $6.86 | 4.5 | powershell | ok |
| Artifact Cleanup Script | typescript-bun | fable5-1m-high | 15.2min | 62 | 1 | $9.45 | 4.5 | typescript | ok |
| Secret Rotation Validator | bash | fable5-1m-high | 12.5min | 48 | 3 | $5.19 | 4.5 | bash | ok |
| Secret Rotation Validator | powershell | fable5-1m-high | 17.4min | 37 | 6 | $5.79 | 4.5 | powershell | ok |
| Secret Rotation Validator | powershell | fable5-1m-medium | 18.0min | 30 | 5 | $5.33 | 4.5 | powershell | ok |
| Secret Rotation Validator | typescript-bun | fable5-1m-high | 11.5min | 51 | 1 | $5.95 | 4.5 | typescript | ok |
| Secret Rotation Validator | typescript-bun | fable5-1m-medium | 12.7min | 42 | 0 | $4.84 | 4.5 | typescript | ok |
| Semantic Version Bumper | powershell | fable5-1m-high | 19.3min | 47 | 2 | $5.82 | 4.0 | powershell | ok |
| PR Label Assigner | bash | fable5-1m-high | 11.7min | 46 | 2 | $4.85 | 4.0 | bash | ok |
| Dependency License Checker | bash | fable5-1m-high | 9.9min | 46 | 0 | $4.58 | 4.0 | bash | ok |
| Dependency License Checker | bash | fable5-1m-medium | 6.3min | 36 | 1 | $2.95 | 4.0 | bash | ok |
| Dependency License Checker | typescript-bun | fable5-1m-medium | 9.2min | 46 | 0 | $4.24 | 4.0 | typescript | ok |
| Test Results Aggregator | bash | fable5-1m-medium | 7.8min | 34 | 3 | $3.46 | 4.0 | bash | ok |
| Test Results Aggregator | default | fable5-1m-high | 8.4min | 39 | 0 | $4.18 | 4.0 | python | ok |
| Test Results Aggregator | powershell | fable5-1m-high | 15.0min | 46 | 6 | $5.05 | 4.0 | powershell | ok |
| Environment Matrix Generator | bash | fable5-1m-high | 11.2min | 45 | 1 | $6.86 | 4.0 | bash | ok |
| Environment Matrix Generator | default | fable5-1m-medium | 10.6min | 47 | 2 | $4.57 | 4.0 | python | ok |
| Environment Matrix Generator | typescript-bun | fable5-1m-high | 15.1min | 55 | 4 | $6.33 | 4.0 | typescript | ok |
| Artifact Cleanup Script | default | fable5-1m-medium | 12.1min | 52 | 0 | $5.22 | 4.0 | python | ok |
| Artifact Cleanup Script | typescript-bun | fable5-1m-medium | 14.5min | 51 | 0 | $5.68 | 4.0 | typescript | ok |
| Secret Rotation Validator | bash | fable5-1m-medium | 9.4min | 37 | 0 | $3.92 | 4.0 | bash | ok |
| Secret Rotation Validator | default | fable5-1m-high | 12.3min | 58 | 1 | $7.27 | 4.0 | python | ok |
| Test Results Aggregator | typescript-bun | fable5-1m-high | 11.7min | 55 | 2 | $5.91 | 3.5 | typescript | ok |
| Artifact Cleanup Script | bash | fable5-1m-medium | 7.7min | 31 | 5 | $3.53 | 3.5 | bash | ok |
| PR Label Assigner | default | fable5-1m-medium | 6.8min | 35 | 1 | $3.04 | 2.0 | python | ok |
| Dependency License Checker | default | fable5-1m-high | 9.6min | 46 | 1 | $4.49 | 2.0 | javascript | ok |
| Environment Matrix Generator | default | fable5-1m-high | 13.5min | 65 | 1 | $6.97 | 2.0 | python | ok |
| Secret Rotation Validator | default | fable5-1m-medium | 7.3min | 32 | 0 | $3.13 | 2.0 | python | ok |
| Semantic Version Bumper | default | fable5-1m-high | 12.9min | 52 | 1 | $6.53 | 1.5 | javascript | ok |
| Semantic Version Bumper | default | fable5-1m-medium | 9.1min | 35 | 2 | $4.21 | 1.0 | javascript | ok |

</details>

## Notes

### Tiers

- **Duration bands:** **A+** ≤1.07×, **A** ≤1.14×, **A-** ≤1.21×, **B+** ≤1.29×, **B** ≤1.37×, **B-** ≤1.46×, **C+** ≤1.56×, **C** ≤1.66×, **C-** ≤1.77×, **D+** ≤1.89×, **D** ≤2.01×, **D-** ≤2.14×, **F** >2.14×
- **Cost bands:** **A+** ≤1.04×, **A** ≤1.09×, **A-** ≤1.13×, **B+** ≤1.18×, **B** ≤1.23×, **B-** ≤1.29×, **C+** ≤1.34×, **C** ≤1.40×, **C-** ≤1.46×, **D+** ≤1.52×, **D** ≤1.59×, **D-** ≤1.66×, **F** >1.66×

*Tests/Workflow Craft bands are absolute Overall score bands:* **A+** ≥4.7, **A** ≥4.4, **A-** ≥4.1, **B+** ≥3.8, **B** ≥3.5, **B-** ≥3.2, **C+** ≥2.9, **C** ≥2.6, **C-** ≥2.3, **D+** ≥2.0, **D** ≥1.7, **D-** ≥1.4, **F** <1.4, `—` = no data.*

### CLI Version Legend

| Variant label | CLI version | Tasks | Languages |
|---------------|-------------|-------|-----------|
| fable5-1m-high | 2.1.198 | All | All |
| fable5-1m-medium | 2.1.198 | All | All |

### Judge Consistency Summary

**🟡 The panel is largely doing its job, but Workflow Craft language ordering diverges enough to warrant a look:** Both judges agree default/Python is the weakest language for Tests Quality, and no reversal favors either judge's own-model family — so self-preference isn't showing up. The catch: on Workflow Craft language ordering the Spearman correlation drops to −0.60, driven by Gemini pinning bash and powershell at the 5.00 ceiling across every task while Haiku still separates them.

- 👀 **Where to look closer:** Sample the widest disagreements on Workflow Craft (one judge scoring 1 while the other scores 5, a 4-point gap on the 1–5 scale) — 12-pr-label-assigner / powershell / fable5-medium (Haiku 1, Gemini 5) and 15-test-results-aggregator / bash / fable5-high (Haiku 2, Gemini 5) — to decide whether Gemini's ceiling is masking real quality gaps or Haiku is being unusually stingy.
- 🤓 **Surprise finding:** Both judges rank default/Python worst on Tests Quality — the one point of full ordinal agreement sits at the bottom of the ladder, not the top.
- ℹ️ **Recommended next step:** Tighten the Workflow Craft rubric so Gemini can score bash and powershell below 5 when warranted, then rerun to see if the language correlation recovers.

#### Provenance

- **Model:** `claude-opus-4-7[1m]` at effort `xhigh` via the Claude CLI.
- **Inputs:** the [`judge-consistency-data.md`](judge-consistency-data.md) tables plus benchmark context (rubrics, task list, experiment setup).
- **Script:** [`conclusions_report.py`](../../conclusions_report.py) — regenerate with `python3 generate_results.py <run_dir>`.
- **Instruction:** [`JUDGE_CONSISTENCY_SUMMARY_SYSTEM_PROMPT`](../../judge_consistency_report.py) in that script.
- **Usage:** 5 input + 2395 output tokens, $0.2154.

*Full breakdown with per-model / per-language / per-language×model ranking tables and disagreement hotspots in [judge-consistency-data.md](judge-consistency-data.md).*

---
*Generated by generate_results.py — benchmark instructions v4*