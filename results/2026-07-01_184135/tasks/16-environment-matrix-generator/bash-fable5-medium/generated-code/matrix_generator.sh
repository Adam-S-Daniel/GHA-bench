#!/usr/bin/env bash
# matrix_generator.sh — generate a GitHub Actions strategy.matrix JSON from a
# configuration file describing OS options, language versions, and feature flags.
#
# Config schema (JSON):
#   os           - array of runner OS labels                    (dimension "os")
#   versions     - array of language versions                   (dimension "version")
#   features     - object mapping feature-flag name -> values   (one dimension each)
#   exclude      - array of objects; a combo is dropped when ALL keys of an
#                  exclude entry match it (GitHub Actions exclude semantics)
#   include      - array of objects; entries whose dimension keys match existing
#                  combos augment them with extra keys, otherwise they are
#                  appended as standalone combos
#   fail-fast    - boolean, default true
#   max-parallel - positive integer, optional (omitted from output if absent)
#   max-size     - maximum allowed number of combos, default 256 (GitHub's limit)
#
# Output: a single JSON object {fail-fast, [max-parallel], matrix:{include:[...]}}
# suitable for feeding a reusable workflow's strategy via fromJSON().
#
# Approach: bash handles argument/file validation and exit codes; all set
# arithmetic (cartesian product, exclude filtering, include merging) is done in
# one jq program so the data never round-trips through fragile shell quoting.
set -euo pipefail

DEFAULT_MAX_SIZE=256

die() {
  echo "error: $*" >&2
  exit 1
}

usage() {
  echo "usage: matrix_generator.sh <config.json>" >&2
  exit 2
}

[ "$#" -eq 1 ] || usage
config_file="$1"

# --- input validation -------------------------------------------------------
[ -f "$config_file" ] || die "config file not found: $config_file"
jq -e . "$config_file" > /dev/null 2>&1 \
  || die "config file is not valid JSON: $config_file"
jq -e 'type == "object"' "$config_file" > /dev/null \
  || die "config must be a JSON object: $config_file"

# --- matrix generation ------------------------------------------------------
# The jq program returns the final matrix document, or an error string of the
# form "ERR:<message>" for semantic failures (no dimensions / size exceeded),
# which bash turns into a proper exit code + stderr message.
result="$(jq -c --argjson default_max "$DEFAULT_MAX_SIZE" '
  # Build the ordered dimension map: os, version, then each feature flag.
  ( {}
    + (if has("os")       then {os: .os}            else {} end)
    + (if has("versions") then {version: .versions} else {} end)
    + (.features // {})
  ) as $dims

  | if ($dims | length) == 0 then
      "ERR:config must define at least one dimension (os, versions, or features)"
    else
      # Cartesian product over every dimension, preserving dimension order.
      ( reduce ($dims | to_entries[]) as $d
          ([{}]; [ .[] as $acc | $d.value[] | $acc + {($d.key): .} ])
      ) as $product

      # Exclude: drop combos where every key of some exclude entry matches.
      | ( (.exclude // []) ) as $excludes
      | ( $product
          | map(. as $combo
                | select( ($excludes | any(. as $e
                    | ($e | to_entries | all($combo[.key] == .value)))) | not ))
        ) as $kept

      # Include: two-pass merge mirroring GitHub Actions include semantics.
      # Pass 1: every include entry whose dimension keys all match a combo
      #         augments that combo with its extra (non-dimension) keys.
      # Pass 2: entries that matched no combo are appended as standalone combos.
      | ( (.include // []) ) as $includes
      | ( $kept | map(. as $combo
            | reduce ($includes[] | select(
                  ( with_entries(select(.key as $k | $dims | has($k)))
                    | to_entries | length > 0 and all($combo[.key] == .value) )
                )) as $inc ($combo; $inc + .)
          )
        ) as $merged
      | ( $includes | map(select(
            ( with_entries(select(.key as $k | $dims | has($k)))
              | to_entries ) as $dk
            | ($dk | length) == 0
              or ($kept | any(. as $c | $dk | all($c[.key] == .value)) | not)
          ))
        ) as $appended

      | ($merged + $appended) as $final
      | (."max-size" // $default_max) as $max
      | if ($final | length) > $max then
          "ERR:matrix size \($final | length) exceeds maximum allowed size \($max)"
        else
          { "fail-fast": (if has("fail-fast") then ."fail-fast" else true end) }
          + (if has("max-parallel") then {"max-parallel": ."max-parallel"} else {} end)
          + { matrix: { include: $final } }
        end
    end
' "$config_file")" || die "failed to process config: $config_file"

# Semantic errors are signalled by the jq program as "ERR:<message>".
case "$result" in
  '"ERR:'*)
    die "$(jq -r 'ltrimstr("ERR:")' <<< "$result")"
    ;;
esac

echo "$result"
