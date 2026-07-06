# Benchmark Results: Language Comparison

**Last updated:** 2026-07-06 01:03:23 PM ET — 245/245 runs completed, 0 remaining; total cost $360.74; total agent time 2265.0 min.
**Claude Code versions used:** [v2.1.112](claude-code-2.1.112.md) (70 runs), [v2.1.114](claude-code-2.1.114.md) (175 runs). Each link goes to a per-version snapshot of the system prompt, default-tool descriptions, and the chronological Anthropic changelog up to that version. Regenerate with `python3 version_docs.py`.

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
- The **Geo Duration pool additionally includes timed-out runs**, counted at their recorded wall clock. A timeout is right-censored — its true duration might have been longer, but is known to be AT LEAST the recorded value — so excluding it outright would effectively reward timing out with a better average.
- **Total Cost** now includes timed-out cells: the CLI-recorded cost when the stream captured a final result record, otherwise a **floor estimate recovered from the partial `cli-output.json` event stream** (see `recover_cost.py`) — input / cache-read / cache-write tokens are exact per-message usage; output tokens are estimated from visible content plus thinking-token telemetry (a lower bound: most thinking output never appears in a killed stream) and priced via `models.py`. Rows containing a timeout without CLI-recorded cost are `≥`-prefixed.
- **Geo Cost / Geo Turns still exclude every failed run, including timeouts**: a killed CLI records `cost=0`/`turns=0`, which is missing data, not a real zero, and recovered floors are estimates — pooling a known-low bound into a geometric mean would bias the ratio statistics the tiers are built from. The exact-vs-floor distinction only affects the additive Total Cost column.
- **Max Duration** is the slowest run in the Geo Duration pool for that combo, `≥`-prefixed when that run was a timeout (true duration unknown, but at least the shown value).
- **Avg Errors** remains an arithmetic mean.
- **Geo Duration Net of Traps** (in the Comparison table only): the geometric mean of (per-run `Duration` − that run's `Time Lost`), where `Time Lost` is the trap detector's estimate of seconds spent on detected anti-patterns (see [Trap Descriptions](#trap-descriptions) and the trap-table [Column Definitions](#column-definitions) for the trap list and how Time Lost is computed). Pooled over the SAME runs as Geo Duration — timed-out cells are included, with their detected traps (if any) deducted too. Reads as a counterfactual: roughly how fast each combo would have been without the detected traps.
- The **Tier table's Duration/Cost columns** show the tier letter (A+..F) for the combo's gross **Geo Duration**/**Geo Cost** ratio. Net of Traps does not feed the tier band.
## Tiers by Language/Model/Effort

*Default sort: weighted composite of tiers (40% Tests, 25% Workflow Craft, 35% split between Duration & Cost). See [Notes](#notes) for tier-band definitions and scoring rubric.*
*`*` after a Model label = one or more of this combo's runs failed or timed out — excluded from the cost/turns/errors aggregates, though timeouts still pool into the duration stats (see the Failed / Timed-Out Runs table).*

| Language | Model | Duration | Cost | Tests Quality | Workflow Craft |
|----------|-------|----------|------|-----------|-------------|
| default | opus47-200k-medium | A+ (4.6min) | B- ($1.13) | B+ (3.8) | B (3.6) |
| bash | opus47-200k-medium | A+ (4.5min) | B- ($1.09) | B- (3.2) | A- (4.2) |
| default | opus47-1m-high | B (7.1min) | C- ($1.92) | A- (4.2) | A- (4.2) |
| powershell | sonnet46-200k-medium | B+ (6.1min) | B+ ($0.79) | B (3.5) | B- (3.3) |
| powershell | opus47-1m-high | C+ (8.6min) | D+ ($2.35) | A- (4.2) | A- (4.2) |
| typescript-bun | opus47-200k-medium | A (5.4min) | C+ ($1.31) | B (3.8) | B- (3.4) |
| bash | opus47-1m-high | B+ (6.5min) | C ($1.59) | B (3.5) | B+ (4.0) |
| bash | opus47-1m-medium | A+ (4.8min) | B- ($1.08) | B- (3.2) | B- (3.2) |
| powershell | opus47-1m-medium | B- (7.9min) | C+ ($1.40) | B+ (3.9) | B (3.7) |
| default | opus47-1m-xhigh | B- (7.7min) | D+ ($2.27) | B+ (4.0) | A- (4.2) |
| powershell | opus47-200k-medium | A- (5.9min) | C ($1.49) | B (3.8) | B (3.5) |
| bash | sonnet46-200k-medium* | B+ (6.1min) | B+ ($0.82) | B- (3.2) | B- (3.2) |
| default | opus47-1m-medium | A (5.1min) | B- ($1.02) | B- (3.4) | B- (3.4) |
| default | sonnet46-200k-medium | B+ (6.3min) | B ($0.95) | B (3.6) | C+ (3.1) |
| powershell | sonnet46-1m-medium | B- (7.5min) | B ($0.99) | B (3.5) | B- (3.2) |
| typescript-bun | opus47-1m-medium | B- (7.5min) | C+ ($1.28) | B (3.8) | B (3.5) |
| typescript-bun | sonnet46-1m-medium | B- (7.8min) | B- ($1.03) | B (3.6) | B- (3.4) |
| typescript-bun | opus47-1m-xhigh | D+ (11.4min) | D- ($3.34) | A (4.5) | B+ (4.0) |
| default | sonnet46-1m-medium | B+ (6.5min) | B ($0.93) | B- (3.3) | C+ (3.1) |
| typescript-bun | opus47-1m-high | C (8.9min) | D+ ($2.30) | B+ (4.1) | B+ (3.9) |
| typescript-bun | sonnet46-200k-medium | B (6.9min) | B ($0.87) | B- (3.2) | C+ (2.9) |
| powershell | opus47-1m-xhigh | D+ (10.7min) | D- ($3.08) | B+ (4.0) | A- (4.1) |
| bash | sonnet46-1m-medium | C- (10.0min) | C+ ($1.34) | B- (3.4) | B- (3.4) |
| powershell | haiku45-200k-na | B+ (6.2min) | A+ ($0.45) | C- (2.3) | C- (2.5) |
| default | haiku45-200k-na | A- (5.8min) | A+ ($0.42) | D+ (2.1) | C- (2.4) |
| typescript-bun | haiku45-200k-na | A- (5.6min) | A+ ($0.47) | D+ (2.1) | D+ (2.2) |
| bash | opus47-1m-xhigh | D- (14.1min) | D ($2.73) | B (3.7) | B (3.7) |
| bash | haiku45-200k-na* | D- (13.4min) | A+ ($0.47) | C- (2.3) | C- (2.5) |


<details>
<summary>Sorted by Duration tier (best-first), then avg of Cost/Tests/Workflow Craft tiers</summary>

| Language | Model | Duration | Cost | Tests Quality | Workflow Craft |
|----------|-------|----------|------|-----------|-------------|
| bash | opus47-200k-medium | A+ (4.5min) | B- ($1.09) | B- (3.2) | A- (4.2) |
| default | opus47-200k-medium | A+ (4.6min) | B- ($1.13) | B+ (3.8) | B (3.6) |
| bash | opus47-1m-medium | A+ (4.8min) | B- ($1.08) | B- (3.2) | B- (3.2) |
| default | opus47-1m-medium | A (5.1min) | B- ($1.02) | B- (3.4) | B- (3.4) |
| typescript-bun | opus47-200k-medium | A (5.4min) | C+ ($1.31) | B (3.8) | B- (3.4) |
| powershell | opus47-200k-medium | A- (5.9min) | C ($1.49) | B (3.8) | B (3.5) |
| default | haiku45-200k-na | A- (5.8min) | A+ ($0.42) | D+ (2.1) | C- (2.4) |
| typescript-bun | haiku45-200k-na | A- (5.6min) | A+ ($0.47) | D+ (2.1) | D+ (2.2) |
| powershell | sonnet46-200k-medium | B+ (6.1min) | B+ ($0.79) | B (3.5) | B- (3.3) |
| bash | sonnet46-200k-medium* | B+ (6.1min) | B+ ($0.82) | B- (3.2) | B- (3.2) |
| bash | opus47-1m-high | B+ (6.5min) | C ($1.59) | B (3.5) | B+ (4.0) |
| default | sonnet46-200k-medium | B+ (6.3min) | B ($0.95) | B (3.6) | C+ (3.1) |
| default | sonnet46-1m-medium | B+ (6.5min) | B ($0.93) | B- (3.3) | C+ (3.1) |
| powershell | haiku45-200k-na | B+ (6.2min) | A+ ($0.45) | C- (2.3) | C- (2.5) |
| default | opus47-1m-high | B (7.1min) | C- ($1.92) | A- (4.2) | A- (4.2) |
| typescript-bun | sonnet46-200k-medium | B (6.9min) | B ($0.87) | B- (3.2) | C+ (2.9) |
| powershell | opus47-1m-medium | B- (7.9min) | C+ ($1.40) | B+ (3.9) | B (3.7) |
| powershell | sonnet46-1m-medium | B- (7.5min) | B ($0.99) | B (3.5) | B- (3.2) |
| default | opus47-1m-xhigh | B- (7.7min) | D+ ($2.27) | B+ (4.0) | A- (4.2) |
| typescript-bun | opus47-1m-medium | B- (7.5min) | C+ ($1.28) | B (3.8) | B (3.5) |
| typescript-bun | sonnet46-1m-medium | B- (7.8min) | B- ($1.03) | B (3.6) | B- (3.4) |
| powershell | opus47-1m-high | C+ (8.6min) | D+ ($2.35) | A- (4.2) | A- (4.2) |
| typescript-bun | opus47-1m-high | C (8.9min) | D+ ($2.30) | B+ (4.1) | B+ (3.9) |
| bash | sonnet46-1m-medium | C- (10.0min) | C+ ($1.34) | B- (3.4) | B- (3.4) |
| typescript-bun | opus47-1m-xhigh | D+ (11.4min) | D- ($3.34) | A (4.5) | B+ (4.0) |
| powershell | opus47-1m-xhigh | D+ (10.7min) | D- ($3.08) | B+ (4.0) | A- (4.1) |
| bash | haiku45-200k-na* | D- (13.4min) | A+ ($0.47) | C- (2.3) | C- (2.5) |
| bash | opus47-1m-xhigh | D- (14.1min) | D ($2.73) | B (3.7) | B (3.7) |

</details>

<details>
<summary>Sorted by Cost tier (best-first), then avg of Duration/Tests/Workflow Craft tiers</summary>

| Language | Model | Duration | Cost | Tests Quality | Workflow Craft |
|----------|-------|----------|------|-----------|-------------|
| default | haiku45-200k-na | A- (5.8min) | A+ ($0.42) | D+ (2.1) | C- (2.4) |
| powershell | haiku45-200k-na | B+ (6.2min) | A+ ($0.45) | C- (2.3) | C- (2.5) |
| typescript-bun | haiku45-200k-na | A- (5.6min) | A+ ($0.47) | D+ (2.1) | D+ (2.2) |
| bash | haiku45-200k-na* | D- (13.4min) | A+ ($0.47) | C- (2.3) | C- (2.5) |
| powershell | sonnet46-200k-medium | B+ (6.1min) | B+ ($0.79) | B (3.5) | B- (3.3) |
| bash | sonnet46-200k-medium* | B+ (6.1min) | B+ ($0.82) | B- (3.2) | B- (3.2) |
| default | sonnet46-200k-medium | B+ (6.3min) | B ($0.95) | B (3.6) | C+ (3.1) |
| default | sonnet46-1m-medium | B+ (6.5min) | B ($0.93) | B- (3.3) | C+ (3.1) |
| powershell | sonnet46-1m-medium | B- (7.5min) | B ($0.99) | B (3.5) | B- (3.2) |
| typescript-bun | sonnet46-200k-medium | B (6.9min) | B ($0.87) | B- (3.2) | C+ (2.9) |
| bash | opus47-200k-medium | A+ (4.5min) | B- ($1.09) | B- (3.2) | A- (4.2) |
| default | opus47-200k-medium | A+ (4.6min) | B- ($1.13) | B+ (3.8) | B (3.6) |
| bash | opus47-1m-medium | A+ (4.8min) | B- ($1.08) | B- (3.2) | B- (3.2) |
| default | opus47-1m-medium | A (5.1min) | B- ($1.02) | B- (3.4) | B- (3.4) |
| typescript-bun | sonnet46-1m-medium | B- (7.8min) | B- ($1.03) | B (3.6) | B- (3.4) |
| typescript-bun | opus47-200k-medium | A (5.4min) | C+ ($1.31) | B (3.8) | B- (3.4) |
| powershell | opus47-1m-medium | B- (7.9min) | C+ ($1.40) | B+ (3.9) | B (3.7) |
| typescript-bun | opus47-1m-medium | B- (7.5min) | C+ ($1.28) | B (3.8) | B (3.5) |
| bash | sonnet46-1m-medium | C- (10.0min) | C+ ($1.34) | B- (3.4) | B- (3.4) |
| bash | opus47-1m-high | B+ (6.5min) | C ($1.59) | B (3.5) | B+ (4.0) |
| powershell | opus47-200k-medium | A- (5.9min) | C ($1.49) | B (3.8) | B (3.5) |
| default | opus47-1m-high | B (7.1min) | C- ($1.92) | A- (4.2) | A- (4.2) |
| default | opus47-1m-xhigh | B- (7.7min) | D+ ($2.27) | B+ (4.0) | A- (4.2) |
| powershell | opus47-1m-high | C+ (8.6min) | D+ ($2.35) | A- (4.2) | A- (4.2) |
| typescript-bun | opus47-1m-high | C (8.9min) | D+ ($2.30) | B+ (4.1) | B+ (3.9) |
| bash | opus47-1m-xhigh | D- (14.1min) | D ($2.73) | B (3.7) | B (3.7) |
| typescript-bun | opus47-1m-xhigh | D+ (11.4min) | D- ($3.34) | A (4.5) | B+ (4.0) |
| powershell | opus47-1m-xhigh | D+ (10.7min) | D- ($3.08) | B+ (4.0) | A- (4.1) |

</details>

<details>
<summary>Sorted by Tests Quality tier (best-first; no-data last), then avg of other tiers</summary>

| Language | Model | Duration | Cost | Tests Quality | Workflow Craft |
|----------|-------|----------|------|-----------|-------------|
| typescript-bun | opus47-1m-xhigh | D+ (11.4min) | D- ($3.34) | A (4.5) | B+ (4.0) |
| default | opus47-1m-high | B (7.1min) | C- ($1.92) | A- (4.2) | A- (4.2) |
| powershell | opus47-1m-high | C+ (8.6min) | D+ ($2.35) | A- (4.2) | A- (4.2) |
| default | opus47-200k-medium | A+ (4.6min) | B- ($1.13) | B+ (3.8) | B (3.6) |
| powershell | opus47-1m-medium | B- (7.9min) | C+ ($1.40) | B+ (3.9) | B (3.7) |
| default | opus47-1m-xhigh | B- (7.7min) | D+ ($2.27) | B+ (4.0) | A- (4.2) |
| typescript-bun | opus47-1m-high | C (8.9min) | D+ ($2.30) | B+ (4.1) | B+ (3.9) |
| powershell | opus47-1m-xhigh | D+ (10.7min) | D- ($3.08) | B+ (4.0) | A- (4.1) |
| powershell | sonnet46-200k-medium | B+ (6.1min) | B+ ($0.79) | B (3.5) | B- (3.3) |
| typescript-bun | opus47-200k-medium | A (5.4min) | C+ ($1.31) | B (3.8) | B- (3.4) |
| bash | opus47-1m-high | B+ (6.5min) | C ($1.59) | B (3.5) | B+ (4.0) |
| default | sonnet46-200k-medium | B+ (6.3min) | B ($0.95) | B (3.6) | C+ (3.1) |
| powershell | opus47-200k-medium | A- (5.9min) | C ($1.49) | B (3.8) | B (3.5) |
| powershell | sonnet46-1m-medium | B- (7.5min) | B ($0.99) | B (3.5) | B- (3.2) |
| typescript-bun | opus47-1m-medium | B- (7.5min) | C+ ($1.28) | B (3.8) | B (3.5) |
| typescript-bun | sonnet46-1m-medium | B- (7.8min) | B- ($1.03) | B (3.6) | B- (3.4) |
| bash | opus47-1m-xhigh | D- (14.1min) | D ($2.73) | B (3.7) | B (3.7) |
| bash | opus47-200k-medium | A+ (4.5min) | B- ($1.09) | B- (3.2) | A- (4.2) |
| bash | opus47-1m-medium | A+ (4.8min) | B- ($1.08) | B- (3.2) | B- (3.2) |
| bash | sonnet46-200k-medium* | B+ (6.1min) | B+ ($0.82) | B- (3.2) | B- (3.2) |
| default | opus47-1m-medium | A (5.1min) | B- ($1.02) | B- (3.4) | B- (3.4) |
| default | sonnet46-1m-medium | B+ (6.5min) | B ($0.93) | B- (3.3) | C+ (3.1) |
| typescript-bun | sonnet46-200k-medium | B (6.9min) | B ($0.87) | B- (3.2) | C+ (2.9) |
| bash | sonnet46-1m-medium | C- (10.0min) | C+ ($1.34) | B- (3.4) | B- (3.4) |
| powershell | haiku45-200k-na | B+ (6.2min) | A+ ($0.45) | C- (2.3) | C- (2.5) |
| bash | haiku45-200k-na* | D- (13.4min) | A+ ($0.47) | C- (2.3) | C- (2.5) |
| default | haiku45-200k-na | A- (5.8min) | A+ ($0.42) | D+ (2.1) | C- (2.4) |
| typescript-bun | haiku45-200k-na | A- (5.6min) | A+ ($0.47) | D+ (2.1) | D+ (2.2) |

</details>

<details>
<summary>Sorted by Workflow Craft tier (best-first; no-data last), then avg of other tiers</summary>

| Language | Model | Duration | Cost | Tests Quality | Workflow Craft |
|----------|-------|----------|------|-----------|-------------|
| bash | opus47-200k-medium | A+ (4.5min) | B- ($1.09) | B- (3.2) | A- (4.2) |
| default | opus47-1m-high | B (7.1min) | C- ($1.92) | A- (4.2) | A- (4.2) |
| default | opus47-1m-xhigh | B- (7.7min) | D+ ($2.27) | B+ (4.0) | A- (4.2) |
| powershell | opus47-1m-high | C+ (8.6min) | D+ ($2.35) | A- (4.2) | A- (4.2) |
| powershell | opus47-1m-xhigh | D+ (10.7min) | D- ($3.08) | B+ (4.0) | A- (4.1) |
| bash | opus47-1m-high | B+ (6.5min) | C ($1.59) | B (3.5) | B+ (4.0) |
| typescript-bun | opus47-1m-high | C (8.9min) | D+ ($2.30) | B+ (4.1) | B+ (3.9) |
| typescript-bun | opus47-1m-xhigh | D+ (11.4min) | D- ($3.34) | A (4.5) | B+ (4.0) |
| default | opus47-200k-medium | A+ (4.6min) | B- ($1.13) | B+ (3.8) | B (3.6) |
| powershell | opus47-200k-medium | A- (5.9min) | C ($1.49) | B (3.8) | B (3.5) |
| powershell | opus47-1m-medium | B- (7.9min) | C+ ($1.40) | B+ (3.9) | B (3.7) |
| typescript-bun | opus47-1m-medium | B- (7.5min) | C+ ($1.28) | B (3.8) | B (3.5) |
| bash | opus47-1m-xhigh | D- (14.1min) | D ($2.73) | B (3.7) | B (3.7) |
| bash | opus47-1m-medium | A+ (4.8min) | B- ($1.08) | B- (3.2) | B- (3.2) |
| powershell | sonnet46-200k-medium | B+ (6.1min) | B+ ($0.79) | B (3.5) | B- (3.3) |
| bash | sonnet46-200k-medium* | B+ (6.1min) | B+ ($0.82) | B- (3.2) | B- (3.2) |
| default | opus47-1m-medium | A (5.1min) | B- ($1.02) | B- (3.4) | B- (3.4) |
| typescript-bun | opus47-200k-medium | A (5.4min) | C+ ($1.31) | B (3.8) | B- (3.4) |
| powershell | sonnet46-1m-medium | B- (7.5min) | B ($0.99) | B (3.5) | B- (3.2) |
| typescript-bun | sonnet46-1m-medium | B- (7.8min) | B- ($1.03) | B (3.6) | B- (3.4) |
| bash | sonnet46-1m-medium | C- (10.0min) | C+ ($1.34) | B- (3.4) | B- (3.4) |
| default | sonnet46-200k-medium | B+ (6.3min) | B ($0.95) | B (3.6) | C+ (3.1) |
| default | sonnet46-1m-medium | B+ (6.5min) | B ($0.93) | B- (3.3) | C+ (3.1) |
| typescript-bun | sonnet46-200k-medium | B (6.9min) | B ($0.87) | B- (3.2) | C+ (2.9) |
| default | haiku45-200k-na | A- (5.8min) | A+ ($0.42) | D+ (2.1) | C- (2.4) |
| powershell | haiku45-200k-na | B+ (6.2min) | A+ ($0.45) | C- (2.3) | C- (2.5) |
| bash | haiku45-200k-na* | D- (13.4min) | A+ ($0.47) | C- (2.3) | C- (2.5) |
| typescript-bun | haiku45-200k-na | A- (5.6min) | A+ ($0.47) | D+ (2.1) | D+ (2.2) |

</details>

## Failed / Timed-Out Runs

| Task | Language | Model | Duration | Cost | Reason | Lines | actionlint | act-result.txt |
|------|------|-------|----------|------|--------|-------|------------|----------------|
| Environment Matrix Generator | bash | haiku45-200k-na | 322.8min | $0.75 | timeout | 377 | pass | yes |
| Environment Matrix Generator | bash | sonnet46-200k-medium | 4.2min | — | cli_error | 0 | n/a | no |

*2 run(s) excluded from averages below. Timed-out rows' cost is included in Total Cost above (recovered from the event stream when the CLI didn't record it — see [Column Definitions](#column-definitions)).*

## Comparison by Language/Model/Effort
*(failed runs are excluded from the cost/turns/errors averages; timed-out runs still pool into the duration stats, and timed-out runs' spend is folded into Total Cost — see [Column Definitions](#column-definitions))*
*See [Notes](#notes) for scoring rubric and CLI version legend.*

| Language | Model | Runs | Geo Duration | Max Duration | Geo Duration Net of Traps | Avg Errors | Geo Turns | Geo Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| bash | haiku45-200k-na* | 6 | 13.4min | ≥322.8min | 8.7min | 3.0 | 56 | $0.47 | $3.63 | 2.3 | 2.5 |
| bash | opus47-1m-high | 7 | 6.5min | 11.3min | 6.2min | 0.6 | 34 | $1.59 | $11.54 | 3.5 | 4.0 |
| bash | opus47-1m-medium | 7 | 4.8min | 6.7min | 4.8min | 1.1 | 27 | $1.08 | $7.74 | 3.2 | 3.2 |
| bash | opus47-1m-xhigh | 7 | 14.1min | 39.8min | 13.9min | 1.4 | 47 | $2.73 | $20.11 | 3.7 | 3.7 |
| bash | opus47-200k-medium | 7 | 4.5min | 7.5min | 4.5min | 1.1 | 26 | $1.09 | $7.66 | 3.2 | 4.2 |
| bash | sonnet46-1m-medium | 7 | 10.0min | 29.1min | 9.3min | 4.6 | 40 | $1.34 | $10.71 | 3.4 | 3.4 |
| bash | sonnet46-200k-medium* | 6 | 6.1min | 8.6min | 5.8min | 2.3 | 34 | $0.82 | $5.01 | 3.2 | 3.2 |
| default | haiku45-200k-na | 7 | 5.8min | 59.1min | 4.8min | 5.4 | 47 | $0.42 | $3.17 | 2.1 | 2.4 |
| default | opus47-1m-high | 7 | 7.1min | 8.5min | 7.0min | 0.3 | 34 | $1.92 | $13.67 | 4.2 | 4.2 |
| default | opus47-1m-medium | 7 | 5.1min | 8.2min | 5.1min | 0.3 | 24 | $1.02 | $7.24 | 3.4 | 3.4 |
| default | opus47-1m-xhigh | 7 | 7.7min | 9.2min | 7.5min | 0.6 | 42 | $2.27 | $16.00 | 4.0 | 4.2 |
| default | opus47-200k-medium | 7 | 4.6min | 6.1min | 4.6min | 0.4 | 26 | $1.13 | $8.18 | 3.8 | 3.6 |
| default | sonnet46-1m-medium | 7 | 6.5min | 9.6min | 6.3min | 3.3 | 33 | $0.93 | $6.78 | 3.3 | 3.1 |
| default | sonnet46-200k-medium | 7 | 6.3min | 11.7min | 6.2min | 2.6 | 36 | $0.95 | $7.26 | 3.6 | 3.1 |
| powershell | haiku45-200k-na | 14 | 6.2min | 15.1min | 3.0min | 3.1 | 49 | $0.45 | $6.76 | 2.3 | 2.5 |
| powershell | opus47-1m-high | 14 | 8.6min | 15.9min | 8.3min | 0.4 | 41 | $2.35 | $34.00 | 4.2 | 4.2 |
| powershell | opus47-1m-medium | 14 | 7.9min | 22.5min | 7.5min | 0.4 | 30 | $1.40 | $20.60 | 3.9 | 3.7 |
| powershell | opus47-1m-xhigh | 14 | 10.7min | 17.3min | 9.9min | 0.4 | 47 | $3.08 | $44.61 | 4.0 | 4.1 |
| powershell | opus47-200k-medium | 14 | 5.9min | 8.5min | 5.7min | 0.3 | 30 | $1.49 | $21.18 | 3.8 | 3.5 |
| powershell | sonnet46-1m-medium | 14 | 7.5min | 12.0min | 6.9min | 1.5 | 29 | $0.99 | $15.23 | 3.5 | 3.2 |
| powershell | sonnet46-200k-medium | 14 | 6.1min | 11.7min | 3.8min | 1.0 | 27 | $0.79 | $12.26 | 3.5 | 3.3 |
| typescript-bun | haiku45-200k-na | 7 | 5.6min | 8.2min | 1.4min | 5.0 | 55 | $0.47 | $3.42 | 2.1 | 2.2 |
| typescript-bun | opus47-1m-high | 7 | 8.9min | 10.9min | 7.8min | 0.1 | 50 | $2.30 | $16.61 | 4.1 | 3.9 |
| typescript-bun | opus47-1m-medium | 7 | 7.5min | 9.0min | 7.4min | 0.4 | 32 | $1.28 | $9.00 | 3.8 | 3.5 |
| typescript-bun | opus47-1m-xhigh | 7 | 11.4min | 20.8min | 10.1min | 0.4 | 64 | $3.34 | $24.75 | 4.5 | 4.0 |
| typescript-bun | opus47-200k-medium | 7 | 5.4min | 6.9min | 5.2min | 0.4 | 31 | $1.31 | $9.47 | 3.8 | 3.4 |
| typescript-bun | sonnet46-1m-medium | 7 | 7.8min | 12.2min | 7.4min | 2.6 | 39 | $1.03 | $7.42 | 3.6 | 3.4 |
| typescript-bun | sonnet46-200k-medium | 7 | 6.9min | 11.0min | 6.6min | 2.6 | 33 | $0.87 | $6.41 | 3.2 | 2.9 |


<details>
<summary>Sorted by cost (geomean, cheapest first)</summary>

| Language | Model | Runs | Geo Duration | Max Duration | Geo Duration Net of Traps | Avg Errors | Geo Turns | Geo Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| default | haiku45-200k-na | 7 | 5.8min | 59.1min | 4.8min | 5.4 | 47 | $0.42 | $3.17 | 2.1 | 2.4 |
| powershell | haiku45-200k-na | 14 | 6.2min | 15.1min | 3.0min | 3.1 | 49 | $0.45 | $6.76 | 2.3 | 2.5 |
| typescript-bun | haiku45-200k-na | 7 | 5.6min | 8.2min | 1.4min | 5.0 | 55 | $0.47 | $3.42 | 2.1 | 2.2 |
| bash | haiku45-200k-na* | 6 | 13.4min | ≥322.8min | 8.7min | 3.0 | 56 | $0.47 | $3.63 | 2.3 | 2.5 |
| powershell | sonnet46-200k-medium | 14 | 6.1min | 11.7min | 3.8min | 1.0 | 27 | $0.79 | $12.26 | 3.5 | 3.3 |
| bash | sonnet46-200k-medium* | 6 | 6.1min | 8.6min | 5.8min | 2.3 | 34 | $0.82 | $5.01 | 3.2 | 3.2 |
| typescript-bun | sonnet46-200k-medium | 7 | 6.9min | 11.0min | 6.6min | 2.6 | 33 | $0.87 | $6.41 | 3.2 | 2.9 |
| default | sonnet46-1m-medium | 7 | 6.5min | 9.6min | 6.3min | 3.3 | 33 | $0.93 | $6.78 | 3.3 | 3.1 |
| default | sonnet46-200k-medium | 7 | 6.3min | 11.7min | 6.2min | 2.6 | 36 | $0.95 | $7.26 | 3.6 | 3.1 |
| powershell | sonnet46-1m-medium | 14 | 7.5min | 12.0min | 6.9min | 1.5 | 29 | $0.99 | $15.23 | 3.5 | 3.2 |
| default | opus47-1m-medium | 7 | 5.1min | 8.2min | 5.1min | 0.3 | 24 | $1.02 | $7.24 | 3.4 | 3.4 |
| typescript-bun | sonnet46-1m-medium | 7 | 7.8min | 12.2min | 7.4min | 2.6 | 39 | $1.03 | $7.42 | 3.6 | 3.4 |
| bash | opus47-1m-medium | 7 | 4.8min | 6.7min | 4.8min | 1.1 | 27 | $1.08 | $7.74 | 3.2 | 3.2 |
| bash | opus47-200k-medium | 7 | 4.5min | 7.5min | 4.5min | 1.1 | 26 | $1.09 | $7.66 | 3.2 | 4.2 |
| default | opus47-200k-medium | 7 | 4.6min | 6.1min | 4.6min | 0.4 | 26 | $1.13 | $8.18 | 3.8 | 3.6 |
| typescript-bun | opus47-1m-medium | 7 | 7.5min | 9.0min | 7.4min | 0.4 | 32 | $1.28 | $9.00 | 3.8 | 3.5 |
| typescript-bun | opus47-200k-medium | 7 | 5.4min | 6.9min | 5.2min | 0.4 | 31 | $1.31 | $9.47 | 3.8 | 3.4 |
| bash | sonnet46-1m-medium | 7 | 10.0min | 29.1min | 9.3min | 4.6 | 40 | $1.34 | $10.71 | 3.4 | 3.4 |
| powershell | opus47-1m-medium | 14 | 7.9min | 22.5min | 7.5min | 0.4 | 30 | $1.40 | $20.60 | 3.9 | 3.7 |
| powershell | opus47-200k-medium | 14 | 5.9min | 8.5min | 5.7min | 0.3 | 30 | $1.49 | $21.18 | 3.8 | 3.5 |
| bash | opus47-1m-high | 7 | 6.5min | 11.3min | 6.2min | 0.6 | 34 | $1.59 | $11.54 | 3.5 | 4.0 |
| default | opus47-1m-high | 7 | 7.1min | 8.5min | 7.0min | 0.3 | 34 | $1.92 | $13.67 | 4.2 | 4.2 |
| default | opus47-1m-xhigh | 7 | 7.7min | 9.2min | 7.5min | 0.6 | 42 | $2.27 | $16.00 | 4.0 | 4.2 |
| typescript-bun | opus47-1m-high | 7 | 8.9min | 10.9min | 7.8min | 0.1 | 50 | $2.30 | $16.61 | 4.1 | 3.9 |
| powershell | opus47-1m-high | 14 | 8.6min | 15.9min | 8.3min | 0.4 | 41 | $2.35 | $34.00 | 4.2 | 4.2 |
| bash | opus47-1m-xhigh | 7 | 14.1min | 39.8min | 13.9min | 1.4 | 47 | $2.73 | $20.11 | 3.7 | 3.7 |
| powershell | opus47-1m-xhigh | 14 | 10.7min | 17.3min | 9.9min | 0.4 | 47 | $3.08 | $44.61 | 4.0 | 4.1 |
| typescript-bun | opus47-1m-xhigh | 7 | 11.4min | 20.8min | 10.1min | 0.4 | 64 | $3.34 | $24.75 | 4.5 | 4.0 |

</details>

<details>
<summary>Sorted by duration (geomean, fastest first)</summary>

| Language | Model | Runs | Geo Duration | Max Duration | Geo Duration Net of Traps | Avg Errors | Geo Turns | Geo Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| bash | opus47-200k-medium | 7 | 4.5min | 7.5min | 4.5min | 1.1 | 26 | $1.09 | $7.66 | 3.2 | 4.2 |
| default | opus47-200k-medium | 7 | 4.6min | 6.1min | 4.6min | 0.4 | 26 | $1.13 | $8.18 | 3.8 | 3.6 |
| bash | opus47-1m-medium | 7 | 4.8min | 6.7min | 4.8min | 1.1 | 27 | $1.08 | $7.74 | 3.2 | 3.2 |
| default | opus47-1m-medium | 7 | 5.1min | 8.2min | 5.1min | 0.3 | 24 | $1.02 | $7.24 | 3.4 | 3.4 |
| typescript-bun | opus47-200k-medium | 7 | 5.4min | 6.9min | 5.2min | 0.4 | 31 | $1.31 | $9.47 | 3.8 | 3.4 |
| typescript-bun | haiku45-200k-na | 7 | 5.6min | 8.2min | 1.4min | 5.0 | 55 | $0.47 | $3.42 | 2.1 | 2.2 |
| default | haiku45-200k-na | 7 | 5.8min | 59.1min | 4.8min | 5.4 | 47 | $0.42 | $3.17 | 2.1 | 2.4 |
| powershell | opus47-200k-medium | 14 | 5.9min | 8.5min | 5.7min | 0.3 | 30 | $1.49 | $21.18 | 3.8 | 3.5 |
| powershell | sonnet46-200k-medium | 14 | 6.1min | 11.7min | 3.8min | 1.0 | 27 | $0.79 | $12.26 | 3.5 | 3.3 |
| bash | sonnet46-200k-medium* | 6 | 6.1min | 8.6min | 5.8min | 2.3 | 34 | $0.82 | $5.01 | 3.2 | 3.2 |
| powershell | haiku45-200k-na | 14 | 6.2min | 15.1min | 3.0min | 3.1 | 49 | $0.45 | $6.76 | 2.3 | 2.5 |
| default | sonnet46-200k-medium | 7 | 6.3min | 11.7min | 6.2min | 2.6 | 36 | $0.95 | $7.26 | 3.6 | 3.1 |
| bash | opus47-1m-high | 7 | 6.5min | 11.3min | 6.2min | 0.6 | 34 | $1.59 | $11.54 | 3.5 | 4.0 |
| default | sonnet46-1m-medium | 7 | 6.5min | 9.6min | 6.3min | 3.3 | 33 | $0.93 | $6.78 | 3.3 | 3.1 |
| typescript-bun | sonnet46-200k-medium | 7 | 6.9min | 11.0min | 6.6min | 2.6 | 33 | $0.87 | $6.41 | 3.2 | 2.9 |
| default | opus47-1m-high | 7 | 7.1min | 8.5min | 7.0min | 0.3 | 34 | $1.92 | $13.67 | 4.2 | 4.2 |
| powershell | sonnet46-1m-medium | 14 | 7.5min | 12.0min | 6.9min | 1.5 | 29 | $0.99 | $15.23 | 3.5 | 3.2 |
| typescript-bun | opus47-1m-medium | 7 | 7.5min | 9.0min | 7.4min | 0.4 | 32 | $1.28 | $9.00 | 3.8 | 3.5 |
| default | opus47-1m-xhigh | 7 | 7.7min | 9.2min | 7.5min | 0.6 | 42 | $2.27 | $16.00 | 4.0 | 4.2 |
| typescript-bun | sonnet46-1m-medium | 7 | 7.8min | 12.2min | 7.4min | 2.6 | 39 | $1.03 | $7.42 | 3.6 | 3.4 |
| powershell | opus47-1m-medium | 14 | 7.9min | 22.5min | 7.5min | 0.4 | 30 | $1.40 | $20.60 | 3.9 | 3.7 |
| powershell | opus47-1m-high | 14 | 8.6min | 15.9min | 8.3min | 0.4 | 41 | $2.35 | $34.00 | 4.2 | 4.2 |
| typescript-bun | opus47-1m-high | 7 | 8.9min | 10.9min | 7.8min | 0.1 | 50 | $2.30 | $16.61 | 4.1 | 3.9 |
| bash | sonnet46-1m-medium | 7 | 10.0min | 29.1min | 9.3min | 4.6 | 40 | $1.34 | $10.71 | 3.4 | 3.4 |
| powershell | opus47-1m-xhigh | 14 | 10.7min | 17.3min | 9.9min | 0.4 | 47 | $3.08 | $44.61 | 4.0 | 4.1 |
| typescript-bun | opus47-1m-xhigh | 7 | 11.4min | 20.8min | 10.1min | 0.4 | 64 | $3.34 | $24.75 | 4.5 | 4.0 |
| bash | haiku45-200k-na* | 6 | 13.4min | ≥322.8min | 8.7min | 3.0 | 56 | $0.47 | $3.63 | 2.3 | 2.5 |
| bash | opus47-1m-xhigh | 7 | 14.1min | 39.8min | 13.9min | 1.4 | 47 | $2.73 | $20.11 | 3.7 | 3.7 |

</details>

<details>
<summary>Sorted by duration net of traps (geomean, fastest first)</summary>

| Language | Model | Runs | Geo Duration | Max Duration | Geo Duration Net of Traps | Avg Errors | Geo Turns | Geo Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| typescript-bun | haiku45-200k-na | 7 | 5.6min | 8.2min | 1.4min | 5.0 | 55 | $0.47 | $3.42 | 2.1 | 2.2 |
| powershell | haiku45-200k-na | 14 | 6.2min | 15.1min | 3.0min | 3.1 | 49 | $0.45 | $6.76 | 2.3 | 2.5 |
| powershell | sonnet46-200k-medium | 14 | 6.1min | 11.7min | 3.8min | 1.0 | 27 | $0.79 | $12.26 | 3.5 | 3.3 |
| bash | opus47-200k-medium | 7 | 4.5min | 7.5min | 4.5min | 1.1 | 26 | $1.09 | $7.66 | 3.2 | 4.2 |
| default | opus47-200k-medium | 7 | 4.6min | 6.1min | 4.6min | 0.4 | 26 | $1.13 | $8.18 | 3.8 | 3.6 |
| bash | opus47-1m-medium | 7 | 4.8min | 6.7min | 4.8min | 1.1 | 27 | $1.08 | $7.74 | 3.2 | 3.2 |
| default | haiku45-200k-na | 7 | 5.8min | 59.1min | 4.8min | 5.4 | 47 | $0.42 | $3.17 | 2.1 | 2.4 |
| default | opus47-1m-medium | 7 | 5.1min | 8.2min | 5.1min | 0.3 | 24 | $1.02 | $7.24 | 3.4 | 3.4 |
| typescript-bun | opus47-200k-medium | 7 | 5.4min | 6.9min | 5.2min | 0.4 | 31 | $1.31 | $9.47 | 3.8 | 3.4 |
| powershell | opus47-200k-medium | 14 | 5.9min | 8.5min | 5.7min | 0.3 | 30 | $1.49 | $21.18 | 3.8 | 3.5 |
| bash | sonnet46-200k-medium* | 6 | 6.1min | 8.6min | 5.8min | 2.3 | 34 | $0.82 | $5.01 | 3.2 | 3.2 |
| bash | opus47-1m-high | 7 | 6.5min | 11.3min | 6.2min | 0.6 | 34 | $1.59 | $11.54 | 3.5 | 4.0 |
| default | sonnet46-200k-medium | 7 | 6.3min | 11.7min | 6.2min | 2.6 | 36 | $0.95 | $7.26 | 3.6 | 3.1 |
| default | sonnet46-1m-medium | 7 | 6.5min | 9.6min | 6.3min | 3.3 | 33 | $0.93 | $6.78 | 3.3 | 3.1 |
| typescript-bun | sonnet46-200k-medium | 7 | 6.9min | 11.0min | 6.6min | 2.6 | 33 | $0.87 | $6.41 | 3.2 | 2.9 |
| powershell | sonnet46-1m-medium | 14 | 7.5min | 12.0min | 6.9min | 1.5 | 29 | $0.99 | $15.23 | 3.5 | 3.2 |
| default | opus47-1m-high | 7 | 7.1min | 8.5min | 7.0min | 0.3 | 34 | $1.92 | $13.67 | 4.2 | 4.2 |
| typescript-bun | opus47-1m-medium | 7 | 7.5min | 9.0min | 7.4min | 0.4 | 32 | $1.28 | $9.00 | 3.8 | 3.5 |
| typescript-bun | sonnet46-1m-medium | 7 | 7.8min | 12.2min | 7.4min | 2.6 | 39 | $1.03 | $7.42 | 3.6 | 3.4 |
| powershell | opus47-1m-medium | 14 | 7.9min | 22.5min | 7.5min | 0.4 | 30 | $1.40 | $20.60 | 3.9 | 3.7 |
| default | opus47-1m-xhigh | 7 | 7.7min | 9.2min | 7.5min | 0.6 | 42 | $2.27 | $16.00 | 4.0 | 4.2 |
| typescript-bun | opus47-1m-high | 7 | 8.9min | 10.9min | 7.8min | 0.1 | 50 | $2.30 | $16.61 | 4.1 | 3.9 |
| powershell | opus47-1m-high | 14 | 8.6min | 15.9min | 8.3min | 0.4 | 41 | $2.35 | $34.00 | 4.2 | 4.2 |
| bash | haiku45-200k-na* | 6 | 13.4min | ≥322.8min | 8.7min | 3.0 | 56 | $0.47 | $3.63 | 2.3 | 2.5 |
| bash | sonnet46-1m-medium | 7 | 10.0min | 29.1min | 9.3min | 4.6 | 40 | $1.34 | $10.71 | 3.4 | 3.4 |
| powershell | opus47-1m-xhigh | 14 | 10.7min | 17.3min | 9.9min | 0.4 | 47 | $3.08 | $44.61 | 4.0 | 4.1 |
| typescript-bun | opus47-1m-xhigh | 7 | 11.4min | 20.8min | 10.1min | 0.4 | 64 | $3.34 | $24.75 | 4.5 | 4.0 |
| bash | opus47-1m-xhigh | 7 | 14.1min | 39.8min | 13.9min | 1.4 | 47 | $2.73 | $20.11 | 3.7 | 3.7 |

</details>

<details>
<summary>Sorted by avg errors (fewest first)</summary>

| Language | Model | Runs | Geo Duration | Max Duration | Geo Duration Net of Traps | Avg Errors | Geo Turns | Geo Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| typescript-bun | opus47-1m-high | 7 | 8.9min | 10.9min | 7.8min | 0.1 | 50 | $2.30 | $16.61 | 4.1 | 3.9 |
| default | opus47-1m-high | 7 | 7.1min | 8.5min | 7.0min | 0.3 | 34 | $1.92 | $13.67 | 4.2 | 4.2 |
| default | opus47-1m-medium | 7 | 5.1min | 8.2min | 5.1min | 0.3 | 24 | $1.02 | $7.24 | 3.4 | 3.4 |
| powershell | opus47-200k-medium | 14 | 5.9min | 8.5min | 5.7min | 0.3 | 30 | $1.49 | $21.18 | 3.8 | 3.5 |
| powershell | opus47-1m-high | 14 | 8.6min | 15.9min | 8.3min | 0.4 | 41 | $2.35 | $34.00 | 4.2 | 4.2 |
| powershell | opus47-1m-medium | 14 | 7.9min | 22.5min | 7.5min | 0.4 | 30 | $1.40 | $20.60 | 3.9 | 3.7 |
| powershell | opus47-1m-xhigh | 14 | 10.7min | 17.3min | 9.9min | 0.4 | 47 | $3.08 | $44.61 | 4.0 | 4.1 |
| default | opus47-200k-medium | 7 | 4.6min | 6.1min | 4.6min | 0.4 | 26 | $1.13 | $8.18 | 3.8 | 3.6 |
| typescript-bun | opus47-1m-medium | 7 | 7.5min | 9.0min | 7.4min | 0.4 | 32 | $1.28 | $9.00 | 3.8 | 3.5 |
| typescript-bun | opus47-1m-xhigh | 7 | 11.4min | 20.8min | 10.1min | 0.4 | 64 | $3.34 | $24.75 | 4.5 | 4.0 |
| typescript-bun | opus47-200k-medium | 7 | 5.4min | 6.9min | 5.2min | 0.4 | 31 | $1.31 | $9.47 | 3.8 | 3.4 |
| bash | opus47-1m-high | 7 | 6.5min | 11.3min | 6.2min | 0.6 | 34 | $1.59 | $11.54 | 3.5 | 4.0 |
| default | opus47-1m-xhigh | 7 | 7.7min | 9.2min | 7.5min | 0.6 | 42 | $2.27 | $16.00 | 4.0 | 4.2 |
| powershell | sonnet46-200k-medium | 14 | 6.1min | 11.7min | 3.8min | 1.0 | 27 | $0.79 | $12.26 | 3.5 | 3.3 |
| bash | opus47-1m-medium | 7 | 4.8min | 6.7min | 4.8min | 1.1 | 27 | $1.08 | $7.74 | 3.2 | 3.2 |
| bash | opus47-200k-medium | 7 | 4.5min | 7.5min | 4.5min | 1.1 | 26 | $1.09 | $7.66 | 3.2 | 4.2 |
| bash | opus47-1m-xhigh | 7 | 14.1min | 39.8min | 13.9min | 1.4 | 47 | $2.73 | $20.11 | 3.7 | 3.7 |
| powershell | sonnet46-1m-medium | 14 | 7.5min | 12.0min | 6.9min | 1.5 | 29 | $0.99 | $15.23 | 3.5 | 3.2 |
| bash | sonnet46-200k-medium* | 6 | 6.1min | 8.6min | 5.8min | 2.3 | 34 | $0.82 | $5.01 | 3.2 | 3.2 |
| default | sonnet46-200k-medium | 7 | 6.3min | 11.7min | 6.2min | 2.6 | 36 | $0.95 | $7.26 | 3.6 | 3.1 |
| typescript-bun | sonnet46-1m-medium | 7 | 7.8min | 12.2min | 7.4min | 2.6 | 39 | $1.03 | $7.42 | 3.6 | 3.4 |
| typescript-bun | sonnet46-200k-medium | 7 | 6.9min | 11.0min | 6.6min | 2.6 | 33 | $0.87 | $6.41 | 3.2 | 2.9 |
| bash | haiku45-200k-na* | 6 | 13.4min | ≥322.8min | 8.7min | 3.0 | 56 | $0.47 | $3.63 | 2.3 | 2.5 |
| powershell | haiku45-200k-na | 14 | 6.2min | 15.1min | 3.0min | 3.1 | 49 | $0.45 | $6.76 | 2.3 | 2.5 |
| default | sonnet46-1m-medium | 7 | 6.5min | 9.6min | 6.3min | 3.3 | 33 | $0.93 | $6.78 | 3.3 | 3.1 |
| bash | sonnet46-1m-medium | 7 | 10.0min | 29.1min | 9.3min | 4.6 | 40 | $1.34 | $10.71 | 3.4 | 3.4 |
| typescript-bun | haiku45-200k-na | 7 | 5.6min | 8.2min | 1.4min | 5.0 | 55 | $0.47 | $3.42 | 2.1 | 2.2 |
| default | haiku45-200k-na | 7 | 5.8min | 59.1min | 4.8min | 5.4 | 47 | $0.42 | $3.17 | 2.1 | 2.4 |

</details>

<details>
<summary>Sorted by turns (geomean, fewest first)</summary>

| Language | Model | Runs | Geo Duration | Max Duration | Geo Duration Net of Traps | Avg Errors | Geo Turns | Geo Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| default | opus47-1m-medium | 7 | 5.1min | 8.2min | 5.1min | 0.3 | 24 | $1.02 | $7.24 | 3.4 | 3.4 |
| default | opus47-200k-medium | 7 | 4.6min | 6.1min | 4.6min | 0.4 | 26 | $1.13 | $8.18 | 3.8 | 3.6 |
| bash | opus47-200k-medium | 7 | 4.5min | 7.5min | 4.5min | 1.1 | 26 | $1.09 | $7.66 | 3.2 | 4.2 |
| bash | opus47-1m-medium | 7 | 4.8min | 6.7min | 4.8min | 1.1 | 27 | $1.08 | $7.74 | 3.2 | 3.2 |
| powershell | sonnet46-200k-medium | 14 | 6.1min | 11.7min | 3.8min | 1.0 | 27 | $0.79 | $12.26 | 3.5 | 3.3 |
| powershell | sonnet46-1m-medium | 14 | 7.5min | 12.0min | 6.9min | 1.5 | 29 | $0.99 | $15.23 | 3.5 | 3.2 |
| powershell | opus47-200k-medium | 14 | 5.9min | 8.5min | 5.7min | 0.3 | 30 | $1.49 | $21.18 | 3.8 | 3.5 |
| powershell | opus47-1m-medium | 14 | 7.9min | 22.5min | 7.5min | 0.4 | 30 | $1.40 | $20.60 | 3.9 | 3.7 |
| typescript-bun | opus47-200k-medium | 7 | 5.4min | 6.9min | 5.2min | 0.4 | 31 | $1.31 | $9.47 | 3.8 | 3.4 |
| typescript-bun | opus47-1m-medium | 7 | 7.5min | 9.0min | 7.4min | 0.4 | 32 | $1.28 | $9.00 | 3.8 | 3.5 |
| default | sonnet46-1m-medium | 7 | 6.5min | 9.6min | 6.3min | 3.3 | 33 | $0.93 | $6.78 | 3.3 | 3.1 |
| typescript-bun | sonnet46-200k-medium | 7 | 6.9min | 11.0min | 6.6min | 2.6 | 33 | $0.87 | $6.41 | 3.2 | 2.9 |
| default | opus47-1m-high | 7 | 7.1min | 8.5min | 7.0min | 0.3 | 34 | $1.92 | $13.67 | 4.2 | 4.2 |
| bash | sonnet46-200k-medium* | 6 | 6.1min | 8.6min | 5.8min | 2.3 | 34 | $0.82 | $5.01 | 3.2 | 3.2 |
| bash | opus47-1m-high | 7 | 6.5min | 11.3min | 6.2min | 0.6 | 34 | $1.59 | $11.54 | 3.5 | 4.0 |
| default | sonnet46-200k-medium | 7 | 6.3min | 11.7min | 6.2min | 2.6 | 36 | $0.95 | $7.26 | 3.6 | 3.1 |
| typescript-bun | sonnet46-1m-medium | 7 | 7.8min | 12.2min | 7.4min | 2.6 | 39 | $1.03 | $7.42 | 3.6 | 3.4 |
| bash | sonnet46-1m-medium | 7 | 10.0min | 29.1min | 9.3min | 4.6 | 40 | $1.34 | $10.71 | 3.4 | 3.4 |
| powershell | opus47-1m-high | 14 | 8.6min | 15.9min | 8.3min | 0.4 | 41 | $2.35 | $34.00 | 4.2 | 4.2 |
| default | opus47-1m-xhigh | 7 | 7.7min | 9.2min | 7.5min | 0.6 | 42 | $2.27 | $16.00 | 4.0 | 4.2 |
| default | haiku45-200k-na | 7 | 5.8min | 59.1min | 4.8min | 5.4 | 47 | $0.42 | $3.17 | 2.1 | 2.4 |
| powershell | opus47-1m-xhigh | 14 | 10.7min | 17.3min | 9.9min | 0.4 | 47 | $3.08 | $44.61 | 4.0 | 4.1 |
| bash | opus47-1m-xhigh | 7 | 14.1min | 39.8min | 13.9min | 1.4 | 47 | $2.73 | $20.11 | 3.7 | 3.7 |
| powershell | haiku45-200k-na | 14 | 6.2min | 15.1min | 3.0min | 3.1 | 49 | $0.45 | $6.76 | 2.3 | 2.5 |
| typescript-bun | opus47-1m-high | 7 | 8.9min | 10.9min | 7.8min | 0.1 | 50 | $2.30 | $16.61 | 4.1 | 3.9 |
| typescript-bun | haiku45-200k-na | 7 | 5.6min | 8.2min | 1.4min | 5.0 | 55 | $0.47 | $3.42 | 2.1 | 2.2 |
| bash | haiku45-200k-na* | 6 | 13.4min | ≥322.8min | 8.7min | 3.0 | 56 | $0.47 | $3.63 | 2.3 | 2.5 |
| typescript-bun | opus47-1m-xhigh | 7 | 11.4min | 20.8min | 10.1min | 0.4 | 64 | $3.34 | $24.75 | 4.5 | 4.0 |

</details>

<details>
<summary>Sorted by LLM-as-judge score (best first)</summary>

| Language | Model | Runs | Geo Duration | Max Duration | Geo Duration Net of Traps | Avg Errors | Geo Turns | Geo Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| typescript-bun | opus47-1m-xhigh | 7 | 11.4min | 20.8min | 10.1min | 0.4 | 64 | $3.34 | $24.75 | 4.5 | 4.0 |
| powershell | opus47-1m-high | 14 | 8.6min | 15.9min | 8.3min | 0.4 | 41 | $2.35 | $34.00 | 4.2 | 4.2 |
| default | opus47-1m-high | 7 | 7.1min | 8.5min | 7.0min | 0.3 | 34 | $1.92 | $13.67 | 4.2 | 4.2 |
| typescript-bun | opus47-1m-high | 7 | 8.9min | 10.9min | 7.8min | 0.1 | 50 | $2.30 | $16.61 | 4.1 | 3.9 |
| powershell | opus47-1m-xhigh | 14 | 10.7min | 17.3min | 9.9min | 0.4 | 47 | $3.08 | $44.61 | 4.0 | 4.1 |
| default | opus47-1m-xhigh | 7 | 7.7min | 9.2min | 7.5min | 0.6 | 42 | $2.27 | $16.00 | 4.0 | 4.2 |
| powershell | opus47-1m-medium | 14 | 7.9min | 22.5min | 7.5min | 0.4 | 30 | $1.40 | $20.60 | 3.9 | 3.7 |
| default | opus47-200k-medium | 7 | 4.6min | 6.1min | 4.6min | 0.4 | 26 | $1.13 | $8.18 | 3.8 | 3.6 |
| powershell | opus47-200k-medium | 14 | 5.9min | 8.5min | 5.7min | 0.3 | 30 | $1.49 | $21.18 | 3.8 | 3.5 |
| typescript-bun | opus47-1m-medium | 7 | 7.5min | 9.0min | 7.4min | 0.4 | 32 | $1.28 | $9.00 | 3.8 | 3.5 |
| typescript-bun | opus47-200k-medium | 7 | 5.4min | 6.9min | 5.2min | 0.4 | 31 | $1.31 | $9.47 | 3.8 | 3.4 |
| bash | opus47-1m-xhigh | 7 | 14.1min | 39.8min | 13.9min | 1.4 | 47 | $2.73 | $20.11 | 3.7 | 3.7 |
| default | sonnet46-200k-medium | 7 | 6.3min | 11.7min | 6.2min | 2.6 | 36 | $0.95 | $7.26 | 3.6 | 3.1 |
| typescript-bun | sonnet46-1m-medium | 7 | 7.8min | 12.2min | 7.4min | 2.6 | 39 | $1.03 | $7.42 | 3.6 | 3.4 |
| bash | opus47-1m-high | 7 | 6.5min | 11.3min | 6.2min | 0.6 | 34 | $1.59 | $11.54 | 3.5 | 4.0 |
| powershell | sonnet46-1m-medium | 14 | 7.5min | 12.0min | 6.9min | 1.5 | 29 | $0.99 | $15.23 | 3.5 | 3.2 |
| powershell | sonnet46-200k-medium | 14 | 6.1min | 11.7min | 3.8min | 1.0 | 27 | $0.79 | $12.26 | 3.5 | 3.3 |
| bash | sonnet46-1m-medium | 7 | 10.0min | 29.1min | 9.3min | 4.6 | 40 | $1.34 | $10.71 | 3.4 | 3.4 |
| default | opus47-1m-medium | 7 | 5.1min | 8.2min | 5.1min | 0.3 | 24 | $1.02 | $7.24 | 3.4 | 3.4 |
| default | sonnet46-1m-medium | 7 | 6.5min | 9.6min | 6.3min | 3.3 | 33 | $0.93 | $6.78 | 3.3 | 3.1 |
| bash | sonnet46-200k-medium* | 6 | 6.1min | 8.6min | 5.8min | 2.3 | 34 | $0.82 | $5.01 | 3.2 | 3.2 |
| bash | opus47-1m-medium | 7 | 4.8min | 6.7min | 4.8min | 1.1 | 27 | $1.08 | $7.74 | 3.2 | 3.2 |
| bash | opus47-200k-medium | 7 | 4.5min | 7.5min | 4.5min | 1.1 | 26 | $1.09 | $7.66 | 3.2 | 4.2 |
| typescript-bun | sonnet46-200k-medium | 7 | 6.9min | 11.0min | 6.6min | 2.6 | 33 | $0.87 | $6.41 | 3.2 | 2.9 |
| bash | haiku45-200k-na* | 6 | 13.4min | ≥322.8min | 8.7min | 3.0 | 56 | $0.47 | $3.63 | 2.3 | 2.5 |
| powershell | haiku45-200k-na | 14 | 6.2min | 15.1min | 3.0min | 3.1 | 49 | $0.45 | $6.76 | 2.3 | 2.5 |
| typescript-bun | haiku45-200k-na | 7 | 5.6min | 8.2min | 1.4min | 5.0 | 55 | $0.47 | $3.42 | 2.1 | 2.2 |
| default | haiku45-200k-na | 7 | 5.8min | 59.1min | 4.8min | 5.4 | 47 | $0.42 | $3.17 | 2.1 | 2.4 |

</details>

<details>
<summary>Sorted by deliverable-quality score (best first)</summary>

| Language | Model | Runs | Geo Duration | Max Duration | Geo Duration Net of Traps | Avg Errors | Geo Turns | Geo Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| bash | opus47-200k-medium | 7 | 4.5min | 7.5min | 4.5min | 1.1 | 26 | $1.09 | $7.66 | 3.2 | 4.2 |
| default | opus47-1m-high | 7 | 7.1min | 8.5min | 7.0min | 0.3 | 34 | $1.92 | $13.67 | 4.2 | 4.2 |
| default | opus47-1m-xhigh | 7 | 7.7min | 9.2min | 7.5min | 0.6 | 42 | $2.27 | $16.00 | 4.0 | 4.2 |
| powershell | opus47-1m-high | 14 | 8.6min | 15.9min | 8.3min | 0.4 | 41 | $2.35 | $34.00 | 4.2 | 4.2 |
| powershell | opus47-1m-xhigh | 14 | 10.7min | 17.3min | 9.9min | 0.4 | 47 | $3.08 | $44.61 | 4.0 | 4.1 |
| bash | opus47-1m-high | 7 | 6.5min | 11.3min | 6.2min | 0.6 | 34 | $1.59 | $11.54 | 3.5 | 4.0 |
| typescript-bun | opus47-1m-xhigh | 7 | 11.4min | 20.8min | 10.1min | 0.4 | 64 | $3.34 | $24.75 | 4.5 | 4.0 |
| typescript-bun | opus47-1m-high | 7 | 8.9min | 10.9min | 7.8min | 0.1 | 50 | $2.30 | $16.61 | 4.1 | 3.9 |
| bash | opus47-1m-xhigh | 7 | 14.1min | 39.8min | 13.9min | 1.4 | 47 | $2.73 | $20.11 | 3.7 | 3.7 |
| powershell | opus47-1m-medium | 14 | 7.9min | 22.5min | 7.5min | 0.4 | 30 | $1.40 | $20.60 | 3.9 | 3.7 |
| default | opus47-200k-medium | 7 | 4.6min | 6.1min | 4.6min | 0.4 | 26 | $1.13 | $8.18 | 3.8 | 3.6 |
| powershell | opus47-200k-medium | 14 | 5.9min | 8.5min | 5.7min | 0.3 | 30 | $1.49 | $21.18 | 3.8 | 3.5 |
| typescript-bun | opus47-1m-medium | 7 | 7.5min | 9.0min | 7.4min | 0.4 | 32 | $1.28 | $9.00 | 3.8 | 3.5 |
| bash | sonnet46-1m-medium | 7 | 10.0min | 29.1min | 9.3min | 4.6 | 40 | $1.34 | $10.71 | 3.4 | 3.4 |
| default | opus47-1m-medium | 7 | 5.1min | 8.2min | 5.1min | 0.3 | 24 | $1.02 | $7.24 | 3.4 | 3.4 |
| typescript-bun | opus47-200k-medium | 7 | 5.4min | 6.9min | 5.2min | 0.4 | 31 | $1.31 | $9.47 | 3.8 | 3.4 |
| typescript-bun | sonnet46-1m-medium | 7 | 7.8min | 12.2min | 7.4min | 2.6 | 39 | $1.03 | $7.42 | 3.6 | 3.4 |
| powershell | sonnet46-200k-medium | 14 | 6.1min | 11.7min | 3.8min | 1.0 | 27 | $0.79 | $12.26 | 3.5 | 3.3 |
| bash | sonnet46-200k-medium* | 6 | 6.1min | 8.6min | 5.8min | 2.3 | 34 | $0.82 | $5.01 | 3.2 | 3.2 |
| powershell | sonnet46-1m-medium | 14 | 7.5min | 12.0min | 6.9min | 1.5 | 29 | $0.99 | $15.23 | 3.5 | 3.2 |
| bash | opus47-1m-medium | 7 | 4.8min | 6.7min | 4.8min | 1.1 | 27 | $1.08 | $7.74 | 3.2 | 3.2 |
| default | sonnet46-1m-medium | 7 | 6.5min | 9.6min | 6.3min | 3.3 | 33 | $0.93 | $6.78 | 3.3 | 3.1 |
| default | sonnet46-200k-medium | 7 | 6.3min | 11.7min | 6.2min | 2.6 | 36 | $0.95 | $7.26 | 3.6 | 3.1 |
| typescript-bun | sonnet46-200k-medium | 7 | 6.9min | 11.0min | 6.6min | 2.6 | 33 | $0.87 | $6.41 | 3.2 | 2.9 |
| bash | haiku45-200k-na* | 6 | 13.4min | ≥322.8min | 8.7min | 3.0 | 56 | $0.47 | $3.63 | 2.3 | 2.5 |
| powershell | haiku45-200k-na | 14 | 6.2min | 15.1min | 3.0min | 3.1 | 49 | $0.45 | $6.76 | 2.3 | 2.5 |
| default | haiku45-200k-na | 7 | 5.8min | 59.1min | 4.8min | 5.4 | 47 | $0.42 | $3.17 | 2.1 | 2.4 |
| typescript-bun | haiku45-200k-na | 7 | 5.6min | 8.2min | 1.4min | 5.0 | 55 | $0.47 | $3.42 | 2.1 | 2.2 |

</details>

## Savings Analysis

### Trap Analysis by Language/Model/Effort/Category

| Trap | Language | Model | Fell In | Time Lost | % of Time | $ Lost | % of $ |
|------|------|-------|---------|-----------|-----------|--------|--------|
| repeated-test-reruns | bash | haiku45-200k-na-cli2.1.114 | 5 | 6.7min | 0.3% | $0.38 | 0.11% |
| repeated-test-reruns | bash | opus47-1m-xhigh-cli2.1.112 | 1 | 1.7min | 0.1% | $0.52 | 0.14% |
| repeated-test-reruns | bash | sonnet46-1m-medium-cli2.1.114 | 2 | 1.3min | 0.1% | $0.16 | 0.04% |
| repeated-test-reruns | bash | sonnet46-200k-medium-cli2.1.114 | 1 | 0.7min | 0.0% | $0.09 | 0.02% |
| repeated-test-reruns | default | haiku45-200k-na-cli2.1.114 | 3 | 2.0min | 0.1% | $0.18 | 0.05% |
| repeated-test-reruns | default | opus47-1m-xhigh-cli2.1.112 | 1 | 0.7min | 0.0% | $0.18 | 0.05% |
| repeated-test-reruns | powershell | haiku45-200k-na-cli2.1.114 | 13 | 19.0min | 0.8% | $1.58 | 0.44% |
| repeated-test-reruns | powershell | opus47-1m-high-cli2.1.114 | 3 | 3.0min | 0.1% | $0.76 | 0.21% |
| repeated-test-reruns | powershell | opus47-1m-medium-cli2.1.112 | 3 | 3.7min | 0.2% | $0.75 | 0.21% |
| repeated-test-reruns | powershell | opus47-1m-xhigh-cli2.1.112 | 6 | 5.0min | 0.2% | $1.53 | 0.42% |
| repeated-test-reruns | powershell | opus47-200k-medium-cli2.1.114 | 4 | 3.0min | 0.1% | $0.72 | 0.20% |
| repeated-test-reruns | powershell | sonnet46-1m-medium-cli2.1.114 | 2 | 2.7min | 0.1% | $0.39 | 0.11% |
| repeated-test-reruns | powershell | sonnet46-200k-medium-cli2.1.114 | 1 | 1.0min | 0.0% | $0.13 | 0.04% |
| repeated-test-reruns | typescript-bun | haiku45-200k-na-cli2.1.114 | 6 | 8.7min | 0.4% | $0.81 | 0.22% |
| repeated-test-reruns | typescript-bun | opus47-1m-high-cli2.1.114 | 5 | 7.7min | 0.3% | $2.00 | 0.55% |
| repeated-test-reruns | typescript-bun | opus47-1m-medium-cli2.1.112 | 1 | 0.7min | 0.0% | $0.16 | 0.04% |
| repeated-test-reruns | typescript-bun | opus47-1m-xhigh-cli2.1.112 | 5 | 7.7min | 0.3% | $2.28 | 0.63% |
| repeated-test-reruns | typescript-bun | opus47-200k-medium-cli2.1.114 | 1 | 0.7min | 0.0% | $0.19 | 0.05% |
| repeated-test-reruns | typescript-bun | sonnet46-1m-medium-cli2.1.114 | 3 | 2.7min | 0.1% | $0.38 | 0.11% |
| repeated-test-reruns | typescript-bun | sonnet46-200k-medium-cli2.1.114 | 3 | 2.0min | 0.1% | $0.27 | 0.07% |
| act-push-debug-loops | bash | haiku45-200k-na-cli2.1.114 | 4 | 13.8min | 0.6% | $0.32 | 0.09% |
| act-push-debug-loops | bash | sonnet46-200k-medium-cli2.1.114 | 3 | 1.8min | 0.1% | $0.23 | 0.06% |
| act-push-debug-loops | default | haiku45-200k-na-cli2.1.114 | 4 | 3.0min | 0.1% | $0.12 | 0.03% |
| act-push-debug-loops | default | sonnet46-1m-medium-cli2.1.114 | 1 | 0.3min | 0.0% | $0.05 | 0.01% |
| act-push-debug-loops | default | sonnet46-200k-medium-cli2.1.114 | 1 | 0.3min | 0.0% | $0.04 | 0.01% |
| act-push-debug-loops | powershell | haiku45-200k-na-cli2.1.114 | 9 | 12.4min | 0.5% | $0.80 | 0.22% |
| act-push-debug-loops | powershell | sonnet46-1m-medium-cli2.1.114 | 4 | 2.9min | 0.1% | $0.37 | 0.10% |
| act-push-debug-loops | powershell | sonnet46-200k-medium-cli2.1.114 | 3 | 2.3min | 0.1% | $0.29 | 0.08% |
| act-push-debug-loops | typescript-bun | haiku45-200k-na-cli2.1.114 | 4 | 4.0min | 0.2% | $0.32 | 0.09% |
| act-push-debug-loops | typescript-bun | opus47-1m-xhigh-cli2.1.112 | 1 | 0.8min | 0.0% | $0.24 | 0.07% |
| fixture-rework | bash | haiku45-200k-na-cli2.1.114 | 1 | 0.7min | 0.0% | $0.06 | 0.02% |
| fixture-rework | bash | opus47-1m-high-cli2.1.114 | 2 | 1.7min | 0.1% | $0.39 | 0.11% |
| fixture-rework | bash | sonnet46-1m-medium-cli2.1.114 | 1 | 9.3min | 0.4% | $1.04 | 0.29% |
| fixture-rework | default | haiku45-200k-na-cli2.1.114 | 1 | 6.3min | 0.3% | $0.09 | 0.03% |
| fixture-rework | default | opus47-1m-high-cli2.1.114 | 1 | 0.7min | 0.0% | $0.18 | 0.05% |
| fixture-rework | default | opus47-1m-xhigh-cli2.1.112 | 1 | 0.7min | 0.0% | $0.18 | 0.05% |
| fixture-rework | default | sonnet46-1m-medium-cli2.1.114 | 1 | 1.3min | 0.1% | $0.14 | 0.04% |
| fixture-rework | powershell | haiku45-200k-na-cli2.1.114 | 1 | 1.3min | 0.1% | $0.12 | 0.03% |
| fixture-rework | powershell | opus47-1m-high-cli2.1.114 | 1 | 0.7min | 0.0% | $0.19 | 0.05% |
| fixture-rework | powershell | opus47-1m-medium-cli2.1.112 | 1 | 1.0min | 0.0% | $0.22 | 0.06% |
| fixture-rework | powershell | opus47-1m-xhigh-cli2.1.112 | 1 | 1.3min | 0.1% | $0.48 | 0.13% |
| fixture-rework | powershell | sonnet46-1m-medium-cli2.1.114 | 1 | 1.0min | 0.0% | $0.14 | 0.04% |
| fixture-rework | powershell | sonnet46-200k-medium-cli2.1.114 | 1 | 6.7min | 0.3% | $0.84 | 0.23% |
| fixture-rework | typescript-bun | haiku45-200k-na-cli2.1.114 | 2 | 6.3min | 0.3% | $0.54 | 0.15% |
| fixture-rework | typescript-bun | opus47-200k-medium-cli2.1.114 | 1 | 1.0min | 0.0% | $0.22 | 0.06% |
| actionlint-fix-cycles | bash | haiku45-200k-na-cli2.1.114 | 1 | 1.3min | 0.1% | $0.09 | 0.02% |
| actionlint-fix-cycles | default | haiku45-200k-na-cli2.1.114 | 3 | 3.7min | 0.2% | $0.16 | 0.04% |
| actionlint-fix-cycles | powershell | haiku45-200k-na-cli2.1.114 | 3 | 3.0min | 0.1% | $0.24 | 0.07% |
| actionlint-fix-cycles | typescript-bun | haiku45-200k-na-cli2.1.114 | 1 | 0.7min | 0.0% | $0.04 | 0.01% |
| mid-run-module-restructure | powershell | opus47-1m-medium-cli2.1.112 | 1 | 2.0min | 0.1% | $0.44 | 0.12% |
| mid-run-module-restructure | powershell | opus47-1m-xhigh-cli2.1.112 | 2 | 4.0min | 0.2% | $1.06 | 0.29% |
| pwsh-runtime-install-overhead | powershell | haiku45-200k-na-cli2.1.114 | 5 | 3.9min | 0.2% | $0.22 | 0.06% |
| pwsh-runtime-install-overhead | powershell | sonnet46-200k-medium-cli2.1.114 | 2 | 0.9min | 0.0% | $0.12 | 0.03% |
| docker-pwsh-install | powershell | opus47-1m-xhigh-cli2.1.112 | 1 | 1.5min | 0.1% | $0.42 | 0.12% |
| docker-pwsh-install | powershell | sonnet46-1m-medium-cli2.1.114 | 1 | 3.0min | 0.1% | $0.41 | 0.11% |
| act-permission-path-errors | default | sonnet46-200k-medium-cli2.1.114 | 1 | 0.5min | 0.0% | $0.07 | 0.02% |
| act-permission-path-errors | powershell | sonnet46-200k-medium-cli2.1.114 | 1 | 0.5min | 0.0% | $0.06 | 0.02% |
| act-permission-path-errors | typescript-bun | haiku45-200k-na-cli2.1.114 | 1 | 1.5min | 0.1% | $0.12 | 0.03% |
| bats-setup-issues | bash | haiku45-200k-na-cli2.1.114 | 2 | 1.5min | 0.1% | $0.05 | 0.01% |
| bats-setup-issues | bash | sonnet46-1m-medium-cli2.1.114 | 1 | 0.8min | 0.0% | $0.08 | 0.02% |


<details>
<summary>Sorted by time lost (least first)</summary>

| Trap | Language | Model | Fell In | Time Lost | % of Time | $ Lost | % of $ |
|------|------|-------|---------|-----------|-----------|--------|--------|
| act-push-debug-loops | default | sonnet46-200k-medium-cli2.1.114 | 1 | 0.3min | 0.0% | $0.04 | 0.01% |
| act-push-debug-loops | default | sonnet46-1m-medium-cli2.1.114 | 1 | 0.3min | 0.0% | $0.05 | 0.01% |
| act-permission-path-errors | default | sonnet46-200k-medium-cli2.1.114 | 1 | 0.5min | 0.0% | $0.07 | 0.02% |
| act-permission-path-errors | powershell | sonnet46-200k-medium-cli2.1.114 | 1 | 0.5min | 0.0% | $0.06 | 0.02% |
| repeated-test-reruns | bash | sonnet46-200k-medium-cli2.1.114 | 1 | 0.7min | 0.0% | $0.09 | 0.02% |
| repeated-test-reruns | default | opus47-1m-xhigh-cli2.1.112 | 1 | 0.7min | 0.0% | $0.18 | 0.05% |
| repeated-test-reruns | typescript-bun | opus47-1m-medium-cli2.1.112 | 1 | 0.7min | 0.0% | $0.16 | 0.04% |
| repeated-test-reruns | typescript-bun | opus47-200k-medium-cli2.1.114 | 1 | 0.7min | 0.0% | $0.19 | 0.05% |
| fixture-rework | bash | haiku45-200k-na-cli2.1.114 | 1 | 0.7min | 0.0% | $0.06 | 0.02% |
| fixture-rework | default | opus47-1m-high-cli2.1.114 | 1 | 0.7min | 0.0% | $0.18 | 0.05% |
| fixture-rework | default | opus47-1m-xhigh-cli2.1.112 | 1 | 0.7min | 0.0% | $0.18 | 0.05% |
| fixture-rework | powershell | opus47-1m-high-cli2.1.114 | 1 | 0.7min | 0.0% | $0.19 | 0.05% |
| actionlint-fix-cycles | typescript-bun | haiku45-200k-na-cli2.1.114 | 1 | 0.7min | 0.0% | $0.04 | 0.01% |
| bats-setup-issues | bash | sonnet46-1m-medium-cli2.1.114 | 1 | 0.8min | 0.0% | $0.08 | 0.02% |
| act-push-debug-loops | typescript-bun | opus47-1m-xhigh-cli2.1.112 | 1 | 0.8min | 0.0% | $0.24 | 0.07% |
| pwsh-runtime-install-overhead | powershell | sonnet46-200k-medium-cli2.1.114 | 2 | 0.9min | 0.0% | $0.12 | 0.03% |
| repeated-test-reruns | powershell | sonnet46-200k-medium-cli2.1.114 | 1 | 1.0min | 0.0% | $0.13 | 0.04% |
| fixture-rework | powershell | opus47-1m-medium-cli2.1.112 | 1 | 1.0min | 0.0% | $0.22 | 0.06% |
| fixture-rework | powershell | sonnet46-1m-medium-cli2.1.114 | 1 | 1.0min | 0.0% | $0.14 | 0.04% |
| fixture-rework | typescript-bun | opus47-200k-medium-cli2.1.114 | 1 | 1.0min | 0.0% | $0.22 | 0.06% |
| repeated-test-reruns | bash | sonnet46-1m-medium-cli2.1.114 | 2 | 1.3min | 0.1% | $0.16 | 0.04% |
| fixture-rework | default | sonnet46-1m-medium-cli2.1.114 | 1 | 1.3min | 0.1% | $0.14 | 0.04% |
| fixture-rework | powershell | haiku45-200k-na-cli2.1.114 | 1 | 1.3min | 0.1% | $0.12 | 0.03% |
| fixture-rework | powershell | opus47-1m-xhigh-cli2.1.112 | 1 | 1.3min | 0.1% | $0.48 | 0.13% |
| actionlint-fix-cycles | bash | haiku45-200k-na-cli2.1.114 | 1 | 1.3min | 0.1% | $0.09 | 0.02% |
| docker-pwsh-install | powershell | opus47-1m-xhigh-cli2.1.112 | 1 | 1.5min | 0.1% | $0.42 | 0.12% |
| act-permission-path-errors | typescript-bun | haiku45-200k-na-cli2.1.114 | 1 | 1.5min | 0.1% | $0.12 | 0.03% |
| bats-setup-issues | bash | haiku45-200k-na-cli2.1.114 | 2 | 1.5min | 0.1% | $0.05 | 0.01% |
| repeated-test-reruns | bash | opus47-1m-xhigh-cli2.1.112 | 1 | 1.7min | 0.1% | $0.52 | 0.14% |
| fixture-rework | bash | opus47-1m-high-cli2.1.114 | 2 | 1.7min | 0.1% | $0.39 | 0.11% |
| act-push-debug-loops | bash | sonnet46-200k-medium-cli2.1.114 | 3 | 1.8min | 0.1% | $0.23 | 0.06% |
| repeated-test-reruns | default | haiku45-200k-na-cli2.1.114 | 3 | 2.0min | 0.1% | $0.18 | 0.05% |
| repeated-test-reruns | typescript-bun | sonnet46-200k-medium-cli2.1.114 | 3 | 2.0min | 0.1% | $0.27 | 0.07% |
| mid-run-module-restructure | powershell | opus47-1m-medium-cli2.1.112 | 1 | 2.0min | 0.1% | $0.44 | 0.12% |
| act-push-debug-loops | powershell | sonnet46-200k-medium-cli2.1.114 | 3 | 2.3min | 0.1% | $0.29 | 0.08% |
| repeated-test-reruns | powershell | sonnet46-1m-medium-cli2.1.114 | 2 | 2.7min | 0.1% | $0.39 | 0.11% |
| repeated-test-reruns | typescript-bun | sonnet46-1m-medium-cli2.1.114 | 3 | 2.7min | 0.1% | $0.38 | 0.11% |
| act-push-debug-loops | powershell | sonnet46-1m-medium-cli2.1.114 | 4 | 2.9min | 0.1% | $0.37 | 0.10% |
| repeated-test-reruns | powershell | opus47-1m-high-cli2.1.114 | 3 | 3.0min | 0.1% | $0.76 | 0.21% |
| repeated-test-reruns | powershell | opus47-200k-medium-cli2.1.114 | 4 | 3.0min | 0.1% | $0.72 | 0.20% |
| actionlint-fix-cycles | powershell | haiku45-200k-na-cli2.1.114 | 3 | 3.0min | 0.1% | $0.24 | 0.07% |
| docker-pwsh-install | powershell | sonnet46-1m-medium-cli2.1.114 | 1 | 3.0min | 0.1% | $0.41 | 0.11% |
| act-push-debug-loops | default | haiku45-200k-na-cli2.1.114 | 4 | 3.0min | 0.1% | $0.12 | 0.03% |
| repeated-test-reruns | powershell | opus47-1m-medium-cli2.1.112 | 3 | 3.7min | 0.2% | $0.75 | 0.21% |
| actionlint-fix-cycles | default | haiku45-200k-na-cli2.1.114 | 3 | 3.7min | 0.2% | $0.16 | 0.04% |
| pwsh-runtime-install-overhead | powershell | haiku45-200k-na-cli2.1.114 | 5 | 3.9min | 0.2% | $0.22 | 0.06% |
| mid-run-module-restructure | powershell | opus47-1m-xhigh-cli2.1.112 | 2 | 4.0min | 0.2% | $1.06 | 0.29% |
| act-push-debug-loops | typescript-bun | haiku45-200k-na-cli2.1.114 | 4 | 4.0min | 0.2% | $0.32 | 0.09% |
| repeated-test-reruns | powershell | opus47-1m-xhigh-cli2.1.112 | 6 | 5.0min | 0.2% | $1.53 | 0.42% |
| fixture-rework | default | haiku45-200k-na-cli2.1.114 | 1 | 6.3min | 0.3% | $0.09 | 0.03% |
| fixture-rework | typescript-bun | haiku45-200k-na-cli2.1.114 | 2 | 6.3min | 0.3% | $0.54 | 0.15% |
| repeated-test-reruns | bash | haiku45-200k-na-cli2.1.114 | 5 | 6.7min | 0.3% | $0.38 | 0.11% |
| fixture-rework | powershell | sonnet46-200k-medium-cli2.1.114 | 1 | 6.7min | 0.3% | $0.84 | 0.23% |
| repeated-test-reruns | typescript-bun | opus47-1m-high-cli2.1.114 | 5 | 7.7min | 0.3% | $2.00 | 0.55% |
| repeated-test-reruns | typescript-bun | opus47-1m-xhigh-cli2.1.112 | 5 | 7.7min | 0.3% | $2.28 | 0.63% |
| repeated-test-reruns | typescript-bun | haiku45-200k-na-cli2.1.114 | 6 | 8.7min | 0.4% | $0.81 | 0.22% |
| fixture-rework | bash | sonnet46-1m-medium-cli2.1.114 | 1 | 9.3min | 0.4% | $1.04 | 0.29% |
| act-push-debug-loops | powershell | haiku45-200k-na-cli2.1.114 | 9 | 12.4min | 0.5% | $0.80 | 0.22% |
| act-push-debug-loops | bash | haiku45-200k-na-cli2.1.114 | 4 | 13.8min | 0.6% | $0.32 | 0.09% |
| repeated-test-reruns | powershell | haiku45-200k-na-cli2.1.114 | 13 | 19.0min | 0.8% | $1.58 | 0.44% |

</details>

<details>
<summary>Sorted by $ lost (least first)</summary>

| Trap | Language | Model | Fell In | Time Lost | % of Time | $ Lost | % of $ |
|------|------|-------|---------|-----------|-----------|--------|--------|
| actionlint-fix-cycles | typescript-bun | haiku45-200k-na-cli2.1.114 | 1 | 0.7min | 0.0% | $0.04 | 0.01% |
| act-push-debug-loops | default | sonnet46-200k-medium-cli2.1.114 | 1 | 0.3min | 0.0% | $0.04 | 0.01% |
| act-push-debug-loops | default | sonnet46-1m-medium-cli2.1.114 | 1 | 0.3min | 0.0% | $0.05 | 0.01% |
| bats-setup-issues | bash | haiku45-200k-na-cli2.1.114 | 2 | 1.5min | 0.1% | $0.05 | 0.01% |
| fixture-rework | bash | haiku45-200k-na-cli2.1.114 | 1 | 0.7min | 0.0% | $0.06 | 0.02% |
| act-permission-path-errors | powershell | sonnet46-200k-medium-cli2.1.114 | 1 | 0.5min | 0.0% | $0.06 | 0.02% |
| act-permission-path-errors | default | sonnet46-200k-medium-cli2.1.114 | 1 | 0.5min | 0.0% | $0.07 | 0.02% |
| bats-setup-issues | bash | sonnet46-1m-medium-cli2.1.114 | 1 | 0.8min | 0.0% | $0.08 | 0.02% |
| repeated-test-reruns | bash | sonnet46-200k-medium-cli2.1.114 | 1 | 0.7min | 0.0% | $0.09 | 0.02% |
| actionlint-fix-cycles | bash | haiku45-200k-na-cli2.1.114 | 1 | 1.3min | 0.1% | $0.09 | 0.02% |
| fixture-rework | default | haiku45-200k-na-cli2.1.114 | 1 | 6.3min | 0.3% | $0.09 | 0.03% |
| pwsh-runtime-install-overhead | powershell | sonnet46-200k-medium-cli2.1.114 | 2 | 0.9min | 0.0% | $0.12 | 0.03% |
| fixture-rework | powershell | haiku45-200k-na-cli2.1.114 | 1 | 1.3min | 0.1% | $0.12 | 0.03% |
| act-push-debug-loops | default | haiku45-200k-na-cli2.1.114 | 4 | 3.0min | 0.1% | $0.12 | 0.03% |
| act-permission-path-errors | typescript-bun | haiku45-200k-na-cli2.1.114 | 1 | 1.5min | 0.1% | $0.12 | 0.03% |
| repeated-test-reruns | powershell | sonnet46-200k-medium-cli2.1.114 | 1 | 1.0min | 0.0% | $0.13 | 0.04% |
| fixture-rework | powershell | sonnet46-1m-medium-cli2.1.114 | 1 | 1.0min | 0.0% | $0.14 | 0.04% |
| fixture-rework | default | sonnet46-1m-medium-cli2.1.114 | 1 | 1.3min | 0.1% | $0.14 | 0.04% |
| repeated-test-reruns | typescript-bun | opus47-1m-medium-cli2.1.112 | 1 | 0.7min | 0.0% | $0.16 | 0.04% |
| actionlint-fix-cycles | default | haiku45-200k-na-cli2.1.114 | 3 | 3.7min | 0.2% | $0.16 | 0.04% |
| repeated-test-reruns | bash | sonnet46-1m-medium-cli2.1.114 | 2 | 1.3min | 0.1% | $0.16 | 0.04% |
| fixture-rework | default | opus47-1m-high-cli2.1.114 | 1 | 0.7min | 0.0% | $0.18 | 0.05% |
| repeated-test-reruns | default | opus47-1m-xhigh-cli2.1.112 | 1 | 0.7min | 0.0% | $0.18 | 0.05% |
| fixture-rework | default | opus47-1m-xhigh-cli2.1.112 | 1 | 0.7min | 0.0% | $0.18 | 0.05% |
| repeated-test-reruns | default | haiku45-200k-na-cli2.1.114 | 3 | 2.0min | 0.1% | $0.18 | 0.05% |
| repeated-test-reruns | typescript-bun | opus47-200k-medium-cli2.1.114 | 1 | 0.7min | 0.0% | $0.19 | 0.05% |
| fixture-rework | powershell | opus47-1m-high-cli2.1.114 | 1 | 0.7min | 0.0% | $0.19 | 0.05% |
| fixture-rework | typescript-bun | opus47-200k-medium-cli2.1.114 | 1 | 1.0min | 0.0% | $0.22 | 0.06% |
| fixture-rework | powershell | opus47-1m-medium-cli2.1.112 | 1 | 1.0min | 0.0% | $0.22 | 0.06% |
| pwsh-runtime-install-overhead | powershell | haiku45-200k-na-cli2.1.114 | 5 | 3.9min | 0.2% | $0.22 | 0.06% |
| act-push-debug-loops | bash | sonnet46-200k-medium-cli2.1.114 | 3 | 1.8min | 0.1% | $0.23 | 0.06% |
| act-push-debug-loops | typescript-bun | opus47-1m-xhigh-cli2.1.112 | 1 | 0.8min | 0.0% | $0.24 | 0.07% |
| actionlint-fix-cycles | powershell | haiku45-200k-na-cli2.1.114 | 3 | 3.0min | 0.1% | $0.24 | 0.07% |
| repeated-test-reruns | typescript-bun | sonnet46-200k-medium-cli2.1.114 | 3 | 2.0min | 0.1% | $0.27 | 0.07% |
| act-push-debug-loops | powershell | sonnet46-200k-medium-cli2.1.114 | 3 | 2.3min | 0.1% | $0.29 | 0.08% |
| act-push-debug-loops | bash | haiku45-200k-na-cli2.1.114 | 4 | 13.8min | 0.6% | $0.32 | 0.09% |
| act-push-debug-loops | typescript-bun | haiku45-200k-na-cli2.1.114 | 4 | 4.0min | 0.2% | $0.32 | 0.09% |
| act-push-debug-loops | powershell | sonnet46-1m-medium-cli2.1.114 | 4 | 2.9min | 0.1% | $0.37 | 0.10% |
| repeated-test-reruns | typescript-bun | sonnet46-1m-medium-cli2.1.114 | 3 | 2.7min | 0.1% | $0.38 | 0.11% |
| repeated-test-reruns | bash | haiku45-200k-na-cli2.1.114 | 5 | 6.7min | 0.3% | $0.38 | 0.11% |
| fixture-rework | bash | opus47-1m-high-cli2.1.114 | 2 | 1.7min | 0.1% | $0.39 | 0.11% |
| repeated-test-reruns | powershell | sonnet46-1m-medium-cli2.1.114 | 2 | 2.7min | 0.1% | $0.39 | 0.11% |
| docker-pwsh-install | powershell | sonnet46-1m-medium-cli2.1.114 | 1 | 3.0min | 0.1% | $0.41 | 0.11% |
| docker-pwsh-install | powershell | opus47-1m-xhigh-cli2.1.112 | 1 | 1.5min | 0.1% | $0.42 | 0.12% |
| mid-run-module-restructure | powershell | opus47-1m-medium-cli2.1.112 | 1 | 2.0min | 0.1% | $0.44 | 0.12% |
| fixture-rework | powershell | opus47-1m-xhigh-cli2.1.112 | 1 | 1.3min | 0.1% | $0.48 | 0.13% |
| repeated-test-reruns | bash | opus47-1m-xhigh-cli2.1.112 | 1 | 1.7min | 0.1% | $0.52 | 0.14% |
| fixture-rework | typescript-bun | haiku45-200k-na-cli2.1.114 | 2 | 6.3min | 0.3% | $0.54 | 0.15% |
| repeated-test-reruns | powershell | opus47-200k-medium-cli2.1.114 | 4 | 3.0min | 0.1% | $0.72 | 0.20% |
| repeated-test-reruns | powershell | opus47-1m-medium-cli2.1.112 | 3 | 3.7min | 0.2% | $0.75 | 0.21% |
| repeated-test-reruns | powershell | opus47-1m-high-cli2.1.114 | 3 | 3.0min | 0.1% | $0.76 | 0.21% |
| act-push-debug-loops | powershell | haiku45-200k-na-cli2.1.114 | 9 | 12.4min | 0.5% | $0.80 | 0.22% |
| repeated-test-reruns | typescript-bun | haiku45-200k-na-cli2.1.114 | 6 | 8.7min | 0.4% | $0.81 | 0.22% |
| fixture-rework | powershell | sonnet46-200k-medium-cli2.1.114 | 1 | 6.7min | 0.3% | $0.84 | 0.23% |
| fixture-rework | bash | sonnet46-1m-medium-cli2.1.114 | 1 | 9.3min | 0.4% | $1.04 | 0.29% |
| mid-run-module-restructure | powershell | opus47-1m-xhigh-cli2.1.112 | 2 | 4.0min | 0.2% | $1.06 | 0.29% |
| repeated-test-reruns | powershell | opus47-1m-xhigh-cli2.1.112 | 6 | 5.0min | 0.2% | $1.53 | 0.42% |
| repeated-test-reruns | powershell | haiku45-200k-na-cli2.1.114 | 13 | 19.0min | 0.8% | $1.58 | 0.44% |
| repeated-test-reruns | typescript-bun | opus47-1m-high-cli2.1.114 | 5 | 7.7min | 0.3% | $2.00 | 0.55% |
| repeated-test-reruns | typescript-bun | opus47-1m-xhigh-cli2.1.112 | 5 | 7.7min | 0.3% | $2.28 | 0.63% |

</details>

<details>
<summary>Sorted by fell-in count (fewest first)</summary>

| Trap | Language | Model | Fell In | Time Lost | % of Time | $ Lost | % of $ |
|------|------|-------|---------|-----------|-----------|--------|--------|
| repeated-test-reruns | bash | opus47-1m-xhigh-cli2.1.112 | 1 | 1.7min | 0.1% | $0.52 | 0.14% |
| repeated-test-reruns | bash | sonnet46-200k-medium-cli2.1.114 | 1 | 0.7min | 0.0% | $0.09 | 0.02% |
| repeated-test-reruns | default | opus47-1m-xhigh-cli2.1.112 | 1 | 0.7min | 0.0% | $0.18 | 0.05% |
| repeated-test-reruns | powershell | sonnet46-200k-medium-cli2.1.114 | 1 | 1.0min | 0.0% | $0.13 | 0.04% |
| repeated-test-reruns | typescript-bun | opus47-1m-medium-cli2.1.112 | 1 | 0.7min | 0.0% | $0.16 | 0.04% |
| repeated-test-reruns | typescript-bun | opus47-200k-medium-cli2.1.114 | 1 | 0.7min | 0.0% | $0.19 | 0.05% |
| act-push-debug-loops | default | sonnet46-1m-medium-cli2.1.114 | 1 | 0.3min | 0.0% | $0.05 | 0.01% |
| act-push-debug-loops | default | sonnet46-200k-medium-cli2.1.114 | 1 | 0.3min | 0.0% | $0.04 | 0.01% |
| act-push-debug-loops | typescript-bun | opus47-1m-xhigh-cli2.1.112 | 1 | 0.8min | 0.0% | $0.24 | 0.07% |
| fixture-rework | bash | haiku45-200k-na-cli2.1.114 | 1 | 0.7min | 0.0% | $0.06 | 0.02% |
| fixture-rework | bash | sonnet46-1m-medium-cli2.1.114 | 1 | 9.3min | 0.4% | $1.04 | 0.29% |
| fixture-rework | default | haiku45-200k-na-cli2.1.114 | 1 | 6.3min | 0.3% | $0.09 | 0.03% |
| fixture-rework | default | opus47-1m-high-cli2.1.114 | 1 | 0.7min | 0.0% | $0.18 | 0.05% |
| fixture-rework | default | opus47-1m-xhigh-cli2.1.112 | 1 | 0.7min | 0.0% | $0.18 | 0.05% |
| fixture-rework | default | sonnet46-1m-medium-cli2.1.114 | 1 | 1.3min | 0.1% | $0.14 | 0.04% |
| fixture-rework | powershell | haiku45-200k-na-cli2.1.114 | 1 | 1.3min | 0.1% | $0.12 | 0.03% |
| fixture-rework | powershell | opus47-1m-high-cli2.1.114 | 1 | 0.7min | 0.0% | $0.19 | 0.05% |
| fixture-rework | powershell | opus47-1m-medium-cli2.1.112 | 1 | 1.0min | 0.0% | $0.22 | 0.06% |
| fixture-rework | powershell | opus47-1m-xhigh-cli2.1.112 | 1 | 1.3min | 0.1% | $0.48 | 0.13% |
| fixture-rework | powershell | sonnet46-1m-medium-cli2.1.114 | 1 | 1.0min | 0.0% | $0.14 | 0.04% |
| fixture-rework | powershell | sonnet46-200k-medium-cli2.1.114 | 1 | 6.7min | 0.3% | $0.84 | 0.23% |
| fixture-rework | typescript-bun | opus47-200k-medium-cli2.1.114 | 1 | 1.0min | 0.0% | $0.22 | 0.06% |
| actionlint-fix-cycles | bash | haiku45-200k-na-cli2.1.114 | 1 | 1.3min | 0.1% | $0.09 | 0.02% |
| actionlint-fix-cycles | typescript-bun | haiku45-200k-na-cli2.1.114 | 1 | 0.7min | 0.0% | $0.04 | 0.01% |
| mid-run-module-restructure | powershell | opus47-1m-medium-cli2.1.112 | 1 | 2.0min | 0.1% | $0.44 | 0.12% |
| docker-pwsh-install | powershell | opus47-1m-xhigh-cli2.1.112 | 1 | 1.5min | 0.1% | $0.42 | 0.12% |
| docker-pwsh-install | powershell | sonnet46-1m-medium-cli2.1.114 | 1 | 3.0min | 0.1% | $0.41 | 0.11% |
| act-permission-path-errors | default | sonnet46-200k-medium-cli2.1.114 | 1 | 0.5min | 0.0% | $0.07 | 0.02% |
| act-permission-path-errors | powershell | sonnet46-200k-medium-cli2.1.114 | 1 | 0.5min | 0.0% | $0.06 | 0.02% |
| act-permission-path-errors | typescript-bun | haiku45-200k-na-cli2.1.114 | 1 | 1.5min | 0.1% | $0.12 | 0.03% |
| bats-setup-issues | bash | sonnet46-1m-medium-cli2.1.114 | 1 | 0.8min | 0.0% | $0.08 | 0.02% |
| repeated-test-reruns | bash | sonnet46-1m-medium-cli2.1.114 | 2 | 1.3min | 0.1% | $0.16 | 0.04% |
| repeated-test-reruns | powershell | sonnet46-1m-medium-cli2.1.114 | 2 | 2.7min | 0.1% | $0.39 | 0.11% |
| fixture-rework | bash | opus47-1m-high-cli2.1.114 | 2 | 1.7min | 0.1% | $0.39 | 0.11% |
| fixture-rework | typescript-bun | haiku45-200k-na-cli2.1.114 | 2 | 6.3min | 0.3% | $0.54 | 0.15% |
| mid-run-module-restructure | powershell | opus47-1m-xhigh-cli2.1.112 | 2 | 4.0min | 0.2% | $1.06 | 0.29% |
| pwsh-runtime-install-overhead | powershell | sonnet46-200k-medium-cli2.1.114 | 2 | 0.9min | 0.0% | $0.12 | 0.03% |
| bats-setup-issues | bash | haiku45-200k-na-cli2.1.114 | 2 | 1.5min | 0.1% | $0.05 | 0.01% |
| repeated-test-reruns | default | haiku45-200k-na-cli2.1.114 | 3 | 2.0min | 0.1% | $0.18 | 0.05% |
| repeated-test-reruns | powershell | opus47-1m-high-cli2.1.114 | 3 | 3.0min | 0.1% | $0.76 | 0.21% |
| repeated-test-reruns | powershell | opus47-1m-medium-cli2.1.112 | 3 | 3.7min | 0.2% | $0.75 | 0.21% |
| repeated-test-reruns | typescript-bun | sonnet46-1m-medium-cli2.1.114 | 3 | 2.7min | 0.1% | $0.38 | 0.11% |
| repeated-test-reruns | typescript-bun | sonnet46-200k-medium-cli2.1.114 | 3 | 2.0min | 0.1% | $0.27 | 0.07% |
| act-push-debug-loops | bash | sonnet46-200k-medium-cli2.1.114 | 3 | 1.8min | 0.1% | $0.23 | 0.06% |
| act-push-debug-loops | powershell | sonnet46-200k-medium-cli2.1.114 | 3 | 2.3min | 0.1% | $0.29 | 0.08% |
| actionlint-fix-cycles | default | haiku45-200k-na-cli2.1.114 | 3 | 3.7min | 0.2% | $0.16 | 0.04% |
| actionlint-fix-cycles | powershell | haiku45-200k-na-cli2.1.114 | 3 | 3.0min | 0.1% | $0.24 | 0.07% |
| repeated-test-reruns | powershell | opus47-200k-medium-cli2.1.114 | 4 | 3.0min | 0.1% | $0.72 | 0.20% |
| act-push-debug-loops | bash | haiku45-200k-na-cli2.1.114 | 4 | 13.8min | 0.6% | $0.32 | 0.09% |
| act-push-debug-loops | default | haiku45-200k-na-cli2.1.114 | 4 | 3.0min | 0.1% | $0.12 | 0.03% |
| act-push-debug-loops | powershell | sonnet46-1m-medium-cli2.1.114 | 4 | 2.9min | 0.1% | $0.37 | 0.10% |
| act-push-debug-loops | typescript-bun | haiku45-200k-na-cli2.1.114 | 4 | 4.0min | 0.2% | $0.32 | 0.09% |
| repeated-test-reruns | bash | haiku45-200k-na-cli2.1.114 | 5 | 6.7min | 0.3% | $0.38 | 0.11% |
| repeated-test-reruns | typescript-bun | opus47-1m-high-cli2.1.114 | 5 | 7.7min | 0.3% | $2.00 | 0.55% |
| repeated-test-reruns | typescript-bun | opus47-1m-xhigh-cli2.1.112 | 5 | 7.7min | 0.3% | $2.28 | 0.63% |
| pwsh-runtime-install-overhead | powershell | haiku45-200k-na-cli2.1.114 | 5 | 3.9min | 0.2% | $0.22 | 0.06% |
| repeated-test-reruns | powershell | opus47-1m-xhigh-cli2.1.112 | 6 | 5.0min | 0.2% | $1.53 | 0.42% |
| repeated-test-reruns | typescript-bun | haiku45-200k-na-cli2.1.114 | 6 | 8.7min | 0.4% | $0.81 | 0.22% |
| act-push-debug-loops | powershell | haiku45-200k-na-cli2.1.114 | 9 | 12.4min | 0.5% | $0.80 | 0.22% |
| repeated-test-reruns | powershell | haiku45-200k-na-cli2.1.114 | 13 | 19.0min | 0.8% | $1.58 | 0.44% |

</details>

#### Trap Descriptions

- **act-permission-path-errors**: Files not found or permission denied inside the act Docker container.
- **act-push-debug-loops**: Agent ran `act push` more than twice, indicating repeated workflow debugging.
- **actionlint-fix-cycles**: Workflow YAML required 3+ actionlint runs and 2+ fixes to pass.
- **bats-setup-issues**: Agent struggled with bats-core test framework setup or load helpers.
- **docker-pwsh-install**: Multiple Docker test runs trying to figure out how to install PowerShell in act's container.
- **fixture-rework**: Agent rewrote or edited the same fixture file multiple times (genuine redo cycles, not one-time fixture creation).
- **mid-run-module-restructure**: Agent restructured from a flat .ps1 script to a .psm1 module mid-run.
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
| bash | haiku45-200k-na-cli2.1.114 | 7 | 13 | 24.0min | 1.1% | $0.89 | 0.25% |
| bash | opus47-1m-high-cli2.1.114 | 7 | 2 | 1.7min | 0.1% | $0.39 | 0.11% |
| bash | opus47-1m-medium-cli2.1.112 | 7 | 0 | 0.0min | 0.0% | $0.00 | 0.00% |
| bash | opus47-1m-xhigh-cli2.1.112 | 7 | 1 | 1.7min | 0.1% | $0.52 | 0.14% |
| bash | opus47-200k-medium-cli2.1.114 | 7 | 0 | 0.0min | 0.0% | $0.00 | 0.00% |
| bash | sonnet46-1m-medium-cli2.1.114 | 7 | 4 | 11.4min | 0.5% | $1.29 | 0.36% |
| bash | sonnet46-200k-medium-cli2.1.114 | 7 | 4 | 2.5min | 0.1% | $0.32 | 0.09% |
| default | haiku45-200k-na-cli2.1.114 | 7 | 11 | 15.0min | 0.7% | $0.55 | 0.15% |
| default | opus47-1m-high-cli2.1.114 | 7 | 1 | 0.7min | 0.0% | $0.18 | 0.05% |
| default | opus47-1m-medium-cli2.1.112 | 7 | 0 | 0.0min | 0.0% | $0.00 | 0.00% |
| default | opus47-1m-xhigh-cli2.1.112 | 7 | 2 | 1.3min | 0.1% | $0.36 | 0.10% |
| default | opus47-200k-medium-cli2.1.114 | 7 | 0 | 0.0min | 0.0% | $0.00 | 0.00% |
| default | sonnet46-1m-medium-cli2.1.114 | 7 | 2 | 1.7min | 0.1% | $0.19 | 0.05% |
| default | sonnet46-200k-medium-cli2.1.114 | 7 | 2 | 0.8min | 0.0% | $0.11 | 0.03% |
| powershell | haiku45-200k-na-cli2.1.114 | 14 | 31 | 39.6min | 1.7% | $2.96 | 0.82% |
| powershell | opus47-1m-high-cli2.1.114 | 14 | 4 | 3.7min | 0.2% | $0.94 | 0.26% |
| powershell | opus47-1m-medium-cli2.1.112 | 14 | 5 | 6.7min | 0.3% | $1.41 | 0.39% |
| powershell | opus47-1m-xhigh-cli2.1.112 | 14 | 10 | 11.8min | 0.5% | $3.49 | 0.97% |
| powershell | opus47-200k-medium-cli2.1.114 | 14 | 4 | 3.0min | 0.1% | $0.72 | 0.20% |
| powershell | sonnet46-1m-medium-cli2.1.114 | 14 | 8 | 9.5min | 0.4% | $1.31 | 0.36% |
| powershell | sonnet46-200k-medium-cli2.1.114 | 14 | 8 | 11.3min | 0.5% | $1.44 | 0.40% |
| typescript-bun | haiku45-200k-na-cli2.1.114 | 7 | 14 | 21.2min | 0.9% | $1.84 | 0.51% |
| typescript-bun | opus47-1m-high-cli2.1.114 | 7 | 5 | 7.7min | 0.3% | $2.00 | 0.55% |
| typescript-bun | opus47-1m-medium-cli2.1.112 | 7 | 1 | 0.7min | 0.0% | $0.16 | 0.04% |
| typescript-bun | opus47-1m-xhigh-cli2.1.112 | 7 | 6 | 8.5min | 0.4% | $2.51 | 0.70% |
| typescript-bun | opus47-200k-medium-cli2.1.114 | 7 | 2 | 1.7min | 0.1% | $0.40 | 0.11% |
| typescript-bun | sonnet46-1m-medium-cli2.1.114 | 7 | 3 | 2.7min | 0.1% | $0.38 | 0.11% |
| typescript-bun | sonnet46-200k-medium-cli2.1.114 | 7 | 3 | 2.0min | 0.1% | $0.27 | 0.07% |


<details>
<summary>Sorted by time lost (least first)</summary>

| Language | Model | Runs | Traps | Time Lost | % of Time | $ Lost | % of $ |
|------|-------|------|-------|-----------|-----------|--------|--------|
| bash | opus47-1m-medium-cli2.1.112 | 7 | 0 | 0.0min | 0.0% | $0.00 | 0.00% |
| bash | opus47-200k-medium-cli2.1.114 | 7 | 0 | 0.0min | 0.0% | $0.00 | 0.00% |
| default | opus47-1m-medium-cli2.1.112 | 7 | 0 | 0.0min | 0.0% | $0.00 | 0.00% |
| default | opus47-200k-medium-cli2.1.114 | 7 | 0 | 0.0min | 0.0% | $0.00 | 0.00% |
| default | opus47-1m-high-cli2.1.114 | 7 | 1 | 0.7min | 0.0% | $0.18 | 0.05% |
| typescript-bun | opus47-1m-medium-cli2.1.112 | 7 | 1 | 0.7min | 0.0% | $0.16 | 0.04% |
| default | sonnet46-200k-medium-cli2.1.114 | 7 | 2 | 0.8min | 0.0% | $0.11 | 0.03% |
| default | opus47-1m-xhigh-cli2.1.112 | 7 | 2 | 1.3min | 0.1% | $0.36 | 0.10% |
| default | sonnet46-1m-medium-cli2.1.114 | 7 | 2 | 1.7min | 0.1% | $0.19 | 0.05% |
| bash | opus47-1m-high-cli2.1.114 | 7 | 2 | 1.7min | 0.1% | $0.39 | 0.11% |
| bash | opus47-1m-xhigh-cli2.1.112 | 7 | 1 | 1.7min | 0.1% | $0.52 | 0.14% |
| typescript-bun | opus47-200k-medium-cli2.1.114 | 7 | 2 | 1.7min | 0.1% | $0.40 | 0.11% |
| typescript-bun | sonnet46-200k-medium-cli2.1.114 | 7 | 3 | 2.0min | 0.1% | $0.27 | 0.07% |
| bash | sonnet46-200k-medium-cli2.1.114 | 7 | 4 | 2.5min | 0.1% | $0.32 | 0.09% |
| typescript-bun | sonnet46-1m-medium-cli2.1.114 | 7 | 3 | 2.7min | 0.1% | $0.38 | 0.11% |
| powershell | opus47-200k-medium-cli2.1.114 | 14 | 4 | 3.0min | 0.1% | $0.72 | 0.20% |
| powershell | opus47-1m-high-cli2.1.114 | 14 | 4 | 3.7min | 0.2% | $0.94 | 0.26% |
| powershell | opus47-1m-medium-cli2.1.112 | 14 | 5 | 6.7min | 0.3% | $1.41 | 0.39% |
| typescript-bun | opus47-1m-high-cli2.1.114 | 7 | 5 | 7.7min | 0.3% | $2.00 | 0.55% |
| typescript-bun | opus47-1m-xhigh-cli2.1.112 | 7 | 6 | 8.5min | 0.4% | $2.51 | 0.70% |
| powershell | sonnet46-1m-medium-cli2.1.114 | 14 | 8 | 9.5min | 0.4% | $1.31 | 0.36% |
| powershell | sonnet46-200k-medium-cli2.1.114 | 14 | 8 | 11.3min | 0.5% | $1.44 | 0.40% |
| bash | sonnet46-1m-medium-cli2.1.114 | 7 | 4 | 11.4min | 0.5% | $1.29 | 0.36% |
| powershell | opus47-1m-xhigh-cli2.1.112 | 14 | 10 | 11.8min | 0.5% | $3.49 | 0.97% |
| default | haiku45-200k-na-cli2.1.114 | 7 | 11 | 15.0min | 0.7% | $0.55 | 0.15% |
| typescript-bun | haiku45-200k-na-cli2.1.114 | 7 | 14 | 21.2min | 0.9% | $1.84 | 0.51% |
| bash | haiku45-200k-na-cli2.1.114 | 7 | 13 | 24.0min | 1.1% | $0.89 | 0.25% |
| powershell | haiku45-200k-na-cli2.1.114 | 14 | 31 | 39.6min | 1.7% | $2.96 | 0.82% |

</details>

<details>
<summary>Sorted by $ lost (least first)</summary>

| Language | Model | Runs | Traps | Time Lost | % of Time | $ Lost | % of $ |
|------|-------|------|-------|-----------|-----------|--------|--------|
| bash | opus47-1m-medium-cli2.1.112 | 7 | 0 | 0.0min | 0.0% | $0.00 | 0.00% |
| bash | opus47-200k-medium-cli2.1.114 | 7 | 0 | 0.0min | 0.0% | $0.00 | 0.00% |
| default | opus47-1m-medium-cli2.1.112 | 7 | 0 | 0.0min | 0.0% | $0.00 | 0.00% |
| default | opus47-200k-medium-cli2.1.114 | 7 | 0 | 0.0min | 0.0% | $0.00 | 0.00% |
| default | sonnet46-200k-medium-cli2.1.114 | 7 | 2 | 0.8min | 0.0% | $0.11 | 0.03% |
| typescript-bun | opus47-1m-medium-cli2.1.112 | 7 | 1 | 0.7min | 0.0% | $0.16 | 0.04% |
| default | opus47-1m-high-cli2.1.114 | 7 | 1 | 0.7min | 0.0% | $0.18 | 0.05% |
| default | sonnet46-1m-medium-cli2.1.114 | 7 | 2 | 1.7min | 0.1% | $0.19 | 0.05% |
| typescript-bun | sonnet46-200k-medium-cli2.1.114 | 7 | 3 | 2.0min | 0.1% | $0.27 | 0.07% |
| bash | sonnet46-200k-medium-cli2.1.114 | 7 | 4 | 2.5min | 0.1% | $0.32 | 0.09% |
| default | opus47-1m-xhigh-cli2.1.112 | 7 | 2 | 1.3min | 0.1% | $0.36 | 0.10% |
| typescript-bun | sonnet46-1m-medium-cli2.1.114 | 7 | 3 | 2.7min | 0.1% | $0.38 | 0.11% |
| bash | opus47-1m-high-cli2.1.114 | 7 | 2 | 1.7min | 0.1% | $0.39 | 0.11% |
| typescript-bun | opus47-200k-medium-cli2.1.114 | 7 | 2 | 1.7min | 0.1% | $0.40 | 0.11% |
| bash | opus47-1m-xhigh-cli2.1.112 | 7 | 1 | 1.7min | 0.1% | $0.52 | 0.14% |
| default | haiku45-200k-na-cli2.1.114 | 7 | 11 | 15.0min | 0.7% | $0.55 | 0.15% |
| powershell | opus47-200k-medium-cli2.1.114 | 14 | 4 | 3.0min | 0.1% | $0.72 | 0.20% |
| bash | haiku45-200k-na-cli2.1.114 | 7 | 13 | 24.0min | 1.1% | $0.89 | 0.25% |
| powershell | opus47-1m-high-cli2.1.114 | 14 | 4 | 3.7min | 0.2% | $0.94 | 0.26% |
| bash | sonnet46-1m-medium-cli2.1.114 | 7 | 4 | 11.4min | 0.5% | $1.29 | 0.36% |
| powershell | sonnet46-1m-medium-cli2.1.114 | 14 | 8 | 9.5min | 0.4% | $1.31 | 0.36% |
| powershell | opus47-1m-medium-cli2.1.112 | 14 | 5 | 6.7min | 0.3% | $1.41 | 0.39% |
| powershell | sonnet46-200k-medium-cli2.1.114 | 14 | 8 | 11.3min | 0.5% | $1.44 | 0.40% |
| typescript-bun | haiku45-200k-na-cli2.1.114 | 7 | 14 | 21.2min | 0.9% | $1.84 | 0.51% |
| typescript-bun | opus47-1m-high-cli2.1.114 | 7 | 5 | 7.7min | 0.3% | $2.00 | 0.55% |
| typescript-bun | opus47-1m-xhigh-cli2.1.112 | 7 | 6 | 8.5min | 0.4% | $2.51 | 0.70% |
| powershell | haiku45-200k-na-cli2.1.114 | 14 | 31 | 39.6min | 1.7% | $2.96 | 0.82% |
| powershell | opus47-1m-xhigh-cli2.1.112 | 14 | 10 | 11.8min | 0.5% | $3.49 | 0.97% |

</details>

### Prompt Cache Savings

| Status | Runs | $ Saved | % of $ |
|--------|------|---------|--------|
| Full hit (100%) | 0 | $0.00 | 0.00% |
| Partial | 225 | $15.88 | 4.40% |
| Miss | 20 | $0.00 | 0.00% |

## Test Quality Evaluation

### Structural Metrics by Language/Model/Effort

Automated analysis of test files: test count, assertion count, and test-to-code line ratio.

| Language | Model | Avg Tests | Avg Assertions | Avg Assert/Test | Avg Test:Code Ratio |
|------|-------|-----------|----------------|-----------------|---------------------|
| bash | haiku45-200k-na | 14.3 | 21.4 | 1.5 | 0.85 |
| bash | opus47-1m-high | 24.9 | 49.4 | 2.0 | 1.23 |
| bash | opus47-1m-medium | 11.9 | 31.7 | 2.7 | 1.21 |
| bash | opus47-1m-xhigh | 25.9 | 47.3 | 1.8 | 1.26 |
| bash | opus47-200k-medium | 17.0 | 35.1 | 2.1 | 1.14 |
| bash | sonnet46-1m-medium | 22.1 | 44.6 | 2.0 | 1.36 |
| bash | sonnet46-200k-medium | 17.4 | 36.4 | 2.1 | 0.91 |
| default | haiku45-200k-na | 15.9 | 32.3 | 2.0 | 1.43 |
| default | opus47-1m-high | 23.3 | 50.3 | 2.2 | 1.16 |
| default | opus47-1m-medium | 17.0 | 33.3 | 2.0 | 1.64 |
| default | opus47-1m-xhigh | 24.0 | 50.6 | 2.1 | 1.55 |
| default | opus47-200k-medium | 17.4 | 42.7 | 2.5 | 1.77 |
| default | sonnet46-1m-medium | 30.9 | 37.7 | 1.2 | 1.26 |
| default | sonnet46-200k-medium | 30.1 | 45.4 | 1.5 | 1.81 |
| powershell | haiku45-200k-na | 6.4 | 12.4 | 1.9 | 0.46 |
| powershell | opus47-1m-high | 26.4 | 50.3 | 1.9 | 3.11 |
| powershell | opus47-1m-medium | 19.4 | 39.7 | 2.0 | 3.42 |
| powershell | opus47-1m-xhigh | 28.7 | 55.2 | 1.9 | 2.18 |
| powershell | opus47-200k-medium | 21.1 | 42.0 | 2.0 | 5.34 |
| powershell | sonnet46-1m-medium | 31.7 | 45.2 | 1.4 | 1.65 |
| powershell | sonnet46-200k-medium | 29.6 | 41.7 | 1.4 | 1.16 |
| typescript-bun | haiku45-200k-na | 17.3 | 40.4 | 2.3 | 0.77 |
| typescript-bun | opus47-1m-high | 27.6 | 61.0 | 2.2 | 1.48 |
| typescript-bun | opus47-1m-medium | 18.0 | 42.0 | 2.3 | 1.54 |
| typescript-bun | opus47-1m-xhigh | 30.7 | 65.6 | 2.1 | 1.73 |
| typescript-bun | opus47-200k-medium | 15.0 | 37.9 | 2.5 | 0.92 |
| typescript-bun | sonnet46-1m-medium | 31.6 | 53.7 | 1.7 | 1.07 |
| typescript-bun | sonnet46-200k-medium | 27.3 | 54.7 | 2.0 | 1.42 |


<details>
<summary>Sorted by avg tests (most first)</summary>

| Language | Model | Avg Tests | Avg Assertions | Avg Assert/Test | Avg Test:Code Ratio |
|------|-------|-----------|----------------|-----------------|---------------------|
| powershell | sonnet46-1m-medium | 31.7 | 45.2 | 1.4 | 1.65 |
| typescript-bun | sonnet46-1m-medium | 31.6 | 53.7 | 1.7 | 1.07 |
| default | sonnet46-1m-medium | 30.9 | 37.7 | 1.2 | 1.26 |
| typescript-bun | opus47-1m-xhigh | 30.7 | 65.6 | 2.1 | 1.73 |
| default | sonnet46-200k-medium | 30.1 | 45.4 | 1.5 | 1.81 |
| powershell | sonnet46-200k-medium | 29.6 | 41.7 | 1.4 | 1.16 |
| powershell | opus47-1m-xhigh | 28.7 | 55.2 | 1.9 | 2.18 |
| typescript-bun | opus47-1m-high | 27.6 | 61.0 | 2.2 | 1.48 |
| typescript-bun | sonnet46-200k-medium | 27.3 | 54.7 | 2.0 | 1.42 |
| powershell | opus47-1m-high | 26.4 | 50.3 | 1.9 | 3.11 |
| bash | opus47-1m-xhigh | 25.9 | 47.3 | 1.8 | 1.26 |
| bash | opus47-1m-high | 24.9 | 49.4 | 2.0 | 1.23 |
| default | opus47-1m-xhigh | 24.0 | 50.6 | 2.1 | 1.55 |
| default | opus47-1m-high | 23.3 | 50.3 | 2.2 | 1.16 |
| bash | sonnet46-1m-medium | 22.1 | 44.6 | 2.0 | 1.36 |
| powershell | opus47-200k-medium | 21.1 | 42.0 | 2.0 | 5.34 |
| powershell | opus47-1m-medium | 19.4 | 39.7 | 2.0 | 3.42 |
| typescript-bun | opus47-1m-medium | 18.0 | 42.0 | 2.3 | 1.54 |
| bash | sonnet46-200k-medium | 17.4 | 36.4 | 2.1 | 0.91 |
| default | opus47-200k-medium | 17.4 | 42.7 | 2.5 | 1.77 |
| typescript-bun | haiku45-200k-na | 17.3 | 40.4 | 2.3 | 0.77 |
| bash | opus47-200k-medium | 17.0 | 35.1 | 2.1 | 1.14 |
| default | opus47-1m-medium | 17.0 | 33.3 | 2.0 | 1.64 |
| default | haiku45-200k-na | 15.9 | 32.3 | 2.0 | 1.43 |
| typescript-bun | opus47-200k-medium | 15.0 | 37.9 | 2.5 | 0.92 |
| bash | haiku45-200k-na | 14.3 | 21.4 | 1.5 | 0.85 |
| bash | opus47-1m-medium | 11.9 | 31.7 | 2.7 | 1.21 |
| powershell | haiku45-200k-na | 6.4 | 12.4 | 1.9 | 0.46 |

</details>

<details>
<summary>Sorted by avg assertions (most first)</summary>

| Language | Model | Avg Tests | Avg Assertions | Avg Assert/Test | Avg Test:Code Ratio |
|------|-------|-----------|----------------|-----------------|---------------------|
| typescript-bun | opus47-1m-xhigh | 30.7 | 65.6 | 2.1 | 1.73 |
| typescript-bun | opus47-1m-high | 27.6 | 61.0 | 2.2 | 1.48 |
| powershell | opus47-1m-xhigh | 28.7 | 55.2 | 1.9 | 2.18 |
| typescript-bun | sonnet46-200k-medium | 27.3 | 54.7 | 2.0 | 1.42 |
| typescript-bun | sonnet46-1m-medium | 31.6 | 53.7 | 1.7 | 1.07 |
| default | opus47-1m-xhigh | 24.0 | 50.6 | 2.1 | 1.55 |
| default | opus47-1m-high | 23.3 | 50.3 | 2.2 | 1.16 |
| powershell | opus47-1m-high | 26.4 | 50.3 | 1.9 | 3.11 |
| bash | opus47-1m-high | 24.9 | 49.4 | 2.0 | 1.23 |
| bash | opus47-1m-xhigh | 25.9 | 47.3 | 1.8 | 1.26 |
| default | sonnet46-200k-medium | 30.1 | 45.4 | 1.5 | 1.81 |
| powershell | sonnet46-1m-medium | 31.7 | 45.2 | 1.4 | 1.65 |
| bash | sonnet46-1m-medium | 22.1 | 44.6 | 2.0 | 1.36 |
| default | opus47-200k-medium | 17.4 | 42.7 | 2.5 | 1.77 |
| powershell | opus47-200k-medium | 21.1 | 42.0 | 2.0 | 5.34 |
| typescript-bun | opus47-1m-medium | 18.0 | 42.0 | 2.3 | 1.54 |
| powershell | sonnet46-200k-medium | 29.6 | 41.7 | 1.4 | 1.16 |
| typescript-bun | haiku45-200k-na | 17.3 | 40.4 | 2.3 | 0.77 |
| powershell | opus47-1m-medium | 19.4 | 39.7 | 2.0 | 3.42 |
| typescript-bun | opus47-200k-medium | 15.0 | 37.9 | 2.5 | 0.92 |
| default | sonnet46-1m-medium | 30.9 | 37.7 | 1.2 | 1.26 |
| bash | sonnet46-200k-medium | 17.4 | 36.4 | 2.1 | 0.91 |
| bash | opus47-200k-medium | 17.0 | 35.1 | 2.1 | 1.14 |
| default | opus47-1m-medium | 17.0 | 33.3 | 2.0 | 1.64 |
| default | haiku45-200k-na | 15.9 | 32.3 | 2.0 | 1.43 |
| bash | opus47-1m-medium | 11.9 | 31.7 | 2.7 | 1.21 |
| bash | haiku45-200k-na | 14.3 | 21.4 | 1.5 | 0.85 |
| powershell | haiku45-200k-na | 6.4 | 12.4 | 1.9 | 0.46 |

</details>

<details>
<summary>Sorted by avg test:code ratio (highest first)</summary>

| Language | Model | Avg Tests | Avg Assertions | Avg Assert/Test | Avg Test:Code Ratio |
|------|-------|-----------|----------------|-----------------|---------------------|
| powershell | opus47-200k-medium | 21.1 | 42.0 | 2.0 | 5.34 |
| powershell | opus47-1m-medium | 19.4 | 39.7 | 2.0 | 3.42 |
| powershell | opus47-1m-high | 26.4 | 50.3 | 1.9 | 3.11 |
| powershell | opus47-1m-xhigh | 28.7 | 55.2 | 1.9 | 2.18 |
| default | sonnet46-200k-medium | 30.1 | 45.4 | 1.5 | 1.81 |
| default | opus47-200k-medium | 17.4 | 42.7 | 2.5 | 1.77 |
| typescript-bun | opus47-1m-xhigh | 30.7 | 65.6 | 2.1 | 1.73 |
| powershell | sonnet46-1m-medium | 31.7 | 45.2 | 1.4 | 1.65 |
| default | opus47-1m-medium | 17.0 | 33.3 | 2.0 | 1.64 |
| default | opus47-1m-xhigh | 24.0 | 50.6 | 2.1 | 1.55 |
| typescript-bun | opus47-1m-medium | 18.0 | 42.0 | 2.3 | 1.54 |
| typescript-bun | opus47-1m-high | 27.6 | 61.0 | 2.2 | 1.48 |
| default | haiku45-200k-na | 15.9 | 32.3 | 2.0 | 1.43 |
| typescript-bun | sonnet46-200k-medium | 27.3 | 54.7 | 2.0 | 1.42 |
| bash | sonnet46-1m-medium | 22.1 | 44.6 | 2.0 | 1.36 |
| bash | opus47-1m-xhigh | 25.9 | 47.3 | 1.8 | 1.26 |
| default | sonnet46-1m-medium | 30.9 | 37.7 | 1.2 | 1.26 |
| bash | opus47-1m-high | 24.9 | 49.4 | 2.0 | 1.23 |
| bash | opus47-1m-medium | 11.9 | 31.7 | 2.7 | 1.21 |
| default | opus47-1m-high | 23.3 | 50.3 | 2.2 | 1.16 |
| powershell | sonnet46-200k-medium | 29.6 | 41.7 | 1.4 | 1.16 |
| bash | opus47-200k-medium | 17.0 | 35.1 | 2.1 | 1.14 |
| typescript-bun | sonnet46-1m-medium | 31.6 | 53.7 | 1.7 | 1.07 |
| typescript-bun | opus47-200k-medium | 15.0 | 37.9 | 2.5 | 0.92 |
| bash | sonnet46-200k-medium | 17.4 | 36.4 | 2.1 | 0.91 |
| bash | haiku45-200k-na | 14.3 | 21.4 | 1.5 | 0.85 |
| typescript-bun | haiku45-200k-na | 17.3 | 40.4 | 2.3 | 0.77 |
| powershell | haiku45-200k-na | 6.4 | 12.4 | 1.9 | 0.46 |

</details>


<details>
<summary>Per-run structural metrics</summary>

| Task | Language | Model | Tests | Assertions | Assert/Test | Test Lines | Impl Lines | Test:Code |
|------|------|-------|-------|------------|-------------|------------|------------|-----------|
| Semantic Version Bumper | bash | haiku45-200k-na | 12 | 14 | 1.2 | 165 | 580 | 0.28 |
| Semantic Version Bumper | bash | opus47-1m-high | 31 | 61 | 2.0 | 397 | 240 | 1.65 |
| Semantic Version Bumper | bash | opus47-1m-medium | 6 | 7 | 1.2 | 96 | 152 | 0.63 |
| Semantic Version Bumper | bash | opus47-1m-xhigh | 35 | 67 | 1.9 | 374 | 298 | 1.26 |
| Semantic Version Bumper | bash | opus47-200k-medium | 27 | 58 | 2.1 | 299 | 182 | 1.64 |
| Semantic Version Bumper | bash | sonnet46-200k-medium | 20 | 43 | 2.1 | 275 | 142 | 1.94 |
| Semantic Version Bumper | bash | sonnet46-1m-medium | 21 | 25 | 1.2 | 217 | 376 | 0.58 |
| Semantic Version Bumper | default | haiku45-200k-na | 21 | 29 | 1.4 | 210 | 217 | 0.97 |
| Semantic Version Bumper | default | opus47-1m-high | 25 | 47 | 1.9 | 231 | 421 | 0.55 |
| Semantic Version Bumper | default | opus47-1m-medium | 22 | 39 | 1.8 | 319 | 180 | 1.77 |
| Semantic Version Bumper | default | opus47-1m-xhigh | 30 | 70 | 2.3 | 505 | 280 | 1.80 |
| Semantic Version Bumper | default | opus47-200k-medium | 13 | 53 | 4.1 | 245 | 170 | 1.44 |
| Semantic Version Bumper | default | sonnet46-200k-medium | 44 | 53 | 1.2 | 399 | 175 | 2.28 |
| Semantic Version Bumper | default | sonnet46-1m-medium | 44 | 46 | 1.0 | 359 | 320 | 1.12 |
| Semantic Version Bumper | powershell | haiku45-200k-na | 0 | 0 | 0.0 | 0 | 702 | 0.00 |
| Semantic Version Bumper | powershell | opus47-1m-high | 54 | 82 | 1.5 | 514 | 39 | 13.18 |
| Semantic Version Bumper | powershell | opus47-1m-medium | 36 | 66 | 1.8 | 315 | 54 | 5.83 |
| Semantic Version Bumper | powershell | opus47-1m-xhigh | 27 | 46 | 1.7 | 261 | 248 | 1.05 |
| Semantic Version Bumper | powershell | opus47-200k-medium | 33 | 60 | 1.8 | 229 | 127 | 1.80 |
| Semantic Version Bumper | powershell | sonnet46-200k-medium | 44 | 58 | 1.3 | 355 | 181 | 1.96 |
| Semantic Version Bumper | powershell | sonnet46-1m-medium | 37 | 46 | 1.2 | 309 | 164 | 1.88 |
| Semantic Version Bumper | powershell | haiku45-200k-na | 0 | 0 | 0.0 | 0 | 711 | 0.00 |
| Semantic Version Bumper | powershell | opus47-1m-high | 24 | 33 | 1.4 | 220 | 429 | 0.51 |
| Semantic Version Bumper | powershell | opus47-1m-medium | 31 | 56 | 1.8 | 243 | 22 | 11.05 |
| Semantic Version Bumper | powershell | opus47-1m-xhigh | 33 | 54 | 1.6 | 396 | 42 | 9.43 |
| Semantic Version Bumper | powershell | opus47-200k-medium | 22 | 37 | 1.7 | 180 | 369 | 0.49 |
| Semantic Version Bumper | powershell | sonnet46-200k-medium | 34 | 40 | 1.2 | 260 | 389 | 0.67 |
| Semantic Version Bumper | powershell | sonnet46-1m-medium | 46 | 54 | 1.2 | 361 | 178 | 2.03 |
| Semantic Version Bumper | typescript-bun | haiku45-200k-na | 31 | 55 | 1.8 | 287 | 690 | 0.42 |
| Semantic Version Bumper | typescript-bun | opus47-1m-high | 35 | 66 | 1.9 | 397 | 487 | 0.82 |
| Semantic Version Bumper | typescript-bun | opus47-1m-medium | 23 | 49 | 2.1 | 279 | 248 | 1.12 |
| Semantic Version Bumper | typescript-bun | opus47-1m-xhigh | 45 | 95 | 2.1 | 805 | 504 | 1.60 |
| Semantic Version Bumper | typescript-bun | opus47-200k-medium | 23 | 50 | 2.2 | 227 | 211 | 1.08 |
| Semantic Version Bumper | typescript-bun | sonnet46-200k-medium | 28 | 38 | 1.4 | 196 | 221 | 0.89 |
| Semantic Version Bumper | typescript-bun | sonnet46-1m-medium | 42 | 51 | 1.2 | 287 | 594 | 0.48 |
| PR Label Assigner | bash | haiku45-200k-na | 13 | 25 | 1.9 | 241 | 381 | 0.63 |
| PR Label Assigner | bash | opus47-1m-high | 26 | 53 | 2.0 | 397 | 194 | 2.05 |
| PR Label Assigner | bash | opus47-1m-medium | 16 | 31 | 1.9 | 201 | 136 | 1.48 |
| PR Label Assigner | bash | opus47-1m-xhigh | 28 | 43 | 1.5 | 303 | 360 | 0.84 |
| PR Label Assigner | bash | opus47-200k-medium | 21 | 33 | 1.6 | 181 | 261 | 0.69 |
| PR Label Assigner | bash | sonnet46-200k-medium | 28 | 43 | 1.5 | 252 | 338 | 0.75 |
| PR Label Assigner | bash | sonnet46-1m-medium | 18 | 25 | 1.4 | 188 | 164 | 1.15 |
| PR Label Assigner | default | haiku45-200k-na | 21 | 28 | 1.3 | 255 | 156 | 1.63 |
| PR Label Assigner | default | opus47-1m-high | 30 | 50 | 1.7 | 470 | 212 | 2.22 |
| PR Label Assigner | default | opus47-1m-medium | 0 | 9 | 0.0 | 194 | 132 | 1.47 |
| PR Label Assigner | default | opus47-1m-xhigh | 27 | 43 | 1.6 | 431 | 224 | 1.92 |
| PR Label Assigner | default | opus47-200k-medium | 14 | 26 | 1.9 | 174 | 110 | 1.58 |
| PR Label Assigner | default | sonnet46-200k-medium | 15 | 17 | 1.1 | 170 | 146 | 1.16 |
| PR Label Assigner | default | sonnet46-1m-medium | 31 | 34 | 1.1 | 230 | 295 | 0.78 |
| PR Label Assigner | powershell | haiku45-200k-na | 10 | 13 | 1.3 | 107 | 142 | 0.75 |
| PR Label Assigner | powershell | opus47-1m-high | 23 | 44 | 1.9 | 215 | 329 | 0.65 |
| PR Label Assigner | powershell | opus47-1m-medium | 22 | 23 | 1.0 | 153 | 229 | 0.67 |
| PR Label Assigner | powershell | opus47-1m-xhigh | 39 | 47 | 1.2 | 319 | 386 | 0.83 |
| PR Label Assigner | powershell | opus47-200k-medium | 27 | 37 | 1.4 | 288 | 14 | 20.57 |
| PR Label Assigner | powershell | sonnet46-200k-medium | 20 | 41 | 2.0 | 176 | 128 | 1.38 |
| PR Label Assigner | powershell | sonnet46-1m-medium | 47 | 53 | 1.1 | 405 | 108 | 3.75 |
| PR Label Assigner | powershell | haiku45-200k-na | 13 | 19 | 1.5 | 189 | 129 | 1.47 |
| PR Label Assigner | powershell | opus47-1m-high | 24 | 35 | 1.5 | 223 | 274 | 0.81 |
| PR Label Assigner | powershell | opus47-1m-medium | 27 | 49 | 1.8 | 315 | 39 | 8.08 |
| PR Label Assigner | powershell | opus47-1m-xhigh | 31 | 62 | 2.0 | 324 | 202 | 1.60 |
| PR Label Assigner | powershell | opus47-200k-medium | 14 | 16 | 1.1 | 111 | 256 | 0.43 |
| PR Label Assigner | powershell | sonnet46-200k-medium | 28 | 55 | 2.0 | 204 | 281 | 0.73 |
| PR Label Assigner | powershell | sonnet46-1m-medium | 25 | 52 | 2.1 | 231 | 211 | 1.09 |
| PR Label Assigner | typescript-bun | haiku45-200k-na | 10 | 17 | 1.7 | 120 | 384 | 0.31 |
| PR Label Assigner | typescript-bun | opus47-1m-high | 27 | 55 | 2.0 | 402 | 257 | 1.56 |
| PR Label Assigner | typescript-bun | opus47-1m-medium | 16 | 35 | 2.2 | 271 | 138 | 1.96 |
| PR Label Assigner | typescript-bun | opus47-1m-xhigh | 32 | 51 | 1.6 | 620 | 263 | 2.36 |
| PR Label Assigner | typescript-bun | opus47-200k-medium | 13 | 29 | 2.2 | 232 | 174 | 1.33 |
| PR Label Assigner | typescript-bun | sonnet46-200k-medium | 29 | 55 | 1.9 | 359 | 144 | 2.49 |
| PR Label Assigner | typescript-bun | sonnet46-1m-medium | 19 | 25 | 1.3 | 157 | 255 | 0.62 |
| Dependency License Checker | bash | haiku45-200k-na | 15 | 31 | 2.1 | 266 | 328 | 0.81 |
| Dependency License Checker | bash | opus47-1m-high | 5 | 7 | 1.4 | 127 | 212 | 0.60 |
| Dependency License Checker | bash | opus47-1m-medium | 10 | 43 | 4.3 | 169 | 174 | 0.97 |
| Dependency License Checker | bash | opus47-1m-xhigh | 14 | 14 | 1.0 | 152 | 171 | 0.89 |
| Dependency License Checker | bash | opus47-200k-medium | 18 | 32 | 1.8 | 156 | 255 | 0.61 |
| Dependency License Checker | bash | sonnet46-200k-medium | 23 | 54 | 2.3 | 262 | 205 | 1.28 |
| Dependency License Checker | bash | sonnet46-1m-medium | 31 | 50 | 1.6 | 315 | 228 | 1.38 |
| Dependency License Checker | default | haiku45-200k-na | 10 | 30 | 3.0 | 200 | 415 | 0.48 |
| Dependency License Checker | default | opus47-1m-high | 18 | 77 | 4.3 | 570 | 354 | 1.61 |
| Dependency License Checker | default | opus47-1m-medium | 21 | 35 | 1.7 | 400 | 166 | 2.41 |
| Dependency License Checker | default | opus47-1m-xhigh | 24 | 36 | 1.5 | 284 | 578 | 0.49 |
| Dependency License Checker | default | opus47-200k-medium | 23 | 43 | 1.9 | 373 | 174 | 2.14 |
| Dependency License Checker | default | sonnet46-200k-medium | 39 | 51 | 1.3 | 587 | 257 | 2.28 |
| Dependency License Checker | default | sonnet46-1m-medium | 36 | 46 | 1.3 | 528 | 221 | 2.39 |
| Dependency License Checker | powershell | haiku45-200k-na | 9 | 23 | 2.6 | 144 | 439 | 0.33 |
| Dependency License Checker | powershell | opus47-1m-high | 13 | 31 | 2.4 | 192 | 312 | 0.62 |
| Dependency License Checker | powershell | opus47-1m-medium | 11 | 24 | 2.2 | 127 | 208 | 0.61 |
| Dependency License Checker | powershell | opus47-1m-xhigh | 22 | 79 | 3.6 | 456 | 277 | 1.65 |
| Dependency License Checker | powershell | opus47-200k-medium | 19 | 31 | 1.6 | 252 | 61 | 4.13 |
| Dependency License Checker | powershell | sonnet46-200k-medium | 21 | 38 | 1.8 | 216 | 257 | 0.84 |
| Dependency License Checker | powershell | sonnet46-1m-medium | 41 | 54 | 1.3 | 380 | 216 | 1.76 |
| Dependency License Checker | powershell | haiku45-200k-na | 5 | 18 | 3.6 | 188 | 172 | 1.09 |
| Dependency License Checker | powershell | opus47-1m-high | 48 | 82 | 1.7 | 492 | 28 | 17.57 |
| Dependency License Checker | powershell | opus47-1m-medium | 11 | 23 | 2.1 | 116 | 250 | 0.46 |
| Dependency License Checker | powershell | opus47-1m-xhigh | 19 | 32 | 1.7 | 223 | 440 | 0.51 |
| Dependency License Checker | powershell | opus47-200k-medium | 18 | 56 | 3.1 | 286 | 30 | 9.53 |
| Dependency License Checker | powershell | sonnet46-200k-medium | 24 | 27 | 1.1 | 243 | 213 | 1.14 |
| Dependency License Checker | powershell | sonnet46-1m-medium | 42 | 55 | 1.3 | 360 | 181 | 1.99 |
| Dependency License Checker | typescript-bun | haiku45-200k-na | 9 | 24 | 2.7 | 201 | 272 | 0.74 |
| Dependency License Checker | typescript-bun | opus47-1m-high | 29 | 59 | 2.0 | 605 | 279 | 2.17 |
| Dependency License Checker | typescript-bun | opus47-1m-medium | 16 | 32 | 2.0 | 343 | 166 | 2.07 |
| Dependency License Checker | typescript-bun | opus47-1m-xhigh | 29 | 50 | 1.7 | 402 | 559 | 0.72 |
| Dependency License Checker | typescript-bun | opus47-200k-medium | 12 | 23 | 1.9 | 141 | 460 | 0.31 |
| Dependency License Checker | typescript-bun | sonnet46-200k-medium | 28 | 55 | 2.0 | 345 | 221 | 1.56 |
| Dependency License Checker | typescript-bun | sonnet46-1m-medium | 34 | 58 | 1.7 | 350 | 173 | 2.02 |
| Test Results Aggregator | bash | haiku45-200k-na | 19 | 17 | 0.9 | 304 | 462 | 0.66 |
| Test Results Aggregator | bash | opus47-1m-high | 26 | 52 | 2.0 | 200 | 515 | 0.39 |
| Test Results Aggregator | bash | opus47-1m-medium | 11 | 46 | 4.2 | 237 | 189 | 1.25 |
| Test Results Aggregator | bash | opus47-1m-xhigh | 37 | 95 | 2.6 | 385 | 101 | 3.81 |
| Test Results Aggregator | bash | opus47-200k-medium | 22 | 45 | 2.0 | 245 | 161 | 1.52 |
| Test Results Aggregator | bash | sonnet46-200k-medium | 16 | 47 | 2.9 | 213 | 209 | 1.02 |
| Test Results Aggregator | bash | sonnet46-1m-medium | 18 | 40 | 2.2 | 186 | 396 | 0.47 |
| Test Results Aggregator | default | haiku45-200k-na | 11 | 47 | 4.3 | 437 | 98 | 4.46 |
| Test Results Aggregator | default | opus47-1m-high | 27 | 62 | 2.3 | 444 | 672 | 0.66 |
| Test Results Aggregator | default | opus47-1m-medium | 19 | 43 | 2.3 | 353 | 185 | 1.91 |
| Test Results Aggregator | default | opus47-1m-xhigh | 30 | 70 | 2.3 | 543 | 334 | 1.63 |
| Test Results Aggregator | default | opus47-200k-medium | 21 | 44 | 2.1 | 427 | 268 | 1.59 |
| Test Results Aggregator | default | sonnet46-200k-medium | 50 | 55 | 1.1 | 587 | 264 | 2.22 |
| Test Results Aggregator | default | sonnet46-1m-medium | 8 | 29 | 3.6 | 337 | 382 | 0.88 |
| Test Results Aggregator | powershell | haiku45-200k-na | 6 | 9 | 1.5 | 71 | 422 | 0.17 |
| Test Results Aggregator | powershell | opus47-1m-high | 16 | 35 | 2.2 | 169 | 354 | 0.48 |
| Test Results Aggregator | powershell | opus47-1m-medium | 17 | 46 | 2.7 | 294 | 21 | 14.00 |
| Test Results Aggregator | powershell | opus47-1m-xhigh | 27 | 73 | 2.7 | 343 | 372 | 0.92 |
| Test Results Aggregator | powershell | opus47-200k-medium | 22 | 59 | 2.7 | 309 | 19 | 16.26 |
| Test Results Aggregator | powershell | sonnet46-200k-medium | 48 | 54 | 1.1 | 290 | 285 | 1.02 |
| Test Results Aggregator | powershell | sonnet46-1m-medium | 20 | 20 | 1.0 | 154 | 211 | 0.73 |
| Test Results Aggregator | powershell | haiku45-200k-na | 0 | 0 | 0.0 | 0 | 359 | 0.00 |
| Test Results Aggregator | powershell | opus47-1m-high | 38 | 63 | 1.7 | 292 | 620 | 0.47 |
| Test Results Aggregator | powershell | opus47-1m-medium | 20 | 45 | 2.2 | 202 | 179 | 1.13 |
| Test Results Aggregator | powershell | opus47-1m-xhigh | 37 | 65 | 1.8 | 337 | 265 | 1.27 |
| Test Results Aggregator | powershell | opus47-200k-medium | 24 | 43 | 1.8 | 191 | 271 | 0.70 |
| Test Results Aggregator | powershell | sonnet46-200k-medium | 46 | 56 | 1.2 | 312 | 408 | 0.76 |
| Test Results Aggregator | powershell | sonnet46-1m-medium | 44 | 61 | 1.4 | 362 | 483 | 0.75 |
| Test Results Aggregator | typescript-bun | haiku45-200k-na | 25 | 80 | 3.2 | 521 | 555 | 0.94 |
| Test Results Aggregator | typescript-bun | opus47-1m-high | 26 | 72 | 2.8 | 529 | 537 | 0.99 |
| Test Results Aggregator | typescript-bun | opus47-1m-medium | 17 | 42 | 2.5 | 379 | 244 | 1.55 |
| Test Results Aggregator | typescript-bun | opus47-1m-xhigh | 33 | 88 | 2.7 | 658 | 481 | 1.37 |
| Test Results Aggregator | typescript-bun | opus47-200k-medium | 14 | 43 | 3.1 | 220 | 429 | 0.51 |
| Test Results Aggregator | typescript-bun | sonnet46-200k-medium | 36 | 102 | 2.8 | 588 | 388 | 1.52 |
| Test Results Aggregator | typescript-bun | sonnet46-1m-medium | 36 | 53 | 1.5 | 386 | 368 | 1.05 |
| Environment Matrix Generator | bash | haiku45-200k-na | 12 | 13 | 1.1 | 131 | 104 | 1.26 |
| Environment Matrix Generator | bash | opus47-1m-high | 34 | 55 | 1.6 | 341 | 186 | 1.83 |
| Environment Matrix Generator | bash | opus47-1m-medium | 19 | 38 | 2.0 | 221 | 90 | 2.46 |
| Environment Matrix Generator | bash | opus47-1m-xhigh | 27 | 30 | 1.1 | 186 | 304 | 0.61 |
| Environment Matrix Generator | bash | opus47-200k-medium | 6 | 14 | 2.3 | 171 | 97 | 1.76 |
| Environment Matrix Generator | bash | sonnet46-200k-medium | 0 | 0 | 0.0 | 0 | 0 | 0.00 |
| Environment Matrix Generator | bash | sonnet46-1m-medium | 26 | 58 | 2.2 | 288 | 84 | 3.43 |
| Environment Matrix Generator | default | haiku45-200k-na | 23 | 36 | 1.6 | 350 | 304 | 1.15 |
| Environment Matrix Generator | default | opus47-1m-high | 29 | 48 | 1.7 | 451 | 226 | 2.00 |
| Environment Matrix Generator | default | opus47-1m-medium | 20 | 27 | 1.4 | 281 | 337 | 0.83 |
| Environment Matrix Generator | default | opus47-1m-xhigh | 23 | 35 | 1.5 | 283 | 202 | 1.40 |
| Environment Matrix Generator | default | opus47-200k-medium | 14 | 35 | 2.5 | 241 | 129 | 1.87 |
| Environment Matrix Generator | default | sonnet46-200k-medium | 14 | 29 | 2.1 | 250 | 134 | 1.87 |
| Environment Matrix Generator | default | sonnet46-1m-medium | 33 | 26 | 0.8 | 303 | 130 | 2.33 |
| Environment Matrix Generator | powershell | haiku45-200k-na | 0 | 0 | 0.0 | 0 | 497 | 0.00 |
| Environment Matrix Generator | powershell | opus47-1m-high | 32 | 54 | 1.7 | 346 | 188 | 1.84 |
| Environment Matrix Generator | powershell | opus47-1m-medium | 24 | 49 | 2.0 | 252 | 267 | 0.94 |
| Environment Matrix Generator | powershell | opus47-1m-xhigh | 39 | 54 | 1.4 | 334 | 411 | 0.81 |
| Environment Matrix Generator | powershell | opus47-200k-medium | 22 | 53 | 2.4 | 306 | 19 | 16.11 |
| Environment Matrix Generator | powershell | sonnet46-200k-medium | 15 | 26 | 1.7 | 198 | 82 | 2.41 |
| Environment Matrix Generator | powershell | sonnet46-1m-medium | 20 | 33 | 1.6 | 234 | 123 | 1.90 |
| Environment Matrix Generator | powershell | haiku45-200k-na | 18 | 33 | 1.8 | 270 | 297 | 0.91 |
| Environment Matrix Generator | powershell | opus47-1m-high | 17 | 26 | 1.5 | 188 | 206 | 0.91 |
| Environment Matrix Generator | powershell | opus47-1m-medium | 11 | 18 | 1.6 | 129 | 150 | 0.86 |
| Environment Matrix Generator | powershell | opus47-1m-xhigh | 42 | 59 | 1.4 | 294 | 437 | 0.67 |
| Environment Matrix Generator | powershell | opus47-200k-medium | 36 | 50 | 1.4 | 322 | 211 | 1.53 |
| Environment Matrix Generator | powershell | sonnet46-200k-medium | 24 | 31 | 1.3 | 152 | 214 | 0.71 |
| Environment Matrix Generator | powershell | sonnet46-1m-medium | 23 | 36 | 1.6 | 284 | 323 | 0.88 |
| Environment Matrix Generator | typescript-bun | haiku45-200k-na | 20 | 48 | 2.4 | 368 | 297 | 1.24 |
| Environment Matrix Generator | typescript-bun | opus47-1m-high | 29 | 57 | 2.0 | 410 | 210 | 1.95 |
| Environment Matrix Generator | typescript-bun | opus47-1m-medium | 13 | 38 | 2.9 | 238 | 145 | 1.64 |
| Environment Matrix Generator | typescript-bun | opus47-1m-xhigh | 31 | 59 | 1.9 | 622 | 305 | 2.04 |
| Environment Matrix Generator | typescript-bun | opus47-200k-medium | 14 | 32 | 2.3 | 250 | 177 | 1.41 |
| Environment Matrix Generator | typescript-bun | sonnet46-200k-medium | 35 | 60 | 1.7 | 416 | 182 | 2.29 |
| Environment Matrix Generator | typescript-bun | sonnet46-1m-medium | 24 | 55 | 2.3 | 275 | 269 | 1.02 |
| Artifact Cleanup Script | bash | haiku45-200k-na | 10 | 19 | 1.9 | 260 | 249 | 1.04 |
| Artifact Cleanup Script | bash | opus47-1m-high | 23 | 41 | 1.8 | 225 | 461 | 0.49 |
| Artifact Cleanup Script | bash | opus47-1m-medium | 16 | 36 | 2.2 | 223 | 199 | 1.12 |
| Artifact Cleanup Script | bash | opus47-1m-xhigh | 15 | 63 | 4.2 | 183 | 398 | 0.46 |
| Artifact Cleanup Script | bash | opus47-200k-medium | 11 | 48 | 4.4 | 157 | 310 | 0.51 |
| Artifact Cleanup Script | bash | sonnet46-200k-medium | 13 | 39 | 3.0 | 191 | 221 | 0.86 |
| Artifact Cleanup Script | bash | sonnet46-1m-medium | 17 | 61 | 3.6 | 358 | 176 | 2.03 |
| Artifact Cleanup Script | default | haiku45-200k-na | 11 | 27 | 2.5 | 352 | 606 | 0.58 |
| Artifact Cleanup Script | default | opus47-1m-high | 14 | 28 | 2.0 | 223 | 491 | 0.45 |
| Artifact Cleanup Script | default | opus47-1m-medium | 16 | 37 | 2.3 | 293 | 196 | 1.49 |
| Artifact Cleanup Script | default | opus47-1m-xhigh | 18 | 39 | 2.2 | 525 | 321 | 1.64 |
| Artifact Cleanup Script | default | opus47-200k-medium | 16 | 48 | 3.0 | 431 | 196 | 2.20 |
| Artifact Cleanup Script | default | sonnet46-200k-medium | 22 | 52 | 2.4 | 308 | 487 | 0.63 |
| Artifact Cleanup Script | default | sonnet46-1m-medium | 26 | 35 | 1.3 | 266 | 563 | 0.47 |
| Artifact Cleanup Script | powershell | haiku45-200k-na | 0 | 0 | 0.0 | 0 | 335 | 0.00 |
| Artifact Cleanup Script | powershell | opus47-1m-high | 22 | 84 | 3.8 | 440 | 115 | 3.83 |
| Artifact Cleanup Script | powershell | opus47-1m-medium | 9 | 18 | 2.0 | 133 | 166 | 0.80 |
| Artifact Cleanup Script | powershell | opus47-1m-xhigh | 19 | 44 | 2.3 | 267 | 374 | 0.71 |
| Artifact Cleanup Script | powershell | opus47-200k-medium | 16 | 47 | 2.9 | 277 | 234 | 1.18 |
| Artifact Cleanup Script | powershell | sonnet46-200k-medium | 29 | 46 | 1.6 | 298 | 258 | 1.16 |
| Artifact Cleanup Script | powershell | sonnet46-1m-medium | 28 | 48 | 1.7 | 373 | 214 | 1.74 |
| Artifact Cleanup Script | powershell | haiku45-200k-na | 8 | 18 | 2.2 | 134 | 173 | 0.77 |
| Artifact Cleanup Script | powershell | opus47-1m-high | 22 | 51 | 2.3 | 291 | 366 | 0.80 |
| Artifact Cleanup Script | powershell | opus47-1m-medium | 8 | 25 | 3.1 | 135 | 186 | 0.73 |
| Artifact Cleanup Script | powershell | opus47-1m-xhigh | 17 | 35 | 2.1 | 205 | 373 | 0.55 |
| Artifact Cleanup Script | powershell | opus47-200k-medium | 12 | 28 | 2.3 | 144 | 166 | 0.87 |
| Artifact Cleanup Script | powershell | sonnet46-200k-medium | 12 | 21 | 1.8 | 158 | 185 | 0.85 |
| Artifact Cleanup Script | powershell | sonnet46-1m-medium | 13 | 33 | 2.5 | 224 | 131 | 1.71 |
| Artifact Cleanup Script | typescript-bun | haiku45-200k-na | 6 | 17 | 2.8 | 172 | 262 | 0.66 |
| Artifact Cleanup Script | typescript-bun | opus47-1m-high | 27 | 66 | 2.4 | 570 | 384 | 1.48 |
| Artifact Cleanup Script | typescript-bun | opus47-1m-medium | 21 | 56 | 2.7 | 271 | 334 | 0.81 |
| Artifact Cleanup Script | typescript-bun | opus47-1m-xhigh | 18 | 40 | 2.2 | 459 | 271 | 1.69 |
| Artifact Cleanup Script | typescript-bun | opus47-200k-medium | 13 | 40 | 3.1 | 307 | 207 | 1.48 |
| Artifact Cleanup Script | typescript-bun | sonnet46-200k-medium | 14 | 25 | 1.8 | 233 | 371 | 0.63 |
| Artifact Cleanup Script | typescript-bun | sonnet46-1m-medium | 30 | 67 | 2.2 | 395 | 400 | 0.99 |
| Secret Rotation Validator | bash | haiku45-200k-na | 19 | 31 | 1.6 | 234 | 185 | 1.26 |
| Secret Rotation Validator | bash | opus47-1m-high | 29 | 77 | 2.7 | 337 | 211 | 1.60 |
| Secret Rotation Validator | bash | opus47-1m-medium | 5 | 21 | 4.2 | 120 | 209 | 0.57 |
| Secret Rotation Validator | bash | opus47-1m-xhigh | 25 | 19 | 0.8 | 258 | 280 | 0.92 |
| Secret Rotation Validator | bash | opus47-200k-medium | 14 | 16 | 1.1 | 171 | 140 | 1.22 |
| Secret Rotation Validator | bash | sonnet46-200k-medium | 22 | 29 | 1.3 | 216 | 421 | 0.51 |
| Secret Rotation Validator | bash | sonnet46-1m-medium | 24 | 53 | 2.2 | 244 | 490 | 0.50 |
| Secret Rotation Validator | default | haiku45-200k-na | 14 | 29 | 2.1 | 198 | 272 | 0.73 |
| Secret Rotation Validator | default | opus47-1m-high | 20 | 40 | 2.0 | 271 | 425 | 0.64 |
| Secret Rotation Validator | default | opus47-1m-medium | 21 | 43 | 2.0 | 397 | 244 | 1.63 |
| Secret Rotation Validator | default | opus47-1m-xhigh | 16 | 61 | 3.8 | 645 | 330 | 1.95 |
| Secret Rotation Validator | default | opus47-200k-medium | 21 | 50 | 2.4 | 454 | 283 | 1.60 |
| Secret Rotation Validator | default | sonnet46-200k-medium | 27 | 61 | 2.3 | 541 | 242 | 2.24 |
| Secret Rotation Validator | default | sonnet46-1m-medium | 38 | 48 | 1.3 | 327 | 399 | 0.82 |
| Secret Rotation Validator | powershell | haiku45-200k-na | 12 | 24 | 2.0 | 151 | 215 | 0.70 |
| Secret Rotation Validator | powershell | opus47-1m-high | 18 | 38 | 2.1 | 223 | 275 | 0.81 |
| Secret Rotation Validator | powershell | opus47-1m-medium | 21 | 46 | 2.2 | 184 | 225 | 0.82 |
| Secret Rotation Validator | powershell | opus47-1m-xhigh | 24 | 54 | 2.2 | 315 | 326 | 0.97 |
| Secret Rotation Validator | powershell | opus47-200k-medium | 19 | 42 | 2.2 | 159 | 250 | 0.64 |
| Secret Rotation Validator | powershell | sonnet46-200k-medium | 16 | 25 | 1.6 | 182 | 201 | 0.91 |
| Secret Rotation Validator | powershell | sonnet46-1m-medium | 32 | 56 | 1.8 | 341 | 211 | 1.62 |
| Secret Rotation Validator | powershell | haiku45-200k-na | 8 | 16 | 2.0 | 154 | 505 | 0.30 |
| Secret Rotation Validator | powershell | opus47-1m-high | 19 | 46 | 2.4 | 235 | 215 | 1.09 |
| Secret Rotation Validator | powershell | opus47-1m-medium | 24 | 68 | 2.8 | 310 | 159 | 1.95 |
| Secret Rotation Validator | powershell | opus47-1m-xhigh | 26 | 69 | 2.7 | 468 | 49 | 9.55 |
| Secret Rotation Validator | powershell | opus47-200k-medium | 12 | 29 | 2.4 | 154 | 323 | 0.48 |
| Secret Rotation Validator | powershell | sonnet46-200k-medium | 54 | 66 | 1.2 | 422 | 245 | 1.72 |
| Secret Rotation Validator | powershell | sonnet46-1m-medium | 26 | 32 | 1.2 | 255 | 198 | 1.29 |
| Secret Rotation Validator | typescript-bun | haiku45-200k-na | 20 | 42 | 2.1 | 270 | 249 | 1.08 |
| Secret Rotation Validator | typescript-bun | opus47-1m-high | 20 | 52 | 2.6 | 421 | 305 | 1.38 |
| Secret Rotation Validator | typescript-bun | opus47-1m-medium | 20 | 42 | 2.1 | 349 | 213 | 1.64 |
| Secret Rotation Validator | typescript-bun | opus47-1m-xhigh | 27 | 76 | 2.8 | 820 | 354 | 2.32 |
| Secret Rotation Validator | typescript-bun | opus47-200k-medium | 16 | 48 | 3.0 | 217 | 628 | 0.35 |
| Secret Rotation Validator | typescript-bun | sonnet46-200k-medium | 21 | 48 | 2.3 | 232 | 432 | 0.54 |
| Secret Rotation Validator | typescript-bun | sonnet46-1m-medium | 36 | 67 | 1.9 | 378 | 288 | 1.31 |

</details>

### LLM-as-Judge Scores

An LLM evaluates each test suite on four dimensions (1-5 scale):

- **Coverage** (1-5): Do tests exercise the key requirements? 1 = most untested, 5 = all covered.
- **Rigor** (1-5): Edge cases, error handling, boundary conditions? 1 = happy path only, 5 = thorough.
- **Design** (1-5): Test organization, fixtures, readability? 1 = messy/brittle, 5 = well-structured.
- **Overall** (1-5): Holistic quality — would you trust this suite to catch regressions? 1 = no, 5 = absolutely. Use this as the primary ranking metric.

| Language | Model | Avg Overall | Avg Coverage | Avg Rigor | Avg Design | Judge Cost |
|------|-------|-------------|-------------|-----------|------------|------------|
| bash | haiku45-200k-na | **2.3** | 3.1 | 2.3 | 2.9 | $0.4059 |
| bash | opus47-1m-high | **3.5** | 3.8 | 3.4 | 3.9 | $0.4673 |
| bash | opus47-1m-medium | **3.2** | 3.5 | 2.8 | 3.6 | $0.3898 |
| bash | opus47-1m-xhigh | **3.7** | 3.9 | 3.6 | 4.1 | $0.4523 |
| bash | opus47-200k-medium | **3.2** | 3.6 | 3.2 | 3.3 | $0.3447 |
| bash | sonnet46-1m-medium | **3.4** | 3.9 | 3.3 | 3.9 | $0.4322 |
| bash | sonnet46-200k-medium | **3.2** | 3.6 | 3.2 | 3.8 | $0.3385 |
| default | haiku45-200k-na | **2.1** | 2.8 | 2.4 | 3.2 | $0.3524 |
| default | opus47-1m-high | **4.2** | 4.4 | 4.1 | 4.4 | $0.4466 |
| default | opus47-1m-medium | **3.4** | 3.7 | 3.2 | 3.8 | $0.4134 |
| default | opus47-1m-xhigh | **4.0** | 4.3 | 4.1 | 4.4 | $0.5308 |
| default | opus47-200k-medium | **3.8** | 4.1 | 3.5 | 4.1 | $0.3469 |
| default | sonnet46-1m-medium | **3.3** | 3.5 | 3.1 | 3.9 | $0.4653 |
| default | sonnet46-200k-medium | **3.6** | 4.1 | 3.8 | 4.1 | $0.4675 |
| powershell | haiku45-200k-na | **2.3** | 2.7 | 2.2 | 2.9 | $0.4179 |
| powershell | opus47-1m-high | **4.2** | 4.4 | 4.0 | 4.3 | $0.8964 |
| powershell | opus47-1m-medium | **3.9** | 4.3 | 3.9 | 4.1 | $0.7870 |
| powershell | opus47-1m-xhigh | **4.0** | 4.2 | 3.9 | 4.2 | $1.0066 |
| powershell | opus47-200k-medium | **3.8** | 4.2 | 3.8 | 4.0 | $0.8618 |
| powershell | sonnet46-1m-medium | **3.5** | 4.0 | 3.5 | 4.0 | $0.8736 |
| powershell | sonnet46-200k-medium | **3.5** | 3.6 | 3.3 | 4.0 | $0.8403 |
| typescript-bun | haiku45-200k-na | **2.1** | 2.6 | 2.1 | 3.1 | $0.4090 |
| typescript-bun | opus47-1m-high | **4.1** | 4.2 | 3.8 | 4.3 | $0.5363 |
| typescript-bun | opus47-1m-medium | **3.8** | 4.1 | 3.8 | 3.9 | $0.4228 |
| typescript-bun | opus47-1m-xhigh | **4.5** | 4.6 | 4.2 | 4.5 | $0.5838 |
| typescript-bun | opus47-200k-medium | **3.8** | 4.0 | 3.7 | 4.0 | $0.4318 |
| typescript-bun | sonnet46-1m-medium | **3.6** | 3.9 | 3.5 | 4.1 | $0.4408 |
| typescript-bun | sonnet46-200k-medium | **3.2** | 3.5 | 3.4 | 3.8 | $0.4464 |
| **Total** | | | | | | **$14.8081** |


<details>
<summary>Sorted by avg overall (highest first)</summary>

| Language | Model | Avg Overall | Avg Coverage | Avg Rigor | Avg Design | Judge Cost |
|------|-------|-------------|-------------|-----------|------------|------------|
| typescript-bun | opus47-1m-xhigh | **4.5** | 4.6 | 4.2 | 4.5 | $0.5838 |
| powershell | opus47-1m-high | **4.2** | 4.4 | 4.0 | 4.3 | $0.8964 |
| default | opus47-1m-high | **4.2** | 4.4 | 4.1 | 4.4 | $0.4466 |
| typescript-bun | opus47-1m-high | **4.1** | 4.2 | 3.8 | 4.3 | $0.5363 |
| powershell | opus47-1m-xhigh | **4.0** | 4.2 | 3.9 | 4.2 | $1.0066 |
| default | opus47-1m-xhigh | **4.0** | 4.3 | 4.1 | 4.4 | $0.5308 |
| powershell | opus47-1m-medium | **3.9** | 4.3 | 3.9 | 4.1 | $0.7870 |
| default | opus47-200k-medium | **3.8** | 4.1 | 3.5 | 4.1 | $0.3469 |
| powershell | opus47-200k-medium | **3.8** | 4.2 | 3.8 | 4.0 | $0.8618 |
| typescript-bun | opus47-1m-medium | **3.8** | 4.1 | 3.8 | 3.9 | $0.4228 |
| typescript-bun | opus47-200k-medium | **3.8** | 4.0 | 3.7 | 4.0 | $0.4318 |
| bash | opus47-1m-xhigh | **3.7** | 3.9 | 3.6 | 4.1 | $0.4523 |
| default | sonnet46-200k-medium | **3.6** | 4.1 | 3.8 | 4.1 | $0.4675 |
| typescript-bun | sonnet46-1m-medium | **3.6** | 3.9 | 3.5 | 4.1 | $0.4408 |
| bash | opus47-1m-high | **3.5** | 3.8 | 3.4 | 3.9 | $0.4673 |
| powershell | sonnet46-1m-medium | **3.5** | 4.0 | 3.5 | 4.0 | $0.8736 |
| powershell | sonnet46-200k-medium | **3.5** | 3.6 | 3.3 | 4.0 | $0.8403 |
| bash | sonnet46-1m-medium | **3.4** | 3.9 | 3.3 | 3.9 | $0.4322 |
| default | opus47-1m-medium | **3.4** | 3.7 | 3.2 | 3.8 | $0.4134 |
| default | sonnet46-1m-medium | **3.3** | 3.5 | 3.1 | 3.9 | $0.4653 |
| bash | sonnet46-200k-medium | **3.2** | 3.6 | 3.2 | 3.8 | $0.3385 |
| bash | opus47-1m-medium | **3.2** | 3.5 | 2.8 | 3.6 | $0.3898 |
| bash | opus47-200k-medium | **3.2** | 3.6 | 3.2 | 3.3 | $0.3447 |
| typescript-bun | sonnet46-200k-medium | **3.2** | 3.5 | 3.4 | 3.8 | $0.4464 |
| powershell | haiku45-200k-na | **2.3** | 2.7 | 2.2 | 2.9 | $0.4179 |
| bash | haiku45-200k-na | **2.3** | 3.1 | 2.3 | 2.9 | $0.4059 |
| typescript-bun | haiku45-200k-na | **2.1** | 2.6 | 2.1 | 3.1 | $0.4090 |
| default | haiku45-200k-na | **2.1** | 2.8 | 2.4 | 3.2 | $0.3524 |

</details>

<details>
<summary>Sorted by avg coverage (highest first)</summary>

| Language | Model | Avg Overall | Avg Coverage | Avg Rigor | Avg Design | Judge Cost |
|------|-------|-------------|-------------|-----------|------------|------------|
| typescript-bun | opus47-1m-xhigh | **4.5** | 4.6 | 4.2 | 4.5 | $0.5838 |
| default | opus47-1m-high | **4.2** | 4.4 | 4.1 | 4.4 | $0.4466 |
| powershell | opus47-1m-high | **4.2** | 4.4 | 4.0 | 4.3 | $0.8964 |
| default | opus47-1m-xhigh | **4.0** | 4.3 | 4.1 | 4.4 | $0.5308 |
| powershell | opus47-1m-medium | **3.9** | 4.3 | 3.9 | 4.1 | $0.7870 |
| powershell | opus47-1m-xhigh | **4.0** | 4.2 | 3.9 | 4.2 | $1.0066 |
| powershell | opus47-200k-medium | **3.8** | 4.2 | 3.8 | 4.0 | $0.8618 |
| typescript-bun | opus47-1m-high | **4.1** | 4.2 | 3.8 | 4.3 | $0.5363 |
| default | opus47-200k-medium | **3.8** | 4.1 | 3.5 | 4.1 | $0.3469 |
| default | sonnet46-200k-medium | **3.6** | 4.1 | 3.8 | 4.1 | $0.4675 |
| typescript-bun | opus47-1m-medium | **3.8** | 4.1 | 3.8 | 3.9 | $0.4228 |
| typescript-bun | opus47-200k-medium | **3.8** | 4.0 | 3.7 | 4.0 | $0.4318 |
| powershell | sonnet46-1m-medium | **3.5** | 4.0 | 3.5 | 4.0 | $0.8736 |
| typescript-bun | sonnet46-1m-medium | **3.6** | 3.9 | 3.5 | 4.1 | $0.4408 |
| bash | opus47-1m-xhigh | **3.7** | 3.9 | 3.6 | 4.1 | $0.4523 |
| bash | sonnet46-1m-medium | **3.4** | 3.9 | 3.3 | 3.9 | $0.4322 |
| bash | opus47-1m-high | **3.5** | 3.8 | 3.4 | 3.9 | $0.4673 |
| default | opus47-1m-medium | **3.4** | 3.7 | 3.2 | 3.8 | $0.4134 |
| bash | opus47-200k-medium | **3.2** | 3.6 | 3.2 | 3.3 | $0.3447 |
| powershell | sonnet46-200k-medium | **3.5** | 3.6 | 3.3 | 4.0 | $0.8403 |
| bash | sonnet46-200k-medium | **3.2** | 3.6 | 3.2 | 3.8 | $0.3385 |
| bash | opus47-1m-medium | **3.2** | 3.5 | 2.8 | 3.6 | $0.3898 |
| default | sonnet46-1m-medium | **3.3** | 3.5 | 3.1 | 3.9 | $0.4653 |
| typescript-bun | sonnet46-200k-medium | **3.2** | 3.5 | 3.4 | 3.8 | $0.4464 |
| bash | haiku45-200k-na | **2.3** | 3.1 | 2.3 | 2.9 | $0.4059 |
| default | haiku45-200k-na | **2.1** | 2.8 | 2.4 | 3.2 | $0.3524 |
| powershell | haiku45-200k-na | **2.3** | 2.7 | 2.2 | 2.9 | $0.4179 |
| typescript-bun | haiku45-200k-na | **2.1** | 2.6 | 2.1 | 3.1 | $0.4090 |

</details>

<details>
<summary>Sorted by avg rigor (highest first)</summary>

| Language | Model | Avg Overall | Avg Coverage | Avg Rigor | Avg Design | Judge Cost |
|------|-------|-------------|-------------|-----------|------------|------------|
| typescript-bun | opus47-1m-xhigh | **4.5** | 4.6 | 4.2 | 4.5 | $0.5838 |
| default | opus47-1m-high | **4.2** | 4.4 | 4.1 | 4.4 | $0.4466 |
| default | opus47-1m-xhigh | **4.0** | 4.3 | 4.1 | 4.4 | $0.5308 |
| powershell | opus47-1m-high | **4.2** | 4.4 | 4.0 | 4.3 | $0.8964 |
| powershell | opus47-1m-medium | **3.9** | 4.3 | 3.9 | 4.1 | $0.7870 |
| powershell | opus47-1m-xhigh | **4.0** | 4.2 | 3.9 | 4.2 | $1.0066 |
| default | sonnet46-200k-medium | **3.6** | 4.1 | 3.8 | 4.1 | $0.4675 |
| powershell | opus47-200k-medium | **3.8** | 4.2 | 3.8 | 4.0 | $0.8618 |
| typescript-bun | opus47-1m-high | **4.1** | 4.2 | 3.8 | 4.3 | $0.5363 |
| typescript-bun | opus47-1m-medium | **3.8** | 4.1 | 3.8 | 3.9 | $0.4228 |
| typescript-bun | opus47-200k-medium | **3.8** | 4.0 | 3.7 | 4.0 | $0.4318 |
| bash | opus47-1m-xhigh | **3.7** | 3.9 | 3.6 | 4.1 | $0.4523 |
| powershell | sonnet46-1m-medium | **3.5** | 4.0 | 3.5 | 4.0 | $0.8736 |
| default | opus47-200k-medium | **3.8** | 4.1 | 3.5 | 4.1 | $0.3469 |
| typescript-bun | sonnet46-1m-medium | **3.6** | 3.9 | 3.5 | 4.1 | $0.4408 |
| bash | opus47-1m-high | **3.5** | 3.8 | 3.4 | 3.9 | $0.4673 |
| typescript-bun | sonnet46-200k-medium | **3.2** | 3.5 | 3.4 | 3.8 | $0.4464 |
| powershell | sonnet46-200k-medium | **3.5** | 3.6 | 3.3 | 4.0 | $0.8403 |
| bash | sonnet46-1m-medium | **3.4** | 3.9 | 3.3 | 3.9 | $0.4322 |
| bash | sonnet46-200k-medium | **3.2** | 3.6 | 3.2 | 3.8 | $0.3385 |
| bash | opus47-200k-medium | **3.2** | 3.6 | 3.2 | 3.3 | $0.3447 |
| default | opus47-1m-medium | **3.4** | 3.7 | 3.2 | 3.8 | $0.4134 |
| default | sonnet46-1m-medium | **3.3** | 3.5 | 3.1 | 3.9 | $0.4653 |
| bash | opus47-1m-medium | **3.2** | 3.5 | 2.8 | 3.6 | $0.3898 |
| default | haiku45-200k-na | **2.1** | 2.8 | 2.4 | 3.2 | $0.3524 |
| bash | haiku45-200k-na | **2.3** | 3.1 | 2.3 | 2.9 | $0.4059 |
| powershell | haiku45-200k-na | **2.3** | 2.7 | 2.2 | 2.9 | $0.4179 |
| typescript-bun | haiku45-200k-na | **2.1** | 2.6 | 2.1 | 3.1 | $0.4090 |

</details>

<details>
<summary>Sorted by avg design (highest first)</summary>

| Language | Model | Avg Overall | Avg Coverage | Avg Rigor | Avg Design | Judge Cost |
|------|-------|-------------|-------------|-----------|------------|------------|
| typescript-bun | opus47-1m-xhigh | **4.5** | 4.6 | 4.2 | 4.5 | $0.5838 |
| default | opus47-1m-high | **4.2** | 4.4 | 4.1 | 4.4 | $0.4466 |
| default | opus47-1m-xhigh | **4.0** | 4.3 | 4.1 | 4.4 | $0.5308 |
| powershell | opus47-1m-high | **4.2** | 4.4 | 4.0 | 4.3 | $0.8964 |
| typescript-bun | opus47-1m-high | **4.1** | 4.2 | 3.8 | 4.3 | $0.5363 |
| powershell | opus47-1m-xhigh | **4.0** | 4.2 | 3.9 | 4.2 | $1.0066 |
| bash | opus47-1m-xhigh | **3.7** | 3.9 | 3.6 | 4.1 | $0.4523 |
| typescript-bun | sonnet46-1m-medium | **3.6** | 3.9 | 3.5 | 4.1 | $0.4408 |
| default | opus47-200k-medium | **3.8** | 4.1 | 3.5 | 4.1 | $0.3469 |
| default | sonnet46-200k-medium | **3.6** | 4.1 | 3.8 | 4.1 | $0.4675 |
| powershell | opus47-1m-medium | **3.9** | 4.3 | 3.9 | 4.1 | $0.7870 |
| powershell | opus47-200k-medium | **3.8** | 4.2 | 3.8 | 4.0 | $0.8618 |
| powershell | sonnet46-1m-medium | **3.5** | 4.0 | 3.5 | 4.0 | $0.8736 |
| powershell | sonnet46-200k-medium | **3.5** | 3.6 | 3.3 | 4.0 | $0.8403 |
| typescript-bun | opus47-200k-medium | **3.8** | 4.0 | 3.7 | 4.0 | $0.4318 |
| default | sonnet46-1m-medium | **3.3** | 3.5 | 3.1 | 3.9 | $0.4653 |
| typescript-bun | opus47-1m-medium | **3.8** | 4.1 | 3.8 | 3.9 | $0.4228 |
| bash | opus47-1m-high | **3.5** | 3.8 | 3.4 | 3.9 | $0.4673 |
| bash | sonnet46-1m-medium | **3.4** | 3.9 | 3.3 | 3.9 | $0.4322 |
| default | opus47-1m-medium | **3.4** | 3.7 | 3.2 | 3.8 | $0.4134 |
| typescript-bun | sonnet46-200k-medium | **3.2** | 3.5 | 3.4 | 3.8 | $0.4464 |
| bash | sonnet46-200k-medium | **3.2** | 3.6 | 3.2 | 3.8 | $0.3385 |
| bash | opus47-1m-medium | **3.2** | 3.5 | 2.8 | 3.6 | $0.3898 |
| bash | opus47-200k-medium | **3.2** | 3.6 | 3.2 | 3.3 | $0.3447 |
| default | haiku45-200k-na | **2.1** | 2.8 | 2.4 | 3.2 | $0.3524 |
| typescript-bun | haiku45-200k-na | **2.1** | 2.6 | 2.1 | 3.1 | $0.4090 |
| powershell | haiku45-200k-na | **2.3** | 2.7 | 2.2 | 2.9 | $0.4179 |
| bash | haiku45-200k-na | **2.3** | 3.1 | 2.3 | 2.9 | $0.4059 |

</details>


<details>
<summary>Per-run LLM judge scores</summary>

| Task | Language | Model | Cov | Rig | Des | Ovr | Summary |
|------|------|-------|-----|-----|-----|-----|---------|
| Semantic Version Bumper | bash | haiku45-200k-na | 3.0 | 2.0 | 2.5 | 2.5 |  |
| Semantic Version Bumper | bash | opus47-1m-high | 4.0 | 4.0 | 3.5 | 4.0 |  |
| Semantic Version Bumper | bash | opus47-1m-medium | 2.5 | 2.0 | 3.0 | 2.5 |  |
| Semantic Version Bumper | bash | opus47-1m-xhigh | 4.5 | 4.5 | 4.5 | 4.5 |  |
| Semantic Version Bumper | bash | opus47-200k-medium | 4.5 | 4.0 | 4.0 | 4.0 |  |
| Semantic Version Bumper | bash | sonnet46-200k-medium | 3.0 | 3.5 | 4.0 | 3.0 |  |
| Semantic Version Bumper | bash | sonnet46-1m-medium | 4.0 | 3.0 | 3.0 | 3.0 |  |
| Semantic Version Bumper | default | opus47-1m-medium | 4.5 | 4.0 | 4.0 | 4.0 |  |
| Semantic Version Bumper | default | opus47-1m-xhigh | 4.5 | 4.0 | 4.5 | 4.5 |  |
| Semantic Version Bumper | default | sonnet46-200k-medium | 4.5 | 4.0 | 4.0 | 4.0 |  |
| Semantic Version Bumper | default | sonnet46-1m-medium | 2.5 | 2.5 | 3.5 | 2.0 |  |
| Semantic Version Bumper | powershell | opus47-1m-high | 5.0 | 4.5 | 4.5 | 4.5 |  |
| Semantic Version Bumper | powershell | opus47-1m-medium | 5.0 | 4.5 | 4.5 | 4.5 |  |
| Semantic Version Bumper | powershell | opus47-1m-xhigh | 4.5 | 4.0 | 4.5 | 4.5 |  |
| Semantic Version Bumper | powershell | opus47-200k-medium | 4.0 | 4.0 | 4.0 | 4.0 |  |
| Semantic Version Bumper | powershell | sonnet46-200k-medium | 4.0 | 3.5 | 4.0 | 4.0 |  |
| Semantic Version Bumper | powershell | sonnet46-1m-medium | 4.0 | 4.0 | 4.0 | 4.0 |  |
| Semantic Version Bumper | powershell | opus47-1m-high | 4.5 | 3.5 | 4.5 | 4.5 |  |
| Semantic Version Bumper | powershell | opus47-1m-medium | 4.5 | 4.0 | 4.5 | 4.0 |  |
| Semantic Version Bumper | powershell | opus47-1m-xhigh | 3.5 | 3.5 | 3.5 | 3.5 |  |
| Semantic Version Bumper | powershell | opus47-200k-medium | 4.5 | 4.0 | 4.5 | 4.0 |  |
| Semantic Version Bumper | powershell | sonnet46-200k-medium | 4.5 | 4.0 | 4.5 | 4.5 |  |
| Semantic Version Bumper | powershell | sonnet46-1m-medium | 4.5 | 4.0 | 3.5 | 3.5 |  |
| Semantic Version Bumper | typescript-bun | haiku45-200k-na | 3.0 | 2.5 | 2.5 | 2.0 |  |
| Semantic Version Bumper | typescript-bun | opus47-1m-high | 4.5 | 4.0 | 4.5 | 4.5 |  |
| Semantic Version Bumper | typescript-bun | opus47-1m-medium | 4.0 | 4.0 | 4.0 | 4.0 |  |
| Semantic Version Bumper | typescript-bun | opus47-1m-xhigh | 5.0 | 4.5 | 4.5 | 4.5 |  |
| Semantic Version Bumper | typescript-bun | opus47-200k-medium | 4.0 | 3.5 | 4.0 | 3.5 |  |
| Semantic Version Bumper | typescript-bun | sonnet46-200k-medium | 2.0 | 2.5 | 3.5 | 2.0 |  |
| Semantic Version Bumper | typescript-bun | sonnet46-1m-medium | 4.0 | 3.5 | 4.0 | 4.0 |  |
| PR Label Assigner | bash | haiku45-200k-na | 2.5 | 2.0 | 2.0 | 2.0 |  |
| PR Label Assigner | bash | opus47-1m-high | 4.5 | 3.5 | 4.5 | 4.0 |  |
| PR Label Assigner | bash | opus47-1m-medium | 4.0 | 3.0 | 4.0 | 4.0 |  |
| PR Label Assigner | bash | opus47-1m-xhigh | 4.0 | 4.0 | 4.5 | 3.5 |  |
| PR Label Assigner | bash | opus47-200k-medium | 3.5 | 3.0 | 2.0 | 2.0 |  |
| PR Label Assigner | bash | sonnet46-200k-medium | 4.0 | 3.5 | 4.0 | 4.0 |  |
| PR Label Assigner | bash | sonnet46-1m-medium | 2.5 | 2.5 | 3.5 | 2.0 |  |
| PR Label Assigner | default | haiku45-200k-na | 2.0 | 2.0 | 3.0 | 1.5 |  |
| PR Label Assigner | default | opus47-1m-high | 4.5 | 4.0 | 4.0 | 4.0 |  |
| PR Label Assigner | default | opus47-1m-medium | 1.5 | 1.5 | 3.5 | 2.0 |  |
| PR Label Assigner | default | opus47-1m-xhigh | 4.5 | 4.0 | 4.0 | 4.0 |  |
| PR Label Assigner | default | opus47-200k-medium | 2.0 | 2.0 | 3.0 | 2.0 |  |
| PR Label Assigner | default | sonnet46-200k-medium | 3.0 | 3.5 | 4.0 | 2.5 |  |
| PR Label Assigner | default | sonnet46-1m-medium | 3.5 | 3.0 | 4.5 | 3.0 |  |
| PR Label Assigner | powershell | haiku45-200k-na | 2.0 | 2.5 | 3.0 | 2.0 |  |
| PR Label Assigner | powershell | opus47-1m-high | 4.5 | 4.0 | 4.5 | 4.0 |  |
| PR Label Assigner | powershell | opus47-1m-medium | 4.5 | 4.5 | 3.5 | 4.0 |  |
| PR Label Assigner | powershell | opus47-1m-xhigh | 4.0 | 3.5 | 4.0 | 4.0 |  |
| PR Label Assigner | powershell | opus47-200k-medium | 4.5 | 4.0 | 4.0 | 4.0 |  |
| PR Label Assigner | powershell | sonnet46-200k-medium | 2.0 | 2.5 | 3.5 | 1.5 |  |
| PR Label Assigner | powershell | sonnet46-1m-medium | 5.0 | 4.5 | 4.5 | 4.5 |  |
| PR Label Assigner | powershell | haiku45-200k-na | 3.0 | 2.5 | 3.0 | 2.5 |  |
| PR Label Assigner | powershell | opus47-1m-high | 4.5 | 4.5 | 4.5 | 4.5 |  |
| PR Label Assigner | powershell | opus47-1m-medium | 4.0 | 4.0 | 4.0 | 3.5 |  |
| PR Label Assigner | powershell | opus47-1m-xhigh | 4.5 | 4.0 | 4.5 | 4.0 |  |
| PR Label Assigner | powershell | opus47-200k-medium | 4.5 | 4.0 | 4.5 | 4.0 |  |
| PR Label Assigner | powershell | sonnet46-200k-medium | 4.5 | 4.0 | 4.0 | 4.0 |  |
| PR Label Assigner | powershell | sonnet46-1m-medium | 3.0 | 3.0 | 3.0 | 2.5 |  |
| PR Label Assigner | typescript-bun | haiku45-200k-na | 2.5 | 1.5 | 2.5 | 2.0 |  |
| PR Label Assigner | typescript-bun | opus47-1m-high | 4.0 | 3.5 | 4.0 | 4.0 |  |
| PR Label Assigner | typescript-bun | opus47-1m-medium | 4.0 | 4.0 | 4.0 | 4.0 |  |
| PR Label Assigner | typescript-bun | opus47-1m-xhigh | 4.5 | 4.0 | 4.5 | 4.5 |  |
| PR Label Assigner | typescript-bun | opus47-200k-medium | 4.0 | 4.0 | 4.0 | 4.0 |  |
| PR Label Assigner | typescript-bun | sonnet46-200k-medium | 3.0 | 3.0 | 2.5 | 2.5 |  |
| PR Label Assigner | typescript-bun | sonnet46-1m-medium | 3.5 | 3.5 | 4.0 | 3.0 |  |
| Dependency License Checker | bash | haiku45-200k-na | 4.5 | 2.5 | 3.0 | 2.5 |  |
| Dependency License Checker | bash | opus47-1m-high | 3.0 | 2.0 | 4.0 | 2.5 |  |
| Dependency License Checker | bash | opus47-1m-medium | 3.0 | 2.0 | 4.0 | 3.0 |  |
| Dependency License Checker | bash | opus47-1m-xhigh | 2.5 | 2.5 | 3.5 | 2.5 |  |
| Dependency License Checker | bash | opus47-200k-medium | 3.5 | 3.5 | 3.0 | 3.0 |  |
| Dependency License Checker | bash | sonnet46-200k-medium | 3.5 | 3.0 | 2.5 | 2.0 |  |
| Dependency License Checker | bash | sonnet46-1m-medium | 4.5 | 3.5 | 4.0 | 4.0 |  |
| Dependency License Checker | default | haiku45-200k-na | 3.5 | 2.5 | 3.0 | 2.5 |  |
| Dependency License Checker | default | opus47-1m-high | 4.0 | 4.0 | 4.5 | 4.0 |  |
| Dependency License Checker | default | opus47-1m-medium | 4.5 | 4.0 | 4.0 | 4.0 |  |
| Dependency License Checker | default | opus47-1m-xhigh | 4.5 | 4.0 | 4.5 | 4.0 |  |
| Dependency License Checker | default | opus47-200k-medium | 4.5 | 4.0 | 4.5 | 4.5 |  |
| Dependency License Checker | default | sonnet46-200k-medium | 5.0 | 4.5 | 4.5 | 4.5 |  |
| Dependency License Checker | default | sonnet46-1m-medium | 3.5 | 3.5 | 3.5 | 3.5 |  |
| Dependency License Checker | powershell | haiku45-200k-na | 3.0 | 2.0 | 3.0 | 2.5 |  |
| Dependency License Checker | powershell | opus47-1m-high | 4.0 | 4.0 | 4.0 | 4.0 |  |
| Dependency License Checker | powershell | opus47-1m-medium | 3.5 | 3.5 | 3.5 | 3.5 |  |
| Dependency License Checker | powershell | opus47-1m-xhigh | 4.0 | 4.0 | 4.0 | 4.0 |  |
| Dependency License Checker | powershell | opus47-200k-medium | 4.0 | 3.5 | 4.0 | 3.5 |  |
| Dependency License Checker | powershell | sonnet46-200k-medium | 3.0 | 3.0 | 4.0 | 3.0 |  |
| Dependency License Checker | powershell | sonnet46-1m-medium | 4.5 | 4.0 | 4.5 | 4.5 |  |
| Dependency License Checker | powershell | haiku45-200k-na | 3.0 | 2.0 | 3.5 | 2.5 |  |
| Dependency License Checker | powershell | opus47-1m-high | 4.0 | 4.0 | 4.5 | 4.0 |  |
| Dependency License Checker | powershell | opus47-1m-medium | 4.5 | 4.0 | 4.5 | 4.0 |  |
| Dependency License Checker | powershell | opus47-1m-xhigh | 4.5 | 4.0 | 4.5 | 4.0 |  |
| Dependency License Checker | powershell | opus47-200k-medium | 4.0 | 3.5 | 4.0 | 4.0 |  |
| Dependency License Checker | powershell | sonnet46-200k-medium | 3.5 | 3.0 | 3.5 | 3.5 |  |
| Dependency License Checker | powershell | sonnet46-1m-medium | 4.5 | 4.5 | 4.0 | 4.0 |  |
| Dependency License Checker | typescript-bun | haiku45-200k-na | 2.0 | 2.0 | 3.5 | 2.0 |  |
| Dependency License Checker | typescript-bun | opus47-1m-high | 4.5 | 4.0 | 4.5 | 4.5 |  |
| Dependency License Checker | typescript-bun | opus47-1m-medium | 4.5 | 4.0 | 4.0 | 4.0 |  |
| Dependency License Checker | typescript-bun | opus47-1m-xhigh | 4.5 | 4.5 | 4.5 | 4.5 |  |
| Dependency License Checker | typescript-bun | opus47-200k-medium | 4.0 | 4.0 | 4.5 | 4.0 |  |
| Dependency License Checker | typescript-bun | sonnet46-200k-medium | 3.5 | 3.5 | 4.0 | 3.5 |  |
| Dependency License Checker | typescript-bun | sonnet46-1m-medium | 4.5 | 4.0 | 4.5 | 4.0 |  |
| Test Results Aggregator | bash | haiku45-200k-na | 3.0 | 2.5 | 3.5 | 2.5 |  |
| Test Results Aggregator | bash | opus47-1m-high | 3.5 | 4.0 | 3.5 | 3.5 |  |
| Test Results Aggregator | bash | opus47-1m-medium | 4.0 | 3.5 | 4.0 | 4.0 |  |
| Test Results Aggregator | bash | opus47-1m-xhigh | 4.5 | 4.0 | 4.5 | 4.5 |  |
| Test Results Aggregator | bash | opus47-200k-medium | 4.5 | 3.5 | 4.0 | 4.0 |  |
| Test Results Aggregator | bash | sonnet46-200k-medium | 4.0 | 3.5 | 4.0 | 4.0 |  |
| Test Results Aggregator | bash | sonnet46-1m-medium | 4.0 | 3.5 | 4.0 | 3.5 |  |
| Test Results Aggregator | default | haiku45-200k-na | 3.0 | 2.0 | 3.5 | 2.5 |  |
| Test Results Aggregator | default | opus47-1m-high | 4.5 | 4.0 | 4.5 | 4.0 |  |
| Test Results Aggregator | default | opus47-1m-medium | 4.0 | 3.5 | 4.0 | 3.5 |  |
| Test Results Aggregator | default | opus47-1m-xhigh | 4.5 | 4.0 | 4.5 | 4.0 |  |
| Test Results Aggregator | default | opus47-200k-medium | 4.0 | 3.0 | 4.0 | 4.0 |  |
| Test Results Aggregator | default | sonnet46-200k-medium | 5.0 | 4.5 | 4.5 | 4.5 |  |
| Test Results Aggregator | default | sonnet46-1m-medium | 3.5 | 3.0 | 3.5 | 3.5 |  |
| Test Results Aggregator | powershell | haiku45-200k-na | 2.5 | 1.5 | 2.0 | 1.5 |  |
| Test Results Aggregator | powershell | opus47-1m-high | 4.5 | 3.5 | 4.0 | 4.0 |  |
| Test Results Aggregator | powershell | opus47-1m-medium | 5.0 | 4.0 | 4.5 | 4.0 |  |
| Test Results Aggregator | powershell | opus47-1m-xhigh | 3.5 | 3.5 | 4.0 | 3.5 |  |
| Test Results Aggregator | powershell | opus47-200k-medium | 4.5 | 4.0 | 3.5 | 3.5 |  |
| Test Results Aggregator | powershell | sonnet46-200k-medium | 4.0 | 3.5 | 4.0 | 4.0 |  |
| Test Results Aggregator | powershell | sonnet46-1m-medium | 3.5 | 2.5 | 3.5 | 3.0 |  |
| Test Results Aggregator | powershell | opus47-1m-high | 4.0 | 4.0 | 4.0 | 4.0 |  |
| Test Results Aggregator | powershell | opus47-1m-medium | 4.0 | 3.5 | 4.0 | 3.5 |  |
| Test Results Aggregator | powershell | opus47-1m-xhigh | 4.0 | 4.0 | 4.0 | 4.0 |  |
| Test Results Aggregator | powershell | opus47-200k-medium | 4.0 | 3.5 | 4.0 | 3.5 |  |
| Test Results Aggregator | powershell | sonnet46-200k-medium | 4.5 | 3.5 | 4.5 | 4.5 |  |
| Test Results Aggregator | powershell | sonnet46-1m-medium | 4.5 | 4.0 | 4.5 | 4.0 |  |
| Test Results Aggregator | typescript-bun | haiku45-200k-na | 2.5 | 2.0 | 3.0 | 2.0 |  |
| Test Results Aggregator | typescript-bun | opus47-1m-high | 4.0 | 4.0 | 4.5 | 4.0 |  |
| Test Results Aggregator | typescript-bun | opus47-1m-medium | 4.0 | 4.0 | 4.0 | 4.0 |  |
| Test Results Aggregator | typescript-bun | opus47-1m-xhigh | 4.5 | 4.5 | 4.5 | 4.5 |  |
| Test Results Aggregator | typescript-bun | opus47-200k-medium | 4.0 | 3.5 | 3.5 | 3.5 |  |
| Test Results Aggregator | typescript-bun | sonnet46-200k-medium | 4.5 | 4.0 | 4.5 | 4.0 |  |
| Test Results Aggregator | typescript-bun | sonnet46-1m-medium | 4.0 | 3.0 | 4.5 | 3.5 |  |
| Environment Matrix Generator | bash | haiku45-200k-na | 2.5 | 2.0 | 3.0 | 2.0 |  |
| Environment Matrix Generator | bash | opus47-1m-high | 4.0 | 3.5 | 4.0 | 4.0 |  |
| Environment Matrix Generator | bash | opus47-1m-medium | 3.5 | 3.5 | 3.5 | 3.0 |  |
| Environment Matrix Generator | bash | opus47-1m-xhigh | 3.5 | 3.5 | 4.0 | 3.5 |  |
| Environment Matrix Generator | bash | opus47-200k-medium | 3.5 | 3.0 | 3.5 | 3.5 |  |
| Environment Matrix Generator | bash | sonnet46-1m-medium | 3.5 | 3.5 | 4.0 | 3.5 |  |
| Environment Matrix Generator | default | haiku45-200k-na | 2.0 | 2.5 | 3.5 | 2.0 |  |
| Environment Matrix Generator | default | opus47-1m-high | 4.5 | 4.0 | 4.5 | 4.0 |  |
| Environment Matrix Generator | default | opus47-1m-medium | 4.5 | 4.0 | 4.0 | 4.0 |  |
| Environment Matrix Generator | default | opus47-1m-xhigh | 3.5 | 4.0 | 4.0 | 3.0 |  |
| Environment Matrix Generator | default | opus47-200k-medium | 4.5 | 4.0 | 4.0 | 4.0 |  |
| Environment Matrix Generator | default | sonnet46-200k-medium | 2.5 | 2.5 | 3.5 | 2.0 |  |
| Environment Matrix Generator | default | sonnet46-1m-medium | 2.0 | 2.5 | 3.5 | 2.0 |  |
| Environment Matrix Generator | powershell | opus47-1m-high | 4.0 | 3.5 | 4.0 | 4.0 |  |
| Environment Matrix Generator | powershell | opus47-1m-medium | 4.5 | 4.0 | 4.0 | 4.0 |  |
| Environment Matrix Generator | powershell | opus47-1m-xhigh | 4.5 | 4.0 | 4.0 | 4.0 |  |
| Environment Matrix Generator | powershell | opus47-200k-medium | 4.0 | 4.0 | 4.0 | 4.0 |  |
| Environment Matrix Generator | powershell | sonnet46-200k-medium | 3.0 | 2.5 | 3.5 | 2.5 |  |
| Environment Matrix Generator | powershell | sonnet46-1m-medium | 3.0 | 2.5 | 4.0 | 2.5 |  |
| Environment Matrix Generator | powershell | haiku45-200k-na | 3.5 | 3.0 | 4.0 | 3.5 |  |
| Environment Matrix Generator | powershell | opus47-1m-high | 4.0 | 3.5 | 4.0 | 3.5 |  |
| Environment Matrix Generator | powershell | opus47-1m-medium | 4.0 | 3.5 | 3.5 | 3.5 |  |
| Environment Matrix Generator | powershell | opus47-1m-xhigh | 4.5 | 4.0 | 4.0 | 4.0 |  |
| Environment Matrix Generator | powershell | opus47-200k-medium | 4.5 | 4.0 | 4.0 | 4.0 |  |
| Environment Matrix Generator | powershell | sonnet46-200k-medium | 4.0 | 3.5 | 4.5 | 4.0 |  |
| Environment Matrix Generator | powershell | sonnet46-1m-medium | 4.5 | 4.0 | 4.5 | 4.0 |  |
| Environment Matrix Generator | typescript-bun | haiku45-200k-na | 3.0 | 2.5 | 3.5 | 3.0 |  |
| Environment Matrix Generator | typescript-bun | opus47-1m-high | 4.0 | 3.5 | 4.0 | 3.5 |  |
| Environment Matrix Generator | typescript-bun | opus47-1m-medium | 4.0 | 3.0 | 3.0 | 3.0 |  |
| Environment Matrix Generator | typescript-bun | opus47-1m-xhigh | 4.5 | 4.0 | 4.5 | 4.5 |  |
| Environment Matrix Generator | typescript-bun | opus47-200k-medium | 4.0 | 4.0 | 4.0 | 4.0 |  |
| Environment Matrix Generator | typescript-bun | sonnet46-200k-medium | 4.0 | 3.5 | 3.5 | 3.5 |  |
| Environment Matrix Generator | typescript-bun | sonnet46-1m-medium | 4.0 | 3.5 | 3.5 | 3.5 |  |
| Artifact Cleanup Script | bash | haiku45-200k-na | 3.0 | 3.0 | 3.5 | 2.5 |  |
| Artifact Cleanup Script | bash | opus47-1m-high | 4.0 | 3.5 | 4.0 | 3.5 |  |
| Artifact Cleanup Script | bash | opus47-1m-medium | 4.0 | 3.0 | 3.5 | 3.0 |  |
| Artifact Cleanup Script | bash | opus47-1m-xhigh | 4.5 | 4.0 | 4.0 | 4.0 |  |
| Artifact Cleanup Script | bash | opus47-200k-medium | 3.0 | 3.0 | 3.0 | 3.0 |  |
| Artifact Cleanup Script | bash | sonnet46-200k-medium | 3.0 | 2.0 | 3.5 | 2.5 |  |
| Artifact Cleanup Script | bash | sonnet46-1m-medium | 4.5 | 3.5 | 4.5 | 4.0 |  |
| Artifact Cleanup Script | default | haiku45-200k-na | 4.0 | 3.0 | 3.0 | 2.5 |  |
| Artifact Cleanup Script | default | opus47-1m-high | 4.5 | 4.0 | 4.5 | 4.5 |  |
| Artifact Cleanup Script | default | opus47-1m-medium | 4.0 | 3.5 | 4.0 | 4.0 |  |
| Artifact Cleanup Script | default | opus47-1m-xhigh | 4.5 | 4.5 | 4.5 | 4.5 |  |
| Artifact Cleanup Script | default | opus47-200k-medium | 5.0 | 4.0 | 4.5 | 4.5 |  |
| Artifact Cleanup Script | default | sonnet46-200k-medium | 4.5 | 3.5 | 4.5 | 4.0 |  |
| Artifact Cleanup Script | default | sonnet46-1m-medium | 5.0 | 3.5 | 4.5 | 4.5 |  |
| Artifact Cleanup Script | powershell | opus47-1m-high | 4.5 | 4.0 | 4.5 | 4.5 |  |
| Artifact Cleanup Script | powershell | opus47-1m-medium | 4.0 | 3.5 | 4.0 | 3.5 |  |
| Artifact Cleanup Script | powershell | opus47-1m-xhigh | 4.5 | 4.0 | 5.0 | 4.5 |  |
| Artifact Cleanup Script | powershell | opus47-200k-medium | 4.0 | 3.5 | 4.0 | 3.5 |  |
| Artifact Cleanup Script | powershell | sonnet46-200k-medium | 4.0 | 3.0 | 4.5 | 4.0 |  |
| Artifact Cleanup Script | powershell | sonnet46-1m-medium | 4.0 | 3.0 | 3.5 | 3.5 |  |
| Artifact Cleanup Script | powershell | haiku45-200k-na | 2.0 | 1.5 | 2.0 | 1.5 |  |
| Artifact Cleanup Script | powershell | opus47-1m-high | 4.0 | 4.0 | 4.5 | 4.0 |  |
| Artifact Cleanup Script | powershell | opus47-1m-medium | 4.0 | 3.5 | 4.0 | 4.0 |  |
| Artifact Cleanup Script | powershell | opus47-1m-xhigh | 4.5 | 4.0 | 4.5 | 4.0 |  |
| Artifact Cleanup Script | powershell | opus47-200k-medium | 4.5 | 4.0 | 4.5 | 4.0 |  |
| Artifact Cleanup Script | powershell | sonnet46-200k-medium | 4.0 | 4.0 | 4.0 | 4.0 |  |
| Artifact Cleanup Script | powershell | sonnet46-1m-medium | 3.5 | 3.0 | 4.5 | 3.0 |  |
| Artifact Cleanup Script | typescript-bun | haiku45-200k-na | 2.5 | 2.0 | 3.5 | 2.0 |  |
| Artifact Cleanup Script | typescript-bun | opus47-1m-high | 4.5 | 4.0 | 4.5 | 4.5 |  |
| Artifact Cleanup Script | typescript-bun | opus47-1m-medium | 4.0 | 3.5 | 4.0 | 3.5 |  |
| Artifact Cleanup Script | typescript-bun | opus47-1m-xhigh | 4.5 | 4.0 | 4.5 | 4.5 |  |
| Artifact Cleanup Script | typescript-bun | opus47-200k-medium | 4.0 | 3.5 | 4.0 | 4.0 |  |
| Artifact Cleanup Script | typescript-bun | sonnet46-200k-medium | 3.5 | 3.0 | 4.0 | 3.0 |  |
| Artifact Cleanup Script | typescript-bun | sonnet46-1m-medium | 4.5 | 4.0 | 4.5 | 4.0 |  |
| Secret Rotation Validator | bash | haiku45-200k-na | 3.0 | 2.0 | 2.5 | 2.0 |  |
| Secret Rotation Validator | bash | opus47-1m-high | 3.5 | 3.0 | 3.5 | 3.0 |  |
| Secret Rotation Validator | bash | opus47-1m-medium | 3.5 | 2.5 | 3.0 | 3.0 |  |
| Secret Rotation Validator | bash | opus47-1m-xhigh | 3.5 | 3.0 | 4.0 | 3.5 |  |
| Secret Rotation Validator | bash | opus47-200k-medium | 3.0 | 2.5 | 3.5 | 3.0 |  |
| Secret Rotation Validator | bash | sonnet46-200k-medium | 4.0 | 4.0 | 4.5 | 4.0 |  |
| Secret Rotation Validator | bash | sonnet46-1m-medium | 4.0 | 3.5 | 4.0 | 3.5 |  |
| Secret Rotation Validator | default | haiku45-200k-na | 2.0 | 2.5 | 3.0 | 1.5 |  |
| Secret Rotation Validator | default | opus47-1m-high | 4.5 | 4.5 | 4.5 | 4.5 |  |
| Secret Rotation Validator | default | opus47-1m-medium | 3.0 | 2.0 | 3.0 | 2.0 |  |
| Secret Rotation Validator | default | opus47-1m-xhigh | 4.0 | 4.0 | 4.5 | 4.0 |  |
| Secret Rotation Validator | default | opus47-200k-medium | 4.5 | 4.0 | 4.5 | 4.0 |  |
| Secret Rotation Validator | default | sonnet46-200k-medium | 4.0 | 4.0 | 3.5 | 3.5 |  |
| Secret Rotation Validator | default | sonnet46-1m-medium | 4.5 | 4.0 | 4.5 | 4.5 |  |
| Secret Rotation Validator | powershell | haiku45-200k-na | 2.0 | 2.0 | 2.5 | 2.0 |  |
| Secret Rotation Validator | powershell | opus47-1m-high | 4.5 | 4.5 | 4.5 | 4.5 |  |
| Secret Rotation Validator | powershell | opus47-1m-medium | 4.0 | 4.0 | 4.0 | 4.0 |  |
| Secret Rotation Validator | powershell | opus47-1m-xhigh | 4.5 | 4.0 | 4.5 | 4.5 |  |
| Secret Rotation Validator | powershell | opus47-200k-medium | 4.0 | 3.5 | 3.5 | 3.5 |  |
| Secret Rotation Validator | powershell | sonnet46-200k-medium | 2.5 | 2.5 | 3.5 | 2.5 |  |
| Secret Rotation Validator | powershell | sonnet46-1m-medium | 4.0 | 3.5 | 4.0 | 3.5 |  |
| Secret Rotation Validator | powershell | haiku45-200k-na | 3.5 | 2.5 | 3.5 | 3.0 |  |
| Secret Rotation Validator | powershell | opus47-1m-high | 5.0 | 4.5 | 4.5 | 4.5 |  |
| Secret Rotation Validator | powershell | opus47-1m-medium | 4.5 | 4.0 | 4.5 | 4.0 |  |
| Secret Rotation Validator | powershell | opus47-1m-xhigh | 4.0 | 4.0 | 4.5 | 4.0 |  |
| Secret Rotation Validator | powershell | opus47-200k-medium | 4.0 | 3.5 | 4.0 | 3.5 |  |
| Secret Rotation Validator | powershell | sonnet46-200k-medium | 3.5 | 4.0 | 4.5 | 3.0 |  |
| Secret Rotation Validator | powershell | sonnet46-1m-medium | 3.0 | 3.0 | 4.5 | 2.5 |  |
| Secret Rotation Validator | typescript-bun | haiku45-200k-na | 2.5 | 2.5 | 3.5 | 2.0 |  |
| Secret Rotation Validator | typescript-bun | opus47-1m-high | 4.0 | 3.5 | 4.0 | 3.5 |  |
| Secret Rotation Validator | typescript-bun | opus47-1m-medium | 4.0 | 4.0 | 4.5 | 4.0 |  |
| Secret Rotation Validator | typescript-bun | opus47-1m-xhigh | 4.5 | 4.0 | 4.5 | 4.5 |  |
| Secret Rotation Validator | typescript-bun | opus47-200k-medium | 4.0 | 3.5 | 4.0 | 3.5 |  |
| Secret Rotation Validator | typescript-bun | sonnet46-200k-medium | 4.0 | 4.0 | 4.5 | 4.0 |  |
| Secret Rotation Validator | typescript-bun | sonnet46-1m-medium | 3.0 | 3.0 | 4.0 | 3.0 |  |

</details>

### Correlation: Structural Metrics vs Tests Quality

Spearman rank correlation between automated counts and LLM judge scores.
Values near +1.0 indicate the LLM agrees with the structural signal; near 0 means no relationship.

| Structural Metric | vs Coverage | vs Rigor | vs Design | vs Overall |
|-------------------|------------|---------|----------|-----------|
| Test count | 0.35 | 0.42 | 0.35 | 0.37 |
| Assertion count | 0.4 | 0.46 | 0.38 | 0.43 |
| Test:code ratio | 0.13 | 0.21 | 0.13 | 0.18 |

*Based on 236 runs with both structural and LLM scores.*

### LLM vs Structural Discrepancies

**Qualitative disagreements** — structural metrics look reasonable; the LLM judge is weighing factors the counters can't measure.

| Task | Language | Model | Tests | Asserts | Cov | Rig | Des | Ovr | Flag | Justification |
|------|------|-------|-------|---------|-----|-----|-----|-----|------|---------------|
| Semantic Version Bumper | typescript-bun | sonnet46-200k-medium | 28 | 38 | 2.0 | 2.5 | 3.5 | 2.0 | LLM says low coverage (2.0/5) but 28 tests detected |  |
| PR Label Assigner | default | haiku45-200k-na | 21 | 28 | 2.0 | 2.0 | 3.0 | 1.5 | LLM says low coverage (2.0/5) but 21 tests detected |  |
| PR Label Assigner | powershell | sonnet46-200k-medium | 28 | 55 | 2.0 | 2.5 | 3.5 | 1.5 | LLM says low coverage (2.0/5) but 28 tests detected |  |
| Dependency License Checker | bash | opus47-1m-medium | 10 | 43 | 3.0 | 2.0 | 4.0 | 3.0 | LLM says low rigor (2.0/5) but 43 assertions detected |  |
| Test Results Aggregator | default | haiku45-200k-na | 11 | 47 | 3.0 | 2.0 | 3.5 | 2.5 | LLM says low rigor (2.0/5) but 47 assertions detected |  |
| Test Results Aggregator | typescript-bun | haiku45-200k-na | 25 | 80 | 2.5 | 2.0 | 3.0 | 2.0 | LLM says low rigor (2.0/5) but 80 assertions detected |  |
| Environment Matrix Generator | default | haiku45-200k-na | 23 | 36 | 2.0 | 2.5 | 3.5 | 2.0 | LLM says low coverage (2.0/5) but 23 tests detected |  |
| Environment Matrix Generator | default | sonnet46-1m-medium | 33 | 26 | 2.0 | 2.5 | 3.5 | 2.0 | LLM says low coverage (2.0/5) but 33 tests detected |  |
| Secret Rotation Validator | default | opus47-1m-medium | 21 | 43 | 3.0 | 2.0 | 3.0 | 2.0 | LLM says low rigor (2.0/5) but 43 assertions detected |  |

## Per-Run Results

*Tests Quality = Overall (1-5) from LLM-as-judge of generated test code (dimensions: coverage, rigor, design). `—` = no judge data.*

| Task | Language | Model | Duration | Turns | Errors | Cost | Tests Quality | Chosen | Status |
|------|----------|-------|----------|-------|--------|------|-----------|--------|--------|
| Artifact Cleanup Script | bash | haiku45-200k-na | 6.6min | 51 | 3 | $0.43 | 2.5 | bash | ok |
| Artifact Cleanup Script | bash | opus47-1m-high | 9.1min | 44 | 0 | $2.18 | 3.5 | bash | ok |
| Artifact Cleanup Script | bash | opus47-1m-medium | 3.1min | 24 | 3 | $0.92 | 3.0 | bash | ok |
| Artifact Cleanup Script | bash | opus47-1m-xhigh | 7.6min | 34 | 1 | $1.84 | 4.0 | bash | ok |
| Artifact Cleanup Script | bash | opus47-200k-medium | 5.8min | 25 | 1 | $1.26 | 3.0 | bash | ok |
| Artifact Cleanup Script | bash | sonnet46-1m-medium | 11.6min | 45 | 6 | $1.78 | 4.0 | bash | ok |
| Artifact Cleanup Script | bash | sonnet46-200k-medium | 4.4min | 31 | 2 | $0.61 | 2.5 | bash | ok |
| Artifact Cleanup Script | default | haiku45-200k-na | 4.8min | 45 | 4 | $0.46 | 2.5 | python | ok |
| Artifact Cleanup Script | default | opus47-1m-high | 6.6min | 36 | 0 | $2.04 | 4.5 | python | ok |
| Artifact Cleanup Script | default | opus47-1m-medium | 3.2min | 19 | 0 | $0.85 | 4.0 | python | ok |
| Artifact Cleanup Script | default | opus47-1m-xhigh | 7.1min | 35 | 1 | $1.91 | 4.5 | python | ok |
| Artifact Cleanup Script | default | opus47-200k-medium | 5.0min | 23 | 0 | $1.30 | 4.5 | python | ok |
| Artifact Cleanup Script | default | sonnet46-1m-medium | 6.8min | 32 | 2 | $1.02 | 4.5 | python | ok |
| Artifact Cleanup Script | default | sonnet46-200k-medium | 8.2min | 28 | 2 | $1.14 | 4.0 | python | ok |
| Artifact Cleanup Script | powershell | haiku45-200k-na | 7.8min | 31 | 2 | $0.28 | — | powershell | ok |
| Artifact Cleanup Script | powershell | haiku45-200k-na | 3.2min | 29 | 2 | $0.28 | 1.5 | powershell | ok |
| Artifact Cleanup Script | powershell | opus47-1m-high | 9.4min | 39 | 0 | $2.30 | 4.5 | powershell | ok |
| Artifact Cleanup Script | powershell | opus47-1m-high | 11.7min | 54 | 1 | $3.33 | 4.0 | powershell | ok |
| Artifact Cleanup Script | powershell | opus47-1m-medium | 4.7min | 22 | 0 | $1.08 | 3.5 | powershell | ok |
| Artifact Cleanup Script | powershell | opus47-1m-medium | 4.1min | 20 | 0 | $0.96 | 4.0 | powershell | ok |
| Artifact Cleanup Script | powershell | opus47-1m-xhigh | 10.9min | 43 | 0 | $3.19 | 4.5 | powershell | ok |
| Artifact Cleanup Script | powershell | opus47-1m-xhigh | 12.0min | 51 | 1 | $3.21 | 4.0 | powershell | ok |
| Artifact Cleanup Script | powershell | opus47-200k-medium | 4.0min | 23 | 0 | $1.09 | 3.5 | powershell | ok |
| Artifact Cleanup Script | powershell | opus47-200k-medium | 5.4min | 32 | 0 | $1.65 | 4.0 | powershell | ok |
| Artifact Cleanup Script | powershell | sonnet46-1m-medium | 7.8min | 28 | 0 | $1.09 | 3.5 | powershell | ok |
| Artifact Cleanup Script | powershell | sonnet46-1m-medium | 3.1min | 18 | 2 | $0.46 | 3.0 | powershell | ok |
| Artifact Cleanup Script | powershell | sonnet46-200k-medium | 8.4min | 31 | 2 | $1.25 | 4.0 | powershell | ok |
| Artifact Cleanup Script | powershell | sonnet46-200k-medium | 6.0min | 50 | 1 | $0.94 | 4.0 | powershell | ok |
| Artifact Cleanup Script | typescript-bun | haiku45-200k-na | 3.8min | 39 | 3 | $0.33 | 2.0 | typescript | ok |
| Artifact Cleanup Script | typescript-bun | opus47-1m-high | 9.2min | 39 | 0 | $2.07 | 4.5 | typescript | ok |
| Artifact Cleanup Script | typescript-bun | opus47-1m-medium | 7.2min | 29 | 0 | $1.25 | 3.5 | typescript | ok |
| Artifact Cleanup Script | typescript-bun | opus47-1m-xhigh | 8.5min | 53 | 0 | $2.41 | 4.5 | typescript | ok |
| Artifact Cleanup Script | typescript-bun | opus47-200k-medium | 4.4min | 22 | 0 | $0.92 | 4.0 | typescript | ok |
| Artifact Cleanup Script | typescript-bun | sonnet46-1m-medium | 7.9min | 49 | 4 | $1.37 | 4.0 | typescript | ok |
| Artifact Cleanup Script | typescript-bun | sonnet46-200k-medium | 3.6min | 26 | 3 | $0.49 | 3.0 | typescript | ok |
| Dependency License Checker | bash | haiku45-200k-na | 14.2min | 47 | 2 | $0.36 | 2.5 | bash | ok |
| Dependency License Checker | bash | opus47-1m-high | 4.0min | 30 | 0 | $1.35 | 2.5 | bash | ok |
| Dependency License Checker | bash | opus47-1m-medium | 5.5min | 30 | 1 | $1.55 | 3.0 | bash | ok |
| Dependency License Checker | bash | opus47-1m-xhigh | 39.8min | 38 | 2 | $2.19 | 2.5 | bash | ok |
| Dependency License Checker | bash | opus47-200k-medium | 7.5min | 26 | 1 | $0.92 | 3.0 | bash | ok |
| Dependency License Checker | bash | sonnet46-1m-medium | 9.1min | 36 | 1 | $1.28 | 4.0 | bash | ok |
| Dependency License Checker | bash | sonnet46-200k-medium | 6.9min | 34 | 2 | $0.97 | 2.0 | bash | ok |
| Dependency License Checker | default | haiku45-200k-na | 4.0min | 47 | 7 | $0.40 | 2.5 | python | ok |
| Dependency License Checker | default | opus47-1m-high | 8.5min | 37 | 0 | $2.28 | 4.0 | python | ok |
| Dependency License Checker | default | opus47-1m-medium | 8.2min | 34 | 2 | $1.33 | 4.0 | python | ok |
| Dependency License Checker | default | opus47-1m-xhigh | 7.5min | 40 | 0 | $2.04 | 4.0 | python | ok |
| Dependency License Checker | default | opus47-200k-medium | 4.1min | 24 | 0 | $0.97 | 4.5 | python | ok |
| Dependency License Checker | default | sonnet46-1m-medium | 6.7min | 43 | 3 | $1.07 | 3.5 | python | ok |
| Dependency License Checker | default | sonnet46-200k-medium | 11.7min | 44 | 4 | $1.68 | 4.5 | python | ok |
| Dependency License Checker | powershell | haiku45-200k-na | 7.6min | 70 | 1 | $0.58 | 2.5 | powershell | ok |
| Dependency License Checker | powershell | haiku45-200k-na | 4.0min | 55 | 2 | $0.42 | 2.5 | powershell | ok |
| Dependency License Checker | powershell | opus47-1m-high | 7.1min | 31 | 0 | $1.93 | 4.0 | powershell | ok |
| Dependency License Checker | powershell | opus47-1m-high | 10.1min | 42 | 0 | $2.43 | 4.0 | powershell | ok |
| Dependency License Checker | powershell | opus47-1m-medium | 6.6min | 23 | 0 | $1.00 | 3.5 | powershell | ok |
| Dependency License Checker | powershell | opus47-1m-medium | 4.9min | 26 | 0 | $1.18 | 4.0 | powershell | ok |
| Dependency License Checker | powershell | opus47-1m-xhigh | 10.2min | 48 | 1 | $2.95 | 4.0 | powershell | ok |
| Dependency License Checker | powershell | opus47-1m-xhigh | 11.2min | 48 | 0 | $2.86 | 4.0 | powershell | ok |
| Dependency License Checker | powershell | opus47-200k-medium | 8.0min | 41 | 1 | $1.86 | 3.5 | powershell | ok |
| Dependency License Checker | powershell | opus47-200k-medium | 6.3min | 34 | 1 | $1.68 | 4.0 | powershell | ok |
| Dependency License Checker | powershell | sonnet46-1m-medium | 7.1min | 43 | 1 | $1.05 | 4.5 | powershell | ok |
| Dependency License Checker | powershell | sonnet46-1m-medium | 12.0min | 45 | 1 | $1.79 | 4.0 | powershell | ok |
| Dependency License Checker | powershell | sonnet46-200k-medium | 8.6min | 40 | 0 | $1.09 | 3.0 | powershell | ok |
| Dependency License Checker | powershell | sonnet46-200k-medium | 9.0min | 27 | 1 | $1.04 | 3.5 | powershell | ok |
| Dependency License Checker | typescript-bun | haiku45-200k-na | 4.3min | 48 | 1 | $0.39 | 2.0 | typescript | ok |
| Dependency License Checker | typescript-bun | opus47-1m-high | 10.9min | 68 | 0 | $3.08 | 4.5 | typescript | ok |
| Dependency License Checker | typescript-bun | opus47-1m-medium | 8.2min | 32 | 1 | $1.34 | 4.0 | typescript | ok |
| Dependency License Checker | typescript-bun | opus47-1m-xhigh | 11.8min | 74 | 0 | $3.64 | 4.5 | typescript | ok |
| Dependency License Checker | typescript-bun | opus47-200k-medium | 4.8min | 29 | 0 | $1.10 | 4.0 | typescript | ok |
| Dependency License Checker | typescript-bun | sonnet46-1m-medium | 8.4min | 50 | 3 | $1.23 | 4.0 | typescript | ok |
| Dependency License Checker | typescript-bun | sonnet46-200k-medium | 6.8min | 35 | 2 | $0.93 | 3.5 | typescript | ok |
| Environment Matrix Generator | bash | haiku45-200k-na | 322.8min | 85 | 10 | $0.75 | 2.0 | bash | timeout |
| Environment Matrix Generator | bash | opus47-1m-high | 6.6min | 42 | 0 | $1.69 | 4.0 | bash | ok |
| Environment Matrix Generator | bash | opus47-1m-medium | 3.5min | 23 | 1 | $0.88 | 3.0 | bash | ok |
| Environment Matrix Generator | bash | opus47-1m-xhigh | 8.3min | 51 | 2 | $2.49 | 3.5 | bash | ok |
| Environment Matrix Generator | bash | opus47-200k-medium | 2.9min | 23 | 0 | $1.05 | 3.5 | bash | ok |
| Environment Matrix Generator | bash | sonnet46-1m-medium | 29.1min | 58 | 6 | $3.25 | 3.5 | bash | ok |
| Environment Matrix Generator | bash | sonnet46-200k-medium | 4.2min | 7 | 1 | $0.35 | — | bash | cli_error |
| Environment Matrix Generator | default | haiku45-200k-na | 4.0min | 42 | 4 | $0.38 | 2.0 | python | ok |
| Environment Matrix Generator | default | opus47-1m-high | 5.7min | 38 | 0 | $1.87 | 4.0 | python | ok |
| Environment Matrix Generator | default | opus47-1m-medium | 5.4min | 26 | 0 | $1.12 | 4.0 | python | ok |
| Environment Matrix Generator | default | opus47-1m-xhigh | 6.8min | 34 | 2 | $2.01 | 3.0 | python | ok |
| Environment Matrix Generator | default | opus47-200k-medium | 5.0min | 28 | 1 | $1.05 | 4.0 | python | ok |
| Environment Matrix Generator | default | sonnet46-1m-medium | 3.7min | 25 | 3 | $0.56 | 2.0 | python | ok |
| Environment Matrix Generator | default | sonnet46-200k-medium | 2.9min | 23 | 2 | $0.41 | 2.0 | python | ok |
| Environment Matrix Generator | powershell | haiku45-200k-na | 4.6min | 43 | 3 | $0.39 | — | powershell | ok |
| Environment Matrix Generator | powershell | haiku45-200k-na | 6.1min | 49 | 6 | $0.56 | 3.5 | powershell | ok |
| Environment Matrix Generator | powershell | opus47-1m-high | 7.0min | 41 | 0 | $2.04 | 4.0 | powershell | ok |
| Environment Matrix Generator | powershell | opus47-1m-high | 7.4min | 30 | 0 | $2.13 | 3.5 | powershell | ok |
| Environment Matrix Generator | powershell | opus47-1m-medium | 14.0min | 59 | 0 | $3.01 | 4.0 | powershell | ok |
| Environment Matrix Generator | powershell | opus47-1m-medium | 4.6min | 29 | 2 | $1.30 | 3.5 | powershell | ok |
| Environment Matrix Generator | powershell | opus47-1m-xhigh | 13.5min | 54 | 0 | $3.93 | 4.0 | powershell | ok |
| Environment Matrix Generator | powershell | opus47-1m-xhigh | 10.2min | 43 | 1 | $3.08 | 4.0 | powershell | ok |
| Environment Matrix Generator | powershell | opus47-200k-medium | 6.1min | 30 | 0 | $1.42 | 4.0 | powershell | ok |
| Environment Matrix Generator | powershell | opus47-200k-medium | 6.0min | 27 | 1 | $1.51 | 4.0 | powershell | ok |
| Environment Matrix Generator | powershell | sonnet46-1m-medium | 2.7min | 16 | 1 | $0.34 | 2.5 | powershell | ok |
| Environment Matrix Generator | powershell | sonnet46-1m-medium | 8.1min | 36 | 7 | $1.04 | 4.0 | powershell | ok |
| Environment Matrix Generator | powershell | sonnet46-200k-medium | 2.1min | 14 | 1 | $0.28 | 2.5 | powershell | ok |
| Environment Matrix Generator | powershell | sonnet46-200k-medium | 8.0min | 25 | 1 | $1.00 | 4.0 | powershell | ok |
| Environment Matrix Generator | typescript-bun | haiku45-200k-na | 8.2min | 73 | 4 | $0.68 | 3.0 | typescript | ok |
| Environment Matrix Generator | typescript-bun | opus47-1m-high | 6.7min | 42 | 0 | $2.13 | 3.5 | typescript | ok |
| Environment Matrix Generator | typescript-bun | opus47-1m-medium | 7.4min | 29 | 0 | $1.07 | 3.0 | typescript | ok |
| Environment Matrix Generator | typescript-bun | opus47-1m-xhigh | 9.8min | 52 | 0 | $2.60 | 4.5 | typescript | ok |
| Environment Matrix Generator | typescript-bun | opus47-200k-medium | 6.5min | 36 | 1 | $1.41 | 4.0 | typescript | ok |
| Environment Matrix Generator | typescript-bun | sonnet46-1m-medium | 12.2min | 42 | 2 | $1.34 | 3.5 | typescript | ok |
| Environment Matrix Generator | typescript-bun | sonnet46-200k-medium | 6.4min | 31 | 2 | $0.90 | 3.5 | typescript | ok |
| PR Label Assigner | bash | haiku45-200k-na | 7.1min | 62 | 4 | $0.50 | 2.0 | bash | ok |
| PR Label Assigner | bash | opus47-1m-high | 5.9min | 31 | 2 | $1.46 | 4.0 | bash | ok |
| PR Label Assigner | bash | opus47-1m-medium | 6.2min | 23 | 1 | $0.87 | 4.0 | bash | ok |
| PR Label Assigner | bash | opus47-1m-xhigh | 16.7min | 61 | 2 | $3.14 | 3.5 | bash | ok |
| PR Label Assigner | bash | opus47-200k-medium | 5.0min | 29 | 3 | $1.18 | 2.0 | bash | ok |
| PR Label Assigner | bash | sonnet46-1m-medium | 3.1min | 28 | 4 | $0.50 | 2.0 | bash | ok |
| PR Label Assigner | bash | sonnet46-200k-medium | 7.2min | 44 | 3 | $0.90 | 4.0 | bash | ok |
| PR Label Assigner | default | haiku45-200k-na | 2.9min | 27 | 3 | $0.25 | 1.5 | python | ok |
| PR Label Assigner | default | opus47-1m-high | 7.6min | 23 | 1 | $1.32 | 4.0 | python | ok |
| PR Label Assigner | default | opus47-1m-medium | 3.1min | 23 | 0 | $0.83 | 2.0 | python | ok |
| PR Label Assigner | default | opus47-1m-xhigh | 7.8min | 43 | 0 | $2.25 | 4.0 | python | ok |
| PR Label Assigner | default | opus47-200k-medium | 3.2min | 21 | 0 | $0.70 | 2.0 | python | ok |
| PR Label Assigner | default | sonnet46-1m-medium | 9.6min | 44 | 7 | $1.38 | 3.0 | python | ok |
| PR Label Assigner | default | sonnet46-200k-medium | 4.4min | 34 | 1 | $0.66 | 2.5 | python | ok |
| PR Label Assigner | powershell | haiku45-200k-na | 5.2min | 44 | 1 | $0.38 | 2.0 | powershell | ok |
| PR Label Assigner | powershell | haiku45-200k-na | 3.0min | 26 | 1 | $0.23 | 2.5 | powershell | ok |
| PR Label Assigner | powershell | opus47-1m-high | 10.0min | 49 | 1 | $2.92 | 4.0 | powershell | ok |
| PR Label Assigner | powershell | opus47-1m-high | 5.7min | 29 | 1 | $1.67 | 4.5 | powershell | ok |
| PR Label Assigner | powershell | opus47-1m-medium | 5.1min | 27 | 0 | $1.11 | 4.0 | powershell | ok |
| PR Label Assigner | powershell | opus47-1m-medium | 7.4min | 29 | 0 | $1.33 | 3.5 | powershell | ok |
| PR Label Assigner | powershell | opus47-1m-xhigh | 9.6min | 43 | 0 | $2.60 | 4.0 | powershell | ok |
| PR Label Assigner | powershell | opus47-1m-xhigh | 7.7min | 37 | 0 | $2.01 | 4.0 | powershell | ok |
| PR Label Assigner | powershell | opus47-200k-medium | 8.5min | 38 | 0 | $1.93 | 4.0 | powershell | ok |
| PR Label Assigner | powershell | opus47-200k-medium | 5.3min | 27 | 0 | $1.34 | 4.0 | powershell | ok |
| PR Label Assigner | powershell | sonnet46-1m-medium | 12.0min | 31 | 1 | $1.61 | 4.5 | powershell | ok |
| PR Label Assigner | powershell | sonnet46-1m-medium | 4.4min | 28 | 1 | $0.59 | 2.5 | powershell | ok |
| PR Label Assigner | powershell | sonnet46-200k-medium | 2.9min | 19 | 0 | $0.38 | 1.5 | powershell | ok |
| PR Label Assigner | powershell | sonnet46-200k-medium | 8.4min | 35 | 3 | $1.11 | 4.0 | powershell | ok |
| PR Label Assigner | typescript-bun | haiku45-200k-na | 6.0min | 43 | 2 | $0.37 | 2.0 | typescript | ok |
| PR Label Assigner | typescript-bun | opus47-1m-high | 7.3min | 44 | 0 | $1.86 | 4.0 | typescript | ok |
| PR Label Assigner | typescript-bun | opus47-1m-medium | 9.0min | 30 | 0 | $1.06 | 4.0 | typescript | ok |
| PR Label Assigner | typescript-bun | opus47-1m-xhigh | 10.4min | 57 | 0 | $3.05 | 4.5 | typescript | ok |
| PR Label Assigner | typescript-bun | opus47-200k-medium | 4.5min | 28 | 0 | $1.00 | 4.0 | typescript | ok |
| PR Label Assigner | typescript-bun | sonnet46-1m-medium | 4.7min | 27 | 0 | $0.67 | 3.0 | typescript | ok |
| PR Label Assigner | typescript-bun | sonnet46-200k-medium | 6.9min | 41 | 3 | $0.87 | 2.5 | typescript | ok |
| Secret Rotation Validator | bash | haiku45-200k-na | 7.7min | 56 | 3 | $0.49 | 2.0 | bash | ok |
| Secret Rotation Validator | bash | opus47-1m-high | 4.6min | 22 | 0 | $1.06 | 3.0 | bash | ok |
| Secret Rotation Validator | bash | opus47-1m-medium | 5.4min | 24 | 0 | $1.09 | 3.0 | bash | ok |
| Secret Rotation Validator | bash | opus47-1m-xhigh | 9.4min | 35 | 0 | $2.40 | 3.5 | bash | ok |
| Secret Rotation Validator | bash | opus47-200k-medium | 3.4min | 29 | 2 | $1.10 | 3.0 | bash | ok |
| Secret Rotation Validator | bash | sonnet46-1m-medium | 10.0min | 41 | 6 | $1.10 | 3.5 | bash | ok |
| Secret Rotation Validator | bash | sonnet46-200k-medium | 8.6min | 39 | 5 | $1.11 | 4.0 | bash | ok |
| Secret Rotation Validator | default | haiku45-200k-na | 4.2min | 38 | 3 | $0.34 | 1.5 | python | ok |
| Secret Rotation Validator | default | opus47-1m-high | 7.9min | 30 | 1 | $1.93 | 4.5 | python | ok |
| Secret Rotation Validator | default | opus47-1m-medium | 7.0min | 19 | 0 | $0.88 | 2.0 | python | ok |
| Secret Rotation Validator | default | opus47-1m-xhigh | 9.1min | 45 | 0 | $2.54 | 4.0 | python | ok |
| Secret Rotation Validator | default | opus47-200k-medium | 5.5min | 25 | 0 | $1.27 | 4.0 | python | ok |
| Secret Rotation Validator | default | sonnet46-1m-medium | 8.0min | 31 | 4 | $1.16 | 4.5 | python | ok |
| Secret Rotation Validator | default | sonnet46-200k-medium | 8.5min | 42 | 2 | $1.25 | 3.5 | python | ok |
| Secret Rotation Validator | powershell | haiku45-200k-na | 6.8min | 56 | 5 | $0.49 | 2.0 | powershell | ok |
| Secret Rotation Validator | powershell | haiku45-200k-na | 11.4min | 40 | 3 | $0.39 | 3.0 | powershell | ok |
| Secret Rotation Validator | powershell | opus47-1m-high | 6.7min | 36 | 0 | $1.89 | 4.5 | powershell | ok |
| Secret Rotation Validator | powershell | opus47-1m-high | 8.2min | 41 | 0 | $2.29 | 4.5 | powershell | ok |
| Secret Rotation Validator | powershell | opus47-1m-medium | 22.5min | 31 | 0 | $1.27 | 4.0 | powershell | ok |
| Secret Rotation Validator | powershell | opus47-1m-medium | 17.8min | 38 | 2 | $1.70 | 4.0 | powershell | ok |
| Secret Rotation Validator | powershell | opus47-1m-xhigh | 11.0min | 46 | 2 | $3.07 | 4.5 | powershell | ok |
| Secret Rotation Validator | powershell | opus47-1m-xhigh | 9.9min | 38 | 0 | $2.58 | 4.0 | powershell | ok |
| Secret Rotation Validator | powershell | opus47-200k-medium | 4.9min | 32 | 0 | $1.40 | 3.5 | powershell | ok |
| Secret Rotation Validator | powershell | opus47-200k-medium | 4.0min | 19 | 0 | $1.06 | 3.5 | powershell | ok |
| Secret Rotation Validator | powershell | sonnet46-1m-medium | 9.9min | 36 | 1 | $1.35 | 3.5 | powershell | ok |
| Secret Rotation Validator | powershell | sonnet46-1m-medium | 7.8min | 33 | 1 | $0.94 | 2.5 | powershell | ok |
| Secret Rotation Validator | powershell | sonnet46-200k-medium | 3.4min | 22 | 1 | $0.47 | 2.5 | powershell | ok |
| Secret Rotation Validator | powershell | sonnet46-200k-medium | 8.0min | 19 | 0 | $0.96 | 3.0 | powershell | ok |
| Secret Rotation Validator | typescript-bun | haiku45-200k-na | 3.8min | 55 | 6 | $0.42 | 2.0 | typescript | ok |
| Secret Rotation Validator | typescript-bun | opus47-1m-high | 9.5min | 55 | 0 | $2.95 | 3.5 | typescript | ok |
| Secret Rotation Validator | typescript-bun | opus47-1m-medium | 7.4min | 35 | 2 | $1.46 | 4.0 | typescript | ok |
| Secret Rotation Validator | typescript-bun | opus47-1m-xhigh | 8.2min | 46 | 1 | $2.52 | 4.5 | typescript | ok |
| Secret Rotation Validator | typescript-bun | opus47-200k-medium | 6.9min | 36 | 0 | $1.92 | 3.5 | typescript | ok |
| Secret Rotation Validator | typescript-bun | sonnet46-1m-medium | 6.6min | 37 | 3 | $0.78 | 3.0 | typescript | ok |
| Secret Rotation Validator | typescript-bun | sonnet46-200k-medium | 8.9min | 30 | 1 | $1.07 | 4.0 | typescript | ok |
| Semantic Version Bumper | bash | haiku45-200k-na | 6.3min | 48 | 1 | $0.45 | 2.5 | bash | ok |
| Semantic Version Bumper | bash | opus47-1m-high | 6.3min | 31 | 1 | $1.44 | 4.0 | bash | ok |
| Semantic Version Bumper | bash | opus47-1m-medium | 4.2min | 30 | 2 | $1.07 | 2.5 | bash | ok |
| Semantic Version Bumper | bash | opus47-1m-xhigh | 17.2min | 48 | 2 | $2.95 | 4.5 | bash | ok |
| Semantic Version Bumper | bash | opus47-200k-medium | 4.1min | 25 | 0 | $1.02 | 4.0 | bash | ok |
| Semantic Version Bumper | bash | sonnet46-1m-medium | 10.0min | 40 | 4 | $1.38 | 3.0 | bash | ok |
| Semantic Version Bumper | bash | sonnet46-200k-medium | 4.5min | 36 | 2 | $0.64 | 3.0 | bash | ok |
| Semantic Version Bumper | default | haiku45-200k-na | 59.1min | 97 | 12 | $0.84 | — | javascript | ok |
| Semantic Version Bumper | default | opus47-1m-high | 7.1min | 31 | 0 | $1.85 | — | javascript | ok |
| Semantic Version Bumper | default | opus47-1m-medium | 4.1min | 22 | 0 | $0.93 | 4.0 | python | ok |
| Semantic Version Bumper | default | opus47-1m-xhigh | 6.8min | 45 | 0 | $2.45 | 4.5 | python | ok |
| Semantic Version Bumper | default | opus47-200k-medium | 4.2min | 31 | 1 | $1.21 | — | javascript | ok |
| Semantic Version Bumper | default | sonnet46-1m-medium | 4.6min | 33 | 3 | $0.67 | 2.0 | python | ok |
| Semantic Version Bumper | default | sonnet46-200k-medium | 5.8min | 42 | 3 | $0.94 | 4.0 | python | ok |
| Semantic Version Bumper | powershell | haiku45-200k-na | 6.3min | 65 | 4 | $0.57 | — | powershell | ok |
| Semantic Version Bumper | powershell | haiku45-200k-na | 15.1min | 92 | 7 | $0.93 | — | powershell | ok |
| Semantic Version Bumper | powershell | opus47-1m-high | 8.0min | 40 | 0 | $2.23 | 4.5 | powershell | ok |
| Semantic Version Bumper | powershell | opus47-1m-high | 6.1min | 34 | 0 | $1.78 | 4.5 | powershell | ok |
| Semantic Version Bumper | powershell | opus47-1m-medium | 8.6min | 35 | 0 | $1.69 | 4.5 | powershell | ok |
| Semantic Version Bumper | powershell | opus47-1m-medium | 8.0min | 37 | 1 | $1.75 | 4.0 | powershell | ok |
| Semantic Version Bumper | powershell | opus47-1m-xhigh | 7.7min | 38 | 0 | $2.27 | 4.5 | powershell | ok |
| Semantic Version Bumper | powershell | opus47-1m-xhigh | 8.0min | 49 | 0 | $2.90 | 3.5 | powershell | ok |
| Semantic Version Bumper | powershell | opus47-200k-medium | 6.3min | 33 | 0 | $1.44 | 4.0 | powershell | ok |
| Semantic Version Bumper | powershell | opus47-200k-medium | 5.3min | 27 | 0 | $1.36 | 4.0 | powershell | ok |
| Semantic Version Bumper | powershell | sonnet46-1m-medium | 8.3min | 27 | 1 | $0.98 | 4.0 | powershell | ok |
| Semantic Version Bumper | powershell | sonnet46-1m-medium | 11.9min | 40 | 1 | $1.69 | 3.5 | powershell | ok |
| Semantic Version Bumper | powershell | sonnet46-200k-medium | 3.9min | 23 | 1 | $0.44 | 4.0 | powershell | ok |
| Semantic Version Bumper | powershell | sonnet46-200k-medium | 5.9min | 33 | 2 | $0.87 | 4.5 | powershell | ok |
| Semantic Version Bumper | typescript-bun | haiku45-200k-na | 7.6min | 74 | 10 | $0.62 | 2.0 | typescript | ok |
| Semantic Version Bumper | typescript-bun | opus47-1m-high | 10.9min | 62 | 1 | $2.99 | 4.5 | typescript | ok |
| Semantic Version Bumper | typescript-bun | opus47-1m-medium | 5.6min | 33 | 0 | $1.31 | 4.0 | typescript | ok |
| Semantic Version Bumper | typescript-bun | opus47-1m-xhigh | 14.3min | 80 | 1 | $4.21 | 4.5 | typescript | ok |
| Semantic Version Bumper | typescript-bun | opus47-200k-medium | 5.1min | 35 | 1 | $1.58 | 3.5 | typescript | ok |
| Semantic Version Bumper | typescript-bun | sonnet46-1m-medium | 8.5min | 42 | 4 | $0.92 | 4.0 | typescript | ok |
| Semantic Version Bumper | typescript-bun | sonnet46-200k-medium | 7.4min | 33 | 4 | $0.68 | 2.0 | typescript | ok |
| Test Results Aggregator | bash | haiku45-200k-na | 7.4min | 77 | 5 | $0.64 | 2.5 | bash | ok |
| Test Results Aggregator | bash | opus47-1m-high | 11.3min | 48 | 1 | $2.37 | 3.5 | bash | ok |
| Test Results Aggregator | bash | opus47-1m-medium | 6.7min | 35 | 0 | $1.36 | 4.0 | bash | ok |
| Test Results Aggregator | bash | opus47-1m-xhigh | 16.5min | 79 | 1 | $5.09 | 4.5 | bash | ok |
| Test Results Aggregator | bash | opus47-200k-medium | 4.3min | 29 | 1 | $1.12 | 4.0 | bash | ok |
| Test Results Aggregator | bash | sonnet46-1m-medium | 10.7min | 39 | 5 | $1.42 | 3.5 | bash | ok |
| Test Results Aggregator | bash | sonnet46-200k-medium | 6.3min | 23 | 0 | $0.78 | 4.0 | bash | ok |
| Test Results Aggregator | default | haiku45-200k-na | 4.3min | 60 | 5 | $0.51 | 2.5 | python | ok |
| Test Results Aggregator | default | opus47-1m-high | 6.5min | 44 | 0 | $2.37 | 4.0 | python | ok |
| Test Results Aggregator | default | opus47-1m-medium | 6.9min | 31 | 0 | $1.28 | 3.5 | python | ok |
| Test Results Aggregator | default | opus47-1m-xhigh | 9.2min | 54 | 1 | $2.81 | 4.0 | python | ok |
| Test Results Aggregator | default | opus47-200k-medium | 6.1min | 35 | 1 | $1.68 | 4.0 | python | ok |
| Test Results Aggregator | default | sonnet46-1m-medium | 8.4min | 25 | 1 | $0.90 | 3.5 | python | ok |
| Test Results Aggregator | default | sonnet46-200k-medium | 6.5min | 43 | 4 | $1.17 | 4.5 | python | ok |
| Test Results Aggregator | powershell | haiku45-200k-na | 6.6min | 63 | 2 | $0.62 | 1.5 | powershell | ok |
| Test Results Aggregator | powershell | haiku45-200k-na | 7.1min | 63 | 5 | $0.63 | — | powershell | ok |
| Test Results Aggregator | powershell | opus47-1m-high | 11.1min | 49 | 1 | $3.14 | 4.0 | powershell | ok |
| Test Results Aggregator | powershell | opus47-1m-high | 15.9min | 69 | 1 | $3.91 | 4.0 | powershell | ok |
| Test Results Aggregator | powershell | opus47-1m-medium | 9.6min | 27 | 0 | $1.44 | 4.0 | powershell | ok |
| Test Results Aggregator | powershell | opus47-1m-medium | 9.4min | 37 | 0 | $1.76 | 3.5 | powershell | ok |
| Test Results Aggregator | powershell | opus47-1m-xhigh | 17.3min | 74 | 0 | $4.47 | 3.5 | powershell | ok |
| Test Results Aggregator | powershell | opus47-1m-xhigh | 15.2min | 63 | 0 | $5.47 | 4.0 | powershell | ok |
| Test Results Aggregator | powershell | opus47-200k-medium | 7.1min | 37 | 1 | $1.79 | 3.5 | powershell | ok |
| Test Results Aggregator | powershell | opus47-200k-medium | 7.0min | 31 | 0 | $1.64 | 3.5 | powershell | ok |
| Test Results Aggregator | powershell | sonnet46-1m-medium | 8.3min | 24 | 1 | $0.99 | 3.0 | powershell | ok |
| Test Results Aggregator | powershell | sonnet46-1m-medium | 11.4min | 25 | 2 | $1.32 | 4.0 | powershell | ok |
| Test Results Aggregator | powershell | sonnet46-200k-medium | 7.7min | 27 | 0 | $1.03 | 4.0 | powershell | ok |
| Test Results Aggregator | powershell | sonnet46-200k-medium | 11.7min | 32 | 1 | $1.40 | 4.5 | powershell | ok |
| Test Results Aggregator | typescript-bun | haiku45-200k-na | 7.8min | 67 | 9 | $0.60 | 2.0 | typescript | ok |
| Test Results Aggregator | typescript-bun | opus47-1m-high | 8.6min | 44 | 0 | $1.52 | 4.0 | typescript | ok |
| Test Results Aggregator | typescript-bun | opus47-1m-medium | 8.4min | 35 | 0 | $1.49 | 4.0 | typescript | ok |
| Test Results Aggregator | typescript-bun | opus47-1m-xhigh | 20.8min | 103 | 1 | $6.31 | 4.5 | typescript | ok |
| Test Results Aggregator | typescript-bun | opus47-200k-medium | 6.4min | 33 | 1 | $1.53 | 3.5 | typescript | ok |
| Test Results Aggregator | typescript-bun | sonnet46-1m-medium | 8.5min | 34 | 2 | $1.11 | 3.5 | typescript | ok |
| Test Results Aggregator | typescript-bun | sonnet46-200k-medium | 11.0min | 39 | 3 | $1.47 | 4.0 | typescript | ok |


<details>
<summary>Sorted by cost (cheapest first)</summary>

| Task | Language | Model | Duration | Turns | Errors | Cost | Tests Quality | Chosen | Status |
|------|----------|-------|----------|-------|--------|------|-----------|--------|--------|
| PR Label Assigner | powershell | haiku45-200k-na | 3.0min | 26 | 1 | $0.23 | 2.5 | powershell | ok |
| PR Label Assigner | default | haiku45-200k-na | 2.9min | 27 | 3 | $0.25 | 1.5 | python | ok |
| Environment Matrix Generator | powershell | sonnet46-200k-medium | 2.1min | 14 | 1 | $0.28 | 2.5 | powershell | ok |
| Artifact Cleanup Script | powershell | haiku45-200k-na | 3.2min | 29 | 2 | $0.28 | 1.5 | powershell | ok |
| Artifact Cleanup Script | powershell | haiku45-200k-na | 7.8min | 31 | 2 | $0.28 | — | powershell | ok |
| Artifact Cleanup Script | typescript-bun | haiku45-200k-na | 3.8min | 39 | 3 | $0.33 | 2.0 | typescript | ok |
| Environment Matrix Generator | powershell | sonnet46-1m-medium | 2.7min | 16 | 1 | $0.34 | 2.5 | powershell | ok |
| Secret Rotation Validator | default | haiku45-200k-na | 4.2min | 38 | 3 | $0.34 | 1.5 | python | ok |
| Environment Matrix Generator | bash | sonnet46-200k-medium | 4.2min | 7 | 1 | $0.35 | — | bash | cli_error |
| Dependency License Checker | bash | haiku45-200k-na | 14.2min | 47 | 2 | $0.36 | 2.5 | bash | ok |
| PR Label Assigner | typescript-bun | haiku45-200k-na | 6.0min | 43 | 2 | $0.37 | 2.0 | typescript | ok |
| Environment Matrix Generator | default | haiku45-200k-na | 4.0min | 42 | 4 | $0.38 | 2.0 | python | ok |
| PR Label Assigner | powershell | sonnet46-200k-medium | 2.9min | 19 | 0 | $0.38 | 1.5 | powershell | ok |
| PR Label Assigner | powershell | haiku45-200k-na | 5.2min | 44 | 1 | $0.38 | 2.0 | powershell | ok |
| Dependency License Checker | typescript-bun | haiku45-200k-na | 4.3min | 48 | 1 | $0.39 | 2.0 | typescript | ok |
| Secret Rotation Validator | powershell | haiku45-200k-na | 11.4min | 40 | 3 | $0.39 | 3.0 | powershell | ok |
| Environment Matrix Generator | powershell | haiku45-200k-na | 4.6min | 43 | 3 | $0.39 | — | powershell | ok |
| Dependency License Checker | default | haiku45-200k-na | 4.0min | 47 | 7 | $0.40 | 2.5 | python | ok |
| Environment Matrix Generator | default | sonnet46-200k-medium | 2.9min | 23 | 2 | $0.41 | 2.0 | python | ok |
| Dependency License Checker | powershell | haiku45-200k-na | 4.0min | 55 | 2 | $0.42 | 2.5 | powershell | ok |
| Secret Rotation Validator | typescript-bun | haiku45-200k-na | 3.8min | 55 | 6 | $0.42 | 2.0 | typescript | ok |
| Artifact Cleanup Script | bash | haiku45-200k-na | 6.6min | 51 | 3 | $0.43 | 2.5 | bash | ok |
| Semantic Version Bumper | powershell | sonnet46-200k-medium | 3.9min | 23 | 1 | $0.44 | 4.0 | powershell | ok |
| Semantic Version Bumper | bash | haiku45-200k-na | 6.3min | 48 | 1 | $0.45 | 2.5 | bash | ok |
| Artifact Cleanup Script | powershell | sonnet46-1m-medium | 3.1min | 18 | 2 | $0.46 | 3.0 | powershell | ok |
| Artifact Cleanup Script | default | haiku45-200k-na | 4.8min | 45 | 4 | $0.46 | 2.5 | python | ok |
| Secret Rotation Validator | powershell | sonnet46-200k-medium | 3.4min | 22 | 1 | $0.47 | 2.5 | powershell | ok |
| Secret Rotation Validator | powershell | haiku45-200k-na | 6.8min | 56 | 5 | $0.49 | 2.0 | powershell | ok |
| Artifact Cleanup Script | typescript-bun | sonnet46-200k-medium | 3.6min | 26 | 3 | $0.49 | 3.0 | typescript | ok |
| Secret Rotation Validator | bash | haiku45-200k-na | 7.7min | 56 | 3 | $0.49 | 2.0 | bash | ok |
| PR Label Assigner | bash | sonnet46-1m-medium | 3.1min | 28 | 4 | $0.50 | 2.0 | bash | ok |
| PR Label Assigner | bash | haiku45-200k-na | 7.1min | 62 | 4 | $0.50 | 2.0 | bash | ok |
| Test Results Aggregator | default | haiku45-200k-na | 4.3min | 60 | 5 | $0.51 | 2.5 | python | ok |
| Environment Matrix Generator | default | sonnet46-1m-medium | 3.7min | 25 | 3 | $0.56 | 2.0 | python | ok |
| Environment Matrix Generator | powershell | haiku45-200k-na | 6.1min | 49 | 6 | $0.56 | 3.5 | powershell | ok |
| Semantic Version Bumper | powershell | haiku45-200k-na | 6.3min | 65 | 4 | $0.57 | — | powershell | ok |
| Dependency License Checker | powershell | haiku45-200k-na | 7.6min | 70 | 1 | $0.58 | 2.5 | powershell | ok |
| PR Label Assigner | powershell | sonnet46-1m-medium | 4.4min | 28 | 1 | $0.59 | 2.5 | powershell | ok |
| Test Results Aggregator | typescript-bun | haiku45-200k-na | 7.8min | 67 | 9 | $0.60 | 2.0 | typescript | ok |
| Artifact Cleanup Script | bash | sonnet46-200k-medium | 4.4min | 31 | 2 | $0.61 | 2.5 | bash | ok |
| Semantic Version Bumper | typescript-bun | haiku45-200k-na | 7.6min | 74 | 10 | $0.62 | 2.0 | typescript | ok |
| Test Results Aggregator | powershell | haiku45-200k-na | 6.6min | 63 | 2 | $0.62 | 1.5 | powershell | ok |
| Test Results Aggregator | powershell | haiku45-200k-na | 7.1min | 63 | 5 | $0.63 | — | powershell | ok |
| Test Results Aggregator | bash | haiku45-200k-na | 7.4min | 77 | 5 | $0.64 | 2.5 | bash | ok |
| Semantic Version Bumper | bash | sonnet46-200k-medium | 4.5min | 36 | 2 | $0.64 | 3.0 | bash | ok |
| PR Label Assigner | default | sonnet46-200k-medium | 4.4min | 34 | 1 | $0.66 | 2.5 | python | ok |
| Semantic Version Bumper | default | sonnet46-1m-medium | 4.6min | 33 | 3 | $0.67 | 2.0 | python | ok |
| PR Label Assigner | typescript-bun | sonnet46-1m-medium | 4.7min | 27 | 0 | $0.67 | 3.0 | typescript | ok |
| Semantic Version Bumper | typescript-bun | sonnet46-200k-medium | 7.4min | 33 | 4 | $0.68 | 2.0 | typescript | ok |
| Environment Matrix Generator | typescript-bun | haiku45-200k-na | 8.2min | 73 | 4 | $0.68 | 3.0 | typescript | ok |
| PR Label Assigner | default | opus47-200k-medium | 3.2min | 21 | 0 | $0.70 | 2.0 | python | ok |
| Environment Matrix Generator | bash | haiku45-200k-na | 322.8min | 85 | 10 | $0.75 | 2.0 | bash | timeout |
| Test Results Aggregator | bash | sonnet46-200k-medium | 6.3min | 23 | 0 | $0.78 | 4.0 | bash | ok |
| Secret Rotation Validator | typescript-bun | sonnet46-1m-medium | 6.6min | 37 | 3 | $0.78 | 3.0 | typescript | ok |
| PR Label Assigner | default | opus47-1m-medium | 3.1min | 23 | 0 | $0.83 | 2.0 | python | ok |
| Semantic Version Bumper | default | haiku45-200k-na | 59.1min | 97 | 12 | $0.84 | — | javascript | ok |
| Artifact Cleanup Script | default | opus47-1m-medium | 3.2min | 19 | 0 | $0.85 | 4.0 | python | ok |
| PR Label Assigner | typescript-bun | sonnet46-200k-medium | 6.9min | 41 | 3 | $0.87 | 2.5 | typescript | ok |
| Semantic Version Bumper | powershell | sonnet46-200k-medium | 5.9min | 33 | 2 | $0.87 | 4.5 | powershell | ok |
| PR Label Assigner | bash | opus47-1m-medium | 6.2min | 23 | 1 | $0.87 | 4.0 | bash | ok |
| Environment Matrix Generator | bash | opus47-1m-medium | 3.5min | 23 | 1 | $0.88 | 3.0 | bash | ok |
| Secret Rotation Validator | default | opus47-1m-medium | 7.0min | 19 | 0 | $0.88 | 2.0 | python | ok |
| Environment Matrix Generator | typescript-bun | sonnet46-200k-medium | 6.4min | 31 | 2 | $0.90 | 3.5 | typescript | ok |
| PR Label Assigner | bash | sonnet46-200k-medium | 7.2min | 44 | 3 | $0.90 | 4.0 | bash | ok |
| Test Results Aggregator | default | sonnet46-1m-medium | 8.4min | 25 | 1 | $0.90 | 3.5 | python | ok |
| Semantic Version Bumper | typescript-bun | sonnet46-1m-medium | 8.5min | 42 | 4 | $0.92 | 4.0 | typescript | ok |
| Dependency License Checker | bash | opus47-200k-medium | 7.5min | 26 | 1 | $0.92 | 3.0 | bash | ok |
| Artifact Cleanup Script | bash | opus47-1m-medium | 3.1min | 24 | 3 | $0.92 | 3.0 | bash | ok |
| Artifact Cleanup Script | typescript-bun | opus47-200k-medium | 4.4min | 22 | 0 | $0.92 | 4.0 | typescript | ok |
| Semantic Version Bumper | powershell | haiku45-200k-na | 15.1min | 92 | 7 | $0.93 | — | powershell | ok |
| Dependency License Checker | typescript-bun | sonnet46-200k-medium | 6.8min | 35 | 2 | $0.93 | 3.5 | typescript | ok |
| Semantic Version Bumper | default | opus47-1m-medium | 4.1min | 22 | 0 | $0.93 | 4.0 | python | ok |
| Artifact Cleanup Script | powershell | sonnet46-200k-medium | 6.0min | 50 | 1 | $0.94 | 4.0 | powershell | ok |
| Secret Rotation Validator | powershell | sonnet46-1m-medium | 7.8min | 33 | 1 | $0.94 | 2.5 | powershell | ok |
| Semantic Version Bumper | default | sonnet46-200k-medium | 5.8min | 42 | 3 | $0.94 | 4.0 | python | ok |
| Artifact Cleanup Script | powershell | opus47-1m-medium | 4.1min | 20 | 0 | $0.96 | 4.0 | powershell | ok |
| Secret Rotation Validator | powershell | sonnet46-200k-medium | 8.0min | 19 | 0 | $0.96 | 3.0 | powershell | ok |
| Dependency License Checker | bash | sonnet46-200k-medium | 6.9min | 34 | 2 | $0.97 | 2.0 | bash | ok |
| Dependency License Checker | default | opus47-200k-medium | 4.1min | 24 | 0 | $0.97 | 4.5 | python | ok |
| Semantic Version Bumper | powershell | sonnet46-1m-medium | 8.3min | 27 | 1 | $0.98 | 4.0 | powershell | ok |
| Test Results Aggregator | powershell | sonnet46-1m-medium | 8.3min | 24 | 1 | $0.99 | 3.0 | powershell | ok |
| Environment Matrix Generator | powershell | sonnet46-200k-medium | 8.0min | 25 | 1 | $1.00 | 4.0 | powershell | ok |
| PR Label Assigner | typescript-bun | opus47-200k-medium | 4.5min | 28 | 0 | $1.00 | 4.0 | typescript | ok |
| Dependency License Checker | powershell | opus47-1m-medium | 6.6min | 23 | 0 | $1.00 | 3.5 | powershell | ok |
| Semantic Version Bumper | bash | opus47-200k-medium | 4.1min | 25 | 0 | $1.02 | 4.0 | bash | ok |
| Artifact Cleanup Script | default | sonnet46-1m-medium | 6.8min | 32 | 2 | $1.02 | 4.5 | python | ok |
| Test Results Aggregator | powershell | sonnet46-200k-medium | 7.7min | 27 | 0 | $1.03 | 4.0 | powershell | ok |
| Environment Matrix Generator | powershell | sonnet46-1m-medium | 8.1min | 36 | 7 | $1.04 | 4.0 | powershell | ok |
| Dependency License Checker | powershell | sonnet46-200k-medium | 9.0min | 27 | 1 | $1.04 | 3.5 | powershell | ok |
| Environment Matrix Generator | default | opus47-200k-medium | 5.0min | 28 | 1 | $1.05 | 4.0 | python | ok |
| Environment Matrix Generator | bash | opus47-200k-medium | 2.9min | 23 | 0 | $1.05 | 3.5 | bash | ok |
| Dependency License Checker | powershell | sonnet46-1m-medium | 7.1min | 43 | 1 | $1.05 | 4.5 | powershell | ok |
| Secret Rotation Validator | powershell | opus47-200k-medium | 4.0min | 19 | 0 | $1.06 | 3.5 | powershell | ok |
| Secret Rotation Validator | bash | opus47-1m-high | 4.6min | 22 | 0 | $1.06 | 3.0 | bash | ok |
| PR Label Assigner | typescript-bun | opus47-1m-medium | 9.0min | 30 | 0 | $1.06 | 4.0 | typescript | ok |
| Semantic Version Bumper | bash | opus47-1m-medium | 4.2min | 30 | 2 | $1.07 | 2.5 | bash | ok |
| Secret Rotation Validator | typescript-bun | sonnet46-200k-medium | 8.9min | 30 | 1 | $1.07 | 4.0 | typescript | ok |
| Environment Matrix Generator | typescript-bun | opus47-1m-medium | 7.4min | 29 | 0 | $1.07 | 3.0 | typescript | ok |
| Dependency License Checker | default | sonnet46-1m-medium | 6.7min | 43 | 3 | $1.07 | 3.5 | python | ok |
| Artifact Cleanup Script | powershell | opus47-1m-medium | 4.7min | 22 | 0 | $1.08 | 3.5 | powershell | ok |
| Artifact Cleanup Script | powershell | sonnet46-1m-medium | 7.8min | 28 | 0 | $1.09 | 3.5 | powershell | ok |
| Artifact Cleanup Script | powershell | opus47-200k-medium | 4.0min | 23 | 0 | $1.09 | 3.5 | powershell | ok |
| Dependency License Checker | powershell | sonnet46-200k-medium | 8.6min | 40 | 0 | $1.09 | 3.0 | powershell | ok |
| Secret Rotation Validator | bash | opus47-1m-medium | 5.4min | 24 | 0 | $1.09 | 3.0 | bash | ok |
| Secret Rotation Validator | bash | sonnet46-1m-medium | 10.0min | 41 | 6 | $1.10 | 3.5 | bash | ok |
| Secret Rotation Validator | bash | opus47-200k-medium | 3.4min | 29 | 2 | $1.10 | 3.0 | bash | ok |
| Dependency License Checker | typescript-bun | opus47-200k-medium | 4.8min | 29 | 0 | $1.10 | 4.0 | typescript | ok |
| Secret Rotation Validator | bash | sonnet46-200k-medium | 8.6min | 39 | 5 | $1.11 | 4.0 | bash | ok |
| Test Results Aggregator | typescript-bun | sonnet46-1m-medium | 8.5min | 34 | 2 | $1.11 | 3.5 | typescript | ok |
| PR Label Assigner | powershell | sonnet46-200k-medium | 8.4min | 35 | 3 | $1.11 | 4.0 | powershell | ok |
| PR Label Assigner | powershell | opus47-1m-medium | 5.1min | 27 | 0 | $1.11 | 4.0 | powershell | ok |
| Test Results Aggregator | bash | opus47-200k-medium | 4.3min | 29 | 1 | $1.12 | 4.0 | bash | ok |
| Environment Matrix Generator | default | opus47-1m-medium | 5.4min | 26 | 0 | $1.12 | 4.0 | python | ok |
| Artifact Cleanup Script | default | sonnet46-200k-medium | 8.2min | 28 | 2 | $1.14 | 4.0 | python | ok |
| Secret Rotation Validator | default | sonnet46-1m-medium | 8.0min | 31 | 4 | $1.16 | 4.5 | python | ok |
| Test Results Aggregator | default | sonnet46-200k-medium | 6.5min | 43 | 4 | $1.17 | 4.5 | python | ok |
| Dependency License Checker | powershell | opus47-1m-medium | 4.9min | 26 | 0 | $1.18 | 4.0 | powershell | ok |
| PR Label Assigner | bash | opus47-200k-medium | 5.0min | 29 | 3 | $1.18 | 2.0 | bash | ok |
| Semantic Version Bumper | default | opus47-200k-medium | 4.2min | 31 | 1 | $1.21 | — | javascript | ok |
| Dependency License Checker | typescript-bun | sonnet46-1m-medium | 8.4min | 50 | 3 | $1.23 | 4.0 | typescript | ok |
| Secret Rotation Validator | default | sonnet46-200k-medium | 8.5min | 42 | 2 | $1.25 | 3.5 | python | ok |
| Artifact Cleanup Script | typescript-bun | opus47-1m-medium | 7.2min | 29 | 0 | $1.25 | 3.5 | typescript | ok |
| Artifact Cleanup Script | powershell | sonnet46-200k-medium | 8.4min | 31 | 2 | $1.25 | 4.0 | powershell | ok |
| Artifact Cleanup Script | bash | opus47-200k-medium | 5.8min | 25 | 1 | $1.26 | 3.0 | bash | ok |
| Secret Rotation Validator | default | opus47-200k-medium | 5.5min | 25 | 0 | $1.27 | 4.0 | python | ok |
| Secret Rotation Validator | powershell | opus47-1m-medium | 22.5min | 31 | 0 | $1.27 | 4.0 | powershell | ok |
| Dependency License Checker | bash | sonnet46-1m-medium | 9.1min | 36 | 1 | $1.28 | 4.0 | bash | ok |
| Test Results Aggregator | default | opus47-1m-medium | 6.9min | 31 | 0 | $1.28 | 3.5 | python | ok |
| Environment Matrix Generator | powershell | opus47-1m-medium | 4.6min | 29 | 2 | $1.30 | 3.5 | powershell | ok |
| Artifact Cleanup Script | default | opus47-200k-medium | 5.0min | 23 | 0 | $1.30 | 4.5 | python | ok |
| Semantic Version Bumper | typescript-bun | opus47-1m-medium | 5.6min | 33 | 0 | $1.31 | 4.0 | typescript | ok |
| Test Results Aggregator | powershell | sonnet46-1m-medium | 11.4min | 25 | 2 | $1.32 | 4.0 | powershell | ok |
| PR Label Assigner | default | opus47-1m-high | 7.6min | 23 | 1 | $1.32 | 4.0 | python | ok |
| Dependency License Checker | default | opus47-1m-medium | 8.2min | 34 | 2 | $1.33 | 4.0 | python | ok |
| PR Label Assigner | powershell | opus47-1m-medium | 7.4min | 29 | 0 | $1.33 | 3.5 | powershell | ok |
| PR Label Assigner | powershell | opus47-200k-medium | 5.3min | 27 | 0 | $1.34 | 4.0 | powershell | ok |
| Dependency License Checker | typescript-bun | opus47-1m-medium | 8.2min | 32 | 1 | $1.34 | 4.0 | typescript | ok |
| Environment Matrix Generator | typescript-bun | sonnet46-1m-medium | 12.2min | 42 | 2 | $1.34 | 3.5 | typescript | ok |
| Dependency License Checker | bash | opus47-1m-high | 4.0min | 30 | 0 | $1.35 | 2.5 | bash | ok |
| Secret Rotation Validator | powershell | sonnet46-1m-medium | 9.9min | 36 | 1 | $1.35 | 3.5 | powershell | ok |
| Test Results Aggregator | bash | opus47-1m-medium | 6.7min | 35 | 0 | $1.36 | 4.0 | bash | ok |
| Semantic Version Bumper | powershell | opus47-200k-medium | 5.3min | 27 | 0 | $1.36 | 4.0 | powershell | ok |
| Artifact Cleanup Script | typescript-bun | sonnet46-1m-medium | 7.9min | 49 | 4 | $1.37 | 4.0 | typescript | ok |
| Semantic Version Bumper | bash | sonnet46-1m-medium | 10.0min | 40 | 4 | $1.38 | 3.0 | bash | ok |
| PR Label Assigner | default | sonnet46-1m-medium | 9.6min | 44 | 7 | $1.38 | 3.0 | python | ok |
| Secret Rotation Validator | powershell | opus47-200k-medium | 4.9min | 32 | 0 | $1.40 | 3.5 | powershell | ok |
| Test Results Aggregator | powershell | sonnet46-200k-medium | 11.7min | 32 | 1 | $1.40 | 4.5 | powershell | ok |
| Environment Matrix Generator | typescript-bun | opus47-200k-medium | 6.5min | 36 | 1 | $1.41 | 4.0 | typescript | ok |
| Test Results Aggregator | bash | sonnet46-1m-medium | 10.7min | 39 | 5 | $1.42 | 3.5 | bash | ok |
| Environment Matrix Generator | powershell | opus47-200k-medium | 6.1min | 30 | 0 | $1.42 | 4.0 | powershell | ok |
| Semantic Version Bumper | bash | opus47-1m-high | 6.3min | 31 | 1 | $1.44 | 4.0 | bash | ok |
| Test Results Aggregator | powershell | opus47-1m-medium | 9.6min | 27 | 0 | $1.44 | 4.0 | powershell | ok |
| Semantic Version Bumper | powershell | opus47-200k-medium | 6.3min | 33 | 0 | $1.44 | 4.0 | powershell | ok |
| PR Label Assigner | bash | opus47-1m-high | 5.9min | 31 | 2 | $1.46 | 4.0 | bash | ok |
| Secret Rotation Validator | typescript-bun | opus47-1m-medium | 7.4min | 35 | 2 | $1.46 | 4.0 | typescript | ok |
| Test Results Aggregator | typescript-bun | sonnet46-200k-medium | 11.0min | 39 | 3 | $1.47 | 4.0 | typescript | ok |
| Test Results Aggregator | typescript-bun | opus47-1m-medium | 8.4min | 35 | 0 | $1.49 | 4.0 | typescript | ok |
| Environment Matrix Generator | powershell | opus47-200k-medium | 6.0min | 27 | 1 | $1.51 | 4.0 | powershell | ok |
| Test Results Aggregator | typescript-bun | opus47-1m-high | 8.6min | 44 | 0 | $1.52 | 4.0 | typescript | ok |
| Test Results Aggregator | typescript-bun | opus47-200k-medium | 6.4min | 33 | 1 | $1.53 | 3.5 | typescript | ok |
| Dependency License Checker | bash | opus47-1m-medium | 5.5min | 30 | 1 | $1.55 | 3.0 | bash | ok |
| Semantic Version Bumper | typescript-bun | opus47-200k-medium | 5.1min | 35 | 1 | $1.58 | 3.5 | typescript | ok |
| PR Label Assigner | powershell | sonnet46-1m-medium | 12.0min | 31 | 1 | $1.61 | 4.5 | powershell | ok |
| Test Results Aggregator | powershell | opus47-200k-medium | 7.0min | 31 | 0 | $1.64 | 3.5 | powershell | ok |
| Artifact Cleanup Script | powershell | opus47-200k-medium | 5.4min | 32 | 0 | $1.65 | 4.0 | powershell | ok |
| PR Label Assigner | powershell | opus47-1m-high | 5.7min | 29 | 1 | $1.67 | 4.5 | powershell | ok |
| Test Results Aggregator | default | opus47-200k-medium | 6.1min | 35 | 1 | $1.68 | 4.0 | python | ok |
| Dependency License Checker | powershell | opus47-200k-medium | 6.3min | 34 | 1 | $1.68 | 4.0 | powershell | ok |
| Dependency License Checker | default | sonnet46-200k-medium | 11.7min | 44 | 4 | $1.68 | 4.5 | python | ok |
| Semantic Version Bumper | powershell | opus47-1m-medium | 8.6min | 35 | 0 | $1.69 | 4.5 | powershell | ok |
| Semantic Version Bumper | powershell | sonnet46-1m-medium | 11.9min | 40 | 1 | $1.69 | 3.5 | powershell | ok |
| Environment Matrix Generator | bash | opus47-1m-high | 6.6min | 42 | 0 | $1.69 | 4.0 | bash | ok |
| Secret Rotation Validator | powershell | opus47-1m-medium | 17.8min | 38 | 2 | $1.70 | 4.0 | powershell | ok |
| Semantic Version Bumper | powershell | opus47-1m-medium | 8.0min | 37 | 1 | $1.75 | 4.0 | powershell | ok |
| Test Results Aggregator | powershell | opus47-1m-medium | 9.4min | 37 | 0 | $1.76 | 3.5 | powershell | ok |
| Semantic Version Bumper | powershell | opus47-1m-high | 6.1min | 34 | 0 | $1.78 | 4.5 | powershell | ok |
| Artifact Cleanup Script | bash | sonnet46-1m-medium | 11.6min | 45 | 6 | $1.78 | 4.0 | bash | ok |
| Dependency License Checker | powershell | sonnet46-1m-medium | 12.0min | 45 | 1 | $1.79 | 4.0 | powershell | ok |
| Test Results Aggregator | powershell | opus47-200k-medium | 7.1min | 37 | 1 | $1.79 | 3.5 | powershell | ok |
| Artifact Cleanup Script | bash | opus47-1m-xhigh | 7.6min | 34 | 1 | $1.84 | 4.0 | bash | ok |
| Semantic Version Bumper | default | opus47-1m-high | 7.1min | 31 | 0 | $1.85 | — | javascript | ok |
| PR Label Assigner | typescript-bun | opus47-1m-high | 7.3min | 44 | 0 | $1.86 | 4.0 | typescript | ok |
| Dependency License Checker | powershell | opus47-200k-medium | 8.0min | 41 | 1 | $1.86 | 3.5 | powershell | ok |
| Environment Matrix Generator | default | opus47-1m-high | 5.7min | 38 | 0 | $1.87 | 4.0 | python | ok |
| Secret Rotation Validator | powershell | opus47-1m-high | 6.7min | 36 | 0 | $1.89 | 4.5 | powershell | ok |
| Artifact Cleanup Script | default | opus47-1m-xhigh | 7.1min | 35 | 1 | $1.91 | 4.5 | python | ok |
| Secret Rotation Validator | typescript-bun | opus47-200k-medium | 6.9min | 36 | 0 | $1.92 | 3.5 | typescript | ok |
| Secret Rotation Validator | default | opus47-1m-high | 7.9min | 30 | 1 | $1.93 | 4.5 | python | ok |
| Dependency License Checker | powershell | opus47-1m-high | 7.1min | 31 | 0 | $1.93 | 4.0 | powershell | ok |
| PR Label Assigner | powershell | opus47-200k-medium | 8.5min | 38 | 0 | $1.93 | 4.0 | powershell | ok |
| Environment Matrix Generator | default | opus47-1m-xhigh | 6.8min | 34 | 2 | $2.01 | 3.0 | python | ok |
| PR Label Assigner | powershell | opus47-1m-xhigh | 7.7min | 37 | 0 | $2.01 | 4.0 | powershell | ok |
| Dependency License Checker | default | opus47-1m-xhigh | 7.5min | 40 | 0 | $2.04 | 4.0 | python | ok |
| Environment Matrix Generator | powershell | opus47-1m-high | 7.0min | 41 | 0 | $2.04 | 4.0 | powershell | ok |
| Artifact Cleanup Script | default | opus47-1m-high | 6.6min | 36 | 0 | $2.04 | 4.5 | python | ok |
| Artifact Cleanup Script | typescript-bun | opus47-1m-high | 9.2min | 39 | 0 | $2.07 | 4.5 | typescript | ok |
| Environment Matrix Generator | powershell | opus47-1m-high | 7.4min | 30 | 0 | $2.13 | 3.5 | powershell | ok |
| Environment Matrix Generator | typescript-bun | opus47-1m-high | 6.7min | 42 | 0 | $2.13 | 3.5 | typescript | ok |
| Artifact Cleanup Script | bash | opus47-1m-high | 9.1min | 44 | 0 | $2.18 | 3.5 | bash | ok |
| Dependency License Checker | bash | opus47-1m-xhigh | 39.8min | 38 | 2 | $2.19 | 2.5 | bash | ok |
| Semantic Version Bumper | powershell | opus47-1m-high | 8.0min | 40 | 0 | $2.23 | 4.5 | powershell | ok |
| PR Label Assigner | default | opus47-1m-xhigh | 7.8min | 43 | 0 | $2.25 | 4.0 | python | ok |
| Semantic Version Bumper | powershell | opus47-1m-xhigh | 7.7min | 38 | 0 | $2.27 | 4.5 | powershell | ok |
| Dependency License Checker | default | opus47-1m-high | 8.5min | 37 | 0 | $2.28 | 4.0 | python | ok |
| Secret Rotation Validator | powershell | opus47-1m-high | 8.2min | 41 | 0 | $2.29 | 4.5 | powershell | ok |
| Artifact Cleanup Script | powershell | opus47-1m-high | 9.4min | 39 | 0 | $2.30 | 4.5 | powershell | ok |
| Test Results Aggregator | default | opus47-1m-high | 6.5min | 44 | 0 | $2.37 | 4.0 | python | ok |
| Test Results Aggregator | bash | opus47-1m-high | 11.3min | 48 | 1 | $2.37 | 3.5 | bash | ok |
| Secret Rotation Validator | bash | opus47-1m-xhigh | 9.4min | 35 | 0 | $2.40 | 3.5 | bash | ok |
| Artifact Cleanup Script | typescript-bun | opus47-1m-xhigh | 8.5min | 53 | 0 | $2.41 | 4.5 | typescript | ok |
| Dependency License Checker | powershell | opus47-1m-high | 10.1min | 42 | 0 | $2.43 | 4.0 | powershell | ok |
| Semantic Version Bumper | default | opus47-1m-xhigh | 6.8min | 45 | 0 | $2.45 | 4.5 | python | ok |
| Environment Matrix Generator | bash | opus47-1m-xhigh | 8.3min | 51 | 2 | $2.49 | 3.5 | bash | ok |
| Secret Rotation Validator | typescript-bun | opus47-1m-xhigh | 8.2min | 46 | 1 | $2.52 | 4.5 | typescript | ok |
| Secret Rotation Validator | default | opus47-1m-xhigh | 9.1min | 45 | 0 | $2.54 | 4.0 | python | ok |
| Secret Rotation Validator | powershell | opus47-1m-xhigh | 9.9min | 38 | 0 | $2.58 | 4.0 | powershell | ok |
| Environment Matrix Generator | typescript-bun | opus47-1m-xhigh | 9.8min | 52 | 0 | $2.60 | 4.5 | typescript | ok |
| PR Label Assigner | powershell | opus47-1m-xhigh | 9.6min | 43 | 0 | $2.60 | 4.0 | powershell | ok |
| Test Results Aggregator | default | opus47-1m-xhigh | 9.2min | 54 | 1 | $2.81 | 4.0 | python | ok |
| Dependency License Checker | powershell | opus47-1m-xhigh | 11.2min | 48 | 0 | $2.86 | 4.0 | powershell | ok |
| Semantic Version Bumper | powershell | opus47-1m-xhigh | 8.0min | 49 | 0 | $2.90 | 3.5 | powershell | ok |
| PR Label Assigner | powershell | opus47-1m-high | 10.0min | 49 | 1 | $2.92 | 4.0 | powershell | ok |
| Semantic Version Bumper | bash | opus47-1m-xhigh | 17.2min | 48 | 2 | $2.95 | 4.5 | bash | ok |
| Secret Rotation Validator | typescript-bun | opus47-1m-high | 9.5min | 55 | 0 | $2.95 | 3.5 | typescript | ok |
| Dependency License Checker | powershell | opus47-1m-xhigh | 10.2min | 48 | 1 | $2.95 | 4.0 | powershell | ok |
| Semantic Version Bumper | typescript-bun | opus47-1m-high | 10.9min | 62 | 1 | $2.99 | 4.5 | typescript | ok |
| Environment Matrix Generator | powershell | opus47-1m-medium | 14.0min | 59 | 0 | $3.01 | 4.0 | powershell | ok |
| PR Label Assigner | typescript-bun | opus47-1m-xhigh | 10.4min | 57 | 0 | $3.05 | 4.5 | typescript | ok |
| Secret Rotation Validator | powershell | opus47-1m-xhigh | 11.0min | 46 | 2 | $3.07 | 4.5 | powershell | ok |
| Environment Matrix Generator | powershell | opus47-1m-xhigh | 10.2min | 43 | 1 | $3.08 | 4.0 | powershell | ok |
| Dependency License Checker | typescript-bun | opus47-1m-high | 10.9min | 68 | 0 | $3.08 | 4.5 | typescript | ok |
| Test Results Aggregator | powershell | opus47-1m-high | 11.1min | 49 | 1 | $3.14 | 4.0 | powershell | ok |
| PR Label Assigner | bash | opus47-1m-xhigh | 16.7min | 61 | 2 | $3.14 | 3.5 | bash | ok |
| Artifact Cleanup Script | powershell | opus47-1m-xhigh | 10.9min | 43 | 0 | $3.19 | 4.5 | powershell | ok |
| Artifact Cleanup Script | powershell | opus47-1m-xhigh | 12.0min | 51 | 1 | $3.21 | 4.0 | powershell | ok |
| Environment Matrix Generator | bash | sonnet46-1m-medium | 29.1min | 58 | 6 | $3.25 | 3.5 | bash | ok |
| Artifact Cleanup Script | powershell | opus47-1m-high | 11.7min | 54 | 1 | $3.33 | 4.0 | powershell | ok |
| Dependency License Checker | typescript-bun | opus47-1m-xhigh | 11.8min | 74 | 0 | $3.64 | 4.5 | typescript | ok |
| Test Results Aggregator | powershell | opus47-1m-high | 15.9min | 69 | 1 | $3.91 | 4.0 | powershell | ok |
| Environment Matrix Generator | powershell | opus47-1m-xhigh | 13.5min | 54 | 0 | $3.93 | 4.0 | powershell | ok |
| Semantic Version Bumper | typescript-bun | opus47-1m-xhigh | 14.3min | 80 | 1 | $4.21 | 4.5 | typescript | ok |
| Test Results Aggregator | powershell | opus47-1m-xhigh | 17.3min | 74 | 0 | $4.47 | 3.5 | powershell | ok |
| Test Results Aggregator | bash | opus47-1m-xhigh | 16.5min | 79 | 1 | $5.09 | 4.5 | bash | ok |
| Test Results Aggregator | powershell | opus47-1m-xhigh | 15.2min | 63 | 0 | $5.47 | 4.0 | powershell | ok |
| Test Results Aggregator | typescript-bun | opus47-1m-xhigh | 20.8min | 103 | 1 | $6.31 | 4.5 | typescript | ok |

</details>

<details>
<summary>Sorted by duration (fastest first)</summary>

| Task | Language | Model | Duration | Turns | Errors | Cost | Tests Quality | Chosen | Status |
|------|----------|-------|----------|-------|--------|------|-----------|--------|--------|
| Environment Matrix Generator | powershell | sonnet46-200k-medium | 2.1min | 14 | 1 | $0.28 | 2.5 | powershell | ok |
| Environment Matrix Generator | powershell | sonnet46-1m-medium | 2.7min | 16 | 1 | $0.34 | 2.5 | powershell | ok |
| PR Label Assigner | default | haiku45-200k-na | 2.9min | 27 | 3 | $0.25 | 1.5 | python | ok |
| Environment Matrix Generator | bash | opus47-200k-medium | 2.9min | 23 | 0 | $1.05 | 3.5 | bash | ok |
| PR Label Assigner | powershell | sonnet46-200k-medium | 2.9min | 19 | 0 | $0.38 | 1.5 | powershell | ok |
| Environment Matrix Generator | default | sonnet46-200k-medium | 2.9min | 23 | 2 | $0.41 | 2.0 | python | ok |
| PR Label Assigner | powershell | haiku45-200k-na | 3.0min | 26 | 1 | $0.23 | 2.5 | powershell | ok |
| PR Label Assigner | default | opus47-1m-medium | 3.1min | 23 | 0 | $0.83 | 2.0 | python | ok |
| Artifact Cleanup Script | powershell | sonnet46-1m-medium | 3.1min | 18 | 2 | $0.46 | 3.0 | powershell | ok |
| PR Label Assigner | bash | sonnet46-1m-medium | 3.1min | 28 | 4 | $0.50 | 2.0 | bash | ok |
| Artifact Cleanup Script | bash | opus47-1m-medium | 3.1min | 24 | 3 | $0.92 | 3.0 | bash | ok |
| PR Label Assigner | default | opus47-200k-medium | 3.2min | 21 | 0 | $0.70 | 2.0 | python | ok |
| Artifact Cleanup Script | default | opus47-1m-medium | 3.2min | 19 | 0 | $0.85 | 4.0 | python | ok |
| Artifact Cleanup Script | powershell | haiku45-200k-na | 3.2min | 29 | 2 | $0.28 | 1.5 | powershell | ok |
| Secret Rotation Validator | bash | opus47-200k-medium | 3.4min | 29 | 2 | $1.10 | 3.0 | bash | ok |
| Secret Rotation Validator | powershell | sonnet46-200k-medium | 3.4min | 22 | 1 | $0.47 | 2.5 | powershell | ok |
| Environment Matrix Generator | bash | opus47-1m-medium | 3.5min | 23 | 1 | $0.88 | 3.0 | bash | ok |
| Artifact Cleanup Script | typescript-bun | sonnet46-200k-medium | 3.6min | 26 | 3 | $0.49 | 3.0 | typescript | ok |
| Environment Matrix Generator | default | sonnet46-1m-medium | 3.7min | 25 | 3 | $0.56 | 2.0 | python | ok |
| Artifact Cleanup Script | typescript-bun | haiku45-200k-na | 3.8min | 39 | 3 | $0.33 | 2.0 | typescript | ok |
| Secret Rotation Validator | typescript-bun | haiku45-200k-na | 3.8min | 55 | 6 | $0.42 | 2.0 | typescript | ok |
| Semantic Version Bumper | powershell | sonnet46-200k-medium | 3.9min | 23 | 1 | $0.44 | 4.0 | powershell | ok |
| Dependency License Checker | powershell | haiku45-200k-na | 4.0min | 55 | 2 | $0.42 | 2.5 | powershell | ok |
| Artifact Cleanup Script | powershell | opus47-200k-medium | 4.0min | 23 | 0 | $1.09 | 3.5 | powershell | ok |
| Dependency License Checker | default | haiku45-200k-na | 4.0min | 47 | 7 | $0.40 | 2.5 | python | ok |
| Environment Matrix Generator | default | haiku45-200k-na | 4.0min | 42 | 4 | $0.38 | 2.0 | python | ok |
| Dependency License Checker | bash | opus47-1m-high | 4.0min | 30 | 0 | $1.35 | 2.5 | bash | ok |
| Secret Rotation Validator | powershell | opus47-200k-medium | 4.0min | 19 | 0 | $1.06 | 3.5 | powershell | ok |
| Dependency License Checker | default | opus47-200k-medium | 4.1min | 24 | 0 | $0.97 | 4.5 | python | ok |
| Semantic Version Bumper | default | opus47-1m-medium | 4.1min | 22 | 0 | $0.93 | 4.0 | python | ok |
| Artifact Cleanup Script | powershell | opus47-1m-medium | 4.1min | 20 | 0 | $0.96 | 4.0 | powershell | ok |
| Semantic Version Bumper | bash | opus47-200k-medium | 4.1min | 25 | 0 | $1.02 | 4.0 | bash | ok |
| Semantic Version Bumper | bash | opus47-1m-medium | 4.2min | 30 | 2 | $1.07 | 2.5 | bash | ok |
| Environment Matrix Generator | bash | sonnet46-200k-medium | 4.2min | 7 | 1 | $0.35 | — | bash | cli_error |
| Semantic Version Bumper | default | opus47-200k-medium | 4.2min | 31 | 1 | $1.21 | — | javascript | ok |
| Secret Rotation Validator | default | haiku45-200k-na | 4.2min | 38 | 3 | $0.34 | 1.5 | python | ok |
| Test Results Aggregator | default | haiku45-200k-na | 4.3min | 60 | 5 | $0.51 | 2.5 | python | ok |
| Dependency License Checker | typescript-bun | haiku45-200k-na | 4.3min | 48 | 1 | $0.39 | 2.0 | typescript | ok |
| Test Results Aggregator | bash | opus47-200k-medium | 4.3min | 29 | 1 | $1.12 | 4.0 | bash | ok |
| PR Label Assigner | default | sonnet46-200k-medium | 4.4min | 34 | 1 | $0.66 | 2.5 | python | ok |
| Artifact Cleanup Script | typescript-bun | opus47-200k-medium | 4.4min | 22 | 0 | $0.92 | 4.0 | typescript | ok |
| Artifact Cleanup Script | bash | sonnet46-200k-medium | 4.4min | 31 | 2 | $0.61 | 2.5 | bash | ok |
| PR Label Assigner | powershell | sonnet46-1m-medium | 4.4min | 28 | 1 | $0.59 | 2.5 | powershell | ok |
| Semantic Version Bumper | bash | sonnet46-200k-medium | 4.5min | 36 | 2 | $0.64 | 3.0 | bash | ok |
| PR Label Assigner | typescript-bun | opus47-200k-medium | 4.5min | 28 | 0 | $1.00 | 4.0 | typescript | ok |
| Environment Matrix Generator | powershell | opus47-1m-medium | 4.6min | 29 | 2 | $1.30 | 3.5 | powershell | ok |
| Environment Matrix Generator | powershell | haiku45-200k-na | 4.6min | 43 | 3 | $0.39 | — | powershell | ok |
| Secret Rotation Validator | bash | opus47-1m-high | 4.6min | 22 | 0 | $1.06 | 3.0 | bash | ok |
| Semantic Version Bumper | default | sonnet46-1m-medium | 4.6min | 33 | 3 | $0.67 | 2.0 | python | ok |
| Artifact Cleanup Script | powershell | opus47-1m-medium | 4.7min | 22 | 0 | $1.08 | 3.5 | powershell | ok |
| PR Label Assigner | typescript-bun | sonnet46-1m-medium | 4.7min | 27 | 0 | $0.67 | 3.0 | typescript | ok |
| Dependency License Checker | typescript-bun | opus47-200k-medium | 4.8min | 29 | 0 | $1.10 | 4.0 | typescript | ok |
| Artifact Cleanup Script | default | haiku45-200k-na | 4.8min | 45 | 4 | $0.46 | 2.5 | python | ok |
| Dependency License Checker | powershell | opus47-1m-medium | 4.9min | 26 | 0 | $1.18 | 4.0 | powershell | ok |
| Secret Rotation Validator | powershell | opus47-200k-medium | 4.9min | 32 | 0 | $1.40 | 3.5 | powershell | ok |
| PR Label Assigner | bash | opus47-200k-medium | 5.0min | 29 | 3 | $1.18 | 2.0 | bash | ok |
| Environment Matrix Generator | default | opus47-200k-medium | 5.0min | 28 | 1 | $1.05 | 4.0 | python | ok |
| Artifact Cleanup Script | default | opus47-200k-medium | 5.0min | 23 | 0 | $1.30 | 4.5 | python | ok |
| Semantic Version Bumper | typescript-bun | opus47-200k-medium | 5.1min | 35 | 1 | $1.58 | 3.5 | typescript | ok |
| PR Label Assigner | powershell | opus47-1m-medium | 5.1min | 27 | 0 | $1.11 | 4.0 | powershell | ok |
| PR Label Assigner | powershell | haiku45-200k-na | 5.2min | 44 | 1 | $0.38 | 2.0 | powershell | ok |
| PR Label Assigner | powershell | opus47-200k-medium | 5.3min | 27 | 0 | $1.34 | 4.0 | powershell | ok |
| Semantic Version Bumper | powershell | opus47-200k-medium | 5.3min | 27 | 0 | $1.36 | 4.0 | powershell | ok |
| Environment Matrix Generator | default | opus47-1m-medium | 5.4min | 26 | 0 | $1.12 | 4.0 | python | ok |
| Artifact Cleanup Script | powershell | opus47-200k-medium | 5.4min | 32 | 0 | $1.65 | 4.0 | powershell | ok |
| Secret Rotation Validator | bash | opus47-1m-medium | 5.4min | 24 | 0 | $1.09 | 3.0 | bash | ok |
| Secret Rotation Validator | default | opus47-200k-medium | 5.5min | 25 | 0 | $1.27 | 4.0 | python | ok |
| Dependency License Checker | bash | opus47-1m-medium | 5.5min | 30 | 1 | $1.55 | 3.0 | bash | ok |
| Semantic Version Bumper | typescript-bun | opus47-1m-medium | 5.6min | 33 | 0 | $1.31 | 4.0 | typescript | ok |
| Environment Matrix Generator | default | opus47-1m-high | 5.7min | 38 | 0 | $1.87 | 4.0 | python | ok |
| PR Label Assigner | powershell | opus47-1m-high | 5.7min | 29 | 1 | $1.67 | 4.5 | powershell | ok |
| Semantic Version Bumper | default | sonnet46-200k-medium | 5.8min | 42 | 3 | $0.94 | 4.0 | python | ok |
| Artifact Cleanup Script | bash | opus47-200k-medium | 5.8min | 25 | 1 | $1.26 | 3.0 | bash | ok |
| Semantic Version Bumper | powershell | sonnet46-200k-medium | 5.9min | 33 | 2 | $0.87 | 4.5 | powershell | ok |
| PR Label Assigner | bash | opus47-1m-high | 5.9min | 31 | 2 | $1.46 | 4.0 | bash | ok |
| Artifact Cleanup Script | powershell | sonnet46-200k-medium | 6.0min | 50 | 1 | $0.94 | 4.0 | powershell | ok |
| PR Label Assigner | typescript-bun | haiku45-200k-na | 6.0min | 43 | 2 | $0.37 | 2.0 | typescript | ok |
| Environment Matrix Generator | powershell | opus47-200k-medium | 6.0min | 27 | 1 | $1.51 | 4.0 | powershell | ok |
| Environment Matrix Generator | powershell | haiku45-200k-na | 6.1min | 49 | 6 | $0.56 | 3.5 | powershell | ok |
| Environment Matrix Generator | powershell | opus47-200k-medium | 6.1min | 30 | 0 | $1.42 | 4.0 | powershell | ok |
| Semantic Version Bumper | powershell | opus47-1m-high | 6.1min | 34 | 0 | $1.78 | 4.5 | powershell | ok |
| Test Results Aggregator | default | opus47-200k-medium | 6.1min | 35 | 1 | $1.68 | 4.0 | python | ok |
| PR Label Assigner | bash | opus47-1m-medium | 6.2min | 23 | 1 | $0.87 | 4.0 | bash | ok |
| Test Results Aggregator | bash | sonnet46-200k-medium | 6.3min | 23 | 0 | $0.78 | 4.0 | bash | ok |
| Semantic Version Bumper | bash | opus47-1m-high | 6.3min | 31 | 1 | $1.44 | 4.0 | bash | ok |
| Semantic Version Bumper | powershell | opus47-200k-medium | 6.3min | 33 | 0 | $1.44 | 4.0 | powershell | ok |
| Semantic Version Bumper | bash | haiku45-200k-na | 6.3min | 48 | 1 | $0.45 | 2.5 | bash | ok |
| Semantic Version Bumper | powershell | haiku45-200k-na | 6.3min | 65 | 4 | $0.57 | — | powershell | ok |
| Dependency License Checker | powershell | opus47-200k-medium | 6.3min | 34 | 1 | $1.68 | 4.0 | powershell | ok |
| Test Results Aggregator | typescript-bun | opus47-200k-medium | 6.4min | 33 | 1 | $1.53 | 3.5 | typescript | ok |
| Environment Matrix Generator | typescript-bun | sonnet46-200k-medium | 6.4min | 31 | 2 | $0.90 | 3.5 | typescript | ok |
| Test Results Aggregator | default | opus47-1m-high | 6.5min | 44 | 0 | $2.37 | 4.0 | python | ok |
| Environment Matrix Generator | typescript-bun | opus47-200k-medium | 6.5min | 36 | 1 | $1.41 | 4.0 | typescript | ok |
| Test Results Aggregator | default | sonnet46-200k-medium | 6.5min | 43 | 4 | $1.17 | 4.5 | python | ok |
| Secret Rotation Validator | typescript-bun | sonnet46-1m-medium | 6.6min | 37 | 3 | $0.78 | 3.0 | typescript | ok |
| Dependency License Checker | powershell | opus47-1m-medium | 6.6min | 23 | 0 | $1.00 | 3.5 | powershell | ok |
| Environment Matrix Generator | bash | opus47-1m-high | 6.6min | 42 | 0 | $1.69 | 4.0 | bash | ok |
| Artifact Cleanup Script | default | opus47-1m-high | 6.6min | 36 | 0 | $2.04 | 4.5 | python | ok |
| Test Results Aggregator | powershell | haiku45-200k-na | 6.6min | 63 | 2 | $0.62 | 1.5 | powershell | ok |
| Artifact Cleanup Script | bash | haiku45-200k-na | 6.6min | 51 | 3 | $0.43 | 2.5 | bash | ok |
| Environment Matrix Generator | typescript-bun | opus47-1m-high | 6.7min | 42 | 0 | $2.13 | 3.5 | typescript | ok |
| Test Results Aggregator | bash | opus47-1m-medium | 6.7min | 35 | 0 | $1.36 | 4.0 | bash | ok |
| Dependency License Checker | default | sonnet46-1m-medium | 6.7min | 43 | 3 | $1.07 | 3.5 | python | ok |
| Secret Rotation Validator | powershell | opus47-1m-high | 6.7min | 36 | 0 | $1.89 | 4.5 | powershell | ok |
| Artifact Cleanup Script | default | sonnet46-1m-medium | 6.8min | 32 | 2 | $1.02 | 4.5 | python | ok |
| Environment Matrix Generator | default | opus47-1m-xhigh | 6.8min | 34 | 2 | $2.01 | 3.0 | python | ok |
| Dependency License Checker | typescript-bun | sonnet46-200k-medium | 6.8min | 35 | 2 | $0.93 | 3.5 | typescript | ok |
| Secret Rotation Validator | powershell | haiku45-200k-na | 6.8min | 56 | 5 | $0.49 | 2.0 | powershell | ok |
| Semantic Version Bumper | default | opus47-1m-xhigh | 6.8min | 45 | 0 | $2.45 | 4.5 | python | ok |
| Secret Rotation Validator | typescript-bun | opus47-200k-medium | 6.9min | 36 | 0 | $1.92 | 3.5 | typescript | ok |
| PR Label Assigner | typescript-bun | sonnet46-200k-medium | 6.9min | 41 | 3 | $0.87 | 2.5 | typescript | ok |
| Test Results Aggregator | default | opus47-1m-medium | 6.9min | 31 | 0 | $1.28 | 3.5 | python | ok |
| Dependency License Checker | bash | sonnet46-200k-medium | 6.9min | 34 | 2 | $0.97 | 2.0 | bash | ok |
| Test Results Aggregator | powershell | opus47-200k-medium | 7.0min | 31 | 0 | $1.64 | 3.5 | powershell | ok |
| Secret Rotation Validator | default | opus47-1m-medium | 7.0min | 19 | 0 | $0.88 | 2.0 | python | ok |
| Environment Matrix Generator | powershell | opus47-1m-high | 7.0min | 41 | 0 | $2.04 | 4.0 | powershell | ok |
| Artifact Cleanup Script | default | opus47-1m-xhigh | 7.1min | 35 | 1 | $1.91 | 4.5 | python | ok |
| PR Label Assigner | bash | haiku45-200k-na | 7.1min | 62 | 4 | $0.50 | 2.0 | bash | ok |
| Semantic Version Bumper | default | opus47-1m-high | 7.1min | 31 | 0 | $1.85 | — | javascript | ok |
| Test Results Aggregator | powershell | opus47-200k-medium | 7.1min | 37 | 1 | $1.79 | 3.5 | powershell | ok |
| Dependency License Checker | powershell | sonnet46-1m-medium | 7.1min | 43 | 1 | $1.05 | 4.5 | powershell | ok |
| Dependency License Checker | powershell | opus47-1m-high | 7.1min | 31 | 0 | $1.93 | 4.0 | powershell | ok |
| Test Results Aggregator | powershell | haiku45-200k-na | 7.1min | 63 | 5 | $0.63 | — | powershell | ok |
| Artifact Cleanup Script | typescript-bun | opus47-1m-medium | 7.2min | 29 | 0 | $1.25 | 3.5 | typescript | ok |
| PR Label Assigner | bash | sonnet46-200k-medium | 7.2min | 44 | 3 | $0.90 | 4.0 | bash | ok |
| PR Label Assigner | typescript-bun | opus47-1m-high | 7.3min | 44 | 0 | $1.86 | 4.0 | typescript | ok |
| Environment Matrix Generator | typescript-bun | opus47-1m-medium | 7.4min | 29 | 0 | $1.07 | 3.0 | typescript | ok |
| Secret Rotation Validator | typescript-bun | opus47-1m-medium | 7.4min | 35 | 2 | $1.46 | 4.0 | typescript | ok |
| Semantic Version Bumper | typescript-bun | sonnet46-200k-medium | 7.4min | 33 | 4 | $0.68 | 2.0 | typescript | ok |
| Environment Matrix Generator | powershell | opus47-1m-high | 7.4min | 30 | 0 | $2.13 | 3.5 | powershell | ok |
| Test Results Aggregator | bash | haiku45-200k-na | 7.4min | 77 | 5 | $0.64 | 2.5 | bash | ok |
| PR Label Assigner | powershell | opus47-1m-medium | 7.4min | 29 | 0 | $1.33 | 3.5 | powershell | ok |
| Dependency License Checker | bash | opus47-200k-medium | 7.5min | 26 | 1 | $0.92 | 3.0 | bash | ok |
| Dependency License Checker | default | opus47-1m-xhigh | 7.5min | 40 | 0 | $2.04 | 4.0 | python | ok |
| Artifact Cleanup Script | bash | opus47-1m-xhigh | 7.6min | 34 | 1 | $1.84 | 4.0 | bash | ok |
| Semantic Version Bumper | typescript-bun | haiku45-200k-na | 7.6min | 74 | 10 | $0.62 | 2.0 | typescript | ok |
| PR Label Assigner | default | opus47-1m-high | 7.6min | 23 | 1 | $1.32 | 4.0 | python | ok |
| Dependency License Checker | powershell | haiku45-200k-na | 7.6min | 70 | 1 | $0.58 | 2.5 | powershell | ok |
| Semantic Version Bumper | powershell | opus47-1m-xhigh | 7.7min | 38 | 0 | $2.27 | 4.5 | powershell | ok |
| Secret Rotation Validator | bash | haiku45-200k-na | 7.7min | 56 | 3 | $0.49 | 2.0 | bash | ok |
| PR Label Assigner | powershell | opus47-1m-xhigh | 7.7min | 37 | 0 | $2.01 | 4.0 | powershell | ok |
| Test Results Aggregator | powershell | sonnet46-200k-medium | 7.7min | 27 | 0 | $1.03 | 4.0 | powershell | ok |
| Secret Rotation Validator | powershell | sonnet46-1m-medium | 7.8min | 33 | 1 | $0.94 | 2.5 | powershell | ok |
| PR Label Assigner | default | opus47-1m-xhigh | 7.8min | 43 | 0 | $2.25 | 4.0 | python | ok |
| Test Results Aggregator | typescript-bun | haiku45-200k-na | 7.8min | 67 | 9 | $0.60 | 2.0 | typescript | ok |
| Artifact Cleanup Script | powershell | sonnet46-1m-medium | 7.8min | 28 | 0 | $1.09 | 3.5 | powershell | ok |
| Artifact Cleanup Script | powershell | haiku45-200k-na | 7.8min | 31 | 2 | $0.28 | — | powershell | ok |
| Artifact Cleanup Script | typescript-bun | sonnet46-1m-medium | 7.9min | 49 | 4 | $1.37 | 4.0 | typescript | ok |
| Secret Rotation Validator | default | opus47-1m-high | 7.9min | 30 | 1 | $1.93 | 4.5 | python | ok |
| Dependency License Checker | powershell | opus47-200k-medium | 8.0min | 41 | 1 | $1.86 | 3.5 | powershell | ok |
| Secret Rotation Validator | powershell | sonnet46-200k-medium | 8.0min | 19 | 0 | $0.96 | 3.0 | powershell | ok |
| Semantic Version Bumper | powershell | opus47-1m-high | 8.0min | 40 | 0 | $2.23 | 4.5 | powershell | ok |
| Semantic Version Bumper | powershell | opus47-1m-xhigh | 8.0min | 49 | 0 | $2.90 | 3.5 | powershell | ok |
| Semantic Version Bumper | powershell | opus47-1m-medium | 8.0min | 37 | 1 | $1.75 | 4.0 | powershell | ok |
| Secret Rotation Validator | default | sonnet46-1m-medium | 8.0min | 31 | 4 | $1.16 | 4.5 | python | ok |
| Environment Matrix Generator | powershell | sonnet46-200k-medium | 8.0min | 25 | 1 | $1.00 | 4.0 | powershell | ok |
| Environment Matrix Generator | powershell | sonnet46-1m-medium | 8.1min | 36 | 7 | $1.04 | 4.0 | powershell | ok |
| Secret Rotation Validator | typescript-bun | opus47-1m-xhigh | 8.2min | 46 | 1 | $2.52 | 4.5 | typescript | ok |
| Artifact Cleanup Script | default | sonnet46-200k-medium | 8.2min | 28 | 2 | $1.14 | 4.0 | python | ok |
| Dependency License Checker | typescript-bun | opus47-1m-medium | 8.2min | 32 | 1 | $1.34 | 4.0 | typescript | ok |
| Environment Matrix Generator | typescript-bun | haiku45-200k-na | 8.2min | 73 | 4 | $0.68 | 3.0 | typescript | ok |
| Dependency License Checker | default | opus47-1m-medium | 8.2min | 34 | 2 | $1.33 | 4.0 | python | ok |
| Secret Rotation Validator | powershell | opus47-1m-high | 8.2min | 41 | 0 | $2.29 | 4.5 | powershell | ok |
| Environment Matrix Generator | bash | opus47-1m-xhigh | 8.3min | 51 | 2 | $2.49 | 3.5 | bash | ok |
| Semantic Version Bumper | powershell | sonnet46-1m-medium | 8.3min | 27 | 1 | $0.98 | 4.0 | powershell | ok |
| Test Results Aggregator | powershell | sonnet46-1m-medium | 8.3min | 24 | 1 | $0.99 | 3.0 | powershell | ok |
| Dependency License Checker | typescript-bun | sonnet46-1m-medium | 8.4min | 50 | 3 | $1.23 | 4.0 | typescript | ok |
| Artifact Cleanup Script | powershell | sonnet46-200k-medium | 8.4min | 31 | 2 | $1.25 | 4.0 | powershell | ok |
| Test Results Aggregator | typescript-bun | opus47-1m-medium | 8.4min | 35 | 0 | $1.49 | 4.0 | typescript | ok |
| Test Results Aggregator | default | sonnet46-1m-medium | 8.4min | 25 | 1 | $0.90 | 3.5 | python | ok |
| PR Label Assigner | powershell | sonnet46-200k-medium | 8.4min | 35 | 3 | $1.11 | 4.0 | powershell | ok |
| Artifact Cleanup Script | typescript-bun | opus47-1m-xhigh | 8.5min | 53 | 0 | $2.41 | 4.5 | typescript | ok |
| Secret Rotation Validator | default | sonnet46-200k-medium | 8.5min | 42 | 2 | $1.25 | 3.5 | python | ok |
| Semantic Version Bumper | typescript-bun | sonnet46-1m-medium | 8.5min | 42 | 4 | $0.92 | 4.0 | typescript | ok |
| Test Results Aggregator | typescript-bun | sonnet46-1m-medium | 8.5min | 34 | 2 | $1.11 | 3.5 | typescript | ok |
| PR Label Assigner | powershell | opus47-200k-medium | 8.5min | 38 | 0 | $1.93 | 4.0 | powershell | ok |
| Dependency License Checker | default | opus47-1m-high | 8.5min | 37 | 0 | $2.28 | 4.0 | python | ok |
| Semantic Version Bumper | powershell | opus47-1m-medium | 8.6min | 35 | 0 | $1.69 | 4.5 | powershell | ok |
| Secret Rotation Validator | bash | sonnet46-200k-medium | 8.6min | 39 | 5 | $1.11 | 4.0 | bash | ok |
| Dependency License Checker | powershell | sonnet46-200k-medium | 8.6min | 40 | 0 | $1.09 | 3.0 | powershell | ok |
| Test Results Aggregator | typescript-bun | opus47-1m-high | 8.6min | 44 | 0 | $1.52 | 4.0 | typescript | ok |
| Secret Rotation Validator | typescript-bun | sonnet46-200k-medium | 8.9min | 30 | 1 | $1.07 | 4.0 | typescript | ok |
| PR Label Assigner | typescript-bun | opus47-1m-medium | 9.0min | 30 | 0 | $1.06 | 4.0 | typescript | ok |
| Dependency License Checker | powershell | sonnet46-200k-medium | 9.0min | 27 | 1 | $1.04 | 3.5 | powershell | ok |
| Secret Rotation Validator | default | opus47-1m-xhigh | 9.1min | 45 | 0 | $2.54 | 4.0 | python | ok |
| Dependency License Checker | bash | sonnet46-1m-medium | 9.1min | 36 | 1 | $1.28 | 4.0 | bash | ok |
| Artifact Cleanup Script | bash | opus47-1m-high | 9.1min | 44 | 0 | $2.18 | 3.5 | bash | ok |
| Test Results Aggregator | default | opus47-1m-xhigh | 9.2min | 54 | 1 | $2.81 | 4.0 | python | ok |
| Artifact Cleanup Script | typescript-bun | opus47-1m-high | 9.2min | 39 | 0 | $2.07 | 4.5 | typescript | ok |
| Secret Rotation Validator | bash | opus47-1m-xhigh | 9.4min | 35 | 0 | $2.40 | 3.5 | bash | ok |
| Artifact Cleanup Script | powershell | opus47-1m-high | 9.4min | 39 | 0 | $2.30 | 4.5 | powershell | ok |
| Test Results Aggregator | powershell | opus47-1m-medium | 9.4min | 37 | 0 | $1.76 | 3.5 | powershell | ok |
| Secret Rotation Validator | typescript-bun | opus47-1m-high | 9.5min | 55 | 0 | $2.95 | 3.5 | typescript | ok |
| Test Results Aggregator | powershell | opus47-1m-medium | 9.6min | 27 | 0 | $1.44 | 4.0 | powershell | ok |
| PR Label Assigner | default | sonnet46-1m-medium | 9.6min | 44 | 7 | $1.38 | 3.0 | python | ok |
| PR Label Assigner | powershell | opus47-1m-xhigh | 9.6min | 43 | 0 | $2.60 | 4.0 | powershell | ok |
| Environment Matrix Generator | typescript-bun | opus47-1m-xhigh | 9.8min | 52 | 0 | $2.60 | 4.5 | typescript | ok |
| Secret Rotation Validator | powershell | opus47-1m-xhigh | 9.9min | 38 | 0 | $2.58 | 4.0 | powershell | ok |
| Secret Rotation Validator | powershell | sonnet46-1m-medium | 9.9min | 36 | 1 | $1.35 | 3.5 | powershell | ok |
| Secret Rotation Validator | bash | sonnet46-1m-medium | 10.0min | 41 | 6 | $1.10 | 3.5 | bash | ok |
| Semantic Version Bumper | bash | sonnet46-1m-medium | 10.0min | 40 | 4 | $1.38 | 3.0 | bash | ok |
| PR Label Assigner | powershell | opus47-1m-high | 10.0min | 49 | 1 | $2.92 | 4.0 | powershell | ok |
| Dependency License Checker | powershell | opus47-1m-high | 10.1min | 42 | 0 | $2.43 | 4.0 | powershell | ok |
| Environment Matrix Generator | powershell | opus47-1m-xhigh | 10.2min | 43 | 1 | $3.08 | 4.0 | powershell | ok |
| Dependency License Checker | powershell | opus47-1m-xhigh | 10.2min | 48 | 1 | $2.95 | 4.0 | powershell | ok |
| PR Label Assigner | typescript-bun | opus47-1m-xhigh | 10.4min | 57 | 0 | $3.05 | 4.5 | typescript | ok |
| Test Results Aggregator | bash | sonnet46-1m-medium | 10.7min | 39 | 5 | $1.42 | 3.5 | bash | ok |
| Semantic Version Bumper | typescript-bun | opus47-1m-high | 10.9min | 62 | 1 | $2.99 | 4.5 | typescript | ok |
| Dependency License Checker | typescript-bun | opus47-1m-high | 10.9min | 68 | 0 | $3.08 | 4.5 | typescript | ok |
| Artifact Cleanup Script | powershell | opus47-1m-xhigh | 10.9min | 43 | 0 | $3.19 | 4.5 | powershell | ok |
| Secret Rotation Validator | powershell | opus47-1m-xhigh | 11.0min | 46 | 2 | $3.07 | 4.5 | powershell | ok |
| Test Results Aggregator | typescript-bun | sonnet46-200k-medium | 11.0min | 39 | 3 | $1.47 | 4.0 | typescript | ok |
| Test Results Aggregator | powershell | opus47-1m-high | 11.1min | 49 | 1 | $3.14 | 4.0 | powershell | ok |
| Dependency License Checker | powershell | opus47-1m-xhigh | 11.2min | 48 | 0 | $2.86 | 4.0 | powershell | ok |
| Test Results Aggregator | bash | opus47-1m-high | 11.3min | 48 | 1 | $2.37 | 3.5 | bash | ok |
| Test Results Aggregator | powershell | sonnet46-1m-medium | 11.4min | 25 | 2 | $1.32 | 4.0 | powershell | ok |
| Secret Rotation Validator | powershell | haiku45-200k-na | 11.4min | 40 | 3 | $0.39 | 3.0 | powershell | ok |
| Artifact Cleanup Script | bash | sonnet46-1m-medium | 11.6min | 45 | 6 | $1.78 | 4.0 | bash | ok |
| Artifact Cleanup Script | powershell | opus47-1m-high | 11.7min | 54 | 1 | $3.33 | 4.0 | powershell | ok |
| Test Results Aggregator | powershell | sonnet46-200k-medium | 11.7min | 32 | 1 | $1.40 | 4.5 | powershell | ok |
| Dependency License Checker | default | sonnet46-200k-medium | 11.7min | 44 | 4 | $1.68 | 4.5 | python | ok |
| Dependency License Checker | typescript-bun | opus47-1m-xhigh | 11.8min | 74 | 0 | $3.64 | 4.5 | typescript | ok |
| Semantic Version Bumper | powershell | sonnet46-1m-medium | 11.9min | 40 | 1 | $1.69 | 3.5 | powershell | ok |
| Dependency License Checker | powershell | sonnet46-1m-medium | 12.0min | 45 | 1 | $1.79 | 4.0 | powershell | ok |
| Artifact Cleanup Script | powershell | opus47-1m-xhigh | 12.0min | 51 | 1 | $3.21 | 4.0 | powershell | ok |
| PR Label Assigner | powershell | sonnet46-1m-medium | 12.0min | 31 | 1 | $1.61 | 4.5 | powershell | ok |
| Environment Matrix Generator | typescript-bun | sonnet46-1m-medium | 12.2min | 42 | 2 | $1.34 | 3.5 | typescript | ok |
| Environment Matrix Generator | powershell | opus47-1m-xhigh | 13.5min | 54 | 0 | $3.93 | 4.0 | powershell | ok |
| Environment Matrix Generator | powershell | opus47-1m-medium | 14.0min | 59 | 0 | $3.01 | 4.0 | powershell | ok |
| Dependency License Checker | bash | haiku45-200k-na | 14.2min | 47 | 2 | $0.36 | 2.5 | bash | ok |
| Semantic Version Bumper | typescript-bun | opus47-1m-xhigh | 14.3min | 80 | 1 | $4.21 | 4.5 | typescript | ok |
| Semantic Version Bumper | powershell | haiku45-200k-na | 15.1min | 92 | 7 | $0.93 | — | powershell | ok |
| Test Results Aggregator | powershell | opus47-1m-xhigh | 15.2min | 63 | 0 | $5.47 | 4.0 | powershell | ok |
| Test Results Aggregator | powershell | opus47-1m-high | 15.9min | 69 | 1 | $3.91 | 4.0 | powershell | ok |
| Test Results Aggregator | bash | opus47-1m-xhigh | 16.5min | 79 | 1 | $5.09 | 4.5 | bash | ok |
| PR Label Assigner | bash | opus47-1m-xhigh | 16.7min | 61 | 2 | $3.14 | 3.5 | bash | ok |
| Semantic Version Bumper | bash | opus47-1m-xhigh | 17.2min | 48 | 2 | $2.95 | 4.5 | bash | ok |
| Test Results Aggregator | powershell | opus47-1m-xhigh | 17.3min | 74 | 0 | $4.47 | 3.5 | powershell | ok |
| Secret Rotation Validator | powershell | opus47-1m-medium | 17.8min | 38 | 2 | $1.70 | 4.0 | powershell | ok |
| Test Results Aggregator | typescript-bun | opus47-1m-xhigh | 20.8min | 103 | 1 | $6.31 | 4.5 | typescript | ok |
| Secret Rotation Validator | powershell | opus47-1m-medium | 22.5min | 31 | 0 | $1.27 | 4.0 | powershell | ok |
| Environment Matrix Generator | bash | sonnet46-1m-medium | 29.1min | 58 | 6 | $3.25 | 3.5 | bash | ok |
| Dependency License Checker | bash | opus47-1m-xhigh | 39.8min | 38 | 2 | $2.19 | 2.5 | bash | ok |
| Semantic Version Bumper | default | haiku45-200k-na | 59.1min | 97 | 12 | $0.84 | — | javascript | ok |
| Environment Matrix Generator | bash | haiku45-200k-na | 322.8min | 85 | 10 | $0.75 | 2.0 | bash | timeout |

</details>

<details>
<summary>Sorted by errors (fewest first)</summary>

| Task | Language | Model | Duration | Turns | Errors | Cost | Tests Quality | Chosen | Status |
|------|----------|-------|----------|-------|--------|------|-----------|--------|--------|
| Semantic Version Bumper | bash | opus47-200k-medium | 4.1min | 25 | 0 | $1.02 | 4.0 | bash | ok |
| Semantic Version Bumper | default | opus47-1m-high | 7.1min | 31 | 0 | $1.85 | — | javascript | ok |
| Semantic Version Bumper | default | opus47-1m-medium | 4.1min | 22 | 0 | $0.93 | 4.0 | python | ok |
| Semantic Version Bumper | default | opus47-1m-xhigh | 6.8min | 45 | 0 | $2.45 | 4.5 | python | ok |
| Semantic Version Bumper | powershell | opus47-1m-high | 8.0min | 40 | 0 | $2.23 | 4.5 | powershell | ok |
| Semantic Version Bumper | powershell | opus47-1m-medium | 8.6min | 35 | 0 | $1.69 | 4.5 | powershell | ok |
| Semantic Version Bumper | powershell | opus47-1m-xhigh | 7.7min | 38 | 0 | $2.27 | 4.5 | powershell | ok |
| Semantic Version Bumper | powershell | opus47-200k-medium | 6.3min | 33 | 0 | $1.44 | 4.0 | powershell | ok |
| Semantic Version Bumper | powershell | opus47-1m-high | 6.1min | 34 | 0 | $1.78 | 4.5 | powershell | ok |
| Semantic Version Bumper | powershell | opus47-1m-xhigh | 8.0min | 49 | 0 | $2.90 | 3.5 | powershell | ok |
| Semantic Version Bumper | powershell | opus47-200k-medium | 5.3min | 27 | 0 | $1.36 | 4.0 | powershell | ok |
| Semantic Version Bumper | typescript-bun | opus47-1m-medium | 5.6min | 33 | 0 | $1.31 | 4.0 | typescript | ok |
| PR Label Assigner | default | opus47-1m-medium | 3.1min | 23 | 0 | $0.83 | 2.0 | python | ok |
| PR Label Assigner | default | opus47-1m-xhigh | 7.8min | 43 | 0 | $2.25 | 4.0 | python | ok |
| PR Label Assigner | default | opus47-200k-medium | 3.2min | 21 | 0 | $0.70 | 2.0 | python | ok |
| PR Label Assigner | powershell | opus47-1m-medium | 5.1min | 27 | 0 | $1.11 | 4.0 | powershell | ok |
| PR Label Assigner | powershell | opus47-1m-xhigh | 9.6min | 43 | 0 | $2.60 | 4.0 | powershell | ok |
| PR Label Assigner | powershell | opus47-200k-medium | 8.5min | 38 | 0 | $1.93 | 4.0 | powershell | ok |
| PR Label Assigner | powershell | sonnet46-200k-medium | 2.9min | 19 | 0 | $0.38 | 1.5 | powershell | ok |
| PR Label Assigner | powershell | opus47-1m-medium | 7.4min | 29 | 0 | $1.33 | 3.5 | powershell | ok |
| PR Label Assigner | powershell | opus47-1m-xhigh | 7.7min | 37 | 0 | $2.01 | 4.0 | powershell | ok |
| PR Label Assigner | powershell | opus47-200k-medium | 5.3min | 27 | 0 | $1.34 | 4.0 | powershell | ok |
| PR Label Assigner | typescript-bun | opus47-1m-high | 7.3min | 44 | 0 | $1.86 | 4.0 | typescript | ok |
| PR Label Assigner | typescript-bun | opus47-1m-medium | 9.0min | 30 | 0 | $1.06 | 4.0 | typescript | ok |
| PR Label Assigner | typescript-bun | opus47-1m-xhigh | 10.4min | 57 | 0 | $3.05 | 4.5 | typescript | ok |
| PR Label Assigner | typescript-bun | opus47-200k-medium | 4.5min | 28 | 0 | $1.00 | 4.0 | typescript | ok |
| PR Label Assigner | typescript-bun | sonnet46-1m-medium | 4.7min | 27 | 0 | $0.67 | 3.0 | typescript | ok |
| Dependency License Checker | bash | opus47-1m-high | 4.0min | 30 | 0 | $1.35 | 2.5 | bash | ok |
| Dependency License Checker | default | opus47-1m-high | 8.5min | 37 | 0 | $2.28 | 4.0 | python | ok |
| Dependency License Checker | default | opus47-1m-xhigh | 7.5min | 40 | 0 | $2.04 | 4.0 | python | ok |
| Dependency License Checker | default | opus47-200k-medium | 4.1min | 24 | 0 | $0.97 | 4.5 | python | ok |
| Dependency License Checker | powershell | opus47-1m-high | 7.1min | 31 | 0 | $1.93 | 4.0 | powershell | ok |
| Dependency License Checker | powershell | opus47-1m-medium | 6.6min | 23 | 0 | $1.00 | 3.5 | powershell | ok |
| Dependency License Checker | powershell | sonnet46-200k-medium | 8.6min | 40 | 0 | $1.09 | 3.0 | powershell | ok |
| Dependency License Checker | powershell | opus47-1m-high | 10.1min | 42 | 0 | $2.43 | 4.0 | powershell | ok |
| Dependency License Checker | powershell | opus47-1m-medium | 4.9min | 26 | 0 | $1.18 | 4.0 | powershell | ok |
| Dependency License Checker | powershell | opus47-1m-xhigh | 11.2min | 48 | 0 | $2.86 | 4.0 | powershell | ok |
| Dependency License Checker | typescript-bun | opus47-1m-high | 10.9min | 68 | 0 | $3.08 | 4.5 | typescript | ok |
| Dependency License Checker | typescript-bun | opus47-1m-xhigh | 11.8min | 74 | 0 | $3.64 | 4.5 | typescript | ok |
| Dependency License Checker | typescript-bun | opus47-200k-medium | 4.8min | 29 | 0 | $1.10 | 4.0 | typescript | ok |
| Test Results Aggregator | bash | opus47-1m-medium | 6.7min | 35 | 0 | $1.36 | 4.0 | bash | ok |
| Test Results Aggregator | bash | sonnet46-200k-medium | 6.3min | 23 | 0 | $0.78 | 4.0 | bash | ok |
| Test Results Aggregator | default | opus47-1m-high | 6.5min | 44 | 0 | $2.37 | 4.0 | python | ok |
| Test Results Aggregator | default | opus47-1m-medium | 6.9min | 31 | 0 | $1.28 | 3.5 | python | ok |
| Test Results Aggregator | powershell | opus47-1m-medium | 9.6min | 27 | 0 | $1.44 | 4.0 | powershell | ok |
| Test Results Aggregator | powershell | opus47-1m-xhigh | 17.3min | 74 | 0 | $4.47 | 3.5 | powershell | ok |
| Test Results Aggregator | powershell | sonnet46-200k-medium | 7.7min | 27 | 0 | $1.03 | 4.0 | powershell | ok |
| Test Results Aggregator | powershell | opus47-1m-medium | 9.4min | 37 | 0 | $1.76 | 3.5 | powershell | ok |
| Test Results Aggregator | powershell | opus47-1m-xhigh | 15.2min | 63 | 0 | $5.47 | 4.0 | powershell | ok |
| Test Results Aggregator | powershell | opus47-200k-medium | 7.0min | 31 | 0 | $1.64 | 3.5 | powershell | ok |
| Test Results Aggregator | typescript-bun | opus47-1m-high | 8.6min | 44 | 0 | $1.52 | 4.0 | typescript | ok |
| Test Results Aggregator | typescript-bun | opus47-1m-medium | 8.4min | 35 | 0 | $1.49 | 4.0 | typescript | ok |
| Environment Matrix Generator | bash | opus47-1m-high | 6.6min | 42 | 0 | $1.69 | 4.0 | bash | ok |
| Environment Matrix Generator | bash | opus47-200k-medium | 2.9min | 23 | 0 | $1.05 | 3.5 | bash | ok |
| Environment Matrix Generator | default | opus47-1m-high | 5.7min | 38 | 0 | $1.87 | 4.0 | python | ok |
| Environment Matrix Generator | default | opus47-1m-medium | 5.4min | 26 | 0 | $1.12 | 4.0 | python | ok |
| Environment Matrix Generator | powershell | opus47-1m-high | 7.0min | 41 | 0 | $2.04 | 4.0 | powershell | ok |
| Environment Matrix Generator | powershell | opus47-1m-medium | 14.0min | 59 | 0 | $3.01 | 4.0 | powershell | ok |
| Environment Matrix Generator | powershell | opus47-1m-xhigh | 13.5min | 54 | 0 | $3.93 | 4.0 | powershell | ok |
| Environment Matrix Generator | powershell | opus47-200k-medium | 6.1min | 30 | 0 | $1.42 | 4.0 | powershell | ok |
| Environment Matrix Generator | powershell | opus47-1m-high | 7.4min | 30 | 0 | $2.13 | 3.5 | powershell | ok |
| Environment Matrix Generator | typescript-bun | opus47-1m-high | 6.7min | 42 | 0 | $2.13 | 3.5 | typescript | ok |
| Environment Matrix Generator | typescript-bun | opus47-1m-medium | 7.4min | 29 | 0 | $1.07 | 3.0 | typescript | ok |
| Environment Matrix Generator | typescript-bun | opus47-1m-xhigh | 9.8min | 52 | 0 | $2.60 | 4.5 | typescript | ok |
| Artifact Cleanup Script | bash | opus47-1m-high | 9.1min | 44 | 0 | $2.18 | 3.5 | bash | ok |
| Artifact Cleanup Script | default | opus47-1m-high | 6.6min | 36 | 0 | $2.04 | 4.5 | python | ok |
| Artifact Cleanup Script | default | opus47-1m-medium | 3.2min | 19 | 0 | $0.85 | 4.0 | python | ok |
| Artifact Cleanup Script | default | opus47-200k-medium | 5.0min | 23 | 0 | $1.30 | 4.5 | python | ok |
| Artifact Cleanup Script | powershell | opus47-1m-high | 9.4min | 39 | 0 | $2.30 | 4.5 | powershell | ok |
| Artifact Cleanup Script | powershell | opus47-1m-medium | 4.7min | 22 | 0 | $1.08 | 3.5 | powershell | ok |
| Artifact Cleanup Script | powershell | opus47-1m-xhigh | 10.9min | 43 | 0 | $3.19 | 4.5 | powershell | ok |
| Artifact Cleanup Script | powershell | opus47-200k-medium | 4.0min | 23 | 0 | $1.09 | 3.5 | powershell | ok |
| Artifact Cleanup Script | powershell | sonnet46-1m-medium | 7.8min | 28 | 0 | $1.09 | 3.5 | powershell | ok |
| Artifact Cleanup Script | powershell | opus47-1m-medium | 4.1min | 20 | 0 | $0.96 | 4.0 | powershell | ok |
| Artifact Cleanup Script | powershell | opus47-200k-medium | 5.4min | 32 | 0 | $1.65 | 4.0 | powershell | ok |
| Artifact Cleanup Script | typescript-bun | opus47-1m-high | 9.2min | 39 | 0 | $2.07 | 4.5 | typescript | ok |
| Artifact Cleanup Script | typescript-bun | opus47-1m-medium | 7.2min | 29 | 0 | $1.25 | 3.5 | typescript | ok |
| Artifact Cleanup Script | typescript-bun | opus47-1m-xhigh | 8.5min | 53 | 0 | $2.41 | 4.5 | typescript | ok |
| Artifact Cleanup Script | typescript-bun | opus47-200k-medium | 4.4min | 22 | 0 | $0.92 | 4.0 | typescript | ok |
| Secret Rotation Validator | bash | opus47-1m-high | 4.6min | 22 | 0 | $1.06 | 3.0 | bash | ok |
| Secret Rotation Validator | bash | opus47-1m-medium | 5.4min | 24 | 0 | $1.09 | 3.0 | bash | ok |
| Secret Rotation Validator | bash | opus47-1m-xhigh | 9.4min | 35 | 0 | $2.40 | 3.5 | bash | ok |
| Secret Rotation Validator | default | opus47-1m-medium | 7.0min | 19 | 0 | $0.88 | 2.0 | python | ok |
| Secret Rotation Validator | default | opus47-1m-xhigh | 9.1min | 45 | 0 | $2.54 | 4.0 | python | ok |
| Secret Rotation Validator | default | opus47-200k-medium | 5.5min | 25 | 0 | $1.27 | 4.0 | python | ok |
| Secret Rotation Validator | powershell | opus47-1m-high | 6.7min | 36 | 0 | $1.89 | 4.5 | powershell | ok |
| Secret Rotation Validator | powershell | opus47-1m-medium | 22.5min | 31 | 0 | $1.27 | 4.0 | powershell | ok |
| Secret Rotation Validator | powershell | opus47-200k-medium | 4.9min | 32 | 0 | $1.40 | 3.5 | powershell | ok |
| Secret Rotation Validator | powershell | opus47-1m-high | 8.2min | 41 | 0 | $2.29 | 4.5 | powershell | ok |
| Secret Rotation Validator | powershell | opus47-1m-xhigh | 9.9min | 38 | 0 | $2.58 | 4.0 | powershell | ok |
| Secret Rotation Validator | powershell | opus47-200k-medium | 4.0min | 19 | 0 | $1.06 | 3.5 | powershell | ok |
| Secret Rotation Validator | powershell | sonnet46-200k-medium | 8.0min | 19 | 0 | $0.96 | 3.0 | powershell | ok |
| Secret Rotation Validator | typescript-bun | opus47-1m-high | 9.5min | 55 | 0 | $2.95 | 3.5 | typescript | ok |
| Secret Rotation Validator | typescript-bun | opus47-200k-medium | 6.9min | 36 | 0 | $1.92 | 3.5 | typescript | ok |
| Semantic Version Bumper | bash | haiku45-200k-na | 6.3min | 48 | 1 | $0.45 | 2.5 | bash | ok |
| Semantic Version Bumper | bash | opus47-1m-high | 6.3min | 31 | 1 | $1.44 | 4.0 | bash | ok |
| Semantic Version Bumper | default | opus47-200k-medium | 4.2min | 31 | 1 | $1.21 | — | javascript | ok |
| Semantic Version Bumper | powershell | sonnet46-200k-medium | 3.9min | 23 | 1 | $0.44 | 4.0 | powershell | ok |
| Semantic Version Bumper | powershell | sonnet46-1m-medium | 8.3min | 27 | 1 | $0.98 | 4.0 | powershell | ok |
| Semantic Version Bumper | powershell | opus47-1m-medium | 8.0min | 37 | 1 | $1.75 | 4.0 | powershell | ok |
| Semantic Version Bumper | powershell | sonnet46-1m-medium | 11.9min | 40 | 1 | $1.69 | 3.5 | powershell | ok |
| Semantic Version Bumper | typescript-bun | opus47-1m-high | 10.9min | 62 | 1 | $2.99 | 4.5 | typescript | ok |
| Semantic Version Bumper | typescript-bun | opus47-1m-xhigh | 14.3min | 80 | 1 | $4.21 | 4.5 | typescript | ok |
| Semantic Version Bumper | typescript-bun | opus47-200k-medium | 5.1min | 35 | 1 | $1.58 | 3.5 | typescript | ok |
| PR Label Assigner | bash | opus47-1m-medium | 6.2min | 23 | 1 | $0.87 | 4.0 | bash | ok |
| PR Label Assigner | default | opus47-1m-high | 7.6min | 23 | 1 | $1.32 | 4.0 | python | ok |
| PR Label Assigner | default | sonnet46-200k-medium | 4.4min | 34 | 1 | $0.66 | 2.5 | python | ok |
| PR Label Assigner | powershell | haiku45-200k-na | 5.2min | 44 | 1 | $0.38 | 2.0 | powershell | ok |
| PR Label Assigner | powershell | opus47-1m-high | 10.0min | 49 | 1 | $2.92 | 4.0 | powershell | ok |
| PR Label Assigner | powershell | sonnet46-1m-medium | 12.0min | 31 | 1 | $1.61 | 4.5 | powershell | ok |
| PR Label Assigner | powershell | haiku45-200k-na | 3.0min | 26 | 1 | $0.23 | 2.5 | powershell | ok |
| PR Label Assigner | powershell | opus47-1m-high | 5.7min | 29 | 1 | $1.67 | 4.5 | powershell | ok |
| PR Label Assigner | powershell | sonnet46-1m-medium | 4.4min | 28 | 1 | $0.59 | 2.5 | powershell | ok |
| Dependency License Checker | bash | opus47-1m-medium | 5.5min | 30 | 1 | $1.55 | 3.0 | bash | ok |
| Dependency License Checker | bash | opus47-200k-medium | 7.5min | 26 | 1 | $0.92 | 3.0 | bash | ok |
| Dependency License Checker | bash | sonnet46-1m-medium | 9.1min | 36 | 1 | $1.28 | 4.0 | bash | ok |
| Dependency License Checker | powershell | haiku45-200k-na | 7.6min | 70 | 1 | $0.58 | 2.5 | powershell | ok |
| Dependency License Checker | powershell | opus47-1m-xhigh | 10.2min | 48 | 1 | $2.95 | 4.0 | powershell | ok |
| Dependency License Checker | powershell | opus47-200k-medium | 8.0min | 41 | 1 | $1.86 | 3.5 | powershell | ok |
| Dependency License Checker | powershell | sonnet46-1m-medium | 7.1min | 43 | 1 | $1.05 | 4.5 | powershell | ok |
| Dependency License Checker | powershell | opus47-200k-medium | 6.3min | 34 | 1 | $1.68 | 4.0 | powershell | ok |
| Dependency License Checker | powershell | sonnet46-200k-medium | 9.0min | 27 | 1 | $1.04 | 3.5 | powershell | ok |
| Dependency License Checker | powershell | sonnet46-1m-medium | 12.0min | 45 | 1 | $1.79 | 4.0 | powershell | ok |
| Dependency License Checker | typescript-bun | haiku45-200k-na | 4.3min | 48 | 1 | $0.39 | 2.0 | typescript | ok |
| Dependency License Checker | typescript-bun | opus47-1m-medium | 8.2min | 32 | 1 | $1.34 | 4.0 | typescript | ok |
| Test Results Aggregator | bash | opus47-1m-high | 11.3min | 48 | 1 | $2.37 | 3.5 | bash | ok |
| Test Results Aggregator | bash | opus47-1m-xhigh | 16.5min | 79 | 1 | $5.09 | 4.5 | bash | ok |
| Test Results Aggregator | bash | opus47-200k-medium | 4.3min | 29 | 1 | $1.12 | 4.0 | bash | ok |
| Test Results Aggregator | default | opus47-1m-xhigh | 9.2min | 54 | 1 | $2.81 | 4.0 | python | ok |
| Test Results Aggregator | default | opus47-200k-medium | 6.1min | 35 | 1 | $1.68 | 4.0 | python | ok |
| Test Results Aggregator | default | sonnet46-1m-medium | 8.4min | 25 | 1 | $0.90 | 3.5 | python | ok |
| Test Results Aggregator | powershell | opus47-1m-high | 11.1min | 49 | 1 | $3.14 | 4.0 | powershell | ok |
| Test Results Aggregator | powershell | opus47-200k-medium | 7.1min | 37 | 1 | $1.79 | 3.5 | powershell | ok |
| Test Results Aggregator | powershell | sonnet46-1m-medium | 8.3min | 24 | 1 | $0.99 | 3.0 | powershell | ok |
| Test Results Aggregator | powershell | opus47-1m-high | 15.9min | 69 | 1 | $3.91 | 4.0 | powershell | ok |
| Test Results Aggregator | powershell | sonnet46-200k-medium | 11.7min | 32 | 1 | $1.40 | 4.5 | powershell | ok |
| Test Results Aggregator | typescript-bun | opus47-1m-xhigh | 20.8min | 103 | 1 | $6.31 | 4.5 | typescript | ok |
| Test Results Aggregator | typescript-bun | opus47-200k-medium | 6.4min | 33 | 1 | $1.53 | 3.5 | typescript | ok |
| Environment Matrix Generator | bash | opus47-1m-medium | 3.5min | 23 | 1 | $0.88 | 3.0 | bash | ok |
| Environment Matrix Generator | bash | sonnet46-200k-medium | 4.2min | 7 | 1 | $0.35 | — | bash | cli_error |
| Environment Matrix Generator | default | opus47-200k-medium | 5.0min | 28 | 1 | $1.05 | 4.0 | python | ok |
| Environment Matrix Generator | powershell | sonnet46-200k-medium | 2.1min | 14 | 1 | $0.28 | 2.5 | powershell | ok |
| Environment Matrix Generator | powershell | sonnet46-1m-medium | 2.7min | 16 | 1 | $0.34 | 2.5 | powershell | ok |
| Environment Matrix Generator | powershell | opus47-1m-xhigh | 10.2min | 43 | 1 | $3.08 | 4.0 | powershell | ok |
| Environment Matrix Generator | powershell | opus47-200k-medium | 6.0min | 27 | 1 | $1.51 | 4.0 | powershell | ok |
| Environment Matrix Generator | powershell | sonnet46-200k-medium | 8.0min | 25 | 1 | $1.00 | 4.0 | powershell | ok |
| Environment Matrix Generator | typescript-bun | opus47-200k-medium | 6.5min | 36 | 1 | $1.41 | 4.0 | typescript | ok |
| Artifact Cleanup Script | bash | opus47-1m-xhigh | 7.6min | 34 | 1 | $1.84 | 4.0 | bash | ok |
| Artifact Cleanup Script | bash | opus47-200k-medium | 5.8min | 25 | 1 | $1.26 | 3.0 | bash | ok |
| Artifact Cleanup Script | default | opus47-1m-xhigh | 7.1min | 35 | 1 | $1.91 | 4.5 | python | ok |
| Artifact Cleanup Script | powershell | opus47-1m-high | 11.7min | 54 | 1 | $3.33 | 4.0 | powershell | ok |
| Artifact Cleanup Script | powershell | opus47-1m-xhigh | 12.0min | 51 | 1 | $3.21 | 4.0 | powershell | ok |
| Artifact Cleanup Script | powershell | sonnet46-200k-medium | 6.0min | 50 | 1 | $0.94 | 4.0 | powershell | ok |
| Secret Rotation Validator | default | opus47-1m-high | 7.9min | 30 | 1 | $1.93 | 4.5 | python | ok |
| Secret Rotation Validator | powershell | sonnet46-200k-medium | 3.4min | 22 | 1 | $0.47 | 2.5 | powershell | ok |
| Secret Rotation Validator | powershell | sonnet46-1m-medium | 9.9min | 36 | 1 | $1.35 | 3.5 | powershell | ok |
| Secret Rotation Validator | powershell | sonnet46-1m-medium | 7.8min | 33 | 1 | $0.94 | 2.5 | powershell | ok |
| Secret Rotation Validator | typescript-bun | opus47-1m-xhigh | 8.2min | 46 | 1 | $2.52 | 4.5 | typescript | ok |
| Secret Rotation Validator | typescript-bun | sonnet46-200k-medium | 8.9min | 30 | 1 | $1.07 | 4.0 | typescript | ok |
| Semantic Version Bumper | bash | opus47-1m-medium | 4.2min | 30 | 2 | $1.07 | 2.5 | bash | ok |
| Semantic Version Bumper | bash | opus47-1m-xhigh | 17.2min | 48 | 2 | $2.95 | 4.5 | bash | ok |
| Semantic Version Bumper | bash | sonnet46-200k-medium | 4.5min | 36 | 2 | $0.64 | 3.0 | bash | ok |
| Semantic Version Bumper | powershell | sonnet46-200k-medium | 5.9min | 33 | 2 | $0.87 | 4.5 | powershell | ok |
| PR Label Assigner | bash | opus47-1m-high | 5.9min | 31 | 2 | $1.46 | 4.0 | bash | ok |
| PR Label Assigner | bash | opus47-1m-xhigh | 16.7min | 61 | 2 | $3.14 | 3.5 | bash | ok |
| PR Label Assigner | typescript-bun | haiku45-200k-na | 6.0min | 43 | 2 | $0.37 | 2.0 | typescript | ok |
| Dependency License Checker | bash | haiku45-200k-na | 14.2min | 47 | 2 | $0.36 | 2.5 | bash | ok |
| Dependency License Checker | bash | opus47-1m-xhigh | 39.8min | 38 | 2 | $2.19 | 2.5 | bash | ok |
| Dependency License Checker | bash | sonnet46-200k-medium | 6.9min | 34 | 2 | $0.97 | 2.0 | bash | ok |
| Dependency License Checker | default | opus47-1m-medium | 8.2min | 34 | 2 | $1.33 | 4.0 | python | ok |
| Dependency License Checker | powershell | haiku45-200k-na | 4.0min | 55 | 2 | $0.42 | 2.5 | powershell | ok |
| Dependency License Checker | typescript-bun | sonnet46-200k-medium | 6.8min | 35 | 2 | $0.93 | 3.5 | typescript | ok |
| Test Results Aggregator | powershell | haiku45-200k-na | 6.6min | 63 | 2 | $0.62 | 1.5 | powershell | ok |
| Test Results Aggregator | powershell | sonnet46-1m-medium | 11.4min | 25 | 2 | $1.32 | 4.0 | powershell | ok |
| Test Results Aggregator | typescript-bun | sonnet46-1m-medium | 8.5min | 34 | 2 | $1.11 | 3.5 | typescript | ok |
| Environment Matrix Generator | bash | opus47-1m-xhigh | 8.3min | 51 | 2 | $2.49 | 3.5 | bash | ok |
| Environment Matrix Generator | default | opus47-1m-xhigh | 6.8min | 34 | 2 | $2.01 | 3.0 | python | ok |
| Environment Matrix Generator | default | sonnet46-200k-medium | 2.9min | 23 | 2 | $0.41 | 2.0 | python | ok |
| Environment Matrix Generator | powershell | opus47-1m-medium | 4.6min | 29 | 2 | $1.30 | 3.5 | powershell | ok |
| Environment Matrix Generator | typescript-bun | sonnet46-200k-medium | 6.4min | 31 | 2 | $0.90 | 3.5 | typescript | ok |
| Environment Matrix Generator | typescript-bun | sonnet46-1m-medium | 12.2min | 42 | 2 | $1.34 | 3.5 | typescript | ok |
| Artifact Cleanup Script | bash | sonnet46-200k-medium | 4.4min | 31 | 2 | $0.61 | 2.5 | bash | ok |
| Artifact Cleanup Script | default | sonnet46-200k-medium | 8.2min | 28 | 2 | $1.14 | 4.0 | python | ok |
| Artifact Cleanup Script | default | sonnet46-1m-medium | 6.8min | 32 | 2 | $1.02 | 4.5 | python | ok |
| Artifact Cleanup Script | powershell | haiku45-200k-na | 7.8min | 31 | 2 | $0.28 | — | powershell | ok |
| Artifact Cleanup Script | powershell | sonnet46-200k-medium | 8.4min | 31 | 2 | $1.25 | 4.0 | powershell | ok |
| Artifact Cleanup Script | powershell | haiku45-200k-na | 3.2min | 29 | 2 | $0.28 | 1.5 | powershell | ok |
| Artifact Cleanup Script | powershell | sonnet46-1m-medium | 3.1min | 18 | 2 | $0.46 | 3.0 | powershell | ok |
| Secret Rotation Validator | bash | opus47-200k-medium | 3.4min | 29 | 2 | $1.10 | 3.0 | bash | ok |
| Secret Rotation Validator | default | sonnet46-200k-medium | 8.5min | 42 | 2 | $1.25 | 3.5 | python | ok |
| Secret Rotation Validator | powershell | opus47-1m-xhigh | 11.0min | 46 | 2 | $3.07 | 4.5 | powershell | ok |
| Secret Rotation Validator | powershell | opus47-1m-medium | 17.8min | 38 | 2 | $1.70 | 4.0 | powershell | ok |
| Secret Rotation Validator | typescript-bun | opus47-1m-medium | 7.4min | 35 | 2 | $1.46 | 4.0 | typescript | ok |
| Semantic Version Bumper | default | sonnet46-200k-medium | 5.8min | 42 | 3 | $0.94 | 4.0 | python | ok |
| Semantic Version Bumper | default | sonnet46-1m-medium | 4.6min | 33 | 3 | $0.67 | 2.0 | python | ok |
| PR Label Assigner | bash | opus47-200k-medium | 5.0min | 29 | 3 | $1.18 | 2.0 | bash | ok |
| PR Label Assigner | bash | sonnet46-200k-medium | 7.2min | 44 | 3 | $0.90 | 4.0 | bash | ok |
| PR Label Assigner | default | haiku45-200k-na | 2.9min | 27 | 3 | $0.25 | 1.5 | python | ok |
| PR Label Assigner | powershell | sonnet46-200k-medium | 8.4min | 35 | 3 | $1.11 | 4.0 | powershell | ok |
| PR Label Assigner | typescript-bun | sonnet46-200k-medium | 6.9min | 41 | 3 | $0.87 | 2.5 | typescript | ok |
| Dependency License Checker | default | sonnet46-1m-medium | 6.7min | 43 | 3 | $1.07 | 3.5 | python | ok |
| Dependency License Checker | typescript-bun | sonnet46-1m-medium | 8.4min | 50 | 3 | $1.23 | 4.0 | typescript | ok |
| Test Results Aggregator | typescript-bun | sonnet46-200k-medium | 11.0min | 39 | 3 | $1.47 | 4.0 | typescript | ok |
| Environment Matrix Generator | default | sonnet46-1m-medium | 3.7min | 25 | 3 | $0.56 | 2.0 | python | ok |
| Environment Matrix Generator | powershell | haiku45-200k-na | 4.6min | 43 | 3 | $0.39 | — | powershell | ok |
| Artifact Cleanup Script | bash | haiku45-200k-na | 6.6min | 51 | 3 | $0.43 | 2.5 | bash | ok |
| Artifact Cleanup Script | bash | opus47-1m-medium | 3.1min | 24 | 3 | $0.92 | 3.0 | bash | ok |
| Artifact Cleanup Script | typescript-bun | haiku45-200k-na | 3.8min | 39 | 3 | $0.33 | 2.0 | typescript | ok |
| Artifact Cleanup Script | typescript-bun | sonnet46-200k-medium | 3.6min | 26 | 3 | $0.49 | 3.0 | typescript | ok |
| Secret Rotation Validator | bash | haiku45-200k-na | 7.7min | 56 | 3 | $0.49 | 2.0 | bash | ok |
| Secret Rotation Validator | default | haiku45-200k-na | 4.2min | 38 | 3 | $0.34 | 1.5 | python | ok |
| Secret Rotation Validator | powershell | haiku45-200k-na | 11.4min | 40 | 3 | $0.39 | 3.0 | powershell | ok |
| Secret Rotation Validator | typescript-bun | sonnet46-1m-medium | 6.6min | 37 | 3 | $0.78 | 3.0 | typescript | ok |
| Semantic Version Bumper | bash | sonnet46-1m-medium | 10.0min | 40 | 4 | $1.38 | 3.0 | bash | ok |
| Semantic Version Bumper | powershell | haiku45-200k-na | 6.3min | 65 | 4 | $0.57 | — | powershell | ok |
| Semantic Version Bumper | typescript-bun | sonnet46-200k-medium | 7.4min | 33 | 4 | $0.68 | 2.0 | typescript | ok |
| Semantic Version Bumper | typescript-bun | sonnet46-1m-medium | 8.5min | 42 | 4 | $0.92 | 4.0 | typescript | ok |
| PR Label Assigner | bash | haiku45-200k-na | 7.1min | 62 | 4 | $0.50 | 2.0 | bash | ok |
| PR Label Assigner | bash | sonnet46-1m-medium | 3.1min | 28 | 4 | $0.50 | 2.0 | bash | ok |
| Dependency License Checker | default | sonnet46-200k-medium | 11.7min | 44 | 4 | $1.68 | 4.5 | python | ok |
| Test Results Aggregator | default | sonnet46-200k-medium | 6.5min | 43 | 4 | $1.17 | 4.5 | python | ok |
| Environment Matrix Generator | default | haiku45-200k-na | 4.0min | 42 | 4 | $0.38 | 2.0 | python | ok |
| Environment Matrix Generator | typescript-bun | haiku45-200k-na | 8.2min | 73 | 4 | $0.68 | 3.0 | typescript | ok |
| Artifact Cleanup Script | default | haiku45-200k-na | 4.8min | 45 | 4 | $0.46 | 2.5 | python | ok |
| Artifact Cleanup Script | typescript-bun | sonnet46-1m-medium | 7.9min | 49 | 4 | $1.37 | 4.0 | typescript | ok |
| Secret Rotation Validator | default | sonnet46-1m-medium | 8.0min | 31 | 4 | $1.16 | 4.5 | python | ok |
| Test Results Aggregator | bash | haiku45-200k-na | 7.4min | 77 | 5 | $0.64 | 2.5 | bash | ok |
| Test Results Aggregator | bash | sonnet46-1m-medium | 10.7min | 39 | 5 | $1.42 | 3.5 | bash | ok |
| Test Results Aggregator | default | haiku45-200k-na | 4.3min | 60 | 5 | $0.51 | 2.5 | python | ok |
| Test Results Aggregator | powershell | haiku45-200k-na | 7.1min | 63 | 5 | $0.63 | — | powershell | ok |
| Secret Rotation Validator | bash | sonnet46-200k-medium | 8.6min | 39 | 5 | $1.11 | 4.0 | bash | ok |
| Secret Rotation Validator | powershell | haiku45-200k-na | 6.8min | 56 | 5 | $0.49 | 2.0 | powershell | ok |
| Environment Matrix Generator | bash | sonnet46-1m-medium | 29.1min | 58 | 6 | $3.25 | 3.5 | bash | ok |
| Environment Matrix Generator | powershell | haiku45-200k-na | 6.1min | 49 | 6 | $0.56 | 3.5 | powershell | ok |
| Artifact Cleanup Script | bash | sonnet46-1m-medium | 11.6min | 45 | 6 | $1.78 | 4.0 | bash | ok |
| Secret Rotation Validator | bash | sonnet46-1m-medium | 10.0min | 41 | 6 | $1.10 | 3.5 | bash | ok |
| Secret Rotation Validator | typescript-bun | haiku45-200k-na | 3.8min | 55 | 6 | $0.42 | 2.0 | typescript | ok |
| Semantic Version Bumper | powershell | haiku45-200k-na | 15.1min | 92 | 7 | $0.93 | — | powershell | ok |
| PR Label Assigner | default | sonnet46-1m-medium | 9.6min | 44 | 7 | $1.38 | 3.0 | python | ok |
| Dependency License Checker | default | haiku45-200k-na | 4.0min | 47 | 7 | $0.40 | 2.5 | python | ok |
| Environment Matrix Generator | powershell | sonnet46-1m-medium | 8.1min | 36 | 7 | $1.04 | 4.0 | powershell | ok |
| Test Results Aggregator | typescript-bun | haiku45-200k-na | 7.8min | 67 | 9 | $0.60 | 2.0 | typescript | ok |
| Semantic Version Bumper | typescript-bun | haiku45-200k-na | 7.6min | 74 | 10 | $0.62 | 2.0 | typescript | ok |
| Environment Matrix Generator | bash | haiku45-200k-na | 322.8min | 85 | 10 | $0.75 | 2.0 | bash | timeout |
| Semantic Version Bumper | default | haiku45-200k-na | 59.1min | 97 | 12 | $0.84 | — | javascript | ok |

</details>

<details>
<summary>Sorted by turns (fewest first)</summary>

| Task | Language | Model | Duration | Turns | Errors | Cost | Tests Quality | Chosen | Status |
|------|----------|-------|----------|-------|--------|------|-----------|--------|--------|
| Environment Matrix Generator | bash | sonnet46-200k-medium | 4.2min | 7 | 1 | $0.35 | — | bash | cli_error |
| Environment Matrix Generator | powershell | sonnet46-200k-medium | 2.1min | 14 | 1 | $0.28 | 2.5 | powershell | ok |
| Environment Matrix Generator | powershell | sonnet46-1m-medium | 2.7min | 16 | 1 | $0.34 | 2.5 | powershell | ok |
| Artifact Cleanup Script | powershell | sonnet46-1m-medium | 3.1min | 18 | 2 | $0.46 | 3.0 | powershell | ok |
| PR Label Assigner | powershell | sonnet46-200k-medium | 2.9min | 19 | 0 | $0.38 | 1.5 | powershell | ok |
| Artifact Cleanup Script | default | opus47-1m-medium | 3.2min | 19 | 0 | $0.85 | 4.0 | python | ok |
| Secret Rotation Validator | default | opus47-1m-medium | 7.0min | 19 | 0 | $0.88 | 2.0 | python | ok |
| Secret Rotation Validator | powershell | opus47-200k-medium | 4.0min | 19 | 0 | $1.06 | 3.5 | powershell | ok |
| Secret Rotation Validator | powershell | sonnet46-200k-medium | 8.0min | 19 | 0 | $0.96 | 3.0 | powershell | ok |
| Artifact Cleanup Script | powershell | opus47-1m-medium | 4.1min | 20 | 0 | $0.96 | 4.0 | powershell | ok |
| PR Label Assigner | default | opus47-200k-medium | 3.2min | 21 | 0 | $0.70 | 2.0 | python | ok |
| Semantic Version Bumper | default | opus47-1m-medium | 4.1min | 22 | 0 | $0.93 | 4.0 | python | ok |
| Artifact Cleanup Script | powershell | opus47-1m-medium | 4.7min | 22 | 0 | $1.08 | 3.5 | powershell | ok |
| Artifact Cleanup Script | typescript-bun | opus47-200k-medium | 4.4min | 22 | 0 | $0.92 | 4.0 | typescript | ok |
| Secret Rotation Validator | bash | opus47-1m-high | 4.6min | 22 | 0 | $1.06 | 3.0 | bash | ok |
| Secret Rotation Validator | powershell | sonnet46-200k-medium | 3.4min | 22 | 1 | $0.47 | 2.5 | powershell | ok |
| Semantic Version Bumper | powershell | sonnet46-200k-medium | 3.9min | 23 | 1 | $0.44 | 4.0 | powershell | ok |
| PR Label Assigner | bash | opus47-1m-medium | 6.2min | 23 | 1 | $0.87 | 4.0 | bash | ok |
| PR Label Assigner | default | opus47-1m-high | 7.6min | 23 | 1 | $1.32 | 4.0 | python | ok |
| PR Label Assigner | default | opus47-1m-medium | 3.1min | 23 | 0 | $0.83 | 2.0 | python | ok |
| Dependency License Checker | powershell | opus47-1m-medium | 6.6min | 23 | 0 | $1.00 | 3.5 | powershell | ok |
| Test Results Aggregator | bash | sonnet46-200k-medium | 6.3min | 23 | 0 | $0.78 | 4.0 | bash | ok |
| Environment Matrix Generator | bash | opus47-1m-medium | 3.5min | 23 | 1 | $0.88 | 3.0 | bash | ok |
| Environment Matrix Generator | bash | opus47-200k-medium | 2.9min | 23 | 0 | $1.05 | 3.5 | bash | ok |
| Environment Matrix Generator | default | sonnet46-200k-medium | 2.9min | 23 | 2 | $0.41 | 2.0 | python | ok |
| Artifact Cleanup Script | default | opus47-200k-medium | 5.0min | 23 | 0 | $1.30 | 4.5 | python | ok |
| Artifact Cleanup Script | powershell | opus47-200k-medium | 4.0min | 23 | 0 | $1.09 | 3.5 | powershell | ok |
| Dependency License Checker | default | opus47-200k-medium | 4.1min | 24 | 0 | $0.97 | 4.5 | python | ok |
| Test Results Aggregator | powershell | sonnet46-1m-medium | 8.3min | 24 | 1 | $0.99 | 3.0 | powershell | ok |
| Artifact Cleanup Script | bash | opus47-1m-medium | 3.1min | 24 | 3 | $0.92 | 3.0 | bash | ok |
| Secret Rotation Validator | bash | opus47-1m-medium | 5.4min | 24 | 0 | $1.09 | 3.0 | bash | ok |
| Semantic Version Bumper | bash | opus47-200k-medium | 4.1min | 25 | 0 | $1.02 | 4.0 | bash | ok |
| Test Results Aggregator | default | sonnet46-1m-medium | 8.4min | 25 | 1 | $0.90 | 3.5 | python | ok |
| Test Results Aggregator | powershell | sonnet46-1m-medium | 11.4min | 25 | 2 | $1.32 | 4.0 | powershell | ok |
| Environment Matrix Generator | default | sonnet46-1m-medium | 3.7min | 25 | 3 | $0.56 | 2.0 | python | ok |
| Environment Matrix Generator | powershell | sonnet46-200k-medium | 8.0min | 25 | 1 | $1.00 | 4.0 | powershell | ok |
| Artifact Cleanup Script | bash | opus47-200k-medium | 5.8min | 25 | 1 | $1.26 | 3.0 | bash | ok |
| Secret Rotation Validator | default | opus47-200k-medium | 5.5min | 25 | 0 | $1.27 | 4.0 | python | ok |
| PR Label Assigner | powershell | haiku45-200k-na | 3.0min | 26 | 1 | $0.23 | 2.5 | powershell | ok |
| Dependency License Checker | bash | opus47-200k-medium | 7.5min | 26 | 1 | $0.92 | 3.0 | bash | ok |
| Dependency License Checker | powershell | opus47-1m-medium | 4.9min | 26 | 0 | $1.18 | 4.0 | powershell | ok |
| Environment Matrix Generator | default | opus47-1m-medium | 5.4min | 26 | 0 | $1.12 | 4.0 | python | ok |
| Artifact Cleanup Script | typescript-bun | sonnet46-200k-medium | 3.6min | 26 | 3 | $0.49 | 3.0 | typescript | ok |
| Semantic Version Bumper | powershell | sonnet46-1m-medium | 8.3min | 27 | 1 | $0.98 | 4.0 | powershell | ok |
| Semantic Version Bumper | powershell | opus47-200k-medium | 5.3min | 27 | 0 | $1.36 | 4.0 | powershell | ok |
| PR Label Assigner | default | haiku45-200k-na | 2.9min | 27 | 3 | $0.25 | 1.5 | python | ok |
| PR Label Assigner | powershell | opus47-1m-medium | 5.1min | 27 | 0 | $1.11 | 4.0 | powershell | ok |
| PR Label Assigner | powershell | opus47-200k-medium | 5.3min | 27 | 0 | $1.34 | 4.0 | powershell | ok |
| PR Label Assigner | typescript-bun | sonnet46-1m-medium | 4.7min | 27 | 0 | $0.67 | 3.0 | typescript | ok |
| Dependency License Checker | powershell | sonnet46-200k-medium | 9.0min | 27 | 1 | $1.04 | 3.5 | powershell | ok |
| Test Results Aggregator | powershell | opus47-1m-medium | 9.6min | 27 | 0 | $1.44 | 4.0 | powershell | ok |
| Test Results Aggregator | powershell | sonnet46-200k-medium | 7.7min | 27 | 0 | $1.03 | 4.0 | powershell | ok |
| Environment Matrix Generator | powershell | opus47-200k-medium | 6.0min | 27 | 1 | $1.51 | 4.0 | powershell | ok |
| PR Label Assigner | bash | sonnet46-1m-medium | 3.1min | 28 | 4 | $0.50 | 2.0 | bash | ok |
| PR Label Assigner | powershell | sonnet46-1m-medium | 4.4min | 28 | 1 | $0.59 | 2.5 | powershell | ok |
| PR Label Assigner | typescript-bun | opus47-200k-medium | 4.5min | 28 | 0 | $1.00 | 4.0 | typescript | ok |
| Environment Matrix Generator | default | opus47-200k-medium | 5.0min | 28 | 1 | $1.05 | 4.0 | python | ok |
| Artifact Cleanup Script | default | sonnet46-200k-medium | 8.2min | 28 | 2 | $1.14 | 4.0 | python | ok |
| Artifact Cleanup Script | powershell | sonnet46-1m-medium | 7.8min | 28 | 0 | $1.09 | 3.5 | powershell | ok |
| PR Label Assigner | bash | opus47-200k-medium | 5.0min | 29 | 3 | $1.18 | 2.0 | bash | ok |
| PR Label Assigner | powershell | opus47-1m-high | 5.7min | 29 | 1 | $1.67 | 4.5 | powershell | ok |
| PR Label Assigner | powershell | opus47-1m-medium | 7.4min | 29 | 0 | $1.33 | 3.5 | powershell | ok |
| Dependency License Checker | typescript-bun | opus47-200k-medium | 4.8min | 29 | 0 | $1.10 | 4.0 | typescript | ok |
| Test Results Aggregator | bash | opus47-200k-medium | 4.3min | 29 | 1 | $1.12 | 4.0 | bash | ok |
| Environment Matrix Generator | powershell | opus47-1m-medium | 4.6min | 29 | 2 | $1.30 | 3.5 | powershell | ok |
| Environment Matrix Generator | typescript-bun | opus47-1m-medium | 7.4min | 29 | 0 | $1.07 | 3.0 | typescript | ok |
| Artifact Cleanup Script | powershell | haiku45-200k-na | 3.2min | 29 | 2 | $0.28 | 1.5 | powershell | ok |
| Artifact Cleanup Script | typescript-bun | opus47-1m-medium | 7.2min | 29 | 0 | $1.25 | 3.5 | typescript | ok |
| Secret Rotation Validator | bash | opus47-200k-medium | 3.4min | 29 | 2 | $1.10 | 3.0 | bash | ok |
| Semantic Version Bumper | bash | opus47-1m-medium | 4.2min | 30 | 2 | $1.07 | 2.5 | bash | ok |
| PR Label Assigner | typescript-bun | opus47-1m-medium | 9.0min | 30 | 0 | $1.06 | 4.0 | typescript | ok |
| Dependency License Checker | bash | opus47-1m-high | 4.0min | 30 | 0 | $1.35 | 2.5 | bash | ok |
| Dependency License Checker | bash | opus47-1m-medium | 5.5min | 30 | 1 | $1.55 | 3.0 | bash | ok |
| Environment Matrix Generator | powershell | opus47-200k-medium | 6.1min | 30 | 0 | $1.42 | 4.0 | powershell | ok |
| Environment Matrix Generator | powershell | opus47-1m-high | 7.4min | 30 | 0 | $2.13 | 3.5 | powershell | ok |
| Secret Rotation Validator | default | opus47-1m-high | 7.9min | 30 | 1 | $1.93 | 4.5 | python | ok |
| Secret Rotation Validator | typescript-bun | sonnet46-200k-medium | 8.9min | 30 | 1 | $1.07 | 4.0 | typescript | ok |
| Semantic Version Bumper | bash | opus47-1m-high | 6.3min | 31 | 1 | $1.44 | 4.0 | bash | ok |
| Semantic Version Bumper | default | opus47-1m-high | 7.1min | 31 | 0 | $1.85 | — | javascript | ok |
| Semantic Version Bumper | default | opus47-200k-medium | 4.2min | 31 | 1 | $1.21 | — | javascript | ok |
| PR Label Assigner | bash | opus47-1m-high | 5.9min | 31 | 2 | $1.46 | 4.0 | bash | ok |
| PR Label Assigner | powershell | sonnet46-1m-medium | 12.0min | 31 | 1 | $1.61 | 4.5 | powershell | ok |
| Dependency License Checker | powershell | opus47-1m-high | 7.1min | 31 | 0 | $1.93 | 4.0 | powershell | ok |
| Test Results Aggregator | default | opus47-1m-medium | 6.9min | 31 | 0 | $1.28 | 3.5 | python | ok |
| Test Results Aggregator | powershell | opus47-200k-medium | 7.0min | 31 | 0 | $1.64 | 3.5 | powershell | ok |
| Environment Matrix Generator | typescript-bun | sonnet46-200k-medium | 6.4min | 31 | 2 | $0.90 | 3.5 | typescript | ok |
| Artifact Cleanup Script | bash | sonnet46-200k-medium | 4.4min | 31 | 2 | $0.61 | 2.5 | bash | ok |
| Artifact Cleanup Script | powershell | haiku45-200k-na | 7.8min | 31 | 2 | $0.28 | — | powershell | ok |
| Artifact Cleanup Script | powershell | sonnet46-200k-medium | 8.4min | 31 | 2 | $1.25 | 4.0 | powershell | ok |
| Secret Rotation Validator | default | sonnet46-1m-medium | 8.0min | 31 | 4 | $1.16 | 4.5 | python | ok |
| Secret Rotation Validator | powershell | opus47-1m-medium | 22.5min | 31 | 0 | $1.27 | 4.0 | powershell | ok |
| Dependency License Checker | typescript-bun | opus47-1m-medium | 8.2min | 32 | 1 | $1.34 | 4.0 | typescript | ok |
| Test Results Aggregator | powershell | sonnet46-200k-medium | 11.7min | 32 | 1 | $1.40 | 4.5 | powershell | ok |
| Artifact Cleanup Script | default | sonnet46-1m-medium | 6.8min | 32 | 2 | $1.02 | 4.5 | python | ok |
| Artifact Cleanup Script | powershell | opus47-200k-medium | 5.4min | 32 | 0 | $1.65 | 4.0 | powershell | ok |
| Secret Rotation Validator | powershell | opus47-200k-medium | 4.9min | 32 | 0 | $1.40 | 3.5 | powershell | ok |
| Semantic Version Bumper | default | sonnet46-1m-medium | 4.6min | 33 | 3 | $0.67 | 2.0 | python | ok |
| Semantic Version Bumper | powershell | opus47-200k-medium | 6.3min | 33 | 0 | $1.44 | 4.0 | powershell | ok |
| Semantic Version Bumper | powershell | sonnet46-200k-medium | 5.9min | 33 | 2 | $0.87 | 4.5 | powershell | ok |
| Semantic Version Bumper | typescript-bun | opus47-1m-medium | 5.6min | 33 | 0 | $1.31 | 4.0 | typescript | ok |
| Semantic Version Bumper | typescript-bun | sonnet46-200k-medium | 7.4min | 33 | 4 | $0.68 | 2.0 | typescript | ok |
| Test Results Aggregator | typescript-bun | opus47-200k-medium | 6.4min | 33 | 1 | $1.53 | 3.5 | typescript | ok |
| Secret Rotation Validator | powershell | sonnet46-1m-medium | 7.8min | 33 | 1 | $0.94 | 2.5 | powershell | ok |
| Semantic Version Bumper | powershell | opus47-1m-high | 6.1min | 34 | 0 | $1.78 | 4.5 | powershell | ok |
| PR Label Assigner | default | sonnet46-200k-medium | 4.4min | 34 | 1 | $0.66 | 2.5 | python | ok |
| Dependency License Checker | bash | sonnet46-200k-medium | 6.9min | 34 | 2 | $0.97 | 2.0 | bash | ok |
| Dependency License Checker | default | opus47-1m-medium | 8.2min | 34 | 2 | $1.33 | 4.0 | python | ok |
| Dependency License Checker | powershell | opus47-200k-medium | 6.3min | 34 | 1 | $1.68 | 4.0 | powershell | ok |
| Test Results Aggregator | typescript-bun | sonnet46-1m-medium | 8.5min | 34 | 2 | $1.11 | 3.5 | typescript | ok |
| Environment Matrix Generator | default | opus47-1m-xhigh | 6.8min | 34 | 2 | $2.01 | 3.0 | python | ok |
| Artifact Cleanup Script | bash | opus47-1m-xhigh | 7.6min | 34 | 1 | $1.84 | 4.0 | bash | ok |
| Semantic Version Bumper | powershell | opus47-1m-medium | 8.6min | 35 | 0 | $1.69 | 4.5 | powershell | ok |
| Semantic Version Bumper | typescript-bun | opus47-200k-medium | 5.1min | 35 | 1 | $1.58 | 3.5 | typescript | ok |
| PR Label Assigner | powershell | sonnet46-200k-medium | 8.4min | 35 | 3 | $1.11 | 4.0 | powershell | ok |
| Dependency License Checker | typescript-bun | sonnet46-200k-medium | 6.8min | 35 | 2 | $0.93 | 3.5 | typescript | ok |
| Test Results Aggregator | bash | opus47-1m-medium | 6.7min | 35 | 0 | $1.36 | 4.0 | bash | ok |
| Test Results Aggregator | default | opus47-200k-medium | 6.1min | 35 | 1 | $1.68 | 4.0 | python | ok |
| Test Results Aggregator | typescript-bun | opus47-1m-medium | 8.4min | 35 | 0 | $1.49 | 4.0 | typescript | ok |
| Artifact Cleanup Script | default | opus47-1m-xhigh | 7.1min | 35 | 1 | $1.91 | 4.5 | python | ok |
| Secret Rotation Validator | bash | opus47-1m-xhigh | 9.4min | 35 | 0 | $2.40 | 3.5 | bash | ok |
| Secret Rotation Validator | typescript-bun | opus47-1m-medium | 7.4min | 35 | 2 | $1.46 | 4.0 | typescript | ok |
| Semantic Version Bumper | bash | sonnet46-200k-medium | 4.5min | 36 | 2 | $0.64 | 3.0 | bash | ok |
| Dependency License Checker | bash | sonnet46-1m-medium | 9.1min | 36 | 1 | $1.28 | 4.0 | bash | ok |
| Environment Matrix Generator | powershell | sonnet46-1m-medium | 8.1min | 36 | 7 | $1.04 | 4.0 | powershell | ok |
| Environment Matrix Generator | typescript-bun | opus47-200k-medium | 6.5min | 36 | 1 | $1.41 | 4.0 | typescript | ok |
| Artifact Cleanup Script | default | opus47-1m-high | 6.6min | 36 | 0 | $2.04 | 4.5 | python | ok |
| Secret Rotation Validator | powershell | opus47-1m-high | 6.7min | 36 | 0 | $1.89 | 4.5 | powershell | ok |
| Secret Rotation Validator | powershell | sonnet46-1m-medium | 9.9min | 36 | 1 | $1.35 | 3.5 | powershell | ok |
| Secret Rotation Validator | typescript-bun | opus47-200k-medium | 6.9min | 36 | 0 | $1.92 | 3.5 | typescript | ok |
| Semantic Version Bumper | powershell | opus47-1m-medium | 8.0min | 37 | 1 | $1.75 | 4.0 | powershell | ok |
| PR Label Assigner | powershell | opus47-1m-xhigh | 7.7min | 37 | 0 | $2.01 | 4.0 | powershell | ok |
| Dependency License Checker | default | opus47-1m-high | 8.5min | 37 | 0 | $2.28 | 4.0 | python | ok |
| Test Results Aggregator | powershell | opus47-200k-medium | 7.1min | 37 | 1 | $1.79 | 3.5 | powershell | ok |
| Test Results Aggregator | powershell | opus47-1m-medium | 9.4min | 37 | 0 | $1.76 | 3.5 | powershell | ok |
| Secret Rotation Validator | typescript-bun | sonnet46-1m-medium | 6.6min | 37 | 3 | $0.78 | 3.0 | typescript | ok |
| Semantic Version Bumper | powershell | opus47-1m-xhigh | 7.7min | 38 | 0 | $2.27 | 4.5 | powershell | ok |
| PR Label Assigner | powershell | opus47-200k-medium | 8.5min | 38 | 0 | $1.93 | 4.0 | powershell | ok |
| Dependency License Checker | bash | opus47-1m-xhigh | 39.8min | 38 | 2 | $2.19 | 2.5 | bash | ok |
| Environment Matrix Generator | default | opus47-1m-high | 5.7min | 38 | 0 | $1.87 | 4.0 | python | ok |
| Secret Rotation Validator | default | haiku45-200k-na | 4.2min | 38 | 3 | $0.34 | 1.5 | python | ok |
| Secret Rotation Validator | powershell | opus47-1m-medium | 17.8min | 38 | 2 | $1.70 | 4.0 | powershell | ok |
| Secret Rotation Validator | powershell | opus47-1m-xhigh | 9.9min | 38 | 0 | $2.58 | 4.0 | powershell | ok |
| Test Results Aggregator | bash | sonnet46-1m-medium | 10.7min | 39 | 5 | $1.42 | 3.5 | bash | ok |
| Test Results Aggregator | typescript-bun | sonnet46-200k-medium | 11.0min | 39 | 3 | $1.47 | 4.0 | typescript | ok |
| Artifact Cleanup Script | powershell | opus47-1m-high | 9.4min | 39 | 0 | $2.30 | 4.5 | powershell | ok |
| Artifact Cleanup Script | typescript-bun | haiku45-200k-na | 3.8min | 39 | 3 | $0.33 | 2.0 | typescript | ok |
| Artifact Cleanup Script | typescript-bun | opus47-1m-high | 9.2min | 39 | 0 | $2.07 | 4.5 | typescript | ok |
| Secret Rotation Validator | bash | sonnet46-200k-medium | 8.6min | 39 | 5 | $1.11 | 4.0 | bash | ok |
| Semantic Version Bumper | bash | sonnet46-1m-medium | 10.0min | 40 | 4 | $1.38 | 3.0 | bash | ok |
| Semantic Version Bumper | powershell | opus47-1m-high | 8.0min | 40 | 0 | $2.23 | 4.5 | powershell | ok |
| Semantic Version Bumper | powershell | sonnet46-1m-medium | 11.9min | 40 | 1 | $1.69 | 3.5 | powershell | ok |
| Dependency License Checker | default | opus47-1m-xhigh | 7.5min | 40 | 0 | $2.04 | 4.0 | python | ok |
| Dependency License Checker | powershell | sonnet46-200k-medium | 8.6min | 40 | 0 | $1.09 | 3.0 | powershell | ok |
| Secret Rotation Validator | powershell | haiku45-200k-na | 11.4min | 40 | 3 | $0.39 | 3.0 | powershell | ok |
| PR Label Assigner | typescript-bun | sonnet46-200k-medium | 6.9min | 41 | 3 | $0.87 | 2.5 | typescript | ok |
| Dependency License Checker | powershell | opus47-200k-medium | 8.0min | 41 | 1 | $1.86 | 3.5 | powershell | ok |
| Environment Matrix Generator | powershell | opus47-1m-high | 7.0min | 41 | 0 | $2.04 | 4.0 | powershell | ok |
| Secret Rotation Validator | bash | sonnet46-1m-medium | 10.0min | 41 | 6 | $1.10 | 3.5 | bash | ok |
| Secret Rotation Validator | powershell | opus47-1m-high | 8.2min | 41 | 0 | $2.29 | 4.5 | powershell | ok |
| Semantic Version Bumper | default | sonnet46-200k-medium | 5.8min | 42 | 3 | $0.94 | 4.0 | python | ok |
| Semantic Version Bumper | typescript-bun | sonnet46-1m-medium | 8.5min | 42 | 4 | $0.92 | 4.0 | typescript | ok |
| Dependency License Checker | powershell | opus47-1m-high | 10.1min | 42 | 0 | $2.43 | 4.0 | powershell | ok |
| Environment Matrix Generator | bash | opus47-1m-high | 6.6min | 42 | 0 | $1.69 | 4.0 | bash | ok |
| Environment Matrix Generator | default | haiku45-200k-na | 4.0min | 42 | 4 | $0.38 | 2.0 | python | ok |
| Environment Matrix Generator | typescript-bun | opus47-1m-high | 6.7min | 42 | 0 | $2.13 | 3.5 | typescript | ok |
| Environment Matrix Generator | typescript-bun | sonnet46-1m-medium | 12.2min | 42 | 2 | $1.34 | 3.5 | typescript | ok |
| Secret Rotation Validator | default | sonnet46-200k-medium | 8.5min | 42 | 2 | $1.25 | 3.5 | python | ok |
| PR Label Assigner | default | opus47-1m-xhigh | 7.8min | 43 | 0 | $2.25 | 4.0 | python | ok |
| PR Label Assigner | powershell | opus47-1m-xhigh | 9.6min | 43 | 0 | $2.60 | 4.0 | powershell | ok |
| PR Label Assigner | typescript-bun | haiku45-200k-na | 6.0min | 43 | 2 | $0.37 | 2.0 | typescript | ok |
| Dependency License Checker | default | sonnet46-1m-medium | 6.7min | 43 | 3 | $1.07 | 3.5 | python | ok |
| Dependency License Checker | powershell | sonnet46-1m-medium | 7.1min | 43 | 1 | $1.05 | 4.5 | powershell | ok |
| Test Results Aggregator | default | sonnet46-200k-medium | 6.5min | 43 | 4 | $1.17 | 4.5 | python | ok |
| Environment Matrix Generator | powershell | haiku45-200k-na | 4.6min | 43 | 3 | $0.39 | — | powershell | ok |
| Environment Matrix Generator | powershell | opus47-1m-xhigh | 10.2min | 43 | 1 | $3.08 | 4.0 | powershell | ok |
| Artifact Cleanup Script | powershell | opus47-1m-xhigh | 10.9min | 43 | 0 | $3.19 | 4.5 | powershell | ok |
| PR Label Assigner | bash | sonnet46-200k-medium | 7.2min | 44 | 3 | $0.90 | 4.0 | bash | ok |
| PR Label Assigner | default | sonnet46-1m-medium | 9.6min | 44 | 7 | $1.38 | 3.0 | python | ok |
| PR Label Assigner | powershell | haiku45-200k-na | 5.2min | 44 | 1 | $0.38 | 2.0 | powershell | ok |
| PR Label Assigner | typescript-bun | opus47-1m-high | 7.3min | 44 | 0 | $1.86 | 4.0 | typescript | ok |
| Dependency License Checker | default | sonnet46-200k-medium | 11.7min | 44 | 4 | $1.68 | 4.5 | python | ok |
| Test Results Aggregator | default | opus47-1m-high | 6.5min | 44 | 0 | $2.37 | 4.0 | python | ok |
| Test Results Aggregator | typescript-bun | opus47-1m-high | 8.6min | 44 | 0 | $1.52 | 4.0 | typescript | ok |
| Artifact Cleanup Script | bash | opus47-1m-high | 9.1min | 44 | 0 | $2.18 | 3.5 | bash | ok |
| Semantic Version Bumper | default | opus47-1m-xhigh | 6.8min | 45 | 0 | $2.45 | 4.5 | python | ok |
| Dependency License Checker | powershell | sonnet46-1m-medium | 12.0min | 45 | 1 | $1.79 | 4.0 | powershell | ok |
| Artifact Cleanup Script | bash | sonnet46-1m-medium | 11.6min | 45 | 6 | $1.78 | 4.0 | bash | ok |
| Artifact Cleanup Script | default | haiku45-200k-na | 4.8min | 45 | 4 | $0.46 | 2.5 | python | ok |
| Secret Rotation Validator | default | opus47-1m-xhigh | 9.1min | 45 | 0 | $2.54 | 4.0 | python | ok |
| Secret Rotation Validator | powershell | opus47-1m-xhigh | 11.0min | 46 | 2 | $3.07 | 4.5 | powershell | ok |
| Secret Rotation Validator | typescript-bun | opus47-1m-xhigh | 8.2min | 46 | 1 | $2.52 | 4.5 | typescript | ok |
| Dependency License Checker | bash | haiku45-200k-na | 14.2min | 47 | 2 | $0.36 | 2.5 | bash | ok |
| Dependency License Checker | default | haiku45-200k-na | 4.0min | 47 | 7 | $0.40 | 2.5 | python | ok |
| Semantic Version Bumper | bash | haiku45-200k-na | 6.3min | 48 | 1 | $0.45 | 2.5 | bash | ok |
| Semantic Version Bumper | bash | opus47-1m-xhigh | 17.2min | 48 | 2 | $2.95 | 4.5 | bash | ok |
| Dependency License Checker | powershell | opus47-1m-xhigh | 10.2min | 48 | 1 | $2.95 | 4.0 | powershell | ok |
| Dependency License Checker | powershell | opus47-1m-xhigh | 11.2min | 48 | 0 | $2.86 | 4.0 | powershell | ok |
| Dependency License Checker | typescript-bun | haiku45-200k-na | 4.3min | 48 | 1 | $0.39 | 2.0 | typescript | ok |
| Test Results Aggregator | bash | opus47-1m-high | 11.3min | 48 | 1 | $2.37 | 3.5 | bash | ok |
| Semantic Version Bumper | powershell | opus47-1m-xhigh | 8.0min | 49 | 0 | $2.90 | 3.5 | powershell | ok |
| PR Label Assigner | powershell | opus47-1m-high | 10.0min | 49 | 1 | $2.92 | 4.0 | powershell | ok |
| Test Results Aggregator | powershell | opus47-1m-high | 11.1min | 49 | 1 | $3.14 | 4.0 | powershell | ok |
| Environment Matrix Generator | powershell | haiku45-200k-na | 6.1min | 49 | 6 | $0.56 | 3.5 | powershell | ok |
| Artifact Cleanup Script | typescript-bun | sonnet46-1m-medium | 7.9min | 49 | 4 | $1.37 | 4.0 | typescript | ok |
| Dependency License Checker | typescript-bun | sonnet46-1m-medium | 8.4min | 50 | 3 | $1.23 | 4.0 | typescript | ok |
| Artifact Cleanup Script | powershell | sonnet46-200k-medium | 6.0min | 50 | 1 | $0.94 | 4.0 | powershell | ok |
| Environment Matrix Generator | bash | opus47-1m-xhigh | 8.3min | 51 | 2 | $2.49 | 3.5 | bash | ok |
| Artifact Cleanup Script | bash | haiku45-200k-na | 6.6min | 51 | 3 | $0.43 | 2.5 | bash | ok |
| Artifact Cleanup Script | powershell | opus47-1m-xhigh | 12.0min | 51 | 1 | $3.21 | 4.0 | powershell | ok |
| Environment Matrix Generator | typescript-bun | opus47-1m-xhigh | 9.8min | 52 | 0 | $2.60 | 4.5 | typescript | ok |
| Artifact Cleanup Script | typescript-bun | opus47-1m-xhigh | 8.5min | 53 | 0 | $2.41 | 4.5 | typescript | ok |
| Test Results Aggregator | default | opus47-1m-xhigh | 9.2min | 54 | 1 | $2.81 | 4.0 | python | ok |
| Environment Matrix Generator | powershell | opus47-1m-xhigh | 13.5min | 54 | 0 | $3.93 | 4.0 | powershell | ok |
| Artifact Cleanup Script | powershell | opus47-1m-high | 11.7min | 54 | 1 | $3.33 | 4.0 | powershell | ok |
| Dependency License Checker | powershell | haiku45-200k-na | 4.0min | 55 | 2 | $0.42 | 2.5 | powershell | ok |
| Secret Rotation Validator | typescript-bun | haiku45-200k-na | 3.8min | 55 | 6 | $0.42 | 2.0 | typescript | ok |
| Secret Rotation Validator | typescript-bun | opus47-1m-high | 9.5min | 55 | 0 | $2.95 | 3.5 | typescript | ok |
| Secret Rotation Validator | bash | haiku45-200k-na | 7.7min | 56 | 3 | $0.49 | 2.0 | bash | ok |
| Secret Rotation Validator | powershell | haiku45-200k-na | 6.8min | 56 | 5 | $0.49 | 2.0 | powershell | ok |
| PR Label Assigner | typescript-bun | opus47-1m-xhigh | 10.4min | 57 | 0 | $3.05 | 4.5 | typescript | ok |
| Environment Matrix Generator | bash | sonnet46-1m-medium | 29.1min | 58 | 6 | $3.25 | 3.5 | bash | ok |
| Environment Matrix Generator | powershell | opus47-1m-medium | 14.0min | 59 | 0 | $3.01 | 4.0 | powershell | ok |
| Test Results Aggregator | default | haiku45-200k-na | 4.3min | 60 | 5 | $0.51 | 2.5 | python | ok |
| PR Label Assigner | bash | opus47-1m-xhigh | 16.7min | 61 | 2 | $3.14 | 3.5 | bash | ok |
| Semantic Version Bumper | typescript-bun | opus47-1m-high | 10.9min | 62 | 1 | $2.99 | 4.5 | typescript | ok |
| PR Label Assigner | bash | haiku45-200k-na | 7.1min | 62 | 4 | $0.50 | 2.0 | bash | ok |
| Test Results Aggregator | powershell | haiku45-200k-na | 6.6min | 63 | 2 | $0.62 | 1.5 | powershell | ok |
| Test Results Aggregator | powershell | haiku45-200k-na | 7.1min | 63 | 5 | $0.63 | — | powershell | ok |
| Test Results Aggregator | powershell | opus47-1m-xhigh | 15.2min | 63 | 0 | $5.47 | 4.0 | powershell | ok |
| Semantic Version Bumper | powershell | haiku45-200k-na | 6.3min | 65 | 4 | $0.57 | — | powershell | ok |
| Test Results Aggregator | typescript-bun | haiku45-200k-na | 7.8min | 67 | 9 | $0.60 | 2.0 | typescript | ok |
| Dependency License Checker | typescript-bun | opus47-1m-high | 10.9min | 68 | 0 | $3.08 | 4.5 | typescript | ok |
| Test Results Aggregator | powershell | opus47-1m-high | 15.9min | 69 | 1 | $3.91 | 4.0 | powershell | ok |
| Dependency License Checker | powershell | haiku45-200k-na | 7.6min | 70 | 1 | $0.58 | 2.5 | powershell | ok |
| Environment Matrix Generator | typescript-bun | haiku45-200k-na | 8.2min | 73 | 4 | $0.68 | 3.0 | typescript | ok |
| Semantic Version Bumper | typescript-bun | haiku45-200k-na | 7.6min | 74 | 10 | $0.62 | 2.0 | typescript | ok |
| Dependency License Checker | typescript-bun | opus47-1m-xhigh | 11.8min | 74 | 0 | $3.64 | 4.5 | typescript | ok |
| Test Results Aggregator | powershell | opus47-1m-xhigh | 17.3min | 74 | 0 | $4.47 | 3.5 | powershell | ok |
| Test Results Aggregator | bash | haiku45-200k-na | 7.4min | 77 | 5 | $0.64 | 2.5 | bash | ok |
| Test Results Aggregator | bash | opus47-1m-xhigh | 16.5min | 79 | 1 | $5.09 | 4.5 | bash | ok |
| Semantic Version Bumper | typescript-bun | opus47-1m-xhigh | 14.3min | 80 | 1 | $4.21 | 4.5 | typescript | ok |
| Environment Matrix Generator | bash | haiku45-200k-na | 322.8min | 85 | 10 | $0.75 | 2.0 | bash | timeout |
| Semantic Version Bumper | powershell | haiku45-200k-na | 15.1min | 92 | 7 | $0.93 | — | powershell | ok |
| Semantic Version Bumper | default | haiku45-200k-na | 59.1min | 97 | 12 | $0.84 | — | javascript | ok |
| Test Results Aggregator | typescript-bun | opus47-1m-xhigh | 20.8min | 103 | 1 | $6.31 | 4.5 | typescript | ok |

</details>

<details>
<summary>Sorted by LLM-as-judge score (best first)</summary>

| Task | Language | Model | Duration | Turns | Errors | Cost | Tests Quality | Chosen | Status |
|------|----------|-------|----------|-------|--------|------|-----------|--------|--------|
| Semantic Version Bumper | bash | opus47-1m-xhigh | 17.2min | 48 | 2 | $2.95 | 4.5 | bash | ok |
| Semantic Version Bumper | default | opus47-1m-xhigh | 6.8min | 45 | 0 | $2.45 | 4.5 | python | ok |
| Semantic Version Bumper | powershell | opus47-1m-high | 8.0min | 40 | 0 | $2.23 | 4.5 | powershell | ok |
| Semantic Version Bumper | powershell | opus47-1m-medium | 8.6min | 35 | 0 | $1.69 | 4.5 | powershell | ok |
| Semantic Version Bumper | powershell | opus47-1m-xhigh | 7.7min | 38 | 0 | $2.27 | 4.5 | powershell | ok |
| Semantic Version Bumper | powershell | opus47-1m-high | 6.1min | 34 | 0 | $1.78 | 4.5 | powershell | ok |
| Semantic Version Bumper | powershell | sonnet46-200k-medium | 5.9min | 33 | 2 | $0.87 | 4.5 | powershell | ok |
| Semantic Version Bumper | typescript-bun | opus47-1m-high | 10.9min | 62 | 1 | $2.99 | 4.5 | typescript | ok |
| Semantic Version Bumper | typescript-bun | opus47-1m-xhigh | 14.3min | 80 | 1 | $4.21 | 4.5 | typescript | ok |
| PR Label Assigner | powershell | sonnet46-1m-medium | 12.0min | 31 | 1 | $1.61 | 4.5 | powershell | ok |
| PR Label Assigner | powershell | opus47-1m-high | 5.7min | 29 | 1 | $1.67 | 4.5 | powershell | ok |
| PR Label Assigner | typescript-bun | opus47-1m-xhigh | 10.4min | 57 | 0 | $3.05 | 4.5 | typescript | ok |
| Dependency License Checker | default | opus47-200k-medium | 4.1min | 24 | 0 | $0.97 | 4.5 | python | ok |
| Dependency License Checker | default | sonnet46-200k-medium | 11.7min | 44 | 4 | $1.68 | 4.5 | python | ok |
| Dependency License Checker | powershell | sonnet46-1m-medium | 7.1min | 43 | 1 | $1.05 | 4.5 | powershell | ok |
| Dependency License Checker | typescript-bun | opus47-1m-high | 10.9min | 68 | 0 | $3.08 | 4.5 | typescript | ok |
| Dependency License Checker | typescript-bun | opus47-1m-xhigh | 11.8min | 74 | 0 | $3.64 | 4.5 | typescript | ok |
| Test Results Aggregator | bash | opus47-1m-xhigh | 16.5min | 79 | 1 | $5.09 | 4.5 | bash | ok |
| Test Results Aggregator | default | sonnet46-200k-medium | 6.5min | 43 | 4 | $1.17 | 4.5 | python | ok |
| Test Results Aggregator | powershell | sonnet46-200k-medium | 11.7min | 32 | 1 | $1.40 | 4.5 | powershell | ok |
| Test Results Aggregator | typescript-bun | opus47-1m-xhigh | 20.8min | 103 | 1 | $6.31 | 4.5 | typescript | ok |
| Environment Matrix Generator | typescript-bun | opus47-1m-xhigh | 9.8min | 52 | 0 | $2.60 | 4.5 | typescript | ok |
| Artifact Cleanup Script | default | opus47-1m-high | 6.6min | 36 | 0 | $2.04 | 4.5 | python | ok |
| Artifact Cleanup Script | default | opus47-1m-xhigh | 7.1min | 35 | 1 | $1.91 | 4.5 | python | ok |
| Artifact Cleanup Script | default | opus47-200k-medium | 5.0min | 23 | 0 | $1.30 | 4.5 | python | ok |
| Artifact Cleanup Script | default | sonnet46-1m-medium | 6.8min | 32 | 2 | $1.02 | 4.5 | python | ok |
| Artifact Cleanup Script | powershell | opus47-1m-high | 9.4min | 39 | 0 | $2.30 | 4.5 | powershell | ok |
| Artifact Cleanup Script | powershell | opus47-1m-xhigh | 10.9min | 43 | 0 | $3.19 | 4.5 | powershell | ok |
| Artifact Cleanup Script | typescript-bun | opus47-1m-high | 9.2min | 39 | 0 | $2.07 | 4.5 | typescript | ok |
| Artifact Cleanup Script | typescript-bun | opus47-1m-xhigh | 8.5min | 53 | 0 | $2.41 | 4.5 | typescript | ok |
| Secret Rotation Validator | default | opus47-1m-high | 7.9min | 30 | 1 | $1.93 | 4.5 | python | ok |
| Secret Rotation Validator | default | sonnet46-1m-medium | 8.0min | 31 | 4 | $1.16 | 4.5 | python | ok |
| Secret Rotation Validator | powershell | opus47-1m-high | 6.7min | 36 | 0 | $1.89 | 4.5 | powershell | ok |
| Secret Rotation Validator | powershell | opus47-1m-xhigh | 11.0min | 46 | 2 | $3.07 | 4.5 | powershell | ok |
| Secret Rotation Validator | powershell | opus47-1m-high | 8.2min | 41 | 0 | $2.29 | 4.5 | powershell | ok |
| Secret Rotation Validator | typescript-bun | opus47-1m-xhigh | 8.2min | 46 | 1 | $2.52 | 4.5 | typescript | ok |
| Semantic Version Bumper | bash | opus47-1m-high | 6.3min | 31 | 1 | $1.44 | 4.0 | bash | ok |
| Semantic Version Bumper | bash | opus47-200k-medium | 4.1min | 25 | 0 | $1.02 | 4.0 | bash | ok |
| Semantic Version Bumper | default | opus47-1m-medium | 4.1min | 22 | 0 | $0.93 | 4.0 | python | ok |
| Semantic Version Bumper | default | sonnet46-200k-medium | 5.8min | 42 | 3 | $0.94 | 4.0 | python | ok |
| Semantic Version Bumper | powershell | opus47-200k-medium | 6.3min | 33 | 0 | $1.44 | 4.0 | powershell | ok |
| Semantic Version Bumper | powershell | sonnet46-200k-medium | 3.9min | 23 | 1 | $0.44 | 4.0 | powershell | ok |
| Semantic Version Bumper | powershell | sonnet46-1m-medium | 8.3min | 27 | 1 | $0.98 | 4.0 | powershell | ok |
| Semantic Version Bumper | powershell | opus47-1m-medium | 8.0min | 37 | 1 | $1.75 | 4.0 | powershell | ok |
| Semantic Version Bumper | powershell | opus47-200k-medium | 5.3min | 27 | 0 | $1.36 | 4.0 | powershell | ok |
| Semantic Version Bumper | typescript-bun | opus47-1m-medium | 5.6min | 33 | 0 | $1.31 | 4.0 | typescript | ok |
| Semantic Version Bumper | typescript-bun | sonnet46-1m-medium | 8.5min | 42 | 4 | $0.92 | 4.0 | typescript | ok |
| PR Label Assigner | bash | opus47-1m-high | 5.9min | 31 | 2 | $1.46 | 4.0 | bash | ok |
| PR Label Assigner | bash | opus47-1m-medium | 6.2min | 23 | 1 | $0.87 | 4.0 | bash | ok |
| PR Label Assigner | bash | sonnet46-200k-medium | 7.2min | 44 | 3 | $0.90 | 4.0 | bash | ok |
| PR Label Assigner | default | opus47-1m-high | 7.6min | 23 | 1 | $1.32 | 4.0 | python | ok |
| PR Label Assigner | default | opus47-1m-xhigh | 7.8min | 43 | 0 | $2.25 | 4.0 | python | ok |
| PR Label Assigner | powershell | opus47-1m-high | 10.0min | 49 | 1 | $2.92 | 4.0 | powershell | ok |
| PR Label Assigner | powershell | opus47-1m-medium | 5.1min | 27 | 0 | $1.11 | 4.0 | powershell | ok |
| PR Label Assigner | powershell | opus47-1m-xhigh | 9.6min | 43 | 0 | $2.60 | 4.0 | powershell | ok |
| PR Label Assigner | powershell | opus47-200k-medium | 8.5min | 38 | 0 | $1.93 | 4.0 | powershell | ok |
| PR Label Assigner | powershell | opus47-1m-xhigh | 7.7min | 37 | 0 | $2.01 | 4.0 | powershell | ok |
| PR Label Assigner | powershell | opus47-200k-medium | 5.3min | 27 | 0 | $1.34 | 4.0 | powershell | ok |
| PR Label Assigner | powershell | sonnet46-200k-medium | 8.4min | 35 | 3 | $1.11 | 4.0 | powershell | ok |
| PR Label Assigner | typescript-bun | opus47-1m-high | 7.3min | 44 | 0 | $1.86 | 4.0 | typescript | ok |
| PR Label Assigner | typescript-bun | opus47-1m-medium | 9.0min | 30 | 0 | $1.06 | 4.0 | typescript | ok |
| PR Label Assigner | typescript-bun | opus47-200k-medium | 4.5min | 28 | 0 | $1.00 | 4.0 | typescript | ok |
| Dependency License Checker | bash | sonnet46-1m-medium | 9.1min | 36 | 1 | $1.28 | 4.0 | bash | ok |
| Dependency License Checker | default | opus47-1m-high | 8.5min | 37 | 0 | $2.28 | 4.0 | python | ok |
| Dependency License Checker | default | opus47-1m-medium | 8.2min | 34 | 2 | $1.33 | 4.0 | python | ok |
| Dependency License Checker | default | opus47-1m-xhigh | 7.5min | 40 | 0 | $2.04 | 4.0 | python | ok |
| Dependency License Checker | powershell | opus47-1m-high | 7.1min | 31 | 0 | $1.93 | 4.0 | powershell | ok |
| Dependency License Checker | powershell | opus47-1m-xhigh | 10.2min | 48 | 1 | $2.95 | 4.0 | powershell | ok |
| Dependency License Checker | powershell | opus47-1m-high | 10.1min | 42 | 0 | $2.43 | 4.0 | powershell | ok |
| Dependency License Checker | powershell | opus47-1m-medium | 4.9min | 26 | 0 | $1.18 | 4.0 | powershell | ok |
| Dependency License Checker | powershell | opus47-1m-xhigh | 11.2min | 48 | 0 | $2.86 | 4.0 | powershell | ok |
| Dependency License Checker | powershell | opus47-200k-medium | 6.3min | 34 | 1 | $1.68 | 4.0 | powershell | ok |
| Dependency License Checker | powershell | sonnet46-1m-medium | 12.0min | 45 | 1 | $1.79 | 4.0 | powershell | ok |
| Dependency License Checker | typescript-bun | opus47-1m-medium | 8.2min | 32 | 1 | $1.34 | 4.0 | typescript | ok |
| Dependency License Checker | typescript-bun | opus47-200k-medium | 4.8min | 29 | 0 | $1.10 | 4.0 | typescript | ok |
| Dependency License Checker | typescript-bun | sonnet46-1m-medium | 8.4min | 50 | 3 | $1.23 | 4.0 | typescript | ok |
| Test Results Aggregator | bash | opus47-1m-medium | 6.7min | 35 | 0 | $1.36 | 4.0 | bash | ok |
| Test Results Aggregator | bash | opus47-200k-medium | 4.3min | 29 | 1 | $1.12 | 4.0 | bash | ok |
| Test Results Aggregator | bash | sonnet46-200k-medium | 6.3min | 23 | 0 | $0.78 | 4.0 | bash | ok |
| Test Results Aggregator | default | opus47-1m-high | 6.5min | 44 | 0 | $2.37 | 4.0 | python | ok |
| Test Results Aggregator | default | opus47-1m-xhigh | 9.2min | 54 | 1 | $2.81 | 4.0 | python | ok |
| Test Results Aggregator | default | opus47-200k-medium | 6.1min | 35 | 1 | $1.68 | 4.0 | python | ok |
| Test Results Aggregator | powershell | opus47-1m-high | 11.1min | 49 | 1 | $3.14 | 4.0 | powershell | ok |
| Test Results Aggregator | powershell | opus47-1m-medium | 9.6min | 27 | 0 | $1.44 | 4.0 | powershell | ok |
| Test Results Aggregator | powershell | sonnet46-200k-medium | 7.7min | 27 | 0 | $1.03 | 4.0 | powershell | ok |
| Test Results Aggregator | powershell | opus47-1m-high | 15.9min | 69 | 1 | $3.91 | 4.0 | powershell | ok |
| Test Results Aggregator | powershell | opus47-1m-xhigh | 15.2min | 63 | 0 | $5.47 | 4.0 | powershell | ok |
| Test Results Aggregator | powershell | sonnet46-1m-medium | 11.4min | 25 | 2 | $1.32 | 4.0 | powershell | ok |
| Test Results Aggregator | typescript-bun | opus47-1m-high | 8.6min | 44 | 0 | $1.52 | 4.0 | typescript | ok |
| Test Results Aggregator | typescript-bun | opus47-1m-medium | 8.4min | 35 | 0 | $1.49 | 4.0 | typescript | ok |
| Test Results Aggregator | typescript-bun | sonnet46-200k-medium | 11.0min | 39 | 3 | $1.47 | 4.0 | typescript | ok |
| Environment Matrix Generator | bash | opus47-1m-high | 6.6min | 42 | 0 | $1.69 | 4.0 | bash | ok |
| Environment Matrix Generator | default | opus47-1m-high | 5.7min | 38 | 0 | $1.87 | 4.0 | python | ok |
| Environment Matrix Generator | default | opus47-1m-medium | 5.4min | 26 | 0 | $1.12 | 4.0 | python | ok |
| Environment Matrix Generator | default | opus47-200k-medium | 5.0min | 28 | 1 | $1.05 | 4.0 | python | ok |
| Environment Matrix Generator | powershell | opus47-1m-high | 7.0min | 41 | 0 | $2.04 | 4.0 | powershell | ok |
| Environment Matrix Generator | powershell | opus47-1m-medium | 14.0min | 59 | 0 | $3.01 | 4.0 | powershell | ok |
| Environment Matrix Generator | powershell | opus47-1m-xhigh | 13.5min | 54 | 0 | $3.93 | 4.0 | powershell | ok |
| Environment Matrix Generator | powershell | opus47-200k-medium | 6.1min | 30 | 0 | $1.42 | 4.0 | powershell | ok |
| Environment Matrix Generator | powershell | opus47-1m-xhigh | 10.2min | 43 | 1 | $3.08 | 4.0 | powershell | ok |
| Environment Matrix Generator | powershell | opus47-200k-medium | 6.0min | 27 | 1 | $1.51 | 4.0 | powershell | ok |
| Environment Matrix Generator | powershell | sonnet46-200k-medium | 8.0min | 25 | 1 | $1.00 | 4.0 | powershell | ok |
| Environment Matrix Generator | powershell | sonnet46-1m-medium | 8.1min | 36 | 7 | $1.04 | 4.0 | powershell | ok |
| Environment Matrix Generator | typescript-bun | opus47-200k-medium | 6.5min | 36 | 1 | $1.41 | 4.0 | typescript | ok |
| Artifact Cleanup Script | bash | opus47-1m-xhigh | 7.6min | 34 | 1 | $1.84 | 4.0 | bash | ok |
| Artifact Cleanup Script | bash | sonnet46-1m-medium | 11.6min | 45 | 6 | $1.78 | 4.0 | bash | ok |
| Artifact Cleanup Script | default | opus47-1m-medium | 3.2min | 19 | 0 | $0.85 | 4.0 | python | ok |
| Artifact Cleanup Script | default | sonnet46-200k-medium | 8.2min | 28 | 2 | $1.14 | 4.0 | python | ok |
| Artifact Cleanup Script | powershell | sonnet46-200k-medium | 8.4min | 31 | 2 | $1.25 | 4.0 | powershell | ok |
| Artifact Cleanup Script | powershell | opus47-1m-high | 11.7min | 54 | 1 | $3.33 | 4.0 | powershell | ok |
| Artifact Cleanup Script | powershell | opus47-1m-medium | 4.1min | 20 | 0 | $0.96 | 4.0 | powershell | ok |
| Artifact Cleanup Script | powershell | opus47-1m-xhigh | 12.0min | 51 | 1 | $3.21 | 4.0 | powershell | ok |
| Artifact Cleanup Script | powershell | opus47-200k-medium | 5.4min | 32 | 0 | $1.65 | 4.0 | powershell | ok |
| Artifact Cleanup Script | powershell | sonnet46-200k-medium | 6.0min | 50 | 1 | $0.94 | 4.0 | powershell | ok |
| Artifact Cleanup Script | typescript-bun | opus47-200k-medium | 4.4min | 22 | 0 | $0.92 | 4.0 | typescript | ok |
| Artifact Cleanup Script | typescript-bun | sonnet46-1m-medium | 7.9min | 49 | 4 | $1.37 | 4.0 | typescript | ok |
| Secret Rotation Validator | bash | sonnet46-200k-medium | 8.6min | 39 | 5 | $1.11 | 4.0 | bash | ok |
| Secret Rotation Validator | default | opus47-1m-xhigh | 9.1min | 45 | 0 | $2.54 | 4.0 | python | ok |
| Secret Rotation Validator | default | opus47-200k-medium | 5.5min | 25 | 0 | $1.27 | 4.0 | python | ok |
| Secret Rotation Validator | powershell | opus47-1m-medium | 22.5min | 31 | 0 | $1.27 | 4.0 | powershell | ok |
| Secret Rotation Validator | powershell | opus47-1m-medium | 17.8min | 38 | 2 | $1.70 | 4.0 | powershell | ok |
| Secret Rotation Validator | powershell | opus47-1m-xhigh | 9.9min | 38 | 0 | $2.58 | 4.0 | powershell | ok |
| Secret Rotation Validator | typescript-bun | opus47-1m-medium | 7.4min | 35 | 2 | $1.46 | 4.0 | typescript | ok |
| Secret Rotation Validator | typescript-bun | sonnet46-200k-medium | 8.9min | 30 | 1 | $1.07 | 4.0 | typescript | ok |
| Semantic Version Bumper | powershell | opus47-1m-xhigh | 8.0min | 49 | 0 | $2.90 | 3.5 | powershell | ok |
| Semantic Version Bumper | powershell | sonnet46-1m-medium | 11.9min | 40 | 1 | $1.69 | 3.5 | powershell | ok |
| Semantic Version Bumper | typescript-bun | opus47-200k-medium | 5.1min | 35 | 1 | $1.58 | 3.5 | typescript | ok |
| PR Label Assigner | bash | opus47-1m-xhigh | 16.7min | 61 | 2 | $3.14 | 3.5 | bash | ok |
| PR Label Assigner | powershell | opus47-1m-medium | 7.4min | 29 | 0 | $1.33 | 3.5 | powershell | ok |
| Dependency License Checker | default | sonnet46-1m-medium | 6.7min | 43 | 3 | $1.07 | 3.5 | python | ok |
| Dependency License Checker | powershell | opus47-1m-medium | 6.6min | 23 | 0 | $1.00 | 3.5 | powershell | ok |
| Dependency License Checker | powershell | opus47-200k-medium | 8.0min | 41 | 1 | $1.86 | 3.5 | powershell | ok |
| Dependency License Checker | powershell | sonnet46-200k-medium | 9.0min | 27 | 1 | $1.04 | 3.5 | powershell | ok |
| Dependency License Checker | typescript-bun | sonnet46-200k-medium | 6.8min | 35 | 2 | $0.93 | 3.5 | typescript | ok |
| Test Results Aggregator | bash | opus47-1m-high | 11.3min | 48 | 1 | $2.37 | 3.5 | bash | ok |
| Test Results Aggregator | bash | sonnet46-1m-medium | 10.7min | 39 | 5 | $1.42 | 3.5 | bash | ok |
| Test Results Aggregator | default | opus47-1m-medium | 6.9min | 31 | 0 | $1.28 | 3.5 | python | ok |
| Test Results Aggregator | default | sonnet46-1m-medium | 8.4min | 25 | 1 | $0.90 | 3.5 | python | ok |
| Test Results Aggregator | powershell | opus47-1m-xhigh | 17.3min | 74 | 0 | $4.47 | 3.5 | powershell | ok |
| Test Results Aggregator | powershell | opus47-200k-medium | 7.1min | 37 | 1 | $1.79 | 3.5 | powershell | ok |
| Test Results Aggregator | powershell | opus47-1m-medium | 9.4min | 37 | 0 | $1.76 | 3.5 | powershell | ok |
| Test Results Aggregator | powershell | opus47-200k-medium | 7.0min | 31 | 0 | $1.64 | 3.5 | powershell | ok |
| Test Results Aggregator | typescript-bun | opus47-200k-medium | 6.4min | 33 | 1 | $1.53 | 3.5 | typescript | ok |
| Test Results Aggregator | typescript-bun | sonnet46-1m-medium | 8.5min | 34 | 2 | $1.11 | 3.5 | typescript | ok |
| Environment Matrix Generator | bash | opus47-1m-xhigh | 8.3min | 51 | 2 | $2.49 | 3.5 | bash | ok |
| Environment Matrix Generator | bash | opus47-200k-medium | 2.9min | 23 | 0 | $1.05 | 3.5 | bash | ok |
| Environment Matrix Generator | bash | sonnet46-1m-medium | 29.1min | 58 | 6 | $3.25 | 3.5 | bash | ok |
| Environment Matrix Generator | powershell | haiku45-200k-na | 6.1min | 49 | 6 | $0.56 | 3.5 | powershell | ok |
| Environment Matrix Generator | powershell | opus47-1m-high | 7.4min | 30 | 0 | $2.13 | 3.5 | powershell | ok |
| Environment Matrix Generator | powershell | opus47-1m-medium | 4.6min | 29 | 2 | $1.30 | 3.5 | powershell | ok |
| Environment Matrix Generator | typescript-bun | opus47-1m-high | 6.7min | 42 | 0 | $2.13 | 3.5 | typescript | ok |
| Environment Matrix Generator | typescript-bun | sonnet46-200k-medium | 6.4min | 31 | 2 | $0.90 | 3.5 | typescript | ok |
| Environment Matrix Generator | typescript-bun | sonnet46-1m-medium | 12.2min | 42 | 2 | $1.34 | 3.5 | typescript | ok |
| Artifact Cleanup Script | bash | opus47-1m-high | 9.1min | 44 | 0 | $2.18 | 3.5 | bash | ok |
| Artifact Cleanup Script | powershell | opus47-1m-medium | 4.7min | 22 | 0 | $1.08 | 3.5 | powershell | ok |
| Artifact Cleanup Script | powershell | opus47-200k-medium | 4.0min | 23 | 0 | $1.09 | 3.5 | powershell | ok |
| Artifact Cleanup Script | powershell | sonnet46-1m-medium | 7.8min | 28 | 0 | $1.09 | 3.5 | powershell | ok |
| Artifact Cleanup Script | typescript-bun | opus47-1m-medium | 7.2min | 29 | 0 | $1.25 | 3.5 | typescript | ok |
| Secret Rotation Validator | bash | opus47-1m-xhigh | 9.4min | 35 | 0 | $2.40 | 3.5 | bash | ok |
| Secret Rotation Validator | bash | sonnet46-1m-medium | 10.0min | 41 | 6 | $1.10 | 3.5 | bash | ok |
| Secret Rotation Validator | default | sonnet46-200k-medium | 8.5min | 42 | 2 | $1.25 | 3.5 | python | ok |
| Secret Rotation Validator | powershell | opus47-200k-medium | 4.9min | 32 | 0 | $1.40 | 3.5 | powershell | ok |
| Secret Rotation Validator | powershell | sonnet46-1m-medium | 9.9min | 36 | 1 | $1.35 | 3.5 | powershell | ok |
| Secret Rotation Validator | powershell | opus47-200k-medium | 4.0min | 19 | 0 | $1.06 | 3.5 | powershell | ok |
| Secret Rotation Validator | typescript-bun | opus47-1m-high | 9.5min | 55 | 0 | $2.95 | 3.5 | typescript | ok |
| Secret Rotation Validator | typescript-bun | opus47-200k-medium | 6.9min | 36 | 0 | $1.92 | 3.5 | typescript | ok |
| Semantic Version Bumper | bash | sonnet46-200k-medium | 4.5min | 36 | 2 | $0.64 | 3.0 | bash | ok |
| Semantic Version Bumper | bash | sonnet46-1m-medium | 10.0min | 40 | 4 | $1.38 | 3.0 | bash | ok |
| PR Label Assigner | default | sonnet46-1m-medium | 9.6min | 44 | 7 | $1.38 | 3.0 | python | ok |
| PR Label Assigner | typescript-bun | sonnet46-1m-medium | 4.7min | 27 | 0 | $0.67 | 3.0 | typescript | ok |
| Dependency License Checker | bash | opus47-1m-medium | 5.5min | 30 | 1 | $1.55 | 3.0 | bash | ok |
| Dependency License Checker | bash | opus47-200k-medium | 7.5min | 26 | 1 | $0.92 | 3.0 | bash | ok |
| Dependency License Checker | powershell | sonnet46-200k-medium | 8.6min | 40 | 0 | $1.09 | 3.0 | powershell | ok |
| Test Results Aggregator | powershell | sonnet46-1m-medium | 8.3min | 24 | 1 | $0.99 | 3.0 | powershell | ok |
| Environment Matrix Generator | bash | opus47-1m-medium | 3.5min | 23 | 1 | $0.88 | 3.0 | bash | ok |
| Environment Matrix Generator | default | opus47-1m-xhigh | 6.8min | 34 | 2 | $2.01 | 3.0 | python | ok |
| Environment Matrix Generator | typescript-bun | haiku45-200k-na | 8.2min | 73 | 4 | $0.68 | 3.0 | typescript | ok |
| Environment Matrix Generator | typescript-bun | opus47-1m-medium | 7.4min | 29 | 0 | $1.07 | 3.0 | typescript | ok |
| Artifact Cleanup Script | bash | opus47-1m-medium | 3.1min | 24 | 3 | $0.92 | 3.0 | bash | ok |
| Artifact Cleanup Script | bash | opus47-200k-medium | 5.8min | 25 | 1 | $1.26 | 3.0 | bash | ok |
| Artifact Cleanup Script | powershell | sonnet46-1m-medium | 3.1min | 18 | 2 | $0.46 | 3.0 | powershell | ok |
| Artifact Cleanup Script | typescript-bun | sonnet46-200k-medium | 3.6min | 26 | 3 | $0.49 | 3.0 | typescript | ok |
| Secret Rotation Validator | bash | opus47-1m-high | 4.6min | 22 | 0 | $1.06 | 3.0 | bash | ok |
| Secret Rotation Validator | bash | opus47-1m-medium | 5.4min | 24 | 0 | $1.09 | 3.0 | bash | ok |
| Secret Rotation Validator | bash | opus47-200k-medium | 3.4min | 29 | 2 | $1.10 | 3.0 | bash | ok |
| Secret Rotation Validator | powershell | haiku45-200k-na | 11.4min | 40 | 3 | $0.39 | 3.0 | powershell | ok |
| Secret Rotation Validator | powershell | sonnet46-200k-medium | 8.0min | 19 | 0 | $0.96 | 3.0 | powershell | ok |
| Secret Rotation Validator | typescript-bun | sonnet46-1m-medium | 6.6min | 37 | 3 | $0.78 | 3.0 | typescript | ok |
| Semantic Version Bumper | bash | haiku45-200k-na | 6.3min | 48 | 1 | $0.45 | 2.5 | bash | ok |
| Semantic Version Bumper | bash | opus47-1m-medium | 4.2min | 30 | 2 | $1.07 | 2.5 | bash | ok |
| PR Label Assigner | default | sonnet46-200k-medium | 4.4min | 34 | 1 | $0.66 | 2.5 | python | ok |
| PR Label Assigner | powershell | haiku45-200k-na | 3.0min | 26 | 1 | $0.23 | 2.5 | powershell | ok |
| PR Label Assigner | powershell | sonnet46-1m-medium | 4.4min | 28 | 1 | $0.59 | 2.5 | powershell | ok |
| PR Label Assigner | typescript-bun | sonnet46-200k-medium | 6.9min | 41 | 3 | $0.87 | 2.5 | typescript | ok |
| Dependency License Checker | bash | haiku45-200k-na | 14.2min | 47 | 2 | $0.36 | 2.5 | bash | ok |
| Dependency License Checker | bash | opus47-1m-high | 4.0min | 30 | 0 | $1.35 | 2.5 | bash | ok |
| Dependency License Checker | bash | opus47-1m-xhigh | 39.8min | 38 | 2 | $2.19 | 2.5 | bash | ok |
| Dependency License Checker | default | haiku45-200k-na | 4.0min | 47 | 7 | $0.40 | 2.5 | python | ok |
| Dependency License Checker | powershell | haiku45-200k-na | 7.6min | 70 | 1 | $0.58 | 2.5 | powershell | ok |
| Dependency License Checker | powershell | haiku45-200k-na | 4.0min | 55 | 2 | $0.42 | 2.5 | powershell | ok |
| Test Results Aggregator | bash | haiku45-200k-na | 7.4min | 77 | 5 | $0.64 | 2.5 | bash | ok |
| Test Results Aggregator | default | haiku45-200k-na | 4.3min | 60 | 5 | $0.51 | 2.5 | python | ok |
| Environment Matrix Generator | powershell | sonnet46-200k-medium | 2.1min | 14 | 1 | $0.28 | 2.5 | powershell | ok |
| Environment Matrix Generator | powershell | sonnet46-1m-medium | 2.7min | 16 | 1 | $0.34 | 2.5 | powershell | ok |
| Artifact Cleanup Script | bash | haiku45-200k-na | 6.6min | 51 | 3 | $0.43 | 2.5 | bash | ok |
| Artifact Cleanup Script | bash | sonnet46-200k-medium | 4.4min | 31 | 2 | $0.61 | 2.5 | bash | ok |
| Artifact Cleanup Script | default | haiku45-200k-na | 4.8min | 45 | 4 | $0.46 | 2.5 | python | ok |
| Secret Rotation Validator | powershell | sonnet46-200k-medium | 3.4min | 22 | 1 | $0.47 | 2.5 | powershell | ok |
| Secret Rotation Validator | powershell | sonnet46-1m-medium | 7.8min | 33 | 1 | $0.94 | 2.5 | powershell | ok |
| Semantic Version Bumper | default | sonnet46-1m-medium | 4.6min | 33 | 3 | $0.67 | 2.0 | python | ok |
| Semantic Version Bumper | typescript-bun | haiku45-200k-na | 7.6min | 74 | 10 | $0.62 | 2.0 | typescript | ok |
| Semantic Version Bumper | typescript-bun | sonnet46-200k-medium | 7.4min | 33 | 4 | $0.68 | 2.0 | typescript | ok |
| PR Label Assigner | bash | haiku45-200k-na | 7.1min | 62 | 4 | $0.50 | 2.0 | bash | ok |
| PR Label Assigner | bash | opus47-200k-medium | 5.0min | 29 | 3 | $1.18 | 2.0 | bash | ok |
| PR Label Assigner | bash | sonnet46-1m-medium | 3.1min | 28 | 4 | $0.50 | 2.0 | bash | ok |
| PR Label Assigner | default | opus47-1m-medium | 3.1min | 23 | 0 | $0.83 | 2.0 | python | ok |
| PR Label Assigner | default | opus47-200k-medium | 3.2min | 21 | 0 | $0.70 | 2.0 | python | ok |
| PR Label Assigner | powershell | haiku45-200k-na | 5.2min | 44 | 1 | $0.38 | 2.0 | powershell | ok |
| PR Label Assigner | typescript-bun | haiku45-200k-na | 6.0min | 43 | 2 | $0.37 | 2.0 | typescript | ok |
| Dependency License Checker | bash | sonnet46-200k-medium | 6.9min | 34 | 2 | $0.97 | 2.0 | bash | ok |
| Dependency License Checker | typescript-bun | haiku45-200k-na | 4.3min | 48 | 1 | $0.39 | 2.0 | typescript | ok |
| Test Results Aggregator | typescript-bun | haiku45-200k-na | 7.8min | 67 | 9 | $0.60 | 2.0 | typescript | ok |
| Environment Matrix Generator | bash | haiku45-200k-na | 322.8min | 85 | 10 | $0.75 | 2.0 | bash | timeout |
| Environment Matrix Generator | default | haiku45-200k-na | 4.0min | 42 | 4 | $0.38 | 2.0 | python | ok |
| Environment Matrix Generator | default | sonnet46-200k-medium | 2.9min | 23 | 2 | $0.41 | 2.0 | python | ok |
| Environment Matrix Generator | default | sonnet46-1m-medium | 3.7min | 25 | 3 | $0.56 | 2.0 | python | ok |
| Artifact Cleanup Script | typescript-bun | haiku45-200k-na | 3.8min | 39 | 3 | $0.33 | 2.0 | typescript | ok |
| Secret Rotation Validator | bash | haiku45-200k-na | 7.7min | 56 | 3 | $0.49 | 2.0 | bash | ok |
| Secret Rotation Validator | default | opus47-1m-medium | 7.0min | 19 | 0 | $0.88 | 2.0 | python | ok |
| Secret Rotation Validator | powershell | haiku45-200k-na | 6.8min | 56 | 5 | $0.49 | 2.0 | powershell | ok |
| Secret Rotation Validator | typescript-bun | haiku45-200k-na | 3.8min | 55 | 6 | $0.42 | 2.0 | typescript | ok |
| PR Label Assigner | default | haiku45-200k-na | 2.9min | 27 | 3 | $0.25 | 1.5 | python | ok |
| PR Label Assigner | powershell | sonnet46-200k-medium | 2.9min | 19 | 0 | $0.38 | 1.5 | powershell | ok |
| Test Results Aggregator | powershell | haiku45-200k-na | 6.6min | 63 | 2 | $0.62 | 1.5 | powershell | ok |
| Artifact Cleanup Script | powershell | haiku45-200k-na | 3.2min | 29 | 2 | $0.28 | 1.5 | powershell | ok |
| Secret Rotation Validator | default | haiku45-200k-na | 4.2min | 38 | 3 | $0.34 | 1.5 | python | ok |
| Semantic Version Bumper | default | haiku45-200k-na | 59.1min | 97 | 12 | $0.84 | — | javascript | ok |
| Semantic Version Bumper | default | opus47-1m-high | 7.1min | 31 | 0 | $1.85 | — | javascript | ok |
| Semantic Version Bumper | default | opus47-200k-medium | 4.2min | 31 | 1 | $1.21 | — | javascript | ok |
| Semantic Version Bumper | powershell | haiku45-200k-na | 6.3min | 65 | 4 | $0.57 | — | powershell | ok |
| Semantic Version Bumper | powershell | haiku45-200k-na | 15.1min | 92 | 7 | $0.93 | — | powershell | ok |
| Test Results Aggregator | powershell | haiku45-200k-na | 7.1min | 63 | 5 | $0.63 | — | powershell | ok |
| Environment Matrix Generator | bash | sonnet46-200k-medium | 4.2min | 7 | 1 | $0.35 | — | bash | cli_error |
| Environment Matrix Generator | powershell | haiku45-200k-na | 4.6min | 43 | 3 | $0.39 | — | powershell | ok |
| Artifact Cleanup Script | powershell | haiku45-200k-na | 7.8min | 31 | 2 | $0.28 | — | powershell | ok |

</details>

## Notes

### Tiers

- **Duration bands:** **A+** ≤1.10×, **A** ≤1.21×, **A-** ≤1.33×, **B+** ≤1.46×, **B** ≤1.61×, **B-** ≤1.77×, **C+** ≤1.94×, **C** ≤2.13×, **C-** ≤2.35×, **D+** ≤2.58×, **D** ≤2.83×, **D-** ≤3.12×, **F** >3.12×
- **Cost bands:** **A+** ≤1.19×, **A** ≤1.41×, **A-** ≤1.68×, **B+** ≤1.99×, **B** ≤2.36×, **B-** ≤2.81×, **C+** ≤3.33×, **C** ≤3.96×, **C-** ≤4.70×, **D+** ≤5.59×, **D** ≤6.63×, **D-** ≤7.88×, **F** >7.88×

*Tests/Workflow Craft bands are absolute Overall score bands:* **A+** ≥4.7, **A** ≥4.4, **A-** ≥4.1, **B+** ≥3.8, **B** ≥3.5, **B-** ≥3.2, **C+** ≥2.9, **C** ≥2.6, **C-** ≥2.3, **D+** ≥2.0, **D** ≥1.7, **D-** ≥1.4, **F** <1.4, `—` = no data.*

### CLI Version Legend

| Variant label | CLI version | Tasks | Languages |
|---------------|-------------|-------|-----------|
| haiku45-200k-na | 2.1.114 | All | All |
| opus47-1m-high | 2.1.114 | All | All |
| opus47-1m-medium | 2.1.112 | All | All |
| opus47-1m-xhigh | 2.1.112 | All | All |
| opus47-200k-medium | 2.1.114 | All | All |
| sonnet46-1m-medium | 2.1.114 | All | All |
| sonnet46-200k-medium | 2.1.114 | All | All |

### Judge Consistency Summary

**🟢 The panel is doing its job:** The judges agree strongly on which model produces better code (Spearman +0.90 on Workflow Craft, +0.70 on Tests), both put Opus 4.7-1m first and Haiku 4.5 last with no near-top reversals, and Haiku actually scores its own model family harsher than the baseline gap — the opposite of self-preference. The only clean divergence is language ordering (ρ = +0.00 on both axes), which reads as aesthetic calibration, not a ranking failure.

- 👀 **Where to look closer:** The widest disagreements (a judge scoring 1 vs 5, a 4-point gap on a 1–5 scale) cluster in **15-test-results-aggregator / default / opus47-1m-medium** and its sonnet46-1m-medium sibling, plus **11-semantic-version-bumper / powershell / opus47-1m-medium** and **17-artifact-cleanup-script / bash / opus47-1m-medium** — Gemini gives 5s where Haiku gives 1s. Worth checking whether Haiku is floor-bound on style issues Gemini shrugs off.
- 🤓 **Surprise finding:** Haiku's self-judgment rows sit ~1.6 points BELOW the panel's baseline delta, meaning the intra-family judge is anti-self-preferring — not the failure mode this check was designed to catch.
- ℹ️ **Recommended next step:** Hand-review the eight Workflow Craft rows with 4-point gaps to decide whether Haiku's 1s are a floor artifact or real signal about failure modes Gemini misses.

#### Provenance

- **Model:** `claude-opus-4-7[1m]` at effort `xhigh` via the Claude CLI.
- **Inputs:** the [`judge-consistency-data.md`](judge-consistency-data.md) tables plus benchmark context (rubrics, task list, experiment setup).
- **Script:** [`conclusions_report.py`](../../conclusions_report.py) — regenerate with `python3 generate_results.py <run_dir>`.
- **Instruction:** [`JUDGE_CONSISTENCY_SUMMARY_SYSTEM_PROMPT`](../../judge_consistency_report.py) in that script.
- **Usage:** 5 input + 2013 output tokens, $0.3499.

*Full breakdown with per-model / per-language / per-language×model ranking tables and disagreement hotspots in [judge-consistency-data.md](judge-consistency-data.md).*

---
*Generated by generate_results.py — benchmark instructions v4*