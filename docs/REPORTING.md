# Reporting

### Combined-report invariants (`combine_results.py`)

The combined report (e.g. `results/results_<dirA>__<dirB>.md`) pools
runs across multiple source directories. A few layout invariants must
hold — changes here have broken the generated markdown before, so
`tests/test_combine_results.py` guards them:

- **No duplicate `(language, variant_disp)` rows in Tiers or
  Comparison.** `aggregate_rows` groups by `(_disp_mode(language_mode),
  derived_label)` — `_disp_mode` collapses `powershell-tool` into
  `powershell` so the two pool into one column (#30; they are
  replicates in this WSL environment). `derived_label` is
  `<name-version>-<context>-<effort>` built by `_derived_label(m)`
  (name+version from `model_short` with the `-1m`/`-200k` suffix
  stripped and the legacy `opus`/`sonnet`→`opus46`/`sonnet46` rename;
  context from the **recorded** `contextWindow` in
  `model_usage_detail`, NOT the model_short suffix; effort from
  `effort_level` or, when null, `na` for Haiku / `high`-or-`medium`-
  by-CC-version for legacy Opus/Sonnet — see `derive_effort`). This
  grouping is injective per language mode, so the invariant still
  holds. CLI versions pool into one row; `cli_versions` retains the
  per-CLI breakdown for the legend. Because context comes from the
  recorded window, a mislabeled `opus47-200k` cell that actually ran
  at 1M pools into `opus47-1m-medium`, while genuine-200k `opus47`
  cells form a separate `opus47-200k-medium` row.
- **CLI Version Legend schema.** Exactly one CLI version per row.
  Columns: `Variant label | CLI version | Tasks | Languages`. `Tasks`
  and `Languages` each hold either `All` (pair covered every task /
  every language observed in the report) or a comma-sorted subset.
  The plural header `CLI version(s)` and comma-joined version cells
  are the old layout — do not reintroduce.
- **Section order in the body:** Scoring → **Judge Consistency
  Summary** → Judge Audit Outcomes → Tiers → Failed / Timed-Out Runs
  → Comparison → Test Quality Evaluation → Per-Run → Notes. JCS is a
  top-level `##`, not a `### ` under Notes, because readers benefit
  from the panel-health verdict before they consume rankings. (A
  `%%%CONCLUSIONS_SECTION%%%` marker sits between Scoring and JCS but
  always expands to nothing — see "The Conclusions prose is disabled
  for EVERY caller" below.) Only the JCS-above-Tiers half of this
  order is test-guarded today
  (`test_judge_consistency_summary_renders_above_tiers`); the rest is
  convention.
- **Quality-score lookup key.** The per-variant score bucket is keyed
  by `(_disp_mode(language_mode), _derived_label(m))` — the display
  mode + CLI-less derived label, so quality-score pooling matches the
  duration/cost pooling in `aggregate_rows` exactly (including the
  `powershell` + `powershell-tool` collapse). Aggregate lookups therefore use
  `r["variant"]` (the derived label), NOT `r["variant_with_cli"]`.
  (Panel JSONs are still retrieved by the on-disk path
  `(source_run_dir, task_id, original_subdir)` where `original_subdir`
  comes from `_path_label` = RAW model_short + effort — retrieval is
  unaffected; only which aggregate row a score rolls up into changed.)
  Watch for the failure mode where a pooled row's Avg Tests Quality /
  Workflow Craft renders `—` or reflects only one context variant when
  it should be the mean across the whole derived-label pool.

### The Conclusions prose is disabled for EVERY caller

**No report emits `## Conclusions` — not the per-run `results.md`,
not the combined cross-run report.** The merged max-effort Opus
Conclusions call was dropped in `195502a2` (2026-04-24, "drop LLM
Conclusions entirely (#12)") and
`conclusions_report.generate_conclusions_from_inputs` now hard-codes
`out["conclusions"] = None` and discards its `speed_cost_input`
argument (`_ = speed_cost_input`, kept only for call-site compat).
The one LLM call that survives is the Judge Consistency Summary.

This paragraph used to say the block was combined-report-only, which
made the doc read as a scoping decision rather than a removal. It was
wrong for four months: zero of the generated reports under `results/`
contain a `## Conclusions` heading.

Both generators still carry the dead scaffolding — a
`conclusions_block` list and a `%%%CONCLUSIONS_SECTION%%%` marker
(`generate_results.py`, `combine_results.py`). It renders as nothing
(an empty block contributes no lines, so no stray marker leaks into
the markdown), so the scaffolding is harmless, but do not read its
presence as evidence the section is live.

Re-enabling it is therefore NOT a matter of passing
`speed_cost_input` from a call site — the prompt dispatch itself has
to come back in `conclusions_report.py`. Budget for it: the retired
call ran at `SUMMARY_MODEL`/`SUMMARY_EFFORT` (max-effort Opus), on
the order of $1 per regeneration. `tests/test_conclusions_report.py`
pins the current behaviour, so a re-enable will fail that test until
this section is updated with it.

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
| `## Savings Analysis` (Trap / Cache savings) | **Not yet ported.** Depends on per-run `_detect_traps` output + prompt-cache telemetry that aren't currently threaded into `combine_results.py`. Readers needing savings data should drop into the per-run `results.md` for now. |

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

