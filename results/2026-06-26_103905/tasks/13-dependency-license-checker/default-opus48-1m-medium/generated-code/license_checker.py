#!/usr/bin/env python3
"""
Dependency license compliance checker.

Pipeline:
  1. parse_manifest()   - extract {name: version} from package.json / requirements.txt
  2. lookup_license()   - resolve a dependency to its license (mockable lookup)
  3. classify()         - approved / denied / unknown given the policy config
  4. generate_report()  - assemble a structured compliance report
  5. main()             - CLI glue with graceful error handling

The license lookup is deliberately injected as a plain dict ("license database")
rather than calling a network registry. This keeps the tool hermetic and makes
it trivial to mock in tests and to feed deterministic fixtures in CI.
"""
import argparse
import json
import os
import re
import sys

# Sentinel used when a license cannot be resolved.
UNKNOWN_LICENSE = "UNKNOWN"


def parse_manifest(path):
    """Return {dependency_name: version_spec} for a supported manifest.

    Supports package.json (npm) and requirements.txt (pip). The format is
    chosen by file name/extension. Raises FileNotFoundError if the file is
    missing and ValueError for unsupported formats / malformed content.
    """
    if not os.path.exists(path):
        raise FileNotFoundError("Manifest not found: {}".format(path))

    name = os.path.basename(path).lower()
    if name.endswith(".json"):
        return _parse_package_json(path)
    if name.endswith(".txt"):
        return _parse_requirements_txt(path)
    raise ValueError(
        "Unsupported manifest format: {} "
        "(expected package.json or requirements.txt)".format(path))


def _parse_package_json(path):
    with open(path, "r", encoding="utf-8") as fh:
        try:
            data = json.load(fh)
        except json.JSONDecodeError as exc:
            raise ValueError("Invalid JSON in {}: {}".format(path, exc))
    deps = {}
    for section in ("dependencies", "devDependencies"):
        deps.update(data.get(section, {}))
    return deps


# A requirements line looks like:  name[extras]<op>version  with optional comment.
_REQ_RE = re.compile(
    r"^\s*(?P<name>[A-Za-z0-9_.\-]+)"      # package name
    r"(?:\[[^\]]*\])?"                       # optional extras, ignored
    r"\s*(?:(?P<op>==|>=|<=|~=|!=|>|<)\s*(?P<ver>[^#;\s]+))?"  # optional version
)


def _parse_requirements_txt(path):
    deps = {}
    with open(path, "r", encoding="utf-8") as fh:
        for raw in fh:
            line = raw.strip()
            # Skip blanks, comments, and pip directives (-e, -r, --flag, etc.).
            if not line or line.startswith("#") or line.startswith("-"):
                continue
            match = _REQ_RE.match(line)
            if not match:
                continue
            deps[match.group("name")] = match.group("ver") or ""
    return deps


def lookup_license(name, license_db):
    """Resolve a dependency name to a license string via the (mock) database.

    Returns UNKNOWN_LICENSE when the dependency is not present, so downstream
    code never has to special-case missing data.
    """
    return license_db.get(name, UNKNOWN_LICENSE)


def classify(license_id, config):
    """Classify a license as 'approved', 'denied', or 'unknown'.

    Matching is case-insensitive. The deny-list takes precedence over the
    allow-list; anything not listed (including UNKNOWN) is 'unknown'.
    """
    lic = (license_id or "").strip().lower()
    deny = {x.lower() for x in config.get("deny", [])}
    allow = {x.lower() for x in config.get("allow", [])}
    if lic in deny:
        return "denied"
    if lic in allow:
        return "approved"
    return "unknown"


def generate_report(deps, config, license_db):
    """Build a structured compliance report for the given dependencies."""
    entries = []
    summary = {"approved": 0, "denied": 0, "unknown": 0, "total": 0}
    for name in sorted(deps):
        license_id = lookup_license(name, license_db)
        status = classify(license_id, config)
        entries.append({
            "name": name,
            "version": deps[name],
            "license": license_id,
            "status": status,
        })
        summary[status] += 1
        summary["total"] += 1
    return {
        "compliant": summary["denied"] == 0 and summary["unknown"] == 0,
        "summary": summary,
        "dependencies": entries,
    }


def _load_json(path, label):
    if not os.path.exists(path):
        raise FileNotFoundError("{} not found: {}".format(label, path))
    with open(path, "r", encoding="utf-8") as fh:
        try:
            return json.load(fh)
        except json.JSONDecodeError as exc:
            raise ValueError("Invalid JSON in {} ({}): {}".format(label, path, exc))


def _print_human(report):
    print("=== Dependency License Compliance Report ===")
    for e in report["dependencies"]:
        print("  [{status:>8}] {name} ({version}) -> {license}".format(**e))
    s = report["summary"]
    print("--- Summary: {total} deps | {approved} approved | "
          "{denied} denied | {unknown} unknown".format(**s))
    print("COMPLIANT: {}".format("YES" if report["compliant"] else "NO"))


def main(argv=None):
    """CLI entry point. Returns an exit code (0 compliant, 1 violations, 2 error)."""
    parser = argparse.ArgumentParser(
        description="Check dependency licenses against an allow/deny policy.")
    parser.add_argument("--manifest", required=True,
                        help="Path to package.json or requirements.txt")
    parser.add_argument("--config", required=True,
                        help="JSON policy file with 'allow' and 'deny' lists")
    parser.add_argument("--license-db", required=True,
                        help="JSON map of dependency-name -> license (mock lookup)")
    parser.add_argument("--output", help="Where to write the JSON report")
    args = parser.parse_args(argv)

    try:
        deps = parse_manifest(args.manifest)
        config = _load_json(args.config, "Config")
        license_db = _load_json(args.license_db, "License database")
    except (FileNotFoundError, ValueError) as exc:
        # Graceful, meaningful error instead of a traceback.
        print("ERROR: {}".format(exc), file=sys.stderr)
        return 2

    report = generate_report(deps, config, license_db)

    if args.output:
        with open(args.output, "w", encoding="utf-8") as fh:
            json.dump(report, fh, indent=2, sort_keys=True)
            fh.write("\n")  # trailing newline so log readers flush the last line
    _print_human(report)

    return 0 if report["compliant"] else 1


if __name__ == "__main__":
    sys.exit(main())
