# Judge Consistency Data

*Raw panel-of-judges data plus a rankings-focused Quality Analysis. Backs the merged Conclusions and Judge Consistency Summary in the corresponding [`results.md`](results.md).*

## Notes

- **Generated:** 2026-07-02 09:54:07 AM ET
- **Source:** `/home/passp/repos/GHA-bench-integration/results/2026-04-17_004319`
- **Judges present:** haiku45, gemini31pro
- **Score conventions:** Scores shown are the `overall` dimension from each judge (1-5). Δ column is the second judge minus the first; positive = second judge is more generous.

## Quality Analysis

Opus 4.7 at 1M context, run at high or extra-high effort, is the strongest configuration on both axes — both judges place it first on Workflow Craft (ρ = +0.90) and first on Tests Quality (ρ = +0.70), with no reversals near the top of either ranking. PowerShell paired with Opus 4.7-1m leads the Workflow Craft language×model board, while PowerShell-Tool and TypeScript-Bun paired with Opus 4.7-1m share the Tests Quality lead.

- **Top performer**: opus47-1m at xhigh and high effort sits at 3.31/4.74 and 3.24/4.94 on Workflow Craft, ahead of every other model+effort cell, and both judges agree on the top three tiers with no reversals among them.
- **Effort tier**: moving Opus 4.7-1m from medium to high lifts Workflow Craft from 2.26/4.74 to 3.24/4.94 — both judges register the gain, and xhigh shows diminishing returns above high.
- **Best by language**: powershell/opus47-1m ranks #1 by Gemini and #2 by Haiku on Workflow Craft, with default/opus47-1m and powershell-tool/opus47-1m close behind (ρ = +0.79 across all language×model cells).
- **Workflow Craft ceiling**: Gemini caps the field at 4.94 for opus47-1m-high, and the +0.90 Spearman across model+effort cells means that ceiling reflects panel agreement, not a single judge's scale.
- **Where rankings diverge**: language ordering scores ρ = +0.00 on both axes — the panel agrees on which model produces better code but not on which scripting language flatters it; haiku45 still lands last across both judges with no reversal.

*Provenance:* `claude-opus-4-7[1m]` at effort `xhigh` via Claude CLI (from cache); 5 in / 2472 out tokens, $0.2484. Prompt: [`QUALITY_ANALYSIS_SYSTEM_PROMPT`](../../judge_consistency_report.py).

## Campaign summary

### Tests Quality

| Scope | n | haiku45 ovr | gemini31pro ovr | Δ(gemini31pro−haiku45) |
|---|---|---|---|---|
| all | 231 | 2.75 | 4.32 | +1.57 |

### Workflow Craft

| Scope | n | haiku45 ovr | gemini31pro ovr | Δ(gemini31pro−haiku45) |
|---|---|---|---|---|
| all | 230 | 2.48 | 4.45 | +1.97 |

## By task

### Tests Quality

| Task | n | haiku45 ovr | gemini31pro ovr | Δ(gemini31pro−haiku45) |
|---|---|---|---|---|
| 11-semantic-version-bumper | 30 | 3.07 | 4.40 | +1.33 |
| 12-pr-label-assigner | 35 | 2.71 | 3.77 | +1.06 |
| 13-dependency-license-checker | 35 | 2.80 | 4.29 | +1.49 |
| 15-test-results-aggregator | 33 | 2.61 | 4.70 | +2.09 |
| 16-environment-matrix-generator | 32 | 2.59 | 4.28 | +1.69 |
| 17-artifact-cleanup-script | 33 | 2.88 | 4.48 | +1.61 |
| 18-secret-rotation-validator | 33 | 2.61 | 4.33 | +1.73 |

### Workflow Craft

| Task | n | haiku45 ovr | gemini31pro ovr | Δ(gemini31pro−haiku45) |
|---|---|---|---|---|
| 11-semantic-version-bumper | 34 | 2.29 | 4.09 | +1.79 |
| 12-pr-label-assigner | 33 | 2.45 | 3.85 | +1.39 |
| 13-dependency-license-checker | 35 | 2.54 | 4.43 | +1.89 |
| 15-test-results-aggregator | 31 | 2.45 | 4.71 | +2.26 |
| 16-environment-matrix-generator | 30 | 2.43 | 4.80 | +2.37 |
| 17-artifact-cleanup-script | 33 | 2.52 | 4.55 | +2.03 |
| 18-secret-rotation-validator | 34 | 2.68 | 4.76 | +2.09 |

## By language mode

### Tests Quality

| Mode | n | haiku45 ovr | gemini31pro ovr | Δ(gemini31pro−haiku45) |
|---|---|---|---|---|
| bash | 47 | 2.49 | 3.96 | +1.47 |
| default | 44 | 2.84 | 4.16 | +1.32 |
| powershell | 46 | 2.85 | 4.41 | +1.57 |
| powershell-tool | 47 | 2.79 | 4.62 | +1.83 |
| typescript-bun | 47 | 2.79 | 4.43 | +1.64 |

### Workflow Craft

| Mode | n | haiku45 ovr | gemini31pro ovr | Δ(gemini31pro−haiku45) |
|---|---|---|---|---|
| bash | 46 | 2.59 | 4.39 | +1.80 |
| default | 47 | 2.45 | 4.55 | +2.11 |
| powershell | 47 | 2.49 | 4.49 | +2.00 |
| powershell-tool | 46 | 2.43 | 4.52 | +2.09 |
| typescript-bun | 44 | 2.45 | 4.27 | +1.82 |

## By model + effort

### Tests Quality

| Model-Effort | n | haiku45 ovr | gemini31pro ovr | Δ(gemini31pro−haiku45) |
|---|---|---|---|---|
| haiku45 | 29 | 2.07 | 2.38 | +0.31 |
| opus47-1m-high | 34 | 3.12 | 4.91 | +1.79 |
| opus47-1m-medium | 33 | 2.67 | 4.70 | +2.03 |
| opus47-1m-xhigh | 35 | 3.23 | 4.89 | +1.66 |
| opus47-200k-medium | 32 | 2.66 | 4.72 | +2.06 |
| sonnet-medium | 34 | 2.82 | 4.00 | +1.18 |
| sonnet46-1m-medium | 34 | 2.56 | 4.35 | +1.79 |

