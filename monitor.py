#!/usr/bin/env python3
"""monitor.py — live progress + comparative stats for an in-flight benchmark run.

A lightweight, read-only dashboard you run *while* a run is going. It is
distinct from the other run-adjacent tools:

  - `generate_results.py` builds the heavy post-run `results.md` (needs the run
    finished); this only reads whatever `metrics.json` files exist *so far*.
  - `watchdog.sh` supervises the *process* (restarts a crashed runner); this
    reports the *numbers* and never touches the run.

It groups completed cells by `variant` and prints, per variant: run-health
(duration, cost, turns, errors, actionlint, test-exec time), structural
code metrics (impl files/lines, workflow files/lines, total lines — all
non-LLM), structural test metrics (test files/lines, tests, assertions,
assertions/test, test:code ratio — all non-LLM), and live-detected traps.

When the session is authenticated by a Claude subscription (not an API key) it
also shows the **weekly subscription allowance** — the same five-hour + weekly
limits as the CLI's `/usage` command (via GET /api/oauth/usage), annotating
which weekly cap an Opus run draws from. Skipped automatically when no OAuth
credentials are present (API-key auth has no weekly cap); disable with
`--no-usage`. The access token is read locally and never logged.

HEAD-TO-HEAD is automatic and always strongest-vs-strongest: the **most
powerful model+version in the current run** vs the **most powerful in the
previous report** (the newest completed run), matched by task+language at each
shared effort level. Power ranks by family (opus>sonnet>haiku), then version
(4.8>4.7>…), then context window (1m>200k). It also breaks the comparison down
**per scripting language** and flags the languages whose deltas differ
markedly from the cross-language norm.

Override the auto-selection with `--baseline DIR` (which prior run) and/or
`--pair RUNVAR=BASEVAR` (exact variant pairing). For full cross-model rollups
use `combine_results.py` post-run.

Usage:
  python3 monitor.py [RUN_DIR] [options]

    RUN_DIR                  results/<timestamp> (default: newest run dir).
    --baseline DIR           prior run dir (default: newest *completed* run
                             before RUN_DIR; pass "none" to skip head-to-head).
    --pair RUNVAR=BASEVAR    force an exact variant pairing (repeatable);
                             disables the automatic strongest-vs-strongest pick.
    --total N                expected total cell count -> %% + pace-based ETA.
    --watch SECS             refresh every SECS until Ctrl-C.
    --no-usage               skip the subscription weekly-allowance lookup.

Examples:
  python3 monitor.py --total 140 --watch 30
  python3 monitor.py results/2026-06-26_103905 --total 140
  python3 monitor.py results/2026-06-26_103905 --baseline results/2026-05-06_173435
"""
from __future__ import annotations
import argparse, glob, json, math, os, re, statistics, sys, time, datetime, collections
import urllib.request, urllib.error
from pathlib import Path

# Claude Code subscription credentials + the endpoint the `/usage` command uses.
DEFAULT_CREDS = Path.home() / ".claude" / ".credentials.json"
USAGE_PATH = "/api/oauth/usage"

try:
    from test_quality import compute_structural_metrics
except Exception:
    compute_structural_metrics = None
try:
    from generate_results import _detect_traps
except Exception:
    _detect_traps = None

LANG_OUTLIER_PP = 25.0  # a per-language delta is "notable" if it deviates from
                        # the cross-language mean by at least this many points.


# ── loading ────────────────────────────────────────────────────────────────
def newest_run_dir(results_root: Path) -> Path | None:
    dirs = [p for p in results_root.glob("*") if p.is_dir() and (p / "tasks").exists()]
    return max(dirs, key=lambda p: p.name) if dirs else None


def previous_report_dir(results_root: Path, current: Path) -> Path | None:
    """Newest *completed* run (has summary.json) older than `current`."""
    done = [p for p in results_root.glob("*")
            if p.is_dir() and (p / "summary.json").exists() and p.name < current.name]
    return max(done, key=lambda p: p.name) if done else None


