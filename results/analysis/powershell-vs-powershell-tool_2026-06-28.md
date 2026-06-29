# `powershell` vs `powershell-tool`: are they a distinct condition in this (WSL) benchmark?

**Date:** 2026-06-28
**Author:** analysis session (issue #23, Prompt 1 in `followup-session-prompts_2026-06-28.md`)
**Dataset pin:** commit `83299e56` (`Merge pull request #26 from Adam-S-Daniel/worktree-opus48-bench`)
**Nature:** read-only over committed benchmark data. No benchmark code/data was run or modified.

---

## Verdict (TL;DR)

**`powershell-tool` is NOT a behaviorally distinct condition in this environment.** Across **all 133
`powershell-tool` cells** in every run directory that contains the condition, the agent reached `pwsh`
**through the Bash tool in 100% of cells**, exactly as the `powershell` cells do. The native PowerShell
tool — the *only* thing that differs between the two modes — was invoked in just **2 of 133 cells
(1.5%)**, both **haiku-4.5**, accounting for **10 of ~5,387 shell invocations (0.19%)**, and even those
two cells used it solely to re-run Pester tests while routing the rest of their work through Bash. The
headline **Opus and Sonnet cells never touched it at all.**

Consequently the two columns are statistically indistinguishable on outcome, timing, cost, and hook
behavior: within each run the **median duration is identical** (7.7 vs 7.8 min; 8.6 vs 8.6 min; 17.1 vs
17.2 min) and the paired duration ratio has **median 1.00** with `powershell-tool` slower in exactly half
the pairs (67/133, 50.4%). Any per-variant grade gap the reports show between the two columns (e.g. the
opus-4.8/medium `A+` vs `B+` in `2026-06-26`) is **run-to-run nondeterminism, not a tool effect** — the
native tool was provably never used in those cells.

**Framing implication:** treat `powershell` and `powershell-tool` as **one PowerShell condition** in the
report/blog (or explicitly caveat the column), and do **not** attribute any `powershell-tool`-vs-`powershell`
difference to "the PowerShell tool." See [Framing caveats](#framing-caveats-for-the-reportblog).

This **confirms and extends** the preliminary finding (issue #23): the native tool was unused in the
`2026-06-26` opus-4.8 cells (true — 0/28 here), and the pattern holds across the older `2026-04-17` and
`2026-05-06` runs too, with the single qualification that **2 haiku-4.5 cells did touch the native tool**
(the preliminary, scoped to opus-4.8, did not see these).

---

## Why the two modes can only differ via the tool

The mode prompts are **byte-for-byte identical** (`runner.py` `PROMPT_TEMPLATES`, ~L250–280): same TDD
instructions, same Pester requirement, same "you MUST use PowerShell." The **only** difference the harness
introduces is an environment variable (`runner.py` ~L993–1001):

```python
if mode == "powershell-tool":
    env["CLAUDE_CODE_USE_POWERSHELL_TOOL"] = "1"
elif mode == "powershell":
    env["CLAUDE_CODE_USE_POWERSHELL_TOOL"] = "0"
```

So the two conditions are identical unless the agent actually *invokes the native PowerShell tool*. If it
never does, the two cells are running the same experiment twice. The runner's own comment anticipates this:
"Without this, the agent always routes pwsh invocations through the Bash tool on Linux/WSL." The benchmark
runs in WSL, and Claude Code's PowerShell-tool documentation is Windows-oriented — the motivating hypothesis
for this issue.

---

## Scope: which run dirs, which contain the condition

Seven run dirs exist under `results/`. The **current combined report** is
`results/results_2026-05-06_173435__2026-04-17_004319__2026-04-09_152435.md` (sources: `2026-05-06`,
`2026-04-17`, `2026-04-09`). The `powershell-tool` condition was only introduced part-way through the
project's history, so older dirs lack it:

| Run dir | In current combined report? | `powershell` cells | `powershell-tool` cells |
|---|---|---|---|
| `2026-04-02_163146` | no | 72 | **0** (pre-condition) |
| `2026-04-07_225702` | no | 72 | **0** (pre-condition) |
| `2026-04-08_192624` | no | 16 | **0** (pre-condition) |
| `2026-04-09_152435` | **yes** | 16 | **0** (pre-condition) |
| `2026-04-17_004319` | **yes** | 49 | **49** |
| `2026-05-06_173435` | **yes** | 56 | **56** |
| `2026-06-26_103905` | not yet (opus-4.8, incoming) | 28 | **28** |

So **within the current combined report**, `powershell-tool` exists in **two** of the three source dirs
(`2026-05-06`, `2026-04-17`); `2026-04-09` predates the condition. The **`2026-06-26` opus-4.8 run** — the
preliminary finding's subject — is not yet merged into the combined report on this pinned commit, but it is
the most decision-relevant run and is included here as the incoming canonical dataset.

This analysis covers the **133 `powershell-tool` cells and their 133 matched `powershell` cells** in
`{2026-04-17, 2026-05-06, 2026-06-26}` (7 tasks × the model/effort variants present in each run).

### Method

A read-only scan parsed each cell's raw `cli-output.json` (the unfiltered Claude Code event stream — ground
truth for tool names, so this is a behavioral finding and not a capture-gap artifact) and its `metrics.json`
(outcomes/timing/cost/tokens/quality/hooks). Tool-name tallies came from `tool_use` blocks; `pwsh` reach
was detected from `Bash` command bodies. The scan script lives outside the repo (scratchpad) and wrote
nothing into `results/`.

---

## Findings

### 1. The native PowerShell tool is almost never used — and never by Opus/Sonnet

Across all 266 cells (both modes), the distinct tool names invoked were:

```
Bash 5377, Write 2336, Edit 1628, Read 494, TodoWrite 441, ToolSearch 105,
TaskUpdate 71, TaskCreate 44, Monitor 6, TaskOutput 5, Glob 5, TaskStop 3,
Grep 1, Agent 1, Workflow 1, ScheduleWakeup 1, PowerShell 10
```

`PowerShell` (the native tool) = **10 calls total**, vs **5,377 Bash** calls. All 10 are concentrated in
**two cells**, both `powershell-tool`, both `haiku-4.5`:

| Run | Cell | Native `PowerShell` calls | pwsh-via-Bash calls in same cell |
|---|---|---|---|
| `2026-04-17` | `18-secret-rotation-validator / powershell-tool-haiku45` | 5 | 13 |
| `2026-05-06` | `15-test-results-aggregator / powershell-tool-haiku45` | 5 | 4 |

- **Zero** native-tool calls in any `powershell` (tool-disabled) cell — confirming the
  `CLAUDE_CODE_USE_POWERSHELL_TOOL=0` opt-out works and there is no ambient leakage.
- **Zero** native-tool calls in any Opus-4.7, Opus-4.8, or Sonnet-4.6 cell, at any effort level.
- Even the two haiku cells used the tool **only to run Pester**, after building everything through Bash.
  In `2026-04-17` the calls are genuine PowerShell (`Set-Location …; Invoke-Pester …Tests.ps1 -PassThru`);
  in `2026-05-06` the agent fed the PowerShell tool a **Bash-shaped** line
  (`cd … && pwsh -Command "Invoke-Pester …"`) — i.e. it treated the native tool like a Bash shell, nesting
  another `pwsh` inside it. Either way the tool had no bearing on how the solution was built.

### 2. How `pwsh` is actually reached: via the Bash tool, identically in both modes

**Every one of the 133 `powershell-tool` cells reached `pwsh` through the Bash tool** (and so did every
`powershell` cell). The dominant pattern is `pwsh -NoProfile -Command '…'` / `pwsh -NoProfile -Command
'Invoke-Pester -Path …Tests.ps1 -Output Minimal'`, plus occasional `& ./script.ps1`. This is exactly the
mechanism the `powershell` (tool-disabled) cells use. The env var changed *what tools were available*; it
did not change *what the agent chose to do*.

### 3. Language compliance is total in both modes

`language_chosen == "powershell"` in **266/266** cells. Enabling or disabling the PowerShell tool had no
effect on whether the agent complied with the mandated language.

### 4. Outcomes, timing, and cost are indistinguishable between the modes

Per-run, per-mode summary (medians):

| Run | Mode | Cells | Success | Native-tool cells | Median duration | Median cost | Mean error_count |
|---|---|---|---|---|---|---|---|
| `2026-04-17` | powershell      | 49 | 49/49 | 0 | 7.7 min | $1.35 | 0.73 |
| `2026-04-17` | powershell-tool | 49 | 49/49 | 1 | 7.8 min | $1.36 | 1.27 |
| `2026-05-06` | powershell      | 56 | 55/56 | 0 | 8.6 min | $1.51 | 1.11 |
| `2026-05-06` | powershell-tool | 56 | 55/56 | 1 | 8.6 min | $1.62 | 1.11 |
| `2026-06-26` | powershell      | 28 | 27/28 | 0 | 17.1 min | $3.59 | 0.57 |
| `2026-06-26` | powershell-tool | 28 | 25/28 | 0 | 17.2 min | $3.39 | 0.50 |

Median durations match to within ~0.1 min within every run; median cost is within a few cents; success
rates are within one cell. Hook behavior is identical (same `hook_fires` per run, ~0 catches in both — a
separate known PowerShell-linter-availability issue, out of scope here).

**Paired test (same task + variant, differing only in mode), n = 133 pairs:**

- Median duration ratio `powershell-tool / powershell` = **1.002** (essentially 1.0).
- `powershell-tool` slower in **67/133 pairs (50.4%)** — a coin flip.
- Per-run median duration delta: **−4.9 s** (`2026-04-17`), **−11.4 s** (`2026-05-06`),
  **+69.6 s** (`2026-06-26`) — i.e. `powershell-tool` is *median-faster* in two of three runs.
- The mean ratios (1.10–1.44) sit above 1 only because a handful of long-running cells (high-effort /
  ultracode / timeout variance) happen to land in one mode — the right-skew signature of outliers, not a
  systematic treatment effect. Median + 50/50 split are the reliable readings.

### 5. Failures are timeouts driven by effort, evenly split across the modes

All 6 failures (of 266) are `timeout`, almost entirely at `xhigh`/`ultracode`:

| Run | Mode | Variant | Task |
|---|---|---|---|
| `2026-05-06` | powershell      | haiku45        | 12-pr-label-assigner |
| `2026-05-06` | powershell-tool | opus47-1m-xhigh | 12-pr-label-assigner |
| `2026-06-26` | powershell      | opus48-1m-xhigh | 13-dependency-license-checker |
| `2026-06-26` | powershell-tool | opus48-1m-xhigh | 12-pr-label-assigner |
| `2026-06-26` | powershell-tool | opus48-1m-xhigh | 16-environment-matrix-generator |
| `2026-06-26` | powershell-tool | opus48-1m-xhigh | 17-artifact-cleanup-script |

3 in each mode. These track effort/model (xhigh budget exhaustion), not the tool condition.

### 6. Quality / error patterns: no meaningful gap

`error_count` (lint/runtime errors the harness recorded) is essentially equal: `powershell` mean 0.86 vs
`powershell-tool` mean 1.04 across all cells; the only visible per-run spread is `2026-04-17`
(0.73 vs 1.27), reversed by `2026-06-26` (0.57 vs 0.50). The judge-scored grades in the reports
(Test Quality / Workflow Craft) likewise move within a band consistent with run-to-run variance, not a
direction attributable to the tool (which, again, was never invoked in the graded Opus/Sonnet cells).

---

## Framing caveats for the report/blog

1. **Do not present `powershell-tool` as a distinct treatment in this dataset.** The per-run and combined
   reports list it as its own language-mode column with independent grades. Behaviorally it is the same
   experiment as `powershell` run a second time. Safest options: (a) merge the two into a single
   "PowerShell" condition, or (b) keep both columns but add a prominent note that they are
   environmentally-identical-in-practice here and that differences between them are noise.

2. **Never attribute a `powershell-tool` − `powershell` difference to "the PowerShell tool."** The clearest
   trap is `2026-06-26` opus-4.8/medium, where the report shows `powershell` `A+` (7.4 min / $1.81) vs
   `powershell-tool` `B+` (10.1 min / $2.57). The native tool was invoked **0 times** in those cells, so the
   gap is pure model nondeterminism. A reader skimming the column will otherwise conclude the tool slowed
   things down.

3. **The "Windows tool in a WSL/Linux box" caveat is the real story.** The native PowerShell tool is a
   Windows-oriented feature; on this WSL host the model defaults to `pwsh`-via-Bash and almost never reaches
   for it. If the blog wants to say anything about the PowerShell *tool*, the honest claim is "in our Linux
   environment the agent effectively ignores it" — not a performance comparison.

4. **Scope the claim precisely.** "Native tool unused" is fully true for Opus/Sonnet at every effort and for
   the entire `2026-06-26` run; the only exceptions are **2 haiku-4.5 cells** that used it sporadically for
   test execution. State the 1.5%-of-cells / 0.19%-of-calls figures rather than an absolute "never."

5. **Input to the stat-rework / hook-savings work (Prompt 2).** This confirms the empirical premise there:
   because `pwsh` is reached through Bash, PowerShell command time is *not* dropped by the `tool_name ==
   "Bash"` filter in `_categorize_tool_time` for the current dataset. The PowerShell-robustness fix is a
   latent-robustness concern (it would bite only if a *future* run actually used the native tool), not a
   correction the current numbers need.

---

## Limitations of this analysis

- Detection of the native tool relies on the tool name (`"PowerShell"`) appearing in `cli-output.json`. The
  scan also searched case-insensitively for any `pwsh|power` tool name and found only `PowerShell` — no
  alternate-cased or aliased variant exists in the data.
- `quality.tests_pass` is `null` for all these cells (the project scores quality via the LLM-judge panel,
  not a captured pass flag), so the outcome proxies used here are `run_success`, `error_count`, and
  `failure_reason`, cross-checked against the reports' judge grades.
- `2026-04-09` is part of the combined report but predates the `powershell-tool` condition (0 cells), so it
  contributes a `powershell` baseline only.
- Counts reflect the pinned commit `83299e56`. The `2026-06-26` run shows 28 `powershell-tool` cells here;
  the preliminary memo cited 26–27 because it was written mid-run.
