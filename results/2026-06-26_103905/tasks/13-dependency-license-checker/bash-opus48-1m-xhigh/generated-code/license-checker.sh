#!/usr/bin/env bash
#
# license-checker.sh — Dependency license compliance checker.
#
# Parses a dependency manifest (package.json or requirements.txt), looks up each
# dependency's license (via a mockable lookup), classifies it against an
# allow-list / deny-list policy, and emits a compliance report.
#
# The file is written so it can be *sourced* by the bats test-suite without
# running main(): every piece of behaviour lives in a small function and main()
# only runs when the file is executed directly (see the guard at the bottom).
# Strict shell options are set inside main() (not at top level) so that sourcing
# the script does not mutate the test shell's options.

# --------------------------------------------------------------------------- #
# Manifest type detection
# --------------------------------------------------------------------------- #
# Echoes "npm" for package.json-style manifests, "pip" for requirements.txt
# style ones, or "unknown". Detection is by filename first, then a light
# content sniff so unusually named files still work.
detect_manifest_type() {
  local file="$1"
  local base
  base="$(basename "$file")"

  case "$base" in
    package.json|*.json) echo "npm"; return 0 ;;
    requirements*.txt|*.pip) echo "pip"; return 0 ;;
  esac

  # Content sniff fallback: a leading '{' looks like JSON (npm).
  if [[ -f "$file" ]]; then
    local first
    first="$(grep -m1 -o '[^[:space:]]' "$file" 2>/dev/null | head -n1 || true)"
    if [[ "$first" == "{" ]]; then
      echo "npm"; return 0
    fi
    echo "pip"; return 0
  fi

  echo "unknown"
  return 1
}

# --------------------------------------------------------------------------- #
# Version normalisation
# --------------------------------------------------------------------------- #
# Reduce a manifest version spec to a bare version, e.g. "^4.18.2" -> "4.18.2",
# ">= 2.31.0" -> "2.31.0". Specs without a concrete version ("*", "latest",
# "workspace:*", empty) become "unspecified".
_normalize_version() {
  local v="$1"
  # Strip leading range operators / leading 'v' / whitespace.
  v="$(printf '%s' "$v" | sed -E 's/^[[:space:]~^=<>v]+//')"
  if [[ "$v" =~ ^[0-9][0-9A-Za-z.+-]* ]]; then
    printf '%s' "${BASH_REMATCH[0]}"
  else
    printf 'unspecified'
  fi
}

# --------------------------------------------------------------------------- #
# Manifest parsing — emits one "name<TAB>version" line per dependency.
# --------------------------------------------------------------------------- #
parse_manifest() {
  local file="$1"
  local type="${2:-}"
  [[ -f "$file" ]] || { echo "Error: manifest not found: $file" >&2; return 1; }
  [[ -n "$type" ]] || type="$(detect_manifest_type "$file")"

  case "$type" in
    npm) _parse_npm "$file" ;;
    pip) _parse_pip "$file" ;;
    *)   echo "Error: unsupported manifest type: $type" >&2; return 1 ;;
  esac
}