def load_cells(run_dir: Path) -> list[dict]:
    out = []
    for mf in run_dir.glob("tasks/*/*/metrics.json"):
        try:
            d = json.loads(mf.read_text())
        except Exception:
            continue
        d["_dir"] = str(mf.parent)
        out.append(d)
    return out


def group_by_variant(cells: list[dict]) -> dict[str, list[dict]]:
    g: dict[str, list[dict]] = collections.defaultdict(list)
    for d in cells:
        g[d.get("variant", "?")].append(d)
    return dict(sorted(g.items()))


# ── model power ranking (unit-tested) ────────────────────────────────────────
def model_power(model_id: str) -> tuple:
    """Rank a model id by (family, version, context-window). Higher = stronger.

    e.g. claude-opus-4-8[1m] -> (3, 4.8, 2);  claude-opus-4-7 -> (3, 4.7, 1);
         claude-sonnet-4-6[1m] -> (2, 4.6, 2);  claude-haiku-4-5 -> (1, 4.5, 1).
    """
    s = (model_id or "").lower()
    fam = 3 if "opus" in s else 2 if "sonnet" in s else 1 if "haiku" in s else 0
    m = re.search(r"(\d+)-(\d+)", s)          # "4-8" -> 4.8
    ver = float(f"{m.group(1)}.{m.group(2)}") if m else 0.0
    ctx = 2 if "[1m]" in s else 1
    return (fam, ver, ctx)


def strongest_model_short(cells: list[dict]) -> str | None:
    """The model_short of the most powerful model present in `cells`."""
    best = None
    for d in cells:
        ms = d.get("model_short")
        if not ms:
            continue
        p = model_power(d.get("model", ""))
        if best is None or p > best[1]:
            best = (ms, p)
    return best[0] if best else None


def select(cells: list[dict], model_short: str, effort=None) -> list[dict]:
    return [d for d in cells if d.get("model_short") == model_short
            and (effort is None or d.get("effort_level") == effort)]


def efforts_of(cells: list[dict], model_short: str) -> list[str]:
    es = {d.get("effort_level") for d in select(cells, model_short)}
    order = {"low": 0, "medium": 1, "high": 2, "xhigh": 3, "max": 4, "ultracode": 5, None: 9}
    return sorted((e for e in es), key=lambda e: order.get(e, 9))


# ── pure aggregation (unit-tested) ───────────────────────────────────────────
def _dur(d): return d.get("timing", {}).get("grand_total_duration_ms", 0) / 60000
def _cost(d): return d.get("cost", {}).get("total_cost_usd", 0)
def _turns(d): return d.get("timing", {}).get("num_turns", 0)
def _testsec(d): return d.get("tool_use_timing", {}).get("test_duration_ms", 0) / 1000
def _errs(d): return d.get("quality", {}).get("error_count", 0)


def _mean(vals):
    vals = [v for v in vals if v is not None]
    return statistics.mean(vals) if vals else 0


def _geomean(vals) -> float:
    """Geometric mean over the positive values; 0.0 if none."""
    pos = [v for v in vals if v > 0]
    if not pos:
        return 0.0
    return math.exp(sum(math.log(v) for v in pos) / len(pos))


def aggregate(cells: list[dict]) -> dict:
    if not cells:
        return {"n": 0}
    return {
        "n": len(cells),
        "ok": sum(1 for d in cells if d.get("run_success")),
        "fail": sum(1 for d in cells if not d.get("run_success")),
        # Geometric mean (issue #33): outlier-damped vs. a plain average.
        # Duration pools successful cells + timeouts (a timeout ran at
        # LEAST that long — right-censored, not droppable without
        # rewarding it with a better average). Cost/turns exclude ALL
        # failed cells (a SIGKILL'd timeout records cost=0/turns=0 —
        # missing data, not a real zero).
        "dur": _geomean([_dur(d) for d in cells
                         if d.get("run_success") or d.get("failure_reason") == "timeout"]),
        "cost": _geomean([_cost(d) for d in cells if d.get("run_success")]),
        "turns": _geomean([_turns(d) for d in cells if d.get("run_success")]),
        "testsec": _mean([_testsec(d) for d in cells]),
        "errors": sum(_errs(d) for d in cells),
        "actionlint_pass": sum(1 for d in cells if d.get("quality", {}).get("actionlint_pass") is True),
    }


