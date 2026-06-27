#!/usr/bin/env python3
"""Generate results.md from benchmark metrics.

Can be run standalone to regenerate results.md for any run directory,
or imported by runner.py during benchmark execution.

Usage:
    python3 generate_results.py [results-dir]
    python3 generate_results.py results/2026-04-08_192624
    python3 generate_results.py --all          # regenerate all runs
    python3 generate_results.py --update-readme # update README.md run index
"""

import json
import os
import re
import sys
from collections import Counter, defaultdict
from datetime import datetime
from pathlib import Path

from models import COST_PER_MTOK, MODELS  # noqa: E402  (single source of truth)

INSTRUCTIONS_VERSION = "v4"


def _find_discrepancies(llm_rows: list[dict], tq_lookup: dict) -> list[dict]:
    """Find discrepancies between LLM judge scores and structural metrics.

    Each discrepancy is classified as:
    - "counter-gap": structural metrics are implausibly low (e.g. 0 tests or
      0 assertions despite high LLM scores). Likely a missing pattern in
      test_quality.py — should be investigated and fixed.
    - "qualitative": structural metrics look reasonable but the LLM disagrees
      on quality. The LLM is judging aspects (edge cases, test isolation,
      error paths) that raw counts can't measure. The LLM's summary is
      included as justification.

    Returns list of dicts with keys: task, mode, model, tests, asserts,
    cov, rig, des, ovr, flag, kind, justification.
    """
    discrepancies = []
    for lr in llm_rows:
        key = (lr["task"], lr["mode"], lr["model"])
        sq = tq_lookup.get(key)
        if not sq:
            continue

        tests = sq["tests"]
        asserts = sq["asserts"]
        ratio = sq["ratio"]
        summary = lr.get("summary", "")

        def _add(flag: str, kind: str):
            discrepancies.append({
                "task": lr["task"], "mode": lr["mode"], "model": lr["model"],
                "tests": tests, "asserts": asserts, "ratio": ratio,
                "cov": lr["coverage"], "rig": lr["rigor"],
                "des": lr["design"], "ovr": lr["overall"],
                "flag": flag, "kind": kind,
                "justification": summary if kind == "qualitative" else "",
            })

        # --- Counter-gap signals: structural metrics implausibly low ---

        # High LLM coverage but very few tests
        if lr["coverage"] >= 4 and tests <= 3:
            _add(f"LLM says high coverage ({lr['coverage']}/5) but only {tests} tests detected",
                 "counter-gap" if tests == 0 else "qualitative")

        # High LLM rigor but few assertions
        if lr["rigor"] >= 4 and asserts <= 5:
            _add(f"LLM says high rigor ({lr['rigor']}/5) but only {asserts} assertions detected",
                 "counter-gap" if asserts == 0 else "qualitative")

        # High LLM overall but no tests
        if lr["overall"] >= 4 and tests == 0:
            _add(f"LLM says high overall ({lr['overall']}/5) but 0 tests detected",
                 "counter-gap")

        # High LLM overall but zero assertions per test
        if lr["overall"] >= 4 and tests > 0 and asserts == 0:
            _add(f"LLM says high overall ({lr['overall']}/5) but 0 assertions detected",
                 "counter-gap")

        # High LLM overall but very low assertion density (non-zero)
        if lr["overall"] >= 4 and tests > 0 and 0 < asserts / tests < 0.5:
            _add(f"LLM says high overall ({lr['overall']}/5) but only {asserts/tests:.1f} assertions/test",
                 "qualitative")

        # --- Qualitative signals: metrics look reasonable, LLM disagrees ---

        # Low LLM coverage but many tests
        if lr["coverage"] <= 2 and tests >= 20:
            _add(f"LLM says low coverage ({lr['coverage']}/5) but {tests} tests detected",
                 "qualitative")

        # Low LLM rigor but many assertions
        if lr["rigor"] <= 2 and asserts >= 40:
            _add(f"LLM says low rigor ({lr['rigor']}/5) but {asserts} assertions detected",
                 "qualitative")

        # Low LLM design but high test-to-code ratio
        if lr["design"] <= 2 and ratio >= 2.0:
            _add(f"LLM says poor design ({lr['design']}/5) but test:code ratio is {ratio:.1f}",
                 "qualitative")

    return discrepancies


def _detect_traps(events: list[dict], console: str, metrics: dict) -> list[dict]:
    """Detect time-costly debugging traps from a run's event stream.

    Returns list of {"name": str, "time_s": float, "desc": str} dicts for
    traps that wasted ≥15 seconds.

    ADDING NEW TRAPS
    ================
    When you discover a new recurring pattern that costs agents ≥15 seconds,
    add a numbered block below following the existing pattern:

    1. Give the trap a kebab-case name (e.g. "yaml-indent-errors").
    2. Write detection logic that examines bash_cmds, all_text (agent's
       reasoning), console (tool output), and/or metrics (hook counts, etc.).
    3. Estimate time_s — use the number of wasted commands × a per-command
       cost.  For Bash commands, 15-25s is typical (API turn + execution).
       For act push, use 50s.  For pwsh Pester, use 25-35s.
    4. Call _add(name, time_s, description_string).
    5. If the trap only applies to a specific mode, guard with
       `if mode == "..."`.  Otherwise it is tested on all runs.
    6. If the trap applies to a specific mode, add it to the trap_mode dict
       inside generate_results_md (search for "trap_mode") so the
       "applicable runs" denominator is correct.  Default is "all".

    To find new trap candidates: look at the slowest or highest-error runs
    in results.md, read their console-log.txt for repeated patterns or long
    debugging sequences, then generalise into a detection rule.
    """
    mode = metrics.get("language_mode", "")
    bash_cmds: list[str] = []
    texts: list[str] = []
    for e in events:
        if e.get("type") == "assistant":
            for c in e.get("message", {}).get("content", []):
                if isinstance(c, dict):
                    if c.get("type") == "tool_use" and c.get("name") == "Bash":
                        bash_cmds.append(c.get("input", {}).get("command", ""))
                    elif c.get("type") == "text":
                        texts.append(c.get("text", ""))
    all_text = "\n".join(texts)
    traps: list[dict] = []

    def _add(name, t, desc):
        if t >= 15:
            traps.append({"name": name, "time_s": t, "desc": desc})

    # 1. Pester CmdletBinding parameter binding spiral
    if mode in ("powershell", "powershell-tool"):
        diag = [c for c in bash_cmds if re.search(r"/tmp/test_\w+\.(?:ps1|Tests\.ps1)", c)]
        if len(diag) >= 2:
            _add("pester-cmdletbinding-spiral", len(diag) * 25,
                 f"{len(diag)} /tmp/test_*.ps1 diagnostic scripts bisecting Pester parameter binding")

    # 2. Wrong Pester assertion names
    if mode in ("powershell", "powershell-tool"):
        wrong = [n for n, p in [("BeInRange", r"Should\s+-BeInRange"),
                                 ("BeGreaterOrEqualTo", r"Should\s+-BeGreaterOrEqualTo"),
                                 ("BeLessOrEqualTo", r"Should\s+-BeLessOrEqualTo")]
                 if re.search(p, "\n".join(bash_cmds) + all_text)]
        if wrong and re.search(r"fix|correct|wrong|not.*valid|doesn.t exist", all_text, re.I):
            _add("pester-wrong-assertions", 45, f"Used nonexistent assertions: {', '.join(wrong)}")

    # 3. Docker PowerShell install exploration
    if mode in ("powershell", "powershell-tool"):
        dp = [c for c in bash_cmds if re.search(r"docker\s+run.*(?:powershell|pwsh|microsoft-prod)", c, re.I)]
        if len(dp) >= 2:
            _add("docker-pwsh-install", len(dp) * 45, f"{len(dp)} Docker runs exploring pwsh install")

    # 4. Module restructure mid-run
    if mode in ("powershell", "powershell-tool"):
        if (re.search(r"restructur|separate.*into.*module|\.psm1.*fix", all_text, re.I)
                and any(".psm1" in c for c in bash_cmds)):
            _add("mid-run-module-restructure", 120, "Restructured to .psm1 module mid-run")

    # 5. act push debug loops (>2 invocations)
    act_pushes = [c for c in bash_cmds if re.search(r"\bact\s+push", c)]
    if len(act_pushes) > 2:
        extra = len(act_pushes) - 2
        act_times = [t["duration_ms"] for t in metrics.get("tool_use_timing", {}).get("slowest_tool_uses", [])
                     if re.search(r"\bact\s+push", t.get("command", ""))]
        t = extra * (sum(act_times) / len(act_times) / 1000 if act_times else 50)
        _add("act-push-debug-loops", t, f"{len(act_pushes)} act push invocations ({extra} extra)")

    # 6. TypeScript type error fix cycles
    if mode == "typescript-bun":
        he = metrics.get("hooks", {}).get("hook_errors_caught", 0)
        if he >= 2:
            _add("ts-type-error-fix-cycles", he * 12, f"{he} type errors caught by hooks")

    # 7. Docker package install exploration (non-pwsh)
    dpkg = [c for c in bash_cmds if re.search(r"docker\s+run.*(?:pip\s+install|apt-get\s+install)", c, re.I)
            and not re.search(r"powershell|pwsh", c, re.I)]
    if len(dpkg) >= 2:
        _add("docker-pkg-install", len(dpkg) * 30, f"{len(dpkg)} Docker runs exploring package install")

    # 8. bats-core setup confusion
    if mode == "bash":
        bs = [c for c in bash_cmds if re.search(r"which bats|npm.*bats|install.*bats|load.*test_helper", c, re.I)]
        be = len(re.findall(r"bats.*not found|load.*error|helper.*not|cannot.*load", console, re.I))
        if len(bs) >= 3 and be >= 1:
            _add("bats-setup-issues", len(bs) * 15, f"{len(bs)} commands debugging bats setup")

    # 9. Fixture rework
    # Use word-boundary patterns to avoid matching filenames like "test_database"
    fc = [c for c in bash_cmds if re.search(
        r"fixture|sample[_\-\s]data|mock[_\-\s]data|test[_\-\s]data\b", c, re.I)]
    if len(fc) >= 4:
        _add("fixture-rework", (len(fc) - 2) * 15, f"{len(fc)} commands creating/fixing fixtures")

    # 10. Repeated identical test reruns
    cmd_cnt: dict[str, int] = {}
    for c in bash_cmds:
        if re.search(r"pytest|Invoke-Pester|bun\s+test|bats\s+|dotnet\s+test|unittest\b", c):
            key = re.sub(r"\s+2>&1.*|\s+\|.*", "", c)[:80]
            cmd_cnt[key] = cmd_cnt.get(key, 0) + 1
    for cmd, count in cmd_cnt.items():
        if count >= 4:
            _add("repeated-test-reruns", (count - 2) * 20, f"Same test run {count} times")

    # 11. actionlint fix cycles
    ar = [c for c in bash_cmds if "actionlint" in c]
    af = len(re.findall(r"actionlint.*error", console, re.I))
    if len(ar) >= 3 and af >= 2:
        _add("actionlint-fix-cycles", af * 20, f"{len(ar)} actionlint runs, {af} failures")

    # 12. Permission/path errors in act container
    # Only check when act was actually used in this run
    used_act = any(re.search(r"\bact\s+(push|run|pull)\b", c) for c in bash_cmds)
    if used_act:
        # Look for errors that specifically indicate act container issues, not general chmod/ENOENT
        pe = len(re.findall(
            r"Permission denied.*/home/runner|ENOENT.*/home/runner|"
            r"chmod\s+\+x.*&&.*act\b|"
            r"\bact\b.*not found|No such file.*\.github/workflows",
            console, re.I))
        if pe >= 2:
            _add("act-permission-path-errors", pe * 15, f"{pe} permission/path errors in act container")

    # 13. act fixture path issues
    if used_act and (re.search(r"Config file not found|fixture.*not found|No such file.*fixture", console, re.I)
            and re.search(r"fixture.*path|copy.*fixture|missing.*fixture", all_text, re.I)):
        _add("act-fixture-paths", 60, "Fixtures not found inside act Docker container")

    # 14. Permission denial retry loops (v1 harness issue — sandbox blocked commands)
    denial_count = len(re.findall(
        r"\[Result ERROR\].*(?:requires approval|haven't granted it yet|was blocked)", console))
    if denial_count >= 5:
        _add("permission-denial-loops", denial_count * 10,
             f"{denial_count} commands blocked by CLI sandbox (permission denials)")

    # 15. Dotnet SDK install loop (csharp-script agents stuck installing .NET)
    if mode == "csharp-script":
        dotnet_cmds = [c for c in bash_cmds if re.search(
            r"dotnet-install|dot\.net/v1|Install-DotNet|dotnet\s+--version", c, re.I)]
        dotnet_denials = len(re.findall(
            r"dotnet.*requires approval|dotnet.*Permission denied", console, re.I))
        total = len(dotnet_cmds) + dotnet_denials
        if total >= 5:
            _add("dotnet-install-loop", total * 12,
                 f"{total} attempts to install/verify .NET SDK")

    # 16. PowerShell invoked from bash instead of shell: pwsh
    # When agents use `pwsh -Command "..."` or `pwsh -File` inside bash run: steps,
    # they can hit: (a) bash parser errors from PS syntax (e.g. @'...'@ heredocs),
    # (b) variable/quoting issues passing structured data through bash to pwsh,
    # (c) scope/invocation issues requiring diagnostic scripts.
    # shell: pwsh works fine in act containers (act translates to docker exec pwsh),
    # but agents that invoke pwsh from bash waste time on cross-shell debugging.
    if mode in ("powershell", "powershell-tool"):
        # Signal 1: /tmp/scope_test*.ps1 diagnostic scripts (bisecting pwsh invocation)
        scope_scripts = [c for c in bash_cmds if re.search(
            r"/tmp/scope_test\d*\.ps1|/tmp/pwsh_debug\d*\.ps1", c)]
        # Signal 2: bash parser errors from PS syntax inside bash
        ps_in_bash_errors = len(re.findall(
            r"Unrecognized token in source text", console))
        # Signal 3: pwsh command not found inside act container (late discovery)
        pwsh_not_found_act = len(re.findall(
            r"line \d+: pwsh: command not found|"
            r"exec:.*pwsh.*executable file not found",
            console, re.I))
        # Signal 4: agent reasoning about quoting/escaping between bash and pwsh
        quoting_issues = len(re.findall(
            r"(?:quot|escap).*(?:bash.*pwsh|pwsh.*bash|variable.*pass)|"
            r"output isn.t visible.*(?:pwsh|PowerShell|JSON)|"
            r"(?:pwsh|PowerShell).*(?:quoting|embedded quotes)",
            all_text, re.I))
        # Signal 5: pwsh -Command invocations used as diagnostic probes (not normal script runs)
        pwsh_diag = [c for c in bash_cmds if re.search(
            r"pwsh\s+-Command.*(?:MyInvocation|ScriptName|InvocationName|Write-Host.*test|scope|param\b)",
            c, re.I)]
        total_signals = (len(scope_scripts) + ps_in_bash_errors + pwsh_not_found_act
                         + (1 if quoting_issues >= 1 else 0) + len(pwsh_diag))
        if total_signals >= 2:
            parts = []
            if scope_scripts:
                parts.append(f"{len(scope_scripts)} scope-test scripts")
            if ps_in_bash_errors:
                parts.append(f"{ps_in_bash_errors} bash parser errors from PS syntax")
            if pwsh_not_found_act:
                parts.append(f"{pwsh_not_found_act} pwsh-not-found in act")
            if quoting_issues:
                parts.append(f"{quoting_issues} quoting issue mentions")
            if pwsh_diag:
                parts.append(f"{len(pwsh_diag)} diagnostic pwsh probes")
            # Time estimate: scope scripts ~25s each (write + run + analyze),
            # parse errors ~30s each (error + investigate + fix),
            # not-found ~45s (act run + error + workflow rewrite),
            # quoting ~60s (investigate + rewrite workflow),
            # diagnostic probes ~20s each
            t = (len(scope_scripts) * 25 + ps_in_bash_errors * 30
                 + pwsh_not_found_act * 45 + quoting_issues * 60
                 + len(pwsh_diag) * 20)
            _add("pwsh-invoked-from-bash", t, "; ".join(parts))

    return traps



