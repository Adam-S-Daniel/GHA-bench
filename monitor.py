#!/usr/bin/env python3
"""monitor.py — live progress + comparative stats for an in-flight benchmark run.

A lightweight, read-only dashboard you run *while* a run is going. It is
distinct from the other run-adjacent tools:

  - `generate_results.py` builds the heavy post-run `results.md` (needs the run
    finished); this only reads whatever `metrics.json` files exist *so far*.
  - `watchdog.sh` supervises the *process* (restarts a crashed runner); this
    reports the *numbers* and never touches the run.

It groups the completed cells by their `variant` (e.g. `opus48-1m-medium`) and
prints, per variant: run-health (duration, cost, turns, errors, actionlint,
hooks, test-exec time), the structural code metrics (impl files/lines, workflow
files/lines, total lines — all non-LLM), the structural test metrics (test
files/lines, tests, assertions, assertions/test, test:code ratio — all
non-LLM), and the time-wasting traps detected live from each cell's event
stream. With `--baseline` it adds a matched task+language head-to-head against a
prior run (use this for re-runs of the same matrix; for cross-model rollups use
`combine_results.py` post-run).

Usage:
  python3 monitor.py [RUN_DIR] [options]

    RUN_DIR                  results/<timestamp> dir. Default: the newest dir
                             under results/ (the in-flight run).
    --baseline DIR           a prior run dir for a matched head-to-head.
    --pair RUNVAR=BASEVAR    compare RUN's variant RUNVAR against the baseline's
                             BASEVAR (repeatable). Use for cross-model pairs
                             like opus48-1m-medium=opus47-1m-medium. Without it,
                             variants present in both dirs are paired by name.
    --total N                expected total cell count -> enables % and an ETA
                             (pace-based: remaining / current cells-per-hour).
    --watch SECS             refresh every SECS until Ctrl-C.

Examples:
  python3 monitor.py
  python3 monitor.py results/2026-06-26_103905 --total 140 --watch 30
  python3 monitor.py results/2026-06-26_103905 --baseline results/2026-05-06_173435 \
      --pair opus48-1m-medium=opus47-1m-medium
"""
from __future__ import annotations
import argparse, glob, json, os, statistics, sys, time, datetime, collections
from pathlib import Path

# Optional, best-effort imports. The metric-dict aggregation works without
# these; only the structural and trap sections degrade gracefully if absent.
try:
    from test_quality import compute_structural_metrics
except Exception:
    compute_structural_metrics = None
try:
    from generate_results import _detect_traps
except Exception:
    _detect_traps = None


# ── loading ────────────────────────────────────────────────────────────────
def newest_run_dir(results_root: Path) -> Path | None:
    dirs = [p for p in results_root.glob("*") if p.is_dir() and (p / "tasks").exists()]
    return max(dirs, key=lambda p: p.name) if dirs else None


def load_cells(run_dir: Path) -> list[dict]:
    """Every completed cell's metrics, each tagged with `_dir` (its cell dir)."""
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


# ── pure aggregation (unit-tested) ───────────────────────────────────────────
def _dur(d): return d.get("timing", {}).get("grand_total_duration_ms", 0) / 60000
def _cost(d): return d.get("cost", {}).get("total_cost_usd", 0)
def _turns(d): return d.get("timing", {}).get("num_turns", 0)
def _testsec(d): return d.get("tool_use_timing", {}).get("test_duration_ms", 0) / 1000


def _mean(vals):
    vals = [v for v in vals if v is not None]
    return statistics.mean(vals) if vals else 0


def aggregate(cells: list[dict]) -> dict:
    """Run-health aggregates over a list of cell metrics. Pure; no file I/O."""
    if not cells:
        return {"n": 0}
    h = lambda k: sum(d.get("hooks", {}).get(k, 0) for d in cells)
    return {
        "n": len(cells),
        "ok": sum(1 for d in cells if d.get("run_success")),
        "fail": sum(1 for d in cells if not d.get("run_success")),
        "dur": _mean([_dur(d) for d in cells]),
        "cost": _mean([_cost(d) for d in cells]),
        "turns": _mean([_turns(d) for d in cells]),
        "testsec": _mean([_testsec(d) for d in cells]),
        "errors": sum(d.get("quality", {}).get("error_count", 0) for d in cells),
        "actionlint_pass": sum(1 for d in cells if d.get("quality", {}).get("actionlint_pass") is True),
        "hook_fires": h("hook_fires"),
        "hook_errs_caught": h("hook_errors_caught"),
        "hook_failures": h("hook_failures"),
    }


def match_pairs(run_cells: list[dict], base_cells: list[dict]) -> list[tuple[dict, dict]]:
    """Pair cells across two runs by (task_id, language_mode). Pure."""
    base = {(d.get("task_id"), d.get("language_mode")): d for d in base_cells}
    pairs = []
    for d in run_cells:
        k = (d.get("task_id"), d.get("language_mode"))
        if k in base:
            pairs.append((d, base[k]))
    return pairs


