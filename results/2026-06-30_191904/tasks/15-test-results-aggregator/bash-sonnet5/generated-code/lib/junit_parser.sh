#!/usr/bin/env bash
# JUnit XML parser -- pure bash (no xmllint/xmlstarlet dependency).
#
# JUnit XML is simple enough that a line-oriented state machine over
# <testcase> ... </testcase> blocks is sufficient; we don't need a full
# XML parser. This intentionally only supports the common JUnit shape:
# a <testcase classname="..." name="..." time="..."> element that is
# either self-closed (pass) or contains a <failure>/<error> (fail) or
# <skipped> (skip) child.

# Extract the value of attribute $2 from XML fragment $1. Prints nothing
# if the attribute is not present. The boundary group before the key
# prevents "name" from matching inside "classname".
_junit_attr() {
  local fragment="$1" key="$2"
  if [[ $fragment =~ (^|[^A-Za-z])${key}=\"([^\"]*)\" ]]; then
    printf '%s' "${BASH_REMATCH[2]}"
  fi
}

# Collapse tabs/newlines in a string so it is safe to embed in a single
# TSV field / markdown table cell.
_junit_sanitize() {
  local s="$1"
  s="${s//$'\t'/ }"
  s="${s//$'\n'/ }"
  s="${s//$'\r'/ }"
  printf '%s' "$s"
}

# parse_junit_xml FILE RUN_ID
#
# Prints one normalized TSV record per <testcase>:
#   run_id<TAB>classname<TAB>name<TAB>status<TAB>duration<TAB>message
#
# status is one of: passed, failed, skipped
# Exits non-zero with a message on stderr if the file cannot be parsed
# as JUnit XML (missing <testcase> elements, or a testcase missing its
# required "name" attribute).
parse_junit_xml() {
  local file="$1" run_id="$2"
  local in_testcase=0 classname="" name="" duration="0" status="passed" message=""
  local line record_count=0

  if [[ ! -f "$file" ]]; then
    echo "ERROR: JUnit XML file not found: $file" >&2
    return 1
  fi
  if ! grep -q '<testcase' "$file"; then
    echo "ERROR: failed to parse JUnit XML file '$file': no <testcase> elements found" >&2
    return 1
  fi

  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ $line =~ \<testcase[[:space:]] ]]; then
      classname=$(_junit_attr "$line" classname)
      name=$(_junit_attr "$line" name)
      duration=$(_junit_attr "$line" time)
      [[ -z "$duration" ]] && duration="0"
      status="passed"
      message=""

      if [[ -z "$name" ]]; then
        echo "ERROR: malformed JUnit XML in '$file': <testcase> missing required 'name' attribute" >&2
        return 1
      fi

      if [[ $line =~ /\>[[:space:]]*$ ]]; then
        printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$run_id" "$classname" "$name" "$status" "$duration" "$message"
        record_count=$((record_count + 1))
        in_testcase=0
      else
        in_testcase=1
      fi
      continue
    fi

    if ((in_testcase)); then
      if [[ $line =~ \<(failure|error) ]]; then
        status="failed"
        message=$(_junit_sanitize "$(_junit_attr "$line" message)")
      elif [[ $line =~ \<skipped ]]; then
        status="skipped"
        message=$(_junit_sanitize "$(_junit_attr "$line" message)")
      elif [[ $line =~ \</testcase\> ]]; then
        printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$run_id" "$classname" "$name" "$status" "$duration" "$message"
        record_count=$((record_count + 1))
        in_testcase=0
      fi
    fi
  done < "$file"

  if ((record_count == 0)); then
    echo "ERROR: failed to parse JUnit XML file '$file': no complete <testcase> records found" >&2
    return 1
  fi
  return 0
}
