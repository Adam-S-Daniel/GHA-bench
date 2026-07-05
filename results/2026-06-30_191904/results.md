# Benchmark Results: Language Comparison

**Last updated:** 2026-07-05 01:02:49 AM ET — 100/100 runs completed, 0 remaining; total cost $255.46; total agent time 1388.8 min.
**Claude Code versions used:** [v2.1.197](claude-code-2.1.197.md) (89 runs), [v2.1.198](claude-code-2.1.198.md) (11 runs). Each link goes to a per-version snapshot of the system prompt, default-tool descriptions, and the chronological Anthropic changelog up to that version. Regenerate with `python3 version_docs.py`.

## Table of Contents

- [Scoring](#scoring)
  - [Duration columns](#duration-columns)
- [Tiers by Language/Model/Effort](#tiers-by-languagemodeleffort)
- [Failed / Timed-Out Runs](#failed-timed-out-runs)
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
- The **Geo Duration pool additionally includes timed-out runs**, counted at their recorded wall clock. A timeout is right-censored — its true duration might have been longer, but is known to be AT LEAST the recorded value — so excluding it outright would effectively reward timing out with a better average. Geo Cost and Geo Turns still exclude ALL failed runs (including timeouts): a killed CLI records `cost=0`/`turns=0`, which is missing data, not a real zero, and would bias those averages down if pooled in. This means **Total Cost can slightly understate** true spend on rows with timeouts (the timeout's own cost isn't in the sum either).
- **Max Duration** is the slowest run in the Geo Duration pool for that combo, `≥`-prefixed when that run was a timeout (true duration unknown, but at least the shown value).
- **Avg Errors** remains an arithmetic mean.
- **Geo Duration Net of Traps** (in the Comparison table only): the geometric mean of (per-run `Duration` − that run's `Time Lost`), where `Time Lost` is the trap detector's estimate of seconds spent on detected anti-patterns (see [Trap Descriptions](#trap-descriptions) and the trap-table [Column Definitions](#column-definitions) for the trap list and how Time Lost is computed). Pooled over the SAME runs as Geo Duration — timed-out cells are included, with their detected traps (if any) deducted too. Reads as a counterfactual: roughly how fast each combo would have been without the detected traps.
- The **Tier table's Duration/Cost columns** show the tier letter (A+..F) for the combo's gross **Geo Duration**/**Geo Cost** ratio. Net of Traps does not feed the tier band.
## Tiers by Language/Model/Effort

*Default sort: weighted composite of tiers (40% Tests, 25% Workflow Craft, 35% split between Duration & Cost). See [Notes](#notes) for tier-band definitions and scoring rubric.*
*`*` after a Model label = one or more of this combo's runs failed or timed out — excluded from the cost/turns/errors aggregates, though timeouts still pool into the duration stats (see the Failed / Timed-Out Runs table).*

| Language | Model | Duration | Cost | Tests Quality | Workflow Craft |
|----------|-------|----------|------|-----------|-------------|
| default | sonnet5-1m-low | A+ (5.9min) | B+ ($1.10) | C+ (3.0) | B (3.6) |
| bash | sonnet5-1m-low | A (7.1min) | A+ ($0.59) | C (2.9) | B (3.5) |
| default | sonnet5-1m-medium | A- (7.9min) | C+ ($1.98) | C+ (3.1) | B+ (4.0) |
| powershell | sonnet5-1m-medium | C+ (12.9min) | C ($2.21) | B (3.7) | B+ (3.9) |
| bash | sonnet5-1m-medium* | B- (11.9min) | C- ($2.77) | B+ (3.8) | B- (3.3) |
| powershell | sonnet5-1m-high* | D- (24.9min) | D ($4.52) | A- (4.3) | A (4.4) |
| typescript-bun | sonnet5-1m-high | D (21.1min) | D- ($5.62) | A- (4.3) | A- (4.1) |
| default | sonnet5-1m-high | C+ (13.1min) | D+ ($3.44) | B (3.6) | B (3.6) |
| powershell | sonnet5-1m-low | B+ (8.5min) | B+ ($1.20) | C (2.8) | C (2.8) |
| typescript-bun | sonnet5-1m-medium | C+ (12.8min) | C ($2.64) | C+ (3.1) | B (3.8) |
| bash | sonnet5-1m-high* | D+ (18.2min) | D- ($4.96) | B (3.7) | B (3.6) |
| typescript-bun | sonnet5-1m-low | A- (7.8min) | B+ ($1.07) | D+ (2.1) | C (2.7) |


<details>
<summary>Sorted by Duration tier (best-first), then avg of Cost/Tests/Workflow Craft tiers</summary>

| Language | Model | Duration | Cost | Tests Quality | Workflow Craft |
|----------|-------|----------|------|-----------|-------------|
| default | sonnet5-1m-low | A+ (5.9min) | B+ ($1.10) | C+ (3.0) | B (3.6) |
| bash | sonnet5-1m-low | A (7.1min) | A+ ($0.59) | C (2.9) | B (3.5) |
| default | sonnet5-1m-medium | A- (7.9min) | C+ ($1.98) | C+ (3.1) | B+ (4.0) |
| typescript-bun | sonnet5-1m-low | A- (7.8min) | B+ ($1.07) | D+ (2.1) | C (2.7) |
| powershell | sonnet5-1m-low | B+ (8.5min) | B+ ($1.20) | C (2.8) | C (2.8) |
| bash | sonnet5-1m-medium* | B- (11.9min) | C- ($2.77) | B+ (3.8) | B- (3.3) |
| powershell | sonnet5-1m-medium | C+ (12.9min) | C ($2.21) | B (3.7) | B+ (3.9) |
| default | sonnet5-1m-high | C+ (13.1min) | D+ ($3.44) | B (3.6) | B (3.6) |
| typescript-bun | sonnet5-1m-medium | C+ (12.8min) | C ($2.64) | C+ (3.1) | B (3.8) |
| bash | sonnet5-1m-high* | D+ (18.2min) | D- ($4.96) | B (3.7) | B (3.6) |
| typescript-bun | sonnet5-1m-high | D (21.1min) | D- ($5.62) | A- (4.3) | A- (4.1) |
| powershell | sonnet5-1m-high* | D- (24.9min) | D ($4.52) | A- (4.3) | A (4.4) |

</details>

<details>
<summary>Sorted by Cost tier (best-first), then avg of Duration/Tests/Workflow Craft tiers</summary>

| Language | Model | Duration | Cost | Tests Quality | Workflow Craft |
|----------|-------|----------|------|-----------|-------------|
| bash | sonnet5-1m-low | A (7.1min) | A+ ($0.59) | C (2.9) | B (3.5) |
| default | sonnet5-1m-low | A+ (5.9min) | B+ ($1.10) | C+ (3.0) | B (3.6) |
| powershell | sonnet5-1m-low | B+ (8.5min) | B+ ($1.20) | C (2.8) | C (2.8) |
| typescript-bun | sonnet5-1m-low | A- (7.8min) | B+ ($1.07) | D+ (2.1) | C (2.7) |
| default | sonnet5-1m-medium | A- (7.9min) | C+ ($1.98) | C+ (3.1) | B+ (4.0) |
| powershell | sonnet5-1m-medium | C+ (12.9min) | C ($2.21) | B (3.7) | B+ (3.9) |
| typescript-bun | sonnet5-1m-medium | C+ (12.8min) | C ($2.64) | C+ (3.1) | B (3.8) |
| bash | sonnet5-1m-medium* | B- (11.9min) | C- ($2.77) | B+ (3.8) | B- (3.3) |
| default | sonnet5-1m-high | C+ (13.1min) | D+ ($3.44) | B (3.6) | B (3.6) |
| powershell | sonnet5-1m-high* | D- (24.9min) | D ($4.52) | A- (4.3) | A (4.4) |
| typescript-bun | sonnet5-1m-high | D (21.1min) | D- ($5.62) | A- (4.3) | A- (4.1) |
| bash | sonnet5-1m-high* | D+ (18.2min) | D- ($4.96) | B (3.7) | B (3.6) |

</details>

<details>
<summary>Sorted by Tests Quality tier (best-first; no-data last), then avg of other tiers</summary>

| Language | Model | Duration | Cost | Tests Quality | Workflow Craft |
|----------|-------|----------|------|-----------|-------------|
| powershell | sonnet5-1m-high* | D- (24.9min) | D ($4.52) | A- (4.3) | A (4.4) |
| typescript-bun | sonnet5-1m-high | D (21.1min) | D- ($5.62) | A- (4.3) | A- (4.1) |
| bash | sonnet5-1m-medium* | B- (11.9min) | C- ($2.77) | B+ (3.8) | B- (3.3) |
| powershell | sonnet5-1m-medium | C+ (12.9min) | C ($2.21) | B (3.7) | B+ (3.9) |
| default | sonnet5-1m-high | C+ (13.1min) | D+ ($3.44) | B (3.6) | B (3.6) |
| bash | sonnet5-1m-high* | D+ (18.2min) | D- ($4.96) | B (3.7) | B (3.6) |
| default | sonnet5-1m-low | A+ (5.9min) | B+ ($1.10) | C+ (3.0) | B (3.6) |
| default | sonnet5-1m-medium | A- (7.9min) | C+ ($1.98) | C+ (3.1) | B+ (4.0) |
| typescript-bun | sonnet5-1m-medium | C+ (12.8min) | C ($2.64) | C+ (3.1) | B (3.8) |
| bash | sonnet5-1m-low | A (7.1min) | A+ ($0.59) | C (2.9) | B (3.5) |
| powershell | sonnet5-1m-low | B+ (8.5min) | B+ ($1.20) | C (2.8) | C (2.8) |
| typescript-bun | sonnet5-1m-low | A- (7.8min) | B+ ($1.07) | D+ (2.1) | C (2.7) |

</details>

<details>
<summary>Sorted by Workflow Craft tier (best-first; no-data last), then avg of other tiers</summary>

| Language | Model | Duration | Cost | Tests Quality | Workflow Craft |
|----------|-------|----------|------|-----------|-------------|
| powershell | sonnet5-1m-high* | D- (24.9min) | D ($4.52) | A- (4.3) | A (4.4) |
| typescript-bun | sonnet5-1m-high | D (21.1min) | D- ($5.62) | A- (4.3) | A- (4.1) |
| default | sonnet5-1m-medium | A- (7.9min) | C+ ($1.98) | C+ (3.1) | B+ (4.0) |
| powershell | sonnet5-1m-medium | C+ (12.9min) | C ($2.21) | B (3.7) | B+ (3.9) |
| bash | sonnet5-1m-low | A (7.1min) | A+ ($0.59) | C (2.9) | B (3.5) |
| default | sonnet5-1m-low | A+ (5.9min) | B+ ($1.10) | C+ (3.0) | B (3.6) |
| default | sonnet5-1m-high | C+ (13.1min) | D+ ($3.44) | B (3.6) | B (3.6) |
| typescript-bun | sonnet5-1m-medium | C+ (12.8min) | C ($2.64) | C+ (3.1) | B (3.8) |
| bash | sonnet5-1m-high* | D+ (18.2min) | D- ($4.96) | B (3.7) | B (3.6) |
| bash | sonnet5-1m-medium* | B- (11.9min) | C- ($2.77) | B+ (3.8) | B- (3.3) |
| powershell | sonnet5-1m-low | B+ (8.5min) | B+ ($1.20) | C (2.8) | C (2.8) |
| typescript-bun | sonnet5-1m-low | A- (7.8min) | B+ ($1.07) | D+ (2.1) | C (2.7) |

</details>

## Failed / Timed-Out Runs

| Task | Language | Model | Duration | Reason | Lines | actionlint | act-result.txt |
|------|------|-------|----------|--------|-------|------------|----------------|
| Semantic Version Bumper | powershell | sonnet5-1m-high | 30.0min | timeout | 667 | pass | yes |
| PR Label Assigner | bash | sonnet5-1m-high | 30.0min | timeout | 1034 | pass | yes |
| PR Label Assigner | powershell | sonnet5-1m-high | 30.0min | timeout | 806 | pass | yes |
| PR Label Assigner | powershell | sonnet5-1m-high | 30.0min | timeout | 621 | pass | no |
| Test Results Aggregator | powershell | sonnet5-1m-high | 30.0min | timeout | 824 | pass | yes |
| Secret Rotation Validator | bash | sonnet5-1m-medium | 9.3min | cli_error | 652 | pass | yes |
| Secret Rotation Validator | powershell | sonnet5-1m-high | 30.0min | timeout | 723 | pass | yes |

*7 run(s) excluded from averages below.*

## Comparison by Language/Model/Effort
*(failed runs are excluded from the cost/turns/errors averages; timed-out runs still pool into the duration stats — see [Column Definitions](#column-definitions))*
*See [Notes](#notes) for scoring rubric and CLI version legend.*

| Language | Model | Runs | Geo Duration | Max Duration | Geo Duration Net of Traps | Avg Errors | Geo Turns | Geo Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| bash | sonnet5-1m-high* | 6 | 18.2min | ≥30.0min | 15.3min | 4.3 | 94 | $4.96 | $31.61 | 3.7 | 3.6 |
| bash | sonnet5-1m-low | 7 | 7.1min | 13.7min | 5.3min | 2.4 | 15 | $0.59 | $5.58 | 2.9 | 3.5 |
| bash | sonnet5-1m-medium* | 6 | 11.9min | 16.9min | 8.8min | 3.3 | 73 | $2.77 | $17.14 | 3.8 | 3.3 |
| default | sonnet5-1m-high | 7 | 13.1min | 18.0min | 11.9min | 0.9 | 69 | $3.44 | $24.82 | 3.6 | 3.6 |
| default | sonnet5-1m-low | 7 | 5.9min | 10.7min | 5.3min | 0.4 | 33 | $1.10 | $7.94 | 3.0 | 3.6 |
| default | sonnet5-1m-medium | 7 | 7.9min | 11.5min | 6.6min | 1.3 | 56 | $1.98 | $14.44 | 3.1 | 4.0 |
| powershell | sonnet5-1m-high* | 9 | 24.9min | ≥30.0min | 21.4min | 1.1 | 87 | $4.52 | $41.97 | 4.3 | 4.4 |
| powershell | sonnet5-1m-low | 9 | 8.5min | 15.4min | 7.5min | 0.6 | 29 | $1.20 | $11.16 | 2.8 | 2.8 |
| powershell | sonnet5-1m-medium | 14 | 12.9min | 18.8min | 11.2min | 0.5 | 54 | $2.21 | $32.83 | 3.7 | 3.9 |
| typescript-bun | sonnet5-1m-high | 7 | 21.1min | 25.3min | 18.5min | 3.6 | 122 | $5.62 | $39.95 | 4.3 | 4.1 |
| typescript-bun | sonnet5-1m-low | 7 | 7.8min | 12.0min | 5.2min | 1.6 | 32 | $1.07 | $9.28 | 2.1 | 2.7 |
| typescript-bun | sonnet5-1m-medium | 7 | 12.8min | 17.0min | 9.4min | 1.4 | 82 | $2.64 | $18.75 | 3.1 | 3.8 |


<details>
<summary>Sorted by cost (geomean, cheapest first)</summary>

| Language | Model | Runs | Geo Duration | Max Duration | Geo Duration Net of Traps | Avg Errors | Geo Turns | Geo Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| bash | sonnet5-1m-low | 7 | 7.1min | 13.7min | 5.3min | 2.4 | 15 | $0.59 | $5.58 | 2.9 | 3.5 |
| typescript-bun | sonnet5-1m-low | 7 | 7.8min | 12.0min | 5.2min | 1.6 | 32 | $1.07 | $9.28 | 2.1 | 2.7 |
| default | sonnet5-1m-low | 7 | 5.9min | 10.7min | 5.3min | 0.4 | 33 | $1.10 | $7.94 | 3.0 | 3.6 |
| powershell | sonnet5-1m-low | 9 | 8.5min | 15.4min | 7.5min | 0.6 | 29 | $1.20 | $11.16 | 2.8 | 2.8 |
| default | sonnet5-1m-medium | 7 | 7.9min | 11.5min | 6.6min | 1.3 | 56 | $1.98 | $14.44 | 3.1 | 4.0 |
| powershell | sonnet5-1m-medium | 14 | 12.9min | 18.8min | 11.2min | 0.5 | 54 | $2.21 | $32.83 | 3.7 | 3.9 |
| typescript-bun | sonnet5-1m-medium | 7 | 12.8min | 17.0min | 9.4min | 1.4 | 82 | $2.64 | $18.75 | 3.1 | 3.8 |
| bash | sonnet5-1m-medium* | 6 | 11.9min | 16.9min | 8.8min | 3.3 | 73 | $2.77 | $17.14 | 3.8 | 3.3 |
| default | sonnet5-1m-high | 7 | 13.1min | 18.0min | 11.9min | 0.9 | 69 | $3.44 | $24.82 | 3.6 | 3.6 |
| powershell | sonnet5-1m-high* | 9 | 24.9min | ≥30.0min | 21.4min | 1.1 | 87 | $4.52 | $41.97 | 4.3 | 4.4 |
| bash | sonnet5-1m-high* | 6 | 18.2min | ≥30.0min | 15.3min | 4.3 | 94 | $4.96 | $31.61 | 3.7 | 3.6 |
| typescript-bun | sonnet5-1m-high | 7 | 21.1min | 25.3min | 18.5min | 3.6 | 122 | $5.62 | $39.95 | 4.3 | 4.1 |

</details>

<details>
<summary>Sorted by duration (geomean, fastest first)</summary>

| Language | Model | Runs | Geo Duration | Max Duration | Geo Duration Net of Traps | Avg Errors | Geo Turns | Geo Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| default | sonnet5-1m-low | 7 | 5.9min | 10.7min | 5.3min | 0.4 | 33 | $1.10 | $7.94 | 3.0 | 3.6 |
| bash | sonnet5-1m-low | 7 | 7.1min | 13.7min | 5.3min | 2.4 | 15 | $0.59 | $5.58 | 2.9 | 3.5 |
| typescript-bun | sonnet5-1m-low | 7 | 7.8min | 12.0min | 5.2min | 1.6 | 32 | $1.07 | $9.28 | 2.1 | 2.7 |
| default | sonnet5-1m-medium | 7 | 7.9min | 11.5min | 6.6min | 1.3 | 56 | $1.98 | $14.44 | 3.1 | 4.0 |
| powershell | sonnet5-1m-low | 9 | 8.5min | 15.4min | 7.5min | 0.6 | 29 | $1.20 | $11.16 | 2.8 | 2.8 |
| bash | sonnet5-1m-medium* | 6 | 11.9min | 16.9min | 8.8min | 3.3 | 73 | $2.77 | $17.14 | 3.8 | 3.3 |
| typescript-bun | sonnet5-1m-medium | 7 | 12.8min | 17.0min | 9.4min | 1.4 | 82 | $2.64 | $18.75 | 3.1 | 3.8 |
| powershell | sonnet5-1m-medium | 14 | 12.9min | 18.8min | 11.2min | 0.5 | 54 | $2.21 | $32.83 | 3.7 | 3.9 |
| default | sonnet5-1m-high | 7 | 13.1min | 18.0min | 11.9min | 0.9 | 69 | $3.44 | $24.82 | 3.6 | 3.6 |
| bash | sonnet5-1m-high* | 6 | 18.2min | ≥30.0min | 15.3min | 4.3 | 94 | $4.96 | $31.61 | 3.7 | 3.6 |
| typescript-bun | sonnet5-1m-high | 7 | 21.1min | 25.3min | 18.5min | 3.6 | 122 | $5.62 | $39.95 | 4.3 | 4.1 |
| powershell | sonnet5-1m-high* | 9 | 24.9min | ≥30.0min | 21.4min | 1.1 | 87 | $4.52 | $41.97 | 4.3 | 4.4 |

</details>

<details>
<summary>Sorted by duration net of traps (geomean, fastest first)</summary>

| Language | Model | Runs | Geo Duration | Max Duration | Geo Duration Net of Traps | Avg Errors | Geo Turns | Geo Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| typescript-bun | sonnet5-1m-low | 7 | 7.8min | 12.0min | 5.2min | 1.6 | 32 | $1.07 | $9.28 | 2.1 | 2.7 |
| bash | sonnet5-1m-low | 7 | 7.1min | 13.7min | 5.3min | 2.4 | 15 | $0.59 | $5.58 | 2.9 | 3.5 |
| default | sonnet5-1m-low | 7 | 5.9min | 10.7min | 5.3min | 0.4 | 33 | $1.10 | $7.94 | 3.0 | 3.6 |
| default | sonnet5-1m-medium | 7 | 7.9min | 11.5min | 6.6min | 1.3 | 56 | $1.98 | $14.44 | 3.1 | 4.0 |
| powershell | sonnet5-1m-low | 9 | 8.5min | 15.4min | 7.5min | 0.6 | 29 | $1.20 | $11.16 | 2.8 | 2.8 |
| bash | sonnet5-1m-medium* | 6 | 11.9min | 16.9min | 8.8min | 3.3 | 73 | $2.77 | $17.14 | 3.8 | 3.3 |
| typescript-bun | sonnet5-1m-medium | 7 | 12.8min | 17.0min | 9.4min | 1.4 | 82 | $2.64 | $18.75 | 3.1 | 3.8 |
| powershell | sonnet5-1m-medium | 14 | 12.9min | 18.8min | 11.2min | 0.5 | 54 | $2.21 | $32.83 | 3.7 | 3.9 |
| default | sonnet5-1m-high | 7 | 13.1min | 18.0min | 11.9min | 0.9 | 69 | $3.44 | $24.82 | 3.6 | 3.6 |
| bash | sonnet5-1m-high* | 6 | 18.2min | ≥30.0min | 15.3min | 4.3 | 94 | $4.96 | $31.61 | 3.7 | 3.6 |
| typescript-bun | sonnet5-1m-high | 7 | 21.1min | 25.3min | 18.5min | 3.6 | 122 | $5.62 | $39.95 | 4.3 | 4.1 |
| powershell | sonnet5-1m-high* | 9 | 24.9min | ≥30.0min | 21.4min | 1.1 | 87 | $4.52 | $41.97 | 4.3 | 4.4 |

</details>

<details>
<summary>Sorted by avg errors (fewest first)</summary>

| Language | Model | Runs | Geo Duration | Max Duration | Geo Duration Net of Traps | Avg Errors | Geo Turns | Geo Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| default | sonnet5-1m-low | 7 | 5.9min | 10.7min | 5.3min | 0.4 | 33 | $1.10 | $7.94 | 3.0 | 3.6 |
| powershell | sonnet5-1m-medium | 14 | 12.9min | 18.8min | 11.2min | 0.5 | 54 | $2.21 | $32.83 | 3.7 | 3.9 |
| powershell | sonnet5-1m-low | 9 | 8.5min | 15.4min | 7.5min | 0.6 | 29 | $1.20 | $11.16 | 2.8 | 2.8 |
| default | sonnet5-1m-high | 7 | 13.1min | 18.0min | 11.9min | 0.9 | 69 | $3.44 | $24.82 | 3.6 | 3.6 |
| powershell | sonnet5-1m-high* | 9 | 24.9min | ≥30.0min | 21.4min | 1.1 | 87 | $4.52 | $41.97 | 4.3 | 4.4 |
| default | sonnet5-1m-medium | 7 | 7.9min | 11.5min | 6.6min | 1.3 | 56 | $1.98 | $14.44 | 3.1 | 4.0 |
| typescript-bun | sonnet5-1m-medium | 7 | 12.8min | 17.0min | 9.4min | 1.4 | 82 | $2.64 | $18.75 | 3.1 | 3.8 |
| typescript-bun | sonnet5-1m-low | 7 | 7.8min | 12.0min | 5.2min | 1.6 | 32 | $1.07 | $9.28 | 2.1 | 2.7 |
| bash | sonnet5-1m-low | 7 | 7.1min | 13.7min | 5.3min | 2.4 | 15 | $0.59 | $5.58 | 2.9 | 3.5 |
| bash | sonnet5-1m-medium* | 6 | 11.9min | 16.9min | 8.8min | 3.3 | 73 | $2.77 | $17.14 | 3.8 | 3.3 |
| typescript-bun | sonnet5-1m-high | 7 | 21.1min | 25.3min | 18.5min | 3.6 | 122 | $5.62 | $39.95 | 4.3 | 4.1 |
| bash | sonnet5-1m-high* | 6 | 18.2min | ≥30.0min | 15.3min | 4.3 | 94 | $4.96 | $31.61 | 3.7 | 3.6 |

</details>

<details>
<summary>Sorted by turns (geomean, fewest first)</summary>

| Language | Model | Runs | Geo Duration | Max Duration | Geo Duration Net of Traps | Avg Errors | Geo Turns | Geo Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| bash | sonnet5-1m-low | 7 | 7.1min | 13.7min | 5.3min | 2.4 | 15 | $0.59 | $5.58 | 2.9 | 3.5 |
| powershell | sonnet5-1m-low | 9 | 8.5min | 15.4min | 7.5min | 0.6 | 29 | $1.20 | $11.16 | 2.8 | 2.8 |
| typescript-bun | sonnet5-1m-low | 7 | 7.8min | 12.0min | 5.2min | 1.6 | 32 | $1.07 | $9.28 | 2.1 | 2.7 |
| default | sonnet5-1m-low | 7 | 5.9min | 10.7min | 5.3min | 0.4 | 33 | $1.10 | $7.94 | 3.0 | 3.6 |
| powershell | sonnet5-1m-medium | 14 | 12.9min | 18.8min | 11.2min | 0.5 | 54 | $2.21 | $32.83 | 3.7 | 3.9 |
| default | sonnet5-1m-medium | 7 | 7.9min | 11.5min | 6.6min | 1.3 | 56 | $1.98 | $14.44 | 3.1 | 4.0 |
| default | sonnet5-1m-high | 7 | 13.1min | 18.0min | 11.9min | 0.9 | 69 | $3.44 | $24.82 | 3.6 | 3.6 |
| bash | sonnet5-1m-medium* | 6 | 11.9min | 16.9min | 8.8min | 3.3 | 73 | $2.77 | $17.14 | 3.8 | 3.3 |
| typescript-bun | sonnet5-1m-medium | 7 | 12.8min | 17.0min | 9.4min | 1.4 | 82 | $2.64 | $18.75 | 3.1 | 3.8 |
| powershell | sonnet5-1m-high* | 9 | 24.9min | ≥30.0min | 21.4min | 1.1 | 87 | $4.52 | $41.97 | 4.3 | 4.4 |
| bash | sonnet5-1m-high* | 6 | 18.2min | ≥30.0min | 15.3min | 4.3 | 94 | $4.96 | $31.61 | 3.7 | 3.6 |
| typescript-bun | sonnet5-1m-high | 7 | 21.1min | 25.3min | 18.5min | 3.6 | 122 | $5.62 | $39.95 | 4.3 | 4.1 |

</details>

<details>
<summary>Sorted by LLM-as-judge score (best first)</summary>

| Language | Model | Runs | Geo Duration | Max Duration | Geo Duration Net of Traps | Avg Errors | Geo Turns | Geo Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| powershell | sonnet5-1m-high* | 9 | 24.9min | ≥30.0min | 21.4min | 1.1 | 87 | $4.52 | $41.97 | 4.3 | 4.4 |
| typescript-bun | sonnet5-1m-high | 7 | 21.1min | 25.3min | 18.5min | 3.6 | 122 | $5.62 | $39.95 | 4.3 | 4.1 |
| bash | sonnet5-1m-medium* | 6 | 11.9min | 16.9min | 8.8min | 3.3 | 73 | $2.77 | $17.14 | 3.8 | 3.3 |
| powershell | sonnet5-1m-medium | 14 | 12.9min | 18.8min | 11.2min | 0.5 | 54 | $2.21 | $32.83 | 3.7 | 3.9 |
| bash | sonnet5-1m-high* | 6 | 18.2min | ≥30.0min | 15.3min | 4.3 | 94 | $4.96 | $31.61 | 3.7 | 3.6 |
| default | sonnet5-1m-high | 7 | 13.1min | 18.0min | 11.9min | 0.9 | 69 | $3.44 | $24.82 | 3.6 | 3.6 |
| typescript-bun | sonnet5-1m-medium | 7 | 12.8min | 17.0min | 9.4min | 1.4 | 82 | $2.64 | $18.75 | 3.1 | 3.8 |
| default | sonnet5-1m-medium | 7 | 7.9min | 11.5min | 6.6min | 1.3 | 56 | $1.98 | $14.44 | 3.1 | 4.0 |
| default | sonnet5-1m-low | 7 | 5.9min | 10.7min | 5.3min | 0.4 | 33 | $1.10 | $7.94 | 3.0 | 3.6 |
| bash | sonnet5-1m-low | 7 | 7.1min | 13.7min | 5.3min | 2.4 | 15 | $0.59 | $5.58 | 2.9 | 3.5 |
| powershell | sonnet5-1m-low | 9 | 8.5min | 15.4min | 7.5min | 0.6 | 29 | $1.20 | $11.16 | 2.8 | 2.8 |
| typescript-bun | sonnet5-1m-low | 7 | 7.8min | 12.0min | 5.2min | 1.6 | 32 | $1.07 | $9.28 | 2.1 | 2.7 |

</details>

<details>
<summary>Sorted by deliverable-quality score (best first)</summary>

| Language | Model | Runs | Geo Duration | Max Duration | Geo Duration Net of Traps | Avg Errors | Geo Turns | Geo Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| powershell | sonnet5-1m-high* | 9 | 24.9min | ≥30.0min | 21.4min | 1.1 | 87 | $4.52 | $41.97 | 4.3 | 4.4 |
| typescript-bun | sonnet5-1m-high | 7 | 21.1min | 25.3min | 18.5min | 3.6 | 122 | $5.62 | $39.95 | 4.3 | 4.1 |
| default | sonnet5-1m-medium | 7 | 7.9min | 11.5min | 6.6min | 1.3 | 56 | $1.98 | $14.44 | 3.1 | 4.0 |
| powershell | sonnet5-1m-medium | 14 | 12.9min | 18.8min | 11.2min | 0.5 | 54 | $2.21 | $32.83 | 3.7 | 3.9 |
| typescript-bun | sonnet5-1m-medium | 7 | 12.8min | 17.0min | 9.4min | 1.4 | 82 | $2.64 | $18.75 | 3.1 | 3.8 |
| bash | sonnet5-1m-high* | 6 | 18.2min | ≥30.0min | 15.3min | 4.3 | 94 | $4.96 | $31.61 | 3.7 | 3.6 |
| default | sonnet5-1m-high | 7 | 13.1min | 18.0min | 11.9min | 0.9 | 69 | $3.44 | $24.82 | 3.6 | 3.6 |
| default | sonnet5-1m-low | 7 | 5.9min | 10.7min | 5.3min | 0.4 | 33 | $1.10 | $7.94 | 3.0 | 3.6 |
| bash | sonnet5-1m-low | 7 | 7.1min | 13.7min | 5.3min | 2.4 | 15 | $0.59 | $5.58 | 2.9 | 3.5 |
| bash | sonnet5-1m-medium* | 6 | 11.9min | 16.9min | 8.8min | 3.3 | 73 | $2.77 | $17.14 | 3.8 | 3.3 |
| powershell | sonnet5-1m-low | 9 | 8.5min | 15.4min | 7.5min | 0.6 | 29 | $1.20 | $11.16 | 2.8 | 2.8 |
| typescript-bun | sonnet5-1m-low | 7 | 7.8min | 12.0min | 5.2min | 1.6 | 32 | $1.07 | $9.28 | 2.1 | 2.7 |

</details>

## Savings Analysis

### Trap Analysis by Language/Model/Effort/Category

| Trap | Language | Model | Fell In | Time Lost | % of Time | $ Lost | % of $ |
|------|------|-------|---------|-----------|-----------|--------|--------|
| repeated-test-reruns | bash | sonnet5-1m-high-cli2.1.197 | 4 | 5.3min | 0.4% | $1.63 | 0.64% |
| repeated-test-reruns | bash | sonnet5-1m-low-cli2.1.197 | 2 | 1.7min | 0.1% | $0.23 | 0.09% |
| repeated-test-reruns | bash | sonnet5-1m-low-cli2.1.198 | 1 | 2.3min | 0.2% | $0.02 | 0.01% |
| repeated-test-reruns | bash | sonnet5-1m-medium-cli2.1.197 | 6 | 7.0min | 0.5% | $1.63 | 0.64% |
| repeated-test-reruns | default | sonnet5-1m-high-cli2.1.197 | 3 | 7.0min | 0.5% | $1.79 | 0.70% |
| repeated-test-reruns | default | sonnet5-1m-low-cli2.1.197 | 2 | 2.0min | 0.1% | $0.46 | 0.18% |
| repeated-test-reruns | default | sonnet5-1m-low-cli2.1.198 | 1 | 1.7min | 0.1% | $0.28 | 0.11% |
| repeated-test-reruns | default | sonnet5-1m-medium-cli2.1.197 | 5 | 7.7min | 0.6% | $2.04 | 0.80% |
| repeated-test-reruns | powershell | sonnet5-1m-high-cli2.1.197 | 18 | 39.0min | 2.8% | $3.39 | 1.33% |
| repeated-test-reruns | powershell | sonnet5-1m-low-cli2.1.197 | 5 | 5.0min | 0.4% | $0.70 | 0.27% |
| repeated-test-reruns | powershell | sonnet5-1m-low-cli2.1.198 | 2 | 3.0min | 0.2% | $0.40 | 0.16% |
| repeated-test-reruns | powershell | sonnet5-1m-medium-cli2.1.197 | 10 | 17.7min | 1.3% | $3.31 | 1.30% |
| repeated-test-reruns | typescript-bun | sonnet5-1m-high-cli2.1.197 | 7 | 10.3min | 0.7% | $2.51 | 0.98% |
| repeated-test-reruns | typescript-bun | sonnet5-1m-low-cli2.1.197 | 2 | 1.7min | 0.1% | $0.36 | 0.14% |
| repeated-test-reruns | typescript-bun | sonnet5-1m-low-cli2.1.198 | 2 | 4.0min | 0.3% | $0.66 | 0.26% |
| repeated-test-reruns | typescript-bun | sonnet5-1m-medium-cli2.1.197 | 7 | 12.3min | 0.9% | $2.54 | 1.00% |
| act-push-debug-loops | bash | sonnet5-1m-high-cli2.1.197 | 2 | 5.1min | 0.4% | $1.56 | 0.61% |
| act-push-debug-loops | bash | sonnet5-1m-low-cli2.1.197 | 2 | 0.8min | 0.1% | $0.12 | 0.05% |
| act-push-debug-loops | bash | sonnet5-1m-low-cli2.1.198 | 2 | 3.5min | 0.3% | $0.27 | 0.10% |
| act-push-debug-loops | bash | sonnet5-1m-medium-cli2.1.197 | 1 | 0.7min | 0.1% | $0.14 | 0.06% |
| act-push-debug-loops | default | sonnet5-1m-high-cli2.1.197 | 1 | 1.7min | 0.1% | $0.47 | 0.18% |
| act-push-debug-loops | default | sonnet5-1m-medium-cli2.1.197 | 1 | 1.0min | 0.1% | $0.27 | 0.11% |
| act-push-debug-loops | powershell | sonnet5-1m-high-cli2.1.197 | 2 | 3.6min | 0.3% | $0.75 | 0.29% |
| act-push-debug-loops | powershell | sonnet5-1m-low-cli2.1.197 | 1 | 0.4min | 0.0% | $0.05 | 0.02% |
| act-push-debug-loops | powershell | sonnet5-1m-low-cli2.1.198 | 1 | 0.5min | 0.0% | $0.07 | 0.03% |
| act-push-debug-loops | powershell | sonnet5-1m-medium-cli2.1.197 | 4 | 2.6min | 0.2% | $0.49 | 0.19% |
| act-push-debug-loops | typescript-bun | sonnet5-1m-high-cli2.1.197 | 1 | 2.8min | 0.2% | $0.71 | 0.28% |
| act-push-debug-loops | typescript-bun | sonnet5-1m-low-cli2.1.197 | 1 | 2.0min | 0.1% | $0.33 | 0.13% |
| act-push-debug-loops | typescript-bun | sonnet5-1m-low-cli2.1.198 | 2 | 3.7min | 0.3% | $0.58 | 0.23% |
| act-push-debug-loops | typescript-bun | sonnet5-1m-medium-cli2.1.197 | 4 | 9.7min | 0.7% | $1.89 | 0.74% |
| fixture-rework | bash | sonnet5-1m-high-cli2.1.197 | 4 | 7.0min | 0.5% | $1.94 | 0.76% |
| fixture-rework | bash | sonnet5-1m-low-cli2.1.197 | 1 | 0.7min | 0.0% | $0.15 | 0.06% |
| fixture-rework | bash | sonnet5-1m-low-cli2.1.198 | 1 | 2.0min | 0.1% | $0.46 | 0.18% |
| fixture-rework | bash | sonnet5-1m-medium-cli2.1.197 | 2 | 9.0min | 0.6% | $2.44 | 0.95% |
| fixture-rework | default | sonnet5-1m-low-cli2.1.198 | 1 | 0.7min | 0.0% | $0.11 | 0.04% |
| fixture-rework | default | sonnet5-1m-medium-cli2.1.197 | 1 | 1.0min | 0.1% | $0.28 | 0.11% |
| fixture-rework | powershell | sonnet5-1m-high-cli2.1.197 | 2 | 4.0min | 0.3% | $0.20 | 0.08% |
| fixture-rework | powershell | sonnet5-1m-medium-cli2.1.197 | 2 | 4.0min | 0.3% | $0.75 | 0.30% |
| fixture-rework | typescript-bun | sonnet5-1m-high-cli2.1.197 | 1 | 3.3min | 0.2% | $0.96 | 0.38% |
| fixture-rework | typescript-bun | sonnet5-1m-low-cli2.1.197 | 2 | 4.0min | 0.3% | $0.70 | 0.27% |
| fixture-rework | typescript-bun | sonnet5-1m-low-cli2.1.198 | 1 | 0.7min | 0.0% | $0.15 | 0.06% |
| fixture-rework | typescript-bun | sonnet5-1m-medium-cli2.1.197 | 1 | 0.7min | 0.0% | $0.13 | 0.05% |
| docker-pwsh-install | powershell | sonnet5-1m-high-cli2.1.197 | 2 | 3.8min | 0.3% | $0.72 | 0.28% |
| bats-setup-issues | bash | sonnet5-1m-high-cli2.1.197 | 2 | 1.8min | 0.1% | $0.53 | 0.21% |
| bats-setup-issues | bash | sonnet5-1m-medium-cli2.1.197 | 1 | 0.8min | 0.1% | $0.23 | 0.09% |
| actionlint-fix-cycles | powershell | sonnet5-1m-medium-cli2.1.197 | 1 | 0.7min | 0.0% | $0.13 | 0.05% |
| actionlint-fix-cycles | typescript-bun | sonnet5-1m-high-cli2.1.197 | 2 | 1.7min | 0.1% | $0.39 | 0.15% |


<details>
<summary>Sorted by time lost (least first)</summary>

| Trap | Language | Model | Fell In | Time Lost | % of Time | $ Lost | % of $ |
|------|------|-------|---------|-----------|-----------|--------|--------|
| act-push-debug-loops | powershell | sonnet5-1m-low-cli2.1.197 | 1 | 0.4min | 0.0% | $0.05 | 0.02% |
| act-push-debug-loops | powershell | sonnet5-1m-low-cli2.1.198 | 1 | 0.5min | 0.0% | $0.07 | 0.03% |
| fixture-rework | bash | sonnet5-1m-low-cli2.1.197 | 1 | 0.7min | 0.0% | $0.15 | 0.06% |
| fixture-rework | default | sonnet5-1m-low-cli2.1.198 | 1 | 0.7min | 0.0% | $0.11 | 0.04% |
| fixture-rework | typescript-bun | sonnet5-1m-low-cli2.1.198 | 1 | 0.7min | 0.0% | $0.15 | 0.06% |
| fixture-rework | typescript-bun | sonnet5-1m-medium-cli2.1.197 | 1 | 0.7min | 0.0% | $0.13 | 0.05% |
| actionlint-fix-cycles | powershell | sonnet5-1m-medium-cli2.1.197 | 1 | 0.7min | 0.0% | $0.13 | 0.05% |
| act-push-debug-loops | bash | sonnet5-1m-medium-cli2.1.197 | 1 | 0.7min | 0.1% | $0.14 | 0.06% |
| bats-setup-issues | bash | sonnet5-1m-medium-cli2.1.197 | 1 | 0.8min | 0.1% | $0.23 | 0.09% |
| act-push-debug-loops | bash | sonnet5-1m-low-cli2.1.197 | 2 | 0.8min | 0.1% | $0.12 | 0.05% |
| fixture-rework | default | sonnet5-1m-medium-cli2.1.197 | 1 | 1.0min | 0.1% | $0.28 | 0.11% |
| act-push-debug-loops | default | sonnet5-1m-medium-cli2.1.197 | 1 | 1.0min | 0.1% | $0.27 | 0.11% |
| repeated-test-reruns | bash | sonnet5-1m-low-cli2.1.197 | 2 | 1.7min | 0.1% | $0.23 | 0.09% |
| repeated-test-reruns | default | sonnet5-1m-low-cli2.1.198 | 1 | 1.7min | 0.1% | $0.28 | 0.11% |
| repeated-test-reruns | typescript-bun | sonnet5-1m-low-cli2.1.197 | 2 | 1.7min | 0.1% | $0.36 | 0.14% |
| act-push-debug-loops | default | sonnet5-1m-high-cli2.1.197 | 1 | 1.7min | 0.1% | $0.47 | 0.18% |
| actionlint-fix-cycles | typescript-bun | sonnet5-1m-high-cli2.1.197 | 2 | 1.7min | 0.1% | $0.39 | 0.15% |
| bats-setup-issues | bash | sonnet5-1m-high-cli2.1.197 | 2 | 1.8min | 0.1% | $0.53 | 0.21% |
| repeated-test-reruns | default | sonnet5-1m-low-cli2.1.197 | 2 | 2.0min | 0.1% | $0.46 | 0.18% |
| fixture-rework | bash | sonnet5-1m-low-cli2.1.198 | 1 | 2.0min | 0.1% | $0.46 | 0.18% |
| act-push-debug-loops | typescript-bun | sonnet5-1m-low-cli2.1.197 | 1 | 2.0min | 0.1% | $0.33 | 0.13% |
| repeated-test-reruns | bash | sonnet5-1m-low-cli2.1.198 | 1 | 2.3min | 0.2% | $0.02 | 0.01% |
| act-push-debug-loops | powershell | sonnet5-1m-medium-cli2.1.197 | 4 | 2.6min | 0.2% | $0.49 | 0.19% |
| act-push-debug-loops | typescript-bun | sonnet5-1m-high-cli2.1.197 | 1 | 2.8min | 0.2% | $0.71 | 0.28% |
| repeated-test-reruns | powershell | sonnet5-1m-low-cli2.1.198 | 2 | 3.0min | 0.2% | $0.40 | 0.16% |
| fixture-rework | typescript-bun | sonnet5-1m-high-cli2.1.197 | 1 | 3.3min | 0.2% | $0.96 | 0.38% |
| act-push-debug-loops | bash | sonnet5-1m-low-cli2.1.198 | 2 | 3.5min | 0.3% | $0.27 | 0.10% |
| act-push-debug-loops | powershell | sonnet5-1m-high-cli2.1.197 | 2 | 3.6min | 0.3% | $0.75 | 0.29% |
| act-push-debug-loops | typescript-bun | sonnet5-1m-low-cli2.1.198 | 2 | 3.7min | 0.3% | $0.58 | 0.23% |
| docker-pwsh-install | powershell | sonnet5-1m-high-cli2.1.197 | 2 | 3.8min | 0.3% | $0.72 | 0.28% |
| repeated-test-reruns | typescript-bun | sonnet5-1m-low-cli2.1.198 | 2 | 4.0min | 0.3% | $0.66 | 0.26% |
| fixture-rework | powershell | sonnet5-1m-high-cli2.1.197 | 2 | 4.0min | 0.3% | $0.20 | 0.08% |
| fixture-rework | powershell | sonnet5-1m-medium-cli2.1.197 | 2 | 4.0min | 0.3% | $0.75 | 0.30% |
| fixture-rework | typescript-bun | sonnet5-1m-low-cli2.1.197 | 2 | 4.0min | 0.3% | $0.70 | 0.27% |
| repeated-test-reruns | powershell | sonnet5-1m-low-cli2.1.197 | 5 | 5.0min | 0.4% | $0.70 | 0.27% |
| act-push-debug-loops | bash | sonnet5-1m-high-cli2.1.197 | 2 | 5.1min | 0.4% | $1.56 | 0.61% |
| repeated-test-reruns | bash | sonnet5-1m-high-cli2.1.197 | 4 | 5.3min | 0.4% | $1.63 | 0.64% |
| repeated-test-reruns | bash | sonnet5-1m-medium-cli2.1.197 | 6 | 7.0min | 0.5% | $1.63 | 0.64% |
| repeated-test-reruns | default | sonnet5-1m-high-cli2.1.197 | 3 | 7.0min | 0.5% | $1.79 | 0.70% |
| fixture-rework | bash | sonnet5-1m-high-cli2.1.197 | 4 | 7.0min | 0.5% | $1.94 | 0.76% |
| repeated-test-reruns | default | sonnet5-1m-medium-cli2.1.197 | 5 | 7.7min | 0.6% | $2.04 | 0.80% |
| fixture-rework | bash | sonnet5-1m-medium-cli2.1.197 | 2 | 9.0min | 0.6% | $2.44 | 0.95% |
| act-push-debug-loops | typescript-bun | sonnet5-1m-medium-cli2.1.197 | 4 | 9.7min | 0.7% | $1.89 | 0.74% |
| repeated-test-reruns | typescript-bun | sonnet5-1m-high-cli2.1.197 | 7 | 10.3min | 0.7% | $2.51 | 0.98% |
| repeated-test-reruns | typescript-bun | sonnet5-1m-medium-cli2.1.197 | 7 | 12.3min | 0.9% | $2.54 | 1.00% |
| repeated-test-reruns | powershell | sonnet5-1m-medium-cli2.1.197 | 10 | 17.7min | 1.3% | $3.31 | 1.30% |
| repeated-test-reruns | powershell | sonnet5-1m-high-cli2.1.197 | 18 | 39.0min | 2.8% | $3.39 | 1.33% |

</details>

<details>
<summary>Sorted by $ lost (least first)</summary>

| Trap | Language | Model | Fell In | Time Lost | % of Time | $ Lost | % of $ |
|------|------|-------|---------|-----------|-----------|--------|--------|
| repeated-test-reruns | bash | sonnet5-1m-low-cli2.1.198 | 1 | 2.3min | 0.2% | $0.02 | 0.01% |
| act-push-debug-loops | powershell | sonnet5-1m-low-cli2.1.197 | 1 | 0.4min | 0.0% | $0.05 | 0.02% |
| act-push-debug-loops | powershell | sonnet5-1m-low-cli2.1.198 | 1 | 0.5min | 0.0% | $0.07 | 0.03% |
| fixture-rework | default | sonnet5-1m-low-cli2.1.198 | 1 | 0.7min | 0.0% | $0.11 | 0.04% |
| act-push-debug-loops | bash | sonnet5-1m-low-cli2.1.197 | 2 | 0.8min | 0.1% | $0.12 | 0.05% |
| fixture-rework | typescript-bun | sonnet5-1m-medium-cli2.1.197 | 1 | 0.7min | 0.0% | $0.13 | 0.05% |
| actionlint-fix-cycles | powershell | sonnet5-1m-medium-cli2.1.197 | 1 | 0.7min | 0.0% | $0.13 | 0.05% |
| act-push-debug-loops | bash | sonnet5-1m-medium-cli2.1.197 | 1 | 0.7min | 0.1% | $0.14 | 0.06% |
| fixture-rework | typescript-bun | sonnet5-1m-low-cli2.1.198 | 1 | 0.7min | 0.0% | $0.15 | 0.06% |
| fixture-rework | bash | sonnet5-1m-low-cli2.1.197 | 1 | 0.7min | 0.0% | $0.15 | 0.06% |
| fixture-rework | powershell | sonnet5-1m-high-cli2.1.197 | 2 | 4.0min | 0.3% | $0.20 | 0.08% |
| repeated-test-reruns | bash | sonnet5-1m-low-cli2.1.197 | 2 | 1.7min | 0.1% | $0.23 | 0.09% |
| bats-setup-issues | bash | sonnet5-1m-medium-cli2.1.197 | 1 | 0.8min | 0.1% | $0.23 | 0.09% |
| act-push-debug-loops | bash | sonnet5-1m-low-cli2.1.198 | 2 | 3.5min | 0.3% | $0.27 | 0.10% |
| act-push-debug-loops | default | sonnet5-1m-medium-cli2.1.197 | 1 | 1.0min | 0.1% | $0.27 | 0.11% |
| repeated-test-reruns | default | sonnet5-1m-low-cli2.1.198 | 1 | 1.7min | 0.1% | $0.28 | 0.11% |
| fixture-rework | default | sonnet5-1m-medium-cli2.1.197 | 1 | 1.0min | 0.1% | $0.28 | 0.11% |
| act-push-debug-loops | typescript-bun | sonnet5-1m-low-cli2.1.197 | 1 | 2.0min | 0.1% | $0.33 | 0.13% |
| repeated-test-reruns | typescript-bun | sonnet5-1m-low-cli2.1.197 | 2 | 1.7min | 0.1% | $0.36 | 0.14% |
| actionlint-fix-cycles | typescript-bun | sonnet5-1m-high-cli2.1.197 | 2 | 1.7min | 0.1% | $0.39 | 0.15% |
| repeated-test-reruns | powershell | sonnet5-1m-low-cli2.1.198 | 2 | 3.0min | 0.2% | $0.40 | 0.16% |
| fixture-rework | bash | sonnet5-1m-low-cli2.1.198 | 1 | 2.0min | 0.1% | $0.46 | 0.18% |
| repeated-test-reruns | default | sonnet5-1m-low-cli2.1.197 | 2 | 2.0min | 0.1% | $0.46 | 0.18% |
| act-push-debug-loops | default | sonnet5-1m-high-cli2.1.197 | 1 | 1.7min | 0.1% | $0.47 | 0.18% |
| act-push-debug-loops | powershell | sonnet5-1m-medium-cli2.1.197 | 4 | 2.6min | 0.2% | $0.49 | 0.19% |
| bats-setup-issues | bash | sonnet5-1m-high-cli2.1.197 | 2 | 1.8min | 0.1% | $0.53 | 0.21% |
| act-push-debug-loops | typescript-bun | sonnet5-1m-low-cli2.1.198 | 2 | 3.7min | 0.3% | $0.58 | 0.23% |
| repeated-test-reruns | typescript-bun | sonnet5-1m-low-cli2.1.198 | 2 | 4.0min | 0.3% | $0.66 | 0.26% |
| repeated-test-reruns | powershell | sonnet5-1m-low-cli2.1.197 | 5 | 5.0min | 0.4% | $0.70 | 0.27% |
| fixture-rework | typescript-bun | sonnet5-1m-low-cli2.1.197 | 2 | 4.0min | 0.3% | $0.70 | 0.27% |
| act-push-debug-loops | typescript-bun | sonnet5-1m-high-cli2.1.197 | 1 | 2.8min | 0.2% | $0.71 | 0.28% |
| docker-pwsh-install | powershell | sonnet5-1m-high-cli2.1.197 | 2 | 3.8min | 0.3% | $0.72 | 0.28% |
| act-push-debug-loops | powershell | sonnet5-1m-high-cli2.1.197 | 2 | 3.6min | 0.3% | $0.75 | 0.29% |
| fixture-rework | powershell | sonnet5-1m-medium-cli2.1.197 | 2 | 4.0min | 0.3% | $0.75 | 0.30% |
| fixture-rework | typescript-bun | sonnet5-1m-high-cli2.1.197 | 1 | 3.3min | 0.2% | $0.96 | 0.38% |
| act-push-debug-loops | bash | sonnet5-1m-high-cli2.1.197 | 2 | 5.1min | 0.4% | $1.56 | 0.61% |
| repeated-test-reruns | bash | sonnet5-1m-medium-cli2.1.197 | 6 | 7.0min | 0.5% | $1.63 | 0.64% |
| repeated-test-reruns | bash | sonnet5-1m-high-cli2.1.197 | 4 | 5.3min | 0.4% | $1.63 | 0.64% |
| repeated-test-reruns | default | sonnet5-1m-high-cli2.1.197 | 3 | 7.0min | 0.5% | $1.79 | 0.70% |
| act-push-debug-loops | typescript-bun | sonnet5-1m-medium-cli2.1.197 | 4 | 9.7min | 0.7% | $1.89 | 0.74% |
| fixture-rework | bash | sonnet5-1m-high-cli2.1.197 | 4 | 7.0min | 0.5% | $1.94 | 0.76% |
| repeated-test-reruns | default | sonnet5-1m-medium-cli2.1.197 | 5 | 7.7min | 0.6% | $2.04 | 0.80% |
| fixture-rework | bash | sonnet5-1m-medium-cli2.1.197 | 2 | 9.0min | 0.6% | $2.44 | 0.95% |
| repeated-test-reruns | typescript-bun | sonnet5-1m-high-cli2.1.197 | 7 | 10.3min | 0.7% | $2.51 | 0.98% |
| repeated-test-reruns | typescript-bun | sonnet5-1m-medium-cli2.1.197 | 7 | 12.3min | 0.9% | $2.54 | 1.00% |
| repeated-test-reruns | powershell | sonnet5-1m-medium-cli2.1.197 | 10 | 17.7min | 1.3% | $3.31 | 1.30% |
| repeated-test-reruns | powershell | sonnet5-1m-high-cli2.1.197 | 18 | 39.0min | 2.8% | $3.39 | 1.33% |

</details>

<details>
<summary>Sorted by fell-in count (fewest first)</summary>

| Trap | Language | Model | Fell In | Time Lost | % of Time | $ Lost | % of $ |
|------|------|-------|---------|-----------|-----------|--------|--------|
| repeated-test-reruns | bash | sonnet5-1m-low-cli2.1.198 | 1 | 2.3min | 0.2% | $0.02 | 0.01% |
| repeated-test-reruns | default | sonnet5-1m-low-cli2.1.198 | 1 | 1.7min | 0.1% | $0.28 | 0.11% |
| act-push-debug-loops | bash | sonnet5-1m-medium-cli2.1.197 | 1 | 0.7min | 0.1% | $0.14 | 0.06% |
| act-push-debug-loops | default | sonnet5-1m-high-cli2.1.197 | 1 | 1.7min | 0.1% | $0.47 | 0.18% |
| act-push-debug-loops | default | sonnet5-1m-medium-cli2.1.197 | 1 | 1.0min | 0.1% | $0.27 | 0.11% |
| act-push-debug-loops | powershell | sonnet5-1m-low-cli2.1.197 | 1 | 0.4min | 0.0% | $0.05 | 0.02% |
| act-push-debug-loops | powershell | sonnet5-1m-low-cli2.1.198 | 1 | 0.5min | 0.0% | $0.07 | 0.03% |
| act-push-debug-loops | typescript-bun | sonnet5-1m-high-cli2.1.197 | 1 | 2.8min | 0.2% | $0.71 | 0.28% |
| act-push-debug-loops | typescript-bun | sonnet5-1m-low-cli2.1.197 | 1 | 2.0min | 0.1% | $0.33 | 0.13% |
| fixture-rework | bash | sonnet5-1m-low-cli2.1.197 | 1 | 0.7min | 0.0% | $0.15 | 0.06% |
| fixture-rework | bash | sonnet5-1m-low-cli2.1.198 | 1 | 2.0min | 0.1% | $0.46 | 0.18% |
| fixture-rework | default | sonnet5-1m-low-cli2.1.198 | 1 | 0.7min | 0.0% | $0.11 | 0.04% |
| fixture-rework | default | sonnet5-1m-medium-cli2.1.197 | 1 | 1.0min | 0.1% | $0.28 | 0.11% |
| fixture-rework | typescript-bun | sonnet5-1m-high-cli2.1.197 | 1 | 3.3min | 0.2% | $0.96 | 0.38% |
| fixture-rework | typescript-bun | sonnet5-1m-low-cli2.1.198 | 1 | 0.7min | 0.0% | $0.15 | 0.06% |
| fixture-rework | typescript-bun | sonnet5-1m-medium-cli2.1.197 | 1 | 0.7min | 0.0% | $0.13 | 0.05% |
| bats-setup-issues | bash | sonnet5-1m-medium-cli2.1.197 | 1 | 0.8min | 0.1% | $0.23 | 0.09% |
| actionlint-fix-cycles | powershell | sonnet5-1m-medium-cli2.1.197 | 1 | 0.7min | 0.0% | $0.13 | 0.05% |
| repeated-test-reruns | bash | sonnet5-1m-low-cli2.1.197 | 2 | 1.7min | 0.1% | $0.23 | 0.09% |
| repeated-test-reruns | default | sonnet5-1m-low-cli2.1.197 | 2 | 2.0min | 0.1% | $0.46 | 0.18% |
| repeated-test-reruns | powershell | sonnet5-1m-low-cli2.1.198 | 2 | 3.0min | 0.2% | $0.40 | 0.16% |
| repeated-test-reruns | typescript-bun | sonnet5-1m-low-cli2.1.197 | 2 | 1.7min | 0.1% | $0.36 | 0.14% |
| repeated-test-reruns | typescript-bun | sonnet5-1m-low-cli2.1.198 | 2 | 4.0min | 0.3% | $0.66 | 0.26% |
| act-push-debug-loops | bash | sonnet5-1m-high-cli2.1.197 | 2 | 5.1min | 0.4% | $1.56 | 0.61% |
| act-push-debug-loops | bash | sonnet5-1m-low-cli2.1.197 | 2 | 0.8min | 0.1% | $0.12 | 0.05% |
| act-push-debug-loops | bash | sonnet5-1m-low-cli2.1.198 | 2 | 3.5min | 0.3% | $0.27 | 0.10% |
| act-push-debug-loops | powershell | sonnet5-1m-high-cli2.1.197 | 2 | 3.6min | 0.3% | $0.75 | 0.29% |
| act-push-debug-loops | typescript-bun | sonnet5-1m-low-cli2.1.198 | 2 | 3.7min | 0.3% | $0.58 | 0.23% |
| fixture-rework | bash | sonnet5-1m-medium-cli2.1.197 | 2 | 9.0min | 0.6% | $2.44 | 0.95% |
| fixture-rework | powershell | sonnet5-1m-high-cli2.1.197 | 2 | 4.0min | 0.3% | $0.20 | 0.08% |
| fixture-rework | powershell | sonnet5-1m-medium-cli2.1.197 | 2 | 4.0min | 0.3% | $0.75 | 0.30% |
| fixture-rework | typescript-bun | sonnet5-1m-low-cli2.1.197 | 2 | 4.0min | 0.3% | $0.70 | 0.27% |
| docker-pwsh-install | powershell | sonnet5-1m-high-cli2.1.197 | 2 | 3.8min | 0.3% | $0.72 | 0.28% |
| bats-setup-issues | bash | sonnet5-1m-high-cli2.1.197 | 2 | 1.8min | 0.1% | $0.53 | 0.21% |
| actionlint-fix-cycles | typescript-bun | sonnet5-1m-high-cli2.1.197 | 2 | 1.7min | 0.1% | $0.39 | 0.15% |
| repeated-test-reruns | default | sonnet5-1m-high-cli2.1.197 | 3 | 7.0min | 0.5% | $1.79 | 0.70% |
| repeated-test-reruns | bash | sonnet5-1m-high-cli2.1.197 | 4 | 5.3min | 0.4% | $1.63 | 0.64% |
| act-push-debug-loops | powershell | sonnet5-1m-medium-cli2.1.197 | 4 | 2.6min | 0.2% | $0.49 | 0.19% |
| act-push-debug-loops | typescript-bun | sonnet5-1m-medium-cli2.1.197 | 4 | 9.7min | 0.7% | $1.89 | 0.74% |
| fixture-rework | bash | sonnet5-1m-high-cli2.1.197 | 4 | 7.0min | 0.5% | $1.94 | 0.76% |
| repeated-test-reruns | default | sonnet5-1m-medium-cli2.1.197 | 5 | 7.7min | 0.6% | $2.04 | 0.80% |
| repeated-test-reruns | powershell | sonnet5-1m-low-cli2.1.197 | 5 | 5.0min | 0.4% | $0.70 | 0.27% |
| repeated-test-reruns | bash | sonnet5-1m-medium-cli2.1.197 | 6 | 7.0min | 0.5% | $1.63 | 0.64% |
| repeated-test-reruns | typescript-bun | sonnet5-1m-high-cli2.1.197 | 7 | 10.3min | 0.7% | $2.51 | 0.98% |
| repeated-test-reruns | typescript-bun | sonnet5-1m-medium-cli2.1.197 | 7 | 12.3min | 0.9% | $2.54 | 1.00% |
| repeated-test-reruns | powershell | sonnet5-1m-medium-cli2.1.197 | 10 | 17.7min | 1.3% | $3.31 | 1.30% |
| repeated-test-reruns | powershell | sonnet5-1m-high-cli2.1.197 | 18 | 39.0min | 2.8% | $3.39 | 1.33% |

</details>

#### Trap Descriptions

- **act-push-debug-loops**: Agent ran `act push` more than twice, indicating repeated workflow debugging.
- **actionlint-fix-cycles**: Workflow YAML required 3+ actionlint runs and 2+ fixes to pass.
- **bats-setup-issues**: Agent struggled with bats-core test framework setup or load helpers.
- **docker-pwsh-install**: Multiple Docker test runs trying to figure out how to install PowerShell in act's container.
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
| bash | sonnet5-1m-high-cli2.1.197 | 7 | 12 | 19.2min | 1.4% | $5.66 | 2.22% |
| bash | sonnet5-1m-low-cli2.1.197 | 4 | 5 | 3.1min | 0.2% | $0.50 | 0.19% |
| bash | sonnet5-1m-low-cli2.1.198 | 3 | 4 | 7.9min | 0.6% | $0.75 | 0.29% |
| bash | sonnet5-1m-medium-cli2.1.197 | 7 | 10 | 17.4min | 1.3% | $4.44 | 1.74% |
| default | sonnet5-1m-high-cli2.1.197 | 7 | 4 | 8.7min | 0.6% | $2.26 | 0.89% |
| default | sonnet5-1m-low-cli2.1.197 | 5 | 2 | 2.0min | 0.1% | $0.46 | 0.18% |
| default | sonnet5-1m-low-cli2.1.198 | 2 | 2 | 2.3min | 0.2% | $0.39 | 0.15% |
| default | sonnet5-1m-medium-cli2.1.197 | 7 | 7 | 9.7min | 0.7% | $2.59 | 1.01% |
| powershell | sonnet5-1m-high-cli2.1.197 | 14 | 24 | 50.4min | 3.6% | $5.07 | 1.98% |
| powershell | sonnet5-1m-low-cli2.1.197 | 6 | 6 | 5.4min | 0.4% | $0.75 | 0.29% |
| powershell | sonnet5-1m-low-cli2.1.198 | 3 | 3 | 3.5min | 0.3% | $0.48 | 0.19% |
| powershell | sonnet5-1m-medium-cli2.1.197 | 14 | 17 | 24.9min | 1.8% | $4.69 | 1.84% |
| typescript-bun | sonnet5-1m-high-cli2.1.197 | 7 | 11 | 18.2min | 1.3% | $4.57 | 1.79% |
| typescript-bun | sonnet5-1m-low-cli2.1.197 | 4 | 5 | 7.7min | 0.6% | $1.39 | 0.55% |
| typescript-bun | sonnet5-1m-low-cli2.1.198 | 3 | 5 | 8.3min | 0.6% | $1.39 | 0.54% |
| typescript-bun | sonnet5-1m-medium-cli2.1.197 | 7 | 12 | 22.7min | 1.6% | $4.57 | 1.79% |


<details>
<summary>Sorted by time lost (least first)</summary>

| Language | Model | Runs | Traps | Time Lost | % of Time | $ Lost | % of $ |
|------|-------|------|-------|-----------|-----------|--------|--------|
| default | sonnet5-1m-low-cli2.1.197 | 5 | 2 | 2.0min | 0.1% | $0.46 | 0.18% |
| default | sonnet5-1m-low-cli2.1.198 | 2 | 2 | 2.3min | 0.2% | $0.39 | 0.15% |
| bash | sonnet5-1m-low-cli2.1.197 | 4 | 5 | 3.1min | 0.2% | $0.50 | 0.19% |
| powershell | sonnet5-1m-low-cli2.1.198 | 3 | 3 | 3.5min | 0.3% | $0.48 | 0.19% |
| powershell | sonnet5-1m-low-cli2.1.197 | 6 | 6 | 5.4min | 0.4% | $0.75 | 0.29% |
| typescript-bun | sonnet5-1m-low-cli2.1.197 | 4 | 5 | 7.7min | 0.6% | $1.39 | 0.55% |
| bash | sonnet5-1m-low-cli2.1.198 | 3 | 4 | 7.9min | 0.6% | $0.75 | 0.29% |
| typescript-bun | sonnet5-1m-low-cli2.1.198 | 3 | 5 | 8.3min | 0.6% | $1.39 | 0.54% |
| default | sonnet5-1m-high-cli2.1.197 | 7 | 4 | 8.7min | 0.6% | $2.26 | 0.89% |
| default | sonnet5-1m-medium-cli2.1.197 | 7 | 7 | 9.7min | 0.7% | $2.59 | 1.01% |
| bash | sonnet5-1m-medium-cli2.1.197 | 7 | 10 | 17.4min | 1.3% | $4.44 | 1.74% |
| typescript-bun | sonnet5-1m-high-cli2.1.197 | 7 | 11 | 18.2min | 1.3% | $4.57 | 1.79% |
| bash | sonnet5-1m-high-cli2.1.197 | 7 | 12 | 19.2min | 1.4% | $5.66 | 2.22% |
| typescript-bun | sonnet5-1m-medium-cli2.1.197 | 7 | 12 | 22.7min | 1.6% | $4.57 | 1.79% |
| powershell | sonnet5-1m-medium-cli2.1.197 | 14 | 17 | 24.9min | 1.8% | $4.69 | 1.84% |
| powershell | sonnet5-1m-high-cli2.1.197 | 14 | 24 | 50.4min | 3.6% | $5.07 | 1.98% |

</details>

<details>
<summary>Sorted by $ lost (least first)</summary>

| Language | Model | Runs | Traps | Time Lost | % of Time | $ Lost | % of $ |
|------|-------|------|-------|-----------|-----------|--------|--------|
| default | sonnet5-1m-low-cli2.1.198 | 2 | 2 | 2.3min | 0.2% | $0.39 | 0.15% |
| default | sonnet5-1m-low-cli2.1.197 | 5 | 2 | 2.0min | 0.1% | $0.46 | 0.18% |
| powershell | sonnet5-1m-low-cli2.1.198 | 3 | 3 | 3.5min | 0.3% | $0.48 | 0.19% |
| bash | sonnet5-1m-low-cli2.1.197 | 4 | 5 | 3.1min | 0.2% | $0.50 | 0.19% |
| powershell | sonnet5-1m-low-cli2.1.197 | 6 | 6 | 5.4min | 0.4% | $0.75 | 0.29% |
| bash | sonnet5-1m-low-cli2.1.198 | 3 | 4 | 7.9min | 0.6% | $0.75 | 0.29% |
| typescript-bun | sonnet5-1m-low-cli2.1.198 | 3 | 5 | 8.3min | 0.6% | $1.39 | 0.54% |
| typescript-bun | sonnet5-1m-low-cli2.1.197 | 4 | 5 | 7.7min | 0.6% | $1.39 | 0.55% |
| default | sonnet5-1m-high-cli2.1.197 | 7 | 4 | 8.7min | 0.6% | $2.26 | 0.89% |
| default | sonnet5-1m-medium-cli2.1.197 | 7 | 7 | 9.7min | 0.7% | $2.59 | 1.01% |
| bash | sonnet5-1m-medium-cli2.1.197 | 7 | 10 | 17.4min | 1.3% | $4.44 | 1.74% |
| typescript-bun | sonnet5-1m-medium-cli2.1.197 | 7 | 12 | 22.7min | 1.6% | $4.57 | 1.79% |
| typescript-bun | sonnet5-1m-high-cli2.1.197 | 7 | 11 | 18.2min | 1.3% | $4.57 | 1.79% |
| powershell | sonnet5-1m-medium-cli2.1.197 | 14 | 17 | 24.9min | 1.8% | $4.69 | 1.84% |
| powershell | sonnet5-1m-high-cli2.1.197 | 14 | 24 | 50.4min | 3.6% | $5.07 | 1.98% |
| bash | sonnet5-1m-high-cli2.1.197 | 7 | 12 | 19.2min | 1.4% | $5.66 | 2.22% |

</details>

### Prompt Cache Savings

| Status | Runs | $ Saved | % of $ |
|--------|------|---------|--------|
| Full hit (100%) | 0 | $0.00 | 0.00% |
| Partial | 97 | $8.78 | 3.44% |
| Miss | 3 | $0.00 | 0.00% |

## Test Quality Evaluation

### Structural Metrics by Language/Model/Effort

Automated analysis of test files: test count, assertion count, and test-to-code line ratio.

| Language | Model | Avg Tests | Avg Assertions | Avg Assert/Test | Avg Test:Code Ratio |
|------|-------|-----------|----------------|-----------------|---------------------|
| bash | sonnet5-1m-high | 34.4 | 73.3 | 2.1 | 0.89 |
| bash | sonnet5-1m-low | 22.9 | 52.0 | 2.3 | 0.96 |
| bash | sonnet5-1m-medium | 27.6 | 71.3 | 2.6 | 1.22 |
| default | sonnet5-1m-high | 22.0 | 41.1 | 1.9 | 0.86 |
| default | sonnet5-1m-low | 22.0 | 37.4 | 1.7 | 1.19 |
| default | sonnet5-1m-medium | 32.9 | 56.1 | 1.7 | 1.26 |
| powershell | sonnet5-1m-high | 47.6 | 88.1 | 1.9 | 5.65 |
| powershell | sonnet5-1m-low | 23.1 | 42.9 | 1.9 | 4.30 |
| powershell | sonnet5-1m-medium | 32.2 | 57.1 | 1.8 | 2.93 |
| typescript-bun | sonnet5-1m-high | 45.1 | 83.9 | 1.9 | 1.57 |
| typescript-bun | sonnet5-1m-low | 18.4 | 37.6 | 2.0 | 0.96 |
| typescript-bun | sonnet5-1m-medium | 27.3 | 51.6 | 1.9 | 1.12 |


<details>
<summary>Sorted by avg tests (most first)</summary>

| Language | Model | Avg Tests | Avg Assertions | Avg Assert/Test | Avg Test:Code Ratio |
|------|-------|-----------|----------------|-----------------|---------------------|
| powershell | sonnet5-1m-high | 47.6 | 88.1 | 1.9 | 5.65 |
| typescript-bun | sonnet5-1m-high | 45.1 | 83.9 | 1.9 | 1.57 |
| bash | sonnet5-1m-high | 34.4 | 73.3 | 2.1 | 0.89 |
| default | sonnet5-1m-medium | 32.9 | 56.1 | 1.7 | 1.26 |
| powershell | sonnet5-1m-medium | 32.2 | 57.1 | 1.8 | 2.93 |
| bash | sonnet5-1m-medium | 27.6 | 71.3 | 2.6 | 1.22 |
| typescript-bun | sonnet5-1m-medium | 27.3 | 51.6 | 1.9 | 1.12 |
| powershell | sonnet5-1m-low | 23.1 | 42.9 | 1.9 | 4.30 |
| bash | sonnet5-1m-low | 22.9 | 52.0 | 2.3 | 0.96 |
| default | sonnet5-1m-high | 22.0 | 41.1 | 1.9 | 0.86 |
| default | sonnet5-1m-low | 22.0 | 37.4 | 1.7 | 1.19 |
| typescript-bun | sonnet5-1m-low | 18.4 | 37.6 | 2.0 | 0.96 |

</details>

<details>
<summary>Sorted by avg assertions (most first)</summary>

| Language | Model | Avg Tests | Avg Assertions | Avg Assert/Test | Avg Test:Code Ratio |
|------|-------|-----------|----------------|-----------------|---------------------|
| powershell | sonnet5-1m-high | 47.6 | 88.1 | 1.9 | 5.65 |
| typescript-bun | sonnet5-1m-high | 45.1 | 83.9 | 1.9 | 1.57 |
| bash | sonnet5-1m-high | 34.4 | 73.3 | 2.1 | 0.89 |
| bash | sonnet5-1m-medium | 27.6 | 71.3 | 2.6 | 1.22 |
| powershell | sonnet5-1m-medium | 32.2 | 57.1 | 1.8 | 2.93 |
| default | sonnet5-1m-medium | 32.9 | 56.1 | 1.7 | 1.26 |
| bash | sonnet5-1m-low | 22.9 | 52.0 | 2.3 | 0.96 |
| typescript-bun | sonnet5-1m-medium | 27.3 | 51.6 | 1.9 | 1.12 |
| powershell | sonnet5-1m-low | 23.1 | 42.9 | 1.9 | 4.30 |
| default | sonnet5-1m-high | 22.0 | 41.1 | 1.9 | 0.86 |
| typescript-bun | sonnet5-1m-low | 18.4 | 37.6 | 2.0 | 0.96 |
| default | sonnet5-1m-low | 22.0 | 37.4 | 1.7 | 1.19 |

</details>

<details>
<summary>Sorted by avg test:code ratio (highest first)</summary>

| Language | Model | Avg Tests | Avg Assertions | Avg Assert/Test | Avg Test:Code Ratio |
|------|-------|-----------|----------------|-----------------|---------------------|
| powershell | sonnet5-1m-high | 47.6 | 88.1 | 1.9 | 5.65 |
| powershell | sonnet5-1m-low | 23.1 | 42.9 | 1.9 | 4.30 |
| powershell | sonnet5-1m-medium | 32.2 | 57.1 | 1.8 | 2.93 |
| typescript-bun | sonnet5-1m-high | 45.1 | 83.9 | 1.9 | 1.57 |
| default | sonnet5-1m-medium | 32.9 | 56.1 | 1.7 | 1.26 |
| bash | sonnet5-1m-medium | 27.6 | 71.3 | 2.6 | 1.22 |
| default | sonnet5-1m-low | 22.0 | 37.4 | 1.7 | 1.19 |
| typescript-bun | sonnet5-1m-medium | 27.3 | 51.6 | 1.9 | 1.12 |
| bash | sonnet5-1m-low | 22.9 | 52.0 | 2.3 | 0.96 |
| typescript-bun | sonnet5-1m-low | 18.4 | 37.6 | 2.0 | 0.96 |
| bash | sonnet5-1m-high | 34.4 | 73.3 | 2.1 | 0.89 |
| default | sonnet5-1m-high | 22.0 | 41.1 | 1.9 | 0.86 |

</details>


<details>
<summary>Per-run structural metrics</summary>

| Task | Language | Model | Tests | Assertions | Assert/Test | Test Lines | Impl Lines | Test:Code |
|------|------|-------|-------|------------|-------------|------------|------------|-----------|
| Semantic Version Bumper | bash | sonnet5-1m-high | 7 | 20 | 2.9 | 77 | 238 | 0.32 |
| Semantic Version Bumper | bash | sonnet5-1m-medium | 32 | 72 | 2.2 | 349 | 240 | 1.45 |
| Semantic Version Bumper | bash | sonnet5-1m-low | 20 | 31 | 1.6 | 201 | 260 | 0.77 |
| Semantic Version Bumper | default | sonnet5-1m-high | 38 | 60 | 1.6 | 438 | 336 | 1.30 |
| Semantic Version Bumper | default | sonnet5-1m-medium | 37 | 59 | 1.6 | 454 | 218 | 2.08 |
| Semantic Version Bumper | default | sonnet5-1m-low | 35 | 44 | 1.3 | 282 | 223 | 1.26 |
| Semantic Version Bumper | powershell | sonnet5-1m-high | 43 | 87 | 2.0 | 514 | 89 | 5.78 |
| Semantic Version Bumper | powershell | sonnet5-1m-medium | 36 | 64 | 1.8 | 321 | 143 | 2.24 |
| Semantic Version Bumper | powershell | sonnet5-1m-low | 35 | 52 | 1.5 | 259 | 41 | 6.32 |
| Semantic Version Bumper | powershell | sonnet5-1m-high | 51 | 88 | 1.7 | 649 | 72 | 9.01 |
| Semantic Version Bumper | powershell | sonnet5-1m-medium | 40 | 61 | 1.5 | 312 | 172 | 1.81 |
| Semantic Version Bumper | powershell | sonnet5-1m-low | 29 | 48 | 1.7 | 239 | 35 | 6.83 |
| Semantic Version Bumper | typescript-bun | sonnet5-1m-high | 51 | 88 | 1.7 | 869 | 470 | 1.85 |
| Semantic Version Bumper | typescript-bun | sonnet5-1m-medium | 24 | 43 | 1.8 | 391 | 272 | 1.44 |
| Semantic Version Bumper | typescript-bun | sonnet5-1m-low | 25 | 40 | 1.6 | 272 | 386 | 0.70 |
| PR Label Assigner | bash | sonnet5-1m-high | 52 | 100 | 1.9 | 517 | 447 | 1.16 |
| PR Label Assigner | bash | sonnet5-1m-medium | 24 | 54 | 2.2 | 192 | 246 | 0.78 |
| PR Label Assigner | bash | sonnet5-1m-low | 25 | 51 | 2.0 | 189 | 159 | 1.19 |
| PR Label Assigner | default | sonnet5-1m-high | 30 | 57 | 1.9 | 323 | 319 | 1.01 |
| PR Label Assigner | default | sonnet5-1m-medium | 23 | 43 | 1.9 | 194 | 239 | 0.81 |
| PR Label Assigner | default | sonnet5-1m-low | 18 | 12 | 0.7 | 209 | 333 | 0.63 |
| PR Label Assigner | powershell | sonnet5-1m-high | 58 | 77 | 1.3 | 504 | 215 | 2.34 |
| PR Label Assigner | powershell | sonnet5-1m-medium | 35 | 51 | 1.5 | 277 | 180 | 1.54 |
| PR Label Assigner | powershell | sonnet5-1m-low | 21 | 39 | 1.9 | 224 | 248 | 0.90 |
| PR Label Assigner | powershell | sonnet5-1m-high | 59 | 92 | 1.6 | 472 | 71 | 6.65 |
| PR Label Assigner | powershell | sonnet5-1m-medium | 28 | 37 | 1.3 | 227 | 40 | 5.67 |
| PR Label Assigner | powershell | sonnet5-1m-low | 24 | 46 | 1.9 | 242 | 35 | 6.91 |
| PR Label Assigner | typescript-bun | sonnet5-1m-high | 35 | 40 | 1.1 | 317 | 404 | 0.78 |
| PR Label Assigner | typescript-bun | sonnet5-1m-medium | 35 | 55 | 1.6 | 266 | 323 | 0.82 |
| PR Label Assigner | typescript-bun | sonnet5-1m-low | 17 | 26 | 1.5 | 161 | 154 | 1.05 |
| Dependency License Checker | bash | sonnet5-1m-high | 39 | 95 | 2.4 | 521 | 395 | 1.32 |
| Dependency License Checker | bash | sonnet5-1m-medium | 35 | 88 | 2.5 | 337 | 334 | 1.01 |
| Dependency License Checker | bash | sonnet5-1m-low | 22 | 65 | 3.0 | 218 | 183 | 1.19 |
| Dependency License Checker | default | sonnet5-1m-high | 8 | 30 | 3.8 | 218 | 274 | 0.80 |
| Dependency License Checker | default | sonnet5-1m-medium | 58 | 76 | 1.3 | 670 | 389 | 1.72 |
| Dependency License Checker | default | sonnet5-1m-low | 25 | 55 | 2.2 | 294 | 324 | 0.91 |
| Dependency License Checker | powershell | sonnet5-1m-high | 37 | 52 | 1.4 | 384 | 181 | 2.12 |
| Dependency License Checker | powershell | sonnet5-1m-medium | 27 | 47 | 1.7 | 234 | 205 | 1.14 |
| Dependency License Checker | powershell | sonnet5-1m-low | 27 | 45 | 1.7 | 220 | 52 | 4.23 |
| Dependency License Checker | powershell | sonnet5-1m-high | 31 | 58 | 1.9 | 340 | 87 | 3.91 |
| Dependency License Checker | powershell | sonnet5-1m-medium | 53 | 60 | 1.1 | 430 | 77 | 5.58 |
| Dependency License Checker | typescript-bun | sonnet5-1m-high | 40 | 65 | 1.6 | 579 | 385 | 1.50 |
| Dependency License Checker | typescript-bun | sonnet5-1m-medium | 29 | 60 | 2.1 | 370 | 452 | 0.82 |
| Dependency License Checker | typescript-bun | sonnet5-1m-low | 26 | 45 | 1.7 | 337 | 237 | 1.42 |
| Test Results Aggregator | bash | sonnet5-1m-high | 24 | 30 | 1.2 | 221 | 578 | 0.38 |
| Test Results Aggregator | bash | sonnet5-1m-medium | 34 | 68 | 2.0 | 279 | 317 | 0.88 |
| Test Results Aggregator | bash | sonnet5-1m-low | 20 | 41 | 2.0 | 181 | 189 | 0.96 |
| Test Results Aggregator | default | sonnet5-1m-high | 12 | 28 | 2.3 | 317 | 430 | 0.74 |
| Test Results Aggregator | default | sonnet5-1m-medium | 26 | 56 | 2.2 | 339 | 317 | 1.07 |
| Test Results Aggregator | default | sonnet5-1m-low | 25 | 57 | 2.3 | 308 | 250 | 1.23 |
| Test Results Aggregator | powershell | sonnet5-1m-high | 72 | 128 | 1.8 | 597 | 173 | 3.45 |
| Test Results Aggregator | powershell | sonnet5-1m-medium | 36 | 72 | 2.0 | 382 | 269 | 1.42 |
| Test Results Aggregator | powershell | sonnet5-1m-low | 17 | 42 | 2.5 | 167 | 113 | 1.48 |
| Test Results Aggregator | powershell | sonnet5-1m-high | 23 | 30 | 1.3 | 292 | 51 | 5.73 |
| Test Results Aggregator | powershell | sonnet5-1m-medium | 30 | 69 | 2.3 | 271 | 333 | 0.81 |
| Test Results Aggregator | typescript-bun | sonnet5-1m-high | 34 | 96 | 2.8 | 661 | 456 | 1.45 |
| Test Results Aggregator | typescript-bun | sonnet5-1m-medium | 28 | 60 | 2.1 | 332 | 384 | 0.86 |
| Test Results Aggregator | typescript-bun | sonnet5-1m-low | 16 | 62 | 3.9 | 263 | 250 | 1.05 |
| Environment Matrix Generator | bash | sonnet5-1m-high | 27 | 73 | 2.7 | 263 | 327 | 0.80 |
| Environment Matrix Generator | bash | sonnet5-1m-medium | 22 | 32 | 1.5 | 217 | 139 | 1.56 |
| Environment Matrix Generator | bash | sonnet5-1m-low | 14 | 27 | 1.9 | 115 | 112 | 1.03 |
| Environment Matrix Generator | default | sonnet5-1m-high | 43 | 43 | 1.0 | 433 | 422 | 1.03 |
| Environment Matrix Generator | default | sonnet5-1m-medium | 35 | 59 | 1.7 | 360 | 362 | 0.99 |
| Environment Matrix Generator | default | sonnet5-1m-low | 20 | 37 | 1.9 | 264 | 120 | 2.20 |
| Environment Matrix Generator | powershell | sonnet5-1m-high | 47 | 110 | 2.3 | 467 | 41 | 11.39 |
| Environment Matrix Generator | powershell | sonnet5-1m-medium | 41 | 65 | 1.6 | 406 | 55 | 7.38 |
| Environment Matrix Generator | powershell | sonnet5-1m-low | 13 | 16 | 1.2 | 115 | 276 | 0.42 |
| Environment Matrix Generator | powershell | sonnet5-1m-high | 49 | 103 | 2.1 | 531 | 332 | 1.60 |
| Environment Matrix Generator | powershell | sonnet5-1m-medium | 23 | 47 | 2.0 | 256 | 201 | 1.27 |
| Environment Matrix Generator | typescript-bun | sonnet5-1m-high | 40 | 76 | 1.9 | 630 | 287 | 2.20 |
| Environment Matrix Generator | typescript-bun | sonnet5-1m-medium | 16 | 30 | 1.9 | 262 | 225 | 1.16 |
| Environment Matrix Generator | typescript-bun | sonnet5-1m-low | 18 | 36 | 2.0 | 170 | 175 | 0.97 |
| Artifact Cleanup Script | bash | sonnet5-1m-high | 22 | 13 | 0.6 | 209 | 293 | 0.71 |
| Artifact Cleanup Script | bash | sonnet5-1m-medium | 21 | 84 | 4.0 | 330 | 193 | 1.71 |
| Artifact Cleanup Script | bash | sonnet5-1m-low | 30 | 86 | 2.9 | 250 | 368 | 0.68 |
| Artifact Cleanup Script | default | sonnet5-1m-high | 10 | 22 | 2.2 | 103 | 0 | 0.00 |
| Artifact Cleanup Script | default | sonnet5-1m-medium | 21 | 48 | 2.3 | 364 | 486 | 0.75 |
| Artifact Cleanup Script | default | sonnet5-1m-low | 17 | 31 | 1.8 | 221 | 294 | 0.75 |
| Artifact Cleanup Script | powershell | sonnet5-1m-high | 57 | 117 | 2.1 | 570 | 122 | 4.67 |
| Artifact Cleanup Script | powershell | sonnet5-1m-medium | 19 | 57 | 3.0 | 262 | 165 | 1.59 |
| Artifact Cleanup Script | powershell | sonnet5-1m-low | 17 | 38 | 2.2 | 192 | 35 | 5.49 |
| Artifact Cleanup Script | powershell | sonnet5-1m-high | 41 | 109 | 2.7 | 495 | 128 | 3.87 |
| Artifact Cleanup Script | powershell | sonnet5-1m-medium | 32 | 68 | 2.1 | 304 | 74 | 4.11 |
| Artifact Cleanup Script | typescript-bun | sonnet5-1m-high | 53 | 107 | 2.0 | 700 | 578 | 1.21 |
| Artifact Cleanup Script | typescript-bun | sonnet5-1m-medium | 22 | 41 | 1.9 | 396 | 343 | 1.15 |
| Artifact Cleanup Script | typescript-bun | sonnet5-1m-low | 18 | 37 | 2.1 | 282 | 344 | 0.82 |
| Secret Rotation Validator | bash | sonnet5-1m-high | 70 | 182 | 2.6 | 631 | 416 | 1.52 |
| Secret Rotation Validator | bash | sonnet5-1m-medium | 25 | 101 | 4.0 | 299 | 263 | 1.14 |
| Secret Rotation Validator | bash | sonnet5-1m-low | 29 | 63 | 2.2 | 223 | 241 | 0.93 |
| Secret Rotation Validator | default | sonnet5-1m-high | 13 | 48 | 3.7 | 326 | 280 | 1.16 |
| Secret Rotation Validator | default | sonnet5-1m-medium | 30 | 52 | 1.7 | 320 | 226 | 1.42 |
| Secret Rotation Validator | default | sonnet5-1m-low | 14 | 26 | 1.9 | 213 | 161 | 1.32 |
| Secret Rotation Validator | powershell | sonnet5-1m-high | 32 | 80 | 2.5 | 582 | 46 | 12.65 |
| Secret Rotation Validator | powershell | sonnet5-1m-medium | 18 | 36 | 2.0 | 189 | 147 | 1.29 |
| Secret Rotation Validator | powershell | sonnet5-1m-low | 25 | 60 | 2.4 | 317 | 52 | 6.10 |
| Secret Rotation Validator | powershell | sonnet5-1m-high | 66 | 102 | 1.5 | 564 | 96 | 5.88 |
| Secret Rotation Validator | powershell | sonnet5-1m-medium | 33 | 66 | 2.0 | 366 | 70 | 5.23 |
| Secret Rotation Validator | typescript-bun | sonnet5-1m-high | 63 | 115 | 1.8 | 927 | 461 | 2.01 |
| Secret Rotation Validator | typescript-bun | sonnet5-1m-medium | 37 | 72 | 1.9 | 466 | 292 | 1.60 |
| Secret Rotation Validator | typescript-bun | sonnet5-1m-low | 9 | 17 | 1.9 | 85 | 122 | 0.70 |

</details>

### LLM-as-Judge Scores

An LLM evaluates each test suite on four dimensions (1-5 scale):

- **Coverage** (1-5): Do tests exercise the key requirements? 1 = most untested, 5 = all covered.
- **Rigor** (1-5): Edge cases, error handling, boundary conditions? 1 = happy path only, 5 = thorough.
- **Design** (1-5): Test organization, fixtures, readability? 1 = messy/brittle, 5 = well-structured.
- **Overall** (1-5): Holistic quality — would you trust this suite to catch regressions? 1 = no, 5 = absolutely. Use this as the primary ranking metric.

| Language | Model | Avg Overall | Avg Coverage | Avg Rigor | Avg Design | Judge Cost |
|------|-------|-------------|-------------|-----------|------------|------------|
| bash | sonnet5-1m-high | **3.8** | 4.1 | 3.6 | 4.1 | $0.6081 |
| bash | sonnet5-1m-low | **2.9** | 3.3 | 3.0 | 3.3 | $0.4499 |
| bash | sonnet5-1m-medium | **3.9** | 4.3 | 3.8 | 4.0 | $0.4190 |
| default | sonnet5-1m-high | **3.6** | 3.7 | 3.4 | 4.3 | $0.4316 |
| default | sonnet5-1m-low | **3.0** | 3.1 | 3.1 | 3.9 | $0.3686 |
| default | sonnet5-1m-medium | **3.1** | 3.3 | 3.6 | 3.9 | $0.4125 |
| powershell | sonnet5-1m-high | **4.2** | 4.4 | 4.2 | 4.4 | $0.8458 |
| powershell | sonnet5-1m-low | **2.8** | 3.0 | 2.9 | 3.6 | $0.5602 |
| powershell | sonnet5-1m-medium | **3.7** | 4.0 | 3.8 | 3.9 | $0.9048 |
| typescript-bun | sonnet5-1m-high | **4.3** | 4.4 | 4.5 | 4.6 | $0.4521 |
| typescript-bun | sonnet5-1m-low | **2.1** | 2.4 | 2.9 | 3.4 | $0.3009 |
| typescript-bun | sonnet5-1m-medium | **3.1** | 3.3 | 3.5 | 3.8 | $0.4688 |
| **Total** | | | | | | **$6.2223** |


<details>
<summary>Sorted by avg overall (highest first)</summary>

| Language | Model | Avg Overall | Avg Coverage | Avg Rigor | Avg Design | Judge Cost |
|------|-------|-------------|-------------|-----------|------------|------------|
| typescript-bun | sonnet5-1m-high | **4.3** | 4.4 | 4.5 | 4.6 | $0.4521 |
| powershell | sonnet5-1m-high | **4.2** | 4.4 | 4.2 | 4.4 | $0.8458 |
| bash | sonnet5-1m-medium | **3.9** | 4.3 | 3.8 | 4.0 | $0.4190 |
| bash | sonnet5-1m-high | **3.8** | 4.1 | 3.6 | 4.1 | $0.6081 |
| powershell | sonnet5-1m-medium | **3.7** | 4.0 | 3.8 | 3.9 | $0.9048 |
| default | sonnet5-1m-high | **3.6** | 3.7 | 3.4 | 4.3 | $0.4316 |
| typescript-bun | sonnet5-1m-medium | **3.1** | 3.3 | 3.5 | 3.8 | $0.4688 |
| default | sonnet5-1m-medium | **3.1** | 3.3 | 3.6 | 3.9 | $0.4125 |
| default | sonnet5-1m-low | **3.0** | 3.1 | 3.1 | 3.9 | $0.3686 |
| bash | sonnet5-1m-low | **2.9** | 3.3 | 3.0 | 3.3 | $0.4499 |
| powershell | sonnet5-1m-low | **2.8** | 3.0 | 2.9 | 3.6 | $0.5602 |
| typescript-bun | sonnet5-1m-low | **2.1** | 2.4 | 2.9 | 3.4 | $0.3009 |

</details>

<details>
<summary>Sorted by avg coverage (highest first)</summary>

| Language | Model | Avg Overall | Avg Coverage | Avg Rigor | Avg Design | Judge Cost |
|------|-------|-------------|-------------|-----------|------------|------------|
| powershell | sonnet5-1m-high | **4.2** | 4.4 | 4.2 | 4.4 | $0.8458 |
| typescript-bun | sonnet5-1m-high | **4.3** | 4.4 | 4.5 | 4.6 | $0.4521 |
| bash | sonnet5-1m-medium | **3.9** | 4.3 | 3.8 | 4.0 | $0.4190 |
| bash | sonnet5-1m-high | **3.8** | 4.1 | 3.6 | 4.1 | $0.6081 |
| powershell | sonnet5-1m-medium | **3.7** | 4.0 | 3.8 | 3.9 | $0.9048 |
| default | sonnet5-1m-high | **3.6** | 3.7 | 3.4 | 4.3 | $0.4316 |
| bash | sonnet5-1m-low | **2.9** | 3.3 | 3.0 | 3.3 | $0.4499 |
| default | sonnet5-1m-medium | **3.1** | 3.3 | 3.6 | 3.9 | $0.4125 |
| typescript-bun | sonnet5-1m-medium | **3.1** | 3.3 | 3.5 | 3.8 | $0.4688 |
| default | sonnet5-1m-low | **3.0** | 3.1 | 3.1 | 3.9 | $0.3686 |
| powershell | sonnet5-1m-low | **2.8** | 3.0 | 2.9 | 3.6 | $0.5602 |
| typescript-bun | sonnet5-1m-low | **2.1** | 2.4 | 2.9 | 3.4 | $0.3009 |

</details>

<details>
<summary>Sorted by avg rigor (highest first)</summary>

| Language | Model | Avg Overall | Avg Coverage | Avg Rigor | Avg Design | Judge Cost |
|------|-------|-------------|-------------|-----------|------------|------------|
| typescript-bun | sonnet5-1m-high | **4.3** | 4.4 | 4.5 | 4.6 | $0.4521 |
| powershell | sonnet5-1m-high | **4.2** | 4.4 | 4.2 | 4.4 | $0.8458 |
| powershell | sonnet5-1m-medium | **3.7** | 4.0 | 3.8 | 3.9 | $0.9048 |
| bash | sonnet5-1m-medium | **3.9** | 4.3 | 3.8 | 4.0 | $0.4190 |
| bash | sonnet5-1m-high | **3.8** | 4.1 | 3.6 | 4.1 | $0.6081 |
| default | sonnet5-1m-medium | **3.1** | 3.3 | 3.6 | 3.9 | $0.4125 |
| typescript-bun | sonnet5-1m-medium | **3.1** | 3.3 | 3.5 | 3.8 | $0.4688 |
| default | sonnet5-1m-high | **3.6** | 3.7 | 3.4 | 4.3 | $0.4316 |
| default | sonnet5-1m-low | **3.0** | 3.1 | 3.1 | 3.9 | $0.3686 |
| bash | sonnet5-1m-low | **2.9** | 3.3 | 3.0 | 3.3 | $0.4499 |
| typescript-bun | sonnet5-1m-low | **2.1** | 2.4 | 2.9 | 3.4 | $0.3009 |
| powershell | sonnet5-1m-low | **2.8** | 3.0 | 2.9 | 3.6 | $0.5602 |

</details>

<details>
<summary>Sorted by avg design (highest first)</summary>

| Language | Model | Avg Overall | Avg Coverage | Avg Rigor | Avg Design | Judge Cost |
|------|-------|-------------|-------------|-----------|------------|------------|
| typescript-bun | sonnet5-1m-high | **4.3** | 4.4 | 4.5 | 4.6 | $0.4521 |
| powershell | sonnet5-1m-high | **4.2** | 4.4 | 4.2 | 4.4 | $0.8458 |
| default | sonnet5-1m-high | **3.6** | 3.7 | 3.4 | 4.3 | $0.4316 |
| bash | sonnet5-1m-high | **3.8** | 4.1 | 3.6 | 4.1 | $0.6081 |
| bash | sonnet5-1m-medium | **3.9** | 4.3 | 3.8 | 4.0 | $0.4190 |
| default | sonnet5-1m-medium | **3.1** | 3.3 | 3.6 | 3.9 | $0.4125 |
| powershell | sonnet5-1m-medium | **3.7** | 4.0 | 3.8 | 3.9 | $0.9048 |
| default | sonnet5-1m-low | **3.0** | 3.1 | 3.1 | 3.9 | $0.3686 |
| typescript-bun | sonnet5-1m-medium | **3.1** | 3.3 | 3.5 | 3.8 | $0.4688 |
| powershell | sonnet5-1m-low | **2.8** | 3.0 | 2.9 | 3.6 | $0.5602 |
| typescript-bun | sonnet5-1m-low | **2.1** | 2.4 | 2.9 | 3.4 | $0.3009 |
| bash | sonnet5-1m-low | **2.9** | 3.3 | 3.0 | 3.3 | $0.4499 |

</details>


<details>
<summary>Per-run LLM judge scores</summary>

| Task | Language | Model | Cov | Rig | Des | Ovr | Summary |
|------|------|-------|-----|-----|-----|-----|---------|
| Semantic Version Bumper | bash | sonnet5-1m-high | 2.0 | 1.0 | 3.0 | 1.5 |  |
| Semantic Version Bumper | bash | sonnet5-1m-medium | 4.0 | 3.5 | 4.0 | 4.0 |  |
| Semantic Version Bumper | bash | sonnet5-1m-low | 4.0 | 4.0 | 4.5 | 4.0 |  |
| Semantic Version Bumper | default | sonnet5-1m-high | 5.0 | 4.5 | 5.0 | 4.5 |  |
| Semantic Version Bumper | default | sonnet5-1m-medium | 4.5 | 4.0 | 4.5 | 4.0 |  |
| Semantic Version Bumper | default | sonnet5-1m-low | 2.0 | 2.5 | 3.5 | 1.5 |  |
| Semantic Version Bumper | powershell | sonnet5-1m-high | 4.5 | 4.5 | 4.0 | 4.0 |  |
| Semantic Version Bumper | powershell | sonnet5-1m-medium | 4.5 | 4.0 | 4.5 | 4.5 |  |
| Semantic Version Bumper | powershell | sonnet5-1m-low | 2.0 | 3.0 | 3.0 | 2.0 |  |
| Semantic Version Bumper | powershell | sonnet5-1m-high | 4.5 | 4.0 | 4.5 | 4.0 |  |
| Semantic Version Bumper | powershell | sonnet5-1m-medium | 4.5 | 4.0 | 4.5 | 4.5 |  |
| Semantic Version Bumper | powershell | sonnet5-1m-low | 3.5 | 3.5 | 4.0 | 3.5 |  |
| Semantic Version Bumper | typescript-bun | sonnet5-1m-high | 4.5 | 4.5 | 4.5 | 4.5 |  |
| Semantic Version Bumper | typescript-bun | sonnet5-1m-medium | 3.5 | 3.5 | 4.0 | 3.5 |  |
| Semantic Version Bumper | typescript-bun | sonnet5-1m-low | 4.5 | 4.0 | 4.5 | 4.5 |  |
| PR Label Assigner | bash | sonnet5-1m-high | 4.5 | 4.5 | 4.5 | 4.5 |  |
| PR Label Assigner | bash | sonnet5-1m-medium | 5.0 | 4.5 | 4.5 | 4.5 |  |
| PR Label Assigner | bash | sonnet5-1m-low | 2.0 | 2.5 | 2.0 | 2.0 |  |
| PR Label Assigner | default | sonnet5-1m-high | 4.5 | 4.5 | 4.5 | 4.5 |  |
| PR Label Assigner | default | sonnet5-1m-medium | 2.0 | 3.0 | 3.5 | 2.0 |  |
| PR Label Assigner | default | sonnet5-1m-low | 4.5 | 4.0 | 4.5 | 4.5 |  |
| PR Label Assigner | powershell | sonnet5-1m-high | 4.5 | 4.5 | 4.5 | 4.5 |  |
| PR Label Assigner | powershell | sonnet5-1m-medium | 4.5 | 4.5 | 4.0 | 4.5 |  |
| PR Label Assigner | powershell | sonnet5-1m-low | 4.0 | 3.5 | 3.5 | 3.5 |  |
| PR Label Assigner | powershell | sonnet5-1m-high | 3.5 | 4.0 | 4.5 | 3.5 |  |
| PR Label Assigner | powershell | sonnet5-1m-medium | 2.0 | 2.5 | 3.0 | 2.0 |  |
| PR Label Assigner | powershell | sonnet5-1m-low | 2.5 | 2.5 | 3.5 | 2.0 |  |
| PR Label Assigner | typescript-bun | sonnet5-1m-high | 5.0 | 4.5 | 4.5 | 4.5 |  |
| PR Label Assigner | typescript-bun | sonnet5-1m-medium | 4.5 | 4.0 | 4.0 | 4.0 |  |
| PR Label Assigner | typescript-bun | sonnet5-1m-low | 2.0 | 2.5 | 3.0 | 2.0 |  |
| Dependency License Checker | bash | sonnet5-1m-high | 4.5 | 4.5 | 4.0 | 4.0 |  |
| Dependency License Checker | bash | sonnet5-1m-medium | 4.0 | 4.0 | 3.5 | 3.5 |  |
| Dependency License Checker | bash | sonnet5-1m-low | 3.5 | 2.5 | 2.5 | 2.5 |  |
| Dependency License Checker | default | sonnet5-1m-high | 3.0 | 2.0 | 4.5 | 3.0 |  |
| Dependency License Checker | default | sonnet5-1m-medium | 3.0 | 3.5 | 4.0 | 2.5 |  |
| Dependency License Checker | default | sonnet5-1m-low | 4.5 | 4.5 | 4.5 | 4.5 |  |
| Dependency License Checker | powershell | sonnet5-1m-high | 4.5 | 4.5 | 4.5 | 4.5 |  |
| Dependency License Checker | powershell | sonnet5-1m-medium | 4.0 | 3.5 | 4.0 | 4.0 |  |
| Dependency License Checker | powershell | sonnet5-1m-low | 2.0 | 2.5 | 3.5 | 2.0 |  |
| Dependency License Checker | powershell | sonnet5-1m-high | 4.5 | 4.0 | 4.5 | 4.5 |  |
| Dependency License Checker | powershell | sonnet5-1m-medium | 4.5 | 4.0 | 4.5 | 4.5 |  |
| Dependency License Checker | typescript-bun | sonnet5-1m-high | 5.0 | 4.5 | 4.5 | 4.5 |  |
| Dependency License Checker | typescript-bun | sonnet5-1m-medium | 4.5 | 4.0 | 4.5 | 4.5 |  |
| Dependency License Checker | typescript-bun | sonnet5-1m-low | 2.5 | 2.5 | 4.0 | 2.0 |  |
| Test Results Aggregator | bash | sonnet5-1m-high | 4.5 | 4.0 | 4.5 | 4.5 |  |
| Test Results Aggregator | bash | sonnet5-1m-medium | 4.0 | 3.0 | 4.0 | 3.5 |  |
| Test Results Aggregator | bash | sonnet5-1m-low | 2.5 | 2.5 | 3.0 | 2.0 |  |
| Test Results Aggregator | default | sonnet5-1m-high | 4.0 | 2.5 | 4.5 | 3.5 |  |
| Test Results Aggregator | default | sonnet5-1m-medium | 2.5 | 3.0 | 3.5 | 2.0 |  |
| Test Results Aggregator | default | sonnet5-1m-low | 2.0 | 2.5 | 3.5 | 2.0 |  |
| Test Results Aggregator | powershell | sonnet5-1m-high | 5.0 | 4.5 | 4.5 | 4.5 |  |
| Test Results Aggregator | powershell | sonnet5-1m-medium | 5.0 | 4.0 | 3.5 | 3.5 |  |
| Test Results Aggregator | powershell | sonnet5-1m-low | 3.5 | 2.5 | 4.0 | 3.5 |  |
| Test Results Aggregator | powershell | sonnet5-1m-high | 3.5 | 3.0 | 3.5 | 3.5 |  |
| Test Results Aggregator | powershell | sonnet5-1m-medium | 4.0 | 3.5 | 4.0 | 3.5 |  |
| Test Results Aggregator | typescript-bun | sonnet5-1m-high | 4.5 | 4.5 | 4.5 | 4.5 |  |
| Test Results Aggregator | typescript-bun | sonnet5-1m-medium | 2.5 | 3.0 | 3.5 | 2.5 |  |
| Test Results Aggregator | typescript-bun | sonnet5-1m-low | 2.0 | 2.5 | 3.0 | 1.5 |  |
| Environment Matrix Generator | bash | sonnet5-1m-high | 4.5 | 4.0 | 4.5 | 4.0 |  |
| Environment Matrix Generator | bash | sonnet5-1m-medium | 4.0 | 3.5 | 4.0 | 4.0 |  |
| Environment Matrix Generator | bash | sonnet5-1m-low | 2.0 | 2.0 | 2.5 | 2.0 |  |
| Environment Matrix Generator | default | sonnet5-1m-high | 4.5 | 4.5 | 4.5 | 4.5 |  |
| Environment Matrix Generator | default | sonnet5-1m-medium | 4.0 | 4.0 | 4.0 | 4.0 |  |
| Environment Matrix Generator | default | sonnet5-1m-low | 2.0 | 2.5 | 3.0 | 2.0 |  |
| Environment Matrix Generator | powershell | sonnet5-1m-high | 5.0 | 4.5 | 4.5 | 4.5 |  |
| Environment Matrix Generator | powershell | sonnet5-1m-medium | 4.5 | 4.5 | 4.5 | 4.5 |  |
| Environment Matrix Generator | powershell | sonnet5-1m-low | 3.5 | 3.0 | 3.5 | 2.5 |  |
| Environment Matrix Generator | powershell | sonnet5-1m-high | 4.5 | 4.0 | 4.5 | 4.5 |  |
| Environment Matrix Generator | powershell | sonnet5-1m-medium | 4.5 | 4.5 | 4.0 | 4.0 |  |
| Environment Matrix Generator | typescript-bun | sonnet5-1m-high | 4.5 | 4.5 | 4.5 | 4.5 |  |
| Environment Matrix Generator | typescript-bun | sonnet5-1m-medium | 2.0 | 3.0 | 3.5 | 2.0 |  |
| Environment Matrix Generator | typescript-bun | sonnet5-1m-low | 2.0 | 3.0 | 2.5 | 1.5 |  |
| Artifact Cleanup Script | bash | sonnet5-1m-high | 4.5 | 3.5 | 4.5 | 4.0 |  |
| Artifact Cleanup Script | bash | sonnet5-1m-medium | 4.0 | 3.5 | 3.5 | 3.5 |  |
| Artifact Cleanup Script | bash | sonnet5-1m-low | 4.5 | 4.0 | 4.5 | 4.0 |  |
| Artifact Cleanup Script | default | sonnet5-1m-high | 1.0 | 1.5 | 3.0 | 1.0 |  |
| Artifact Cleanup Script | default | sonnet5-1m-medium | 4.5 | 4.5 | 4.5 | 4.5 |  |
| Artifact Cleanup Script | default | sonnet5-1m-low | 4.0 | 3.5 | 4.5 | 4.0 |  |
| Artifact Cleanup Script | powershell | sonnet5-1m-high | 4.5 | 4.5 | 4.5 | 4.5 |  |
| Artifact Cleanup Script | powershell | sonnet5-1m-medium | 4.5 | 4.5 | 4.5 | 4.5 |  |
| Artifact Cleanup Script | powershell | sonnet5-1m-low | 2.0 | 2.0 | 3.5 | 2.0 |  |
| Artifact Cleanup Script | powershell | sonnet5-1m-high | 5.0 | 4.5 | 4.5 | 4.5 |  |
| Artifact Cleanup Script | powershell | sonnet5-1m-medium | 3.0 | 3.5 | 3.5 | 2.0 |  |
| Artifact Cleanup Script | typescript-bun | sonnet5-1m-high | 2.5 | 4.0 | 4.5 | 2.5 |  |
| Artifact Cleanup Script | typescript-bun | sonnet5-1m-medium | 2.5 | 3.5 | 3.5 | 2.0 |  |
| Artifact Cleanup Script | typescript-bun | sonnet5-1m-low | 2.0 | 3.0 | 3.5 | 1.5 |  |
| Secret Rotation Validator | bash | sonnet5-1m-high | 4.5 | 4.0 | 4.0 | 4.0 |  |
| Secret Rotation Validator | bash | sonnet5-1m-medium | 5.0 | 4.5 | 4.5 | 4.5 |  |
| Secret Rotation Validator | bash | sonnet5-1m-low | 4.5 | 3.5 | 4.0 | 3.5 |  |
| Secret Rotation Validator | default | sonnet5-1m-high | 4.0 | 4.0 | 4.0 | 4.0 |  |
| Secret Rotation Validator | default | sonnet5-1m-medium | 2.5 | 3.0 | 3.5 | 2.5 |  |
| Secret Rotation Validator | default | sonnet5-1m-low | 2.5 | 2.5 | 3.5 | 2.5 |  |
| Secret Rotation Validator | powershell | sonnet5-1m-high | 4.0 | 4.0 | 4.5 | 4.0 |  |
| Secret Rotation Validator | powershell | sonnet5-1m-medium | 3.5 | 3.0 | 4.0 | 3.5 |  |
| Secret Rotation Validator | powershell | sonnet5-1m-low | 4.0 | 3.5 | 4.0 | 4.0 |  |
| Secret Rotation Validator | powershell | sonnet5-1m-high | 4.5 | 4.5 | 4.5 | 4.5 |  |
| Secret Rotation Validator | powershell | sonnet5-1m-medium | 2.5 | 3.5 | 2.5 | 2.0 |  |
| Secret Rotation Validator | typescript-bun | sonnet5-1m-high | 5.0 | 5.0 | 5.0 | 5.0 |  |
| Secret Rotation Validator | typescript-bun | sonnet5-1m-medium | 3.5 | 3.5 | 3.5 | 3.5 |  |
| Secret Rotation Validator | typescript-bun | sonnet5-1m-low | 1.5 | 3.0 | 3.0 | 1.5 |  |

</details>

### Correlation: Structural Metrics vs Tests Quality

Spearman rank correlation between automated counts and LLM judge scores.
Values near +1.0 indicate the LLM agrees with the structural signal; near 0 means no relationship.

| Structural Metric | vs Coverage | vs Rigor | vs Design | vs Overall |
|-------------------|------------|---------|----------|-----------|
| Test count | 0.49 | 0.58 | 0.46 | 0.49 |
| Assertion count | 0.44 | 0.52 | 0.36 | 0.39 |
| Test:code ratio | 0.05 | 0.15 | 0.02 | 0.12 |

*Based on 100 runs with both structural and LLM scores.*

### LLM vs Structural Discrepancies

**Qualitative disagreements** — structural metrics look reasonable; the LLM judge is weighing factors the counters can't measure.

| Task | Language | Model | Tests | Asserts | Cov | Rig | Des | Ovr | Flag | Justification |
|------|------|-------|-------|---------|-----|-----|-----|-----|------|---------------|
| Semantic Version Bumper | default | sonnet5-1m-low | 35 | 44 | 2.0 | 2.5 | 3.5 | 1.5 | LLM says low coverage (2.0/5) but 35 tests detected |  |
| Semantic Version Bumper | powershell | sonnet5-1m-low | 29 | 48 | 2.0 | 3.0 | 3.0 | 2.0 | LLM says low coverage (2.0/5) but 29 tests detected |  |
| PR Label Assigner | bash | sonnet5-1m-low | 25 | 51 | 2.0 | 2.5 | 2.0 | 2.0 | LLM says low coverage (2.0/5) but 25 tests detected |  |
| PR Label Assigner | default | sonnet5-1m-medium | 23 | 43 | 2.0 | 3.0 | 3.5 | 2.0 | LLM says low coverage (2.0/5) but 23 tests detected |  |
| PR Label Assigner | powershell | sonnet5-1m-medium | 28 | 37 | 2.0 | 2.5 | 3.0 | 2.0 | LLM says low coverage (2.0/5) but 28 tests detected |  |
| Dependency License Checker | powershell | sonnet5-1m-low | 27 | 45 | 2.0 | 2.5 | 3.5 | 2.0 | LLM says low coverage (2.0/5) but 27 tests detected |  |
| Test Results Aggregator | default | sonnet5-1m-low | 25 | 57 | 2.0 | 2.5 | 3.5 | 2.0 | LLM says low coverage (2.0/5) but 25 tests detected |  |
| Environment Matrix Generator | default | sonnet5-1m-low | 20 | 37 | 2.0 | 2.5 | 3.0 | 2.0 | LLM says low coverage (2.0/5) but 20 tests detected |  |

## Per-Run Results

*Tests Quality = Overall (1-5) from LLM-as-judge of generated test code (dimensions: coverage, rigor, design). `—` = no judge data.*

| Task | Language | Model | Duration | Turns | Errors | Cost | Tests Quality | Chosen | Status |
|------|----------|-------|----------|-------|--------|------|-----------|--------|--------|
| Artifact Cleanup Script | bash | sonnet5-1m-high | 11.8min | 59 | 4 | $3.37 | 4.0 | bash | ok |
| Artifact Cleanup Script | bash | sonnet5-1m-low | 13.7min | 2 | 6 | $0.14 | 4.0 | bash | ok |
| Artifact Cleanup Script | bash | sonnet5-1m-medium | 16.9min | 80 | 7 | $3.35 | 3.5 | bash | ok |
| Artifact Cleanup Script | default | sonnet5-1m-high | 18.0min | 76 | 1 | $3.61 | 1.0 | powershell | ok |
| Artifact Cleanup Script | default | sonnet5-1m-low | 4.5min | 32 | 0 | $1.07 | 4.0 | python | ok |
| Artifact Cleanup Script | default | sonnet5-1m-medium | 11.5min | 86 | 3 | $3.10 | 4.5 | python | ok |
| Artifact Cleanup Script | powershell | sonnet5-1m-high | 23.4min | 98 | 3 | $5.42 | 4.5 | powershell | ok |
| Artifact Cleanup Script | powershell | sonnet5-1m-high | 21.2min | 79 | 0 | $4.33 | 4.5 | powershell | ok |
| Artifact Cleanup Script | powershell | sonnet5-1m-low | 7.5min | 35 | 0 | $1.05 | 2.0 | powershell | ok |
| Artifact Cleanup Script | powershell | sonnet5-1m-medium | 11.3min | 38 | 0 | $1.90 | 4.5 | powershell | ok |
| Artifact Cleanup Script | powershell | sonnet5-1m-medium | 16.6min | 64 | 2 | $3.28 | 2.0 | powershell | ok |
| Artifact Cleanup Script | typescript-bun | sonnet5-1m-high | 23.5min | 150 | 2 | $6.00 | 2.5 | typescript | ok |
| Artifact Cleanup Script | typescript-bun | sonnet5-1m-low | 9.3min | 46 | 0 | $1.30 | 1.5 | typescript | ok |
| Artifact Cleanup Script | typescript-bun | sonnet5-1m-medium | 13.7min | 109 | 0 | $3.28 | 2.0 | typescript | ok |
| Dependency License Checker | bash | sonnet5-1m-high | 17.4min | 105 | 3 | $5.57 | 4.0 | bash | ok |
| Dependency License Checker | bash | sonnet5-1m-low | 12.3min | 49 | 4 | $1.36 | 2.5 | bash | ok |
| Dependency License Checker | bash | sonnet5-1m-medium | 11.0min | 74 | 4 | $2.43 | 3.5 | bash | ok |
| Dependency License Checker | default | sonnet5-1m-high | 9.9min | 39 | 1 | $1.99 | 3.0 | python | ok |
| Dependency License Checker | default | sonnet5-1m-low | 4.9min | 34 | 0 | $1.13 | 4.5 | python | ok |
| Dependency License Checker | default | sonnet5-1m-medium | 8.9min | 73 | 0 | $2.48 | 2.5 | python | ok |
| Dependency License Checker | powershell | sonnet5-1m-high | 16.8min | 80 | 0 | $3.03 | 4.5 | powershell | ok |
| Dependency License Checker | powershell | sonnet5-1m-high | 14.6min | 58 | 1 | $2.80 | 4.5 | powershell | ok |
| Dependency License Checker | powershell | sonnet5-1m-low | 7.6min | 39 | 0 | $1.17 | 2.0 | powershell | ok |
| Dependency License Checker | powershell | sonnet5-1m-medium | 13.5min | 52 | 3 | $2.14 | 4.0 | powershell | ok |
| Dependency License Checker | powershell | sonnet5-1m-medium | 18.8min | 70 | 0 | $4.02 | 4.5 | powershell | ok |
| Dependency License Checker | typescript-bun | sonnet5-1m-high | 18.4min | 137 | 11 | $5.28 | 4.5 | typescript | ok |
| Dependency License Checker | typescript-bun | sonnet5-1m-low | 10.4min | 63 | 3 | $1.73 | 2.0 | typescript | ok |
| Dependency License Checker | typescript-bun | sonnet5-1m-medium | 13.6min | 93 | 1 | $2.82 | 4.5 | typescript | ok |
| Environment Matrix Generator | bash | sonnet5-1m-high | 26.2min | 150 | 9 | $8.03 | 4.0 | bash | ok |
| Environment Matrix Generator | bash | sonnet5-1m-low | 5.3min | 42 | 1 | $1.21 | 2.0 | bash | ok |
| Environment Matrix Generator | bash | sonnet5-1m-medium | 14.2min | 67 | 0 | $2.90 | 4.0 | bash | ok |
| Environment Matrix Generator | default | sonnet5-1m-high | 16.4min | 94 | 2 | $5.01 | 4.5 | python | ok |
| Environment Matrix Generator | default | sonnet5-1m-low | 10.7min | 26 | 1 | $0.84 | 2.0 | python | ok |
| Environment Matrix Generator | default | sonnet5-1m-medium | 6.9min | 59 | 0 | $1.72 | 4.0 | python | ok |
| Environment Matrix Generator | powershell | sonnet5-1m-high | 29.5min | 103 | 0 | $6.22 | 4.5 | powershell | ok |
| Environment Matrix Generator | powershell | sonnet5-1m-high | 25.4min | 82 | 0 | $5.48 | 4.5 | powershell | ok |
| Environment Matrix Generator | powershell | sonnet5-1m-low | 7.4min | 3 | 0 | $1.10 | 2.5 | powershell | ok |
| Environment Matrix Generator | powershell | sonnet5-1m-medium | 16.5min | 99 | 1 | $3.46 | 4.5 | powershell | ok |
| Environment Matrix Generator | powershell | sonnet5-1m-medium | 15.8min | 55 | 0 | $2.82 | 4.0 | powershell | ok |
| Environment Matrix Generator | typescript-bun | sonnet5-1m-high | 19.7min | 75 | 1 | $4.76 | 4.5 | typescript | ok |
| Environment Matrix Generator | typescript-bun | sonnet5-1m-low | 5.8min | 36 | 2 | $1.26 | 1.5 | typescript | ok |
| Environment Matrix Generator | typescript-bun | sonnet5-1m-medium | 17.0min | 87 | 4 | $3.12 | 2.0 | typescript | ok |
| PR Label Assigner | bash | sonnet5-1m-high | 30.0min | 0 | 2 | $0.00 | 4.5 | bash | timeout |
| PR Label Assigner | bash | sonnet5-1m-low | 3.4min | 28 | 1 | $0.76 | 2.0 | bash | ok |
| PR Label Assigner | bash | sonnet5-1m-medium | 14.3min | 101 | 5 | $3.99 | 4.5 | bash | ok |
| PR Label Assigner | default | sonnet5-1m-high | 11.6min | 80 | 0 | $3.61 | 4.5 | python | ok |
| PR Label Assigner | default | sonnet5-1m-low | 3.7min | 24 | 0 | $0.75 | 4.5 | python | ok |
| PR Label Assigner | default | sonnet5-1m-medium | 9.5min | 64 | 1 | $2.04 | 2.0 | powershell | ok |
| PR Label Assigner | powershell | sonnet5-1m-high | 30.0min | 0 | 1 | $0.00 | 4.5 | powershell | timeout |
| PR Label Assigner | powershell | sonnet5-1m-high | 30.0min | 0 | 4 | $0.00 | 3.5 | powershell | timeout |
| PR Label Assigner | powershell | sonnet5-1m-low | 6.0min | 34 | 1 | $0.96 | 3.5 | powershell | ok |
| PR Label Assigner | powershell | sonnet5-1m-low | 11.3min | 48 | 1 | $1.50 | 2.0 | powershell | ok |
| PR Label Assigner | powershell | sonnet5-1m-medium | 9.6min | 40 | 0 | $1.58 | 4.5 | powershell | ok |
| PR Label Assigner | powershell | sonnet5-1m-medium | 8.7min | 27 | 1 | $1.19 | 2.0 | powershell | ok |
| PR Label Assigner | typescript-bun | sonnet5-1m-high | 18.3min | 106 | 0 | $4.13 | 4.5 | typescript | ok |
| PR Label Assigner | typescript-bun | sonnet5-1m-low | 4.6min | 33 | 0 | $0.91 | 2.0 | typescript | ok |
| PR Label Assigner | typescript-bun | sonnet5-1m-medium | 11.0min | 63 | 2 | $2.28 | 4.0 | typescript | ok |
| Secret Rotation Validator | bash | sonnet5-1m-high | 20.7min | 119 | 1 | $6.24 | 4.0 | bash | ok |
| Secret Rotation Validator | bash | sonnet5-1m-low | 4.3min | 32 | 1 | $0.99 | 3.5 | bash | ok |
| Secret Rotation Validator | bash | sonnet5-1m-medium | 9.3min | 0 | 4 | $0.00 | 4.5 | bash | cli_error |
| Secret Rotation Validator | default | sonnet5-1m-high | 12.7min | 69 | 0 | $3.58 | 4.0 | python | ok |
| Secret Rotation Validator | default | sonnet5-1m-low | 9.0min | 46 | 1 | $1.50 | 2.5 | python | ok |
| Secret Rotation Validator | default | sonnet5-1m-medium | 5.5min | 38 | 3 | $1.44 | 2.5 | python | ok |
| Secret Rotation Validator | powershell | sonnet5-1m-high | 30.0min | 0 | 0 | $0.00 | 4.0 | powershell | timeout |
| Secret Rotation Validator | powershell | sonnet5-1m-high | 22.6min | 102 | 2 | $4.46 | 4.5 | powershell | ok |
| Secret Rotation Validator | powershell | sonnet5-1m-low | 15.4min | 54 | 1 | $1.98 | 4.0 | powershell | ok |
| Secret Rotation Validator | powershell | sonnet5-1m-medium | 10.2min | 43 | 0 | $1.49 | 3.5 | powershell | ok |
| Secret Rotation Validator | powershell | sonnet5-1m-medium | 15.4min | 83 | 0 | $2.81 | 2.0 | powershell | ok |
| Secret Rotation Validator | typescript-bun | sonnet5-1m-high | 25.3min | 136 | 1 | $6.32 | 5.0 | typescript | ok |
| Secret Rotation Validator | typescript-bun | sonnet5-1m-low | 6.9min | 3 | 5 | $0.16 | 1.5 | typescript | ok |
| Secret Rotation Validator | typescript-bun | sonnet5-1m-medium | 11.2min | 65 | 1 | $2.19 | 3.5 | typescript | ok |
| Semantic Version Bumper | bash | sonnet5-1m-high | 11.8min | 57 | 3 | $2.84 | 1.5 | bash | ok |
| Semantic Version Bumper | bash | sonnet5-1m-low | 12.5min | 27 | 0 | $0.96 | 4.0 | bash | ok |
| Semantic Version Bumper | bash | sonnet5-1m-medium | 8.7min | 85 | 4 | $2.67 | 4.0 | bash | ok |
| Semantic Version Bumper | default | sonnet5-1m-high | 12.5min | 80 | 2 | $3.54 | 4.5 | python | ok |
| Semantic Version Bumper | default | sonnet5-1m-low | 4.1min | 26 | 0 | $1.02 | 1.5 | python | ok |
| Semantic Version Bumper | default | sonnet5-1m-medium | 5.1min | 33 | 2 | $1.28 | 4.0 | python | ok |
| Semantic Version Bumper | powershell | sonnet5-1m-high | 30.0min | 0 | 1 | $0.00 | 4.0 | powershell | timeout |
| Semantic Version Bumper | powershell | sonnet5-1m-high | 26.7min | 111 | 0 | $5.41 | 4.0 | powershell | ok |
| Semantic Version Bumper | powershell | sonnet5-1m-low | 9.6min | 43 | 0 | $1.43 | 2.0 | powershell | ok |
| Semantic Version Bumper | powershell | sonnet5-1m-low | 7.5min | 32 | 2 | $1.02 | 3.5 | powershell | ok |
| Semantic Version Bumper | powershell | sonnet5-1m-medium | 13.0min | 60 | 0 | $1.99 | 4.5 | powershell | ok |
| Semantic Version Bumper | powershell | sonnet5-1m-medium | 10.2min | 40 | 0 | $1.42 | 4.5 | powershell | ok |
| Semantic Version Bumper | typescript-bun | sonnet5-1m-high | 18.6min | 127 | 8 | $6.16 | 4.5 | typescript | ok |
| Semantic Version Bumper | typescript-bun | sonnet5-1m-low | 8.0min | 47 | 0 | $1.84 | 4.5 | typescript | ok |
| Semantic Version Bumper | typescript-bun | sonnet5-1m-medium | 11.7min | 69 | 1 | $2.15 | 3.5 | typescript | ok |
| Test Results Aggregator | bash | sonnet5-1m-high | 17.1min | 108 | 6 | $5.57 | 4.5 | bash | ok |
| Test Results Aggregator | bash | sonnet5-1m-low | 5.8min | 2 | 4 | $0.15 | 2.0 | bash | ok |
| Test Results Aggregator | bash | sonnet5-1m-medium | 8.5min | 46 | 0 | $1.80 | 3.5 | bash | ok |
| Test Results Aggregator | default | sonnet5-1m-high | 12.7min | 59 | 0 | $3.47 | 3.5 | python | ok |
| Test Results Aggregator | default | sonnet5-1m-low | 7.3min | 54 | 1 | $1.62 | 2.0 | python | ok |
| Test Results Aggregator | default | sonnet5-1m-medium | 10.1min | 61 | 0 | $2.37 | 2.0 | python | ok |
| Test Results Aggregator | powershell | sonnet5-1m-high | 30.0min | 0 | 0 | $0.00 | 4.5 | powershell | timeout |
| Test Results Aggregator | powershell | sonnet5-1m-high | 26.0min | 87 | 4 | $4.82 | 3.5 | powershell | ok |
| Test Results Aggregator | powershell | sonnet5-1m-low | 7.6min | 33 | 0 | $0.94 | 3.5 | powershell | ok |
| Test Results Aggregator | powershell | sonnet5-1m-medium | 12.6min | 58 | 0 | $2.54 | 3.5 | powershell | ok |
| Test Results Aggregator | powershell | sonnet5-1m-medium | 13.3min | 69 | 0 | $2.19 | 3.5 | powershell | ok |
| Test Results Aggregator | typescript-bun | sonnet5-1m-high | 25.3min | 143 | 2 | $7.29 | 4.5 | typescript | ok |
| Test Results Aggregator | typescript-bun | sonnet5-1m-low | 12.0min | 66 | 1 | $2.08 | 1.5 | typescript | ok |
| Test Results Aggregator | typescript-bun | sonnet5-1m-medium | 12.8min | 101 | 1 | $2.92 | 2.5 | typescript | ok |


<details>
<summary>Sorted by cost (cheapest first)</summary>

| Task | Language | Model | Duration | Turns | Errors | Cost | Tests Quality | Chosen | Status |
|------|----------|-------|----------|-------|--------|------|-----------|--------|--------|
| Semantic Version Bumper | powershell | sonnet5-1m-high | 30.0min | 0 | 1 | $0.00 | 4.0 | powershell | timeout |
| PR Label Assigner | bash | sonnet5-1m-high | 30.0min | 0 | 2 | $0.00 | 4.5 | bash | timeout |
| PR Label Assigner | powershell | sonnet5-1m-high | 30.0min | 0 | 1 | $0.00 | 4.5 | powershell | timeout |
| PR Label Assigner | powershell | sonnet5-1m-high | 30.0min | 0 | 4 | $0.00 | 3.5 | powershell | timeout |
| Test Results Aggregator | powershell | sonnet5-1m-high | 30.0min | 0 | 0 | $0.00 | 4.5 | powershell | timeout |
| Secret Rotation Validator | bash | sonnet5-1m-medium | 9.3min | 0 | 4 | $0.00 | 4.5 | bash | cli_error |
| Secret Rotation Validator | powershell | sonnet5-1m-high | 30.0min | 0 | 0 | $0.00 | 4.0 | powershell | timeout |
| Artifact Cleanup Script | bash | sonnet5-1m-low | 13.7min | 2 | 6 | $0.14 | 4.0 | bash | ok |
| Test Results Aggregator | bash | sonnet5-1m-low | 5.8min | 2 | 4 | $0.15 | 2.0 | bash | ok |
| Secret Rotation Validator | typescript-bun | sonnet5-1m-low | 6.9min | 3 | 5 | $0.16 | 1.5 | typescript | ok |
| PR Label Assigner | default | sonnet5-1m-low | 3.7min | 24 | 0 | $0.75 | 4.5 | python | ok |
| PR Label Assigner | bash | sonnet5-1m-low | 3.4min | 28 | 1 | $0.76 | 2.0 | bash | ok |
| Environment Matrix Generator | default | sonnet5-1m-low | 10.7min | 26 | 1 | $0.84 | 2.0 | python | ok |
| PR Label Assigner | typescript-bun | sonnet5-1m-low | 4.6min | 33 | 0 | $0.91 | 2.0 | typescript | ok |
| Test Results Aggregator | powershell | sonnet5-1m-low | 7.6min | 33 | 0 | $0.94 | 3.5 | powershell | ok |
| PR Label Assigner | powershell | sonnet5-1m-low | 6.0min | 34 | 1 | $0.96 | 3.5 | powershell | ok |
| Semantic Version Bumper | bash | sonnet5-1m-low | 12.5min | 27 | 0 | $0.96 | 4.0 | bash | ok |
| Secret Rotation Validator | bash | sonnet5-1m-low | 4.3min | 32 | 1 | $0.99 | 3.5 | bash | ok |
| Semantic Version Bumper | default | sonnet5-1m-low | 4.1min | 26 | 0 | $1.02 | 1.5 | python | ok |
| Semantic Version Bumper | powershell | sonnet5-1m-low | 7.5min | 32 | 2 | $1.02 | 3.5 | powershell | ok |
| Artifact Cleanup Script | powershell | sonnet5-1m-low | 7.5min | 35 | 0 | $1.05 | 2.0 | powershell | ok |
| Artifact Cleanup Script | default | sonnet5-1m-low | 4.5min | 32 | 0 | $1.07 | 4.0 | python | ok |
| Environment Matrix Generator | powershell | sonnet5-1m-low | 7.4min | 3 | 0 | $1.10 | 2.5 | powershell | ok |
| Dependency License Checker | default | sonnet5-1m-low | 4.9min | 34 | 0 | $1.13 | 4.5 | python | ok |
| Dependency License Checker | powershell | sonnet5-1m-low | 7.6min | 39 | 0 | $1.17 | 2.0 | powershell | ok |
| PR Label Assigner | powershell | sonnet5-1m-medium | 8.7min | 27 | 1 | $1.19 | 2.0 | powershell | ok |
| Environment Matrix Generator | bash | sonnet5-1m-low | 5.3min | 42 | 1 | $1.21 | 2.0 | bash | ok |
| Environment Matrix Generator | typescript-bun | sonnet5-1m-low | 5.8min | 36 | 2 | $1.26 | 1.5 | typescript | ok |
| Semantic Version Bumper | default | sonnet5-1m-medium | 5.1min | 33 | 2 | $1.28 | 4.0 | python | ok |
| Artifact Cleanup Script | typescript-bun | sonnet5-1m-low | 9.3min | 46 | 0 | $1.30 | 1.5 | typescript | ok |
| Dependency License Checker | bash | sonnet5-1m-low | 12.3min | 49 | 4 | $1.36 | 2.5 | bash | ok |
| Semantic Version Bumper | powershell | sonnet5-1m-medium | 10.2min | 40 | 0 | $1.42 | 4.5 | powershell | ok |
| Semantic Version Bumper | powershell | sonnet5-1m-low | 9.6min | 43 | 0 | $1.43 | 2.0 | powershell | ok |
| Secret Rotation Validator | default | sonnet5-1m-medium | 5.5min | 38 | 3 | $1.44 | 2.5 | python | ok |
| Secret Rotation Validator | powershell | sonnet5-1m-medium | 10.2min | 43 | 0 | $1.49 | 3.5 | powershell | ok |
| PR Label Assigner | powershell | sonnet5-1m-low | 11.3min | 48 | 1 | $1.50 | 2.0 | powershell | ok |
| Secret Rotation Validator | default | sonnet5-1m-low | 9.0min | 46 | 1 | $1.50 | 2.5 | python | ok |
| PR Label Assigner | powershell | sonnet5-1m-medium | 9.6min | 40 | 0 | $1.58 | 4.5 | powershell | ok |
| Test Results Aggregator | default | sonnet5-1m-low | 7.3min | 54 | 1 | $1.62 | 2.0 | python | ok |
| Environment Matrix Generator | default | sonnet5-1m-medium | 6.9min | 59 | 0 | $1.72 | 4.0 | python | ok |
| Dependency License Checker | typescript-bun | sonnet5-1m-low | 10.4min | 63 | 3 | $1.73 | 2.0 | typescript | ok |
| Test Results Aggregator | bash | sonnet5-1m-medium | 8.5min | 46 | 0 | $1.80 | 3.5 | bash | ok |
| Semantic Version Bumper | typescript-bun | sonnet5-1m-low | 8.0min | 47 | 0 | $1.84 | 4.5 | typescript | ok |
| Artifact Cleanup Script | powershell | sonnet5-1m-medium | 11.3min | 38 | 0 | $1.90 | 4.5 | powershell | ok |
| Secret Rotation Validator | powershell | sonnet5-1m-low | 15.4min | 54 | 1 | $1.98 | 4.0 | powershell | ok |
| Dependency License Checker | default | sonnet5-1m-high | 9.9min | 39 | 1 | $1.99 | 3.0 | python | ok |
| Semantic Version Bumper | powershell | sonnet5-1m-medium | 13.0min | 60 | 0 | $1.99 | 4.5 | powershell | ok |
| PR Label Assigner | default | sonnet5-1m-medium | 9.5min | 64 | 1 | $2.04 | 2.0 | powershell | ok |
| Test Results Aggregator | typescript-bun | sonnet5-1m-low | 12.0min | 66 | 1 | $2.08 | 1.5 | typescript | ok |
| Dependency License Checker | powershell | sonnet5-1m-medium | 13.5min | 52 | 3 | $2.14 | 4.0 | powershell | ok |
| Semantic Version Bumper | typescript-bun | sonnet5-1m-medium | 11.7min | 69 | 1 | $2.15 | 3.5 | typescript | ok |
| Test Results Aggregator | powershell | sonnet5-1m-medium | 13.3min | 69 | 0 | $2.19 | 3.5 | powershell | ok |
| Secret Rotation Validator | typescript-bun | sonnet5-1m-medium | 11.2min | 65 | 1 | $2.19 | 3.5 | typescript | ok |
| PR Label Assigner | typescript-bun | sonnet5-1m-medium | 11.0min | 63 | 2 | $2.28 | 4.0 | typescript | ok |
| Test Results Aggregator | default | sonnet5-1m-medium | 10.1min | 61 | 0 | $2.37 | 2.0 | python | ok |
| Dependency License Checker | bash | sonnet5-1m-medium | 11.0min | 74 | 4 | $2.43 | 3.5 | bash | ok |
| Dependency License Checker | default | sonnet5-1m-medium | 8.9min | 73 | 0 | $2.48 | 2.5 | python | ok |
| Test Results Aggregator | powershell | sonnet5-1m-medium | 12.6min | 58 | 0 | $2.54 | 3.5 | powershell | ok |
| Semantic Version Bumper | bash | sonnet5-1m-medium | 8.7min | 85 | 4 | $2.67 | 4.0 | bash | ok |
| Dependency License Checker | powershell | sonnet5-1m-high | 14.6min | 58 | 1 | $2.80 | 4.5 | powershell | ok |
| Secret Rotation Validator | powershell | sonnet5-1m-medium | 15.4min | 83 | 0 | $2.81 | 2.0 | powershell | ok |
| Environment Matrix Generator | powershell | sonnet5-1m-medium | 15.8min | 55 | 0 | $2.82 | 4.0 | powershell | ok |
| Dependency License Checker | typescript-bun | sonnet5-1m-medium | 13.6min | 93 | 1 | $2.82 | 4.5 | typescript | ok |
| Semantic Version Bumper | bash | sonnet5-1m-high | 11.8min | 57 | 3 | $2.84 | 1.5 | bash | ok |
| Environment Matrix Generator | bash | sonnet5-1m-medium | 14.2min | 67 | 0 | $2.90 | 4.0 | bash | ok |
| Test Results Aggregator | typescript-bun | sonnet5-1m-medium | 12.8min | 101 | 1 | $2.92 | 2.5 | typescript | ok |
| Dependency License Checker | powershell | sonnet5-1m-high | 16.8min | 80 | 0 | $3.03 | 4.5 | powershell | ok |
| Artifact Cleanup Script | default | sonnet5-1m-medium | 11.5min | 86 | 3 | $3.10 | 4.5 | python | ok |
| Environment Matrix Generator | typescript-bun | sonnet5-1m-medium | 17.0min | 87 | 4 | $3.12 | 2.0 | typescript | ok |
| Artifact Cleanup Script | typescript-bun | sonnet5-1m-medium | 13.7min | 109 | 0 | $3.28 | 2.0 | typescript | ok |
| Artifact Cleanup Script | powershell | sonnet5-1m-medium | 16.6min | 64 | 2 | $3.28 | 2.0 | powershell | ok |
| Artifact Cleanup Script | bash | sonnet5-1m-medium | 16.9min | 80 | 7 | $3.35 | 3.5 | bash | ok |
| Artifact Cleanup Script | bash | sonnet5-1m-high | 11.8min | 59 | 4 | $3.37 | 4.0 | bash | ok |
| Environment Matrix Generator | powershell | sonnet5-1m-medium | 16.5min | 99 | 1 | $3.46 | 4.5 | powershell | ok |
| Test Results Aggregator | default | sonnet5-1m-high | 12.7min | 59 | 0 | $3.47 | 3.5 | python | ok |
| Semantic Version Bumper | default | sonnet5-1m-high | 12.5min | 80 | 2 | $3.54 | 4.5 | python | ok |
| Secret Rotation Validator | default | sonnet5-1m-high | 12.7min | 69 | 0 | $3.58 | 4.0 | python | ok |
| PR Label Assigner | default | sonnet5-1m-high | 11.6min | 80 | 0 | $3.61 | 4.5 | python | ok |
| Artifact Cleanup Script | default | sonnet5-1m-high | 18.0min | 76 | 1 | $3.61 | 1.0 | powershell | ok |
| PR Label Assigner | bash | sonnet5-1m-medium | 14.3min | 101 | 5 | $3.99 | 4.5 | bash | ok |
| Dependency License Checker | powershell | sonnet5-1m-medium | 18.8min | 70 | 0 | $4.02 | 4.5 | powershell | ok |
| PR Label Assigner | typescript-bun | sonnet5-1m-high | 18.3min | 106 | 0 | $4.13 | 4.5 | typescript | ok |
| Artifact Cleanup Script | powershell | sonnet5-1m-high | 21.2min | 79 | 0 | $4.33 | 4.5 | powershell | ok |
| Secret Rotation Validator | powershell | sonnet5-1m-high | 22.6min | 102 | 2 | $4.46 | 4.5 | powershell | ok |
| Environment Matrix Generator | typescript-bun | sonnet5-1m-high | 19.7min | 75 | 1 | $4.76 | 4.5 | typescript | ok |
| Test Results Aggregator | powershell | sonnet5-1m-high | 26.0min | 87 | 4 | $4.82 | 3.5 | powershell | ok |
| Environment Matrix Generator | default | sonnet5-1m-high | 16.4min | 94 | 2 | $5.01 | 4.5 | python | ok |
| Dependency License Checker | typescript-bun | sonnet5-1m-high | 18.4min | 137 | 11 | $5.28 | 4.5 | typescript | ok |
| Semantic Version Bumper | powershell | sonnet5-1m-high | 26.7min | 111 | 0 | $5.41 | 4.0 | powershell | ok |
| Artifact Cleanup Script | powershell | sonnet5-1m-high | 23.4min | 98 | 3 | $5.42 | 4.5 | powershell | ok |
| Environment Matrix Generator | powershell | sonnet5-1m-high | 25.4min | 82 | 0 | $5.48 | 4.5 | powershell | ok |
| Test Results Aggregator | bash | sonnet5-1m-high | 17.1min | 108 | 6 | $5.57 | 4.5 | bash | ok |
| Dependency License Checker | bash | sonnet5-1m-high | 17.4min | 105 | 3 | $5.57 | 4.0 | bash | ok |
| Artifact Cleanup Script | typescript-bun | sonnet5-1m-high | 23.5min | 150 | 2 | $6.00 | 2.5 | typescript | ok |
| Semantic Version Bumper | typescript-bun | sonnet5-1m-high | 18.6min | 127 | 8 | $6.16 | 4.5 | typescript | ok |
| Environment Matrix Generator | powershell | sonnet5-1m-high | 29.5min | 103 | 0 | $6.22 | 4.5 | powershell | ok |
| Secret Rotation Validator | bash | sonnet5-1m-high | 20.7min | 119 | 1 | $6.24 | 4.0 | bash | ok |
| Secret Rotation Validator | typescript-bun | sonnet5-1m-high | 25.3min | 136 | 1 | $6.32 | 5.0 | typescript | ok |
| Test Results Aggregator | typescript-bun | sonnet5-1m-high | 25.3min | 143 | 2 | $7.29 | 4.5 | typescript | ok |
| Environment Matrix Generator | bash | sonnet5-1m-high | 26.2min | 150 | 9 | $8.03 | 4.0 | bash | ok |

</details>

<details>
<summary>Sorted by duration (fastest first)</summary>

| Task | Language | Model | Duration | Turns | Errors | Cost | Tests Quality | Chosen | Status |
|------|----------|-------|----------|-------|--------|------|-----------|--------|--------|
| PR Label Assigner | bash | sonnet5-1m-low | 3.4min | 28 | 1 | $0.76 | 2.0 | bash | ok |
| PR Label Assigner | default | sonnet5-1m-low | 3.7min | 24 | 0 | $0.75 | 4.5 | python | ok |
| Semantic Version Bumper | default | sonnet5-1m-low | 4.1min | 26 | 0 | $1.02 | 1.5 | python | ok |
| Secret Rotation Validator | bash | sonnet5-1m-low | 4.3min | 32 | 1 | $0.99 | 3.5 | bash | ok |
| Artifact Cleanup Script | default | sonnet5-1m-low | 4.5min | 32 | 0 | $1.07 | 4.0 | python | ok |
| PR Label Assigner | typescript-bun | sonnet5-1m-low | 4.6min | 33 | 0 | $0.91 | 2.0 | typescript | ok |
| Dependency License Checker | default | sonnet5-1m-low | 4.9min | 34 | 0 | $1.13 | 4.5 | python | ok |
| Semantic Version Bumper | default | sonnet5-1m-medium | 5.1min | 33 | 2 | $1.28 | 4.0 | python | ok |
| Environment Matrix Generator | bash | sonnet5-1m-low | 5.3min | 42 | 1 | $1.21 | 2.0 | bash | ok |
| Secret Rotation Validator | default | sonnet5-1m-medium | 5.5min | 38 | 3 | $1.44 | 2.5 | python | ok |
| Test Results Aggregator | bash | sonnet5-1m-low | 5.8min | 2 | 4 | $0.15 | 2.0 | bash | ok |
| Environment Matrix Generator | typescript-bun | sonnet5-1m-low | 5.8min | 36 | 2 | $1.26 | 1.5 | typescript | ok |
| PR Label Assigner | powershell | sonnet5-1m-low | 6.0min | 34 | 1 | $0.96 | 3.5 | powershell | ok |
| Environment Matrix Generator | default | sonnet5-1m-medium | 6.9min | 59 | 0 | $1.72 | 4.0 | python | ok |
| Secret Rotation Validator | typescript-bun | sonnet5-1m-low | 6.9min | 3 | 5 | $0.16 | 1.5 | typescript | ok |
| Test Results Aggregator | default | sonnet5-1m-low | 7.3min | 54 | 1 | $1.62 | 2.0 | python | ok |
| Environment Matrix Generator | powershell | sonnet5-1m-low | 7.4min | 3 | 0 | $1.10 | 2.5 | powershell | ok |
| Artifact Cleanup Script | powershell | sonnet5-1m-low | 7.5min | 35 | 0 | $1.05 | 2.0 | powershell | ok |
| Semantic Version Bumper | powershell | sonnet5-1m-low | 7.5min | 32 | 2 | $1.02 | 3.5 | powershell | ok |
| Dependency License Checker | powershell | sonnet5-1m-low | 7.6min | 39 | 0 | $1.17 | 2.0 | powershell | ok |
| Test Results Aggregator | powershell | sonnet5-1m-low | 7.6min | 33 | 0 | $0.94 | 3.5 | powershell | ok |
| Semantic Version Bumper | typescript-bun | sonnet5-1m-low | 8.0min | 47 | 0 | $1.84 | 4.5 | typescript | ok |
| Test Results Aggregator | bash | sonnet5-1m-medium | 8.5min | 46 | 0 | $1.80 | 3.5 | bash | ok |
| PR Label Assigner | powershell | sonnet5-1m-medium | 8.7min | 27 | 1 | $1.19 | 2.0 | powershell | ok |
| Semantic Version Bumper | bash | sonnet5-1m-medium | 8.7min | 85 | 4 | $2.67 | 4.0 | bash | ok |
| Dependency License Checker | default | sonnet5-1m-medium | 8.9min | 73 | 0 | $2.48 | 2.5 | python | ok |
| Secret Rotation Validator | default | sonnet5-1m-low | 9.0min | 46 | 1 | $1.50 | 2.5 | python | ok |
| Secret Rotation Validator | bash | sonnet5-1m-medium | 9.3min | 0 | 4 | $0.00 | 4.5 | bash | cli_error |
| Artifact Cleanup Script | typescript-bun | sonnet5-1m-low | 9.3min | 46 | 0 | $1.30 | 1.5 | typescript | ok |
| PR Label Assigner | default | sonnet5-1m-medium | 9.5min | 64 | 1 | $2.04 | 2.0 | powershell | ok |
| PR Label Assigner | powershell | sonnet5-1m-medium | 9.6min | 40 | 0 | $1.58 | 4.5 | powershell | ok |
| Semantic Version Bumper | powershell | sonnet5-1m-low | 9.6min | 43 | 0 | $1.43 | 2.0 | powershell | ok |
| Dependency License Checker | default | sonnet5-1m-high | 9.9min | 39 | 1 | $1.99 | 3.0 | python | ok |
| Test Results Aggregator | default | sonnet5-1m-medium | 10.1min | 61 | 0 | $2.37 | 2.0 | python | ok |
| Secret Rotation Validator | powershell | sonnet5-1m-medium | 10.2min | 43 | 0 | $1.49 | 3.5 | powershell | ok |
| Semantic Version Bumper | powershell | sonnet5-1m-medium | 10.2min | 40 | 0 | $1.42 | 4.5 | powershell | ok |
| Dependency License Checker | typescript-bun | sonnet5-1m-low | 10.4min | 63 | 3 | $1.73 | 2.0 | typescript | ok |
| Environment Matrix Generator | default | sonnet5-1m-low | 10.7min | 26 | 1 | $0.84 | 2.0 | python | ok |
| Dependency License Checker | bash | sonnet5-1m-medium | 11.0min | 74 | 4 | $2.43 | 3.5 | bash | ok |
| PR Label Assigner | typescript-bun | sonnet5-1m-medium | 11.0min | 63 | 2 | $2.28 | 4.0 | typescript | ok |
| Secret Rotation Validator | typescript-bun | sonnet5-1m-medium | 11.2min | 65 | 1 | $2.19 | 3.5 | typescript | ok |
| PR Label Assigner | powershell | sonnet5-1m-low | 11.3min | 48 | 1 | $1.50 | 2.0 | powershell | ok |
| Artifact Cleanup Script | powershell | sonnet5-1m-medium | 11.3min | 38 | 0 | $1.90 | 4.5 | powershell | ok |
| Artifact Cleanup Script | default | sonnet5-1m-medium | 11.5min | 86 | 3 | $3.10 | 4.5 | python | ok |
| PR Label Assigner | default | sonnet5-1m-high | 11.6min | 80 | 0 | $3.61 | 4.5 | python | ok |
| Semantic Version Bumper | typescript-bun | sonnet5-1m-medium | 11.7min | 69 | 1 | $2.15 | 3.5 | typescript | ok |
| Semantic Version Bumper | bash | sonnet5-1m-high | 11.8min | 57 | 3 | $2.84 | 1.5 | bash | ok |
| Artifact Cleanup Script | bash | sonnet5-1m-high | 11.8min | 59 | 4 | $3.37 | 4.0 | bash | ok |
| Test Results Aggregator | typescript-bun | sonnet5-1m-low | 12.0min | 66 | 1 | $2.08 | 1.5 | typescript | ok |
| Dependency License Checker | bash | sonnet5-1m-low | 12.3min | 49 | 4 | $1.36 | 2.5 | bash | ok |
| Semantic Version Bumper | default | sonnet5-1m-high | 12.5min | 80 | 2 | $3.54 | 4.5 | python | ok |
| Semantic Version Bumper | bash | sonnet5-1m-low | 12.5min | 27 | 0 | $0.96 | 4.0 | bash | ok |
| Test Results Aggregator | powershell | sonnet5-1m-medium | 12.6min | 58 | 0 | $2.54 | 3.5 | powershell | ok |
| Test Results Aggregator | default | sonnet5-1m-high | 12.7min | 59 | 0 | $3.47 | 3.5 | python | ok |
| Secret Rotation Validator | default | sonnet5-1m-high | 12.7min | 69 | 0 | $3.58 | 4.0 | python | ok |
| Test Results Aggregator | typescript-bun | sonnet5-1m-medium | 12.8min | 101 | 1 | $2.92 | 2.5 | typescript | ok |
| Semantic Version Bumper | powershell | sonnet5-1m-medium | 13.0min | 60 | 0 | $1.99 | 4.5 | powershell | ok |
| Test Results Aggregator | powershell | sonnet5-1m-medium | 13.3min | 69 | 0 | $2.19 | 3.5 | powershell | ok |
| Dependency License Checker | powershell | sonnet5-1m-medium | 13.5min | 52 | 3 | $2.14 | 4.0 | powershell | ok |
| Dependency License Checker | typescript-bun | sonnet5-1m-medium | 13.6min | 93 | 1 | $2.82 | 4.5 | typescript | ok |
| Artifact Cleanup Script | bash | sonnet5-1m-low | 13.7min | 2 | 6 | $0.14 | 4.0 | bash | ok |
| Artifact Cleanup Script | typescript-bun | sonnet5-1m-medium | 13.7min | 109 | 0 | $3.28 | 2.0 | typescript | ok |
| Environment Matrix Generator | bash | sonnet5-1m-medium | 14.2min | 67 | 0 | $2.90 | 4.0 | bash | ok |
| PR Label Assigner | bash | sonnet5-1m-medium | 14.3min | 101 | 5 | $3.99 | 4.5 | bash | ok |
| Dependency License Checker | powershell | sonnet5-1m-high | 14.6min | 58 | 1 | $2.80 | 4.5 | powershell | ok |
| Secret Rotation Validator | powershell | sonnet5-1m-medium | 15.4min | 83 | 0 | $2.81 | 2.0 | powershell | ok |
| Secret Rotation Validator | powershell | sonnet5-1m-low | 15.4min | 54 | 1 | $1.98 | 4.0 | powershell | ok |
| Environment Matrix Generator | powershell | sonnet5-1m-medium | 15.8min | 55 | 0 | $2.82 | 4.0 | powershell | ok |
| Environment Matrix Generator | default | sonnet5-1m-high | 16.4min | 94 | 2 | $5.01 | 4.5 | python | ok |
| Environment Matrix Generator | powershell | sonnet5-1m-medium | 16.5min | 99 | 1 | $3.46 | 4.5 | powershell | ok |
| Artifact Cleanup Script | powershell | sonnet5-1m-medium | 16.6min | 64 | 2 | $3.28 | 2.0 | powershell | ok |
| Dependency License Checker | powershell | sonnet5-1m-high | 16.8min | 80 | 0 | $3.03 | 4.5 | powershell | ok |
| Artifact Cleanup Script | bash | sonnet5-1m-medium | 16.9min | 80 | 7 | $3.35 | 3.5 | bash | ok |
| Environment Matrix Generator | typescript-bun | sonnet5-1m-medium | 17.0min | 87 | 4 | $3.12 | 2.0 | typescript | ok |
| Test Results Aggregator | bash | sonnet5-1m-high | 17.1min | 108 | 6 | $5.57 | 4.5 | bash | ok |
| Dependency License Checker | bash | sonnet5-1m-high | 17.4min | 105 | 3 | $5.57 | 4.0 | bash | ok |
| Artifact Cleanup Script | default | sonnet5-1m-high | 18.0min | 76 | 1 | $3.61 | 1.0 | powershell | ok |
| PR Label Assigner | typescript-bun | sonnet5-1m-high | 18.3min | 106 | 0 | $4.13 | 4.5 | typescript | ok |
| Dependency License Checker | typescript-bun | sonnet5-1m-high | 18.4min | 137 | 11 | $5.28 | 4.5 | typescript | ok |
| Semantic Version Bumper | typescript-bun | sonnet5-1m-high | 18.6min | 127 | 8 | $6.16 | 4.5 | typescript | ok |
| Dependency License Checker | powershell | sonnet5-1m-medium | 18.8min | 70 | 0 | $4.02 | 4.5 | powershell | ok |
| Environment Matrix Generator | typescript-bun | sonnet5-1m-high | 19.7min | 75 | 1 | $4.76 | 4.5 | typescript | ok |
| Secret Rotation Validator | bash | sonnet5-1m-high | 20.7min | 119 | 1 | $6.24 | 4.0 | bash | ok |
| Artifact Cleanup Script | powershell | sonnet5-1m-high | 21.2min | 79 | 0 | $4.33 | 4.5 | powershell | ok |
| Secret Rotation Validator | powershell | sonnet5-1m-high | 22.6min | 102 | 2 | $4.46 | 4.5 | powershell | ok |
| Artifact Cleanup Script | powershell | sonnet5-1m-high | 23.4min | 98 | 3 | $5.42 | 4.5 | powershell | ok |
| Artifact Cleanup Script | typescript-bun | sonnet5-1m-high | 23.5min | 150 | 2 | $6.00 | 2.5 | typescript | ok |
| Secret Rotation Validator | typescript-bun | sonnet5-1m-high | 25.3min | 136 | 1 | $6.32 | 5.0 | typescript | ok |
| Test Results Aggregator | typescript-bun | sonnet5-1m-high | 25.3min | 143 | 2 | $7.29 | 4.5 | typescript | ok |
| Environment Matrix Generator | powershell | sonnet5-1m-high | 25.4min | 82 | 0 | $5.48 | 4.5 | powershell | ok |
| Test Results Aggregator | powershell | sonnet5-1m-high | 26.0min | 87 | 4 | $4.82 | 3.5 | powershell | ok |
| Environment Matrix Generator | bash | sonnet5-1m-high | 26.2min | 150 | 9 | $8.03 | 4.0 | bash | ok |
| Semantic Version Bumper | powershell | sonnet5-1m-high | 26.7min | 111 | 0 | $5.41 | 4.0 | powershell | ok |
| Environment Matrix Generator | powershell | sonnet5-1m-high | 29.5min | 103 | 0 | $6.22 | 4.5 | powershell | ok |
| Test Results Aggregator | powershell | sonnet5-1m-high | 30.0min | 0 | 0 | $0.00 | 4.5 | powershell | timeout |
| Secret Rotation Validator | powershell | sonnet5-1m-high | 30.0min | 0 | 0 | $0.00 | 4.0 | powershell | timeout |
| Semantic Version Bumper | powershell | sonnet5-1m-high | 30.0min | 0 | 1 | $0.00 | 4.0 | powershell | timeout |
| PR Label Assigner | powershell | sonnet5-1m-high | 30.0min | 0 | 4 | $0.00 | 3.5 | powershell | timeout |
| PR Label Assigner | bash | sonnet5-1m-high | 30.0min | 0 | 2 | $0.00 | 4.5 | bash | timeout |
| PR Label Assigner | powershell | sonnet5-1m-high | 30.0min | 0 | 1 | $0.00 | 4.5 | powershell | timeout |

</details>

<details>
<summary>Sorted by errors (fewest first)</summary>

| Task | Language | Model | Duration | Turns | Errors | Cost | Tests Quality | Chosen | Status |
|------|----------|-------|----------|-------|--------|------|-----------|--------|--------|
| Semantic Version Bumper | bash | sonnet5-1m-low | 12.5min | 27 | 0 | $0.96 | 4.0 | bash | ok |
| Semantic Version Bumper | default | sonnet5-1m-low | 4.1min | 26 | 0 | $1.02 | 1.5 | python | ok |
| Semantic Version Bumper | powershell | sonnet5-1m-medium | 13.0min | 60 | 0 | $1.99 | 4.5 | powershell | ok |
| Semantic Version Bumper | powershell | sonnet5-1m-low | 9.6min | 43 | 0 | $1.43 | 2.0 | powershell | ok |
| Semantic Version Bumper | powershell | sonnet5-1m-high | 26.7min | 111 | 0 | $5.41 | 4.0 | powershell | ok |
| Semantic Version Bumper | powershell | sonnet5-1m-medium | 10.2min | 40 | 0 | $1.42 | 4.5 | powershell | ok |
| Semantic Version Bumper | typescript-bun | sonnet5-1m-low | 8.0min | 47 | 0 | $1.84 | 4.5 | typescript | ok |
| PR Label Assigner | default | sonnet5-1m-high | 11.6min | 80 | 0 | $3.61 | 4.5 | python | ok |
| PR Label Assigner | default | sonnet5-1m-low | 3.7min | 24 | 0 | $0.75 | 4.5 | python | ok |
| PR Label Assigner | powershell | sonnet5-1m-medium | 9.6min | 40 | 0 | $1.58 | 4.5 | powershell | ok |
| PR Label Assigner | typescript-bun | sonnet5-1m-high | 18.3min | 106 | 0 | $4.13 | 4.5 | typescript | ok |
| PR Label Assigner | typescript-bun | sonnet5-1m-low | 4.6min | 33 | 0 | $0.91 | 2.0 | typescript | ok |
| Dependency License Checker | default | sonnet5-1m-medium | 8.9min | 73 | 0 | $2.48 | 2.5 | python | ok |
| Dependency License Checker | default | sonnet5-1m-low | 4.9min | 34 | 0 | $1.13 | 4.5 | python | ok |
| Dependency License Checker | powershell | sonnet5-1m-high | 16.8min | 80 | 0 | $3.03 | 4.5 | powershell | ok |
| Dependency License Checker | powershell | sonnet5-1m-low | 7.6min | 39 | 0 | $1.17 | 2.0 | powershell | ok |
| Dependency License Checker | powershell | sonnet5-1m-medium | 18.8min | 70 | 0 | $4.02 | 4.5 | powershell | ok |
| Test Results Aggregator | bash | sonnet5-1m-medium | 8.5min | 46 | 0 | $1.80 | 3.5 | bash | ok |
| Test Results Aggregator | default | sonnet5-1m-high | 12.7min | 59 | 0 | $3.47 | 3.5 | python | ok |
| Test Results Aggregator | default | sonnet5-1m-medium | 10.1min | 61 | 0 | $2.37 | 2.0 | python | ok |
| Test Results Aggregator | powershell | sonnet5-1m-high | 30.0min | 0 | 0 | $0.00 | 4.5 | powershell | timeout |
| Test Results Aggregator | powershell | sonnet5-1m-medium | 12.6min | 58 | 0 | $2.54 | 3.5 | powershell | ok |
| Test Results Aggregator | powershell | sonnet5-1m-low | 7.6min | 33 | 0 | $0.94 | 3.5 | powershell | ok |
| Test Results Aggregator | powershell | sonnet5-1m-medium | 13.3min | 69 | 0 | $2.19 | 3.5 | powershell | ok |
| Environment Matrix Generator | bash | sonnet5-1m-medium | 14.2min | 67 | 0 | $2.90 | 4.0 | bash | ok |
| Environment Matrix Generator | default | sonnet5-1m-medium | 6.9min | 59 | 0 | $1.72 | 4.0 | python | ok |
| Environment Matrix Generator | powershell | sonnet5-1m-high | 29.5min | 103 | 0 | $6.22 | 4.5 | powershell | ok |
| Environment Matrix Generator | powershell | sonnet5-1m-low | 7.4min | 3 | 0 | $1.10 | 2.5 | powershell | ok |
| Environment Matrix Generator | powershell | sonnet5-1m-high | 25.4min | 82 | 0 | $5.48 | 4.5 | powershell | ok |
| Environment Matrix Generator | powershell | sonnet5-1m-medium | 15.8min | 55 | 0 | $2.82 | 4.0 | powershell | ok |
| Artifact Cleanup Script | default | sonnet5-1m-low | 4.5min | 32 | 0 | $1.07 | 4.0 | python | ok |
| Artifact Cleanup Script | powershell | sonnet5-1m-medium | 11.3min | 38 | 0 | $1.90 | 4.5 | powershell | ok |
| Artifact Cleanup Script | powershell | sonnet5-1m-low | 7.5min | 35 | 0 | $1.05 | 2.0 | powershell | ok |
| Artifact Cleanup Script | powershell | sonnet5-1m-high | 21.2min | 79 | 0 | $4.33 | 4.5 | powershell | ok |
| Artifact Cleanup Script | typescript-bun | sonnet5-1m-medium | 13.7min | 109 | 0 | $3.28 | 2.0 | typescript | ok |
| Artifact Cleanup Script | typescript-bun | sonnet5-1m-low | 9.3min | 46 | 0 | $1.30 | 1.5 | typescript | ok |
| Secret Rotation Validator | default | sonnet5-1m-high | 12.7min | 69 | 0 | $3.58 | 4.0 | python | ok |
| Secret Rotation Validator | powershell | sonnet5-1m-high | 30.0min | 0 | 0 | $0.00 | 4.0 | powershell | timeout |
| Secret Rotation Validator | powershell | sonnet5-1m-medium | 10.2min | 43 | 0 | $1.49 | 3.5 | powershell | ok |
| Secret Rotation Validator | powershell | sonnet5-1m-medium | 15.4min | 83 | 0 | $2.81 | 2.0 | powershell | ok |
| Semantic Version Bumper | powershell | sonnet5-1m-high | 30.0min | 0 | 1 | $0.00 | 4.0 | powershell | timeout |
| Semantic Version Bumper | typescript-bun | sonnet5-1m-medium | 11.7min | 69 | 1 | $2.15 | 3.5 | typescript | ok |
| PR Label Assigner | bash | sonnet5-1m-low | 3.4min | 28 | 1 | $0.76 | 2.0 | bash | ok |
| PR Label Assigner | default | sonnet5-1m-medium | 9.5min | 64 | 1 | $2.04 | 2.0 | powershell | ok |
| PR Label Assigner | powershell | sonnet5-1m-high | 30.0min | 0 | 1 | $0.00 | 4.5 | powershell | timeout |
| PR Label Assigner | powershell | sonnet5-1m-low | 6.0min | 34 | 1 | $0.96 | 3.5 | powershell | ok |
| PR Label Assigner | powershell | sonnet5-1m-medium | 8.7min | 27 | 1 | $1.19 | 2.0 | powershell | ok |
| PR Label Assigner | powershell | sonnet5-1m-low | 11.3min | 48 | 1 | $1.50 | 2.0 | powershell | ok |
| Dependency License Checker | default | sonnet5-1m-high | 9.9min | 39 | 1 | $1.99 | 3.0 | python | ok |
| Dependency License Checker | powershell | sonnet5-1m-high | 14.6min | 58 | 1 | $2.80 | 4.5 | powershell | ok |
| Dependency License Checker | typescript-bun | sonnet5-1m-medium | 13.6min | 93 | 1 | $2.82 | 4.5 | typescript | ok |
| Test Results Aggregator | default | sonnet5-1m-low | 7.3min | 54 | 1 | $1.62 | 2.0 | python | ok |
| Test Results Aggregator | typescript-bun | sonnet5-1m-medium | 12.8min | 101 | 1 | $2.92 | 2.5 | typescript | ok |
| Test Results Aggregator | typescript-bun | sonnet5-1m-low | 12.0min | 66 | 1 | $2.08 | 1.5 | typescript | ok |
| Environment Matrix Generator | bash | sonnet5-1m-low | 5.3min | 42 | 1 | $1.21 | 2.0 | bash | ok |
| Environment Matrix Generator | default | sonnet5-1m-low | 10.7min | 26 | 1 | $0.84 | 2.0 | python | ok |
| Environment Matrix Generator | powershell | sonnet5-1m-medium | 16.5min | 99 | 1 | $3.46 | 4.5 | powershell | ok |
| Environment Matrix Generator | typescript-bun | sonnet5-1m-high | 19.7min | 75 | 1 | $4.76 | 4.5 | typescript | ok |
| Artifact Cleanup Script | default | sonnet5-1m-high | 18.0min | 76 | 1 | $3.61 | 1.0 | powershell | ok |
| Secret Rotation Validator | bash | sonnet5-1m-high | 20.7min | 119 | 1 | $6.24 | 4.0 | bash | ok |
| Secret Rotation Validator | bash | sonnet5-1m-low | 4.3min | 32 | 1 | $0.99 | 3.5 | bash | ok |
| Secret Rotation Validator | default | sonnet5-1m-low | 9.0min | 46 | 1 | $1.50 | 2.5 | python | ok |
| Secret Rotation Validator | powershell | sonnet5-1m-low | 15.4min | 54 | 1 | $1.98 | 4.0 | powershell | ok |
| Secret Rotation Validator | typescript-bun | sonnet5-1m-high | 25.3min | 136 | 1 | $6.32 | 5.0 | typescript | ok |
| Secret Rotation Validator | typescript-bun | sonnet5-1m-medium | 11.2min | 65 | 1 | $2.19 | 3.5 | typescript | ok |
| Semantic Version Bumper | default | sonnet5-1m-high | 12.5min | 80 | 2 | $3.54 | 4.5 | python | ok |
| Semantic Version Bumper | default | sonnet5-1m-medium | 5.1min | 33 | 2 | $1.28 | 4.0 | python | ok |
| Semantic Version Bumper | powershell | sonnet5-1m-low | 7.5min | 32 | 2 | $1.02 | 3.5 | powershell | ok |
| PR Label Assigner | bash | sonnet5-1m-high | 30.0min | 0 | 2 | $0.00 | 4.5 | bash | timeout |
| PR Label Assigner | typescript-bun | sonnet5-1m-medium | 11.0min | 63 | 2 | $2.28 | 4.0 | typescript | ok |
| Test Results Aggregator | typescript-bun | sonnet5-1m-high | 25.3min | 143 | 2 | $7.29 | 4.5 | typescript | ok |
| Environment Matrix Generator | default | sonnet5-1m-high | 16.4min | 94 | 2 | $5.01 | 4.5 | python | ok |
| Environment Matrix Generator | typescript-bun | sonnet5-1m-low | 5.8min | 36 | 2 | $1.26 | 1.5 | typescript | ok |
| Artifact Cleanup Script | powershell | sonnet5-1m-medium | 16.6min | 64 | 2 | $3.28 | 2.0 | powershell | ok |
| Artifact Cleanup Script | typescript-bun | sonnet5-1m-high | 23.5min | 150 | 2 | $6.00 | 2.5 | typescript | ok |
| Secret Rotation Validator | powershell | sonnet5-1m-high | 22.6min | 102 | 2 | $4.46 | 4.5 | powershell | ok |
| Semantic Version Bumper | bash | sonnet5-1m-high | 11.8min | 57 | 3 | $2.84 | 1.5 | bash | ok |
| Dependency License Checker | bash | sonnet5-1m-high | 17.4min | 105 | 3 | $5.57 | 4.0 | bash | ok |
| Dependency License Checker | powershell | sonnet5-1m-medium | 13.5min | 52 | 3 | $2.14 | 4.0 | powershell | ok |
| Dependency License Checker | typescript-bun | sonnet5-1m-low | 10.4min | 63 | 3 | $1.73 | 2.0 | typescript | ok |
| Artifact Cleanup Script | default | sonnet5-1m-medium | 11.5min | 86 | 3 | $3.10 | 4.5 | python | ok |
| Artifact Cleanup Script | powershell | sonnet5-1m-high | 23.4min | 98 | 3 | $5.42 | 4.5 | powershell | ok |
| Secret Rotation Validator | default | sonnet5-1m-medium | 5.5min | 38 | 3 | $1.44 | 2.5 | python | ok |
| Semantic Version Bumper | bash | sonnet5-1m-medium | 8.7min | 85 | 4 | $2.67 | 4.0 | bash | ok |
| PR Label Assigner | powershell | sonnet5-1m-high | 30.0min | 0 | 4 | $0.00 | 3.5 | powershell | timeout |
| Dependency License Checker | bash | sonnet5-1m-medium | 11.0min | 74 | 4 | $2.43 | 3.5 | bash | ok |
| Dependency License Checker | bash | sonnet5-1m-low | 12.3min | 49 | 4 | $1.36 | 2.5 | bash | ok |
| Test Results Aggregator | bash | sonnet5-1m-low | 5.8min | 2 | 4 | $0.15 | 2.0 | bash | ok |
| Test Results Aggregator | powershell | sonnet5-1m-high | 26.0min | 87 | 4 | $4.82 | 3.5 | powershell | ok |
| Environment Matrix Generator | typescript-bun | sonnet5-1m-medium | 17.0min | 87 | 4 | $3.12 | 2.0 | typescript | ok |
| Artifact Cleanup Script | bash | sonnet5-1m-high | 11.8min | 59 | 4 | $3.37 | 4.0 | bash | ok |
| Secret Rotation Validator | bash | sonnet5-1m-medium | 9.3min | 0 | 4 | $0.00 | 4.5 | bash | cli_error |
| PR Label Assigner | bash | sonnet5-1m-medium | 14.3min | 101 | 5 | $3.99 | 4.5 | bash | ok |
| Secret Rotation Validator | typescript-bun | sonnet5-1m-low | 6.9min | 3 | 5 | $0.16 | 1.5 | typescript | ok |
| Test Results Aggregator | bash | sonnet5-1m-high | 17.1min | 108 | 6 | $5.57 | 4.5 | bash | ok |
| Artifact Cleanup Script | bash | sonnet5-1m-low | 13.7min | 2 | 6 | $0.14 | 4.0 | bash | ok |
| Artifact Cleanup Script | bash | sonnet5-1m-medium | 16.9min | 80 | 7 | $3.35 | 3.5 | bash | ok |
| Semantic Version Bumper | typescript-bun | sonnet5-1m-high | 18.6min | 127 | 8 | $6.16 | 4.5 | typescript | ok |
| Environment Matrix Generator | bash | sonnet5-1m-high | 26.2min | 150 | 9 | $8.03 | 4.0 | bash | ok |
| Dependency License Checker | typescript-bun | sonnet5-1m-high | 18.4min | 137 | 11 | $5.28 | 4.5 | typescript | ok |

</details>

<details>
<summary>Sorted by turns (fewest first)</summary>

| Task | Language | Model | Duration | Turns | Errors | Cost | Tests Quality | Chosen | Status |
|------|----------|-------|----------|-------|--------|------|-----------|--------|--------|
| Semantic Version Bumper | powershell | sonnet5-1m-high | 30.0min | 0 | 1 | $0.00 | 4.0 | powershell | timeout |
| PR Label Assigner | bash | sonnet5-1m-high | 30.0min | 0 | 2 | $0.00 | 4.5 | bash | timeout |
| PR Label Assigner | powershell | sonnet5-1m-high | 30.0min | 0 | 1 | $0.00 | 4.5 | powershell | timeout |
| PR Label Assigner | powershell | sonnet5-1m-high | 30.0min | 0 | 4 | $0.00 | 3.5 | powershell | timeout |
| Test Results Aggregator | powershell | sonnet5-1m-high | 30.0min | 0 | 0 | $0.00 | 4.5 | powershell | timeout |
| Secret Rotation Validator | bash | sonnet5-1m-medium | 9.3min | 0 | 4 | $0.00 | 4.5 | bash | cli_error |
| Secret Rotation Validator | powershell | sonnet5-1m-high | 30.0min | 0 | 0 | $0.00 | 4.0 | powershell | timeout |
| Test Results Aggregator | bash | sonnet5-1m-low | 5.8min | 2 | 4 | $0.15 | 2.0 | bash | ok |
| Artifact Cleanup Script | bash | sonnet5-1m-low | 13.7min | 2 | 6 | $0.14 | 4.0 | bash | ok |
| Environment Matrix Generator | powershell | sonnet5-1m-low | 7.4min | 3 | 0 | $1.10 | 2.5 | powershell | ok |
| Secret Rotation Validator | typescript-bun | sonnet5-1m-low | 6.9min | 3 | 5 | $0.16 | 1.5 | typescript | ok |
| PR Label Assigner | default | sonnet5-1m-low | 3.7min | 24 | 0 | $0.75 | 4.5 | python | ok |
| Semantic Version Bumper | default | sonnet5-1m-low | 4.1min | 26 | 0 | $1.02 | 1.5 | python | ok |
| Environment Matrix Generator | default | sonnet5-1m-low | 10.7min | 26 | 1 | $0.84 | 2.0 | python | ok |
| Semantic Version Bumper | bash | sonnet5-1m-low | 12.5min | 27 | 0 | $0.96 | 4.0 | bash | ok |
| PR Label Assigner | powershell | sonnet5-1m-medium | 8.7min | 27 | 1 | $1.19 | 2.0 | powershell | ok |
| PR Label Assigner | bash | sonnet5-1m-low | 3.4min | 28 | 1 | $0.76 | 2.0 | bash | ok |
| Semantic Version Bumper | powershell | sonnet5-1m-low | 7.5min | 32 | 2 | $1.02 | 3.5 | powershell | ok |
| Artifact Cleanup Script | default | sonnet5-1m-low | 4.5min | 32 | 0 | $1.07 | 4.0 | python | ok |
| Secret Rotation Validator | bash | sonnet5-1m-low | 4.3min | 32 | 1 | $0.99 | 3.5 | bash | ok |
| Semantic Version Bumper | default | sonnet5-1m-medium | 5.1min | 33 | 2 | $1.28 | 4.0 | python | ok |
| PR Label Assigner | typescript-bun | sonnet5-1m-low | 4.6min | 33 | 0 | $0.91 | 2.0 | typescript | ok |
| Test Results Aggregator | powershell | sonnet5-1m-low | 7.6min | 33 | 0 | $0.94 | 3.5 | powershell | ok |
| PR Label Assigner | powershell | sonnet5-1m-low | 6.0min | 34 | 1 | $0.96 | 3.5 | powershell | ok |
| Dependency License Checker | default | sonnet5-1m-low | 4.9min | 34 | 0 | $1.13 | 4.5 | python | ok |
| Artifact Cleanup Script | powershell | sonnet5-1m-low | 7.5min | 35 | 0 | $1.05 | 2.0 | powershell | ok |
| Environment Matrix Generator | typescript-bun | sonnet5-1m-low | 5.8min | 36 | 2 | $1.26 | 1.5 | typescript | ok |
| Artifact Cleanup Script | powershell | sonnet5-1m-medium | 11.3min | 38 | 0 | $1.90 | 4.5 | powershell | ok |
| Secret Rotation Validator | default | sonnet5-1m-medium | 5.5min | 38 | 3 | $1.44 | 2.5 | python | ok |
| Dependency License Checker | default | sonnet5-1m-high | 9.9min | 39 | 1 | $1.99 | 3.0 | python | ok |
| Dependency License Checker | powershell | sonnet5-1m-low | 7.6min | 39 | 0 | $1.17 | 2.0 | powershell | ok |
| Semantic Version Bumper | powershell | sonnet5-1m-medium | 10.2min | 40 | 0 | $1.42 | 4.5 | powershell | ok |
| PR Label Assigner | powershell | sonnet5-1m-medium | 9.6min | 40 | 0 | $1.58 | 4.5 | powershell | ok |
| Environment Matrix Generator | bash | sonnet5-1m-low | 5.3min | 42 | 1 | $1.21 | 2.0 | bash | ok |
| Semantic Version Bumper | powershell | sonnet5-1m-low | 9.6min | 43 | 0 | $1.43 | 2.0 | powershell | ok |
| Secret Rotation Validator | powershell | sonnet5-1m-medium | 10.2min | 43 | 0 | $1.49 | 3.5 | powershell | ok |
| Test Results Aggregator | bash | sonnet5-1m-medium | 8.5min | 46 | 0 | $1.80 | 3.5 | bash | ok |
| Artifact Cleanup Script | typescript-bun | sonnet5-1m-low | 9.3min | 46 | 0 | $1.30 | 1.5 | typescript | ok |
| Secret Rotation Validator | default | sonnet5-1m-low | 9.0min | 46 | 1 | $1.50 | 2.5 | python | ok |
| Semantic Version Bumper | typescript-bun | sonnet5-1m-low | 8.0min | 47 | 0 | $1.84 | 4.5 | typescript | ok |
| PR Label Assigner | powershell | sonnet5-1m-low | 11.3min | 48 | 1 | $1.50 | 2.0 | powershell | ok |
| Dependency License Checker | bash | sonnet5-1m-low | 12.3min | 49 | 4 | $1.36 | 2.5 | bash | ok |
| Dependency License Checker | powershell | sonnet5-1m-medium | 13.5min | 52 | 3 | $2.14 | 4.0 | powershell | ok |
| Test Results Aggregator | default | sonnet5-1m-low | 7.3min | 54 | 1 | $1.62 | 2.0 | python | ok |
| Secret Rotation Validator | powershell | sonnet5-1m-low | 15.4min | 54 | 1 | $1.98 | 4.0 | powershell | ok |
| Environment Matrix Generator | powershell | sonnet5-1m-medium | 15.8min | 55 | 0 | $2.82 | 4.0 | powershell | ok |
| Semantic Version Bumper | bash | sonnet5-1m-high | 11.8min | 57 | 3 | $2.84 | 1.5 | bash | ok |
| Dependency License Checker | powershell | sonnet5-1m-high | 14.6min | 58 | 1 | $2.80 | 4.5 | powershell | ok |
| Test Results Aggregator | powershell | sonnet5-1m-medium | 12.6min | 58 | 0 | $2.54 | 3.5 | powershell | ok |
| Test Results Aggregator | default | sonnet5-1m-high | 12.7min | 59 | 0 | $3.47 | 3.5 | python | ok |
| Environment Matrix Generator | default | sonnet5-1m-medium | 6.9min | 59 | 0 | $1.72 | 4.0 | python | ok |
| Artifact Cleanup Script | bash | sonnet5-1m-high | 11.8min | 59 | 4 | $3.37 | 4.0 | bash | ok |
| Semantic Version Bumper | powershell | sonnet5-1m-medium | 13.0min | 60 | 0 | $1.99 | 4.5 | powershell | ok |
| Test Results Aggregator | default | sonnet5-1m-medium | 10.1min | 61 | 0 | $2.37 | 2.0 | python | ok |
| PR Label Assigner | typescript-bun | sonnet5-1m-medium | 11.0min | 63 | 2 | $2.28 | 4.0 | typescript | ok |
| Dependency License Checker | typescript-bun | sonnet5-1m-low | 10.4min | 63 | 3 | $1.73 | 2.0 | typescript | ok |
| PR Label Assigner | default | sonnet5-1m-medium | 9.5min | 64 | 1 | $2.04 | 2.0 | powershell | ok |
| Artifact Cleanup Script | powershell | sonnet5-1m-medium | 16.6min | 64 | 2 | $3.28 | 2.0 | powershell | ok |
| Secret Rotation Validator | typescript-bun | sonnet5-1m-medium | 11.2min | 65 | 1 | $2.19 | 3.5 | typescript | ok |
| Test Results Aggregator | typescript-bun | sonnet5-1m-low | 12.0min | 66 | 1 | $2.08 | 1.5 | typescript | ok |
| Environment Matrix Generator | bash | sonnet5-1m-medium | 14.2min | 67 | 0 | $2.90 | 4.0 | bash | ok |
| Semantic Version Bumper | typescript-bun | sonnet5-1m-medium | 11.7min | 69 | 1 | $2.15 | 3.5 | typescript | ok |
| Test Results Aggregator | powershell | sonnet5-1m-medium | 13.3min | 69 | 0 | $2.19 | 3.5 | powershell | ok |
| Secret Rotation Validator | default | sonnet5-1m-high | 12.7min | 69 | 0 | $3.58 | 4.0 | python | ok |
| Dependency License Checker | powershell | sonnet5-1m-medium | 18.8min | 70 | 0 | $4.02 | 4.5 | powershell | ok |
| Dependency License Checker | default | sonnet5-1m-medium | 8.9min | 73 | 0 | $2.48 | 2.5 | python | ok |
| Dependency License Checker | bash | sonnet5-1m-medium | 11.0min | 74 | 4 | $2.43 | 3.5 | bash | ok |
| Environment Matrix Generator | typescript-bun | sonnet5-1m-high | 19.7min | 75 | 1 | $4.76 | 4.5 | typescript | ok |
| Artifact Cleanup Script | default | sonnet5-1m-high | 18.0min | 76 | 1 | $3.61 | 1.0 | powershell | ok |
| Artifact Cleanup Script | powershell | sonnet5-1m-high | 21.2min | 79 | 0 | $4.33 | 4.5 | powershell | ok |
| Semantic Version Bumper | default | sonnet5-1m-high | 12.5min | 80 | 2 | $3.54 | 4.5 | python | ok |
| PR Label Assigner | default | sonnet5-1m-high | 11.6min | 80 | 0 | $3.61 | 4.5 | python | ok |
| Dependency License Checker | powershell | sonnet5-1m-high | 16.8min | 80 | 0 | $3.03 | 4.5 | powershell | ok |
| Artifact Cleanup Script | bash | sonnet5-1m-medium | 16.9min | 80 | 7 | $3.35 | 3.5 | bash | ok |
| Environment Matrix Generator | powershell | sonnet5-1m-high | 25.4min | 82 | 0 | $5.48 | 4.5 | powershell | ok |
| Secret Rotation Validator | powershell | sonnet5-1m-medium | 15.4min | 83 | 0 | $2.81 | 2.0 | powershell | ok |
| Semantic Version Bumper | bash | sonnet5-1m-medium | 8.7min | 85 | 4 | $2.67 | 4.0 | bash | ok |
| Artifact Cleanup Script | default | sonnet5-1m-medium | 11.5min | 86 | 3 | $3.10 | 4.5 | python | ok |
| Test Results Aggregator | powershell | sonnet5-1m-high | 26.0min | 87 | 4 | $4.82 | 3.5 | powershell | ok |
| Environment Matrix Generator | typescript-bun | sonnet5-1m-medium | 17.0min | 87 | 4 | $3.12 | 2.0 | typescript | ok |
| Dependency License Checker | typescript-bun | sonnet5-1m-medium | 13.6min | 93 | 1 | $2.82 | 4.5 | typescript | ok |
| Environment Matrix Generator | default | sonnet5-1m-high | 16.4min | 94 | 2 | $5.01 | 4.5 | python | ok |
| Artifact Cleanup Script | powershell | sonnet5-1m-high | 23.4min | 98 | 3 | $5.42 | 4.5 | powershell | ok |
| Environment Matrix Generator | powershell | sonnet5-1m-medium | 16.5min | 99 | 1 | $3.46 | 4.5 | powershell | ok |
| PR Label Assigner | bash | sonnet5-1m-medium | 14.3min | 101 | 5 | $3.99 | 4.5 | bash | ok |
| Test Results Aggregator | typescript-bun | sonnet5-1m-medium | 12.8min | 101 | 1 | $2.92 | 2.5 | typescript | ok |
| Secret Rotation Validator | powershell | sonnet5-1m-high | 22.6min | 102 | 2 | $4.46 | 4.5 | powershell | ok |
| Environment Matrix Generator | powershell | sonnet5-1m-high | 29.5min | 103 | 0 | $6.22 | 4.5 | powershell | ok |
| Dependency License Checker | bash | sonnet5-1m-high | 17.4min | 105 | 3 | $5.57 | 4.0 | bash | ok |
| PR Label Assigner | typescript-bun | sonnet5-1m-high | 18.3min | 106 | 0 | $4.13 | 4.5 | typescript | ok |
| Test Results Aggregator | bash | sonnet5-1m-high | 17.1min | 108 | 6 | $5.57 | 4.5 | bash | ok |
| Artifact Cleanup Script | typescript-bun | sonnet5-1m-medium | 13.7min | 109 | 0 | $3.28 | 2.0 | typescript | ok |
| Semantic Version Bumper | powershell | sonnet5-1m-high | 26.7min | 111 | 0 | $5.41 | 4.0 | powershell | ok |
| Secret Rotation Validator | bash | sonnet5-1m-high | 20.7min | 119 | 1 | $6.24 | 4.0 | bash | ok |
| Semantic Version Bumper | typescript-bun | sonnet5-1m-high | 18.6min | 127 | 8 | $6.16 | 4.5 | typescript | ok |
| Secret Rotation Validator | typescript-bun | sonnet5-1m-high | 25.3min | 136 | 1 | $6.32 | 5.0 | typescript | ok |
| Dependency License Checker | typescript-bun | sonnet5-1m-high | 18.4min | 137 | 11 | $5.28 | 4.5 | typescript | ok |
| Test Results Aggregator | typescript-bun | sonnet5-1m-high | 25.3min | 143 | 2 | $7.29 | 4.5 | typescript | ok |
| Environment Matrix Generator | bash | sonnet5-1m-high | 26.2min | 150 | 9 | $8.03 | 4.0 | bash | ok |
| Artifact Cleanup Script | typescript-bun | sonnet5-1m-high | 23.5min | 150 | 2 | $6.00 | 2.5 | typescript | ok |

</details>

<details>
<summary>Sorted by LLM-as-judge score (best first)</summary>

| Task | Language | Model | Duration | Turns | Errors | Cost | Tests Quality | Chosen | Status |
|------|----------|-------|----------|-------|--------|------|-----------|--------|--------|
| Secret Rotation Validator | typescript-bun | sonnet5-1m-high | 25.3min | 136 | 1 | $6.32 | 5.0 | typescript | ok |
| Semantic Version Bumper | default | sonnet5-1m-high | 12.5min | 80 | 2 | $3.54 | 4.5 | python | ok |
| Semantic Version Bumper | powershell | sonnet5-1m-medium | 13.0min | 60 | 0 | $1.99 | 4.5 | powershell | ok |
| Semantic Version Bumper | powershell | sonnet5-1m-medium | 10.2min | 40 | 0 | $1.42 | 4.5 | powershell | ok |
| Semantic Version Bumper | typescript-bun | sonnet5-1m-high | 18.6min | 127 | 8 | $6.16 | 4.5 | typescript | ok |
| Semantic Version Bumper | typescript-bun | sonnet5-1m-low | 8.0min | 47 | 0 | $1.84 | 4.5 | typescript | ok |
| PR Label Assigner | bash | sonnet5-1m-high | 30.0min | 0 | 2 | $0.00 | 4.5 | bash | timeout |
| PR Label Assigner | bash | sonnet5-1m-medium | 14.3min | 101 | 5 | $3.99 | 4.5 | bash | ok |
| PR Label Assigner | default | sonnet5-1m-high | 11.6min | 80 | 0 | $3.61 | 4.5 | python | ok |
| PR Label Assigner | default | sonnet5-1m-low | 3.7min | 24 | 0 | $0.75 | 4.5 | python | ok |
| PR Label Assigner | powershell | sonnet5-1m-high | 30.0min | 0 | 1 | $0.00 | 4.5 | powershell | timeout |
| PR Label Assigner | powershell | sonnet5-1m-medium | 9.6min | 40 | 0 | $1.58 | 4.5 | powershell | ok |
| PR Label Assigner | typescript-bun | sonnet5-1m-high | 18.3min | 106 | 0 | $4.13 | 4.5 | typescript | ok |
| Dependency License Checker | default | sonnet5-1m-low | 4.9min | 34 | 0 | $1.13 | 4.5 | python | ok |
| Dependency License Checker | powershell | sonnet5-1m-high | 16.8min | 80 | 0 | $3.03 | 4.5 | powershell | ok |
| Dependency License Checker | powershell | sonnet5-1m-high | 14.6min | 58 | 1 | $2.80 | 4.5 | powershell | ok |
| Dependency License Checker | powershell | sonnet5-1m-medium | 18.8min | 70 | 0 | $4.02 | 4.5 | powershell | ok |
| Dependency License Checker | typescript-bun | sonnet5-1m-high | 18.4min | 137 | 11 | $5.28 | 4.5 | typescript | ok |
| Dependency License Checker | typescript-bun | sonnet5-1m-medium | 13.6min | 93 | 1 | $2.82 | 4.5 | typescript | ok |
| Test Results Aggregator | bash | sonnet5-1m-high | 17.1min | 108 | 6 | $5.57 | 4.5 | bash | ok |
| Test Results Aggregator | powershell | sonnet5-1m-high | 30.0min | 0 | 0 | $0.00 | 4.5 | powershell | timeout |
| Test Results Aggregator | typescript-bun | sonnet5-1m-high | 25.3min | 143 | 2 | $7.29 | 4.5 | typescript | ok |
| Environment Matrix Generator | default | sonnet5-1m-high | 16.4min | 94 | 2 | $5.01 | 4.5 | python | ok |
| Environment Matrix Generator | powershell | sonnet5-1m-high | 29.5min | 103 | 0 | $6.22 | 4.5 | powershell | ok |
| Environment Matrix Generator | powershell | sonnet5-1m-medium | 16.5min | 99 | 1 | $3.46 | 4.5 | powershell | ok |
| Environment Matrix Generator | powershell | sonnet5-1m-high | 25.4min | 82 | 0 | $5.48 | 4.5 | powershell | ok |
| Environment Matrix Generator | typescript-bun | sonnet5-1m-high | 19.7min | 75 | 1 | $4.76 | 4.5 | typescript | ok |
| Artifact Cleanup Script | default | sonnet5-1m-medium | 11.5min | 86 | 3 | $3.10 | 4.5 | python | ok |
| Artifact Cleanup Script | powershell | sonnet5-1m-high | 23.4min | 98 | 3 | $5.42 | 4.5 | powershell | ok |
| Artifact Cleanup Script | powershell | sonnet5-1m-medium | 11.3min | 38 | 0 | $1.90 | 4.5 | powershell | ok |
| Artifact Cleanup Script | powershell | sonnet5-1m-high | 21.2min | 79 | 0 | $4.33 | 4.5 | powershell | ok |
| Secret Rotation Validator | bash | sonnet5-1m-medium | 9.3min | 0 | 4 | $0.00 | 4.5 | bash | cli_error |
| Secret Rotation Validator | powershell | sonnet5-1m-high | 22.6min | 102 | 2 | $4.46 | 4.5 | powershell | ok |
| Semantic Version Bumper | bash | sonnet5-1m-medium | 8.7min | 85 | 4 | $2.67 | 4.0 | bash | ok |
| Semantic Version Bumper | bash | sonnet5-1m-low | 12.5min | 27 | 0 | $0.96 | 4.0 | bash | ok |
| Semantic Version Bumper | default | sonnet5-1m-medium | 5.1min | 33 | 2 | $1.28 | 4.0 | python | ok |
| Semantic Version Bumper | powershell | sonnet5-1m-high | 30.0min | 0 | 1 | $0.00 | 4.0 | powershell | timeout |
| Semantic Version Bumper | powershell | sonnet5-1m-high | 26.7min | 111 | 0 | $5.41 | 4.0 | powershell | ok |
| PR Label Assigner | typescript-bun | sonnet5-1m-medium | 11.0min | 63 | 2 | $2.28 | 4.0 | typescript | ok |
| Dependency License Checker | bash | sonnet5-1m-high | 17.4min | 105 | 3 | $5.57 | 4.0 | bash | ok |
| Dependency License Checker | powershell | sonnet5-1m-medium | 13.5min | 52 | 3 | $2.14 | 4.0 | powershell | ok |
| Environment Matrix Generator | bash | sonnet5-1m-high | 26.2min | 150 | 9 | $8.03 | 4.0 | bash | ok |
| Environment Matrix Generator | bash | sonnet5-1m-medium | 14.2min | 67 | 0 | $2.90 | 4.0 | bash | ok |
| Environment Matrix Generator | default | sonnet5-1m-medium | 6.9min | 59 | 0 | $1.72 | 4.0 | python | ok |
| Environment Matrix Generator | powershell | sonnet5-1m-medium | 15.8min | 55 | 0 | $2.82 | 4.0 | powershell | ok |
| Artifact Cleanup Script | bash | sonnet5-1m-high | 11.8min | 59 | 4 | $3.37 | 4.0 | bash | ok |
| Artifact Cleanup Script | bash | sonnet5-1m-low | 13.7min | 2 | 6 | $0.14 | 4.0 | bash | ok |
| Artifact Cleanup Script | default | sonnet5-1m-low | 4.5min | 32 | 0 | $1.07 | 4.0 | python | ok |
| Secret Rotation Validator | bash | sonnet5-1m-high | 20.7min | 119 | 1 | $6.24 | 4.0 | bash | ok |
| Secret Rotation Validator | default | sonnet5-1m-high | 12.7min | 69 | 0 | $3.58 | 4.0 | python | ok |
| Secret Rotation Validator | powershell | sonnet5-1m-high | 30.0min | 0 | 0 | $0.00 | 4.0 | powershell | timeout |
| Secret Rotation Validator | powershell | sonnet5-1m-low | 15.4min | 54 | 1 | $1.98 | 4.0 | powershell | ok |
| Semantic Version Bumper | powershell | sonnet5-1m-low | 7.5min | 32 | 2 | $1.02 | 3.5 | powershell | ok |
| Semantic Version Bumper | typescript-bun | sonnet5-1m-medium | 11.7min | 69 | 1 | $2.15 | 3.5 | typescript | ok |
| PR Label Assigner | powershell | sonnet5-1m-low | 6.0min | 34 | 1 | $0.96 | 3.5 | powershell | ok |
| PR Label Assigner | powershell | sonnet5-1m-high | 30.0min | 0 | 4 | $0.00 | 3.5 | powershell | timeout |
| Dependency License Checker | bash | sonnet5-1m-medium | 11.0min | 74 | 4 | $2.43 | 3.5 | bash | ok |
| Test Results Aggregator | bash | sonnet5-1m-medium | 8.5min | 46 | 0 | $1.80 | 3.5 | bash | ok |
| Test Results Aggregator | default | sonnet5-1m-high | 12.7min | 59 | 0 | $3.47 | 3.5 | python | ok |
| Test Results Aggregator | powershell | sonnet5-1m-medium | 12.6min | 58 | 0 | $2.54 | 3.5 | powershell | ok |
| Test Results Aggregator | powershell | sonnet5-1m-low | 7.6min | 33 | 0 | $0.94 | 3.5 | powershell | ok |
| Test Results Aggregator | powershell | sonnet5-1m-high | 26.0min | 87 | 4 | $4.82 | 3.5 | powershell | ok |
| Test Results Aggregator | powershell | sonnet5-1m-medium | 13.3min | 69 | 0 | $2.19 | 3.5 | powershell | ok |
| Artifact Cleanup Script | bash | sonnet5-1m-medium | 16.9min | 80 | 7 | $3.35 | 3.5 | bash | ok |
| Secret Rotation Validator | bash | sonnet5-1m-low | 4.3min | 32 | 1 | $0.99 | 3.5 | bash | ok |
| Secret Rotation Validator | powershell | sonnet5-1m-medium | 10.2min | 43 | 0 | $1.49 | 3.5 | powershell | ok |
| Secret Rotation Validator | typescript-bun | sonnet5-1m-medium | 11.2min | 65 | 1 | $2.19 | 3.5 | typescript | ok |
| Dependency License Checker | default | sonnet5-1m-high | 9.9min | 39 | 1 | $1.99 | 3.0 | python | ok |
| Dependency License Checker | bash | sonnet5-1m-low | 12.3min | 49 | 4 | $1.36 | 2.5 | bash | ok |
| Dependency License Checker | default | sonnet5-1m-medium | 8.9min | 73 | 0 | $2.48 | 2.5 | python | ok |
| Test Results Aggregator | typescript-bun | sonnet5-1m-medium | 12.8min | 101 | 1 | $2.92 | 2.5 | typescript | ok |
| Environment Matrix Generator | powershell | sonnet5-1m-low | 7.4min | 3 | 0 | $1.10 | 2.5 | powershell | ok |
| Artifact Cleanup Script | typescript-bun | sonnet5-1m-high | 23.5min | 150 | 2 | $6.00 | 2.5 | typescript | ok |
| Secret Rotation Validator | default | sonnet5-1m-medium | 5.5min | 38 | 3 | $1.44 | 2.5 | python | ok |
| Secret Rotation Validator | default | sonnet5-1m-low | 9.0min | 46 | 1 | $1.50 | 2.5 | python | ok |
| Semantic Version Bumper | powershell | sonnet5-1m-low | 9.6min | 43 | 0 | $1.43 | 2.0 | powershell | ok |
| PR Label Assigner | bash | sonnet5-1m-low | 3.4min | 28 | 1 | $0.76 | 2.0 | bash | ok |
| PR Label Assigner | default | sonnet5-1m-medium | 9.5min | 64 | 1 | $2.04 | 2.0 | powershell | ok |
| PR Label Assigner | powershell | sonnet5-1m-medium | 8.7min | 27 | 1 | $1.19 | 2.0 | powershell | ok |
| PR Label Assigner | powershell | sonnet5-1m-low | 11.3min | 48 | 1 | $1.50 | 2.0 | powershell | ok |
| PR Label Assigner | typescript-bun | sonnet5-1m-low | 4.6min | 33 | 0 | $0.91 | 2.0 | typescript | ok |
| Dependency License Checker | powershell | sonnet5-1m-low | 7.6min | 39 | 0 | $1.17 | 2.0 | powershell | ok |
| Dependency License Checker | typescript-bun | sonnet5-1m-low | 10.4min | 63 | 3 | $1.73 | 2.0 | typescript | ok |
| Test Results Aggregator | bash | sonnet5-1m-low | 5.8min | 2 | 4 | $0.15 | 2.0 | bash | ok |
| Test Results Aggregator | default | sonnet5-1m-medium | 10.1min | 61 | 0 | $2.37 | 2.0 | python | ok |
| Test Results Aggregator | default | sonnet5-1m-low | 7.3min | 54 | 1 | $1.62 | 2.0 | python | ok |
| Environment Matrix Generator | bash | sonnet5-1m-low | 5.3min | 42 | 1 | $1.21 | 2.0 | bash | ok |
| Environment Matrix Generator | default | sonnet5-1m-low | 10.7min | 26 | 1 | $0.84 | 2.0 | python | ok |
| Environment Matrix Generator | typescript-bun | sonnet5-1m-medium | 17.0min | 87 | 4 | $3.12 | 2.0 | typescript | ok |
| Artifact Cleanup Script | powershell | sonnet5-1m-low | 7.5min | 35 | 0 | $1.05 | 2.0 | powershell | ok |
| Artifact Cleanup Script | powershell | sonnet5-1m-medium | 16.6min | 64 | 2 | $3.28 | 2.0 | powershell | ok |
| Artifact Cleanup Script | typescript-bun | sonnet5-1m-medium | 13.7min | 109 | 0 | $3.28 | 2.0 | typescript | ok |
| Secret Rotation Validator | powershell | sonnet5-1m-medium | 15.4min | 83 | 0 | $2.81 | 2.0 | powershell | ok |
| Semantic Version Bumper | bash | sonnet5-1m-high | 11.8min | 57 | 3 | $2.84 | 1.5 | bash | ok |
| Semantic Version Bumper | default | sonnet5-1m-low | 4.1min | 26 | 0 | $1.02 | 1.5 | python | ok |
| Test Results Aggregator | typescript-bun | sonnet5-1m-low | 12.0min | 66 | 1 | $2.08 | 1.5 | typescript | ok |
| Environment Matrix Generator | typescript-bun | sonnet5-1m-low | 5.8min | 36 | 2 | $1.26 | 1.5 | typescript | ok |
| Artifact Cleanup Script | typescript-bun | sonnet5-1m-low | 9.3min | 46 | 0 | $1.30 | 1.5 | typescript | ok |
| Secret Rotation Validator | typescript-bun | sonnet5-1m-low | 6.9min | 3 | 5 | $0.16 | 1.5 | typescript | ok |
| Artifact Cleanup Script | default | sonnet5-1m-high | 18.0min | 76 | 1 | $3.61 | 1.0 | powershell | ok |

</details>

## Notes

### Tiers

- **Duration bands:** **A+** ≤1.13×, **A** ≤1.27×, **A-** ≤1.44×, **B+** ≤1.62×, **B** ≤1.83×, **B-** ≤2.06×, **C+** ≤2.32×, **C** ≤2.62×, **C-** ≤2.96×, **D+** ≤3.34×, **D** ≤3.76×, **D-** ≤4.25×, **F** >4.25×
- **Cost bands:** **A+** ≤1.21×, **A** ≤1.45×, **A-** ≤1.75×, **B+** ≤2.12×, **B** ≤2.55×, **B-** ≤3.08×, **C+** ≤3.71×, **C** ≤4.48×, **C-** ≤5.40×, **D+** ≤6.52×, **D** ≤7.86×, **D-** ≤9.48×, **F** >9.48×

*Tests/Workflow Craft bands are absolute Overall score bands:* **A+** ≥4.7, **A** ≥4.4, **A-** ≥4.1, **B+** ≥3.8, **B** ≥3.5, **B-** ≥3.2, **C+** ≥2.9, **C** ≥2.6, **C-** ≥2.3, **D+** ≥2.0, **D** ≥1.7, **D-** ≥1.4, **F** <1.4, `—` = no data.*

### CLI Version Legend

| Variant label | CLI version | Tasks | Languages |
|---------------|-------------|-------|-----------|
| sonnet5-1m-high | 2.1.197 | All | All |
| sonnet5-1m-low | 2.1.197 | 11-semantic-version-bumper, 12-pr-label-assigner, 13-dependency-license-checker, 15-test-results-aggregator, 16-environment-matrix-generator | All |
| sonnet5-1m-low | 2.1.198 | 16-environment-matrix-generator, 17-artifact-cleanup-script, 18-secret-rotation-validator | All |
| sonnet5-1m-medium | 2.1.197 | All | All |

### Judge Consistency Summary

**🟢 The panel is doing its job:** Both judges agree on model ordering for Workflow Craft (ρ = +1.00), and the sole Tests Quality reversal is a hairline flip between sonnet5 and sonnet5-1m (Haiku scores them 3.02 vs 2.86 — well inside calibration noise). No reversal favours either judge's own model family, and the language×model correlations of +0.31 to +0.40 reflect calibration gaps plus one real disagreement about bash.

- 👀 **Where to look closer:** Bash on Tests Quality — Haiku ranks it worst (2.81 mean), Gemini ranks it second-best (4.24). Spot-check the widest single-run gap (one judge scoring 1, the other 5, a 4-point gap on a 1–5 scale) at 15-test-results-aggregator / typescript-bun / sonnet5-1m-medium on Workflow Craft, plus the three 3-point bash gaps at 13-dependency-license-checker, 15-test-results-aggregator, and 17-artifact-cleanup-script — all bash / sonnet5-1m-medium, all Haiku 2 vs Gemini 5.
- 🤓 **Surprise finding:** 18-secret-rotation-validator / default / sonnet5-low is the only row where Gemini drops to 1 while Haiku holds at 4 — the opposite of Gemini's usual ceiling-hugging pattern.
- ℹ️ **Recommended next step:** Hand-review those four runs to decide whether Haiku is under-scoring bash workflows or Gemini is over-scoring them, then re-check rankings with the resolved calls.

#### Provenance

- **Model:** `claude-opus-4-7[1m]` at effort `xhigh` via the Claude CLI.
- **Inputs:** the [`judge-consistency-data.md`](judge-consistency-data.md) tables plus benchmark context (rubrics, task list, experiment setup).
- **Script:** [`conclusions_report.py`](../../conclusions_report.py) — regenerate with `python3 generate_results.py <run_dir>`.
- **Instruction:** [`JUDGE_CONSISTENCY_SUMMARY_SYSTEM_PROMPT`](../../judge_consistency_report.py) in that script.
- **Usage:** 5 input + 3872 output tokens, $0.2864.

*Full breakdown with per-model / per-language / per-language×model ranking tables and disagreement hotspots in [judge-consistency-data.md](judge-consistency-data.md).*

---
*Generated by generate_results.py — benchmark instructions v4*