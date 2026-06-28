# Why Opus 4.8 trips ~2× the traps of Opus 4.7 — verdict

_Investigation date: 2026-06-28. Scope: GHA-bench trap detection, Opus 4.7 (1m)
vs Opus 4.8 (1m). This synthesis is anchored on a hand-review of **all 201** of
Opus 4.8's trap occurrences (per-occurrence forensic verdicts), the deterministic
parity/normalization analysis, 10 matched-pair transcript comparisons, and the
CC-version confounder analysis._

## Bottom line

The "~2× the traps" headline is **real as a count but almost entirely benign as a
phenomenon, and partly a measurement/harness artifact.** It does **not** mean
Opus 4.8 gets stuck twice as often. Three results carry the verdict:

1. **Traps are not distress.** Across all 201 of 4.8's trap occurrences, **199
   (99.0%) show no circling**, **173 (86.1%) are legitimate engineering behavior
   that merely tripped a count-based detector**, **27 (13.4%) are outright
   detector false positives**, and only **~1–1.5%** (3 timeouts + 2 partial
   loops) resemble genuine "going in circles." Whatever drives the 2×, it is not
   the model spinning.

2. **The gap lives in two volume/style-sensitive detectors.** `repeated-test-reruns`
   (119 vs 31) and `fixture-rework` (43 vs 23) account for **~90% of the
   occurrence gap**; the style-insensitive `ts-type-error-fix-cycles` is at
   near-parity (24 vs 21). The dominant category, `repeated-test-reruns`, is
   heavily inflated by a concrete measurement artifact (below).

3. **The behavioral excess is effort-modulated.** Normalized per turn **and** per
   test, 4.8 genuinely trips more at medium/high effort (a real but benign
   finer-iteration propensity); at xhigh it is roughly proportional — and per
   test actually *lower* than 4.7 (4.03 vs 4.76 traps/100 tests).

**Verdict: it is a mix, ~99% benign.** Ranked by contribution to the gap:
(a) detector measurement artifacts that scale with 4.8's command *style*;
(b) genuine-but-benign higher/finer iteration (more tests, finer red-green
cycles, more fixtures, more decomposed solutions); (c) a plausible-but-unverified
CC-version persistence-prompt nudge; (d) genuine distress, ~1%. **Yes, the
report/blog framing needs a caveat — exact wording in the final section.**

## Method

- **Forensic anchor (primary).** Every one of Opus 4.8's 201 trap occurrences was
  reviewed and labelled on three axes — `circling` (was the agent actually going
  in circles?), `interpretation` (legit behavior tripped the detector vs detector
  false positive), and `resolution` (resolved / ran-to-completion-with-issue /
  timeout). The aggregate and a 45-occurrence verdict sample are reproduced below.
- **Deterministic parity check (Part 2A).** Confirmed which benchmark inputs were
  held constant across the two runs.
- **Deterministic normalization (Part 2B).** Trap counts normalized per cell, per
  100 tests, per turn, and as a share of wall-clock, by effort.
- **Matched-pair transcript reads (10).** Same task / language / effort, 4.8 vs
  4.7, reading both console logs and re-running the detector to attribute the
  per-cell delta to a concrete cause.
- **Detector semantics.** Verified directly in `generate_results.py::_detect_traps`
  (lines 111–252). Load-bearing lines: `ts-type-error-fix-cycles = hook_errors_caught × 12s`
  (L198, counts hook events, not bugs); `fixture-rework` matches the literal word
  "fixture" in any bash command, threshold ≥4 (L215–218); `repeated-test-reruns`
  dedups test commands via `re.sub(pipes)…[:80]` then fires at ≥4 (L224–228).

Counts: 4.8 = **201 occurrences over 140 cells** (4 efforts × 5 languages × 7
tasks, including the 4.8-only `ultracode` effort); 4.7 = **81 occurrences over 105
cells** (3 efforts, no ultracode). Per cell that is **1.44 vs 0.77 = 1.86×**;
restricting to the three matched efforts it is **149 vs 81 = 1.84×**. "~2×" refers
to these per-cell ratios.

## Part 2A — Parity check (deterministic): what was held constant

The benchmark substrate is **identical** across the two runs, so the comparison is
not contaminated by task/instruction/detector drift:

