#!/usr/bin/env bats
#
# Workflow STRUCTURE tests. These do not run act (that lives in
# run-act-tests.sh); they validate the workflow file statically: it is valid
# per actionlint, has the expected triggers/jobs/steps, and references files
# that actually exist on disk.

setup() {
  ROOT="${BATS_TEST_DIRNAME}/.."
  WF="${ROOT}/.github/workflows/semantic-version-bumper.yml"
}

# Small helper: query the parsed YAML with a tiny python expression that prints
# "1" for truthy / "0" for falsy so bats can assert on it.
yq() {
  python3 - "$WF" "$1" <<'PY'
import sys, yaml
doc = yaml.safe_load(open(sys.argv[1]))
expr = sys.argv[2]
val = eval(expr, {"doc": doc})
print("1" if val else "0")
PY
}

@test "workflow file exists" {
  [ -f "$WF" ]
}

@test "workflow passes actionlint cleanly" {
  run actionlint "$WF"
  [ "$status" -eq 0 ]
}

@test "workflow is valid YAML and has a name" {
  run yq "isinstance(doc.get('name'), str) and len(doc['name'])>0"
  [ "$output" = "1" ]
}

@test "workflow declares push, pull_request, schedule and workflow_dispatch triggers" {
  # PyYAML parses the bare key 'on' as the boolean True, so look it up by both.
  run yq "(lambda o: all(k in o for k in ('push','pull_request','schedule','workflow_dispatch')))(doc.get('on') or doc.get(True))"
  [ "$output" = "1" ]
}

@test "workflow sets least-privilege contents: read permission" {
  run yq "doc.get('permissions',{}).get('contents')=='read'"
  [ "$output" = "1" ]
}

@test "workflow has a bump job running on ubuntu-latest" {
  run yq "doc['jobs']['bump']['runs-on']=='ubuntu-latest'"
  [ "$output" = "1" ]
}

@test "bump job uses a matrix covering all six fixture cases" {
  run yq "set(e['case'] for e in doc['jobs']['bump']['strategy']['matrix']['include']) == {'patch','minor','major','pkgjson','breaking-footer','none'}"
  [ "$output" = "1" ]
}

@test "bump job checks out the repo with actions/checkout@v4" {
  run yq "any(s.get('uses')=='actions/checkout@v4' for s in doc['jobs']['bump']['steps'])"
  [ "$output" = "1" ]
}

@test "bump job invokes the semver-bump.sh script" {
  run yq "any('semver-bump.sh' in (s.get('run') or '') for s in doc['jobs']['bump']['steps'])"
  [ "$output" = "1" ]
}

@test "workflow references the script file which exists on disk" {
  [ -f "${ROOT}/semver-bump.sh" ]
}

@test "every fixture path referenced by the matrix exists on disk" {
  run python3 - "$WF" "$ROOT" <<'PY'
import sys, os, yaml
wf, root = sys.argv[1], sys.argv[2]
doc = yaml.safe_load(open(wf))
missing = []
for e in doc['jobs']['bump']['strategy']['matrix']['include']:
    for key in ('version_file', 'commits'):
        p = os.path.join(root, e[key])
        if not os.path.isfile(p):
            missing.append(e[key])
print("MISSING:" + ",".join(missing) if missing else "OK")
PY
  [ "$output" = "OK" ]
}

@test "matrix expected versions match the documented bump rules" {
  run python3 - "$WF" <<'PY'
import sys, yaml
doc = yaml.safe_load(open(sys.argv[1]))
want = {'patch':'1.1.1','minor':'1.2.0','major':'2.0.0',
        'pkgjson':'0.4.0','breaking-footer':'3.0.0','none':'1.1.0'}
got = {e['case']: str(e['expected']) for e in doc['jobs']['bump']['strategy']['matrix']['include']}
print("OK" if got == want else f"MISMATCH {got}")
PY
  [ "$output" = "OK" ]
}
