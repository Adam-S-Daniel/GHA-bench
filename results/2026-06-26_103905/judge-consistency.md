# Judge Consistency Data

*Raw panel-of-judges data plus a rankings-focused Quality Analysis. Backs the merged Conclusions and Judge Consistency Summary in the corresponding [`results.md`](results.md).*

## Notes

- **Generated:** 2026-06-28 06:53:06 PM ET
- **Source:** `/home/passp/repos/GHA-bench/.claude/worktrees/opus48-bench/results/2026-06-26_103905`
- **Judges present:** haiku45, gemini31pro
- **Score conventions:** Scores shown are the `overall` dimension from each judge (1-5). Δ column is the second judge minus the first; positive = second judge is more generous.

## Quality Analysis

opus48-1m-ultracode produces the strongest test suites in the panel — both judges rank it #1 on Tests Quality with perfect rank agreement (ρ = +1.00, zero reversals). For language fit on tests, powershell-tool, typescript-bun, and powershell cluster at the top for both judges, while bash sits last on every axis the panel scored.

- **Top performer**: opus48-1m-ultracode leads Tests Quality across both judges, with haiku45 at 3.85 and gemini31pro at 4.94 — the only model ordering with no reversals on either axis.
- **Best by language**: the powershell-tool / typescript-bun / powershell trio holds the top three Tests Quality slots for both judges (ρ = +0.70); the two reversals stay inside that cluster, so the top-versus-bottom split is unambiguous.
- **Bash floor**: bash ranks last for both judges on both Tests Quality and Workflow Craft — one of the very few orderings both judges agree on in the Workflow Craft view.
- **Effort tier**: the ultracode tier lifts Tests Quality above the standard opus48-1m baseline for both judges (3.85 vs 3.46 on haiku45; 4.94 vs 4.85 on gemini31pro).
- **Workflow Craft ceiling**: judges diverge sharply on Workflow Craft language ordering (ρ = +0.00, six pair-wise reversals) and flip the model ordering outright (ρ = −1.00), so language conclusions on the deliverable axis carry far less confidence than the Tests Quality ones.

*Provenance:* `claude-opus-4-7[1m]` at effort `xhigh` via Claude CLI; 5 in / 1571 out tokens, $0.4359. Prompt: [`QUALITY_ANALYSIS_SYSTEM_PROMPT`](../../judge_consistency_report.py).

## Campaign summary

### Tests Quality

| Scope | n | haiku45 ovr | gemini31pro ovr | Δ(gemini31pro−haiku45) |
|---|---|---|---|---|
| all | 135 | 3.56 | 4.87 | +1.31 |

### Workflow Craft

| Scope | n | haiku45 ovr | gemini31pro ovr | Δ(gemini31pro−haiku45) |
|---|---|---|---|---|
| all | 130 | 3.09 | 4.92 | +1.83 |

## By task

### Tests Quality

| Task | n | haiku45 ovr | gemini31pro ovr | Δ(gemini31pro−haiku45) |
|---|---|---|---|---|
| 11-semantic-version-bumper | 20 | 3.70 | 4.75 | +1.05 |
| 12-pr-label-assigner | 20 | 3.55 | 4.85 | +1.30 |
| 13-dependency-license-checker | 20 | 3.45 | 4.85 | +1.40 |
| 15-test-results-aggregator | 19 | 3.53 | 4.79 | +1.26 |
| 16-environment-matrix-generator | 19 | 3.53 | 5.00 | +1.47 |
| 17-artifact-cleanup-script | 19 | 3.53 | 4.84 | +1.32 |
| 18-secret-rotation-validator | 18 | 3.61 | 5.00 | +1.39 |

### Workflow Craft

