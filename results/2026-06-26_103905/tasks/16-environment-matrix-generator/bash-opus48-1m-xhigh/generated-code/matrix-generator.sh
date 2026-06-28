#!/usr/bin/env bash
#
# matrix-generator.sh
# ===================
# Generate a GitHub Actions `strategy.matrix` build matrix from a JSON config
# describing OS options, language versions, and feature flags.
#
# Features:
#   * Cartesian product of arbitrary named dimensions (os, node, feature, ...)
#   * `exclude` rules        -> remove matching combinations (partial match)
#   * `include` rules        -> augment matching combos or add brand-new ones,
#                               following GitHub Actions' documented semantics
#   * `fail-fast` config     -> emitted into the strategy block (default: true)
#   * `max-parallel` config  -> emitted into the strategy block when present
#   * `max-size` validation  -> fail if the expanded job count exceeds the limit
#                               (GitHub's real limit is 256 jobs; that is the default)
#
# The heavy lifting (set algebra over the matrix) is done with `jq` so the logic
# stays declarative and correct. Bash handles argument parsing, IO, validation
# reporting, and the max-size gate.
#
# Usage:
#   matrix-generator.sh [--config FILE] [--max-size N] [--output MODE]
#   cat config.json | matrix-generator.sh --output matrix
#
# Output modes (--output):
#   strategy  (default)  full strategy block: {fail-fast, max-parallel, matrix}
#   matrix               just the matrix block: {<dims>, include, exclude}
#   expand               JSON array of every expanded job combination
#   size | count         integer count of expanded job combinations
#   all                  debug object: {strategy, matrix, expanded, size, max-size}
#
# Exit codes:
#   0  success
#   1  usage / config validation error
#   2  missing dependency (jq) or unreadable config file
#   3  generated matrix exceeds max-size
#
set -euo pipefail

PROG="${0##*/}"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
err() { printf '%s: %s\n' "$PROG" "$*" >&2; }

usage() {
  cat <<EOF
Usage: $PROG [--config FILE] [--max-size N] [--output MODE]

Generate a GitHub Actions strategy.matrix from a JSON configuration.

Options:
  -c, --config FILE     Read configuration from FILE (default: stdin)
  -m, --max-size N      Override the maximum allowed expanded matrix size
  -o, --output MODE     Output mode: strategy (default) | matrix | expand |
                        size | count | all
  -h, --help            Show this help and exit

Config schema (JSON):
  {
    "dimensions":   { "os": [...], "node": [...], "feature": [...] },
    "include":      [ { ... } ],
    "exclude":      [ { ... } ],
    "fail-fast":    true,
    "max-parallel": 4,
    "max-size":     256
  }
EOF
}

# ---------------------------------------------------------------------------
# The jq program that does the matrix algebra.
# Quoted heredoc => no shell expansion inside.
# ---------------------------------------------------------------------------
read -r -d '' JQ_MAIN <<'JQ' || true
# --- cartesian product of the dimensions object ---------------------------
# {"os":["a","b"],"node":["1","2"]} -> [{"os":"a","node":"1"}, ...]
# An empty dimensions object yields [] (no base combos) so that include-only
# matrices behave like GitHub (one job per include entry).
def cartesian($d):
  ($d | keys_unsorted) as $ks
  | if ($ks | length) == 0 then []
    else
      reduce $ks[] as $k ([{}];
        [ .[] as $acc | $d[$k][] as $v | $acc + {($k): $v} ])
    end;

# --- exclude test ----------------------------------------------------------
# A combo is excluded if ANY exclude entry is a full (partial-key) match:
# every key in the exclude entry must equal the combo's value for that key.
def is_excluded($combo; $exs):
  any($exs[];
    . as $ex
    | all($ex | keys_unsorted[]; $combo[.] == $ex[.]));

