# Judge-harness calibration: agy (Gemini 3.1 Pro High) vs the retired gemini-cli

**Date:** 2026-06-26
**Why:** Google retired the Gemini CLI for individuals/subscription use
([source](https://developers.googleblog.com/an-important-update-transitioning-gemini-cli-to-antigravity-cli/):
*"On June 18, 2026, Gemini CLI and Gemini Code Assist IDE extensions will stop
serving requests for Google AI Pro and Ultra, as well as those using it free of
charge using Gemini Code Assist for individuals."*). The panel's `gemini31pro`
seat moved from the `gemini-cli` provider (`gemini-3.1-pro-preview`) to the
`agy` provider (Antigravity CLI, `Gemini 3.1 Pro (High)`). Same underlying model
(Gemini 3.1 Pro), different harness + explicit High effort tier. This note
quantifies how closely the new judge reproduces the old one, so cross-report
quality comparisons (opus-4.8 run, agy-judged, vs prior runs, gemini-cli-judged
and cached) can be read correctly.

## Method

Re-judged a stratified sample of **9 cells from the prior report**
(`results/2026-05-06_173435/`) with the new agy judge and compared to each
cell's cached `test-quality-gemini31pro.json` (old gemini-cli) score. The sample
spans the full score range and several languages/models:

| task | language | model | old (cov/rig/des/ovr) |
|---|---|---|---|
| 11-semantic-version-bumper | bash | opus | 5/5/5/5 |
| 11-semantic-version-bumper | default | opus47-1m | 5/5/5/5 |
| 11-semantic-version-bumper | powershell | opus | 5/5/5/5 |
| 11-semantic-version-bumper | bash | opus47-1m | 4/4/2/3 |
| 11-semantic-version-bumper | default | opus | 4/4/5/4 |
| 11-semantic-version-bumper | powershell | opus47-1m | 4/2/5/3 |
| 11-semantic-version-bumper | bash | haiku45 | 2/2/2/1 |
| 12-pr-label-assigner | default | haiku45 | 2/2/3/2 |
| 11-semantic-version-bumper | powershell | haiku45 | 2/2/3/2 |

Read-only: comparison used `test_quality.evaluate_with_llm()` directly (no cache
writes), so the prior report's cached scores are untouched.

## Result (n = 9)

| dimension | MAE | bias (new−old) | exact | within-1 | Pearson r | mean shift |
|---|---|---|---|---|---|---|
| coverage | 0.22 | −0.22 | 78% | 100% | 0.98 | 3.67 → 3.44 |
| rigor    | 0.44 | −0.22 | 56% | 100% | 0.88 | 3.44 → 3.22 |
| design   | 0.78 | −0.33 | 44% | 78%  | 0.63 | 3.89 → 3.56 |
| overall  | 0.56 | −0.33 | 44% | 100% | 0.90 | 3.33 → 3.00 |

## Interpretation

- **Tracks closely on the primary ranking metric.** `overall` correlates r=0.90
  with the old judge and **every sampled cell is within 1 point**; `coverage` is
  near-identical (r=0.98). Rankings are preserved.
- **Small, consistent downward bias (~0.3 pts).** agy/Gemini 3.1 Pro (High)
  scores marginally stricter on every dimension (overall mean 3.33 → 3.00). It is
  systematic, not random.
- **`design` is the noisiest dimension** (r=0.63, one cell off by 2) — expected,
  as test organization/readability is the most subjective axis.

## Implication for the cross-report comparison

The opus-4.8 run is agy-judged; the prior runs remain gemini-cli-judged (cached).
The ~0.3 downward bias gives opus-4.8 a slight handicap on the Gemini dimension
relative to the older cells. Two things bound the impact:

1. The panel is **two judges**, and the **Haiku 4.5 judge (claude-cli) is
   unchanged** and directly comparable across reports — so the bias is roughly
   halved in the panel mean.
2. High correlation means **tiers/rankings are preserved**; the effect is a small
   uniform level shift, not reordering.

Treat absolute opus-4.8-vs-prior **Gemini-dimension** deltas of ≤ ~0.3 as within
judge-harness noise. Sample is small (n=9); rerun with a larger N to tighten the
bias estimate if a finer cross-report quality claim is needed.
