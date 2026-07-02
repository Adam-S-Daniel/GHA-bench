#!/usr/bin/env bash
#
# matrix-gen.sh — Generate a GitHub Actions strategy.matrix JSON document
# from a configuration file describing OS options, language versions and
# feature flags, with support for include/exclude rules, max-parallel,
# fail-fast, and matrix-size validation.
#
# Usage: matrix-gen.sh [--config FILE] [--max-size N] [--compact]
#
# Exit codes: 0 success, 1 runtime/validation error, 2 usage error.

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: matrix-gen.sh [OPTIONS]

Generate a GitHub Actions strategy matrix (JSON) from a configuration file.

Options:
  -c, --config FILE   Path to the JSON configuration file (default: stdin)
  -m, --max-size N    Maximum allowed number of matrix jobs (default: 256)
  -C, --compact       Emit compact (single-line) JSON
  -h, --help          Show this help and exit
EOF
}

# die MESSAGE — print a meaningful error to stderr and exit 1.
die() {
  echo "matrix-gen: error: $*" >&2
  exit 1
}

main() {
  local config_file="" compact=0 max_size=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -c|--config)
        [[ $# -ge 2 ]] || { usage >&2; exit 2; }
        config_file="$2"; shift 2 ;;
      -m|--max-size)
        [[ $# -ge 2 ]] || { usage >&2; exit 2; }
        max_size="$2"; shift 2 ;;
      -C|--compact)
        compact=1; shift ;;
      -h|--help)
        usage; exit 0 ;;
      *)
        echo "matrix-gen: unknown option: $1" >&2
        usage >&2
        exit 2 ;;
    esac
  done

  if [[ -n "$config_file" && ! -f "$config_file" ]]; then
    die "config file not found: $config_file"
  fi

  command -v jq > /dev/null 2>&1 || die "required dependency 'jq' is not installed"

  # Read the configuration (file or stdin) and make sure it is valid JSON.
  local config
  if [[ -n "$config_file" ]]; then
    config="$(cat -- "$config_file")"
  else
    config="$(cat)"
  fi
  echo "$config" | jq -e . > /dev/null 2>&1 || die "config is not valid JSON"

  validate_config "$config"
  generate_matrix "$config" "$compact" "$max_size"
}

# validate_config CONFIG
# Check the shape of every supported configuration key and die with a
# meaningful message on the first violation. All checks are expressed as
# jq predicates so the rules live in one place.
validate_config() {
  local config="$1" axis

  echo "$config" | jq -e 'type == "object"' > /dev/null \
    || die "config must be a JSON object"

  # The three matrix axes are required, non-empty arrays of strings.
  for axis in "os" "language-versions" "feature-flags"; do
    echo "$config" | jq -e --arg k "$axis" '
      (.[$k] | type == "array")
      and (.[$k] | length > 0)
      and (.[$k] | all(type == "string"))
    ' > /dev/null \
      || die "'$axis' must be a non-empty array of strings"
  done

  echo "$config" | jq -e '
    (has("fail-fast") | not) or (.["fail-fast"] | type == "boolean")
  ' > /dev/null || die "'fail-fast' must be a boolean"

  echo "$config" | jq -e '
    (has("max-parallel") | not)
    or (.["max-parallel"] | type == "number" and . == floor and . >= 1)
  ' > /dev/null || die "'max-parallel' must be a positive integer"

  local rule
  for rule in include exclude; do
    echo "$config" | jq -e --arg k "$rule" '
      (has($k) | not)
      or (.[$k] | type == "array" and all(type == "object"))
    ' > /dev/null || die "'$rule' must be an array of objects"
  done

  echo "$config" | jq -e '
    (has("max-size") | not)
    or (.["max-size"] | type == "number" and . == floor and . >= 1)
  ' > /dev/null || die "'max-size' in config must be a positive integer"
}

# effective_size CONFIG
# Print the number of jobs the matrix will produce, mirroring the GitHub
# Actions expansion rules:
#   * start with the cartesian product of the three axes,
#   * an exclude rule removes every combination whose values match ALL of
#     the rule's keys (partial rules match broadly),
#   * an include entry only creates a NEW job when its axis values do not
#     match any surviving combination (otherwise it merely annotates one).
effective_size() {
  local config="$1"
  echo "$config" | jq '
    (.exclude // []) as $ex
    | (.include // []) as $inc
    # Cartesian product of the three axes, using job-level key names.
    | ([ .os[] as $o
         | .["language-versions"][] as $l
         | .["feature-flags"][] as $f
         | {os: $o, "language-version": $l, "feature-flag": $f} ]) as $cells
    # Keep a combination only if every exclude rule mismatches on some key.
    | ([ $cells[] | . as $c
         | select(all($ex[]; . as $r
             | any($r | keys[]; . as $k | $r[$k] != $c[$k]))) ]) as $kept
    # Count include entries whose axis values match no surviving combo.
    | ($inc
       | map(with_entries(select(.key | IN("os", "language-version", "feature-flag"))))
       | map(select(. as $i
           | (($i | length) > 0)
             and all($kept[]; . as $c
                     | any($i | keys[]; . as $k | $i[$k] != $c[$k]))))
       | length) as $new
    | ($kept | length) + $new
  '
}

# generate_matrix CONFIG COMPACT MAX_SIZE
# Build the strategy JSON document from the validated configuration.
generate_matrix() {
  local config="$1" compact="$2" max_size="$3"
  local -a jq_flags=()
  [[ "$compact" -eq 1 ]] && jq_flags+=(-c)

  # Resolve the size limit: --max-size beats the config's "max-size",
  # which beats the GitHub Actions hard limit of 256 jobs per matrix.
  local limit
  if [[ -n "$max_size" ]]; then
    [[ "$max_size" =~ ^[1-9][0-9]*$ ]] \
      || die "max-size must be a positive integer (got: $max_size)"
    limit="$max_size"
  else
    limit="$(echo "$config" | jq '.["max-size"] // 256')"
  fi

  local size
  size="$(effective_size "$config")"
  if (( size > limit )); then
    die "matrix size $size exceeds maximum allowed size $limit"
  fi

  # Assemble the strategy document:
  #  - fail-fast defaults to true (mirrors the GitHub Actions default)
  #  - max-parallel is only emitted when configured (GHA default: unlimited)
  #  - matrix axes are renamed to the singular job-level keys
  echo "$config" | jq "${jq_flags[@]}" '
    {
      "fail-fast": (if has("fail-fast") then .["fail-fast"] else true end)
    }
    + (if has("max-parallel") then {"max-parallel": .["max-parallel"]} else {} end)
    + {
        matrix: (
          {
            os: .os,
            "language-version": .["language-versions"],
            "feature-flag": .["feature-flags"]
          }
          + (if has("include") then {include: .include} else {} end)
          + (if has("exclude") then {exclude: .exclude} else {} end)
        )
      }
  '
}

main "$@"
