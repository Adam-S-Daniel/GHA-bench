#!/usr/bin/env bash
#
# license-checker.sh — Dependency license compliance checker.
#
# Parses a dependency manifest (package.json / requirements.txt), looks up
# each dependency's license (via a mockable license database), classifies it
# against an allow-list / deny-list, and prints a compliance report.
#
# The file is safe to `source`: it only defines functions at load time and
# runs main() only when executed directly (see the guard at the bottom).

# Strict mode is enabled inside main() rather than at file scope so that
# sourcing this script from the test suite does not alter the test shell.

# detect_manifest_type PATH
#   Echoes the manifest type ("npm" or "pip") inferred from the file name.
#   Returns non-zero with an error message for unrecognised manifests.
detect_manifest_type() {
  local path="$1"
  local base
  base="$(basename -- "$path")"
  case "$base" in
    package.json)     echo "npm" ;;
    requirements.txt) echo "pip" ;;
    *)
      echo "error: unrecognised manifest type for '$path'" >&2
      return 1
      ;;
  esac
}

# clean_version VERSION
#   Strips common semver range operators (^ ~ >= <= > < = !) and surrounding
#   whitespace so the report shows a bare version string.
clean_version() {
  local v="$1"
  # Strip a leading run of range-operator/space characters.
  v="${v#"${v%%[!^~><=! ]*}"}"
  echo "$v"
}

# parse_npm FILE
#   Emits "name<TAB>version" for every entry in the "dependencies" and
#   "devDependencies" objects of a package.json. Uses jq for correct JSON
#   handling regardless of formatting (single-line or pretty-printed).
#   dependencies are listed before devDependencies, preserving file order.
parse_npm() {
  local file="$1"
  if ! command -v jq >/dev/null 2>&1; then
    echo "error: jq is required to parse package.json manifests" >&2
    return 1
  fi
  if ! jq -e . "$file" >/dev/null 2>&1; then
    echo "error: '$file' is not valid JSON" >&2
    return 1
  fi
  jq -r '((.dependencies // {}) + (.devDependencies // {}))
         | to_entries[] | "\(.key)\t\(.value)"' "$file"
}

# parse_pip FILE
#   Emits "name<TAB>version" for each requirement in a requirements.txt.
#   Skips blank lines, comments, inline comments, option lines (-r, --flag)
#   and strips extras (e.g. requests[security]).
parse_pip() {
  local file="$1"
  local line name spec
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%%#*}"             # drop comments (full-line and inline)
    line="${line//[[:space:]]/}"   # remove all whitespace
    [[ -z "$line" ]] && continue
    [[ "$line" == -* ]] && continue # skip option lines like -r / --index-url
    # Name is everything before the first version operator or extras bracket.
    name="${line%%[=<>~!\[]*}"
    spec="${line#"$name"}"
    spec="${spec#\[*]}"            # drop extras like [security]
    printf '%s\t%s\n' "$name" "$spec"
  done < "$file"
}