| Task | n | haiku45 ovr | gemini31pro ovr | Δ(gemini31pro−haiku45) |
|---|---|---|---|---|
| 11-semantic-version-bumper | 20 | 3.25 | 5.00 | +1.75 |
| 12-pr-label-assigner | 20 | 2.90 | 4.95 | +2.05 |
| 13-dependency-license-checker | 19 | 3.37 | 4.74 | +1.37 |
| 15-test-results-aggregator | 19 | 3.37 | 4.95 | +1.58 |
| 16-environment-matrix-generator | 19 | 3.00 | 4.95 | +1.95 |
| 17-artifact-cleanup-script | 17 | 2.94 | 4.94 | +2.00 |
| 18-secret-rotation-validator | 16 | 2.75 | 4.94 | +2.19 |

## By language mode

### Tests Quality

| Mode | n | haiku45 ovr | gemini31pro ovr | Δ(gemini31pro−haiku45) |
|---|---|---|---|---|
| bash | 26 | 3.00 | 4.54 | +1.54 |
| default | 26 | 3.42 | 4.77 | +1.35 |
| powershell | 28 | 3.75 | 5.00 | +1.25 |
| powershell-tool | 28 | 3.79 | 5.00 | +1.21 |
| typescript-bun | 27 | 3.78 | 5.00 | +1.22 |

### Workflow Craft

| Mode | n | haiku45 ovr | gemini31pro ovr | Δ(gemini31pro−haiku45) |
|---|---|---|---|---|
| bash | 26 | 2.96 | 4.77 | +1.81 |
| default | 25 | 3.00 | 5.00 | +2.00 |
| powershell | 24 | 3.12 | 5.00 | +1.88 |
| powershell-tool | 28 | 3.14 | 4.93 | +1.79 |
| typescript-bun | 27 | 3.22 | 4.93 | +1.70 |

## By model + effort

### Tests Quality

| Model-Effort | n | haiku45 ovr | gemini31pro ovr | Δ(gemini31pro−haiku45) |
|---|---|---|---|---|
| opus48-1m-high | 34 | 3.47 | 4.76 | +1.29 |
| opus48-1m-medium | 34 | 3.24 | 4.82 | +1.59 |
| opus48-1m-ultracode | 33 | 3.85 | 4.94 | +1.09 |
| opus48-1m-xhigh | 34 | 3.68 | 4.94 | +1.26 |

### Workflow Craft

| Model-Effort | n | haiku45 ovr | gemini31pro ovr | Δ(gemini31pro−haiku45) |
|---|---|---|---|---|
| opus48-1m-high | 31 | 2.84 | 4.97 | +2.13 |
| opus48-1m-medium | 32 | 3.16 | 4.81 | +1.66 |
| opus48-1m-ultracode | 34 | 3.03 | 4.94 | +1.91 |
| opus48-1m-xhigh | 33 | 3.33 | 4.97 | +1.64 |

## Disagreement hotspots (panel span ≥ 2 on overall)

### Tests Quality

| Task | Mode | Model | Span | haiku45 ovr | gemini31pro ovr |
|---|---|---|---|---|---|
| 17-artifact-cleanup-script | bash | opus48-1m-high | 4.0 | 1.0 | 5.0 |
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

### Workflow Craft

| Task | Mode | Model | Span | haiku45 ovr | gemini31pro ovr |
|---|---|---|---|---|---|
| 12-pr-label-assigner | powershell-tool | opus48-1m-ultracode | 4.0 | 1.0 | 5.0 |
| 15-test-results-aggregator | default | opus48-1m-medium | 4.0 | 1.0 | 5.0 |
| 16-environment-matrix-generato | bash | opus48-1m-high | 4.0 | 1.0 | 5.0 |
| 16-environment-matrix-generato | default | opus48-1m-ultracode | 4.0 | 1.0 | 5.0 |
| 17-artifact-cleanup-script | bash | opus48-1m-xhigh | 4.0 | 1.0 | 5.0 |
| 17-artifact-cleanup-script | powershell-tool | opus48-1m-high | 4.0 | 1.0 | 5.0 |
| 18-secret-rotation-validator | typescript-bun | opus48-1m-high | 4.0 | 1.0 | 5.0 |
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
| 15-test-results-aggregator | default | opus48-1m-xhigh | 3.0 | 2.0 | 5.0 |
| 15-test-results-aggregator | powershell | opus48-1m-high | 3.0 | 2.0 | 5.0 |

