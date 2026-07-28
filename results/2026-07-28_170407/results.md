# Benchmark Results: Language Comparison

**Last updated:** 2026-07-28 01:41:52 PM ET — 5/8 runs completed, 3 remaining; total cost $3.22; total agent time 36.7 min.
**Claude Code versions used:** v2.1.220 (5 runs). Each link goes to a per-version snapshot of the system prompt, default-tool descriptions, and the chronological Anthropic changelog up to that version. Regenerate with `python3 version_docs.py`.

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
| powershell | haiku45-200k-na | A+ (5.4min) | A+ ($0.48) | — | — |
| bash | haiku45-200k-na | B (6.8min) | B ($0.62) | — | — |
| default | haiku45-200k-na | C (7.8min) | A ($0.53) | — | — |
| typescript-bun | haiku45-200k-na | D- (9.8min) | D- ($0.94) | — | — |


<details>
<summary>Sorted by Duration tier (best-first), then avg of Cost/Tests/Workflow Craft tiers</summary>

| Language | Model | Duration | Cost | Tests Quality | Workflow Craft |
|----------|-------|----------|------|-----------|-------------|
| powershell | haiku45-200k-na | A+ (5.4min) | A+ ($0.48) | — | — |
| bash | haiku45-200k-na | B (6.8min) | B ($0.62) | — | — |
| default | haiku45-200k-na | C (7.8min) | A ($0.53) | — | — |
| typescript-bun | haiku45-200k-na | D- (9.8min) | D- ($0.94) | — | — |

</details>

<details>
<summary>Sorted by Cost tier (best-first), then avg of Duration/Tests/Workflow Craft tiers</summary>

| Language | Model | Duration | Cost | Tests Quality | Workflow Craft |
|----------|-------|----------|------|-----------|-------------|
| powershell | haiku45-200k-na | A+ (5.4min) | A+ ($0.48) | — | — |
| default | haiku45-200k-na | C (7.8min) | A ($0.53) | — | — |
| bash | haiku45-200k-na | B (6.8min) | B ($0.62) | — | — |
| typescript-bun | haiku45-200k-na | D- (9.8min) | D- ($0.94) | — | — |

</details>

<details>
<summary>Sorted by Tests Quality tier (best-first; no-data last), then avg of other tiers</summary>

| Language | Model | Duration | Cost | Tests Quality | Workflow Craft |
|----------|-------|----------|------|-----------|-------------|
| powershell | haiku45-200k-na | A+ (5.4min) | A+ ($0.48) | — | — |
| bash | haiku45-200k-na | B (6.8min) | B ($0.62) | — | — |
| default | haiku45-200k-na | C (7.8min) | A ($0.53) | — | — |
| typescript-bun | haiku45-200k-na | D- (9.8min) | D- ($0.94) | — | — |

</details>

<details>
<summary>Sorted by Workflow Craft tier (best-first; no-data last), then avg of other tiers</summary>

| Language | Model | Duration | Cost | Tests Quality | Workflow Craft |
|----------|-------|----------|------|-----------|-------------|
| powershell | haiku45-200k-na | A+ (5.4min) | A+ ($0.48) | — | — |
| bash | haiku45-200k-na | B (6.8min) | B ($0.62) | — | — |
| default | haiku45-200k-na | C (7.8min) | A ($0.53) | — | — |
| typescript-bun | haiku45-200k-na | D- (9.8min) | D- ($0.94) | — | — |

</details>

- **Estimated time remaining:** 22.0min
- **Estimated total cost:** $5.15

