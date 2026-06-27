# Benchmark Results: Language Comparison

**Last updated:** 2026-06-27 08:33:06 AM ET — 46/70 runs completed, 24 remaining; total cost $109.36; total agent time 491.6 min.
**Claude Code versions used:** v2.1.193 (23 runs), v2.1.195 (23 runs). Each link goes to a per-version snapshot of the system prompt, default-tool descriptions, and the chronological Anthropic changelog up to that version. Regenerate with `python3 version_docs.py`.

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
| powershell | opus48-1m-medium | A (7.8min) | A+ ($1.75) | — | — |
| typescript-bun | opus48-1m-high | A+ (7.2min) | B ($2.15) | — | — |
| default | opus48-1m-high | B+ (8.6min) | C ($2.48) | — | — |
| default | opus48-1m-medium | B (9.5min) | C+ ($2.34) | — | — |
| bash | opus48-1m-high | B- (9.8min) | C- ($2.57) | — | — |
| powershell-tool | opus48-1m-medium | C+ (10.3min) | C- ($2.58) | — | — |
| powershell-tool | opus48-1m-high | C- (11.7min) | C ($2.55) | — | — |
| bash | opus48-1m-medium | D+ (12.1min) | C ($2.56) | — | — |
| typescript-bun | opus48-1m-medium* | C- (11.8min) | D+ ($2.76) | — | — |
| powershell | opus48-1m-high | D- (14.0min) | D- ($3.12) | — | — |


<details>
<summary>Sorted by Duration tier (best-first), then avg of Cost/Tests/Workflow Craft tiers</summary>

| Language | Model | Duration | Cost | Tests Quality | Workflow Craft |
|----------|-------|----------|------|-----------|-------------|
| typescript-bun | opus48-1m-high | A+ (7.2min) | B ($2.15) | — | — |
| powershell | opus48-1m-medium | A (7.8min) | A+ ($1.75) | — | — |
| default | opus48-1m-high | B+ (8.6min) | C ($2.48) | — | — |
| default | opus48-1m-medium | B (9.5min) | C+ ($2.34) | — | — |
| bash | opus48-1m-high | B- (9.8min) | C- ($2.57) | — | — |
| powershell-tool | opus48-1m-medium | C+ (10.3min) | C- ($2.58) | — | — |
| powershell-tool | opus48-1m-high | C- (11.7min) | C ($2.55) | — | — |
| typescript-bun | opus48-1m-medium* | C- (11.8min) | D+ ($2.76) | — | — |
| bash | opus48-1m-medium | D+ (12.1min) | C ($2.56) | — | — |
| powershell | opus48-1m-high | D- (14.0min) | D- ($3.12) | — | — |

</details>

<details>
<summary>Sorted by Cost tier (best-first), then avg of Duration/Tests/Workflow Craft tiers</summary>

| Language | Model | Duration | Cost | Tests Quality | Workflow Craft |
|----------|-------|----------|------|-----------|-------------|
| powershell | opus48-1m-medium | A (7.8min) | A+ ($1.75) | — | — |
| typescript-bun | opus48-1m-high | A+ (7.2min) | B ($2.15) | — | — |
| default | opus48-1m-medium | B (9.5min) | C+ ($2.34) | — | — |
| default | opus48-1m-high | B+ (8.6min) | C ($2.48) | — | — |
| powershell-tool | opus48-1m-high | C- (11.7min) | C ($2.55) | — | — |
| bash | opus48-1m-medium | D+ (12.1min) | C ($2.56) | — | — |
| bash | opus48-1m-high | B- (9.8min) | C- ($2.57) | — | — |
| powershell-tool | opus48-1m-medium | C+ (10.3min) | C- ($2.58) | — | — |
| typescript-bun | opus48-1m-medium* | C- (11.8min) | D+ ($2.76) | — | — |
| powershell | opus48-1m-high | D- (14.0min) | D- ($3.12) | — | — |

</details>

<details>
<summary>Sorted by Tests Quality tier (best-first; no-data last), then avg of other tiers</summary>

| Language | Model | Duration | Cost | Tests Quality | Workflow Craft |
|----------|-------|----------|------|-----------|-------------|
| powershell | opus48-1m-medium | A (7.8min) | A+ ($1.75) | — | — |
| typescript-bun | opus48-1m-high | A+ (7.2min) | B ($2.15) | — | — |
| default | opus48-1m-high | B+ (8.6min) | C ($2.48) | — | — |
| default | opus48-1m-medium | B (9.5min) | C+ ($2.34) | — | — |
| bash | opus48-1m-high | B- (9.8min) | C- ($2.57) | — | — |
| powershell-tool | opus48-1m-medium | C+ (10.3min) | C- ($2.58) | — | — |
| powershell-tool | opus48-1m-high | C- (11.7min) | C ($2.55) | — | — |
| bash | opus48-1m-medium | D+ (12.1min) | C ($2.56) | — | — |
| typescript-bun | opus48-1m-medium* | C- (11.8min) | D+ ($2.76) | — | — |
| powershell | opus48-1m-high | D- (14.0min) | D- ($3.12) | — | — |

</details>

<details>
<summary>Sorted by Workflow Craft tier (best-first; no-data last), then avg of other tiers</summary>

| Language | Model | Duration | Cost | Tests Quality | Workflow Craft |
|----------|-------|----------|------|-----------|-------------|
| powershell | opus48-1m-medium | A (7.8min) | A+ ($1.75) | — | — |
| typescript-bun | opus48-1m-high | A+ (7.2min) | B ($2.15) | — | — |
| default | opus48-1m-high | B+ (8.6min) | C ($2.48) | — | — |
| default | opus48-1m-medium | B (9.5min) | C+ ($2.34) | — | — |
| bash | opus48-1m-high | B- (9.8min) | C- ($2.57) | — | — |
| powershell-tool | opus48-1m-medium | C+ (10.3min) | C- ($2.58) | — | — |
| powershell-tool | opus48-1m-high | C- (11.7min) | C ($2.55) | — | — |
| bash | opus48-1m-medium | D+ (12.1min) | C ($2.56) | — | — |
| typescript-bun | opus48-1m-medium* | C- (11.8min) | D+ ($2.76) | — | — |
| powershell | opus48-1m-high | D- (14.0min) | D- ($3.12) | — | — |

</details>

- **Estimated time remaining:** 630.5min
- **Estimated total cost:** $166.42

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
| bash | opus48-1m-high | 2 | 9.8min | 6.8min | 0.5 | 36 | $2.57 | $5.15 | — | — |
| bash | opus48-1m-medium | 7 | 12.1min | 12.1min | 1.4 | 35 | $2.56 | $17.91 | — | — |
| default | opus48-1m-high | 3 | 8.6min | 7.9min | 0.3 | 37 | $2.48 | $7.44 | — | — |
| default | opus48-1m-medium | 7 | 9.5min | 9.5min | 0.3 | 33 | $2.34 | $16.35 | — | — |
| powershell | opus48-1m-high | 2 | 14.0min | 9.2min | 1.0 | 54 | $3.12 | $6.24 | — | — |
| powershell | opus48-1m-medium | 7 | 7.8min | 7.8min | 0.1 | 28 | $1.75 | $12.23 | — | — |
| powershell-tool | opus48-1m-high | 2 | 11.7min | 10.3min | 0.0 | 38 | $2.55 | $5.10 | — | — |
| powershell-tool | opus48-1m-medium | 7 | 10.3min | 10.3min | 1.0 | 39 | $2.58 | $18.08 | — | — |
| typescript-bun | opus48-1m-high | 2 | 7.2min | 5.4min | 0.5 | 39 | $2.15 | $4.31 | — | — |
| typescript-bun | opus48-1m-medium* | 6 | 11.8min | 11.8min | 0.8 | 46 | $2.76 | $16.56 | — | — |


<details>
<summary>Sorted by avg cost (cheapest first)</summary>

| Language | Model | Runs | Avg Duration | Avg Duration Net of Traps | Avg Errors | Avg Turns | Avg Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| powershell | opus48-1m-medium | 7 | 7.8min | 7.8min | 0.1 | 28 | $1.75 | $12.23 | — | — |
| typescript-bun | opus48-1m-high | 2 | 7.2min | 5.4min | 0.5 | 39 | $2.15 | $4.31 | — | — |
| default | opus48-1m-medium | 7 | 9.5min | 9.5min | 0.3 | 33 | $2.34 | $16.35 | — | — |
| default | opus48-1m-high | 3 | 8.6min | 7.9min | 0.3 | 37 | $2.48 | $7.44 | — | — |
| powershell-tool | opus48-1m-high | 2 | 11.7min | 10.3min | 0.0 | 38 | $2.55 | $5.10 | — | — |
| bash | opus48-1m-medium | 7 | 12.1min | 12.1min | 1.4 | 35 | $2.56 | $17.91 | — | — |
| bash | opus48-1m-high | 2 | 9.8min | 6.8min | 0.5 | 36 | $2.57 | $5.15 | — | — |
| powershell-tool | opus48-1m-medium | 7 | 10.3min | 10.3min | 1.0 | 39 | $2.58 | $18.08 | — | — |
| typescript-bun | opus48-1m-medium* | 6 | 11.8min | 11.8min | 0.8 | 46 | $2.76 | $16.56 | — | — |
| powershell | opus48-1m-high | 2 | 14.0min | 9.2min | 1.0 | 54 | $3.12 | $6.24 | — | — |

</details>

<details>
<summary>Sorted by avg duration (fastest first)</summary>

| Language | Model | Runs | Avg Duration | Avg Duration Net of Traps | Avg Errors | Avg Turns | Avg Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| typescript-bun | opus48-1m-high | 2 | 7.2min | 5.4min | 0.5 | 39 | $2.15 | $4.31 | — | — |
| powershell | opus48-1m-medium | 7 | 7.8min | 7.8min | 0.1 | 28 | $1.75 | $12.23 | — | — |
| default | opus48-1m-high | 3 | 8.6min | 7.9min | 0.3 | 37 | $2.48 | $7.44 | — | — |
| default | opus48-1m-medium | 7 | 9.5min | 9.5min | 0.3 | 33 | $2.34 | $16.35 | — | — |
| bash | opus48-1m-high | 2 | 9.8min | 6.8min | 0.5 | 36 | $2.57 | $5.15 | — | — |
| powershell-tool | opus48-1m-medium | 7 | 10.3min | 10.3min | 1.0 | 39 | $2.58 | $18.08 | — | — |
| powershell-tool | opus48-1m-high | 2 | 11.7min | 10.3min | 0.0 | 38 | $2.55 | $5.10 | — | — |
| typescript-bun | opus48-1m-medium* | 6 | 11.8min | 11.8min | 0.8 | 46 | $2.76 | $16.56 | — | — |
| bash | opus48-1m-medium | 7 | 12.1min | 12.1min | 1.4 | 35 | $2.56 | $17.91 | — | — |
| powershell | opus48-1m-high | 2 | 14.0min | 9.2min | 1.0 | 54 | $3.12 | $6.24 | — | — |

</details>

<details>
<summary>Sorted by avg duration net of traps (fastest first)</summary>

