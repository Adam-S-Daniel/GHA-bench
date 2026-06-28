# Judge Consistency Data

*Raw panel-of-judges data plus a rankings-focused Quality Analysis. Backs the merged Conclusions and Judge Consistency Summary in the corresponding [`results.md`](results.md).*

## Notes

- **Generated:** 2026-06-28 07:44:49 PM ET
- **Source:** `/home/passp/repos/GHA-bench/.claude/worktrees/opus48-bench/results/2026-04-09_152435`
- **Judges present:** haiku45, gemini31pro, sonnet-legacy
- **Score conventions:** Scores shown are the `overall` dimension from each judge (1-5). Δ column is the second judge minus the first; positive = second judge is more generous.

## Quality Analysis

The strongest signal is that Sonnet outranks Opus on both Tests Quality and Workflow Craft — both judges place Sonnet #1 in every aggregation (ρ = +1.00, zero model-axis reversals). On Workflow Craft, the single language×model cell both judges crown #1 is bash + Sonnet, the only configuration where the panel unanimously agrees on top placement.

- **Top performer**: bash/sonnet holds rank #1 by both judges on Workflow Craft (haiku 3.17, gemini 5.00), the only cell where the panel agrees on first place across the eight-cell grid.
- **Sonnet over Opus**: Sonnet beats Opus by 0.41 points (haiku) and 0.22 points (gemini) on Tests Quality, and by 0.42 / 0.22 on Workflow Craft, with no model-pair reversals on either axis.
- **Best by language**: Workflow Craft agreement places bash/sonnet and default/sonnet at ranks 1-2 for both judges (ρ = +0.57 across the full grid); powershell/opus and bash/opus land in haiku's bottom two.
- **Where rankings diverge**: Language ordering on Tests Quality is fully reversed between judges (ρ = -1.00) — gemini ranks bash first while haiku ranks it last — so language alone is an unreliable signal without conditioning on the model.
- **Workflow Craft ceiling**: Workflow Craft averages run below Tests Quality on haiku's scale (2.00 vs 2.68) but slightly above on gemini's (4.54 vs 4.37), and gemini's only perfect 5.00 average is bash/sonnet.

*Provenance:* `claude-opus-4-7[1m]` at effort `xhigh` via Claude CLI (from cache); 5 in / 4788 out tokens, $0.3134. Prompt: [`QUALITY_ANALYSIS_SYSTEM_PROMPT`](../../judge_consistency_report.py).

## Campaign summary

### Tests Quality

| Scope | n | haiku45 ovr | gemini31pro ovr | sonnet-legacy ovr |
|---|---|---|---|---|
| all | 62 | 2.68 | 4.37 | 3.42 |

### Workflow Craft

| Scope | n | haiku45 ovr | gemini31pro ovr | sonnet-legacy ovr |
|---|---|---|---|---|
| all | 13 | 2.00 | 4.54 | 3.00 |

## By task

### Tests Quality

| Task | n | haiku45 ovr | gemini31pro ovr | sonnet-legacy ovr |
|---|---|---|---|---|
| 11-semantic-version-bumper | 8 | 2.38 | 4.38 | 3.12 |
| 12-pr-label-assigner | 8 | 2.75 | 4.00 | 4.00 |
| 13-dependency-license-checker | 8 | 3.00 | 4.25 | 3.62 |
| 14-docker-image-tag-generator | 7 | 2.43 | 4.71 | 3.57 |
| 15-test-results-aggregator | 8 | 2.88 | 4.75 | 3.00 |
| 16-environment-matrix-generator | 7 | 2.57 | 4.71 | 3.29 |
| 17-artifact-cleanup-script | 8 | 2.75 | 3.25 | 3.62 |
| 18-secret-rotation-validator | 8 | 2.62 | 5.00 | 3.12 |

### Workflow Craft

| Task | n | haiku45 ovr | gemini31pro ovr | sonnet-legacy ovr |
|---|---|---|---|---|
| 11-semantic-version-bumper | 6 | 2.17 | 4.67 | 2.83 |
| 12-pr-label-assigner | 7 | 1.86 | 4.43 | 3.14 |

