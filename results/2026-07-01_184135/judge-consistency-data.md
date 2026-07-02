# Judge Consistency Data

*Raw panel-of-judges data plus a rankings-focused Quality Analysis. Backs the merged Conclusions and Judge Consistency Summary in the corresponding [`results.md`](results.md).*

## Notes

- **Generated:** 2026-07-02 09:58:11 AM ET
- **Source:** `/home/passp/repos/GHA-bench-integration/results/2026-07-01_184135`
- **Judges present:** haiku45, gemini31pro
- **Score conventions:** Scores shown are the `overall` dimension from each judge (1-5). Δ column is the second judge minus the first; positive = second judge is more generous.

## Quality Analysis

The panel converges on fable5 as the top-scoring model on both Tests Quality and Workflow Craft, with no pair-wise model reversals across the two judges. Both judges also agree that the default (python) language is the weakest choice for Tests Quality, though language ordering on Workflow Craft splits sharply between the panel (ρ = -0.60).

- **Top performer**: fable5 sits at rank 1 on both axes for both judges; Haiku shows fable5-high edging fable5-medium on Workflow Craft (3.36 vs 3.00) while Gemini treats the two effort tiers as equal (4.89 each), so the high tier has at most a small measurable lift.
- **Best by language for Tests Quality**: Both judges place default at the bottom (Haiku 2.86, Gemini 3.57) — the one place their language orderings agree — while bash, powershell, and typescript-bun tie for Gemini at 5.00.
- **Effort tier**: The high-vs-medium gap barely registers on Tests Quality — both judges score the tiers within 0.07 of each other — and only appears at all in Haiku's Workflow Craft numbers (+0.36).
- **Workflow Craft ceiling**: Gemini caps bash and powershell at 5.00, but Haiku ranks those same two languages last (3.14 and 3.00); the ρ = -0.60 correlation and four pair-wise reversals mean the panel offers no shared verdict on language for shippable workflows.
- **Where rankings diverge**: All disagreement lives on the language axis, not the model axis — zero model reversals on either metric, versus two language reversals on Tests Quality and four on Workflow Craft.

*Provenance:* `claude-opus-4-7[1m]` at effort `xhigh` via Claude CLI (from cache); 5 in / 3935 out tokens, $0.2362. Prompt: [`QUALITY_ANALYSIS_SYSTEM_PROMPT`](../../judge_consistency_report.py).

## Campaign summary

### Tests Quality

| Scope | n | haiku45 ovr | gemini31pro ovr | Δ(gemini31pro−haiku45) |
|---|---|---|---|---|
| all | 56 | 3.46 | 4.64 | +1.18 |

### Workflow Craft

| Scope | n | haiku45 ovr | gemini31pro ovr | Δ(gemini31pro−haiku45) |
|---|---|---|---|---|
| all | 56 | 3.18 | 4.89 | +1.71 |

## By task

### Tests Quality

| Task | n | haiku45 ovr | gemini31pro ovr | Δ(gemini31pro−haiku45) |
|---|---|---|---|---|
| 11-semantic-version-bumper | 8 | 3.38 | 4.00 | +0.62 |
| 12-pr-label-assigner | 8 | 3.62 | 4.62 | +1.00 |
| 13-dependency-license-checker | 8 | 3.38 | 4.62 | +1.25 |
| 15-test-results-aggregator | 8 | 3.50 | 5.00 | +1.50 |
| 16-environment-matrix-generator | 8 | 3.38 | 4.62 | +1.25 |
| 17-artifact-cleanup-script | 8 | 3.50 | 5.00 | +1.50 |
| 18-secret-rotation-validator | 8 | 3.50 | 4.62 | +1.12 |

### Workflow Craft

| Task | n | haiku45 ovr | gemini31pro ovr | Δ(gemini31pro−haiku45) |
|---|---|---|---|---|
| 11-semantic-version-bumper | 8 | 3.75 | 5.00 | +1.25 |
| 12-pr-label-assigner | 8 | 2.62 | 4.88 | +2.25 |
| 13-dependency-license-checker | 8 | 3.12 | 5.00 | +1.88 |
| 15-test-results-aggregator | 8 | 3.00 | 5.00 | +2.00 |
| 16-environment-matrix-generator | 8 | 3.00 | 4.88 | +1.88 |
| 17-artifact-cleanup-script | 8 | 3.12 | 4.88 | +1.75 |
| 18-secret-rotation-validator | 8 | 3.62 | 4.62 | +1.00 |