# list_contains VALUE FILE
#   Returns 0 if VALUE matches a non-comment, trimmed line in FILE.
list_contains() {
  local value="$1" file="$2" line
  [[ -f "$file" ]] || return 1
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%%#*}"                       # strip comments
    line="${line#"${line%%[![:space:]]*}"}"  # ltrim
    line="${line%"${line##*[![:space:]]}"}"  # rtrim
    [[ -z "$line" ]] && continue
    [[ "$line" == "$value" ]] && return 0
  done < "$file"
  return 1
}

# classify_license LICENSE ALLOW_FILE DENY_FILE
#   Echoes APPROVED, DENIED or UNKNOWN. An empty license is UNKNOWN. The
#   deny-list is checked first so it wins any conflict with the allow-list.
classify_license() {
  local license="$1" allow="$2" deny="$3"
  if [[ -z "$license" ]]; then
    echo "UNKNOWN"; return 0
  fi
  if list_contains "$license" "$deny"; then
    echo "DENIED"; return 0
  fi
  if list_contains "$license" "$allow"; then
    echo "APPROVED"; return 0
  fi
  echo "UNKNOWN"
}

# lookup_license NAME DB_FILE
#   Mockable license lookup. Reads a "name,license" CSV database and echoes the
#   license for NAME, or an empty string if not present. In production this
#   function would query a registry (npm/PyPI); tests inject a fixture CSV,
#   which keeps the lookup deterministic and offline.
lookup_license() {
  local name="$1" db="$2"
  if [[ -z "${db:-}" || ! -f "$db" ]]; then
    # No database available: every package is unknown.
    echo ""
    return 0
  fi
  local line key value
  while IFS=',' read -r key value || [[ -n "$key" ]]; do
    key="${key#"${key%%[![:space:]]*}"}"   # ltrim
    key="${key%"${key##*[![:space:]]}"}"   # rtrim
    [[ -z "$key" || "$key" == \#* ]] && continue
    if [[ "$key" == "$name" ]]; then
      # Trim whitespace around the value too.
      value="${value#"${value%%[![:space:]]*}"}"
      value="${value%"${value##*[![:space:]]}"}"
      echo "$value"
      return 0
    fi
  done < "$db"
  echo ""
}

# parse_manifest TYPE FILE
#   Dispatches to the right parser and normalises versions. Output is one
#   "name<TAB>cleaned-version" record per line.
parse_manifest() {
  local type="$1" file="$2"
  if [[ ! -f "$file" ]]; then
    echo "error: manifest file not found: '$file'" >&2
    return 1
  fi
  local raw name ver
  case "$type" in
    npm) raw="$(parse_npm "$file")" ;;
    pip) raw="$(parse_pip "$file")" ;;
    *)
      echo "error: unsupported manifest type: '$type'" >&2
      return 1
      ;;
  esac
  # Normalise each version through clean_version.
  while IFS=$'\t' read -r name ver; do
    [[ -z "$name" ]] && continue
    printf '%s\t%s\n' "$name" "$(clean_version "$ver")"
  done <<< "$raw"
}

# run_check MANIFEST ALLOW DENY DB [TYPE]
#   The orchestrator: parse the manifest, look up and classify each
#   dependency, print the compliance report, and return an exit code that
#   reflects the worst status found:
#     0 -> all approved (PASS)
#     1 -> at least one denied (FAIL)
#     2 -> at least one unknown, none denied (FAIL)
run_check() {
  local manifest="$1" allow="$2" deny="$3" db="$4" type="${5:-auto}"

  if [[ "$type" == "auto" ]]; then
    type="$(detect_manifest_type "$manifest")" || return 3
  fi

  local rows
  rows="$(parse_manifest "$type" "$manifest")" || return 3

  local name ver license status disp
  local total=0 approved=0 denied=0 unknown=0
  local body=""

  while IFS=$'\t' read -r name ver; do
    [[ -z "$name" ]] && continue
    license="$(lookup_license "$name" "$db")"
    status="$(classify_license "$license" "$allow" "$deny")"
    disp="$license"; [[ -z "$disp" ]] && disp="-"
    body+="$(printf '%-22s %-15s %-15s %-10s' "$name" "$ver" "$disp" "$status")"$'\n'
    total=$((total + 1))
    case "$status" in
      APPROVED) approved=$((approved + 1)) ;;
      DENIED)   denied=$((denied + 1)) ;;
      UNKNOWN)  unknown=$((unknown + 1)) ;;
    esac
  done <<< "$rows"

  local result rc
  if [[ "$denied" -gt 0 ]]; then
    result="FAIL"; rc=1
  elif [[ "$unknown" -gt 0 ]]; then
    result="FAIL"; rc=2
  else
    result="PASS"; rc=0
  fi

  # Emit the report.
  echo "Dependency License Compliance Report"
  echo "===================================="
  echo "Manifest: $manifest ($type)"
  echo
  printf '%-22s %-15s %-15s %-10s\n' "NAME" "VERSION" "LICENSE" "STATUS"
  printf '%-22s %-15s %-15s %-10s\n' "----" "-------" "-------" "------"
  printf '%s' "$body"
  echo
  echo "Summary: total=$total approved=$approved denied=$denied unknown=$unknown"
  echo "Result: $result"
  return "$rc"
}

# usage
#   Prints CLI help to stdout.
usage() {
  cat <<'USAGE'
Usage: license-checker.sh --manifest FILE --allow-list FILE --deny-list FILE [options]

Parse a dependency manifest, look up each dependency's license, classify it
against allow/deny lists, and print a compliance report.

Required:
  -m, --manifest FILE      Dependency manifest (package.json or requirements.txt)
  -a, --allow-list FILE    File of approved licenses, one per line
  -d, --deny-list FILE     File of denied licenses, one per line

Options:
  -l, --license-db FILE    Mock license database CSV ("name,license" per line).
                           When omitted, every license is treated as unknown.
  -t, --type TYPE          Manifest type: npm | pip | auto (default: auto)
      --no-fail            Always exit 0, even when violations are found
  -h, --help               Show this help and exit

Exit codes:
  0  all dependencies approved (PASS)
  1  at least one denied license (FAIL)
  2  at least one unknown license, none denied (FAIL)
  3  input/processing error
  64 command-line usage error
USAGE
}

# main "$@"
#   Parses CLI arguments, validates them, runs the check and applies the
#   --no-fail override to the exit code.
main() {
  set -o errexit
  set -o nounset
  set -o pipefail

  local manifest="" allow="" deny="" db="" type="auto" no_fail=0

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -m|--manifest)   manifest="${2:-}"; shift 2 ;;
      -a|--allow-list) allow="${2:-}";    shift 2 ;;
      -d|--deny-list)  deny="${2:-}";     shift 2 ;;
      -l|--license-db) db="${2:-}";       shift 2 ;;
      -t|--type)       type="${2:-}";     shift 2 ;;
      --no-fail)       no_fail=1;         shift ;;
      -h|--help)       usage; return 0 ;;
      *)
        echo "error: unknown argument '$1'" >&2
        usage >&2
        return 64
        ;;
    esac
  done

  # Validate required options.
  local missing=()
  [[ -z "$manifest" ]] && missing+=("--manifest")
  [[ -z "$allow" ]]    && missing+=("--allow-list")
  [[ -z "$deny" ]]     && missing+=("--deny-list")
  if [[ ${#missing[@]} -gt 0 ]]; then
    echo "error: missing required option(s): ${missing[*]}" >&2
    usage >&2
    return 64
  fi

  # Validate that the list files exist.
  local f
  for f in "$allow" "$deny"; do
    if [[ ! -f "$f" ]]; then
      echo "error: list file not found: '$f'" >&2
      return 3
    fi
  done

  # run_check returns the policy exit code; capture it without tripping
  # errexit, then optionally override it with --no-fail.
  local rc=0
  run_check "$manifest" "$allow" "$deny" "$db" "$type" || rc=$?

  if [[ "$no_fail" -eq 1 ]]; then
    return 0
  fi
  return "$rc"
}

# Run main() only when executed directly, not when sourced by the tests.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
