#!/usr/bin/env python3
"""
Dependency License Checker
===========================

Parses a dependency manifest (package.json or requirements.txt), looks up
each dependency's license, classifies it against an allow-list/deny-list
policy, and prints/writes a compliance report.

The real-world "look up a package's license" step would normally mean a
network call to the npm registry or PyPI JSON API. That is deliberately
kept behind a single small function, `lookup_license()`, which reads from
a local JSON file (the "mock" license database) instead. Tests substitute
their own in-memory dict for that database, so no network access is ever
required to exercise the classification logic.
"""
from __future__ import annotations

import argparse
import json
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Optional


class LicenseCheckerError(Exception):
    """Raised for any expected failure (bad input, missing file, etc.)."""


@dataclass(frozen=True)
class Dependency:
    name: str
    version: str


@dataclass(frozen=True)
class Policy:
    allow: frozenset
    deny: frozenset


# ---------------------------------------------------------------------------
# Manifest parsing
# ---------------------------------------------------------------------------

def parse_package_json(path: Path) -> list[Dependency]:
    """Extract name/version pairs from an npm package.json's dependencies."""
    try:
        data = json.loads(path.read_text())
    except json.JSONDecodeError as exc:
        raise LicenseCheckerError(f"Invalid JSON in manifest {path}: {exc}") from exc

    deps: list[Dependency] = []
    for section in ("dependencies", "devDependencies"):
        for name, version in (data.get(section) or {}).items():
            deps.append(Dependency(name=name, version=str(version).lstrip("^~=")))
    return deps


def parse_requirements_txt(path: Path) -> list[Dependency]:
    """Extract name/version pairs from a pip requirements.txt file.

    Supports the common `name==version` pin format. Lines that are blank,
    comments, or have no exact version pin are handled gracefully: a
    version-less line yields a dependency with version "unspecified" rather
    than raising, since requirements.txt does not require every line to be
    pinned.
    """
    deps: list[Dependency] = []
    for raw_line in path.read_text().splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        if "==" in line:
            name, version = line.split("==", 1)
            deps.append(Dependency(name=name.strip(), version=version.strip()))
        else:
            deps.append(Dependency(name=line, version="unspecified"))
    return deps


def resolve_manifest_path(target: Path) -> Path:
    """Given a file or a directory, return the manifest file to parse.

    If `target` is a directory, look for a known manifest filename inside
    it (package.json first, then requirements.txt).
    """
    if target.is_dir():
        for candidate in ("package.json", "requirements.txt"):
            candidate_path = target / candidate
            if candidate_path.is_file():
                return candidate_path
        raise LicenseCheckerError(
            f"No supported manifest (package.json or requirements.txt) found in {target}"
        )
    if not target.is_file():
        raise LicenseCheckerError(f"Manifest file not found: {target}")
    return target


def parse_manifest(path: Path) -> list[Dependency]:
    """Parse a manifest file, dispatching on its filename."""
    if path.name == "package.json":
        return parse_package_json(path)
    if path.name == "requirements.txt":
        return parse_requirements_txt(path)
    raise LicenseCheckerError(
        f"Unsupported manifest format: {path.name} "
        "(expected package.json or requirements.txt)"
    )


# ---------------------------------------------------------------------------
# Policy / license database loading
# ---------------------------------------------------------------------------

def load_policy(path: Path) -> Policy:
    if not path.is_file():
        raise LicenseCheckerError(f"Policy file not found: {path}")
    try:
        data = json.loads(path.read_text())
    except json.JSONDecodeError as exc:
        raise LicenseCheckerError(f"Invalid JSON in policy file {path}: {exc}") from exc

    return Policy(
        allow=frozenset(data.get("allow", [])),
        deny=frozenset(data.get("deny", [])),
    )


def load_license_db(path: Path) -> dict:
    if not path.is_file():
        raise LicenseCheckerError(f"License database file not found: {path}")
    try:
        data = json.loads(path.read_text())
    except json.JSONDecodeError as exc:
        raise LicenseCheckerError(f"Invalid JSON in license db {path}: {exc}") from exc
    return {k: v for k, v in data.items() if not k.startswith("_")}