## By language mode

### Tests Quality

| Mode | n | haiku45 ovr | gemini31pro ovr | sonnet-legacy ovr |
|---|---|---|---|---|
| bash | 15 | 2.47 | 4.60 | 3.53 |
| default | 15 | 2.80 | 4.27 | 3.47 |
| powershell | 16 | 2.62 | 4.38 | 3.31 |
| typescript-bun | 16 | 2.81 | 4.25 | 3.38 |

### Workflow Craft

| Mode | n | haiku45 ovr | gemini31pro ovr | sonnet-legacy ovr |
|---|---|---|---|---|
| bash | 3 | 2.33 | 4.33 | 3.00 |
| default | 3 | 1.67 | 4.00 | 2.67 |
| powershell | 4 | 2.25 | 5.00 | 3.25 |
| typescript-bun | 3 | 1.67 | 4.67 | 3.00 |

## By model + effort

### Tests Quality

| Model-Effort | n | haiku45 ovr | gemini31pro ovr | sonnet-legacy ovr |
|---|---|---|---|---|
| opus | 30 | 2.47 | 4.23 | 3.07 |
| sonnet | 32 | 2.88 | 4.50 | 3.75 |

### Workflow Craft

| Model-Effort | n | haiku45 ovr | gemini31pro ovr | sonnet-legacy ovr |
|---|---|---|---|---|
| opus | 7 | 1.86 | 4.43 | 2.86 |
| sonnet | 6 | 2.17 | 4.67 | 3.17 |

## Disagreement hotspots (panel span ≥ 2 on overall)

### Tests Quality

| Task | Mode | Model | Span | haiku45 ovr | gemini31pro ovr | sonnet-legacy ovr |
|---|---|---|---|---|---|---|
| 11-semantic-version-bumper | bash | opus | 3.0 | 2.0 | 5.0 | 4.0 |
| 11-semantic-version-bumper | bash | sonnet | 3.0 | 2.0 | 5.0 | 4.0 |
| 11-semantic-version-bumper | default | opus | 3.0 | 3.0 | 5.0 | 2.0 |
| 11-semantic-version-bumper | powershell | opus | 3.0 | 1.0 | 4.0 | 2.0 |
| 12-pr-label-assigner | default | sonnet | 3.0 | 2.0 | 5.0 | 4.0 |
| 14-docker-image-tag-generator | default | sonnet | 3.0 | 2.0 | 5.0 | 4.0 |
| 14-docker-image-tag-generator | powershell | opus | 3.0 | 2.0 | 5.0 | 3.0 |
| 14-docker-image-tag-generator | typescript-bun | opus | 3.0 | 2.0 | 5.0 | 2.0 |
| 15-test-results-aggregator | default | opus | 3.0 | 2.0 | 5.0 | 2.0 |
| 15-test-results-aggregator | powershell | opus | 3.0 | 2.0 | 5.0 | 2.0 |
| 15-test-results-aggregator | powershell | sonnet | 3.0 | 4.0 | 5.0 | 2.0 |
| 15-test-results-aggregator | typescript-bun | opus | 3.0 | 2.0 | 5.0 | 3.0 |
| 16-environment-matrix-generato | default | sonnet | 3.0 | 2.0 | 5.0 | 4.0 |
| 16-environment-matrix-generato | typescript-bun | opus | 3.0 | 2.0 | 5.0 | 2.0 |
| 17-artifact-cleanup-script | bash | opus | 3.0 | 2.0 | 5.0 | 3.0 |
| 18-secret-rotation-validator | bash | opus | 3.0 | 2.0 | 5.0 | 3.0 |
| 18-secret-rotation-validator | bash | sonnet | 3.0 | 2.0 | 5.0 | 3.0 |
| 18-secret-rotation-validator | powershell | opus | 3.0 | 2.0 | 5.0 | 3.0 |
| 11-semantic-version-bumper | default | sonnet | 2.0 | 3.0 | 2.0 | 4.0 |
| 11-semantic-version-bumper | powershell | sonnet | 2.0 | 3.0 | 5.0 | 4.0 |
| 11-semantic-version-bumper | typescript-bun | opus | 2.0 | 2.0 | 4.0 | 2.0 |
| 11-semantic-version-bumper | typescript-bun | sonnet | 2.0 | 3.0 | 5.0 | 3.0 |
| 12-pr-label-assigner | bash | opus | 2.0 | 1.0 | 3.0 | 2.0 |
| 12-pr-label-assigner | bash | sonnet | 2.0 | 3.0 | 5.0 | 5.0 |
| 12-pr-label-assigner | powershell | opus | 2.0 | 2.0 | 2.0 | 4.0 |