### Workflow Craft

| Model-Effort | n | haiku45 ovr | gemini31pro ovr | Δ(gemini31pro−haiku45) |
|---|---|---|---|---|
| haiku45 | 31 | 1.65 | 3.29 | +1.65 |
| opus47-1m-high | 34 | 3.24 | 4.94 | +1.71 |
| opus47-1m-medium | 34 | 2.26 | 4.74 | +2.47 |
| opus47-1m-xhigh | 35 | 3.31 | 4.74 | +1.43 |
| opus47-200k-medium | 30 | 2.43 | 4.73 | +2.30 |
| sonnet-medium | 31 | 2.23 | 4.23 | +2.00 |
| sonnet46-1m-medium | 35 | 2.14 | 4.37 | +2.23 |

## Disagreement hotspots (panel span ≥ 2 on overall)

### Tests Quality

| Task | Mode | Model | Span | haiku45 ovr | gemini31pro ovr |
|---|---|---|---|---|---|
| 11-semantic-version-bumper | powershell-tool | opus47-1m-xhigh | 3.0 | 2.0 | 5.0 |
| 11-semantic-version-bumper | powershell-tool | sonnet46-1m-medium | 3.0 | 2.0 | 5.0 |
| 11-semantic-version-bumper | typescript-bun | opus47-200k-medium | 3.0 | 2.0 | 5.0 |
| 12-pr-label-assigner | bash | opus47-1m-xhigh | 3.0 | 2.0 | 5.0 |
| 12-pr-label-assigner | powershell-tool | opus47-1m-medium | 3.0 | 2.0 | 5.0 |
| 13-dependency-license-checker | default | sonnet46-1m-medium | 3.0 | 2.0 | 5.0 |
| 13-dependency-license-checker | powershell | opus47-1m-medium | 3.0 | 2.0 | 5.0 |
| 13-dependency-license-checker | powershell | opus47-200k-medium | 3.0 | 2.0 | 5.0 |
| 13-dependency-license-checker | powershell-tool | sonnet-medium | 3.0 | 2.0 | 5.0 |
| 13-dependency-license-checker | typescript-bun | sonnet-medium | 3.0 | 2.0 | 5.0 |
| 15-test-results-aggregator | bash | opus47-1m-high | 3.0 | 2.0 | 5.0 |
| 15-test-results-aggregator | bash | sonnet46-1m-medium | 3.0 | 2.0 | 5.0 |
| 15-test-results-aggregator | default | haiku45 | 3.0 | 1.0 | 4.0 |
| 15-test-results-aggregator | default | opus47-1m-medium | 3.0 | 2.0 | 5.0 |
| 15-test-results-aggregator | default | sonnet46-1m-medium | 3.0 | 2.0 | 5.0 |
| 15-test-results-aggregator | powershell | opus47-1m-xhigh | 3.0 | 2.0 | 5.0 |
| 15-test-results-aggregator | powershell | opus47-200k-medium | 3.0 | 2.0 | 5.0 |
| 15-test-results-aggregator | powershell-tool | opus47-1m-medium | 3.0 | 2.0 | 5.0 |
| 15-test-results-aggregator | powershell-tool | opus47-200k-medium | 3.0 | 2.0 | 5.0 |
| 15-test-results-aggregator | typescript-bun | opus47-200k-medium | 3.0 | 2.0 | 5.0 |
| 15-test-results-aggregator | typescript-bun | sonnet46-1m-medium | 3.0 | 2.0 | 5.0 |
| 16-environment-matrix-generato | bash | opus47-1m-xhigh | 3.0 | 2.0 | 5.0 |
| 16-environment-matrix-generato | bash | opus47-200k-medium | 3.0 | 2.0 | 5.0 |
| 16-environment-matrix-generato | bash | sonnet46-1m-medium | 3.0 | 2.0 | 5.0 |
| 16-environment-matrix-generato | powershell-tool | opus47-1m-high | 3.0 | 2.0 | 5.0 |

### Workflow Craft

| Task | Mode | Model | Span | haiku45 ovr | gemini31pro ovr |
|---|---|---|---|---|---|
| 11-semantic-version-bumper | powershell | opus47-1m-medium | 4.0 | 1.0 | 5.0 |
| 11-semantic-version-bumper | powershell-tool | sonnet46-1m-medium | 4.0 | 1.0 | 5.0 |
| 12-pr-label-assigner | bash | opus47-1m-medium | 4.0 | 1.0 | 5.0 |
| 13-dependency-license-checker | powershell-tool | sonnet-medium | 4.0 | 1.0 | 5.0 |
| 15-test-results-aggregator | default | opus47-1m-medium | 4.0 | 1.0 | 5.0 |
| 15-test-results-aggregator | default | sonnet46-1m-medium | 4.0 | 1.0 | 5.0 |
| 16-environment-matrix-generato | powershell | opus47-1m-xhigh | 4.0 | 1.0 | 5.0 |
| 17-artifact-cleanup-script | bash | opus47-1m-medium | 4.0 | 1.0 | 5.0 |
| 11-semantic-version-bumper | bash | opus47-1m-xhigh | 3.0 | 2.0 | 5.0 |
| 11-semantic-version-bumper | default | opus47-1m-medium | 3.0 | 1.0 | 4.0 |
| 11-semantic-version-bumper | default | opus47-1m-xhigh | 3.0 | 2.0 | 5.0 |
| 11-semantic-version-bumper | default | opus47-200k-medium | 3.0 | 2.0 | 5.0 |
| 11-semantic-version-bumper | powershell-tool | opus47-1m-medium | 3.0 | 2.0 | 5.0 |
| 11-semantic-version-bumper | powershell-tool | opus47-1m-xhigh | 3.0 | 2.0 | 5.0 |
| 11-semantic-version-bumper | typescript-bun | opus47-200k-medium | 3.0 | 2.0 | 5.0 |
| 11-semantic-version-bumper | typescript-bun | sonnet-medium | 3.0 | 2.0 | 5.0 |
| 12-pr-label-assigner | bash | sonnet46-1m-medium | 3.0 | 2.0 | 5.0 |
| 12-pr-label-assigner | default | opus47-1m-medium | 3.0 | 2.0 | 5.0 |
| 12-pr-label-assigner | default | opus47-1m-xhigh | 3.0 | 2.0 | 5.0 |
| 12-pr-label-assigner | default | opus47-200k-medium | 3.0 | 2.0 | 5.0 |
| 12-pr-label-assigner | powershell | opus47-1m-xhigh | 3.0 | 2.0 | 5.0 |
| 12-pr-label-assigner | powershell | opus47-200k-medium | 3.0 | 1.0 | 4.0 |
| 12-pr-label-assigner | typescript-bun | opus47-1m-xhigh | 3.0 | 2.0 | 5.0 |
| 13-dependency-license-checker | bash | opus47-1m-medium | 3.0 | 2.0 | 5.0 |
| 13-dependency-license-checker | bash | sonnet46-1m-medium | 3.0 | 1.0 | 4.0 |

