#!/usr/bin/env bash
#
# matrix-gen.sh — Generate a GitHub Actions strategy.matrix from a config file.
#
# Reads a JSON config describing matrix axes (OS, language versions, feature
# flags, ...) plus include/exclude rules, max-parallel, fail-fast and an
# optional max-size guard. It:
#   1. validates the config,
#   2. computes the effective number of jobs the matrix expands to,
#   3. fails if that exceeds max-size, and
#   4. emits a canonical `strategy` object as JSON on stdout.
#
# Config shape (mirrors GitHub's own structure):
#   {
#     "matrix": {
#       "os":   ["ubuntu-latest", "windows-latest"],   # an axis
#       "node": ["18", "20"],                           # another axis
#       "exclude": [ {"os":"windows-latest","node":"18"} ],
#       "include": [ {"os":"macos-latest","node":"21"} ]
#     },
#     "fail-fast":    false,     # optional, defaults to true (GitHub default)
#     "max-parallel": 4,         # optional
#     "max-size":     256        # optional guard on the expanded job count
#   }
#
# Inside "matrix", every key other than "include"/"exclude" is treated as an axis.
#
# Usage:  matrix-gen.sh [CONFIG.json]   (reads stdin when CONFIG is omitted or "-")

set -euo pipefail

# die MESSAGE — print an error to stderr and exit non-zero.
die() {
  printf 'error: %s\n' "$1" >&2
  exit 1
}

# read_config CFG — echo the raw config text from a file, stdin, or "-".
read_config() {
  local cfg="$1"
  if [ "$cfg" = "-" ]; then
    cat
  else
    [ -f "$cfg" ] || die "config file not found: $cfg"
    cat "$cfg"
  fi
}

# compute_size RAW — print the number of jobs the matrix expands to.
#
# Algorithm (faithful to GitHub Actions semantics):
#   - axes        = matrix keys other than include/exclude
#   - base combos = cartesian product of all axes
#   - excludes    = drop any base combo that is a superset of an exclude object
#   - includes    = an include that, on its overlapping axis keys, matches no
#                   surviving combo adds a brand-new job (+1). Includes that
#                   extend existing combos (or have no overlapping keys) add none.
compute_size() {
  jq -r '
    .matrix as $m
    | ($m | to_entries
           | map(select(.key != "include" and .key != "exclude"))) as $axes
    | ($m.exclude // [])  as $excludes
    | ($m.include // [])  as $includes
    | ($axes | map(.key)) as $axisKeys

    # Cartesian product of the axes -> array of combo objects.
    | (reduce $axes[] as $a ([{}];
         [ .[] as $combo | $a.value[] as $v | $combo + {($a.key): $v} ])) as $all
    | (if ($axes | length) == 0 then [] else $all end) as $base

    # Apply excludes: keep combos NOT covered by any exclude object.
    | ($base | map(select(. as $c
          | ($excludes | any(. as $e
              | ($e | to_entries | all(.value == $c[.key]))))
            | not))) as $kept

    # Count includes that introduce a brand-new job.
    | ([ $includes[] | . as $inc
          | ($inc | to_entries | map(select(.key as $k | $axisKeys | index($k)))) as $overlap
          | if ($kept | length) == 0 then 1                       # nothing to extend
            elif ($overlap | length) == 0 then 0                  # extends all combos
            elif ($kept | any(. as $c | ($overlap | all(.value == $c[.key]))))
              then 0                                              # extends a match
            else 1 end ]                                          # genuinely new
        | add // 0) as $newIncludes

    | ($kept | length) + $newIncludes
  ' <<<"$1"
}

main() {
  local cfg="${1:--}"

  local raw
  raw="$(read_config "$cfg")"

  # Validate that the input is JSON at all.
  jq -e . >/dev/null 2>&1 <<<"$raw" || die "invalid JSON in config"

  # There must be a matrix with at least one axis.
  local axis_count
  axis_count="$(jq -r '
      (.matrix // {})
      | to_entries
      | map(select(.key != "include" and .key != "exclude"))
      | length' <<<"$raw")"
  [ "$axis_count" -ge 1 ] || die "matrix must define at least one axis (e.g. \"os\")"

  # Enforce the optional max-size guard against the computed job count.
  local size max_size
  size="$(compute_size "$raw")"
  max_size="$(jq -r '.["max-size"] // empty' <<<"$raw")"
  if [ -n "$max_size" ] && [ "$size" -gt "$max_size" ]; then
    die "matrix size ($size) exceeds max-size ($max_size)"
  fi
  printf 'matrix expands to %s job(s)\n' "$size" >&2

  # Emit the canonical strategy object. GitHub expands include/exclude itself,
  # so we pass the matrix through and attach the strategy knobs. max-parallel is
  # only included when configured; fail-fast defaults to GitHub's default (true).
  jq '
    {
      # `//` treats false as empty, so test presence explicitly to keep false.
      "fail-fast": (if has("fail-fast") then .["fail-fast"] else true end),
      "matrix": .matrix
    }
    + (if .["max-parallel"] != null then {"max-parallel": .["max-parallel"]} else {} end)
  ' <<<"$raw"
}

main "$@"
