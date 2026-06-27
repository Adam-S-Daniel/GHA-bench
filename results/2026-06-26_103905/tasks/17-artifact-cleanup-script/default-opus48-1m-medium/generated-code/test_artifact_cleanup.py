"""
Unit tests for the artifact cleanup script (red/green TDD).

Each test was written BEFORE the corresponding implementation. We build up the
functionality one policy at a time:

  1. Parsing/normalising artifact metadata.
  2. The "max age" retention policy.
  3. The "keep-latest-N per workflow" protective policy.
  4. The "max total size" retention policy.
  5. The combined deletion plan + summary.
  6. Dry-run behaviour.
  7. Graceful error handling.

All dates are expressed as ISO-8601 strings. To keep the tests deterministic the
cleanup functions accept an explicit ``now`` reference time rather than reading
the wall clock.
"""

import json
from datetime import datetime, timezone

import pytest

import artifact_cleanup as ac


# A fixed reference "now" used across the age-based tests.
NOW = datetime(2026, 6, 26, 12, 0, 0, tzinfo=timezone.utc)


def make_artifact(name, size, days_old, run_id, workflow):
    """Helper that builds an artifact dict whose creation date is ``days_old``
    days before NOW. Keeps the individual tests terse and readable."""
    created = NOW.timestamp() - days_old * 86400
    return {
        "name": name,
        "size_bytes": size,
        "created_at": datetime.fromtimestamp(created, tz=timezone.utc).isoformat(),
        "run_id": run_id,
        "workflow": workflow,
    }


# ---------------------------------------------------------------------------
# 1. Parsing / normalisation
# ---------------------------------------------------------------------------

def test_parse_artifact_normalises_created_at_to_datetime():
    raw = make_artifact("build", 100, 1, 1001, "ci")
    art = ac.parse_artifact(raw)
    assert isinstance(art.created_at, datetime)
    assert art.name == "build"
    assert art.size_bytes == 100


def test_parse_artifact_rejects_missing_fields():
    with pytest.raises(ac.ArtifactError):
        ac.parse_artifact({"name": "incomplete"})


def test_parse_artifact_rejects_negative_size():
    raw = make_artifact("bad", -5, 1, 1, "ci")
    with pytest.raises(ac.ArtifactError):
        ac.parse_artifact(raw)


# ---------------------------------------------------------------------------
# 2. max age policy
# ---------------------------------------------------------------------------

def test_max_age_marks_only_old_artifacts():
    artifacts = [
        make_artifact("a", 10, days_old=2, run_id=1, workflow="ci"),
        make_artifact("b", 10, days_old=40, run_id=2, workflow="ci"),
    ]
    plan = ac.build_plan(artifacts, policy={"max_age_days": 30}, now=NOW)
    deleted = {d["name"] for d in plan["delete"]}
    assert deleted == {"b"}


# ---------------------------------------------------------------------------
# 3. keep-latest-N per workflow (protective)
# ---------------------------------------------------------------------------

def test_keep_latest_protects_newest_per_workflow():
    artifacts = [
        make_artifact("old1", 10, days_old=50, run_id=1, workflow="ci"),
        make_artifact("old2", 10, days_old=40, run_id=2, workflow="ci"),
        make_artifact("new", 10, days_old=1, run_id=3, workflow="ci"),
    ]
    # keep latest 1 per workflow AND a max age that would otherwise nuke all.
    plan = ac.build_plan(
        artifacts, policy={"max_age_days": 5, "keep_latest_per_workflow": 1}, now=NOW
    )
    deleted = {d["name"] for d in plan["delete"]}
    retained = {r["name"] for r in plan["retain"]}
    # "new" is the latest in workflow "ci" -> protected even though < max age anyway.
    # old1/old2 exceed max age and are NOT among the latest 1 -> deleted.
    assert deleted == {"old1", "old2"}
    assert "new" in retained


def test_keep_latest_is_per_workflow_group():
    artifacts = [
        make_artifact("ci_old", 10, days_old=50, run_id=1, workflow="ci"),
        make_artifact("ci_new", 10, days_old=10, run_id=2, workflow="ci"),
        make_artifact("rel_old", 10, days_old=50, run_id=3, workflow="release"),
    ]
    plan = ac.build_plan(
        artifacts, policy={"keep_latest_per_workflow": 1}, now=NOW
    )
    deleted = {d["name"] for d in plan["delete"]}
    # Each workflow keeps its own latest; ci_old loses to ci_new, release keeps its only one.
    assert deleted == {"ci_old"}


# ---------------------------------------------------------------------------
# 4. max total size policy
# ---------------------------------------------------------------------------

def test_max_total_size_deletes_oldest_until_under_limit():
    artifacts = [
        make_artifact("a", 100, days_old=3, run_id=1, workflow="ci"),
        make_artifact("b", 100, days_old=2, run_id=2, workflow="ci"),
        make_artifact("c", 100, days_old=1, run_id=3, workflow="ci"),
    ]
    # Limit 250 -> must drop one 100-byte artifact, the oldest ("a").
    plan = ac.build_plan(artifacts, policy={"max_total_size_bytes": 250}, now=NOW)
    deleted = {d["name"] for d in plan["delete"]}
    assert deleted == {"a"}
    assert plan["summary"]["retained_size_bytes"] == 200


# ---------------------------------------------------------------------------
# 5. summary
# ---------------------------------------------------------------------------

def test_summary_reports_counts_and_reclaimed_space():
    artifacts = [
        make_artifact("a", 100, days_old=40, run_id=1, workflow="ci"),
        make_artifact("b", 200, days_old=1, run_id=2, workflow="ci"),
    ]
    plan = ac.build_plan(artifacts, policy={"max_age_days": 30}, now=NOW)
    s = plan["summary"]
    assert s["total_artifacts"] == 2
    assert s["deleted_count"] == 1
    assert s["retained_count"] == 1
    assert s["reclaimed_size_bytes"] == 100
    assert s["retained_size_bytes"] == 200


def test_delete_entries_record_a_reason():
    artifacts = [make_artifact("a", 100, days_old=40, run_id=1, workflow="ci")]
    plan = ac.build_plan(artifacts, policy={"max_age_days": 30}, now=NOW)
    assert plan["delete"][0]["reason"] == "max_age"


# ---------------------------------------------------------------------------
# 6. dry-run
# ---------------------------------------------------------------------------

def test_dry_run_flag_is_recorded_in_summary():
    artifacts = [make_artifact("a", 100, days_old=40, run_id=1, workflow="ci")]
    plan = ac.build_plan(artifacts, policy={"max_age_days": 30}, now=NOW, dry_run=True)
    assert plan["summary"]["dry_run"] is True


# ---------------------------------------------------------------------------
# 7. error handling
# ---------------------------------------------------------------------------

def test_build_plan_rejects_non_list():
    with pytest.raises(ac.ArtifactError):
        ac.build_plan({"not": "a list"}, policy={}, now=NOW)


def test_load_artifacts_reports_bad_json(tmp_path):
    bad = tmp_path / "bad.json"
    bad.write_text("{not valid json", encoding="utf-8")
    with pytest.raises(ac.ArtifactError):
        ac.load_artifacts(str(bad))


def test_load_artifacts_reports_missing_file():
    with pytest.raises(ac.ArtifactError):
        ac.load_artifacts("/no/such/file.json")
