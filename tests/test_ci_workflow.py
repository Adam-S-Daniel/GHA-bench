"""Structural guards on this repo's OWN CI workflow (.github/workflows/ci.yml).

Why this file exists: #53 added `workflow_dispatch:` to ci.yml -- an event that can
re-fire on a head SHA that push/pull_request already covered. Its safety argument was
that this repo publishes no REQUIRED status context, which is true, but which is a fact
about repo-settings' fleet.yml: another repo, editable without anything here noticing,
and one whose sibling entry for `Adam-S-Daniel/agentskills` already carries exactly the
`required_status_checks` override that would flip it. That argument was recorded only in
a workflow comment and in the commit message, with NOTHING enforcing it -- an
unenforced, point-in-time assertion about somebody else's config.

These tests are the enforcement, and they deliberately lock the property that holds
WHETHER OR NOT a required check ever appears, rather than re-asserting the fleet.yml
fact: a job that publishes a required context and can fire more than once on one head
SHA must carry NO `concurrency` block at all. GitHub picks non-deterministically between
a cancelled run and a successful one for the same context + SHA, and when cancelled wins
the merge API returns `405 Required status check "<ctx>" is cancelled` -- which nothing
overrides, so the PR reads all-green and never lands. `cancel-in-progress: false` is not
a substitute; GitHub keeps the in-progress run plus only the LATEST pending one and
cancels the other duplicates.

Deliberately NOT asserted here: that repo-settings' fleet.yml still gives this repo no
required check. That file is in a different, private repo; a CI runner checking out
GHA-bench will never have it, so the assertion would be permanently skipped in the one
place that gates merges -- a guard that silently examines nothing. Locally its path is
host-specific (repos live under `/home/user/<repo>` here and `D:\\repos\\<owner>\\<repo>`
on ZENDA), and a local clone can be stale, so a green assert against it would be a FALSE
clearance rather than no clearance. Cross-repo enforcement belongs in repo-settings; the
in-file precondition plus this no-concurrency lock is the right stopping point here.

Parsed with PyYAML, never regex- or line-scanned: a scan reads clean on a `concurrency:`
key it cannot see -- inside a quoted block, or behind a YAML anchor, which GitHub enabled
in workflows on 2025-09-18.
"""

from pathlib import Path

try:
    import yaml
except ImportError as exc:  # pragma: no cover - environment guard, not a code path
    raise ImportError(
        "PyYAML is required to lint .github/workflows/ci.yml structurally; a regex or "
        "line scan reads clean on text it cannot see, so this guard must parse. ci.yml's "
        "'Install dependencies' step installs it -- restore that package rather than "
        "skipping this module. Never pytest.importorskip here: a silent skip is exactly "
        "the failure this file exists to close."
    ) from exc

REPO_ROOT = Path(__file__).resolve().parent.parent
CI_WORKFLOW = REPO_ROOT / ".github" / "workflows" / "ci.yml"

# The exact trigger set ci.yml's PRECONDITION block claims. Compared as a SET EQUALITY so
# that ADDING a trigger fails here too, not just removing one: every extra event is
# another way to land two runs on one head SHA, and the precondition has to be re-read
# before one goes in.
EXPECTED_TRIGGERS = {"push", "pull_request", "workflow_dispatch"}

# Lexical anchor for the in-file precondition (one leaf token, not a structural claim --
# YAML comments do not survive parsing, so there is nothing structural to assert). Its
# job is narrow: stop the revisit-condition from being quietly deleted back into a commit
# message, which is where #53 left it and where nobody editing fleet.yml can see it.
PRECONDITION_MARKER = "PRECONDITION (repo-settings/fleet.yml)"


def _read_ci_workflow_text():
    """Return ci.yml's text, failing loudly if the file is missing or empty."""
    assert CI_WORKFLOW.is_file(), (
        f"{CI_WORKFLOW} is missing. These guards cover this repo's own merge gate; if the "
        "workflow moved, point them at the new path -- do not let them pass on a file "
        "that is not there."
    )
    text = CI_WORKFLOW.read_text(encoding="utf-8")
    assert text.strip(), f"{CI_WORKFLOW} is empty; there is nothing here to have checked."
    return text


def _load_ci_workflow():
    """Parse ci.yml into a non-empty mapping.

    The vacuity floor for every guard below: `"concurrency" not in doc` is trivially true
    of an empty or non-mapping document, so a parse that yields nothing must fail here
    rather than being handed on as a clean bill of health.
    """
    doc = yaml.safe_load(_read_ci_workflow_text())
    assert isinstance(doc, dict) and doc, (
        f"{CI_WORKFLOW} did not parse to a non-empty mapping (got {type(doc).__name__}). "
        "A guard that asserts a key is ABSENT passes vacuously on an empty document, so "
        "stop here instead."
    )
    return doc


