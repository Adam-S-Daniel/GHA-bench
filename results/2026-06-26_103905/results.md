# Benchmark Results: Language Comparison

**Last updated:** 2026-06-27 11:40:35 AM ET — 51/58 runs completed, 7 remaining; total cost $127.56; total agent time 509.2 min.
**Claude Code versions used:** v2.1.193 (23 runs), v2.1.195 (28 runs). Each link goes to a per-version snapshot of the system prompt, default-tool descriptions, and the chronological Anthropic changelog up to that version. Regenerate with `python3 version_docs.py`.

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
| powershell | opus48-1m-medium | A+ (7.1min) | A+ ($1.73) | — | — |
| default | opus48-1m-medium | A (7.8min) | A ($1.93) | — | — |
| bash | opus48-1m-medium | B+ (8.9min) | B ($2.25) | — | — |
| default | opus48-1m-high | B (9.3min) | C ($2.57) | — | — |
| typescript-bun | opus48-1m-medium | B- (9.9min) | C+ ($2.43) | — | — |
| powershell-tool | opus48-1m-medium | C+ (10.2min) | C ($2.59) | — | — |
| bash | opus48-1m-high | C+ (10.5min) | C- ($2.78) | — | — |
| powershell-tool | opus48-1m-high | D+ (12.7min) | C- ($2.78) | — | — |
| typescript-bun | opus48-1m-high | C (11.3min) | D ($3.14) | — | — |
| powershell | opus48-1m-high | D- (14.3min) | D- ($3.33) | — | — |


<details>
<summary>Sorted by Duration tier (best-first), then avg of Cost/Tests/Workflow Craft tiers</summary>

| Language | Model | Duration | Cost | Tests Quality | Workflow Craft |
|----------|-------|----------|------|-----------|-------------|
| powershell | opus48-1m-medium | A+ (7.1min) | A+ ($1.73) | — | — |
| default | opus48-1m-medium | A (7.8min) | A ($1.93) | — | — |
| bash | opus48-1m-medium | B+ (8.9min) | B ($2.25) | — | — |
| default | opus48-1m-high | B (9.3min) | C ($2.57) | — | — |
| typescript-bun | opus48-1m-medium | B- (9.9min) | C+ ($2.43) | — | — |
| powershell-tool | opus48-1m-medium | C+ (10.2min) | C ($2.59) | — | — |
| bash | opus48-1m-high | C+ (10.5min) | C- ($2.78) | — | — |
| typescript-bun | opus48-1m-high | C (11.3min) | D ($3.14) | — | — |
| powershell-tool | opus48-1m-high | D+ (12.7min) | C- ($2.78) | — | — |
| powershell | opus48-1m-high | D- (14.3min) | D- ($3.33) | — | — |

</details>

<details>
<summary>Sorted by Cost tier (best-first), then avg of Duration/Tests/Workflow Craft tiers</summary>

| Language | Model | Duration | Cost | Tests Quality | Workflow Craft |
|----------|-------|----------|------|-----------|-------------|
| powershell | opus48-1m-medium | A+ (7.1min) | A+ ($1.73) | — | — |
| default | opus48-1m-medium | A (7.8min) | A ($1.93) | — | — |
| bash | opus48-1m-medium | B+ (8.9min) | B ($2.25) | — | — |
| typescript-bun | opus48-1m-medium | B- (9.9min) | C+ ($2.43) | — | — |
| default | opus48-1m-high | B (9.3min) | C ($2.57) | — | — |
| powershell-tool | opus48-1m-medium | C+ (10.2min) | C ($2.59) | — | — |
| bash | opus48-1m-high | C+ (10.5min) | C- ($2.78) | — | — |
| powershell-tool | opus48-1m-high | D+ (12.7min) | C- ($2.78) | — | — |
| typescript-bun | opus48-1m-high | C (11.3min) | D ($3.14) | — | — |
| powershell | opus48-1m-high | D- (14.3min) | D- ($3.33) | — | — |

</details>

<details>
<summary>Sorted by Tests Quality tier (best-first; no-data last), then avg of other tiers</summary>

| Language | Model | Duration | Cost | Tests Quality | Workflow Craft |
|----------|-------|----------|------|-----------|-------------|
| powershell | opus48-1m-medium | A+ (7.1min) | A+ ($1.73) | — | — |
| default | opus48-1m-medium | A (7.8min) | A ($1.93) | — | — |
| bash | opus48-1m-medium | B+ (8.9min) | B ($2.25) | — | — |
| default | opus48-1m-high | B (9.3min) | C ($2.57) | — | — |
| typescript-bun | opus48-1m-medium | B- (9.9min) | C+ ($2.43) | — | — |
| powershell-tool | opus48-1m-medium | C+ (10.2min) | C ($2.59) | — | — |
| bash | opus48-1m-high | C+ (10.5min) | C- ($2.78) | — | — |
| powershell-tool | opus48-1m-high | D+ (12.7min) | C- ($2.78) | — | — |
| typescript-bun | opus48-1m-high | C (11.3min) | D ($3.14) | — | — |
| powershell | opus48-1m-high | D- (14.3min) | D- ($3.33) | — | — |

</details>

<details>
<summary>Sorted by Workflow Craft tier (best-first; no-data last), then avg of other tiers</summary>

| Language | Model | Duration | Cost | Tests Quality | Workflow Craft |
|----------|-------|----------|------|-----------|-------------|
| powershell | opus48-1m-medium | A+ (7.1min) | A+ ($1.73) | — | — |
| default | opus48-1m-medium | A (7.8min) | A ($1.93) | — | — |
| bash | opus48-1m-medium | B+ (8.9min) | B ($2.25) | — | — |
| default | opus48-1m-high | B (9.3min) | C ($2.57) | — | — |
| typescript-bun | opus48-1m-medium | B- (9.9min) | C+ ($2.43) | — | — |
| powershell-tool | opus48-1m-medium | C+ (10.2min) | C ($2.59) | — | — |
| bash | opus48-1m-high | C+ (10.5min) | C- ($2.78) | — | — |
| powershell-tool | opus48-1m-high | D+ (12.7min) | C- ($2.78) | — | — |
| typescript-bun | opus48-1m-high | C (11.3min) | D ($3.14) | — | — |
| powershell | opus48-1m-high | D- (14.3min) | D- ($3.33) | — | — |

</details>

- **Estimated time remaining:** 319.5min
- **Estimated total cost:** $145.07

