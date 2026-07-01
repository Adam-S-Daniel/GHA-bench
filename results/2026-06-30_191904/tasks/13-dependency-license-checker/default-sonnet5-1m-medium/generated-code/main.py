#!/usr/bin/env python3
"""
CLI entry point: parse a dependency manifest, look up each dependency's
license against a package registry, classify against an allow/deny
license config, and print a compliance report.

Exit codes:
  0 - all dependencies approved or unknown, none denied
  1 - at least one dependency has a denied license (CI should fail)
  2 - a fatal error occurred (bad manifest/config/args)
"""
import argparse
import sys

from config import ConfigError, load_license_config
from license_checker import LicenseLookupError, check_compliance
from manifest_parser import ManifestParseError, parse_manifest
from registry_lookup import fixture_license_lookup, make_registry_lookup
from report import compliance_exit_code, generate_json_report, generate_text_report


def build_arg_parser():
    parser = argparse.ArgumentParser(description="Check dependency licenses for compliance.")
    parser.add_argument("--manifest", required=True, help="Path to package.json/requirements.txt")
    parser.add_argument("--config", required=True, help="Path to license allow/deny config JSON")
    parser.add_argument(
        "--ecosystem",
        choices=["npm", "pypi", "fixture"],
        required=True,
        help="Package registry to query for license info, or 'fixture' for an "
        "offline local license-data JSON file (see --license-data)",
    )
    parser.add_argument(
        "--license-data",
        help="Path to a {name: license} JSON file, required when --ecosystem fixture",
    )
    parser.add_argument("--format", choices=["text", "json"], default="text")
    return parser


def run(argv):
    args = build_arg_parser().parse_args(argv)

    try:
        dependencies = parse_manifest(args.manifest)
        license_config = load_license_config(args.config)
        if args.ecosystem == "fixture":
            if not args.license_data:
                raise ValueError("--license-data is required when --ecosystem fixture")
            lookup = fixture_license_lookup(args.license_data)
        else:
            lookup = make_registry_lookup(args.ecosystem)
    except (ManifestParseError, ConfigError, ValueError, LicenseLookupError) as exc:
        print(f"Error: {exc}", file=sys.stderr)
        return 2

    results = check_compliance(
        dependencies, lookup, license_config.allow_list, license_config.deny_list
    )

    if args.format == "json":
        print(generate_json_report(results))
    else:
        print(generate_text_report(results))

    return compliance_exit_code(results)


def main():
    sys.exit(run(sys.argv[1:]))


if __name__ == "__main__":
    main()