## By language mode

### Tests Quality

| Mode | n | haiku45 ovr | gemini31pro ovr | Δ(gemini31pro−haiku45) |
|---|---|---|---|---|
| bash | 14 | 3.43 | 5.00 | +1.57 |
| default | 14 | 2.86 | 3.57 | +0.71 |
| powershell | 14 | 3.86 | 5.00 | +1.14 |
| typescript-bun | 14 | 3.71 | 5.00 | +1.29 |

### Workflow Craft

| Mode | n | haiku45 ovr | gemini31pro ovr | Δ(gemini31pro−haiku45) |
|---|---|---|---|---|
| bash | 14 | 3.14 | 5.00 | +1.86 |
| default | 14 | 3.29 | 4.79 | +1.50 |
| powershell | 14 | 3.00 | 5.00 | +2.00 |
| typescript-bun | 14 | 3.29 | 4.79 | +1.50 |

## By model + effort

### Tests Quality

| Model-Effort | n | haiku45 ovr | gemini31pro ovr | Δ(gemini31pro−haiku45) |
|---|---|---|---|---|
| fable5-high | 28 | 3.43 | 4.64 | +1.21 |
| fable5-medium | 28 | 3.50 | 4.64 | +1.14 |

### Workflow Craft

| Model-Effort | n | haiku45 ovr | gemini31pro ovr | Δ(gemini31pro−haiku45) |
|---|---|---|---|---|
| fable5-high | 28 | 3.36 | 4.89 | +1.54 |
| fable5-medium | 28 | 3.00 | 4.89 | +1.89 |

## Disagreement hotspots (panel span ≥ 2 on overall)

### Tests Quality

| Task | Mode | Model | Span | haiku45 ovr | gemini31pro ovr |
|---|---|---|---|---|---|
| 15-test-results-aggregator | typescript-bun | fable5-high | 3.0 | 2.0 | 5.0 |
| 17-artifact-cleanup-script | bash | fable5-medium | 3.0 | 2.0 | 5.0 |
| 11-semantic-version-bumper | powershell | fable5-high | 2.0 | 3.0 | 5.0 |
| 12-pr-label-assigner | bash | fable5-high | 2.0 | 3.0 | 5.0 |
| 13-dependency-license-checker | bash | fable5-high | 2.0 | 3.0 | 5.0 |
| 13-dependency-license-checker | bash | fable5-medium | 2.0 | 3.0 | 5.0 |
| 13-dependency-license-checker | typescript-bun | fable5-medium | 2.0 | 3.0 | 5.0 |
| 15-test-results-aggregator | bash | fable5-medium | 2.0 | 3.0 | 5.0 |
| 15-test-results-aggregator | default | fable5-high | 2.0 | 3.0 | 5.0 |
| 15-test-results-aggregator | powershell | fable5-high | 2.0 | 3.0 | 5.0 |
| 16-environment-matrix-generato | bash | fable5-high | 2.0 | 3.0 | 5.0 |
| 16-environment-matrix-generato | default | fable5-medium | 2.0 | 3.0 | 5.0 |
| 16-environment-matrix-generato | typescript-bun | fable5-high | 2.0 | 3.0 | 5.0 |
| 17-artifact-cleanup-script | default | fable5-medium | 2.0 | 3.0 | 5.0 |
| 17-artifact-cleanup-script | typescript-bun | fable5-medium | 2.0 | 3.0 | 5.0 |
| 18-secret-rotation-validator | bash | fable5-medium | 2.0 | 3.0 | 5.0 |
| 18-secret-rotation-validator | default | fable5-high | 2.0 | 3.0 | 5.0 |

### Workflow Craft