- **Identical:** `Dockerfile.act`, `hooks/syntax-check.py`,
  `benchmark-instructions-v4.md` (both runs are 100% v4 instructions, including
  the explicit anti-trap "Common Pitfalls" tips — *"Test reruns: fix the code not
  the test command," "design fixtures up front," "avoid act push >3×"*),
  `_detect_traps` (applied uniformly), permissions (`bypassPermissions`, no Auto
  mode), both.
- **Changed but inert to agent behavior:** `runner.py` — only
  observation/recording/resume/concurrency-guard logic; it does **not** alter the
  agent prompt, effort, permissions, or tools.
- **Not captured (residual unknown):** pwsh/dotnet runtime versions in either run.
- **Changed and behaviorally live:** the Claude Code version (see CC-version
  verdict). This is the one non-model, non-volume difference that can move agent
  behavior.

Implication: with detectors, instructions (including anti-trap guidance), hooks,
and permissions all held constant, the 2× gap is attributable to **(model
behavior + iteration volume + CC-version prompt) interacting with fixed
detectors** — not to a changed measuring stick.

## Forensic aggregate (n = 201 of 201 per-occurrence verdicts)

| Axis | Outcome | Count | Share |
|------|---------|------:|------:|
| **circling** | no | 199 | **99.0%** |
| | partial | 2 | 1.0% |
| | yes | 0 | 0.0% |
| **interpretation** | legit-behavior-tripped-detector | 173 | **86.1%** |
| | detector-false-positive | 27 | 13.4% |
| | mixed | 1 | 0.5% |
| **resolution** | ran-to-completion-with-issue | 124 | 61.7% |
| | resolved-then-moved-on | 73 | 36.3% |
| | eventually-resolved | 1 | 0.5% |
| | timeout | 3 | **1.5%** |

Read: a "trap" in this dataset is, **86% of the time, the agent doing legitimate
engineering** (red-green TDD reruns, building fixtures up front, fixing a real
type error) that a count-thresholded heuristic flagged; **13% of the time it is
an outright false positive**; and **~1% of the time** it looks like real
distress. `ran-to-completion-with-issue` is the modal resolution because most
flagged spans are productive iteration the agent simply continued through, not
loops it had to escape.

### Gap decomposition by trap category (deterministic counts)

| Category | 4.8 | 4.7 | Δ | Share of gap | Nature |
|----------|----:|----:|--:|-------------:|--------|
| repeated-test-reruns | 119 | 31 | **+88** | **73.3%** | finer red-green TDD + cd-prefix dedup artifact |
| fixture-rework | 43 | 23 | +20 | 16.7% | more/granular fixtures + keyword reference-counting |
| ts-type-error-fix-cycles | 24 | 21 | +3 | 2.5% | near-parity; driven by a broken tsc hook for both |
| all other | 15 | 6 | +9 | 7.5% | small infra-spiral categories |
| **total** | **201** | **81** | **+120** | 100% | |

Ninety percent of the gap is the two volume/style-sensitive detectors.

## Key per-occurrence findings

From the 45-occurrence verdict sample, with the detector mechanics that explain
each pattern:

- **`repeated-test-reruns` is overwhelmingly red-green-refactor TDD, not
  repetition.** Sample after sample shows monotonically *increasing* pass counts
  between "identical" runs — e.g. Pester `1 → 10 → 15 → 22 → 26 → 30`, bun test
  `0 → 7 → 18 → 33 → 54`, pytest growing scope each call. The detector's own
  premise — "same test run N times *without the underlying code changing*" — is
  **false** in these cases: the code changed every cycle. The command string
  repeats; the program under test does not.
- **The 80-character dedup is silently defeated by 4.8's command style.** 4.8
  prefixes nearly every Bash command with a long absolute `cd
  /home/passp/.../workspaces/2026-06-26_103905/<task>/<cell>` path. The detector
  key is `re.sub(strip-pipes)[:80]`, and the truncation lands *inside* that path,
  so 6–12 genuinely different test commands collapse to **one** key and read as
  "same test run 12×." 4.7 emitted essentially no cd-prefixes, so its commands
  kept distinct keys and stayed under the ≥4 threshold. This is a pure
  measurement artifact and it sits on top of the dominant (73%-of-gap) category.
- **`ts-type-error-fix-cycles` is mostly a broken hook.** The PostToolUse tsc
  hook is mis-invoked (runs `tsc <file>` with a tsconfig present → spurious
  `TS5112`), so `hook_errors_caught` effectively counts **`.ts` write/edit
  operations, not real type errors**. In one matched cell all 24 of 4.8's
  "errors" decoded to the identical spurious TS5112. The few genuine tsc cycles in
  the sample (e.g. `@types/bun` not in tsconfig `types`; env index-narrowing
  TS2345) were each diagnosed once, fixed once, confirmed once — no cycling.
- **`fixture-rework` mostly counts deliberate up-front fixture design and
  fixture-path *references*, not breakage.** The sample repeatedly shows 3–7
  fixtures written once, verified with exact expected counts, and never touched
  again — exactly the "design fixtures up front" behavior the v4 instructions
  *recommend*. The detector counts any bash command containing the word
  "fixture," so referencing `fixtures/case2.json` on a CLI invocation, or even a
  grep whose pattern contains "fixture," is counted as "rework."
- **The 27 false positives have crisp causes:** detector substring matches on the
  agent's *own* validator error text (`config file not found: nope.json` from
  deliberately testing the error path), Docker image *probes* (2 read-only
  `docker run` version checks) miscounted as "exploring pwsh install," and the
  TS5112 hook noise above.
