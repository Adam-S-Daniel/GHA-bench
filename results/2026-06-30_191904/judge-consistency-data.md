# Judge Consistency Data

*Raw panel-of-judges data plus a rankings-focused Quality Analysis. Backs the merged Conclusions and Judge Consistency Summary in the corresponding [`results.md`](results.md).*

## Notes

- **Generated:** 2026-07-03 08:52:45 AM ET
- **Source:** `/home/passp/repos/GHA-bench/results/2026-06-30_191904`
- **Judges present:** haiku45, gemini31pro
- **Score conventions:** Scores shown are the `overall` dimension from each judge (1-5). Δ column is the second judge minus the first; positive = second judge is more generous.

## Quality Analysis

Sonnet at 1M context with medium effort produces the strongest workflow deliverables, ranked #1 by both judges with perfect agreement on model ordering (ρ = +1.00 on Workflow Craft, zero reversals). PowerShell is the best language fit for that model on shipped workflows, taking the top language×model slot under both judges, and PowerShell also tops the Tests Quality language ranking under both.

- **Top performer**: sonnet5-1m-medium leads Workflow Craft under both judges (ρ = +1.00, no reversals) and takes #1 on Tests Quality under Gemini, with a single reversal from Haiku on the model axis.
- **Best by language**: PowerShell / sonnet5-1m is the #1 language×model cell on Workflow Craft under both judges, and Haiku's #1 on Tests Quality (tied-top for Gemini at a 5.00 average).
- **Effort tier**: low-effort Sonnet trails on both axes for both judges — 2.10 / 4.00 on Workflow Craft, 2.50 / 2.87 on Tests Quality — and finishes last in every model ranking presented.
- **Where rankings diverge**: Bash is Haiku's worst Tests Quality language but Gemini's second-best (three Bash reversals against Haiku); the default (Python) language shows the same pattern on Workflow Craft, ranked #1 by Gemini and #4 by Haiku.

*Provenance:* `claude-opus-4-7[1m]` at effort `xhigh` via Claude CLI (from cache); 5 in / 4445 out tokens, $0.2939. Prompt: [`QUALITY_ANALYSIS_SYSTEM_PROMPT`](../../judge_consistency_report.py).

## Campaign summary

### Tests Quality

| Scope | n | haiku45 ovr | gemini31pro ovr | Δ(gemini31pro−haiku45) |
|---|---|---|---|---|
| all | 100 | 2.96 | 3.92 | +0.96 |

### Workflow Craft

| Scope | n | haiku45 ovr | gemini31pro ovr | Δ(gemini31pro−haiku45) |
|---|---|---|---|---|
| all | 95 | 2.66 | 4.45 | +1.79 |

## By task

### Tests Quality

| Task | n | haiku45 ovr | gemini31pro ovr | Δ(gemini31pro−haiku45) |
|---|---|---|---|---|
| 11-semantic-version-bumper | 15 | 2.93 | 4.33 | +1.40 |
| 12-pr-label-assigner | 15 | 3.20 | 3.80 | +0.60 |
| 13-dependency-license-checker | 14 | 3.14 | 4.07 | +0.93 |
| 15-test-results-aggregator | 14 | 2.57 | 3.79 | +1.21 |
| 16-environment-matrix-generator | 14 | 3.00 | 3.93 | +0.93 |
| 17-artifact-cleanup-script | 14 | 2.79 | 3.57 | +0.79 |
| 18-secret-rotation-validator | 14 | 3.07 | 3.93 | +0.86 |

### Workflow Craft

| Task | n | haiku45 ovr | gemini31pro ovr | Δ(gemini31pro−haiku45) |
|---|---|---|---|---|
| 11-semantic-version-bumper | 15 | 2.80 | 4.40 | +1.60 |
| 12-pr-label-assigner | 14 | 2.71 | 4.50 | +1.79 |
| 13-dependency-license-checker | 14 | 3.14 | 4.79 | +1.64 |
| 15-test-results-aggregator | 14 | 2.36 | 4.43 | +2.07 |
| 16-environment-matrix-generator | 12 | 2.75 | 4.25 | +1.50 |
| 17-artifact-cleanup-script | 13 | 2.54 | 4.62 | +2.08 |
| 18-secret-rotation-validator | 13 | 2.31 | 4.15 | +1.85 |