## Model rankings by judge

*Agreement on model ordering tells us the panel agrees on which configurations produce better output on this axis. Absolute-score differences between judges are expected (different grading scales) and are not a bias concern.*

### Tests Quality

| Model | haiku45 rank (mean, n) | gemini31pro rank (mean, n) |
|---|---|---|
| opus47-1m | 1 (3.00, n=104) | 1 (4.83, n=102) |
| sonnet | 2 (2.82, n=34) | 4 (4.00, n=34) |
| opus47-200k | 3 (2.71, n=34) | 2 (4.72, n=32) |
| sonnet46-1m | 4 (2.57, n=35) | 3 (4.35, n=34) |
| haiku45 | 5 (2.07, n=29) | 5 (2.38, n=29) |

*Spearman rank correlation between haiku45 and gemini31pro: **+0.70**. (+1.0 = judges agree perfectly on ordering; 0 = no correlation; -1.0 = reversed.)*

**Pair-wise reversals** (where the two judges disagree on which model is better):

| Pair | haiku45 prefers | gemini31pro prefers | Own-family signal? |
|---|---|---|---|
| opus47-200k vs sonnet | sonnet | opus47-200k | — |
| sonnet vs sonnet46-1m | sonnet | sonnet46-1m | — |

### Workflow Craft

| Model | haiku45 rank (mean, n) | gemini31pro rank (mean, n) |
|---|---|---|
| opus47-1m | 1 (2.94, n=104) | 1 (4.81, n=104) |
| opus47-200k | 2 (2.44, n=32) | 2 (4.76, n=33) |
| sonnet | 3 (2.18, n=33) | 4 (4.25, n=32) |
| sonnet46-1m | 4 (2.14, n=35) | 3 (4.37, n=35) |
| haiku45 | 5 (1.62, n=34) | 5 (3.34, n=32) |

*Spearman rank correlation between haiku45 and gemini31pro: **+0.90**. (+1.0 = judges agree perfectly on ordering; 0 = no correlation; -1.0 = reversed.)*

**Pair-wise reversals** (where the two judges disagree on which model is better):

| Pair | haiku45 prefers | gemini31pro prefers | Own-family signal? |
|---|---|---|---|
| sonnet vs sonnet46-1m | sonnet | sonnet46-1m | — |

## Language rankings by judge

*Agreement on language ordering tells us the panel agrees on which configurations produce better output on this axis. Absolute-score differences between judges are expected (different grading scales) and are not a bias concern.*

### Tests Quality

| Language | haiku45 rank (mean, n) | gemini31pro rank (mean, n) |
|---|---|---|
| default | 1 (2.85, n=46) | 4 (4.16, n=44) |
| powershell | 2 (2.85, n=46) | 3 (4.41, n=46) |
| typescript-bun | 3 (2.80, n=49) | 2 (4.43, n=47) |
| powershell-tool | 4 (2.79, n=47) | 1 (4.62, n=47) |
| bash | 5 (2.50, n=48) | 5 (3.96, n=47) |

*Spearman rank correlation between haiku45 and gemini31pro: **+0.00**. (+1.0 = judges agree perfectly on ordering; 0 = no correlation; -1.0 = reversed.)*

**Pair-wise reversals** (where the two judges disagree on which language is better):

| Pair | haiku45 prefers | gemini31pro prefers | Own-family signal? |
|---|---|---|---|
| default vs powershell | default | powershell | — |
| default vs powershell-tool | default | powershell-tool | — |
| default vs typescript-bun | default | typescript-bun | — |
| powershell vs powershell-tool | powershell | powershell-tool | — |
| powershell vs typescript-bun | powershell | typescript-bun | — |
| powershell-tool vs typescript-bun | typescript-bun | powershell-tool | — |

### Workflow Craft

| Language | haiku45 rank (mean, n) | gemini31pro rank (mean, n) |
|---|---|---|
| bash | 1 (2.57, n=47) | 4 (4.40, n=47) |
| powershell | 2 (2.49, n=47) | 3 (4.51, n=49) |
| powershell-tool | 3 (2.44, n=48) | 2 (4.53, n=47) |
| default | 4 (2.41, n=49) | 1 (4.55, n=47) |
| typescript-bun | 5 (2.40, n=47) | 5 (4.30, n=46) |

*Spearman rank correlation between haiku45 and gemini31pro: **+0.00**. (+1.0 = judges agree perfectly on ordering; 0 = no correlation; -1.0 = reversed.)*

**Pair-wise reversals** (where the two judges disagree on which language is better):

| Pair | haiku45 prefers | gemini31pro prefers | Own-family signal? |
|---|---|---|---|
| bash vs default | bash | default | — |
| bash vs powershell | bash | powershell | — |
| bash vs powershell-tool | bash | powershell-tool | — |
| default vs powershell | powershell | default | — |
| default vs powershell-tool | powershell-tool | default | — |
| powershell vs powershell-tool | powershell | powershell-tool | — |

## Language×Model rankings by judge

*Agreement on language×model ordering tells us the panel agrees on which configurations produce better output on this axis. Absolute-score differences between judges are expected (different grading scales) and are not a bias concern.*

### Tests Quality

