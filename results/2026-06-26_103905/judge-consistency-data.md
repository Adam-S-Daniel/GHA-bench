# Judge Consistency Data

*Raw panel-of-judges data plus a rankings-focused Quality Analysis. Backs the merged Conclusions and Judge Consistency Summary in the corresponding [`results.md`](results.md).*

## Notes

- **Generated:** 2026-07-02 09:57:14 AM ET
- **Source:** `/home/passp/repos/GHA-bench-integration/results/2026-06-26_103905`
- **Judges present:** haiku45, gemini31pro
- **Score conventions:** Scores shown are the `overall` dimension from each judge (1-5). Δ column is the second judge minus the first; positive = second judge is more generous.

## Quality Analysis

Opus 4.8 at ultracode effort produces the highest-quality test suites in the dataset, ranked first by both judges with perfect agreement (ρ = +1.00, zero reversals). For language pairings on Tests Quality, PowerShell, PowerShell-tool, and TypeScript-Bun cluster at the top while Bash trails every other language across both judges (ρ = +0.90).

- **Top performer**: opus48-1m at ultracode effort leads Tests Quality (Haiku 3.83, Gemini 4.94) over the pooled non-ultracode runs (3.50, 4.85), and both judges place it #1 with no pair-wise reversals.
- **Best by language**: PowerShell-tool (3.79 / 5.00), PowerShell (3.75 / 5.00), and TypeScript-Bun (3.75 / 5.00) tie at the top of Tests Quality; the sole reversal is an internal PowerShell vs PowerShell-tool swap, so the top three are effectively interchangeable.
- **Effort tier**: ultracode and xhigh both outscore medium on Tests Quality (Haiku 3.83 and 3.69 vs 3.26; Gemini 4.94 and 4.94 vs 4.83), and both judges agree that medium sits lowest among the four effort tiers.
- **Bash trails consistently**: Bash lands last on Tests Quality (3.15 / 4.57) and last on Workflow Craft (3.15 / 4.79) — the one axis where the panel agrees decisively at the bottom.
- **Where rankings diverge**: Workflow Craft language ordering shows only weak agreement (ρ = +0.10) because Gemini scores nearly every non-Bash language at 5.00, so past first place those rankings carry less signal than the Tests Quality panel.

*Provenance:* `claude-opus-4-7[1m]` at effort `xhigh` via Claude CLI; 5 in / 2028 out tokens, $0.2346. Prompt: [`QUALITY_ANALYSIS_SYSTEM_PROMPT`](../../judge_consistency_report.py).

## Campaign summary

### Tests Quality

| Scope | n | haiku45 ovr | gemini31pro ovr | Δ(gemini31pro−haiku45) |
|---|---|---|---|---|
| all | 139 | 3.58 | 4.87 | +1.29 |

### Workflow Craft

| Scope | n | haiku45 ovr | gemini31pro ovr | Δ(gemini31pro−haiku45) |
|---|---|---|---|---|
| all | 134 | 3.21 | 4.93 | +1.72 |

## By task

### Tests Quality

| Task | n | haiku45 ovr | gemini31pro ovr | Δ(gemini31pro−haiku45) |
|---|---|---|---|---|
| 11-semantic-version-bumper | 20 | 3.70 | 4.75 | +1.05 |
| 12-pr-label-assigner | 20 | 3.55 | 4.85 | +1.30 |
| 13-dependency-license-checker | 20 | 3.45 | 4.85 | +1.40 |
| 15-test-results-aggregator | 20 | 3.55 | 4.80 | +1.25 |
| 16-environment-matrix-generator | 20 | 3.50 | 5.00 | +1.50 |
| 17-artifact-cleanup-script | 19 | 3.68 | 4.84 | +1.16 |
| 18-secret-rotation-validator | 20 | 3.65 | 5.00 | +1.35 |

### Workflow Craft

