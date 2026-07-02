#!/usr/bin/env python3
"""
Secret Rotation Validator
==========================

Reads a JSON config describing secrets (name, last-rotated date, rotation
policy in days, and the services that require them -- all mock data, no
real secret values are ever read or stored), determines which secrets are
expired, expiring soon (within a configurable warning window), or fine,
and renders a rotation report as Markdown or JSON.

Design notes:
- All secret metadata is plain data (dicts), not a class, so fixtures can
  be expressed directly as JSON with no custom (de)serialization layer.
- `SecretRotationError` is the single error type raised for anything the
  caller did wrong (bad config path, malformed date, missing field) so the
  CLI only needs one except clause to turn failures into a clean message
  and a non-zero exit code.
"""
import argparse
import datetime
import json
import sys
from pathlib import Path

DATE_FORMAT = "%Y-%m-%d"


class SecretRotationError(Exception):
    """Raised for any user-facing config or validation failure."""


def parse_date(value):
    """Parse a YYYY-MM-DD string into a date, with a clear error on failure."""
    try:
        return datetime.datetime.strptime(value, DATE_FORMAT).date()
    except (ValueError, TypeError) as exc:
        raise SecretRotationError(
            f"invalid date '{value}': expected format YYYY-MM-DD"
        ) from exc


def days_since(last_rotated, today):
    """Whole days elapsed between last_rotated and today."""
    return (today - last_rotated).days


def days_until_expiry(secret, today):
    """Days remaining before the secret's rotation policy is violated.

    Negative values mean the secret is already past its rotation window.
    """
    last_rotated = parse_date(secret["last_rotated"])
    elapsed = days_since(last_rotated, today)
    return secret["rotation_days"] - elapsed


def classify(secret, today, warning_days):
    """Classify a secret as "expired", "warning", or "ok".

    A secret with zero (or fewer) days remaining is already due for
    rotation, so it counts as "expired" rather than "warning" -- the
    warning window only covers secrets that are *not yet* due.
    """
    remaining = days_until_expiry(secret, today)
    if remaining <= 0:
        return "expired"
    if remaining <= warning_days:
        return "warning"
    return "ok"


REQUIRED_SECRET_FIELDS = ("name", "last_rotated", "rotation_days")


def _validate_secret(secret):
    for field in REQUIRED_SECRET_FIELDS:
        if field not in secret:
            name = secret.get("name", "<unnamed>")
            raise SecretRotationError(f"secret '{name}' is missing required field '{field}'")
    if secret["rotation_days"] <= 0:
        raise SecretRotationError(
            f"secret '{secret['name']}' has invalid rotation_days: "
            f"{secret['rotation_days']} (must be positive)"
        )
    # Validate the date eagerly so bad fixtures fail fast with the
    # offending secret's name in the error, not a generic strptime trace.
    try:
        parse_date(secret["last_rotated"])
    except SecretRotationError as exc:
        raise SecretRotationError(f"secret '{secret['name']}': {exc}") from exc


def load_config(path):
    """Load and validate the secrets config JSON file.

    Raises SecretRotationError with a message that names the offending
    file or secret, so failures are actionable without a stack trace.
    """
    path = Path(path)
    if not path.is_file():
        raise SecretRotationError(f"config file not found: {path}")

    try:
        raw = path.read_text()
    except OSError as exc:
        raise SecretRotationError(f"could not read config file {path}: {exc}") from exc

    try:
        config = json.loads(raw)
    except json.JSONDecodeError as exc:
        raise SecretRotationError(f"config file {path} is not valid JSON: {exc}") from exc

    if "secrets" not in config or not isinstance(config["secrets"], list):
        raise SecretRotationError(f"config file {path} must contain a 'secrets' list")

    warning_days = config.get("warning_days", 7)
    if not isinstance(warning_days, int) or warning_days < 0:
        raise SecretRotationError("warning_days must be a non-negative integer")

    for secret in config["secrets"]:
        _validate_secret(secret)
        secret.setdefault("required_by", [])

    config["warning_days"] = warning_days
    return config


def build_report(secrets, today, warning_days):
    """Group secrets by urgency and annotate each with days_until_expiry."""
    report = {"expired": [], "warning": [], "ok": []}

    for secret in secrets:
        urgency = classify(secret, today, warning_days)
        annotated = dict(secret)
        annotated["days_until_expiry"] = days_until_expiry(secret, today)
        annotated["required_by"] = secret.get("required_by", [])
        report[urgency].append(annotated)

    report["summary"] = {
        "expired": len(report["expired"]),
        "warning": len(report["warning"]),
        "ok": len(report["ok"]),
        "total": len(secrets),
    }
    return report


def render_json(report):
    return json.dumps(report, indent=2)


_SECTION_TITLES = {"expired": "Expired", "warning": "Warning", "ok": "OK"}


def render_markdown(report):
    """Render the report as Markdown with one table per non-empty urgency."""
    lines = ["# Secret Rotation Report", ""]
    summary = report["summary"]
    lines.append(
        f"**Summary**: {summary['expired']} expired, {summary['warning']} warning, "
        f"{summary['ok']} ok (of {summary['total']} total)"
    )
    lines.append("")

    for urgency in ("expired", "warning", "ok"):
        secrets = report[urgency]
        if not secrets:
            continue
        lines.append(f"## {_SECTION_TITLES[urgency]}")
        lines.append("")
        lines.append("| Name | Last Rotated | Rotation Policy (days) | Days Until Expiry | Required By |")
        lines.append("|------|--------------|-------------------------|--------------------|-------------|")
        for secret in secrets:
            required_by = ", ".join(secret.get("required_by", []))
            lines.append(
                f"| {secret['name']} | {secret['last_rotated']} | {secret['rotation_days']} | "
                f"{secret['days_until_expiry']} | {required_by} |"
            )
        lines.append("")

    return "\n".join(lines)


def main(argv=None):
    parser = argparse.ArgumentParser(description="Validate secret rotation policies.")
    parser.add_argument("--config", required=True, help="Path to secrets config JSON file")
    parser.add_argument("--format", choices=["markdown", "json"], default="markdown")
    parser.add_argument(
        "--warning-days", type=int, default=None,
        help="Override the warning window (days) from the config file",
    )
    parser.add_argument(
        "--today", default=None,
        help="Override today's date (YYYY-MM-DD), mainly for reproducible tests",
    )
    parser.add_argument(
        "--fail-on-expired", action="store_true",
        help="Exit with status 1 if any secret is expired",
    )
    args = parser.parse_args(argv)

    try:
        config = load_config(args.config)
        today = parse_date(args.today) if args.today else datetime.date.today()
        warning_days = args.warning_days if args.warning_days is not None else config["warning_days"]

        report = build_report(config["secrets"], today, warning_days)
        output = render_json(report) if args.format == "json" else render_markdown(report)
        print(output)

        if args.fail_on_expired and report["summary"]["expired"] > 0:
            return 1
        return 0
    except SecretRotationError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
