# Benchmark Results: Language Comparison

**Last updated:** 2026-07-06 01:01:57 PM ET — 64/64 runs completed, 0 remaining; total cost $84.25; total agent time 726.1 min.
**Claude Code versions used:** [v2.1.97](claude-code-2.1.97.md) (64 runs). Each link goes to a per-version snapshot of the system prompt, default-tool descriptions, and the chronological Anthropic changelog up to that version. Regenerate with `python3 version_docs.py`.

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
| bash | sonnet46-200k-medium | B+ (9.4min) | A+ ($1.01) | B- (3.4) | — |
| default | opus46-200k-medium | A+ (6.7min) | B- ($1.22) | C+ (3.1) | — |
| typescript-bun | sonnet46-200k-medium | B- (11.0min) | B ($1.18) | B- (3.4) | — |
| default | sonnet46-200k-medium | C- (14.5min) | C- ($1.36) | A- (4.2) | — |
| typescript-bun | opus46-200k-medium | A- (8.5min) | C+ ($1.30) | C+ (3.1) | — |
| powershell | opus46-200k-medium | B+ (8.9min) | B+ ($1.14) | C (2.9) | — |
| bash | opus46-200k-medium | A- (8.2min) | C ($1.33) | C+ (3.0) | — |
| powershell | sonnet46-200k-medium | D- (19.2min) | D- ($1.56) | B- (3.4) | — |


<details>
<summary>Sorted by Duration tier (best-first), then avg of Cost/Tests/Workflow Craft tiers</summary>

| Language | Model | Duration | Cost | Tests Quality | Workflow Craft |
|----------|-------|----------|------|-----------|-------------|
| default | opus46-200k-medium | A+ (6.7min) | B- ($1.22) | C+ (3.1) | — |
| typescript-bun | opus46-200k-medium | A- (8.5min) | C+ ($1.30) | C+ (3.1) | — |
| bash | opus46-200k-medium | A- (8.2min) | C ($1.33) | C+ (3.0) | — |
| bash | sonnet46-200k-medium | B+ (9.4min) | A+ ($1.01) | B- (3.4) | — |
| powershell | opus46-200k-medium | B+ (8.9min) | B+ ($1.14) | C (2.9) | — |
| typescript-bun | sonnet46-200k-medium | B- (11.0min) | B ($1.18) | B- (3.4) | — |
| default | sonnet46-200k-medium | C- (14.5min) | C- ($1.36) | A- (4.2) | — |
| powershell | sonnet46-200k-medium | D- (19.2min) | D- ($1.56) | B- (3.4) | — |

</details>

<details>
<summary>Sorted by Cost tier (best-first), then avg of Duration/Tests/Workflow Craft tiers</summary>

| Language | Model | Duration | Cost | Tests Quality | Workflow Craft |
|----------|-------|----------|------|-----------|-------------|
| bash | sonnet46-200k-medium | B+ (9.4min) | A+ ($1.01) | B- (3.4) | — |
| powershell | opus46-200k-medium | B+ (8.9min) | B+ ($1.14) | C (2.9) | — |
| typescript-bun | sonnet46-200k-medium | B- (11.0min) | B ($1.18) | B- (3.4) | — |
| default | opus46-200k-medium | A+ (6.7min) | B- ($1.22) | C+ (3.1) | — |
| typescript-bun | opus46-200k-medium | A- (8.5min) | C+ ($1.30) | C+ (3.1) | — |
| bash | opus46-200k-medium | A- (8.2min) | C ($1.33) | C+ (3.0) | — |
| default | sonnet46-200k-medium | C- (14.5min) | C- ($1.36) | A- (4.2) | — |
| powershell | sonnet46-200k-medium | D- (19.2min) | D- ($1.56) | B- (3.4) | — |

</details>

<details>
<summary>Sorted by Tests Quality tier (best-first; no-data last), then avg of other tiers</summary>

| Language | Model | Duration | Cost | Tests Quality | Workflow Craft |
|----------|-------|----------|------|-----------|-------------|
| default | sonnet46-200k-medium | C- (14.5min) | C- ($1.36) | A- (4.2) | — |
| bash | sonnet46-200k-medium | B+ (9.4min) | A+ ($1.01) | B- (3.4) | — |
| typescript-bun | sonnet46-200k-medium | B- (11.0min) | B ($1.18) | B- (3.4) | — |
| powershell | sonnet46-200k-medium | D- (19.2min) | D- ($1.56) | B- (3.4) | — |
| default | opus46-200k-medium | A+ (6.7min) | B- ($1.22) | C+ (3.1) | — |
| typescript-bun | opus46-200k-medium | A- (8.5min) | C+ ($1.30) | C+ (3.1) | — |
| bash | opus46-200k-medium | A- (8.2min) | C ($1.33) | C+ (3.0) | — |
| powershell | opus46-200k-medium | B+ (8.9min) | B+ ($1.14) | C (2.9) | — |

</details>

<details>
<summary>Sorted by Workflow Craft tier (best-first; no-data last), then avg of other tiers</summary>

| Language | Model | Duration | Cost | Tests Quality | Workflow Craft |
|----------|-------|----------|------|-----------|-------------|
| bash | sonnet46-200k-medium | B+ (9.4min) | A+ ($1.01) | B- (3.4) | — |
| default | opus46-200k-medium | A+ (6.7min) | B- ($1.22) | C+ (3.1) | — |
| powershell | opus46-200k-medium | B+ (8.9min) | B+ ($1.14) | C (2.9) | — |
| typescript-bun | opus46-200k-medium | A- (8.5min) | C+ ($1.30) | C+ (3.1) | — |
| typescript-bun | sonnet46-200k-medium | B- (11.0min) | B ($1.18) | B- (3.4) | — |
| bash | opus46-200k-medium | A- (8.2min) | C ($1.33) | C+ (3.0) | — |
| default | sonnet46-200k-medium | C- (14.5min) | C- ($1.36) | A- (4.2) | — |
| powershell | sonnet46-200k-medium | D- (19.2min) | D- ($1.56) | B- (3.4) | — |

</details>