- **Genuine distress is the rare residue.** Of 201, only 3 timed out and 2 showed
  partial circling. The closest things to real loops in the whole sample are
  isolated, well-handled episodes that arose *because 4.8 built more surface*
  (e.g. a Pester `It -ForEach` discovery-scope bug from choosing a data-driven
  test pattern; an `actionlint`/`Bun.spawnSync`-throws episode from adding a
  structural workflow test) — consequences of ambition, not capability
  regression, and each ended resolved.

## Part 2B — Effort-dependent normalization (deterministic)

This is the load-bearing quantitative result. Normalizing the trap counts four
ways, by effort:

| Metric (4.8 vs 4.7) | medium | high | xhigh |
|---|---|---|---|
| traps / cell | 1.14 vs 0.51 (**2.24×**) | 1.37 vs 0.54 (**2.54×**) | 1.74 vs 1.26 (1.38×) |
| traps / 100 tests | 3.92 vs 2.88 (1.36×) | 3.70 vs 2.08 (1.78×) | 4.03 vs 4.76 (**0.85×**) |
| traps / turn | 0.031 vs 0.017 (1.82×) | 0.031 vs 0.012 (2.58×) | 0.034 vs 0.023 (1.48×) |
| trap-time % of wall* | 21.1 vs 8.0 | 22.2 vs 8.6 | 17.5 vs 13.4 |

\* Detector *heuristic* time estimates (e.g. 12s/hook-error, 20s/extra-rerun).
Matched-pair reads show these **badly overstate** actual wasted wall-time: in one
xhigh bash pair the estimated trap time dwarfs the cell's *entire* 21.6s of
command-execution time. Treat the % row as an upper bound, not measured idle time.

**Read:**
- **Medium/high: a genuine behavioral component.** 4.8 trips more *per turn* and
  *per test* — i.e. the excess survives normalizing for "did more work." There is
  a real propensity to iterate more granularly (more, finer red-green cycles).
- **xhigh: proportional, even sub-proportional.** Per test, 4.8 trips **fewer**
  traps than 4.7 (4.03 vs 4.76). At xhigh the extra raw traps are just the tax of
  writing more tests; 4.7's *own* trap density also climbs to meet 4.8's.
- **Caveat on the "genuine" component:** because the cd-prefix artifact inflates
  the raw numerator that feeds even the per-turn/per-test ratios, part of the
  medium/high "genuine per-turn excess" is itself the measurement artifact. The
  matched pairs confirm a *real* finer-TDD signal underneath (the true `bats`
  rerun count in several cells is ~7, which would clear the ≥4 threshold even
  after fixing the dedup), so the behavioral component is real but **smaller than
  the raw 2.5× implies.**

## Matched-pair findings (10 cells, 4.8 vs 4.7)

Every pair tells the same story with local variations. None is a capability
regression; all attribute the delta to volume/style/artifact:

- **same_root_cause across the 10 pairs: 3 "yes," 7 "partial"** — i.e. the broad
  mechanism (*4.8 does more, more granularly → trips count/keyword/dedup-threshold
  detectors*) is shared, while the proximate inflator varies by cell.
- **The cd-prefix dedup collapse is the single most common inflator.** Across the
  4.8 bash runs, **149/709 bash commands are cd-prefixed vs 0/428 for 4.7.** In
  multiple pairs, 7–12 distinct test commands collapse to one key purely from this
  prefix. Counterfactual stated explicitly in one pair: had 4.7 cd-prefixed, its 5
  bats commands would also have collapsed to one key (≥4) and *it* would have
  tripped the trap — direct evidence the delta is substantially harness/style
  driven.