## Comparison by Language/Model/Effort
*See [Notes](#notes) for scoring rubric and CLI version legend.*

| Language | Model | Runs | Geo Duration | Max Duration | Geo Duration Net of Traps | Avg Errors | Geo Turns | Geo Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| bash | haiku45-200k-na | 2 | 6.8min | 7.7min | 6.0min | 4.0 | 67 | $0.62 | $1.27 | — | — |
| default | haiku45-200k-na | 1 | 7.8min | 7.8min | 4.5min | 1.0 | 40 | $0.53 | $0.53 | — | — |
| powershell | haiku45-200k-na | 1 | 5.4min | 5.4min | 3.1min | 3.0 | 43 | $0.48 | $0.48 | — | — |
| typescript-bun | haiku45-200k-na | 1 | 9.8min | 9.8min | 6.3min | 6.0 | 81 | $0.94 | $0.94 | — | — |


<details>
<summary>Sorted by cost (geomean, cheapest first)</summary>

| Language | Model | Runs | Geo Duration | Max Duration | Geo Duration Net of Traps | Avg Errors | Geo Turns | Geo Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| powershell | haiku45-200k-na | 1 | 5.4min | 5.4min | 3.1min | 3.0 | 43 | $0.48 | $0.48 | — | — |
| default | haiku45-200k-na | 1 | 7.8min | 7.8min | 4.5min | 1.0 | 40 | $0.53 | $0.53 | — | — |
| bash | haiku45-200k-na | 2 | 6.8min | 7.7min | 6.0min | 4.0 | 67 | $0.62 | $1.27 | — | — |
| typescript-bun | haiku45-200k-na | 1 | 9.8min | 9.8min | 6.3min | 6.0 | 81 | $0.94 | $0.94 | — | — |

</details>

<details>
<summary>Sorted by duration (geomean, fastest first)</summary>

| Language | Model | Runs | Geo Duration | Max Duration | Geo Duration Net of Traps | Avg Errors | Geo Turns | Geo Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| powershell | haiku45-200k-na | 1 | 5.4min | 5.4min | 3.1min | 3.0 | 43 | $0.48 | $0.48 | — | — |
| bash | haiku45-200k-na | 2 | 6.8min | 7.7min | 6.0min | 4.0 | 67 | $0.62 | $1.27 | — | — |
| default | haiku45-200k-na | 1 | 7.8min | 7.8min | 4.5min | 1.0 | 40 | $0.53 | $0.53 | — | — |
| typescript-bun | haiku45-200k-na | 1 | 9.8min | 9.8min | 6.3min | 6.0 | 81 | $0.94 | $0.94 | — | — |

</details>

<details>
<summary>Sorted by duration net of traps (geomean, fastest first)</summary>

| Language | Model | Runs | Geo Duration | Max Duration | Geo Duration Net of Traps | Avg Errors | Geo Turns | Geo Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| powershell | haiku45-200k-na | 1 | 5.4min | 5.4min | 3.1min | 3.0 | 43 | $0.48 | $0.48 | — | — |
| default | haiku45-200k-na | 1 | 7.8min | 7.8min | 4.5min | 1.0 | 40 | $0.53 | $0.53 | — | — |
| bash | haiku45-200k-na | 2 | 6.8min | 7.7min | 6.0min | 4.0 | 67 | $0.62 | $1.27 | — | — |
| typescript-bun | haiku45-200k-na | 1 | 9.8min | 9.8min | 6.3min | 6.0 | 81 | $0.94 | $0.94 | — | — |

</details>

<details>
<summary>Sorted by avg errors (fewest first)</summary>

| Language | Model | Runs | Geo Duration | Max Duration | Geo Duration Net of Traps | Avg Errors | Geo Turns | Geo Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| default | haiku45-200k-na | 1 | 7.8min | 7.8min | 4.5min | 1.0 | 40 | $0.53 | $0.53 | — | — |
| powershell | haiku45-200k-na | 1 | 5.4min | 5.4min | 3.1min | 3.0 | 43 | $0.48 | $0.48 | — | — |
| bash | haiku45-200k-na | 2 | 6.8min | 7.7min | 6.0min | 4.0 | 67 | $0.62 | $1.27 | — | — |
| typescript-bun | haiku45-200k-na | 1 | 9.8min | 9.8min | 6.3min | 6.0 | 81 | $0.94 | $0.94 | — | — |

</details>

<details>
<summary>Sorted by turns (geomean, fewest first)</summary>

| Language | Model | Runs | Geo Duration | Max Duration | Geo Duration Net of Traps | Avg Errors | Geo Turns | Geo Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| default | haiku45-200k-na | 1 | 7.8min | 7.8min | 4.5min | 1.0 | 40 | $0.53 | $0.53 | — | — |
| powershell | haiku45-200k-na | 1 | 5.4min | 5.4min | 3.1min | 3.0 | 43 | $0.48 | $0.48 | — | — |
| bash | haiku45-200k-na | 2 | 6.8min | 7.7min | 6.0min | 4.0 | 67 | $0.62 | $1.27 | — | — |
| typescript-bun | haiku45-200k-na | 1 | 9.8min | 9.8min | 6.3min | 6.0 | 81 | $0.94 | $0.94 | — | — |

</details>

<details>
<summary>Sorted by LLM-as-judge score (best first)</summary>

| Language | Model | Runs | Geo Duration | Max Duration | Geo Duration Net of Traps | Avg Errors | Geo Turns | Geo Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| bash | haiku45-200k-na | 2 | 6.8min | 7.7min | 6.0min | 4.0 | 67 | $0.62 | $1.27 | — | — |
| default | haiku45-200k-na | 1 | 7.8min | 7.8min | 4.5min | 1.0 | 40 | $0.53 | $0.53 | — | — |
| powershell | haiku45-200k-na | 1 | 5.4min | 5.4min | 3.1min | 3.0 | 43 | $0.48 | $0.48 | — | — |
| typescript-bun | haiku45-200k-na | 1 | 9.8min | 9.8min | 6.3min | 6.0 | 81 | $0.94 | $0.94 | — | — |

</details>

<details>
<summary>Sorted by deliverable-quality score (best first)</summary>

| Language | Model | Runs | Geo Duration | Max Duration | Geo Duration Net of Traps | Avg Errors | Geo Turns | Geo Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| bash | haiku45-200k-na | 2 | 6.8min | 7.7min | 6.0min | 4.0 | 67 | $0.62 | $1.27 | — | — |
| default | haiku45-200k-na | 1 | 7.8min | 7.8min | 4.5min | 1.0 | 40 | $0.53 | $0.53 | — | — |
| powershell | haiku45-200k-na | 1 | 5.4min | 5.4min | 3.1min | 3.0 | 43 | $0.48 | $0.48 | — | — |
| typescript-bun | haiku45-200k-na | 1 | 9.8min | 9.8min | 6.3min | 6.0 | 81 | $0.94 | $0.94 | — | — |

</details>

## Savings Analysis

### Trap Analysis by Language/Model/Effort/Category

| Trap | Language | Model | Fell In | Time Lost | % of Time | $ Lost | % of $ |
|------|------|-------|---------|-----------|-----------|--------|--------|
| actionlint-fix-cycles | default | haiku45-200k-na-cli2.1.220 | 1 | 3.3min | 9.1% | $0.23 | 7.01% |
| actionlint-fix-cycles | powershell | haiku45-200k-na-cli2.1.220 | 1 | 2.3min | 6.4% | $0.21 | 6.44% |
| act-push-debug-loops | bash | haiku45-200k-na-cli2.1.220 | 1 | 0.7min | 2.0% | $0.07 | 2.28% |
| act-push-debug-loops | typescript-bun | haiku45-200k-na-cli2.1.220 | 1 | 2.1min | 5.7% | $0.20 | 6.22% |
| repeated-test-reruns | bash | haiku45-200k-na-cli2.1.220 | 1 | 1.0min | 2.7% | $0.10 | 3.08% |
| repeated-test-reruns | typescript-bun | haiku45-200k-na-cli2.1.220 | 1 | 1.3min | 3.6% | $0.13 | 4.00% |


<details>
<summary>Sorted by time lost (least first)</summary>

| Trap | Language | Model | Fell In | Time Lost | % of Time | $ Lost | % of $ |
|------|------|-------|---------|-----------|-----------|--------|--------|
| act-push-debug-loops | bash | haiku45-200k-na-cli2.1.220 | 1 | 0.7min | 2.0% | $0.07 | 2.28% |
| repeated-test-reruns | bash | haiku45-200k-na-cli2.1.220 | 1 | 1.0min | 2.7% | $0.10 | 3.08% |
| repeated-test-reruns | typescript-bun | haiku45-200k-na-cli2.1.220 | 1 | 1.3min | 3.6% | $0.13 | 4.00% |
| act-push-debug-loops | typescript-bun | haiku45-200k-na-cli2.1.220 | 1 | 2.1min | 5.7% | $0.20 | 6.22% |
| actionlint-fix-cycles | powershell | haiku45-200k-na-cli2.1.220 | 1 | 2.3min | 6.4% | $0.21 | 6.44% |
| actionlint-fix-cycles | default | haiku45-200k-na-cli2.1.220 | 1 | 3.3min | 9.1% | $0.23 | 7.01% |

</details>

<details>
<summary>Sorted by $ lost (least first)</summary>

| Trap | Language | Model | Fell In | Time Lost | % of Time | $ Lost | % of $ |
|------|------|-------|---------|-----------|-----------|--------|--------|
| act-push-debug-loops | bash | haiku45-200k-na-cli2.1.220 | 1 | 0.7min | 2.0% | $0.07 | 2.28% |
| repeated-test-reruns | bash | haiku45-200k-na-cli2.1.220 | 1 | 1.0min | 2.7% | $0.10 | 3.08% |
| repeated-test-reruns | typescript-bun | haiku45-200k-na-cli2.1.220 | 1 | 1.3min | 3.6% | $0.13 | 4.00% |
| act-push-debug-loops | typescript-bun | haiku45-200k-na-cli2.1.220 | 1 | 2.1min | 5.7% | $0.20 | 6.22% |
| actionlint-fix-cycles | powershell | haiku45-200k-na-cli2.1.220 | 1 | 2.3min | 6.4% | $0.21 | 6.44% |
| actionlint-fix-cycles | default | haiku45-200k-na-cli2.1.220 | 1 | 3.3min | 9.1% | $0.23 | 7.01% |

</details>

<details>
<summary>Sorted by fell-in count (fewest first)</summary>

| Trap | Language | Model | Fell In | Time Lost | % of Time | $ Lost | % of $ |
|------|------|-------|---------|-----------|-----------|--------|--------|
| actionlint-fix-cycles | default | haiku45-200k-na-cli2.1.220 | 1 | 3.3min | 9.1% | $0.23 | 7.01% |
| actionlint-fix-cycles | powershell | haiku45-200k-na-cli2.1.220 | 1 | 2.3min | 6.4% | $0.21 | 6.44% |
| act-push-debug-loops | bash | haiku45-200k-na-cli2.1.220 | 1 | 0.7min | 2.0% | $0.07 | 2.28% |
| act-push-debug-loops | typescript-bun | haiku45-200k-na-cli2.1.220 | 1 | 2.1min | 5.7% | $0.20 | 6.22% |
| repeated-test-reruns | bash | haiku45-200k-na-cli2.1.220 | 1 | 1.0min | 2.7% | $0.10 | 3.08% |
| repeated-test-reruns | typescript-bun | haiku45-200k-na-cli2.1.220 | 1 | 1.3min | 3.6% | $0.13 | 4.00% |

</details>

#### Trap Descriptions

- **act-push-debug-loops**: Agent ran `act push` more than twice, indicating repeated workflow debugging.
- **actionlint-fix-cycles**: Workflow YAML required 3+ actionlint runs and 2+ fixes to pass.
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
| bash | haiku45-200k-na-cli2.1.220 | 2 | 2 | 1.7min | 4.7% | $0.17 | 5.36% |
| default | haiku45-200k-na-cli2.1.220 | 1 | 1 | 3.3min | 9.1% | $0.23 | 7.01% |
| powershell | haiku45-200k-na-cli2.1.220 | 1 | 1 | 2.3min | 6.4% | $0.21 | 6.44% |
| typescript-bun | haiku45-200k-na-cli2.1.220 | 1 | 2 | 3.4min | 9.3% | $0.33 | 10.22% |


<details>
<summary>Sorted by time lost (least first)</summary>

| Language | Model | Runs | Traps | Time Lost | % of Time | $ Lost | % of $ |
|------|-------|------|-------|-----------|-----------|--------|--------|
| bash | haiku45-200k-na-cli2.1.220 | 2 | 2 | 1.7min | 4.7% | $0.17 | 5.36% |
| powershell | haiku45-200k-na-cli2.1.220 | 1 | 1 | 2.3min | 6.4% | $0.21 | 6.44% |
| default | haiku45-200k-na-cli2.1.220 | 1 | 1 | 3.3min | 9.1% | $0.23 | 7.01% |
| typescript-bun | haiku45-200k-na-cli2.1.220 | 1 | 2 | 3.4min | 9.3% | $0.33 | 10.22% |

</details>

<details>
<summary>Sorted by $ lost (least first)</summary>

| Language | Model | Runs | Traps | Time Lost | % of Time | $ Lost | % of $ |
|------|-------|------|-------|-----------|-----------|--------|--------|
| bash | haiku45-200k-na-cli2.1.220 | 2 | 2 | 1.7min | 4.7% | $0.17 | 5.36% |
| powershell | haiku45-200k-na-cli2.1.220 | 1 | 1 | 2.3min | 6.4% | $0.21 | 6.44% |
| default | haiku45-200k-na-cli2.1.220 | 1 | 1 | 3.3min | 9.1% | $0.23 | 7.01% |
| typescript-bun | haiku45-200k-na-cli2.1.220 | 1 | 2 | 3.4min | 9.3% | $0.33 | 10.22% |

</details>

### Prompt Cache Savings

| Status | Runs | $ Saved | % of $ |
|--------|------|---------|--------|
| Full hit (100%) | 0 | $0.00 | 0.00% |
| Partial | 4 | $0.08 | 2.61% |
| Miss | 1 | $0.00 | 0.00% |

## Test Quality Evaluation

### Structural Metrics by Language/Model/Effort

Automated analysis of test files: test count, assertion count, and test-to-code line ratio.

| Language | Model | Avg Tests | Avg Assertions | Avg Assert/Test | Avg Test:Code Ratio |
|------|-------|-----------|----------------|-----------------|---------------------|
| bash | haiku45-200k-na | 30.5 | 37.0 | 1.2 | 2.21 |
| default | haiku45-200k-na | 0.0 | 0.0 | 0.0 | 0.00 |
| powershell | haiku45-200k-na | 18.0 | 35.0 | 1.9 | 0.59 |
| typescript-bun | haiku45-200k-na | 15.0 | 30.0 | 2.0 | 0.36 |


<details>
<summary>Sorted by avg tests (most first)</summary>

| Language | Model | Avg Tests | Avg Assertions | Avg Assert/Test | Avg Test:Code Ratio |
|------|-------|-----------|----------------|-----------------|---------------------|
| bash | haiku45-200k-na | 30.5 | 37.0 | 1.2 | 2.21 |
| powershell | haiku45-200k-na | 18.0 | 35.0 | 1.9 | 0.59 |
| typescript-bun | haiku45-200k-na | 15.0 | 30.0 | 2.0 | 0.36 |
| default | haiku45-200k-na | 0.0 | 0.0 | 0.0 | 0.00 |

</details>

<details>
<summary>Sorted by avg assertions (most first)</summary>

| Language | Model | Avg Tests | Avg Assertions | Avg Assert/Test | Avg Test:Code Ratio |
|------|-------|-----------|----------------|-----------------|---------------------|
| bash | haiku45-200k-na | 30.5 | 37.0 | 1.2 | 2.21 |
| powershell | haiku45-200k-na | 18.0 | 35.0 | 1.9 | 0.59 |
| typescript-bun | haiku45-200k-na | 15.0 | 30.0 | 2.0 | 0.36 |
| default | haiku45-200k-na | 0.0 | 0.0 | 0.0 | 0.00 |

</details>

<details>
<summary>Sorted by avg test:code ratio (highest first)</summary>

| Language | Model | Avg Tests | Avg Assertions | Avg Assert/Test | Avg Test:Code Ratio |
|------|-------|-----------|----------------|-----------------|---------------------|
| bash | haiku45-200k-na | 30.5 | 37.0 | 1.2 | 2.21 |
| powershell | haiku45-200k-na | 18.0 | 35.0 | 1.9 | 0.59 |
| typescript-bun | haiku45-200k-na | 15.0 | 30.0 | 2.0 | 0.36 |
| default | haiku45-200k-na | 0.0 | 0.0 | 0.0 | 0.00 |

</details>


<details>
<summary>Per-run structural metrics</summary>

| Task | Language | Model | Tests | Assertions | Assert/Test | Test Lines | Impl Lines | Test:Code |
|------|------|-------|-------|------------|-------------|------------|------------|-----------|
| Semantic Version Bumper | bash | haiku45-200k-na | 44 | 50 | 1.1 | 481 | 262 | 1.84 |
| Semantic Version Bumper | default | haiku45-200k-na | 0 | 0 | 0.0 | 0 | 1082 | 0.00 |
| Semantic Version Bumper | powershell | haiku45-200k-na | 18 | 35 | 1.9 | 148 | 251 | 0.59 |
| Semantic Version Bumper | typescript-bun | haiku45-200k-na | 15 | 30 | 2.0 | 202 | 562 | 0.36 |
| Environment Matrix Generator | bash | haiku45-200k-na | 17 | 24 | 1.4 | 284 | 110 | 2.58 |

</details>

## Per-Run Results

*Tests Quality = Overall (1-5) from LLM-as-judge of generated test code (dimensions: coverage, rigor, design). `—` = no judge data.*

| Task | Language | Model | Duration | Turns | Errors | Cost | Tests Quality | Chosen | Status |
|------|----------|-------|----------|-------|--------|------|-----------|--------|--------|
| Environment Matrix Generator | bash | haiku45-200k-na | 7.7min | 70 | 4 | $0.77 | — | bash | ok |
| Semantic Version Bumper | bash | haiku45-200k-na | 6.0min | 64 | 4 | $0.50 | — | bash | ok |
| Semantic Version Bumper | default | haiku45-200k-na | 7.8min | 40 | 1 | $0.53 | — | bash | ok |
| Semantic Version Bumper | powershell | haiku45-200k-na | 5.4min | 43 | 3 | $0.48 | — | powershell | ok |
| Semantic Version Bumper | typescript-bun | haiku45-200k-na | 9.8min | 81 | 6 | $0.94 | — | typescript | ok |


<details>
<summary>Sorted by cost (cheapest first)</summary>

| Task | Language | Model | Duration | Turns | Errors | Cost | Tests Quality | Chosen | Status |
|------|----------|-------|----------|-------|--------|------|-----------|--------|--------|
| Semantic Version Bumper | powershell | haiku45-200k-na | 5.4min | 43 | 3 | $0.48 | — | powershell | ok |
| Semantic Version Bumper | bash | haiku45-200k-na | 6.0min | 64 | 4 | $0.50 | — | bash | ok |
| Semantic Version Bumper | default | haiku45-200k-na | 7.8min | 40 | 1 | $0.53 | — | bash | ok |
| Environment Matrix Generator | bash | haiku45-200k-na | 7.7min | 70 | 4 | $0.77 | — | bash | ok |
| Semantic Version Bumper | typescript-bun | haiku45-200k-na | 9.8min | 81 | 6 | $0.94 | — | typescript | ok |

</details>

<details>
<summary>Sorted by duration (fastest first)</summary>

| Task | Language | Model | Duration | Turns | Errors | Cost | Tests Quality | Chosen | Status |
|------|----------|-------|----------|-------|--------|------|-----------|--------|--------|
| Semantic Version Bumper | powershell | haiku45-200k-na | 5.4min | 43 | 3 | $0.48 | — | powershell | ok |
| Semantic Version Bumper | bash | haiku45-200k-na | 6.0min | 64 | 4 | $0.50 | — | bash | ok |
| Environment Matrix Generator | bash | haiku45-200k-na | 7.7min | 70 | 4 | $0.77 | — | bash | ok |
| Semantic Version Bumper | default | haiku45-200k-na | 7.8min | 40 | 1 | $0.53 | — | bash | ok |
| Semantic Version Bumper | typescript-bun | haiku45-200k-na | 9.8min | 81 | 6 | $0.94 | — | typescript | ok |

</details>

<details>
<summary>Sorted by errors (fewest first)</summary>

| Task | Language | Model | Duration | Turns | Errors | Cost | Tests Quality | Chosen | Status |
|------|----------|-------|----------|-------|--------|------|-----------|--------|--------|
| Semantic Version Bumper | default | haiku45-200k-na | 7.8min | 40 | 1 | $0.53 | — | bash | ok |
| Semantic Version Bumper | powershell | haiku45-200k-na | 5.4min | 43 | 3 | $0.48 | — | powershell | ok |
| Semantic Version Bumper | bash | haiku45-200k-na | 6.0min | 64 | 4 | $0.50 | — | bash | ok |
| Environment Matrix Generator | bash | haiku45-200k-na | 7.7min | 70 | 4 | $0.77 | — | bash | ok |
| Semantic Version Bumper | typescript-bun | haiku45-200k-na | 9.8min | 81 | 6 | $0.94 | — | typescript | ok |

</details>

<details>
<summary>Sorted by turns (fewest first)</summary>

| Task | Language | Model | Duration | Turns | Errors | Cost | Tests Quality | Chosen | Status |
|------|----------|-------|----------|-------|--------|------|-----------|--------|--------|
| Semantic Version Bumper | default | haiku45-200k-na | 7.8min | 40 | 1 | $0.53 | — | bash | ok |
| Semantic Version Bumper | powershell | haiku45-200k-na | 5.4min | 43 | 3 | $0.48 | — | powershell | ok |
| Semantic Version Bumper | bash | haiku45-200k-na | 6.0min | 64 | 4 | $0.50 | — | bash | ok |
| Environment Matrix Generator | bash | haiku45-200k-na | 7.7min | 70 | 4 | $0.77 | — | bash | ok |
| Semantic Version Bumper | typescript-bun | haiku45-200k-na | 9.8min | 81 | 6 | $0.94 | — | typescript | ok |

</details>

<details>
<summary>Sorted by LLM-as-judge score (best first)</summary>

| Task | Language | Model | Duration | Turns | Errors | Cost | Tests Quality | Chosen | Status |
|------|----------|-------|----------|-------|--------|------|-----------|--------|--------|
| Semantic Version Bumper | bash | haiku45-200k-na | 6.0min | 64 | 4 | $0.50 | — | bash | ok |
| Semantic Version Bumper | default | haiku45-200k-na | 7.8min | 40 | 1 | $0.53 | — | bash | ok |
| Semantic Version Bumper | powershell | haiku45-200k-na | 5.4min | 43 | 3 | $0.48 | — | powershell | ok |
| Semantic Version Bumper | typescript-bun | haiku45-200k-na | 9.8min | 81 | 6 | $0.94 | — | typescript | ok |
| Environment Matrix Generator | bash | haiku45-200k-na | 7.7min | 70 | 4 | $0.77 | — | bash | ok |

</details>

## Notes

### Tiers

- **Duration bands:** **A+** ≤1.05×, **A** ≤1.10×, **A-** ≤1.16×, **B+** ≤1.22×, **B** ≤1.28×, **B-** ≤1.35×, **C+** ≤1.41×, **C** ≤1.49×, **C-** ≤1.56×, **D+** ≤1.64×, **D** ≤1.72×, **D-** ≤1.81×, **F** >1.81×
- **Cost bands:** **A+** ≤1.06×, **A** ≤1.12×, **A-** ≤1.18×, **B+** ≤1.25×, **B** ≤1.33×, **B-** ≤1.40×, **C+** ≤1.48×, **C** ≤1.57×, **C-** ≤1.66×, **D+** ≤1.76×, **D** ≤1.86×, **D-** ≤1.97×, **F** >1.97×

*Tests/Workflow Craft bands are absolute Overall score bands:* **A+** ≥4.7, **A** ≥4.4, **A-** ≥4.1, **B+** ≥3.8, **B** ≥3.5, **B-** ≥3.2, **C+** ≥2.9, **C** ≥2.6, **C-** ≥2.3, **D+** ≥2.0, **D** ≥1.7, **D-** ≥1.4, **F** <1.4, `—` = no data.*

### CLI Version Legend

| Variant label | CLI version | Tasks | Languages |
|---------------|-------------|-------|-----------|
| haiku45-200k-na | 2.1.220 | All | All |

---
*Generated by generate_results.py — benchmark instructions v4*