# How noisy is a benchmark cell? Six replicates of the same 8 cells, on two Claude Code versions

**Date:** 2026-07-28
**Author:** analysis session (Claude Code on the web, PR #44)
**Dataset pin:** commit `029ed681` on `claude/web-version-haiku-test-lrs38s`
**Nature:** six new 8-cell benchmark runs executed in a Claude Code on the web sandbox, compared
against the matched laptop cells in `results/2026-05-06_173435`. No existing results were modified.

---

## Verdict (TL;DR)

**A single benchmark cell, re-run under conditions that are identical in every way this harness
controls, has a 1σ of about ±25% on duration and ±30–40% on cost.** Individual cells swing much
further: `16/powershell` came back at 280s, 284s, 356s, 400s, 564s and 649s across six runs of the
same configuration — a 2.3× spread with nothing changed between them.

That noise floor is **larger than every environment and version effect this campaign set out to
measure**, and it retroactively invalidates the per-cell comparisons made earlier in this PR:

| contrast | duration | cost |
|---|---|---|
| **CC 2.1.220 vs 2.1.132** (cloud both, version isolated) | 1.072× [0.947, 1.212] | **1.244× [1.080, 1.434]** |
| **cloud vs laptop** (version ~fixed, environment isolated) | 1.004× [0.709, 1.422] | 0.937× [0.723, 1.214] |
| cloud 2.1.220 vs laptop (both differ) | 1.076× [0.745, 1.553] | 1.166× [0.956, 1.422] |

Geometric mean over the 8 paired cells, 95% CI, 3 replicates per cloud arm.

**The cloud sandbox is indistinguishable from the laptop on both duration and cost** — the
environment contrast lands at 1.004× with a CI that spans 0.71–1.42×. The earlier claim in this PR
that the sandbox is "not obviously slower" survives, but it was never in danger and never
informative: at n=1 that CI would have been far wider still.

**One contrast is real: CC 2.1.220 costs ~24% more than 2.1.132 for identical work**, and it has a
measured mechanism rather than being the one lucky draw out of six — see
[Why the cost difference is credible](#why-the-cost-difference-is-credible).

**Operationally:** with 8 paired cells, this design can detect a 1.20× effect with 2 replicates per
arm and a 1.10× effect with 5, but a 1.05× effect needs ~19. **Any single-replicate comparison in the
existing corpus — including every cross-run comparison in the README's results tables — cannot
resolve anything below roughly 1.5×.**

---

## The design

Six runs of the same 8 cells (haiku-4.5 × tasks `11-semantic-version-bumper` and
`16-environment-matrix-generator` × `bash`, `default`, `powershell`, `typescript-bun`), all inside one
Claude Code on the web sandbox:

| arm | Claude Code | replicates |
|---|---|---|
| **A** | 2.1.220 (the sandbox's own CLI) | `2026-07-28_114218`, `2026-07-28_170407`, `2026-07-28_195532` |
| **B** | 2.1.132 (pinned, `/opt/cc-2.1.132`) | `2026-07-28_142445`, `2026-07-28_180536`, `2026-07-28_205523` |

Arm B pins the CLI the laptop baseline ran on, so that **B vs laptop isolates the environment** and
**A vs B isolates the version**. The arms were interleaved (B A B A B) rather than blocked, so drift
over the 7.5-hour window — disk pressure, a noisy neighbour — hits both arms instead of aliasing onto
the arm. `DISABLE_AUTOUPDATER=1` held the pin; the CLI was still 2.1.132 at the end.

48/48 cloud cells succeeded, with an `act-result.txt` in all 48. 5.79 hours of agent time, ~$26.

The laptop comparison uses the matched cells from `results/2026-05-06_173435`. Restricting to these
four language modes matters: **the laptop corpus also contains `powershell-tool` cells the cloud
campaign never ran**, and a naive join on task+model would silently mismatch them.

## The noise floor

Pooled within-arm 1σ on a single cell, as a multiplicative factor:

| | duration | cost |
|---|---|---|
| arm A (2.1.220) | **1.24×** | 1.30× |
| arm B (2.1.132) | **1.25×** | 1.42× |

So ~95% of single cells land within 0.65–1.55× of that cell's own mean on duration. The per-cell
duration table shows what that looks like in practice (seconds):

| cell | A r1 | A r2 | A r3 | B r1 | B r2 | B r3 | laptop |
|---|---|---|---|---|---|---|---|
| 11/bash | 352 | 362 | 362 | 492 | 449 | 315 | 712 |
| 11/default | 468 | 469 | 404 | 442 | 368 | 447 | 448 |
| 11/powershell | 542 | 323 | 520 | 406 | 376 | 496 | 587 |
| 11/typescript-bun | 401 | 585 | 483 | 398 | 309 | 381 | 508 |
| 16/bash | 614 | 463 | 464 | 460 | 553 | 596 | 458 |
| 16/default | 394 | 531 | 508 | 311 | 379 | 405 | 303 |
| 16/powershell | 400 | 564 | 280 | 356 | 649 | 284 | 189 |
| 16/typescript-bun | 340 | 377 | 562 | 310 | 531 | 365 | 311 |

**Aggregates are far steadier than cells.** Per-replicate totals for the whole 8-cell set:

* arm A: 58.5, 61.2, 59.7 min (1.05× spread) — $4.5, $5.3, $4.9
* arm B: 52.9, 60.2, 54.8 min (1.14× spread) — $4.0, $4.0, $4.0
* laptop: 58.6 min — $4.3

Averaging 8 cells pulls a ±25% per-cell σ down to a few percent on the total. This is why run-level
totals in the corpus are trustworthy and per-cell numbers are not. (Arm B's three cost totals landing
on $4.0 three times is a coincidence at n=3, not evidence of extra stability — its *per-cell* cost
noise is the highest of the two arms at 1.42×.)

## Contrast 1 — Claude Code version, environment fixed

Duration **1.072× [0.947, 1.212]**: no detectable difference. Cost **1.244× [1.080, 1.434]**: 2.1.220
is more expensive.

### Why the cost difference is credible

It is one of six contrasts examined, and on its own significance it is marginal — t ≈ 3.6 against the
≈3.9 a Bonferroni correction over six tests would demand. What makes it credible is that it comes
with an independently measured mechanism, and one that explains why *cost* moved while *duration*
did not. Per-cell means, arm A vs arm B:

| | arm A (2.1.220) | arm B (2.1.132) | A/B |
|---|---|---|---|
| turns | 55.3 | 55.2 | 1.014× |
| output tokens | 28,782 | 28,013 | 1.028× |
| cache read tokens | 3,168,125 | 2,821,280 | **1.133×** |
| cache creation tokens | 75,703 | 65,309 | 1.159× |
| total context consumed | 3,244,138 | 2,887,032 | **1.134×** |
| tools offered | 30 | 27 | |

**The agent does the same amount of work and re-reads ~13% more context per turn to do it.** Same
turn count, same output volume, more context carried. Cache reads are the largest single line in the
bill, so a context difference shows up as a cost difference without touching wall-clock. The tool
surface differs in the same direction (30 vs 27, with `Glob`/`Grep`/`TodoWrite` behind `ToolSearch`
on 2.1.220), but 88 patch versions separate these builds and the context growth is not attributable
to the tool list alone.

The cost ratio (1.22×) exceeds the context ratio (1.13×), so context size does not account for all of
it; treat the mechanism as corroborating the direction, not as a complete explanation.

## Contrast 2 — environment, version near-fixed

Duration **1.004× [0.709, 1.422]**, cost **0.937× [0.723, 1.214]**. The cloud sandbox and the laptop
are indistinguishable on both.

The CI is much wider here than for the version contrast, and that is structural, not fixable by
running more cloud replicates: **the laptop side is n=1 per cell**, so this comparison inherits the
full single-cell noise no matter how much the cloud side is replicated. Narrowing it requires
re-running the laptop cells.

One caveat on "version near-fixed": the laptop's task-11 cells ran on 2.1.131 and its task-16 cells
on 2.1.132, while arm B is 2.1.132 throughout.

## What this means for the existing corpus

1. **Per-cell cross-run comparisons are not interpretable.** The earlier read in this PR — that
   `16/powershell` was "189s on the laptop vs ~400s in the cloud" and `11/bash` "712s vs 352s" —
   is noise. Both cells reproduce that entire range within a single arm.
2. **Run-level totals are sound.** An 8-cell total has a few percent of spread, so comparisons of
   whole-run aggregates hold up.
3. **Grade and quality deltas between single runs need the same scepticism** as timing deltas. This
   campaign measured duration and cost only; there is no reason to assume the judge-facing outputs
   are quieter, and the prior `powershell-vs-powershell-tool` analysis reached the same conclusion
   from a different direction.
4. **Budget replication by the effect you care about** (8 paired cells, 95% CI):

   | effect to detect | replicates per arm |
   |---|---|
   | 1.50× | 1 |
   | 1.20× | 2 |
   | 1.10× | 5 |
   | 1.05× | ~19 |

## Caveats

* One model (haiku-4.5), two tasks, four language modes. Noise may differ for slower models or
  other task categories; haiku's short cells may be proportionally noisier than opus cells.
* Duration and cost only. Nothing here measures grade, quality, or correctness variance.
* The cloud arms share one sandbox and one 7.5-hour window. Interleaving protects the A/B contrast
  from drift, but both arms would move together under a sustained platform-wide slowdown.
* The 95% CIs are paired-t over 8 cells, using per-cell means across replicates. With 8 cells the t
  critical value is 2.365, so these intervals are not tight.
* One container restart interrupted the campaign mid-replicate; it was resumed via
  `runner.py --resume` and no cell was run twice or partially counted.

## Reproduction

```bash
./run-web-variability-2026-07-28.sh              # the campaign (restart-safe, resumable)
python3 results/analysis/analyze_variability_2026-07-28.py   # every number in this document
```

The analysis script discovers replicates from the `.campaign` marker each run directory carries,
plus the unmarked arm A replicate 1 (`results/2026-07-28_114218`, which predates the campaign).