| Language / Model | haiku45 rank (mean, n) | gemini31pro rank (mean, n) |
|---|---|---|
| default / opus47-200k | 1 (3.33, n=6) | 13 (4.40, n=5) |
| typescript-bun / opus47-1m | 2 (3.33, n=21) | 4 (5.00, n=20) |
| powershell / opus47-1m | 3 (3.24, n=21) | 6 (4.95, n=21) |
| default / opus47-1m | 4 (3.05, n=20) | 9 (4.74, n=19) |
| bash / sonnet | 5 (3.00, n=6) | 19 (3.50, n=6) |
| default / sonnet | 6 (3.00, n=7) | 14 (4.14, n=7) |
| powershell-tool / sonnet | 7 (3.00, n=7) | 7 (4.86, n=7) |
| powershell-tool / opus47-1m | 8 (2.90, n=21) | 2 (5.00, n=21) |
| powershell / sonnet46-1m | 9 (2.86, n=7) | 12 (4.43, n=7) |
| powershell / sonnet | 10 (2.71, n=7) | 20 (3.43, n=7) |
| powershell-tool / opus47-200k | 11 (2.71, n=7) | 3 (5.00, n=7) |
| bash / opus47-200k | 12 (2.57, n=7) | 16 (4.00, n=6) |
| default / sonnet46-1m | 13 (2.57, n=7) | 17 (4.00, n=7) |
| powershell-tool / sonnet46-1m | 14 (2.57, n=7) | 15 (4.14, n=7) |
| typescript-bun / opus47-200k | 15 (2.57, n=7) | 5 (5.00, n=7) |
| typescript-bun / sonnet46-1m | 16 (2.57, n=7) | 8 (4.83, n=6) |
| bash / opus47-1m | 17 (2.48, n=21) | 10 (4.48, n=21) |
| powershell / opus47-200k | 18 (2.43, n=7) | 1 (5.00, n=7) |
| typescript-bun / sonnet | 19 (2.43, n=7) | 18 (4.00, n=7) |
| powershell-tool / haiku45 | 20 (2.40, n=5) | 21 (2.80, n=5) |
| bash / haiku45 | 21 (2.29, n=7) | 23 (2.29, n=7) |
| bash / sonnet46-1m | 22 (2.29, n=7) | 11 (4.43, n=7) |
| typescript-bun / haiku45 | 23 (2.00, n=7) | 24 (2.29, n=7) |
| default / haiku45 | 24 (1.83, n=6) | 22 (2.33, n=6) |
| powershell / haiku45 | 25 (1.75, n=4) | 25 (2.25, n=4) |

*Spearman rank correlation between haiku45 and gemini31pro: **+0.49**. (+1.0 = judges agree perfectly on ordering; 0 = no correlation; -1.0 = reversed.)*

**Pair-wise reversals** (where the two judges disagree on which language×model is better):

