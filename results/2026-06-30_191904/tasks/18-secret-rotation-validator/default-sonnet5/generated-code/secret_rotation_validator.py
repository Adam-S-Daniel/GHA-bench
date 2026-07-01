#!/usr/bin/env python3
"""
Secret Rotation Validator.

Reads a JSON configuration describing secrets (name, last-rotated date,
rotation policy in days, and the services that require each secret),
computes each secret's rotation status against a configurable warning
window, and renders a report grouped by urgency: expired, warning, ok.

Supports markdown (for GitHub Actions job summaries) and JSON output.

Design notes:
- "now" is injectable via --now so runs are deterministic and testable
  instead of depending on the wall clock.
- A single malformed secret entry is skipped with a warning rather than
  aborting the whole report -- one bad record shouldn't hide the status
  of every other secret. A missing/unreadable config *file*, on the other
  hand, is fatal since there is nothing to report on at all.
"""
import argparse
import json
import sys
from dataclasses import dataclass
from datetime import date, timedelta
from pathlib import Path


class ConfigError(Exception):
    """Raised when the secrets configuration file itself is unusable."""


@dataclass
class SecretStatus:
    name: str
    last_rotated: str
    rotation_days: int
    expiry_date: str
    days_remaining: int
    status: str  # "expired" | "warning" | "ok"
    required_by: list


def load_config(path: str) -> dict:
    """Read and parse the secrets config JSON file.

    Raises ConfigError with a human-readable message for any problem that
    makes the *entire file* unusable: missing file, unreadable file,
    invalid JSON, or a missing/invalid top-level "secrets" array.
    """
    config_path = Path(path)
    if not config_path.is_file():
        raise ConfigError(f"Config file not found: {path}")

    try:
        raw = config_path.read_text()
    except OSError as exc:
        raise ConfigError(f"Could not read config file {path}: {exc}") from exc

    try:
        data = json.loads(raw)
    except json.JSONDecodeError as exc:
        raise ConfigError(f"Invalid JSON in config file {path}: {exc}") from exc

    if not isinstance(data, dict):
        raise ConfigError(f"Config file {path} must contain a JSON object at the top level")

    if not isinstance(data.get("secrets"), list):
        raise ConfigError(f"Config file {path} must contain a 'secrets' array")

    return data


def validate_secret_entry(entry, index: int):
    """Validate a single secret entry.

    Returns (True, "") when valid, or (False, message) when the entry
    should be skipped. Skipped entries are reported as warnings by the
    caller, not raised as errors, so one bad record can't hide the rest
    of the report.
    """
    label = entry.get("name") if isinstance(entry, dict) else None
    label = label if isinstance(label, str) and label else f"<entry #{index}>"

    if not isinstance(entry, dict):
        return False, f"Secret {label} is not a JSON object"

    name = entry.get("name")
    if not name or not isinstance(name, str):
        return False, f"Secret {label} is missing a valid 'name'"

    last_rotated = entry.get("last_rotated")
    if not isinstance(last_rotated, str):
        return False, f"Secret '{name}' is missing 'last_rotated'"
    try:
        date.fromisoformat(last_rotated)
    except ValueError:
        return False, f"Secret '{name}' has an invalid 'last_rotated' date: {last_rotated!r}"

    rotation_days = entry.get("rotation_days")
    if not isinstance(rotation_days, int) or isinstance(rotation_days, bool) or rotation_days <= 0:
        return False, f"Secret '{name}' is missing a valid positive integer 'rotation_days'"

    if not isinstance(entry.get("required_by"), list):
        return False, f"Secret '{name}' is missing a valid 'required_by' list"

    return True, ""


def compute_status(entry: dict, today: date, warning_days: int) -> SecretStatus:
    """Compute the rotation status of a single, already-validated secret entry."""
    last_rotated = date.fromisoformat(entry["last_rotated"])
    rotation_days = entry["rotation_days"]
    expiry = last_rotated + timedelta(days=rotation_days)
    days_remaining = (expiry - today).days

    if days_remaining < 0:
        status = "expired"
    elif days_remaining <= warning_days:
        status = "warning"
    else:
        status = "ok"

    return SecretStatus(
        name=entry["name"],
        last_rotated=entry["last_rotated"],
        rotation_days=rotation_days,
        expiry_date=expiry.isoformat(),
        days_remaining=days_remaining,
        status=status,
        required_by=list(entry["required_by"]),
    )