| Task | n | haiku45 ovr | gemini31pro ovr | Δ(gemini31pro−haiku45) |
|---|---|---|---|---|
| 11-semantic-version-bumper | 20 | 3.25 | 5.00 | +1.75 |
| 12-pr-label-assigner | 19 | 3.00 | 4.95 | +1.95 |
| 13-dependency-license-checker | 20 | 3.40 | 4.75 | +1.35 |
| 15-test-results-aggregator | 19 | 3.42 | 4.95 | +1.53 |
| 16-environment-matrix-generator | 18 | 3.17 | 4.94 | +1.78 |
| 17-artifact-cleanup-script | 19 | 3.11 | 4.95 | +1.84 |
| 18-secret-rotation-validator | 19 | 3.11 | 4.95 | +1.84 |

## By language mode

### Tests Quality

| Mode | n | haiku45 ovr | gemini31pro ovr | Δ(gemini31pro−haiku45) |
|---|---|---|---|---|
| bash | 27 | 3.15 | 4.56 | +1.41 |
| default | 28 | 3.46 | 4.79 | +1.32 |
| powershell | 28 | 3.75 | 5.00 | +1.25 |
| powershell-tool | 28 | 3.79 | 5.00 | +1.21 |
| typescript-bun | 28 | 3.75 | 5.00 | +1.25 |

### Workflow Craft

| Mode | n | haiku45 ovr | gemini31pro ovr | Δ(gemini31pro−haiku45) |
|---|---|---|---|---|
| bash | 27 | 3.15 | 4.78 | +1.63 |
| default | 26 | 3.15 | 5.00 | +1.85 |
| powershell | 28 | 3.18 | 5.00 | +1.82 |
| powershell-tool | 26 | 3.31 | 4.92 | +1.62 |
| typescript-bun | 27 | 3.26 | 4.93 | +1.67 |

## By model + effort

### Tests Quality

| Model-Effort | n | haiku45 ovr | gemini31pro ovr | Δ(gemini31pro−haiku45) |
|---|---|---|---|---|
| opus48-1m-high | 34 | 3.56 | 4.76 | +1.21 |
| opus48-1m-medium | 35 | 3.26 | 4.83 | +1.57 |
| opus48-1m-ultracode | 35 | 3.83 | 4.94 | +1.11 |
| opus48-1m-xhigh | 35 | 3.69 | 4.94 | +1.26 |

### Workflow Craft

| Model-Effort | n | haiku45 ovr | gemini31pro ovr | Δ(gemini31pro−haiku45) |
|---|---|---|---|---|
| opus48-1m-high | 32 | 3.06 | 4.97 | +1.91 |
| opus48-1m-medium | 34 | 3.29 | 4.82 | +1.53 |
| opus48-1m-ultracode | 33 | 3.18 | 4.94 | +1.76 |
| opus48-1m-xhigh | 35 | 3.29 | 4.97 | +1.69 |

## Disagreement hotspots (panel span ≥ 2 on overall)

### Tests Quality

