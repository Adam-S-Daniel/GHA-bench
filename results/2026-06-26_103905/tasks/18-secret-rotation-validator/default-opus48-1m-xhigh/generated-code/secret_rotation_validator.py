#!/usr/bin/env python3
"""Secret rotation validator.

Reads a configuration of secrets (name, last-rotated date, rotation policy in
days, and the services that require them), works out which secrets are
*expired* or *expiring* within a configurable warning window, and emits a
rotation report grouped by urgency (expired / warning / ok).

Design notes
------------
* Pure standard library so the same code runs locally, in CI, and inside the
  ``act`` container with no third-party dependencies.
* The "current" date is injectable (``--now`` / ``now=``) so every result is
  deterministic and testable -- nothing depends on the wall-clock day.
* The logic is split into small, individually testable functions:
  ``parse_date`` -> ``classify_secret`` -> ``build_report`` ->
  ``render_markdown`` / ``render_json``. ``main`` only wires together CLI
  parsing, file I/O, and rendering.
"""

from __future__ import annotations

import json
from datetime import date, datetime, timedelta


class ConfigError(Exception):
    """Raised for any problem with the secrets configuration.

    The message is intended to be shown directly to the user, so it always
    points at the specific secret / field that is wrong.
    """

# Urgency buckets, ordered most -> least urgent. Exposed as constants so callers
# and tests never hard-code the bare strings.
STATUS_EXPIRED = "expired"
STATUS_WARNING = "warning"
STATUS_OK = "ok"
STATUS_ORDER = (STATUS_EXPIRED, STATUS_WARNING, STATUS_OK)

DATE_FORMAT = "%Y-%m-%d"


def load_config(path: str) -> list:
    """Load and validate the secrets config from ``path``.

    Accepts either ``{"secrets": [...]}`` or a bare top-level list. Every secret
    is validated up front so the report step never trips over malformed data.
    Returns the raw (still string-dated) list of secret dicts.

    Raises :class:`ConfigError` with an actionable message on any problem.
    """
    try:
        with open(path, "r", encoding="utf-8") as fh:
            raw = fh.read()
    except FileNotFoundError as exc:
        raise ConfigError(f"config file not found: {path}") from exc
    except OSError as exc:  # permissions, is-a-directory, etc.
        raise ConfigError(f"could not read config file {path}: {exc}") from exc

    try:
        data = json.loads(raw)
    except json.JSONDecodeError as exc:
        raise ConfigError(f"invalid JSON in {path}: {exc}") from exc

    # Accept both shapes; normalise to a list of secret dicts.
    if isinstance(data, dict):
        if "secrets" not in data:
            raise ConfigError(
                "config object must contain a 'secrets' key with a list of secrets"
            )
        secrets = data["secrets"]
    elif isinstance(data, list):
        secrets = data
    else:
        raise ConfigError(
            "config must be a JSON object with a 'secrets' list, or a JSON list"
        )

    if not isinstance(secrets, list):
        raise ConfigError("'secrets' must be a list")

    for index, secret in enumerate(secrets):
        _validate_secret(secret, index)

    return secrets


def _validate_secret(secret, index: int) -> None:
    """Validate one secret entry, raising ConfigError that identifies it."""
    if not isinstance(secret, dict):
        raise ConfigError(f"secret #{index} must be a JSON object")

    # Use the name (if any) to make later messages easy to act on.
    label = secret.get("name") if isinstance(secret.get("name"), str) else None
    where = f"secret '{label}'" if label else f"secret #{index}"

    name = secret.get("name")
    if not isinstance(name, str) or not name.strip():
        raise ConfigError(f"{where}: 'name' is required and must be a non-empty string")

    if "last_rotated" not in secret:
        raise ConfigError(f"{where}: missing required field 'last_rotated'")
    try:
        parse_date(secret["last_rotated"])
    except ValueError as exc:
        raise ConfigError(f"{where}: 'last_rotated' {exc}") from exc

    if "rotation_policy_days" not in secret:
        raise ConfigError(f"{where}: missing required field 'rotation_policy_days'")
    policy = secret["rotation_policy_days"]
    # bool is a subclass of int -- reject it explicitly.
    if isinstance(policy, bool) or not isinstance(policy, int) or policy <= 0:
        raise ConfigError(
            f"{where}: 'rotation_policy_days' must be a positive integer, got {policy!r}"
        )

    required_by = secret.get("required_by", [])
    if not isinstance(required_by, list) or not all(
        isinstance(s, str) for s in required_by
    ):
        raise ConfigError(f"{where}: 'required_by' must be a list of strings")