## Model rankings by judge

*Agreement on model ordering tells us the panel agrees on which configurations produce better output on this axis. Absolute-score differences between judges are expected (different grading scales) and are not a bias concern.*

### Tests Quality

| Model | haiku45 rank (mean, n) | gemini31pro rank (mean, n) |
|---|---|---|
| opus48-1m-ultracode | 1 (3.85, n=33) | 1 (4.94, n=35) |
| opus48-1m | 2 (3.46, n=102) | 2 (4.85, n=105) |

*Spearman rank correlation between haiku45 and gemini31pro: **+1.00**. (+1.0 = judges agree perfectly on ordering; 0 = no correlation; -1.0 = reversed.)*

*No pair-wise reversals — both judges agree on every model-vs-model ordering.*

### Workflow Craft

| Model | haiku45 rank (mean, n) | gemini31pro rank (mean, n) |
|---|---|---|
| opus48-1m | 1 (3.11, n=96) | 2 (4.92, n=105) |
| opus48-1m-ultracode | 2 (3.03, n=34) | 1 (4.94, n=35) |

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
| typescript-bun | 2 (3.78, n=27) | 3 (5.00, n=28) |
| powershell | 3 (3.75, n=28) | 1 (5.00, n=28) |
| default | 4 (3.42, n=26) | 4 (4.79, n=28) |
| bash | 5 (3.00, n=26) | 5 (4.57, n=28) |

*Spearman rank correlation between haiku45 and gemini31pro: **+0.70**. (+1.0 = judges agree perfectly on ordering; 0 = no correlation; -1.0 = reversed.)*

**Pair-wise reversals** (where the two judges disagree on which language is better):

| Pair | haiku45 prefers | gemini31pro prefers | Own-family signal? |
|---|---|---|---|
| powershell vs powershell-tool | powershell-tool | powershell | — |
| powershell vs typescript-bun | typescript-bun | powershell | — |

### Workflow Craft

| Language | haiku45 rank (mean, n) | gemini31pro rank (mean, n) |
|---|---|---|
| typescript-bun | 1 (3.22, n=27) | 4 (4.93, n=28) |
| powershell-tool | 2 (3.14, n=28) | 3 (4.93, n=28) |
| powershell | 3 (3.12, n=24) | 2 (5.00, n=28) |
| default | 4 (3.00, n=25) | 1 (5.00, n=28) |
| bash | 5 (2.96, n=26) | 5 (4.79, n=28) |

*Spearman rank correlation between haiku45 and gemini31pro: **+0.00**. (+1.0 = judges agree perfectly on ordering; 0 = no correlation; -1.0 = reversed.)*

**Pair-wise reversals** (where the two judges disagree on which language is better):

| Pair | haiku45 prefers | gemini31pro prefers | Own-family signal? |
|---|---|---|---|
| default vs powershell | powershell | default | — |
| default vs powershell-tool | powershell-tool | default | — |
| default vs typescript-bun | typescript-bun | default | — |
| powershell vs powershell-tool | powershell-tool | powershell | — |
| powershell vs typescript-bun | typescript-bun | powershell | — |
| powershell-tool vs typescript-bun | typescript-bun | powershell-tool | — |

## Language×Model rankings by judge

*Agreement on language×model ordering tells us the panel agrees on which configurations produce better output on this axis. Absolute-score differences between judges are expected (different grading scales) and are not a bias concern.*

### Tests Quality