| Task | Mode | Model | Span | haiku45 ovr | gemini31pro ovr |
|---|---|---|---|---|---|
| 12-pr-label-assigner | typescript-bun | opus48-1m-xhigh | 3.0 | 2.0 | 5.0 |
| 13-dependency-license-checker | bash | opus48-1m-xhigh | 3.0 | 2.0 | 5.0 |
| 13-dependency-license-checker | powershell-tool | opus48-1m-medium | 3.0 | 2.0 | 5.0 |
| 16-environment-matrix-generato | bash | opus48-1m-medium | 3.0 | 2.0 | 5.0 |
| 16-environment-matrix-generato | default | opus48-1m-high | 3.0 | 2.0 | 5.0 |
| 16-environment-matrix-generato | default | opus48-1m-medium | 3.0 | 2.0 | 5.0 |
| 16-environment-matrix-generato | default | opus48-1m-xhigh | 3.0 | 2.0 | 5.0 |
| 11-semantic-version-bumper | bash | opus48-1m-medium | 2.0 | 3.0 | 5.0 |
| 11-semantic-version-bumper | powershell | opus48-1m-medium | 2.0 | 3.0 | 5.0 |
| 11-semantic-version-bumper | typescript-bun | opus48-1m-high | 2.0 | 3.0 | 5.0 |
| 12-pr-label-assigner | default | opus48-1m-high | 2.0 | 3.0 | 5.0 |
| 12-pr-label-assigner | default | opus48-1m-medium | 2.0 | 3.0 | 5.0 |
| 12-pr-label-assigner | default | opus48-1m-ultracode | 2.0 | 3.0 | 5.0 |
| 12-pr-label-assigner | powershell-tool | opus48-1m-high | 2.0 | 3.0 | 5.0 |
| 12-pr-label-assigner | typescript-bun | opus48-1m-high | 2.0 | 3.0 | 5.0 |
| 13-dependency-license-checker | bash | opus48-1m-medium | 2.0 | 3.0 | 5.0 |
| 13-dependency-license-checker | bash | opus48-1m-ultracode | 2.0 | 3.0 | 5.0 |
| 13-dependency-license-checker | powershell | opus48-1m-medium | 2.0 | 3.0 | 5.0 |
| 13-dependency-license-checker | typescript-bun | opus48-1m-medium | 2.0 | 3.0 | 5.0 |
| 13-dependency-license-checker | typescript-bun | opus48-1m-ultracode | 2.0 | 3.0 | 5.0 |
| 15-test-results-aggregator | bash | opus48-1m-medium | 2.0 | 2.0 | 4.0 |
| 15-test-results-aggregator | bash | opus48-1m-ultracode | 2.0 | 2.0 | 4.0 |
| 15-test-results-aggregator | default | opus48-1m-high | 2.0 | 3.0 | 5.0 |
| 15-test-results-aggregator | powershell | opus48-1m-ultracode | 2.0 | 3.0 | 5.0 |
| 15-test-results-aggregator | powershell | opus48-1m-xhigh | 2.0 | 3.0 | 5.0 |

### Workflow Craft

| Task | Mode | Model | Span | haiku45 ovr | gemini31pro ovr |
|---|---|---|---|---|---|
| 17-artifact-cleanup-script | bash | opus48-1m-xhigh | 4.0 | 1.0 | 5.0 |
| 11-semantic-version-bumper | bash | opus48-1m-high | 3.0 | 2.0 | 5.0 |
| 11-semantic-version-bumper | bash | opus48-1m-medium | 3.0 | 2.0 | 5.0 |
| 11-semantic-version-bumper | default | opus48-1m-high | 3.0 | 2.0 | 5.0 |
| 11-semantic-version-bumper | powershell | opus48-1m-high | 3.0 | 2.0 | 5.0 |
| 11-semantic-version-bumper | powershell-tool | opus48-1m-high | 3.0 | 2.0 | 5.0 |
| 12-pr-label-assigner | bash | opus48-1m-high | 3.0 | 2.0 | 5.0 |
| 12-pr-label-assigner | bash | opus48-1m-xhigh | 3.0 | 2.0 | 5.0 |
| 12-pr-label-assigner | default | opus48-1m-xhigh | 3.0 | 2.0 | 5.0 |
| 12-pr-label-assigner | powershell | opus48-1m-high | 3.0 | 2.0 | 5.0 |
| 12-pr-label-assigner | powershell | opus48-1m-medium | 3.0 | 2.0 | 5.0 |
| 12-pr-label-assigner | typescript-bun | opus48-1m-high | 3.0 | 2.0 | 5.0 |
| 12-pr-label-assigner | typescript-bun | opus48-1m-xhigh | 3.0 | 2.0 | 5.0 |
| 13-dependency-license-checker | powershell | opus48-1m-high | 3.0 | 2.0 | 5.0 |
| 13-dependency-license-checker | powershell-tool | opus48-1m-high | 3.0 | 2.0 | 5.0 |
| 13-dependency-license-checker | powershell-tool | opus48-1m-ultracode | 3.0 | 2.0 | 5.0 |
| 13-dependency-license-checker | typescript-bun | opus48-1m-ultracode | 3.0 | 2.0 | 5.0 |
| 15-test-results-aggregator | default | opus48-1m-high | 3.0 | 2.0 | 5.0 |
| 15-test-results-aggregator | default | opus48-1m-xhigh | 3.0 | 2.0 | 5.0 |
| 15-test-results-aggregator | powershell | opus48-1m-high | 3.0 | 2.0 | 5.0 |
| 15-test-results-aggregator | powershell | opus48-1m-ultracode | 3.0 | 2.0 | 5.0 |
| 15-test-results-aggregator | typescript-bun | opus48-1m-medium | 3.0 | 2.0 | 5.0 |
| 16-environment-matrix-generato | bash | opus48-1m-medium | 3.0 | 1.0 | 4.0 |
| 16-environment-matrix-generato | bash | opus48-1m-xhigh | 3.0 | 2.0 | 5.0 |
| 16-environment-matrix-generato | powershell | opus48-1m-medium | 3.0 | 2.0 | 5.0 |

