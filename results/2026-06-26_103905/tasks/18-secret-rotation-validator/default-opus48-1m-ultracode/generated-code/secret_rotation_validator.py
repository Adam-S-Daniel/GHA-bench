#!/usr/bin/env python3
"""Secret Rotation Validator.

Given a configuration of secrets with metadata (name, last-rotated date,
rotation policy in days, required-by services), determine which secrets are
expired or expiring within a configurable warning window, then emit a rotation
report / notifications grouped by urgency in either markdown or JSON.

Built with stdlib only (no third-party runtime deps) so it runs unchanged on a
vanilla CI runner. See README.md for usage.
"""

from __future__ import annotations

import argparse
import datetime
import json
import sys


# Urgency buckets, ordered from most to least urgent. Used everywhere we group
# or render so the ordering stays consistent.
URGENCY_ORDER = ("expired", "warning", "ok")

# Human-readable labels for each urgency bucket (kept ASCII / emoji-free so the
# output is easy to diff and assert on).
URGENCY_LABELS = {"expired": "Expired", "warning": "Warning", "ok": "OK"}

# Supported output formats.
OUTPUT_FORMATS = ("markdown", "json", "summary")


class ConfigError(Exception):
    """Raised when the configuration file is missing, malformed, or invalid.

    Carries a human-readable message; ``main`` prints it to stderr and exits
    with a non-zero status so CI surfaces the problem clearly.
    """


# ---------------------------------------------------------------------------
# Config loading + validation (fail early with a message that names the secret).
# ---------------------------------------------------------------------------
def load_config(path: str) -> dict:
    """Read and validate the secrets config file, returning the parsed dict.

    Every failure mode (missing file, bad JSON, missing/invalid fields) raises
    ``ConfigError`` with a message specific enough to fix the config.
    """
    try:
        with open(path, encoding="utf-8") as handle:
            raw = handle.read()
    except FileNotFoundError:
        raise ConfigError(f"Config file not found: {path}")
    except OSError as exc:  # permissions, is-a-directory, etc.
        raise ConfigError(f"Could not read config file {path}: {exc}")

    try:
        data = json.loads(raw)
    except json.JSONDecodeError as exc:
        raise ConfigError(f"Config file {path} is not valid JSON: {exc}")

    if not isinstance(data, dict):
        raise ConfigError("Config root must be a JSON object")

    secrets = data.get("secrets")
    if secrets is None:
        raise ConfigError("Config is missing the required 'secrets' key")
    if not isinstance(secrets, list):
        raise ConfigError("'secrets' must be a list")

    for index, secret in enumerate(secrets):
        _validate_secret(secret, index)

    return data


def _validate_secret(secret: object, index: int) -> None:
    """Validate one secret entry in place, raising ConfigError on any problem."""
    if not isinstance(secret, dict):
        raise ConfigError(f"Secret #{index} must be a JSON object")

    name = secret.get("name")
    if not isinstance(name, str) or not name:
        raise ConfigError(f"Secret #{index} is missing a non-empty string 'name'")

    for field in ("last_rotated", "rotation_policy_days"):
        if field not in secret:
            raise ConfigError(
                f"Secret {name!r} is missing required field {field!r}")

    try:
        datetime.date.fromisoformat(secret["last_rotated"])
    except (ValueError, TypeError):
        raise ConfigError(
            f"Secret {name!r} has invalid 'last_rotated' value "
            f"{secret['last_rotated']!r}; expected an ISO date (YYYY-MM-DD)")

    policy = secret["rotation_policy_days"]
    # bool is a subclass of int, so reject it explicitly.
    if isinstance(policy, bool) or not isinstance(policy, int) or policy <= 0:
        raise ConfigError(
            f"Secret {name!r} has invalid 'rotation_policy_days' {policy!r}; "
            f"expected a positive integer")

    required_by = secret.get("required_by", [])
    if not isinstance(required_by, list) or not all(
        isinstance(item, str) for item in required_by
    ):
        raise ConfigError(
            f"Secret {name!r} has invalid 'required_by'; "
            f"expected a list of service-name strings")