### Workflow Craft

| Task | Mode | Model | Span | haiku45 ovr | gemini31pro ovr | sonnet-legacy ovr |
|---|---|---|---|---|---|---|
| 11-semantic-version-bumper | bash | opus | 3.0 | 2.0 | 5.0 | 3.0 |
| 11-semantic-version-bumper | powershell | opus | 3.0 | 2.0 | 5.0 | 3.0 |
| 11-semantic-version-bumper | typescript-bun | sonnet | 3.0 | 2.0 | 5.0 | 3.0 |
| 12-pr-label-assigner | default | opus | 3.0 | 1.0 | 4.0 | 3.0 |
| 12-pr-label-assigner | powershell | opus | 3.0 | 2.0 | 5.0 | 3.0 |
| 12-pr-label-assigner | powershell | sonnet | 3.0 | 2.0 | 5.0 | 4.0 |
| 12-pr-label-assigner | typescript-bun | opus | 3.0 | 2.0 | 5.0 | 3.0 |
| 12-pr-label-assigner | typescript-bun | sonnet | 3.0 | 1.0 | 4.0 | 3.0 |
| 11-semantic-version-bumper | default | opus | 2.0 | 2.0 | 4.0 | 2.0 |
| 11-semantic-version-bumper | default | sonnet | 2.0 | 2.0 | 4.0 | 3.0 |
| 11-semantic-version-bumper | powershell | sonnet | 2.0 | 3.0 | 5.0 | 3.0 |
| 12-pr-label-assigner | bash | sonnet | 2.0 | 3.0 | 5.0 | 3.0 |

## Model rankings by judge

*Agreement on model ordering tells us the panel agrees on which configurations produce better output on this axis. Absolute-score differences between judges are expected (different grading scales) and are not a bias concern.*

### Tests Quality

| Model | haiku45 rank (mean, n) | gemini31pro rank (mean, n) | sonnet-legacy rank (mean, n) |
|---|---|---|---|
| sonnet | 1 (2.88, n=32) | 1 (4.50, n=32) | 1 (3.75, n=32) |
| opus | 2 (2.47, n=30) | 2 (4.28, n=32) | 2 (3.03, n=32) |

*Spearman rank correlation between haiku45 and gemini31pro: **+1.00**. (+1.0 = judges agree perfectly on ordering; 0 = no correlation; -1.0 = reversed.)*

*No pair-wise reversals — both judges agree on every model-vs-model ordering.*

### Workflow Craft

| Model | haiku45 rank (mean, n) | gemini31pro rank (mean, n) | sonnet-legacy rank (mean, n) |
|---|---|---|---|
| sonnet | 1 (2.63, n=27) | 1 (4.75, n=32) | 1 (3.12, n=8) |
| opus | 2 (2.21, n=29) | 2 (4.53, n=32) | 2 (2.75, n=8) |

*Spearman rank correlation between haiku45 and gemini31pro: **+1.00**. (+1.0 = judges agree perfectly on ordering; 0 = no correlation; -1.0 = reversed.)*

*No pair-wise reversals — both judges agree on every model-vs-model ordering.*

## Language rankings by judge

*Agreement on language ordering tells us the panel agrees on which configurations produce better output on this axis. Absolute-score differences between judges are expected (different grading scales) and are not a bias concern.*

### Tests Quality