## Model rankings by judge

*Agreement on model ordering tells us the panel agrees on which configurations produce better output on this axis. Absolute-score differences between judges are expected (different grading scales) and are not a bias concern.*

### Tests Quality

| Model | haiku45 rank (mean, n) | gemini31pro rank (mean, n) |
|---|---|---|
| opus48-1m-ultracode | 1 (3.83, n=35) | 1 (4.94, n=35) |
| opus48-1m | 2 (3.50, n=104) | 2 (4.85, n=105) |

*Spearman rank correlation between haiku45 and gemini31pro: **+1.00**. (+1.0 = judges agree perfectly on ordering; 0 = no correlation; -1.0 = reversed.)*

*No pair-wise reversals — both judges agree on every model-vs-model ordering.*

### Workflow Craft

| Model | haiku45 rank (mean, n) | gemini31pro rank (mean, n) |
|---|---|---|
| opus48-1m | 1 (3.22, n=101) | 2 (4.92, n=105) |
| opus48-1m-ultracode | 2 (3.18, n=33) | 1 (4.94, n=35) |

*Spearman rank correlation between haiku45 and gemini31pro: **-1.00**. (+1.0 = judges agree perfectly on ordering; 0 = no correlation; -1.0 = reversed.)*

**Pair-wise reversals** (where the two judges disagree on which model is better):

| Pair | haiku45 prefers | gemini31pro prefers | Own-family signal? |
|---|---|---|---|
| opus48-1m vs opus48-1m-ultracode | opus48-1m | opus48-1m-ultracode | — |

## Language rankings by judge

*Agreement on language ordering tells us the panel agrees on which configurations produce better output on this axis. Absolute-score differences between judges are expected (different grading scales) and are not a bias concern.*

### Tests Quality

| Language | haiku45 rank (mean, n) | gemini31pro rank (mean, n) |
|---|---|---|
| powershell-tool | 1 (3.79, n=28) | 2 (5.00, n=28) |
| powershell | 2 (3.75, n=28) | 1 (5.00, n=28) |
| typescript-bun | 3 (3.75, n=28) | 3 (5.00, n=28) |
| default | 4 (3.46, n=28) | 4 (4.79, n=28) |
| bash | 5 (3.15, n=27) | 5 (4.57, n=28) |

*Spearman rank correlation between haiku45 and gemini31pro: **+0.90**. (+1.0 = judges agree perfectly on ordering; 0 = no correlation; -1.0 = reversed.)*

**Pair-wise reversals** (where the two judges disagree on which language is better):