# --- include application ---------------------------------------------------
# GitHub semantics: for each include entry, the keys that are also matrix
# dimension keys ("original" keys) must match a base combination for the entry
# to merge into it. Merging adds the entry's extra keys (added keys may be
# overwritten by later includes; original keys never change because matching
# requires equality). If an entry matches no base combo it becomes a new job.
# Matching/merging runs against the evolving accumulator so includes stack.
def apply_includes($base; $incs; $mkeys):
  reduce $incs[] as $inc (
    { base: $base, extra: [] };
    . as $st
    | ( [ $inc | keys_unsorted[] | select(. as $k | $mkeys | index($k)) ] ) as $orig
    | ( [ range(0; ($st.base | length))
          | select(. as $i | all($orig[]; $st.base[$i][.] == $inc[.])) ] ) as $hits
    | if ($hits | length) > 0
      then .base = [ range(0; ($st.base | length)) as $i
                     | if ($hits | index($i)) != null
                       then ($st.base[$i] + $inc)
                       else $st.base[$i] end ]
      else .extra += [ $inc ]
      end
  )
  | (.base + .extra);

# --- assemble the result ---------------------------------------------------
. as $cfg
| ($cfg.dimensions // {})                      as $dims
| ($cfg.include // [])                          as $incs
| ($cfg.exclude // [])                          as $excs
| ($dims | keys_unsorted)                       as $mkeys
| [ cartesian($dims)[] | select(is_excluded(.; $excs) | not) ] as $base
| apply_includes($base; $incs; $mkeys)          as $expanded
| ($expanded | length)                          as $size
| ( $dims
    + (if ($incs | length) > 0 then { include: $incs } else {} end)
    + (if ($excs | length) > 0 then { exclude: $excs } else {} end)
  )                                             as $matrix
| ( { "fail-fast": (if $cfg["fail-fast"] == null then true else $cfg["fail-fast"] end) }
    + (if ($cfg["max-parallel"] != null)
       then { "max-parallel": $cfg["max-parallel"] } else {} end)
    + { matrix: $matrix }
  )                                             as $strategy
| { strategy: $strategy,
    matrix:   $matrix,
    expanded: $expanded,
    size:     $size,
    "max-size": ($maxsize_override // $cfg["max-size"] // 256) }
JQ

# ---------------------------------------------------------------------------
# Config validation jq program: emits one error string per problem, or nothing.
# ---------------------------------------------------------------------------
read -r -d '' JQ_VALIDATE <<'JQ' || true
[
  (if (.dimensions != null and (.dimensions | type) != "object")
   then "'dimensions' must be an object" else empty end),
  (if (.include != null and (.include | type) != "array")
   then "'include' must be an array" else empty end),
  (if (.exclude != null and (.exclude | type) != "array")
   then "'exclude' must be an array" else empty end),
  (if (.["max-parallel"] != null and (.["max-parallel"] | type) != "number")
   then "'max-parallel' must be a number" else empty end),
  (if (.["fail-fast"] != null and (.["fail-fast"] | type) != "boolean")
   then "'fail-fast' must be a boolean" else empty end),
  (if (.["max-size"] != null and (.["max-size"] | type) != "number")
   then "'max-size' must be a number" else empty end),
  ( if ((.dimensions // {}) | type) == "object"
    then (.dimensions // {}) | to_entries[]
         | select((.value | type) != "array")
         | "dimension '\(.key)' must be an array"
    else empty end ),
  ( if ((.dimensions // {}) | type) == "object"
    then (.dimensions // {}) | to_entries[]
         | select((.value | type) == "array" and (.value | length) == 0)
         | "dimension '\(.key)' must not be empty"
    else empty end ),
  ( if ((.include // []) | type) == "array"
    then (.include // []) | to_entries[]
         | select((.value | type) != "object")
         | "include[\(.key)] must be an object"
    else empty end ),
  ( if ((.exclude // []) | type) == "array"
    then (.exclude // []) | to_entries[]
         | select((.value | type) != "object")
         | "exclude[\(.key)] must be an object"
    else empty end ),
  (if (((.dimensions // {}) | length) == 0 and ((.include // []) | length) == 0)
   then "matrix is empty: provide 'dimensions' and/or 'include'" else empty end)
] | .[]
JQ

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
config_file=""
max_size_override="null"
output_mode="strategy"

while [ $# -gt 0 ]; do
  case "$1" in
    -c|--config)
      [ $# -ge 2 ] || { err "option $1 requires an argument"; exit 1; }
      config_file="$2"; shift 2 ;;
    -m|--max-size)
      [ $# -ge 2 ] || { err "option $1 requires an argument"; exit 1; }
      if ! [[ "$2" =~ ^[0-9]+$ ]]; then
        err "--max-size must be a non-negative integer (got '$2')"; exit 1
      fi
      max_size_override="$2"; shift 2 ;;
    -o|--output)
      [ $# -ge 2 ] || { err "option $1 requires an argument"; exit 1; }
      output_mode="$2"; shift 2 ;;
    -h|--help)
      usage; exit 0 ;;
    --)
      shift; break ;;
    -*)
      err "unknown option: $1"; usage >&2; exit 1 ;;
    *)
      # First positional argument is treated as the config file.
      if [ -z "$config_file" ]; then config_file="$1"; shift
      else err "unexpected argument: $1"; exit 1; fi ;;
  esac
done

case "$output_mode" in
  strategy|matrix|expand|size|count|all) ;;
  *) err "invalid --output mode: '$output_mode'"; usage >&2; exit 1 ;;
esac

# ---------------------------------------------------------------------------
# Preconditions
# ---------------------------------------------------------------------------
if ! command -v jq >/dev/null 2>&1; then
  err "required dependency 'jq' is not installed"; exit 2
fi

# ---------------------------------------------------------------------------
# Read config (file or stdin)
# ---------------------------------------------------------------------------
if [ -n "$config_file" ]; then
  if [ ! -r "$config_file" ]; then
    err "cannot read config file: $config_file"; exit 2
  fi
  config="$(cat -- "$config_file")"
else
  config="$(cat)"
fi

if [ -z "${config//[[:space:]]/}" ]; then
  err "configuration is empty"; exit 1
fi

# ---------------------------------------------------------------------------
# Validate JSON syntax
# ---------------------------------------------------------------------------
if ! jq_err="$(printf '%s' "$config" | jq empty 2>&1)"; then
  err "configuration is not valid JSON: ${jq_err}"; exit 1
fi

# ---------------------------------------------------------------------------
# Validate config structure
# ---------------------------------------------------------------------------
validation="$(printf '%s' "$config" | jq -r "$JQ_VALIDATE")"
if [ -n "$validation" ]; then
  while IFS= read -r line; do
    [ -n "$line" ] && err "invalid config: $line"
  done <<< "$validation"
  exit 1
fi

# ---------------------------------------------------------------------------
# Compute the matrix
# ---------------------------------------------------------------------------
result="$(printf '%s' "$config" \
  | jq --argjson maxsize_override "$max_size_override" "$JQ_MAIN")"

size="$(printf '%s' "$result"   | jq '.size')"
maxsize="$(printf '%s' "$result" | jq '.["max-size"]')"

# ---------------------------------------------------------------------------
# Enforce the max-size limit
# ---------------------------------------------------------------------------
if [ "$size" -gt "$maxsize" ]; then
  err "generated matrix has $size combinations, which exceeds the maximum allowed size of $maxsize"
  exit 3
fi

# ---------------------------------------------------------------------------
# Emit the requested view
# ---------------------------------------------------------------------------
case "$output_mode" in
  strategy)    printf '%s' "$result" | jq '.strategy' ;;
  matrix)      printf '%s' "$result" | jq '.matrix' ;;
  expand)      printf '%s' "$result" | jq '.expanded' ;;
  size|count)  printf '%s' "$result" | jq '.size' ;;
  all)         printf '%s' "$result" | jq '.' ;;
esac
