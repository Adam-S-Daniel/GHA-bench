# Benchmark Results: Language Comparison

**Last updated:** 2026-06-27 02:43:47 PM ET — 67/70 runs completed, 3 remaining; total cost $178.12; total agent time 692.6 min.
**Claude Code versions used:** v2.1.193 (23 runs), v2.1.195 (44 runs). Each link goes to a per-version snapshot of the system prompt, default-tool descriptions, and the chronological Anthropic changelog up to that version. Regenerate with `python3 version_docs.py`.

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
| default | opus48-1m-medium | A+ (7.5min) | A+ ($1.89) | — | — |
| powershell | opus48-1m-medium | A+ (7.4min) | A+ ($1.81) | — | — |
| bash | opus48-1m-medium | B (9.2min) | B ($2.38) | — | — |
| default | opus48-1m-high | B (9.4min) | C+ ($2.74) | — | — |
| powershell-tool | opus48-1m-medium | C+ (10.1min) | B- ($2.57) | — | — |
| bash | opus48-1m-high | C (10.7min) | C ($2.87) | — | — |
| typescript-bun | opus48-1m-medium | C- (11.7min) | C+ ($2.73) | — | — |
| powershell-tool | opus48-1m-high | D+ (12.0min) | C ($2.83) | — | — |
| powershell | opus48-1m-high | D- (13.8min) | D+ ($3.24) | — | — |
| typescript-bun | opus48-1m-high | D+ (12.2min) | D- ($3.75) | — | — |


<details>
<summary>Sorted by Duration tier (best-first), then avg of Cost/Tests/Workflow Craft tiers</summary>

| Language | Model | Duration | Cost | Tests Quality | Workflow Craft |
|----------|-------|----------|------|-----------|-------------|
| default | opus48-1m-medium | A+ (7.5min) | A+ ($1.89) | — | — |
| powershell | opus48-1m-medium | A+ (7.4min) | A+ ($1.81) | — | — |
| bash | opus48-1m-medium | B (9.2min) | B ($2.38) | — | — |
| default | opus48-1m-high | B (9.4min) | C+ ($2.74) | — | — |
| powershell-tool | opus48-1m-medium | C+ (10.1min) | B- ($2.57) | — | — |
| bash | opus48-1m-high | C (10.7min) | C ($2.87) | — | — |
| typescript-bun | opus48-1m-medium | C- (11.7min) | C+ ($2.73) | — | — |
| powershell-tool | opus48-1m-high | D+ (12.0min) | C ($2.83) | — | — |
| typescript-bun | opus48-1m-high | D+ (12.2min) | D- ($3.75) | — | — |
| powershell | opus48-1m-high | D- (13.8min) | D+ ($3.24) | — | — |

</details>

<details>
<summary>Sorted by Cost tier (best-first), then avg of Duration/Tests/Workflow Craft tiers</summary>

| Language | Model | Duration | Cost | Tests Quality | Workflow Craft |
|----------|-------|----------|------|-----------|-------------|
| default | opus48-1m-medium | A+ (7.5min) | A+ ($1.89) | — | — |
| powershell | opus48-1m-medium | A+ (7.4min) | A+ ($1.81) | — | — |
| bash | opus48-1m-medium | B (9.2min) | B ($2.38) | — | — |
| powershell-tool | opus48-1m-medium | C+ (10.1min) | B- ($2.57) | — | — |
| default | opus48-1m-high | B (9.4min) | C+ ($2.74) | — | — |
| typescript-bun | opus48-1m-medium | C- (11.7min) | C+ ($2.73) | — | — |
| bash | opus48-1m-high | C (10.7min) | C ($2.87) | — | — |
| powershell-tool | opus48-1m-high | D+ (12.0min) | C ($2.83) | — | — |
| powershell | opus48-1m-high | D- (13.8min) | D+ ($3.24) | — | — |
| typescript-bun | opus48-1m-high | D+ (12.2min) | D- ($3.75) | — | — |

</details>

<details>
<summary>Sorted by Tests Quality tier (best-first; no-data last), then avg of other tiers</summary>

| Language | Model | Duration | Cost | Tests Quality | Workflow Craft |
|----------|-------|----------|------|-----------|-------------|
| default | opus48-1m-medium | A+ (7.5min) | A+ ($1.89) | — | — |
| powershell | opus48-1m-medium | A+ (7.4min) | A+ ($1.81) | — | — |
| bash | opus48-1m-medium | B (9.2min) | B ($2.38) | — | — |
| default | opus48-1m-high | B (9.4min) | C+ ($2.74) | — | — |
| powershell-tool | opus48-1m-medium | C+ (10.1min) | B- ($2.57) | — | — |
| bash | opus48-1m-high | C (10.7min) | C ($2.87) | — | — |
| typescript-bun | opus48-1m-medium | C- (11.7min) | C+ ($2.73) | — | — |
| powershell-tool | opus48-1m-high | D+ (12.0min) | C ($2.83) | — | — |
| powershell | opus48-1m-high | D- (13.8min) | D+ ($3.24) | — | — |
| typescript-bun | opus48-1m-high | D+ (12.2min) | D- ($3.75) | — | — |

</details>

<details>
<summary>Sorted by Workflow Craft tier (best-first; no-data last), then avg of other tiers</summary>

| Language | Model | Duration | Cost | Tests Quality | Workflow Craft |
|----------|-------|----------|------|-----------|-------------|
| default | opus48-1m-medium | A+ (7.5min) | A+ ($1.89) | — | — |
| powershell | opus48-1m-medium | A+ (7.4min) | A+ ($1.81) | — | — |
| bash | opus48-1m-medium | B (9.2min) | B ($2.38) | — | — |
| default | opus48-1m-high | B (9.4min) | C+ ($2.74) | — | — |
| powershell-tool | opus48-1m-medium | C+ (10.1min) | B- ($2.57) | — | — |
| bash | opus48-1m-high | C (10.7min) | C ($2.87) | — | — |
| typescript-bun | opus48-1m-medium | C- (11.7min) | C+ ($2.73) | — | — |
| powershell-tool | opus48-1m-high | D+ (12.0min) | C ($2.83) | — | — |
| powershell | opus48-1m-high | D- (13.8min) | D+ ($3.24) | — | — |
| typescript-bun | opus48-1m-high | D+ (12.2min) | D- ($3.75) | — | — |

</details>

- **Estimated time remaining:** 392.8min
- **Estimated total cost:** $186.10