# ── file-based stats (best-effort) ───────────────────────────────────────────
def structural(cell: dict) -> dict:
    """Structural code + test metrics for one cell (needs generated-code/)."""
    out = {"impl_files": None, "impl_lines": None, "test_files": None,
           "test_lines": None, "tests": None, "asserts": None, "apt": None,
           "tc": None, "wf_files": 0, "wf_lines": 0,
           "total_files": cell.get("code_metrics", {}).get("file_count"),
           "total_lines": cell.get("code_metrics", {}).get("total_lines")}
    gc = Path(cell.get("_dir", "")) / "generated-code"
    if compute_structural_metrics and gc.exists():
        try:
            s = compute_structural_metrics(gc)
            out.update(impl_files=s.get("impl_file_count"), impl_lines=s.get("impl_lines"),
                       test_files=s.get("test_file_count"), test_lines=s.get("test_lines"),
                       tests=s.get("test_count"), asserts=s.get("assertion_count"),
                       apt=s.get("assertions_per_test"), tc=s.get("test_to_code_ratio"))
        except Exception:
            pass
    wf = glob.glob(str(gc / ".github/workflows/*.yml")) + glob.glob(str(gc / ".github/workflows/*.yaml"))
    out["wf_files"] = len(wf)
    out["wf_lines"] = sum(len(open(w, errors="ignore").read().splitlines()) for w in wf) if wf else 0
    return out


def traps(cells: list[dict]):
    """(cells_with_traps, total_minutes_wasted, Counter(names))."""
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


# ── rendering ────────────────────────────────────────────────────────────────
def _pct(a, b): return f"{100*(a-b)/b:+.0f}%" if b else "n/a"


def render(run_dir: Path, baseline_dir: Path | None, pairs_map: dict,
           total: int | None) -> str:
    cells = load_cells(run_dir)
    groups = group_by_variant(cells)
    done = len(cells)
    lines = []
    now = datetime.datetime.now()
    head = f"GHA-bench monitor · run {run_dir.name} · {now:%Y-%m-%d %H:%M}"
    lines.append(head)

    # progress / pace / ETA
    starts = [d.get("timestamp_start") for d in cells if d.get("timestamp_start")]
    elapsed_h = 0.0
    if starts:
        now_utc = datetime.datetime.now(datetime.timezone.utc)
        elapsed_h = (now_utc - datetime.datetime.fromisoformat(min(starts))).total_seconds() / 3600
    pace = done / elapsed_h if elapsed_h else 0
    spend = sum(_cost(d) for d in cells)
    if total:
        pctc = 100 * done / total
        eta = ""
        if pace > 0 and done < total:
            eta_dt = now + datetime.timedelta(hours=(total - done) / pace)
            eta = f" · ETA ~{eta_dt:%a %b %d %H:%M} (at current pace)"
        lines.append(f"Progress  {done}/{total} ({pctc:.0f}%) · ~{pace:.1f} cells/hr · elapsed {elapsed_h:.1f}h{eta}")
    else:
        lines.append(f"Progress  {done} cells done · ~{pace:.1f} cells/hr · elapsed {elapsed_h:.1f}h")
    lines.append(f"Spend     ${spend:.0f} so far")

    # per-variant summary
    lines.append("\nPER-VARIANT SUMMARY (per-cell averages)")
    lines.append(f"  {'variant':<22}{'done':>5}{'ok':>4}{'dur':>7}{'cost':>8}{'turns':>6}"
                 f"{'tests':>6}{'tst:cd':>7}{'impl_ln':>8}{'wf_ln':>6}{'alint':>7}{'traps':>7}")
    for var, gc in groups.items():
        a = aggregate(gc)
        ss = [structural(d) for d in gc]
        cw, _, _ = traps(gc)
        alint_s = f"{a['actionlint_pass']}/{a['n']}"
        traps_s = f"{cw}/{a['n']}"
        lines.append(f"  {var:<22}{a['n']:>5}{a['ok']:>4}{a['dur']:>6.1f}m${a['cost']:>6.2f}"
                     f"{a['turns']:>6.0f}{_mean([s['tests'] for s in ss]):>6.0f}"
                     f"{_mean([s['tc'] for s in ss]):>7.1f}{_mean([s['impl_lines'] for s in ss]):>8.0f}"
                     f"{_mean([s['wf_lines'] for s in ss]):>6.0f}{alint_s:>7}{traps_s:>7}")

    # detailed head-to-head
    if baseline_dir:
        base_cells = load_cells(baseline_dir)
        base_groups = group_by_variant(base_cells)
        # decide which (run_variant, base_variant) pairs to show
        todo = []
        if pairs_map:
            todo = [(rv, bv) for rv, bv in pairs_map.items() if rv in groups and bv in base_groups]
        else:
            todo = [(v, v) for v in groups if v in base_groups]
        for rv, bv in todo:
            lines.append(_h2h_block(rv, bv, groups[rv], base_groups[bv]))
    return "\n".join(lines)


