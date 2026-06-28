#!/usr/bin/env python3
"""Secret Rotation Validator.

Given a configuration of secrets with metadata, classify each secret by
rotation urgency (expired / warning / ok), build a rotation report, and render
it as a markdown table, JSON, or a compact machine-readable summary line.

Approach
--------
The logic is split into small, pure functions so each can be driven by a unit
test (red/green TDD):

* ``classify_secret``  -> urgency + dates for one secret
* ``build_report``     -> classify every secret, group by urgency
* ``render_*``         -> turn a report into markdown / JSON / summary text
* ``load_config``      -> read + validate the input file
* ``main``             -> CLI glue (argument parsing, error handling, exit code)

A "reference date" (``now``) is always injected rather than read from the wall
clock, which keeps both the tests and the CI workflow fully deterministic.
"""
from __future__ import annotations

import argparse
import json
import sys
from datetime import date, datetime, timedelta

# Urgency buckets, ordered most-urgent first. Used for grouping and display.
STATUSES = ("expired", "warning", "ok")

# Renderers keyed by the --format flag.
RENDERERS = {
    "markdown": lambda r: render_markdown(r),
    "json": lambda r: render_json(r),
    "summary": lambda r: render_summary(r),
}


class ConfigError(Exception):
    """Raised when the secrets configuration cannot be read or is malformed."""


def classify_secret(secret: dict, now: date, warning_days: int) -> dict:
    """Classify a single secret by how close it is to its rotation deadline.

    The expiry date is ``last_rotated + rotation_policy_days``. From there:

    * ``days_until_expiry < 0``              -> ``expired``
    * ``0 <= days_until_expiry <= warning``  -> ``warning``
    * otherwise                              -> ``ok``

    Returns a new dict combining the original metadata with the computed
    ``expiry_date``, ``days_until_expiry`` and ``status`` fields.
    """
    last_rotated = _parse_date(secret.get("last_rotated"), field="last_rotated")
    policy_days = _parse_policy(secret.get("rotation_policy_days"))

    expiry_date = last_rotated + timedelta(days=policy_days)
    days_until_expiry = (expiry_date - now).days

    if days_until_expiry < 0:
        status = "expired"
    elif days_until_expiry <= warning_days:
        status = "warning"
    else:
        status = "ok"

    return {
        "name": secret.get("name", "<unnamed>"),
        "last_rotated": last_rotated.isoformat(),
        "rotation_policy_days": policy_days,
        "required_by": list(secret.get("required_by", [])),
        "expiry_date": expiry_date,
        "days_until_expiry": days_until_expiry,
        "status": status,
    }


def build_report(config: dict, now: date, warning_days: int) -> dict:
    """Classify every secret in ``config`` and group the results by urgency.

    Within each urgency group secrets are sorted by ``days_until_expiry``
    ascending, so the most overdue / soonest-to-expire appears first.
    """
    secrets = config.get("secrets")
    if secrets is None:
        raise ValueError("config is missing the required 'secrets' list")
    if not isinstance(secrets, list):
        raise ValueError("'secrets' must be a list")

    groups: dict[str, list] = {status: [] for status in STATUSES}
    for entry in secrets:
        classified = classify_secret(entry, now=now, warning_days=warning_days)
        groups[classified["status"]].append(classified)

    for status in STATUSES:
        groups[status].sort(key=lambda s: s["days_until_expiry"])

    counts = {status: len(groups[status]) for status in STATUSES}
    counts["total"] = sum(counts[status] for status in STATUSES)

    return {
        "generated_for": now.isoformat(),
        "warning_days": warning_days,
        "counts": counts,
        "groups": groups,
    }


# Human-friendly section titles for each urgency bucket.
_SECTION_TITLES = {"expired": "Expired", "warning": "Warning", "ok": "OK"}


def render_summary(report: dict) -> str:
    """One compact, grep-friendly line — handy for CI logs and assertions."""
    c = report["counts"]
    return (
        f"ROTATION_SUMMARY expired={c['expired']} warning={c['warning']} "
        f"ok={c['ok']} total={c['total']}"
    )


def render_json(report: dict) -> str:
    """Serialise the report as pretty JSON with ISO date strings."""
    return json.dumps(report, indent=2, sort_keys=False, default=_json_default)


def _json_default(value):
    if isinstance(value, date):
        return value.isoformat()
    raise TypeError(f"Object of type {type(value).__name__} is not JSON serializable")


