#!/usr/bin/env python3
"""Dependency License Checker.

Parse a dependency manifest (``package.json`` or ``requirements.txt``), look up
each dependency's license, classify it against an allow-list / deny-list policy,
and produce a compliance report listing every dependency's status
(``approved`` / ``denied`` / ``unknown``).

Design notes
------------
* **The license lookup is an injectable seam.**  Real-world license discovery
  means querying a registry (npm, PyPI, ``license-checker`` ...) over the
  network.  That is slow and non-deterministic, so the lookup is modelled as a
  callable ``resolve(name, version) -> Optional[str]``.  In production we build
  that callable from a "license database" JSON file; in tests we inject a plain
  ``dict``.  This is exactly the *mock* the task asks for.
* **Deny beats allow.**  If a license somehow appears on both lists we treat it
  as ``denied`` -- failing safe is the only sane default for a compliance gate.
* **Errors are surfaced as meaningful messages**, never raw tracebacks, via the
  ``ManifestError`` / ``ConfigError`` exception types and the CLI's exit codes.

Built with red/green TDD -- see ``tests/test_license_checker.py``.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
from dataclasses import dataclass
from typing import Callable, Optional


# --------------------------------------------------------------------------- #
# Errors
# --------------------------------------------------------------------------- #
class ManifestError(Exception):
    """Raised when a dependency manifest cannot be read or parsed."""


class ConfigError(Exception):
    """Raised when the policy / license-db config cannot be read or parsed."""


# --------------------------------------------------------------------------- #
# Data model
# --------------------------------------------------------------------------- #
@dataclass(frozen=True)
class Dependency:
    """A single dependency extracted from a manifest."""

    name: str
    version: str


@dataclass
class Policy:
    """The allow-list / deny-list compliance policy."""

    allow: list
    deny: list


@dataclass
class LicenseRecord:
    """The result of checking one dependency."""

    name: str
    version: str
    license: Optional[str]
    status: str  # "approved" | "denied" | "unknown"


# --------------------------------------------------------------------------- #
# Manifest parsing
# --------------------------------------------------------------------------- #
# A leading version-range operator that npm / pip allow in front of a version
# (e.g. ``^4.17.21`` or ``>= 2.0.0``).  We strip it to report a bare version.
_RANGE_PREFIX = re.compile(r"^[\^~>=<!= ]+")
# ``name`` optionally followed by ``[extras]`` then the rest of the spec.
_REQ_LINE = re.compile(r"^([A-Za-z0-9][A-Za-z0-9._-]*)\s*(?:\[[^\]]*\])?\s*(.*)$")


def _clean_version(raw: object) -> str:
    """Normalise a version spec to a bare version string."""
    return _RANGE_PREFIX.sub("", str(raw).strip()).strip()


def _parse_package_json(text: str, label: str) -> list[Dependency]:
    """Parse npm-style ``package.json`` content."""
    try:
        data = json.loads(text)
    except json.JSONDecodeError as exc:
        raise ManifestError(f"Manifest '{label}' is not valid JSON: {exc}") from exc
    if not isinstance(data, dict):
        raise ManifestError(f"Manifest '{label}' must be a JSON object.")
    deps: list[Dependency] = []
    section = data.get("dependencies") or {}
    if not isinstance(section, dict):
        raise ManifestError(
            f"Manifest '{label}' has a non-object 'dependencies' section."
        )
    for name, spec in section.items():
        deps.append(Dependency(name=name, version=_clean_version(spec)))
    return deps


def _parse_requirements_txt(text: str) -> list[Dependency]:
    """Parse pip-style ``requirements.txt`` content."""
    deps: list[Dependency] = []
    for raw in text.splitlines():
        line = raw.split("#", 1)[0].strip()  # drop comments / inline comments
        if not line or line.startswith("-"):  # skip blanks and pip directives
            continue
        m = _REQ_LINE.match(line)
        if not m:
            continue
        name = m.group(1)
        deps.append(Dependency(name=name, version=_clean_version(m.group(2))))
    return deps


def parse_manifest(path: str) -> list[Dependency]:
    """Parse a dependency manifest and return its dependencies.

    The format is auto-detected from the file name:
    ``*.json`` -> npm ``package.json``; ``*.txt`` -> pip ``requirements.txt``.

    Raises :class:`ManifestError` with a meaningful message if the file is
    missing, unreadable, of an unsupported type, or malformed.
    """
    name = os.path.basename(path).lower()
    try:
        with open(path, "r", encoding="utf-8") as fh:
            text = fh.read()
    except FileNotFoundError as exc:
        raise ManifestError(f"Manifest file not found: {path}") from exc
    except OSError as exc:
        raise ManifestError(f"Could not read manifest '{path}': {exc}") from exc

    if name.endswith(".json"):
        return _parse_package_json(text, os.path.basename(path))
    if name.endswith(".txt"):
        return _parse_requirements_txt(text)
    raise ManifestError(
        f"Unsupported manifest type: '{os.path.basename(path)}'. "
        "Expected a *.json (package.json) or *.txt (requirements.txt) file."
    )


# --------------------------------------------------------------------------- #
# License lookup (mockable) + policy classification
# --------------------------------------------------------------------------- #
def make_license_resolver(license_db: dict) -> Callable[[str, str], Optional[str]]:
    """Build a license-lookup callable backed by a *mock* license database.

    Lookup order: an exact ``"name@version"`` key first, then a bare ``"name"``
    key.  Returns ``None`` when the dependency is unknown to the database -- the
    real-world equivalent of "the registry has no license metadata".
    """

    def resolve(name: str, version: str) -> Optional[str]:
        return license_db.get(f"{name}@{version}") or license_db.get(name)

    return resolve


def classify(license_id: Optional[str], policy: Policy) -> str:
    """Classify a license against the policy as approved / denied / unknown.

    Matching is case-insensitive and *deny takes precedence over allow*.
    A missing / empty license is always ``unknown``.
    """
    if not license_id or not str(license_id).strip():
        return "unknown"
    norm = str(license_id).strip().lower()
    if norm in {d.strip().lower() for d in policy.deny}:
        return "denied"
    if norm in {a.strip().lower() for a in policy.allow}:
        return "approved"
    return "unknown"


def check_dependencies(
    deps: list[Dependency],
    resolve_license: Callable[[str, str], Optional[str]],
    policy: Policy,
) -> list[LicenseRecord]:
    """Resolve and classify every dependency, returning one record each."""
    records: list[LicenseRecord] = []
    for dep in deps:
        license_id = resolve_license(dep.name, dep.version)
        records.append(
            LicenseRecord(
                name=dep.name,
                version=dep.version,
                license=license_id,
                status=classify(license_id, policy),
            )
        )
    return records


def summarize(records: list[LicenseRecord]) -> dict:
    """Tally records into total / approved / denied / unknown counts."""
    summary = {"total": len(records), "approved": 0, "denied": 0, "unknown": 0}
    for rec in records:
        summary[rec.status] = summary.get(rec.status, 0) + 1
    return summary


# --------------------------------------------------------------------------- #
# Report rendering
# --------------------------------------------------------------------------- #
def format_report(records: list[LicenseRecord], summary: dict, fmt: str = "text") -> str:
    """Render the compliance report as ``text`` or ``json``.

    The text format ends with a single machine-readable line that CI can grep:
    ``LICENSE-CHECK-SUMMARY total=N approved=N denied=N unknown=N``.
    """
    if fmt == "json":
        return json.dumps(
            {
                "summary": summary,
                "dependencies": [
                    {
                        "name": r.name,
                        "version": r.version,
                        "license": r.license,
                        "status": r.status,
                    }
                    for r in records
                ],
            },
            indent=2,
        )
    if fmt == "text":
        lines = [
            "Dependency License Compliance Report",
            "====================================",
        ]
        for r in records:
            shown = r.license if r.license else "UNKNOWN"
            lines.append(f"- {r.name}@{r.version}: {shown} [{r.status}]")
        lines.append("")
        lines.append(
            "Summary: {total} dependencies | approved={approved} "
            "denied={denied} unknown={unknown}".format(**summary)
        )
        lines.append(
            "LICENSE-CHECK-SUMMARY total={total} approved={approved} "
            "denied={denied} unknown={unknown}".format(**summary)
        )
        return "\n".join(lines)
    raise ValueError(f"Unknown report format: {fmt!r} (expected 'text' or 'json').")


# --------------------------------------------------------------------------- #
# Config loading
# --------------------------------------------------------------------------- #
def _load_json_file(path: str, what: str) -> object:
    try:
        with open(path, "r", encoding="utf-8") as fh:
            return json.load(fh)
    except FileNotFoundError as exc:
        raise ConfigError(f"{what} file not found: {path}") from exc
    except json.JSONDecodeError as exc:
        raise ConfigError(f"{what} file '{path}' is not valid JSON: {exc}") from exc
    except OSError as exc:
        raise ConfigError(f"Could not read {what} file '{path}': {exc}") from exc


def load_policy(path: str) -> Policy:
    """Load the allow/deny policy from a JSON file."""
    data = _load_json_file(path, "Policy")
    if not isinstance(data, dict):
        raise ConfigError(f"Policy file '{path}' must be a JSON object.")
    allow = data.get("allow", [])
    deny = data.get("deny", [])
    if not isinstance(allow, list) or not isinstance(deny, list):
        raise ConfigError(
            f"Policy file '{path}' must have list-valued 'allow' and 'deny' keys."
        )
    return Policy(allow=allow, deny=deny)


def load_license_db(path: str) -> dict:
    """Load the (mock) license database from a JSON file."""
    data = _load_json_file(path, "License database")
    if not isinstance(data, dict):
        raise ConfigError(
            f"License database '{path}' must be a JSON object mapping "
            "name (or name@version) to a license id."
        )
    return data


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #
def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="license_checker.py",
        description="Check dependency licenses against an allow/deny policy.",
    )
    parser.add_argument("--manifest", required=True, help="Path to package.json / requirements.txt")
    parser.add_argument("--policy", required=True, help="Path to allow/deny policy JSON")
    parser.add_argument("--license-db", required=True, help="Path to (mock) license database JSON")
    parser.add_argument("--format", choices=("text", "json"), default="text", help="Report format")
    parser.add_argument("--output", help="Write the report to this file (default: stdout)")
    parser.add_argument(
        "--fail-on-denied",
        action="store_true",
        help="Exit with code 2 if any dependency is denied (for enforcing gates).",
    )
    return parser


def main(argv: Optional[list] = None) -> int:
    """CLI entry point. Returns a process exit code.

    Exit codes: ``0`` report generated; ``2`` ``--fail-on-denied`` and at least
    one denied dependency; ``1`` any input/parse error (message on stderr).
    """
    args = _build_parser().parse_args(argv)
    try:
        deps = parse_manifest(args.manifest)
        policy = load_policy(args.policy)
        license_db = load_license_db(args.license_db)
    except (ManifestError, ConfigError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1

    resolve = make_license_resolver(license_db)
    records = check_dependencies(deps, resolve, policy)
    summary = summarize(records)
    report = format_report(records, summary, fmt=args.format)

    if args.output:
        try:
            with open(args.output, "w", encoding="utf-8") as fh:
                fh.write(report + "\n")
        except OSError as exc:
            print(f"error: could not write report to '{args.output}': {exc}", file=sys.stderr)
            return 1
    else:
        print(report)

    if args.fail_on_denied and summary["denied"] > 0:
        print(
            f"error: {summary['denied']} dependency(ies) use denied licenses.",
            file=sys.stderr,
        )
        return 2
    return 0


if __name__ == "__main__":  # pragma: no cover
    raise SystemExit(main())