| Task | Mode | Model | Span | haiku45 ovr | gemini31pro ovr |
|---|---|---|---|---|---|
| 12-pr-label-assigner | powershell | fable5-medium | 4.0 | 1.0 | 5.0 |
| 13-dependency-license-checker | default | fable5-high | 4.0 | 1.0 | 5.0 |
| 11-semantic-version-bumper | powershell | fable5-medium | 3.0 | 2.0 | 5.0 |
| 12-pr-label-assigner | default | fable5-medium | 3.0 | 2.0 | 5.0 |
| 12-pr-label-assigner | typescript-bun | fable5-medium | 3.0 | 2.0 | 5.0 |
| 13-dependency-license-checker | powershell | fable5-medium | 3.0 | 2.0 | 5.0 |
| 15-test-results-aggregator | bash | fable5-high | 3.0 | 2.0 | 5.0 |
| 15-test-results-aggregator | bash | fable5-medium | 3.0 | 2.0 | 5.0 |
| 15-test-results-aggregator | powershell | fable5-medium | 3.0 | 2.0 | 5.0 |
| 15-test-results-aggregator | typescript-bun | fable5-high | 3.0 | 2.0 | 5.0 |
| 16-environment-matrix-generato | powershell | fable5-medium | 3.0 | 2.0 | 5.0 |
| 16-environment-matrix-generato | typescript-bun | fable5-high | 3.0 | 2.0 | 5.0 |
| 17-artifact-cleanup-script | default | fable5-medium | 3.0 | 2.0 | 5.0 |
| 11-semantic-version-bumper | powershell | fable5-high | 2.0 | 3.0 | 5.0 |
| 12-pr-label-assigner | bash | fable5-high | 2.0 | 3.0 | 5.0 |
| 12-pr-label-assigner | bash | fable5-medium | 2.0 | 3.0 | 5.0 |
| 12-pr-label-assigner | typescript-bun | fable5-high | 2.0 | 2.0 | 4.0 |
| 13-dependency-license-checker | bash | fable5-high | 2.0 | 3.0 | 5.0 |
| 13-dependency-license-checker | bash | fable5-medium | 2.0 | 3.0 | 5.0 |
| 15-test-results-aggregator | default | fable5-high | 2.0 | 3.0 | 5.0 |
| 16-environment-matrix-generato | bash | fable5-high | 2.0 | 3.0 | 5.0 |
| 16-environment-matrix-generato | bash | fable5-medium | 2.0 | 3.0 | 5.0 |
| 16-environment-matrix-generato | default | fable5-medium | 2.0 | 2.0 | 4.0 |
| 17-artifact-cleanup-script | bash | fable5-medium | 2.0 | 3.0 | 5.0 |
| 17-artifact-cleanup-script | powershell | fable5-high | 2.0 | 3.0 | 5.0 |

## Model rankings by judge

*Agreement on model ordering tells us the panel agrees on which configurations produce better output on this axis. Absolute-score differences between judges are expected (different grading scales) and are not a bias concern.*

### Tests Quality

| Model | haiku45 rank (mean, n) | gemini31pro rank (mean, n) |
|---|---|---|
| fable5 | 1 (3.46, n=56) | 1 (4.64, n=56) |

*No pair-wise reversals — both judges agree on every model-vs-model ordering.*

### Workflow Craft

| Model | haiku45 rank (mean, n) | gemini31pro rank (mean, n) |
|---|---|---|
| fable5 | 1 (3.18, n=56) | 1 (4.89, n=56) |

*No pair-wise reversals — both judges agree on every model-vs-model ordering.*

## Language rankings by judge

*Agreement on language ordering tells us the panel agrees on which configurations produce better output on this axis. Absolute-score differences between judges are expected (different grading scales) and are not a bias concern.*

### Tests Quality

| Language | haiku45 rank (mean, n) | gemini31pro rank (mean, n) |
|---|---|---|
| powershell | 1 (3.86, n=14) | 2 (5.00, n=14) |
| typescript-bun | 2 (3.71, n=14) | 3 (5.00, n=14) |
| bash | 3 (3.43, n=14) | 1 (5.00, n=14) |
| default | 4 (2.86, n=14) | 4 (3.57, n=14) |

*Spearman rank correlation between haiku45 and gemini31pro: **+0.40**. (+1.0 = judges agree perfectly on ordering; 0 = no correlation; -1.0 = reversed.)*

**Pair-wise reversals** (where the two judges disagree on which language is better):

| Pair | haiku45 prefers | gemini31pro prefers | Own-family signal? |
|---|---|---|---|
| bash vs powershell | powershell | bash | — |
| bash vs typescript-bun | typescript-bun | bash | — |

### Workflow Craft

