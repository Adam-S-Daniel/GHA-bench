#!/usr/bin/env python3
"""Report-time recovery of a timed-out cell's true API spend.

Timed-out benchmark cells (`failure_reason == "timeout"`) get SIGKILLed
mid-run, so the CLI process is killed before it ever emits its final
`result` event — the one that carries the authoritative `total_cost_usd`.
As a result `metrics.json` records `cost.total_cost_usd = 0` (and
`num_turns = 0`) for those cells, even though real API calls — and real
spend — happened before the kill.

This module reconstructs a FLOOR (lower-bound) estimate of that spend
from the partial `cli-output.json` event stream still on disk in the
cell's directory:

  - input / cache-read / cache-write token counts are EXACT — they come
    from per-message `usage` snapshots the CLI emits as it streams, and
    have been validated penny-exact against the CLI's own cost math on
    cells that ran to completion.
  - output tokens are only PARTIALLY observable: visible text/tool_use
    content is counted in full, but "thinking" output is mostly invisible
    in a killed stream (only occasional `thinking_tokens` telemetry
    events survive it), so the output-token estimate — and therefore the
    total cost — is a conservative lower bound, never an exact figure.

This is report-time-only: nothing here ever writes to disk or mutates
`results/` (a committed, immutable archive). `runner.py` observes and
records; it never estimates — recovery only happens when
`generate_results.py` / `combine_results.py` build a report.
"""
import json
from pathlib import Path

from models import COST_PER_MTOK


def normalize_model_id(model_id: str) -> str | None:
    """Map a stream-observed model id to a COST_PER_MTOK key.

    Streams carry dated ids (`claude-haiku-4-5-20251001`) and the result
    record carries `[1m]` suffixes; pricing is identical for `[1m]`
    variants, and dated ids strip to their base entry. None if unknown.
    """
    if model_id in COST_PER_MTOK:
        return model_id
    base, _, tail = model_id.rpartition("-")
    if tail.isdigit() and len(tail) == 8 and base in COST_PER_MTOK:
        return base
    if model_id.endswith("]") and "[" in model_id:
        stripped = model_id[: model_id.index("[")]
        if stripped in COST_PER_MTOK:
            return stripped
    return None


# Conservative chars-per-token divisor for output-token floor estimation.
_CHARS_PER_TOKEN = 4.0


def recover_timeout_cost(cell_dir: Path) -> float | None:
    """Best-effort floor estimate (USD) of a killed cell's true API spend,
    derived from the partial `cli-output.json` event stream. None when the
    stream is missing/unparseable/has no usage data.
    """
    try:
        events = json.loads((cell_dir / "cli-output.json").read_text())
    except Exception:
        return None
    if not isinstance(events, list):
        return None

    # Newer CLIs (>= ~2.1.19x) emit discrete `thinking_tokens` telemetry
    # events instead of streaming thinking content; older CLIs stream the
    # thinking content itself. We only ever count one or the other per
    # model (see `thinking_chars_seen` below) — never both.
    thinking_est = 0.0
    # Last-event-per-message-id wins: an assistant message's `usage` field
    # is a cumulative snapshot as of that event, so only the latest one
    # per id is meaningful.
    per_id: dict[str, tuple[str, dict]] = {}
    # Visible content chars, keyed by model — feeds the output-token floor
    # when the last usage snapshot undercounts (e.g. content emitted after
    # the last usage-bearing event before the kill).
    chars_by_model: dict[str, int] = {}
    thinking_chars_seen = False
    result_cost = None

    for e in events:
        if not isinstance(e, dict):
            continue
        if e.get("subtype") == "thinking_tokens":
            thinking_est += e.get("estimated_tokens_delta") or 0
        if e.get("type") == "assistant":
            msg = e.get("message") or {}
            mid = msg.get("id")
            usage = msg.get("usage")
            model = msg.get("model")
            if mid and usage and model:
                per_id[mid] = (model, usage)
            for block in (msg.get("content") or []):
                if not isinstance(block, dict):
                    continue
                btype = block.get("type")
                if btype == "text":
                    chars_by_model[model] = chars_by_model.get(model, 0) + len(block.get("text") or "")
                elif btype == "thinking":
                    chars_by_model[model] = chars_by_model.get(model, 0) + len(block.get("thinking") or "")
                    thinking_chars_seen = True
                elif btype == "tool_use":
                    chars_by_model[model] = chars_by_model.get(model, 0) + len(json.dumps(block.get("input") or {}))
        elif e.get("type") == "result":
            rc = e.get("total_cost_usd")
            if isinstance(rc, (int, float)) and rc > 0:
                result_cost = rc

    if not per_id:
        return None

    # Sum exact components per model over the deduped usage snapshots.
    components: dict[str, dict[str, float]] = {}
    for model, usage in per_id.values():
        c = components.setdefault(model, {"in": 0.0, "cr": 0.0, "cw": 0.0, "out": 0.0})
        c["in"] += usage.get("input_tokens", 0) or 0
        c["cr"] += usage.get("cache_read_input_tokens", 0) or 0
        c["cw"] += usage.get("cache_creation_input_tokens", 0) or 0
        c["out"] += usage.get("output_tokens", 0) or 0

    # Thinking telemetry isn't model-attributed; in practice cells have one
    # main model plus a tiny haiku side-call, so we assign it to whichever
    # model produced the most output.
    main_model = max(components, key=lambda mdl: components[mdl]["out"])

    cost = 0.0
    for model, c in components.items():
        nm = normalize_model_id(model)
        if nm is None:
            continue  # unknown model — skip rather than guess, keeps the floor a floor
        rates = COST_PER_MTOK[nm]
        out = max(c["out"], chars_by_model.get(model, 0) / _CHARS_PER_TOKEN)
        if model == main_model and not thinking_chars_seen:
            out += thinking_est
        cost += (c["in"] * rates["input"] + c["cr"] * rates["cache_read"]
                  + c["cw"] * rates["cache_write"] + out * rates["output"]) / 1e6

    if result_cost is not None:
        return max(result_cost, cost)
    return cost


def timeout_cost_contribution(m: dict, cell_dir: Path) -> tuple[float, bool]:
    """(contribution_usd, is_exact) for a timed-out cell's Total Cost share.

    CLI-recorded cost when the stream finished in time (exact); otherwise a
    stream-recovered floor (not exact); 0.0 and not exact when recovery fails.
    """
    recorded = (m.get("cost") or {}).get("total_cost_usd") or 0.0
    if recorded > 0:
        return recorded, True
    return (recover_timeout_cost(cell_dir) or 0.0), False
