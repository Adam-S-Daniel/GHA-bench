# Benchmark Results: Language Comparison

**Last updated:** 2026-07-28 03:16:37 PM ET — 3/8 runs completed, 5 remaining; total cost $1.10; total agent time 19.9 min.
**Claude Code versions used:** v2.1.132 (3 runs). Each link goes to a per-version snapshot of the system prompt, default-tool descriptions, and the chronological Anthropic changelog up to that version. Regenerate with `python3 version_docs.py`.

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
| default | haiku45-200k-na | A+ (6.1min) | D+ ($0.38) | — | — |
| bash | haiku45-200k-na | D- (7.5min) | A+ ($0.34) | — | — |
| powershell | haiku45-200k-na | A (6.3min) | D- ($0.39) | — | — |


<details>
<summary>Sorted by Duration tier (best-first), then avg of Cost/Tests/Workflow Craft tiers</summary>

| Language | Model | Duration | Cost | Tests Quality | Workflow Craft |
|----------|-------|----------|------|-----------|-------------|
| default | haiku45-200k-na | A+ (6.1min) | D+ ($0.38) | — | — |
| powershell | haiku45-200k-na | A (6.3min) | D- ($0.39) | — | — |
| bash | haiku45-200k-na | D- (7.5min) | A+ ($0.34) | — | — |

</details>

<details>
<summary>Sorted by Cost tier (best-first), then avg of Duration/Tests/Workflow Craft tiers</summary>

| Language | Model | Duration | Cost | Tests Quality | Workflow Craft |
|----------|-------|----------|------|-----------|-------------|
| bash | haiku45-200k-na | D- (7.5min) | A+ ($0.34) | — | — |
| default | haiku45-200k-na | A+ (6.1min) | D+ ($0.38) | — | — |
| powershell | haiku45-200k-na | A (6.3min) | D- ($0.39) | — | — |

</details>

<details>
<summary>Sorted by Tests Quality tier (best-first; no-data last), then avg of other tiers</summary>

| Language | Model | Duration | Cost | Tests Quality | Workflow Craft |
|----------|-------|----------|------|-----------|-------------|
| default | haiku45-200k-na | A+ (6.1min) | D+ ($0.38) | — | — |
| bash | haiku45-200k-na | D- (7.5min) | A+ ($0.34) | — | — |
| powershell | haiku45-200k-na | A (6.3min) | D- ($0.39) | — | — |

</details>

<details>
<summary>Sorted by Workflow Craft tier (best-first; no-data last), then avg of other tiers</summary>

| Language | Model | Duration | Cost | Tests Quality | Workflow Craft |
|----------|-------|----------|------|-----------|-------------|
| default | haiku45-200k-na | A+ (6.1min) | D+ ($0.38) | — | — |
| bash | haiku45-200k-na | D- (7.5min) | A+ ($0.34) | — | — |
| powershell | haiku45-200k-na | A (6.3min) | D- ($0.39) | — | — |

</details>

- **Estimated time remaining:** 33.2min
- **Estimated total cost:** $2.93

