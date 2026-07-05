# Benchmark Results: Language Comparison

**Last updated:** 2026-07-05 01:01:30 AM ET — 140/140 runs completed, 0 remaining; total cost $577.71; total agent time 2233.1 min.
**Claude Code versions used:** [v2.1.193](claude-code-2.1.193.md) (23 runs), [v2.1.195](claude-code-2.1.195.md) (117 runs). Each link goes to a per-version snapshot of the system prompt, default-tool descriptions, and the chronological Anthropic changelog up to that version. Regenerate with `python3 version_docs.py`.

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
| default | opus48-1m-medium | A+ (7.4min) | A+ ($1.87) | A- (4.1) | A- (4.3) |
| powershell | opus48-1m-medium | A+ (7.9min) | A+ ($2.03) | A- (4.2) | B+ (4.1) |
| bash | opus48-1m-high | B+ (10.3min) | B+ ($2.74) | A- (4.3) | A- (4.3) |
| typescript-bun | opus48-1m-medium | B+ (10.9min) | B+ ($2.65) | A- (4.4) | A- (4.3) |
| typescript-bun | opus48-1m-high | B+ (10.9min) | B- ($3.33) | A- (4.3) | A- (4.2) |
| powershell | opus48-1m-high | B- (12.9min) | B ($3.04) | A (4.5) | B+ (3.9) |
| bash | opus48-1m-medium | A+ (7.8min) | A+ ($2.06) | B- (3.3) | B (3.7) |
| default | opus48-1m-high | A- (9.2min) | B+ ($2.66) | B- (3.4) | A- (4.1) |
| default | opus48-1m-ultracode | C- (16.6min) | C- ($4.79) | A (4.6) | A- (4.2) |
| default | opus48-1m-xhigh | C (15.0min) | C ($4.31) | A- (4.4) | B+ (3.9) |
| powershell | opus48-1m-ultracode | D (22.2min) | D ($5.98) | A (4.5) | A- (4.2) |
| typescript-bun | opus48-1m-xhigh | D (20.2min) | D ($5.69) | A- (4.4) | A- (4.1) |
| bash | opus48-1m-ultracode | D+ (19.5min) | D+ ($5.29) | B+ (3.9) | A- (4.1) |
| powershell | opus48-1m-xhigh* | D- (24.6min) | D ($6.18) | A- (4.3) | A- (4.3) |
| typescript-bun | opus48-1m-ultracode | D- (23.5min) | D- ($6.94) | A (4.5) | B+ (3.9) |
| bash | opus48-1m-xhigh | D (20.2min) | D ($5.67) | B+ (4.1) | B+ (3.9) |


<details>
<summary>Sorted by Duration tier (best-first), then avg of Cost/Tests/Workflow Craft tiers</summary>

| Language | Model | Duration | Cost | Tests Quality | Workflow Craft |
|----------|-------|----------|------|-----------|-------------|
| default | opus48-1m-medium | A+ (7.4min) | A+ ($1.87) | A- (4.1) | A- (4.3) |
| powershell | opus48-1m-medium | A+ (7.9min) | A+ ($2.03) | A- (4.2) | B+ (4.1) |
| bash | opus48-1m-medium | A+ (7.8min) | A+ ($2.06) | B- (3.3) | B (3.7) |
| default | opus48-1m-high | A- (9.2min) | B+ ($2.66) | B- (3.4) | A- (4.1) |
| bash | opus48-1m-high | B+ (10.3min) | B+ ($2.74) | A- (4.3) | A- (4.3) |
| typescript-bun | opus48-1m-medium | B+ (10.9min) | B+ ($2.65) | A- (4.4) | A- (4.3) |
| typescript-bun | opus48-1m-high | B+ (10.9min) | B- ($3.33) | A- (4.3) | A- (4.2) |
| powershell | opus48-1m-high | B- (12.9min) | B ($3.04) | A (4.5) | B+ (3.9) |
| default | opus48-1m-xhigh | C (15.0min) | C ($4.31) | A- (4.4) | B+ (3.9) |
| default | opus48-1m-ultracode | C- (16.6min) | C- ($4.79) | A (4.6) | A- (4.2) |
| bash | opus48-1m-ultracode | D+ (19.5min) | D+ ($5.29) | B+ (3.9) | A- (4.1) |
| powershell | opus48-1m-ultracode | D (22.2min) | D ($5.98) | A (4.5) | A- (4.2) |
| typescript-bun | opus48-1m-xhigh | D (20.2min) | D ($5.69) | A- (4.4) | A- (4.1) |
| bash | opus48-1m-xhigh | D (20.2min) | D ($5.67) | B+ (4.1) | B+ (3.9) |
| powershell | opus48-1m-xhigh* | D- (24.6min) | D ($6.18) | A- (4.3) | A- (4.3) |
| typescript-bun | opus48-1m-ultracode | D- (23.5min) | D- ($6.94) | A (4.5) | B+ (3.9) |

</details>

<details>
<summary>Sorted by Cost tier (best-first), then avg of Duration/Tests/Workflow Craft tiers</summary>

| Language | Model | Duration | Cost | Tests Quality | Workflow Craft |
|----------|-------|----------|------|-----------|-------------|
| default | opus48-1m-medium | A+ (7.4min) | A+ ($1.87) | A- (4.1) | A- (4.3) |
| powershell | opus48-1m-medium | A+ (7.9min) | A+ ($2.03) | A- (4.2) | B+ (4.1) |
| bash | opus48-1m-medium | A+ (7.8min) | A+ ($2.06) | B- (3.3) | B (3.7) |
| bash | opus48-1m-high | B+ (10.3min) | B+ ($2.74) | A- (4.3) | A- (4.3) |
| typescript-bun | opus48-1m-medium | B+ (10.9min) | B+ ($2.65) | A- (4.4) | A- (4.3) |
| default | opus48-1m-high | A- (9.2min) | B+ ($2.66) | B- (3.4) | A- (4.1) |
| powershell | opus48-1m-high | B- (12.9min) | B ($3.04) | A (4.5) | B+ (3.9) |
| typescript-bun | opus48-1m-high | B+ (10.9min) | B- ($3.33) | A- (4.3) | A- (4.2) |
| default | opus48-1m-xhigh | C (15.0min) | C ($4.31) | A- (4.4) | B+ (3.9) |
| default | opus48-1m-ultracode | C- (16.6min) | C- ($4.79) | A (4.6) | A- (4.2) |
| bash | opus48-1m-ultracode | D+ (19.5min) | D+ ($5.29) | B+ (3.9) | A- (4.1) |
| powershell | opus48-1m-ultracode | D (22.2min) | D ($5.98) | A (4.5) | A- (4.2) |
| typescript-bun | opus48-1m-xhigh | D (20.2min) | D ($5.69) | A- (4.4) | A- (4.1) |
| powershell | opus48-1m-xhigh* | D- (24.6min) | D ($6.18) | A- (4.3) | A- (4.3) |
| bash | opus48-1m-xhigh | D (20.2min) | D ($5.67) | B+ (4.1) | B+ (3.9) |
| typescript-bun | opus48-1m-ultracode | D- (23.5min) | D- ($6.94) | A (4.5) | B+ (3.9) |

</details>

<details>
<summary>Sorted by Tests Quality tier (best-first; no-data last), then avg of other tiers</summary>

| Language | Model | Duration | Cost | Tests Quality | Workflow Craft |
|----------|-------|----------|------|-----------|-------------|
| powershell | opus48-1m-high | B- (12.9min) | B ($3.04) | A (4.5) | B+ (3.9) |
| default | opus48-1m-ultracode | C- (16.6min) | C- ($4.79) | A (4.6) | A- (4.2) |
| powershell | opus48-1m-ultracode | D (22.2min) | D ($5.98) | A (4.5) | A- (4.2) |
| typescript-bun | opus48-1m-ultracode | D- (23.5min) | D- ($6.94) | A (4.5) | B+ (3.9) |
| default | opus48-1m-medium | A+ (7.4min) | A+ ($1.87) | A- (4.1) | A- (4.3) |
| powershell | opus48-1m-medium | A+ (7.9min) | A+ ($2.03) | A- (4.2) | B+ (4.1) |
| bash | opus48-1m-high | B+ (10.3min) | B+ ($2.74) | A- (4.3) | A- (4.3) |
| typescript-bun | opus48-1m-medium | B+ (10.9min) | B+ ($2.65) | A- (4.4) | A- (4.3) |
| typescript-bun | opus48-1m-high | B+ (10.9min) | B- ($3.33) | A- (4.3) | A- (4.2) |
| default | opus48-1m-xhigh | C (15.0min) | C ($4.31) | A- (4.4) | B+ (3.9) |
| typescript-bun | opus48-1m-xhigh | D (20.2min) | D ($5.69) | A- (4.4) | A- (4.1) |
| powershell | opus48-1m-xhigh* | D- (24.6min) | D ($6.18) | A- (4.3) | A- (4.3) |
| bash | opus48-1m-ultracode | D+ (19.5min) | D+ ($5.29) | B+ (3.9) | A- (4.1) |
| bash | opus48-1m-xhigh | D (20.2min) | D ($5.67) | B+ (4.1) | B+ (3.9) |
| bash | opus48-1m-medium | A+ (7.8min) | A+ ($2.06) | B- (3.3) | B (3.7) |
| default | opus48-1m-high | A- (9.2min) | B+ ($2.66) | B- (3.4) | A- (4.1) |

</details>

<details>
<summary>Sorted by Workflow Craft tier (best-first; no-data last), then avg of other tiers</summary>

| Language | Model | Duration | Cost | Tests Quality | Workflow Craft |
|----------|-------|----------|------|-----------|-------------|
| default | opus48-1m-medium | A+ (7.4min) | A+ ($1.87) | A- (4.1) | A- (4.3) |
| bash | opus48-1m-high | B+ (10.3min) | B+ ($2.74) | A- (4.3) | A- (4.3) |
| typescript-bun | opus48-1m-medium | B+ (10.9min) | B+ ($2.65) | A- (4.4) | A- (4.3) |
| default | opus48-1m-high | A- (9.2min) | B+ ($2.66) | B- (3.4) | A- (4.1) |
| typescript-bun | opus48-1m-high | B+ (10.9min) | B- ($3.33) | A- (4.3) | A- (4.2) |
| default | opus48-1m-ultracode | C- (16.6min) | C- ($4.79) | A (4.6) | A- (4.2) |
| bash | opus48-1m-ultracode | D+ (19.5min) | D+ ($5.29) | B+ (3.9) | A- (4.1) |
| powershell | opus48-1m-ultracode | D (22.2min) | D ($5.98) | A (4.5) | A- (4.2) |
| typescript-bun | opus48-1m-xhigh | D (20.2min) | D ($5.69) | A- (4.4) | A- (4.1) |
| powershell | opus48-1m-xhigh* | D- (24.6min) | D ($6.18) | A- (4.3) | A- (4.3) |
| powershell | opus48-1m-medium | A+ (7.9min) | A+ ($2.03) | A- (4.2) | B+ (4.1) |
| powershell | opus48-1m-high | B- (12.9min) | B ($3.04) | A (4.5) | B+ (3.9) |
| default | opus48-1m-xhigh | C (15.0min) | C ($4.31) | A- (4.4) | B+ (3.9) |
| bash | opus48-1m-xhigh | D (20.2min) | D ($5.67) | B+ (4.1) | B+ (3.9) |
| typescript-bun | opus48-1m-ultracode | D- (23.5min) | D- ($6.94) | A (4.5) | B+ (3.9) |
| bash | opus48-1m-medium | A+ (7.8min) | A+ ($2.06) | B- (3.3) | B (3.7) |

</details>

## Failed / Timed-Out Runs

| Task | Language | Model | Duration | Reason | Lines | actionlint | act-result.txt |
|------|------|-------|----------|--------|-------|------------|----------------|
| PR Label Assigner | powershell | opus48-1m-xhigh | 30.0min | timeout | 791 | pass | yes |
| Dependency License Checker | powershell | opus48-1m-xhigh | 30.0min | timeout | 880 | pass | yes |
| Environment Matrix Generator | powershell | opus48-1m-xhigh | 30.0min | timeout | 1190 | pass | no |
| Artifact Cleanup Script | powershell | opus48-1m-xhigh | 30.0min | timeout | 952 | pass | yes |

*4 run(s) excluded from averages below.*