| Language | Model | Runs | Avg Duration | Avg Duration Net of Traps | Avg Errors | Avg Turns | Avg Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| typescript-bun | opus48-1m-high | 2 | 7.2min | 5.4min | 0.5 | 39 | $2.15 | $4.31 | — | — |
| bash | opus48-1m-high | 2 | 9.8min | 6.8min | 0.5 | 36 | $2.57 | $5.15 | — | — |
| powershell | opus48-1m-medium | 7 | 7.8min | 7.8min | 0.1 | 28 | $1.75 | $12.23 | — | — |
| default | opus48-1m-high | 3 | 8.6min | 7.9min | 0.3 | 37 | $2.48 | $7.44 | — | — |
| powershell | opus48-1m-high | 2 | 14.0min | 9.2min | 1.0 | 54 | $3.12 | $6.24 | — | — |
| default | opus48-1m-medium | 7 | 9.5min | 9.5min | 0.3 | 33 | $2.34 | $16.35 | — | — |
| powershell-tool | opus48-1m-medium | 7 | 10.3min | 10.3min | 1.0 | 39 | $2.58 | $18.08 | — | — |
| powershell-tool | opus48-1m-high | 2 | 11.7min | 10.3min | 0.0 | 38 | $2.55 | $5.10 | — | — |
| typescript-bun | opus48-1m-medium* | 6 | 11.8min | 11.8min | 0.8 | 46 | $2.76 | $16.56 | — | — |
| bash | opus48-1m-medium | 7 | 12.1min | 12.1min | 1.4 | 35 | $2.56 | $17.91 | — | — |

</details>

<details>
<summary>Sorted by avg errors (fewest first)</summary>

| Language | Model | Runs | Avg Duration | Avg Duration Net of Traps | Avg Errors | Avg Turns | Avg Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| powershell-tool | opus48-1m-high | 2 | 11.7min | 10.3min | 0.0 | 38 | $2.55 | $5.10 | — | — |
| powershell | opus48-1m-medium | 7 | 7.8min | 7.8min | 0.1 | 28 | $1.75 | $12.23 | — | — |
| default | opus48-1m-medium | 7 | 9.5min | 9.5min | 0.3 | 33 | $2.34 | $16.35 | — | — |
| default | opus48-1m-high | 3 | 8.6min | 7.9min | 0.3 | 37 | $2.48 | $7.44 | — | — |
| bash | opus48-1m-high | 2 | 9.8min | 6.8min | 0.5 | 36 | $2.57 | $5.15 | — | — |
| typescript-bun | opus48-1m-high | 2 | 7.2min | 5.4min | 0.5 | 39 | $2.15 | $4.31 | — | — |
| typescript-bun | opus48-1m-medium* | 6 | 11.8min | 11.8min | 0.8 | 46 | $2.76 | $16.56 | — | — |
| powershell | opus48-1m-high | 2 | 14.0min | 9.2min | 1.0 | 54 | $3.12 | $6.24 | — | — |
| powershell-tool | opus48-1m-medium | 7 | 10.3min | 10.3min | 1.0 | 39 | $2.58 | $18.08 | — | — |
| bash | opus48-1m-medium | 7 | 12.1min | 12.1min | 1.4 | 35 | $2.56 | $17.91 | — | — |

</details>

<details>
<summary>Sorted by avg turns (fewest first)</summary>

| Language | Model | Runs | Avg Duration | Avg Duration Net of Traps | Avg Errors | Avg Turns | Avg Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| powershell | opus48-1m-medium | 7 | 7.8min | 7.8min | 0.1 | 28 | $1.75 | $12.23 | — | — |
| default | opus48-1m-medium | 7 | 9.5min | 9.5min | 0.3 | 33 | $2.34 | $16.35 | — | — |
| bash | opus48-1m-medium | 7 | 12.1min | 12.1min | 1.4 | 35 | $2.56 | $17.91 | — | — |
| bash | opus48-1m-high | 2 | 9.8min | 6.8min | 0.5 | 36 | $2.57 | $5.15 | — | — |
| default | opus48-1m-high | 3 | 8.6min | 7.9min | 0.3 | 37 | $2.48 | $7.44 | — | — |
| powershell-tool | opus48-1m-high | 2 | 11.7min | 10.3min | 0.0 | 38 | $2.55 | $5.10 | — | — |
| powershell-tool | opus48-1m-medium | 7 | 10.3min | 10.3min | 1.0 | 39 | $2.58 | $18.08 | — | — |
| typescript-bun | opus48-1m-high | 2 | 7.2min | 5.4min | 0.5 | 39 | $2.15 | $4.31 | — | — |
| typescript-bun | opus48-1m-medium* | 6 | 11.8min | 11.8min | 0.8 | 46 | $2.76 | $16.56 | — | — |
| powershell | opus48-1m-high | 2 | 14.0min | 9.2min | 1.0 | 54 | $3.12 | $6.24 | — | — |

</details>

<details>
<summary>Sorted by LLM-as-judge score (best first)</summary>

| Language | Model | Runs | Avg Duration | Avg Duration Net of Traps | Avg Errors | Avg Turns | Avg Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| bash | opus48-1m-high | 2 | 9.8min | 6.8min | 0.5 | 36 | $2.57 | $5.15 | — | — |
| bash | opus48-1m-medium | 7 | 12.1min | 12.1min | 1.4 | 35 | $2.56 | $17.91 | — | — |
| default | opus48-1m-high | 3 | 8.6min | 7.9min | 0.3 | 37 | $2.48 | $7.44 | — | — |
| default | opus48-1m-medium | 7 | 9.5min | 9.5min | 0.3 | 33 | $2.34 | $16.35 | — | — |
| powershell | opus48-1m-high | 2 | 14.0min | 9.2min | 1.0 | 54 | $3.12 | $6.24 | — | — |
| powershell | opus48-1m-medium | 7 | 7.8min | 7.8min | 0.1 | 28 | $1.75 | $12.23 | — | — |
| powershell-tool | opus48-1m-high | 2 | 11.7min | 10.3min | 0.0 | 38 | $2.55 | $5.10 | — | — |
| powershell-tool | opus48-1m-medium | 7 | 10.3min | 10.3min | 1.0 | 39 | $2.58 | $18.08 | — | — |
| typescript-bun | opus48-1m-high | 2 | 7.2min | 5.4min | 0.5 | 39 | $2.15 | $4.31 | — | — |
| typescript-bun | opus48-1m-medium* | 6 | 11.8min | 11.8min | 0.8 | 46 | $2.76 | $16.56 | — | — |

</details>

<details>
<summary>Sorted by deliverable-quality score (best first)</summary>

| Language | Model | Runs | Avg Duration | Avg Duration Net of Traps | Avg Errors | Avg Turns | Avg Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| bash | opus48-1m-high | 2 | 9.8min | 6.8min | 0.5 | 36 | $2.57 | $5.15 | — | — |
| bash | opus48-1m-medium | 7 | 12.1min | 12.1min | 1.4 | 35 | $2.56 | $17.91 | — | — |
| default | opus48-1m-high | 3 | 8.6min | 7.9min | 0.3 | 37 | $2.48 | $7.44 | — | — |
| default | opus48-1m-medium | 7 | 9.5min | 9.5min | 0.3 | 33 | $2.34 | $16.35 | — | — |
| powershell | opus48-1m-high | 2 | 14.0min | 9.2min | 1.0 | 54 | $3.12 | $6.24 | — | — |
| powershell | opus48-1m-medium | 7 | 7.8min | 7.8min | 0.1 | 28 | $1.75 | $12.23 | — | — |
| powershell-tool | opus48-1m-high | 2 | 11.7min | 10.3min | 0.0 | 38 | $2.55 | $5.10 | — | — |
| powershell-tool | opus48-1m-medium | 7 | 10.3min | 10.3min | 1.0 | 39 | $2.58 | $18.08 | — | — |
| typescript-bun | opus48-1m-high | 2 | 7.2min | 5.4min | 0.5 | 39 | $2.15 | $4.31 | — | — |
| typescript-bun | opus48-1m-medium* | 6 | 11.8min | 11.8min | 0.8 | 46 | $2.76 | $16.56 | — | — |

</details>

## Savings Analysis

### Hook Savings by Language/Model/Effort

Each hook-caught error avoids one test run that would otherwise have been needed to discover it.
Every hook fire (hit or miss) costs execution time for the syntax/type checker.

*`% of Test Time Saved` = `net / (net + test_time) × 100` — the share of total (would-have-been + actually-spent) test time that hooks eliminated. Bounded in (-∞, 100%) without an artificial cap; near 100% means hooks substituted for almost all of the hypothetical test work.*

| Language | Model | Fires | Caught | Rate | Gross Saved | % of Time | Overhead | % of Time | Net Saved | % of Time | Test Run Time | % of Test Time Saved |
|------|-------|-------|--------|------|------------|-----------|----------|-----------|-----------|-----------|---------------|----------------------|
| bash | opus48-1m-high-cli2.1.195 | 26 | 1 | 3.8% | 0.2min | 0.0% | 0.0min | 0.0% | 0.2min | 0.0% | 1.8min | 9.3% |
| bash | opus48-1m-medium-cli2.1.193 | 51 | 1 | 2.0% | 0.2min | 0.0% | 0.0min | 0.0% | 0.2min | 0.0% | 0.7min | 20.5% |
| bash | opus48-1m-medium-cli2.1.195 | 28 | 1 | 3.6% | 0.2min | 0.0% | 0.0min | 0.0% | 0.2min | 0.0% | 19.4min | 0.8% |
| default | opus48-1m-high-cli2.1.195 | 57 | 1 | 1.8% | 0.1min | 0.0% | 0.1min | 0.0% | 0.0min | 0.0% | 1.5min | 2.5% |
| default | opus48-1m-medium-cli2.1.193 | 68 | 0 | 0.0% | 0.0min | 0.0% | 0.2min | 0.0% | -0.2min | -0.0% | 4.0min | -3.9% |
| default | opus48-1m-medium-cli2.1.195 | 30 | 0 | 0.0% | 0.0min | 0.0% | 0.1min | 0.0% | -0.1min | -0.0% | 5.6min | -1.0% |
| powershell | opus48-1m-high-cli2.1.195 | 47 | 0 | 0.0% | 0.0min | 0.0% | 0.8min | 0.2% | -0.8min | -0.2% | 6.3min | -14.0% |
| powershell | opus48-1m-medium-cli2.1.193 | 70 | 0 | 0.0% | 0.0min | 0.0% | 0.7min | 0.1% | -0.7min | -0.1% | 4.3min | -19.8% |
| powershell | opus48-1m-medium-cli2.1.195 | 17 | 0 | 0.0% | 0.0min | 0.0% | 0.5min | 0.1% | -0.5min | -0.1% | 3.3min | -17.9% |
| powershell-tool | opus48-1m-high-cli2.1.195 | 37 | 0 | 0.0% | 0.0min | 0.0% | 0.3min | 0.1% | -0.3min | -0.1% | 5.4min | -6.6% |
| powershell-tool | opus48-1m-medium-cli2.1.193 | 62 | 0 | 0.0% | 0.0min | 0.0% | 0.3min | 0.1% | -0.3min | -0.1% | 3.6min | -8.2% |
| powershell-tool | opus48-1m-medium-cli2.1.195 | 39 | 0 | 0.0% | 0.0min | 0.0% | 0.3min | 0.1% | -0.3min | -0.1% | 2.6min | -12.0% |
| typescript-bun | opus48-1m-high-cli2.1.195 | 34 | 13 | 38.2% | 1.7min | 0.4% | 0.2min | 0.0% | 1.5min | 0.3% | 1.3min | 53.4% |
| typescript-bun | opus48-1m-medium-cli2.1.193 | 95 | 40 | 42.1% | 5.3min | 1.1% | 1.4min | 0.3% | 3.9min | 0.8% | 4.0min | 49.5% |
| typescript-bun | opus48-1m-medium-cli2.1.195 | 42 | 14 | 33.3% | 1.9min | 0.4% | 1.5min | 0.3% | 0.3min | 0.1% | 10.4min | 3.3% |