## By language mode

### Tests Quality

| Mode | n | haiku45 ovr | gemini31pro ovr | Δ(gemini31pro−haiku45) |
|---|---|---|---|---|
| bash | 21 | 2.81 | 4.24 | +1.43 |
| default | 21 | 2.95 | 3.48 | +0.52 |
| powershell | 21 | 3.14 | 4.38 | +1.24 |
| powershell-tool | 16 | 3.00 | 4.12 | +1.12 |
| typescript-bun | 21 | 2.90 | 3.43 | +0.52 |

### Workflow Craft

| Mode | n | haiku45 ovr | gemini31pro ovr | Δ(gemini31pro−haiku45) |
|---|---|---|---|---|
| bash | 20 | 2.55 | 4.20 | +1.65 |
| default | 20 | 2.60 | 4.70 | +2.10 |
| powershell | 20 | 2.75 | 4.40 | +1.65 |
| powershell-tool | 14 | 2.79 | 4.57 | +1.79 |
| typescript-bun | 21 | 2.67 | 4.43 | +1.76 |

## By model + effort

### Tests Quality

| Model-Effort | n | haiku45 ovr | gemini31pro ovr | Δ(gemini31pro−haiku45) |
|---|---|---|---|---|
| sonnet5 | 35 | 3.46 | 4.60 | +1.14 |
| sonnet5-1m-medium | 35 | 2.86 | 4.14 | +1.29 |
| sonnet5-low | 30 | 2.50 | 2.87 | +0.37 |

### Workflow Craft

| Model-Effort | n | haiku45 ovr | gemini31pro ovr | Δ(gemini31pro−haiku45) |
|---|---|---|---|---|
| sonnet5 | 33 | 3.09 | 4.70 | +1.61 |
| sonnet5-1m-medium | 33 | 2.73 | 4.61 | +1.88 |
| sonnet5-low | 29 | 2.10 | 4.00 | +1.90 |

## Disagreement hotspots (panel span ≥ 2 on overall)

### Tests Quality

| Task | Mode | Model | Span | haiku45 ovr | gemini31pro ovr |
|---|---|---|---|---|---|
| 11-semantic-version-bumper | powershell-tool | sonnet5-low | 3.0 | 2.0 | 5.0 |
| 11-semantic-version-bumper | typescript-bun | sonnet5-1m-medium | 3.0 | 2.0 | 5.0 |
| 13-dependency-license-checker | bash | sonnet5-1m-medium | 3.0 | 2.0 | 5.0 |
| 15-test-results-aggregator | bash | sonnet5-1m-medium | 3.0 | 2.0 | 5.0 |
| 15-test-results-aggregator | powershell | sonnet5-1m-medium | 3.0 | 2.0 | 5.0 |
| 15-test-results-aggregator | powershell-tool | sonnet5 | 3.0 | 2.0 | 5.0 |
| 15-test-results-aggregator | powershell-tool | sonnet5-1m-medium | 3.0 | 2.0 | 5.0 |
| 17-artifact-cleanup-script | bash | sonnet5-1m-medium | 3.0 | 2.0 | 5.0 |
| 18-secret-rotation-validator | default | sonnet5-low | 3.0 | 4.0 | 1.0 |
| 18-secret-rotation-validator | powershell | sonnet5-1m-medium | 3.0 | 2.0 | 5.0 |
| 18-secret-rotation-validator | typescript-bun | sonnet5-1m-medium | 3.0 | 2.0 | 5.0 |
| 11-semantic-version-bumper | bash | sonnet5-1m-medium | 2.0 | 3.0 | 5.0 |
| 11-semantic-version-bumper | bash | sonnet5-low | 2.0 | 3.0 | 5.0 |
| 11-semantic-version-bumper | default | sonnet5-1m-medium | 2.0 | 3.0 | 5.0 |
| 11-semantic-version-bumper | powershell | sonnet5 | 2.0 | 3.0 | 5.0 |
| 11-semantic-version-bumper | powershell-tool | sonnet5 | 2.0 | 3.0 | 5.0 |
| 12-pr-label-assigner | typescript-bun | sonnet5-1m-medium | 2.0 | 3.0 | 5.0 |
| 13-dependency-license-checker | bash | sonnet5 | 2.0 | 3.0 | 5.0 |
| 13-dependency-license-checker | default | sonnet5 | 2.0 | 2.0 | 4.0 |
| 13-dependency-license-checker | powershell | sonnet5-1m-medium | 2.0 | 3.0 | 5.0 |
| 16-environment-matrix-generato | bash | sonnet5 | 2.0 | 3.0 | 5.0 |
| 16-environment-matrix-generato | bash | sonnet5-1m-medium | 2.0 | 3.0 | 5.0 |
| 16-environment-matrix-generato | default | sonnet5-1m-medium | 2.0 | 3.0 | 5.0 |
| 16-environment-matrix-generato | powershell-tool | sonnet5-1m-medium | 2.0 | 3.0 | 5.0 |
| 17-artifact-cleanup-script | bash | sonnet5 | 2.0 | 3.0 | 5.0 |

