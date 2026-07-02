#!/usr/bin/env python3
"""Dependency license compliance checker.

Approach
--------
1. Parse a dependency manifest (package.json or requirements.txt style).
   The format is auto-detected by *content*, not filename: JSON objects
   are treated as package.json, anything else as pip requirements.
2. Look up each dependency's license through a pluggable LicenseSource.
   In production this would query a registry/API; for testing and CI the
   lookup is mocked with a JSON file mapping name -> SPDX license id.
3. Classify each license against a config with an allow-list and a
   deny-list. Deny wins over allow; anything on neither list is
   'unknown'. Matching is case-insensitive.
4. Emit a pipe-delimited compliance report plus a summary line.

All error paths raise LicenseCheckerError with a human-readable message;
the CLI converts those into stderr output and exit code 1.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import NamedTuple


class LicenseCheckerError(Exception):
    """Any user-facing failure: bad paths, bad formats, bad config."""


class Dependency(NamedTuple):
    name: str
    version: str


# --------------------------------------------------------------------------
# Manifest parsing
# --------------------------------------------------------------------------

# name, optional comparator+version, e.g. "flask>=3.0.0" or bare "pyyaml"
_REQUIREMENT_RE = re.compile(
    r"^(?P<name>[A-Za-z0-9][A-Za-z0-9._-]*)\s*(?:[=<>!~]+\s*(?P<version>[\w.*+-]+))?$"
)


def parse_manifest(path: Path | str) -> list[Dependency]:
    """Parse a manifest file into an ordered list of dependencies."""
    path = Path(path)
    if not path.is_file():
        raise LicenseCheckerError(f"Manifest not found: {path}")
    text = path.read_text(encoding="utf-8")

    # Content-based detection: a JSON object means package.json format.
    if text.lstrip().startswith("{"):
        return _parse_package_json(text, path)
    return _parse_requirements(text, path)


def _parse_package_json(text: str, path: Path) -> list[Dependency]:
    try:
        data = json.loads(text)
    except json.JSONDecodeError as exc:
        raise LicenseCheckerError(f"Invalid JSON in manifest {path}: {exc}") from exc
    if not isinstance(data, dict):
        raise LicenseCheckerError(f"Invalid JSON in manifest {path}: expected an object")

    deps = []
    for section in ("dependencies", "devDependencies"):
        for name, version in (data.get(section) or {}).items():
            # Strip npm range prefixes (^, ~, >=, ...) to a plain version.
            deps.append(Dependency(name, str(version).lstrip("^~><= ") or "unspecified"))
    return deps


def _parse_requirements(text: str, path: Path) -> list[Dependency]:
    deps = []
    for lineno, raw in enumerate(text.splitlines(), start=1):
        line = raw.split("#", 1)[0].strip()  # drop comments and whitespace
        if not line:
            continue
        match = _REQUIREMENT_RE.match(line)
        if not match:
            raise LicenseCheckerError(
                f"Unparseable requirement at {path}:{lineno}: {raw.strip()!r}"
            )
        deps.append(Dependency(match["name"], match["version"] or "unspecified"))
    return deps


# --------------------------------------------------------------------------
# Config
# --------------------------------------------------------------------------

def load_config(path: Path | str) -> dict:
    """Load {'allow': [...], 'deny': [...]} license lists from JSON."""
    path = Path(path)
    if not path.is_file():
        raise LicenseCheckerError(f"Config not found: {path}")
    try:
        config = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        raise LicenseCheckerError(f"Invalid JSON in config {path}: {exc}") from exc
    if not isinstance(config, dict) or "allow" not in config or "deny" not in config:
        raise LicenseCheckerError(
            f"Config {path} must contain 'allow' and 'deny' lists"
        )
    return config


# --------------------------------------------------------------------------
# License lookup (mockable)
# --------------------------------------------------------------------------

class MockLicenseSource:
    """Test/CI stand-in for a real registry lookup.

    Backed by a plain dict of package name -> license id; unknown
    packages return None, exactly like a failed registry lookup would.
    """

    def __init__(self, licenses: dict[str, str]):
        self._licenses = licenses

    @classmethod
    def from_json_file(cls, path: Path | str) -> "MockLicenseSource":
        path = Path(path)
        if not path.is_file():
            raise LicenseCheckerError(f"License database not found: {path}")
        try:
            return cls(json.loads(path.read_text(encoding="utf-8")))
        except json.JSONDecodeError as exc:
            raise LicenseCheckerError(
                f"Invalid JSON in license database {path}: {exc}"
            ) from exc

    def lookup(self, name: str) -> str | None:
        return self._licenses.get(name)


# --------------------------------------------------------------------------
# Classification and reporting
# --------------------------------------------------------------------------

def classify_license(license_id: str | None, config: dict) -> str:
    """Return 'approved', 'denied', or 'unknown' for one license id."""
    if license_id is None:
        return "unknown"
    normalized = license_id.lower()
    # Deny takes precedence: a license on both lists is still a violation.
    if normalized in (entry.lower() for entry in config["deny"]):
        return "denied"
    if normalized in (entry.lower() for entry in config["allow"]):
        return "approved"
    return "unknown"


def generate_report(deps: list[Dependency], source, config: dict) -> list[dict]:
    """Resolve and classify every dependency; preserves manifest order."""
    report = []
    for dep in deps:
        license_id = source.lookup(dep.name)
        report.append({
            "name": dep.name,
            "version": dep.version,
            "license": license_id if license_id is not None else "UNKNOWN",
            "status": classify_license(license_id, config),
        })
    return report


def render_report(report: list[dict]) -> str:
    """Render the report as pipe-delimited lines plus a summary."""
    lines = ["Dependency License Compliance Report", "-" * 40]
    lines += [
        f"{row['name']} | {row['version']} | {row['license']} | {row['status']}"
        for row in report
    ]
    counts = {status: 0 for status in ("approved", "denied", "unknown")}
    for row in report:
        counts[row["status"]] += 1
    lines.append(
        f"Summary: {counts['approved']} approved, "
        f"{counts['denied']} denied, {counts['unknown']} unknown"
    )
    return "\n".join(lines)


# --------------------------------------------------------------------------
# CLI
# --------------------------------------------------------------------------

def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--manifest", required=True, help="dependency manifest file")
    parser.add_argument("--config", required=True, help="JSON with allow/deny license lists")
    parser.add_argument("--licenses", required=True,
                        help="JSON license database (mock of a registry lookup)")
    parser.add_argument("--fail-on-denied", action="store_true",
                        help="exit with code 2 if any dependency is denied")
    args = parser.parse_args(argv)

    try:
        deps = parse_manifest(args.manifest)
        config = load_config(args.config)
        source = MockLicenseSource.from_json_file(args.licenses)
        report = generate_report(deps, source, config)
    except LicenseCheckerError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1

    print(render_report(report))
    if args.fail_on_denied and any(row["status"] == "denied" for row in report):
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