# package.json: merge dependencies + devDependencies via jq, then normalise.
_parse_npm() {
  local file="$1" name raw ver
  command -v jq >/dev/null 2>&1 || {
    echo "Error: jq is required to parse npm manifests" >&2; return 5
  }
  while IFS=$'\t' read -r name raw; do
    [[ -n "$name" ]] || continue
    ver="$(_normalize_version "$raw")"
    printf '%s\t%s\n' "$name" "$ver"
  done < <(jq -r '
    [(.dependencies // {}), (.devDependencies // {})]
    | add // {}
    | to_entries[]
    | "\(.key)\t\(.value)"' "$file")
}

# requirements.txt: skip comments/blank lines, parse "name[extras]OP version".
_parse_pip() {
  local file="$1" line name ver
  # Regexes live in variables so '<' and '>' are not parsed by [[ ]].
  local re_pinned='^([A-Za-z0-9._-]+)(\[[^]]*\])?[[:space:]]*[=<>!~]+[[:space:]]*([0-9][^[:space:];,]*)'
  local re_name='^([A-Za-z0-9._-]+)'
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%%#*}"                       # strip inline comments
    line="${line#"${line%%[![:space:]]*}"}"  # ltrim
    line="${line%"${line##*[![:space:]]}"}"  # rtrim
    [[ -n "$line" ]] || continue
    if [[ "$line" =~ $re_pinned ]]; then
      name="${BASH_REMATCH[1]}"; ver="${BASH_REMATCH[3]}"
    elif [[ "$line" =~ $re_name ]]; then
      name="${BASH_REMATCH[1]}"; ver="unspecified"
    else
      continue
    fi
    printf '%s\t%s\n' "$name" "$ver"
  done < "$file"
}

# --------------------------------------------------------------------------- #
# Policy config: allow-list / deny-list of licenses
# --------------------------------------------------------------------------- #
# Populates the global associative arrays ALLOW and DENY from a config file.
# Config lines look like "allow: MIT" or "deny: GPL-3.0"; '#' starts a comment.
load_config() {
  local file="$1" line
  local re_allow='^allow:[[:space:]]*(.+)$'
  local re_deny='^deny:[[:space:]]*(.+)$'
  [[ -f "$file" ]] || { echo "Error: config not found: $file" >&2; return 1; }
  # (Re)declare as empty global associative arrays.
  declare -gA ALLOW=() DENY=()
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%%#*}"                       # strip comments
    line="${line#"${line%%[![:space:]]*}"}"  # ltrim
    line="${line%"${line##*[![:space:]]}"}"  # rtrim
    [[ -n "$line" ]] || continue
    if [[ "$line" =~ $re_allow ]]; then
      ALLOW["${BASH_REMATCH[1]}"]=1
    elif [[ "$line" =~ $re_deny ]]; then
      DENY["${BASH_REMATCH[1]}"]=1
    fi
  done < "$file"
}

# Classify a license string into APPROVED / DENIED / UNKNOWN using ALLOW/DENY.
# Deny-list wins over allow-list (conservative). Empty or the "UNKNOWN"
# sentinel (no license could be resolved) classifies as UNKNOWN.
classify_license() {
  local lic="$1"
  if [[ -z "$lic" || "$lic" == "UNKNOWN" ]]; then
    echo "UNKNOWN"; return 0
  fi
  if [[ -n "${DENY[$lic]:-}" ]]; then
    echo "DENIED"; return 0
  fi
  if [[ -n "${ALLOW[$lic]:-}" ]]; then
    echo "APPROVED"; return 0
  fi
  echo "UNKNOWN"
  return 0
}

# --------------------------------------------------------------------------- #
# Mock license lookup
# --------------------------------------------------------------------------- #
# load_db reads the mock license database (TAB-separated name/version/license)
# into the global associative array DB, keyed "name@version". A version of "*"
# in the DB acts as a wildcard. In production this data would come from a
# registry/API call; for testing we mock it with a static file.
load_db() {
  local file="$1" name ver lic
  [[ -f "$file" ]] || { echo "Error: license db not found: $file" >&2; return 1; }
  declare -gA DB=()
  while IFS=$'\t' read -r name ver lic || [[ -n "$name" ]]; do
    [[ "$name" =~ ^[[:space:]]*# ]] && continue   # skip comments
    [[ -n "$name" && -n "${ver:-}" ]] || continue # skip blanks/malformed
    DB["$name@$ver"]="$lic"
  done < "$file"
}

# lookup_license resolves a dependency's license. If LICENSE_LOOKUP_CMD is set
# it is invoked as `$LICENSE_LOOKUP_CMD <name> <version>` (a pluggable, mockable
# external lookup); otherwise the DB populated by load_db is consulted with an
# exact name@version match, then a name@* wildcard. Unresolved -> "UNKNOWN".
lookup_license() {
  local name="$1" version="${2:-}" out lic

  if [[ -n "${LICENSE_LOOKUP_CMD:-}" ]]; then
    out="$("$LICENSE_LOOKUP_CMD" "$name" "$version" 2>/dev/null || true)"
    if [[ -n "$out" ]]; then
      echo "$out"
    else
      echo "UNKNOWN"
    fi
    return 0
  fi

  lic="${DB[$name@$version]:-}"
  [[ -n "$lic" ]] || lic="${DB[$name@*]:-}"
  if [[ -n "$lic" ]]; then
    echo "$lic"
  else
    echo "UNKNOWN"
  fi
  return 0
}

# --------------------------------------------------------------------------- #
# Report generation
# --------------------------------------------------------------------------- #
# Walks the manifest, resolves + classifies each dependency, and emits a report
# in the chosen format. Results (counts + rows) are stashed in REPORT_* globals
# so main() can derive the process exit code without re-parsing the output.
generate_report() {
  local manifest="$1" type="${2:-}" format="${3:-text}"
  [[ -n "$type" ]] || type="$(detect_manifest_type "$manifest")"

  local name version license status
  local total=0 approved=0 denied=0 unknown=0
  declare -ga REPORT_ROWS=()

  while IFS=$'\t' read -r name version; do
    [[ -n "$name" ]] || continue
    license="$(lookup_license "$name" "$version")"
    status="$(classify_license "$license")"
    total=$((total + 1))
    case "$status" in
      APPROVED) approved=$((approved + 1)) ;;
      DENIED)   denied=$((denied + 1)) ;;
      *)        unknown=$((unknown + 1)) ;;
    esac
    REPORT_ROWS+=("${name}"$'\t'"${version}"$'\t'"${license}"$'\t'"${status}")
  done < <(parse_manifest "$manifest" "$type")

  REPORT_MANIFEST="$manifest"
  REPORT_TYPE="$type"
  REPORT_TOTAL="$total"
  REPORT_APPROVED="$approved"
  REPORT_DENIED="$denied"
  REPORT_UNKNOWN="$unknown"

  if [[ "$format" == "json" ]]; then
    _emit_json
  else
    _emit_text
  fi
}

# Human-readable, column-aligned report.
_emit_text() {
  local row name version license status
  printf 'Dependency License Compliance Report\n'
  printf '====================================\n'
  printf 'Manifest: %s (%s)\n\n' "$REPORT_MANIFEST" "$REPORT_TYPE"
  printf '%-24s %-14s %-15s %s\n' "NAME" "VERSION" "LICENSE" "STATUS"
  printf '%-24s %-14s %-15s %s\n' "------------------------" "--------------" \
                                  "---------------" "------"
  for row in "${REPORT_ROWS[@]}"; do
    IFS=$'\t' read -r name version license status <<<"$row"
    printf '%-24s %-14s %-15s %s\n' "$name" "$version" "$license" "$status"
  done
  printf '\n'
  printf 'Summary: %d total, %d approved, %d denied, %d unknown\n' \
    "$REPORT_TOTAL" "$REPORT_APPROVED" "$REPORT_DENIED" "$REPORT_UNKNOWN"
  if (( REPORT_DENIED == 0 && REPORT_UNKNOWN == 0 )); then
    printf 'Result: COMPLIANT\n'
  else
    printf 'Result: NON-COMPLIANT\n'
  fi
}

# Machine-readable JSON report (built with jq so quoting is always correct).
_emit_json() {
  local row deps
  deps="$(
    for row in "${REPORT_ROWS[@]}"; do printf '%s\n' "$row"; done \
      | jq -R -s '
          split("\n")
          | map(select(length > 0))
          | map(split("\t"))
          | map({name: .[0], version: .[1], license: .[2],
                 status: (.[3] | ascii_downcase)})'
  )"
  [[ -n "$deps" ]] || deps="[]"
  jq -n \
    --arg manifest "$REPORT_MANIFEST" \
    --arg type "$REPORT_TYPE" \
    --argjson total "$REPORT_TOTAL" \
    --argjson approved "$REPORT_APPROVED" \
    --argjson denied "$REPORT_DENIED" \
    --argjson unknown "$REPORT_UNKNOWN" \
    --argjson deps "$deps" \
    '{
       manifest: $manifest,
       type: $type,
       summary: {
         total: $total, approved: $approved, denied: $denied, unknown: $unknown,
         compliant: ($denied == 0 and $unknown == 0)
       },
       dependencies: $deps
     }'
}

# --------------------------------------------------------------------------- #
# Usage / help
# --------------------------------------------------------------------------- #
usage() {
  cat <<'EOF'
Usage: license-checker.sh --manifest FILE --config FILE [--db FILE] [options]

Parse a dependency manifest, resolve each dependency's license, classify it
against an allow-list / deny-list policy, and print a compliance report.

Required:
  --manifest FILE   Path to package.json or requirements.txt
  --config FILE     Path to the license policy config (allow:/deny: lines)

License lookup (choose one):
  --db FILE         Mock license database (name<TAB>version<TAB>license)
  --lookup-cmd CMD  External command invoked as: CMD <name> <version>
                    (also settable via the LICENSE_LOOKUP_CMD env var)

Options:
  --type npm|pip    Force the manifest type (default: auto-detect)
  --format text|json  Output format (default: text)
  --no-fail         Always exit 0 (report-only mode; useful in CI logging)
  -h, --help        Show this help and exit

Exit codes:
  0  compliant (or --no-fail / --help)
  1  one or more denied licenses
  2  one or more unknown licenses (and no denied)
  3  input/IO error (missing file, etc.)
  64 usage error (bad/missing arguments)
EOF
}

# --------------------------------------------------------------------------- #
# main — argument parsing and orchestration.
# --------------------------------------------------------------------------- #
main() {
  set -o errexit
  set -o nounset
  set -o pipefail

  local manifest="" config="" db="" type="" format="text" no_fail=0

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --manifest)   manifest="${2:?--manifest needs a value}"; shift 2 ;;
      --manifest=*) manifest="${1#*=}"; shift ;;
      --config)     config="${2:?--config needs a value}"; shift 2 ;;
      --config=*)   config="${1#*=}"; shift ;;
      --db)         db="${2:?--db needs a value}"; shift 2 ;;
      --db=*)       db="${1#*=}"; shift ;;
      --lookup-cmd)   export LICENSE_LOOKUP_CMD="${2:?--lookup-cmd needs a value}"; shift 2 ;;
      --lookup-cmd=*) export LICENSE_LOOKUP_CMD="${1#*=}"; shift ;;
      --type)       type="${2:?--type needs a value}"; shift 2 ;;
      --type=*)     type="${1#*=}"; shift ;;
      --format)     format="${2:?--format needs a value}"; shift 2 ;;
      --format=*)   format="${1#*=}"; shift ;;
      --no-fail)    no_fail=1; shift ;;
      -h|--help)    usage; return 0 ;;
      *) echo "Error: unknown argument: $1" >&2; usage >&2; return 64 ;;
    esac
  done

  # Validate required arguments.
  [[ -n "$manifest" ]] || { echo "Error: --manifest is required" >&2; return 64; }
  [[ -n "$config"   ]] || { echo "Error: --config is required" >&2; return 64; }
  [[ -f "$manifest" ]] || { echo "Error: manifest not found: $manifest" >&2; return 3; }

  load_config "$config" || return 3

  # The license lookup is either an external command or the mock DB file.
  if [[ -z "${LICENSE_LOOKUP_CMD:-}" ]]; then
    [[ -n "$db" ]] || {
      echo "Error: provide --db FILE or --lookup-cmd CMD (or set LICENSE_LOOKUP_CMD)" >&2
      return 64
    }
    load_db "$db" || return 3
  fi

  generate_report "$manifest" "$type" "$format"

  # Derive exit code from the compliance result, unless --no-fail. These are
  # written as if-blocks (not `(( )) && return`) so that a *false* arithmetic
  # test does not trip `set -o errexit`.
  if (( no_fail )); then
    return 0
  fi
  if (( REPORT_DENIED > 0 )); then
    return 1
  fi
  if (( REPORT_UNKNOWN > 0 )); then
    return 2
  fi
  return 0
}

# --------------------------------------------------------------------------- #
# Entry point guard: only run main() when executed, not when sourced by bats.
# --------------------------------------------------------------------------- #
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