# ---------------------------------------------------------------------------
# Core logic: lookup + classification
# ---------------------------------------------------------------------------

def lookup_license(name: str, version: str, license_db: dict) -> Optional[str]:
    """Return the SPDX license id for name@version, or None if unknown.

    This is the seam that tests mock: in production it would query an
    external registry; here it looks up a local dict (loaded from a JSON
    fixture in the CLI, or supplied directly in-memory by tests).
    """
    return license_db.get(f"{name}@{version}")


def classify_license(license_id: Optional[str], policy: Policy) -> str:
    """Classify a license as 'approved', 'denied', or 'unknown'.

    - No license could be determined -> unknown.
    - License is in the deny-list -> denied (checked before allow, so an
      explicit deny always wins over an accidental overlap).
    - License is in the allow-list -> approved.
    - License is known but not present in either list -> unknown (the
      policy simply hasn't classified it yet).
    """
    if not license_id:
        return "unknown"
    if license_id in policy.deny:
        return "denied"
    if license_id in policy.allow:
        return "approved"
    return "unknown"


def build_report(dependencies: list[Dependency], license_db: dict, policy: Policy) -> list[dict]:
    report = []
    for dep in dependencies:
        license_id = lookup_license(dep.name, dep.version, license_db)
        status = classify_license(license_id, policy)
        report.append(
            {
                "name": dep.name,
                "version": dep.version,
                "license": license_id or "UNKNOWN",
                "status": status,
            }
        )
    return report


def summarize(report: list[dict]) -> dict:
    summary = {"total": len(report), "approved": 0, "denied": 0, "unknown": 0}
    for entry in report:
        summary[entry["status"]] += 1
    return summary


# ---------------------------------------------------------------------------
# Output formatting
# ---------------------------------------------------------------------------

def format_text(report: list[dict], summary: dict) -> str:
    lines = [f"STATUS {e['name']} {e['version']} {e['license']} {e['status']}" for e in report]
    lines.append(
        "SUMMARY approved={approved} denied={denied} unknown={unknown} total={total}".format(
            **summary
        )
    )
    return "\n".join(lines)


def format_markdown(report: list[dict], summary: dict) -> str:
    lines = [
        "## Dependency License Compliance Report",
        "",
        f"Total: {summary['total']} | Approved: {summary['approved']} | "
        f"Denied: {summary['denied']} | Unknown: {summary['unknown']}",
        "",
        "| Dependency | Version | License | Status |",
        "|---|---|---|---|",
    ]
    for e in report:
        lines.append(f"| {e['name']} | {e['version']} | {e['license']} | {e['status']} |")
    return "\n".join(lines)


def format_json(report: list[dict], summary: dict) -> str:
    return json.dumps({"summary": summary, "dependencies": report}, indent=2)


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def run(manifest: Path, policy_path: Path, license_db_path: Path) -> tuple[list[dict], dict]:
    manifest_file = resolve_manifest_path(manifest)
    dependencies = parse_manifest(manifest_file)
    policy = load_policy(policy_path)
    license_db = load_license_db(license_db_path)
    report = build_report(dependencies, license_db, policy)
    summary = summarize(report)
    return report, summary


def main(argv: Optional[list[str]] = None) -> int:
    parser = argparse.ArgumentParser(description="Check dependency licenses against a policy.")
    parser.add_argument("manifest", type=Path, help="Path to a manifest file or a directory containing one")
    parser.add_argument("--policy", type=Path, required=True, help="Path to policy JSON (allow/deny lists)")
    parser.add_argument("--license-db", type=Path, required=True, help="Path to the mock license lookup JSON")
    parser.add_argument("--format", choices=["text", "json", "markdown"], default="text")
    parser.add_argument("--output", type=Path, help="Optional path to also write the JSON report to")
    args = parser.parse_args(argv)

    try:
        report, summary = run(args.manifest, args.policy, args.license_db)
    except LicenseCheckerError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2

    if args.format == "text":
        print(format_text(report, summary))
    elif args.format == "markdown":
        print(format_markdown(report, summary))
    else:
        print(format_json(report, summary))

    if args.output:
        args.output.write_text(format_json(report, summary) + "\n")

    return 0


if __name__ == "__main__":
    sys.exit(main())
