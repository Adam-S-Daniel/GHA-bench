# Benchmark Results: Language Comparison

**Last updated:** 2026-07-03 07:19:53 AM ET — 111/144 runs completed, 33 remaining; total cost $76.34; total agent time 459.2 min.
**Claude Code versions used:** [v2.1.94](claude-code-2.1.94.md) (25 runs), [v2.1.96](claude-code-2.1.96.md) (86 runs). Each link goes to a per-version snapshot of the system prompt, default-tool descriptions, and the chronological Anthropic changelog up to that version. Regenerate with `python3 version_docs.py`.

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
- **Avg Duration** (in the [Comparison by Language/Model/Effort](#comparison-by-languagemodeleffort) table; also drives the [Tiers](#tiers-by-languagemodeleffort) Duration column): arithmetic mean of `Duration` over the runs in that combo, excluding failed/timed-out runs.
- **Avg Duration Net of Traps** (in the Comparison table only): mean of (per-run `Duration` − that run's `Time Lost`), where `Time Lost` is the trap detector's estimate of seconds spent on detected anti-patterns (see [Trap Descriptions](#trap-descriptions) and the trap-table [Column Definitions](#column-definitions) for the trap list and how Time Lost is computed). Reads as a counterfactual: roughly how fast each combo would have been without the detected traps.
- The **Tier table's Duration column** shows the tier letter (A+..F) for the combo's gross **Avg Duration** ratio. Net of Traps does not feed the tier band.
## Tiers by Language/Model/Effort

*Default sort: weighted composite of tiers (40% Tests, 25% Workflow Craft, 35% split between Duration & Cost). See [Notes](#notes) for tier-band definitions and scoring rubric.*
*`*` after a Model label = this combo's aggregates exclude one or more failed/timed-out runs (see the Failed / Timed-Out Runs table).*

| Language | Model | Duration | Cost | Tests Quality | Workflow Craft |
|----------|-------|----------|------|-----------|-------------|
| csharp-script | sonnet46-200k-medium | A+ (0.6min) | A+ ($0.12) | B+ (4.0) | — |
| default | sonnet46-200k-medium* | C (2.8min) | B- ($0.35) | A- (4.2) | — |
| csharp-script | opus46-200k-medium | B- (1.8min) | C+ ($0.42) | B+ (4.0) | — |
| powershell | sonnet46-200k-medium* | D+ (3.6min) | C+ ($0.39) | B+ (3.9) | — |
| default | opus46-200k-medium | D+ (3.5min) | D ($0.88) | A- (4.2) | — |
| powershell | opus46-200k-medium | D (4.3min) | D ($0.97) | B+ (4.1) | — |
| powershell-strict | sonnet46-200k-medium* | D- (6.1min) | D+ ($0.74) | B+ (4.0) | — |
| powershell-strict | opus46-200k-medium* | D (4.9min) | D- ($1.20) | B+ (3.9) | — |


<details>
<summary>Sorted by Duration tier (best-first), then avg of Cost/Tests/Workflow Craft tiers</summary>

| Language | Model | Duration | Cost | Tests Quality | Workflow Craft |
|----------|-------|----------|------|-----------|-------------|
| csharp-script | sonnet46-200k-medium | A+ (0.6min) | A+ ($0.12) | B+ (4.0) | — |
| csharp-script | opus46-200k-medium | B- (1.8min) | C+ ($0.42) | B+ (4.0) | — |
| default | sonnet46-200k-medium* | C (2.8min) | B- ($0.35) | A- (4.2) | — |
| powershell | sonnet46-200k-medium* | D+ (3.6min) | C+ ($0.39) | B+ (3.9) | — |
| default | opus46-200k-medium | D+ (3.5min) | D ($0.88) | A- (4.2) | — |
| powershell | opus46-200k-medium | D (4.3min) | D ($0.97) | B+ (4.1) | — |
| powershell-strict | opus46-200k-medium* | D (4.9min) | D- ($1.20) | B+ (3.9) | — |
| powershell-strict | sonnet46-200k-medium* | D- (6.1min) | D+ ($0.74) | B+ (4.0) | — |

</details>

<details>
<summary>Sorted by Cost tier (best-first), then avg of Duration/Tests/Workflow Craft tiers</summary>

| Language | Model | Duration | Cost | Tests Quality | Workflow Craft |
|----------|-------|----------|------|-----------|-------------|
| csharp-script | sonnet46-200k-medium | A+ (0.6min) | A+ ($0.12) | B+ (4.0) | — |
| default | sonnet46-200k-medium* | C (2.8min) | B- ($0.35) | A- (4.2) | — |
| csharp-script | opus46-200k-medium | B- (1.8min) | C+ ($0.42) | B+ (4.0) | — |
| powershell | sonnet46-200k-medium* | D+ (3.6min) | C+ ($0.39) | B+ (3.9) | — |
| powershell-strict | sonnet46-200k-medium* | D- (6.1min) | D+ ($0.74) | B+ (4.0) | — |
| default | opus46-200k-medium | D+ (3.5min) | D ($0.88) | A- (4.2) | — |
| powershell | opus46-200k-medium | D (4.3min) | D ($0.97) | B+ (4.1) | — |
| powershell-strict | opus46-200k-medium* | D (4.9min) | D- ($1.20) | B+ (3.9) | — |

</details>

<details>
<summary>Sorted by Tests Quality tier (best-first; no-data last), then avg of other tiers</summary>

| Language | Model | Duration | Cost | Tests Quality | Workflow Craft |
|----------|-------|----------|------|-----------|-------------|
| default | sonnet46-200k-medium* | C (2.8min) | B- ($0.35) | A- (4.2) | — |
| default | opus46-200k-medium | D+ (3.5min) | D ($0.88) | A- (4.2) | — |
| csharp-script | sonnet46-200k-medium | A+ (0.6min) | A+ ($0.12) | B+ (4.0) | — |
| csharp-script | opus46-200k-medium | B- (1.8min) | C+ ($0.42) | B+ (4.0) | — |
| powershell | sonnet46-200k-medium* | D+ (3.6min) | C+ ($0.39) | B+ (3.9) | — |
| powershell | opus46-200k-medium | D (4.3min) | D ($0.97) | B+ (4.1) | — |
| powershell-strict | sonnet46-200k-medium* | D- (6.1min) | D+ ($0.74) | B+ (4.0) | — |
| powershell-strict | opus46-200k-medium* | D (4.9min) | D- ($1.20) | B+ (3.9) | — |

</details>

<details>
<summary>Sorted by Workflow Craft tier (best-first; no-data last), then avg of other tiers</summary>

| Language | Model | Duration | Cost | Tests Quality | Workflow Craft |
|----------|-------|----------|------|-----------|-------------|
| csharp-script | sonnet46-200k-medium | A+ (0.6min) | A+ ($0.12) | B+ (4.0) | — |
| csharp-script | opus46-200k-medium | B- (1.8min) | C+ ($0.42) | B+ (4.0) | — |
| default | sonnet46-200k-medium* | C (2.8min) | B- ($0.35) | A- (4.2) | — |
| powershell | sonnet46-200k-medium* | D+ (3.6min) | C+ ($0.39) | B+ (3.9) | — |
| default | opus46-200k-medium | D+ (3.5min) | D ($0.88) | A- (4.2) | — |
| powershell | opus46-200k-medium | D (4.3min) | D ($0.97) | B+ (4.1) | — |
| powershell-strict | sonnet46-200k-medium* | D- (6.1min) | D+ ($0.74) | B+ (4.0) | — |
| powershell-strict | opus46-200k-medium* | D (4.9min) | D- ($1.20) | B+ (3.9) | — |

</details>

- **Estimated time remaining:** 0.0min
- **Estimated total cost:** $99.03

## Failed / Timed-Out Runs

| Task | Language | Model | Duration | Reason | Lines | actionlint | act-result.txt |
|------|------|-------|----------|--------|-------|------------|----------------|
| Database Seed Script | default | sonnet46-200k-medium | 3.9min | exit_code=1 | 0 | n/a | no |
| Database Seed Script | powershell | sonnet46-200k-medium | 3.8min | exit_code=1 | 0 | n/a | no |
| Database Seed Script | powershell-strict | sonnet46-200k-medium | 3.6min | exit_code=1 | 0 | n/a | no |
| Error Retry Pipeline | default | sonnet46-200k-medium | 3.7min | exit_code=1 | 0 | n/a | no |
| Error Retry Pipeline | powershell | sonnet46-200k-medium | 3.8min | exit_code=1 | 0 | n/a | no |
| Error Retry Pipeline | powershell-strict | opus46-200k-medium | 9.7min | exit_code=143 | 425 | n/a | no |
| Error Retry Pipeline | powershell-strict | sonnet46-200k-medium | 3.8min | exit_code=1 | 0 | n/a | no |
| Multi-file Search and Replace | default | sonnet46-200k-medium | 3.9min | exit_code=1 | 0 | n/a | no |
| Multi-file Search and Replace | powershell-strict | sonnet46-200k-medium | 3.8min | exit_code=1 | 0 | n/a | no |
| Semantic Version Bumper | powershell-strict | sonnet46-200k-medium | 5.3min | exit_code=1 | 353 | n/a | no |
| Dependency License Checker | default | sonnet46-200k-medium | 4.0min | exit_code=1 | 0 | n/a | no |

*11 run(s) excluded from averages below.*

## Comparison by Language/Model/Effort
*(averages exclude failed/timed-out runs)*
*See [Notes](#notes) for scoring rubric and CLI version legend.*

| Language | Model | Runs | Avg Duration | Avg Duration Net of Traps | Avg Errors | Avg Turns | Avg Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| csharp-script | opus46-200k-medium | 2 | 1.8min | 1.8min | 0.0 | 10 | $0.42 | $0.84 | 4.0 | — |
| csharp-script | sonnet46-200k-medium | 1 | 0.6min | 0.6min | 0.0 | 7 | $0.12 | $0.12 | 4.0 | — |
| default | opus46-200k-medium | 18 | 3.5min | 3.5min | 1.1 | 32 | $0.88 | $15.75 | 4.2 | — |
| default | sonnet46-200k-medium* | 14 | 2.8min | 2.8min | 0.9 | 12 | $0.35 | $4.91 | 4.2 | — |
| powershell | opus46-200k-medium | 18 | 4.3min | 4.3min | 0.4 | 32 | $0.97 | $17.49 | 4.1 | — |
| powershell | sonnet46-200k-medium* | 16 | 3.6min | 3.6min | 0.0 | 11 | $0.39 | $6.32 | 3.9 | — |
| powershell-strict | opus46-200k-medium* | 17 | 4.9min | 4.9min | 0.8 | 37 | $1.20 | $20.45 | 3.9 | — |
| powershell-strict | sonnet46-200k-medium* | 14 | 6.1min | 6.1min | 0.1 | 17 | $0.74 | $10.31 | 4.0 | — |


<details>
<summary>Sorted by avg cost (cheapest first)</summary>

| Language | Model | Runs | Avg Duration | Avg Duration Net of Traps | Avg Errors | Avg Turns | Avg Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| csharp-script | sonnet46-200k-medium | 1 | 0.6min | 0.6min | 0.0 | 7 | $0.12 | $0.12 | 4.0 | — |
| default | sonnet46-200k-medium* | 14 | 2.8min | 2.8min | 0.9 | 12 | $0.35 | $4.91 | 4.2 | — |
| powershell | sonnet46-200k-medium* | 16 | 3.6min | 3.6min | 0.0 | 11 | $0.39 | $6.32 | 3.9 | — |
| csharp-script | opus46-200k-medium | 2 | 1.8min | 1.8min | 0.0 | 10 | $0.42 | $0.84 | 4.0 | — |
| powershell-strict | sonnet46-200k-medium* | 14 | 6.1min | 6.1min | 0.1 | 17 | $0.74 | $10.31 | 4.0 | — |
| default | opus46-200k-medium | 18 | 3.5min | 3.5min | 1.1 | 32 | $0.88 | $15.75 | 4.2 | — |
| powershell | opus46-200k-medium | 18 | 4.3min | 4.3min | 0.4 | 32 | $0.97 | $17.49 | 4.1 | — |
| powershell-strict | opus46-200k-medium* | 17 | 4.9min | 4.9min | 0.8 | 37 | $1.20 | $20.45 | 3.9 | — |

</details>

<details>
<summary>Sorted by avg duration (fastest first)</summary>

| Language | Model | Runs | Avg Duration | Avg Duration Net of Traps | Avg Errors | Avg Turns | Avg Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| csharp-script | sonnet46-200k-medium | 1 | 0.6min | 0.6min | 0.0 | 7 | $0.12 | $0.12 | 4.0 | — |
| csharp-script | opus46-200k-medium | 2 | 1.8min | 1.8min | 0.0 | 10 | $0.42 | $0.84 | 4.0 | — |
| default | sonnet46-200k-medium* | 14 | 2.8min | 2.8min | 0.9 | 12 | $0.35 | $4.91 | 4.2 | — |
| default | opus46-200k-medium | 18 | 3.5min | 3.5min | 1.1 | 32 | $0.88 | $15.75 | 4.2 | — |
| powershell | sonnet46-200k-medium* | 16 | 3.6min | 3.6min | 0.0 | 11 | $0.39 | $6.32 | 3.9 | — |
| powershell | opus46-200k-medium | 18 | 4.3min | 4.3min | 0.4 | 32 | $0.97 | $17.49 | 4.1 | — |
| powershell-strict | opus46-200k-medium* | 17 | 4.9min | 4.9min | 0.8 | 37 | $1.20 | $20.45 | 3.9 | — |
| powershell-strict | sonnet46-200k-medium* | 14 | 6.1min | 6.1min | 0.1 | 17 | $0.74 | $10.31 | 4.0 | — |

</details>

<details>
<summary>Sorted by avg duration net of traps (fastest first)</summary>

| Language | Model | Runs | Avg Duration | Avg Duration Net of Traps | Avg Errors | Avg Turns | Avg Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| csharp-script | sonnet46-200k-medium | 1 | 0.6min | 0.6min | 0.0 | 7 | $0.12 | $0.12 | 4.0 | — |
| csharp-script | opus46-200k-medium | 2 | 1.8min | 1.8min | 0.0 | 10 | $0.42 | $0.84 | 4.0 | — |
| default | sonnet46-200k-medium* | 14 | 2.8min | 2.8min | 0.9 | 12 | $0.35 | $4.91 | 4.2 | — |
| default | opus46-200k-medium | 18 | 3.5min | 3.5min | 1.1 | 32 | $0.88 | $15.75 | 4.2 | — |
| powershell | sonnet46-200k-medium* | 16 | 3.6min | 3.6min | 0.0 | 11 | $0.39 | $6.32 | 3.9 | — |
| powershell | opus46-200k-medium | 18 | 4.3min | 4.3min | 0.4 | 32 | $0.97 | $17.49 | 4.1 | — |
| powershell-strict | opus46-200k-medium* | 17 | 4.9min | 4.9min | 0.8 | 37 | $1.20 | $20.45 | 3.9 | — |
| powershell-strict | sonnet46-200k-medium* | 14 | 6.1min | 6.1min | 0.1 | 17 | $0.74 | $10.31 | 4.0 | — |

</details>

<details>
<summary>Sorted by avg errors (fewest first)</summary>

| Language | Model | Runs | Avg Duration | Avg Duration Net of Traps | Avg Errors | Avg Turns | Avg Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| csharp-script | opus46-200k-medium | 2 | 1.8min | 1.8min | 0.0 | 10 | $0.42 | $0.84 | 4.0 | — |
| csharp-script | sonnet46-200k-medium | 1 | 0.6min | 0.6min | 0.0 | 7 | $0.12 | $0.12 | 4.0 | — |
| powershell | sonnet46-200k-medium* | 16 | 3.6min | 3.6min | 0.0 | 11 | $0.39 | $6.32 | 3.9 | — |
| powershell-strict | sonnet46-200k-medium* | 14 | 6.1min | 6.1min | 0.1 | 17 | $0.74 | $10.31 | 4.0 | — |
| powershell | opus46-200k-medium | 18 | 4.3min | 4.3min | 0.4 | 32 | $0.97 | $17.49 | 4.1 | — |
| powershell-strict | opus46-200k-medium* | 17 | 4.9min | 4.9min | 0.8 | 37 | $1.20 | $20.45 | 3.9 | — |
| default | sonnet46-200k-medium* | 14 | 2.8min | 2.8min | 0.9 | 12 | $0.35 | $4.91 | 4.2 | — |
| default | opus46-200k-medium | 18 | 3.5min | 3.5min | 1.1 | 32 | $0.88 | $15.75 | 4.2 | — |

</details>

<details>
<summary>Sorted by avg turns (fewest first)</summary>

| Language | Model | Runs | Avg Duration | Avg Duration Net of Traps | Avg Errors | Avg Turns | Avg Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| csharp-script | sonnet46-200k-medium | 1 | 0.6min | 0.6min | 0.0 | 7 | $0.12 | $0.12 | 4.0 | — |
| csharp-script | opus46-200k-medium | 2 | 1.8min | 1.8min | 0.0 | 10 | $0.42 | $0.84 | 4.0 | — |
| powershell | sonnet46-200k-medium* | 16 | 3.6min | 3.6min | 0.0 | 11 | $0.39 | $6.32 | 3.9 | — |
| default | sonnet46-200k-medium* | 14 | 2.8min | 2.8min | 0.9 | 12 | $0.35 | $4.91 | 4.2 | — |
| powershell-strict | sonnet46-200k-medium* | 14 | 6.1min | 6.1min | 0.1 | 17 | $0.74 | $10.31 | 4.0 | — |
| default | opus46-200k-medium | 18 | 3.5min | 3.5min | 1.1 | 32 | $0.88 | $15.75 | 4.2 | — |
| powershell | opus46-200k-medium | 18 | 4.3min | 4.3min | 0.4 | 32 | $0.97 | $17.49 | 4.1 | — |
| powershell-strict | opus46-200k-medium* | 17 | 4.9min | 4.9min | 0.8 | 37 | $1.20 | $20.45 | 3.9 | — |

</details>

<details>
<summary>Sorted by LLM-as-judge score (best first)</summary>

| Language | Model | Runs | Avg Duration | Avg Duration Net of Traps | Avg Errors | Avg Turns | Avg Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| default | opus46-200k-medium | 18 | 3.5min | 3.5min | 1.1 | 32 | $0.88 | $15.75 | 4.2 | — |
| default | sonnet46-200k-medium* | 14 | 2.8min | 2.8min | 0.9 | 12 | $0.35 | $4.91 | 4.2 | — |
| powershell | opus46-200k-medium | 18 | 4.3min | 4.3min | 0.4 | 32 | $0.97 | $17.49 | 4.1 | — |
| csharp-script | opus46-200k-medium | 2 | 1.8min | 1.8min | 0.0 | 10 | $0.42 | $0.84 | 4.0 | — |
| csharp-script | sonnet46-200k-medium | 1 | 0.6min | 0.6min | 0.0 | 7 | $0.12 | $0.12 | 4.0 | — |
| powershell-strict | sonnet46-200k-medium* | 14 | 6.1min | 6.1min | 0.1 | 17 | $0.74 | $10.31 | 4.0 | — |
| powershell-strict | opus46-200k-medium* | 17 | 4.9min | 4.9min | 0.8 | 37 | $1.20 | $20.45 | 3.9 | — |
| powershell | sonnet46-200k-medium* | 16 | 3.6min | 3.6min | 0.0 | 11 | $0.39 | $6.32 | 3.9 | — |

</details>

<details>
<summary>Sorted by deliverable-quality score (best first)</summary>

| Language | Model | Runs | Avg Duration | Avg Duration Net of Traps | Avg Errors | Avg Turns | Avg Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| csharp-script | opus46-200k-medium | 2 | 1.8min | 1.8min | 0.0 | 10 | $0.42 | $0.84 | 4.0 | — |
| csharp-script | sonnet46-200k-medium | 1 | 0.6min | 0.6min | 0.0 | 7 | $0.12 | $0.12 | 4.0 | — |
| default | opus46-200k-medium | 18 | 3.5min | 3.5min | 1.1 | 32 | $0.88 | $15.75 | 4.2 | — |
| default | sonnet46-200k-medium* | 14 | 2.8min | 2.8min | 0.9 | 12 | $0.35 | $4.91 | 4.2 | — |
| powershell | opus46-200k-medium | 18 | 4.3min | 4.3min | 0.4 | 32 | $0.97 | $17.49 | 4.1 | — |
| powershell | sonnet46-200k-medium* | 16 | 3.6min | 3.6min | 0.0 | 11 | $0.39 | $6.32 | 3.9 | — |
| powershell-strict | opus46-200k-medium* | 17 | 4.9min | 4.9min | 0.8 | 37 | $1.20 | $20.45 | 3.9 | — |
| powershell-strict | sonnet46-200k-medium* | 14 | 6.1min | 6.1min | 0.1 | 17 | $0.74 | $10.31 | 4.0 | — |

</details>

## Savings Analysis

### Trap Analysis by Language/Model/Effort/Category

| Trap | Language | Model | Fell In | Time Lost | % of Time | $ Lost | % of $ |
|------|------|-------|---------|-----------|-----------|--------|--------|
| repeated-test-reruns | default | opus46-200k-medium-cli2.1.94 | 3 | 7.7min | 1.7% | $2.11 | 2.77% |
| repeated-test-reruns | default | opus46-200k-medium-cli2.1.96 | 10 | 19.3min | 4.2% | $4.79 | 6.28% |
| repeated-test-reruns | powershell | opus46-200k-medium-cli2.1.94 | 4 | 15.7min | 3.4% | $3.73 | 4.88% |
| repeated-test-reruns | powershell | opus46-200k-medium-cli2.1.96 | 13 | 27.3min | 6.0% | $6.16 | 8.07% |
| repeated-test-reruns | powershell | sonnet46-200k-medium-cli2.1.94 | 1 | 0.7min | 0.1% | $0.08 | 0.11% |
| repeated-test-reruns | powershell | sonnet46-200k-medium-cli2.1.96 | 1 | 0.7min | 0.1% | $0.09 | 0.12% |
| repeated-test-reruns | powershell-strict | opus46-200k-medium-cli2.1.94 | 4 | 8.7min | 1.9% | $1.97 | 2.59% |
| repeated-test-reruns | powershell-strict | opus46-200k-medium-cli2.1.96 | 13 | 40.0min | 8.7% | $10.22 | 13.38% |
| repeated-test-reruns | powershell-strict | sonnet46-200k-medium-cli2.1.94 | 2 | 2.3min | 0.5% | $0.32 | 0.42% |
| repeated-test-reruns | powershell-strict | sonnet46-200k-medium-cli2.1.96 | 4 | 3.3min | 0.7% | $0.44 | 0.57% |
| fixture-rework | powershell-strict | opus46-200k-medium-cli2.1.96 | 1 | 0.5min | 0.1% | $0.12 | 0.15% |


<details>
<summary>Sorted by time lost (least first)</summary>

| Trap | Language | Model | Fell In | Time Lost | % of Time | $ Lost | % of $ |
|------|------|-------|---------|-----------|-----------|--------|--------|
| fixture-rework | powershell-strict | opus46-200k-medium-cli2.1.96 | 1 | 0.5min | 0.1% | $0.12 | 0.15% |
| repeated-test-reruns | powershell | sonnet46-200k-medium-cli2.1.94 | 1 | 0.7min | 0.1% | $0.08 | 0.11% |
| repeated-test-reruns | powershell | sonnet46-200k-medium-cli2.1.96 | 1 | 0.7min | 0.1% | $0.09 | 0.12% |
| repeated-test-reruns | powershell-strict | sonnet46-200k-medium-cli2.1.94 | 2 | 2.3min | 0.5% | $0.32 | 0.42% |
| repeated-test-reruns | powershell-strict | sonnet46-200k-medium-cli2.1.96 | 4 | 3.3min | 0.7% | $0.44 | 0.57% |
| repeated-test-reruns | default | opus46-200k-medium-cli2.1.94 | 3 | 7.7min | 1.7% | $2.11 | 2.77% |
| repeated-test-reruns | powershell-strict | opus46-200k-medium-cli2.1.94 | 4 | 8.7min | 1.9% | $1.97 | 2.59% |
| repeated-test-reruns | powershell | opus46-200k-medium-cli2.1.94 | 4 | 15.7min | 3.4% | $3.73 | 4.88% |
| repeated-test-reruns | default | opus46-200k-medium-cli2.1.96 | 10 | 19.3min | 4.2% | $4.79 | 6.28% |
| repeated-test-reruns | powershell | opus46-200k-medium-cli2.1.96 | 13 | 27.3min | 6.0% | $6.16 | 8.07% |
| repeated-test-reruns | powershell-strict | opus46-200k-medium-cli2.1.96 | 13 | 40.0min | 8.7% | $10.22 | 13.38% |

</details>

<details>
<summary>Sorted by $ lost (least first)</summary>

| Trap | Language | Model | Fell In | Time Lost | % of Time | $ Lost | % of $ |
|------|------|-------|---------|-----------|-----------|--------|--------|
| repeated-test-reruns | powershell | sonnet46-200k-medium-cli2.1.94 | 1 | 0.7min | 0.1% | $0.08 | 0.11% |
| repeated-test-reruns | powershell | sonnet46-200k-medium-cli2.1.96 | 1 | 0.7min | 0.1% | $0.09 | 0.12% |
| fixture-rework | powershell-strict | opus46-200k-medium-cli2.1.96 | 1 | 0.5min | 0.1% | $0.12 | 0.15% |
| repeated-test-reruns | powershell-strict | sonnet46-200k-medium-cli2.1.94 | 2 | 2.3min | 0.5% | $0.32 | 0.42% |
| repeated-test-reruns | powershell-strict | sonnet46-200k-medium-cli2.1.96 | 4 | 3.3min | 0.7% | $0.44 | 0.57% |
| repeated-test-reruns | powershell-strict | opus46-200k-medium-cli2.1.94 | 4 | 8.7min | 1.9% | $1.97 | 2.59% |
| repeated-test-reruns | default | opus46-200k-medium-cli2.1.94 | 3 | 7.7min | 1.7% | $2.11 | 2.77% |
| repeated-test-reruns | powershell | opus46-200k-medium-cli2.1.94 | 4 | 15.7min | 3.4% | $3.73 | 4.88% |
| repeated-test-reruns | default | opus46-200k-medium-cli2.1.96 | 10 | 19.3min | 4.2% | $4.79 | 6.28% |
| repeated-test-reruns | powershell | opus46-200k-medium-cli2.1.96 | 13 | 27.3min | 6.0% | $6.16 | 8.07% |
| repeated-test-reruns | powershell-strict | opus46-200k-medium-cli2.1.96 | 13 | 40.0min | 8.7% | $10.22 | 13.38% |

</details>

<details>
<summary>Sorted by fell-in count (fewest first)</summary>

| Trap | Language | Model | Fell In | Time Lost | % of Time | $ Lost | % of $ |
|------|------|-------|---------|-----------|-----------|--------|--------|
| repeated-test-reruns | powershell | sonnet46-200k-medium-cli2.1.94 | 1 | 0.7min | 0.1% | $0.08 | 0.11% |
| repeated-test-reruns | powershell | sonnet46-200k-medium-cli2.1.96 | 1 | 0.7min | 0.1% | $0.09 | 0.12% |
| fixture-rework | powershell-strict | opus46-200k-medium-cli2.1.96 | 1 | 0.5min | 0.1% | $0.12 | 0.15% |
| repeated-test-reruns | powershell-strict | sonnet46-200k-medium-cli2.1.94 | 2 | 2.3min | 0.5% | $0.32 | 0.42% |
| repeated-test-reruns | default | opus46-200k-medium-cli2.1.94 | 3 | 7.7min | 1.7% | $2.11 | 2.77% |
| repeated-test-reruns | powershell | opus46-200k-medium-cli2.1.94 | 4 | 15.7min | 3.4% | $3.73 | 4.88% |
| repeated-test-reruns | powershell-strict | opus46-200k-medium-cli2.1.94 | 4 | 8.7min | 1.9% | $1.97 | 2.59% |
| repeated-test-reruns | powershell-strict | sonnet46-200k-medium-cli2.1.96 | 4 | 3.3min | 0.7% | $0.44 | 0.57% |
| repeated-test-reruns | default | opus46-200k-medium-cli2.1.96 | 10 | 19.3min | 4.2% | $4.79 | 6.28% |
| repeated-test-reruns | powershell | opus46-200k-medium-cli2.1.96 | 13 | 27.3min | 6.0% | $6.16 | 8.07% |
| repeated-test-reruns | powershell-strict | opus46-200k-medium-cli2.1.96 | 13 | 40.0min | 8.7% | $10.22 | 13.38% |

</details>

#### Trap Descriptions

- **fixture-rework**: Agent wrote, broke, and rewrote test fixture data (4+ fixture-related commands).
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
| csharp-script | opus46-200k-medium-cli2.1.96 | 2 | 0 | 0.0min | 0.0% | $0.00 | 0.00% |
| csharp-script | sonnet46-200k-medium-cli2.1.96 | 1 | 0 | 0.0min | 0.0% | $0.00 | 0.00% |
| default | opus46-200k-medium-cli2.1.94 | 5 | 3 | 7.7min | 1.7% | $2.11 | 2.77% |
| default | opus46-200k-medium-cli2.1.96 | 13 | 10 | 19.3min | 4.2% | $4.79 | 6.28% |
| default | sonnet46-200k-medium-cli2.1.94 | 4 | 0 | 0.0min | 0.0% | $0.00 | 0.00% |
| default | sonnet46-200k-medium-cli2.1.96 | 14 | 0 | 0.0min | 0.0% | $0.00 | 0.00% |
| powershell | opus46-200k-medium-cli2.1.94 | 4 | 4 | 15.7min | 3.4% | $3.73 | 4.88% |
| powershell | opus46-200k-medium-cli2.1.96 | 14 | 13 | 27.3min | 6.0% | $6.16 | 8.07% |
| powershell | sonnet46-200k-medium-cli2.1.94 | 4 | 1 | 0.7min | 0.1% | $0.08 | 0.11% |
| powershell | sonnet46-200k-medium-cli2.1.96 | 14 | 1 | 0.7min | 0.1% | $0.09 | 0.12% |
| powershell-strict | opus46-200k-medium-cli2.1.94 | 4 | 4 | 8.7min | 1.9% | $1.97 | 2.59% |
| powershell-strict | opus46-200k-medium-cli2.1.96 | 14 | 14 | 40.5min | 8.8% | $10.33 | 13.53% |
| powershell-strict | sonnet46-200k-medium-cli2.1.94 | 4 | 2 | 2.3min | 0.5% | $0.32 | 0.42% |
| powershell-strict | sonnet46-200k-medium-cli2.1.96 | 14 | 4 | 3.3min | 0.7% | $0.44 | 0.57% |


<details>
<summary>Sorted by time lost (least first)</summary>

| Language | Model | Runs | Traps | Time Lost | % of Time | $ Lost | % of $ |
|------|-------|------|-------|-----------|-----------|--------|--------|
| csharp-script | opus46-200k-medium-cli2.1.96 | 2 | 0 | 0.0min | 0.0% | $0.00 | 0.00% |
| csharp-script | sonnet46-200k-medium-cli2.1.96 | 1 | 0 | 0.0min | 0.0% | $0.00 | 0.00% |
| default | sonnet46-200k-medium-cli2.1.94 | 4 | 0 | 0.0min | 0.0% | $0.00 | 0.00% |
| default | sonnet46-200k-medium-cli2.1.96 | 14 | 0 | 0.0min | 0.0% | $0.00 | 0.00% |
| powershell | sonnet46-200k-medium-cli2.1.94 | 4 | 1 | 0.7min | 0.1% | $0.08 | 0.11% |
| powershell | sonnet46-200k-medium-cli2.1.96 | 14 | 1 | 0.7min | 0.1% | $0.09 | 0.12% |
| powershell-strict | sonnet46-200k-medium-cli2.1.94 | 4 | 2 | 2.3min | 0.5% | $0.32 | 0.42% |
| powershell-strict | sonnet46-200k-medium-cli2.1.96 | 14 | 4 | 3.3min | 0.7% | $0.44 | 0.57% |
| default | opus46-200k-medium-cli2.1.94 | 5 | 3 | 7.7min | 1.7% | $2.11 | 2.77% |
| powershell-strict | opus46-200k-medium-cli2.1.94 | 4 | 4 | 8.7min | 1.9% | $1.97 | 2.59% |
| powershell | opus46-200k-medium-cli2.1.94 | 4 | 4 | 15.7min | 3.4% | $3.73 | 4.88% |
| default | opus46-200k-medium-cli2.1.96 | 13 | 10 | 19.3min | 4.2% | $4.79 | 6.28% |
| powershell | opus46-200k-medium-cli2.1.96 | 14 | 13 | 27.3min | 6.0% | $6.16 | 8.07% |
| powershell-strict | opus46-200k-medium-cli2.1.96 | 14 | 14 | 40.5min | 8.8% | $10.33 | 13.53% |

</details>

<details>
<summary>Sorted by $ lost (least first)</summary>

| Language | Model | Runs | Traps | Time Lost | % of Time | $ Lost | % of $ |
|------|-------|------|-------|-----------|-----------|--------|--------|
| csharp-script | opus46-200k-medium-cli2.1.96 | 2 | 0 | 0.0min | 0.0% | $0.00 | 0.00% |
| csharp-script | sonnet46-200k-medium-cli2.1.96 | 1 | 0 | 0.0min | 0.0% | $0.00 | 0.00% |
| default | sonnet46-200k-medium-cli2.1.94 | 4 | 0 | 0.0min | 0.0% | $0.00 | 0.00% |
| default | sonnet46-200k-medium-cli2.1.96 | 14 | 0 | 0.0min | 0.0% | $0.00 | 0.00% |
| powershell | sonnet46-200k-medium-cli2.1.94 | 4 | 1 | 0.7min | 0.1% | $0.08 | 0.11% |
| powershell | sonnet46-200k-medium-cli2.1.96 | 14 | 1 | 0.7min | 0.1% | $0.09 | 0.12% |
| powershell-strict | sonnet46-200k-medium-cli2.1.94 | 4 | 2 | 2.3min | 0.5% | $0.32 | 0.42% |
| powershell-strict | sonnet46-200k-medium-cli2.1.96 | 14 | 4 | 3.3min | 0.7% | $0.44 | 0.57% |
| powershell-strict | opus46-200k-medium-cli2.1.94 | 4 | 4 | 8.7min | 1.9% | $1.97 | 2.59% |
| default | opus46-200k-medium-cli2.1.94 | 5 | 3 | 7.7min | 1.7% | $2.11 | 2.77% |
| powershell | opus46-200k-medium-cli2.1.94 | 4 | 4 | 15.7min | 3.4% | $3.73 | 4.88% |
| default | opus46-200k-medium-cli2.1.96 | 13 | 10 | 19.3min | 4.2% | $4.79 | 6.28% |
| powershell | opus46-200k-medium-cli2.1.96 | 14 | 13 | 27.3min | 6.0% | $6.16 | 8.07% |
| powershell-strict | opus46-200k-medium-cli2.1.96 | 14 | 14 | 40.5min | 8.8% | $10.33 | 13.53% |

</details>

### Prompt Cache Savings

| Status | Runs | $ Saved | % of $ |
|--------|------|---------|--------|
| Full hit (100%) | 0 | $0.00 | 0.00% |
| Partial | 102 | $5.46 | 7.15% |
| Miss | 9 | $0.00 | 0.00% |

## Test Quality Evaluation

### Structural Metrics by Language/Model/Effort

Automated analysis of test files: test count, assertion count, and test-to-code line ratio.

| Language | Model | Avg Tests | Avg Assertions | Avg Assert/Test | Avg Test:Code Ratio |
|------|-------|-----------|----------------|-----------------|---------------------|
| csharp-script | opus46-200k-medium | 56.0 | 56.0 | 1.0 | 2.08 |
| csharp-script | sonnet46-200k-medium | 0.0 | 0.0 | 0.0 | 1.76 |
| default | opus46-200k-medium | 25.1 | 43.6 | 1.7 | 1.49 |
| default | sonnet46-200k-medium | 19.6 | 30.6 | 1.6 | 0.97 |
| powershell | opus46-200k-medium | 23.8 | 44.2 | 1.9 | 1.39 |
| powershell | sonnet46-200k-medium | 21.2 | 36.6 | 1.7 | 1.11 |
| powershell-strict | opus46-200k-medium | 22.3 | 48.1 | 2.2 | 1.40 |
| powershell-strict | sonnet46-200k-medium | 27.0 | 45.6 | 1.7 | 0.51 |


<details>
<summary>Sorted by avg tests (most first)</summary>

| Language | Model | Avg Tests | Avg Assertions | Avg Assert/Test | Avg Test:Code Ratio |
|------|-------|-----------|----------------|-----------------|---------------------|
| csharp-script | opus46-200k-medium | 56.0 | 56.0 | 1.0 | 2.08 |
| powershell-strict | sonnet46-200k-medium | 27.0 | 45.6 | 1.7 | 0.51 |
| default | opus46-200k-medium | 25.1 | 43.6 | 1.7 | 1.49 |
| powershell | opus46-200k-medium | 23.8 | 44.2 | 1.9 | 1.39 |
| powershell-strict | opus46-200k-medium | 22.3 | 48.1 | 2.2 | 1.40 |
| powershell | sonnet46-200k-medium | 21.2 | 36.6 | 1.7 | 1.11 |
| default | sonnet46-200k-medium | 19.6 | 30.6 | 1.6 | 0.97 |
| csharp-script | sonnet46-200k-medium | 0.0 | 0.0 | 0.0 | 1.76 |

</details>

<details>
<summary>Sorted by avg assertions (most first)</summary>

| Language | Model | Avg Tests | Avg Assertions | Avg Assert/Test | Avg Test:Code Ratio |
|------|-------|-----------|----------------|-----------------|---------------------|
| csharp-script | opus46-200k-medium | 56.0 | 56.0 | 1.0 | 2.08 |
| powershell-strict | opus46-200k-medium | 22.3 | 48.1 | 2.2 | 1.40 |
| powershell-strict | sonnet46-200k-medium | 27.0 | 45.6 | 1.7 | 0.51 |
| powershell | opus46-200k-medium | 23.8 | 44.2 | 1.9 | 1.39 |
| default | opus46-200k-medium | 25.1 | 43.6 | 1.7 | 1.49 |
| powershell | sonnet46-200k-medium | 21.2 | 36.6 | 1.7 | 1.11 |
| default | sonnet46-200k-medium | 19.6 | 30.6 | 1.6 | 0.97 |
| csharp-script | sonnet46-200k-medium | 0.0 | 0.0 | 0.0 | 1.76 |

</details>

<details>
<summary>Sorted by avg test:code ratio (highest first)</summary>

| Language | Model | Avg Tests | Avg Assertions | Avg Assert/Test | Avg Test:Code Ratio |
|------|-------|-----------|----------------|-----------------|---------------------|
| csharp-script | opus46-200k-medium | 56.0 | 56.0 | 1.0 | 2.08 |
| csharp-script | sonnet46-200k-medium | 0.0 | 0.0 | 0.0 | 1.76 |
| default | opus46-200k-medium | 25.1 | 43.6 | 1.7 | 1.49 |
| powershell-strict | opus46-200k-medium | 22.3 | 48.1 | 2.2 | 1.40 |
| powershell | opus46-200k-medium | 23.8 | 44.2 | 1.9 | 1.39 |
| powershell | sonnet46-200k-medium | 21.2 | 36.6 | 1.7 | 1.11 |
| default | sonnet46-200k-medium | 19.6 | 30.6 | 1.6 | 0.97 |
| powershell-strict | sonnet46-200k-medium | 27.0 | 45.6 | 1.7 | 0.51 |

</details>


<details>
<summary>Per-run structural metrics</summary>

| Task | Language | Model | Tests | Assertions | Assert/Test | Test Lines | Impl Lines | Test:Code |
|------|------|-------|-------|------------|-------------|------------|------------|-----------|
| CSV Report Generator | csharp-script | opus46-200k-medium | 59 | 59 | 1.0 | 471 | 227 | 2.07 |
| CSV Report Generator | csharp-script | sonnet46-200k-medium | 0 | 0 | 0.0 | 450 | 256 | 1.76 |
| CSV Report Generator | default | opus46-200k-medium | 24 | 39 | 1.6 | 309 | 158 | 1.96 |
| CSV Report Generator | default | sonnet46-200k-medium | 38 | 43 | 1.1 | 314 | 220 | 1.43 |
| CSV Report Generator | powershell | opus46-200k-medium | 21 | 35 | 1.7 | 185 | 145 | 1.28 |
| CSV Report Generator | powershell | sonnet46-200k-medium | 25 | 34 | 1.4 | 243 | 178 | 1.37 |
| CSV Report Generator | powershell-strict | opus46-200k-medium | 24 | 37 | 1.5 | 223 | 218 | 1.02 |
| CSV Report Generator | powershell-strict | sonnet46-200k-medium | 30 | 44 | 1.5 | 272 | 0 | 0.00 |
| Log File Analyzer | csharp-script | opus46-200k-medium | 53 | 53 | 1.0 | 548 | 263 | 2.08 |
| Log File Analyzer | default | opus46-200k-medium | 21 | 52 | 2.5 | 262 | 194 | 1.35 |
| Log File Analyzer | default | sonnet46-200k-medium | 51 | 67 | 1.3 | 405 | 306 | 1.32 |
| Log File Analyzer | powershell | opus46-200k-medium | 18 | 55 | 3.1 | 216 | 227 | 0.95 |
| Log File Analyzer | powershell | sonnet46-200k-medium | 34 | 57 | 1.7 | 341 | 312 | 1.09 |
| Log File Analyzer | powershell-strict | opus46-200k-medium | 15 | 39 | 2.6 | 181 | 351 | 0.52 |
| Log File Analyzer | powershell-strict | sonnet46-200k-medium | 26 | 57 | 2.2 | 342 | 0 | 0.00 |
| Directory Tree Sync | default | opus46-200k-medium | 27 | 47 | 1.7 | 294 | 217 | 1.35 |
| Directory Tree Sync | default | sonnet46-200k-medium | 25 | 56 | 2.2 | 345 | 409 | 0.84 |
| Directory Tree Sync | powershell | opus46-200k-medium | 30 | 49 | 1.6 | 320 | 222 | 1.44 |
| Directory Tree Sync | powershell | sonnet46-200k-medium | 32 | 69 | 2.2 | 447 | 310 | 1.44 |
| Directory Tree Sync | powershell-strict | opus46-200k-medium | 28 | 65 | 2.3 | 384 | 244 | 1.57 |
| Directory Tree Sync | powershell-strict | sonnet46-200k-medium | 31 | 49 | 1.6 | 391 | 0 | 0.00 |
| REST API Client | default | opus46-200k-medium | 16 | 29 | 1.8 | 329 | 130 | 2.53 |
| REST API Client | default | sonnet46-200k-medium | 14 | 26 | 1.9 | 303 | 191 | 1.59 |
| REST API Client | powershell | opus46-200k-medium | 27 | 30 | 1.1 | 351 | 186 | 1.89 |
| REST API Client | powershell | sonnet46-200k-medium | 12 | 19 | 1.6 | 194 | 233 | 0.83 |
| REST API Client | powershell-strict | opus46-200k-medium | 21 | 22 | 1.0 | 353 | 45 | 7.84 |
| REST API Client | powershell-strict | sonnet46-200k-medium | 24 | 40 | 1.7 | 391 | 0 | 0.00 |
| Process Monitor | default | opus46-200k-medium | 16 | 40 | 2.5 | 184 | 220 | 0.84 |
| Process Monitor | default | sonnet46-200k-medium | 20 | 39 | 1.9 | 198 | 209 | 0.95 |
| Process Monitor | powershell | opus46-200k-medium | 19 | 48 | 2.5 | 197 | 195 | 1.01 |
| Process Monitor | powershell | sonnet46-200k-medium | 17 | 36 | 2.1 | 203 | 186 | 1.09 |
| Process Monitor | powershell-strict | opus46-200k-medium | 22 | 50 | 2.3 | 217 | 194 | 1.12 |
| Process Monitor | powershell-strict | sonnet46-200k-medium | 24 | 42 | 1.8 | 254 | 0 | 0.00 |
| Config File Migrator | default | opus46-200k-medium | 31 | 66 | 2.1 | 480 | 340 | 1.41 |
| Config File Migrator | default | sonnet46-200k-medium | 28 | 41 | 1.5 | 404 | 309 | 1.31 |
| Config File Migrator | powershell | opus46-200k-medium | 31 | 56 | 1.8 | 259 | 337 | 0.77 |
| Config File Migrator | powershell | sonnet46-200k-medium | 39 | 63 | 1.6 | 450 | 417 | 1.08 |
| Config File Migrator | powershell-strict | opus46-200k-medium | 27 | 63 | 2.3 | 415 | 321 | 1.29 |
| Config File Migrator | powershell-strict | sonnet46-200k-medium | 66 | 116 | 1.8 | 627 | 0 | 0.00 |
| Batch File Renamer | default | opus46-200k-medium | 20 | 40 | 2.0 | 269 | 173 | 1.55 |
| Batch File Renamer | default | sonnet46-200k-medium | 17 | 35 | 2.1 | 320 | 212 | 1.51 |
| Batch File Renamer | powershell | opus46-200k-medium | 14 | 38 | 2.7 | 252 | 99 | 2.55 |
| Batch File Renamer | powershell | sonnet46-200k-medium | 11 | 23 | 2.1 | 181 | 170 | 1.06 |
| Batch File Renamer | powershell-strict | opus46-200k-medium | 20 | 45 | 2.2 | 281 | 189 | 1.49 |
| Batch File Renamer | powershell-strict | sonnet46-200k-medium | 22 | 45 | 2.0 | 287 | 0 | 0.00 |
| Database Seed Script | default | opus46-200k-medium | 37 | 66 | 1.8 | 339 | 293 | 1.16 |
| Database Seed Script | default | sonnet46-200k-medium | 0 | 0 | 0.0 | 0 | 0 | 0.00 |
| Database Seed Script | powershell | opus46-200k-medium | 37 | 60 | 1.6 | 334 | 464 | 0.72 |
| Database Seed Script | powershell | sonnet46-200k-medium | 0 | 0 | 0.0 | 0 | 0 | 0.00 |
| Database Seed Script | powershell-strict | opus46-200k-medium | 28 | 79 | 2.8 | 398 | 558 | 0.71 |
| Database Seed Script | powershell-strict | sonnet46-200k-medium | 0 | 0 | 0.0 | 0 | 0 | 0.00 |
| Error Retry Pipeline | default | opus46-200k-medium | 15 | 37 | 2.5 | 229 | 144 | 1.59 |
| Error Retry Pipeline | default | sonnet46-200k-medium | 0 | 0 | 0.0 | 0 | 0 | 0.00 |
| Error Retry Pipeline | powershell | opus46-200k-medium | 16 | 44 | 2.8 | 233 | 135 | 1.73 |
| Error Retry Pipeline | powershell | sonnet46-200k-medium | 0 | 0 | 0.0 | 0 | 0 | 0.00 |
| Error Retry Pipeline | powershell-strict | opus46-200k-medium | 18 | 42 | 2.3 | 196 | 229 | 0.86 |
| Error Retry Pipeline | powershell-strict | sonnet46-200k-medium | 0 | 0 | 0.0 | 0 | 0 | 0.00 |
| Multi-file Search and Replace | default | opus46-200k-medium | 24 | 36 | 1.5 | 220 | 182 | 1.21 |
| Multi-file Search and Replace | default | sonnet46-200k-medium | 0 | 0 | 0.0 | 0 | 0 | 0.00 |
| Multi-file Search and Replace | powershell | opus46-200k-medium | 21 | 38 | 1.8 | 298 | 151 | 1.97 |
| Multi-file Search and Replace | powershell | sonnet46-200k-medium | 17 | 31 | 1.8 | 214 | 125 | 1.71 |
| Multi-file Search and Replace | powershell-strict | opus46-200k-medium | 17 | 39 | 2.3 | 286 | 213 | 1.34 |
| Multi-file Search and Replace | powershell-strict | sonnet46-200k-medium | 0 | 0 | 0.0 | 0 | 0 | 0.00 |
| Semantic Version Bumper | default | opus46-200k-medium | 44 | 52 | 1.2 | 310 | 196 | 1.58 |
| Semantic Version Bumper | default | sonnet46-200k-medium | 31 | 31 | 1.0 | 231 | 293 | 0.79 |
| Semantic Version Bumper | powershell | opus46-200k-medium | 24 | 52 | 2.2 | 241 | 201 | 1.20 |
| Semantic Version Bumper | powershell | sonnet46-200k-medium | 29 | 40 | 1.4 | 308 | 303 | 1.02 |
| Semantic Version Bumper | powershell-strict | opus46-200k-medium | 26 | 57 | 2.2 | 268 | 338 | 0.79 |
| Semantic Version Bumper | powershell-strict | sonnet46-200k-medium | 32 | 38 | 1.2 | 353 | 0 | 0.00 |
| PR Label Assigner | default | opus46-200k-medium | 24 | 22 | 0.9 | 218 | 160 | 1.36 |
| PR Label Assigner | default | sonnet46-200k-medium | 21 | 26 | 1.2 | 232 | 195 | 1.19 |
| PR Label Assigner | powershell | opus46-200k-medium | 18 | 33 | 1.8 | 212 | 146 | 1.45 |
| PR Label Assigner | powershell | sonnet46-200k-medium | 27 | 46 | 1.7 | 313 | 202 | 1.55 |
| PR Label Assigner | powershell-strict | opus46-200k-medium | 18 | 32 | 1.8 | 248 | 148 | 1.68 |
| PR Label Assigner | powershell-strict | sonnet46-200k-medium | 30 | 56 | 1.9 | 275 | 0 | 0.00 |
| Dependency License Checker | default | opus46-200k-medium | 29 | 51 | 1.8 | 367 | 227 | 1.62 |
| Dependency License Checker | default | sonnet46-200k-medium | 0 | 0 | 0.0 | 0 | 0 | 0.00 |
| Dependency License Checker | powershell | opus46-200k-medium | 17 | 52 | 3.1 | 319 | 228 | 1.40 |
| Dependency License Checker | powershell | sonnet46-200k-medium | 27 | 50 | 1.9 | 403 | 257 | 1.57 |
| Dependency License Checker | powershell-strict | opus46-200k-medium | 18 | 54 | 3.0 | 336 | 381 | 0.88 |
| Dependency License Checker | powershell-strict | sonnet46-200k-medium | 35 | 59 | 1.7 | 343 | 0 | 0.00 |
| Docker Image Tag Generator | default | opus46-200k-medium | 20 | 35 | 1.8 | 167 | 129 | 1.29 |
| Docker Image Tag Generator | default | sonnet46-200k-medium | 22 | 21 | 1.0 | 147 | 101 | 1.46 |
| Docker Image Tag Generator | powershell | opus46-200k-medium | 21 | 24 | 1.1 | 132 | 90 | 1.47 |
| Docker Image Tag Generator | powershell | sonnet46-200k-medium | 20 | 22 | 1.1 | 133 | 120 | 1.11 |
| Docker Image Tag Generator | powershell-strict | opus46-200k-medium | 17 | 23 | 1.4 | 202 | 147 | 1.37 |
| Docker Image Tag Generator | powershell-strict | sonnet46-200k-medium | 22 | 23 | 1.0 | 167 | 62 | 2.69 |
| Test Results Aggregator | default | opus46-200k-medium | 28 | 43 | 1.5 | 391 | 227 | 1.72 |
| Test Results Aggregator | default | sonnet46-200k-medium | 10 | 47 | 4.7 | 301 | 375 | 0.80 |
| Test Results Aggregator | powershell | opus46-200k-medium | 50 | 63 | 1.3 | 372 | 330 | 1.13 |
| Test Results Aggregator | powershell | sonnet46-200k-medium | 24 | 44 | 1.8 | 341 | 260 | 1.31 |
| Test Results Aggregator | powershell-strict | opus46-200k-medium | 35 | 60 | 1.7 | 343 | 0 | 0.00 |
| Test Results Aggregator | powershell-strict | sonnet46-200k-medium | 67 | 77 | 1.1 | 498 | 0 | 0.00 |
| Environment Matrix Generator | default | opus46-200k-medium | 37 | 57 | 1.5 | 441 | 215 | 2.05 |
| Environment Matrix Generator | default | sonnet46-200k-medium | 37 | 40 | 1.1 | 300 | 218 | 1.38 |
| Environment Matrix Generator | powershell | opus46-200k-medium | 21 | 33 | 1.6 | 293 | 161 | 1.82 |
| Environment Matrix Generator | powershell | sonnet46-200k-medium | 17 | 24 | 1.4 | 242 | 234 | 1.03 |
| Environment Matrix Generator | powershell-strict | opus46-200k-medium | 21 | 37 | 1.8 | 303 | 337 | 0.90 |
| Environment Matrix Generator | powershell-strict | sonnet46-200k-medium | 22 | 63 | 2.9 | 337 | 52 | 6.48 |
| Artifact Cleanup Script | default | opus46-200k-medium | 17 | 32 | 1.9 | 265 | 269 | 0.99 |
| Artifact Cleanup Script | default | sonnet46-200k-medium | 19 | 40 | 2.1 | 318 | 239 | 1.33 |
| Artifact Cleanup Script | powershell | opus46-200k-medium | 23 | 50 | 2.2 | 360 | 277 | 1.30 |
| Artifact Cleanup Script | powershell | sonnet46-200k-medium | 19 | 39 | 2.1 | 220 | 237 | 0.93 |
| Artifact Cleanup Script | powershell-strict | opus46-200k-medium | 28 | 73 | 2.6 | 348 | 373 | 0.93 |
| Artifact Cleanup Script | powershell-strict | sonnet46-200k-medium | 30 | 59 | 2.0 | 313 | 0 | 0.00 |
| Secret Rotation Validator | default | opus46-200k-medium | 22 | 41 | 1.9 | 268 | 203 | 1.32 |
| Secret Rotation Validator | default | sonnet46-200k-medium | 20 | 39 | 1.9 | 232 | 157 | 1.48 |
| Secret Rotation Validator | powershell | opus46-200k-medium | 21 | 35 | 1.7 | 239 | 241 | 0.99 |
| Secret Rotation Validator | powershell | sonnet46-200k-medium | 32 | 62 | 1.9 | 468 | 250 | 1.87 |
| Secret Rotation Validator | powershell-strict | opus46-200k-medium | 18 | 49 | 2.7 | 295 | 367 | 0.80 |
| Secret Rotation Validator | powershell-strict | sonnet46-200k-medium | 25 | 53 | 2.1 | 298 | 0 | 0.00 |

</details>

### LLM-as-Judge Scores

An LLM evaluates each test suite on four dimensions (1-5 scale):

- **Coverage** (1-5): Do tests exercise the key requirements? 1 = most untested, 5 = all covered.
- **Rigor** (1-5): Edge cases, error handling, boundary conditions? 1 = happy path only, 5 = thorough.
- **Design** (1-5): Test organization, fixtures, readability? 1 = messy/brittle, 5 = well-structured.
- **Overall** (1-5): Holistic quality — would you trust this suite to catch regressions? 1 = no, 5 = absolutely. Use this as the primary ranking metric.

| Language | Model | Avg Overall | Avg Coverage | Avg Rigor | Avg Design | Judge Cost |
|------|-------|-------------|-------------|-----------|------------|------------|
| csharp-script | opus46-200k-medium | **4.0** | 5.0 | 4.0 | 4.0 | $0.1328 |
| csharp-script | sonnet46-200k-medium | **4.0** | 5.0 | 3.0 | 4.0 | $0.0662 |
| default | opus46-200k-medium | **4.2** | 4.9 | 3.9 | 4.4 | $0.8973 |
| default | sonnet46-200k-medium | **4.2** | 4.6 | 3.5 | 4.5 | $0.7411 |
| powershell | opus46-200k-medium | **4.1** | 4.8 | 3.7 | 4.2 | $1.0395 |
| powershell | sonnet46-200k-medium | **3.9** | 4.2 | 3.2 | 4.1 | $0.9164 |
| powershell-strict | opus46-200k-medium | **3.9** | 4.7 | 3.6 | 3.9 | $1.1270 |
| powershell-strict | sonnet46-200k-medium | **4.0** | 4.9 | 3.7 | 4.3 | $0.7898 |
| **Total** | | | | | | **$5.7101** |


<details>
<summary>Sorted by avg overall (highest first)</summary>

| Language | Model | Avg Overall | Avg Coverage | Avg Rigor | Avg Design | Judge Cost |
|------|-------|-------------|-------------|-----------|------------|------------|
| default | opus46-200k-medium | **4.2** | 4.9 | 3.9 | 4.4 | $0.8973 |
| default | sonnet46-200k-medium | **4.2** | 4.6 | 3.5 | 4.5 | $0.7411 |
| powershell | opus46-200k-medium | **4.1** | 4.8 | 3.7 | 4.2 | $1.0395 |
| csharp-script | opus46-200k-medium | **4.0** | 5.0 | 4.0 | 4.0 | $0.1328 |
| csharp-script | sonnet46-200k-medium | **4.0** | 5.0 | 3.0 | 4.0 | $0.0662 |
| powershell-strict | sonnet46-200k-medium | **4.0** | 4.9 | 3.7 | 4.3 | $0.7898 |
| powershell-strict | opus46-200k-medium | **3.9** | 4.7 | 3.6 | 3.9 | $1.1270 |
| powershell | sonnet46-200k-medium | **3.9** | 4.2 | 3.2 | 4.1 | $0.9164 |

</details>

<details>
<summary>Sorted by avg coverage (highest first)</summary>

| Language | Model | Avg Overall | Avg Coverage | Avg Rigor | Avg Design | Judge Cost |
|------|-------|-------------|-------------|-----------|------------|------------|
| csharp-script | opus46-200k-medium | **4.0** | 5.0 | 4.0 | 4.0 | $0.1328 |
| csharp-script | sonnet46-200k-medium | **4.0** | 5.0 | 3.0 | 4.0 | $0.0662 |
| powershell-strict | sonnet46-200k-medium | **4.0** | 4.9 | 3.7 | 4.3 | $0.7898 |
| default | opus46-200k-medium | **4.2** | 4.9 | 3.9 | 4.4 | $0.8973 |
| powershell | opus46-200k-medium | **4.1** | 4.8 | 3.7 | 4.2 | $1.0395 |
| powershell-strict | opus46-200k-medium | **3.9** | 4.7 | 3.6 | 3.9 | $1.1270 |
| default | sonnet46-200k-medium | **4.2** | 4.6 | 3.5 | 4.5 | $0.7411 |
| powershell | sonnet46-200k-medium | **3.9** | 4.2 | 3.2 | 4.1 | $0.9164 |

</details>

<details>
<summary>Sorted by avg rigor (highest first)</summary>

| Language | Model | Avg Overall | Avg Coverage | Avg Rigor | Avg Design | Judge Cost |
|------|-------|-------------|-------------|-----------|------------|------------|
| csharp-script | opus46-200k-medium | **4.0** | 5.0 | 4.0 | 4.0 | $0.1328 |
| default | opus46-200k-medium | **4.2** | 4.9 | 3.9 | 4.4 | $0.8973 |
| powershell | opus46-200k-medium | **4.1** | 4.8 | 3.7 | 4.2 | $1.0395 |
| powershell-strict | sonnet46-200k-medium | **4.0** | 4.9 | 3.7 | 4.3 | $0.7898 |
| powershell-strict | opus46-200k-medium | **3.9** | 4.7 | 3.6 | 3.9 | $1.1270 |
| default | sonnet46-200k-medium | **4.2** | 4.6 | 3.5 | 4.5 | $0.7411 |
| powershell | sonnet46-200k-medium | **3.9** | 4.2 | 3.2 | 4.1 | $0.9164 |
| csharp-script | sonnet46-200k-medium | **4.0** | 5.0 | 3.0 | 4.0 | $0.0662 |

</details>

<details>
<summary>Sorted by avg design (highest first)</summary>

| Language | Model | Avg Overall | Avg Coverage | Avg Rigor | Avg Design | Judge Cost |
|------|-------|-------------|-------------|-----------|------------|------------|
| default | sonnet46-200k-medium | **4.2** | 4.6 | 3.5 | 4.5 | $0.7411 |
| default | opus46-200k-medium | **4.2** | 4.9 | 3.9 | 4.4 | $0.8973 |
| powershell-strict | sonnet46-200k-medium | **4.0** | 4.9 | 3.7 | 4.3 | $0.7898 |
| powershell | opus46-200k-medium | **4.1** | 4.8 | 3.7 | 4.2 | $1.0395 |
| powershell | sonnet46-200k-medium | **3.9** | 4.2 | 3.2 | 4.1 | $0.9164 |
| csharp-script | opus46-200k-medium | **4.0** | 5.0 | 4.0 | 4.0 | $0.1328 |
| csharp-script | sonnet46-200k-medium | **4.0** | 5.0 | 3.0 | 4.0 | $0.0662 |
| powershell-strict | opus46-200k-medium | **3.9** | 4.7 | 3.6 | 3.9 | $1.1270 |

</details>


<details>
<summary>Per-run LLM judge scores</summary>

| Task | Language | Model | Cov | Rig | Des | Ovr | Summary |
|------|------|-------|-----|-----|-----|-----|---------|
| CSV Report Generator | csharp-script | opus46-200k-medium | 5.0 | 4.0 | 4.0 | 4.0 |  |
| CSV Report Generator | csharp-script | sonnet46-200k-medium | 5.0 | 3.0 | 4.0 | 4.0 |  |
| CSV Report Generator | default | opus46-200k-medium | 5.0 | 4.0 | 5.0 | 5.0 |  |
| CSV Report Generator | default | sonnet46-200k-medium | 5.0 | 4.0 | 5.0 | 4.0 |  |
| CSV Report Generator | powershell | opus46-200k-medium | 5.0 | 3.0 | 4.0 | 4.0 |  |
| CSV Report Generator | powershell | sonnet46-200k-medium | 4.0 | 3.0 | 3.0 | 3.0 |  |
| CSV Report Generator | powershell-strict | opus46-200k-medium | 4.0 | 3.0 | 4.0 | 4.0 |  |
| CSV Report Generator | powershell-strict | sonnet46-200k-medium | 5.0 | 3.0 | 4.0 | 4.0 |  |
| Log File Analyzer | csharp-script | opus46-200k-medium | 5.0 | 4.0 | 4.0 | 4.0 |  |
| Log File Analyzer | default | opus46-200k-medium | 5.0 | 4.0 | 5.0 | 5.0 |  |
| Log File Analyzer | default | sonnet46-200k-medium | 5.0 | 4.0 | 5.0 | 5.0 |  |
| Log File Analyzer | powershell | opus46-200k-medium | 4.0 | 3.0 | 4.0 | 4.0 |  |
| Log File Analyzer | powershell | sonnet46-200k-medium | 5.0 | 3.0 | 4.0 | 4.0 |  |
| Log File Analyzer | powershell-strict | opus46-200k-medium | 4.0 | 3.0 | 4.0 | 4.0 |  |
| Log File Analyzer | powershell-strict | sonnet46-200k-medium | 5.0 | 3.0 | 4.0 | 4.0 |  |
| Directory Tree Sync | default | opus46-200k-medium | 5.0 | 4.0 | 4.0 | 4.0 |  |
| Directory Tree Sync | default | sonnet46-200k-medium | 5.0 | 4.0 | 5.0 | 5.0 |  |
| Directory Tree Sync | powershell | opus46-200k-medium | 5.0 | 4.0 | 5.0 | 4.0 |  |
| Directory Tree Sync | powershell | sonnet46-200k-medium | 5.0 | 4.0 | 5.0 | 4.0 |  |
| Directory Tree Sync | powershell-strict | opus46-200k-medium | 5.0 | 4.0 | 4.0 | 4.0 |  |
| Directory Tree Sync | powershell-strict | sonnet46-200k-medium | 5.0 | 4.0 | 5.0 | 4.0 |  |
| REST API Client | default | opus46-200k-medium | 5.0 | 5.0 | 5.0 | 5.0 |  |
| REST API Client | default | sonnet46-200k-medium | 5.0 | 4.0 | 5.0 | 5.0 |  |
| REST API Client | powershell | opus46-200k-medium | 5.0 | 4.0 | 3.0 | 4.0 |  |
| REST API Client | powershell | sonnet46-200k-medium | 4.0 | 3.0 | 3.0 | 3.0 |  |
| REST API Client | powershell-strict | opus46-200k-medium | 5.0 | 4.0 | 4.0 | 4.0 |  |
| REST API Client | powershell-strict | sonnet46-200k-medium | 5.0 | 4.0 | 5.0 | 4.0 |  |
| Process Monitor | default | opus46-200k-medium | 4.0 | 3.0 | 3.0 | 3.0 |  |
| Process Monitor | default | sonnet46-200k-medium | 5.0 | 3.0 | 4.0 | 4.0 |  |
| Process Monitor | powershell | opus46-200k-medium | 4.0 | 4.0 | 4.0 | 4.0 |  |
| Process Monitor | powershell | sonnet46-200k-medium | 5.0 | 3.0 | 4.0 | 4.0 |  |
| Process Monitor | powershell-strict | opus46-200k-medium | 5.0 | 4.0 | 4.0 | 4.0 |  |
| Process Monitor | powershell-strict | sonnet46-200k-medium | 5.0 | 4.0 | 5.0 | 4.0 |  |
| Config File Migrator | default | opus46-200k-medium | 5.0 | 4.0 | 5.0 | 4.0 |  |
| Config File Migrator | default | sonnet46-200k-medium | 4.0 | 4.0 | 5.0 | 4.0 |  |
| Config File Migrator | powershell | opus46-200k-medium | 4.0 | 3.0 | 4.0 | 4.0 |  |
| Config File Migrator | powershell | sonnet46-200k-medium | 4.0 | 3.0 | 4.0 | 4.0 |  |
| Config File Migrator | powershell-strict | opus46-200k-medium | 4.0 | 3.0 | 4.0 | 4.0 |  |
| Config File Migrator | powershell-strict | sonnet46-200k-medium | 5.0 | 4.0 | 4.0 | 4.0 |  |
| Batch File Renamer | default | opus46-200k-medium | 5.0 | 4.0 | 4.0 | 4.0 |  |
| Batch File Renamer | default | sonnet46-200k-medium | 5.0 | 3.0 | 4.0 | 4.0 |  |
| Batch File Renamer | powershell | opus46-200k-medium | 5.0 | 4.0 | 5.0 | 4.0 |  |
| Batch File Renamer | powershell | sonnet46-200k-medium | 3.0 | 2.0 | 3.0 | 3.0 |  |
| Batch File Renamer | powershell-strict | opus46-200k-medium | 4.0 | 4.0 | 4.0 | 4.0 |  |
| Batch File Renamer | powershell-strict | sonnet46-200k-medium | 4.0 | 3.0 | 4.0 | 4.0 |  |
| Database Seed Script | default | opus46-200k-medium | 5.0 | 4.0 | 5.0 | 5.0 |  |
| Database Seed Script | powershell | opus46-200k-medium | 5.0 | 4.0 | 4.0 | 4.0 |  |
| Database Seed Script | powershell-strict | opus46-200k-medium | 5.0 | 4.0 | 4.0 | 4.0 |  |
| Error Retry Pipeline | default | opus46-200k-medium | 5.0 | 3.0 | 4.0 | 4.0 |  |
| Error Retry Pipeline | powershell | opus46-200k-medium | 5.0 | 4.0 | 4.0 | 4.0 |  |
| Error Retry Pipeline | powershell-strict | opus46-200k-medium | 5.0 | 3.0 | 4.0 | 4.0 |  |
| Multi-file Search and Replace | default | opus46-200k-medium | 5.0 | 4.0 | 4.0 | 4.0 |  |
| Multi-file Search and Replace | powershell | opus46-200k-medium | 5.0 | 4.0 | 4.0 | 4.0 |  |
| Multi-file Search and Replace | powershell | sonnet46-200k-medium | 4.0 | 3.0 | 4.0 | 4.0 |  |
| Multi-file Search and Replace | powershell-strict | opus46-200k-medium | 4.0 | 3.0 | 3.0 | 3.0 |  |
| Semantic Version Bumper | default | opus46-200k-medium | 5.0 | 4.0 | 5.0 | 4.0 |  |
| Semantic Version Bumper | default | sonnet46-200k-medium | 5.0 | 4.0 | 4.0 | 4.0 |  |
| Semantic Version Bumper | powershell | opus46-200k-medium | 5.0 | 3.0 | 4.0 | 4.0 |  |
| Semantic Version Bumper | powershell | sonnet46-200k-medium | 4.0 | 3.0 | 4.0 | 4.0 |  |
| Semantic Version Bumper | powershell-strict | opus46-200k-medium | 5.0 | 4.0 | 4.0 | 4.0 |  |
| Semantic Version Bumper | powershell-strict | sonnet46-200k-medium | 5.0 | 4.0 | 4.0 | 4.0 |  |
| PR Label Assigner | default | opus46-200k-medium | 5.0 | 4.0 | 4.0 | 4.0 |  |
| PR Label Assigner | default | sonnet46-200k-medium | 5.0 | 4.0 | 5.0 | 5.0 |  |
| PR Label Assigner | powershell | opus46-200k-medium | 5.0 | 4.0 | 4.0 | 4.0 |  |
| PR Label Assigner | powershell | sonnet46-200k-medium | 5.0 | 4.0 | 5.0 | 4.0 |  |
| PR Label Assigner | powershell-strict | opus46-200k-medium | 4.0 | 3.0 | 4.0 | 4.0 |  |
| PR Label Assigner | powershell-strict | sonnet46-200k-medium | 5.0 | 4.0 | 5.0 | 4.0 |  |
| Dependency License Checker | default | opus46-200k-medium | 5.0 | 4.0 | 5.0 | 5.0 |  |
| Dependency License Checker | powershell | opus46-200k-medium | 5.0 | 4.0 | 5.0 | 5.0 |  |
| Dependency License Checker | powershell | sonnet46-200k-medium | 5.0 | 4.0 | 5.0 | 5.0 |  |
| Dependency License Checker | powershell-strict | opus46-200k-medium | 5.0 | 3.0 | 4.0 | 4.0 |  |
| Dependency License Checker | powershell-strict | sonnet46-200k-medium | 5.0 | 4.0 | 5.0 | 4.0 |  |
| Docker Image Tag Generator | default | opus46-200k-medium | 5.0 | 4.0 | 5.0 | 4.0 |  |
| Docker Image Tag Generator | default | sonnet46-200k-medium | 5.0 | 4.0 | 5.0 | 4.0 |  |
| Docker Image Tag Generator | powershell | opus46-200k-medium | 5.0 | 4.0 | 5.0 | 4.0 |  |
| Docker Image Tag Generator | powershell | sonnet46-200k-medium | 4.0 | 4.0 | 5.0 | 4.0 |  |
| Docker Image Tag Generator | powershell-strict | opus46-200k-medium | 5.0 | 4.0 | 4.0 | 4.0 |  |
| Docker Image Tag Generator | powershell-strict | sonnet46-200k-medium | 5.0 | 3.0 | 4.0 | 4.0 |  |
| Test Results Aggregator | default | opus46-200k-medium | 5.0 | 3.0 | 4.0 | 4.0 |  |
| Test Results Aggregator | default | sonnet46-200k-medium | 4.0 | 2.0 | 3.0 | 3.0 |  |
| Test Results Aggregator | powershell | opus46-200k-medium | 5.0 | 3.0 | 4.0 | 4.0 |  |
| Test Results Aggregator | powershell | sonnet46-200k-medium | 4.0 | 3.0 | 4.0 | 4.0 |  |
| Test Results Aggregator | powershell-strict | opus46-200k-medium | 5.0 | 3.0 | 4.0 | 4.0 |  |
| Test Results Aggregator | powershell-strict | sonnet46-200k-medium | 5.0 | 4.0 | 4.0 | 4.0 |  |
| Environment Matrix Generator | default | opus46-200k-medium | 5.0 | 4.0 | 4.0 | 4.0 |  |
| Environment Matrix Generator | default | sonnet46-200k-medium | 4.0 | 3.0 | 5.0 | 4.0 |  |
| Environment Matrix Generator | powershell | opus46-200k-medium | 5.0 | 4.0 | 5.0 | 4.0 |  |
| Environment Matrix Generator | powershell | sonnet46-200k-medium | 4.0 | 3.0 | 5.0 | 4.0 |  |
| Environment Matrix Generator | powershell-strict | opus46-200k-medium | 5.0 | 4.0 | 4.0 | 4.0 |  |
| Environment Matrix Generator | powershell-strict | sonnet46-200k-medium | 5.0 | 3.0 | 4.0 | 4.0 |  |
| Artifact Cleanup Script | default | opus46-200k-medium | 5.0 | 4.0 | 5.0 | 4.0 |  |
| Artifact Cleanup Script | default | sonnet46-200k-medium | 4.0 | 3.0 | 4.0 | 4.0 |  |
| Artifact Cleanup Script | powershell | opus46-200k-medium | 5.0 | 4.0 | 4.0 | 4.0 |  |
| Artifact Cleanup Script | powershell | sonnet46-200k-medium | 4.0 | 3.0 | 4.0 | 4.0 |  |
| Artifact Cleanup Script | powershell-strict | opus46-200k-medium | 5.0 | 4.0 | 4.0 | 4.0 |  |
| Artifact Cleanup Script | powershell-strict | sonnet46-200k-medium | 5.0 | 4.0 | 4.0 | 4.0 |  |
| Secret Rotation Validator | default | opus46-200k-medium | 4.0 | 4.0 | 4.0 | 4.0 |  |
| Secret Rotation Validator | default | sonnet46-200k-medium | 4.0 | 3.0 | 4.0 | 4.0 |  |
| Secret Rotation Validator | powershell | opus46-200k-medium | 5.0 | 4.0 | 4.0 | 4.0 |  |
| Secret Rotation Validator | powershell | sonnet46-200k-medium | 4.0 | 4.0 | 4.0 | 4.0 |  |
| Secret Rotation Validator | powershell-strict | opus46-200k-medium | 5.0 | 4.0 | 4.0 | 4.0 |  |
| Secret Rotation Validator | powershell-strict | sonnet46-200k-medium | 5.0 | 4.0 | 4.0 | 4.0 |  |

</details>

### Correlation: Structural Metrics vs Tests Quality

Spearman rank correlation between automated counts and LLM judge scores.
Values near +1.0 indicate the LLM agrees with the structural signal; near 0 means no relationship.

| Structural Metric | vs Coverage | vs Rigor | vs Design | vs Overall |
|-------------------|------------|---------|----------|-----------|
| Test count | 0.25 | 0.27 | 0.19 | 0.16 |
| Assertion count | 0.15 | 0.11 | 0.05 | 0.15 |
| Test:code ratio | 0.1 | 0.15 | 0.13 | 0.21 |

*Based on 102 runs with both structural and LLM scores.*

### LLM vs Structural Discrepancies

**Probable counter gaps** — structural counters may be missing a test pattern. Investigate and fix `test_quality.py`.

| Task | Language | Model | Tests | Asserts | Cov | Rig | Des | Ovr | Flag |
|------|------|-------|-------|---------|-----|-----|-----|-----|------|
| CSV Report Generator | csharp-script | sonnet46-200k-medium | 0 | 0 | 5.0 | 3.0 | 4.0 | 4.0 | LLM says high coverage (5.0/5) but only 0 tests detected |
| CSV Report Generator | csharp-script | sonnet46-200k-medium | 0 | 0 | 5.0 | 3.0 | 4.0 | 4.0 | LLM says high overall (4.0/5) but 0 tests detected |

**Qualitative disagreements** — structural metrics look reasonable; the LLM judge is weighing factors the counters can't measure.

| Task | Language | Model | Tests | Asserts | Cov | Rig | Des | Ovr | Flag | Justification |
|------|------|-------|-------|---------|-----|-----|-----|-----|------|---------------|
| Test Results Aggregator | default | sonnet46-200k-medium | 10 | 47 | 4.0 | 2.0 | 3.0 | 3.0 | LLM says low rigor (2.0/5) but 47 assertions detected |  |

## Per-Run Results

*Tests Quality = Overall (1-5) from LLM-as-judge of generated test code (dimensions: coverage, rigor, design). `—` = no judge data.*

| Task | Language | Model | Duration | Turns | Errors | Cost | Tests Quality | Chosen | Status |
|------|----------|-------|----------|-------|--------|------|-----------|--------|--------|
| Artifact Cleanup Script | default | opus46-200k-medium | 4.4min | 34 | 0 | $0.98 | 4.0 | python | ok |
| Artifact Cleanup Script | default | sonnet46-200k-medium | 2.6min | 17 | 4 | $0.44 | 4.0 | python | ok |
| Artifact Cleanup Script | powershell | opus46-200k-medium | 4.9min | 30 | 0 | $1.16 | 4.0 | powershell | ok |
| Artifact Cleanup Script | powershell | sonnet46-200k-medium | 2.6min | 9 | 0 | $0.35 | 4.0 | powershell | ok |
| Artifact Cleanup Script | powershell-strict | opus46-200k-medium | 5.5min | 37 | 1 | $1.37 | 4.0 | powershell | ok |
| Artifact Cleanup Script | powershell-strict | sonnet46-200k-medium | 3.6min | 15 | 0 | $0.49 | 4.0 | powershell | ok |
| Batch File Renamer | default | opus46-200k-medium | 2.8min | 30 | 2 | $0.81 | 4.0 | python | ok |
| Batch File Renamer | default | sonnet46-200k-medium | 2.3min | 8 | 0 | $0.22 | 4.0 | python | ok |
| Batch File Renamer | powershell | opus46-200k-medium | 3.0min | 21 | 0 | $0.59 | 4.0 | powershell | ok |
| Batch File Renamer | powershell | sonnet46-200k-medium | 1.4min | 6 | 0 | $0.16 | 3.0 | powershell | ok |
| Batch File Renamer | powershell-strict | opus46-200k-medium | 4.5min | 35 | 0 | $1.05 | 4.0 | powershell | ok |
| Batch File Renamer | powershell-strict | sonnet46-200k-medium | 3.7min | 16 | 1 | $0.50 | 4.0 | powershell | ok |
| CSV Report Generator | csharp-script | opus46-200k-medium | 2.8min | 12 | 0 | $0.58 | 4.0 | csharp | ok |
| CSV Report Generator | csharp-script | sonnet46-200k-medium | 0.6min | 7 | 0 | $0.12 | 4.0 | csharp | ok |
| CSV Report Generator | default | opus46-200k-medium | 1.7min | 12 | 0 | $0.38 | 5.0 | python | ok |
| CSV Report Generator | default | sonnet46-200k-medium | 6.3min | 1 | 3 | $0.71 | 4.0 | python | ok |
| CSV Report Generator | powershell | opus46-200k-medium | 4.3min | 37 | 0 | $1.05 | 4.0 | powershell | ok |
| CSV Report Generator | powershell | sonnet46-200k-medium | 2.1min | 9 | 0 | $0.31 | 3.0 | powershell | ok |
| CSV Report Generator | powershell-strict | opus46-200k-medium | 4.3min | 40 | 1 | $1.04 | 4.0 | powershell | ok |
| CSV Report Generator | powershell-strict | sonnet46-200k-medium | 6.5min | 29 | 0 | $0.97 | 4.0 | powershell | ok |
| Config File Migrator | default | opus46-200k-medium | 2.8min | 14 | 1 | $0.59 | 4.0 | python | ok |
| Config File Migrator | default | sonnet46-200k-medium | 3.4min | 18 | 1 | $0.47 | 4.0 | python | ok |
| Config File Migrator | powershell | opus46-200k-medium | 3.7min | 20 | 0 | $0.69 | 4.0 | powershell | ok |
| Config File Migrator | powershell | sonnet46-200k-medium | 3.4min | 15 | 0 | $0.38 | 4.0 | powershell | ok |
| Config File Migrator | powershell-strict | opus46-200k-medium | 2.7min | 12 | 0 | $0.49 | 4.0 | powershell | ok |
| Config File Migrator | powershell-strict | sonnet46-200k-medium | 13.9min | 21 | 0 | $1.60 | 4.0 | powershell | ok |
| Database Seed Script | default | opus46-200k-medium | 4.3min | 36 | 1 | $1.04 | 5.0 | python | ok |
| Database Seed Script | default | sonnet46-200k-medium | 3.9min | 1 | 0 | $0.00 | — |  | failed |
| Database Seed Script | powershell | opus46-200k-medium | 5.8min | 42 | 4 | $1.32 | 4.0 | powershell | ok |
| Database Seed Script | powershell | sonnet46-200k-medium | 3.8min | 1 | 0 | $0.00 | — | powershell | failed |
| Database Seed Script | powershell-strict | opus46-200k-medium | 8.7min | 56 | 2 | $2.03 | 4.0 | powershell | ok |
| Database Seed Script | powershell-strict | sonnet46-200k-medium | 3.6min | 1 | 0 | $0.00 | — | powershell | failed |
| Dependency License Checker | default | opus46-200k-medium | 5.6min | 64 | 4 | $1.73 | 5.0 | python | ok |
| Dependency License Checker | default | sonnet46-200k-medium | 4.0min | 1 | 0 | $0.00 | — |  | failed |
| Dependency License Checker | powershell | opus46-200k-medium | 5.8min | 45 | 1 | $1.37 | 5.0 | powershell | ok |
| Dependency License Checker | powershell | sonnet46-200k-medium | 2.6min | 11 | 0 | $0.36 | 5.0 | powershell | ok |
| Dependency License Checker | powershell-strict | opus46-200k-medium | 5.4min | 52 | 4 | $1.59 | 4.0 | powershell | ok |
| Dependency License Checker | powershell-strict | sonnet46-200k-medium | 9.5min | 18 | 0 | $0.97 | 4.0 | powershell | ok |
| Directory Tree Sync | default | opus46-200k-medium | 3.8min | 43 | 0 | $1.18 | 4.0 | python | ok |
| Directory Tree Sync | default | sonnet46-200k-medium | 3.9min | 11 | 1 | $0.45 | 5.0 | python | ok |
| Directory Tree Sync | powershell | opus46-200k-medium | 5.3min | 42 | 0 | $1.13 | 4.0 | powershell | ok |
| Directory Tree Sync | powershell | sonnet46-200k-medium | 3.0min | 11 | 0 | $0.37 | 4.0 | powershell | ok |
| Directory Tree Sync | powershell-strict | opus46-200k-medium | 5.4min | 34 | 0 | $1.21 | 4.0 | powershell | ok |
| Directory Tree Sync | powershell-strict | sonnet46-200k-medium | 4.3min | 13 | 0 | $0.49 | 4.0 | powershell | ok |
| Docker Image Tag Generator | default | opus46-200k-medium | 2.7min | 30 | 0 | $0.67 | 4.0 | python | ok |
| Docker Image Tag Generator | default | sonnet46-200k-medium | 1.8min | 10 | 1 | $0.23 | 4.0 | python | ok |
| Docker Image Tag Generator | powershell | opus46-200k-medium | 3.5min | 32 | 0 | $0.84 | 4.0 | powershell | ok |
| Docker Image Tag Generator | powershell | sonnet46-200k-medium | 2.9min | 9 | 0 | $0.31 | 4.0 | powershell | ok |
| Docker Image Tag Generator | powershell-strict | opus46-200k-medium | 5.0min | 44 | 0 | $1.28 | 4.0 | powershell | ok |
| Docker Image Tag Generator | powershell-strict | sonnet46-200k-medium | 2.5min | 13 | 0 | $0.33 | 4.0 | powershell | ok |
| Environment Matrix Generator | default | opus46-200k-medium | 4.7min | 38 | 1 | $1.11 | 4.0 | python | ok |
| Environment Matrix Generator | default | sonnet46-200k-medium | 2.0min | 9 | 0 | $0.26 | 4.0 | python | ok |
| Environment Matrix Generator | powershell | opus46-200k-medium | 2.3min | 18 | 0 | $0.54 | 4.0 | powershell | ok |
| Environment Matrix Generator | powershell | sonnet46-200k-medium | 2.8min | 13 | 0 | $0.36 | 4.0 | powershell | ok |
| Environment Matrix Generator | powershell-strict | opus46-200k-medium | 4.2min | 31 | 2 | $0.96 | 4.0 | powershell | ok |
| Environment Matrix Generator | powershell-strict | sonnet46-200k-medium | 5.4min | 16 | 0 | $0.62 | 4.0 | powershell | ok |
| Error Retry Pipeline | default | opus46-200k-medium | 2.3min | 24 | 0 | $0.54 | 4.0 | python | ok |
| Error Retry Pipeline | default | sonnet46-200k-medium | 3.7min | 1 | 0 | $0.00 | — |  | failed |
| Error Retry Pipeline | powershell | opus46-200k-medium | 3.8min | 34 | 0 | $0.93 | 4.0 | powershell | ok |
| Error Retry Pipeline | powershell | sonnet46-200k-medium | 3.8min | 1 | 0 | $0.00 | — | powershell | failed |
| Error Retry Pipeline | powershell-strict | opus46-200k-medium | 9.7min | 0 | 1 | $0.00 | 4.0 | powershell | failed |
| Error Retry Pipeline | powershell-strict | sonnet46-200k-medium | 3.8min | 1 | 0 | $0.00 | — | powershell | failed |
| Log File Analyzer | csharp-script | opus46-200k-medium | 0.7min | 9 | 0 | $0.25 | 4.0 | csharp | ok |
| Log File Analyzer | default | opus46-200k-medium | 4.2min | 43 | 0 | $1.18 | 5.0 | python | ok |
| Log File Analyzer | default | sonnet46-200k-medium | 2.9min | 19 | 0 | $0.48 | 5.0 | python | ok |
| Log File Analyzer | powershell | opus46-200k-medium | 4.6min | 41 | 0 | $1.14 | 4.0 | powershell | ok |
| Log File Analyzer | powershell | sonnet46-200k-medium | 3.9min | 10 | 0 | $0.44 | 4.0 | powershell | ok |
| Log File Analyzer | powershell-strict | opus46-200k-medium | 4.5min | 31 | 1 | $0.95 | 4.0 | powershell | ok |
| Log File Analyzer | powershell-strict | sonnet46-200k-medium | 3.8min | 14 | 1 | $0.50 | 4.0 | powershell | ok |
| Multi-file Search and Replace | default | opus46-200k-medium | 3.1min | 25 | 3 | $0.70 | 4.0 | python | ok |
| Multi-file Search and Replace | default | sonnet46-200k-medium | 3.9min | 1 | 0 | $0.00 | — |  | failed |
| Multi-file Search and Replace | powershell | opus46-200k-medium | 3.6min | 21 | 0 | $0.65 | 4.0 | powershell | ok |
| Multi-file Search and Replace | powershell | sonnet46-200k-medium | 1.4min | 10 | 0 | $0.19 | 4.0 | powershell | ok |
| Multi-file Search and Replace | powershell-strict | opus46-200k-medium | 4.1min | 34 | 0 | $1.09 | 3.0 | powershell | ok |
| Multi-file Search and Replace | powershell-strict | sonnet46-200k-medium | 3.8min | 1 | 0 | $0.00 | — | powershell | failed |
| PR Label Assigner | default | opus46-200k-medium | 1.9min | 11 | 1 | $0.38 | 4.0 | python | ok |
| PR Label Assigner | default | sonnet46-200k-medium | 1.8min | 8 | 0 | $0.21 | 5.0 | python | ok |
| PR Label Assigner | powershell | opus46-200k-medium | 3.1min | 23 | 0 | $0.61 | 4.0 | powershell | ok |
| PR Label Assigner | powershell | sonnet46-200k-medium | 3.7min | 10 | 0 | $0.38 | 4.0 | powershell | ok |
| PR Label Assigner | powershell-strict | opus46-200k-medium | 4.0min | 37 | 0 | $1.03 | 4.0 | powershell | ok |
| PR Label Assigner | powershell-strict | sonnet46-200k-medium | 3.3min | 12 | 0 | $0.35 | 4.0 | powershell | ok |
| Process Monitor | default | opus46-200k-medium | 3.3min | 40 | 1 | $1.00 | 3.0 | python | ok |
| Process Monitor | default | sonnet46-200k-medium | 2.0min | 12 | 0 | $0.25 | 4.0 | python | ok |
| Process Monitor | powershell | opus46-200k-medium | 5.4min | 39 | 0 | $1.21 | 4.0 | powershell | ok |
| Process Monitor | powershell | sonnet46-200k-medium | 3.8min | 13 | 0 | $0.40 | 4.0 | powershell | ok |
| Process Monitor | powershell-strict | opus46-200k-medium | 5.6min | 53 | 0 | $1.61 | 4.0 | powershell | ok |
| Process Monitor | powershell-strict | sonnet46-200k-medium | 4.6min | 19 | 0 | $0.54 | 4.0 | powershell | ok |
| REST API Client | default | opus46-200k-medium | 5.2min | 45 | 0 | $1.21 | 5.0 | python | ok |
| REST API Client | default | sonnet46-200k-medium | 1.8min | 9 | 1 | $0.23 | 5.0 | python | ok |
| REST API Client | powershell | opus46-200k-medium | 7.2min | 51 | 1 | $1.82 | 4.0 | powershell | ok |
| REST API Client | powershell | sonnet46-200k-medium | 12.6min | 13 | 0 | $0.96 | 3.0 | powershell | ok |
| REST API Client | powershell-strict | opus46-200k-medium | 5.1min | 19 | 0 | $0.94 | 4.0 | powershell | ok |
| REST API Client | powershell-strict | sonnet46-200k-medium | 9.2min | 14 | 0 | $0.99 | 4.0 | powershell | ok |
| Secret Rotation Validator | default | opus46-200k-medium | 2.6min | 17 | 0 | $0.51 | 4.0 | python | ok |
| Secret Rotation Validator | default | sonnet46-200k-medium | 1.5min | 11 | 0 | $0.22 | 4.0 | python | ok |
| Secret Rotation Validator | powershell | opus46-200k-medium | 3.3min | 23 | 1 | $0.72 | 4.0 | powershell | ok |
| Secret Rotation Validator | powershell | sonnet46-200k-medium | 3.5min | 11 | 0 | $0.48 | 4.0 | powershell | ok |
| Secret Rotation Validator | powershell-strict | opus46-200k-medium | 5.3min | 39 | 2 | $1.27 | 4.0 | powershell | ok |
| Secret Rotation Validator | powershell-strict | sonnet46-200k-medium | 4.0min | 20 | 0 | $0.53 | 4.0 | powershell | ok |
| Semantic Version Bumper | default | opus46-200k-medium | 4.8min | 47 | 5 | $1.23 | 4.0 | python | ok |
| Semantic Version Bumper | default | sonnet46-200k-medium | 2.5min | 11 | 0 | $0.25 | 4.0 | python | ok |
| Semantic Version Bumper | powershell | opus46-200k-medium | 3.6min | 27 | 0 | $0.77 | 4.0 | powershell | ok |
| Semantic Version Bumper | powershell | sonnet46-200k-medium | 2.7min | 16 | 0 | $0.33 | 4.0 | powershell | ok |
| Semantic Version Bumper | powershell-strict | opus46-200k-medium | 5.8min | 52 | 0 | $1.57 | 4.0 | powershell | ok |
| Semantic Version Bumper | powershell-strict | sonnet46-200k-medium | 5.3min | 5 | 0 | $0.15 | 4.0 | powershell | failed |
| Test Results Aggregator | default | opus46-200k-medium | 2.3min | 15 | 1 | $0.51 | 4.0 | python | ok |
| Test Results Aggregator | default | sonnet46-200k-medium | 4.0min | 20 | 1 | $0.49 | 3.0 | python | ok |
| Test Results Aggregator | powershell | opus46-200k-medium | 4.3min | 33 | 0 | $0.95 | 4.0 | powershell | ok |
| Test Results Aggregator | powershell | sonnet46-200k-medium | 5.0min | 15 | 0 | $0.55 | 4.0 | powershell | ok |
| Test Results Aggregator | powershell-strict | opus46-200k-medium | 4.0min | 24 | 0 | $0.95 | 4.0 | powershell | ok |
| Test Results Aggregator | powershell-strict | sonnet46-200k-medium | 11.5min | 20 | 0 | $1.42 | 4.0 | powershell | ok |


<details>
<summary>Sorted by cost (cheapest first)</summary>

| Task | Language | Model | Duration | Turns | Errors | Cost | Tests Quality | Chosen | Status |
|------|----------|-------|----------|-------|--------|------|-----------|--------|--------|
| Database Seed Script | default | sonnet46-200k-medium | 3.9min | 1 | 0 | $0.00 | — |  | failed |
| Database Seed Script | powershell | sonnet46-200k-medium | 3.8min | 1 | 0 | $0.00 | — | powershell | failed |
| Database Seed Script | powershell-strict | sonnet46-200k-medium | 3.6min | 1 | 0 | $0.00 | — | powershell | failed |
| Error Retry Pipeline | default | sonnet46-200k-medium | 3.7min | 1 | 0 | $0.00 | — |  | failed |
| Error Retry Pipeline | powershell | sonnet46-200k-medium | 3.8min | 1 | 0 | $0.00 | — | powershell | failed |
| Error Retry Pipeline | powershell-strict | opus46-200k-medium | 9.7min | 0 | 1 | $0.00 | 4.0 | powershell | failed |
| Error Retry Pipeline | powershell-strict | sonnet46-200k-medium | 3.8min | 1 | 0 | $0.00 | — | powershell | failed |
| Multi-file Search and Replace | default | sonnet46-200k-medium | 3.9min | 1 | 0 | $0.00 | — |  | failed |
| Multi-file Search and Replace | powershell-strict | sonnet46-200k-medium | 3.8min | 1 | 0 | $0.00 | — | powershell | failed |
| Dependency License Checker | default | sonnet46-200k-medium | 4.0min | 1 | 0 | $0.00 | — |  | failed |
| CSV Report Generator | csharp-script | sonnet46-200k-medium | 0.6min | 7 | 0 | $0.12 | 4.0 | csharp | ok |
| Semantic Version Bumper | powershell-strict | sonnet46-200k-medium | 5.3min | 5 | 0 | $0.15 | 4.0 | powershell | failed |
| Batch File Renamer | powershell | sonnet46-200k-medium | 1.4min | 6 | 0 | $0.16 | 3.0 | powershell | ok |
| Multi-file Search and Replace | powershell | sonnet46-200k-medium | 1.4min | 10 | 0 | $0.19 | 4.0 | powershell | ok |
| PR Label Assigner | default | sonnet46-200k-medium | 1.8min | 8 | 0 | $0.21 | 5.0 | python | ok |
| Secret Rotation Validator | default | sonnet46-200k-medium | 1.5min | 11 | 0 | $0.22 | 4.0 | python | ok |
| Batch File Renamer | default | sonnet46-200k-medium | 2.3min | 8 | 0 | $0.22 | 4.0 | python | ok |
| REST API Client | default | sonnet46-200k-medium | 1.8min | 9 | 1 | $0.23 | 5.0 | python | ok |
| Docker Image Tag Generator | default | sonnet46-200k-medium | 1.8min | 10 | 1 | $0.23 | 4.0 | python | ok |
| Semantic Version Bumper | default | sonnet46-200k-medium | 2.5min | 11 | 0 | $0.25 | 4.0 | python | ok |
| Process Monitor | default | sonnet46-200k-medium | 2.0min | 12 | 0 | $0.25 | 4.0 | python | ok |
| Log File Analyzer | csharp-script | opus46-200k-medium | 0.7min | 9 | 0 | $0.25 | 4.0 | csharp | ok |
| Environment Matrix Generator | default | sonnet46-200k-medium | 2.0min | 9 | 0 | $0.26 | 4.0 | python | ok |
| CSV Report Generator | powershell | sonnet46-200k-medium | 2.1min | 9 | 0 | $0.31 | 3.0 | powershell | ok |
| Docker Image Tag Generator | powershell | sonnet46-200k-medium | 2.9min | 9 | 0 | $0.31 | 4.0 | powershell | ok |
| Semantic Version Bumper | powershell | sonnet46-200k-medium | 2.7min | 16 | 0 | $0.33 | 4.0 | powershell | ok |
| Docker Image Tag Generator | powershell-strict | sonnet46-200k-medium | 2.5min | 13 | 0 | $0.33 | 4.0 | powershell | ok |
| Artifact Cleanup Script | powershell | sonnet46-200k-medium | 2.6min | 9 | 0 | $0.35 | 4.0 | powershell | ok |
| PR Label Assigner | powershell-strict | sonnet46-200k-medium | 3.3min | 12 | 0 | $0.35 | 4.0 | powershell | ok |
| Environment Matrix Generator | powershell | sonnet46-200k-medium | 2.8min | 13 | 0 | $0.36 | 4.0 | powershell | ok |
| Dependency License Checker | powershell | sonnet46-200k-medium | 2.6min | 11 | 0 | $0.36 | 5.0 | powershell | ok |
| Directory Tree Sync | powershell | sonnet46-200k-medium | 3.0min | 11 | 0 | $0.37 | 4.0 | powershell | ok |
| PR Label Assigner | default | opus46-200k-medium | 1.9min | 11 | 1 | $0.38 | 4.0 | python | ok |
| CSV Report Generator | default | opus46-200k-medium | 1.7min | 12 | 0 | $0.38 | 5.0 | python | ok |
| Config File Migrator | powershell | sonnet46-200k-medium | 3.4min | 15 | 0 | $0.38 | 4.0 | powershell | ok |
| PR Label Assigner | powershell | sonnet46-200k-medium | 3.7min | 10 | 0 | $0.38 | 4.0 | powershell | ok |
| Process Monitor | powershell | sonnet46-200k-medium | 3.8min | 13 | 0 | $0.40 | 4.0 | powershell | ok |
| Artifact Cleanup Script | default | sonnet46-200k-medium | 2.6min | 17 | 4 | $0.44 | 4.0 | python | ok |
| Log File Analyzer | powershell | sonnet46-200k-medium | 3.9min | 10 | 0 | $0.44 | 4.0 | powershell | ok |
| Directory Tree Sync | default | sonnet46-200k-medium | 3.9min | 11 | 1 | $0.45 | 5.0 | python | ok |
| Config File Migrator | default | sonnet46-200k-medium | 3.4min | 18 | 1 | $0.47 | 4.0 | python | ok |
| Secret Rotation Validator | powershell | sonnet46-200k-medium | 3.5min | 11 | 0 | $0.48 | 4.0 | powershell | ok |
| Log File Analyzer | default | sonnet46-200k-medium | 2.9min | 19 | 0 | $0.48 | 5.0 | python | ok |
| Artifact Cleanup Script | powershell-strict | sonnet46-200k-medium | 3.6min | 15 | 0 | $0.49 | 4.0 | powershell | ok |
| Config File Migrator | powershell-strict | opus46-200k-medium | 2.7min | 12 | 0 | $0.49 | 4.0 | powershell | ok |
| Directory Tree Sync | powershell-strict | sonnet46-200k-medium | 4.3min | 13 | 0 | $0.49 | 4.0 | powershell | ok |
| Test Results Aggregator | default | sonnet46-200k-medium | 4.0min | 20 | 1 | $0.49 | 3.0 | python | ok |
| Batch File Renamer | powershell-strict | sonnet46-200k-medium | 3.7min | 16 | 1 | $0.50 | 4.0 | powershell | ok |
| Log File Analyzer | powershell-strict | sonnet46-200k-medium | 3.8min | 14 | 1 | $0.50 | 4.0 | powershell | ok |
| Test Results Aggregator | default | opus46-200k-medium | 2.3min | 15 | 1 | $0.51 | 4.0 | python | ok |
| Secret Rotation Validator | default | opus46-200k-medium | 2.6min | 17 | 0 | $0.51 | 4.0 | python | ok |
| Secret Rotation Validator | powershell-strict | sonnet46-200k-medium | 4.0min | 20 | 0 | $0.53 | 4.0 | powershell | ok |
| Process Monitor | powershell-strict | sonnet46-200k-medium | 4.6min | 19 | 0 | $0.54 | 4.0 | powershell | ok |
| Environment Matrix Generator | powershell | opus46-200k-medium | 2.3min | 18 | 0 | $0.54 | 4.0 | powershell | ok |
| Error Retry Pipeline | default | opus46-200k-medium | 2.3min | 24 | 0 | $0.54 | 4.0 | python | ok |
| Test Results Aggregator | powershell | sonnet46-200k-medium | 5.0min | 15 | 0 | $0.55 | 4.0 | powershell | ok |
| CSV Report Generator | csharp-script | opus46-200k-medium | 2.8min | 12 | 0 | $0.58 | 4.0 | csharp | ok |
| Config File Migrator | default | opus46-200k-medium | 2.8min | 14 | 1 | $0.59 | 4.0 | python | ok |
| Batch File Renamer | powershell | opus46-200k-medium | 3.0min | 21 | 0 | $0.59 | 4.0 | powershell | ok |
| PR Label Assigner | powershell | opus46-200k-medium | 3.1min | 23 | 0 | $0.61 | 4.0 | powershell | ok |
| Environment Matrix Generator | powershell-strict | sonnet46-200k-medium | 5.4min | 16 | 0 | $0.62 | 4.0 | powershell | ok |
| Multi-file Search and Replace | powershell | opus46-200k-medium | 3.6min | 21 | 0 | $0.65 | 4.0 | powershell | ok |
| Docker Image Tag Generator | default | opus46-200k-medium | 2.7min | 30 | 0 | $0.67 | 4.0 | python | ok |
| Config File Migrator | powershell | opus46-200k-medium | 3.7min | 20 | 0 | $0.69 | 4.0 | powershell | ok |
| Multi-file Search and Replace | default | opus46-200k-medium | 3.1min | 25 | 3 | $0.70 | 4.0 | python | ok |
| CSV Report Generator | default | sonnet46-200k-medium | 6.3min | 1 | 3 | $0.71 | 4.0 | python | ok |
| Secret Rotation Validator | powershell | opus46-200k-medium | 3.3min | 23 | 1 | $0.72 | 4.0 | powershell | ok |
| Semantic Version Bumper | powershell | opus46-200k-medium | 3.6min | 27 | 0 | $0.77 | 4.0 | powershell | ok |
| Batch File Renamer | default | opus46-200k-medium | 2.8min | 30 | 2 | $0.81 | 4.0 | python | ok |
| Docker Image Tag Generator | powershell | opus46-200k-medium | 3.5min | 32 | 0 | $0.84 | 4.0 | powershell | ok |
| Error Retry Pipeline | powershell | opus46-200k-medium | 3.8min | 34 | 0 | $0.93 | 4.0 | powershell | ok |
| REST API Client | powershell-strict | opus46-200k-medium | 5.1min | 19 | 0 | $0.94 | 4.0 | powershell | ok |
| Log File Analyzer | powershell-strict | opus46-200k-medium | 4.5min | 31 | 1 | $0.95 | 4.0 | powershell | ok |
| Test Results Aggregator | powershell-strict | opus46-200k-medium | 4.0min | 24 | 0 | $0.95 | 4.0 | powershell | ok |
| Test Results Aggregator | powershell | opus46-200k-medium | 4.3min | 33 | 0 | $0.95 | 4.0 | powershell | ok |
| REST API Client | powershell | sonnet46-200k-medium | 12.6min | 13 | 0 | $0.96 | 3.0 | powershell | ok |
| Environment Matrix Generator | powershell-strict | opus46-200k-medium | 4.2min | 31 | 2 | $0.96 | 4.0 | powershell | ok |
| Dependency License Checker | powershell-strict | sonnet46-200k-medium | 9.5min | 18 | 0 | $0.97 | 4.0 | powershell | ok |
| CSV Report Generator | powershell-strict | sonnet46-200k-medium | 6.5min | 29 | 0 | $0.97 | 4.0 | powershell | ok |
| Artifact Cleanup Script | default | opus46-200k-medium | 4.4min | 34 | 0 | $0.98 | 4.0 | python | ok |
| REST API Client | powershell-strict | sonnet46-200k-medium | 9.2min | 14 | 0 | $0.99 | 4.0 | powershell | ok |
| Process Monitor | default | opus46-200k-medium | 3.3min | 40 | 1 | $1.00 | 3.0 | python | ok |
| PR Label Assigner | powershell-strict | opus46-200k-medium | 4.0min | 37 | 0 | $1.03 | 4.0 | powershell | ok |
| Database Seed Script | default | opus46-200k-medium | 4.3min | 36 | 1 | $1.04 | 5.0 | python | ok |
| CSV Report Generator | powershell-strict | opus46-200k-medium | 4.3min | 40 | 1 | $1.04 | 4.0 | powershell | ok |
| CSV Report Generator | powershell | opus46-200k-medium | 4.3min | 37 | 0 | $1.05 | 4.0 | powershell | ok |
| Batch File Renamer | powershell-strict | opus46-200k-medium | 4.5min | 35 | 0 | $1.05 | 4.0 | powershell | ok |
| Multi-file Search and Replace | powershell-strict | opus46-200k-medium | 4.1min | 34 | 0 | $1.09 | 3.0 | powershell | ok |
| Environment Matrix Generator | default | opus46-200k-medium | 4.7min | 38 | 1 | $1.11 | 4.0 | python | ok |
| Directory Tree Sync | powershell | opus46-200k-medium | 5.3min | 42 | 0 | $1.13 | 4.0 | powershell | ok |
| Log File Analyzer | powershell | opus46-200k-medium | 4.6min | 41 | 0 | $1.14 | 4.0 | powershell | ok |
| Artifact Cleanup Script | powershell | opus46-200k-medium | 4.9min | 30 | 0 | $1.16 | 4.0 | powershell | ok |
| Directory Tree Sync | default | opus46-200k-medium | 3.8min | 43 | 0 | $1.18 | 4.0 | python | ok |
| Log File Analyzer | default | opus46-200k-medium | 4.2min | 43 | 0 | $1.18 | 5.0 | python | ok |
| Process Monitor | powershell | opus46-200k-medium | 5.4min | 39 | 0 | $1.21 | 4.0 | powershell | ok |
| Directory Tree Sync | powershell-strict | opus46-200k-medium | 5.4min | 34 | 0 | $1.21 | 4.0 | powershell | ok |
| REST API Client | default | opus46-200k-medium | 5.2min | 45 | 0 | $1.21 | 5.0 | python | ok |
| Semantic Version Bumper | default | opus46-200k-medium | 4.8min | 47 | 5 | $1.23 | 4.0 | python | ok |
| Secret Rotation Validator | powershell-strict | opus46-200k-medium | 5.3min | 39 | 2 | $1.27 | 4.0 | powershell | ok |
| Docker Image Tag Generator | powershell-strict | opus46-200k-medium | 5.0min | 44 | 0 | $1.28 | 4.0 | powershell | ok |
| Database Seed Script | powershell | opus46-200k-medium | 5.8min | 42 | 4 | $1.32 | 4.0 | powershell | ok |
| Artifact Cleanup Script | powershell-strict | opus46-200k-medium | 5.5min | 37 | 1 | $1.37 | 4.0 | powershell | ok |
| Dependency License Checker | powershell | opus46-200k-medium | 5.8min | 45 | 1 | $1.37 | 5.0 | powershell | ok |
| Test Results Aggregator | powershell-strict | sonnet46-200k-medium | 11.5min | 20 | 0 | $1.42 | 4.0 | powershell | ok |
| Semantic Version Bumper | powershell-strict | opus46-200k-medium | 5.8min | 52 | 0 | $1.57 | 4.0 | powershell | ok |
| Dependency License Checker | powershell-strict | opus46-200k-medium | 5.4min | 52 | 4 | $1.59 | 4.0 | powershell | ok |
| Config File Migrator | powershell-strict | sonnet46-200k-medium | 13.9min | 21 | 0 | $1.60 | 4.0 | powershell | ok |
| Process Monitor | powershell-strict | opus46-200k-medium | 5.6min | 53 | 0 | $1.61 | 4.0 | powershell | ok |
| Dependency License Checker | default | opus46-200k-medium | 5.6min | 64 | 4 | $1.73 | 5.0 | python | ok |
| REST API Client | powershell | opus46-200k-medium | 7.2min | 51 | 1 | $1.82 | 4.0 | powershell | ok |
| Database Seed Script | powershell-strict | opus46-200k-medium | 8.7min | 56 | 2 | $2.03 | 4.0 | powershell | ok |

</details>

<details>
<summary>Sorted by duration (fastest first)</summary>

| Task | Language | Model | Duration | Turns | Errors | Cost | Tests Quality | Chosen | Status |
|------|----------|-------|----------|-------|--------|------|-----------|--------|--------|
| CSV Report Generator | csharp-script | sonnet46-200k-medium | 0.6min | 7 | 0 | $0.12 | 4.0 | csharp | ok |
| Log File Analyzer | csharp-script | opus46-200k-medium | 0.7min | 9 | 0 | $0.25 | 4.0 | csharp | ok |
| Batch File Renamer | powershell | sonnet46-200k-medium | 1.4min | 6 | 0 | $0.16 | 3.0 | powershell | ok |
| Multi-file Search and Replace | powershell | sonnet46-200k-medium | 1.4min | 10 | 0 | $0.19 | 4.0 | powershell | ok |
| Secret Rotation Validator | default | sonnet46-200k-medium | 1.5min | 11 | 0 | $0.22 | 4.0 | python | ok |
| CSV Report Generator | default | opus46-200k-medium | 1.7min | 12 | 0 | $0.38 | 5.0 | python | ok |
| PR Label Assigner | default | sonnet46-200k-medium | 1.8min | 8 | 0 | $0.21 | 5.0 | python | ok |
| Docker Image Tag Generator | default | sonnet46-200k-medium | 1.8min | 10 | 1 | $0.23 | 4.0 | python | ok |
| REST API Client | default | sonnet46-200k-medium | 1.8min | 9 | 1 | $0.23 | 5.0 | python | ok |
| PR Label Assigner | default | opus46-200k-medium | 1.9min | 11 | 1 | $0.38 | 4.0 | python | ok |
| Process Monitor | default | sonnet46-200k-medium | 2.0min | 12 | 0 | $0.25 | 4.0 | python | ok |
| Environment Matrix Generator | default | sonnet46-200k-medium | 2.0min | 9 | 0 | $0.26 | 4.0 | python | ok |
| CSV Report Generator | powershell | sonnet46-200k-medium | 2.1min | 9 | 0 | $0.31 | 3.0 | powershell | ok |
| Batch File Renamer | default | sonnet46-200k-medium | 2.3min | 8 | 0 | $0.22 | 4.0 | python | ok |
| Test Results Aggregator | default | opus46-200k-medium | 2.3min | 15 | 1 | $0.51 | 4.0 | python | ok |
| Error Retry Pipeline | default | opus46-200k-medium | 2.3min | 24 | 0 | $0.54 | 4.0 | python | ok |
| Environment Matrix Generator | powershell | opus46-200k-medium | 2.3min | 18 | 0 | $0.54 | 4.0 | powershell | ok |
| Semantic Version Bumper | default | sonnet46-200k-medium | 2.5min | 11 | 0 | $0.25 | 4.0 | python | ok |
| Docker Image Tag Generator | powershell-strict | sonnet46-200k-medium | 2.5min | 13 | 0 | $0.33 | 4.0 | powershell | ok |
| Dependency License Checker | powershell | sonnet46-200k-medium | 2.6min | 11 | 0 | $0.36 | 5.0 | powershell | ok |
| Artifact Cleanup Script | powershell | sonnet46-200k-medium | 2.6min | 9 | 0 | $0.35 | 4.0 | powershell | ok |
| Artifact Cleanup Script | default | sonnet46-200k-medium | 2.6min | 17 | 4 | $0.44 | 4.0 | python | ok |
| Secret Rotation Validator | default | opus46-200k-medium | 2.6min | 17 | 0 | $0.51 | 4.0 | python | ok |
| Semantic Version Bumper | powershell | sonnet46-200k-medium | 2.7min | 16 | 0 | $0.33 | 4.0 | powershell | ok |
| Docker Image Tag Generator | default | opus46-200k-medium | 2.7min | 30 | 0 | $0.67 | 4.0 | python | ok |
| Config File Migrator | powershell-strict | opus46-200k-medium | 2.7min | 12 | 0 | $0.49 | 4.0 | powershell | ok |
| Config File Migrator | default | opus46-200k-medium | 2.8min | 14 | 1 | $0.59 | 4.0 | python | ok |
| Batch File Renamer | default | opus46-200k-medium | 2.8min | 30 | 2 | $0.81 | 4.0 | python | ok |
| Environment Matrix Generator | powershell | sonnet46-200k-medium | 2.8min | 13 | 0 | $0.36 | 4.0 | powershell | ok |
| CSV Report Generator | csharp-script | opus46-200k-medium | 2.8min | 12 | 0 | $0.58 | 4.0 | csharp | ok |
| Log File Analyzer | default | sonnet46-200k-medium | 2.9min | 19 | 0 | $0.48 | 5.0 | python | ok |
| Docker Image Tag Generator | powershell | sonnet46-200k-medium | 2.9min | 9 | 0 | $0.31 | 4.0 | powershell | ok |
| Batch File Renamer | powershell | opus46-200k-medium | 3.0min | 21 | 0 | $0.59 | 4.0 | powershell | ok |
| Directory Tree Sync | powershell | sonnet46-200k-medium | 3.0min | 11 | 0 | $0.37 | 4.0 | powershell | ok |
| PR Label Assigner | powershell | opus46-200k-medium | 3.1min | 23 | 0 | $0.61 | 4.0 | powershell | ok |
| Multi-file Search and Replace | default | opus46-200k-medium | 3.1min | 25 | 3 | $0.70 | 4.0 | python | ok |
| PR Label Assigner | powershell-strict | sonnet46-200k-medium | 3.3min | 12 | 0 | $0.35 | 4.0 | powershell | ok |
| Secret Rotation Validator | powershell | opus46-200k-medium | 3.3min | 23 | 1 | $0.72 | 4.0 | powershell | ok |
| Process Monitor | default | opus46-200k-medium | 3.3min | 40 | 1 | $1.00 | 3.0 | python | ok |
| Config File Migrator | default | sonnet46-200k-medium | 3.4min | 18 | 1 | $0.47 | 4.0 | python | ok |
| Config File Migrator | powershell | sonnet46-200k-medium | 3.4min | 15 | 0 | $0.38 | 4.0 | powershell | ok |
| Docker Image Tag Generator | powershell | opus46-200k-medium | 3.5min | 32 | 0 | $0.84 | 4.0 | powershell | ok |
| Secret Rotation Validator | powershell | sonnet46-200k-medium | 3.5min | 11 | 0 | $0.48 | 4.0 | powershell | ok |
| Semantic Version Bumper | powershell | opus46-200k-medium | 3.6min | 27 | 0 | $0.77 | 4.0 | powershell | ok |
| Database Seed Script | powershell-strict | sonnet46-200k-medium | 3.6min | 1 | 0 | $0.00 | — | powershell | failed |
| Artifact Cleanup Script | powershell-strict | sonnet46-200k-medium | 3.6min | 15 | 0 | $0.49 | 4.0 | powershell | ok |
| Multi-file Search and Replace | powershell | opus46-200k-medium | 3.6min | 21 | 0 | $0.65 | 4.0 | powershell | ok |
| PR Label Assigner | powershell | sonnet46-200k-medium | 3.7min | 10 | 0 | $0.38 | 4.0 | powershell | ok |
| Batch File Renamer | powershell-strict | sonnet46-200k-medium | 3.7min | 16 | 1 | $0.50 | 4.0 | powershell | ok |
| Error Retry Pipeline | default | sonnet46-200k-medium | 3.7min | 1 | 0 | $0.00 | — |  | failed |
| Config File Migrator | powershell | opus46-200k-medium | 3.7min | 20 | 0 | $0.69 | 4.0 | powershell | ok |
| Database Seed Script | powershell | sonnet46-200k-medium | 3.8min | 1 | 0 | $0.00 | — | powershell | failed |
| Process Monitor | powershell | sonnet46-200k-medium | 3.8min | 13 | 0 | $0.40 | 4.0 | powershell | ok |
| Directory Tree Sync | default | opus46-200k-medium | 3.8min | 43 | 0 | $1.18 | 4.0 | python | ok |
| Multi-file Search and Replace | powershell-strict | sonnet46-200k-medium | 3.8min | 1 | 0 | $0.00 | — | powershell | failed |
| Log File Analyzer | powershell-strict | sonnet46-200k-medium | 3.8min | 14 | 1 | $0.50 | 4.0 | powershell | ok |
| Error Retry Pipeline | powershell | opus46-200k-medium | 3.8min | 34 | 0 | $0.93 | 4.0 | powershell | ok |
| Error Retry Pipeline | powershell | sonnet46-200k-medium | 3.8min | 1 | 0 | $0.00 | — | powershell | failed |
| Error Retry Pipeline | powershell-strict | sonnet46-200k-medium | 3.8min | 1 | 0 | $0.00 | — | powershell | failed |
| Database Seed Script | default | sonnet46-200k-medium | 3.9min | 1 | 0 | $0.00 | — |  | failed |
| Log File Analyzer | powershell | sonnet46-200k-medium | 3.9min | 10 | 0 | $0.44 | 4.0 | powershell | ok |
| Multi-file Search and Replace | default | sonnet46-200k-medium | 3.9min | 1 | 0 | $0.00 | — |  | failed |
| Directory Tree Sync | default | sonnet46-200k-medium | 3.9min | 11 | 1 | $0.45 | 5.0 | python | ok |
| Test Results Aggregator | powershell-strict | opus46-200k-medium | 4.0min | 24 | 0 | $0.95 | 4.0 | powershell | ok |
| Secret Rotation Validator | powershell-strict | sonnet46-200k-medium | 4.0min | 20 | 0 | $0.53 | 4.0 | powershell | ok |
| Dependency License Checker | default | sonnet46-200k-medium | 4.0min | 1 | 0 | $0.00 | — |  | failed |
| Test Results Aggregator | default | sonnet46-200k-medium | 4.0min | 20 | 1 | $0.49 | 3.0 | python | ok |
| PR Label Assigner | powershell-strict | opus46-200k-medium | 4.0min | 37 | 0 | $1.03 | 4.0 | powershell | ok |
| Multi-file Search and Replace | powershell-strict | opus46-200k-medium | 4.1min | 34 | 0 | $1.09 | 3.0 | powershell | ok |
| Log File Analyzer | default | opus46-200k-medium | 4.2min | 43 | 0 | $1.18 | 5.0 | python | ok |
| Environment Matrix Generator | powershell-strict | opus46-200k-medium | 4.2min | 31 | 2 | $0.96 | 4.0 | powershell | ok |
| CSV Report Generator | powershell | opus46-200k-medium | 4.3min | 37 | 0 | $1.05 | 4.0 | powershell | ok |
| CSV Report Generator | powershell-strict | opus46-200k-medium | 4.3min | 40 | 1 | $1.04 | 4.0 | powershell | ok |
| Test Results Aggregator | powershell | opus46-200k-medium | 4.3min | 33 | 0 | $0.95 | 4.0 | powershell | ok |
| Database Seed Script | default | opus46-200k-medium | 4.3min | 36 | 1 | $1.04 | 5.0 | python | ok |
| Directory Tree Sync | powershell-strict | sonnet46-200k-medium | 4.3min | 13 | 0 | $0.49 | 4.0 | powershell | ok |
| Artifact Cleanup Script | default | opus46-200k-medium | 4.4min | 34 | 0 | $0.98 | 4.0 | python | ok |
| Log File Analyzer | powershell-strict | opus46-200k-medium | 4.5min | 31 | 1 | $0.95 | 4.0 | powershell | ok |
| Batch File Renamer | powershell-strict | opus46-200k-medium | 4.5min | 35 | 0 | $1.05 | 4.0 | powershell | ok |
| Log File Analyzer | powershell | opus46-200k-medium | 4.6min | 41 | 0 | $1.14 | 4.0 | powershell | ok |
| Process Monitor | powershell-strict | sonnet46-200k-medium | 4.6min | 19 | 0 | $0.54 | 4.0 | powershell | ok |
| Environment Matrix Generator | default | opus46-200k-medium | 4.7min | 38 | 1 | $1.11 | 4.0 | python | ok |
| Semantic Version Bumper | default | opus46-200k-medium | 4.8min | 47 | 5 | $1.23 | 4.0 | python | ok |
| Artifact Cleanup Script | powershell | opus46-200k-medium | 4.9min | 30 | 0 | $1.16 | 4.0 | powershell | ok |
| Test Results Aggregator | powershell | sonnet46-200k-medium | 5.0min | 15 | 0 | $0.55 | 4.0 | powershell | ok |
| Docker Image Tag Generator | powershell-strict | opus46-200k-medium | 5.0min | 44 | 0 | $1.28 | 4.0 | powershell | ok |
| REST API Client | powershell-strict | opus46-200k-medium | 5.1min | 19 | 0 | $0.94 | 4.0 | powershell | ok |
| REST API Client | default | opus46-200k-medium | 5.2min | 45 | 0 | $1.21 | 5.0 | python | ok |
| Semantic Version Bumper | powershell-strict | sonnet46-200k-medium | 5.3min | 5 | 0 | $0.15 | 4.0 | powershell | failed |
| Secret Rotation Validator | powershell-strict | opus46-200k-medium | 5.3min | 39 | 2 | $1.27 | 4.0 | powershell | ok |
| Directory Tree Sync | powershell | opus46-200k-medium | 5.3min | 42 | 0 | $1.13 | 4.0 | powershell | ok |
| Process Monitor | powershell | opus46-200k-medium | 5.4min | 39 | 0 | $1.21 | 4.0 | powershell | ok |
| Directory Tree Sync | powershell-strict | opus46-200k-medium | 5.4min | 34 | 0 | $1.21 | 4.0 | powershell | ok |
| Environment Matrix Generator | powershell-strict | sonnet46-200k-medium | 5.4min | 16 | 0 | $0.62 | 4.0 | powershell | ok |
| Dependency License Checker | powershell-strict | opus46-200k-medium | 5.4min | 52 | 4 | $1.59 | 4.0 | powershell | ok |
| Artifact Cleanup Script | powershell-strict | opus46-200k-medium | 5.5min | 37 | 1 | $1.37 | 4.0 | powershell | ok |
| Dependency License Checker | default | opus46-200k-medium | 5.6min | 64 | 4 | $1.73 | 5.0 | python | ok |
| Process Monitor | powershell-strict | opus46-200k-medium | 5.6min | 53 | 0 | $1.61 | 4.0 | powershell | ok |
| Dependency License Checker | powershell | opus46-200k-medium | 5.8min | 45 | 1 | $1.37 | 5.0 | powershell | ok |
| Semantic Version Bumper | powershell-strict | opus46-200k-medium | 5.8min | 52 | 0 | $1.57 | 4.0 | powershell | ok |
| Database Seed Script | powershell | opus46-200k-medium | 5.8min | 42 | 4 | $1.32 | 4.0 | powershell | ok |
| CSV Report Generator | default | sonnet46-200k-medium | 6.3min | 1 | 3 | $0.71 | 4.0 | python | ok |
| CSV Report Generator | powershell-strict | sonnet46-200k-medium | 6.5min | 29 | 0 | $0.97 | 4.0 | powershell | ok |
| REST API Client | powershell | opus46-200k-medium | 7.2min | 51 | 1 | $1.82 | 4.0 | powershell | ok |
| Database Seed Script | powershell-strict | opus46-200k-medium | 8.7min | 56 | 2 | $2.03 | 4.0 | powershell | ok |
| REST API Client | powershell-strict | sonnet46-200k-medium | 9.2min | 14 | 0 | $0.99 | 4.0 | powershell | ok |
| Dependency License Checker | powershell-strict | sonnet46-200k-medium | 9.5min | 18 | 0 | $0.97 | 4.0 | powershell | ok |
| Error Retry Pipeline | powershell-strict | opus46-200k-medium | 9.7min | 0 | 1 | $0.00 | 4.0 | powershell | failed |
| Test Results Aggregator | powershell-strict | sonnet46-200k-medium | 11.5min | 20 | 0 | $1.42 | 4.0 | powershell | ok |
| REST API Client | powershell | sonnet46-200k-medium | 12.6min | 13 | 0 | $0.96 | 3.0 | powershell | ok |
| Config File Migrator | powershell-strict | sonnet46-200k-medium | 13.9min | 21 | 0 | $1.60 | 4.0 | powershell | ok |

</details>

<details>
<summary>Sorted by errors (fewest first)</summary>

| Task | Language | Model | Duration | Turns | Errors | Cost | Tests Quality | Chosen | Status |
|------|----------|-------|----------|-------|--------|------|-----------|--------|--------|
| CSV Report Generator | csharp-script | opus46-200k-medium | 2.8min | 12 | 0 | $0.58 | 4.0 | csharp | ok |
| CSV Report Generator | csharp-script | sonnet46-200k-medium | 0.6min | 7 | 0 | $0.12 | 4.0 | csharp | ok |
| CSV Report Generator | default | opus46-200k-medium | 1.7min | 12 | 0 | $0.38 | 5.0 | python | ok |
| CSV Report Generator | powershell | opus46-200k-medium | 4.3min | 37 | 0 | $1.05 | 4.0 | powershell | ok |
| CSV Report Generator | powershell | sonnet46-200k-medium | 2.1min | 9 | 0 | $0.31 | 3.0 | powershell | ok |
| CSV Report Generator | powershell-strict | sonnet46-200k-medium | 6.5min | 29 | 0 | $0.97 | 4.0 | powershell | ok |
| Log File Analyzer | csharp-script | opus46-200k-medium | 0.7min | 9 | 0 | $0.25 | 4.0 | csharp | ok |
| Log File Analyzer | default | opus46-200k-medium | 4.2min | 43 | 0 | $1.18 | 5.0 | python | ok |
| Log File Analyzer | default | sonnet46-200k-medium | 2.9min | 19 | 0 | $0.48 | 5.0 | python | ok |
| Log File Analyzer | powershell | opus46-200k-medium | 4.6min | 41 | 0 | $1.14 | 4.0 | powershell | ok |
| Log File Analyzer | powershell | sonnet46-200k-medium | 3.9min | 10 | 0 | $0.44 | 4.0 | powershell | ok |
| Directory Tree Sync | default | opus46-200k-medium | 3.8min | 43 | 0 | $1.18 | 4.0 | python | ok |
| Directory Tree Sync | powershell | opus46-200k-medium | 5.3min | 42 | 0 | $1.13 | 4.0 | powershell | ok |
| Directory Tree Sync | powershell | sonnet46-200k-medium | 3.0min | 11 | 0 | $0.37 | 4.0 | powershell | ok |
| Directory Tree Sync | powershell-strict | opus46-200k-medium | 5.4min | 34 | 0 | $1.21 | 4.0 | powershell | ok |
| Directory Tree Sync | powershell-strict | sonnet46-200k-medium | 4.3min | 13 | 0 | $0.49 | 4.0 | powershell | ok |
| REST API Client | default | opus46-200k-medium | 5.2min | 45 | 0 | $1.21 | 5.0 | python | ok |
| REST API Client | powershell | sonnet46-200k-medium | 12.6min | 13 | 0 | $0.96 | 3.0 | powershell | ok |
| REST API Client | powershell-strict | opus46-200k-medium | 5.1min | 19 | 0 | $0.94 | 4.0 | powershell | ok |
| REST API Client | powershell-strict | sonnet46-200k-medium | 9.2min | 14 | 0 | $0.99 | 4.0 | powershell | ok |
| Process Monitor | default | sonnet46-200k-medium | 2.0min | 12 | 0 | $0.25 | 4.0 | python | ok |
| Process Monitor | powershell | opus46-200k-medium | 5.4min | 39 | 0 | $1.21 | 4.0 | powershell | ok |
| Process Monitor | powershell | sonnet46-200k-medium | 3.8min | 13 | 0 | $0.40 | 4.0 | powershell | ok |
| Process Monitor | powershell-strict | opus46-200k-medium | 5.6min | 53 | 0 | $1.61 | 4.0 | powershell | ok |
| Process Monitor | powershell-strict | sonnet46-200k-medium | 4.6min | 19 | 0 | $0.54 | 4.0 | powershell | ok |
| Config File Migrator | powershell | opus46-200k-medium | 3.7min | 20 | 0 | $0.69 | 4.0 | powershell | ok |
| Config File Migrator | powershell | sonnet46-200k-medium | 3.4min | 15 | 0 | $0.38 | 4.0 | powershell | ok |
| Config File Migrator | powershell-strict | opus46-200k-medium | 2.7min | 12 | 0 | $0.49 | 4.0 | powershell | ok |
| Config File Migrator | powershell-strict | sonnet46-200k-medium | 13.9min | 21 | 0 | $1.60 | 4.0 | powershell | ok |
| Batch File Renamer | default | sonnet46-200k-medium | 2.3min | 8 | 0 | $0.22 | 4.0 | python | ok |
| Batch File Renamer | powershell | opus46-200k-medium | 3.0min | 21 | 0 | $0.59 | 4.0 | powershell | ok |
| Batch File Renamer | powershell | sonnet46-200k-medium | 1.4min | 6 | 0 | $0.16 | 3.0 | powershell | ok |
| Batch File Renamer | powershell-strict | opus46-200k-medium | 4.5min | 35 | 0 | $1.05 | 4.0 | powershell | ok |
| Database Seed Script | default | sonnet46-200k-medium | 3.9min | 1 | 0 | $0.00 | — |  | failed |
| Database Seed Script | powershell | sonnet46-200k-medium | 3.8min | 1 | 0 | $0.00 | — | powershell | failed |
| Database Seed Script | powershell-strict | sonnet46-200k-medium | 3.6min | 1 | 0 | $0.00 | — | powershell | failed |
| Error Retry Pipeline | default | opus46-200k-medium | 2.3min | 24 | 0 | $0.54 | 4.0 | python | ok |
| Error Retry Pipeline | default | sonnet46-200k-medium | 3.7min | 1 | 0 | $0.00 | — |  | failed |
| Error Retry Pipeline | powershell | opus46-200k-medium | 3.8min | 34 | 0 | $0.93 | 4.0 | powershell | ok |
| Error Retry Pipeline | powershell | sonnet46-200k-medium | 3.8min | 1 | 0 | $0.00 | — | powershell | failed |
| Error Retry Pipeline | powershell-strict | sonnet46-200k-medium | 3.8min | 1 | 0 | $0.00 | — | powershell | failed |
| Multi-file Search and Replace | default | sonnet46-200k-medium | 3.9min | 1 | 0 | $0.00 | — |  | failed |
| Multi-file Search and Replace | powershell | opus46-200k-medium | 3.6min | 21 | 0 | $0.65 | 4.0 | powershell | ok |
| Multi-file Search and Replace | powershell | sonnet46-200k-medium | 1.4min | 10 | 0 | $0.19 | 4.0 | powershell | ok |
| Multi-file Search and Replace | powershell-strict | opus46-200k-medium | 4.1min | 34 | 0 | $1.09 | 3.0 | powershell | ok |
| Multi-file Search and Replace | powershell-strict | sonnet46-200k-medium | 3.8min | 1 | 0 | $0.00 | — | powershell | failed |
| Semantic Version Bumper | default | sonnet46-200k-medium | 2.5min | 11 | 0 | $0.25 | 4.0 | python | ok |
| Semantic Version Bumper | powershell | opus46-200k-medium | 3.6min | 27 | 0 | $0.77 | 4.0 | powershell | ok |
| Semantic Version Bumper | powershell | sonnet46-200k-medium | 2.7min | 16 | 0 | $0.33 | 4.0 | powershell | ok |
| Semantic Version Bumper | powershell-strict | opus46-200k-medium | 5.8min | 52 | 0 | $1.57 | 4.0 | powershell | ok |
| Semantic Version Bumper | powershell-strict | sonnet46-200k-medium | 5.3min | 5 | 0 | $0.15 | 4.0 | powershell | failed |
| PR Label Assigner | default | sonnet46-200k-medium | 1.8min | 8 | 0 | $0.21 | 5.0 | python | ok |
| PR Label Assigner | powershell | opus46-200k-medium | 3.1min | 23 | 0 | $0.61 | 4.0 | powershell | ok |
| PR Label Assigner | powershell | sonnet46-200k-medium | 3.7min | 10 | 0 | $0.38 | 4.0 | powershell | ok |
| PR Label Assigner | powershell-strict | opus46-200k-medium | 4.0min | 37 | 0 | $1.03 | 4.0 | powershell | ok |
| PR Label Assigner | powershell-strict | sonnet46-200k-medium | 3.3min | 12 | 0 | $0.35 | 4.0 | powershell | ok |
| Dependency License Checker | default | sonnet46-200k-medium | 4.0min | 1 | 0 | $0.00 | — |  | failed |
| Dependency License Checker | powershell | sonnet46-200k-medium | 2.6min | 11 | 0 | $0.36 | 5.0 | powershell | ok |
| Dependency License Checker | powershell-strict | sonnet46-200k-medium | 9.5min | 18 | 0 | $0.97 | 4.0 | powershell | ok |
| Docker Image Tag Generator | default | opus46-200k-medium | 2.7min | 30 | 0 | $0.67 | 4.0 | python | ok |
| Docker Image Tag Generator | powershell | opus46-200k-medium | 3.5min | 32 | 0 | $0.84 | 4.0 | powershell | ok |
| Docker Image Tag Generator | powershell | sonnet46-200k-medium | 2.9min | 9 | 0 | $0.31 | 4.0 | powershell | ok |
| Docker Image Tag Generator | powershell-strict | opus46-200k-medium | 5.0min | 44 | 0 | $1.28 | 4.0 | powershell | ok |
| Docker Image Tag Generator | powershell-strict | sonnet46-200k-medium | 2.5min | 13 | 0 | $0.33 | 4.0 | powershell | ok |
| Test Results Aggregator | powershell | opus46-200k-medium | 4.3min | 33 | 0 | $0.95 | 4.0 | powershell | ok |
| Test Results Aggregator | powershell | sonnet46-200k-medium | 5.0min | 15 | 0 | $0.55 | 4.0 | powershell | ok |
| Test Results Aggregator | powershell-strict | opus46-200k-medium | 4.0min | 24 | 0 | $0.95 | 4.0 | powershell | ok |
| Test Results Aggregator | powershell-strict | sonnet46-200k-medium | 11.5min | 20 | 0 | $1.42 | 4.0 | powershell | ok |
| Environment Matrix Generator | default | sonnet46-200k-medium | 2.0min | 9 | 0 | $0.26 | 4.0 | python | ok |
| Environment Matrix Generator | powershell | opus46-200k-medium | 2.3min | 18 | 0 | $0.54 | 4.0 | powershell | ok |
| Environment Matrix Generator | powershell | sonnet46-200k-medium | 2.8min | 13 | 0 | $0.36 | 4.0 | powershell | ok |
| Environment Matrix Generator | powershell-strict | sonnet46-200k-medium | 5.4min | 16 | 0 | $0.62 | 4.0 | powershell | ok |
| Artifact Cleanup Script | default | opus46-200k-medium | 4.4min | 34 | 0 | $0.98 | 4.0 | python | ok |
| Artifact Cleanup Script | powershell | opus46-200k-medium | 4.9min | 30 | 0 | $1.16 | 4.0 | powershell | ok |
| Artifact Cleanup Script | powershell | sonnet46-200k-medium | 2.6min | 9 | 0 | $0.35 | 4.0 | powershell | ok |
| Artifact Cleanup Script | powershell-strict | sonnet46-200k-medium | 3.6min | 15 | 0 | $0.49 | 4.0 | powershell | ok |
| Secret Rotation Validator | default | opus46-200k-medium | 2.6min | 17 | 0 | $0.51 | 4.0 | python | ok |
| Secret Rotation Validator | default | sonnet46-200k-medium | 1.5min | 11 | 0 | $0.22 | 4.0 | python | ok |
| Secret Rotation Validator | powershell | sonnet46-200k-medium | 3.5min | 11 | 0 | $0.48 | 4.0 | powershell | ok |
| Secret Rotation Validator | powershell-strict | sonnet46-200k-medium | 4.0min | 20 | 0 | $0.53 | 4.0 | powershell | ok |
| CSV Report Generator | powershell-strict | opus46-200k-medium | 4.3min | 40 | 1 | $1.04 | 4.0 | powershell | ok |
| Log File Analyzer | powershell-strict | opus46-200k-medium | 4.5min | 31 | 1 | $0.95 | 4.0 | powershell | ok |
| Log File Analyzer | powershell-strict | sonnet46-200k-medium | 3.8min | 14 | 1 | $0.50 | 4.0 | powershell | ok |
| Directory Tree Sync | default | sonnet46-200k-medium | 3.9min | 11 | 1 | $0.45 | 5.0 | python | ok |
| REST API Client | default | sonnet46-200k-medium | 1.8min | 9 | 1 | $0.23 | 5.0 | python | ok |
| REST API Client | powershell | opus46-200k-medium | 7.2min | 51 | 1 | $1.82 | 4.0 | powershell | ok |
| Process Monitor | default | opus46-200k-medium | 3.3min | 40 | 1 | $1.00 | 3.0 | python | ok |
| Config File Migrator | default | opus46-200k-medium | 2.8min | 14 | 1 | $0.59 | 4.0 | python | ok |
| Config File Migrator | default | sonnet46-200k-medium | 3.4min | 18 | 1 | $0.47 | 4.0 | python | ok |
| Batch File Renamer | powershell-strict | sonnet46-200k-medium | 3.7min | 16 | 1 | $0.50 | 4.0 | powershell | ok |
| Database Seed Script | default | opus46-200k-medium | 4.3min | 36 | 1 | $1.04 | 5.0 | python | ok |
| Error Retry Pipeline | powershell-strict | opus46-200k-medium | 9.7min | 0 | 1 | $0.00 | 4.0 | powershell | failed |
| PR Label Assigner | default | opus46-200k-medium | 1.9min | 11 | 1 | $0.38 | 4.0 | python | ok |
| Dependency License Checker | powershell | opus46-200k-medium | 5.8min | 45 | 1 | $1.37 | 5.0 | powershell | ok |
| Docker Image Tag Generator | default | sonnet46-200k-medium | 1.8min | 10 | 1 | $0.23 | 4.0 | python | ok |
| Test Results Aggregator | default | opus46-200k-medium | 2.3min | 15 | 1 | $0.51 | 4.0 | python | ok |
| Test Results Aggregator | default | sonnet46-200k-medium | 4.0min | 20 | 1 | $0.49 | 3.0 | python | ok |
| Environment Matrix Generator | default | opus46-200k-medium | 4.7min | 38 | 1 | $1.11 | 4.0 | python | ok |
| Artifact Cleanup Script | powershell-strict | opus46-200k-medium | 5.5min | 37 | 1 | $1.37 | 4.0 | powershell | ok |
| Secret Rotation Validator | powershell | opus46-200k-medium | 3.3min | 23 | 1 | $0.72 | 4.0 | powershell | ok |
| Batch File Renamer | default | opus46-200k-medium | 2.8min | 30 | 2 | $0.81 | 4.0 | python | ok |
| Database Seed Script | powershell-strict | opus46-200k-medium | 8.7min | 56 | 2 | $2.03 | 4.0 | powershell | ok |
| Environment Matrix Generator | powershell-strict | opus46-200k-medium | 4.2min | 31 | 2 | $0.96 | 4.0 | powershell | ok |
| Secret Rotation Validator | powershell-strict | opus46-200k-medium | 5.3min | 39 | 2 | $1.27 | 4.0 | powershell | ok |
| CSV Report Generator | default | sonnet46-200k-medium | 6.3min | 1 | 3 | $0.71 | 4.0 | python | ok |
| Multi-file Search and Replace | default | opus46-200k-medium | 3.1min | 25 | 3 | $0.70 | 4.0 | python | ok |
| Database Seed Script | powershell | opus46-200k-medium | 5.8min | 42 | 4 | $1.32 | 4.0 | powershell | ok |
| Dependency License Checker | default | opus46-200k-medium | 5.6min | 64 | 4 | $1.73 | 5.0 | python | ok |
| Dependency License Checker | powershell-strict | opus46-200k-medium | 5.4min | 52 | 4 | $1.59 | 4.0 | powershell | ok |
| Artifact Cleanup Script | default | sonnet46-200k-medium | 2.6min | 17 | 4 | $0.44 | 4.0 | python | ok |
| Semantic Version Bumper | default | opus46-200k-medium | 4.8min | 47 | 5 | $1.23 | 4.0 | python | ok |

</details>

<details>
<summary>Sorted by turns (fewest first)</summary>

| Task | Language | Model | Duration | Turns | Errors | Cost | Tests Quality | Chosen | Status |
|------|----------|-------|----------|-------|--------|------|-----------|--------|--------|
| Error Retry Pipeline | powershell-strict | opus46-200k-medium | 9.7min | 0 | 1 | $0.00 | 4.0 | powershell | failed |
| CSV Report Generator | default | sonnet46-200k-medium | 6.3min | 1 | 3 | $0.71 | 4.0 | python | ok |
| Database Seed Script | default | sonnet46-200k-medium | 3.9min | 1 | 0 | $0.00 | — |  | failed |
| Database Seed Script | powershell | sonnet46-200k-medium | 3.8min | 1 | 0 | $0.00 | — | powershell | failed |
| Database Seed Script | powershell-strict | sonnet46-200k-medium | 3.6min | 1 | 0 | $0.00 | — | powershell | failed |
| Error Retry Pipeline | default | sonnet46-200k-medium | 3.7min | 1 | 0 | $0.00 | — |  | failed |
| Error Retry Pipeline | powershell | sonnet46-200k-medium | 3.8min | 1 | 0 | $0.00 | — | powershell | failed |
| Error Retry Pipeline | powershell-strict | sonnet46-200k-medium | 3.8min | 1 | 0 | $0.00 | — | powershell | failed |
| Multi-file Search and Replace | default | sonnet46-200k-medium | 3.9min | 1 | 0 | $0.00 | — |  | failed |
| Multi-file Search and Replace | powershell-strict | sonnet46-200k-medium | 3.8min | 1 | 0 | $0.00 | — | powershell | failed |
| Dependency License Checker | default | sonnet46-200k-medium | 4.0min | 1 | 0 | $0.00 | — |  | failed |
| Semantic Version Bumper | powershell-strict | sonnet46-200k-medium | 5.3min | 5 | 0 | $0.15 | 4.0 | powershell | failed |
| Batch File Renamer | powershell | sonnet46-200k-medium | 1.4min | 6 | 0 | $0.16 | 3.0 | powershell | ok |
| CSV Report Generator | csharp-script | sonnet46-200k-medium | 0.6min | 7 | 0 | $0.12 | 4.0 | csharp | ok |
| Batch File Renamer | default | sonnet46-200k-medium | 2.3min | 8 | 0 | $0.22 | 4.0 | python | ok |
| PR Label Assigner | default | sonnet46-200k-medium | 1.8min | 8 | 0 | $0.21 | 5.0 | python | ok |
| CSV Report Generator | powershell | sonnet46-200k-medium | 2.1min | 9 | 0 | $0.31 | 3.0 | powershell | ok |
| Log File Analyzer | csharp-script | opus46-200k-medium | 0.7min | 9 | 0 | $0.25 | 4.0 | csharp | ok |
| REST API Client | default | sonnet46-200k-medium | 1.8min | 9 | 1 | $0.23 | 5.0 | python | ok |
| Docker Image Tag Generator | powershell | sonnet46-200k-medium | 2.9min | 9 | 0 | $0.31 | 4.0 | powershell | ok |
| Environment Matrix Generator | default | sonnet46-200k-medium | 2.0min | 9 | 0 | $0.26 | 4.0 | python | ok |
| Artifact Cleanup Script | powershell | sonnet46-200k-medium | 2.6min | 9 | 0 | $0.35 | 4.0 | powershell | ok |
| Log File Analyzer | powershell | sonnet46-200k-medium | 3.9min | 10 | 0 | $0.44 | 4.0 | powershell | ok |
| Multi-file Search and Replace | powershell | sonnet46-200k-medium | 1.4min | 10 | 0 | $0.19 | 4.0 | powershell | ok |
| PR Label Assigner | powershell | sonnet46-200k-medium | 3.7min | 10 | 0 | $0.38 | 4.0 | powershell | ok |
| Docker Image Tag Generator | default | sonnet46-200k-medium | 1.8min | 10 | 1 | $0.23 | 4.0 | python | ok |
| Directory Tree Sync | default | sonnet46-200k-medium | 3.9min | 11 | 1 | $0.45 | 5.0 | python | ok |
| Directory Tree Sync | powershell | sonnet46-200k-medium | 3.0min | 11 | 0 | $0.37 | 4.0 | powershell | ok |
| Semantic Version Bumper | default | sonnet46-200k-medium | 2.5min | 11 | 0 | $0.25 | 4.0 | python | ok |
| PR Label Assigner | default | opus46-200k-medium | 1.9min | 11 | 1 | $0.38 | 4.0 | python | ok |
| Dependency License Checker | powershell | sonnet46-200k-medium | 2.6min | 11 | 0 | $0.36 | 5.0 | powershell | ok |
| Secret Rotation Validator | default | sonnet46-200k-medium | 1.5min | 11 | 0 | $0.22 | 4.0 | python | ok |
| Secret Rotation Validator | powershell | sonnet46-200k-medium | 3.5min | 11 | 0 | $0.48 | 4.0 | powershell | ok |
| CSV Report Generator | csharp-script | opus46-200k-medium | 2.8min | 12 | 0 | $0.58 | 4.0 | csharp | ok |
| CSV Report Generator | default | opus46-200k-medium | 1.7min | 12 | 0 | $0.38 | 5.0 | python | ok |
| Process Monitor | default | sonnet46-200k-medium | 2.0min | 12 | 0 | $0.25 | 4.0 | python | ok |
| Config File Migrator | powershell-strict | opus46-200k-medium | 2.7min | 12 | 0 | $0.49 | 4.0 | powershell | ok |
| PR Label Assigner | powershell-strict | sonnet46-200k-medium | 3.3min | 12 | 0 | $0.35 | 4.0 | powershell | ok |
| Directory Tree Sync | powershell-strict | sonnet46-200k-medium | 4.3min | 13 | 0 | $0.49 | 4.0 | powershell | ok |
| REST API Client | powershell | sonnet46-200k-medium | 12.6min | 13 | 0 | $0.96 | 3.0 | powershell | ok |
| Process Monitor | powershell | sonnet46-200k-medium | 3.8min | 13 | 0 | $0.40 | 4.0 | powershell | ok |
| Docker Image Tag Generator | powershell-strict | sonnet46-200k-medium | 2.5min | 13 | 0 | $0.33 | 4.0 | powershell | ok |
| Environment Matrix Generator | powershell | sonnet46-200k-medium | 2.8min | 13 | 0 | $0.36 | 4.0 | powershell | ok |
| Log File Analyzer | powershell-strict | sonnet46-200k-medium | 3.8min | 14 | 1 | $0.50 | 4.0 | powershell | ok |
| REST API Client | powershell-strict | sonnet46-200k-medium | 9.2min | 14 | 0 | $0.99 | 4.0 | powershell | ok |
| Config File Migrator | default | opus46-200k-medium | 2.8min | 14 | 1 | $0.59 | 4.0 | python | ok |
| Config File Migrator | powershell | sonnet46-200k-medium | 3.4min | 15 | 0 | $0.38 | 4.0 | powershell | ok |
| Test Results Aggregator | default | opus46-200k-medium | 2.3min | 15 | 1 | $0.51 | 4.0 | python | ok |
| Test Results Aggregator | powershell | sonnet46-200k-medium | 5.0min | 15 | 0 | $0.55 | 4.0 | powershell | ok |
| Artifact Cleanup Script | powershell-strict | sonnet46-200k-medium | 3.6min | 15 | 0 | $0.49 | 4.0 | powershell | ok |
| Batch File Renamer | powershell-strict | sonnet46-200k-medium | 3.7min | 16 | 1 | $0.50 | 4.0 | powershell | ok |
| Semantic Version Bumper | powershell | sonnet46-200k-medium | 2.7min | 16 | 0 | $0.33 | 4.0 | powershell | ok |
| Environment Matrix Generator | powershell-strict | sonnet46-200k-medium | 5.4min | 16 | 0 | $0.62 | 4.0 | powershell | ok |
| Artifact Cleanup Script | default | sonnet46-200k-medium | 2.6min | 17 | 4 | $0.44 | 4.0 | python | ok |
| Secret Rotation Validator | default | opus46-200k-medium | 2.6min | 17 | 0 | $0.51 | 4.0 | python | ok |
| Config File Migrator | default | sonnet46-200k-medium | 3.4min | 18 | 1 | $0.47 | 4.0 | python | ok |
| Dependency License Checker | powershell-strict | sonnet46-200k-medium | 9.5min | 18 | 0 | $0.97 | 4.0 | powershell | ok |
| Environment Matrix Generator | powershell | opus46-200k-medium | 2.3min | 18 | 0 | $0.54 | 4.0 | powershell | ok |
| Log File Analyzer | default | sonnet46-200k-medium | 2.9min | 19 | 0 | $0.48 | 5.0 | python | ok |
| REST API Client | powershell-strict | opus46-200k-medium | 5.1min | 19 | 0 | $0.94 | 4.0 | powershell | ok |
| Process Monitor | powershell-strict | sonnet46-200k-medium | 4.6min | 19 | 0 | $0.54 | 4.0 | powershell | ok |
| Config File Migrator | powershell | opus46-200k-medium | 3.7min | 20 | 0 | $0.69 | 4.0 | powershell | ok |
| Test Results Aggregator | default | sonnet46-200k-medium | 4.0min | 20 | 1 | $0.49 | 3.0 | python | ok |
| Test Results Aggregator | powershell-strict | sonnet46-200k-medium | 11.5min | 20 | 0 | $1.42 | 4.0 | powershell | ok |
| Secret Rotation Validator | powershell-strict | sonnet46-200k-medium | 4.0min | 20 | 0 | $0.53 | 4.0 | powershell | ok |
| Config File Migrator | powershell-strict | sonnet46-200k-medium | 13.9min | 21 | 0 | $1.60 | 4.0 | powershell | ok |
| Batch File Renamer | powershell | opus46-200k-medium | 3.0min | 21 | 0 | $0.59 | 4.0 | powershell | ok |
| Multi-file Search and Replace | powershell | opus46-200k-medium | 3.6min | 21 | 0 | $0.65 | 4.0 | powershell | ok |
| PR Label Assigner | powershell | opus46-200k-medium | 3.1min | 23 | 0 | $0.61 | 4.0 | powershell | ok |
| Secret Rotation Validator | powershell | opus46-200k-medium | 3.3min | 23 | 1 | $0.72 | 4.0 | powershell | ok |
| Error Retry Pipeline | default | opus46-200k-medium | 2.3min | 24 | 0 | $0.54 | 4.0 | python | ok |
| Test Results Aggregator | powershell-strict | opus46-200k-medium | 4.0min | 24 | 0 | $0.95 | 4.0 | powershell | ok |
| Multi-file Search and Replace | default | opus46-200k-medium | 3.1min | 25 | 3 | $0.70 | 4.0 | python | ok |
| Semantic Version Bumper | powershell | opus46-200k-medium | 3.6min | 27 | 0 | $0.77 | 4.0 | powershell | ok |
| CSV Report Generator | powershell-strict | sonnet46-200k-medium | 6.5min | 29 | 0 | $0.97 | 4.0 | powershell | ok |
| Batch File Renamer | default | opus46-200k-medium | 2.8min | 30 | 2 | $0.81 | 4.0 | python | ok |
| Docker Image Tag Generator | default | opus46-200k-medium | 2.7min | 30 | 0 | $0.67 | 4.0 | python | ok |
| Artifact Cleanup Script | powershell | opus46-200k-medium | 4.9min | 30 | 0 | $1.16 | 4.0 | powershell | ok |
| Log File Analyzer | powershell-strict | opus46-200k-medium | 4.5min | 31 | 1 | $0.95 | 4.0 | powershell | ok |
| Environment Matrix Generator | powershell-strict | opus46-200k-medium | 4.2min | 31 | 2 | $0.96 | 4.0 | powershell | ok |
| Docker Image Tag Generator | powershell | opus46-200k-medium | 3.5min | 32 | 0 | $0.84 | 4.0 | powershell | ok |
| Test Results Aggregator | powershell | opus46-200k-medium | 4.3min | 33 | 0 | $0.95 | 4.0 | powershell | ok |
| Directory Tree Sync | powershell-strict | opus46-200k-medium | 5.4min | 34 | 0 | $1.21 | 4.0 | powershell | ok |
| Error Retry Pipeline | powershell | opus46-200k-medium | 3.8min | 34 | 0 | $0.93 | 4.0 | powershell | ok |
| Multi-file Search and Replace | powershell-strict | opus46-200k-medium | 4.1min | 34 | 0 | $1.09 | 3.0 | powershell | ok |
| Artifact Cleanup Script | default | opus46-200k-medium | 4.4min | 34 | 0 | $0.98 | 4.0 | python | ok |
| Batch File Renamer | powershell-strict | opus46-200k-medium | 4.5min | 35 | 0 | $1.05 | 4.0 | powershell | ok |
| Database Seed Script | default | opus46-200k-medium | 4.3min | 36 | 1 | $1.04 | 5.0 | python | ok |
| CSV Report Generator | powershell | opus46-200k-medium | 4.3min | 37 | 0 | $1.05 | 4.0 | powershell | ok |
| PR Label Assigner | powershell-strict | opus46-200k-medium | 4.0min | 37 | 0 | $1.03 | 4.0 | powershell | ok |
| Artifact Cleanup Script | powershell-strict | opus46-200k-medium | 5.5min | 37 | 1 | $1.37 | 4.0 | powershell | ok |
| Environment Matrix Generator | default | opus46-200k-medium | 4.7min | 38 | 1 | $1.11 | 4.0 | python | ok |
| Process Monitor | powershell | opus46-200k-medium | 5.4min | 39 | 0 | $1.21 | 4.0 | powershell | ok |
| Secret Rotation Validator | powershell-strict | opus46-200k-medium | 5.3min | 39 | 2 | $1.27 | 4.0 | powershell | ok |
| CSV Report Generator | powershell-strict | opus46-200k-medium | 4.3min | 40 | 1 | $1.04 | 4.0 | powershell | ok |
| Process Monitor | default | opus46-200k-medium | 3.3min | 40 | 1 | $1.00 | 3.0 | python | ok |
| Log File Analyzer | powershell | opus46-200k-medium | 4.6min | 41 | 0 | $1.14 | 4.0 | powershell | ok |
| Directory Tree Sync | powershell | opus46-200k-medium | 5.3min | 42 | 0 | $1.13 | 4.0 | powershell | ok |
| Database Seed Script | powershell | opus46-200k-medium | 5.8min | 42 | 4 | $1.32 | 4.0 | powershell | ok |
| Log File Analyzer | default | opus46-200k-medium | 4.2min | 43 | 0 | $1.18 | 5.0 | python | ok |
| Directory Tree Sync | default | opus46-200k-medium | 3.8min | 43 | 0 | $1.18 | 4.0 | python | ok |
| Docker Image Tag Generator | powershell-strict | opus46-200k-medium | 5.0min | 44 | 0 | $1.28 | 4.0 | powershell | ok |
| REST API Client | default | opus46-200k-medium | 5.2min | 45 | 0 | $1.21 | 5.0 | python | ok |
| Dependency License Checker | powershell | opus46-200k-medium | 5.8min | 45 | 1 | $1.37 | 5.0 | powershell | ok |
| Semantic Version Bumper | default | opus46-200k-medium | 4.8min | 47 | 5 | $1.23 | 4.0 | python | ok |
| REST API Client | powershell | opus46-200k-medium | 7.2min | 51 | 1 | $1.82 | 4.0 | powershell | ok |
| Semantic Version Bumper | powershell-strict | opus46-200k-medium | 5.8min | 52 | 0 | $1.57 | 4.0 | powershell | ok |
| Dependency License Checker | powershell-strict | opus46-200k-medium | 5.4min | 52 | 4 | $1.59 | 4.0 | powershell | ok |
| Process Monitor | powershell-strict | opus46-200k-medium | 5.6min | 53 | 0 | $1.61 | 4.0 | powershell | ok |
| Database Seed Script | powershell-strict | opus46-200k-medium | 8.7min | 56 | 2 | $2.03 | 4.0 | powershell | ok |
| Dependency License Checker | default | opus46-200k-medium | 5.6min | 64 | 4 | $1.73 | 5.0 | python | ok |

</details>

<details>
<summary>Sorted by LLM-as-judge score (best first)</summary>

| Task | Language | Model | Duration | Turns | Errors | Cost | Tests Quality | Chosen | Status |
|------|----------|-------|----------|-------|--------|------|-----------|--------|--------|
| CSV Report Generator | default | opus46-200k-medium | 1.7min | 12 | 0 | $0.38 | 5.0 | python | ok |
| Log File Analyzer | default | opus46-200k-medium | 4.2min | 43 | 0 | $1.18 | 5.0 | python | ok |
| Log File Analyzer | default | sonnet46-200k-medium | 2.9min | 19 | 0 | $0.48 | 5.0 | python | ok |
| Directory Tree Sync | default | sonnet46-200k-medium | 3.9min | 11 | 1 | $0.45 | 5.0 | python | ok |
| REST API Client | default | opus46-200k-medium | 5.2min | 45 | 0 | $1.21 | 5.0 | python | ok |
| REST API Client | default | sonnet46-200k-medium | 1.8min | 9 | 1 | $0.23 | 5.0 | python | ok |
| Database Seed Script | default | opus46-200k-medium | 4.3min | 36 | 1 | $1.04 | 5.0 | python | ok |
| PR Label Assigner | default | sonnet46-200k-medium | 1.8min | 8 | 0 | $0.21 | 5.0 | python | ok |
| Dependency License Checker | default | opus46-200k-medium | 5.6min | 64 | 4 | $1.73 | 5.0 | python | ok |
| Dependency License Checker | powershell | opus46-200k-medium | 5.8min | 45 | 1 | $1.37 | 5.0 | powershell | ok |
| Dependency License Checker | powershell | sonnet46-200k-medium | 2.6min | 11 | 0 | $0.36 | 5.0 | powershell | ok |
| CSV Report Generator | csharp-script | opus46-200k-medium | 2.8min | 12 | 0 | $0.58 | 4.0 | csharp | ok |
| CSV Report Generator | csharp-script | sonnet46-200k-medium | 0.6min | 7 | 0 | $0.12 | 4.0 | csharp | ok |
| CSV Report Generator | default | sonnet46-200k-medium | 6.3min | 1 | 3 | $0.71 | 4.0 | python | ok |
| CSV Report Generator | powershell | opus46-200k-medium | 4.3min | 37 | 0 | $1.05 | 4.0 | powershell | ok |
| CSV Report Generator | powershell-strict | opus46-200k-medium | 4.3min | 40 | 1 | $1.04 | 4.0 | powershell | ok |
| CSV Report Generator | powershell-strict | sonnet46-200k-medium | 6.5min | 29 | 0 | $0.97 | 4.0 | powershell | ok |
| Log File Analyzer | csharp-script | opus46-200k-medium | 0.7min | 9 | 0 | $0.25 | 4.0 | csharp | ok |
| Log File Analyzer | powershell | opus46-200k-medium | 4.6min | 41 | 0 | $1.14 | 4.0 | powershell | ok |
| Log File Analyzer | powershell | sonnet46-200k-medium | 3.9min | 10 | 0 | $0.44 | 4.0 | powershell | ok |
| Log File Analyzer | powershell-strict | opus46-200k-medium | 4.5min | 31 | 1 | $0.95 | 4.0 | powershell | ok |
| Log File Analyzer | powershell-strict | sonnet46-200k-medium | 3.8min | 14 | 1 | $0.50 | 4.0 | powershell | ok |
| Directory Tree Sync | default | opus46-200k-medium | 3.8min | 43 | 0 | $1.18 | 4.0 | python | ok |
| Directory Tree Sync | powershell | opus46-200k-medium | 5.3min | 42 | 0 | $1.13 | 4.0 | powershell | ok |
| Directory Tree Sync | powershell | sonnet46-200k-medium | 3.0min | 11 | 0 | $0.37 | 4.0 | powershell | ok |
| Directory Tree Sync | powershell-strict | opus46-200k-medium | 5.4min | 34 | 0 | $1.21 | 4.0 | powershell | ok |
| Directory Tree Sync | powershell-strict | sonnet46-200k-medium | 4.3min | 13 | 0 | $0.49 | 4.0 | powershell | ok |
| REST API Client | powershell | opus46-200k-medium | 7.2min | 51 | 1 | $1.82 | 4.0 | powershell | ok |
| REST API Client | powershell-strict | opus46-200k-medium | 5.1min | 19 | 0 | $0.94 | 4.0 | powershell | ok |
| REST API Client | powershell-strict | sonnet46-200k-medium | 9.2min | 14 | 0 | $0.99 | 4.0 | powershell | ok |
| Process Monitor | default | sonnet46-200k-medium | 2.0min | 12 | 0 | $0.25 | 4.0 | python | ok |
| Process Monitor | powershell | opus46-200k-medium | 5.4min | 39 | 0 | $1.21 | 4.0 | powershell | ok |
| Process Monitor | powershell | sonnet46-200k-medium | 3.8min | 13 | 0 | $0.40 | 4.0 | powershell | ok |
| Process Monitor | powershell-strict | opus46-200k-medium | 5.6min | 53 | 0 | $1.61 | 4.0 | powershell | ok |
| Process Monitor | powershell-strict | sonnet46-200k-medium | 4.6min | 19 | 0 | $0.54 | 4.0 | powershell | ok |
| Config File Migrator | default | opus46-200k-medium | 2.8min | 14 | 1 | $0.59 | 4.0 | python | ok |
| Config File Migrator | default | sonnet46-200k-medium | 3.4min | 18 | 1 | $0.47 | 4.0 | python | ok |
| Config File Migrator | powershell | opus46-200k-medium | 3.7min | 20 | 0 | $0.69 | 4.0 | powershell | ok |
| Config File Migrator | powershell | sonnet46-200k-medium | 3.4min | 15 | 0 | $0.38 | 4.0 | powershell | ok |
| Config File Migrator | powershell-strict | opus46-200k-medium | 2.7min | 12 | 0 | $0.49 | 4.0 | powershell | ok |
| Config File Migrator | powershell-strict | sonnet46-200k-medium | 13.9min | 21 | 0 | $1.60 | 4.0 | powershell | ok |
| Batch File Renamer | default | opus46-200k-medium | 2.8min | 30 | 2 | $0.81 | 4.0 | python | ok |
| Batch File Renamer | default | sonnet46-200k-medium | 2.3min | 8 | 0 | $0.22 | 4.0 | python | ok |
| Batch File Renamer | powershell | opus46-200k-medium | 3.0min | 21 | 0 | $0.59 | 4.0 | powershell | ok |
| Batch File Renamer | powershell-strict | opus46-200k-medium | 4.5min | 35 | 0 | $1.05 | 4.0 | powershell | ok |
| Batch File Renamer | powershell-strict | sonnet46-200k-medium | 3.7min | 16 | 1 | $0.50 | 4.0 | powershell | ok |
| Database Seed Script | powershell | opus46-200k-medium | 5.8min | 42 | 4 | $1.32 | 4.0 | powershell | ok |
| Database Seed Script | powershell-strict | opus46-200k-medium | 8.7min | 56 | 2 | $2.03 | 4.0 | powershell | ok |
| Error Retry Pipeline | default | opus46-200k-medium | 2.3min | 24 | 0 | $0.54 | 4.0 | python | ok |
| Error Retry Pipeline | powershell | opus46-200k-medium | 3.8min | 34 | 0 | $0.93 | 4.0 | powershell | ok |
| Error Retry Pipeline | powershell-strict | opus46-200k-medium | 9.7min | 0 | 1 | $0.00 | 4.0 | powershell | failed |
| Multi-file Search and Replace | default | opus46-200k-medium | 3.1min | 25 | 3 | $0.70 | 4.0 | python | ok |
| Multi-file Search and Replace | powershell | opus46-200k-medium | 3.6min | 21 | 0 | $0.65 | 4.0 | powershell | ok |
| Multi-file Search and Replace | powershell | sonnet46-200k-medium | 1.4min | 10 | 0 | $0.19 | 4.0 | powershell | ok |
| Semantic Version Bumper | default | opus46-200k-medium | 4.8min | 47 | 5 | $1.23 | 4.0 | python | ok |
| Semantic Version Bumper | default | sonnet46-200k-medium | 2.5min | 11 | 0 | $0.25 | 4.0 | python | ok |
| Semantic Version Bumper | powershell | opus46-200k-medium | 3.6min | 27 | 0 | $0.77 | 4.0 | powershell | ok |
| Semantic Version Bumper | powershell | sonnet46-200k-medium | 2.7min | 16 | 0 | $0.33 | 4.0 | powershell | ok |
| Semantic Version Bumper | powershell-strict | opus46-200k-medium | 5.8min | 52 | 0 | $1.57 | 4.0 | powershell | ok |
| Semantic Version Bumper | powershell-strict | sonnet46-200k-medium | 5.3min | 5 | 0 | $0.15 | 4.0 | powershell | failed |
| PR Label Assigner | default | opus46-200k-medium | 1.9min | 11 | 1 | $0.38 | 4.0 | python | ok |
| PR Label Assigner | powershell | opus46-200k-medium | 3.1min | 23 | 0 | $0.61 | 4.0 | powershell | ok |
| PR Label Assigner | powershell | sonnet46-200k-medium | 3.7min | 10 | 0 | $0.38 | 4.0 | powershell | ok |
| PR Label Assigner | powershell-strict | opus46-200k-medium | 4.0min | 37 | 0 | $1.03 | 4.0 | powershell | ok |
| PR Label Assigner | powershell-strict | sonnet46-200k-medium | 3.3min | 12 | 0 | $0.35 | 4.0 | powershell | ok |
| Dependency License Checker | powershell-strict | opus46-200k-medium | 5.4min | 52 | 4 | $1.59 | 4.0 | powershell | ok |
| Dependency License Checker | powershell-strict | sonnet46-200k-medium | 9.5min | 18 | 0 | $0.97 | 4.0 | powershell | ok |
| Docker Image Tag Generator | default | opus46-200k-medium | 2.7min | 30 | 0 | $0.67 | 4.0 | python | ok |
| Docker Image Tag Generator | default | sonnet46-200k-medium | 1.8min | 10 | 1 | $0.23 | 4.0 | python | ok |
| Docker Image Tag Generator | powershell | opus46-200k-medium | 3.5min | 32 | 0 | $0.84 | 4.0 | powershell | ok |
| Docker Image Tag Generator | powershell | sonnet46-200k-medium | 2.9min | 9 | 0 | $0.31 | 4.0 | powershell | ok |
| Docker Image Tag Generator | powershell-strict | opus46-200k-medium | 5.0min | 44 | 0 | $1.28 | 4.0 | powershell | ok |
| Docker Image Tag Generator | powershell-strict | sonnet46-200k-medium | 2.5min | 13 | 0 | $0.33 | 4.0 | powershell | ok |
| Test Results Aggregator | default | opus46-200k-medium | 2.3min | 15 | 1 | $0.51 | 4.0 | python | ok |
| Test Results Aggregator | powershell | opus46-200k-medium | 4.3min | 33 | 0 | $0.95 | 4.0 | powershell | ok |
| Test Results Aggregator | powershell | sonnet46-200k-medium | 5.0min | 15 | 0 | $0.55 | 4.0 | powershell | ok |
| Test Results Aggregator | powershell-strict | opus46-200k-medium | 4.0min | 24 | 0 | $0.95 | 4.0 | powershell | ok |
| Test Results Aggregator | powershell-strict | sonnet46-200k-medium | 11.5min | 20 | 0 | $1.42 | 4.0 | powershell | ok |
| Environment Matrix Generator | default | opus46-200k-medium | 4.7min | 38 | 1 | $1.11 | 4.0 | python | ok |
| Environment Matrix Generator | default | sonnet46-200k-medium | 2.0min | 9 | 0 | $0.26 | 4.0 | python | ok |
| Environment Matrix Generator | powershell | opus46-200k-medium | 2.3min | 18 | 0 | $0.54 | 4.0 | powershell | ok |
| Environment Matrix Generator | powershell | sonnet46-200k-medium | 2.8min | 13 | 0 | $0.36 | 4.0 | powershell | ok |
| Environment Matrix Generator | powershell-strict | opus46-200k-medium | 4.2min | 31 | 2 | $0.96 | 4.0 | powershell | ok |
| Environment Matrix Generator | powershell-strict | sonnet46-200k-medium | 5.4min | 16 | 0 | $0.62 | 4.0 | powershell | ok |
| Artifact Cleanup Script | default | opus46-200k-medium | 4.4min | 34 | 0 | $0.98 | 4.0 | python | ok |
| Artifact Cleanup Script | default | sonnet46-200k-medium | 2.6min | 17 | 4 | $0.44 | 4.0 | python | ok |
| Artifact Cleanup Script | powershell | opus46-200k-medium | 4.9min | 30 | 0 | $1.16 | 4.0 | powershell | ok |
| Artifact Cleanup Script | powershell | sonnet46-200k-medium | 2.6min | 9 | 0 | $0.35 | 4.0 | powershell | ok |
| Artifact Cleanup Script | powershell-strict | opus46-200k-medium | 5.5min | 37 | 1 | $1.37 | 4.0 | powershell | ok |
| Artifact Cleanup Script | powershell-strict | sonnet46-200k-medium | 3.6min | 15 | 0 | $0.49 | 4.0 | powershell | ok |
| Secret Rotation Validator | default | opus46-200k-medium | 2.6min | 17 | 0 | $0.51 | 4.0 | python | ok |
| Secret Rotation Validator | default | sonnet46-200k-medium | 1.5min | 11 | 0 | $0.22 | 4.0 | python | ok |
| Secret Rotation Validator | powershell | opus46-200k-medium | 3.3min | 23 | 1 | $0.72 | 4.0 | powershell | ok |
| Secret Rotation Validator | powershell | sonnet46-200k-medium | 3.5min | 11 | 0 | $0.48 | 4.0 | powershell | ok |
| Secret Rotation Validator | powershell-strict | opus46-200k-medium | 5.3min | 39 | 2 | $1.27 | 4.0 | powershell | ok |
| Secret Rotation Validator | powershell-strict | sonnet46-200k-medium | 4.0min | 20 | 0 | $0.53 | 4.0 | powershell | ok |
| CSV Report Generator | powershell | sonnet46-200k-medium | 2.1min | 9 | 0 | $0.31 | 3.0 | powershell | ok |
| REST API Client | powershell | sonnet46-200k-medium | 12.6min | 13 | 0 | $0.96 | 3.0 | powershell | ok |
| Process Monitor | default | opus46-200k-medium | 3.3min | 40 | 1 | $1.00 | 3.0 | python | ok |
| Batch File Renamer | powershell | sonnet46-200k-medium | 1.4min | 6 | 0 | $0.16 | 3.0 | powershell | ok |
| Multi-file Search and Replace | powershell-strict | opus46-200k-medium | 4.1min | 34 | 0 | $1.09 | 3.0 | powershell | ok |
| Test Results Aggregator | default | sonnet46-200k-medium | 4.0min | 20 | 1 | $0.49 | 3.0 | python | ok |
| Database Seed Script | default | sonnet46-200k-medium | 3.9min | 1 | 0 | $0.00 | — |  | failed |
| Database Seed Script | powershell | sonnet46-200k-medium | 3.8min | 1 | 0 | $0.00 | — | powershell | failed |
| Database Seed Script | powershell-strict | sonnet46-200k-medium | 3.6min | 1 | 0 | $0.00 | — | powershell | failed |
| Error Retry Pipeline | default | sonnet46-200k-medium | 3.7min | 1 | 0 | $0.00 | — |  | failed |
| Error Retry Pipeline | powershell | sonnet46-200k-medium | 3.8min | 1 | 0 | $0.00 | — | powershell | failed |
| Error Retry Pipeline | powershell-strict | sonnet46-200k-medium | 3.8min | 1 | 0 | $0.00 | — | powershell | failed |
| Multi-file Search and Replace | default | sonnet46-200k-medium | 3.9min | 1 | 0 | $0.00 | — |  | failed |
| Multi-file Search and Replace | powershell-strict | sonnet46-200k-medium | 3.8min | 1 | 0 | $0.00 | — | powershell | failed |
| Dependency License Checker | default | sonnet46-200k-medium | 4.0min | 1 | 0 | $0.00 | — |  | failed |

</details>

## Notes

### Tiers

- **Duration bands:** **A+** ≤1.21×, **A** ≤1.47×, **A-** ≤1.79×, **B+** ≤2.17×, **B** ≤2.63×, **B-** ≤3.19×, **C+** ≤3.87×, **C** ≤4.69×, **C-** ≤5.69×, **D+** ≤6.90×, **D** ≤8.37×, **D-** ≤10.16×, **F** >10.16×
- **Cost bands:** **A+** ≤1.21×, **A** ≤1.47×, **A-** ≤1.78×, **B+** ≤2.16×, **B** ≤2.61×, **B-** ≤3.17×, **C+** ≤3.84×, **C** ≤4.65×, **C-** ≤5.63×, **D+** ≤6.83×, **D** ≤8.27×, **D-** ≤10.03×, **F** >10.03×

*Tests/Workflow Craft bands are absolute Overall score bands:* **A+** ≥4.7, **A** ≥4.4, **A-** ≥4.1, **B+** ≥3.8, **B** ≥3.5, **B-** ≥3.2, **C+** ≥2.9, **C** ≥2.6, **C-** ≥2.3, **D+** ≥2.0, **D** ≥1.7, **D-** ≥1.4, **F** <1.4, `—` = no data.*

### CLI Version Legend

| Variant label | CLI version | Tasks | Languages |
|---------------|-------------|-------|-----------|
| opus46-200k-medium | 2.1.94 | 01-csv-report-generator, 02-log-file-analyzer, 03-directory-tree-sync, 04-rest-api-client, 05-process-monitor | default, powershell, powershell-strict |
| opus46-200k-medium | 2.1.96 | 01-csv-report-generator, 02-log-file-analyzer, 05-process-monitor, 06-config-file-migrator, 07-batch-file-renamer, 08-database-seed-script, 09-error-retry-pipeline, 10-multi-file-search-replace, 11-semantic-version-bumper, 12-pr-label-assigner, 13-dependency-license-checker, 14-docker-image-tag-generator, 15-test-results-aggregator, 16-environment-matrix-generator, 17-artifact-cleanup-script, 18-secret-rotation-validator | All |
| sonnet46-200k-medium | 2.1.94 | 01-csv-report-generator, 02-log-file-analyzer, 03-directory-tree-sync, 04-rest-api-client | default, powershell, powershell-strict |
| sonnet46-200k-medium | 2.1.96 | 01-csv-report-generator, 05-process-monitor, 06-config-file-migrator, 07-batch-file-renamer, 10-multi-file-search-replace, 11-semantic-version-bumper, 12-pr-label-assigner, 13-dependency-license-checker, 14-docker-image-tag-generator, 15-test-results-aggregator, 16-environment-matrix-generator, 17-artifact-cleanup-script, 18-secret-rotation-validator | All |

---
*Generated by generate_results.py — benchmark instructions v2*