<details>
<summary>Sorted by net saved (most first)</summary>

| Language | Model | Fires | Caught | Rate | Gross Saved | % of Time | Overhead | % of Time | Net Saved | % of Time | Test Run Time | % of Test Time Saved |
|------|-------|-------|--------|------|------------|-----------|----------|-----------|-----------|-----------|---------------|----------------------|
| typescript-bun | opus48-1m-medium-cli2.1.193 | 95 | 40 | 42.1% | 5.3min | 1.1% | 1.4min | 0.3% | 3.9min | 0.8% | 4.0min | 49.5% |
| typescript-bun | opus48-1m-high-cli2.1.195 | 34 | 13 | 38.2% | 1.7min | 0.4% | 0.2min | 0.0% | 1.5min | 0.3% | 1.3min | 53.4% |
| typescript-bun | opus48-1m-medium-cli2.1.195 | 42 | 14 | 33.3% | 1.9min | 0.4% | 1.5min | 0.3% | 0.3min | 0.1% | 10.4min | 3.3% |
| bash | opus48-1m-medium-cli2.1.193 | 51 | 1 | 2.0% | 0.2min | 0.0% | 0.0min | 0.0% | 0.2min | 0.0% | 0.7min | 20.5% |
| bash | opus48-1m-high-cli2.1.195 | 26 | 1 | 3.8% | 0.2min | 0.0% | 0.0min | 0.0% | 0.2min | 0.0% | 1.8min | 9.3% |
| bash | opus48-1m-medium-cli2.1.195 | 28 | 1 | 3.6% | 0.2min | 0.0% | 0.0min | 0.0% | 0.2min | 0.0% | 19.4min | 0.8% |
| default | opus48-1m-high-cli2.1.195 | 57 | 1 | 1.8% | 0.1min | 0.0% | 0.1min | 0.0% | 0.0min | 0.0% | 1.5min | 2.5% |
| default | opus48-1m-medium-cli2.1.195 | 30 | 0 | 0.0% | 0.0min | 0.0% | 0.1min | 0.0% | -0.1min | -0.0% | 5.6min | -1.0% |
| default | opus48-1m-medium-cli2.1.193 | 68 | 0 | 0.0% | 0.0min | 0.0% | 0.2min | 0.0% | -0.2min | -0.0% | 4.0min | -3.9% |
| powershell-tool | opus48-1m-medium-cli2.1.193 | 62 | 0 | 0.0% | 0.0min | 0.0% | 0.3min | 0.1% | -0.3min | -0.1% | 3.6min | -8.2% |
| powershell-tool | opus48-1m-medium-cli2.1.195 | 39 | 0 | 0.0% | 0.0min | 0.0% | 0.3min | 0.1% | -0.3min | -0.1% | 2.6min | -12.0% |
| powershell-tool | opus48-1m-high-cli2.1.195 | 37 | 0 | 0.0% | 0.0min | 0.0% | 0.3min | 0.1% | -0.3min | -0.1% | 5.4min | -6.6% |
| powershell | opus48-1m-medium-cli2.1.195 | 17 | 0 | 0.0% | 0.0min | 0.0% | 0.5min | 0.1% | -0.5min | -0.1% | 3.3min | -17.9% |
| powershell | opus48-1m-medium-cli2.1.193 | 70 | 0 | 0.0% | 0.0min | 0.0% | 0.7min | 0.1% | -0.7min | -0.1% | 4.3min | -19.8% |
| powershell | opus48-1m-high-cli2.1.195 | 47 | 0 | 0.0% | 0.0min | 0.0% | 0.8min | 0.2% | -0.8min | -0.2% | 6.3min | -14.0% |

</details>

<details>
<summary>Sorted by net % of test time saved (most first)</summary>

| Language | Model | Fires | Caught | Rate | Gross Saved | % of Time | Overhead | % of Time | Net Saved | % of Time | Test Run Time | % of Test Time Saved |
|------|-------|-------|--------|------|------------|-----------|----------|-----------|-----------|-----------|---------------|----------------------|
| typescript-bun | opus48-1m-high-cli2.1.195 | 34 | 13 | 38.2% | 1.7min | 0.4% | 0.2min | 0.0% | 1.5min | 0.3% | 1.3min | 53.4% |
| typescript-bun | opus48-1m-medium-cli2.1.193 | 95 | 40 | 42.1% | 5.3min | 1.1% | 1.4min | 0.3% | 3.9min | 0.8% | 4.0min | 49.5% |
| bash | opus48-1m-medium-cli2.1.193 | 51 | 1 | 2.0% | 0.2min | 0.0% | 0.0min | 0.0% | 0.2min | 0.0% | 0.7min | 20.5% |
| bash | opus48-1m-high-cli2.1.195 | 26 | 1 | 3.8% | 0.2min | 0.0% | 0.0min | 0.0% | 0.2min | 0.0% | 1.8min | 9.3% |
| typescript-bun | opus48-1m-medium-cli2.1.195 | 42 | 14 | 33.3% | 1.9min | 0.4% | 1.5min | 0.3% | 0.3min | 0.1% | 10.4min | 3.3% |
| default | opus48-1m-high-cli2.1.195 | 57 | 1 | 1.8% | 0.1min | 0.0% | 0.1min | 0.0% | 0.0min | 0.0% | 1.5min | 2.5% |
| bash | opus48-1m-medium-cli2.1.195 | 28 | 1 | 3.6% | 0.2min | 0.0% | 0.0min | 0.0% | 0.2min | 0.0% | 19.4min | 0.8% |
| default | opus48-1m-medium-cli2.1.195 | 30 | 0 | 0.0% | 0.0min | 0.0% | 0.1min | 0.0% | -0.1min | -0.0% | 5.6min | -1.0% |
| default | opus48-1m-medium-cli2.1.193 | 68 | 0 | 0.0% | 0.0min | 0.0% | 0.2min | 0.0% | -0.2min | -0.0% | 4.0min | -3.9% |
| powershell-tool | opus48-1m-high-cli2.1.195 | 37 | 0 | 0.0% | 0.0min | 0.0% | 0.3min | 0.1% | -0.3min | -0.1% | 5.4min | -6.6% |
| powershell-tool | opus48-1m-medium-cli2.1.193 | 62 | 0 | 0.0% | 0.0min | 0.0% | 0.3min | 0.1% | -0.3min | -0.1% | 3.6min | -8.2% |
| powershell-tool | opus48-1m-medium-cli2.1.195 | 39 | 0 | 0.0% | 0.0min | 0.0% | 0.3min | 0.1% | -0.3min | -0.1% | 2.6min | -12.0% |
| powershell | opus48-1m-high-cli2.1.195 | 47 | 0 | 0.0% | 0.0min | 0.0% | 0.8min | 0.2% | -0.8min | -0.2% | 6.3min | -14.0% |
| powershell | opus48-1m-medium-cli2.1.195 | 17 | 0 | 0.0% | 0.0min | 0.0% | 0.5min | 0.1% | -0.5min | -0.1% | 3.3min | -17.9% |
| powershell | opus48-1m-medium-cli2.1.193 | 70 | 0 | 0.0% | 0.0min | 0.0% | 0.7min | 0.1% | -0.7min | -0.1% | 4.3min | -19.8% |

</details>

<details>
<summary>Sorted by catch rate (highest first)</summary>

| Language | Model | Fires | Caught | Rate | Gross Saved | % of Time | Overhead | % of Time | Net Saved | % of Time | Test Run Time | % of Test Time Saved |
|------|-------|-------|--------|------|------------|-----------|----------|-----------|-----------|-----------|---------------|----------------------|
| typescript-bun | opus48-1m-medium-cli2.1.193 | 95 | 40 | 42.1% | 5.3min | 1.1% | 1.4min | 0.3% | 3.9min | 0.8% | 4.0min | 49.5% |
| typescript-bun | opus48-1m-high-cli2.1.195 | 34 | 13 | 38.2% | 1.7min | 0.4% | 0.2min | 0.0% | 1.5min | 0.3% | 1.3min | 53.4% |
| typescript-bun | opus48-1m-medium-cli2.1.195 | 42 | 14 | 33.3% | 1.9min | 0.4% | 1.5min | 0.3% | 0.3min | 0.1% | 10.4min | 3.3% |
| bash | opus48-1m-high-cli2.1.195 | 26 | 1 | 3.8% | 0.2min | 0.0% | 0.0min | 0.0% | 0.2min | 0.0% | 1.8min | 9.3% |
| bash | opus48-1m-medium-cli2.1.195 | 28 | 1 | 3.6% | 0.2min | 0.0% | 0.0min | 0.0% | 0.2min | 0.0% | 19.4min | 0.8% |
| bash | opus48-1m-medium-cli2.1.193 | 51 | 1 | 2.0% | 0.2min | 0.0% | 0.0min | 0.0% | 0.2min | 0.0% | 0.7min | 20.5% |
| default | opus48-1m-high-cli2.1.195 | 57 | 1 | 1.8% | 0.1min | 0.0% | 0.1min | 0.0% | 0.0min | 0.0% | 1.5min | 2.5% |
| default | opus48-1m-medium-cli2.1.193 | 68 | 0 | 0.0% | 0.0min | 0.0% | 0.2min | 0.0% | -0.2min | -0.0% | 4.0min | -3.9% |
| default | opus48-1m-medium-cli2.1.195 | 30 | 0 | 0.0% | 0.0min | 0.0% | 0.1min | 0.0% | -0.1min | -0.0% | 5.6min | -1.0% |
| powershell | opus48-1m-high-cli2.1.195 | 47 | 0 | 0.0% | 0.0min | 0.0% | 0.8min | 0.2% | -0.8min | -0.2% | 6.3min | -14.0% |
| powershell | opus48-1m-medium-cli2.1.193 | 70 | 0 | 0.0% | 0.0min | 0.0% | 0.7min | 0.1% | -0.7min | -0.1% | 4.3min | -19.8% |
| powershell | opus48-1m-medium-cli2.1.195 | 17 | 0 | 0.0% | 0.0min | 0.0% | 0.5min | 0.1% | -0.5min | -0.1% | 3.3min | -17.9% |
| powershell-tool | opus48-1m-high-cli2.1.195 | 37 | 0 | 0.0% | 0.0min | 0.0% | 0.3min | 0.1% | -0.3min | -0.1% | 5.4min | -6.6% |
| powershell-tool | opus48-1m-medium-cli2.1.193 | 62 | 0 | 0.0% | 0.0min | 0.0% | 0.3min | 0.1% | -0.3min | -0.1% | 3.6min | -8.2% |
| powershell-tool | opus48-1m-medium-cli2.1.195 | 39 | 0 | 0.0% | 0.0min | 0.0% | 0.3min | 0.1% | -0.3min | -0.1% | 2.6min | -12.0% |

</details>

### Trap Analysis by Language/Model/Effort/Category

