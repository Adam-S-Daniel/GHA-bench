# Benchmark Results: Language Comparison

**Last updated:** 2026-07-02 09:52:36 AM ET — 144/144 runs completed, 0 remaining; total cost $436.67; total agent time 5098.1 min.
**Claude Code versions used:** [v2.1.81](claude-code-2.1.81.md) (139 runs). Each link goes to a per-version snapshot of the system prompt, default-tool descriptions, and the chronological Anthropic changelog up to that version. Regenerate with `python3 version_docs.py`.

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
  - [LLM-as-Judge Scores](#llm-as-judge-scores)
  - [Correlation: Structural Metrics vs Tests Quality](#correlation-structural-metrics-vs-tests-quality)
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
| default | sonnet46-200k-medium | A+ (16.7min) | A+ ($1.23) | A- (4.1) | — |
| powershell-strict | sonnet46-200k-medium | A- (21.9min) | A ($1.55) | B+ (3.8) | — |
| powershell | sonnet46-200k-medium | C+ (31.1min) | A- ($1.63) | B+ (4.0) | — |
| default | opus46-200k-medium | C+ (30.8min) | D+ ($3.99) | A (4.4) | — |
| powershell | opus46-200k-medium | C+ (30.1min) | C- ($3.65) | A- (4.2) | — |
| csharp-script | sonnet46-200k-medium | C (33.1min) | C+ ($2.77) | B (3.5) | — |
| csharp-script | opus46-200k-medium | D+ (40.2min) | D- ($5.59) | A- (4.1) | — |
| powershell-strict | opus46-200k-medium | D- (52.8min) | D ($4.92) | B+ (4.1) | — |


<details>
<summary>Sorted by Duration tier (best-first), then avg of Cost/Tests/Workflow Craft tiers</summary>

| Language | Model | Duration | Cost | Tests Quality | Workflow Craft |
|----------|-------|----------|------|-----------|-------------|
| default | sonnet46-200k-medium | A+ (16.7min) | A+ ($1.23) | A- (4.1) | — |
| powershell-strict | sonnet46-200k-medium | A- (21.9min) | A ($1.55) | B+ (3.8) | — |
| powershell | sonnet46-200k-medium | C+ (31.1min) | A- ($1.63) | B+ (4.0) | — |
| default | opus46-200k-medium | C+ (30.8min) | D+ ($3.99) | A (4.4) | — |
| powershell | opus46-200k-medium | C+ (30.1min) | C- ($3.65) | A- (4.2) | — |
| csharp-script | sonnet46-200k-medium | C (33.1min) | C+ ($2.77) | B (3.5) | — |
| csharp-script | opus46-200k-medium | D+ (40.2min) | D- ($5.59) | A- (4.1) | — |
| powershell-strict | opus46-200k-medium | D- (52.8min) | D ($4.92) | B+ (4.1) | — |

</details>

<details>
<summary>Sorted by Cost tier (best-first), then avg of Duration/Tests/Workflow Craft tiers</summary>

| Language | Model | Duration | Cost | Tests Quality | Workflow Craft |
|----------|-------|----------|------|-----------|-------------|
| default | sonnet46-200k-medium | A+ (16.7min) | A+ ($1.23) | A- (4.1) | — |
| powershell-strict | sonnet46-200k-medium | A- (21.9min) | A ($1.55) | B+ (3.8) | — |
| powershell | sonnet46-200k-medium | C+ (31.1min) | A- ($1.63) | B+ (4.0) | — |
| csharp-script | sonnet46-200k-medium | C (33.1min) | C+ ($2.77) | B (3.5) | — |
| powershell | opus46-200k-medium | C+ (30.1min) | C- ($3.65) | A- (4.2) | — |
| default | opus46-200k-medium | C+ (30.8min) | D+ ($3.99) | A (4.4) | — |
| powershell-strict | opus46-200k-medium | D- (52.8min) | D ($4.92) | B+ (4.1) | — |
| csharp-script | opus46-200k-medium | D+ (40.2min) | D- ($5.59) | A- (4.1) | — |

</details>

<details>
<summary>Sorted by Tests Quality tier (best-first; no-data last), then avg of other tiers</summary>

| Language | Model | Duration | Cost | Tests Quality | Workflow Craft |
|----------|-------|----------|------|-----------|-------------|
| default | opus46-200k-medium | C+ (30.8min) | D+ ($3.99) | A (4.4) | — |
| default | sonnet46-200k-medium | A+ (16.7min) | A+ ($1.23) | A- (4.1) | — |
| powershell | opus46-200k-medium | C+ (30.1min) | C- ($3.65) | A- (4.2) | — |
| csharp-script | opus46-200k-medium | D+ (40.2min) | D- ($5.59) | A- (4.1) | — |
| powershell-strict | sonnet46-200k-medium | A- (21.9min) | A ($1.55) | B+ (3.8) | — |
| powershell | sonnet46-200k-medium | C+ (31.1min) | A- ($1.63) | B+ (4.0) | — |
| powershell-strict | opus46-200k-medium | D- (52.8min) | D ($4.92) | B+ (4.1) | — |
| csharp-script | sonnet46-200k-medium | C (33.1min) | C+ ($2.77) | B (3.5) | — |

</details>

<details>
<summary>Sorted by Workflow Craft tier (best-first; no-data last), then avg of other tiers</summary>

| Language | Model | Duration | Cost | Tests Quality | Workflow Craft |
|----------|-------|----------|------|-----------|-------------|
| default | sonnet46-200k-medium | A+ (16.7min) | A+ ($1.23) | A- (4.1) | — |
| powershell-strict | sonnet46-200k-medium | A- (21.9min) | A ($1.55) | B+ (3.8) | — |
| powershell | sonnet46-200k-medium | C+ (31.1min) | A- ($1.63) | B+ (4.0) | — |
| default | opus46-200k-medium | C+ (30.8min) | D+ ($3.99) | A (4.4) | — |
| powershell | opus46-200k-medium | C+ (30.1min) | C- ($3.65) | A- (4.2) | — |
| csharp-script | sonnet46-200k-medium | C (33.1min) | C+ ($2.77) | B (3.5) | — |
| csharp-script | opus46-200k-medium | D+ (40.2min) | D- ($5.59) | A- (4.1) | — |
| powershell-strict | opus46-200k-medium | D- (52.8min) | D ($4.92) | B+ (4.1) | — |

</details>

## Failed / Timed-Out Runs

| Task | Language | Model | Duration | Reason | Lines | actionlint | act-result.txt |
|------|------|-------|----------|--------|-------|------------|----------------|
| CSV Report Generator | csharp-script | opus46-200k-medium | 271.2min | exit_code=-1 | 132 | n/a | no |
| REST API Client | powershell | opus46-200k-medium | 257.5min | exit_code=-1 | 376 | n/a | no |
| Config File Migrator | csharp-script | opus46-200k-medium | 54.2min | exit_code=-1 | 1701 | n/a | no |
| Database Seed Script | csharp-script | sonnet46-200k-medium | 28.1min | exit_code=-1 | 1850 | n/a | no |
| Environment Matrix Generator | powershell-strict | sonnet46-200k-medium | 30.0min | exit_code=-1 | 340 | n/a | no |

*5 run(s) excluded from averages below.*

## Comparison by Language/Model/Effort
*(averages exclude failed/timed-out runs)*
*See [Notes](#notes) for scoring rubric and CLI version legend.*

| Language | Model | Runs | Avg Duration | Avg Duration Net of Traps | Avg Errors | Avg Turns | Avg Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| csharp-script | opus46-200k-medium | 16 | 40.2min | 3.8min | 154.0 | 163 | $5.59 | $89.38 | 4.1 | — |
| csharp-script | sonnet46-200k-medium | 17 | 33.1min | 21.3min | 59.9 | 86 | $2.77 | $47.12 | 3.5 | — |
| default | opus46-200k-medium | 18 | 30.8min | -18.0min | 149.4 | 148 | $3.99 | $71.84 | 4.4 | — |
| default | sonnet46-200k-medium | 18 | 16.7min | 10.0min | 35.5 | 51 | $1.23 | $22.08 | 4.1 | — |
| powershell | opus46-200k-medium | 17 | 30.1min | 0.9min | 101.4 | 112 | $3.65 | $61.98 | 4.2 | — |
| powershell | sonnet46-200k-medium | 18 | 31.1min | 22.5min | 46.9 | 63 | $1.63 | $29.38 | 4.0 | — |
| powershell-strict | opus46-200k-medium | 18 | 52.8min | 14.3min | 134.1 | 145 | $4.92 | $88.48 | 4.1 | — |
| powershell-strict | sonnet46-200k-medium | 17 | 21.9min | 16.7min | 32.5 | 48 | $1.55 | $26.42 | 3.8 | — |


<details>
<summary>Sorted by avg cost (cheapest first)</summary>

| Language | Model | Runs | Avg Duration | Avg Duration Net of Traps | Avg Errors | Avg Turns | Avg Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| default | sonnet46-200k-medium | 18 | 16.7min | 10.0min | 35.5 | 51 | $1.23 | $22.08 | 4.1 | — |
| powershell-strict | sonnet46-200k-medium | 17 | 21.9min | 16.7min | 32.5 | 48 | $1.55 | $26.42 | 3.8 | — |
| powershell | sonnet46-200k-medium | 18 | 31.1min | 22.5min | 46.9 | 63 | $1.63 | $29.38 | 4.0 | — |
| csharp-script | sonnet46-200k-medium | 17 | 33.1min | 21.3min | 59.9 | 86 | $2.77 | $47.12 | 3.5 | — |
| powershell | opus46-200k-medium | 17 | 30.1min | 0.9min | 101.4 | 112 | $3.65 | $61.98 | 4.2 | — |
| default | opus46-200k-medium | 18 | 30.8min | -18.0min | 149.4 | 148 | $3.99 | $71.84 | 4.4 | — |
| powershell-strict | opus46-200k-medium | 18 | 52.8min | 14.3min | 134.1 | 145 | $4.92 | $88.48 | 4.1 | — |
| csharp-script | opus46-200k-medium | 16 | 40.2min | 3.8min | 154.0 | 163 | $5.59 | $89.38 | 4.1 | — |

</details>

<details>
<summary>Sorted by avg duration (fastest first)</summary>

| Language | Model | Runs | Avg Duration | Avg Duration Net of Traps | Avg Errors | Avg Turns | Avg Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| default | sonnet46-200k-medium | 18 | 16.7min | 10.0min | 35.5 | 51 | $1.23 | $22.08 | 4.1 | — |
| powershell-strict | sonnet46-200k-medium | 17 | 21.9min | 16.7min | 32.5 | 48 | $1.55 | $26.42 | 3.8 | — |
| powershell | opus46-200k-medium | 17 | 30.1min | 0.9min | 101.4 | 112 | $3.65 | $61.98 | 4.2 | — |
| default | opus46-200k-medium | 18 | 30.8min | -18.0min | 149.4 | 148 | $3.99 | $71.84 | 4.4 | — |
| powershell | sonnet46-200k-medium | 18 | 31.1min | 22.5min | 46.9 | 63 | $1.63 | $29.38 | 4.0 | — |
| csharp-script | sonnet46-200k-medium | 17 | 33.1min | 21.3min | 59.9 | 86 | $2.77 | $47.12 | 3.5 | — |
| csharp-script | opus46-200k-medium | 16 | 40.2min | 3.8min | 154.0 | 163 | $5.59 | $89.38 | 4.1 | — |
| powershell-strict | opus46-200k-medium | 18 | 52.8min | 14.3min | 134.1 | 145 | $4.92 | $88.48 | 4.1 | — |

</details>

<details>
<summary>Sorted by avg duration net of traps (fastest first)</summary>

| Language | Model | Runs | Avg Duration | Avg Duration Net of Traps | Avg Errors | Avg Turns | Avg Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| default | opus46-200k-medium | 18 | 30.8min | -18.0min | 149.4 | 148 | $3.99 | $71.84 | 4.4 | — |
| powershell | opus46-200k-medium | 17 | 30.1min | 0.9min | 101.4 | 112 | $3.65 | $61.98 | 4.2 | — |
| csharp-script | opus46-200k-medium | 16 | 40.2min | 3.8min | 154.0 | 163 | $5.59 | $89.38 | 4.1 | — |
| default | sonnet46-200k-medium | 18 | 16.7min | 10.0min | 35.5 | 51 | $1.23 | $22.08 | 4.1 | — |
| powershell-strict | opus46-200k-medium | 18 | 52.8min | 14.3min | 134.1 | 145 | $4.92 | $88.48 | 4.1 | — |
| powershell-strict | sonnet46-200k-medium | 17 | 21.9min | 16.7min | 32.5 | 48 | $1.55 | $26.42 | 3.8 | — |
| csharp-script | sonnet46-200k-medium | 17 | 33.1min | 21.3min | 59.9 | 86 | $2.77 | $47.12 | 3.5 | — |
| powershell | sonnet46-200k-medium | 18 | 31.1min | 22.5min | 46.9 | 63 | $1.63 | $29.38 | 4.0 | — |

</details>

<details>
<summary>Sorted by avg errors (fewest first)</summary>

| Language | Model | Runs | Avg Duration | Avg Duration Net of Traps | Avg Errors | Avg Turns | Avg Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| powershell-strict | sonnet46-200k-medium | 17 | 21.9min | 16.7min | 32.5 | 48 | $1.55 | $26.42 | 3.8 | — |
| default | sonnet46-200k-medium | 18 | 16.7min | 10.0min | 35.5 | 51 | $1.23 | $22.08 | 4.1 | — |
| powershell | sonnet46-200k-medium | 18 | 31.1min | 22.5min | 46.9 | 63 | $1.63 | $29.38 | 4.0 | — |
| csharp-script | sonnet46-200k-medium | 17 | 33.1min | 21.3min | 59.9 | 86 | $2.77 | $47.12 | 3.5 | — |
| powershell | opus46-200k-medium | 17 | 30.1min | 0.9min | 101.4 | 112 | $3.65 | $61.98 | 4.2 | — |
| powershell-strict | opus46-200k-medium | 18 | 52.8min | 14.3min | 134.1 | 145 | $4.92 | $88.48 | 4.1 | — |
| default | opus46-200k-medium | 18 | 30.8min | -18.0min | 149.4 | 148 | $3.99 | $71.84 | 4.4 | — |
| csharp-script | opus46-200k-medium | 16 | 40.2min | 3.8min | 154.0 | 163 | $5.59 | $89.38 | 4.1 | — |

</details>

<details>
<summary>Sorted by avg turns (fewest first)</summary>

| Language | Model | Runs | Avg Duration | Avg Duration Net of Traps | Avg Errors | Avg Turns | Avg Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| powershell-strict | sonnet46-200k-medium | 17 | 21.9min | 16.7min | 32.5 | 48 | $1.55 | $26.42 | 3.8 | — |
| default | sonnet46-200k-medium | 18 | 16.7min | 10.0min | 35.5 | 51 | $1.23 | $22.08 | 4.1 | — |
| powershell | sonnet46-200k-medium | 18 | 31.1min | 22.5min | 46.9 | 63 | $1.63 | $29.38 | 4.0 | — |
| csharp-script | sonnet46-200k-medium | 17 | 33.1min | 21.3min | 59.9 | 86 | $2.77 | $47.12 | 3.5 | — |
| powershell | opus46-200k-medium | 17 | 30.1min | 0.9min | 101.4 | 112 | $3.65 | $61.98 | 4.2 | — |
| powershell-strict | opus46-200k-medium | 18 | 52.8min | 14.3min | 134.1 | 145 | $4.92 | $88.48 | 4.1 | — |
| default | opus46-200k-medium | 18 | 30.8min | -18.0min | 149.4 | 148 | $3.99 | $71.84 | 4.4 | — |
| csharp-script | opus46-200k-medium | 16 | 40.2min | 3.8min | 154.0 | 163 | $5.59 | $89.38 | 4.1 | — |

</details>

<details>
<summary>Sorted by LLM-as-judge score (best first)</summary>

| Language | Model | Runs | Avg Duration | Avg Duration Net of Traps | Avg Errors | Avg Turns | Avg Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| default | opus46-200k-medium | 18 | 30.8min | -18.0min | 149.4 | 148 | $3.99 | $71.84 | 4.4 | — |
| powershell | opus46-200k-medium | 17 | 30.1min | 0.9min | 101.4 | 112 | $3.65 | $61.98 | 4.2 | — |
| csharp-script | opus46-200k-medium | 16 | 40.2min | 3.8min | 154.0 | 163 | $5.59 | $89.38 | 4.1 | — |
| default | sonnet46-200k-medium | 18 | 16.7min | 10.0min | 35.5 | 51 | $1.23 | $22.08 | 4.1 | — |
| powershell-strict | opus46-200k-medium | 18 | 52.8min | 14.3min | 134.1 | 145 | $4.92 | $88.48 | 4.1 | — |
| powershell | sonnet46-200k-medium | 18 | 31.1min | 22.5min | 46.9 | 63 | $1.63 | $29.38 | 4.0 | — |
| powershell-strict | sonnet46-200k-medium | 17 | 21.9min | 16.7min | 32.5 | 48 | $1.55 | $26.42 | 3.8 | — |
| csharp-script | sonnet46-200k-medium | 17 | 33.1min | 21.3min | 59.9 | 86 | $2.77 | $47.12 | 3.5 | — |

</details>

<details>
<summary>Sorted by deliverable-quality score (best first)</summary>

| Language | Model | Runs | Avg Duration | Avg Duration Net of Traps | Avg Errors | Avg Turns | Avg Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| csharp-script | opus46-200k-medium | 16 | 40.2min | 3.8min | 154.0 | 163 | $5.59 | $89.38 | 4.1 | — |
| csharp-script | sonnet46-200k-medium | 17 | 33.1min | 21.3min | 59.9 | 86 | $2.77 | $47.12 | 3.5 | — |
| default | opus46-200k-medium | 18 | 30.8min | -18.0min | 149.4 | 148 | $3.99 | $71.84 | 4.4 | — |
| default | sonnet46-200k-medium | 18 | 16.7min | 10.0min | 35.5 | 51 | $1.23 | $22.08 | 4.1 | — |
| powershell | opus46-200k-medium | 17 | 30.1min | 0.9min | 101.4 | 112 | $3.65 | $61.98 | 4.2 | — |
| powershell | sonnet46-200k-medium | 18 | 31.1min | 22.5min | 46.9 | 63 | $1.63 | $29.38 | 4.0 | — |
| powershell-strict | opus46-200k-medium | 18 | 52.8min | 14.3min | 134.1 | 145 | $4.92 | $88.48 | 4.1 | — |
| powershell-strict | sonnet46-200k-medium | 17 | 21.9min | 16.7min | 32.5 | 48 | $1.55 | $26.42 | 3.8 | — |

</details>

## Savings Analysis

### Hook Savings by Language/Model/Effort

Each hook-caught error avoids one test run that would otherwise have been needed to discover it.
Every hook fire (hit or miss) costs execution time for the syntax/type checker.

*`% of Test Time Saved` = `net / (net + test_time) × 100` — the share of total (would-have-been + actually-spent) test time that hooks eliminated. Bounded in (-∞, 100%) without an artificial cap; near 100% means hooks substituted for almost all of the hypothetical test work.*

| Language | Model | Fires | Caught | Rate | Gross Saved | % of Time | Overhead | % of Time | Net Saved | % of Time | Test Run Time | % of Test Time Saved |
|------|-------|-------|--------|------|------------|-----------|----------|-----------|-----------|-----------|---------------|----------------------|


<details>
<summary>Sorted by net saved (most first)</summary>

| Language | Model | Fires | Caught | Rate | Gross Saved | % of Time | Overhead | % of Time | Net Saved | % of Time | Test Run Time | % of Test Time Saved |
|------|-------|-------|--------|------|------------|-----------|----------|-----------|-----------|-----------|---------------|----------------------|

</details>

<details>
<summary>Sorted by net % of test time saved (most first)</summary>

| Language | Model | Fires | Caught | Rate | Gross Saved | % of Time | Overhead | % of Time | Net Saved | % of Time | Test Run Time | % of Test Time Saved |
|------|-------|-------|--------|------|------------|-----------|----------|-----------|-----------|-----------|---------------|----------------------|

</details>

<details>
<summary>Sorted by catch rate (highest first)</summary>

| Language | Model | Fires | Caught | Rate | Gross Saved | % of Time | Overhead | % of Time | Net Saved | % of Time | Test Run Time | % of Test Time Saved |
|------|-------|-------|--------|------|------------|-----------|----------|-----------|-----------|-----------|---------------|----------------------|

</details>

### Trap Analysis by Language/Model/Effort/Category

| Trap | Language | Model | Fell In | Time Lost | % of Time | $ Lost | % of $ |
|------|------|-------|---------|-----------|-----------|--------|--------|
| permission-denial-loops | csharp-script | opus46-200k-medium-cli2.1.81 | 16 | 349.2min | 6.8% | $87.42 | 20.02% |
| permission-denial-loops | csharp-script | sonnet46-200k-medium-cli2.1.81 | 17 | 138.8min | 2.7% | $21.10 | 4.83% |
| permission-denial-loops | default | opus46-200k-medium-cli2.1.81 | 18 | 439.2min | 8.6% | $99.42 | 22.77% |
| permission-denial-loops | default | sonnet46-200k-medium-cli2.1.81 | 18 | 93.7min | 1.8% | $12.17 | 2.79% |
| permission-denial-loops | powershell | opus46-200k-medium-cli2.1.81 | 17 | 280.0min | 5.5% | $65.92 | 15.10% |
| permission-denial-loops | powershell | sonnet46-200k-medium-cli2.1.81 | 18 | 126.0min | 2.5% | $19.18 | 4.39% |
| permission-denial-loops | powershell-strict | opus46-200k-medium-cli2.1.81 | 18 | 391.5min | 7.7% | $101.79 | 23.31% |
| permission-denial-loops | powershell-strict | sonnet46-200k-medium-cli2.1.81 | 17 | 81.3min | 1.6% | $9.45 | 2.16% |
| repeated-test-reruns | csharp-script | opus46-200k-medium-cli2.1.81 | 24 | 55.7min | 1.1% | $16.57 | 3.79% |
| repeated-test-reruns | csharp-script | sonnet46-200k-medium-cli2.1.81 | 15 | 18.0min | 0.4% | $2.60 | 0.59% |
| repeated-test-reruns | default | opus46-200k-medium-cli2.1.81 | 50 | 439.7min | 8.6% | $107.75 | 24.68% |
| repeated-test-reruns | default | sonnet46-200k-medium-cli2.1.81 | 23 | 27.7min | 0.5% | $3.54 | 0.81% |
| repeated-test-reruns | powershell | opus46-200k-medium-cli2.1.81 | 48 | 215.3min | 4.2% | $50.76 | 11.62% |
| repeated-test-reruns | powershell | sonnet46-200k-medium-cli2.1.81 | 12 | 21.3min | 0.4% | $3.68 | 0.84% |
| repeated-test-reruns | powershell-strict | opus46-200k-medium-cli2.1.81 | 49 | 302.7min | 5.9% | $73.02 | 16.72% |
| repeated-test-reruns | powershell-strict | sonnet46-200k-medium-cli2.1.81 | 6 | 7.0min | 0.1% | $0.64 | 0.15% |
| dotnet-install-loop | csharp-script | opus46-200k-medium-cli2.1.81 | 16 | 178.6min | 3.5% | $40.93 | 9.37% |
| dotnet-install-loop | csharp-script | sonnet46-200k-medium-cli2.1.81 | 13 | 44.2min | 0.9% | $7.17 | 1.64% |
| pwsh-invoked-from-bash | powershell | sonnet46-200k-medium-cli2.1.81 | 1 | 7.7min | 0.2% | $1.46 | 0.33% |
| fixture-rework | default | opus46-200k-medium-cli2.1.81 | 1 | 0.5min | 0.0% | $0.03 | 0.01% |
| fixture-rework | default | sonnet46-200k-medium-cli2.1.81 | 1 | 0.8min | 0.0% | $0.15 | 0.03% |
| fixture-rework | powershell | sonnet46-200k-medium-cli2.1.81 | 1 | 0.5min | 0.0% | $0.08 | 0.02% |


<details>
<summary>Sorted by time lost (least first)</summary>

| Trap | Language | Model | Fell In | Time Lost | % of Time | $ Lost | % of $ |
|------|------|-------|---------|-----------|-----------|--------|--------|
| fixture-rework | default | opus46-200k-medium-cli2.1.81 | 1 | 0.5min | 0.0% | $0.03 | 0.01% |
| fixture-rework | powershell | sonnet46-200k-medium-cli2.1.81 | 1 | 0.5min | 0.0% | $0.08 | 0.02% |
| fixture-rework | default | sonnet46-200k-medium-cli2.1.81 | 1 | 0.8min | 0.0% | $0.15 | 0.03% |
| repeated-test-reruns | powershell-strict | sonnet46-200k-medium-cli2.1.81 | 6 | 7.0min | 0.1% | $0.64 | 0.15% |
| pwsh-invoked-from-bash | powershell | sonnet46-200k-medium-cli2.1.81 | 1 | 7.7min | 0.2% | $1.46 | 0.33% |
| repeated-test-reruns | csharp-script | sonnet46-200k-medium-cli2.1.81 | 15 | 18.0min | 0.4% | $2.60 | 0.59% |
| repeated-test-reruns | powershell | sonnet46-200k-medium-cli2.1.81 | 12 | 21.3min | 0.4% | $3.68 | 0.84% |
| repeated-test-reruns | default | sonnet46-200k-medium-cli2.1.81 | 23 | 27.7min | 0.5% | $3.54 | 0.81% |
| dotnet-install-loop | csharp-script | sonnet46-200k-medium-cli2.1.81 | 13 | 44.2min | 0.9% | $7.17 | 1.64% |
| repeated-test-reruns | csharp-script | opus46-200k-medium-cli2.1.81 | 24 | 55.7min | 1.1% | $16.57 | 3.79% |
| permission-denial-loops | powershell-strict | sonnet46-200k-medium-cli2.1.81 | 17 | 81.3min | 1.6% | $9.45 | 2.16% |
| permission-denial-loops | default | sonnet46-200k-medium-cli2.1.81 | 18 | 93.7min | 1.8% | $12.17 | 2.79% |
| permission-denial-loops | powershell | sonnet46-200k-medium-cli2.1.81 | 18 | 126.0min | 2.5% | $19.18 | 4.39% |
| permission-denial-loops | csharp-script | sonnet46-200k-medium-cli2.1.81 | 17 | 138.8min | 2.7% | $21.10 | 4.83% |
| dotnet-install-loop | csharp-script | opus46-200k-medium-cli2.1.81 | 16 | 178.6min | 3.5% | $40.93 | 9.37% |
| repeated-test-reruns | powershell | opus46-200k-medium-cli2.1.81 | 48 | 215.3min | 4.2% | $50.76 | 11.62% |
| permission-denial-loops | powershell | opus46-200k-medium-cli2.1.81 | 17 | 280.0min | 5.5% | $65.92 | 15.10% |
| repeated-test-reruns | powershell-strict | opus46-200k-medium-cli2.1.81 | 49 | 302.7min | 5.9% | $73.02 | 16.72% |
| permission-denial-loops | csharp-script | opus46-200k-medium-cli2.1.81 | 16 | 349.2min | 6.8% | $87.42 | 20.02% |
| permission-denial-loops | powershell-strict | opus46-200k-medium-cli2.1.81 | 18 | 391.5min | 7.7% | $101.79 | 23.31% |
| permission-denial-loops | default | opus46-200k-medium-cli2.1.81 | 18 | 439.2min | 8.6% | $99.42 | 22.77% |
| repeated-test-reruns | default | opus46-200k-medium-cli2.1.81 | 50 | 439.7min | 8.6% | $107.75 | 24.68% |

</details>

<details>
<summary>Sorted by $ lost (least first)</summary>

| Trap | Language | Model | Fell In | Time Lost | % of Time | $ Lost | % of $ |
|------|------|-------|---------|-----------|-----------|--------|--------|
| fixture-rework | default | opus46-200k-medium-cli2.1.81 | 1 | 0.5min | 0.0% | $0.03 | 0.01% |
| fixture-rework | powershell | sonnet46-200k-medium-cli2.1.81 | 1 | 0.5min | 0.0% | $0.08 | 0.02% |
| fixture-rework | default | sonnet46-200k-medium-cli2.1.81 | 1 | 0.8min | 0.0% | $0.15 | 0.03% |
| repeated-test-reruns | powershell-strict | sonnet46-200k-medium-cli2.1.81 | 6 | 7.0min | 0.1% | $0.64 | 0.15% |
| pwsh-invoked-from-bash | powershell | sonnet46-200k-medium-cli2.1.81 | 1 | 7.7min | 0.2% | $1.46 | 0.33% |
| repeated-test-reruns | csharp-script | sonnet46-200k-medium-cli2.1.81 | 15 | 18.0min | 0.4% | $2.60 | 0.59% |
| repeated-test-reruns | default | sonnet46-200k-medium-cli2.1.81 | 23 | 27.7min | 0.5% | $3.54 | 0.81% |
| repeated-test-reruns | powershell | sonnet46-200k-medium-cli2.1.81 | 12 | 21.3min | 0.4% | $3.68 | 0.84% |
| dotnet-install-loop | csharp-script | sonnet46-200k-medium-cli2.1.81 | 13 | 44.2min | 0.9% | $7.17 | 1.64% |
| permission-denial-loops | powershell-strict | sonnet46-200k-medium-cli2.1.81 | 17 | 81.3min | 1.6% | $9.45 | 2.16% |
| permission-denial-loops | default | sonnet46-200k-medium-cli2.1.81 | 18 | 93.7min | 1.8% | $12.17 | 2.79% |
| repeated-test-reruns | csharp-script | opus46-200k-medium-cli2.1.81 | 24 | 55.7min | 1.1% | $16.57 | 3.79% |
| permission-denial-loops | powershell | sonnet46-200k-medium-cli2.1.81 | 18 | 126.0min | 2.5% | $19.18 | 4.39% |
| permission-denial-loops | csharp-script | sonnet46-200k-medium-cli2.1.81 | 17 | 138.8min | 2.7% | $21.10 | 4.83% |
| dotnet-install-loop | csharp-script | opus46-200k-medium-cli2.1.81 | 16 | 178.6min | 3.5% | $40.93 | 9.37% |
| repeated-test-reruns | powershell | opus46-200k-medium-cli2.1.81 | 48 | 215.3min | 4.2% | $50.76 | 11.62% |
| permission-denial-loops | powershell | opus46-200k-medium-cli2.1.81 | 17 | 280.0min | 5.5% | $65.92 | 15.10% |
| repeated-test-reruns | powershell-strict | opus46-200k-medium-cli2.1.81 | 49 | 302.7min | 5.9% | $73.02 | 16.72% |
| permission-denial-loops | csharp-script | opus46-200k-medium-cli2.1.81 | 16 | 349.2min | 6.8% | $87.42 | 20.02% |
| permission-denial-loops | default | opus46-200k-medium-cli2.1.81 | 18 | 439.2min | 8.6% | $99.42 | 22.77% |
| permission-denial-loops | powershell-strict | opus46-200k-medium-cli2.1.81 | 18 | 391.5min | 7.7% | $101.79 | 23.31% |
| repeated-test-reruns | default | opus46-200k-medium-cli2.1.81 | 50 | 439.7min | 8.6% | $107.75 | 24.68% |

</details>

<details>
<summary>Sorted by fell-in count (fewest first)</summary>

| Trap | Language | Model | Fell In | Time Lost | % of Time | $ Lost | % of $ |
|------|------|-------|---------|-----------|-----------|--------|--------|
| pwsh-invoked-from-bash | powershell | sonnet46-200k-medium-cli2.1.81 | 1 | 7.7min | 0.2% | $1.46 | 0.33% |
| fixture-rework | default | opus46-200k-medium-cli2.1.81 | 1 | 0.5min | 0.0% | $0.03 | 0.01% |
| fixture-rework | default | sonnet46-200k-medium-cli2.1.81 | 1 | 0.8min | 0.0% | $0.15 | 0.03% |
| fixture-rework | powershell | sonnet46-200k-medium-cli2.1.81 | 1 | 0.5min | 0.0% | $0.08 | 0.02% |
| repeated-test-reruns | powershell-strict | sonnet46-200k-medium-cli2.1.81 | 6 | 7.0min | 0.1% | $0.64 | 0.15% |
| repeated-test-reruns | powershell | sonnet46-200k-medium-cli2.1.81 | 12 | 21.3min | 0.4% | $3.68 | 0.84% |
| dotnet-install-loop | csharp-script | sonnet46-200k-medium-cli2.1.81 | 13 | 44.2min | 0.9% | $7.17 | 1.64% |
| repeated-test-reruns | csharp-script | sonnet46-200k-medium-cli2.1.81 | 15 | 18.0min | 0.4% | $2.60 | 0.59% |
| permission-denial-loops | csharp-script | opus46-200k-medium-cli2.1.81 | 16 | 349.2min | 6.8% | $87.42 | 20.02% |
| dotnet-install-loop | csharp-script | opus46-200k-medium-cli2.1.81 | 16 | 178.6min | 3.5% | $40.93 | 9.37% |
| permission-denial-loops | csharp-script | sonnet46-200k-medium-cli2.1.81 | 17 | 138.8min | 2.7% | $21.10 | 4.83% |
| permission-denial-loops | powershell | opus46-200k-medium-cli2.1.81 | 17 | 280.0min | 5.5% | $65.92 | 15.10% |
| permission-denial-loops | powershell-strict | sonnet46-200k-medium-cli2.1.81 | 17 | 81.3min | 1.6% | $9.45 | 2.16% |
| permission-denial-loops | default | opus46-200k-medium-cli2.1.81 | 18 | 439.2min | 8.6% | $99.42 | 22.77% |
| permission-denial-loops | default | sonnet46-200k-medium-cli2.1.81 | 18 | 93.7min | 1.8% | $12.17 | 2.79% |
| permission-denial-loops | powershell | sonnet46-200k-medium-cli2.1.81 | 18 | 126.0min | 2.5% | $19.18 | 4.39% |
| permission-denial-loops | powershell-strict | opus46-200k-medium-cli2.1.81 | 18 | 391.5min | 7.7% | $101.79 | 23.31% |
| repeated-test-reruns | default | sonnet46-200k-medium-cli2.1.81 | 23 | 27.7min | 0.5% | $3.54 | 0.81% |
| repeated-test-reruns | csharp-script | opus46-200k-medium-cli2.1.81 | 24 | 55.7min | 1.1% | $16.57 | 3.79% |
| repeated-test-reruns | powershell | opus46-200k-medium-cli2.1.81 | 48 | 215.3min | 4.2% | $50.76 | 11.62% |
| repeated-test-reruns | powershell-strict | opus46-200k-medium-cli2.1.81 | 49 | 302.7min | 5.9% | $73.02 | 16.72% |
| repeated-test-reruns | default | opus46-200k-medium-cli2.1.81 | 50 | 439.7min | 8.6% | $107.75 | 24.68% |

</details>

#### Trap Descriptions

- **dotnet-install-loop**: Agent stuck in loop trying to install/verify .NET SDK, blocked by CLI sandbox.
- **fixture-rework**: Agent wrote, broke, and rewrote test fixture data (4+ fixture-related commands).
- **permission-denial-loops**: CLI sandbox blocked commands and agent retried instead of adapting (v1 harness issue).
- **pwsh-invoked-from-bash**: Agent used `pwsh -Command`/`-File` from bash `run:` steps instead of `shell: pwsh`, causing cross-shell debugging (parse errors, quoting issues, scope problems, late pwsh discovery in act).
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
| csharp-script | opus46-200k-medium-cli2.1.81 | 16 | 56 | 583.4min | 11.4% | $144.91 | 33.19% |
| csharp-script | opus46-200k-medium-cliunk | 2 | 0 | 0.0min | 0.0% | $0.00 | 0.00% |
| csharp-script | sonnet46-200k-medium-cli2.1.81 | 17 | 45 | 201.0min | 3.9% | $30.87 | 7.07% |
| csharp-script | sonnet46-200k-medium-cliunk | 1 | 0 | 0.0min | 0.0% | $0.00 | 0.00% |
| default | opus46-200k-medium-cli2.1.81 | 18 | 69 | 879.3min | 17.2% | $207.20 | 47.45% |
| default | sonnet46-200k-medium-cli2.1.81 | 18 | 42 | 122.1min | 2.4% | $15.86 | 3.63% |
| powershell | opus46-200k-medium-cli2.1.81 | 17 | 65 | 495.3min | 9.7% | $116.68 | 26.72% |
| powershell | opus46-200k-medium-cliunk | 1 | 0 | 0.0min | 0.0% | $0.00 | 0.00% |
| powershell | sonnet46-200k-medium-cli2.1.81 | 18 | 32 | 155.5min | 3.1% | $24.40 | 5.59% |
| powershell-strict | opus46-200k-medium-cli2.1.81 | 18 | 67 | 694.2min | 13.6% | $174.81 | 40.03% |
| powershell-strict | sonnet46-200k-medium-cli2.1.81 | 17 | 23 | 88.3min | 1.7% | $10.09 | 2.31% |
| powershell-strict | sonnet46-200k-medium-cliunk | 1 | 0 | 0.0min | 0.0% | $0.00 | 0.00% |


<details>
<summary>Sorted by time lost (least first)</summary>

| Language | Model | Runs | Traps | Time Lost | % of Time | $ Lost | % of $ |
|------|-------|------|-------|-----------|-----------|--------|--------|
| csharp-script | opus46-200k-medium-cliunk | 2 | 0 | 0.0min | 0.0% | $0.00 | 0.00% |
| csharp-script | sonnet46-200k-medium-cliunk | 1 | 0 | 0.0min | 0.0% | $0.00 | 0.00% |
| powershell | opus46-200k-medium-cliunk | 1 | 0 | 0.0min | 0.0% | $0.00 | 0.00% |
| powershell-strict | sonnet46-200k-medium-cliunk | 1 | 0 | 0.0min | 0.0% | $0.00 | 0.00% |
| powershell-strict | sonnet46-200k-medium-cli2.1.81 | 17 | 23 | 88.3min | 1.7% | $10.09 | 2.31% |
| default | sonnet46-200k-medium-cli2.1.81 | 18 | 42 | 122.1min | 2.4% | $15.86 | 3.63% |
| powershell | sonnet46-200k-medium-cli2.1.81 | 18 | 32 | 155.5min | 3.1% | $24.40 | 5.59% |
| csharp-script | sonnet46-200k-medium-cli2.1.81 | 17 | 45 | 201.0min | 3.9% | $30.87 | 7.07% |
| powershell | opus46-200k-medium-cli2.1.81 | 17 | 65 | 495.3min | 9.7% | $116.68 | 26.72% |
| csharp-script | opus46-200k-medium-cli2.1.81 | 16 | 56 | 583.4min | 11.4% | $144.91 | 33.19% |
| powershell-strict | opus46-200k-medium-cli2.1.81 | 18 | 67 | 694.2min | 13.6% | $174.81 | 40.03% |
| default | opus46-200k-medium-cli2.1.81 | 18 | 69 | 879.3min | 17.2% | $207.20 | 47.45% |

</details>

<details>
<summary>Sorted by $ lost (least first)</summary>

| Language | Model | Runs | Traps | Time Lost | % of Time | $ Lost | % of $ |
|------|-------|------|-------|-----------|-----------|--------|--------|
| csharp-script | opus46-200k-medium-cliunk | 2 | 0 | 0.0min | 0.0% | $0.00 | 0.00% |
| csharp-script | sonnet46-200k-medium-cliunk | 1 | 0 | 0.0min | 0.0% | $0.00 | 0.00% |
| powershell | opus46-200k-medium-cliunk | 1 | 0 | 0.0min | 0.0% | $0.00 | 0.00% |
| powershell-strict | sonnet46-200k-medium-cliunk | 1 | 0 | 0.0min | 0.0% | $0.00 | 0.00% |
| powershell-strict | sonnet46-200k-medium-cli2.1.81 | 17 | 23 | 88.3min | 1.7% | $10.09 | 2.31% |
| default | sonnet46-200k-medium-cli2.1.81 | 18 | 42 | 122.1min | 2.4% | $15.86 | 3.63% |
| powershell | sonnet46-200k-medium-cli2.1.81 | 18 | 32 | 155.5min | 3.1% | $24.40 | 5.59% |
| csharp-script | sonnet46-200k-medium-cli2.1.81 | 17 | 45 | 201.0min | 3.9% | $30.87 | 7.07% |
| powershell | opus46-200k-medium-cli2.1.81 | 17 | 65 | 495.3min | 9.7% | $116.68 | 26.72% |
| csharp-script | opus46-200k-medium-cli2.1.81 | 16 | 56 | 583.4min | 11.4% | $144.91 | 33.19% |
| powershell-strict | opus46-200k-medium-cli2.1.81 | 18 | 67 | 694.2min | 13.6% | $174.81 | 40.03% |
| default | opus46-200k-medium-cli2.1.81 | 18 | 69 | 879.3min | 17.2% | $207.20 | 47.45% |

</details>

### Prompt Cache Savings

| Status | Runs | $ Saved | % of $ |
|--------|------|---------|--------|
| Full hit (100%) | 0 | $0.00 | 0.00% |
| Partial | 125 | $4.84 | 1.11% |
| Miss | 14 | $0.00 | 0.00% |

## Test Quality Evaluation

### Structural Metrics by Language/Model/Effort

Automated analysis of test files: test count, assertion count, and test-to-code line ratio.

| Language | Model | Avg Tests | Avg Assertions | Avg Assert/Test | Avg Test:Code Ratio |
|------|-------|-----------|----------------|-----------------|---------------------|
| csharp-script | opus46-200k-medium | 32.0 | 71.4 | 2.2 | 1.41 |
| csharp-script | sonnet46-200k-medium | 23.5 | 55.1 | 2.3 | 0.77 |
| default | opus46-200k-medium | 34.2 | 60.7 | 1.8 | 1.41 |
| default | sonnet46-200k-medium | 31.7 | 55.8 | 1.8 | 1.30 |
| powershell | opus46-200k-medium | 39.1 | 66.8 | 1.7 | 38.36 |
| powershell | sonnet46-200k-medium | 25.7 | 45.3 | 1.8 | 2.47 |
| powershell-strict | opus46-200k-medium | 37.5 | 71.0 | 1.9 | 76.19 |
| powershell-strict | sonnet46-200k-medium | 27.0 | 48.9 | 1.8 | 13.65 |


<details>
<summary>Sorted by avg tests (most first)</summary>

| Language | Model | Avg Tests | Avg Assertions | Avg Assert/Test | Avg Test:Code Ratio |
|------|-------|-----------|----------------|-----------------|---------------------|
| powershell | opus46-200k-medium | 39.1 | 66.8 | 1.7 | 38.36 |
| powershell-strict | opus46-200k-medium | 37.5 | 71.0 | 1.9 | 76.19 |
| default | opus46-200k-medium | 34.2 | 60.7 | 1.8 | 1.41 |
| csharp-script | opus46-200k-medium | 32.0 | 71.4 | 2.2 | 1.41 |
| default | sonnet46-200k-medium | 31.7 | 55.8 | 1.8 | 1.30 |
| powershell-strict | sonnet46-200k-medium | 27.0 | 48.9 | 1.8 | 13.65 |
| powershell | sonnet46-200k-medium | 25.7 | 45.3 | 1.8 | 2.47 |
| csharp-script | sonnet46-200k-medium | 23.5 | 55.1 | 2.3 | 0.77 |

</details>

<details>
<summary>Sorted by avg assertions (most first)</summary>

| Language | Model | Avg Tests | Avg Assertions | Avg Assert/Test | Avg Test:Code Ratio |
|------|-------|-----------|----------------|-----------------|---------------------|
| csharp-script | opus46-200k-medium | 32.0 | 71.4 | 2.2 | 1.41 |
| powershell-strict | opus46-200k-medium | 37.5 | 71.0 | 1.9 | 76.19 |
| powershell | opus46-200k-medium | 39.1 | 66.8 | 1.7 | 38.36 |
| default | opus46-200k-medium | 34.2 | 60.7 | 1.8 | 1.41 |
| default | sonnet46-200k-medium | 31.7 | 55.8 | 1.8 | 1.30 |
| csharp-script | sonnet46-200k-medium | 23.5 | 55.1 | 2.3 | 0.77 |
| powershell-strict | sonnet46-200k-medium | 27.0 | 48.9 | 1.8 | 13.65 |
| powershell | sonnet46-200k-medium | 25.7 | 45.3 | 1.8 | 2.47 |

</details>

<details>
<summary>Sorted by avg test:code ratio (highest first)</summary>

| Language | Model | Avg Tests | Avg Assertions | Avg Assert/Test | Avg Test:Code Ratio |
|------|-------|-----------|----------------|-----------------|---------------------|
| powershell-strict | opus46-200k-medium | 37.5 | 71.0 | 1.9 | 76.19 |
| powershell | opus46-200k-medium | 39.1 | 66.8 | 1.7 | 38.36 |
| powershell-strict | sonnet46-200k-medium | 27.0 | 48.9 | 1.8 | 13.65 |
| powershell | sonnet46-200k-medium | 25.7 | 45.3 | 1.8 | 2.47 |
| default | opus46-200k-medium | 34.2 | 60.7 | 1.8 | 1.41 |
| csharp-script | opus46-200k-medium | 32.0 | 71.4 | 2.2 | 1.41 |
| default | sonnet46-200k-medium | 31.7 | 55.8 | 1.8 | 1.30 |
| csharp-script | sonnet46-200k-medium | 23.5 | 55.1 | 2.3 | 0.77 |

</details>


<details>
<summary>Per-run structural metrics</summary>

| Task | Language | Model | Tests | Assertions | Assert/Test | Test Lines | Impl Lines | Test:Code |
|------|------|-------|-------|------------|-------------|------------|------------|-----------|
| CSV Report Generator | csharp-script | opus46-200k-medium | 9 | 18 | 2.0 | 114 | 18 | 6.33 |
| CSV Report Generator | csharp-script | sonnet46-200k-medium | 22 | 58 | 2.6 | 344 | 278 | 1.24 |
| CSV Report Generator | default | opus46-200k-medium | 29 | 40 | 1.4 | 203 | 154 | 1.32 |
| CSV Report Generator | default | sonnet46-200k-medium | 18 | 34 | 1.9 | 279 | 207 | 1.35 |
| CSV Report Generator | powershell | opus46-200k-medium | 36 | 47 | 1.3 | 289 | 177 | 1.63 |
| CSV Report Generator | powershell | sonnet46-200k-medium | 17 | 27 | 1.6 | 180 | 215 | 0.84 |
| CSV Report Generator | powershell-strict | opus46-200k-medium | 25 | 50 | 2.0 | 270 | 38 | 7.11 |
| CSV Report Generator | powershell-strict | sonnet46-200k-medium | 24 | 39 | 1.6 | 226 | 66 | 3.42 |
| Log File Analyzer | csharp-script | opus46-200k-medium | 38 | 107 | 2.8 | 613 | 606 | 1.01 |
| Log File Analyzer | csharp-script | sonnet46-200k-medium | 34 | 100 | 2.9 | 589 | 589 | 1.00 |
| Log File Analyzer | default | opus46-200k-medium | 0 | 0 | 0.0 | 0 | 812 | 0.00 |
| Log File Analyzer | default | sonnet46-200k-medium | 64 | 122 | 1.9 | 778 | 372 | 2.09 |
| Log File Analyzer | powershell | opus46-200k-medium | 33 | 55 | 1.7 | 294 | 291 | 1.01 |
| Log File Analyzer | powershell | sonnet46-200k-medium | 34 | 57 | 1.7 | 365 | 373 | 0.98 |
| Log File Analyzer | powershell-strict | opus46-200k-medium | 28 | 73 | 2.6 | 344 | 54 | 6.37 |
| Log File Analyzer | powershell-strict | sonnet46-200k-medium | 44 | 66 | 1.5 | 357 | 52 | 6.87 |
| Directory Tree Sync | csharp-script | opus46-200k-medium | 17 | 41 | 2.4 | 330 | 481 | 0.69 |
| Directory Tree Sync | csharp-script | sonnet46-200k-medium | 27 | 93 | 3.4 | 611 | 721 | 0.85 |
| Directory Tree Sync | default | opus46-200k-medium | 28 | 52 | 1.9 | 414 | 245 | 1.69 |
| Directory Tree Sync | default | sonnet46-200k-medium | 34 | 51 | 1.5 | 427 | 252 | 1.69 |
| Directory Tree Sync | powershell | opus46-200k-medium | 26 | 51 | 2.0 | 481 | 275 | 1.75 |
| Directory Tree Sync | powershell | sonnet46-200k-medium | 26 | 45 | 1.7 | 371 | 277 | 1.34 |
| Directory Tree Sync | powershell-strict | opus46-200k-medium | 29 | 97 | 3.3 | 522 | 4 | 130.50 |
| Directory Tree Sync | powershell-strict | sonnet46-200k-medium | 28 | 47 | 1.7 | 457 | 329 | 1.39 |
| REST API Client | csharp-script | opus46-200k-medium | 29 | 90 | 3.1 | 968 | 579 | 1.67 |
| REST API Client | csharp-script | sonnet46-200k-medium | 30 | 65 | 2.2 | 573 | 500 | 1.15 |
| REST API Client | default | opus46-200k-medium | 25 | 51 | 2.0 | 366 | 210 | 1.74 |
| REST API Client | default | sonnet46-200k-medium | 26 | 40 | 1.5 | 418 | 276 | 1.51 |
| REST API Client | powershell | opus46-200k-medium | 21 | 23 | 1.1 | 373 | 3 | 124.33 |
| REST API Client | powershell | sonnet46-200k-medium | 26 | 28 | 1.1 | 373 | 322 | 1.16 |
| REST API Client | powershell-strict | opus46-200k-medium | 40 | 50 | 1.2 | 638 | 53 | 12.04 |
| REST API Client | powershell-strict | sonnet46-200k-medium | 21 | 47 | 2.2 | 381 | 24 | 15.88 |
| Process Monitor | csharp-script | opus46-200k-medium | 33 | 74 | 2.2 | 511 | 281 | 1.82 |
| Process Monitor | csharp-script | sonnet46-200k-medium | 0 | 0 | 0.0 | 86 | 0 | 0.00 |
| Process Monitor | default | opus46-200k-medium | 31 | 43 | 1.4 | 320 | 260 | 1.23 |
| Process Monitor | default | sonnet46-200k-medium | 23 | 51 | 2.2 | 285 | 263 | 1.08 |
| Process Monitor | powershell | opus46-200k-medium | 37 | 66 | 1.8 | 379 | 1 | 379.00 |
| Process Monitor | powershell | sonnet46-200k-medium | 17 | 44 | 2.6 | 214 | 239 | 0.90 |
| Process Monitor | powershell-strict | opus46-200k-medium | 40 | 75 | 1.9 | 417 | 0 | 0.00 |
| Process Monitor | powershell-strict | sonnet46-200k-medium | 28 | 50 | 1.8 | 310 | 33 | 9.39 |
| Config File Migrator | csharp-script | opus46-200k-medium | 72 | 132 | 1.8 | 981 | 720 | 1.36 |
| Config File Migrator | csharp-script | sonnet46-200k-medium | 0 | 0 | 0.0 | 81 | 0 | 0.00 |
| Config File Migrator | default | opus46-200k-medium | 43 | 90 | 2.1 | 510 | 435 | 1.17 |
| Config File Migrator | default | sonnet46-200k-medium | 42 | 68 | 1.6 | 487 | 383 | 1.27 |
| Config File Migrator | powershell | opus46-200k-medium | 67 | 102 | 1.5 | 647 | 329 | 1.97 |
| Config File Migrator | powershell | sonnet46-200k-medium | 33 | 72 | 2.2 | 548 | 470 | 1.17 |
| Config File Migrator | powershell-strict | opus46-200k-medium | 78 | 133 | 1.7 | 624 | 3 | 208.00 |
| Config File Migrator | powershell-strict | sonnet46-200k-medium | 28 | 51 | 1.8 | 326 | 25 | 13.04 |
| Batch File Renamer | csharp-script | opus46-200k-medium | 23 | 62 | 2.7 | 482 | 464 | 1.04 |
| Batch File Renamer | csharp-script | sonnet46-200k-medium | 15 | 39 | 2.6 | 391 | 667 | 0.59 |
| Batch File Renamer | default | opus46-200k-medium | 31 | 45 | 1.5 | 369 | 344 | 1.07 |
| Batch File Renamer | default | sonnet46-200k-medium | 22 | 44 | 2.0 | 328 | 221 | 1.48 |
| Batch File Renamer | powershell | opus46-200k-medium | 34 | 94 | 2.8 | 571 | 329 | 1.74 |
| Batch File Renamer | powershell | sonnet46-200k-medium | 18 | 34 | 1.9 | 243 | 208 | 1.17 |
| Batch File Renamer | powershell-strict | opus46-200k-medium | 23 | 50 | 2.2 | 375 | 0 | 0.00 |
| Batch File Renamer | powershell-strict | sonnet46-200k-medium | 18 | 50 | 2.8 | 323 | 17 | 19.00 |
| Database Seed Script | csharp-script | opus46-200k-medium | 38 | 62 | 1.6 | 622 | 640 | 0.97 |
| Database Seed Script | csharp-script | sonnet46-200k-medium | 51 | 102 | 2.0 | 741 | 1109 | 0.67 |
| Database Seed Script | default | opus46-200k-medium | 50 | 75 | 1.5 | 477 | 366 | 1.30 |
| Database Seed Script | default | sonnet46-200k-medium | 30 | 51 | 1.7 | 341 | 388 | 0.88 |
| Database Seed Script | powershell | opus46-200k-medium | 70 | 120 | 1.7 | 544 | 569 | 0.96 |
| Database Seed Script | powershell | sonnet46-200k-medium | 27 | 65 | 2.4 | 315 | 493 | 0.64 |
| Database Seed Script | powershell-strict | opus46-200k-medium | 47 | 95 | 2.0 | 449 | 30 | 14.97 |
| Database Seed Script | powershell-strict | sonnet46-200k-medium | 46 | 80 | 1.7 | 454 | 137 | 3.31 |
| Error Retry Pipeline | csharp-script | opus46-200k-medium | 21 | 61 | 2.9 | 398 | 541 | 0.74 |
| Error Retry Pipeline | csharp-script | sonnet46-200k-medium | 10 | 35 | 3.5 | 266 | 481 | 0.55 |
| Error Retry Pipeline | default | opus46-200k-medium | 29 | 104 | 3.6 | 612 | 249 | 2.46 |
| Error Retry Pipeline | default | sonnet46-200k-medium | 23 | 45 | 2.0 | 305 | 328 | 0.93 |
| Error Retry Pipeline | powershell | opus46-200k-medium | 25 | 89 | 3.6 | 420 | 245 | 1.71 |
| Error Retry Pipeline | powershell | sonnet46-200k-medium | 21 | 42 | 2.0 | 232 | 9 | 25.78 |
| Error Retry Pipeline | powershell-strict | opus46-200k-medium | 35 | 93 | 2.7 | 546 | 2 | 273.00 |
| Error Retry Pipeline | powershell-strict | sonnet46-200k-medium | 17 | 45 | 2.6 | 208 | 0 | 0.00 |
| Multi-file Search and Replace | csharp-script | opus46-200k-medium | 38 | 88 | 2.3 | 681 | 544 | 1.25 |
| Multi-file Search and Replace | csharp-script | sonnet46-200k-medium | 10 | 40 | 4.0 | 279 | 491 | 0.57 |
| Multi-file Search and Replace | default | opus46-200k-medium | 38 | 65 | 1.7 | 429 | 227 | 1.89 |
| Multi-file Search and Replace | default | sonnet46-200k-medium | 39 | 75 | 1.9 | 411 | 375 | 1.10 |
| Multi-file Search and Replace | powershell | opus46-200k-medium | 38 | 56 | 1.5 | 381 | 6 | 63.50 |
| Multi-file Search and Replace | powershell | sonnet46-200k-medium | 19 | 29 | 1.5 | 261 | 198 | 1.32 |
| Multi-file Search and Replace | powershell-strict | opus46-200k-medium | 14 | 38 | 2.7 | 251 | 242 | 1.04 |
| Multi-file Search and Replace | powershell-strict | sonnet46-200k-medium | 36 | 70 | 1.9 | 565 | 355 | 1.59 |
| Semantic Version Bumper | csharp-script | opus46-200k-medium | 0 | 0 | 0.0 | 0 | 18 | 0.00 |
| Semantic Version Bumper | csharp-script | sonnet46-200k-medium | 53 | 108 | 2.0 | 847 | 722 | 1.17 |
| Semantic Version Bumper | default | opus46-200k-medium | 53 | 72 | 1.4 | 429 | 395 | 1.09 |
| Semantic Version Bumper | default | sonnet46-200k-medium | 35 | 35 | 1.0 | 267 | 354 | 0.75 |
| Semantic Version Bumper | powershell | opus46-200k-medium | 54 | 69 | 1.3 | 431 | 0 | 0.00 |
| Semantic Version Bumper | powershell | sonnet46-200k-medium | 33 | 46 | 1.4 | 329 | 263 | 1.25 |
| Semantic Version Bumper | powershell-strict | opus46-200k-medium | 34 | 62 | 1.8 | 393 | 5 | 78.60 |
| Semantic Version Bumper | powershell-strict | sonnet46-200k-medium | 42 | 57 | 1.4 | 389 | 349 | 1.11 |
| PR Label Assigner | csharp-script | opus46-200k-medium | 27 | 49 | 1.8 | 532 | 509 | 1.05 |
| PR Label Assigner | csharp-script | sonnet46-200k-medium | 25 | 35 | 1.4 | 344 | 380 | 0.91 |
| PR Label Assigner | default | opus46-200k-medium | 28 | 39 | 1.4 | 306 | 211 | 1.45 |
| PR Label Assigner | default | sonnet46-200k-medium | 22 | 27 | 1.2 | 337 | 193 | 1.75 |
| PR Label Assigner | powershell | opus46-200k-medium | 31 | 56 | 1.8 | 342 | 263 | 1.30 |
| PR Label Assigner | powershell | sonnet46-200k-medium | 39 | 61 | 1.6 | 286 | 168 | 1.70 |
| PR Label Assigner | powershell-strict | opus46-200k-medium | 35 | 59 | 1.7 | 395 | 275 | 1.44 |
| PR Label Assigner | powershell-strict | sonnet46-200k-medium | 28 | 42 | 1.5 | 239 | 141 | 1.70 |
| Dependency License Checker | csharp-script | opus46-200k-medium | 36 | 93 | 2.6 | 708 | 547 | 1.29 |
| Dependency License Checker | csharp-script | sonnet46-200k-medium | 24 | 72 | 3.0 | 529 | 649 | 0.82 |
| Dependency License Checker | default | opus46-200k-medium | 37 | 71 | 1.9 | 531 | 358 | 1.48 |
| Dependency License Checker | default | sonnet46-200k-medium | 31 | 55 | 1.8 | 384 | 291 | 1.32 |
| Dependency License Checker | powershell | opus46-200k-medium | 36 | 62 | 1.7 | 482 | 361 | 1.34 |
| Dependency License Checker | powershell | sonnet46-200k-medium | 22 | 43 | 2.0 | 258 | 270 | 0.96 |
| Dependency License Checker | powershell-strict | opus46-200k-medium | 37 | 71 | 1.9 | 497 | 6 | 82.83 |
| Dependency License Checker | powershell-strict | sonnet46-200k-medium | 0 | 0 | 0.0 | 16 | 0 | 0.00 |
| Docker Image Tag Generator | csharp-script | opus46-200k-medium | 30 | 36 | 1.2 | 441 | 308 | 1.43 |
| Docker Image Tag Generator | csharp-script | sonnet46-200k-medium | 32 | 35 | 1.1 | 297 | 331 | 0.90 |
| Docker Image Tag Generator | default | opus46-200k-medium | 33 | 39 | 1.2 | 259 | 141 | 1.84 |
| Docker Image Tag Generator | default | sonnet46-200k-medium | 17 | 20 | 1.2 | 142 | 155 | 0.92 |
| Docker Image Tag Generator | powershell | opus46-200k-medium | 39 | 50 | 1.3 | 270 | 151 | 1.79 |
| Docker Image Tag Generator | powershell | sonnet46-200k-medium | 20 | 23 | 1.1 | 155 | 129 | 1.20 |
| Docker Image Tag Generator | powershell-strict | opus46-200k-medium | 26 | 36 | 1.4 | 305 | 173 | 1.76 |
| Docker Image Tag Generator | powershell-strict | sonnet46-200k-medium | 23 | 28 | 1.2 | 357 | 71 | 5.03 |
| Test Results Aggregator | csharp-script | opus46-200k-medium | 47 | 83 | 1.8 | 695 | 1022 | 0.68 |
| Test Results Aggregator | csharp-script | sonnet46-200k-medium | 50 | 94 | 1.9 | 795 | 505 | 1.57 |
| Test Results Aggregator | default | opus46-200k-medium | 41 | 62 | 1.5 | 375 | 351 | 1.07 |
| Test Results Aggregator | default | sonnet46-200k-medium | 52 | 120 | 2.3 | 710 | 471 | 1.51 |
| Test Results Aggregator | powershell | opus46-200k-medium | 48 | 68 | 1.4 | 414 | 4 | 103.50 |
| Test Results Aggregator | powershell | sonnet46-200k-medium | 40 | 68 | 1.7 | 372 | 406 | 0.92 |
| Test Results Aggregator | powershell-strict | opus46-200k-medium | 56 | 70 | 1.2 | 454 | 5 | 90.80 |
| Test Results Aggregator | powershell-strict | sonnet46-200k-medium | 14 | 45 | 3.2 | 247 | 3 | 82.33 |
| Environment Matrix Generator | csharp-script | opus46-200k-medium | 50 | 106 | 2.1 | 1104 | 774 | 1.43 |
| Environment Matrix Generator | csharp-script | sonnet46-200k-medium | 0 | 0 | 0.0 | 30 | 0 | 0.00 |
| Environment Matrix Generator | default | opus46-200k-medium | 30 | 56 | 1.9 | 427 | 270 | 1.58 |
| Environment Matrix Generator | default | sonnet46-200k-medium | 46 | 66 | 1.4 | 576 | 349 | 1.65 |
| Environment Matrix Generator | powershell | opus46-200k-medium | 44 | 74 | 1.7 | 672 | 259 | 2.59 |
| Environment Matrix Generator | powershell | sonnet46-200k-medium | 19 | 36 | 1.9 | 294 | 222 | 1.32 |
| Environment Matrix Generator | powershell-strict | opus46-200k-medium | 27 | 47 | 1.7 | 493 | 372 | 1.33 |
| Environment Matrix Generator | powershell-strict | sonnet46-200k-medium | 24 | 36 | 1.5 | 323 | 17 | 19.00 |
| Artifact Cleanup Script | csharp-script | opus46-200k-medium | 26 | 73 | 2.8 | 558 | 418 | 1.33 |
| Artifact Cleanup Script | csharp-script | sonnet46-200k-medium | 16 | 53 | 3.3 | 398 | 399 | 1.00 |
| Artifact Cleanup Script | default | opus46-200k-medium | 32 | 71 | 2.2 | 430 | 396 | 1.09 |
| Artifact Cleanup Script | default | sonnet46-200k-medium | 21 | 50 | 2.4 | 306 | 248 | 1.23 |
| Artifact Cleanup Script | powershell | opus46-200k-medium | 34 | 81 | 2.4 | 440 | 344 | 1.28 |
| Artifact Cleanup Script | powershell | sonnet46-200k-medium | 25 | 43 | 1.7 | 318 | 409 | 0.78 |
| Artifact Cleanup Script | powershell-strict | opus46-200k-medium | 34 | 73 | 2.1 | 653 | 3 | 217.67 |
| Artifact Cleanup Script | powershell-strict | sonnet46-200k-medium | 35 | 74 | 2.1 | 524 | 9 | 58.22 |
| Secret Rotation Validator | csharp-script | opus46-200k-medium | 42 | 110 | 2.6 | 732 | 610 | 1.20 |
| Secret Rotation Validator | csharp-script | sonnet46-200k-medium | 24 | 63 | 2.6 | 428 | 543 | 0.79 |
| Secret Rotation Validator | default | opus46-200k-medium | 58 | 118 | 2.0 | 766 | 418 | 1.83 |
| Secret Rotation Validator | default | sonnet46-200k-medium | 26 | 50 | 1.9 | 282 | 304 | 0.93 |
| Secret Rotation Validator | powershell | opus46-200k-medium | 30 | 40 | 1.3 | 328 | 328 | 1.00 |
| Secret Rotation Validator | powershell | sonnet46-200k-medium | 27 | 53 | 2.0 | 435 | 408 | 1.07 |
| Secret Rotation Validator | powershell-strict | opus46-200k-medium | 67 | 106 | 1.6 | 732 | 3 | 244.00 |
| Secret Rotation Validator | powershell-strict | sonnet46-200k-medium | 30 | 53 | 1.8 | 441 | 101 | 4.37 |

</details>

### LLM-as-Judge Scores

An LLM evaluates each test suite on four dimensions (1-5 scale):

- **Coverage** (1-5): Do tests exercise the key requirements? 1 = most untested, 5 = all covered.
- **Rigor** (1-5): Edge cases, error handling, boundary conditions? 1 = happy path only, 5 = thorough.
- **Design** (1-5): Test organization, fixtures, readability? 1 = messy/brittle, 5 = well-structured.
- **Overall** (1-5): Holistic quality — would you trust this suite to catch regressions? 1 = no, 5 = absolutely. Use this as the primary ranking metric.

| Language | Model | Avg Overall | Avg Coverage | Avg Rigor | Avg Design | Judge Cost |
|------|-------|-------------|-------------|-----------|------------|------------|
| csharp-script | opus46-200k-medium | **4.0** | 4.6 | 3.6 | 4.3 | $1.4348 |
| csharp-script | sonnet46-200k-medium | **3.6** | 3.9 | 3.0 | 3.9 | $1.2972 |
| default | opus46-200k-medium | **4.4** | 4.9 | 4.0 | 4.7 | $0.9990 |
| default | sonnet46-200k-medium | **4.1** | 4.6 | 3.4 | 4.2 | $1.0822 |
| powershell | opus46-200k-medium | **4.2** | 4.9 | 4.1 | 4.4 | $1.1611 |
| powershell | sonnet46-200k-medium | **4.0** | 4.7 | 3.3 | 4.1 | $1.1508 |
| powershell-strict | opus46-200k-medium | **4.1** | 4.9 | 3.9 | 4.4 | $1.0742 |
| powershell-strict | sonnet46-200k-medium | **3.8** | 4.5 | 3.4 | 4.1 | $0.9716 |
| **Total** | | | | | | **$9.1709** |


<details>
<summary>Sorted by avg overall (highest first)</summary>

| Language | Model | Avg Overall | Avg Coverage | Avg Rigor | Avg Design | Judge Cost |
|------|-------|-------------|-------------|-----------|------------|------------|
| default | opus46-200k-medium | **4.4** | 4.9 | 4.0 | 4.7 | $0.9990 |
| powershell | opus46-200k-medium | **4.2** | 4.9 | 4.1 | 4.4 | $1.1611 |
| default | sonnet46-200k-medium | **4.1** | 4.6 | 3.4 | 4.2 | $1.0822 |
| powershell-strict | opus46-200k-medium | **4.1** | 4.9 | 3.9 | 4.4 | $1.0742 |
| csharp-script | opus46-200k-medium | **4.0** | 4.6 | 3.6 | 4.3 | $1.4348 |
| powershell | sonnet46-200k-medium | **4.0** | 4.7 | 3.3 | 4.1 | $1.1508 |
| powershell-strict | sonnet46-200k-medium | **3.8** | 4.5 | 3.4 | 4.1 | $0.9716 |
| csharp-script | sonnet46-200k-medium | **3.6** | 3.9 | 3.0 | 3.9 | $1.2972 |

</details>

<details>
<summary>Sorted by avg coverage (highest first)</summary>

| Language | Model | Avg Overall | Avg Coverage | Avg Rigor | Avg Design | Judge Cost |
|------|-------|-------------|-------------|-----------|------------|------------|
| powershell | opus46-200k-medium | **4.2** | 4.9 | 4.1 | 4.4 | $1.1611 |
| default | opus46-200k-medium | **4.4** | 4.9 | 4.0 | 4.7 | $0.9990 |
| powershell-strict | opus46-200k-medium | **4.1** | 4.9 | 3.9 | 4.4 | $1.0742 |
| powershell | sonnet46-200k-medium | **4.0** | 4.7 | 3.3 | 4.1 | $1.1508 |
| csharp-script | opus46-200k-medium | **4.0** | 4.6 | 3.6 | 4.3 | $1.4348 |
| default | sonnet46-200k-medium | **4.1** | 4.6 | 3.4 | 4.2 | $1.0822 |
| powershell-strict | sonnet46-200k-medium | **3.8** | 4.5 | 3.4 | 4.1 | $0.9716 |
| csharp-script | sonnet46-200k-medium | **3.6** | 3.9 | 3.0 | 3.9 | $1.2972 |

</details>

<details>
<summary>Sorted by avg rigor (highest first)</summary>

| Language | Model | Avg Overall | Avg Coverage | Avg Rigor | Avg Design | Judge Cost |
|------|-------|-------------|-------------|-----------|------------|------------|
| powershell | opus46-200k-medium | **4.2** | 4.9 | 4.1 | 4.4 | $1.1611 |
| default | opus46-200k-medium | **4.4** | 4.9 | 4.0 | 4.7 | $0.9990 |
| powershell-strict | opus46-200k-medium | **4.1** | 4.9 | 3.9 | 4.4 | $1.0742 |
| csharp-script | opus46-200k-medium | **4.0** | 4.6 | 3.6 | 4.3 | $1.4348 |
| default | sonnet46-200k-medium | **4.1** | 4.6 | 3.4 | 4.2 | $1.0822 |
| powershell-strict | sonnet46-200k-medium | **3.8** | 4.5 | 3.4 | 4.1 | $0.9716 |
| powershell | sonnet46-200k-medium | **4.0** | 4.7 | 3.3 | 4.1 | $1.1508 |
| csharp-script | sonnet46-200k-medium | **3.6** | 3.9 | 3.0 | 3.9 | $1.2972 |

</details>

<details>
<summary>Sorted by avg design (highest first)</summary>

| Language | Model | Avg Overall | Avg Coverage | Avg Rigor | Avg Design | Judge Cost |
|------|-------|-------------|-------------|-----------|------------|------------|
| default | opus46-200k-medium | **4.4** | 4.9 | 4.0 | 4.7 | $0.9990 |
| powershell-strict | opus46-200k-medium | **4.1** | 4.9 | 3.9 | 4.4 | $1.0742 |
| powershell | opus46-200k-medium | **4.2** | 4.9 | 4.1 | 4.4 | $1.1611 |
| csharp-script | opus46-200k-medium | **4.0** | 4.6 | 3.6 | 4.3 | $1.4348 |
| default | sonnet46-200k-medium | **4.1** | 4.6 | 3.4 | 4.2 | $1.0822 |
| powershell-strict | sonnet46-200k-medium | **3.8** | 4.5 | 3.4 | 4.1 | $0.9716 |
| powershell | sonnet46-200k-medium | **4.0** | 4.7 | 3.3 | 4.1 | $1.1508 |
| csharp-script | sonnet46-200k-medium | **3.6** | 3.9 | 3.0 | 3.9 | $1.2972 |

</details>


<details>
<summary>Per-run LLM judge scores</summary>

| Task | Language | Model | Cov | Rig | Des | Ovr | Summary |
|------|------|-------|-----|-----|-----|-----|---------|
| CSV Report Generator | csharp-script | opus46-200k-medium | 2.0 | 3.0 | 3.0 | 2.0 |  |
| CSV Report Generator | csharp-script | sonnet46-200k-medium | 4.0 | 3.0 | 4.0 | 4.0 |  |
| CSV Report Generator | default | opus46-200k-medium | 5.0 | 3.0 | 5.0 | 4.0 |  |
| CSV Report Generator | default | sonnet46-200k-medium | 5.0 | 4.0 | 4.0 | 4.0 |  |
| CSV Report Generator | powershell | opus46-200k-medium | 5.0 | 4.0 | 4.0 | 4.0 |  |
| CSV Report Generator | powershell | sonnet46-200k-medium | 4.0 | 3.0 | 4.0 | 4.0 |  |
| CSV Report Generator | powershell-strict | opus46-200k-medium | 5.0 | 4.0 | 4.0 | 4.0 |  |
| CSV Report Generator | powershell-strict | sonnet46-200k-medium | 5.0 | 3.0 | 4.0 | 4.0 |  |
| Log File Analyzer | csharp-script | opus46-200k-medium | 5.0 | 3.0 | 4.0 | 4.0 |  |
| Log File Analyzer | csharp-script | sonnet46-200k-medium | 5.0 | 4.0 | 5.0 | 5.0 |  |
| Log File Analyzer | default | sonnet46-200k-medium | 4.0 | 3.0 | 3.0 | 3.0 |  |
| Log File Analyzer | powershell | opus46-200k-medium | 5.0 | 4.0 | 4.0 | 4.0 |  |
| Log File Analyzer | powershell | sonnet46-200k-medium | 5.0 | 3.0 | 4.0 | 4.0 |  |
| Log File Analyzer | powershell-strict | opus46-200k-medium | 4.0 | 4.0 | 4.0 | 4.0 |  |
| Log File Analyzer | powershell-strict | sonnet46-200k-medium | 5.0 | 3.0 | 3.0 | 4.0 |  |
| Directory Tree Sync | csharp-script | opus46-200k-medium | 4.0 | 3.0 | 5.0 | 4.0 |  |
| Directory Tree Sync | csharp-script | sonnet46-200k-medium | 5.0 | 4.0 | 5.0 | 5.0 |  |
| Directory Tree Sync | default | opus46-200k-medium | 5.0 | 4.0 | 4.0 | 4.0 |  |
| Directory Tree Sync | default | sonnet46-200k-medium | 5.0 | 4.0 | 5.0 | 5.0 |  |
| Directory Tree Sync | powershell | opus46-200k-medium | 5.0 | 4.0 | 4.0 | 4.0 |  |
| Directory Tree Sync | powershell | sonnet46-200k-medium | 5.0 | 3.0 | 4.0 | 4.0 |  |
| Directory Tree Sync | powershell-strict | opus46-200k-medium | 5.0 | 4.0 | 5.0 | 4.0 |  |
| Directory Tree Sync | powershell-strict | sonnet46-200k-medium | 4.0 | 3.0 | 4.0 | 4.0 |  |
| REST API Client | csharp-script | opus46-200k-medium | 5.0 | 4.0 | 4.0 | 4.0 |  |
| REST API Client | csharp-script | sonnet46-200k-medium | 4.0 | 4.0 | 5.0 | 4.0 |  |
| REST API Client | default | opus46-200k-medium | 5.0 | 4.0 | 4.0 | 4.0 |  |
| REST API Client | default | sonnet46-200k-medium | 5.0 | 4.0 | 5.0 | 4.0 |  |
| REST API Client | powershell | opus46-200k-medium | 5.0 | 4.0 | 4.0 | 4.0 |  |
| REST API Client | powershell | sonnet46-200k-medium | 5.0 | 4.0 | 4.0 | 4.0 |  |
| REST API Client | powershell-strict | opus46-200k-medium | 5.0 | 4.0 | 5.0 | 4.0 |  |
| REST API Client | powershell-strict | sonnet46-200k-medium | 4.0 | 4.0 | 5.0 | 4.0 |  |
| Process Monitor | csharp-script | opus46-200k-medium | 5.0 | 4.0 | 4.0 | 4.0 |  |
| Process Monitor | csharp-script | sonnet46-200k-medium | 1.0 | 1.0 | 1.0 | 1.0 |  |
| Process Monitor | default | opus46-200k-medium | 5.0 | 4.0 | 5.0 | 4.0 |  |
| Process Monitor | default | sonnet46-200k-medium | 4.0 | 3.0 | 4.0 | 4.0 |  |
| Process Monitor | powershell | opus46-200k-medium | 5.0 | 4.0 | 5.0 | 5.0 |  |
| Process Monitor | powershell | sonnet46-200k-medium | 5.0 | 3.0 | 4.0 | 4.0 |  |
| Process Monitor | powershell-strict | opus46-200k-medium | 5.0 | 4.0 | 5.0 | 4.0 |  |
| Process Monitor | powershell-strict | sonnet46-200k-medium | 5.0 | 4.0 | 5.0 | 4.0 |  |
| Config File Migrator | csharp-script | opus46-200k-medium | 5.0 | 4.0 | 4.0 | 4.0 |  |
| Config File Migrator | csharp-script | sonnet46-200k-medium | 1.0 | 1.0 | 1.0 | 1.0 |  |
| Config File Migrator | default | opus46-200k-medium | 5.0 | 4.0 | 4.0 | 4.0 |  |
| Config File Migrator | default | sonnet46-200k-medium | 4.0 | 3.0 | 4.0 | 4.0 |  |
| Config File Migrator | powershell | opus46-200k-medium | 5.0 | 4.0 | 4.0 | 4.0 |  |
| Config File Migrator | powershell | sonnet46-200k-medium | 4.0 | 3.0 | 4.0 | 4.0 |  |
| Config File Migrator | powershell-strict | opus46-200k-medium | 5.0 | 4.0 | 4.0 | 4.0 |  |
| Config File Migrator | powershell-strict | sonnet46-200k-medium | 4.0 | 3.0 | 3.0 | 3.0 |  |
| Batch File Renamer | csharp-script | opus46-200k-medium | 5.0 | 4.0 | 4.0 | 4.0 |  |
| Batch File Renamer | csharp-script | sonnet46-200k-medium | 4.0 | 3.0 | 4.0 | 3.0 |  |
| Batch File Renamer | default | opus46-200k-medium | 4.0 | 3.0 | 5.0 | 4.0 |  |
| Batch File Renamer | default | sonnet46-200k-medium | 5.0 | 4.0 | 5.0 | 5.0 |  |
| Batch File Renamer | powershell | opus46-200k-medium | 5.0 | 4.0 | 4.0 | 4.0 |  |
| Batch File Renamer | powershell | sonnet46-200k-medium | 4.0 | 3.0 | 4.0 | 4.0 |  |
| Batch File Renamer | powershell-strict | opus46-200k-medium | 5.0 | 4.0 | 5.0 | 4.0 |  |
| Batch File Renamer | powershell-strict | sonnet46-200k-medium | 5.0 | 4.0 | 5.0 | 5.0 |  |
| Database Seed Script | csharp-script | opus46-200k-medium | 5.0 | 4.0 | 4.0 | 4.0 |  |
| Database Seed Script | csharp-script | sonnet46-200k-medium | 5.0 | 4.0 | 5.0 | 5.0 |  |
| Database Seed Script | default | opus46-200k-medium | 5.0 | 4.0 | 5.0 | 5.0 |  |
| Database Seed Script | default | sonnet46-200k-medium | 4.0 | 3.0 | 4.0 | 3.0 |  |
| Database Seed Script | powershell | opus46-200k-medium | 5.0 | 4.0 | 5.0 | 4.0 |  |
| Database Seed Script | powershell | sonnet46-200k-medium | 4.0 | 3.0 | 4.0 | 4.0 |  |
| Database Seed Script | powershell-strict | opus46-200k-medium | 5.0 | 3.0 | 4.0 | 4.0 |  |
| Database Seed Script | powershell-strict | sonnet46-200k-medium | 5.0 | 3.0 | 4.0 | 4.0 |  |
| Error Retry Pipeline | csharp-script | opus46-200k-medium | 4.0 | 3.0 | 4.0 | 4.0 |  |
| Error Retry Pipeline | csharp-script | sonnet46-200k-medium | 4.0 | 3.0 | 4.0 | 4.0 |  |
| Error Retry Pipeline | default | sonnet46-200k-medium | 5.0 | 3.0 | 4.0 | 4.0 |  |
| Error Retry Pipeline | powershell | opus46-200k-medium | 5.0 | 4.0 | 5.0 | 5.0 |  |
| Error Retry Pipeline | powershell | sonnet46-200k-medium | 5.0 | 4.0 | 4.0 | 4.0 |  |
| Error Retry Pipeline | powershell-strict | opus46-200k-medium | 5.0 | 4.0 | 5.0 | 4.0 |  |
| Error Retry Pipeline | powershell-strict | sonnet46-200k-medium | 5.0 | 3.0 | 3.0 | 4.0 |  |
| Multi-file Search and Replace | csharp-script | opus46-200k-medium | 4.0 | 3.0 | 5.0 | 4.0 |  |
| Multi-file Search and Replace | csharp-script | sonnet46-200k-medium | 5.0 | 4.0 | 5.0 | 5.0 |  |
| Multi-file Search and Replace | default | opus46-200k-medium | 5.0 | 4.0 | 5.0 | 4.0 |  |
| Multi-file Search and Replace | default | sonnet46-200k-medium | 5.0 | 3.0 | 4.0 | 4.0 |  |
| Multi-file Search and Replace | powershell | opus46-200k-medium | 5.0 | 4.0 | 4.0 | 4.0 |  |
| Multi-file Search and Replace | powershell | sonnet46-200k-medium | 5.0 | 3.0 | 4.0 | 4.0 |  |
| Multi-file Search and Replace | powershell-strict | opus46-200k-medium | 4.0 | 3.0 | 3.0 | 3.0 |  |
| Multi-file Search and Replace | powershell-strict | sonnet46-200k-medium | 5.0 | 4.0 | 5.0 | 4.0 |  |
| Semantic Version Bumper | csharp-script | sonnet46-200k-medium | 5.0 | 4.0 | 5.0 | 5.0 |  |
| Semantic Version Bumper | default | opus46-200k-medium | 5.0 | 4.0 | 5.0 | 4.0 |  |
| Semantic Version Bumper | default | sonnet46-200k-medium | 5.0 | 4.0 | 5.0 | 5.0 |  |
| Semantic Version Bumper | powershell | opus46-200k-medium | 5.0 | 4.0 | 5.0 | 4.0 |  |
| Semantic Version Bumper | powershell | sonnet46-200k-medium | 5.0 | 4.0 | 4.0 | 4.0 |  |
| Semantic Version Bumper | powershell-strict | opus46-200k-medium | 5.0 | 4.0 | 5.0 | 4.0 |  |
| Semantic Version Bumper | powershell-strict | sonnet46-200k-medium | 5.0 | 4.0 | 4.0 | 4.0 |  |
| PR Label Assigner | csharp-script | opus46-200k-medium | 5.0 | 4.0 | 5.0 | 4.0 |  |
| PR Label Assigner | csharp-script | sonnet46-200k-medium | 4.0 | 3.0 | 4.0 | 3.0 |  |
| PR Label Assigner | default | opus46-200k-medium | 5.0 | 4.0 | 5.0 | 5.0 |  |
| PR Label Assigner | default | sonnet46-200k-medium | 5.0 | 3.0 | 4.0 | 4.0 |  |
| PR Label Assigner | powershell | opus46-200k-medium | 4.0 | 4.0 | 4.0 | 4.0 |  |
| PR Label Assigner | powershell | sonnet46-200k-medium | 4.0 | 4.0 | 4.0 | 4.0 |  |
| PR Label Assigner | powershell-strict | opus46-200k-medium | 5.0 | 4.0 | 5.0 | 4.0 |  |
| PR Label Assigner | powershell-strict | sonnet46-200k-medium | 4.0 | 4.0 | 5.0 | 4.0 |  |
| Dependency License Checker | csharp-script | opus46-200k-medium | 5.0 | 4.0 | 4.0 | 4.0 |  |
| Dependency License Checker | csharp-script | sonnet46-200k-medium | 4.0 | 3.0 | 5.0 | 4.0 |  |
| Dependency License Checker | default | opus46-200k-medium | 5.0 | 5.0 | 5.0 | 5.0 |  |
| Dependency License Checker | default | sonnet46-200k-medium | 5.0 | 4.0 | 5.0 | 5.0 |  |
| Dependency License Checker | powershell | opus46-200k-medium | 5.0 | 4.0 | 4.0 | 4.0 |  |
| Dependency License Checker | powershell | sonnet46-200k-medium | 5.0 | 3.0 | 4.0 | 4.0 |  |
| Dependency License Checker | powershell-strict | opus46-200k-medium | 5.0 | 4.0 | 5.0 | 5.0 |  |
| Dependency License Checker | powershell-strict | sonnet46-200k-medium | 1.0 | 1.0 | 1.0 | 1.0 |  |
| Docker Image Tag Generator | csharp-script | opus46-200k-medium | 5.0 | 4.0 | 5.0 | 4.0 |  |
| Docker Image Tag Generator | csharp-script | sonnet46-200k-medium | 4.0 | 3.0 | 3.0 | 3.0 |  |
| Docker Image Tag Generator | default | opus46-200k-medium | 5.0 | 4.0 | 5.0 | 5.0 |  |
| Docker Image Tag Generator | default | sonnet46-200k-medium | 4.0 | 3.0 | 4.0 | 4.0 |  |
| Docker Image Tag Generator | powershell | opus46-200k-medium | 5.0 | 5.0 | 5.0 | 5.0 |  |
| Docker Image Tag Generator | powershell | sonnet46-200k-medium | 4.0 | 4.0 | 5.0 | 4.0 |  |
| Docker Image Tag Generator | powershell-strict | opus46-200k-medium | 5.0 | 4.0 | 4.0 | 4.0 |  |
| Docker Image Tag Generator | powershell-strict | sonnet46-200k-medium | 5.0 | 4.0 | 4.0 | 4.0 |  |
| Test Results Aggregator | csharp-script | opus46-200k-medium | 5.0 | 3.0 | 3.0 | 4.0 |  |
| Test Results Aggregator | csharp-script | sonnet46-200k-medium | 5.0 | 3.0 | 4.0 | 4.0 |  |
| Test Results Aggregator | default | opus46-200k-medium | 5.0 | 3.0 | 4.0 | 4.0 |  |
| Test Results Aggregator | default | sonnet46-200k-medium | 5.0 | 4.0 | 4.0 | 4.0 |  |
| Test Results Aggregator | powershell | opus46-200k-medium | 5.0 | 4.0 | 4.0 | 4.0 |  |
| Test Results Aggregator | powershell | sonnet46-200k-medium | 5.0 | 3.0 | 4.0 | 4.0 |  |
| Test Results Aggregator | powershell-strict | opus46-200k-medium | 5.0 | 4.0 | 4.0 | 4.0 |  |
| Test Results Aggregator | powershell-strict | sonnet46-200k-medium | 5.0 | 3.0 | 4.0 | 4.0 |  |
| Environment Matrix Generator | csharp-script | opus46-200k-medium | 5.0 | 4.0 | 5.0 | 5.0 |  |
| Environment Matrix Generator | csharp-script | sonnet46-200k-medium | 1.0 | 1.0 | 1.0 | 1.0 |  |
| Environment Matrix Generator | default | opus46-200k-medium | 5.0 | 4.0 | 5.0 | 5.0 |  |
| Environment Matrix Generator | default | sonnet46-200k-medium | 4.0 | 3.0 | 3.0 | 4.0 |  |
| Environment Matrix Generator | powershell | opus46-200k-medium | 5.0 | 4.0 | 5.0 | 4.0 |  |
| Environment Matrix Generator | powershell | sonnet46-200k-medium | 5.0 | 4.0 | 4.0 | 4.0 |  |
| Environment Matrix Generator | powershell-strict | opus46-200k-medium | 5.0 | 4.0 | 4.0 | 4.0 |  |
| Environment Matrix Generator | powershell-strict | sonnet46-200k-medium | 5.0 | 4.0 | 5.0 | 4.0 |  |
| Artifact Cleanup Script | csharp-script | opus46-200k-medium | 5.0 | 4.0 | 5.0 | 4.0 |  |
| Artifact Cleanup Script | csharp-script | sonnet46-200k-medium | 5.0 | 3.0 | 4.0 | 4.0 |  |
| Artifact Cleanup Script | default | opus46-200k-medium | 5.0 | 5.0 | 5.0 | 5.0 |  |
| Artifact Cleanup Script | default | sonnet46-200k-medium | 5.0 | 3.0 | 4.0 | 4.0 |  |
| Artifact Cleanup Script | powershell | opus46-200k-medium | 5.0 | 4.0 | 4.0 | 4.0 |  |
| Artifact Cleanup Script | powershell | sonnet46-200k-medium | 5.0 | 3.0 | 4.0 | 4.0 |  |
| Artifact Cleanup Script | powershell-strict | opus46-200k-medium | 5.0 | 4.0 | 4.0 | 4.0 |  |
| Artifact Cleanup Script | powershell-strict | sonnet46-200k-medium | 5.0 | 4.0 | 5.0 | 4.0 |  |
| Secret Rotation Validator | csharp-script | opus46-200k-medium | 5.0 | 4.0 | 5.0 | 5.0 |  |
| Secret Rotation Validator | csharp-script | sonnet46-200k-medium | 4.0 | 3.0 | 5.0 | 4.0 |  |
| Secret Rotation Validator | default | opus46-200k-medium | 5.0 | 5.0 | 4.0 | 5.0 |  |
| Secret Rotation Validator | default | sonnet46-200k-medium | 4.0 | 3.0 | 4.0 | 4.0 |  |
| Secret Rotation Validator | powershell | opus46-200k-medium | 5.0 | 4.0 | 5.0 | 4.0 |  |
| Secret Rotation Validator | powershell | sonnet46-200k-medium | 5.0 | 3.0 | 4.0 | 4.0 |  |
| Secret Rotation Validator | powershell-strict | opus46-200k-medium | 5.0 | 4.0 | 5.0 | 5.0 |  |
| Secret Rotation Validator | powershell-strict | sonnet46-200k-medium | 4.0 | 3.0 | 5.0 | 4.0 |  |

</details>

### Correlation: Structural Metrics vs Tests Quality

Spearman rank correlation between automated counts and LLM judge scores.
Values near +1.0 indicate the LLM agrees with the structural signal; near 0 means no relationship.

| Structural Metric | vs Coverage | vs Rigor | vs Design | vs Overall |
|-------------------|------------|---------|----------|-----------|
| Test count | 0.37 | 0.37 | 0.2 | 0.29 |
| Assertion count | 0.3 | 0.3 | 0.19 | 0.32 |
| Test:code ratio | 0.31 | 0.41 | 0.13 | 0.18 |

*Based on 141 runs with both structural and LLM scores.*

## Per-Run Results

*Tests Quality = Overall (1-5) from LLM-as-judge of generated test code (dimensions: coverage, rigor, design). `—` = no judge data.*

| Task | Language | Model | Duration | Turns | Errors | Cost | Tests Quality | Chosen | Status |
|------|----------|-------|----------|-------|--------|------|-----------|--------|--------|
| Artifact Cleanup Script | csharp-script | opus46-200k-medium | 17.9min | 131 | 121 | $4.17 | 4.0 | csharp | ok |
| Artifact Cleanup Script | csharp-script | sonnet46-200k-medium | 9.1min | 39 | 22 | $1.16 | 4.0 | csharp | ok |
| Artifact Cleanup Script | default | opus46-200k-medium | 12.9min | 110 | 113 | $3.49 | 5.0 | python | ok |
| Artifact Cleanup Script | default | sonnet46-200k-medium | 3.2min | 26 | 15 | $0.49 | 4.0 | python | ok |
| Artifact Cleanup Script | powershell | opus46-200k-medium | 11.6min | 91 | 90 | $2.83 | 4.0 | powershell | ok |
| Artifact Cleanup Script | powershell | sonnet46-200k-medium | 13.0min | 40 | 37 | $1.63 | 4.0 | powershell | ok |
| Artifact Cleanup Script | powershell-strict | opus46-200k-medium | 16.7min | 135 | 132 | $5.03 | 4.0 | powershell | ok |
| Artifact Cleanup Script | powershell-strict | sonnet46-200k-medium | 13.3min | 52 | 35 | $1.83 | 4.0 | powershell | ok |
| Batch File Renamer | csharp-script | opus46-200k-medium | 40.4min | 108 | 134 | $3.34 | 4.0 | csharp | ok |
| Batch File Renamer | csharp-script | sonnet46-200k-medium | 19.3min | 60 | 121 | $3.76 | 3.0 | csharp | ok |
| Batch File Renamer | default | opus46-200k-medium | 33.9min | 106 | 109 | $2.76 | 4.0 | python | ok |
| Batch File Renamer | default | sonnet46-200k-medium | 46.7min | 58 | 44 | $1.27 | 5.0 | python | ok |
| Batch File Renamer | powershell | opus46-200k-medium | 67.4min | 104 | 117 | $3.32 | 4.0 | powershell | ok |
| Batch File Renamer | powershell | sonnet46-200k-medium | 246.7min | 67 | 37 | $2.07 | 4.0 | powershell | ok |
| Batch File Renamer | powershell-strict | opus46-200k-medium | 76.3min | 163 | 148 | $5.60 | 4.0 | powershell | ok |
| Batch File Renamer | powershell-strict | sonnet46-200k-medium | 12.6min | 48 | 30 | $1.38 | 5.0 | powershell | ok |
| CSV Report Generator | csharp-script | opus46-200k-medium | 271.2min | 0 | 0 | $0.00 | 2.0 | csharp | failed |
| CSV Report Generator | csharp-script | sonnet46-200k-medium | 112.8min | 48 | 26 | $1.13 | 4.0 | csharp | ok |
| CSV Report Generator | default | opus46-200k-medium | 23.8min | 222 | 225 | $4.92 | 4.0 | python | ok |
| CSV Report Generator | default | sonnet46-200k-medium | 53.2min | 37 | 25 | $0.65 | 4.0 | python | ok |
| CSV Report Generator | powershell | opus46-200k-medium | 11.4min | 97 | 89 | $3.05 | 4.0 | powershell | ok |
| CSV Report Generator | powershell | sonnet46-200k-medium | 56.1min | 52 | 27 | $0.97 | 4.0 | powershell | ok |
| CSV Report Generator | powershell-strict | opus46-200k-medium | 16.2min | 168 | 176 | $5.79 | 4.0 | powershell | ok |
| CSV Report Generator | powershell-strict | sonnet46-200k-medium | 121.6min | 74 | 41 | $1.75 | 4.0 | powershell | ok |
| Config File Migrator | csharp-script | opus46-200k-medium | 54.2min | 0 | 0 | $0.00 | 4.0 | csharp | failed |
| Config File Migrator | csharp-script | sonnet46-200k-medium | 73.6min | 138 | 58 | $5.32 | 1.0 | csharp | ok |
| Config File Migrator | default | opus46-200k-medium | 16.7min | 165 | 150 | $5.11 | 4.0 | python | ok |
| Config File Migrator | default | sonnet46-200k-medium | 58.5min | 102 | 65 | $2.44 | 4.0 | python | ok |
| Config File Migrator | powershell | opus46-200k-medium | 12.6min | 115 | 90 | $3.65 | 4.0 | powershell | ok |
| Config File Migrator | powershell | sonnet46-200k-medium | 52.0min | 81 | 60 | $2.57 | 4.0 | powershell | ok |
| Config File Migrator | powershell-strict | opus46-200k-medium | 16.2min | 154 | 130 | $5.77 | 4.0 | powershell | ok |
| Config File Migrator | powershell-strict | sonnet46-200k-medium | 44.9min | 69 | 40 | $1.84 | 3.0 | powershell | ok |
| Database Seed Script | csharp-script | opus46-200k-medium | 11.4min | 122 | 103 | $3.49 | 4.0 | csharp | ok |
| Database Seed Script | csharp-script | sonnet46-200k-medium | 28.1min | 0 | 0 | $0.00 | 5.0 | csharp | failed |
| Database Seed Script | default | opus46-200k-medium | 13.1min | 146 | 141 | $3.83 | 5.0 | python | ok |
| Database Seed Script | default | sonnet46-200k-medium | 16.3min | 42 | 28 | $0.98 | 3.0 | python | ok |
| Database Seed Script | powershell | opus46-200k-medium | 14.4min | 167 | 140 | $5.61 | 4.0 | powershell | ok |
| Database Seed Script | powershell | sonnet46-200k-medium | 12.1min | 60 | 36 | $1.67 | 4.0 | powershell | ok |
| Database Seed Script | powershell-strict | opus46-200k-medium | 19.8min | 162 | 160 | $6.54 | 4.0 | powershell | ok |
| Database Seed Script | powershell-strict | sonnet46-200k-medium | 12.7min | 35 | 17 | $1.65 | 4.0 | powershell | ok |
| Dependency License Checker | csharp-script | opus46-200k-medium | 21.8min | 223 | 197 | $8.83 | 4.0 | csharp | ok |
| Dependency License Checker | csharp-script | sonnet46-200k-medium | 26.6min | 126 | 67 | $3.08 | 4.0 | csharp | ok |
| Dependency License Checker | default | opus46-200k-medium | 17.2min | 217 | 220 | $6.00 | 5.0 | python | ok |
| Dependency License Checker | default | sonnet46-200k-medium | 7.3min | 52 | 39 | $1.18 | 5.0 | python | ok |
| Dependency License Checker | powershell | opus46-200k-medium | 14.9min | 118 | 99 | $4.17 | 4.0 | powershell | ok |
| Dependency License Checker | powershell | sonnet46-200k-medium | 3.0min | 33 | 18 | $0.59 | 4.0 | powershell | ok |
| Dependency License Checker | powershell-strict | opus46-200k-medium | 14.6min | 87 | 60 | $2.75 | 5.0 | powershell | ok |
| Dependency License Checker | powershell-strict | sonnet46-200k-medium | 15.7min | 70 | 57 | $2.20 | 1.0 | powershell | ok |
| Directory Tree Sync | csharp-script | opus46-200k-medium | 202.0min | 229 | 205 | $7.54 | 4.0 | csharp | ok |
| Directory Tree Sync | csharp-script | sonnet46-200k-medium | 143.8min | 83 | 49 | $2.42 | 5.0 | csharp | ok |
| Directory Tree Sync | default | opus46-200k-medium | 44.4min | 122 | 107 | $3.24 | 4.0 | python | ok |
| Directory Tree Sync | default | sonnet46-200k-medium | 26.1min | 17 | 9 | $0.42 | 5.0 | python | ok |
| Directory Tree Sync | powershell | opus46-200k-medium | 112.3min | 93 | 91 | $2.97 | 4.0 | powershell | ok |
| Directory Tree Sync | powershell | sonnet46-200k-medium | 69.6min | 60 | 41 | $1.54 | 4.0 | powershell | ok |
| Directory Tree Sync | powershell-strict | opus46-200k-medium | 144.7min | 140 | 140 | $4.71 | 4.0 | powershell | ok |
| Directory Tree Sync | powershell-strict | sonnet46-200k-medium | 23.7min | 31 | 19 | $0.57 | 4.0 | powershell | ok |
| Docker Image Tag Generator | csharp-script | opus46-200k-medium | 16.6min | 154 | 139 | $4.60 | 4.0 | csharp | ok |
| Docker Image Tag Generator | csharp-script | sonnet46-200k-medium | 13.3min | 103 | 88 | $2.28 | 3.0 | csharp | ok |
| Docker Image Tag Generator | default | opus46-200k-medium | 15.3min | 156 | 162 | $3.82 | 5.0 | python | ok |
| Docker Image Tag Generator | default | sonnet46-200k-medium | 3.8min | 20 | 17 | $0.50 | 4.0 | python | ok |
| Docker Image Tag Generator | powershell | opus46-200k-medium | 12.4min | 109 | 101 | $3.05 | 5.0 | powershell | ok |
| Docker Image Tag Generator | powershell | sonnet46-200k-medium | 13.5min | 169 | 143 | $3.46 | 4.0 | powershell | ok |
| Docker Image Tag Generator | powershell-strict | opus46-200k-medium | 12.2min | 130 | 127 | $3.40 | 4.0 | powershell | ok |
| Docker Image Tag Generator | powershell-strict | sonnet46-200k-medium | 8.7min | 59 | 38 | $1.34 | 4.0 | powershell | ok |
| Environment Matrix Generator | csharp-script | opus46-200k-medium | 21.0min | 175 | 142 | $6.47 | 5.0 | csharp | ok |
| Environment Matrix Generator | csharp-script | sonnet46-200k-medium | 12.9min | 85 | 59 | $2.26 | 1.0 | csharp | ok |
| Environment Matrix Generator | default | opus46-200k-medium | 15.5min | 119 | 172 | $3.93 | 5.0 | python | ok |
| Environment Matrix Generator | default | sonnet46-200k-medium | 8.2min | 52 | 33 | $1.32 | 4.0 | python | ok |
| Environment Matrix Generator | powershell | opus46-200k-medium | 14.9min | 148 | 117 | $4.93 | 4.0 | powershell | ok |
| Environment Matrix Generator | powershell | sonnet46-200k-medium | 6.7min | 30 | 33 | $0.89 | 4.0 | powershell | ok |
| Environment Matrix Generator | powershell-strict | opus46-200k-medium | 16.8min | 137 | 126 | $4.48 | 4.0 | powershell | ok |
| Environment Matrix Generator | powershell-strict | sonnet46-200k-medium | 30.0min | 0 | 0 | $0.00 | 4.0 | powershell | failed |
| Error Retry Pipeline | csharp-script | opus46-200k-medium | 26.0min | 173 | 194 | $6.97 | 4.0 | csharp | ok |
| Error Retry Pipeline | csharp-script | sonnet46-200k-medium | 10.1min | 71 | 42 | $1.49 | 4.0 | csharp | ok |
| Error Retry Pipeline | default | opus46-200k-medium | 17.1min | 156 | 140 | $3.93 | — |  | ok |
| Error Retry Pipeline | default | sonnet46-200k-medium | 8.8min | 69 | 42 | $1.50 | 4.0 | python | ok |
| Error Retry Pipeline | powershell | opus46-200k-medium | 14.6min | 80 | 90 | $3.26 | 5.0 | powershell | ok |
| Error Retry Pipeline | powershell | sonnet46-200k-medium | 8.2min | 42 | 22 | $1.05 | 4.0 | powershell | ok |
| Error Retry Pipeline | powershell-strict | opus46-200k-medium | 11.1min | 114 | 103 | $3.17 | 4.0 | powershell | ok |
| Error Retry Pipeline | powershell-strict | sonnet46-200k-medium | 7.1min | 35 | 17 | $0.92 | 4.0 | powershell | ok |
| Log File Analyzer | csharp-script | opus46-200k-medium | 168.4min | 221 | 193 | $8.66 | 4.0 | csharp | ok |
| Log File Analyzer | csharp-script | sonnet46-200k-medium | 25.4min | 131 | 73 | $4.11 | 5.0 | csharp | ok |
| Log File Analyzer | default | opus46-200k-medium | 105.3min | 195 | 205 | $5.43 | — | javascript | ok |
| Log File Analyzer | default | sonnet46-200k-medium | 10.6min | 72 | 48 | $1.84 | 3.0 | python | ok |
| Log File Analyzer | powershell | opus46-200k-medium | 143.9min | 123 | 105 | $3.88 | 4.0 | powershell | ok |
| Log File Analyzer | powershell | sonnet46-200k-medium | 10.6min | 62 | 51 | $1.78 | 4.0 | powershell | ok |
| Log File Analyzer | powershell-strict | opus46-200k-medium | 128.9min | 155 | 134 | $5.44 | 4.0 | powershell | ok |
| Log File Analyzer | powershell-strict | sonnet46-200k-medium | 25.2min | 52 | 22 | $1.37 | 4.0 | powershell | ok |
| Multi-file Search and Replace | csharp-script | opus46-200k-medium | 17.3min | 134 | 130 | $4.56 | 4.0 | csharp | ok |
| Multi-file Search and Replace | csharp-script | sonnet46-200k-medium | 14.6min | 94 | 66 | $2.39 | 5.0 | csharp | ok |
| Multi-file Search and Replace | default | opus46-200k-medium | 15.9min | 181 | 171 | $4.45 | 4.0 | python | ok |
| Multi-file Search and Replace | default | sonnet46-200k-medium | 4.5min | 25 | 21 | $0.71 | 4.0 | python | ok |
| Multi-file Search and Replace | powershell | opus46-200k-medium | 17.1min | 126 | 124 | $4.56 | 4.0 | powershell | ok |
| Multi-file Search and Replace | powershell | sonnet46-200k-medium | 8.8min | 49 | 49 | $1.17 | 4.0 | powershell | ok |
| Multi-file Search and Replace | powershell-strict | opus46-200k-medium | 12.2min | 129 | 130 | $3.52 | 3.0 | powershell | ok |
| Multi-file Search and Replace | powershell-strict | sonnet46-200k-medium | 15.3min | 69 | 62 | $2.41 | 4.0 | powershell | ok |
| PR Label Assigner | csharp-script | opus46-200k-medium | 21.5min | 215 | 203 | $7.33 | 4.0 | csharp | ok |
| PR Label Assigner | csharp-script | sonnet46-200k-medium | 21.0min | 143 | 95 | $4.26 | 3.0 | csharp | ok |
| PR Label Assigner | default | opus46-200k-medium | 16.1min | 140 | 142 | $3.77 | 5.0 | python | ok |
| PR Label Assigner | default | sonnet46-200k-medium | 6.7min | 26 | 23 | $0.92 | 4.0 | python | ok |
| PR Label Assigner | powershell | opus46-200k-medium | 10.0min | 93 | 75 | $2.48 | 4.0 | powershell | ok |
| PR Label Assigner | powershell | sonnet46-200k-medium | 7.8min | 44 | 33 | $1.26 | 4.0 | powershell | ok |
| PR Label Assigner | powershell-strict | opus46-200k-medium | 11.1min | 141 | 130 | $3.72 | 4.0 | powershell | ok |
| PR Label Assigner | powershell-strict | sonnet46-200k-medium | 8.9min | 28 | 16 | $1.02 | 4.0 | powershell | ok |
| Process Monitor | csharp-script | opus46-200k-medium | 21.7min | 182 | 188 | $6.00 | 4.0 | csharp | ok |
| Process Monitor | csharp-script | sonnet46-200k-medium | 13.2min | 61 | 33 | $1.89 | 1.0 | csharp | ok |
| Process Monitor | default | opus46-200k-medium | 9.8min | 115 | 109 | $2.34 | 4.0 | python | ok |
| Process Monitor | default | sonnet46-200k-medium | 9.8min | 76 | 61 | $1.60 | 4.0 | python | ok |
| Process Monitor | powershell | opus46-200k-medium | 14.6min | 96 | 78 | $3.28 | 5.0 | powershell | ok |
| Process Monitor | powershell | sonnet46-200k-medium | 6.6min | 53 | 33 | $1.11 | 4.0 | powershell | ok |
| Process Monitor | powershell-strict | opus46-200k-medium | 15.3min | 126 | 114 | $4.00 | 4.0 | powershell | ok |
| Process Monitor | powershell-strict | sonnet46-200k-medium | 14.1min | 46 | 39 | $2.11 | 4.0 | powershell | ok |
| REST API Client | csharp-script | opus46-200k-medium | 22.6min | 195 | 177 | $7.32 | 4.0 | csharp | ok |
| REST API Client | csharp-script | sonnet46-200k-medium | 23.2min | 74 | 63 | $3.91 | 4.0 | csharp | ok |
| REST API Client | default | opus46-200k-medium | 157.1min | 113 | 118 | $3.08 | 4.0 | python | ok |
| REST API Client | default | sonnet46-200k-medium | 10.8min | 54 | 33 | $1.49 | 4.0 | python | ok |
| REST API Client | powershell | opus46-200k-medium | 257.5min | 0 | 0 | $0.00 | 4.0 | powershell | failed |
| REST API Client | powershell | sonnet46-200k-medium | 13.9min | 56 | 35 | $1.93 | 4.0 | powershell | ok |
| REST API Client | powershell-strict | opus46-200k-medium | 378.5min | 101 | 87 | $4.06 | 4.0 | powershell | ok |
| REST API Client | powershell-strict | sonnet46-200k-medium | 13.4min | 41 | 27 | $1.82 | 4.0 | powershell | ok |
| Secret Rotation Validator | csharp-script | opus46-200k-medium | 17.2min | 162 | 149 | $5.30 | 5.0 | csharp | ok |
| Secret Rotation Validator | csharp-script | sonnet46-200k-medium | 14.2min | 74 | 85 | $2.67 | 4.0 | csharp | ok |
| Secret Rotation Validator | default | opus46-200k-medium | 12.2min | 108 | 88 | $3.43 | 5.0 | python | ok |
| Secret Rotation Validator | default | sonnet46-200k-medium | 3.7min | 23 | 19 | $0.58 | 4.0 | python | ok |
| Secret Rotation Validator | powershell | opus46-200k-medium | 15.4min | 136 | 148 | $4.01 | 4.0 | powershell | ok |
| Secret Rotation Validator | powershell | sonnet46-200k-medium | 8.3min | 61 | 53 | $1.52 | 4.0 | powershell | ok |
| Secret Rotation Validator | powershell-strict | opus46-200k-medium | 23.4min | 175 | 159 | $6.38 | 5.0 | powershell | ok |
| Secret Rotation Validator | powershell-strict | sonnet46-200k-medium | 7.0min | 13 | 6 | $0.80 | 4.0 | powershell | ok |
| Semantic Version Bumper | csharp-script | opus46-200k-medium | 6.2min | 65 | 96 | $1.39 | — | bash | ok |
| Semantic Version Bumper | csharp-script | sonnet46-200k-medium | 17.0min | 64 | 42 | $2.67 | 5.0 | csharp | ok |
| Semantic Version Bumper | default | opus46-200k-medium | 12.0min | 129 | 115 | $3.34 | 4.0 | python | ok |
| Semantic Version Bumper | default | sonnet46-200k-medium | 12.9min | 98 | 58 | $2.16 | 5.0 | python | ok |
| Semantic Version Bumper | powershell | opus46-200k-medium | 13.3min | 120 | 100 | $3.84 | 4.0 | powershell | ok |
| Semantic Version Bumper | powershell | sonnet46-200k-medium | 13.7min | 116 | 96 | $2.60 | 4.0 | powershell | ok |
| Semantic Version Bumper | powershell-strict | opus46-200k-medium | 18.5min | 225 | 210 | $7.96 | 4.0 | powershell | ok |
| Semantic Version Bumper | powershell-strict | sonnet46-200k-medium | 12.7min | 60 | 59 | $2.08 | 4.0 | powershell | ok |
| Test Results Aggregator | csharp-script | opus46-200k-medium | 11.7min | 120 | 93 | $3.40 | 4.0 | csharp | ok |
| Test Results Aggregator | csharp-script | sonnet46-200k-medium | 13.0min | 67 | 29 | $2.32 | 4.0 | csharp | ok |
| Test Results Aggregator | default | opus46-200k-medium | 16.9min | 172 | 203 | $4.97 | 4.0 | python | ok |
| Test Results Aggregator | default | sonnet46-200k-medium | 10.2min | 76 | 59 | $2.01 | 4.0 | python | ok |
| Test Results Aggregator | powershell | opus46-200k-medium | 10.2min | 89 | 70 | $3.10 | 4.0 | powershell | ok |
| Test Results Aggregator | powershell | sonnet46-200k-medium | 9.6min | 63 | 40 | $1.57 | 4.0 | powershell | ok |
| Test Results Aggregator | powershell-strict | opus46-200k-medium | 18.6min | 164 | 148 | $6.18 | 4.0 | powershell | ok |
| Test Results Aggregator | powershell-strict | sonnet46-200k-medium | 14.6min | 37 | 27 | $1.33 | 4.0 | powershell | ok |


<details>
<summary>Sorted by cost (cheapest first)</summary>

| Task | Language | Model | Duration | Turns | Errors | Cost | Tests Quality | Chosen | Status |
|------|----------|-------|----------|-------|--------|------|-----------|--------|--------|
| CSV Report Generator | csharp-script | opus46-200k-medium | 271.2min | 0 | 0 | $0.00 | 2.0 | csharp | failed |
| REST API Client | powershell | opus46-200k-medium | 257.5min | 0 | 0 | $0.00 | 4.0 | powershell | failed |
| Config File Migrator | csharp-script | opus46-200k-medium | 54.2min | 0 | 0 | $0.00 | 4.0 | csharp | failed |
| Database Seed Script | csharp-script | sonnet46-200k-medium | 28.1min | 0 | 0 | $0.00 | 5.0 | csharp | failed |
| Environment Matrix Generator | powershell-strict | sonnet46-200k-medium | 30.0min | 0 | 0 | $0.00 | 4.0 | powershell | failed |
| Directory Tree Sync | default | sonnet46-200k-medium | 26.1min | 17 | 9 | $0.42 | 5.0 | python | ok |
| Artifact Cleanup Script | default | sonnet46-200k-medium | 3.2min | 26 | 15 | $0.49 | 4.0 | python | ok |
| Docker Image Tag Generator | default | sonnet46-200k-medium | 3.8min | 20 | 17 | $0.50 | 4.0 | python | ok |
| Directory Tree Sync | powershell-strict | sonnet46-200k-medium | 23.7min | 31 | 19 | $0.57 | 4.0 | powershell | ok |
| Secret Rotation Validator | default | sonnet46-200k-medium | 3.7min | 23 | 19 | $0.58 | 4.0 | python | ok |
| Dependency License Checker | powershell | sonnet46-200k-medium | 3.0min | 33 | 18 | $0.59 | 4.0 | powershell | ok |
| CSV Report Generator | default | sonnet46-200k-medium | 53.2min | 37 | 25 | $0.65 | 4.0 | python | ok |
| Multi-file Search and Replace | default | sonnet46-200k-medium | 4.5min | 25 | 21 | $0.71 | 4.0 | python | ok |
| Secret Rotation Validator | powershell-strict | sonnet46-200k-medium | 7.0min | 13 | 6 | $0.80 | 4.0 | powershell | ok |
| Environment Matrix Generator | powershell | sonnet46-200k-medium | 6.7min | 30 | 33 | $0.89 | 4.0 | powershell | ok |
| Error Retry Pipeline | powershell-strict | sonnet46-200k-medium | 7.1min | 35 | 17 | $0.92 | 4.0 | powershell | ok |
| PR Label Assigner | default | sonnet46-200k-medium | 6.7min | 26 | 23 | $0.92 | 4.0 | python | ok |
| CSV Report Generator | powershell | sonnet46-200k-medium | 56.1min | 52 | 27 | $0.97 | 4.0 | powershell | ok |
| Database Seed Script | default | sonnet46-200k-medium | 16.3min | 42 | 28 | $0.98 | 3.0 | python | ok |
| PR Label Assigner | powershell-strict | sonnet46-200k-medium | 8.9min | 28 | 16 | $1.02 | 4.0 | powershell | ok |
| Error Retry Pipeline | powershell | sonnet46-200k-medium | 8.2min | 42 | 22 | $1.05 | 4.0 | powershell | ok |
| Process Monitor | powershell | sonnet46-200k-medium | 6.6min | 53 | 33 | $1.11 | 4.0 | powershell | ok |
| CSV Report Generator | csharp-script | sonnet46-200k-medium | 112.8min | 48 | 26 | $1.13 | 4.0 | csharp | ok |
| Artifact Cleanup Script | csharp-script | sonnet46-200k-medium | 9.1min | 39 | 22 | $1.16 | 4.0 | csharp | ok |
| Multi-file Search and Replace | powershell | sonnet46-200k-medium | 8.8min | 49 | 49 | $1.17 | 4.0 | powershell | ok |
| Dependency License Checker | default | sonnet46-200k-medium | 7.3min | 52 | 39 | $1.18 | 5.0 | python | ok |
| PR Label Assigner | powershell | sonnet46-200k-medium | 7.8min | 44 | 33 | $1.26 | 4.0 | powershell | ok |
| Batch File Renamer | default | sonnet46-200k-medium | 46.7min | 58 | 44 | $1.27 | 5.0 | python | ok |
| Environment Matrix Generator | default | sonnet46-200k-medium | 8.2min | 52 | 33 | $1.32 | 4.0 | python | ok |
| Test Results Aggregator | powershell-strict | sonnet46-200k-medium | 14.6min | 37 | 27 | $1.33 | 4.0 | powershell | ok |
| Docker Image Tag Generator | powershell-strict | sonnet46-200k-medium | 8.7min | 59 | 38 | $1.34 | 4.0 | powershell | ok |
| Log File Analyzer | powershell-strict | sonnet46-200k-medium | 25.2min | 52 | 22 | $1.37 | 4.0 | powershell | ok |
| Batch File Renamer | powershell-strict | sonnet46-200k-medium | 12.6min | 48 | 30 | $1.38 | 5.0 | powershell | ok |
| Semantic Version Bumper | csharp-script | opus46-200k-medium | 6.2min | 65 | 96 | $1.39 | — | bash | ok |
| REST API Client | default | sonnet46-200k-medium | 10.8min | 54 | 33 | $1.49 | 4.0 | python | ok |
| Error Retry Pipeline | csharp-script | sonnet46-200k-medium | 10.1min | 71 | 42 | $1.49 | 4.0 | csharp | ok |
| Error Retry Pipeline | default | sonnet46-200k-medium | 8.8min | 69 | 42 | $1.50 | 4.0 | python | ok |
| Secret Rotation Validator | powershell | sonnet46-200k-medium | 8.3min | 61 | 53 | $1.52 | 4.0 | powershell | ok |
| Directory Tree Sync | powershell | sonnet46-200k-medium | 69.6min | 60 | 41 | $1.54 | 4.0 | powershell | ok |
| Test Results Aggregator | powershell | sonnet46-200k-medium | 9.6min | 63 | 40 | $1.57 | 4.0 | powershell | ok |
| Process Monitor | default | sonnet46-200k-medium | 9.8min | 76 | 61 | $1.60 | 4.0 | python | ok |
| Artifact Cleanup Script | powershell | sonnet46-200k-medium | 13.0min | 40 | 37 | $1.63 | 4.0 | powershell | ok |
| Database Seed Script | powershell-strict | sonnet46-200k-medium | 12.7min | 35 | 17 | $1.65 | 4.0 | powershell | ok |
| Database Seed Script | powershell | sonnet46-200k-medium | 12.1min | 60 | 36 | $1.67 | 4.0 | powershell | ok |
| CSV Report Generator | powershell-strict | sonnet46-200k-medium | 121.6min | 74 | 41 | $1.75 | 4.0 | powershell | ok |
| Log File Analyzer | powershell | sonnet46-200k-medium | 10.6min | 62 | 51 | $1.78 | 4.0 | powershell | ok |
| REST API Client | powershell-strict | sonnet46-200k-medium | 13.4min | 41 | 27 | $1.82 | 4.0 | powershell | ok |
| Artifact Cleanup Script | powershell-strict | sonnet46-200k-medium | 13.3min | 52 | 35 | $1.83 | 4.0 | powershell | ok |
| Log File Analyzer | default | sonnet46-200k-medium | 10.6min | 72 | 48 | $1.84 | 3.0 | python | ok |
| Config File Migrator | powershell-strict | sonnet46-200k-medium | 44.9min | 69 | 40 | $1.84 | 3.0 | powershell | ok |
| Process Monitor | csharp-script | sonnet46-200k-medium | 13.2min | 61 | 33 | $1.89 | 1.0 | csharp | ok |
| REST API Client | powershell | sonnet46-200k-medium | 13.9min | 56 | 35 | $1.93 | 4.0 | powershell | ok |
| Test Results Aggregator | default | sonnet46-200k-medium | 10.2min | 76 | 59 | $2.01 | 4.0 | python | ok |
| Batch File Renamer | powershell | sonnet46-200k-medium | 246.7min | 67 | 37 | $2.07 | 4.0 | powershell | ok |
| Semantic Version Bumper | powershell-strict | sonnet46-200k-medium | 12.7min | 60 | 59 | $2.08 | 4.0 | powershell | ok |
| Process Monitor | powershell-strict | sonnet46-200k-medium | 14.1min | 46 | 39 | $2.11 | 4.0 | powershell | ok |
| Semantic Version Bumper | default | sonnet46-200k-medium | 12.9min | 98 | 58 | $2.16 | 5.0 | python | ok |
| Dependency License Checker | powershell-strict | sonnet46-200k-medium | 15.7min | 70 | 57 | $2.20 | 1.0 | powershell | ok |
| Environment Matrix Generator | csharp-script | sonnet46-200k-medium | 12.9min | 85 | 59 | $2.26 | 1.0 | csharp | ok |
| Docker Image Tag Generator | csharp-script | sonnet46-200k-medium | 13.3min | 103 | 88 | $2.28 | 3.0 | csharp | ok |
| Test Results Aggregator | csharp-script | sonnet46-200k-medium | 13.0min | 67 | 29 | $2.32 | 4.0 | csharp | ok |
| Process Monitor | default | opus46-200k-medium | 9.8min | 115 | 109 | $2.34 | 4.0 | python | ok |
| Multi-file Search and Replace | csharp-script | sonnet46-200k-medium | 14.6min | 94 | 66 | $2.39 | 5.0 | csharp | ok |
| Multi-file Search and Replace | powershell-strict | sonnet46-200k-medium | 15.3min | 69 | 62 | $2.41 | 4.0 | powershell | ok |
| Directory Tree Sync | csharp-script | sonnet46-200k-medium | 143.8min | 83 | 49 | $2.42 | 5.0 | csharp | ok |
| Config File Migrator | default | sonnet46-200k-medium | 58.5min | 102 | 65 | $2.44 | 4.0 | python | ok |
| PR Label Assigner | powershell | opus46-200k-medium | 10.0min | 93 | 75 | $2.48 | 4.0 | powershell | ok |
| Config File Migrator | powershell | sonnet46-200k-medium | 52.0min | 81 | 60 | $2.57 | 4.0 | powershell | ok |
| Semantic Version Bumper | powershell | sonnet46-200k-medium | 13.7min | 116 | 96 | $2.60 | 4.0 | powershell | ok |
| Semantic Version Bumper | csharp-script | sonnet46-200k-medium | 17.0min | 64 | 42 | $2.67 | 5.0 | csharp | ok |
| Secret Rotation Validator | csharp-script | sonnet46-200k-medium | 14.2min | 74 | 85 | $2.67 | 4.0 | csharp | ok |
| Dependency License Checker | powershell-strict | opus46-200k-medium | 14.6min | 87 | 60 | $2.75 | 5.0 | powershell | ok |
| Batch File Renamer | default | opus46-200k-medium | 33.9min | 106 | 109 | $2.76 | 4.0 | python | ok |
| Artifact Cleanup Script | powershell | opus46-200k-medium | 11.6min | 91 | 90 | $2.83 | 4.0 | powershell | ok |
| Directory Tree Sync | powershell | opus46-200k-medium | 112.3min | 93 | 91 | $2.97 | 4.0 | powershell | ok |
| Docker Image Tag Generator | powershell | opus46-200k-medium | 12.4min | 109 | 101 | $3.05 | 5.0 | powershell | ok |
| CSV Report Generator | powershell | opus46-200k-medium | 11.4min | 97 | 89 | $3.05 | 4.0 | powershell | ok |
| REST API Client | default | opus46-200k-medium | 157.1min | 113 | 118 | $3.08 | 4.0 | python | ok |
| Dependency License Checker | csharp-script | sonnet46-200k-medium | 26.6min | 126 | 67 | $3.08 | 4.0 | csharp | ok |
| Test Results Aggregator | powershell | opus46-200k-medium | 10.2min | 89 | 70 | $3.10 | 4.0 | powershell | ok |
| Error Retry Pipeline | powershell-strict | opus46-200k-medium | 11.1min | 114 | 103 | $3.17 | 4.0 | powershell | ok |
| Directory Tree Sync | default | opus46-200k-medium | 44.4min | 122 | 107 | $3.24 | 4.0 | python | ok |
| Error Retry Pipeline | powershell | opus46-200k-medium | 14.6min | 80 | 90 | $3.26 | 5.0 | powershell | ok |
| Process Monitor | powershell | opus46-200k-medium | 14.6min | 96 | 78 | $3.28 | 5.0 | powershell | ok |
| Batch File Renamer | powershell | opus46-200k-medium | 67.4min | 104 | 117 | $3.32 | 4.0 | powershell | ok |
| Semantic Version Bumper | default | opus46-200k-medium | 12.0min | 129 | 115 | $3.34 | 4.0 | python | ok |
| Batch File Renamer | csharp-script | opus46-200k-medium | 40.4min | 108 | 134 | $3.34 | 4.0 | csharp | ok |
| Docker Image Tag Generator | powershell-strict | opus46-200k-medium | 12.2min | 130 | 127 | $3.40 | 4.0 | powershell | ok |
| Test Results Aggregator | csharp-script | opus46-200k-medium | 11.7min | 120 | 93 | $3.40 | 4.0 | csharp | ok |
| Secret Rotation Validator | default | opus46-200k-medium | 12.2min | 108 | 88 | $3.43 | 5.0 | python | ok |
| Docker Image Tag Generator | powershell | sonnet46-200k-medium | 13.5min | 169 | 143 | $3.46 | 4.0 | powershell | ok |
| Artifact Cleanup Script | default | opus46-200k-medium | 12.9min | 110 | 113 | $3.49 | 5.0 | python | ok |
| Database Seed Script | csharp-script | opus46-200k-medium | 11.4min | 122 | 103 | $3.49 | 4.0 | csharp | ok |
| Multi-file Search and Replace | powershell-strict | opus46-200k-medium | 12.2min | 129 | 130 | $3.52 | 3.0 | powershell | ok |
| Config File Migrator | powershell | opus46-200k-medium | 12.6min | 115 | 90 | $3.65 | 4.0 | powershell | ok |
| PR Label Assigner | powershell-strict | opus46-200k-medium | 11.1min | 141 | 130 | $3.72 | 4.0 | powershell | ok |
| Batch File Renamer | csharp-script | sonnet46-200k-medium | 19.3min | 60 | 121 | $3.76 | 3.0 | csharp | ok |
| PR Label Assigner | default | opus46-200k-medium | 16.1min | 140 | 142 | $3.77 | 5.0 | python | ok |
| Docker Image Tag Generator | default | opus46-200k-medium | 15.3min | 156 | 162 | $3.82 | 5.0 | python | ok |
| Database Seed Script | default | opus46-200k-medium | 13.1min | 146 | 141 | $3.83 | 5.0 | python | ok |
| Semantic Version Bumper | powershell | opus46-200k-medium | 13.3min | 120 | 100 | $3.84 | 4.0 | powershell | ok |
| Log File Analyzer | powershell | opus46-200k-medium | 143.9min | 123 | 105 | $3.88 | 4.0 | powershell | ok |
| REST API Client | csharp-script | sonnet46-200k-medium | 23.2min | 74 | 63 | $3.91 | 4.0 | csharp | ok |
| Error Retry Pipeline | default | opus46-200k-medium | 17.1min | 156 | 140 | $3.93 | — |  | ok |
| Environment Matrix Generator | default | opus46-200k-medium | 15.5min | 119 | 172 | $3.93 | 5.0 | python | ok |
| Process Monitor | powershell-strict | opus46-200k-medium | 15.3min | 126 | 114 | $4.00 | 4.0 | powershell | ok |
| Secret Rotation Validator | powershell | opus46-200k-medium | 15.4min | 136 | 148 | $4.01 | 4.0 | powershell | ok |
| REST API Client | powershell-strict | opus46-200k-medium | 378.5min | 101 | 87 | $4.06 | 4.0 | powershell | ok |
| Log File Analyzer | csharp-script | sonnet46-200k-medium | 25.4min | 131 | 73 | $4.11 | 5.0 | csharp | ok |
| Dependency License Checker | powershell | opus46-200k-medium | 14.9min | 118 | 99 | $4.17 | 4.0 | powershell | ok |
| Artifact Cleanup Script | csharp-script | opus46-200k-medium | 17.9min | 131 | 121 | $4.17 | 4.0 | csharp | ok |
| PR Label Assigner | csharp-script | sonnet46-200k-medium | 21.0min | 143 | 95 | $4.26 | 3.0 | csharp | ok |
| Multi-file Search and Replace | default | opus46-200k-medium | 15.9min | 181 | 171 | $4.45 | 4.0 | python | ok |
| Environment Matrix Generator | powershell-strict | opus46-200k-medium | 16.8min | 137 | 126 | $4.48 | 4.0 | powershell | ok |
| Multi-file Search and Replace | powershell | opus46-200k-medium | 17.1min | 126 | 124 | $4.56 | 4.0 | powershell | ok |
| Multi-file Search and Replace | csharp-script | opus46-200k-medium | 17.3min | 134 | 130 | $4.56 | 4.0 | csharp | ok |
| Docker Image Tag Generator | csharp-script | opus46-200k-medium | 16.6min | 154 | 139 | $4.60 | 4.0 | csharp | ok |
| Directory Tree Sync | powershell-strict | opus46-200k-medium | 144.7min | 140 | 140 | $4.71 | 4.0 | powershell | ok |
| CSV Report Generator | default | opus46-200k-medium | 23.8min | 222 | 225 | $4.92 | 4.0 | python | ok |
| Environment Matrix Generator | powershell | opus46-200k-medium | 14.9min | 148 | 117 | $4.93 | 4.0 | powershell | ok |
| Test Results Aggregator | default | opus46-200k-medium | 16.9min | 172 | 203 | $4.97 | 4.0 | python | ok |
| Artifact Cleanup Script | powershell-strict | opus46-200k-medium | 16.7min | 135 | 132 | $5.03 | 4.0 | powershell | ok |
| Config File Migrator | default | opus46-200k-medium | 16.7min | 165 | 150 | $5.11 | 4.0 | python | ok |
| Secret Rotation Validator | csharp-script | opus46-200k-medium | 17.2min | 162 | 149 | $5.30 | 5.0 | csharp | ok |
| Config File Migrator | csharp-script | sonnet46-200k-medium | 73.6min | 138 | 58 | $5.32 | 1.0 | csharp | ok |
| Log File Analyzer | default | opus46-200k-medium | 105.3min | 195 | 205 | $5.43 | — | javascript | ok |
| Log File Analyzer | powershell-strict | opus46-200k-medium | 128.9min | 155 | 134 | $5.44 | 4.0 | powershell | ok |
| Batch File Renamer | powershell-strict | opus46-200k-medium | 76.3min | 163 | 148 | $5.60 | 4.0 | powershell | ok |
| Database Seed Script | powershell | opus46-200k-medium | 14.4min | 167 | 140 | $5.61 | 4.0 | powershell | ok |
| Config File Migrator | powershell-strict | opus46-200k-medium | 16.2min | 154 | 130 | $5.77 | 4.0 | powershell | ok |
| CSV Report Generator | powershell-strict | opus46-200k-medium | 16.2min | 168 | 176 | $5.79 | 4.0 | powershell | ok |
| Dependency License Checker | default | opus46-200k-medium | 17.2min | 217 | 220 | $6.00 | 5.0 | python | ok |
| Process Monitor | csharp-script | opus46-200k-medium | 21.7min | 182 | 188 | $6.00 | 4.0 | csharp | ok |
| Test Results Aggregator | powershell-strict | opus46-200k-medium | 18.6min | 164 | 148 | $6.18 | 4.0 | powershell | ok |
| Secret Rotation Validator | powershell-strict | opus46-200k-medium | 23.4min | 175 | 159 | $6.38 | 5.0 | powershell | ok |
| Environment Matrix Generator | csharp-script | opus46-200k-medium | 21.0min | 175 | 142 | $6.47 | 5.0 | csharp | ok |
| Database Seed Script | powershell-strict | opus46-200k-medium | 19.8min | 162 | 160 | $6.54 | 4.0 | powershell | ok |
| Error Retry Pipeline | csharp-script | opus46-200k-medium | 26.0min | 173 | 194 | $6.97 | 4.0 | csharp | ok |
| REST API Client | csharp-script | opus46-200k-medium | 22.6min | 195 | 177 | $7.32 | 4.0 | csharp | ok |
| PR Label Assigner | csharp-script | opus46-200k-medium | 21.5min | 215 | 203 | $7.33 | 4.0 | csharp | ok |
| Directory Tree Sync | csharp-script | opus46-200k-medium | 202.0min | 229 | 205 | $7.54 | 4.0 | csharp | ok |
| Semantic Version Bumper | powershell-strict | opus46-200k-medium | 18.5min | 225 | 210 | $7.96 | 4.0 | powershell | ok |
| Log File Analyzer | csharp-script | opus46-200k-medium | 168.4min | 221 | 193 | $8.66 | 4.0 | csharp | ok |
| Dependency License Checker | csharp-script | opus46-200k-medium | 21.8min | 223 | 197 | $8.83 | 4.0 | csharp | ok |

</details>

<details>
<summary>Sorted by duration (fastest first)</summary>

| Task | Language | Model | Duration | Turns | Errors | Cost | Tests Quality | Chosen | Status |
|------|----------|-------|----------|-------|--------|------|-----------|--------|--------|
| Dependency License Checker | powershell | sonnet46-200k-medium | 3.0min | 33 | 18 | $0.59 | 4.0 | powershell | ok |
| Artifact Cleanup Script | default | sonnet46-200k-medium | 3.2min | 26 | 15 | $0.49 | 4.0 | python | ok |
| Secret Rotation Validator | default | sonnet46-200k-medium | 3.7min | 23 | 19 | $0.58 | 4.0 | python | ok |
| Docker Image Tag Generator | default | sonnet46-200k-medium | 3.8min | 20 | 17 | $0.50 | 4.0 | python | ok |
| Multi-file Search and Replace | default | sonnet46-200k-medium | 4.5min | 25 | 21 | $0.71 | 4.0 | python | ok |
| Semantic Version Bumper | csharp-script | opus46-200k-medium | 6.2min | 65 | 96 | $1.39 | — | bash | ok |
| Process Monitor | powershell | sonnet46-200k-medium | 6.6min | 53 | 33 | $1.11 | 4.0 | powershell | ok |
| PR Label Assigner | default | sonnet46-200k-medium | 6.7min | 26 | 23 | $0.92 | 4.0 | python | ok |
| Environment Matrix Generator | powershell | sonnet46-200k-medium | 6.7min | 30 | 33 | $0.89 | 4.0 | powershell | ok |
| Secret Rotation Validator | powershell-strict | sonnet46-200k-medium | 7.0min | 13 | 6 | $0.80 | 4.0 | powershell | ok |
| Error Retry Pipeline | powershell-strict | sonnet46-200k-medium | 7.1min | 35 | 17 | $0.92 | 4.0 | powershell | ok |
| Dependency License Checker | default | sonnet46-200k-medium | 7.3min | 52 | 39 | $1.18 | 5.0 | python | ok |
| PR Label Assigner | powershell | sonnet46-200k-medium | 7.8min | 44 | 33 | $1.26 | 4.0 | powershell | ok |
| Error Retry Pipeline | powershell | sonnet46-200k-medium | 8.2min | 42 | 22 | $1.05 | 4.0 | powershell | ok |
| Environment Matrix Generator | default | sonnet46-200k-medium | 8.2min | 52 | 33 | $1.32 | 4.0 | python | ok |
| Secret Rotation Validator | powershell | sonnet46-200k-medium | 8.3min | 61 | 53 | $1.52 | 4.0 | powershell | ok |
| Docker Image Tag Generator | powershell-strict | sonnet46-200k-medium | 8.7min | 59 | 38 | $1.34 | 4.0 | powershell | ok |
| Multi-file Search and Replace | powershell | sonnet46-200k-medium | 8.8min | 49 | 49 | $1.17 | 4.0 | powershell | ok |
| Error Retry Pipeline | default | sonnet46-200k-medium | 8.8min | 69 | 42 | $1.50 | 4.0 | python | ok |
| PR Label Assigner | powershell-strict | sonnet46-200k-medium | 8.9min | 28 | 16 | $1.02 | 4.0 | powershell | ok |
| Artifact Cleanup Script | csharp-script | sonnet46-200k-medium | 9.1min | 39 | 22 | $1.16 | 4.0 | csharp | ok |
| Test Results Aggregator | powershell | sonnet46-200k-medium | 9.6min | 63 | 40 | $1.57 | 4.0 | powershell | ok |
| Process Monitor | default | sonnet46-200k-medium | 9.8min | 76 | 61 | $1.60 | 4.0 | python | ok |
| Process Monitor | default | opus46-200k-medium | 9.8min | 115 | 109 | $2.34 | 4.0 | python | ok |
| PR Label Assigner | powershell | opus46-200k-medium | 10.0min | 93 | 75 | $2.48 | 4.0 | powershell | ok |
| Error Retry Pipeline | csharp-script | sonnet46-200k-medium | 10.1min | 71 | 42 | $1.49 | 4.0 | csharp | ok |
| Test Results Aggregator | powershell | opus46-200k-medium | 10.2min | 89 | 70 | $3.10 | 4.0 | powershell | ok |
| Test Results Aggregator | default | sonnet46-200k-medium | 10.2min | 76 | 59 | $2.01 | 4.0 | python | ok |
| Log File Analyzer | default | sonnet46-200k-medium | 10.6min | 72 | 48 | $1.84 | 3.0 | python | ok |
| Log File Analyzer | powershell | sonnet46-200k-medium | 10.6min | 62 | 51 | $1.78 | 4.0 | powershell | ok |
| REST API Client | default | sonnet46-200k-medium | 10.8min | 54 | 33 | $1.49 | 4.0 | python | ok |
| PR Label Assigner | powershell-strict | opus46-200k-medium | 11.1min | 141 | 130 | $3.72 | 4.0 | powershell | ok |
| Error Retry Pipeline | powershell-strict | opus46-200k-medium | 11.1min | 114 | 103 | $3.17 | 4.0 | powershell | ok |
| Database Seed Script | csharp-script | opus46-200k-medium | 11.4min | 122 | 103 | $3.49 | 4.0 | csharp | ok |
| CSV Report Generator | powershell | opus46-200k-medium | 11.4min | 97 | 89 | $3.05 | 4.0 | powershell | ok |
| Artifact Cleanup Script | powershell | opus46-200k-medium | 11.6min | 91 | 90 | $2.83 | 4.0 | powershell | ok |
| Test Results Aggregator | csharp-script | opus46-200k-medium | 11.7min | 120 | 93 | $3.40 | 4.0 | csharp | ok |
| Semantic Version Bumper | default | opus46-200k-medium | 12.0min | 129 | 115 | $3.34 | 4.0 | python | ok |
| Database Seed Script | powershell | sonnet46-200k-medium | 12.1min | 60 | 36 | $1.67 | 4.0 | powershell | ok |
| Multi-file Search and Replace | powershell-strict | opus46-200k-medium | 12.2min | 129 | 130 | $3.52 | 3.0 | powershell | ok |
| Docker Image Tag Generator | powershell-strict | opus46-200k-medium | 12.2min | 130 | 127 | $3.40 | 4.0 | powershell | ok |
| Secret Rotation Validator | default | opus46-200k-medium | 12.2min | 108 | 88 | $3.43 | 5.0 | python | ok |
| Docker Image Tag Generator | powershell | opus46-200k-medium | 12.4min | 109 | 101 | $3.05 | 5.0 | powershell | ok |
| Config File Migrator | powershell | opus46-200k-medium | 12.6min | 115 | 90 | $3.65 | 4.0 | powershell | ok |
| Batch File Renamer | powershell-strict | sonnet46-200k-medium | 12.6min | 48 | 30 | $1.38 | 5.0 | powershell | ok |
| Semantic Version Bumper | powershell-strict | sonnet46-200k-medium | 12.7min | 60 | 59 | $2.08 | 4.0 | powershell | ok |
| Database Seed Script | powershell-strict | sonnet46-200k-medium | 12.7min | 35 | 17 | $1.65 | 4.0 | powershell | ok |
| Environment Matrix Generator | csharp-script | sonnet46-200k-medium | 12.9min | 85 | 59 | $2.26 | 1.0 | csharp | ok |
| Semantic Version Bumper | default | sonnet46-200k-medium | 12.9min | 98 | 58 | $2.16 | 5.0 | python | ok |
| Artifact Cleanup Script | default | opus46-200k-medium | 12.9min | 110 | 113 | $3.49 | 5.0 | python | ok |
| Test Results Aggregator | csharp-script | sonnet46-200k-medium | 13.0min | 67 | 29 | $2.32 | 4.0 | csharp | ok |
| Artifact Cleanup Script | powershell | sonnet46-200k-medium | 13.0min | 40 | 37 | $1.63 | 4.0 | powershell | ok |
| Database Seed Script | default | opus46-200k-medium | 13.1min | 146 | 141 | $3.83 | 5.0 | python | ok |
| Process Monitor | csharp-script | sonnet46-200k-medium | 13.2min | 61 | 33 | $1.89 | 1.0 | csharp | ok |
| Docker Image Tag Generator | csharp-script | sonnet46-200k-medium | 13.3min | 103 | 88 | $2.28 | 3.0 | csharp | ok |
| Semantic Version Bumper | powershell | opus46-200k-medium | 13.3min | 120 | 100 | $3.84 | 4.0 | powershell | ok |
| Artifact Cleanup Script | powershell-strict | sonnet46-200k-medium | 13.3min | 52 | 35 | $1.83 | 4.0 | powershell | ok |
| REST API Client | powershell-strict | sonnet46-200k-medium | 13.4min | 41 | 27 | $1.82 | 4.0 | powershell | ok |
| Docker Image Tag Generator | powershell | sonnet46-200k-medium | 13.5min | 169 | 143 | $3.46 | 4.0 | powershell | ok |
| Semantic Version Bumper | powershell | sonnet46-200k-medium | 13.7min | 116 | 96 | $2.60 | 4.0 | powershell | ok |
| REST API Client | powershell | sonnet46-200k-medium | 13.9min | 56 | 35 | $1.93 | 4.0 | powershell | ok |
| Process Monitor | powershell-strict | sonnet46-200k-medium | 14.1min | 46 | 39 | $2.11 | 4.0 | powershell | ok |
| Secret Rotation Validator | csharp-script | sonnet46-200k-medium | 14.2min | 74 | 85 | $2.67 | 4.0 | csharp | ok |
| Database Seed Script | powershell | opus46-200k-medium | 14.4min | 167 | 140 | $5.61 | 4.0 | powershell | ok |
| Test Results Aggregator | powershell-strict | sonnet46-200k-medium | 14.6min | 37 | 27 | $1.33 | 4.0 | powershell | ok |
| Process Monitor | powershell | opus46-200k-medium | 14.6min | 96 | 78 | $3.28 | 5.0 | powershell | ok |
| Multi-file Search and Replace | csharp-script | sonnet46-200k-medium | 14.6min | 94 | 66 | $2.39 | 5.0 | csharp | ok |
| Dependency License Checker | powershell-strict | opus46-200k-medium | 14.6min | 87 | 60 | $2.75 | 5.0 | powershell | ok |
| Error Retry Pipeline | powershell | opus46-200k-medium | 14.6min | 80 | 90 | $3.26 | 5.0 | powershell | ok |
| Dependency License Checker | powershell | opus46-200k-medium | 14.9min | 118 | 99 | $4.17 | 4.0 | powershell | ok |
| Environment Matrix Generator | powershell | opus46-200k-medium | 14.9min | 148 | 117 | $4.93 | 4.0 | powershell | ok |
| Process Monitor | powershell-strict | opus46-200k-medium | 15.3min | 126 | 114 | $4.00 | 4.0 | powershell | ok |
| Multi-file Search and Replace | powershell-strict | sonnet46-200k-medium | 15.3min | 69 | 62 | $2.41 | 4.0 | powershell | ok |
| Docker Image Tag Generator | default | opus46-200k-medium | 15.3min | 156 | 162 | $3.82 | 5.0 | python | ok |
| Secret Rotation Validator | powershell | opus46-200k-medium | 15.4min | 136 | 148 | $4.01 | 4.0 | powershell | ok |
| Environment Matrix Generator | default | opus46-200k-medium | 15.5min | 119 | 172 | $3.93 | 5.0 | python | ok |
| Dependency License Checker | powershell-strict | sonnet46-200k-medium | 15.7min | 70 | 57 | $2.20 | 1.0 | powershell | ok |
| Multi-file Search and Replace | default | opus46-200k-medium | 15.9min | 181 | 171 | $4.45 | 4.0 | python | ok |
| PR Label Assigner | default | opus46-200k-medium | 16.1min | 140 | 142 | $3.77 | 5.0 | python | ok |
| CSV Report Generator | powershell-strict | opus46-200k-medium | 16.2min | 168 | 176 | $5.79 | 4.0 | powershell | ok |
| Config File Migrator | powershell-strict | opus46-200k-medium | 16.2min | 154 | 130 | $5.77 | 4.0 | powershell | ok |
| Database Seed Script | default | sonnet46-200k-medium | 16.3min | 42 | 28 | $0.98 | 3.0 | python | ok |
| Docker Image Tag Generator | csharp-script | opus46-200k-medium | 16.6min | 154 | 139 | $4.60 | 4.0 | csharp | ok |
| Artifact Cleanup Script | powershell-strict | opus46-200k-medium | 16.7min | 135 | 132 | $5.03 | 4.0 | powershell | ok |
| Config File Migrator | default | opus46-200k-medium | 16.7min | 165 | 150 | $5.11 | 4.0 | python | ok |
| Environment Matrix Generator | powershell-strict | opus46-200k-medium | 16.8min | 137 | 126 | $4.48 | 4.0 | powershell | ok |
| Test Results Aggregator | default | opus46-200k-medium | 16.9min | 172 | 203 | $4.97 | 4.0 | python | ok |
| Semantic Version Bumper | csharp-script | sonnet46-200k-medium | 17.0min | 64 | 42 | $2.67 | 5.0 | csharp | ok |
| Error Retry Pipeline | default | opus46-200k-medium | 17.1min | 156 | 140 | $3.93 | — |  | ok |
| Multi-file Search and Replace | powershell | opus46-200k-medium | 17.1min | 126 | 124 | $4.56 | 4.0 | powershell | ok |
| Dependency License Checker | default | opus46-200k-medium | 17.2min | 217 | 220 | $6.00 | 5.0 | python | ok |
| Secret Rotation Validator | csharp-script | opus46-200k-medium | 17.2min | 162 | 149 | $5.30 | 5.0 | csharp | ok |
| Multi-file Search and Replace | csharp-script | opus46-200k-medium | 17.3min | 134 | 130 | $4.56 | 4.0 | csharp | ok |
| Artifact Cleanup Script | csharp-script | opus46-200k-medium | 17.9min | 131 | 121 | $4.17 | 4.0 | csharp | ok |
| Semantic Version Bumper | powershell-strict | opus46-200k-medium | 18.5min | 225 | 210 | $7.96 | 4.0 | powershell | ok |
| Test Results Aggregator | powershell-strict | opus46-200k-medium | 18.6min | 164 | 148 | $6.18 | 4.0 | powershell | ok |
| Batch File Renamer | csharp-script | sonnet46-200k-medium | 19.3min | 60 | 121 | $3.76 | 3.0 | csharp | ok |
| Database Seed Script | powershell-strict | opus46-200k-medium | 19.8min | 162 | 160 | $6.54 | 4.0 | powershell | ok |
| PR Label Assigner | csharp-script | sonnet46-200k-medium | 21.0min | 143 | 95 | $4.26 | 3.0 | csharp | ok |
| Environment Matrix Generator | csharp-script | opus46-200k-medium | 21.0min | 175 | 142 | $6.47 | 5.0 | csharp | ok |
| PR Label Assigner | csharp-script | opus46-200k-medium | 21.5min | 215 | 203 | $7.33 | 4.0 | csharp | ok |
| Process Monitor | csharp-script | opus46-200k-medium | 21.7min | 182 | 188 | $6.00 | 4.0 | csharp | ok |
| Dependency License Checker | csharp-script | opus46-200k-medium | 21.8min | 223 | 197 | $8.83 | 4.0 | csharp | ok |
| REST API Client | csharp-script | opus46-200k-medium | 22.6min | 195 | 177 | $7.32 | 4.0 | csharp | ok |
| REST API Client | csharp-script | sonnet46-200k-medium | 23.2min | 74 | 63 | $3.91 | 4.0 | csharp | ok |
| Secret Rotation Validator | powershell-strict | opus46-200k-medium | 23.4min | 175 | 159 | $6.38 | 5.0 | powershell | ok |
| Directory Tree Sync | powershell-strict | sonnet46-200k-medium | 23.7min | 31 | 19 | $0.57 | 4.0 | powershell | ok |
| CSV Report Generator | default | opus46-200k-medium | 23.8min | 222 | 225 | $4.92 | 4.0 | python | ok |
| Log File Analyzer | powershell-strict | sonnet46-200k-medium | 25.2min | 52 | 22 | $1.37 | 4.0 | powershell | ok |
| Log File Analyzer | csharp-script | sonnet46-200k-medium | 25.4min | 131 | 73 | $4.11 | 5.0 | csharp | ok |
| Error Retry Pipeline | csharp-script | opus46-200k-medium | 26.0min | 173 | 194 | $6.97 | 4.0 | csharp | ok |
| Directory Tree Sync | default | sonnet46-200k-medium | 26.1min | 17 | 9 | $0.42 | 5.0 | python | ok |
| Dependency License Checker | csharp-script | sonnet46-200k-medium | 26.6min | 126 | 67 | $3.08 | 4.0 | csharp | ok |
| Database Seed Script | csharp-script | sonnet46-200k-medium | 28.1min | 0 | 0 | $0.00 | 5.0 | csharp | failed |
| Environment Matrix Generator | powershell-strict | sonnet46-200k-medium | 30.0min | 0 | 0 | $0.00 | 4.0 | powershell | failed |
| Batch File Renamer | default | opus46-200k-medium | 33.9min | 106 | 109 | $2.76 | 4.0 | python | ok |
| Batch File Renamer | csharp-script | opus46-200k-medium | 40.4min | 108 | 134 | $3.34 | 4.0 | csharp | ok |
| Directory Tree Sync | default | opus46-200k-medium | 44.4min | 122 | 107 | $3.24 | 4.0 | python | ok |
| Config File Migrator | powershell-strict | sonnet46-200k-medium | 44.9min | 69 | 40 | $1.84 | 3.0 | powershell | ok |
| Batch File Renamer | default | sonnet46-200k-medium | 46.7min | 58 | 44 | $1.27 | 5.0 | python | ok |
| Config File Migrator | powershell | sonnet46-200k-medium | 52.0min | 81 | 60 | $2.57 | 4.0 | powershell | ok |
| CSV Report Generator | default | sonnet46-200k-medium | 53.2min | 37 | 25 | $0.65 | 4.0 | python | ok |
| Config File Migrator | csharp-script | opus46-200k-medium | 54.2min | 0 | 0 | $0.00 | 4.0 | csharp | failed |
| CSV Report Generator | powershell | sonnet46-200k-medium | 56.1min | 52 | 27 | $0.97 | 4.0 | powershell | ok |
| Config File Migrator | default | sonnet46-200k-medium | 58.5min | 102 | 65 | $2.44 | 4.0 | python | ok |
| Batch File Renamer | powershell | opus46-200k-medium | 67.4min | 104 | 117 | $3.32 | 4.0 | powershell | ok |
| Directory Tree Sync | powershell | sonnet46-200k-medium | 69.6min | 60 | 41 | $1.54 | 4.0 | powershell | ok |
| Config File Migrator | csharp-script | sonnet46-200k-medium | 73.6min | 138 | 58 | $5.32 | 1.0 | csharp | ok |
| Batch File Renamer | powershell-strict | opus46-200k-medium | 76.3min | 163 | 148 | $5.60 | 4.0 | powershell | ok |
| Log File Analyzer | default | opus46-200k-medium | 105.3min | 195 | 205 | $5.43 | — | javascript | ok |
| Directory Tree Sync | powershell | opus46-200k-medium | 112.3min | 93 | 91 | $2.97 | 4.0 | powershell | ok |
| CSV Report Generator | csharp-script | sonnet46-200k-medium | 112.8min | 48 | 26 | $1.13 | 4.0 | csharp | ok |
| CSV Report Generator | powershell-strict | sonnet46-200k-medium | 121.6min | 74 | 41 | $1.75 | 4.0 | powershell | ok |
| Log File Analyzer | powershell-strict | opus46-200k-medium | 128.9min | 155 | 134 | $5.44 | 4.0 | powershell | ok |
| Directory Tree Sync | csharp-script | sonnet46-200k-medium | 143.8min | 83 | 49 | $2.42 | 5.0 | csharp | ok |
| Log File Analyzer | powershell | opus46-200k-medium | 143.9min | 123 | 105 | $3.88 | 4.0 | powershell | ok |
| Directory Tree Sync | powershell-strict | opus46-200k-medium | 144.7min | 140 | 140 | $4.71 | 4.0 | powershell | ok |
| REST API Client | default | opus46-200k-medium | 157.1min | 113 | 118 | $3.08 | 4.0 | python | ok |
| Log File Analyzer | csharp-script | opus46-200k-medium | 168.4min | 221 | 193 | $8.66 | 4.0 | csharp | ok |
| Directory Tree Sync | csharp-script | opus46-200k-medium | 202.0min | 229 | 205 | $7.54 | 4.0 | csharp | ok |
| Batch File Renamer | powershell | sonnet46-200k-medium | 246.7min | 67 | 37 | $2.07 | 4.0 | powershell | ok |
| REST API Client | powershell | opus46-200k-medium | 257.5min | 0 | 0 | $0.00 | 4.0 | powershell | failed |
| CSV Report Generator | csharp-script | opus46-200k-medium | 271.2min | 0 | 0 | $0.00 | 2.0 | csharp | failed |
| REST API Client | powershell-strict | opus46-200k-medium | 378.5min | 101 | 87 | $4.06 | 4.0 | powershell | ok |

</details>

<details>
<summary>Sorted by errors (fewest first)</summary>

| Task | Language | Model | Duration | Turns | Errors | Cost | Tests Quality | Chosen | Status |
|------|----------|-------|----------|-------|--------|------|-----------|--------|--------|
| CSV Report Generator | csharp-script | opus46-200k-medium | 271.2min | 0 | 0 | $0.00 | 2.0 | csharp | failed |
| REST API Client | powershell | opus46-200k-medium | 257.5min | 0 | 0 | $0.00 | 4.0 | powershell | failed |
| Config File Migrator | csharp-script | opus46-200k-medium | 54.2min | 0 | 0 | $0.00 | 4.0 | csharp | failed |
| Database Seed Script | csharp-script | sonnet46-200k-medium | 28.1min | 0 | 0 | $0.00 | 5.0 | csharp | failed |
| Environment Matrix Generator | powershell-strict | sonnet46-200k-medium | 30.0min | 0 | 0 | $0.00 | 4.0 | powershell | failed |
| Secret Rotation Validator | powershell-strict | sonnet46-200k-medium | 7.0min | 13 | 6 | $0.80 | 4.0 | powershell | ok |
| Directory Tree Sync | default | sonnet46-200k-medium | 26.1min | 17 | 9 | $0.42 | 5.0 | python | ok |
| Artifact Cleanup Script | default | sonnet46-200k-medium | 3.2min | 26 | 15 | $0.49 | 4.0 | python | ok |
| PR Label Assigner | powershell-strict | sonnet46-200k-medium | 8.9min | 28 | 16 | $1.02 | 4.0 | powershell | ok |
| Database Seed Script | powershell-strict | sonnet46-200k-medium | 12.7min | 35 | 17 | $1.65 | 4.0 | powershell | ok |
| Error Retry Pipeline | powershell-strict | sonnet46-200k-medium | 7.1min | 35 | 17 | $0.92 | 4.0 | powershell | ok |
| Docker Image Tag Generator | default | sonnet46-200k-medium | 3.8min | 20 | 17 | $0.50 | 4.0 | python | ok |
| Dependency License Checker | powershell | sonnet46-200k-medium | 3.0min | 33 | 18 | $0.59 | 4.0 | powershell | ok |
| Directory Tree Sync | powershell-strict | sonnet46-200k-medium | 23.7min | 31 | 19 | $0.57 | 4.0 | powershell | ok |
| Secret Rotation Validator | default | sonnet46-200k-medium | 3.7min | 23 | 19 | $0.58 | 4.0 | python | ok |
| Multi-file Search and Replace | default | sonnet46-200k-medium | 4.5min | 25 | 21 | $0.71 | 4.0 | python | ok |
| Log File Analyzer | powershell-strict | sonnet46-200k-medium | 25.2min | 52 | 22 | $1.37 | 4.0 | powershell | ok |
| Error Retry Pipeline | powershell | sonnet46-200k-medium | 8.2min | 42 | 22 | $1.05 | 4.0 | powershell | ok |
| Artifact Cleanup Script | csharp-script | sonnet46-200k-medium | 9.1min | 39 | 22 | $1.16 | 4.0 | csharp | ok |
| PR Label Assigner | default | sonnet46-200k-medium | 6.7min | 26 | 23 | $0.92 | 4.0 | python | ok |
| CSV Report Generator | default | sonnet46-200k-medium | 53.2min | 37 | 25 | $0.65 | 4.0 | python | ok |
| CSV Report Generator | csharp-script | sonnet46-200k-medium | 112.8min | 48 | 26 | $1.13 | 4.0 | csharp | ok |
| CSV Report Generator | powershell | sonnet46-200k-medium | 56.1min | 52 | 27 | $0.97 | 4.0 | powershell | ok |
| REST API Client | powershell-strict | sonnet46-200k-medium | 13.4min | 41 | 27 | $1.82 | 4.0 | powershell | ok |
| Test Results Aggregator | powershell-strict | sonnet46-200k-medium | 14.6min | 37 | 27 | $1.33 | 4.0 | powershell | ok |
| Database Seed Script | default | sonnet46-200k-medium | 16.3min | 42 | 28 | $0.98 | 3.0 | python | ok |
| Test Results Aggregator | csharp-script | sonnet46-200k-medium | 13.0min | 67 | 29 | $2.32 | 4.0 | csharp | ok |
| Batch File Renamer | powershell-strict | sonnet46-200k-medium | 12.6min | 48 | 30 | $1.38 | 5.0 | powershell | ok |
| REST API Client | default | sonnet46-200k-medium | 10.8min | 54 | 33 | $1.49 | 4.0 | python | ok |
| Process Monitor | csharp-script | sonnet46-200k-medium | 13.2min | 61 | 33 | $1.89 | 1.0 | csharp | ok |
| Process Monitor | powershell | sonnet46-200k-medium | 6.6min | 53 | 33 | $1.11 | 4.0 | powershell | ok |
| PR Label Assigner | powershell | sonnet46-200k-medium | 7.8min | 44 | 33 | $1.26 | 4.0 | powershell | ok |
| Environment Matrix Generator | default | sonnet46-200k-medium | 8.2min | 52 | 33 | $1.32 | 4.0 | python | ok |
| Environment Matrix Generator | powershell | sonnet46-200k-medium | 6.7min | 30 | 33 | $0.89 | 4.0 | powershell | ok |
| REST API Client | powershell | sonnet46-200k-medium | 13.9min | 56 | 35 | $1.93 | 4.0 | powershell | ok |
| Artifact Cleanup Script | powershell-strict | sonnet46-200k-medium | 13.3min | 52 | 35 | $1.83 | 4.0 | powershell | ok |
| Database Seed Script | powershell | sonnet46-200k-medium | 12.1min | 60 | 36 | $1.67 | 4.0 | powershell | ok |
| Batch File Renamer | powershell | sonnet46-200k-medium | 246.7min | 67 | 37 | $2.07 | 4.0 | powershell | ok |
| Artifact Cleanup Script | powershell | sonnet46-200k-medium | 13.0min | 40 | 37 | $1.63 | 4.0 | powershell | ok |
| Docker Image Tag Generator | powershell-strict | sonnet46-200k-medium | 8.7min | 59 | 38 | $1.34 | 4.0 | powershell | ok |
| Process Monitor | powershell-strict | sonnet46-200k-medium | 14.1min | 46 | 39 | $2.11 | 4.0 | powershell | ok |
| Dependency License Checker | default | sonnet46-200k-medium | 7.3min | 52 | 39 | $1.18 | 5.0 | python | ok |
| Config File Migrator | powershell-strict | sonnet46-200k-medium | 44.9min | 69 | 40 | $1.84 | 3.0 | powershell | ok |
| Test Results Aggregator | powershell | sonnet46-200k-medium | 9.6min | 63 | 40 | $1.57 | 4.0 | powershell | ok |
| CSV Report Generator | powershell-strict | sonnet46-200k-medium | 121.6min | 74 | 41 | $1.75 | 4.0 | powershell | ok |
| Directory Tree Sync | powershell | sonnet46-200k-medium | 69.6min | 60 | 41 | $1.54 | 4.0 | powershell | ok |
| Error Retry Pipeline | csharp-script | sonnet46-200k-medium | 10.1min | 71 | 42 | $1.49 | 4.0 | csharp | ok |
| Error Retry Pipeline | default | sonnet46-200k-medium | 8.8min | 69 | 42 | $1.50 | 4.0 | python | ok |
| Semantic Version Bumper | csharp-script | sonnet46-200k-medium | 17.0min | 64 | 42 | $2.67 | 5.0 | csharp | ok |
| Batch File Renamer | default | sonnet46-200k-medium | 46.7min | 58 | 44 | $1.27 | 5.0 | python | ok |
| Log File Analyzer | default | sonnet46-200k-medium | 10.6min | 72 | 48 | $1.84 | 3.0 | python | ok |
| Directory Tree Sync | csharp-script | sonnet46-200k-medium | 143.8min | 83 | 49 | $2.42 | 5.0 | csharp | ok |
| Multi-file Search and Replace | powershell | sonnet46-200k-medium | 8.8min | 49 | 49 | $1.17 | 4.0 | powershell | ok |
| Log File Analyzer | powershell | sonnet46-200k-medium | 10.6min | 62 | 51 | $1.78 | 4.0 | powershell | ok |
| Secret Rotation Validator | powershell | sonnet46-200k-medium | 8.3min | 61 | 53 | $1.52 | 4.0 | powershell | ok |
| Dependency License Checker | powershell-strict | sonnet46-200k-medium | 15.7min | 70 | 57 | $2.20 | 1.0 | powershell | ok |
| Config File Migrator | csharp-script | sonnet46-200k-medium | 73.6min | 138 | 58 | $5.32 | 1.0 | csharp | ok |
| Semantic Version Bumper | default | sonnet46-200k-medium | 12.9min | 98 | 58 | $2.16 | 5.0 | python | ok |
| Semantic Version Bumper | powershell-strict | sonnet46-200k-medium | 12.7min | 60 | 59 | $2.08 | 4.0 | powershell | ok |
| Test Results Aggregator | default | sonnet46-200k-medium | 10.2min | 76 | 59 | $2.01 | 4.0 | python | ok |
| Environment Matrix Generator | csharp-script | sonnet46-200k-medium | 12.9min | 85 | 59 | $2.26 | 1.0 | csharp | ok |
| Config File Migrator | powershell | sonnet46-200k-medium | 52.0min | 81 | 60 | $2.57 | 4.0 | powershell | ok |
| Dependency License Checker | powershell-strict | opus46-200k-medium | 14.6min | 87 | 60 | $2.75 | 5.0 | powershell | ok |
| Process Monitor | default | sonnet46-200k-medium | 9.8min | 76 | 61 | $1.60 | 4.0 | python | ok |
| Multi-file Search and Replace | powershell-strict | sonnet46-200k-medium | 15.3min | 69 | 62 | $2.41 | 4.0 | powershell | ok |
| REST API Client | csharp-script | sonnet46-200k-medium | 23.2min | 74 | 63 | $3.91 | 4.0 | csharp | ok |
| Config File Migrator | default | sonnet46-200k-medium | 58.5min | 102 | 65 | $2.44 | 4.0 | python | ok |
| Multi-file Search and Replace | csharp-script | sonnet46-200k-medium | 14.6min | 94 | 66 | $2.39 | 5.0 | csharp | ok |
| Dependency License Checker | csharp-script | sonnet46-200k-medium | 26.6min | 126 | 67 | $3.08 | 4.0 | csharp | ok |
| Test Results Aggregator | powershell | opus46-200k-medium | 10.2min | 89 | 70 | $3.10 | 4.0 | powershell | ok |
| Log File Analyzer | csharp-script | sonnet46-200k-medium | 25.4min | 131 | 73 | $4.11 | 5.0 | csharp | ok |
| PR Label Assigner | powershell | opus46-200k-medium | 10.0min | 93 | 75 | $2.48 | 4.0 | powershell | ok |
| Process Monitor | powershell | opus46-200k-medium | 14.6min | 96 | 78 | $3.28 | 5.0 | powershell | ok |
| Secret Rotation Validator | csharp-script | sonnet46-200k-medium | 14.2min | 74 | 85 | $2.67 | 4.0 | csharp | ok |
| REST API Client | powershell-strict | opus46-200k-medium | 378.5min | 101 | 87 | $4.06 | 4.0 | powershell | ok |
| Docker Image Tag Generator | csharp-script | sonnet46-200k-medium | 13.3min | 103 | 88 | $2.28 | 3.0 | csharp | ok |
| Secret Rotation Validator | default | opus46-200k-medium | 12.2min | 108 | 88 | $3.43 | 5.0 | python | ok |
| CSV Report Generator | powershell | opus46-200k-medium | 11.4min | 97 | 89 | $3.05 | 4.0 | powershell | ok |
| Config File Migrator | powershell | opus46-200k-medium | 12.6min | 115 | 90 | $3.65 | 4.0 | powershell | ok |
| Error Retry Pipeline | powershell | opus46-200k-medium | 14.6min | 80 | 90 | $3.26 | 5.0 | powershell | ok |
| Artifact Cleanup Script | powershell | opus46-200k-medium | 11.6min | 91 | 90 | $2.83 | 4.0 | powershell | ok |
| Directory Tree Sync | powershell | opus46-200k-medium | 112.3min | 93 | 91 | $2.97 | 4.0 | powershell | ok |
| Test Results Aggregator | csharp-script | opus46-200k-medium | 11.7min | 120 | 93 | $3.40 | 4.0 | csharp | ok |
| PR Label Assigner | csharp-script | sonnet46-200k-medium | 21.0min | 143 | 95 | $4.26 | 3.0 | csharp | ok |
| Semantic Version Bumper | csharp-script | opus46-200k-medium | 6.2min | 65 | 96 | $1.39 | — | bash | ok |
| Semantic Version Bumper | powershell | sonnet46-200k-medium | 13.7min | 116 | 96 | $2.60 | 4.0 | powershell | ok |
| Dependency License Checker | powershell | opus46-200k-medium | 14.9min | 118 | 99 | $4.17 | 4.0 | powershell | ok |
| Semantic Version Bumper | powershell | opus46-200k-medium | 13.3min | 120 | 100 | $3.84 | 4.0 | powershell | ok |
| Docker Image Tag Generator | powershell | opus46-200k-medium | 12.4min | 109 | 101 | $3.05 | 5.0 | powershell | ok |
| Database Seed Script | csharp-script | opus46-200k-medium | 11.4min | 122 | 103 | $3.49 | 4.0 | csharp | ok |
| Error Retry Pipeline | powershell-strict | opus46-200k-medium | 11.1min | 114 | 103 | $3.17 | 4.0 | powershell | ok |
| Log File Analyzer | powershell | opus46-200k-medium | 143.9min | 123 | 105 | $3.88 | 4.0 | powershell | ok |
| Directory Tree Sync | default | opus46-200k-medium | 44.4min | 122 | 107 | $3.24 | 4.0 | python | ok |
| Process Monitor | default | opus46-200k-medium | 9.8min | 115 | 109 | $2.34 | 4.0 | python | ok |
| Batch File Renamer | default | opus46-200k-medium | 33.9min | 106 | 109 | $2.76 | 4.0 | python | ok |
| Artifact Cleanup Script | default | opus46-200k-medium | 12.9min | 110 | 113 | $3.49 | 5.0 | python | ok |
| Process Monitor | powershell-strict | opus46-200k-medium | 15.3min | 126 | 114 | $4.00 | 4.0 | powershell | ok |
| Semantic Version Bumper | default | opus46-200k-medium | 12.0min | 129 | 115 | $3.34 | 4.0 | python | ok |
| Batch File Renamer | powershell | opus46-200k-medium | 67.4min | 104 | 117 | $3.32 | 4.0 | powershell | ok |
| Environment Matrix Generator | powershell | opus46-200k-medium | 14.9min | 148 | 117 | $4.93 | 4.0 | powershell | ok |
| REST API Client | default | opus46-200k-medium | 157.1min | 113 | 118 | $3.08 | 4.0 | python | ok |
| Batch File Renamer | csharp-script | sonnet46-200k-medium | 19.3min | 60 | 121 | $3.76 | 3.0 | csharp | ok |
| Artifact Cleanup Script | csharp-script | opus46-200k-medium | 17.9min | 131 | 121 | $4.17 | 4.0 | csharp | ok |
| Multi-file Search and Replace | powershell | opus46-200k-medium | 17.1min | 126 | 124 | $4.56 | 4.0 | powershell | ok |
| Environment Matrix Generator | powershell-strict | opus46-200k-medium | 16.8min | 137 | 126 | $4.48 | 4.0 | powershell | ok |
| Docker Image Tag Generator | powershell-strict | opus46-200k-medium | 12.2min | 130 | 127 | $3.40 | 4.0 | powershell | ok |
| Config File Migrator | powershell-strict | opus46-200k-medium | 16.2min | 154 | 130 | $5.77 | 4.0 | powershell | ok |
| Multi-file Search and Replace | csharp-script | opus46-200k-medium | 17.3min | 134 | 130 | $4.56 | 4.0 | csharp | ok |
| Multi-file Search and Replace | powershell-strict | opus46-200k-medium | 12.2min | 129 | 130 | $3.52 | 3.0 | powershell | ok |
| PR Label Assigner | powershell-strict | opus46-200k-medium | 11.1min | 141 | 130 | $3.72 | 4.0 | powershell | ok |
| Artifact Cleanup Script | powershell-strict | opus46-200k-medium | 16.7min | 135 | 132 | $5.03 | 4.0 | powershell | ok |
| Log File Analyzer | powershell-strict | opus46-200k-medium | 128.9min | 155 | 134 | $5.44 | 4.0 | powershell | ok |
| Batch File Renamer | csharp-script | opus46-200k-medium | 40.4min | 108 | 134 | $3.34 | 4.0 | csharp | ok |
| Docker Image Tag Generator | csharp-script | opus46-200k-medium | 16.6min | 154 | 139 | $4.60 | 4.0 | csharp | ok |
| Directory Tree Sync | powershell-strict | opus46-200k-medium | 144.7min | 140 | 140 | $4.71 | 4.0 | powershell | ok |
| Database Seed Script | powershell | opus46-200k-medium | 14.4min | 167 | 140 | $5.61 | 4.0 | powershell | ok |
| Error Retry Pipeline | default | opus46-200k-medium | 17.1min | 156 | 140 | $3.93 | — |  | ok |
| Database Seed Script | default | opus46-200k-medium | 13.1min | 146 | 141 | $3.83 | 5.0 | python | ok |
| PR Label Assigner | default | opus46-200k-medium | 16.1min | 140 | 142 | $3.77 | 5.0 | python | ok |
| Environment Matrix Generator | csharp-script | opus46-200k-medium | 21.0min | 175 | 142 | $6.47 | 5.0 | csharp | ok |
| Docker Image Tag Generator | powershell | sonnet46-200k-medium | 13.5min | 169 | 143 | $3.46 | 4.0 | powershell | ok |
| Batch File Renamer | powershell-strict | opus46-200k-medium | 76.3min | 163 | 148 | $5.60 | 4.0 | powershell | ok |
| Test Results Aggregator | powershell-strict | opus46-200k-medium | 18.6min | 164 | 148 | $6.18 | 4.0 | powershell | ok |
| Secret Rotation Validator | powershell | opus46-200k-medium | 15.4min | 136 | 148 | $4.01 | 4.0 | powershell | ok |
| Secret Rotation Validator | csharp-script | opus46-200k-medium | 17.2min | 162 | 149 | $5.30 | 5.0 | csharp | ok |
| Config File Migrator | default | opus46-200k-medium | 16.7min | 165 | 150 | $5.11 | 4.0 | python | ok |
| Secret Rotation Validator | powershell-strict | opus46-200k-medium | 23.4min | 175 | 159 | $6.38 | 5.0 | powershell | ok |
| Database Seed Script | powershell-strict | opus46-200k-medium | 19.8min | 162 | 160 | $6.54 | 4.0 | powershell | ok |
| Docker Image Tag Generator | default | opus46-200k-medium | 15.3min | 156 | 162 | $3.82 | 5.0 | python | ok |
| Multi-file Search and Replace | default | opus46-200k-medium | 15.9min | 181 | 171 | $4.45 | 4.0 | python | ok |
| Environment Matrix Generator | default | opus46-200k-medium | 15.5min | 119 | 172 | $3.93 | 5.0 | python | ok |
| CSV Report Generator | powershell-strict | opus46-200k-medium | 16.2min | 168 | 176 | $5.79 | 4.0 | powershell | ok |
| REST API Client | csharp-script | opus46-200k-medium | 22.6min | 195 | 177 | $7.32 | 4.0 | csharp | ok |
| Process Monitor | csharp-script | opus46-200k-medium | 21.7min | 182 | 188 | $6.00 | 4.0 | csharp | ok |
| Log File Analyzer | csharp-script | opus46-200k-medium | 168.4min | 221 | 193 | $8.66 | 4.0 | csharp | ok |
| Error Retry Pipeline | csharp-script | opus46-200k-medium | 26.0min | 173 | 194 | $6.97 | 4.0 | csharp | ok |
| Dependency License Checker | csharp-script | opus46-200k-medium | 21.8min | 223 | 197 | $8.83 | 4.0 | csharp | ok |
| PR Label Assigner | csharp-script | opus46-200k-medium | 21.5min | 215 | 203 | $7.33 | 4.0 | csharp | ok |
| Test Results Aggregator | default | opus46-200k-medium | 16.9min | 172 | 203 | $4.97 | 4.0 | python | ok |
| Log File Analyzer | default | opus46-200k-medium | 105.3min | 195 | 205 | $5.43 | — | javascript | ok |
| Directory Tree Sync | csharp-script | opus46-200k-medium | 202.0min | 229 | 205 | $7.54 | 4.0 | csharp | ok |
| Semantic Version Bumper | powershell-strict | opus46-200k-medium | 18.5min | 225 | 210 | $7.96 | 4.0 | powershell | ok |
| Dependency License Checker | default | opus46-200k-medium | 17.2min | 217 | 220 | $6.00 | 5.0 | python | ok |
| CSV Report Generator | default | opus46-200k-medium | 23.8min | 222 | 225 | $4.92 | 4.0 | python | ok |

</details>

<details>
<summary>Sorted by turns (fewest first)</summary>

| Task | Language | Model | Duration | Turns | Errors | Cost | Tests Quality | Chosen | Status |
|------|----------|-------|----------|-------|--------|------|-----------|--------|--------|
| CSV Report Generator | csharp-script | opus46-200k-medium | 271.2min | 0 | 0 | $0.00 | 2.0 | csharp | failed |
| REST API Client | powershell | opus46-200k-medium | 257.5min | 0 | 0 | $0.00 | 4.0 | powershell | failed |
| Config File Migrator | csharp-script | opus46-200k-medium | 54.2min | 0 | 0 | $0.00 | 4.0 | csharp | failed |
| Database Seed Script | csharp-script | sonnet46-200k-medium | 28.1min | 0 | 0 | $0.00 | 5.0 | csharp | failed |
| Environment Matrix Generator | powershell-strict | sonnet46-200k-medium | 30.0min | 0 | 0 | $0.00 | 4.0 | powershell | failed |
| Secret Rotation Validator | powershell-strict | sonnet46-200k-medium | 7.0min | 13 | 6 | $0.80 | 4.0 | powershell | ok |
| Directory Tree Sync | default | sonnet46-200k-medium | 26.1min | 17 | 9 | $0.42 | 5.0 | python | ok |
| Docker Image Tag Generator | default | sonnet46-200k-medium | 3.8min | 20 | 17 | $0.50 | 4.0 | python | ok |
| Secret Rotation Validator | default | sonnet46-200k-medium | 3.7min | 23 | 19 | $0.58 | 4.0 | python | ok |
| Multi-file Search and Replace | default | sonnet46-200k-medium | 4.5min | 25 | 21 | $0.71 | 4.0 | python | ok |
| PR Label Assigner | default | sonnet46-200k-medium | 6.7min | 26 | 23 | $0.92 | 4.0 | python | ok |
| Artifact Cleanup Script | default | sonnet46-200k-medium | 3.2min | 26 | 15 | $0.49 | 4.0 | python | ok |
| PR Label Assigner | powershell-strict | sonnet46-200k-medium | 8.9min | 28 | 16 | $1.02 | 4.0 | powershell | ok |
| Environment Matrix Generator | powershell | sonnet46-200k-medium | 6.7min | 30 | 33 | $0.89 | 4.0 | powershell | ok |
| Directory Tree Sync | powershell-strict | sonnet46-200k-medium | 23.7min | 31 | 19 | $0.57 | 4.0 | powershell | ok |
| Dependency License Checker | powershell | sonnet46-200k-medium | 3.0min | 33 | 18 | $0.59 | 4.0 | powershell | ok |
| Database Seed Script | powershell-strict | sonnet46-200k-medium | 12.7min | 35 | 17 | $1.65 | 4.0 | powershell | ok |
| Error Retry Pipeline | powershell-strict | sonnet46-200k-medium | 7.1min | 35 | 17 | $0.92 | 4.0 | powershell | ok |
| CSV Report Generator | default | sonnet46-200k-medium | 53.2min | 37 | 25 | $0.65 | 4.0 | python | ok |
| Test Results Aggregator | powershell-strict | sonnet46-200k-medium | 14.6min | 37 | 27 | $1.33 | 4.0 | powershell | ok |
| Artifact Cleanup Script | csharp-script | sonnet46-200k-medium | 9.1min | 39 | 22 | $1.16 | 4.0 | csharp | ok |
| Artifact Cleanup Script | powershell | sonnet46-200k-medium | 13.0min | 40 | 37 | $1.63 | 4.0 | powershell | ok |
| REST API Client | powershell-strict | sonnet46-200k-medium | 13.4min | 41 | 27 | $1.82 | 4.0 | powershell | ok |
| Database Seed Script | default | sonnet46-200k-medium | 16.3min | 42 | 28 | $0.98 | 3.0 | python | ok |
| Error Retry Pipeline | powershell | sonnet46-200k-medium | 8.2min | 42 | 22 | $1.05 | 4.0 | powershell | ok |
| PR Label Assigner | powershell | sonnet46-200k-medium | 7.8min | 44 | 33 | $1.26 | 4.0 | powershell | ok |
| Process Monitor | powershell-strict | sonnet46-200k-medium | 14.1min | 46 | 39 | $2.11 | 4.0 | powershell | ok |
| CSV Report Generator | csharp-script | sonnet46-200k-medium | 112.8min | 48 | 26 | $1.13 | 4.0 | csharp | ok |
| Batch File Renamer | powershell-strict | sonnet46-200k-medium | 12.6min | 48 | 30 | $1.38 | 5.0 | powershell | ok |
| Multi-file Search and Replace | powershell | sonnet46-200k-medium | 8.8min | 49 | 49 | $1.17 | 4.0 | powershell | ok |
| CSV Report Generator | powershell | sonnet46-200k-medium | 56.1min | 52 | 27 | $0.97 | 4.0 | powershell | ok |
| Log File Analyzer | powershell-strict | sonnet46-200k-medium | 25.2min | 52 | 22 | $1.37 | 4.0 | powershell | ok |
| Dependency License Checker | default | sonnet46-200k-medium | 7.3min | 52 | 39 | $1.18 | 5.0 | python | ok |
| Environment Matrix Generator | default | sonnet46-200k-medium | 8.2min | 52 | 33 | $1.32 | 4.0 | python | ok |
| Artifact Cleanup Script | powershell-strict | sonnet46-200k-medium | 13.3min | 52 | 35 | $1.83 | 4.0 | powershell | ok |
| Process Monitor | powershell | sonnet46-200k-medium | 6.6min | 53 | 33 | $1.11 | 4.0 | powershell | ok |
| REST API Client | default | sonnet46-200k-medium | 10.8min | 54 | 33 | $1.49 | 4.0 | python | ok |
| REST API Client | powershell | sonnet46-200k-medium | 13.9min | 56 | 35 | $1.93 | 4.0 | powershell | ok |
| Batch File Renamer | default | sonnet46-200k-medium | 46.7min | 58 | 44 | $1.27 | 5.0 | python | ok |
| Docker Image Tag Generator | powershell-strict | sonnet46-200k-medium | 8.7min | 59 | 38 | $1.34 | 4.0 | powershell | ok |
| Directory Tree Sync | powershell | sonnet46-200k-medium | 69.6min | 60 | 41 | $1.54 | 4.0 | powershell | ok |
| Batch File Renamer | csharp-script | sonnet46-200k-medium | 19.3min | 60 | 121 | $3.76 | 3.0 | csharp | ok |
| Database Seed Script | powershell | sonnet46-200k-medium | 12.1min | 60 | 36 | $1.67 | 4.0 | powershell | ok |
| Semantic Version Bumper | powershell-strict | sonnet46-200k-medium | 12.7min | 60 | 59 | $2.08 | 4.0 | powershell | ok |
| Process Monitor | csharp-script | sonnet46-200k-medium | 13.2min | 61 | 33 | $1.89 | 1.0 | csharp | ok |
| Secret Rotation Validator | powershell | sonnet46-200k-medium | 8.3min | 61 | 53 | $1.52 | 4.0 | powershell | ok |
| Log File Analyzer | powershell | sonnet46-200k-medium | 10.6min | 62 | 51 | $1.78 | 4.0 | powershell | ok |
| Test Results Aggregator | powershell | sonnet46-200k-medium | 9.6min | 63 | 40 | $1.57 | 4.0 | powershell | ok |
| Semantic Version Bumper | csharp-script | sonnet46-200k-medium | 17.0min | 64 | 42 | $2.67 | 5.0 | csharp | ok |
| Semantic Version Bumper | csharp-script | opus46-200k-medium | 6.2min | 65 | 96 | $1.39 | — | bash | ok |
| Batch File Renamer | powershell | sonnet46-200k-medium | 246.7min | 67 | 37 | $2.07 | 4.0 | powershell | ok |
| Test Results Aggregator | csharp-script | sonnet46-200k-medium | 13.0min | 67 | 29 | $2.32 | 4.0 | csharp | ok |
| Config File Migrator | powershell-strict | sonnet46-200k-medium | 44.9min | 69 | 40 | $1.84 | 3.0 | powershell | ok |
| Error Retry Pipeline | default | sonnet46-200k-medium | 8.8min | 69 | 42 | $1.50 | 4.0 | python | ok |
| Multi-file Search and Replace | powershell-strict | sonnet46-200k-medium | 15.3min | 69 | 62 | $2.41 | 4.0 | powershell | ok |
| Dependency License Checker | powershell-strict | sonnet46-200k-medium | 15.7min | 70 | 57 | $2.20 | 1.0 | powershell | ok |
| Error Retry Pipeline | csharp-script | sonnet46-200k-medium | 10.1min | 71 | 42 | $1.49 | 4.0 | csharp | ok |
| Log File Analyzer | default | sonnet46-200k-medium | 10.6min | 72 | 48 | $1.84 | 3.0 | python | ok |
| CSV Report Generator | powershell-strict | sonnet46-200k-medium | 121.6min | 74 | 41 | $1.75 | 4.0 | powershell | ok |
| REST API Client | csharp-script | sonnet46-200k-medium | 23.2min | 74 | 63 | $3.91 | 4.0 | csharp | ok |
| Secret Rotation Validator | csharp-script | sonnet46-200k-medium | 14.2min | 74 | 85 | $2.67 | 4.0 | csharp | ok |
| Process Monitor | default | sonnet46-200k-medium | 9.8min | 76 | 61 | $1.60 | 4.0 | python | ok |
| Test Results Aggregator | default | sonnet46-200k-medium | 10.2min | 76 | 59 | $2.01 | 4.0 | python | ok |
| Error Retry Pipeline | powershell | opus46-200k-medium | 14.6min | 80 | 90 | $3.26 | 5.0 | powershell | ok |
| Config File Migrator | powershell | sonnet46-200k-medium | 52.0min | 81 | 60 | $2.57 | 4.0 | powershell | ok |
| Directory Tree Sync | csharp-script | sonnet46-200k-medium | 143.8min | 83 | 49 | $2.42 | 5.0 | csharp | ok |
| Environment Matrix Generator | csharp-script | sonnet46-200k-medium | 12.9min | 85 | 59 | $2.26 | 1.0 | csharp | ok |
| Dependency License Checker | powershell-strict | opus46-200k-medium | 14.6min | 87 | 60 | $2.75 | 5.0 | powershell | ok |
| Test Results Aggregator | powershell | opus46-200k-medium | 10.2min | 89 | 70 | $3.10 | 4.0 | powershell | ok |
| Artifact Cleanup Script | powershell | opus46-200k-medium | 11.6min | 91 | 90 | $2.83 | 4.0 | powershell | ok |
| Directory Tree Sync | powershell | opus46-200k-medium | 112.3min | 93 | 91 | $2.97 | 4.0 | powershell | ok |
| PR Label Assigner | powershell | opus46-200k-medium | 10.0min | 93 | 75 | $2.48 | 4.0 | powershell | ok |
| Multi-file Search and Replace | csharp-script | sonnet46-200k-medium | 14.6min | 94 | 66 | $2.39 | 5.0 | csharp | ok |
| Process Monitor | powershell | opus46-200k-medium | 14.6min | 96 | 78 | $3.28 | 5.0 | powershell | ok |
| CSV Report Generator | powershell | opus46-200k-medium | 11.4min | 97 | 89 | $3.05 | 4.0 | powershell | ok |
| Semantic Version Bumper | default | sonnet46-200k-medium | 12.9min | 98 | 58 | $2.16 | 5.0 | python | ok |
| REST API Client | powershell-strict | opus46-200k-medium | 378.5min | 101 | 87 | $4.06 | 4.0 | powershell | ok |
| Config File Migrator | default | sonnet46-200k-medium | 58.5min | 102 | 65 | $2.44 | 4.0 | python | ok |
| Docker Image Tag Generator | csharp-script | sonnet46-200k-medium | 13.3min | 103 | 88 | $2.28 | 3.0 | csharp | ok |
| Batch File Renamer | powershell | opus46-200k-medium | 67.4min | 104 | 117 | $3.32 | 4.0 | powershell | ok |
| Batch File Renamer | default | opus46-200k-medium | 33.9min | 106 | 109 | $2.76 | 4.0 | python | ok |
| Batch File Renamer | csharp-script | opus46-200k-medium | 40.4min | 108 | 134 | $3.34 | 4.0 | csharp | ok |
| Secret Rotation Validator | default | opus46-200k-medium | 12.2min | 108 | 88 | $3.43 | 5.0 | python | ok |
| Docker Image Tag Generator | powershell | opus46-200k-medium | 12.4min | 109 | 101 | $3.05 | 5.0 | powershell | ok |
| Artifact Cleanup Script | default | opus46-200k-medium | 12.9min | 110 | 113 | $3.49 | 5.0 | python | ok |
| REST API Client | default | opus46-200k-medium | 157.1min | 113 | 118 | $3.08 | 4.0 | python | ok |
| Error Retry Pipeline | powershell-strict | opus46-200k-medium | 11.1min | 114 | 103 | $3.17 | 4.0 | powershell | ok |
| Process Monitor | default | opus46-200k-medium | 9.8min | 115 | 109 | $2.34 | 4.0 | python | ok |
| Config File Migrator | powershell | opus46-200k-medium | 12.6min | 115 | 90 | $3.65 | 4.0 | powershell | ok |
| Semantic Version Bumper | powershell | sonnet46-200k-medium | 13.7min | 116 | 96 | $2.60 | 4.0 | powershell | ok |
| Dependency License Checker | powershell | opus46-200k-medium | 14.9min | 118 | 99 | $4.17 | 4.0 | powershell | ok |
| Environment Matrix Generator | default | opus46-200k-medium | 15.5min | 119 | 172 | $3.93 | 5.0 | python | ok |
| Semantic Version Bumper | powershell | opus46-200k-medium | 13.3min | 120 | 100 | $3.84 | 4.0 | powershell | ok |
| Test Results Aggregator | csharp-script | opus46-200k-medium | 11.7min | 120 | 93 | $3.40 | 4.0 | csharp | ok |
| Directory Tree Sync | default | opus46-200k-medium | 44.4min | 122 | 107 | $3.24 | 4.0 | python | ok |
| Database Seed Script | csharp-script | opus46-200k-medium | 11.4min | 122 | 103 | $3.49 | 4.0 | csharp | ok |
| Log File Analyzer | powershell | opus46-200k-medium | 143.9min | 123 | 105 | $3.88 | 4.0 | powershell | ok |
| Process Monitor | powershell-strict | opus46-200k-medium | 15.3min | 126 | 114 | $4.00 | 4.0 | powershell | ok |
| Multi-file Search and Replace | powershell | opus46-200k-medium | 17.1min | 126 | 124 | $4.56 | 4.0 | powershell | ok |
| Dependency License Checker | csharp-script | sonnet46-200k-medium | 26.6min | 126 | 67 | $3.08 | 4.0 | csharp | ok |
| Multi-file Search and Replace | powershell-strict | opus46-200k-medium | 12.2min | 129 | 130 | $3.52 | 3.0 | powershell | ok |
| Semantic Version Bumper | default | opus46-200k-medium | 12.0min | 129 | 115 | $3.34 | 4.0 | python | ok |
| Docker Image Tag Generator | powershell-strict | opus46-200k-medium | 12.2min | 130 | 127 | $3.40 | 4.0 | powershell | ok |
| Log File Analyzer | csharp-script | sonnet46-200k-medium | 25.4min | 131 | 73 | $4.11 | 5.0 | csharp | ok |
| Artifact Cleanup Script | csharp-script | opus46-200k-medium | 17.9min | 131 | 121 | $4.17 | 4.0 | csharp | ok |
| Multi-file Search and Replace | csharp-script | opus46-200k-medium | 17.3min | 134 | 130 | $4.56 | 4.0 | csharp | ok |
| Artifact Cleanup Script | powershell-strict | opus46-200k-medium | 16.7min | 135 | 132 | $5.03 | 4.0 | powershell | ok |
| Secret Rotation Validator | powershell | opus46-200k-medium | 15.4min | 136 | 148 | $4.01 | 4.0 | powershell | ok |
| Environment Matrix Generator | powershell-strict | opus46-200k-medium | 16.8min | 137 | 126 | $4.48 | 4.0 | powershell | ok |
| Config File Migrator | csharp-script | sonnet46-200k-medium | 73.6min | 138 | 58 | $5.32 | 1.0 | csharp | ok |
| Directory Tree Sync | powershell-strict | opus46-200k-medium | 144.7min | 140 | 140 | $4.71 | 4.0 | powershell | ok |
| PR Label Assigner | default | opus46-200k-medium | 16.1min | 140 | 142 | $3.77 | 5.0 | python | ok |
| PR Label Assigner | powershell-strict | opus46-200k-medium | 11.1min | 141 | 130 | $3.72 | 4.0 | powershell | ok |
| PR Label Assigner | csharp-script | sonnet46-200k-medium | 21.0min | 143 | 95 | $4.26 | 3.0 | csharp | ok |
| Database Seed Script | default | opus46-200k-medium | 13.1min | 146 | 141 | $3.83 | 5.0 | python | ok |
| Environment Matrix Generator | powershell | opus46-200k-medium | 14.9min | 148 | 117 | $4.93 | 4.0 | powershell | ok |
| Config File Migrator | powershell-strict | opus46-200k-medium | 16.2min | 154 | 130 | $5.77 | 4.0 | powershell | ok |
| Docker Image Tag Generator | csharp-script | opus46-200k-medium | 16.6min | 154 | 139 | $4.60 | 4.0 | csharp | ok |
| Log File Analyzer | powershell-strict | opus46-200k-medium | 128.9min | 155 | 134 | $5.44 | 4.0 | powershell | ok |
| Error Retry Pipeline | default | opus46-200k-medium | 17.1min | 156 | 140 | $3.93 | — |  | ok |
| Docker Image Tag Generator | default | opus46-200k-medium | 15.3min | 156 | 162 | $3.82 | 5.0 | python | ok |
| Database Seed Script | powershell-strict | opus46-200k-medium | 19.8min | 162 | 160 | $6.54 | 4.0 | powershell | ok |
| Secret Rotation Validator | csharp-script | opus46-200k-medium | 17.2min | 162 | 149 | $5.30 | 5.0 | csharp | ok |
| Batch File Renamer | powershell-strict | opus46-200k-medium | 76.3min | 163 | 148 | $5.60 | 4.0 | powershell | ok |
| Test Results Aggregator | powershell-strict | opus46-200k-medium | 18.6min | 164 | 148 | $6.18 | 4.0 | powershell | ok |
| Config File Migrator | default | opus46-200k-medium | 16.7min | 165 | 150 | $5.11 | 4.0 | python | ok |
| Database Seed Script | powershell | opus46-200k-medium | 14.4min | 167 | 140 | $5.61 | 4.0 | powershell | ok |
| CSV Report Generator | powershell-strict | opus46-200k-medium | 16.2min | 168 | 176 | $5.79 | 4.0 | powershell | ok |
| Docker Image Tag Generator | powershell | sonnet46-200k-medium | 13.5min | 169 | 143 | $3.46 | 4.0 | powershell | ok |
| Test Results Aggregator | default | opus46-200k-medium | 16.9min | 172 | 203 | $4.97 | 4.0 | python | ok |
| Error Retry Pipeline | csharp-script | opus46-200k-medium | 26.0min | 173 | 194 | $6.97 | 4.0 | csharp | ok |
| Environment Matrix Generator | csharp-script | opus46-200k-medium | 21.0min | 175 | 142 | $6.47 | 5.0 | csharp | ok |
| Secret Rotation Validator | powershell-strict | opus46-200k-medium | 23.4min | 175 | 159 | $6.38 | 5.0 | powershell | ok |
| Multi-file Search and Replace | default | opus46-200k-medium | 15.9min | 181 | 171 | $4.45 | 4.0 | python | ok |
| Process Monitor | csharp-script | opus46-200k-medium | 21.7min | 182 | 188 | $6.00 | 4.0 | csharp | ok |
| Log File Analyzer | default | opus46-200k-medium | 105.3min | 195 | 205 | $5.43 | — | javascript | ok |
| REST API Client | csharp-script | opus46-200k-medium | 22.6min | 195 | 177 | $7.32 | 4.0 | csharp | ok |
| PR Label Assigner | csharp-script | opus46-200k-medium | 21.5min | 215 | 203 | $7.33 | 4.0 | csharp | ok |
| Dependency License Checker | default | opus46-200k-medium | 17.2min | 217 | 220 | $6.00 | 5.0 | python | ok |
| Log File Analyzer | csharp-script | opus46-200k-medium | 168.4min | 221 | 193 | $8.66 | 4.0 | csharp | ok |
| CSV Report Generator | default | opus46-200k-medium | 23.8min | 222 | 225 | $4.92 | 4.0 | python | ok |
| Dependency License Checker | csharp-script | opus46-200k-medium | 21.8min | 223 | 197 | $8.83 | 4.0 | csharp | ok |
| Semantic Version Bumper | powershell-strict | opus46-200k-medium | 18.5min | 225 | 210 | $7.96 | 4.0 | powershell | ok |
| Directory Tree Sync | csharp-script | opus46-200k-medium | 202.0min | 229 | 205 | $7.54 | 4.0 | csharp | ok |

</details>

<details>
<summary>Sorted by LLM-as-judge score (best first)</summary>

| Task | Language | Model | Duration | Turns | Errors | Cost | Tests Quality | Chosen | Status |
|------|----------|-------|----------|-------|--------|------|-----------|--------|--------|
| Log File Analyzer | csharp-script | sonnet46-200k-medium | 25.4min | 131 | 73 | $4.11 | 5.0 | csharp | ok |
| Directory Tree Sync | csharp-script | sonnet46-200k-medium | 143.8min | 83 | 49 | $2.42 | 5.0 | csharp | ok |
| Directory Tree Sync | default | sonnet46-200k-medium | 26.1min | 17 | 9 | $0.42 | 5.0 | python | ok |
| Process Monitor | powershell | opus46-200k-medium | 14.6min | 96 | 78 | $3.28 | 5.0 | powershell | ok |
| Batch File Renamer | default | sonnet46-200k-medium | 46.7min | 58 | 44 | $1.27 | 5.0 | python | ok |
| Batch File Renamer | powershell-strict | sonnet46-200k-medium | 12.6min | 48 | 30 | $1.38 | 5.0 | powershell | ok |
| Database Seed Script | csharp-script | sonnet46-200k-medium | 28.1min | 0 | 0 | $0.00 | 5.0 | csharp | failed |
| Database Seed Script | default | opus46-200k-medium | 13.1min | 146 | 141 | $3.83 | 5.0 | python | ok |
| Error Retry Pipeline | powershell | opus46-200k-medium | 14.6min | 80 | 90 | $3.26 | 5.0 | powershell | ok |
| Multi-file Search and Replace | csharp-script | sonnet46-200k-medium | 14.6min | 94 | 66 | $2.39 | 5.0 | csharp | ok |
| Semantic Version Bumper | csharp-script | sonnet46-200k-medium | 17.0min | 64 | 42 | $2.67 | 5.0 | csharp | ok |
| Semantic Version Bumper | default | sonnet46-200k-medium | 12.9min | 98 | 58 | $2.16 | 5.0 | python | ok |
| PR Label Assigner | default | opus46-200k-medium | 16.1min | 140 | 142 | $3.77 | 5.0 | python | ok |
| Dependency License Checker | default | opus46-200k-medium | 17.2min | 217 | 220 | $6.00 | 5.0 | python | ok |
| Dependency License Checker | default | sonnet46-200k-medium | 7.3min | 52 | 39 | $1.18 | 5.0 | python | ok |
| Dependency License Checker | powershell-strict | opus46-200k-medium | 14.6min | 87 | 60 | $2.75 | 5.0 | powershell | ok |
| Docker Image Tag Generator | default | opus46-200k-medium | 15.3min | 156 | 162 | $3.82 | 5.0 | python | ok |
| Docker Image Tag Generator | powershell | opus46-200k-medium | 12.4min | 109 | 101 | $3.05 | 5.0 | powershell | ok |
| Environment Matrix Generator | csharp-script | opus46-200k-medium | 21.0min | 175 | 142 | $6.47 | 5.0 | csharp | ok |
| Environment Matrix Generator | default | opus46-200k-medium | 15.5min | 119 | 172 | $3.93 | 5.0 | python | ok |
| Artifact Cleanup Script | default | opus46-200k-medium | 12.9min | 110 | 113 | $3.49 | 5.0 | python | ok |
| Secret Rotation Validator | csharp-script | opus46-200k-medium | 17.2min | 162 | 149 | $5.30 | 5.0 | csharp | ok |
| Secret Rotation Validator | default | opus46-200k-medium | 12.2min | 108 | 88 | $3.43 | 5.0 | python | ok |
| Secret Rotation Validator | powershell-strict | opus46-200k-medium | 23.4min | 175 | 159 | $6.38 | 5.0 | powershell | ok |
| CSV Report Generator | csharp-script | sonnet46-200k-medium | 112.8min | 48 | 26 | $1.13 | 4.0 | csharp | ok |
| CSV Report Generator | default | opus46-200k-medium | 23.8min | 222 | 225 | $4.92 | 4.0 | python | ok |
| CSV Report Generator | default | sonnet46-200k-medium | 53.2min | 37 | 25 | $0.65 | 4.0 | python | ok |
| CSV Report Generator | powershell | opus46-200k-medium | 11.4min | 97 | 89 | $3.05 | 4.0 | powershell | ok |
| CSV Report Generator | powershell | sonnet46-200k-medium | 56.1min | 52 | 27 | $0.97 | 4.0 | powershell | ok |
| CSV Report Generator | powershell-strict | opus46-200k-medium | 16.2min | 168 | 176 | $5.79 | 4.0 | powershell | ok |
| CSV Report Generator | powershell-strict | sonnet46-200k-medium | 121.6min | 74 | 41 | $1.75 | 4.0 | powershell | ok |
| Log File Analyzer | csharp-script | opus46-200k-medium | 168.4min | 221 | 193 | $8.66 | 4.0 | csharp | ok |
| Log File Analyzer | powershell | opus46-200k-medium | 143.9min | 123 | 105 | $3.88 | 4.0 | powershell | ok |
| Log File Analyzer | powershell | sonnet46-200k-medium | 10.6min | 62 | 51 | $1.78 | 4.0 | powershell | ok |
| Log File Analyzer | powershell-strict | opus46-200k-medium | 128.9min | 155 | 134 | $5.44 | 4.0 | powershell | ok |
| Log File Analyzer | powershell-strict | sonnet46-200k-medium | 25.2min | 52 | 22 | $1.37 | 4.0 | powershell | ok |
| Directory Tree Sync | csharp-script | opus46-200k-medium | 202.0min | 229 | 205 | $7.54 | 4.0 | csharp | ok |
| Directory Tree Sync | default | opus46-200k-medium | 44.4min | 122 | 107 | $3.24 | 4.0 | python | ok |
| Directory Tree Sync | powershell | opus46-200k-medium | 112.3min | 93 | 91 | $2.97 | 4.0 | powershell | ok |
| Directory Tree Sync | powershell | sonnet46-200k-medium | 69.6min | 60 | 41 | $1.54 | 4.0 | powershell | ok |
| Directory Tree Sync | powershell-strict | opus46-200k-medium | 144.7min | 140 | 140 | $4.71 | 4.0 | powershell | ok |
| Directory Tree Sync | powershell-strict | sonnet46-200k-medium | 23.7min | 31 | 19 | $0.57 | 4.0 | powershell | ok |
| REST API Client | csharp-script | opus46-200k-medium | 22.6min | 195 | 177 | $7.32 | 4.0 | csharp | ok |
| REST API Client | csharp-script | sonnet46-200k-medium | 23.2min | 74 | 63 | $3.91 | 4.0 | csharp | ok |
| REST API Client | default | opus46-200k-medium | 157.1min | 113 | 118 | $3.08 | 4.0 | python | ok |
| REST API Client | default | sonnet46-200k-medium | 10.8min | 54 | 33 | $1.49 | 4.0 | python | ok |
| REST API Client | powershell | opus46-200k-medium | 257.5min | 0 | 0 | $0.00 | 4.0 | powershell | failed |
| REST API Client | powershell | sonnet46-200k-medium | 13.9min | 56 | 35 | $1.93 | 4.0 | powershell | ok |
| REST API Client | powershell-strict | opus46-200k-medium | 378.5min | 101 | 87 | $4.06 | 4.0 | powershell | ok |
| REST API Client | powershell-strict | sonnet46-200k-medium | 13.4min | 41 | 27 | $1.82 | 4.0 | powershell | ok |
| Process Monitor | csharp-script | opus46-200k-medium | 21.7min | 182 | 188 | $6.00 | 4.0 | csharp | ok |
| Process Monitor | default | opus46-200k-medium | 9.8min | 115 | 109 | $2.34 | 4.0 | python | ok |
| Process Monitor | default | sonnet46-200k-medium | 9.8min | 76 | 61 | $1.60 | 4.0 | python | ok |
| Process Monitor | powershell | sonnet46-200k-medium | 6.6min | 53 | 33 | $1.11 | 4.0 | powershell | ok |
| Process Monitor | powershell-strict | opus46-200k-medium | 15.3min | 126 | 114 | $4.00 | 4.0 | powershell | ok |
| Process Monitor | powershell-strict | sonnet46-200k-medium | 14.1min | 46 | 39 | $2.11 | 4.0 | powershell | ok |
| Config File Migrator | csharp-script | opus46-200k-medium | 54.2min | 0 | 0 | $0.00 | 4.0 | csharp | failed |
| Config File Migrator | default | opus46-200k-medium | 16.7min | 165 | 150 | $5.11 | 4.0 | python | ok |
| Config File Migrator | default | sonnet46-200k-medium | 58.5min | 102 | 65 | $2.44 | 4.0 | python | ok |
| Config File Migrator | powershell | opus46-200k-medium | 12.6min | 115 | 90 | $3.65 | 4.0 | powershell | ok |
| Config File Migrator | powershell | sonnet46-200k-medium | 52.0min | 81 | 60 | $2.57 | 4.0 | powershell | ok |
| Config File Migrator | powershell-strict | opus46-200k-medium | 16.2min | 154 | 130 | $5.77 | 4.0 | powershell | ok |
| Batch File Renamer | csharp-script | opus46-200k-medium | 40.4min | 108 | 134 | $3.34 | 4.0 | csharp | ok |
| Batch File Renamer | default | opus46-200k-medium | 33.9min | 106 | 109 | $2.76 | 4.0 | python | ok |
| Batch File Renamer | powershell | opus46-200k-medium | 67.4min | 104 | 117 | $3.32 | 4.0 | powershell | ok |
| Batch File Renamer | powershell | sonnet46-200k-medium | 246.7min | 67 | 37 | $2.07 | 4.0 | powershell | ok |
| Batch File Renamer | powershell-strict | opus46-200k-medium | 76.3min | 163 | 148 | $5.60 | 4.0 | powershell | ok |
| Database Seed Script | csharp-script | opus46-200k-medium | 11.4min | 122 | 103 | $3.49 | 4.0 | csharp | ok |
| Database Seed Script | powershell | opus46-200k-medium | 14.4min | 167 | 140 | $5.61 | 4.0 | powershell | ok |
| Database Seed Script | powershell | sonnet46-200k-medium | 12.1min | 60 | 36 | $1.67 | 4.0 | powershell | ok |
| Database Seed Script | powershell-strict | opus46-200k-medium | 19.8min | 162 | 160 | $6.54 | 4.0 | powershell | ok |
| Database Seed Script | powershell-strict | sonnet46-200k-medium | 12.7min | 35 | 17 | $1.65 | 4.0 | powershell | ok |
| Error Retry Pipeline | csharp-script | opus46-200k-medium | 26.0min | 173 | 194 | $6.97 | 4.0 | csharp | ok |
| Error Retry Pipeline | csharp-script | sonnet46-200k-medium | 10.1min | 71 | 42 | $1.49 | 4.0 | csharp | ok |
| Error Retry Pipeline | default | sonnet46-200k-medium | 8.8min | 69 | 42 | $1.50 | 4.0 | python | ok |
| Error Retry Pipeline | powershell | sonnet46-200k-medium | 8.2min | 42 | 22 | $1.05 | 4.0 | powershell | ok |
| Error Retry Pipeline | powershell-strict | opus46-200k-medium | 11.1min | 114 | 103 | $3.17 | 4.0 | powershell | ok |
| Error Retry Pipeline | powershell-strict | sonnet46-200k-medium | 7.1min | 35 | 17 | $0.92 | 4.0 | powershell | ok |
| Multi-file Search and Replace | csharp-script | opus46-200k-medium | 17.3min | 134 | 130 | $4.56 | 4.0 | csharp | ok |
| Multi-file Search and Replace | default | opus46-200k-medium | 15.9min | 181 | 171 | $4.45 | 4.0 | python | ok |
| Multi-file Search and Replace | default | sonnet46-200k-medium | 4.5min | 25 | 21 | $0.71 | 4.0 | python | ok |
| Multi-file Search and Replace | powershell | opus46-200k-medium | 17.1min | 126 | 124 | $4.56 | 4.0 | powershell | ok |
| Multi-file Search and Replace | powershell | sonnet46-200k-medium | 8.8min | 49 | 49 | $1.17 | 4.0 | powershell | ok |
| Multi-file Search and Replace | powershell-strict | sonnet46-200k-medium | 15.3min | 69 | 62 | $2.41 | 4.0 | powershell | ok |
| Semantic Version Bumper | default | opus46-200k-medium | 12.0min | 129 | 115 | $3.34 | 4.0 | python | ok |
| Semantic Version Bumper | powershell | opus46-200k-medium | 13.3min | 120 | 100 | $3.84 | 4.0 | powershell | ok |
| Semantic Version Bumper | powershell | sonnet46-200k-medium | 13.7min | 116 | 96 | $2.60 | 4.0 | powershell | ok |
| Semantic Version Bumper | powershell-strict | opus46-200k-medium | 18.5min | 225 | 210 | $7.96 | 4.0 | powershell | ok |
| Semantic Version Bumper | powershell-strict | sonnet46-200k-medium | 12.7min | 60 | 59 | $2.08 | 4.0 | powershell | ok |
| PR Label Assigner | csharp-script | opus46-200k-medium | 21.5min | 215 | 203 | $7.33 | 4.0 | csharp | ok |
| PR Label Assigner | default | sonnet46-200k-medium | 6.7min | 26 | 23 | $0.92 | 4.0 | python | ok |
| PR Label Assigner | powershell | opus46-200k-medium | 10.0min | 93 | 75 | $2.48 | 4.0 | powershell | ok |
| PR Label Assigner | powershell | sonnet46-200k-medium | 7.8min | 44 | 33 | $1.26 | 4.0 | powershell | ok |
| PR Label Assigner | powershell-strict | opus46-200k-medium | 11.1min | 141 | 130 | $3.72 | 4.0 | powershell | ok |
| PR Label Assigner | powershell-strict | sonnet46-200k-medium | 8.9min | 28 | 16 | $1.02 | 4.0 | powershell | ok |
| Dependency License Checker | csharp-script | opus46-200k-medium | 21.8min | 223 | 197 | $8.83 | 4.0 | csharp | ok |
| Dependency License Checker | csharp-script | sonnet46-200k-medium | 26.6min | 126 | 67 | $3.08 | 4.0 | csharp | ok |
| Dependency License Checker | powershell | opus46-200k-medium | 14.9min | 118 | 99 | $4.17 | 4.0 | powershell | ok |
| Dependency License Checker | powershell | sonnet46-200k-medium | 3.0min | 33 | 18 | $0.59 | 4.0 | powershell | ok |
| Docker Image Tag Generator | csharp-script | opus46-200k-medium | 16.6min | 154 | 139 | $4.60 | 4.0 | csharp | ok |
| Docker Image Tag Generator | default | sonnet46-200k-medium | 3.8min | 20 | 17 | $0.50 | 4.0 | python | ok |
| Docker Image Tag Generator | powershell | sonnet46-200k-medium | 13.5min | 169 | 143 | $3.46 | 4.0 | powershell | ok |
| Docker Image Tag Generator | powershell-strict | opus46-200k-medium | 12.2min | 130 | 127 | $3.40 | 4.0 | powershell | ok |
| Docker Image Tag Generator | powershell-strict | sonnet46-200k-medium | 8.7min | 59 | 38 | $1.34 | 4.0 | powershell | ok |
| Test Results Aggregator | csharp-script | opus46-200k-medium | 11.7min | 120 | 93 | $3.40 | 4.0 | csharp | ok |
| Test Results Aggregator | csharp-script | sonnet46-200k-medium | 13.0min | 67 | 29 | $2.32 | 4.0 | csharp | ok |
| Test Results Aggregator | default | opus46-200k-medium | 16.9min | 172 | 203 | $4.97 | 4.0 | python | ok |
| Test Results Aggregator | default | sonnet46-200k-medium | 10.2min | 76 | 59 | $2.01 | 4.0 | python | ok |
| Test Results Aggregator | powershell | opus46-200k-medium | 10.2min | 89 | 70 | $3.10 | 4.0 | powershell | ok |
| Test Results Aggregator | powershell | sonnet46-200k-medium | 9.6min | 63 | 40 | $1.57 | 4.0 | powershell | ok |
| Test Results Aggregator | powershell-strict | opus46-200k-medium | 18.6min | 164 | 148 | $6.18 | 4.0 | powershell | ok |
| Test Results Aggregator | powershell-strict | sonnet46-200k-medium | 14.6min | 37 | 27 | $1.33 | 4.0 | powershell | ok |
| Environment Matrix Generator | default | sonnet46-200k-medium | 8.2min | 52 | 33 | $1.32 | 4.0 | python | ok |
| Environment Matrix Generator | powershell | opus46-200k-medium | 14.9min | 148 | 117 | $4.93 | 4.0 | powershell | ok |
| Environment Matrix Generator | powershell | sonnet46-200k-medium | 6.7min | 30 | 33 | $0.89 | 4.0 | powershell | ok |
| Environment Matrix Generator | powershell-strict | opus46-200k-medium | 16.8min | 137 | 126 | $4.48 | 4.0 | powershell | ok |
| Environment Matrix Generator | powershell-strict | sonnet46-200k-medium | 30.0min | 0 | 0 | $0.00 | 4.0 | powershell | failed |
| Artifact Cleanup Script | csharp-script | opus46-200k-medium | 17.9min | 131 | 121 | $4.17 | 4.0 | csharp | ok |
| Artifact Cleanup Script | csharp-script | sonnet46-200k-medium | 9.1min | 39 | 22 | $1.16 | 4.0 | csharp | ok |
| Artifact Cleanup Script | default | sonnet46-200k-medium | 3.2min | 26 | 15 | $0.49 | 4.0 | python | ok |
| Artifact Cleanup Script | powershell | opus46-200k-medium | 11.6min | 91 | 90 | $2.83 | 4.0 | powershell | ok |
| Artifact Cleanup Script | powershell | sonnet46-200k-medium | 13.0min | 40 | 37 | $1.63 | 4.0 | powershell | ok |
| Artifact Cleanup Script | powershell-strict | opus46-200k-medium | 16.7min | 135 | 132 | $5.03 | 4.0 | powershell | ok |
| Artifact Cleanup Script | powershell-strict | sonnet46-200k-medium | 13.3min | 52 | 35 | $1.83 | 4.0 | powershell | ok |
| Secret Rotation Validator | csharp-script | sonnet46-200k-medium | 14.2min | 74 | 85 | $2.67 | 4.0 | csharp | ok |
| Secret Rotation Validator | default | sonnet46-200k-medium | 3.7min | 23 | 19 | $0.58 | 4.0 | python | ok |
| Secret Rotation Validator | powershell | opus46-200k-medium | 15.4min | 136 | 148 | $4.01 | 4.0 | powershell | ok |
| Secret Rotation Validator | powershell | sonnet46-200k-medium | 8.3min | 61 | 53 | $1.52 | 4.0 | powershell | ok |
| Secret Rotation Validator | powershell-strict | sonnet46-200k-medium | 7.0min | 13 | 6 | $0.80 | 4.0 | powershell | ok |
| Log File Analyzer | default | sonnet46-200k-medium | 10.6min | 72 | 48 | $1.84 | 3.0 | python | ok |
| Config File Migrator | powershell-strict | sonnet46-200k-medium | 44.9min | 69 | 40 | $1.84 | 3.0 | powershell | ok |
| Batch File Renamer | csharp-script | sonnet46-200k-medium | 19.3min | 60 | 121 | $3.76 | 3.0 | csharp | ok |
| Database Seed Script | default | sonnet46-200k-medium | 16.3min | 42 | 28 | $0.98 | 3.0 | python | ok |
| Multi-file Search and Replace | powershell-strict | opus46-200k-medium | 12.2min | 129 | 130 | $3.52 | 3.0 | powershell | ok |
| PR Label Assigner | csharp-script | sonnet46-200k-medium | 21.0min | 143 | 95 | $4.26 | 3.0 | csharp | ok |
| Docker Image Tag Generator | csharp-script | sonnet46-200k-medium | 13.3min | 103 | 88 | $2.28 | 3.0 | csharp | ok |
| CSV Report Generator | csharp-script | opus46-200k-medium | 271.2min | 0 | 0 | $0.00 | 2.0 | csharp | failed |
| Process Monitor | csharp-script | sonnet46-200k-medium | 13.2min | 61 | 33 | $1.89 | 1.0 | csharp | ok |
| Config File Migrator | csharp-script | sonnet46-200k-medium | 73.6min | 138 | 58 | $5.32 | 1.0 | csharp | ok |
| Dependency License Checker | powershell-strict | sonnet46-200k-medium | 15.7min | 70 | 57 | $2.20 | 1.0 | powershell | ok |
| Environment Matrix Generator | csharp-script | sonnet46-200k-medium | 12.9min | 85 | 59 | $2.26 | 1.0 | csharp | ok |
| Log File Analyzer | default | opus46-200k-medium | 105.3min | 195 | 205 | $5.43 | — | javascript | ok |
| Error Retry Pipeline | default | opus46-200k-medium | 17.1min | 156 | 140 | $3.93 | — |  | ok |
| Semantic Version Bumper | csharp-script | opus46-200k-medium | 6.2min | 65 | 96 | $1.39 | — | bash | ok |

</details>

## Notes

### Tiers

- **Duration bands:** **A+** ≤1.10×, **A** ≤1.21×, **A-** ≤1.33×, **B+** ≤1.47×, **B** ≤1.61×, **B-** ≤1.78×, **C+** ≤1.96×, **C** ≤2.15×, **C-** ≤2.37×, **D+** ≤2.61×, **D** ≤2.87×, **D-** ≤3.16×, **F** >3.16×
- **Cost bands:** **A+** ≤1.13×, **A** ≤1.29×, **A-** ≤1.46×, **B+** ≤1.66×, **B** ≤1.88×, **B-** ≤2.13×, **C+** ≤2.42×, **C** ≤2.75×, **C-** ≤3.12×, **D+** ≤3.54×, **D** ≤4.01×, **D-** ≤4.55×, **F** >4.55×

*Tests/Workflow Craft bands are absolute Overall score bands:* **A+** ≥4.7, **A** ≥4.4, **A-** ≥4.1, **B+** ≥3.8, **B** ≥3.5, **B-** ≥3.2, **C+** ≥2.9, **C** ≥2.6, **C-** ≥2.3, **D+** ≥2.0, **D** ≥1.7, **D-** ≥1.4, **F** <1.4, `—` = no data.*

### CLI Version Legend

| Variant label | CLI version | Tasks | Languages |
|---------------|-------------|-------|-----------|
| opus46-200k-medium | 2.1.81 | All | All |
| sonnet46-200k-medium | 2.1.81 | All | All |

---
*Generated by generate_results.py — benchmark instructions v1*