| Language / Model | haiku45 rank (mean, n) | gemini31pro rank (mean, n) |
|---|---|---|
| typescript-bun / opus48-1m-ultracode | 1 (4.17, n=6) | 7 (5.00, n=7) |
| default / opus48-1m-ultracode | 2 (4.14, n=7) | 1 (5.00, n=7) |
| powershell-tool / opus48-1m-ultracode | 3 (4.00, n=7) | 5 (5.00, n=7) |
| powershell / opus48-1m-ultracode | 4 (3.86, n=7) | 3 (5.00, n=7) |
| powershell / opus48-1m | 5 (3.71, n=21) | 2 (5.00, n=21) |
| powershell-tool / opus48-1m | 6 (3.71, n=21) | 4 (5.00, n=21) |
| typescript-bun / opus48-1m | 7 (3.67, n=21) | 6 (5.00, n=21) |
| default / opus48-1m | 8 (3.16, n=19) | 9 (4.71, n=21) |
| bash / opus48-1m | 9 (3.00, n=20) | 10 (4.52, n=21) |
| bash / opus48-1m-ultracode | 10 (3.00, n=6) | 8 (4.71, n=7) |

*Spearman rank correlation between haiku45 and gemini31pro: **+0.62**. (+1.0 = judges agree perfectly on ordering; 0 = no correlation; -1.0 = reversed.)*

**Pair-wise reversals** (where the two judges disagree on which language×model is better):

| Pair | haiku45 prefers | gemini31pro prefers | Own-family signal? |
|---|---|---|---|
| bash / opus48-1m vs bash / opus48-1m-ultracode | bash / opus48-1m | bash / opus48-1m-ultracode | — |
| bash / opus48-1m-ultracode vs default / opus48-1m | default / opus48-1m | bash / opus48-1m-ultracode | — |
| default / opus48-1m-ultracode vs typescript-bun / opus48-1m-ultracode | typescript-bun / opus48-1m-ultracode | default / opus48-1m-ultracode | — |
| powershell / opus48-1m vs powershell / opus48-1m-ultracode | powershell / opus48-1m-ultracode | powershell / opus48-1m | — |
| powershell / opus48-1m vs powershell-tool / opus48-1m-ultracode | powershell-tool / opus48-1m-ultracode | powershell / opus48-1m | — |
| powershell / opus48-1m vs typescript-bun / opus48-1m-ultracode | typescript-bun / opus48-1m-ultracode | powershell / opus48-1m | — |
| powershell / opus48-1m-ultracode vs powershell-tool / opus48-1m-ultracode | powershell-tool / opus48-1m-ultracode | powershell / opus48-1m-ultracode | — |
| powershell / opus48-1m-ultracode vs typescript-bun / opus48-1m-ultracode | typescript-bun / opus48-1m-ultracode | powershell / opus48-1m-ultracode | — |
| powershell-tool / opus48-1m vs powershell-tool / opus48-1m-ultracode | powershell-tool / opus48-1m-ultracode | powershell-tool / opus48-1m | — |
| powershell-tool / opus48-1m vs typescript-bun / opus48-1m-ultracode | typescript-bun / opus48-1m-ultracode | powershell-tool / opus48-1m | — |
| powershell-tool / opus48-1m-ultracode vs typescript-bun / opus48-1m-ultracode | typescript-bun / opus48-1m-ultracode | powershell-tool / opus48-1m-ultracode | — |
| typescript-bun / opus48-1m vs typescript-bun / opus48-1m-ultracode | typescript-bun / opus48-1m-ultracode | typescript-bun / opus48-1m | — |

### Workflow Craft

| Language / Model | haiku45 rank (mean, n) | gemini31pro rank (mean, n) |
|---|---|---|
| bash / opus48-1m-ultracode | 1 (3.57, n=7) | 10 (4.71, n=7) |
| typescript-bun / opus48-1m | 2 (3.40, n=20) | 8 (4.90, n=21) |
| powershell-tool / opus48-1m | 3 (3.19, n=21) | 7 (4.90, n=21) |
| powershell / opus48-1m | 4 (3.17, n=18) | 3 (5.00, n=21) |
| default / opus48-1m | 5 (3.06, n=18) | 1 (5.00, n=21) |
| powershell / opus48-1m-ultracode | 6 (3.00, n=6) | 4 (5.00, n=7) |
| powershell-tool / opus48-1m-ultracode | 7 (3.00, n=7) | 5 (5.00, n=7) |
| default / opus48-1m-ultracode | 8 (2.86, n=7) | 2 (5.00, n=7) |
| bash / opus48-1m | 9 (2.74, n=19) | 9 (4.81, n=21) |
| typescript-bun / opus48-1m-ultracode | 10 (2.71, n=7) | 6 (5.00, n=7) |