def parse_date(value: str) -> date:
    """Parse a ``YYYY-MM-DD`` string into a :class:`datetime.date`.

    Raises ``ValueError`` with a clear message when the format is wrong; callers
    translate this into a user-facing configuration error.
    """
    if not isinstance(value, str):
        raise ValueError(f"date must be a string, got {type(value).__name__}")
    try:
        return datetime.strptime(value.strip(), DATE_FORMAT).date()
    except ValueError as exc:
        raise ValueError(
            f"invalid date {value!r}; expected format YYYY-MM-DD"
        ) from exc


def classify_secret(secret: dict, now: date, warning_days: int) -> dict:
    """Turn one secret config entry into an enriched record with a status.

    The returned dict keeps the original metadata and adds:
      * ``due_date``        -- last_rotated + rotation_policy_days (ISO string)
      * ``days_until_due``  -- signed integer; negative means overdue
      * ``status``          -- one of the STATUS_* buckets

    Classification rule (``d`` = days_until_due):
        d <  0                       -> expired  (past the due date)
        0 <= d <= warning_days       -> warning  (due now/soon, incl. today)
        d >  warning_days            -> ok
    """
    last_rotated = parse_date(secret["last_rotated"])
    policy_days = secret["rotation_policy_days"]
    due_date = last_rotated + timedelta(days=policy_days)
    days_until_due = (due_date - now).days

    if days_until_due < 0:
        status = STATUS_EXPIRED
    elif days_until_due <= warning_days:
        status = STATUS_WARNING
    else:
        status = STATUS_OK

    return {
        "name": secret["name"],
        "last_rotated": last_rotated.strftime(DATE_FORMAT),
        "rotation_policy_days": policy_days,
        "required_by": list(secret.get("required_by", [])),
        "due_date": due_date.strftime(DATE_FORMAT),
        "days_until_due": days_until_due,
        "status": status,
    }


def build_report(secrets: list, now: date, warning_days: int) -> dict:
    """Classify every secret and assemble the full rotation report.

    The report is a plain dict (JSON-serialisable) with:
      * ``reference_date`` / ``warning_days`` -- the inputs, echoed for context
      * ``summary``  -- total + per-bucket counts
      * ``groups``   -- secrets bucketed into expired/warning/ok, each group
                        sorted by urgency (soonest due / most overdue first)
    """
    if warning_days < 0:
        raise ValueError("warning_days must be >= 0")

    classified = [classify_secret(s, now=now, warning_days=warning_days) for s in secrets]

    groups = {status: [] for status in STATUS_ORDER}
    for record in classified:
        groups[record["status"]].append(record)

    # Within each bucket, surface the most urgent first: the lowest
    # days_until_due (most overdue / soonest) comes first; ties broken by name
    # for stable, deterministic output.
    for bucket in groups.values():
        bucket.sort(key=lambda r: (r["days_until_due"], r["name"]))

    summary = {"total": len(classified)}
    for status in STATUS_ORDER:
        summary[status] = len(groups[status])

    return {
        "reference_date": now.strftime(DATE_FORMAT),
        "warning_days": warning_days,
        "summary": summary,
        "groups": groups,
    }


# Human-friendly labels and the column used to describe "time" for each bucket.
_SECTION_TITLES = {
    STATUS_EXPIRED: "Expired",
    STATUS_WARNING: "Warning",
    STATUS_OK: "OK",
}


def _format_required_by(required_by: list) -> str:
    return ", ".join(required_by) if required_by else "-"


