"""
Secret rotation validator.

Reads a JSON config describing mock secrets (name, last-rotated date,
rotation policy in days, services that require the secret), determines
which secrets are expired, expiring soon (within a warning window), or
still ok, and renders a report as Markdown or JSON.
"""
import argparse
import datetime
import json
import sys


class SecretConfigError(Exception):
    """Raised when the secrets config is missing required fields or malformed."""


def check_secret_status(secret, today, warning_days):
    """Classify a single secret as 'expired', 'warning', or 'ok'.

    days_until_expiry is (last_rotated + rotation_days) - today. A secret is
    'expired' once that count drops below zero, 'warning' when it falls
    within [0, warning_days], and 'ok' otherwise.
    """
    last_rotated = datetime.date.fromisoformat(secret["last_rotated"])
    rotation_days = secret["rotation_days"]
    expiry_date = last_rotated + datetime.timedelta(days=rotation_days)
    days_until_expiry = (expiry_date - today).days

    if days_until_expiry < 0:
        status = "expired"
    elif days_until_expiry <= warning_days:
        status = "warning"
    else:
        status = "ok"

    return {
        "name": secret["name"],
        "status": status,
        "days_until_expiry": days_until_expiry,
        "expiry_date": expiry_date.isoformat(),
        "required_by": secret.get("required_by", []),
    }


def load_secrets(path):
    """Load and minimally validate a secrets config JSON file."""
    try:
        with open(path, "r") as f:
            data = json.load(f)
    except FileNotFoundError:
        raise SecretConfigError(f"secrets config file not found: {path}")
    except json.JSONDecodeError as e:
        raise SecretConfigError(f"{path}: invalid JSON ({e})")

    secrets = data.get("secrets") if isinstance(data, dict) else data
    if not isinstance(secrets, list):
        raise SecretConfigError(f"{path}: expected a top-level 'secrets' list")

    for secret in secrets:
        for field in ("name", "last_rotated", "rotation_days"):
            if field not in secret:
                raise SecretConfigError(
                    f"secret entry missing required field '{field}': {secret}"
                )

    return secrets


def build_report(secrets, today, warning_days):
    """Classify every secret and group the results by urgency."""
    report = {"expired": [], "warning": [], "ok": []}
    for secret in secrets:
        result = check_secret_status(secret, today=today, warning_days=warning_days)
        report[result["status"]].append(result)

    report["summary"] = {
        "expired": len(report["expired"]),
        "warning": len(report["warning"]),
        "ok": len(report["ok"]),
        "total": len(secrets),
    }
    return report


def render_json(report):
    """Render a report as pretty-printed JSON."""
    return json.dumps(report, indent=2)


def render_markdown(report):
    """Render a report as a Markdown document with one table per urgency section."""
    lines = ["# Secret Rotation Report", ""]
    summary = report["summary"]
    lines.append(
        f"Total: {summary['total']} | Expired: {summary['expired']} | "
        f"Warning: {summary['warning']} | OK: {summary['ok']}"
    )
    lines.append("")

    for section, title in (("expired", "Expired"), ("warning", "Warning"), ("ok", "OK")):
        lines.append(f"## {title}")
        lines.append("")
        entries = report[section]
        if not entries:
            lines.append("_None_")
            lines.append("")
            continue
        lines.append("| Name | Status | Days Until Expiry | Expiry Date | Required By |")
        lines.append("|------|--------|--------------------|-------------|-------------|")
        for entry in entries:
            required_by = ", ".join(entry["required_by"])
            lines.append(
                f"| {entry['name']} | {entry['status']} | {entry['days_until_expiry']} "
                f"| {entry['expiry_date']} | {required_by} |"
            )
        lines.append("")

    return "\n".join(lines)


def main(argv=None):
    """CLI entry point: load a secrets config, build a report, print it."""
    parser = argparse.ArgumentParser(description="Validate secret rotation policies.")
    parser.add_argument("config", help="Path to the secrets JSON config file")
    parser.add_argument(
        "--warning-days", type=int, default=14,
        help="Days before expiry to start warning (default: 14)",
    )
    parser.add_argument(
        "--format", choices=["markdown", "json"], default="markdown",
        help="Output format (default: markdown)",
    )
    parser.add_argument(
        "--fail-on-expired", action="store_true",
        help="Exit with a non-zero status if any secret is expired",
    )
    args = parser.parse_args(argv)

    try:
        secrets = load_secrets(args.config)
    except SecretConfigError as e:
        print(f"Error: {e}", file=sys.stderr)
        return 2

    today = datetime.date.today()
    report = build_report(secrets, today=today, warning_days=args.warning_days)

    if args.format == "json":
        print(render_json(report))
    else:
        print(render_markdown(report))

    if args.fail_on_expired and report["summary"]["expired"] > 0:
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