def _categorize_tool_time(tool_uses: list[dict]) -> dict:
    """Categorize Bash tool use durations into install, test, and act buckets."""
    install_ms = 0
    test_ms = 0
    act_ms = 0
    install_patterns = [
        r"docker\s+run.*(?:install|apt-get|wget|dpkg|curl.*download)",
        r"apt-get\s+(?:update|install)",
        r"pip3?\s+install",
        r"npm\s+install",
        r"Install-Module",
        r"dotnet\s+tool\s+install",
    ]
    test_patterns = [
        r"Invoke-Pester",
        r"pytest|python3?\s+-m\s+pytest",
        r"\bbats\b",
        r"bun\s+test",
        r"bun\s+run\s+\S*test",       # bun run run-act-tests.ts, etc.
        r"pwsh\s+.*Tests?\.ps1",
        r"run[-_](?:act[-_])?tests",   # run-tests, run_tests, run-act-tests
        r"test_harness",
        r"python3?\s+\S*test\S*\.py",  # python3 test_foo.py, python3 run_tests.py
        r"bash\s+\S*test\S*\.sh",      # bash run-act-tests.sh, bash test_foo.sh
        r"pwsh\s+\S*[Tt]est\S*\.ps1",  # pwsh Run-Tests.ps1, pwsh Test-Workflow.ps1
    ]
    act_patterns = [
        r"\bact\s+(?:push|pull_request)",
    ]
    for t in tool_uses:
        if t.get("tool_name") != "Bash":
            continue
        cmd = t.get("command", "")
        dur = t["duration_ms"]
        if any(re.search(p, cmd, re.IGNORECASE) for p in act_patterns):
            act_ms += dur
        elif any(re.search(p, cmd, re.IGNORECASE) for p in test_patterns):
            test_ms += dur
        elif any(re.search(p, cmd, re.IGNORECASE) for p in install_patterns):
            install_ms += dur
    return {
        "install_duration_ms": install_ms,
        "test_duration_ms": test_ms,
        "act_duration_ms": act_ms,
    }



def _collapsible_table(summary: str, header: str, separator: str, rows: list[str]) -> list[str]:
    """Wrap a markdown table in a <details> block."""
    out = ["", "<details>", f"<summary>{summary}</summary>", ""]
    out.append(header)
    out.append(separator)
    out.extend(rows)
    out.append("")
    out.append("</details>")
    return out


def _rank(values):
    """Assign ranks to values (average rank for ties)."""
    indexed = sorted(enumerate(values), key=lambda x: x[1])
    ranks = [0.0] * len(values)
    i = 0
    while i < len(indexed):
        j = i
        while j < len(indexed) and indexed[j][1] == indexed[i][1]:
            j += 1
        avg_rank = (i + j + 1) / 2  # 1-based average rank
        for k in range(i, j):
            ranks[indexed[k][0]] = avg_rank
        i = j
    return ranks


def _spearman(xs, ys):
    """Compute Spearman rank correlation coefficient."""
    if len(xs) < 3:
        return None
    rx, ry = _rank(xs), _rank(ys)
    n = len(xs)
    mean_rx = sum(rx) / n
    mean_ry = sum(ry) / n
    num = sum((a - mean_rx) * (b - mean_ry) for a, b in zip(rx, ry))
    den_x = sum((a - mean_rx) ** 2 for a in rx) ** 0.5
    den_y = sum((b - mean_ry) ** 2 for b in ry) ** 0.5
    if den_x == 0 or den_y == 0:
        return None
    return round(num / (den_x * den_y), 2)



def _emit_sorted_variants(header: str, separator: str, data_rows: list[dict],
                           sort_specs: list[tuple[str, object, bool]],
                           row_formatter) -> list[str]:
    """Emit multiple collapsed copies of a table, each sorted differently.

    sort_specs: list of (summary_label, sort_key, reverse). `sort_key` is
    either a dict-key string (lookup + numeric/string fallback) or a
    callable(row_dict)->sort_key for compound / computed orderings.
    row_formatter: callable(row_dict) -> markdown row string.
    """
    out: list[str] = []
    for label, key, reverse in sort_specs:
        if callable(key):
            sorted_rows = sorted(data_rows, key=key, reverse=reverse)
        else:
            sorted_rows = sorted(data_rows, key=lambda r: (r.get(key, 0) if isinstance(r.get(key, 0), (int, float)) else str(r.get(key, ""))), reverse=reverse)
        row_strs = [row_formatter(r) for r in sorted_rows]
        out.extend(_collapsible_table(label, header, separator, row_strs))
    return out


# Tier letters mapped to numeric positions for compound sort keys.
# "—" (em-dash, no data) gets the highest value so no-data rows sink
# to the bottom when sorting ascending/A-first.
# 13-tier grade scheme: A+ (best) → F (worst), with "—" as no-data sentinel.
# Ordered numerically so lower numbers are better, identical to academic grades.
_TIER_LETTERS: tuple[str, ...] = (
    "A+", "A", "A-",
    "B+", "B", "B-",
    "C+", "C", "C-",
    "D+", "D", "D-",
    "F",
)
_TIER_RANK = {letter: i + 1 for i, letter in enumerate(_TIER_LETTERS)}
_TIER_RANK["—"] = len(_TIER_LETTERS) + 1  # no-data sorts after F
_N_TIERS = len(_TIER_LETTERS)  # = 13


def _tier_num(tier: str) -> int:
    """Return the numeric position of a tier letter (A+=1 ... F=13; —=14)."""
    return _TIER_RANK.get(tier, _N_TIERS + 1)


# ── Tier binning: groups close values into bands so tables can answer
# "is 1st tightly clustered with the rest, or a runaway?" at a glance.
# Ratio-based for lower-is-better axes (duration, cost); absolute-band
# for LLM score since its 1-5 scale makes ratios meaningless.
def _compute_ratio_bands(ratios: list[float]) -> tuple[float, ...]:
    """Return 12 band boundaries (b1..b12) such that tier[i] applies when
    ratio ≤ b[i] and F = > b12. Boundaries are log-equal divisions of the
    best-to-worst spread so they auto-calibrate: tight clusters get narrow
    bands (everything ~A+); wide spreads get wide bands (A+..D-, with F
    reserved for ratios exceeding the observed max).

    For best ratio 1.0 and max M, boundary i is M^(i/12), so the worst
    observed value (r == M) satisfies `r <= b12 = M` and lands in D-;
    anything beyond M would fall to F.
    """
    n_bands = _N_TIERS - 1  # 12 boundaries for 13 tiers
    if not ratios:
        return tuple(1.0 for _ in range(n_bands))
    max_r = max(ratios)
    if max_r <= 1.0:
        return tuple(1.0 for _ in range(n_bands))
    return tuple(max_r ** (i / n_bands) for i in range(1, n_bands + 1))


def _ratio_tier(ratio: float, bands: tuple[float, ...] | None = None) -> str:
    """Return tier letter A+..F for a ratio where 1.0 is best.

    `bands` must have len == _N_TIERS - 1 (=12). When None, falls back to
    a fixed spread that keeps agent-benchmark ratios (Haiku→Opus-xhigh
    is ~7x on cost) mostly within the letter grades; ratios beyond the
    spread top fall to F.
    """
    if bands is None:
        # Fallback: boundary 12 at ratio ~8 (~= observed worst campaign
        # spread) so a typical dataset maps sanely even before
        # _compute_ratio_bands is called with real data.
        n_bands = _N_TIERS - 1  # 12
        max_r = 8.0
        bands = tuple(max_r ** (i / n_bands) for i in range(1, n_bands + 1))
    for letter, b in zip(_TIER_LETTERS[:-1], bands):
        if ratio <= b:
            return letter
    return _TIER_LETTERS[-1]  # "F"


def _llm_tier(score: float) -> str:
    """Return tier letter A+..F for an LLM judge Overall score (1-5 scale).
    Step is 0.3 points; top boundary 4.7, bottom boundary 1.4. Score 3.5
    (between B and B-) maps to B, matching intuitive "slightly above
    average" grading."""
    thresholds = [4.7, 4.4, 4.1, 3.8, 3.5, 3.2, 2.9, 2.6, 2.3, 2.0, 1.7, 1.4]
    for letter, t in zip(_TIER_LETTERS[:-1], thresholds):
        if score >= t:
            return letter
    return _TIER_LETTERS[-1]  # "F"



