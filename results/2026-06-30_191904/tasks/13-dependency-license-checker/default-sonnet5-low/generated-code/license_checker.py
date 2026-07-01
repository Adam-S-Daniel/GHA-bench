#!/usr/bin/env python3
"""
Dependency license compliance checker.

Parses a dependency manifest (package.json or requirements.txt), looks up
each dependency's license, and classifies it against an allow-list /
deny-list of licenses supplied in a JSON config file. Produces a plain-text
compliance report and exits non-zero if any dependency is denied.

The license lookup itself is pluggable: `default_license_lookup` reads from
a small local JSON "license database" fixture. Tests replace it with a mock
function so no network access is required.
"""
import json
import os
import sys


class LicenseCheckerError(Exception):
    """Raised for any user-facing error (missing file, bad config, etc.)."""


def parse_package_json(path):
    """Return {name: version} for dependencies + devDependencies of a package.json."""
    if not os.path.isfile(path):
        raise LicenseCheckerError(f"package.json not found at: {path}")
    try:
        with open(path, "r", encoding="utf-8") as f:
            data = json.load(f)
    except json.JSONDecodeError as e:
        raise LicenseCheckerError(f"Invalid JSON in {path}: {e}") from e

    deps = {}
    for section in ("dependencies", "devDependencies"):
        for name, version in data.get(section, {}).items():
            deps[name] = str(version).lstrip("^~=")
    return deps


def parse_requirements_txt(path):
    """Return {name: version} parsed from a pip requirements.txt file.

    Only handles simple `name==version` pins; other lines (comments, blank
    lines, unpinned requirements) are skipped since they carry no version
    to look a license up against.
    """
    if not os.path.isfile(path):
        raise LicenseCheckerError(f"requirements.txt not found at: {path}")

    deps = {}
    with open(path, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            if "==" not in line:
                continue
            name, version = line.split("==", 1)
            deps[name.strip()] = version.strip()
    return deps


def load_config(path):
    """Load a JSON config with "allow" and "deny" license lists."""
    if not os.path.isfile(path):
        raise LicenseCheckerError(f"license policy config not found at: {path}")
    try:
        with open(path, "r", encoding="utf-8") as f:
            config = json.load(f)
    except json.JSONDecodeError as e:
        raise LicenseCheckerError(f"Invalid JSON in {path}: {e}") from e

    config.setdefault("allow", [])
    config.setdefault("deny", [])
    return config


def classify_license(license_name, config):
    """Classify a license string as 'approved', 'denied', or 'unknown'."""
    if not license_name:
        return "unknown"
    if license_name in config.get("deny", []):
        return "denied"
    if license_name in config.get("allow", []):
        return "approved"
    return "unknown"


def default_license_lookup(name, version, db_path=None):
    """Look up a license in the local license-database JSON fixture.

    This stands in for a call to a real package registry (npm/PyPI). Kept
    local and file-based so the checker never depends on network access.
    """
    if db_path is None:
        db_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "fixtures", "license-db.json")
    if not os.path.isfile(db_path):
        return None
    with open(db_path, "r", encoding="utf-8") as f:
        db = json.load(f)
    return db.get(f"{name}=={version}")


def check_dependencies(deps, license_lookup, config):
    """Look up and classify the license for every dependency.

    `license_lookup(name, version)` may return None (unknown license) or
    raise; any exception is treated as an unknown license rather than
    aborting the whole check, since one bad lookup shouldn't hide the rest
    of the report.
    """
    results = []
    for name, version in sorted(deps.items()):
        try:
            license_name = license_lookup(name, version)
        except Exception:
            license_name = None
        status = classify_license(license_name, config)
        results.append({
            "name": name,
            "version": version,
            "license": license_name,
            "status": status,
        })
    return results


def generate_report(results):
    """Render a plain-text compliance report."""
    lines = ["Dependency License Compliance Report", "=" * 38, ""]
    counts = {"approved": 0, "denied": 0, "unknown": 0}
    for r in results:
        counts[r["status"]] += 1
        license_display = r["license"] or "UNKNOWN"
        lines.append(f"[{r['status'].upper():8}] {r['name']}=={r['version']} -> {license_display}")

    lines.append("")
    lines.append("Summary")
    lines.append("-------")
    lines.append(f"Approved: {counts['approved']}")
    lines.append(f"Denied: {counts['denied']}")
    lines.append(f"Unknown: {counts['unknown']}")
    return "\n".join(lines)


def _parse_manifest(manifest_path):
    if manifest_path.endswith(".json"):
        return parse_package_json(manifest_path)
    return parse_requirements_txt(manifest_path)


def main(argv=None):
    argv = argv if argv is not None else sys.argv[1:]
    if len(argv) < 2:
        print("Usage: license_checker.py <manifest> <policy-config> [license-db]", file=sys.stderr)
        return 2

    manifest_path, config_path = argv[0], argv[1]
    db_path = argv[2] if len(argv) > 2 else None

    try:
        deps = _parse_manifest(manifest_path)
        config = load_config(config_path)
    except LicenseCheckerError as e:
        print(f"Error: {e}", file=sys.stderr)
        return 1

    lookup = lambda name, version: default_license_lookup(name, version, db_path)
    results = check_dependencies(deps, lookup, config)
    report = generate_report(results)
    print(report)

    if any(r["status"] == "denied" for r in results):
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
