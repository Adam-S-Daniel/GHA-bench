# Benchmark Results: Language Comparison

**Last updated:** 2026-07-02 09:53:17 AM ET — 64/64 runs completed, 0 remaining; total cost $86.90; total agent time 550.6 min.
**Claude Code versions used:** [v2.1.97](claude-code-2.1.97.md) (1 run), [v2.1.98](claude-code-2.1.98.md) (57 runs), [v2.1.100](claude-code-2.1.100.md) (6 runs). Each link goes to a per-version snapshot of the system prompt, default-tool descriptions, and the chronological Anthropic changelog up to that version. Regenerate with `python3 version_docs.py`.

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
  - [LLM-as-Judge Scores](#llm-as-judge-scores)
  - [Correlation: Structural Metrics vs Tests Quality](#correlation-structural-metrics-vs-tests-quality)
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

Every Duration figure in this report derives from `timing.grand_total_duration_ms` in `metrics.json` — wall-clock seconds from CLI invocation to the final assistant turn (agent thinking + tool execution + hooks).

- **Duration** (single run): that one run's wall clock. Appears in the [Failed / Timed-Out Runs](#failed--timed-out-runs) and per-run detail tables.
- **Avg Duration** (in the [Comparison by Language/Model/Effort](#comparison-by-languagemodeleffort) table; also drives the [Tiers](#tiers-by-languagemodeleffort) Duration column): arithmetic mean of `Duration` over the runs in that combo, excluding failed/timed-out runs.
- **Avg Duration Net of Traps** (in the Comparison table only): mean of (per-run `Duration` − that run's `Time Lost`), where `Time Lost` is the trap detector's estimate of seconds spent on detected anti-patterns (see [Trap Descriptions](#trap-descriptions) and the trap-table [Column Definitions](#column-definitions) for the trap list and how Time Lost is computed). Reads as a counterfactual: roughly how fast each combo would have been without the detected traps.
- The **Tier table's Duration column** shows the tier letter (A+..F) for the combo's gross **Avg Duration** ratio. Net of Traps does not feed the tier band.
## Tiers by Language/Model/Effort

*Default sort: weighted composite of tiers (40% Tests, 25% Workflow Craft, 35% split between Duration & Cost). See [Notes](#notes) for tier-band definitions and scoring rubric.*

| Language | Model | Duration | Cost | Tests Quality | Workflow Craft |
|----------|-------|----------|------|-----------|-------------|
| default | sonnet46-200k-medium | B (8.3min) | A+ ($1.14) | B (3.6) | A- (4.1) |
| typescript-bun | opus46-200k-medium | A+ (6.9min) | B- ($1.32) | B- (3.2) | B- (3.5) |
| typescript-bun | sonnet46-200k-medium | C- (9.5min) | A ($1.17) | B (3.7) | B- (3.4) |
| default | opus46-200k-medium | A+ (6.9min) | D+ ($1.45) | B- (3.5) | B- (3.5) |
| bash | sonnet46-200k-medium | D (10.4min) | C- ($1.40) | B (3.8) | A- (4.1) |
| powershell | sonnet46-200k-medium | D- (11.0min) | B- ($1.30) | B (3.7) | B- (3.5) |
| bash | opus46-200k-medium | B+ (7.7min) | D- ($1.52) | B- (3.3) | B- (3.3) |
| powershell | opus46-200k-medium | B (8.2min) | D- ($1.55) | C+ (3.2) | B- (3.5) |


<details>
<summary>Sorted by Duration tier (best-first), then avg of Cost/Tests/Workflow Craft tiers</summary>

| Language | Model | Duration | Cost | Tests Quality | Workflow Craft |
|----------|-------|----------|------|-----------|-------------|
| typescript-bun | opus46-200k-medium | A+ (6.9min) | B- ($1.32) | B- (3.2) | B- (3.5) |
| default | opus46-200k-medium | A+ (6.9min) | D+ ($1.45) | B- (3.5) | B- (3.5) |
| bash | opus46-200k-medium | B+ (7.7min) | D- ($1.52) | B- (3.3) | B- (3.3) |
| default | sonnet46-200k-medium | B (8.3min) | A+ ($1.14) | B (3.6) | A- (4.1) |
| powershell | opus46-200k-medium | B (8.2min) | D- ($1.55) | C+ (3.2) | B- (3.5) |
| typescript-bun | sonnet46-200k-medium | C- (9.5min) | A ($1.17) | B (3.7) | B- (3.4) |
| bash | sonnet46-200k-medium | D (10.4min) | C- ($1.40) | B (3.8) | A- (4.1) |
| powershell | sonnet46-200k-medium | D- (11.0min) | B- ($1.30) | B (3.7) | B- (3.5) |

</details>

<details>
<summary>Sorted by Cost tier (best-first), then avg of Duration/Tests/Workflow Craft tiers</summary>

| Language | Model | Duration | Cost | Tests Quality | Workflow Craft |
|----------|-------|----------|------|-----------|-------------|
| default | sonnet46-200k-medium | B (8.3min) | A+ ($1.14) | B (3.6) | A- (4.1) |
| typescript-bun | sonnet46-200k-medium | C- (9.5min) | A ($1.17) | B (3.7) | B- (3.4) |
| typescript-bun | opus46-200k-medium | A+ (6.9min) | B- ($1.32) | B- (3.2) | B- (3.5) |
| powershell | sonnet46-200k-medium | D- (11.0min) | B- ($1.30) | B (3.7) | B- (3.5) |
| bash | sonnet46-200k-medium | D (10.4min) | C- ($1.40) | B (3.8) | A- (4.1) |
| default | opus46-200k-medium | A+ (6.9min) | D+ ($1.45) | B- (3.5) | B- (3.5) |
| bash | opus46-200k-medium | B+ (7.7min) | D- ($1.52) | B- (3.3) | B- (3.3) |
| powershell | opus46-200k-medium | B (8.2min) | D- ($1.55) | C+ (3.2) | B- (3.5) |

</details>

<details>
<summary>Sorted by Tests Quality tier (best-first; no-data last), then avg of other tiers</summary>

| Language | Model | Duration | Cost | Tests Quality | Workflow Craft |
|----------|-------|----------|------|-----------|-------------|
| default | sonnet46-200k-medium | B (8.3min) | A+ ($1.14) | B (3.6) | A- (4.1) |
| typescript-bun | sonnet46-200k-medium | C- (9.5min) | A ($1.17) | B (3.7) | B- (3.4) |
| bash | sonnet46-200k-medium | D (10.4min) | C- ($1.40) | B (3.8) | A- (4.1) |
| powershell | sonnet46-200k-medium | D- (11.0min) | B- ($1.30) | B (3.7) | B- (3.5) |
| typescript-bun | opus46-200k-medium | A+ (6.9min) | B- ($1.32) | B- (3.2) | B- (3.5) |
| default | opus46-200k-medium | A+ (6.9min) | D+ ($1.45) | B- (3.5) | B- (3.5) |
| bash | opus46-200k-medium | B+ (7.7min) | D- ($1.52) | B- (3.3) | B- (3.3) |
| powershell | opus46-200k-medium | B (8.2min) | D- ($1.55) | C+ (3.2) | B- (3.5) |

</details>

<details>
<summary>Sorted by Workflow Craft tier (best-first; no-data last), then avg of other tiers</summary>

| Language | Model | Duration | Cost | Tests Quality | Workflow Craft |
|----------|-------|----------|------|-----------|-------------|
| default | sonnet46-200k-medium | B (8.3min) | A+ ($1.14) | B (3.6) | A- (4.1) |
| bash | sonnet46-200k-medium | D (10.4min) | C- ($1.40) | B (3.8) | A- (4.1) |
| typescript-bun | opus46-200k-medium | A+ (6.9min) | B- ($1.32) | B- (3.2) | B- (3.5) |
| typescript-bun | sonnet46-200k-medium | C- (9.5min) | A ($1.17) | B (3.7) | B- (3.4) |
| default | opus46-200k-medium | A+ (6.9min) | D+ ($1.45) | B- (3.5) | B- (3.5) |
| bash | opus46-200k-medium | B+ (7.7min) | D- ($1.52) | B- (3.3) | B- (3.3) |
| powershell | sonnet46-200k-medium | D- (11.0min) | B- ($1.30) | B (3.7) | B- (3.5) |
| powershell | opus46-200k-medium | B (8.2min) | D- ($1.55) | C+ (3.2) | B- (3.5) |

</details>

## Comparison by Language/Model/Effort
*See [Notes](#notes) for scoring rubric and CLI version legend.*

| Language | Model | Runs | Avg Duration | Avg Duration Net of Traps | Avg Errors | Avg Turns | Avg Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| bash | opus46-200k-medium | 8 | 7.7min | 7.7min | 1.6 | 43 | $1.52 | $12.19 | 3.3 | 3.3 |
| bash | sonnet46-200k-medium | 8 | 10.4min | 10.4min | 4.0 | 42 | $1.40 | $11.21 | 3.8 | 4.1 |
| default | opus46-200k-medium | 8 | 6.9min | 6.9min | 1.5 | 34 | $1.45 | $11.57 | 3.5 | 3.5 |
| default | sonnet46-200k-medium | 8 | 8.3min | 8.3min | 2.8 | 38 | $1.14 | $9.14 | 3.6 | 4.1 |
| powershell | opus46-200k-medium | 8 | 8.2min | 8.0min | 1.5 | 34 | $1.55 | $12.37 | 3.2 | 3.5 |
| powershell | sonnet46-200k-medium | 8 | 11.0min | 11.0min | 1.6 | 38 | $1.30 | $10.43 | 3.7 | 3.5 |
| typescript-bun | opus46-200k-medium | 8 | 6.9min | 6.9min | 2.0 | 39 | $1.32 | $10.60 | 3.2 | 3.5 |
| typescript-bun | sonnet46-200k-medium | 8 | 9.5min | 9.5min | 1.6 | 37 | $1.17 | $9.39 | 3.7 | 3.4 |


<details>
<summary>Sorted by avg cost (cheapest first)</summary>

| Language | Model | Runs | Avg Duration | Avg Duration Net of Traps | Avg Errors | Avg Turns | Avg Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| default | sonnet46-200k-medium | 8 | 8.3min | 8.3min | 2.8 | 38 | $1.14 | $9.14 | 3.6 | 4.1 |
| typescript-bun | sonnet46-200k-medium | 8 | 9.5min | 9.5min | 1.6 | 37 | $1.17 | $9.39 | 3.7 | 3.4 |
| powershell | sonnet46-200k-medium | 8 | 11.0min | 11.0min | 1.6 | 38 | $1.30 | $10.43 | 3.7 | 3.5 |
| typescript-bun | opus46-200k-medium | 8 | 6.9min | 6.9min | 2.0 | 39 | $1.32 | $10.60 | 3.2 | 3.5 |
| bash | sonnet46-200k-medium | 8 | 10.4min | 10.4min | 4.0 | 42 | $1.40 | $11.21 | 3.8 | 4.1 |
| default | opus46-200k-medium | 8 | 6.9min | 6.9min | 1.5 | 34 | $1.45 | $11.57 | 3.5 | 3.5 |
| bash | opus46-200k-medium | 8 | 7.7min | 7.7min | 1.6 | 43 | $1.52 | $12.19 | 3.3 | 3.3 |
| powershell | opus46-200k-medium | 8 | 8.2min | 8.0min | 1.5 | 34 | $1.55 | $12.37 | 3.2 | 3.5 |

</details>

<details>
<summary>Sorted by avg duration (fastest first)</summary>

| Language | Model | Runs | Avg Duration | Avg Duration Net of Traps | Avg Errors | Avg Turns | Avg Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| typescript-bun | opus46-200k-medium | 8 | 6.9min | 6.9min | 2.0 | 39 | $1.32 | $10.60 | 3.2 | 3.5 |
| default | opus46-200k-medium | 8 | 6.9min | 6.9min | 1.5 | 34 | $1.45 | $11.57 | 3.5 | 3.5 |
| bash | opus46-200k-medium | 8 | 7.7min | 7.7min | 1.6 | 43 | $1.52 | $12.19 | 3.3 | 3.3 |
| powershell | opus46-200k-medium | 8 | 8.2min | 8.0min | 1.5 | 34 | $1.55 | $12.37 | 3.2 | 3.5 |
| default | sonnet46-200k-medium | 8 | 8.3min | 8.3min | 2.8 | 38 | $1.14 | $9.14 | 3.6 | 4.1 |
| typescript-bun | sonnet46-200k-medium | 8 | 9.5min | 9.5min | 1.6 | 37 | $1.17 | $9.39 | 3.7 | 3.4 |
| bash | sonnet46-200k-medium | 8 | 10.4min | 10.4min | 4.0 | 42 | $1.40 | $11.21 | 3.8 | 4.1 |
| powershell | sonnet46-200k-medium | 8 | 11.0min | 11.0min | 1.6 | 38 | $1.30 | $10.43 | 3.7 | 3.5 |

</details>

<details>
<summary>Sorted by avg duration net of traps (fastest first)</summary>

| Language | Model | Runs | Avg Duration | Avg Duration Net of Traps | Avg Errors | Avg Turns | Avg Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| typescript-bun | opus46-200k-medium | 8 | 6.9min | 6.9min | 2.0 | 39 | $1.32 | $10.60 | 3.2 | 3.5 |
| default | opus46-200k-medium | 8 | 6.9min | 6.9min | 1.5 | 34 | $1.45 | $11.57 | 3.5 | 3.5 |
| bash | opus46-200k-medium | 8 | 7.7min | 7.7min | 1.6 | 43 | $1.52 | $12.19 | 3.3 | 3.3 |
| powershell | opus46-200k-medium | 8 | 8.2min | 8.0min | 1.5 | 34 | $1.55 | $12.37 | 3.2 | 3.5 |
| default | sonnet46-200k-medium | 8 | 8.3min | 8.3min | 2.8 | 38 | $1.14 | $9.14 | 3.6 | 4.1 |
| typescript-bun | sonnet46-200k-medium | 8 | 9.5min | 9.5min | 1.6 | 37 | $1.17 | $9.39 | 3.7 | 3.4 |
| bash | sonnet46-200k-medium | 8 | 10.4min | 10.4min | 4.0 | 42 | $1.40 | $11.21 | 3.8 | 4.1 |
| powershell | sonnet46-200k-medium | 8 | 11.0min | 11.0min | 1.6 | 38 | $1.30 | $10.43 | 3.7 | 3.5 |

</details>

<details>
<summary>Sorted by avg errors (fewest first)</summary>

| Language | Model | Runs | Avg Duration | Avg Duration Net of Traps | Avg Errors | Avg Turns | Avg Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| default | opus46-200k-medium | 8 | 6.9min | 6.9min | 1.5 | 34 | $1.45 | $11.57 | 3.5 | 3.5 |
| powershell | opus46-200k-medium | 8 | 8.2min | 8.0min | 1.5 | 34 | $1.55 | $12.37 | 3.2 | 3.5 |
| bash | opus46-200k-medium | 8 | 7.7min | 7.7min | 1.6 | 43 | $1.52 | $12.19 | 3.3 | 3.3 |
| powershell | sonnet46-200k-medium | 8 | 11.0min | 11.0min | 1.6 | 38 | $1.30 | $10.43 | 3.7 | 3.5 |
| typescript-bun | sonnet46-200k-medium | 8 | 9.5min | 9.5min | 1.6 | 37 | $1.17 | $9.39 | 3.7 | 3.4 |
| typescript-bun | opus46-200k-medium | 8 | 6.9min | 6.9min | 2.0 | 39 | $1.32 | $10.60 | 3.2 | 3.5 |
| default | sonnet46-200k-medium | 8 | 8.3min | 8.3min | 2.8 | 38 | $1.14 | $9.14 | 3.6 | 4.1 |
| bash | sonnet46-200k-medium | 8 | 10.4min | 10.4min | 4.0 | 42 | $1.40 | $11.21 | 3.8 | 4.1 |

</details>

<details>
<summary>Sorted by avg turns (fewest first)</summary>

| Language | Model | Runs | Avg Duration | Avg Duration Net of Traps | Avg Errors | Avg Turns | Avg Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| powershell | opus46-200k-medium | 8 | 8.2min | 8.0min | 1.5 | 34 | $1.55 | $12.37 | 3.2 | 3.5 |
| default | opus46-200k-medium | 8 | 6.9min | 6.9min | 1.5 | 34 | $1.45 | $11.57 | 3.5 | 3.5 |
| typescript-bun | sonnet46-200k-medium | 8 | 9.5min | 9.5min | 1.6 | 37 | $1.17 | $9.39 | 3.7 | 3.4 |
| default | sonnet46-200k-medium | 8 | 8.3min | 8.3min | 2.8 | 38 | $1.14 | $9.14 | 3.6 | 4.1 |
| powershell | sonnet46-200k-medium | 8 | 11.0min | 11.0min | 1.6 | 38 | $1.30 | $10.43 | 3.7 | 3.5 |
| typescript-bun | opus46-200k-medium | 8 | 6.9min | 6.9min | 2.0 | 39 | $1.32 | $10.60 | 3.2 | 3.5 |
| bash | sonnet46-200k-medium | 8 | 10.4min | 10.4min | 4.0 | 42 | $1.40 | $11.21 | 3.8 | 4.1 |
| bash | opus46-200k-medium | 8 | 7.7min | 7.7min | 1.6 | 43 | $1.52 | $12.19 | 3.3 | 3.3 |

</details>

<details>
<summary>Sorted by LLM-as-judge score (best first)</summary>

| Language | Model | Runs | Avg Duration | Avg Duration Net of Traps | Avg Errors | Avg Turns | Avg Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| bash | sonnet46-200k-medium | 8 | 10.4min | 10.4min | 4.0 | 42 | $1.40 | $11.21 | 3.8 | 4.1 |
| powershell | sonnet46-200k-medium | 8 | 11.0min | 11.0min | 1.6 | 38 | $1.30 | $10.43 | 3.7 | 3.5 |
| typescript-bun | sonnet46-200k-medium | 8 | 9.5min | 9.5min | 1.6 | 37 | $1.17 | $9.39 | 3.7 | 3.4 |
| default | sonnet46-200k-medium | 8 | 8.3min | 8.3min | 2.8 | 38 | $1.14 | $9.14 | 3.6 | 4.1 |
| default | opus46-200k-medium | 8 | 6.9min | 6.9min | 1.5 | 34 | $1.45 | $11.57 | 3.5 | 3.5 |
| bash | opus46-200k-medium | 8 | 7.7min | 7.7min | 1.6 | 43 | $1.52 | $12.19 | 3.3 | 3.3 |
| typescript-bun | opus46-200k-medium | 8 | 6.9min | 6.9min | 2.0 | 39 | $1.32 | $10.60 | 3.2 | 3.5 |
| powershell | opus46-200k-medium | 8 | 8.2min | 8.0min | 1.5 | 34 | $1.55 | $12.37 | 3.2 | 3.5 |

</details>

<details>
<summary>Sorted by deliverable-quality score (best first)</summary>

| Language | Model | Runs | Avg Duration | Avg Duration Net of Traps | Avg Errors | Avg Turns | Avg Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| bash | sonnet46-200k-medium | 8 | 10.4min | 10.4min | 4.0 | 42 | $1.40 | $11.21 | 3.8 | 4.1 |
| default | sonnet46-200k-medium | 8 | 8.3min | 8.3min | 2.8 | 38 | $1.14 | $9.14 | 3.6 | 4.1 |
| default | opus46-200k-medium | 8 | 6.9min | 6.9min | 1.5 | 34 | $1.45 | $11.57 | 3.5 | 3.5 |
| powershell | sonnet46-200k-medium | 8 | 11.0min | 11.0min | 1.6 | 38 | $1.30 | $10.43 | 3.7 | 3.5 |
| typescript-bun | opus46-200k-medium | 8 | 6.9min | 6.9min | 2.0 | 39 | $1.32 | $10.60 | 3.2 | 3.5 |
| powershell | opus46-200k-medium | 8 | 8.2min | 8.0min | 1.5 | 34 | $1.55 | $12.37 | 3.2 | 3.5 |
| typescript-bun | sonnet46-200k-medium | 8 | 9.5min | 9.5min | 1.6 | 37 | $1.17 | $9.39 | 3.7 | 3.4 |
| bash | opus46-200k-medium | 8 | 7.7min | 7.7min | 1.6 | 43 | $1.52 | $12.19 | 3.3 | 3.3 |

</details>

## Savings Analysis

### Hook Savings by Language/Model/Effort

Each hook-caught error avoids one test run that would otherwise have been needed to discover it.
Every hook fire (hit or miss) costs execution time for the syntax/type checker.

*`% of Test Time Saved` = `net / (net + test_time) × 100` — the share of total (would-have-been + actually-spent) test time that hooks eliminated. Bounded in (-∞, 100%) without an artificial cap; near 100% means hooks substituted for almost all of the hypothetical test work.*

| Language | Model | Fires | Caught | Rate | Gross Saved | % of Time | Overhead | % of Time | Net Saved | % of Time | Test Run Time | % of Test Time Saved |
|------|-------|-------|--------|------|------------|-----------|----------|-----------|-----------|-----------|---------------|----------------------|
| bash | opus46-200k-medium-cli2.1.100 | 9 | 0 | 0.0% | 0.0min | 0.0% | 0.0min | 0.0% | -0.0min | -0.0% | 0.3min | -8.1% |
| bash | opus46-200k-medium-cli2.1.98 | 82 | 3 | 3.7% | 0.6min | 0.1% | 0.6min | 0.1% | 0.0min | 0.0% | 6.8min | 0.4% |
| bash | sonnet46-200k-medium-cli2.1.100 | 29 | 2 | 6.9% | 0.4min | 0.1% | 0.0min | 0.0% | 0.4min | 0.1% | 2.6min | 12.5% |
| bash | sonnet46-200k-medium-cli2.1.98 | 78 | 7 | 9.0% | 1.4min | 0.3% | 0.2min | 0.0% | 1.2min | 0.2% | 6.4min | 16.1% |
| default | opus46-200k-medium-cli2.1.97 | 7 | 0 | 0.0% | 0.0min | 0.0% | 0.0min | 0.0% | -0.0min | -0.0% | 0.4min | -12.6% |
| default | opus46-200k-medium-cli2.1.98 | 70 | 14 | 20.0% | 1.9min | 0.3% | 0.2min | 0.0% | 1.7min | 0.3% | 2.6min | 39.2% |
| default | sonnet46-200k-medium-cli2.1.100 | 12 | 2 | 16.7% | 0.3min | 0.0% | 0.0min | 0.0% | 0.3min | 0.0% | 0.3min | 43.2% |
| default | sonnet46-200k-medium-cli2.1.98 | 69 | 1 | 1.4% | 0.1min | 0.0% | 0.2min | 0.0% | -0.1min | -0.0% | 3.3min | -1.9% |
| powershell | opus46-200k-medium-cli2.1.98 | 86 | 10 | 11.6% | 5.8min | 1.1% | 0.7min | 0.1% | 5.2min | 0.9% | 5.9min | 46.6% |
| powershell | sonnet46-200k-medium-cli2.1.100 | 11 | 0 | 0.0% | 0.0min | 0.0% | 0.1min | 0.0% | -0.1min | -0.0% | 0.8min | -7.1% |
| powershell | sonnet46-200k-medium-cli2.1.98 | 75 | 1 | 1.3% | 0.6min | 0.1% | 0.7min | 0.1% | -0.1min | -0.0% | 8.8min | -1.6% |
| typescript-bun | opus46-200k-medium-cli2.1.100 | 15 | 9 | 60.0% | 1.2min | 0.2% | 0.6min | 0.1% | 0.6min | 0.1% | 0.7min | 44.0% |
| typescript-bun | opus46-200k-medium-cli2.1.98 | 51 | 27 | 52.9% | 3.6min | 0.7% | 3.6min | 0.7% | -0.0min | -0.0% | 4.5min | -0.8% |
| typescript-bun | sonnet46-200k-medium-cli2.1.100 | 12 | 4 | 33.3% | 0.5min | 0.1% | 0.3min | 0.1% | 0.2min | 0.0% | 0.4min | 36.7% |
| typescript-bun | sonnet46-200k-medium-cli2.1.98 | 82 | 42 | 51.2% | 5.6min | 1.0% | 2.1min | 0.4% | 3.5min | 0.6% | 4.9min | 41.6% |


<details>
<summary>Sorted by net saved (most first)</summary>

| Language | Model | Fires | Caught | Rate | Gross Saved | % of Time | Overhead | % of Time | Net Saved | % of Time | Test Run Time | % of Test Time Saved |
|------|-------|-------|--------|------|------------|-----------|----------|-----------|-----------|-----------|---------------|----------------------|
| powershell | opus46-200k-medium-cli2.1.98 | 86 | 10 | 11.6% | 5.8min | 1.1% | 0.7min | 0.1% | 5.2min | 0.9% | 5.9min | 46.6% |
| typescript-bun | sonnet46-200k-medium-cli2.1.98 | 82 | 42 | 51.2% | 5.6min | 1.0% | 2.1min | 0.4% | 3.5min | 0.6% | 4.9min | 41.6% |
| default | opus46-200k-medium-cli2.1.98 | 70 | 14 | 20.0% | 1.9min | 0.3% | 0.2min | 0.0% | 1.7min | 0.3% | 2.6min | 39.2% |
| bash | sonnet46-200k-medium-cli2.1.98 | 78 | 7 | 9.0% | 1.4min | 0.3% | 0.2min | 0.0% | 1.2min | 0.2% | 6.4min | 16.1% |
| typescript-bun | opus46-200k-medium-cli2.1.100 | 15 | 9 | 60.0% | 1.2min | 0.2% | 0.6min | 0.1% | 0.6min | 0.1% | 0.7min | 44.0% |
| bash | sonnet46-200k-medium-cli2.1.100 | 29 | 2 | 6.9% | 0.4min | 0.1% | 0.0min | 0.0% | 0.4min | 0.1% | 2.6min | 12.5% |
| default | sonnet46-200k-medium-cli2.1.100 | 12 | 2 | 16.7% | 0.3min | 0.0% | 0.0min | 0.0% | 0.3min | 0.0% | 0.3min | 43.2% |
| typescript-bun | sonnet46-200k-medium-cli2.1.100 | 12 | 4 | 33.3% | 0.5min | 0.1% | 0.3min | 0.1% | 0.2min | 0.0% | 0.4min | 36.7% |
| bash | opus46-200k-medium-cli2.1.98 | 82 | 3 | 3.7% | 0.6min | 0.1% | 0.6min | 0.1% | 0.0min | 0.0% | 6.8min | 0.4% |
| bash | opus46-200k-medium-cli2.1.100 | 9 | 0 | 0.0% | 0.0min | 0.0% | 0.0min | 0.0% | -0.0min | -0.0% | 0.3min | -8.1% |
| typescript-bun | opus46-200k-medium-cli2.1.98 | 51 | 27 | 52.9% | 3.6min | 0.7% | 3.6min | 0.7% | -0.0min | -0.0% | 4.5min | -0.8% |
| default | opus46-200k-medium-cli2.1.97 | 7 | 0 | 0.0% | 0.0min | 0.0% | 0.0min | 0.0% | -0.0min | -0.0% | 0.4min | -12.6% |
| powershell | sonnet46-200k-medium-cli2.1.100 | 11 | 0 | 0.0% | 0.0min | 0.0% | 0.1min | 0.0% | -0.1min | -0.0% | 0.8min | -7.1% |
| default | sonnet46-200k-medium-cli2.1.98 | 69 | 1 | 1.4% | 0.1min | 0.0% | 0.2min | 0.0% | -0.1min | -0.0% | 3.3min | -1.9% |
| powershell | sonnet46-200k-medium-cli2.1.98 | 75 | 1 | 1.3% | 0.6min | 0.1% | 0.7min | 0.1% | -0.1min | -0.0% | 8.8min | -1.6% |

</details>

<details>
<summary>Sorted by net % of test time saved (most first)</summary>

| Language | Model | Fires | Caught | Rate | Gross Saved | % of Time | Overhead | % of Time | Net Saved | % of Time | Test Run Time | % of Test Time Saved |
|------|-------|-------|--------|------|------------|-----------|----------|-----------|-----------|-----------|---------------|----------------------|
| powershell | opus46-200k-medium-cli2.1.98 | 86 | 10 | 11.6% | 5.8min | 1.1% | 0.7min | 0.1% | 5.2min | 0.9% | 5.9min | 46.6% |
| typescript-bun | opus46-200k-medium-cli2.1.100 | 15 | 9 | 60.0% | 1.2min | 0.2% | 0.6min | 0.1% | 0.6min | 0.1% | 0.7min | 44.0% |
| default | sonnet46-200k-medium-cli2.1.100 | 12 | 2 | 16.7% | 0.3min | 0.0% | 0.0min | 0.0% | 0.3min | 0.0% | 0.3min | 43.2% |
| typescript-bun | sonnet46-200k-medium-cli2.1.98 | 82 | 42 | 51.2% | 5.6min | 1.0% | 2.1min | 0.4% | 3.5min | 0.6% | 4.9min | 41.6% |
| default | opus46-200k-medium-cli2.1.98 | 70 | 14 | 20.0% | 1.9min | 0.3% | 0.2min | 0.0% | 1.7min | 0.3% | 2.6min | 39.2% |
| typescript-bun | sonnet46-200k-medium-cli2.1.100 | 12 | 4 | 33.3% | 0.5min | 0.1% | 0.3min | 0.1% | 0.2min | 0.0% | 0.4min | 36.7% |
| bash | sonnet46-200k-medium-cli2.1.98 | 78 | 7 | 9.0% | 1.4min | 0.3% | 0.2min | 0.0% | 1.2min | 0.2% | 6.4min | 16.1% |
| bash | sonnet46-200k-medium-cli2.1.100 | 29 | 2 | 6.9% | 0.4min | 0.1% | 0.0min | 0.0% | 0.4min | 0.1% | 2.6min | 12.5% |
| bash | opus46-200k-medium-cli2.1.98 | 82 | 3 | 3.7% | 0.6min | 0.1% | 0.6min | 0.1% | 0.0min | 0.0% | 6.8min | 0.4% |
| typescript-bun | opus46-200k-medium-cli2.1.98 | 51 | 27 | 52.9% | 3.6min | 0.7% | 3.6min | 0.7% | -0.0min | -0.0% | 4.5min | -0.8% |
| powershell | sonnet46-200k-medium-cli2.1.98 | 75 | 1 | 1.3% | 0.6min | 0.1% | 0.7min | 0.1% | -0.1min | -0.0% | 8.8min | -1.6% |
| default | sonnet46-200k-medium-cli2.1.98 | 69 | 1 | 1.4% | 0.1min | 0.0% | 0.2min | 0.0% | -0.1min | -0.0% | 3.3min | -1.9% |
| powershell | sonnet46-200k-medium-cli2.1.100 | 11 | 0 | 0.0% | 0.0min | 0.0% | 0.1min | 0.0% | -0.1min | -0.0% | 0.8min | -7.1% |
| bash | opus46-200k-medium-cli2.1.100 | 9 | 0 | 0.0% | 0.0min | 0.0% | 0.0min | 0.0% | -0.0min | -0.0% | 0.3min | -8.1% |
| default | opus46-200k-medium-cli2.1.97 | 7 | 0 | 0.0% | 0.0min | 0.0% | 0.0min | 0.0% | -0.0min | -0.0% | 0.4min | -12.6% |

</details>

<details>
<summary>Sorted by catch rate (highest first)</summary>

| Language | Model | Fires | Caught | Rate | Gross Saved | % of Time | Overhead | % of Time | Net Saved | % of Time | Test Run Time | % of Test Time Saved |
|------|-------|-------|--------|------|------------|-----------|----------|-----------|-----------|-----------|---------------|----------------------|
| typescript-bun | opus46-200k-medium-cli2.1.100 | 15 | 9 | 60.0% | 1.2min | 0.2% | 0.6min | 0.1% | 0.6min | 0.1% | 0.7min | 44.0% |
| typescript-bun | opus46-200k-medium-cli2.1.98 | 51 | 27 | 52.9% | 3.6min | 0.7% | 3.6min | 0.7% | -0.0min | -0.0% | 4.5min | -0.8% |
| typescript-bun | sonnet46-200k-medium-cli2.1.98 | 82 | 42 | 51.2% | 5.6min | 1.0% | 2.1min | 0.4% | 3.5min | 0.6% | 4.9min | 41.6% |
| typescript-bun | sonnet46-200k-medium-cli2.1.100 | 12 | 4 | 33.3% | 0.5min | 0.1% | 0.3min | 0.1% | 0.2min | 0.0% | 0.4min | 36.7% |
| default | opus46-200k-medium-cli2.1.98 | 70 | 14 | 20.0% | 1.9min | 0.3% | 0.2min | 0.0% | 1.7min | 0.3% | 2.6min | 39.2% |
| default | sonnet46-200k-medium-cli2.1.100 | 12 | 2 | 16.7% | 0.3min | 0.0% | 0.0min | 0.0% | 0.3min | 0.0% | 0.3min | 43.2% |
| powershell | opus46-200k-medium-cli2.1.98 | 86 | 10 | 11.6% | 5.8min | 1.1% | 0.7min | 0.1% | 5.2min | 0.9% | 5.9min | 46.6% |
| bash | sonnet46-200k-medium-cli2.1.98 | 78 | 7 | 9.0% | 1.4min | 0.3% | 0.2min | 0.0% | 1.2min | 0.2% | 6.4min | 16.1% |
| bash | sonnet46-200k-medium-cli2.1.100 | 29 | 2 | 6.9% | 0.4min | 0.1% | 0.0min | 0.0% | 0.4min | 0.1% | 2.6min | 12.5% |
| bash | opus46-200k-medium-cli2.1.98 | 82 | 3 | 3.7% | 0.6min | 0.1% | 0.6min | 0.1% | 0.0min | 0.0% | 6.8min | 0.4% |
| default | sonnet46-200k-medium-cli2.1.98 | 69 | 1 | 1.4% | 0.1min | 0.0% | 0.2min | 0.0% | -0.1min | -0.0% | 3.3min | -1.9% |
| powershell | sonnet46-200k-medium-cli2.1.98 | 75 | 1 | 1.3% | 0.6min | 0.1% | 0.7min | 0.1% | -0.1min | -0.0% | 8.8min | -1.6% |
| bash | opus46-200k-medium-cli2.1.100 | 9 | 0 | 0.0% | 0.0min | 0.0% | 0.0min | 0.0% | -0.0min | -0.0% | 0.3min | -8.1% |
| default | opus46-200k-medium-cli2.1.97 | 7 | 0 | 0.0% | 0.0min | 0.0% | 0.0min | 0.0% | -0.0min | -0.0% | 0.4min | -12.6% |
| powershell | sonnet46-200k-medium-cli2.1.100 | 11 | 0 | 0.0% | 0.0min | 0.0% | 0.1min | 0.0% | -0.1min | -0.0% | 0.8min | -7.1% |

</details>

### Trap Analysis by Language/Model/Effort/Category

| Trap | Language | Model | Fell In | Time Lost | % of Time | $ Lost | % of $ |
|------|------|-------|---------|-----------|-----------|--------|--------|
| ts-type-error-fix-cycles | typescript-bun | opus46-200k-medium-cli2.1.100 | 1 | 1.8min | 0.3% | $0.40 | 0.46% |
| ts-type-error-fix-cycles | typescript-bun | opus46-200k-medium-cli2.1.98 | 6 | 5.4min | 1.0% | $1.01 | 1.17% |
| ts-type-error-fix-cycles | typescript-bun | sonnet46-200k-medium-cli2.1.100 | 1 | 0.8min | 0.1% | $0.10 | 0.12% |
| ts-type-error-fix-cycles | typescript-bun | sonnet46-200k-medium-cli2.1.98 | 7 | 8.4min | 1.5% | $1.05 | 1.21% |
| fixture-rework | bash | opus46-200k-medium-cli2.1.100 | 1 | 0.8min | 0.1% | $0.17 | 0.20% |
| fixture-rework | bash | opus46-200k-medium-cli2.1.98 | 3 | 2.8min | 0.5% | $0.59 | 0.68% |
| fixture-rework | bash | sonnet46-200k-medium-cli2.1.100 | 1 | 0.5min | 0.1% | $0.08 | 0.10% |
| fixture-rework | bash | sonnet46-200k-medium-cli2.1.98 | 1 | 0.5min | 0.1% | $0.06 | 0.07% |
| fixture-rework | powershell | opus46-200k-medium-cli2.1.98 | 1 | 1.5min | 0.3% | $0.37 | 0.42% |
| fixture-rework | powershell | sonnet46-200k-medium-cli2.1.98 | 2 | 2.5min | 0.5% | $0.36 | 0.41% |
| fixture-rework | typescript-bun | opus46-200k-medium-cli2.1.98 | 1 | 0.8min | 0.1% | $0.14 | 0.16% |
| repeated-test-reruns | bash | sonnet46-200k-medium-cli2.1.100 | 1 | 0.7min | 0.1% | $0.11 | 0.13% |
| repeated-test-reruns | default | sonnet46-200k-medium-cli2.1.98 | 1 | 0.7min | 0.1% | $0.08 | 0.09% |
| repeated-test-reruns | powershell | sonnet46-200k-medium-cli2.1.98 | 4 | 4.3min | 0.8% | $0.55 | 0.63% |
| repeated-test-reruns | typescript-bun | opus46-200k-medium-cli2.1.100 | 1 | 0.7min | 0.1% | $0.15 | 0.17% |
| repeated-test-reruns | typescript-bun | sonnet46-200k-medium-cli2.1.98 | 1 | 1.0min | 0.2% | $0.14 | 0.17% |
| act-push-debug-loops | bash | opus46-200k-medium-cli2.1.98 | 1 | 0.8min | 0.2% | $0.11 | 0.13% |
| act-push-debug-loops | bash | sonnet46-200k-medium-cli2.1.98 | 1 | 0.4min | 0.1% | $0.05 | 0.05% |
| act-push-debug-loops | default | sonnet46-200k-medium-cli2.1.98 | 2 | 2.2min | 0.4% | $0.28 | 0.32% |
| act-push-debug-loops | typescript-bun | opus46-200k-medium-cli2.1.98 | 1 | 0.5min | 0.1% | $0.09 | 0.11% |
| act-push-debug-loops | typescript-bun | sonnet46-200k-medium-cli2.1.98 | 1 | 1.2min | 0.2% | $0.13 | 0.15% |
| docker-pwsh-install | powershell | sonnet46-200k-medium-cli2.1.98 | 2 | 4.5min | 0.8% | $0.57 | 0.65% |
| bats-setup-issues | bash | sonnet46-200k-medium-cli2.1.98 | 2 | 1.8min | 0.3% | $0.25 | 0.29% |
| actionlint-fix-cycles | bash | opus46-200k-medium-cli2.1.98 | 1 | 0.7min | 0.1% | $0.09 | 0.10% |
| actionlint-fix-cycles | default | sonnet46-200k-medium-cli2.1.98 | 1 | 0.7min | 0.1% | $0.09 | 0.10% |
| act-permission-path-errors | default | sonnet46-200k-medium-cli2.1.98 | 1 | 0.8min | 0.1% | $0.09 | 0.10% |


<details>
<summary>Sorted by time lost (least first)</summary>

| Trap | Language | Model | Fell In | Time Lost | % of Time | $ Lost | % of $ |
|------|------|-------|---------|-----------|-----------|--------|--------|
| act-push-debug-loops | bash | sonnet46-200k-medium-cli2.1.98 | 1 | 0.4min | 0.1% | $0.05 | 0.05% |
| fixture-rework | bash | sonnet46-200k-medium-cli2.1.100 | 1 | 0.5min | 0.1% | $0.08 | 0.10% |
| fixture-rework | bash | sonnet46-200k-medium-cli2.1.98 | 1 | 0.5min | 0.1% | $0.06 | 0.07% |
| act-push-debug-loops | typescript-bun | opus46-200k-medium-cli2.1.98 | 1 | 0.5min | 0.1% | $0.09 | 0.11% |
| repeated-test-reruns | bash | sonnet46-200k-medium-cli2.1.100 | 1 | 0.7min | 0.1% | $0.11 | 0.13% |
| repeated-test-reruns | default | sonnet46-200k-medium-cli2.1.98 | 1 | 0.7min | 0.1% | $0.08 | 0.09% |
| repeated-test-reruns | typescript-bun | opus46-200k-medium-cli2.1.100 | 1 | 0.7min | 0.1% | $0.15 | 0.17% |
| actionlint-fix-cycles | bash | opus46-200k-medium-cli2.1.98 | 1 | 0.7min | 0.1% | $0.09 | 0.10% |
| actionlint-fix-cycles | default | sonnet46-200k-medium-cli2.1.98 | 1 | 0.7min | 0.1% | $0.09 | 0.10% |
| fixture-rework | bash | opus46-200k-medium-cli2.1.100 | 1 | 0.8min | 0.1% | $0.17 | 0.20% |
| fixture-rework | typescript-bun | opus46-200k-medium-cli2.1.98 | 1 | 0.8min | 0.1% | $0.14 | 0.16% |
| act-permission-path-errors | default | sonnet46-200k-medium-cli2.1.98 | 1 | 0.8min | 0.1% | $0.09 | 0.10% |
| ts-type-error-fix-cycles | typescript-bun | sonnet46-200k-medium-cli2.1.100 | 1 | 0.8min | 0.1% | $0.10 | 0.12% |
| act-push-debug-loops | bash | opus46-200k-medium-cli2.1.98 | 1 | 0.8min | 0.2% | $0.11 | 0.13% |
| repeated-test-reruns | typescript-bun | sonnet46-200k-medium-cli2.1.98 | 1 | 1.0min | 0.2% | $0.14 | 0.17% |
| act-push-debug-loops | typescript-bun | sonnet46-200k-medium-cli2.1.98 | 1 | 1.2min | 0.2% | $0.13 | 0.15% |
| fixture-rework | powershell | opus46-200k-medium-cli2.1.98 | 1 | 1.5min | 0.3% | $0.37 | 0.42% |
| bats-setup-issues | bash | sonnet46-200k-medium-cli2.1.98 | 2 | 1.8min | 0.3% | $0.25 | 0.29% |
| ts-type-error-fix-cycles | typescript-bun | opus46-200k-medium-cli2.1.100 | 1 | 1.8min | 0.3% | $0.40 | 0.46% |
| act-push-debug-loops | default | sonnet46-200k-medium-cli2.1.98 | 2 | 2.2min | 0.4% | $0.28 | 0.32% |
| fixture-rework | powershell | sonnet46-200k-medium-cli2.1.98 | 2 | 2.5min | 0.5% | $0.36 | 0.41% |
| fixture-rework | bash | opus46-200k-medium-cli2.1.98 | 3 | 2.8min | 0.5% | $0.59 | 0.68% |
| repeated-test-reruns | powershell | sonnet46-200k-medium-cli2.1.98 | 4 | 4.3min | 0.8% | $0.55 | 0.63% |
| docker-pwsh-install | powershell | sonnet46-200k-medium-cli2.1.98 | 2 | 4.5min | 0.8% | $0.57 | 0.65% |
| ts-type-error-fix-cycles | typescript-bun | opus46-200k-medium-cli2.1.98 | 6 | 5.4min | 1.0% | $1.01 | 1.17% |
| ts-type-error-fix-cycles | typescript-bun | sonnet46-200k-medium-cli2.1.98 | 7 | 8.4min | 1.5% | $1.05 | 1.21% |

</details>

<details>
<summary>Sorted by $ lost (least first)</summary>

| Trap | Language | Model | Fell In | Time Lost | % of Time | $ Lost | % of $ |
|------|------|-------|---------|-----------|-----------|--------|--------|
| act-push-debug-loops | bash | sonnet46-200k-medium-cli2.1.98 | 1 | 0.4min | 0.1% | $0.05 | 0.05% |
| fixture-rework | bash | sonnet46-200k-medium-cli2.1.98 | 1 | 0.5min | 0.1% | $0.06 | 0.07% |
| repeated-test-reruns | default | sonnet46-200k-medium-cli2.1.98 | 1 | 0.7min | 0.1% | $0.08 | 0.09% |
| fixture-rework | bash | sonnet46-200k-medium-cli2.1.100 | 1 | 0.5min | 0.1% | $0.08 | 0.10% |
| actionlint-fix-cycles | default | sonnet46-200k-medium-cli2.1.98 | 1 | 0.7min | 0.1% | $0.09 | 0.10% |
| actionlint-fix-cycles | bash | opus46-200k-medium-cli2.1.98 | 1 | 0.7min | 0.1% | $0.09 | 0.10% |
| act-permission-path-errors | default | sonnet46-200k-medium-cli2.1.98 | 1 | 0.8min | 0.1% | $0.09 | 0.10% |
| act-push-debug-loops | typescript-bun | opus46-200k-medium-cli2.1.98 | 1 | 0.5min | 0.1% | $0.09 | 0.11% |
| ts-type-error-fix-cycles | typescript-bun | sonnet46-200k-medium-cli2.1.100 | 1 | 0.8min | 0.1% | $0.10 | 0.12% |
| repeated-test-reruns | bash | sonnet46-200k-medium-cli2.1.100 | 1 | 0.7min | 0.1% | $0.11 | 0.13% |
| act-push-debug-loops | bash | opus46-200k-medium-cli2.1.98 | 1 | 0.8min | 0.2% | $0.11 | 0.13% |
| act-push-debug-loops | typescript-bun | sonnet46-200k-medium-cli2.1.98 | 1 | 1.2min | 0.2% | $0.13 | 0.15% |
| fixture-rework | typescript-bun | opus46-200k-medium-cli2.1.98 | 1 | 0.8min | 0.1% | $0.14 | 0.16% |
| repeated-test-reruns | typescript-bun | sonnet46-200k-medium-cli2.1.98 | 1 | 1.0min | 0.2% | $0.14 | 0.17% |
| repeated-test-reruns | typescript-bun | opus46-200k-medium-cli2.1.100 | 1 | 0.7min | 0.1% | $0.15 | 0.17% |
| fixture-rework | bash | opus46-200k-medium-cli2.1.100 | 1 | 0.8min | 0.1% | $0.17 | 0.20% |
| bats-setup-issues | bash | sonnet46-200k-medium-cli2.1.98 | 2 | 1.8min | 0.3% | $0.25 | 0.29% |
| act-push-debug-loops | default | sonnet46-200k-medium-cli2.1.98 | 2 | 2.2min | 0.4% | $0.28 | 0.32% |
| fixture-rework | powershell | sonnet46-200k-medium-cli2.1.98 | 2 | 2.5min | 0.5% | $0.36 | 0.41% |
| fixture-rework | powershell | opus46-200k-medium-cli2.1.98 | 1 | 1.5min | 0.3% | $0.37 | 0.42% |
| ts-type-error-fix-cycles | typescript-bun | opus46-200k-medium-cli2.1.100 | 1 | 1.8min | 0.3% | $0.40 | 0.46% |
| repeated-test-reruns | powershell | sonnet46-200k-medium-cli2.1.98 | 4 | 4.3min | 0.8% | $0.55 | 0.63% |
| docker-pwsh-install | powershell | sonnet46-200k-medium-cli2.1.98 | 2 | 4.5min | 0.8% | $0.57 | 0.65% |
| fixture-rework | bash | opus46-200k-medium-cli2.1.98 | 3 | 2.8min | 0.5% | $0.59 | 0.68% |
| ts-type-error-fix-cycles | typescript-bun | opus46-200k-medium-cli2.1.98 | 6 | 5.4min | 1.0% | $1.01 | 1.17% |
| ts-type-error-fix-cycles | typescript-bun | sonnet46-200k-medium-cli2.1.98 | 7 | 8.4min | 1.5% | $1.05 | 1.21% |

</details>

<details>
<summary>Sorted by fell-in count (fewest first)</summary>

| Trap | Language | Model | Fell In | Time Lost | % of Time | $ Lost | % of $ |
|------|------|-------|---------|-----------|-----------|--------|--------|
| ts-type-error-fix-cycles | typescript-bun | opus46-200k-medium-cli2.1.100 | 1 | 1.8min | 0.3% | $0.40 | 0.46% |
| ts-type-error-fix-cycles | typescript-bun | sonnet46-200k-medium-cli2.1.100 | 1 | 0.8min | 0.1% | $0.10 | 0.12% |
| fixture-rework | bash | opus46-200k-medium-cli2.1.100 | 1 | 0.8min | 0.1% | $0.17 | 0.20% |
| fixture-rework | bash | sonnet46-200k-medium-cli2.1.100 | 1 | 0.5min | 0.1% | $0.08 | 0.10% |
| fixture-rework | bash | sonnet46-200k-medium-cli2.1.98 | 1 | 0.5min | 0.1% | $0.06 | 0.07% |
| fixture-rework | powershell | opus46-200k-medium-cli2.1.98 | 1 | 1.5min | 0.3% | $0.37 | 0.42% |
| fixture-rework | typescript-bun | opus46-200k-medium-cli2.1.98 | 1 | 0.8min | 0.1% | $0.14 | 0.16% |
| repeated-test-reruns | bash | sonnet46-200k-medium-cli2.1.100 | 1 | 0.7min | 0.1% | $0.11 | 0.13% |
| repeated-test-reruns | default | sonnet46-200k-medium-cli2.1.98 | 1 | 0.7min | 0.1% | $0.08 | 0.09% |
| repeated-test-reruns | typescript-bun | opus46-200k-medium-cli2.1.100 | 1 | 0.7min | 0.1% | $0.15 | 0.17% |
| repeated-test-reruns | typescript-bun | sonnet46-200k-medium-cli2.1.98 | 1 | 1.0min | 0.2% | $0.14 | 0.17% |
| act-push-debug-loops | bash | opus46-200k-medium-cli2.1.98 | 1 | 0.8min | 0.2% | $0.11 | 0.13% |
| act-push-debug-loops | bash | sonnet46-200k-medium-cli2.1.98 | 1 | 0.4min | 0.1% | $0.05 | 0.05% |
| act-push-debug-loops | typescript-bun | opus46-200k-medium-cli2.1.98 | 1 | 0.5min | 0.1% | $0.09 | 0.11% |
| act-push-debug-loops | typescript-bun | sonnet46-200k-medium-cli2.1.98 | 1 | 1.2min | 0.2% | $0.13 | 0.15% |
| actionlint-fix-cycles | bash | opus46-200k-medium-cli2.1.98 | 1 | 0.7min | 0.1% | $0.09 | 0.10% |
| actionlint-fix-cycles | default | sonnet46-200k-medium-cli2.1.98 | 1 | 0.7min | 0.1% | $0.09 | 0.10% |
| act-permission-path-errors | default | sonnet46-200k-medium-cli2.1.98 | 1 | 0.8min | 0.1% | $0.09 | 0.10% |
| fixture-rework | powershell | sonnet46-200k-medium-cli2.1.98 | 2 | 2.5min | 0.5% | $0.36 | 0.41% |
| act-push-debug-loops | default | sonnet46-200k-medium-cli2.1.98 | 2 | 2.2min | 0.4% | $0.28 | 0.32% |
| docker-pwsh-install | powershell | sonnet46-200k-medium-cli2.1.98 | 2 | 4.5min | 0.8% | $0.57 | 0.65% |
| bats-setup-issues | bash | sonnet46-200k-medium-cli2.1.98 | 2 | 1.8min | 0.3% | $0.25 | 0.29% |
| fixture-rework | bash | opus46-200k-medium-cli2.1.98 | 3 | 2.8min | 0.5% | $0.59 | 0.68% |
| repeated-test-reruns | powershell | sonnet46-200k-medium-cli2.1.98 | 4 | 4.3min | 0.8% | $0.55 | 0.63% |
| ts-type-error-fix-cycles | typescript-bun | opus46-200k-medium-cli2.1.98 | 6 | 5.4min | 1.0% | $1.01 | 1.17% |
| ts-type-error-fix-cycles | typescript-bun | sonnet46-200k-medium-cli2.1.98 | 7 | 8.4min | 1.5% | $1.05 | 1.21% |

</details>

#### Trap Descriptions

- **act-permission-path-errors**: Files not found or permission denied inside the act Docker container.
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
| bash | opus46-200k-medium-cli2.1.100 | 1 | 1 | 0.8min | 0.1% | $0.17 | 0.20% |
| bash | opus46-200k-medium-cli2.1.98 | 7 | 5 | 4.2min | 0.8% | $0.79 | 0.91% |
| bash | sonnet46-200k-medium-cli2.1.100 | 1 | 2 | 1.2min | 0.2% | $0.19 | 0.22% |
| bash | sonnet46-200k-medium-cli2.1.98 | 7 | 4 | 2.7min | 0.5% | $0.36 | 0.41% |
| default | opus46-200k-medium-cli2.1.97 | 1 | 0 | 0.0min | 0.0% | $0.00 | 0.00% |
| default | opus46-200k-medium-cli2.1.98 | 7 | 0 | 0.0min | 0.0% | $0.00 | 0.00% |
| default | sonnet46-200k-medium-cli2.1.100 | 1 | 0 | 0.0min | 0.0% | $0.00 | 0.00% |
| default | sonnet46-200k-medium-cli2.1.98 | 7 | 5 | 4.2min | 0.8% | $0.54 | 0.62% |
| powershell | opus46-200k-medium-cli2.1.98 | 8 | 1 | 1.5min | 0.3% | $0.37 | 0.42% |
| powershell | sonnet46-200k-medium-cli2.1.100 | 1 | 0 | 0.0min | 0.0% | $0.00 | 0.00% |
| powershell | sonnet46-200k-medium-cli2.1.98 | 7 | 8 | 11.3min | 2.1% | $1.48 | 1.70% |
| typescript-bun | opus46-200k-medium-cli2.1.100 | 1 | 2 | 2.5min | 0.4% | $0.55 | 0.63% |
| typescript-bun | opus46-200k-medium-cli2.1.98 | 7 | 8 | 6.7min | 1.2% | $1.24 | 1.43% |
| typescript-bun | sonnet46-200k-medium-cli2.1.100 | 1 | 1 | 0.8min | 0.1% | $0.10 | 0.12% |
| typescript-bun | sonnet46-200k-medium-cli2.1.98 | 7 | 9 | 10.6min | 1.9% | $1.32 | 1.52% |


<details>
<summary>Sorted by time lost (least first)</summary>

| Language | Model | Runs | Traps | Time Lost | % of Time | $ Lost | % of $ |
|------|-------|------|-------|-----------|-----------|--------|--------|
| default | opus46-200k-medium-cli2.1.97 | 1 | 0 | 0.0min | 0.0% | $0.00 | 0.00% |
| default | opus46-200k-medium-cli2.1.98 | 7 | 0 | 0.0min | 0.0% | $0.00 | 0.00% |
| default | sonnet46-200k-medium-cli2.1.100 | 1 | 0 | 0.0min | 0.0% | $0.00 | 0.00% |
| powershell | sonnet46-200k-medium-cli2.1.100 | 1 | 0 | 0.0min | 0.0% | $0.00 | 0.00% |
| bash | opus46-200k-medium-cli2.1.100 | 1 | 1 | 0.8min | 0.1% | $0.17 | 0.20% |
| typescript-bun | sonnet46-200k-medium-cli2.1.100 | 1 | 1 | 0.8min | 0.1% | $0.10 | 0.12% |
| bash | sonnet46-200k-medium-cli2.1.100 | 1 | 2 | 1.2min | 0.2% | $0.19 | 0.22% |
| powershell | opus46-200k-medium-cli2.1.98 | 8 | 1 | 1.5min | 0.3% | $0.37 | 0.42% |
| typescript-bun | opus46-200k-medium-cli2.1.100 | 1 | 2 | 2.5min | 0.4% | $0.55 | 0.63% |
| bash | sonnet46-200k-medium-cli2.1.98 | 7 | 4 | 2.7min | 0.5% | $0.36 | 0.41% |
| default | sonnet46-200k-medium-cli2.1.98 | 7 | 5 | 4.2min | 0.8% | $0.54 | 0.62% |
| bash | opus46-200k-medium-cli2.1.98 | 7 | 5 | 4.2min | 0.8% | $0.79 | 0.91% |
| typescript-bun | opus46-200k-medium-cli2.1.98 | 7 | 8 | 6.7min | 1.2% | $1.24 | 1.43% |
| typescript-bun | sonnet46-200k-medium-cli2.1.98 | 7 | 9 | 10.6min | 1.9% | $1.32 | 1.52% |
| powershell | sonnet46-200k-medium-cli2.1.98 | 7 | 8 | 11.3min | 2.1% | $1.48 | 1.70% |

</details>

<details>
<summary>Sorted by $ lost (least first)</summary>

| Language | Model | Runs | Traps | Time Lost | % of Time | $ Lost | % of $ |
|------|-------|------|-------|-----------|-----------|--------|--------|
| default | opus46-200k-medium-cli2.1.97 | 1 | 0 | 0.0min | 0.0% | $0.00 | 0.00% |
| default | opus46-200k-medium-cli2.1.98 | 7 | 0 | 0.0min | 0.0% | $0.00 | 0.00% |
| default | sonnet46-200k-medium-cli2.1.100 | 1 | 0 | 0.0min | 0.0% | $0.00 | 0.00% |
| powershell | sonnet46-200k-medium-cli2.1.100 | 1 | 0 | 0.0min | 0.0% | $0.00 | 0.00% |
| typescript-bun | sonnet46-200k-medium-cli2.1.100 | 1 | 1 | 0.8min | 0.1% | $0.10 | 0.12% |
| bash | opus46-200k-medium-cli2.1.100 | 1 | 1 | 0.8min | 0.1% | $0.17 | 0.20% |
| bash | sonnet46-200k-medium-cli2.1.100 | 1 | 2 | 1.2min | 0.2% | $0.19 | 0.22% |
| bash | sonnet46-200k-medium-cli2.1.98 | 7 | 4 | 2.7min | 0.5% | $0.36 | 0.41% |
| powershell | opus46-200k-medium-cli2.1.98 | 8 | 1 | 1.5min | 0.3% | $0.37 | 0.42% |
| default | sonnet46-200k-medium-cli2.1.98 | 7 | 5 | 4.2min | 0.8% | $0.54 | 0.62% |
| typescript-bun | opus46-200k-medium-cli2.1.100 | 1 | 2 | 2.5min | 0.4% | $0.55 | 0.63% |
| bash | opus46-200k-medium-cli2.1.98 | 7 | 5 | 4.2min | 0.8% | $0.79 | 0.91% |
| typescript-bun | opus46-200k-medium-cli2.1.98 | 7 | 8 | 6.7min | 1.2% | $1.24 | 1.43% |
| typescript-bun | sonnet46-200k-medium-cli2.1.98 | 7 | 9 | 10.6min | 1.9% | $1.32 | 1.52% |
| powershell | sonnet46-200k-medium-cli2.1.98 | 7 | 8 | 11.3min | 2.1% | $1.48 | 1.70% |

</details>

### Prompt Cache Savings

| Status | Runs | $ Saved | % of $ |
|--------|------|---------|--------|
| Full hit (100%) | 1 | $0.06 | 0.07% |
| Partial | 60 | $3.14 | 3.61% |
| Miss | 3 | $0.00 | 0.00% |

## Test Quality Evaluation

### Structural Metrics by Language/Model/Effort

Automated analysis of test files: test count, assertion count, and test-to-code line ratio.

| Language | Model | Avg Tests | Avg Assertions | Avg Assert/Test | Avg Test:Code Ratio |
|------|-------|-----------|----------------|-----------------|---------------------|
| bash | opus46-200k-medium | 26.1 | 35.1 | 1.3 | 1.12 |
| bash | sonnet46-200k-medium | 27.2 | 43.5 | 1.6 | 0.91 |
| default | opus46-200k-medium | 17.8 | 26.8 | 1.5 | 2.21 |
| default | sonnet46-200k-medium | 34.5 | 47.5 | 1.4 | 1.76 |
| powershell | opus46-200k-medium | 24.0 | 41.1 | 1.7 | 1.30 |
| powershell | sonnet46-200k-medium | 37.9 | 51.8 | 1.4 | 0.78 |
| typescript-bun | opus46-200k-medium | 24.8 | 48.4 | 2.0 | 1.00 |
| typescript-bun | sonnet46-200k-medium | 33.2 | 62.5 | 1.9 | 1.01 |


<details>
<summary>Sorted by avg tests (most first)</summary>

| Language | Model | Avg Tests | Avg Assertions | Avg Assert/Test | Avg Test:Code Ratio |
|------|-------|-----------|----------------|-----------------|---------------------|
| powershell | sonnet46-200k-medium | 37.9 | 51.8 | 1.4 | 0.78 |
| default | sonnet46-200k-medium | 34.5 | 47.5 | 1.4 | 1.76 |
| typescript-bun | sonnet46-200k-medium | 33.2 | 62.5 | 1.9 | 1.01 |
| bash | sonnet46-200k-medium | 27.2 | 43.5 | 1.6 | 0.91 |
| bash | opus46-200k-medium | 26.1 | 35.1 | 1.3 | 1.12 |
| typescript-bun | opus46-200k-medium | 24.8 | 48.4 | 2.0 | 1.00 |
| powershell | opus46-200k-medium | 24.0 | 41.1 | 1.7 | 1.30 |
| default | opus46-200k-medium | 17.8 | 26.8 | 1.5 | 2.21 |

</details>

<details>
<summary>Sorted by avg assertions (most first)</summary>

| Language | Model | Avg Tests | Avg Assertions | Avg Assert/Test | Avg Test:Code Ratio |
|------|-------|-----------|----------------|-----------------|---------------------|
| typescript-bun | sonnet46-200k-medium | 33.2 | 62.5 | 1.9 | 1.01 |
| powershell | sonnet46-200k-medium | 37.9 | 51.8 | 1.4 | 0.78 |
| typescript-bun | opus46-200k-medium | 24.8 | 48.4 | 2.0 | 1.00 |
| default | sonnet46-200k-medium | 34.5 | 47.5 | 1.4 | 1.76 |
| bash | sonnet46-200k-medium | 27.2 | 43.5 | 1.6 | 0.91 |
| powershell | opus46-200k-medium | 24.0 | 41.1 | 1.7 | 1.30 |
| bash | opus46-200k-medium | 26.1 | 35.1 | 1.3 | 1.12 |
| default | opus46-200k-medium | 17.8 | 26.8 | 1.5 | 2.21 |

</details>

<details>
<summary>Sorted by avg test:code ratio (highest first)</summary>

| Language | Model | Avg Tests | Avg Assertions | Avg Assert/Test | Avg Test:Code Ratio |
|------|-------|-----------|----------------|-----------------|---------------------|
| default | opus46-200k-medium | 17.8 | 26.8 | 1.5 | 2.21 |
| default | sonnet46-200k-medium | 34.5 | 47.5 | 1.4 | 1.76 |
| powershell | opus46-200k-medium | 24.0 | 41.1 | 1.7 | 1.30 |
| bash | opus46-200k-medium | 26.1 | 35.1 | 1.3 | 1.12 |
| typescript-bun | sonnet46-200k-medium | 33.2 | 62.5 | 1.9 | 1.01 |
| typescript-bun | opus46-200k-medium | 24.8 | 48.4 | 2.0 | 1.00 |
| bash | sonnet46-200k-medium | 27.2 | 43.5 | 1.6 | 0.91 |
| powershell | sonnet46-200k-medium | 37.9 | 51.8 | 1.4 | 0.78 |

</details>


<details>
<summary>Per-run structural metrics</summary>

| Task | Language | Model | Tests | Assertions | Assert/Test | Test Lines | Impl Lines | Test:Code |
|------|------|-------|-------|------------|-------------|------------|------------|-----------|
| Semantic Version Bumper | bash | opus46-200k-medium | 20 | 37 | 1.9 | 206 | 530 | 0.39 |
| Semantic Version Bumper | bash | sonnet46-200k-medium | 29 | 42 | 1.4 | 270 | 473 | 0.57 |
| Semantic Version Bumper | default | opus46-200k-medium | 1 | 2 | 2.0 | 352 | 288 | 1.22 |
| Semantic Version Bumper | default | sonnet46-200k-medium | 44 | 42 | 1.0 | 289 | 243 | 1.19 |
| Semantic Version Bumper | powershell | opus46-200k-medium | 13 | 31 | 2.4 | 203 | 203 | 1.00 |
| Semantic Version Bumper | powershell | sonnet46-200k-medium | 32 | 43 | 1.3 | 267 | 482 | 0.55 |
| Semantic Version Bumper | typescript-bun | opus46-200k-medium | 14 | 27 | 1.9 | 245 | 251 | 0.98 |
| Semantic Version Bumper | typescript-bun | sonnet46-200k-medium | 37 | 43 | 1.2 | 276 | 423 | 0.65 |
| PR Label Assigner | bash | opus46-200k-medium | 12 | 5 | 0.4 | 147 | 279 | 0.53 |
| PR Label Assigner | bash | sonnet46-200k-medium | 33 | 60 | 1.8 | 287 | 336 | 0.85 |
| PR Label Assigner | default | opus46-200k-medium | 17 | 18 | 1.1 | 622 | 169 | 3.68 |
| PR Label Assigner | default | sonnet46-200k-medium | 26 | 32 | 1.2 | 508 | 217 | 2.34 |
| PR Label Assigner | powershell | opus46-200k-medium | 34 | 49 | 1.4 | 294 | 159 | 1.85 |
| PR Label Assigner | powershell | sonnet46-200k-medium | 38 | 47 | 1.2 | 273 | 378 | 0.72 |
| PR Label Assigner | typescript-bun | opus46-200k-medium | 21 | 51 | 2.4 | 268 | 226 | 1.19 |
| PR Label Assigner | typescript-bun | sonnet46-200k-medium | 22 | 33 | 1.5 | 191 | 424 | 0.45 |
| Dependency License Checker | bash | opus46-200k-medium | 52 | 51 | 1.0 | 378 | 252 | 1.50 |
| Dependency License Checker | bash | sonnet46-200k-medium | 44 | 67 | 1.5 | 443 | 309 | 1.43 |
| Dependency License Checker | default | opus46-200k-medium | 28 | 45 | 1.6 | 369 | 219 | 1.68 |
| Dependency License Checker | default | sonnet46-200k-medium | 31 | 70 | 2.3 | 589 | 260 | 2.27 |
| Dependency License Checker | powershell | opus46-200k-medium | 23 | 49 | 2.1 | 205 | 316 | 0.65 |
| Dependency License Checker | powershell | sonnet46-200k-medium | 26 | 52 | 2.0 | 305 | 481 | 0.63 |
| Dependency License Checker | typescript-bun | opus46-200k-medium | 65 | 112 | 1.7 | 707 | 363 | 1.95 |
| Dependency License Checker | typescript-bun | sonnet46-200k-medium | 36 | 51 | 1.4 | 318 | 289 | 1.10 |
| Docker Image Tag Generator | bash | opus46-200k-medium | 25 | 6 | 0.2 | 167 | 108 | 1.55 |
| Docker Image Tag Generator | bash | sonnet46-200k-medium | 15 | 25 | 1.7 | 128 | 373 | 0.34 |
| Docker Image Tag Generator | default | opus46-200k-medium | 26 | 36 | 1.4 | 251 | 128 | 1.96 |
| Docker Image Tag Generator | default | sonnet46-200k-medium | 36 | 42 | 1.2 | 605 | 176 | 3.44 |
| Docker Image Tag Generator | powershell | opus46-200k-medium | 13 | 40 | 3.1 | 170 | 72 | 2.36 |
| Docker Image Tag Generator | powershell | sonnet46-200k-medium | 34 | 37 | 1.1 | 209 | 338 | 0.62 |
| Docker Image Tag Generator | typescript-bun | opus46-200k-medium | 23 | 27 | 1.2 | 217 | 136 | 1.60 |
| Docker Image Tag Generator | typescript-bun | sonnet46-200k-medium | 13 | 14 | 1.1 | 73 | 289 | 0.25 |
| Test Results Aggregator | bash | opus46-200k-medium | 14 | 43 | 3.1 | 168 | 241 | 0.70 |
| Test Results Aggregator | bash | sonnet46-200k-medium | 25 | 26 | 1.0 | 173 | 307 | 0.56 |
| Test Results Aggregator | default | opus46-200k-medium | 9 | 27 | 3.0 | 468 | 337 | 1.39 |
| Test Results Aggregator | default | sonnet46-200k-medium | 33 | 41 | 1.2 | 266 | 377 | 0.71 |
| Test Results Aggregator | powershell | opus46-200k-medium | 28 | 30 | 1.1 | 264 | 244 | 1.08 |
| Test Results Aggregator | powershell | sonnet46-200k-medium | 99 | 111 | 1.1 | 701 | 994 | 0.71 |
| Test Results Aggregator | typescript-bun | opus46-200k-medium | 22 | 45 | 2.0 | 265 | 552 | 0.48 |
| Test Results Aggregator | typescript-bun | sonnet46-200k-medium | 46 | 110 | 2.4 | 611 | 387 | 1.58 |
| Environment Matrix Generator | bash | opus46-200k-medium | 24 | 9 | 0.4 | 233 | 134 | 1.74 |
| Environment Matrix Generator | bash | sonnet46-200k-medium | 22 | 38 | 1.7 | 233 | 321 | 0.73 |
| Environment Matrix Generator | default | opus46-200k-medium | 16 | 16 | 1.0 | 515 | 185 | 2.78 |
| Environment Matrix Generator | default | sonnet46-200k-medium | 37 | 51 | 1.4 | 592 | 207 | 2.86 |
| Environment Matrix Generator | powershell | opus46-200k-medium | 19 | 43 | 2.3 | 279 | 139 | 2.01 |
| Environment Matrix Generator | powershell | sonnet46-200k-medium | 24 | 41 | 1.7 | 284 | 244 | 1.16 |
| Environment Matrix Generator | typescript-bun | opus46-200k-medium | 23 | 28 | 1.2 | 207 | 347 | 0.60 |
| Environment Matrix Generator | typescript-bun | sonnet46-200k-medium | 28 | 42 | 1.5 | 292 | 427 | 0.68 |
| Artifact Cleanup Script | bash | opus46-200k-medium | 24 | 103 | 4.3 | 339 | 347 | 0.98 |
| Artifact Cleanup Script | bash | sonnet46-200k-medium | 27 | 47 | 1.7 | 323 | 238 | 1.36 |
| Artifact Cleanup Script | default | opus46-200k-medium | 21 | 30 | 1.4 | 384 | 209 | 1.84 |
| Artifact Cleanup Script | default | sonnet46-200k-medium | 30 | 47 | 1.6 | 333 | 542 | 0.61 |
| Artifact Cleanup Script | powershell | opus46-200k-medium | 15 | 39 | 2.6 | 220 | 0 | 0.00 |
| Artifact Cleanup Script | powershell | sonnet46-200k-medium | 16 | 30 | 1.9 | 197 | 170 | 1.16 |
| Artifact Cleanup Script | typescript-bun | opus46-200k-medium | 17 | 48 | 2.8 | 261 | 341 | 0.77 |
| Artifact Cleanup Script | typescript-bun | sonnet46-200k-medium | 35 | 78 | 2.2 | 497 | 392 | 1.27 |
| Secret Rotation Validator | bash | opus46-200k-medium | 38 | 27 | 0.7 | 273 | 177 | 1.54 |
| Secret Rotation Validator | bash | sonnet46-200k-medium | 23 | 43 | 1.9 | 422 | 302 | 1.40 |
| Secret Rotation Validator | default | opus46-200k-medium | 24 | 40 | 1.7 | 659 | 212 | 3.11 |
| Secret Rotation Validator | default | sonnet46-200k-medium | 39 | 55 | 1.4 | 430 | 611 | 0.70 |
| Secret Rotation Validator | powershell | opus46-200k-medium | 47 | 48 | 1.0 | 325 | 220 | 1.48 |
| Secret Rotation Validator | powershell | sonnet46-200k-medium | 34 | 53 | 1.6 | 323 | 464 | 0.70 |
| Secret Rotation Validator | typescript-bun | opus46-200k-medium | 13 | 49 | 3.8 | 217 | 548 | 0.40 |
| Secret Rotation Validator | typescript-bun | sonnet46-200k-medium | 49 | 129 | 2.6 | 616 | 293 | 2.10 |

</details>

### LLM-as-Judge Scores

An LLM evaluates each test suite on four dimensions (1-5 scale):

- **Coverage** (1-5): Do tests exercise the key requirements? 1 = most untested, 5 = all covered.
- **Rigor** (1-5): Edge cases, error handling, boundary conditions? 1 = happy path only, 5 = thorough.
- **Design** (1-5): Test organization, fixtures, readability? 1 = messy/brittle, 5 = well-structured.
- **Overall** (1-5): Holistic quality — would you trust this suite to catch regressions? 1 = no, 5 = absolutely. Use this as the primary ranking metric.

| Language | Model | Avg Overall | Avg Coverage | Avg Rigor | Avg Design | Judge Cost |
|------|-------|-------------|-------------|-----------|------------|------------|
| bash | opus46-200k-medium | **3.3** | 3.8 | 3.1 | 3.1 | $0.9027 |
| bash | sonnet46-200k-medium | **3.8** | 4.1 | 3.5 | 4.0 | $0.9950 |
| default | opus46-200k-medium | **3.5** | 3.8 | 3.3 | 3.8 | $0.9879 |
| default | sonnet46-200k-medium | **3.6** | 4.0 | 3.5 | 4.1 | $1.0423 |
| powershell | opus46-200k-medium | **3.2** | 3.5 | 3.0 | 3.5 | $0.8562 |
| powershell | sonnet46-200k-medium | **3.7** | 4.0 | 3.5 | 4.1 | $1.1350 |
| typescript-bun | opus46-200k-medium | **3.2** | 3.5 | 3.0 | 3.7 | $0.9769 |
| typescript-bun | sonnet46-200k-medium | **3.7** | 3.8 | 3.7 | 4.0 | $1.0105 |
| **Total** | | | | | | **$7.9065** |


<details>
<summary>Sorted by avg overall (highest first)</summary>

| Language | Model | Avg Overall | Avg Coverage | Avg Rigor | Avg Design | Judge Cost |
|------|-------|-------------|-------------|-----------|------------|------------|
| bash | sonnet46-200k-medium | **3.8** | 4.1 | 3.5 | 4.0 | $0.9950 |
| powershell | sonnet46-200k-medium | **3.7** | 4.0 | 3.5 | 4.1 | $1.1350 |
| typescript-bun | sonnet46-200k-medium | **3.7** | 3.8 | 3.7 | 4.0 | $1.0105 |
| default | sonnet46-200k-medium | **3.6** | 4.0 | 3.5 | 4.1 | $1.0423 |
| default | opus46-200k-medium | **3.5** | 3.8 | 3.3 | 3.8 | $0.9879 |
| bash | opus46-200k-medium | **3.3** | 3.8 | 3.1 | 3.1 | $0.9027 |
| typescript-bun | opus46-200k-medium | **3.2** | 3.5 | 3.0 | 3.7 | $0.9769 |
| powershell | opus46-200k-medium | **3.2** | 3.5 | 3.0 | 3.5 | $0.8562 |

</details>

<details>
<summary>Sorted by avg coverage (highest first)</summary>

| Language | Model | Avg Overall | Avg Coverage | Avg Rigor | Avg Design | Judge Cost |
|------|-------|-------------|-------------|-----------|------------|------------|
| bash | sonnet46-200k-medium | **3.8** | 4.1 | 3.5 | 4.0 | $0.9950 |
| default | sonnet46-200k-medium | **3.6** | 4.0 | 3.5 | 4.1 | $1.0423 |
| powershell | sonnet46-200k-medium | **3.7** | 4.0 | 3.5 | 4.1 | $1.1350 |
| typescript-bun | sonnet46-200k-medium | **3.7** | 3.8 | 3.7 | 4.0 | $1.0105 |
| default | opus46-200k-medium | **3.5** | 3.8 | 3.3 | 3.8 | $0.9879 |
| bash | opus46-200k-medium | **3.3** | 3.8 | 3.1 | 3.1 | $0.9027 |
| typescript-bun | opus46-200k-medium | **3.2** | 3.5 | 3.0 | 3.7 | $0.9769 |
| powershell | opus46-200k-medium | **3.2** | 3.5 | 3.0 | 3.5 | $0.8562 |

</details>

<details>
<summary>Sorted by avg rigor (highest first)</summary>

| Language | Model | Avg Overall | Avg Coverage | Avg Rigor | Avg Design | Judge Cost |
|------|-------|-------------|-------------|-----------|------------|------------|
| typescript-bun | sonnet46-200k-medium | **3.7** | 3.8 | 3.7 | 4.0 | $1.0105 |
| powershell | sonnet46-200k-medium | **3.7** | 4.0 | 3.5 | 4.1 | $1.1350 |
| bash | sonnet46-200k-medium | **3.8** | 4.1 | 3.5 | 4.0 | $0.9950 |
| default | sonnet46-200k-medium | **3.6** | 4.0 | 3.5 | 4.1 | $1.0423 |
| default | opus46-200k-medium | **3.5** | 3.8 | 3.3 | 3.8 | $0.9879 |
| bash | opus46-200k-medium | **3.3** | 3.8 | 3.1 | 3.1 | $0.9027 |
| typescript-bun | opus46-200k-medium | **3.2** | 3.5 | 3.0 | 3.7 | $0.9769 |
| powershell | opus46-200k-medium | **3.2** | 3.5 | 3.0 | 3.5 | $0.8562 |

</details>

<details>
<summary>Sorted by avg design (highest first)</summary>

| Language | Model | Avg Overall | Avg Coverage | Avg Rigor | Avg Design | Judge Cost |
|------|-------|-------------|-------------|-----------|------------|------------|
| default | sonnet46-200k-medium | **3.6** | 4.0 | 3.5 | 4.1 | $1.0423 |
| powershell | sonnet46-200k-medium | **3.7** | 4.0 | 3.5 | 4.1 | $1.1350 |
| bash | sonnet46-200k-medium | **3.8** | 4.1 | 3.5 | 4.0 | $0.9950 |
| typescript-bun | sonnet46-200k-medium | **3.7** | 3.8 | 3.7 | 4.0 | $1.0105 |
| default | opus46-200k-medium | **3.5** | 3.8 | 3.3 | 3.8 | $0.9879 |
| typescript-bun | opus46-200k-medium | **3.2** | 3.5 | 3.0 | 3.7 | $0.9769 |
| powershell | opus46-200k-medium | **3.2** | 3.5 | 3.0 | 3.5 | $0.8562 |
| bash | opus46-200k-medium | **3.3** | 3.8 | 3.1 | 3.1 | $0.9027 |

</details>


<details>
<summary>Per-run LLM judge scores</summary>

| Task | Language | Model | Cov | Rig | Des | Ovr | Summary |
|------|------|-------|-----|-----|-----|-----|---------|
| Semantic Version Bumper | bash | opus46-200k-medium | 4.0 | 3.3333333333333335 | 3.6666666666666665 | 3.6666666666666665 |  |
| Semantic Version Bumper | bash | sonnet46-200k-medium | 4.0 | 3.3333333333333335 | 4.0 | 3.6666666666666665 |  |
| Semantic Version Bumper | default | opus46-200k-medium | 3.3333333333333335 | 2.6666666666666665 | 3.6666666666666665 | 3.3333333333333335 |  |
| Semantic Version Bumper | default | sonnet46-200k-medium | 3.6666666666666665 | 3.0 | 4.333333333333333 | 3.0 |  |
| Semantic Version Bumper | powershell | opus46-200k-medium | 3.0 | 2.0 | 3.3333333333333335 | 2.3333333333333335 |  |
| Semantic Version Bumper | powershell | sonnet46-200k-medium | 4.333333333333333 | 3.6666666666666665 | 4.0 | 4.0 |  |
| Semantic Version Bumper | typescript-bun | opus46-200k-medium | 2.6666666666666665 | 2.0 | 3.6666666666666665 | 2.6666666666666665 |  |
| Semantic Version Bumper | typescript-bun | sonnet46-200k-medium | 3.6666666666666665 | 3.3333333333333335 | 4.0 | 3.6666666666666665 |  |
| PR Label Assigner | bash | opus46-200k-medium | 3.0 | 2.0 | 1.6666666666666667 | 2.0 |  |
| PR Label Assigner | bash | sonnet46-200k-medium | 4.666666666666667 | 4.0 | 4.666666666666667 | 4.333333333333333 |  |
| PR Label Assigner | default | opus46-200k-medium | 4.666666666666667 | 4.0 | 4.333333333333333 | 4.333333333333333 |  |
| PR Label Assigner | default | sonnet46-200k-medium | 3.6666666666666665 | 3.6666666666666665 | 4.0 | 3.6666666666666665 |  |
| PR Label Assigner | powershell | opus46-200k-medium | 3.0 | 3.3333333333333335 | 2.6666666666666665 | 2.6666666666666665 |  |
| PR Label Assigner | powershell | sonnet46-200k-medium | 4.333333333333333 | 3.6666666666666665 | 4.333333333333333 | 4.0 |  |
| PR Label Assigner | typescript-bun | opus46-200k-medium | 3.3333333333333335 | 2.6666666666666665 | 4.333333333333333 | 3.0 |  |
| PR Label Assigner | typescript-bun | sonnet46-200k-medium | 4.666666666666667 | 4.0 | 4.666666666666667 | 4.666666666666667 |  |
| Dependency License Checker | bash | opus46-200k-medium | 4.333333333333333 | 3.3333333333333335 | 4.0 | 4.0 |  |
| Dependency License Checker | bash | sonnet46-200k-medium | 4.333333333333333 | 3.6666666666666665 | 3.6666666666666665 | 3.6666666666666665 |  |
| Dependency License Checker | default | opus46-200k-medium | 3.3333333333333335 | 3.0 | 4.333333333333333 | 3.0 |  |
| Dependency License Checker | default | sonnet46-200k-medium | 4.666666666666667 | 4.0 | 4.333333333333333 | 4.333333333333333 |  |
| Dependency License Checker | powershell | opus46-200k-medium | 4.333333333333333 | 3.6666666666666665 | 4.333333333333333 | 4.0 |  |
| Dependency License Checker | powershell | sonnet46-200k-medium | 4.333333333333333 | 4.0 | 4.333333333333333 | 4.0 |  |
| Dependency License Checker | typescript-bun | opus46-200k-medium | 4.0 | 3.6666666666666665 | 3.6666666666666665 | 3.6666666666666665 |  |
| Dependency License Checker | typescript-bun | sonnet46-200k-medium | 2.3333333333333335 | 2.6666666666666665 | 3.0 | 2.3333333333333335 |  |
| Docker Image Tag Generator | bash | opus46-200k-medium | 3.6666666666666665 | 3.0 | 2.3333333333333335 | 2.6666666666666665 |  |
| Docker Image Tag Generator | bash | sonnet46-200k-medium | 4.666666666666667 | 4.0 | 4.666666666666667 | 4.333333333333333 |  |
| Docker Image Tag Generator | default | opus46-200k-medium | 4.5 | 4.0 | 4.0 | 4.0 |  |
| Docker Image Tag Generator | default | sonnet46-200k-medium | 4.333333333333333 | 3.6666666666666665 | 4.333333333333333 | 3.6666666666666665 |  |
| Docker Image Tag Generator | powershell | opus46-200k-medium | 3.6666666666666665 | 2.6666666666666665 | 3.0 | 3.3333333333333335 |  |
| Docker Image Tag Generator | powershell | sonnet46-200k-medium | 4.0 | 3.3333333333333335 | 4.333333333333333 | 4.0 |  |
| Docker Image Tag Generator | typescript-bun | opus46-200k-medium | 3.3333333333333335 | 2.6666666666666665 | 3.0 | 3.0 |  |
| Docker Image Tag Generator | typescript-bun | sonnet46-200k-medium | 4.333333333333333 | 3.6666666666666665 | 4.0 | 4.0 |  |
| Test Results Aggregator | bash | opus46-200k-medium | 3.6666666666666665 | 2.6666666666666665 | 3.3333333333333335 | 3.6666666666666665 |  |
| Test Results Aggregator | bash | sonnet46-200k-medium | 4.0 | 3.0 | 3.6666666666666665 | 3.6666666666666665 |  |
| Test Results Aggregator | default | opus46-200k-medium | 3.3333333333333335 | 3.0 | 3.0 | 3.0 |  |
| Test Results Aggregator | default | sonnet46-200k-medium | 3.3333333333333335 | 2.6666666666666665 | 3.6666666666666665 | 3.3333333333333335 |  |
| Test Results Aggregator | powershell | opus46-200k-medium | 3.3333333333333335 | 2.6666666666666665 | 3.3333333333333335 | 3.0 |  |
| Test Results Aggregator | powershell | sonnet46-200k-medium | 4.666666666666667 | 4.0 | 3.6666666666666665 | 3.6666666666666665 |  |
| Test Results Aggregator | typescript-bun | opus46-200k-medium | 3.6666666666666665 | 3.0 | 3.3333333333333335 | 3.3333333333333335 |  |
| Test Results Aggregator | typescript-bun | sonnet46-200k-medium | 4.666666666666667 | 4.333333333333333 | 4.666666666666667 | 4.666666666666667 |  |
| Environment Matrix Generator | bash | opus46-200k-medium | 4.0 | 3.5 | 3.5 | 3.5 |  |
| Environment Matrix Generator | bash | sonnet46-200k-medium | 4.0 | 3.6666666666666665 | 3.6666666666666665 | 4.0 |  |
| Environment Matrix Generator | default | opus46-200k-medium | 4.0 | 3.3333333333333335 | 3.6666666666666665 | 3.6666666666666665 |  |
| Environment Matrix Generator | default | sonnet46-200k-medium | 4.333333333333333 | 3.6666666666666665 | 4.333333333333333 | 3.6666666666666665 |  |
| Environment Matrix Generator | powershell | opus46-200k-medium | 3.3333333333333335 | 3.0 | 4.0 | 2.6666666666666665 |  |
| Environment Matrix Generator | powershell | sonnet46-200k-medium | 4.0 | 3.3333333333333335 | 4.0 | 4.0 |  |
| Environment Matrix Generator | typescript-bun | opus46-200k-medium | 3.3333333333333335 | 2.6666666666666665 | 3.0 | 3.0 |  |
| Environment Matrix Generator | typescript-bun | sonnet46-200k-medium | 3.6666666666666665 | 3.6666666666666665 | 3.6666666666666665 | 3.6666666666666665 |  |
| Artifact Cleanup Script | bash | opus46-200k-medium | 3.6666666666666665 | 3.3333333333333335 | 3.3333333333333335 | 3.3333333333333335 |  |
| Artifact Cleanup Script | bash | sonnet46-200k-medium | 3.6666666666666665 | 3.3333333333333335 | 4.0 | 3.3333333333333335 |  |
| Artifact Cleanup Script | default | opus46-200k-medium | 3.3333333333333335 | 3.0 | 3.3333333333333335 | 2.6666666666666665 |  |
| Artifact Cleanup Script | default | sonnet46-200k-medium | 3.6666666666666665 | 3.6666666666666665 | 4.0 | 3.6666666666666665 |  |
| Artifact Cleanup Script | powershell | opus46-200k-medium | 3.6666666666666665 | 3.6666666666666665 | 4.333333333333333 | 4.0 |  |
| Artifact Cleanup Script | powershell | sonnet46-200k-medium | 2.3333333333333335 | 2.6666666666666665 | 3.6666666666666665 | 2.3333333333333335 |  |
| Artifact Cleanup Script | typescript-bun | opus46-200k-medium | 4.0 | 4.333333333333333 | 4.666666666666667 | 3.6666666666666665 |  |
| Artifact Cleanup Script | typescript-bun | sonnet46-200k-medium | 3.0 | 3.6666666666666665 | 3.6666666666666665 | 2.6666666666666665 |  |
| Secret Rotation Validator | bash | opus46-200k-medium | 4.0 | 3.3333333333333335 | 3.3333333333333335 | 3.3333333333333335 |  |
| Secret Rotation Validator | bash | sonnet46-200k-medium | 3.6666666666666665 | 3.0 | 3.6666666666666665 | 3.3333333333333335 |  |
| Secret Rotation Validator | default | opus46-200k-medium | 4.0 | 3.6666666666666665 | 3.6666666666666665 | 3.6666666666666665 |  |
| Secret Rotation Validator | default | sonnet46-200k-medium | 4.333333333333333 | 3.6666666666666665 | 4.0 | 3.6666666666666665 |  |
| Secret Rotation Validator | powershell | opus46-200k-medium | 3.3333333333333335 | 2.6666666666666665 | 3.3333333333333335 | 3.3333333333333335 |  |
| Secret Rotation Validator | powershell | sonnet46-200k-medium | 4.0 | 3.6666666666666665 | 4.333333333333333 | 3.6666666666666665 |  |
| Secret Rotation Validator | typescript-bun | opus46-200k-medium | 3.6666666666666665 | 3.3333333333333335 | 4.0 | 3.6666666666666665 |  |
| Secret Rotation Validator | typescript-bun | sonnet46-200k-medium | 4.333333333333333 | 4.0 | 4.333333333333333 | 4.0 |  |

</details>

### Correlation: Structural Metrics vs Tests Quality

Spearman rank correlation between automated counts and LLM judge scores.
Values near +1.0 indicate the LLM agrees with the structural signal; near 0 means no relationship.

| Structural Metric | vs Coverage | vs Rigor | vs Design | vs Overall |
|-------------------|------------|---------|----------|-----------|
| Test count | 0.32 | 0.34 | 0.21 | 0.19 |
| Assertion count | 0.24 | 0.39 | 0.33 | 0.21 |
| Test:code ratio | -0.01 | 0.02 | -0.1 | -0.17 |

*Based on 64 runs with both structural and LLM scores.*

## Per-Run Results

*Tests Quality = Overall (1-5) from LLM-as-judge of generated test code (dimensions: coverage, rigor, design). `—` = no judge data.*

| Task | Language | Model | Duration | Turns | Errors | Cost | Tests Quality | Chosen | Status |
|------|----------|-------|----------|-------|--------|------|-----------|--------|--------|
| Artifact Cleanup Script | bash | opus46-200k-medium | 5.7min | 50 | 2 | $1.50 | 3.3 | bash | ok |
| Artifact Cleanup Script | bash | sonnet46-200k-medium | 7.2min | 35 | 1 | $0.77 | 3.3 | bash | ok |
| Artifact Cleanup Script | default | opus46-200k-medium | 9.2min | 49 | 2 | $2.19 | 2.7 | python | ok |
| Artifact Cleanup Script | default | sonnet46-200k-medium | 6.3min | 31 | 2 | $0.83 | 3.7 | python | ok |
| Artifact Cleanup Script | powershell | opus46-200k-medium | 5.4min | 29 | 2 | $1.07 | 4.0 | powershell | ok |
| Artifact Cleanup Script | powershell | sonnet46-200k-medium | 12.0min | 15 | 0 | $0.99 | 2.3 | powershell | ok |
| Artifact Cleanup Script | typescript-bun | opus46-200k-medium | 7.7min | 34 | 1 | $1.68 | 3.7 | typescript | ok |
| Artifact Cleanup Script | typescript-bun | sonnet46-200k-medium | 9.2min | 38 | 2 | $1.17 | 2.7 | typescript | ok |
| Dependency License Checker | bash | opus46-200k-medium | 6.9min | 55 | 3 | $1.50 | 4.0 | bash | ok |
| Dependency License Checker | bash | sonnet46-200k-medium | 14.1min | 42 | 3 | $1.68 | 3.7 | bash | ok |
| Dependency License Checker | default | opus46-200k-medium | 5.9min | 39 | 0 | $1.24 | 3.0 | python | ok |
| Dependency License Checker | default | sonnet46-200k-medium | 9.2min | 39 | 3 | $1.30 | 4.3 | python | ok |
| Dependency License Checker | powershell | opus46-200k-medium | 6.0min | 38 | 3 | $1.24 | 4.0 | powershell | ok |
| Dependency License Checker | powershell | sonnet46-200k-medium | 12.3min | 58 | 2 | $1.93 | 4.0 | powershell | ok |
| Dependency License Checker | typescript-bun | opus46-200k-medium | 6.8min | 48 | 3 | $1.35 | 3.7 | typescript | ok |
| Dependency License Checker | typescript-bun | sonnet46-200k-medium | 9.5min | 43 | 2 | $1.47 | 2.3 | typescript | ok |
| Docker Image Tag Generator | bash | opus46-200k-medium | 3.7min | 28 | 1 | $0.78 | 2.7 | bash | ok |
| Docker Image Tag Generator | bash | sonnet46-200k-medium | 4.5min | 26 | 2 | $0.61 | 4.3 | bash | ok |
| Docker Image Tag Generator | default | opus46-200k-medium | 5.5min | 27 | 2 | $1.25 | 4.0 | python | ok |
| Docker Image Tag Generator | default | sonnet46-200k-medium | 8.4min | 35 | 1 | $1.00 | 3.7 | python | ok |
| Docker Image Tag Generator | powershell | opus46-200k-medium | 7.9min | 24 | 0 | $1.39 | 3.3 | powershell | ok |
| Docker Image Tag Generator | powershell | sonnet46-200k-medium | 9.2min | 35 | 2 | $1.13 | 4.0 | powershell | ok |
| Docker Image Tag Generator | typescript-bun | opus46-200k-medium | 8.6min | 38 | 1 | $1.53 | 3.0 | typescript | ok |
| Docker Image Tag Generator | typescript-bun | sonnet46-200k-medium | 12.0min | 25 | 3 | $0.98 | 4.0 | typescript | ok |
| Environment Matrix Generator | bash | opus46-200k-medium | 4.1min | 42 | 1 | $0.98 | 3.5 | bash | ok |
| Environment Matrix Generator | bash | sonnet46-200k-medium | 10.5min | 25 | 3 | $1.22 | 4.0 | bash | ok |
| Environment Matrix Generator | default | opus46-200k-medium | 6.4min | 29 | 1 | $1.21 | 3.7 | python | ok |
| Environment Matrix Generator | default | sonnet46-200k-medium | 7.8min | 36 | 5 | $1.05 | 3.7 | python | ok |
| Environment Matrix Generator | powershell | opus46-200k-medium | 5.3min | 38 | 3 | $1.25 | 2.7 | powershell | ok |
| Environment Matrix Generator | powershell | sonnet46-200k-medium | 11.5min | 54 | 1 | $1.46 | 4.0 | powershell | ok |
| Environment Matrix Generator | typescript-bun | opus46-200k-medium | 6.0min | 42 | 3 | $1.10 | 3.0 | typescript | ok |
| Environment Matrix Generator | typescript-bun | sonnet46-200k-medium | 8.5min | 48 | 3 | $1.22 | 3.7 | typescript | ok |
| PR Label Assigner | bash | opus46-200k-medium | 5.6min | 42 | 2 | $1.16 | 2.0 | bash | ok |
| PR Label Assigner | bash | sonnet46-200k-medium | 13.2min | 39 | 6 | $1.73 | 4.3 | bash | ok |
| PR Label Assigner | default | opus46-200k-medium | 7.7min | 29 | 2 | $1.57 | 4.3 | python | ok |
| PR Label Assigner | default | sonnet46-200k-medium | 10.3min | 43 | 4 | $1.52 | 3.7 | python | ok |
| PR Label Assigner | powershell | opus46-200k-medium | 11.4min | 35 | 2 | $1.93 | 2.7 | powershell | ok |
| PR Label Assigner | powershell | sonnet46-200k-medium | 8.7min | 29 | 1 | $1.09 | 4.0 | powershell | ok |
| PR Label Assigner | typescript-bun | opus46-200k-medium | 5.1min | 33 | 2 | $1.01 | 3.0 | typescript | ok |
| PR Label Assigner | typescript-bun | sonnet46-200k-medium | 8.1min | 43 | 1 | $0.89 | 4.7 | typescript | ok |
| Secret Rotation Validator | bash | opus46-200k-medium | 7.8min | 38 | 1 | $1.78 | 3.3 | bash | ok |
| Secret Rotation Validator | bash | sonnet46-200k-medium | 15.6min | 78 | 8 | $2.60 | 3.3 | bash | ok |
| Secret Rotation Validator | default | opus46-200k-medium | 7.3min | 38 | 1 | $1.51 | 3.7 | python | ok |
| Secret Rotation Validator | default | sonnet46-200k-medium | 7.1min | 47 | 4 | $1.25 | 3.7 | python | ok |
| Secret Rotation Validator | powershell | opus46-200k-medium | 12.4min | 30 | 0 | $1.99 | 3.3 | powershell | ok |
| Secret Rotation Validator | powershell | sonnet46-200k-medium | 10.8min | 40 | 3 | $1.55 | 3.7 | powershell | ok |
| Secret Rotation Validator | typescript-bun | opus46-200k-medium | 8.1min | 56 | 4 | $1.79 | 3.7 | typescript | ok |
| Secret Rotation Validator | typescript-bun | sonnet46-200k-medium | 10.1min | 32 | 0 | $1.28 | 4.0 | typescript | ok |
| Semantic Version Bumper | bash | opus46-200k-medium | 12.4min | 50 | 1 | $1.65 | 3.7 | bash | ok |
| Semantic Version Bumper | bash | sonnet46-200k-medium | 9.0min | 57 | 6 | $1.38 | 3.7 | bash | ok |
| Semantic Version Bumper | default | opus46-200k-medium | 7.1min | 28 | 1 | $1.33 | 3.3 | python | ok |
| Semantic Version Bumper | default | sonnet46-200k-medium | 7.3min | 46 | 1 | $0.99 | 3.0 | python | ok |
| Semantic Version Bumper | powershell | opus46-200k-medium | 6.9min | 27 | 0 | $1.04 | 2.3 | powershell | ok |
| Semantic Version Bumper | powershell | sonnet46-200k-medium | 11.4min | 43 | 3 | $0.92 | 4.0 | powershell | ok |
| Semantic Version Bumper | typescript-bun | opus46-200k-medium | 10.3min | 32 | 1 | $1.54 | 2.7 | typescript | ok |
| Semantic Version Bumper | typescript-bun | sonnet46-200k-medium | 8.1min | 30 | 1 | $0.97 | 3.7 | typescript | ok |
| Test Results Aggregator | bash | opus46-200k-medium | 15.8min | 42 | 2 | $2.85 | 3.7 | bash | ok |
| Test Results Aggregator | bash | sonnet46-200k-medium | 9.0min | 31 | 3 | $1.22 | 3.7 | bash | ok |
| Test Results Aggregator | default | opus46-200k-medium | 5.7min | 35 | 3 | $1.27 | 3.0 | python | ok |
| Test Results Aggregator | default | sonnet46-200k-medium | 9.9min | 24 | 2 | $1.20 | 3.3 | python | ok |
| Test Results Aggregator | powershell | opus46-200k-medium | 10.0min | 48 | 2 | $2.45 | 3.0 | powershell | ok |
| Test Results Aggregator | powershell | sonnet46-200k-medium | 11.8min | 29 | 1 | $1.36 | 3.7 | powershell | ok |
| Test Results Aggregator | typescript-bun | opus46-200k-medium | 2.3min | 29 | 1 | $0.61 | 3.3 | typescript | ok |
| Test Results Aggregator | typescript-bun | sonnet46-200k-medium | 10.9min | 35 | 1 | $1.41 | 4.7 | typescript | ok |


<details>
<summary>Sorted by cost (cheapest first)</summary>

| Task | Language | Model | Duration | Turns | Errors | Cost | Tests Quality | Chosen | Status |
|------|----------|-------|----------|-------|--------|------|-----------|--------|--------|
| Docker Image Tag Generator | bash | sonnet46-200k-medium | 4.5min | 26 | 2 | $0.61 | 4.3 | bash | ok |
| Test Results Aggregator | typescript-bun | opus46-200k-medium | 2.3min | 29 | 1 | $0.61 | 3.3 | typescript | ok |
| Artifact Cleanup Script | bash | sonnet46-200k-medium | 7.2min | 35 | 1 | $0.77 | 3.3 | bash | ok |
| Docker Image Tag Generator | bash | opus46-200k-medium | 3.7min | 28 | 1 | $0.78 | 2.7 | bash | ok |
| Artifact Cleanup Script | default | sonnet46-200k-medium | 6.3min | 31 | 2 | $0.83 | 3.7 | python | ok |
| PR Label Assigner | typescript-bun | sonnet46-200k-medium | 8.1min | 43 | 1 | $0.89 | 4.7 | typescript | ok |
| Semantic Version Bumper | powershell | sonnet46-200k-medium | 11.4min | 43 | 3 | $0.92 | 4.0 | powershell | ok |
| Semantic Version Bumper | typescript-bun | sonnet46-200k-medium | 8.1min | 30 | 1 | $0.97 | 3.7 | typescript | ok |
| Environment Matrix Generator | bash | opus46-200k-medium | 4.1min | 42 | 1 | $0.98 | 3.5 | bash | ok |
| Docker Image Tag Generator | typescript-bun | sonnet46-200k-medium | 12.0min | 25 | 3 | $0.98 | 4.0 | typescript | ok |
| Semantic Version Bumper | default | sonnet46-200k-medium | 7.3min | 46 | 1 | $0.99 | 3.0 | python | ok |
| Artifact Cleanup Script | powershell | sonnet46-200k-medium | 12.0min | 15 | 0 | $0.99 | 2.3 | powershell | ok |
| Docker Image Tag Generator | default | sonnet46-200k-medium | 8.4min | 35 | 1 | $1.00 | 3.7 | python | ok |
| PR Label Assigner | typescript-bun | opus46-200k-medium | 5.1min | 33 | 2 | $1.01 | 3.0 | typescript | ok |
| Semantic Version Bumper | powershell | opus46-200k-medium | 6.9min | 27 | 0 | $1.04 | 2.3 | powershell | ok |
| Environment Matrix Generator | default | sonnet46-200k-medium | 7.8min | 36 | 5 | $1.05 | 3.7 | python | ok |
| Artifact Cleanup Script | powershell | opus46-200k-medium | 5.4min | 29 | 2 | $1.07 | 4.0 | powershell | ok |
| PR Label Assigner | powershell | sonnet46-200k-medium | 8.7min | 29 | 1 | $1.09 | 4.0 | powershell | ok |
| Environment Matrix Generator | typescript-bun | opus46-200k-medium | 6.0min | 42 | 3 | $1.10 | 3.0 | typescript | ok |
| Docker Image Tag Generator | powershell | sonnet46-200k-medium | 9.2min | 35 | 2 | $1.13 | 4.0 | powershell | ok |
| PR Label Assigner | bash | opus46-200k-medium | 5.6min | 42 | 2 | $1.16 | 2.0 | bash | ok |
| Artifact Cleanup Script | typescript-bun | sonnet46-200k-medium | 9.2min | 38 | 2 | $1.17 | 2.7 | typescript | ok |
| Test Results Aggregator | default | sonnet46-200k-medium | 9.9min | 24 | 2 | $1.20 | 3.3 | python | ok |
| Environment Matrix Generator | default | opus46-200k-medium | 6.4min | 29 | 1 | $1.21 | 3.7 | python | ok |
| Test Results Aggregator | bash | sonnet46-200k-medium | 9.0min | 31 | 3 | $1.22 | 3.7 | bash | ok |
| Environment Matrix Generator | typescript-bun | sonnet46-200k-medium | 8.5min | 48 | 3 | $1.22 | 3.7 | typescript | ok |
| Environment Matrix Generator | bash | sonnet46-200k-medium | 10.5min | 25 | 3 | $1.22 | 4.0 | bash | ok |
| Dependency License Checker | powershell | opus46-200k-medium | 6.0min | 38 | 3 | $1.24 | 4.0 | powershell | ok |
| Dependency License Checker | default | opus46-200k-medium | 5.9min | 39 | 0 | $1.24 | 3.0 | python | ok |
| Secret Rotation Validator | default | sonnet46-200k-medium | 7.1min | 47 | 4 | $1.25 | 3.7 | python | ok |
| Environment Matrix Generator | powershell | opus46-200k-medium | 5.3min | 38 | 3 | $1.25 | 2.7 | powershell | ok |
| Docker Image Tag Generator | default | opus46-200k-medium | 5.5min | 27 | 2 | $1.25 | 4.0 | python | ok |
| Test Results Aggregator | default | opus46-200k-medium | 5.7min | 35 | 3 | $1.27 | 3.0 | python | ok |
| Secret Rotation Validator | typescript-bun | sonnet46-200k-medium | 10.1min | 32 | 0 | $1.28 | 4.0 | typescript | ok |
| Dependency License Checker | default | sonnet46-200k-medium | 9.2min | 39 | 3 | $1.30 | 4.3 | python | ok |
| Semantic Version Bumper | default | opus46-200k-medium | 7.1min | 28 | 1 | $1.33 | 3.3 | python | ok |
| Dependency License Checker | typescript-bun | opus46-200k-medium | 6.8min | 48 | 3 | $1.35 | 3.7 | typescript | ok |
| Test Results Aggregator | powershell | sonnet46-200k-medium | 11.8min | 29 | 1 | $1.36 | 3.7 | powershell | ok |
| Semantic Version Bumper | bash | sonnet46-200k-medium | 9.0min | 57 | 6 | $1.38 | 3.7 | bash | ok |
| Docker Image Tag Generator | powershell | opus46-200k-medium | 7.9min | 24 | 0 | $1.39 | 3.3 | powershell | ok |
| Test Results Aggregator | typescript-bun | sonnet46-200k-medium | 10.9min | 35 | 1 | $1.41 | 4.7 | typescript | ok |
| Environment Matrix Generator | powershell | sonnet46-200k-medium | 11.5min | 54 | 1 | $1.46 | 4.0 | powershell | ok |
| Dependency License Checker | typescript-bun | sonnet46-200k-medium | 9.5min | 43 | 2 | $1.47 | 2.3 | typescript | ok |
| Dependency License Checker | bash | opus46-200k-medium | 6.9min | 55 | 3 | $1.50 | 4.0 | bash | ok |
| Artifact Cleanup Script | bash | opus46-200k-medium | 5.7min | 50 | 2 | $1.50 | 3.3 | bash | ok |
| Secret Rotation Validator | default | opus46-200k-medium | 7.3min | 38 | 1 | $1.51 | 3.7 | python | ok |
| PR Label Assigner | default | sonnet46-200k-medium | 10.3min | 43 | 4 | $1.52 | 3.7 | python | ok |
| Docker Image Tag Generator | typescript-bun | opus46-200k-medium | 8.6min | 38 | 1 | $1.53 | 3.0 | typescript | ok |
| Semantic Version Bumper | typescript-bun | opus46-200k-medium | 10.3min | 32 | 1 | $1.54 | 2.7 | typescript | ok |
| Secret Rotation Validator | powershell | sonnet46-200k-medium | 10.8min | 40 | 3 | $1.55 | 3.7 | powershell | ok |
| PR Label Assigner | default | opus46-200k-medium | 7.7min | 29 | 2 | $1.57 | 4.3 | python | ok |
| Semantic Version Bumper | bash | opus46-200k-medium | 12.4min | 50 | 1 | $1.65 | 3.7 | bash | ok |
| Artifact Cleanup Script | typescript-bun | opus46-200k-medium | 7.7min | 34 | 1 | $1.68 | 3.7 | typescript | ok |
| Dependency License Checker | bash | sonnet46-200k-medium | 14.1min | 42 | 3 | $1.68 | 3.7 | bash | ok |
| PR Label Assigner | bash | sonnet46-200k-medium | 13.2min | 39 | 6 | $1.73 | 4.3 | bash | ok |
| Secret Rotation Validator | bash | opus46-200k-medium | 7.8min | 38 | 1 | $1.78 | 3.3 | bash | ok |
| Secret Rotation Validator | typescript-bun | opus46-200k-medium | 8.1min | 56 | 4 | $1.79 | 3.7 | typescript | ok |
| Dependency License Checker | powershell | sonnet46-200k-medium | 12.3min | 58 | 2 | $1.93 | 4.0 | powershell | ok |
| PR Label Assigner | powershell | opus46-200k-medium | 11.4min | 35 | 2 | $1.93 | 2.7 | powershell | ok |
| Secret Rotation Validator | powershell | opus46-200k-medium | 12.4min | 30 | 0 | $1.99 | 3.3 | powershell | ok |
| Artifact Cleanup Script | default | opus46-200k-medium | 9.2min | 49 | 2 | $2.19 | 2.7 | python | ok |
| Test Results Aggregator | powershell | opus46-200k-medium | 10.0min | 48 | 2 | $2.45 | 3.0 | powershell | ok |
| Secret Rotation Validator | bash | sonnet46-200k-medium | 15.6min | 78 | 8 | $2.60 | 3.3 | bash | ok |
| Test Results Aggregator | bash | opus46-200k-medium | 15.8min | 42 | 2 | $2.85 | 3.7 | bash | ok |

</details>

<details>
<summary>Sorted by duration (fastest first)</summary>

| Task | Language | Model | Duration | Turns | Errors | Cost | Tests Quality | Chosen | Status |
|------|----------|-------|----------|-------|--------|------|-----------|--------|--------|
| Test Results Aggregator | typescript-bun | opus46-200k-medium | 2.3min | 29 | 1 | $0.61 | 3.3 | typescript | ok |
| Docker Image Tag Generator | bash | opus46-200k-medium | 3.7min | 28 | 1 | $0.78 | 2.7 | bash | ok |
| Environment Matrix Generator | bash | opus46-200k-medium | 4.1min | 42 | 1 | $0.98 | 3.5 | bash | ok |
| Docker Image Tag Generator | bash | sonnet46-200k-medium | 4.5min | 26 | 2 | $0.61 | 4.3 | bash | ok |
| PR Label Assigner | typescript-bun | opus46-200k-medium | 5.1min | 33 | 2 | $1.01 | 3.0 | typescript | ok |
| Environment Matrix Generator | powershell | opus46-200k-medium | 5.3min | 38 | 3 | $1.25 | 2.7 | powershell | ok |
| Artifact Cleanup Script | powershell | opus46-200k-medium | 5.4min | 29 | 2 | $1.07 | 4.0 | powershell | ok |
| Docker Image Tag Generator | default | opus46-200k-medium | 5.5min | 27 | 2 | $1.25 | 4.0 | python | ok |
| PR Label Assigner | bash | opus46-200k-medium | 5.6min | 42 | 2 | $1.16 | 2.0 | bash | ok |
| Artifact Cleanup Script | bash | opus46-200k-medium | 5.7min | 50 | 2 | $1.50 | 3.3 | bash | ok |
| Test Results Aggregator | default | opus46-200k-medium | 5.7min | 35 | 3 | $1.27 | 3.0 | python | ok |
| Dependency License Checker | default | opus46-200k-medium | 5.9min | 39 | 0 | $1.24 | 3.0 | python | ok |
| Environment Matrix Generator | typescript-bun | opus46-200k-medium | 6.0min | 42 | 3 | $1.10 | 3.0 | typescript | ok |
| Dependency License Checker | powershell | opus46-200k-medium | 6.0min | 38 | 3 | $1.24 | 4.0 | powershell | ok |
| Artifact Cleanup Script | default | sonnet46-200k-medium | 6.3min | 31 | 2 | $0.83 | 3.7 | python | ok |
| Environment Matrix Generator | default | opus46-200k-medium | 6.4min | 29 | 1 | $1.21 | 3.7 | python | ok |
| Dependency License Checker | typescript-bun | opus46-200k-medium | 6.8min | 48 | 3 | $1.35 | 3.7 | typescript | ok |
| Dependency License Checker | bash | opus46-200k-medium | 6.9min | 55 | 3 | $1.50 | 4.0 | bash | ok |
| Semantic Version Bumper | powershell | opus46-200k-medium | 6.9min | 27 | 0 | $1.04 | 2.3 | powershell | ok |
| Secret Rotation Validator | default | sonnet46-200k-medium | 7.1min | 47 | 4 | $1.25 | 3.7 | python | ok |
| Semantic Version Bumper | default | opus46-200k-medium | 7.1min | 28 | 1 | $1.33 | 3.3 | python | ok |
| Artifact Cleanup Script | bash | sonnet46-200k-medium | 7.2min | 35 | 1 | $0.77 | 3.3 | bash | ok |
| Secret Rotation Validator | default | opus46-200k-medium | 7.3min | 38 | 1 | $1.51 | 3.7 | python | ok |
| Semantic Version Bumper | default | sonnet46-200k-medium | 7.3min | 46 | 1 | $0.99 | 3.0 | python | ok |
| Artifact Cleanup Script | typescript-bun | opus46-200k-medium | 7.7min | 34 | 1 | $1.68 | 3.7 | typescript | ok |
| PR Label Assigner | default | opus46-200k-medium | 7.7min | 29 | 2 | $1.57 | 4.3 | python | ok |
| Secret Rotation Validator | bash | opus46-200k-medium | 7.8min | 38 | 1 | $1.78 | 3.3 | bash | ok |
| Environment Matrix Generator | default | sonnet46-200k-medium | 7.8min | 36 | 5 | $1.05 | 3.7 | python | ok |
| Docker Image Tag Generator | powershell | opus46-200k-medium | 7.9min | 24 | 0 | $1.39 | 3.3 | powershell | ok |
| Semantic Version Bumper | typescript-bun | sonnet46-200k-medium | 8.1min | 30 | 1 | $0.97 | 3.7 | typescript | ok |
| Secret Rotation Validator | typescript-bun | opus46-200k-medium | 8.1min | 56 | 4 | $1.79 | 3.7 | typescript | ok |
| PR Label Assigner | typescript-bun | sonnet46-200k-medium | 8.1min | 43 | 1 | $0.89 | 4.7 | typescript | ok |
| Docker Image Tag Generator | default | sonnet46-200k-medium | 8.4min | 35 | 1 | $1.00 | 3.7 | python | ok |
| Environment Matrix Generator | typescript-bun | sonnet46-200k-medium | 8.5min | 48 | 3 | $1.22 | 3.7 | typescript | ok |
| Docker Image Tag Generator | typescript-bun | opus46-200k-medium | 8.6min | 38 | 1 | $1.53 | 3.0 | typescript | ok |
| PR Label Assigner | powershell | sonnet46-200k-medium | 8.7min | 29 | 1 | $1.09 | 4.0 | powershell | ok |
| Semantic Version Bumper | bash | sonnet46-200k-medium | 9.0min | 57 | 6 | $1.38 | 3.7 | bash | ok |
| Test Results Aggregator | bash | sonnet46-200k-medium | 9.0min | 31 | 3 | $1.22 | 3.7 | bash | ok |
| Docker Image Tag Generator | powershell | sonnet46-200k-medium | 9.2min | 35 | 2 | $1.13 | 4.0 | powershell | ok |
| Artifact Cleanup Script | typescript-bun | sonnet46-200k-medium | 9.2min | 38 | 2 | $1.17 | 2.7 | typescript | ok |
| Dependency License Checker | default | sonnet46-200k-medium | 9.2min | 39 | 3 | $1.30 | 4.3 | python | ok |
| Artifact Cleanup Script | default | opus46-200k-medium | 9.2min | 49 | 2 | $2.19 | 2.7 | python | ok |
| Dependency License Checker | typescript-bun | sonnet46-200k-medium | 9.5min | 43 | 2 | $1.47 | 2.3 | typescript | ok |
| Test Results Aggregator | default | sonnet46-200k-medium | 9.9min | 24 | 2 | $1.20 | 3.3 | python | ok |
| Test Results Aggregator | powershell | opus46-200k-medium | 10.0min | 48 | 2 | $2.45 | 3.0 | powershell | ok |
| Secret Rotation Validator | typescript-bun | sonnet46-200k-medium | 10.1min | 32 | 0 | $1.28 | 4.0 | typescript | ok |
| Semantic Version Bumper | typescript-bun | opus46-200k-medium | 10.3min | 32 | 1 | $1.54 | 2.7 | typescript | ok |
| PR Label Assigner | default | sonnet46-200k-medium | 10.3min | 43 | 4 | $1.52 | 3.7 | python | ok |
| Environment Matrix Generator | bash | sonnet46-200k-medium | 10.5min | 25 | 3 | $1.22 | 4.0 | bash | ok |
| Secret Rotation Validator | powershell | sonnet46-200k-medium | 10.8min | 40 | 3 | $1.55 | 3.7 | powershell | ok |
| Test Results Aggregator | typescript-bun | sonnet46-200k-medium | 10.9min | 35 | 1 | $1.41 | 4.7 | typescript | ok |
| PR Label Assigner | powershell | opus46-200k-medium | 11.4min | 35 | 2 | $1.93 | 2.7 | powershell | ok |
| Semantic Version Bumper | powershell | sonnet46-200k-medium | 11.4min | 43 | 3 | $0.92 | 4.0 | powershell | ok |
| Environment Matrix Generator | powershell | sonnet46-200k-medium | 11.5min | 54 | 1 | $1.46 | 4.0 | powershell | ok |
| Test Results Aggregator | powershell | sonnet46-200k-medium | 11.8min | 29 | 1 | $1.36 | 3.7 | powershell | ok |
| Docker Image Tag Generator | typescript-bun | sonnet46-200k-medium | 12.0min | 25 | 3 | $0.98 | 4.0 | typescript | ok |
| Artifact Cleanup Script | powershell | sonnet46-200k-medium | 12.0min | 15 | 0 | $0.99 | 2.3 | powershell | ok |
| Dependency License Checker | powershell | sonnet46-200k-medium | 12.3min | 58 | 2 | $1.93 | 4.0 | powershell | ok |
| Semantic Version Bumper | bash | opus46-200k-medium | 12.4min | 50 | 1 | $1.65 | 3.7 | bash | ok |
| Secret Rotation Validator | powershell | opus46-200k-medium | 12.4min | 30 | 0 | $1.99 | 3.3 | powershell | ok |
| PR Label Assigner | bash | sonnet46-200k-medium | 13.2min | 39 | 6 | $1.73 | 4.3 | bash | ok |
| Dependency License Checker | bash | sonnet46-200k-medium | 14.1min | 42 | 3 | $1.68 | 3.7 | bash | ok |
| Secret Rotation Validator | bash | sonnet46-200k-medium | 15.6min | 78 | 8 | $2.60 | 3.3 | bash | ok |
| Test Results Aggregator | bash | opus46-200k-medium | 15.8min | 42 | 2 | $2.85 | 3.7 | bash | ok |

</details>

<details>
<summary>Sorted by errors (fewest first)</summary>

| Task | Language | Model | Duration | Turns | Errors | Cost | Tests Quality | Chosen | Status |
|------|----------|-------|----------|-------|--------|------|-----------|--------|--------|
| Semantic Version Bumper | powershell | opus46-200k-medium | 6.9min | 27 | 0 | $1.04 | 2.3 | powershell | ok |
| Dependency License Checker | default | opus46-200k-medium | 5.9min | 39 | 0 | $1.24 | 3.0 | python | ok |
| Docker Image Tag Generator | powershell | opus46-200k-medium | 7.9min | 24 | 0 | $1.39 | 3.3 | powershell | ok |
| Artifact Cleanup Script | powershell | sonnet46-200k-medium | 12.0min | 15 | 0 | $0.99 | 2.3 | powershell | ok |
| Secret Rotation Validator | powershell | opus46-200k-medium | 12.4min | 30 | 0 | $1.99 | 3.3 | powershell | ok |
| Secret Rotation Validator | typescript-bun | sonnet46-200k-medium | 10.1min | 32 | 0 | $1.28 | 4.0 | typescript | ok |
| Semantic Version Bumper | bash | opus46-200k-medium | 12.4min | 50 | 1 | $1.65 | 3.7 | bash | ok |
| Semantic Version Bumper | default | opus46-200k-medium | 7.1min | 28 | 1 | $1.33 | 3.3 | python | ok |
| Semantic Version Bumper | default | sonnet46-200k-medium | 7.3min | 46 | 1 | $0.99 | 3.0 | python | ok |
| Semantic Version Bumper | typescript-bun | opus46-200k-medium | 10.3min | 32 | 1 | $1.54 | 2.7 | typescript | ok |
| Semantic Version Bumper | typescript-bun | sonnet46-200k-medium | 8.1min | 30 | 1 | $0.97 | 3.7 | typescript | ok |
| PR Label Assigner | powershell | sonnet46-200k-medium | 8.7min | 29 | 1 | $1.09 | 4.0 | powershell | ok |
| PR Label Assigner | typescript-bun | sonnet46-200k-medium | 8.1min | 43 | 1 | $0.89 | 4.7 | typescript | ok |
| Docker Image Tag Generator | bash | opus46-200k-medium | 3.7min | 28 | 1 | $0.78 | 2.7 | bash | ok |
| Docker Image Tag Generator | default | sonnet46-200k-medium | 8.4min | 35 | 1 | $1.00 | 3.7 | python | ok |
| Docker Image Tag Generator | typescript-bun | opus46-200k-medium | 8.6min | 38 | 1 | $1.53 | 3.0 | typescript | ok |
| Test Results Aggregator | powershell | sonnet46-200k-medium | 11.8min | 29 | 1 | $1.36 | 3.7 | powershell | ok |
| Test Results Aggregator | typescript-bun | opus46-200k-medium | 2.3min | 29 | 1 | $0.61 | 3.3 | typescript | ok |
| Test Results Aggregator | typescript-bun | sonnet46-200k-medium | 10.9min | 35 | 1 | $1.41 | 4.7 | typescript | ok |
| Environment Matrix Generator | bash | opus46-200k-medium | 4.1min | 42 | 1 | $0.98 | 3.5 | bash | ok |
| Environment Matrix Generator | default | opus46-200k-medium | 6.4min | 29 | 1 | $1.21 | 3.7 | python | ok |
| Environment Matrix Generator | powershell | sonnet46-200k-medium | 11.5min | 54 | 1 | $1.46 | 4.0 | powershell | ok |
| Artifact Cleanup Script | bash | sonnet46-200k-medium | 7.2min | 35 | 1 | $0.77 | 3.3 | bash | ok |
| Artifact Cleanup Script | typescript-bun | opus46-200k-medium | 7.7min | 34 | 1 | $1.68 | 3.7 | typescript | ok |
| Secret Rotation Validator | bash | opus46-200k-medium | 7.8min | 38 | 1 | $1.78 | 3.3 | bash | ok |
| Secret Rotation Validator | default | opus46-200k-medium | 7.3min | 38 | 1 | $1.51 | 3.7 | python | ok |
| PR Label Assigner | bash | opus46-200k-medium | 5.6min | 42 | 2 | $1.16 | 2.0 | bash | ok |
| PR Label Assigner | default | opus46-200k-medium | 7.7min | 29 | 2 | $1.57 | 4.3 | python | ok |
| PR Label Assigner | powershell | opus46-200k-medium | 11.4min | 35 | 2 | $1.93 | 2.7 | powershell | ok |
| PR Label Assigner | typescript-bun | opus46-200k-medium | 5.1min | 33 | 2 | $1.01 | 3.0 | typescript | ok |
| Dependency License Checker | powershell | sonnet46-200k-medium | 12.3min | 58 | 2 | $1.93 | 4.0 | powershell | ok |
| Dependency License Checker | typescript-bun | sonnet46-200k-medium | 9.5min | 43 | 2 | $1.47 | 2.3 | typescript | ok |
| Docker Image Tag Generator | bash | sonnet46-200k-medium | 4.5min | 26 | 2 | $0.61 | 4.3 | bash | ok |
| Docker Image Tag Generator | default | opus46-200k-medium | 5.5min | 27 | 2 | $1.25 | 4.0 | python | ok |
| Docker Image Tag Generator | powershell | sonnet46-200k-medium | 9.2min | 35 | 2 | $1.13 | 4.0 | powershell | ok |
| Test Results Aggregator | bash | opus46-200k-medium | 15.8min | 42 | 2 | $2.85 | 3.7 | bash | ok |
| Test Results Aggregator | default | sonnet46-200k-medium | 9.9min | 24 | 2 | $1.20 | 3.3 | python | ok |
| Test Results Aggregator | powershell | opus46-200k-medium | 10.0min | 48 | 2 | $2.45 | 3.0 | powershell | ok |
| Artifact Cleanup Script | bash | opus46-200k-medium | 5.7min | 50 | 2 | $1.50 | 3.3 | bash | ok |
| Artifact Cleanup Script | default | opus46-200k-medium | 9.2min | 49 | 2 | $2.19 | 2.7 | python | ok |
| Artifact Cleanup Script | default | sonnet46-200k-medium | 6.3min | 31 | 2 | $0.83 | 3.7 | python | ok |
| Artifact Cleanup Script | powershell | opus46-200k-medium | 5.4min | 29 | 2 | $1.07 | 4.0 | powershell | ok |
| Artifact Cleanup Script | typescript-bun | sonnet46-200k-medium | 9.2min | 38 | 2 | $1.17 | 2.7 | typescript | ok |
| Semantic Version Bumper | powershell | sonnet46-200k-medium | 11.4min | 43 | 3 | $0.92 | 4.0 | powershell | ok |
| Dependency License Checker | bash | opus46-200k-medium | 6.9min | 55 | 3 | $1.50 | 4.0 | bash | ok |
| Dependency License Checker | bash | sonnet46-200k-medium | 14.1min | 42 | 3 | $1.68 | 3.7 | bash | ok |
| Dependency License Checker | default | sonnet46-200k-medium | 9.2min | 39 | 3 | $1.30 | 4.3 | python | ok |
| Dependency License Checker | powershell | opus46-200k-medium | 6.0min | 38 | 3 | $1.24 | 4.0 | powershell | ok |
| Dependency License Checker | typescript-bun | opus46-200k-medium | 6.8min | 48 | 3 | $1.35 | 3.7 | typescript | ok |
| Docker Image Tag Generator | typescript-bun | sonnet46-200k-medium | 12.0min | 25 | 3 | $0.98 | 4.0 | typescript | ok |
| Test Results Aggregator | bash | sonnet46-200k-medium | 9.0min | 31 | 3 | $1.22 | 3.7 | bash | ok |
| Test Results Aggregator | default | opus46-200k-medium | 5.7min | 35 | 3 | $1.27 | 3.0 | python | ok |
| Environment Matrix Generator | bash | sonnet46-200k-medium | 10.5min | 25 | 3 | $1.22 | 4.0 | bash | ok |
| Environment Matrix Generator | powershell | opus46-200k-medium | 5.3min | 38 | 3 | $1.25 | 2.7 | powershell | ok |
| Environment Matrix Generator | typescript-bun | opus46-200k-medium | 6.0min | 42 | 3 | $1.10 | 3.0 | typescript | ok |
| Environment Matrix Generator | typescript-bun | sonnet46-200k-medium | 8.5min | 48 | 3 | $1.22 | 3.7 | typescript | ok |
| Secret Rotation Validator | powershell | sonnet46-200k-medium | 10.8min | 40 | 3 | $1.55 | 3.7 | powershell | ok |
| PR Label Assigner | default | sonnet46-200k-medium | 10.3min | 43 | 4 | $1.52 | 3.7 | python | ok |
| Secret Rotation Validator | default | sonnet46-200k-medium | 7.1min | 47 | 4 | $1.25 | 3.7 | python | ok |
| Secret Rotation Validator | typescript-bun | opus46-200k-medium | 8.1min | 56 | 4 | $1.79 | 3.7 | typescript | ok |
| Environment Matrix Generator | default | sonnet46-200k-medium | 7.8min | 36 | 5 | $1.05 | 3.7 | python | ok |
| Semantic Version Bumper | bash | sonnet46-200k-medium | 9.0min | 57 | 6 | $1.38 | 3.7 | bash | ok |
| PR Label Assigner | bash | sonnet46-200k-medium | 13.2min | 39 | 6 | $1.73 | 4.3 | bash | ok |
| Secret Rotation Validator | bash | sonnet46-200k-medium | 15.6min | 78 | 8 | $2.60 | 3.3 | bash | ok |

</details>

<details>
<summary>Sorted by turns (fewest first)</summary>

| Task | Language | Model | Duration | Turns | Errors | Cost | Tests Quality | Chosen | Status |
|------|----------|-------|----------|-------|--------|------|-----------|--------|--------|
| Artifact Cleanup Script | powershell | sonnet46-200k-medium | 12.0min | 15 | 0 | $0.99 | 2.3 | powershell | ok |
| Docker Image Tag Generator | powershell | opus46-200k-medium | 7.9min | 24 | 0 | $1.39 | 3.3 | powershell | ok |
| Test Results Aggregator | default | sonnet46-200k-medium | 9.9min | 24 | 2 | $1.20 | 3.3 | python | ok |
| Docker Image Tag Generator | typescript-bun | sonnet46-200k-medium | 12.0min | 25 | 3 | $0.98 | 4.0 | typescript | ok |
| Environment Matrix Generator | bash | sonnet46-200k-medium | 10.5min | 25 | 3 | $1.22 | 4.0 | bash | ok |
| Docker Image Tag Generator | bash | sonnet46-200k-medium | 4.5min | 26 | 2 | $0.61 | 4.3 | bash | ok |
| Semantic Version Bumper | powershell | opus46-200k-medium | 6.9min | 27 | 0 | $1.04 | 2.3 | powershell | ok |
| Docker Image Tag Generator | default | opus46-200k-medium | 5.5min | 27 | 2 | $1.25 | 4.0 | python | ok |
| Semantic Version Bumper | default | opus46-200k-medium | 7.1min | 28 | 1 | $1.33 | 3.3 | python | ok |
| Docker Image Tag Generator | bash | opus46-200k-medium | 3.7min | 28 | 1 | $0.78 | 2.7 | bash | ok |
| PR Label Assigner | default | opus46-200k-medium | 7.7min | 29 | 2 | $1.57 | 4.3 | python | ok |
| PR Label Assigner | powershell | sonnet46-200k-medium | 8.7min | 29 | 1 | $1.09 | 4.0 | powershell | ok |
| Test Results Aggregator | powershell | sonnet46-200k-medium | 11.8min | 29 | 1 | $1.36 | 3.7 | powershell | ok |
| Test Results Aggregator | typescript-bun | opus46-200k-medium | 2.3min | 29 | 1 | $0.61 | 3.3 | typescript | ok |
| Environment Matrix Generator | default | opus46-200k-medium | 6.4min | 29 | 1 | $1.21 | 3.7 | python | ok |
| Artifact Cleanup Script | powershell | opus46-200k-medium | 5.4min | 29 | 2 | $1.07 | 4.0 | powershell | ok |
| Semantic Version Bumper | typescript-bun | sonnet46-200k-medium | 8.1min | 30 | 1 | $0.97 | 3.7 | typescript | ok |
| Secret Rotation Validator | powershell | opus46-200k-medium | 12.4min | 30 | 0 | $1.99 | 3.3 | powershell | ok |
| Test Results Aggregator | bash | sonnet46-200k-medium | 9.0min | 31 | 3 | $1.22 | 3.7 | bash | ok |
| Artifact Cleanup Script | default | sonnet46-200k-medium | 6.3min | 31 | 2 | $0.83 | 3.7 | python | ok |
| Semantic Version Bumper | typescript-bun | opus46-200k-medium | 10.3min | 32 | 1 | $1.54 | 2.7 | typescript | ok |
| Secret Rotation Validator | typescript-bun | sonnet46-200k-medium | 10.1min | 32 | 0 | $1.28 | 4.0 | typescript | ok |
| PR Label Assigner | typescript-bun | opus46-200k-medium | 5.1min | 33 | 2 | $1.01 | 3.0 | typescript | ok |
| Artifact Cleanup Script | typescript-bun | opus46-200k-medium | 7.7min | 34 | 1 | $1.68 | 3.7 | typescript | ok |
| PR Label Assigner | powershell | opus46-200k-medium | 11.4min | 35 | 2 | $1.93 | 2.7 | powershell | ok |
| Docker Image Tag Generator | default | sonnet46-200k-medium | 8.4min | 35 | 1 | $1.00 | 3.7 | python | ok |
| Docker Image Tag Generator | powershell | sonnet46-200k-medium | 9.2min | 35 | 2 | $1.13 | 4.0 | powershell | ok |
| Test Results Aggregator | default | opus46-200k-medium | 5.7min | 35 | 3 | $1.27 | 3.0 | python | ok |
| Test Results Aggregator | typescript-bun | sonnet46-200k-medium | 10.9min | 35 | 1 | $1.41 | 4.7 | typescript | ok |
| Artifact Cleanup Script | bash | sonnet46-200k-medium | 7.2min | 35 | 1 | $0.77 | 3.3 | bash | ok |
| Environment Matrix Generator | default | sonnet46-200k-medium | 7.8min | 36 | 5 | $1.05 | 3.7 | python | ok |
| Dependency License Checker | powershell | opus46-200k-medium | 6.0min | 38 | 3 | $1.24 | 4.0 | powershell | ok |
| Docker Image Tag Generator | typescript-bun | opus46-200k-medium | 8.6min | 38 | 1 | $1.53 | 3.0 | typescript | ok |
| Environment Matrix Generator | powershell | opus46-200k-medium | 5.3min | 38 | 3 | $1.25 | 2.7 | powershell | ok |
| Artifact Cleanup Script | typescript-bun | sonnet46-200k-medium | 9.2min | 38 | 2 | $1.17 | 2.7 | typescript | ok |
| Secret Rotation Validator | bash | opus46-200k-medium | 7.8min | 38 | 1 | $1.78 | 3.3 | bash | ok |
| Secret Rotation Validator | default | opus46-200k-medium | 7.3min | 38 | 1 | $1.51 | 3.7 | python | ok |
| PR Label Assigner | bash | sonnet46-200k-medium | 13.2min | 39 | 6 | $1.73 | 4.3 | bash | ok |
| Dependency License Checker | default | opus46-200k-medium | 5.9min | 39 | 0 | $1.24 | 3.0 | python | ok |
| Dependency License Checker | default | sonnet46-200k-medium | 9.2min | 39 | 3 | $1.30 | 4.3 | python | ok |
| Secret Rotation Validator | powershell | sonnet46-200k-medium | 10.8min | 40 | 3 | $1.55 | 3.7 | powershell | ok |
| PR Label Assigner | bash | opus46-200k-medium | 5.6min | 42 | 2 | $1.16 | 2.0 | bash | ok |
| Dependency License Checker | bash | sonnet46-200k-medium | 14.1min | 42 | 3 | $1.68 | 3.7 | bash | ok |
| Test Results Aggregator | bash | opus46-200k-medium | 15.8min | 42 | 2 | $2.85 | 3.7 | bash | ok |
| Environment Matrix Generator | bash | opus46-200k-medium | 4.1min | 42 | 1 | $0.98 | 3.5 | bash | ok |
| Environment Matrix Generator | typescript-bun | opus46-200k-medium | 6.0min | 42 | 3 | $1.10 | 3.0 | typescript | ok |
| Semantic Version Bumper | powershell | sonnet46-200k-medium | 11.4min | 43 | 3 | $0.92 | 4.0 | powershell | ok |
| PR Label Assigner | default | sonnet46-200k-medium | 10.3min | 43 | 4 | $1.52 | 3.7 | python | ok |
| PR Label Assigner | typescript-bun | sonnet46-200k-medium | 8.1min | 43 | 1 | $0.89 | 4.7 | typescript | ok |
| Dependency License Checker | typescript-bun | sonnet46-200k-medium | 9.5min | 43 | 2 | $1.47 | 2.3 | typescript | ok |
| Semantic Version Bumper | default | sonnet46-200k-medium | 7.3min | 46 | 1 | $0.99 | 3.0 | python | ok |
| Secret Rotation Validator | default | sonnet46-200k-medium | 7.1min | 47 | 4 | $1.25 | 3.7 | python | ok |
| Dependency License Checker | typescript-bun | opus46-200k-medium | 6.8min | 48 | 3 | $1.35 | 3.7 | typescript | ok |
| Test Results Aggregator | powershell | opus46-200k-medium | 10.0min | 48 | 2 | $2.45 | 3.0 | powershell | ok |
| Environment Matrix Generator | typescript-bun | sonnet46-200k-medium | 8.5min | 48 | 3 | $1.22 | 3.7 | typescript | ok |
| Artifact Cleanup Script | default | opus46-200k-medium | 9.2min | 49 | 2 | $2.19 | 2.7 | python | ok |
| Semantic Version Bumper | bash | opus46-200k-medium | 12.4min | 50 | 1 | $1.65 | 3.7 | bash | ok |
| Artifact Cleanup Script | bash | opus46-200k-medium | 5.7min | 50 | 2 | $1.50 | 3.3 | bash | ok |
| Environment Matrix Generator | powershell | sonnet46-200k-medium | 11.5min | 54 | 1 | $1.46 | 4.0 | powershell | ok |
| Dependency License Checker | bash | opus46-200k-medium | 6.9min | 55 | 3 | $1.50 | 4.0 | bash | ok |
| Secret Rotation Validator | typescript-bun | opus46-200k-medium | 8.1min | 56 | 4 | $1.79 | 3.7 | typescript | ok |
| Semantic Version Bumper | bash | sonnet46-200k-medium | 9.0min | 57 | 6 | $1.38 | 3.7 | bash | ok |
| Dependency License Checker | powershell | sonnet46-200k-medium | 12.3min | 58 | 2 | $1.93 | 4.0 | powershell | ok |
| Secret Rotation Validator | bash | sonnet46-200k-medium | 15.6min | 78 | 8 | $2.60 | 3.3 | bash | ok |

</details>

<details>
<summary>Sorted by LLM-as-judge score (best first)</summary>

| Task | Language | Model | Duration | Turns | Errors | Cost | Tests Quality | Chosen | Status |
|------|----------|-------|----------|-------|--------|------|-----------|--------|--------|
| PR Label Assigner | typescript-bun | sonnet46-200k-medium | 8.1min | 43 | 1 | $0.89 | 4.7 | typescript | ok |
| Test Results Aggregator | typescript-bun | sonnet46-200k-medium | 10.9min | 35 | 1 | $1.41 | 4.7 | typescript | ok |
| PR Label Assigner | bash | sonnet46-200k-medium | 13.2min | 39 | 6 | $1.73 | 4.3 | bash | ok |
| PR Label Assigner | default | opus46-200k-medium | 7.7min | 29 | 2 | $1.57 | 4.3 | python | ok |
| Dependency License Checker | default | sonnet46-200k-medium | 9.2min | 39 | 3 | $1.30 | 4.3 | python | ok |
| Docker Image Tag Generator | bash | sonnet46-200k-medium | 4.5min | 26 | 2 | $0.61 | 4.3 | bash | ok |
| Semantic Version Bumper | powershell | sonnet46-200k-medium | 11.4min | 43 | 3 | $0.92 | 4.0 | powershell | ok |
| PR Label Assigner | powershell | sonnet46-200k-medium | 8.7min | 29 | 1 | $1.09 | 4.0 | powershell | ok |
| Dependency License Checker | bash | opus46-200k-medium | 6.9min | 55 | 3 | $1.50 | 4.0 | bash | ok |
| Dependency License Checker | powershell | opus46-200k-medium | 6.0min | 38 | 3 | $1.24 | 4.0 | powershell | ok |
| Dependency License Checker | powershell | sonnet46-200k-medium | 12.3min | 58 | 2 | $1.93 | 4.0 | powershell | ok |
| Docker Image Tag Generator | default | opus46-200k-medium | 5.5min | 27 | 2 | $1.25 | 4.0 | python | ok |
| Docker Image Tag Generator | powershell | sonnet46-200k-medium | 9.2min | 35 | 2 | $1.13 | 4.0 | powershell | ok |
| Docker Image Tag Generator | typescript-bun | sonnet46-200k-medium | 12.0min | 25 | 3 | $0.98 | 4.0 | typescript | ok |
| Environment Matrix Generator | bash | sonnet46-200k-medium | 10.5min | 25 | 3 | $1.22 | 4.0 | bash | ok |
| Environment Matrix Generator | powershell | sonnet46-200k-medium | 11.5min | 54 | 1 | $1.46 | 4.0 | powershell | ok |
| Artifact Cleanup Script | powershell | opus46-200k-medium | 5.4min | 29 | 2 | $1.07 | 4.0 | powershell | ok |
| Secret Rotation Validator | typescript-bun | sonnet46-200k-medium | 10.1min | 32 | 0 | $1.28 | 4.0 | typescript | ok |
| Semantic Version Bumper | bash | opus46-200k-medium | 12.4min | 50 | 1 | $1.65 | 3.7 | bash | ok |
| Semantic Version Bumper | bash | sonnet46-200k-medium | 9.0min | 57 | 6 | $1.38 | 3.7 | bash | ok |
| Semantic Version Bumper | typescript-bun | sonnet46-200k-medium | 8.1min | 30 | 1 | $0.97 | 3.7 | typescript | ok |
| PR Label Assigner | default | sonnet46-200k-medium | 10.3min | 43 | 4 | $1.52 | 3.7 | python | ok |
| Dependency License Checker | bash | sonnet46-200k-medium | 14.1min | 42 | 3 | $1.68 | 3.7 | bash | ok |
| Dependency License Checker | typescript-bun | opus46-200k-medium | 6.8min | 48 | 3 | $1.35 | 3.7 | typescript | ok |
| Docker Image Tag Generator | default | sonnet46-200k-medium | 8.4min | 35 | 1 | $1.00 | 3.7 | python | ok |
| Test Results Aggregator | bash | opus46-200k-medium | 15.8min | 42 | 2 | $2.85 | 3.7 | bash | ok |
| Test Results Aggregator | bash | sonnet46-200k-medium | 9.0min | 31 | 3 | $1.22 | 3.7 | bash | ok |
| Test Results Aggregator | powershell | sonnet46-200k-medium | 11.8min | 29 | 1 | $1.36 | 3.7 | powershell | ok |
| Environment Matrix Generator | default | opus46-200k-medium | 6.4min | 29 | 1 | $1.21 | 3.7 | python | ok |
| Environment Matrix Generator | default | sonnet46-200k-medium | 7.8min | 36 | 5 | $1.05 | 3.7 | python | ok |
| Environment Matrix Generator | typescript-bun | sonnet46-200k-medium | 8.5min | 48 | 3 | $1.22 | 3.7 | typescript | ok |
| Artifact Cleanup Script | default | sonnet46-200k-medium | 6.3min | 31 | 2 | $0.83 | 3.7 | python | ok |
| Artifact Cleanup Script | typescript-bun | opus46-200k-medium | 7.7min | 34 | 1 | $1.68 | 3.7 | typescript | ok |
| Secret Rotation Validator | default | opus46-200k-medium | 7.3min | 38 | 1 | $1.51 | 3.7 | python | ok |
| Secret Rotation Validator | default | sonnet46-200k-medium | 7.1min | 47 | 4 | $1.25 | 3.7 | python | ok |
| Secret Rotation Validator | powershell | sonnet46-200k-medium | 10.8min | 40 | 3 | $1.55 | 3.7 | powershell | ok |
| Secret Rotation Validator | typescript-bun | opus46-200k-medium | 8.1min | 56 | 4 | $1.79 | 3.7 | typescript | ok |
| Environment Matrix Generator | bash | opus46-200k-medium | 4.1min | 42 | 1 | $0.98 | 3.5 | bash | ok |
| Semantic Version Bumper | default | opus46-200k-medium | 7.1min | 28 | 1 | $1.33 | 3.3 | python | ok |
| Docker Image Tag Generator | powershell | opus46-200k-medium | 7.9min | 24 | 0 | $1.39 | 3.3 | powershell | ok |
| Test Results Aggregator | default | sonnet46-200k-medium | 9.9min | 24 | 2 | $1.20 | 3.3 | python | ok |
| Test Results Aggregator | typescript-bun | opus46-200k-medium | 2.3min | 29 | 1 | $0.61 | 3.3 | typescript | ok |
| Artifact Cleanup Script | bash | opus46-200k-medium | 5.7min | 50 | 2 | $1.50 | 3.3 | bash | ok |
| Artifact Cleanup Script | bash | sonnet46-200k-medium | 7.2min | 35 | 1 | $0.77 | 3.3 | bash | ok |
| Secret Rotation Validator | bash | opus46-200k-medium | 7.8min | 38 | 1 | $1.78 | 3.3 | bash | ok |
| Secret Rotation Validator | bash | sonnet46-200k-medium | 15.6min | 78 | 8 | $2.60 | 3.3 | bash | ok |
| Secret Rotation Validator | powershell | opus46-200k-medium | 12.4min | 30 | 0 | $1.99 | 3.3 | powershell | ok |
| Semantic Version Bumper | default | sonnet46-200k-medium | 7.3min | 46 | 1 | $0.99 | 3.0 | python | ok |
| PR Label Assigner | typescript-bun | opus46-200k-medium | 5.1min | 33 | 2 | $1.01 | 3.0 | typescript | ok |
| Dependency License Checker | default | opus46-200k-medium | 5.9min | 39 | 0 | $1.24 | 3.0 | python | ok |
| Docker Image Tag Generator | typescript-bun | opus46-200k-medium | 8.6min | 38 | 1 | $1.53 | 3.0 | typescript | ok |
| Test Results Aggregator | default | opus46-200k-medium | 5.7min | 35 | 3 | $1.27 | 3.0 | python | ok |
| Test Results Aggregator | powershell | opus46-200k-medium | 10.0min | 48 | 2 | $2.45 | 3.0 | powershell | ok |
| Environment Matrix Generator | typescript-bun | opus46-200k-medium | 6.0min | 42 | 3 | $1.10 | 3.0 | typescript | ok |
| Semantic Version Bumper | typescript-bun | opus46-200k-medium | 10.3min | 32 | 1 | $1.54 | 2.7 | typescript | ok |
| PR Label Assigner | powershell | opus46-200k-medium | 11.4min | 35 | 2 | $1.93 | 2.7 | powershell | ok |
| Docker Image Tag Generator | bash | opus46-200k-medium | 3.7min | 28 | 1 | $0.78 | 2.7 | bash | ok |
| Environment Matrix Generator | powershell | opus46-200k-medium | 5.3min | 38 | 3 | $1.25 | 2.7 | powershell | ok |
| Artifact Cleanup Script | default | opus46-200k-medium | 9.2min | 49 | 2 | $2.19 | 2.7 | python | ok |
| Artifact Cleanup Script | typescript-bun | sonnet46-200k-medium | 9.2min | 38 | 2 | $1.17 | 2.7 | typescript | ok |
| Semantic Version Bumper | powershell | opus46-200k-medium | 6.9min | 27 | 0 | $1.04 | 2.3 | powershell | ok |
| Dependency License Checker | typescript-bun | sonnet46-200k-medium | 9.5min | 43 | 2 | $1.47 | 2.3 | typescript | ok |
| Artifact Cleanup Script | powershell | sonnet46-200k-medium | 12.0min | 15 | 0 | $0.99 | 2.3 | powershell | ok |
| PR Label Assigner | bash | opus46-200k-medium | 5.6min | 42 | 2 | $1.16 | 2.0 | bash | ok |

</details>

## Notes

### Tiers

- **Duration bands:** **A+** ≤1.04×, **A** ≤1.08×, **A-** ≤1.12×, **B+** ≤1.17×, **B** ≤1.22×, **B-** ≤1.27×, **C+** ≤1.32×, **C** ≤1.37×, **C-** ≤1.42×, **D+** ≤1.48×, **D** ≤1.54×, **D-** ≤1.60×, **F** >1.60×
- **Cost bands:** **A+** ≤1.03×, **A** ≤1.05×, **A-** ≤1.08×, **B+** ≤1.11×, **B** ≤1.13×, **B-** ≤1.16×, **C+** ≤1.19×, **C** ≤1.22×, **C-** ≤1.25×, **D+** ≤1.29×, **D** ≤1.32×, **D-** ≤1.35×, **F** >1.35×

*Tests/Workflow Craft bands are absolute Overall score bands:* **A+** ≥4.7, **A** ≥4.4, **A-** ≥4.1, **B+** ≥3.8, **B** ≥3.5, **B-** ≥3.2, **C+** ≥2.9, **C** ≥2.6, **C-** ≥2.3, **D+** ≥2.0, **D** ≥1.7, **D-** ≥1.4, **F** <1.4, `—` = no data.*

### CLI Version Legend

| Variant label | CLI version | Tasks | Languages |
|---------------|-------------|-------|-----------|
| opus46-200k-medium | 2.1.100 | 18-secret-rotation-validator | bash, typescript-bun |
| opus46-200k-medium | 2.1.97 | 11-semantic-version-bumper | default |
| opus46-200k-medium | 2.1.98 | All | All |
| sonnet46-200k-medium | 2.1.100 | 18-secret-rotation-validator | All |
| sonnet46-200k-medium | 2.1.98 | 11-semantic-version-bumper, 12-pr-label-assigner, 13-dependency-license-checker, 14-docker-image-tag-generator, 15-test-results-aggregator, 16-environment-matrix-generator, 17-artifact-cleanup-script | All |

### Judge Consistency Summary

**🟡 The panel is doing its main job:** Both judges rank Sonnet above Opus on every axis with zero pair-wise reversals, and no reversal anywhere lines up with a judge's own model family — so the model-comparison verdict is trustworthy. But language rankings on Tests Quality fully invert between the two judges (Spearman -1.00), so any language-only claim needs care.

- 👀 **Where to look closer:** Bash is the pivot — Gemini rates it best on Tests Quality (mean 4.62) while Haiku rates it worst (mean 2.47). Spot-check the widest bash hotspots (3-point gaps on the 1–5 scale): 11-semantic-version-bumper / bash / opus and 18-secret-rotation-validator / bash / opus, both scored 2 by Haiku and 5 by Gemini.
- 🤓 **Surprise finding:** Gemini's scores compress into a narrow 4.25–5.00 band, so the big gaps come from Gemini's ceiling meeting Haiku's full-range use — not from Haiku punishing any specific family, including its own.
- ℹ️ **Recommended next step:** Lead with the model-axis ranking; footnote language rankings with the Tests Quality reversal and re-score the bash hotspots with a tie-breaker judge.

#### Provenance

- **Model:** `claude-opus-4-7[1m]` at effort `xhigh` via the Claude CLI.
- **Inputs:** the [`judge-consistency-data.md`](judge-consistency-data.md) tables plus benchmark context (rubrics, task list, experiment setup).
- **Script:** [`conclusions_report.py`](../../conclusions_report.py) — regenerate with `python3 generate_results.py <run_dir>`.
- **Instruction:** [`JUDGE_CONSISTENCY_SUMMARY_SYSTEM_PROMPT`](../../judge_consistency_report.py) in that script.
- **Usage:** 5 input + 2739 output tokens, $0.2396.

*Full breakdown with per-model / per-language / per-language×model ranking tables and disagreement hotspots in [judge-consistency-data.md](judge-consistency-data.md).*

---
*Generated by generate_results.py — benchmark instructions v4*