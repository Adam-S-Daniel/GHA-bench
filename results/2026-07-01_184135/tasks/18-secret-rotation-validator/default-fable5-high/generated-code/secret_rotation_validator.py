"""Secret rotation validator.

Given a config of secrets (name, last-rotated date, rotation policy in
days, required-by services), classify each secret as expired / warning /
ok relative to an as-of date and a configurable warning window.
Usage:
    python3 secret_rotation_validator.py --config secrets.json \
        [--as-of YYYY-MM-DD] [--warn-days N] [--format markdown|json]

Exit codes: 0 = report produced, 1 = config/usage error (message on stderr).
"""

import argparse
import datetime
import json
import sys

#: Group order also encodes urgency: most urgent first.
STATUSES = ("expired", "warning", "ok")

REQUIRED_FIELDS = ("name", "last_rotated", "rotation_days", "required_by")


class ConfigError(Exception):
    """Raised for any problem with the secrets config file.

    The message is always actionable: it names the file, the offending
    secret (by position and name where possible), and what was expected.
    """


def _validate_secret(secret, index):
    """Validate one secret entry; return a normalized copy."""
    label = f"Secret #{index}"
    if isinstance(secret, dict) and isinstance(secret.get("name"), str):
        label = f"Secret #{index} ({secret['name']!r})"
    if not isinstance(secret, dict):
        raise ConfigError(f"{label}: must be an object, got {type(secret).__name__}")
    for field in REQUIRED_FIELDS:
        if field not in secret:
            raise ConfigError(f"{label}: missing required field {field!r}")
    if not isinstance(secret["name"], str) or not secret["name"].strip():
        raise ConfigError(f"{label}: name must be a non-empty string")
    try:
        datetime.date.fromisoformat(secret["last_rotated"])
    except (TypeError, ValueError):
        raise ConfigError(
            f"{label}: invalid last_rotated {secret['last_rotated']!r} "
            "(expected YYYY-MM-DD)"
        )
    rotation_days = secret["rotation_days"]
    # bool is an int subclass; reject it explicitly.
    if not isinstance(rotation_days, int) or isinstance(rotation_days, bool) \
            or rotation_days <= 0:
        raise ConfigError(
            f"{label}: rotation_days must be a positive integer, "
            f"got {rotation_days!r}"
        )
    required_by = secret["required_by"]
    if not isinstance(required_by, list) \
            or not all(isinstance(s, str) for s in required_by):
        raise ConfigError(
            f"{label}: required_by must be a list of service names, "
            f"got {required_by!r}"
        )
    return {
        "name": secret["name"],
        "last_rotated": secret["last_rotated"],
        "rotation_days": rotation_days,
        "required_by": required_by,
    }


def load_config(path):
    """Load and validate a secrets config file; return the secrets list."""
    try:
        with open(path, encoding="utf-8") as handle:
            raw = json.load(handle)
    except FileNotFoundError:
        raise ConfigError(f"Config file not found: {path}")
    except json.JSONDecodeError as exc:
        raise ConfigError(f"Invalid JSON in {path}: {exc}")
    except OSError as exc:
        raise ConfigError(f"Cannot read config file {path}: {exc}")
    if not isinstance(raw, dict) or not isinstance(raw.get("secrets"), list):
        raise ConfigError(
            f"Config {path} must contain a 'secrets' list at the top level"
        )
    secrets, seen = [], set()
    for index, secret in enumerate(raw["secrets"], start=1):
        entry = _validate_secret(secret, index)
        if entry["name"] in seen:
            raise ConfigError(
                f"Secret #{index}: duplicate secret name {entry['name']!r}"
            )
        seen.add(entry["name"])
        secrets.append(entry)
    return secrets


def classify_secret(secret, as_of, warn_days):
    """Classify one secret against `as_of`.

    A secret is due `rotation_days` after `last_rotated`. It is:
      - "expired" when the due date is today or in the past
        (days_remaining <= 0 -- due *today* means "rotate now");
      - "warning" when it is due within `warn_days` (boundary inclusive);
      - "ok" otherwise.
    """
    last_rotated = datetime.date.fromisoformat(secret["last_rotated"])
    due_date = last_rotated + datetime.timedelta(days=secret["rotation_days"])
    days_remaining = (due_date - as_of).days
    if days_remaining <= 0:
        status = "expired"
    elif days_remaining <= warn_days:
        status = "warning"
    else:
        status = "ok"
    return {
        "name": secret["name"],
        "status": status,
        "last_rotated": secret["last_rotated"],
        "due_date": due_date.isoformat(),
        "days_remaining": days_remaining,
        "required_by": list(secret["required_by"]),
    }