def generate_results_md(run_dir, all_metrics, total_runs, run_count):
    """Generate/update a results.md file with tables, commentary, and status."""
    from zoneinfo import ZoneInfo
    from pathlib import Path
    import json, re
    from collections import defaultdict

    et = ZoneInfo("America/New_York")
    now_et = datetime.now(et).strftime("%Y-%m-%d %I:%M:%S %p ET")

    completed = len(all_metrics)
    # Remaining is derived from cumulative completion vs the declared total so
    # the line stays self-consistent even when a resumed run inherits prior
    # metrics (which make `completed` exceed the per-invocation `run_count`).
    remaining = max(0, total_runs - completed)

    total_cost = sum(m["cost"]["total_cost_usd"] for m in all_metrics)
    total_duration = sum(m["timing"]["grand_total_duration_ms"] for m in all_metrics) / 1000

    # We build the body into `lines` and emit a Table of Contents at the
    # very top once all section headings are known. `_TOC_MARKER` reserves
    # the slot; we substitute it at write time.
    _TOC_MARKER = "%%%TABLE_OF_CONTENTS%%%"
    # Notes deferred to the bottom: tier-band explanations, scoring rubric
    # anchors, CLI-version legend. Any caller that would have emitted an
    # above-table prose block now appends to `notes_sections` instead so
    # the body stays scannable.
    notes_sections: list[tuple[str, list[str]]] = []

    # Conclusions section (LLM-generated) is populated AFTER cmp_rows
    # exist and judge-consistency-data.md has been (re)built, then
    # substituted into this marker at write time.
    _CONCLUSIONS_MARKER = "%%%CONCLUSIONS_SECTION%%%"
    # Scoring section sits between ToC and Conclusions. Built after
    # ratio bands are computed (they populate the "Properties" bullets
    # for Duration/Cost), then substituted into this slot.
    _SCORING_MARKER = "%%%SCORING_SECTION%%%"

    lines = []
    lines.append("# Benchmark Results: Language Comparison")
    lines.append("")
    # Status inlined with "Last updated:" — no separate Status section.
    lines.append(
        f"**Last updated:** {now_et} — {completed}/{total_runs} runs "
        f"completed, {remaining} remaining; total cost "
        f"${total_cost:.2f}; total agent time "
        f"{total_duration/60:.1f} min."
    )
    # Claude Code versions used in this run, with links to per-version
    # reference docs (system prompt + tool descriptions + slice of the
    # Anthropic changelog) generated by `version_docs.py`. Surfaced
    # immediately under the header so readers can resolve any
    # version-specific behaviour question without scrolling.
    cc_versions = Counter(
        m.get("claude_code_version", "") for m in all_metrics
        if m.get("claude_code_version")
    )
    if cc_versions:
        ver_links = []
        for ver, n in sorted(cc_versions.items(), key=lambda kv: tuple(int(x) for x in kv[0].split("."))):
            doc_path = run_dir / f"claude-code-{ver}.md"
            label = f"v{ver}"
            link = f"[{label}](claude-code-{ver}.md)" if doc_path.exists() else label
            ver_links.append(f"{link} ({n} run{'s' if n != 1 else ''})")
        lines.append(
            f"**Claude Code versions used:** {', '.join(ver_links)}. "
            "Each link goes to a per-version snapshot of the system prompt, "
            "default-tool descriptions, and the chronological Anthropic "
            "changelog up to that version. Regenerate with "
            "`python3 version_docs.py`."
        )
    lines.append("")
    lines.append(_TOC_MARKER)
    # Scoring section sits directly under the ToC so readers see the
    # rubric before the Conclusions interpret it.
    lines.append(_SCORING_MARKER)
    # Conclusions slot — filled at write time if the LLM calls succeed.
    lines.append(_CONCLUSIONS_MARKER)

    if not all_metrics:
        lines.append("")
        lines.append("*No completed runs yet.*")
        text = "\n".join(lines).replace(_TOC_MARKER, "")
        (run_dir / "results.md").write_text(text)
        return

    # Separate successful and failed runs
    successful = [m for m in all_metrics if m.get("run_success", m.get("exit_code", 0) == 0 and m.get("timing", {}).get("num_turns", 0) > 0)]
    failed = [m for m in all_metrics if m not in successful]

    # Pre-effort-flag runs (v1-v4) used `opus`/`sonnet` as short names in
    # the CLI, which today resolve to different models across providers.
    # Rename them in DISPLAY so readers of the merged report know which
    # concrete version was tested (Opus 4.6 / Sonnet 4.6 on this repo's
    # history) and at what context window. Filesystem subdirs keep their
    # original plain name.
    _DISPLAY_RENAME = {
        "opus": "opus46-200k",
        "sonnet": "sonnet46-200k",
        "haiku45": "haiku45-200k",
    }

    def _cli_suffix(m):
        """Format the CLI version as a `-cli<ver>` label suffix. Different
        CLI releases are tracked as distinct buckets — CLI behavior changes
        per release, so we don't want to silently average across them."""
        ver = m.get("claude_code_version") or ""
        return f"-cli{ver}" if ver else "-cliunk"

    def _path_label(m):
        """On-disk subdir label: exactly matches directories already on
        the filesystem. No rename here, and no CLI version — existing
        subdirs were written without either and migrating would rename
        every prior run's directory on disk."""
        eff = m.get("effort_level")
        return f"{m['model_short']}-{eff}" if eff else m["model_short"]

    def _label(m):
        """Internal grouping label — includes `-cli<ver>` so distinct
        Claude Code releases bucket separately. Used as a dict key for
        aggregation. NOT for display; use `_strip_cli(_label(m))` when
        rendering to tables/prose — the CLI Version Legend in Notes is
        the canonical mapping from label → CLI version."""
        eff = m.get("effort_level")
        short = _DISPLAY_RENAME.get(m["model_short"], m["model_short"])
        base = f"{short}-{eff}" if eff else short
        return base + _cli_suffix(m)

    _CLI_SUFFIX_RE = re.compile(r"-cli[^-\s*]+$")

    def _strip_cli(s: str) -> str:
        """Strip `-cli<ver>` from a display label. Preserves a trailing
        `*` (excluded-runs marker) if present."""
        had_star = s.endswith("*")
        core = s[:-1] if had_star else s
        core = _CLI_SUFFIX_RE.sub("", core)
        return core + ("*" if had_star else "")

    modes_seen = sorted(set(m["language_mode"] for m in all_metrics))
    models_seen = sorted(set(_label(m) for m in all_metrics))
    # Map variant label -> plain model_short for pricing lookups (keyed by
    # COST_PER_MTOK, which indexes on model_short only).
    _label_to_model_short = {_label(m): m["model_short"] for m in all_metrics}

    # ── Helper: format duration as minutes ──
    def _dur(seconds):
        return f"{seconds/60:.1f}min"

    # ==================================================================
    # COLLECT ALL ANALYSIS DATA UP FRONT
    # ==================================================================

    # ── Panel-of-judges score cache ──
    # Both the test-quality judge and the deliverable-quality judge can
    # now have multiple judges contributing per run (e.g. Haiku + Gemini).
    # load_panel_scores reads every `{kind}-*.json` under a variant subdir
    # and returns a panel-averaged dict (coverage/rigor/design/overall
    # for test-quality; best_practices/.../overall for deliverable), plus
    # n_judges, judges, and total judge_cost_usd. Legacy Sonnet-era
    # `{kind}-llm.json` files are picked up too for back-compat.
    from test_quality import load_panel_scores
    llm_data_by_key: dict[tuple, dict] = {}
    deliv_data_by_key: dict[tuple, dict] = {}
    for m in all_metrics:
        variant_subdir = run_dir / "tasks" / m["task_id"] / f"{m['language_mode']}-{_path_label(m)}"
        key = (m["task_id"], m["language_mode"], _label(m))
        lj_panel = load_panel_scores(variant_subdir, "test-quality")
        if lj_panel is not None:
            llm_data_by_key[key] = lj_panel
        dj_panel = load_panel_scores(variant_subdir, "deliverable-quality")
        if dj_panel is not None:
            deliv_data_by_key[key] = dj_panel

    # ── Comparison by Language/Model/Effort ──
    # Track how many failed runs each (mode, model) combo excluded from
    # aggregates. An asterisk on the row's Model cell + a footnote makes
    # that exclusion visible at every table that renders the aggregates.
    excluded_by_combo: dict[tuple, int] = {}
    for m in failed:
        excluded_by_combo[(m["language_mode"], _label(m))] = (
            excluded_by_combo.get((m["language_mode"], _label(m)), 0) + 1
        )
    cmp_rows = []
    for mode in modes_seen:
        for model in models_seen:
            mm = [m for m in successful if m["language_mode"] == mode and _label(m) == model]
            n = len(mm)
            if n == 0:
                continue
            # Average LLM-judge Overall across this combo's runs that have a
            # cached score. Stored as 0.0 for sort purposes + a separate
            # display string so missing data doesn't sort above zero scores.
            llm_scores = [llm_data_by_key[(m["task_id"], mode, model)].get("overall")
                          for m in mm
                          if (m["task_id"], mode, model) in llm_data_by_key]
            llm_scores = [s for s in llm_scores if isinstance(s, (int, float))]
            avg_llm = sum(llm_scores) / len(llm_scores) if llm_scores else None
            # Same treatment for the deliverable-quality judge (scores the
            # produced workflows + scripts, not the test code).
            deliv_scores = [deliv_data_by_key[(m["task_id"], mode, model)].get("overall")
                            for m in mm
                            if (m["task_id"], mode, model) in deliv_data_by_key]
            deliv_scores = [s for s in deliv_scores if isinstance(s, (int, float))]
            avg_deliv = sum(deliv_scores) / len(deliv_scores) if deliv_scores else None
            excl = excluded_by_combo.get((mode, model), 0)
            cmp_rows.append({
                "mode": mode, "model": model,
                # Plain model string; Model column display appends an
                # asterisk in the row formatters when excluded > 0.
                "excluded": excl,
                # `model_disp` drops the `-cli<ver>` so rendered tables
                # stay compact; the CLI Version Legend in Notes maps
                # each stripped label back to its CLI release.
                "model_disp": f"{_strip_cli(model)}*" if excl else _strip_cli(model),
                "model_full": model,  # retained for legend/grouping use
                "n": n,
                "avg_dur": sum(m["timing"]["grand_total_duration_ms"] for m in mm) / n / 1000,
                "avg_lines": sum(m["code_metrics"]["total_lines"] for m in mm) / n,
                "avg_errors": sum(m["quality"]["error_count"] for m in mm) / n,
                "avg_turns": sum(m["timing"]["num_turns"] for m in mm) / n,
                "avg_cost": sum(m["cost"]["total_cost_usd"] for m in mm) / n,
                "total_cost": sum(m["cost"]["total_cost_usd"] for m in mm),
                "avg_llm": avg_llm if avg_llm is not None else 0.0,
                "avg_llm_disp": f"{avg_llm:.1f}" if avg_llm is not None else "—",
                "avg_llm_n": len(llm_scores),
                "avg_deliv": avg_deliv if avg_deliv is not None else 0.0,
                "avg_deliv_disp": f"{avg_deliv:.1f}" if avg_deliv is not None else "—",
                "avg_deliv_n": len(deliv_scores),
            })

    # Consolidate per-CLI rows sharing the same display label into one.
    # Without this step a run dir that spans two CLI releases for the
    # same (language, model, effort) renders two Comparison/Tiers rows
    # whose Language + Model cells are identical — indistinguishable
    # duplicates to the reader. The CLI Version Legend further down
    # still documents each CLI release individually.
    def _consolidate_cmp_rows(rows):
        grouped: dict[tuple, list[dict]] = {}
        order: list[tuple] = []
        for r in rows:
            k = (r["mode"], _strip_cli(r["model"]))
            if k not in grouped:
                order.append(k)
            grouped.setdefault(k, []).append(r)
        merged: list[dict] = []
        for k in order:
            parts = grouped[k]
            if len(parts) == 1:
                merged.append(parts[0])
                continue
            n_total = sum(p["n"] for p in parts)
            def _wavg(key):
                return sum(p[key] * p["n"] for p in parts) / n_total
            def _wavg_judged(key, n_key):
                total_n = sum(p[n_key] for p in parts)
                if not total_n:
                    return None
                return sum(p[key] * p[n_key] for p in parts) / total_n
            avg_llm = _wavg_judged("avg_llm", "avg_llm_n")
            avg_deliv = _wavg_judged("avg_deliv", "avg_deliv_n")
            excl_total = sum(p.get("excluded", 0) for p in parts)
            base = dict(parts[0])
            display_model = _strip_cli(parts[0]["model"])
            base.update({
                "model": display_model,
                "model_disp": f"{display_model}*" if excl_total else display_model,
                "model_full": ",".join(p["model"] for p in parts),
                "excluded": excl_total,
                "n": n_total,
                "avg_dur": _wavg("avg_dur"),
                "avg_lines": _wavg("avg_lines"),
                "avg_errors": _wavg("avg_errors"),
                "avg_turns": _wavg("avg_turns"),
                "avg_cost": _wavg("avg_cost"),
                "total_cost": sum(p["total_cost"] for p in parts),
                "avg_llm": avg_llm if avg_llm is not None else 0.0,
                "avg_llm_disp": f"{avg_llm:.1f}" if avg_llm is not None else "—",
                "avg_llm_n": sum(p["avg_llm_n"] for p in parts),
                "avg_deliv": avg_deliv if avg_deliv is not None else 0.0,
                "avg_deliv_disp": f"{avg_deliv:.1f}" if avg_deliv is not None else "—",
                "avg_deliv_n": sum(p["avg_deliv_n"] for p in parts),
            })
            merged.append(base)
        return merged
    cmp_rows = _consolidate_cmp_rows(cmp_rows)

    # ── Trap & Hook data ──
    TEST_RUN_COST_S = {"default": 8, "powershell": 35, "powershell-tool": 35, "bash": 12, "typescript-bun": 8}
    # Compute per-(mode, model) hook overhead from actual Write/Edit durations.
    # Use all_tool_uses when available (full list), fall back to slowest_tool_uses.
    # Subtract 0.05s baseline for the Write operation itself.
    _write_durs_by_combo: dict[tuple, list] = {}
    for m in all_metrics:
        combo = (m["language_mode"], _label(m))
        source = m.get("tool_use_timing", {}).get("all_tool_uses") or m.get("tool_use_timing", {}).get("slowest_tool_uses", [])
        for t in source:
            if t["tool_name"] in ("Write", "Edit"):
                _write_durs_by_combo.setdefault(combo, []).append(t["duration_ms"] / 1000)
    HOOK_OVERHEAD_BY_COMBO = {
        combo: max(0, (sum(ds) / len(ds)) - 0.05) if ds else 0.5
        for combo, ds in _write_durs_by_combo.items()
    }

    trap_instances = []
    hook_by_combo = {}
    combo_run_counts = {}

    for m in all_metrics:
        mode, model = m["language_mode"], _label(m)
        path_subdir = f"{mode}-{_path_label(m)}"
        combo = (mode, model)
        combo_run_counts[combo] = combo_run_counts.get(combo, 0) + 1

        cli_path = run_dir / "tasks" / m["task_id"] / path_subdir / "cli-output.json"
        console_path = run_dir / "tasks" / m["task_id"] / path_subdir / "console-log.txt"
        try:
            evts = json.loads(cli_path.read_text())
        except Exception:
            evts = []
        console_text = console_path.read_text() if console_path.exists() else ""

        for trap in _detect_traps(evts, console_text, m):
            trap_instances.append({
                "mode": mode, "model": model, "task_id": m["task_id"],
                "task_name": m["task_name"],
                "dur_s": m["timing"]["grand_total_duration_ms"] / 1000,
                "cost": m["cost"]["total_cost_usd"],
                **trap,
            })

        # Trap: PowerShell runtime install overhead (pwsh + Pester pre-installed on
        # real GitHub runners but must be installed in act containers every run).
        # Primary source: act-result.txt step timings.  Fallback: event stream.
        if mode in ("powershell", "powershell-tool"):
            act_result_path = (run_dir / "tasks" / m["task_id"]
                               / path_subdir / "generated-code" / "act-result.txt")
            act_text = act_result_path.read_text() if act_result_path.exists() else ""
            # Primary: parse exact step durations from act output
            pwsh_times = [float(x) for x in re.findall(
                r"Install PowerShell \[(\d+\.?\d*)s\]", act_text)]
            pester_times = [float(x) for x in re.findall(
                r"Install Pester \[(\d+\.?\d*)s\]", act_text)]
            # Fallback: if act-result.txt had no timings, check event stream
            if not pwsh_times and not pester_times:
                for ev in evts:
                    if not isinstance(ev, dict) or ev.get("type") != "user":
                        continue
                    for c in (ev.get("message", {}).get("content", []) or []):
                        if isinstance(c, dict) and c.get("type") == "tool_result":
                            txt = str(c.get("content", ""))
                            pwsh_times.extend(float(x) for x in re.findall(
                                r"Install PowerShell \[(\d+\.?\d*)s\]", txt))
                            pester_times.extend(float(x) for x in re.findall(
                                r"Install Pester \[(\d+\.?\d*)s\]", txt))
            pwsh_secs = sum(pwsh_times)
            pester_secs = sum(pester_times)
            total_overhead = pwsh_secs + pester_secs
            if total_overhead >= 15:
                parts = []
                if pwsh_times:
                    parts.append(f"{len(pwsh_times)} pwsh installs ({pwsh_secs:.0f}s)")
                if pester_times:
                    parts.append(f"{len(pester_times)} Pester installs ({pester_secs:.0f}s)")
                trap_instances.append({
                    "mode": mode, "model": model, "task_id": m["task_id"],
                    "task_name": m["task_name"],
                    "dur_s": m["timing"]["grand_total_duration_ms"] / 1000,
                    "cost": m["cost"]["total_cost_usd"],
                    "name": "pwsh-runtime-install-overhead",
                    "time_s": total_overhead,
                    "desc": "; ".join(parts),
                })

        caught = m.get("hooks", {}).get("hook_errors_caught", 0)
        fires = m.get("hooks", {}).get("hook_fires", 0)
        gross_saved = caught * TEST_RUN_COST_S.get(mode, 10)
        overhead = fires * HOOK_OVERHEAD_BY_COMBO.get(combo, 0.5)
        # Only include test time if we have real durations from all_tool_uses.
        # Older runs that only have top-5/10 slowest_tool_uses produce a lower
        # bound that's misleading — omit rather than show bad data.
        all_uses = m.get("tool_use_timing", {}).get("all_tool_uses", [])
        has_real_test_time = bool(all_uses)
        test_time = _categorize_tool_time(all_uses)["test_duration_ms"] / 1000 if all_uses else 0
        if combo not in hook_by_combo:
            hook_by_combo[combo] = {"fires": 0, "caught": 0, "gross_saved": 0, "overhead": 0,
                                     "test_time": 0, "has_real_test_time": True}
        hook_by_combo[combo]["fires"] += fires
        hook_by_combo[combo]["caught"] += caught
        hook_by_combo[combo]["gross_saved"] += gross_saved
        hook_by_combo[combo]["overhead"] += overhead
        if has_real_test_time:
            hook_by_combo[combo]["test_time"] += test_time
        else:
            hook_by_combo[combo]["has_real_test_time"] = False

    # ── Aggregate trap time/cost by (mode, model) for net-of-traps columns ──
    trap_time_by_combo: dict[tuple, float] = defaultdict(float)
    trap_cost_by_combo: dict[tuple, float] = defaultdict(float)
    for t in trap_instances:
        combo = (t["mode"], t["model"])
        trap_time_by_combo[combo] += t["time_s"]
        # Estimate cost proportional to time fraction of the run
        if t["dur_s"] > 0 and t["cost"] > 0:
            trap_cost_by_combo[combo] += t["time_s"] / t["dur_s"] * t["cost"]

    for r in cmp_rows:
        combo = (r["mode"], r["model"])
        n = r["n"]
        r["avg_trap_dur"] = trap_time_by_combo.get(combo, 0) / n
        r["avg_dur_net"] = r["avg_dur"] - r["avg_trap_dur"]

    # ── Prompt cache data ──
    cache_data = []
    cache_read_rates = {s: COST_PER_MTOK[mid]["cache_read"] for s, mid in MODELS.items() if mid in COST_PER_MTOK}
    cache_create_rates = {s: COST_PER_MTOK[mid]["cache_write"] for s, mid in MODELS.items() if mid in COST_PER_MTOK}
    for m in all_metrics:
        cli_path = run_dir / "tasks" / m["task_id"] / f"{m['language_mode']}-{_path_label(m)}" / "cli-output.json"
        if not cli_path.exists():
            continue
        try:
            evts = json.loads(cli_path.read_text())
        except Exception:
            continue
        for e in evts:
            if e.get("type") == "assistant":
                usage = e.get("message", {}).get("usage", {})
                cr = usage.get("cache_read_input_tokens", 0)
                cc = usage.get("cache_creation_input_tokens", 0)
                # Pricing lookup uses plain model_short; display label includes effort.
                ms_price = m["model_short"]
                ms_label = _label(m)
                saved = cr * (cache_create_rates.get(ms_price, 0) - cache_read_rates.get(ms_price, 0)) / 1_000_000 if cr else 0
                status = "full_hit" if cr > 0 and cc == 0 else "partial" if cr > 0 else "miss"
                cache_data.append({"mode": m["language_mode"], "model": ms_label, "saved": saved, "status": status})
                break

    # ==================================================================
    # OBSERVATIONS (at top of document)
    # ==================================================================
    if len(successful) >= 2 and len(cmp_rows) >= 2:
        # Compute rank + tier once; the two sections below reuse these
        # per-row fields.
        for i, r in enumerate(sorted(cmp_rows, key=lambda r: r["avg_dur"]), start=1):
            r["dur_rank"] = i
        for i, r in enumerate(sorted(cmp_rows, key=lambda r: r["avg_cost"]), start=1):
            r["cost_rank"] = i
        llm_scored = [r for r in cmp_rows if r["avg_llm_n"] > 0]
        for i, r in enumerate(sorted(llm_scored, key=lambda r: -r["avg_llm"]), start=1):
            r["llm_rank"] = i
        _llm_sentinel = len(cmp_rows) + 1
        for r in cmp_rows:
            r.setdefault("llm_rank", _llm_sentinel)
            r["llm_rank_disp"] = str(r["llm_rank"]) if r["llm_rank"] != _llm_sentinel else "—"
        # Same pattern for deliverable judge score. Separate sentinel so
        # rows missing one judge but having the other still sort sensibly.
        deliv_scored = [r for r in cmp_rows if r["avg_deliv_n"] > 0]
        for i, r in enumerate(sorted(deliv_scored, key=lambda r: -r["avg_deliv"]), start=1):
            r["deliv_rank"] = i
        _deliv_sentinel = len(cmp_rows) + 1
        for r in cmp_rows:
            r.setdefault("deliv_rank", _deliv_sentinel)
            r["deliv_rank_disp"] = str(r["deliv_rank"]) if r["deliv_rank"] != _deliv_sentinel else "—"
        best_dur = min(r["avg_dur"] for r in cmp_rows)
        best_cost = min(r["avg_cost"] for r in cmp_rows)
        # Auto-calibrate ratio bands to this dataset's best-to-worst spread.
        # A tight cluster gets narrow bands (so meaningful gaps still show
        # as distinct tiers); a wide spread gets proportionally wide bands
        # (so the full A-E range is populated instead of everything pinned
        # to D/E). Formula: log-equal divisions — boundary i = max^(i/5).
        dur_ratios = [r["avg_dur"] / best_dur for r in cmp_rows]
        cost_ratios = [r["avg_cost"] / best_cost for r in cmp_rows]
        dur_bands = _compute_ratio_bands(dur_ratios)
        cost_bands = _compute_ratio_bands(cost_ratios)
        for r in cmp_rows:
            r["dur_tier"] = _ratio_tier(r["avg_dur"] / best_dur, dur_bands)
            r["cost_tier"] = _ratio_tier(r["avg_cost"] / best_cost, cost_bands)
            r["llm_tier"] = _llm_tier(r["avg_llm"]) if r["avg_llm_n"] > 0 else "—"
            r["deliv_tier"] = _llm_tier(r["avg_deliv"]) if r["avg_deliv_n"] > 0 else "—"

        def _fmt_bands(bands):
            # Format the 12 log-equal boundaries compactly: one line with
            # every letter tier paired with its upper bound ratio. F is
            # "> b12" (beyond the observed worst), so it sits at the end.
            parts = [f"**{letter}** ≤{b:.2f}×"
                     for letter, b in zip(_TIER_LETTERS[:-1], bands)]
            parts.append(f"**{_TIER_LETTERS[-1]}** >{bands[-1]:.2f}×")
            return ", ".join(parts)

        # Composite key used as the DEFAULT sort for both Tiers and
        # Rankings: 40% Tests Quality, 25% Workflow Craft, 35% split
        # evenly between Duration and Cost tiers. All tier_num values
        # are lower-is-better (A+=1, F=13, —=14), so ascending sort
        # surfaces the best combo first. Per-axis sort variants below
        # still allow isolating a single axis.
        def _tier_composite(r):
            return (0.40 * _tier_num(r["llm_tier"])
                    + 0.25 * _tier_num(r["deliv_tier"])
                    + 0.35 * (_tier_num(r["dur_tier"])
                              + _tier_num(r["cost_tier"])) / 2)

        # ── Tiers (bin by value so gap-vs-cluster is visible at a glance) ──
        lines.append("## Tiers by Language/Model/Effort")
        lines.append("")
        lines.append("*Default sort: weighted composite of tiers (40% Tests, 25% Workflow Craft, 35% split between Duration & Cost). See [Notes](#notes) for tier-band definitions and scoring rubric.*")
        any_excluded = sum(r["excluded"] for r in cmp_rows) > 0
        if any_excluded:
            lines.append("*`*` after a Model label = this combo's aggregates exclude one or more failed/timed-out runs (see the Failed / Timed-Out Runs table).*")
        lines.append("")
        tr_hdr = "| Language | Model | Duration | Cost | Tests Quality | Workflow Craft |"
        tr_sep = "|----------|-------|----------|------|-----------|-------------|"
        def _fmt_tr(r):
            return (f"| {r['mode']} | {r['model_disp']} "
                    f"| {r['dur_tier']} ({_dur(r['avg_dur'])}) "
                    f"| {r['cost_tier']} (${r['avg_cost']:.2f}) "
                    f"| {r['llm_tier']}"
                    + (f" ({r['avg_llm']:.1f})" if r['avg_llm_n'] > 0 else "")
                    + " | "
                    + r['deliv_tier']
                    + (f" ({r['avg_deliv']:.1f})" if r['avg_deliv_n'] > 0 else "")
                    + " |")
        lines.append(tr_hdr)
        lines.append(tr_sep)
        for r in sorted(cmp_rows, key=_tier_composite):
            lines.append(_fmt_tr(r))
        lines.append("")
        # Sort variants for Tiers. Primary key is the sorted-on axis's
        # tier; secondary is the average numeric tier of the OTHER three
        # axes, so ties on the primary axis break toward the combo that
        # is stronger overall. A-first / ascending on both.
        lines.extend(_emit_sorted_variants(tr_hdr, tr_sep, cmp_rows, [
            ("Sorted by Duration tier (best-first), then avg of Cost/Tests/Workflow Craft tiers",
             lambda r: (_tier_num(r["dur_tier"]),
                        (_tier_num(r["cost_tier"]) + _tier_num(r["llm_tier"])
                         + _tier_num(r["deliv_tier"])) / 3),
             False),
            ("Sorted by Cost tier (best-first), then avg of Duration/Tests/Workflow Craft tiers",
             lambda r: (_tier_num(r["cost_tier"]),
                        (_tier_num(r["dur_tier"]) + _tier_num(r["llm_tier"])
                         + _tier_num(r["deliv_tier"])) / 3),
             False),
            ("Sorted by Tests Quality tier (best-first; no-data last), then avg of other tiers",
             lambda r: (_tier_num(r["llm_tier"]),
                        (_tier_num(r["dur_tier"]) + _tier_num(r["cost_tier"])
                         + _tier_num(r["deliv_tier"])) / 3),
             False),
            ("Sorted by Workflow Craft tier (best-first; no-data last), then avg of other tiers",
             lambda r: (_tier_num(r["deliv_tier"]),
                        (_tier_num(r["dur_tier"]) + _tier_num(r["cost_tier"])
                         + _tier_num(r["llm_tier"])) / 3),
             False),
        ], _fmt_tr))
        lines.append("")

        # Tiers under Notes carries only the band tables; the Duration/
        # Cost "what are ratios" prose lives in the top-level Scoring
        # section (built below as `scoring_block`).
        notes_sections.append(("Tiers", [
            f"- **Duration bands:** {_fmt_bands(dur_bands)}",
            f"- **Cost bands:** {_fmt_bands(cost_bands)}",
            "",
            "*Tests/Workflow Craft bands are absolute Overall score bands:* "
            "**A+** ≥4.7, **A** ≥4.4, **A-** ≥4.1, "
            "**B+** ≥3.8, **B** ≥3.5, **B-** ≥3.2, "
            "**C+** ≥2.9, **C** ≥2.6, **C-** ≥2.3, "
            "**D+** ≥2.0, **D** ≥1.7, **D-** ≥1.4, "
            "**F** <1.4, `—` = no data.*",
        ]))

        if completed < total_runs and total_duration > 0 and completed > 0:
            est_remaining_s = (total_duration / completed) * (total_runs - run_count)
            lines.append(f"- **Estimated time remaining:** {_dur(est_remaining_s)}")
            est_total_cost = (total_cost / completed) * total_runs
            lines.append(f"- **Estimated total cost:** ${est_total_cost:.2f}")
            lines.append("")

    # ── Failed runs (if any) ──
    if failed:
        lines.append("## Failed / Timed-Out Runs")
        lines.append("")
        lines.append("| Task | Language | Model | Duration | Reason | Lines | actionlint | act-result.txt |")
        lines.append("|------|------|-------|----------|--------|-------|------------|----------------|")
        for m in failed:
            dur = m["timing"]["grand_total_duration_ms"] / 1000
            reason = m.get("failure_reason", "exit_code=" + str(m.get("exit_code", "?")))
            alint_val = m.get("quality", {}).get("actionlint_pass")
            alint = "pass" if alint_val else ("fail" if alint_val is False else "n/a")
            act = "yes" if m.get("quality", {}).get("act_result_txt_exists") else "no"
            lines.append(
                f"| {m['task_name'][:30]} | {m['language_mode']} | {_strip_cli(_label(m))} "
                f"| {_dur(dur)} | {reason} | {m['code_metrics']['total_lines']} | {alint} | {act} |")
        lines.append("")
        lines.append(f"*{len(failed)} run(s) excluded from averages below.*")
        lines.append("")

    # ==================================================================
    # COMPARISON BY LANGUAGE/MODEL
    # ==================================================================
    if cmp_rows:
        lines.append("## Comparison by Language/Model/Effort")
        if failed:
            lines.append("*(averages exclude failed/timed-out runs)*")
        lines.append("*See [Notes](#notes) for scoring rubric and CLI version legend.*")
        lines.append("")
        cmp_hdr = "| Language | Model | Runs | Avg Duration | Avg Duration Net of Traps | Avg Errors | Avg Turns | Avg Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |"
        cmp_sep = "|----------|-------|------|--------------|---------------------------|------------|-----------|----------|------------|---------------|-----------------|"
        def _fmt_cmp(r):
            return (f"| {r['mode']} | {r['model_disp']} | {r['n']} | {_dur(r['avg_dur'])} | {_dur(r['avg_dur_net'])} "
                    f"| {r['avg_errors']:.1f} | {r['avg_turns']:.0f} | ${r['avg_cost']:.2f} | ${r['total_cost']:.2f} "
                    f"| {r['avg_llm_disp']} | {r['avg_deliv_disp']} |")
        lines.append(cmp_hdr)
        lines.append(cmp_sep)
        for r in cmp_rows:
            lines.append(_fmt_cmp(r))
        lines.append("")
        lines.extend(_emit_sorted_variants(cmp_hdr, cmp_sep, cmp_rows, [
            ("Sorted by avg cost (cheapest first)", "avg_cost", False),
            ("Sorted by avg duration (fastest first)", "avg_dur", False),
            ("Sorted by avg duration net of traps (fastest first)", "avg_dur_net", False),
            ("Sorted by avg errors (fewest first)", "avg_errors", False),
            ("Sorted by avg turns (fewest first)", "avg_turns", False),
            ("Sorted by LLM-as-judge score (best first)", "avg_llm", True),
            ("Sorted by deliverable-quality score (best first)", "avg_deliv", True),
        ], _fmt_cmp))
        lines.append("")

    # ==================================================================
    # SAVINGS ANALYSIS
    # ==================================================================
    lines.append("## Savings Analysis")
    lines.append("")

    # ── Hook Savings by Language/Model/Effort ──
    lines.append("### Hook Savings by Language/Model/Effort")
    lines.append("")
    lines.append("Each hook-caught error avoids one test run that would otherwise have been needed to discover it.")
    lines.append("Every hook fire (hit or miss) costs execution time for the syntax/type checker.")
    lines.append("")
    lines.append("*`% of Test Time Saved` = `net / (net + test_time) × 100` — the share of total (would-have-been + actually-spent) test time that hooks eliminated. Bounded in (-∞, 100%) without an artificial cap; near 100% means hooks substituted for almost all of the hypothetical test work.*")
    lines.append("")

    # Determine if we have real test time data (all_tool_uses with durations)
    has_test_time = all(hs.get("has_real_test_time", False) for hs in hook_by_combo.values() if hs.get("fires", 0) > 0)

    if has_test_time:
        hook_hdr = ("| Language | Model | Fires | Caught | Rate "
                    "| Gross Saved | % of Time | Overhead | % of Time | Net Saved | % of Time "
                    "| Test Run Time | % of Test Time Saved |")
        hook_sep = ("|------|-------|-------|--------|------"
                    "|------------|-----------|----------|-----------|-----------|-----------|"
                    "---------------|----------------------|")
    else:
        hook_hdr = ("| Language | Model | Fires | Caught | Rate "
                    "| Gross Saved | % of Time | Overhead | % of Time | Net Saved | % of Time |")
        hook_sep = ("|------|-------|-------|--------|------"
                    "|------------|-----------|----------|-----------|-----------|-----------|")

    hook_rows = []
    for mode in modes_seen:
        for model in models_seen:
            hs = hook_by_combo.get((mode, model), {})
            f_count = hs.get("fires", 0)
            c_count = hs.get("caught", 0)
            if f_count == 0:
                continue
            gross = hs["gross_saved"]
            overhead = hs["overhead"]
            net = gross - overhead
            test_t = hs.get("test_time", 0)
            hook_rows.append({
                "mode": mode, "model": model, "fires": f_count, "caught": c_count,
                "rate": c_count / f_count * 100,
                "gross": gross, "gross_pct": gross / total_duration * 100 if total_duration else 0,
                "overhead": overhead, "overhead_pct": overhead / total_duration * 100 if total_duration else 0,
                "net": net, "net_pct": net / total_duration * 100 if total_duration else 0,
                "test_time": test_t,
                # Denominator = net + test_t so the metric reads as "share
                # of total (would-have-been + actually-spent) test time that
                # hooks saved." Naturally bounded above by 100% without a
                # cap, even when gross_saved far exceeds actual test time.
                "test_time_pct": (net / (net + test_t) * 100) if (net + test_t) else 0,
            })

    def _fmt_hook(r):
        base = (f"| {r['mode']} | {r['model']} | {r['fires']} | {r['caught']} | {r['rate']:.1f}% "
                f"| {_dur(r['gross'])} | {r['gross_pct']:.1f}% "
                f"| {_dur(r['overhead'])} | {r['overhead_pct']:.1f}% "
                f"| {_dur(r['net'])} | {r['net_pct']:.1f}%")
        if has_test_time:
            return base + f" | {_dur(r['test_time'])} | {r['test_time_pct']:.1f}% |"
        return base + " |"

    lines.append(hook_hdr)
    lines.append(hook_sep)
    for r in hook_rows:
        lines.append(_fmt_hook(r))
    lines.append("")

    sort_specs = [
        ("Sorted by net saved (most first)", "net", True),
        ("Sorted by catch rate (highest first)", "rate", True),
    ]
    if has_test_time:
        sort_specs.insert(1, ("Sorted by net % of test time saved (most first)", "test_time_pct", True))
    lines.extend(_emit_sorted_variants(hook_hdr, hook_sep, hook_rows, sort_specs, _fmt_hook))
    lines.append("")

    # ── Trap Analysis by Language/Model/Effort/Category ──
    if trap_instances:
        # Each value is a tuple of modes the trap applies to. A trap that can
        # fire in any PowerShell variant uses the full PS family so its
        # catch-rate denominator counts runs of both `powershell` and
        # `powershell-tool` modes.
        PS_FAMILY = ("powershell", "powershell-tool")
        trap_applicable_mode = {
            "pester-cmdletbinding-spiral": PS_FAMILY,
            "pester-wrong-assertions": PS_FAMILY,
            "docker-pwsh-install": PS_FAMILY,
            "mid-run-module-restructure": PS_FAMILY,
            "ts-type-error-fix-cycles": ("typescript-bun",),
            "bats-setup-issues": ("bash",),
            "dotnet-install-loop": ("csharp-script",),
            "pwsh-invoked-from-bash": PS_FAMILY,
            "pwsh-runtime-install-overhead": PS_FAMILY,
        }
        trap_descriptions = {
            "act-push-debug-loops": "Agent ran `act push` more than twice, indicating repeated workflow debugging.",
            "ts-type-error-fix-cycles": "TypeScript type errors caught by `tsc --noEmit` hooks; each requires a fix cycle.",
            "fixture-rework": "Agent wrote, broke, and rewrote test fixture data (4+ fixture-related commands).",
            "repeated-test-reruns": "Same test command executed 4+ times without the underlying code changing.",
            "docker-pwsh-install": "Multiple Docker test runs trying to figure out how to install PowerShell in act's container.",
            "act-permission-path-errors": "Files not found or permission denied inside the act Docker container.",
            "docker-pkg-install": "Multiple Docker test runs exploring non-PowerShell package installation for act.",
            "actionlint-fix-cycles": "Workflow YAML required 3+ actionlint runs and 2+ fixes to pass.",
            "pester-cmdletbinding-spiral": "Agent wrote many /tmp/test_*.ps1 scripts to bisect a Pester parameter binding conflict.",
            "pester-wrong-assertions": "Agent used nonexistent Pester assertion names (e.g. BeInRange).",
            "mid-run-module-restructure": "Agent restructured from a flat .ps1 script to a .psm1 module mid-run.",
            "bats-setup-issues": "Agent struggled with bats-core test framework setup or load helpers.",
            "act-fixture-paths": "Test fixtures not found inside the act Docker container due to path issues.",
            "permission-denial-loops": "CLI sandbox blocked commands and agent retried instead of adapting (v1 harness issue).",
            "dotnet-install-loop": "Agent stuck in loop trying to install/verify .NET SDK, blocked by CLI sandbox.",
            "pwsh-invoked-from-bash": "Agent used `pwsh -Command`/`-File` from bash `run:` steps instead of `shell: pwsh`, causing cross-shell debugging (parse errors, quoting issues, scope problems, late pwsh discovery in act).",
            "pwsh-runtime-install-overhead": "Time spent installing PowerShell and Pester inside act containers. Both are pre-installed on real GitHub runners but must be downloaded (~56MB) and installed in each act job. Measured from act step durations.",
        }

        trap_agg = defaultdict(list)
        for t in trap_instances:
            trap_agg[t["name"]].append(t)
        mode_run_totals = {md: sum(1 for m in all_metrics if m["language_mode"] == md) for md in modes_seen}

        # Build rows: one per (trap, mode, model) combo that actually occurred
        tlmc_rows = []
        for trap_name in sorted(trap_agg, key=lambda k: -sum(t["time_s"] for t in trap_agg[k])):
            insts = trap_agg[trap_name]
            tmodes = trap_applicable_mode.get(trap_name)  # tuple or None (=all)
            if tmodes is None:
                n_app = completed
            else:
                n_app = sum(mode_run_totals.get(m, 0) for m in tmodes)
            n_fell = len(insts)
            t_time = sum(t["time_s"] for t in insts)
            t_cost = sum(t["time_s"] / t["dur_s"] * t["cost"] for t in insts if t["dur_s"] > 0 and t["cost"] > 0)
            rate = n_fell / n_app * 100 if n_app else 0

            # Break down by mode/model
            by_combo = defaultdict(list)
            for t in insts:
                by_combo[(t["mode"], t["model"])].append(t)

            for (tmode_k, tmodel_k), combo_insts in sorted(by_combo.items()):
                combo_time = sum(t["time_s"] for t in combo_insts)
                combo_cost = sum(t["time_s"] / t["dur_s"] * t["cost"] for t in combo_insts if t["dur_s"] > 0 and t["cost"] > 0)
                tlmc_rows.append({
                    "trap": trap_name, "mode": tmode_k, "model": tmodel_k,
                    "fell_in": len(combo_insts), "applicable": n_app, "rate": rate,
                    "time_lost": combo_time,
                    "time_pct": combo_time / total_duration * 100 if total_duration else 0,
                    "cost_lost": combo_cost,
                    "cost_pct": combo_cost / total_cost * 100 if total_cost else 0,
                })

        lines.append("### Trap Analysis by Language/Model/Effort/Category")
        lines.append("")
        tlmc_hdr = "| Trap | Language | Model | Fell In | Time Lost | % of Time | $ Lost | % of $ |"
        tlmc_sep = "|------|------|-------|---------|-----------|-----------|--------|--------|"
        def _fmt_tlmc(r):
            return (f"| {r['trap']} | {r['mode']} | {r['model']} | {r['fell_in']} "
                    f"| {_dur(r['time_lost'])} | {r['time_pct']:.1f}% | ${r['cost_lost']:.2f} | {r['cost_pct']:.2f}% |")
        lines.append(tlmc_hdr)
        lines.append(tlmc_sep)
        for r in tlmc_rows:
            lines.append(_fmt_tlmc(r))
        total_trap_time = sum(t["time_s"] for t in trap_instances)
        total_trap_cost = sum(t["time_s"] / t["dur_s"] * t["cost"] for t in trap_instances if t["dur_s"] > 0 and t["cost"] > 0)
        total_trapped = len(set((t["task_id"], t["mode"], t["model"]) for t in trap_instances))
        lines.append("")
        lines.extend(_emit_sorted_variants(tlmc_hdr, tlmc_sep, tlmc_rows, [
            ("Sorted by time lost (least first)", "time_lost", False),
            ("Sorted by $ lost (least first)", "cost_lost", False),
            ("Sorted by fell-in count (fewest first)", "fell_in", False),
        ], _fmt_tlmc))
        lines.append("")

        # Trap descriptions and column explanations
        lines.append("#### Trap Descriptions")
        lines.append("")
        for trap_name in sorted(trap_agg):
            desc = trap_descriptions.get(trap_name, "No description available.")
            lines.append(f"- **{trap_name}**: {desc}")
        lines.append("")
        lines.append("#### Column Definitions")
        lines.append("")
        lines.append("- **Fell In**: Number of runs (within that language/model) where this trap was detected.")
        lines.append("- **Time Lost**: Estimated wall-clock seconds wasted on the trap, based on the number of")
        lines.append("  wasted commands multiplied by a per-command cost (15\u201325s for typical Bash, 45s for Docker runs, 50s for act push).")
        lines.append("- **% of Time**: Time Lost as a percentage of total benchmark duration.")
        lines.append("- **$ Lost**: Proportional cost impact, calculated as (Time Lost / Run Duration) \u00d7 Run Cost for each affected run.")
        lines.append("- **% of $**: $ Lost as a percentage of total benchmark cost.")
        lines.append("")

    # ── Traps by Language/Model/Effort ──
    if trap_instances:
        lines.append("### Traps by Language/Model/Effort")
        lines.append("")
        tlm_hdr = "| Language | Model | Runs | Traps | Time Lost | % of Time | $ Lost | % of $ |"
        tlm_sep = "|------|-------|------|-------|-----------|-----------|--------|--------|"
        trapped_runs_by_combo = {}
        trap_count_by_combo = {}
        trap_time_by_combo = {}
        trap_cost_by_combo = {}
        for t in trap_instances:
            combo = (t["mode"], t["model"])
            trapped_runs_by_combo.setdefault(combo, set()).add(t["task_id"])
            trap_count_by_combo[combo] = trap_count_by_combo.get(combo, 0) + 1
            trap_time_by_combo[combo] = trap_time_by_combo.get(combo, 0) + t["time_s"]
            if t["dur_s"] > 0 and t["cost"] > 0:
                trap_cost_by_combo[combo] = trap_cost_by_combo.get(combo, 0) + t["time_s"] / t["dur_s"] * t["cost"]

        tlm_rows = []
        for mode in modes_seen:
            for model in models_seen:
                combo = (mode, model)
                n = combo_run_counts.get(combo, 0)
                if n == 0:
                    continue
                n_trapped = len(trapped_runs_by_combo.get(combo, set()))
                rate = n_trapped / n * 100 if n else 0
                tc = trap_count_by_combo.get(combo, 0)
                tt = trap_time_by_combo.get(combo, 0)
                tcc = trap_cost_by_combo.get(combo, 0)
                tlm_rows.append({
                    "mode": mode, "model": model, "n": n, "trapped": n_trapped,
                    "rate": rate, "traps": tc,
                    "time_lost": tt, "time_pct": tt / total_duration * 100 if total_duration else 0,
                    "cost_lost": tcc, "cost_pct": tcc / total_cost * 100 if total_cost else 0,
                })
        def _fmt_tlm(r):
            return (f"| {r['mode']} | {r['model']} | {r['n']} "
                    f"| {r['traps']} | {_dur(r['time_lost'])} | {r['time_pct']:.1f}% "
                    f"| ${r['cost_lost']:.2f} | {r['cost_pct']:.2f}% |")
        lines.append(tlm_hdr)
        lines.append(tlm_sep)
        for r in tlm_rows:
            lines.append(_fmt_tlm(r))
        lines.append("")
        lines.extend(_emit_sorted_variants(tlm_hdr, tlm_sep, tlm_rows, [
            ("Sorted by time lost (least first)", "time_lost", False),
            ("Sorted by $ lost (least first)", "cost_lost", False),
        ], _fmt_tlm))
        lines.append("")

    # ── Prompt Cache Savings (at end of savings) ──
    if cache_data:
        cache_total_saved = sum(d["saved"] for d in cache_data)
        cache_pct = cache_total_saved / total_cost * 100 if total_cost else 0
        lines.append("### Prompt Cache Savings")
        lines.append("")
        lines.append("| Status | Runs | $ Saved | % of $ |")
        lines.append("|--------|------|---------|--------|")
        for label, st in [("Full hit (100%)", "full_hit"), ("Partial", "partial"), ("Miss", "miss")]:
            sv = sum(d["saved"] for d in cache_data if d["status"] == st)
            pct = sv / total_cost * 100 if total_cost else 0
            cnt = sum(1 for d in cache_data if d["status"] == st)
            lines.append(f"| {label} | {cnt} | ${sv:.2f} | {pct:.2f}% |")
        lines.append("")

    # ==================================================================
    # TEST QUALITY EVALUATION
    # ==================================================================
    from test_quality import compute_structural_metrics, LLM_JUDGE_CACHE_FILE

    tq_rows = []
    llm_rows = []
    has_llm = False
    for m in all_metrics:
        variant_dir = run_dir / "tasks" / m["task_id"] / f"{m['language_mode']}-{_path_label(m)}"
        gen_dir = variant_dir / "generated-code"
        sq = compute_structural_metrics(gen_dir)

        tq_rows.append({
            "task": m["task_name"][:30], "mode": m["language_mode"],
            "model": _strip_cli(_label(m)),
            "tests": sq["test_count"], "asserts": sq["assertion_count"],
            "apt": sq["assertions_per_test"],
            "t_lines": sq["test_lines"], "i_lines": sq["impl_lines"],
            "ratio": sq["test_to_code_ratio"],
            "lang": sq["language"],
        })

        # LLM-as-judge scores — read from the hoisted cache loaded earlier.
        lj = llm_data_by_key.get((m["task_id"], m["language_mode"], _label(m)))
        if lj:
            has_llm = True
            llm_rows.append({
                "task": m["task_name"][:30], "mode": m["language_mode"],
                "model": _strip_cli(_label(m)),
                "coverage": lj.get("coverage", 0), "rigor": lj.get("rigor", 0),
                "design": lj.get("design", 0), "overall": lj.get("overall", 0),
                "summary": lj.get("summary", ""),
                "judge_cost": lj.get("judge_cost_usd", 0),
            })

    lines.append("## Test Quality Evaluation")
    lines.append("")

    # ── Structural Metrics by Language/Model/Effort ──
    lines.append("### Structural Metrics by Language/Model/Effort")
    lines.append("")
    lines.append("Automated analysis of test files: test count, assertion count, and test-to-code line ratio.")
    lines.append("")

    sq_agg = {}
    for r in tq_rows:
        key = (r["mode"], r["model"])
        if key not in sq_agg:
            sq_agg[key] = {"mode": r["mode"], "model": r["model"],
                           "tests": [], "asserts": [], "ratios": []}
        sq_agg[key]["tests"].append(r["tests"])
        sq_agg[key]["asserts"].append(r["asserts"])
        sq_agg[key]["ratios"].append(r["ratio"])

    sq_hdr = "| Language | Model | Avg Tests | Avg Assertions | Avg Assert/Test | Avg Test:Code Ratio |"
    sq_sep = "|------|-------|-----------|----------------|-----------------|---------------------|"
    sq_summary_rows = []
    for key in sorted(sq_agg):
        a = sq_agg[key]
        n = len(a["tests"])
        avg_tests = sum(a["tests"]) / n
        avg_asserts = sum(a["asserts"]) / n
        avg_apt = avg_asserts / avg_tests if avg_tests > 0 else 0
        avg_ratio = sum(a["ratios"]) / n
        sq_summary_rows.append({
            "mode": a["mode"], "model": a["model"],
            "avg_tests": avg_tests, "avg_asserts": avg_asserts,
            "avg_apt": avg_apt, "avg_ratio": avg_ratio,
        })

    def _fmt_sq(r):
        return (f"| {r['mode']} | {r['model']} | {r['avg_tests']:.1f} "
                f"| {r['avg_asserts']:.1f} | {r['avg_apt']:.1f} | {r['avg_ratio']:.2f} |")

    lines.append(sq_hdr)
    lines.append(sq_sep)
    for r in sq_summary_rows:
        lines.append(_fmt_sq(r))
    lines.append("")
    lines.extend(_emit_sorted_variants(sq_hdr, sq_sep, sq_summary_rows, [
        ("Sorted by avg tests (most first)", "avg_tests", True),
        ("Sorted by avg assertions (most first)", "avg_asserts", True),
        ("Sorted by avg test:code ratio (highest first)", "avg_ratio", True),
    ], _fmt_sq))
    lines.append("")

    # ── Per-Run Structural Metrics ──
    tq_hdr = "| Task | Language | Model | Tests | Assertions | Assert/Test | Test Lines | Impl Lines | Test:Code |"
    tq_sep = "|------|------|-------|-------|------------|-------------|------------|------------|-----------|"
    def _fmt_tq(r):
        return (f"| {r['task']} | {r['mode']} | {r['model']} "
                f"| {r['tests']} | {r['asserts']} | {r['apt']:.1f} "
                f"| {r['t_lines']} | {r['i_lines']} | {r['ratio']:.2f} |")
    lines.extend(_collapsible_table("Per-run structural metrics", tq_hdr, tq_sep,
                                    [_fmt_tq(r) for r in tq_rows]))
    lines.append("")

    # ── LLM-as-Judge Scores ──
    if has_llm and llm_rows:
        lines.append("### LLM-as-Judge Scores")
        lines.append("")
        lines.append("An LLM evaluates each test suite on four dimensions (1-5 scale):")
        lines.append("")
        lines.append("- **Coverage** (1-5): Do tests exercise the key requirements? 1 = most untested, 5 = all covered.")
        lines.append("- **Rigor** (1-5): Edge cases, error handling, boundary conditions? 1 = happy path only, 5 = thorough.")
        lines.append("- **Design** (1-5): Test organization, fixtures, readability? 1 = messy/brittle, 5 = well-structured.")
        lines.append("- **Overall** (1-5): Holistic quality — would you trust this suite to catch regressions? 1 = no, 5 = absolutely. Use this as the primary ranking metric.")
        lines.append("")

        # Aggregate by mode/model
        lj_agg = {}
        for r in llm_rows:
            key = (r["mode"], r["model"])
            if key not in lj_agg:
                lj_agg[key] = {"mode": r["mode"], "model": r["model"],
                               "cov": [], "rig": [], "des": [], "ovr": [], "cost": []}
            lj_agg[key]["cov"].append(r["coverage"])
            lj_agg[key]["rig"].append(r["rigor"])
            lj_agg[key]["des"].append(r["design"])
            lj_agg[key]["ovr"].append(r["overall"])
            lj_agg[key]["cost"].append(r["judge_cost"])

        lj_hdr = "| Language | Model | Avg Overall | Avg Coverage | Avg Rigor | Avg Design | Judge Cost |"
        lj_sep = "|------|-------|-------------|-------------|-----------|------------|------------|"
        lj_summary_rows = []
        for key in sorted(lj_agg):
            a = lj_agg[key]
            n = len(a["cov"])
            lj_summary_rows.append({
                "mode": a["mode"], "model": a["model"],
                "avg_cov": sum(a["cov"]) / n, "avg_rig": sum(a["rig"]) / n,
                "avg_des": sum(a["des"]) / n, "avg_ovr": sum(a["ovr"]) / n,
                "cost": sum(a["cost"]),
            })
        def _fmt_lj(r):
            return (f"| {r['mode']} | {r['model']} | **{r['avg_ovr']:.1f}** "
                    f"| {r['avg_cov']:.1f} | {r['avg_rig']:.1f} "
                    f"| {r['avg_des']:.1f} "
                    f"| ${r['cost']:.4f} |")

        lines.append(lj_hdr)
        lines.append(lj_sep)
        for r in lj_summary_rows:
            lines.append(_fmt_lj(r))
        total_judge_cost = sum(r["cost"] for r in lj_summary_rows)
        lines.append(f"| **Total** | | | | | | **${total_judge_cost:.4f}** |")
        lines.append("")
        lines.extend(_emit_sorted_variants(lj_hdr, lj_sep, lj_summary_rows, [
            ("Sorted by avg overall (highest first)", "avg_ovr", True),
            ("Sorted by avg coverage (highest first)", "avg_cov", True),
            ("Sorted by avg rigor (highest first)", "avg_rig", True),
            ("Sorted by avg design (highest first)", "avg_des", True),
        ], _fmt_lj))
        lines.append("")

        # Per-run LLM scores
        lj_pr_hdr = "| Task | Language | Model | Cov | Rig | Des | Ovr | Summary |"
        lj_pr_sep = "|------|------|-------|-----|-----|-----|-----|---------|"
        def _fmt_lj_pr(r):
            return (f"| {r['task']} | {r['mode']} | {r['model']} "
                    f"| {r['coverage']} | {r['rigor']} "
                    f"| {r['design']} | {r['overall']} "
                    f"| {r['summary'][:60]} |")
        lines.extend(_collapsible_table("Per-run LLM judge scores", lj_pr_hdr, lj_pr_sep,
                                        [_fmt_lj_pr(r) for r in llm_rows]))
        lines.append("")

    # ── Cross-comparison: LLM scores vs structural metrics ──
    if has_llm and llm_rows and tq_rows:
        # Build lookup from (task, mode, model) -> structural data
        tq_lookup = {}
        for r in tq_rows:
            tq_lookup[(r["task"], r["mode"], r["model"])] = r

        # Collect paired data
        paired_tests, paired_asserts, paired_ratio = [], [], []
        paired_cov, paired_rig, paired_des, paired_ovr = [], [], [], []
        for lr in llm_rows:
            key = (lr["task"], lr["mode"], lr["model"])
            sq = tq_lookup.get(key)
            if not sq:
                continue
            paired_tests.append(sq["tests"])
            paired_asserts.append(sq["asserts"])
            paired_ratio.append(sq["ratio"])
            paired_cov.append(lr["coverage"])
            paired_rig.append(lr["rigor"])
            paired_des.append(lr["design"])
            paired_ovr.append(lr["overall"])

        if len(paired_tests) >= 5:
            lines.append("### Correlation: Structural Metrics vs Tests Quality")
            lines.append("")
            lines.append("Spearman rank correlation between automated counts and LLM judge scores.")
            lines.append("Values near +1.0 indicate the LLM agrees with the structural signal; near 0 means no relationship.")
            lines.append("")
            lines.append("| Structural Metric | vs Coverage | vs Rigor | vs Design | vs Overall |")
            lines.append("|-------------------|------------|---------|----------|-----------|")
            for label, vals in [("Test count", paired_tests),
                                ("Assertion count", paired_asserts),
                                ("Test:code ratio", paired_ratio)]:
                rc = _spearman(vals, paired_cov)
                rr = _spearman(vals, paired_rig)
                rd = _spearman(vals, paired_des)
                ro = _spearman(vals, paired_ovr)
                lines.append(
                    f"| {label} | {rc if rc is not None else 'n/a'} "
                    f"| {rr if rr is not None else 'n/a'} "
                    f"| {rd if rd is not None else 'n/a'} "
                    f"| {ro if ro is not None else 'n/a'} |")
            lines.append("")
            lines.append(f"*Based on {len(paired_tests)} runs with both structural and LLM scores.*")
            lines.append("")

        discrepancies = _find_discrepancies(llm_rows, tq_lookup)

        if discrepancies:
            counter_gaps = [d for d in discrepancies if d["kind"] == "counter-gap"]
            qualitative = [d for d in discrepancies if d["kind"] == "qualitative"]

            lines.append("### LLM vs Structural Discrepancies")
            lines.append("")

            if counter_gaps:
                lines.append("**Probable counter gaps** — structural counters may be missing "
                             "a test pattern. Investigate and fix `test_quality.py`.")
                lines.append("")
                lines.append("| Task | Language | Model | Tests | Asserts | Cov | Rig | Des | Ovr | Flag |")
                lines.append("|------|------|-------|-------|---------|-----|-----|-----|-----|------|")
                for d in counter_gaps:
                    lines.append(
                        f"| {d['task']} | {d['mode']} | {d['model']} "
                        f"| {d['tests']} | {d['asserts']} "
                        f"| {d['cov']} | {d['rig']} | {d['des']} | {d['ovr']} "
                        f"| {d['flag']} |")
                lines.append("")

            if qualitative:
                lines.append("**Qualitative disagreements** — structural metrics look reasonable; "
                             "the LLM judge is weighing factors the counters can't measure.")
                lines.append("")
                lines.append("| Task | Language | Model | Tests | Asserts | Cov | Rig | Des | Ovr | Flag | Justification |")
                lines.append("|------|------|-------|-------|---------|-----|-----|-----|-----|------|---------------|")
                for d in qualitative:
                    # Truncate justification to keep table readable
                    justification = d.get("justification", "")
                    if len(justification) > 200:
                        justification = justification[:197] + "..."
                    # Escape pipes in justification text
                    justification = justification.replace("|", "\\|")
                    lines.append(
                        f"| {d['task']} | {d['mode']} | {d['model']} "
                        f"| {d['tests']} | {d['asserts']} "
                        f"| {d['cov']} | {d['rig']} | {d['des']} | {d['ovr']} "
                        f"| {d['flag']} | {justification} |")
                lines.append("")

    # ==================================================================
    # PER-RUN RESULTS
    # ==================================================================
    lines.append("## Per-Run Results")
    lines.append("")
    lines.append("*Tests Quality = Overall (1-5) from LLM-as-judge of generated test code (dimensions: coverage, rigor, design). `—` = no judge data.*")
    lines.append("")
    pr_hdr = "| Task | Language | Model | Duration | Turns | Errors | Cost | Tests Quality | Chosen | Status |"
    pr_sep = "|------|----------|-------|----------|-------|--------|------|-----------|--------|--------|"
    pr_rows = []
    for m in all_metrics:
        dur = m["timing"]["grand_total_duration_ms"] / 1000
        status = "ok" if m in successful else m.get("failure_reason", "failed")
        lj = llm_data_by_key.get((m["task_id"], m["language_mode"], _label(m)))
        llm_overall = lj.get("overall") if lj else None
        pr_rows.append({
            "task": m["task_name"][:30], "mode": m["language_mode"],
            "model": _strip_cli(_label(m)),
            "dur": dur, "turns": m["timing"]["num_turns"],
            "errors": m["quality"]["error_count"],
            "cost": m["cost"]["total_cost_usd"],
            "lang": m["language_chosen"], "status": status,
            "llm": float(llm_overall) if isinstance(llm_overall, (int, float)) else 0.0,
            "llm_disp": f"{llm_overall:.1f}" if isinstance(llm_overall, (int, float)) else "—",
        })
    def _fmt_pr(r):
        return (f"| {r['task']} | {r['mode']} | {r['model']} "
                f"| {_dur(r['dur'])} | {r['turns']} "
                f"| {r['errors']} | ${r['cost']:.2f} "
                f"| {r['llm_disp']} "
                f"| {r['lang']} | {r['status']} |")
    lines.append(pr_hdr)
    lines.append(pr_sep)
    # Default table sorts by (task, language, model) so it reads as a
    # stable reference regardless of iteration order; sorted-detail
    # variants below offer other sorts.
    for r in sorted(pr_rows, key=lambda r: (r['task'], r['mode'], r['model'])):
        lines.append(_fmt_pr(r))
    lines.append("")
    lines.extend(_emit_sorted_variants(pr_hdr, pr_sep, pr_rows, [
        ("Sorted by cost (cheapest first)", "cost", False),
        ("Sorted by duration (fastest first)", "dur", False),
        ("Sorted by errors (fewest first)", "errors", False),
        ("Sorted by turns (fewest first)", "turns", False),
        ("Sorted by LLM-as-judge score (best first)", "llm", True),
    ], _fmt_pr))
    lines.append("")

    # ──────────────────────────────────────────────────────────────────
    # NOTES SECTION — rendered at the very bottom of the body. Moved here
    # from above-table prose so the tables themselves lead the document.
    # ──────────────────────────────────────────────────────────────────
    if cmp_rows:
        # Scoring rubric now lives in a top-level `## Scoring` section
        # substituted into _SCORING_MARKER directly after the ToC.

        # CLI Version Legend: one row per (variant × CLI version), with
        # Tasks/Languages columns that spell out the subset when a
        # release was added mid-campaign. "All" means the pair covered
        # every task / every language present in this report.
        from collections import defaultdict as _defaultdict
        all_task_ids = sorted({m["task_id"] for m in successful})
        all_langs = sorted({m["language_mode"] for m in successful})
        per_pair: dict[tuple[str, str], dict[str, set[str]]] = _defaultdict(
            lambda: {"tasks": set(), "langs": set()})
        for m in successful:
            model_short = m["model_short"]
            display_model = _DISPLAY_RENAME.get(model_short, model_short)
            effort = m.get("effort_level")
            variant = f"{display_model}-{effort}" if effort else display_model
            cli = m.get("claude_code_version") or "?"
            bucket = per_pair[(variant, cli)]
            bucket["tasks"].add(m["task_id"])
            bucket["langs"].add(m["language_mode"])
        if per_pair:
            def _cell(observed: set[str], universe: list[str]) -> str:
                if set(observed) == set(universe):
                    return "All"
                return ", ".join(sorted(observed))
            legend = [
                "| Variant label | CLI version | Tasks | Languages |",
                "|---------------|-------------|-------|-----------|",
            ]
            for (variant, cli) in sorted(per_pair):
                bucket = per_pair[(variant, cli)]
                tasks_cell = _cell(bucket["tasks"], all_task_ids)
                langs_cell = _cell(bucket["langs"], all_langs)
                legend.append(
                    f"| {variant} | {cli} | {tasks_cell} | {langs_cell} |"
                )
            notes_sections.append(("CLI Version Legend", legend))

    # ── Build/refresh judge-consistency-data.md + LLM conclusions ──
    # Prefer a fresh run: if per-judge cache files exist for this run,
    # rebuild the data .md (which includes its own LLM Quality Analysis)
    # and call the merged Conclusions generator (quality+speed+cost
    # integrated). Both cached in conclusions-cache.json so regens are
    # cheap when the underlying data hasn't changed.
    conclusions = {"conclusions": None, "judge_consistency_summary": None}
    has_panel_data = any(
        (p / "test-quality-haiku45.json").exists() or
        (p / "test-quality-gemini31pro.json").exists() or
        (p / "deliverable-quality-haiku45.json").exists() or
        (p / "deliverable-quality-gemini31pro.json").exists()
        for p in (run_dir / "tasks").glob("*/*")
    )
    if has_panel_data:
        print(f"  [{run_dir.name}] panel data detected — building "
              "judge-consistency-data.md (may invoke Opus-max for "
              "Quality Analysis)...", file=sys.stderr, flush=True)
        try:
            from judge_consistency_report import build_report as _build_jc
            data_md = _build_jc(run_dir)
            (run_dir / "judge-consistency-data.md").write_text(data_md)
            print(f"  [{run_dir.name}] judge-consistency-data.md "
                  "written.", file=sys.stderr, flush=True)
        except Exception as e:
            print(f"  (judge-consistency-data.md not written: {e})",
                  file=sys.stderr)

        # Per-run reports do NOT invoke the merged Conclusions LLM —
        # that section is produced only for combined cross-run reports
        # (see combine_results.py) where comparing multiple run dirs
        # actually surfaces tradeoffs worth prose. Passing
        # `speed_cost_input=None` below short-circuits the Conclusions
        # call in conclusions_report.generate_conclusions_from_inputs
        # while still generating the Judge Consistency Summary (which
        # only needs data_md).
        print(f"  [{run_dir.name}] invoking JCS Summary (Opus-max, "
              "cached by input hash)...",
              file=sys.stderr, flush=True)
        try:
            from conclusions_report import generate_conclusions
            conclusions = generate_conclusions(
                run_dir, speed_cost_input=None,
                repo_root=Path(__file__).parent.resolve())
            entry = conclusions.get("judge_consistency_summary")
            if entry and entry.get("text"):
                cached = " (cached)" if entry.get("from_cache") else ""
                print(f"    judge_consistency_summary: "
                      f"{entry.get('input_tokens', 0)}in/"
                      f"{entry.get('output_tokens', 0)}out "
                      f"${entry.get('cost_usd', 0):.4f}{cached}",
                      file=sys.stderr, flush=True)
            else:
                print(f"    judge_consistency_summary: (empty/failed)",
                      file=sys.stderr, flush=True)
        except Exception as e:
            print(f"  (JCS generation failed: {e})", file=sys.stderr)

    # Judge Consistency Summary in Notes (shortened — "What we can trust"
    # moved up to Conclusions > Quality). Pulls from the LLM output if
    # available; otherwise notes-section is skipped.
    jcs = conclusions.get("judge_consistency_summary")
    if jcs and jcs.get("text"):
        prov_bullets = [
            f"- **Model:** `{jcs.get('model', '?')}` at effort "
            f"`{jcs.get('effort', '?')}` via the Claude CLI"
            f"{' (from cache)' if jcs.get('from_cache') else ''}.",
            "- **Inputs:** the [`judge-consistency-data.md`]"
            "(judge-consistency-data.md) tables plus benchmark context "
            "(rubrics, task list, experiment setup).",
            "- **Script:** [`conclusions_report.py`]"
            "(../../conclusions_report.py) — regenerate with "
            "`python3 generate_results.py <run_dir>`.",
            "- **Instruction:** [`JUDGE_CONSISTENCY_SUMMARY_SYSTEM_PROMPT`]"
            "(../../judge_consistency_report.py) in that script.",
            f"- **Usage:** {jcs.get('input_tokens', 0)} input + "
            f"{jcs.get('output_tokens', 0)} output tokens, "
            f"${jcs.get('cost_usd', 0):.4f}.",
        ]
        notes_sections.append(("Judge Consistency Summary", [
            jcs["text"],
            "",
            "#### Provenance",
            "",
            *prov_bullets,
            "",
            "*Full breakdown with per-model / per-language / "
            "per-language×model ranking tables and disagreement "
            "hotspots in [judge-consistency-data.md]"
            "(judge-consistency-data.md).*",
        ]))

    if notes_sections:
        lines.append("## Notes")
        lines.append("")
        for subtitle, subtext in notes_sections:
            lines.append(f"### {subtitle}")
            lines.append("")
            lines.extend(subtext)
            lines.append("")

    lines.append("---")
    # Determine the instructions version from the run data, not from the
    # current generate_results.py constant (which may have moved on to a
    # newer version since these runs were executed).
    run_versions = sorted(set(
        m.get("instructions_version", "?") for m in all_metrics if m.get("instructions_version")))
    run_ver_str = ", ".join(run_versions) if run_versions else "unknown"
    lines.append(f"*Generated by generate_results.py — benchmark instructions {run_ver_str}*")

    # ── Build Conclusions section (if LLM output available) ──
    # Populated here so it can go immediately after the header via the
    # _CONCLUSIONS_MARKER placeholder. The merged Conclusions integrates
    # quality + speed + cost tradeoffs in one prose block — no
    # subheadings.
    def _prov_line(entry: dict | None, prompt_anchor: str) -> str | None:
        if not entry:
            return None
        return (
            "*Provenance:* "
            f"`{entry.get('model', '?')}` at effort "
            f"`{entry.get('effort', '?')}` via Claude CLI"
            f"{' (from cache)' if entry.get('from_cache') else ''}; "
            f"{entry.get('input_tokens', 0)} in / "
            f"{entry.get('output_tokens', 0)} out tokens, "
            f"${entry.get('cost_usd', 0):.4f}. "
            f"Prompt: [`{prompt_anchor.rsplit('#', 1)[0].split('/')[-1]}"
            f"`]({prompt_anchor})."
        )

    merged = conclusions.get("conclusions")
    conclusions_block: list[str] = []
    if merged and merged.get("text"):
        conclusions_block.append("## Conclusions")
        conclusions_block.append("")
        conclusions_block.append(merged["text"])
        conclusions_block.append("")
        prov = _prov_line(merged, "../../conclusions_report.py")
        if prov:
            conclusions_block.append(prov)
        conclusions_block.append("")
    conclusions_md = "\n".join(conclusions_block)

    # ── Build Scoring section (renders between ToC and Conclusions) ──
    # Defines each scored axis, its dimensions, and how Duration/Cost
    # ratios map to tier letters. `_fmt_bands()` is defined where the
    # ratio bands themselves are computed; we only build the Scoring
    # block here if cmp_rows had content so bands exist.
    scoring_block: list[str] = []
    if cmp_rows:
        scoring_block = [
            "## Scoring",
            "",
            "Judges: panel of LLM-as-judge models — `haiku-4-5` (via Claude CLI) and `Gemini 3.1 Pro (High)` (via the Antigravity `agy` CLI). Each run's quality score is the mean of both judges, cached per-run so numbers are deterministic across regenerations. Known bias caveats live in the [Judge Consistency Summary](#judge-consistency-summary).",
            "",
            "**Tests Quality** = Overall score (1-5) for the generated **test code**.",
            "",
            "Dimensions:",
            "- **coverage** — requirements tested",
            "- **rigor** — edge cases + error paths",
            "- **design** — fixture quality + independence",
            "- **overall** — holistic",
            "",
            "**Workflow Craft** = Overall score (1-5) for the produced **deliverable** (workflow YAML + scripts, excluding tests).",
            "",
            "Dimensions:",
            "- **best_practices** — language-appropriate conventions",
            "- **conciseness** — penalizes dead code AND repetition that should be factored",
            "- **readability** — clarity for a reader encountering it cold",
            "- **maintainability** — modularity, error-handling, testability",
            "- **overall** — holistic",
            "",
            "**Duration / Cost** = ratio of each combo's average to the best combo's average on the same axis (lower is better).",
            "",
            "Properties:",
            "- **Scale:** ratios, not raw seconds or dollars",
            "- **Band calibration:** auto-calibrated to the data's best-to-worst spread via log-equal division (`boundary_i = max_ratio^(i/12)`), so the best observed ratio lands at A+ and the worst at D-",
            "- **F band:** reserved for ratios beyond the observed worst",
            "",
            "### Duration columns",
            "",
            "Every Duration figure in this report derives from `timing.grand_total_duration_ms` in `metrics.json` — wall-clock seconds from CLI invocation to the final assistant turn (agent thinking + tool execution + hooks).",
            "",
            "- **Duration** (single run): that one run's wall clock. Appears in the [Failed / Timed-Out Runs](#failed--timed-out-runs) and per-run detail tables.",
            "- **Avg Duration** (in the [Comparison by Language/Model/Effort](#comparison-by-languagemodeleffort) table; also drives the [Tiers](#tiers-by-languagemodeleffort) Duration column): arithmetic mean of `Duration` over the runs in that combo, excluding failed/timed-out runs.",
            "- **Avg Duration Net of Traps** (in the Comparison table only): mean of (per-run `Duration` − that run's `Time Lost`), where `Time Lost` is the trap detector's estimate of seconds spent on detected anti-patterns (see [Trap Descriptions](#trap-descriptions) and the trap-table [Column Definitions](#column-definitions) for the trap list and how Time Lost is computed). Reads as a counterfactual: roughly how fast each combo would have been without the detected traps.",
            "- The **Tier table's Duration column** shows the tier letter (A+..F) for the combo's gross **Avg Duration** ratio. Net of Traps does not feed the tier band.",
            "",
        ]
    scoring_md = "\n".join(scoring_block)

    # ── Build TOC and substitute into the placeholder slot ──
    # Scan `## ` (H2) and `### ` (H3) headings; H3 entries indent one
    # level under their preceding H2. GitHub flavoured Markdown anchors
    # lowercase the heading, replace spaces with hyphens, and strip most
    # punctuation. We scan AFTER the conclusions + scoring blocks are
    # assembled so their headings are picked up for the TOC.
    all_lines = []
    for line in lines:
        if line == _CONCLUSIONS_MARKER:
            all_lines.extend(conclusions_md.splitlines())
        elif line == _SCORING_MARKER:
            all_lines.extend(scoring_md.splitlines())
        else:
            all_lines.append(line)
    toc_lines = ["## Table of Contents", ""]
    for line in all_lines:
        if line.startswith("## ") and line != "## Table of Contents":
            title = line[3:].strip()
            slug = re.sub(r"[^\w\s-]", "", title.lower()).strip()
            slug = re.sub(r"[\s_]+", "-", slug)
            toc_lines.append(f"- [{title}](#{slug})")
        elif line.startswith("### "):
            title = line[4:].strip()
            slug = re.sub(r"[^\w\s-]", "", title.lower()).strip()
            slug = re.sub(r"[\s_]+", "-", slug)
            toc_lines.append(f"  - [{title}](#{slug})")
    toc_lines.append("")
    toc_md = "\n".join(toc_lines)

    text = "\n".join(all_lines).replace(_TOC_MARKER, toc_md)
    (run_dir / "results.md").write_text(text)


