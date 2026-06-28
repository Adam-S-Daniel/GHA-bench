# Follow-up session prompts + hook-savings scoping (2026-06-28)

Captured during the opus-4.8 benchmark resume session (run dir `2026-06-26_103905`).
These are spin-off investigations that were deliberately kept OUT of the
finalization session to preserve focus. Nothing here has been actioned — this memo
is the handoff.

---

## 1. Hook time-saved stat — scoping findings (advisory, not yet fixed)

The "time saved by hooks" stat lives in `generate_results.py` ~L807–913
(`### Hook Savings by Language/Model/Effort`). Mechanism:

- **Net saved (seconds)** = `caught × TEST_RUN_COST_S[mode] − fires × write_overhead`.
  `TEST_RUN_COST_S = {default:8, powershell:35, powershell-tool:35, bash:12, ts-bun:8}`.
  `caught`/`fires` come from the hook events and are **language-agnostic** (the
  syntax-check hook runs PSScriptAnalyzer on `.ps1`, actionlint on workflow YAML, etc.).
- **"% of test time saved"** uses a denominator `test_time` from
  `_categorize_tool_time()` (`generate_results.py` ~L329), which at ~L359 filters to
  `tool_name == "Bash"`.

### Claim 1 — "only accounts for Bash, misses PowerShell": real as a code smell, but does NOT bite the current dataset

- Net-saved seconds are **not** bash-only — they use the per-mode constant
  (powershell/powershell-tool = 35, the highest valuation).
- The `tool_name == "Bash"` filter in `_categorize_tool_time` is the "bash-only"-looking
  part. But empirically it loses nothing here: **agents run `pwsh` through the Bash tool**,
  and the test patterns (`Invoke-Pester`, `pwsh …Tests.ps1`) match those Bash commands.
  Verified across all 26 `powershell-tool` cells in `2026-06-26_103905`: captured tool
  calls are `Bash:634, Write:283, Edit:209, Read, ToolSearch, Task*` — **no native
  PowerShell tool at all**, despite `CLAUDE_CODE_USE_POWERSHELL_TOOL=1`. Confirmed
  behavioral (not a capture gap) from the raw `cli-output.json` (e.g.
  `pwsh -NoProfile -Command "Invoke-Pester -Path tests/…Tests.ps1 -Output Minimal"`).
