# Benchmark Results: Language Comparison

**Last updated:** 2026-07-28 12:48:02 PM ET — 5/8 runs completed, 3 remaining; total cost $2.77; total agent time 36.6 min.
**Claude Code versions used:** v2.1.132 (5 runs). Each link goes to a per-version snapshot of the system prompt, default-tool descriptions, and the chronological Anthropic changelog up to that version. Regenerate with `python3 version_docs.py`.

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
| powershell | haiku45-200k-na | A (6.8min) | A+ ($0.51) | — | — |
| typescript-bun | haiku45-200k-na | A+ (6.6min) | B- ($0.58) | — | — |
| bash | haiku45-200k-na | D- (7.9min) | A+ ($0.50) | — | — |
| default | haiku45-200k-na | C (7.4min) | D- ($0.68) | — | — |


<details>
<summary>Sorted by Duration tier (best-first), then avg of Cost/Tests/Workflow Craft tiers</summary>

| Language | Model | Duration | Cost | Tests Quality | Workflow Craft |
|----------|-------|----------|------|-----------|-------------|
| typescript-bun | haiku45-200k-na | A+ (6.6min) | B- ($0.58) | — | — |
| powershell | haiku45-200k-na | A (6.8min) | A+ ($0.51) | — | — |
| default | haiku45-200k-na | C (7.4min) | D- ($0.68) | — | — |
| bash | haiku45-200k-na | D- (7.9min) | A+ ($0.50) | — | — |

</details>

<details>
<summary>Sorted by Cost tier (best-first), then avg of Duration/Tests/Workflow Craft tiers</summary>

| Language | Model | Duration | Cost | Tests Quality | Workflow Craft |
|----------|-------|----------|------|-----------|-------------|
| powershell | haiku45-200k-na | A (6.8min) | A+ ($0.51) | — | — |
| bash | haiku45-200k-na | D- (7.9min) | A+ ($0.50) | — | — |
| typescript-bun | haiku45-200k-na | A+ (6.6min) | B- ($0.58) | — | — |
| default | haiku45-200k-na | C (7.4min) | D- ($0.68) | — | — |

</details>

<details>
<summary>Sorted by Tests Quality tier (best-first; no-data last), then avg of other tiers</summary>

| Language | Model | Duration | Cost | Tests Quality | Workflow Craft |
|----------|-------|----------|------|-----------|-------------|
| powershell | haiku45-200k-na | A (6.8min) | A+ ($0.51) | — | — |
| typescript-bun | haiku45-200k-na | A+ (6.6min) | B- ($0.58) | — | — |
| bash | haiku45-200k-na | D- (7.9min) | A+ ($0.50) | — | — |
| default | haiku45-200k-na | C (7.4min) | D- ($0.68) | — | — |

</details>

<details>
<summary>Sorted by Workflow Craft tier (best-first; no-data last), then avg of other tiers</summary>

| Language | Model | Duration | Cost | Tests Quality | Workflow Craft |
|----------|-------|----------|------|-----------|-------------|
| powershell | haiku45-200k-na | A (6.8min) | A+ ($0.51) | — | — |
| typescript-bun | haiku45-200k-na | A+ (6.6min) | B- ($0.58) | — | — |
| bash | haiku45-200k-na | D- (7.9min) | A+ ($0.50) | — | — |
| default | haiku45-200k-na | C (7.4min) | D- ($0.68) | — | — |

</details>

- **Estimated time remaining:** 22.0min
- **Estimated total cost:** $4.44

