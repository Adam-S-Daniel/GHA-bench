# Benchmark Results: Language Comparison

**Last updated:** 2026-06-28 09:00:16 AM ET — 117/140 runs completed, 23 remaining; total cost $437.04; total agent time 1714.8 min.
**Claude Code versions used:** v2.1.193 (23 runs), v2.1.195 (94 runs). Each link goes to a per-version snapshot of the system prompt, default-tool descriptions, and the chronological Anthropic changelog up to that version. Regenerate with `python3 version_docs.py`.

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
*`*` after a Model label = this combo's aggregates exclude one or more failed/timed-out runs (see the Failed / Timed-Out Runs table).*

| Language | Model | Duration | Cost | Tests Quality | Workflow Craft |
|----------|-------|----------|------|-----------|-------------|
| default | opus48-1m-medium | A+ (7.5min) | A+ ($1.89) | — | — |
| powershell | opus48-1m-medium | A+ (7.4min) | A+ ($1.81) | — | — |
| bash | opus48-1m-medium | A- (9.2min) | A- ($2.38) | — | — |
| default | opus48-1m-high | A- (9.4min) | B+ ($2.74) | — | — |
| powershell-tool | opus48-1m-medium | B+ (10.1min) | A- ($2.57) | — | — |
| bash | opus48-1m-high | B+ (10.5min) | B+ ($2.80) | — | — |
| powershell-tool | opus48-1m-high | B (12.4min) | B+ ($2.89) | — | — |
| typescript-bun | opus48-1m-medium | B (11.7min) | B+ ($2.73) | — | — |
| powershell | opus48-1m-high | B- (13.8min) | B ($3.24) | — | — |
| typescript-bun | opus48-1m-high | B (12.2min) | B- ($3.68) | — | — |
| default | opus48-1m-xhigh | C+ (15.3min) | C+ ($4.48) | — | — |
| default | opus48-1m-ultracode | C (16.2min) | C ($4.65) | — | — |
| bash | opus48-1m-ultracode | D+ (19.7min) | C- ($5.67) | — | — |
| bash | opus48-1m-xhigh | D+ (20.3min) | C- ($5.74) | — | — |
| typescript-bun | opus48-1m-xhigh | D+ (20.4min) | C- ($5.76) | — | — |
| powershell | opus48-1m-ultracode | D+ (19.1min) | D+ ($6.76) | — | — |
| powershell | opus48-1m-xhigh* | D (21.9min) | D+ ($6.08) | — | — |
| powershell-tool | opus48-1m-ultracode | D- (23.7min) | D+ ($6.18) | — | — |
| powershell-tool | opus48-1m-xhigh* | D- (24.6min) | D+ ($6.51) | — | — |
| typescript-bun | opus48-1m-ultracode | D- (26.0min) | D- ($8.85) | — | — |


<details>
<summary>Sorted by Duration tier (best-first), then avg of Cost/Tests/Workflow Craft tiers</summary>

| Language | Model | Duration | Cost | Tests Quality | Workflow Craft |
|----------|-------|----------|------|-----------|-------------|
| default | opus48-1m-medium | A+ (7.5min) | A+ ($1.89) | — | — |
| powershell | opus48-1m-medium | A+ (7.4min) | A+ ($1.81) | — | — |
| bash | opus48-1m-medium | A- (9.2min) | A- ($2.38) | — | — |
| default | opus48-1m-high | A- (9.4min) | B+ ($2.74) | — | — |
| powershell-tool | opus48-1m-medium | B+ (10.1min) | A- ($2.57) | — | — |
| bash | opus48-1m-high | B+ (10.5min) | B+ ($2.80) | — | — |
| powershell-tool | opus48-1m-high | B (12.4min) | B+ ($2.89) | — | — |
| typescript-bun | opus48-1m-medium | B (11.7min) | B+ ($2.73) | — | — |
| typescript-bun | opus48-1m-high | B (12.2min) | B- ($3.68) | — | — |
| powershell | opus48-1m-high | B- (13.8min) | B ($3.24) | — | — |
| default | opus48-1m-xhigh | C+ (15.3min) | C+ ($4.48) | — | — |
| default | opus48-1m-ultracode | C (16.2min) | C ($4.65) | — | — |
| bash | opus48-1m-ultracode | D+ (19.7min) | C- ($5.67) | — | — |
| bash | opus48-1m-xhigh | D+ (20.3min) | C- ($5.74) | — | — |
| typescript-bun | opus48-1m-xhigh | D+ (20.4min) | C- ($5.76) | — | — |
| powershell | opus48-1m-ultracode | D+ (19.1min) | D+ ($6.76) | — | — |
| powershell | opus48-1m-xhigh* | D (21.9min) | D+ ($6.08) | — | — |
| powershell-tool | opus48-1m-ultracode | D- (23.7min) | D+ ($6.18) | — | — |
| powershell-tool | opus48-1m-xhigh* | D- (24.6min) | D+ ($6.51) | — | — |
| typescript-bun | opus48-1m-ultracode | D- (26.0min) | D- ($8.85) | — | — |

</details>

<details>
<summary>Sorted by Cost tier (best-first), then avg of Duration/Tests/Workflow Craft tiers</summary>

| Language | Model | Duration | Cost | Tests Quality | Workflow Craft |
|----------|-------|----------|------|-----------|-------------|
| default | opus48-1m-medium | A+ (7.5min) | A+ ($1.89) | — | — |
| powershell | opus48-1m-medium | A+ (7.4min) | A+ ($1.81) | — | — |
| bash | opus48-1m-medium | A- (9.2min) | A- ($2.38) | — | — |
| powershell-tool | opus48-1m-medium | B+ (10.1min) | A- ($2.57) | — | — |
| default | opus48-1m-high | A- (9.4min) | B+ ($2.74) | — | — |
| bash | opus48-1m-high | B+ (10.5min) | B+ ($2.80) | — | — |
| powershell-tool | opus48-1m-high | B (12.4min) | B+ ($2.89) | — | — |
| typescript-bun | opus48-1m-medium | B (11.7min) | B+ ($2.73) | — | — |
| powershell | opus48-1m-high | B- (13.8min) | B ($3.24) | — | — |
| typescript-bun | opus48-1m-high | B (12.2min) | B- ($3.68) | — | — |
| default | opus48-1m-xhigh | C+ (15.3min) | C+ ($4.48) | — | — |
| default | opus48-1m-ultracode | C (16.2min) | C ($4.65) | — | — |
| bash | opus48-1m-ultracode | D+ (19.7min) | C- ($5.67) | — | — |
| bash | opus48-1m-xhigh | D+ (20.3min) | C- ($5.74) | — | — |
| typescript-bun | opus48-1m-xhigh | D+ (20.4min) | C- ($5.76) | — | — |
| powershell | opus48-1m-ultracode | D+ (19.1min) | D+ ($6.76) | — | — |
| powershell | opus48-1m-xhigh* | D (21.9min) | D+ ($6.08) | — | — |
| powershell-tool | opus48-1m-ultracode | D- (23.7min) | D+ ($6.18) | — | — |
| powershell-tool | opus48-1m-xhigh* | D- (24.6min) | D+ ($6.51) | — | — |
| typescript-bun | opus48-1m-ultracode | D- (26.0min) | D- ($8.85) | — | — |

</details>

<details>
<summary>Sorted by Tests Quality tier (best-first; no-data last), then avg of other tiers</summary>

| Language | Model | Duration | Cost | Tests Quality | Workflow Craft |
|----------|-------|----------|------|-----------|-------------|
| default | opus48-1m-medium | A+ (7.5min) | A+ ($1.89) | — | — |
| powershell | opus48-1m-medium | A+ (7.4min) | A+ ($1.81) | — | — |
| bash | opus48-1m-medium | A- (9.2min) | A- ($2.38) | — | — |
| default | opus48-1m-high | A- (9.4min) | B+ ($2.74) | — | — |
| powershell-tool | opus48-1m-medium | B+ (10.1min) | A- ($2.57) | — | — |
| bash | opus48-1m-high | B+ (10.5min) | B+ ($2.80) | — | — |
| powershell-tool | opus48-1m-high | B (12.4min) | B+ ($2.89) | — | — |
| typescript-bun | opus48-1m-medium | B (11.7min) | B+ ($2.73) | — | — |
| powershell | opus48-1m-high | B- (13.8min) | B ($3.24) | — | — |
| typescript-bun | opus48-1m-high | B (12.2min) | B- ($3.68) | — | — |
| default | opus48-1m-xhigh | C+ (15.3min) | C+ ($4.48) | — | — |
| default | opus48-1m-ultracode | C (16.2min) | C ($4.65) | — | — |
| bash | opus48-1m-ultracode | D+ (19.7min) | C- ($5.67) | — | — |
| bash | opus48-1m-xhigh | D+ (20.3min) | C- ($5.74) | — | — |
| typescript-bun | opus48-1m-xhigh | D+ (20.4min) | C- ($5.76) | — | — |
| powershell | opus48-1m-ultracode | D+ (19.1min) | D+ ($6.76) | — | — |
| powershell | opus48-1m-xhigh* | D (21.9min) | D+ ($6.08) | — | — |
| powershell-tool | opus48-1m-ultracode | D- (23.7min) | D+ ($6.18) | — | — |
| powershell-tool | opus48-1m-xhigh* | D- (24.6min) | D+ ($6.51) | — | — |
| typescript-bun | opus48-1m-ultracode | D- (26.0min) | D- ($8.85) | — | — |

</details>

<details>
<summary>Sorted by Workflow Craft tier (best-first; no-data last), then avg of other tiers</summary>

| Language | Model | Duration | Cost | Tests Quality | Workflow Craft |
|----------|-------|----------|------|-----------|-------------|
| default | opus48-1m-medium | A+ (7.5min) | A+ ($1.89) | — | — |
| powershell | opus48-1m-medium | A+ (7.4min) | A+ ($1.81) | — | — |
| bash | opus48-1m-medium | A- (9.2min) | A- ($2.38) | — | — |
| default | opus48-1m-high | A- (9.4min) | B+ ($2.74) | — | — |
| powershell-tool | opus48-1m-medium | B+ (10.1min) | A- ($2.57) | — | — |
| bash | opus48-1m-high | B+ (10.5min) | B+ ($2.80) | — | — |
| powershell-tool | opus48-1m-high | B (12.4min) | B+ ($2.89) | — | — |
| typescript-bun | opus48-1m-medium | B (11.7min) | B+ ($2.73) | — | — |
| powershell | opus48-1m-high | B- (13.8min) | B ($3.24) | — | — |
| typescript-bun | opus48-1m-high | B (12.2min) | B- ($3.68) | — | — |
| default | opus48-1m-xhigh | C+ (15.3min) | C+ ($4.48) | — | — |
| default | opus48-1m-ultracode | C (16.2min) | C ($4.65) | — | — |
| bash | opus48-1m-ultracode | D+ (19.7min) | C- ($5.67) | — | — |
| bash | opus48-1m-xhigh | D+ (20.3min) | C- ($5.74) | — | — |
| typescript-bun | opus48-1m-xhigh | D+ (20.4min) | C- ($5.76) | — | — |
| powershell | opus48-1m-ultracode | D+ (19.1min) | D+ ($6.76) | — | — |
| powershell | opus48-1m-xhigh* | D (21.9min) | D+ ($6.08) | — | — |
| powershell-tool | opus48-1m-ultracode | D- (23.7min) | D+ ($6.18) | — | — |
| powershell-tool | opus48-1m-xhigh* | D- (24.6min) | D+ ($6.51) | — | — |
| typescript-bun | opus48-1m-ultracode | D- (26.0min) | D- ($8.85) | — | — |

</details>

- **Estimated time remaining:** 1876.0min
- **Estimated total cost:** $522.96

## Failed / Timed-Out Runs

| Task | Language | Model | Duration | Reason | Lines | actionlint | act-result.txt |
|------|------|-------|----------|--------|-------|------------|----------------|
| PR Label Assigner | powershell-tool | opus48-1m-xhigh | 30.0min | timeout | 791 | pass | yes |
| Dependency License Checker | powershell | opus48-1m-xhigh | 30.0min | timeout | 880 | pass | yes |
| Environment Matrix Generator | powershell-tool | opus48-1m-xhigh | 30.0min | timeout | 1190 | pass | no |
| Artifact Cleanup Script | powershell-tool | opus48-1m-xhigh | 30.0min | timeout | 952 | pass | yes |

*4 run(s) excluded from averages below.*