def match_pairs(run_cells, base_cells, key=("task_id", "language_mode")):
    """Pair cells across two runs by the given key tuple. Pure."""
    def k(d): return tuple(d.get(f) for f in key)
    base = {k(d): d for d in base_cells}
    return [(d, base[k(d)]) for d in run_cells if k(d) in base]


def flag_outliers(by_lang: dict[str, float], z=1.5, min_pp=LANG_OUTLIER_PP):
    """Languages whose value differs *significantly* from the cross-language norm.

    A language is flagged when its deviation from the mean is at least both
    `z` population-standard-deviations AND `min_pp` absolute points — so we
    don't flag a tight cluster (large z but tiny absolute spread) or a single
    modest gap in a noisy set. Needs >=3 languages for a meaningful spread.

    Returns [(lang, value, mean)] sorted by absolute deviation, biggest first.
    """
    vals = [v for v in by_lang.values() if v is not None]
    if len(vals) < 3:
        return []
    mu = statistics.mean(vals)
    sd = statistics.pstdev(vals)
    if sd == 0:
        return []
    cut = max(z * sd, min_pp)
    out = [(L, v, mu) for L, v in by_lang.items() if v is not None and abs(v - mu) >= cut]
    return sorted(out, key=lambda t: -abs(t[1] - t[2]))


# ── file-based stats (best-effort) ───────────────────────────────────────────
def structural(cell: dict) -> dict:
    # total_lines here is the authored-code total = impl + test + workflow
    # (from compute_structural_metrics.code_lines), NOT the runner's
    # code_metrics.total_lines (which also counts fixtures/README/act-result.txt).
    out = {"impl_files": None, "impl_lines": None, "test_files": None,
           "test_lines": None, "tests": None, "asserts": None, "apt": None,
           "tc": None, "wf_files": 0, "wf_lines": 0,
           "total_files": cell.get("code_metrics", {}).get("file_count"),
           "total_lines": None}
    gc = Path(cell.get("_dir", "")) / "generated-code"
    if compute_structural_metrics and gc.exists():
        try:
            s = compute_structural_metrics(gc)
            out.update(impl_files=s.get("impl_file_count"), impl_lines=s.get("impl_lines"),
                       test_files=s.get("test_file_count"), test_lines=s.get("test_lines"),
                       tests=s.get("test_count"), asserts=s.get("assertion_count"),
                       apt=s.get("assertions_per_test"), tc=s.get("test_to_code_ratio"),
                       wf_files=s.get("workflow_file_count"), wf_lines=s.get("workflow_lines"),
                       total_lines=s.get("code_lines"))
        except Exception:
            pass
    return out


def traps(cells: list[dict]):
    cw = 0; tot = 0.0; names = collections.Counter()
    if _detect_traps is None:
        return cw, 0.0, names
    for d in cells:
        cli = Path(d.get("_dir", "")) / "cli-output.json"
        con = Path(d.get("_dir", "")) / "console-log.txt"
        try:
            if not cli.exists() or cli.stat().st_size > 25_000_000:
                continue
            tr = _detect_traps(json.loads(cli.read_text()),
                               con.read_text() if con.exists() else "", d)
        except Exception:
            continue
        if tr:
            cw += 1
            for t in tr:
                tot += t.get("time_s", 0); names[t.get("name", "?")] += 1
    return cw, tot / 60.0, names


