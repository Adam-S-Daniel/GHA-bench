#!/usr/bin/env bash
#
# generate-matrix.sh
# -----------------------------------------------------------------------------
# Generate a GitHub Actions `strategy.matrix` (as JSON) from a declarative
# configuration describing OS options, language versions and feature flags.
#
# Features:
#   * Cartesian product of arbitrary named dimensions.
#   * `exclude` rules  — remove combinations matching a subset of key/values.
#   * `include` rules  — extend matching combinations or add new ones, following
#                        GitHub Actions' documented include semantics.
#   * `max-parallel`   — passed through to the output.
#   * `fail-fast`      — passed through to the output (defaults to true, the
#                        GitHub Actions default).
#   * `max-size`       — validation: fail if the matrix would exceed this size.
#
# Input : a JSON config file (path argument) or JSON on stdin.
# Output: the complete strategy JSON on stdout. Errors go to stderr.
#
# Exit codes:
#   0  success
#   1  usage / validation / parse error
#   2  generated matrix exceeds the configured `max-size`
#
# The heavy JSON set-algebra (cartesian product, include/exclude merging) is
# delegated to `jq`; Bash owns argument parsing, validation, error reporting and
# the size-limit gate.
# -----------------------------------------------------------------------------

set -euo pipefail

PROG=${0##*/}

# --- helpers ----------------------------------------------------------------

# die <exit-code> <message...> : print an error to stderr and exit.
die() {
  local code=$1
  shift
  printf 'Error: %s\n' "$*" >&2
  exit "$code"
}

usage() {
  cat <<EOF
Usage: $PROG [CONFIG]

Generate a GitHub Actions strategy.matrix JSON from a configuration file.

Arguments:
  CONFIG   Path to a JSON config file. If omitted or '-', read JSON from stdin.

Options:
  -h, --help   Show this help and exit.

Config schema (all keys optional unless noted):
  {
    "dimensions":  { "<name>": [<values>...], ... },   # base axes (cartesian)
    "include":     [ { ... }, ... ],                   # GHA include rules
    "exclude":     [ { ... }, ... ],                   # GHA exclude rules
    "max-parallel": <positive integer>,
    "fail-fast":    <boolean>,                         # default: true
    "max-size":     <positive integer>                 # validation guard
  }

At least one of 'dimensions' (non-empty) or 'include' (non-empty) is required.
EOF
}

# --- jq programs ------------------------------------------------------------

# Validation: emit an array of human-readable error strings. Empty == valid.
# Assumes the input is already known to be a JSON object.
read -r -d '' JQ_VALIDATE <<'JQ' || true
[
  # at least one source of combinations
  (if (((.dimensions // {}) | length) == 0) and (((.include // []) | length) == 0)
   then "config must define a non-empty 'dimensions' object or 'include' array"
   else empty end),

  # dimensions must be an object of (non-empty array | scalar) values
  (if ((.dimensions // {}) | type) != "object"
   then "'dimensions' must be an object" else empty end),
  ( (.dimensions // {}) | to_entries[]
    | (.value | type) as $t
    | if   ($t == "array" and (.value | length) == 0)
           then "dimension '\(.key)' must be a non-empty array"
      elif ($t == "object" or $t == "null")
           then "dimension '\(.key)' must be an array or scalar"
      else empty end ),

  # include / exclude must be arrays of objects
  (if   ((.include // []) | type) != "array"        then "'include' must be an array"
   elif ((.include // []) | any(type != "object"))  then "'include' entries must be objects"
   else empty end),
  (if   ((.exclude // []) | type) != "array"        then "'exclude' must be an array"
   elif ((.exclude // []) | any(type != "object"))  then "'exclude' entries must be objects"
   else empty end),

  # fail-fast must be boolean when present
  (if (has("fail-fast") and ((.["fail-fast"] | type) != "boolean"))
   then "'fail-fast' must be a boolean" else empty end),

  # max-parallel must be a positive integer when present
  (if has("max-parallel")
   then ( .["max-parallel"] as $m
          | if   ($m | type) != "number"   then "'max-parallel' must be a positive integer"
            elif ($m != ($m | floor))      then "'max-parallel' must be a positive integer"
            elif ($m < 1)                  then "'max-parallel' must be a positive integer"
            else empty end )
   else empty end),

  # max-size must be a positive integer when present
  (if has("max-size")
   then ( .["max-size"] as $m
          | if   ($m | type) != "number"   then "'max-size' must be a positive integer"
            elif ($m != ($m | floor))      then "'max-size' must be a positive integer"
            elif ($m < 1)                  then "'max-size' must be a positive integer"
            else empty end )
   else empty end)
]
| (.[0] // "")
JQ

# Resolution: cartesian product -> exclude -> include -> assembled strategy JSON.
read -r -d '' JQ_RESOLVE <<'JQ' || true
# Treat a scalar dimension value as a single-element list.
def coerceArr: if type == "array" then . else [.] end;

. as $cfg
| ($cfg.dimensions // {})            as $dims
| ($dims | keys_unsorted)            as $origKeys
| ($cfg.exclude // [])               as $excludes
| ($cfg.include // [])               as $includes

# 1. Cartesian product of the named dimensions (insertion order preserved).
#    With no dimensions we start from an empty list so that include-only
#    configs turn each include entry into its own combination.
| ( if ($dims | length) == 0 then []
    else
      reduce ($dims | to_entries[]) as $e ([ {} ];
        ($e.value | coerceArr) as $vals
        | [ .[] as $acc | $vals[] as $v | $acc + { ($e.key): $v } ]
      )
    end ) as $base

# 2. Apply exclude rules. An exclude entry removes a combination when every one
#    of its key/value pairs matches that combination (empty entries are ignored).
| ( [ $base[]
      | . as $c
      | select(
          ( $excludes
            | any( . as $ex
                   | ($ex | to_entries) as $ee
                   | (($ee | length) > 0) and ($ee | all(.value == $c[.key])) ) )
          | not ) ] ) as $orig

# 3. Apply include rules, following GitHub Actions semantics:
#    For each include entry, the keys it shares with the *original* dimensions
#    must match a base combination for it to be merged in; original dimension
#    values are never overwritten but previously-added values may be. An entry
#    that matches no base combination becomes a new standalone combination.
#    Includes only ever merge into the original (cartesian) combinations, never
#    into combinations created by an earlier include.
| ( reduce $includes[] as $inc ($orig;
      . as $R
      | ( [ $origKeys[] | select( . as $k | $inc | has($k) ) ] ) as $relevant
      | ( reduce range(0; ($orig | length)) as $i ( { r: $R, matched: false };
            ($orig[$i]) as $oc
            | if ($relevant | all( $oc[.] == $inc[.] ))
              then { r: (.r | .[$i] |= (. + $inc)), matched: true }
              else . end
          ) ) as $st
      | if $st.matched then $st.r else ($st.r + [ $inc ]) end
    ) ) as $resolved

# 4. Assemble the strategy output. fail-fast defaults to true *only* when
#    absent (a literal false must be preserved, so `//` cannot be used here).
| ($resolved | length) as $size
| ( { "fail-fast": (if ($cfg | has("fail-fast")) then $cfg["fail-fast"] else true end),
      "matrix": { "include": $resolved } }
    + (if ($cfg | has("max-parallel")) then { "max-parallel": $cfg["max-parallel"] } else {} end)
    + { "size": $size } )
JQ

# --- argument parsing -------------------------------------------------------

config_arg=""
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    -)         config_arg="-"; shift ;;
    --)        shift; [ $# -gt 0 ] && config_arg="$1"; break ;;
    -*)        die 1 "unknown option: $1 (try --help)" ;;
    *)         config_arg="$1"; shift ;;
  esac
done

# --- read configuration -----------------------------------------------------

command -v jq >/dev/null 2>&1 || die 1 "jq is required but was not found in PATH"

if [ -z "$config_arg" ] || [ "$config_arg" = "-" ]; then
  if [ -t 0 ]; then
    die 1 "no config provided. Usage: $PROG <config.json> (or pipe JSON on stdin)"
  fi
  config="$(cat)"
else
  [ -f "$config_arg" ] || die 1 "config file not found: $config_arg"
  config="$(cat -- "$config_arg")"
fi

# --- validate ---------------------------------------------------------------

printf '%s' "$config" | jq empty 2>/dev/null || die 1 "config is not valid JSON"

cfg_type="$(printf '%s' "$config" | jq -r 'type')"
[ "$cfg_type" = "object" ] || die 1 "config must be a JSON object, got: $cfg_type"

validation_error="$(printf '%s' "$config" | jq -r "$JQ_VALIDATE")"
[ -z "$validation_error" ] || die 1 "$validation_error"

# --- resolve ----------------------------------------------------------------

output="$(printf '%s' "$config" | jq "$JQ_RESOLVE")" \
  || die 1 "failed to generate matrix from configuration"

size="$(printf '%s' "$output" | jq -r '.size')"

# A matrix with zero combinations is unusable in GitHub Actions.
[ "$size" -ge 1 ] || die 1 "generated matrix is empty (no combinations produced)"

# --- enforce max-size -------------------------------------------------------

max_size="$(printf '%s' "$config" | jq -r 'if has("max-size") then .["max-size"] else "null" end')"
if [ "$max_size" != "null" ] && [ "$size" -gt "$max_size" ]; then
  die 2 "matrix size $size exceeds maximum $max_size"
fi

# --- emit -------------------------------------------------------------------

printf '%s\n' "$output"