- **fixture-rework is a keyword/threshold artifact in the bash/powershell cells.**
  4.8 builds named `fixtures/`/`test/fixtures/` trees and drives the script with
  explicit fixture paths (so "fixture" appears in many commands); 4.7 hides
  fixture staging inside a `.ps1`/`.sh` harness or uses the Write tool (which the
  detector never scans), so the word never surfaces → 0 matches.
- **ts-type-error-fix-cycles is the broken-hook artifact at parity.** Where it
  fired (typescript-bun), it is the spurious TS5112 hook counting `.ts` edits for
  *both* models; 4.8 trips it slightly more only because it writes more `.ts`
  files (more decomposed solution). One pair confirmed 4.8 actually had *cleaner*
  TypeScript than 4.7.
- **The real, equal obstacle both models hit and both fixed one-shot:** `act`'s
  default `--pull=true` force-pulling the local-only `act-ubuntu-pwsh:latest`
  image → registry auth failure → fixed by `--pull=false`/`.actrc`. It tripped
  *neither* model's trap threshold; not a differentiator.
- **One pair is environmentally confounded** (task-18 bash medium): a concurrent
  sibling agent injected a rival "srv18b" canonical solution into 4.8's workspace
  mid-run and a shared Docker daemon under load threw `RWLayer nil`/stale-volume
  errors — neither present in the isolated 2026-05-06 4.7 baseline. That cell's
  delta overstates model behavior; recommend treating it as confounded.
- **Where 4.8 did more, it shipped more.** In the matched cells 4.8 routinely
  delivered 3–6× the tests, more fixtures, and more decomposed modules, at
  equal-or-better correctness (e.g. 65/65 vs 13/13; 5 modules + JSON+markdown
  formatters vs 1 module), while frequently **pre-empting** the one real
  environment trap 4.7 stumbled on (dry-running act, pre-checking container
  tooling, pre-emptive `--pull=false`).

## CC-version confounder verdict

**Likely contributes — PARTIAL. A genuine confounder, not a clean A/B.**