## Comparison by Language/Model/Effort
*See [Notes](#notes) for scoring rubric and CLI version legend.*

| Language | Model | Runs | Geo Duration | Max Duration | Geo Duration Net of Traps | Avg Errors | Geo Turns | Geo Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| bash | haiku45-200k-na | 1 | 7.5min | 7.5min | 6.0min | 2.0 | 36 | $0.34 | $0.34 | — | — |
| default | haiku45-200k-na | 1 | 6.1min | 6.1min | 5.1min | 4.0 | 45 | $0.38 | $0.38 | — | — |
| powershell | haiku45-200k-na | 1 | 6.3min | 6.3min | 0.4min | 1.0 | 39 | $0.39 | $0.39 | — | — |


<details>
<summary>Sorted by cost (geomean, cheapest first)</summary>

| Language | Model | Runs | Geo Duration | Max Duration | Geo Duration Net of Traps | Avg Errors | Geo Turns | Geo Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| bash | haiku45-200k-na | 1 | 7.5min | 7.5min | 6.0min | 2.0 | 36 | $0.34 | $0.34 | — | — |
| default | haiku45-200k-na | 1 | 6.1min | 6.1min | 5.1min | 4.0 | 45 | $0.38 | $0.38 | — | — |
| powershell | haiku45-200k-na | 1 | 6.3min | 6.3min | 0.4min | 1.0 | 39 | $0.39 | $0.39 | — | — |

</details>

<details>
<summary>Sorted by duration (geomean, fastest first)</summary>

| Language | Model | Runs | Geo Duration | Max Duration | Geo Duration Net of Traps | Avg Errors | Geo Turns | Geo Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| default | haiku45-200k-na | 1 | 6.1min | 6.1min | 5.1min | 4.0 | 45 | $0.38 | $0.38 | — | — |
| powershell | haiku45-200k-na | 1 | 6.3min | 6.3min | 0.4min | 1.0 | 39 | $0.39 | $0.39 | — | — |
| bash | haiku45-200k-na | 1 | 7.5min | 7.5min | 6.0min | 2.0 | 36 | $0.34 | $0.34 | — | — |

</details>

<details>
<summary>Sorted by duration net of traps (geomean, fastest first)</summary>

| Language | Model | Runs | Geo Duration | Max Duration | Geo Duration Net of Traps | Avg Errors | Geo Turns | Geo Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| powershell | haiku45-200k-na | 1 | 6.3min | 6.3min | 0.4min | 1.0 | 39 | $0.39 | $0.39 | — | — |
| default | haiku45-200k-na | 1 | 6.1min | 6.1min | 5.1min | 4.0 | 45 | $0.38 | $0.38 | — | — |
| bash | haiku45-200k-na | 1 | 7.5min | 7.5min | 6.0min | 2.0 | 36 | $0.34 | $0.34 | — | — |

</details>

<details>
<summary>Sorted by avg errors (fewest first)</summary>

| Language | Model | Runs | Geo Duration | Max Duration | Geo Duration Net of Traps | Avg Errors | Geo Turns | Geo Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| powershell | haiku45-200k-na | 1 | 6.3min | 6.3min | 0.4min | 1.0 | 39 | $0.39 | $0.39 | — | — |
| bash | haiku45-200k-na | 1 | 7.5min | 7.5min | 6.0min | 2.0 | 36 | $0.34 | $0.34 | — | — |
| default | haiku45-200k-na | 1 | 6.1min | 6.1min | 5.1min | 4.0 | 45 | $0.38 | $0.38 | — | — |

</details>

<details>
<summary>Sorted by turns (geomean, fewest first)</summary>

| Language | Model | Runs | Geo Duration | Max Duration | Geo Duration Net of Traps | Avg Errors | Geo Turns | Geo Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| bash | haiku45-200k-na | 1 | 7.5min | 7.5min | 6.0min | 2.0 | 36 | $0.34 | $0.34 | — | — |
| powershell | haiku45-200k-na | 1 | 6.3min | 6.3min | 0.4min | 1.0 | 39 | $0.39 | $0.39 | — | — |
| default | haiku45-200k-na | 1 | 6.1min | 6.1min | 5.1min | 4.0 | 45 | $0.38 | $0.38 | — | — |

</details>

<details>
<summary>Sorted by LLM-as-judge score (best first)</summary>

| Language | Model | Runs | Geo Duration | Max Duration | Geo Duration Net of Traps | Avg Errors | Geo Turns | Geo Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| bash | haiku45-200k-na | 1 | 7.5min | 7.5min | 6.0min | 2.0 | 36 | $0.34 | $0.34 | — | — |
| default | haiku45-200k-na | 1 | 6.1min | 6.1min | 5.1min | 4.0 | 45 | $0.38 | $0.38 | — | — |
| powershell | haiku45-200k-na | 1 | 6.3min | 6.3min | 0.4min | 1.0 | 39 | $0.39 | $0.39 | — | — |

</details>

<details>
<summary>Sorted by deliverable-quality score (best first)</summary>

| Language | Model | Runs | Geo Duration | Max Duration | Geo Duration Net of Traps | Avg Errors | Geo Turns | Geo Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| bash | haiku45-200k-na | 1 | 7.5min | 7.5min | 6.0min | 2.0 | 36 | $0.34 | $0.34 | — | — |
| default | haiku45-200k-na | 1 | 6.1min | 6.1min | 5.1min | 4.0 | 45 | $0.38 | $0.38 | — | — |
| powershell | haiku45-200k-na | 1 | 6.3min | 6.3min | 0.4min | 1.0 | 39 | $0.39 | $0.39 | — | — |

</details>

## Savings Analysis

### Trap Analysis by Language/Model/Effort/Category

| Trap | Language | Model | Fell In | Time Lost | % of Time | $ Lost | % of $ |
|------|------|-------|---------|-----------|-----------|--------|--------|
| fixture-rework | bash | haiku45-200k-na-cli2.1.132 | 1 | 1.0min | 5.0% | $0.04 | 4.09% |
| fixture-rework | default | haiku45-200k-na-cli2.1.132 | 1 | 1.0min | 5.0% | $0.06 | 5.57% |
| fixture-rework | powershell | haiku45-200k-na-cli2.1.132 | 1 | 5.3min | 26.8% | $0.33 | 29.91% |
| act-permission-path-errors | bash | haiku45-200k-na-cli2.1.132 | 1 | 0.5min | 2.5% | $0.02 | 2.05% |
| act-push-debug-loops | powershell | haiku45-200k-na-cli2.1.132 | 1 | 0.5min | 2.5% | $0.03 | 2.75% |


<details>
<summary>Sorted by time lost (least first)</summary>

| Trap | Language | Model | Fell In | Time Lost | % of Time | $ Lost | % of $ |
|------|------|-------|---------|-----------|-----------|--------|--------|
| act-push-debug-loops | powershell | haiku45-200k-na-cli2.1.132 | 1 | 0.5min | 2.5% | $0.03 | 2.75% |
| act-permission-path-errors | bash | haiku45-200k-na-cli2.1.132 | 1 | 0.5min | 2.5% | $0.02 | 2.05% |
| fixture-rework | bash | haiku45-200k-na-cli2.1.132 | 1 | 1.0min | 5.0% | $0.04 | 4.09% |
| fixture-rework | default | haiku45-200k-na-cli2.1.132 | 1 | 1.0min | 5.0% | $0.06 | 5.57% |
| fixture-rework | powershell | haiku45-200k-na-cli2.1.132 | 1 | 5.3min | 26.8% | $0.33 | 29.91% |

</details>

<details>
<summary>Sorted by $ lost (least first)</summary>

| Trap | Language | Model | Fell In | Time Lost | % of Time | $ Lost | % of $ |
|------|------|-------|---------|-----------|-----------|--------|--------|
| act-permission-path-errors | bash | haiku45-200k-na-cli2.1.132 | 1 | 0.5min | 2.5% | $0.02 | 2.05% |
| act-push-debug-loops | powershell | haiku45-200k-na-cli2.1.132 | 1 | 0.5min | 2.5% | $0.03 | 2.75% |
| fixture-rework | bash | haiku45-200k-na-cli2.1.132 | 1 | 1.0min | 5.0% | $0.04 | 4.09% |
| fixture-rework | default | haiku45-200k-na-cli2.1.132 | 1 | 1.0min | 5.0% | $0.06 | 5.57% |
| fixture-rework | powershell | haiku45-200k-na-cli2.1.132 | 1 | 5.3min | 26.8% | $0.33 | 29.91% |

</details>

<details>
<summary>Sorted by fell-in count (fewest first)</summary>

| Trap | Language | Model | Fell In | Time Lost | % of Time | $ Lost | % of $ |
|------|------|-------|---------|-----------|-----------|--------|--------|
| fixture-rework | bash | haiku45-200k-na-cli2.1.132 | 1 | 1.0min | 5.0% | $0.04 | 4.09% |
| fixture-rework | default | haiku45-200k-na-cli2.1.132 | 1 | 1.0min | 5.0% | $0.06 | 5.57% |
| fixture-rework | powershell | haiku45-200k-na-cli2.1.132 | 1 | 5.3min | 26.8% | $0.33 | 29.91% |
| act-permission-path-errors | bash | haiku45-200k-na-cli2.1.132 | 1 | 0.5min | 2.5% | $0.02 | 2.05% |
| act-push-debug-loops | powershell | haiku45-200k-na-cli2.1.132 | 1 | 0.5min | 2.5% | $0.03 | 2.75% |

</details>

#### Trap Descriptions

- **act-permission-path-errors**: Files not found or permission denied inside the act Docker container.
- **act-push-debug-loops**: Agent ran `act push` more than twice, indicating repeated workflow debugging.
- **fixture-rework**: Agent rewrote or edited the same fixture file multiple times (genuine redo cycles, not one-time fixture creation).

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
| bash | haiku45-200k-na-cli2.1.132 | 1 | 2 | 1.5min | 7.5% | $0.07 | 6.14% |
| default | haiku45-200k-na-cli2.1.132 | 1 | 1 | 1.0min | 5.0% | $0.06 | 5.57% |
| powershell | haiku45-200k-na-cli2.1.132 | 1 | 2 | 5.8min | 29.3% | $0.36 | 32.66% |


<details>
<summary>Sorted by time lost (least first)</summary>

| Language | Model | Runs | Traps | Time Lost | % of Time | $ Lost | % of $ |
|------|-------|------|-------|-----------|-----------|--------|--------|
| default | haiku45-200k-na-cli2.1.132 | 1 | 1 | 1.0min | 5.0% | $0.06 | 5.57% |
| bash | haiku45-200k-na-cli2.1.132 | 1 | 2 | 1.5min | 7.5% | $0.07 | 6.14% |
| powershell | haiku45-200k-na-cli2.1.132 | 1 | 2 | 5.8min | 29.3% | $0.36 | 32.66% |

</details>

<details>
<summary>Sorted by $ lost (least first)</summary>

| Language | Model | Runs | Traps | Time Lost | % of Time | $ Lost | % of $ |
|------|-------|------|-------|-----------|-----------|--------|--------|
| default | haiku45-200k-na-cli2.1.132 | 1 | 1 | 1.0min | 5.0% | $0.06 | 5.57% |
| bash | haiku45-200k-na-cli2.1.132 | 1 | 2 | 1.5min | 7.5% | $0.07 | 6.14% |
| powershell | haiku45-200k-na-cli2.1.132 | 1 | 2 | 5.8min | 29.3% | $0.36 | 32.66% |

</details>

### Prompt Cache Savings

| Status | Runs | $ Saved | % of $ |
|--------|------|---------|--------|
| Full hit (100%) | 0 | $0.00 | 0.00% |
| Partial | 3 | $0.04 | 3.95% |
| Miss | 0 | $0.00 | 0.00% |

## Test Quality Evaluation

### Structural Metrics by Language/Model/Effort

Automated analysis of test files: test count, assertion count, and test-to-code line ratio.

| Language | Model | Avg Tests | Avg Assertions | Avg Assert/Test | Avg Test:Code Ratio |
|------|-------|-----------|----------------|-----------------|---------------------|
| bash | haiku45-200k-na | 10.0 | 8.0 | 0.8 | 0.19 |
| default | haiku45-200k-na | 11.0 | 19.0 | 1.7 | 0.86 |
| powershell | haiku45-200k-na | 13.0 | 16.0 | 1.2 | 0.22 |


<details>
<summary>Sorted by avg tests (most first)</summary>

| Language | Model | Avg Tests | Avg Assertions | Avg Assert/Test | Avg Test:Code Ratio |
|------|-------|-----------|----------------|-----------------|---------------------|
| powershell | haiku45-200k-na | 13.0 | 16.0 | 1.2 | 0.22 |
| default | haiku45-200k-na | 11.0 | 19.0 | 1.7 | 0.86 |
| bash | haiku45-200k-na | 10.0 | 8.0 | 0.8 | 0.19 |

</details>

<details>
<summary>Sorted by avg assertions (most first)</summary>

| Language | Model | Avg Tests | Avg Assertions | Avg Assert/Test | Avg Test:Code Ratio |
|------|-------|-----------|----------------|-----------------|---------------------|
| default | haiku45-200k-na | 11.0 | 19.0 | 1.7 | 0.86 |
| powershell | haiku45-200k-na | 13.0 | 16.0 | 1.2 | 0.22 |
| bash | haiku45-200k-na | 10.0 | 8.0 | 0.8 | 0.19 |

</details>

<details>
<summary>Sorted by avg test:code ratio (highest first)</summary>

| Language | Model | Avg Tests | Avg Assertions | Avg Assert/Test | Avg Test:Code Ratio |
|------|-------|-----------|----------------|-----------------|---------------------|
| default | haiku45-200k-na | 11.0 | 19.0 | 1.7 | 0.86 |
| powershell | haiku45-200k-na | 13.0 | 16.0 | 1.2 | 0.22 |
| bash | haiku45-200k-na | 10.0 | 8.0 | 0.8 | 0.19 |

</details>


<details>
<summary>Per-run structural metrics</summary>

| Task | Language | Model | Tests | Assertions | Assert/Test | Test Lines | Impl Lines | Test:Code |
|------|------|-------|-------|------------|-------------|------------|------------|-----------|
| Semantic Version Bumper | bash | haiku45-200k-na | 10 | 8 | 0.8 | 136 | 698 | 0.19 |
| Semantic Version Bumper | default | haiku45-200k-na | 11 | 19 | 1.7 | 169 | 197 | 0.86 |
| Semantic Version Bumper | powershell | haiku45-200k-na | 13 | 16 | 1.2 | 179 | 813 | 0.22 |

</details>

## Per-Run Results

*Tests Quality = Overall (1-5) from LLM-as-judge of generated test code (dimensions: coverage, rigor, design). `—` = no judge data.*

| Task | Language | Model | Duration | Turns | Errors | Cost | Tests Quality | Chosen | Status |
|------|----------|-------|----------|-------|--------|------|-----------|--------|--------|
| Semantic Version Bumper | bash | haiku45-200k-na | 7.5min | 36 | 2 | $0.34 | — | bash | ok |
| Semantic Version Bumper | default | haiku45-200k-na | 6.1min | 45 | 4 | $0.38 | — | bash | ok |
| Semantic Version Bumper | powershell | haiku45-200k-na | 6.3min | 39 | 1 | $0.39 | — | powershell | ok |


<details>
<summary>Sorted by cost (cheapest first)</summary>

| Task | Language | Model | Duration | Turns | Errors | Cost | Tests Quality | Chosen | Status |
|------|----------|-------|----------|-------|--------|------|-----------|--------|--------|
| Semantic Version Bumper | bash | haiku45-200k-na | 7.5min | 36 | 2 | $0.34 | — | bash | ok |
| Semantic Version Bumper | default | haiku45-200k-na | 6.1min | 45 | 4 | $0.38 | — | bash | ok |
| Semantic Version Bumper | powershell | haiku45-200k-na | 6.3min | 39 | 1 | $0.39 | — | powershell | ok |

</details>

<details>
<summary>Sorted by duration (fastest first)</summary>

| Task | Language | Model | Duration | Turns | Errors | Cost | Tests Quality | Chosen | Status |
|------|----------|-------|----------|-------|--------|------|-----------|--------|--------|
| Semantic Version Bumper | default | haiku45-200k-na | 6.1min | 45 | 4 | $0.38 | — | bash | ok |
| Semantic Version Bumper | powershell | haiku45-200k-na | 6.3min | 39 | 1 | $0.39 | — | powershell | ok |
| Semantic Version Bumper | bash | haiku45-200k-na | 7.5min | 36 | 2 | $0.34 | — | bash | ok |

</details>

<details>
<summary>Sorted by errors (fewest first)</summary>

| Task | Language | Model | Duration | Turns | Errors | Cost | Tests Quality | Chosen | Status |
|------|----------|-------|----------|-------|--------|------|-----------|--------|--------|
| Semantic Version Bumper | powershell | haiku45-200k-na | 6.3min | 39 | 1 | $0.39 | — | powershell | ok |
| Semantic Version Bumper | bash | haiku45-200k-na | 7.5min | 36 | 2 | $0.34 | — | bash | ok |
| Semantic Version Bumper | default | haiku45-200k-na | 6.1min | 45 | 4 | $0.38 | — | bash | ok |

</details>

<details>
<summary>Sorted by turns (fewest first)</summary>

| Task | Language | Model | Duration | Turns | Errors | Cost | Tests Quality | Chosen | Status |
|------|----------|-------|----------|-------|--------|------|-----------|--------|--------|
| Semantic Version Bumper | bash | haiku45-200k-na | 7.5min | 36 | 2 | $0.34 | — | bash | ok |
| Semantic Version Bumper | powershell | haiku45-200k-na | 6.3min | 39 | 1 | $0.39 | — | powershell | ok |
| Semantic Version Bumper | default | haiku45-200k-na | 6.1min | 45 | 4 | $0.38 | — | bash | ok |

</details>

<details>
<summary>Sorted by LLM-as-judge score (best first)</summary>

| Task | Language | Model | Duration | Turns | Errors | Cost | Tests Quality | Chosen | Status |
|------|----------|-------|----------|-------|--------|------|-----------|--------|--------|
| Semantic Version Bumper | bash | haiku45-200k-na | 7.5min | 36 | 2 | $0.34 | — | bash | ok |
| Semantic Version Bumper | default | haiku45-200k-na | 6.1min | 45 | 4 | $0.38 | — | bash | ok |
| Semantic Version Bumper | powershell | haiku45-200k-na | 6.3min | 39 | 1 | $0.39 | — | powershell | ok |

</details>

## Notes

### Tiers

- **Duration bands:** **A+** ≤1.02×, **A** ≤1.03×, **A-** ≤1.05×, **B+** ≤1.07×, **B** ≤1.09×, **B-** ≤1.10×, **C+** ≤1.12×, **C** ≤1.14×, **C-** ≤1.16×, **D+** ≤1.18×, **D** ≤1.20×, **D-** ≤1.22×, **F** >1.22×
- **Cost bands:** **A+** ≤1.01×, **A** ≤1.02×, **A-** ≤1.04×, **B+** ≤1.05×, **B** ≤1.06×, **B-** ≤1.07×, **C+** ≤1.08×, **C** ≤1.10×, **C-** ≤1.11×, **D+** ≤1.12×, **D** ≤1.13×, **D-** ≤1.15×, **F** >1.15×

*Tests/Workflow Craft bands are absolute Overall score bands:* **A+** ≥4.7, **A** ≥4.4, **A-** ≥4.1, **B+** ≥3.8, **B** ≥3.5, **B-** ≥3.2, **C+** ≥2.9, **C** ≥2.6, **C-** ≥2.3, **D+** ≥2.0, **D** ≥1.7, **D-** ≥1.4, **F** <1.4, `—` = no data.*

### CLI Version Legend

| Variant label | CLI version | Tasks | Languages |
|---------------|-------------|-------|-----------|
| haiku45-200k-na | 2.1.132 | All | All |

---
*Generated by generate_results.py — benchmark instructions v4*