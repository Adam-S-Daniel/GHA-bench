# tsc hook invocation — validity & comparability evaluation (issue #21)

**Date:** 2026-06-29
**Branch / worktree:** `issue-21-tsc-eval` (off `origin/main` @ `c359411b`, after the opus-4.8 finalization merged — sequencing precondition satisfied)
**Dataset under evaluation:** `results/2026-06-26_103905` (opus-4.8, 7 tasks × 5 languages × 4 efforts = 140 cells; 28 per language)
**Scope:** read-only/analytical. **No code changed.** Deliverable is a recommendation for sign-off, per the issue.

---

## TL;DR / Recommendation

The tsc hook bug is real and slightly worse than the issue framed it — but a **second, previously-unrecorded hook bug masks its behavioral impact**, which makes the validity verdict *cleaner*, not messier:

1. **The tsc invocation never type-checks** (confirmed by reproduction). All **367** TypeScript hook "catches" in this run are config artifacts; **zero** are genuine type defects in agent code.
2. **The hook never delivered *any* nudge to the model — in *any* language** (confirmed empirically across all 280 cells *and* against Claude Code's documented hook schema). The hook emits a **top-level** `additionalContext`, but PostToolUse requires `hookSpecificOutput.additionalContext`, so Claude Code logged the output as telemetry and **never injected it into the model's context**.

**Consequence for the four lenses:**

- **Validity of existing results:** The headline ts-bun cell metrics (duration, cost, quality grades) are **valid and unconfounded** — the hook was inert, so each ts-bun cell is behaviorally equivalent to "no TS hook at all." The damage is confined to three *secondary* artifacts: the **Hook-Savings stat**, the **`ts-type-error-fix-cycles` trap**, and the trap-derived **`avg_dur_net`** column.
- **Comparability if changed:** A comparability break only materializes if a future fix makes the hook *actually deliver and type-check* — and that requires fixing **both** bugs together. Fixing the invocation alone leaves the hook inert (still comparable, still useless); fixing the schema alone would deliver pure TS5112 noise (actively harmful). 
- **Cross-language comparability now:** The Hook-Savings *cross-language* comparison is already unsound for three independent reasons (false TS catches, undelivered catches in every language, missing linters per #22). The *headline* cross-language comparison is **not** distorted — an inert hook applied equally to all languages.

**Recommended action — (d) + (b), explicitly NOT (c), NOT pure (a):**

- **(d) Salvage the stat now (owned by #25):** the correct TS catch count for this dataset is **0**. Zero out ts-bun hook savings, drop the fictional `ts-type-error-fix-cycles` trap, and recompute `avg_dur_net`. No re-run needed — stored `hook_events` make this fully retroactive. Given finding #2, #25 should also weigh whether the Hook-Savings section is meaningful *at all* for this dataset (the hook delivered nothing in any language) versus carrying a prominent caveat.
- **(b) Fix going forward — both bugs together — and document the discontinuity:** correct the tsc invocation *and* the output schema in `hooks/syntax-check.py` so future runs get a delivering, project-faithful type-check. Flag that future TS runs are **not behaviorally comparable** to this dataset's (inert-hook) TS cells.
- **NOT (c) (re-run affected cells):** unjustified. The cells are already valid; there is no prior "comparable" condition to restore, because the existing TS data was collected with an inert hook. Re-running 28 cells (real allowance + wall time) to repair a secondary stat — when a retroactive filter already repairs it — is not worth it.
- **NOT pure (a) (leave + caveat):** the ts-bun "saves 49–70% of test time" headline is not merely imperfect, it is **100% artifact**. Caveating a fabricated number is worse than zeroing it.

**Sign-off gate:** This session stops here. The hook-code change (invocation + schema) and the stat recompute (#25's job) should not be made until you sign off on this recommendation.

---

## Evidence

### Finding 1 — the tsc invocation never type-checks (confirmed)

The hook runs `bunx tsc --noEmit <file_path>` for `.ts`/`.tsx` (`hooks/syntax-check.py:104-117`). Passing a file explicitly makes modern `tsc` refuse to load the project `tsconfig.json` and abort with a hard error. Exact message from stored hook stdout:

> `error TS5112: tsconfig.json is present but will not be loaded if files are specified on commandline. Use '--ignoreConfig' to skip this error.`

**Error-code census across all 28 ts-bun cells' stored hook stdout** (one nudge = one "caught" event; stdout truncated to 500 chars at storage):

| TS code | caught-events containing it | meaning | nature |
|---|---|---|---|
| **TS5112** | **345** | tsconfig not loaded (hard abort) | pure config noise — zero type info |
| TS1343 | 13 | `import.meta` needs `--module es2020+` | default-module fallout (no tsconfig) |
| TS1503 | 5 | named capture groups need `target ES2018+` | default-target fallout (no tsconfig) |
| TS2307 | 3 | cannot find module `'../src/x'` | default-resolution fallout (no tsconfig) |
| **genuine type defect in agent code** | **0** | — | — |

The 22 non-TS5112 events occur in cells where the agent wrote a source file **before** writing `tsconfig.json`, so `tsc` ran with default options (target ES5 / module commonjs) and produced target/module/resolution complaints. Those are **also** config artifacts, not defects — the code is correct under bun and under the agent's own `ESNext`/`bundler` tsconfig.

**Live reproduction** (copied `11-semantic-version-bumper/typescript-bun-opus48-1m-high/generated-code` to scratch, pinned `typescript`):
- `tsc --noEmit src/bumper.ts` with the project `tsconfig.json` present → the hard config refusal (run-env `tsc ≥5.8` emits TS5112; older `tsc ≤5.7` silently ignores tsconfig and floods with `bun-types`↔`lib.dom` conflicts, TS2717/TS2430). **Neither path yields a clean, project-faithful check.**
- The project-aware form `tsc --noEmit -p tsconfig.json` only works if `bun-types`/`@types/bun` are physically resolvable to standalone `tsc`; otherwise it trips `TS2688`. So a *correct* invocation is non-trivial (needs the project tsconfig **and** bun's types available to a non-bun `tsc`).

**Verdict:** 367/367 ts-bun catches are misconfiguration artifacts. The one language meant to get a deep semantic check got none.

### Finding 2 — the hook never reached the model, in any language (new; confirmed two ways)

The hook prints `{"additionalContext": "..."}` at the **top level** (`hooks/syntax-check.py:152-159`). This output format has existed since the hook was created (v3, commit `d5173223`).

- **Empirical:** the nudge string `"SYNTAX/TYPE ERRORS detected"` appears in **397 system/telemetry events and 0 model-input (user-turn) events** across all 280 cells; **0** assistant turns reference it. Stored agent reasoning (`thinking` blocks) is redacted to empty, so this was checked against assistant `text` + `tool_use` and the full user-turn stream.
- **Documented:** Claude Code's PostToolUse hook honors `additionalContext` **only** under `hookSpecificOutput.additionalContext`. A top-level `additionalContext` is silently ignored for PostToolUse (it is the schema for UserPromptSubmit/SessionStart). Confirmed against the official hooks reference for v2.1.193–2.1.195 (the run's CLI versions); no schema change in that range.

So every hook "catch" — TypeScript false positives *and* the 24 bash shellcheck catches *and* everything else — was recorded as telemetry but **never shown to the agent**.

**Two implications, pulling in opposite directions:**
- It **strengthens validity:** the spurious nudges could not have confounded agent behavior, because the agent never saw them. We essentially got lucky — bug #2 (no delivery) masked bug #1 (false content). Had the schema been correct, ~13 TS5112 spam messages per ts-bun cell *would* have confounded those cells badly.
- It **widens the stat invalidity:** the Hook-Savings premise ("each caught error avoids a test run the agent would otherwise have needed") is unsupported for *every* language in this dataset, since no catch ever influenced the agent.

**Corroboration that cells were unaffected:** 17/28 ts-bun cells ran their **own** type-check via Bash (`tsc`/`typecheck`/`tsconfig`), and **0** of those agent-initiated runs surfaced TS5112 — agents used proper project-aware invocations and got real type information independently of the hook. (This also reconciles the memo's "1/26 reacted": any reaction came from an agent's own tool output, never from the hook.)

### Quantified harm

**Per-language hook catches (authoritative, from `metrics.json`, completed 28-cell dataset):**

| language | cells | fires | caught | caught/cell |
|---|---|---|---|---|
| bash | 28 | 500 | 24 | 0.86 |
| default (Python) | 28 | 592 | 1 | 0.04 |
| powershell | 28 | 598 | 0 | 0.00 |
| powershell-tool | 28 | 591 | 2 | 0.07 |
| **typescript-bun** | 28 | 770 | **367** | **13.11** |

ts-bun is **93.1%** of all catches (367/394) and **88.9%** of all credited gross "time saved" (48.9 of 55.0 min) — and **all of it is false** (false content, and never delivered).

**Three corrupted report artifacts (in `results/2026-06-26_103905/results.md`):**

1. **Hook Savings table** — ts-bun rows credit ≈ **49 min gross / 39 min net "saved"** and headline **`% of Test Time Saved` of 49.5%–69.7%** per effort. Entirely fictional. (Other languages: bash ≈ 4.8 min gross / 3.5–24.5%; default/powershell ≈ 0 or negative.)
2. **Trap Analysis — `ts-type-error-fix-cycles`** (`generate_results.py:194-198`, estimated as `hook_errors_caught × 12s`): **24 instances, ≈73 min, ≈$21** of fictional "fix-cycle" cost. Internally contradictory with #1 (the same false catches are booked as *both* time-saved *and* time-lost), and fictional either way.
3. **Comparison `avg_dur_net`** (`generate_results.py:925-929`): the fictional trap subtracts ≈4 min/cell from ts-bun's displayed net-of-traps duration, making ts-bun look faster than it was — a real cross-language duration distortion.

**Not affected:** `avg_dur`, cost, token, and quality-grade columns (the headline 4.8-vs-4.7 findings). The hook was inert; it cost only the checker's wall time (already captured in raw durations).

---

## The four lenses, answered

**1. Does the no-op TS hook invalidate anything?**
Not the headline results. ts-bun cells are valid and behaviorally equivalent to "no TS hook." The only invalid outputs are the Hook-Savings stat (93% of catches / 89% of gross savings), the `ts-type-error-fix-cycles` trap (~73 min / ~$21), and the ts-bun `avg_dur_net` (~4 min/cell). All three live in the secondary Savings/Trap sub-analysis, which AGENTS.md already notes is **not ported into the combined report** — so the canonical cross-run comparison never surfaced these numbers anyway.

**2. Is the comparability break (if fixed going forward) acceptable, and how flagged?**
The break is acceptable and is the normal cost of fixing a measurement instrument — but it only occurs on a **both-bugs** fix that makes the hook deliver real diagnostics. Fixing the invocation alone changes nothing observable (still undelivered). Flag the break in (i) AGENTS.md "Current state", (ii) the next results regeneration's hook-section caveat, and (iii) the v5+ instructions note (see Downstream). The existing TS dataset should be labeled "collected with an inert syntax-check hook."

**3. Does a TS-only no-op distort language comparisons now?**
For the Hook-Savings sub-analysis: yes, severely — but that comparison is independently unsound (undelivered catches in every language; missing pyflakes/PSScriptAnalyzer per #22 zeroing Python/PowerShell). For the headline metrics: no — an inert hook applied uniformly to all five languages cannot distort their relative duration/cost/quality.

**4. Options (a)–(d), weighed.**

| Option | Verdict | Why |
|---|---|---|
| (a) leave as-is + caveat | **Reject (alone)** | The ts-bun savings/trap numbers are 100% artifact; a caveat on a fabricated headline misleads. |
| (b) fix going forward + document break | **Adopt** | Restores a useful hook for future runs — *but only if invocation **and** schema are fixed together* (see below). Break is documentable and acceptable. |
| (c) fix + re-run affected cells | **Reject** | Cells are already valid; no prior comparable condition exists to restore; cost (allowance + wall time) unjustified for a secondary stat that a retroactive filter already repairs. |
| (d) salvage stat by filtering config artifacts | **Adopt (now; #25)** | Stored `hook_events` make it fully retroactive. Correct TS catch count = 0 → zeroes the stat, drops the trap, fixes `avg_dur_net`, no re-run. |

---

## Recommended fix specifics (for the sign-off decision — not yet implemented)

These belong to the fix sessions (hook code is fair to change; **never** touch agent code in `workspaces/` or `results/*/generated-code/`). Two bugs that must be fixed **together** — order matters:

1. **Invocation** (`hooks/syntax-check.py:104-117`): replace `bunx tsc --noEmit <file>` with a project-aware check that loads the agent's `tsconfig.json` and makes bun's types resolvable to standalone `tsc` (e.g. `tsc --noEmit -p tsconfig.json` after ensuring `bun-types`/`@types/bun` are installed, or `bunx tsgo`/`bun --bun tsc` if it honors the project). Validate it produces *zero* errors on known-clean generated code and catches a real injected `TS2322`/`TS2532`.
2. **Output schema** (`hooks/syntax-check.py:152-159`): nest the payload as
   `{"hookSpecificOutput": {"hookEventName": "PostToolUse", "additionalContext": "..."}}`
   so it is actually delivered. **This applies to all languages, not just TS.**

⚠️ **Interaction (critical):** fixing the **schema alone** would start delivering the existing TS5112 spam to agents — actively harmful. Fixing the **invocation alone** keeps the hook inert. Ship both or neither. If the schema is fixed for the other (working) language branches, the TS branch must be fixed in the same change.

**Stat salvage (#25):** filter config-artifact catches (TS5112 + TS1343/TS1503/TS2307 cascade) from stored `hook_events` stdout → TS catch count = 0 → recompute Hook Savings, drop `ts-type-error-fix-cycles`, recompute `avg_dur_net`. Add tests; follow the AGENTS.md "Before every PR" checklist; regenerate per-run `results.md`. Given finding #2, also decide whether the Hook-Savings section should render at all for inert-hook datasets or carry a header caveat.

---

## Scope, ownership, downstream

- **This issue (#21):** evaluation + recommendation only. Done. Awaiting sign-off.
- **#25 (stat rework, runs last/alone):** owns the salvage (option d) and the broader "hook delivered nothing" implication. Finding #2 means the missing-linter remediation (#22) and the act-crediting work should be re-scoped: there is no point installing pyflakes/PSScriptAnalyzer for "hook savings" until the hook actually *delivers* (schema fix), and the existing savings data is artifactual for **all** languages, not just TS.
- **#22 (missing linters):** intersects — a delivering hook is a precondition for any cross-language hook-savings parity to mean anything.
- **Downstream instructions (per the issue comment):** `benchmark-instructions-v4.md` (~L162-164) tells agents the tsc hook is "net-positive (53% catch rate)"; that premise is now doubly false (false catches + undelivered). The v4 instructions are a benchmark constant and must **not** be edited retroactively; revisit the tsc tip only for v5+.

---

## Reproduction appendix

```bash
# Census of catches + TS error-code distribution (run inside results/2026-06-26_103905/tasks)
#   per-mode caught from metrics.json hooks.hook_errors_caught
#   TS codes parsed from hook_events[].stdout via regex 'error (TS\d+)'
# Delivery check: search type=="user" events for "SYNTAX/TYPE ERRORS detected" -> 0/280 cells
# Live tsc repro: copy a ts-bun generated-code dir, `npm i typescript`,
#   run `tsc --noEmit src/<f>.ts` (config-refusal) vs `tsc --noEmit -p tsconfig.json`.
```

Raw figures cited above were produced by the scripts in this session's transcript; all counts are from the completed 28-cell-per-language `2026-06-26_103905` dataset.