| Trap | Language | Model | Fell In | Time Lost | % of Time | $ Lost | % of $ |
|------|------|-------|---------|-----------|-----------|--------|--------|
| repeated-test-reruns | bash | opus48-1m-high-cli2.1.195 | 2 | 4.7min | 0.9% | $1.26 | 1.15% |
| repeated-test-reruns | bash | opus48-1m-medium-cli2.1.193 | 3 | 4.0min | 0.8% | $1.08 | 0.98% |
| repeated-test-reruns | bash | opus48-1m-medium-cli2.1.195 | 2 | 7.7min | 1.6% | $1.32 | 1.20% |
| repeated-test-reruns | default | opus48-1m-high-cli2.1.195 | 1 | 2.3min | 0.5% | $0.58 | 0.53% |
| repeated-test-reruns | default | opus48-1m-medium-cli2.1.193 | 4 | 5.7min | 1.2% | $1.34 | 1.23% |
| repeated-test-reruns | default | opus48-1m-medium-cli2.1.195 | 2 | 3.3min | 0.7% | $0.72 | 0.66% |
| repeated-test-reruns | powershell | opus48-1m-high-cli2.1.195 | 2 | 9.0min | 1.8% | $2.00 | 1.83% |
| repeated-test-reruns | powershell | opus48-1m-medium-cli2.1.193 | 2 | 2.7min | 0.5% | $0.66 | 0.61% |
| repeated-test-reruns | powershell-tool | opus48-1m-high-cli2.1.195 | 1 | 2.3min | 0.5% | $0.57 | 0.52% |
| repeated-test-reruns | powershell-tool | opus48-1m-medium-cli2.1.193 | 2 | 3.3min | 0.7% | $0.78 | 0.71% |
| repeated-test-reruns | powershell-tool | opus48-1m-medium-cli2.1.195 | 2 | 1.3min | 0.3% | $0.34 | 0.31% |
| repeated-test-reruns | typescript-bun | opus48-1m-high-cli2.1.195 | 1 | 1.0min | 0.2% | $0.27 | 0.25% |
| repeated-test-reruns | typescript-bun | opus48-1m-medium-cli2.1.193 | 4 | 8.7min | 1.8% | $2.26 | 2.06% |
| repeated-test-reruns | typescript-bun | opus48-1m-medium-cli2.1.195 | 3 | 2.3min | 0.5% | $0.30 | 0.27% |
| ts-type-error-fix-cycles | typescript-bun | opus48-1m-high-cli2.1.195 | 2 | 2.6min | 0.5% | $0.76 | 0.69% |
| ts-type-error-fix-cycles | typescript-bun | opus48-1m-medium-cli2.1.193 | 3 | 8.0min | 1.6% | $2.17 | 1.98% |
| ts-type-error-fix-cycles | typescript-bun | opus48-1m-medium-cli2.1.195 | 1 | 2.8min | 0.6% | $0.60 | 0.55% |
| fixture-rework | bash | opus48-1m-high-cli2.1.195 | 2 | 1.2min | 0.3% | $0.33 | 0.31% |
| fixture-rework | bash | opus48-1m-medium-cli2.1.193 | 2 | 1.5min | 0.3% | $0.41 | 0.37% |
| fixture-rework | bash | opus48-1m-medium-cli2.1.195 | 2 | 3.8min | 0.8% | $0.82 | 0.75% |
| fixture-rework | default | opus48-1m-medium-cli2.1.193 | 1 | 0.8min | 0.2% | $0.22 | 0.20% |
| fixture-rework | default | opus48-1m-medium-cli2.1.195 | 1 | 1.5min | 0.3% | $0.41 | 0.38% |
| fixture-rework | powershell | opus48-1m-high-cli2.1.195 | 1 | 0.5min | 0.1% | $0.11 | 0.10% |
| fixture-rework | powershell | opus48-1m-medium-cli2.1.193 | 1 | 0.5min | 0.1% | $0.12 | 0.11% |
| fixture-rework | powershell-tool | opus48-1m-high-cli2.1.195 | 1 | 0.5min | 0.1% | $0.12 | 0.11% |
| fixture-rework | powershell-tool | opus48-1m-medium-cli2.1.193 | 1 | 1.0min | 0.2% | $0.27 | 0.24% |
| fixture-rework | powershell-tool | opus48-1m-medium-cli2.1.195 | 1 | 0.8min | 0.2% | $0.18 | 0.16% |
| actionlint-fix-cycles | powershell-tool | opus48-1m-medium-cli2.1.193 | 1 | 1.0min | 0.2% | $0.27 | 0.24% |
| act-push-debug-loops | bash | opus48-1m-medium-cli2.1.195 | 1 | 0.8min | 0.2% | $0.12 | 0.11% |


<details>
<summary>Sorted by time lost (least first)</summary>

| Trap | Language | Model | Fell In | Time Lost | % of Time | $ Lost | % of $ |
|------|------|-------|---------|-----------|-----------|--------|--------|
| fixture-rework | powershell | opus48-1m-high-cli2.1.195 | 1 | 0.5min | 0.1% | $0.11 | 0.10% |
| fixture-rework | powershell | opus48-1m-medium-cli2.1.193 | 1 | 0.5min | 0.1% | $0.12 | 0.11% |
| fixture-rework | powershell-tool | opus48-1m-high-cli2.1.195 | 1 | 0.5min | 0.1% | $0.12 | 0.11% |
| fixture-rework | default | opus48-1m-medium-cli2.1.193 | 1 | 0.8min | 0.2% | $0.22 | 0.20% |
| fixture-rework | powershell-tool | opus48-1m-medium-cli2.1.195 | 1 | 0.8min | 0.2% | $0.18 | 0.16% |
| act-push-debug-loops | bash | opus48-1m-medium-cli2.1.195 | 1 | 0.8min | 0.2% | $0.12 | 0.11% |
| repeated-test-reruns | typescript-bun | opus48-1m-high-cli2.1.195 | 1 | 1.0min | 0.2% | $0.27 | 0.25% |
| fixture-rework | powershell-tool | opus48-1m-medium-cli2.1.193 | 1 | 1.0min | 0.2% | $0.27 | 0.24% |
| actionlint-fix-cycles | powershell-tool | opus48-1m-medium-cli2.1.193 | 1 | 1.0min | 0.2% | $0.27 | 0.24% |
| fixture-rework | bash | opus48-1m-high-cli2.1.195 | 2 | 1.2min | 0.3% | $0.33 | 0.31% |
| repeated-test-reruns | powershell-tool | opus48-1m-medium-cli2.1.195 | 2 | 1.3min | 0.3% | $0.34 | 0.31% |
| fixture-rework | bash | opus48-1m-medium-cli2.1.193 | 2 | 1.5min | 0.3% | $0.41 | 0.37% |
| fixture-rework | default | opus48-1m-medium-cli2.1.195 | 1 | 1.5min | 0.3% | $0.41 | 0.38% |
| repeated-test-reruns | default | opus48-1m-high-cli2.1.195 | 1 | 2.3min | 0.5% | $0.58 | 0.53% |
| repeated-test-reruns | powershell-tool | opus48-1m-high-cli2.1.195 | 1 | 2.3min | 0.5% | $0.57 | 0.52% |
| repeated-test-reruns | typescript-bun | opus48-1m-medium-cli2.1.195 | 3 | 2.3min | 0.5% | $0.30 | 0.27% |
| ts-type-error-fix-cycles | typescript-bun | opus48-1m-high-cli2.1.195 | 2 | 2.6min | 0.5% | $0.76 | 0.69% |
| repeated-test-reruns | powershell | opus48-1m-medium-cli2.1.193 | 2 | 2.7min | 0.5% | $0.66 | 0.61% |
| ts-type-error-fix-cycles | typescript-bun | opus48-1m-medium-cli2.1.195 | 1 | 2.8min | 0.6% | $0.60 | 0.55% |
| repeated-test-reruns | default | opus48-1m-medium-cli2.1.195 | 2 | 3.3min | 0.7% | $0.72 | 0.66% |
| repeated-test-reruns | powershell-tool | opus48-1m-medium-cli2.1.193 | 2 | 3.3min | 0.7% | $0.78 | 0.71% |
| fixture-rework | bash | opus48-1m-medium-cli2.1.195 | 2 | 3.8min | 0.8% | $0.82 | 0.75% |
| repeated-test-reruns | bash | opus48-1m-medium-cli2.1.193 | 3 | 4.0min | 0.8% | $1.08 | 0.98% |
| repeated-test-reruns | bash | opus48-1m-high-cli2.1.195 | 2 | 4.7min | 0.9% | $1.26 | 1.15% |
| repeated-test-reruns | default | opus48-1m-medium-cli2.1.193 | 4 | 5.7min | 1.2% | $1.34 | 1.23% |
| repeated-test-reruns | bash | opus48-1m-medium-cli2.1.195 | 2 | 7.7min | 1.6% | $1.32 | 1.20% |
| ts-type-error-fix-cycles | typescript-bun | opus48-1m-medium-cli2.1.193 | 3 | 8.0min | 1.6% | $2.17 | 1.98% |
| repeated-test-reruns | typescript-bun | opus48-1m-medium-cli2.1.193 | 4 | 8.7min | 1.8% | $2.26 | 2.06% |
| repeated-test-reruns | powershell | opus48-1m-high-cli2.1.195 | 2 | 9.0min | 1.8% | $2.00 | 1.83% |

</details>

<details>
<summary>Sorted by $ lost (least first)</summary>

| Trap | Language | Model | Fell In | Time Lost | % of Time | $ Lost | % of $ |
|------|------|-------|---------|-----------|-----------|--------|--------|
| fixture-rework | powershell | opus48-1m-high-cli2.1.195 | 1 | 0.5min | 0.1% | $0.11 | 0.10% |
| fixture-rework | powershell | opus48-1m-medium-cli2.1.193 | 1 | 0.5min | 0.1% | $0.12 | 0.11% |
| act-push-debug-loops | bash | opus48-1m-medium-cli2.1.195 | 1 | 0.8min | 0.2% | $0.12 | 0.11% |
| fixture-rework | powershell-tool | opus48-1m-high-cli2.1.195 | 1 | 0.5min | 0.1% | $0.12 | 0.11% |
| fixture-rework | powershell-tool | opus48-1m-medium-cli2.1.195 | 1 | 0.8min | 0.2% | $0.18 | 0.16% |
| fixture-rework | default | opus48-1m-medium-cli2.1.193 | 1 | 0.8min | 0.2% | $0.22 | 0.20% |
| fixture-rework | powershell-tool | opus48-1m-medium-cli2.1.193 | 1 | 1.0min | 0.2% | $0.27 | 0.24% |
| actionlint-fix-cycles | powershell-tool | opus48-1m-medium-cli2.1.193 | 1 | 1.0min | 0.2% | $0.27 | 0.24% |
| repeated-test-reruns | typescript-bun | opus48-1m-high-cli2.1.195 | 1 | 1.0min | 0.2% | $0.27 | 0.25% |
| repeated-test-reruns | typescript-bun | opus48-1m-medium-cli2.1.195 | 3 | 2.3min | 0.5% | $0.30 | 0.27% |
| fixture-rework | bash | opus48-1m-high-cli2.1.195 | 2 | 1.2min | 0.3% | $0.33 | 0.31% |
| repeated-test-reruns | powershell-tool | opus48-1m-medium-cli2.1.195 | 2 | 1.3min | 0.3% | $0.34 | 0.31% |
| fixture-rework | bash | opus48-1m-medium-cli2.1.193 | 2 | 1.5min | 0.3% | $0.41 | 0.37% |
| fixture-rework | default | opus48-1m-medium-cli2.1.195 | 1 | 1.5min | 0.3% | $0.41 | 0.38% |
| repeated-test-reruns | powershell-tool | opus48-1m-high-cli2.1.195 | 1 | 2.3min | 0.5% | $0.57 | 0.52% |
| repeated-test-reruns | default | opus48-1m-high-cli2.1.195 | 1 | 2.3min | 0.5% | $0.58 | 0.53% |
| ts-type-error-fix-cycles | typescript-bun | opus48-1m-medium-cli2.1.195 | 1 | 2.8min | 0.6% | $0.60 | 0.55% |
| repeated-test-reruns | powershell | opus48-1m-medium-cli2.1.193 | 2 | 2.7min | 0.5% | $0.66 | 0.61% |
| repeated-test-reruns | default | opus48-1m-medium-cli2.1.195 | 2 | 3.3min | 0.7% | $0.72 | 0.66% |
| ts-type-error-fix-cycles | typescript-bun | opus48-1m-high-cli2.1.195 | 2 | 2.6min | 0.5% | $0.76 | 0.69% |
| repeated-test-reruns | powershell-tool | opus48-1m-medium-cli2.1.193 | 2 | 3.3min | 0.7% | $0.78 | 0.71% |
| fixture-rework | bash | opus48-1m-medium-cli2.1.195 | 2 | 3.8min | 0.8% | $0.82 | 0.75% |
| repeated-test-reruns | bash | opus48-1m-medium-cli2.1.193 | 3 | 4.0min | 0.8% | $1.08 | 0.98% |
| repeated-test-reruns | bash | opus48-1m-high-cli2.1.195 | 2 | 4.7min | 0.9% | $1.26 | 1.15% |
| repeated-test-reruns | bash | opus48-1m-medium-cli2.1.195 | 2 | 7.7min | 1.6% | $1.32 | 1.20% |
| repeated-test-reruns | default | opus48-1m-medium-cli2.1.193 | 4 | 5.7min | 1.2% | $1.34 | 1.23% |
| repeated-test-reruns | powershell | opus48-1m-high-cli2.1.195 | 2 | 9.0min | 1.8% | $2.00 | 1.83% |
| ts-type-error-fix-cycles | typescript-bun | opus48-1m-medium-cli2.1.193 | 3 | 8.0min | 1.6% | $2.17 | 1.98% |
| repeated-test-reruns | typescript-bun | opus48-1m-medium-cli2.1.193 | 4 | 8.7min | 1.8% | $2.26 | 2.06% |

