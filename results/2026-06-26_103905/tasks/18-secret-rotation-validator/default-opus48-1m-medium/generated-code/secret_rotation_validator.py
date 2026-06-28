#!/usr/bin/env python3
"""
Secret Rotation Validator
=========================

Given a configuration of secrets with metadata (name, last-rotated date,
rotation policy in days, required-by services), this tool:

  * classifies each secret by urgency:
        - "expired"  : the rotation due date is in the past
        - "warning"  : due within a configurable warning window (>= 0 days away)
        - "ok"       : due further out than the warning window
  * builds a rotation report
  * emits notifications grouped by urgency
  * supports two output formats: `markdown` (a table) and `json`

Design notes
------------
The logic is split into small pure functions so each can be unit-tested in
isolation (TDD-friendly):

    classify_secret() -> per-secret status
    build_report()    -> grouped report dict for the whole config
    render_markdown() / render_json() -> presentation only

A `--now` flag lets tests pin "today" to a fixed date so results are
deterministic; in production it defaults to the real current date.

All errors raise `ValidationError` with a meaningful message; `main()` catches
it and exits non-zero with that message on stderr.
"""
from __future__ import annotations

import argparse
import datetime
import json
import sys
from typing import Any

# Urgency buckets in display order (most urgent first).
URGENCY_ORDER = ["expired", "warning", "ok"]

# Fields every secret entry must contain.
REQUIRED_FIELDS = ("name", "last_rotated", "rotation_policy_days")


class ValidationError(Exception):
    """Raised for any user-facing configuration or input error."""


# --------------------------------------------------------------------------- #
# Core logic (pure functions)
# --------------------------------------------------------------------------- #
def _parse_date(value: str, *, field: str, secret_name: str = "") -> datetime.date:
    """Parse an ISO (YYYY-MM-DD) date, raising a helpful error on failure."""
    where = f" for secret '{secret_name}'" if secret_name else ""
    if not isinstance(value, str):
        raise ValidationError(f"Field '{field}'{where} must be a YYYY-MM-DD string")
    try:
        return datetime.date.fromisoformat(value)
    except ValueError:
        raise ValidationError(
            f"Field '{field}'{where} has invalid date '{value}'; expected YYYY-MM-DD"
        )


def classify_secret(
    secret: dict[str, Any], *, now: datetime.date, warning_days: int
) -> dict[str, Any]:
    """
    Classify a single secret and return an enriched record.

    next_rotation     = last_rotated + rotation_policy_days
    days_until        = (next_rotation - now).days
        < 0                       -> expired
        0 <= d <= warning_days    -> warning
        otherwise                 -> ok
    """
    # Validate required fields are present.
    for field in REQUIRED_FIELDS:
        if field not in secret:
            name = secret.get("name", "<unknown>")
            raise ValidationError(f"Secret '{name}' is missing required field '{field}'")

    name = secret["name"]
    last_rotated = _parse_date(secret["last_rotated"], field="last_rotated", secret_name=name)

    policy = secret["rotation_policy_days"]
    if not isinstance(policy, int) or isinstance(policy, bool) or policy <= 0:
        raise ValidationError(
            f"Secret '{name}' has invalid rotation_policy_days '{policy}'; "
            "expected a positive integer"
        )

    next_rotation = last_rotated + datetime.timedelta(days=policy)
    days_until = (next_rotation - now).days

    if days_until < 0:
        status = "expired"
    elif days_until <= warning_days:
        status = "warning"
    else:
        status = "ok"

    return {
        "name": name,
        "last_rotated": last_rotated.isoformat(),
        "rotation_policy_days": policy,
        "required_by": list(secret.get("required_by", [])),
        "next_rotation": next_rotation.isoformat(),
        "days_until_rotation": days_until,
        "status": status,
    }


def build_report(
    config: dict[str, Any], *, now: datetime.date, warning_days: int
) -> dict[str, Any]:
    """Classify every secret and group the results by urgency."""
    if not isinstance(config, dict) or "secrets" not in config:
        raise ValidationError("Config must be an object with a top-level 'secrets' list")
    if not isinstance(config["secrets"], list):
        raise ValidationError("'secrets' must be a list")

    grouped: dict[str, list[dict[str, Any]]] = {u: [] for u in URGENCY_ORDER}
    for secret in config["secrets"]:
        if not isinstance(secret, dict):
            raise ValidationError("Each secret entry must be an object")
        record = classify_secret(secret, now=now, warning_days=warning_days)
        grouped[record["status"]].append(record)

    # Within each group, soonest-due first makes the report easy to action.
    for records in grouped.values():
        records.sort(key=lambda r: r["days_until_rotation"])

    summary = {u: len(grouped[u]) for u in URGENCY_ORDER}
    summary["total"] = sum(summary[u] for u in URGENCY_ORDER)

    return {
        "generated_at": now.isoformat(),
        "warning_days": warning_days,
        "summary": summary,
        "secrets": grouped,
    }