## Comparison by Language/Model/Effort
*See [Notes](#notes) for scoring rubric and CLI version legend.*

| Language | Model | Runs | Avg Duration | Avg Duration Net of Traps | Avg Errors | Avg Turns | Avg Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| bash | opus48-1m-high | 6 | 10.7min | 7.7min | 0.8 | 40 | $2.87 | $17.21 | — | — |
| bash | opus48-1m-medium | 7 | 9.2min | 9.2min | 1.1 | 34 | $2.38 | $16.64 | — | — |
| default | opus48-1m-high | 7 | 9.4min | 7.9min | 0.3 | 42 | $2.74 | $19.15 | — | — |
| default | opus48-1m-medium | 7 | 7.5min | 7.5min | 0.1 | 32 | $1.89 | $13.21 | — | — |
| powershell | opus48-1m-high | 7 | 13.8min | 10.3min | 0.9 | 49 | $3.24 | $22.70 | — | — |
| powershell | opus48-1m-medium | 7 | 7.4min | 7.4min | 0.0 | 27 | $1.81 | $12.64 | — | — |
| powershell-tool | opus48-1m-high | 6 | 12.0min | 10.5min | 0.2 | 36 | $2.83 | $17.00 | — | — |
| powershell-tool | opus48-1m-medium | 7 | 10.1min | 10.1min | 0.9 | 40 | $2.57 | $18.00 | — | — |
| typescript-bun | opus48-1m-high | 6 | 12.2min | 7.9min | 0.3 | 58 | $3.75 | $22.48 | — | — |
| typescript-bun | opus48-1m-medium | 7 | 11.7min | 11.7min | 0.6 | 49 | $2.73 | $19.09 | — | — |


<details>
<summary>Sorted by avg cost (cheapest first)</summary>

| Language | Model | Runs | Avg Duration | Avg Duration Net of Traps | Avg Errors | Avg Turns | Avg Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| powershell | opus48-1m-medium | 7 | 7.4min | 7.4min | 0.0 | 27 | $1.81 | $12.64 | — | — |
| default | opus48-1m-medium | 7 | 7.5min | 7.5min | 0.1 | 32 | $1.89 | $13.21 | — | — |
| bash | opus48-1m-medium | 7 | 9.2min | 9.2min | 1.1 | 34 | $2.38 | $16.64 | — | — |
| powershell-tool | opus48-1m-medium | 7 | 10.1min | 10.1min | 0.9 | 40 | $2.57 | $18.00 | — | — |
| typescript-bun | opus48-1m-medium | 7 | 11.7min | 11.7min | 0.6 | 49 | $2.73 | $19.09 | — | — |
| default | opus48-1m-high | 7 | 9.4min | 7.9min | 0.3 | 42 | $2.74 | $19.15 | — | — |
| powershell-tool | opus48-1m-high | 6 | 12.0min | 10.5min | 0.2 | 36 | $2.83 | $17.00 | — | — |
| bash | opus48-1m-high | 6 | 10.7min | 7.7min | 0.8 | 40 | $2.87 | $17.21 | — | — |
| powershell | opus48-1m-high | 7 | 13.8min | 10.3min | 0.9 | 49 | $3.24 | $22.70 | — | — |
| typescript-bun | opus48-1m-high | 6 | 12.2min | 7.9min | 0.3 | 58 | $3.75 | $22.48 | — | — |

</details>

<details>
<summary>Sorted by avg duration (fastest first)</summary>

| Language | Model | Runs | Avg Duration | Avg Duration Net of Traps | Avg Errors | Avg Turns | Avg Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| powershell | opus48-1m-medium | 7 | 7.4min | 7.4min | 0.0 | 27 | $1.81 | $12.64 | — | — |
| default | opus48-1m-medium | 7 | 7.5min | 7.5min | 0.1 | 32 | $1.89 | $13.21 | — | — |
| bash | opus48-1m-medium | 7 | 9.2min | 9.2min | 1.1 | 34 | $2.38 | $16.64 | — | — |
| default | opus48-1m-high | 7 | 9.4min | 7.9min | 0.3 | 42 | $2.74 | $19.15 | — | — |
| powershell-tool | opus48-1m-medium | 7 | 10.1min | 10.1min | 0.9 | 40 | $2.57 | $18.00 | — | — |
| bash | opus48-1m-high | 6 | 10.7min | 7.7min | 0.8 | 40 | $2.87 | $17.21 | — | — |
| typescript-bun | opus48-1m-medium | 7 | 11.7min | 11.7min | 0.6 | 49 | $2.73 | $19.09 | — | — |
| powershell-tool | opus48-1m-high | 6 | 12.0min | 10.5min | 0.2 | 36 | $2.83 | $17.00 | — | — |
| typescript-bun | opus48-1m-high | 6 | 12.2min | 7.9min | 0.3 | 58 | $3.75 | $22.48 | — | — |
| powershell | opus48-1m-high | 7 | 13.8min | 10.3min | 0.9 | 49 | $3.24 | $22.70 | — | — |

</details>

<details>
<summary>Sorted by avg duration net of traps (fastest first)</summary>

| Language | Model | Runs | Avg Duration | Avg Duration Net of Traps | Avg Errors | Avg Turns | Avg Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| powershell | opus48-1m-medium | 7 | 7.4min | 7.4min | 0.0 | 27 | $1.81 | $12.64 | — | — |
| default | opus48-1m-medium | 7 | 7.5min | 7.5min | 0.1 | 32 | $1.89 | $13.21 | — | — |
| bash | opus48-1m-high | 6 | 10.7min | 7.7min | 0.8 | 40 | $2.87 | $17.21 | — | — |
| default | opus48-1m-high | 7 | 9.4min | 7.9min | 0.3 | 42 | $2.74 | $19.15 | — | — |
| typescript-bun | opus48-1m-high | 6 | 12.2min | 7.9min | 0.3 | 58 | $3.75 | $22.48 | — | — |
| bash | opus48-1m-medium | 7 | 9.2min | 9.2min | 1.1 | 34 | $2.38 | $16.64 | — | — |
| powershell-tool | opus48-1m-medium | 7 | 10.1min | 10.1min | 0.9 | 40 | $2.57 | $18.00 | — | — |
| powershell | opus48-1m-high | 7 | 13.8min | 10.3min | 0.9 | 49 | $3.24 | $22.70 | — | — |
| powershell-tool | opus48-1m-high | 6 | 12.0min | 10.5min | 0.2 | 36 | $2.83 | $17.00 | — | — |
| typescript-bun | opus48-1m-medium | 7 | 11.7min | 11.7min | 0.6 | 49 | $2.73 | $19.09 | — | — |

</details>

<details>
<summary>Sorted by avg errors (fewest first)</summary>

| Language | Model | Runs | Avg Duration | Avg Duration Net of Traps | Avg Errors | Avg Turns | Avg Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| powershell | opus48-1m-medium | 7 | 7.4min | 7.4min | 0.0 | 27 | $1.81 | $12.64 | — | — |
| default | opus48-1m-medium | 7 | 7.5min | 7.5min | 0.1 | 32 | $1.89 | $13.21 | — | — |
| powershell-tool | opus48-1m-high | 6 | 12.0min | 10.5min | 0.2 | 36 | $2.83 | $17.00 | — | — |
| default | opus48-1m-high | 7 | 9.4min | 7.9min | 0.3 | 42 | $2.74 | $19.15 | — | — |
| typescript-bun | opus48-1m-high | 6 | 12.2min | 7.9min | 0.3 | 58 | $3.75 | $22.48 | — | — |
| typescript-bun | opus48-1m-medium | 7 | 11.7min | 11.7min | 0.6 | 49 | $2.73 | $19.09 | — | — |
| bash | opus48-1m-high | 6 | 10.7min | 7.7min | 0.8 | 40 | $2.87 | $17.21 | — | — |
| powershell | opus48-1m-high | 7 | 13.8min | 10.3min | 0.9 | 49 | $3.24 | $22.70 | — | — |
| powershell-tool | opus48-1m-medium | 7 | 10.1min | 10.1min | 0.9 | 40 | $2.57 | $18.00 | — | — |
| bash | opus48-1m-medium | 7 | 9.2min | 9.2min | 1.1 | 34 | $2.38 | $16.64 | — | — |

</details>

<details>
<summary>Sorted by avg turns (fewest first)</summary>

| Language | Model | Runs | Avg Duration | Avg Duration Net of Traps | Avg Errors | Avg Turns | Avg Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| powershell | opus48-1m-medium | 7 | 7.4min | 7.4min | 0.0 | 27 | $1.81 | $12.64 | — | — |
| default | opus48-1m-medium | 7 | 7.5min | 7.5min | 0.1 | 32 | $1.89 | $13.21 | — | — |
| bash | opus48-1m-medium | 7 | 9.2min | 9.2min | 1.1 | 34 | $2.38 | $16.64 | — | — |
| powershell-tool | opus48-1m-high | 6 | 12.0min | 10.5min | 0.2 | 36 | $2.83 | $17.00 | — | — |
| bash | opus48-1m-high | 6 | 10.7min | 7.7min | 0.8 | 40 | $2.87 | $17.21 | — | — |
| powershell-tool | opus48-1m-medium | 7 | 10.1min | 10.1min | 0.9 | 40 | $2.57 | $18.00 | — | — |
| default | opus48-1m-high | 7 | 9.4min | 7.9min | 0.3 | 42 | $2.74 | $19.15 | — | — |
| powershell | opus48-1m-high | 7 | 13.8min | 10.3min | 0.9 | 49 | $3.24 | $22.70 | — | — |
| typescript-bun | opus48-1m-medium | 7 | 11.7min | 11.7min | 0.6 | 49 | $2.73 | $19.09 | — | — |
| typescript-bun | opus48-1m-high | 6 | 12.2min | 7.9min | 0.3 | 58 | $3.75 | $22.48 | — | — |

</details>

<details>
<summary>Sorted by LLM-as-judge score (best first)</summary>

| Language | Model | Runs | Avg Duration | Avg Duration Net of Traps | Avg Errors | Avg Turns | Avg Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| bash | opus48-1m-high | 6 | 10.7min | 7.7min | 0.8 | 40 | $2.87 | $17.21 | — | — |
| bash | opus48-1m-medium | 7 | 9.2min | 9.2min | 1.1 | 34 | $2.38 | $16.64 | — | — |
| default | opus48-1m-high | 7 | 9.4min | 7.9min | 0.3 | 42 | $2.74 | $19.15 | — | — |
| default | opus48-1m-medium | 7 | 7.5min | 7.5min | 0.1 | 32 | $1.89 | $13.21 | — | — |
| powershell | opus48-1m-high | 7 | 13.8min | 10.3min | 0.9 | 49 | $3.24 | $22.70 | — | — |
| powershell | opus48-1m-medium | 7 | 7.4min | 7.4min | 0.0 | 27 | $1.81 | $12.64 | — | — |
| powershell-tool | opus48-1m-high | 6 | 12.0min | 10.5min | 0.2 | 36 | $2.83 | $17.00 | — | — |
| powershell-tool | opus48-1m-medium | 7 | 10.1min | 10.1min | 0.9 | 40 | $2.57 | $18.00 | — | — |
| typescript-bun | opus48-1m-high | 6 | 12.2min | 7.9min | 0.3 | 58 | $3.75 | $22.48 | — | — |
| typescript-bun | opus48-1m-medium | 7 | 11.7min | 11.7min | 0.6 | 49 | $2.73 | $19.09 | — | — |

</details>

<details>
<summary>Sorted by deliverable-quality score (best first)</summary>

| Language | Model | Runs | Avg Duration | Avg Duration Net of Traps | Avg Errors | Avg Turns | Avg Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| bash | opus48-1m-high | 6 | 10.7min | 7.7min | 0.8 | 40 | $2.87 | $17.21 | — | — |
| bash | opus48-1m-medium | 7 | 9.2min | 9.2min | 1.1 | 34 | $2.38 | $16.64 | — | — |
| default | opus48-1m-high | 7 | 9.4min | 7.9min | 0.3 | 42 | $2.74 | $19.15 | — | — |
| default | opus48-1m-medium | 7 | 7.5min | 7.5min | 0.1 | 32 | $1.89 | $13.21 | — | — |
| powershell | opus48-1m-high | 7 | 13.8min | 10.3min | 0.9 | 49 | $3.24 | $22.70 | — | — |
| powershell | opus48-1m-medium | 7 | 7.4min | 7.4min | 0.0 | 27 | $1.81 | $12.64 | — | — |
| powershell-tool | opus48-1m-high | 6 | 12.0min | 10.5min | 0.2 | 36 | $2.83 | $17.00 | — | — |
| powershell-tool | opus48-1m-medium | 7 | 10.1min | 10.1min | 0.9 | 40 | $2.57 | $18.00 | — | — |
| typescript-bun | opus48-1m-high | 6 | 12.2min | 7.9min | 0.3 | 58 | $3.75 | $22.48 | — | — |
| typescript-bun | opus48-1m-medium | 7 | 11.7min | 11.7min | 0.6 | 49 | $2.73 | $19.09 | — | — |

</details>

## Savings Analysis

### Hook Savings by Language/Model/Effort

Each hook-caught error avoids one test run that would otherwise have been needed to discover it.
Every hook fire (hit or miss) costs execution time for the syntax/type checker.

*`% of Test Time Saved` = `net / (net + test_time) × 100` — the share of total (would-have-been + actually-spent) test time that hooks eliminated. Bounded in (-∞, 100%) without an artificial cap; near 100% means hooks substituted for almost all of the hypothetical test work.*

| Language | Model | Fires | Caught | Rate | Gross Saved | % of Time | Overhead | % of Time | Net Saved | % of Time | Test Run Time | % of Test Time Saved |
|------|-------|-------|--------|------|------------|-----------|----------|-----------|-----------|-----------|---------------|----------------------|
| bash | opus48-1m-high-cli2.1.195 | 89 | 6 | 6.7% | 1.2min | 0.2% | 0.1min | 0.0% | 1.1min | 0.2% | 2.7min | 29.6% |
| bash | opus48-1m-medium-cli2.1.193 | 51 | 1 | 2.0% | 0.2min | 0.0% | 0.0min | 0.0% | 0.2min | 0.0% | 0.7min | 20.5% |
| bash | opus48-1m-medium-cli2.1.195 | 32 | 1 | 3.1% | 0.2min | 0.0% | 0.0min | 0.0% | 0.2min | 0.0% | 4.4min | 3.5% |
| default | opus48-1m-high-cli2.1.195 | 147 | 1 | 0.7% | 0.1min | 0.0% | 0.1min | 0.0% | -0.0min | -0.0% | 4.8min | -0.0% |
| default | opus48-1m-medium-cli2.1.193 | 68 | 0 | 0.0% | 0.0min | 0.0% | 0.2min | 0.0% | -0.2min | -0.0% | 4.0min | -3.9% |
| default | opus48-1m-medium-cli2.1.195 | 34 | 0 | 0.0% | 0.0min | 0.0% | 0.1min | 0.0% | -0.1min | -0.0% | 2.9min | -5.0% |
| powershell | opus48-1m-high-cli2.1.195 | 157 | 0 | 0.0% | 0.0min | 0.0% | 2.0min | 0.3% | -2.0min | -0.3% | 17.3min | -13.0% |
| powershell | opus48-1m-medium-cli2.1.193 | 70 | 0 | 0.0% | 0.0min | 0.0% | 0.7min | 0.1% | -0.7min | -0.1% | 4.3min | -19.8% |
| powershell | opus48-1m-medium-cli2.1.195 | 18 | 0 | 0.0% | 0.0min | 0.0% | 0.1min | 0.0% | -0.1min | -0.0% | 1.5min | -10.4% |
| powershell-tool | opus48-1m-high-cli2.1.195 | 101 | 0 | 0.0% | 0.0min | 0.0% | 1.2min | 0.2% | -1.2min | -0.2% | 10.8min | -12.1% |
| powershell-tool | opus48-1m-medium-cli2.1.193 | 62 | 0 | 0.0% | 0.0min | 0.0% | 0.3min | 0.0% | -0.3min | -0.0% | 3.6min | -8.2% |
| powershell-tool | opus48-1m-medium-cli2.1.195 | 55 | 0 | 0.0% | 0.0min | 0.0% | 0.5min | 0.1% | -0.5min | -0.1% | 4.0min | -14.3% |
| typescript-bun | opus48-1m-high-cli2.1.195 | 167 | 72 | 43.1% | 9.6min | 1.4% | 3.1min | 0.4% | 6.5min | 0.9% | 3.0min | 68.4% |
| typescript-bun | opus48-1m-medium-cli2.1.193 | 95 | 40 | 42.1% | 5.3min | 0.8% | 1.4min | 0.2% | 3.9min | 0.6% | 4.0min | 49.5% |
| typescript-bun | opus48-1m-medium-cli2.1.195 | 79 | 39 | 49.4% | 5.2min | 0.8% | 1.4min | 0.2% | 3.8min | 0.6% | 2.1min | 64.3% |


<details>
<summary>Sorted by net saved (most first)</summary>

| Language | Model | Fires | Caught | Rate | Gross Saved | % of Time | Overhead | % of Time | Net Saved | % of Time | Test Run Time | % of Test Time Saved |
|------|-------|-------|--------|------|------------|-----------|----------|-----------|-----------|-----------|---------------|----------------------|
| typescript-bun | opus48-1m-high-cli2.1.195 | 167 | 72 | 43.1% | 9.6min | 1.4% | 3.1min | 0.4% | 6.5min | 0.9% | 3.0min | 68.4% |
| typescript-bun | opus48-1m-medium-cli2.1.193 | 95 | 40 | 42.1% | 5.3min | 0.8% | 1.4min | 0.2% | 3.9min | 0.6% | 4.0min | 49.5% |
| typescript-bun | opus48-1m-medium-cli2.1.195 | 79 | 39 | 49.4% | 5.2min | 0.8% | 1.4min | 0.2% | 3.8min | 0.6% | 2.1min | 64.3% |
| bash | opus48-1m-high-cli2.1.195 | 89 | 6 | 6.7% | 1.2min | 0.2% | 0.1min | 0.0% | 1.1min | 0.2% | 2.7min | 29.6% |
| bash | opus48-1m-medium-cli2.1.193 | 51 | 1 | 2.0% | 0.2min | 0.0% | 0.0min | 0.0% | 0.2min | 0.0% | 0.7min | 20.5% |
| bash | opus48-1m-medium-cli2.1.195 | 32 | 1 | 3.1% | 0.2min | 0.0% | 0.0min | 0.0% | 0.2min | 0.0% | 4.4min | 3.5% |
| default | opus48-1m-high-cli2.1.195 | 147 | 1 | 0.7% | 0.1min | 0.0% | 0.1min | 0.0% | -0.0min | -0.0% | 4.8min | -0.0% |
| default | opus48-1m-medium-cli2.1.195 | 34 | 0 | 0.0% | 0.0min | 0.0% | 0.1min | 0.0% | -0.1min | -0.0% | 2.9min | -5.0% |
| powershell | opus48-1m-medium-cli2.1.195 | 18 | 0 | 0.0% | 0.0min | 0.0% | 0.1min | 0.0% | -0.1min | -0.0% | 1.5min | -10.4% |
| default | opus48-1m-medium-cli2.1.193 | 68 | 0 | 0.0% | 0.0min | 0.0% | 0.2min | 0.0% | -0.2min | -0.0% | 4.0min | -3.9% |
| powershell-tool | opus48-1m-medium-cli2.1.193 | 62 | 0 | 0.0% | 0.0min | 0.0% | 0.3min | 0.0% | -0.3min | -0.0% | 3.6min | -8.2% |
| powershell-tool | opus48-1m-medium-cli2.1.195 | 55 | 0 | 0.0% | 0.0min | 0.0% | 0.5min | 0.1% | -0.5min | -0.1% | 4.0min | -14.3% |
| powershell | opus48-1m-medium-cli2.1.193 | 70 | 0 | 0.0% | 0.0min | 0.0% | 0.7min | 0.1% | -0.7min | -0.1% | 4.3min | -19.8% |
| powershell-tool | opus48-1m-high-cli2.1.195 | 101 | 0 | 0.0% | 0.0min | 0.0% | 1.2min | 0.2% | -1.2min | -0.2% | 10.8min | -12.1% |
| powershell | opus48-1m-high-cli2.1.195 | 157 | 0 | 0.0% | 0.0min | 0.0% | 2.0min | 0.3% | -2.0min | -0.3% | 17.3min | -13.0% |

</details>

<details>
<summary>Sorted by net % of test time saved (most first)</summary>

| Language | Model | Fires | Caught | Rate | Gross Saved | % of Time | Overhead | % of Time | Net Saved | % of Time | Test Run Time | % of Test Time Saved |
|------|-------|-------|--------|------|------------|-----------|----------|-----------|-----------|-----------|---------------|----------------------|
| typescript-bun | opus48-1m-high-cli2.1.195 | 167 | 72 | 43.1% | 9.6min | 1.4% | 3.1min | 0.4% | 6.5min | 0.9% | 3.0min | 68.4% |
| typescript-bun | opus48-1m-medium-cli2.1.195 | 79 | 39 | 49.4% | 5.2min | 0.8% | 1.4min | 0.2% | 3.8min | 0.6% | 2.1min | 64.3% |
| typescript-bun | opus48-1m-medium-cli2.1.193 | 95 | 40 | 42.1% | 5.3min | 0.8% | 1.4min | 0.2% | 3.9min | 0.6% | 4.0min | 49.5% |
| bash | opus48-1m-high-cli2.1.195 | 89 | 6 | 6.7% | 1.2min | 0.2% | 0.1min | 0.0% | 1.1min | 0.2% | 2.7min | 29.6% |
| bash | opus48-1m-medium-cli2.1.193 | 51 | 1 | 2.0% | 0.2min | 0.0% | 0.0min | 0.0% | 0.2min | 0.0% | 0.7min | 20.5% |
| bash | opus48-1m-medium-cli2.1.195 | 32 | 1 | 3.1% | 0.2min | 0.0% | 0.0min | 0.0% | 0.2min | 0.0% | 4.4min | 3.5% |
| default | opus48-1m-high-cli2.1.195 | 147 | 1 | 0.7% | 0.1min | 0.0% | 0.1min | 0.0% | -0.0min | -0.0% | 4.8min | -0.0% |
| default | opus48-1m-medium-cli2.1.193 | 68 | 0 | 0.0% | 0.0min | 0.0% | 0.2min | 0.0% | -0.2min | -0.0% | 4.0min | -3.9% |
| default | opus48-1m-medium-cli2.1.195 | 34 | 0 | 0.0% | 0.0min | 0.0% | 0.1min | 0.0% | -0.1min | -0.0% | 2.9min | -5.0% |
| powershell-tool | opus48-1m-medium-cli2.1.193 | 62 | 0 | 0.0% | 0.0min | 0.0% | 0.3min | 0.0% | -0.3min | -0.0% | 3.6min | -8.2% |
| powershell | opus48-1m-medium-cli2.1.195 | 18 | 0 | 0.0% | 0.0min | 0.0% | 0.1min | 0.0% | -0.1min | -0.0% | 1.5min | -10.4% |
| powershell-tool | opus48-1m-high-cli2.1.195 | 101 | 0 | 0.0% | 0.0min | 0.0% | 1.2min | 0.2% | -1.2min | -0.2% | 10.8min | -12.1% |
| powershell | opus48-1m-high-cli2.1.195 | 157 | 0 | 0.0% | 0.0min | 0.0% | 2.0min | 0.3% | -2.0min | -0.3% | 17.3min | -13.0% |
| powershell-tool | opus48-1m-medium-cli2.1.195 | 55 | 0 | 0.0% | 0.0min | 0.0% | 0.5min | 0.1% | -0.5min | -0.1% | 4.0min | -14.3% |
| powershell | opus48-1m-medium-cli2.1.193 | 70 | 0 | 0.0% | 0.0min | 0.0% | 0.7min | 0.1% | -0.7min | -0.1% | 4.3min | -19.8% |

</details>

<details>
<summary>Sorted by catch rate (highest first)</summary>

| Language | Model | Fires | Caught | Rate | Gross Saved | % of Time | Overhead | % of Time | Net Saved | % of Time | Test Run Time | % of Test Time Saved |
|------|-------|-------|--------|------|------------|-----------|----------|-----------|-----------|-----------|---------------|----------------------|
| typescript-bun | opus48-1m-medium-cli2.1.195 | 79 | 39 | 49.4% | 5.2min | 0.8% | 1.4min | 0.2% | 3.8min | 0.6% | 2.1min | 64.3% |
| typescript-bun | opus48-1m-high-cli2.1.195 | 167 | 72 | 43.1% | 9.6min | 1.4% | 3.1min | 0.4% | 6.5min | 0.9% | 3.0min | 68.4% |
| typescript-bun | opus48-1m-medium-cli2.1.193 | 95 | 40 | 42.1% | 5.3min | 0.8% | 1.4min | 0.2% | 3.9min | 0.6% | 4.0min | 49.5% |
| bash | opus48-1m-high-cli2.1.195 | 89 | 6 | 6.7% | 1.2min | 0.2% | 0.1min | 0.0% | 1.1min | 0.2% | 2.7min | 29.6% |
| bash | opus48-1m-medium-cli2.1.195 | 32 | 1 | 3.1% | 0.2min | 0.0% | 0.0min | 0.0% | 0.2min | 0.0% | 4.4min | 3.5% |
| bash | opus48-1m-medium-cli2.1.193 | 51 | 1 | 2.0% | 0.2min | 0.0% | 0.0min | 0.0% | 0.2min | 0.0% | 0.7min | 20.5% |
| default | opus48-1m-high-cli2.1.195 | 147 | 1 | 0.7% | 0.1min | 0.0% | 0.1min | 0.0% | -0.0min | -0.0% | 4.8min | -0.0% |
| default | opus48-1m-medium-cli2.1.193 | 68 | 0 | 0.0% | 0.0min | 0.0% | 0.2min | 0.0% | -0.2min | -0.0% | 4.0min | -3.9% |
| default | opus48-1m-medium-cli2.1.195 | 34 | 0 | 0.0% | 0.0min | 0.0% | 0.1min | 0.0% | -0.1min | -0.0% | 2.9min | -5.0% |
| powershell | opus48-1m-high-cli2.1.195 | 157 | 0 | 0.0% | 0.0min | 0.0% | 2.0min | 0.3% | -2.0min | -0.3% | 17.3min | -13.0% |
| powershell | opus48-1m-medium-cli2.1.193 | 70 | 0 | 0.0% | 0.0min | 0.0% | 0.7min | 0.1% | -0.7min | -0.1% | 4.3min | -19.8% |
| powershell | opus48-1m-medium-cli2.1.195 | 18 | 0 | 0.0% | 0.0min | 0.0% | 0.1min | 0.0% | -0.1min | -0.0% | 1.5min | -10.4% |
| powershell-tool | opus48-1m-high-cli2.1.195 | 101 | 0 | 0.0% | 0.0min | 0.0% | 1.2min | 0.2% | -1.2min | -0.2% | 10.8min | -12.1% |
| powershell-tool | opus48-1m-medium-cli2.1.193 | 62 | 0 | 0.0% | 0.0min | 0.0% | 0.3min | 0.0% | -0.3min | -0.0% | 3.6min | -8.2% |
| powershell-tool | opus48-1m-medium-cli2.1.195 | 55 | 0 | 0.0% | 0.0min | 0.0% | 0.5min | 0.1% | -0.5min | -0.1% | 4.0min | -14.3% |

</details>

### Trap Analysis by Language/Model/Effort/Category

| Trap | Language | Model | Fell In | Time Lost | % of Time | $ Lost | % of $ |
|------|------|-------|---------|-----------|-----------|--------|--------|
| repeated-test-reruns | bash | opus48-1m-high-cli2.1.195 | 5 | 11.7min | 1.7% | $3.16 | 1.77% |
| repeated-test-reruns | bash | opus48-1m-medium-cli2.1.193 | 3 | 4.0min | 0.6% | $1.08 | 0.60% |
| repeated-test-reruns | bash | opus48-1m-medium-cli2.1.195 | 2 | 4.7min | 0.7% | $1.21 | 0.68% |
| repeated-test-reruns | default | opus48-1m-high-cli2.1.195 | 5 | 10.0min | 1.4% | $2.94 | 1.65% |
| repeated-test-reruns | default | opus48-1m-medium-cli2.1.193 | 4 | 5.7min | 0.8% | $1.34 | 0.75% |
| repeated-test-reruns | default | opus48-1m-medium-cli2.1.195 | 2 | 3.3min | 0.5% | $0.82 | 0.46% |
| repeated-test-reruns | powershell | opus48-1m-high-cli2.1.195 | 8 | 22.3min | 3.2% | $5.14 | 2.88% |
| repeated-test-reruns | powershell | opus48-1m-medium-cli2.1.193 | 2 | 2.7min | 0.4% | $0.66 | 0.37% |
| repeated-test-reruns | powershell-tool | opus48-1m-high-cli2.1.195 | 5 | 8.3min | 1.2% | $1.98 | 1.11% |
| repeated-test-reruns | powershell-tool | opus48-1m-medium-cli2.1.193 | 2 | 3.3min | 0.5% | $0.78 | 0.44% |
| repeated-test-reruns | powershell-tool | opus48-1m-medium-cli2.1.195 | 3 | 3.3min | 0.5% | $0.85 | 0.48% |
| repeated-test-reruns | typescript-bun | opus48-1m-high-cli2.1.195 | 4 | 10.0min | 1.4% | $3.35 | 1.88% |
| repeated-test-reruns | typescript-bun | opus48-1m-medium-cli2.1.193 | 4 | 8.7min | 1.3% | $2.26 | 1.27% |
| repeated-test-reruns | typescript-bun | opus48-1m-medium-cli2.1.195 | 4 | 7.3min | 1.1% | $1.71 | 0.96% |
| ts-type-error-fix-cycles | typescript-bun | opus48-1m-high-cli2.1.195 | 5 | 14.4min | 2.1% | $4.55 | 2.56% |
| ts-type-error-fix-cycles | typescript-bun | opus48-1m-medium-cli2.1.193 | 3 | 8.0min | 1.2% | $2.17 | 1.22% |
| ts-type-error-fix-cycles | typescript-bun | opus48-1m-medium-cli2.1.195 | 2 | 7.8min | 1.1% | $1.74 | 0.98% |
| fixture-rework | bash | opus48-1m-high-cli2.1.195 | 6 | 5.0min | 0.7% | $1.35 | 0.76% |
| fixture-rework | bash | opus48-1m-medium-cli2.1.193 | 2 | 1.5min | 0.2% | $0.41 | 0.23% |
| fixture-rework | bash | opus48-1m-medium-cli2.1.195 | 1 | 3.0min | 0.4% | $0.72 | 0.40% |
| fixture-rework | default | opus48-1m-medium-cli2.1.193 | 1 | 0.8min | 0.1% | $0.22 | 0.13% |
| fixture-rework | powershell | opus48-1m-high-cli2.1.195 | 4 | 2.5min | 0.4% | $0.62 | 0.35% |
| fixture-rework | powershell | opus48-1m-medium-cli2.1.193 | 1 | 0.5min | 0.1% | $0.12 | 0.07% |
| fixture-rework | powershell-tool | opus48-1m-high-cli2.1.195 | 1 | 0.5min | 0.1% | $0.12 | 0.07% |
| fixture-rework | powershell-tool | opus48-1m-medium-cli2.1.193 | 1 | 1.0min | 0.1% | $0.27 | 0.15% |
| fixture-rework | typescript-bun | opus48-1m-high-cli2.1.195 | 1 | 1.2min | 0.2% | $0.37 | 0.21% |
| fixture-rework | typescript-bun | opus48-1m-medium-cli2.1.195 | 1 | 0.5min | 0.1% | $0.10 | 0.05% |
| actionlint-fix-cycles | powershell-tool | opus48-1m-medium-cli2.1.193 | 1 | 1.0min | 0.1% | $0.27 | 0.15% |
| actionlint-fix-cycles | typescript-bun | opus48-1m-medium-cli2.1.195 | 1 | 0.7min | 0.1% | $0.13 | 0.07% |
| bats-setup-issues | bash | opus48-1m-high-cli2.1.195 | 1 | 1.2min | 0.2% | $0.33 | 0.19% |


<details>
<summary>Sorted by time lost (least first)</summary>

| Trap | Language | Model | Fell In | Time Lost | % of Time | $ Lost | % of $ |
|------|------|-------|---------|-----------|-----------|--------|--------|
| fixture-rework | powershell | opus48-1m-medium-cli2.1.193 | 1 | 0.5min | 0.1% | $0.12 | 0.07% |
| fixture-rework | powershell-tool | opus48-1m-high-cli2.1.195 | 1 | 0.5min | 0.1% | $0.12 | 0.07% |
| fixture-rework | typescript-bun | opus48-1m-medium-cli2.1.195 | 1 | 0.5min | 0.1% | $0.10 | 0.05% |
| actionlint-fix-cycles | typescript-bun | opus48-1m-medium-cli2.1.195 | 1 | 0.7min | 0.1% | $0.13 | 0.07% |
| fixture-rework | default | opus48-1m-medium-cli2.1.193 | 1 | 0.8min | 0.1% | $0.22 | 0.13% |
| fixture-rework | powershell-tool | opus48-1m-medium-cli2.1.193 | 1 | 1.0min | 0.1% | $0.27 | 0.15% |
| actionlint-fix-cycles | powershell-tool | opus48-1m-medium-cli2.1.193 | 1 | 1.0min | 0.1% | $0.27 | 0.15% |
| fixture-rework | typescript-bun | opus48-1m-high-cli2.1.195 | 1 | 1.2min | 0.2% | $0.37 | 0.21% |
| bats-setup-issues | bash | opus48-1m-high-cli2.1.195 | 1 | 1.2min | 0.2% | $0.33 | 0.19% |
| fixture-rework | bash | opus48-1m-medium-cli2.1.193 | 2 | 1.5min | 0.2% | $0.41 | 0.23% |
| fixture-rework | powershell | opus48-1m-high-cli2.1.195 | 4 | 2.5min | 0.4% | $0.62 | 0.35% |
| repeated-test-reruns | powershell | opus48-1m-medium-cli2.1.193 | 2 | 2.7min | 0.4% | $0.66 | 0.37% |
| fixture-rework | bash | opus48-1m-medium-cli2.1.195 | 1 | 3.0min | 0.4% | $0.72 | 0.40% |
| repeated-test-reruns | default | opus48-1m-medium-cli2.1.195 | 2 | 3.3min | 0.5% | $0.82 | 0.46% |
| repeated-test-reruns | powershell-tool | opus48-1m-medium-cli2.1.193 | 2 | 3.3min | 0.5% | $0.78 | 0.44% |
| repeated-test-reruns | powershell-tool | opus48-1m-medium-cli2.1.195 | 3 | 3.3min | 0.5% | $0.85 | 0.48% |
| repeated-test-reruns | bash | opus48-1m-medium-cli2.1.193 | 3 | 4.0min | 0.6% | $1.08 | 0.60% |
| repeated-test-reruns | bash | opus48-1m-medium-cli2.1.195 | 2 | 4.7min | 0.7% | $1.21 | 0.68% |
| fixture-rework | bash | opus48-1m-high-cli2.1.195 | 6 | 5.0min | 0.7% | $1.35 | 0.76% |
| repeated-test-reruns | default | opus48-1m-medium-cli2.1.193 | 4 | 5.7min | 0.8% | $1.34 | 0.75% |
| repeated-test-reruns | typescript-bun | opus48-1m-medium-cli2.1.195 | 4 | 7.3min | 1.1% | $1.71 | 0.96% |
| ts-type-error-fix-cycles | typescript-bun | opus48-1m-medium-cli2.1.195 | 2 | 7.8min | 1.1% | $1.74 | 0.98% |
| ts-type-error-fix-cycles | typescript-bun | opus48-1m-medium-cli2.1.193 | 3 | 8.0min | 1.2% | $2.17 | 1.22% |
| repeated-test-reruns | powershell-tool | opus48-1m-high-cli2.1.195 | 5 | 8.3min | 1.2% | $1.98 | 1.11% |
| repeated-test-reruns | typescript-bun | opus48-1m-medium-cli2.1.193 | 4 | 8.7min | 1.3% | $2.26 | 1.27% |
| repeated-test-reruns | default | opus48-1m-high-cli2.1.195 | 5 | 10.0min | 1.4% | $2.94 | 1.65% |
| repeated-test-reruns | typescript-bun | opus48-1m-high-cli2.1.195 | 4 | 10.0min | 1.4% | $3.35 | 1.88% |
| repeated-test-reruns | bash | opus48-1m-high-cli2.1.195 | 5 | 11.7min | 1.7% | $3.16 | 1.77% |
| ts-type-error-fix-cycles | typescript-bun | opus48-1m-high-cli2.1.195 | 5 | 14.4min | 2.1% | $4.55 | 2.56% |
| repeated-test-reruns | powershell | opus48-1m-high-cli2.1.195 | 8 | 22.3min | 3.2% | $5.14 | 2.88% |

</details>

<details>
<summary>Sorted by $ lost (least first)</summary>

| Trap | Language | Model | Fell In | Time Lost | % of Time | $ Lost | % of $ |
|------|------|-------|---------|-----------|-----------|--------|--------|
| fixture-rework | typescript-bun | opus48-1m-medium-cli2.1.195 | 1 | 0.5min | 0.1% | $0.10 | 0.05% |
| fixture-rework | powershell | opus48-1m-medium-cli2.1.193 | 1 | 0.5min | 0.1% | $0.12 | 0.07% |
| fixture-rework | powershell-tool | opus48-1m-high-cli2.1.195 | 1 | 0.5min | 0.1% | $0.12 | 0.07% |
| actionlint-fix-cycles | typescript-bun | opus48-1m-medium-cli2.1.195 | 1 | 0.7min | 0.1% | $0.13 | 0.07% |
| fixture-rework | default | opus48-1m-medium-cli2.1.193 | 1 | 0.8min | 0.1% | $0.22 | 0.13% |
| fixture-rework | powershell-tool | opus48-1m-medium-cli2.1.193 | 1 | 1.0min | 0.1% | $0.27 | 0.15% |
| actionlint-fix-cycles | powershell-tool | opus48-1m-medium-cli2.1.193 | 1 | 1.0min | 0.1% | $0.27 | 0.15% |
| bats-setup-issues | bash | opus48-1m-high-cli2.1.195 | 1 | 1.2min | 0.2% | $0.33 | 0.19% |
| fixture-rework | typescript-bun | opus48-1m-high-cli2.1.195 | 1 | 1.2min | 0.2% | $0.37 | 0.21% |
| fixture-rework | bash | opus48-1m-medium-cli2.1.193 | 2 | 1.5min | 0.2% | $0.41 | 0.23% |
| fixture-rework | powershell | opus48-1m-high-cli2.1.195 | 4 | 2.5min | 0.4% | $0.62 | 0.35% |
| repeated-test-reruns | powershell | opus48-1m-medium-cli2.1.193 | 2 | 2.7min | 0.4% | $0.66 | 0.37% |
| fixture-rework | bash | opus48-1m-medium-cli2.1.195 | 1 | 3.0min | 0.4% | $0.72 | 0.40% |
| repeated-test-reruns | powershell-tool | opus48-1m-medium-cli2.1.193 | 2 | 3.3min | 0.5% | $0.78 | 0.44% |
| repeated-test-reruns | default | opus48-1m-medium-cli2.1.195 | 2 | 3.3min | 0.5% | $0.82 | 0.46% |
| repeated-test-reruns | powershell-tool | opus48-1m-medium-cli2.1.195 | 3 | 3.3min | 0.5% | $0.85 | 0.48% |
| repeated-test-reruns | bash | opus48-1m-medium-cli2.1.193 | 3 | 4.0min | 0.6% | $1.08 | 0.60% |
| repeated-test-reruns | bash | opus48-1m-medium-cli2.1.195 | 2 | 4.7min | 0.7% | $1.21 | 0.68% |
| repeated-test-reruns | default | opus48-1m-medium-cli2.1.193 | 4 | 5.7min | 0.8% | $1.34 | 0.75% |
| fixture-rework | bash | opus48-1m-high-cli2.1.195 | 6 | 5.0min | 0.7% | $1.35 | 0.76% |
| repeated-test-reruns | typescript-bun | opus48-1m-medium-cli2.1.195 | 4 | 7.3min | 1.1% | $1.71 | 0.96% |
| ts-type-error-fix-cycles | typescript-bun | opus48-1m-medium-cli2.1.195 | 2 | 7.8min | 1.1% | $1.74 | 0.98% |
| repeated-test-reruns | powershell-tool | opus48-1m-high-cli2.1.195 | 5 | 8.3min | 1.2% | $1.98 | 1.11% |
| ts-type-error-fix-cycles | typescript-bun | opus48-1m-medium-cli2.1.193 | 3 | 8.0min | 1.2% | $2.17 | 1.22% |
| repeated-test-reruns | typescript-bun | opus48-1m-medium-cli2.1.193 | 4 | 8.7min | 1.3% | $2.26 | 1.27% |
| repeated-test-reruns | default | opus48-1m-high-cli2.1.195 | 5 | 10.0min | 1.4% | $2.94 | 1.65% |
| repeated-test-reruns | bash | opus48-1m-high-cli2.1.195 | 5 | 11.7min | 1.7% | $3.16 | 1.77% |
| repeated-test-reruns | typescript-bun | opus48-1m-high-cli2.1.195 | 4 | 10.0min | 1.4% | $3.35 | 1.88% |
| ts-type-error-fix-cycles | typescript-bun | opus48-1m-high-cli2.1.195 | 5 | 14.4min | 2.1% | $4.55 | 2.56% |
| repeated-test-reruns | powershell | opus48-1m-high-cli2.1.195 | 8 | 22.3min | 3.2% | $5.14 | 2.88% |

</details>

<details>
<summary>Sorted by fell-in count (fewest first)</summary>

| Trap | Language | Model | Fell In | Time Lost | % of Time | $ Lost | % of $ |
|------|------|-------|---------|-----------|-----------|--------|--------|
| fixture-rework | bash | opus48-1m-medium-cli2.1.195 | 1 | 3.0min | 0.4% | $0.72 | 0.40% |
| fixture-rework | default | opus48-1m-medium-cli2.1.193 | 1 | 0.8min | 0.1% | $0.22 | 0.13% |
| fixture-rework | powershell | opus48-1m-medium-cli2.1.193 | 1 | 0.5min | 0.1% | $0.12 | 0.07% |
| fixture-rework | powershell-tool | opus48-1m-high-cli2.1.195 | 1 | 0.5min | 0.1% | $0.12 | 0.07% |
| fixture-rework | powershell-tool | opus48-1m-medium-cli2.1.193 | 1 | 1.0min | 0.1% | $0.27 | 0.15% |
| fixture-rework | typescript-bun | opus48-1m-high-cli2.1.195 | 1 | 1.2min | 0.2% | $0.37 | 0.21% |
| fixture-rework | typescript-bun | opus48-1m-medium-cli2.1.195 | 1 | 0.5min | 0.1% | $0.10 | 0.05% |
| actionlint-fix-cycles | powershell-tool | opus48-1m-medium-cli2.1.193 | 1 | 1.0min | 0.1% | $0.27 | 0.15% |
| actionlint-fix-cycles | typescript-bun | opus48-1m-medium-cli2.1.195 | 1 | 0.7min | 0.1% | $0.13 | 0.07% |
| bats-setup-issues | bash | opus48-1m-high-cli2.1.195 | 1 | 1.2min | 0.2% | $0.33 | 0.19% |
| repeated-test-reruns | bash | opus48-1m-medium-cli2.1.195 | 2 | 4.7min | 0.7% | $1.21 | 0.68% |
| repeated-test-reruns | default | opus48-1m-medium-cli2.1.195 | 2 | 3.3min | 0.5% | $0.82 | 0.46% |
| repeated-test-reruns | powershell | opus48-1m-medium-cli2.1.193 | 2 | 2.7min | 0.4% | $0.66 | 0.37% |
| repeated-test-reruns | powershell-tool | opus48-1m-medium-cli2.1.193 | 2 | 3.3min | 0.5% | $0.78 | 0.44% |
| ts-type-error-fix-cycles | typescript-bun | opus48-1m-medium-cli2.1.195 | 2 | 7.8min | 1.1% | $1.74 | 0.98% |
| fixture-rework | bash | opus48-1m-medium-cli2.1.193 | 2 | 1.5min | 0.2% | $0.41 | 0.23% |
| repeated-test-reruns | bash | opus48-1m-medium-cli2.1.193 | 3 | 4.0min | 0.6% | $1.08 | 0.60% |
| repeated-test-reruns | powershell-tool | opus48-1m-medium-cli2.1.195 | 3 | 3.3min | 0.5% | $0.85 | 0.48% |
| ts-type-error-fix-cycles | typescript-bun | opus48-1m-medium-cli2.1.193 | 3 | 8.0min | 1.2% | $2.17 | 1.22% |
| repeated-test-reruns | default | opus48-1m-medium-cli2.1.193 | 4 | 5.7min | 0.8% | $1.34 | 0.75% |
| repeated-test-reruns | typescript-bun | opus48-1m-high-cli2.1.195 | 4 | 10.0min | 1.4% | $3.35 | 1.88% |
| repeated-test-reruns | typescript-bun | opus48-1m-medium-cli2.1.193 | 4 | 8.7min | 1.3% | $2.26 | 1.27% |
| repeated-test-reruns | typescript-bun | opus48-1m-medium-cli2.1.195 | 4 | 7.3min | 1.1% | $1.71 | 0.96% |
| fixture-rework | powershell | opus48-1m-high-cli2.1.195 | 4 | 2.5min | 0.4% | $0.62 | 0.35% |
| repeated-test-reruns | bash | opus48-1m-high-cli2.1.195 | 5 | 11.7min | 1.7% | $3.16 | 1.77% |
| repeated-test-reruns | default | opus48-1m-high-cli2.1.195 | 5 | 10.0min | 1.4% | $2.94 | 1.65% |
| repeated-test-reruns | powershell-tool | opus48-1m-high-cli2.1.195 | 5 | 8.3min | 1.2% | $1.98 | 1.11% |
| ts-type-error-fix-cycles | typescript-bun | opus48-1m-high-cli2.1.195 | 5 | 14.4min | 2.1% | $4.55 | 2.56% |
| fixture-rework | bash | opus48-1m-high-cli2.1.195 | 6 | 5.0min | 0.7% | $1.35 | 0.76% |
| repeated-test-reruns | powershell | opus48-1m-high-cli2.1.195 | 8 | 22.3min | 3.2% | $5.14 | 2.88% |

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
| bash | opus48-1m-high-cli2.1.195 | 6 | 12 | 17.9min | 2.6% | $4.84 | 2.72% |
| bash | opus48-1m-medium-cli2.1.193 | 5 | 5 | 5.5min | 0.8% | $1.49 | 0.83% |
| bash | opus48-1m-medium-cli2.1.195 | 2 | 3 | 7.7min | 1.1% | $1.92 | 1.08% |
| default | opus48-1m-high-cli2.1.195 | 7 | 5 | 10.0min | 1.4% | $2.94 | 1.65% |
| default | opus48-1m-medium-cli2.1.193 | 5 | 5 | 6.4min | 0.9% | $1.57 | 0.88% |
| default | opus48-1m-medium-cli2.1.195 | 2 | 2 | 3.3min | 0.5% | $0.82 | 0.46% |
| powershell | opus48-1m-high-cli2.1.195 | 7 | 12 | 24.8min | 3.6% | $5.75 | 3.23% |
| powershell | opus48-1m-medium-cli2.1.193 | 5 | 3 | 3.2min | 0.5% | $0.78 | 0.44% |
| powershell | opus48-1m-medium-cli2.1.195 | 2 | 0 | 0.0min | 0.0% | $0.00 | 0.00% |
| powershell-tool | opus48-1m-high-cli2.1.195 | 6 | 6 | 8.8min | 1.3% | $2.10 | 1.18% |
| powershell-tool | opus48-1m-medium-cli2.1.193 | 4 | 4 | 5.3min | 0.8% | $1.31 | 0.73% |
| powershell-tool | opus48-1m-medium-cli2.1.195 | 3 | 3 | 3.3min | 0.5% | $0.85 | 0.48% |
| typescript-bun | opus48-1m-high-cli2.1.195 | 6 | 10 | 25.6min | 3.7% | $8.27 | 4.64% |
| typescript-bun | opus48-1m-medium-cli2.1.193 | 4 | 7 | 16.7min | 2.4% | $4.43 | 2.49% |
| typescript-bun | opus48-1m-medium-cli2.1.195 | 3 | 8 | 16.3min | 2.4% | $3.68 | 2.06% |


<details>
<summary>Sorted by time lost (least first)</summary>

| Language | Model | Runs | Traps | Time Lost | % of Time | $ Lost | % of $ |
|------|-------|------|-------|-----------|-----------|--------|--------|
| powershell | opus48-1m-medium-cli2.1.195 | 2 | 0 | 0.0min | 0.0% | $0.00 | 0.00% |
| powershell | opus48-1m-medium-cli2.1.193 | 5 | 3 | 3.2min | 0.5% | $0.78 | 0.44% |
| default | opus48-1m-medium-cli2.1.195 | 2 | 2 | 3.3min | 0.5% | $0.82 | 0.46% |
| powershell-tool | opus48-1m-medium-cli2.1.195 | 3 | 3 | 3.3min | 0.5% | $0.85 | 0.48% |
| powershell-tool | opus48-1m-medium-cli2.1.193 | 4 | 4 | 5.3min | 0.8% | $1.31 | 0.73% |
| bash | opus48-1m-medium-cli2.1.193 | 5 | 5 | 5.5min | 0.8% | $1.49 | 0.83% |
| default | opus48-1m-medium-cli2.1.193 | 5 | 5 | 6.4min | 0.9% | $1.57 | 0.88% |
| bash | opus48-1m-medium-cli2.1.195 | 2 | 3 | 7.7min | 1.1% | $1.92 | 1.08% |
| powershell-tool | opus48-1m-high-cli2.1.195 | 6 | 6 | 8.8min | 1.3% | $2.10 | 1.18% |
| default | opus48-1m-high-cli2.1.195 | 7 | 5 | 10.0min | 1.4% | $2.94 | 1.65% |
| typescript-bun | opus48-1m-medium-cli2.1.195 | 3 | 8 | 16.3min | 2.4% | $3.68 | 2.06% |
| typescript-bun | opus48-1m-medium-cli2.1.193 | 4 | 7 | 16.7min | 2.4% | $4.43 | 2.49% |
| bash | opus48-1m-high-cli2.1.195 | 6 | 12 | 17.9min | 2.6% | $4.84 | 2.72% |
| powershell | opus48-1m-high-cli2.1.195 | 7 | 12 | 24.8min | 3.6% | $5.75 | 3.23% |
| typescript-bun | opus48-1m-high-cli2.1.195 | 6 | 10 | 25.6min | 3.7% | $8.27 | 4.64% |

</details>

<details>
<summary>Sorted by $ lost (least first)</summary>

| Language | Model | Runs | Traps | Time Lost | % of Time | $ Lost | % of $ |
|------|-------|------|-------|-----------|-----------|--------|--------|
| powershell | opus48-1m-medium-cli2.1.195 | 2 | 0 | 0.0min | 0.0% | $0.00 | 0.00% |
| powershell | opus48-1m-medium-cli2.1.193 | 5 | 3 | 3.2min | 0.5% | $0.78 | 0.44% |
| default | opus48-1m-medium-cli2.1.195 | 2 | 2 | 3.3min | 0.5% | $0.82 | 0.46% |
| powershell-tool | opus48-1m-medium-cli2.1.195 | 3 | 3 | 3.3min | 0.5% | $0.85 | 0.48% |
| powershell-tool | opus48-1m-medium-cli2.1.193 | 4 | 4 | 5.3min | 0.8% | $1.31 | 0.73% |
| bash | opus48-1m-medium-cli2.1.193 | 5 | 5 | 5.5min | 0.8% | $1.49 | 0.83% |
| default | opus48-1m-medium-cli2.1.193 | 5 | 5 | 6.4min | 0.9% | $1.57 | 0.88% |
| bash | opus48-1m-medium-cli2.1.195 | 2 | 3 | 7.7min | 1.1% | $1.92 | 1.08% |
| powershell-tool | opus48-1m-high-cli2.1.195 | 6 | 6 | 8.8min | 1.3% | $2.10 | 1.18% |
| default | opus48-1m-high-cli2.1.195 | 7 | 5 | 10.0min | 1.4% | $2.94 | 1.65% |
| typescript-bun | opus48-1m-medium-cli2.1.195 | 3 | 8 | 16.3min | 2.4% | $3.68 | 2.06% |
| typescript-bun | opus48-1m-medium-cli2.1.193 | 4 | 7 | 16.7min | 2.4% | $4.43 | 2.49% |
| bash | opus48-1m-high-cli2.1.195 | 6 | 12 | 17.9min | 2.6% | $4.84 | 2.72% |
| powershell | opus48-1m-high-cli2.1.195 | 7 | 12 | 24.8min | 3.6% | $5.75 | 3.23% |
| typescript-bun | opus48-1m-high-cli2.1.195 | 6 | 10 | 25.6min | 3.7% | $8.27 | 4.64% |

</details>

### Prompt Cache Savings

| Status | Runs | $ Saved | % of $ |
|--------|------|---------|--------|
| Full hit (100%) | 1 | $0.12 | 0.07% |
| Partial | 60 | $6.03 | 3.39% |
| Miss | 6 | $0.00 | 0.00% |

## Test Quality Evaluation

### Structural Metrics by Language/Model/Effort

Automated analysis of test files: test count, assertion count, and test-to-code line ratio.

| Language | Model | Avg Tests | Avg Assertions | Avg Assert/Test | Avg Test:Code Ratio |
|------|-------|-----------|----------------|-----------------|---------------------|
| bash | opus48-1m-high | 29.8 | 63.5 | 2.1 | 1.38 |
| bash | opus48-1m-medium | 22.4 | 39.0 | 1.7 | 1.19 |
| default | opus48-1m-high | 28.3 | 55.9 | 2.0 | 1.45 |
| default | opus48-1m-medium | 27.0 | 49.1 | 1.8 | 1.01 |
| powershell | opus48-1m-high | 44.7 | 82.4 | 1.8 | 5.25 |
| powershell | opus48-1m-medium | 33.7 | 63.0 | 1.9 | 2.54 |
| powershell-tool | opus48-1m-high | 40.7 | 76.5 | 1.9 | 3.52 |
| powershell-tool | opus48-1m-medium | 31.9 | 56.7 | 1.8 | 4.49 |
| typescript-bun | opus48-1m-high | 40.0 | 85.7 | 2.1 | 0.99 |
| typescript-bun | opus48-1m-medium | 30.9 | 65.1 | 2.1 | 1.02 |


<details>
<summary>Sorted by avg tests (most first)</summary>

| Language | Model | Avg Tests | Avg Assertions | Avg Assert/Test | Avg Test:Code Ratio |
|------|-------|-----------|----------------|-----------------|---------------------|
| powershell | opus48-1m-high | 44.7 | 82.4 | 1.8 | 5.25 |
| powershell-tool | opus48-1m-high | 40.7 | 76.5 | 1.9 | 3.52 |
| typescript-bun | opus48-1m-high | 40.0 | 85.7 | 2.1 | 0.99 |
| powershell | opus48-1m-medium | 33.7 | 63.0 | 1.9 | 2.54 |
| powershell-tool | opus48-1m-medium | 31.9 | 56.7 | 1.8 | 4.49 |
| typescript-bun | opus48-1m-medium | 30.9 | 65.1 | 2.1 | 1.02 |
| bash | opus48-1m-high | 29.8 | 63.5 | 2.1 | 1.38 |
| default | opus48-1m-high | 28.3 | 55.9 | 2.0 | 1.45 |
| default | opus48-1m-medium | 27.0 | 49.1 | 1.8 | 1.01 |
| bash | opus48-1m-medium | 22.4 | 39.0 | 1.7 | 1.19 |

</details>

<details>
<summary>Sorted by avg assertions (most first)</summary>

| Language | Model | Avg Tests | Avg Assertions | Avg Assert/Test | Avg Test:Code Ratio |
|------|-------|-----------|----------------|-----------------|---------------------|
| typescript-bun | opus48-1m-high | 40.0 | 85.7 | 2.1 | 0.99 |
| powershell | opus48-1m-high | 44.7 | 82.4 | 1.8 | 5.25 |
| powershell-tool | opus48-1m-high | 40.7 | 76.5 | 1.9 | 3.52 |
| typescript-bun | opus48-1m-medium | 30.9 | 65.1 | 2.1 | 1.02 |
| bash | opus48-1m-high | 29.8 | 63.5 | 2.1 | 1.38 |
| powershell | opus48-1m-medium | 33.7 | 63.0 | 1.9 | 2.54 |
| powershell-tool | opus48-1m-medium | 31.9 | 56.7 | 1.8 | 4.49 |
| default | opus48-1m-high | 28.3 | 55.9 | 2.0 | 1.45 |
| default | opus48-1m-medium | 27.0 | 49.1 | 1.8 | 1.01 |
| bash | opus48-1m-medium | 22.4 | 39.0 | 1.7 | 1.19 |

</details>

<details>
<summary>Sorted by avg test:code ratio (highest first)</summary>

| Language | Model | Avg Tests | Avg Assertions | Avg Assert/Test | Avg Test:Code Ratio |
|------|-------|-----------|----------------|-----------------|---------------------|
| powershell | opus48-1m-high | 44.7 | 82.4 | 1.8 | 5.25 |
| powershell-tool | opus48-1m-medium | 31.9 | 56.7 | 1.8 | 4.49 |
| powershell-tool | opus48-1m-high | 40.7 | 76.5 | 1.9 | 3.52 |
| powershell | opus48-1m-medium | 33.7 | 63.0 | 1.9 | 2.54 |
| default | opus48-1m-high | 28.3 | 55.9 | 2.0 | 1.45 |
| bash | opus48-1m-high | 29.8 | 63.5 | 2.1 | 1.38 |
| bash | opus48-1m-medium | 22.4 | 39.0 | 1.7 | 1.19 |
| typescript-bun | opus48-1m-medium | 30.9 | 65.1 | 2.1 | 1.02 |
| default | opus48-1m-medium | 27.0 | 49.1 | 1.8 | 1.01 |
| typescript-bun | opus48-1m-high | 40.0 | 85.7 | 2.1 | 0.99 |

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
| Environment Matrix Generator | typescript-bun | opus48-1m-medium | 29 | 55 | 1.9 | 547 | 262 | 2.09 |
| Artifact Cleanup Script | bash | opus48-1m-medium | 17 | 55 | 3.2 | 304 | 258 | 1.18 |
| Artifact Cleanup Script | default | opus48-1m-medium | 28 | 54 | 1.9 | 253 | 263 | 0.96 |
| Artifact Cleanup Script | powershell | opus48-1m-medium | 25 | 62 | 2.5 | 328 | 292 | 1.12 |
| Artifact Cleanup Script | powershell-tool | opus48-1m-medium | 25 | 48 | 1.9 | 369 | 155 | 2.38 |
| Artifact Cleanup Script | typescript-bun | opus48-1m-medium | 23 | 53 | 2.3 | 273 | 525 | 0.52 |
| Secret Rotation Validator | bash | opus48-1m-medium | 27 | 62 | 2.3 | 229 | 372 | 0.62 |
| Secret Rotation Validator | default | opus48-1m-medium | 25 | 43 | 1.7 | 261 | 404 | 0.65 |
| Secret Rotation Validator | powershell | opus48-1m-medium | 46 | 91 | 2.0 | 446 | 299 | 1.49 |
| Secret Rotation Validator | powershell-tool | opus48-1m-medium | 43 | 78 | 1.8 | 481 | 58 | 8.29 |
| Secret Rotation Validator | typescript-bun | opus48-1m-medium | 35 | 86 | 2.5 | 435 | 701 | 0.62 |
| Environment Matrix Generator | powershell-tool | opus48-1m-high | 55 | 106 | 1.9 | 669 | 256 | 2.61 |
| Environment Matrix Generator | typescript-bun | opus48-1m-high | 38 | 83 | 2.2 | 568 | 393 | 1.45 |
| Artifact Cleanup Script | default | opus48-1m-high | 24 | 57 | 2.4 | 369 | 505 | 0.73 |
| Artifact Cleanup Script | powershell | opus48-1m-high | 25 | 55 | 2.2 | 339 | 420 | 0.81 |
| Artifact Cleanup Script | bash | opus48-1m-high | 23 | 43 | 1.9 | 278 | 292 | 0.95 |
| Artifact Cleanup Script | powershell-tool | opus48-1m-high | 38 | 79 | 2.1 | 442 | 89 | 4.97 |
| Artifact Cleanup Script | typescript-bun | opus48-1m-high | 33 | 80 | 2.4 | 406 | 622 | 0.65 |
| Secret Rotation Validator | default | opus48-1m-high | 27 | 58 | 2.1 | 453 | 290 | 1.56 |
| Secret Rotation Validator | powershell | opus48-1m-high | 46 | 89 | 1.9 | 414 | 264 | 1.57 |

</details>

## Per-Run Results

*Tests Quality = Overall (1-5) from LLM-as-judge of generated test code (dimensions: coverage, rigor, design). `—` = no judge data.*

| Task | Language | Model | Duration | Turns | Errors | Cost | Tests Quality | Chosen | Status |
|------|----------|-------|----------|-------|--------|------|-----------|--------|--------|
| Artifact Cleanup Script | bash | opus48-1m-high | 11.6min | 47 | 0 | $3.32 | — | bash | ok |
| Artifact Cleanup Script | bash | opus48-1m-medium | 11.4min | 53 | 1 | $3.16 | — | bash | ok |
| Artifact Cleanup Script | default | opus48-1m-high | 10.2min | 50 | 0 | $3.16 | — | python | ok |
| Artifact Cleanup Script | default | opus48-1m-medium | 9.9min | 43 | 0 | $2.37 | — | powershell | ok |
| Artifact Cleanup Script | powershell | opus48-1m-high | 9.6min | 35 | 2 | $2.60 | — | powershell | ok |
| Artifact Cleanup Script | powershell | opus48-1m-medium | 9.3min | 28 | 0 | $2.26 | — | powershell | ok |
| Artifact Cleanup Script | powershell-tool | opus48-1m-high | 11.8min | 31 | 1 | $2.83 | — | powershell | ok |
| Artifact Cleanup Script | powershell-tool | opus48-1m-medium | 11.9min | 46 | 1 | $2.91 | — | powershell | ok |
| Artifact Cleanup Script | typescript-bun | opus48-1m-high | 14.8min | 82 | 1 | $6.00 | — | typescript | ok |
| Artifact Cleanup Script | typescript-bun | opus48-1m-medium | 9.2min | 44 | 0 | $2.44 | — | typescript | ok |
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
| Environment Matrix Generator | powershell-tool | opus48-1m-high | 9.2min | 27 | 0 | $3.06 | — | powershell | ok |
| Environment Matrix Generator | powershell-tool | opus48-1m-medium | 12.9min | 52 | 2 | $3.60 | — | powershell | ok |
| Environment Matrix Generator | typescript-bun | opus48-1m-high | 13.3min | 69 | 0 | $3.94 | — | typescript | ok |
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
| Secret Rotation Validator | default | opus48-1m-high | 9.1min | 47 | 0 | $3.12 | — | python | ok |
| Secret Rotation Validator | default | opus48-1m-medium | 5.9min | 29 | 0 | $1.65 | — | python | ok |
| Secret Rotation Validator | powershell | opus48-1m-high | 15.4min | 53 | 0 | $3.46 | — | powershell | ok |
| Secret Rotation Validator | powershell | opus48-1m-medium | 1.1min | 11 | 0 | $0.55 | — | powershell | ok |
| Secret Rotation Validator | powershell-tool | opus48-1m-medium | 8.0min | 34 | 1 | $2.14 | — | powershell | ok |
| Secret Rotation Validator | typescript-bun | opus48-1m-medium | 23.0min | 78 | 2 | $4.51 | — | typescript | ok |
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
| Secret Rotation Validator | default | opus48-1m-medium | 5.9min | 29 | 0 | $1.65 | — | python | ok |
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
| Secret Rotation Validator | powershell-tool | opus48-1m-medium | 8.0min | 34 | 1 | $2.14 | — | powershell | ok |
| Test Results Aggregator | bash | opus48-1m-high | 8.4min | 28 | 0 | $2.20 | — | bash | ok |
| Dependency License Checker | default | opus48-1m-high | 9.0min | 34 | 0 | $2.24 | — | powershell | ok |
| Artifact Cleanup Script | powershell | opus48-1m-medium | 9.3min | 28 | 0 | $2.26 | — | powershell | ok |
| Environment Matrix Generator | typescript-bun | opus48-1m-medium | 9.1min | 40 | 0 | $2.29 | — | typescript | ok |
| Environment Matrix Generator | powershell | opus48-1m-medium | 9.3min | 33 | 0 | $2.29 | — | powershell | ok |
| Semantic Version Bumper | powershell-tool | opus48-1m-high | 12.1min | 34 | 0 | $2.32 | — | powershell | ok |
| Dependency License Checker | typescript-bun | opus48-1m-medium | 8.7min | 45 | 0 | $2.33 | — | typescript | ok |
| Semantic Version Bumper | powershell | opus48-1m-medium | 10.0min | 34 | 0 | $2.33 | — | powershell | ok |
| Artifact Cleanup Script | default | opus48-1m-medium | 9.9min | 43 | 0 | $2.37 | — | powershell | ok |
| Semantic Version Bumper | powershell-tool | opus48-1m-medium | 10.6min | 40 | 1 | $2.39 | — | powershell | ok |
| Artifact Cleanup Script | typescript-bun | opus48-1m-medium | 9.2min | 44 | 0 | $2.44 | — | typescript | ok |
| PR Label Assigner | bash | opus48-1m-high | 10.1min | 31 | 0 | $2.45 | — | bash | ok |
| Semantic Version Bumper | typescript-bun | opus48-1m-medium | 9.3min | 47 | 2 | $2.47 | — | typescript | ok |
| PR Label Assigner | typescript-bun | opus48-1m-medium | 13.1min | 44 | 0 | $2.48 | — | typescript | ok |
| Environment Matrix Generator | bash | opus48-1m-high | 9.4min | 39 | 1 | $2.51 | — | bash | ok |
| Test Results Aggregator | typescript-bun | opus48-1m-medium | 9.2min | 45 | 0 | $2.57 | — | typescript | ok |
| Artifact Cleanup Script | powershell | opus48-1m-high | 9.6min | 35 | 2 | $2.60 | — | powershell | ok |
| Dependency License Checker | powershell-tool | opus48-1m-high | 12.2min | 33 | 0 | $2.63 | — | powershell | ok |
| PR Label Assigner | powershell | opus48-1m-high | 11.0min | 47 | 0 | $2.65 | — | powershell | ok |
| Semantic Version Bumper | bash | opus48-1m-high | 9.5min | 41 | 1 | $2.70 | — | bash | ok |
| PR Label Assigner | powershell-tool | opus48-1m-high | 11.4min | 41 | 0 | $2.78 | — | powershell | ok |
| Artifact Cleanup Script | powershell-tool | opus48-1m-high | 11.8min | 31 | 1 | $2.83 | — | powershell | ok |
| Artifact Cleanup Script | powershell-tool | opus48-1m-medium | 11.9min | 46 | 1 | $2.91 | — | powershell | ok |
| Dependency License Checker | typescript-bun | opus48-1m-high | 11.5min | 47 | 0 | $3.04 | — | typescript | ok |
| Environment Matrix Generator | powershell-tool | opus48-1m-high | 9.2min | 27 | 0 | $3.06 | — | powershell | ok |
| Dependency License Checker | powershell | opus48-1m-high | 12.8min | 42 | 1 | $3.09 | — | powershell | ok |
| Secret Rotation Validator | default | opus48-1m-high | 9.1min | 47 | 0 | $3.12 | — | python | ok |
| Semantic Version Bumper | typescript-bun | opus48-1m-high | 11.5min | 52 | 0 | $3.14 | — | typescript | ok |
| Artifact Cleanup Script | bash | opus48-1m-medium | 11.4min | 53 | 1 | $3.16 | — | bash | ok |
| Artifact Cleanup Script | default | opus48-1m-high | 10.2min | 50 | 0 | $3.16 | — | python | ok |
| Artifact Cleanup Script | bash | opus48-1m-high | 11.6min | 47 | 0 | $3.32 | — | bash | ok |
| Semantic Version Bumper | default | opus48-1m-high | 9.8min | 52 | 0 | $3.34 | — | javascript | ok |
| Dependency License Checker | powershell-tool | opus48-1m-medium | 12.7min | 49 | 0 | $3.35 | — | powershell | ok |
| Test Results Aggregator | powershell-tool | opus48-1m-high | 15.2min | 47 | 0 | $3.39 | — | powershell | ok |
| Test Results Aggregator | default | opus48-1m-high | 12.2min | 59 | 1 | $3.42 | — | python | ok |
| Secret Rotation Validator | powershell | opus48-1m-high | 15.4min | 53 | 0 | $3.46 | — | powershell | ok |
| Environment Matrix Generator | powershell | opus48-1m-high | 13.7min | 44 | 1 | $3.48 | — | powershell | ok |
| Semantic Version Bumper | powershell | opus48-1m-high | 16.9min | 60 | 2 | $3.59 | — | powershell | ok |
| Environment Matrix Generator | powershell-tool | opus48-1m-medium | 12.9min | 52 | 2 | $3.60 | — | powershell | ok |
| Test Results Aggregator | powershell | opus48-1m-high | 17.3min | 59 | 0 | $3.84 | — | powershell | ok |
| Environment Matrix Generator | typescript-bun | opus48-1m-high | 13.3min | 69 | 0 | $3.94 | — | typescript | ok |
| Dependency License Checker | bash | opus48-1m-high | 15.0min | 51 | 3 | $4.02 | — | bash | ok |
| Secret Rotation Validator | typescript-bun | opus48-1m-medium | 23.0min | 78 | 2 | $4.51 | — | typescript | ok |
| Test Results Aggregator | typescript-bun | opus48-1m-high | 19.2min | 69 | 0 | $5.19 | — | typescript | ok |
| Secret Rotation Validator | bash | opus48-1m-medium | 23.9min | 64 | 6 | $5.71 | — | bash | ok |
| Artifact Cleanup Script | typescript-bun | opus48-1m-high | 14.8min | 82 | 1 | $6.00 | — | typescript | ok |

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
| Secret Rotation Validator | default | opus48-1m-medium | 5.9min | 29 | 0 | $1.65 | — | python | ok |
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
| Secret Rotation Validator | powershell-tool | opus48-1m-medium | 8.0min | 34 | 1 | $2.14 | — | powershell | ok |
| Test Results Aggregator | powershell | opus48-1m-medium | 8.1min | 30 | 0 | $1.77 | — | powershell | ok |
| PR Label Assigner | default | opus48-1m-medium | 8.2min | 36 | 1 | $1.91 | — | powershell | ok |
| Environment Matrix Generator | default | opus48-1m-high | 8.2min | 24 | 0 | $2.01 | — | python | ok |
| Test Results Aggregator | bash | opus48-1m-high | 8.4min | 28 | 0 | $2.20 | — | bash | ok |
| Dependency License Checker | typescript-bun | opus48-1m-medium | 8.7min | 45 | 0 | $2.33 | — | typescript | ok |
| Dependency License Checker | default | opus48-1m-high | 9.0min | 34 | 0 | $2.24 | — | powershell | ok |
| Secret Rotation Validator | default | opus48-1m-high | 9.1min | 47 | 0 | $3.12 | — | python | ok |
| Environment Matrix Generator | typescript-bun | opus48-1m-medium | 9.1min | 40 | 0 | $2.29 | — | typescript | ok |
| Environment Matrix Generator | powershell-tool | opus48-1m-high | 9.2min | 27 | 0 | $3.06 | — | powershell | ok |
| Artifact Cleanup Script | typescript-bun | opus48-1m-medium | 9.2min | 44 | 0 | $2.44 | — | typescript | ok |
| Test Results Aggregator | typescript-bun | opus48-1m-medium | 9.2min | 45 | 0 | $2.57 | — | typescript | ok |
| Artifact Cleanup Script | powershell | opus48-1m-medium | 9.3min | 28 | 0 | $2.26 | — | powershell | ok |
| Semantic Version Bumper | typescript-bun | opus48-1m-medium | 9.3min | 47 | 2 | $2.47 | — | typescript | ok |
| Environment Matrix Generator | powershell | opus48-1m-medium | 9.3min | 33 | 0 | $2.29 | — | powershell | ok |
| Environment Matrix Generator | bash | opus48-1m-high | 9.4min | 39 | 1 | $2.51 | — | bash | ok |
| Semantic Version Bumper | bash | opus48-1m-high | 9.5min | 41 | 1 | $2.70 | — | bash | ok |
| Artifact Cleanup Script | powershell | opus48-1m-high | 9.6min | 35 | 2 | $2.60 | — | powershell | ok |
| Semantic Version Bumper | default | opus48-1m-high | 9.8min | 52 | 0 | $3.34 | — | javascript | ok |
| Artifact Cleanup Script | default | opus48-1m-medium | 9.9min | 43 | 0 | $2.37 | — | powershell | ok |
| Semantic Version Bumper | powershell | opus48-1m-medium | 10.0min | 34 | 0 | $2.33 | — | powershell | ok |
| PR Label Assigner | bash | opus48-1m-high | 10.1min | 31 | 0 | $2.45 | — | bash | ok |
| Artifact Cleanup Script | default | opus48-1m-high | 10.2min | 50 | 0 | $3.16 | — | python | ok |
| Semantic Version Bumper | powershell-tool | opus48-1m-medium | 10.6min | 40 | 1 | $2.39 | — | powershell | ok |
| PR Label Assigner | powershell | opus48-1m-high | 11.0min | 47 | 0 | $2.65 | — | powershell | ok |
| Artifact Cleanup Script | bash | opus48-1m-medium | 11.4min | 53 | 1 | $3.16 | — | bash | ok |
| PR Label Assigner | powershell-tool | opus48-1m-high | 11.4min | 41 | 0 | $2.78 | — | powershell | ok |
| Semantic Version Bumper | typescript-bun | opus48-1m-high | 11.5min | 52 | 0 | $3.14 | — | typescript | ok |
| Dependency License Checker | typescript-bun | opus48-1m-high | 11.5min | 47 | 0 | $3.04 | — | typescript | ok |
| Artifact Cleanup Script | bash | opus48-1m-high | 11.6min | 47 | 0 | $3.32 | — | bash | ok |
| Artifact Cleanup Script | powershell-tool | opus48-1m-high | 11.8min | 31 | 1 | $2.83 | — | powershell | ok |
| Artifact Cleanup Script | powershell-tool | opus48-1m-medium | 11.9min | 46 | 1 | $2.91 | — | powershell | ok |
| Semantic Version Bumper | powershell-tool | opus48-1m-high | 12.1min | 34 | 0 | $2.32 | — | powershell | ok |
| Dependency License Checker | powershell-tool | opus48-1m-high | 12.2min | 33 | 0 | $2.63 | — | powershell | ok |
| Test Results Aggregator | default | opus48-1m-high | 12.2min | 59 | 1 | $3.42 | — | python | ok |
| Dependency License Checker | powershell-tool | opus48-1m-medium | 12.7min | 49 | 0 | $3.35 | — | powershell | ok |
| Dependency License Checker | powershell | opus48-1m-high | 12.8min | 42 | 1 | $3.09 | — | powershell | ok |
| Environment Matrix Generator | powershell-tool | opus48-1m-medium | 12.9min | 52 | 2 | $3.60 | — | powershell | ok |
| PR Label Assigner | typescript-bun | opus48-1m-medium | 13.1min | 44 | 0 | $2.48 | — | typescript | ok |
| Environment Matrix Generator | typescript-bun | opus48-1m-high | 13.3min | 69 | 0 | $3.94 | — | typescript | ok |
| Environment Matrix Generator | powershell | opus48-1m-high | 13.7min | 44 | 1 | $3.48 | — | powershell | ok |
| Artifact Cleanup Script | typescript-bun | opus48-1m-high | 14.8min | 82 | 1 | $6.00 | — | typescript | ok |
| Dependency License Checker | bash | opus48-1m-high | 15.0min | 51 | 3 | $4.02 | — | bash | ok |
| Test Results Aggregator | powershell-tool | opus48-1m-high | 15.2min | 47 | 0 | $3.39 | — | powershell | ok |
| Secret Rotation Validator | powershell | opus48-1m-high | 15.4min | 53 | 0 | $3.46 | — | powershell | ok |
| Semantic Version Bumper | powershell | opus48-1m-high | 16.9min | 60 | 2 | $3.59 | — | powershell | ok |
| Test Results Aggregator | powershell | opus48-1m-high | 17.3min | 59 | 0 | $3.84 | — | powershell | ok |
| Test Results Aggregator | typescript-bun | opus48-1m-high | 19.2min | 69 | 0 | $5.19 | — | typescript | ok |
| Secret Rotation Validator | typescript-bun | opus48-1m-medium | 23.0min | 78 | 2 | $4.51 | — | typescript | ok |
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
| Environment Matrix Generator | typescript-bun | opus48-1m-medium | 9.1min | 40 | 0 | $2.29 | — | typescript | ok |
| Artifact Cleanup Script | default | opus48-1m-medium | 9.9min | 43 | 0 | $2.37 | — | powershell | ok |
| Artifact Cleanup Script | powershell | opus48-1m-medium | 9.3min | 28 | 0 | $2.26 | — | powershell | ok |
| Artifact Cleanup Script | typescript-bun | opus48-1m-medium | 9.2min | 44 | 0 | $2.44 | — | typescript | ok |
| Secret Rotation Validator | default | opus48-1m-medium | 5.9min | 29 | 0 | $1.65 | — | python | ok |
| Secret Rotation Validator | powershell | opus48-1m-medium | 1.1min | 11 | 0 | $0.55 | — | powershell | ok |
| Environment Matrix Generator | powershell-tool | opus48-1m-high | 9.2min | 27 | 0 | $3.06 | — | powershell | ok |
| Environment Matrix Generator | typescript-bun | opus48-1m-high | 13.3min | 69 | 0 | $3.94 | — | typescript | ok |
| Artifact Cleanup Script | default | opus48-1m-high | 10.2min | 50 | 0 | $3.16 | — | python | ok |
| Artifact Cleanup Script | bash | opus48-1m-high | 11.6min | 47 | 0 | $3.32 | — | bash | ok |
| Secret Rotation Validator | default | opus48-1m-high | 9.1min | 47 | 0 | $3.12 | — | python | ok |
| Secret Rotation Validator | powershell | opus48-1m-high | 15.4min | 53 | 0 | $3.46 | — | powershell | ok |
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
| Artifact Cleanup Script | bash | opus48-1m-medium | 11.4min | 53 | 1 | $3.16 | — | bash | ok |
| Artifact Cleanup Script | powershell-tool | opus48-1m-medium | 11.9min | 46 | 1 | $2.91 | — | powershell | ok |
| Secret Rotation Validator | powershell-tool | opus48-1m-medium | 8.0min | 34 | 1 | $2.14 | — | powershell | ok |
| Artifact Cleanup Script | powershell-tool | opus48-1m-high | 11.8min | 31 | 1 | $2.83 | — | powershell | ok |
| Artifact Cleanup Script | typescript-bun | opus48-1m-high | 14.8min | 82 | 1 | $6.00 | — | typescript | ok |
| Semantic Version Bumper | powershell | opus48-1m-high | 16.9min | 60 | 2 | $3.59 | — | powershell | ok |
| Semantic Version Bumper | typescript-bun | opus48-1m-medium | 9.3min | 47 | 2 | $2.47 | — | typescript | ok |
| Environment Matrix Generator | powershell-tool | opus48-1m-medium | 12.9min | 52 | 2 | $3.60 | — | powershell | ok |
| Secret Rotation Validator | typescript-bun | opus48-1m-medium | 23.0min | 78 | 2 | $4.51 | — | typescript | ok |
| Artifact Cleanup Script | powershell | opus48-1m-high | 9.6min | 35 | 2 | $2.60 | — | powershell | ok |
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
| Environment Matrix Generator | powershell-tool | opus48-1m-high | 9.2min | 27 | 0 | $3.06 | — | powershell | ok |
| Test Results Aggregator | bash | opus48-1m-high | 8.4min | 28 | 0 | $2.20 | — | bash | ok |
| Environment Matrix Generator | default | opus48-1m-medium | 6.7min | 28 | 0 | $2.01 | — | python | ok |
| Artifact Cleanup Script | powershell | opus48-1m-medium | 9.3min | 28 | 0 | $2.26 | — | powershell | ok |
| Test Results Aggregator | bash | opus48-1m-medium | 6.3min | 29 | 1 | $1.83 | — | bash | ok |
| Test Results Aggregator | powershell-tool | opus48-1m-medium | 7.4min | 29 | 0 | $1.95 | — | powershell | ok |
| Secret Rotation Validator | default | opus48-1m-medium | 5.9min | 29 | 0 | $1.65 | — | python | ok |
| Test Results Aggregator | powershell | opus48-1m-medium | 8.1min | 30 | 0 | $1.77 | — | powershell | ok |
| PR Label Assigner | bash | opus48-1m-high | 10.1min | 31 | 0 | $2.45 | — | bash | ok |
| Artifact Cleanup Script | powershell-tool | opus48-1m-high | 11.8min | 31 | 1 | $2.83 | — | powershell | ok |
| Dependency License Checker | default | opus48-1m-medium | 7.9min | 33 | 0 | $1.94 | — | python | ok |
| Dependency License Checker | powershell | opus48-1m-medium | 7.7min | 33 | 0 | $1.93 | — | powershell | ok |
| Dependency License Checker | powershell-tool | opus48-1m-high | 12.2min | 33 | 0 | $2.63 | — | powershell | ok |
| Environment Matrix Generator | powershell | opus48-1m-medium | 9.3min | 33 | 0 | $2.29 | — | powershell | ok |
| Semantic Version Bumper | powershell | opus48-1m-medium | 10.0min | 34 | 0 | $2.33 | — | powershell | ok |
| Semantic Version Bumper | powershell-tool | opus48-1m-high | 12.1min | 34 | 0 | $2.32 | — | powershell | ok |
| Dependency License Checker | default | opus48-1m-high | 9.0min | 34 | 0 | $2.24 | — | powershell | ok |
| Secret Rotation Validator | powershell-tool | opus48-1m-medium | 8.0min | 34 | 1 | $2.14 | — | powershell | ok |
| Artifact Cleanup Script | powershell | opus48-1m-high | 9.6min | 35 | 2 | $2.60 | — | powershell | ok |
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
| Artifact Cleanup Script | typescript-bun | opus48-1m-medium | 9.2min | 44 | 0 | $2.44 | — | typescript | ok |
| Dependency License Checker | typescript-bun | opus48-1m-medium | 8.7min | 45 | 0 | $2.33 | — | typescript | ok |
| Test Results Aggregator | typescript-bun | opus48-1m-medium | 9.2min | 45 | 0 | $2.57 | — | typescript | ok |
| Artifact Cleanup Script | powershell-tool | opus48-1m-medium | 11.9min | 46 | 1 | $2.91 | — | powershell | ok |
| Semantic Version Bumper | typescript-bun | opus48-1m-medium | 9.3min | 47 | 2 | $2.47 | — | typescript | ok |
| PR Label Assigner | powershell | opus48-1m-high | 11.0min | 47 | 0 | $2.65 | — | powershell | ok |
| Dependency License Checker | typescript-bun | opus48-1m-high | 11.5min | 47 | 0 | $3.04 | — | typescript | ok |
| Test Results Aggregator | powershell-tool | opus48-1m-high | 15.2min | 47 | 0 | $3.39 | — | powershell | ok |
| Artifact Cleanup Script | bash | opus48-1m-high | 11.6min | 47 | 0 | $3.32 | — | bash | ok |
| Secret Rotation Validator | default | opus48-1m-high | 9.1min | 47 | 0 | $3.12 | — | python | ok |
| Dependency License Checker | powershell-tool | opus48-1m-medium | 12.7min | 49 | 0 | $3.35 | — | powershell | ok |
| Artifact Cleanup Script | default | opus48-1m-high | 10.2min | 50 | 0 | $3.16 | — | python | ok |
| Dependency License Checker | bash | opus48-1m-high | 15.0min | 51 | 3 | $4.02 | — | bash | ok |
| Semantic Version Bumper | default | opus48-1m-high | 9.8min | 52 | 0 | $3.34 | — | javascript | ok |
| Semantic Version Bumper | typescript-bun | opus48-1m-high | 11.5min | 52 | 0 | $3.14 | — | typescript | ok |
| Environment Matrix Generator | powershell-tool | opus48-1m-medium | 12.9min | 52 | 2 | $3.60 | — | powershell | ok |
| Artifact Cleanup Script | bash | opus48-1m-medium | 11.4min | 53 | 1 | $3.16 | — | bash | ok |
| Secret Rotation Validator | powershell | opus48-1m-high | 15.4min | 53 | 0 | $3.46 | — | powershell | ok |
| Test Results Aggregator | default | opus48-1m-high | 12.2min | 59 | 1 | $3.42 | — | python | ok |
| Test Results Aggregator | powershell | opus48-1m-high | 17.3min | 59 | 0 | $3.84 | — | powershell | ok |
| Semantic Version Bumper | powershell | opus48-1m-high | 16.9min | 60 | 2 | $3.59 | — | powershell | ok |
| Secret Rotation Validator | bash | opus48-1m-medium | 23.9min | 64 | 6 | $5.71 | — | bash | ok |
| Test Results Aggregator | typescript-bun | opus48-1m-high | 19.2min | 69 | 0 | $5.19 | — | typescript | ok |
| Environment Matrix Generator | typescript-bun | opus48-1m-high | 13.3min | 69 | 0 | $3.94 | — | typescript | ok |
| Secret Rotation Validator | typescript-bun | opus48-1m-medium | 23.0min | 78 | 2 | $4.51 | — | typescript | ok |
| Artifact Cleanup Script | typescript-bun | opus48-1m-high | 14.8min | 82 | 1 | $6.00 | — | typescript | ok |

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
| Environment Matrix Generator | typescript-bun | opus48-1m-medium | 9.1min | 40 | 0 | $2.29 | — | typescript | ok |
| Artifact Cleanup Script | bash | opus48-1m-medium | 11.4min | 53 | 1 | $3.16 | — | bash | ok |
| Artifact Cleanup Script | default | opus48-1m-medium | 9.9min | 43 | 0 | $2.37 | — | powershell | ok |
| Artifact Cleanup Script | powershell | opus48-1m-medium | 9.3min | 28 | 0 | $2.26 | — | powershell | ok |
| Artifact Cleanup Script | powershell-tool | opus48-1m-medium | 11.9min | 46 | 1 | $2.91 | — | powershell | ok |
| Artifact Cleanup Script | typescript-bun | opus48-1m-medium | 9.2min | 44 | 0 | $2.44 | — | typescript | ok |
| Secret Rotation Validator | bash | opus48-1m-medium | 23.9min | 64 | 6 | $5.71 | — | bash | ok |
| Secret Rotation Validator | default | opus48-1m-medium | 5.9min | 29 | 0 | $1.65 | — | python | ok |
| Secret Rotation Validator | powershell | opus48-1m-medium | 1.1min | 11 | 0 | $0.55 | — | powershell | ok |
| Secret Rotation Validator | powershell-tool | opus48-1m-medium | 8.0min | 34 | 1 | $2.14 | — | powershell | ok |
| Secret Rotation Validator | typescript-bun | opus48-1m-medium | 23.0min | 78 | 2 | $4.51 | — | typescript | ok |
| Environment Matrix Generator | powershell-tool | opus48-1m-high | 9.2min | 27 | 0 | $3.06 | — | powershell | ok |
| Environment Matrix Generator | typescript-bun | opus48-1m-high | 13.3min | 69 | 0 | $3.94 | — | typescript | ok |
| Artifact Cleanup Script | default | opus48-1m-high | 10.2min | 50 | 0 | $3.16 | — | python | ok |
| Artifact Cleanup Script | powershell | opus48-1m-high | 9.6min | 35 | 2 | $2.60 | — | powershell | ok |
| Artifact Cleanup Script | bash | opus48-1m-high | 11.6min | 47 | 0 | $3.32 | — | bash | ok |
| Artifact Cleanup Script | powershell-tool | opus48-1m-high | 11.8min | 31 | 1 | $2.83 | — | powershell | ok |
| Artifact Cleanup Script | typescript-bun | opus48-1m-high | 14.8min | 82 | 1 | $6.00 | — | typescript | ok |
| Secret Rotation Validator | default | opus48-1m-high | 9.1min | 47 | 0 | $3.12 | — | python | ok |
| Secret Rotation Validator | powershell | opus48-1m-high | 15.4min | 53 | 0 | $3.46 | — | powershell | ok |

</details>

## Notes

### Tiers

- **Duration bands:** **A+** ≤1.05×, **A** ≤1.11×, **A-** ≤1.17×, **B+** ≤1.23×, **B** ≤1.30×, **B-** ≤1.37×, **C+** ≤1.44×, **C** ≤1.52×, **C-** ≤1.60×, **D+** ≤1.68×, **D** ≤1.77×, **D-** ≤1.87×, **F** >1.87×
- **Cost bands:** **A+** ≤1.06×, **A** ≤1.13×, **A-** ≤1.20×, **B+** ≤1.28×, **B** ≤1.36×, **B-** ≤1.44×, **C+** ≤1.53×, **C** ≤1.63×, **C-** ≤1.73×, **D+** ≤1.84×, **D** ≤1.95×, **D-** ≤2.07×, **F** >2.07×

*Tests/Workflow Craft bands are absolute Overall score bands:* **A+** ≥4.7, **A** ≥4.4, **A-** ≥4.1, **B+** ≥3.8, **B** ≥3.5, **B-** ≥3.2, **C+** ≥2.9, **C** ≥2.6, **C-** ≥2.3, **D+** ≥2.0, **D** ≥1.7, **D-** ≥1.4, **F** <1.4, `—` = no data.*

### CLI Version Legend

| Variant label | CLI version | Tasks | Languages |
|---------------|-------------|-------|-----------|
| opus48-1m-high | 2.1.195 | All | All |
| opus48-1m-medium | 2.1.193 | 11-semantic-version-bumper, 12-pr-label-assigner, 13-dependency-license-checker, 15-test-results-aggregator, 16-environment-matrix-generator | All |
| opus48-1m-medium | 2.1.195 | 16-environment-matrix-generator, 17-artifact-cleanup-script, 18-secret-rotation-validator | All |

---
*Generated by generate_results.py — benchmark instructions v4*