### Workflow Craft

| Task | Mode | Model | Span | haiku45 ovr | gemini31pro ovr |
|---|---|---|---|---|---|
| 15-test-results-aggregator | typescript-bun | sonnet5-1m-medium | 4.0 | 1.0 | 5.0 |
| 11-semantic-version-bumper | default | sonnet5 | 3.0 | 2.0 | 5.0 |
| 11-semantic-version-bumper | typescript-bun | sonnet5-low | 3.0 | 1.0 | 4.0 |
| 12-pr-label-assigner | bash | sonnet5-1m-medium | 3.0 | 2.0 | 5.0 |
| 12-pr-label-assigner | default | sonnet5 | 3.0 | 2.0 | 5.0 |
| 12-pr-label-assigner | default | sonnet5-low | 3.0 | 2.0 | 5.0 |
| 12-pr-label-assigner | powershell | sonnet5 | 3.0 | 2.0 | 5.0 |
| 12-pr-label-assigner | powershell-tool | sonnet5-low | 3.0 | 1.0 | 4.0 |
| 13-dependency-license-checker | default | sonnet5 | 3.0 | 2.0 | 5.0 |
| 13-dependency-license-checker | default | sonnet5-low | 3.0 | 2.0 | 5.0 |
| 13-dependency-license-checker | powershell | sonnet5-low | 3.0 | 1.0 | 4.0 |
| 13-dependency-license-checker | typescript-bun | sonnet5-low | 3.0 | 2.0 | 5.0 |
| 15-test-results-aggregator | bash | sonnet5 | 3.0 | 2.0 | 5.0 |
| 15-test-results-aggregator | default | sonnet5 | 3.0 | 2.0 | 5.0 |
| 15-test-results-aggregator | powershell | sonnet5 | 3.0 | 2.0 | 5.0 |
| 15-test-results-aggregator | typescript-bun | sonnet5 | 3.0 | 2.0 | 5.0 |
| 16-environment-matrix-generato | bash | sonnet5 | 3.0 | 2.0 | 5.0 |
| 16-environment-matrix-generato | powershell-tool | sonnet5-1m-medium | 3.0 | 2.0 | 5.0 |
| 17-artifact-cleanup-script | bash | sonnet5-1m-medium | 3.0 | 2.0 | 5.0 |
| 17-artifact-cleanup-script | default | sonnet5 | 3.0 | 2.0 | 5.0 |
| 17-artifact-cleanup-script | default | sonnet5-1m-medium | 3.0 | 2.0 | 5.0 |
| 17-artifact-cleanup-script | default | sonnet5-low | 3.0 | 2.0 | 5.0 |
| 17-artifact-cleanup-script | powershell | sonnet5-1m-medium | 3.0 | 2.0 | 5.0 |
| 17-artifact-cleanup-script | powershell | sonnet5-low | 3.0 | 2.0 | 5.0 |
| 17-artifact-cleanup-script | powershell-tool | sonnet5-1m-medium | 3.0 | 2.0 | 5.0 |

## Model rankings by judge