# ── subscription weekly allowance (best-effort) ──────────────────────────────
def fetch_usage(creds_path: Path = DEFAULT_CREDS, base_url: str | None = None,
                timeout: float = 5.0) -> dict | None:
    """Best-effort subscription usage via GET /api/oauth/usage (the same endpoint
    the CLI's `/usage` command uses). Returns the parsed JSON (with a
    `subscription` key added), `{"error": ...}` on a failed call, or None when
    not applicable (no OAuth credentials -> e.g. API-key auth, no weekly cap).
    Never returns or logs the access token.
    """
    try:
        oauth = json.loads(creds_path.read_text()).get("claudeAiOauth", {})
    except Exception:
        return None
    tok = oauth.get("accessToken")
    if not tok:
        return None
    base = (base_url or os.environ.get("ANTHROPIC_BASE_URL", "https://api.anthropic.com")).rstrip("/")
    req = urllib.request.Request(base + USAGE_PATH, headers={
        "Authorization": f"Bearer {tok}",
        "anthropic-beta": "oauth-2025-04-20",
        "anthropic-version": "2023-06-01",
        "User-Agent": "gha-bench-monitor",
    })
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            data = json.loads(r.read().decode())
    except urllib.error.HTTPError as e:
        hint = " (token expired — run any `claude` command to refresh)" if e.code == 401 else ""
        return {"error": f"HTTP {e.code}{hint}", "subscription": oauth.get("subscriptionType")}
    except Exception as e:
        return {"error": str(e)[:80], "subscription": oauth.get("subscriptionType")}
    data["subscription"] = oauth.get("subscriptionType")
    return data


def _short_ts(ts):
    try:
        return datetime.datetime.fromisoformat(str(ts).replace("Z", "+00:00")).strftime("%a %b %d %H:%M UTC")
    except Exception:
        return str(ts) if ts else "?"


def format_usage(raw: dict | None) -> list[str]:
    """Render the subscription weekly/5h allowance. Pure (no I/O). [] if N/A."""
    if not raw or not isinstance(raw, dict):
        return []
    sub = raw.get("subscription")
    head = f"Subscription allowance{f' ({sub})' if sub else ''}:"
    if raw.get("error"):
        return [f"{head} unavailable — {raw['error']}"]
    lines = [head]
    limits = raw.get("limits") or []
    if limits:
        for lim in limits:
            grp, kind, pct = lim.get("group"), lim.get("kind"), lim.get("percent")
            scope = (lim.get("scope") or {}).get("model") or {}
            mdl = scope.get("display_name")
            sev = lim.get("severity")
            tag = ""
            if grp == "weekly":
                tag = f"  (scoped: {mdl})" if mdl else "  (all models — the weekly cap an Opus run draws from)"
            sevtag = f"  [{sev}]" if sev and sev != "normal" else ""
            label = f"{kind}{f'/{mdl}' if mdl else ''}"
            lines.append(f"  {label:<22}{pct:>3}%  resets {_short_ts(lim.get('resets_at'))}{tag}{sevtag}")
    else:  # fallback to typed fields if `limits` absent
        for key, label in [("five_hour", "5-hour"), ("seven_day", "weekly (all)"),
                           ("seven_day_opus", "weekly (Opus)"), ("seven_day_sonnet", "weekly (Sonnet)")]:
            v = raw.get(key)
            if isinstance(v, dict) and v.get("utilization") is not None:
                lines.append(f"  {label:<22}{v['utilization']:>3.0f}%  resets {_short_ts(v.get('resets_at'))}")
    eu = raw.get("extra_usage")
    if isinstance(eu, dict) and eu.get("is_enabled"):
        dp = eu.get("decimal_places", 2) or 0
        div = 10 ** dp
        lim = (eu.get("monthly_limit") or 0) / div
        used = eu.get("used_credits") or 0
        cur = eu.get("currency", "USD")
        lines.append(f"  {'extra-usage':<22}      {cur} {used:.2f} / {lim:.2f} monthly (enabled)")
    return lines


# ── rendering ────────────────────────────────────────────────────────────────
def _pct(a, b): return f"{100*(a-b)/b:+.0f}%" if b else "n/a"
def _num(s):
    m = re.search(r"-?\d+(?:\.\d+)?", str(s)); return float(m.group()) if m else 0.0