- 4.7 baseline ran Claude Code **2.1.131/132**; 4.8 ran **2.1.195**. The 2.1.195
  system prompt added a NEW general autonomous-operation / persistence cluster
  **absent** from the baseline: `autonomous-operation-guidelines` (@2.1.169 —
  *"retry after errors… do not stop until the task is complete or blocked on user
  input"*), `task-approval-continuity` (@2.1.173), `act-when-ready` (@2.1.173).
  These map directly onto the retry/rerun/keep-reworking shape of the dominant
  detectors, and these runs use `claude -p` headless — exactly the autonomous mode
  the fragments target — so activation is **plausible**.
- **Why partial, not yes:** (1) the effective system prompt is *not captured* in
  the transcripts, so activation is **inferred, not verified**; (2) the same
  release added counter-pressure fragments (`doing-tasks-no-unnecessary-additions`,
  `exploratory-questions-analyze-before-implementing`) pushing the other way; (3)
  magnitude is unquantifiable from the docs. Secondary: changelog 2.1.161 (a
  failed Bash command in a parallel batch no longer cancels its siblings) can
  lengthen rerun loops.
- **Net:** because this is a harness-level prompt change applied to *any* model on
  2.1.195, an unknown fraction of the medium/high per-turn excess could be
  **prompt-driven, not model-driven.** It is the most likely explanation for the
  portion of the behavioral excess that survives volume-normalization yet is not a
  pure measurement artifact.

## Verdict: weighing the hypotheses

Two levels. **What a trap is** (hard, from n=201) and **why 4.8 logs ~2× more**
(estimative, because the artifact and genuine-iteration components are entangled
inside `repeated-test-reruns`).

**What a 4.8 trap is (measured):** 86% legitimate behavior tripping a detector,
13% detector false positive, ~1% genuine distress. ⇒ **~99% benign.**

**Why ~2× more events (estimated contribution to the 1.84× gap):**

| Hypothesis | Contribution | Confidence | Basis |
|---|---|---|---|
| Detector measurement artifacts scaling with 4.8's command *style* (cd-prefix defeating the `[:80]` dedup; fixture keyword reference-counting; broken TS5112 hook) | **~35–45%** | Medium-high | Dominates the 73%-of-gap `repeated-test-reruns` category; verified in detector source + multiple matched pairs |
| Genuine-but-benign higher/finer iteration (more tests, finer red-green cycles, more fixtures, more decomposed solutions) — pure proportionality at xhigh, real per-turn/per-test excess at medium/high | **~35–45%** | Medium-high | Part 2B normalization + per-occurrence TDD evidence |
| CC-version persistence-prompt nudge (confounder) | **~10–20%** | Low-medium | Plausible, activation inferred not verified |
| Genuine distress / going in circles | **~1–2%** | High | n=201: 0 full + 2 partial circling, 3 timeouts |

**It is a mix, dominated by benign causes.** Genuine distress is effectively ruled
out as a driver. The 2× is, in roughly equal parts, a measurement/style artifact
sitting on the dominant detector and a real-but-benign tendency to iterate more
and more granularly, with a plausible CC-version prompt nudge on top. The only
*behavioral* signal that is both real and model-attributable is the medium/high
per-turn excess (a finer-TDD propensity) — and even that is partly inflated by the
cd-prefix artifact and fades to proportional (sub-proportional per test) at xhigh.

## Does the "traps more" framing need a caveat? — YES, with exact wording

Use this verbatim wherever the "~2×" figure appears:

> **Caveat on "Opus 4.8 trips ~2× the traps of Opus 4.7."** A "trap" is a
> detector heuristic firing, not a confirmed failure. We hand-reviewed all 201 of
> Opus 4.8's trap occurrences: **99% showed no looping, 86% were legitimate
> engineering** (red-green TDD reruns, designing fixtures up front, fixing real
> type errors) that merely tripped a count-based detector, **13% were outright
> detector false positives, and only ~1%** (3 timeouts, 2 partial loops)
> resembled genuine distress. The ~2× figure therefore measures **how much more,
> and more granularly, Opus 4.8 iterates — not how often it gets stuck.** Three
> further qualifications: (1) the dominant trap, `repeated-test-reruns` (~73% of
> the gap), is heavily inflated by a measurement artifact — Opus 4.8 prefixes
> nearly every shell command with a long absolute `cd` path, which collapses
> distinct test commands into one key under the detector's 80-character dedup —
> and the TypeScript type-error trap is driven by a misconfigured hook that counts
> file edits, not real errors. (2) The two runs used **different Claude Code
> versions** (4.7 on 2.1.131/132, 4.8 on 2.1.195, whose system prompt added an
> autonomous-persistence cluster that encourages exactly this retry/rerun
> behavior), so part of the gap is harness- not model-driven. (3) Normalized per
> turn, the excess is genuine at medium/high effort but converges to roughly
> proportional — and *per test slightly lower* — at xhigh. Read "~2× the traps" as
> **"iterates ~2× more granularly," not "fails ~2× as often."** A clean
> model-only attribution would require re-running 4.7 and 4.8 on the same Claude
> Code version.

Short inline version (if space-constrained):

> "~2× the traps" counts detector heuristics, not failures: a review of all 201
> Opus 4.8 occurrences found 99% no looping, 86% legitimate iteration, ~1%
> distress. The gap is dominated by a command-style measurement artifact (long
> `cd`-prefixes defeating the rerun-dedup) plus more granular TDD, on different
> Claude Code versions (2.1.131/132 vs 2.1.195). Read it as "iterates more," not
> "fails more."

## Limitations

- The "why ~2×" weighting bands are estimates: the artifact and genuine-iteration
  components are entangled inside `repeated-test-reruns` and cannot be cleanly
  separated without re-running the detector with a fixed dedup key.
- The 4.8 run is an incremental checkpoint; some xhigh PowerShell/powershell-tool
  variants timed out (30-min cap) and are absent, so xhigh turn/test denominators
  are slightly undercounted (making the xhigh per-turn ratio an upper bound).
- One matched cell (task-18 bash medium) is environmentally confounded by a
  concurrent sibling agent and shared-Docker contention.
- CC-version fragment activation is inferred from the version-doc manifest, not
  verified against captured system prompts; pwsh/dotnet runtime versions were not
  captured in either run.
- **Recommended fixes** (independent of the model question): strip leading
  `cd …;`/`cd … &&` before the `[:80]` dedup key; require an actual `act`-step
  failure (not the validator's own error text) for `act-fixture-paths`; count
  fixture *rework* (edits to an existing fixture) rather than fixture-path
  references; and fix the tsc hook's TS5112 false positive. Then re-run 4.7 and
  4.8 on a single Claude Code version before publishing a clean model-attributed
  ratio.
