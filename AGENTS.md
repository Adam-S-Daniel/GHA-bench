# Agent Instructions

All agent-facing instructions live in this file. `CLAUDE.md` contains only a
reference here. If you are a Claude Code agent, you have already loaded this
via `CLAUDE.md`. Other agents: read this file directly.

## Build and test

```bash
# Run unit tests (REQUIRED before every PR)
pip install pytest  # if not already installed
python3 -m pytest tests/ -v

# Validate imports
python3 -c "from runner import main"
python3 -c "from generate_results import generate_results_md"
python3 -c "from test_quality import compute_structural_metrics"
python3 -c "from llm_providers import get_provider"
python3 -c "from version_docs import build_doc, main"
python3 -c "from combine_results import combine"

# Regenerate all reports
python3 generate_results.py --all

# Run a benchmark (v4, all tasks/modes/models). Use 5 modes including
# powershell-tool. For multi-(model,effort) matrices, run sequentially via
# a wrapper script (see run-fresh-matrix-2026-05-06.sh).
python3 runner.py --tasks 11,12,13,15,16,17,18 --modes default,powershell,powershell-tool,bash,typescript-bun --models opus,sonnet

# Watch a run while it is still in progress (read-only live dashboard). Reads
# whatever metrics.json files exist so far; never touches the run. The head-to-head
# is automatic: the strongest model+version in this run vs the strongest in the
# previous report (newest completed run), broken down per scripting language.
# Override the auto-pick with --baseline DIR and/or --pair RUNVAR=BASEVAR.
python3 monitor.py --total 140 --watch 30                 # newest run, refresh 30s

# Build per-CC-version reference docs in each run dir (system prompt +
# tool descriptions + sliced changelog). Idempotent; caches under
# .cache/cc-versions/.
python3 version_docs.py                   # all run dirs
python3 version_docs.py results/<run-dir> # one run

# Evaluate test quality (structural metrics only)
python3 test_quality.py results/2026-04-09_152435

# Evaluate test + deliverable quality with the default panel of judges
# (Haiku 4.5 via claude-cli + Gemini 3.1 Pro via the agy CLI). Each judge
# writes its own cache file: test-quality-{short}.json and
# deliverable-quality-{short}.json. 8-worker thread pool by default;
# bump `--workers` if your CLIs + account limits allow more concurrency.
python3 test_quality.py --llm-judge --deliverable-judge \
    --judges haiku45,gemini31pro --workers 8 results/2026-04-17_004319

# Re-evaluate with a single judge only (useful for bias cross-checks)
python3 test_quality.py --llm-judge --judges haiku45 results/2026-04-17_004319

# Build custom act container (optional, eliminates pwsh install overhead)
docker build -t act-ubuntu-pwsh:latest -f Dockerfile.act .
```

## Code style

- Python 3.12+. No type stubs or mypy. Use type hints where they aid readability.
- Dollar amounts in results.md: round to nearest penny (`.2f`).
- Durations in results.md: always in minutes with 1 decimal (`{seconds/60:.1f}min`).
- No emojis in code or docs unless the user asks.

## Terminology