def _jobs(doc):
    """Return ci.yml's jobs mapping, refusing an empty one."""
    jobs = doc.get("jobs")
    assert isinstance(jobs, dict) and jobs, (
        f"{CI_WORKFLOW} declares no jobs. The per-job concurrency guard iterates this "
        "mapping and would pass on zero jobs while checking nothing."
    )
    return jobs


def _triggers(doc):
    """Return ci.yml's `on:` mapping, refusing an empty one.

    YAML 1.1 resolves a bare `on:` to the boolean True, so the key PyYAML hands back is
    `True` and not the string "on" -- read only one of the two and a real trigger set
    looks like no trigger set at all.
    """
    on = doc.get("on", doc.get(True))
    assert isinstance(on, dict) and on, (
        f"{CI_WORKFLOW} has no usable `on:` mapping (got {type(on).__name__}). A workflow "
        "with no triggers cannot be compared against the documented set."
    )
    return on


def test_ci_workflow_parses_and_declares_jobs():
    """Vacuity floor: the file exists, parses to a mapping, and has jobs to inspect."""
    doc = _load_ci_workflow()
    jobs = _jobs(doc)
    assert "test" in jobs, (
        f"ci.yml's `test` job is gone (jobs: {sorted(jobs)}). That job publishes the "
        "`CI / test` context named in ci.yml's PRECONDITION block; if it was renamed, "
        "update the precondition too so the 405 story still names a real context."
    )


def test_ci_workflow_declares_no_workflow_level_concurrency():
    """No workflow-level `concurrency` -- see this module's docstring for the 405 trap."""
    doc = _load_ci_workflow()
    assert "concurrency" not in doc, (
        "ci.yml declared a workflow-level `concurrency` group. This workflow runs on a "
        "re-fireable event (workflow_dispatch) and its context becomes REQUIRED the day "
        "repo-settings' fleet.yml grows a required check for this repo; a concurrency "
        "group is what leaves a cancelled run shadowing a success, and the merge API "
        f"then answers 405 forever. Found: {doc.get('concurrency')!r}. "
        "`cancel-in-progress: false` is not a fix -- remove the block."
    )


def test_ci_workflow_jobs_declare_no_concurrency():
    """No job-level `concurrency` either -- a per-job group wedges the same way."""
    doc = _load_ci_workflow()
    offenders = {
        name: job["concurrency"]
        for name, job in _jobs(doc).items()
        if isinstance(job, dict) and "concurrency" in job
    }
    assert not offenders, (
        f"ci.yml job(s) declared a `concurrency` group: {offenders!r}. A job-level group "
        "cancels same-SHA duplicates exactly like a workflow-level one, so it re-opens "
        "the `405 Required status check \"CI / test\" is cancelled` trap the moment this "
        "repo's ruleset gains a required check. See ci.yml's PRECONDITION block."
    )


def test_ci_workflow_trigger_set_matches_the_documented_precondition():
    """The trigger set is exactly what ci.yml's PRECONDITION block claims it is."""
    triggers = set(_triggers(_load_ci_workflow()))
    assert triggers == EXPECTED_TRIGGERS, (
        f"ci.yml's triggers are {sorted(triggers)}, not the documented "
        f"{sorted(EXPECTED_TRIGGERS)}. Every event is another way to produce two runs on "
        "one head SHA, so re-read ci.yml's PRECONDITION block before widening this: if "
        "the addition is right, change it there and here together. (A removal fails here "
        "too, on purpose -- the comment must not outlive the thing it describes.)"
    )


def test_ci_workflow_carries_the_revisit_condition_in_the_file():
    """The revisit-condition stays IN ci.yml, not only in a commit message.

    #53 left it in the commit message alone, where it is invisible both to someone
    reading ci.yml and to someone editing fleet.yml in another repo. This fleet's own
    guidance is that durable findings go in the repo, because repo files version with the
    code and every harness that opens the repo sees them.
    """
    text = _read_ci_workflow_text()
    assert PRECONDITION_MARKER in text, (
        f"ci.yml no longer contains {PRECONDITION_MARKER!r}. The precondition behind its "
        "`workflow_dispatch:` trigger -- that repo-settings' fleet.yml gives this repo no "
        "required status check, that the fact lives in another repo and can change "
        "unnoticed, and that a required context plus a re-fireable event is what triggers "
        "the unoverridable 405 -- has to stay readable at the point of edit. Restore it."
    )