def render(run_dir, baseline_dir, pairs_map, total, show_usage=True):
    cells = load_cells(run_dir)
    groups = group_by_variant(cells)
    done = len(cells)
    out = [f"GHA-bench monitor · run {run_dir.name} · {datetime.datetime.now():%Y-%m-%d %H:%M}"]
    now = datetime.datetime.now()

    starts = [d.get("timestamp_start") for d in cells if d.get("timestamp_start")]
    elapsed_h = 0.0
    if starts:
        now_utc = datetime.datetime.now(datetime.timezone.utc)
        elapsed_h = (now_utc - datetime.datetime.fromisoformat(min(starts))).total_seconds() / 3600
    pace = done / elapsed_h if elapsed_h else 0
    spend = sum(_cost(d) for d in cells)
    if total:
        eta = ""
        if pace > 0 and done < total:
            eta_dt = now + datetime.timedelta(hours=(total - done) / pace)
            eta = f" · ETA ~{eta_dt:%a %b %d %H:%M} (at current pace; a floor — later tranches run slower)"
        out.append(f"Progress  {done}/{total} ({100*done/total:.0f}%) · ~{pace:.1f} cells/hr · elapsed {elapsed_h:.1f}h{eta}")
    else:
        out.append(f"Progress  {done} cells · ~{pace:.1f} cells/hr · elapsed {elapsed_h:.1f}h")
    out.append(f"Spend     ${spend:.0f} so far")
    if show_usage:
        out.extend(format_usage(fetch_usage()))

    out.append("\nPER-VARIANT SUMMARY (per-cell averages)")
    out.append(f"  {'variant':<22}{'done':>5}{'ok':>4}{'dur':>7}{'cost':>8}{'turns':>6}"
               f"{'tests':>6}{'tst:cd':>7}{'impl_ln':>8}{'wf_ln':>6}{'alint':>7}{'traps':>7}")
    for var, gc in groups.items():
        a = aggregate(gc); ss = [structural(d) for d in gc]; cw, _, _ = traps(gc)
        alint_s = f"{a['actionlint_pass']}/{a['n']}"; traps_s = f"{cw}/{a['n']}"
        out.append(f"  {var:<22}{a['n']:>5}{a['ok']:>4}{a['dur']:>6.1f}m${a['cost']:>6.2f}"
                   f"{a['turns']:>6.0f}{_mean([s['tests'] for s in ss]):>6.0f}"
                   f"{_mean([s['tc'] for s in ss]):>7.1f}{_mean([s['impl_lines'] for s in ss]):>8.0f}"
                   f"{_mean([s['wf_lines'] for s in ss]):>6.0f}{alint_s:>7}{traps_s:>7}")

    if baseline_dir is None:
        return "\n".join(out)
    base_cells = load_cells(baseline_dir)

    if pairs_map:                       # manual override
        bg = group_by_variant(base_cells)
        for rv, bv in pairs_map.items():
            if rv in groups and bv in bg:
                out.append(_h2h_block(rv, bv, groups[rv], bg[bv]))
        return "\n".join(out)

    # automatic strongest-vs-strongest
    scur = strongest_model_short(cells)
    sbase = strongest_model_short(base_cells)
    if not scur or not sbase:
        return "\n".join(out)
    cur_model = next((d.get("model") for d in cells if d.get("model_short") == scur), scur)
    base_model = next((d.get("model") for d in base_cells if d.get("model_short") == sbase), sbase)
    out.append(f"\nHEAD-TO-HEAD  strongest vs strongest  ·  {scur} ({cur_model})  vs  "
               f"{sbase} ({base_model})  [baseline {baseline_dir.name}]")
    shared = [e for e in efforts_of(cells, scur) if e in set(efforts_of(base_cells, sbase))]
    cur_only = [e for e in efforts_of(cells, scur) if e not in set(efforts_of(base_cells, sbase))]
    for eff in shared:
        out.append(_h2h_block(f"{scur}-{eff}", f"{sbase}-{eff}",
                              select(cells, scur, eff), select(base_cells, sbase, eff)))
    if cur_only:
        out.append(f"\n  (current-only efforts with no {sbase} counterpart: {', '.join(str(e) for e in cur_only)} — shown in PER-VARIANT SUMMARY only)")
    out.append(_per_language_block(scur, sbase, select(cells, scur), select(base_cells, sbase)))
    return "\n".join(out)


