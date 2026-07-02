"""Secret rotation validator.

Reads a JSON config describing secrets (name, last-rotated date, rotation
policy in days, required-by services), classifies each secret as
expired / warning / ok relative to a reference date and a configurable
warning window, and renders a rotation report as a markdown table or JSON.

Approach (built via red/green TDD):
  1. classify_secret  - pure date math for one secret
  2. load_config      - parse + validate input with meaningful errors
  3. generate_report  - classify all secrets, group by urgency
  4. format_markdown / format_json - render the report
  5. main             - thin CLI wrapper
"""
import argparse
import datetime
import json
import sys


class ConfigError(Exception):
    """Raised when the secrets config is missing, unreadable, or malformed."""


def _validate_secret(secret, index):
    """Validate one secret entry; raise ConfigError naming the bad field."""
    label = f"secrets[{index}]"
    if not isinstance(secret, dict):
        raise ConfigError(f"{label}: each secret must be an object")

    for field in ("name", "last_rotated", "rotation_days", "required_by"):
        if field not in secret:
            raise ConfigError(f"{label}: missing required field '{field}'")

    if not isinstance(secret["name"], str) or not secret["name"]:
        raise ConfigError(f"{label}: 'name' must be a non-empty string")

    try:
        datetime.date.fromisoformat(secret["last_rotated"])
    except (TypeError, ValueError):
        raise ConfigError(
            f"{label} ({secret['name']}): 'last_rotated' must be an ISO date "
            f"(YYYY-MM-DD), got {secret['last_rotated']!r}"
        )

    days = secret["rotation_days"]
    if not isinstance(days, int) or isinstance(days, bool) or days <= 0:
        raise ConfigError(
            f"{label} ({secret['name']}): 'rotation_days' must be a "
            f"positive integer, got {days!r}"
        )

    required_by = secret["required_by"]
    if not isinstance(required_by, list) or not all(
        isinstance(s, str) for s in required_by
    ):
        raise ConfigError(
            f"{label} ({secret['name']}): 'required_by' must be a list of "
            f"service names"
        )


def load_config(path):
    """Load and validate the secrets config JSON; raise ConfigError on any problem."""
    try:
        with open(path, encoding="utf-8") as f:
            raw = f.read()
    except FileNotFoundError:
        raise ConfigError(f"Config file not found: {path}")
    except OSError as exc:
        raise ConfigError(f"Cannot read config file {path}: {exc}")

    try:
        config = json.loads(raw)
    except json.JSONDecodeError as exc:
        raise ConfigError(f"Invalid JSON in {path}: {exc}")

    if not isinstance(config, dict):
        raise ConfigError(f"{path}: top-level config must be a JSON object")
    if "secrets" not in config:
        raise ConfigError(f"{path}: missing required key 'secrets'")
    if not isinstance(config["secrets"], list):
        raise ConfigError(f"{path}: 'secrets' must be a list")

    for i, secret in enumerate(config["secrets"]):
        _validate_secret(secret, i)

    return config


def classify_secret(secret, today, warn_days):
    """Classify one secret dict against `today`.

    Returns a copy of the secret enriched with expiry_date,
    days_until_expiry, and status (expired / warning / ok).
    A secret is expired the day its rotation policy elapses.
    """
    last_rotated = datetime.date.fromisoformat(secret["last_rotated"])
    expiry_date = last_rotated + datetime.timedelta(days=secret["rotation_days"])
    days_until_expiry = (expiry_date - today).days

    if days_until_expiry <= 0:
        status = "expired"
    elif days_until_expiry <= warn_days:
        status = "warning"
    else:
        status = "ok"

    return {
        **secret,
        "expiry_date": expiry_date.isoformat(),
        "days_until_expiry": days_until_expiry,
        "status": status,
    }


def generate_report(secrets, today, warn_days):
    """Classify every secret and group by urgency, most urgent first."""
    classified = sorted(
        (classify_secret(s, today, warn_days) for s in secrets),
        key=lambda s: s["days_until_expiry"],
    )
    groups = {"expired": [], "warning": [], "ok": []}
    for secret in classified:
        groups[secret["status"]].append(secret)

    return {
        "reference_date": today.isoformat(),
        "warn_days": warn_days,
        "summary": {
            "expired": len(groups["expired"]),
            "warning": len(groups["warning"]),
            "ok": len(groups["ok"]),
            "total": len(classified),
        },
        **groups,
    }


def format_json(report):
    """Render the report as pretty-printed JSON."""
    return json.dumps(report, indent=2)


def format_markdown(report):
    """Render the report as a markdown document with one table row per secret."""
    summary = report["summary"]
    lines = [
        "# Secret Rotation Report",
        "",
        f"Reference date: {report['reference_date']} | "
        f"warning window: {report['warn_days']} days",
        "",
        f"**{summary['expired']} expired**, "
        f"**{summary['warning']} expiring soon**, "
        f"{summary['ok']} ok ({summary['total']} total)",
        "",
        "| Status | Secret | Expiry date | Days left | Required by |",
        "| --- | --- | --- | --- | --- |",
    ]
    for group in ("expired", "warning", "ok"):
        for s in report[group]:
            lines.append(
                f"| {s['status'].upper()} | {s['name']} | {s['expiry_date']} "
                f"| {s['days_until_expiry']} | {', '.join(s['required_by'])} |"
            )
    return "\n".join(lines) + "\n"


FORMATTERS = {"markdown": format_markdown, "json": format_json}


def main(argv=None):
    """CLI entry point. Exit codes: 0 ok, 1 usage/config error, 2 expired secrets."""
    parser = argparse.ArgumentParser(
        description="Validate secret rotation status and emit a report."
    )
    parser.add_argument("--config", required=True, help="Path to secrets JSON config")
    parser.add_argument(
        "--format", choices=sorted(FORMATTERS), default="markdown",
        help="Output format (default: markdown)",
    )
    parser.add_argument(
        "--warn-days", type=int, default=None,
        help="Warning window in days (overrides config; default 14)",
    )
    parser.add_argument(
        "--today", default=None,
        help="Reference date YYYY-MM-DD (overrides config; default: system date)",
    )
    parser.add_argument(
        "--fail-on-expired", action="store_true",
        help="Exit with code 2 if any secret is expired",
    )
    args = parser.parse_args(argv)

    try:
        config = load_config(args.config)
    except ConfigError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1

    # Precedence for reference date / warn window: CLI flag > config > default.
    today_str = args.today or config.get("reference_date")
    try:
        today = (
            datetime.date.fromisoformat(today_str)
            if today_str
            else datetime.date.today()
        )
    except ValueError:
        print(f"error: invalid reference date {today_str!r} "
              f"(expected YYYY-MM-DD)", file=sys.stderr)
        return 1

    warn_days = args.warn_days if args.warn_days is not None else config.get("warn_days", 14)
    if not isinstance(warn_days, int) or warn_days < 0:
        print(f"error: warn_days must be a non-negative integer, "
              f"got {warn_days!r}", file=sys.stderr)
        return 1

    report = generate_report(config["secrets"], today, warn_days)
    print(FORMATTERS[args.format](report))

    if args.fail_on_expired and report["summary"]["expired"] > 0:
        print(f"error: {report['summary']['expired']} secret(s) require "
              f"immediate rotation", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
