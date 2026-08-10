<!-- BEGIN MANAGED SECTION — DO NOT EDIT ABOVE "## Repo-specific additions" -->
<!-- Source: _agent-guidance -->
<!-- Sections: none -->

# AGENTS.md

> **Managed by [`_agent-guidance`].**
> Edit only below the `## Repo-specific additions` header.
> Everything above it will be overwritten on the next sync.

This block is deliberately short. It carries the things that are **specific to
this account and learned the hard way** — incidents, fleet policy, machine
layout. It does not restate general engineering practice, and it does not
describe anything you can learn by reading the repo. Depth lives in each repo's
`docs/` and in the skills registry; follow the pointers when the work touches
that area.

## Working in these repos

- Fix what was asked. No speculative features, premature abstractions, or
  unused helpers.
- Prefer editing an existing file over creating a new one.
- Every public interface change updates the corresponding tests.
- Run the existing test suite before calling a task complete, and say plainly
  what you ran. New behaviour gets a test; a bug fix gets a regression test.
- Tests must be deterministic — no sleeps, no network, no reliance on
  wall-clock time.

## Finding your unknowns

Output quality on a non-trivial task is bounded by how well the ambiguities got
resolved — and most of them surface *during* implementation, not before it. So
treat unknown-hunting as part of the work, not a phase that ends at the plan:

- Before building: name what you don't know. Prefer a reference in **code** — an
  existing implementation to mirror, a failing test, a rubric, an HTML mockup —
  over a prose description of the same thing.
- While building: keep a running note of decisions that departed from the plan
  and edge cases you hit. Surface them; don't silently absorb them.
- After building: be able to explain what changed and why it is correct.

The full workflow (blind-spot pass, self-interview, implementation notes,
post-hoc explainer) is the **`finding-unknowns`** skill in the registry. Reach
for it on unfamiliar code, a new domain, or anything with subjective acceptance
criteria.

## Workstation layout

Repo locations are host-specific — match the convention of the machine you're on
(on Windows, check `$env:COMPUTERNAME`).

- **`ZENDA`** (Windows): local clones live under `D:\repos\<github-owner-or-org>\<repo>`
  (for example `D:\repos\adam-s-daniel\wsl-automation`). Clone new repos there, and
  assume existing repos live there rather than under the user profile
  (`C:\Users\<user>\...`).

## Security

Standard practice applies without being restated here. These are the ones with
teeth in this account:

- Validate anything that crosses a trust boundary — user input, API responses,
  file contents.
- Never build SQL, shell commands, or HTML by string-concatenating untrusted
  data. Use parameterized queries, shell arrays, and context-aware escaping.
- Never commit secrets, credentials, or `.env` files.
- Never disable TLS verification, authentication, or CSRF protection.

## Data exposure in CI and public repos

Treat CI run logs, job summaries, artifacts, workflow run pages, and git history
as **public** on a public repo. (Real incident: a workflow printed the owner's
email addresses and their correspondents' into a public Actions log.)

- **Never print personal or sensitive data to a log** — no emails, contacts,
  names, IDs, mailbox sizes/counts, tokens, or anything "useful to an attacker or
  scammer." Deliver sensitive results out-of-band (e.g. email the account itself,
  write to a private store) and log only a non-identifying status line.
- **Don't interpolate `${{ inputs.* }}` / `${{ github.event.* }}` into a `run:`
  block** — the rendered command is echoed to the log. Read inputs from
  `$GITHUB_EVENT_PATH` inside the script and `::add-mask::` sensitive values
  before use. `::add-mask::` only scrubs the log *stream*, not other surfaces.
- **Put sensitive config in secrets, not plaintext inputs or `vars`.** Only
  secret *values* are masked in logs.
- **Sanitize error output** — never dump an API/HTTP response body on failure (it
  can quote personal data); reduce it to a status code + machine error type, and
  keep the data-bearing serialization/call inside the try/catch.
- **Least privilege:** set `permissions:` to the minimum (usually
  `contents: read`) and require approval for outside-collaborator fork PRs.
- **Test fixtures use reserved `example.com` / `example.net` domains only** —
  never a real address; fixtures get committed and logged.

### git history & metadata
- **Sanitize before the first commit.** Fixing the current file does not remove
  data from history. If sensitive data was committed, rewrite history to drop the
  commits, delete every ref that points at them (branches, tags, **PRs**), and
  force-push. GitHub garbage-collects unreachable objects on its own schedule
  (days to weeks) — until then they remain reachable *by SHA* — and you can ask
  GitHub Support to expedite for a public repo. (This is the deliberate exception
  to "don't force-push"; it is a security remediation.)