</details>

<details>
<summary>Sorted by fell-in count (fewest first)</summary>

| Trap | Language | Model | Fell In | Time Lost | % of Time | $ Lost | % of $ |
|------|------|-------|---------|-----------|-----------|--------|--------|
| repeated-test-reruns | default | opus48-1m-high-cli2.1.195 | 1 | 2.3min | 0.5% | $0.58 | 0.53% |
| repeated-test-reruns | powershell-tool | opus48-1m-high-cli2.1.195 | 1 | 2.3min | 0.5% | $0.57 | 0.52% |
| repeated-test-reruns | typescript-bun | opus48-1m-high-cli2.1.195 | 1 | 1.0min | 0.2% | $0.27 | 0.25% |
| ts-type-error-fix-cycles | typescript-bun | opus48-1m-medium-cli2.1.195 | 1 | 2.8min | 0.6% | $0.60 | 0.55% |
| fixture-rework | default | opus48-1m-medium-cli2.1.193 | 1 | 0.8min | 0.2% | $0.22 | 0.20% |
| fixture-rework | default | opus48-1m-medium-cli2.1.195 | 1 | 1.5min | 0.3% | $0.41 | 0.38% |
| fixture-rework | powershell | opus48-1m-high-cli2.1.195 | 1 | 0.5min | 0.1% | $0.11 | 0.10% |
| fixture-rework | powershell | opus48-1m-medium-cli2.1.193 | 1 | 0.5min | 0.1% | $0.12 | 0.11% |
| fixture-rework | powershell-tool | opus48-1m-high-cli2.1.195 | 1 | 0.5min | 0.1% | $0.12 | 0.11% |
| fixture-rework | powershell-tool | opus48-1m-medium-cli2.1.193 | 1 | 1.0min | 0.2% | $0.27 | 0.24% |
| fixture-rework | powershell-tool | opus48-1m-medium-cli2.1.195 | 1 | 0.8min | 0.2% | $0.18 | 0.16% |
| actionlint-fix-cycles | powershell-tool | opus48-1m-medium-cli2.1.193 | 1 | 1.0min | 0.2% | $0.27 | 0.24% |
| act-push-debug-loops | bash | opus48-1m-medium-cli2.1.195 | 1 | 0.8min | 0.2% | $0.12 | 0.11% |
| repeated-test-reruns | bash | opus48-1m-high-cli2.1.195 | 2 | 4.7min | 0.9% | $1.26 | 1.15% |
| repeated-test-reruns | bash | opus48-1m-medium-cli2.1.195 | 2 | 7.7min | 1.6% | $1.32 | 1.20% |
| repeated-test-reruns | default | opus48-1m-medium-cli2.1.195 | 2 | 3.3min | 0.7% | $0.72 | 0.66% |
| repeated-test-reruns | powershell | opus48-1m-high-cli2.1.195 | 2 | 9.0min | 1.8% | $2.00 | 1.83% |
| repeated-test-reruns | powershell | opus48-1m-medium-cli2.1.193 | 2 | 2.7min | 0.5% | $0.66 | 0.61% |
| repeated-test-reruns | powershell-tool | opus48-1m-medium-cli2.1.193 | 2 | 3.3min | 0.7% | $0.78 | 0.71% |
| repeated-test-reruns | powershell-tool | opus48-1m-medium-cli2.1.195 | 2 | 1.3min | 0.3% | $0.34 | 0.31% |
| ts-type-error-fix-cycles | typescript-bun | opus48-1m-high-cli2.1.195 | 2 | 2.6min | 0.5% | $0.76 | 0.69% |
| fixture-rework | bash | opus48-1m-high-cli2.1.195 | 2 | 1.2min | 0.3% | $0.33 | 0.31% |
| fixture-rework | bash | opus48-1m-medium-cli2.1.193 | 2 | 1.5min | 0.3% | $0.41 | 0.37% |
| fixture-rework | bash | opus48-1m-medium-cli2.1.195 | 2 | 3.8min | 0.8% | $0.82 | 0.75% |
| repeated-test-reruns | bash | opus48-1m-medium-cli2.1.193 | 3 | 4.0min | 0.8% | $1.08 | 0.98% |
| repeated-test-reruns | typescript-bun | opus48-1m-medium-cli2.1.195 | 3 | 2.3min | 0.5% | $0.30 | 0.27% |
| ts-type-error-fix-cycles | typescript-bun | opus48-1m-medium-cli2.1.193 | 3 | 8.0min | 1.6% | $2.17 | 1.98% |
| repeated-test-reruns | default | opus48-1m-medium-cli2.1.193 | 4 | 5.7min | 1.2% | $1.34 | 1.23% |
| repeated-test-reruns | typescript-bun | opus48-1m-medium-cli2.1.193 | 4 | 8.7min | 1.8% | $2.26 | 2.06% |

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
| bash | opus48-1m-high-cli2.1.195 | 2 | 4 | 5.9min | 1.2% | $1.59 | 1.45% |
| bash | opus48-1m-medium-cli2.1.193 | 5 | 5 | 5.5min | 1.1% | $1.49 | 1.36% |
| bash | opus48-1m-medium-cli2.1.195 | 2 | 5 | 12.2min | 2.5% | $2.26 | 2.07% |
| default | opus48-1m-high-cli2.1.195 | 3 | 1 | 2.3min | 0.5% | $0.58 | 0.53% |
| default | opus48-1m-medium-cli2.1.193 | 5 | 5 | 6.4min | 1.3% | $1.57 | 1.43% |
| default | opus48-1m-medium-cli2.1.195 | 2 | 3 | 4.8min | 1.0% | $1.14 | 1.04% |
| powershell | opus48-1m-high-cli2.1.195 | 2 | 3 | 9.5min | 1.9% | $2.11 | 1.93% |
| powershell | opus48-1m-medium-cli2.1.193 | 5 | 3 | 3.2min | 0.6% | $0.78 | 0.71% |
| powershell | opus48-1m-medium-cli2.1.195 | 2 | 0 | 0.0min | 0.0% | $0.00 | 0.00% |
| powershell-tool | opus48-1m-high-cli2.1.195 | 2 | 2 | 2.8min | 0.6% | $0.69 | 0.63% |
| powershell-tool | opus48-1m-medium-cli2.1.193 | 4 | 4 | 5.3min | 1.1% | $1.31 | 1.20% |
| powershell-tool | opus48-1m-medium-cli2.1.195 | 3 | 3 | 2.1min | 0.4% | $0.52 | 0.47% |
| typescript-bun | opus48-1m-high-cli2.1.195 | 2 | 3 | 3.6min | 0.7% | $1.03 | 0.94% |
| typescript-bun | opus48-1m-medium-cli2.1.193 | 4 | 7 | 16.7min | 3.4% | $4.43 | 4.05% |
| typescript-bun | opus48-1m-medium-cli2.1.195 | 3 | 4 | 5.1min | 1.0% | $0.90 | 0.82% |


<details>
<summary>Sorted by time lost (least first)</summary>

| Language | Model | Runs | Traps | Time Lost | % of Time | $ Lost | % of $ |
|------|-------|------|-------|-----------|-----------|--------|--------|
| powershell | opus48-1m-medium-cli2.1.195 | 2 | 0 | 0.0min | 0.0% | $0.00 | 0.00% |
| powershell-tool | opus48-1m-medium-cli2.1.195 | 3 | 3 | 2.1min | 0.4% | $0.52 | 0.47% |
| default | opus48-1m-high-cli2.1.195 | 3 | 1 | 2.3min | 0.5% | $0.58 | 0.53% |
| powershell-tool | opus48-1m-high-cli2.1.195 | 2 | 2 | 2.8min | 0.6% | $0.69 | 0.63% |
| powershell | opus48-1m-medium-cli2.1.193 | 5 | 3 | 3.2min | 0.6% | $0.78 | 0.71% |
| typescript-bun | opus48-1m-high-cli2.1.195 | 2 | 3 | 3.6min | 0.7% | $1.03 | 0.94% |
| default | opus48-1m-medium-cli2.1.195 | 2 | 3 | 4.8min | 1.0% | $1.14 | 1.04% |
| typescript-bun | opus48-1m-medium-cli2.1.195 | 3 | 4 | 5.1min | 1.0% | $0.90 | 0.82% |
| powershell-tool | opus48-1m-medium-cli2.1.193 | 4 | 4 | 5.3min | 1.1% | $1.31 | 1.20% |
| bash | opus48-1m-medium-cli2.1.193 | 5 | 5 | 5.5min | 1.1% | $1.49 | 1.36% |
| bash | opus48-1m-high-cli2.1.195 | 2 | 4 | 5.9min | 1.2% | $1.59 | 1.45% |
| default | opus48-1m-medium-cli2.1.193 | 5 | 5 | 6.4min | 1.3% | $1.57 | 1.43% |
| powershell | opus48-1m-high-cli2.1.195 | 2 | 3 | 9.5min | 1.9% | $2.11 | 1.93% |
| bash | opus48-1m-medium-cli2.1.195 | 2 | 5 | 12.2min | 2.5% | $2.26 | 2.07% |
| typescript-bun | opus48-1m-medium-cli2.1.193 | 4 | 7 | 16.7min | 3.4% | $4.43 | 4.05% |

</details>

<details>
<summary>Sorted by $ lost (least first)</summary>