| Pair | haiku45 prefers | gemini31pro prefers | Own-family signal? |
|---|---|---|---|
| bash / haiku45 vs bash / sonnet46-1m | bash / haiku45 | bash / sonnet46-1m | ⚠️ haiku45 |
| bash / haiku45 vs default / haiku45 | bash / haiku45 | default / haiku45 | ⚠️ haiku45 |
| bash / opus47-1m vs bash / opus47-200k | bash / opus47-200k | bash / opus47-1m | — |
| bash / opus47-1m vs bash / sonnet | bash / sonnet | bash / opus47-1m | — |
| bash / opus47-1m vs default / opus47-200k | default / opus47-200k | bash / opus47-1m | — |
| bash / opus47-1m vs default / sonnet | default / sonnet | bash / opus47-1m | — |
| bash / opus47-1m vs default / sonnet46-1m | default / sonnet46-1m | bash / opus47-1m | — |
| bash / opus47-1m vs powershell / opus47-200k | bash / opus47-1m | powershell / opus47-200k | — |
| bash / opus47-1m vs powershell / sonnet | powershell / sonnet | bash / opus47-1m | — |
| bash / opus47-1m vs powershell / sonnet46-1m | powershell / sonnet46-1m | bash / opus47-1m | — |
| bash / opus47-1m vs powershell-tool / sonnet46-1m | powershell-tool / sonnet46-1m | bash / opus47-1m | — |
| bash / opus47-200k vs bash / sonnet | bash / sonnet | bash / opus47-200k | — |
| bash / opus47-200k vs bash / sonnet46-1m | bash / opus47-200k | bash / sonnet46-1m | — |
| bash / opus47-200k vs powershell / opus47-200k | bash / opus47-200k | powershell / opus47-200k | — |
| bash / opus47-200k vs powershell / sonnet | powershell / sonnet | bash / opus47-200k | — |
| bash / opus47-200k vs powershell-tool / sonnet46-1m | bash / opus47-200k | powershell-tool / sonnet46-1m | — |
| bash / opus47-200k vs typescript-bun / opus47-200k | bash / opus47-200k | typescript-bun / opus47-200k | — |
| bash / opus47-200k vs typescript-bun / sonnet46-1m | bash / opus47-200k | typescript-bun / sonnet46-1m | — |
| bash / sonnet vs bash / sonnet46-1m | bash / sonnet | bash / sonnet46-1m | — |
| bash / sonnet vs default / sonnet | bash / sonnet | default / sonnet | — |
| bash / sonnet vs default / sonnet46-1m | bash / sonnet | default / sonnet46-1m | — |
| bash / sonnet vs powershell / opus47-200k | bash / sonnet | powershell / opus47-200k | — |
| bash / sonnet vs powershell / sonnet46-1m | bash / sonnet | powershell / sonnet46-1m | — |
| bash / sonnet vs powershell-tool / opus47-1m | bash / sonnet | powershell-tool / opus47-1m | — |
| bash / sonnet vs powershell-tool / opus47-200k | bash / sonnet | powershell-tool / opus47-200k | — |
| bash / sonnet vs powershell-tool / sonnet | bash / sonnet | powershell-tool / sonnet | — |
| bash / sonnet vs powershell-tool / sonnet46-1m | bash / sonnet | powershell-tool / sonnet46-1m | — |
| bash / sonnet vs typescript-bun / opus47-200k | bash / sonnet | typescript-bun / opus47-200k | — |
| bash / sonnet vs typescript-bun / sonnet | bash / sonnet | typescript-bun / sonnet | — |
| bash / sonnet vs typescript-bun / sonnet46-1m | bash / sonnet | typescript-bun / sonnet46-1m | — |
| bash / sonnet46-1m vs default / opus47-200k | default / opus47-200k | bash / sonnet46-1m | — |
| bash / sonnet46-1m vs default / sonnet | default / sonnet | bash / sonnet46-1m | — |
| bash / sonnet46-1m vs default / sonnet46-1m | default / sonnet46-1m | bash / sonnet46-1m | — |
| bash / sonnet46-1m vs powershell / sonnet | powershell / sonnet | bash / sonnet46-1m | — |
| bash / sonnet46-1m vs powershell / sonnet46-1m | powershell / sonnet46-1m | bash / sonnet46-1m | — |
| bash / sonnet46-1m vs powershell-tool / haiku45 | powershell-tool / haiku45 | bash / sonnet46-1m | ⚠️ haiku45 |
| bash / sonnet46-1m vs powershell-tool / sonnet46-1m | powershell-tool / sonnet46-1m | bash / sonnet46-1m | — |
| bash / sonnet46-1m vs typescript-bun / sonnet | typescript-bun / sonnet | bash / sonnet46-1m | — |
| default / haiku45 vs typescript-bun / haiku45 | typescript-bun / haiku45 | default / haiku45 | ⚠️ haiku45 |
| default / opus47-1m vs default / opus47-200k | default / opus47-200k | default / opus47-1m | — |
| default / opus47-1m vs powershell / opus47-200k | default / opus47-1m | powershell / opus47-200k | — |
| default / opus47-1m vs powershell-tool / opus47-1m | default / opus47-1m | powershell-tool / opus47-1m | — |
| default / opus47-1m vs powershell-tool / opus47-200k | default / opus47-1m | powershell-tool / opus47-200k | — |
| default / opus47-1m vs powershell-tool / sonnet | default / opus47-1m | powershell-tool / sonnet | — |
| default / opus47-1m vs typescript-bun / opus47-200k | default / opus47-1m | typescript-bun / opus47-200k | — |
| default / opus47-1m vs typescript-bun / sonnet46-1m | default / opus47-1m | typescript-bun / sonnet46-1m | — |
| default / opus47-200k vs powershell / opus47-1m | default / opus47-200k | powershell / opus47-1m | — |
| default / opus47-200k vs powershell / opus47-200k | default / opus47-200k | powershell / opus47-200k | — |
| default / opus47-200k vs powershell / sonnet46-1m | default / opus47-200k | powershell / sonnet46-1m | — |
| default / opus47-200k vs powershell-tool / opus47-1m | default / opus47-200k | powershell-tool / opus47-1m | — |
| default / opus47-200k vs powershell-tool / opus47-200k | default / opus47-200k | powershell-tool / opus47-200k | — |
| default / opus47-200k vs powershell-tool / sonnet | default / opus47-200k | powershell-tool / sonnet | — |
| default / opus47-200k vs typescript-bun / opus47-1m | default / opus47-200k | typescript-bun / opus47-1m | — |
| default / opus47-200k vs typescript-bun / opus47-200k | default / opus47-200k | typescript-bun / opus47-200k | — |
| default / opus47-200k vs typescript-bun / sonnet46-1m | default / opus47-200k | typescript-bun / sonnet46-1m | — |
| default / sonnet vs powershell / opus47-200k | default / sonnet | powershell / opus47-200k | — |
| default / sonnet vs powershell / sonnet46-1m | default / sonnet | powershell / sonnet46-1m | — |
| default / sonnet vs powershell-tool / opus47-1m | default / sonnet | powershell-tool / opus47-1m | — |
| default / sonnet vs powershell-tool / opus47-200k | default / sonnet | powershell-tool / opus47-200k | — |
| default / sonnet vs powershell-tool / sonnet | default / sonnet | powershell-tool / sonnet | — |
| default / sonnet vs typescript-bun / opus47-200k | default / sonnet | typescript-bun / opus47-200k | — |
| default / sonnet vs typescript-bun / sonnet46-1m | default / sonnet | typescript-bun / sonnet46-1m | — |
| default / sonnet46-1m vs powershell / opus47-200k | default / sonnet46-1m | powershell / opus47-200k | — |
| default / sonnet46-1m vs powershell / sonnet | powershell / sonnet | default / sonnet46-1m | — |
| default / sonnet46-1m vs powershell-tool / sonnet46-1m | default / sonnet46-1m | powershell-tool / sonnet46-1m | — |
| default / sonnet46-1m vs typescript-bun / opus47-200k | default / sonnet46-1m | typescript-bun / opus47-200k | — |
| default / sonnet46-1m vs typescript-bun / sonnet46-1m | default / sonnet46-1m | typescript-bun / sonnet46-1m | — |
| powershell / opus47-1m vs powershell / opus47-200k | powershell / opus47-1m | powershell / opus47-200k | — |
| powershell / opus47-1m vs powershell-tool / opus47-1m | powershell / opus47-1m | powershell-tool / opus47-1m | — |
| powershell / opus47-1m vs powershell-tool / opus47-200k | powershell / opus47-1m | powershell-tool / opus47-200k | — |
| powershell / opus47-1m vs typescript-bun / opus47-200k | powershell / opus47-1m | typescript-bun / opus47-200k | — |
| powershell / opus47-200k vs powershell / sonnet | powershell / sonnet | powershell / opus47-200k | — |
| powershell / opus47-200k vs powershell / sonnet46-1m | powershell / sonnet46-1m | powershell / opus47-200k | — |
| powershell / opus47-200k vs powershell-tool / opus47-1m | powershell-tool / opus47-1m | powershell / opus47-200k | — |
| powershell / opus47-200k vs powershell-tool / opus47-200k | powershell-tool / opus47-200k | powershell / opus47-200k | — |
| powershell / opus47-200k vs powershell-tool / sonnet | powershell-tool / sonnet | powershell / opus47-200k | — |
| powershell / opus47-200k vs powershell-tool / sonnet46-1m | powershell-tool / sonnet46-1m | powershell / opus47-200k | — |
| powershell / opus47-200k vs typescript-bun / opus47-1m | typescript-bun / opus47-1m | powershell / opus47-200k | — |
| powershell / opus47-200k vs typescript-bun / opus47-200k | typescript-bun / opus47-200k | powershell / opus47-200k | — |
| powershell / opus47-200k vs typescript-bun / sonnet46-1m | typescript-bun / sonnet46-1m | powershell / opus47-200k | — |
| powershell / sonnet vs powershell-tool / opus47-200k | powershell / sonnet | powershell-tool / opus47-200k | — |
| powershell / sonnet vs powershell-tool / sonnet46-1m | powershell / sonnet | powershell-tool / sonnet46-1m | — |
| powershell / sonnet vs typescript-bun / opus47-200k | powershell / sonnet | typescript-bun / opus47-200k | — |
| powershell / sonnet vs typescript-bun / sonnet | powershell / sonnet | typescript-bun / sonnet | — |
| powershell / sonnet vs typescript-bun / sonnet46-1m | powershell / sonnet | typescript-bun / sonnet46-1m | — |
| powershell / sonnet46-1m vs powershell-tool / opus47-200k | powershell / sonnet46-1m | powershell-tool / opus47-200k | — |
| powershell / sonnet46-1m vs typescript-bun / opus47-200k | powershell / sonnet46-1m | typescript-bun / opus47-200k | — |
| powershell / sonnet46-1m vs typescript-bun / sonnet46-1m | powershell / sonnet46-1m | typescript-bun / sonnet46-1m | — |
| powershell-tool / opus47-1m vs powershell-tool / sonnet | powershell-tool / sonnet | powershell-tool / opus47-1m | — |
| powershell-tool / opus47-1m vs typescript-bun / opus47-1m | typescript-bun / opus47-1m | powershell-tool / opus47-1m | — |
| powershell-tool / opus47-200k vs powershell-tool / sonnet | powershell-tool / sonnet | powershell-tool / opus47-200k | — |
| powershell-tool / opus47-200k vs typescript-bun / opus47-1m | typescript-bun / opus47-1m | powershell-tool / opus47-200k | — |
| powershell-tool / sonnet vs typescript-bun / opus47-200k | powershell-tool / sonnet | typescript-bun / opus47-200k | — |
| powershell-tool / sonnet46-1m vs typescript-bun / opus47-200k | powershell-tool / sonnet46-1m | typescript-bun / opus47-200k | — |
| powershell-tool / sonnet46-1m vs typescript-bun / sonnet46-1m | powershell-tool / sonnet46-1m | typescript-bun / sonnet46-1m | — |