def render_markdown(report: dict) -> str:
    """Render the report as a grouped markdown document, one table per bucket."""
    summary = report["summary"]
    lines = []
    lines.append("# Secret Rotation Report")
    lines.append("")
    lines.append(
        f"_Reference date: {report['reference_date']} "
        f"· Warning window: {report['warning_days']} day(s)_"
    )
    lines.append("")
    lines.append(
        f"**Summary:** {summary['total']} secret(s) — "
        f"{summary['expired']} expired, {summary['warning']} warning, "
        f"{summary['ok']} ok"
    )
    lines.append("")

    for status in STATUS_ORDER:
        bucket = report["groups"][status]
        lines.append(f"## {_SECTION_TITLES[status]} ({len(bucket)})")
        lines.append("")
        if not bucket:
            lines.append("_None_")
            lines.append("")
            continue

        # Expired secrets are described by how overdue they are; the rest by how
        # many days remain.
        time_col = "Days Overdue" if status == STATUS_EXPIRED else "Days Until Due"
        lines.append(
            f"| Secret | Last Rotated | Policy (days) | Due Date | {time_col} | Required By |"
        )
        lines.append("| --- | --- | --- | --- | --- | --- |")
        for s in bucket:
            days = s["days_until_due"]
            time_val = -days if status == STATUS_EXPIRED else days
            lines.append(
                f"| {s['name']} | {s['last_rotated']} | {s['rotation_policy_days']} "
                f"| {s['due_date']} | {time_val} | {_format_required_by(s['required_by'])} |"
            )
        lines.append("")

    return "\n".join(lines).rstrip() + "\n"


def render_json(report: dict, compact: bool = False) -> str:
    """Render the report as JSON.

    ``compact=True`` produces a single line (ideal for machine consumption in
    CI logs); otherwise the output is indented for human reading.
    """
    if compact:
        return json.dumps(report, separators=(",", ":"))
    return json.dumps(report, indent=2)


# ---------------------------------------------------------------------------
# Command line entry point
# ---------------------------------------------------------------------------

# Exit codes form a small, documented contract so CI can act on them.
EXIT_OK = 0
EXIT_ERROR = 1          # usage / config / I/O error
EXIT_EXPIRED_FOUND = 2  # only with --fail-on-expired when expired secrets exist


def _build_arg_parser():
    import argparse

    parser = argparse.ArgumentParser(
        prog="secret_rotation_validator",
        description=(
            "Validate secret rotation: flag secrets that are expired or "
            "expiring within a warning window and emit a grouped report."
        ),
    )
    parser.add_argument(
        "--config", required=True,
        help="Path to the secrets configuration JSON file.",
    )
    parser.add_argument(
        "--warning-days", type=int, default=14,
        help="Warning window in days (default: 14). Secrets due within this "
             "many days are flagged 'warning'.",
    )
    parser.add_argument(
        "--now", default=None,
        help="Reference date as YYYY-MM-DD (default: today). Pinning this makes "
             "output deterministic.",
    )
    parser.add_argument(
        "--format", choices=("markdown", "json"), default="markdown",
        help="Output format (default: markdown).",
    )
    parser.add_argument(
        "--compact", action="store_true",
        help="For --format json, emit a single compact line instead of indented JSON.",
    )
    parser.add_argument(
        "--fail-on-expired", action="store_true",
        help="Exit with code 2 if any secret is expired (useful as a CI gate). "
             "The report is still printed.",
    )
    return parser


def main(argv=None) -> int:
    """CLI entry point. Returns a process exit code; never raises for expected
    user errors -- those are turned into messages on stderr + a non-zero code."""
    import sys

    parser = _build_arg_parser()
    args = parser.parse_args(argv)

    # Resolve the reference date.
    if args.now is None:
        now = date.today()
    else:
        try:
            now = parse_date(args.now)
        except ValueError as exc:
            print(f"error: --now {exc}", file=sys.stderr)
            return EXIT_ERROR

    if args.warning_days < 0:
        print("error: --warning-days must be >= 0", file=sys.stderr)
        return EXIT_ERROR

    # Load + validate config, then build and render the report.
    try:
        secrets = load_config(args.config)
        report = build_report(secrets, now=now, warning_days=args.warning_days)
    except ConfigError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return EXIT_ERROR

    if args.format == "json":
        print(render_json(report, compact=args.compact))
    else:
        print(render_markdown(report))

    if args.fail_on_expired and report["summary"]["expired"] > 0:
        print(
            f"error: {report['summary']['expired']} expired secret(s) found",
            file=sys.stderr,
        )
        return EXIT_EXPIRED_FOUND

    return EXIT_OK


if __name__ == "__main__":
    import sys

    sys.exit(main())