| Language | Model | Runs | Traps | Time Lost | % of Time | $ Lost | % of $ |
|------|-------|------|-------|-----------|-----------|--------|--------|
| powershell | opus48-1m-medium-cli2.1.195 | 2 | 0 | 0.0min | 0.0% | $0.00 | 0.00% |
| powershell-tool | opus48-1m-medium-cli2.1.195 | 3 | 3 | 2.1min | 0.4% | $0.52 | 0.47% |
| default | opus48-1m-high-cli2.1.195 | 3 | 1 | 2.3min | 0.5% | $0.58 | 0.53% |
| powershell-tool | opus48-1m-high-cli2.1.195 | 2 | 2 | 2.8min | 0.6% | $0.69 | 0.63% |
| powershell | opus48-1m-medium-cli2.1.193 | 5 | 3 | 3.2min | 0.6% | $0.78 | 0.71% |
| typescript-bun | opus48-1m-medium-cli2.1.195 | 3 | 4 | 5.1min | 1.0% | $0.90 | 0.82% |
| typescript-bun | opus48-1m-high-cli2.1.195 | 2 | 3 | 3.6min | 0.7% | $1.03 | 0.94% |
| default | opus48-1m-medium-cli2.1.195 | 2 | 3 | 4.8min | 1.0% | $1.14 | 1.04% |
| powershell-tool | opus48-1m-medium-cli2.1.193 | 4 | 4 | 5.3min | 1.1% | $1.31 | 1.20% |
| bash | opus48-1m-medium-cli2.1.193 | 5 | 5 | 5.5min | 1.1% | $1.49 | 1.36% |
| default | opus48-1m-medium-cli2.1.193 | 5 | 5 | 6.4min | 1.3% | $1.57 | 1.43% |
| bash | opus48-1m-high-cli2.1.195 | 2 | 4 | 5.9min | 1.2% | $1.59 | 1.45% |
| powershell | opus48-1m-high-cli2.1.195 | 2 | 3 | 9.5min | 1.9% | $2.11 | 1.93% |
| bash | opus48-1m-medium-cli2.1.195 | 2 | 5 | 12.2min | 2.5% | $2.26 | 2.07% |
| typescript-bun | opus48-1m-medium-cli2.1.193 | 4 | 7 | 16.7min | 3.4% | $4.43 | 4.05% |

</details>

### Prompt Cache Savings

| Status | Runs | $ Saved | % of $ |
|--------|------|---------|--------|
| Full hit (100%) | 1 | $0.12 | 0.11% |
| Partial | 41 | $4.12 | 3.77% |
| Miss | 4 | $0.00 | 0.00% |

## Test Quality Evaluation

### Structural Metrics by Language/Model/Effort

Automated analysis of test files: test count, assertion count, and test-to-code line ratio.

| Language | Model | Avg Tests | Avg Assertions | Avg Assert/Test | Avg Test:Code Ratio |
|------|-------|-----------|----------------|-----------------|---------------------|
| bash | opus48-1m-high | 39.5 | 69.0 | 1.7 | 1.46 |
| bash | opus48-1m-medium | 22.9 | 40.6 | 1.8 | 1.15 |
| default | opus48-1m-high | 33.0 | 53.3 | 1.6 | 1.75 |
| default | opus48-1m-medium | 26.7 | 48.0 | 1.8 | 1.08 |
| powershell | opus48-1m-high | 49.5 | 81.0 | 1.6 | 7.63 |
| powershell | opus48-1m-medium | 32.4 | 60.3 | 1.9 | 2.76 |
| powershell-tool | opus48-1m-high | 39.0 | 63.0 | 1.6 | 3.01 |
| powershell-tool | opus48-1m-medium | 32.6 | 56.4 | 1.7 | 4.17 |
| typescript-bun | opus48-1m-high | 40.0 | 73.5 | 1.8 | 0.93 |
| typescript-bun | opus48-1m-medium | 31.0 | 64.6 | 2.1 | 1.04 |


<details>
<summary>Sorted by avg tests (most first)</summary>

| Language | Model | Avg Tests | Avg Assertions | Avg Assert/Test | Avg Test:Code Ratio |
|------|-------|-----------|----------------|-----------------|---------------------|
| powershell | opus48-1m-high | 49.5 | 81.0 | 1.6 | 7.63 |
| typescript-bun | opus48-1m-high | 40.0 | 73.5 | 1.8 | 0.93 |
| bash | opus48-1m-high | 39.5 | 69.0 | 1.7 | 1.46 |
| powershell-tool | opus48-1m-high | 39.0 | 63.0 | 1.6 | 3.01 |
| default | opus48-1m-high | 33.0 | 53.3 | 1.6 | 1.75 |
| powershell-tool | opus48-1m-medium | 32.6 | 56.4 | 1.7 | 4.17 |
| powershell | opus48-1m-medium | 32.4 | 60.3 | 1.9 | 2.76 |
| typescript-bun | opus48-1m-medium | 31.0 | 64.6 | 2.1 | 1.04 |
| default | opus48-1m-medium | 26.7 | 48.0 | 1.8 | 1.08 |
| bash | opus48-1m-medium | 22.9 | 40.6 | 1.8 | 1.15 |

</details>

<details>
<summary>Sorted by avg assertions (most first)</summary>

| Language | Model | Avg Tests | Avg Assertions | Avg Assert/Test | Avg Test:Code Ratio |
|------|-------|-----------|----------------|-----------------|---------------------|
| powershell | opus48-1m-high | 49.5 | 81.0 | 1.6 | 7.63 |
| typescript-bun | opus48-1m-high | 40.0 | 73.5 | 1.8 | 0.93 |
| bash | opus48-1m-high | 39.5 | 69.0 | 1.7 | 1.46 |
| typescript-bun | opus48-1m-medium | 31.0 | 64.6 | 2.1 | 1.04 |
| powershell-tool | opus48-1m-high | 39.0 | 63.0 | 1.6 | 3.01 |
| powershell | opus48-1m-medium | 32.4 | 60.3 | 1.9 | 2.76 |
| powershell-tool | opus48-1m-medium | 32.6 | 56.4 | 1.7 | 4.17 |
| default | opus48-1m-high | 33.0 | 53.3 | 1.6 | 1.75 |
| default | opus48-1m-medium | 26.7 | 48.0 | 1.8 | 1.08 |
| bash | opus48-1m-medium | 22.9 | 40.6 | 1.8 | 1.15 |

</details>

<details>
<summary>Sorted by avg test:code ratio (highest first)</summary>

| Language | Model | Avg Tests | Avg Assertions | Avg Assert/Test | Avg Test:Code Ratio |
|------|-------|-----------|----------------|-----------------|---------------------|
| powershell | opus48-1m-high | 49.5 | 81.0 | 1.6 | 7.63 |
| powershell-tool | opus48-1m-medium | 32.6 | 56.4 | 1.7 | 4.17 |
| powershell-tool | opus48-1m-high | 39.0 | 63.0 | 1.6 | 3.01 |
| powershell | opus48-1m-medium | 32.4 | 60.3 | 1.9 | 2.76 |
| default | opus48-1m-high | 33.0 | 53.3 | 1.6 | 1.75 |
| bash | opus48-1m-high | 39.5 | 69.0 | 1.7 | 1.46 |
| bash | opus48-1m-medium | 22.9 | 40.6 | 1.8 | 1.15 |
| default | opus48-1m-medium | 26.7 | 48.0 | 1.8 | 1.08 |
| typescript-bun | opus48-1m-medium | 31.0 | 64.6 | 2.1 | 1.04 |
| typescript-bun | opus48-1m-high | 40.0 | 73.5 | 1.8 | 0.93 |

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
| Environment Matrix Generator | powershell-tool | opus48-1m-medium | 31 | 57 | 1.8 | 352 | 36 | 9.78 |
| Environment Matrix Generator | typescript-bun | opus48-1m-medium | 26 | 43 | 1.7 | 313 | 482 | 0.65 |
| Artifact Cleanup Script | bash | opus48-1m-medium | 20 | 66 | 3.3 | 357 | 384 | 0.93 |
| Artifact Cleanup Script | default | opus48-1m-medium | 20 | 31 | 1.6 | 391 | 324 | 1.21 |
| Artifact Cleanup Script | powershell | opus48-1m-medium | 16 | 43 | 2.7 | 278 | 106 | 2.62 |
| Artifact Cleanup Script | powershell-tool | opus48-1m-medium | 21 | 46 | 2.2 | 228 | 238 | 0.96 |
| Artifact Cleanup Script | typescript-bun | opus48-1m-medium | 23 | 67 | 2.9 | 507 | 308 | 1.65 |
| Secret Rotation Validator | bash | opus48-1m-medium | 27 | 62 | 2.3 | 229 | 372 | 0.62 |
| Secret Rotation Validator | default | opus48-1m-medium | 31 | 58 | 1.9 | 250 | 291 | 0.86 |
| Secret Rotation Validator | powershell | opus48-1m-medium | 46 | 91 | 2.0 | 446 | 299 | 1.49 |
| Secret Rotation Validator | powershell-tool | opus48-1m-medium | 52 | 78 | 1.5 | 462 | 62 | 7.45 |
| Secret Rotation Validator | typescript-bun | opus48-1m-medium | 39 | 80 | 2.1 | 586 | 554 | 1.06 |
| PR Label Assigner | typescript-bun | opus48-1m-high | 29 | 43 | 1.5 | 307 | 474 | 0.65 |
| Dependency License Checker | default | opus48-1m-high | 33 | 52 | 1.6 | 314 | 84 | 3.74 |

</details>

## Per-Run Results

*Tests Quality = Overall (1-5) from LLM-as-judge of generated test code (dimensions: coverage, rigor, design). `—` = no judge data.*