*Spearman rank correlation between haiku45 and gemini31pro: **-0.27**. (+1.0 = judges agree perfectly on ordering; 0 = no correlation; -1.0 = reversed.)*

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
| default / opus48-1m vs powershell / opus48-1m | powershell / opus48-1m | default / opus48-1m | — |
| default / opus48-1m vs powershell-tool / opus48-1m | powershell-tool / opus48-1m | default / opus48-1m | — |
| default / opus48-1m vs typescript-bun / opus48-1m | typescript-bun / opus48-1m | default / opus48-1m | — |
| default / opus48-1m-ultracode vs powershell / opus48-1m | powershell / opus48-1m | default / opus48-1m-ultracode | — |
| default / opus48-1m-ultracode vs powershell / opus48-1m-ultracode | powershell / opus48-1m-ultracode | default / opus48-1m-ultracode | — |
| default / opus48-1m-ultracode vs powershell-tool / opus48-1m | powershell-tool / opus48-1m | default / opus48-1m-ultracode | — |
| default / opus48-1m-ultracode vs powershell-tool / opus48-1m-ultracode | powershell-tool / opus48-1m-ultracode | default / opus48-1m-ultracode | — |
| default / opus48-1m-ultracode vs typescript-bun / opus48-1m | typescript-bun / opus48-1m | default / opus48-1m-ultracode | — |
| powershell / opus48-1m vs powershell-tool / opus48-1m | powershell-tool / opus48-1m | powershell / opus48-1m | — |
| powershell / opus48-1m vs typescript-bun / opus48-1m | typescript-bun / opus48-1m | powershell / opus48-1m | — |
| powershell / opus48-1m-ultracode vs powershell-tool / opus48-1m | powershell-tool / opus48-1m | powershell / opus48-1m-ultracode | — |
| powershell / opus48-1m-ultracode vs typescript-bun / opus48-1m | typescript-bun / opus48-1m | powershell / opus48-1m-ultracode | — |
| powershell-tool / opus48-1m vs powershell-tool / opus48-1m-ultracode | powershell-tool / opus48-1m | powershell-tool / opus48-1m-ultracode | — |
| powershell-tool / opus48-1m vs typescript-bun / opus48-1m | typescript-bun / opus48-1m | powershell-tool / opus48-1m | — |
| powershell-tool / opus48-1m vs typescript-bun / opus48-1m-ultracode | powershell-tool / opus48-1m | typescript-bun / opus48-1m-ultracode | — |
| powershell-tool / opus48-1m-ultracode vs typescript-bun / opus48-1m | typescript-bun / opus48-1m | powershell-tool / opus48-1m-ultracode | — |
| typescript-bun / opus48-1m vs typescript-bun / opus48-1m-ultracode | typescript-bun / opus48-1m | typescript-bun / opus48-1m-ultracode | — |

## Per-run self-judgment rows (reference)

*Rows where a judge evaluated output from its own model family. These individual runs are kept as a sanity check — the actual bias test is the pair-wise ranking reversals in the table above. Filtered to rows whose inter-judge delta differs from the baseline delta by ≥1.0 point; such rows are plausibly interesting but don't by themselves indicate bias (absolute-score differences between judges are expected).*

### Tests Quality

*Baseline delta (gemini31pro − haiku45) across the whole dataset: **+1.31**.*

*(no self-judgment rows exceed the 1.0-point deviation threshold — judges agree about in-family output roughly as much as about out-of-family output)*

### Workflow Craft

*Baseline delta (gemini31pro − haiku45) across the whole dataset: **+1.83**.*

*(no self-judgment rows exceed the 1.0-point deviation threshold — judges agree about in-family output roughly as much as about out-of-family output)*