## Comparison by Language/Model/Effort
*See [Notes](#notes) for scoring rubric and CLI version legend.*

| Language | Model | Runs | Geo Duration | Max Duration | Geo Duration Net of Traps | Avg Errors | Geo Turns | Geo Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| bash | haiku45-200k-na | 2 | 7.9min | 8.2min | 7.1min | 4.5 | 58 | $0.50 | $1.00 | — | — |
| default | haiku45-200k-na | 1 | 7.4min | 7.4min | 7.4min | 7.0 | 67 | $0.68 | $0.68 | — | — |
| powershell | haiku45-200k-na | 1 | 6.8min | 6.8min | 3.8min | 2.0 | 50 | $0.51 | $0.51 | — | — |
| typescript-bun | haiku45-200k-na | 1 | 6.6min | 6.6min | 1.2min | 4.0 | 56 | $0.58 | $0.58 | — | — |


<details>
<summary>Sorted by cost (geomean, cheapest first)</summary>

| Language | Model | Runs | Geo Duration | Max Duration | Geo Duration Net of Traps | Avg Errors | Geo Turns | Geo Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| bash | haiku45-200k-na | 2 | 7.9min | 8.2min | 7.1min | 4.5 | 58 | $0.50 | $1.00 | — | — |
| powershell | haiku45-200k-na | 1 | 6.8min | 6.8min | 3.8min | 2.0 | 50 | $0.51 | $0.51 | — | — |
| typescript-bun | haiku45-200k-na | 1 | 6.6min | 6.6min | 1.2min | 4.0 | 56 | $0.58 | $0.58 | — | — |
| default | haiku45-200k-na | 1 | 7.4min | 7.4min | 7.4min | 7.0 | 67 | $0.68 | $0.68 | — | — |

</details>

<details>
<summary>Sorted by duration (geomean, fastest first)</summary>

| Language | Model | Runs | Geo Duration | Max Duration | Geo Duration Net of Traps | Avg Errors | Geo Turns | Geo Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| typescript-bun | haiku45-200k-na | 1 | 6.6min | 6.6min | 1.2min | 4.0 | 56 | $0.58 | $0.58 | — | — |
| powershell | haiku45-200k-na | 1 | 6.8min | 6.8min | 3.8min | 2.0 | 50 | $0.51 | $0.51 | — | — |
| default | haiku45-200k-na | 1 | 7.4min | 7.4min | 7.4min | 7.0 | 67 | $0.68 | $0.68 | — | — |
| bash | haiku45-200k-na | 2 | 7.9min | 8.2min | 7.1min | 4.5 | 58 | $0.50 | $1.00 | — | — |

</details>

<details>
<summary>Sorted by duration net of traps (geomean, fastest first)</summary>

| Language | Model | Runs | Geo Duration | Max Duration | Geo Duration Net of Traps | Avg Errors | Geo Turns | Geo Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| typescript-bun | haiku45-200k-na | 1 | 6.6min | 6.6min | 1.2min | 4.0 | 56 | $0.58 | $0.58 | — | — |
| powershell | haiku45-200k-na | 1 | 6.8min | 6.8min | 3.8min | 2.0 | 50 | $0.51 | $0.51 | — | — |
| bash | haiku45-200k-na | 2 | 7.9min | 8.2min | 7.1min | 4.5 | 58 | $0.50 | $1.00 | — | — |
| default | haiku45-200k-na | 1 | 7.4min | 7.4min | 7.4min | 7.0 | 67 | $0.68 | $0.68 | — | — |

</details>

<details>
<summary>Sorted by avg errors (fewest first)</summary>

| Language | Model | Runs | Geo Duration | Max Duration | Geo Duration Net of Traps | Avg Errors | Geo Turns | Geo Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| powershell | haiku45-200k-na | 1 | 6.8min | 6.8min | 3.8min | 2.0 | 50 | $0.51 | $0.51 | — | — |
| typescript-bun | haiku45-200k-na | 1 | 6.6min | 6.6min | 1.2min | 4.0 | 56 | $0.58 | $0.58 | — | — |
| bash | haiku45-200k-na | 2 | 7.9min | 8.2min | 7.1min | 4.5 | 58 | $0.50 | $1.00 | — | — |
| default | haiku45-200k-na | 1 | 7.4min | 7.4min | 7.4min | 7.0 | 67 | $0.68 | $0.68 | — | — |

</details>

<details>
<summary>Sorted by turns (geomean, fewest first)</summary>

| Language | Model | Runs | Geo Duration | Max Duration | Geo Duration Net of Traps | Avg Errors | Geo Turns | Geo Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| powershell | haiku45-200k-na | 1 | 6.8min | 6.8min | 3.8min | 2.0 | 50 | $0.51 | $0.51 | — | — |
| typescript-bun | haiku45-200k-na | 1 | 6.6min | 6.6min | 1.2min | 4.0 | 56 | $0.58 | $0.58 | — | — |
| bash | haiku45-200k-na | 2 | 7.9min | 8.2min | 7.1min | 4.5 | 58 | $0.50 | $1.00 | — | — |
| default | haiku45-200k-na | 1 | 7.4min | 7.4min | 7.4min | 7.0 | 67 | $0.68 | $0.68 | — | — |

</details>

<details>
<summary>Sorted by LLM-as-judge score (best first)</summary>

| Language | Model | Runs | Geo Duration | Max Duration | Geo Duration Net of Traps | Avg Errors | Geo Turns | Geo Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| bash | haiku45-200k-na | 2 | 7.9min | 8.2min | 7.1min | 4.5 | 58 | $0.50 | $1.00 | — | — |
| default | haiku45-200k-na | 1 | 7.4min | 7.4min | 7.4min | 7.0 | 67 | $0.68 | $0.68 | — | — |
| powershell | haiku45-200k-na | 1 | 6.8min | 6.8min | 3.8min | 2.0 | 50 | $0.51 | $0.51 | — | — |
| typescript-bun | haiku45-200k-na | 1 | 6.6min | 6.6min | 1.2min | 4.0 | 56 | $0.58 | $0.58 | — | — |

</details>

<details>
<summary>Sorted by deliverable-quality score (best first)</summary>

| Language | Model | Runs | Geo Duration | Max Duration | Geo Duration Net of Traps | Avg Errors | Geo Turns | Geo Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| bash | haiku45-200k-na | 2 | 7.9min | 8.2min | 7.1min | 4.5 | 58 | $0.50 | $1.00 | — | — |
| default | haiku45-200k-na | 1 | 7.4min | 7.4min | 7.4min | 7.0 | 67 | $0.68 | $0.68 | — | — |
| powershell | haiku45-200k-na | 1 | 6.8min | 6.8min | 3.8min | 2.0 | 50 | $0.51 | $0.51 | — | — |
| typescript-bun | haiku45-200k-na | 1 | 6.6min | 6.6min | 1.2min | 4.0 | 56 | $0.58 | $0.58 | — | — |

</details>

## Savings Analysis

### Trap Analysis by Language/Model/Effort/Category

| Trap | Language | Model | Fell In | Time Lost | % of Time | $ Lost | % of $ |
|------|------|-------|---------|-----------|-----------|--------|--------|
| repeated-test-reruns | bash | haiku45-200k-na-cli2.1.132 | 2 | 1.7min | 4.6% | $0.10 | 3.74% |
| repeated-test-reruns | powershell | haiku45-200k-na-cli2.1.132 | 1 | 1.3min | 3.6% | $0.10 | 3.63% |
| repeated-test-reruns | typescript-bun | haiku45-200k-na-cli2.1.132 | 1 | 1.3min | 3.6% | $0.12 | 4.21% |
| fixture-rework | typescript-bun | haiku45-200k-na-cli2.1.132 | 1 | 2.7min | 7.3% | $0.23 | 8.42% |
| actionlint-fix-cycles | powershell | haiku45-200k-na-cli2.1.132 | 1 | 0.7min | 1.8% | $0.05 | 1.82% |
| actionlint-fix-cycles | typescript-bun | haiku45-200k-na-cli2.1.132 | 1 | 0.7min | 1.8% | $0.06 | 2.11% |
| act-push-debug-loops | powershell | haiku45-200k-na-cli2.1.132 | 1 | 1.0min | 2.7% | $0.07 | 2.66% |
| act-permission-path-errors | typescript-bun | haiku45-200k-na-cli2.1.132 | 1 | 0.8min | 2.0% | $0.07 | 2.37% |


<details>
<summary>Sorted by time lost (least first)</summary>

| Trap | Language | Model | Fell In | Time Lost | % of Time | $ Lost | % of $ |
|------|------|-------|---------|-----------|-----------|--------|--------|
| actionlint-fix-cycles | powershell | haiku45-200k-na-cli2.1.132 | 1 | 0.7min | 1.8% | $0.05 | 1.82% |
| actionlint-fix-cycles | typescript-bun | haiku45-200k-na-cli2.1.132 | 1 | 0.7min | 1.8% | $0.06 | 2.11% |
| act-permission-path-errors | typescript-bun | haiku45-200k-na-cli2.1.132 | 1 | 0.8min | 2.0% | $0.07 | 2.37% |
| act-push-debug-loops | powershell | haiku45-200k-na-cli2.1.132 | 1 | 1.0min | 2.7% | $0.07 | 2.66% |
| repeated-test-reruns | powershell | haiku45-200k-na-cli2.1.132 | 1 | 1.3min | 3.6% | $0.10 | 3.63% |
| repeated-test-reruns | typescript-bun | haiku45-200k-na-cli2.1.132 | 1 | 1.3min | 3.6% | $0.12 | 4.21% |
| repeated-test-reruns | bash | haiku45-200k-na-cli2.1.132 | 2 | 1.7min | 4.6% | $0.10 | 3.74% |
| fixture-rework | typescript-bun | haiku45-200k-na-cli2.1.132 | 1 | 2.7min | 7.3% | $0.23 | 8.42% |

</details>

<details>
<summary>Sorted by $ lost (least first)</summary>

| Trap | Language | Model | Fell In | Time Lost | % of Time | $ Lost | % of $ |
|------|------|-------|---------|-----------|-----------|--------|--------|
| actionlint-fix-cycles | powershell | haiku45-200k-na-cli2.1.132 | 1 | 0.7min | 1.8% | $0.05 | 1.82% |
| actionlint-fix-cycles | typescript-bun | haiku45-200k-na-cli2.1.132 | 1 | 0.7min | 1.8% | $0.06 | 2.11% |
| act-permission-path-errors | typescript-bun | haiku45-200k-na-cli2.1.132 | 1 | 0.8min | 2.0% | $0.07 | 2.37% |
| act-push-debug-loops | powershell | haiku45-200k-na-cli2.1.132 | 1 | 1.0min | 2.7% | $0.07 | 2.66% |
| repeated-test-reruns | powershell | haiku45-200k-na-cli2.1.132 | 1 | 1.3min | 3.6% | $0.10 | 3.63% |
| repeated-test-reruns | bash | haiku45-200k-na-cli2.1.132 | 2 | 1.7min | 4.6% | $0.10 | 3.74% |
| repeated-test-reruns | typescript-bun | haiku45-200k-na-cli2.1.132 | 1 | 1.3min | 3.6% | $0.12 | 4.21% |
| fixture-rework | typescript-bun | haiku45-200k-na-cli2.1.132 | 1 | 2.7min | 7.3% | $0.23 | 8.42% |

</details>

<details>
<summary>Sorted by fell-in count (fewest first)</summary>

| Trap | Language | Model | Fell In | Time Lost | % of Time | $ Lost | % of $ |
|------|------|-------|---------|-----------|-----------|--------|--------|
| repeated-test-reruns | powershell | haiku45-200k-na-cli2.1.132 | 1 | 1.3min | 3.6% | $0.10 | 3.63% |
| repeated-test-reruns | typescript-bun | haiku45-200k-na-cli2.1.132 | 1 | 1.3min | 3.6% | $0.12 | 4.21% |
| fixture-rework | typescript-bun | haiku45-200k-na-cli2.1.132 | 1 | 2.7min | 7.3% | $0.23 | 8.42% |
| actionlint-fix-cycles | powershell | haiku45-200k-na-cli2.1.132 | 1 | 0.7min | 1.8% | $0.05 | 1.82% |
| actionlint-fix-cycles | typescript-bun | haiku45-200k-na-cli2.1.132 | 1 | 0.7min | 1.8% | $0.06 | 2.11% |
| act-push-debug-loops | powershell | haiku45-200k-na-cli2.1.132 | 1 | 1.0min | 2.7% | $0.07 | 2.66% |
| act-permission-path-errors | typescript-bun | haiku45-200k-na-cli2.1.132 | 1 | 0.8min | 2.0% | $0.07 | 2.37% |
| repeated-test-reruns | bash | haiku45-200k-na-cli2.1.132 | 2 | 1.7min | 4.6% | $0.10 | 3.74% |

</details>

#### Trap Descriptions

- **act-permission-path-errors**: Files not found or permission denied inside the act Docker container.
- **act-push-debug-loops**: Agent ran `act push` more than twice, indicating repeated workflow debugging.
- **actionlint-fix-cycles**: Workflow YAML required 3+ actionlint runs and 2+ fixes to pass.
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
| bash | haiku45-200k-na-cli2.1.132 | 2 | 2 | 1.7min | 4.6% | $0.10 | 3.74% |
| default | haiku45-200k-na-cli2.1.132 | 1 | 0 | 0.0min | 0.0% | $0.00 | 0.00% |
| powershell | haiku45-200k-na-cli2.1.132 | 1 | 3 | 3.0min | 8.1% | $0.22 | 8.11% |
| typescript-bun | haiku45-200k-na-cli2.1.132 | 1 | 4 | 5.4min | 14.8% | $0.47 | 17.11% |


<details>
<summary>Sorted by time lost (least first)</summary>

| Language | Model | Runs | Traps | Time Lost | % of Time | $ Lost | % of $ |
|------|-------|------|-------|-----------|-----------|--------|--------|
| default | haiku45-200k-na-cli2.1.132 | 1 | 0 | 0.0min | 0.0% | $0.00 | 0.00% |
| bash | haiku45-200k-na-cli2.1.132 | 2 | 2 | 1.7min | 4.6% | $0.10 | 3.74% |
| powershell | haiku45-200k-na-cli2.1.132 | 1 | 3 | 3.0min | 8.1% | $0.22 | 8.11% |
| typescript-bun | haiku45-200k-na-cli2.1.132 | 1 | 4 | 5.4min | 14.8% | $0.47 | 17.11% |

</details>

<details>
<summary>Sorted by $ lost (least first)</summary>

| Language | Model | Runs | Traps | Time Lost | % of Time | $ Lost | % of $ |
|------|-------|------|-------|-----------|-----------|--------|--------|
| default | haiku45-200k-na-cli2.1.132 | 1 | 0 | 0.0min | 0.0% | $0.00 | 0.00% |
| bash | haiku45-200k-na-cli2.1.132 | 2 | 2 | 1.7min | 4.6% | $0.10 | 3.74% |
| powershell | haiku45-200k-na-cli2.1.132 | 1 | 3 | 3.0min | 8.1% | $0.22 | 8.11% |
| typescript-bun | haiku45-200k-na-cli2.1.132 | 1 | 4 | 5.4min | 14.8% | $0.47 | 17.11% |

</details>

### Prompt Cache Savings

| Status | Runs | $ Saved | % of $ |
|--------|------|---------|--------|
| Full hit (100%) | 0 | $0.00 | 0.00% |
| Partial | 5 | $0.07 | 2.60% |
| Miss | 0 | $0.00 | 0.00% |

## Test Quality Evaluation

### Structural Metrics by Language/Model/Effort

Automated analysis of test files: test count, assertion count, and test-to-code line ratio.

| Language | Model | Avg Tests | Avg Assertions | Avg Assert/Test | Avg Test:Code Ratio |
|------|-------|-----------|----------------|-----------------|---------------------|
| bash | haiku45-200k-na | 12.5 | 12.5 | 1.0 | 0.39 |
| default | haiku45-200k-na | 22.0 | 29.0 | 1.3 | 0.78 |
| powershell | haiku45-200k-na | 0.0 | 0.0 | 0.0 | 0.00 |
| typescript-bun | haiku45-200k-na | 15.0 | 22.0 | 1.5 | 0.46 |


<details>
<summary>Sorted by avg tests (most first)</summary>

| Language | Model | Avg Tests | Avg Assertions | Avg Assert/Test | Avg Test:Code Ratio |
|------|-------|-----------|----------------|-----------------|---------------------|
| default | haiku45-200k-na | 22.0 | 29.0 | 1.3 | 0.78 |
| typescript-bun | haiku45-200k-na | 15.0 | 22.0 | 1.5 | 0.46 |
| bash | haiku45-200k-na | 12.5 | 12.5 | 1.0 | 0.39 |
| powershell | haiku45-200k-na | 0.0 | 0.0 | 0.0 | 0.00 |

</details>

<details>
<summary>Sorted by avg assertions (most first)</summary>

| Language | Model | Avg Tests | Avg Assertions | Avg Assert/Test | Avg Test:Code Ratio |
|------|-------|-----------|----------------|-----------------|---------------------|
| default | haiku45-200k-na | 22.0 | 29.0 | 1.3 | 0.78 |
| typescript-bun | haiku45-200k-na | 15.0 | 22.0 | 1.5 | 0.46 |
| bash | haiku45-200k-na | 12.5 | 12.5 | 1.0 | 0.39 |
| powershell | haiku45-200k-na | 0.0 | 0.0 | 0.0 | 0.00 |

</details>

<details>
<summary>Sorted by avg test:code ratio (highest first)</summary>

| Language | Model | Avg Tests | Avg Assertions | Avg Assert/Test | Avg Test:Code Ratio |
|------|-------|-----------|----------------|-----------------|---------------------|
| default | haiku45-200k-na | 22.0 | 29.0 | 1.3 | 0.78 |
| typescript-bun | haiku45-200k-na | 15.0 | 22.0 | 1.5 | 0.46 |
| bash | haiku45-200k-na | 12.5 | 12.5 | 1.0 | 0.39 |
| powershell | haiku45-200k-na | 0.0 | 0.0 | 0.0 | 0.00 |

</details>


<details>
<summary>Per-run structural metrics</summary>

| Task | Language | Model | Tests | Assertions | Assert/Test | Test Lines | Impl Lines | Test:Code |
|------|------|-------|-------|------------|-------------|------------|------------|-----------|
| Semantic Version Bumper | bash | haiku45-200k-na | 10 | 8 | 0.8 | 162 | 496 | 0.33 |
| Semantic Version Bumper | default | haiku45-200k-na | 22 | 29 | 1.3 | 594 | 761 | 0.78 |
| Semantic Version Bumper | powershell | haiku45-200k-na | 0 | 0 | 0.0 | 0 | 796 | 0.00 |
| Semantic Version Bumper | typescript-bun | haiku45-200k-na | 15 | 22 | 1.5 | 175 | 380 | 0.46 |
| Environment Matrix Generator | bash | haiku45-200k-na | 15 | 17 | 1.1 | 174 | 383 | 0.45 |

</details>

## Per-Run Results

*Tests Quality = Overall (1-5) from LLM-as-judge of generated test code (dimensions: coverage, rigor, design). `—` = no judge data.*

| Task | Language | Model | Duration | Turns | Errors | Cost | Tests Quality | Chosen | Status |
|------|----------|-------|----------|-------|--------|------|-----------|--------|--------|
| Environment Matrix Generator | bash | haiku45-200k-na | 7.7min | 60 | 4 | $0.45 | — | bash | ok |
| Semantic Version Bumper | bash | haiku45-200k-na | 8.2min | 57 | 5 | $0.55 | — | bash | ok |
| Semantic Version Bumper | default | haiku45-200k-na | 7.4min | 67 | 7 | $0.68 | — | python | ok |
| Semantic Version Bumper | powershell | haiku45-200k-na | 6.8min | 50 | 2 | $0.51 | — | powershell | ok |
| Semantic Version Bumper | typescript-bun | haiku45-200k-na | 6.6min | 56 | 4 | $0.58 | — | typescript | ok |


<details>
<summary>Sorted by cost (cheapest first)</summary>

| Task | Language | Model | Duration | Turns | Errors | Cost | Tests Quality | Chosen | Status |
|------|----------|-------|----------|-------|--------|------|-----------|--------|--------|
| Environment Matrix Generator | bash | haiku45-200k-na | 7.7min | 60 | 4 | $0.45 | — | bash | ok |
| Semantic Version Bumper | powershell | haiku45-200k-na | 6.8min | 50 | 2 | $0.51 | — | powershell | ok |
| Semantic Version Bumper | bash | haiku45-200k-na | 8.2min | 57 | 5 | $0.55 | — | bash | ok |
| Semantic Version Bumper | typescript-bun | haiku45-200k-na | 6.6min | 56 | 4 | $0.58 | — | typescript | ok |
| Semantic Version Bumper | default | haiku45-200k-na | 7.4min | 67 | 7 | $0.68 | — | python | ok |

</details>

<details>
<summary>Sorted by duration (fastest first)</summary>

| Task | Language | Model | Duration | Turns | Errors | Cost | Tests Quality | Chosen | Status |
|------|----------|-------|----------|-------|--------|------|-----------|--------|--------|
| Semantic Version Bumper | typescript-bun | haiku45-200k-na | 6.6min | 56 | 4 | $0.58 | — | typescript | ok |
| Semantic Version Bumper | powershell | haiku45-200k-na | 6.8min | 50 | 2 | $0.51 | — | powershell | ok |
| Semantic Version Bumper | default | haiku45-200k-na | 7.4min | 67 | 7 | $0.68 | — | python | ok |
| Environment Matrix Generator | bash | haiku45-200k-na | 7.7min | 60 | 4 | $0.45 | — | bash | ok |
| Semantic Version Bumper | bash | haiku45-200k-na | 8.2min | 57 | 5 | $0.55 | — | bash | ok |

</details>

<details>
<summary>Sorted by errors (fewest first)</summary>

| Task | Language | Model | Duration | Turns | Errors | Cost | Tests Quality | Chosen | Status |
|------|----------|-------|----------|-------|--------|------|-----------|--------|--------|
| Semantic Version Bumper | powershell | haiku45-200k-na | 6.8min | 50 | 2 | $0.51 | — | powershell | ok |
| Semantic Version Bumper | typescript-bun | haiku45-200k-na | 6.6min | 56 | 4 | $0.58 | — | typescript | ok |
| Environment Matrix Generator | bash | haiku45-200k-na | 7.7min | 60 | 4 | $0.45 | — | bash | ok |
| Semantic Version Bumper | bash | haiku45-200k-na | 8.2min | 57 | 5 | $0.55 | — | bash | ok |
| Semantic Version Bumper | default | haiku45-200k-na | 7.4min | 67 | 7 | $0.68 | — | python | ok |

</details>

<details>
<summary>Sorted by turns (fewest first)</summary>

| Task | Language | Model | Duration | Turns | Errors | Cost | Tests Quality | Chosen | Status |
|------|----------|-------|----------|-------|--------|------|-----------|--------|--------|
| Semantic Version Bumper | powershell | haiku45-200k-na | 6.8min | 50 | 2 | $0.51 | — | powershell | ok |
| Semantic Version Bumper | typescript-bun | haiku45-200k-na | 6.6min | 56 | 4 | $0.58 | — | typescript | ok |
| Semantic Version Bumper | bash | haiku45-200k-na | 8.2min | 57 | 5 | $0.55 | — | bash | ok |
| Environment Matrix Generator | bash | haiku45-200k-na | 7.7min | 60 | 4 | $0.45 | — | bash | ok |
| Semantic Version Bumper | default | haiku45-200k-na | 7.4min | 67 | 7 | $0.68 | — | python | ok |

</details>

<details>
<summary>Sorted by LLM-as-judge score (best first)</summary>

| Task | Language | Model | Duration | Turns | Errors | Cost | Tests Quality | Chosen | Status |
|------|----------|-------|----------|-------|--------|------|-----------|--------|--------|
| Semantic Version Bumper | bash | haiku45-200k-na | 8.2min | 57 | 5 | $0.55 | — | bash | ok |
| Semantic Version Bumper | default | haiku45-200k-na | 7.4min | 67 | 7 | $0.68 | — | python | ok |
| Semantic Version Bumper | powershell | haiku45-200k-na | 6.8min | 50 | 2 | $0.51 | — | powershell | ok |
| Semantic Version Bumper | typescript-bun | haiku45-200k-na | 6.6min | 56 | 4 | $0.58 | — | typescript | ok |
| Environment Matrix Generator | bash | haiku45-200k-na | 7.7min | 60 | 4 | $0.45 | — | bash | ok |

</details>

## Notes

### Tiers

- **Duration bands:** **A+** ≤1.02×, **A** ≤1.03×, **A-** ≤1.05×, **B+** ≤1.06×, **B** ≤1.08×, **B-** ≤1.09×, **C+** ≤1.11×, **C** ≤1.13×, **C-** ≤1.14×, **D+** ≤1.16×, **D** ≤1.18×, **D-** ≤1.20×, **F** >1.20×
- **Cost bands:** **A+** ≤1.03×, **A** ≤1.05×, **A-** ≤1.08×, **B+** ≤1.11×, **B** ≤1.14×, **B-** ≤1.17×, **C+** ≤1.20×, **C** ≤1.23×, **C-** ≤1.26×, **D+** ≤1.30×, **D** ≤1.33×, **D-** ≤1.37×, **F** >1.37×

*Tests/Workflow Craft bands are absolute Overall score bands:* **A+** ≥4.7, **A** ≥4.4, **A-** ≥4.1, **B+** ≥3.8, **B** ≥3.5, **B-** ≥3.2, **C+** ≥2.9, **C** ≥2.6, **C-** ≥2.3, **D+** ≥2.0, **D** ≥1.7, **D-** ≥1.4, **F** <1.4, `—` = no data.*

### CLI Version Legend

| Variant label | CLI version | Tasks | Languages |
|---------------|-------------|-------|-----------|
| haiku45-200k-na | 2.1.132 | All | All |

---
*Generated by generate_results.py — benchmark instructions v4*