### Workflow Craft

| Language / Model | haiku45 rank (mean, n) | gemini31pro rank (mean, n) |
|---|---|---|
| bash / opus47-200k | 1 (3.33, n=6) | 4 (4.86, n=7) |
| powershell / opus47-1m | 2 (3.14, n=21) | 1 (5.00, n=21) |
| default / opus47-1m | 3 (2.95, n=21) | 2 (4.90, n=21) |
| powershell-tool / opus47-1m | 4 (2.95, n=21) | 3 (4.90, n=21) |
| typescript-bun / opus47-1m | 5 (2.90, n=20) | 8 (4.70, n=20) |
| bash / opus47-1m | 6 (2.76, n=21) | 11 (4.52, n=21) |
| powershell-tool / opus47-200k | 7 (2.57, n=7) | 7 (4.80, n=5) |
| bash / sonnet | 8 (2.50, n=6) | 14 (4.40, n=5) |
| default / opus47-200k | 9 (2.43, n=7) | 5 (4.86, n=7) |
| powershell / sonnet | 10 (2.43, n=7) | 20 (4.00, n=7) |
| typescript-bun / sonnet46-1m | 11 (2.43, n=7) | 17 (4.29, n=7) |
| bash / sonnet46-1m | 12 (2.29, n=7) | 12 (4.43, n=7) |
| powershell-tool / sonnet46-1m | 13 (2.29, n=7) | 10 (4.57, n=7) |
| typescript-bun / sonnet | 14 (2.14, n=7) | 18 (4.17, n=6) |
| default / sonnet | 15 (2.00, n=7) | 19 (4.14, n=7) |
| powershell / opus47-200k | 16 (2.00, n=6) | 6 (4.86, n=7) |
| default / sonnet46-1m | 17 (1.86, n=7) | 15 (4.29, n=7) |
| powershell / sonnet46-1m | 18 (1.86, n=7) | 16 (4.29, n=7) |
| powershell-tool / sonnet | 19 (1.83, n=6) | 9 (4.57, n=7) |
| typescript-bun / opus47-200k | 20 (1.83, n=6) | 13 (4.43, n=7) |
| bash / haiku45 | 21 (1.71, n=7) | 22 (3.57, n=7) |
| default / haiku45 | 22 (1.71, n=7) | 21 (3.60, n=5) |
| typescript-bun / haiku45 | 23 (1.71, n=7) | 25 (3.00, n=6) |
| powershell / haiku45 | 24 (1.50, n=6) | 23 (3.43, n=7) |
| powershell-tool / haiku45 | 25 (1.43, n=7) | 24 (3.14, n=7) |

*Spearman rank correlation between haiku45 and gemini31pro: **+0.79**. (+1.0 = judges agree perfectly on ordering; 0 = no correlation; -1.0 = reversed.)*

**Pair-wise reversals** (where the two judges disagree on which language×model is better):