## Comparison by Language/Model/Effort
*(averages exclude failed/timed-out runs)*
*See [Notes](#notes) for scoring rubric and CLI version legend.*

| Language | Model | Runs | Avg Duration | Avg Duration Net of Traps | Avg Errors | Avg Turns | Avg Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| bash | opus48-1m-high | 7 | 10.5min | 7.9min | 0.7 | 39 | $2.80 | $19.59 | — | — |
| bash | opus48-1m-medium | 7 | 9.2min | 9.2min | 1.1 | 34 | $2.38 | $16.64 | — | — |
| bash | opus48-1m-ultracode | 2 | 19.7min | 18.2min | 1.0 | 64 | $5.67 | $11.33 | — | — |
| bash | opus48-1m-xhigh | 7 | 20.3min | 17.0min | 1.3 | 60 | $5.74 | $40.21 | — | — |
| default | opus48-1m-high | 7 | 9.4min | 7.9min | 0.3 | 42 | $2.74 | $19.15 | — | — |
| default | opus48-1m-medium | 7 | 7.5min | 7.5min | 0.1 | 32 | $1.89 | $13.21 | — | — |
| default | opus48-1m-ultracode | 3 | 16.2min | 13.7min | 0.0 | 54 | $4.65 | $13.95 | — | — |
| default | opus48-1m-xhigh | 7 | 15.3min | 12.4min | 0.1 | 48 | $4.48 | $31.34 | — | — |
| powershell | opus48-1m-high | 7 | 13.8min | 10.3min | 0.9 | 49 | $3.24 | $22.70 | — | — |
| powershell | opus48-1m-medium | 7 | 7.4min | 7.4min | 0.0 | 27 | $1.81 | $12.64 | — | — |
| powershell | opus48-1m-ultracode | 3 | 19.1min | 15.1min | 0.7 | 47 | $6.76 | $20.28 | — | — |
| powershell | opus48-1m-xhigh* | 6 | 21.9min | 18.3min | 0.3 | 64 | $6.08 | $36.46 | — | — |
| powershell-tool | opus48-1m-high | 7 | 12.4min | 11.1min | 0.1 | 35 | $2.89 | $20.22 | — | — |
| powershell-tool | opus48-1m-medium | 7 | 10.1min | 10.1min | 0.9 | 40 | $2.57 | $18.00 | — | — |
| powershell-tool | opus48-1m-ultracode | 2 | 23.7min | 20.6min | 0.5 | 54 | $6.18 | $12.37 | — | — |
| powershell-tool | opus48-1m-xhigh* | 4 | 24.6min | 16.8min | 0.8 | 64 | $6.51 | $26.06 | — | — |
| typescript-bun | opus48-1m-high | 7 | 12.2min | 8.1min | 0.4 | 56 | $3.68 | $25.77 | — | — |
| typescript-bun | opus48-1m-medium | 7 | 11.7min | 11.7min | 0.6 | 49 | $2.73 | $19.09 | — | — |
| typescript-bun | opus48-1m-ultracode | 2 | 26.0min | 20.5min | 2.5 | 83 | $8.85 | $17.71 | — | — |
| typescript-bun | opus48-1m-xhigh | 7 | 20.4min | 15.6min | 0.9 | 60 | $5.76 | $40.33 | — | — |


<details>
<summary>Sorted by avg cost (cheapest first)</summary>

| Language | Model | Runs | Avg Duration | Avg Duration Net of Traps | Avg Errors | Avg Turns | Avg Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| powershell | opus48-1m-medium | 7 | 7.4min | 7.4min | 0.0 | 27 | $1.81 | $12.64 | — | — |
| default | opus48-1m-medium | 7 | 7.5min | 7.5min | 0.1 | 32 | $1.89 | $13.21 | — | — |
| bash | opus48-1m-medium | 7 | 9.2min | 9.2min | 1.1 | 34 | $2.38 | $16.64 | — | — |
| powershell-tool | opus48-1m-medium | 7 | 10.1min | 10.1min | 0.9 | 40 | $2.57 | $18.00 | — | — |
| typescript-bun | opus48-1m-medium | 7 | 11.7min | 11.7min | 0.6 | 49 | $2.73 | $19.09 | — | — |
| default | opus48-1m-high | 7 | 9.4min | 7.9min | 0.3 | 42 | $2.74 | $19.15 | — | — |
| bash | opus48-1m-high | 7 | 10.5min | 7.9min | 0.7 | 39 | $2.80 | $19.59 | — | — |
| powershell-tool | opus48-1m-high | 7 | 12.4min | 11.1min | 0.1 | 35 | $2.89 | $20.22 | — | — |
| powershell | opus48-1m-high | 7 | 13.8min | 10.3min | 0.9 | 49 | $3.24 | $22.70 | — | — |
| typescript-bun | opus48-1m-high | 7 | 12.2min | 8.1min | 0.4 | 56 | $3.68 | $25.77 | — | — |
| default | opus48-1m-xhigh | 7 | 15.3min | 12.4min | 0.1 | 48 | $4.48 | $31.34 | — | — |
| default | opus48-1m-ultracode | 3 | 16.2min | 13.7min | 0.0 | 54 | $4.65 | $13.95 | — | — |
| bash | opus48-1m-ultracode | 2 | 19.7min | 18.2min | 1.0 | 64 | $5.67 | $11.33 | — | — |
| bash | opus48-1m-xhigh | 7 | 20.3min | 17.0min | 1.3 | 60 | $5.74 | $40.21 | — | — |
| typescript-bun | opus48-1m-xhigh | 7 | 20.4min | 15.6min | 0.9 | 60 | $5.76 | $40.33 | — | — |
| powershell | opus48-1m-xhigh* | 6 | 21.9min | 18.3min | 0.3 | 64 | $6.08 | $36.46 | — | — |
| powershell-tool | opus48-1m-ultracode | 2 | 23.7min | 20.6min | 0.5 | 54 | $6.18 | $12.37 | — | — |
| powershell-tool | opus48-1m-xhigh* | 4 | 24.6min | 16.8min | 0.8 | 64 | $6.51 | $26.06 | — | — |
| powershell | opus48-1m-ultracode | 3 | 19.1min | 15.1min | 0.7 | 47 | $6.76 | $20.28 | — | — |
| typescript-bun | opus48-1m-ultracode | 2 | 26.0min | 20.5min | 2.5 | 83 | $8.85 | $17.71 | — | — |

</details>

<details>
<summary>Sorted by avg duration (fastest first)</summary>

| Language | Model | Runs | Avg Duration | Avg Duration Net of Traps | Avg Errors | Avg Turns | Avg Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| powershell | opus48-1m-medium | 7 | 7.4min | 7.4min | 0.0 | 27 | $1.81 | $12.64 | — | — |
| default | opus48-1m-medium | 7 | 7.5min | 7.5min | 0.1 | 32 | $1.89 | $13.21 | — | — |
| bash | opus48-1m-medium | 7 | 9.2min | 9.2min | 1.1 | 34 | $2.38 | $16.64 | — | — |
| default | opus48-1m-high | 7 | 9.4min | 7.9min | 0.3 | 42 | $2.74 | $19.15 | — | — |
| powershell-tool | opus48-1m-medium | 7 | 10.1min | 10.1min | 0.9 | 40 | $2.57 | $18.00 | — | — |
| bash | opus48-1m-high | 7 | 10.5min | 7.9min | 0.7 | 39 | $2.80 | $19.59 | — | — |
| typescript-bun | opus48-1m-medium | 7 | 11.7min | 11.7min | 0.6 | 49 | $2.73 | $19.09 | — | — |
| typescript-bun | opus48-1m-high | 7 | 12.2min | 8.1min | 0.4 | 56 | $3.68 | $25.77 | — | — |
| powershell-tool | opus48-1m-high | 7 | 12.4min | 11.1min | 0.1 | 35 | $2.89 | $20.22 | — | — |
| powershell | opus48-1m-high | 7 | 13.8min | 10.3min | 0.9 | 49 | $3.24 | $22.70 | — | — |
| default | opus48-1m-xhigh | 7 | 15.3min | 12.4min | 0.1 | 48 | $4.48 | $31.34 | — | — |
| default | opus48-1m-ultracode | 3 | 16.2min | 13.7min | 0.0 | 54 | $4.65 | $13.95 | — | — |
| powershell | opus48-1m-ultracode | 3 | 19.1min | 15.1min | 0.7 | 47 | $6.76 | $20.28 | — | — |
| bash | opus48-1m-ultracode | 2 | 19.7min | 18.2min | 1.0 | 64 | $5.67 | $11.33 | — | — |
| bash | opus48-1m-xhigh | 7 | 20.3min | 17.0min | 1.3 | 60 | $5.74 | $40.21 | — | — |
| typescript-bun | opus48-1m-xhigh | 7 | 20.4min | 15.6min | 0.9 | 60 | $5.76 | $40.33 | — | — |
| powershell | opus48-1m-xhigh* | 6 | 21.9min | 18.3min | 0.3 | 64 | $6.08 | $36.46 | — | — |
| powershell-tool | opus48-1m-ultracode | 2 | 23.7min | 20.6min | 0.5 | 54 | $6.18 | $12.37 | — | — |
| powershell-tool | opus48-1m-xhigh* | 4 | 24.6min | 16.8min | 0.8 | 64 | $6.51 | $26.06 | — | — |
| typescript-bun | opus48-1m-ultracode | 2 | 26.0min | 20.5min | 2.5 | 83 | $8.85 | $17.71 | — | — |

</details>

<details>
<summary>Sorted by avg duration net of traps (fastest first)</summary>

| Language | Model | Runs | Avg Duration | Avg Duration Net of Traps | Avg Errors | Avg Turns | Avg Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| powershell | opus48-1m-medium | 7 | 7.4min | 7.4min | 0.0 | 27 | $1.81 | $12.64 | — | — |
| default | opus48-1m-medium | 7 | 7.5min | 7.5min | 0.1 | 32 | $1.89 | $13.21 | — | — |
| bash | opus48-1m-high | 7 | 10.5min | 7.9min | 0.7 | 39 | $2.80 | $19.59 | — | — |
| default | opus48-1m-high | 7 | 9.4min | 7.9min | 0.3 | 42 | $2.74 | $19.15 | — | — |
| typescript-bun | opus48-1m-high | 7 | 12.2min | 8.1min | 0.4 | 56 | $3.68 | $25.77 | — | — |
| bash | opus48-1m-medium | 7 | 9.2min | 9.2min | 1.1 | 34 | $2.38 | $16.64 | — | — |
| powershell-tool | opus48-1m-medium | 7 | 10.1min | 10.1min | 0.9 | 40 | $2.57 | $18.00 | — | — |
| powershell | opus48-1m-high | 7 | 13.8min | 10.3min | 0.9 | 49 | $3.24 | $22.70 | — | — |
| powershell-tool | opus48-1m-high | 7 | 12.4min | 11.1min | 0.1 | 35 | $2.89 | $20.22 | — | — |
| typescript-bun | opus48-1m-medium | 7 | 11.7min | 11.7min | 0.6 | 49 | $2.73 | $19.09 | — | — |
| default | opus48-1m-xhigh | 7 | 15.3min | 12.4min | 0.1 | 48 | $4.48 | $31.34 | — | — |
| default | opus48-1m-ultracode | 3 | 16.2min | 13.7min | 0.0 | 54 | $4.65 | $13.95 | — | — |
| powershell | opus48-1m-ultracode | 3 | 19.1min | 15.1min | 0.7 | 47 | $6.76 | $20.28 | — | — |
| typescript-bun | opus48-1m-xhigh | 7 | 20.4min | 15.6min | 0.9 | 60 | $5.76 | $40.33 | — | — |
| powershell-tool | opus48-1m-xhigh* | 4 | 24.6min | 16.8min | 0.8 | 64 | $6.51 | $26.06 | — | — |
| bash | opus48-1m-xhigh | 7 | 20.3min | 17.0min | 1.3 | 60 | $5.74 | $40.21 | — | — |
| bash | opus48-1m-ultracode | 2 | 19.7min | 18.2min | 1.0 | 64 | $5.67 | $11.33 | — | — |
| powershell | opus48-1m-xhigh* | 6 | 21.9min | 18.3min | 0.3 | 64 | $6.08 | $36.46 | — | — |
| typescript-bun | opus48-1m-ultracode | 2 | 26.0min | 20.5min | 2.5 | 83 | $8.85 | $17.71 | — | — |
| powershell-tool | opus48-1m-ultracode | 2 | 23.7min | 20.6min | 0.5 | 54 | $6.18 | $12.37 | — | — |

</details>

<details>
<summary>Sorted by avg errors (fewest first)</summary>

| Language | Model | Runs | Avg Duration | Avg Duration Net of Traps | Avg Errors | Avg Turns | Avg Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| default | opus48-1m-ultracode | 3 | 16.2min | 13.7min | 0.0 | 54 | $4.65 | $13.95 | — | — |
| powershell | opus48-1m-medium | 7 | 7.4min | 7.4min | 0.0 | 27 | $1.81 | $12.64 | — | — |
| default | opus48-1m-medium | 7 | 7.5min | 7.5min | 0.1 | 32 | $1.89 | $13.21 | — | — |
| default | opus48-1m-xhigh | 7 | 15.3min | 12.4min | 0.1 | 48 | $4.48 | $31.34 | — | — |
| powershell-tool | opus48-1m-high | 7 | 12.4min | 11.1min | 0.1 | 35 | $2.89 | $20.22 | — | — |
| default | opus48-1m-high | 7 | 9.4min | 7.9min | 0.3 | 42 | $2.74 | $19.15 | — | — |
| powershell | opus48-1m-xhigh* | 6 | 21.9min | 18.3min | 0.3 | 64 | $6.08 | $36.46 | — | — |
| typescript-bun | opus48-1m-high | 7 | 12.2min | 8.1min | 0.4 | 56 | $3.68 | $25.77 | — | — |
| powershell-tool | opus48-1m-ultracode | 2 | 23.7min | 20.6min | 0.5 | 54 | $6.18 | $12.37 | — | — |
| typescript-bun | opus48-1m-medium | 7 | 11.7min | 11.7min | 0.6 | 49 | $2.73 | $19.09 | — | — |
| powershell | opus48-1m-ultracode | 3 | 19.1min | 15.1min | 0.7 | 47 | $6.76 | $20.28 | — | — |
| bash | opus48-1m-high | 7 | 10.5min | 7.9min | 0.7 | 39 | $2.80 | $19.59 | — | — |
| powershell-tool | opus48-1m-xhigh* | 4 | 24.6min | 16.8min | 0.8 | 64 | $6.51 | $26.06 | — | — |
| powershell | opus48-1m-high | 7 | 13.8min | 10.3min | 0.9 | 49 | $3.24 | $22.70 | — | — |
| powershell-tool | opus48-1m-medium | 7 | 10.1min | 10.1min | 0.9 | 40 | $2.57 | $18.00 | — | — |
| typescript-bun | opus48-1m-xhigh | 7 | 20.4min | 15.6min | 0.9 | 60 | $5.76 | $40.33 | — | — |
| bash | opus48-1m-ultracode | 2 | 19.7min | 18.2min | 1.0 | 64 | $5.67 | $11.33 | — | — |
| bash | opus48-1m-medium | 7 | 9.2min | 9.2min | 1.1 | 34 | $2.38 | $16.64 | — | — |
| bash | opus48-1m-xhigh | 7 | 20.3min | 17.0min | 1.3 | 60 | $5.74 | $40.21 | — | — |
| typescript-bun | opus48-1m-ultracode | 2 | 26.0min | 20.5min | 2.5 | 83 | $8.85 | $17.71 | — | — |

</details>

<details>
<summary>Sorted by avg turns (fewest first)</summary>

| Language | Model | Runs | Avg Duration | Avg Duration Net of Traps | Avg Errors | Avg Turns | Avg Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| powershell | opus48-1m-medium | 7 | 7.4min | 7.4min | 0.0 | 27 | $1.81 | $12.64 | — | — |
| default | opus48-1m-medium | 7 | 7.5min | 7.5min | 0.1 | 32 | $1.89 | $13.21 | — | — |
| bash | opus48-1m-medium | 7 | 9.2min | 9.2min | 1.1 | 34 | $2.38 | $16.64 | — | — |
| powershell-tool | opus48-1m-high | 7 | 12.4min | 11.1min | 0.1 | 35 | $2.89 | $20.22 | — | — |
| bash | opus48-1m-high | 7 | 10.5min | 7.9min | 0.7 | 39 | $2.80 | $19.59 | — | — |
| powershell-tool | opus48-1m-medium | 7 | 10.1min | 10.1min | 0.9 | 40 | $2.57 | $18.00 | — | — |
| default | opus48-1m-high | 7 | 9.4min | 7.9min | 0.3 | 42 | $2.74 | $19.15 | — | — |
| powershell | opus48-1m-ultracode | 3 | 19.1min | 15.1min | 0.7 | 47 | $6.76 | $20.28 | — | — |
| default | opus48-1m-xhigh | 7 | 15.3min | 12.4min | 0.1 | 48 | $4.48 | $31.34 | — | — |
| powershell | opus48-1m-high | 7 | 13.8min | 10.3min | 0.9 | 49 | $3.24 | $22.70 | — | — |
| typescript-bun | opus48-1m-medium | 7 | 11.7min | 11.7min | 0.6 | 49 | $2.73 | $19.09 | — | — |
| default | opus48-1m-ultracode | 3 | 16.2min | 13.7min | 0.0 | 54 | $4.65 | $13.95 | — | — |
| powershell-tool | opus48-1m-ultracode | 2 | 23.7min | 20.6min | 0.5 | 54 | $6.18 | $12.37 | — | — |
| typescript-bun | opus48-1m-high | 7 | 12.2min | 8.1min | 0.4 | 56 | $3.68 | $25.77 | — | — |
| typescript-bun | opus48-1m-xhigh | 7 | 20.4min | 15.6min | 0.9 | 60 | $5.76 | $40.33 | — | — |
| bash | opus48-1m-xhigh | 7 | 20.3min | 17.0min | 1.3 | 60 | $5.74 | $40.21 | — | — |
| powershell | opus48-1m-xhigh* | 6 | 21.9min | 18.3min | 0.3 | 64 | $6.08 | $36.46 | — | — |
| powershell-tool | opus48-1m-xhigh* | 4 | 24.6min | 16.8min | 0.8 | 64 | $6.51 | $26.06 | — | — |
| bash | opus48-1m-ultracode | 2 | 19.7min | 18.2min | 1.0 | 64 | $5.67 | $11.33 | — | — |
| typescript-bun | opus48-1m-ultracode | 2 | 26.0min | 20.5min | 2.5 | 83 | $8.85 | $17.71 | — | — |

</details>

<details>
<summary>Sorted by LLM-as-judge score (best first)</summary>

| Language | Model | Runs | Avg Duration | Avg Duration Net of Traps | Avg Errors | Avg Turns | Avg Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| bash | opus48-1m-high | 7 | 10.5min | 7.9min | 0.7 | 39 | $2.80 | $19.59 | — | — |
| bash | opus48-1m-medium | 7 | 9.2min | 9.2min | 1.1 | 34 | $2.38 | $16.64 | — | — |
| bash | opus48-1m-ultracode | 2 | 19.7min | 18.2min | 1.0 | 64 | $5.67 | $11.33 | — | — |
| bash | opus48-1m-xhigh | 7 | 20.3min | 17.0min | 1.3 | 60 | $5.74 | $40.21 | — | — |
| default | opus48-1m-high | 7 | 9.4min | 7.9min | 0.3 | 42 | $2.74 | $19.15 | — | — |
| default | opus48-1m-medium | 7 | 7.5min | 7.5min | 0.1 | 32 | $1.89 | $13.21 | — | — |
| default | opus48-1m-ultracode | 3 | 16.2min | 13.7min | 0.0 | 54 | $4.65 | $13.95 | — | — |
| default | opus48-1m-xhigh | 7 | 15.3min | 12.4min | 0.1 | 48 | $4.48 | $31.34 | — | — |
| powershell | opus48-1m-high | 7 | 13.8min | 10.3min | 0.9 | 49 | $3.24 | $22.70 | — | — |
| powershell | opus48-1m-medium | 7 | 7.4min | 7.4min | 0.0 | 27 | $1.81 | $12.64 | — | — |
| powershell | opus48-1m-ultracode | 3 | 19.1min | 15.1min | 0.7 | 47 | $6.76 | $20.28 | — | — |
| powershell | opus48-1m-xhigh* | 6 | 21.9min | 18.3min | 0.3 | 64 | $6.08 | $36.46 | — | — |
| powershell-tool | opus48-1m-high | 7 | 12.4min | 11.1min | 0.1 | 35 | $2.89 | $20.22 | — | — |
| powershell-tool | opus48-1m-medium | 7 | 10.1min | 10.1min | 0.9 | 40 | $2.57 | $18.00 | — | — |
| powershell-tool | opus48-1m-ultracode | 2 | 23.7min | 20.6min | 0.5 | 54 | $6.18 | $12.37 | — | — |
| powershell-tool | opus48-1m-xhigh* | 4 | 24.6min | 16.8min | 0.8 | 64 | $6.51 | $26.06 | — | — |
| typescript-bun | opus48-1m-high | 7 | 12.2min | 8.1min | 0.4 | 56 | $3.68 | $25.77 | — | — |
| typescript-bun | opus48-1m-medium | 7 | 11.7min | 11.7min | 0.6 | 49 | $2.73 | $19.09 | — | — |
| typescript-bun | opus48-1m-ultracode | 2 | 26.0min | 20.5min | 2.5 | 83 | $8.85 | $17.71 | — | — |
| typescript-bun | opus48-1m-xhigh | 7 | 20.4min | 15.6min | 0.9 | 60 | $5.76 | $40.33 | — | — |

</details>

<details>
<summary>Sorted by deliverable-quality score (best first)</summary>

| Language | Model | Runs | Avg Duration | Avg Duration Net of Traps | Avg Errors | Avg Turns | Avg Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |
|----------|-------|------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|
| bash | opus48-1m-high | 7 | 10.5min | 7.9min | 0.7 | 39 | $2.80 | $19.59 | — | — |
| bash | opus48-1m-medium | 7 | 9.2min | 9.2min | 1.1 | 34 | $2.38 | $16.64 | — | — |
| bash | opus48-1m-ultracode | 2 | 19.7min | 18.2min | 1.0 | 64 | $5.67 | $11.33 | — | — |
| bash | opus48-1m-xhigh | 7 | 20.3min | 17.0min | 1.3 | 60 | $5.74 | $40.21 | — | — |
| default | opus48-1m-high | 7 | 9.4min | 7.9min | 0.3 | 42 | $2.74 | $19.15 | — | — |
| default | opus48-1m-medium | 7 | 7.5min | 7.5min | 0.1 | 32 | $1.89 | $13.21 | — | — |
| default | opus48-1m-ultracode | 3 | 16.2min | 13.7min | 0.0 | 54 | $4.65 | $13.95 | — | — |
| default | opus48-1m-xhigh | 7 | 15.3min | 12.4min | 0.1 | 48 | $4.48 | $31.34 | — | — |
| powershell | opus48-1m-high | 7 | 13.8min | 10.3min | 0.9 | 49 | $3.24 | $22.70 | — | — |
| powershell | opus48-1m-medium | 7 | 7.4min | 7.4min | 0.0 | 27 | $1.81 | $12.64 | — | — |
| powershell | opus48-1m-ultracode | 3 | 19.1min | 15.1min | 0.7 | 47 | $6.76 | $20.28 | — | — |
| powershell | opus48-1m-xhigh* | 6 | 21.9min | 18.3min | 0.3 | 64 | $6.08 | $36.46 | — | — |
| powershell-tool | opus48-1m-high | 7 | 12.4min | 11.1min | 0.1 | 35 | $2.89 | $20.22 | — | — |
| powershell-tool | opus48-1m-medium | 7 | 10.1min | 10.1min | 0.9 | 40 | $2.57 | $18.00 | — | — |
| powershell-tool | opus48-1m-ultracode | 2 | 23.7min | 20.6min | 0.5 | 54 | $6.18 | $12.37 | — | — |
| powershell-tool | opus48-1m-xhigh* | 4 | 24.6min | 16.8min | 0.8 | 64 | $6.51 | $26.06 | — | — |
| typescript-bun | opus48-1m-high | 7 | 12.2min | 8.1min | 0.4 | 56 | $3.68 | $25.77 | — | — |
| typescript-bun | opus48-1m-medium | 7 | 11.7min | 11.7min | 0.6 | 49 | $2.73 | $19.09 | — | — |
| typescript-bun | opus48-1m-ultracode | 2 | 26.0min | 20.5min | 2.5 | 83 | $8.85 | $17.71 | — | — |
| typescript-bun | opus48-1m-xhigh | 7 | 20.4min | 15.6min | 0.9 | 60 | $5.76 | $40.33 | — | — |

</details>

## Savings Analysis

### Hook Savings by Language/Model/Effort

Each hook-caught error avoids one test run that would otherwise have been needed to discover it.
Every hook fire (hit or miss) costs execution time for the syntax/type checker.

*`% of Test Time Saved` = `net / (net + test_time) × 100` — the share of total (would-have-been + actually-spent) test time that hooks eliminated. Bounded in (-∞, 100%) without an artificial cap; near 100% means hooks substituted for almost all of the hypothetical test work.*

| Language | Model | Fires | Caught | Rate | Gross Saved | % of Time | Overhead | % of Time | Net Saved | % of Time | Test Run Time | % of Test Time Saved |
|------|-------|-------|--------|------|------------|-----------|----------|-----------|-----------|-----------|---------------|----------------------|
| bash | opus48-1m-high-cli2.1.195 | 102 | 6 | 5.9% | 1.2min | 0.1% | 0.1min | 0.0% | 1.1min | 0.1% | 3.5min | 24.5% |
| bash | opus48-1m-medium-cli2.1.193 | 51 | 1 | 2.0% | 0.2min | 0.0% | 0.0min | 0.0% | 0.2min | 0.0% | 0.7min | 20.5% |
| bash | opus48-1m-medium-cli2.1.195 | 32 | 1 | 3.1% | 0.2min | 0.0% | 0.0min | 0.0% | 0.2min | 0.0% | 4.4min | 3.5% |
| bash | opus48-1m-ultracode-cli2.1.195 | 54 | 0 | 0.0% | 0.0min | 0.0% | 0.0min | 0.0% | -0.0min | -0.0% | 2.2min | -1.4% |
| bash | opus48-1m-xhigh-cli2.1.195 | 162 | 11 | 6.8% | 2.2min | 0.1% | 0.1min | 0.0% | 2.1min | 0.1% | 7.1min | 22.6% |
| default | opus48-1m-high-cli2.1.195 | 147 | 1 | 0.7% | 0.1min | 0.0% | 0.1min | 0.0% | -0.0min | -0.0% | 4.8min | -0.0% |
| default | opus48-1m-medium-cli2.1.193 | 68 | 0 | 0.0% | 0.0min | 0.0% | 0.2min | 0.0% | -0.2min | -0.0% | 4.0min | -3.9% |
| default | opus48-1m-medium-cli2.1.195 | 34 | 0 | 0.0% | 0.0min | 0.0% | 0.1min | 0.0% | -0.1min | -0.0% | 2.9min | -5.0% |
| default | opus48-1m-ultracode-cli2.1.195 | 89 | 0 | 0.0% | 0.0min | 0.0% | 0.2min | 0.0% | -0.2min | -0.0% | 3.1min | -7.8% |
| default | opus48-1m-xhigh-cli2.1.195 | 159 | 0 | 0.0% | 0.0min | 0.0% | 0.1min | 0.0% | -0.1min | -0.0% | 4.1min | -2.2% |
| powershell | opus48-1m-high-cli2.1.195 | 157 | 0 | 0.0% | 0.0min | 0.0% | 2.0min | 0.1% | -2.0min | -0.1% | 17.3min | -13.0% |
| powershell | opus48-1m-medium-cli2.1.193 | 70 | 0 | 0.0% | 0.0min | 0.0% | 0.7min | 0.0% | -0.7min | -0.0% | 4.3min | -19.8% |
| powershell | opus48-1m-medium-cli2.1.195 | 18 | 0 | 0.0% | 0.0min | 0.0% | 0.1min | 0.0% | -0.1min | -0.0% | 1.5min | -10.4% |
| powershell | opus48-1m-ultracode-cli2.1.195 | 60 | 0 | 0.0% | 0.0min | 0.0% | 0.6min | 0.0% | -0.6min | -0.0% | 2.4min | -36.0% |
| powershell | opus48-1m-xhigh-cli2.1.195 | 204 | 0 | 0.0% | 0.0min | 0.0% | 3.1min | 0.2% | -3.1min | -0.2% | 12.9min | -32.0% |
| powershell-tool | opus48-1m-high-cli2.1.195 | 116 | 0 | 0.0% | 0.0min | 0.0% | 1.3min | 0.1% | -1.3min | -0.1% | 13.7min | -10.4% |
| powershell-tool | opus48-1m-medium-cli2.1.193 | 62 | 0 | 0.0% | 0.0min | 0.0% | 0.3min | 0.0% | -0.3min | -0.0% | 3.6min | -8.2% |
| powershell-tool | opus48-1m-medium-cli2.1.195 | 55 | 0 | 0.0% | 0.0min | 0.0% | 0.5min | 0.0% | -0.5min | -0.0% | 4.0min | -14.3% |
| powershell-tool | opus48-1m-ultracode-cli2.1.195 | 54 | 0 | 0.0% | 0.0min | 0.0% | 0.7min | 0.0% | -0.7min | -0.0% | 2.6min | -39.5% |
| powershell-tool | opus48-1m-xhigh-cli2.1.195 | 198 | 2 | 1.0% | 1.2min | 0.1% | 3.6min | 0.2% | -2.4min | -0.1% | 13.3min | -22.0% |
| typescript-bun | opus48-1m-high-cli2.1.195 | 189 | 82 | 43.4% | 10.9min | 0.6% | 3.2min | 0.2% | 7.7min | 0.5% | 4.3min | 64.5% |
| typescript-bun | opus48-1m-medium-cli2.1.193 | 95 | 40 | 42.1% | 5.3min | 0.3% | 1.4min | 0.1% | 3.9min | 0.2% | 4.0min | 49.5% |
| typescript-bun | opus48-1m-medium-cli2.1.195 | 79 | 39 | 49.4% | 5.2min | 0.3% | 1.4min | 0.1% | 3.8min | 0.2% | 2.1min | 64.3% |
| typescript-bun | opus48-1m-ultracode-cli2.1.195 | 71 | 14 | 19.7% | 1.9min | 0.1% | 1.4min | 0.1% | 0.4min | 0.0% | 0.3min | 63.6% |
| typescript-bun | opus48-1m-xhigh-cli2.1.195 | 190 | 106 | 55.8% | 14.1min | 0.8% | 1.2min | 0.1% | 13.0min | 0.8% | 6.2min | 67.8% |


<details>
<summary>Sorted by net saved (most first)</summary>

| Language | Model | Fires | Caught | Rate | Gross Saved | % of Time | Overhead | % of Time | Net Saved | % of Time | Test Run Time | % of Test Time Saved |
|------|-------|-------|--------|------|------------|-----------|----------|-----------|-----------|-----------|---------------|----------------------|
| typescript-bun | opus48-1m-xhigh-cli2.1.195 | 190 | 106 | 55.8% | 14.1min | 0.8% | 1.2min | 0.1% | 13.0min | 0.8% | 6.2min | 67.8% |
| typescript-bun | opus48-1m-high-cli2.1.195 | 189 | 82 | 43.4% | 10.9min | 0.6% | 3.2min | 0.2% | 7.7min | 0.5% | 4.3min | 64.5% |
| typescript-bun | opus48-1m-medium-cli2.1.193 | 95 | 40 | 42.1% | 5.3min | 0.3% | 1.4min | 0.1% | 3.9min | 0.2% | 4.0min | 49.5% |
| typescript-bun | opus48-1m-medium-cli2.1.195 | 79 | 39 | 49.4% | 5.2min | 0.3% | 1.4min | 0.1% | 3.8min | 0.2% | 2.1min | 64.3% |
| bash | opus48-1m-xhigh-cli2.1.195 | 162 | 11 | 6.8% | 2.2min | 0.1% | 0.1min | 0.0% | 2.1min | 0.1% | 7.1min | 22.6% |
| bash | opus48-1m-high-cli2.1.195 | 102 | 6 | 5.9% | 1.2min | 0.1% | 0.1min | 0.0% | 1.1min | 0.1% | 3.5min | 24.5% |
| typescript-bun | opus48-1m-ultracode-cli2.1.195 | 71 | 14 | 19.7% | 1.9min | 0.1% | 1.4min | 0.1% | 0.4min | 0.0% | 0.3min | 63.6% |
| bash | opus48-1m-medium-cli2.1.193 | 51 | 1 | 2.0% | 0.2min | 0.0% | 0.0min | 0.0% | 0.2min | 0.0% | 0.7min | 20.5% |
| bash | opus48-1m-medium-cli2.1.195 | 32 | 1 | 3.1% | 0.2min | 0.0% | 0.0min | 0.0% | 0.2min | 0.0% | 4.4min | 3.5% |
| default | opus48-1m-high-cli2.1.195 | 147 | 1 | 0.7% | 0.1min | 0.0% | 0.1min | 0.0% | -0.0min | -0.0% | 4.8min | -0.0% |
| bash | opus48-1m-ultracode-cli2.1.195 | 54 | 0 | 0.0% | 0.0min | 0.0% | 0.0min | 0.0% | -0.0min | -0.0% | 2.2min | -1.4% |
| default | opus48-1m-xhigh-cli2.1.195 | 159 | 0 | 0.0% | 0.0min | 0.0% | 0.1min | 0.0% | -0.1min | -0.0% | 4.1min | -2.2% |
| default | opus48-1m-medium-cli2.1.195 | 34 | 0 | 0.0% | 0.0min | 0.0% | 0.1min | 0.0% | -0.1min | -0.0% | 2.9min | -5.0% |
| powershell | opus48-1m-medium-cli2.1.195 | 18 | 0 | 0.0% | 0.0min | 0.0% | 0.1min | 0.0% | -0.1min | -0.0% | 1.5min | -10.4% |
| default | opus48-1m-medium-cli2.1.193 | 68 | 0 | 0.0% | 0.0min | 0.0% | 0.2min | 0.0% | -0.2min | -0.0% | 4.0min | -3.9% |
| default | opus48-1m-ultracode-cli2.1.195 | 89 | 0 | 0.0% | 0.0min | 0.0% | 0.2min | 0.0% | -0.2min | -0.0% | 3.1min | -7.8% |
| powershell-tool | opus48-1m-medium-cli2.1.193 | 62 | 0 | 0.0% | 0.0min | 0.0% | 0.3min | 0.0% | -0.3min | -0.0% | 3.6min | -8.2% |
| powershell-tool | opus48-1m-medium-cli2.1.195 | 55 | 0 | 0.0% | 0.0min | 0.0% | 0.5min | 0.0% | -0.5min | -0.0% | 4.0min | -14.3% |
| powershell | opus48-1m-ultracode-cli2.1.195 | 60 | 0 | 0.0% | 0.0min | 0.0% | 0.6min | 0.0% | -0.6min | -0.0% | 2.4min | -36.0% |
| powershell | opus48-1m-medium-cli2.1.193 | 70 | 0 | 0.0% | 0.0min | 0.0% | 0.7min | 0.0% | -0.7min | -0.0% | 4.3min | -19.8% |
| powershell-tool | opus48-1m-ultracode-cli2.1.195 | 54 | 0 | 0.0% | 0.0min | 0.0% | 0.7min | 0.0% | -0.7min | -0.0% | 2.6min | -39.5% |
| powershell-tool | opus48-1m-high-cli2.1.195 | 116 | 0 | 0.0% | 0.0min | 0.0% | 1.3min | 0.1% | -1.3min | -0.1% | 13.7min | -10.4% |
| powershell | opus48-1m-high-cli2.1.195 | 157 | 0 | 0.0% | 0.0min | 0.0% | 2.0min | 0.1% | -2.0min | -0.1% | 17.3min | -13.0% |
| powershell-tool | opus48-1m-xhigh-cli2.1.195 | 198 | 2 | 1.0% | 1.2min | 0.1% | 3.6min | 0.2% | -2.4min | -0.1% | 13.3min | -22.0% |
| powershell | opus48-1m-xhigh-cli2.1.195 | 204 | 0 | 0.0% | 0.0min | 0.0% | 3.1min | 0.2% | -3.1min | -0.2% | 12.9min | -32.0% |

</details>

<details>
<summary>Sorted by net % of test time saved (most first)</summary>

| Language | Model | Fires | Caught | Rate | Gross Saved | % of Time | Overhead | % of Time | Net Saved | % of Time | Test Run Time | % of Test Time Saved |
|------|-------|-------|--------|------|------------|-----------|----------|-----------|-----------|-----------|---------------|----------------------|
| typescript-bun | opus48-1m-xhigh-cli2.1.195 | 190 | 106 | 55.8% | 14.1min | 0.8% | 1.2min | 0.1% | 13.0min | 0.8% | 6.2min | 67.8% |
| typescript-bun | opus48-1m-high-cli2.1.195 | 189 | 82 | 43.4% | 10.9min | 0.6% | 3.2min | 0.2% | 7.7min | 0.5% | 4.3min | 64.5% |
| typescript-bun | opus48-1m-medium-cli2.1.195 | 79 | 39 | 49.4% | 5.2min | 0.3% | 1.4min | 0.1% | 3.8min | 0.2% | 2.1min | 64.3% |
| typescript-bun | opus48-1m-ultracode-cli2.1.195 | 71 | 14 | 19.7% | 1.9min | 0.1% | 1.4min | 0.1% | 0.4min | 0.0% | 0.3min | 63.6% |
| typescript-bun | opus48-1m-medium-cli2.1.193 | 95 | 40 | 42.1% | 5.3min | 0.3% | 1.4min | 0.1% | 3.9min | 0.2% | 4.0min | 49.5% |
| bash | opus48-1m-high-cli2.1.195 | 102 | 6 | 5.9% | 1.2min | 0.1% | 0.1min | 0.0% | 1.1min | 0.1% | 3.5min | 24.5% |
| bash | opus48-1m-xhigh-cli2.1.195 | 162 | 11 | 6.8% | 2.2min | 0.1% | 0.1min | 0.0% | 2.1min | 0.1% | 7.1min | 22.6% |
| bash | opus48-1m-medium-cli2.1.193 | 51 | 1 | 2.0% | 0.2min | 0.0% | 0.0min | 0.0% | 0.2min | 0.0% | 0.7min | 20.5% |
| bash | opus48-1m-medium-cli2.1.195 | 32 | 1 | 3.1% | 0.2min | 0.0% | 0.0min | 0.0% | 0.2min | 0.0% | 4.4min | 3.5% |
| default | opus48-1m-high-cli2.1.195 | 147 | 1 | 0.7% | 0.1min | 0.0% | 0.1min | 0.0% | -0.0min | -0.0% | 4.8min | -0.0% |
| bash | opus48-1m-ultracode-cli2.1.195 | 54 | 0 | 0.0% | 0.0min | 0.0% | 0.0min | 0.0% | -0.0min | -0.0% | 2.2min | -1.4% |
| default | opus48-1m-xhigh-cli2.1.195 | 159 | 0 | 0.0% | 0.0min | 0.0% | 0.1min | 0.0% | -0.1min | -0.0% | 4.1min | -2.2% |
| default | opus48-1m-medium-cli2.1.193 | 68 | 0 | 0.0% | 0.0min | 0.0% | 0.2min | 0.0% | -0.2min | -0.0% | 4.0min | -3.9% |
| default | opus48-1m-medium-cli2.1.195 | 34 | 0 | 0.0% | 0.0min | 0.0% | 0.1min | 0.0% | -0.1min | -0.0% | 2.9min | -5.0% |
| default | opus48-1m-ultracode-cli2.1.195 | 89 | 0 | 0.0% | 0.0min | 0.0% | 0.2min | 0.0% | -0.2min | -0.0% | 3.1min | -7.8% |
| powershell-tool | opus48-1m-medium-cli2.1.193 | 62 | 0 | 0.0% | 0.0min | 0.0% | 0.3min | 0.0% | -0.3min | -0.0% | 3.6min | -8.2% |
| powershell-tool | opus48-1m-high-cli2.1.195 | 116 | 0 | 0.0% | 0.0min | 0.0% | 1.3min | 0.1% | -1.3min | -0.1% | 13.7min | -10.4% |
| powershell | opus48-1m-medium-cli2.1.195 | 18 | 0 | 0.0% | 0.0min | 0.0% | 0.1min | 0.0% | -0.1min | -0.0% | 1.5min | -10.4% |
| powershell | opus48-1m-high-cli2.1.195 | 157 | 0 | 0.0% | 0.0min | 0.0% | 2.0min | 0.1% | -2.0min | -0.1% | 17.3min | -13.0% |
| powershell-tool | opus48-1m-medium-cli2.1.195 | 55 | 0 | 0.0% | 0.0min | 0.0% | 0.5min | 0.0% | -0.5min | -0.0% | 4.0min | -14.3% |
| powershell | opus48-1m-medium-cli2.1.193 | 70 | 0 | 0.0% | 0.0min | 0.0% | 0.7min | 0.0% | -0.7min | -0.0% | 4.3min | -19.8% |
| powershell-tool | opus48-1m-xhigh-cli2.1.195 | 198 | 2 | 1.0% | 1.2min | 0.1% | 3.6min | 0.2% | -2.4min | -0.1% | 13.3min | -22.0% |
| powershell | opus48-1m-xhigh-cli2.1.195 | 204 | 0 | 0.0% | 0.0min | 0.0% | 3.1min | 0.2% | -3.1min | -0.2% | 12.9min | -32.0% |
| powershell | opus48-1m-ultracode-cli2.1.195 | 60 | 0 | 0.0% | 0.0min | 0.0% | 0.6min | 0.0% | -0.6min | -0.0% | 2.4min | -36.0% |
| powershell-tool | opus48-1m-ultracode-cli2.1.195 | 54 | 0 | 0.0% | 0.0min | 0.0% | 0.7min | 0.0% | -0.7min | -0.0% | 2.6min | -39.5% |

</details>

<details>
<summary>Sorted by catch rate (highest first)</summary>

| Language | Model | Fires | Caught | Rate | Gross Saved | % of Time | Overhead | % of Time | Net Saved | % of Time | Test Run Time | % of Test Time Saved |
|------|-------|-------|--------|------|------------|-----------|----------|-----------|-----------|-----------|---------------|----------------------|
| typescript-bun | opus48-1m-xhigh-cli2.1.195 | 190 | 106 | 55.8% | 14.1min | 0.8% | 1.2min | 0.1% | 13.0min | 0.8% | 6.2min | 67.8% |
| typescript-bun | opus48-1m-medium-cli2.1.195 | 79 | 39 | 49.4% | 5.2min | 0.3% | 1.4min | 0.1% | 3.8min | 0.2% | 2.1min | 64.3% |
| typescript-bun | opus48-1m-high-cli2.1.195 | 189 | 82 | 43.4% | 10.9min | 0.6% | 3.2min | 0.2% | 7.7min | 0.5% | 4.3min | 64.5% |
| typescript-bun | opus48-1m-medium-cli2.1.193 | 95 | 40 | 42.1% | 5.3min | 0.3% | 1.4min | 0.1% | 3.9min | 0.2% | 4.0min | 49.5% |
| typescript-bun | opus48-1m-ultracode-cli2.1.195 | 71 | 14 | 19.7% | 1.9min | 0.1% | 1.4min | 0.1% | 0.4min | 0.0% | 0.3min | 63.6% |
| bash | opus48-1m-xhigh-cli2.1.195 | 162 | 11 | 6.8% | 2.2min | 0.1% | 0.1min | 0.0% | 2.1min | 0.1% | 7.1min | 22.6% |
| bash | opus48-1m-high-cli2.1.195 | 102 | 6 | 5.9% | 1.2min | 0.1% | 0.1min | 0.0% | 1.1min | 0.1% | 3.5min | 24.5% |
| bash | opus48-1m-medium-cli2.1.195 | 32 | 1 | 3.1% | 0.2min | 0.0% | 0.0min | 0.0% | 0.2min | 0.0% | 4.4min | 3.5% |
| bash | opus48-1m-medium-cli2.1.193 | 51 | 1 | 2.0% | 0.2min | 0.0% | 0.0min | 0.0% | 0.2min | 0.0% | 0.7min | 20.5% |
| powershell-tool | opus48-1m-xhigh-cli2.1.195 | 198 | 2 | 1.0% | 1.2min | 0.1% | 3.6min | 0.2% | -2.4min | -0.1% | 13.3min | -22.0% |
| default | opus48-1m-high-cli2.1.195 | 147 | 1 | 0.7% | 0.1min | 0.0% | 0.1min | 0.0% | -0.0min | -0.0% | 4.8min | -0.0% |
| bash | opus48-1m-ultracode-cli2.1.195 | 54 | 0 | 0.0% | 0.0min | 0.0% | 0.0min | 0.0% | -0.0min | -0.0% | 2.2min | -1.4% |
| default | opus48-1m-medium-cli2.1.193 | 68 | 0 | 0.0% | 0.0min | 0.0% | 0.2min | 0.0% | -0.2min | -0.0% | 4.0min | -3.9% |
| default | opus48-1m-medium-cli2.1.195 | 34 | 0 | 0.0% | 0.0min | 0.0% | 0.1min | 0.0% | -0.1min | -0.0% | 2.9min | -5.0% |
| default | opus48-1m-ultracode-cli2.1.195 | 89 | 0 | 0.0% | 0.0min | 0.0% | 0.2min | 0.0% | -0.2min | -0.0% | 3.1min | -7.8% |
| default | opus48-1m-xhigh-cli2.1.195 | 159 | 0 | 0.0% | 0.0min | 0.0% | 0.1min | 0.0% | -0.1min | -0.0% | 4.1min | -2.2% |
| powershell | opus48-1m-high-cli2.1.195 | 157 | 0 | 0.0% | 0.0min | 0.0% | 2.0min | 0.1% | -2.0min | -0.1% | 17.3min | -13.0% |
| powershell | opus48-1m-medium-cli2.1.193 | 70 | 0 | 0.0% | 0.0min | 0.0% | 0.7min | 0.0% | -0.7min | -0.0% | 4.3min | -19.8% |
| powershell | opus48-1m-medium-cli2.1.195 | 18 | 0 | 0.0% | 0.0min | 0.0% | 0.1min | 0.0% | -0.1min | -0.0% | 1.5min | -10.4% |
| powershell | opus48-1m-ultracode-cli2.1.195 | 60 | 0 | 0.0% | 0.0min | 0.0% | 0.6min | 0.0% | -0.6min | -0.0% | 2.4min | -36.0% |
| powershell | opus48-1m-xhigh-cli2.1.195 | 204 | 0 | 0.0% | 0.0min | 0.0% | 3.1min | 0.2% | -3.1min | -0.2% | 12.9min | -32.0% |
| powershell-tool | opus48-1m-high-cli2.1.195 | 116 | 0 | 0.0% | 0.0min | 0.0% | 1.3min | 0.1% | -1.3min | -0.1% | 13.7min | -10.4% |
| powershell-tool | opus48-1m-medium-cli2.1.193 | 62 | 0 | 0.0% | 0.0min | 0.0% | 0.3min | 0.0% | -0.3min | -0.0% | 3.6min | -8.2% |
| powershell-tool | opus48-1m-medium-cli2.1.195 | 55 | 0 | 0.0% | 0.0min | 0.0% | 0.5min | 0.0% | -0.5min | -0.0% | 4.0min | -14.3% |
| powershell-tool | opus48-1m-ultracode-cli2.1.195 | 54 | 0 | 0.0% | 0.0min | 0.0% | 0.7min | 0.0% | -0.7min | -0.0% | 2.6min | -39.5% |

</details>

### Trap Analysis by Language/Model/Effort/Category

| Trap | Language | Model | Fell In | Time Lost | % of Time | $ Lost | % of $ |
|------|------|-------|---------|-----------|-----------|--------|--------|
| repeated-test-reruns | bash | opus48-1m-high-cli2.1.195 | 5 | 11.7min | 0.7% | $3.16 | 0.72% |
| repeated-test-reruns | bash | opus48-1m-medium-cli2.1.193 | 3 | 4.0min | 0.2% | $1.08 | 0.25% |
| repeated-test-reruns | bash | opus48-1m-medium-cli2.1.195 | 2 | 4.7min | 0.3% | $1.21 | 0.28% |
| repeated-test-reruns | bash | opus48-1m-ultracode-cli2.1.195 | 1 | 3.0min | 0.2% | $0.88 | 0.20% |
| repeated-test-reruns | bash | opus48-1m-xhigh-cli2.1.195 | 5 | 13.7min | 0.8% | $4.08 | 0.93% |
| repeated-test-reruns | default | opus48-1m-high-cli2.1.195 | 5 | 10.0min | 0.6% | $2.94 | 0.67% |
| repeated-test-reruns | default | opus48-1m-medium-cli2.1.193 | 4 | 5.7min | 0.3% | $1.34 | 0.31% |
| repeated-test-reruns | default | opus48-1m-medium-cli2.1.195 | 2 | 3.3min | 0.2% | $0.82 | 0.19% |
| repeated-test-reruns | default | opus48-1m-ultracode-cli2.1.195 | 3 | 7.3min | 0.4% | $2.02 | 0.46% |
| repeated-test-reruns | default | opus48-1m-xhigh-cli2.1.195 | 8 | 18.3min | 1.1% | $5.59 | 1.28% |
| repeated-test-reruns | powershell | opus48-1m-high-cli2.1.195 | 8 | 22.3min | 1.3% | $5.14 | 1.18% |
| repeated-test-reruns | powershell | opus48-1m-medium-cli2.1.193 | 2 | 2.7min | 0.2% | $0.66 | 0.15% |
| repeated-test-reruns | powershell | opus48-1m-ultracode-cli2.1.195 | 2 | 7.0min | 0.4% | $2.53 | 0.58% |
| repeated-test-reruns | powershell | opus48-1m-xhigh-cli2.1.195 | 6 | 16.7min | 1.0% | $3.23 | 0.74% |
| repeated-test-reruns | powershell-tool | opus48-1m-high-cli2.1.195 | 6 | 9.0min | 0.5% | $2.12 | 0.49% |
| repeated-test-reruns | powershell-tool | opus48-1m-medium-cli2.1.193 | 2 | 3.3min | 0.2% | $0.78 | 0.18% |
| repeated-test-reruns | powershell-tool | opus48-1m-medium-cli2.1.195 | 3 | 3.3min | 0.2% | $0.85 | 0.20% |
| repeated-test-reruns | powershell-tool | opus48-1m-ultracode-cli2.1.195 | 3 | 6.3min | 0.4% | $1.64 | 0.37% |
| repeated-test-reruns | powershell-tool | opus48-1m-xhigh-cli2.1.195 | 7 | 28.0min | 1.6% | $4.15 | 0.95% |
| repeated-test-reruns | typescript-bun | opus48-1m-high-cli2.1.195 | 5 | 10.7min | 0.6% | $3.53 | 0.81% |
| repeated-test-reruns | typescript-bun | opus48-1m-medium-cli2.1.193 | 4 | 8.7min | 0.5% | $2.26 | 0.52% |
| repeated-test-reruns | typescript-bun | opus48-1m-medium-cli2.1.195 | 4 | 7.3min | 0.4% | $1.71 | 0.39% |
| repeated-test-reruns | typescript-bun | opus48-1m-ultracode-cli2.1.195 | 2 | 7.7min | 0.4% | $2.67 | 0.61% |
| repeated-test-reruns | typescript-bun | opus48-1m-xhigh-cli2.1.195 | 5 | 10.3min | 0.6% | $2.91 | 0.67% |
| ts-type-error-fix-cycles | typescript-bun | opus48-1m-high-cli2.1.195 | 6 | 16.4min | 1.0% | $5.11 | 1.17% |
| ts-type-error-fix-cycles | typescript-bun | opus48-1m-medium-cli2.1.193 | 3 | 8.0min | 0.5% | $2.17 | 0.50% |
| ts-type-error-fix-cycles | typescript-bun | opus48-1m-medium-cli2.1.195 | 2 | 7.8min | 0.5% | $1.74 | 0.40% |
| ts-type-error-fix-cycles | typescript-bun | opus48-1m-ultracode-cli2.1.195 | 1 | 2.8min | 0.2% | $0.76 | 0.17% |
| ts-type-error-fix-cycles | typescript-bun | opus48-1m-xhigh-cli2.1.195 | 7 | 21.2min | 1.2% | $6.01 | 1.38% |
| fixture-rework | bash | opus48-1m-high-cli2.1.195 | 6 | 5.0min | 0.3% | $1.35 | 0.31% |
| fixture-rework | bash | opus48-1m-medium-cli2.1.193 | 2 | 1.5min | 0.1% | $0.41 | 0.09% |
| fixture-rework | bash | opus48-1m-medium-cli2.1.195 | 1 | 3.0min | 0.2% | $0.72 | 0.16% |
| fixture-rework | bash | opus48-1m-xhigh-cli2.1.195 | 5 | 6.8min | 0.4% | $1.83 | 0.42% |
| fixture-rework | default | opus48-1m-medium-cli2.1.193 | 1 | 0.8min | 0.0% | $0.22 | 0.05% |
| fixture-rework | default | opus48-1m-xhigh-cli2.1.195 | 3 | 1.5min | 0.1% | $0.42 | 0.10% |
| fixture-rework | powershell | opus48-1m-high-cli2.1.195 | 4 | 2.5min | 0.1% | $0.62 | 0.14% |
| fixture-rework | powershell | opus48-1m-medium-cli2.1.193 | 1 | 0.5min | 0.0% | $0.12 | 0.03% |
| fixture-rework | powershell | opus48-1m-xhigh-cli2.1.195 | 4 | 3.8min | 0.2% | $0.53 | 0.12% |
| fixture-rework | powershell-tool | opus48-1m-high-cli2.1.195 | 1 | 0.5min | 0.0% | $0.12 | 0.03% |
| fixture-rework | powershell-tool | opus48-1m-medium-cli2.1.193 | 1 | 1.0min | 0.1% | $0.27 | 0.06% |
| fixture-rework | powershell-tool | opus48-1m-xhigh-cli2.1.195 | 2 | 1.5min | 0.1% | $0.14 | 0.03% |
| fixture-rework | typescript-bun | opus48-1m-high-cli2.1.195 | 1 | 1.2min | 0.1% | $0.37 | 0.08% |
| fixture-rework | typescript-bun | opus48-1m-medium-cli2.1.195 | 1 | 0.5min | 0.0% | $0.10 | 0.02% |
| fixture-rework | typescript-bun | opus48-1m-ultracode-cli2.1.195 | 1 | 0.5min | 0.0% | $0.19 | 0.04% |
| fixture-rework | typescript-bun | opus48-1m-xhigh-cli2.1.195 | 4 | 2.0min | 0.1% | $0.55 | 0.13% |
| docker-pwsh-install | powershell | opus48-1m-ultracode-cli2.1.195 | 2 | 3.0min | 0.2% | $0.83 | 0.19% |
| docker-pwsh-install | powershell | opus48-1m-xhigh-cli2.1.195 | 1 | 1.5min | 0.1% | $0.44 | 0.10% |
| docker-pwsh-install | powershell-tool | opus48-1m-xhigh-cli2.1.195 | 1 | 1.5min | 0.1% | $0.39 | 0.09% |
| bats-setup-issues | bash | opus48-1m-high-cli2.1.195 | 1 | 1.2min | 0.1% | $0.33 | 0.08% |
| bats-setup-issues | bash | opus48-1m-xhigh-cli2.1.195 | 2 | 1.8min | 0.1% | $0.51 | 0.12% |
| mid-run-module-restructure | powershell | opus48-1m-ultracode-cli2.1.195 | 1 | 2.0min | 0.1% | $0.84 | 0.19% |
| actionlint-fix-cycles | powershell-tool | opus48-1m-medium-cli2.1.193 | 1 | 1.0min | 0.1% | $0.27 | 0.06% |
| actionlint-fix-cycles | typescript-bun | opus48-1m-medium-cli2.1.195 | 1 | 0.7min | 0.0% | $0.13 | 0.03% |
| act-fixture-paths | bash | opus48-1m-xhigh-cli2.1.195 | 1 | 1.0min | 0.1% | $0.25 | 0.06% |


<details>
<summary>Sorted by time lost (least first)</summary>

| Trap | Language | Model | Fell In | Time Lost | % of Time | $ Lost | % of $ |
|------|------|-------|---------|-----------|-----------|--------|--------|
| fixture-rework | powershell | opus48-1m-medium-cli2.1.193 | 1 | 0.5min | 0.0% | $0.12 | 0.03% |
| fixture-rework | powershell-tool | opus48-1m-high-cli2.1.195 | 1 | 0.5min | 0.0% | $0.12 | 0.03% |
| fixture-rework | typescript-bun | opus48-1m-medium-cli2.1.195 | 1 | 0.5min | 0.0% | $0.10 | 0.02% |
| fixture-rework | typescript-bun | opus48-1m-ultracode-cli2.1.195 | 1 | 0.5min | 0.0% | $0.19 | 0.04% |
| actionlint-fix-cycles | typescript-bun | opus48-1m-medium-cli2.1.195 | 1 | 0.7min | 0.0% | $0.13 | 0.03% |
| fixture-rework | default | opus48-1m-medium-cli2.1.193 | 1 | 0.8min | 0.0% | $0.22 | 0.05% |
| fixture-rework | powershell-tool | opus48-1m-medium-cli2.1.193 | 1 | 1.0min | 0.1% | $0.27 | 0.06% |
| actionlint-fix-cycles | powershell-tool | opus48-1m-medium-cli2.1.193 | 1 | 1.0min | 0.1% | $0.27 | 0.06% |
| act-fixture-paths | bash | opus48-1m-xhigh-cli2.1.195 | 1 | 1.0min | 0.1% | $0.25 | 0.06% |
| fixture-rework | typescript-bun | opus48-1m-high-cli2.1.195 | 1 | 1.2min | 0.1% | $0.37 | 0.08% |
| bats-setup-issues | bash | opus48-1m-high-cli2.1.195 | 1 | 1.2min | 0.1% | $0.33 | 0.08% |
| fixture-rework | bash | opus48-1m-medium-cli2.1.193 | 2 | 1.5min | 0.1% | $0.41 | 0.09% |
| fixture-rework | default | opus48-1m-xhigh-cli2.1.195 | 3 | 1.5min | 0.1% | $0.42 | 0.10% |
| fixture-rework | powershell-tool | opus48-1m-xhigh-cli2.1.195 | 2 | 1.5min | 0.1% | $0.14 | 0.03% |
| docker-pwsh-install | powershell | opus48-1m-xhigh-cli2.1.195 | 1 | 1.5min | 0.1% | $0.44 | 0.10% |
| docker-pwsh-install | powershell-tool | opus48-1m-xhigh-cli2.1.195 | 1 | 1.5min | 0.1% | $0.39 | 0.09% |
| bats-setup-issues | bash | opus48-1m-xhigh-cli2.1.195 | 2 | 1.8min | 0.1% | $0.51 | 0.12% |
| fixture-rework | typescript-bun | opus48-1m-xhigh-cli2.1.195 | 4 | 2.0min | 0.1% | $0.55 | 0.13% |
| mid-run-module-restructure | powershell | opus48-1m-ultracode-cli2.1.195 | 1 | 2.0min | 0.1% | $0.84 | 0.19% |
| fixture-rework | powershell | opus48-1m-high-cli2.1.195 | 4 | 2.5min | 0.1% | $0.62 | 0.14% |
| repeated-test-reruns | powershell | opus48-1m-medium-cli2.1.193 | 2 | 2.7min | 0.2% | $0.66 | 0.15% |
| ts-type-error-fix-cycles | typescript-bun | opus48-1m-ultracode-cli2.1.195 | 1 | 2.8min | 0.2% | $0.76 | 0.17% |
| repeated-test-reruns | bash | opus48-1m-ultracode-cli2.1.195 | 1 | 3.0min | 0.2% | $0.88 | 0.20% |
| fixture-rework | bash | opus48-1m-medium-cli2.1.195 | 1 | 3.0min | 0.2% | $0.72 | 0.16% |
| docker-pwsh-install | powershell | opus48-1m-ultracode-cli2.1.195 | 2 | 3.0min | 0.2% | $0.83 | 0.19% |
| repeated-test-reruns | default | opus48-1m-medium-cli2.1.195 | 2 | 3.3min | 0.2% | $0.82 | 0.19% |
| repeated-test-reruns | powershell-tool | opus48-1m-medium-cli2.1.193 | 2 | 3.3min | 0.2% | $0.78 | 0.18% |
| repeated-test-reruns | powershell-tool | opus48-1m-medium-cli2.1.195 | 3 | 3.3min | 0.2% | $0.85 | 0.20% |
| fixture-rework | powershell | opus48-1m-xhigh-cli2.1.195 | 4 | 3.8min | 0.2% | $0.53 | 0.12% |
| repeated-test-reruns | bash | opus48-1m-medium-cli2.1.193 | 3 | 4.0min | 0.2% | $1.08 | 0.25% |
| repeated-test-reruns | bash | opus48-1m-medium-cli2.1.195 | 2 | 4.7min | 0.3% | $1.21 | 0.28% |
| fixture-rework | bash | opus48-1m-high-cli2.1.195 | 6 | 5.0min | 0.3% | $1.35 | 0.31% |
| repeated-test-reruns | default | opus48-1m-medium-cli2.1.193 | 4 | 5.7min | 0.3% | $1.34 | 0.31% |
| repeated-test-reruns | powershell-tool | opus48-1m-ultracode-cli2.1.195 | 3 | 6.3min | 0.4% | $1.64 | 0.37% |
| fixture-rework | bash | opus48-1m-xhigh-cli2.1.195 | 5 | 6.8min | 0.4% | $1.83 | 0.42% |
| repeated-test-reruns | powershell | opus48-1m-ultracode-cli2.1.195 | 2 | 7.0min | 0.4% | $2.53 | 0.58% |
| repeated-test-reruns | default | opus48-1m-ultracode-cli2.1.195 | 3 | 7.3min | 0.4% | $2.02 | 0.46% |
| repeated-test-reruns | typescript-bun | opus48-1m-medium-cli2.1.195 | 4 | 7.3min | 0.4% | $1.71 | 0.39% |
| repeated-test-reruns | typescript-bun | opus48-1m-ultracode-cli2.1.195 | 2 | 7.7min | 0.4% | $2.67 | 0.61% |
| ts-type-error-fix-cycles | typescript-bun | opus48-1m-medium-cli2.1.195 | 2 | 7.8min | 0.5% | $1.74 | 0.40% |
| ts-type-error-fix-cycles | typescript-bun | opus48-1m-medium-cli2.1.193 | 3 | 8.0min | 0.5% | $2.17 | 0.50% |
| repeated-test-reruns | typescript-bun | opus48-1m-medium-cli2.1.193 | 4 | 8.7min | 0.5% | $2.26 | 0.52% |
| repeated-test-reruns | powershell-tool | opus48-1m-high-cli2.1.195 | 6 | 9.0min | 0.5% | $2.12 | 0.49% |
| repeated-test-reruns | default | opus48-1m-high-cli2.1.195 | 5 | 10.0min | 0.6% | $2.94 | 0.67% |
| repeated-test-reruns | typescript-bun | opus48-1m-xhigh-cli2.1.195 | 5 | 10.3min | 0.6% | $2.91 | 0.67% |
| repeated-test-reruns | typescript-bun | opus48-1m-high-cli2.1.195 | 5 | 10.7min | 0.6% | $3.53 | 0.81% |
| repeated-test-reruns | bash | opus48-1m-high-cli2.1.195 | 5 | 11.7min | 0.7% | $3.16 | 0.72% |
| repeated-test-reruns | bash | opus48-1m-xhigh-cli2.1.195 | 5 | 13.7min | 0.8% | $4.08 | 0.93% |
| ts-type-error-fix-cycles | typescript-bun | opus48-1m-high-cli2.1.195 | 6 | 16.4min | 1.0% | $5.11 | 1.17% |
| repeated-test-reruns | powershell | opus48-1m-xhigh-cli2.1.195 | 6 | 16.7min | 1.0% | $3.23 | 0.74% |
| repeated-test-reruns | default | opus48-1m-xhigh-cli2.1.195 | 8 | 18.3min | 1.1% | $5.59 | 1.28% |
| ts-type-error-fix-cycles | typescript-bun | opus48-1m-xhigh-cli2.1.195 | 7 | 21.2min | 1.2% | $6.01 | 1.38% |
| repeated-test-reruns | powershell | opus48-1m-high-cli2.1.195 | 8 | 22.3min | 1.3% | $5.14 | 1.18% |
| repeated-test-reruns | powershell-tool | opus48-1m-xhigh-cli2.1.195 | 7 | 28.0min | 1.6% | $4.15 | 0.95% |

</details>

<details>
<summary>Sorted by $ lost (least first)</summary>

| Trap | Language | Model | Fell In | Time Lost | % of Time | $ Lost | % of $ |
|------|------|-------|---------|-----------|-----------|--------|--------|
| fixture-rework | typescript-bun | opus48-1m-medium-cli2.1.195 | 1 | 0.5min | 0.0% | $0.10 | 0.02% |
| fixture-rework | powershell | opus48-1m-medium-cli2.1.193 | 1 | 0.5min | 0.0% | $0.12 | 0.03% |
| fixture-rework | powershell-tool | opus48-1m-high-cli2.1.195 | 1 | 0.5min | 0.0% | $0.12 | 0.03% |
| actionlint-fix-cycles | typescript-bun | opus48-1m-medium-cli2.1.195 | 1 | 0.7min | 0.0% | $0.13 | 0.03% |
| fixture-rework | powershell-tool | opus48-1m-xhigh-cli2.1.195 | 2 | 1.5min | 0.1% | $0.14 | 0.03% |
| fixture-rework | typescript-bun | opus48-1m-ultracode-cli2.1.195 | 1 | 0.5min | 0.0% | $0.19 | 0.04% |
| fixture-rework | default | opus48-1m-medium-cli2.1.193 | 1 | 0.8min | 0.0% | $0.22 | 0.05% |
| act-fixture-paths | bash | opus48-1m-xhigh-cli2.1.195 | 1 | 1.0min | 0.1% | $0.25 | 0.06% |
| fixture-rework | powershell-tool | opus48-1m-medium-cli2.1.193 | 1 | 1.0min | 0.1% | $0.27 | 0.06% |
| actionlint-fix-cycles | powershell-tool | opus48-1m-medium-cli2.1.193 | 1 | 1.0min | 0.1% | $0.27 | 0.06% |
| bats-setup-issues | bash | opus48-1m-high-cli2.1.195 | 1 | 1.2min | 0.1% | $0.33 | 0.08% |
| fixture-rework | typescript-bun | opus48-1m-high-cli2.1.195 | 1 | 1.2min | 0.1% | $0.37 | 0.08% |
| docker-pwsh-install | powershell-tool | opus48-1m-xhigh-cli2.1.195 | 1 | 1.5min | 0.1% | $0.39 | 0.09% |
| fixture-rework | bash | opus48-1m-medium-cli2.1.193 | 2 | 1.5min | 0.1% | $0.41 | 0.09% |
| fixture-rework | default | opus48-1m-xhigh-cli2.1.195 | 3 | 1.5min | 0.1% | $0.42 | 0.10% |
| docker-pwsh-install | powershell | opus48-1m-xhigh-cli2.1.195 | 1 | 1.5min | 0.1% | $0.44 | 0.10% |
| bats-setup-issues | bash | opus48-1m-xhigh-cli2.1.195 | 2 | 1.8min | 0.1% | $0.51 | 0.12% |
| fixture-rework | powershell | opus48-1m-xhigh-cli2.1.195 | 4 | 3.8min | 0.2% | $0.53 | 0.12% |
| fixture-rework | typescript-bun | opus48-1m-xhigh-cli2.1.195 | 4 | 2.0min | 0.1% | $0.55 | 0.13% |
| fixture-rework | powershell | opus48-1m-high-cli2.1.195 | 4 | 2.5min | 0.1% | $0.62 | 0.14% |
| repeated-test-reruns | powershell | opus48-1m-medium-cli2.1.193 | 2 | 2.7min | 0.2% | $0.66 | 0.15% |
| fixture-rework | bash | opus48-1m-medium-cli2.1.195 | 1 | 3.0min | 0.2% | $0.72 | 0.16% |
| ts-type-error-fix-cycles | typescript-bun | opus48-1m-ultracode-cli2.1.195 | 1 | 2.8min | 0.2% | $0.76 | 0.17% |
| repeated-test-reruns | powershell-tool | opus48-1m-medium-cli2.1.193 | 2 | 3.3min | 0.2% | $0.78 | 0.18% |
| repeated-test-reruns | default | opus48-1m-medium-cli2.1.195 | 2 | 3.3min | 0.2% | $0.82 | 0.19% |
| docker-pwsh-install | powershell | opus48-1m-ultracode-cli2.1.195 | 2 | 3.0min | 0.2% | $0.83 | 0.19% |
| mid-run-module-restructure | powershell | opus48-1m-ultracode-cli2.1.195 | 1 | 2.0min | 0.1% | $0.84 | 0.19% |
| repeated-test-reruns | powershell-tool | opus48-1m-medium-cli2.1.195 | 3 | 3.3min | 0.2% | $0.85 | 0.20% |
| repeated-test-reruns | bash | opus48-1m-ultracode-cli2.1.195 | 1 | 3.0min | 0.2% | $0.88 | 0.20% |
| repeated-test-reruns | bash | opus48-1m-medium-cli2.1.193 | 3 | 4.0min | 0.2% | $1.08 | 0.25% |
| repeated-test-reruns | bash | opus48-1m-medium-cli2.1.195 | 2 | 4.7min | 0.3% | $1.21 | 0.28% |
| repeated-test-reruns | default | opus48-1m-medium-cli2.1.193 | 4 | 5.7min | 0.3% | $1.34 | 0.31% |
| fixture-rework | bash | opus48-1m-high-cli2.1.195 | 6 | 5.0min | 0.3% | $1.35 | 0.31% |
| repeated-test-reruns | powershell-tool | opus48-1m-ultracode-cli2.1.195 | 3 | 6.3min | 0.4% | $1.64 | 0.37% |
| repeated-test-reruns | typescript-bun | opus48-1m-medium-cli2.1.195 | 4 | 7.3min | 0.4% | $1.71 | 0.39% |
| ts-type-error-fix-cycles | typescript-bun | opus48-1m-medium-cli2.1.195 | 2 | 7.8min | 0.5% | $1.74 | 0.40% |
| fixture-rework | bash | opus48-1m-xhigh-cli2.1.195 | 5 | 6.8min | 0.4% | $1.83 | 0.42% |
| repeated-test-reruns | default | opus48-1m-ultracode-cli2.1.195 | 3 | 7.3min | 0.4% | $2.02 | 0.46% |
| repeated-test-reruns | powershell-tool | opus48-1m-high-cli2.1.195 | 6 | 9.0min | 0.5% | $2.12 | 0.49% |
| ts-type-error-fix-cycles | typescript-bun | opus48-1m-medium-cli2.1.193 | 3 | 8.0min | 0.5% | $2.17 | 0.50% |
| repeated-test-reruns | typescript-bun | opus48-1m-medium-cli2.1.193 | 4 | 8.7min | 0.5% | $2.26 | 0.52% |
| repeated-test-reruns | powershell | opus48-1m-ultracode-cli2.1.195 | 2 | 7.0min | 0.4% | $2.53 | 0.58% |
| repeated-test-reruns | typescript-bun | opus48-1m-ultracode-cli2.1.195 | 2 | 7.7min | 0.4% | $2.67 | 0.61% |
| repeated-test-reruns | typescript-bun | opus48-1m-xhigh-cli2.1.195 | 5 | 10.3min | 0.6% | $2.91 | 0.67% |
| repeated-test-reruns | default | opus48-1m-high-cli2.1.195 | 5 | 10.0min | 0.6% | $2.94 | 0.67% |
| repeated-test-reruns | bash | opus48-1m-high-cli2.1.195 | 5 | 11.7min | 0.7% | $3.16 | 0.72% |
| repeated-test-reruns | powershell | opus48-1m-xhigh-cli2.1.195 | 6 | 16.7min | 1.0% | $3.23 | 0.74% |
| repeated-test-reruns | typescript-bun | opus48-1m-high-cli2.1.195 | 5 | 10.7min | 0.6% | $3.53 | 0.81% |
| repeated-test-reruns | bash | opus48-1m-xhigh-cli2.1.195 | 5 | 13.7min | 0.8% | $4.08 | 0.93% |
| repeated-test-reruns | powershell-tool | opus48-1m-xhigh-cli2.1.195 | 7 | 28.0min | 1.6% | $4.15 | 0.95% |
| ts-type-error-fix-cycles | typescript-bun | opus48-1m-high-cli2.1.195 | 6 | 16.4min | 1.0% | $5.11 | 1.17% |
| repeated-test-reruns | powershell | opus48-1m-high-cli2.1.195 | 8 | 22.3min | 1.3% | $5.14 | 1.18% |
| repeated-test-reruns | default | opus48-1m-xhigh-cli2.1.195 | 8 | 18.3min | 1.1% | $5.59 | 1.28% |
| ts-type-error-fix-cycles | typescript-bun | opus48-1m-xhigh-cli2.1.195 | 7 | 21.2min | 1.2% | $6.01 | 1.38% |

</details>

<details>
<summary>Sorted by fell-in count (fewest first)</summary>

| Trap | Language | Model | Fell In | Time Lost | % of Time | $ Lost | % of $ |
|------|------|-------|---------|-----------|-----------|--------|--------|
| repeated-test-reruns | bash | opus48-1m-ultracode-cli2.1.195 | 1 | 3.0min | 0.2% | $0.88 | 0.20% |
| ts-type-error-fix-cycles | typescript-bun | opus48-1m-ultracode-cli2.1.195 | 1 | 2.8min | 0.2% | $0.76 | 0.17% |
| fixture-rework | bash | opus48-1m-medium-cli2.1.195 | 1 | 3.0min | 0.2% | $0.72 | 0.16% |
| fixture-rework | default | opus48-1m-medium-cli2.1.193 | 1 | 0.8min | 0.0% | $0.22 | 0.05% |
| fixture-rework | powershell | opus48-1m-medium-cli2.1.193 | 1 | 0.5min | 0.0% | $0.12 | 0.03% |
| fixture-rework | powershell-tool | opus48-1m-high-cli2.1.195 | 1 | 0.5min | 0.0% | $0.12 | 0.03% |
| fixture-rework | powershell-tool | opus48-1m-medium-cli2.1.193 | 1 | 1.0min | 0.1% | $0.27 | 0.06% |
| fixture-rework | typescript-bun | opus48-1m-high-cli2.1.195 | 1 | 1.2min | 0.1% | $0.37 | 0.08% |
| fixture-rework | typescript-bun | opus48-1m-medium-cli2.1.195 | 1 | 0.5min | 0.0% | $0.10 | 0.02% |
| fixture-rework | typescript-bun | opus48-1m-ultracode-cli2.1.195 | 1 | 0.5min | 0.0% | $0.19 | 0.04% |
| docker-pwsh-install | powershell | opus48-1m-xhigh-cli2.1.195 | 1 | 1.5min | 0.1% | $0.44 | 0.10% |
| docker-pwsh-install | powershell-tool | opus48-1m-xhigh-cli2.1.195 | 1 | 1.5min | 0.1% | $0.39 | 0.09% |
| bats-setup-issues | bash | opus48-1m-high-cli2.1.195 | 1 | 1.2min | 0.1% | $0.33 | 0.08% |
| mid-run-module-restructure | powershell | opus48-1m-ultracode-cli2.1.195 | 1 | 2.0min | 0.1% | $0.84 | 0.19% |
| actionlint-fix-cycles | powershell-tool | opus48-1m-medium-cli2.1.193 | 1 | 1.0min | 0.1% | $0.27 | 0.06% |
| actionlint-fix-cycles | typescript-bun | opus48-1m-medium-cli2.1.195 | 1 | 0.7min | 0.0% | $0.13 | 0.03% |
| act-fixture-paths | bash | opus48-1m-xhigh-cli2.1.195 | 1 | 1.0min | 0.1% | $0.25 | 0.06% |
| repeated-test-reruns | bash | opus48-1m-medium-cli2.1.195 | 2 | 4.7min | 0.3% | $1.21 | 0.28% |
| repeated-test-reruns | default | opus48-1m-medium-cli2.1.195 | 2 | 3.3min | 0.2% | $0.82 | 0.19% |
| repeated-test-reruns | powershell | opus48-1m-medium-cli2.1.193 | 2 | 2.7min | 0.2% | $0.66 | 0.15% |
| repeated-test-reruns | powershell | opus48-1m-ultracode-cli2.1.195 | 2 | 7.0min | 0.4% | $2.53 | 0.58% |
| repeated-test-reruns | powershell-tool | opus48-1m-medium-cli2.1.193 | 2 | 3.3min | 0.2% | $0.78 | 0.18% |
| repeated-test-reruns | typescript-bun | opus48-1m-ultracode-cli2.1.195 | 2 | 7.7min | 0.4% | $2.67 | 0.61% |
| ts-type-error-fix-cycles | typescript-bun | opus48-1m-medium-cli2.1.195 | 2 | 7.8min | 0.5% | $1.74 | 0.40% |
| fixture-rework | bash | opus48-1m-medium-cli2.1.193 | 2 | 1.5min | 0.1% | $0.41 | 0.09% |
| fixture-rework | powershell-tool | opus48-1m-xhigh-cli2.1.195 | 2 | 1.5min | 0.1% | $0.14 | 0.03% |
| docker-pwsh-install | powershell | opus48-1m-ultracode-cli2.1.195 | 2 | 3.0min | 0.2% | $0.83 | 0.19% |
| bats-setup-issues | bash | opus48-1m-xhigh-cli2.1.195 | 2 | 1.8min | 0.1% | $0.51 | 0.12% |
| repeated-test-reruns | bash | opus48-1m-medium-cli2.1.193 | 3 | 4.0min | 0.2% | $1.08 | 0.25% |
| repeated-test-reruns | default | opus48-1m-ultracode-cli2.1.195 | 3 | 7.3min | 0.4% | $2.02 | 0.46% |
| repeated-test-reruns | powershell-tool | opus48-1m-medium-cli2.1.195 | 3 | 3.3min | 0.2% | $0.85 | 0.20% |
| repeated-test-reruns | powershell-tool | opus48-1m-ultracode-cli2.1.195 | 3 | 6.3min | 0.4% | $1.64 | 0.37% |
| ts-type-error-fix-cycles | typescript-bun | opus48-1m-medium-cli2.1.193 | 3 | 8.0min | 0.5% | $2.17 | 0.50% |
| fixture-rework | default | opus48-1m-xhigh-cli2.1.195 | 3 | 1.5min | 0.1% | $0.42 | 0.10% |
| repeated-test-reruns | default | opus48-1m-medium-cli2.1.193 | 4 | 5.7min | 0.3% | $1.34 | 0.31% |
| repeated-test-reruns | typescript-bun | opus48-1m-medium-cli2.1.193 | 4 | 8.7min | 0.5% | $2.26 | 0.52% |
| repeated-test-reruns | typescript-bun | opus48-1m-medium-cli2.1.195 | 4 | 7.3min | 0.4% | $1.71 | 0.39% |
| fixture-rework | powershell | opus48-1m-high-cli2.1.195 | 4 | 2.5min | 0.1% | $0.62 | 0.14% |
| fixture-rework | powershell | opus48-1m-xhigh-cli2.1.195 | 4 | 3.8min | 0.2% | $0.53 | 0.12% |
| fixture-rework | typescript-bun | opus48-1m-xhigh-cli2.1.195 | 4 | 2.0min | 0.1% | $0.55 | 0.13% |
| repeated-test-reruns | bash | opus48-1m-high-cli2.1.195 | 5 | 11.7min | 0.7% | $3.16 | 0.72% |
| repeated-test-reruns | bash | opus48-1m-xhigh-cli2.1.195 | 5 | 13.7min | 0.8% | $4.08 | 0.93% |
| repeated-test-reruns | default | opus48-1m-high-cli2.1.195 | 5 | 10.0min | 0.6% | $2.94 | 0.67% |
| repeated-test-reruns | typescript-bun | opus48-1m-high-cli2.1.195 | 5 | 10.7min | 0.6% | $3.53 | 0.81% |
| repeated-test-reruns | typescript-bun | opus48-1m-xhigh-cli2.1.195 | 5 | 10.3min | 0.6% | $2.91 | 0.67% |
| fixture-rework | bash | opus48-1m-xhigh-cli2.1.195 | 5 | 6.8min | 0.4% | $1.83 | 0.42% |
| repeated-test-reruns | powershell | opus48-1m-xhigh-cli2.1.195 | 6 | 16.7min | 1.0% | $3.23 | 0.74% |
| repeated-test-reruns | powershell-tool | opus48-1m-high-cli2.1.195 | 6 | 9.0min | 0.5% | $2.12 | 0.49% |
| ts-type-error-fix-cycles | typescript-bun | opus48-1m-high-cli2.1.195 | 6 | 16.4min | 1.0% | $5.11 | 1.17% |
| fixture-rework | bash | opus48-1m-high-cli2.1.195 | 6 | 5.0min | 0.3% | $1.35 | 0.31% |
| repeated-test-reruns | powershell-tool | opus48-1m-xhigh-cli2.1.195 | 7 | 28.0min | 1.6% | $4.15 | 0.95% |
| ts-type-error-fix-cycles | typescript-bun | opus48-1m-xhigh-cli2.1.195 | 7 | 21.2min | 1.2% | $6.01 | 1.38% |
| repeated-test-reruns | default | opus48-1m-xhigh-cli2.1.195 | 8 | 18.3min | 1.1% | $5.59 | 1.28% |
| repeated-test-reruns | powershell | opus48-1m-high-cli2.1.195 | 8 | 22.3min | 1.3% | $5.14 | 1.18% |

</details>

#### Trap Descriptions

- **act-fixture-paths**: Test fixtures not found inside the act Docker container due to path issues.
- **actionlint-fix-cycles**: Workflow YAML required 3+ actionlint runs and 2+ fixes to pass.
- **bats-setup-issues**: Agent struggled with bats-core test framework setup or load helpers.
- **docker-pwsh-install**: Multiple Docker test runs trying to figure out how to install PowerShell in act's container.
- **fixture-rework**: Agent wrote, broke, and rewrote test fixture data (4+ fixture-related commands).
- **mid-run-module-restructure**: Agent restructured from a flat .ps1 script to a .psm1 module mid-run.
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
| bash | opus48-1m-high-cli2.1.195 | 7 | 12 | 17.9min | 1.0% | $4.84 | 1.11% |
| bash | opus48-1m-medium-cli2.1.193 | 5 | 5 | 5.5min | 0.3% | $1.49 | 0.34% |
| bash | opus48-1m-medium-cli2.1.195 | 2 | 3 | 7.7min | 0.4% | $1.92 | 0.44% |
| bash | opus48-1m-ultracode-cli2.1.195 | 2 | 1 | 3.0min | 0.2% | $0.88 | 0.20% |
| bash | opus48-1m-xhigh-cli2.1.195 | 7 | 13 | 23.2min | 1.4% | $6.67 | 1.53% |
| default | opus48-1m-high-cli2.1.195 | 7 | 5 | 10.0min | 0.6% | $2.94 | 0.67% |
| default | opus48-1m-medium-cli2.1.193 | 5 | 5 | 6.4min | 0.4% | $1.57 | 0.36% |
| default | opus48-1m-medium-cli2.1.195 | 2 | 2 | 3.3min | 0.2% | $0.82 | 0.19% |
| default | opus48-1m-ultracode-cli2.1.195 | 3 | 3 | 7.3min | 0.4% | $2.02 | 0.46% |
| default | opus48-1m-xhigh-cli2.1.195 | 7 | 11 | 19.8min | 1.2% | $6.01 | 1.37% |
| powershell | opus48-1m-high-cli2.1.195 | 7 | 12 | 24.8min | 1.4% | $5.75 | 1.32% |
| powershell | opus48-1m-medium-cli2.1.193 | 5 | 3 | 3.2min | 0.2% | $0.78 | 0.18% |
| powershell | opus48-1m-medium-cli2.1.195 | 2 | 0 | 0.0min | 0.0% | $0.00 | 0.00% |
| powershell | opus48-1m-ultracode-cli2.1.195 | 3 | 5 | 12.0min | 0.7% | $4.20 | 0.96% |
| powershell | opus48-1m-xhigh-cli2.1.195 | 7 | 11 | 21.9min | 1.3% | $4.20 | 0.96% |
| powershell-tool | opus48-1m-high-cli2.1.195 | 7 | 7 | 9.5min | 0.6% | $2.24 | 0.51% |
| powershell-tool | opus48-1m-medium-cli2.1.193 | 4 | 4 | 5.3min | 0.3% | $1.31 | 0.30% |
| powershell-tool | opus48-1m-medium-cli2.1.195 | 3 | 3 | 3.3min | 0.2% | $0.85 | 0.20% |
| powershell-tool | opus48-1m-ultracode-cli2.1.195 | 2 | 3 | 6.3min | 0.4% | $1.64 | 0.37% |
| powershell-tool | opus48-1m-xhigh-cli2.1.195 | 7 | 10 | 31.0min | 1.8% | $4.68 | 1.07% |
| typescript-bun | opus48-1m-high-cli2.1.195 | 7 | 12 | 28.3min | 1.7% | $9.01 | 2.06% |
| typescript-bun | opus48-1m-medium-cli2.1.193 | 4 | 7 | 16.7min | 1.0% | $4.43 | 1.01% |
| typescript-bun | opus48-1m-medium-cli2.1.195 | 3 | 8 | 16.3min | 1.0% | $3.68 | 0.84% |
| typescript-bun | opus48-1m-ultracode-cli2.1.195 | 2 | 4 | 11.0min | 0.6% | $3.62 | 0.83% |
| typescript-bun | opus48-1m-xhigh-cli2.1.195 | 7 | 16 | 33.5min | 2.0% | $9.48 | 2.17% |


<details>
<summary>Sorted by time lost (least first)</summary>

| Language | Model | Runs | Traps | Time Lost | % of Time | $ Lost | % of $ |
|------|-------|------|-------|-----------|-----------|--------|--------|
| powershell | opus48-1m-medium-cli2.1.195 | 2 | 0 | 0.0min | 0.0% | $0.00 | 0.00% |
| bash | opus48-1m-ultracode-cli2.1.195 | 2 | 1 | 3.0min | 0.2% | $0.88 | 0.20% |
| powershell | opus48-1m-medium-cli2.1.193 | 5 | 3 | 3.2min | 0.2% | $0.78 | 0.18% |
| default | opus48-1m-medium-cli2.1.195 | 2 | 2 | 3.3min | 0.2% | $0.82 | 0.19% |
| powershell-tool | opus48-1m-medium-cli2.1.195 | 3 | 3 | 3.3min | 0.2% | $0.85 | 0.20% |
| powershell-tool | opus48-1m-medium-cli2.1.193 | 4 | 4 | 5.3min | 0.3% | $1.31 | 0.30% |
| bash | opus48-1m-medium-cli2.1.193 | 5 | 5 | 5.5min | 0.3% | $1.49 | 0.34% |
| powershell-tool | opus48-1m-ultracode-cli2.1.195 | 2 | 3 | 6.3min | 0.4% | $1.64 | 0.37% |
| default | opus48-1m-medium-cli2.1.193 | 5 | 5 | 6.4min | 0.4% | $1.57 | 0.36% |
| default | opus48-1m-ultracode-cli2.1.195 | 3 | 3 | 7.3min | 0.4% | $2.02 | 0.46% |
| bash | opus48-1m-medium-cli2.1.195 | 2 | 3 | 7.7min | 0.4% | $1.92 | 0.44% |
| powershell-tool | opus48-1m-high-cli2.1.195 | 7 | 7 | 9.5min | 0.6% | $2.24 | 0.51% |
| default | opus48-1m-high-cli2.1.195 | 7 | 5 | 10.0min | 0.6% | $2.94 | 0.67% |
| typescript-bun | opus48-1m-ultracode-cli2.1.195 | 2 | 4 | 11.0min | 0.6% | $3.62 | 0.83% |
| powershell | opus48-1m-ultracode-cli2.1.195 | 3 | 5 | 12.0min | 0.7% | $4.20 | 0.96% |
| typescript-bun | opus48-1m-medium-cli2.1.195 | 3 | 8 | 16.3min | 1.0% | $3.68 | 0.84% |
| typescript-bun | opus48-1m-medium-cli2.1.193 | 4 | 7 | 16.7min | 1.0% | $4.43 | 1.01% |
| bash | opus48-1m-high-cli2.1.195 | 7 | 12 | 17.9min | 1.0% | $4.84 | 1.11% |
| default | opus48-1m-xhigh-cli2.1.195 | 7 | 11 | 19.8min | 1.2% | $6.01 | 1.37% |
| powershell | opus48-1m-xhigh-cli2.1.195 | 7 | 11 | 21.9min | 1.3% | $4.20 | 0.96% |
| bash | opus48-1m-xhigh-cli2.1.195 | 7 | 13 | 23.2min | 1.4% | $6.67 | 1.53% |
| powershell | opus48-1m-high-cli2.1.195 | 7 | 12 | 24.8min | 1.4% | $5.75 | 1.32% |
| typescript-bun | opus48-1m-high-cli2.1.195 | 7 | 12 | 28.3min | 1.7% | $9.01 | 2.06% |
| powershell-tool | opus48-1m-xhigh-cli2.1.195 | 7 | 10 | 31.0min | 1.8% | $4.68 | 1.07% |
| typescript-bun | opus48-1m-xhigh-cli2.1.195 | 7 | 16 | 33.5min | 2.0% | $9.48 | 2.17% |

</details>

<details>
<summary>Sorted by $ lost (least first)</summary>

| Language | Model | Runs | Traps | Time Lost | % of Time | $ Lost | % of $ |
|------|-------|------|-------|-----------|-----------|--------|--------|
| powershell | opus48-1m-medium-cli2.1.195 | 2 | 0 | 0.0min | 0.0% | $0.00 | 0.00% |
| powershell | opus48-1m-medium-cli2.1.193 | 5 | 3 | 3.2min | 0.2% | $0.78 | 0.18% |
| default | opus48-1m-medium-cli2.1.195 | 2 | 2 | 3.3min | 0.2% | $0.82 | 0.19% |
| powershell-tool | opus48-1m-medium-cli2.1.195 | 3 | 3 | 3.3min | 0.2% | $0.85 | 0.20% |
| bash | opus48-1m-ultracode-cli2.1.195 | 2 | 1 | 3.0min | 0.2% | $0.88 | 0.20% |
| powershell-tool | opus48-1m-medium-cli2.1.193 | 4 | 4 | 5.3min | 0.3% | $1.31 | 0.30% |
| bash | opus48-1m-medium-cli2.1.193 | 5 | 5 | 5.5min | 0.3% | $1.49 | 0.34% |
| default | opus48-1m-medium-cli2.1.193 | 5 | 5 | 6.4min | 0.4% | $1.57 | 0.36% |
| powershell-tool | opus48-1m-ultracode-cli2.1.195 | 2 | 3 | 6.3min | 0.4% | $1.64 | 0.37% |
| bash | opus48-1m-medium-cli2.1.195 | 2 | 3 | 7.7min | 0.4% | $1.92 | 0.44% |
| default | opus48-1m-ultracode-cli2.1.195 | 3 | 3 | 7.3min | 0.4% | $2.02 | 0.46% |
| powershell-tool | opus48-1m-high-cli2.1.195 | 7 | 7 | 9.5min | 0.6% | $2.24 | 0.51% |
| default | opus48-1m-high-cli2.1.195 | 7 | 5 | 10.0min | 0.6% | $2.94 | 0.67% |
| typescript-bun | opus48-1m-ultracode-cli2.1.195 | 2 | 4 | 11.0min | 0.6% | $3.62 | 0.83% |
| typescript-bun | opus48-1m-medium-cli2.1.195 | 3 | 8 | 16.3min | 1.0% | $3.68 | 0.84% |
| powershell | opus48-1m-ultracode-cli2.1.195 | 3 | 5 | 12.0min | 0.7% | $4.20 | 0.96% |
| powershell | opus48-1m-xhigh-cli2.1.195 | 7 | 11 | 21.9min | 1.3% | $4.20 | 0.96% |
| typescript-bun | opus48-1m-medium-cli2.1.193 | 4 | 7 | 16.7min | 1.0% | $4.43 | 1.01% |
| powershell-tool | opus48-1m-xhigh-cli2.1.195 | 7 | 10 | 31.0min | 1.8% | $4.68 | 1.07% |
| bash | opus48-1m-high-cli2.1.195 | 7 | 12 | 17.9min | 1.0% | $4.84 | 1.11% |
| powershell | opus48-1m-high-cli2.1.195 | 7 | 12 | 24.8min | 1.4% | $5.75 | 1.32% |
| default | opus48-1m-xhigh-cli2.1.195 | 7 | 11 | 19.8min | 1.2% | $6.01 | 1.37% |
| bash | opus48-1m-xhigh-cli2.1.195 | 7 | 13 | 23.2min | 1.4% | $6.67 | 1.53% |
| typescript-bun | opus48-1m-high-cli2.1.195 | 7 | 12 | 28.3min | 1.7% | $9.01 | 2.06% |
| typescript-bun | opus48-1m-xhigh-cli2.1.195 | 7 | 16 | 33.5min | 2.0% | $9.48 | 2.17% |

</details>

### Prompt Cache Savings

| Status | Runs | $ Saved | % of $ |
|--------|------|---------|--------|
| Full hit (100%) | 1 | $0.12 | 0.03% |
| Partial | 109 | $10.96 | 2.51% |
| Miss | 7 | $0.00 | 0.00% |

## Test Quality Evaluation

### Structural Metrics by Language/Model/Effort

Automated analysis of test files: test count, assertion count, and test-to-code line ratio.

| Language | Model | Avg Tests | Avg Assertions | Avg Assert/Test | Avg Test:Code Ratio |
|------|-------|-----------|----------------|-----------------|---------------------|
| bash | opus48-1m-high | 32.1 | 67.3 | 2.1 | 1.32 |
| bash | opus48-1m-medium | 22.4 | 39.0 | 1.7 | 1.19 |
| bash | opus48-1m-ultracode | 51.0 | 85.0 | 1.7 | 1.15 |
| bash | opus48-1m-xhigh | 30.6 | 76.4 | 2.5 | 1.00 |
| default | opus48-1m-high | 28.3 | 55.9 | 2.0 | 1.45 |
| default | opus48-1m-medium | 27.0 | 49.1 | 1.8 | 1.01 |
| default | opus48-1m-ultracode | 42.0 | 80.0 | 1.9 | 1.23 |
| default | opus48-1m-xhigh | 36.4 | 68.7 | 1.9 | 0.97 |
| powershell | opus48-1m-high | 44.7 | 82.4 | 1.8 | 5.25 |
| powershell | opus48-1m-medium | 33.7 | 63.0 | 1.9 | 2.54 |
| powershell | opus48-1m-ultracode | 60.3 | 94.7 | 1.6 | 4.34 |
| powershell | opus48-1m-xhigh | 47.4 | 82.0 | 1.7 | 3.83 |
| powershell-tool | opus48-1m-high | 40.1 | 76.1 | 1.9 | 3.47 |
| powershell-tool | opus48-1m-medium | 31.9 | 56.7 | 1.8 | 4.49 |
| powershell-tool | opus48-1m-ultracode | 47.0 | 75.0 | 1.6 | 5.41 |
| powershell-tool | opus48-1m-xhigh | 50.4 | 103.9 | 2.1 | 3.07 |
| typescript-bun | opus48-1m-high | 40.3 | 87.3 | 2.2 | 1.02 |
| typescript-bun | opus48-1m-medium | 30.9 | 65.1 | 2.1 | 1.02 |
| typescript-bun | opus48-1m-ultracode | 59.5 | 102.5 | 1.7 | 1.14 |
| typescript-bun | opus48-1m-xhigh | 51.4 | 104.0 | 2.0 | 1.19 |


<details>
<summary>Sorted by avg tests (most first)</summary>

| Language | Model | Avg Tests | Avg Assertions | Avg Assert/Test | Avg Test:Code Ratio |
|------|-------|-----------|----------------|-----------------|---------------------|
| powershell | opus48-1m-ultracode | 60.3 | 94.7 | 1.6 | 4.34 |
| typescript-bun | opus48-1m-ultracode | 59.5 | 102.5 | 1.7 | 1.14 |
| typescript-bun | opus48-1m-xhigh | 51.4 | 104.0 | 2.0 | 1.19 |
| bash | opus48-1m-ultracode | 51.0 | 85.0 | 1.7 | 1.15 |
| powershell-tool | opus48-1m-xhigh | 50.4 | 103.9 | 2.1 | 3.07 |
| powershell | opus48-1m-xhigh | 47.4 | 82.0 | 1.7 | 3.83 |
| powershell-tool | opus48-1m-ultracode | 47.0 | 75.0 | 1.6 | 5.41 |
| powershell | opus48-1m-high | 44.7 | 82.4 | 1.8 | 5.25 |
| default | opus48-1m-ultracode | 42.0 | 80.0 | 1.9 | 1.23 |
| typescript-bun | opus48-1m-high | 40.3 | 87.3 | 2.2 | 1.02 |
| powershell-tool | opus48-1m-high | 40.1 | 76.1 | 1.9 | 3.47 |
| default | opus48-1m-xhigh | 36.4 | 68.7 | 1.9 | 0.97 |
| powershell | opus48-1m-medium | 33.7 | 63.0 | 1.9 | 2.54 |
| bash | opus48-1m-high | 32.1 | 67.3 | 2.1 | 1.32 |
| powershell-tool | opus48-1m-medium | 31.9 | 56.7 | 1.8 | 4.49 |
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
| typescript-bun | opus48-1m-xhigh | 51.4 | 104.0 | 2.0 | 1.19 |
| powershell-tool | opus48-1m-xhigh | 50.4 | 103.9 | 2.1 | 3.07 |
| typescript-bun | opus48-1m-ultracode | 59.5 | 102.5 | 1.7 | 1.14 |
| powershell | opus48-1m-ultracode | 60.3 | 94.7 | 1.6 | 4.34 |
| typescript-bun | opus48-1m-high | 40.3 | 87.3 | 2.2 | 1.02 |
| bash | opus48-1m-ultracode | 51.0 | 85.0 | 1.7 | 1.15 |
| powershell | opus48-1m-high | 44.7 | 82.4 | 1.8 | 5.25 |
| powershell | opus48-1m-xhigh | 47.4 | 82.0 | 1.7 | 3.83 |
| default | opus48-1m-ultracode | 42.0 | 80.0 | 1.9 | 1.23 |
| bash | opus48-1m-xhigh | 30.6 | 76.4 | 2.5 | 1.00 |
| powershell-tool | opus48-1m-high | 40.1 | 76.1 | 1.9 | 3.47 |
| powershell-tool | opus48-1m-ultracode | 47.0 | 75.0 | 1.6 | 5.41 |
| default | opus48-1m-xhigh | 36.4 | 68.7 | 1.9 | 0.97 |
| bash | opus48-1m-high | 32.1 | 67.3 | 2.1 | 1.32 |
| typescript-bun | opus48-1m-medium | 30.9 | 65.1 | 2.1 | 1.02 |
| powershell | opus48-1m-medium | 33.7 | 63.0 | 1.9 | 2.54 |
| powershell-tool | opus48-1m-medium | 31.9 | 56.7 | 1.8 | 4.49 |
| default | opus48-1m-high | 28.3 | 55.9 | 2.0 | 1.45 |
| default | opus48-1m-medium | 27.0 | 49.1 | 1.8 | 1.01 |
| bash | opus48-1m-medium | 22.4 | 39.0 | 1.7 | 1.19 |

</details>

<details>
<summary>Sorted by avg test:code ratio (highest first)</summary>

| Language | Model | Avg Tests | Avg Assertions | Avg Assert/Test | Avg Test:Code Ratio |
|------|-------|-----------|----------------|-----------------|---------------------|
| powershell-tool | opus48-1m-ultracode | 47.0 | 75.0 | 1.6 | 5.41 |
| powershell | opus48-1m-high | 44.7 | 82.4 | 1.8 | 5.25 |
| powershell-tool | opus48-1m-medium | 31.9 | 56.7 | 1.8 | 4.49 |
| powershell | opus48-1m-ultracode | 60.3 | 94.7 | 1.6 | 4.34 |
| powershell | opus48-1m-xhigh | 47.4 | 82.0 | 1.7 | 3.83 |
| powershell-tool | opus48-1m-high | 40.1 | 76.1 | 1.9 | 3.47 |
| powershell-tool | opus48-1m-xhigh | 50.4 | 103.9 | 2.1 | 3.07 |
| powershell | opus48-1m-medium | 33.7 | 63.0 | 1.9 | 2.54 |
| default | opus48-1m-high | 28.3 | 55.9 | 2.0 | 1.45 |
| bash | opus48-1m-high | 32.1 | 67.3 | 2.1 | 1.32 |
| default | opus48-1m-ultracode | 42.0 | 80.0 | 1.9 | 1.23 |
| typescript-bun | opus48-1m-xhigh | 51.4 | 104.0 | 2.0 | 1.19 |
| bash | opus48-1m-medium | 22.4 | 39.0 | 1.7 | 1.19 |
| bash | opus48-1m-ultracode | 51.0 | 85.0 | 1.7 | 1.15 |
| typescript-bun | opus48-1m-ultracode | 59.5 | 102.5 | 1.7 | 1.14 |
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
| Semantic Version Bumper | powershell-tool | opus48-1m-high | 40 | 69 | 1.7 | 360 | 585 | 0.62 |
| Semantic Version Bumper | powershell-tool | opus48-1m-medium | 35 | 57 | 1.6 | 380 | 118 | 3.22 |
| Semantic Version Bumper | powershell-tool | opus48-1m-ultracode | 45 | 85 | 1.9 | 532 | 127 | 4.19 |
| Semantic Version Bumper | powershell-tool | opus48-1m-xhigh | 56 | 95 | 1.7 | 626 | 666 | 0.94 |
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
| PR Label Assigner | powershell-tool | opus48-1m-high | 38 | 57 | 1.5 | 443 | 82 | 5.40 |
| PR Label Assigner | powershell-tool | opus48-1m-medium | 26 | 46 | 1.8 | 210 | 253 | 0.83 |
| PR Label Assigner | powershell-tool | opus48-1m-ultracode | 49 | 65 | 1.3 | 537 | 81 | 6.63 |
| PR Label Assigner | powershell-tool | opus48-1m-xhigh | 50 | 73 | 1.5 | 600 | 81 | 7.41 |
| PR Label Assigner | typescript-bun | opus48-1m-high | 29 | 43 | 1.5 | 307 | 474 | 0.65 |
| PR Label Assigner | typescript-bun | opus48-1m-medium | 25 | 53 | 2.1 | 362 | 372 | 0.97 |
| PR Label Assigner | typescript-bun | opus48-1m-ultracode | 46 | 70 | 1.5 | 428 | 623 | 0.69 |
| PR Label Assigner | typescript-bun | opus48-1m-xhigh | 47 | 72 | 1.5 | 471 | 808 | 0.58 |
| Dependency License Checker | bash | opus48-1m-high | 26 | 74 | 2.8 | 449 | 315 | 1.43 |
| Dependency License Checker | bash | opus48-1m-medium | 24 | 52 | 2.2 | 334 | 191 | 1.75 |
| Dependency License Checker | bash | opus48-1m-xhigh | 39 | 82 | 2.1 | 426 | 422 | 1.01 |
| Dependency License Checker | default | opus48-1m-high | 33 | 52 | 1.6 | 314 | 84 | 3.74 |
| Dependency License Checker | default | opus48-1m-medium | 19 | 37 | 1.9 | 212 | 433 | 0.49 |
| Dependency License Checker | default | opus48-1m-ultracode | 37 | 93 | 2.5 | 445 | 274 | 1.62 |
| Dependency License Checker | default | opus48-1m-xhigh | 28 | 53 | 1.9 | 384 | 555 | 0.69 |
| Dependency License Checker | powershell | opus48-1m-high | 54 | 79 | 1.5 | 521 | 111 | 4.69 |
| Dependency License Checker | powershell | opus48-1m-medium | 34 | 56 | 1.6 | 386 | 68 | 5.68 |
| Dependency License Checker | powershell | opus48-1m-xhigh | 45 | 70 | 1.6 | 634 | 137 | 4.63 |
| Dependency License Checker | powershell-tool | opus48-1m-high | 35 | 63 | 1.8 | 381 | 326 | 1.17 |
| Dependency License Checker | powershell-tool | opus48-1m-medium | 32 | 53 | 1.7 | 388 | 60 | 6.47 |
| Dependency License Checker | powershell-tool | opus48-1m-xhigh | 47 | 87 | 1.9 | 503 | 480 | 1.05 |
| Dependency License Checker | typescript-bun | opus48-1m-high | 40 | 106 | 2.6 | 732 | 511 | 1.43 |
| Dependency License Checker | typescript-bun | opus48-1m-medium | 32 | 76 | 2.4 | 548 | 358 | 1.53 |
| Dependency License Checker | typescript-bun | opus48-1m-xhigh | 39 | 56 | 1.4 | 596 | 441 | 1.35 |
| Test Results Aggregator | bash | opus48-1m-high | 20 | 63 | 3.1 | 286 | 275 | 1.04 |
| Test Results Aggregator | bash | opus48-1m-medium | 25 | 26 | 1.0 | 221 | 291 | 0.76 |
| Test Results Aggregator | bash | opus48-1m-xhigh | 32 | 62 | 1.9 | 292 | 580 | 0.50 |
| Test Results Aggregator | default | opus48-1m-high | 21 | 67 | 3.2 | 451 | 450 | 1.00 |
| Test Results Aggregator | default | opus48-1m-medium | 23 | 63 | 2.7 | 493 | 263 | 1.87 |
| Test Results Aggregator | default | opus48-1m-xhigh | 26 | 66 | 2.5 | 514 | 483 | 1.06 |
| Test Results Aggregator | powershell | opus48-1m-high | 38 | 91 | 2.4 | 527 | 72 | 7.32 |
| Test Results Aggregator | powershell | opus48-1m-medium | 29 | 52 | 1.8 | 250 | 253 | 0.99 |
| Test Results Aggregator | powershell | opus48-1m-xhigh | 59 | 108 | 1.8 | 489 | 95 | 5.15 |
| Test Results Aggregator | powershell-tool | opus48-1m-high | 38 | 85 | 2.2 | 584 | 92 | 6.35 |
| Test Results Aggregator | powershell-tool | opus48-1m-medium | 31 | 58 | 1.9 | 269 | 568 | 0.47 |
| Test Results Aggregator | powershell-tool | opus48-1m-xhigh | 50 | 102 | 2.0 | 732 | 100 | 7.32 |
| Test Results Aggregator | typescript-bun | opus48-1m-high | 49 | 98 | 2.0 | 550 | 971 | 0.57 |
| Test Results Aggregator | typescript-bun | opus48-1m-medium | 34 | 57 | 1.7 | 408 | 707 | 0.58 |
| Test Results Aggregator | typescript-bun | opus48-1m-xhigh | 50 | 111 | 2.2 | 756 | 576 | 1.31 |
| Environment Matrix Generator | bash | opus48-1m-high | 31 | 63 | 2.0 | 306 | 159 | 1.92 |
| Environment Matrix Generator | bash | opus48-1m-medium | 22 | 34 | 1.5 | 278 | 132 | 2.11 |
| Environment Matrix Generator | bash | opus48-1m-xhigh | 18 | 23 | 1.3 | 213 | 429 | 0.50 |
| Environment Matrix Generator | default | opus48-1m-high | 27 | 49 | 1.8 | 435 | 270 | 1.61 |
| Environment Matrix Generator | default | opus48-1m-medium | 26 | 50 | 1.9 | 350 | 356 | 0.98 |
| Environment Matrix Generator | default | opus48-1m-xhigh | 33 | 58 | 1.8 | 583 | 374 | 1.56 |
| Environment Matrix Generator | powershell | opus48-1m-high | 51 | 101 | 2.0 | 510 | 72 | 7.08 |
| Environment Matrix Generator | powershell | opus48-1m-medium | 31 | 71 | 2.3 | 419 | 389 | 1.08 |
| Environment Matrix Generator | powershell | opus48-1m-xhigh | 34 | 74 | 2.2 | 358 | 316 | 1.13 |
| Environment Matrix Generator | powershell-tool | opus48-1m-high | 55 | 106 | 1.9 | 669 | 256 | 2.61 |
| Environment Matrix Generator | powershell-tool | opus48-1m-medium | 31 | 57 | 1.8 | 352 | 36 | 9.78 |
| Environment Matrix Generator | powershell-tool | opus48-1m-xhigh | 55 | 146 | 2.7 | 673 | 395 | 1.70 |
| Environment Matrix Generator | typescript-bun | opus48-1m-high | 38 | 83 | 2.2 | 568 | 393 | 1.45 |
| Environment Matrix Generator | typescript-bun | opus48-1m-medium | 29 | 55 | 1.9 | 547 | 262 | 2.09 |
| Environment Matrix Generator | typescript-bun | opus48-1m-xhigh | 62 | 101 | 1.6 | 985 | 587 | 1.68 |
| Artifact Cleanup Script | bash | opus48-1m-high | 23 | 43 | 1.9 | 278 | 292 | 0.95 |
| Artifact Cleanup Script | bash | opus48-1m-medium | 17 | 55 | 3.2 | 304 | 258 | 1.18 |
| Artifact Cleanup Script | bash | opus48-1m-xhigh | 34 | 144 | 4.2 | 502 | 511 | 0.98 |
| Artifact Cleanup Script | default | opus48-1m-high | 24 | 57 | 2.4 | 369 | 505 | 0.73 |
| Artifact Cleanup Script | default | opus48-1m-medium | 28 | 54 | 1.9 | 253 | 263 | 0.96 |
| Artifact Cleanup Script | default | opus48-1m-xhigh | 36 | 77 | 2.1 | 613 | 450 | 1.36 |
| Artifact Cleanup Script | powershell | opus48-1m-high | 25 | 55 | 2.2 | 339 | 420 | 0.81 |
| Artifact Cleanup Script | powershell | opus48-1m-medium | 25 | 62 | 2.5 | 328 | 292 | 1.12 |
| Artifact Cleanup Script | powershell | opus48-1m-xhigh | 42 | 100 | 2.4 | 577 | 73 | 7.90 |
| Artifact Cleanup Script | powershell-tool | opus48-1m-high | 38 | 79 | 2.1 | 442 | 89 | 4.97 |
| Artifact Cleanup Script | powershell-tool | opus48-1m-medium | 25 | 48 | 1.9 | 369 | 155 | 2.38 |
| Artifact Cleanup Script | powershell-tool | opus48-1m-xhigh | 37 | 95 | 2.6 | 523 | 320 | 1.63 |
| Artifact Cleanup Script | typescript-bun | opus48-1m-high | 33 | 80 | 2.4 | 406 | 622 | 0.65 |
| Artifact Cleanup Script | typescript-bun | opus48-1m-medium | 23 | 53 | 2.3 | 273 | 525 | 0.52 |
| Artifact Cleanup Script | typescript-bun | opus48-1m-xhigh | 29 | 69 | 2.4 | 580 | 585 | 0.99 |
| Secret Rotation Validator | bash | opus48-1m-high | 46 | 90 | 2.0 | 449 | 472 | 0.95 |
| Secret Rotation Validator | bash | opus48-1m-medium | 27 | 62 | 2.3 | 229 | 372 | 0.62 |
| Secret Rotation Validator | bash | opus48-1m-xhigh | 44 | 132 | 3.0 | 503 | 372 | 1.35 |
| Secret Rotation Validator | default | opus48-1m-high | 27 | 58 | 2.1 | 453 | 290 | 1.56 |
| Secret Rotation Validator | default | opus48-1m-medium | 25 | 43 | 1.7 | 261 | 404 | 0.65 |
| Secret Rotation Validator | default | opus48-1m-xhigh | 48 | 95 | 2.0 | 562 | 653 | 0.86 |
| Secret Rotation Validator | powershell | opus48-1m-high | 46 | 89 | 1.9 | 414 | 264 | 1.57 |
| Secret Rotation Validator | powershell | opus48-1m-medium | 46 | 91 | 2.0 | 446 | 299 | 1.49 |
| Secret Rotation Validator | powershell | opus48-1m-xhigh | 44 | 78 | 1.8 | 557 | 107 | 5.21 |
| Secret Rotation Validator | powershell-tool | opus48-1m-high | 37 | 74 | 2.0 | 476 | 151 | 3.15 |
| Secret Rotation Validator | powershell-tool | opus48-1m-medium | 43 | 78 | 1.8 | 481 | 58 | 8.29 |
| Secret Rotation Validator | powershell-tool | opus48-1m-xhigh | 58 | 129 | 2.2 | 526 | 360 | 1.46 |
| Secret Rotation Validator | typescript-bun | opus48-1m-high | 42 | 97 | 2.3 | 699 | 571 | 1.22 |
| Secret Rotation Validator | typescript-bun | opus48-1m-medium | 35 | 86 | 2.5 | 435 | 701 | 0.62 |
| Secret Rotation Validator | typescript-bun | opus48-1m-xhigh | 65 | 171 | 2.6 | 800 | 810 | 0.99 |
| Dependency License Checker | powershell | opus48-1m-ultracode | 72 | 107 | 1.5 | 639 | 117 | 5.46 |

</details>

## Per-Run Results

*Tests Quality = Overall (1-5) from LLM-as-judge of generated test code (dimensions: coverage, rigor, design). `—` = no judge data.*

| Task | Language | Model | Duration | Turns | Errors | Cost | Tests Quality | Chosen | Status |
|------|----------|-------|----------|-------|--------|------|-----------|--------|--------|
| Artifact Cleanup Script | bash | opus48-1m-high | 11.6min | 47 | 0 | $3.32 | — | bash | ok |
| Artifact Cleanup Script | bash | opus48-1m-medium | 11.4min | 53 | 1 | $3.16 | — | bash | ok |
| Artifact Cleanup Script | bash | opus48-1m-xhigh | 18.1min | 49 | 2 | $5.08 | — | bash | ok |
| Artifact Cleanup Script | default | opus48-1m-high | 10.2min | 50 | 0 | $3.16 | — | python | ok |
| Artifact Cleanup Script | default | opus48-1m-medium | 9.9min | 43 | 0 | $2.37 | — | powershell | ok |
| Artifact Cleanup Script | default | opus48-1m-xhigh | 19.1min | 77 | 0 | $6.84 | — | python | ok |
| Artifact Cleanup Script | powershell | opus48-1m-high | 9.6min | 35 | 2 | $2.60 | — | powershell | ok |
| Artifact Cleanup Script | powershell | opus48-1m-medium | 9.3min | 28 | 0 | $2.26 | — | powershell | ok |
| Artifact Cleanup Script | powershell | opus48-1m-xhigh | 25.0min | 92 | 1 | $7.41 | — | powershell | ok |
| Artifact Cleanup Script | powershell-tool | opus48-1m-high | 11.8min | 31 | 1 | $2.83 | — | powershell | ok |
| Artifact Cleanup Script | powershell-tool | opus48-1m-medium | 11.9min | 46 | 1 | $2.91 | — | powershell | ok |
| Artifact Cleanup Script | powershell-tool | opus48-1m-xhigh | 30.0min | 0 | 1 | $0.00 | — | powershell | timeout |
| Artifact Cleanup Script | typescript-bun | opus48-1m-high | 14.8min | 82 | 1 | $6.00 | — | typescript | ok |
| Artifact Cleanup Script | typescript-bun | opus48-1m-medium | 9.2min | 44 | 0 | $2.44 | — | typescript | ok |
| Artifact Cleanup Script | typescript-bun | opus48-1m-xhigh | 21.6min | 49 | 2 | $5.91 | — | typescript | ok |
| Dependency License Checker | bash | opus48-1m-high | 15.0min | 51 | 3 | $4.02 | — | bash | ok |
| Dependency License Checker | bash | opus48-1m-medium | 5.7min | 24 | 0 | $1.45 | — | bash | ok |
| Dependency License Checker | bash | opus48-1m-xhigh | 23.9min | 96 | 2 | $8.01 | — | bash | ok |
| Dependency License Checker | default | opus48-1m-high | 9.0min | 34 | 0 | $2.24 | — | powershell | ok |
| Dependency License Checker | default | opus48-1m-medium | 7.9min | 33 | 0 | $1.94 | — | python | ok |
| Dependency License Checker | default | opus48-1m-ultracode | 21.3min | 67 | 0 | $5.41 | — | powershell | ok |
| Dependency License Checker | default | opus48-1m-xhigh | 13.6min | 34 | 0 | $3.67 | — | python | ok |
| Dependency License Checker | powershell | opus48-1m-high | 12.8min | 42 | 1 | $3.09 | — | powershell | ok |
| Dependency License Checker | powershell | opus48-1m-medium | 7.7min | 33 | 0 | $1.93 | — | powershell | ok |
| Dependency License Checker | powershell | opus48-1m-ultracode | 4.3min | 23 | 0 | $1.21 | — | powershell | ok |
| Dependency License Checker | powershell | opus48-1m-xhigh | 30.0min | 0 | 5 | $0.00 | — | powershell | timeout |
| Dependency License Checker | powershell-tool | opus48-1m-high | 12.2min | 33 | 0 | $2.63 | — | powershell | ok |
| Dependency License Checker | powershell-tool | opus48-1m-medium | 12.7min | 49 | 0 | $3.35 | — | powershell | ok |
| Dependency License Checker | powershell-tool | opus48-1m-xhigh | 25.2min | 49 | 0 | $6.38 | — | powershell | ok |
| Dependency License Checker | typescript-bun | opus48-1m-high | 11.5min | 47 | 0 | $3.04 | — | typescript | ok |
| Dependency License Checker | typescript-bun | opus48-1m-medium | 8.7min | 45 | 0 | $2.33 | — | typescript | ok |
| Dependency License Checker | typescript-bun | opus48-1m-xhigh | 19.6min | 48 | 0 | $5.16 | — | typescript | ok |
| Environment Matrix Generator | bash | opus48-1m-high | 9.4min | 39 | 1 | $2.51 | — | bash | ok |
| Environment Matrix Generator | bash | opus48-1m-medium | 5.8min | 27 | 0 | $1.72 | — | bash | ok |
| Environment Matrix Generator | bash | opus48-1m-xhigh | 18.6min | 59 | 0 | $5.52 | — | bash | ok |
| Environment Matrix Generator | default | opus48-1m-high | 8.2min | 24 | 0 | $2.01 | — | python | ok |
| Environment Matrix Generator | default | opus48-1m-medium | 6.7min | 28 | 0 | $2.01 | — | python | ok |
| Environment Matrix Generator | default | opus48-1m-xhigh | 16.2min | 38 | 0 | $4.05 | — | python | ok |
| Environment Matrix Generator | powershell | opus48-1m-high | 13.7min | 44 | 1 | $3.48 | — | powershell | ok |
| Environment Matrix Generator | powershell | opus48-1m-medium | 9.3min | 33 | 0 | $2.29 | — | powershell | ok |
| Environment Matrix Generator | powershell | opus48-1m-xhigh | 28.4min | 58 | 0 | $7.16 | — | powershell | ok |
| Environment Matrix Generator | powershell-tool | opus48-1m-high | 9.2min | 27 | 0 | $3.06 | — | powershell | ok |
| Environment Matrix Generator | powershell-tool | opus48-1m-medium | 12.9min | 52 | 2 | $3.60 | — | powershell | ok |
| Environment Matrix Generator | powershell-tool | opus48-1m-xhigh | 30.0min | 0 | 0 | $0.00 | — | powershell | timeout |
| Environment Matrix Generator | typescript-bun | opus48-1m-high | 13.3min | 69 | 0 | $3.94 | — | typescript | ok |
| Environment Matrix Generator | typescript-bun | opus48-1m-medium | 9.1min | 40 | 0 | $2.29 | — | typescript | ok |
| Environment Matrix Generator | typescript-bun | opus48-1m-xhigh | 25.3min | 77 | 1 | $7.25 | — | typescript | ok |
| PR Label Assigner | bash | opus48-1m-high | 10.1min | 31 | 0 | $2.45 | — | bash | ok |
| PR Label Assigner | bash | opus48-1m-medium | 4.8min | 20 | 0 | $1.22 | — | bash | ok |
| PR Label Assigner | bash | opus48-1m-ultracode | 18.6min | 55 | 2 | $5.24 | — | bash | ok |
| PR Label Assigner | bash | opus48-1m-xhigh | 20.5min | 64 | 0 | $5.87 | — | bash | ok |
| PR Label Assigner | default | opus48-1m-high | 7.1min | 25 | 1 | $1.86 | — | python | ok |
| PR Label Assigner | default | opus48-1m-medium | 8.2min | 36 | 1 | $1.91 | — | powershell | ok |
| PR Label Assigner | default | opus48-1m-ultracode | 12.6min | 51 | 0 | $4.18 | — | python | ok |
| PR Label Assigner | default | opus48-1m-xhigh | 9.8min | 29 | 0 | $2.66 | — | python | ok |
| PR Label Assigner | powershell | opus48-1m-high | 11.0min | 47 | 0 | $2.65 | — | powershell | ok |
| PR Label Assigner | powershell | opus48-1m-medium | 6.3min | 23 | 0 | $1.52 | — | powershell | ok |
| PR Label Assigner | powershell | opus48-1m-ultracode | 21.3min | 52 | 0 | $5.68 | — | powershell | ok |
| PR Label Assigner | powershell | opus48-1m-xhigh | 19.4min | 63 | 0 | $5.67 | — | powershell | ok |
| PR Label Assigner | powershell-tool | opus48-1m-high | 11.4min | 41 | 0 | $2.78 | — | powershell | ok |
| PR Label Assigner | powershell-tool | opus48-1m-medium | 7.6min | 27 | 1 | $1.66 | — | powershell | ok |
| PR Label Assigner | powershell-tool | opus48-1m-ultracode | 22.3min | 50 | 1 | $5.54 | — | powershell | ok |
| PR Label Assigner | powershell-tool | opus48-1m-xhigh | 30.0min | 0 | 0 | $0.00 | — | powershell | timeout |
| PR Label Assigner | typescript-bun | opus48-1m-high | 3.0min | 26 | 1 | $1.17 | — | typescript | ok |
| PR Label Assigner | typescript-bun | opus48-1m-medium | 13.1min | 44 | 0 | $2.48 | — | typescript | ok |
| PR Label Assigner | typescript-bun | opus48-1m-ultracode | 21.5min | 62 | 5 | $5.80 | — | typescript | ok |
| PR Label Assigner | typescript-bun | opus48-1m-xhigh | 19.8min | 72 | 0 | $6.01 | — | typescript | ok |
| Secret Rotation Validator | bash | opus48-1m-high | 9.4min | 33 | 0 | $2.38 | — | bash | ok |
| Secret Rotation Validator | bash | opus48-1m-medium | 23.9min | 64 | 6 | $5.71 | — | bash | ok |
| Secret Rotation Validator | bash | opus48-1m-xhigh | 21.4min | 55 | 0 | $5.41 | — | bash | ok |
| Secret Rotation Validator | default | opus48-1m-high | 9.1min | 47 | 0 | $3.12 | — | python | ok |
| Secret Rotation Validator | default | opus48-1m-medium | 5.9min | 29 | 0 | $1.65 | — | python | ok |
| Secret Rotation Validator | default | opus48-1m-xhigh | 15.6min | 46 | 0 | $4.15 | — | python | ok |
| Secret Rotation Validator | powershell | opus48-1m-high | 15.4min | 53 | 0 | $3.46 | — | powershell | ok |
| Secret Rotation Validator | powershell | opus48-1m-medium | 1.1min | 11 | 0 | $0.55 | — | powershell | ok |
| Secret Rotation Validator | powershell | opus48-1m-xhigh | 19.5min | 60 | 0 | $5.52 | — | powershell | ok |
| Secret Rotation Validator | powershell-tool | opus48-1m-high | 15.2min | 33 | 0 | $3.22 | — | powershell | ok |
| Secret Rotation Validator | powershell-tool | opus48-1m-medium | 8.0min | 34 | 1 | $2.14 | — | powershell | ok |
| Secret Rotation Validator | powershell-tool | opus48-1m-xhigh | 26.1min | 78 | 0 | $7.45 | — | powershell | ok |
| Secret Rotation Validator | typescript-bun | opus48-1m-high | 11.9min | 45 | 1 | $3.29 | — | typescript | ok |
| Secret Rotation Validator | typescript-bun | opus48-1m-medium | 23.0min | 78 | 2 | $4.51 | — | typescript | ok |
| Secret Rotation Validator | typescript-bun | opus48-1m-xhigh | 17.5min | 54 | 0 | $5.12 | — | typescript | ok |
| Semantic Version Bumper | bash | opus48-1m-high | 9.5min | 41 | 1 | $2.70 | — | bash | ok |
| Semantic Version Bumper | bash | opus48-1m-medium | 6.8min | 22 | 0 | $1.55 | — | bash | ok |
| Semantic Version Bumper | bash | opus48-1m-ultracode | 20.8min | 74 | 0 | $6.09 | — | bash | ok |
| Semantic Version Bumper | bash | opus48-1m-xhigh | 18.1min | 47 | 2 | $4.91 | — | bash | ok |
| Semantic Version Bumper | default | opus48-1m-high | 9.8min | 52 | 0 | $3.34 | — | javascript | ok |
| Semantic Version Bumper | default | opus48-1m-medium | 7.2min | 27 | 0 | $1.83 | — | python | ok |
| Semantic Version Bumper | default | opus48-1m-ultracode | 14.6min | 43 | 0 | $4.35 | — | python | ok |
| Semantic Version Bumper | default | opus48-1m-xhigh | 15.3min | 50 | 1 | $4.59 | — | python | ok |
| Semantic Version Bumper | powershell | opus48-1m-high | 16.9min | 60 | 2 | $3.59 | — | powershell | ok |
| Semantic Version Bumper | powershell | opus48-1m-medium | 10.0min | 34 | 0 | $2.33 | — | powershell | ok |
| Semantic Version Bumper | powershell | opus48-1m-ultracode | 31.9min | 65 | 2 | $13.39 | — | powershell | ok |
| Semantic Version Bumper | powershell | opus48-1m-xhigh | 21.0min | 69 | 1 | $6.19 | — | powershell | ok |
| Semantic Version Bumper | powershell-tool | opus48-1m-high | 12.1min | 34 | 0 | $2.32 | — | powershell | ok |
| Semantic Version Bumper | powershell-tool | opus48-1m-medium | 10.6min | 40 | 1 | $2.39 | — | powershell | ok |
| Semantic Version Bumper | powershell-tool | opus48-1m-ultracode | 25.2min | 58 | 0 | $6.83 | — | powershell | ok |
| Semantic Version Bumper | powershell-tool | opus48-1m-xhigh | 21.0min | 61 | 1 | $5.56 | — | powershell | ok |
| Semantic Version Bumper | typescript-bun | opus48-1m-high | 11.5min | 52 | 0 | $3.14 | — | typescript | ok |
| Semantic Version Bumper | typescript-bun | opus48-1m-medium | 9.3min | 47 | 2 | $2.47 | — | typescript | ok |
| Semantic Version Bumper | typescript-bun | opus48-1m-ultracode | 30.6min | 104 | 0 | $11.91 | — | typescript | ok |
| Semantic Version Bumper | typescript-bun | opus48-1m-xhigh | 22.3min | 71 | 3 | $6.51 | — | typescript | ok |
| Test Results Aggregator | bash | opus48-1m-high | 8.4min | 28 | 0 | $2.20 | — | bash | ok |
| Test Results Aggregator | bash | opus48-1m-medium | 6.3min | 29 | 1 | $1.83 | — | bash | ok |
| Test Results Aggregator | bash | opus48-1m-xhigh | 21.2min | 53 | 3 | $5.41 | — | bash | ok |
| Test Results Aggregator | default | opus48-1m-high | 12.2min | 59 | 1 | $3.42 | — | python | ok |
| Test Results Aggregator | default | opus48-1m-medium | 6.6min | 26 | 0 | $1.50 | — | python | ok |
| Test Results Aggregator | default | opus48-1m-xhigh | 17.2min | 63 | 0 | $5.38 | — | python | ok |
| Test Results Aggregator | powershell | opus48-1m-high | 17.3min | 59 | 0 | $3.84 | — | powershell | ok |
| Test Results Aggregator | powershell | opus48-1m-medium | 8.1min | 30 | 0 | $1.77 | — | powershell | ok |
| Test Results Aggregator | powershell | opus48-1m-xhigh | 18.2min | 39 | 0 | $4.52 | — | powershell | ok |
| Test Results Aggregator | powershell-tool | opus48-1m-high | 15.2min | 47 | 0 | $3.39 | — | powershell | ok |
| Test Results Aggregator | powershell-tool | opus48-1m-medium | 7.4min | 29 | 0 | $1.95 | — | powershell | ok |
| Test Results Aggregator | powershell-tool | opus48-1m-xhigh | 25.9min | 67 | 2 | $6.67 | — | powershell | ok |
| Test Results Aggregator | typescript-bun | opus48-1m-high | 19.2min | 69 | 0 | $5.19 | — | typescript | ok |
| Test Results Aggregator | typescript-bun | opus48-1m-medium | 9.2min | 45 | 0 | $2.57 | — | typescript | ok |
| Test Results Aggregator | typescript-bun | opus48-1m-xhigh | 16.4min | 46 | 0 | $4.37 | — | typescript | ok |


<details>
<summary>Sorted by cost (cheapest first)</summary>

| Task | Language | Model | Duration | Turns | Errors | Cost | Tests Quality | Chosen | Status |
|------|----------|-------|----------|-------|--------|------|-----------|--------|--------|
| PR Label Assigner | powershell-tool | opus48-1m-xhigh | 30.0min | 0 | 0 | $0.00 | — | powershell | timeout |
| Dependency License Checker | powershell | opus48-1m-xhigh | 30.0min | 0 | 5 | $0.00 | — | powershell | timeout |
| Environment Matrix Generator | powershell-tool | opus48-1m-xhigh | 30.0min | 0 | 0 | $0.00 | — | powershell | timeout |
| Artifact Cleanup Script | powershell-tool | opus48-1m-xhigh | 30.0min | 0 | 1 | $0.00 | — | powershell | timeout |
| Secret Rotation Validator | powershell | opus48-1m-medium | 1.1min | 11 | 0 | $0.55 | — | powershell | ok |
| PR Label Assigner | typescript-bun | opus48-1m-high | 3.0min | 26 | 1 | $1.17 | — | typescript | ok |
| Dependency License Checker | powershell | opus48-1m-ultracode | 4.3min | 23 | 0 | $1.21 | — | powershell | ok |
| PR Label Assigner | bash | opus48-1m-medium | 4.8min | 20 | 0 | $1.22 | — | bash | ok |
| Dependency License Checker | bash | opus48-1m-medium | 5.7min | 24 | 0 | $1.45 | — | bash | ok |
| Test Results Aggregator | default | opus48-1m-medium | 6.6min | 26 | 0 | $1.50 | — | python | ok |
| PR Label Assigner | powershell | opus48-1m-medium | 6.3min | 23 | 0 | $1.52 | — | powershell | ok |
| Semantic Version Bumper | bash | opus48-1m-medium | 6.8min | 22 | 0 | $1.55 | — | bash | ok |
| Secret Rotation Validator | default | opus48-1m-medium | 5.9min | 29 | 0 | $1.65 | — | python | ok |
| PR Label Assigner | powershell-tool | opus48-1m-medium | 7.6min | 27 | 1 | $1.66 | — | powershell | ok |
| Environment Matrix Generator | bash | opus48-1m-medium | 5.8min | 27 | 0 | $1.72 | — | bash | ok |
| Test Results Aggregator | powershell | opus48-1m-medium | 8.1min | 30 | 0 | $1.77 | — | powershell | ok |
| Semantic Version Bumper | default | opus48-1m-medium | 7.2min | 27 | 0 | $1.83 | — | python | ok |
| Test Results Aggregator | bash | opus48-1m-medium | 6.3min | 29 | 1 | $1.83 | — | bash | ok |
| PR Label Assigner | default | opus48-1m-high | 7.1min | 25 | 1 | $1.86 | — | python | ok |
| PR Label Assigner | default | opus48-1m-medium | 8.2min | 36 | 1 | $1.91 | — | powershell | ok |
| Dependency License Checker | powershell | opus48-1m-medium | 7.7min | 33 | 0 | $1.93 | — | powershell | ok |
| Dependency License Checker | default | opus48-1m-medium | 7.9min | 33 | 0 | $1.94 | — | python | ok |
| Test Results Aggregator | powershell-tool | opus48-1m-medium | 7.4min | 29 | 0 | $1.95 | — | powershell | ok |
| Environment Matrix Generator | default | opus48-1m-medium | 6.7min | 28 | 0 | $2.01 | — | python | ok |
| Environment Matrix Generator | default | opus48-1m-high | 8.2min | 24 | 0 | $2.01 | — | python | ok |
| Secret Rotation Validator | powershell-tool | opus48-1m-medium | 8.0min | 34 | 1 | $2.14 | — | powershell | ok |
| Test Results Aggregator | bash | opus48-1m-high | 8.4min | 28 | 0 | $2.20 | — | bash | ok |
| Dependency License Checker | default | opus48-1m-high | 9.0min | 34 | 0 | $2.24 | — | powershell | ok |
| Artifact Cleanup Script | powershell | opus48-1m-medium | 9.3min | 28 | 0 | $2.26 | — | powershell | ok |
| Environment Matrix Generator | typescript-bun | opus48-1m-medium | 9.1min | 40 | 0 | $2.29 | — | typescript | ok |
| Environment Matrix Generator | powershell | opus48-1m-medium | 9.3min | 33 | 0 | $2.29 | — | powershell | ok |
| Semantic Version Bumper | powershell-tool | opus48-1m-high | 12.1min | 34 | 0 | $2.32 | — | powershell | ok |
| Dependency License Checker | typescript-bun | opus48-1m-medium | 8.7min | 45 | 0 | $2.33 | — | typescript | ok |
| Semantic Version Bumper | powershell | opus48-1m-medium | 10.0min | 34 | 0 | $2.33 | — | powershell | ok |
| Artifact Cleanup Script | default | opus48-1m-medium | 9.9min | 43 | 0 | $2.37 | — | powershell | ok |
| Secret Rotation Validator | bash | opus48-1m-high | 9.4min | 33 | 0 | $2.38 | — | bash | ok |
| Semantic Version Bumper | powershell-tool | opus48-1m-medium | 10.6min | 40 | 1 | $2.39 | — | powershell | ok |
| Artifact Cleanup Script | typescript-bun | opus48-1m-medium | 9.2min | 44 | 0 | $2.44 | — | typescript | ok |
| PR Label Assigner | bash | opus48-1m-high | 10.1min | 31 | 0 | $2.45 | — | bash | ok |
| Semantic Version Bumper | typescript-bun | opus48-1m-medium | 9.3min | 47 | 2 | $2.47 | — | typescript | ok |
| PR Label Assigner | typescript-bun | opus48-1m-medium | 13.1min | 44 | 0 | $2.48 | — | typescript | ok |
| Environment Matrix Generator | bash | opus48-1m-high | 9.4min | 39 | 1 | $2.51 | — | bash | ok |
| Test Results Aggregator | typescript-bun | opus48-1m-medium | 9.2min | 45 | 0 | $2.57 | — | typescript | ok |
| Artifact Cleanup Script | powershell | opus48-1m-high | 9.6min | 35 | 2 | $2.60 | — | powershell | ok |
| Dependency License Checker | powershell-tool | opus48-1m-high | 12.2min | 33 | 0 | $2.63 | — | powershell | ok |
| PR Label Assigner | powershell | opus48-1m-high | 11.0min | 47 | 0 | $2.65 | — | powershell | ok |
| PR Label Assigner | default | opus48-1m-xhigh | 9.8min | 29 | 0 | $2.66 | — | python | ok |
| Semantic Version Bumper | bash | opus48-1m-high | 9.5min | 41 | 1 | $2.70 | — | bash | ok |
| PR Label Assigner | powershell-tool | opus48-1m-high | 11.4min | 41 | 0 | $2.78 | — | powershell | ok |
| Artifact Cleanup Script | powershell-tool | opus48-1m-high | 11.8min | 31 | 1 | $2.83 | — | powershell | ok |
| Artifact Cleanup Script | powershell-tool | opus48-1m-medium | 11.9min | 46 | 1 | $2.91 | — | powershell | ok |
| Dependency License Checker | typescript-bun | opus48-1m-high | 11.5min | 47 | 0 | $3.04 | — | typescript | ok |
| Environment Matrix Generator | powershell-tool | opus48-1m-high | 9.2min | 27 | 0 | $3.06 | — | powershell | ok |
| Dependency License Checker | powershell | opus48-1m-high | 12.8min | 42 | 1 | $3.09 | — | powershell | ok |
| Secret Rotation Validator | default | opus48-1m-high | 9.1min | 47 | 0 | $3.12 | — | python | ok |
| Semantic Version Bumper | typescript-bun | opus48-1m-high | 11.5min | 52 | 0 | $3.14 | — | typescript | ok |
| Artifact Cleanup Script | bash | opus48-1m-medium | 11.4min | 53 | 1 | $3.16 | — | bash | ok |
| Artifact Cleanup Script | default | opus48-1m-high | 10.2min | 50 | 0 | $3.16 | — | python | ok |
| Secret Rotation Validator | powershell-tool | opus48-1m-high | 15.2min | 33 | 0 | $3.22 | — | powershell | ok |
| Secret Rotation Validator | typescript-bun | opus48-1m-high | 11.9min | 45 | 1 | $3.29 | — | typescript | ok |
| Artifact Cleanup Script | bash | opus48-1m-high | 11.6min | 47 | 0 | $3.32 | — | bash | ok |
| Semantic Version Bumper | default | opus48-1m-high | 9.8min | 52 | 0 | $3.34 | — | javascript | ok |
| Dependency License Checker | powershell-tool | opus48-1m-medium | 12.7min | 49 | 0 | $3.35 | — | powershell | ok |
| Test Results Aggregator | powershell-tool | opus48-1m-high | 15.2min | 47 | 0 | $3.39 | — | powershell | ok |
| Test Results Aggregator | default | opus48-1m-high | 12.2min | 59 | 1 | $3.42 | — | python | ok |
| Secret Rotation Validator | powershell | opus48-1m-high | 15.4min | 53 | 0 | $3.46 | — | powershell | ok |
| Environment Matrix Generator | powershell | opus48-1m-high | 13.7min | 44 | 1 | $3.48 | — | powershell | ok |
| Semantic Version Bumper | powershell | opus48-1m-high | 16.9min | 60 | 2 | $3.59 | — | powershell | ok |
| Environment Matrix Generator | powershell-tool | opus48-1m-medium | 12.9min | 52 | 2 | $3.60 | — | powershell | ok |
| Dependency License Checker | default | opus48-1m-xhigh | 13.6min | 34 | 0 | $3.67 | — | python | ok |
| Test Results Aggregator | powershell | opus48-1m-high | 17.3min | 59 | 0 | $3.84 | — | powershell | ok |
| Environment Matrix Generator | typescript-bun | opus48-1m-high | 13.3min | 69 | 0 | $3.94 | — | typescript | ok |
| Dependency License Checker | bash | opus48-1m-high | 15.0min | 51 | 3 | $4.02 | — | bash | ok |
| Environment Matrix Generator | default | opus48-1m-xhigh | 16.2min | 38 | 0 | $4.05 | — | python | ok |
| Secret Rotation Validator | default | opus48-1m-xhigh | 15.6min | 46 | 0 | $4.15 | — | python | ok |
| PR Label Assigner | default | opus48-1m-ultracode | 12.6min | 51 | 0 | $4.18 | — | python | ok |
| Semantic Version Bumper | default | opus48-1m-ultracode | 14.6min | 43 | 0 | $4.35 | — | python | ok |
| Test Results Aggregator | typescript-bun | opus48-1m-xhigh | 16.4min | 46 | 0 | $4.37 | — | typescript | ok |
| Secret Rotation Validator | typescript-bun | opus48-1m-medium | 23.0min | 78 | 2 | $4.51 | — | typescript | ok |
| Test Results Aggregator | powershell | opus48-1m-xhigh | 18.2min | 39 | 0 | $4.52 | — | powershell | ok |
| Semantic Version Bumper | default | opus48-1m-xhigh | 15.3min | 50 | 1 | $4.59 | — | python | ok |
| Semantic Version Bumper | bash | opus48-1m-xhigh | 18.1min | 47 | 2 | $4.91 | — | bash | ok |
| Artifact Cleanup Script | bash | opus48-1m-xhigh | 18.1min | 49 | 2 | $5.08 | — | bash | ok |
| Secret Rotation Validator | typescript-bun | opus48-1m-xhigh | 17.5min | 54 | 0 | $5.12 | — | typescript | ok |
| Dependency License Checker | typescript-bun | opus48-1m-xhigh | 19.6min | 48 | 0 | $5.16 | — | typescript | ok |
| Test Results Aggregator | typescript-bun | opus48-1m-high | 19.2min | 69 | 0 | $5.19 | — | typescript | ok |
| PR Label Assigner | bash | opus48-1m-ultracode | 18.6min | 55 | 2 | $5.24 | — | bash | ok |
| Test Results Aggregator | default | opus48-1m-xhigh | 17.2min | 63 | 0 | $5.38 | — | python | ok |
| Test Results Aggregator | bash | opus48-1m-xhigh | 21.2min | 53 | 3 | $5.41 | — | bash | ok |
| Secret Rotation Validator | bash | opus48-1m-xhigh | 21.4min | 55 | 0 | $5.41 | — | bash | ok |
| Dependency License Checker | default | opus48-1m-ultracode | 21.3min | 67 | 0 | $5.41 | — | powershell | ok |
| Environment Matrix Generator | bash | opus48-1m-xhigh | 18.6min | 59 | 0 | $5.52 | — | bash | ok |
| Secret Rotation Validator | powershell | opus48-1m-xhigh | 19.5min | 60 | 0 | $5.52 | — | powershell | ok |
| PR Label Assigner | powershell-tool | opus48-1m-ultracode | 22.3min | 50 | 1 | $5.54 | — | powershell | ok |
| Semantic Version Bumper | powershell-tool | opus48-1m-xhigh | 21.0min | 61 | 1 | $5.56 | — | powershell | ok |
| PR Label Assigner | powershell | opus48-1m-xhigh | 19.4min | 63 | 0 | $5.67 | — | powershell | ok |
| PR Label Assigner | powershell | opus48-1m-ultracode | 21.3min | 52 | 0 | $5.68 | — | powershell | ok |
| Secret Rotation Validator | bash | opus48-1m-medium | 23.9min | 64 | 6 | $5.71 | — | bash | ok |
| PR Label Assigner | typescript-bun | opus48-1m-ultracode | 21.5min | 62 | 5 | $5.80 | — | typescript | ok |
| PR Label Assigner | bash | opus48-1m-xhigh | 20.5min | 64 | 0 | $5.87 | — | bash | ok |
| Artifact Cleanup Script | typescript-bun | opus48-1m-xhigh | 21.6min | 49 | 2 | $5.91 | — | typescript | ok |
| Artifact Cleanup Script | typescript-bun | opus48-1m-high | 14.8min | 82 | 1 | $6.00 | — | typescript | ok |
| PR Label Assigner | typescript-bun | opus48-1m-xhigh | 19.8min | 72 | 0 | $6.01 | — | typescript | ok |
| Semantic Version Bumper | bash | opus48-1m-ultracode | 20.8min | 74 | 0 | $6.09 | — | bash | ok |
| Semantic Version Bumper | powershell | opus48-1m-xhigh | 21.0min | 69 | 1 | $6.19 | — | powershell | ok |
| Dependency License Checker | powershell-tool | opus48-1m-xhigh | 25.2min | 49 | 0 | $6.38 | — | powershell | ok |
| Semantic Version Bumper | typescript-bun | opus48-1m-xhigh | 22.3min | 71 | 3 | $6.51 | — | typescript | ok |
| Test Results Aggregator | powershell-tool | opus48-1m-xhigh | 25.9min | 67 | 2 | $6.67 | — | powershell | ok |
| Semantic Version Bumper | powershell-tool | opus48-1m-ultracode | 25.2min | 58 | 0 | $6.83 | — | powershell | ok |
| Artifact Cleanup Script | default | opus48-1m-xhigh | 19.1min | 77 | 0 | $6.84 | — | python | ok |
| Environment Matrix Generator | powershell | opus48-1m-xhigh | 28.4min | 58 | 0 | $7.16 | — | powershell | ok |
| Environment Matrix Generator | typescript-bun | opus48-1m-xhigh | 25.3min | 77 | 1 | $7.25 | — | typescript | ok |
| Artifact Cleanup Script | powershell | opus48-1m-xhigh | 25.0min | 92 | 1 | $7.41 | — | powershell | ok |
| Secret Rotation Validator | powershell-tool | opus48-1m-xhigh | 26.1min | 78 | 0 | $7.45 | — | powershell | ok |
| Dependency License Checker | bash | opus48-1m-xhigh | 23.9min | 96 | 2 | $8.01 | — | bash | ok |
| Semantic Version Bumper | typescript-bun | opus48-1m-ultracode | 30.6min | 104 | 0 | $11.91 | — | typescript | ok |
| Semantic Version Bumper | powershell | opus48-1m-ultracode | 31.9min | 65 | 2 | $13.39 | — | powershell | ok |

</details>

<details>
<summary>Sorted by duration (fastest first)</summary>

| Task | Language | Model | Duration | Turns | Errors | Cost | Tests Quality | Chosen | Status |
|------|----------|-------|----------|-------|--------|------|-----------|--------|--------|
| Secret Rotation Validator | powershell | opus48-1m-medium | 1.1min | 11 | 0 | $0.55 | — | powershell | ok |
| PR Label Assigner | typescript-bun | opus48-1m-high | 3.0min | 26 | 1 | $1.17 | — | typescript | ok |
| Dependency License Checker | powershell | opus48-1m-ultracode | 4.3min | 23 | 0 | $1.21 | — | powershell | ok |
| PR Label Assigner | bash | opus48-1m-medium | 4.8min | 20 | 0 | $1.22 | — | bash | ok |
| Dependency License Checker | bash | opus48-1m-medium | 5.7min | 24 | 0 | $1.45 | — | bash | ok |
| Environment Matrix Generator | bash | opus48-1m-medium | 5.8min | 27 | 0 | $1.72 | — | bash | ok |
| Secret Rotation Validator | default | opus48-1m-medium | 5.9min | 29 | 0 | $1.65 | — | python | ok |
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
| Secret Rotation Validator | powershell-tool | opus48-1m-medium | 8.0min | 34 | 1 | $2.14 | — | powershell | ok |
| Test Results Aggregator | powershell | opus48-1m-medium | 8.1min | 30 | 0 | $1.77 | — | powershell | ok |
| PR Label Assigner | default | opus48-1m-medium | 8.2min | 36 | 1 | $1.91 | — | powershell | ok |
| Environment Matrix Generator | default | opus48-1m-high | 8.2min | 24 | 0 | $2.01 | — | python | ok |
| Test Results Aggregator | bash | opus48-1m-high | 8.4min | 28 | 0 | $2.20 | — | bash | ok |
| Dependency License Checker | typescript-bun | opus48-1m-medium | 8.7min | 45 | 0 | $2.33 | — | typescript | ok |
| Dependency License Checker | default | opus48-1m-high | 9.0min | 34 | 0 | $2.24 | — | powershell | ok |
| Secret Rotation Validator | default | opus48-1m-high | 9.1min | 47 | 0 | $3.12 | — | python | ok |
| Environment Matrix Generator | typescript-bun | opus48-1m-medium | 9.1min | 40 | 0 | $2.29 | — | typescript | ok |
| Environment Matrix Generator | powershell-tool | opus48-1m-high | 9.2min | 27 | 0 | $3.06 | — | powershell | ok |
| Artifact Cleanup Script | typescript-bun | opus48-1m-medium | 9.2min | 44 | 0 | $2.44 | — | typescript | ok |
| Test Results Aggregator | typescript-bun | opus48-1m-medium | 9.2min | 45 | 0 | $2.57 | — | typescript | ok |
| Artifact Cleanup Script | powershell | opus48-1m-medium | 9.3min | 28 | 0 | $2.26 | — | powershell | ok |
| Semantic Version Bumper | typescript-bun | opus48-1m-medium | 9.3min | 47 | 2 | $2.47 | — | typescript | ok |
| Environment Matrix Generator | powershell | opus48-1m-medium | 9.3min | 33 | 0 | $2.29 | — | powershell | ok |
| Secret Rotation Validator | bash | opus48-1m-high | 9.4min | 33 | 0 | $2.38 | — | bash | ok |
| Environment Matrix Generator | bash | opus48-1m-high | 9.4min | 39 | 1 | $2.51 | — | bash | ok |
| Semantic Version Bumper | bash | opus48-1m-high | 9.5min | 41 | 1 | $2.70 | — | bash | ok |
| Artifact Cleanup Script | powershell | opus48-1m-high | 9.6min | 35 | 2 | $2.60 | — | powershell | ok |
| Semantic Version Bumper | default | opus48-1m-high | 9.8min | 52 | 0 | $3.34 | — | javascript | ok |
| PR Label Assigner | default | opus48-1m-xhigh | 9.8min | 29 | 0 | $2.66 | — | python | ok |
| Artifact Cleanup Script | default | opus48-1m-medium | 9.9min | 43 | 0 | $2.37 | — | powershell | ok |
| Semantic Version Bumper | powershell | opus48-1m-medium | 10.0min | 34 | 0 | $2.33 | — | powershell | ok |
| PR Label Assigner | bash | opus48-1m-high | 10.1min | 31 | 0 | $2.45 | — | bash | ok |
| Artifact Cleanup Script | default | opus48-1m-high | 10.2min | 50 | 0 | $3.16 | — | python | ok |
| Semantic Version Bumper | powershell-tool | opus48-1m-medium | 10.6min | 40 | 1 | $2.39 | — | powershell | ok |
| PR Label Assigner | powershell | opus48-1m-high | 11.0min | 47 | 0 | $2.65 | — | powershell | ok |
| Artifact Cleanup Script | bash | opus48-1m-medium | 11.4min | 53 | 1 | $3.16 | — | bash | ok |
| PR Label Assigner | powershell-tool | opus48-1m-high | 11.4min | 41 | 0 | $2.78 | — | powershell | ok |
| Semantic Version Bumper | typescript-bun | opus48-1m-high | 11.5min | 52 | 0 | $3.14 | — | typescript | ok |
| Dependency License Checker | typescript-bun | opus48-1m-high | 11.5min | 47 | 0 | $3.04 | — | typescript | ok |
| Artifact Cleanup Script | bash | opus48-1m-high | 11.6min | 47 | 0 | $3.32 | — | bash | ok |
| Artifact Cleanup Script | powershell-tool | opus48-1m-high | 11.8min | 31 | 1 | $2.83 | — | powershell | ok |
| Artifact Cleanup Script | powershell-tool | opus48-1m-medium | 11.9min | 46 | 1 | $2.91 | — | powershell | ok |
| Secret Rotation Validator | typescript-bun | opus48-1m-high | 11.9min | 45 | 1 | $3.29 | — | typescript | ok |
| Semantic Version Bumper | powershell-tool | opus48-1m-high | 12.1min | 34 | 0 | $2.32 | — | powershell | ok |
| Dependency License Checker | powershell-tool | opus48-1m-high | 12.2min | 33 | 0 | $2.63 | — | powershell | ok |
| Test Results Aggregator | default | opus48-1m-high | 12.2min | 59 | 1 | $3.42 | — | python | ok |
| PR Label Assigner | default | opus48-1m-ultracode | 12.6min | 51 | 0 | $4.18 | — | python | ok |
| Dependency License Checker | powershell-tool | opus48-1m-medium | 12.7min | 49 | 0 | $3.35 | — | powershell | ok |
| Dependency License Checker | powershell | opus48-1m-high | 12.8min | 42 | 1 | $3.09 | — | powershell | ok |
| Environment Matrix Generator | powershell-tool | opus48-1m-medium | 12.9min | 52 | 2 | $3.60 | — | powershell | ok |
| PR Label Assigner | typescript-bun | opus48-1m-medium | 13.1min | 44 | 0 | $2.48 | — | typescript | ok |
| Environment Matrix Generator | typescript-bun | opus48-1m-high | 13.3min | 69 | 0 | $3.94 | — | typescript | ok |
| Dependency License Checker | default | opus48-1m-xhigh | 13.6min | 34 | 0 | $3.67 | — | python | ok |
| Environment Matrix Generator | powershell | opus48-1m-high | 13.7min | 44 | 1 | $3.48 | — | powershell | ok |
| Semantic Version Bumper | default | opus48-1m-ultracode | 14.6min | 43 | 0 | $4.35 | — | python | ok |
| Artifact Cleanup Script | typescript-bun | opus48-1m-high | 14.8min | 82 | 1 | $6.00 | — | typescript | ok |
| Dependency License Checker | bash | opus48-1m-high | 15.0min | 51 | 3 | $4.02 | — | bash | ok |
| Test Results Aggregator | powershell-tool | opus48-1m-high | 15.2min | 47 | 0 | $3.39 | — | powershell | ok |
| Secret Rotation Validator | powershell-tool | opus48-1m-high | 15.2min | 33 | 0 | $3.22 | — | powershell | ok |
| Semantic Version Bumper | default | opus48-1m-xhigh | 15.3min | 50 | 1 | $4.59 | — | python | ok |
| Secret Rotation Validator | powershell | opus48-1m-high | 15.4min | 53 | 0 | $3.46 | — | powershell | ok |
| Secret Rotation Validator | default | opus48-1m-xhigh | 15.6min | 46 | 0 | $4.15 | — | python | ok |
| Environment Matrix Generator | default | opus48-1m-xhigh | 16.2min | 38 | 0 | $4.05 | — | python | ok |
| Test Results Aggregator | typescript-bun | opus48-1m-xhigh | 16.4min | 46 | 0 | $4.37 | — | typescript | ok |
| Semantic Version Bumper | powershell | opus48-1m-high | 16.9min | 60 | 2 | $3.59 | — | powershell | ok |
| Test Results Aggregator | default | opus48-1m-xhigh | 17.2min | 63 | 0 | $5.38 | — | python | ok |
| Test Results Aggregator | powershell | opus48-1m-high | 17.3min | 59 | 0 | $3.84 | — | powershell | ok |
| Secret Rotation Validator | typescript-bun | opus48-1m-xhigh | 17.5min | 54 | 0 | $5.12 | — | typescript | ok |
| Artifact Cleanup Script | bash | opus48-1m-xhigh | 18.1min | 49 | 2 | $5.08 | — | bash | ok |
| Semantic Version Bumper | bash | opus48-1m-xhigh | 18.1min | 47 | 2 | $4.91 | — | bash | ok |
| Test Results Aggregator | powershell | opus48-1m-xhigh | 18.2min | 39 | 0 | $4.52 | — | powershell | ok |
| PR Label Assigner | bash | opus48-1m-ultracode | 18.6min | 55 | 2 | $5.24 | — | bash | ok |
| Environment Matrix Generator | bash | opus48-1m-xhigh | 18.6min | 59 | 0 | $5.52 | — | bash | ok |
| Artifact Cleanup Script | default | opus48-1m-xhigh | 19.1min | 77 | 0 | $6.84 | — | python | ok |
| Test Results Aggregator | typescript-bun | opus48-1m-high | 19.2min | 69 | 0 | $5.19 | — | typescript | ok |
| PR Label Assigner | powershell | opus48-1m-xhigh | 19.4min | 63 | 0 | $5.67 | — | powershell | ok |
| Secret Rotation Validator | powershell | opus48-1m-xhigh | 19.5min | 60 | 0 | $5.52 | — | powershell | ok |
| Dependency License Checker | typescript-bun | opus48-1m-xhigh | 19.6min | 48 | 0 | $5.16 | — | typescript | ok |
| PR Label Assigner | typescript-bun | opus48-1m-xhigh | 19.8min | 72 | 0 | $6.01 | — | typescript | ok |
| PR Label Assigner | bash | opus48-1m-xhigh | 20.5min | 64 | 0 | $5.87 | — | bash | ok |
| Semantic Version Bumper | bash | opus48-1m-ultracode | 20.8min | 74 | 0 | $6.09 | — | bash | ok |
| Semantic Version Bumper | powershell | opus48-1m-xhigh | 21.0min | 69 | 1 | $6.19 | — | powershell | ok |
| Semantic Version Bumper | powershell-tool | opus48-1m-xhigh | 21.0min | 61 | 1 | $5.56 | — | powershell | ok |
| Test Results Aggregator | bash | opus48-1m-xhigh | 21.2min | 53 | 3 | $5.41 | — | bash | ok |
| PR Label Assigner | powershell | opus48-1m-ultracode | 21.3min | 52 | 0 | $5.68 | — | powershell | ok |
| Dependency License Checker | default | opus48-1m-ultracode | 21.3min | 67 | 0 | $5.41 | — | powershell | ok |
| Secret Rotation Validator | bash | opus48-1m-xhigh | 21.4min | 55 | 0 | $5.41 | — | bash | ok |
| PR Label Assigner | typescript-bun | opus48-1m-ultracode | 21.5min | 62 | 5 | $5.80 | — | typescript | ok |
| Artifact Cleanup Script | typescript-bun | opus48-1m-xhigh | 21.6min | 49 | 2 | $5.91 | — | typescript | ok |
| Semantic Version Bumper | typescript-bun | opus48-1m-xhigh | 22.3min | 71 | 3 | $6.51 | — | typescript | ok |
| PR Label Assigner | powershell-tool | opus48-1m-ultracode | 22.3min | 50 | 1 | $5.54 | — | powershell | ok |
| Secret Rotation Validator | typescript-bun | opus48-1m-medium | 23.0min | 78 | 2 | $4.51 | — | typescript | ok |
| Secret Rotation Validator | bash | opus48-1m-medium | 23.9min | 64 | 6 | $5.71 | — | bash | ok |
| Dependency License Checker | bash | opus48-1m-xhigh | 23.9min | 96 | 2 | $8.01 | — | bash | ok |
| Artifact Cleanup Script | powershell | opus48-1m-xhigh | 25.0min | 92 | 1 | $7.41 | — | powershell | ok |
| Semantic Version Bumper | powershell-tool | opus48-1m-ultracode | 25.2min | 58 | 0 | $6.83 | — | powershell | ok |
| Dependency License Checker | powershell-tool | opus48-1m-xhigh | 25.2min | 49 | 0 | $6.38 | — | powershell | ok |
| Environment Matrix Generator | typescript-bun | opus48-1m-xhigh | 25.3min | 77 | 1 | $7.25 | — | typescript | ok |
| Test Results Aggregator | powershell-tool | opus48-1m-xhigh | 25.9min | 67 | 2 | $6.67 | — | powershell | ok |
| Secret Rotation Validator | powershell-tool | opus48-1m-xhigh | 26.1min | 78 | 0 | $7.45 | — | powershell | ok |
| Environment Matrix Generator | powershell | opus48-1m-xhigh | 28.4min | 58 | 0 | $7.16 | — | powershell | ok |
| Artifact Cleanup Script | powershell-tool | opus48-1m-xhigh | 30.0min | 0 | 1 | $0.00 | — | powershell | timeout |
| Dependency License Checker | powershell | opus48-1m-xhigh | 30.0min | 0 | 5 | $0.00 | — | powershell | timeout |
| PR Label Assigner | powershell-tool | opus48-1m-xhigh | 30.0min | 0 | 0 | $0.00 | — | powershell | timeout |
| Environment Matrix Generator | powershell-tool | opus48-1m-xhigh | 30.0min | 0 | 0 | $0.00 | — | powershell | timeout |
| Semantic Version Bumper | typescript-bun | opus48-1m-ultracode | 30.6min | 104 | 0 | $11.91 | — | typescript | ok |
| Semantic Version Bumper | powershell | opus48-1m-ultracode | 31.9min | 65 | 2 | $13.39 | — | powershell | ok |

</details>

<details>
<summary>Sorted by errors (fewest first)</summary>

| Task | Language | Model | Duration | Turns | Errors | Cost | Tests Quality | Chosen | Status |
|------|----------|-------|----------|-------|--------|------|-----------|--------|--------|
| Semantic Version Bumper | bash | opus48-1m-medium | 6.8min | 22 | 0 | $1.55 | — | bash | ok |
| Semantic Version Bumper | bash | opus48-1m-ultracode | 20.8min | 74 | 0 | $6.09 | — | bash | ok |
| Semantic Version Bumper | default | opus48-1m-high | 9.8min | 52 | 0 | $3.34 | — | javascript | ok |
| Semantic Version Bumper | default | opus48-1m-medium | 7.2min | 27 | 0 | $1.83 | — | python | ok |
| Semantic Version Bumper | default | opus48-1m-ultracode | 14.6min | 43 | 0 | $4.35 | — | python | ok |
| Semantic Version Bumper | powershell | opus48-1m-medium | 10.0min | 34 | 0 | $2.33 | — | powershell | ok |
| Semantic Version Bumper | powershell-tool | opus48-1m-high | 12.1min | 34 | 0 | $2.32 | — | powershell | ok |
| Semantic Version Bumper | powershell-tool | opus48-1m-ultracode | 25.2min | 58 | 0 | $6.83 | — | powershell | ok |
| Semantic Version Bumper | typescript-bun | opus48-1m-high | 11.5min | 52 | 0 | $3.14 | — | typescript | ok |
| Semantic Version Bumper | typescript-bun | opus48-1m-ultracode | 30.6min | 104 | 0 | $11.91 | — | typescript | ok |
| PR Label Assigner | bash | opus48-1m-high | 10.1min | 31 | 0 | $2.45 | — | bash | ok |
| PR Label Assigner | bash | opus48-1m-medium | 4.8min | 20 | 0 | $1.22 | — | bash | ok |
| PR Label Assigner | bash | opus48-1m-xhigh | 20.5min | 64 | 0 | $5.87 | — | bash | ok |
| PR Label Assigner | default | opus48-1m-ultracode | 12.6min | 51 | 0 | $4.18 | — | python | ok |
| PR Label Assigner | default | opus48-1m-xhigh | 9.8min | 29 | 0 | $2.66 | — | python | ok |
| PR Label Assigner | powershell | opus48-1m-high | 11.0min | 47 | 0 | $2.65 | — | powershell | ok |
| PR Label Assigner | powershell | opus48-1m-medium | 6.3min | 23 | 0 | $1.52 | — | powershell | ok |
| PR Label Assigner | powershell | opus48-1m-ultracode | 21.3min | 52 | 0 | $5.68 | — | powershell | ok |
| PR Label Assigner | powershell | opus48-1m-xhigh | 19.4min | 63 | 0 | $5.67 | — | powershell | ok |
| PR Label Assigner | powershell-tool | opus48-1m-high | 11.4min | 41 | 0 | $2.78 | — | powershell | ok |
| PR Label Assigner | powershell-tool | opus48-1m-xhigh | 30.0min | 0 | 0 | $0.00 | — | powershell | timeout |
| PR Label Assigner | typescript-bun | opus48-1m-medium | 13.1min | 44 | 0 | $2.48 | — | typescript | ok |
| PR Label Assigner | typescript-bun | opus48-1m-xhigh | 19.8min | 72 | 0 | $6.01 | — | typescript | ok |
| Dependency License Checker | bash | opus48-1m-medium | 5.7min | 24 | 0 | $1.45 | — | bash | ok |
| Dependency License Checker | default | opus48-1m-high | 9.0min | 34 | 0 | $2.24 | — | powershell | ok |
| Dependency License Checker | default | opus48-1m-medium | 7.9min | 33 | 0 | $1.94 | — | python | ok |
| Dependency License Checker | default | opus48-1m-ultracode | 21.3min | 67 | 0 | $5.41 | — | powershell | ok |
| Dependency License Checker | default | opus48-1m-xhigh | 13.6min | 34 | 0 | $3.67 | — | python | ok |
| Dependency License Checker | powershell | opus48-1m-medium | 7.7min | 33 | 0 | $1.93 | — | powershell | ok |
| Dependency License Checker | powershell-tool | opus48-1m-high | 12.2min | 33 | 0 | $2.63 | — | powershell | ok |
| Dependency License Checker | powershell-tool | opus48-1m-medium | 12.7min | 49 | 0 | $3.35 | — | powershell | ok |
| Dependency License Checker | powershell-tool | opus48-1m-xhigh | 25.2min | 49 | 0 | $6.38 | — | powershell | ok |
| Dependency License Checker | typescript-bun | opus48-1m-high | 11.5min | 47 | 0 | $3.04 | — | typescript | ok |
| Dependency License Checker | typescript-bun | opus48-1m-medium | 8.7min | 45 | 0 | $2.33 | — | typescript | ok |
| Dependency License Checker | typescript-bun | opus48-1m-xhigh | 19.6min | 48 | 0 | $5.16 | — | typescript | ok |
| Test Results Aggregator | bash | opus48-1m-high | 8.4min | 28 | 0 | $2.20 | — | bash | ok |
| Test Results Aggregator | default | opus48-1m-medium | 6.6min | 26 | 0 | $1.50 | — | python | ok |
| Test Results Aggregator | default | opus48-1m-xhigh | 17.2min | 63 | 0 | $5.38 | — | python | ok |
| Test Results Aggregator | powershell | opus48-1m-high | 17.3min | 59 | 0 | $3.84 | — | powershell | ok |
| Test Results Aggregator | powershell | opus48-1m-medium | 8.1min | 30 | 0 | $1.77 | — | powershell | ok |
| Test Results Aggregator | powershell | opus48-1m-xhigh | 18.2min | 39 | 0 | $4.52 | — | powershell | ok |
| Test Results Aggregator | powershell-tool | opus48-1m-high | 15.2min | 47 | 0 | $3.39 | — | powershell | ok |
| Test Results Aggregator | powershell-tool | opus48-1m-medium | 7.4min | 29 | 0 | $1.95 | — | powershell | ok |
| Test Results Aggregator | typescript-bun | opus48-1m-high | 19.2min | 69 | 0 | $5.19 | — | typescript | ok |
| Test Results Aggregator | typescript-bun | opus48-1m-medium | 9.2min | 45 | 0 | $2.57 | — | typescript | ok |
| Test Results Aggregator | typescript-bun | opus48-1m-xhigh | 16.4min | 46 | 0 | $4.37 | — | typescript | ok |
| Environment Matrix Generator | bash | opus48-1m-medium | 5.8min | 27 | 0 | $1.72 | — | bash | ok |
| Environment Matrix Generator | bash | opus48-1m-xhigh | 18.6min | 59 | 0 | $5.52 | — | bash | ok |
| Environment Matrix Generator | default | opus48-1m-high | 8.2min | 24 | 0 | $2.01 | — | python | ok |
| Environment Matrix Generator | default | opus48-1m-medium | 6.7min | 28 | 0 | $2.01 | — | python | ok |
| Environment Matrix Generator | default | opus48-1m-xhigh | 16.2min | 38 | 0 | $4.05 | — | python | ok |
| Environment Matrix Generator | powershell | opus48-1m-medium | 9.3min | 33 | 0 | $2.29 | — | powershell | ok |
| Environment Matrix Generator | powershell | opus48-1m-xhigh | 28.4min | 58 | 0 | $7.16 | — | powershell | ok |
| Environment Matrix Generator | powershell-tool | opus48-1m-high | 9.2min | 27 | 0 | $3.06 | — | powershell | ok |
| Environment Matrix Generator | powershell-tool | opus48-1m-xhigh | 30.0min | 0 | 0 | $0.00 | — | powershell | timeout |
| Environment Matrix Generator | typescript-bun | opus48-1m-high | 13.3min | 69 | 0 | $3.94 | — | typescript | ok |
| Environment Matrix Generator | typescript-bun | opus48-1m-medium | 9.1min | 40 | 0 | $2.29 | — | typescript | ok |
| Artifact Cleanup Script | bash | opus48-1m-high | 11.6min | 47 | 0 | $3.32 | — | bash | ok |
| Artifact Cleanup Script | default | opus48-1m-high | 10.2min | 50 | 0 | $3.16 | — | python | ok |
| Artifact Cleanup Script | default | opus48-1m-medium | 9.9min | 43 | 0 | $2.37 | — | powershell | ok |
| Artifact Cleanup Script | default | opus48-1m-xhigh | 19.1min | 77 | 0 | $6.84 | — | python | ok |
| Artifact Cleanup Script | powershell | opus48-1m-medium | 9.3min | 28 | 0 | $2.26 | — | powershell | ok |
| Artifact Cleanup Script | typescript-bun | opus48-1m-medium | 9.2min | 44 | 0 | $2.44 | — | typescript | ok |
| Secret Rotation Validator | bash | opus48-1m-high | 9.4min | 33 | 0 | $2.38 | — | bash | ok |
| Secret Rotation Validator | bash | opus48-1m-xhigh | 21.4min | 55 | 0 | $5.41 | — | bash | ok |
| Secret Rotation Validator | default | opus48-1m-high | 9.1min | 47 | 0 | $3.12 | — | python | ok |
| Secret Rotation Validator | default | opus48-1m-medium | 5.9min | 29 | 0 | $1.65 | — | python | ok |
| Secret Rotation Validator | default | opus48-1m-xhigh | 15.6min | 46 | 0 | $4.15 | — | python | ok |
| Secret Rotation Validator | powershell | opus48-1m-high | 15.4min | 53 | 0 | $3.46 | — | powershell | ok |
| Secret Rotation Validator | powershell | opus48-1m-medium | 1.1min | 11 | 0 | $0.55 | — | powershell | ok |
| Secret Rotation Validator | powershell | opus48-1m-xhigh | 19.5min | 60 | 0 | $5.52 | — | powershell | ok |
| Secret Rotation Validator | powershell-tool | opus48-1m-high | 15.2min | 33 | 0 | $3.22 | — | powershell | ok |
| Secret Rotation Validator | powershell-tool | opus48-1m-xhigh | 26.1min | 78 | 0 | $7.45 | — | powershell | ok |
| Secret Rotation Validator | typescript-bun | opus48-1m-xhigh | 17.5min | 54 | 0 | $5.12 | — | typescript | ok |
| Dependency License Checker | powershell | opus48-1m-ultracode | 4.3min | 23 | 0 | $1.21 | — | powershell | ok |
| Semantic Version Bumper | bash | opus48-1m-high | 9.5min | 41 | 1 | $2.70 | — | bash | ok |
| Semantic Version Bumper | default | opus48-1m-xhigh | 15.3min | 50 | 1 | $4.59 | — | python | ok |
| Semantic Version Bumper | powershell | opus48-1m-xhigh | 21.0min | 69 | 1 | $6.19 | — | powershell | ok |
| Semantic Version Bumper | powershell-tool | opus48-1m-medium | 10.6min | 40 | 1 | $2.39 | — | powershell | ok |
| Semantic Version Bumper | powershell-tool | opus48-1m-xhigh | 21.0min | 61 | 1 | $5.56 | — | powershell | ok |
| PR Label Assigner | default | opus48-1m-high | 7.1min | 25 | 1 | $1.86 | — | python | ok |
| PR Label Assigner | default | opus48-1m-medium | 8.2min | 36 | 1 | $1.91 | — | powershell | ok |
| PR Label Assigner | powershell-tool | opus48-1m-medium | 7.6min | 27 | 1 | $1.66 | — | powershell | ok |
| PR Label Assigner | powershell-tool | opus48-1m-ultracode | 22.3min | 50 | 1 | $5.54 | — | powershell | ok |
| PR Label Assigner | typescript-bun | opus48-1m-high | 3.0min | 26 | 1 | $1.17 | — | typescript | ok |
| Dependency License Checker | powershell | opus48-1m-high | 12.8min | 42 | 1 | $3.09 | — | powershell | ok |
| Test Results Aggregator | bash | opus48-1m-medium | 6.3min | 29 | 1 | $1.83 | — | bash | ok |
| Test Results Aggregator | default | opus48-1m-high | 12.2min | 59 | 1 | $3.42 | — | python | ok |
| Environment Matrix Generator | bash | opus48-1m-high | 9.4min | 39 | 1 | $2.51 | — | bash | ok |
| Environment Matrix Generator | powershell | opus48-1m-high | 13.7min | 44 | 1 | $3.48 | — | powershell | ok |
| Environment Matrix Generator | typescript-bun | opus48-1m-xhigh | 25.3min | 77 | 1 | $7.25 | — | typescript | ok |
| Artifact Cleanup Script | bash | opus48-1m-medium | 11.4min | 53 | 1 | $3.16 | — | bash | ok |
| Artifact Cleanup Script | powershell | opus48-1m-xhigh | 25.0min | 92 | 1 | $7.41 | — | powershell | ok |
| Artifact Cleanup Script | powershell-tool | opus48-1m-high | 11.8min | 31 | 1 | $2.83 | — | powershell | ok |
| Artifact Cleanup Script | powershell-tool | opus48-1m-medium | 11.9min | 46 | 1 | $2.91 | — | powershell | ok |
| Artifact Cleanup Script | powershell-tool | opus48-1m-xhigh | 30.0min | 0 | 1 | $0.00 | — | powershell | timeout |
| Artifact Cleanup Script | typescript-bun | opus48-1m-high | 14.8min | 82 | 1 | $6.00 | — | typescript | ok |
| Secret Rotation Validator | powershell-tool | opus48-1m-medium | 8.0min | 34 | 1 | $2.14 | — | powershell | ok |
| Secret Rotation Validator | typescript-bun | opus48-1m-high | 11.9min | 45 | 1 | $3.29 | — | typescript | ok |
| Semantic Version Bumper | bash | opus48-1m-xhigh | 18.1min | 47 | 2 | $4.91 | — | bash | ok |
| Semantic Version Bumper | powershell | opus48-1m-high | 16.9min | 60 | 2 | $3.59 | — | powershell | ok |
| Semantic Version Bumper | powershell | opus48-1m-ultracode | 31.9min | 65 | 2 | $13.39 | — | powershell | ok |
| Semantic Version Bumper | typescript-bun | opus48-1m-medium | 9.3min | 47 | 2 | $2.47 | — | typescript | ok |
| PR Label Assigner | bash | opus48-1m-ultracode | 18.6min | 55 | 2 | $5.24 | — | bash | ok |
| Dependency License Checker | bash | opus48-1m-xhigh | 23.9min | 96 | 2 | $8.01 | — | bash | ok |
| Test Results Aggregator | powershell-tool | opus48-1m-xhigh | 25.9min | 67 | 2 | $6.67 | — | powershell | ok |
| Environment Matrix Generator | powershell-tool | opus48-1m-medium | 12.9min | 52 | 2 | $3.60 | — | powershell | ok |
| Artifact Cleanup Script | bash | opus48-1m-xhigh | 18.1min | 49 | 2 | $5.08 | — | bash | ok |
| Artifact Cleanup Script | powershell | opus48-1m-high | 9.6min | 35 | 2 | $2.60 | — | powershell | ok |
| Artifact Cleanup Script | typescript-bun | opus48-1m-xhigh | 21.6min | 49 | 2 | $5.91 | — | typescript | ok |
| Secret Rotation Validator | typescript-bun | opus48-1m-medium | 23.0min | 78 | 2 | $4.51 | — | typescript | ok |
| Semantic Version Bumper | typescript-bun | opus48-1m-xhigh | 22.3min | 71 | 3 | $6.51 | — | typescript | ok |
| Dependency License Checker | bash | opus48-1m-high | 15.0min | 51 | 3 | $4.02 | — | bash | ok |
| Test Results Aggregator | bash | opus48-1m-xhigh | 21.2min | 53 | 3 | $5.41 | — | bash | ok |
| PR Label Assigner | typescript-bun | opus48-1m-ultracode | 21.5min | 62 | 5 | $5.80 | — | typescript | ok |
| Dependency License Checker | powershell | opus48-1m-xhigh | 30.0min | 0 | 5 | $0.00 | — | powershell | timeout |
| Secret Rotation Validator | bash | opus48-1m-medium | 23.9min | 64 | 6 | $5.71 | — | bash | ok |

</details>

<details>
<summary>Sorted by turns (fewest first)</summary>

| Task | Language | Model | Duration | Turns | Errors | Cost | Tests Quality | Chosen | Status |
|------|----------|-------|----------|-------|--------|------|-----------|--------|--------|
| PR Label Assigner | powershell-tool | opus48-1m-xhigh | 30.0min | 0 | 0 | $0.00 | — | powershell | timeout |
| Dependency License Checker | powershell | opus48-1m-xhigh | 30.0min | 0 | 5 | $0.00 | — | powershell | timeout |
| Environment Matrix Generator | powershell-tool | opus48-1m-xhigh | 30.0min | 0 | 0 | $0.00 | — | powershell | timeout |
| Artifact Cleanup Script | powershell-tool | opus48-1m-xhigh | 30.0min | 0 | 1 | $0.00 | — | powershell | timeout |
| Secret Rotation Validator | powershell | opus48-1m-medium | 1.1min | 11 | 0 | $0.55 | — | powershell | ok |
| PR Label Assigner | bash | opus48-1m-medium | 4.8min | 20 | 0 | $1.22 | — | bash | ok |
| Semantic Version Bumper | bash | opus48-1m-medium | 6.8min | 22 | 0 | $1.55 | — | bash | ok |
| PR Label Assigner | powershell | opus48-1m-medium | 6.3min | 23 | 0 | $1.52 | — | powershell | ok |
| Dependency License Checker | powershell | opus48-1m-ultracode | 4.3min | 23 | 0 | $1.21 | — | powershell | ok |
| Dependency License Checker | bash | opus48-1m-medium | 5.7min | 24 | 0 | $1.45 | — | bash | ok |
| Environment Matrix Generator | default | opus48-1m-high | 8.2min | 24 | 0 | $2.01 | — | python | ok |
| PR Label Assigner | default | opus48-1m-high | 7.1min | 25 | 1 | $1.86 | — | python | ok |
| PR Label Assigner | typescript-bun | opus48-1m-high | 3.0min | 26 | 1 | $1.17 | — | typescript | ok |
| Test Results Aggregator | default | opus48-1m-medium | 6.6min | 26 | 0 | $1.50 | — | python | ok |
| Semantic Version Bumper | default | opus48-1m-medium | 7.2min | 27 | 0 | $1.83 | — | python | ok |
| PR Label Assigner | powershell-tool | opus48-1m-medium | 7.6min | 27 | 1 | $1.66 | — | powershell | ok |
| Environment Matrix Generator | bash | opus48-1m-medium | 5.8min | 27 | 0 | $1.72 | — | bash | ok |
| Environment Matrix Generator | powershell-tool | opus48-1m-high | 9.2min | 27 | 0 | $3.06 | — | powershell | ok |
| Test Results Aggregator | bash | opus48-1m-high | 8.4min | 28 | 0 | $2.20 | — | bash | ok |
| Environment Matrix Generator | default | opus48-1m-medium | 6.7min | 28 | 0 | $2.01 | — | python | ok |
| Artifact Cleanup Script | powershell | opus48-1m-medium | 9.3min | 28 | 0 | $2.26 | — | powershell | ok |
| PR Label Assigner | default | opus48-1m-xhigh | 9.8min | 29 | 0 | $2.66 | — | python | ok |
| Test Results Aggregator | bash | opus48-1m-medium | 6.3min | 29 | 1 | $1.83 | — | bash | ok |
| Test Results Aggregator | powershell-tool | opus48-1m-medium | 7.4min | 29 | 0 | $1.95 | — | powershell | ok |
| Secret Rotation Validator | default | opus48-1m-medium | 5.9min | 29 | 0 | $1.65 | — | python | ok |
| Test Results Aggregator | powershell | opus48-1m-medium | 8.1min | 30 | 0 | $1.77 | — | powershell | ok |
| PR Label Assigner | bash | opus48-1m-high | 10.1min | 31 | 0 | $2.45 | — | bash | ok |
| Artifact Cleanup Script | powershell-tool | opus48-1m-high | 11.8min | 31 | 1 | $2.83 | — | powershell | ok |
| Dependency License Checker | default | opus48-1m-medium | 7.9min | 33 | 0 | $1.94 | — | python | ok |
| Dependency License Checker | powershell | opus48-1m-medium | 7.7min | 33 | 0 | $1.93 | — | powershell | ok |
| Dependency License Checker | powershell-tool | opus48-1m-high | 12.2min | 33 | 0 | $2.63 | — | powershell | ok |
| Environment Matrix Generator | powershell | opus48-1m-medium | 9.3min | 33 | 0 | $2.29 | — | powershell | ok |
| Secret Rotation Validator | bash | opus48-1m-high | 9.4min | 33 | 0 | $2.38 | — | bash | ok |
| Secret Rotation Validator | powershell-tool | opus48-1m-high | 15.2min | 33 | 0 | $3.22 | — | powershell | ok |
| Semantic Version Bumper | powershell | opus48-1m-medium | 10.0min | 34 | 0 | $2.33 | — | powershell | ok |
| Semantic Version Bumper | powershell-tool | opus48-1m-high | 12.1min | 34 | 0 | $2.32 | — | powershell | ok |
| Dependency License Checker | default | opus48-1m-high | 9.0min | 34 | 0 | $2.24 | — | powershell | ok |
| Dependency License Checker | default | opus48-1m-xhigh | 13.6min | 34 | 0 | $3.67 | — | python | ok |
| Secret Rotation Validator | powershell-tool | opus48-1m-medium | 8.0min | 34 | 1 | $2.14 | — | powershell | ok |
| Artifact Cleanup Script | powershell | opus48-1m-high | 9.6min | 35 | 2 | $2.60 | — | powershell | ok |
| PR Label Assigner | default | opus48-1m-medium | 8.2min | 36 | 1 | $1.91 | — | powershell | ok |
| Environment Matrix Generator | default | opus48-1m-xhigh | 16.2min | 38 | 0 | $4.05 | — | python | ok |
| Test Results Aggregator | powershell | opus48-1m-xhigh | 18.2min | 39 | 0 | $4.52 | — | powershell | ok |
| Environment Matrix Generator | bash | opus48-1m-high | 9.4min | 39 | 1 | $2.51 | — | bash | ok |
| Semantic Version Bumper | powershell-tool | opus48-1m-medium | 10.6min | 40 | 1 | $2.39 | — | powershell | ok |
| Environment Matrix Generator | typescript-bun | opus48-1m-medium | 9.1min | 40 | 0 | $2.29 | — | typescript | ok |
| Semantic Version Bumper | bash | opus48-1m-high | 9.5min | 41 | 1 | $2.70 | — | bash | ok |
| PR Label Assigner | powershell-tool | opus48-1m-high | 11.4min | 41 | 0 | $2.78 | — | powershell | ok |
| Dependency License Checker | powershell | opus48-1m-high | 12.8min | 42 | 1 | $3.09 | — | powershell | ok |
| Semantic Version Bumper | default | opus48-1m-ultracode | 14.6min | 43 | 0 | $4.35 | — | python | ok |
| Artifact Cleanup Script | default | opus48-1m-medium | 9.9min | 43 | 0 | $2.37 | — | powershell | ok |
| PR Label Assigner | typescript-bun | opus48-1m-medium | 13.1min | 44 | 0 | $2.48 | — | typescript | ok |
| Environment Matrix Generator | powershell | opus48-1m-high | 13.7min | 44 | 1 | $3.48 | — | powershell | ok |
| Artifact Cleanup Script | typescript-bun | opus48-1m-medium | 9.2min | 44 | 0 | $2.44 | — | typescript | ok |
| Dependency License Checker | typescript-bun | opus48-1m-medium | 8.7min | 45 | 0 | $2.33 | — | typescript | ok |
| Test Results Aggregator | typescript-bun | opus48-1m-medium | 9.2min | 45 | 0 | $2.57 | — | typescript | ok |
| Secret Rotation Validator | typescript-bun | opus48-1m-high | 11.9min | 45 | 1 | $3.29 | — | typescript | ok |
| Test Results Aggregator | typescript-bun | opus48-1m-xhigh | 16.4min | 46 | 0 | $4.37 | — | typescript | ok |
| Artifact Cleanup Script | powershell-tool | opus48-1m-medium | 11.9min | 46 | 1 | $2.91 | — | powershell | ok |
| Secret Rotation Validator | default | opus48-1m-xhigh | 15.6min | 46 | 0 | $4.15 | — | python | ok |
| Semantic Version Bumper | bash | opus48-1m-xhigh | 18.1min | 47 | 2 | $4.91 | — | bash | ok |
| Semantic Version Bumper | typescript-bun | opus48-1m-medium | 9.3min | 47 | 2 | $2.47 | — | typescript | ok |
| PR Label Assigner | powershell | opus48-1m-high | 11.0min | 47 | 0 | $2.65 | — | powershell | ok |
| Dependency License Checker | typescript-bun | opus48-1m-high | 11.5min | 47 | 0 | $3.04 | — | typescript | ok |
| Test Results Aggregator | powershell-tool | opus48-1m-high | 15.2min | 47 | 0 | $3.39 | — | powershell | ok |
| Artifact Cleanup Script | bash | opus48-1m-high | 11.6min | 47 | 0 | $3.32 | — | bash | ok |
| Secret Rotation Validator | default | opus48-1m-high | 9.1min | 47 | 0 | $3.12 | — | python | ok |
| Dependency License Checker | typescript-bun | opus48-1m-xhigh | 19.6min | 48 | 0 | $5.16 | — | typescript | ok |
| Dependency License Checker | powershell-tool | opus48-1m-medium | 12.7min | 49 | 0 | $3.35 | — | powershell | ok |
| Dependency License Checker | powershell-tool | opus48-1m-xhigh | 25.2min | 49 | 0 | $6.38 | — | powershell | ok |
| Artifact Cleanup Script | bash | opus48-1m-xhigh | 18.1min | 49 | 2 | $5.08 | — | bash | ok |
| Artifact Cleanup Script | typescript-bun | opus48-1m-xhigh | 21.6min | 49 | 2 | $5.91 | — | typescript | ok |
| Semantic Version Bumper | default | opus48-1m-xhigh | 15.3min | 50 | 1 | $4.59 | — | python | ok |
| PR Label Assigner | powershell-tool | opus48-1m-ultracode | 22.3min | 50 | 1 | $5.54 | — | powershell | ok |
| Artifact Cleanup Script | default | opus48-1m-high | 10.2min | 50 | 0 | $3.16 | — | python | ok |
| PR Label Assigner | default | opus48-1m-ultracode | 12.6min | 51 | 0 | $4.18 | — | python | ok |
| Dependency License Checker | bash | opus48-1m-high | 15.0min | 51 | 3 | $4.02 | — | bash | ok |
| Semantic Version Bumper | default | opus48-1m-high | 9.8min | 52 | 0 | $3.34 | — | javascript | ok |
| Semantic Version Bumper | typescript-bun | opus48-1m-high | 11.5min | 52 | 0 | $3.14 | — | typescript | ok |
| PR Label Assigner | powershell | opus48-1m-ultracode | 21.3min | 52 | 0 | $5.68 | — | powershell | ok |
| Environment Matrix Generator | powershell-tool | opus48-1m-medium | 12.9min | 52 | 2 | $3.60 | — | powershell | ok |
| Test Results Aggregator | bash | opus48-1m-xhigh | 21.2min | 53 | 3 | $5.41 | — | bash | ok |
| Artifact Cleanup Script | bash | opus48-1m-medium | 11.4min | 53 | 1 | $3.16 | — | bash | ok |
| Secret Rotation Validator | powershell | opus48-1m-high | 15.4min | 53 | 0 | $3.46 | — | powershell | ok |
| Secret Rotation Validator | typescript-bun | opus48-1m-xhigh | 17.5min | 54 | 0 | $5.12 | — | typescript | ok |
| PR Label Assigner | bash | opus48-1m-ultracode | 18.6min | 55 | 2 | $5.24 | — | bash | ok |
| Secret Rotation Validator | bash | opus48-1m-xhigh | 21.4min | 55 | 0 | $5.41 | — | bash | ok |
| Semantic Version Bumper | powershell-tool | opus48-1m-ultracode | 25.2min | 58 | 0 | $6.83 | — | powershell | ok |
| Environment Matrix Generator | powershell | opus48-1m-xhigh | 28.4min | 58 | 0 | $7.16 | — | powershell | ok |
| Test Results Aggregator | default | opus48-1m-high | 12.2min | 59 | 1 | $3.42 | — | python | ok |
| Test Results Aggregator | powershell | opus48-1m-high | 17.3min | 59 | 0 | $3.84 | — | powershell | ok |
| Environment Matrix Generator | bash | opus48-1m-xhigh | 18.6min | 59 | 0 | $5.52 | — | bash | ok |
| Semantic Version Bumper | powershell | opus48-1m-high | 16.9min | 60 | 2 | $3.59 | — | powershell | ok |
| Secret Rotation Validator | powershell | opus48-1m-xhigh | 19.5min | 60 | 0 | $5.52 | — | powershell | ok |
| Semantic Version Bumper | powershell-tool | opus48-1m-xhigh | 21.0min | 61 | 1 | $5.56 | — | powershell | ok |
| PR Label Assigner | typescript-bun | opus48-1m-ultracode | 21.5min | 62 | 5 | $5.80 | — | typescript | ok |
| PR Label Assigner | powershell | opus48-1m-xhigh | 19.4min | 63 | 0 | $5.67 | — | powershell | ok |
| Test Results Aggregator | default | opus48-1m-xhigh | 17.2min | 63 | 0 | $5.38 | — | python | ok |
| PR Label Assigner | bash | opus48-1m-xhigh | 20.5min | 64 | 0 | $5.87 | — | bash | ok |
| Secret Rotation Validator | bash | opus48-1m-medium | 23.9min | 64 | 6 | $5.71 | — | bash | ok |
| Semantic Version Bumper | powershell | opus48-1m-ultracode | 31.9min | 65 | 2 | $13.39 | — | powershell | ok |
| Dependency License Checker | default | opus48-1m-ultracode | 21.3min | 67 | 0 | $5.41 | — | powershell | ok |
| Test Results Aggregator | powershell-tool | opus48-1m-xhigh | 25.9min | 67 | 2 | $6.67 | — | powershell | ok |
| Semantic Version Bumper | powershell | opus48-1m-xhigh | 21.0min | 69 | 1 | $6.19 | — | powershell | ok |
| Test Results Aggregator | typescript-bun | opus48-1m-high | 19.2min | 69 | 0 | $5.19 | — | typescript | ok |
| Environment Matrix Generator | typescript-bun | opus48-1m-high | 13.3min | 69 | 0 | $3.94 | — | typescript | ok |
| Semantic Version Bumper | typescript-bun | opus48-1m-xhigh | 22.3min | 71 | 3 | $6.51 | — | typescript | ok |
| PR Label Assigner | typescript-bun | opus48-1m-xhigh | 19.8min | 72 | 0 | $6.01 | — | typescript | ok |
| Semantic Version Bumper | bash | opus48-1m-ultracode | 20.8min | 74 | 0 | $6.09 | — | bash | ok |
| Environment Matrix Generator | typescript-bun | opus48-1m-xhigh | 25.3min | 77 | 1 | $7.25 | — | typescript | ok |
| Artifact Cleanup Script | default | opus48-1m-xhigh | 19.1min | 77 | 0 | $6.84 | — | python | ok |
| Secret Rotation Validator | powershell-tool | opus48-1m-xhigh | 26.1min | 78 | 0 | $7.45 | — | powershell | ok |
| Secret Rotation Validator | typescript-bun | opus48-1m-medium | 23.0min | 78 | 2 | $4.51 | — | typescript | ok |
| Artifact Cleanup Script | typescript-bun | opus48-1m-high | 14.8min | 82 | 1 | $6.00 | — | typescript | ok |
| Artifact Cleanup Script | powershell | opus48-1m-xhigh | 25.0min | 92 | 1 | $7.41 | — | powershell | ok |
| Dependency License Checker | bash | opus48-1m-xhigh | 23.9min | 96 | 2 | $8.01 | — | bash | ok |
| Semantic Version Bumper | typescript-bun | opus48-1m-ultracode | 30.6min | 104 | 0 | $11.91 | — | typescript | ok |

</details>

<details>
<summary>Sorted by LLM-as-judge score (best first)</summary>

| Task | Language | Model | Duration | Turns | Errors | Cost | Tests Quality | Chosen | Status |
|------|----------|-------|----------|-------|--------|------|-----------|--------|--------|
| Semantic Version Bumper | bash | opus48-1m-high | 9.5min | 41 | 1 | $2.70 | — | bash | ok |
| Semantic Version Bumper | bash | opus48-1m-medium | 6.8min | 22 | 0 | $1.55 | — | bash | ok |
| Semantic Version Bumper | bash | opus48-1m-ultracode | 20.8min | 74 | 0 | $6.09 | — | bash | ok |
| Semantic Version Bumper | bash | opus48-1m-xhigh | 18.1min | 47 | 2 | $4.91 | — | bash | ok |
| Semantic Version Bumper | default | opus48-1m-high | 9.8min | 52 | 0 | $3.34 | — | javascript | ok |
| Semantic Version Bumper | default | opus48-1m-medium | 7.2min | 27 | 0 | $1.83 | — | python | ok |
| Semantic Version Bumper | default | opus48-1m-ultracode | 14.6min | 43 | 0 | $4.35 | — | python | ok |
| Semantic Version Bumper | default | opus48-1m-xhigh | 15.3min | 50 | 1 | $4.59 | — | python | ok |
| Semantic Version Bumper | powershell | opus48-1m-high | 16.9min | 60 | 2 | $3.59 | — | powershell | ok |
| Semantic Version Bumper | powershell | opus48-1m-medium | 10.0min | 34 | 0 | $2.33 | — | powershell | ok |
| Semantic Version Bumper | powershell | opus48-1m-ultracode | 31.9min | 65 | 2 | $13.39 | — | powershell | ok |
| Semantic Version Bumper | powershell | opus48-1m-xhigh | 21.0min | 69 | 1 | $6.19 | — | powershell | ok |
| Semantic Version Bumper | powershell-tool | opus48-1m-high | 12.1min | 34 | 0 | $2.32 | — | powershell | ok |
| Semantic Version Bumper | powershell-tool | opus48-1m-medium | 10.6min | 40 | 1 | $2.39 | — | powershell | ok |
| Semantic Version Bumper | powershell-tool | opus48-1m-ultracode | 25.2min | 58 | 0 | $6.83 | — | powershell | ok |
| Semantic Version Bumper | powershell-tool | opus48-1m-xhigh | 21.0min | 61 | 1 | $5.56 | — | powershell | ok |
| Semantic Version Bumper | typescript-bun | opus48-1m-high | 11.5min | 52 | 0 | $3.14 | — | typescript | ok |
| Semantic Version Bumper | typescript-bun | opus48-1m-medium | 9.3min | 47 | 2 | $2.47 | — | typescript | ok |
| Semantic Version Bumper | typescript-bun | opus48-1m-ultracode | 30.6min | 104 | 0 | $11.91 | — | typescript | ok |
| Semantic Version Bumper | typescript-bun | opus48-1m-xhigh | 22.3min | 71 | 3 | $6.51 | — | typescript | ok |
| PR Label Assigner | bash | opus48-1m-high | 10.1min | 31 | 0 | $2.45 | — | bash | ok |
| PR Label Assigner | bash | opus48-1m-medium | 4.8min | 20 | 0 | $1.22 | — | bash | ok |
| PR Label Assigner | bash | opus48-1m-ultracode | 18.6min | 55 | 2 | $5.24 | — | bash | ok |
| PR Label Assigner | bash | opus48-1m-xhigh | 20.5min | 64 | 0 | $5.87 | — | bash | ok |
| PR Label Assigner | default | opus48-1m-high | 7.1min | 25 | 1 | $1.86 | — | python | ok |
| PR Label Assigner | default | opus48-1m-medium | 8.2min | 36 | 1 | $1.91 | — | powershell | ok |
| PR Label Assigner | default | opus48-1m-ultracode | 12.6min | 51 | 0 | $4.18 | — | python | ok |
| PR Label Assigner | default | opus48-1m-xhigh | 9.8min | 29 | 0 | $2.66 | — | python | ok |
| PR Label Assigner | powershell | opus48-1m-high | 11.0min | 47 | 0 | $2.65 | — | powershell | ok |
| PR Label Assigner | powershell | opus48-1m-medium | 6.3min | 23 | 0 | $1.52 | — | powershell | ok |
| PR Label Assigner | powershell | opus48-1m-ultracode | 21.3min | 52 | 0 | $5.68 | — | powershell | ok |
| PR Label Assigner | powershell | opus48-1m-xhigh | 19.4min | 63 | 0 | $5.67 | — | powershell | ok |
| PR Label Assigner | powershell-tool | opus48-1m-high | 11.4min | 41 | 0 | $2.78 | — | powershell | ok |
| PR Label Assigner | powershell-tool | opus48-1m-medium | 7.6min | 27 | 1 | $1.66 | — | powershell | ok |
| PR Label Assigner | powershell-tool | opus48-1m-ultracode | 22.3min | 50 | 1 | $5.54 | — | powershell | ok |
| PR Label Assigner | powershell-tool | opus48-1m-xhigh | 30.0min | 0 | 0 | $0.00 | — | powershell | timeout |
| PR Label Assigner | typescript-bun | opus48-1m-high | 3.0min | 26 | 1 | $1.17 | — | typescript | ok |
| PR Label Assigner | typescript-bun | opus48-1m-medium | 13.1min | 44 | 0 | $2.48 | — | typescript | ok |
| PR Label Assigner | typescript-bun | opus48-1m-ultracode | 21.5min | 62 | 5 | $5.80 | — | typescript | ok |
| PR Label Assigner | typescript-bun | opus48-1m-xhigh | 19.8min | 72 | 0 | $6.01 | — | typescript | ok |
| Dependency License Checker | bash | opus48-1m-high | 15.0min | 51 | 3 | $4.02 | — | bash | ok |
| Dependency License Checker | bash | opus48-1m-medium | 5.7min | 24 | 0 | $1.45 | — | bash | ok |
| Dependency License Checker | bash | opus48-1m-xhigh | 23.9min | 96 | 2 | $8.01 | — | bash | ok |
| Dependency License Checker | default | opus48-1m-high | 9.0min | 34 | 0 | $2.24 | — | powershell | ok |
| Dependency License Checker | default | opus48-1m-medium | 7.9min | 33 | 0 | $1.94 | — | python | ok |
| Dependency License Checker | default | opus48-1m-ultracode | 21.3min | 67 | 0 | $5.41 | — | powershell | ok |
| Dependency License Checker | default | opus48-1m-xhigh | 13.6min | 34 | 0 | $3.67 | — | python | ok |
| Dependency License Checker | powershell | opus48-1m-high | 12.8min | 42 | 1 | $3.09 | — | powershell | ok |
| Dependency License Checker | powershell | opus48-1m-medium | 7.7min | 33 | 0 | $1.93 | — | powershell | ok |
| Dependency License Checker | powershell | opus48-1m-xhigh | 30.0min | 0 | 5 | $0.00 | — | powershell | timeout |
| Dependency License Checker | powershell-tool | opus48-1m-high | 12.2min | 33 | 0 | $2.63 | — | powershell | ok |
| Dependency License Checker | powershell-tool | opus48-1m-medium | 12.7min | 49 | 0 | $3.35 | — | powershell | ok |
| Dependency License Checker | powershell-tool | opus48-1m-xhigh | 25.2min | 49 | 0 | $6.38 | — | powershell | ok |
| Dependency License Checker | typescript-bun | opus48-1m-high | 11.5min | 47 | 0 | $3.04 | — | typescript | ok |
| Dependency License Checker | typescript-bun | opus48-1m-medium | 8.7min | 45 | 0 | $2.33 | — | typescript | ok |
| Dependency License Checker | typescript-bun | opus48-1m-xhigh | 19.6min | 48 | 0 | $5.16 | — | typescript | ok |
| Test Results Aggregator | bash | opus48-1m-high | 8.4min | 28 | 0 | $2.20 | — | bash | ok |
| Test Results Aggregator | bash | opus48-1m-medium | 6.3min | 29 | 1 | $1.83 | — | bash | ok |
| Test Results Aggregator | bash | opus48-1m-xhigh | 21.2min | 53 | 3 | $5.41 | — | bash | ok |
| Test Results Aggregator | default | opus48-1m-high | 12.2min | 59 | 1 | $3.42 | — | python | ok |
| Test Results Aggregator | default | opus48-1m-medium | 6.6min | 26 | 0 | $1.50 | — | python | ok |
| Test Results Aggregator | default | opus48-1m-xhigh | 17.2min | 63 | 0 | $5.38 | — | python | ok |
| Test Results Aggregator | powershell | opus48-1m-high | 17.3min | 59 | 0 | $3.84 | — | powershell | ok |
| Test Results Aggregator | powershell | opus48-1m-medium | 8.1min | 30 | 0 | $1.77 | — | powershell | ok |
| Test Results Aggregator | powershell | opus48-1m-xhigh | 18.2min | 39 | 0 | $4.52 | — | powershell | ok |
| Test Results Aggregator | powershell-tool | opus48-1m-high | 15.2min | 47 | 0 | $3.39 | — | powershell | ok |
| Test Results Aggregator | powershell-tool | opus48-1m-medium | 7.4min | 29 | 0 | $1.95 | — | powershell | ok |
| Test Results Aggregator | powershell-tool | opus48-1m-xhigh | 25.9min | 67 | 2 | $6.67 | — | powershell | ok |
| Test Results Aggregator | typescript-bun | opus48-1m-high | 19.2min | 69 | 0 | $5.19 | — | typescript | ok |
| Test Results Aggregator | typescript-bun | opus48-1m-medium | 9.2min | 45 | 0 | $2.57 | — | typescript | ok |
| Test Results Aggregator | typescript-bun | opus48-1m-xhigh | 16.4min | 46 | 0 | $4.37 | — | typescript | ok |
| Environment Matrix Generator | bash | opus48-1m-high | 9.4min | 39 | 1 | $2.51 | — | bash | ok |
| Environment Matrix Generator | bash | opus48-1m-medium | 5.8min | 27 | 0 | $1.72 | — | bash | ok |
| Environment Matrix Generator | bash | opus48-1m-xhigh | 18.6min | 59 | 0 | $5.52 | — | bash | ok |
| Environment Matrix Generator | default | opus48-1m-high | 8.2min | 24 | 0 | $2.01 | — | python | ok |
| Environment Matrix Generator | default | opus48-1m-medium | 6.7min | 28 | 0 | $2.01 | — | python | ok |
| Environment Matrix Generator | default | opus48-1m-xhigh | 16.2min | 38 | 0 | $4.05 | — | python | ok |
| Environment Matrix Generator | powershell | opus48-1m-high | 13.7min | 44 | 1 | $3.48 | — | powershell | ok |
| Environment Matrix Generator | powershell | opus48-1m-medium | 9.3min | 33 | 0 | $2.29 | — | powershell | ok |
| Environment Matrix Generator | powershell | opus48-1m-xhigh | 28.4min | 58 | 0 | $7.16 | — | powershell | ok |
| Environment Matrix Generator | powershell-tool | opus48-1m-high | 9.2min | 27 | 0 | $3.06 | — | powershell | ok |
| Environment Matrix Generator | powershell-tool | opus48-1m-medium | 12.9min | 52 | 2 | $3.60 | — | powershell | ok |
| Environment Matrix Generator | powershell-tool | opus48-1m-xhigh | 30.0min | 0 | 0 | $0.00 | — | powershell | timeout |
| Environment Matrix Generator | typescript-bun | opus48-1m-high | 13.3min | 69 | 0 | $3.94 | — | typescript | ok |
| Environment Matrix Generator | typescript-bun | opus48-1m-medium | 9.1min | 40 | 0 | $2.29 | — | typescript | ok |
| Environment Matrix Generator | typescript-bun | opus48-1m-xhigh | 25.3min | 77 | 1 | $7.25 | — | typescript | ok |
| Artifact Cleanup Script | bash | opus48-1m-high | 11.6min | 47 | 0 | $3.32 | — | bash | ok |
| Artifact Cleanup Script | bash | opus48-1m-medium | 11.4min | 53 | 1 | $3.16 | — | bash | ok |
| Artifact Cleanup Script | bash | opus48-1m-xhigh | 18.1min | 49 | 2 | $5.08 | — | bash | ok |
| Artifact Cleanup Script | default | opus48-1m-high | 10.2min | 50 | 0 | $3.16 | — | python | ok |
| Artifact Cleanup Script | default | opus48-1m-medium | 9.9min | 43 | 0 | $2.37 | — | powershell | ok |
| Artifact Cleanup Script | default | opus48-1m-xhigh | 19.1min | 77 | 0 | $6.84 | — | python | ok |
| Artifact Cleanup Script | powershell | opus48-1m-high | 9.6min | 35 | 2 | $2.60 | — | powershell | ok |
| Artifact Cleanup Script | powershell | opus48-1m-medium | 9.3min | 28 | 0 | $2.26 | — | powershell | ok |
| Artifact Cleanup Script | powershell | opus48-1m-xhigh | 25.0min | 92 | 1 | $7.41 | — | powershell | ok |
| Artifact Cleanup Script | powershell-tool | opus48-1m-high | 11.8min | 31 | 1 | $2.83 | — | powershell | ok |
| Artifact Cleanup Script | powershell-tool | opus48-1m-medium | 11.9min | 46 | 1 | $2.91 | — | powershell | ok |
| Artifact Cleanup Script | powershell-tool | opus48-1m-xhigh | 30.0min | 0 | 1 | $0.00 | — | powershell | timeout |
| Artifact Cleanup Script | typescript-bun | opus48-1m-high | 14.8min | 82 | 1 | $6.00 | — | typescript | ok |
| Artifact Cleanup Script | typescript-bun | opus48-1m-medium | 9.2min | 44 | 0 | $2.44 | — | typescript | ok |
| Artifact Cleanup Script | typescript-bun | opus48-1m-xhigh | 21.6min | 49 | 2 | $5.91 | — | typescript | ok |
| Secret Rotation Validator | bash | opus48-1m-high | 9.4min | 33 | 0 | $2.38 | — | bash | ok |
| Secret Rotation Validator | bash | opus48-1m-medium | 23.9min | 64 | 6 | $5.71 | — | bash | ok |
| Secret Rotation Validator | bash | opus48-1m-xhigh | 21.4min | 55 | 0 | $5.41 | — | bash | ok |
| Secret Rotation Validator | default | opus48-1m-high | 9.1min | 47 | 0 | $3.12 | — | python | ok |
| Secret Rotation Validator | default | opus48-1m-medium | 5.9min | 29 | 0 | $1.65 | — | python | ok |
| Secret Rotation Validator | default | opus48-1m-xhigh | 15.6min | 46 | 0 | $4.15 | — | python | ok |
| Secret Rotation Validator | powershell | opus48-1m-high | 15.4min | 53 | 0 | $3.46 | — | powershell | ok |
| Secret Rotation Validator | powershell | opus48-1m-medium | 1.1min | 11 | 0 | $0.55 | — | powershell | ok |
| Secret Rotation Validator | powershell | opus48-1m-xhigh | 19.5min | 60 | 0 | $5.52 | — | powershell | ok |
| Secret Rotation Validator | powershell-tool | opus48-1m-high | 15.2min | 33 | 0 | $3.22 | — | powershell | ok |
| Secret Rotation Validator | powershell-tool | opus48-1m-medium | 8.0min | 34 | 1 | $2.14 | — | powershell | ok |
| Secret Rotation Validator | powershell-tool | opus48-1m-xhigh | 26.1min | 78 | 0 | $7.45 | — | powershell | ok |
| Secret Rotation Validator | typescript-bun | opus48-1m-high | 11.9min | 45 | 1 | $3.29 | — | typescript | ok |
| Secret Rotation Validator | typescript-bun | opus48-1m-medium | 23.0min | 78 | 2 | $4.51 | — | typescript | ok |
| Secret Rotation Validator | typescript-bun | opus48-1m-xhigh | 17.5min | 54 | 0 | $5.12 | — | typescript | ok |
| Dependency License Checker | powershell | opus48-1m-ultracode | 4.3min | 23 | 0 | $1.21 | — | powershell | ok |

</details>

## Notes

### Tiers

- **Duration bands:** **A+** ≤1.11×, **A** ≤1.23×, **A-** ≤1.37×, **B+** ≤1.52×, **B** ≤1.69×, **B-** ≤1.88×, **C+** ≤2.08×, **C** ≤2.31×, **C-** ≤2.57×, **D+** ≤2.85×, **D** ≤3.17×, **D-** ≤3.52×, **F** >3.52×
- **Cost bands:** **A+** ≤1.14×, **A** ≤1.30×, **A-** ≤1.49×, **B+** ≤1.70×, **B** ≤1.94×, **B-** ≤2.21×, **C+** ≤2.53×, **C** ≤2.89×, **C-** ≤3.29×, **D+** ≤3.76×, **D** ≤4.29×, **D-** ≤4.90×, **F** >4.90×

*Tests/Workflow Craft bands are absolute Overall score bands:* **A+** ≥4.7, **A** ≥4.4, **A-** ≥4.1, **B+** ≥3.8, **B** ≥3.5, **B-** ≥3.2, **C+** ≥2.9, **C** ≥2.6, **C-** ≥2.3, **D+** ≥2.0, **D** ≥1.7, **D-** ≥1.4, **F** <1.4, `—` = no data.*

### CLI Version Legend

| Variant label | CLI version | Tasks | Languages |
|---------------|-------------|-------|-----------|
| opus48-1m-high | 2.1.195 | All | All |
| opus48-1m-medium | 2.1.193 | 11-semantic-version-bumper, 12-pr-label-assigner, 13-dependency-license-checker, 15-test-results-aggregator, 16-environment-matrix-generator | All |
| opus48-1m-medium | 2.1.195 | 16-environment-matrix-generator, 17-artifact-cleanup-script, 18-secret-rotation-validator | All |
| opus48-1m-ultracode | 2.1.195 | 11-semantic-version-bumper, 12-pr-label-assigner, 13-dependency-license-checker | All |
| opus48-1m-xhigh | 2.1.195 | All | All |

---
*Generated by generate_results.py — benchmark instructions v4*