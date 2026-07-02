# lib/matrix.jq
#
# Pure jq helper functions for resolving a GitHub Actions build matrix from
# a set of named axes plus include/exclude rules. Loaded by matrix-generator.sh
# via `jq -L <libdir> 'include "matrix"; ...'`.
#
# Semantics deliberately mirror the documented behavior of a native
# jobs.<id>.strategy.matrix block (see GitHub Actions "Workflow syntax"
# docs, section on include/exclude) so that a config expressed here behaves
# the same way a hand-written matrix: {os: [...], include: [...]} would.

# cartesian_product(axes): axes is an object mapping axis name -> array of
# values, e.g. {"os": ["a","b"], "node": ["18","20"]}. Streams one object per
# combination, e.g. {"os":"a","node":"18"}, {"os":"a","node":"20"}, ...
def cartesian_product(axes):
  (axes | to_entries) as $entries
  | ($entries | map(.key)) as $keys
  | ($entries | map(.value)) as $vals
  | ($vals | combinations) as $combo
  | [$keys, $combo] | transpose | map({(.[0]): .[1]}) | add;

# matches_rule(combo; rule; axisKeys): true if every key in `rule` that is
# also an original axis key (i.e. one of axisKeys) has an equal value in
# `combo`. Keys in `rule` that are NOT original axis keys (new keys being
# introduced, or keys previously added by an earlier include) never block a
# match -- this is what lets includes "add" fields without needing to repeat
# every axis value.
#
# NOTE: filter arguments must be captured with `as $x` before use inside a
# nested construct like `all`/`map` -- passing a bare `.` and re-referencing
# the argument later re-evaluates it in whatever `.` is current at that
# point, not the caller's `.` (a classic jq gotcha).
def matches_rule(combo; rule; axisKeys):
  (rule | to_entries | map(select(.key as $k | axisKeys | index($k) != null))) as $kvs
  | ($kvs | all( .key as $k | .value == (combo[$k]) ));

# apply_exclude(combos; axisKeys; excludes): drop any combo matched by at
# least one exclude rule.
def apply_exclude(combos; axisKeys; excludes):
  combos | map( . as $c | select( ( [excludes[] | matches_rule($c; .; axisKeys)] | any ) | not ) );

# apply_include(combos; axisKeys; includes): process include rules in order.
# Each rule is merged into every combo it matches (overwriting only fields
# previously added by an earlier include, never an original axis value); a
# rule matching zero combos is instead appended as a standalone new combo.
def apply_include(combos; axisKeys; includes):
  reduce includes[] as $inc (
    combos;
    . as $cur
    | ( [ $cur[] | . as $c | select( matches_rule($c; $inc; axisKeys) ) ] ) as $matched
    | if ( $matched | length ) > 0 then
        ( $cur | map( . as $c | if matches_rule($c; $inc; axisKeys) then . + $inc else . end ) )
      else
        $cur + [ $inc ]
      end
  );

# resolve_matrix(axes; excludes; includes): full pipeline -- cartesian
# product, then exclude, then include (in that order; this mirrors the
# order GitHub documents: excludes remove from the base product, includes
# are layered on top and may add back combinations excludes removed).
def resolve_matrix(axes; excludes; includes):
  (axes | keys) as $axisKeys
  | [cartesian_product(axes)] as $base
  | apply_exclude($base; $axisKeys; excludes) as $afterExclude
  | apply_include($afterExclude; $axisKeys; includes);