| Pair | haiku45 prefers | gemini31pro prefers | Own-family signal? |
|---|---|---|---|
| powershell vs powershell-tool | powershell-tool | powershell | — |

### Workflow Craft

| Language | haiku45 rank (mean, n) | gemini31pro rank (mean, n) |
|---|---|---|
| powershell-tool | 1 (3.31, n=26) | 3 (4.93, n=28) |
| typescript-bun | 2 (3.26, n=27) | 4 (4.93, n=28) |
| powershell | 3 (3.18, n=28) | 2 (5.00, n=28) |
| default | 4 (3.15, n=26) | 1 (5.00, n=28) |
| bash | 5 (3.15, n=27) | 5 (4.79, n=28) |

*Spearman rank correlation between haiku45 and gemini31pro: **+0.10**. (+1.0 = judges agree perfectly on ordering; 0 = no correlation; -1.0 = reversed.)*

**Pair-wise reversals** (where the two judges disagree on which language is better):

| Pair | haiku45 prefers | gemini31pro prefers | Own-family signal? |
|---|---|---|---|
| default vs powershell | powershell | default | — |
| default vs powershell-tool | powershell-tool | default | — |
| default vs typescript-bun | typescript-bun | default | — |
| powershell vs powershell-tool | powershell-tool | powershell | — |
| powershell vs typescript-bun | typescript-bun | powershell | — |

## Language×Model rankings by judge

*Agreement on language×model ordering tells us the panel agrees on which configurations produce better output on this axis. Absolute-score differences between judges are expected (different grading scales) and are not a bias concern.*

### Tests Quality

| Language / Model | haiku45 rank (mean, n) | gemini31pro rank (mean, n) |
|---|---|---|
| default / opus48-1m-ultracode | 1 (4.14, n=7) | 1 (5.00, n=7) |
| powershell-tool / opus48-1m-ultracode | 2 (4.00, n=7) | 5 (5.00, n=7) |
| typescript-bun / opus48-1m-ultracode | 3 (4.00, n=7) | 7 (5.00, n=7) |
| powershell / opus48-1m-ultracode | 4 (3.86, n=7) | 3 (5.00, n=7) |
| powershell / opus48-1m | 5 (3.71, n=21) | 2 (5.00, n=21) |
| powershell-tool / opus48-1m | 6 (3.71, n=21) | 4 (5.00, n=21) |
| typescript-bun / opus48-1m | 7 (3.67, n=21) | 6 (5.00, n=21) |
| default / opus48-1m | 8 (3.24, n=21) | 9 (4.71, n=21) |
| bash / opus48-1m | 9 (3.15, n=20) | 10 (4.52, n=21) |
| bash / opus48-1m-ultracode | 10 (3.14, n=7) | 8 (4.71, n=7) |

*Spearman rank correlation between haiku45 and gemini31pro: **+0.72**. (+1.0 = judges agree perfectly on ordering; 0 = no correlation; -1.0 = reversed.)*

**Pair-wise reversals** (where the two judges disagree on which language×model is better):

| Pair | haiku45 prefers | gemini31pro prefers | Own-family signal? |
|---|---|---|---|
| bash / opus48-1m vs bash / opus48-1m-ultracode | bash / opus48-1m | bash / opus48-1m-ultracode | — |
| bash / opus48-1m-ultracode vs default / opus48-1m | default / opus48-1m | bash / opus48-1m-ultracode | — |
| powershell / opus48-1m vs powershell / opus48-1m-ultracode | powershell / opus48-1m-ultracode | powershell / opus48-1m | — |
| powershell / opus48-1m vs powershell-tool / opus48-1m-ultracode | powershell-tool / opus48-1m-ultracode | powershell / opus48-1m | — |
| powershell / opus48-1m vs typescript-bun / opus48-1m-ultracode | typescript-bun / opus48-1m-ultracode | powershell / opus48-1m | — |
| powershell / opus48-1m-ultracode vs powershell-tool / opus48-1m-ultracode | powershell-tool / opus48-1m-ultracode | powershell / opus48-1m-ultracode | — |
| powershell / opus48-1m-ultracode vs typescript-bun / opus48-1m-ultracode | typescript-bun / opus48-1m-ultracode | powershell / opus48-1m-ultracode | — |
| powershell-tool / opus48-1m vs powershell-tool / opus48-1m-ultracode | powershell-tool / opus48-1m-ultracode | powershell-tool / opus48-1m | — |
| powershell-tool / opus48-1m vs typescript-bun / opus48-1m-ultracode | typescript-bun / opus48-1m-ultracode | powershell-tool / opus48-1m | — |
| typescript-bun / opus48-1m vs typescript-bun / opus48-1m-ultracode | typescript-bun / opus48-1m-ultracode | typescript-bun / opus48-1m | — |