# --------------------------------------------------------------------------- #
# Rendering
# --------------------------------------------------------------------------- #
def render_json(report: dict[str, Any]) -> str:
    """Pretty-printed, stable JSON for machine consumption."""
    return json.dumps(report, indent=2, sort_keys=False)


_STATUS_LABEL = {
    "expired": "EXPIRED",
    "warning": "WARNING",
    "ok": "OK",
}


def render_markdown(report: dict[str, Any]) -> str:
    """Render the report as grouped markdown tables with a summary header."""
    s = report["summary"]
    lines: list[str] = []
    lines.append("# Secret Rotation Report")
    lines.append("")
    lines.append(f"Generated: {report['generated_at']} | Warning window: "
                 f"{report['warning_days']} days")
    lines.append("")
    lines.append(
        f"Summary: {s['expired']} expired, {s['warning']} warning, "
        f"{s['ok']} ok ({s['total']} total)"
    )
    lines.append("")

    for urgency in URGENCY_ORDER:
        records = report["secrets"][urgency]
        lines.append(f"## {_STATUS_LABEL[urgency]} ({len(records)})")
        lines.append("")
        if not records:
            lines.append("_None_")
            lines.append("")
            continue
        lines.append("| Secret | Last Rotated | Policy (days) | Next Rotation | Days Left | Required By |")
        lines.append("| --- | --- | --- | --- | --- | --- |")
        for r in records:
            required = ", ".join(r["required_by"]) if r["required_by"] else "-"
            lines.append(
                f"| {r['name']} | {r['last_rotated']} | {r['rotation_policy_days']} "
                f"| {r['next_rotation']} | {r['days_until_rotation']} | {required} |"
            )
        lines.append("")

    return "\n".join(lines).rstrip() + "\n"


# --------------------------------------------------------------------------- #
# I/O + CLI
# --------------------------------------------------------------------------- #
def load_config(path: str) -> dict[str, Any]:
    """Load and JSON-parse the config file with friendly error messages."""
    try:
        with open(path, "r", encoding="utf-8") as fh:
            raw = fh.read()
    except FileNotFoundError:
        raise ValidationError(f"Config file not found: {path}")
    except OSError as exc:
        raise ValidationError(f"Could not read config file '{path}': {exc}")

    try:
        return json.loads(raw)
    except json.JSONDecodeError as exc:
        raise ValidationError(f"Config file '{path}' is not valid JSON: {exc}")


def _parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Validate secret rotation status and report by urgency."
    )
    parser.add_argument("--config", required=True, help="Path to the secrets JSON config")
    parser.add_argument(
        "--warning-days", type=int, default=14,
        help="Warning window in days (default: 14)",
    )
    parser.add_argument(
        "--now", default=None,
        help="Override 'today' as YYYY-MM-DD (default: current date)",
    )
    parser.add_argument(
        "--format", choices=["markdown", "json"], default="markdown",
        help="Output format (default: markdown)",
    )
    parser.add_argument(
        "--fail-on-expired", action="store_true",
        help="Exit with code 2 if any secret is expired (for CI gating)",
    )
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    """CLI entry point. Returns a process exit code."""
    args = _parse_args(argv if argv is not None else sys.argv[1:])
    try:
        if args.warning_days < 0:
            raise ValidationError("--warning-days must be >= 0")
        now = (
            _parse_date(args.now, field="--now")
            if args.now
            else datetime.date.today()
        )
        config = load_config(args.config)
        report = build_report(config, now=now, warning_days=args.warning_days)

        if args.format == "json":
            print(render_json(report))
        else:
            print(render_markdown(report))

        if args.fail_on_expired and report["summary"]["expired"] > 0:
            print(
                f"ERROR: {report['summary']['expired']} expired secret(s) found",
                file=sys.stderr,
            )
            return 2
        return 0
    except ValidationError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
