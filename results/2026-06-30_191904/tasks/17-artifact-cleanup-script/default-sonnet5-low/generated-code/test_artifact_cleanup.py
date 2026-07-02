"""
Red/Green TDD test suite for artifact_cleanup.py.

Each test below was written before its corresponding implementation piece,
per the task's TDD requirement. Fixtures (mock artifact lists) are defined
once at module scope and reused across tests to avoid fixture churn.
"""
import pytest
from datetime import datetime, timedelta

from artifact_cleanup import (
    Artifact,
    apply_max_age_policy,
    apply_keep_latest_n_policy,
    apply_max_total_size_policy,
    build_deletion_plan,
)

NOW = datetime(2026, 7, 1, 12, 0, 0)


def make_artifact(name, size_bytes, age_days, workflow_run_id, workflow_name="ci"):
    """Helper to build an Artifact fixture at a given age relative to NOW."""
    return Artifact(
        name=name,
        size_bytes=size_bytes,
        created_at=NOW - timedelta(days=age_days),
        workflow_run_id=workflow_run_id,
        workflow_name=workflow_name,
    )


# ---------------------------------------------------------------------------
# Piece 1: max-age retention policy
# ---------------------------------------------------------------------------

def test_max_age_policy_flags_old_artifacts_for_deletion():
    artifacts = [
        make_artifact("recent", 100, age_days=1, workflow_run_id=1),
        make_artifact("old", 100, age_days=100, workflow_run_id=2),
    ]
    to_delete = apply_max_age_policy(artifacts, max_age_days=90, now=NOW)
    assert [a.name for a in to_delete] == ["old"]


def test_max_age_policy_keeps_artifacts_within_limit():
    artifacts = [make_artifact("edge", 100, age_days=89, workflow_run_id=1)]
    to_delete = apply_max_age_policy(artifacts, max_age_days=90, now=NOW)
    assert to_delete == []


# ---------------------------------------------------------------------------
# Piece 2: keep-latest-N per workflow policy
# ---------------------------------------------------------------------------

def test_keep_latest_n_flags_older_artifacts_beyond_n_per_workflow():
    artifacts = [
        make_artifact("wf1-run3", 10, age_days=1, workflow_run_id=3, workflow_name="build"),
        make_artifact("wf1-run2", 10, age_days=2, workflow_run_id=2, workflow_name="build"),
        make_artifact("wf1-run1", 10, age_days=3, workflow_run_id=1, workflow_name="build"),
        make_artifact("wf2-run1", 10, age_days=1, workflow_run_id=1, workflow_name="deploy"),
    ]
    to_delete = apply_keep_latest_n_policy(artifacts, keep_latest_n=2)
    # "build" workflow has 3 artifacts, keep the 2 newest, delete the oldest.
    # "deploy" workflow only has 1 artifact, nothing to delete.
    assert [a.name for a in to_delete] == ["wf1-run1"]


def test_keep_latest_n_keeps_all_when_under_limit():
    artifacts = [
        make_artifact("only-one", 10, age_days=1, workflow_run_id=1, workflow_name="build"),
    ]
    to_delete = apply_keep_latest_n_policy(artifacts, keep_latest_n=5)
    assert to_delete == []


# ---------------------------------------------------------------------------
# Piece 3: max total size policy (oldest-first eviction until under budget)
# ---------------------------------------------------------------------------

def test_max_total_size_policy_evicts_oldest_until_under_budget():
    artifacts = [
        make_artifact("newest", 50, age_days=1, workflow_run_id=1),
        make_artifact("middle", 50, age_days=2, workflow_run_id=2),
        make_artifact("oldest", 50, age_days=3, workflow_run_id=3),
    ]
    # Total size is 150; budget is 100, so we must evict at least 50 bytes.
    # Oldest-first eviction removes "oldest" (50), bringing total to 100 <= 100.
    to_delete = apply_max_total_size_policy(artifacts, max_total_size_bytes=100)
    assert [a.name for a in to_delete] == ["oldest"]


def test_max_total_size_policy_no_op_when_under_budget():
    artifacts = [make_artifact("small", 10, age_days=1, workflow_run_id=1)]
    to_delete = apply_max_total_size_policy(artifacts, max_total_size_bytes=100)
    assert to_delete == []


# ---------------------------------------------------------------------------
# Piece 4: combined deletion plan + summary + dry-run
# ---------------------------------------------------------------------------

def test_build_deletion_plan_combines_all_policies_and_summarizes():
    artifacts = [
        make_artifact("old-and-big", 200, age_days=100, workflow_run_id=1, workflow_name="build"),
        make_artifact("kept", 50, age_days=1, workflow_run_id=2, workflow_name="build"),
    ]
    plan = build_deletion_plan(
        artifacts,
        max_age_days=90,
        max_total_size_bytes=10_000,
        keep_latest_n=5,
        now=NOW,
    )
    assert [a.name for a in plan.to_delete] == ["old-and-big"]
    assert [a.name for a in plan.to_retain] == ["kept"]
    assert plan.total_bytes_reclaimed == 200
    assert plan.retained_count == 1
    assert plan.deleted_count == 1


def test_build_deletion_plan_dry_run_does_not_mutate_input_and_marks_dry_run():
    artifacts = [make_artifact("old", 100, age_days=100, workflow_run_id=1)]
    plan = build_deletion_plan(
        artifacts,
        max_age_days=90,
        max_total_size_bytes=None,
        keep_latest_n=None,
        now=NOW,
        dry_run=True,
    )
    assert plan.dry_run is True
    assert plan.deleted_count == 1
    # dry run: input list itself is untouched (no deletion actually performed)
    assert len(artifacts) == 1


def test_build_deletion_plan_raises_on_invalid_max_age():
    with pytest.raises(ValueError, match="max_age_days must be positive"):
        build_deletion_plan([], max_age_days=-1, max_total_size_bytes=None,
                             keep_latest_n=None, now=NOW)


def test_build_deletion_plan_raises_on_invalid_keep_latest_n():
    with pytest.raises(ValueError, match="keep_latest_n must be positive"):
        build_deletion_plan([], max_age_days=None, max_total_size_bytes=None,
                             keep_latest_n=0, now=NOW)