| Language | haiku45 rank (mean, n) | gemini31pro rank (mean, n) |
|---|---|---|
| default | 1 (3.29, n=14) | 3 (4.79, n=14) |
| typescript-bun | 2 (3.29, n=14) | 4 (4.79, n=14) |
| bash | 3 (3.14, n=14) | 1 (5.00, n=14) |
| powershell | 4 (3.00, n=14) | 2 (5.00, n=14) |

*Spearman rank correlation between haiku45 and gemini31pro: **-0.60**. (+1.0 = judges agree perfectly on ordering; 0 = no correlation; -1.0 = reversed.)*

**Pair-wise reversals** (where the two judges disagree on which language is better):

| Pair | haiku45 prefers | gemini31pro prefers | Own-family signal? |
|---|---|---|---|
| bash vs default | default | bash | — |
| bash vs typescript-bun | typescript-bun | bash | — |
| default vs powershell | default | powershell | — |
| powershell vs typescript-bun | typescript-bun | powershell | — |

## Language×Model rankings by judge

*Agreement on language×model ordering tells us the panel agrees on which configurations produce better output on this axis. Absolute-score differences between judges are expected (different grading scales) and are not a bias concern.*

### Tests Quality

| Language / Model | haiku45 rank (mean, n) | gemini31pro rank (mean, n) |
|---|---|---|
| powershell / fable5 | 1 (3.86, n=14) | 2 (5.00, n=14) |
| typescript-bun / fable5 | 2 (3.71, n=14) | 3 (5.00, n=14) |
| bash / fable5 | 3 (3.43, n=14) | 1 (5.00, n=14) |
| default / fable5 | 4 (2.86, n=14) | 4 (3.57, n=14) |

*Spearman rank correlation between haiku45 and gemini31pro: **+0.40**. (+1.0 = judges agree perfectly on ordering; 0 = no correlation; -1.0 = reversed.)*

**Pair-wise reversals** (where the two judges disagree on which language×model is better):

| Pair | haiku45 prefers | gemini31pro prefers | Own-family signal? |
|---|---|---|---|
| bash / fable5 vs powershell / fable5 | powershell / fable5 | bash / fable5 | — |
| bash / fable5 vs typescript-bun / fable5 | typescript-bun / fable5 | bash / fable5 | — |

### Workflow Craft

| Language / Model | haiku45 rank (mean, n) | gemini31pro rank (mean, n) |
|---|---|---|
| default / fable5 | 1 (3.29, n=14) | 3 (4.79, n=14) |
| typescript-bun / fable5 | 2 (3.29, n=14) | 4 (4.79, n=14) |
| bash / fable5 | 3 (3.14, n=14) | 1 (5.00, n=14) |
| powershell / fable5 | 4 (3.00, n=14) | 2 (5.00, n=14) |

*Spearman rank correlation between haiku45 and gemini31pro: **-0.60**. (+1.0 = judges agree perfectly on ordering; 0 = no correlation; -1.0 = reversed.)*

**Pair-wise reversals** (where the two judges disagree on which language×model is better):

| Pair | haiku45 prefers | gemini31pro prefers | Own-family signal? |
|---|---|---|---|
| bash / fable5 vs default / fable5 | default / fable5 | bash / fable5 | — |
| bash / fable5 vs typescript-bun / fable5 | typescript-bun / fable5 | bash / fable5 | — |
| default / fable5 vs powershell / fable5 | default / fable5 | powershell / fable5 | — |
| powershell / fable5 vs typescript-bun / fable5 | typescript-bun / fable5 | powershell / fable5 | — |

## Per-run self-judgment rows (reference)

*Rows where a judge evaluated output from its own model family. These individual runs are kept as a sanity check — the actual bias test is the pair-wise ranking reversals in the table above. Filtered to rows whose inter-judge delta differs from the baseline delta by ≥1.0 point; such rows are plausibly interesting but don't by themselves indicate bias (absolute-score differences between judges are expected).*

### Tests Quality

*Baseline delta (gemini31pro − haiku45) across the whole dataset: **+1.18**.*

*(no self-judgment rows exceed the 1.0-point deviation threshold — judges agree about in-family output roughly as much as about out-of-family output)*

### Workflow Craft

*Baseline delta (gemini31pro − haiku45) across the whole dataset: **+1.71**.*

*(no self-judgment rows exceed the 1.0-point deviation threshold — judges agree about in-family output roughly as much as about out-of-family output)*

