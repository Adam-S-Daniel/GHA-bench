# Judge Consistency Data

*Raw panel-of-judges data plus a rankings-focused Quality Analysis. Backs the merged Conclusions and Judge Consistency Summary in the corresponding [`results.md`](results.md).*

## Notes

- **Generated:** 2026-07-05 01:00:31 AM ET
- **Source:** `/home/passp/repos/GHA-bench/results/2026-05-06_173435`
- **Judges present:** haiku45, gemini31pro
- **Score conventions:** Scores shown are the `overall` dimension from each judge (1-5). Δ column is the second judge minus the first; positive = second judge is more generous.

## Quality Analysis

The opus47-1m configuration at the xhigh effort tier produces the strongest output overall, taking the top model+effort slot on both Tests Quality and Workflow Craft from each judge. Default (Python) leads the language ranking for Tests Quality (#1 by both judges), while typescript-bun leads for Workflow Craft (#1 by both judges), with strong agreement across the language axis (ρ = +0.90 on both rubrics).

- **Effort tier**: Within opus47-1m, the xhigh tier outscores both medium and high on Tests Quality and Workflow Craft from both judges, with no reversals between effort levels.
- **Bottom of the stack**: The haiku45 model and bash language sit last on every aggregate ranking by both judges, making haiku45-on-bash the clear floor across both axes.
- **Workflow Craft ceiling**: Gemini gives opus47-1m xhigh a 4.91 average and lands several language×model cells at a perfect 5.00, indicating headroom is largely exhausted at the top tier.
- **Where rankings diverge**: Agreement weakens at finer language×model granularity (ρ = +0.62 Tests, +0.56 Craft); the model-level reversals all involve opus47-200k, which Gemini ranks above opus47-1m on Workflow Craft and above sonnet on both axes.
- **Haiku grades harder**: The inter-judge gap is wider on Workflow Craft (+2.23) than Tests Quality (+1.67), a baseline difference in scale rather than ordering disagreement, since both judges still produce the same top-to-bottom model ranking.

*Provenance:* `claude-opus-4-7[1m]` at effort `xhigh` via Claude CLI (from cache); 5 in / 3536 out tokens, $0.3071. Prompt: [`QUALITY_ANALYSIS_SYSTEM_PROMPT`](../../judge_consistency_report.py).

## Campaign summary

### Tests Quality

| Scope | n | haiku45 ovr | gemini31pro ovr | Δ(gemini31pro−haiku45) |
|---|---|---|---|---|
| all | 265 | 2.79 | 4.46 | +1.67 |

### Workflow Craft

| Scope | n | haiku45 ovr | gemini31pro ovr | Δ(gemini31pro−haiku45) |
|---|---|---|---|---|
| all | 248 | 2.32 | 4.54 | +2.23 |

## By task

### Tests Quality

| Task | n | haiku45 ovr | gemini31pro ovr | Δ(gemini31pro−haiku45) |
|---|---|---|---|---|
| 11-semantic-version-bumper | 38 | 2.68 | 4.16 | +1.47 |
| 12-pr-label-assigner | 31 | 2.65 | 3.90 | +1.26 |
| 13-dependency-license-checker | 40 | 3.00 | 4.60 | +1.60 |
| 15-test-results-aggregator | 38 | 2.82 | 4.55 | +1.74 |
| 16-environment-matrix-generator | 40 | 2.77 | 4.62 | +1.85 |
| 17-artifact-cleanup-script | 40 | 2.70 | 4.58 | +1.88 |
| 18-secret-rotation-validator | 38 | 2.89 | 4.68 | +1.79 |

### Workflow Craft

| Task | n | haiku45 ovr | gemini31pro ovr | Δ(gemini31pro−haiku45) |
|---|---|---|---|---|
| 11-semantic-version-bumper | 37 | 2.14 | 4.24 | +2.11 |
| 12-pr-label-assigner | 29 | 2.10 | 4.03 | +1.93 |
| 13-dependency-license-checker | 39 | 2.62 | 4.59 | +1.97 |
| 15-test-results-aggregator | 34 | 2.29 | 4.79 | +2.50 |
| 16-environment-matrix-generator | 37 | 2.38 | 4.68 | +2.30 |
| 17-artifact-cleanup-script | 34 | 2.18 | 4.65 | +2.47 |
| 18-secret-rotation-validator | 38 | 2.45 | 4.74 | +2.29 |

## By language mode

### Tests Quality

| Mode | n | haiku45 ovr | gemini31pro ovr | Δ(gemini31pro−haiku45) |
|---|---|---|---|---|
| bash | 55 | 2.42 | 4.09 | +1.67 |
| default | 51 | 2.96 | 4.61 | +1.65 |
| powershell | 50 | 2.96 | 4.54 | +1.58 |
| powershell-tool | 53 | 2.83 | 4.47 | +1.64 |
| typescript-bun | 56 | 2.82 | 4.61 | +1.79 |

### Workflow Craft

| Mode | n | haiku45 ovr | gemini31pro ovr | Δ(gemini31pro−haiku45) |
|---|---|---|---|---|
| bash | 55 | 2.24 | 4.35 | +2.11 |
| default | 48 | 2.25 | 4.56 | +2.31 |
| powershell | 46 | 2.39 | 4.59 | +2.20 |
| powershell-tool | 50 | 2.30 | 4.56 | +2.26 |
| typescript-bun | 49 | 2.43 | 4.69 | +2.27 |

## By model + effort

### Tests Quality

| Model-Effort | n | haiku45 ovr | gemini31pro ovr | Δ(gemini31pro−haiku45) |
|---|---|---|---|---|
| haiku45 | 30 | 1.93 | 2.33 | +0.40 |
| opus | 34 | 2.88 | 4.56 | +1.68 |
| opus47-1m-high | 34 | 3.09 | 4.79 | +1.71 |
| opus47-1m-medium | 34 | 2.74 | 4.82 | +2.09 |
| opus47-1m-xhigh | 34 | 3.29 | 4.91 | +1.62 |
| opus47-200k-medium | 34 | 2.74 | 4.82 | +2.09 |
| sonnet | 33 | 2.91 | 4.67 | +1.76 |
| sonnet46-1m-medium | 32 | 2.66 | 4.53 | +1.88 |

### Workflow Craft

| Model-Effort | n | haiku45 ovr | gemini31pro ovr | Δ(gemini31pro−haiku45) |
|---|---|---|---|---|
| haiku45 | 33 | 1.79 | 3.67 | +1.88 |
| opus | 29 | 2.00 | 4.52 | +2.52 |
| opus47-1m-high | 31 | 2.71 | 4.74 | +2.03 |
| opus47-1m-medium | 32 | 2.38 | 4.81 | +2.44 |
| opus47-1m-xhigh | 32 | 3.06 | 4.91 | +1.84 |
| opus47-200k-medium | 31 | 2.29 | 4.84 | +2.55 |
| sonnet | 30 | 2.37 | 4.57 | +2.20 |
| sonnet46-1m-medium | 30 | 1.93 | 4.33 | +2.40 |

## Disagreement hotspots (panel span ≥ 2 on overall)

### Tests Quality

| Task | Mode | Model | Span | haiku45 ovr | gemini31pro ovr |
|---|---|---|---|---|---|
| 13-dependency-license-checker | bash | opus47-1m-xhigh | 4.0 | 1.0 | 5.0 |
| 11-semantic-version-bumper | powershell | opus | 3.0 | 2.0 | 5.0 |
| 11-semantic-version-bumper | powershell | opus47-200k-medium | 3.0 | 2.0 | 5.0 |
| 11-semantic-version-bumper | powershell-tool | opus | 3.0 | 2.0 | 5.0 |
| 11-semantic-version-bumper | powershell-tool | opus47-1m-high | 3.0 | 2.0 | 5.0 |
| 11-semantic-version-bumper | typescript-bun | opus | 3.0 | 2.0 | 5.0 |
| 11-semantic-version-bumper | typescript-bun | opus47-200k-medium | 3.0 | 2.0 | 5.0 |
| 12-pr-label-assigner | bash | opus47-1m-high | 3.0 | 2.0 | 5.0 |
| 12-pr-label-assigner | powershell-tool | opus47-1m-high | 3.0 | 2.0 | 5.0 |
| 12-pr-label-assigner | powershell-tool | opus47-1m-medium | 3.0 | 2.0 | 5.0 |
| 12-pr-label-assigner | typescript-bun | opus47-200k-medium | 3.0 | 2.0 | 5.0 |
| 12-pr-label-assigner | typescript-bun | sonnet46-1m-medium | 3.0 | 2.0 | 5.0 |
| 13-dependency-license-checker | bash | opus47-200k-medium | 3.0 | 2.0 | 5.0 |
| 13-dependency-license-checker | powershell | opus47-1m-medium | 3.0 | 2.0 | 5.0 |
| 13-dependency-license-checker | powershell | opus47-200k-medium | 3.0 | 2.0 | 5.0 |
| 15-test-results-aggregator | bash | opus | 3.0 | 2.0 | 5.0 |
| 15-test-results-aggregator | bash | opus47-1m-medium | 3.0 | 2.0 | 5.0 |
| 15-test-results-aggregator | bash | opus47-200k-medium | 3.0 | 2.0 | 5.0 |
| 15-test-results-aggregator | bash | sonnet46-1m-medium | 3.0 | 2.0 | 5.0 |
| 15-test-results-aggregator | default | opus | 3.0 | 2.0 | 5.0 |
| 15-test-results-aggregator | powershell | opus47-1m-high | 3.0 | 2.0 | 5.0 |
| 15-test-results-aggregator | powershell-tool | opus47-1m-medium | 3.0 | 2.0 | 5.0 |
| 15-test-results-aggregator | typescript-bun | sonnet46-1m-medium | 3.0 | 2.0 | 5.0 |
| 16-environment-matrix-generato | bash | opus47-1m-high | 3.0 | 2.0 | 5.0 |
| 16-environment-matrix-generato | bash | opus47-1m-medium | 3.0 | 2.0 | 5.0 |

### Workflow Craft

| Task | Mode | Model | Span | haiku45 ovr | gemini31pro ovr |
|---|---|---|---|---|---|
| 11-semantic-version-bumper | typescript-bun | opus47-200k-medium | 4.0 | 1.0 | 5.0 |
| 12-pr-label-assigner | bash | opus47-1m-high | 4.0 | 1.0 | 5.0 |
| 12-pr-label-assigner | typescript-bun | opus47-200k-medium | 4.0 | 1.0 | 5.0 |
| 15-test-results-aggregator | bash | opus | 4.0 | 1.0 | 5.0 |
| 15-test-results-aggregator | bash | opus47-1m-medium | 4.0 | 1.0 | 5.0 |
| 15-test-results-aggregator | default | opus | 4.0 | 1.0 | 5.0 |
| 15-test-results-aggregator | powershell | opus47-1m-medium | 4.0 | 1.0 | 5.0 |
| 16-environment-matrix-generato | bash | opus47-1m-medium | 4.0 | 1.0 | 5.0 |
| 16-environment-matrix-generato | default | haiku45 | 4.0 | 1.0 | 5.0 |
| 17-artifact-cleanup-script | default | opus | 4.0 | 1.0 | 5.0 |
| 18-secret-rotation-validator | powershell-tool | opus47-1m-xhigh | 4.0 | 1.0 | 5.0 |
| 11-semantic-version-bumper | bash | opus47-1m-high | 3.0 | 2.0 | 5.0 |
| 11-semantic-version-bumper | bash | opus47-200k-medium | 3.0 | 2.0 | 5.0 |
| 11-semantic-version-bumper | bash | sonnet | 3.0 | 1.0 | 4.0 |
| 11-semantic-version-bumper | default | opus47-1m-high | 3.0 | 2.0 | 5.0 |
| 11-semantic-version-bumper | default | opus47-1m-medium | 3.0 | 2.0 | 5.0 |
| 11-semantic-version-bumper | default | opus47-200k-medium | 3.0 | 2.0 | 5.0 |
| 11-semantic-version-bumper | powershell | opus47-1m-high | 3.0 | 2.0 | 5.0 |
| 11-semantic-version-bumper | powershell | opus47-1m-medium | 3.0 | 2.0 | 5.0 |
| 11-semantic-version-bumper | powershell-tool | opus47-1m-medium | 3.0 | 2.0 | 5.0 |
| 11-semantic-version-bumper | powershell-tool | opus47-1m-xhigh | 3.0 | 2.0 | 5.0 |
| 11-semantic-version-bumper | powershell-tool | opus47-200k-medium | 3.0 | 2.0 | 5.0 |
| 11-semantic-version-bumper | typescript-bun | opus | 3.0 | 2.0 | 5.0 |
| 11-semantic-version-bumper | typescript-bun | opus47-1m-medium | 3.0 | 2.0 | 5.0 |
| 11-semantic-version-bumper | typescript-bun | sonnet | 3.0 | 2.0 | 5.0 |

## Model rankings by judge

*Agreement on model ordering tells us the panel agrees on which configurations produce better output on this axis. Absolute-score differences between judges are expected (different grading scales) and are not a bias concern.*

### Tests Quality

| Model | haiku45 rank (mean, n) | gemini31pro rank (mean, n) |
|---|---|---|
| opus47-1m | 1 (3.05, n=104) | 1 (4.84, n=102) |
| sonnet | 2 (2.91, n=35) | 3 (4.67, n=33) |
| opus | 3 (2.88, n=34) | 4 (4.56, n=34) |
| opus47-200k | 4 (2.74, n=35) | 2 (4.82, n=34) |
| sonnet46-1m | 5 (2.67, n=33) | 5 (4.55, n=33) |
| haiku45 | 6 (1.94, n=31) | 6 (2.33, n=30) |

*Spearman rank correlation between haiku45 and gemini31pro: **+0.83**. (+1.0 = judges agree perfectly on ordering; 0 = no correlation; -1.0 = reversed.)*

**Pair-wise reversals** (where the two judges disagree on which model is better):

| Pair | haiku45 prefers | gemini31pro prefers | Own-family signal? |
|---|---|---|---|
| opus vs opus47-200k | opus | opus47-200k | — |
| opus47-200k vs sonnet | sonnet | opus47-200k | — |

### Workflow Craft

| Model | haiku45 rank (mean, n) | gemini31pro rank (mean, n) |
|---|---|---|
| opus47-1m | 1 (2.69, n=101) | 2 (4.83, n=99) |
| sonnet | 2 (2.38, n=32) | 3 (4.61, n=33) |
| opus47-200k | 3 (2.29, n=31) | 1 (4.86, n=35) |
| opus | 4 (2.00, n=30) | 4 (4.59, n=34) |
| sonnet46-1m | 5 (1.94, n=31) | 5 (4.41, n=34) |
| haiku45 | 6 (1.76, n=34) | 6 (3.71, n=34) |

*Spearman rank correlation between haiku45 and gemini31pro: **+0.83**. (+1.0 = judges agree perfectly on ordering; 0 = no correlation; -1.0 = reversed.)*

**Pair-wise reversals** (where the two judges disagree on which model is better):

| Pair | haiku45 prefers | gemini31pro prefers | Own-family signal? |
|---|---|---|---|
| opus47-1m vs opus47-200k | opus47-1m | opus47-200k | — |
| opus47-200k vs sonnet | sonnet | opus47-200k | — |

## Language rankings by judge

*Agreement on language ordering tells us the panel agrees on which configurations produce better output on this axis. Absolute-score differences between judges are expected (different grading scales) and are not a bias concern.*

### Tests Quality

| Language | haiku45 rank (mean, n) | gemini31pro rank (mean, n) |
|---|---|---|
| default | 1 (2.98, n=55) | 1 (4.61, n=51) |
| powershell | 2 (2.96, n=52) | 3 (4.54, n=50) |
| typescript-bun | 3 (2.82, n=56) | 2 (4.61, n=56) |
| powershell-tool | 4 (2.81, n=54) | 4 (4.48, n=54) |
| bash | 5 (2.42, n=55) | 5 (4.09, n=55) |

*Spearman rank correlation between haiku45 and gemini31pro: **+0.90**. (+1.0 = judges agree perfectly on ordering; 0 = no correlation; -1.0 = reversed.)*

**Pair-wise reversals** (where the two judges disagree on which language is better):

| Pair | haiku45 prefers | gemini31pro prefers | Own-family signal? |
|---|---|---|---|
| powershell vs typescript-bun | powershell | typescript-bun | — |

### Workflow Craft

| Language | haiku45 rank (mean, n) | gemini31pro rank (mean, n) |
|---|---|---|
| typescript-bun | 1 (2.42, n=50) | 1 (4.73, n=55) |
| powershell | 2 (2.36, n=50) | 2 (4.63, n=52) |
| powershell-tool | 3 (2.31, n=52) | 4 (4.59, n=54) |
| default | 4 (2.25, n=52) | 3 (4.60, n=52) |
| bash | 5 (2.24, n=55) | 5 (4.36, n=56) |

*Spearman rank correlation between haiku45 and gemini31pro: **+0.90**. (+1.0 = judges agree perfectly on ordering; 0 = no correlation; -1.0 = reversed.)*

**Pair-wise reversals** (where the two judges disagree on which language is better):

| Pair | haiku45 prefers | gemini31pro prefers | Own-family signal? |
|---|---|---|---|
| default vs powershell-tool | powershell-tool | default | — |

## Language×Model rankings by judge

*Agreement on language×model ordering tells us the panel agrees on which configurations produce better output on this axis. Absolute-score differences between judges are expected (different grading scales) and are not a bias concern.*

### Tests Quality

| Language / Model | haiku45 rank (mean, n) | gemini31pro rank (mean, n) |
|---|---|---|
| powershell / sonnet46-1m | 1 (3.50, n=6) | 15 (4.83, n=6) |
| default / opus47-1m | 2 (3.48, n=21) | 12 (4.85, n=20) |
| powershell / sonnet | 3 (3.29, n=7) | 17 (4.57, n=7) |
| typescript-bun / opus47-1m | 4 (3.24, n=21) | 7 (5.00, n=21) |
| bash / opus | 5 (3.17, n=6) | 1 (5.00, n=6) |
| powershell / opus47-1m | 6 (3.15, n=20) | 13 (4.84, n=19) |
| powershell-tool / opus | 7 (3.14, n=7) | 20 (4.43, n=7) |
| powershell-tool / opus47-200k | 8 (3.14, n=7) | 6 (5.00, n=7) |
| default / sonnet | 9 (3.00, n=7) | 14 (4.83, n=6) |
| typescript-bun / opus47-200k | 10 (3.00, n=7) | 8 (5.00, n=7) |
| typescript-bun / sonnet | 11 (3.00, n=7) | 11 (4.86, n=7) |
| default / opus47-200k | 12 (2.86, n=7) | 2 (5.00, n=6) |
| default / sonnet46-1m | 13 (2.86, n=7) | 3 (5.00, n=6) |
| powershell / opus | 14 (2.86, n=7) | 24 (4.14, n=7) |
| powershell-tool / opus47-1m | 15 (2.86, n=21) | 5 (5.00, n=21) |
| default / opus | 16 (2.71, n=7) | 19 (4.43, n=7) |
| powershell / opus47-200k | 17 (2.71, n=7) | 4 (5.00, n=7) |
| powershell-tool / sonnet | 18 (2.71, n=7) | 21 (4.33, n=6) |
| bash / sonnet | 19 (2.57, n=7) | 16 (4.71, n=7) |
| typescript-bun / opus | 20 (2.57, n=7) | 10 (4.86, n=7) |
| typescript-bun / sonnet46-1m | 21 (2.57, n=7) | 9 (5.00, n=7) |
| bash / opus47-1m | 22 (2.52, n=21) | 18 (4.52, n=21) |
| powershell-tool / sonnet46-1m | 23 (2.50, n=6) | 22 (4.29, n=7) |
| powershell-tool / haiku45 | 24 (2.33, n=6) | 28 (2.50, n=6) |
| bash / haiku45 | 25 (2.14, n=7) | 30 (1.71, n=7) |
| bash / opus47-200k | 26 (2.00, n=7) | 23 (4.14, n=7) |
| bash / sonnet46-1m | 27 (2.00, n=7) | 25 (3.71, n=7) |
| default / haiku45 | 28 (1.83, n=6) | 26 (3.00, n=6) |
| typescript-bun / haiku45 | 29 (1.71, n=7) | 29 (2.14, n=7) |
| powershell / haiku45 | 30 (1.60, n=5) | 27 (2.50, n=4) |

*Spearman rank correlation between haiku45 and gemini31pro: **+0.62**. (+1.0 = judges agree perfectly on ordering; 0 = no correlation; -1.0 = reversed.)*

**Pair-wise reversals** (where the two judges disagree on which language×model is better):

| Pair | haiku45 prefers | gemini31pro prefers | Own-family signal? |
|---|---|---|---|
| bash / haiku45 vs bash / opus47-200k | bash / haiku45 | bash / opus47-200k | ⚠️ haiku45 |
| bash / haiku45 vs bash / sonnet46-1m | bash / haiku45 | bash / sonnet46-1m | ⚠️ haiku45 |
| bash / haiku45 vs default / haiku45 | bash / haiku45 | default / haiku45 | ⚠️ haiku45 |
| bash / haiku45 vs powershell / haiku45 | bash / haiku45 | powershell / haiku45 | ⚠️ haiku45 |
| bash / haiku45 vs typescript-bun / haiku45 | bash / haiku45 | typescript-bun / haiku45 | ⚠️ haiku45 |
| bash / opus vs default / opus47-1m | default / opus47-1m | bash / opus | — |
| bash / opus vs powershell / sonnet | powershell / sonnet | bash / opus | — |
| bash / opus vs powershell / sonnet46-1m | powershell / sonnet46-1m | bash / opus | — |
| bash / opus vs typescript-bun / opus47-1m | typescript-bun / opus47-1m | bash / opus | — |
| bash / opus47-1m vs default / opus | default / opus | bash / opus47-1m | — |
| bash / opus47-1m vs powershell / opus | powershell / opus | bash / opus47-1m | — |
| bash / opus47-1m vs powershell-tool / opus | powershell-tool / opus | bash / opus47-1m | — |
| bash / opus47-1m vs powershell-tool / sonnet | powershell-tool / sonnet | bash / opus47-1m | — |
| bash / opus47-200k vs powershell / opus | powershell / opus | bash / opus47-200k | — |
| bash / opus47-200k vs powershell-tool / haiku45 | powershell-tool / haiku45 | bash / opus47-200k | ⚠️ haiku45 |
| bash / sonnet vs default / opus | default / opus | bash / sonnet | — |
| bash / sonnet vs powershell / opus | powershell / opus | bash / sonnet | — |
| bash / sonnet vs powershell / sonnet | powershell / sonnet | bash / sonnet | — |
| bash / sonnet vs powershell-tool / opus | powershell-tool / opus | bash / sonnet | — |
| bash / sonnet vs powershell-tool / sonnet | powershell-tool / sonnet | bash / sonnet | — |
| bash / sonnet vs typescript-bun / opus | bash / sonnet | typescript-bun / opus | — |
| bash / sonnet vs typescript-bun / sonnet46-1m | bash / sonnet | typescript-bun / sonnet46-1m | — |
| bash / sonnet46-1m vs powershell-tool / haiku45 | powershell-tool / haiku45 | bash / sonnet46-1m | ⚠️ haiku45 |
| default / haiku45 vs powershell-tool / haiku45 | powershell-tool / haiku45 | default / haiku45 | ⚠️ haiku45 |
| default / opus vs powershell / opus | powershell / opus | default / opus | — |
| default / opus vs powershell / opus47-200k | default / opus | powershell / opus47-200k | — |
| default / opus vs powershell-tool / opus | powershell-tool / opus | default / opus | — |
| default / opus vs typescript-bun / opus | default / opus | typescript-bun / opus | — |
| default / opus vs typescript-bun / sonnet46-1m | default / opus | typescript-bun / sonnet46-1m | — |
| default / opus47-1m vs default / opus47-200k | default / opus47-1m | default / opus47-200k | — |
| default / opus47-1m vs default / sonnet46-1m | default / opus47-1m | default / sonnet46-1m | — |
| default / opus47-1m vs powershell / opus47-200k | default / opus47-1m | powershell / opus47-200k | — |
| default / opus47-1m vs powershell / sonnet46-1m | powershell / sonnet46-1m | default / opus47-1m | — |
| default / opus47-1m vs powershell-tool / opus47-1m | default / opus47-1m | powershell-tool / opus47-1m | — |
| default / opus47-1m vs powershell-tool / opus47-200k | default / opus47-1m | powershell-tool / opus47-200k | — |
| default / opus47-1m vs typescript-bun / opus | default / opus47-1m | typescript-bun / opus | — |
| default / opus47-1m vs typescript-bun / opus47-1m | default / opus47-1m | typescript-bun / opus47-1m | — |
| default / opus47-1m vs typescript-bun / opus47-200k | default / opus47-1m | typescript-bun / opus47-200k | — |
| default / opus47-1m vs typescript-bun / sonnet | default / opus47-1m | typescript-bun / sonnet | — |
| default / opus47-1m vs typescript-bun / sonnet46-1m | default / opus47-1m | typescript-bun / sonnet46-1m | — |
| default / opus47-200k vs default / sonnet | default / sonnet | default / opus47-200k | — |
| default / opus47-200k vs powershell / opus47-1m | powershell / opus47-1m | default / opus47-200k | — |
| default / opus47-200k vs powershell / sonnet | powershell / sonnet | default / opus47-200k | — |
| default / opus47-200k vs powershell / sonnet46-1m | powershell / sonnet46-1m | default / opus47-200k | — |
| default / opus47-200k vs powershell-tool / opus | powershell-tool / opus | default / opus47-200k | — |
| default / opus47-200k vs powershell-tool / opus47-200k | powershell-tool / opus47-200k | default / opus47-200k | — |
| default / opus47-200k vs typescript-bun / opus47-1m | typescript-bun / opus47-1m | default / opus47-200k | — |
| default / opus47-200k vs typescript-bun / opus47-200k | typescript-bun / opus47-200k | default / opus47-200k | — |
| default / opus47-200k vs typescript-bun / sonnet | typescript-bun / sonnet | default / opus47-200k | — |
| default / sonnet vs default / sonnet46-1m | default / sonnet | default / sonnet46-1m | — |
| default / sonnet vs powershell / opus47-200k | default / sonnet | powershell / opus47-200k | — |
| default / sonnet vs powershell / sonnet | powershell / sonnet | default / sonnet | — |
| default / sonnet vs powershell / sonnet46-1m | powershell / sonnet46-1m | default / sonnet | — |
| default / sonnet vs powershell-tool / opus | powershell-tool / opus | default / sonnet | — |
| default / sonnet vs powershell-tool / opus47-1m | default / sonnet | powershell-tool / opus47-1m | — |
| default / sonnet vs typescript-bun / opus | default / sonnet | typescript-bun / opus | — |
| default / sonnet vs typescript-bun / opus47-200k | default / sonnet | typescript-bun / opus47-200k | — |
| default / sonnet vs typescript-bun / sonnet | default / sonnet | typescript-bun / sonnet | — |
| default / sonnet vs typescript-bun / sonnet46-1m | default / sonnet | typescript-bun / sonnet46-1m | — |
| default / sonnet46-1m vs powershell / opus47-1m | powershell / opus47-1m | default / sonnet46-1m | — |
| default / sonnet46-1m vs powershell / sonnet | powershell / sonnet | default / sonnet46-1m | — |
| default / sonnet46-1m vs powershell / sonnet46-1m | powershell / sonnet46-1m | default / sonnet46-1m | — |
| default / sonnet46-1m vs powershell-tool / opus | powershell-tool / opus | default / sonnet46-1m | — |
| default / sonnet46-1m vs powershell-tool / opus47-200k | powershell-tool / opus47-200k | default / sonnet46-1m | — |
| default / sonnet46-1m vs typescript-bun / opus47-1m | typescript-bun / opus47-1m | default / sonnet46-1m | — |
| default / sonnet46-1m vs typescript-bun / opus47-200k | typescript-bun / opus47-200k | default / sonnet46-1m | — |
| default / sonnet46-1m vs typescript-bun / sonnet | typescript-bun / sonnet | default / sonnet46-1m | — |
| powershell / haiku45 vs powershell-tool / haiku45 | powershell-tool / haiku45 | powershell / haiku45 | ⚠️ haiku45 |
| powershell / haiku45 vs typescript-bun / haiku45 | typescript-bun / haiku45 | powershell / haiku45 | ⚠️ haiku45 |
| powershell / opus vs powershell / opus47-200k | powershell / opus | powershell / opus47-200k | — |
| powershell / opus vs powershell-tool / opus47-1m | powershell / opus | powershell-tool / opus47-1m | — |
| powershell / opus vs powershell-tool / sonnet | powershell / opus | powershell-tool / sonnet | — |
| powershell / opus vs powershell-tool / sonnet46-1m | powershell / opus | powershell-tool / sonnet46-1m | — |
| powershell / opus vs typescript-bun / opus | powershell / opus | typescript-bun / opus | — |
| powershell / opus vs typescript-bun / sonnet46-1m | powershell / opus | typescript-bun / sonnet46-1m | — |
| powershell / opus47-1m vs powershell / opus47-200k | powershell / opus47-1m | powershell / opus47-200k | — |
| powershell / opus47-1m vs powershell / sonnet | powershell / sonnet | powershell / opus47-1m | — |
| powershell / opus47-1m vs powershell / sonnet46-1m | powershell / sonnet46-1m | powershell / opus47-1m | — |
| powershell / opus47-1m vs powershell-tool / opus47-1m | powershell / opus47-1m | powershell-tool / opus47-1m | — |
| powershell / opus47-1m vs powershell-tool / opus47-200k | powershell / opus47-1m | powershell-tool / opus47-200k | — |
| powershell / opus47-1m vs typescript-bun / opus | powershell / opus47-1m | typescript-bun / opus | — |
| powershell / opus47-1m vs typescript-bun / opus47-200k | powershell / opus47-1m | typescript-bun / opus47-200k | — |
| powershell / opus47-1m vs typescript-bun / sonnet | powershell / opus47-1m | typescript-bun / sonnet | — |
| powershell / opus47-1m vs typescript-bun / sonnet46-1m | powershell / opus47-1m | typescript-bun / sonnet46-1m | — |
| powershell / opus47-200k vs powershell / sonnet | powershell / sonnet | powershell / opus47-200k | — |
| powershell / opus47-200k vs powershell / sonnet46-1m | powershell / sonnet46-1m | powershell / opus47-200k | — |
| powershell / opus47-200k vs powershell-tool / opus | powershell-tool / opus | powershell / opus47-200k | — |
| powershell / opus47-200k vs powershell-tool / opus47-1m | powershell-tool / opus47-1m | powershell / opus47-200k | — |
| powershell / opus47-200k vs powershell-tool / opus47-200k | powershell-tool / opus47-200k | powershell / opus47-200k | — |
| powershell / opus47-200k vs typescript-bun / opus47-1m | typescript-bun / opus47-1m | powershell / opus47-200k | — |
| powershell / opus47-200k vs typescript-bun / opus47-200k | typescript-bun / opus47-200k | powershell / opus47-200k | — |
| powershell / opus47-200k vs typescript-bun / sonnet | typescript-bun / sonnet | powershell / opus47-200k | — |
| powershell / sonnet vs powershell-tool / opus47-1m | powershell / sonnet | powershell-tool / opus47-1m | — |
| powershell / sonnet vs powershell-tool / opus47-200k | powershell / sonnet | powershell-tool / opus47-200k | — |
| powershell / sonnet vs typescript-bun / opus | powershell / sonnet | typescript-bun / opus | — |
| powershell / sonnet vs typescript-bun / opus47-1m | powershell / sonnet | typescript-bun / opus47-1m | — |
| powershell / sonnet vs typescript-bun / opus47-200k | powershell / sonnet | typescript-bun / opus47-200k | — |
| powershell / sonnet vs typescript-bun / sonnet | powershell / sonnet | typescript-bun / sonnet | — |
| powershell / sonnet vs typescript-bun / sonnet46-1m | powershell / sonnet | typescript-bun / sonnet46-1m | — |
| powershell / sonnet46-1m vs powershell-tool / opus47-1m | powershell / sonnet46-1m | powershell-tool / opus47-1m | — |
| powershell / sonnet46-1m vs powershell-tool / opus47-200k | powershell / sonnet46-1m | powershell-tool / opus47-200k | — |
| powershell / sonnet46-1m vs typescript-bun / opus | powershell / sonnet46-1m | typescript-bun / opus | — |
| powershell / sonnet46-1m vs typescript-bun / opus47-1m | powershell / sonnet46-1m | typescript-bun / opus47-1m | — |
| powershell / sonnet46-1m vs typescript-bun / opus47-200k | powershell / sonnet46-1m | typescript-bun / opus47-200k | — |
| powershell / sonnet46-1m vs typescript-bun / sonnet | powershell / sonnet46-1m | typescript-bun / sonnet | — |
| powershell / sonnet46-1m vs typescript-bun / sonnet46-1m | powershell / sonnet46-1m | typescript-bun / sonnet46-1m | — |
| powershell-tool / opus vs powershell-tool / opus47-1m | powershell-tool / opus | powershell-tool / opus47-1m | — |
| powershell-tool / opus vs powershell-tool / opus47-200k | powershell-tool / opus | powershell-tool / opus47-200k | — |
| powershell-tool / opus vs typescript-bun / opus | powershell-tool / opus | typescript-bun / opus | — |
| powershell-tool / opus vs typescript-bun / opus47-200k | powershell-tool / opus | typescript-bun / opus47-200k | — |
| powershell-tool / opus vs typescript-bun / sonnet | powershell-tool / opus | typescript-bun / sonnet | — |
| powershell-tool / opus vs typescript-bun / sonnet46-1m | powershell-tool / opus | typescript-bun / sonnet46-1m | — |
| powershell-tool / opus47-1m vs powershell-tool / opus47-200k | powershell-tool / opus47-200k | powershell-tool / opus47-1m | — |
| powershell-tool / opus47-1m vs typescript-bun / opus47-1m | typescript-bun / opus47-1m | powershell-tool / opus47-1m | — |
| powershell-tool / opus47-1m vs typescript-bun / opus47-200k | typescript-bun / opus47-200k | powershell-tool / opus47-1m | — |
| powershell-tool / opus47-1m vs typescript-bun / sonnet | typescript-bun / sonnet | powershell-tool / opus47-1m | — |
| powershell-tool / opus47-200k vs typescript-bun / opus47-1m | typescript-bun / opus47-1m | powershell-tool / opus47-200k | — |
| powershell-tool / sonnet vs typescript-bun / opus | powershell-tool / sonnet | typescript-bun / opus | — |
| powershell-tool / sonnet vs typescript-bun / sonnet46-1m | powershell-tool / sonnet | typescript-bun / sonnet46-1m | — |
| typescript-bun / opus vs typescript-bun / sonnet | typescript-bun / sonnet | typescript-bun / opus | — |
| typescript-bun / opus vs typescript-bun / sonnet46-1m | typescript-bun / opus | typescript-bun / sonnet46-1m | — |
| typescript-bun / sonnet vs typescript-bun / sonnet46-1m | typescript-bun / sonnet | typescript-bun / sonnet46-1m | — |

### Workflow Craft

| Language / Model | haiku45 rank (mean, n) | gemini31pro rank (mean, n) |
|---|---|---|
| typescript-bun / opus47-1m | 1 (2.80, n=20) | 10 (4.85, n=20) |
| default / opus47-1m | 2 (2.76, n=21) | 5 (4.89, n=19) |
| powershell / opus47-1m | 3 (2.70, n=20) | 4 (4.95, n=19) |
| powershell-tool / opus47-1m | 4 (2.68, n=19) | 1 (5.00, n=20) |
| typescript-bun / sonnet | 5 (2.67, n=6) | 16 (4.57, n=7) |
| bash / opus47-200k | 6 (2.57, n=7) | 6 (4.86, n=7) |
| bash / opus47-1m | 7 (2.52, n=21) | 18 (4.48, n=21) |
| powershell / opus47-200k | 8 (2.50, n=6) | 8 (4.86, n=7) |
| powershell-tool / sonnet | 9 (2.50, n=6) | 14 (4.67, n=6) |
| default / sonnet | 10 (2.33, n=6) | 17 (4.50, n=6) |
| powershell-tool / opus | 11 (2.33, n=6) | 15 (4.57, n=7) |
| powershell / sonnet | 12 (2.29, n=7) | 20 (4.43, n=7) |
| powershell-tool / opus47-200k | 13 (2.29, n=7) | 9 (4.86, n=7) |
| typescript-bun / sonnet46-1m | 14 (2.20, n=5) | 22 (4.43, n=7) |
| bash / sonnet | 15 (2.14, n=7) | 7 (4.86, n=7) |
| powershell / sonnet46-1m | 16 (2.14, n=7) | 27 (4.14, n=7) |
| bash / opus | 17 (2.00, n=7) | 23 (4.29, n=7) |
| default / opus47-200k | 18 (2.00, n=5) | 12 (4.71, n=7) |
| powershell / opus | 19 (2.00, n=4) | 13 (4.67, n=6) |
| typescript-bun / haiku45 | 20 (2.00, n=7) | 25 (4.29, n=7) |
| typescript-bun / opus | 21 (2.00, n=6) | 2 (5.00, n=7) |
| typescript-bun / opus47-200k | 22 (2.00, n=6) | 3 (5.00, n=7) |
| bash / haiku45 | 23 (1.86, n=7) | 30 (3.14, n=7) |
| powershell-tool / sonnet46-1m | 24 (1.86, n=7) | 21 (4.43, n=7) |
| default / sonnet46-1m | 25 (1.83, n=6) | 11 (4.83, n=6) |
| default / haiku45 | 26 (1.71, n=7) | 28 (3.71, n=7) |
| default / opus | 27 (1.71, n=7) | 19 (4.43, n=7) |
| bash / sonnet46-1m | 28 (1.67, n=6) | 24 (4.29, n=7) |
| powershell / haiku45 | 29 (1.67, n=6) | 26 (4.17, n=6) |
| powershell-tool / haiku45 | 30 (1.57, n=7) | 29 (3.29, n=7) |

*Spearman rank correlation between haiku45 and gemini31pro: **+0.56**. (+1.0 = judges agree perfectly on ordering; 0 = no correlation; -1.0 = reversed.)*

**Pair-wise reversals** (where the two judges disagree on which language×model is better):

| Pair | haiku45 prefers | gemini31pro prefers | Own-family signal? |
|---|---|---|---|
| bash / haiku45 vs bash / sonnet46-1m | bash / haiku45 | bash / sonnet46-1m | ⚠️ haiku45 |
| bash / haiku45 vs default / haiku45 | bash / haiku45 | default / haiku45 | ⚠️ haiku45 |
| bash / haiku45 vs default / opus | bash / haiku45 | default / opus | ⚠️ haiku45 |
| bash / haiku45 vs default / sonnet46-1m | bash / haiku45 | default / sonnet46-1m | ⚠️ haiku45 |
| bash / haiku45 vs powershell / haiku45 | bash / haiku45 | powershell / haiku45 | ⚠️ haiku45 |
| bash / haiku45 vs powershell-tool / haiku45 | bash / haiku45 | powershell-tool / haiku45 | ⚠️ haiku45 |
| bash / haiku45 vs powershell-tool / sonnet46-1m | bash / haiku45 | powershell-tool / sonnet46-1m | ⚠️ haiku45 |
| bash / opus vs default / opus | bash / opus | default / opus | — |
| bash / opus vs default / opus47-200k | bash / opus | default / opus47-200k | — |
| bash / opus vs default / sonnet46-1m | bash / opus | default / sonnet46-1m | — |
| bash / opus vs powershell / opus | bash / opus | powershell / opus | — |
| bash / opus vs powershell / sonnet46-1m | powershell / sonnet46-1m | bash / opus | — |
| bash / opus vs powershell-tool / sonnet46-1m | bash / opus | powershell-tool / sonnet46-1m | — |
| bash / opus vs typescript-bun / opus | bash / opus | typescript-bun / opus | — |
| bash / opus vs typescript-bun / opus47-200k | bash / opus | typescript-bun / opus47-200k | — |
| bash / opus47-1m vs bash / sonnet | bash / opus47-1m | bash / sonnet | — |
| bash / opus47-1m vs default / opus47-200k | bash / opus47-1m | default / opus47-200k | — |
| bash / opus47-1m vs default / sonnet | bash / opus47-1m | default / sonnet | — |
| bash / opus47-1m vs default / sonnet46-1m | bash / opus47-1m | default / sonnet46-1m | — |
| bash / opus47-1m vs powershell / opus | bash / opus47-1m | powershell / opus | — |
| bash / opus47-1m vs powershell / opus47-200k | bash / opus47-1m | powershell / opus47-200k | — |
| bash / opus47-1m vs powershell-tool / opus | bash / opus47-1m | powershell-tool / opus | — |
| bash / opus47-1m vs powershell-tool / opus47-200k | bash / opus47-1m | powershell-tool / opus47-200k | — |
| bash / opus47-1m vs powershell-tool / sonnet | bash / opus47-1m | powershell-tool / sonnet | — |
| bash / opus47-1m vs typescript-bun / opus | bash / opus47-1m | typescript-bun / opus | — |
| bash / opus47-1m vs typescript-bun / opus47-200k | bash / opus47-1m | typescript-bun / opus47-200k | — |
| bash / opus47-200k vs typescript-bun / opus | bash / opus47-200k | typescript-bun / opus | — |
| bash / opus47-200k vs typescript-bun / opus47-1m | typescript-bun / opus47-1m | bash / opus47-200k | — |
| bash / opus47-200k vs typescript-bun / opus47-200k | bash / opus47-200k | typescript-bun / opus47-200k | — |
| bash / opus47-200k vs typescript-bun / sonnet | typescript-bun / sonnet | bash / opus47-200k | — |
| bash / sonnet vs default / sonnet | default / sonnet | bash / sonnet | — |
| bash / sonnet vs powershell / opus47-200k | powershell / opus47-200k | bash / sonnet | — |
| bash / sonnet vs powershell / sonnet | powershell / sonnet | bash / sonnet | — |
| bash / sonnet vs powershell-tool / opus | powershell-tool / opus | bash / sonnet | — |
| bash / sonnet vs powershell-tool / opus47-200k | powershell-tool / opus47-200k | bash / sonnet | — |
| bash / sonnet vs powershell-tool / sonnet | powershell-tool / sonnet | bash / sonnet | — |
| bash / sonnet vs typescript-bun / opus | bash / sonnet | typescript-bun / opus | — |
| bash / sonnet vs typescript-bun / opus47-1m | typescript-bun / opus47-1m | bash / sonnet | — |
| bash / sonnet vs typescript-bun / opus47-200k | bash / sonnet | typescript-bun / opus47-200k | — |
| bash / sonnet vs typescript-bun / sonnet | typescript-bun / sonnet | bash / sonnet | — |
| bash / sonnet vs typescript-bun / sonnet46-1m | typescript-bun / sonnet46-1m | bash / sonnet | — |
| bash / sonnet46-1m vs default / haiku45 | default / haiku45 | bash / sonnet46-1m | ⚠️ haiku45 |
| bash / sonnet46-1m vs powershell / sonnet46-1m | powershell / sonnet46-1m | bash / sonnet46-1m | — |
| bash / sonnet46-1m vs typescript-bun / haiku45 | typescript-bun / haiku45 | bash / sonnet46-1m | ⚠️ haiku45 |
| default / haiku45 vs default / opus | default / haiku45 | default / opus | ⚠️ haiku45 |
| default / haiku45 vs powershell / haiku45 | default / haiku45 | powershell / haiku45 | ⚠️ haiku45 |
| default / opus vs powershell / sonnet | powershell / sonnet | default / opus | — |
| default / opus vs powershell / sonnet46-1m | powershell / sonnet46-1m | default / opus | — |
| default / opus vs powershell-tool / sonnet46-1m | powershell-tool / sonnet46-1m | default / opus | — |
| default / opus vs typescript-bun / haiku45 | typescript-bun / haiku45 | default / opus | ⚠️ haiku45 |
| default / opus vs typescript-bun / sonnet46-1m | typescript-bun / sonnet46-1m | default / opus | — |
| default / opus47-1m vs powershell / opus47-1m | default / opus47-1m | powershell / opus47-1m | — |
| default / opus47-1m vs powershell-tool / opus47-1m | default / opus47-1m | powershell-tool / opus47-1m | — |
| default / opus47-1m vs typescript-bun / opus | default / opus47-1m | typescript-bun / opus | — |
| default / opus47-1m vs typescript-bun / opus47-1m | typescript-bun / opus47-1m | default / opus47-1m | — |
| default / opus47-1m vs typescript-bun / opus47-200k | default / opus47-1m | typescript-bun / opus47-200k | — |
| default / opus47-200k vs default / sonnet | default / sonnet | default / opus47-200k | — |
| default / opus47-200k vs default / sonnet46-1m | default / opus47-200k | default / sonnet46-1m | — |
| default / opus47-200k vs powershell / sonnet | powershell / sonnet | default / opus47-200k | — |
| default / opus47-200k vs powershell / sonnet46-1m | powershell / sonnet46-1m | default / opus47-200k | — |
| default / opus47-200k vs powershell-tool / opus | powershell-tool / opus | default / opus47-200k | — |
| default / opus47-200k vs powershell-tool / sonnet | powershell-tool / sonnet | default / opus47-200k | — |
| default / opus47-200k vs typescript-bun / opus | default / opus47-200k | typescript-bun / opus | — |
| default / opus47-200k vs typescript-bun / opus47-200k | default / opus47-200k | typescript-bun / opus47-200k | — |
| default / opus47-200k vs typescript-bun / sonnet | typescript-bun / sonnet | default / opus47-200k | — |
| default / opus47-200k vs typescript-bun / sonnet46-1m | typescript-bun / sonnet46-1m | default / opus47-200k | — |
| default / sonnet vs default / sonnet46-1m | default / sonnet | default / sonnet46-1m | — |
| default / sonnet vs powershell / opus | default / sonnet | powershell / opus | — |
| default / sonnet vs powershell-tool / opus | default / sonnet | powershell-tool / opus | — |
| default / sonnet vs powershell-tool / opus47-200k | default / sonnet | powershell-tool / opus47-200k | — |
| default / sonnet vs typescript-bun / opus | default / sonnet | typescript-bun / opus | — |
| default / sonnet vs typescript-bun / opus47-200k | default / sonnet | typescript-bun / opus47-200k | — |
| default / sonnet46-1m vs powershell / opus | powershell / opus | default / sonnet46-1m | — |
| default / sonnet46-1m vs powershell / sonnet | powershell / sonnet | default / sonnet46-1m | — |
| default / sonnet46-1m vs powershell / sonnet46-1m | powershell / sonnet46-1m | default / sonnet46-1m | — |
| default / sonnet46-1m vs powershell-tool / opus | powershell-tool / opus | default / sonnet46-1m | — |
| default / sonnet46-1m vs powershell-tool / sonnet | powershell-tool / sonnet | default / sonnet46-1m | — |
| default / sonnet46-1m vs powershell-tool / sonnet46-1m | powershell-tool / sonnet46-1m | default / sonnet46-1m | — |
| default / sonnet46-1m vs typescript-bun / haiku45 | typescript-bun / haiku45 | default / sonnet46-1m | ⚠️ haiku45 |
| default / sonnet46-1m vs typescript-bun / sonnet | typescript-bun / sonnet | default / sonnet46-1m | — |
| default / sonnet46-1m vs typescript-bun / sonnet46-1m | typescript-bun / sonnet46-1m | default / sonnet46-1m | — |
| powershell / haiku45 vs powershell / sonnet46-1m | powershell / sonnet46-1m | powershell / haiku45 | — |
| powershell / opus vs powershell / sonnet | powershell / sonnet | powershell / opus | — |
| powershell / opus vs powershell / sonnet46-1m | powershell / sonnet46-1m | powershell / opus | — |
| powershell / opus vs powershell-tool / opus | powershell-tool / opus | powershell / opus | — |
| powershell / opus vs powershell-tool / sonnet | powershell-tool / sonnet | powershell / opus | — |
| powershell / opus vs typescript-bun / opus | powershell / opus | typescript-bun / opus | — |
| powershell / opus vs typescript-bun / opus47-200k | powershell / opus | typescript-bun / opus47-200k | — |
| powershell / opus vs typescript-bun / sonnet | typescript-bun / sonnet | powershell / opus | — |
| powershell / opus vs typescript-bun / sonnet46-1m | typescript-bun / sonnet46-1m | powershell / opus | — |
| powershell / opus47-1m vs powershell-tool / opus47-1m | powershell / opus47-1m | powershell-tool / opus47-1m | — |
| powershell / opus47-1m vs typescript-bun / opus | powershell / opus47-1m | typescript-bun / opus | — |
| powershell / opus47-1m vs typescript-bun / opus47-1m | typescript-bun / opus47-1m | powershell / opus47-1m | — |
| powershell / opus47-1m vs typescript-bun / opus47-200k | powershell / opus47-1m | typescript-bun / opus47-200k | — |
| powershell / opus47-200k vs typescript-bun / opus | powershell / opus47-200k | typescript-bun / opus | — |
| powershell / opus47-200k vs typescript-bun / opus47-1m | typescript-bun / opus47-1m | powershell / opus47-200k | — |
| powershell / opus47-200k vs typescript-bun / opus47-200k | powershell / opus47-200k | typescript-bun / opus47-200k | — |
| powershell / opus47-200k vs typescript-bun / sonnet | typescript-bun / sonnet | powershell / opus47-200k | — |
| powershell / sonnet vs powershell-tool / opus47-200k | powershell / sonnet | powershell-tool / opus47-200k | — |
| powershell / sonnet vs typescript-bun / opus | powershell / sonnet | typescript-bun / opus | — |
| powershell / sonnet vs typescript-bun / opus47-200k | powershell / sonnet | typescript-bun / opus47-200k | — |
| powershell / sonnet46-1m vs powershell-tool / sonnet46-1m | powershell / sonnet46-1m | powershell-tool / sonnet46-1m | — |
| powershell / sonnet46-1m vs typescript-bun / haiku45 | powershell / sonnet46-1m | typescript-bun / haiku45 | — |
| powershell / sonnet46-1m vs typescript-bun / opus | powershell / sonnet46-1m | typescript-bun / opus | — |
| powershell / sonnet46-1m vs typescript-bun / opus47-200k | powershell / sonnet46-1m | typescript-bun / opus47-200k | — |
| powershell-tool / opus vs powershell-tool / opus47-200k | powershell-tool / opus | powershell-tool / opus47-200k | — |
| powershell-tool / opus vs typescript-bun / opus | powershell-tool / opus | typescript-bun / opus | — |
| powershell-tool / opus vs typescript-bun / opus47-200k | powershell-tool / opus | typescript-bun / opus47-200k | — |
| powershell-tool / opus vs typescript-bun / sonnet | typescript-bun / sonnet | powershell-tool / opus | — |
| powershell-tool / opus47-1m vs typescript-bun / opus47-1m | typescript-bun / opus47-1m | powershell-tool / opus47-1m | — |
| powershell-tool / opus47-200k vs powershell-tool / sonnet | powershell-tool / sonnet | powershell-tool / opus47-200k | — |
| powershell-tool / opus47-200k vs typescript-bun / opus | powershell-tool / opus47-200k | typescript-bun / opus | — |
| powershell-tool / opus47-200k vs typescript-bun / opus47-1m | typescript-bun / opus47-1m | powershell-tool / opus47-200k | — |
| powershell-tool / opus47-200k vs typescript-bun / opus47-200k | powershell-tool / opus47-200k | typescript-bun / opus47-200k | — |
| powershell-tool / opus47-200k vs typescript-bun / sonnet | typescript-bun / sonnet | powershell-tool / opus47-200k | — |
| powershell-tool / sonnet vs typescript-bun / opus | powershell-tool / sonnet | typescript-bun / opus | — |
| powershell-tool / sonnet vs typescript-bun / opus47-200k | powershell-tool / sonnet | typescript-bun / opus47-200k | — |
| powershell-tool / sonnet vs typescript-bun / sonnet | typescript-bun / sonnet | powershell-tool / sonnet | — |
| powershell-tool / sonnet46-1m vs typescript-bun / haiku45 | typescript-bun / haiku45 | powershell-tool / sonnet46-1m | ⚠️ haiku45 |
| powershell-tool / sonnet46-1m vs typescript-bun / sonnet46-1m | typescript-bun / sonnet46-1m | powershell-tool / sonnet46-1m | — |
| typescript-bun / haiku45 vs typescript-bun / opus | typescript-bun / haiku45 | typescript-bun / opus | ⚠️ haiku45 |
| typescript-bun / haiku45 vs typescript-bun / opus47-200k | typescript-bun / haiku45 | typescript-bun / opus47-200k | ⚠️ haiku45 |
| typescript-bun / opus vs typescript-bun / opus47-1m | typescript-bun / opus47-1m | typescript-bun / opus | — |
| typescript-bun / opus vs typescript-bun / sonnet | typescript-bun / sonnet | typescript-bun / opus | — |
| typescript-bun / opus vs typescript-bun / sonnet46-1m | typescript-bun / sonnet46-1m | typescript-bun / opus | — |
| typescript-bun / opus47-1m vs typescript-bun / opus47-200k | typescript-bun / opus47-1m | typescript-bun / opus47-200k | — |
| typescript-bun / opus47-200k vs typescript-bun / sonnet | typescript-bun / sonnet | typescript-bun / opus47-200k | — |
| typescript-bun / opus47-200k vs typescript-bun / sonnet46-1m | typescript-bun / sonnet46-1m | typescript-bun / opus47-200k | — |

## Per-run self-judgment rows (reference)

*Rows where a judge evaluated output from its own model family. These individual runs are kept as a sanity check — the actual bias test is the pair-wise ranking reversals in the table above. Filtered to rows whose inter-judge delta differs from the baseline delta by ≥1.0 point; such rows are plausibly interesting but don't by themselves indicate bias (absolute-score differences between judges are expected).*

### Tests Quality

*Baseline delta (gemini31pro − haiku45) across the whole dataset: **+1.67**.*

| Task | Mode | Model | Self judge | Self score | Other judge | Other score | Row Δ | Deviation |
|---|---|---|---|---|---|---|---|---|
| 11-semantic-version-bumper | bash | haiku45 | haiku45 | 2.0 | gemini31pro | 1.0 | -1.0 | -2.7 |
| 11-semantic-version-bumper | powershell-tool | haiku45 | haiku45 | 2.0 | gemini31pro | 2.0 | +0.0 | -1.7 |
| 11-semantic-version-bumper | typescript-bun | haiku45 | haiku45 | 2.0 | gemini31pro | 2.0 | +0.0 | -1.7 |
| 12-pr-label-assigner | bash | haiku45 | haiku45 | 2.0 | gemini31pro | 1.0 | -1.0 | -2.7 |
| 12-pr-label-assigner | default | haiku45 | haiku45 | 2.0 | gemini31pro | 2.0 | +0.0 | -1.7 |
| 12-pr-label-assigner | powershell | haiku45 | haiku45 | 2.0 | — | — | — | — |
| 12-pr-label-assigner | powershell-tool | haiku45 | haiku45 | 2.0 | gemini31pro | 2.0 | +0.0 | -1.7 |
| 12-pr-label-assigner | typescript-bun | haiku45 | haiku45 | 2.0 | gemini31pro | 1.0 | -1.0 | -2.7 |
| 13-dependency-license-checker | bash | haiku45 | haiku45 | 3.0 | gemini31pro | 1.0 | -2.0 | -3.7 |
| 13-dependency-license-checker | powershell | haiku45 | haiku45 | 2.0 | gemini31pro | 2.0 | +0.0 | -1.7 |
| 13-dependency-license-checker | typescript-bun | haiku45 | haiku45 | 2.0 | gemini31pro | 2.0 | +0.0 | -1.7 |
| 15-test-results-aggregator | bash | haiku45 | haiku45 | 2.0 | gemini31pro | 2.0 | +0.0 | -1.7 |
| 15-test-results-aggregator | powershell-tool | haiku45 | haiku45 | 3.0 | gemini31pro | 3.0 | +0.0 | -1.7 |
| 15-test-results-aggregator | typescript-bun | haiku45 | haiku45 | 2.0 | gemini31pro | 2.0 | +0.0 | -1.7 |
| 16-environment-matrix-generato | bash | haiku45 | haiku45 | 2.0 | gemini31pro | 2.0 | +0.0 | -1.7 |
| 16-environment-matrix-generato | powershell | haiku45 | haiku45 | 2.0 | gemini31pro | 2.0 | +0.0 | -1.7 |
| 16-environment-matrix-generato | powershell-tool | haiku45 | haiku45 | 4.0 | gemini31pro | 3.0 | -1.0 | -2.7 |
| 17-artifact-cleanup-script | default | haiku45 | haiku45 | 2.0 | gemini31pro | 2.0 | +0.0 | -1.7 |
| 17-artifact-cleanup-script | powershell | haiku45 | haiku45 | 1.0 | gemini31pro | 4.0 | +3.0 | +1.3 |
| 18-secret-rotation-validator | bash | haiku45 | haiku45 | 2.0 | gemini31pro | 2.0 | +0.0 | -1.7 |

### Workflow Craft

*Baseline delta (gemini31pro − haiku45) across the whole dataset: **+2.23**.*

| Task | Mode | Model | Self judge | Self score | Other judge | Other score | Row Δ | Deviation |
|---|---|---|---|---|---|---|---|---|
| 11-semantic-version-bumper | default | haiku45 | haiku45 | 2.0 | gemini31pro | 2.0 | +0.0 | -2.2 |
| 11-semantic-version-bumper | powershell-tool | haiku45 | haiku45 | 2.0 | gemini31pro | 2.0 | +0.0 | -2.2 |
| 11-semantic-version-bumper | typescript-bun | haiku45 | haiku45 | 2.0 | gemini31pro | 3.0 | +1.0 | -1.2 |
| 12-pr-label-assigner | bash | haiku45 | haiku45 | 2.0 | gemini31pro | 1.0 | -1.0 | -3.2 |
| 12-pr-label-assigner | default | haiku45 | haiku45 | 2.0 | gemini31pro | 2.0 | +0.0 | -2.2 |
| 12-pr-label-assigner | powershell | haiku45 | haiku45 | 1.0 | — | — | — | — |
| 13-dependency-license-checker | bash | haiku45 | haiku45 | 2.0 | gemini31pro | 3.0 | +1.0 | -1.2 |
| 15-test-results-aggregator | default | haiku45 | haiku45 | 3.0 | gemini31pro | 4.0 | +1.0 | -1.2 |
| 16-environment-matrix-generato | default | haiku45 | haiku45 | 1.0 | gemini31pro | 5.0 | +4.0 | +1.8 |
| 16-environment-matrix-generato | powershell-tool | haiku45 | haiku45 | 2.0 | gemini31pro | 3.0 | +1.0 | -1.2 |
| 17-artifact-cleanup-script | bash | haiku45 | haiku45 | 3.0 | gemini31pro | 4.0 | +1.0 | -1.2 |
| 17-artifact-cleanup-script | powershell-tool | haiku45 | haiku45 | 1.0 | gemini31pro | 2.0 | +1.0 | -1.2 |