def render_markdown(report: dict) -> str:
    """Render the report as GitHub-flavoured markdown with a table per group."""
    c = report["counts"]
    lines = [
        f"# Secret Rotation Report (as of {report['generated_for']})",
        "",
        f"Warning window: {report['warning_days']} days",
        "",
        f"**Expired: {c['expired']} | Warning: {c['warning']} | "
        f"OK: {c['ok']} | Total: {c['total']}**",
        "",
    ]

    header = "| Secret | Last Rotated | Policy (days) | Expiry | Days Left | Required By |"
    divider = "| --- | --- | --- | --- | --- | --- |"

    for status in STATUSES:
        group = report["groups"][status]
        lines.append(f"## {_SECTION_TITLES[status]} ({len(group)})")
        lines.append("")
        if not group:
            lines.append("_None_")
            lines.append("")
            continue
        lines.append(header)
        lines.append(divider)
        for s in group:
            required_by = ", ".join(s["required_by"]) if s["required_by"] else "-"
            expiry = s["expiry_date"]
            expiry = expiry.isoformat() if isinstance(expiry, date) else expiry
            lines.append(
                f"| {s['name']} | {s['last_rotated']} | {s['rotation_policy_days']} "
                f"| {expiry} | {s['days_until_expiry']} | {required_by} |"
            )
        lines.append("")

    return "\n".join(lines).rstrip() + "\n"


def _parse_date(value, field: str) -> date:
    """Parse an ISO ``YYYY-MM-DD`` date, raising a clear error otherwise."""
    if value is None:
        raise ValueError(f"missing required field '{field}'")
    if isinstance(value, date):
        return value
    try:
        return datetime.strptime(str(value), "%Y-%m-%d").date()
    except ValueError as exc:
        raise ValueError(
            f"invalid date for '{field}': {value!r} (expected YYYY-MM-DD)"
        ) from exc


def _parse_policy(value) -> int:
    """Validate the rotation policy is a positive integer number of days."""
    try:
        days = int(value)
    except (TypeError, ValueError) as exc:
        raise ValueError(
            f"invalid rotation_policy_days: {value!r} (expected a positive integer)"
        ) from exc
    if days <= 0:
        raise ValueError(
            f"invalid rotation_policy_days: {days} (must be greater than 0)"
        )
    return days


def load_config(path: str) -> dict:
    """Read and JSON-parse the secrets config, raising ``ConfigError`` on failure."""
    try:
        with open(path, "r", encoding="utf-8") as fh:
            raw = fh.read()
    except FileNotFoundError as exc:
        raise ConfigError(f"config file not found: {path}") from exc
    except OSError as exc:
        raise ConfigError(f"could not read config file '{path}': {exc}") from exc

    try:
        data = json.loads(raw)
    except json.JSONDecodeError as exc:
        raise ConfigError(f"invalid JSON in config file '{path}': {exc}") from exc

    if not isinstance(data, dict):
        raise ConfigError("config root must be a JSON object with a 'secrets' list")
    return data


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="secret_rotation_validator",
        description="Validate secret rotation freshness and report by urgency.",
    )
    parser.add_argument(
        "--config", required=True,
        help="Path to the secrets configuration JSON file.",
    )
    parser.add_argument(
        "--warning-days", type=int, default=14,
        help="Days before expiry to start warning (default: 14).",
    )
    parser.add_argument(
        "--now", default=None,
        help="Reference date (YYYY-MM-DD). Defaults to today. "
             "Mainly for deterministic tests/CI.",
    )
    parser.add_argument(
        "--format", choices=sorted(RENDERERS), default="markdown",
        help="Output format (default: markdown).",
    )
    parser.add_argument(
        "--fail-on", choices=("none", "warning", "expired"), default="none",
        help="Exit non-zero when secrets at/above this urgency exist "
             "(default: none — always exit 0).",
    )
    return parser


def _exit_code_for_fail_on(fail_on: str, counts: dict) -> int:
    """Return a non-zero exit code if the --fail-on threshold is breached."""
    if fail_on == "expired":
        return 1 if counts["expired"] > 0 else 0
    if fail_on == "warning":
        return 1 if (counts["expired"] + counts["warning"]) > 0 else 0
    return 0  # "none"


def main(argv=None) -> int:
    """CLI entrypoint. Returns a process exit code (never raises for user errors)."""
    args = _build_parser().parse_args(argv)

    try:
        if args.now is None:
            now = date.today()
        else:
            now = _parse_date(args.now, field="--now")
        if args.warning_days < 0:
            raise ValueError("--warning-days must be zero or greater")

        config = load_config(args.config)
        report = build_report(config, now=now, warning_days=args.warning_days)
    except (ConfigError, ValueError) as exc:
        print(f"Error: {exc}", file=sys.stderr)
        return 2

    print(RENDERERS[args.format](report))
    return _exit_code_for_fail_on(args.fail_on, report["counts"])


if __name__ == "__main__":  # pragma: no cover
    sys.exit(main())