*Agreement on model ordering tells us the panel agrees on which configurations produce better output on this axis. Absolute-score differences between judges are expected (different grading scales) and are not a bias concern.*

### Tests Quality

| Model | haiku45 rank (mean, n) | gemini31pro rank (mean, n) |
|---|---|---|
| sonnet5 | 1 (3.02, n=65) | 2 (3.80, n=65) |
| sonnet5-1m | 2 (2.86, n=35) | 1 (4.14, n=35) |

*Spearman rank correlation between haiku45 and gemini31pro: **-1.00**. (+1.0 = judges agree perfectly on ordering; 0 = no correlation; -1.0 = reversed.)*

**Pair-wise reversals** (where the two judges disagree on which model is better):

| Pair | haiku45 prefers | gemini31pro prefers | Own-family signal? |
|---|---|---|---|
| sonnet5 vs sonnet5-1m | sonnet5 | sonnet5-1m | — |

### Workflow Craft

| Model | haiku45 rank (mean, n) | gemini31pro rank (mean, n) |
|---|---|---|
| sonnet5-1m | 1 (2.73, n=33) | 1 (4.63, n=35) |
| sonnet5 | 2 (2.63, n=62) | 2 (4.40, n=65) |

*Spearman rank correlation between haiku45 and gemini31pro: **+1.00**. (+1.0 = judges agree perfectly on ordering; 0 = no correlation; -1.0 = reversed.)*

*No pair-wise reversals — both judges agree on every model-vs-model ordering.*

## Language rankings by judge

*Agreement on language ordering tells us the panel agrees on which configurations produce better output on this axis. Absolute-score differences between judges are expected (different grading scales) and are not a bias concern.*

### Tests Quality

| Language | haiku45 rank (mean, n) | gemini31pro rank (mean, n) |
|---|---|---|
| powershell | 1 (3.14, n=21) | 1 (4.38, n=21) |
| powershell-tool | 2 (3.00, n=16) | 3 (4.12, n=16) |
| default | 3 (2.95, n=21) | 4 (3.48, n=21) |
| typescript-bun | 4 (2.90, n=21) | 5 (3.43, n=21) |
| bash | 5 (2.81, n=21) | 2 (4.24, n=21) |

*Spearman rank correlation between haiku45 and gemini31pro: **+0.40**. (+1.0 = judges agree perfectly on ordering; 0 = no correlation; -1.0 = reversed.)*

**Pair-wise reversals** (where the two judges disagree on which language is better):

| Pair | haiku45 prefers | gemini31pro prefers | Own-family signal? |
|---|---|---|---|
| bash vs default | default | bash | — |
| bash vs powershell-tool | powershell-tool | bash | — |
| bash vs typescript-bun | typescript-bun | bash | — |

### Workflow Craft

| Language | haiku45 rank (mean, n) | gemini31pro rank (mean, n) |
|---|---|---|
| powershell-tool | 1 (2.79, n=14) | 2 (4.62, n=16) |
| powershell | 2 (2.75, n=20) | 3 (4.43, n=21) |
| typescript-bun | 3 (2.67, n=21) | 4 (4.43, n=21) |
| default | 4 (2.60, n=20) | 1 (4.71, n=21) |
| bash | 5 (2.55, n=20) | 5 (4.24, n=21) |

*Spearman rank correlation between haiku45 and gemini31pro: **+0.40**. (+1.0 = judges agree perfectly on ordering; 0 = no correlation; -1.0 = reversed.)*

**Pair-wise reversals** (where the two judges disagree on which language is better):

| Pair | haiku45 prefers | gemini31pro prefers | Own-family signal? |
|---|---|---|---|
| default vs powershell | powershell | default | — |
| default vs powershell-tool | powershell-tool | default | — |
| default vs typescript-bun | typescript-bun | default | — |

## Language×Model rankings by judge

*Agreement on language×model ordering tells us the panel agrees on which configurations produce better output on this axis. Absolute-score differences between judges are expected (different grading scales) and are not a bias concern.*

### Tests Quality