def _h2h_block(run_var, base_var, run_cells, base_cells):
    pairs = match_pairs(run_cells, base_cells)
    if not pairs:
        return f"\n{run_var} vs {base_var}: no matched task+language pairs yet"
    L = [f"\n{run_var} vs {base_var} — matched task+language pairs (n={len(pairs)})"]
    def row(label, na, ba): L.append(f"    {label:<16}{na:>9}{ba:>9}{_pct(_num(na), _num(ba)):>8}")
    avg = lambda fn, i: _mean([fn(p[i]) for p in pairs])
    rs = [structural(p[0]) for p in pairs]; bs = [structural(p[1]) for p in pairs]
    sa = lambda lst, k: _mean([x[k] for x in lst])
    L.append("    EFFORT / COST")
    row("duration", f"{avg(_dur,0):.1f}m", f"{avg(_dur,1):.1f}m")
    row("cost", f"${avg(_cost,0):.2f}", f"${avg(_cost,1):.2f}")
    row("turns", f"{avg(_turns,0):.0f}", f"{avg(_turns,1):.0f}")
    L.append("    CODE (non-test)")
    row("impl files", f"{sa(rs,'impl_files'):.1f}", f"{sa(bs,'impl_files'):.1f}")
    row("impl lines", f"{sa(rs,'impl_lines'):.0f}", f"{sa(bs,'impl_lines'):.0f}")
    row("workflow lines", f"{sa(rs,'wf_lines'):.0f}", f"{sa(bs,'wf_lines'):.0f}")
    row("total (i+t+wf)", f"{sa(rs,'total_lines'):.0f}", f"{sa(bs,'total_lines'):.0f}")
    L.append("    TESTS")
    row("test files", f"{sa(rs,'test_files'):.1f}", f"{sa(bs,'test_files'):.1f}")
    row("test lines", f"{sa(rs,'test_lines'):.0f}", f"{sa(bs,'test_lines'):.0f}")
    row("tests", f"{sa(rs,'tests'):.0f}", f"{sa(bs,'tests'):.0f}")
    row("assertions", f"{sa(rs,'asserts'):.0f}", f"{sa(bs,'asserts'):.0f}")
    row("assert/test", f"{sa(rs,'apt'):.1f}", f"{sa(bs,'apt'):.1f}")
    row("test:code", f"{sa(rs,'tc'):.1f}", f"{sa(bs,'tc'):.1f}")
    L.append("    RELIABILITY")
    row("run errors/cell", f"{avg(_errs,0):.1f}", f"{avg(_errs,1):.1f}")
    row("test-exec sec", f"{avg(_testsec,0):.0f}s", f"{avg(_testsec,1):.0f}s")
    # traps for BOTH models over the same matched cells (apples-to-apples)
    rc, rm, rn = traps([p[0] for p in pairs])
    bc, bm, bn = traps([p[1] for p in pairs])
    def _t(c, m, n): return (f"{c}/{len(pairs)} cells, ~{m:.0f}min | "
                             f"top: {', '.join(f'{k}x{v}' for k, v in n.most_common(3)) or 'none'}")
    L.append("    TRAPS (matched cells; detectors are the 16 static ones in generate_results._detect_traps)")
    L.append(f"      {run_var:<22}{_t(rc, rm, rn)}")
    L.append(f"      {base_var:<22}{_t(bc, bm, bn)}")
    return "\n".join(L)


# metric -> (extractor, is_structural, fmt) for the per-language table
_LANG_METRICS = [
    ("dur%",  _dur,    False),
    ("cost%", _cost,   False),
    ("turns%", _turns, False),
    ("tests%", "tests", True),
    ("tst:cd%", "tc",  True),
    ("implln%", "impl_lines", True),
]