def _notification(entry):
    """Human-readable notification line for one classified secret."""
    services = ", ".join(entry["required_by"])
    impact = f" Impacted services: {services}" if services else ""
    if entry["status"] == "expired":
        overdue = -entry["days_remaining"]
        when = "today" if overdue == 0 else f"{overdue} days overdue"
        return (
            f"EXPIRED: '{entry['name']}' was due {entry['due_date']} "
            f"({when}); rotate immediately.{impact}"
        )
    if entry["status"] == "warning":
        return (
            f"WARNING: '{entry['name']}' is due {entry['due_date']} "
            f"(in {entry['days_remaining']} days).{impact}"
        )
    return (
        f"OK: '{entry['name']}' is due {entry['due_date']} "
        f"(in {entry['days_remaining']} days)."
    )


def build_report(secrets, as_of, warn_days):
    """Classify every secret and group results by urgency.

    Within each group, the most urgent secret (fewest days remaining)
    comes first so notifications read top-down by priority.
    """
    groups = {status: [] for status in STATUSES}
    for secret in secrets:
        entry = classify_secret(secret, as_of=as_of, warn_days=warn_days)
        entry["message"] = _notification(entry)
        groups[entry["status"]].append(entry)
    for entries in groups.values():
        entries.sort(key=lambda e: (e["days_remaining"], e["name"]))
    return {
        "as_of": as_of.isoformat(),
        "warn_days": warn_days,
        "summary": {status: len(groups[status]) for status in STATUSES},
        "groups": groups,
    }


def _all_entries(report):
    """All classified secrets in urgency order (expired -> warning -> ok)."""
    return [e for status in STATUSES for e in report["groups"][status]]


def _render_markdown(report):
    summary = report["summary"]
    lines = [
        "# Secret Rotation Report",
        "",
        f"- As of: {report['as_of']}",
        f"- Warning window: {report['warn_days']} days",
        "- Summary: {expired} expired, {warning} warning, {ok} ok".format(**summary),
        "",
        "| Secret | Status | Last rotated | Due date | Days remaining | Required by |",
        "| --- | --- | --- | --- | --- | --- |",
    ]
    for e in _all_entries(report):
        lines.append(
            "| {name} | {status} | {last_rotated} | {due_date} "
            "| {days_remaining} | {required_by} |".format(
                name=e["name"],
                status=e["status"].upper(),
                last_rotated=e["last_rotated"],
                due_date=e["due_date"],
                days_remaining=e["days_remaining"],
                required_by=", ".join(e["required_by"]) or "-",
            )
        )
    lines += ["", "## Notifications"]
    for status in STATUSES:
        entries = report["groups"][status]
        lines += ["", f"### {status.capitalize()} ({len(entries)})", ""]
        lines += [f"- {e['message']}" for e in entries] or ["- none"]
    return "\n".join(lines)


def render_report(report, output_format):
    """Render a report as 'markdown' or 'json'."""
    if output_format == "markdown":
        return _render_markdown(report)
    if output_format == "json":
        return json.dumps(report, indent=2)
    raise ValueError(
        f"Unsupported format {output_format!r}: expected 'markdown' or 'json'"
    )


def _today():
    """Injectable clock: tests patch this instead of the real date."""
    return datetime.date.today()


def main(argv=None):
    """CLI entry point. Returns a process exit code instead of exiting,
    so tests can call it in-process."""
    parser = argparse.ArgumentParser(
        prog="secret_rotation_validator",
        description="Report secrets that are expired or expiring soon.",
    )
    parser.add_argument("--config", required=True,
                        help="path to the secrets JSON config")
    parser.add_argument("--as-of", default=None, metavar="YYYY-MM-DD",
                        help="evaluate as of this date (default: today)")
    parser.add_argument("--warn-days", type=int, default=14,
                        help="warning window in days (default: 14)")
    parser.add_argument("--format", choices=("markdown", "json"),
                        default="markdown", help="output format")
    args = parser.parse_args(argv)

    try:
        if args.as_of is None:
            as_of = _today()
        else:
            try:
                as_of = datetime.date.fromisoformat(args.as_of)
            except ValueError:
                raise ConfigError(
                    f"invalid --as-of {args.as_of!r} (expected YYYY-MM-DD)"
                )
        if args.warn_days < 0:
            raise ConfigError(f"--warn-days must be >= 0, got {args.warn_days}")
        secrets = load_config(args.config)
        report = build_report(secrets, as_of=as_of, warn_days=args.warn_days)
        print(render_report(report, args.format))
        return 0
    except ConfigError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