def classify_secret(secret: dict, now: datetime.date, warning_days: int) -> dict:
    """Classify one secret into an urgency bucket relative to ``now``.

    A secret "expires" ``rotation_policy_days`` after it was last rotated.

    * expired  -> the expiry date is already in the past.
    * warning  -> it expires today or within the next ``warning_days`` days.
    * ok       -> it expires further out than the warning window.

    Returns an enriched dict (the original metadata plus computed fields) rather
    than mutating the input, so callers can render it directly.
    """
    last_rotated = datetime.date.fromisoformat(secret["last_rotated"])
    policy_days = secret["rotation_policy_days"]
    expires_on = last_rotated + datetime.timedelta(days=policy_days)
    days_until_expiry = (expires_on - now).days

    if days_until_expiry < 0:
        status = "expired"
        message = f"{-days_until_expiry} days overdue"
    elif days_until_expiry <= warning_days:
        status = "warning"
        message = f"expires in {days_until_expiry} days"
    else:
        status = "ok"
        message = f"expires in {days_until_expiry} days"

    return {
        "name": secret["name"],
        "last_rotated": last_rotated.isoformat(),
        "rotation_policy_days": policy_days,
        "expires_on": expires_on.isoformat(),
        "days_until_expiry": days_until_expiry,
        "status": status,
        "required_by": list(secret.get("required_by", [])),
        "message": message,
    }


def build_report(config: dict, warning_days: int, now: datetime.date) -> dict:
    """Classify every secret and assemble the full rotation report.

    Returns a JSON-serialisable dict with three parts:
      * ``generated_at`` / ``warning_days`` -- run metadata.
      * ``summary``  -- counts per urgency plus a total.
      * ``groups``   -- the secrets themselves, bucketed by urgency and sorted
                        most-urgent-first (smallest days_until_expiry) so the
                        report reads as a prioritised to-do list.
    """
    groups: dict[str, list] = {bucket: [] for bucket in URGENCY_ORDER}
    for secret in config["secrets"]:
        classified = classify_secret(secret, now=now, warning_days=warning_days)
        groups[classified["status"]].append(classified)

    for bucket in groups.values():
        bucket.sort(key=lambda s: s["days_until_expiry"])

    summary = {bucket: len(groups[bucket]) for bucket in URGENCY_ORDER}
    summary["total"] = sum(summary[b] for b in URGENCY_ORDER)

    return {
        "generated_at": now.isoformat(),
        "warning_days": warning_days,
        "summary": summary,
        "groups": groups,
    }


# ---------------------------------------------------------------------------
# Rendering: turn a report dict into one of the supported output formats.
# ---------------------------------------------------------------------------
def render(report: dict, fmt: str) -> str:
    """Render ``report`` in the requested format ('markdown', 'json', 'summary')."""
    if fmt == "json":
        return render_json(report)
    if fmt == "markdown":
        return render_markdown(report)
    if fmt == "summary":
        return render_summary(report)
    raise ValueError(
        f"Unknown output format {fmt!r}; expected one of {', '.join(OUTPUT_FORMATS)}"
    )


def render_json(report: dict) -> str:
    """Pretty-printed JSON of the full report (groups + summary + metadata)."""
    return json.dumps(report, indent=2)


def render_summary(report: dict) -> str:
    """A single machine-parseable line, e.g. ``expired=2 warning=1 ok=1 total=4``."""
    s = report["summary"]
    return f"expired={s['expired']} warning={s['warning']} ok={s['ok']} total={s['total']}"


def _required_by(secret: dict) -> str:
    """Render the required-by services as a comma list (or '-' when none)."""
    return ", ".join(secret["required_by"]) if secret["required_by"] else "-"