| Language / Model | haiku45 rank (mean, n) | gemini31pro rank (mean, n) |
|---|---|---|
| powershell / sonnet5-1m | 1 (3.29, n=7) | 2 (5.00, n=7) |
| powershell-tool / sonnet5 | 2 (3.22, n=9) | 3 (4.44, n=9) |
| powershell / sonnet5 | 3 (3.07, n=14) | 4 (4.07, n=14) |
| typescript-bun / sonnet5 | 4 (3.07, n=14) | 10 (3.29, n=14) |
| default / sonnet5 | 5 (3.00, n=14) | 8 (3.57, n=14) |
| bash / sonnet5-1m | 6 (2.86, n=7) | 1 (5.00, n=7) |
| default / sonnet5-1m | 7 (2.86, n=7) | 9 (3.29, n=7) |
| bash / sonnet5 | 8 (2.79, n=14) | 5 (3.86, n=14) |
| powershell-tool / sonnet5-1m | 9 (2.71, n=7) | 6 (3.71, n=7) |
| typescript-bun / sonnet5-1m | 10 (2.57, n=7) | 7 (3.71, n=7) |

*Spearman rank correlation between haiku45 and gemini31pro: **+0.37**. (+1.0 = judges agree perfectly on ordering; 0 = no correlation; -1.0 = reversed.)*

**Pair-wise reversals** (where the two judges disagree on which language×model is better):

| Pair | haiku45 prefers | gemini31pro prefers | Own-family signal? |
|---|---|---|---|
| bash / sonnet5 vs default / sonnet5 | default / sonnet5 | bash / sonnet5 | — |
| bash / sonnet5 vs default / sonnet5-1m | default / sonnet5-1m | bash / sonnet5 | — |
| bash / sonnet5 vs typescript-bun / sonnet5 | typescript-bun / sonnet5 | bash / sonnet5 | — |
| bash / sonnet5-1m vs default / sonnet5 | default / sonnet5 | bash / sonnet5-1m | — |
| bash / sonnet5-1m vs powershell / sonnet5 | powershell / sonnet5 | bash / sonnet5-1m | — |
| bash / sonnet5-1m vs powershell / sonnet5-1m | powershell / sonnet5-1m | bash / sonnet5-1m | — |
| bash / sonnet5-1m vs powershell-tool / sonnet5 | powershell-tool / sonnet5 | bash / sonnet5-1m | — |
| bash / sonnet5-1m vs typescript-bun / sonnet5 | typescript-bun / sonnet5 | bash / sonnet5-1m | — |
| default / sonnet5 vs powershell-tool / sonnet5-1m | default / sonnet5 | powershell-tool / sonnet5-1m | — |
| default / sonnet5 vs typescript-bun / sonnet5 | typescript-bun / sonnet5 | default / sonnet5 | — |
| default / sonnet5 vs typescript-bun / sonnet5-1m | default / sonnet5 | typescript-bun / sonnet5-1m | — |
| default / sonnet5-1m vs powershell-tool / sonnet5-1m | default / sonnet5-1m | powershell-tool / sonnet5-1m | — |
| default / sonnet5-1m vs typescript-bun / sonnet5 | typescript-bun / sonnet5 | default / sonnet5-1m | — |
| default / sonnet5-1m vs typescript-bun / sonnet5-1m | default / sonnet5-1m | typescript-bun / sonnet5-1m | — |
| powershell-tool / sonnet5-1m vs typescript-bun / sonnet5 | typescript-bun / sonnet5 | powershell-tool / sonnet5-1m | — |
| typescript-bun / sonnet5 vs typescript-bun / sonnet5-1m | typescript-bun / sonnet5 | typescript-bun / sonnet5-1m | — |

### Workflow Craft

| Language / Model | haiku45 rank (mean, n) | gemini31pro rank (mean, n) |
|---|---|---|
| powershell / sonnet5-1m | 1 (3.33, n=6) | 1 (4.86, n=7) |
| powershell-tool / sonnet5 | 2 (3.14, n=7) | 6 (4.56, n=9) |
| default / sonnet5-1m | 3 (3.00, n=6) | 3 (4.71, n=7) |
| typescript-bun / sonnet5-1m | 4 (3.00, n=7) | 5 (4.57, n=7) |
| bash / sonnet5 | 5 (2.85, n=13) | 9 (4.21, n=14) |
| powershell / sonnet5 | 6 (2.50, n=14) | 10 (4.21, n=14) |
| typescript-bun / sonnet5 | 7 (2.50, n=14) | 7 (4.36, n=14) |
| default / sonnet5 | 8 (2.43, n=14) | 2 (4.71, n=14) |
| powershell-tool / sonnet5-1m | 9 (2.43, n=7) | 4 (4.71, n=7) |
| bash / sonnet5-1m | 10 (2.00, n=7) | 8 (4.29, n=7) |