| Language | haiku45 rank (mean, n) | gemini31pro rank (mean, n) | sonnet-legacy rank (mean, n) |
|---|---|---|---|
| typescript-bun | 1 (2.81, n=16) | 4 (4.25, n=16) | 3 (3.38, n=16) |
| default | 2 (2.80, n=15) | 3 (4.31, n=16) | 2 (3.44, n=16) |
| powershell | 3 (2.62, n=16) | 2 (4.38, n=16) | 4 (3.31, n=16) |
| bash | 4 (2.47, n=15) | 1 (4.62, n=16) | 1 (3.44, n=16) |

*Spearman rank correlation between haiku45 and gemini31pro: **-1.00**. (+1.0 = judges agree perfectly on ordering; 0 = no correlation; -1.0 = reversed.)*

**Pair-wise reversals** (where the two judges disagree on which language is better):

| Pair | haiku45 prefers | gemini31pro prefers | Own-family signal? |
|---|---|---|---|
| bash vs default | default | bash | — |
| bash vs powershell | powershell | bash | — |
| bash vs typescript-bun | typescript-bun | bash | — |
| default vs powershell | default | powershell | — |
| default vs typescript-bun | typescript-bun | default | — |
| powershell vs typescript-bun | typescript-bun | powershell | — |

### Workflow Craft

| Language | haiku45 rank (mean, n) | gemini31pro rank (mean, n) | sonnet-legacy rank (mean, n) |
|---|---|---|---|
| default | 1 (2.69, n=13) | 3 (4.62, n=16) | 3 (2.75, n=4) |
| bash | 2 (2.54, n=13) | 2 (4.62, n=16) | 2 (3.00, n=4) |
| powershell | 3 (2.27, n=15) | 4 (4.56, n=16) | 1 (3.25, n=4) |
| typescript-bun | 4 (2.20, n=15) | 1 (4.75, n=16) | 4 (2.75, n=4) |

*Spearman rank correlation between haiku45 and gemini31pro: **-0.40**. (+1.0 = judges agree perfectly on ordering; 0 = no correlation; -1.0 = reversed.)*

**Pair-wise reversals** (where the two judges disagree on which language is better):

| Pair | haiku45 prefers | gemini31pro prefers | Own-family signal? |
|---|---|---|---|
| bash vs default | default | bash | — |
| bash vs typescript-bun | bash | typescript-bun | — |
| default vs typescript-bun | default | typescript-bun | — |
| powershell vs typescript-bun | powershell | typescript-bun | — |

## Language×Model rankings by judge

*Agreement on language×model ordering tells us the panel agrees on which configurations produce better output on this axis. Absolute-score differences between judges are expected (different grading scales) and are not a bias concern.*

### Tests Quality

| Language / Model | haiku45 rank (mean, n) | gemini31pro rank (mean, n) | sonnet-legacy rank (mean, n) |
|---|---|---|---|
| powershell / sonnet | 1 (3.00, n=8) | 2 (4.62, n=8) | 4 (3.50, n=8) |
| typescript-bun / sonnet | 2 (3.00, n=8) | 7 (4.25, n=8) | 2 (3.88, n=8) |
| default / opus | 3 (2.86, n=7) | 5 (4.25, n=8) | 5 (3.12, n=8) |
| bash / sonnet | 4 (2.75, n=8) | 1 (4.75, n=8) | 1 (3.88, n=8) |
| default / sonnet | 5 (2.75, n=8) | 4 (4.38, n=8) | 3 (3.75, n=8) |
| typescript-bun / opus | 6 (2.62, n=8) | 6 (4.25, n=8) | 8 (2.88, n=8) |
| powershell / opus | 7 (2.25, n=8) | 8 (4.12, n=8) | 6 (3.12, n=8) |
| bash / opus | 8 (2.14, n=7) | 3 (4.50, n=8) | 7 (3.00, n=8) |

*Spearman rank correlation between haiku45 and gemini31pro: **+0.21**. (+1.0 = judges agree perfectly on ordering; 0 = no correlation; -1.0 = reversed.)*

**Pair-wise reversals** (where the two judges disagree on which language×model is better):