def _h2h_block(run_var, base_var, run_cells, base_cells) -> str:
    pairs = match_pairs(run_cells, base_cells)
    if not pairs:
        return f"\n{run_var} vs {base_var}: no matched task+language pairs yet"
    L = [f"\n{run_var} vs {base_var} — matched task+language pairs (n={len(pairs)})"]
    def row(label, na, ba):
        L.append(f"    {label:<16}{na:>9}{ba:>9}{_pct(_num(na), _num(ba)):>8}")
    def avg(fn, side):
        return _mean([fn(p[0] if side == 0 else p[1]) for p in pairs])
    rs = [structural(p[0]) for p in pairs]; bs = [structural(p[1]) for p in pairs]
    savg = lambda lst, k: _mean([x[k] for x in lst])
    L.append("    EFFORT / COST")
    row("duration", f"{avg(_dur,0):.1f}m", f"{avg(_dur,1):.1f}m")
    row("cost", f"${avg(_cost,0):.2f}", f"${avg(_cost,1):.2f}")
    row("turns", f"{avg(_turns,0):.0f}", f"{avg(_turns,1):.0f}")
    L.append("    CODE (non-test)")
    row("impl files", f"{savg(rs,'impl_files'):.1f}", f"{savg(bs,'impl_files'):.1f}")
    row("impl lines", f"{savg(rs,'impl_lines'):.0f}", f"{savg(bs,'impl_lines'):.0f}")
    row("workflow lines", f"{savg(rs,'wf_lines'):.0f}", f"{savg(bs,'wf_lines'):.0f}")
    row("total lines", f"{savg(rs,'total_lines'):.0f}", f"{savg(bs,'total_lines'):.0f}")
    L.append("    TESTS")
    row("test files", f"{savg(rs,'test_files'):.1f}", f"{savg(bs,'test_files'):.1f}")
    row("test lines", f"{savg(rs,'test_lines'):.0f}", f"{savg(bs,'test_lines'):.0f}")
    row("tests", f"{savg(rs,'tests'):.0f}", f"{savg(bs,'tests'):.0f}")
    row("assertions", f"{savg(rs,'asserts'):.0f}", f"{savg(bs,'asserts'):.0f}")
    row("assert/test", f"{savg(rs,'apt'):.1f}", f"{savg(bs,'apt'):.1f}")
    row("test:code", f"{savg(rs,'tc'):.1f}", f"{savg(bs,'tc'):.1f}")
    L.append("    RELIABILITY")
    ne = _mean([p[0].get('quality',{}).get('error_count',0) for p in pairs])
    be = _mean([p[1].get('quality',{}).get('error_count',0) for p in pairs])
    row("run errors/cell", f"{ne:.1f}", f"{be:.1f}")
    row("test-exec sec", f"{avg(_testsec,0):.0f}s", f"{avg(_testsec,1):.0f}s")
    cw, mins, names = traps(run_cells)
    L.append(f"    traps: {cw}/{len(run_cells)} cells, ~{mins:.0f}min wasted | "
             f"top: {', '.join(f'{k}x{v}' for k, v in names.most_common(3)) or 'none'}")
    return "\n".join(L)


def _num(s):
    """Pull the leading number out of a rendered cell like '8.3m' or '$2.00'."""
    import re
    m = re.search(r"-?\d+(?:\.\d+)?", str(s))
    return float(m.group()) if m else 0.0


def main(argv=None):
    ap = argparse.ArgumentParser(description="Live progress + stats for an in-flight benchmark run.")
    ap.add_argument("run_dir", nargs="?", default=None, help="results/<timestamp> (default: newest)")
    ap.add_argument("--baseline", default=None, help="prior run dir for matched head-to-head")
    ap.add_argument("--pair", action="append", default=[], metavar="RUNVAR=BASEVAR",
                    help="explicit variant pairing (repeatable)")
    ap.add_argument("--total", type=int, default=None, help="expected total cells (enables %% + ETA)")
    ap.add_argument("--watch", type=int, default=None, help="refresh every N seconds")
    args = ap.parse_args(argv)

    repo = Path(__file__).parent.resolve()
    run_dir = Path(args.run_dir) if args.run_dir else newest_run_dir(repo / "results")
    if not run_dir or not run_dir.exists():
        print("No run directory found under results/.", file=sys.stderr)
        return 1
    baseline_dir = Path(args.baseline) if args.baseline else None
    pairs_map = dict(p.split("=", 1) for p in args.pair if "=" in p)

    def once():
        return render(run_dir, baseline_dir, pairs_map, args.total)

    if args.watch:
        try:
            while True:
                print("\033[2J\033[H" + once(), flush=True)
                time.sleep(args.watch)
        except KeyboardInterrupt:
            return 0
    else:
        print(once())
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
