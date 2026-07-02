#!/usr/bin/env bash
# matrix-generator.sh
#
# Generates a GitHub Actions build matrix (JSON) from a config describing
# OS options, language versions, and optional extra "flag" axes.
#
# Usage: matrix-generator.sh <config.json>
#
# Config schema (JSON):
#   {
#     "os": ["ubuntu-latest", "windows-latest"],   // required, non-empty array
#     "versions": ["18", "20"],                    // required, non-empty array
#     "flags": { "arch": ["x64", "arm64"] },        // optional extra axes
#     "exclude": [ {"os": "windows-latest", "version": "18"} ], // optional
#     "include": [ {"os": "ubuntu-latest", "version": "22", "arch": "x64"} ], // optional
#     "fail-fast": true,                            // optional, default true
#     "max-parallel": 4,                            // optional
#     "max-size": 256                               // optional, default 256
#   }
#
# Output (JSON, on stdout):
#   {
#     "matrix": { "include": [ ... final combinations ... ] },
#     "fail-fast": <bool>,
#     "max-parallel": <int>   // only present if configured
#   }
#
# Exit codes:
#   0 - success
#   1 - usage / config / validation error (message on stderr)

set -euo pipefail

DEFAULT_MAX_SIZE=256

usage() {
  echo "Usage: $(basename "$0") <config.json>" >&2
}

die() {
  echo "Error: $1" >&2
  exit 1
}

main() {
  if [[ $# -ne 1 ]]; then
    usage
    exit 1
  fi

  local config_file=$1

  if [[ ! -f "$config_file" ]]; then
    die "config file not found: $config_file"
  fi

  if ! jq empty "$config_file" >/dev/null 2>&1; then
    die "invalid JSON in config file: $config_file"
  fi

  # Required fields must be present and non-empty arrays.
  local os_count versions_count
  os_count=$(jq '(.os // []) | length' "$config_file")
  versions_count=$(jq '(.versions // []) | length' "$config_file")

  if [[ "$os_count" -eq 0 ]]; then
    die "config must define a non-empty 'os' array"
  fi
  if [[ "$versions_count" -eq 0 ]]; then
    die "config must define a non-empty 'versions' array"
  fi

  local max_size
  max_size=$(jq --argjson default "$DEFAULT_MAX_SIZE" \
    'if has("max-size") then .["max-size"] else $default end' "$config_file")

  # Build the full matrix via jq: cartesian product of axes, then apply
  # exclude rules (drop any combo matching all keys of a rule), then apply
  # include rules (merge into a matching combo, or append as a new one).
  local matrix_json
  matrix_json=$(jq -c '
    def axes: {os: .os, version: .versions} + (.flags // {});

    def cartesian:
      (axes) as $ax
      | reduce ($ax | to_entries[]) as $e
          ([{}]; [ .[] as $c | $e.value[] as $v | $c + {($e.key): $v} ]);

    def rule_matches($c; $rule):
      ($rule | to_entries) as $re
      | ($re | map(. as $kv | $c[$kv.key] == $kv.value) | all);

    . as $cfg
    | (axes | keys) as $axkeys
    | cartesian as $base
    | ($cfg.exclude // []) as $excl
    | [ $base[] | . as $c
        | select( ( [ $excl[] | rule_matches($c; .) ] | any ) | not ) ] as $filtered
    | ($cfg.include // []) as $incl
    | reduce $incl[] as $inc
        ($filtered;
          ($inc | to_entries
             | map(select(.key as $k | $axkeys | index($k) != null))
             | from_entries) as $inckey
          | ($axkeys | map(select(. as $k | $inckey | has($k)))) as $ck
          | ( [ .[] | . as $c
                | select( ($ck | length) > 0 and ($ck | map($c[.] == $inckey[.]) | all) ) ]
              | length ) as $match_count
          | if $match_count > 0 then
              [ .[] | . as $c
                | if ($ck | length) > 0 and ($ck | map($c[.] == $inckey[.]) | all)
                  then ($c + $inc)
                  else $c
                  end ]
            else . + [$inc]
            end
        )
  ' "$config_file")

  local size
  size=$(jq -c 'length' <<<"$matrix_json")

  if [[ "$size" -gt "$max_size" ]]; then
    die "generated matrix size ($size) exceeds max-size ($max_size)"
  fi

  jq -n -c \
    --argjson combos "$matrix_json" \
    --argjson cfg "$(cat "$config_file")" '
    (if ($cfg | has("fail-fast")) then $cfg["fail-fast"] else true end) as $ff
    | {matrix: {"include": $combos}, "fail-fast": $ff}
    | if ($cfg | has("max-parallel"))
      then . + {"max-parallel": $cfg["max-parallel"]}
      else .
      end
  '
}

main "$@"
