# Benchmark Results: Language Comparison

**Last updated:** 2026-06-26 11:01:26 AM ET — 2/35 runs completed, 33 remaining; total cost $4.16; total agent time 17.2 min.
**Claude Code versions used:** v2.1.193 (2 runs). Each link goes to a per-version snapshot of the system prompt, default-tool descriptions, and the chronological Anthropic changelog up to that version. Regenerate with `python3 version_docs.py`.

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

| Language | Model | Duration | Cost | Tests Quality | Workflow Craft |
|----------|-------|----------|------|-----------|-------------|
| default | opus48-1m-medium | A+ (7.2min) | A+ ($1.83) | — | — |
| powershell | opus48-1m-medium | D- (10.0min) | D- ($2.33) | — | — |


<details>
<summary>Sorted by Duration tier (best-first), then avg of Cost/Tests/Workflow Craft tiers</summary>

| Language | Model | Duration | Cost | Tests Quality | Workflow Craft |
|----------|-------|----------|------|-----------|-------------|
| default | opus48-1m-medium | A+ (7.2min) | A+ ($1.83) | — | — |
| powershell | opus48-1m-medium | D- (10.0min) | D- ($2.33) | — | — |

</details>

<details>
<summary>Sorted by Cost tier (best-first), then avg of Duration/Tests/Workflow Craft tiers</summary>

| Language | Model | Duration | Cost | Tests Quality | Workflow Craft |
|----------|-------|----------|------|-----------|-------------|
| default | opus48-1m-medium | A+ (7.2min) | A+ ($1.83) | — | — |
| powershell | opus48-1m-medium | D- (10.0min) | D- ($2.33) | — | — |

</details>

<details>
<summary>Sorted by Tests Quality tier (best-first; no-data last), then avg of other tiers</summary>

| Language | Model | Duration | Cost | Tests Quality | Workflow Craft |
|----------|-------|----------|------|-----------|-------------|
| default | opus48-1m-medium | A+ (7.2min) | A+ ($1.83) | — | — |
| powershell | opus48-1m-medium | D- (10.0min) | D- ($2.33) | — | — |

</details>

<details>
<summary>Sorted by Workflow Craft tier (best-first; no-data last), then avg of other tiers</summary>

| Language | Model | Duration | Cost | Tests Quality | Workflow Craft |
|----------|-------|----------|------|-----------|-------------|
| default | opus48-1m-medium | A+ (7.2min) | A+ ($1.83) | — | — |
| powershell | opus48-1m-medium | D- (10.0min) | D- ($2.33) | — | — |

</details>

- **Estimated time remaining:** 283.8min
- **Estimated total cost:** $72.83