### Workflow Craft

| Language / Model | haiku45 rank (mean, n) | gemini31pro rank (mean, n) |
|---|---|---|
| bash / opus48-1m-ultracode | 1 (3.57, n=7) | 10 (4.71, n=7) |
| typescript-bun / opus48-1m | 2 (3.45, n=20) | 8 (4.90, n=21) |
| powershell-tool / opus48-1m-ultracode | 3 (3.33, n=6) | 5 (5.00, n=7) |
| powershell-tool / opus48-1m | 4 (3.30, n=20) | 7 (4.90, n=21) |
| powershell / opus48-1m | 5 (3.19, n=21) | 3 (5.00, n=21) |
| default / opus48-1m-ultracode | 6 (3.17, n=6) | 2 (5.00, n=7) |
| default / opus48-1m | 7 (3.15, n=20) | 1 (5.00, n=21) |
| powershell / opus48-1m-ultracode | 8 (3.14, n=7) | 4 (5.00, n=7) |
| bash / opus48-1m | 9 (3.00, n=20) | 9 (4.81, n=21) |
| typescript-bun / opus48-1m-ultracode | 10 (2.71, n=7) | 6 (5.00, n=7) |

*Spearman rank correlation between haiku45 and gemini31pro: **-0.32**. (+1.0 = judges agree perfectly on ordering; 0 = no correlation; -1.0 = reversed.)*

**Pair-wise reversals** (where the two judges disagree on which language×model is better):

