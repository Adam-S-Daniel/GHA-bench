#!/usr/bin/env bash
#
# matrix-generator.sh -- Generate a GitHub Actions build matrix (JSON) from a
# config describing OS options, language versions, and feature flags, with
# support for include/exclude rules, max-parallel, fail-fast, and a maximum
# matrix size guard.
#
# Usage: matrix-generator.sh <config.json>
#
# Output (stdout, on success): a JSON object suitable for embedding directly
# as a job's `strategy:` block, e.g.:
#   {"matrix": {"include": [...]}, "fail-fast": true, "max-parallel": 4}
#
# All errors are printed to stderr prefixed with "Error:" and exit non-zero.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/lib"

usage() {
  echo "Usage: $(basename "${BASH_SOURCE[0]}") <config.json>" >&2
  echo "  Generate a GitHub Actions build matrix JSON from a config file." >&2
}

die() {
  echo "Error: $1" >&2
  exit 1
}

main() {
  if [[ $# -lt 1 ]]; then
    usage
    exit 2
  fi

  local config_path="$1"

  if [[ ! -f "$config_path" ]]; then
    die "config file not found: $config_path"
  fi

  if ! jq empty "$config_path" >/dev/null 2>&1; then
    die "invalid JSON in config file: $config_path"
  fi

  # Merge os/versions/flags into a single "axes" object: {axisName: [values]}.
  # Detect duplicate axis names (e.g. the same key used in both "versions"
  # and "flags") before merging, since a silent merge would just let the
  # later one clobber the earlier one.
  local dup_key
  dup_key=$(jq -r '
    ( .os // [] | if length > 0 then ["os"] else [] end ) as $osKeys
    | ( (.versions // {}) | keys ) as $verKeys
    | ( (.flags // {}) | keys ) as $flagKeys
    | ($osKeys + $verKeys + $flagKeys) as $allKeys
    | ($allKeys | unique) as $uniqueKeys
    | if ($allKeys | length) != ($uniqueKeys | length) then
        ($allKeys | group_by(.) | map(select(length > 1) | .[0]) | .[0])
      else
        empty
      end
  ' "$config_path")
  if [[ -n "$dup_key" ]]; then
    die "duplicate axis '$dup_key' defined more than once across os/versions/flags"
  fi

  local axes
  axes=$(jq -c '
    ( .os // [] | if length > 0 then {os: .} else {} end ) as $osAxis
    | (.versions // {}) as $versions
    | (.flags // {}) as $flags
    | ($osAxis + $versions + $flags)
  ' "$config_path")

  if [[ "$axes" == "{}" ]]; then
    die "at least one axis must be defined (os, versions, or flags)"
  fi

  local empty_axis
  empty_axis=$(jq -rn --argjson axes "$axes" '
    $axes | to_entries[] | select(.value | length == 0) | .key
  ' | head -n1)
  if [[ -n "$empty_axis" ]]; then
    die "axis '$empty_axis' must be a non-empty array"
  fi

  local excludes includes
  excludes=$(jq -c '.exclude // []' "$config_path")
  includes=$(jq -c '.include // []' "$config_path")

  # exclude rules may only reference existing axis keys -- excluding on a
  # key that was never defined is always a no-op typo, so fail loudly.
  local bad_exclude_key
  bad_exclude_key=$(jq -rn --argjson axes "$axes" --argjson excludes "$excludes" '
    ($axes | keys) as $axisKeys
    | [ $excludes[] | keys[] | . as $k | select( ($axisKeys | index($k)) == null ) ] | .[0] // empty
  ')
  if [[ -n "$bad_exclude_key" ]]; then
    die "exclude rule references unknown axis '$bad_exclude_key'"
  fi

  local fail_fast max_parallel_raw max_size
  # NOTE: deliberately not `.fail_fast // true` -- jq's `//` alternative
  # operator treats `false` as falsy too, which would silently turn an
  # explicit `"fail_fast": false` into `true`.
  fail_fast=$(jq -r 'if has("fail_fast") then .fail_fast else true end' "$config_path")
  if [[ "$fail_fast" != "true" && "$fail_fast" != "false" ]]; then
    die "'fail_fast' must be a boolean"
  fi

  max_size=$(jq -r '.max_size // 256' "$config_path")
  if ! [[ "$max_size" =~ ^[0-9]+$ ]] || [[ "$max_size" -lt 1 ]]; then
    die "'max_size' must be a positive integer"
  fi

  max_parallel_raw=$(jq -r '.max_parallel // empty' "$config_path")
  if [[ -n "$max_parallel_raw" ]]; then
    if ! [[ "$max_parallel_raw" =~ ^[0-9]+$ ]] || [[ "$max_parallel_raw" -lt 1 ]]; then
      die "'max_parallel' must be a positive integer"
    fi
  fi

  local matrix_json matrix_size
  matrix_json=$(jq -cn -L "$LIB_DIR" --argjson axes "$axes" --argjson excludes "$excludes" --argjson includes "$includes" '
    include "matrix";
    resolve_matrix($axes; $excludes; $includes)
  ')
  matrix_size=$(jq 'length' <<<"$matrix_json")

  if [[ "$matrix_size" -eq 0 ]]; then
    die "resulting matrix is empty; GitHub Actions requires at least one job"
  fi

  if [[ "$matrix_size" -gt "$max_size" ]]; then
    die "matrix size ($matrix_size) exceeds maximum allowed size ($max_size)"
  fi

  # NOTE: the --argjson name below is deliberately "matrix_include", not
  # "include" -- jq 1.6 (as shipped on GitHub-hosted / act runner images)
  # chokes on a bound variable literally named $include ("unexpected
  # include, expecting IDENT"), since `include` is also a jq keyword.
  jq -cn \
    --argjson matrix_include "$matrix_json" \
    --argjson fail_fast "$fail_fast" \
    --arg max_parallel "$max_parallel_raw" \
    '
    {matrix: {include: $matrix_include}, "fail-fast": $fail_fast}
    + (if $max_parallel != "" then {"max-parallel": ($max_parallel | tonumber)} else {} end)
    '
}

main "$@"
