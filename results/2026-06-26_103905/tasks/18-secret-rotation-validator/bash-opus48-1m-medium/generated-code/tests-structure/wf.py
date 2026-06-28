#!/usr/bin/env python3
"""Helper for workflow-structure tests.

Loads the workflow YAML and answers a single query passed as argv[1].
Note: YAML 1.1 parses the bare key ``on`` as boolean True, so we normalise
that back to the string "on" before querying.
"""
import sys
import yaml

WF = ".github/workflows/secret-rotation-validator.yml"


def load():
    with open(WF) as fh:
        data = yaml.safe_load(fh)
    # Normalise the truthy "on" key back to a string.
    if True in data:
        data["on"] = data.pop(True)
    return data


def main():
    query = sys.argv[1]
    d = load()
    triggers = d["on"]
    jobs = d["jobs"]

    if query == "name":
        print(d["name"])
    elif query == "triggers":
        print(",".join(sorted(triggers.keys())))
    elif query == "permissions":
        print(d["permissions"]["contents"])
    elif query == "jobs":
        print(",".join(sorted(jobs.keys())))
    elif query == "report-needs":
        print(",".join(jobs["report"]["needs"]) if isinstance(
            jobs["report"]["needs"], list) else jobs["report"]["needs"])
    elif query == "uses-checkout":
        steps = [s for j in jobs.values() for s in j["steps"]]
        print(any(str(s.get("uses", "")).startswith(
            "actions/checkout@v4") for s in steps))
    elif query == "runs-script":
        text = open(WF).read()
        print("secret-rotation-validator.sh" in text)
    elif query == "config-file":
        print(d["env"]["CONFIG_FILE"])
    elif query == "runs-bats":
        text = open(WF).read()
        print("bats tests/" in text)
    else:
        sys.exit("unknown query: " + query)


if __name__ == "__main__":
    main()