def render_markdown(report: dict) -> str:
    """Render a GitHub-flavoured markdown report.

    Layout: a title + run metadata, a summary count table, then one section per
    urgency bucket (the grouped "notifications"), each a table of its secrets.
    """
    s = report["summary"]
    lines: list[str] = [
        "# Secret Rotation Report",
        "",
        f"Generated: {report['generated_at']} | "
        f"Warning window: {report['warning_days']} days",
        "",
        "## Summary",
        "",
        "| Urgency | Count |",
        "| --- | --- |",
        f"| Expired | {s['expired']} |",
        f"| Warning | {s['warning']} |",
        f"| OK | {s['ok']} |",
        f"| Total | {s['total']} |",
    ]

    for bucket in URGENCY_ORDER:
        secrets = report["groups"][bucket]
        lines += ["", f"## {URGENCY_LABELS[bucket]} ({len(secrets)})", ""]
        if not secrets:
            lines.append("_None_")
            continue
        lines += [
            "| Secret | Last Rotated | Policy (days) | Status | Required By |",
            "| --- | --- | --- | --- | --- |",
        ]
        for secret in secrets:
            lines.append(
                f"| {secret['name']} | {secret['last_rotated']} | "
                f"{secret['rotation_policy_days']} | {secret['message']} | "
                f"{_required_by(secret)} |"
            )

    return "\n".join(lines) + "\n"


# ---------------------------------------------------------------------------
# CLI: wire config -> report -> render, with config-file defaults that CLI
# flags override, and a CI-friendly --fail-on gate.
# ---------------------------------------------------------------------------
# Exit codes: 0 ok, 2 configuration error, 3 gate tripped (--fail-on).
EXIT_OK = 0
EXIT_CONFIG_ERROR = 2
EXIT_GATE_TRIPPED = 3


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="secret_rotation_validator",
        description="Validate secret rotation policies and report by urgency.",
    )
    parser.add_argument("--config", required=True,
                        help="Path to the secrets config JSON file.")
    parser.add_argument("--warning-days", type=int, default=None,
                        help="Warn this many days before expiry "
                             "(default: config 'warning_days' or 14).")
    parser.add_argument("--now", default=None,
                        help="Reference date YYYY-MM-DD used as 'today' "
                             "(default: config 'now' or the real today).")
    parser.add_argument("--format", choices=OUTPUT_FORMATS, default=None,
                        help="Output format (default: config 'format' or markdown).")
    parser.add_argument("--fail-on", choices=("none", "warning", "expired"),
                        default="none",
                        help="Exit non-zero if any secret reaches this urgency "
                             "(default: none -> always exit 0 on success).")
    return parser


def _resolve_now(cli_now: str | None, config: dict) -> datetime.date:
    """Pick the reference date: CLI flag > config 'now' > the real today()."""
    raw = cli_now if cli_now is not None else config.get("now")
    if raw is None:
        return datetime.date.today()
    try:
        return datetime.date.fromisoformat(raw)
    except (ValueError, TypeError):
        raise ConfigError(f"Invalid --now date {raw!r}; expected YYYY-MM-DD")


def _resolve_warning_days(cli_value: int | None, config: dict) -> int:
    raw = cli_value if cli_value is not None else config.get("warning_days", 14)
    if isinstance(raw, bool) or not isinstance(raw, int) or raw < 0:
        raise ConfigError(
            f"Invalid warning_days {raw!r}; expected a non-negative integer")
    return raw


def _gate_exit_code(report: dict, fail_on: str) -> int:
    """Map the --fail-on threshold onto an exit code given the report summary."""
    summary = report["summary"]
    if fail_on == "expired" and summary["expired"] > 0:
        return EXIT_GATE_TRIPPED
    if fail_on == "warning" and (summary["expired"] > 0 or summary["warning"] > 0):
        return EXIT_GATE_TRIPPED
    return EXIT_OK


def main(argv: list[str] | None = None) -> int:
    """CLI entry point. Returns a process exit code (see EXIT_* above)."""
    args = _build_parser().parse_args(argv)
    try:
        config = load_config(args.config)
        warning_days = _resolve_warning_days(args.warning_days, config)
        now = _resolve_now(args.now, config)
        fmt = args.format or config.get("format", "markdown")
        if fmt not in OUTPUT_FORMATS:
            raise ConfigError(
                f"Invalid format {fmt!r}; expected one of {', '.join(OUTPUT_FORMATS)}")
        report = build_report(config, warning_days=warning_days, now=now)
    except ConfigError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return EXIT_CONFIG_ERROR

    print(render(report, fmt))
    return _gate_exit_code(report, args.fail_on)


if __name__ == "__main__":  # pragma: no cover - exercised via the CLI / workflow
    sys.exit(main())