| Pair | haiku45 prefers | gemini31pro prefers | Own-family signal? |
|---|---|---|---|
| bash / opus vs default / opus | default / opus | bash / opus | — |
| bash / opus vs default / sonnet | default / sonnet | bash / opus | — |
| bash / opus vs powershell / opus | powershell / opus | bash / opus | — |
| bash / opus vs typescript-bun / opus | typescript-bun / opus | bash / opus | — |
| bash / opus vs typescript-bun / sonnet | typescript-bun / sonnet | bash / opus | — |
| bash / sonnet vs default / opus | default / opus | bash / sonnet | — |
| bash / sonnet vs powershell / sonnet | powershell / sonnet | bash / sonnet | — |
| bash / sonnet vs typescript-bun / sonnet | typescript-bun / sonnet | bash / sonnet | — |
| default / opus vs default / sonnet | default / opus | default / sonnet | — |
| default / opus vs typescript-bun / sonnet | typescript-bun / sonnet | default / opus | — |
| default / sonnet vs typescript-bun / sonnet | typescript-bun / sonnet | default / sonnet | — |
| typescript-bun / opus vs typescript-bun / sonnet | typescript-bun / sonnet | typescript-bun / opus | — |

### Workflow Craft

| Language / Model | haiku45 rank (mean, n) | gemini31pro rank (mean, n) | sonnet-legacy rank (mean, n) |
|---|---|---|---|
| bash / sonnet | 1 (3.17, n=6) | 1 (5.00, n=8) | 3 (3.00, n=2) |
| default / sonnet | 2 (3.00, n=5) | 2 (4.75, n=8) | 4 (3.00, n=2) |
| default / opus | 3 (2.50, n=8) | 6 (4.50, n=8) | 7 (2.50, n=2) |
| powershell / sonnet | 4 (2.50, n=8) | 7 (4.50, n=8) | 1 (3.50, n=2) |
| typescript-bun / opus | 5 (2.29, n=7) | 3 (4.75, n=8) | 8 (2.50, n=2) |
| typescript-bun / sonnet | 6 (2.12, n=8) | 4 (4.75, n=8) | 6 (3.00, n=2) |
| bash / opus | 7 (2.00, n=7) | 8 (4.25, n=8) | 2 (3.00, n=2) |
| powershell / opus | 8 (2.00, n=7) | 5 (4.62, n=8) | 5 (3.00, n=2) |

*Spearman rank correlation between haiku45 and gemini31pro: **+0.57**. (+1.0 = judges agree perfectly on ordering; 0 = no correlation; -1.0 = reversed.)*

**Pair-wise reversals** (where the two judges disagree on which language×model is better):

| Pair | haiku45 prefers | gemini31pro prefers | Own-family signal? |
|---|---|---|---|
| bash / opus vs powershell / opus | bash / opus | powershell / opus | — |
| default / opus vs powershell / opus | default / opus | powershell / opus | — |
| default / opus vs typescript-bun / opus | default / opus | typescript-bun / opus | — |
| default / opus vs typescript-bun / sonnet | default / opus | typescript-bun / sonnet | — |
| powershell / opus vs powershell / sonnet | powershell / sonnet | powershell / opus | — |
| powershell / sonnet vs typescript-bun / opus | powershell / sonnet | typescript-bun / opus | — |
| powershell / sonnet vs typescript-bun / sonnet | powershell / sonnet | typescript-bun / sonnet | — |

## Per-run self-judgment rows (reference)

*Rows where a judge evaluated output from its own model family. These individual runs are kept as a sanity check — the actual bias test is the pair-wise ranking reversals in the table above. Filtered to rows whose inter-judge delta differs from the baseline delta by ≥1.0 point; such rows are plausibly interesting but don't by themselves indicate bias (absolute-score differences between judges are expected).*

### Tests Quality

*(no self-judgment rows exceed the 1.0-point deviation threshold — judges agree about in-family output roughly as much as about out-of-family output)*

### Workflow Craft

*(no self-judgment rows exceed the 1.0-point deviation threshold — judges agree about in-family output roughly as much as about out-of-family output)*