## Comparison by Language/Model/Effort
*See [Notes](#notes) for scoring rubric and CLI version legend.*

| Language | Model | Runs | Geo Duration | Max Duration | Geo Duration Net of Traps | Avg Errors | Geo Turns | Geo Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| bash | opus46-200k-medium | 8 | 8.2min | 14.5min | 8.2min | 1.8 | 39 | $1.33 | $10.93 | 3.0 | — |
| bash | sonnet46-200k-medium | 8 | 9.4min | 16.0min | 9.1min | 4.1 | 37 | $1.01 | $8.45 | 3.4 | — |
| default | opus46-200k-medium | 8 | 6.7min | 10.6min | 6.7min | 1.2 | 35 | $1.22 | $10.31 | 3.1 | — |
| default | sonnet46-200k-medium | 8 | 14.5min | 17.2min | 13.5min | 1.1 | 29 | $1.36 | $11.06 | 4.2 | — |
| powershell | opus46-200k-medium | 8 | 8.9min | 11.1min | 7.1min | 1.2 | 33 | $1.14 | $9.62 | 2.9 | — |
| powershell | sonnet46-200k-medium | 8 | 19.2min | 28.0min | 13.9min | 0.5 | 41 | $1.56 | $13.37 | 3.4 | — |
| typescript-bun | opus46-200k-medium | 8 | 8.5min | 13.2min | 8.4min | 1.5 | 38 | $1.30 | $10.78 | 3.1 | — |
| typescript-bun | sonnet46-200k-medium | 8 | 11.0min | 13.7min | 10.1min | 2.2 | 22 | $1.18 | $9.74 | 3.4 | — |


<details>
<summary>Sorted by cost (geomean, cheapest first)</summary>

| Language | Model | Runs | Geo Duration | Max Duration | Geo Duration Net of Traps | Avg Errors | Geo Turns | Geo Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| bash | sonnet46-200k-medium | 8 | 9.4min | 16.0min | 9.1min | 4.1 | 37 | $1.01 | $8.45 | 3.4 | — |
| powershell | opus46-200k-medium | 8 | 8.9min | 11.1min | 7.1min | 1.2 | 33 | $1.14 | $9.62 | 2.9 | — |
| typescript-bun | sonnet46-200k-medium | 8 | 11.0min | 13.7min | 10.1min | 2.2 | 22 | $1.18 | $9.74 | 3.4 | — |
| default | opus46-200k-medium | 8 | 6.7min | 10.6min | 6.7min | 1.2 | 35 | $1.22 | $10.31 | 3.1 | — |
| typescript-bun | opus46-200k-medium | 8 | 8.5min | 13.2min | 8.4min | 1.5 | 38 | $1.30 | $10.78 | 3.1 | — |
| bash | opus46-200k-medium | 8 | 8.2min | 14.5min | 8.2min | 1.8 | 39 | $1.33 | $10.93 | 3.0 | — |
| default | sonnet46-200k-medium | 8 | 14.5min | 17.2min | 13.5min | 1.1 | 29 | $1.36 | $11.06 | 4.2 | — |
| powershell | sonnet46-200k-medium | 8 | 19.2min | 28.0min | 13.9min | 0.5 | 41 | $1.56 | $13.37 | 3.4 | — |

</details>

<details>
<summary>Sorted by duration (geomean, fastest first)</summary>

| Language | Model | Runs | Geo Duration | Max Duration | Geo Duration Net of Traps | Avg Errors | Geo Turns | Geo Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| default | opus46-200k-medium | 8 | 6.7min | 10.6min | 6.7min | 1.2 | 35 | $1.22 | $10.31 | 3.1 | — |
| bash | opus46-200k-medium | 8 | 8.2min | 14.5min | 8.2min | 1.8 | 39 | $1.33 | $10.93 | 3.0 | — |
| typescript-bun | opus46-200k-medium | 8 | 8.5min | 13.2min | 8.4min | 1.5 | 38 | $1.30 | $10.78 | 3.1 | — |
| powershell | opus46-200k-medium | 8 | 8.9min | 11.1min | 7.1min | 1.2 | 33 | $1.14 | $9.62 | 2.9 | — |
| bash | sonnet46-200k-medium | 8 | 9.4min | 16.0min | 9.1min | 4.1 | 37 | $1.01 | $8.45 | 3.4 | — |
| typescript-bun | sonnet46-200k-medium | 8 | 11.0min | 13.7min | 10.1min | 2.2 | 22 | $1.18 | $9.74 | 3.4 | — |
| default | sonnet46-200k-medium | 8 | 14.5min | 17.2min | 13.5min | 1.1 | 29 | $1.36 | $11.06 | 4.2 | — |
| powershell | sonnet46-200k-medium | 8 | 19.2min | 28.0min | 13.9min | 0.5 | 41 | $1.56 | $13.37 | 3.4 | — |

</details>

<details>
<summary>Sorted by duration net of traps (geomean, fastest first)</summary>

| Language | Model | Runs | Geo Duration | Max Duration | Geo Duration Net of Traps | Avg Errors | Geo Turns | Geo Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| default | opus46-200k-medium | 8 | 6.7min | 10.6min | 6.7min | 1.2 | 35 | $1.22 | $10.31 | 3.1 | — |
| powershell | opus46-200k-medium | 8 | 8.9min | 11.1min | 7.1min | 1.2 | 33 | $1.14 | $9.62 | 2.9 | — |
| bash | opus46-200k-medium | 8 | 8.2min | 14.5min | 8.2min | 1.8 | 39 | $1.33 | $10.93 | 3.0 | — |
| typescript-bun | opus46-200k-medium | 8 | 8.5min | 13.2min | 8.4min | 1.5 | 38 | $1.30 | $10.78 | 3.1 | — |
| bash | sonnet46-200k-medium | 8 | 9.4min | 16.0min | 9.1min | 4.1 | 37 | $1.01 | $8.45 | 3.4 | — |
| typescript-bun | sonnet46-200k-medium | 8 | 11.0min | 13.7min | 10.1min | 2.2 | 22 | $1.18 | $9.74 | 3.4 | — |
| default | sonnet46-200k-medium | 8 | 14.5min | 17.2min | 13.5min | 1.1 | 29 | $1.36 | $11.06 | 4.2 | — |
| powershell | sonnet46-200k-medium | 8 | 19.2min | 28.0min | 13.9min | 0.5 | 41 | $1.56 | $13.37 | 3.4 | — |

</details>

<details>
<summary>Sorted by avg errors (fewest first)</summary>

| Language | Model | Runs | Geo Duration | Max Duration | Geo Duration Net of Traps | Avg Errors | Geo Turns | Geo Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| powershell | sonnet46-200k-medium | 8 | 19.2min | 28.0min | 13.9min | 0.5 | 41 | $1.56 | $13.37 | 3.4 | — |
| default | sonnet46-200k-medium | 8 | 14.5min | 17.2min | 13.5min | 1.1 | 29 | $1.36 | $11.06 | 4.2 | — |
| default | opus46-200k-medium | 8 | 6.7min | 10.6min | 6.7min | 1.2 | 35 | $1.22 | $10.31 | 3.1 | — |
| powershell | opus46-200k-medium | 8 | 8.9min | 11.1min | 7.1min | 1.2 | 33 | $1.14 | $9.62 | 2.9 | — |
| typescript-bun | opus46-200k-medium | 8 | 8.5min | 13.2min | 8.4min | 1.5 | 38 | $1.30 | $10.78 | 3.1 | — |
| bash | opus46-200k-medium | 8 | 8.2min | 14.5min | 8.2min | 1.8 | 39 | $1.33 | $10.93 | 3.0 | — |
| typescript-bun | sonnet46-200k-medium | 8 | 11.0min | 13.7min | 10.1min | 2.2 | 22 | $1.18 | $9.74 | 3.4 | — |
| bash | sonnet46-200k-medium | 8 | 9.4min | 16.0min | 9.1min | 4.1 | 37 | $1.01 | $8.45 | 3.4 | — |

</details>

<details>
<summary>Sorted by turns (geomean, fewest first)</summary>

| Language | Model | Runs | Geo Duration | Max Duration | Geo Duration Net of Traps | Avg Errors | Geo Turns | Geo Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| typescript-bun | sonnet46-200k-medium | 8 | 11.0min | 13.7min | 10.1min | 2.2 | 22 | $1.18 | $9.74 | 3.4 | — |
| default | sonnet46-200k-medium | 8 | 14.5min | 17.2min | 13.5min | 1.1 | 29 | $1.36 | $11.06 | 4.2 | — |
| powershell | opus46-200k-medium | 8 | 8.9min | 11.1min | 7.1min | 1.2 | 33 | $1.14 | $9.62 | 2.9 | — |
| default | opus46-200k-medium | 8 | 6.7min | 10.6min | 6.7min | 1.2 | 35 | $1.22 | $10.31 | 3.1 | — |
| bash | sonnet46-200k-medium | 8 | 9.4min | 16.0min | 9.1min | 4.1 | 37 | $1.01 | $8.45 | 3.4 | — |
| typescript-bun | opus46-200k-medium | 8 | 8.5min | 13.2min | 8.4min | 1.5 | 38 | $1.30 | $10.78 | 3.1 | — |
| bash | opus46-200k-medium | 8 | 8.2min | 14.5min | 8.2min | 1.8 | 39 | $1.33 | $10.93 | 3.0 | — |
| powershell | sonnet46-200k-medium | 8 | 19.2min | 28.0min | 13.9min | 0.5 | 41 | $1.56 | $13.37 | 3.4 | — |

</details>

<details>
<summary>Sorted by LLM-as-judge score (best first)</summary>

| Language | Model | Runs | Geo Duration | Max Duration | Geo Duration Net of Traps | Avg Errors | Geo Turns | Geo Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| default | sonnet46-200k-medium | 8 | 14.5min | 17.2min | 13.5min | 1.1 | 29 | $1.36 | $11.06 | 4.2 | — |
| bash | sonnet46-200k-medium | 8 | 9.4min | 16.0min | 9.1min | 4.1 | 37 | $1.01 | $8.45 | 3.4 | — |
| powershell | sonnet46-200k-medium | 8 | 19.2min | 28.0min | 13.9min | 0.5 | 41 | $1.56 | $13.37 | 3.4 | — |
| typescript-bun | sonnet46-200k-medium | 8 | 11.0min | 13.7min | 10.1min | 2.2 | 22 | $1.18 | $9.74 | 3.4 | — |
| default | opus46-200k-medium | 8 | 6.7min | 10.6min | 6.7min | 1.2 | 35 | $1.22 | $10.31 | 3.1 | — |
| typescript-bun | opus46-200k-medium | 8 | 8.5min | 13.2min | 8.4min | 1.5 | 38 | $1.30 | $10.78 | 3.1 | — |
| bash | opus46-200k-medium | 8 | 8.2min | 14.5min | 8.2min | 1.8 | 39 | $1.33 | $10.93 | 3.0 | — |
| powershell | opus46-200k-medium | 8 | 8.9min | 11.1min | 7.1min | 1.2 | 33 | $1.14 | $9.62 | 2.9 | — |

</details>

<details>
<summary>Sorted by deliverable-quality score (best first)</summary>

| Language | Model | Runs | Geo Duration | Max Duration | Geo Duration Net of Traps | Avg Errors | Geo Turns | Geo Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| bash | opus46-200k-medium | 8 | 8.2min | 14.5min | 8.2min | 1.8 | 39 | $1.33 | $10.93 | 3.0 | — |
| bash | sonnet46-200k-medium | 8 | 9.4min | 16.0min | 9.1min | 4.1 | 37 | $1.01 | $8.45 | 3.4 | — |
| default | opus46-200k-medium | 8 | 6.7min | 10.6min | 6.7min | 1.2 | 35 | $1.22 | $10.31 | 3.1 | — |
| default | sonnet46-200k-medium | 8 | 14.5min | 17.2min | 13.5min | 1.1 | 29 | $1.36 | $11.06 | 4.2 | — |
| powershell | opus46-200k-medium | 8 | 8.9min | 11.1min | 7.1min | 1.2 | 33 | $1.14 | $9.62 | 2.9 | — |
| powershell | sonnet46-200k-medium | 8 | 19.2min | 28.0min | 13.9min | 0.5 | 41 | $1.56 | $13.37 | 3.4 | — |
| typescript-bun | opus46-200k-medium | 8 | 8.5min | 13.2min | 8.4min | 1.5 | 38 | $1.30 | $10.78 | 3.1 | — |
| typescript-bun | sonnet46-200k-medium | 8 | 11.0min | 13.7min | 10.1min | 2.2 | 22 | $1.18 | $9.74 | 3.4 | — |

</details>

## Savings Analysis

### Trap Analysis by Language/Model/Effort/Category

| Trap | Language | Model | Fell In | Time Lost | % of Time | $ Lost | % of $ |
|------|------|-------|---------|-----------|-----------|--------|--------|
| pwsh-runtime-install-overhead | powershell | opus46-200k-medium-cli2.1.97 | 7 | 10.2min | 1.4% | $1.13 | 1.34% |
| pwsh-runtime-install-overhead | powershell | sonnet46-200k-medium-cli2.1.97 | 8 | 16.0min | 2.2% | $1.31 | 1.56% |
| act-push-debug-loops | default | sonnet46-200k-medium-cli2.1.97 | 3 | 4.7min | 0.7% | $0.50 | 0.60% |
| act-push-debug-loops | powershell | opus46-200k-medium-cli2.1.97 | 1 | 0.8min | 0.1% | $0.13 | 0.16% |
| act-push-debug-loops | powershell | sonnet46-200k-medium-cli2.1.97 | 3 | 15.7min | 2.2% | $0.93 | 1.10% |
| act-push-debug-loops | typescript-bun | sonnet46-200k-medium-cli2.1.97 | 2 | 2.8min | 0.4% | $0.29 | 0.35% |
| repeated-test-reruns | bash | sonnet46-200k-medium-cli2.1.97 | 2 | 1.7min | 0.2% | $0.19 | 0.23% |
| repeated-test-reruns | default | sonnet46-200k-medium-cli2.1.97 | 1 | 0.7min | 0.1% | $0.06 | 0.07% |
| repeated-test-reruns | powershell | opus46-200k-medium-cli2.1.97 | 1 | 0.7min | 0.1% | $0.11 | 0.13% |
| repeated-test-reruns | powershell | sonnet46-200k-medium-cli2.1.97 | 5 | 5.0min | 0.7% | $0.38 | 0.45% |
| repeated-test-reruns | typescript-bun | opus46-200k-medium-cli2.1.97 | 1 | 0.7min | 0.1% | $0.11 | 0.13% |
| repeated-test-reruns | typescript-bun | sonnet46-200k-medium-cli2.1.97 | 2 | 2.7min | 0.4% | $0.31 | 0.36% |
| docker-pwsh-install | powershell | opus46-200k-medium-cli2.1.97 | 1 | 3.0min | 0.4% | $0.42 | 0.50% |
| docker-pwsh-install | powershell | sonnet46-200k-medium-cli2.1.97 | 2 | 4.5min | 0.6% | $0.40 | 0.47% |
| pwsh-invoked-from-bash | powershell | sonnet46-200k-medium-cli2.1.97 | 1 | 5.6min | 0.8% | $0.52 | 0.62% |
| docker-pkg-install | default | sonnet46-200k-medium-cli2.1.97 | 1 | 1.5min | 0.2% | $0.17 | 0.20% |
| actionlint-fix-cycles | bash | opus46-200k-medium-cli2.1.97 | 1 | 0.7min | 0.1% | $0.09 | 0.11% |
| actionlint-fix-cycles | powershell | sonnet46-200k-medium-cli2.1.97 | 1 | 0.7min | 0.1% | $0.07 | 0.08% |
| fixture-rework | default | sonnet46-200k-medium-cli2.1.97 | 1 | 1.0min | 0.1% | $0.09 | 0.11% |
| act-permission-path-errors | powershell | sonnet46-200k-medium-cli2.1.97 | 1 | 0.5min | 0.1% | $0.04 | 0.05% |


<details>
<summary>Sorted by time lost (least first)</summary>

| Trap | Language | Model | Fell In | Time Lost | % of Time | $ Lost | % of $ |
|------|------|-------|---------|-----------|-----------|--------|--------|
| act-permission-path-errors | powershell | sonnet46-200k-medium-cli2.1.97 | 1 | 0.5min | 0.1% | $0.04 | 0.05% |
| repeated-test-reruns | default | sonnet46-200k-medium-cli2.1.97 | 1 | 0.7min | 0.1% | $0.06 | 0.07% |
| repeated-test-reruns | powershell | opus46-200k-medium-cli2.1.97 | 1 | 0.7min | 0.1% | $0.11 | 0.13% |
| repeated-test-reruns | typescript-bun | opus46-200k-medium-cli2.1.97 | 1 | 0.7min | 0.1% | $0.11 | 0.13% |
| actionlint-fix-cycles | bash | opus46-200k-medium-cli2.1.97 | 1 | 0.7min | 0.1% | $0.09 | 0.11% |
| actionlint-fix-cycles | powershell | sonnet46-200k-medium-cli2.1.97 | 1 | 0.7min | 0.1% | $0.07 | 0.08% |
| act-push-debug-loops | powershell | opus46-200k-medium-cli2.1.97 | 1 | 0.8min | 0.1% | $0.13 | 0.16% |
| fixture-rework | default | sonnet46-200k-medium-cli2.1.97 | 1 | 1.0min | 0.1% | $0.09 | 0.11% |
| docker-pkg-install | default | sonnet46-200k-medium-cli2.1.97 | 1 | 1.5min | 0.2% | $0.17 | 0.20% |
| repeated-test-reruns | bash | sonnet46-200k-medium-cli2.1.97 | 2 | 1.7min | 0.2% | $0.19 | 0.23% |
| repeated-test-reruns | typescript-bun | sonnet46-200k-medium-cli2.1.97 | 2 | 2.7min | 0.4% | $0.31 | 0.36% |
| act-push-debug-loops | typescript-bun | sonnet46-200k-medium-cli2.1.97 | 2 | 2.8min | 0.4% | $0.29 | 0.35% |
| docker-pwsh-install | powershell | opus46-200k-medium-cli2.1.97 | 1 | 3.0min | 0.4% | $0.42 | 0.50% |
| docker-pwsh-install | powershell | sonnet46-200k-medium-cli2.1.97 | 2 | 4.5min | 0.6% | $0.40 | 0.47% |
| act-push-debug-loops | default | sonnet46-200k-medium-cli2.1.97 | 3 | 4.7min | 0.7% | $0.50 | 0.60% |
| repeated-test-reruns | powershell | sonnet46-200k-medium-cli2.1.97 | 5 | 5.0min | 0.7% | $0.38 | 0.45% |
| pwsh-invoked-from-bash | powershell | sonnet46-200k-medium-cli2.1.97 | 1 | 5.6min | 0.8% | $0.52 | 0.62% |
| pwsh-runtime-install-overhead | powershell | opus46-200k-medium-cli2.1.97 | 7 | 10.2min | 1.4% | $1.13 | 1.34% |
| act-push-debug-loops | powershell | sonnet46-200k-medium-cli2.1.97 | 3 | 15.7min | 2.2% | $0.93 | 1.10% |
| pwsh-runtime-install-overhead | powershell | sonnet46-200k-medium-cli2.1.97 | 8 | 16.0min | 2.2% | $1.31 | 1.56% |

</details>

<details>
<summary>Sorted by $ lost (least first)</summary>

| Trap | Language | Model | Fell In | Time Lost | % of Time | $ Lost | % of $ |
|------|------|-------|---------|-----------|-----------|--------|--------|
| act-permission-path-errors | powershell | sonnet46-200k-medium-cli2.1.97 | 1 | 0.5min | 0.1% | $0.04 | 0.05% |
| repeated-test-reruns | default | sonnet46-200k-medium-cli2.1.97 | 1 | 0.7min | 0.1% | $0.06 | 0.07% |
| actionlint-fix-cycles | powershell | sonnet46-200k-medium-cli2.1.97 | 1 | 0.7min | 0.1% | $0.07 | 0.08% |
| fixture-rework | default | sonnet46-200k-medium-cli2.1.97 | 1 | 1.0min | 0.1% | $0.09 | 0.11% |
| actionlint-fix-cycles | bash | opus46-200k-medium-cli2.1.97 | 1 | 0.7min | 0.1% | $0.09 | 0.11% |
| repeated-test-reruns | typescript-bun | opus46-200k-medium-cli2.1.97 | 1 | 0.7min | 0.1% | $0.11 | 0.13% |
| repeated-test-reruns | powershell | opus46-200k-medium-cli2.1.97 | 1 | 0.7min | 0.1% | $0.11 | 0.13% |
| act-push-debug-loops | powershell | opus46-200k-medium-cli2.1.97 | 1 | 0.8min | 0.1% | $0.13 | 0.16% |
| docker-pkg-install | default | sonnet46-200k-medium-cli2.1.97 | 1 | 1.5min | 0.2% | $0.17 | 0.20% |
| repeated-test-reruns | bash | sonnet46-200k-medium-cli2.1.97 | 2 | 1.7min | 0.2% | $0.19 | 0.23% |
| act-push-debug-loops | typescript-bun | sonnet46-200k-medium-cli2.1.97 | 2 | 2.8min | 0.4% | $0.29 | 0.35% |
| repeated-test-reruns | typescript-bun | sonnet46-200k-medium-cli2.1.97 | 2 | 2.7min | 0.4% | $0.31 | 0.36% |
| repeated-test-reruns | powershell | sonnet46-200k-medium-cli2.1.97 | 5 | 5.0min | 0.7% | $0.38 | 0.45% |
| docker-pwsh-install | powershell | sonnet46-200k-medium-cli2.1.97 | 2 | 4.5min | 0.6% | $0.40 | 0.47% |
| docker-pwsh-install | powershell | opus46-200k-medium-cli2.1.97 | 1 | 3.0min | 0.4% | $0.42 | 0.50% |
| act-push-debug-loops | default | sonnet46-200k-medium-cli2.1.97 | 3 | 4.7min | 0.7% | $0.50 | 0.60% |
| pwsh-invoked-from-bash | powershell | sonnet46-200k-medium-cli2.1.97 | 1 | 5.6min | 0.8% | $0.52 | 0.62% |
| act-push-debug-loops | powershell | sonnet46-200k-medium-cli2.1.97 | 3 | 15.7min | 2.2% | $0.93 | 1.10% |
| pwsh-runtime-install-overhead | powershell | opus46-200k-medium-cli2.1.97 | 7 | 10.2min | 1.4% | $1.13 | 1.34% |
| pwsh-runtime-install-overhead | powershell | sonnet46-200k-medium-cli2.1.97 | 8 | 16.0min | 2.2% | $1.31 | 1.56% |

</details>

<details>
<summary>Sorted by fell-in count (fewest first)</summary>

| Trap | Language | Model | Fell In | Time Lost | % of Time | $ Lost | % of $ |
|------|------|-------|---------|-----------|-----------|--------|--------|
| act-push-debug-loops | powershell | opus46-200k-medium-cli2.1.97 | 1 | 0.8min | 0.1% | $0.13 | 0.16% |
| repeated-test-reruns | default | sonnet46-200k-medium-cli2.1.97 | 1 | 0.7min | 0.1% | $0.06 | 0.07% |
| repeated-test-reruns | powershell | opus46-200k-medium-cli2.1.97 | 1 | 0.7min | 0.1% | $0.11 | 0.13% |
| repeated-test-reruns | typescript-bun | opus46-200k-medium-cli2.1.97 | 1 | 0.7min | 0.1% | $0.11 | 0.13% |
| docker-pwsh-install | powershell | opus46-200k-medium-cli2.1.97 | 1 | 3.0min | 0.4% | $0.42 | 0.50% |
| pwsh-invoked-from-bash | powershell | sonnet46-200k-medium-cli2.1.97 | 1 | 5.6min | 0.8% | $0.52 | 0.62% |
| docker-pkg-install | default | sonnet46-200k-medium-cli2.1.97 | 1 | 1.5min | 0.2% | $0.17 | 0.20% |
| actionlint-fix-cycles | bash | opus46-200k-medium-cli2.1.97 | 1 | 0.7min | 0.1% | $0.09 | 0.11% |
| actionlint-fix-cycles | powershell | sonnet46-200k-medium-cli2.1.97 | 1 | 0.7min | 0.1% | $0.07 | 0.08% |
| fixture-rework | default | sonnet46-200k-medium-cli2.1.97 | 1 | 1.0min | 0.1% | $0.09 | 0.11% |
| act-permission-path-errors | powershell | sonnet46-200k-medium-cli2.1.97 | 1 | 0.5min | 0.1% | $0.04 | 0.05% |
| act-push-debug-loops | typescript-bun | sonnet46-200k-medium-cli2.1.97 | 2 | 2.8min | 0.4% | $0.29 | 0.35% |
| repeated-test-reruns | bash | sonnet46-200k-medium-cli2.1.97 | 2 | 1.7min | 0.2% | $0.19 | 0.23% |
| repeated-test-reruns | typescript-bun | sonnet46-200k-medium-cli2.1.97 | 2 | 2.7min | 0.4% | $0.31 | 0.36% |
| docker-pwsh-install | powershell | sonnet46-200k-medium-cli2.1.97 | 2 | 4.5min | 0.6% | $0.40 | 0.47% |
| act-push-debug-loops | default | sonnet46-200k-medium-cli2.1.97 | 3 | 4.7min | 0.7% | $0.50 | 0.60% |
| act-push-debug-loops | powershell | sonnet46-200k-medium-cli2.1.97 | 3 | 15.7min | 2.2% | $0.93 | 1.10% |
| repeated-test-reruns | powershell | sonnet46-200k-medium-cli2.1.97 | 5 | 5.0min | 0.7% | $0.38 | 0.45% |
| pwsh-runtime-install-overhead | powershell | opus46-200k-medium-cli2.1.97 | 7 | 10.2min | 1.4% | $1.13 | 1.34% |
| pwsh-runtime-install-overhead | powershell | sonnet46-200k-medium-cli2.1.97 | 8 | 16.0min | 2.2% | $1.31 | 1.56% |

</details>

#### Trap Descriptions

- **act-permission-path-errors**: Files not found or permission denied inside the act Docker container.
- **act-push-debug-loops**: Agent ran `act push` more than twice, indicating repeated workflow debugging.
- **actionlint-fix-cycles**: Workflow YAML required 3+ actionlint runs and 2+ fixes to pass.
- **docker-pkg-install**: Multiple Docker test runs exploring non-PowerShell package installation for act.
- **docker-pwsh-install**: Multiple Docker test runs trying to figure out how to install PowerShell in act's container.
- **fixture-rework**: Agent rewrote or edited the same fixture file multiple times (genuine redo cycles, not one-time fixture creation).
- **pwsh-invoked-from-bash**: Agent used `pwsh -Command`/`-File` from bash `run:` steps instead of `shell: pwsh`, causing cross-shell debugging (parse errors, quoting issues, scope problems, late pwsh discovery in act).
- **pwsh-runtime-install-overhead**: Time spent installing PowerShell and Pester inside act containers. Both are pre-installed on real GitHub runners but must be downloaded (~56MB) and installed in each act job. Measured from act step durations.
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
| bash | opus46-200k-medium-cli2.1.97 | 8 | 1 | 0.7min | 0.1% | $0.09 | 0.11% |
| bash | sonnet46-200k-medium-cli2.1.97 | 8 | 2 | 1.7min | 0.2% | $0.19 | 0.23% |
| default | opus46-200k-medium-cli2.1.97 | 8 | 0 | 0.0min | 0.0% | $0.00 | 0.00% |
| default | sonnet46-200k-medium-cli2.1.97 | 8 | 6 | 7.9min | 1.1% | $0.83 | 0.98% |
| powershell | opus46-200k-medium-cli2.1.97 | 8 | 10 | 14.7min | 2.0% | $1.79 | 2.13% |
| powershell | sonnet46-200k-medium-cli2.1.97 | 8 | 21 | 48.0min | 6.6% | $3.66 | 4.34% |
| typescript-bun | opus46-200k-medium-cli2.1.97 | 8 | 1 | 0.7min | 0.1% | $0.11 | 0.13% |
| typescript-bun | sonnet46-200k-medium-cli2.1.97 | 8 | 4 | 5.5min | 0.8% | $0.60 | 0.71% |


<details>
<summary>Sorted by time lost (least first)</summary>

| Language | Model | Runs | Traps | Time Lost | % of Time | $ Lost | % of $ |
|------|-------|------|-------|-----------|-----------|--------|--------|
| default | opus46-200k-medium-cli2.1.97 | 8 | 0 | 0.0min | 0.0% | $0.00 | 0.00% |
| bash | opus46-200k-medium-cli2.1.97 | 8 | 1 | 0.7min | 0.1% | $0.09 | 0.11% |
| typescript-bun | opus46-200k-medium-cli2.1.97 | 8 | 1 | 0.7min | 0.1% | $0.11 | 0.13% |
| bash | sonnet46-200k-medium-cli2.1.97 | 8 | 2 | 1.7min | 0.2% | $0.19 | 0.23% |
| typescript-bun | sonnet46-200k-medium-cli2.1.97 | 8 | 4 | 5.5min | 0.8% | $0.60 | 0.71% |
| default | sonnet46-200k-medium-cli2.1.97 | 8 | 6 | 7.9min | 1.1% | $0.83 | 0.98% |
| powershell | opus46-200k-medium-cli2.1.97 | 8 | 10 | 14.7min | 2.0% | $1.79 | 2.13% |
| powershell | sonnet46-200k-medium-cli2.1.97 | 8 | 21 | 48.0min | 6.6% | $3.66 | 4.34% |

</details>

<details>
<summary>Sorted by $ lost (least first)</summary>

| Language | Model | Runs | Traps | Time Lost | % of Time | $ Lost | % of $ |
|------|-------|------|-------|-----------|-----------|--------|--------|
| default | opus46-200k-medium-cli2.1.97 | 8 | 0 | 0.0min | 0.0% | $0.00 | 0.00% |
| bash | opus46-200k-medium-cli2.1.97 | 8 | 1 | 0.7min | 0.1% | $0.09 | 0.11% |
| typescript-bun | opus46-200k-medium-cli2.1.97 | 8 | 1 | 0.7min | 0.1% | $0.11 | 0.13% |
| bash | sonnet46-200k-medium-cli2.1.97 | 8 | 2 | 1.7min | 0.2% | $0.19 | 0.23% |
| typescript-bun | sonnet46-200k-medium-cli2.1.97 | 8 | 4 | 5.5min | 0.8% | $0.60 | 0.71% |
| default | sonnet46-200k-medium-cli2.1.97 | 8 | 6 | 7.9min | 1.1% | $0.83 | 0.98% |
| powershell | opus46-200k-medium-cli2.1.97 | 8 | 10 | 14.7min | 2.0% | $1.79 | 2.13% |
| powershell | sonnet46-200k-medium-cli2.1.97 | 8 | 21 | 48.0min | 6.6% | $3.66 | 4.34% |

</details>

### Prompt Cache Savings

| Status | Runs | $ Saved | % of $ |
|--------|------|---------|--------|
| Full hit (100%) | 1 | $0.06 | 0.07% |
| Partial | 62 | $3.24 | 3.84% |
| Miss | 1 | $0.00 | 0.00% |

## Test Quality Evaluation

### Structural Metrics by Language/Model/Effort

Automated analysis of test files: test count, assertion count, and test-to-code line ratio.

| Language | Model | Avg Tests | Avg Assertions | Avg Assert/Test | Avg Test:Code Ratio |
|------|-------|-----------|----------------|-----------------|---------------------|
| bash | opus46-200k-medium | 18.5 | 28.2 | 1.5 | 1.45 |
| bash | sonnet46-200k-medium | 16.8 | 33.9 | 2.0 | 0.67 |
| default | opus46-200k-medium | 9.0 | 24.6 | 2.7 | 1.64 |
| default | sonnet46-200k-medium | 33.1 | 49.8 | 1.5 | 1.10 |
| powershell | opus46-200k-medium | 32.6 | 48.0 | 1.5 | 0.96 |
| powershell | sonnet46-200k-medium | 40.0 | 57.9 | 1.4 | 1.34 |
| typescript-bun | opus46-200k-medium | 10.1 | 40.2 | 4.0 | 1.02 |
| typescript-bun | sonnet46-200k-medium | 34.6 | 60.1 | 1.7 | 1.55 |


<details>
<summary>Sorted by avg tests (most first)</summary>

| Language | Model | Avg Tests | Avg Assertions | Avg Assert/Test | Avg Test:Code Ratio |
|------|-------|-----------|----------------|-----------------|---------------------|
| powershell | sonnet46-200k-medium | 40.0 | 57.9 | 1.4 | 1.34 |
| typescript-bun | sonnet46-200k-medium | 34.6 | 60.1 | 1.7 | 1.55 |
| default | sonnet46-200k-medium | 33.1 | 49.8 | 1.5 | 1.10 |
| powershell | opus46-200k-medium | 32.6 | 48.0 | 1.5 | 0.96 |
| bash | opus46-200k-medium | 18.5 | 28.2 | 1.5 | 1.45 |
| bash | sonnet46-200k-medium | 16.8 | 33.9 | 2.0 | 0.67 |
| typescript-bun | opus46-200k-medium | 10.1 | 40.2 | 4.0 | 1.02 |
| default | opus46-200k-medium | 9.0 | 24.6 | 2.7 | 1.64 |

</details>

<details>
<summary>Sorted by avg assertions (most first)</summary>

| Language | Model | Avg Tests | Avg Assertions | Avg Assert/Test | Avg Test:Code Ratio |
|------|-------|-----------|----------------|-----------------|---------------------|
| typescript-bun | sonnet46-200k-medium | 34.6 | 60.1 | 1.7 | 1.55 |
| powershell | sonnet46-200k-medium | 40.0 | 57.9 | 1.4 | 1.34 |
| default | sonnet46-200k-medium | 33.1 | 49.8 | 1.5 | 1.10 |
| powershell | opus46-200k-medium | 32.6 | 48.0 | 1.5 | 0.96 |
| typescript-bun | opus46-200k-medium | 10.1 | 40.2 | 4.0 | 1.02 |
| bash | sonnet46-200k-medium | 16.8 | 33.9 | 2.0 | 0.67 |
| bash | opus46-200k-medium | 18.5 | 28.2 | 1.5 | 1.45 |
| default | opus46-200k-medium | 9.0 | 24.6 | 2.7 | 1.64 |

</details>

<details>
<summary>Sorted by avg test:code ratio (highest first)</summary>

| Language | Model | Avg Tests | Avg Assertions | Avg Assert/Test | Avg Test:Code Ratio |
|------|-------|-----------|----------------|-----------------|---------------------|
| default | opus46-200k-medium | 9.0 | 24.6 | 2.7 | 1.64 |
| typescript-bun | sonnet46-200k-medium | 34.6 | 60.1 | 1.7 | 1.55 |
| bash | opus46-200k-medium | 18.5 | 28.2 | 1.5 | 1.45 |
| powershell | sonnet46-200k-medium | 40.0 | 57.9 | 1.4 | 1.34 |
| default | sonnet46-200k-medium | 33.1 | 49.8 | 1.5 | 1.10 |
| typescript-bun | opus46-200k-medium | 10.1 | 40.2 | 4.0 | 1.02 |
| powershell | opus46-200k-medium | 32.6 | 48.0 | 1.5 | 0.96 |
| bash | sonnet46-200k-medium | 16.8 | 33.9 | 2.0 | 0.67 |

</details>


<details>
<summary>Per-run structural metrics</summary>

| Task | Language | Model | Tests | Assertions | Assert/Test | Test Lines | Impl Lines | Test:Code |
|------|------|-------|-------|------------|-------------|------------|------------|-----------|
| Semantic Version Bumper | bash | opus46-200k-medium | 30 | 19 | 0.6 | 268 | 268 | 1.00 |
| Semantic Version Bumper | bash | sonnet46-200k-medium | 17 | 41 | 2.4 | 275 | 521 | 0.53 |
| Semantic Version Bumper | default | opus46-200k-medium | 9 | 0 | 0.0 | 421 | 284 | 1.48 |
| Semantic Version Bumper | default | sonnet46-200k-medium | 52 | 57 | 1.1 | 599 | 291 | 2.06 |
| Semantic Version Bumper | powershell | opus46-200k-medium | 34 | 44 | 1.3 | 340 | 361 | 0.94 |
| Semantic Version Bumper | powershell | sonnet46-200k-medium | 36 | 45 | 1.2 | 273 | 279 | 0.98 |
| Semantic Version Bumper | typescript-bun | opus46-200k-medium | 8 | 28 | 3.5 | 310 | 282 | 1.10 |
| Semantic Version Bumper | typescript-bun | sonnet46-200k-medium | 28 | 39 | 1.4 | 253 | 434 | 0.58 |
| PR Label Assigner | bash | opus46-200k-medium | 11 | 17 | 1.5 | 272 | 208 | 1.31 |
| PR Label Assigner | bash | sonnet46-200k-medium | 15 | 34 | 2.3 | 258 | 500 | 0.52 |
| PR Label Assigner | default | opus46-200k-medium | 10 | 0 | 0.0 | 333 | 180 | 1.85 |
| PR Label Assigner | default | sonnet46-200k-medium | 17 | 25 | 1.5 | 274 | 328 | 0.84 |
| PR Label Assigner | powershell | opus46-200k-medium | 17 | 41 | 2.4 | 182 | 332 | 0.55 |
| PR Label Assigner | powershell | sonnet46-200k-medium | 45 | 64 | 1.4 | 484 | 210 | 2.30 |
| PR Label Assigner | typescript-bun | opus46-200k-medium | 6 | 20 | 3.3 | 404 | 252 | 1.60 |
| PR Label Assigner | typescript-bun | sonnet46-200k-medium | 20 | 31 | 1.6 | 208 | 483 | 0.43 |
| Dependency License Checker | bash | opus46-200k-medium | 18 | 46 | 2.6 | 159 | 498 | 0.32 |
| Dependency License Checker | bash | sonnet46-200k-medium | 17 | 28 | 1.6 | 167 | 257 | 0.65 |
| Dependency License Checker | default | opus46-200k-medium | 25 | 32 | 1.3 | 277 | 212 | 1.31 |
| Dependency License Checker | default | sonnet46-200k-medium | 26 | 55 | 2.1 | 364 | 750 | 0.49 |
| Dependency License Checker | powershell | opus46-200k-medium | 37 | 43 | 1.2 | 257 | 754 | 0.34 |
| Dependency License Checker | powershell | sonnet46-200k-medium | 38 | 84 | 2.2 | 448 | 281 | 1.59 |
| Dependency License Checker | typescript-bun | opus46-200k-medium | 19 | 37 | 1.9 | 203 | 588 | 0.35 |
| Dependency License Checker | typescript-bun | sonnet46-200k-medium | 39 | 72 | 1.8 | 537 | 393 | 1.37 |
| Docker Image Tag Generator | bash | opus46-200k-medium | 17 | 31 | 1.8 | 299 | 87 | 3.44 |
| Docker Image Tag Generator | bash | sonnet46-200k-medium | 17 | 12 | 0.7 | 250 | 150 | 1.67 |
| Docker Image Tag Generator | default | opus46-200k-medium | 6 | 2 | 0.3 | 414 | 149 | 2.78 |
| Docker Image Tag Generator | default | sonnet46-200k-medium | 35 | 36 | 1.0 | 265 | 555 | 0.48 |
| Docker Image Tag Generator | powershell | opus46-200k-medium | 21 | 24 | 1.1 | 136 | 441 | 0.31 |
| Docker Image Tag Generator | powershell | sonnet46-200k-medium | 39 | 58 | 1.5 | 295 | 474 | 0.62 |
| Docker Image Tag Generator | typescript-bun | opus46-200k-medium | 8 | 18 | 2.2 | 322 | 164 | 1.96 |
| Docker Image Tag Generator | typescript-bun | sonnet46-200k-medium | 46 | 59 | 1.3 | 653 | 170 | 3.84 |
| Test Results Aggregator | bash | opus46-200k-medium | 24 | 9 | 0.4 | 257 | 295 | 0.87 |
| Test Results Aggregator | bash | sonnet46-200k-medium | 23 | 36 | 1.6 | 137 | 335 | 0.41 |
| Test Results Aggregator | default | opus46-200k-medium | 6 | 49 | 8.2 | 462 | 371 | 1.25 |
| Test Results Aggregator | default | sonnet46-200k-medium | 29 | 77 | 2.7 | 393 | 950 | 0.41 |
| Test Results Aggregator | powershell | opus46-200k-medium | 41 | 43 | 1.0 | 335 | 205 | 1.63 |
| Test Results Aggregator | powershell | sonnet46-200k-medium | 69 | 83 | 1.2 | 588 | 442 | 1.33 |
| Test Results Aggregator | typescript-bun | opus46-200k-medium | 8 | 59 | 7.4 | 302 | 679 | 0.44 |
| Test Results Aggregator | typescript-bun | sonnet46-200k-medium | 45 | 94 | 2.1 | 685 | 585 | 1.17 |
| Environment Matrix Generator | bash | opus46-200k-medium | 17 | 24 | 1.4 | 327 | 166 | 1.97 |
| Environment Matrix Generator | bash | sonnet46-200k-medium | 18 | 29 | 1.6 | 291 | 323 | 0.90 |
| Environment Matrix Generator | default | opus46-200k-medium | 0 | 0 | 0.0 | 0 | 235 | 0.00 |
| Environment Matrix Generator | default | sonnet46-200k-medium | 38 | 46 | 1.2 | 352 | 165 | 2.13 |
| Environment Matrix Generator | powershell | opus46-200k-medium | 43 | 62 | 1.4 | 324 | 286 | 1.13 |
| Environment Matrix Generator | powershell | sonnet46-200k-medium | 36 | 37 | 1.0 | 403 | 170 | 2.37 |
| Environment Matrix Generator | typescript-bun | opus46-200k-medium | 12 | 50 | 4.2 | 340 | 284 | 1.20 |
| Environment Matrix Generator | typescript-bun | sonnet46-200k-medium | 35 | 62 | 1.8 | 611 | 231 | 2.65 |
| Artifact Cleanup Script | bash | opus46-200k-medium | 15 | 29 | 1.9 | 540 | 296 | 1.82 |
| Artifact Cleanup Script | bash | sonnet46-200k-medium | 12 | 48 | 4.0 | 247 | 556 | 0.44 |
| Artifact Cleanup Script | default | opus46-200k-medium | 8 | 55 | 6.9 | 396 | 264 | 1.50 |
| Artifact Cleanup Script | default | sonnet46-200k-medium | 23 | 50 | 2.2 | 705 | 372 | 1.90 |
| Artifact Cleanup Script | powershell | opus46-200k-medium | 19 | 53 | 2.8 | 242 | 306 | 0.79 |
| Artifact Cleanup Script | powershell | sonnet46-200k-medium | 22 | 41 | 1.9 | 226 | 224 | 1.01 |
| Artifact Cleanup Script | typescript-bun | opus46-200k-medium | 13 | 33 | 2.5 | 201 | 531 | 0.38 |
| Artifact Cleanup Script | typescript-bun | sonnet46-200k-medium | 18 | 35 | 1.9 | 276 | 280 | 0.99 |
| Secret Rotation Validator | bash | opus46-200k-medium | 16 | 51 | 3.2 | 212 | 250 | 0.85 |
| Secret Rotation Validator | bash | sonnet46-200k-medium | 15 | 43 | 2.9 | 215 | 871 | 0.25 |
| Secret Rotation Validator | default | opus46-200k-medium | 8 | 59 | 7.4 | 663 | 225 | 2.95 |
| Secret Rotation Validator | default | sonnet46-200k-medium | 45 | 52 | 1.2 | 359 | 735 | 0.49 |
| Secret Rotation Validator | powershell | opus46-200k-medium | 49 | 74 | 1.5 | 396 | 197 | 2.01 |
| Secret Rotation Validator | powershell | sonnet46-200k-medium | 35 | 51 | 1.5 | 382 | 717 | 0.53 |
| Secret Rotation Validator | typescript-bun | opus46-200k-medium | 7 | 77 | 11.0 | 299 | 271 | 1.10 |
| Secret Rotation Validator | typescript-bun | sonnet46-200k-medium | 46 | 89 | 1.9 | 559 | 399 | 1.40 |

</details>

### LLM-as-Judge Scores

An LLM evaluates each test suite on four dimensions (1-5 scale):

- **Coverage** (1-5): Do tests exercise the key requirements? 1 = most untested, 5 = all covered.
- **Rigor** (1-5): Edge cases, error handling, boundary conditions? 1 = happy path only, 5 = thorough.
- **Design** (1-5): Test organization, fixtures, readability? 1 = messy/brittle, 5 = well-structured.
- **Overall** (1-5): Holistic quality — would you trust this suite to catch regressions? 1 = no, 5 = absolutely. Use this as the primary ranking metric.

| Language | Model | Avg Overall | Avg Coverage | Avg Rigor | Avg Design | Judge Cost |
|------|-------|-------------|-------------|-----------|------------|------------|
| bash | opus46-200k-medium | **3.0** | 3.9 | 3.0 | 2.9 | $0.3609 |
| bash | sonnet46-200k-medium | **3.4** | 3.9 | 2.9 | 3.6 | $0.3842 |
| default | opus46-200k-medium | **3.1** | 3.8 | 2.6 | 3.2 | $0.3557 |
| default | sonnet46-200k-medium | **4.2** | 4.6 | 4.1 | 4.6 | $0.3986 |
| powershell | opus46-200k-medium | **2.9** | 3.5 | 2.6 | 3.4 | $0.4482 |
| powershell | sonnet46-200k-medium | **3.4** | 4.4 | 3.0 | 3.2 | $0.5469 |
| typescript-bun | opus46-200k-medium | **3.1** | 3.6 | 2.8 | 3.5 | $0.4148 |
| typescript-bun | sonnet46-200k-medium | **3.4** | 3.8 | 3.1 | 3.8 | $0.4911 |
| **Total** | | | | | | **$3.4004** |


<details>
<summary>Sorted by avg overall (highest first)</summary>

| Language | Model | Avg Overall | Avg Coverage | Avg Rigor | Avg Design | Judge Cost |
|------|-------|-------------|-------------|-----------|------------|------------|
| default | sonnet46-200k-medium | **4.2** | 4.6 | 4.1 | 4.6 | $0.3986 |
| bash | sonnet46-200k-medium | **3.4** | 3.9 | 2.9 | 3.6 | $0.3842 |
| powershell | sonnet46-200k-medium | **3.4** | 4.4 | 3.0 | 3.2 | $0.5469 |
| typescript-bun | sonnet46-200k-medium | **3.4** | 3.8 | 3.1 | 3.8 | $0.4911 |
| default | opus46-200k-medium | **3.1** | 3.8 | 2.6 | 3.2 | $0.3557 |
| typescript-bun | opus46-200k-medium | **3.1** | 3.6 | 2.8 | 3.5 | $0.4148 |
| bash | opus46-200k-medium | **3.0** | 3.9 | 3.0 | 2.9 | $0.3609 |
| powershell | opus46-200k-medium | **2.9** | 3.5 | 2.6 | 3.4 | $0.4482 |

</details>

<details>
<summary>Sorted by avg coverage (highest first)</summary>

| Language | Model | Avg Overall | Avg Coverage | Avg Rigor | Avg Design | Judge Cost |
|------|-------|-------------|-------------|-----------|------------|------------|
| default | sonnet46-200k-medium | **4.2** | 4.6 | 4.1 | 4.6 | $0.3986 |
| powershell | sonnet46-200k-medium | **3.4** | 4.4 | 3.0 | 3.2 | $0.5469 |
| bash | opus46-200k-medium | **3.0** | 3.9 | 3.0 | 2.9 | $0.3609 |
| bash | sonnet46-200k-medium | **3.4** | 3.9 | 2.9 | 3.6 | $0.3842 |
| default | opus46-200k-medium | **3.1** | 3.8 | 2.6 | 3.2 | $0.3557 |
| typescript-bun | sonnet46-200k-medium | **3.4** | 3.8 | 3.1 | 3.8 | $0.4911 |
| typescript-bun | opus46-200k-medium | **3.1** | 3.6 | 2.8 | 3.5 | $0.4148 |
| powershell | opus46-200k-medium | **2.9** | 3.5 | 2.6 | 3.4 | $0.4482 |

</details>

<details>
<summary>Sorted by avg rigor (highest first)</summary>

| Language | Model | Avg Overall | Avg Coverage | Avg Rigor | Avg Design | Judge Cost |
|------|-------|-------------|-------------|-----------|------------|------------|
| default | sonnet46-200k-medium | **4.2** | 4.6 | 4.1 | 4.6 | $0.3986 |
| typescript-bun | sonnet46-200k-medium | **3.4** | 3.8 | 3.1 | 3.8 | $0.4911 |
| bash | opus46-200k-medium | **3.0** | 3.9 | 3.0 | 2.9 | $0.3609 |
| powershell | sonnet46-200k-medium | **3.4** | 4.4 | 3.0 | 3.2 | $0.5469 |
| bash | sonnet46-200k-medium | **3.4** | 3.9 | 2.9 | 3.6 | $0.3842 |
| typescript-bun | opus46-200k-medium | **3.1** | 3.6 | 2.8 | 3.5 | $0.4148 |
| default | opus46-200k-medium | **3.1** | 3.8 | 2.6 | 3.2 | $0.3557 |
| powershell | opus46-200k-medium | **2.9** | 3.5 | 2.6 | 3.4 | $0.4482 |

</details>

<details>
<summary>Sorted by avg design (highest first)</summary>

| Language | Model | Avg Overall | Avg Coverage | Avg Rigor | Avg Design | Judge Cost |
|------|-------|-------------|-------------|-----------|------------|------------|
| default | sonnet46-200k-medium | **4.2** | 4.6 | 4.1 | 4.6 | $0.3986 |
| typescript-bun | sonnet46-200k-medium | **3.4** | 3.8 | 3.1 | 3.8 | $0.4911 |
| bash | sonnet46-200k-medium | **3.4** | 3.9 | 2.9 | 3.6 | $0.3842 |
| typescript-bun | opus46-200k-medium | **3.1** | 3.6 | 2.8 | 3.5 | $0.4148 |
| powershell | opus46-200k-medium | **2.9** | 3.5 | 2.6 | 3.4 | $0.4482 |
| default | opus46-200k-medium | **3.1** | 3.8 | 2.6 | 3.2 | $0.3557 |
| powershell | sonnet46-200k-medium | **3.4** | 4.4 | 3.0 | 3.2 | $0.5469 |
| bash | opus46-200k-medium | **3.0** | 3.9 | 3.0 | 2.9 | $0.3609 |

</details>


<details>
<summary>Per-run LLM judge scores</summary>

| Task | Language | Model | Cov | Rig | Des | Ovr | Summary |
|------|------|-------|-----|-----|-----|-----|---------|
| Semantic Version Bumper | bash | opus46-200k-medium | 4.0 | 3.0 | 3.0 | 3.0 |  |
| Semantic Version Bumper | bash | sonnet46-200k-medium | 5.0 | 4.0 | 4.0 | 4.0 |  |
| Semantic Version Bumper | default | opus46-200k-medium | 2.0 | 2.0 | 2.0 | 2.0 |  |
| Semantic Version Bumper | default | sonnet46-200k-medium | 4.0 | 3.0 | 4.0 | 4.0 |  |
| Semantic Version Bumper | powershell | opus46-200k-medium | 3.0 | 2.0 | 3.0 | 2.0 |  |
| Semantic Version Bumper | powershell | sonnet46-200k-medium | 4.0 | 3.0 | 3.0 | 3.0 |  |
| Semantic Version Bumper | typescript-bun | opus46-200k-medium | 3.0 | 2.0 | 4.0 | 3.0 |  |
| Semantic Version Bumper | typescript-bun | sonnet46-200k-medium | 3.0 | 3.0 | 4.0 | 3.0 |  |
| PR Label Assigner | bash | opus46-200k-medium | 3.0 | 2.0 | 2.0 | 2.0 |  |
| PR Label Assigner | bash | sonnet46-200k-medium | 4.0 | 3.0 | 4.0 | 4.0 |  |
| PR Label Assigner | default | opus46-200k-medium | 4.0 | 2.0 | 3.0 | 3.0 |  |
| PR Label Assigner | default | sonnet46-200k-medium | 5.0 | 4.0 | 4.0 | 4.0 |  |
| PR Label Assigner | powershell | opus46-200k-medium | 4.0 | 3.0 | 4.0 | 3.0 |  |
| PR Label Assigner | powershell | sonnet46-200k-medium | 5.0 | 4.0 | 4.0 | 4.0 |  |
| PR Label Assigner | typescript-bun | opus46-200k-medium | 3.0 | 2.0 | 3.0 | 3.0 |  |
| PR Label Assigner | typescript-bun | sonnet46-200k-medium | 5.0 | 4.0 | 4.0 | 4.0 |  |
| Dependency License Checker | bash | opus46-200k-medium | 4.0 | 4.0 | 4.0 | 4.0 |  |
| Dependency License Checker | bash | sonnet46-200k-medium | 3.0 | 2.0 | 3.0 | 2.0 |  |
| Dependency License Checker | default | opus46-200k-medium | 5.0 | 4.0 | 5.0 | 5.0 |  |
| Dependency License Checker | default | sonnet46-200k-medium | 4.0 | 4.0 | 4.0 | 4.0 |  |
| Dependency License Checker | powershell | opus46-200k-medium | 4.0 | 3.0 | 4.0 | 3.0 |  |
| Dependency License Checker | powershell | sonnet46-200k-medium | 4.0 | 2.0 | 3.0 | 3.0 |  |
| Dependency License Checker | typescript-bun | opus46-200k-medium | 5.0 | 4.0 | 5.0 | 4.0 |  |
| Dependency License Checker | typescript-bun | sonnet46-200k-medium | 3.0 | 3.0 | 3.0 | 3.0 |  |
| Docker Image Tag Generator | bash | opus46-200k-medium | 4.0 | 3.0 | 3.0 | 3.0 |  |
| Docker Image Tag Generator | bash | sonnet46-200k-medium | 4.0 | 3.0 | 4.0 | 4.0 |  |
| Docker Image Tag Generator | default | opus46-200k-medium | 3.0 | 2.0 | 3.0 | 3.0 |  |
| Docker Image Tag Generator | default | sonnet46-200k-medium | 5.0 | 4.0 | 5.0 | 4.0 |  |
| Docker Image Tag Generator | powershell | opus46-200k-medium | 4.0 | 3.0 | 3.0 | 3.0 |  |
| Docker Image Tag Generator | powershell | sonnet46-200k-medium | 5.0 | 4.0 | 3.0 | 4.0 |  |
| Docker Image Tag Generator | typescript-bun | opus46-200k-medium | 4.0 | 3.0 | 3.0 | 3.0 |  |
| Docker Image Tag Generator | typescript-bun | sonnet46-200k-medium | 5.0 | 4.0 | 4.0 | 4.0 |  |
| Test Results Aggregator | bash | opus46-200k-medium | 4.0 | 3.0 | 2.0 | 3.0 |  |
| Test Results Aggregator | bash | sonnet46-200k-medium | 3.0 | 2.0 | 3.0 | 3.0 |  |
| Test Results Aggregator | default | opus46-200k-medium | 4.0 | 3.0 | 4.0 | 3.0 |  |
| Test Results Aggregator | default | sonnet46-200k-medium | 5.0 | 4.0 | 5.0 | 4.0 |  |
| Test Results Aggregator | powershell | opus46-200k-medium | 3.0 | 3.0 | 4.0 | 3.0 |  |
| Test Results Aggregator | powershell | sonnet46-200k-medium | 5.0 | 3.0 | 4.0 | 4.0 |  |
| Test Results Aggregator | typescript-bun | opus46-200k-medium | 4.0 | 2.0 | 3.0 | 3.0 |  |
| Test Results Aggregator | typescript-bun | sonnet46-200k-medium | 3.0 | 3.0 | 4.0 | 3.0 |  |
| Environment Matrix Generator | bash | opus46-200k-medium | 4.0 | 3.0 | 3.0 | 3.0 |  |
| Environment Matrix Generator | bash | sonnet46-200k-medium | 4.0 | 3.0 | 3.0 | 3.0 |  |
| Environment Matrix Generator | default | opus46-200k-medium | 3.0 | 2.0 | 2.0 | 2.0 |  |
| Environment Matrix Generator | default | sonnet46-200k-medium | 5.0 | 5.0 | 5.0 | 5.0 |  |
| Environment Matrix Generator | powershell | opus46-200k-medium | 3.0 | 2.0 | 2.0 | 2.0 |  |
| Environment Matrix Generator | powershell | sonnet46-200k-medium | 4.0 | 2.0 | 3.0 | 3.0 |  |
| Environment Matrix Generator | typescript-bun | opus46-200k-medium | 4.0 | 3.0 | 3.0 | 3.0 |  |
| Environment Matrix Generator | typescript-bun | sonnet46-200k-medium | 4.0 | 3.0 | 4.0 | 4.0 |  |
| Artifact Cleanup Script | bash | opus46-200k-medium | 4.0 | 3.0 | 3.0 | 3.0 |  |
| Artifact Cleanup Script | bash | sonnet46-200k-medium | 4.0 | 3.0 | 4.0 | 4.0 |  |
| Artifact Cleanup Script | default | opus46-200k-medium | 5.0 | 4.0 | 4.0 | 4.0 |  |
| Artifact Cleanup Script | default | sonnet46-200k-medium | 4.0 | 4.0 | 5.0 | 4.0 |  |
| Artifact Cleanup Script | powershell | opus46-200k-medium | 4.0 | 3.0 | 4.0 | 4.0 |  |
| Artifact Cleanup Script | powershell | sonnet46-200k-medium | 4.0 | 3.0 | 3.0 | 3.0 |  |
| Artifact Cleanup Script | typescript-bun | opus46-200k-medium | 4.0 | 4.0 | 5.0 | 4.0 |  |
| Artifact Cleanup Script | typescript-bun | sonnet46-200k-medium | 3.0 | 2.0 | 3.0 | 2.0 |  |
| Secret Rotation Validator | bash | opus46-200k-medium | 4.0 | 3.0 | 3.0 | 3.0 |  |
| Secret Rotation Validator | bash | sonnet46-200k-medium | 4.0 | 3.0 | 4.0 | 3.0 |  |
| Secret Rotation Validator | default | opus46-200k-medium | 4.0 | 2.0 | 3.0 | 3.0 |  |
| Secret Rotation Validator | default | sonnet46-200k-medium | 5.0 | 5.0 | 5.0 | 5.0 |  |
| Secret Rotation Validator | powershell | opus46-200k-medium | 3.0 | 2.0 | 3.0 | 3.0 |  |
| Secret Rotation Validator | powershell | sonnet46-200k-medium | 4.0 | 3.0 | 3.0 | 3.0 |  |
| Secret Rotation Validator | typescript-bun | opus46-200k-medium | 2.0 | 2.0 | 2.0 | 2.0 |  |
| Secret Rotation Validator | typescript-bun | sonnet46-200k-medium | 4.0 | 3.0 | 4.0 | 4.0 |  |

</details>

### Correlation: Structural Metrics vs Tests Quality

Spearman rank correlation between automated counts and LLM judge scores.
Values near +1.0 indicate the LLM agrees with the structural signal; near 0 means no relationship.

| Structural Metric | vs Coverage | vs Rigor | vs Design | vs Overall |
|-------------------|------------|---------|----------|-----------|
| Test count | 0.24 | 0.31 | 0.27 | 0.32 |
| Assertion count | 0.18 | 0.18 | 0.25 | 0.27 |
| Test:code ratio | -0.09 | -0.2 | -0.16 | -0.04 |

*Based on 64 runs with both structural and LLM scores.*

### LLM vs Structural Discrepancies

**Qualitative disagreements** — structural metrics look reasonable; the LLM judge is weighing factors the counters can't measure.

| Task | Language | Model | Tests | Asserts | Cov | Rig | Des | Ovr | Flag | Justification |
|------|------|-------|-------|---------|-----|-----|-----|-----|------|---------------|
| Semantic Version Bumper | powershell | opus46-200k-medium | 34 | 44 | 3.0 | 2.0 | 3.0 | 2.0 | LLM says low rigor (2.0/5) but 44 assertions detected |  |
| Dependency License Checker | powershell | sonnet46-200k-medium | 38 | 84 | 4.0 | 2.0 | 3.0 | 3.0 | LLM says low rigor (2.0/5) but 84 assertions detected |  |
| Test Results Aggregator | typescript-bun | opus46-200k-medium | 8 | 59 | 4.0 | 2.0 | 3.0 | 3.0 | LLM says low rigor (2.0/5) but 59 assertions detected |  |
| Environment Matrix Generator | powershell | opus46-200k-medium | 43 | 62 | 3.0 | 2.0 | 2.0 | 2.0 | LLM says low rigor (2.0/5) but 62 assertions detected |  |
| Secret Rotation Validator | default | opus46-200k-medium | 8 | 59 | 4.0 | 2.0 | 3.0 | 3.0 | LLM says low rigor (2.0/5) but 59 assertions detected |  |
| Secret Rotation Validator | powershell | opus46-200k-medium | 49 | 74 | 3.0 | 2.0 | 3.0 | 3.0 | LLM says low rigor (2.0/5) but 74 assertions detected |  |
| Secret Rotation Validator | typescript-bun | opus46-200k-medium | 7 | 77 | 2.0 | 2.0 | 2.0 | 2.0 | LLM says low rigor (2.0/5) but 77 assertions detected |  |

## Per-Run Results

*Tests Quality = Overall (1-5) from LLM-as-judge of generated test code (dimensions: coverage, rigor, design). `—` = no judge data.*

| Task | Language | Model | Duration | Turns | Errors | Cost | Tests Quality | Chosen | Status |
|------|----------|-------|----------|-------|--------|------|-----------|--------|--------|
| Artifact Cleanup Script | bash | opus46-200k-medium | 8.1min | 38 | 2 | $1.51 | 3.0 | bash | ok |
| Artifact Cleanup Script | bash | sonnet46-200k-medium | 15.4min | 47 | 3 | $1.59 | 4.0 | bash | ok |
| Artifact Cleanup Script | default | opus46-200k-medium | 6.3min | 29 | 0 | $1.05 | 4.0 | python | ok |
| Artifact Cleanup Script | default | sonnet46-200k-medium | 15.9min | 25 | 1 | $1.49 | 4.0 | python | ok |
| Artifact Cleanup Script | powershell | opus46-200k-medium | 9.4min | 39 | 0 | $1.60 | 4.0 | powershell | ok |
| Artifact Cleanup Script | powershell | sonnet46-200k-medium | 6.5min | 31 | 0 | $0.70 | 3.0 | powershell | ok |
| Artifact Cleanup Script | typescript-bun | opus46-200k-medium | 12.3min | 30 | 0 | $2.06 | 4.0 | typescript | ok |
| Artifact Cleanup Script | typescript-bun | sonnet46-200k-medium | 11.7min | 30 | 1 | $1.18 | 2.0 | typescript | ok |
| Dependency License Checker | bash | opus46-200k-medium | 5.4min | 40 | 1 | $1.12 | 4.0 | bash | ok |
| Dependency License Checker | bash | sonnet46-200k-medium | 5.6min | 37 | 4 | $0.75 | 2.0 | bash | ok |
| Dependency License Checker | default | opus46-200k-medium | 10.6min | 65 | 4 | $2.35 | 5.0 | python | ok |
| Dependency License Checker | default | sonnet46-200k-medium | 13.5min | 40 | 1 | $1.13 | 4.0 | python | ok |
| Dependency License Checker | powershell | opus46-200k-medium | 11.1min | 38 | 1 | $1.55 | 3.0 | powershell | ok |
| Dependency License Checker | powershell | sonnet46-200k-medium | 28.0min | 59 | 0 | $1.85 | 3.0 | powershell | ok |
| Dependency License Checker | typescript-bun | opus46-200k-medium | 6.2min | 51 | 1 | $1.34 | 4.0 | typescript | ok |
| Dependency License Checker | typescript-bun | sonnet46-200k-medium | 7.7min | 47 | 4 | $1.10 | 3.0 | typescript | ok |
| Docker Image Tag Generator | bash | opus46-200k-medium | 14.5min | 33 | 2 | $2.06 | 3.0 | bash | ok |
| Docker Image Tag Generator | bash | sonnet46-200k-medium | 16.0min | 34 | 4 | $1.49 | 4.0 | bash | ok |
| Docker Image Tag Generator | default | opus46-200k-medium | 7.8min | 36 | 2 | $1.34 | 3.0 | python | ok |
| Docker Image Tag Generator | default | sonnet46-200k-medium | 14.6min | 13 | 1 | $1.14 | 4.0 | python | ok |
| Docker Image Tag Generator | powershell | opus46-200k-medium | 7.5min | 20 | 1 | $0.61 | 3.0 | powershell | ok |
| Docker Image Tag Generator | powershell | sonnet46-200k-medium | 24.4min | 51 | 1 | $2.13 | 4.0 | powershell | ok |
| Docker Image Tag Generator | typescript-bun | opus46-200k-medium | 11.1min | 40 | 1 | $1.02 | 3.0 | typescript | ok |
| Docker Image Tag Generator | typescript-bun | sonnet46-200k-medium | 10.2min | 19 | 1 | $1.03 | 4.0 | typescript | ok |
| Environment Matrix Generator | bash | opus46-200k-medium | 9.6min | 36 | 1 | $0.87 | 3.0 | bash | ok |
| Environment Matrix Generator | bash | sonnet46-200k-medium | 9.8min | 40 | 6 | $0.84 | 3.0 | bash | ok |
| Environment Matrix Generator | default | opus46-200k-medium | 4.6min | 36 | 1 | $0.98 | 2.0 | bash | ok |
| Environment Matrix Generator | default | sonnet46-200k-medium | 12.0min | 23 | 0 | $1.13 | 5.0 | python | ok |
| Environment Matrix Generator | powershell | opus46-200k-medium | 6.7min | 44 | 5 | $0.99 | 2.0 | powershell | ok |
| Environment Matrix Generator | powershell | sonnet46-200k-medium | 22.1min | 42 | 0 | $1.93 | 3.0 | powershell | ok |
| Environment Matrix Generator | typescript-bun | opus46-200k-medium | 7.0min | 41 | 4 | $1.15 | 3.0 | typescript | ok |
| Environment Matrix Generator | typescript-bun | sonnet46-200k-medium | 13.5min | 24 | 0 | $1.19 | 4.0 | typescript | ok |
| PR Label Assigner | bash | opus46-200k-medium | 6.5min | 42 | 2 | $1.22 | 2.0 | bash | ok |
| PR Label Assigner | bash | sonnet46-200k-medium | 6.8min | 39 | 5 | $0.90 | 4.0 | bash | ok |
| PR Label Assigner | default | opus46-200k-medium | 4.6min | 23 | 0 | $0.69 | 3.0 | python | ok |
| PR Label Assigner | default | sonnet46-200k-medium | 16.5min | 23 | 1 | $1.25 | 4.0 | python | ok |
| PR Label Assigner | powershell | opus46-200k-medium | 8.1min | 32 | 2 | $1.12 | 3.0 | powershell | ok |
| PR Label Assigner | powershell | sonnet46-200k-medium | 27.1min | 50 | 3 | $2.51 | 4.0 | powershell | ok |
| PR Label Assigner | typescript-bun | opus46-200k-medium | 9.1min | 31 | 1 | $0.96 | 3.0 | typescript | ok |
| PR Label Assigner | typescript-bun | sonnet46-200k-medium | 13.7min | 46 | 6 | $1.35 | 4.0 | typescript | ok |
| Secret Rotation Validator | bash | opus46-200k-medium | 11.5min | 33 | 1 | $1.34 | 3.0 | bash | ok |
| Secret Rotation Validator | bash | sonnet46-200k-medium | 11.2min | 31 | 4 | $0.94 | 3.0 | bash | ok |
| Secret Rotation Validator | default | opus46-200k-medium | 5.5min | 32 | 1 | $1.19 | 3.0 | python | ok |
| Secret Rotation Validator | default | sonnet46-200k-medium | 11.5min | 37 | 2 | $1.53 | 5.0 | python | ok |
| Secret Rotation Validator | powershell | opus46-200k-medium | 10.7min | 34 | 0 | $1.35 | 3.0 | powershell | ok |
| Secret Rotation Validator | powershell | sonnet46-200k-medium | 12.7min | 22 | 0 | $1.04 | 3.0 | powershell | ok |
| Secret Rotation Validator | typescript-bun | opus46-200k-medium | 5.4min | 44 | 5 | $1.17 | 2.0 | typescript | ok |
| Secret Rotation Validator | typescript-bun | sonnet46-200k-medium | 13.1min | 1 | 3 | $1.31 | 4.0 | typescript | ok |
| Semantic Version Bumper | bash | opus46-200k-medium | 6.8min | 46 | 2 | $1.45 | 3.0 | bash | ok |
| Semantic Version Bumper | bash | sonnet46-200k-medium | 4.9min | 30 | 2 | $0.68 | 4.0 | bash | ok |
| Semantic Version Bumper | default | opus46-200k-medium | 9.0min | 29 | 0 | $1.27 | 2.0 | python | ok |
| Semantic Version Bumper | default | sonnet46-200k-medium | 17.2min | 38 | 1 | $1.62 | 4.0 | python | ok |
| Semantic Version Bumper | powershell | opus46-200k-medium | 9.2min | 31 | 0 | $0.82 | 2.0 | powershell | ok |
| Semantic Version Bumper | powershell | sonnet46-200k-medium | 27.2min | 42 | 0 | $1.44 | 3.0 | powershell | ok |
| Semantic Version Bumper | typescript-bun | opus46-200k-medium | 13.2min | 35 | 0 | $1.89 | 3.0 | typescript | ok |
| Semantic Version Bumper | typescript-bun | sonnet46-200k-medium | 8.1min | 28 | 0 | $0.72 | 3.0 | typescript | ok |
| Test Results Aggregator | bash | opus46-200k-medium | 6.7min | 44 | 3 | $1.36 | 3.0 | bash | ok |
| Test Results Aggregator | bash | sonnet46-200k-medium | 12.0min | 43 | 5 | $1.26 | 3.0 | bash | ok |
| Test Results Aggregator | default | opus46-200k-medium | 7.6min | 40 | 2 | $1.43 | 3.0 | python | ok |
| Test Results Aggregator | default | sonnet46-200k-medium | 15.9min | 58 | 2 | $1.78 | 4.0 | python | ok |
| Test Results Aggregator | powershell | opus46-200k-medium | 9.8min | 31 | 1 | $1.58 | 3.0 | powershell | ok |
| Test Results Aggregator | powershell | sonnet46-200k-medium | 19.9min | 43 | 0 | $1.77 | 4.0 | powershell | ok |
| Test Results Aggregator | typescript-bun | opus46-200k-medium | 7.1min | 40 | 0 | $1.18 | 3.0 | typescript | ok |
| Test Results Aggregator | typescript-bun | sonnet46-200k-medium | 12.2min | 72 | 3 | $1.86 | 3.0 | typescript | ok |


<details>
<summary>Sorted by cost (cheapest first)</summary>

| Task | Language | Model | Duration | Turns | Errors | Cost | Tests Quality | Chosen | Status |
|------|----------|-------|----------|-------|--------|------|-----------|--------|--------|
| Docker Image Tag Generator | powershell | opus46-200k-medium | 7.5min | 20 | 1 | $0.61 | 3.0 | powershell | ok |
| Semantic Version Bumper | bash | sonnet46-200k-medium | 4.9min | 30 | 2 | $0.68 | 4.0 | bash | ok |
| PR Label Assigner | default | opus46-200k-medium | 4.6min | 23 | 0 | $0.69 | 3.0 | python | ok |
| Artifact Cleanup Script | powershell | sonnet46-200k-medium | 6.5min | 31 | 0 | $0.70 | 3.0 | powershell | ok |
| Semantic Version Bumper | typescript-bun | sonnet46-200k-medium | 8.1min | 28 | 0 | $0.72 | 3.0 | typescript | ok |
| Dependency License Checker | bash | sonnet46-200k-medium | 5.6min | 37 | 4 | $0.75 | 2.0 | bash | ok |
| Semantic Version Bumper | powershell | opus46-200k-medium | 9.2min | 31 | 0 | $0.82 | 2.0 | powershell | ok |
| Environment Matrix Generator | bash | sonnet46-200k-medium | 9.8min | 40 | 6 | $0.84 | 3.0 | bash | ok |
| Environment Matrix Generator | bash | opus46-200k-medium | 9.6min | 36 | 1 | $0.87 | 3.0 | bash | ok |
| PR Label Assigner | bash | sonnet46-200k-medium | 6.8min | 39 | 5 | $0.90 | 4.0 | bash | ok |
| Secret Rotation Validator | bash | sonnet46-200k-medium | 11.2min | 31 | 4 | $0.94 | 3.0 | bash | ok |
| PR Label Assigner | typescript-bun | opus46-200k-medium | 9.1min | 31 | 1 | $0.96 | 3.0 | typescript | ok |
| Environment Matrix Generator | default | opus46-200k-medium | 4.6min | 36 | 1 | $0.98 | 2.0 | bash | ok |
| Environment Matrix Generator | powershell | opus46-200k-medium | 6.7min | 44 | 5 | $0.99 | 2.0 | powershell | ok |
| Docker Image Tag Generator | typescript-bun | opus46-200k-medium | 11.1min | 40 | 1 | $1.02 | 3.0 | typescript | ok |
| Docker Image Tag Generator | typescript-bun | sonnet46-200k-medium | 10.2min | 19 | 1 | $1.03 | 4.0 | typescript | ok |
| Secret Rotation Validator | powershell | sonnet46-200k-medium | 12.7min | 22 | 0 | $1.04 | 3.0 | powershell | ok |
| Artifact Cleanup Script | default | opus46-200k-medium | 6.3min | 29 | 0 | $1.05 | 4.0 | python | ok |
| Dependency License Checker | typescript-bun | sonnet46-200k-medium | 7.7min | 47 | 4 | $1.10 | 3.0 | typescript | ok |
| Dependency License Checker | bash | opus46-200k-medium | 5.4min | 40 | 1 | $1.12 | 4.0 | bash | ok |
| PR Label Assigner | powershell | opus46-200k-medium | 8.1min | 32 | 2 | $1.12 | 3.0 | powershell | ok |
| Dependency License Checker | default | sonnet46-200k-medium | 13.5min | 40 | 1 | $1.13 | 4.0 | python | ok |
| Environment Matrix Generator | default | sonnet46-200k-medium | 12.0min | 23 | 0 | $1.13 | 5.0 | python | ok |
| Docker Image Tag Generator | default | sonnet46-200k-medium | 14.6min | 13 | 1 | $1.14 | 4.0 | python | ok |
| Environment Matrix Generator | typescript-bun | opus46-200k-medium | 7.0min | 41 | 4 | $1.15 | 3.0 | typescript | ok |
| Secret Rotation Validator | typescript-bun | opus46-200k-medium | 5.4min | 44 | 5 | $1.17 | 2.0 | typescript | ok |
| Artifact Cleanup Script | typescript-bun | sonnet46-200k-medium | 11.7min | 30 | 1 | $1.18 | 2.0 | typescript | ok |
| Test Results Aggregator | typescript-bun | opus46-200k-medium | 7.1min | 40 | 0 | $1.18 | 3.0 | typescript | ok |
| Secret Rotation Validator | default | opus46-200k-medium | 5.5min | 32 | 1 | $1.19 | 3.0 | python | ok |
| Environment Matrix Generator | typescript-bun | sonnet46-200k-medium | 13.5min | 24 | 0 | $1.19 | 4.0 | typescript | ok |
| PR Label Assigner | bash | opus46-200k-medium | 6.5min | 42 | 2 | $1.22 | 2.0 | bash | ok |
| PR Label Assigner | default | sonnet46-200k-medium | 16.5min | 23 | 1 | $1.25 | 4.0 | python | ok |
| Test Results Aggregator | bash | sonnet46-200k-medium | 12.0min | 43 | 5 | $1.26 | 3.0 | bash | ok |
| Semantic Version Bumper | default | opus46-200k-medium | 9.0min | 29 | 0 | $1.27 | 2.0 | python | ok |
| Secret Rotation Validator | typescript-bun | sonnet46-200k-medium | 13.1min | 1 | 3 | $1.31 | 4.0 | typescript | ok |
| Dependency License Checker | typescript-bun | opus46-200k-medium | 6.2min | 51 | 1 | $1.34 | 4.0 | typescript | ok |
| Docker Image Tag Generator | default | opus46-200k-medium | 7.8min | 36 | 2 | $1.34 | 3.0 | python | ok |
| Secret Rotation Validator | bash | opus46-200k-medium | 11.5min | 33 | 1 | $1.34 | 3.0 | bash | ok |
| Secret Rotation Validator | powershell | opus46-200k-medium | 10.7min | 34 | 0 | $1.35 | 3.0 | powershell | ok |
| PR Label Assigner | typescript-bun | sonnet46-200k-medium | 13.7min | 46 | 6 | $1.35 | 4.0 | typescript | ok |
| Test Results Aggregator | bash | opus46-200k-medium | 6.7min | 44 | 3 | $1.36 | 3.0 | bash | ok |
| Test Results Aggregator | default | opus46-200k-medium | 7.6min | 40 | 2 | $1.43 | 3.0 | python | ok |
| Semantic Version Bumper | powershell | sonnet46-200k-medium | 27.2min | 42 | 0 | $1.44 | 3.0 | powershell | ok |
| Semantic Version Bumper | bash | opus46-200k-medium | 6.8min | 46 | 2 | $1.45 | 3.0 | bash | ok |
| Docker Image Tag Generator | bash | sonnet46-200k-medium | 16.0min | 34 | 4 | $1.49 | 4.0 | bash | ok |
| Artifact Cleanup Script | default | sonnet46-200k-medium | 15.9min | 25 | 1 | $1.49 | 4.0 | python | ok |
| Artifact Cleanup Script | bash | opus46-200k-medium | 8.1min | 38 | 2 | $1.51 | 3.0 | bash | ok |
| Secret Rotation Validator | default | sonnet46-200k-medium | 11.5min | 37 | 2 | $1.53 | 5.0 | python | ok |
| Dependency License Checker | powershell | opus46-200k-medium | 11.1min | 38 | 1 | $1.55 | 3.0 | powershell | ok |
| Test Results Aggregator | powershell | opus46-200k-medium | 9.8min | 31 | 1 | $1.58 | 3.0 | powershell | ok |
| Artifact Cleanup Script | bash | sonnet46-200k-medium | 15.4min | 47 | 3 | $1.59 | 4.0 | bash | ok |
| Artifact Cleanup Script | powershell | opus46-200k-medium | 9.4min | 39 | 0 | $1.60 | 4.0 | powershell | ok |
| Semantic Version Bumper | default | sonnet46-200k-medium | 17.2min | 38 | 1 | $1.62 | 4.0 | python | ok |
| Test Results Aggregator | powershell | sonnet46-200k-medium | 19.9min | 43 | 0 | $1.77 | 4.0 | powershell | ok |
| Test Results Aggregator | default | sonnet46-200k-medium | 15.9min | 58 | 2 | $1.78 | 4.0 | python | ok |
| Dependency License Checker | powershell | sonnet46-200k-medium | 28.0min | 59 | 0 | $1.85 | 3.0 | powershell | ok |
| Test Results Aggregator | typescript-bun | sonnet46-200k-medium | 12.2min | 72 | 3 | $1.86 | 3.0 | typescript | ok |
| Semantic Version Bumper | typescript-bun | opus46-200k-medium | 13.2min | 35 | 0 | $1.89 | 3.0 | typescript | ok |
| Environment Matrix Generator | powershell | sonnet46-200k-medium | 22.1min | 42 | 0 | $1.93 | 3.0 | powershell | ok |
| Docker Image Tag Generator | bash | opus46-200k-medium | 14.5min | 33 | 2 | $2.06 | 3.0 | bash | ok |
| Artifact Cleanup Script | typescript-bun | opus46-200k-medium | 12.3min | 30 | 0 | $2.06 | 4.0 | typescript | ok |
| Docker Image Tag Generator | powershell | sonnet46-200k-medium | 24.4min | 51 | 1 | $2.13 | 4.0 | powershell | ok |
| Dependency License Checker | default | opus46-200k-medium | 10.6min | 65 | 4 | $2.35 | 5.0 | python | ok |
| PR Label Assigner | powershell | sonnet46-200k-medium | 27.1min | 50 | 3 | $2.51 | 4.0 | powershell | ok |

</details>

<details>
<summary>Sorted by duration (fastest first)</summary>

| Task | Language | Model | Duration | Turns | Errors | Cost | Tests Quality | Chosen | Status |
|------|----------|-------|----------|-------|--------|------|-----------|--------|--------|
| Environment Matrix Generator | default | opus46-200k-medium | 4.6min | 36 | 1 | $0.98 | 2.0 | bash | ok |
| PR Label Assigner | default | opus46-200k-medium | 4.6min | 23 | 0 | $0.69 | 3.0 | python | ok |
| Semantic Version Bumper | bash | sonnet46-200k-medium | 4.9min | 30 | 2 | $0.68 | 4.0 | bash | ok |
| Secret Rotation Validator | typescript-bun | opus46-200k-medium | 5.4min | 44 | 5 | $1.17 | 2.0 | typescript | ok |
| Dependency License Checker | bash | opus46-200k-medium | 5.4min | 40 | 1 | $1.12 | 4.0 | bash | ok |
| Secret Rotation Validator | default | opus46-200k-medium | 5.5min | 32 | 1 | $1.19 | 3.0 | python | ok |
| Dependency License Checker | bash | sonnet46-200k-medium | 5.6min | 37 | 4 | $0.75 | 2.0 | bash | ok |
| Dependency License Checker | typescript-bun | opus46-200k-medium | 6.2min | 51 | 1 | $1.34 | 4.0 | typescript | ok |
| Artifact Cleanup Script | default | opus46-200k-medium | 6.3min | 29 | 0 | $1.05 | 4.0 | python | ok |
| PR Label Assigner | bash | opus46-200k-medium | 6.5min | 42 | 2 | $1.22 | 2.0 | bash | ok |
| Artifact Cleanup Script | powershell | sonnet46-200k-medium | 6.5min | 31 | 0 | $0.70 | 3.0 | powershell | ok |
| Environment Matrix Generator | powershell | opus46-200k-medium | 6.7min | 44 | 5 | $0.99 | 2.0 | powershell | ok |
| Test Results Aggregator | bash | opus46-200k-medium | 6.7min | 44 | 3 | $1.36 | 3.0 | bash | ok |
| PR Label Assigner | bash | sonnet46-200k-medium | 6.8min | 39 | 5 | $0.90 | 4.0 | bash | ok |
| Semantic Version Bumper | bash | opus46-200k-medium | 6.8min | 46 | 2 | $1.45 | 3.0 | bash | ok |
| Environment Matrix Generator | typescript-bun | opus46-200k-medium | 7.0min | 41 | 4 | $1.15 | 3.0 | typescript | ok |
| Test Results Aggregator | typescript-bun | opus46-200k-medium | 7.1min | 40 | 0 | $1.18 | 3.0 | typescript | ok |
| Docker Image Tag Generator | powershell | opus46-200k-medium | 7.5min | 20 | 1 | $0.61 | 3.0 | powershell | ok |
| Test Results Aggregator | default | opus46-200k-medium | 7.6min | 40 | 2 | $1.43 | 3.0 | python | ok |
| Dependency License Checker | typescript-bun | sonnet46-200k-medium | 7.7min | 47 | 4 | $1.10 | 3.0 | typescript | ok |
| Docker Image Tag Generator | default | opus46-200k-medium | 7.8min | 36 | 2 | $1.34 | 3.0 | python | ok |
| Semantic Version Bumper | typescript-bun | sonnet46-200k-medium | 8.1min | 28 | 0 | $0.72 | 3.0 | typescript | ok |
| Artifact Cleanup Script | bash | opus46-200k-medium | 8.1min | 38 | 2 | $1.51 | 3.0 | bash | ok |
| PR Label Assigner | powershell | opus46-200k-medium | 8.1min | 32 | 2 | $1.12 | 3.0 | powershell | ok |
| Semantic Version Bumper | default | opus46-200k-medium | 9.0min | 29 | 0 | $1.27 | 2.0 | python | ok |
| PR Label Assigner | typescript-bun | opus46-200k-medium | 9.1min | 31 | 1 | $0.96 | 3.0 | typescript | ok |
| Semantic Version Bumper | powershell | opus46-200k-medium | 9.2min | 31 | 0 | $0.82 | 2.0 | powershell | ok |
| Artifact Cleanup Script | powershell | opus46-200k-medium | 9.4min | 39 | 0 | $1.60 | 4.0 | powershell | ok |
| Environment Matrix Generator | bash | opus46-200k-medium | 9.6min | 36 | 1 | $0.87 | 3.0 | bash | ok |
| Environment Matrix Generator | bash | sonnet46-200k-medium | 9.8min | 40 | 6 | $0.84 | 3.0 | bash | ok |
| Test Results Aggregator | powershell | opus46-200k-medium | 9.8min | 31 | 1 | $1.58 | 3.0 | powershell | ok |
| Docker Image Tag Generator | typescript-bun | sonnet46-200k-medium | 10.2min | 19 | 1 | $1.03 | 4.0 | typescript | ok |
| Dependency License Checker | default | opus46-200k-medium | 10.6min | 65 | 4 | $2.35 | 5.0 | python | ok |
| Secret Rotation Validator | powershell | opus46-200k-medium | 10.7min | 34 | 0 | $1.35 | 3.0 | powershell | ok |
| Dependency License Checker | powershell | opus46-200k-medium | 11.1min | 38 | 1 | $1.55 | 3.0 | powershell | ok |
| Docker Image Tag Generator | typescript-bun | opus46-200k-medium | 11.1min | 40 | 1 | $1.02 | 3.0 | typescript | ok |
| Secret Rotation Validator | bash | sonnet46-200k-medium | 11.2min | 31 | 4 | $0.94 | 3.0 | bash | ok |
| Secret Rotation Validator | bash | opus46-200k-medium | 11.5min | 33 | 1 | $1.34 | 3.0 | bash | ok |
| Secret Rotation Validator | default | sonnet46-200k-medium | 11.5min | 37 | 2 | $1.53 | 5.0 | python | ok |
| Artifact Cleanup Script | typescript-bun | sonnet46-200k-medium | 11.7min | 30 | 1 | $1.18 | 2.0 | typescript | ok |
| Test Results Aggregator | bash | sonnet46-200k-medium | 12.0min | 43 | 5 | $1.26 | 3.0 | bash | ok |
| Environment Matrix Generator | default | sonnet46-200k-medium | 12.0min | 23 | 0 | $1.13 | 5.0 | python | ok |
| Test Results Aggregator | typescript-bun | sonnet46-200k-medium | 12.2min | 72 | 3 | $1.86 | 3.0 | typescript | ok |
| Artifact Cleanup Script | typescript-bun | opus46-200k-medium | 12.3min | 30 | 0 | $2.06 | 4.0 | typescript | ok |
| Secret Rotation Validator | powershell | sonnet46-200k-medium | 12.7min | 22 | 0 | $1.04 | 3.0 | powershell | ok |
| Secret Rotation Validator | typescript-bun | sonnet46-200k-medium | 13.1min | 1 | 3 | $1.31 | 4.0 | typescript | ok |
| Semantic Version Bumper | typescript-bun | opus46-200k-medium | 13.2min | 35 | 0 | $1.89 | 3.0 | typescript | ok |
| Environment Matrix Generator | typescript-bun | sonnet46-200k-medium | 13.5min | 24 | 0 | $1.19 | 4.0 | typescript | ok |
| Dependency License Checker | default | sonnet46-200k-medium | 13.5min | 40 | 1 | $1.13 | 4.0 | python | ok |
| PR Label Assigner | typescript-bun | sonnet46-200k-medium | 13.7min | 46 | 6 | $1.35 | 4.0 | typescript | ok |
| Docker Image Tag Generator | bash | opus46-200k-medium | 14.5min | 33 | 2 | $2.06 | 3.0 | bash | ok |
| Docker Image Tag Generator | default | sonnet46-200k-medium | 14.6min | 13 | 1 | $1.14 | 4.0 | python | ok |
| Artifact Cleanup Script | bash | sonnet46-200k-medium | 15.4min | 47 | 3 | $1.59 | 4.0 | bash | ok |
| Test Results Aggregator | default | sonnet46-200k-medium | 15.9min | 58 | 2 | $1.78 | 4.0 | python | ok |
| Artifact Cleanup Script | default | sonnet46-200k-medium | 15.9min | 25 | 1 | $1.49 | 4.0 | python | ok |
| Docker Image Tag Generator | bash | sonnet46-200k-medium | 16.0min | 34 | 4 | $1.49 | 4.0 | bash | ok |
| PR Label Assigner | default | sonnet46-200k-medium | 16.5min | 23 | 1 | $1.25 | 4.0 | python | ok |
| Semantic Version Bumper | default | sonnet46-200k-medium | 17.2min | 38 | 1 | $1.62 | 4.0 | python | ok |
| Test Results Aggregator | powershell | sonnet46-200k-medium | 19.9min | 43 | 0 | $1.77 | 4.0 | powershell | ok |
| Environment Matrix Generator | powershell | sonnet46-200k-medium | 22.1min | 42 | 0 | $1.93 | 3.0 | powershell | ok |
| Docker Image Tag Generator | powershell | sonnet46-200k-medium | 24.4min | 51 | 1 | $2.13 | 4.0 | powershell | ok |
| PR Label Assigner | powershell | sonnet46-200k-medium | 27.1min | 50 | 3 | $2.51 | 4.0 | powershell | ok |
| Semantic Version Bumper | powershell | sonnet46-200k-medium | 27.2min | 42 | 0 | $1.44 | 3.0 | powershell | ok |
| Dependency License Checker | powershell | sonnet46-200k-medium | 28.0min | 59 | 0 | $1.85 | 3.0 | powershell | ok |

</details>

<details>
<summary>Sorted by errors (fewest first)</summary>

| Task | Language | Model | Duration | Turns | Errors | Cost | Tests Quality | Chosen | Status |
|------|----------|-------|----------|-------|--------|------|-----------|--------|--------|
| Semantic Version Bumper | default | opus46-200k-medium | 9.0min | 29 | 0 | $1.27 | 2.0 | python | ok |
| Semantic Version Bumper | powershell | opus46-200k-medium | 9.2min | 31 | 0 | $0.82 | 2.0 | powershell | ok |
| Semantic Version Bumper | powershell | sonnet46-200k-medium | 27.2min | 42 | 0 | $1.44 | 3.0 | powershell | ok |
| Semantic Version Bumper | typescript-bun | opus46-200k-medium | 13.2min | 35 | 0 | $1.89 | 3.0 | typescript | ok |
| Semantic Version Bumper | typescript-bun | sonnet46-200k-medium | 8.1min | 28 | 0 | $0.72 | 3.0 | typescript | ok |
| PR Label Assigner | default | opus46-200k-medium | 4.6min | 23 | 0 | $0.69 | 3.0 | python | ok |
| Dependency License Checker | powershell | sonnet46-200k-medium | 28.0min | 59 | 0 | $1.85 | 3.0 | powershell | ok |
| Test Results Aggregator | powershell | sonnet46-200k-medium | 19.9min | 43 | 0 | $1.77 | 4.0 | powershell | ok |
| Test Results Aggregator | typescript-bun | opus46-200k-medium | 7.1min | 40 | 0 | $1.18 | 3.0 | typescript | ok |
| Environment Matrix Generator | default | sonnet46-200k-medium | 12.0min | 23 | 0 | $1.13 | 5.0 | python | ok |
| Environment Matrix Generator | powershell | sonnet46-200k-medium | 22.1min | 42 | 0 | $1.93 | 3.0 | powershell | ok |
| Environment Matrix Generator | typescript-bun | sonnet46-200k-medium | 13.5min | 24 | 0 | $1.19 | 4.0 | typescript | ok |
| Artifact Cleanup Script | default | opus46-200k-medium | 6.3min | 29 | 0 | $1.05 | 4.0 | python | ok |
| Artifact Cleanup Script | powershell | opus46-200k-medium | 9.4min | 39 | 0 | $1.60 | 4.0 | powershell | ok |
| Artifact Cleanup Script | powershell | sonnet46-200k-medium | 6.5min | 31 | 0 | $0.70 | 3.0 | powershell | ok |
| Artifact Cleanup Script | typescript-bun | opus46-200k-medium | 12.3min | 30 | 0 | $2.06 | 4.0 | typescript | ok |
| Secret Rotation Validator | powershell | opus46-200k-medium | 10.7min | 34 | 0 | $1.35 | 3.0 | powershell | ok |
| Secret Rotation Validator | powershell | sonnet46-200k-medium | 12.7min | 22 | 0 | $1.04 | 3.0 | powershell | ok |
| Semantic Version Bumper | default | sonnet46-200k-medium | 17.2min | 38 | 1 | $1.62 | 4.0 | python | ok |
| PR Label Assigner | default | sonnet46-200k-medium | 16.5min | 23 | 1 | $1.25 | 4.0 | python | ok |
| PR Label Assigner | typescript-bun | opus46-200k-medium | 9.1min | 31 | 1 | $0.96 | 3.0 | typescript | ok |
| Dependency License Checker | bash | opus46-200k-medium | 5.4min | 40 | 1 | $1.12 | 4.0 | bash | ok |
| Dependency License Checker | default | sonnet46-200k-medium | 13.5min | 40 | 1 | $1.13 | 4.0 | python | ok |
| Dependency License Checker | powershell | opus46-200k-medium | 11.1min | 38 | 1 | $1.55 | 3.0 | powershell | ok |
| Dependency License Checker | typescript-bun | opus46-200k-medium | 6.2min | 51 | 1 | $1.34 | 4.0 | typescript | ok |
| Docker Image Tag Generator | default | sonnet46-200k-medium | 14.6min | 13 | 1 | $1.14 | 4.0 | python | ok |
| Docker Image Tag Generator | powershell | opus46-200k-medium | 7.5min | 20 | 1 | $0.61 | 3.0 | powershell | ok |
| Docker Image Tag Generator | powershell | sonnet46-200k-medium | 24.4min | 51 | 1 | $2.13 | 4.0 | powershell | ok |
| Docker Image Tag Generator | typescript-bun | opus46-200k-medium | 11.1min | 40 | 1 | $1.02 | 3.0 | typescript | ok |
| Docker Image Tag Generator | typescript-bun | sonnet46-200k-medium | 10.2min | 19 | 1 | $1.03 | 4.0 | typescript | ok |
| Test Results Aggregator | powershell | opus46-200k-medium | 9.8min | 31 | 1 | $1.58 | 3.0 | powershell | ok |
| Environment Matrix Generator | bash | opus46-200k-medium | 9.6min | 36 | 1 | $0.87 | 3.0 | bash | ok |
| Environment Matrix Generator | default | opus46-200k-medium | 4.6min | 36 | 1 | $0.98 | 2.0 | bash | ok |
| Artifact Cleanup Script | default | sonnet46-200k-medium | 15.9min | 25 | 1 | $1.49 | 4.0 | python | ok |
| Artifact Cleanup Script | typescript-bun | sonnet46-200k-medium | 11.7min | 30 | 1 | $1.18 | 2.0 | typescript | ok |
| Secret Rotation Validator | bash | opus46-200k-medium | 11.5min | 33 | 1 | $1.34 | 3.0 | bash | ok |
| Secret Rotation Validator | default | opus46-200k-medium | 5.5min | 32 | 1 | $1.19 | 3.0 | python | ok |
| Semantic Version Bumper | bash | opus46-200k-medium | 6.8min | 46 | 2 | $1.45 | 3.0 | bash | ok |
| Semantic Version Bumper | bash | sonnet46-200k-medium | 4.9min | 30 | 2 | $0.68 | 4.0 | bash | ok |
| PR Label Assigner | bash | opus46-200k-medium | 6.5min | 42 | 2 | $1.22 | 2.0 | bash | ok |
| PR Label Assigner | powershell | opus46-200k-medium | 8.1min | 32 | 2 | $1.12 | 3.0 | powershell | ok |
| Docker Image Tag Generator | bash | opus46-200k-medium | 14.5min | 33 | 2 | $2.06 | 3.0 | bash | ok |
| Docker Image Tag Generator | default | opus46-200k-medium | 7.8min | 36 | 2 | $1.34 | 3.0 | python | ok |
| Test Results Aggregator | default | opus46-200k-medium | 7.6min | 40 | 2 | $1.43 | 3.0 | python | ok |
| Test Results Aggregator | default | sonnet46-200k-medium | 15.9min | 58 | 2 | $1.78 | 4.0 | python | ok |
| Artifact Cleanup Script | bash | opus46-200k-medium | 8.1min | 38 | 2 | $1.51 | 3.0 | bash | ok |
| Secret Rotation Validator | default | sonnet46-200k-medium | 11.5min | 37 | 2 | $1.53 | 5.0 | python | ok |
| PR Label Assigner | powershell | sonnet46-200k-medium | 27.1min | 50 | 3 | $2.51 | 4.0 | powershell | ok |
| Test Results Aggregator | bash | opus46-200k-medium | 6.7min | 44 | 3 | $1.36 | 3.0 | bash | ok |
| Test Results Aggregator | typescript-bun | sonnet46-200k-medium | 12.2min | 72 | 3 | $1.86 | 3.0 | typescript | ok |
| Artifact Cleanup Script | bash | sonnet46-200k-medium | 15.4min | 47 | 3 | $1.59 | 4.0 | bash | ok |
| Secret Rotation Validator | typescript-bun | sonnet46-200k-medium | 13.1min | 1 | 3 | $1.31 | 4.0 | typescript | ok |
| Dependency License Checker | bash | sonnet46-200k-medium | 5.6min | 37 | 4 | $0.75 | 2.0 | bash | ok |
| Dependency License Checker | default | opus46-200k-medium | 10.6min | 65 | 4 | $2.35 | 5.0 | python | ok |
| Dependency License Checker | typescript-bun | sonnet46-200k-medium | 7.7min | 47 | 4 | $1.10 | 3.0 | typescript | ok |
| Docker Image Tag Generator | bash | sonnet46-200k-medium | 16.0min | 34 | 4 | $1.49 | 4.0 | bash | ok |
| Environment Matrix Generator | typescript-bun | opus46-200k-medium | 7.0min | 41 | 4 | $1.15 | 3.0 | typescript | ok |
| Secret Rotation Validator | bash | sonnet46-200k-medium | 11.2min | 31 | 4 | $0.94 | 3.0 | bash | ok |
| PR Label Assigner | bash | sonnet46-200k-medium | 6.8min | 39 | 5 | $0.90 | 4.0 | bash | ok |
| Test Results Aggregator | bash | sonnet46-200k-medium | 12.0min | 43 | 5 | $1.26 | 3.0 | bash | ok |
| Environment Matrix Generator | powershell | opus46-200k-medium | 6.7min | 44 | 5 | $0.99 | 2.0 | powershell | ok |
| Secret Rotation Validator | typescript-bun | opus46-200k-medium | 5.4min | 44 | 5 | $1.17 | 2.0 | typescript | ok |
| PR Label Assigner | typescript-bun | sonnet46-200k-medium | 13.7min | 46 | 6 | $1.35 | 4.0 | typescript | ok |
| Environment Matrix Generator | bash | sonnet46-200k-medium | 9.8min | 40 | 6 | $0.84 | 3.0 | bash | ok |

</details>

<details>
<summary>Sorted by turns (fewest first)</summary>

| Task | Language | Model | Duration | Turns | Errors | Cost | Tests Quality | Chosen | Status |
|------|----------|-------|----------|-------|--------|------|-----------|--------|--------|
| Secret Rotation Validator | typescript-bun | sonnet46-200k-medium | 13.1min | 1 | 3 | $1.31 | 4.0 | typescript | ok |
| Docker Image Tag Generator | default | sonnet46-200k-medium | 14.6min | 13 | 1 | $1.14 | 4.0 | python | ok |
| Docker Image Tag Generator | typescript-bun | sonnet46-200k-medium | 10.2min | 19 | 1 | $1.03 | 4.0 | typescript | ok |
| Docker Image Tag Generator | powershell | opus46-200k-medium | 7.5min | 20 | 1 | $0.61 | 3.0 | powershell | ok |
| Secret Rotation Validator | powershell | sonnet46-200k-medium | 12.7min | 22 | 0 | $1.04 | 3.0 | powershell | ok |
| PR Label Assigner | default | opus46-200k-medium | 4.6min | 23 | 0 | $0.69 | 3.0 | python | ok |
| PR Label Assigner | default | sonnet46-200k-medium | 16.5min | 23 | 1 | $1.25 | 4.0 | python | ok |
| Environment Matrix Generator | default | sonnet46-200k-medium | 12.0min | 23 | 0 | $1.13 | 5.0 | python | ok |
| Environment Matrix Generator | typescript-bun | sonnet46-200k-medium | 13.5min | 24 | 0 | $1.19 | 4.0 | typescript | ok |
| Artifact Cleanup Script | default | sonnet46-200k-medium | 15.9min | 25 | 1 | $1.49 | 4.0 | python | ok |
| Semantic Version Bumper | typescript-bun | sonnet46-200k-medium | 8.1min | 28 | 0 | $0.72 | 3.0 | typescript | ok |
| Semantic Version Bumper | default | opus46-200k-medium | 9.0min | 29 | 0 | $1.27 | 2.0 | python | ok |
| Artifact Cleanup Script | default | opus46-200k-medium | 6.3min | 29 | 0 | $1.05 | 4.0 | python | ok |
| Semantic Version Bumper | bash | sonnet46-200k-medium | 4.9min | 30 | 2 | $0.68 | 4.0 | bash | ok |
| Artifact Cleanup Script | typescript-bun | opus46-200k-medium | 12.3min | 30 | 0 | $2.06 | 4.0 | typescript | ok |
| Artifact Cleanup Script | typescript-bun | sonnet46-200k-medium | 11.7min | 30 | 1 | $1.18 | 2.0 | typescript | ok |
| Semantic Version Bumper | powershell | opus46-200k-medium | 9.2min | 31 | 0 | $0.82 | 2.0 | powershell | ok |
| PR Label Assigner | typescript-bun | opus46-200k-medium | 9.1min | 31 | 1 | $0.96 | 3.0 | typescript | ok |
| Test Results Aggregator | powershell | opus46-200k-medium | 9.8min | 31 | 1 | $1.58 | 3.0 | powershell | ok |
| Artifact Cleanup Script | powershell | sonnet46-200k-medium | 6.5min | 31 | 0 | $0.70 | 3.0 | powershell | ok |
| Secret Rotation Validator | bash | sonnet46-200k-medium | 11.2min | 31 | 4 | $0.94 | 3.0 | bash | ok |
| PR Label Assigner | powershell | opus46-200k-medium | 8.1min | 32 | 2 | $1.12 | 3.0 | powershell | ok |
| Secret Rotation Validator | default | opus46-200k-medium | 5.5min | 32 | 1 | $1.19 | 3.0 | python | ok |
| Docker Image Tag Generator | bash | opus46-200k-medium | 14.5min | 33 | 2 | $2.06 | 3.0 | bash | ok |
| Secret Rotation Validator | bash | opus46-200k-medium | 11.5min | 33 | 1 | $1.34 | 3.0 | bash | ok |
| Docker Image Tag Generator | bash | sonnet46-200k-medium | 16.0min | 34 | 4 | $1.49 | 4.0 | bash | ok |
| Secret Rotation Validator | powershell | opus46-200k-medium | 10.7min | 34 | 0 | $1.35 | 3.0 | powershell | ok |
| Semantic Version Bumper | typescript-bun | opus46-200k-medium | 13.2min | 35 | 0 | $1.89 | 3.0 | typescript | ok |
| Docker Image Tag Generator | default | opus46-200k-medium | 7.8min | 36 | 2 | $1.34 | 3.0 | python | ok |
| Environment Matrix Generator | bash | opus46-200k-medium | 9.6min | 36 | 1 | $0.87 | 3.0 | bash | ok |
| Environment Matrix Generator | default | opus46-200k-medium | 4.6min | 36 | 1 | $0.98 | 2.0 | bash | ok |
| Dependency License Checker | bash | sonnet46-200k-medium | 5.6min | 37 | 4 | $0.75 | 2.0 | bash | ok |
| Secret Rotation Validator | default | sonnet46-200k-medium | 11.5min | 37 | 2 | $1.53 | 5.0 | python | ok |
| Semantic Version Bumper | default | sonnet46-200k-medium | 17.2min | 38 | 1 | $1.62 | 4.0 | python | ok |
| Dependency License Checker | powershell | opus46-200k-medium | 11.1min | 38 | 1 | $1.55 | 3.0 | powershell | ok |
| Artifact Cleanup Script | bash | opus46-200k-medium | 8.1min | 38 | 2 | $1.51 | 3.0 | bash | ok |
| PR Label Assigner | bash | sonnet46-200k-medium | 6.8min | 39 | 5 | $0.90 | 4.0 | bash | ok |
| Artifact Cleanup Script | powershell | opus46-200k-medium | 9.4min | 39 | 0 | $1.60 | 4.0 | powershell | ok |
| Dependency License Checker | bash | opus46-200k-medium | 5.4min | 40 | 1 | $1.12 | 4.0 | bash | ok |
| Dependency License Checker | default | sonnet46-200k-medium | 13.5min | 40 | 1 | $1.13 | 4.0 | python | ok |
| Docker Image Tag Generator | typescript-bun | opus46-200k-medium | 11.1min | 40 | 1 | $1.02 | 3.0 | typescript | ok |
| Test Results Aggregator | default | opus46-200k-medium | 7.6min | 40 | 2 | $1.43 | 3.0 | python | ok |
| Test Results Aggregator | typescript-bun | opus46-200k-medium | 7.1min | 40 | 0 | $1.18 | 3.0 | typescript | ok |
| Environment Matrix Generator | bash | sonnet46-200k-medium | 9.8min | 40 | 6 | $0.84 | 3.0 | bash | ok |
| Environment Matrix Generator | typescript-bun | opus46-200k-medium | 7.0min | 41 | 4 | $1.15 | 3.0 | typescript | ok |
| Semantic Version Bumper | powershell | sonnet46-200k-medium | 27.2min | 42 | 0 | $1.44 | 3.0 | powershell | ok |
| PR Label Assigner | bash | opus46-200k-medium | 6.5min | 42 | 2 | $1.22 | 2.0 | bash | ok |
| Environment Matrix Generator | powershell | sonnet46-200k-medium | 22.1min | 42 | 0 | $1.93 | 3.0 | powershell | ok |
| Test Results Aggregator | bash | sonnet46-200k-medium | 12.0min | 43 | 5 | $1.26 | 3.0 | bash | ok |
| Test Results Aggregator | powershell | sonnet46-200k-medium | 19.9min | 43 | 0 | $1.77 | 4.0 | powershell | ok |
| Test Results Aggregator | bash | opus46-200k-medium | 6.7min | 44 | 3 | $1.36 | 3.0 | bash | ok |
| Environment Matrix Generator | powershell | opus46-200k-medium | 6.7min | 44 | 5 | $0.99 | 2.0 | powershell | ok |
| Secret Rotation Validator | typescript-bun | opus46-200k-medium | 5.4min | 44 | 5 | $1.17 | 2.0 | typescript | ok |
| Semantic Version Bumper | bash | opus46-200k-medium | 6.8min | 46 | 2 | $1.45 | 3.0 | bash | ok |
| PR Label Assigner | typescript-bun | sonnet46-200k-medium | 13.7min | 46 | 6 | $1.35 | 4.0 | typescript | ok |
| Dependency License Checker | typescript-bun | sonnet46-200k-medium | 7.7min | 47 | 4 | $1.10 | 3.0 | typescript | ok |
| Artifact Cleanup Script | bash | sonnet46-200k-medium | 15.4min | 47 | 3 | $1.59 | 4.0 | bash | ok |
| PR Label Assigner | powershell | sonnet46-200k-medium | 27.1min | 50 | 3 | $2.51 | 4.0 | powershell | ok |
| Dependency License Checker | typescript-bun | opus46-200k-medium | 6.2min | 51 | 1 | $1.34 | 4.0 | typescript | ok |
| Docker Image Tag Generator | powershell | sonnet46-200k-medium | 24.4min | 51 | 1 | $2.13 | 4.0 | powershell | ok |
| Test Results Aggregator | default | sonnet46-200k-medium | 15.9min | 58 | 2 | $1.78 | 4.0 | python | ok |
| Dependency License Checker | powershell | sonnet46-200k-medium | 28.0min | 59 | 0 | $1.85 | 3.0 | powershell | ok |
| Dependency License Checker | default | opus46-200k-medium | 10.6min | 65 | 4 | $2.35 | 5.0 | python | ok |
| Test Results Aggregator | typescript-bun | sonnet46-200k-medium | 12.2min | 72 | 3 | $1.86 | 3.0 | typescript | ok |

</details>

<details>
<summary>Sorted by LLM-as-judge score (best first)</summary>

| Task | Language | Model | Duration | Turns | Errors | Cost | Tests Quality | Chosen | Status |
|------|----------|-------|----------|-------|--------|------|-----------|--------|--------|
| Dependency License Checker | default | opus46-200k-medium | 10.6min | 65 | 4 | $2.35 | 5.0 | python | ok |
| Environment Matrix Generator | default | sonnet46-200k-medium | 12.0min | 23 | 0 | $1.13 | 5.0 | python | ok |
| Secret Rotation Validator | default | sonnet46-200k-medium | 11.5min | 37 | 2 | $1.53 | 5.0 | python | ok |
| Semantic Version Bumper | bash | sonnet46-200k-medium | 4.9min | 30 | 2 | $0.68 | 4.0 | bash | ok |
| Semantic Version Bumper | default | sonnet46-200k-medium | 17.2min | 38 | 1 | $1.62 | 4.0 | python | ok |
| PR Label Assigner | bash | sonnet46-200k-medium | 6.8min | 39 | 5 | $0.90 | 4.0 | bash | ok |
| PR Label Assigner | default | sonnet46-200k-medium | 16.5min | 23 | 1 | $1.25 | 4.0 | python | ok |
| PR Label Assigner | powershell | sonnet46-200k-medium | 27.1min | 50 | 3 | $2.51 | 4.0 | powershell | ok |
| PR Label Assigner | typescript-bun | sonnet46-200k-medium | 13.7min | 46 | 6 | $1.35 | 4.0 | typescript | ok |
| Dependency License Checker | bash | opus46-200k-medium | 5.4min | 40 | 1 | $1.12 | 4.0 | bash | ok |
| Dependency License Checker | default | sonnet46-200k-medium | 13.5min | 40 | 1 | $1.13 | 4.0 | python | ok |
| Dependency License Checker | typescript-bun | opus46-200k-medium | 6.2min | 51 | 1 | $1.34 | 4.0 | typescript | ok |
| Docker Image Tag Generator | bash | sonnet46-200k-medium | 16.0min | 34 | 4 | $1.49 | 4.0 | bash | ok |
| Docker Image Tag Generator | default | sonnet46-200k-medium | 14.6min | 13 | 1 | $1.14 | 4.0 | python | ok |
| Docker Image Tag Generator | powershell | sonnet46-200k-medium | 24.4min | 51 | 1 | $2.13 | 4.0 | powershell | ok |
| Docker Image Tag Generator | typescript-bun | sonnet46-200k-medium | 10.2min | 19 | 1 | $1.03 | 4.0 | typescript | ok |
| Test Results Aggregator | default | sonnet46-200k-medium | 15.9min | 58 | 2 | $1.78 | 4.0 | python | ok |
| Test Results Aggregator | powershell | sonnet46-200k-medium | 19.9min | 43 | 0 | $1.77 | 4.0 | powershell | ok |
| Environment Matrix Generator | typescript-bun | sonnet46-200k-medium | 13.5min | 24 | 0 | $1.19 | 4.0 | typescript | ok |
| Artifact Cleanup Script | bash | sonnet46-200k-medium | 15.4min | 47 | 3 | $1.59 | 4.0 | bash | ok |
| Artifact Cleanup Script | default | opus46-200k-medium | 6.3min | 29 | 0 | $1.05 | 4.0 | python | ok |
| Artifact Cleanup Script | default | sonnet46-200k-medium | 15.9min | 25 | 1 | $1.49 | 4.0 | python | ok |
| Artifact Cleanup Script | powershell | opus46-200k-medium | 9.4min | 39 | 0 | $1.60 | 4.0 | powershell | ok |
| Artifact Cleanup Script | typescript-bun | opus46-200k-medium | 12.3min | 30 | 0 | $2.06 | 4.0 | typescript | ok |
| Secret Rotation Validator | typescript-bun | sonnet46-200k-medium | 13.1min | 1 | 3 | $1.31 | 4.0 | typescript | ok |
| Semantic Version Bumper | bash | opus46-200k-medium | 6.8min | 46 | 2 | $1.45 | 3.0 | bash | ok |
| Semantic Version Bumper | powershell | sonnet46-200k-medium | 27.2min | 42 | 0 | $1.44 | 3.0 | powershell | ok |
| Semantic Version Bumper | typescript-bun | opus46-200k-medium | 13.2min | 35 | 0 | $1.89 | 3.0 | typescript | ok |
| Semantic Version Bumper | typescript-bun | sonnet46-200k-medium | 8.1min | 28 | 0 | $0.72 | 3.0 | typescript | ok |
| PR Label Assigner | default | opus46-200k-medium | 4.6min | 23 | 0 | $0.69 | 3.0 | python | ok |
| PR Label Assigner | powershell | opus46-200k-medium | 8.1min | 32 | 2 | $1.12 | 3.0 | powershell | ok |
| PR Label Assigner | typescript-bun | opus46-200k-medium | 9.1min | 31 | 1 | $0.96 | 3.0 | typescript | ok |
| Dependency License Checker | powershell | opus46-200k-medium | 11.1min | 38 | 1 | $1.55 | 3.0 | powershell | ok |
| Dependency License Checker | powershell | sonnet46-200k-medium | 28.0min | 59 | 0 | $1.85 | 3.0 | powershell | ok |
| Dependency License Checker | typescript-bun | sonnet46-200k-medium | 7.7min | 47 | 4 | $1.10 | 3.0 | typescript | ok |
| Docker Image Tag Generator | bash | opus46-200k-medium | 14.5min | 33 | 2 | $2.06 | 3.0 | bash | ok |
| Docker Image Tag Generator | default | opus46-200k-medium | 7.8min | 36 | 2 | $1.34 | 3.0 | python | ok |
| Docker Image Tag Generator | powershell | opus46-200k-medium | 7.5min | 20 | 1 | $0.61 | 3.0 | powershell | ok |
| Docker Image Tag Generator | typescript-bun | opus46-200k-medium | 11.1min | 40 | 1 | $1.02 | 3.0 | typescript | ok |
| Test Results Aggregator | bash | opus46-200k-medium | 6.7min | 44 | 3 | $1.36 | 3.0 | bash | ok |
| Test Results Aggregator | bash | sonnet46-200k-medium | 12.0min | 43 | 5 | $1.26 | 3.0 | bash | ok |
| Test Results Aggregator | default | opus46-200k-medium | 7.6min | 40 | 2 | $1.43 | 3.0 | python | ok |
| Test Results Aggregator | powershell | opus46-200k-medium | 9.8min | 31 | 1 | $1.58 | 3.0 | powershell | ok |
| Test Results Aggregator | typescript-bun | opus46-200k-medium | 7.1min | 40 | 0 | $1.18 | 3.0 | typescript | ok |
| Test Results Aggregator | typescript-bun | sonnet46-200k-medium | 12.2min | 72 | 3 | $1.86 | 3.0 | typescript | ok |
| Environment Matrix Generator | bash | opus46-200k-medium | 9.6min | 36 | 1 | $0.87 | 3.0 | bash | ok |
| Environment Matrix Generator | bash | sonnet46-200k-medium | 9.8min | 40 | 6 | $0.84 | 3.0 | bash | ok |
| Environment Matrix Generator | powershell | sonnet46-200k-medium | 22.1min | 42 | 0 | $1.93 | 3.0 | powershell | ok |
| Environment Matrix Generator | typescript-bun | opus46-200k-medium | 7.0min | 41 | 4 | $1.15 | 3.0 | typescript | ok |
| Artifact Cleanup Script | bash | opus46-200k-medium | 8.1min | 38 | 2 | $1.51 | 3.0 | bash | ok |
| Artifact Cleanup Script | powershell | sonnet46-200k-medium | 6.5min | 31 | 0 | $0.70 | 3.0 | powershell | ok |
| Secret Rotation Validator | bash | opus46-200k-medium | 11.5min | 33 | 1 | $1.34 | 3.0 | bash | ok |
| Secret Rotation Validator | bash | sonnet46-200k-medium | 11.2min | 31 | 4 | $0.94 | 3.0 | bash | ok |
| Secret Rotation Validator | default | opus46-200k-medium | 5.5min | 32 | 1 | $1.19 | 3.0 | python | ok |
| Secret Rotation Validator | powershell | opus46-200k-medium | 10.7min | 34 | 0 | $1.35 | 3.0 | powershell | ok |
| Secret Rotation Validator | powershell | sonnet46-200k-medium | 12.7min | 22 | 0 | $1.04 | 3.0 | powershell | ok |
| Semantic Version Bumper | default | opus46-200k-medium | 9.0min | 29 | 0 | $1.27 | 2.0 | python | ok |
| Semantic Version Bumper | powershell | opus46-200k-medium | 9.2min | 31 | 0 | $0.82 | 2.0 | powershell | ok |
| PR Label Assigner | bash | opus46-200k-medium | 6.5min | 42 | 2 | $1.22 | 2.0 | bash | ok |
| Dependency License Checker | bash | sonnet46-200k-medium | 5.6min | 37 | 4 | $0.75 | 2.0 | bash | ok |
| Environment Matrix Generator | default | opus46-200k-medium | 4.6min | 36 | 1 | $0.98 | 2.0 | bash | ok |
| Environment Matrix Generator | powershell | opus46-200k-medium | 6.7min | 44 | 5 | $0.99 | 2.0 | powershell | ok |
| Artifact Cleanup Script | typescript-bun | sonnet46-200k-medium | 11.7min | 30 | 1 | $1.18 | 2.0 | typescript | ok |
| Secret Rotation Validator | typescript-bun | opus46-200k-medium | 5.4min | 44 | 5 | $1.17 | 2.0 | typescript | ok |

</details>

## Notes

### Tiers

- **Duration bands:** **A+** ≤1.09×, **A** ≤1.19×, **A-** ≤1.30×, **B+** ≤1.42×, **B** ≤1.55×, **B-** ≤1.69×, **C+** ≤1.84×, **C** ≤2.01×, **C-** ≤2.19×, **D+** ≤2.39×, **D** ≤2.61×, **D-** ≤2.85×, **F** >2.85×
- **Cost bands:** **A+** ≤1.04×, **A** ≤1.08×, **A-** ≤1.12×, **B+** ≤1.16×, **B** ≤1.20×, **B-** ≤1.24×, **C+** ≤1.29×, **C** ≤1.34×, **C-** ≤1.39×, **D+** ≤1.44×, **D** ≤1.49×, **D-** ≤1.55×, **F** >1.55×

*Tests/Workflow Craft bands are absolute Overall score bands:* **A+** ≥4.7, **A** ≥4.4, **A-** ≥4.1, **B+** ≥3.8, **B** ≥3.5, **B-** ≥3.2, **C+** ≥2.9, **C** ≥2.6, **C-** ≥2.3, **D+** ≥2.0, **D** ≥1.7, **D-** ≥1.4, **F** <1.4, `—` = no data.*

### CLI Version Legend

| Variant label | CLI version | Tasks | Languages |
|---------------|-------------|-------|-----------|
| opus46-200k-medium | 2.1.97 | All | All |
| sonnet46-200k-medium | 2.1.97 | All | All |

---
*Generated by generate_results.py — benchmark instructions v3*