# ---------------------------------------------------------------------------
# README index
# ---------------------------------------------------------------------------

def update_readme(repo_root: Path) -> None:
    """Update README.md with a table linking to every run's results.md."""
    results_dir = repo_root / "results"
    if not results_dir.exists():
        return

    # Only treat subdirs that look like a benchmark run (have a
    # tasks/ tree or a run-manifest.json) as runs. Ancillary dirs like
    # results/analysis/ — which carries follow-up markdown, not a run
    # — would otherwise show up in the Benchmark Runs table as a
    # garbage row (`0/?`, no cost, no link).
    runs: list[dict] = []
    for d in sorted(results_dir.iterdir(), reverse=True):
        if not d.is_dir() or d.name.startswith("."):
            continue
        if not ((d / "tasks").is_dir() or (d / "run-manifest.json").exists()):
            continue
        results_md = d / "results.md"
        manifest = d / "run-manifest.json"
        n_metrics = len(list(d.glob("tasks/*/*/metrics.json")))
        info: dict = {"dir": d.name, "n_runs": n_metrics, "link": f"results/{d.name}/results.md"}
        if manifest.exists():
            try:
                mf = json.loads(manifest.read_text())
                info["total_planned"] = mf.get("total_runs", "?")
                info["version"] = mf.get("instructions_version", "?")
                info["cost"] = mf.get("total_cost_usd", 0)
                info["started"] = mf.get("started_at", "")[:19]
            except Exception:
                pass
        if results_md.exists():
            info["has_results"] = True
        else:
            info["has_results"] = False
        runs.append(info)

    if not runs:
        return

    # Build the table
    table_lines = []
    table_lines.append("<!-- BEGIN BENCHMARK RUNS -->")
    table_lines.append("| Run | Version | Runs | Cost | Results |")
    table_lines.append("|-----|---------|------|------|---------|")
    for i, r in enumerate(runs):
        name = r["dir"]
        if i == 0:
            name = f"**{name}** (latest)"
        ver_raw = r.get("version", "?")
        # Linkify version to the instructions doc
        ver_links = {"v1": "benchmark-instructions-v1.md", "v2": "benchmark-instructions-v2.md", "v3": "benchmark-instructions-v3.md", "v4": "benchmark-instructions-v4.md"}
        ver = f"[{ver_raw}]({ver_links[ver_raw]})" if ver_raw in ver_links else ver_raw
        count = f"{r['n_runs']}/{r.get('total_planned', '?')}"
        cost = f"${r.get('cost', 0):.2f}" if r.get("cost") else "—"
        link = f"[results.md]({r['link']})" if r.get("has_results") else "—"
        table_lines.append(f"| {name} | {ver} | {count} | {cost} | {link} |")
    table_lines.append("<!-- END BENCHMARK RUNS -->")

    # Update README.md — replace between markers or append
    readme_path = repo_root / "README.md"
    if readme_path.exists():
        content = readme_path.read_text()
    else:
        content = "# GHA-bench\n\n"

    begin = "<!-- BEGIN BENCHMARK RUNS -->"
    end = "<!-- END BENCHMARK RUNS -->"
    if begin in content and end in content:
        before = content[:content.index(begin)]
        after = content[content.index(end) + len(end):]
        new_content = before + "\n".join(table_lines) + after
    else:
        # Append section
        new_content = content.rstrip() + "\n\n## Benchmark Runs\n\n" + "\n".join(table_lines) + "\n"

    # Keep the "Latest results" link in the subtitle current. Prefer the
    # most recently modified combined-report MD at the top level of
    # results/ (if it's newer than the newest per-run results.md), since
    # combined reports are the most current analytical artefact once
    # they exist. Fall back to the newest per-run results.md otherwise.
    combined_candidates = list(results_dir.glob("results_*.md"))
    newest_combined = max(combined_candidates,
                          key=lambda p: p.stat().st_mtime,
                          default=None)
    newest_run_results = None
    if runs and runs[0].get("has_results"):
        newest_run_results = repo_root / runs[0]["link"]
    latest_link = None
    if (newest_combined is not None
            and (newest_run_results is None
                 or newest_combined.stat().st_mtime
                    >= newest_run_results.stat().st_mtime)):
        latest_link = f"results/{newest_combined.name}"
    elif newest_run_results is not None:
        latest_link = runs[0]["link"]
    if latest_link:
        new_content = re.sub(
            r"\*\*\[Latest results\]\([^)]*\)\*\*",
            f"**[Latest results]({latest_link})**",
            new_content,
        )

    readme_path.write_text(new_content)
    print(f"Updated {readme_path} with {len(runs)} run(s)", file=sys.stderr)


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def _regenerate_run(run_dir: Path) -> None:
    """Load metrics from a run directory and regenerate its results.md."""
    metrics_files = sorted(run_dir.glob("tasks/*/*/metrics.json"))
    if not metrics_files:
        print(f"  Skipping {run_dir.name}: no metrics files", file=sys.stderr)
        return
    all_metrics = []
    for f in metrics_files:
        try:
            all_metrics.append(json.loads(f.read_text()))
        except Exception:
            pass
    # Determine total_runs from manifest or metric count, whichever is larger.
    # The manifest reflects the most recent invocation's plan only; a resumed
    # run that fills in a new effort variant may add metrics beyond the
    # manifest's claim. Using the max keeps the Status line honest.
    manifest_path = run_dir / "run-manifest.json"
    total_runs = len(all_metrics)
    if manifest_path.exists():
        try:
            manifest_total = json.loads(manifest_path.read_text()).get("total_runs", total_runs)
            total_runs = max(total_runs, manifest_total)
        except Exception:
            pass
    generate_results_md(run_dir, all_metrics, total_runs, total_runs)
    print(f"  Generated {run_dir / 'results.md'} ({len(all_metrics)} runs)", file=sys.stderr)