## Comparison by Language/Model/Effort
*(failed runs are excluded from the cost/turns/errors averages; timed-out runs still pool into the duration stats — see [Column Definitions](#column-definitions))*
*See [Notes](#notes) for scoring rubric and CLI version legend.*

| Language | Model | Runs | Geo Duration | Max Duration | Geo Duration Net of Traps | Avg Errors | Geo Turns | Geo Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| bash | opus48-1m-high | 7 | 10.3min | 15.0min | 3.6min | 0.7 | 38 | $2.74 | $19.59 | 4.3 | 4.3 |
| bash | opus48-1m-medium | 7 | 7.8min | 23.9min | 7.2min | 1.1 | 31 | $2.06 | $16.64 | 3.3 | 3.7 |
| bash | opus48-1m-ultracode | 7 | 19.5min | 26.1min | 18.5min | 1.0 | 50 | $5.29 | $37.72 | 3.9 | 4.1 |
| bash | opus48-1m-xhigh | 7 | 20.2min | 23.9min | 17.9min | 1.3 | 59 | $5.67 | $40.21 | 4.1 | 3.9 |
| default | opus48-1m-high | 7 | 9.2min | 12.2min | 7.7min | 0.3 | 39 | $2.66 | $19.15 | 3.4 | 4.1 |
| default | opus48-1m-medium | 7 | 7.4min | 9.9min | 6.9min | 0.1 | 31 | $1.87 | $13.21 | 4.1 | 4.3 |
| default | opus48-1m-ultracode | 7 | 16.6min | 22.7min | 14.2min | 0.1 | 51 | $4.79 | $34.32 | 4.6 | 4.2 |
| default | opus48-1m-xhigh | 7 | 15.0min | 19.1min | 12.1min | 0.1 | 46 | $4.31 | $31.34 | 4.4 | 3.9 |
| powershell | opus48-1m-high | 14 | 12.9min | 17.3min | 10.8min | 0.5 | 41 | $3.04 | $42.93 | 4.5 | 3.9 |
| powershell | opus48-1m-medium | 14 | 7.9min | 12.9min | 7.1min | 0.4 | 32 | $2.03 | $30.64 | 4.2 | 4.1 |
| powershell | opus48-1m-ultracode | 14 | 22.2min | 33.6min | 19.7min | 0.4 | 48 | $5.98 | $92.82 | 4.5 | 4.2 |
| powershell | opus48-1m-xhigh* | 10 | 24.6min | ≥30.0min | 21.2min | 0.5 | 62 | $6.18 | $62.52 | 4.3 | 4.3 |
| typescript-bun | opus48-1m-high | 7 | 10.9min | 19.2min | 9.7min | 0.4 | 53 | $3.33 | $25.77 | 4.3 | 4.2 |
| typescript-bun | opus48-1m-medium | 7 | 10.9min | 23.0min | 9.5min | 0.6 | 48 | $2.65 | $19.09 | 4.4 | 4.3 |
| typescript-bun | opus48-1m-ultracode | 7 | 23.5min | 32.3min | 20.4min | 1.0 | 65 | $6.94 | $51.44 | 4.5 | 3.9 |
| typescript-bun | opus48-1m-xhigh | 7 | 20.2min | 25.3min | 18.2min | 0.9 | 58 | $5.69 | $40.33 | 4.4 | 4.1 |


<details>
<summary>Sorted by cost (geomean, cheapest first)</summary>

| Language | Model | Runs | Geo Duration | Max Duration | Geo Duration Net of Traps | Avg Errors | Geo Turns | Geo Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| default | opus48-1m-medium | 7 | 7.4min | 9.9min | 6.9min | 0.1 | 31 | $1.87 | $13.21 | 4.1 | 4.3 |
| powershell | opus48-1m-medium | 14 | 7.9min | 12.9min | 7.1min | 0.4 | 32 | $2.03 | $30.64 | 4.2 | 4.1 |
| bash | opus48-1m-medium | 7 | 7.8min | 23.9min | 7.2min | 1.1 | 31 | $2.06 | $16.64 | 3.3 | 3.7 |
| typescript-bun | opus48-1m-medium | 7 | 10.9min | 23.0min | 9.5min | 0.6 | 48 | $2.65 | $19.09 | 4.4 | 4.3 |
| default | opus48-1m-high | 7 | 9.2min | 12.2min | 7.7min | 0.3 | 39 | $2.66 | $19.15 | 3.4 | 4.1 |
| bash | opus48-1m-high | 7 | 10.3min | 15.0min | 3.6min | 0.7 | 38 | $2.74 | $19.59 | 4.3 | 4.3 |
| powershell | opus48-1m-high | 14 | 12.9min | 17.3min | 10.8min | 0.5 | 41 | $3.04 | $42.93 | 4.5 | 3.9 |
| typescript-bun | opus48-1m-high | 7 | 10.9min | 19.2min | 9.7min | 0.4 | 53 | $3.33 | $25.77 | 4.3 | 4.2 |
| default | opus48-1m-xhigh | 7 | 15.0min | 19.1min | 12.1min | 0.1 | 46 | $4.31 | $31.34 | 4.4 | 3.9 |
| default | opus48-1m-ultracode | 7 | 16.6min | 22.7min | 14.2min | 0.1 | 51 | $4.79 | $34.32 | 4.6 | 4.2 |
| bash | opus48-1m-ultracode | 7 | 19.5min | 26.1min | 18.5min | 1.0 | 50 | $5.29 | $37.72 | 3.9 | 4.1 |
| bash | opus48-1m-xhigh | 7 | 20.2min | 23.9min | 17.9min | 1.3 | 59 | $5.67 | $40.21 | 4.1 | 3.9 |
| typescript-bun | opus48-1m-xhigh | 7 | 20.2min | 25.3min | 18.2min | 0.9 | 58 | $5.69 | $40.33 | 4.4 | 4.1 |
| powershell | opus48-1m-ultracode | 14 | 22.2min | 33.6min | 19.7min | 0.4 | 48 | $5.98 | $92.82 | 4.5 | 4.2 |
| powershell | opus48-1m-xhigh* | 10 | 24.6min | ≥30.0min | 21.2min | 0.5 | 62 | $6.18 | $62.52 | 4.3 | 4.3 |
| typescript-bun | opus48-1m-ultracode | 7 | 23.5min | 32.3min | 20.4min | 1.0 | 65 | $6.94 | $51.44 | 4.5 | 3.9 |

</details>

<details>
<summary>Sorted by duration (geomean, fastest first)</summary>

| Language | Model | Runs | Geo Duration | Max Duration | Geo Duration Net of Traps | Avg Errors | Geo Turns | Geo Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| default | opus48-1m-medium | 7 | 7.4min | 9.9min | 6.9min | 0.1 | 31 | $1.87 | $13.21 | 4.1 | 4.3 |
| bash | opus48-1m-medium | 7 | 7.8min | 23.9min | 7.2min | 1.1 | 31 | $2.06 | $16.64 | 3.3 | 3.7 |
| powershell | opus48-1m-medium | 14 | 7.9min | 12.9min | 7.1min | 0.4 | 32 | $2.03 | $30.64 | 4.2 | 4.1 |
| default | opus48-1m-high | 7 | 9.2min | 12.2min | 7.7min | 0.3 | 39 | $2.66 | $19.15 | 3.4 | 4.1 |
| bash | opus48-1m-high | 7 | 10.3min | 15.0min | 3.6min | 0.7 | 38 | $2.74 | $19.59 | 4.3 | 4.3 |
| typescript-bun | opus48-1m-high | 7 | 10.9min | 19.2min | 9.7min | 0.4 | 53 | $3.33 | $25.77 | 4.3 | 4.2 |
| typescript-bun | opus48-1m-medium | 7 | 10.9min | 23.0min | 9.5min | 0.6 | 48 | $2.65 | $19.09 | 4.4 | 4.3 |
| powershell | opus48-1m-high | 14 | 12.9min | 17.3min | 10.8min | 0.5 | 41 | $3.04 | $42.93 | 4.5 | 3.9 |
| default | opus48-1m-xhigh | 7 | 15.0min | 19.1min | 12.1min | 0.1 | 46 | $4.31 | $31.34 | 4.4 | 3.9 |
| default | opus48-1m-ultracode | 7 | 16.6min | 22.7min | 14.2min | 0.1 | 51 | $4.79 | $34.32 | 4.6 | 4.2 |
| bash | opus48-1m-ultracode | 7 | 19.5min | 26.1min | 18.5min | 1.0 | 50 | $5.29 | $37.72 | 3.9 | 4.1 |
| typescript-bun | opus48-1m-xhigh | 7 | 20.2min | 25.3min | 18.2min | 0.9 | 58 | $5.69 | $40.33 | 4.4 | 4.1 |
| bash | opus48-1m-xhigh | 7 | 20.2min | 23.9min | 17.9min | 1.3 | 59 | $5.67 | $40.21 | 4.1 | 3.9 |
| powershell | opus48-1m-ultracode | 14 | 22.2min | 33.6min | 19.7min | 0.4 | 48 | $5.98 | $92.82 | 4.5 | 4.2 |
| typescript-bun | opus48-1m-ultracode | 7 | 23.5min | 32.3min | 20.4min | 1.0 | 65 | $6.94 | $51.44 | 4.5 | 3.9 |
| powershell | opus48-1m-xhigh* | 10 | 24.6min | ≥30.0min | 21.2min | 0.5 | 62 | $6.18 | $62.52 | 4.3 | 4.3 |

</details>

<details>
<summary>Sorted by duration net of traps (geomean, fastest first)</summary>

| Language | Model | Runs | Geo Duration | Max Duration | Geo Duration Net of Traps | Avg Errors | Geo Turns | Geo Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| bash | opus48-1m-high | 7 | 10.3min | 15.0min | 3.6min | 0.7 | 38 | $2.74 | $19.59 | 4.3 | 4.3 |
| default | opus48-1m-medium | 7 | 7.4min | 9.9min | 6.9min | 0.1 | 31 | $1.87 | $13.21 | 4.1 | 4.3 |
| powershell | opus48-1m-medium | 14 | 7.9min | 12.9min | 7.1min | 0.4 | 32 | $2.03 | $30.64 | 4.2 | 4.1 |
| bash | opus48-1m-medium | 7 | 7.8min | 23.9min | 7.2min | 1.1 | 31 | $2.06 | $16.64 | 3.3 | 3.7 |
| default | opus48-1m-high | 7 | 9.2min | 12.2min | 7.7min | 0.3 | 39 | $2.66 | $19.15 | 3.4 | 4.1 |
| typescript-bun | opus48-1m-medium | 7 | 10.9min | 23.0min | 9.5min | 0.6 | 48 | $2.65 | $19.09 | 4.4 | 4.3 |
| typescript-bun | opus48-1m-high | 7 | 10.9min | 19.2min | 9.7min | 0.4 | 53 | $3.33 | $25.77 | 4.3 | 4.2 |
| powershell | opus48-1m-high | 14 | 12.9min | 17.3min | 10.8min | 0.5 | 41 | $3.04 | $42.93 | 4.5 | 3.9 |
| default | opus48-1m-xhigh | 7 | 15.0min | 19.1min | 12.1min | 0.1 | 46 | $4.31 | $31.34 | 4.4 | 3.9 |
| default | opus48-1m-ultracode | 7 | 16.6min | 22.7min | 14.2min | 0.1 | 51 | $4.79 | $34.32 | 4.6 | 4.2 |
| bash | opus48-1m-xhigh | 7 | 20.2min | 23.9min | 17.9min | 1.3 | 59 | $5.67 | $40.21 | 4.1 | 3.9 |
| typescript-bun | opus48-1m-xhigh | 7 | 20.2min | 25.3min | 18.2min | 0.9 | 58 | $5.69 | $40.33 | 4.4 | 4.1 |
| bash | opus48-1m-ultracode | 7 | 19.5min | 26.1min | 18.5min | 1.0 | 50 | $5.29 | $37.72 | 3.9 | 4.1 |
| powershell | opus48-1m-ultracode | 14 | 22.2min | 33.6min | 19.7min | 0.4 | 48 | $5.98 | $92.82 | 4.5 | 4.2 |
| typescript-bun | opus48-1m-ultracode | 7 | 23.5min | 32.3min | 20.4min | 1.0 | 65 | $6.94 | $51.44 | 4.5 | 3.9 |
| powershell | opus48-1m-xhigh* | 10 | 24.6min | ≥30.0min | 21.2min | 0.5 | 62 | $6.18 | $62.52 | 4.3 | 4.3 |

</details>

<details>
<summary>Sorted by avg errors (fewest first)</summary>

| Language | Model | Runs | Geo Duration | Max Duration | Geo Duration Net of Traps | Avg Errors | Geo Turns | Geo Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| default | opus48-1m-medium | 7 | 7.4min | 9.9min | 6.9min | 0.1 | 31 | $1.87 | $13.21 | 4.1 | 4.3 |
| default | opus48-1m-ultracode | 7 | 16.6min | 22.7min | 14.2min | 0.1 | 51 | $4.79 | $34.32 | 4.6 | 4.2 |
| default | opus48-1m-xhigh | 7 | 15.0min | 19.1min | 12.1min | 0.1 | 46 | $4.31 | $31.34 | 4.4 | 3.9 |
| default | opus48-1m-high | 7 | 9.2min | 12.2min | 7.7min | 0.3 | 39 | $2.66 | $19.15 | 3.4 | 4.1 |
| powershell | opus48-1m-medium | 14 | 7.9min | 12.9min | 7.1min | 0.4 | 32 | $2.03 | $30.64 | 4.2 | 4.1 |
| powershell | opus48-1m-ultracode | 14 | 22.2min | 33.6min | 19.7min | 0.4 | 48 | $5.98 | $92.82 | 4.5 | 4.2 |
| typescript-bun | opus48-1m-high | 7 | 10.9min | 19.2min | 9.7min | 0.4 | 53 | $3.33 | $25.77 | 4.3 | 4.2 |
| powershell | opus48-1m-high | 14 | 12.9min | 17.3min | 10.8min | 0.5 | 41 | $3.04 | $42.93 | 4.5 | 3.9 |
| powershell | opus48-1m-xhigh* | 10 | 24.6min | ≥30.0min | 21.2min | 0.5 | 62 | $6.18 | $62.52 | 4.3 | 4.3 |
| typescript-bun | opus48-1m-medium | 7 | 10.9min | 23.0min | 9.5min | 0.6 | 48 | $2.65 | $19.09 | 4.4 | 4.3 |
| bash | opus48-1m-high | 7 | 10.3min | 15.0min | 3.6min | 0.7 | 38 | $2.74 | $19.59 | 4.3 | 4.3 |
| typescript-bun | opus48-1m-xhigh | 7 | 20.2min | 25.3min | 18.2min | 0.9 | 58 | $5.69 | $40.33 | 4.4 | 4.1 |
| bash | opus48-1m-ultracode | 7 | 19.5min | 26.1min | 18.5min | 1.0 | 50 | $5.29 | $37.72 | 3.9 | 4.1 |
| typescript-bun | opus48-1m-ultracode | 7 | 23.5min | 32.3min | 20.4min | 1.0 | 65 | $6.94 | $51.44 | 4.5 | 3.9 |
| bash | opus48-1m-medium | 7 | 7.8min | 23.9min | 7.2min | 1.1 | 31 | $2.06 | $16.64 | 3.3 | 3.7 |
| bash | opus48-1m-xhigh | 7 | 20.2min | 23.9min | 17.9min | 1.3 | 59 | $5.67 | $40.21 | 4.1 | 3.9 |

</details>

<details>
<summary>Sorted by turns (geomean, fewest first)</summary>

| Language | Model | Runs | Geo Duration | Max Duration | Geo Duration Net of Traps | Avg Errors | Geo Turns | Geo Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| bash | opus48-1m-medium | 7 | 7.8min | 23.9min | 7.2min | 1.1 | 31 | $2.06 | $16.64 | 3.3 | 3.7 |
| default | opus48-1m-medium | 7 | 7.4min | 9.9min | 6.9min | 0.1 | 31 | $1.87 | $13.21 | 4.1 | 4.3 |
| powershell | opus48-1m-medium | 14 | 7.9min | 12.9min | 7.1min | 0.4 | 32 | $2.03 | $30.64 | 4.2 | 4.1 |
| bash | opus48-1m-high | 7 | 10.3min | 15.0min | 3.6min | 0.7 | 38 | $2.74 | $19.59 | 4.3 | 4.3 |
| default | opus48-1m-high | 7 | 9.2min | 12.2min | 7.7min | 0.3 | 39 | $2.66 | $19.15 | 3.4 | 4.1 |
| powershell | opus48-1m-high | 14 | 12.9min | 17.3min | 10.8min | 0.5 | 41 | $3.04 | $42.93 | 4.5 | 3.9 |
| default | opus48-1m-xhigh | 7 | 15.0min | 19.1min | 12.1min | 0.1 | 46 | $4.31 | $31.34 | 4.4 | 3.9 |
| typescript-bun | opus48-1m-medium | 7 | 10.9min | 23.0min | 9.5min | 0.6 | 48 | $2.65 | $19.09 | 4.4 | 4.3 |
| powershell | opus48-1m-ultracode | 14 | 22.2min | 33.6min | 19.7min | 0.4 | 48 | $5.98 | $92.82 | 4.5 | 4.2 |
| bash | opus48-1m-ultracode | 7 | 19.5min | 26.1min | 18.5min | 1.0 | 50 | $5.29 | $37.72 | 3.9 | 4.1 |
| default | opus48-1m-ultracode | 7 | 16.6min | 22.7min | 14.2min | 0.1 | 51 | $4.79 | $34.32 | 4.6 | 4.2 |
| typescript-bun | opus48-1m-high | 7 | 10.9min | 19.2min | 9.7min | 0.4 | 53 | $3.33 | $25.77 | 4.3 | 4.2 |
| typescript-bun | opus48-1m-xhigh | 7 | 20.2min | 25.3min | 18.2min | 0.9 | 58 | $5.69 | $40.33 | 4.4 | 4.1 |
| bash | opus48-1m-xhigh | 7 | 20.2min | 23.9min | 17.9min | 1.3 | 59 | $5.67 | $40.21 | 4.1 | 3.9 |
| powershell | opus48-1m-xhigh* | 10 | 24.6min | ≥30.0min | 21.2min | 0.5 | 62 | $6.18 | $62.52 | 4.3 | 4.3 |
| typescript-bun | opus48-1m-ultracode | 7 | 23.5min | 32.3min | 20.4min | 1.0 | 65 | $6.94 | $51.44 | 4.5 | 3.9 |

</details>

<details>
<summary>Sorted by LLM-as-judge score (best first)</summary>

| Language | Model | Runs | Geo Duration | Max Duration | Geo Duration Net of Traps | Avg Errors | Geo Turns | Geo Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| default | opus48-1m-ultracode | 7 | 16.6min | 22.7min | 14.2min | 0.1 | 51 | $4.79 | $34.32 | 4.6 | 4.2 |
| typescript-bun | opus48-1m-ultracode | 7 | 23.5min | 32.3min | 20.4min | 1.0 | 65 | $6.94 | $51.44 | 4.5 | 3.9 |
| powershell | opus48-1m-high | 14 | 12.9min | 17.3min | 10.8min | 0.5 | 41 | $3.04 | $42.93 | 4.5 | 3.9 |
| powershell | opus48-1m-ultracode | 14 | 22.2min | 33.6min | 19.7min | 0.4 | 48 | $5.98 | $92.82 | 4.5 | 4.2 |
| default | opus48-1m-xhigh | 7 | 15.0min | 19.1min | 12.1min | 0.1 | 46 | $4.31 | $31.34 | 4.4 | 3.9 |
| typescript-bun | opus48-1m-medium | 7 | 10.9min | 23.0min | 9.5min | 0.6 | 48 | $2.65 | $19.09 | 4.4 | 4.3 |
| typescript-bun | opus48-1m-xhigh | 7 | 20.2min | 25.3min | 18.2min | 0.9 | 58 | $5.69 | $40.33 | 4.4 | 4.1 |
| powershell | opus48-1m-xhigh* | 10 | 24.6min | ≥30.0min | 21.2min | 0.5 | 62 | $6.18 | $62.52 | 4.3 | 4.3 |
| bash | opus48-1m-high | 7 | 10.3min | 15.0min | 3.6min | 0.7 | 38 | $2.74 | $19.59 | 4.3 | 4.3 |
| typescript-bun | opus48-1m-high | 7 | 10.9min | 19.2min | 9.7min | 0.4 | 53 | $3.33 | $25.77 | 4.3 | 4.2 |
| powershell | opus48-1m-medium | 14 | 7.9min | 12.9min | 7.1min | 0.4 | 32 | $2.03 | $30.64 | 4.2 | 4.1 |
| default | opus48-1m-medium | 7 | 7.4min | 9.9min | 6.9min | 0.1 | 31 | $1.87 | $13.21 | 4.1 | 4.3 |
| bash | opus48-1m-xhigh | 7 | 20.2min | 23.9min | 17.9min | 1.3 | 59 | $5.67 | $40.21 | 4.1 | 3.9 |
| bash | opus48-1m-ultracode | 7 | 19.5min | 26.1min | 18.5min | 1.0 | 50 | $5.29 | $37.72 | 3.9 | 4.1 |
| default | opus48-1m-high | 7 | 9.2min | 12.2min | 7.7min | 0.3 | 39 | $2.66 | $19.15 | 3.4 | 4.1 |
| bash | opus48-1m-medium | 7 | 7.8min | 23.9min | 7.2min | 1.1 | 31 | $2.06 | $16.64 | 3.3 | 3.7 |

</details>

<details>
<summary>Sorted by deliverable-quality score (best first)</summary>

| Language | Model | Runs | Geo Duration | Max Duration | Geo Duration Net of Traps | Avg Errors | Geo Turns | Geo Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| powershell | opus48-1m-xhigh* | 10 | 24.6min | ≥30.0min | 21.2min | 0.5 | 62 | $6.18 | $62.52 | 4.3 | 4.3 |
| bash | opus48-1m-high | 7 | 10.3min | 15.0min | 3.6min | 0.7 | 38 | $2.74 | $19.59 | 4.3 | 4.3 |
| default | opus48-1m-medium | 7 | 7.4min | 9.9min | 6.9min | 0.1 | 31 | $1.87 | $13.21 | 4.1 | 4.3 |
| typescript-bun | opus48-1m-medium | 7 | 10.9min | 23.0min | 9.5min | 0.6 | 48 | $2.65 | $19.09 | 4.4 | 4.3 |
| default | opus48-1m-ultracode | 7 | 16.6min | 22.7min | 14.2min | 0.1 | 51 | $4.79 | $34.32 | 4.6 | 4.2 |
| typescript-bun | opus48-1m-high | 7 | 10.9min | 19.2min | 9.7min | 0.4 | 53 | $3.33 | $25.77 | 4.3 | 4.2 |
| powershell | opus48-1m-ultracode | 14 | 22.2min | 33.6min | 19.7min | 0.4 | 48 | $5.98 | $92.82 | 4.5 | 4.2 |
| bash | opus48-1m-ultracode | 7 | 19.5min | 26.1min | 18.5min | 1.0 | 50 | $5.29 | $37.72 | 3.9 | 4.1 |
| default | opus48-1m-high | 7 | 9.2min | 12.2min | 7.7min | 0.3 | 39 | $2.66 | $19.15 | 3.4 | 4.1 |
| typescript-bun | opus48-1m-xhigh | 7 | 20.2min | 25.3min | 18.2min | 0.9 | 58 | $5.69 | $40.33 | 4.4 | 4.1 |
| powershell | opus48-1m-medium | 14 | 7.9min | 12.9min | 7.1min | 0.4 | 32 | $2.03 | $30.64 | 4.2 | 4.1 |
| default | opus48-1m-xhigh | 7 | 15.0min | 19.1min | 12.1min | 0.1 | 46 | $4.31 | $31.34 | 4.4 | 3.9 |
| powershell | opus48-1m-high | 14 | 12.9min | 17.3min | 10.8min | 0.5 | 41 | $3.04 | $42.93 | 4.5 | 3.9 |
| bash | opus48-1m-xhigh | 7 | 20.2min | 23.9min | 17.9min | 1.3 | 59 | $5.67 | $40.21 | 4.1 | 3.9 |
| typescript-bun | opus48-1m-ultracode | 7 | 23.5min | 32.3min | 20.4min | 1.0 | 65 | $6.94 | $51.44 | 4.5 | 3.9 |
| bash | opus48-1m-medium | 7 | 7.8min | 23.9min | 7.2min | 1.1 | 31 | $2.06 | $16.64 | 3.3 | 3.7 |

</details>

## Savings Analysis

### Trap Analysis by Language/Model/Effort/Category

| Trap | Language | Model | Fell In | Time Lost | % of Time | $ Lost | % of $ |
|------|------|-------|---------|-----------|-----------|--------|--------|
| repeated-test-reruns | bash | opus48-1m-high-cli2.1.195 | 4 | 7.3min | 0.3% | $2.04 | 0.35% |
| repeated-test-reruns | bash | opus48-1m-medium-cli2.1.195 | 1 | 2.3min | 0.1% | $0.56 | 0.10% |
| repeated-test-reruns | bash | opus48-1m-ultracode-cli2.1.195 | 2 | 4.3min | 0.2% | $1.26 | 0.22% |
| repeated-test-reruns | bash | opus48-1m-xhigh-cli2.1.195 | 5 | 8.0min | 0.4% | $2.34 | 0.41% |
| repeated-test-reruns | default | opus48-1m-high-cli2.1.195 | 4 | 8.0min | 0.4% | $2.44 | 0.42% |
| repeated-test-reruns | default | opus48-1m-medium-cli2.1.193 | 1 | 1.3min | 0.1% | $0.31 | 0.05% |
| repeated-test-reruns | default | opus48-1m-medium-cli2.1.195 | 1 | 2.7min | 0.1% | $0.64 | 0.11% |
| repeated-test-reruns | default | opus48-1m-ultracode-cli2.1.195 | 8 | 18.0min | 0.8% | $5.17 | 0.89% |
| repeated-test-reruns | default | opus48-1m-xhigh-cli2.1.195 | 8 | 17.0min | 0.8% | $5.19 | 0.90% |
| repeated-test-reruns | powershell | opus48-1m-high-cli2.1.195 | 12 | 26.7min | 1.2% | $6.14 | 1.06% |
| repeated-test-reruns | powershell | opus48-1m-medium-cli2.1.193 | 4 | 4.3min | 0.2% | $1.04 | 0.18% |
| repeated-test-reruns | powershell | opus48-1m-medium-cli2.1.195 | 3 | 3.3min | 0.1% | $0.85 | 0.15% |
| repeated-test-reruns | powershell | opus48-1m-ultracode-cli2.1.195 | 11 | 21.7min | 1.0% | $6.04 | 1.05% |
| repeated-test-reruns | powershell | opus48-1m-xhigh-cli2.1.195 | 13 | 39.0min | 1.7% | $6.91 | 1.20% |
| repeated-test-reruns | typescript-bun | opus48-1m-high-cli2.1.195 | 3 | 9.0min | 0.4% | $3.07 | 0.53% |
| repeated-test-reruns | typescript-bun | opus48-1m-medium-cli2.1.193 | 2 | 2.0min | 0.1% | $0.47 | 0.08% |
| repeated-test-reruns | typescript-bun | opus48-1m-medium-cli2.1.195 | 3 | 6.7min | 0.3% | $1.54 | 0.27% |
| repeated-test-reruns | typescript-bun | opus48-1m-ultracode-cli2.1.195 | 7 | 17.7min | 0.8% | $5.22 | 0.90% |
| repeated-test-reruns | typescript-bun | opus48-1m-xhigh-cli2.1.195 | 5 | 9.3min | 0.4% | $2.65 | 0.46% |
| fixture-rework | bash | opus48-1m-high-cli2.1.195 | 4 | 22.0min | 1.0% | $6.20 | 1.07% |
| fixture-rework | bash | opus48-1m-medium-cli2.1.193 | 2 | 1.3min | 0.1% | $0.37 | 0.06% |
| fixture-rework | bash | opus48-1m-medium-cli2.1.195 | 1 | 5.0min | 0.2% | $1.19 | 0.21% |
| fixture-rework | bash | opus48-1m-ultracode-cli2.1.195 | 1 | 2.3min | 0.1% | $0.67 | 0.12% |
| fixture-rework | bash | opus48-1m-xhigh-cli2.1.195 | 3 | 6.0min | 0.3% | $1.62 | 0.28% |
| fixture-rework | default | opus48-1m-high-cli2.1.195 | 1 | 2.0min | 0.1% | $0.52 | 0.09% |
| fixture-rework | default | opus48-1m-xhigh-cli2.1.195 | 3 | 3.3min | 0.1% | $0.88 | 0.15% |
| fixture-rework | powershell | opus48-1m-high-cli2.1.195 | 3 | 3.3min | 0.1% | $0.72 | 0.12% |
| fixture-rework | powershell | opus48-1m-medium-cli2.1.193 | 2 | 3.0min | 0.1% | $0.72 | 0.12% |
| fixture-rework | powershell | opus48-1m-ultracode-cli2.1.195 | 1 | 0.7min | 0.0% | $0.16 | 0.03% |
| fixture-rework | powershell | opus48-1m-xhigh-cli2.1.195 | 2 | 4.7min | 0.2% | $0.38 | 0.07% |
| fixture-rework | typescript-bun | opus48-1m-high-cli2.1.195 | 1 | 0.7min | 0.0% | $0.18 | 0.03% |
| fixture-rework | typescript-bun | opus48-1m-medium-cli2.1.195 | 1 | 1.0min | 0.0% | $0.25 | 0.04% |
| fixture-rework | typescript-bun | opus48-1m-ultracode-cli2.1.195 | 2 | 3.7min | 0.2% | $1.16 | 0.20% |
| fixture-rework | typescript-bun | opus48-1m-xhigh-cli2.1.195 | 3 | 4.7min | 0.2% | $1.32 | 0.23% |
| docker-pwsh-install | powershell | opus48-1m-ultracode-cli2.1.195 | 3 | 4.5min | 0.2% | $1.20 | 0.21% |
| docker-pwsh-install | powershell | opus48-1m-xhigh-cli2.1.195 | 2 | 3.0min | 0.1% | $0.82 | 0.14% |
| mid-run-module-restructure | powershell | opus48-1m-ultracode-cli2.1.195 | 2 | 4.0min | 0.2% | $1.32 | 0.23% |
| bats-setup-issues | bash | opus48-1m-high-cli2.1.195 | 1 | 1.2min | 0.1% | $0.33 | 0.06% |
| bats-setup-issues | bash | opus48-1m-xhigh-cli2.1.195 | 2 | 1.8min | 0.1% | $0.51 | 0.09% |
| actionlint-fix-cycles | powershell | opus48-1m-medium-cli2.1.193 | 1 | 1.0min | 0.0% | $0.27 | 0.05% |
| actionlint-fix-cycles | typescript-bun | opus48-1m-medium-cli2.1.195 | 1 | 0.7min | 0.0% | $0.13 | 0.02% |
| act-fixture-paths | bash | opus48-1m-ultracode-cli2.1.195 | 1 | 1.0min | 0.0% | $0.26 | 0.05% |
| act-push-debug-loops | powershell | opus48-1m-ultracode-cli2.1.195 | 1 | 0.8min | 0.0% | $0.23 | 0.04% |


<details>
<summary>Sorted by time lost (least first)</summary>

| Trap | Language | Model | Fell In | Time Lost | % of Time | $ Lost | % of $ |
|------|------|-------|---------|-----------|-----------|--------|--------|
| fixture-rework | powershell | opus48-1m-ultracode-cli2.1.195 | 1 | 0.7min | 0.0% | $0.16 | 0.03% |
| fixture-rework | typescript-bun | opus48-1m-high-cli2.1.195 | 1 | 0.7min | 0.0% | $0.18 | 0.03% |
| actionlint-fix-cycles | typescript-bun | opus48-1m-medium-cli2.1.195 | 1 | 0.7min | 0.0% | $0.13 | 0.02% |
| act-push-debug-loops | powershell | opus48-1m-ultracode-cli2.1.195 | 1 | 0.8min | 0.0% | $0.23 | 0.04% |
| fixture-rework | typescript-bun | opus48-1m-medium-cli2.1.195 | 1 | 1.0min | 0.0% | $0.25 | 0.04% |
| actionlint-fix-cycles | powershell | opus48-1m-medium-cli2.1.193 | 1 | 1.0min | 0.0% | $0.27 | 0.05% |
| act-fixture-paths | bash | opus48-1m-ultracode-cli2.1.195 | 1 | 1.0min | 0.0% | $0.26 | 0.05% |
| bats-setup-issues | bash | opus48-1m-high-cli2.1.195 | 1 | 1.2min | 0.1% | $0.33 | 0.06% |
| repeated-test-reruns | default | opus48-1m-medium-cli2.1.193 | 1 | 1.3min | 0.1% | $0.31 | 0.05% |
| fixture-rework | bash | opus48-1m-medium-cli2.1.193 | 2 | 1.3min | 0.1% | $0.37 | 0.06% |
| bats-setup-issues | bash | opus48-1m-xhigh-cli2.1.195 | 2 | 1.8min | 0.1% | $0.51 | 0.09% |
| repeated-test-reruns | typescript-bun | opus48-1m-medium-cli2.1.193 | 2 | 2.0min | 0.1% | $0.47 | 0.08% |
| fixture-rework | default | opus48-1m-high-cli2.1.195 | 1 | 2.0min | 0.1% | $0.52 | 0.09% |
| repeated-test-reruns | bash | opus48-1m-medium-cli2.1.195 | 1 | 2.3min | 0.1% | $0.56 | 0.10% |
| fixture-rework | bash | opus48-1m-ultracode-cli2.1.195 | 1 | 2.3min | 0.1% | $0.67 | 0.12% |
| repeated-test-reruns | default | opus48-1m-medium-cli2.1.195 | 1 | 2.7min | 0.1% | $0.64 | 0.11% |
| fixture-rework | powershell | opus48-1m-medium-cli2.1.193 | 2 | 3.0min | 0.1% | $0.72 | 0.12% |
| docker-pwsh-install | powershell | opus48-1m-xhigh-cli2.1.195 | 2 | 3.0min | 0.1% | $0.82 | 0.14% |
| repeated-test-reruns | powershell | opus48-1m-medium-cli2.1.195 | 3 | 3.3min | 0.1% | $0.85 | 0.15% |
| fixture-rework | default | opus48-1m-xhigh-cli2.1.195 | 3 | 3.3min | 0.1% | $0.88 | 0.15% |
| fixture-rework | powershell | opus48-1m-high-cli2.1.195 | 3 | 3.3min | 0.1% | $0.72 | 0.12% |
| fixture-rework | typescript-bun | opus48-1m-ultracode-cli2.1.195 | 2 | 3.7min | 0.2% | $1.16 | 0.20% |
| mid-run-module-restructure | powershell | opus48-1m-ultracode-cli2.1.195 | 2 | 4.0min | 0.2% | $1.32 | 0.23% |
| repeated-test-reruns | bash | opus48-1m-ultracode-cli2.1.195 | 2 | 4.3min | 0.2% | $1.26 | 0.22% |
| repeated-test-reruns | powershell | opus48-1m-medium-cli2.1.193 | 4 | 4.3min | 0.2% | $1.04 | 0.18% |
| docker-pwsh-install | powershell | opus48-1m-ultracode-cli2.1.195 | 3 | 4.5min | 0.2% | $1.20 | 0.21% |
| fixture-rework | powershell | opus48-1m-xhigh-cli2.1.195 | 2 | 4.7min | 0.2% | $0.38 | 0.07% |
| fixture-rework | typescript-bun | opus48-1m-xhigh-cli2.1.195 | 3 | 4.7min | 0.2% | $1.32 | 0.23% |
| fixture-rework | bash | opus48-1m-medium-cli2.1.195 | 1 | 5.0min | 0.2% | $1.19 | 0.21% |
| fixture-rework | bash | opus48-1m-xhigh-cli2.1.195 | 3 | 6.0min | 0.3% | $1.62 | 0.28% |
| repeated-test-reruns | typescript-bun | opus48-1m-medium-cli2.1.195 | 3 | 6.7min | 0.3% | $1.54 | 0.27% |
| repeated-test-reruns | bash | opus48-1m-high-cli2.1.195 | 4 | 7.3min | 0.3% | $2.04 | 0.35% |
| repeated-test-reruns | bash | opus48-1m-xhigh-cli2.1.195 | 5 | 8.0min | 0.4% | $2.34 | 0.41% |
| repeated-test-reruns | default | opus48-1m-high-cli2.1.195 | 4 | 8.0min | 0.4% | $2.44 | 0.42% |
| repeated-test-reruns | typescript-bun | opus48-1m-high-cli2.1.195 | 3 | 9.0min | 0.4% | $3.07 | 0.53% |
| repeated-test-reruns | typescript-bun | opus48-1m-xhigh-cli2.1.195 | 5 | 9.3min | 0.4% | $2.65 | 0.46% |
| repeated-test-reruns | default | opus48-1m-xhigh-cli2.1.195 | 8 | 17.0min | 0.8% | $5.19 | 0.90% |
| repeated-test-reruns | typescript-bun | opus48-1m-ultracode-cli2.1.195 | 7 | 17.7min | 0.8% | $5.22 | 0.90% |
| repeated-test-reruns | default | opus48-1m-ultracode-cli2.1.195 | 8 | 18.0min | 0.8% | $5.17 | 0.89% |
| repeated-test-reruns | powershell | opus48-1m-ultracode-cli2.1.195 | 11 | 21.7min | 1.0% | $6.04 | 1.05% |
| fixture-rework | bash | opus48-1m-high-cli2.1.195 | 4 | 22.0min | 1.0% | $6.20 | 1.07% |
| repeated-test-reruns | powershell | opus48-1m-high-cli2.1.195 | 12 | 26.7min | 1.2% | $6.14 | 1.06% |
| repeated-test-reruns | powershell | opus48-1m-xhigh-cli2.1.195 | 13 | 39.0min | 1.7% | $6.91 | 1.20% |

</details>

<details>
<summary>Sorted by $ lost (least first)</summary>

| Trap | Language | Model | Fell In | Time Lost | % of Time | $ Lost | % of $ |
|------|------|-------|---------|-----------|-----------|--------|--------|
| actionlint-fix-cycles | typescript-bun | opus48-1m-medium-cli2.1.195 | 1 | 0.7min | 0.0% | $0.13 | 0.02% |
| fixture-rework | powershell | opus48-1m-ultracode-cli2.1.195 | 1 | 0.7min | 0.0% | $0.16 | 0.03% |
| fixture-rework | typescript-bun | opus48-1m-high-cli2.1.195 | 1 | 0.7min | 0.0% | $0.18 | 0.03% |
| act-push-debug-loops | powershell | opus48-1m-ultracode-cli2.1.195 | 1 | 0.8min | 0.0% | $0.23 | 0.04% |
| fixture-rework | typescript-bun | opus48-1m-medium-cli2.1.195 | 1 | 1.0min | 0.0% | $0.25 | 0.04% |
| act-fixture-paths | bash | opus48-1m-ultracode-cli2.1.195 | 1 | 1.0min | 0.0% | $0.26 | 0.05% |
| actionlint-fix-cycles | powershell | opus48-1m-medium-cli2.1.193 | 1 | 1.0min | 0.0% | $0.27 | 0.05% |
| repeated-test-reruns | default | opus48-1m-medium-cli2.1.193 | 1 | 1.3min | 0.1% | $0.31 | 0.05% |
| bats-setup-issues | bash | opus48-1m-high-cli2.1.195 | 1 | 1.2min | 0.1% | $0.33 | 0.06% |
| fixture-rework | bash | opus48-1m-medium-cli2.1.193 | 2 | 1.3min | 0.1% | $0.37 | 0.06% |
| fixture-rework | powershell | opus48-1m-xhigh-cli2.1.195 | 2 | 4.7min | 0.2% | $0.38 | 0.07% |
| repeated-test-reruns | typescript-bun | opus48-1m-medium-cli2.1.193 | 2 | 2.0min | 0.1% | $0.47 | 0.08% |
| bats-setup-issues | bash | opus48-1m-xhigh-cli2.1.195 | 2 | 1.8min | 0.1% | $0.51 | 0.09% |
| fixture-rework | default | opus48-1m-high-cli2.1.195 | 1 | 2.0min | 0.1% | $0.52 | 0.09% |
| repeated-test-reruns | bash | opus48-1m-medium-cli2.1.195 | 1 | 2.3min | 0.1% | $0.56 | 0.10% |
| repeated-test-reruns | default | opus48-1m-medium-cli2.1.195 | 1 | 2.7min | 0.1% | $0.64 | 0.11% |
| fixture-rework | bash | opus48-1m-ultracode-cli2.1.195 | 1 | 2.3min | 0.1% | $0.67 | 0.12% |
| fixture-rework | powershell | opus48-1m-medium-cli2.1.193 | 2 | 3.0min | 0.1% | $0.72 | 0.12% |
| fixture-rework | powershell | opus48-1m-high-cli2.1.195 | 3 | 3.3min | 0.1% | $0.72 | 0.12% |
| docker-pwsh-install | powershell | opus48-1m-xhigh-cli2.1.195 | 2 | 3.0min | 0.1% | $0.82 | 0.14% |
| repeated-test-reruns | powershell | opus48-1m-medium-cli2.1.195 | 3 | 3.3min | 0.1% | $0.85 | 0.15% |
| fixture-rework | default | opus48-1m-xhigh-cli2.1.195 | 3 | 3.3min | 0.1% | $0.88 | 0.15% |
| repeated-test-reruns | powershell | opus48-1m-medium-cli2.1.193 | 4 | 4.3min | 0.2% | $1.04 | 0.18% |
| fixture-rework | typescript-bun | opus48-1m-ultracode-cli2.1.195 | 2 | 3.7min | 0.2% | $1.16 | 0.20% |
| fixture-rework | bash | opus48-1m-medium-cli2.1.195 | 1 | 5.0min | 0.2% | $1.19 | 0.21% |
| docker-pwsh-install | powershell | opus48-1m-ultracode-cli2.1.195 | 3 | 4.5min | 0.2% | $1.20 | 0.21% |
| repeated-test-reruns | bash | opus48-1m-ultracode-cli2.1.195 | 2 | 4.3min | 0.2% | $1.26 | 0.22% |
| mid-run-module-restructure | powershell | opus48-1m-ultracode-cli2.1.195 | 2 | 4.0min | 0.2% | $1.32 | 0.23% |
| fixture-rework | typescript-bun | opus48-1m-xhigh-cli2.1.195 | 3 | 4.7min | 0.2% | $1.32 | 0.23% |
| repeated-test-reruns | typescript-bun | opus48-1m-medium-cli2.1.195 | 3 | 6.7min | 0.3% | $1.54 | 0.27% |
| fixture-rework | bash | opus48-1m-xhigh-cli2.1.195 | 3 | 6.0min | 0.3% | $1.62 | 0.28% |
| repeated-test-reruns | bash | opus48-1m-high-cli2.1.195 | 4 | 7.3min | 0.3% | $2.04 | 0.35% |
| repeated-test-reruns | bash | opus48-1m-xhigh-cli2.1.195 | 5 | 8.0min | 0.4% | $2.34 | 0.41% |
| repeated-test-reruns | default | opus48-1m-high-cli2.1.195 | 4 | 8.0min | 0.4% | $2.44 | 0.42% |
| repeated-test-reruns | typescript-bun | opus48-1m-xhigh-cli2.1.195 | 5 | 9.3min | 0.4% | $2.65 | 0.46% |
| repeated-test-reruns | typescript-bun | opus48-1m-high-cli2.1.195 | 3 | 9.0min | 0.4% | $3.07 | 0.53% |
| repeated-test-reruns | default | opus48-1m-ultracode-cli2.1.195 | 8 | 18.0min | 0.8% | $5.17 | 0.89% |
| repeated-test-reruns | default | opus48-1m-xhigh-cli2.1.195 | 8 | 17.0min | 0.8% | $5.19 | 0.90% |
| repeated-test-reruns | typescript-bun | opus48-1m-ultracode-cli2.1.195 | 7 | 17.7min | 0.8% | $5.22 | 0.90% |
| repeated-test-reruns | powershell | opus48-1m-ultracode-cli2.1.195 | 11 | 21.7min | 1.0% | $6.04 | 1.05% |
| repeated-test-reruns | powershell | opus48-1m-high-cli2.1.195 | 12 | 26.7min | 1.2% | $6.14 | 1.06% |
| fixture-rework | bash | opus48-1m-high-cli2.1.195 | 4 | 22.0min | 1.0% | $6.20 | 1.07% |
| repeated-test-reruns | powershell | opus48-1m-xhigh-cli2.1.195 | 13 | 39.0min | 1.7% | $6.91 | 1.20% |

</details>

<details>
<summary>Sorted by fell-in count (fewest first)</summary>

| Trap | Language | Model | Fell In | Time Lost | % of Time | $ Lost | % of $ |
|------|------|-------|---------|-----------|-----------|--------|--------|
| repeated-test-reruns | bash | opus48-1m-medium-cli2.1.195 | 1 | 2.3min | 0.1% | $0.56 | 0.10% |
| repeated-test-reruns | default | opus48-1m-medium-cli2.1.193 | 1 | 1.3min | 0.1% | $0.31 | 0.05% |
| repeated-test-reruns | default | opus48-1m-medium-cli2.1.195 | 1 | 2.7min | 0.1% | $0.64 | 0.11% |
| fixture-rework | bash | opus48-1m-medium-cli2.1.195 | 1 | 5.0min | 0.2% | $1.19 | 0.21% |
| fixture-rework | bash | opus48-1m-ultracode-cli2.1.195 | 1 | 2.3min | 0.1% | $0.67 | 0.12% |
| fixture-rework | default | opus48-1m-high-cli2.1.195 | 1 | 2.0min | 0.1% | $0.52 | 0.09% |
| fixture-rework | powershell | opus48-1m-ultracode-cli2.1.195 | 1 | 0.7min | 0.0% | $0.16 | 0.03% |
| fixture-rework | typescript-bun | opus48-1m-high-cli2.1.195 | 1 | 0.7min | 0.0% | $0.18 | 0.03% |
| fixture-rework | typescript-bun | opus48-1m-medium-cli2.1.195 | 1 | 1.0min | 0.0% | $0.25 | 0.04% |
| bats-setup-issues | bash | opus48-1m-high-cli2.1.195 | 1 | 1.2min | 0.1% | $0.33 | 0.06% |
| actionlint-fix-cycles | powershell | opus48-1m-medium-cli2.1.193 | 1 | 1.0min | 0.0% | $0.27 | 0.05% |
| actionlint-fix-cycles | typescript-bun | opus48-1m-medium-cli2.1.195 | 1 | 0.7min | 0.0% | $0.13 | 0.02% |
| act-fixture-paths | bash | opus48-1m-ultracode-cli2.1.195 | 1 | 1.0min | 0.0% | $0.26 | 0.05% |
| act-push-debug-loops | powershell | opus48-1m-ultracode-cli2.1.195 | 1 | 0.8min | 0.0% | $0.23 | 0.04% |
| repeated-test-reruns | bash | opus48-1m-ultracode-cli2.1.195 | 2 | 4.3min | 0.2% | $1.26 | 0.22% |
| repeated-test-reruns | typescript-bun | opus48-1m-medium-cli2.1.193 | 2 | 2.0min | 0.1% | $0.47 | 0.08% |
| fixture-rework | bash | opus48-1m-medium-cli2.1.193 | 2 | 1.3min | 0.1% | $0.37 | 0.06% |
| fixture-rework | powershell | opus48-1m-medium-cli2.1.193 | 2 | 3.0min | 0.1% | $0.72 | 0.12% |
| fixture-rework | powershell | opus48-1m-xhigh-cli2.1.195 | 2 | 4.7min | 0.2% | $0.38 | 0.07% |
| fixture-rework | typescript-bun | opus48-1m-ultracode-cli2.1.195 | 2 | 3.7min | 0.2% | $1.16 | 0.20% |
| docker-pwsh-install | powershell | opus48-1m-xhigh-cli2.1.195 | 2 | 3.0min | 0.1% | $0.82 | 0.14% |
| mid-run-module-restructure | powershell | opus48-1m-ultracode-cli2.1.195 | 2 | 4.0min | 0.2% | $1.32 | 0.23% |
| bats-setup-issues | bash | opus48-1m-xhigh-cli2.1.195 | 2 | 1.8min | 0.1% | $0.51 | 0.09% |
| repeated-test-reruns | powershell | opus48-1m-medium-cli2.1.195 | 3 | 3.3min | 0.1% | $0.85 | 0.15% |
| repeated-test-reruns | typescript-bun | opus48-1m-high-cli2.1.195 | 3 | 9.0min | 0.4% | $3.07 | 0.53% |
| repeated-test-reruns | typescript-bun | opus48-1m-medium-cli2.1.195 | 3 | 6.7min | 0.3% | $1.54 | 0.27% |
| fixture-rework | bash | opus48-1m-xhigh-cli2.1.195 | 3 | 6.0min | 0.3% | $1.62 | 0.28% |
| fixture-rework | default | opus48-1m-xhigh-cli2.1.195 | 3 | 3.3min | 0.1% | $0.88 | 0.15% |
| fixture-rework | powershell | opus48-1m-high-cli2.1.195 | 3 | 3.3min | 0.1% | $0.72 | 0.12% |
| fixture-rework | typescript-bun | opus48-1m-xhigh-cli2.1.195 | 3 | 4.7min | 0.2% | $1.32 | 0.23% |
| docker-pwsh-install | powershell | opus48-1m-ultracode-cli2.1.195 | 3 | 4.5min | 0.2% | $1.20 | 0.21% |
| repeated-test-reruns | bash | opus48-1m-high-cli2.1.195 | 4 | 7.3min | 0.3% | $2.04 | 0.35% |
| repeated-test-reruns | default | opus48-1m-high-cli2.1.195 | 4 | 8.0min | 0.4% | $2.44 | 0.42% |
| repeated-test-reruns | powershell | opus48-1m-medium-cli2.1.193 | 4 | 4.3min | 0.2% | $1.04 | 0.18% |
| fixture-rework | bash | opus48-1m-high-cli2.1.195 | 4 | 22.0min | 1.0% | $6.20 | 1.07% |
| repeated-test-reruns | bash | opus48-1m-xhigh-cli2.1.195 | 5 | 8.0min | 0.4% | $2.34 | 0.41% |
| repeated-test-reruns | typescript-bun | opus48-1m-xhigh-cli2.1.195 | 5 | 9.3min | 0.4% | $2.65 | 0.46% |
| repeated-test-reruns | typescript-bun | opus48-1m-ultracode-cli2.1.195 | 7 | 17.7min | 0.8% | $5.22 | 0.90% |
| repeated-test-reruns | default | opus48-1m-ultracode-cli2.1.195 | 8 | 18.0min | 0.8% | $5.17 | 0.89% |
| repeated-test-reruns | default | opus48-1m-xhigh-cli2.1.195 | 8 | 17.0min | 0.8% | $5.19 | 0.90% |
| repeated-test-reruns | powershell | opus48-1m-ultracode-cli2.1.195 | 11 | 21.7min | 1.0% | $6.04 | 1.05% |
| repeated-test-reruns | powershell | opus48-1m-high-cli2.1.195 | 12 | 26.7min | 1.2% | $6.14 | 1.06% |
| repeated-test-reruns | powershell | opus48-1m-xhigh-cli2.1.195 | 13 | 39.0min | 1.7% | $6.91 | 1.20% |

</details>

#### Trap Descriptions

- **act-fixture-paths**: Test fixtures not found inside the act Docker container due to path issues.
- **act-push-debug-loops**: Agent ran `act push` more than twice, indicating repeated workflow debugging.
- **actionlint-fix-cycles**: Workflow YAML required 3+ actionlint runs and 2+ fixes to pass.
- **bats-setup-issues**: Agent struggled with bats-core test framework setup or load helpers.
- **docker-pwsh-install**: Multiple Docker test runs trying to figure out how to install PowerShell in act's container.
- **fixture-rework**: Agent rewrote or edited the same fixture file multiple times (genuine redo cycles, not one-time fixture creation).
- **mid-run-module-restructure**: Agent restructured from a flat .ps1 script to a .psm1 module mid-run.
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
| bash | opus48-1m-high-cli2.1.195 | 7 | 9 | 30.6min | 1.4% | $8.57 | 1.48% |
| bash | opus48-1m-medium-cli2.1.193 | 5 | 2 | 1.3min | 0.1% | $0.37 | 0.06% |
| bash | opus48-1m-medium-cli2.1.195 | 2 | 2 | 7.3min | 0.3% | $1.75 | 0.30% |
| bash | opus48-1m-ultracode-cli2.1.195 | 7 | 4 | 7.7min | 0.3% | $2.19 | 0.38% |
| bash | opus48-1m-xhigh-cli2.1.195 | 7 | 10 | 15.8min | 0.7% | $4.47 | 0.77% |
| default | opus48-1m-high-cli2.1.195 | 7 | 5 | 10.0min | 0.4% | $2.96 | 0.51% |
| default | opus48-1m-medium-cli2.1.193 | 5 | 1 | 1.3min | 0.1% | $0.31 | 0.05% |
| default | opus48-1m-medium-cli2.1.195 | 2 | 1 | 2.7min | 0.1% | $0.64 | 0.11% |
| default | opus48-1m-ultracode-cli2.1.195 | 7 | 8 | 18.0min | 0.8% | $5.17 | 0.89% |
| default | opus48-1m-xhigh-cli2.1.195 | 7 | 11 | 20.3min | 0.9% | $6.07 | 1.05% |
| powershell | opus48-1m-high-cli2.1.195 | 14 | 15 | 30.0min | 1.3% | $6.85 | 1.19% |
| powershell | opus48-1m-medium-cli2.1.193 | 9 | 7 | 8.3min | 0.4% | $2.02 | 0.35% |
| powershell | opus48-1m-medium-cli2.1.195 | 5 | 3 | 3.3min | 0.1% | $0.85 | 0.15% |
| powershell | opus48-1m-ultracode-cli2.1.195 | 14 | 18 | 31.7min | 1.4% | $8.96 | 1.55% |
| powershell | opus48-1m-xhigh-cli2.1.195 | 14 | 17 | 46.7min | 2.1% | $8.12 | 1.40% |
| typescript-bun | opus48-1m-high-cli2.1.195 | 7 | 4 | 9.7min | 0.4% | $3.25 | 0.56% |
| typescript-bun | opus48-1m-medium-cli2.1.193 | 4 | 2 | 2.0min | 0.1% | $0.47 | 0.08% |
| typescript-bun | opus48-1m-medium-cli2.1.195 | 3 | 5 | 8.3min | 0.4% | $1.93 | 0.33% |
| typescript-bun | opus48-1m-ultracode-cli2.1.195 | 7 | 9 | 21.3min | 1.0% | $6.38 | 1.10% |
| typescript-bun | opus48-1m-xhigh-cli2.1.195 | 7 | 8 | 14.0min | 0.6% | $3.97 | 0.69% |


<details>
<summary>Sorted by time lost (least first)</summary>

| Language | Model | Runs | Traps | Time Lost | % of Time | $ Lost | % of $ |
|------|-------|------|-------|-----------|-----------|--------|--------|
| bash | opus48-1m-medium-cli2.1.193 | 5 | 2 | 1.3min | 0.1% | $0.37 | 0.06% |
| default | opus48-1m-medium-cli2.1.193 | 5 | 1 | 1.3min | 0.1% | $0.31 | 0.05% |
| typescript-bun | opus48-1m-medium-cli2.1.193 | 4 | 2 | 2.0min | 0.1% | $0.47 | 0.08% |
| default | opus48-1m-medium-cli2.1.195 | 2 | 1 | 2.7min | 0.1% | $0.64 | 0.11% |
| powershell | opus48-1m-medium-cli2.1.195 | 5 | 3 | 3.3min | 0.1% | $0.85 | 0.15% |
| bash | opus48-1m-medium-cli2.1.195 | 2 | 2 | 7.3min | 0.3% | $1.75 | 0.30% |
| bash | opus48-1m-ultracode-cli2.1.195 | 7 | 4 | 7.7min | 0.3% | $2.19 | 0.38% |
| powershell | opus48-1m-medium-cli2.1.193 | 9 | 7 | 8.3min | 0.4% | $2.02 | 0.35% |
| typescript-bun | opus48-1m-medium-cli2.1.195 | 3 | 5 | 8.3min | 0.4% | $1.93 | 0.33% |
| typescript-bun | opus48-1m-high-cli2.1.195 | 7 | 4 | 9.7min | 0.4% | $3.25 | 0.56% |
| default | opus48-1m-high-cli2.1.195 | 7 | 5 | 10.0min | 0.4% | $2.96 | 0.51% |
| typescript-bun | opus48-1m-xhigh-cli2.1.195 | 7 | 8 | 14.0min | 0.6% | $3.97 | 0.69% |
| bash | opus48-1m-xhigh-cli2.1.195 | 7 | 10 | 15.8min | 0.7% | $4.47 | 0.77% |
| default | opus48-1m-ultracode-cli2.1.195 | 7 | 8 | 18.0min | 0.8% | $5.17 | 0.89% |
| default | opus48-1m-xhigh-cli2.1.195 | 7 | 11 | 20.3min | 0.9% | $6.07 | 1.05% |
| typescript-bun | opus48-1m-ultracode-cli2.1.195 | 7 | 9 | 21.3min | 1.0% | $6.38 | 1.10% |
| powershell | opus48-1m-high-cli2.1.195 | 14 | 15 | 30.0min | 1.3% | $6.85 | 1.19% |
| bash | opus48-1m-high-cli2.1.195 | 7 | 9 | 30.6min | 1.4% | $8.57 | 1.48% |
| powershell | opus48-1m-ultracode-cli2.1.195 | 14 | 18 | 31.7min | 1.4% | $8.96 | 1.55% |
| powershell | opus48-1m-xhigh-cli2.1.195 | 14 | 17 | 46.7min | 2.1% | $8.12 | 1.40% |

</details>

<details>
<summary>Sorted by $ lost (least first)</summary>

| Language | Model | Runs | Traps | Time Lost | % of Time | $ Lost | % of $ |
|------|-------|------|-------|-----------|-----------|--------|--------|
| default | opus48-1m-medium-cli2.1.193 | 5 | 1 | 1.3min | 0.1% | $0.31 | 0.05% |
| bash | opus48-1m-medium-cli2.1.193 | 5 | 2 | 1.3min | 0.1% | $0.37 | 0.06% |
| typescript-bun | opus48-1m-medium-cli2.1.193 | 4 | 2 | 2.0min | 0.1% | $0.47 | 0.08% |
| default | opus48-1m-medium-cli2.1.195 | 2 | 1 | 2.7min | 0.1% | $0.64 | 0.11% |
| powershell | opus48-1m-medium-cli2.1.195 | 5 | 3 | 3.3min | 0.1% | $0.85 | 0.15% |
| bash | opus48-1m-medium-cli2.1.195 | 2 | 2 | 7.3min | 0.3% | $1.75 | 0.30% |
| typescript-bun | opus48-1m-medium-cli2.1.195 | 3 | 5 | 8.3min | 0.4% | $1.93 | 0.33% |
| powershell | opus48-1m-medium-cli2.1.193 | 9 | 7 | 8.3min | 0.4% | $2.02 | 0.35% |
| bash | opus48-1m-ultracode-cli2.1.195 | 7 | 4 | 7.7min | 0.3% | $2.19 | 0.38% |
| default | opus48-1m-high-cli2.1.195 | 7 | 5 | 10.0min | 0.4% | $2.96 | 0.51% |
| typescript-bun | opus48-1m-high-cli2.1.195 | 7 | 4 | 9.7min | 0.4% | $3.25 | 0.56% |
| typescript-bun | opus48-1m-xhigh-cli2.1.195 | 7 | 8 | 14.0min | 0.6% | $3.97 | 0.69% |
| bash | opus48-1m-xhigh-cli2.1.195 | 7 | 10 | 15.8min | 0.7% | $4.47 | 0.77% |
| default | opus48-1m-ultracode-cli2.1.195 | 7 | 8 | 18.0min | 0.8% | $5.17 | 0.89% |
| default | opus48-1m-xhigh-cli2.1.195 | 7 | 11 | 20.3min | 0.9% | $6.07 | 1.05% |
| typescript-bun | opus48-1m-ultracode-cli2.1.195 | 7 | 9 | 21.3min | 1.0% | $6.38 | 1.10% |
| powershell | opus48-1m-high-cli2.1.195 | 14 | 15 | 30.0min | 1.3% | $6.85 | 1.19% |
| powershell | opus48-1m-xhigh-cli2.1.195 | 14 | 17 | 46.7min | 2.1% | $8.12 | 1.40% |
| bash | opus48-1m-high-cli2.1.195 | 7 | 9 | 30.6min | 1.4% | $8.57 | 1.48% |
| powershell | opus48-1m-ultracode-cli2.1.195 | 14 | 18 | 31.7min | 1.4% | $8.96 | 1.55% |

</details>

### Prompt Cache Savings

| Status | Runs | $ Saved | % of $ |
|--------|------|---------|--------|
| Full hit (100%) | 1 | $0.12 | 0.02% |
| Partial | 132 | $13.27 | 2.30% |
| Miss | 7 | $0.00 | 0.00% |

## Test Quality Evaluation

### Structural Metrics by Language/Model/Effort

Automated analysis of test files: test count, assertion count, and test-to-code line ratio.

| Language | Model | Avg Tests | Avg Assertions | Avg Assert/Test | Avg Test:Code Ratio |
|------|-------|-----------|----------------|-----------------|---------------------|
| bash | opus48-1m-high | 32.1 | 67.3 | 2.1 | 1.32 |
| bash | opus48-1m-medium | 22.4 | 39.0 | 1.7 | 1.19 |
| bash | opus48-1m-ultracode | 35.6 | 69.1 | 1.9 | 1.08 |
| bash | opus48-1m-xhigh | 30.6 | 76.4 | 2.5 | 1.00 |
| default | opus48-1m-high | 28.3 | 55.9 | 2.0 | 1.45 |
| default | opus48-1m-medium | 27.0 | 49.1 | 1.8 | 1.01 |
| default | opus48-1m-ultracode | 38.3 | 84.4 | 2.2 | 1.41 |
| default | opus48-1m-xhigh | 36.4 | 68.7 | 1.9 | 0.97 |
| powershell | opus48-1m-high | 42.4 | 79.3 | 1.9 | 4.36 |
| powershell | opus48-1m-medium | 32.8 | 59.9 | 1.8 | 3.52 |
| powershell | opus48-1m-ultracode | 52.4 | 93.3 | 1.8 | 4.02 |
| powershell | opus48-1m-xhigh | 48.9 | 92.9 | 1.9 | 3.45 |
| typescript-bun | opus48-1m-high | 40.3 | 87.3 | 2.2 | 1.02 |
| typescript-bun | opus48-1m-medium | 30.9 | 65.1 | 2.1 | 1.02 |
| typescript-bun | opus48-1m-ultracode | 55.1 | 107.7 | 2.0 | 1.18 |
| typescript-bun | opus48-1m-xhigh | 51.4 | 104.0 | 2.0 | 1.19 |


<details>
<summary>Sorted by avg tests (most first)</summary>

| Language | Model | Avg Tests | Avg Assertions | Avg Assert/Test | Avg Test:Code Ratio |
|------|-------|-----------|----------------|-----------------|---------------------|
| typescript-bun | opus48-1m-ultracode | 55.1 | 107.7 | 2.0 | 1.18 |
| powershell | opus48-1m-ultracode | 52.4 | 93.3 | 1.8 | 4.02 |
| typescript-bun | opus48-1m-xhigh | 51.4 | 104.0 | 2.0 | 1.19 |
| powershell | opus48-1m-xhigh | 48.9 | 92.9 | 1.9 | 3.45 |
| powershell | opus48-1m-high | 42.4 | 79.3 | 1.9 | 4.36 |
| typescript-bun | opus48-1m-high | 40.3 | 87.3 | 2.2 | 1.02 |
| default | opus48-1m-ultracode | 38.3 | 84.4 | 2.2 | 1.41 |
| default | opus48-1m-xhigh | 36.4 | 68.7 | 1.9 | 0.97 |
| bash | opus48-1m-ultracode | 35.6 | 69.1 | 1.9 | 1.08 |
| powershell | opus48-1m-medium | 32.8 | 59.9 | 1.8 | 3.52 |
| bash | opus48-1m-high | 32.1 | 67.3 | 2.1 | 1.32 |
| typescript-bun | opus48-1m-medium | 30.9 | 65.1 | 2.1 | 1.02 |
| bash | opus48-1m-xhigh | 30.6 | 76.4 | 2.5 | 1.00 |
| default | opus48-1m-high | 28.3 | 55.9 | 2.0 | 1.45 |
| default | opus48-1m-medium | 27.0 | 49.1 | 1.8 | 1.01 |
| bash | opus48-1m-medium | 22.4 | 39.0 | 1.7 | 1.19 |

</details>

<details>
<summary>Sorted by avg assertions (most first)</summary>

| Language | Model | Avg Tests | Avg Assertions | Avg Assert/Test | Avg Test:Code Ratio |
|------|-------|-----------|----------------|-----------------|---------------------|
| typescript-bun | opus48-1m-ultracode | 55.1 | 107.7 | 2.0 | 1.18 |
| typescript-bun | opus48-1m-xhigh | 51.4 | 104.0 | 2.0 | 1.19 |
| powershell | opus48-1m-ultracode | 52.4 | 93.3 | 1.8 | 4.02 |
| powershell | opus48-1m-xhigh | 48.9 | 92.9 | 1.9 | 3.45 |
| typescript-bun | opus48-1m-high | 40.3 | 87.3 | 2.2 | 1.02 |
| default | opus48-1m-ultracode | 38.3 | 84.4 | 2.2 | 1.41 |
| powershell | opus48-1m-high | 42.4 | 79.3 | 1.9 | 4.36 |
| bash | opus48-1m-xhigh | 30.6 | 76.4 | 2.5 | 1.00 |
| bash | opus48-1m-ultracode | 35.6 | 69.1 | 1.9 | 1.08 |
| default | opus48-1m-xhigh | 36.4 | 68.7 | 1.9 | 0.97 |
| bash | opus48-1m-high | 32.1 | 67.3 | 2.1 | 1.32 |
| typescript-bun | opus48-1m-medium | 30.9 | 65.1 | 2.1 | 1.02 |
| powershell | opus48-1m-medium | 32.8 | 59.9 | 1.8 | 3.52 |
| default | opus48-1m-high | 28.3 | 55.9 | 2.0 | 1.45 |
| default | opus48-1m-medium | 27.0 | 49.1 | 1.8 | 1.01 |
| bash | opus48-1m-medium | 22.4 | 39.0 | 1.7 | 1.19 |

</details>

<details>
<summary>Sorted by avg test:code ratio (highest first)</summary>

| Language | Model | Avg Tests | Avg Assertions | Avg Assert/Test | Avg Test:Code Ratio |
|------|-------|-----------|----------------|-----------------|---------------------|
| powershell | opus48-1m-high | 42.4 | 79.3 | 1.9 | 4.36 |
| powershell | opus48-1m-ultracode | 52.4 | 93.3 | 1.8 | 4.02 |
| powershell | opus48-1m-medium | 32.8 | 59.9 | 1.8 | 3.52 |
| powershell | opus48-1m-xhigh | 48.9 | 92.9 | 1.9 | 3.45 |
| default | opus48-1m-high | 28.3 | 55.9 | 2.0 | 1.45 |
| default | opus48-1m-ultracode | 38.3 | 84.4 | 2.2 | 1.41 |
| bash | opus48-1m-high | 32.1 | 67.3 | 2.1 | 1.32 |
| typescript-bun | opus48-1m-xhigh | 51.4 | 104.0 | 2.0 | 1.19 |
| bash | opus48-1m-medium | 22.4 | 39.0 | 1.7 | 1.19 |
| typescript-bun | opus48-1m-ultracode | 55.1 | 107.7 | 2.0 | 1.18 |
| bash | opus48-1m-ultracode | 35.6 | 69.1 | 1.9 | 1.08 |
| typescript-bun | opus48-1m-high | 40.3 | 87.3 | 2.2 | 1.02 |
| typescript-bun | opus48-1m-medium | 30.9 | 65.1 | 2.1 | 1.02 |
| default | opus48-1m-medium | 27.0 | 49.1 | 1.8 | 1.01 |
| bash | opus48-1m-xhigh | 30.6 | 76.4 | 2.5 | 1.00 |
| default | opus48-1m-xhigh | 36.4 | 68.7 | 1.9 | 0.97 |

</details>


<details>
<summary>Per-run structural metrics</summary>

| Task | Language | Model | Tests | Assertions | Assert/Test | Test Lines | Impl Lines | Test:Code |
|------|------|-------|-------|------------|-------------|------------|------------|-----------|
| Semantic Version Bumper | bash | opus48-1m-high | 36 | 54 | 1.5 | 346 | 467 | 0.74 |
| Semantic Version Bumper | bash | opus48-1m-medium | 24 | 34 | 1.4 | 286 | 275 | 1.04 |
| Semantic Version Bumper | bash | opus48-1m-ultracode | 67 | 106 | 1.6 | 632 | 457 | 1.38 |
| Semantic Version Bumper | bash | opus48-1m-xhigh | 19 | 28 | 1.5 | 238 | 277 | 0.86 |
| Semantic Version Bumper | default | opus48-1m-high | 38 | 66 | 1.7 | 330 | 364 | 0.91 |
| Semantic Version Bumper | default | opus48-1m-medium | 38 | 61 | 1.6 | 498 | 312 | 1.60 |
| Semantic Version Bumper | default | opus48-1m-ultracode | 49 | 74 | 1.5 | 536 | 469 | 1.14 |
| Semantic Version Bumper | default | opus48-1m-xhigh | 48 | 81 | 1.7 | 411 | 607 | 0.68 |
| Semantic Version Bumper | powershell | opus48-1m-high | 53 | 92 | 1.7 | 567 | 75 | 7.56 |
| Semantic Version Bumper | powershell | opus48-1m-medium | 39 | 62 | 1.6 | 359 | 53 | 6.77 |
| Semantic Version Bumper | powershell | opus48-1m-ultracode | 58 | 109 | 1.9 | 644 | 152 | 4.24 |
| Semantic Version Bumper | powershell | opus48-1m-xhigh | 51 | 74 | 1.5 | 414 | 349 | 1.19 |
| Semantic Version Bumper | powershell | opus48-1m-high | 40 | 69 | 1.7 | 360 | 585 | 0.62 |
| Semantic Version Bumper | powershell | opus48-1m-medium | 35 | 57 | 1.6 | 380 | 118 | 3.22 |
| Semantic Version Bumper | powershell | opus48-1m-ultracode | 45 | 85 | 1.9 | 532 | 127 | 4.19 |
| Semantic Version Bumper | powershell | opus48-1m-xhigh | 56 | 95 | 1.7 | 626 | 666 | 0.94 |
| Semantic Version Bumper | typescript-bun | opus48-1m-high | 51 | 104 | 2.0 | 568 | 475 | 1.20 |
| Semantic Version Bumper | typescript-bun | opus48-1m-medium | 38 | 76 | 2.0 | 462 | 558 | 0.83 |
| Semantic Version Bumper | typescript-bun | opus48-1m-ultracode | 73 | 135 | 1.8 | 963 | 605 | 1.59 |
| Semantic Version Bumper | typescript-bun | opus48-1m-xhigh | 68 | 148 | 2.2 | 1013 | 696 | 1.46 |
| PR Label Assigner | bash | opus48-1m-high | 43 | 84 | 2.0 | 506 | 232 | 2.18 |
| PR Label Assigner | bash | opus48-1m-medium | 18 | 10 | 0.6 | 171 | 198 | 0.86 |
| PR Label Assigner | bash | opus48-1m-ultracode | 35 | 64 | 1.8 | 414 | 455 | 0.91 |
| PR Label Assigner | bash | opus48-1m-xhigh | 28 | 64 | 2.3 | 401 | 219 | 1.83 |
| PR Label Assigner | default | opus48-1m-high | 28 | 42 | 1.5 | 266 | 444 | 0.60 |
| PR Label Assigner | default | opus48-1m-medium | 30 | 36 | 1.2 | 222 | 407 | 0.55 |
| PR Label Assigner | default | opus48-1m-ultracode | 40 | 73 | 1.8 | 462 | 491 | 0.94 |
| PR Label Assigner | default | opus48-1m-xhigh | 36 | 51 | 1.4 | 285 | 491 | 0.58 |
| PR Label Assigner | powershell | opus48-1m-high | 46 | 70 | 1.5 | 493 | 64 | 7.70 |
| PR Label Assigner | powershell | opus48-1m-medium | 32 | 47 | 1.5 | 261 | 393 | 0.66 |
| PR Label Assigner | powershell | opus48-1m-ultracode | 51 | 68 | 1.3 | 484 | 146 | 3.32 |
| PR Label Assigner | powershell | opus48-1m-xhigh | 57 | 70 | 1.2 | 394 | 241 | 1.63 |
| PR Label Assigner | powershell | opus48-1m-high | 38 | 57 | 1.5 | 443 | 82 | 5.40 |
| PR Label Assigner | powershell | opus48-1m-medium | 26 | 46 | 1.8 | 210 | 253 | 0.83 |
| PR Label Assigner | powershell | opus48-1m-ultracode | 49 | 65 | 1.3 | 537 | 81 | 6.63 |
| PR Label Assigner | powershell | opus48-1m-xhigh | 50 | 73 | 1.5 | 600 | 81 | 7.41 |
| PR Label Assigner | typescript-bun | opus48-1m-high | 29 | 43 | 1.5 | 307 | 474 | 0.65 |
| PR Label Assigner | typescript-bun | opus48-1m-medium | 25 | 53 | 2.1 | 362 | 372 | 0.97 |
| PR Label Assigner | typescript-bun | opus48-1m-ultracode | 46 | 70 | 1.5 | 428 | 623 | 0.69 |
| PR Label Assigner | typescript-bun | opus48-1m-xhigh | 47 | 72 | 1.5 | 471 | 808 | 0.58 |
| Dependency License Checker | bash | opus48-1m-high | 26 | 74 | 2.8 | 449 | 315 | 1.43 |
| Dependency License Checker | bash | opus48-1m-medium | 24 | 52 | 2.2 | 334 | 191 | 1.75 |
| Dependency License Checker | bash | opus48-1m-ultracode | 35 | 90 | 2.6 | 515 | 444 | 1.16 |
| Dependency License Checker | bash | opus48-1m-xhigh | 39 | 82 | 2.1 | 426 | 422 | 1.01 |
| Dependency License Checker | default | opus48-1m-high | 33 | 52 | 1.6 | 314 | 84 | 3.74 |
| Dependency License Checker | default | opus48-1m-medium | 19 | 37 | 1.9 | 212 | 433 | 0.49 |
| Dependency License Checker | default | opus48-1m-ultracode | 37 | 93 | 2.5 | 445 | 274 | 1.62 |
| Dependency License Checker | default | opus48-1m-xhigh | 28 | 53 | 1.9 | 384 | 555 | 0.69 |
| Dependency License Checker | powershell | opus48-1m-high | 54 | 79 | 1.5 | 521 | 111 | 4.69 |
| Dependency License Checker | powershell | opus48-1m-medium | 34 | 56 | 1.6 | 386 | 68 | 5.68 |
| Dependency License Checker | powershell | opus48-1m-ultracode | 72 | 107 | 1.5 | 639 | 117 | 5.46 |
| Dependency License Checker | powershell | opus48-1m-xhigh | 45 | 70 | 1.6 | 634 | 137 | 4.63 |
| Dependency License Checker | powershell | opus48-1m-high | 35 | 63 | 1.8 | 381 | 326 | 1.17 |
| Dependency License Checker | powershell | opus48-1m-medium | 32 | 53 | 1.7 | 388 | 60 | 6.47 |
| Dependency License Checker | powershell | opus48-1m-ultracode | 46 | 93 | 2.0 | 638 | 459 | 1.39 |
| Dependency License Checker | powershell | opus48-1m-xhigh | 47 | 87 | 1.9 | 503 | 480 | 1.05 |
| Dependency License Checker | typescript-bun | opus48-1m-high | 40 | 106 | 2.6 | 732 | 511 | 1.43 |
| Dependency License Checker | typescript-bun | opus48-1m-medium | 32 | 76 | 2.4 | 548 | 358 | 1.53 |
| Dependency License Checker | typescript-bun | opus48-1m-ultracode | 35 | 78 | 2.2 | 638 | 456 | 1.40 |
| Dependency License Checker | typescript-bun | opus48-1m-xhigh | 39 | 56 | 1.4 | 596 | 441 | 1.35 |
| Test Results Aggregator | bash | opus48-1m-high | 20 | 63 | 3.1 | 286 | 275 | 1.04 |
| Test Results Aggregator | bash | opus48-1m-medium | 25 | 26 | 1.0 | 221 | 291 | 0.76 |
| Test Results Aggregator | bash | opus48-1m-ultracode | 12 | 44 | 3.7 | 182 | 395 | 0.46 |
| Test Results Aggregator | bash | opus48-1m-xhigh | 32 | 62 | 1.9 | 292 | 580 | 0.50 |
| Test Results Aggregator | default | opus48-1m-high | 21 | 67 | 3.2 | 451 | 450 | 1.00 |
| Test Results Aggregator | default | opus48-1m-medium | 23 | 63 | 2.7 | 493 | 263 | 1.87 |
| Test Results Aggregator | default | opus48-1m-ultracode | 28 | 73 | 2.6 | 499 | 442 | 1.13 |
| Test Results Aggregator | default | opus48-1m-xhigh | 26 | 66 | 2.5 | 514 | 483 | 1.06 |
| Test Results Aggregator | powershell | opus48-1m-high | 38 | 91 | 2.4 | 527 | 72 | 7.32 |
| Test Results Aggregator | powershell | opus48-1m-medium | 29 | 52 | 1.8 | 250 | 253 | 0.99 |
| Test Results Aggregator | powershell | opus48-1m-ultracode | 62 | 82 | 1.3 | 411 | 588 | 0.70 |
| Test Results Aggregator | powershell | opus48-1m-xhigh | 59 | 108 | 1.8 | 489 | 95 | 5.15 |
| Test Results Aggregator | powershell | opus48-1m-high | 38 | 85 | 2.2 | 584 | 92 | 6.35 |
| Test Results Aggregator | powershell | opus48-1m-medium | 31 | 58 | 1.9 | 269 | 568 | 0.47 |
| Test Results Aggregator | powershell | opus48-1m-ultracode | 43 | 86 | 2.0 | 526 | 82 | 6.41 |
| Test Results Aggregator | powershell | opus48-1m-xhigh | 50 | 102 | 2.0 | 732 | 100 | 7.32 |
| Test Results Aggregator | typescript-bun | opus48-1m-high | 49 | 98 | 2.0 | 550 | 971 | 0.57 |
| Test Results Aggregator | typescript-bun | opus48-1m-medium | 34 | 57 | 1.7 | 408 | 707 | 0.58 |
| Test Results Aggregator | typescript-bun | opus48-1m-ultracode | 49 | 116 | 2.4 | 967 | 934 | 1.04 |
| Test Results Aggregator | typescript-bun | opus48-1m-xhigh | 50 | 111 | 2.2 | 756 | 576 | 1.31 |
| Environment Matrix Generator | bash | opus48-1m-high | 31 | 63 | 2.0 | 306 | 159 | 1.92 |
| Environment Matrix Generator | bash | opus48-1m-medium | 22 | 34 | 1.5 | 278 | 132 | 2.11 |
| Environment Matrix Generator | bash | opus48-1m-ultracode | 30 | 34 | 1.1 | 367 | 243 | 1.51 |
| Environment Matrix Generator | bash | opus48-1m-xhigh | 18 | 23 | 1.3 | 213 | 429 | 0.50 |
| Environment Matrix Generator | default | opus48-1m-high | 27 | 49 | 1.8 | 435 | 270 | 1.61 |
| Environment Matrix Generator | default | opus48-1m-medium | 26 | 50 | 1.9 | 350 | 356 | 0.98 |
| Environment Matrix Generator | default | opus48-1m-ultracode | 41 | 90 | 2.2 | 707 | 340 | 2.08 |
| Environment Matrix Generator | default | opus48-1m-xhigh | 33 | 58 | 1.8 | 583 | 374 | 1.56 |
| Environment Matrix Generator | powershell | opus48-1m-high | 51 | 101 | 2.0 | 510 | 72 | 7.08 |
| Environment Matrix Generator | powershell | opus48-1m-medium | 31 | 71 | 2.3 | 419 | 389 | 1.08 |
| Environment Matrix Generator | powershell | opus48-1m-ultracode | 54 | 91 | 1.7 | 567 | 109 | 5.20 |
| Environment Matrix Generator | powershell | opus48-1m-xhigh | 34 | 74 | 2.2 | 358 | 316 | 1.13 |
| Environment Matrix Generator | powershell | opus48-1m-high | 55 | 106 | 1.9 | 669 | 256 | 2.61 |
| Environment Matrix Generator | powershell | opus48-1m-medium | 31 | 57 | 1.8 | 352 | 36 | 9.78 |
| Environment Matrix Generator | powershell | opus48-1m-ultracode | 47 | 114 | 2.4 | 494 | 73 | 6.77 |
| Environment Matrix Generator | powershell | opus48-1m-xhigh | 55 | 146 | 2.7 | 673 | 395 | 1.70 |
| Environment Matrix Generator | typescript-bun | opus48-1m-high | 38 | 83 | 2.2 | 568 | 393 | 1.45 |
| Environment Matrix Generator | typescript-bun | opus48-1m-medium | 29 | 55 | 1.9 | 547 | 262 | 2.09 |
| Environment Matrix Generator | typescript-bun | opus48-1m-ultracode | 49 | 91 | 1.9 | 739 | 465 | 1.59 |
| Environment Matrix Generator | typescript-bun | opus48-1m-xhigh | 62 | 101 | 1.6 | 985 | 587 | 1.68 |
| Artifact Cleanup Script | bash | opus48-1m-high | 23 | 43 | 1.9 | 278 | 292 | 0.95 |
| Artifact Cleanup Script | bash | opus48-1m-medium | 17 | 55 | 3.2 | 304 | 258 | 1.18 |
| Artifact Cleanup Script | bash | opus48-1m-ultracode | 21 | 13 | 0.6 | 211 | 411 | 0.51 |
| Artifact Cleanup Script | bash | opus48-1m-xhigh | 34 | 144 | 4.2 | 502 | 511 | 0.98 |
| Artifact Cleanup Script | default | opus48-1m-high | 24 | 57 | 2.4 | 369 | 505 | 0.73 |
| Artifact Cleanup Script | default | opus48-1m-medium | 28 | 54 | 1.9 | 253 | 263 | 0.96 |
| Artifact Cleanup Script | default | opus48-1m-ultracode | 34 | 102 | 3.0 | 628 | 508 | 1.24 |
| Artifact Cleanup Script | default | opus48-1m-xhigh | 36 | 77 | 2.1 | 613 | 450 | 1.36 |
| Artifact Cleanup Script | powershell | opus48-1m-high | 25 | 55 | 2.2 | 339 | 420 | 0.81 |
| Artifact Cleanup Script | powershell | opus48-1m-medium | 25 | 62 | 2.5 | 328 | 292 | 1.12 |
| Artifact Cleanup Script | powershell | opus48-1m-ultracode | 33 | 80 | 2.4 | 525 | 161 | 3.26 |
| Artifact Cleanup Script | powershell | opus48-1m-xhigh | 42 | 100 | 2.4 | 577 | 73 | 7.90 |
| Artifact Cleanup Script | powershell | opus48-1m-high | 38 | 79 | 2.1 | 442 | 89 | 4.97 |
| Artifact Cleanup Script | powershell | opus48-1m-medium | 25 | 48 | 1.9 | 369 | 155 | 2.38 |
| Artifact Cleanup Script | powershell | opus48-1m-ultracode | 62 | 120 | 1.9 | 672 | 261 | 2.57 |
| Artifact Cleanup Script | powershell | opus48-1m-xhigh | 37 | 95 | 2.6 | 523 | 320 | 1.63 |
| Artifact Cleanup Script | typescript-bun | opus48-1m-high | 33 | 80 | 2.4 | 406 | 622 | 0.65 |
| Artifact Cleanup Script | typescript-bun | opus48-1m-medium | 23 | 53 | 2.3 | 273 | 525 | 0.52 |
| Artifact Cleanup Script | typescript-bun | opus48-1m-ultracode | 53 | 99 | 1.9 | 637 | 645 | 0.99 |
| Artifact Cleanup Script | typescript-bun | opus48-1m-xhigh | 29 | 69 | 2.4 | 580 | 585 | 0.99 |
| Secret Rotation Validator | bash | opus48-1m-high | 46 | 90 | 2.0 | 449 | 472 | 0.95 |
| Secret Rotation Validator | bash | opus48-1m-medium | 27 | 62 | 2.3 | 229 | 372 | 0.62 |
| Secret Rotation Validator | bash | opus48-1m-ultracode | 49 | 133 | 2.7 | 541 | 328 | 1.65 |
| Secret Rotation Validator | bash | opus48-1m-xhigh | 44 | 132 | 3.0 | 503 | 372 | 1.35 |
| Secret Rotation Validator | default | opus48-1m-high | 27 | 58 | 2.1 | 453 | 290 | 1.56 |
| Secret Rotation Validator | default | opus48-1m-medium | 25 | 43 | 1.7 | 261 | 404 | 0.65 |
| Secret Rotation Validator | default | opus48-1m-ultracode | 39 | 86 | 2.2 | 593 | 343 | 1.73 |
| Secret Rotation Validator | default | opus48-1m-xhigh | 48 | 95 | 2.0 | 562 | 653 | 0.86 |
| Secret Rotation Validator | powershell | opus48-1m-high | 46 | 89 | 1.9 | 414 | 264 | 1.57 |
| Secret Rotation Validator | powershell | opus48-1m-medium | 46 | 91 | 2.0 | 446 | 299 | 1.49 |
| Secret Rotation Validator | powershell | opus48-1m-ultracode | 65 | 121 | 1.9 | 662 | 521 | 1.27 |
| Secret Rotation Validator | powershell | opus48-1m-xhigh | 44 | 78 | 1.8 | 557 | 107 | 5.21 |
| Secret Rotation Validator | powershell | opus48-1m-high | 37 | 74 | 2.0 | 476 | 151 | 3.15 |
| Secret Rotation Validator | powershell | opus48-1m-medium | 43 | 78 | 1.8 | 481 | 58 | 8.29 |
| Secret Rotation Validator | powershell | opus48-1m-ultracode | 47 | 85 | 1.8 | 638 | 132 | 4.83 |
| Secret Rotation Validator | powershell | opus48-1m-xhigh | 58 | 129 | 2.2 | 526 | 360 | 1.46 |
| Secret Rotation Validator | typescript-bun | opus48-1m-high | 42 | 97 | 2.3 | 699 | 571 | 1.22 |
| Secret Rotation Validator | typescript-bun | opus48-1m-medium | 35 | 86 | 2.5 | 435 | 701 | 0.62 |
| Secret Rotation Validator | typescript-bun | opus48-1m-ultracode | 81 | 165 | 2.0 | 796 | 802 | 0.99 |
| Secret Rotation Validator | typescript-bun | opus48-1m-xhigh | 65 | 171 | 2.6 | 800 | 810 | 0.99 |

</details>

### LLM-as-Judge Scores

An LLM evaluates each test suite on four dimensions (1-5 scale):

- **Coverage** (1-5): Do tests exercise the key requirements? 1 = most untested, 5 = all covered.
- **Rigor** (1-5): Edge cases, error handling, boundary conditions? 1 = happy path only, 5 = thorough.
- **Design** (1-5): Test organization, fixtures, readability? 1 = messy/brittle, 5 = well-structured.
- **Overall** (1-5): Holistic quality — would you trust this suite to catch regressions? 1 = no, 5 = absolutely. Use this as the primary ranking metric.

| Language | Model | Avg Overall | Avg Coverage | Avg Rigor | Avg Design | Judge Cost |
|------|-------|-------------|-------------|-----------|------------|------------|
| bash | opus48-1m-high | **4.3** | 4.4 | 4.3 | 4.3 | $0.4582 |
| bash | opus48-1m-medium | **3.3** | 3.5 | 3.0 | 3.7 | $0.4194 |
| bash | opus48-1m-ultracode | **3.9** | 4.2 | 3.7 | 4.1 | $0.3707 |
| bash | opus48-1m-xhigh | **4.1** | 4.4 | 4.0 | 4.4 | $0.3896 |
| default | opus48-1m-high | **3.4** | 3.5 | 3.8 | 4.0 | $0.4080 |
| default | opus48-1m-medium | **4.1** | 4.2 | 4.3 | 4.3 | $0.4131 |
| default | opus48-1m-ultracode | **4.6** | 4.9 | 4.6 | 4.7 | $0.5519 |
| default | opus48-1m-xhigh | **4.4** | 4.6 | 4.3 | 4.5 | $0.4501 |
| powershell | opus48-1m-high | **4.5** | 4.6 | 4.4 | 4.5 | $0.8947 |
| powershell | opus48-1m-medium | **4.2** | 4.4 | 4.2 | 4.3 | $0.9008 |
| powershell | opus48-1m-ultracode | **4.5** | 4.6 | 4.5 | 4.5 | $0.9778 |
| powershell | opus48-1m-xhigh | **4.4** | 4.5 | 4.4 | 4.5 | $1.0629 |
| typescript-bun | opus48-1m-high | **4.3** | 4.4 | 4.3 | 4.4 | $0.5102 |
| typescript-bun | opus48-1m-medium | **4.4** | 4.4 | 4.3 | 4.5 | $0.4315 |
| typescript-bun | opus48-1m-ultracode | **4.5** | 4.6 | 4.5 | 4.6 | $0.5519 |
| typescript-bun | opus48-1m-xhigh | **4.4** | 4.6 | 4.4 | 4.4 | $0.5334 |
| **Total** | | | | | | **$9.3242** |


<details>
<summary>Sorted by avg overall (highest first)</summary>

| Language | Model | Avg Overall | Avg Coverage | Avg Rigor | Avg Design | Judge Cost |
|------|-------|-------------|-------------|-----------|------------|------------|
| default | opus48-1m-ultracode | **4.6** | 4.9 | 4.6 | 4.7 | $0.5519 |
| typescript-bun | opus48-1m-ultracode | **4.5** | 4.6 | 4.5 | 4.6 | $0.5519 |
| powershell | opus48-1m-high | **4.5** | 4.6 | 4.4 | 4.5 | $0.8947 |
| powershell | opus48-1m-ultracode | **4.5** | 4.6 | 4.5 | 4.5 | $0.9778 |
| powershell | opus48-1m-xhigh | **4.4** | 4.5 | 4.4 | 4.5 | $1.0629 |
| default | opus48-1m-xhigh | **4.4** | 4.6 | 4.3 | 4.5 | $0.4501 |
| typescript-bun | opus48-1m-medium | **4.4** | 4.4 | 4.3 | 4.5 | $0.4315 |
| typescript-bun | opus48-1m-xhigh | **4.4** | 4.6 | 4.4 | 4.4 | $0.5334 |
| bash | opus48-1m-high | **4.3** | 4.4 | 4.3 | 4.3 | $0.4582 |
| typescript-bun | opus48-1m-high | **4.3** | 4.4 | 4.3 | 4.4 | $0.5102 |
| powershell | opus48-1m-medium | **4.2** | 4.4 | 4.2 | 4.3 | $0.9008 |
| default | opus48-1m-medium | **4.1** | 4.2 | 4.3 | 4.3 | $0.4131 |
| bash | opus48-1m-xhigh | **4.1** | 4.4 | 4.0 | 4.4 | $0.3896 |
| bash | opus48-1m-ultracode | **3.9** | 4.2 | 3.7 | 4.1 | $0.3707 |
| default | opus48-1m-high | **3.4** | 3.5 | 3.8 | 4.0 | $0.4080 |
| bash | opus48-1m-medium | **3.3** | 3.5 | 3.0 | 3.7 | $0.4194 |

</details>

<details>
<summary>Sorted by avg coverage (highest first)</summary>

| Language | Model | Avg Overall | Avg Coverage | Avg Rigor | Avg Design | Judge Cost |
|------|-------|-------------|-------------|-----------|------------|------------|
| default | opus48-1m-ultracode | **4.6** | 4.9 | 4.6 | 4.7 | $0.5519 |
| powershell | opus48-1m-ultracode | **4.5** | 4.6 | 4.5 | 4.5 | $0.9778 |
| typescript-bun | opus48-1m-xhigh | **4.4** | 4.6 | 4.4 | 4.4 | $0.5334 |
| default | opus48-1m-xhigh | **4.4** | 4.6 | 4.3 | 4.5 | $0.4501 |
| powershell | opus48-1m-high | **4.5** | 4.6 | 4.4 | 4.5 | $0.8947 |
| typescript-bun | opus48-1m-ultracode | **4.5** | 4.6 | 4.5 | 4.6 | $0.5519 |
| powershell | opus48-1m-xhigh | **4.4** | 4.5 | 4.4 | 4.5 | $1.0629 |
| bash | opus48-1m-high | **4.3** | 4.4 | 4.3 | 4.3 | $0.4582 |
| bash | opus48-1m-xhigh | **4.1** | 4.4 | 4.0 | 4.4 | $0.3896 |
| typescript-bun | opus48-1m-high | **4.3** | 4.4 | 4.3 | 4.4 | $0.5102 |
| typescript-bun | opus48-1m-medium | **4.4** | 4.4 | 4.3 | 4.5 | $0.4315 |
| powershell | opus48-1m-medium | **4.2** | 4.4 | 4.2 | 4.3 | $0.9008 |
| bash | opus48-1m-ultracode | **3.9** | 4.2 | 3.7 | 4.1 | $0.3707 |
| default | opus48-1m-medium | **4.1** | 4.2 | 4.3 | 4.3 | $0.4131 |
| bash | opus48-1m-medium | **3.3** | 3.5 | 3.0 | 3.7 | $0.4194 |
| default | opus48-1m-high | **3.4** | 3.5 | 3.8 | 4.0 | $0.4080 |

</details>

<details>
<summary>Sorted by avg rigor (highest first)</summary>

| Language | Model | Avg Overall | Avg Coverage | Avg Rigor | Avg Design | Judge Cost |
|------|-------|-------------|-------------|-----------|------------|------------|
| default | opus48-1m-ultracode | **4.6** | 4.9 | 4.6 | 4.7 | $0.5519 |
| typescript-bun | opus48-1m-ultracode | **4.5** | 4.6 | 4.5 | 4.6 | $0.5519 |
| powershell | opus48-1m-ultracode | **4.5** | 4.6 | 4.5 | 4.5 | $0.9778 |
| powershell | opus48-1m-high | **4.5** | 4.6 | 4.4 | 4.5 | $0.8947 |
| typescript-bun | opus48-1m-xhigh | **4.4** | 4.6 | 4.4 | 4.4 | $0.5334 |
| powershell | opus48-1m-xhigh | **4.4** | 4.5 | 4.4 | 4.5 | $1.0629 |
| bash | opus48-1m-high | **4.3** | 4.4 | 4.3 | 4.3 | $0.4582 |
| default | opus48-1m-medium | **4.1** | 4.2 | 4.3 | 4.3 | $0.4131 |
| default | opus48-1m-xhigh | **4.4** | 4.6 | 4.3 | 4.5 | $0.4501 |
| typescript-bun | opus48-1m-high | **4.3** | 4.4 | 4.3 | 4.4 | $0.5102 |
| typescript-bun | opus48-1m-medium | **4.4** | 4.4 | 4.3 | 4.5 | $0.4315 |
| powershell | opus48-1m-medium | **4.2** | 4.4 | 4.2 | 4.3 | $0.9008 |
| bash | opus48-1m-xhigh | **4.1** | 4.4 | 4.0 | 4.4 | $0.3896 |
| default | opus48-1m-high | **3.4** | 3.5 | 3.8 | 4.0 | $0.4080 |
| bash | opus48-1m-ultracode | **3.9** | 4.2 | 3.7 | 4.1 | $0.3707 |
| bash | opus48-1m-medium | **3.3** | 3.5 | 3.0 | 3.7 | $0.4194 |

</details>

<details>
<summary>Sorted by avg design (highest first)</summary>

| Language | Model | Avg Overall | Avg Coverage | Avg Rigor | Avg Design | Judge Cost |
|------|-------|-------------|-------------|-----------|------------|------------|
| default | opus48-1m-ultracode | **4.6** | 4.9 | 4.6 | 4.7 | $0.5519 |
| typescript-bun | opus48-1m-ultracode | **4.5** | 4.6 | 4.5 | 4.6 | $0.5519 |
| powershell | opus48-1m-ultracode | **4.5** | 4.6 | 4.5 | 4.5 | $0.9778 |
| default | opus48-1m-xhigh | **4.4** | 4.6 | 4.3 | 4.5 | $0.4501 |
| powershell | opus48-1m-xhigh | **4.4** | 4.5 | 4.4 | 4.5 | $1.0629 |
| typescript-bun | opus48-1m-medium | **4.4** | 4.4 | 4.3 | 4.5 | $0.4315 |
| powershell | opus48-1m-high | **4.5** | 4.6 | 4.4 | 4.5 | $0.8947 |
| typescript-bun | opus48-1m-high | **4.3** | 4.4 | 4.3 | 4.4 | $0.5102 |
| bash | opus48-1m-xhigh | **4.1** | 4.4 | 4.0 | 4.4 | $0.3896 |
| typescript-bun | opus48-1m-xhigh | **4.4** | 4.6 | 4.4 | 4.4 | $0.5334 |
| powershell | opus48-1m-medium | **4.2** | 4.4 | 4.2 | 4.3 | $0.9008 |
| bash | opus48-1m-high | **4.3** | 4.4 | 4.3 | 4.3 | $0.4582 |
| default | opus48-1m-medium | **4.1** | 4.2 | 4.3 | 4.3 | $0.4131 |
| bash | opus48-1m-ultracode | **3.9** | 4.2 | 3.7 | 4.1 | $0.3707 |
| default | opus48-1m-high | **3.4** | 3.5 | 3.8 | 4.0 | $0.4080 |
| bash | opus48-1m-medium | **3.3** | 3.5 | 3.0 | 3.7 | $0.4194 |

</details>


<details>
<summary>Per-run LLM judge scores</summary>

| Task | Language | Model | Cov | Rig | Des | Ovr | Summary |
|------|------|-------|-----|-----|-----|-----|---------|
| Semantic Version Bumper | bash | opus48-1m-high | 4.5 | 4.0 | 4.5 | 4.5 |  |
| Semantic Version Bumper | bash | opus48-1m-medium | 4.0 | 4.0 | 4.0 | 4.0 |  |
| Semantic Version Bumper | bash | opus48-1m-ultracode | 4.5 | 4.5 | 4.5 | 4.5 |  |
| Semantic Version Bumper | bash | opus48-1m-xhigh | 3.0 | 2.0 | 4.0 | 3.0 |  |
| Semantic Version Bumper | default | opus48-1m-high | 2.0 | 3.5 | 3.5 | 2.0 |  |
| Semantic Version Bumper | default | opus48-1m-medium | 4.5 | 4.5 | 4.5 | 4.5 |  |
| Semantic Version Bumper | default | opus48-1m-ultracode | 5.0 | 4.5 | 4.5 | 4.5 |  |
| Semantic Version Bumper | default | opus48-1m-xhigh | 5.0 | 4.5 | 5.0 | 4.5 |  |
| Semantic Version Bumper | powershell | opus48-1m-high | 4.5 | 4.5 | 4.0 | 4.5 |  |
| Semantic Version Bumper | powershell | opus48-1m-medium | 4.5 | 4.5 | 4.0 | 4.0 |  |
| Semantic Version Bumper | powershell | opus48-1m-ultracode | 5.0 | 4.5 | 4.5 | 4.5 |  |
| Semantic Version Bumper | powershell | opus48-1m-xhigh | 4.5 | 4.5 | 4.5 | 4.5 |  |
| Semantic Version Bumper | powershell | opus48-1m-high | 4.5 | 4.5 | 4.5 | 4.5 |  |
| Semantic Version Bumper | powershell | opus48-1m-medium | 4.5 | 4.5 | 4.5 | 4.5 |  |
| Semantic Version Bumper | powershell | opus48-1m-ultracode | 4.5 | 4.0 | 4.5 | 4.5 |  |
| Semantic Version Bumper | powershell | opus48-1m-xhigh | 4.5 | 4.0 | 4.5 | 4.5 |  |
| Semantic Version Bumper | typescript-bun | opus48-1m-high | 4.0 | 4.0 | 4.0 | 4.0 |  |
| Semantic Version Bumper | typescript-bun | opus48-1m-medium | 4.5 | 4.5 | 4.5 | 4.5 |  |
| Semantic Version Bumper | typescript-bun | opus48-1m-ultracode | 4.5 | 4.5 | 4.5 | 4.5 |  |
| Semantic Version Bumper | typescript-bun | opus48-1m-xhigh | 4.5 | 4.5 | 4.5 | 4.5 |  |
| PR Label Assigner | bash | opus48-1m-high | 4.5 | 4.5 | 4.5 | 4.5 |  |
| PR Label Assigner | bash | opus48-1m-medium | 2.0 | 1.0 | 3.5 | 2.0 |  |
| PR Label Assigner | bash | opus48-1m-ultracode | 4.5 | 4.0 | 4.5 | 4.5 |  |
| PR Label Assigner | bash | opus48-1m-xhigh | 5.0 | 4.5 | 4.5 | 4.5 |  |
| PR Label Assigner | default | opus48-1m-high | 4.0 | 4.0 | 4.5 | 4.0 |  |
| PR Label Assigner | default | opus48-1m-medium | 4.0 | 4.0 | 4.5 | 4.0 |  |
| PR Label Assigner | default | opus48-1m-ultracode | 4.5 | 4.0 | 4.5 | 4.0 |  |
| PR Label Assigner | default | opus48-1m-xhigh | 4.5 | 4.5 | 4.5 | 4.5 |  |
| PR Label Assigner | powershell | opus48-1m-high | 4.5 | 4.0 | 4.5 | 4.5 |  |
| PR Label Assigner | powershell | opus48-1m-medium | 4.5 | 4.5 | 4.5 | 4.5 |  |
| PR Label Assigner | powershell | opus48-1m-ultracode | 4.5 | 4.5 | 4.5 | 4.5 |  |
| PR Label Assigner | powershell | opus48-1m-xhigh | 4.5 | 4.5 | 4.5 | 4.5 |  |
| PR Label Assigner | powershell | opus48-1m-high | 4.5 | 4.0 | 4.5 | 4.0 |  |
| PR Label Assigner | powershell | opus48-1m-medium | 4.5 | 4.0 | 4.5 | 4.5 |  |
| PR Label Assigner | powershell | opus48-1m-ultracode | 4.5 | 4.5 | 5.0 | 4.5 |  |
| PR Label Assigner | powershell | opus48-1m-xhigh | 4.5 | 4.5 | 4.5 | 4.5 |  |
| PR Label Assigner | typescript-bun | opus48-1m-high | 4.5 | 4.0 | 4.5 | 4.0 |  |
| PR Label Assigner | typescript-bun | opus48-1m-medium | 4.5 | 4.0 | 4.5 | 4.5 |  |
| PR Label Assigner | typescript-bun | opus48-1m-ultracode | 4.5 | 4.5 | 4.5 | 4.5 |  |
| PR Label Assigner | typescript-bun | opus48-1m-xhigh | 3.5 | 4.0 | 3.5 | 3.5 |  |
| Dependency License Checker | bash | opus48-1m-high | 4.5 | 4.5 | 4.5 | 4.5 |  |
| Dependency License Checker | bash | opus48-1m-medium | 4.5 | 3.5 | 4.0 | 4.0 |  |
| Dependency License Checker | bash | opus48-1m-ultracode | 4.5 | 4.0 | 4.0 | 4.0 |  |
| Dependency License Checker | bash | opus48-1m-xhigh | 5.0 | 4.5 | 3.5 | 3.5 |  |
| Dependency License Checker | default | opus48-1m-high | 2.0 | 3.5 | 3.0 | 2.0 |  |
| Dependency License Checker | default | opus48-1m-medium | 4.5 | 4.5 | 4.5 | 4.5 |  |
| Dependency License Checker | default | opus48-1m-ultracode | 5.0 | 4.5 | 4.5 | 4.5 |  |
| Dependency License Checker | default | opus48-1m-xhigh | 5.0 | 4.5 | 4.5 | 4.5 |  |
| Dependency License Checker | powershell | opus48-1m-high | 4.5 | 4.0 | 4.5 | 4.5 |  |
| Dependency License Checker | powershell | opus48-1m-medium | 4.5 | 4.0 | 4.5 | 4.0 |  |
| Dependency License Checker | powershell | opus48-1m-ultracode | 5.0 | 4.5 | 4.5 | 4.5 |  |
| Dependency License Checker | powershell | opus48-1m-xhigh | 4.5 | 4.5 | 5.0 | 4.5 |  |
| Dependency License Checker | powershell | opus48-1m-high | 5.0 | 4.5 | 4.5 | 4.5 |  |
| Dependency License Checker | powershell | opus48-1m-medium | 3.5 | 3.5 | 4.0 | 3.5 |  |
| Dependency License Checker | powershell | opus48-1m-ultracode | 4.5 | 4.5 | 4.5 | 4.5 |  |
| Dependency License Checker | powershell | opus48-1m-xhigh | 4.5 | 4.0 | 4.0 | 4.5 |  |
| Dependency License Checker | typescript-bun | opus48-1m-high | 4.5 | 4.5 | 4.5 | 4.5 |  |
| Dependency License Checker | typescript-bun | opus48-1m-medium | 4.0 | 4.0 | 4.5 | 4.0 |  |
| Dependency License Checker | typescript-bun | opus48-1m-ultracode | 4.5 | 4.0 | 4.5 | 4.0 |  |
| Dependency License Checker | typescript-bun | opus48-1m-xhigh | 5.0 | 4.5 | 4.5 | 4.5 |  |
| Test Results Aggregator | bash | opus48-1m-high | 3.0 | 3.0 | 2.5 | 2.5 |  |
| Test Results Aggregator | bash | opus48-1m-medium | 3.0 | 1.5 | 3.5 | 3.0 |  |
| Test Results Aggregator | bash | opus48-1m-ultracode | 3.0 | 2.5 | 3.0 | 3.0 |  |
| Test Results Aggregator | bash | opus48-1m-xhigh | 4.5 | 4.0 | 4.5 | 4.5 |  |
| Test Results Aggregator | default | opus48-1m-high | 4.0 | 3.5 | 4.5 | 4.0 |  |
| Test Results Aggregator | default | opus48-1m-medium | 4.5 | 4.5 | 4.5 | 4.5 |  |
| Test Results Aggregator | default | opus48-1m-ultracode | 5.0 | 4.5 | 4.5 | 4.5 |  |
| Test Results Aggregator | default | opus48-1m-xhigh | 4.5 | 4.0 | 4.5 | 4.5 |  |
| Test Results Aggregator | powershell | opus48-1m-high | 4.5 | 4.5 | 4.5 | 4.5 |  |
| Test Results Aggregator | powershell | opus48-1m-medium | 4.5 | 4.0 | 4.5 | 4.5 |  |
| Test Results Aggregator | powershell | opus48-1m-ultracode | 4.0 | 4.0 | 4.5 | 4.0 |  |
| Test Results Aggregator | powershell | opus48-1m-xhigh | 4.0 | 4.5 | 4.5 | 4.0 |  |
| Test Results Aggregator | powershell | opus48-1m-high | 4.5 | 4.5 | 4.5 | 4.5 |  |
| Test Results Aggregator | powershell | opus48-1m-medium | 4.0 | 4.0 | 3.5 | 4.0 |  |
| Test Results Aggregator | powershell | opus48-1m-ultracode | 4.5 | 4.5 | 4.5 | 4.5 |  |
| Test Results Aggregator | powershell | opus48-1m-xhigh | 5.0 | 4.5 | 4.5 | 4.5 |  |
| Test Results Aggregator | typescript-bun | opus48-1m-high | 5.0 | 4.5 | 4.5 | 4.5 |  |
| Test Results Aggregator | typescript-bun | opus48-1m-medium | 5.0 | 4.5 | 4.5 | 4.5 |  |
| Test Results Aggregator | typescript-bun | opus48-1m-ultracode | 5.0 | 5.0 | 5.0 | 5.0 |  |
| Test Results Aggregator | typescript-bun | opus48-1m-xhigh | 5.0 | 4.5 | 4.5 | 4.5 |  |
| Environment Matrix Generator | bash | opus48-1m-high | 5.0 | 4.5 | 4.5 | 4.5 |  |
| Environment Matrix Generator | bash | opus48-1m-medium | 3.5 | 3.5 | 4.0 | 3.5 |  |
| Environment Matrix Generator | bash | opus48-1m-ultracode | 4.0 | 4.0 | 4.0 | 4.0 |  |
| Environment Matrix Generator | bash | opus48-1m-xhigh | 4.5 | 4.0 | 4.5 | 4.0 |  |
| Environment Matrix Generator | default | opus48-1m-high | 3.5 | 3.5 | 3.5 | 3.5 |  |
| Environment Matrix Generator | default | opus48-1m-medium | 3.5 | 4.0 | 3.5 | 3.5 |  |
| Environment Matrix Generator | default | opus48-1m-ultracode | 5.0 | 5.0 | 5.0 | 5.0 |  |
| Environment Matrix Generator | default | opus48-1m-xhigh | 4.0 | 4.0 | 4.0 | 3.5 |  |
| Environment Matrix Generator | powershell | opus48-1m-high | 4.5 | 4.5 | 4.5 | 4.5 |  |
| Environment Matrix Generator | powershell | opus48-1m-medium | 4.5 | 4.5 | 4.5 | 4.5 |  |
| Environment Matrix Generator | powershell | opus48-1m-ultracode | 5.0 | 4.5 | 4.5 | 4.5 |  |
| Environment Matrix Generator | powershell | opus48-1m-xhigh | 4.5 | 4.5 | 4.5 | 4.0 |  |
| Environment Matrix Generator | powershell | opus48-1m-high | 4.5 | 4.5 | 4.5 | 4.5 |  |
| Environment Matrix Generator | powershell | opus48-1m-medium | 4.5 | 4.0 | 4.5 | 4.5 |  |
| Environment Matrix Generator | powershell | opus48-1m-ultracode | 5.0 | 5.0 | 5.0 | 5.0 |  |
| Environment Matrix Generator | powershell | opus48-1m-xhigh | 4.5 | 4.5 | 4.5 | 4.5 |  |
| Environment Matrix Generator | typescript-bun | opus48-1m-high | 4.5 | 4.5 | 4.5 | 4.5 |  |
| Environment Matrix Generator | typescript-bun | opus48-1m-medium | 4.5 | 4.5 | 4.5 | 4.5 |  |
| Environment Matrix Generator | typescript-bun | opus48-1m-ultracode | 4.0 | 4.0 | 4.0 | 4.0 |  |
| Environment Matrix Generator | typescript-bun | opus48-1m-xhigh | 5.0 | 4.5 | 4.5 | 4.5 |  |
| Artifact Cleanup Script | bash | opus48-1m-high | 5.0 | 5.0 | 5.0 | 5.0 |  |
| Artifact Cleanup Script | bash | opus48-1m-medium | 3.5 | 3.5 | 2.5 | 2.5 |  |
| Artifact Cleanup Script | bash | opus48-1m-ultracode | 4.0 | 2.5 | 4.0 | 3.0 |  |
| Artifact Cleanup Script | bash | opus48-1m-xhigh | 4.5 | 4.5 | 4.5 | 4.5 |  |
| Artifact Cleanup Script | default | opus48-1m-high | 5.0 | 4.5 | 4.5 | 4.5 |  |
| Artifact Cleanup Script | default | opus48-1m-medium | 4.5 | 4.5 | 4.0 | 4.0 |  |
| Artifact Cleanup Script | default | opus48-1m-ultracode | 5.0 | 5.0 | 5.0 | 5.0 |  |
| Artifact Cleanup Script | default | opus48-1m-xhigh | 4.5 | 4.0 | 4.5 | 4.5 |  |
| Artifact Cleanup Script | powershell | opus48-1m-high | 4.5 | 4.5 | 4.5 | 4.5 |  |
| Artifact Cleanup Script | powershell | opus48-1m-medium | 4.5 | 4.5 | 4.5 | 4.5 |  |
| Artifact Cleanup Script | powershell | opus48-1m-ultracode | 5.0 | 4.5 | 4.5 | 4.5 |  |
| Artifact Cleanup Script | powershell | opus48-1m-xhigh | 5.0 | 4.5 | 4.5 | 4.5 |  |
| Artifact Cleanup Script | powershell | opus48-1m-high | 5.0 | 4.5 | 4.5 | 4.5 |  |
| Artifact Cleanup Script | powershell | opus48-1m-medium | 4.0 | 4.0 | 4.5 | 4.0 |  |
| Artifact Cleanup Script | powershell | opus48-1m-ultracode | 4.5 | 4.5 | 4.5 | 4.5 |  |
| Artifact Cleanup Script | powershell | opus48-1m-xhigh | 4.5 | 4.5 | 4.5 | 4.5 |  |
| Artifact Cleanup Script | typescript-bun | opus48-1m-high | 4.5 | 4.5 | 4.5 | 4.5 |  |
| Artifact Cleanup Script | typescript-bun | opus48-1m-medium | 4.0 | 4.0 | 4.5 | 4.0 |  |
| Artifact Cleanup Script | typescript-bun | opus48-1m-ultracode | 4.5 | 4.5 | 4.5 | 4.5 |  |
| Artifact Cleanup Script | typescript-bun | opus48-1m-xhigh | 5.0 | 4.5 | 4.5 | 4.5 |  |
| Secret Rotation Validator | bash | opus48-1m-high | 4.5 | 4.5 | 4.5 | 4.5 |  |
| Secret Rotation Validator | bash | opus48-1m-medium | 4.0 | 4.0 | 4.5 | 4.0 |  |
| Secret Rotation Validator | bash | opus48-1m-ultracode | 5.0 | 4.5 | 4.5 | 4.5 |  |
| Secret Rotation Validator | bash | opus48-1m-xhigh | 4.5 | 4.5 | 5.0 | 4.5 |  |
| Secret Rotation Validator | default | opus48-1m-high | 4.0 | 4.0 | 4.5 | 4.0 |  |
| Secret Rotation Validator | default | opus48-1m-medium | 4.0 | 4.0 | 4.5 | 4.0 |  |
| Secret Rotation Validator | default | opus48-1m-ultracode | 5.0 | 4.5 | 5.0 | 4.5 |  |
| Secret Rotation Validator | default | opus48-1m-xhigh | 4.5 | 4.5 | 4.5 | 4.5 |  |
| Secret Rotation Validator | powershell | opus48-1m-high | 4.5 | 5.0 | 4.5 | 4.5 |  |
| Secret Rotation Validator | powershell | opus48-1m-medium | 4.5 | 4.5 | 4.0 | 4.0 |  |
| Secret Rotation Validator | powershell | opus48-1m-ultracode | 4.5 | 4.5 | 4.5 | 4.5 |  |
| Secret Rotation Validator | powershell | opus48-1m-xhigh | 4.0 | 4.0 | 4.5 | 4.0 |  |
| Secret Rotation Validator | powershell | opus48-1m-high | 4.5 | 4.5 | 4.5 | 4.5 |  |
| Secret Rotation Validator | powershell | opus48-1m-medium | 4.5 | 4.0 | 4.5 | 4.0 |  |
| Secret Rotation Validator | powershell | opus48-1m-ultracode | 4.5 | 4.5 | 4.0 | 4.0 |  |
| Secret Rotation Validator | powershell | opus48-1m-xhigh | 4.5 | 4.5 | 4.5 | 4.5 |  |
| Secret Rotation Validator | typescript-bun | opus48-1m-high | 4.0 | 4.0 | 4.5 | 4.0 |  |
| Secret Rotation Validator | typescript-bun | opus48-1m-medium | 4.5 | 4.5 | 4.5 | 4.5 |  |
| Secret Rotation Validator | typescript-bun | opus48-1m-ultracode | 5.0 | 5.0 | 5.0 | 5.0 |  |
| Secret Rotation Validator | typescript-bun | opus48-1m-xhigh | 4.5 | 4.5 | 4.5 | 4.5 |  |

</details>

### Correlation: Structural Metrics vs Tests Quality

Spearman rank correlation between automated counts and LLM judge scores.
Values near +1.0 indicate the LLM agrees with the structural signal; near 0 means no relationship.

| Structural Metric | vs Coverage | vs Rigor | vs Design | vs Overall |
|-------------------|------------|---------|----------|-----------|
| Test count | 0.34 | 0.48 | 0.32 | 0.39 |
| Assertion count | 0.4 | 0.53 | 0.38 | 0.44 |
| Test:code ratio | 0.14 | 0.23 | 0.12 | 0.12 |

*Based on 140 runs with both structural and LLM scores.*

### LLM vs Structural Discrepancies

**Qualitative disagreements** — structural metrics look reasonable; the LLM judge is weighing factors the counters can't measure.

| Task | Language | Model | Tests | Asserts | Cov | Rig | Des | Ovr | Flag | Justification |
|------|------|-------|-------|---------|-----|-----|-----|-----|------|---------------|
| Semantic Version Bumper | default | opus48-1m-high | 38 | 66 | 2.0 | 3.5 | 3.5 | 2.0 | LLM says low coverage (2.0/5) but 38 tests detected |  |
| Dependency License Checker | default | opus48-1m-high | 33 | 52 | 2.0 | 3.5 | 3.0 | 2.0 | LLM says low coverage (2.0/5) but 33 tests detected |  |

## Per-Run Results

*Tests Quality = Overall (1-5) from LLM-as-judge of generated test code (dimensions: coverage, rigor, design). `—` = no judge data.*

| Task | Language | Model | Duration | Turns | Errors | Cost | Tests Quality | Chosen | Status |
|------|----------|-------|----------|-------|--------|------|-----------|--------|--------|
| Artifact Cleanup Script | bash | opus48-1m-high | 11.6min | 47 | 0 | $3.32 | 5.0 | bash | ok |
| Artifact Cleanup Script | bash | opus48-1m-medium | 11.4min | 53 | 1 | $3.16 | 2.5 | bash | ok |
| Artifact Cleanup Script | bash | opus48-1m-ultracode | 14.2min | 28 | 1 | $3.60 | 3.0 | bash | ok |
| Artifact Cleanup Script | bash | opus48-1m-xhigh | 18.1min | 49 | 2 | $5.08 | 4.5 | bash | ok |
| Artifact Cleanup Script | default | opus48-1m-high | 10.2min | 50 | 0 | $3.16 | 4.5 | python | ok |
| Artifact Cleanup Script | default | opus48-1m-medium | 9.9min | 43 | 0 | $2.37 | 4.0 | powershell | ok |
| Artifact Cleanup Script | default | opus48-1m-ultracode | 15.8min | 55 | 0 | $4.99 | 5.0 | python | ok |
| Artifact Cleanup Script | default | opus48-1m-xhigh | 19.1min | 77 | 0 | $6.84 | 4.5 | python | ok |
| Artifact Cleanup Script | powershell | opus48-1m-high | 9.6min | 35 | 2 | $2.60 | 4.5 | powershell | ok |
| Artifact Cleanup Script | powershell | opus48-1m-high | 11.8min | 31 | 1 | $2.83 | 4.5 | powershell | ok |
| Artifact Cleanup Script | powershell | opus48-1m-medium | 9.3min | 28 | 0 | $2.26 | 4.5 | powershell | ok |
| Artifact Cleanup Script | powershell | opus48-1m-medium | 11.9min | 46 | 1 | $2.91 | 4.0 | powershell | ok |
| Artifact Cleanup Script | powershell | opus48-1m-ultracode | 21.5min | 38 | 0 | $5.17 | 4.5 | powershell | ok |
| Artifact Cleanup Script | powershell | opus48-1m-ultracode | 29.4min | 67 | 0 | $8.16 | 4.5 | powershell | ok |
| Artifact Cleanup Script | powershell | opus48-1m-xhigh | 25.0min | 92 | 1 | $7.41 | 4.5 | powershell | ok |
| Artifact Cleanup Script | powershell | opus48-1m-xhigh | 30.0min | 0 | 1 | $0.00 | 4.5 | powershell | timeout |
| Artifact Cleanup Script | typescript-bun | opus48-1m-high | 14.8min | 82 | 1 | $6.00 | 4.5 | typescript | ok |
| Artifact Cleanup Script | typescript-bun | opus48-1m-medium | 9.2min | 44 | 0 | $2.44 | 4.0 | typescript | ok |
| Artifact Cleanup Script | typescript-bun | opus48-1m-ultracode | 19.2min | 51 | 0 | $4.98 | 4.5 | typescript | ok |
| Artifact Cleanup Script | typescript-bun | opus48-1m-xhigh | 21.6min | 49 | 2 | $5.91 | 4.5 | typescript | ok |
| Dependency License Checker | bash | opus48-1m-high | 15.0min | 51 | 3 | $4.02 | 4.5 | bash | ok |
| Dependency License Checker | bash | opus48-1m-medium | 5.7min | 24 | 0 | $1.45 | 4.0 | bash | ok |
| Dependency License Checker | bash | opus48-1m-ultracode | 24.3min | 71 | 1 | $6.98 | 4.0 | bash | ok |
| Dependency License Checker | bash | opus48-1m-xhigh | 23.9min | 96 | 2 | $8.01 | 3.5 | bash | ok |
| Dependency License Checker | default | opus48-1m-high | 9.0min | 34 | 0 | $2.24 | 2.0 | powershell | ok |
| Dependency License Checker | default | opus48-1m-medium | 7.9min | 33 | 0 | $1.94 | 4.5 | python | ok |
| Dependency License Checker | default | opus48-1m-ultracode | 21.3min | 67 | 0 | $5.41 | 4.5 | powershell | ok |
| Dependency License Checker | default | opus48-1m-xhigh | 13.6min | 34 | 0 | $3.67 | 4.5 | python | ok |
| Dependency License Checker | powershell | opus48-1m-high | 12.8min | 42 | 1 | $3.09 | 4.5 | powershell | ok |
| Dependency License Checker | powershell | opus48-1m-high | 12.2min | 33 | 0 | $2.63 | 4.5 | powershell | ok |
| Dependency License Checker | powershell | opus48-1m-medium | 7.7min | 33 | 0 | $1.93 | 4.0 | powershell | ok |
| Dependency License Checker | powershell | opus48-1m-medium | 12.7min | 49 | 0 | $3.35 | 3.5 | powershell | ok |
| Dependency License Checker | powershell | opus48-1m-ultracode | 4.3min | 23 | 0 | $1.21 | 4.5 | powershell | ok |
| Dependency License Checker | powershell | opus48-1m-ultracode | 19.2min | 36 | 0 | $4.57 | 4.5 | powershell | ok |
| Dependency License Checker | powershell | opus48-1m-xhigh | 30.0min | 0 | 5 | $0.00 | 4.5 | powershell | timeout |
| Dependency License Checker | powershell | opus48-1m-xhigh | 25.2min | 49 | 0 | $6.38 | 4.5 | powershell | ok |
| Dependency License Checker | typescript-bun | opus48-1m-high | 11.5min | 47 | 0 | $3.04 | 4.5 | typescript | ok |
| Dependency License Checker | typescript-bun | opus48-1m-medium | 8.7min | 45 | 0 | $2.33 | 4.0 | typescript | ok |
| Dependency License Checker | typescript-bun | opus48-1m-ultracode | 17.8min | 52 | 0 | $4.95 | 4.0 | typescript | ok |
| Dependency License Checker | typescript-bun | opus48-1m-xhigh | 19.6min | 48 | 0 | $5.16 | 4.5 | typescript | ok |
| Environment Matrix Generator | bash | opus48-1m-high | 9.4min | 39 | 1 | $2.51 | 4.5 | bash | ok |
| Environment Matrix Generator | bash | opus48-1m-medium | 5.8min | 27 | 0 | $1.72 | 3.5 | bash | ok |
| Environment Matrix Generator | bash | opus48-1m-ultracode | 17.6min | 41 | 1 | $4.58 | 4.0 | bash | ok |
| Environment Matrix Generator | bash | opus48-1m-xhigh | 18.6min | 59 | 0 | $5.52 | 4.0 | bash | ok |
| Environment Matrix Generator | default | opus48-1m-high | 8.2min | 24 | 0 | $2.01 | 3.5 | python | ok |
| Environment Matrix Generator | default | opus48-1m-medium | 6.7min | 28 | 0 | $2.01 | 3.5 | python | ok |
| Environment Matrix Generator | default | opus48-1m-ultracode | 22.7min | 70 | 1 | $6.54 | 5.0 | python | ok |
| Environment Matrix Generator | default | opus48-1m-xhigh | 16.2min | 38 | 0 | $4.05 | 3.5 | python | ok |
| Environment Matrix Generator | powershell | opus48-1m-high | 13.7min | 44 | 1 | $3.48 | 4.5 | powershell | ok |
| Environment Matrix Generator | powershell | opus48-1m-high | 9.2min | 27 | 0 | $3.06 | 4.5 | powershell | ok |
| Environment Matrix Generator | powershell | opus48-1m-medium | 9.3min | 33 | 0 | $2.29 | 4.5 | powershell | ok |
| Environment Matrix Generator | powershell | opus48-1m-medium | 12.9min | 52 | 2 | $3.60 | 4.5 | powershell | ok |
| Environment Matrix Generator | powershell | opus48-1m-ultracode | 25.3min | 42 | 1 | $6.29 | 4.5 | powershell | ok |
| Environment Matrix Generator | powershell | opus48-1m-ultracode | 26.7min | 49 | 2 | $6.39 | 5.0 | powershell | ok |
| Environment Matrix Generator | powershell | opus48-1m-xhigh | 28.4min | 58 | 0 | $7.16 | 4.0 | powershell | ok |
| Environment Matrix Generator | powershell | opus48-1m-xhigh | 30.0min | 0 | 0 | $0.00 | 4.5 | powershell | timeout |
| Environment Matrix Generator | typescript-bun | opus48-1m-high | 13.3min | 69 | 0 | $3.94 | 4.5 | typescript | ok |
| Environment Matrix Generator | typescript-bun | opus48-1m-medium | 9.1min | 40 | 0 | $2.29 | 4.5 | typescript | ok |
| Environment Matrix Generator | typescript-bun | opus48-1m-ultracode | 21.2min | 56 | 0 | $5.58 | 4.0 | typescript | ok |
| Environment Matrix Generator | typescript-bun | opus48-1m-xhigh | 25.3min | 77 | 1 | $7.25 | 4.5 | typescript | ok |
| PR Label Assigner | bash | opus48-1m-high | 10.1min | 31 | 0 | $2.45 | 4.5 | bash | ok |
| PR Label Assigner | bash | opus48-1m-medium | 4.8min | 20 | 0 | $1.22 | 2.0 | bash | ok |
| PR Label Assigner | bash | opus48-1m-ultracode | 18.6min | 55 | 2 | $5.24 | 4.5 | bash | ok |
| PR Label Assigner | bash | opus48-1m-xhigh | 20.5min | 64 | 0 | $5.87 | 4.5 | bash | ok |
| PR Label Assigner | default | opus48-1m-high | 7.1min | 25 | 1 | $1.86 | 4.0 | python | ok |
| PR Label Assigner | default | opus48-1m-medium | 8.2min | 36 | 1 | $1.91 | 4.0 | powershell | ok |
| PR Label Assigner | default | opus48-1m-ultracode | 12.6min | 51 | 0 | $4.18 | 4.0 | python | ok |
| PR Label Assigner | default | opus48-1m-xhigh | 9.8min | 29 | 0 | $2.66 | 4.5 | python | ok |
| PR Label Assigner | powershell | opus48-1m-high | 11.0min | 47 | 0 | $2.65 | 4.5 | powershell | ok |
| PR Label Assigner | powershell | opus48-1m-high | 11.4min | 41 | 0 | $2.78 | 4.0 | powershell | ok |
| PR Label Assigner | powershell | opus48-1m-medium | 6.3min | 23 | 0 | $1.52 | 4.5 | powershell | ok |
| PR Label Assigner | powershell | opus48-1m-medium | 7.6min | 27 | 1 | $1.66 | 4.5 | powershell | ok |
| PR Label Assigner | powershell | opus48-1m-ultracode | 21.3min | 52 | 0 | $5.68 | 4.5 | powershell | ok |
| PR Label Assigner | powershell | opus48-1m-ultracode | 22.3min | 50 | 1 | $5.54 | 4.5 | powershell | ok |
| PR Label Assigner | powershell | opus48-1m-xhigh | 19.4min | 63 | 0 | $5.67 | 4.5 | powershell | ok |
| PR Label Assigner | powershell | opus48-1m-xhigh | 30.0min | 0 | 0 | $0.00 | 4.5 | powershell | timeout |
| PR Label Assigner | typescript-bun | opus48-1m-high | 3.0min | 26 | 1 | $1.17 | 4.0 | typescript | ok |
| PR Label Assigner | typescript-bun | opus48-1m-medium | 13.1min | 44 | 0 | $2.48 | 4.5 | typescript | ok |
| PR Label Assigner | typescript-bun | opus48-1m-ultracode | 21.5min | 62 | 5 | $5.80 | 4.5 | typescript | ok |
| PR Label Assigner | typescript-bun | opus48-1m-xhigh | 19.8min | 72 | 0 | $6.01 | 3.5 | typescript | ok |
| Secret Rotation Validator | bash | opus48-1m-high | 9.4min | 33 | 0 | $2.38 | 4.5 | bash | ok |
| Secret Rotation Validator | bash | opus48-1m-medium | 23.9min | 64 | 6 | $5.71 | 4.0 | bash | ok |
| Secret Rotation Validator | bash | opus48-1m-ultracode | 26.1min | 52 | 2 | $5.71 | 4.5 | bash | ok |
| Secret Rotation Validator | bash | opus48-1m-xhigh | 21.4min | 55 | 0 | $5.41 | 4.5 | bash | ok |
| Secret Rotation Validator | default | opus48-1m-high | 9.1min | 47 | 0 | $3.12 | 4.0 | python | ok |
| Secret Rotation Validator | default | opus48-1m-medium | 5.9min | 29 | 0 | $1.65 | 4.0 | python | ok |
| Secret Rotation Validator | default | opus48-1m-ultracode | 18.9min | 55 | 0 | $5.63 | 4.5 | python | ok |
| Secret Rotation Validator | default | opus48-1m-xhigh | 15.6min | 46 | 0 | $4.15 | 4.5 | python | ok |
| Secret Rotation Validator | powershell | opus48-1m-high | 15.4min | 53 | 0 | $3.46 | 4.5 | powershell | ok |
| Secret Rotation Validator | powershell | opus48-1m-high | 15.2min | 33 | 0 | $3.22 | 4.5 | powershell | ok |
| Secret Rotation Validator | powershell | opus48-1m-medium | 1.1min | 11 | 0 | $0.55 | 4.0 | powershell | ok |
| Secret Rotation Validator | powershell | opus48-1m-medium | 8.0min | 34 | 1 | $2.14 | 4.0 | powershell | ok |
| Secret Rotation Validator | powershell | opus48-1m-ultracode | 33.6min | 74 | 0 | $9.44 | 4.5 | powershell | ok |
| Secret Rotation Validator | powershell | opus48-1m-ultracode | 30.9min | 52 | 0 | $7.74 | 4.0 | powershell | ok |
| Secret Rotation Validator | powershell | opus48-1m-xhigh | 19.5min | 60 | 0 | $5.52 | 4.0 | powershell | ok |
| Secret Rotation Validator | powershell | opus48-1m-xhigh | 26.1min | 78 | 0 | $7.45 | 4.5 | powershell | ok |
| Secret Rotation Validator | typescript-bun | opus48-1m-high | 11.9min | 45 | 1 | $3.29 | 4.0 | typescript | ok |
| Secret Rotation Validator | typescript-bun | opus48-1m-medium | 23.0min | 78 | 2 | $4.51 | 4.5 | typescript | ok |
| Secret Rotation Validator | typescript-bun | opus48-1m-ultracode | 25.7min | 65 | 2 | $7.94 | 5.0 | typescript | ok |
| Secret Rotation Validator | typescript-bun | opus48-1m-xhigh | 17.5min | 54 | 0 | $5.12 | 4.5 | typescript | ok |
| Semantic Version Bumper | bash | opus48-1m-high | 9.5min | 41 | 1 | $2.70 | 4.5 | bash | ok |
| Semantic Version Bumper | bash | opus48-1m-medium | 6.8min | 22 | 0 | $1.55 | 4.0 | bash | ok |
| Semantic Version Bumper | bash | opus48-1m-ultracode | 20.8min | 74 | 0 | $6.09 | 4.5 | bash | ok |
| Semantic Version Bumper | bash | opus48-1m-xhigh | 18.1min | 47 | 2 | $4.91 | 3.0 | bash | ok |
| Semantic Version Bumper | default | opus48-1m-high | 9.8min | 52 | 0 | $3.34 | 2.0 | javascript | ok |
| Semantic Version Bumper | default | opus48-1m-medium | 7.2min | 27 | 0 | $1.83 | 4.5 | python | ok |
| Semantic Version Bumper | default | opus48-1m-ultracode | 14.6min | 43 | 0 | $4.35 | 4.5 | python | ok |
| Semantic Version Bumper | default | opus48-1m-xhigh | 15.3min | 50 | 1 | $4.59 | 4.5 | python | ok |
| Semantic Version Bumper | powershell | opus48-1m-high | 16.9min | 60 | 2 | $3.59 | 4.5 | powershell | ok |
| Semantic Version Bumper | powershell | opus48-1m-high | 12.1min | 34 | 0 | $2.32 | 4.5 | powershell | ok |
| Semantic Version Bumper | powershell | opus48-1m-medium | 10.0min | 34 | 0 | $2.33 | 4.0 | powershell | ok |
| Semantic Version Bumper | powershell | opus48-1m-medium | 10.6min | 40 | 1 | $2.39 | 4.5 | powershell | ok |
| Semantic Version Bumper | powershell | opus48-1m-ultracode | 31.9min | 65 | 2 | $13.39 | 4.5 | powershell | ok |
| Semantic Version Bumper | powershell | opus48-1m-ultracode | 25.2min | 58 | 0 | $6.83 | 4.5 | powershell | ok |
| Semantic Version Bumper | powershell | opus48-1m-xhigh | 21.0min | 69 | 1 | $6.19 | 4.5 | powershell | ok |
| Semantic Version Bumper | powershell | opus48-1m-xhigh | 21.0min | 61 | 1 | $5.56 | 4.5 | powershell | ok |
| Semantic Version Bumper | typescript-bun | opus48-1m-high | 11.5min | 52 | 0 | $3.14 | 4.0 | typescript | ok |
| Semantic Version Bumper | typescript-bun | opus48-1m-medium | 9.3min | 47 | 2 | $2.47 | 4.5 | typescript | ok |
| Semantic Version Bumper | typescript-bun | opus48-1m-ultracode | 30.6min | 104 | 0 | $11.91 | 4.5 | typescript | ok |
| Semantic Version Bumper | typescript-bun | opus48-1m-xhigh | 22.3min | 71 | 3 | $6.51 | 4.5 | typescript | ok |
| Test Results Aggregator | bash | opus48-1m-high | 8.4min | 28 | 0 | $2.20 | 2.5 | bash | ok |
| Test Results Aggregator | bash | opus48-1m-medium | 6.3min | 29 | 1 | $1.83 | 3.0 | bash | ok |
| Test Results Aggregator | bash | opus48-1m-ultracode | 17.5min | 46 | 0 | $5.53 | 3.0 | bash | ok |
| Test Results Aggregator | bash | opus48-1m-xhigh | 21.2min | 53 | 3 | $5.41 | 4.5 | bash | ok |
| Test Results Aggregator | default | opus48-1m-high | 12.2min | 59 | 1 | $3.42 | 4.0 | python | ok |
| Test Results Aggregator | default | opus48-1m-medium | 6.6min | 26 | 0 | $1.50 | 4.5 | python | ok |
| Test Results Aggregator | default | opus48-1m-ultracode | 13.4min | 29 | 0 | $3.22 | 4.5 | python | ok |
| Test Results Aggregator | default | opus48-1m-xhigh | 17.2min | 63 | 0 | $5.38 | 4.5 | python | ok |
| Test Results Aggregator | powershell | opus48-1m-high | 17.3min | 59 | 0 | $3.84 | 4.5 | powershell | ok |
| Test Results Aggregator | powershell | opus48-1m-high | 15.2min | 47 | 0 | $3.39 | 4.5 | powershell | ok |
| Test Results Aggregator | powershell | opus48-1m-medium | 8.1min | 30 | 0 | $1.77 | 4.5 | powershell | ok |
| Test Results Aggregator | powershell | opus48-1m-medium | 7.4min | 29 | 0 | $1.95 | 4.0 | powershell | ok |
| Test Results Aggregator | powershell | opus48-1m-ultracode | 24.6min | 48 | 0 | $6.88 | 4.0 | powershell | ok |
| Test Results Aggregator | powershell | opus48-1m-ultracode | 20.5min | 47 | 0 | $5.53 | 4.5 | powershell | ok |
| Test Results Aggregator | powershell | opus48-1m-xhigh | 18.2min | 39 | 0 | $4.52 | 4.0 | powershell | ok |
| Test Results Aggregator | powershell | opus48-1m-xhigh | 25.9min | 67 | 2 | $6.67 | 4.5 | powershell | ok |
| Test Results Aggregator | typescript-bun | opus48-1m-high | 19.2min | 69 | 0 | $5.19 | 4.5 | typescript | ok |
| Test Results Aggregator | typescript-bun | opus48-1m-medium | 9.2min | 45 | 0 | $2.57 | 4.5 | typescript | ok |
| Test Results Aggregator | typescript-bun | opus48-1m-ultracode | 32.3min | 79 | 0 | $10.28 | 5.0 | typescript | ok |
| Test Results Aggregator | typescript-bun | opus48-1m-xhigh | 16.4min | 46 | 0 | $4.37 | 4.5 | typescript | ok |


<details>
<summary>Sorted by cost (cheapest first)</summary>

| Task | Language | Model | Duration | Turns | Errors | Cost | Tests Quality | Chosen | Status |
|------|----------|-------|----------|-------|--------|------|-----------|--------|--------|
| PR Label Assigner | powershell | opus48-1m-xhigh | 30.0min | 0 | 0 | $0.00 | 4.5 | powershell | timeout |
| Dependency License Checker | powershell | opus48-1m-xhigh | 30.0min | 0 | 5 | $0.00 | 4.5 | powershell | timeout |
| Environment Matrix Generator | powershell | opus48-1m-xhigh | 30.0min | 0 | 0 | $0.00 | 4.5 | powershell | timeout |
| Artifact Cleanup Script | powershell | opus48-1m-xhigh | 30.0min | 0 | 1 | $0.00 | 4.5 | powershell | timeout |
| Secret Rotation Validator | powershell | opus48-1m-medium | 1.1min | 11 | 0 | $0.55 | 4.0 | powershell | ok |
| PR Label Assigner | typescript-bun | opus48-1m-high | 3.0min | 26 | 1 | $1.17 | 4.0 | typescript | ok |
| Dependency License Checker | powershell | opus48-1m-ultracode | 4.3min | 23 | 0 | $1.21 | 4.5 | powershell | ok |
| PR Label Assigner | bash | opus48-1m-medium | 4.8min | 20 | 0 | $1.22 | 2.0 | bash | ok |
| Dependency License Checker | bash | opus48-1m-medium | 5.7min | 24 | 0 | $1.45 | 4.0 | bash | ok |
| Test Results Aggregator | default | opus48-1m-medium | 6.6min | 26 | 0 | $1.50 | 4.5 | python | ok |
| PR Label Assigner | powershell | opus48-1m-medium | 6.3min | 23 | 0 | $1.52 | 4.5 | powershell | ok |
| Semantic Version Bumper | bash | opus48-1m-medium | 6.8min | 22 | 0 | $1.55 | 4.0 | bash | ok |
| Secret Rotation Validator | default | opus48-1m-medium | 5.9min | 29 | 0 | $1.65 | 4.0 | python | ok |
| PR Label Assigner | powershell | opus48-1m-medium | 7.6min | 27 | 1 | $1.66 | 4.5 | powershell | ok |
| Environment Matrix Generator | bash | opus48-1m-medium | 5.8min | 27 | 0 | $1.72 | 3.5 | bash | ok |
| Test Results Aggregator | powershell | opus48-1m-medium | 8.1min | 30 | 0 | $1.77 | 4.5 | powershell | ok |
| Semantic Version Bumper | default | opus48-1m-medium | 7.2min | 27 | 0 | $1.83 | 4.5 | python | ok |
| Test Results Aggregator | bash | opus48-1m-medium | 6.3min | 29 | 1 | $1.83 | 3.0 | bash | ok |
| PR Label Assigner | default | opus48-1m-high | 7.1min | 25 | 1 | $1.86 | 4.0 | python | ok |
| PR Label Assigner | default | opus48-1m-medium | 8.2min | 36 | 1 | $1.91 | 4.0 | powershell | ok |
| Dependency License Checker | powershell | opus48-1m-medium | 7.7min | 33 | 0 | $1.93 | 4.0 | powershell | ok |
| Dependency License Checker | default | opus48-1m-medium | 7.9min | 33 | 0 | $1.94 | 4.5 | python | ok |
| Test Results Aggregator | powershell | opus48-1m-medium | 7.4min | 29 | 0 | $1.95 | 4.0 | powershell | ok |
| Environment Matrix Generator | default | opus48-1m-medium | 6.7min | 28 | 0 | $2.01 | 3.5 | python | ok |
| Environment Matrix Generator | default | opus48-1m-high | 8.2min | 24 | 0 | $2.01 | 3.5 | python | ok |
| Secret Rotation Validator | powershell | opus48-1m-medium | 8.0min | 34 | 1 | $2.14 | 4.0 | powershell | ok |
| Test Results Aggregator | bash | opus48-1m-high | 8.4min | 28 | 0 | $2.20 | 2.5 | bash | ok |
| Dependency License Checker | default | opus48-1m-high | 9.0min | 34 | 0 | $2.24 | 2.0 | powershell | ok |
| Artifact Cleanup Script | powershell | opus48-1m-medium | 9.3min | 28 | 0 | $2.26 | 4.5 | powershell | ok |
| Environment Matrix Generator | typescript-bun | opus48-1m-medium | 9.1min | 40 | 0 | $2.29 | 4.5 | typescript | ok |
| Environment Matrix Generator | powershell | opus48-1m-medium | 9.3min | 33 | 0 | $2.29 | 4.5 | powershell | ok |
| Semantic Version Bumper | powershell | opus48-1m-high | 12.1min | 34 | 0 | $2.32 | 4.5 | powershell | ok |
| Dependency License Checker | typescript-bun | opus48-1m-medium | 8.7min | 45 | 0 | $2.33 | 4.0 | typescript | ok |
| Semantic Version Bumper | powershell | opus48-1m-medium | 10.0min | 34 | 0 | $2.33 | 4.0 | powershell | ok |
| Artifact Cleanup Script | default | opus48-1m-medium | 9.9min | 43 | 0 | $2.37 | 4.0 | powershell | ok |
| Secret Rotation Validator | bash | opus48-1m-high | 9.4min | 33 | 0 | $2.38 | 4.5 | bash | ok |
| Semantic Version Bumper | powershell | opus48-1m-medium | 10.6min | 40 | 1 | $2.39 | 4.5 | powershell | ok |
| Artifact Cleanup Script | typescript-bun | opus48-1m-medium | 9.2min | 44 | 0 | $2.44 | 4.0 | typescript | ok |
| PR Label Assigner | bash | opus48-1m-high | 10.1min | 31 | 0 | $2.45 | 4.5 | bash | ok |
| Semantic Version Bumper | typescript-bun | opus48-1m-medium | 9.3min | 47 | 2 | $2.47 | 4.5 | typescript | ok |
| PR Label Assigner | typescript-bun | opus48-1m-medium | 13.1min | 44 | 0 | $2.48 | 4.5 | typescript | ok |
| Environment Matrix Generator | bash | opus48-1m-high | 9.4min | 39 | 1 | $2.51 | 4.5 | bash | ok |
| Test Results Aggregator | typescript-bun | opus48-1m-medium | 9.2min | 45 | 0 | $2.57 | 4.5 | typescript | ok |
| Artifact Cleanup Script | powershell | opus48-1m-high | 9.6min | 35 | 2 | $2.60 | 4.5 | powershell | ok |
| Dependency License Checker | powershell | opus48-1m-high | 12.2min | 33 | 0 | $2.63 | 4.5 | powershell | ok |
| PR Label Assigner | powershell | opus48-1m-high | 11.0min | 47 | 0 | $2.65 | 4.5 | powershell | ok |
| PR Label Assigner | default | opus48-1m-xhigh | 9.8min | 29 | 0 | $2.66 | 4.5 | python | ok |
| Semantic Version Bumper | bash | opus48-1m-high | 9.5min | 41 | 1 | $2.70 | 4.5 | bash | ok |
| PR Label Assigner | powershell | opus48-1m-high | 11.4min | 41 | 0 | $2.78 | 4.0 | powershell | ok |
| Artifact Cleanup Script | powershell | opus48-1m-high | 11.8min | 31 | 1 | $2.83 | 4.5 | powershell | ok |
| Artifact Cleanup Script | powershell | opus48-1m-medium | 11.9min | 46 | 1 | $2.91 | 4.0 | powershell | ok |
| Dependency License Checker | typescript-bun | opus48-1m-high | 11.5min | 47 | 0 | $3.04 | 4.5 | typescript | ok |
| Environment Matrix Generator | powershell | opus48-1m-high | 9.2min | 27 | 0 | $3.06 | 4.5 | powershell | ok |
| Dependency License Checker | powershell | opus48-1m-high | 12.8min | 42 | 1 | $3.09 | 4.5 | powershell | ok |
| Secret Rotation Validator | default | opus48-1m-high | 9.1min | 47 | 0 | $3.12 | 4.0 | python | ok |
| Semantic Version Bumper | typescript-bun | opus48-1m-high | 11.5min | 52 | 0 | $3.14 | 4.0 | typescript | ok |
| Artifact Cleanup Script | bash | opus48-1m-medium | 11.4min | 53 | 1 | $3.16 | 2.5 | bash | ok |
| Artifact Cleanup Script | default | opus48-1m-high | 10.2min | 50 | 0 | $3.16 | 4.5 | python | ok |
| Test Results Aggregator | default | opus48-1m-ultracode | 13.4min | 29 | 0 | $3.22 | 4.5 | python | ok |
| Secret Rotation Validator | powershell | opus48-1m-high | 15.2min | 33 | 0 | $3.22 | 4.5 | powershell | ok |
| Secret Rotation Validator | typescript-bun | opus48-1m-high | 11.9min | 45 | 1 | $3.29 | 4.0 | typescript | ok |
| Artifact Cleanup Script | bash | opus48-1m-high | 11.6min | 47 | 0 | $3.32 | 5.0 | bash | ok |
| Semantic Version Bumper | default | opus48-1m-high | 9.8min | 52 | 0 | $3.34 | 2.0 | javascript | ok |
| Dependency License Checker | powershell | opus48-1m-medium | 12.7min | 49 | 0 | $3.35 | 3.5 | powershell | ok |
| Test Results Aggregator | powershell | opus48-1m-high | 15.2min | 47 | 0 | $3.39 | 4.5 | powershell | ok |
| Test Results Aggregator | default | opus48-1m-high | 12.2min | 59 | 1 | $3.42 | 4.0 | python | ok |
| Secret Rotation Validator | powershell | opus48-1m-high | 15.4min | 53 | 0 | $3.46 | 4.5 | powershell | ok |
| Environment Matrix Generator | powershell | opus48-1m-high | 13.7min | 44 | 1 | $3.48 | 4.5 | powershell | ok |
| Semantic Version Bumper | powershell | opus48-1m-high | 16.9min | 60 | 2 | $3.59 | 4.5 | powershell | ok |
| Artifact Cleanup Script | bash | opus48-1m-ultracode | 14.2min | 28 | 1 | $3.60 | 3.0 | bash | ok |
| Environment Matrix Generator | powershell | opus48-1m-medium | 12.9min | 52 | 2 | $3.60 | 4.5 | powershell | ok |
| Dependency License Checker | default | opus48-1m-xhigh | 13.6min | 34 | 0 | $3.67 | 4.5 | python | ok |
| Test Results Aggregator | powershell | opus48-1m-high | 17.3min | 59 | 0 | $3.84 | 4.5 | powershell | ok |
| Environment Matrix Generator | typescript-bun | opus48-1m-high | 13.3min | 69 | 0 | $3.94 | 4.5 | typescript | ok |
| Dependency License Checker | bash | opus48-1m-high | 15.0min | 51 | 3 | $4.02 | 4.5 | bash | ok |
| Environment Matrix Generator | default | opus48-1m-xhigh | 16.2min | 38 | 0 | $4.05 | 3.5 | python | ok |
| Secret Rotation Validator | default | opus48-1m-xhigh | 15.6min | 46 | 0 | $4.15 | 4.5 | python | ok |
| PR Label Assigner | default | opus48-1m-ultracode | 12.6min | 51 | 0 | $4.18 | 4.0 | python | ok |
| Semantic Version Bumper | default | opus48-1m-ultracode | 14.6min | 43 | 0 | $4.35 | 4.5 | python | ok |
| Test Results Aggregator | typescript-bun | opus48-1m-xhigh | 16.4min | 46 | 0 | $4.37 | 4.5 | typescript | ok |
| Secret Rotation Validator | typescript-bun | opus48-1m-medium | 23.0min | 78 | 2 | $4.51 | 4.5 | typescript | ok |
| Test Results Aggregator | powershell | opus48-1m-xhigh | 18.2min | 39 | 0 | $4.52 | 4.0 | powershell | ok |
| Dependency License Checker | powershell | opus48-1m-ultracode | 19.2min | 36 | 0 | $4.57 | 4.5 | powershell | ok |
| Environment Matrix Generator | bash | opus48-1m-ultracode | 17.6min | 41 | 1 | $4.58 | 4.0 | bash | ok |
| Semantic Version Bumper | default | opus48-1m-xhigh | 15.3min | 50 | 1 | $4.59 | 4.5 | python | ok |
| Semantic Version Bumper | bash | opus48-1m-xhigh | 18.1min | 47 | 2 | $4.91 | 3.0 | bash | ok |
| Dependency License Checker | typescript-bun | opus48-1m-ultracode | 17.8min | 52 | 0 | $4.95 | 4.0 | typescript | ok |
| Artifact Cleanup Script | typescript-bun | opus48-1m-ultracode | 19.2min | 51 | 0 | $4.98 | 4.5 | typescript | ok |
| Artifact Cleanup Script | default | opus48-1m-ultracode | 15.8min | 55 | 0 | $4.99 | 5.0 | python | ok |
| Artifact Cleanup Script | bash | opus48-1m-xhigh | 18.1min | 49 | 2 | $5.08 | 4.5 | bash | ok |
| Secret Rotation Validator | typescript-bun | opus48-1m-xhigh | 17.5min | 54 | 0 | $5.12 | 4.5 | typescript | ok |
| Dependency License Checker | typescript-bun | opus48-1m-xhigh | 19.6min | 48 | 0 | $5.16 | 4.5 | typescript | ok |
| Artifact Cleanup Script | powershell | opus48-1m-ultracode | 21.5min | 38 | 0 | $5.17 | 4.5 | powershell | ok |
| Test Results Aggregator | typescript-bun | opus48-1m-high | 19.2min | 69 | 0 | $5.19 | 4.5 | typescript | ok |
| PR Label Assigner | bash | opus48-1m-ultracode | 18.6min | 55 | 2 | $5.24 | 4.5 | bash | ok |
| Test Results Aggregator | default | opus48-1m-xhigh | 17.2min | 63 | 0 | $5.38 | 4.5 | python | ok |
| Test Results Aggregator | bash | opus48-1m-xhigh | 21.2min | 53 | 3 | $5.41 | 4.5 | bash | ok |
| Secret Rotation Validator | bash | opus48-1m-xhigh | 21.4min | 55 | 0 | $5.41 | 4.5 | bash | ok |
| Dependency License Checker | default | opus48-1m-ultracode | 21.3min | 67 | 0 | $5.41 | 4.5 | powershell | ok |
| Environment Matrix Generator | bash | opus48-1m-xhigh | 18.6min | 59 | 0 | $5.52 | 4.0 | bash | ok |
| Secret Rotation Validator | powershell | opus48-1m-xhigh | 19.5min | 60 | 0 | $5.52 | 4.0 | powershell | ok |
| Test Results Aggregator | powershell | opus48-1m-ultracode | 20.5min | 47 | 0 | $5.53 | 4.5 | powershell | ok |
| Test Results Aggregator | bash | opus48-1m-ultracode | 17.5min | 46 | 0 | $5.53 | 3.0 | bash | ok |
| PR Label Assigner | powershell | opus48-1m-ultracode | 22.3min | 50 | 1 | $5.54 | 4.5 | powershell | ok |
| Semantic Version Bumper | powershell | opus48-1m-xhigh | 21.0min | 61 | 1 | $5.56 | 4.5 | powershell | ok |
| Environment Matrix Generator | typescript-bun | opus48-1m-ultracode | 21.2min | 56 | 0 | $5.58 | 4.0 | typescript | ok |
| Secret Rotation Validator | default | opus48-1m-ultracode | 18.9min | 55 | 0 | $5.63 | 4.5 | python | ok |
| PR Label Assigner | powershell | opus48-1m-xhigh | 19.4min | 63 | 0 | $5.67 | 4.5 | powershell | ok |
| PR Label Assigner | powershell | opus48-1m-ultracode | 21.3min | 52 | 0 | $5.68 | 4.5 | powershell | ok |
| Secret Rotation Validator | bash | opus48-1m-ultracode | 26.1min | 52 | 2 | $5.71 | 4.5 | bash | ok |
| Secret Rotation Validator | bash | opus48-1m-medium | 23.9min | 64 | 6 | $5.71 | 4.0 | bash | ok |
| PR Label Assigner | typescript-bun | opus48-1m-ultracode | 21.5min | 62 | 5 | $5.80 | 4.5 | typescript | ok |
| PR Label Assigner | bash | opus48-1m-xhigh | 20.5min | 64 | 0 | $5.87 | 4.5 | bash | ok |
| Artifact Cleanup Script | typescript-bun | opus48-1m-xhigh | 21.6min | 49 | 2 | $5.91 | 4.5 | typescript | ok |
| Artifact Cleanup Script | typescript-bun | opus48-1m-high | 14.8min | 82 | 1 | $6.00 | 4.5 | typescript | ok |
| PR Label Assigner | typescript-bun | opus48-1m-xhigh | 19.8min | 72 | 0 | $6.01 | 3.5 | typescript | ok |
| Semantic Version Bumper | bash | opus48-1m-ultracode | 20.8min | 74 | 0 | $6.09 | 4.5 | bash | ok |
| Semantic Version Bumper | powershell | opus48-1m-xhigh | 21.0min | 69 | 1 | $6.19 | 4.5 | powershell | ok |
| Environment Matrix Generator | powershell | opus48-1m-ultracode | 25.3min | 42 | 1 | $6.29 | 4.5 | powershell | ok |
| Dependency License Checker | powershell | opus48-1m-xhigh | 25.2min | 49 | 0 | $6.38 | 4.5 | powershell | ok |
| Environment Matrix Generator | powershell | opus48-1m-ultracode | 26.7min | 49 | 2 | $6.39 | 5.0 | powershell | ok |
| Semantic Version Bumper | typescript-bun | opus48-1m-xhigh | 22.3min | 71 | 3 | $6.51 | 4.5 | typescript | ok |
| Environment Matrix Generator | default | opus48-1m-ultracode | 22.7min | 70 | 1 | $6.54 | 5.0 | python | ok |
| Test Results Aggregator | powershell | opus48-1m-xhigh | 25.9min | 67 | 2 | $6.67 | 4.5 | powershell | ok |
| Semantic Version Bumper | powershell | opus48-1m-ultracode | 25.2min | 58 | 0 | $6.83 | 4.5 | powershell | ok |
| Artifact Cleanup Script | default | opus48-1m-xhigh | 19.1min | 77 | 0 | $6.84 | 4.5 | python | ok |
| Test Results Aggregator | powershell | opus48-1m-ultracode | 24.6min | 48 | 0 | $6.88 | 4.0 | powershell | ok |
| Dependency License Checker | bash | opus48-1m-ultracode | 24.3min | 71 | 1 | $6.98 | 4.0 | bash | ok |
| Environment Matrix Generator | powershell | opus48-1m-xhigh | 28.4min | 58 | 0 | $7.16 | 4.0 | powershell | ok |
| Environment Matrix Generator | typescript-bun | opus48-1m-xhigh | 25.3min | 77 | 1 | $7.25 | 4.5 | typescript | ok |
| Artifact Cleanup Script | powershell | opus48-1m-xhigh | 25.0min | 92 | 1 | $7.41 | 4.5 | powershell | ok |
| Secret Rotation Validator | powershell | opus48-1m-xhigh | 26.1min | 78 | 0 | $7.45 | 4.5 | powershell | ok |
| Secret Rotation Validator | powershell | opus48-1m-ultracode | 30.9min | 52 | 0 | $7.74 | 4.0 | powershell | ok |
| Secret Rotation Validator | typescript-bun | opus48-1m-ultracode | 25.7min | 65 | 2 | $7.94 | 5.0 | typescript | ok |
| Dependency License Checker | bash | opus48-1m-xhigh | 23.9min | 96 | 2 | $8.01 | 3.5 | bash | ok |
| Artifact Cleanup Script | powershell | opus48-1m-ultracode | 29.4min | 67 | 0 | $8.16 | 4.5 | powershell | ok |
| Secret Rotation Validator | powershell | opus48-1m-ultracode | 33.6min | 74 | 0 | $9.44 | 4.5 | powershell | ok |
| Test Results Aggregator | typescript-bun | opus48-1m-ultracode | 32.3min | 79 | 0 | $10.28 | 5.0 | typescript | ok |
| Semantic Version Bumper | typescript-bun | opus48-1m-ultracode | 30.6min | 104 | 0 | $11.91 | 4.5 | typescript | ok |
| Semantic Version Bumper | powershell | opus48-1m-ultracode | 31.9min | 65 | 2 | $13.39 | 4.5 | powershell | ok |

</details>

<details>
<summary>Sorted by duration (fastest first)</summary>

| Task | Language | Model | Duration | Turns | Errors | Cost | Tests Quality | Chosen | Status |
|------|----------|-------|----------|-------|--------|------|-----------|--------|--------|
| Secret Rotation Validator | powershell | opus48-1m-medium | 1.1min | 11 | 0 | $0.55 | 4.0 | powershell | ok |
| PR Label Assigner | typescript-bun | opus48-1m-high | 3.0min | 26 | 1 | $1.17 | 4.0 | typescript | ok |
| Dependency License Checker | powershell | opus48-1m-ultracode | 4.3min | 23 | 0 | $1.21 | 4.5 | powershell | ok |
| PR Label Assigner | bash | opus48-1m-medium | 4.8min | 20 | 0 | $1.22 | 2.0 | bash | ok |
| Dependency License Checker | bash | opus48-1m-medium | 5.7min | 24 | 0 | $1.45 | 4.0 | bash | ok |
| Environment Matrix Generator | bash | opus48-1m-medium | 5.8min | 27 | 0 | $1.72 | 3.5 | bash | ok |
| Secret Rotation Validator | default | opus48-1m-medium | 5.9min | 29 | 0 | $1.65 | 4.0 | python | ok |
| Test Results Aggregator | bash | opus48-1m-medium | 6.3min | 29 | 1 | $1.83 | 3.0 | bash | ok |
| PR Label Assigner | powershell | opus48-1m-medium | 6.3min | 23 | 0 | $1.52 | 4.5 | powershell | ok |
| Test Results Aggregator | default | opus48-1m-medium | 6.6min | 26 | 0 | $1.50 | 4.5 | python | ok |
| Environment Matrix Generator | default | opus48-1m-medium | 6.7min | 28 | 0 | $2.01 | 3.5 | python | ok |
| Semantic Version Bumper | bash | opus48-1m-medium | 6.8min | 22 | 0 | $1.55 | 4.0 | bash | ok |
| PR Label Assigner | default | opus48-1m-high | 7.1min | 25 | 1 | $1.86 | 4.0 | python | ok |
| Semantic Version Bumper | default | opus48-1m-medium | 7.2min | 27 | 0 | $1.83 | 4.5 | python | ok |
| Test Results Aggregator | powershell | opus48-1m-medium | 7.4min | 29 | 0 | $1.95 | 4.0 | powershell | ok |
| PR Label Assigner | powershell | opus48-1m-medium | 7.6min | 27 | 1 | $1.66 | 4.5 | powershell | ok |
| Dependency License Checker | powershell | opus48-1m-medium | 7.7min | 33 | 0 | $1.93 | 4.0 | powershell | ok |
| Dependency License Checker | default | opus48-1m-medium | 7.9min | 33 | 0 | $1.94 | 4.5 | python | ok |
| Secret Rotation Validator | powershell | opus48-1m-medium | 8.0min | 34 | 1 | $2.14 | 4.0 | powershell | ok |
| Test Results Aggregator | powershell | opus48-1m-medium | 8.1min | 30 | 0 | $1.77 | 4.5 | powershell | ok |
| PR Label Assigner | default | opus48-1m-medium | 8.2min | 36 | 1 | $1.91 | 4.0 | powershell | ok |
| Environment Matrix Generator | default | opus48-1m-high | 8.2min | 24 | 0 | $2.01 | 3.5 | python | ok |
| Test Results Aggregator | bash | opus48-1m-high | 8.4min | 28 | 0 | $2.20 | 2.5 | bash | ok |
| Dependency License Checker | typescript-bun | opus48-1m-medium | 8.7min | 45 | 0 | $2.33 | 4.0 | typescript | ok |
| Dependency License Checker | default | opus48-1m-high | 9.0min | 34 | 0 | $2.24 | 2.0 | powershell | ok |
| Secret Rotation Validator | default | opus48-1m-high | 9.1min | 47 | 0 | $3.12 | 4.0 | python | ok |
| Environment Matrix Generator | typescript-bun | opus48-1m-medium | 9.1min | 40 | 0 | $2.29 | 4.5 | typescript | ok |
| Environment Matrix Generator | powershell | opus48-1m-high | 9.2min | 27 | 0 | $3.06 | 4.5 | powershell | ok |
| Artifact Cleanup Script | typescript-bun | opus48-1m-medium | 9.2min | 44 | 0 | $2.44 | 4.0 | typescript | ok |
| Test Results Aggregator | typescript-bun | opus48-1m-medium | 9.2min | 45 | 0 | $2.57 | 4.5 | typescript | ok |
| Artifact Cleanup Script | powershell | opus48-1m-medium | 9.3min | 28 | 0 | $2.26 | 4.5 | powershell | ok |
| Semantic Version Bumper | typescript-bun | opus48-1m-medium | 9.3min | 47 | 2 | $2.47 | 4.5 | typescript | ok |
| Environment Matrix Generator | powershell | opus48-1m-medium | 9.3min | 33 | 0 | $2.29 | 4.5 | powershell | ok |
| Secret Rotation Validator | bash | opus48-1m-high | 9.4min | 33 | 0 | $2.38 | 4.5 | bash | ok |
| Environment Matrix Generator | bash | opus48-1m-high | 9.4min | 39 | 1 | $2.51 | 4.5 | bash | ok |
| Semantic Version Bumper | bash | opus48-1m-high | 9.5min | 41 | 1 | $2.70 | 4.5 | bash | ok |
| Artifact Cleanup Script | powershell | opus48-1m-high | 9.6min | 35 | 2 | $2.60 | 4.5 | powershell | ok |
| Semantic Version Bumper | default | opus48-1m-high | 9.8min | 52 | 0 | $3.34 | 2.0 | javascript | ok |
| PR Label Assigner | default | opus48-1m-xhigh | 9.8min | 29 | 0 | $2.66 | 4.5 | python | ok |
| Artifact Cleanup Script | default | opus48-1m-medium | 9.9min | 43 | 0 | $2.37 | 4.0 | powershell | ok |
| Semantic Version Bumper | powershell | opus48-1m-medium | 10.0min | 34 | 0 | $2.33 | 4.0 | powershell | ok |
| PR Label Assigner | bash | opus48-1m-high | 10.1min | 31 | 0 | $2.45 | 4.5 | bash | ok |
| Artifact Cleanup Script | default | opus48-1m-high | 10.2min | 50 | 0 | $3.16 | 4.5 | python | ok |
| Semantic Version Bumper | powershell | opus48-1m-medium | 10.6min | 40 | 1 | $2.39 | 4.5 | powershell | ok |
| PR Label Assigner | powershell | opus48-1m-high | 11.0min | 47 | 0 | $2.65 | 4.5 | powershell | ok |
| Artifact Cleanup Script | bash | opus48-1m-medium | 11.4min | 53 | 1 | $3.16 | 2.5 | bash | ok |
| PR Label Assigner | powershell | opus48-1m-high | 11.4min | 41 | 0 | $2.78 | 4.0 | powershell | ok |
| Semantic Version Bumper | typescript-bun | opus48-1m-high | 11.5min | 52 | 0 | $3.14 | 4.0 | typescript | ok |
| Dependency License Checker | typescript-bun | opus48-1m-high | 11.5min | 47 | 0 | $3.04 | 4.5 | typescript | ok |
| Artifact Cleanup Script | bash | opus48-1m-high | 11.6min | 47 | 0 | $3.32 | 5.0 | bash | ok |
| Artifact Cleanup Script | powershell | opus48-1m-high | 11.8min | 31 | 1 | $2.83 | 4.5 | powershell | ok |
| Artifact Cleanup Script | powershell | opus48-1m-medium | 11.9min | 46 | 1 | $2.91 | 4.0 | powershell | ok |
| Secret Rotation Validator | typescript-bun | opus48-1m-high | 11.9min | 45 | 1 | $3.29 | 4.0 | typescript | ok |
| Semantic Version Bumper | powershell | opus48-1m-high | 12.1min | 34 | 0 | $2.32 | 4.5 | powershell | ok |
| Dependency License Checker | powershell | opus48-1m-high | 12.2min | 33 | 0 | $2.63 | 4.5 | powershell | ok |
| Test Results Aggregator | default | opus48-1m-high | 12.2min | 59 | 1 | $3.42 | 4.0 | python | ok |
| PR Label Assigner | default | opus48-1m-ultracode | 12.6min | 51 | 0 | $4.18 | 4.0 | python | ok |
| Dependency License Checker | powershell | opus48-1m-medium | 12.7min | 49 | 0 | $3.35 | 3.5 | powershell | ok |
| Dependency License Checker | powershell | opus48-1m-high | 12.8min | 42 | 1 | $3.09 | 4.5 | powershell | ok |
| Environment Matrix Generator | powershell | opus48-1m-medium | 12.9min | 52 | 2 | $3.60 | 4.5 | powershell | ok |
| PR Label Assigner | typescript-bun | opus48-1m-medium | 13.1min | 44 | 0 | $2.48 | 4.5 | typescript | ok |
| Environment Matrix Generator | typescript-bun | opus48-1m-high | 13.3min | 69 | 0 | $3.94 | 4.5 | typescript | ok |
| Test Results Aggregator | default | opus48-1m-ultracode | 13.4min | 29 | 0 | $3.22 | 4.5 | python | ok |
| Dependency License Checker | default | opus48-1m-xhigh | 13.6min | 34 | 0 | $3.67 | 4.5 | python | ok |
| Environment Matrix Generator | powershell | opus48-1m-high | 13.7min | 44 | 1 | $3.48 | 4.5 | powershell | ok |
| Artifact Cleanup Script | bash | opus48-1m-ultracode | 14.2min | 28 | 1 | $3.60 | 3.0 | bash | ok |
| Semantic Version Bumper | default | opus48-1m-ultracode | 14.6min | 43 | 0 | $4.35 | 4.5 | python | ok |
| Artifact Cleanup Script | typescript-bun | opus48-1m-high | 14.8min | 82 | 1 | $6.00 | 4.5 | typescript | ok |
| Dependency License Checker | bash | opus48-1m-high | 15.0min | 51 | 3 | $4.02 | 4.5 | bash | ok |
| Test Results Aggregator | powershell | opus48-1m-high | 15.2min | 47 | 0 | $3.39 | 4.5 | powershell | ok |
| Secret Rotation Validator | powershell | opus48-1m-high | 15.2min | 33 | 0 | $3.22 | 4.5 | powershell | ok |
| Semantic Version Bumper | default | opus48-1m-xhigh | 15.3min | 50 | 1 | $4.59 | 4.5 | python | ok |
| Secret Rotation Validator | powershell | opus48-1m-high | 15.4min | 53 | 0 | $3.46 | 4.5 | powershell | ok |
| Secret Rotation Validator | default | opus48-1m-xhigh | 15.6min | 46 | 0 | $4.15 | 4.5 | python | ok |
| Artifact Cleanup Script | default | opus48-1m-ultracode | 15.8min | 55 | 0 | $4.99 | 5.0 | python | ok |
| Environment Matrix Generator | default | opus48-1m-xhigh | 16.2min | 38 | 0 | $4.05 | 3.5 | python | ok |
| Test Results Aggregator | typescript-bun | opus48-1m-xhigh | 16.4min | 46 | 0 | $4.37 | 4.5 | typescript | ok |
| Semantic Version Bumper | powershell | opus48-1m-high | 16.9min | 60 | 2 | $3.59 | 4.5 | powershell | ok |
| Test Results Aggregator | default | opus48-1m-xhigh | 17.2min | 63 | 0 | $5.38 | 4.5 | python | ok |
| Test Results Aggregator | powershell | opus48-1m-high | 17.3min | 59 | 0 | $3.84 | 4.5 | powershell | ok |
| Test Results Aggregator | bash | opus48-1m-ultracode | 17.5min | 46 | 0 | $5.53 | 3.0 | bash | ok |
| Secret Rotation Validator | typescript-bun | opus48-1m-xhigh | 17.5min | 54 | 0 | $5.12 | 4.5 | typescript | ok |
| Environment Matrix Generator | bash | opus48-1m-ultracode | 17.6min | 41 | 1 | $4.58 | 4.0 | bash | ok |
| Dependency License Checker | typescript-bun | opus48-1m-ultracode | 17.8min | 52 | 0 | $4.95 | 4.0 | typescript | ok |
| Artifact Cleanup Script | bash | opus48-1m-xhigh | 18.1min | 49 | 2 | $5.08 | 4.5 | bash | ok |
| Semantic Version Bumper | bash | opus48-1m-xhigh | 18.1min | 47 | 2 | $4.91 | 3.0 | bash | ok |
| Test Results Aggregator | powershell | opus48-1m-xhigh | 18.2min | 39 | 0 | $4.52 | 4.0 | powershell | ok |
| PR Label Assigner | bash | opus48-1m-ultracode | 18.6min | 55 | 2 | $5.24 | 4.5 | bash | ok |
| Environment Matrix Generator | bash | opus48-1m-xhigh | 18.6min | 59 | 0 | $5.52 | 4.0 | bash | ok |
| Secret Rotation Validator | default | opus48-1m-ultracode | 18.9min | 55 | 0 | $5.63 | 4.5 | python | ok |
| Artifact Cleanup Script | default | opus48-1m-xhigh | 19.1min | 77 | 0 | $6.84 | 4.5 | python | ok |
| Artifact Cleanup Script | typescript-bun | opus48-1m-ultracode | 19.2min | 51 | 0 | $4.98 | 4.5 | typescript | ok |
| Test Results Aggregator | typescript-bun | opus48-1m-high | 19.2min | 69 | 0 | $5.19 | 4.5 | typescript | ok |
| Dependency License Checker | powershell | opus48-1m-ultracode | 19.2min | 36 | 0 | $4.57 | 4.5 | powershell | ok |
| PR Label Assigner | powershell | opus48-1m-xhigh | 19.4min | 63 | 0 | $5.67 | 4.5 | powershell | ok |
| Secret Rotation Validator | powershell | opus48-1m-xhigh | 19.5min | 60 | 0 | $5.52 | 4.0 | powershell | ok |
| Dependency License Checker | typescript-bun | opus48-1m-xhigh | 19.6min | 48 | 0 | $5.16 | 4.5 | typescript | ok |
| PR Label Assigner | typescript-bun | opus48-1m-xhigh | 19.8min | 72 | 0 | $6.01 | 3.5 | typescript | ok |
| PR Label Assigner | bash | opus48-1m-xhigh | 20.5min | 64 | 0 | $5.87 | 4.5 | bash | ok |
| Test Results Aggregator | powershell | opus48-1m-ultracode | 20.5min | 47 | 0 | $5.53 | 4.5 | powershell | ok |
| Semantic Version Bumper | bash | opus48-1m-ultracode | 20.8min | 74 | 0 | $6.09 | 4.5 | bash | ok |
| Semantic Version Bumper | powershell | opus48-1m-xhigh | 21.0min | 69 | 1 | $6.19 | 4.5 | powershell | ok |
| Semantic Version Bumper | powershell | opus48-1m-xhigh | 21.0min | 61 | 1 | $5.56 | 4.5 | powershell | ok |
| Environment Matrix Generator | typescript-bun | opus48-1m-ultracode | 21.2min | 56 | 0 | $5.58 | 4.0 | typescript | ok |
| Test Results Aggregator | bash | opus48-1m-xhigh | 21.2min | 53 | 3 | $5.41 | 4.5 | bash | ok |
| PR Label Assigner | powershell | opus48-1m-ultracode | 21.3min | 52 | 0 | $5.68 | 4.5 | powershell | ok |
| Dependency License Checker | default | opus48-1m-ultracode | 21.3min | 67 | 0 | $5.41 | 4.5 | powershell | ok |
| Secret Rotation Validator | bash | opus48-1m-xhigh | 21.4min | 55 | 0 | $5.41 | 4.5 | bash | ok |
| PR Label Assigner | typescript-bun | opus48-1m-ultracode | 21.5min | 62 | 5 | $5.80 | 4.5 | typescript | ok |
| Artifact Cleanup Script | powershell | opus48-1m-ultracode | 21.5min | 38 | 0 | $5.17 | 4.5 | powershell | ok |
| Artifact Cleanup Script | typescript-bun | opus48-1m-xhigh | 21.6min | 49 | 2 | $5.91 | 4.5 | typescript | ok |
| Semantic Version Bumper | typescript-bun | opus48-1m-xhigh | 22.3min | 71 | 3 | $6.51 | 4.5 | typescript | ok |
| PR Label Assigner | powershell | opus48-1m-ultracode | 22.3min | 50 | 1 | $5.54 | 4.5 | powershell | ok |
| Environment Matrix Generator | default | opus48-1m-ultracode | 22.7min | 70 | 1 | $6.54 | 5.0 | python | ok |
| Secret Rotation Validator | typescript-bun | opus48-1m-medium | 23.0min | 78 | 2 | $4.51 | 4.5 | typescript | ok |
| Secret Rotation Validator | bash | opus48-1m-medium | 23.9min | 64 | 6 | $5.71 | 4.0 | bash | ok |
| Dependency License Checker | bash | opus48-1m-xhigh | 23.9min | 96 | 2 | $8.01 | 3.5 | bash | ok |
| Dependency License Checker | bash | opus48-1m-ultracode | 24.3min | 71 | 1 | $6.98 | 4.0 | bash | ok |
| Test Results Aggregator | powershell | opus48-1m-ultracode | 24.6min | 48 | 0 | $6.88 | 4.0 | powershell | ok |
| Artifact Cleanup Script | powershell | opus48-1m-xhigh | 25.0min | 92 | 1 | $7.41 | 4.5 | powershell | ok |
| Semantic Version Bumper | powershell | opus48-1m-ultracode | 25.2min | 58 | 0 | $6.83 | 4.5 | powershell | ok |
| Dependency License Checker | powershell | opus48-1m-xhigh | 25.2min | 49 | 0 | $6.38 | 4.5 | powershell | ok |
| Environment Matrix Generator | powershell | opus48-1m-ultracode | 25.3min | 42 | 1 | $6.29 | 4.5 | powershell | ok |
| Environment Matrix Generator | typescript-bun | opus48-1m-xhigh | 25.3min | 77 | 1 | $7.25 | 4.5 | typescript | ok |
| Secret Rotation Validator | typescript-bun | opus48-1m-ultracode | 25.7min | 65 | 2 | $7.94 | 5.0 | typescript | ok |
| Test Results Aggregator | powershell | opus48-1m-xhigh | 25.9min | 67 | 2 | $6.67 | 4.5 | powershell | ok |
| Secret Rotation Validator | bash | opus48-1m-ultracode | 26.1min | 52 | 2 | $5.71 | 4.5 | bash | ok |
| Secret Rotation Validator | powershell | opus48-1m-xhigh | 26.1min | 78 | 0 | $7.45 | 4.5 | powershell | ok |
| Environment Matrix Generator | powershell | opus48-1m-ultracode | 26.7min | 49 | 2 | $6.39 | 5.0 | powershell | ok |
| Environment Matrix Generator | powershell | opus48-1m-xhigh | 28.4min | 58 | 0 | $7.16 | 4.0 | powershell | ok |
| Artifact Cleanup Script | powershell | opus48-1m-ultracode | 29.4min | 67 | 0 | $8.16 | 4.5 | powershell | ok |
| Artifact Cleanup Script | powershell | opus48-1m-xhigh | 30.0min | 0 | 1 | $0.00 | 4.5 | powershell | timeout |
| Dependency License Checker | powershell | opus48-1m-xhigh | 30.0min | 0 | 5 | $0.00 | 4.5 | powershell | timeout |
| PR Label Assigner | powershell | opus48-1m-xhigh | 30.0min | 0 | 0 | $0.00 | 4.5 | powershell | timeout |
| Environment Matrix Generator | powershell | opus48-1m-xhigh | 30.0min | 0 | 0 | $0.00 | 4.5 | powershell | timeout |
| Semantic Version Bumper | typescript-bun | opus48-1m-ultracode | 30.6min | 104 | 0 | $11.91 | 4.5 | typescript | ok |
| Secret Rotation Validator | powershell | opus48-1m-ultracode | 30.9min | 52 | 0 | $7.74 | 4.0 | powershell | ok |
| Semantic Version Bumper | powershell | opus48-1m-ultracode | 31.9min | 65 | 2 | $13.39 | 4.5 | powershell | ok |
| Test Results Aggregator | typescript-bun | opus48-1m-ultracode | 32.3min | 79 | 0 | $10.28 | 5.0 | typescript | ok |
| Secret Rotation Validator | powershell | opus48-1m-ultracode | 33.6min | 74 | 0 | $9.44 | 4.5 | powershell | ok |

</details>

<details>
<summary>Sorted by errors (fewest first)</summary>

| Task | Language | Model | Duration | Turns | Errors | Cost | Tests Quality | Chosen | Status |
|------|----------|-------|----------|-------|--------|------|-----------|--------|--------|
| Semantic Version Bumper | bash | opus48-1m-medium | 6.8min | 22 | 0 | $1.55 | 4.0 | bash | ok |
| Semantic Version Bumper | bash | opus48-1m-ultracode | 20.8min | 74 | 0 | $6.09 | 4.5 | bash | ok |
| Semantic Version Bumper | default | opus48-1m-high | 9.8min | 52 | 0 | $3.34 | 2.0 | javascript | ok |
| Semantic Version Bumper | default | opus48-1m-medium | 7.2min | 27 | 0 | $1.83 | 4.5 | python | ok |
| Semantic Version Bumper | default | opus48-1m-ultracode | 14.6min | 43 | 0 | $4.35 | 4.5 | python | ok |
| Semantic Version Bumper | powershell | opus48-1m-medium | 10.0min | 34 | 0 | $2.33 | 4.0 | powershell | ok |
| Semantic Version Bumper | powershell | opus48-1m-high | 12.1min | 34 | 0 | $2.32 | 4.5 | powershell | ok |
| Semantic Version Bumper | powershell | opus48-1m-ultracode | 25.2min | 58 | 0 | $6.83 | 4.5 | powershell | ok |
| Semantic Version Bumper | typescript-bun | opus48-1m-high | 11.5min | 52 | 0 | $3.14 | 4.0 | typescript | ok |
| Semantic Version Bumper | typescript-bun | opus48-1m-ultracode | 30.6min | 104 | 0 | $11.91 | 4.5 | typescript | ok |
| PR Label Assigner | bash | opus48-1m-high | 10.1min | 31 | 0 | $2.45 | 4.5 | bash | ok |
| PR Label Assigner | bash | opus48-1m-medium | 4.8min | 20 | 0 | $1.22 | 2.0 | bash | ok |
| PR Label Assigner | bash | opus48-1m-xhigh | 20.5min | 64 | 0 | $5.87 | 4.5 | bash | ok |
| PR Label Assigner | default | opus48-1m-ultracode | 12.6min | 51 | 0 | $4.18 | 4.0 | python | ok |
| PR Label Assigner | default | opus48-1m-xhigh | 9.8min | 29 | 0 | $2.66 | 4.5 | python | ok |
| PR Label Assigner | powershell | opus48-1m-high | 11.0min | 47 | 0 | $2.65 | 4.5 | powershell | ok |
| PR Label Assigner | powershell | opus48-1m-medium | 6.3min | 23 | 0 | $1.52 | 4.5 | powershell | ok |
| PR Label Assigner | powershell | opus48-1m-ultracode | 21.3min | 52 | 0 | $5.68 | 4.5 | powershell | ok |
| PR Label Assigner | powershell | opus48-1m-xhigh | 19.4min | 63 | 0 | $5.67 | 4.5 | powershell | ok |
| PR Label Assigner | powershell | opus48-1m-high | 11.4min | 41 | 0 | $2.78 | 4.0 | powershell | ok |
| PR Label Assigner | powershell | opus48-1m-xhigh | 30.0min | 0 | 0 | $0.00 | 4.5 | powershell | timeout |
| PR Label Assigner | typescript-bun | opus48-1m-medium | 13.1min | 44 | 0 | $2.48 | 4.5 | typescript | ok |
| PR Label Assigner | typescript-bun | opus48-1m-xhigh | 19.8min | 72 | 0 | $6.01 | 3.5 | typescript | ok |
| Dependency License Checker | bash | opus48-1m-medium | 5.7min | 24 | 0 | $1.45 | 4.0 | bash | ok |
| Dependency License Checker | default | opus48-1m-high | 9.0min | 34 | 0 | $2.24 | 2.0 | powershell | ok |
| Dependency License Checker | default | opus48-1m-medium | 7.9min | 33 | 0 | $1.94 | 4.5 | python | ok |
| Dependency License Checker | default | opus48-1m-ultracode | 21.3min | 67 | 0 | $5.41 | 4.5 | powershell | ok |
| Dependency License Checker | default | opus48-1m-xhigh | 13.6min | 34 | 0 | $3.67 | 4.5 | python | ok |
| Dependency License Checker | powershell | opus48-1m-medium | 7.7min | 33 | 0 | $1.93 | 4.0 | powershell | ok |
| Dependency License Checker | powershell | opus48-1m-ultracode | 4.3min | 23 | 0 | $1.21 | 4.5 | powershell | ok |
| Dependency License Checker | powershell | opus48-1m-high | 12.2min | 33 | 0 | $2.63 | 4.5 | powershell | ok |
| Dependency License Checker | powershell | opus48-1m-medium | 12.7min | 49 | 0 | $3.35 | 3.5 | powershell | ok |
| Dependency License Checker | powershell | opus48-1m-ultracode | 19.2min | 36 | 0 | $4.57 | 4.5 | powershell | ok |
| Dependency License Checker | powershell | opus48-1m-xhigh | 25.2min | 49 | 0 | $6.38 | 4.5 | powershell | ok |
| Dependency License Checker | typescript-bun | opus48-1m-high | 11.5min | 47 | 0 | $3.04 | 4.5 | typescript | ok |
| Dependency License Checker | typescript-bun | opus48-1m-medium | 8.7min | 45 | 0 | $2.33 | 4.0 | typescript | ok |
| Dependency License Checker | typescript-bun | opus48-1m-ultracode | 17.8min | 52 | 0 | $4.95 | 4.0 | typescript | ok |
| Dependency License Checker | typescript-bun | opus48-1m-xhigh | 19.6min | 48 | 0 | $5.16 | 4.5 | typescript | ok |
| Test Results Aggregator | bash | opus48-1m-high | 8.4min | 28 | 0 | $2.20 | 2.5 | bash | ok |
| Test Results Aggregator | bash | opus48-1m-ultracode | 17.5min | 46 | 0 | $5.53 | 3.0 | bash | ok |
| Test Results Aggregator | default | opus48-1m-medium | 6.6min | 26 | 0 | $1.50 | 4.5 | python | ok |
| Test Results Aggregator | default | opus48-1m-ultracode | 13.4min | 29 | 0 | $3.22 | 4.5 | python | ok |
| Test Results Aggregator | default | opus48-1m-xhigh | 17.2min | 63 | 0 | $5.38 | 4.5 | python | ok |
| Test Results Aggregator | powershell | opus48-1m-high | 17.3min | 59 | 0 | $3.84 | 4.5 | powershell | ok |
| Test Results Aggregator | powershell | opus48-1m-medium | 8.1min | 30 | 0 | $1.77 | 4.5 | powershell | ok |
| Test Results Aggregator | powershell | opus48-1m-ultracode | 24.6min | 48 | 0 | $6.88 | 4.0 | powershell | ok |
| Test Results Aggregator | powershell | opus48-1m-xhigh | 18.2min | 39 | 0 | $4.52 | 4.0 | powershell | ok |
| Test Results Aggregator | powershell | opus48-1m-high | 15.2min | 47 | 0 | $3.39 | 4.5 | powershell | ok |
| Test Results Aggregator | powershell | opus48-1m-medium | 7.4min | 29 | 0 | $1.95 | 4.0 | powershell | ok |
| Test Results Aggregator | powershell | opus48-1m-ultracode | 20.5min | 47 | 0 | $5.53 | 4.5 | powershell | ok |
| Test Results Aggregator | typescript-bun | opus48-1m-high | 19.2min | 69 | 0 | $5.19 | 4.5 | typescript | ok |
| Test Results Aggregator | typescript-bun | opus48-1m-medium | 9.2min | 45 | 0 | $2.57 | 4.5 | typescript | ok |
| Test Results Aggregator | typescript-bun | opus48-1m-ultracode | 32.3min | 79 | 0 | $10.28 | 5.0 | typescript | ok |
| Test Results Aggregator | typescript-bun | opus48-1m-xhigh | 16.4min | 46 | 0 | $4.37 | 4.5 | typescript | ok |
| Environment Matrix Generator | bash | opus48-1m-medium | 5.8min | 27 | 0 | $1.72 | 3.5 | bash | ok |
| Environment Matrix Generator | bash | opus48-1m-xhigh | 18.6min | 59 | 0 | $5.52 | 4.0 | bash | ok |
| Environment Matrix Generator | default | opus48-1m-high | 8.2min | 24 | 0 | $2.01 | 3.5 | python | ok |
| Environment Matrix Generator | default | opus48-1m-medium | 6.7min | 28 | 0 | $2.01 | 3.5 | python | ok |
| Environment Matrix Generator | default | opus48-1m-xhigh | 16.2min | 38 | 0 | $4.05 | 3.5 | python | ok |
| Environment Matrix Generator | powershell | opus48-1m-medium | 9.3min | 33 | 0 | $2.29 | 4.5 | powershell | ok |
| Environment Matrix Generator | powershell | opus48-1m-xhigh | 28.4min | 58 | 0 | $7.16 | 4.0 | powershell | ok |
| Environment Matrix Generator | powershell | opus48-1m-high | 9.2min | 27 | 0 | $3.06 | 4.5 | powershell | ok |
| Environment Matrix Generator | powershell | opus48-1m-xhigh | 30.0min | 0 | 0 | $0.00 | 4.5 | powershell | timeout |
| Environment Matrix Generator | typescript-bun | opus48-1m-high | 13.3min | 69 | 0 | $3.94 | 4.5 | typescript | ok |
| Environment Matrix Generator | typescript-bun | opus48-1m-medium | 9.1min | 40 | 0 | $2.29 | 4.5 | typescript | ok |
| Environment Matrix Generator | typescript-bun | opus48-1m-ultracode | 21.2min | 56 | 0 | $5.58 | 4.0 | typescript | ok |
| Artifact Cleanup Script | bash | opus48-1m-high | 11.6min | 47 | 0 | $3.32 | 5.0 | bash | ok |
| Artifact Cleanup Script | default | opus48-1m-high | 10.2min | 50 | 0 | $3.16 | 4.5 | python | ok |
| Artifact Cleanup Script | default | opus48-1m-medium | 9.9min | 43 | 0 | $2.37 | 4.0 | powershell | ok |
| Artifact Cleanup Script | default | opus48-1m-ultracode | 15.8min | 55 | 0 | $4.99 | 5.0 | python | ok |
| Artifact Cleanup Script | default | opus48-1m-xhigh | 19.1min | 77 | 0 | $6.84 | 4.5 | python | ok |
| Artifact Cleanup Script | powershell | opus48-1m-medium | 9.3min | 28 | 0 | $2.26 | 4.5 | powershell | ok |
| Artifact Cleanup Script | powershell | opus48-1m-ultracode | 21.5min | 38 | 0 | $5.17 | 4.5 | powershell | ok |
| Artifact Cleanup Script | powershell | opus48-1m-ultracode | 29.4min | 67 | 0 | $8.16 | 4.5 | powershell | ok |
| Artifact Cleanup Script | typescript-bun | opus48-1m-medium | 9.2min | 44 | 0 | $2.44 | 4.0 | typescript | ok |
| Artifact Cleanup Script | typescript-bun | opus48-1m-ultracode | 19.2min | 51 | 0 | $4.98 | 4.5 | typescript | ok |
| Secret Rotation Validator | bash | opus48-1m-high | 9.4min | 33 | 0 | $2.38 | 4.5 | bash | ok |
| Secret Rotation Validator | bash | opus48-1m-xhigh | 21.4min | 55 | 0 | $5.41 | 4.5 | bash | ok |
| Secret Rotation Validator | default | opus48-1m-high | 9.1min | 47 | 0 | $3.12 | 4.0 | python | ok |
| Secret Rotation Validator | default | opus48-1m-medium | 5.9min | 29 | 0 | $1.65 | 4.0 | python | ok |
| Secret Rotation Validator | default | opus48-1m-ultracode | 18.9min | 55 | 0 | $5.63 | 4.5 | python | ok |
| Secret Rotation Validator | default | opus48-1m-xhigh | 15.6min | 46 | 0 | $4.15 | 4.5 | python | ok |
| Secret Rotation Validator | powershell | opus48-1m-high | 15.4min | 53 | 0 | $3.46 | 4.5 | powershell | ok |
| Secret Rotation Validator | powershell | opus48-1m-medium | 1.1min | 11 | 0 | $0.55 | 4.0 | powershell | ok |
| Secret Rotation Validator | powershell | opus48-1m-ultracode | 33.6min | 74 | 0 | $9.44 | 4.5 | powershell | ok |
| Secret Rotation Validator | powershell | opus48-1m-xhigh | 19.5min | 60 | 0 | $5.52 | 4.0 | powershell | ok |
| Secret Rotation Validator | powershell | opus48-1m-high | 15.2min | 33 | 0 | $3.22 | 4.5 | powershell | ok |
| Secret Rotation Validator | powershell | opus48-1m-ultracode | 30.9min | 52 | 0 | $7.74 | 4.0 | powershell | ok |
| Secret Rotation Validator | powershell | opus48-1m-xhigh | 26.1min | 78 | 0 | $7.45 | 4.5 | powershell | ok |
| Secret Rotation Validator | typescript-bun | opus48-1m-xhigh | 17.5min | 54 | 0 | $5.12 | 4.5 | typescript | ok |
| Semantic Version Bumper | bash | opus48-1m-high | 9.5min | 41 | 1 | $2.70 | 4.5 | bash | ok |
| Semantic Version Bumper | default | opus48-1m-xhigh | 15.3min | 50 | 1 | $4.59 | 4.5 | python | ok |
| Semantic Version Bumper | powershell | opus48-1m-xhigh | 21.0min | 69 | 1 | $6.19 | 4.5 | powershell | ok |
| Semantic Version Bumper | powershell | opus48-1m-medium | 10.6min | 40 | 1 | $2.39 | 4.5 | powershell | ok |
| Semantic Version Bumper | powershell | opus48-1m-xhigh | 21.0min | 61 | 1 | $5.56 | 4.5 | powershell | ok |
| PR Label Assigner | default | opus48-1m-high | 7.1min | 25 | 1 | $1.86 | 4.0 | python | ok |
| PR Label Assigner | default | opus48-1m-medium | 8.2min | 36 | 1 | $1.91 | 4.0 | powershell | ok |
| PR Label Assigner | powershell | opus48-1m-medium | 7.6min | 27 | 1 | $1.66 | 4.5 | powershell | ok |
| PR Label Assigner | powershell | opus48-1m-ultracode | 22.3min | 50 | 1 | $5.54 | 4.5 | powershell | ok |
| PR Label Assigner | typescript-bun | opus48-1m-high | 3.0min | 26 | 1 | $1.17 | 4.0 | typescript | ok |
| Dependency License Checker | bash | opus48-1m-ultracode | 24.3min | 71 | 1 | $6.98 | 4.0 | bash | ok |
| Dependency License Checker | powershell | opus48-1m-high | 12.8min | 42 | 1 | $3.09 | 4.5 | powershell | ok |
| Test Results Aggregator | bash | opus48-1m-medium | 6.3min | 29 | 1 | $1.83 | 3.0 | bash | ok |
| Test Results Aggregator | default | opus48-1m-high | 12.2min | 59 | 1 | $3.42 | 4.0 | python | ok |
| Environment Matrix Generator | bash | opus48-1m-high | 9.4min | 39 | 1 | $2.51 | 4.5 | bash | ok |
| Environment Matrix Generator | bash | opus48-1m-ultracode | 17.6min | 41 | 1 | $4.58 | 4.0 | bash | ok |
| Environment Matrix Generator | default | opus48-1m-ultracode | 22.7min | 70 | 1 | $6.54 | 5.0 | python | ok |
| Environment Matrix Generator | powershell | opus48-1m-high | 13.7min | 44 | 1 | $3.48 | 4.5 | powershell | ok |
| Environment Matrix Generator | powershell | opus48-1m-ultracode | 25.3min | 42 | 1 | $6.29 | 4.5 | powershell | ok |
| Environment Matrix Generator | typescript-bun | opus48-1m-xhigh | 25.3min | 77 | 1 | $7.25 | 4.5 | typescript | ok |
| Artifact Cleanup Script | bash | opus48-1m-medium | 11.4min | 53 | 1 | $3.16 | 2.5 | bash | ok |
| Artifact Cleanup Script | bash | opus48-1m-ultracode | 14.2min | 28 | 1 | $3.60 | 3.0 | bash | ok |
| Artifact Cleanup Script | powershell | opus48-1m-xhigh | 25.0min | 92 | 1 | $7.41 | 4.5 | powershell | ok |
| Artifact Cleanup Script | powershell | opus48-1m-high | 11.8min | 31 | 1 | $2.83 | 4.5 | powershell | ok |
| Artifact Cleanup Script | powershell | opus48-1m-medium | 11.9min | 46 | 1 | $2.91 | 4.0 | powershell | ok |
| Artifact Cleanup Script | powershell | opus48-1m-xhigh | 30.0min | 0 | 1 | $0.00 | 4.5 | powershell | timeout |
| Artifact Cleanup Script | typescript-bun | opus48-1m-high | 14.8min | 82 | 1 | $6.00 | 4.5 | typescript | ok |
| Secret Rotation Validator | powershell | opus48-1m-medium | 8.0min | 34 | 1 | $2.14 | 4.0 | powershell | ok |
| Secret Rotation Validator | typescript-bun | opus48-1m-high | 11.9min | 45 | 1 | $3.29 | 4.0 | typescript | ok |
| Semantic Version Bumper | bash | opus48-1m-xhigh | 18.1min | 47 | 2 | $4.91 | 3.0 | bash | ok |
| Semantic Version Bumper | powershell | opus48-1m-high | 16.9min | 60 | 2 | $3.59 | 4.5 | powershell | ok |
| Semantic Version Bumper | powershell | opus48-1m-ultracode | 31.9min | 65 | 2 | $13.39 | 4.5 | powershell | ok |
| Semantic Version Bumper | typescript-bun | opus48-1m-medium | 9.3min | 47 | 2 | $2.47 | 4.5 | typescript | ok |
| PR Label Assigner | bash | opus48-1m-ultracode | 18.6min | 55 | 2 | $5.24 | 4.5 | bash | ok |
| Dependency License Checker | bash | opus48-1m-xhigh | 23.9min | 96 | 2 | $8.01 | 3.5 | bash | ok |
| Test Results Aggregator | powershell | opus48-1m-xhigh | 25.9min | 67 | 2 | $6.67 | 4.5 | powershell | ok |
| Environment Matrix Generator | powershell | opus48-1m-medium | 12.9min | 52 | 2 | $3.60 | 4.5 | powershell | ok |
| Environment Matrix Generator | powershell | opus48-1m-ultracode | 26.7min | 49 | 2 | $6.39 | 5.0 | powershell | ok |
| Artifact Cleanup Script | bash | opus48-1m-xhigh | 18.1min | 49 | 2 | $5.08 | 4.5 | bash | ok |
| Artifact Cleanup Script | powershell | opus48-1m-high | 9.6min | 35 | 2 | $2.60 | 4.5 | powershell | ok |
| Artifact Cleanup Script | typescript-bun | opus48-1m-xhigh | 21.6min | 49 | 2 | $5.91 | 4.5 | typescript | ok |
| Secret Rotation Validator | bash | opus48-1m-ultracode | 26.1min | 52 | 2 | $5.71 | 4.5 | bash | ok |
| Secret Rotation Validator | typescript-bun | opus48-1m-medium | 23.0min | 78 | 2 | $4.51 | 4.5 | typescript | ok |
| Secret Rotation Validator | typescript-bun | opus48-1m-ultracode | 25.7min | 65 | 2 | $7.94 | 5.0 | typescript | ok |
| Semantic Version Bumper | typescript-bun | opus48-1m-xhigh | 22.3min | 71 | 3 | $6.51 | 4.5 | typescript | ok |
| Dependency License Checker | bash | opus48-1m-high | 15.0min | 51 | 3 | $4.02 | 4.5 | bash | ok |
| Test Results Aggregator | bash | opus48-1m-xhigh | 21.2min | 53 | 3 | $5.41 | 4.5 | bash | ok |
| PR Label Assigner | typescript-bun | opus48-1m-ultracode | 21.5min | 62 | 5 | $5.80 | 4.5 | typescript | ok |
| Dependency License Checker | powershell | opus48-1m-xhigh | 30.0min | 0 | 5 | $0.00 | 4.5 | powershell | timeout |
| Secret Rotation Validator | bash | opus48-1m-medium | 23.9min | 64 | 6 | $5.71 | 4.0 | bash | ok |

</details>

<details>
<summary>Sorted by turns (fewest first)</summary>

| Task | Language | Model | Duration | Turns | Errors | Cost | Tests Quality | Chosen | Status |
|------|----------|-------|----------|-------|--------|------|-----------|--------|--------|
| PR Label Assigner | powershell | opus48-1m-xhigh | 30.0min | 0 | 0 | $0.00 | 4.5 | powershell | timeout |
| Dependency License Checker | powershell | opus48-1m-xhigh | 30.0min | 0 | 5 | $0.00 | 4.5 | powershell | timeout |
| Environment Matrix Generator | powershell | opus48-1m-xhigh | 30.0min | 0 | 0 | $0.00 | 4.5 | powershell | timeout |
| Artifact Cleanup Script | powershell | opus48-1m-xhigh | 30.0min | 0 | 1 | $0.00 | 4.5 | powershell | timeout |
| Secret Rotation Validator | powershell | opus48-1m-medium | 1.1min | 11 | 0 | $0.55 | 4.0 | powershell | ok |
| PR Label Assigner | bash | opus48-1m-medium | 4.8min | 20 | 0 | $1.22 | 2.0 | bash | ok |
| Semantic Version Bumper | bash | opus48-1m-medium | 6.8min | 22 | 0 | $1.55 | 4.0 | bash | ok |
| PR Label Assigner | powershell | opus48-1m-medium | 6.3min | 23 | 0 | $1.52 | 4.5 | powershell | ok |
| Dependency License Checker | powershell | opus48-1m-ultracode | 4.3min | 23 | 0 | $1.21 | 4.5 | powershell | ok |
| Dependency License Checker | bash | opus48-1m-medium | 5.7min | 24 | 0 | $1.45 | 4.0 | bash | ok |
| Environment Matrix Generator | default | opus48-1m-high | 8.2min | 24 | 0 | $2.01 | 3.5 | python | ok |
| PR Label Assigner | default | opus48-1m-high | 7.1min | 25 | 1 | $1.86 | 4.0 | python | ok |
| PR Label Assigner | typescript-bun | opus48-1m-high | 3.0min | 26 | 1 | $1.17 | 4.0 | typescript | ok |
| Test Results Aggregator | default | opus48-1m-medium | 6.6min | 26 | 0 | $1.50 | 4.5 | python | ok |
| Semantic Version Bumper | default | opus48-1m-medium | 7.2min | 27 | 0 | $1.83 | 4.5 | python | ok |
| PR Label Assigner | powershell | opus48-1m-medium | 7.6min | 27 | 1 | $1.66 | 4.5 | powershell | ok |
| Environment Matrix Generator | bash | opus48-1m-medium | 5.8min | 27 | 0 | $1.72 | 3.5 | bash | ok |
| Environment Matrix Generator | powershell | opus48-1m-high | 9.2min | 27 | 0 | $3.06 | 4.5 | powershell | ok |
| Test Results Aggregator | bash | opus48-1m-high | 8.4min | 28 | 0 | $2.20 | 2.5 | bash | ok |
| Environment Matrix Generator | default | opus48-1m-medium | 6.7min | 28 | 0 | $2.01 | 3.5 | python | ok |
| Artifact Cleanup Script | bash | opus48-1m-ultracode | 14.2min | 28 | 1 | $3.60 | 3.0 | bash | ok |
| Artifact Cleanup Script | powershell | opus48-1m-medium | 9.3min | 28 | 0 | $2.26 | 4.5 | powershell | ok |
| PR Label Assigner | default | opus48-1m-xhigh | 9.8min | 29 | 0 | $2.66 | 4.5 | python | ok |
| Test Results Aggregator | bash | opus48-1m-medium | 6.3min | 29 | 1 | $1.83 | 3.0 | bash | ok |
| Test Results Aggregator | default | opus48-1m-ultracode | 13.4min | 29 | 0 | $3.22 | 4.5 | python | ok |
| Test Results Aggregator | powershell | opus48-1m-medium | 7.4min | 29 | 0 | $1.95 | 4.0 | powershell | ok |
| Secret Rotation Validator | default | opus48-1m-medium | 5.9min | 29 | 0 | $1.65 | 4.0 | python | ok |
| Test Results Aggregator | powershell | opus48-1m-medium | 8.1min | 30 | 0 | $1.77 | 4.5 | powershell | ok |
| PR Label Assigner | bash | opus48-1m-high | 10.1min | 31 | 0 | $2.45 | 4.5 | bash | ok |
| Artifact Cleanup Script | powershell | opus48-1m-high | 11.8min | 31 | 1 | $2.83 | 4.5 | powershell | ok |
| Dependency License Checker | default | opus48-1m-medium | 7.9min | 33 | 0 | $1.94 | 4.5 | python | ok |
| Dependency License Checker | powershell | opus48-1m-medium | 7.7min | 33 | 0 | $1.93 | 4.0 | powershell | ok |
| Dependency License Checker | powershell | opus48-1m-high | 12.2min | 33 | 0 | $2.63 | 4.5 | powershell | ok |
| Environment Matrix Generator | powershell | opus48-1m-medium | 9.3min | 33 | 0 | $2.29 | 4.5 | powershell | ok |
| Secret Rotation Validator | bash | opus48-1m-high | 9.4min | 33 | 0 | $2.38 | 4.5 | bash | ok |
| Secret Rotation Validator | powershell | opus48-1m-high | 15.2min | 33 | 0 | $3.22 | 4.5 | powershell | ok |
| Semantic Version Bumper | powershell | opus48-1m-medium | 10.0min | 34 | 0 | $2.33 | 4.0 | powershell | ok |
| Semantic Version Bumper | powershell | opus48-1m-high | 12.1min | 34 | 0 | $2.32 | 4.5 | powershell | ok |
| Dependency License Checker | default | opus48-1m-high | 9.0min | 34 | 0 | $2.24 | 2.0 | powershell | ok |
| Dependency License Checker | default | opus48-1m-xhigh | 13.6min | 34 | 0 | $3.67 | 4.5 | python | ok |
| Secret Rotation Validator | powershell | opus48-1m-medium | 8.0min | 34 | 1 | $2.14 | 4.0 | powershell | ok |
| Artifact Cleanup Script | powershell | opus48-1m-high | 9.6min | 35 | 2 | $2.60 | 4.5 | powershell | ok |
| PR Label Assigner | default | opus48-1m-medium | 8.2min | 36 | 1 | $1.91 | 4.0 | powershell | ok |
| Dependency License Checker | powershell | opus48-1m-ultracode | 19.2min | 36 | 0 | $4.57 | 4.5 | powershell | ok |
| Environment Matrix Generator | default | opus48-1m-xhigh | 16.2min | 38 | 0 | $4.05 | 3.5 | python | ok |
| Artifact Cleanup Script | powershell | opus48-1m-ultracode | 21.5min | 38 | 0 | $5.17 | 4.5 | powershell | ok |
| Test Results Aggregator | powershell | opus48-1m-xhigh | 18.2min | 39 | 0 | $4.52 | 4.0 | powershell | ok |
| Environment Matrix Generator | bash | opus48-1m-high | 9.4min | 39 | 1 | $2.51 | 4.5 | bash | ok |
| Semantic Version Bumper | powershell | opus48-1m-medium | 10.6min | 40 | 1 | $2.39 | 4.5 | powershell | ok |
| Environment Matrix Generator | typescript-bun | opus48-1m-medium | 9.1min | 40 | 0 | $2.29 | 4.5 | typescript | ok |
| Semantic Version Bumper | bash | opus48-1m-high | 9.5min | 41 | 1 | $2.70 | 4.5 | bash | ok |
| PR Label Assigner | powershell | opus48-1m-high | 11.4min | 41 | 0 | $2.78 | 4.0 | powershell | ok |
| Environment Matrix Generator | bash | opus48-1m-ultracode | 17.6min | 41 | 1 | $4.58 | 4.0 | bash | ok |
| Dependency License Checker | powershell | opus48-1m-high | 12.8min | 42 | 1 | $3.09 | 4.5 | powershell | ok |
| Environment Matrix Generator | powershell | opus48-1m-ultracode | 25.3min | 42 | 1 | $6.29 | 4.5 | powershell | ok |
| Semantic Version Bumper | default | opus48-1m-ultracode | 14.6min | 43 | 0 | $4.35 | 4.5 | python | ok |
| Artifact Cleanup Script | default | opus48-1m-medium | 9.9min | 43 | 0 | $2.37 | 4.0 | powershell | ok |
| PR Label Assigner | typescript-bun | opus48-1m-medium | 13.1min | 44 | 0 | $2.48 | 4.5 | typescript | ok |
| Environment Matrix Generator | powershell | opus48-1m-high | 13.7min | 44 | 1 | $3.48 | 4.5 | powershell | ok |
| Artifact Cleanup Script | typescript-bun | opus48-1m-medium | 9.2min | 44 | 0 | $2.44 | 4.0 | typescript | ok |
| Dependency License Checker | typescript-bun | opus48-1m-medium | 8.7min | 45 | 0 | $2.33 | 4.0 | typescript | ok |
| Test Results Aggregator | typescript-bun | opus48-1m-medium | 9.2min | 45 | 0 | $2.57 | 4.5 | typescript | ok |
| Secret Rotation Validator | typescript-bun | opus48-1m-high | 11.9min | 45 | 1 | $3.29 | 4.0 | typescript | ok |
| Test Results Aggregator | bash | opus48-1m-ultracode | 17.5min | 46 | 0 | $5.53 | 3.0 | bash | ok |
| Test Results Aggregator | typescript-bun | opus48-1m-xhigh | 16.4min | 46 | 0 | $4.37 | 4.5 | typescript | ok |
| Artifact Cleanup Script | powershell | opus48-1m-medium | 11.9min | 46 | 1 | $2.91 | 4.0 | powershell | ok |
| Secret Rotation Validator | default | opus48-1m-xhigh | 15.6min | 46 | 0 | $4.15 | 4.5 | python | ok |
| Semantic Version Bumper | bash | opus48-1m-xhigh | 18.1min | 47 | 2 | $4.91 | 3.0 | bash | ok |
| Semantic Version Bumper | typescript-bun | opus48-1m-medium | 9.3min | 47 | 2 | $2.47 | 4.5 | typescript | ok |
| PR Label Assigner | powershell | opus48-1m-high | 11.0min | 47 | 0 | $2.65 | 4.5 | powershell | ok |
| Dependency License Checker | typescript-bun | opus48-1m-high | 11.5min | 47 | 0 | $3.04 | 4.5 | typescript | ok |
| Test Results Aggregator | powershell | opus48-1m-high | 15.2min | 47 | 0 | $3.39 | 4.5 | powershell | ok |
| Test Results Aggregator | powershell | opus48-1m-ultracode | 20.5min | 47 | 0 | $5.53 | 4.5 | powershell | ok |
| Artifact Cleanup Script | bash | opus48-1m-high | 11.6min | 47 | 0 | $3.32 | 5.0 | bash | ok |
| Secret Rotation Validator | default | opus48-1m-high | 9.1min | 47 | 0 | $3.12 | 4.0 | python | ok |
| Dependency License Checker | typescript-bun | opus48-1m-xhigh | 19.6min | 48 | 0 | $5.16 | 4.5 | typescript | ok |
| Test Results Aggregator | powershell | opus48-1m-ultracode | 24.6min | 48 | 0 | $6.88 | 4.0 | powershell | ok |
| Dependency License Checker | powershell | opus48-1m-medium | 12.7min | 49 | 0 | $3.35 | 3.5 | powershell | ok |
| Dependency License Checker | powershell | opus48-1m-xhigh | 25.2min | 49 | 0 | $6.38 | 4.5 | powershell | ok |
| Environment Matrix Generator | powershell | opus48-1m-ultracode | 26.7min | 49 | 2 | $6.39 | 5.0 | powershell | ok |
| Artifact Cleanup Script | bash | opus48-1m-xhigh | 18.1min | 49 | 2 | $5.08 | 4.5 | bash | ok |
| Artifact Cleanup Script | typescript-bun | opus48-1m-xhigh | 21.6min | 49 | 2 | $5.91 | 4.5 | typescript | ok |
| Semantic Version Bumper | default | opus48-1m-xhigh | 15.3min | 50 | 1 | $4.59 | 4.5 | python | ok |
| PR Label Assigner | powershell | opus48-1m-ultracode | 22.3min | 50 | 1 | $5.54 | 4.5 | powershell | ok |
| Artifact Cleanup Script | default | opus48-1m-high | 10.2min | 50 | 0 | $3.16 | 4.5 | python | ok |
| PR Label Assigner | default | opus48-1m-ultracode | 12.6min | 51 | 0 | $4.18 | 4.0 | python | ok |
| Dependency License Checker | bash | opus48-1m-high | 15.0min | 51 | 3 | $4.02 | 4.5 | bash | ok |
| Artifact Cleanup Script | typescript-bun | opus48-1m-ultracode | 19.2min | 51 | 0 | $4.98 | 4.5 | typescript | ok |
| Semantic Version Bumper | default | opus48-1m-high | 9.8min | 52 | 0 | $3.34 | 2.0 | javascript | ok |
| Semantic Version Bumper | typescript-bun | opus48-1m-high | 11.5min | 52 | 0 | $3.14 | 4.0 | typescript | ok |
| PR Label Assigner | powershell | opus48-1m-ultracode | 21.3min | 52 | 0 | $5.68 | 4.5 | powershell | ok |
| Dependency License Checker | typescript-bun | opus48-1m-ultracode | 17.8min | 52 | 0 | $4.95 | 4.0 | typescript | ok |
| Environment Matrix Generator | powershell | opus48-1m-medium | 12.9min | 52 | 2 | $3.60 | 4.5 | powershell | ok |
| Secret Rotation Validator | bash | opus48-1m-ultracode | 26.1min | 52 | 2 | $5.71 | 4.5 | bash | ok |
| Secret Rotation Validator | powershell | opus48-1m-ultracode | 30.9min | 52 | 0 | $7.74 | 4.0 | powershell | ok |
| Test Results Aggregator | bash | opus48-1m-xhigh | 21.2min | 53 | 3 | $5.41 | 4.5 | bash | ok |
| Artifact Cleanup Script | bash | opus48-1m-medium | 11.4min | 53 | 1 | $3.16 | 2.5 | bash | ok |
| Secret Rotation Validator | powershell | opus48-1m-high | 15.4min | 53 | 0 | $3.46 | 4.5 | powershell | ok |
| Secret Rotation Validator | typescript-bun | opus48-1m-xhigh | 17.5min | 54 | 0 | $5.12 | 4.5 | typescript | ok |
| PR Label Assigner | bash | opus48-1m-ultracode | 18.6min | 55 | 2 | $5.24 | 4.5 | bash | ok |
| Artifact Cleanup Script | default | opus48-1m-ultracode | 15.8min | 55 | 0 | $4.99 | 5.0 | python | ok |
| Secret Rotation Validator | bash | opus48-1m-xhigh | 21.4min | 55 | 0 | $5.41 | 4.5 | bash | ok |
| Secret Rotation Validator | default | opus48-1m-ultracode | 18.9min | 55 | 0 | $5.63 | 4.5 | python | ok |
| Environment Matrix Generator | typescript-bun | opus48-1m-ultracode | 21.2min | 56 | 0 | $5.58 | 4.0 | typescript | ok |
| Semantic Version Bumper | powershell | opus48-1m-ultracode | 25.2min | 58 | 0 | $6.83 | 4.5 | powershell | ok |
| Environment Matrix Generator | powershell | opus48-1m-xhigh | 28.4min | 58 | 0 | $7.16 | 4.0 | powershell | ok |
| Test Results Aggregator | default | opus48-1m-high | 12.2min | 59 | 1 | $3.42 | 4.0 | python | ok |
| Test Results Aggregator | powershell | opus48-1m-high | 17.3min | 59 | 0 | $3.84 | 4.5 | powershell | ok |
| Environment Matrix Generator | bash | opus48-1m-xhigh | 18.6min | 59 | 0 | $5.52 | 4.0 | bash | ok |
| Semantic Version Bumper | powershell | opus48-1m-high | 16.9min | 60 | 2 | $3.59 | 4.5 | powershell | ok |
| Secret Rotation Validator | powershell | opus48-1m-xhigh | 19.5min | 60 | 0 | $5.52 | 4.0 | powershell | ok |
| Semantic Version Bumper | powershell | opus48-1m-xhigh | 21.0min | 61 | 1 | $5.56 | 4.5 | powershell | ok |
| PR Label Assigner | typescript-bun | opus48-1m-ultracode | 21.5min | 62 | 5 | $5.80 | 4.5 | typescript | ok |
| PR Label Assigner | powershell | opus48-1m-xhigh | 19.4min | 63 | 0 | $5.67 | 4.5 | powershell | ok |
| Test Results Aggregator | default | opus48-1m-xhigh | 17.2min | 63 | 0 | $5.38 | 4.5 | python | ok |
| PR Label Assigner | bash | opus48-1m-xhigh | 20.5min | 64 | 0 | $5.87 | 4.5 | bash | ok |
| Secret Rotation Validator | bash | opus48-1m-medium | 23.9min | 64 | 6 | $5.71 | 4.0 | bash | ok |
| Semantic Version Bumper | powershell | opus48-1m-ultracode | 31.9min | 65 | 2 | $13.39 | 4.5 | powershell | ok |
| Secret Rotation Validator | typescript-bun | opus48-1m-ultracode | 25.7min | 65 | 2 | $7.94 | 5.0 | typescript | ok |
| Dependency License Checker | default | opus48-1m-ultracode | 21.3min | 67 | 0 | $5.41 | 4.5 | powershell | ok |
| Test Results Aggregator | powershell | opus48-1m-xhigh | 25.9min | 67 | 2 | $6.67 | 4.5 | powershell | ok |
| Artifact Cleanup Script | powershell | opus48-1m-ultracode | 29.4min | 67 | 0 | $8.16 | 4.5 | powershell | ok |
| Semantic Version Bumper | powershell | opus48-1m-xhigh | 21.0min | 69 | 1 | $6.19 | 4.5 | powershell | ok |
| Test Results Aggregator | typescript-bun | opus48-1m-high | 19.2min | 69 | 0 | $5.19 | 4.5 | typescript | ok |
| Environment Matrix Generator | typescript-bun | opus48-1m-high | 13.3min | 69 | 0 | $3.94 | 4.5 | typescript | ok |
| Environment Matrix Generator | default | opus48-1m-ultracode | 22.7min | 70 | 1 | $6.54 | 5.0 | python | ok |
| Semantic Version Bumper | typescript-bun | opus48-1m-xhigh | 22.3min | 71 | 3 | $6.51 | 4.5 | typescript | ok |
| Dependency License Checker | bash | opus48-1m-ultracode | 24.3min | 71 | 1 | $6.98 | 4.0 | bash | ok |
| PR Label Assigner | typescript-bun | opus48-1m-xhigh | 19.8min | 72 | 0 | $6.01 | 3.5 | typescript | ok |
| Semantic Version Bumper | bash | opus48-1m-ultracode | 20.8min | 74 | 0 | $6.09 | 4.5 | bash | ok |
| Secret Rotation Validator | powershell | opus48-1m-ultracode | 33.6min | 74 | 0 | $9.44 | 4.5 | powershell | ok |
| Environment Matrix Generator | typescript-bun | opus48-1m-xhigh | 25.3min | 77 | 1 | $7.25 | 4.5 | typescript | ok |
| Artifact Cleanup Script | default | opus48-1m-xhigh | 19.1min | 77 | 0 | $6.84 | 4.5 | python | ok |
| Secret Rotation Validator | powershell | opus48-1m-xhigh | 26.1min | 78 | 0 | $7.45 | 4.5 | powershell | ok |
| Secret Rotation Validator | typescript-bun | opus48-1m-medium | 23.0min | 78 | 2 | $4.51 | 4.5 | typescript | ok |
| Test Results Aggregator | typescript-bun | opus48-1m-ultracode | 32.3min | 79 | 0 | $10.28 | 5.0 | typescript | ok |
| Artifact Cleanup Script | typescript-bun | opus48-1m-high | 14.8min | 82 | 1 | $6.00 | 4.5 | typescript | ok |
| Artifact Cleanup Script | powershell | opus48-1m-xhigh | 25.0min | 92 | 1 | $7.41 | 4.5 | powershell | ok |
| Dependency License Checker | bash | opus48-1m-xhigh | 23.9min | 96 | 2 | $8.01 | 3.5 | bash | ok |
| Semantic Version Bumper | typescript-bun | opus48-1m-ultracode | 30.6min | 104 | 0 | $11.91 | 4.5 | typescript | ok |

</details>

<details>
<summary>Sorted by LLM-as-judge score (best first)</summary>

| Task | Language | Model | Duration | Turns | Errors | Cost | Tests Quality | Chosen | Status |
|------|----------|-------|----------|-------|--------|------|-----------|--------|--------|
| Test Results Aggregator | typescript-bun | opus48-1m-ultracode | 32.3min | 79 | 0 | $10.28 | 5.0 | typescript | ok |
| Environment Matrix Generator | default | opus48-1m-ultracode | 22.7min | 70 | 1 | $6.54 | 5.0 | python | ok |
| Environment Matrix Generator | powershell | opus48-1m-ultracode | 26.7min | 49 | 2 | $6.39 | 5.0 | powershell | ok |
| Artifact Cleanup Script | bash | opus48-1m-high | 11.6min | 47 | 0 | $3.32 | 5.0 | bash | ok |
| Artifact Cleanup Script | default | opus48-1m-ultracode | 15.8min | 55 | 0 | $4.99 | 5.0 | python | ok |
| Secret Rotation Validator | typescript-bun | opus48-1m-ultracode | 25.7min | 65 | 2 | $7.94 | 5.0 | typescript | ok |
| Semantic Version Bumper | bash | opus48-1m-high | 9.5min | 41 | 1 | $2.70 | 4.5 | bash | ok |
| Semantic Version Bumper | bash | opus48-1m-ultracode | 20.8min | 74 | 0 | $6.09 | 4.5 | bash | ok |
| Semantic Version Bumper | default | opus48-1m-medium | 7.2min | 27 | 0 | $1.83 | 4.5 | python | ok |
| Semantic Version Bumper | default | opus48-1m-ultracode | 14.6min | 43 | 0 | $4.35 | 4.5 | python | ok |
| Semantic Version Bumper | default | opus48-1m-xhigh | 15.3min | 50 | 1 | $4.59 | 4.5 | python | ok |
| Semantic Version Bumper | powershell | opus48-1m-high | 16.9min | 60 | 2 | $3.59 | 4.5 | powershell | ok |
| Semantic Version Bumper | powershell | opus48-1m-ultracode | 31.9min | 65 | 2 | $13.39 | 4.5 | powershell | ok |
| Semantic Version Bumper | powershell | opus48-1m-xhigh | 21.0min | 69 | 1 | $6.19 | 4.5 | powershell | ok |
| Semantic Version Bumper | powershell | opus48-1m-high | 12.1min | 34 | 0 | $2.32 | 4.5 | powershell | ok |
| Semantic Version Bumper | powershell | opus48-1m-medium | 10.6min | 40 | 1 | $2.39 | 4.5 | powershell | ok |
| Semantic Version Bumper | powershell | opus48-1m-ultracode | 25.2min | 58 | 0 | $6.83 | 4.5 | powershell | ok |
| Semantic Version Bumper | powershell | opus48-1m-xhigh | 21.0min | 61 | 1 | $5.56 | 4.5 | powershell | ok |
| Semantic Version Bumper | typescript-bun | opus48-1m-medium | 9.3min | 47 | 2 | $2.47 | 4.5 | typescript | ok |
| Semantic Version Bumper | typescript-bun | opus48-1m-ultracode | 30.6min | 104 | 0 | $11.91 | 4.5 | typescript | ok |
| Semantic Version Bumper | typescript-bun | opus48-1m-xhigh | 22.3min | 71 | 3 | $6.51 | 4.5 | typescript | ok |
| PR Label Assigner | bash | opus48-1m-high | 10.1min | 31 | 0 | $2.45 | 4.5 | bash | ok |
| PR Label Assigner | bash | opus48-1m-ultracode | 18.6min | 55 | 2 | $5.24 | 4.5 | bash | ok |
| PR Label Assigner | bash | opus48-1m-xhigh | 20.5min | 64 | 0 | $5.87 | 4.5 | bash | ok |
| PR Label Assigner | default | opus48-1m-xhigh | 9.8min | 29 | 0 | $2.66 | 4.5 | python | ok |
| PR Label Assigner | powershell | opus48-1m-high | 11.0min | 47 | 0 | $2.65 | 4.5 | powershell | ok |
| PR Label Assigner | powershell | opus48-1m-medium | 6.3min | 23 | 0 | $1.52 | 4.5 | powershell | ok |
| PR Label Assigner | powershell | opus48-1m-ultracode | 21.3min | 52 | 0 | $5.68 | 4.5 | powershell | ok |
| PR Label Assigner | powershell | opus48-1m-xhigh | 19.4min | 63 | 0 | $5.67 | 4.5 | powershell | ok |
| PR Label Assigner | powershell | opus48-1m-medium | 7.6min | 27 | 1 | $1.66 | 4.5 | powershell | ok |
| PR Label Assigner | powershell | opus48-1m-ultracode | 22.3min | 50 | 1 | $5.54 | 4.5 | powershell | ok |
| PR Label Assigner | powershell | opus48-1m-xhigh | 30.0min | 0 | 0 | $0.00 | 4.5 | powershell | timeout |
| PR Label Assigner | typescript-bun | opus48-1m-medium | 13.1min | 44 | 0 | $2.48 | 4.5 | typescript | ok |
| PR Label Assigner | typescript-bun | opus48-1m-ultracode | 21.5min | 62 | 5 | $5.80 | 4.5 | typescript | ok |
| Dependency License Checker | bash | opus48-1m-high | 15.0min | 51 | 3 | $4.02 | 4.5 | bash | ok |
| Dependency License Checker | default | opus48-1m-medium | 7.9min | 33 | 0 | $1.94 | 4.5 | python | ok |
| Dependency License Checker | default | opus48-1m-ultracode | 21.3min | 67 | 0 | $5.41 | 4.5 | powershell | ok |
| Dependency License Checker | default | opus48-1m-xhigh | 13.6min | 34 | 0 | $3.67 | 4.5 | python | ok |
| Dependency License Checker | powershell | opus48-1m-high | 12.8min | 42 | 1 | $3.09 | 4.5 | powershell | ok |
| Dependency License Checker | powershell | opus48-1m-ultracode | 4.3min | 23 | 0 | $1.21 | 4.5 | powershell | ok |
| Dependency License Checker | powershell | opus48-1m-xhigh | 30.0min | 0 | 5 | $0.00 | 4.5 | powershell | timeout |
| Dependency License Checker | powershell | opus48-1m-high | 12.2min | 33 | 0 | $2.63 | 4.5 | powershell | ok |
| Dependency License Checker | powershell | opus48-1m-ultracode | 19.2min | 36 | 0 | $4.57 | 4.5 | powershell | ok |
| Dependency License Checker | powershell | opus48-1m-xhigh | 25.2min | 49 | 0 | $6.38 | 4.5 | powershell | ok |
| Dependency License Checker | typescript-bun | opus48-1m-high | 11.5min | 47 | 0 | $3.04 | 4.5 | typescript | ok |
| Dependency License Checker | typescript-bun | opus48-1m-xhigh | 19.6min | 48 | 0 | $5.16 | 4.5 | typescript | ok |
| Test Results Aggregator | bash | opus48-1m-xhigh | 21.2min | 53 | 3 | $5.41 | 4.5 | bash | ok |
| Test Results Aggregator | default | opus48-1m-medium | 6.6min | 26 | 0 | $1.50 | 4.5 | python | ok |
| Test Results Aggregator | default | opus48-1m-ultracode | 13.4min | 29 | 0 | $3.22 | 4.5 | python | ok |
| Test Results Aggregator | default | opus48-1m-xhigh | 17.2min | 63 | 0 | $5.38 | 4.5 | python | ok |
| Test Results Aggregator | powershell | opus48-1m-high | 17.3min | 59 | 0 | $3.84 | 4.5 | powershell | ok |
| Test Results Aggregator | powershell | opus48-1m-medium | 8.1min | 30 | 0 | $1.77 | 4.5 | powershell | ok |
| Test Results Aggregator | powershell | opus48-1m-high | 15.2min | 47 | 0 | $3.39 | 4.5 | powershell | ok |
| Test Results Aggregator | powershell | opus48-1m-ultracode | 20.5min | 47 | 0 | $5.53 | 4.5 | powershell | ok |
| Test Results Aggregator | powershell | opus48-1m-xhigh | 25.9min | 67 | 2 | $6.67 | 4.5 | powershell | ok |
| Test Results Aggregator | typescript-bun | opus48-1m-high | 19.2min | 69 | 0 | $5.19 | 4.5 | typescript | ok |
| Test Results Aggregator | typescript-bun | opus48-1m-medium | 9.2min | 45 | 0 | $2.57 | 4.5 | typescript | ok |
| Test Results Aggregator | typescript-bun | opus48-1m-xhigh | 16.4min | 46 | 0 | $4.37 | 4.5 | typescript | ok |
| Environment Matrix Generator | bash | opus48-1m-high | 9.4min | 39 | 1 | $2.51 | 4.5 | bash | ok |
| Environment Matrix Generator | powershell | opus48-1m-high | 13.7min | 44 | 1 | $3.48 | 4.5 | powershell | ok |
| Environment Matrix Generator | powershell | opus48-1m-medium | 9.3min | 33 | 0 | $2.29 | 4.5 | powershell | ok |
| Environment Matrix Generator | powershell | opus48-1m-ultracode | 25.3min | 42 | 1 | $6.29 | 4.5 | powershell | ok |
| Environment Matrix Generator | powershell | opus48-1m-high | 9.2min | 27 | 0 | $3.06 | 4.5 | powershell | ok |
| Environment Matrix Generator | powershell | opus48-1m-medium | 12.9min | 52 | 2 | $3.60 | 4.5 | powershell | ok |
| Environment Matrix Generator | powershell | opus48-1m-xhigh | 30.0min | 0 | 0 | $0.00 | 4.5 | powershell | timeout |
| Environment Matrix Generator | typescript-bun | opus48-1m-high | 13.3min | 69 | 0 | $3.94 | 4.5 | typescript | ok |
| Environment Matrix Generator | typescript-bun | opus48-1m-medium | 9.1min | 40 | 0 | $2.29 | 4.5 | typescript | ok |
| Environment Matrix Generator | typescript-bun | opus48-1m-xhigh | 25.3min | 77 | 1 | $7.25 | 4.5 | typescript | ok |
| Artifact Cleanup Script | bash | opus48-1m-xhigh | 18.1min | 49 | 2 | $5.08 | 4.5 | bash | ok |
| Artifact Cleanup Script | default | opus48-1m-high | 10.2min | 50 | 0 | $3.16 | 4.5 | python | ok |
| Artifact Cleanup Script | default | opus48-1m-xhigh | 19.1min | 77 | 0 | $6.84 | 4.5 | python | ok |
| Artifact Cleanup Script | powershell | opus48-1m-high | 9.6min | 35 | 2 | $2.60 | 4.5 | powershell | ok |
| Artifact Cleanup Script | powershell | opus48-1m-medium | 9.3min | 28 | 0 | $2.26 | 4.5 | powershell | ok |
| Artifact Cleanup Script | powershell | opus48-1m-ultracode | 21.5min | 38 | 0 | $5.17 | 4.5 | powershell | ok |
| Artifact Cleanup Script | powershell | opus48-1m-xhigh | 25.0min | 92 | 1 | $7.41 | 4.5 | powershell | ok |
| Artifact Cleanup Script | powershell | opus48-1m-high | 11.8min | 31 | 1 | $2.83 | 4.5 | powershell | ok |
| Artifact Cleanup Script | powershell | opus48-1m-ultracode | 29.4min | 67 | 0 | $8.16 | 4.5 | powershell | ok |
| Artifact Cleanup Script | powershell | opus48-1m-xhigh | 30.0min | 0 | 1 | $0.00 | 4.5 | powershell | timeout |
| Artifact Cleanup Script | typescript-bun | opus48-1m-high | 14.8min | 82 | 1 | $6.00 | 4.5 | typescript | ok |
| Artifact Cleanup Script | typescript-bun | opus48-1m-ultracode | 19.2min | 51 | 0 | $4.98 | 4.5 | typescript | ok |
| Artifact Cleanup Script | typescript-bun | opus48-1m-xhigh | 21.6min | 49 | 2 | $5.91 | 4.5 | typescript | ok |
| Secret Rotation Validator | bash | opus48-1m-high | 9.4min | 33 | 0 | $2.38 | 4.5 | bash | ok |
| Secret Rotation Validator | bash | opus48-1m-ultracode | 26.1min | 52 | 2 | $5.71 | 4.5 | bash | ok |
| Secret Rotation Validator | bash | opus48-1m-xhigh | 21.4min | 55 | 0 | $5.41 | 4.5 | bash | ok |
| Secret Rotation Validator | default | opus48-1m-ultracode | 18.9min | 55 | 0 | $5.63 | 4.5 | python | ok |
| Secret Rotation Validator | default | opus48-1m-xhigh | 15.6min | 46 | 0 | $4.15 | 4.5 | python | ok |
| Secret Rotation Validator | powershell | opus48-1m-high | 15.4min | 53 | 0 | $3.46 | 4.5 | powershell | ok |
| Secret Rotation Validator | powershell | opus48-1m-ultracode | 33.6min | 74 | 0 | $9.44 | 4.5 | powershell | ok |
| Secret Rotation Validator | powershell | opus48-1m-high | 15.2min | 33 | 0 | $3.22 | 4.5 | powershell | ok |
| Secret Rotation Validator | powershell | opus48-1m-xhigh | 26.1min | 78 | 0 | $7.45 | 4.5 | powershell | ok |
| Secret Rotation Validator | typescript-bun | opus48-1m-medium | 23.0min | 78 | 2 | $4.51 | 4.5 | typescript | ok |
| Secret Rotation Validator | typescript-bun | opus48-1m-xhigh | 17.5min | 54 | 0 | $5.12 | 4.5 | typescript | ok |
| Semantic Version Bumper | bash | opus48-1m-medium | 6.8min | 22 | 0 | $1.55 | 4.0 | bash | ok |
| Semantic Version Bumper | powershell | opus48-1m-medium | 10.0min | 34 | 0 | $2.33 | 4.0 | powershell | ok |
| Semantic Version Bumper | typescript-bun | opus48-1m-high | 11.5min | 52 | 0 | $3.14 | 4.0 | typescript | ok |
| PR Label Assigner | default | opus48-1m-high | 7.1min | 25 | 1 | $1.86 | 4.0 | python | ok |
| PR Label Assigner | default | opus48-1m-medium | 8.2min | 36 | 1 | $1.91 | 4.0 | powershell | ok |
| PR Label Assigner | default | opus48-1m-ultracode | 12.6min | 51 | 0 | $4.18 | 4.0 | python | ok |
| PR Label Assigner | powershell | opus48-1m-high | 11.4min | 41 | 0 | $2.78 | 4.0 | powershell | ok |
| PR Label Assigner | typescript-bun | opus48-1m-high | 3.0min | 26 | 1 | $1.17 | 4.0 | typescript | ok |
| Dependency License Checker | bash | opus48-1m-medium | 5.7min | 24 | 0 | $1.45 | 4.0 | bash | ok |
| Dependency License Checker | bash | opus48-1m-ultracode | 24.3min | 71 | 1 | $6.98 | 4.0 | bash | ok |
| Dependency License Checker | powershell | opus48-1m-medium | 7.7min | 33 | 0 | $1.93 | 4.0 | powershell | ok |
| Dependency License Checker | typescript-bun | opus48-1m-medium | 8.7min | 45 | 0 | $2.33 | 4.0 | typescript | ok |
| Dependency License Checker | typescript-bun | opus48-1m-ultracode | 17.8min | 52 | 0 | $4.95 | 4.0 | typescript | ok |
| Test Results Aggregator | default | opus48-1m-high | 12.2min | 59 | 1 | $3.42 | 4.0 | python | ok |
| Test Results Aggregator | powershell | opus48-1m-ultracode | 24.6min | 48 | 0 | $6.88 | 4.0 | powershell | ok |
| Test Results Aggregator | powershell | opus48-1m-xhigh | 18.2min | 39 | 0 | $4.52 | 4.0 | powershell | ok |
| Test Results Aggregator | powershell | opus48-1m-medium | 7.4min | 29 | 0 | $1.95 | 4.0 | powershell | ok |
| Environment Matrix Generator | bash | opus48-1m-ultracode | 17.6min | 41 | 1 | $4.58 | 4.0 | bash | ok |
| Environment Matrix Generator | bash | opus48-1m-xhigh | 18.6min | 59 | 0 | $5.52 | 4.0 | bash | ok |
| Environment Matrix Generator | powershell | opus48-1m-xhigh | 28.4min | 58 | 0 | $7.16 | 4.0 | powershell | ok |
| Environment Matrix Generator | typescript-bun | opus48-1m-ultracode | 21.2min | 56 | 0 | $5.58 | 4.0 | typescript | ok |
| Artifact Cleanup Script | default | opus48-1m-medium | 9.9min | 43 | 0 | $2.37 | 4.0 | powershell | ok |
| Artifact Cleanup Script | powershell | opus48-1m-medium | 11.9min | 46 | 1 | $2.91 | 4.0 | powershell | ok |
| Artifact Cleanup Script | typescript-bun | opus48-1m-medium | 9.2min | 44 | 0 | $2.44 | 4.0 | typescript | ok |
| Secret Rotation Validator | bash | opus48-1m-medium | 23.9min | 64 | 6 | $5.71 | 4.0 | bash | ok |
| Secret Rotation Validator | default | opus48-1m-high | 9.1min | 47 | 0 | $3.12 | 4.0 | python | ok |
| Secret Rotation Validator | default | opus48-1m-medium | 5.9min | 29 | 0 | $1.65 | 4.0 | python | ok |
| Secret Rotation Validator | powershell | opus48-1m-medium | 1.1min | 11 | 0 | $0.55 | 4.0 | powershell | ok |
| Secret Rotation Validator | powershell | opus48-1m-xhigh | 19.5min | 60 | 0 | $5.52 | 4.0 | powershell | ok |
| Secret Rotation Validator | powershell | opus48-1m-medium | 8.0min | 34 | 1 | $2.14 | 4.0 | powershell | ok |
| Secret Rotation Validator | powershell | opus48-1m-ultracode | 30.9min | 52 | 0 | $7.74 | 4.0 | powershell | ok |
| Secret Rotation Validator | typescript-bun | opus48-1m-high | 11.9min | 45 | 1 | $3.29 | 4.0 | typescript | ok |
| PR Label Assigner | typescript-bun | opus48-1m-xhigh | 19.8min | 72 | 0 | $6.01 | 3.5 | typescript | ok |
| Dependency License Checker | bash | opus48-1m-xhigh | 23.9min | 96 | 2 | $8.01 | 3.5 | bash | ok |
| Dependency License Checker | powershell | opus48-1m-medium | 12.7min | 49 | 0 | $3.35 | 3.5 | powershell | ok |
| Environment Matrix Generator | bash | opus48-1m-medium | 5.8min | 27 | 0 | $1.72 | 3.5 | bash | ok |
| Environment Matrix Generator | default | opus48-1m-high | 8.2min | 24 | 0 | $2.01 | 3.5 | python | ok |
| Environment Matrix Generator | default | opus48-1m-medium | 6.7min | 28 | 0 | $2.01 | 3.5 | python | ok |
| Environment Matrix Generator | default | opus48-1m-xhigh | 16.2min | 38 | 0 | $4.05 | 3.5 | python | ok |
| Semantic Version Bumper | bash | opus48-1m-xhigh | 18.1min | 47 | 2 | $4.91 | 3.0 | bash | ok |
| Test Results Aggregator | bash | opus48-1m-medium | 6.3min | 29 | 1 | $1.83 | 3.0 | bash | ok |
| Test Results Aggregator | bash | opus48-1m-ultracode | 17.5min | 46 | 0 | $5.53 | 3.0 | bash | ok |
| Artifact Cleanup Script | bash | opus48-1m-ultracode | 14.2min | 28 | 1 | $3.60 | 3.0 | bash | ok |
| Test Results Aggregator | bash | opus48-1m-high | 8.4min | 28 | 0 | $2.20 | 2.5 | bash | ok |
| Artifact Cleanup Script | bash | opus48-1m-medium | 11.4min | 53 | 1 | $3.16 | 2.5 | bash | ok |
| Semantic Version Bumper | default | opus48-1m-high | 9.8min | 52 | 0 | $3.34 | 2.0 | javascript | ok |
| PR Label Assigner | bash | opus48-1m-medium | 4.8min | 20 | 0 | $1.22 | 2.0 | bash | ok |
| Dependency License Checker | default | opus48-1m-high | 9.0min | 34 | 0 | $2.24 | 2.0 | powershell | ok |

</details>

## Notes

### Tiers

- **Duration bands:** **A+** ≤1.11×, **A** ≤1.22×, **A-** ≤1.35×, **B+** ≤1.49×, **B** ≤1.65×, **B-** ≤1.83×, **C+** ≤2.02×, **C** ≤2.23×, **C-** ≤2.47×, **D+** ≤2.73×, **D** ≤3.01×, **D-** ≤3.33×, **F** >3.33×
- **Cost bands:** **A+** ≤1.12×, **A** ≤1.24×, **A-** ≤1.39×, **B+** ≤1.55×, **B** ≤1.73×, **B-** ≤1.93×, **C+** ≤2.15×, **C** ≤2.40×, **C-** ≤2.67×, **D+** ≤2.98×, **D** ≤3.33×, **D-** ≤3.71×, **F** >3.71×

*Tests/Workflow Craft bands are absolute Overall score bands:* **A+** ≥4.7, **A** ≥4.4, **A-** ≥4.1, **B+** ≥3.8, **B** ≥3.5, **B-** ≥3.2, **C+** ≥2.9, **C** ≥2.6, **C-** ≥2.3, **D+** ≥2.0, **D** ≥1.7, **D-** ≥1.4, **F** <1.4, `—` = no data.*

### CLI Version Legend

| Variant label | CLI version | Tasks | Languages |
|---------------|-------------|-------|-----------|
| opus48-1m-high | 2.1.195 | All | All |
| opus48-1m-medium | 2.1.193 | 11-semantic-version-bumper, 12-pr-label-assigner, 13-dependency-license-checker, 15-test-results-aggregator, 16-environment-matrix-generator | All |
| opus48-1m-medium | 2.1.195 | 16-environment-matrix-generator, 17-artifact-cleanup-script, 18-secret-rotation-validator | All |
| opus48-1m-ultracode | 2.1.195 | All | All |
| opus48-1m-xhigh | 2.1.195 | All | All |

### Judge Consistency Summary

**🟡 The panel is doing its job on Tests Quality but hitting a ceiling on Workflow Craft:** the two judges agree on model rankings (ρ = +1.00), language rankings (ρ = +0.90), and language×model rankings (ρ = +0.72) for tests, and both put Bash last on every axis — but on Workflow Craft, Gemini scores nearly every non-Bash language at the 5.00 ceiling, collapsing its ability to differentiate and dragging language agreement down to ρ = +0.10. No self-judgment rows exceeded the deviation threshold, so there is no own-model preference signal.

- 👀 **Where to look closer:** the widest single-run disagreement (a judge scoring 1 vs 5, a 4-point gap on a 1–5 scale) is 17-artifact-cleanup-script / bash / opus48-1m-xhigh on Workflow Craft; also worth eyeballing 12-pr-label-assigner / typescript-bun / opus48-1m-xhigh on Tests Quality (Haiku 2, Gemini 5).
- 🤓 **Surprise finding:** on Workflow Craft the panel reverses on which model is best (Haiku prefers opus48-1m, Gemini prefers ultracode), but with means of 3.22 vs 3.18 and 4.92 vs 4.94 it is a coin-flip inside Gemini's ceiling, not a real conflict.
- ℹ️ **Recommended next step:** rerun the Workflow Craft rubric with tighter anchors that force Gemini off the 5.00 ceiling, then recompute rank agreement.

#### Provenance

- **Model:** `claude-opus-4-7[1m]` at effort `xhigh` via the Claude CLI.
- **Inputs:** the [`judge-consistency-data.md`](judge-consistency-data.md) tables plus benchmark context (rubrics, task list, experiment setup).
- **Script:** [`conclusions_report.py`](../../conclusions_report.py) — regenerate with `python3 generate_results.py <run_dir>`.
- **Instruction:** [`JUDGE_CONSISTENCY_SUMMARY_SYSTEM_PROMPT`](../../judge_consistency_report.py) in that script.
- **Usage:** 5 input + 1993 output tokens, $0.2466.

*Full breakdown with per-model / per-language / per-language×model ranking tables and disagreement hotspots in [judge-consistency-data.md](judge-consistency-data.md).*

---
*Generated by generate_results.py — benchmark instructions v4*