*Spearman rank correlation between haiku45 and gemini31pro: **+0.31**. (+1.0 = judges agree perfectly on ordering; 0 = no correlation; -1.0 = reversed.)*

**Pair-wise reversals** (where the two judges disagree on which language×model is better):

| Pair | haiku45 prefers | gemini31pro prefers | Own-family signal? |
|---|---|---|---|
| bash / sonnet5 vs bash / sonnet5-1m | bash / sonnet5 | bash / sonnet5-1m | — |
| bash / sonnet5 vs default / sonnet5 | bash / sonnet5 | default / sonnet5 | — |
| bash / sonnet5 vs powershell-tool / sonnet5-1m | bash / sonnet5 | powershell-tool / sonnet5-1m | — |
| bash / sonnet5 vs typescript-bun / sonnet5 | bash / sonnet5 | typescript-bun / sonnet5 | — |
| bash / sonnet5-1m vs powershell / sonnet5 | powershell / sonnet5 | bash / sonnet5-1m | — |
| default / sonnet5 vs default / sonnet5-1m | default / sonnet5-1m | default / sonnet5 | — |
| default / sonnet5 vs powershell / sonnet5 | powershell / sonnet5 | default / sonnet5 | — |
| default / sonnet5 vs powershell-tool / sonnet5 | powershell-tool / sonnet5 | default / sonnet5 | — |
| default / sonnet5 vs typescript-bun / sonnet5 | typescript-bun / sonnet5 | default / sonnet5 | — |
| default / sonnet5 vs typescript-bun / sonnet5-1m | typescript-bun / sonnet5-1m | default / sonnet5 | — |
| default / sonnet5-1m vs powershell-tool / sonnet5 | powershell-tool / sonnet5 | default / sonnet5-1m | — |
| powershell / sonnet5 vs powershell-tool / sonnet5-1m | powershell / sonnet5 | powershell-tool / sonnet5-1m | — |
| powershell / sonnet5 vs typescript-bun / sonnet5 | powershell / sonnet5 | typescript-bun / sonnet5 | — |
| powershell-tool / sonnet5 vs powershell-tool / sonnet5-1m | powershell-tool / sonnet5 | powershell-tool / sonnet5-1m | — |
| powershell-tool / sonnet5 vs typescript-bun / sonnet5-1m | powershell-tool / sonnet5 | typescript-bun / sonnet5-1m | — |
| powershell-tool / sonnet5-1m vs typescript-bun / sonnet5 | typescript-bun / sonnet5 | powershell-tool / sonnet5-1m | — |
| powershell-tool / sonnet5-1m vs typescript-bun / sonnet5-1m | typescript-bun / sonnet5-1m | powershell-tool / sonnet5-1m | — |

## Per-run self-judgment rows (reference)

*Rows where a judge evaluated output from its own model family. These individual runs are kept as a sanity check — the actual bias test is the pair-wise ranking reversals in the table above. Filtered to rows whose inter-judge delta differs from the baseline delta by ≥1.0 point; such rows are plausibly interesting but don't by themselves indicate bias (absolute-score differences between judges are expected).*

### Tests Quality

*Baseline delta (gemini31pro − haiku45) across the whole dataset: **+0.96**.*

*(no self-judgment rows exceed the 1.0-point deviation threshold — judges agree about in-family output roughly as much as about out-of-family output)*

### Workflow Craft

*Baseline delta (gemini31pro − haiku45) across the whole dataset: **+1.79**.*

*(no self-judgment rows exceed the 1.0-point deviation threshold — judges agree about in-family output roughly as much as about out-of-family output)*