| Task | Language | Model | Duration | Turns | Errors | Cost | Tests Quality | Chosen | Status |
|------|----------|-------|----------|-------|--------|------|-----------|--------|--------|
| Artifact Cleanup Script | bash | opus48-1m-medium | 31.2min | 57 | 3 | $4.44 | — | bash | ok |
| Artifact Cleanup Script | default | opus48-1m-medium | 10.1min | 27 | 0 | $1.80 | — | python | ok |
| Artifact Cleanup Script | powershell | opus48-1m-medium | 12.0min | 30 | 1 | $1.85 | — | powershell | ok |
| Artifact Cleanup Script | powershell-tool | opus48-1m-medium | 8.6min | 39 | 1 | $2.20 | — | powershell | ok |
| Artifact Cleanup Script | typescript-bun | opus48-1m-medium | 15.6min | 48 | 2 | $3.55 | — | typescript | ok |
| Dependency License Checker | bash | opus48-1m-medium | 5.7min | 24 | 0 | $1.45 | — | bash | ok |
| Dependency License Checker | default | opus48-1m-high | 9.0min | 34 | 0 | $2.24 | — | powershell | ok |
| Dependency License Checker | default | opus48-1m-medium | 7.9min | 33 | 0 | $1.94 | — | python | ok |
| Dependency License Checker | powershell | opus48-1m-medium | 7.7min | 33 | 0 | $1.93 | — | powershell | ok |
| Dependency License Checker | powershell-tool | opus48-1m-medium | 12.7min | 49 | 0 | $3.35 | — | powershell | ok |
| Dependency License Checker | typescript-bun | opus48-1m-medium | 8.7min | 45 | 0 | $2.33 | — | typescript | ok |
| Environment Matrix Generator | bash | opus48-1m-medium | 5.8min | 27 | 0 | $1.72 | — | bash | ok |
| Environment Matrix Generator | default | opus48-1m-medium | 6.7min | 28 | 0 | $2.01 | — | python | ok |
| Environment Matrix Generator | powershell | opus48-1m-medium | 9.3min | 33 | 0 | $2.29 | — | powershell | ok |
| Environment Matrix Generator | powershell-tool | opus48-1m-medium | 12.9min | 52 | 2 | $3.60 | — | powershell | ok |
| Environment Matrix Generator | typescript-bun | opus48-1m-medium | 32.5min | 0 | 3 | $0.00 | — | typescript | timeout |
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
| Secret Rotation Validator | default | opus48-1m-medium | 19.4min | 55 | 1 | $5.36 | — | powershell | ok |
| Secret Rotation Validator | powershell | opus48-1m-medium | 1.1min | 11 | 0 | $0.55 | — | powershell | ok |
| Secret Rotation Validator | powershell-tool | opus48-1m-medium | 12.5min | 35 | 2 | $2.93 | — | powershell | ok |
| Secret Rotation Validator | typescript-bun | opus48-1m-medium | 14.6min | 48 | 1 | $3.15 | — | typescript | ok |
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
| Artifact Cleanup Script | default | opus48-1m-medium | 10.1min | 27 | 0 | $1.80 | — | python | ok |
| Semantic Version Bumper | default | opus48-1m-medium | 7.2min | 27 | 0 | $1.83 | — | python | ok |
| Test Results Aggregator | bash | opus48-1m-medium | 6.3min | 29 | 1 | $1.83 | — | bash | ok |
| Artifact Cleanup Script | powershell | opus48-1m-medium | 12.0min | 30 | 1 | $1.85 | — | powershell | ok |
| PR Label Assigner | default | opus48-1m-high | 7.1min | 25 | 1 | $1.86 | — | python | ok |
| PR Label Assigner | default | opus48-1m-medium | 8.2min | 36 | 1 | $1.91 | — | powershell | ok |
| Dependency License Checker | powershell | opus48-1m-medium | 7.7min | 33 | 0 | $1.93 | — | powershell | ok |
| Dependency License Checker | default | opus48-1m-medium | 7.9min | 33 | 0 | $1.94 | — | python | ok |
| Test Results Aggregator | powershell-tool | opus48-1m-medium | 7.4min | 29 | 0 | $1.95 | — | powershell | ok |
| Environment Matrix Generator | default | opus48-1m-medium | 6.7min | 28 | 0 | $2.01 | — | python | ok |
| Artifact Cleanup Script | powershell-tool | opus48-1m-medium | 8.6min | 39 | 1 | $2.20 | — | powershell | ok |
| Dependency License Checker | default | opus48-1m-high | 9.0min | 34 | 0 | $2.24 | — | powershell | ok |
| Environment Matrix Generator | powershell | opus48-1m-medium | 9.3min | 33 | 0 | $2.29 | — | powershell | ok |
| Semantic Version Bumper | powershell-tool | opus48-1m-high | 12.1min | 34 | 0 | $2.32 | — | powershell | ok |
| Dependency License Checker | typescript-bun | opus48-1m-medium | 8.7min | 45 | 0 | $2.33 | — | typescript | ok |
| Semantic Version Bumper | powershell | opus48-1m-medium | 10.0min | 34 | 0 | $2.33 | — | powershell | ok |
| Semantic Version Bumper | powershell-tool | opus48-1m-medium | 10.6min | 40 | 1 | $2.39 | — | powershell | ok |
| PR Label Assigner | bash | opus48-1m-high | 10.1min | 31 | 0 | $2.45 | — | bash | ok |
| Semantic Version Bumper | typescript-bun | opus48-1m-medium | 9.3min | 47 | 2 | $2.47 | — | typescript | ok |
| PR Label Assigner | typescript-bun | opus48-1m-medium | 13.1min | 44 | 0 | $2.48 | — | typescript | ok |
| Test Results Aggregator | typescript-bun | opus48-1m-medium | 9.2min | 45 | 0 | $2.57 | — | typescript | ok |
| PR Label Assigner | powershell | opus48-1m-high | 11.0min | 47 | 0 | $2.65 | — | powershell | ok |
| Semantic Version Bumper | bash | opus48-1m-high | 9.5min | 41 | 1 | $2.70 | — | bash | ok |
| PR Label Assigner | powershell-tool | opus48-1m-high | 11.4min | 41 | 0 | $2.78 | — | powershell | ok |
| Secret Rotation Validator | powershell-tool | opus48-1m-medium | 12.5min | 35 | 2 | $2.93 | — | powershell | ok |
| Semantic Version Bumper | typescript-bun | opus48-1m-high | 11.5min | 52 | 0 | $3.14 | — | typescript | ok |
| Secret Rotation Validator | typescript-bun | opus48-1m-medium | 14.6min | 48 | 1 | $3.15 | — | typescript | ok |
| Semantic Version Bumper | default | opus48-1m-high | 9.8min | 52 | 0 | $3.34 | — | javascript | ok |
| Dependency License Checker | powershell-tool | opus48-1m-medium | 12.7min | 49 | 0 | $3.35 | — | powershell | ok |
| Artifact Cleanup Script | typescript-bun | opus48-1m-medium | 15.6min | 48 | 2 | $3.55 | — | typescript | ok |
| Semantic Version Bumper | powershell | opus48-1m-high | 16.9min | 60 | 2 | $3.59 | — | powershell | ok |
| Environment Matrix Generator | powershell-tool | opus48-1m-medium | 12.9min | 52 | 2 | $3.60 | — | powershell | ok |
| Artifact Cleanup Script | bash | opus48-1m-medium | 31.2min | 57 | 3 | $4.44 | — | bash | ok |
| Secret Rotation Validator | default | opus48-1m-medium | 19.4min | 55 | 1 | $5.36 | — | powershell | ok |
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
| Artifact Cleanup Script | powershell-tool | opus48-1m-medium | 8.6min | 39 | 1 | $2.20 | — | powershell | ok |
| Dependency License Checker | typescript-bun | opus48-1m-medium | 8.7min | 45 | 0 | $2.33 | — | typescript | ok |
| Dependency License Checker | default | opus48-1m-high | 9.0min | 34 | 0 | $2.24 | — | powershell | ok |
| Test Results Aggregator | typescript-bun | opus48-1m-medium | 9.2min | 45 | 0 | $2.57 | — | typescript | ok |
| Semantic Version Bumper | typescript-bun | opus48-1m-medium | 9.3min | 47 | 2 | $2.47 | — | typescript | ok |
| Environment Matrix Generator | powershell | opus48-1m-medium | 9.3min | 33 | 0 | $2.29 | — | powershell | ok |
| Semantic Version Bumper | bash | opus48-1m-high | 9.5min | 41 | 1 | $2.70 | — | bash | ok |
| Semantic Version Bumper | default | opus48-1m-high | 9.8min | 52 | 0 | $3.34 | — | javascript | ok |
| Semantic Version Bumper | powershell | opus48-1m-medium | 10.0min | 34 | 0 | $2.33 | — | powershell | ok |
| PR Label Assigner | bash | opus48-1m-high | 10.1min | 31 | 0 | $2.45 | — | bash | ok |
| Artifact Cleanup Script | default | opus48-1m-medium | 10.1min | 27 | 0 | $1.80 | — | python | ok |
| Semantic Version Bumper | powershell-tool | opus48-1m-medium | 10.6min | 40 | 1 | $2.39 | — | powershell | ok |
| PR Label Assigner | powershell | opus48-1m-high | 11.0min | 47 | 0 | $2.65 | — | powershell | ok |
| PR Label Assigner | powershell-tool | opus48-1m-high | 11.4min | 41 | 0 | $2.78 | — | powershell | ok |
| Semantic Version Bumper | typescript-bun | opus48-1m-high | 11.5min | 52 | 0 | $3.14 | — | typescript | ok |
| Artifact Cleanup Script | powershell | opus48-1m-medium | 12.0min | 30 | 1 | $1.85 | — | powershell | ok |
| Semantic Version Bumper | powershell-tool | opus48-1m-high | 12.1min | 34 | 0 | $2.32 | — | powershell | ok |
| Secret Rotation Validator | powershell-tool | opus48-1m-medium | 12.5min | 35 | 2 | $2.93 | — | powershell | ok |
| Dependency License Checker | powershell-tool | opus48-1m-medium | 12.7min | 49 | 0 | $3.35 | — | powershell | ok |
| Environment Matrix Generator | powershell-tool | opus48-1m-medium | 12.9min | 52 | 2 | $3.60 | — | powershell | ok |
| PR Label Assigner | typescript-bun | opus48-1m-medium | 13.1min | 44 | 0 | $2.48 | — | typescript | ok |
| Secret Rotation Validator | typescript-bun | opus48-1m-medium | 14.6min | 48 | 1 | $3.15 | — | typescript | ok |
| Artifact Cleanup Script | typescript-bun | opus48-1m-medium | 15.6min | 48 | 2 | $3.55 | — | typescript | ok |
| Semantic Version Bumper | powershell | opus48-1m-high | 16.9min | 60 | 2 | $3.59 | — | powershell | ok |
| Secret Rotation Validator | default | opus48-1m-medium | 19.4min | 55 | 1 | $5.36 | — | powershell | ok |
| Secret Rotation Validator | bash | opus48-1m-medium | 23.9min | 64 | 6 | $5.71 | — | bash | ok |
| Artifact Cleanup Script | bash | opus48-1m-medium | 31.2min | 57 | 3 | $4.44 | — | bash | ok |
| Environment Matrix Generator | typescript-bun | opus48-1m-medium | 32.5min | 0 | 3 | $0.00 | — | typescript | timeout |

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
| Artifact Cleanup Script | default | opus48-1m-medium | 10.1min | 27 | 0 | $1.80 | — | python | ok |
| Secret Rotation Validator | powershell | opus48-1m-medium | 1.1min | 11 | 0 | $0.55 | — | powershell | ok |
| Dependency License Checker | default | opus48-1m-high | 9.0min | 34 | 0 | $2.24 | — | powershell | ok |
| Semantic Version Bumper | bash | opus48-1m-high | 9.5min | 41 | 1 | $2.70 | — | bash | ok |
| Semantic Version Bumper | powershell-tool | opus48-1m-medium | 10.6min | 40 | 1 | $2.39 | — | powershell | ok |
| PR Label Assigner | default | opus48-1m-high | 7.1min | 25 | 1 | $1.86 | — | python | ok |
| PR Label Assigner | default | opus48-1m-medium | 8.2min | 36 | 1 | $1.91 | — | powershell | ok |
| PR Label Assigner | powershell-tool | opus48-1m-medium | 7.6min | 27 | 1 | $1.66 | — | powershell | ok |
| Test Results Aggregator | bash | opus48-1m-medium | 6.3min | 29 | 1 | $1.83 | — | bash | ok |
| Artifact Cleanup Script | powershell | opus48-1m-medium | 12.0min | 30 | 1 | $1.85 | — | powershell | ok |
| Artifact Cleanup Script | powershell-tool | opus48-1m-medium | 8.6min | 39 | 1 | $2.20 | — | powershell | ok |
| Secret Rotation Validator | default | opus48-1m-medium | 19.4min | 55 | 1 | $5.36 | — | powershell | ok |
| Secret Rotation Validator | typescript-bun | opus48-1m-medium | 14.6min | 48 | 1 | $3.15 | — | typescript | ok |
| PR Label Assigner | typescript-bun | opus48-1m-high | 3.0min | 26 | 1 | $1.17 | — | typescript | ok |
| Semantic Version Bumper | powershell | opus48-1m-high | 16.9min | 60 | 2 | $3.59 | — | powershell | ok |
| Semantic Version Bumper | typescript-bun | opus48-1m-medium | 9.3min | 47 | 2 | $2.47 | — | typescript | ok |
| Environment Matrix Generator | powershell-tool | opus48-1m-medium | 12.9min | 52 | 2 | $3.60 | — | powershell | ok |
| Artifact Cleanup Script | typescript-bun | opus48-1m-medium | 15.6min | 48 | 2 | $3.55 | — | typescript | ok |
| Secret Rotation Validator | powershell-tool | opus48-1m-medium | 12.5min | 35 | 2 | $2.93 | — | powershell | ok |
| Environment Matrix Generator | typescript-bun | opus48-1m-medium | 32.5min | 0 | 3 | $0.00 | — | typescript | timeout |
| Artifact Cleanup Script | bash | opus48-1m-medium | 31.2min | 57 | 3 | $4.44 | — | bash | ok |
| Secret Rotation Validator | bash | opus48-1m-medium | 23.9min | 64 | 6 | $5.71 | — | bash | ok |