def build_report(config: dict, today: date, warning_days_override=None):
    """Validate every secret entry, compute status, and group by urgency.

    Returns (grouped, warning_days, skipped_warnings):
      - grouped: {"expired": [...], "warning": [...], "ok": [...]} of SecretStatus
      - warning_days: the effective warning window used
      - skipped_warnings: messages for any malformed entries that were skipped
    """
    warning_days = warning_days_override if warning_days_override is not None else config.get("warning_days", 30)
    if not isinstance(warning_days, int) or isinstance(warning_days, bool) or warning_days < 0:
        raise ConfigError(f"'warning_days' must be a non-negative integer, got {warning_days!r}")

    grouped = {"expired": [], "warning": [], "ok": []}
    skipped_warnings = []

    for index, entry in enumerate(config["secrets"]):
        ok, message = validate_secret_entry(entry, index)
        if not ok:
            skipped_warnings.append(message)
            continue
        result = compute_status(entry, today, warning_days)
        grouped[result.status].append(result)

    return grouped, warning_days, skipped_warnings


def _sorted(items):
    """Most urgent first: most-overdue expired / soonest-due warning or ok."""
    return sorted(items, key=lambda s: s.days_remaining)


def format_markdown(grouped, warning_days: int, today: date, skipped_warnings) -> str:
    lines = ["# Secret Rotation Report", ""]
    lines.append(f"Generated: {today.isoformat()}")
    lines.append(f"Warning window: {warning_days} days")
    lines.append("")

    total = sum(len(v) for v in grouped.values())
    lines.append(
        f"Summary: {len(grouped['expired'])} expired, {len(grouped['warning'])} warning, "
        f"{len(grouped['ok'])} ok ({total} total)"
    )
    lines.append("")

    if skipped_warnings:
        lines.append("## Skipped Entries")
        lines.append("")
        for msg in skipped_warnings:
            lines.append(f"- WARNING: {msg}")
        lines.append("")

    section_titles = {"expired": "Expired", "warning": "Warning", "ok": "OK"}
    for key in ("expired", "warning", "ok"):
        items = _sorted(grouped[key])
        lines.append(f"## {section_titles[key]} ({len(items)})")
        lines.append("")
        if not items:
            lines.append("_None_")
            lines.append("")
            continue
        lines.append("| Secret | Last Rotated | Rotation Policy (days) | Days Remaining | Required By |")
        lines.append("|---|---|---|---|---|")
        for item in items:
            days_col = f"{item.days_remaining}" if item.days_remaining >= 0 else f"{-item.days_remaining} days ago"
            lines.append(
                f"| {item.name} | {item.last_rotated} | {item.rotation_days} | {days_col} | "
                f"{', '.join(item.required_by)} |"
            )
        lines.append("")

    return "\n".join(lines).rstrip("\n") + "\n"


def format_json(grouped, warning_days: int, today: date, skipped_warnings) -> str:
    def to_dict(item: SecretStatus) -> dict:
        return {
            "name": item.name,
            "last_rotated": item.last_rotated,
            "rotation_days": item.rotation_days,
            "expiry_date": item.expiry_date,
            "days_remaining": item.days_remaining,
            "status": item.status,
            "required_by": item.required_by,
        }

    payload = {
        "generated_at": today.isoformat(),
        "warning_days": warning_days,
        "summary": {
            "expired": len(grouped["expired"]),
            "warning": len(grouped["warning"]),
            "ok": len(grouped["ok"]),
            "total": sum(len(v) for v in grouped.values()),
        },
        "expired": [to_dict(i) for i in _sorted(grouped["expired"])],
        "warning": [to_dict(i) for i in _sorted(grouped["warning"])],
        "ok": [to_dict(i) for i in _sorted(grouped["ok"])],
        "skipped": skipped_warnings,
    }
    return json.dumps(payload, indent=2) + "\n"


def parse_args(argv=None):
    parser = argparse.ArgumentParser(description="Validate secret rotation status against policy.")
    parser.add_argument("--config", required=True, help="Path to the secrets config JSON file")
    parser.add_argument("--now", default=None, help="Override 'today' as YYYY-MM-DD (for deterministic runs)")
    parser.add_argument("--warning-days", type=int, default=None, help="Override the config's warning window")
    parser.add_argument("--format", choices=["markdown", "json"], default="markdown")
    parser.add_argument("--output", default=None, help="Optional path to also write the rendered report to")
    return parser.parse_args(argv)


def main(argv=None) -> int:
    args = parse_args(argv)

    if args.now is not None:
        try:
            today = date.fromisoformat(args.now)
        except ValueError:
            print(f"Error: --now must be YYYY-MM-DD, got {args.now!r}", file=sys.stderr)
            return 1
    else:
        today = date.today()

    try:
        config = load_config(args.config)
        grouped, warning_days, skipped_warnings = build_report(config, today, args.warning_days)
    except ConfigError as exc:
        print(f"Error: {exc}", file=sys.stderr)
        return 1

    for msg in skipped_warnings:
        print(f"Warning: {msg}", file=sys.stderr)

    report_text = format_json(grouped, warning_days, today, skipped_warnings) if args.format == "json" \
        else format_markdown(grouped, warning_days, today, skipped_warnings)

    print(report_text, end="")

    if args.output:
        Path(args.output).write_text(report_text)

    return 0


if __name__ == "__main__":
    sys.exit(main())