| Pair | haiku45 prefers | gemini31pro prefers | Own-family signal? |
|---|---|---|---|
| bash / opus48-1m vs bash / opus48-1m-ultracode | bash / opus48-1m-ultracode | bash / opus48-1m | — |
| bash / opus48-1m vs typescript-bun / opus48-1m-ultracode | bash / opus48-1m | typescript-bun / opus48-1m-ultracode | — |
| bash / opus48-1m-ultracode vs default / opus48-1m | bash / opus48-1m-ultracode | default / opus48-1m | — |
| bash / opus48-1m-ultracode vs default / opus48-1m-ultracode | bash / opus48-1m-ultracode | default / opus48-1m-ultracode | — |
| bash / opus48-1m-ultracode vs powershell / opus48-1m | bash / opus48-1m-ultracode | powershell / opus48-1m | — |
| bash / opus48-1m-ultracode vs powershell / opus48-1m-ultracode | bash / opus48-1m-ultracode | powershell / opus48-1m-ultracode | — |
| bash / opus48-1m-ultracode vs powershell-tool / opus48-1m | bash / opus48-1m-ultracode | powershell-tool / opus48-1m | — |
| bash / opus48-1m-ultracode vs powershell-tool / opus48-1m-ultracode | bash / opus48-1m-ultracode | powershell-tool / opus48-1m-ultracode | — |
| bash / opus48-1m-ultracode vs typescript-bun / opus48-1m | bash / opus48-1m-ultracode | typescript-bun / opus48-1m | — |
| bash / opus48-1m-ultracode vs typescript-bun / opus48-1m-ultracode | bash / opus48-1m-ultracode | typescript-bun / opus48-1m-ultracode | — |
| default / opus48-1m vs default / opus48-1m-ultracode | default / opus48-1m-ultracode | default / opus48-1m | — |
| default / opus48-1m vs powershell / opus48-1m | powershell / opus48-1m | default / opus48-1m | — |
| default / opus48-1m vs powershell-tool / opus48-1m | powershell-tool / opus48-1m | default / opus48-1m | — |
| default / opus48-1m vs powershell-tool / opus48-1m-ultracode | powershell-tool / opus48-1m-ultracode | default / opus48-1m | — |
| default / opus48-1m vs typescript-bun / opus48-1m | typescript-bun / opus48-1m | default / opus48-1m | — |
| default / opus48-1m-ultracode vs powershell / opus48-1m | powershell / opus48-1m | default / opus48-1m-ultracode | — |
| default / opus48-1m-ultracode vs powershell-tool / opus48-1m | powershell-tool / opus48-1m | default / opus48-1m-ultracode | — |
| default / opus48-1m-ultracode vs powershell-tool / opus48-1m-ultracode | powershell-tool / opus48-1m-ultracode | default / opus48-1m-ultracode | — |
| default / opus48-1m-ultracode vs typescript-bun / opus48-1m | typescript-bun / opus48-1m | default / opus48-1m-ultracode | — |
| powershell / opus48-1m vs powershell-tool / opus48-1m | powershell-tool / opus48-1m | powershell / opus48-1m | — |
| powershell / opus48-1m vs powershell-tool / opus48-1m-ultracode | powershell-tool / opus48-1m-ultracode | powershell / opus48-1m | — |
| powershell / opus48-1m vs typescript-bun / opus48-1m | typescript-bun / opus48-1m | powershell / opus48-1m | — |
| powershell / opus48-1m-ultracode vs powershell-tool / opus48-1m | powershell-tool / opus48-1m | powershell / opus48-1m-ultracode | — |
| powershell / opus48-1m-ultracode vs powershell-tool / opus48-1m-ultracode | powershell-tool / opus48-1m-ultracode | powershell / opus48-1m-ultracode | — |
| powershell / opus48-1m-ultracode vs typescript-bun / opus48-1m | typescript-bun / opus48-1m | powershell / opus48-1m-ultracode | — |
| powershell-tool / opus48-1m vs typescript-bun / opus48-1m | typescript-bun / opus48-1m | powershell-tool / opus48-1m | — |
| powershell-tool / opus48-1m vs typescript-bun / opus48-1m-ultracode | powershell-tool / opus48-1m | typescript-bun / opus48-1m-ultracode | — |
| powershell-tool / opus48-1m-ultracode vs typescript-bun / opus48-1m | typescript-bun / opus48-1m | powershell-tool / opus48-1m-ultracode | — |
| typescript-bun / opus48-1m vs typescript-bun / opus48-1m-ultracode | typescript-bun / opus48-1m | typescript-bun / opus48-1m-ultracode | — |

## Per-run self-judgment rows (reference)

*Rows where a judge evaluated output from its own model family. These individual runs are kept as a sanity check — the actual bias test is the pair-wise ranking reversals in the table above. Filtered to rows whose inter-judge delta differs from the baseline delta by ≥1.0 point; such rows are plausibly interesting but don't by themselves indicate bias (absolute-score differences between judges are expected).*

### Tests Quality

*Baseline delta (gemini31pro − haiku45) across the whole dataset: **+1.29**.*

*(no self-judgment rows exceed the 1.0-point deviation threshold — judges agree about in-family output roughly as much as about out-of-family output)*

### Workflow Craft

*Baseline delta (gemini31pro − haiku45) across the whole dataset: **+1.72**.*

*(no self-judgment rows exceed the 1.0-point deviation threshold — judges agree about in-family output roughly as much as about out-of-family output)*

