#!/usr/bin/env bash
#
# mock-lookup.sh — a stand-in for a real license lookup service.
#
# Usage: mock-lookup.sh <name> <version>
# Prints the license to stdout, or nothing (empty) when the dependency is
# unknown. This is the mock that license-checker.sh calls when the environment
# variable LICENSE_LOOKUP_CMD points here, demonstrating that the lookup is
# pluggable/mockable rather than hard-wired to a static file.

name="${1:-}"
# version="${2:-}"  # accepted for interface compatibility; unused by the mock

case "$name" in
  express) echo "MIT" ;;
  lodash)  echo "MIT" ;;
  bad-lib) echo "GPL-3.0" ;;
  *)       : ;;   # print nothing -> caller treats as UNKNOWN
esac