def per_language_deltas(cur_cells, base_cells):
    """Per-language % deltas (cur vs base) matched by (task, effort). Pure-ish
    (reads structural via structural()). Returns {metric: {lang: pct}}, {lang: n}."""
    langs = sorted({d.get("language_mode") for d in cur_cells} |
                   {d.get("language_mode") for d in base_cells})
    deltas = {m[0]: {} for m in _LANG_METRICS}
    counts = {}
    for L in langs:
        cur_L = [d for d in cur_cells if d.get("language_mode") == L]
        base_L = [d for d in base_cells if d.get("language_mode") == L]
        pairs = match_pairs(cur_L, base_L, key=("task_id", "effort_level"))
        counts[L] = len(pairs)
        if not pairs:
            continue
        rs = [structural(p[0]) for p in pairs]; bs = [structural(p[1]) for p in pairs]
        for name, ex, is_struct in _LANG_METRICS:
            if is_struct:
                a = _mean([r[ex] for r in rs]); b = _mean([r[ex] for r in bs])
            else:
                a = _mean([ex(p[0]) for p in pairs]); b = _mean([ex(p[1]) for p in pairs])
            deltas[name][L] = (100 * (a - b) / b) if b else None
    return deltas, counts


def _per_language_block(scur, sbase, cur_cells, base_cells):
    deltas, counts = per_language_deltas(cur_cells, base_cells)
    langs = [L for L in sorted(counts) if counts[L] > 0]
    if not langs:
        return f"\nPER-LANGUAGE ({scur} vs {sbase}): no matched pairs yet"
    L = [f"\nPER-LANGUAGE  {scur} vs {sbase}  (% delta, matched by task+effort, pooled across shared efforts)"]
    hdr = f"  {'language':<16}{'n':>3}" + "".join(f"{m[0]:>9}" for m in _LANG_METRICS)
    L.append(hdr)
    for lg in langs:
        cells_s = f"{counts[lg]}"
        row = f"  {lg:<16}{cells_s:>3}"
        for name, _, _ in _LANG_METRICS:
            v = deltas[name].get(lg)
            row += f"{(f'{v:+.0f}%' if v is not None else '—'):>9}"
        L.append(row)
    # significant per-language differences
    notes = []
    for name, _, _ in _LANG_METRICS:
        for lg, v, mu in flag_outliers(deltas[name]):
            notes.append(f"{lg} {name} {v:+.0f}% (cross-lang avg {mu:+.0f}%)")
    if notes:
        L.append(f"  Notable per-language differences (≥1.5σ and ≥{int(LANG_OUTLIER_PP)} pts from the cross-language average):")
        for npt in notes[:8]:
            L.append(f"    - {npt}")
    else:
        L.append(f"  No language differs significantly (≥1.5σ, ≥{int(LANG_OUTLIER_PP)} pts) from the cross-language average yet.")
    return "\n".join(L)


def main(argv=None):
    ap = argparse.ArgumentParser(description="Live progress + stats for an in-flight benchmark run.")
    ap.add_argument("run_dir", nargs="?", default=None)
    ap.add_argument("--baseline", default=None, help='prior run dir (default: newest completed; "none" to skip)')
    ap.add_argument("--pair", action="append", default=[], metavar="RUNVAR=BASEVAR")
    ap.add_argument("--total", type=int, default=None)
    ap.add_argument("--watch", type=int, default=None)
    ap.add_argument("--no-usage", action="store_true",
                    help="skip the subscription weekly-allowance lookup (GET /api/oauth/usage)")
    args = ap.parse_args(argv)

    repo = Path(__file__).parent.resolve()
    run_dir = Path(args.run_dir) if args.run_dir else newest_run_dir(repo / "results")
    if not run_dir or not run_dir.exists():
        print("No run directory found under results/.", file=sys.stderr); return 1
    if args.baseline == "none":
        baseline_dir = None
    elif args.baseline:
        baseline_dir = Path(args.baseline)
    else:
        baseline_dir = previous_report_dir(repo / "results", run_dir)
    pairs_map = dict(p.split("=", 1) for p in args.pair if "=" in p)

    def once(): return render(run_dir, baseline_dir, pairs_map, args.total, show_usage=not args.no_usage)

    if args.watch:
        try:
            while True:
                print("\033[2J\033[H" + once(), flush=True); time.sleep(args.watch)
        except KeyboardInterrupt:
            return 0
    print(once()); return 0


if __name__ == "__main__":
    raise SystemExit(main())