- **Commit with the GitHub `…@users.noreply.github.com` identity** on public
  repos so a real email is not baked into commit author/committer metadata.

## Automation vs branch protection

Fleet repos enforce PR-only default branches via ruleset, managed as code in
`repo-settings` (see its ADR 0001). Design automation accordingly:

- Never design a bot that pushes to a protected default branch ad hoc — the
  push is rejected (GH013), even from the repo's own workflows.
- Generated data (badges, run summaries, reports, dashboards) belongs on a
  dedicated unprotected results branch (e.g. skills-evals' `eval-results`);
  consumers read from that branch and treat its content as untrusted.
- The rare bot that genuinely must write to a default branch needs a ruleset
  bypass actor declared in repo-settings' `fleet.yml` — never a hand-granted
  UI bypass (the drift report flags those). The AGENTS.md sync App is the
  standing example.
- PR + auto-merge is not a sanctioned bot-write path for fleet repos; the
  cms-platform-managed repos (outside the fleet ruleset) use it by their own
  design.

## Dependency updates

Dependabot runs with a **minimum package age** (`cooldown`) so an unattended
merge still gets a cooling-off period: `default-days: 7`, `semver-major-days: 30`.
Two things about that setting are easy to get wrong:

- It applies to **version** updates only. A security advisory bypasses cooldown
  entirely and opens immediately — the wait never delays a vulnerability fix.
- An unset `cooldown` is **not** "no wait": GitHub applies an implicit 3-day
  minimum age to version updates. Writing 7 is a raise from 3, not from zero.

`semver-minor-days` / `semver-patch-days` are deliberately left undefined —
they fall back to `default-days`, and spelling them out only invites drift.
Pinning and bumping third-party action SHAs is the `pin-actions-to-sha` skill.

## Subagent delegation (model routing)

- Don't write code in the main loop: run the implementation in a subagent on an
  appropriately lower-power model (e.g. the Agent tool's `model` override in
  Claude Code; skip if the harness has no subagent support).
- Route by mechanicalness: smallest model (haiku-class) for exactly-specified
  edits — pin bumps, renames, config/doc tweaks; mid-tier (sonnet-class) for
  normal implementation from a clear spec. Escalate rather than ship a wrong
  diff when the task is genuinely subtle (cross-repo invariants, race
  conditions).
- The main loop keeps root-cause investigation, architectural decisions,
  writing the spec, and review of the subagent's diff before commit.
- Delegated work is done when a **verifier exits 0**, not when the report reads
  as finished. Name the exact command in the spec and require its exit code
  back. A subagent that cannot run it reports BLOCKED; a count that disagrees
  with the spec's stated expectation is a stop-and-report condition, never a
  rounding difference.
- Don't assume the subagent sees this file: general-purpose and custom
  subagents receive the full memory hierarchy (imports included), but
  Explore/Plan-type agents and SDK harnesses with `settingSources: []` skip
  repo guidance entirely. Restate load-bearing constraints (style, test
  command, invariants) in the delegation prompt, and don't hand
  guidance-sensitive work to agents that won't see it.

## Skills ecosystem

- The canonical skills registry is `github.com/Adam-S-Daniel/agentskills`,
  organized as three bundle plugins — `adam` (general-purpose, cloud-safe;
  default-on), `adam-local` (machine-bound), and `fastmail` — each holding
  `skills/<skill>/` directories.
- In Claude Code with the marketplace installed, invoke a skill as
  `/adam:<skill>` (e.g. `/adam:pin-actions-to-sha`).
- Local machines get the marketplace plus per-agent symlinks via that repo's
  `setup.sh`.
- Cloud sessions currently get **no** plugins from repo-declared settings — a
  known Claude Code limitation (see agentskills' `docs/decisions/0001`) — so
  don't assume bundle skills are available there.
- New reusable skills graduate **into** the registry (sensitive ones into
  `agentskills-private`) rather than living on in a consumer repo. A long skill
  splits across files rather than growing into one wall of text.

## Git practices

- Write concise commit messages that explain *why*, not just *what*.
- One logical change per commit.
- Do not amend published commits or force-push shared branches.

<!-- END MANAGED SECTION -->
## Repo-specific additions

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

# Run a benchmark (v4, all tasks/modes/models). Standard 4-mode set
# (powershell-tool dropped — see Repository rules). Always pass --effort
# explicitly for effort-capable models. For multi-(model,effort) matrices,
# run sequentially via a wrapper script (see run-fresh-matrix-2026-05-06.sh).
python3 runner.py --tasks 11,12,13,15,16,17,18 --modes default,powershell,bash,typescript-bun --models opus48-1m --effort high

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
says "language" (e.g. "default/Python, bash, powershell, typescript-bun").
Historical runs also carry a `powershell-tool` language, but reports collapse
it into `powershell` at display time (`_disp_mode`, #30) — the raw
`language_mode` and on-disk `powershell-tool-*` cell dirs are preserved.
Rationale: "mode" is ambiguous with agent-approval-modes and execution modes;
"language" is the concept readers expect.

## Repository rules

- **No agent-generated `.github/workflows/` at repo root.** Agent workflows only exist inside workspaces under `workspaces/`. The repo's own CI workflow (`.github/workflows/ci.yml`) is the exception.
- **Never fix agent-generated code.** The benchmark measures autonomous output. Do not manually fix, edit, or patch workflow files in `workspaces/` or `results/*/generated-code/`.
- **`runner.py` observes and records, never intervenes** on agent code or errors.
- **Workspaces are throwaway.** Don't commit `workspaces/` contents.
- **`results/` is committed.** It contains archived metrics, generated code, and transcripts.
- **`CLAUDE.md` is only a pointer.** All instructions go in `AGENTS.md`. Never put substantive content in `CLAUDE.md` — it should only reference this file.
- **Always set effort AND context explicitly on every run.** Pass `--effort` for every effort-capable model (i.e. everything but Haiku 4.5) and select an explicit context variant (`opus47-1m` vs `opus47-200k`, etc.). Never rely on the CLI defaults: the default effort is version-dependent (it flipped `medium`→`high` at CC 2.1.117) AND is not recorded in `metrics.json`, so cells run without `--effort` cannot be labeled with certainty afterwards. `runner.py` logs a prominent WARNING (not a refusal) when `--effort` is unset for an effort-capable model.
  - **We are NOT studying "default/no-effort" behavior as a condition.** We don't care about "what do you get when you don't specify effort." A run that omitted `--effort` is labeled purely by the effort it *actually* used (derived from the CC-version default) — e.g. the historical no-`--effort` base Sonnet 5 run is `sonnet5-1m-high` because it ran at the CC default `high`, and it is treated identically to an explicit-`high` run. Do NOT add a `default`/`no-effort` label, an inline "derived" marker, or otherwise try to keep no-effort runs distinct; and do not spin up new no-effort runs to characterize default behavior. (The derived-effort inference itself is documented in each combined report's "Model label conventions" section.)
- **Standard language set is `default,powershell,bash,typescript-bun` (4 modes).** Drop `powershell-tool`: under WSL it is functionally identical to `powershell` (same prompt body, same pwsh), so it adds a redundant cell per task without a distinct signal.
- **Post a live status heartbeat during runs.** Roughly every 30 minutes while a run is in flight, relay the full `python3 monitor.py --total <N>` report (run-health + structural metrics + head-to-head) so progress, pace/ETA, and any emerging failures are visible without waiting for completion.

## Architecture

Key files, trap-detector patterns, and LLM-vs-structural discrepancy handling
→ [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md). Combined-report layout
invariants, judge auditing, and reporting internals →
[`docs/REPORTING.md`](docs/REPORTING.md). Read the relevant doc before
touching `runner.py`, `generate_results.py`, `combine_results.py`,
`test_quality.py`, `judge_audit.py`, or `judge_consistency_report.py`.

### Key files

The purpose of every top-level file (`models.py`, `runner.py`,
`generate_results.py`, `combine_results.py`, `recover_cost.py`, `monitor.py`,
`test_quality.py`, `llm_providers.py`, `version_docs.py`, the
`run-opus48-*`/`run-fresh-matrix-*` wrapper scripts, `skills/`) → read
[`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) before touching any of them.

### Adding new trap detectors

What a new trap detector needs (kebab-case name, detection logic, time
estimate, mode entry) → read [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)
before adding one.

### LLM vs structural discrepancy checks

How `counter-gap` vs `qualitative` discrepancies are classified and which one
requires a fix before merging → read
[`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) after every
`generate_results.py --all` run.

### Combined-report invariants (`combine_results.py`)

The layout invariants `tests/test_combine_results.py` guards (no duplicate
rows, the CLI Version Legend schema, section order, the quality-score lookup
key) → read [`docs/REPORTING.md`](docs/REPORTING.md) before changing
`combine_results.py`.

### Where the Conclusions prose lives

Why the max-effort Opus Conclusions block only runs for combined reports, not
per-run `results.md` → read [`docs/REPORTING.md`](docs/REPORTING.md) before
re-enabling it at the single-run site.

### Judge rationale audit (`judge_audit.py`)

The drop rule for judges that span ≥ 4 points and how `judge-audit-<kind>.json`
verdicts feed back into `test_quality.load_panel_scores` → read
[`docs/REPORTING.md`](docs/REPORTING.md) before touching `judge_audit.py`.

### Per-judge prompt addendums

How `prompt_addendum_tests` scopes a judge-specific rubric steer, and how to
refresh a single judge's cache with `--rejudge` → read
[`docs/REPORTING.md`](docs/REPORTING.md) before editing `JUDGES[...]` in
`test_quality.py`.

### Combined-report parity with per-run reports

Which per-run `results.md` sections the combined report has and hasn't yet
ported, and the DRY rule for porting the rest → read
[`docs/REPORTING.md`](docs/REPORTING.md) before adding a new per-run section.

### Judge consistency summary (prompt hygiene)

The prompt-hygiene rules for `JUDGE_CONSISTENCY_SUMMARY_SYSTEM_PROMPT` (no
unexplained shorthand, plain-language gap sizes, citation format) → read
[`docs/REPORTING.md`](docs/REPORTING.md) before editing
`judge_consistency_report.py` or its prompts.

### Updating model pricing

Where to edit and check pricing → read [`docs/REPORTING.md`](docs/REPORTING.md).

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

## Current state (2026-06-28)

### opus-4.8 (1M) campaign — COMPLETE; canonical dataset (2026-06)

`results/2026-06-26_103905/` is the **canonical current dataset**: a complete v4
campaign adding `claude-opus-4-8[1m]` (model short `opus48-1m`) at four effort
levels — medium, high, xhigh, and the new **`ultracode`** (xhigh +
dynamic-workflow orchestration; enabled via `CLAUDE_CODE_EFFORT_LEVEL=ultracode`,
since `--effort` does not accept it) — over the same 7 tasks × 5 languages = **140
cells** (136 successful; the 4 failures are xhigh PowerShell-family 30-min
timeouts: 12/powershell-tool, 13/powershell, 16/powershell-tool,
17/powershell-tool). CC versions: 2.1.193 (23 medium cells) + 2.1.195 (117).
Rate-limit clean (0 overloaded/rate-limit/529 markers). ~$578 cells + $17.25 panel
eval (Haiku via Claude CLI; Gemini 3.1 Pro (High) via `agy` = $0 on subscription).
Standard panel-of-judges scores populated; `results/CELLS-COMPLETE.md` marks
collection done. The cross-run report
`results/results_2026-06-26_103905__2026-05-06_173435__2026-04-17_004319__2026-04-09_152435.md`
pools opus-4.8 with the three prior runs and is the headline comparison artifact.
Note: opus-4.8 sometimes picks JavaScript / PowerShell for the free-choice
(default) language, not always Python.

Headline findings (vs opus-4.7 1m, matched task+language): opus-4.8 is the
strongest generation on both quality axes (opus48-1m-ultracode tops Tests
Quality). It is +60–67% time / +64% cost at medium, compressing to ~+15% at high;
writes more and denser tests; the 4 xhigh failures are PowerShell-family timeouts.
**Trap caveat (see `results/analysis/opus48-trap-investigation_2026-06-28.md`):**
opus-4.8 logs ~2× the traps of 4.7, but a hand-review of all 201 occurrences found
this is ~99% benign (99% no circling, 86% legitimate iteration tripping count-based
detectors, ~1% genuine distress) — dominated by a `cd`-prefix dedup measurement
artifact + finer TDD, with a partial CC-version (2.1.131/132 vs 2.1.195) confounder.
Read "~2× traps" as "iterates more granularly," not "fails more often." Follow-up
work tracked in GH issues #21–#27.

### v4 full-matrix benchmark — complete (now a baseline within the combined report)

`results/2026-05-06_173435/`: 280/280 runs across 7 tasks × 5 modes × 8
model-effort combos, $493.46 + $40.57 panel eval = $534.03, 38h 35m wall, 278/280
successful (2 failures). Single-directory, single-CC-version-line (2.1.131 →
2.1.132 mid-run). It was the canonical dataset through 2026-06; it is now pooled
as the **opus-4.7 baseline** inside the opus-4.8 combined report above. Standard
panel-of-judges scores populated.

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

## Deeper references

- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) — read when touching
  `runner.py`, adding a trap detector, or triaging an LLM-vs-structural
  discrepancy in a generated `results.md`.
- [`docs/REPORTING.md`](docs/REPORTING.md) — read when changing
  `combine_results.py`, `judge_audit.py`, `judge_consistency_report.py`,
  or the per-judge prompt addendums, or when porting a per-run report
  section into the combined report.