- **So:** the filter is a **latent robustness bug**. A complete fix may span TWO files —
  `runner.py` ~L733 stores an empty command string for any non-Bash tool (so the data
  isn't even captured), plus `_categorize_tool_time` to categorize it. The fix session
  should FIRST verify empirically whether any PowerShell time is actually dropped (it
  appears not to be), then decide how much robustness work is warranted.

### Claim 2 — ACT container time: structurally possible, not currently modeled

- **Can the hook save `act` time? Yes, but only a subset.** The hook catches
  *statically-detectable* errors at Write/Edit (actionlint on workflow YAML, syntax/type).
  Catching those pre-`act` averts a failed Docker container run the agent would otherwise
  have executed and redone. It **cannot** save `act` runs that fail for runtime/logic
  reasons (step ordering, missing secrets, wrong outputs).
- The current stat ignores this: every catch is flat-rated at one *test-run* cost (8–35s),
  so a catch that averts a minutes-long `act` run is badly under-credited. A dormant
  `act_ms` bucket exists in `_categorize_tool_time` (computed, unused) and
  `generated-code/act-result.txt` carries real step timings.
- This half is a **modeling decision**, not a localized bug — it needs a counterfactual
  ("would the agent have run `act` with this error?"). Requires user sign-off on the
  valuation philosophy.

### Can you tell whether a caught lint error was "cosmetic" to ACT?

Partially, by actionlint finding **category**, not perfectly:

- **act-blocking** (workflow won't parse/run → `act` fails): YAML syntax errors,
  workflow-schema violations (unknown keys, malformed structure), `${{ }}` expression
  errors, undefined `needs:`/job refs, bad `uses:` format.
- **act-cosmetic** (`act` runs the workflow anyway): embedded **shellcheck** (`SC####`) on
  `run:` bodies — `act` executes the script regardless of SC opinions.
- **pyflakes is NOT categorically cosmetic** (correction — it was wrongly lumped with
  shellcheck initially). pyflakes' own promise: *"it will never complain about style, and
  it will try very, very hard to never emit false positives"* — so its findings are real
  defects, and act-impact splits **by message type**:
  - `undefined name` → runtime `NameError` → if the Python `run:` step executes, **`act`
    fails**. **act-breaking** — credit as act-time-saved.
  - `unused import` / `unused variable` / redefinition / f-string-without-placeholders →
    script still runs → **act-cosmetic** in pass/fail terms (real smell, doesn't flip act).
  pyflakes therefore *strengthens* the hook→act-savings case, not weakens it.
- Path nuance: the hook's plain-`.py` branch uses `py_compile` (**syntax-only** — would NOT
  catch an undefined name, which is valid syntax). pyflakes findings reach the agent ONLY
  via **actionlint** on workflow YAML's embedded Python `run:` steps. So undefined-name
  catches that avert an act run come specifically through the actionlint path.
- The hook stores actionlint's raw output (rule names + messages), so classification is
  retroactive — split shellcheck/pyflakes findings by message, not by linter.
- **Caveat:** actionlint↔act is not 1:1 (`act` is more lenient than GitHub's validator in
  places). Category is a strong *prior*; the rigorous validation is to correlate each
  category/message against cells where `act` actually ran with that error class and see
  whether `act` failed.

### MAJOR FINDING — missing linters make hook coverage wildly uneven (2026-06-28)

Tested the hook end-to-end + checked run data. The hook NOMINALLY has per-extension
branches (py/sh/yml/cs/ts/fsx/ps1/psm1), but two required linters are MISSING on the host,
and inline-YAML coverage is partial:

| Language | Dedicated file | Inline in YAML |
|---|---|---|
| Python | py_compile = SYNTAX ONLY (undefined-name not caught) | actionlint→pyflakes, but **pyflakes MISSING** → not caught |
| Bash | bash -n + shellcheck (error/warning only; info dropped) | actionlint→shellcheck (syntax/errors yes; info no) |
| PowerShell | PSScriptAnalyzer — **MISSING → nothing** | actionlint has no pwsh support → nothing |
| TypeScript | bunx tsc --noEmit works (type errors are act-cosmetic via bun) | N/A (no native inline TS) |
| Workflow structure | — | actionlint expression/schema/syntax WORKS (act-blocking) |

Run-data corroboration (hook catches/cell, all completed 2026-06-26 cells):

| mode | cells | fires | caught | caught/cell |
|---|---|---|---|---|
| bash | 27 | 480 | 24 | 0.89 |
| default (Python) | 27 | 566 | 1 | 0.04 |
| powershell | 27 | 567 | 0 | **0.00** |
| powershell-tool | 27 | 570 | 2 | 0.07 |
| typescript-bun | 26 | 713 | 335 | **12.88** |

Implications:
1. The "time saved by hooks" stat is essentially a **TypeScript artifact** (gross_saved =
   caught × TEST_RUN_COST_S; TS dominates catches ~14-300×). PowerShell=0 and Python≈0 are
   LINTER AVAILABILITY, not hook design or model behavior.
2. Cross-language hook comparisons are currently **unfair**. Installing pyflakes +
   PSScriptAnalyzer would change the picture materially.

### MAJOR FINDING #2 — the TS catches are ~99% FALSE POSITIVES (tsc invocation bug)

The hook runs `bunx tsc --noEmit <file_path>`. Passing the file explicitly makes tsc
**ignore the project tsconfig.json** and abort with `error TS5112` (treated as fatal), so it
NEVER type-checks the actual code. Verified end-to-end on a real generated file: the hook's
command emits ONLY TS5112. Error-code distribution across stored hook stdout (ts-bun cells):
TS5112=313, TS1503=20 (named-capture-groups — downstream of the wrong default target once
tsconfig is ignored), TS1343=16 (import.meta — same cause), TS2307=3 (module resolution
without tsconfig). So the 335 TS "catches" are the hook's OWN misconfiguration, not defects
in agent code.

Consequences:
- The hook delivered **zero real type-checking value for TS** despite 713 fires — the one
  language that was supposed to get a deep semantic check.
- The TS hook-savings figure is **invalid** (credits time saved for catching ~335 non-errors).
- Behavioral confounder check: only **1 of 26** ts-bun cells had the agent's own text mention
  TS5112/ignoreConfig — agents almost universally ignored the spurious nudge and proceeded
  (code runs fine under bun). So the false positives polluted the STAT but did NOT
  meaningfully confound ts-bun cell behavior/cost/traps. Dataset validity for ts-bun cells
  is OK; only the hook-savings stat is corrupted.
- The project-aware form `tsc --noEmit -p tsconfig.json` trips a DIFFERENT artifact
  (`TS2688: cannot find type definition file for 'bun'`), so a correct fix must also supply
  bun's types (bun provides them at runtime; standalone tsc needs bun-types + proper tsconfig
  `types`/`typeRoots`).
- SALVAGE: hook_events stdout is stored, so the fix session can retroactively FILTER the
  config-artifact catches (TS5112 + its target/module cascade) out of existing data and
  recompute hook-savings WITHOUT re-running cells.

Conceptual note (user, 2026-06-28): a GENUINE tsc type error is NOT act-cosmetic — it can
cause runtime misbehavior (ReferenceError from cannot-find-name, TypeError from
null/undefined access, wrong values from shape mismatch) that fails an act run exercising
that path. So once the tsc invocation is fixed, TS catches become genuinely act-relevant and
should be credited by the same per-error-code spectrum as pyflakes (cannot-find-name etc. =
act-breaking; TS6133 unused = cosmetic). It's only moot for the CURRENT data because the hook
never ran a valid type-check.

These were almost certainly missing during the whole run (the run is ongoing; powershell
cells already show 0/27). Environmental constants — verify with `command -v pyflakes` and
`pwsh -c "Get-Module -ListAvailable PSScriptAnalyzer"`.

### Decisions already made by the user (2026-06-28)

- **Count YAML/actionlint lint catches as act-time-saved** (as proposed).
- **Count dedicated code-file catches as act-saving too** when the workflow directly/
  indirectly executes the file AND the error is act-runtime-relevant (not cosmetic; note TS
  tsc errors are act-cosmetic via bun). Indirect use (script A sources B) needs tracing.
- Open: how to discount/exclude cosmetic-to-act lints (see above) — for the fix session.

### Added scope for the fix session (from the missing-linter finding)

- (a) Install pyflakes + PSScriptAnalyzer on the host for cross-language parity in FUTURE
  runs; (b) apply the act-cosmetic discount (hits TS hardest); (c) caveat the EXISTING
  hook-savings data as linter-availability-dependent and TS-dominated. This is bigger than
  the stat's math — it's about whether the hook-savings comparison is even fair across
  languages.

### Recommendation

Both fixes belong in **one fresh, focused session** (same savings-analysis neighborhood),
run AFTER the opus-4.8 finalization (STEP 6) merges, since they change report numbers
broadly. Hook-savings is a secondary section that does NOT affect the headline
4.8-vs-4.7 findings, so the canonical report can carry a known-imperfect hook sub-section
in the interim and be cheaply regenerated later. Note (AGENTS.md "Combined-report
parity"): hook/trap Savings Analysis is NOT currently ported to the combined report, so
the fix's reach into the combined report is a separate decision.

---

## 2. Fresh-session prompts

### Prompt 1 — PowerShell vs powershell-tool behavioral comparison

```
GHA-bench (WSL bash box, repo at /home/passp/repos/GHA-bench). Orient first: read
AGENTS.md and skim runner.py + generate_results.py. Work in your own git worktree
branched from origin/main (after the opus-4.8 canonical dataset has merged). This is
read-only with respect to benchmark data; you may write an analysis doc under
results/analysis/.

Goal: a comprehensive comparison and contrast of how `powershell` vs `powershell-tool`
agents actually functioned, across every applicable cell in ALL run directories that
feed the current combined report (discover which dirs those are, and which of them
actually contain a powershell-tool condition — older runs may not). Cover every
dimension you find informative: which tools the agent actually invokes, whether the
native PowerShell tool is ever used, how pwsh is reached (e.g. via the Bash tool),
outcomes/quality/timing/cost/traps, error patterns, and whether the two conditions are
meaningfully distinct in practice or effectively the same.

Why this matters: we run in WSL, and Claude Code's powershell-tool docs emphasize
Windows — so the powershell-tool mode may not behave as a distinct condition here, which
would affect how the report/blog should frame that column.

Pointers (not a method): powershell-tool sets CLAUDE_CODE_USE_POWERSHELL_TOOL=1
(runner.py ~L993-1001); the two modes' prompt definitions are ~L265+. Per-cell raw
transcripts are cli-output.json, console-log.txt, metrics.json, and generated-code/ under
each cell dir. A preliminary look at the 2026-06-26 run found the native PowerShell tool
was NOT observed in any of its 26 powershell-tool cells (agents ran pwsh through the Bash
tool); confirm, quantify, and extend that across all the combined run dirs.

Deliverable: a written comparison (saved under results/analysis/, dated) plus a tight
verdict on whether powershell-tool is a distinct condition here and any framing caveats
the report/blog should carry. Report findings; do not change benchmark code or data.
```

### Prompt 2 — Hook time-saved stat: PowerShell + ACT (code fix)

```
GHA-bench (WSL bash box, repo at /home/passp/repos/GHA-bench). Orient first: read
AGENTS.md, then study the hook-savings code. Work in your own git worktree branched from
origin/main, AFTER the opus-4.8 canonical report has merged (this session changes report
numbers, so it must not race the finalization session). Run the unit tests before/after;
add tests for anything you change; follow the "Before every PR" checklist in AGENTS.md.

Two defects in the "time saved by hooks" stat to fix:

(1) PowerShell coverage. The net-saved seconds already use a per-mode constant
(TEST_RUN_COST_S, with powershell entries), so they are NOT bash-only. But the
"% of test time saved" denominator comes from _categorize_tool_time() (generate_results.py
~L329), which filters to tool_name == "Bash" (~L359). Empirically that loses nothing in
the latest run because agents run pwsh THROUGH the Bash tool — so FIRST verify whether any
PowerShell command time is actually dropped in the combined dataset before changing
anything. Treat it primarily as a latent-robustness issue: if a future run used the native
PowerShell tool, that time would vanish — and note runner.py ~L733 stores an empty command
string for any non-Bash tool, so a complete fix may span runner.py (capture) AND
generate_results.py (categorize). (Related context: the native PowerShell tool appears
unused in this WSL environment — see the powershell-vs-powershell-tool analysis if it's
been done.)

(2) ACT time. The hook can structurally save `act` container time, but only for
statically-detectable errors (actionlint on workflow YAML, syntax/type) that would have
caused a failed `act` run the agent then re-ran — never for runtime/logic act failures.
The current model flat-rates every catch at one test-run cost (8-35s), so a catch that
averts a minutes-long `act` run is badly under-credited; there's a dormant act_ms bucket in
_categorize_tool_time you may be able to use for a measured act-run cost (from
generated-code/act-result.txt). DECISION ALREADY MADE: count actionlint/YAML lint catches
as act-time-saved. OPEN QUESTION for you to resolve and propose: how to handle lint
findings that are essentially cosmetic from `act`'s pass/fail perspective vs act-blocking
ones. Classify by MESSAGE, not by linter: YAML syntax / schema / expression / bad
uses-needs = act-blocking; embedded shellcheck SC#### on run bodies = mostly act-cosmetic
(`act` runs the script regardless). NOTE pyflakes is NOT uniformly cosmetic — it "never
complains about style" and avoids false positives, so its `undefined name` finding is a
runtime NameError = act-BREAKING (credit it), while its `unused import`/`unused variable`
findings are act-cosmetic. (Path nuance: the hook's plain-.py branch is py_compile =
syntax-only and would not catch undefined names; pyflakes reaches the agent only via
actionlint on workflow-YAML embedded Python.) actionlint's output (stored by the hook)
carries rule names + messages; consider validating any message→does-act-break heuristic
against cells where `act` actually ran with that error class. This half is a modeling
decision — surface your proposed valuation for sign-off before baking it in.

(3) MISSING LINTERS (bigger than the stat's math). The hook's required linters are
unevenly installed: pyflakes (Python semantic) and PSScriptAnalyzer (PowerShell) are MISSING
on the host, so powershell cells catch 0/27 and python ~0.04/cell, while typescript-bun
catches ~12.88/cell (and those tsc catches are act-cosmetic via bun). So the hook-savings
stat is essentially a TypeScript artifact and cross-language comparison is unfair. Decide:
(a) install pyflakes + PSScriptAnalyzer for parity in future runs; (b) apply the
act-cosmetic discount (hits TS hardest); (c) caveat the existing dataset as
linter-availability-dependent and TS-dominated. See the run-data table in this memo's
"MAJOR FINDING" section.

(4) TSC INVOCATION BUG (the TS catches are ~99% false positives). hooks/syntax-check.py runs
`bunx tsc --noEmit <file>`, which makes tsc IGNORE the project tsconfig and abort with TS5112
— so it never type-checks real TS code; all 335 TS "catches" are config artifacts (TS5112 +
target/module fallout). Fix the invocation so tsc loads the project tsconfig AND has bun's
types available (the -p form trips TS2688 "cannot find type definition file for 'bun'"
otherwise). Agents ignored the spurious nudge (1/26 reacted), so ts-bun cell results are OK,
but the hook-savings TS figure is invalid. You can SALVAGE existing data by filtering
config-artifact catches out of stored hook_events stdout and recomputing — no re-run needed.
This is harness code (fair to fix), not agent-generated code.

Also note (from AGENTS.md "Combined-report parity"): hook/trap Savings Analysis is NOT
currently ported into the combined report, so decide and state how far your fix propagates.

Deliverable: the corrected stat (per-run reports regenerated), tests, a short note on the
empirical PowerShell + missing-linter + tsc-misinvocation findings and your ACT valuation
choice, and a PR. Do not touch agent-generated code in workspaces/ or
results/*/generated-code/.
```

### Prompt 3 — Combined-report completeness audit

```
GHA-bench (WSL bash box, repo at /home/passp/repos/GHA-bench). Orient first: read AGENTS.md
(especially "Combined-report parity with per-run reports" and the combine_results.py
invariants) and compare combine_results.py against generate_results.py. Read-only worktree
from origin/main; CHANGE NOTHING.

Goal: make sure the report-combining script isn't dropping anything from the individual
per-run reports that I might want in the combined report. Enumerate everything that a
per-run results.md contains but the combined report omits or only partially carries —
sections, columns, sub-tables, prose blocks, savings/trap analyses, discrepancy checks,
correlation tables, anything. AGENTS.md already lists some known gaps (e.g. Savings
Analysis not ported, Test Quality partial); verify those are still accurate and find any
others not documented.

Deliverable: a plain-language inventory of what's missing or partial in the combined
report relative to the per-run reports, with enough detail that I can judge each. Then STOP
and ASK me what I want done about each item — do not implement, port, or change anything
until I decide.
```

---

## 3. Combining the sessions & concurrency

**Combine?**
- #1 and #2 share the powershell-tool subject; #1's "is powershell-tool distinct?" verdict
  informs whether #2's PowerShell-robustness work matters. Combining is reasonable, but to
  keep #2 surgical, prefer running **#1 first** and feeding its verdict into #2.
- #3 is a separate question (completeness, not powershell/hooks) — keep it its own session,
  but run it **early**: if it confirms hook/trap Savings Analysis isn't ported to the
  combined report, that bounds how far #2's fix must reach.
- Suggested order: **#3 → #1 → #2** (audit informs scope; analysis informs the fix).

**Concurrency (same machine / same account):**
- NOT concurrent with the in-flight benchmark, and NOT concurrent with the finalization
  session — shared weekly Claude allowance + #2 races `generate_results.py`/`results/`.
  This is what the CELLS-COMPLETE.md signal gates.
- After STEP 6 merges: they CAN run concurrently **only if each is in its own git
  worktree** (file isolation), with caveats — (a) shared weekly allowance drains ~3× faster
  with 3 concurrent heavy sessions, watch the cap; (b) #2 rewrites report files, so #1/#3
  must read a stable dataset (run #2 last, or pin #1/#3 to the post-STEP-6 commit); (c) none
  run the benchmark runner, so the flock is a non-issue. Simplest safe shape: **#3 and #1
  concurrently in separate worktrees, then #2 alone afterward.**