def main():
    repo_root = Path(__file__).parent.resolve()
    results_dir = repo_root / "results"

    if "--update-readme" in sys.argv:
        update_readme(repo_root)
        return

    def _is_run_dir(d: Path) -> bool:
        """A results/ subdir counts as a benchmark run only if it holds a
        tasks/ tree or a run-manifest.json. Ancillary directories like
        results/analysis/ (follow-up markdown, not a run) are skipped."""
        if not d.is_dir() or d.name.startswith("."):
            return False
        return (d / "tasks").is_dir() or (d / "run-manifest.json").exists()

    if "--all" in sys.argv:
        for d in sorted(results_dir.iterdir()):
            if _is_run_dir(d):
                _regenerate_run(d)
        update_readme(repo_root)
        return

    # Specific directory or most recent
    if len(sys.argv) > 1 and not sys.argv[1].startswith("-"):
        target = Path(sys.argv[1])
        if not target.is_absolute():
            target = repo_root / target
    else:
        dirs = sorted(d for d in results_dir.iterdir() if _is_run_dir(d))
        if not dirs:
            print("No results directories found.", file=sys.stderr)
            sys.exit(1)
        target = dirs[-1]

    _regenerate_run(target)
    update_readme(repo_root)


if __name__ == "__main__":
    main()