When the runtime wrapper uses `language_mode` (Python-side variable name), the
*user-facing* axis is called **language**, never "mode". This covers docs,
prompts, report prose, and LLM summaries. The internal field name stays
`language_mode` so existing metrics.json readers don't break; everything else
says "language" (e.g. "default/Python, bash, powershell, powershell-tool,
typescript-bun"). Rationale: "mode" is ambiguous with agent-approval-modes and
execution modes; "language" is the concept readers expect.

## Repository rules

- **No agent-generated `.github/workflows/` at repo root.** Agent workflows only exist inside workspaces under `workspaces/`. The repo's own CI workflow (`.github/workflows/ci.yml`) is the exception.
- **Never fix agent-generated code.** The benchmark measures autonomous output. Do not manually fix, edit, or patch workflow files in `workspaces/` or `results/*/generated-code/`.
- **`runner.py` observes and records, never intervenes** on agent code or errors.
- **Workspaces are throwaway.** Don't commit `workspaces/` contents.
- **`results/` is committed.** It contains archived metrics, generated code, and transcripts.
- **`CLAUDE.md` is only a pointer.** All instructions go in `AGENTS.md`. Never put substantive content in `CLAUDE.md` — it should only reference this file.

## Architecture

### Key files

- `models.py` — single source of truth for model IDs and token pricing. Update here when Anthropic changes prices.
- `runner.py` — benchmark harness. Runs agents via `claude -p`, collects metrics, pushes results. Imports from `models.py` and `generate_results.py`. Robustness invariants added 2026-06:
  - **Single-runner lock.** On startup it takes an exclusive non-blocking `flock` on `<repo>/.runner.lock` (`acquire_single_runner_lock`); a second runner exits(2) rather than execute cells concurrently — concurrent cells compete for CPU/Docker/pwsh and confound each other's timing/cost. (Released automatically on exit.)
  - **Resume validity.** `--resume` skips a cell only when its `metrics.json` is non-empty + parseable (`_metrics_valid`), so a write interrupted by a crash/teardown is re-run rather than skipped forever, leaving a hole.
  - **Honest push logging + commit-per-cell.** The `PeriodicPusher` thread commits+pushes `results/` **once per newly-completed cell** (wakes every `PUSH_CHECK_INTERVAL`s, commits only when `run_count` increased) — one commit per result, each pushed immediately. `git_push_results` checks the push exit code and logs an explicit WARNING on failure instead of always printing "Pushed results".
- `generate_results.py` — generates `results.md` reports and updates `README.md`. Can run standalone: `python3 generate_results.py --all`. Each results.md opens with a "Claude Code versions used" line linking to the per-version docs (see `version_docs.py`).
- `combine_results.py` — produces cross-run combined reports `results/results_<dirA>__<dirB>[__<dirC>...].md`. Same table layout as per-run reports plus a CLI Version Legend; uses `judge_consistency_report.py` for the JCS section and `conclusions_report.py` for the Opus-max Conclusions prose. Standalone: `python3 combine_results.py <dirA> <dirB> [<dirC> ...]`.
- `monitor.py` — read-only **live** dashboard for an in-flight run. Groups completed cells by `variant` and prints per-variant run-health (duration, cost, turns, errors, actionlint, hooks, test-exec time), structural code metrics (impl files/lines, workflow files/lines, total lines — all non-LLM), structural test metrics (test files/lines, tests, assertions, assertions/test, test:code ratio — all non-LLM), and live-detected traps. The head-to-head is **automatic and always strongest-vs-strongest**: `strongest_model_short` (ranked by `model_power` — family, then version, then 1m>200k context) picks the most powerful model+version in *this* run and in the *previous report* (auto-detected: newest run with a `summary.json` older than this one), then matches them by task+language at each shared effort. It also breaks the comparison down **per scripting language** and flags languages whose deltas differ significantly (≥1.5σ and ≥25 pts) from the cross-language mean. Override the auto-pick with `--baseline DIR` (which prior run; `none` to skip) and/or `--pair RUNVAR=BASEVAR` (exact variant pairing); for full cross-model rollups use `combine_results.py` post-run. On Claude-subscription auth it also prints the **weekly subscription allowance** via `GET /api/oauth/usage` (the endpoint behind the CLI's `/usage`): five-hour + weekly limits from the `limits[]` array, annotating which weekly cap an Opus run draws from, plus `extra_usage`. It reads the OAuth token from `~/.claude/.credentials.json`, never logs it, degrades gracefully (skipped when there are no OAuth creds — e.g. API-key auth has no weekly cap — or on HTTP error), and can be disabled with `--no-usage`. `--total N` enables a pace-based ETA (a floor — later tranches run slower); `--watch SECS` refreshes. Pure logic (`aggregate`, `match_pairs`, `group_by_variant`, `model_power`, `strongest_model_short`, `flag_outliers`, `format_usage`) is unit-tested in `tests/test_monitor.py`; the `fetch_usage` network call and the structural/trap helpers (which reuse `test_quality.compute_structural_metrics` and `generate_results._detect_traps`) are best-effort and not unit-tested. Distinct from `watchdog.sh` (process supervision) and `generate_results.py` (post-run report).
- `test_quality.py` — test + deliverable quality evaluation. Structural metrics (always) + panel-of-judges LLM evaluation (`--llm-judge` for test-quality judge, `--deliverable-judge` for workflow+scripts judge). `compute_structural_metrics` returns `impl_lines`, `test_lines`, `workflow_lines`, and **`code_lines` = impl + test + workflow** (the authored-code total). The reports' Failed-Runs "Lines" column and the monitor's "total" now use `code_lines`, NOT the runner's `code_metrics.total_lines` (a whole-dir count that also includes fixtures, README, helper scripts, and the `act-result.txt` log). None of these line counts feed any quality score — those come from the LLM panel (which reads the code) + the structural test:code ratio (`test_lines/impl_lines`). The default panel is Haiku 4.5 + Gemini 3.1 Pro (configured in the module-level `JUDGES` dict). Each judge writes its own per-run cache file; `load_panel_scores(variant_dir, kind)` reads them and returns a mean-aggregated score dict for the reporting layer. Legacy single-Sonnet `*-llm.json` caches still read for backward compat. Imported by `generate_results.py` for the "Test Quality Evaluation" section.
- `llm_providers.py` — pluggable LLM provider abstraction for evaluation tasks (see "Adding LLM providers" below). Currently registered: `claude-cli` (pre-authenticated Claude Code CLI), `agy` (pre-authenticated Antigravity CLI — the Gemini path the `gemini31pro` judge uses; `agy -p` prints the response text directly, default model `Gemini 3.1 Pro (High)`), `gemini-api` (google-genai SDK, requires `GEMINI_API_KEY` and a paid-tier Google AI Studio account). The `gemini-cli` provider was **removed 2026-06-26** — per Google, *"On June 18, 2026, Gemini CLI and Gemini Code Assist IDE extensions will stop serving requests for Google AI Pro and Ultra, as well as those using it free of charge using Gemini Code Assist for individuals."* (https://developers.googleblog.com/an-important-update-transitioning-gemini-cli-to-antigravity-cli/); `agy` is its successor. See the removal note in `llm_providers.py`.
- `version_docs.py` — for each unique Claude Code version observed in a run dir's `metrics.json` files, writes `claude-code-<version>.md` with the full system prompt (concatenated from `Piebald-AI/claude-code-system-prompts` at tag `v<version>`), every default-tool description sorted alphabetically, and the slice of `anthropics/claude-code` `CHANGELOG.md` from the lowest CC version observed in any benchmark in this repo through that version. Standalone: `python3 version_docs.py [<run-dir>]`. Caches upstream content under `.cache/cc-versions/` (gitignored). Output files are referenced by name in each `results.md`'s prominent "Claude Code versions used" line.
- `benchmark-instructions-v*.md` — per-version specs given to agents during runs.
- `hooks/syntax-check.py` — PostToolUse hook for syntax/lint checking.
- `Dockerfile.act` — custom act container image with pwsh + Pester pre-installed. Build with `docker build -t act-ubuntu-pwsh:latest -f Dockerfile.act .`. Runner.py auto-detects it and injects `.actrc` into workspaces.
- `run-fresh-matrix-*.sh` — per-campaign wrapper scripts that drive multiple sequential `runner.py` invocations (one per model-effort combo) into a single results dir using `--resume`. Use when the matrix needs more than one effort level; `runner.py` accepts a single `--effort` per invocation by design. See `run-fresh-matrix-2026-05-06.sh` for the canonical 8-invocation full-matrix template.
- `run-opus48-resume.sh` + `run-opus48-supervisor.sh` — the **resilient** per-campaign runner for the opus-4.8 (1M) campaign (run dir `2026-06-26_103905`; 7 tasks × 5 languages × 4 efforts medium/high/xhigh/ultracode = 140 cells). `run-opus48-resume.sh` runs all four tranches with `--resume` (re-runnable; skips valid cells). `run-opus48-supervisor.sh` is the entry point — launch via `setsid bash run-opus48-supervisor.sh` so it survives a session teardown; it restarts the resume worker whenever the runner dies, until all 140 cells are done. It takes an `flock` on `.supervisor.lock` (and `runner.py` on `.runner.lock`) so no two runners ever run concurrently. This pattern supersedes a plain one-shot launcher for multi-day runs that must survive crashes/reboots; pair it with `monitor.py` for live status (the supervisor and runner never need git for monitoring).
- `skills/` — agent skills following [agentskills.io](https://agentskills.io/specification) spec.

### Adding new trap detectors

See the docstring on `_detect_traps()` in `generate_results.py`. Each trap needs:
a kebab-case name, detection logic over bash_cmds/console/metrics, a time estimate,
and an entry in `trap_applicable_mode` if mode-specific.

### LLM vs structural discrepancy checks

After every report generation (`python3 generate_results.py --all`), check the
"LLM vs Structural Discrepancies" section in each `results.md`. Discrepancies
are auto-classified by `_find_discrepancies()` in `generate_results.py`:

- **counter-gap**: structural metrics are implausibly low (e.g. 0 tests or 0
  assertions while LLM scores high). This means `test_quality.py` is missing a
  test pattern. **Fix the counter** — read the generated test files to identify
  the pattern the counter doesn't recognize, add it to the appropriate
  `_count_*()` function and the detection/classification patterns, add unit
  tests, and regenerate. Counter-gap discrepancies should not persist across PRs.
- **qualitative**: structural metrics look reasonable but the LLM disagrees on
  quality. The report includes the LLM's justification (from the `summary`
  field in `test-quality-llm.json`). These are expected and acceptable — review
  the justification to confirm it's coherent, then leave them.

If a **new counter-gap** appears after changing `test_quality.py`, it's a
regression. Fix it before merging.

### Combined-report invariants (`combine_results.py`)

The combined report (e.g. `results/results_<dirA>__<dirB>.md`) pools
runs across multiple source directories. A few layout invariants must
hold — changes here have broken the generated markdown before, so
`tests/test_combine_results.py` guards them:

- **No duplicate `(language, variant_disp)` rows in Tiers or
  Comparison.** `aggregate_rows` groups by `(language_mode,
  model_short, effort_level)` only. CLI versions pool into one row;
  `cli_versions` on the row retains the per-CLI breakdown for the
  legend to consume. (Previously the aggregate split by CLI, which
  rendered as duplicate-looking rows whose Model column matched.)
- **CLI Version Legend schema.** Exactly one CLI version per row.
  Columns: `Variant label | CLI version | Tasks | Languages`. `Tasks`
  and `Languages` each hold either `All` (pair covered every task /
  every language observed in the report) or a comma-sorted subset.
  The plural header `CLI version(s)` and comma-joined version cells
  are the old layout — do not reintroduce.
- **Section order in the body:** Scoring → Conclusions → **Judge
  Consistency Summary** → Tiers → Comparison → Per-Run → Notes. JCS
  is a top-level `##`, not a `### ` under Notes, because readers
  benefit from the panel-health verdict before they consume
  rankings.
- **Quality-score lookup key.** The per-variant score bucket is keyed
  by `(language_mode, _label(m))` which includes the `-cli<ver>`
  suffix; aggregate lookups must therefore use `r["variant_with_cli"]`
  (not `r["variant"]`). A prior regression where the lookup used the
  CLI-less `variant` caused every aggregate Tests Quality / Workflow
  Craft cell to render as `—` despite per-run scores being present.

### Where the Conclusions prose lives

The max-effort Opus `## Conclusions` block is produced **only for
the combined cross-run report** (`combine_results.py`), not for
per-run `results.md` files. `generate_results.py` still invokes the
JCS Summary LLM call (cheap) but passes `speed_cost_input=None` so
`conclusions_report.generate_conclusions_from_inputs` short-circuits
the Conclusions call. Reasoning: comparing a single run directory
against itself doesn't surface tradeoffs worth ~$1 of max-effort
tokens per regen — the Conclusions prose only reads as useful when
multiple run dirs are being compared.

If you need per-run prose for some new purpose, plumb through a
separate prompt; do not re-enable the merged Conclusions call at the
single-run site.

### Judge rationale audit (`judge_audit.py`)

The combined report includes a `## Judge Audit Outcomes` section
that lists every run where the panel judges span ≥ 4 points on a
1–5 scale (i.e. Haiku = 1, Gemini = 5). For each flagged row the
audit scans each judge's rationale for concrete file-existence
claims (see `MISSING_PHRASES` + file-extension regex) and resolves
them against the run's `generated-code/` tree. Drop rule:

- One judge contradicted → drop that judge's score; panel mean
  becomes the other judge's number.
- Both contradicted → drop both; panel mean becomes `—` and the
  row is excluded from aggregates.
- Neither contradicted → keep both.

Verdicts persist as `judge-audit-<kind>.json` next to each run's
judge caches. `test_quality.load_panel_scores` consumes the verdict
automatically, so the Tiers / Comparison / LLM-as-Judge tables
above honor the audit with no extra plumbing.

### Per-judge prompt addendums

`JUDGES[...]` in `test_quality.py` accepts a `prompt_addendum_tests`
key. The test-quality evaluator appends it to the shared rubric for
that judge alone, so a model-specific steer (e.g. Haiku's
missing-file sanity note) doesn't drag the other judges along.
`python3 test_quality.py --rejudge haiku45 <run_dir>` refreshes
only that judge's cache — handy after tweaking its addendum.

### Combined-report parity with per-run reports

Per-run `results.md` carries three top-level sections the combined
report does not yet replicate in full:

| Per-run section                  | Combined report status |
|----------------------------------|------------------------|
| `## Failed / Timed-Out Runs`     | Ported (2026-04-21)    |
| `## Test Quality Evaluation`     | Partial — structural metrics + panel LLM-as-Judge table ported; Correlation and LLM-vs-Structural Discrepancies sub-tables still absent |
| `## Savings Analysis` (Hook / Trap / Cache savings) | **Not yet ported.** Depends on per-run hook telemetry + `_detect_traps` output that aren't currently threaded into `combine_results.py`. Readers needing savings data should drop into the per-run `results.md` for now. |

When porting the remaining bits, factor the section builders out of
`generate_results.py` into module-level helpers so both entry
points share a single implementation — the duplication we'd
otherwise accrue would drift the two reports out of sync.

### Judge consistency summary (prompt hygiene)

`JUDGE_CONSISTENCY_SUMMARY_SYSTEM_PROMPT` in
`judge_consistency_report.py` forbids unexplained shorthand. If you
surface disagreement rows, introduce them with the plain-language gap
size (e.g. "the widest disagreements — a judge scoring 1 vs 5, a
4-point gap on a 1–5 scale — include …"). Do not coin abbreviations
("Span-N", "Δ-N", etc.) that a reader has to decode. Cite specific
runs as `task-id-name / language / model-variant` (the same triple
the Per-Run table uses).

Follow-up analyses of flagged disagreement rows live under
`results/analysis/` as dated standalone markdown files (e.g.
`judge_disagreement_1-vs-5_2026-04-21.md`). Link them from the JCS
section when regenerating if they remain relevant.

### Updating model pricing

Edit `models.py`. Check https://docs.anthropic.com/en/docs/about-claude/models and
https://www.anthropic.com/pricing. Then run `python3 generate_results.py --all`.

### Regenerating reports

After changing `generate_results.py`, run:
```bash
python3 generate_results.py --all
```
This regenerates `results.md` for every run directory and updates `README.md`.

### Adding LLM providers

The LLM-as-judge evaluation in `test_quality.py` uses a pluggable provider
system defined in `llm_providers.py`. The benchmark runner (`runner.py`) is
inherently tied to the Claude Code CLI (it tests CLI-specific features), but
the evaluation layer is provider-agnostic.

To add a new provider (e.g., Anthropic API, OpenAI, Codex CLI):

1. Open `llm_providers.py` and create a class inheriting from `LLMProvider`.
2. Implement `is_available()` — return True when the provider can be used.
3. Implement `judge(system_prompt, user_message, model)` — return
   `{"text": str, "cost_usd": float, "input_tokens": int, "output_tokens": int}`.
4. Register it in the `PROVIDERS` dict at the bottom of the file.
5. Use it: `python3 test_quality.py --llm-judge --provider your-provider`.

See the docstring in `llm_providers.py` for a complete example skeleton.

## Before every PR

1. **Run all unit tests and verify they pass:**
   ```bash
   python3 -m pytest tests/ -v
   ```
   All tests must pass. Do not create or update a PR with failing tests.
2. **If you added or changed code, add or update unit tests** in `tests/`.
   New functions need test coverage. Changed behavior needs updated assertions.
3. Run `python3 generate_results.py --all` and verify no errors.
4. **Check for counter-gap discrepancies** in the generated `results.md` files.
   If any "Probable counter gaps" appear, fix them in `test_quality.py` before
   merging (see "LLM vs structural discrepancy checks" above). Qualitative
   disagreements are expected — verify the LLM justification is coherent.
5. Verify all import paths work: `python3 -c "from runner import main"`.
6. Spot-check a few numbers in results.md against raw metrics.json.
7. If you changed architecture or findings, update this file (`AGENTS.md`).
8. If you added files or moved things, update the Files table in `README.md`.

## Current state (2026-05-08)

### opus-4.8 (1M) campaign — in progress (2026-06)

`results/2026-06-26_103905/` is an in-progress v4 campaign adding
`claude-opus-4-8[1m]` (model short `opus48-1m`) at four effort levels —
medium, high, xhigh, and the new **`ultracode`** (xhigh + dynamic-workflow
orchestration; enabled via `CLAUDE_CODE_EFFORT_LEVEL=ultracode`, since `--effort`
does not accept it) — over the same 7 tasks × 5 languages = 140 cells. Driven by
the resilient `run-opus48-supervisor.sh` + `run-opus48-resume.sh` pair with
single-runner locks; watch it live with `monitor.py`. When it completes it gets
the standard panel-of-judges eval (Haiku via Claude CLI + Gemini 3.1 Pro (High)
via `agy`) and a consolidated report, and this section's "canonical dataset"
should be updated to point at it. Note: opus-4.8 sometimes picks JavaScript /
PowerShell for the free-choice (default) language, not always Python.

### v4 full-matrix benchmark — complete

`results/2026-05-06_173435/` is the canonical current dataset: 280/280 runs
across 7 tasks × 5 modes × 8 model-effort combos, $493.46 + $40.57 panel
eval = $534.03, 38h 35m wall, 278/280 successful (2 failures).
Single-directory, single-CC-version-line (2.1.131 → 2.1.132 mid-run);
supersedes the `results/2026-04-17_004319/` + `results/2026-04-09_152435/`
combined report. Standard panel-of-judges scores populated.

The 8 model-effort combos: `haiku45` (no effort), `opus`/`sonnet` (no
effort), `opus47-1m` at high/medium/xhigh, `opus47-200k` at medium,
`sonnet46-1m` at medium. The 5 language modes: `default`, `bash`,
`powershell`, `powershell-tool`, `typescript-bun`. The 7 tasks: 11, 12,
13, 15, 16, 17, 18 (task 14 archived earlier).

### Key findings vs prior baselines (CC 2.1.114 → 2.1.131/132)

- haiku45 ~21% faster on average (driven by a bash-mode regression-fix
  on the haiku endpoint; bash specifically went 7× faster, while
  powershell got 33% slower).
- opus47-1m-high notably slower and pricier (+21% dur, +28% cost).
  opus47-1m-medium ~24% faster, opus47-1m-xhigh flat. Other variants
  within run-to-run noise.
- The earlier `2026-04-24_202012` partial run was abandoned (had
  widespread CLI-error failures on haiku/sonnet/opus variants — 46%
  failure rate). Stash dropped on 2026-05-08.

### Earlier reference runs

- `results/2026-04-17_004319/` — 245 runs, mix of `2.1.112` + `2.1.114`. Used as the haiku45 / opus47-1m / sonnet46-1m baseline.
- `results/2026-04-09_152435/` — 64/64, CC 2.1.97/98/100. Used as the no-effort opus / sonnet baseline.
- `results/2026-04-08_192624/` — v3, 64 runs, 1 timeout, 3 double-result bugs. Avg 11.4min/run.
- `results/2026-04-07_225702/` — v2, 111/144 runs. 18 tasks, modes: default/powershell/powershell-strict/csharp-script. Superseded by v3.
- `results/2026-04-02_163146/` — v1, 144 runs, same as v2. Had permission-denial artifacts (88% of errors).
- See `design-and-planning-artifacts/` for historical analysis and planning docs.

### Per-CC-version reference docs

Each run dir contains one `claude-code-<version>.md` per CC version
observed in its `metrics.json` files. Built by `version_docs.py` from
`Piebald-AI/claude-code-system-prompts` (system prompt + tool
descriptions at that tag) and `anthropics/claude-code` `CHANGELOG.md`
(sliced to [lowest CC version observed in any benchmark in this repo,
this version], oldest first). Each `results.md` links these
prominently in the "Claude Code versions used" line at the top.

Regenerate after CC version changes:
```bash
python3 version_docs.py        # idempotent across all run dirs
```