## Comparison by Language/Model/Effort
*See [Notes](#notes) for scoring rubric and CLI version legend.*

| Language | Model | Runs | Avg Duration | Avg Duration Net of Traps | Avg Errors | Avg Turns | Avg Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| bash | opus48-1m-high | 5 | 10.5min | 7.4min | 1.0 | 38 | $2.78 | $13.88 | — | — |
| bash | opus48-1m-medium | 6 | 8.9min | 8.9min | 1.2 | 31 | $2.25 | $13.47 | — | — |
| default | opus48-1m-high | 5 | 9.3min | 8.3min | 0.4 | 39 | $2.57 | $12.87 | — | — |
| default | opus48-1m-medium | 6 | 7.8min | 7.8min | 0.2 | 32 | $1.93 | $11.55 | — | — |
| powershell | opus48-1m-high | 5 | 14.3min | 10.5min | 0.8 | 50 | $3.33 | $16.64 | — | — |
| powershell | opus48-1m-medium | 6 | 7.1min | 7.1min | 0.0 | 27 | $1.73 | $10.38 | — | — |
| powershell-tool | opus48-1m-high | 4 | 12.7min | 10.9min | 0.0 | 39 | $2.78 | $11.12 | — | — |
| powershell-tool | opus48-1m-medium | 5 | 10.2min | 10.2min | 0.8 | 39 | $2.59 | $12.95 | — | — |
| typescript-bun | opus48-1m-high | 4 | 11.3min | 8.3min | 0.2 | 48 | $3.14 | $12.54 | — | — |
| typescript-bun | opus48-1m-medium | 5 | 9.9min | 9.9min | 0.4 | 44 | $2.43 | $12.15 | — | — |


<details>
<summary>Sorted by avg cost (cheapest first)</summary>

| Language | Model | Runs | Avg Duration | Avg Duration Net of Traps | Avg Errors | Avg Turns | Avg Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| powershell | opus48-1m-medium | 6 | 7.1min | 7.1min | 0.0 | 27 | $1.73 | $10.38 | — | — |
| default | opus48-1m-medium | 6 | 7.8min | 7.8min | 0.2 | 32 | $1.93 | $11.55 | — | — |
| bash | opus48-1m-medium | 6 | 8.9min | 8.9min | 1.2 | 31 | $2.25 | $13.47 | — | — |
| typescript-bun | opus48-1m-medium | 5 | 9.9min | 9.9min | 0.4 | 44 | $2.43 | $12.15 | — | — |
| default | opus48-1m-high | 5 | 9.3min | 8.3min | 0.4 | 39 | $2.57 | $12.87 | — | — |
| powershell-tool | opus48-1m-medium | 5 | 10.2min | 10.2min | 0.8 | 39 | $2.59 | $12.95 | — | — |
| bash | opus48-1m-high | 5 | 10.5min | 7.4min | 1.0 | 38 | $2.78 | $13.88 | — | — |
| powershell-tool | opus48-1m-high | 4 | 12.7min | 10.9min | 0.0 | 39 | $2.78 | $11.12 | — | — |
| typescript-bun | opus48-1m-high | 4 | 11.3min | 8.3min | 0.2 | 48 | $3.14 | $12.54 | — | — |
| powershell | opus48-1m-high | 5 | 14.3min | 10.5min | 0.8 | 50 | $3.33 | $16.64 | — | — |

</details>

<details>
<summary>Sorted by avg duration (fastest first)</summary>

| Language | Model | Runs | Avg Duration | Avg Duration Net of Traps | Avg Errors | Avg Turns | Avg Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| powershell | opus48-1m-medium | 6 | 7.1min | 7.1min | 0.0 | 27 | $1.73 | $10.38 | — | — |
| default | opus48-1m-medium | 6 | 7.8min | 7.8min | 0.2 | 32 | $1.93 | $11.55 | — | — |
| bash | opus48-1m-medium | 6 | 8.9min | 8.9min | 1.2 | 31 | $2.25 | $13.47 | — | — |
| default | opus48-1m-high | 5 | 9.3min | 8.3min | 0.4 | 39 | $2.57 | $12.87 | — | — |
| typescript-bun | opus48-1m-medium | 5 | 9.9min | 9.9min | 0.4 | 44 | $2.43 | $12.15 | — | — |
| powershell-tool | opus48-1m-medium | 5 | 10.2min | 10.2min | 0.8 | 39 | $2.59 | $12.95 | — | — |
| bash | opus48-1m-high | 5 | 10.5min | 7.4min | 1.0 | 38 | $2.78 | $13.88 | — | — |
| typescript-bun | opus48-1m-high | 4 | 11.3min | 8.3min | 0.2 | 48 | $3.14 | $12.54 | — | — |
| powershell-tool | opus48-1m-high | 4 | 12.7min | 10.9min | 0.0 | 39 | $2.78 | $11.12 | — | — |
| powershell | opus48-1m-high | 5 | 14.3min | 10.5min | 0.8 | 50 | $3.33 | $16.64 | — | — |

</details>

<details>
<summary>Sorted by avg duration net of traps (fastest first)</summary>

| Language | Model | Runs | Avg Duration | Avg Duration Net of Traps | Avg Errors | Avg Turns | Avg Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| powershell | opus48-1m-medium | 6 | 7.1min | 7.1min | 0.0 | 27 | $1.73 | $10.38 | — | — |
| bash | opus48-1m-high | 5 | 10.5min | 7.4min | 1.0 | 38 | $2.78 | $13.88 | — | — |
| default | opus48-1m-medium | 6 | 7.8min | 7.8min | 0.2 | 32 | $1.93 | $11.55 | — | — |
| default | opus48-1m-high | 5 | 9.3min | 8.3min | 0.4 | 39 | $2.57 | $12.87 | — | — |
| typescript-bun | opus48-1m-high | 4 | 11.3min | 8.3min | 0.2 | 48 | $3.14 | $12.54 | — | — |
| bash | opus48-1m-medium | 6 | 8.9min | 8.9min | 1.2 | 31 | $2.25 | $13.47 | — | — |
| typescript-bun | opus48-1m-medium | 5 | 9.9min | 9.9min | 0.4 | 44 | $2.43 | $12.15 | — | — |
| powershell-tool | opus48-1m-medium | 5 | 10.2min | 10.2min | 0.8 | 39 | $2.59 | $12.95 | — | — |
| powershell | opus48-1m-high | 5 | 14.3min | 10.5min | 0.8 | 50 | $3.33 | $16.64 | — | — |
| powershell-tool | opus48-1m-high | 4 | 12.7min | 10.9min | 0.0 | 39 | $2.78 | $11.12 | — | — |

</details>

<details>
<summary>Sorted by avg errors (fewest first)</summary>

| Language | Model | Runs | Avg Duration | Avg Duration Net of Traps | Avg Errors | Avg Turns | Avg Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| powershell | opus48-1m-medium | 6 | 7.1min | 7.1min | 0.0 | 27 | $1.73 | $10.38 | — | — |
| powershell-tool | opus48-1m-high | 4 | 12.7min | 10.9min | 0.0 | 39 | $2.78 | $11.12 | — | — |
| default | opus48-1m-medium | 6 | 7.8min | 7.8min | 0.2 | 32 | $1.93 | $11.55 | — | — |
| typescript-bun | opus48-1m-high | 4 | 11.3min | 8.3min | 0.2 | 48 | $3.14 | $12.54 | — | — |
| default | opus48-1m-high | 5 | 9.3min | 8.3min | 0.4 | 39 | $2.57 | $12.87 | — | — |
| typescript-bun | opus48-1m-medium | 5 | 9.9min | 9.9min | 0.4 | 44 | $2.43 | $12.15 | — | — |
| powershell | opus48-1m-high | 5 | 14.3min | 10.5min | 0.8 | 50 | $3.33 | $16.64 | — | — |
| powershell-tool | opus48-1m-medium | 5 | 10.2min | 10.2min | 0.8 | 39 | $2.59 | $12.95 | — | — |
| bash | opus48-1m-high | 5 | 10.5min | 7.4min | 1.0 | 38 | $2.78 | $13.88 | — | — |
| bash | opus48-1m-medium | 6 | 8.9min | 8.9min | 1.2 | 31 | $2.25 | $13.47 | — | — |

</details>

<details>
<summary>Sorted by avg turns (fewest first)</summary>

| Language | Model | Runs | Avg Duration | Avg Duration Net of Traps | Avg Errors | Avg Turns | Avg Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| powershell | opus48-1m-medium | 6 | 7.1min | 7.1min | 0.0 | 27 | $1.73 | $10.38 | — | — |
| bash | opus48-1m-medium | 6 | 8.9min | 8.9min | 1.2 | 31 | $2.25 | $13.47 | — | — |
| default | opus48-1m-medium | 6 | 7.8min | 7.8min | 0.2 | 32 | $1.93 | $11.55 | — | — |
| bash | opus48-1m-high | 5 | 10.5min | 7.4min | 1.0 | 38 | $2.78 | $13.88 | — | — |
| powershell-tool | opus48-1m-high | 4 | 12.7min | 10.9min | 0.0 | 39 | $2.78 | $11.12 | — | — |
| default | opus48-1m-high | 5 | 9.3min | 8.3min | 0.4 | 39 | $2.57 | $12.87 | — | — |
| powershell-tool | opus48-1m-medium | 5 | 10.2min | 10.2min | 0.8 | 39 | $2.59 | $12.95 | — | — |
| typescript-bun | opus48-1m-medium | 5 | 9.9min | 9.9min | 0.4 | 44 | $2.43 | $12.15 | — | — |
| typescript-bun | opus48-1m-high | 4 | 11.3min | 8.3min | 0.2 | 48 | $3.14 | $12.54 | — | — |
| powershell | opus48-1m-high | 5 | 14.3min | 10.5min | 0.8 | 50 | $3.33 | $16.64 | — | — |

</details>

<details>
<summary>Sorted by LLM-as-judge score (best first)</summary>

| Language | Model | Runs | Avg Duration | Avg Duration Net of Traps | Avg Errors | Avg Turns | Avg Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| bash | opus48-1m-high | 5 | 10.5min | 7.4min | 1.0 | 38 | $2.78 | $13.88 | — | — |
| bash | opus48-1m-medium | 6 | 8.9min | 8.9min | 1.2 | 31 | $2.25 | $13.47 | — | — |
| default | opus48-1m-high | 5 | 9.3min | 8.3min | 0.4 | 39 | $2.57 | $12.87 | — | — |
| default | opus48-1m-medium | 6 | 7.8min | 7.8min | 0.2 | 32 | $1.93 | $11.55 | — | — |
| powershell | opus48-1m-high | 5 | 14.3min | 10.5min | 0.8 | 50 | $3.33 | $16.64 | — | — |
| powershell | opus48-1m-medium | 6 | 7.1min | 7.1min | 0.0 | 27 | $1.73 | $10.38 | — | — |
| powershell-tool | opus48-1m-high | 4 | 12.7min | 10.9min | 0.0 | 39 | $2.78 | $11.12 | — | — |
| powershell-tool | opus48-1m-medium | 5 | 10.2min | 10.2min | 0.8 | 39 | $2.59 | $12.95 | — | — |
| typescript-bun | opus48-1m-high | 4 | 11.3min | 8.3min | 0.2 | 48 | $3.14 | $12.54 | — | — |
| typescript-bun | opus48-1m-medium | 5 | 9.9min | 9.9min | 0.4 | 44 | $2.43 | $12.15 | — | — |

</details>

<details>
<summary>Sorted by deliverable-quality score (best first)</summary>

| Language | Model | Runs | Avg Duration | Avg Duration Net of Traps | Avg Errors | Avg Turns | Avg Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| bash | opus48-1m-high | 5 | 10.5min | 7.4min | 1.0 | 38 | $2.78 | $13.88 | — | — |
| bash | opus48-1m-medium | 6 | 8.9min | 8.9min | 1.2 | 31 | $2.25 | $13.47 | — | — |
| default | opus48-1m-high | 5 | 9.3min | 8.3min | 0.4 | 39 | $2.57 | $12.87 | — | — |
| default | opus48-1m-medium | 6 | 7.8min | 7.8min | 0.2 | 32 | $1.93 | $11.55 | — | — |
| powershell | opus48-1m-high | 5 | 14.3min | 10.5min | 0.8 | 50 | $3.33 | $16.64 | — | — |
| powershell | opus48-1m-medium | 6 | 7.1min | 7.1min | 0.0 | 27 | $1.73 | $10.38 | — | — |
| powershell-tool | opus48-1m-high | 4 | 12.7min | 10.9min | 0.0 | 39 | $2.78 | $11.12 | — | — |
| powershell-tool | opus48-1m-medium | 5 | 10.2min | 10.2min | 0.8 | 39 | $2.59 | $12.95 | — | — |
| typescript-bun | opus48-1m-high | 4 | 11.3min | 8.3min | 0.2 | 48 | $3.14 | $12.54 | — | — |
| typescript-bun | opus48-1m-medium | 5 | 9.9min | 9.9min | 0.4 | 44 | $2.43 | $12.15 | — | — |

</details>

## Savings Analysis

### Hook Savings by Language/Model/Effort

Each hook-caught error avoids one test run that would otherwise have been needed to discover it.
Every hook fire (hit or miss) costs execution time for the syntax/type checker.

*`% of Test Time Saved` = `net / (net + test_time) × 100` — the share of total (would-have-been + actually-spent) test time that hooks eliminated. Bounded in (-∞, 100%) without an artificial cap; near 100% means hooks substituted for almost all of the hypothetical test work.*

| Language | Model | Fires | Caught | Rate | Gross Saved | % of Time | Overhead | % of Time | Net Saved | % of Time | Test Run Time | % of Test Time Saved |
|------|-------|-------|--------|------|------------|-----------|----------|-----------|-----------|-----------|---------------|----------------------|
| bash | opus48-1m-high-cli2.1.195 | 70 | 1 | 1.4% | 0.2min | 0.0% | 0.0min | 0.0% | 0.2min | 0.0% | 2.5min | 5.9% |
| bash | opus48-1m-medium-cli2.1.193 | 51 | 1 | 2.0% | 0.2min | 0.0% | 0.0min | 0.0% | 0.2min | 0.0% | 0.7min | 20.5% |
| bash | opus48-1m-medium-cli2.1.195 | 17 | 1 | 5.9% | 0.2min | 0.0% | 0.0min | 0.0% | 0.2min | 0.0% | 4.2min | 4.0% |
| default | opus48-1m-high-cli2.1.195 | 97 | 1 | 1.0% | 0.1min | 0.0% | 0.1min | 0.0% | 0.0min | 0.0% | 3.6min | 0.5% |
| default | opus48-1m-medium-cli2.1.193 | 68 | 0 | 0.0% | 0.0min | 0.0% | 0.2min | 0.0% | -0.2min | -0.0% | 4.0min | -3.9% |
| default | opus48-1m-medium-cli2.1.195 | 21 | 0 | 0.0% | 0.0min | 0.0% | 0.1min | 0.0% | -0.1min | -0.0% | 1.8min | -7.8% |
| powershell | opus48-1m-high-cli2.1.195 | 115 | 0 | 0.0% | 0.0min | 0.0% | 1.6min | 0.3% | -1.6min | -0.3% | 13.3min | -13.4% |
| powershell | opus48-1m-medium-cli2.1.193 | 70 | 0 | 0.0% | 0.0min | 0.0% | 0.7min | 0.1% | -0.7min | -0.1% | 4.3min | -19.8% |
| powershell | opus48-1m-medium-cli2.1.195 | 2 | 0 | 0.0% | 0.0min | 0.0% | 0.0min | 0.0% | -0.0min | -0.0% | 0.1min | -14.9% |
| powershell-tool | opus48-1m-high-cli2.1.195 | 78 | 0 | 0.0% | 0.0min | 0.0% | 0.9min | 0.2% | -0.9min | -0.2% | 9.9min | -9.9% |
| powershell-tool | opus48-1m-medium-cli2.1.193 | 62 | 0 | 0.0% | 0.0min | 0.0% | 0.3min | 0.1% | -0.3min | -0.1% | 3.6min | -8.2% |
| powershell-tool | opus48-1m-medium-cli2.1.195 | 18 | 0 | 0.0% | 0.0min | 0.0% | 0.2min | 0.0% | -0.2min | -0.0% | 1.3min | -15.6% |
| typescript-bun | opus48-1m-high-cli2.1.195 | 95 | 49 | 51.6% | 6.5min | 1.3% | 1.3min | 0.2% | 5.3min | 1.0% | 2.3min | 70.0% |
| typescript-bun | opus48-1m-medium-cli2.1.193 | 95 | 40 | 42.1% | 5.3min | 1.0% | 1.4min | 0.3% | 3.9min | 0.8% | 4.0min | 49.5% |
| typescript-bun | opus48-1m-medium-cli2.1.195 | 19 | 0 | 0.0% | 0.0min | 0.0% | 1.0min | 0.2% | -1.0min | -0.2% | 1.1min | -784.0% |


<details>
<summary>Sorted by net saved (most first)</summary>

| Language | Model | Fires | Caught | Rate | Gross Saved | % of Time | Overhead | % of Time | Net Saved | % of Time | Test Run Time | % of Test Time Saved |
|------|-------|-------|--------|------|------------|-----------|----------|-----------|-----------|-----------|---------------|----------------------|
| typescript-bun | opus48-1m-high-cli2.1.195 | 95 | 49 | 51.6% | 6.5min | 1.3% | 1.3min | 0.2% | 5.3min | 1.0% | 2.3min | 70.0% |
| typescript-bun | opus48-1m-medium-cli2.1.193 | 95 | 40 | 42.1% | 5.3min | 1.0% | 1.4min | 0.3% | 3.9min | 0.8% | 4.0min | 49.5% |
| bash | opus48-1m-medium-cli2.1.193 | 51 | 1 | 2.0% | 0.2min | 0.0% | 0.0min | 0.0% | 0.2min | 0.0% | 0.7min | 20.5% |
| bash | opus48-1m-medium-cli2.1.195 | 17 | 1 | 5.9% | 0.2min | 0.0% | 0.0min | 0.0% | 0.2min | 0.0% | 4.2min | 4.0% |
| bash | opus48-1m-high-cli2.1.195 | 70 | 1 | 1.4% | 0.2min | 0.0% | 0.0min | 0.0% | 0.2min | 0.0% | 2.5min | 5.9% |
| default | opus48-1m-high-cli2.1.195 | 97 | 1 | 1.0% | 0.1min | 0.0% | 0.1min | 0.0% | 0.0min | 0.0% | 3.6min | 0.5% |
| powershell | opus48-1m-medium-cli2.1.195 | 2 | 0 | 0.0% | 0.0min | 0.0% | 0.0min | 0.0% | -0.0min | -0.0% | 0.1min | -14.9% |
| default | opus48-1m-medium-cli2.1.195 | 21 | 0 | 0.0% | 0.0min | 0.0% | 0.1min | 0.0% | -0.1min | -0.0% | 1.8min | -7.8% |
| default | opus48-1m-medium-cli2.1.193 | 68 | 0 | 0.0% | 0.0min | 0.0% | 0.2min | 0.0% | -0.2min | -0.0% | 4.0min | -3.9% |
| powershell-tool | opus48-1m-medium-cli2.1.195 | 18 | 0 | 0.0% | 0.0min | 0.0% | 0.2min | 0.0% | -0.2min | -0.0% | 1.3min | -15.6% |
| powershell-tool | opus48-1m-medium-cli2.1.193 | 62 | 0 | 0.0% | 0.0min | 0.0% | 0.3min | 0.1% | -0.3min | -0.1% | 3.6min | -8.2% |
| powershell | opus48-1m-medium-cli2.1.193 | 70 | 0 | 0.0% | 0.0min | 0.0% | 0.7min | 0.1% | -0.7min | -0.1% | 4.3min | -19.8% |
| powershell-tool | opus48-1m-high-cli2.1.195 | 78 | 0 | 0.0% | 0.0min | 0.0% | 0.9min | 0.2% | -0.9min | -0.2% | 9.9min | -9.9% |
| typescript-bun | opus48-1m-medium-cli2.1.195 | 19 | 0 | 0.0% | 0.0min | 0.0% | 1.0min | 0.2% | -1.0min | -0.2% | 1.1min | -784.0% |
| powershell | opus48-1m-high-cli2.1.195 | 115 | 0 | 0.0% | 0.0min | 0.0% | 1.6min | 0.3% | -1.6min | -0.3% | 13.3min | -13.4% |

</details>

<details>
<summary>Sorted by net % of test time saved (most first)</summary>

| Language | Model | Fires | Caught | Rate | Gross Saved | % of Time | Overhead | % of Time | Net Saved | % of Time | Test Run Time | % of Test Time Saved |
|------|-------|-------|--------|------|------------|-----------|----------|-----------|-----------|-----------|---------------|----------------------|
| typescript-bun | opus48-1m-high-cli2.1.195 | 95 | 49 | 51.6% | 6.5min | 1.3% | 1.3min | 0.2% | 5.3min | 1.0% | 2.3min | 70.0% |
| typescript-bun | opus48-1m-medium-cli2.1.193 | 95 | 40 | 42.1% | 5.3min | 1.0% | 1.4min | 0.3% | 3.9min | 0.8% | 4.0min | 49.5% |
| bash | opus48-1m-medium-cli2.1.193 | 51 | 1 | 2.0% | 0.2min | 0.0% | 0.0min | 0.0% | 0.2min | 0.0% | 0.7min | 20.5% |
| bash | opus48-1m-high-cli2.1.195 | 70 | 1 | 1.4% | 0.2min | 0.0% | 0.0min | 0.0% | 0.2min | 0.0% | 2.5min | 5.9% |
| bash | opus48-1m-medium-cli2.1.195 | 17 | 1 | 5.9% | 0.2min | 0.0% | 0.0min | 0.0% | 0.2min | 0.0% | 4.2min | 4.0% |
| default | opus48-1m-high-cli2.1.195 | 97 | 1 | 1.0% | 0.1min | 0.0% | 0.1min | 0.0% | 0.0min | 0.0% | 3.6min | 0.5% |
| default | opus48-1m-medium-cli2.1.193 | 68 | 0 | 0.0% | 0.0min | 0.0% | 0.2min | 0.0% | -0.2min | -0.0% | 4.0min | -3.9% |
| default | opus48-1m-medium-cli2.1.195 | 21 | 0 | 0.0% | 0.0min | 0.0% | 0.1min | 0.0% | -0.1min | -0.0% | 1.8min | -7.8% |
| powershell-tool | opus48-1m-medium-cli2.1.193 | 62 | 0 | 0.0% | 0.0min | 0.0% | 0.3min | 0.1% | -0.3min | -0.1% | 3.6min | -8.2% |
| powershell-tool | opus48-1m-high-cli2.1.195 | 78 | 0 | 0.0% | 0.0min | 0.0% | 0.9min | 0.2% | -0.9min | -0.2% | 9.9min | -9.9% |
| powershell | opus48-1m-high-cli2.1.195 | 115 | 0 | 0.0% | 0.0min | 0.0% | 1.6min | 0.3% | -1.6min | -0.3% | 13.3min | -13.4% |
| powershell | opus48-1m-medium-cli2.1.195 | 2 | 0 | 0.0% | 0.0min | 0.0% | 0.0min | 0.0% | -0.0min | -0.0% | 0.1min | -14.9% |
| powershell-tool | opus48-1m-medium-cli2.1.195 | 18 | 0 | 0.0% | 0.0min | 0.0% | 0.2min | 0.0% | -0.2min | -0.0% | 1.3min | -15.6% |
| powershell | opus48-1m-medium-cli2.1.193 | 70 | 0 | 0.0% | 0.0min | 0.0% | 0.7min | 0.1% | -0.7min | -0.1% | 4.3min | -19.8% |
| typescript-bun | opus48-1m-medium-cli2.1.195 | 19 | 0 | 0.0% | 0.0min | 0.0% | 1.0min | 0.2% | -1.0min | -0.2% | 1.1min | -784.0% |

</details>

<details>
<summary>Sorted by catch rate (highest first)</summary>

| Language | Model | Fires | Caught | Rate | Gross Saved | % of Time | Overhead | % of Time | Net Saved | % of Time | Test Run Time | % of Test Time Saved |
|------|-------|-------|--------|------|------------|-----------|----------|-----------|-----------|-----------|---------------|----------------------|
| typescript-bun | opus48-1m-high-cli2.1.195 | 95 | 49 | 51.6% | 6.5min | 1.3% | 1.3min | 0.2% | 5.3min | 1.0% | 2.3min | 70.0% |
| typescript-bun | opus48-1m-medium-cli2.1.193 | 95 | 40 | 42.1% | 5.3min | 1.0% | 1.4min | 0.3% | 3.9min | 0.8% | 4.0min | 49.5% |
| bash | opus48-1m-medium-cli2.1.195 | 17 | 1 | 5.9% | 0.2min | 0.0% | 0.0min | 0.0% | 0.2min | 0.0% | 4.2min | 4.0% |
| bash | opus48-1m-medium-cli2.1.193 | 51 | 1 | 2.0% | 0.2min | 0.0% | 0.0min | 0.0% | 0.2min | 0.0% | 0.7min | 20.5% |
| bash | opus48-1m-high-cli2.1.195 | 70 | 1 | 1.4% | 0.2min | 0.0% | 0.0min | 0.0% | 0.2min | 0.0% | 2.5min | 5.9% |
| default | opus48-1m-high-cli2.1.195 | 97 | 1 | 1.0% | 0.1min | 0.0% | 0.1min | 0.0% | 0.0min | 0.0% | 3.6min | 0.5% |
| default | opus48-1m-medium-cli2.1.193 | 68 | 0 | 0.0% | 0.0min | 0.0% | 0.2min | 0.0% | -0.2min | -0.0% | 4.0min | -3.9% |
| default | opus48-1m-medium-cli2.1.195 | 21 | 0 | 0.0% | 0.0min | 0.0% | 0.1min | 0.0% | -0.1min | -0.0% | 1.8min | -7.8% |
| powershell | opus48-1m-high-cli2.1.195 | 115 | 0 | 0.0% | 0.0min | 0.0% | 1.6min | 0.3% | -1.6min | -0.3% | 13.3min | -13.4% |
| powershell | opus48-1m-medium-cli2.1.193 | 70 | 0 | 0.0% | 0.0min | 0.0% | 0.7min | 0.1% | -0.7min | -0.1% | 4.3min | -19.8% |
| powershell | opus48-1m-medium-cli2.1.195 | 2 | 0 | 0.0% | 0.0min | 0.0% | 0.0min | 0.0% | -0.0min | -0.0% | 0.1min | -14.9% |
| powershell-tool | opus48-1m-high-cli2.1.195 | 78 | 0 | 0.0% | 0.0min | 0.0% | 0.9min | 0.2% | -0.9min | -0.2% | 9.9min | -9.9% |
| powershell-tool | opus48-1m-medium-cli2.1.193 | 62 | 0 | 0.0% | 0.0min | 0.0% | 0.3min | 0.1% | -0.3min | -0.1% | 3.6min | -8.2% |
| powershell-tool | opus48-1m-medium-cli2.1.195 | 18 | 0 | 0.0% | 0.0min | 0.0% | 0.2min | 0.0% | -0.2min | -0.0% | 1.3min | -15.6% |
| typescript-bun | opus48-1m-medium-cli2.1.195 | 19 | 0 | 0.0% | 0.0min | 0.0% | 1.0min | 0.2% | -1.0min | -0.2% | 1.1min | -784.0% |

</details>

### Trap Analysis by Language/Model/Effort/Category

| Trap | Language | Model | Fell In | Time Lost | % of Time | $ Lost | % of $ |
|------|------|-------|---------|-----------|-----------|--------|--------|
| repeated-test-reruns | bash | opus48-1m-high-cli2.1.195 | 4 | 9.7min | 1.9% | $2.59 | 2.03% |
| repeated-test-reruns | bash | opus48-1m-medium-cli2.1.193 | 3 | 4.0min | 0.8% | $1.08 | 0.84% |
| repeated-test-reruns | bash | opus48-1m-medium-cli2.1.195 | 1 | 2.3min | 0.5% | $0.56 | 0.44% |
| repeated-test-reruns | default | opus48-1m-high-cli2.1.195 | 3 | 5.0min | 1.0% | $1.28 | 1.00% |
| repeated-test-reruns | default | opus48-1m-medium-cli2.1.193 | 4 | 5.7min | 1.1% | $1.34 | 1.05% |
| repeated-test-reruns | default | opus48-1m-medium-cli2.1.195 | 1 | 2.7min | 0.5% | $0.64 | 0.50% |
| repeated-test-reruns | powershell | opus48-1m-high-cli2.1.195 | 6 | 17.3min | 3.4% | $3.94 | 3.09% |
| repeated-test-reruns | powershell | opus48-1m-medium-cli2.1.193 | 2 | 2.7min | 0.5% | $0.66 | 0.52% |
| repeated-test-reruns | powershell-tool | opus48-1m-high-cli2.1.195 | 3 | 6.7min | 1.3% | $1.52 | 1.19% |
| repeated-test-reruns | powershell-tool | opus48-1m-medium-cli2.1.193 | 2 | 3.3min | 0.7% | $0.78 | 0.61% |
| repeated-test-reruns | powershell-tool | opus48-1m-medium-cli2.1.195 | 1 | 0.7min | 0.1% | $0.19 | 0.15% |
| repeated-test-reruns | typescript-bun | opus48-1m-high-cli2.1.195 | 2 | 2.3min | 0.5% | $0.63 | 0.50% |
| repeated-test-reruns | typescript-bun | opus48-1m-medium-cli2.1.193 | 4 | 8.7min | 1.7% | $2.26 | 1.77% |
| repeated-test-reruns | typescript-bun | opus48-1m-medium-cli2.1.195 | 2 | 2.0min | 0.4% | $0.50 | 0.39% |
| ts-type-error-fix-cycles | typescript-bun | opus48-1m-high-cli2.1.195 | 4 | 9.8min | 1.9% | $2.69 | 2.11% |
| ts-type-error-fix-cycles | typescript-bun | opus48-1m-medium-cli2.1.193 | 3 | 8.0min | 1.6% | $2.17 | 1.70% |
| fixture-rework | bash | opus48-1m-high-cli2.1.195 | 5 | 4.5min | 0.9% | $1.20 | 0.94% |
| fixture-rework | bash | opus48-1m-medium-cli2.1.193 | 2 | 1.5min | 0.3% | $0.41 | 0.32% |
| fixture-rework | bash | opus48-1m-medium-cli2.1.195 | 1 | 3.0min | 0.6% | $0.72 | 0.56% |
| fixture-rework | default | opus48-1m-medium-cli2.1.193 | 1 | 0.8min | 0.1% | $0.22 | 0.18% |
| fixture-rework | powershell | opus48-1m-high-cli2.1.195 | 3 | 2.0min | 0.4% | $0.48 | 0.38% |
| fixture-rework | powershell | opus48-1m-medium-cli2.1.193 | 1 | 0.5min | 0.1% | $0.12 | 0.09% |
| fixture-rework | powershell-tool | opus48-1m-high-cli2.1.195 | 1 | 0.5min | 0.1% | $0.12 | 0.10% |
| fixture-rework | powershell-tool | opus48-1m-medium-cli2.1.193 | 1 | 1.0min | 0.2% | $0.27 | 0.21% |
| bats-setup-issues | bash | opus48-1m-high-cli2.1.195 | 1 | 1.2min | 0.2% | $0.33 | 0.26% |
| actionlint-fix-cycles | powershell-tool | opus48-1m-medium-cli2.1.193 | 1 | 1.0min | 0.2% | $0.27 | 0.21% |


<details>
<summary>Sorted by time lost (least first)</summary>

| Trap | Language | Model | Fell In | Time Lost | % of Time | $ Lost | % of $ |
|------|------|-------|---------|-----------|-----------|--------|--------|
| fixture-rework | powershell | opus48-1m-medium-cli2.1.193 | 1 | 0.5min | 0.1% | $0.12 | 0.09% |
| fixture-rework | powershell-tool | opus48-1m-high-cli2.1.195 | 1 | 0.5min | 0.1% | $0.12 | 0.10% |
| repeated-test-reruns | powershell-tool | opus48-1m-medium-cli2.1.195 | 1 | 0.7min | 0.1% | $0.19 | 0.15% |
| fixture-rework | default | opus48-1m-medium-cli2.1.193 | 1 | 0.8min | 0.1% | $0.22 | 0.18% |
| fixture-rework | powershell-tool | opus48-1m-medium-cli2.1.193 | 1 | 1.0min | 0.2% | $0.27 | 0.21% |
| actionlint-fix-cycles | powershell-tool | opus48-1m-medium-cli2.1.193 | 1 | 1.0min | 0.2% | $0.27 | 0.21% |
| bats-setup-issues | bash | opus48-1m-high-cli2.1.195 | 1 | 1.2min | 0.2% | $0.33 | 0.26% |
| fixture-rework | bash | opus48-1m-medium-cli2.1.193 | 2 | 1.5min | 0.3% | $0.41 | 0.32% |
| repeated-test-reruns | typescript-bun | opus48-1m-medium-cli2.1.195 | 2 | 2.0min | 0.4% | $0.50 | 0.39% |
| fixture-rework | powershell | opus48-1m-high-cli2.1.195 | 3 | 2.0min | 0.4% | $0.48 | 0.38% |
| repeated-test-reruns | bash | opus48-1m-medium-cli2.1.195 | 1 | 2.3min | 0.5% | $0.56 | 0.44% |
| repeated-test-reruns | typescript-bun | opus48-1m-high-cli2.1.195 | 2 | 2.3min | 0.5% | $0.63 | 0.50% |
| repeated-test-reruns | default | opus48-1m-medium-cli2.1.195 | 1 | 2.7min | 0.5% | $0.64 | 0.50% |
| repeated-test-reruns | powershell | opus48-1m-medium-cli2.1.193 | 2 | 2.7min | 0.5% | $0.66 | 0.52% |
| fixture-rework | bash | opus48-1m-medium-cli2.1.195 | 1 | 3.0min | 0.6% | $0.72 | 0.56% |
| repeated-test-reruns | powershell-tool | opus48-1m-medium-cli2.1.193 | 2 | 3.3min | 0.7% | $0.78 | 0.61% |
| repeated-test-reruns | bash | opus48-1m-medium-cli2.1.193 | 3 | 4.0min | 0.8% | $1.08 | 0.84% |
| fixture-rework | bash | opus48-1m-high-cli2.1.195 | 5 | 4.5min | 0.9% | $1.20 | 0.94% |
| repeated-test-reruns | default | opus48-1m-high-cli2.1.195 | 3 | 5.0min | 1.0% | $1.28 | 1.00% |
| repeated-test-reruns | default | opus48-1m-medium-cli2.1.193 | 4 | 5.7min | 1.1% | $1.34 | 1.05% |
| repeated-test-reruns | powershell-tool | opus48-1m-high-cli2.1.195 | 3 | 6.7min | 1.3% | $1.52 | 1.19% |
| ts-type-error-fix-cycles | typescript-bun | opus48-1m-medium-cli2.1.193 | 3 | 8.0min | 1.6% | $2.17 | 1.70% |
| repeated-test-reruns | typescript-bun | opus48-1m-medium-cli2.1.193 | 4 | 8.7min | 1.7% | $2.26 | 1.77% |
| repeated-test-reruns | bash | opus48-1m-high-cli2.1.195 | 4 | 9.7min | 1.9% | $2.59 | 2.03% |
| ts-type-error-fix-cycles | typescript-bun | opus48-1m-high-cli2.1.195 | 4 | 9.8min | 1.9% | $2.69 | 2.11% |
| repeated-test-reruns | powershell | opus48-1m-high-cli2.1.195 | 6 | 17.3min | 3.4% | $3.94 | 3.09% |

</details>

<details>
<summary>Sorted by $ lost (least first)</summary>

| Trap | Language | Model | Fell In | Time Lost | % of Time | $ Lost | % of $ |
|------|------|-------|---------|-----------|-----------|--------|--------|
| fixture-rework | powershell | opus48-1m-medium-cli2.1.193 | 1 | 0.5min | 0.1% | $0.12 | 0.09% |
| fixture-rework | powershell-tool | opus48-1m-high-cli2.1.195 | 1 | 0.5min | 0.1% | $0.12 | 0.10% |
| repeated-test-reruns | powershell-tool | opus48-1m-medium-cli2.1.195 | 1 | 0.7min | 0.1% | $0.19 | 0.15% |
| fixture-rework | default | opus48-1m-medium-cli2.1.193 | 1 | 0.8min | 0.1% | $0.22 | 0.18% |
| fixture-rework | powershell-tool | opus48-1m-medium-cli2.1.193 | 1 | 1.0min | 0.2% | $0.27 | 0.21% |
| actionlint-fix-cycles | powershell-tool | opus48-1m-medium-cli2.1.193 | 1 | 1.0min | 0.2% | $0.27 | 0.21% |
| bats-setup-issues | bash | opus48-1m-high-cli2.1.195 | 1 | 1.2min | 0.2% | $0.33 | 0.26% |
| fixture-rework | bash | opus48-1m-medium-cli2.1.193 | 2 | 1.5min | 0.3% | $0.41 | 0.32% |
| fixture-rework | powershell | opus48-1m-high-cli2.1.195 | 3 | 2.0min | 0.4% | $0.48 | 0.38% |
| repeated-test-reruns | typescript-bun | opus48-1m-medium-cli2.1.195 | 2 | 2.0min | 0.4% | $0.50 | 0.39% |
| repeated-test-reruns | bash | opus48-1m-medium-cli2.1.195 | 1 | 2.3min | 0.5% | $0.56 | 0.44% |
| repeated-test-reruns | typescript-bun | opus48-1m-high-cli2.1.195 | 2 | 2.3min | 0.5% | $0.63 | 0.50% |
| repeated-test-reruns | default | opus48-1m-medium-cli2.1.195 | 1 | 2.7min | 0.5% | $0.64 | 0.50% |
| repeated-test-reruns | powershell | opus48-1m-medium-cli2.1.193 | 2 | 2.7min | 0.5% | $0.66 | 0.52% |
| fixture-rework | bash | opus48-1m-medium-cli2.1.195 | 1 | 3.0min | 0.6% | $0.72 | 0.56% |
| repeated-test-reruns | powershell-tool | opus48-1m-medium-cli2.1.193 | 2 | 3.3min | 0.7% | $0.78 | 0.61% |
| repeated-test-reruns | bash | opus48-1m-medium-cli2.1.193 | 3 | 4.0min | 0.8% | $1.08 | 0.84% |
| fixture-rework | bash | opus48-1m-high-cli2.1.195 | 5 | 4.5min | 0.9% | $1.20 | 0.94% |
| repeated-test-reruns | default | opus48-1m-high-cli2.1.195 | 3 | 5.0min | 1.0% | $1.28 | 1.00% |
| repeated-test-reruns | default | opus48-1m-medium-cli2.1.193 | 4 | 5.7min | 1.1% | $1.34 | 1.05% |
| repeated-test-reruns | powershell-tool | opus48-1m-high-cli2.1.195 | 3 | 6.7min | 1.3% | $1.52 | 1.19% |
| ts-type-error-fix-cycles | typescript-bun | opus48-1m-medium-cli2.1.193 | 3 | 8.0min | 1.6% | $2.17 | 1.70% |
| repeated-test-reruns | typescript-bun | opus48-1m-medium-cli2.1.193 | 4 | 8.7min | 1.7% | $2.26 | 1.77% |
| repeated-test-reruns | bash | opus48-1m-high-cli2.1.195 | 4 | 9.7min | 1.9% | $2.59 | 2.03% |
| ts-type-error-fix-cycles | typescript-bun | opus48-1m-high-cli2.1.195 | 4 | 9.8min | 1.9% | $2.69 | 2.11% |
| repeated-test-reruns | powershell | opus48-1m-high-cli2.1.195 | 6 | 17.3min | 3.4% | $3.94 | 3.09% |

</details>

<details>
<summary>Sorted by fell-in count (fewest first)</summary>

| Trap | Language | Model | Fell In | Time Lost | % of Time | $ Lost | % of $ |
|------|------|-------|---------|-----------|-----------|--------|--------|
| repeated-test-reruns | bash | opus48-1m-medium-cli2.1.195 | 1 | 2.3min | 0.5% | $0.56 | 0.44% |
| repeated-test-reruns | default | opus48-1m-medium-cli2.1.195 | 1 | 2.7min | 0.5% | $0.64 | 0.50% |
| repeated-test-reruns | powershell-tool | opus48-1m-medium-cli2.1.195 | 1 | 0.7min | 0.1% | $0.19 | 0.15% |
| fixture-rework | bash | opus48-1m-medium-cli2.1.195 | 1 | 3.0min | 0.6% | $0.72 | 0.56% |
| fixture-rework | default | opus48-1m-medium-cli2.1.193 | 1 | 0.8min | 0.1% | $0.22 | 0.18% |
| fixture-rework | powershell | opus48-1m-medium-cli2.1.193 | 1 | 0.5min | 0.1% | $0.12 | 0.09% |
| fixture-rework | powershell-tool | opus48-1m-high-cli2.1.195 | 1 | 0.5min | 0.1% | $0.12 | 0.10% |
| fixture-rework | powershell-tool | opus48-1m-medium-cli2.1.193 | 1 | 1.0min | 0.2% | $0.27 | 0.21% |
| bats-setup-issues | bash | opus48-1m-high-cli2.1.195 | 1 | 1.2min | 0.2% | $0.33 | 0.26% |
| actionlint-fix-cycles | powershell-tool | opus48-1m-medium-cli2.1.193 | 1 | 1.0min | 0.2% | $0.27 | 0.21% |
| repeated-test-reruns | powershell | opus48-1m-medium-cli2.1.193 | 2 | 2.7min | 0.5% | $0.66 | 0.52% |
| repeated-test-reruns | powershell-tool | opus48-1m-medium-cli2.1.193 | 2 | 3.3min | 0.7% | $0.78 | 0.61% |
| repeated-test-reruns | typescript-bun | opus48-1m-high-cli2.1.195 | 2 | 2.3min | 0.5% | $0.63 | 0.50% |
| repeated-test-reruns | typescript-bun | opus48-1m-medium-cli2.1.195 | 2 | 2.0min | 0.4% | $0.50 | 0.39% |
| fixture-rework | bash | opus48-1m-medium-cli2.1.193 | 2 | 1.5min | 0.3% | $0.41 | 0.32% |
| repeated-test-reruns | bash | opus48-1m-medium-cli2.1.193 | 3 | 4.0min | 0.8% | $1.08 | 0.84% |
| repeated-test-reruns | default | opus48-1m-high-cli2.1.195 | 3 | 5.0min | 1.0% | $1.28 | 1.00% |
| repeated-test-reruns | powershell-tool | opus48-1m-high-cli2.1.195 | 3 | 6.7min | 1.3% | $1.52 | 1.19% |
| ts-type-error-fix-cycles | typescript-bun | opus48-1m-medium-cli2.1.193 | 3 | 8.0min | 1.6% | $2.17 | 1.70% |
| fixture-rework | powershell | opus48-1m-high-cli2.1.195 | 3 | 2.0min | 0.4% | $0.48 | 0.38% |
| repeated-test-reruns | bash | opus48-1m-high-cli2.1.195 | 4 | 9.7min | 1.9% | $2.59 | 2.03% |
| repeated-test-reruns | default | opus48-1m-medium-cli2.1.193 | 4 | 5.7min | 1.1% | $1.34 | 1.05% |
| repeated-test-reruns | typescript-bun | opus48-1m-medium-cli2.1.193 | 4 | 8.7min | 1.7% | $2.26 | 1.77% |
| ts-type-error-fix-cycles | typescript-bun | opus48-1m-high-cli2.1.195 | 4 | 9.8min | 1.9% | $2.69 | 2.11% |
| fixture-rework | bash | opus48-1m-high-cli2.1.195 | 5 | 4.5min | 0.9% | $1.20 | 0.94% |
| repeated-test-reruns | powershell | opus48-1m-high-cli2.1.195 | 6 | 17.3min | 3.4% | $3.94 | 3.09% |

</details>

#### Trap Descriptions

- **actionlint-fix-cycles**: Workflow YAML required 3+ actionlint runs and 2+ fixes to pass.
- **bats-setup-issues**: Agent struggled with bats-core test framework setup or load helpers.
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
| bash | opus48-1m-high-cli2.1.195 | 5 | 10 | 15.4min | 3.0% | $4.12 | 3.23% |
| bash | opus48-1m-medium-cli2.1.193 | 5 | 5 | 5.5min | 1.1% | $1.49 | 1.17% |
| bash | opus48-1m-medium-cli2.1.195 | 1 | 2 | 5.3min | 1.0% | $1.27 | 1.00% |
| default | opus48-1m-high-cli2.1.195 | 5 | 3 | 5.0min | 1.0% | $1.28 | 1.00% |
| default | opus48-1m-medium-cli2.1.193 | 5 | 5 | 6.4min | 1.3% | $1.57 | 1.23% |
| default | opus48-1m-medium-cli2.1.195 | 1 | 1 | 2.7min | 0.5% | $0.64 | 0.50% |
| powershell | opus48-1m-high-cli2.1.195 | 5 | 9 | 19.3min | 3.8% | $4.42 | 3.46% |
| powershell | opus48-1m-medium-cli2.1.193 | 5 | 3 | 3.2min | 0.6% | $0.78 | 0.61% |
| powershell | opus48-1m-medium-cli2.1.195 | 1 | 0 | 0.0min | 0.0% | $0.00 | 0.00% |
| powershell-tool | opus48-1m-high-cli2.1.195 | 4 | 4 | 7.2min | 1.4% | $1.64 | 1.29% |
| powershell-tool | opus48-1m-medium-cli2.1.193 | 4 | 4 | 5.3min | 1.0% | $1.31 | 1.03% |
| powershell-tool | opus48-1m-medium-cli2.1.195 | 1 | 1 | 0.7min | 0.1% | $0.19 | 0.15% |
| typescript-bun | opus48-1m-high-cli2.1.195 | 4 | 6 | 12.1min | 2.4% | $3.32 | 2.60% |
| typescript-bun | opus48-1m-medium-cli2.1.193 | 4 | 7 | 16.7min | 3.3% | $4.43 | 3.47% |
| typescript-bun | opus48-1m-medium-cli2.1.195 | 1 | 2 | 2.0min | 0.4% | $0.50 | 0.39% |


<details>
<summary>Sorted by time lost (least first)</summary>

| Language | Model | Runs | Traps | Time Lost | % of Time | $ Lost | % of $ |
|------|-------|------|-------|-----------|-----------|--------|--------|
| powershell | opus48-1m-medium-cli2.1.195 | 1 | 0 | 0.0min | 0.0% | $0.00 | 0.00% |
| powershell-tool | opus48-1m-medium-cli2.1.195 | 1 | 1 | 0.7min | 0.1% | $0.19 | 0.15% |
| typescript-bun | opus48-1m-medium-cli2.1.195 | 1 | 2 | 2.0min | 0.4% | $0.50 | 0.39% |
| default | opus48-1m-medium-cli2.1.195 | 1 | 1 | 2.7min | 0.5% | $0.64 | 0.50% |
| powershell | opus48-1m-medium-cli2.1.193 | 5 | 3 | 3.2min | 0.6% | $0.78 | 0.61% |
| default | opus48-1m-high-cli2.1.195 | 5 | 3 | 5.0min | 1.0% | $1.28 | 1.00% |
| bash | opus48-1m-medium-cli2.1.195 | 1 | 2 | 5.3min | 1.0% | $1.27 | 1.00% |
| powershell-tool | opus48-1m-medium-cli2.1.193 | 4 | 4 | 5.3min | 1.0% | $1.31 | 1.03% |
| bash | opus48-1m-medium-cli2.1.193 | 5 | 5 | 5.5min | 1.1% | $1.49 | 1.17% |
| default | opus48-1m-medium-cli2.1.193 | 5 | 5 | 6.4min | 1.3% | $1.57 | 1.23% |
| powershell-tool | opus48-1m-high-cli2.1.195 | 4 | 4 | 7.2min | 1.4% | $1.64 | 1.29% |
| typescript-bun | opus48-1m-high-cli2.1.195 | 4 | 6 | 12.1min | 2.4% | $3.32 | 2.60% |
| bash | opus48-1m-high-cli2.1.195 | 5 | 10 | 15.4min | 3.0% | $4.12 | 3.23% |
| typescript-bun | opus48-1m-medium-cli2.1.193 | 4 | 7 | 16.7min | 3.3% | $4.43 | 3.47% |
| powershell | opus48-1m-high-cli2.1.195 | 5 | 9 | 19.3min | 3.8% | $4.42 | 3.46% |

</details>

<details>
<summary>Sorted by $ lost (least first)</summary>

| Language | Model | Runs | Traps | Time Lost | % of Time | $ Lost | % of $ |
|------|-------|------|-------|-----------|-----------|--------|--------|
| powershell | opus48-1m-medium-cli2.1.195 | 1 | 0 | 0.0min | 0.0% | $0.00 | 0.00% |
| powershell-tool | opus48-1m-medium-cli2.1.195 | 1 | 1 | 0.7min | 0.1% | $0.19 | 0.15% |
| typescript-bun | opus48-1m-medium-cli2.1.195 | 1 | 2 | 2.0min | 0.4% | $0.50 | 0.39% |
| default | opus48-1m-medium-cli2.1.195 | 1 | 1 | 2.7min | 0.5% | $0.64 | 0.50% |
| powershell | opus48-1m-medium-cli2.1.193 | 5 | 3 | 3.2min | 0.6% | $0.78 | 0.61% |
| bash | opus48-1m-medium-cli2.1.195 | 1 | 2 | 5.3min | 1.0% | $1.27 | 1.00% |
| default | opus48-1m-high-cli2.1.195 | 5 | 3 | 5.0min | 1.0% | $1.28 | 1.00% |
| powershell-tool | opus48-1m-medium-cli2.1.193 | 4 | 4 | 5.3min | 1.0% | $1.31 | 1.03% |
| bash | opus48-1m-medium-cli2.1.193 | 5 | 5 | 5.5min | 1.1% | $1.49 | 1.17% |
| default | opus48-1m-medium-cli2.1.193 | 5 | 5 | 6.4min | 1.3% | $1.57 | 1.23% |
| powershell-tool | opus48-1m-high-cli2.1.195 | 4 | 4 | 7.2min | 1.4% | $1.64 | 1.29% |
| typescript-bun | opus48-1m-high-cli2.1.195 | 4 | 6 | 12.1min | 2.4% | $3.32 | 2.60% |
| bash | opus48-1m-high-cli2.1.195 | 5 | 10 | 15.4min | 3.0% | $4.12 | 3.23% |
| powershell | opus48-1m-high-cli2.1.195 | 5 | 9 | 19.3min | 3.8% | $4.42 | 3.46% |
| typescript-bun | opus48-1m-medium-cli2.1.193 | 4 | 7 | 16.7min | 3.3% | $4.43 | 3.47% |

</details>

### Prompt Cache Savings

| Status | Runs | $ Saved | % of $ |
|--------|------|---------|--------|
| Full hit (100%) | 1 | $0.12 | 0.10% |
| Partial | 45 | $4.52 | 3.55% |
| Miss | 5 | $0.00 | 0.00% |

## Test Quality Evaluation

### Structural Metrics by Language/Model/Effort

Automated analysis of test files: test count, assertion count, and test-to-code line ratio.

| Language | Model | Avg Tests | Avg Assertions | Avg Assert/Test | Avg Test:Code Ratio |
|------|-------|-----------|----------------|-----------------|---------------------|
| bash | opus48-1m-high | 31.2 | 67.6 | 2.2 | 1.46 |
| bash | opus48-1m-medium | 23.3 | 36.3 | 1.6 | 1.19 |
| default | opus48-1m-high | 29.4 | 55.2 | 1.9 | 1.57 |
| default | opus48-1m-medium | 27.3 | 50.2 | 1.8 | 1.07 |
| powershell | opus48-1m-high | 48.4 | 86.6 | 1.8 | 6.87 |
| powershell | opus48-1m-medium | 35.2 | 63.2 | 1.8 | 2.78 |
| powershell-tool | opus48-1m-high | 37.8 | 68.5 | 1.8 | 3.38 |
| powershell-tool | opus48-1m-medium | 31.0 | 54.2 | 1.7 | 4.15 |
| typescript-bun | opus48-1m-high | 42.2 | 87.8 | 2.1 | 0.96 |
| typescript-bun | opus48-1m-medium | 31.6 | 63.4 | 2.0 | 1.20 |


<details>
<summary>Sorted by avg tests (most first)</summary>

| Language | Model | Avg Tests | Avg Assertions | Avg Assert/Test | Avg Test:Code Ratio |
|------|-------|-----------|----------------|-----------------|---------------------|
| powershell | opus48-1m-high | 48.4 | 86.6 | 1.8 | 6.87 |
| typescript-bun | opus48-1m-high | 42.2 | 87.8 | 2.1 | 0.96 |
| powershell-tool | opus48-1m-high | 37.8 | 68.5 | 1.8 | 3.38 |
| powershell | opus48-1m-medium | 35.2 | 63.2 | 1.8 | 2.78 |
| typescript-bun | opus48-1m-medium | 31.6 | 63.4 | 2.0 | 1.20 |
| bash | opus48-1m-high | 31.2 | 67.6 | 2.2 | 1.46 |
| powershell-tool | opus48-1m-medium | 31.0 | 54.2 | 1.7 | 4.15 |
| default | opus48-1m-high | 29.4 | 55.2 | 1.9 | 1.57 |
| default | opus48-1m-medium | 27.3 | 50.2 | 1.8 | 1.07 |
| bash | opus48-1m-medium | 23.3 | 36.3 | 1.6 | 1.19 |

</details>

<details>
<summary>Sorted by avg assertions (most first)</summary>

| Language | Model | Avg Tests | Avg Assertions | Avg Assert/Test | Avg Test:Code Ratio |
|------|-------|-----------|----------------|-----------------|---------------------|
| typescript-bun | opus48-1m-high | 42.2 | 87.8 | 2.1 | 0.96 |
| powershell | opus48-1m-high | 48.4 | 86.6 | 1.8 | 6.87 |
| powershell-tool | opus48-1m-high | 37.8 | 68.5 | 1.8 | 3.38 |
| bash | opus48-1m-high | 31.2 | 67.6 | 2.2 | 1.46 |
| typescript-bun | opus48-1m-medium | 31.6 | 63.4 | 2.0 | 1.20 |
| powershell | opus48-1m-medium | 35.2 | 63.2 | 1.8 | 2.78 |
| default | opus48-1m-high | 29.4 | 55.2 | 1.9 | 1.57 |
| powershell-tool | opus48-1m-medium | 31.0 | 54.2 | 1.7 | 4.15 |
| default | opus48-1m-medium | 27.3 | 50.2 | 1.8 | 1.07 |
| bash | opus48-1m-medium | 23.3 | 36.3 | 1.6 | 1.19 |

</details>

<details>
<summary>Sorted by avg test:code ratio (highest first)</summary>

| Language | Model | Avg Tests | Avg Assertions | Avg Assert/Test | Avg Test:Code Ratio |
|------|-------|-----------|----------------|-----------------|---------------------|
| powershell | opus48-1m-high | 48.4 | 86.6 | 1.8 | 6.87 |
| powershell-tool | opus48-1m-medium | 31.0 | 54.2 | 1.7 | 4.15 |
| powershell-tool | opus48-1m-high | 37.8 | 68.5 | 1.8 | 3.38 |
| powershell | opus48-1m-medium | 35.2 | 63.2 | 1.8 | 2.78 |
| default | opus48-1m-high | 29.4 | 55.2 | 1.9 | 1.57 |
| bash | opus48-1m-high | 31.2 | 67.6 | 2.2 | 1.46 |
| typescript-bun | opus48-1m-medium | 31.6 | 63.4 | 2.0 | 1.20 |
| bash | opus48-1m-medium | 23.3 | 36.3 | 1.6 | 1.19 |
| default | opus48-1m-medium | 27.3 | 50.2 | 1.8 | 1.07 |
| typescript-bun | opus48-1m-high | 42.2 | 87.8 | 2.1 | 0.96 |

</details>


<details>
<summary>Per-run structural metrics</summary>

| Task | Language | Model | Tests | Assertions | Assert/Test | Test Lines | Impl Lines | Test:Code |
|------|------|-------|-------|------------|-------------|------------|------------|-----------|
| Semantic Version Bumper | bash | opus48-1m-high | 36 | 54 | 1.5 | 346 | 467 | 0.74 |
| Semantic Version Bumper | bash | opus48-1m-medium | 24 | 34 | 1.4 | 286 | 275 | 1.04 |
| Semantic Version Bumper | default | opus48-1m-high | 38 | 66 | 1.7 | 330 | 364 | 0.91 |
| Semantic Version Bumper | default | opus48-1m-medium | 38 | 61 | 1.6 | 498 | 312 | 1.60 |
| Semantic Version Bumper | powershell | opus48-1m-high | 53 | 92 | 1.7 | 567 | 75 | 7.56 |
| Semantic Version Bumper | powershell | opus48-1m-medium | 39 | 62 | 1.6 | 359 | 53 | 6.77 |
| Semantic Version Bumper | powershell-tool | opus48-1m-high | 40 | 69 | 1.7 | 360 | 585 | 0.62 |
| Semantic Version Bumper | powershell-tool | opus48-1m-medium | 35 | 57 | 1.6 | 380 | 118 | 3.22 |
| Semantic Version Bumper | typescript-bun | opus48-1m-high | 51 | 104 | 2.0 | 568 | 475 | 1.20 |
| Semantic Version Bumper | typescript-bun | opus48-1m-medium | 38 | 76 | 2.0 | 462 | 558 | 0.83 |
| PR Label Assigner | bash | opus48-1m-high | 43 | 84 | 2.0 | 506 | 232 | 2.18 |
| PR Label Assigner | bash | opus48-1m-medium | 18 | 10 | 0.6 | 171 | 198 | 0.86 |
| PR Label Assigner | default | opus48-1m-high | 28 | 42 | 1.5 | 266 | 444 | 0.60 |
| PR Label Assigner | default | opus48-1m-medium | 30 | 36 | 1.2 | 222 | 407 | 0.55 |
| PR Label Assigner | powershell | opus48-1m-high | 46 | 70 | 1.5 | 493 | 64 | 7.70 |
| PR Label Assigner | powershell | opus48-1m-medium | 32 | 47 | 1.5 | 261 | 393 | 0.66 |
| PR Label Assigner | powershell-tool | opus48-1m-high | 38 | 57 | 1.5 | 443 | 82 | 5.40 |
| PR Label Assigner | powershell-tool | opus48-1m-medium | 26 | 46 | 1.8 | 210 | 253 | 0.83 |
| PR Label Assigner | typescript-bun | opus48-1m-high | 29 | 43 | 1.5 | 307 | 474 | 0.65 |
| PR Label Assigner | typescript-bun | opus48-1m-medium | 25 | 53 | 2.1 | 362 | 372 | 0.97 |
| Dependency License Checker | bash | opus48-1m-high | 26 | 74 | 2.8 | 449 | 315 | 1.43 |
| Dependency License Checker | bash | opus48-1m-medium | 24 | 52 | 2.2 | 334 | 191 | 1.75 |
| Dependency License Checker | default | opus48-1m-high | 33 | 52 | 1.6 | 314 | 84 | 3.74 |
| Dependency License Checker | default | opus48-1m-medium | 19 | 37 | 1.9 | 212 | 433 | 0.49 |
| Dependency License Checker | powershell | opus48-1m-high | 54 | 79 | 1.5 | 521 | 111 | 4.69 |
| Dependency License Checker | powershell | opus48-1m-medium | 34 | 56 | 1.6 | 386 | 68 | 5.68 |
| Dependency License Checker | powershell-tool | opus48-1m-high | 35 | 63 | 1.8 | 381 | 326 | 1.17 |
| Dependency License Checker | powershell-tool | opus48-1m-medium | 32 | 53 | 1.7 | 388 | 60 | 6.47 |
| Dependency License Checker | typescript-bun | opus48-1m-high | 40 | 106 | 2.6 | 732 | 511 | 1.43 |
| Dependency License Checker | typescript-bun | opus48-1m-medium | 32 | 76 | 2.4 | 548 | 358 | 1.53 |
| Test Results Aggregator | bash | opus48-1m-high | 20 | 63 | 3.1 | 286 | 275 | 1.04 |
| Test Results Aggregator | bash | opus48-1m-medium | 25 | 26 | 1.0 | 221 | 291 | 0.76 |
| Test Results Aggregator | default | opus48-1m-high | 21 | 67 | 3.2 | 451 | 450 | 1.00 |
| Test Results Aggregator | default | opus48-1m-medium | 23 | 63 | 2.7 | 493 | 263 | 1.87 |
| Test Results Aggregator | powershell | opus48-1m-high | 38 | 91 | 2.4 | 527 | 72 | 7.32 |
| Test Results Aggregator | powershell | opus48-1m-medium | 29 | 52 | 1.8 | 250 | 253 | 0.99 |
| Test Results Aggregator | powershell-tool | opus48-1m-high | 38 | 85 | 2.2 | 584 | 92 | 6.35 |
| Test Results Aggregator | powershell-tool | opus48-1m-medium | 31 | 58 | 1.9 | 269 | 568 | 0.47 |
| Test Results Aggregator | typescript-bun | opus48-1m-high | 49 | 98 | 2.0 | 550 | 971 | 0.57 |
| Test Results Aggregator | typescript-bun | opus48-1m-medium | 34 | 57 | 1.7 | 408 | 707 | 0.58 |
| Environment Matrix Generator | bash | opus48-1m-high | 31 | 63 | 2.0 | 306 | 159 | 1.92 |
| Environment Matrix Generator | bash | opus48-1m-medium | 22 | 34 | 1.5 | 278 | 132 | 2.11 |
| Environment Matrix Generator | default | opus48-1m-high | 27 | 49 | 1.8 | 435 | 270 | 1.61 |
| Environment Matrix Generator | default | opus48-1m-medium | 26 | 50 | 1.9 | 350 | 356 | 0.98 |
| Environment Matrix Generator | powershell | opus48-1m-high | 51 | 101 | 2.0 | 510 | 72 | 7.08 |
| Environment Matrix Generator | powershell | opus48-1m-medium | 31 | 71 | 2.3 | 419 | 389 | 1.08 |
| Environment Matrix Generator | powershell-tool | opus48-1m-medium | 31 | 57 | 1.8 | 352 | 36 | 9.78 |
| Secret Rotation Validator | bash | opus48-1m-medium | 27 | 62 | 2.3 | 229 | 372 | 0.62 |
| Secret Rotation Validator | powershell | opus48-1m-medium | 46 | 91 | 2.0 | 446 | 299 | 1.49 |
| Environment Matrix Generator | typescript-bun | opus48-1m-medium | 29 | 55 | 1.9 | 547 | 262 | 2.09 |
| Artifact Cleanup Script | default | opus48-1m-medium | 28 | 54 | 1.9 | 253 | 263 | 0.96 |

</details>

## Per-Run Results

*Tests Quality = Overall (1-5) from LLM-as-judge of generated test code (dimensions: coverage, rigor, design). `—` = no judge data.*

| Task | Language | Model | Duration | Turns | Errors | Cost | Tests Quality | Chosen | Status |
|------|----------|-------|----------|-------|--------|------|-----------|--------|--------|
| Artifact Cleanup Script | default | opus48-1m-medium | 9.9min | 43 | 0 | $2.37 | — | powershell | ok |
| Dependency License Checker | bash | opus48-1m-high | 15.0min | 51 | 3 | $4.02 | — | bash | ok |
| Dependency License Checker | bash | opus48-1m-medium | 5.7min | 24 | 0 | $1.45 | — | bash | ok |
| Dependency License Checker | default | opus48-1m-high | 9.0min | 34 | 0 | $2.24 | — | powershell | ok |
| Dependency License Checker | default | opus48-1m-medium | 7.9min | 33 | 0 | $1.94 | — | python | ok |
| Dependency License Checker | powershell | opus48-1m-high | 12.8min | 42 | 1 | $3.09 | — | powershell | ok |
| Dependency License Checker | powershell | opus48-1m-medium | 7.7min | 33 | 0 | $1.93 | — | powershell | ok |
| Dependency License Checker | powershell-tool | opus48-1m-high | 12.2min | 33 | 0 | $2.63 | — | powershell | ok |
| Dependency License Checker | powershell-tool | opus48-1m-medium | 12.7min | 49 | 0 | $3.35 | — | powershell | ok |
| Dependency License Checker | typescript-bun | opus48-1m-high | 11.5min | 47 | 0 | $3.04 | — | typescript | ok |
| Dependency License Checker | typescript-bun | opus48-1m-medium | 8.7min | 45 | 0 | $2.33 | — | typescript | ok |
| Environment Matrix Generator | bash | opus48-1m-high | 9.4min | 39 | 1 | $2.51 | — | bash | ok |
| Environment Matrix Generator | bash | opus48-1m-medium | 5.8min | 27 | 0 | $1.72 | — | bash | ok |
| Environment Matrix Generator | default | opus48-1m-high | 8.2min | 24 | 0 | $2.01 | — | python | ok |
| Environment Matrix Generator | default | opus48-1m-medium | 6.7min | 28 | 0 | $2.01 | — | python | ok |
| Environment Matrix Generator | powershell | opus48-1m-high | 13.7min | 44 | 1 | $3.48 | — | powershell | ok |
| Environment Matrix Generator | powershell | opus48-1m-medium | 9.3min | 33 | 0 | $2.29 | — | powershell | ok |
| Environment Matrix Generator | powershell-tool | opus48-1m-medium | 12.9min | 52 | 2 | $3.60 | — | powershell | ok |
| Environment Matrix Generator | typescript-bun | opus48-1m-medium | 9.1min | 40 | 0 | $2.29 | — | typescript | ok |
| PR Label Assigner | bash | opus48-1m-high | 10.1min | 31 | 0 | $2.45 | — | bash | ok |
| PR Label Assigner | bash | opus48-1m-medium | 4.8min | 20 | 0 | $1.22 | — | bash | ok |
| PR Label Assigner | default | opus48-1m-high | 7.1min | 25 | 1 | $1.86 | — | python | ok |
| PR Label Assigner | default | opus48-1m-medium | 8.2min | 36 | 1 | $1.91 | — | powershell | ok |
| PR Label Assigner | powershell | opus48-1m-high | 11.0min | 47 | 0 | $2.65 | — | powershell | ok |
| PR Label Assigner | powershell | opus48-1m-medium | 6.3min | 23 | 0 | $1.52 | — | powershell | ok |
| PR Label Assigner | powershell-tool | opus48-1m-high | 11.4min | 41 | 0 | $2.78 | — | powershell | ok |
| PR Label Assigner | powershell-tool | opus48-1m-medium | 7.6min | 27 | 1 | $1.66 | — | powershell | ok |
| PR Label Assigner | typescript-bun | opus48-1m-high | 3.0min | 26 | 1 | $1.17 | — | typescript | ok |
| PR Label Assigner | typescript-bun | opus48-1m-medium | 13.1min | 44 | 0 | $2.48 | — | typescript | ok |
| Secret Rotation Validator | bash | opus48-1m-medium | 23.9min | 64 | 6 | $5.71 | — | bash | ok |
| Secret Rotation Validator | powershell | opus48-1m-medium | 1.1min | 11 | 0 | $0.55 | — | powershell | ok |
| Semantic Version Bumper | bash | opus48-1m-high | 9.5min | 41 | 1 | $2.70 | — | bash | ok |
| Semantic Version Bumper | bash | opus48-1m-medium | 6.8min | 22 | 0 | $1.55 | — | bash | ok |
| Semantic Version Bumper | default | opus48-1m-high | 9.8min | 52 | 0 | $3.34 | — | javascript | ok |
| Semantic Version Bumper | default | opus48-1m-medium | 7.2min | 27 | 0 | $1.83 | — | python | ok |
| Semantic Version Bumper | powershell | opus48-1m-high | 16.9min | 60 | 2 | $3.59 | — | powershell | ok |
| Semantic Version Bumper | powershell | opus48-1m-medium | 10.0min | 34 | 0 | $2.33 | — | powershell | ok |
| Semantic Version Bumper | powershell-tool | opus48-1m-high | 12.1min | 34 | 0 | $2.32 | — | powershell | ok |
| Semantic Version Bumper | powershell-tool | opus48-1m-medium | 10.6min | 40 | 1 | $2.39 | — | powershell | ok |
| Semantic Version Bumper | typescript-bun | opus48-1m-high | 11.5min | 52 | 0 | $3.14 | — | typescript | ok |
| Semantic Version Bumper | typescript-bun | opus48-1m-medium | 9.3min | 47 | 2 | $2.47 | — | typescript | ok |
| Test Results Aggregator | bash | opus48-1m-high | 8.4min | 28 | 0 | $2.20 | — | bash | ok |
| Test Results Aggregator | bash | opus48-1m-medium | 6.3min | 29 | 1 | $1.83 | — | bash | ok |
| Test Results Aggregator | default | opus48-1m-high | 12.2min | 59 | 1 | $3.42 | — | python | ok |
| Test Results Aggregator | default | opus48-1m-medium | 6.6min | 26 | 0 | $1.50 | — | python | ok |
| Test Results Aggregator | powershell | opus48-1m-high | 17.3min | 59 | 0 | $3.84 | — | powershell | ok |
| Test Results Aggregator | powershell | opus48-1m-medium | 8.1min | 30 | 0 | $1.77 | — | powershell | ok |
| Test Results Aggregator | powershell-tool | opus48-1m-high | 15.2min | 47 | 0 | $3.39 | — | powershell | ok |
| Test Results Aggregator | powershell-tool | opus48-1m-medium | 7.4min | 29 | 0 | $1.95 | — | powershell | ok |
| Test Results Aggregator | typescript-bun | opus48-1m-high | 19.2min | 69 | 0 | $5.19 | — | typescript | ok |
| Test Results Aggregator | typescript-bun | opus48-1m-medium | 9.2min | 45 | 0 | $2.57 | — | typescript | ok |


<details>
<summary>Sorted by cost (cheapest first)</summary>

| Task | Language | Model | Duration | Turns | Errors | Cost | Tests Quality | Chosen | Status |
|------|----------|-------|----------|-------|--------|------|-----------|--------|--------|
| Secret Rotation Validator | powershell | opus48-1m-medium | 1.1min | 11 | 0 | $0.55 | — | powershell | ok |
| PR Label Assigner | typescript-bun | opus48-1m-high | 3.0min | 26 | 1 | $1.17 | — | typescript | ok |
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
| PR Label Assigner | default | opus48-1m-high | 7.1min | 25 | 1 | $1.86 | — | python | ok |
| PR Label Assigner | default | opus48-1m-medium | 8.2min | 36 | 1 | $1.91 | — | powershell | ok |
| Dependency License Checker | powershell | opus48-1m-medium | 7.7min | 33 | 0 | $1.93 | — | powershell | ok |
| Dependency License Checker | default | opus48-1m-medium | 7.9min | 33 | 0 | $1.94 | — | python | ok |
| Test Results Aggregator | powershell-tool | opus48-1m-medium | 7.4min | 29 | 0 | $1.95 | — | powershell | ok |
| Environment Matrix Generator | default | opus48-1m-medium | 6.7min | 28 | 0 | $2.01 | — | python | ok |
| Environment Matrix Generator | default | opus48-1m-high | 8.2min | 24 | 0 | $2.01 | — | python | ok |
| Test Results Aggregator | bash | opus48-1m-high | 8.4min | 28 | 0 | $2.20 | — | bash | ok |
| Dependency License Checker | default | opus48-1m-high | 9.0min | 34 | 0 | $2.24 | — | powershell | ok |
| Environment Matrix Generator | typescript-bun | opus48-1m-medium | 9.1min | 40 | 0 | $2.29 | — | typescript | ok |
| Environment Matrix Generator | powershell | opus48-1m-medium | 9.3min | 33 | 0 | $2.29 | — | powershell | ok |
| Semantic Version Bumper | powershell-tool | opus48-1m-high | 12.1min | 34 | 0 | $2.32 | — | powershell | ok |
| Dependency License Checker | typescript-bun | opus48-1m-medium | 8.7min | 45 | 0 | $2.33 | — | typescript | ok |
| Semantic Version Bumper | powershell | opus48-1m-medium | 10.0min | 34 | 0 | $2.33 | — | powershell | ok |
| Artifact Cleanup Script | default | opus48-1m-medium | 9.9min | 43 | 0 | $2.37 | — | powershell | ok |
| Semantic Version Bumper | powershell-tool | opus48-1m-medium | 10.6min | 40 | 1 | $2.39 | — | powershell | ok |
| PR Label Assigner | bash | opus48-1m-high | 10.1min | 31 | 0 | $2.45 | — | bash | ok |
| Semantic Version Bumper | typescript-bun | opus48-1m-medium | 9.3min | 47 | 2 | $2.47 | — | typescript | ok |
| PR Label Assigner | typescript-bun | opus48-1m-medium | 13.1min | 44 | 0 | $2.48 | — | typescript | ok |
| Environment Matrix Generator | bash | opus48-1m-high | 9.4min | 39 | 1 | $2.51 | — | bash | ok |
| Test Results Aggregator | typescript-bun | opus48-1m-medium | 9.2min | 45 | 0 | $2.57 | — | typescript | ok |
| Dependency License Checker | powershell-tool | opus48-1m-high | 12.2min | 33 | 0 | $2.63 | — | powershell | ok |
| PR Label Assigner | powershell | opus48-1m-high | 11.0min | 47 | 0 | $2.65 | — | powershell | ok |
| Semantic Version Bumper | bash | opus48-1m-high | 9.5min | 41 | 1 | $2.70 | — | bash | ok |
| PR Label Assigner | powershell-tool | opus48-1m-high | 11.4min | 41 | 0 | $2.78 | — | powershell | ok |
| Dependency License Checker | typescript-bun | opus48-1m-high | 11.5min | 47 | 0 | $3.04 | — | typescript | ok |
| Dependency License Checker | powershell | opus48-1m-high | 12.8min | 42 | 1 | $3.09 | — | powershell | ok |
| Semantic Version Bumper | typescript-bun | opus48-1m-high | 11.5min | 52 | 0 | $3.14 | — | typescript | ok |
| Semantic Version Bumper | default | opus48-1m-high | 9.8min | 52 | 0 | $3.34 | — | javascript | ok |
| Dependency License Checker | powershell-tool | opus48-1m-medium | 12.7min | 49 | 0 | $3.35 | — | powershell | ok |
| Test Results Aggregator | powershell-tool | opus48-1m-high | 15.2min | 47 | 0 | $3.39 | — | powershell | ok |
| Test Results Aggregator | default | opus48-1m-high | 12.2min | 59 | 1 | $3.42 | — | python | ok |
| Environment Matrix Generator | powershell | opus48-1m-high | 13.7min | 44 | 1 | $3.48 | — | powershell | ok |
| Semantic Version Bumper | powershell | opus48-1m-high | 16.9min | 60 | 2 | $3.59 | — | powershell | ok |
| Environment Matrix Generator | powershell-tool | opus48-1m-medium | 12.9min | 52 | 2 | $3.60 | — | powershell | ok |
| Test Results Aggregator | powershell | opus48-1m-high | 17.3min | 59 | 0 | $3.84 | — | powershell | ok |
| Dependency License Checker | bash | opus48-1m-high | 15.0min | 51 | 3 | $4.02 | — | bash | ok |
| Test Results Aggregator | typescript-bun | opus48-1m-high | 19.2min | 69 | 0 | $5.19 | — | typescript | ok |
| Secret Rotation Validator | bash | opus48-1m-medium | 23.9min | 64 | 6 | $5.71 | — | bash | ok |

</details>

<details>
<summary>Sorted by duration (fastest first)</summary>

| Task | Language | Model | Duration | Turns | Errors | Cost | Tests Quality | Chosen | Status |
|------|----------|-------|----------|-------|--------|------|-----------|--------|--------|
| Secret Rotation Validator | powershell | opus48-1m-medium | 1.1min | 11 | 0 | $0.55 | — | powershell | ok |
| PR Label Assigner | typescript-bun | opus48-1m-high | 3.0min | 26 | 1 | $1.17 | — | typescript | ok |
| PR Label Assigner | bash | opus48-1m-medium | 4.8min | 20 | 0 | $1.22 | — | bash | ok |
| Dependency License Checker | bash | opus48-1m-medium | 5.7min | 24 | 0 | $1.45 | — | bash | ok |
| Environment Matrix Generator | bash | opus48-1m-medium | 5.8min | 27 | 0 | $1.72 | — | bash | ok |
| Test Results Aggregator | bash | opus48-1m-medium | 6.3min | 29 | 1 | $1.83 | — | bash | ok |
| PR Label Assigner | powershell | opus48-1m-medium | 6.3min | 23 | 0 | $1.52 | — | powershell | ok |
| Test Results Aggregator | default | opus48-1m-medium | 6.6min | 26 | 0 | $1.50 | — | python | ok |
| Environment Matrix Generator | default | opus48-1m-medium | 6.7min | 28 | 0 | $2.01 | — | python | ok |
| Semantic Version Bumper | bash | opus48-1m-medium | 6.8min | 22 | 0 | $1.55 | — | bash | ok |
| PR Label Assigner | default | opus48-1m-high | 7.1min | 25 | 1 | $1.86 | — | python | ok |
| Semantic Version Bumper | default | opus48-1m-medium | 7.2min | 27 | 0 | $1.83 | — | python | ok |
| Test Results Aggregator | powershell-tool | opus48-1m-medium | 7.4min | 29 | 0 | $1.95 | — | powershell | ok |
| PR Label Assigner | powershell-tool | opus48-1m-medium | 7.6min | 27 | 1 | $1.66 | — | powershell | ok |
| Dependency License Checker | powershell | opus48-1m-medium | 7.7min | 33 | 0 | $1.93 | — | powershell | ok |
| Dependency License Checker | default | opus48-1m-medium | 7.9min | 33 | 0 | $1.94 | — | python | ok |
| Test Results Aggregator | powershell | opus48-1m-medium | 8.1min | 30 | 0 | $1.77 | — | powershell | ok |
| PR Label Assigner | default | opus48-1m-medium | 8.2min | 36 | 1 | $1.91 | — | powershell | ok |
| Environment Matrix Generator | default | opus48-1m-high | 8.2min | 24 | 0 | $2.01 | — | python | ok |
| Test Results Aggregator | bash | opus48-1m-high | 8.4min | 28 | 0 | $2.20 | — | bash | ok |
| Dependency License Checker | typescript-bun | opus48-1m-medium | 8.7min | 45 | 0 | $2.33 | — | typescript | ok |
| Dependency License Checker | default | opus48-1m-high | 9.0min | 34 | 0 | $2.24 | — | powershell | ok |
| Environment Matrix Generator | typescript-bun | opus48-1m-medium | 9.1min | 40 | 0 | $2.29 | — | typescript | ok |
| Test Results Aggregator | typescript-bun | opus48-1m-medium | 9.2min | 45 | 0 | $2.57 | — | typescript | ok |
| Semantic Version Bumper | typescript-bun | opus48-1m-medium | 9.3min | 47 | 2 | $2.47 | — | typescript | ok |
| Environment Matrix Generator | powershell | opus48-1m-medium | 9.3min | 33 | 0 | $2.29 | — | powershell | ok |
| Environment Matrix Generator | bash | opus48-1m-high | 9.4min | 39 | 1 | $2.51 | — | bash | ok |
| Semantic Version Bumper | bash | opus48-1m-high | 9.5min | 41 | 1 | $2.70 | — | bash | ok |
| Semantic Version Bumper | default | opus48-1m-high | 9.8min | 52 | 0 | $3.34 | — | javascript | ok |
| Artifact Cleanup Script | default | opus48-1m-medium | 9.9min | 43 | 0 | $2.37 | — | powershell | ok |
| Semantic Version Bumper | powershell | opus48-1m-medium | 10.0min | 34 | 0 | $2.33 | — | powershell | ok |
| PR Label Assigner | bash | opus48-1m-high | 10.1min | 31 | 0 | $2.45 | — | bash | ok |
| Semantic Version Bumper | powershell-tool | opus48-1m-medium | 10.6min | 40 | 1 | $2.39 | — | powershell | ok |
| PR Label Assigner | powershell | opus48-1m-high | 11.0min | 47 | 0 | $2.65 | — | powershell | ok |
| PR Label Assigner | powershell-tool | opus48-1m-high | 11.4min | 41 | 0 | $2.78 | — | powershell | ok |
| Semantic Version Bumper | typescript-bun | opus48-1m-high | 11.5min | 52 | 0 | $3.14 | — | typescript | ok |
| Dependency License Checker | typescript-bun | opus48-1m-high | 11.5min | 47 | 0 | $3.04 | — | typescript | ok |
| Semantic Version Bumper | powershell-tool | opus48-1m-high | 12.1min | 34 | 0 | $2.32 | — | powershell | ok |
| Dependency License Checker | powershell-tool | opus48-1m-high | 12.2min | 33 | 0 | $2.63 | — | powershell | ok |
| Test Results Aggregator | default | opus48-1m-high | 12.2min | 59 | 1 | $3.42 | — | python | ok |
| Dependency License Checker | powershell-tool | opus48-1m-medium | 12.7min | 49 | 0 | $3.35 | — | powershell | ok |
| Dependency License Checker | powershell | opus48-1m-high | 12.8min | 42 | 1 | $3.09 | — | powershell | ok |
| Environment Matrix Generator | powershell-tool | opus48-1m-medium | 12.9min | 52 | 2 | $3.60 | — | powershell | ok |
| PR Label Assigner | typescript-bun | opus48-1m-medium | 13.1min | 44 | 0 | $2.48 | — | typescript | ok |
| Environment Matrix Generator | powershell | opus48-1m-high | 13.7min | 44 | 1 | $3.48 | — | powershell | ok |
| Dependency License Checker | bash | opus48-1m-high | 15.0min | 51 | 3 | $4.02 | — | bash | ok |
| Test Results Aggregator | powershell-tool | opus48-1m-high | 15.2min | 47 | 0 | $3.39 | — | powershell | ok |
| Semantic Version Bumper | powershell | opus48-1m-high | 16.9min | 60 | 2 | $3.59 | — | powershell | ok |
| Test Results Aggregator | powershell | opus48-1m-high | 17.3min | 59 | 0 | $3.84 | — | powershell | ok |
| Test Results Aggregator | typescript-bun | opus48-1m-high | 19.2min | 69 | 0 | $5.19 | — | typescript | ok |
| Secret Rotation Validator | bash | opus48-1m-medium | 23.9min | 64 | 6 | $5.71 | — | bash | ok |

</details>

<details>
<summary>Sorted by errors (fewest first)</summary>

| Task | Language | Model | Duration | Turns | Errors | Cost | Tests Quality | Chosen | Status |
|------|----------|-------|----------|-------|--------|------|-----------|--------|--------|
| Semantic Version Bumper | bash | opus48-1m-medium | 6.8min | 22 | 0 | $1.55 | — | bash | ok |
| Semantic Version Bumper | default | opus48-1m-high | 9.8min | 52 | 0 | $3.34 | — | javascript | ok |
| Semantic Version Bumper | default | opus48-1m-medium | 7.2min | 27 | 0 | $1.83 | — | python | ok |
| Semantic Version Bumper | powershell | opus48-1m-medium | 10.0min | 34 | 0 | $2.33 | — | powershell | ok |
| Semantic Version Bumper | powershell-tool | opus48-1m-high | 12.1min | 34 | 0 | $2.32 | — | powershell | ok |
| Semantic Version Bumper | typescript-bun | opus48-1m-high | 11.5min | 52 | 0 | $3.14 | — | typescript | ok |
| PR Label Assigner | bash | opus48-1m-high | 10.1min | 31 | 0 | $2.45 | — | bash | ok |
| PR Label Assigner | bash | opus48-1m-medium | 4.8min | 20 | 0 | $1.22 | — | bash | ok |
| PR Label Assigner | powershell | opus48-1m-high | 11.0min | 47 | 0 | $2.65 | — | powershell | ok |
| PR Label Assigner | powershell | opus48-1m-medium | 6.3min | 23 | 0 | $1.52 | — | powershell | ok |
| PR Label Assigner | powershell-tool | opus48-1m-high | 11.4min | 41 | 0 | $2.78 | — | powershell | ok |
| PR Label Assigner | typescript-bun | opus48-1m-medium | 13.1min | 44 | 0 | $2.48 | — | typescript | ok |
| Dependency License Checker | bash | opus48-1m-medium | 5.7min | 24 | 0 | $1.45 | — | bash | ok |
| Dependency License Checker | default | opus48-1m-high | 9.0min | 34 | 0 | $2.24 | — | powershell | ok |
| Dependency License Checker | default | opus48-1m-medium | 7.9min | 33 | 0 | $1.94 | — | python | ok |
| Dependency License Checker | powershell | opus48-1m-medium | 7.7min | 33 | 0 | $1.93 | — | powershell | ok |
| Dependency License Checker | powershell-tool | opus48-1m-high | 12.2min | 33 | 0 | $2.63 | — | powershell | ok |
| Dependency License Checker | powershell-tool | opus48-1m-medium | 12.7min | 49 | 0 | $3.35 | — | powershell | ok |
| Dependency License Checker | typescript-bun | opus48-1m-high | 11.5min | 47 | 0 | $3.04 | — | typescript | ok |
| Dependency License Checker | typescript-bun | opus48-1m-medium | 8.7min | 45 | 0 | $2.33 | — | typescript | ok |
| Test Results Aggregator | bash | opus48-1m-high | 8.4min | 28 | 0 | $2.20 | — | bash | ok |
| Test Results Aggregator | default | opus48-1m-medium | 6.6min | 26 | 0 | $1.50 | — | python | ok |
| Test Results Aggregator | powershell | opus48-1m-high | 17.3min | 59 | 0 | $3.84 | — | powershell | ok |
| Test Results Aggregator | powershell | opus48-1m-medium | 8.1min | 30 | 0 | $1.77 | — | powershell | ok |
| Test Results Aggregator | powershell-tool | opus48-1m-high | 15.2min | 47 | 0 | $3.39 | — | powershell | ok |
| Test Results Aggregator | powershell-tool | opus48-1m-medium | 7.4min | 29 | 0 | $1.95 | — | powershell | ok |
| Test Results Aggregator | typescript-bun | opus48-1m-high | 19.2min | 69 | 0 | $5.19 | — | typescript | ok |
| Test Results Aggregator | typescript-bun | opus48-1m-medium | 9.2min | 45 | 0 | $2.57 | — | typescript | ok |
| Environment Matrix Generator | bash | opus48-1m-medium | 5.8min | 27 | 0 | $1.72 | — | bash | ok |
| Environment Matrix Generator | default | opus48-1m-high | 8.2min | 24 | 0 | $2.01 | — | python | ok |
| Environment Matrix Generator | default | opus48-1m-medium | 6.7min | 28 | 0 | $2.01 | — | python | ok |
| Environment Matrix Generator | powershell | opus48-1m-medium | 9.3min | 33 | 0 | $2.29 | — | powershell | ok |
| Secret Rotation Validator | powershell | opus48-1m-medium | 1.1min | 11 | 0 | $0.55 | — | powershell | ok |
| Environment Matrix Generator | typescript-bun | opus48-1m-medium | 9.1min | 40 | 0 | $2.29 | — | typescript | ok |
| Artifact Cleanup Script | default | opus48-1m-medium | 9.9min | 43 | 0 | $2.37 | — | powershell | ok |
| Semantic Version Bumper | bash | opus48-1m-high | 9.5min | 41 | 1 | $2.70 | — | bash | ok |
| Semantic Version Bumper | powershell-tool | opus48-1m-medium | 10.6min | 40 | 1 | $2.39 | — | powershell | ok |
| PR Label Assigner | default | opus48-1m-high | 7.1min | 25 | 1 | $1.86 | — | python | ok |
| PR Label Assigner | default | opus48-1m-medium | 8.2min | 36 | 1 | $1.91 | — | powershell | ok |
| PR Label Assigner | powershell-tool | opus48-1m-medium | 7.6min | 27 | 1 | $1.66 | — | powershell | ok |
| PR Label Assigner | typescript-bun | opus48-1m-high | 3.0min | 26 | 1 | $1.17 | — | typescript | ok |
| Dependency License Checker | powershell | opus48-1m-high | 12.8min | 42 | 1 | $3.09 | — | powershell | ok |
| Test Results Aggregator | bash | opus48-1m-medium | 6.3min | 29 | 1 | $1.83 | — | bash | ok |
| Test Results Aggregator | default | opus48-1m-high | 12.2min | 59 | 1 | $3.42 | — | python | ok |
| Environment Matrix Generator | bash | opus48-1m-high | 9.4min | 39 | 1 | $2.51 | — | bash | ok |
| Environment Matrix Generator | powershell | opus48-1m-high | 13.7min | 44 | 1 | $3.48 | — | powershell | ok |
| Semantic Version Bumper | powershell | opus48-1m-high | 16.9min | 60 | 2 | $3.59 | — | powershell | ok |
| Semantic Version Bumper | typescript-bun | opus48-1m-medium | 9.3min | 47 | 2 | $2.47 | — | typescript | ok |
| Environment Matrix Generator | powershell-tool | opus48-1m-medium | 12.9min | 52 | 2 | $3.60 | — | powershell | ok |
| Dependency License Checker | bash | opus48-1m-high | 15.0min | 51 | 3 | $4.02 | — | bash | ok |
| Secret Rotation Validator | bash | opus48-1m-medium | 23.9min | 64 | 6 | $5.71 | — | bash | ok |

</details>

<details>
<summary>Sorted by turns (fewest first)</summary>

| Task | Language | Model | Duration | Turns | Errors | Cost | Tests Quality | Chosen | Status |
|------|----------|-------|----------|-------|--------|------|-----------|--------|--------|
| Secret Rotation Validator | powershell | opus48-1m-medium | 1.1min | 11 | 0 | $0.55 | — | powershell | ok |
| PR Label Assigner | bash | opus48-1m-medium | 4.8min | 20 | 0 | $1.22 | — | bash | ok |
| Semantic Version Bumper | bash | opus48-1m-medium | 6.8min | 22 | 0 | $1.55 | — | bash | ok |
| PR Label Assigner | powershell | opus48-1m-medium | 6.3min | 23 | 0 | $1.52 | — | powershell | ok |
| Dependency License Checker | bash | opus48-1m-medium | 5.7min | 24 | 0 | $1.45 | — | bash | ok |
| Environment Matrix Generator | default | opus48-1m-high | 8.2min | 24 | 0 | $2.01 | — | python | ok |
| PR Label Assigner | default | opus48-1m-high | 7.1min | 25 | 1 | $1.86 | — | python | ok |
| PR Label Assigner | typescript-bun | opus48-1m-high | 3.0min | 26 | 1 | $1.17 | — | typescript | ok |
| Test Results Aggregator | default | opus48-1m-medium | 6.6min | 26 | 0 | $1.50 | — | python | ok |
| Semantic Version Bumper | default | opus48-1m-medium | 7.2min | 27 | 0 | $1.83 | — | python | ok |
| PR Label Assigner | powershell-tool | opus48-1m-medium | 7.6min | 27 | 1 | $1.66 | — | powershell | ok |
| Environment Matrix Generator | bash | opus48-1m-medium | 5.8min | 27 | 0 | $1.72 | — | bash | ok |
| Test Results Aggregator | bash | opus48-1m-high | 8.4min | 28 | 0 | $2.20 | — | bash | ok |
| Environment Matrix Generator | default | opus48-1m-medium | 6.7min | 28 | 0 | $2.01 | — | python | ok |
| Test Results Aggregator | bash | opus48-1m-medium | 6.3min | 29 | 1 | $1.83 | — | bash | ok |
| Test Results Aggregator | powershell-tool | opus48-1m-medium | 7.4min | 29 | 0 | $1.95 | — | powershell | ok |
| Test Results Aggregator | powershell | opus48-1m-medium | 8.1min | 30 | 0 | $1.77 | — | powershell | ok |
| PR Label Assigner | bash | opus48-1m-high | 10.1min | 31 | 0 | $2.45 | — | bash | ok |
| Dependency License Checker | default | opus48-1m-medium | 7.9min | 33 | 0 | $1.94 | — | python | ok |
| Dependency License Checker | powershell | opus48-1m-medium | 7.7min | 33 | 0 | $1.93 | — | powershell | ok |
| Dependency License Checker | powershell-tool | opus48-1m-high | 12.2min | 33 | 0 | $2.63 | — | powershell | ok |
| Environment Matrix Generator | powershell | opus48-1m-medium | 9.3min | 33 | 0 | $2.29 | — | powershell | ok |
| Semantic Version Bumper | powershell | opus48-1m-medium | 10.0min | 34 | 0 | $2.33 | — | powershell | ok |
| Semantic Version Bumper | powershell-tool | opus48-1m-high | 12.1min | 34 | 0 | $2.32 | — | powershell | ok |
| Dependency License Checker | default | opus48-1m-high | 9.0min | 34 | 0 | $2.24 | — | powershell | ok |
| PR Label Assigner | default | opus48-1m-medium | 8.2min | 36 | 1 | $1.91 | — | powershell | ok |
| Environment Matrix Generator | bash | opus48-1m-high | 9.4min | 39 | 1 | $2.51 | — | bash | ok |
| Semantic Version Bumper | powershell-tool | opus48-1m-medium | 10.6min | 40 | 1 | $2.39 | — | powershell | ok |
| Environment Matrix Generator | typescript-bun | opus48-1m-medium | 9.1min | 40 | 0 | $2.29 | — | typescript | ok |
| Semantic Version Bumper | bash | opus48-1m-high | 9.5min | 41 | 1 | $2.70 | — | bash | ok |
| PR Label Assigner | powershell-tool | opus48-1m-high | 11.4min | 41 | 0 | $2.78 | — | powershell | ok |
| Dependency License Checker | powershell | opus48-1m-high | 12.8min | 42 | 1 | $3.09 | — | powershell | ok |
| Artifact Cleanup Script | default | opus48-1m-medium | 9.9min | 43 | 0 | $2.37 | — | powershell | ok |
| PR Label Assigner | typescript-bun | opus48-1m-medium | 13.1min | 44 | 0 | $2.48 | — | typescript | ok |
| Environment Matrix Generator | powershell | opus48-1m-high | 13.7min | 44 | 1 | $3.48 | — | powershell | ok |
| Dependency License Checker | typescript-bun | opus48-1m-medium | 8.7min | 45 | 0 | $2.33 | — | typescript | ok |
| Test Results Aggregator | typescript-bun | opus48-1m-medium | 9.2min | 45 | 0 | $2.57 | — | typescript | ok |
| Semantic Version Bumper | typescript-bun | opus48-1m-medium | 9.3min | 47 | 2 | $2.47 | — | typescript | ok |
| PR Label Assigner | powershell | opus48-1m-high | 11.0min | 47 | 0 | $2.65 | — | powershell | ok |
| Dependency License Checker | typescript-bun | opus48-1m-high | 11.5min | 47 | 0 | $3.04 | — | typescript | ok |
| Test Results Aggregator | powershell-tool | opus48-1m-high | 15.2min | 47 | 0 | $3.39 | — | powershell | ok |
| Dependency License Checker | powershell-tool | opus48-1m-medium | 12.7min | 49 | 0 | $3.35 | — | powershell | ok |
| Dependency License Checker | bash | opus48-1m-high | 15.0min | 51 | 3 | $4.02 | — | bash | ok |
| Semantic Version Bumper | default | opus48-1m-high | 9.8min | 52 | 0 | $3.34 | — | javascript | ok |
| Semantic Version Bumper | typescript-bun | opus48-1m-high | 11.5min | 52 | 0 | $3.14 | — | typescript | ok |
| Environment Matrix Generator | powershell-tool | opus48-1m-medium | 12.9min | 52 | 2 | $3.60 | — | powershell | ok |
| Test Results Aggregator | default | opus48-1m-high | 12.2min | 59 | 1 | $3.42 | — | python | ok |
| Test Results Aggregator | powershell | opus48-1m-high | 17.3min | 59 | 0 | $3.84 | — | powershell | ok |
| Semantic Version Bumper | powershell | opus48-1m-high | 16.9min | 60 | 2 | $3.59 | — | powershell | ok |
| Secret Rotation Validator | bash | opus48-1m-medium | 23.9min | 64 | 6 | $5.71 | — | bash | ok |
| Test Results Aggregator | typescript-bun | opus48-1m-high | 19.2min | 69 | 0 | $5.19 | — | typescript | ok |

</details>

<details>
<summary>Sorted by LLM-as-judge score (best first)</summary>

| Task | Language | Model | Duration | Turns | Errors | Cost | Tests Quality | Chosen | Status |
|------|----------|-------|----------|-------|--------|------|-----------|--------|--------|
| Semantic Version Bumper | bash | opus48-1m-high | 9.5min | 41 | 1 | $2.70 | — | bash | ok |
| Semantic Version Bumper | bash | opus48-1m-medium | 6.8min | 22 | 0 | $1.55 | — | bash | ok |
| Semantic Version Bumper | default | opus48-1m-high | 9.8min | 52 | 0 | $3.34 | — | javascript | ok |
| Semantic Version Bumper | default | opus48-1m-medium | 7.2min | 27 | 0 | $1.83 | — | python | ok |
| Semantic Version Bumper | powershell | opus48-1m-high | 16.9min | 60 | 2 | $3.59 | — | powershell | ok |
| Semantic Version Bumper | powershell | opus48-1m-medium | 10.0min | 34 | 0 | $2.33 | — | powershell | ok |
| Semantic Version Bumper | powershell-tool | opus48-1m-high | 12.1min | 34 | 0 | $2.32 | — | powershell | ok |
| Semantic Version Bumper | powershell-tool | opus48-1m-medium | 10.6min | 40 | 1 | $2.39 | — | powershell | ok |
| Semantic Version Bumper | typescript-bun | opus48-1m-high | 11.5min | 52 | 0 | $3.14 | — | typescript | ok |
| Semantic Version Bumper | typescript-bun | opus48-1m-medium | 9.3min | 47 | 2 | $2.47 | — | typescript | ok |
| PR Label Assigner | bash | opus48-1m-high | 10.1min | 31 | 0 | $2.45 | — | bash | ok |
| PR Label Assigner | bash | opus48-1m-medium | 4.8min | 20 | 0 | $1.22 | — | bash | ok |
| PR Label Assigner | default | opus48-1m-high | 7.1min | 25 | 1 | $1.86 | — | python | ok |
| PR Label Assigner | default | opus48-1m-medium | 8.2min | 36 | 1 | $1.91 | — | powershell | ok |
| PR Label Assigner | powershell | opus48-1m-high | 11.0min | 47 | 0 | $2.65 | — | powershell | ok |
| PR Label Assigner | powershell | opus48-1m-medium | 6.3min | 23 | 0 | $1.52 | — | powershell | ok |
| PR Label Assigner | powershell-tool | opus48-1m-high | 11.4min | 41 | 0 | $2.78 | — | powershell | ok |
| PR Label Assigner | powershell-tool | opus48-1m-medium | 7.6min | 27 | 1 | $1.66 | — | powershell | ok |
| PR Label Assigner | typescript-bun | opus48-1m-high | 3.0min | 26 | 1 | $1.17 | — | typescript | ok |
| PR Label Assigner | typescript-bun | opus48-1m-medium | 13.1min | 44 | 0 | $2.48 | — | typescript | ok |
| Dependency License Checker | bash | opus48-1m-high | 15.0min | 51 | 3 | $4.02 | — | bash | ok |
| Dependency License Checker | bash | opus48-1m-medium | 5.7min | 24 | 0 | $1.45 | — | bash | ok |
| Dependency License Checker | default | opus48-1m-high | 9.0min | 34 | 0 | $2.24 | — | powershell | ok |
| Dependency License Checker | default | opus48-1m-medium | 7.9min | 33 | 0 | $1.94 | — | python | ok |
| Dependency License Checker | powershell | opus48-1m-high | 12.8min | 42 | 1 | $3.09 | — | powershell | ok |
| Dependency License Checker | powershell | opus48-1m-medium | 7.7min | 33 | 0 | $1.93 | — | powershell | ok |
| Dependency License Checker | powershell-tool | opus48-1m-high | 12.2min | 33 | 0 | $2.63 | — | powershell | ok |
| Dependency License Checker | powershell-tool | opus48-1m-medium | 12.7min | 49 | 0 | $3.35 | — | powershell | ok |
| Dependency License Checker | typescript-bun | opus48-1m-high | 11.5min | 47 | 0 | $3.04 | — | typescript | ok |
| Dependency License Checker | typescript-bun | opus48-1m-medium | 8.7min | 45 | 0 | $2.33 | — | typescript | ok |
| Test Results Aggregator | bash | opus48-1m-high | 8.4min | 28 | 0 | $2.20 | — | bash | ok |
| Test Results Aggregator | bash | opus48-1m-medium | 6.3min | 29 | 1 | $1.83 | — | bash | ok |
| Test Results Aggregator | default | opus48-1m-high | 12.2min | 59 | 1 | $3.42 | — | python | ok |
| Test Results Aggregator | default | opus48-1m-medium | 6.6min | 26 | 0 | $1.50 | — | python | ok |
| Test Results Aggregator | powershell | opus48-1m-high | 17.3min | 59 | 0 | $3.84 | — | powershell | ok |
| Test Results Aggregator | powershell | opus48-1m-medium | 8.1min | 30 | 0 | $1.77 | — | powershell | ok |
| Test Results Aggregator | powershell-tool | opus48-1m-high | 15.2min | 47 | 0 | $3.39 | — | powershell | ok |
| Test Results Aggregator | powershell-tool | opus48-1m-medium | 7.4min | 29 | 0 | $1.95 | — | powershell | ok |
| Test Results Aggregator | typescript-bun | opus48-1m-high | 19.2min | 69 | 0 | $5.19 | — | typescript | ok |
| Test Results Aggregator | typescript-bun | opus48-1m-medium | 9.2min | 45 | 0 | $2.57 | — | typescript | ok |
| Environment Matrix Generator | bash | opus48-1m-high | 9.4min | 39 | 1 | $2.51 | — | bash | ok |
| Environment Matrix Generator | bash | opus48-1m-medium | 5.8min | 27 | 0 | $1.72 | — | bash | ok |
| Environment Matrix Generator | default | opus48-1m-high | 8.2min | 24 | 0 | $2.01 | — | python | ok |
| Environment Matrix Generator | default | opus48-1m-medium | 6.7min | 28 | 0 | $2.01 | — | python | ok |
| Environment Matrix Generator | powershell | opus48-1m-high | 13.7min | 44 | 1 | $3.48 | — | powershell | ok |
| Environment Matrix Generator | powershell | opus48-1m-medium | 9.3min | 33 | 0 | $2.29 | — | powershell | ok |
| Environment Matrix Generator | powershell-tool | opus48-1m-medium | 12.9min | 52 | 2 | $3.60 | — | powershell | ok |
| Secret Rotation Validator | bash | opus48-1m-medium | 23.9min | 64 | 6 | $5.71 | — | bash | ok |
| Secret Rotation Validator | powershell | opus48-1m-medium | 1.1min | 11 | 0 | $0.55 | — | powershell | ok |
| Environment Matrix Generator | typescript-bun | opus48-1m-medium | 9.1min | 40 | 0 | $2.29 | — | typescript | ok |
| Artifact Cleanup Script | default | opus48-1m-medium | 9.9min | 43 | 0 | $2.37 | — | powershell | ok |

</details>

## Notes

### Tiers

- **Duration bands:** **A+** ≤1.06×, **A** ≤1.12×, **A-** ≤1.19×, **B+** ≤1.27×, **B** ≤1.34×, **B-** ≤1.42×, **C+** ≤1.51×, **C** ≤1.60×, **C-** ≤1.70×, **D+** ≤1.80×, **D** ≤1.91×, **D-** ≤2.02×, **F** >2.02×
- **Cost bands:** **A+** ≤1.06×, **A** ≤1.12×, **A-** ≤1.18×, **B+** ≤1.24×, **B** ≤1.31×, **B-** ≤1.39×, **C+** ≤1.46×, **C** ≤1.55×, **C-** ≤1.63×, **D+** ≤1.73×, **D** ≤1.82×, **D-** ≤1.92×, **F** >1.92×

*Tests/Workflow Craft bands are absolute Overall score bands:* **A+** ≥4.7, **A** ≥4.4, **A-** ≥4.1, **B+** ≥3.8, **B** ≥3.5, **B-** ≥3.2, **C+** ≥2.9, **C** ≥2.6, **C-** ≥2.3, **D+** ≥2.0, **D** ≥1.7, **D-** ≥1.4, **F** <1.4, `—` = no data.*

### CLI Version Legend

| Variant label | CLI version | Tasks | Languages |
|---------------|-------------|-------|-----------|
| opus48-1m-high | 2.1.195 | 11-semantic-version-bumper, 12-pr-label-assigner, 13-dependency-license-checker, 15-test-results-aggregator, 16-environment-matrix-generator | All |
| opus48-1m-medium | 2.1.193 | 11-semantic-version-bumper, 12-pr-label-assigner, 13-dependency-license-checker, 15-test-results-aggregator, 16-environment-matrix-generator | All |
| opus48-1m-medium | 2.1.195 | 16-environment-matrix-generator, 17-artifact-cleanup-script, 18-secret-rotation-validator | All |

---
*Generated by generate_results.py — benchmark instructions v4*