## Comparison by Language/Model/Effort
*See [Notes](#notes) for scoring rubric and CLI version legend.*

| Language | Model | Runs | Avg Duration | Avg Duration Net of Traps | Avg Errors | Avg Turns | Avg Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| default | opus48-1m-medium | 1 | 7.2min | 6.2min | 0.0 | 27 | $1.83 | $1.83 | — | — |
| powershell | opus48-1m-medium | 1 | 10.0min | 9.5min | 0.0 | 34 | $2.33 | $2.33 | — | — |


<details>
<summary>Sorted by avg cost (cheapest first)</summary>

| Language | Model | Runs | Avg Duration | Avg Duration Net of Traps | Avg Errors | Avg Turns | Avg Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| default | opus48-1m-medium | 1 | 7.2min | 6.2min | 0.0 | 27 | $1.83 | $1.83 | — | — |
| powershell | opus48-1m-medium | 1 | 10.0min | 9.5min | 0.0 | 34 | $2.33 | $2.33 | — | — |

</details>

<details>
<summary>Sorted by avg duration (fastest first)</summary>

| Language | Model | Runs | Avg Duration | Avg Duration Net of Traps | Avg Errors | Avg Turns | Avg Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| default | opus48-1m-medium | 1 | 7.2min | 6.2min | 0.0 | 27 | $1.83 | $1.83 | — | — |
| powershell | opus48-1m-medium | 1 | 10.0min | 9.5min | 0.0 | 34 | $2.33 | $2.33 | — | — |

</details>

<details>
<summary>Sorted by avg duration net of traps (fastest first)</summary>

| Language | Model | Runs | Avg Duration | Avg Duration Net of Traps | Avg Errors | Avg Turns | Avg Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| default | opus48-1m-medium | 1 | 7.2min | 6.2min | 0.0 | 27 | $1.83 | $1.83 | — | — |
| powershell | opus48-1m-medium | 1 | 10.0min | 9.5min | 0.0 | 34 | $2.33 | $2.33 | — | — |

</details>

<details>
<summary>Sorted by avg errors (fewest first)</summary>

| Language | Model | Runs | Avg Duration | Avg Duration Net of Traps | Avg Errors | Avg Turns | Avg Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| default | opus48-1m-medium | 1 | 7.2min | 6.2min | 0.0 | 27 | $1.83 | $1.83 | — | — |
| powershell | opus48-1m-medium | 1 | 10.0min | 9.5min | 0.0 | 34 | $2.33 | $2.33 | — | — |

</details>

<details>
<summary>Sorted by avg turns (fewest first)</summary>

| Language | Model | Runs | Avg Duration | Avg Duration Net of Traps | Avg Errors | Avg Turns | Avg Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| default | opus48-1m-medium | 1 | 7.2min | 6.2min | 0.0 | 27 | $1.83 | $1.83 | — | — |
| powershell | opus48-1m-medium | 1 | 10.0min | 9.5min | 0.0 | 34 | $2.33 | $2.33 | — | — |

</details>

<details>
<summary>Sorted by LLM-as-judge score (best first)</summary>

| Language | Model | Runs | Avg Duration | Avg Duration Net of Traps | Avg Errors | Avg Turns | Avg Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| default | opus48-1m-medium | 1 | 7.2min | 6.2min | 0.0 | 27 | $1.83 | $1.83 | — | — |
| powershell | opus48-1m-medium | 1 | 10.0min | 9.5min | 0.0 | 34 | $2.33 | $2.33 | — | — |

</details>

<details>
<summary>Sorted by deliverable-quality score (best first)</summary>

| Language | Model | Runs | Avg Duration | Avg Duration Net of Traps | Avg Errors | Avg Turns | Avg Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| default | opus48-1m-medium | 1 | 7.2min | 6.2min | 0.0 | 27 | $1.83 | $1.83 | — | — |
| powershell | opus48-1m-medium | 1 | 10.0min | 9.5min | 0.0 | 34 | $2.33 | $2.33 | — | — |

</details>

## Savings Analysis

### Hook Savings by Language/Model/Effort

Each hook-caught error avoids one test run that would otherwise have been needed to discover it.
Every hook fire (hit or miss) costs execution time for the syntax/type checker.

*`% of Test Time Saved` = `net / (net + test_time) × 100` — the share of total (would-have-been + actually-spent) test time that hooks eliminated. Bounded in (-∞, 100%) without an artificial cap; near 100% means hooks substituted for almost all of the hypothetical test work.*

| Language | Model | Fires | Caught | Rate | Gross Saved | % of Time | Overhead | % of Time | Net Saved | % of Time | Test Run Time | % of Test Time Saved |
|------|-------|-------|--------|------|------------|-----------|----------|-----------|-----------|-----------|---------------|----------------------|
| default | opus48-1m-medium-cli2.1.193 | 9 | 0 | 0.0% | 0.0min | 0.0% | 0.0min | 0.0% | -0.0min | -0.0% | 0.6min | -0.7% |
| powershell | opus48-1m-medium-cli2.1.193 | 15 | 0 | 0.0% | 0.0min | 0.0% | 0.1min | 0.5% | -0.1min | -0.5% | 1.7min | -5.3% |


<details>
<summary>Sorted by net saved (most first)</summary>

| Language | Model | Fires | Caught | Rate | Gross Saved | % of Time | Overhead | % of Time | Net Saved | % of Time | Test Run Time | % of Test Time Saved |
|------|-------|-------|--------|------|------------|-----------|----------|-----------|-----------|-----------|---------------|----------------------|
| default | opus48-1m-medium-cli2.1.193 | 9 | 0 | 0.0% | 0.0min | 0.0% | 0.0min | 0.0% | -0.0min | -0.0% | 0.6min | -0.7% |
| powershell | opus48-1m-medium-cli2.1.193 | 15 | 0 | 0.0% | 0.0min | 0.0% | 0.1min | 0.5% | -0.1min | -0.5% | 1.7min | -5.3% |

</details>

<details>
<summary>Sorted by net % of test time saved (most first)</summary>

| Language | Model | Fires | Caught | Rate | Gross Saved | % of Time | Overhead | % of Time | Net Saved | % of Time | Test Run Time | % of Test Time Saved |
|------|-------|-------|--------|------|------------|-----------|----------|-----------|-----------|-----------|---------------|----------------------|
| default | opus48-1m-medium-cli2.1.193 | 9 | 0 | 0.0% | 0.0min | 0.0% | 0.0min | 0.0% | -0.0min | -0.0% | 0.6min | -0.7% |
| powershell | opus48-1m-medium-cli2.1.193 | 15 | 0 | 0.0% | 0.0min | 0.0% | 0.1min | 0.5% | -0.1min | -0.5% | 1.7min | -5.3% |

</details>

<details>
<summary>Sorted by catch rate (highest first)</summary>

| Language | Model | Fires | Caught | Rate | Gross Saved | % of Time | Overhead | % of Time | Net Saved | % of Time | Test Run Time | % of Test Time Saved |
|------|-------|-------|--------|------|------------|-----------|----------|-----------|-----------|-----------|---------------|----------------------|
| default | opus48-1m-medium-cli2.1.193 | 9 | 0 | 0.0% | 0.0min | 0.0% | 0.0min | 0.0% | -0.0min | -0.0% | 0.6min | -0.7% |
| powershell | opus48-1m-medium-cli2.1.193 | 15 | 0 | 0.0% | 0.0min | 0.0% | 0.1min | 0.5% | -0.1min | -0.5% | 1.7min | -5.3% |

</details>

### Trap Analysis by Language/Model/Effort/Category

| Trap | Language | Model | Fell In | Time Lost | % of Time | $ Lost | % of $ |
|------|------|-------|---------|-----------|-----------|--------|--------|
| repeated-test-reruns | default | opus48-1m-medium-cli2.1.193 | 1 | 1.0min | 5.8% | $0.25 | 6.08% |
| fixture-rework | powershell | opus48-1m-medium-cli2.1.193 | 1 | 0.5min | 2.9% | $0.12 | 2.81% |


<details>
<summary>Sorted by time lost (least first)</summary>

| Trap | Language | Model | Fell In | Time Lost | % of Time | $ Lost | % of $ |
|------|------|-------|---------|-----------|-----------|--------|--------|
| fixture-rework | powershell | opus48-1m-medium-cli2.1.193 | 1 | 0.5min | 2.9% | $0.12 | 2.81% |
| repeated-test-reruns | default | opus48-1m-medium-cli2.1.193 | 1 | 1.0min | 5.8% | $0.25 | 6.08% |

</details>

<details>
<summary>Sorted by $ lost (least first)</summary>

| Trap | Language | Model | Fell In | Time Lost | % of Time | $ Lost | % of $ |
|------|------|-------|---------|-----------|-----------|--------|--------|
| fixture-rework | powershell | opus48-1m-medium-cli2.1.193 | 1 | 0.5min | 2.9% | $0.12 | 2.81% |
| repeated-test-reruns | default | opus48-1m-medium-cli2.1.193 | 1 | 1.0min | 5.8% | $0.25 | 6.08% |

</details>

<details>
<summary>Sorted by fell-in count (fewest first)</summary>

| Trap | Language | Model | Fell In | Time Lost | % of Time | $ Lost | % of $ |
|------|------|-------|---------|-----------|-----------|--------|--------|
| repeated-test-reruns | default | opus48-1m-medium-cli2.1.193 | 1 | 1.0min | 5.8% | $0.25 | 6.08% |
| fixture-rework | powershell | opus48-1m-medium-cli2.1.193 | 1 | 0.5min | 2.9% | $0.12 | 2.81% |

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
| default | opus48-1m-medium-cli2.1.193 | 1 | 1 | 1.0min | 5.8% | $0.25 | 6.08% |
| powershell | opus48-1m-medium-cli2.1.193 | 1 | 1 | 0.5min | 2.9% | $0.12 | 2.81% |


<details>
<summary>Sorted by time lost (least first)</summary>

| Language | Model | Runs | Traps | Time Lost | % of Time | $ Lost | % of $ |
|------|-------|------|-------|-----------|-----------|--------|--------|
| powershell | opus48-1m-medium-cli2.1.193 | 1 | 1 | 0.5min | 2.9% | $0.12 | 2.81% |
| default | opus48-1m-medium-cli2.1.193 | 1 | 1 | 1.0min | 5.8% | $0.25 | 6.08% |

</details>

<details>
<summary>Sorted by $ lost (least first)</summary>

| Language | Model | Runs | Traps | Time Lost | % of Time | $ Lost | % of $ |
|------|-------|------|-------|-----------|-----------|--------|--------|
| powershell | opus48-1m-medium-cli2.1.193 | 1 | 1 | 0.5min | 2.9% | $0.12 | 2.81% |
| default | opus48-1m-medium-cli2.1.193 | 1 | 1 | 1.0min | 5.8% | $0.25 | 6.08% |

</details>

### Prompt Cache Savings

| Status | Runs | $ Saved | % of $ |
|--------|------|---------|--------|
| Full hit (100%) | 0 | $0.00 | 0.00% |
| Partial | 1 | $0.10 | 2.42% |
| Miss | 1 | $0.00 | 0.00% |

## Test Quality Evaluation

### Structural Metrics by Language/Model/Effort

Automated analysis of test files: test count, assertion count, and test-to-code line ratio.

| Language | Model | Avg Tests | Avg Assertions | Avg Assert/Test | Avg Test:Code Ratio |
|------|-------|-----------|----------------|-----------------|---------------------|
| default | opus48-1m-medium | 38.0 | 61.0 | 1.6 | 1.60 |
| powershell | opus48-1m-medium | 39.0 | 62.0 | 1.6 | 6.77 |


<details>
<summary>Sorted by avg tests (most first)</summary>

| Language | Model | Avg Tests | Avg Assertions | Avg Assert/Test | Avg Test:Code Ratio |
|------|-------|-----------|----------------|-----------------|---------------------|
| powershell | opus48-1m-medium | 39.0 | 62.0 | 1.6 | 6.77 |
| default | opus48-1m-medium | 38.0 | 61.0 | 1.6 | 1.60 |

</details>

<details>
<summary>Sorted by avg assertions (most first)</summary>

| Language | Model | Avg Tests | Avg Assertions | Avg Assert/Test | Avg Test:Code Ratio |
|------|-------|-----------|----------------|-----------------|---------------------|
| powershell | opus48-1m-medium | 39.0 | 62.0 | 1.6 | 6.77 |
| default | opus48-1m-medium | 38.0 | 61.0 | 1.6 | 1.60 |

</details>

<details>
<summary>Sorted by avg test:code ratio (highest first)</summary>

| Language | Model | Avg Tests | Avg Assertions | Avg Assert/Test | Avg Test:Code Ratio |
|------|-------|-----------|----------------|-----------------|---------------------|
| powershell | opus48-1m-medium | 39.0 | 62.0 | 1.6 | 6.77 |
| default | opus48-1m-medium | 38.0 | 61.0 | 1.6 | 1.60 |

</details>


<details>
<summary>Per-run structural metrics</summary>

| Task | Language | Model | Tests | Assertions | Assert/Test | Test Lines | Impl Lines | Test:Code |
|------|------|-------|-------|------------|-------------|------------|------------|-----------|
| Semantic Version Bumper | default | opus48-1m-medium | 38 | 61 | 1.6 | 498 | 312 | 1.60 |
| Semantic Version Bumper | powershell | opus48-1m-medium | 39 | 62 | 1.6 | 359 | 53 | 6.77 |

</details>

## Per-Run Results

*Tests Quality = Overall (1-5) from LLM-as-judge of generated test code (dimensions: coverage, rigor, design). `—` = no judge data.*

| Task | Language | Model | Duration | Turns | Errors | Cost | Tests Quality | Chosen | Status |
|------|----------|-------|----------|-------|--------|------|-----------|--------|--------|
| Semantic Version Bumper | default | opus48-1m-medium | 7.2min | 27 | 0 | $1.83 | — | python | ok |
| Semantic Version Bumper | powershell | opus48-1m-medium | 10.0min | 34 | 0 | $2.33 | — | powershell | ok |


<details>
<summary>Sorted by cost (cheapest first)</summary>

| Task | Language | Model | Duration | Turns | Errors | Cost | Tests Quality | Chosen | Status |
|------|----------|-------|----------|-------|--------|------|-----------|--------|--------|
| Semantic Version Bumper | default | opus48-1m-medium | 7.2min | 27 | 0 | $1.83 | — | python | ok |
| Semantic Version Bumper | powershell | opus48-1m-medium | 10.0min | 34 | 0 | $2.33 | — | powershell | ok |

</details>

<details>
<summary>Sorted by duration (fastest first)</summary>

| Task | Language | Model | Duration | Turns | Errors | Cost | Tests Quality | Chosen | Status |
|------|----------|-------|----------|-------|--------|------|-----------|--------|--------|
| Semantic Version Bumper | default | opus48-1m-medium | 7.2min | 27 | 0 | $1.83 | — | python | ok |
| Semantic Version Bumper | powershell | opus48-1m-medium | 10.0min | 34 | 0 | $2.33 | — | powershell | ok |

</details>

<details>
<summary>Sorted by errors (fewest first)</summary>

| Task | Language | Model | Duration | Turns | Errors | Cost | Tests Quality | Chosen | Status |
|------|----------|-------|----------|-------|--------|------|-----------|--------|--------|
| Semantic Version Bumper | default | opus48-1m-medium | 7.2min | 27 | 0 | $1.83 | — | python | ok |
| Semantic Version Bumper | powershell | opus48-1m-medium | 10.0min | 34 | 0 | $2.33 | — | powershell | ok |

</details>

<details>
<summary>Sorted by turns (fewest first)</summary>

| Task | Language | Model | Duration | Turns | Errors | Cost | Tests Quality | Chosen | Status |
|------|----------|-------|----------|-------|--------|------|-----------|--------|--------|
| Semantic Version Bumper | default | opus48-1m-medium | 7.2min | 27 | 0 | $1.83 | — | python | ok |
| Semantic Version Bumper | powershell | opus48-1m-medium | 10.0min | 34 | 0 | $2.33 | — | powershell | ok |

</details>

<details>
<summary>Sorted by LLM-as-judge score (best first)</summary>

| Task | Language | Model | Duration | Turns | Errors | Cost | Tests Quality | Chosen | Status |
|------|----------|-------|----------|-------|--------|------|-----------|--------|--------|
| Semantic Version Bumper | default | opus48-1m-medium | 7.2min | 27 | 0 | $1.83 | — | python | ok |
| Semantic Version Bumper | powershell | opus48-1m-medium | 10.0min | 34 | 0 | $2.33 | — | powershell | ok |

</details>

## Notes

### Tiers

- **Duration bands:** **A+** ≤1.03×, **A** ≤1.05×, **A-** ≤1.08×, **B+** ≤1.11×, **B** ≤1.14×, **B-** ≤1.17×, **C+** ≤1.20×, **C** ≤1.24×, **C-** ≤1.27×, **D+** ≤1.30×, **D** ≤1.34×, **D-** ≤1.38×, **F** >1.38×
- **Cost bands:** **A+** ≤1.02×, **A** ≤1.04×, **A-** ≤1.06×, **B+** ≤1.08×, **B** ≤1.11×, **B-** ≤1.13×, **C+** ≤1.15×, **C** ≤1.18×, **C-** ≤1.20×, **D+** ≤1.22×, **D** ≤1.25×, **D-** ≤1.27×, **F** >1.27×

*Tests/Workflow Craft bands are absolute Overall score bands:* **A+** ≥4.7, **A** ≥4.4, **A-** ≥4.1, **B+** ≥3.8, **B** ≥3.5, **B-** ≥3.2, **C+** ≥2.9, **C** ≥2.6, **C-** ≥2.3, **D+** ≥2.0, **D** ≥1.7, **D-** ≥1.4, **F** <1.4, `—` = no data.*

### CLI Version Legend

| Variant label | CLI version | Tasks | Languages |
|---------------|-------------|-------|-----------|
| opus48-1m-medium | 2.1.193 | All | All |

---
*Generated by generate_results.py — benchmark instructions v4*