| Pair | haiku45 prefers | gemini31pro prefers | Own-family signal? |
|---|---|---|---|
| bash / haiku45 vs default / haiku45 | bash / haiku45 | default / haiku45 | ⚠️ haiku45 |
| bash / opus47-1m vs default / opus47-200k | bash / opus47-1m | default / opus47-200k | — |
| bash / opus47-1m vs powershell / opus47-200k | bash / opus47-1m | powershell / opus47-200k | — |
| bash / opus47-1m vs powershell-tool / opus47-200k | bash / opus47-1m | powershell-tool / opus47-200k | — |
| bash / opus47-1m vs powershell-tool / sonnet | bash / opus47-1m | powershell-tool / sonnet | — |
| bash / opus47-1m vs powershell-tool / sonnet46-1m | bash / opus47-1m | powershell-tool / sonnet46-1m | — |
| bash / opus47-200k vs default / opus47-1m | bash / opus47-200k | default / opus47-1m | — |
| bash / opus47-200k vs powershell / opus47-1m | bash / opus47-200k | powershell / opus47-1m | — |
| bash / opus47-200k vs powershell-tool / opus47-1m | bash / opus47-200k | powershell-tool / opus47-1m | — |
| bash / sonnet vs bash / sonnet46-1m | bash / sonnet | bash / sonnet46-1m | — |
| bash / sonnet vs default / opus47-200k | bash / sonnet | default / opus47-200k | — |
| bash / sonnet vs powershell / opus47-200k | bash / sonnet | powershell / opus47-200k | — |
| bash / sonnet vs powershell-tool / sonnet | bash / sonnet | powershell-tool / sonnet | — |
| bash / sonnet vs powershell-tool / sonnet46-1m | bash / sonnet | powershell-tool / sonnet46-1m | — |
| bash / sonnet vs typescript-bun / opus47-200k | bash / sonnet | typescript-bun / opus47-200k | — |
| bash / sonnet46-1m vs powershell / opus47-200k | bash / sonnet46-1m | powershell / opus47-200k | — |
| bash / sonnet46-1m vs powershell / sonnet | powershell / sonnet | bash / sonnet46-1m | — |
| bash / sonnet46-1m vs powershell-tool / sonnet | bash / sonnet46-1m | powershell-tool / sonnet | — |
| bash / sonnet46-1m vs powershell-tool / sonnet46-1m | bash / sonnet46-1m | powershell-tool / sonnet46-1m | — |
| bash / sonnet46-1m vs typescript-bun / sonnet46-1m | typescript-bun / sonnet46-1m | bash / sonnet46-1m | — |
| default / opus47-200k vs powershell-tool / opus47-200k | powershell-tool / opus47-200k | default / opus47-200k | — |
| default / opus47-200k vs typescript-bun / opus47-1m | typescript-bun / opus47-1m | default / opus47-200k | — |
| default / sonnet vs default / sonnet46-1m | default / sonnet | default / sonnet46-1m | — |
| default / sonnet vs powershell / opus47-200k | default / sonnet | powershell / opus47-200k | — |
| default / sonnet vs powershell / sonnet | powershell / sonnet | default / sonnet | — |
| default / sonnet vs powershell / sonnet46-1m | default / sonnet | powershell / sonnet46-1m | — |
| default / sonnet vs powershell-tool / sonnet | default / sonnet | powershell-tool / sonnet | — |
| default / sonnet vs typescript-bun / opus47-200k | default / sonnet | typescript-bun / opus47-200k | — |
| default / sonnet46-1m vs powershell / sonnet | powershell / sonnet | default / sonnet46-1m | — |
| default / sonnet46-1m vs powershell-tool / sonnet | default / sonnet46-1m | powershell-tool / sonnet | — |
| default / sonnet46-1m vs typescript-bun / opus47-200k | default / sonnet46-1m | typescript-bun / opus47-200k | — |
| default / sonnet46-1m vs typescript-bun / sonnet | typescript-bun / sonnet | default / sonnet46-1m | — |
| default / sonnet46-1m vs typescript-bun / sonnet46-1m | typescript-bun / sonnet46-1m | default / sonnet46-1m | — |
| powershell / haiku45 vs typescript-bun / haiku45 | typescript-bun / haiku45 | powershell / haiku45 | ⚠️ haiku45 |
| powershell / opus47-200k vs powershell / sonnet | powershell / sonnet | powershell / opus47-200k | — |
| powershell / opus47-200k vs powershell-tool / opus47-200k | powershell-tool / opus47-200k | powershell / opus47-200k | — |
| powershell / opus47-200k vs powershell-tool / sonnet46-1m | powershell-tool / sonnet46-1m | powershell / opus47-200k | — |
| powershell / opus47-200k vs typescript-bun / opus47-1m | typescript-bun / opus47-1m | powershell / opus47-200k | — |
| powershell / opus47-200k vs typescript-bun / sonnet | typescript-bun / sonnet | powershell / opus47-200k | — |
| powershell / opus47-200k vs typescript-bun / sonnet46-1m | typescript-bun / sonnet46-1m | powershell / opus47-200k | — |
| powershell / sonnet vs powershell / sonnet46-1m | powershell / sonnet | powershell / sonnet46-1m | — |
| powershell / sonnet vs powershell-tool / sonnet | powershell / sonnet | powershell-tool / sonnet | — |
| powershell / sonnet vs powershell-tool / sonnet46-1m | powershell / sonnet | powershell-tool / sonnet46-1m | — |
| powershell / sonnet vs typescript-bun / opus47-200k | powershell / sonnet | typescript-bun / opus47-200k | — |
| powershell / sonnet vs typescript-bun / sonnet | powershell / sonnet | typescript-bun / sonnet | — |
| powershell / sonnet vs typescript-bun / sonnet46-1m | powershell / sonnet | typescript-bun / sonnet46-1m | — |
| powershell / sonnet46-1m vs powershell-tool / sonnet | powershell / sonnet46-1m | powershell-tool / sonnet | — |
| powershell / sonnet46-1m vs typescript-bun / opus47-200k | powershell / sonnet46-1m | typescript-bun / opus47-200k | — |
| powershell / sonnet46-1m vs typescript-bun / sonnet | typescript-bun / sonnet | powershell / sonnet46-1m | — |
| powershell / sonnet46-1m vs typescript-bun / sonnet46-1m | typescript-bun / sonnet46-1m | powershell / sonnet46-1m | — |
| powershell-tool / haiku45 vs typescript-bun / haiku45 | typescript-bun / haiku45 | powershell-tool / haiku45 | ⚠️ haiku45 |
| powershell-tool / opus47-200k vs typescript-bun / opus47-1m | typescript-bun / opus47-1m | powershell-tool / opus47-200k | — |
| powershell-tool / sonnet vs powershell-tool / sonnet46-1m | powershell-tool / sonnet46-1m | powershell-tool / sonnet | — |
| powershell-tool / sonnet vs typescript-bun / sonnet | typescript-bun / sonnet | powershell-tool / sonnet | — |
| powershell-tool / sonnet vs typescript-bun / sonnet46-1m | typescript-bun / sonnet46-1m | powershell-tool / sonnet | — |
| powershell-tool / sonnet46-1m vs typescript-bun / sonnet46-1m | typescript-bun / sonnet46-1m | powershell-tool / sonnet46-1m | — |
| typescript-bun / opus47-200k vs typescript-bun / sonnet | typescript-bun / sonnet | typescript-bun / opus47-200k | — |
| typescript-bun / opus47-200k vs typescript-bun / sonnet46-1m | typescript-bun / sonnet46-1m | typescript-bun / opus47-200k | — |