</details>

<details>
<summary>Sorted by turns (fewest first)</summary>

| Task | Language | Model | Duration | Turns | Errors | Cost | Tests Quality | Chosen | Status |
|------|----------|-------|----------|-------|--------|------|-----------|--------|--------|
| Environment Matrix Generator | typescript-bun | opus48-1m-medium | 32.5min | 0 | 3 | $0.00 | — | typescript | timeout |
| Secret Rotation Validator | powershell | opus48-1m-medium | 1.1min | 11 | 0 | $0.55 | — | powershell | ok |
| PR Label Assigner | bash | opus48-1m-medium | 4.8min | 20 | 0 | $1.22 | — | bash | ok |
| Semantic Version Bumper | bash | opus48-1m-medium | 6.8min | 22 | 0 | $1.55 | — | bash | ok |
| PR Label Assigner | powershell | opus48-1m-medium | 6.3min | 23 | 0 | $1.52 | — | powershell | ok |
| Dependency License Checker | bash | opus48-1m-medium | 5.7min | 24 | 0 | $1.45 | — | bash | ok |
| PR Label Assigner | default | opus48-1m-high | 7.1min | 25 | 1 | $1.86 | — | python | ok |
| Test Results Aggregator | default | opus48-1m-medium | 6.6min | 26 | 0 | $1.50 | — | python | ok |
| PR Label Assigner | typescript-bun | opus48-1m-high | 3.0min | 26 | 1 | $1.17 | — | typescript | ok |
| Semantic Version Bumper | default | opus48-1m-medium | 7.2min | 27 | 0 | $1.83 | — | python | ok |
| PR Label Assigner | powershell-tool | opus48-1m-medium | 7.6min | 27 | 1 | $1.66 | — | powershell | ok |
| Environment Matrix Generator | bash | opus48-1m-medium | 5.8min | 27 | 0 | $1.72 | — | bash | ok |
| Artifact Cleanup Script | default | opus48-1m-medium | 10.1min | 27 | 0 | $1.80 | — | python | ok |
| Environment Matrix Generator | default | opus48-1m-medium | 6.7min | 28 | 0 | $2.01 | — | python | ok |
| Test Results Aggregator | bash | opus48-1m-medium | 6.3min | 29 | 1 | $1.83 | — | bash | ok |
| Test Results Aggregator | powershell-tool | opus48-1m-medium | 7.4min | 29 | 0 | $1.95 | — | powershell | ok |
| Test Results Aggregator | powershell | opus48-1m-medium | 8.1min | 30 | 0 | $1.77 | — | powershell | ok |
| Artifact Cleanup Script | powershell | opus48-1m-medium | 12.0min | 30 | 1 | $1.85 | — | powershell | ok |
| PR Label Assigner | bash | opus48-1m-high | 10.1min | 31 | 0 | $2.45 | — | bash | ok |
| Dependency License Checker | default | opus48-1m-medium | 7.9min | 33 | 0 | $1.94 | — | python | ok |
| Dependency License Checker | powershell | opus48-1m-medium | 7.7min | 33 | 0 | $1.93 | — | powershell | ok |
| Environment Matrix Generator | powershell | opus48-1m-medium | 9.3min | 33 | 0 | $2.29 | — | powershell | ok |
| Semantic Version Bumper | powershell | opus48-1m-medium | 10.0min | 34 | 0 | $2.33 | — | powershell | ok |
| Semantic Version Bumper | powershell-tool | opus48-1m-high | 12.1min | 34 | 0 | $2.32 | — | powershell | ok |
| Dependency License Checker | default | opus48-1m-high | 9.0min | 34 | 0 | $2.24 | — | powershell | ok |
| Secret Rotation Validator | powershell-tool | opus48-1m-medium | 12.5min | 35 | 2 | $2.93 | — | powershell | ok |
| PR Label Assigner | default | opus48-1m-medium | 8.2min | 36 | 1 | $1.91 | — | powershell | ok |
| Artifact Cleanup Script | powershell-tool | opus48-1m-medium | 8.6min | 39 | 1 | $2.20 | — | powershell | ok |
| Semantic Version Bumper | powershell-tool | opus48-1m-medium | 10.6min | 40 | 1 | $2.39 | — | powershell | ok |
| Semantic Version Bumper | bash | opus48-1m-high | 9.5min | 41 | 1 | $2.70 | — | bash | ok |
| PR Label Assigner | powershell-tool | opus48-1m-high | 11.4min | 41 | 0 | $2.78 | — | powershell | ok |
| PR Label Assigner | typescript-bun | opus48-1m-medium | 13.1min | 44 | 0 | $2.48 | — | typescript | ok |
| Dependency License Checker | typescript-bun | opus48-1m-medium | 8.7min | 45 | 0 | $2.33 | — | typescript | ok |
| Test Results Aggregator | typescript-bun | opus48-1m-medium | 9.2min | 45 | 0 | $2.57 | — | typescript | ok |
| Semantic Version Bumper | typescript-bun | opus48-1m-medium | 9.3min | 47 | 2 | $2.47 | — | typescript | ok |
| PR Label Assigner | powershell | opus48-1m-high | 11.0min | 47 | 0 | $2.65 | — | powershell | ok |
| Artifact Cleanup Script | typescript-bun | opus48-1m-medium | 15.6min | 48 | 2 | $3.55 | — | typescript | ok |
| Secret Rotation Validator | typescript-bun | opus48-1m-medium | 14.6min | 48 | 1 | $3.15 | — | typescript | ok |
| Dependency License Checker | powershell-tool | opus48-1m-medium | 12.7min | 49 | 0 | $3.35 | — | powershell | ok |
| Semantic Version Bumper | default | opus48-1m-high | 9.8min | 52 | 0 | $3.34 | — | javascript | ok |
| Semantic Version Bumper | typescript-bun | opus48-1m-high | 11.5min | 52 | 0 | $3.14 | — | typescript | ok |
| Environment Matrix Generator | powershell-tool | opus48-1m-medium | 12.9min | 52 | 2 | $3.60 | — | powershell | ok |
| Secret Rotation Validator | default | opus48-1m-medium | 19.4min | 55 | 1 | $5.36 | — | powershell | ok |
| Artifact Cleanup Script | bash | opus48-1m-medium | 31.2min | 57 | 3 | $4.44 | — | bash | ok |
| Semantic Version Bumper | powershell | opus48-1m-high | 16.9min | 60 | 2 | $3.59 | — | powershell | ok |
| Secret Rotation Validator | bash | opus48-1m-medium | 23.9min | 64 | 6 | $5.71 | — | bash | ok |

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
| Environment Matrix Generator | powershell-tool | opus48-1m-medium | 12.9min | 52 | 2 | $3.60 | — | powershell | ok |
| Environment Matrix Generator | typescript-bun | opus48-1m-medium | 32.5min | 0 | 3 | $0.00 | — | typescript | timeout |
| Artifact Cleanup Script | bash | opus48-1m-medium | 31.2min | 57 | 3 | $4.44 | — | bash | ok |
| Artifact Cleanup Script | default | opus48-1m-medium | 10.1min | 27 | 0 | $1.80 | — | python | ok |
| Artifact Cleanup Script | powershell | opus48-1m-medium | 12.0min | 30 | 1 | $1.85 | — | powershell | ok |
| Artifact Cleanup Script | powershell-tool | opus48-1m-medium | 8.6min | 39 | 1 | $2.20 | — | powershell | ok |
| Artifact Cleanup Script | typescript-bun | opus48-1m-medium | 15.6min | 48 | 2 | $3.55 | — | typescript | ok |
| Secret Rotation Validator | bash | opus48-1m-medium | 23.9min | 64 | 6 | $5.71 | — | bash | ok |
| Secret Rotation Validator | default | opus48-1m-medium | 19.4min | 55 | 1 | $5.36 | — | powershell | ok |
| Secret Rotation Validator | powershell | opus48-1m-medium | 1.1min | 11 | 0 | $0.55 | — | powershell | ok |
| Secret Rotation Validator | powershell-tool | opus48-1m-medium | 12.5min | 35 | 2 | $2.93 | — | powershell | ok |
| Secret Rotation Validator | typescript-bun | opus48-1m-medium | 14.6min | 48 | 1 | $3.15 | — | typescript | ok |
| PR Label Assigner | typescript-bun | opus48-1m-high | 3.0min | 26 | 1 | $1.17 | — | typescript | ok |
| Dependency License Checker | default | opus48-1m-high | 9.0min | 34 | 0 | $2.24 | — | powershell | ok |

</details>

## Notes

### Tiers

- **Duration bands:** **A+** ≤1.06×, **A** ≤1.12×, **A-** ≤1.18×, **B+** ≤1.24×, **B** ≤1.31×, **B-** ≤1.39×, **C+** ≤1.47×, **C** ≤1.55×, **C-** ≤1.64×, **D+** ≤1.73×, **D** ≤1.82×, **D-** ≤1.93×, **F** >1.93×
- **Cost bands:** **A+** ≤1.05×, **A** ≤1.10×, **A-** ≤1.16×, **B+** ≤1.21×, **B** ≤1.27×, **B-** ≤1.34×, **C+** ≤1.40×, **C** ≤1.47×, **C-** ≤1.54×, **D+** ≤1.62×, **D** ≤1.70×, **D-** ≤1.78×, **F** >1.78×

*Tests/Workflow Craft bands are absolute Overall score bands:* **A+** ≥4.7, **A** ≥4.4, **A-** ≥4.1, **B+** ≥3.8, **B** ≥3.5, **B-** ≥3.2, **C+** ≥2.9, **C** ≥2.6, **C-** ≥2.3, **D+** ≥2.0, **D** ≥1.7, **D-** ≥1.4, **F** <1.4, `—` = no data.*

### CLI Version Legend

| Variant label | CLI version | Tasks | Languages |
|---------------|-------------|-------|-----------|
| opus48-1m-high | 2.1.195 | 11-semantic-version-bumper, 12-pr-label-assigner, 13-dependency-license-checker | All |
| opus48-1m-medium | 2.1.193 | 11-semantic-version-bumper, 12-pr-label-assigner, 13-dependency-license-checker, 15-test-results-aggregator, 16-environment-matrix-generator | All |
| opus48-1m-medium | 2.1.195 | 16-environment-matrix-generator, 17-artifact-cleanup-script, 18-secret-rotation-validator | All |

---
*Generated by generate_results.py — benchmark instructions v4*