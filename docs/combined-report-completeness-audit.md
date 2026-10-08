# Combined-report completeness audit

Audit date: October 7, 2026. Part of
[issue #24](https://github.com/Adam-S-Daniel/GHA-bench/issues/24).
Source snapshot: [21916084](https://github.com/Adam-S-Daniel/GHA-bench/tree/21916084b46d945b5213992a69259fe17c367900).

The combined report still omits Savings Analysis and carries Test Quality
Evaluation only partially. The earlier inventory in the
[issue comments](https://github.com/Adam-S-Daniel/GHA-bench/issues/24)
remains accurate on those points. Additional differences include navigation
to version documentation, campaign totals, and judge-summary drill-down links.
This document records findings and decision questions only; it authorizes no
porting, measurement changes, or report regeneration.

## Scope and method

The comparison is between
[generate_results_md](../generate_results.py#L598) and
[_build_markdown](../combine_results.py#L391), with
[REPORTING.md](REPORTING.md#combined-report-parity-with-per-run-reports)
as the documented parity baseline. Python's `ast` parser was used to inspect
literal headings, table headers, dynamic Notes titles, and sorted-table call
sites. Heading and summary tokens in existing Markdown were checked as data.
Conditional headings and disabled scaffolding were then checked against the
code; a literal by itself does not establish that a section renders.

The archived comparison covers nine per-run reports and four combined reports
under [results](../results/). The primary combined artifact is the
[six-source report](../results/results_2026-06-30_191904__2026-07-01_184135__2026-06-26_103905__2026-05-06_173435__2026-04-17_004319__2026-04-09_152435.md).
Its sources are the [June 30](../results/2026-06-30_191904/results.md),
[July 1](../results/2026-07-01_184135/results.md),
[June 26](../results/2026-06-26_103905/results.md),
[May 6](../results/2026-05-06_173435/results.md),
[April 17](../results/2026-04-17_004319/results.md), and
[April 9](../results/2026-04-09_152435/results.md) reports.
Older artifacts are corroboration, not proof that every current conditional
section must appear in every historical report.

The combined generator deliberately retains only the intersection of task IDs
across source directories, as shown in its
[combine function](../combine_results.py#L1170) and Scope notes. Per-run reports
include their whole campaign. Differences in rows, totals, calibrated tier
bands, and narrative findings therefore need not indicate lost report content.

## Section and table inventory

| Per-run content | Combined status | What the reader loses or gains |
|---|---|---|
| Table of Contents | Present | Both index emitted second- and third-level headings. Fourth-level Trap Descriptions, Column Definitions, and Provenance are not separate ToC entries. |
| Scoring and Duration columns | Present, with a deliberate exception | The same quality rubric, ratio calibration, geometric means, timeout censoring, and timeout-cost floors are explained. Combined explicitly discloses that net-of-traps duration is absent. |
| Tiers by Language/Model/Effort | Present | Same six columns, composite weighting, four sorted views, and tier-band notes. Bands are calibrated to each report's own pool. |
| Failed / Timed-Out Runs | Present | Task, Language, Model, Duration, Cost, Reason, Lines, actionlint, and act-result.txt are carried; combined adds Source. Both distinguish recorded cost, a recovered floor, and unavailable cost. |
| Comparison by Language/Model/Effort | Partial | All shared columns remain, but Geo Duration Net of Traps is missing. Combined also omits this table's seven alternate sort views. |
| Savings Analysis | Absent | Entire subtree is missing: the category table, descriptions, definitions, combo table, and prompt-cache table detailed below. |
| Test Quality Evaluation: Structural Metrics | Partial | Same six aggregate columns. The per-cell structural detail table and three alternate aggregate sorts are absent. |
| Test Quality Evaluation: LLM-as-Judge Scores | Partial | Tests Quality preserves the Overall score. Coverage, Rigor, Design, Judge Cost, the judge-cost total, four alternate sorts, and the per-cell dimension/summary table are absent. Combined adds Runs and Workflow Craft. |
| Correlation: Structural Metrics vs Tests Quality | Absent | No Spearman table relating test count, assertion count, and test:code ratio to Coverage, Rigor, Design, and Overall; no paired-sample count or interpretation prose. Per-run emits it only with at least five paired cells. |
| LLM vs Structural Discrepancies | Absent | No probable-counter-gap or qualitative-disagreement tables, flags, or justification text. Per-run emits these only when discrepancies exist. |
| Per-Run Results | Partial, with additions | Task, Language, Model, Duration, Turns, Errors, Cost, and Tests Quality remain. Chosen and Status are missing; combined adds Source and Workflow Craft. Five alternate sorts are absent. |
| Notes: Tiers and CLI Version Legend | Present | Same band explanations and Variant label / CLI version / Tasks / Languages schema. Combined additionally explains Scope and Model label conventions. |
| Judge Consistency Summary | Present, relocated | Per-run places it under Notes; combined promotes it above Tiers and pools source panels. Provenance survives as inline prose, but the per-run full-breakdown link does not. |
| Conclusions | Disabled in both | A heading literal remains in both builders, but the shared producer returns no Conclusions entry. This is not a parity gap. |

Source blocks for the missing tables:
[Comparison](../generate_results.py#L1346),
[Savings Analysis](../generate_results.py#L1378),
[Structural Metrics](../generate_results.py#L1594),
[judge scores](../generate_results.py#L1658),
[correlation and discrepancies](../generate_results.py#L1726), and
[Per-Run Results](../generate_results.py#L1819).
Their combined counterparts are
[Comparison](../combine_results.py#L699),
[Test Quality Evaluation](../combine_results.py#L760), and
[Per-Run Results](../combine_results.py#L820).

## What the missing content means

### Savings and trap analysis

The per-run category table has Trap, Language, Model, Fell In, Time Lost,
% of Time, $ Lost, and % of $. The combo table has Language, Model, Runs,
Traps, Time Lost, % of Time, $ Lost, and % of $. Both tables,
their alternate sorts, and the accompanying detector descriptions and column
definitions are absent from the combined report. The combined reader cannot
attribute detected trap counts or estimated time/cost impact to a category or
combo. The per-run descriptions define Time Lost as an estimate and dollars
lost as a proportional allocation, rather than observed savings.

The missing Geo Duration Net of Traps column is the geometric mean of each
cell's duration minus its detected trap time, using the same duration pool,
including timeouts. It does not feed Duration tiers. Adding it would therefore
add an explanatory comparison without changing tier inputs unless separately
authorized. The missing definition and links to detector descriptions matter
as much as the numbers.

Prompt Cache Savings is a separate Status / Runs / $ Saved / % of $ table with
full-hit, partial, and miss rows. In the
[current collection loop](../generate_results.py#L1142), classification and
savings use only the first assistant usage block per cell, and savings use the
cache-write minus cache-read price. It is not a whole-transcript cache audit.
A port should preserve or explicitly reconsider those semantics, rather than
silently presenting it as total session savings.

Hook Savings is not part of the current per-run generator and is not a gap.
The removed hooks are documented in
[ARCHITECTURE.md](ARCHITECTURE.md#posttooluse-syntax-check-hooks-removed-in-pr-35).
Because combined has neither trap collection nor net-of-traps duration, a
trap-measurement change has no existing combined trap table to update; any new
combined surface is a separate owner decision.

### Quality detail and diagnostic tables

The missing per-cell structural table exposes Tests, Assertions, Assert/Test,
Test Lines, Impl Lines, and Test:Code beside Task, Language, and Model. The
missing per-cell judge table exposes Coverage, Rigor, Design, Overall, and a
summary excerpt (currently truncated to 60 characters). Combined aggregates
cannot show which cell caused a low counter or conflicting judge score.

The
[combined score loader](../combine_results.py#L369) reads audit-aware panel
scores and retains only Overall. The aggregate judge table's prose mentions
Coverage, Rigor, and Design, but those dimensions have no columns. Workflow
Craft is an added Overall score for deliverables, not a replacement for the
missing test dimensions. Per-run also reports summed judge expense and a total
row; combined reports neither.

The two missing diagnostic subsections answer different questions. Correlation
asks whether automated metrics track the rubric across paired cells.
Discrepancies flag individual conflicts, separating probable missing counter
patterns from coherent qualitative disagreements and showing justifications
for the latter. The combined structural introduction says pairing counters
with judges helps surface counter gaps, but only aggregate tables are shown.
It supplies no dedicated discrepancy check. These omissions cannot be inferred
away from the separate Judge Audit Outcomes section, which investigates
contradicted file-existence claims between judges.

### Alternate views

The source contains seven
[_emit_sorted_variants](../generate_results.py#L497) call sites defining up to
28 alternate views, compared with one combined call defining four:

| Table | Per-run sort views | Combined sort views |
|---|---:|---:|
| Tiers | 4 | 4 |
| Comparison | 7 | 0 |
| Trap category table | 3 | 0 |
| Trap combo table | 2 | 0 |
| Structural aggregates | 3 | 0 |
| Judge aggregates | 4 | 0 |
| Per-Run Results | 5 | 0 |
| Total | 28 | 4 |

Thus 24 alternate views are absent when all per-run conditional sections render.
The two per-cell detail collapsibles are additional content, not sorted views;
counting all details blocks would double-count them. Combined already imports
and uses the shared sorter for Tiers, so restoring sorts on existing tables
does not require new telemetry. Trap sorts depend on first deciding whether
their tables belong in combined.

### Header, provenance, and other prose

The per-run
[header](../generate_results.py#L781) reports completed/expected cells,
remaining cells, campaign cost (with a floor marker where needed), and total
agent time. Combined's header identifies source directories and update time;
its Scope notes list retained counts and dropped tasks, but it has no single
pooled cost/time total or campaign-completion line. Per-run also has conditional
remaining-time and estimated-total-cost prose for incomplete campaigns. Those
estimates have no direct combined counterpart because combined has no expected
campaign-size input.

Per-run's version line links each observed CLI version to its system-prompt,
tool-description, and changelog snapshot, with a cell count per version.
Combined's legend lists version values and coverage but does not offer those
snapshot links or that per-version count. Source names and Source cells are
plain text, so the combined reader must navigate manually to the source report.

Per-run's
[judge-summary provenance](../generate_results.py#L1970) identifies the provider,
model, effort, cache status, prompt, token usage, and expense. Combined retains
the same kinds of provenance and adds that panels are pooled. However, it omits
the link to each source's full ranking and disagreement breakdown in
judge-consistency-data.md. Promotion from a third-level heading to a top-level
heading and inline Provenance are layout changes, not lost summary content.

The per-run
[footer](../generate_results.py#L2009) records the observed benchmark instruction
version(s). Combined has no equivalent instruction-version footer. These
provenance and navigation omissions were not captured by the earlier
section/column inventory.

## Documented parity and limits

The six source directories contain 885 files matching the combined loader's
`tasks/*/*/metrics.json` pattern. CLI output and console logs exist beside all
885, and all 885 metrics contain `language_chosen`. Test-quality cache files
exist for 869 cells; deliverable-quality caches exist for 884. These are file
presence counts, not claims that every cache is valid or every score survives
the judge audit. They establish that the savings gap is principally missing
collection/rendering plumbing, not missing event-stream files.

The combined
[metrics loader](../combine_results.py#L37) preserves each cell's directory.
The existing detector, correlation, discrepancy, and sorting helpers in
[generate_results.py](../generate_results.py) are module-level functions;
trap/cache collection and their table builders are still inline in the per-run
builder. Dimensions and diagnostics need a wider combined score loader;
Chosen/Status need row formatting; provenance links need source-aware paths.
None requires a new benchmark campaign. Availability does not decide whether
an item belongs in the combined report.

The parity claims in
[REPORTING.md](REPORTING.md#combined-report-parity-with-per-run-reports),
referenced by [AGENTS.md](../AGENTS.md#combined-report-parity-with-per-run-reports),
still hold: failures are ported, test quality is partial, savings are unported.
The Conclusions and section-order corrections from
[merged PR #58](https://github.com/Adam-S-Daniel/GHA-bench/pull/58) are present;
the former stale claims do not need another fix. The parity table remains a
summary rather than an exhaustive list of columns, alternate views, or prose.

Combined-only Judge Audit Outcomes, Scope, Model label conventions, Source
columns, and the no-common-tasks error path are additions, not per-run omissions.
Both generators explain the quality axes and timeout-cost treatment. Neither
shows a deliverable-dimension detail table, so that would be new behavior beyond
this parity request.

This audit did not run benchmark cells, providers, detector timing trials,
paid judges, or either report generator. It makes no fresh runtime estimate
for trap porting and does not reuse the earlier audit's timing as a current
measurement. Archived report timestamps and cached narratives are preserved.

## Decisions requested from the owner

No decisions below have been made. For each item, should it be ported, retained
as a documented omission, or deferred?

1. Trap category/combo tables, definitions, and Geo Duration Net of Traps.
2. Prompt Cache Savings, independently or together with trap analysis.
3. Coverage/Rigor/Design columns, Judge Cost, and its total row.
4. Per-cell structural detail and per-cell judge dimensions/summary excerpts.
5. Correlation and its interpretation/sample-size prose.
6. Counter-gap and qualitative-disagreement tables with flags/justifications.
7. Alternate sorts on existing combined tables; trap sorts if item 1 proceeds.
8. Chosen and Status columns, decided separately.
9. Pooled cost/time totals; incomplete-campaign progress and estimates separately.
10. CLI snapshot links/version counts, source-report links, instruction-version
    provenance, and judge full-breakdown links, decided separately.

Any approved port should follow the
[shared-builder rule](REPORTING.md#combined-report-parity-with-per-run-reports):
extract the existing per-run section builder for reuse instead of duplicating
it. The factual audit is complete; implementation and issue closure remain
pending the owner's decisions.
