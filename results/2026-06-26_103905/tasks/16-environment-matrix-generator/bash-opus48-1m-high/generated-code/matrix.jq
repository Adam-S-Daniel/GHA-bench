# matrix.jq -- core matrix-generation logic for generate-matrix.sh
#
# Input : the parsed config object (axes / include / exclude / strategy opts).
# Output: a GitHub Actions strategy object of the form
#           { "max-parallel": N|null, "fail-fast": bool,
#             "total": K, "matrix": { "include": [ {combo}, ... ] } }
#
# The expansion mirrors GitHub Actions semantics:
#   1. cartesian product of every axis
#   2. remove combinations matched by any `exclude` entry (partial match)
#   3. apply `include` entries (extend matching originals, else add new combos)

# Ordered list of the matrix axis keys (preserves config order).
def axiskeys: (.axes | keys_unsorted);

# Cartesian product of all axes -> array of combination objects.
def cartesian:
  .axes as $axes
  | reduce ($axes | keys_unsorted)[] as $k (
      [{}];
      [ .[] as $combo | $axes[$k][] as $v | ($combo + {($k): $v}) ]
    );

# True if combination $combo contains every key/value pair of $pattern
# (a partial match -- the pattern may name only a subset of the axes).
def matches_pattern($combo; $pattern):
  $pattern | to_entries | all(.value == $combo[.key]);

# Drop every combination matched by any entry in the exclude list.
def apply_excludes($combos; $excludes):
  $combos
  | map( . as $c | select( ($excludes | any(matches_pattern($c; .))) | not ) );

# An include entry $inc can be added to combination $combo iff none of the
# entry's *axis* keys would overwrite the combo's original axis values.
# Non-axis keys are always free to add (or to overwrite earlier added keys).
def addable($combo; $inc; $axiskeys):
  $inc
  | to_entries
  | all( .key as $k
         | (($axiskeys | index($k)) == null) or (.value == $combo[$k]) );

# Apply include entries in order. Each entry extends every original combination
# it is addable to; if it is addable to none, it becomes a new standalone
# combination. New combinations are not themselves extended by later entries
# (matching GitHub's behaviour), so we keep originals and extras separate.
def apply_includes($combos; $includes; $axiskeys):
  reduce $includes[] as $inc (
    { originals: $combos, extras: [] };
    if ([ .originals[] | select(addable(.; $inc; $axiskeys)) ] | length) == 0
    then .extras += [$inc]
    else .originals |= map( if addable(.; $inc; $axiskeys) then . + $inc else . end )
    end
  )
  | (.originals + .extras);

# --- Top-level pipeline -------------------------------------------------------
. as $cfg
| ($cfg | axiskeys) as $axiskeys
| ($cfg | cartesian) as $cart
| apply_excludes($cart; ($cfg.exclude // [])) as $base
| apply_includes($base; ($cfg.include // []); $axiskeys) as $combos
| {
    "max-parallel": ($cfg["max-parallel"] // null),
    "fail-fast":    (if ($cfg | has("fail-fast")) then $cfg["fail-fast"] else true end),
    "total":        ($combos | length),
    "matrix":       { "include": $combos }
  }