## Per-run self-judgment rows (reference)

*Rows where a judge evaluated output from its own model family. These individual runs are kept as a sanity check — the actual bias test is the pair-wise ranking reversals in the table above. Filtered to rows whose inter-judge delta differs from the baseline delta by ≥1.0 point; such rows are plausibly interesting but don't by themselves indicate bias (absolute-score differences between judges are expected).*

### Tests Quality

*Baseline delta (gemini31pro − haiku45) across the whole dataset: **+1.57**.*

| Task | Mode | Model | Self judge | Self score | Other judge | Other score | Row Δ | Deviation |
|---|---|---|---|---|---|---|---|---|
| 11-semantic-version-bumper | bash | haiku45 | haiku45 | 3.0 | gemini31pro | 2.0 | -1.0 | -2.6 |
| 11-semantic-version-bumper | typescript-bun | haiku45 | haiku45 | 2.0 | gemini31pro | 2.0 | +0.0 | -1.6 |
| 12-pr-label-assigner | bash | haiku45 | haiku45 | 2.0 | gemini31pro | 2.0 | +0.0 | -1.6 |
| 12-pr-label-assigner | default | haiku45 | haiku45 | 2.0 | gemini31pro | 1.0 | -1.0 | -2.6 |
| 12-pr-label-assigner | powershell | haiku45 | haiku45 | 2.0 | gemini31pro | 2.0 | +0.0 | -1.6 |
| 12-pr-label-assigner | powershell-tool | haiku45 | haiku45 | 3.0 | gemini31pro | 2.0 | -1.0 | -2.6 |
| 12-pr-label-assigner | typescript-bun | haiku45 | haiku45 | 2.0 | gemini31pro | 2.0 | +0.0 | -1.6 |
| 13-dependency-license-checker | bash | haiku45 | haiku45 | 3.0 | gemini31pro | 2.0 | -1.0 | -2.6 |
| 13-dependency-license-checker | default | haiku45 | haiku45 | 3.0 | gemini31pro | 2.0 | -1.0 | -2.6 |
| 13-dependency-license-checker | typescript-bun | haiku45 | haiku45 | 2.0 | gemini31pro | 2.0 | +0.0 | -1.6 |
| 15-test-results-aggregator | default | haiku45 | haiku45 | 1.0 | gemini31pro | 4.0 | +3.0 | +1.4 |
| 15-test-results-aggregator | typescript-bun | haiku45 | haiku45 | 2.0 | gemini31pro | 2.0 | +0.0 | -1.6 |
| 16-environment-matrix-generato | bash | haiku45 | haiku45 | 2.0 | gemini31pro | 2.0 | +0.0 | -1.6 |
| 16-environment-matrix-generato | default | haiku45 | haiku45 | 2.0 | gemini31pro | 2.0 | +0.0 | -1.6 |
| 17-artifact-cleanup-script | powershell-tool | haiku45 | haiku45 | 2.0 | gemini31pro | 1.0 | -1.0 | -2.6 |
| 17-artifact-cleanup-script | typescript-bun | haiku45 | haiku45 | 2.0 | gemini31pro | 2.0 | +0.0 | -1.6 |
| 18-secret-rotation-validator | bash | haiku45 | haiku45 | 2.0 | gemini31pro | 2.0 | +0.0 | -1.6 |
| 18-secret-rotation-validator | powershell | haiku45 | haiku45 | 2.0 | gemini31pro | 2.0 | +0.0 | -1.6 |
| 18-secret-rotation-validator | typescript-bun | haiku45 | haiku45 | 2.0 | gemini31pro | 2.0 | +0.0 | -1.6 |

### Workflow Craft

*Baseline delta (gemini31pro − haiku45) across the whole dataset: **+1.97**.*

| Task | Mode | Model | Self judge | Self score | Other judge | Other score | Row Δ | Deviation |
|---|---|---|---|---|---|---|---|---|
| 11-semantic-version-bumper | powershell-tool | haiku45 | haiku45 | 2.0 | gemini31pro | 2.0 | +0.0 | -2.0 |
| 11-semantic-version-bumper | typescript-bun | haiku45 | haiku45 | 2.0 | gemini31pro | 2.0 | +0.0 | -2.0 |
| 12-pr-label-assigner | typescript-bun | haiku45 | haiku45 | 2.0 | gemini31pro | 2.0 | +0.0 | -2.0 |
| 13-dependency-license-checker | powershell-tool | haiku45 | haiku45 | 1.0 | gemini31pro | 4.0 | +3.0 | +1.0 |
| 15-test-results-aggregator | bash | haiku45 | haiku45 | 1.0 | gemini31pro | 4.0 | +3.0 | +1.0 |
| 15-test-results-aggregator | default | haiku45 | haiku45 | 1.0 | — | — | — | — |
| 15-test-results-aggregator | powershell-tool | haiku45 | haiku45 | 1.0 | gemini31pro | 4.0 | +3.0 | +1.0 |
| 16-environment-matrix-generato | bash | haiku45 | haiku45 | 2.0 | gemini31pro | 5.0 | +3.0 | +1.0 |
| 16-environment-matrix-generato | default | haiku45 | haiku45 | 2.0 | — | — | — | — |
| 16-environment-matrix-generato | powershell | haiku45 | haiku45 | 2.0 | gemini31pro | 5.0 | +3.0 | +1.0 |
| 16-environment-matrix-generato | typescript-bun | haiku45 | haiku45 | 1.0 | — | — | — | — |
| 17-artifact-cleanup-script | default | haiku45 | haiku45 | 2.0 | gemini31pro | 5.0 | +3.0 | +1.0 |
| 17-artifact-cleanup-script | powershell-tool | haiku45 | haiku45 | 1.0 | gemini31pro | 4.0 | +3.0 | +1.0 |
| 18-secret-rotation-validator | typescript-bun | haiku45 | haiku45 | 2.0 | gemini31pro | 5.0 | +3.0 | +1.0 |

