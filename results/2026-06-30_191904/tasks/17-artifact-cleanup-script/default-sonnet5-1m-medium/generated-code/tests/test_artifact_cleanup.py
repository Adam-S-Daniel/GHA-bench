"""
Red/Green TDD test suite for artifact_cleanup.

Each test below was written before its corresponding implementation code.
Run with: python3 -m pytest tests/ -v
"""
from datetime import datetime, timedelta, timezone

import pytest

from artifact_cleanup import Artifact, RetentionPolicy, plan_deletions, execute_plan


def _art(name, days_old, size_bytes=100, workflow_run_id="run-1", now=None):
    now = now or datetime(2026, 1, 31, tzinfo=timezone.utc)
    return Artifact(
        name=name,
        size_bytes=size_bytes,
        created_at=now - timedelta(days=days_old),
        workflow_run_id=workflow_run_id,
    )


def test_artifact_holds_basic_metadata():
    # First failing test: Artifact is just a metadata container.
    created = datetime(2026, 1, 1, tzinfo=timezone.utc)
    art = Artifact(
        name="build-output",
        size_bytes=1024,
        created_at=created,
        workflow_run_id="run-1",
    )
    assert art.name == "build-output"
    assert art.size_bytes == 1024
    assert art.created_at == created
    assert art.workflow_run_id == "run-1"


def test_max_age_policy_deletes_artifacts_older_than_threshold():
    # Second failing test: max_age_days policy alone.
    now = datetime(2026, 1, 31, tzinfo=timezone.utc)
    artifacts = [
        _art("old", days_old=10, now=now),
        _art("new", days_old=1, now=now),
    ]
    policy = RetentionPolicy(max_age_days=5)
    plan = plan_deletions(artifacts, policy, now=now)

    assert [a.name for a in plan.to_delete] == ["old"]
    assert [a.name for a in plan.to_retain] == ["new"]


def test_keep_latest_n_per_workflow_overrides_max_age():
    # Third failing test: keep_latest_n_per_workflow protects recent artifacts
    # from an otherwise-triggered max_age deletion.
    now = datetime(2026, 1, 31, tzinfo=timezone.utc)
    artifacts = [
        _art("wf1-oldest", days_old=30, workflow_run_id="wf1", now=now),
        _art("wf1-old", days_old=20, workflow_run_id="wf1", now=now),
        _art("wf1-newest", days_old=10, workflow_run_id="wf1", now=now),
        _art("wf2-only", days_old=10, workflow_run_id="wf2", now=now),
    ]
    policy = RetentionPolicy(max_age_days=5, keep_latest_n_per_workflow=1)
    plan = plan_deletions(artifacts, policy, now=now)

    # wf1-newest and wf2-only are each the latest artifact for their
    # workflow, so they're kept even though they're older than max_age_days.
    assert sorted(a.name for a in plan.to_retain) == ["wf1-newest", "wf2-only"]
    assert sorted(a.name for a in plan.to_delete) == ["wf1-old", "wf1-oldest"]


def test_max_total_size_deletes_oldest_survivors_until_under_budget():
    # Fourth failing test: max_total_size_bytes deletes oldest-first among
    # artifacts that survived other policies, until total size <= budget.
    now = datetime(2026, 1, 31, tzinfo=timezone.utc)
    artifacts = [
        _art("a-oldest", days_old=30, size_bytes=50, workflow_run_id="wf1", now=now),
        _art("b-middle", days_old=20, size_bytes=50, workflow_run_id="wf2", now=now),
        _art("c-newest", days_old=10, size_bytes=50, workflow_run_id="wf3", now=now),
    ]
    policy = RetentionPolicy(max_total_size_bytes=80)
    plan = plan_deletions(artifacts, policy, now=now)

    # Total is 150; must drop to <= 80. Oldest ("a-oldest", 50) removed first,
    # leaving 100, still over budget, so next oldest ("b-middle", 50) also
    # removed, leaving 50 <= 80.
    assert sorted(a.name for a in plan.to_delete) == ["a-oldest", "b-middle"]
    assert [a.name for a in plan.to_retain] == ["c-newest"]


def test_max_total_size_respects_keep_latest_n_protection():
    # keep_latest_n_per_workflow protection must be honored even when it
    # means staying over the size budget.
    now = datetime(2026, 1, 31, tzinfo=timezone.utc)
    artifacts = [
        _art("only-one", days_old=30, size_bytes=200, workflow_run_id="wf1", now=now),
    ]
    policy = RetentionPolicy(max_total_size_bytes=10, keep_latest_n_per_workflow=1)
    plan = plan_deletions(artifacts, policy, now=now)

    assert plan.to_delete == []
    assert [a.name for a in plan.to_retain] == ["only-one"]


def test_deletion_plan_summary_reports_space_and_counts():
    # Fifth failing test: DeletionPlan.summary() aggregates space reclaimed
    # and retained/deleted counts.
    now = datetime(2026, 1, 31, tzinfo=timezone.utc)
    artifacts = [
        _art("old", days_old=10, size_bytes=300, now=now),
        _art("new", days_old=1, size_bytes=100, now=now),
    ]
    policy = RetentionPolicy(max_age_days=5)
    plan = plan_deletions(artifacts, policy, now=now)

    summary = plan.summary()
    assert summary["artifacts_deleted"] == 1
    assert summary["artifacts_retained"] == 1
    assert summary["space_reclaimed_bytes"] == 300


def test_execute_plan_dry_run_does_not_call_deleter():
    # Sixth failing test: dry_run=True must not invoke the deleter callback,
    # but still reports what *would* be deleted.
    now = datetime(2026, 1, 31, tzinfo=timezone.utc)
    artifacts = [_art("old", days_old=10, now=now)]
    policy = RetentionPolicy(max_age_days=5)
    plan = plan_deletions(artifacts, policy, now=now)

    calls = []
    result = execute_plan(plan, deleter=calls.append, dry_run=True)

    assert calls == []
    assert result.dry_run is True
    assert [a.name for a in result.deleted] == ["old"]


def test_execute_plan_live_run_invokes_deleter_for_each_deletion():
    # Seventh failing test: dry_run=False calls the deleter once per artifact
    # to be deleted (mock deleter used for testability -- no real API calls).
    now = datetime(2026, 1, 31, tzinfo=timezone.utc)
    artifacts = [_art("old", days_old=10, now=now), _art("new", days_old=1, now=now)]
    policy = RetentionPolicy(max_age_days=5)
    plan = plan_deletions(artifacts, policy, now=now)

    calls = []
    result = execute_plan(plan, deleter=calls.append, dry_run=False)

    assert [a.name for a in calls] == ["old"]
    assert result.dry_run is False
    assert [a.name for a in result.deleted] == ["old"]
    assert result.errors == []


def test_execute_plan_records_error_and_continues_when_deleter_raises():
    # Eighth failing test: a deleter failure for one artifact must not abort
    # the whole run -- it should be recorded with a meaningful message and
    # processing should continue for remaining artifacts.
    now = datetime(2026, 1, 31, tzinfo=timezone.utc)
    artifacts = [
        _art("fails", days_old=10, workflow_run_id="wf1", now=now),
        _art("also-old", days_old=10, workflow_run_id="wf2", now=now),
    ]
    policy = RetentionPolicy(max_age_days=5)
    plan = plan_deletions(artifacts, policy, now=now)

    def flaky_deleter(art):
        if art.name == "fails":
            raise RuntimeError("simulated API failure")

    result = execute_plan(plan, deleter=flaky_deleter, dry_run=False)

    assert [a.name for a in result.deleted] == ["also-old"]
    assert len(result.errors) == 1
    assert "fails" in result.errors[0]
    assert "simulated API failure" in result.errors[0]


def test_plan_deletions_rejects_negative_max_age():
    # Ninth failing test: boundary validation with a meaningful error
    # message, rather than silently misbehaving on bad policy input.
    now = datetime(2026, 1, 31, tzinfo=timezone.utc)
    policy = RetentionPolicy(max_age_days=-1)

    with pytest.raises(ValueError, match="max_age_days must be non-negative"):
        plan_deletions([], policy, now=now)


def test_plan_deletions_rejects_negative_max_total_size():
    now = datetime(2026, 1, 31, tzinfo=timezone.utc)
    policy = RetentionPolicy(max_total_size_bytes=-5)

    with pytest.raises(ValueError, match="max_total_size_bytes must be non-negative"):
        plan_deletions([], policy, now=now)


def test_plan_deletions_rejects_negative_keep_latest_n():
    now = datetime(2026, 1, 31, tzinfo=timezone.utc)
    policy = RetentionPolicy(keep_latest_n_per_workflow=-1)

    with pytest.raises(ValueError, match="keep_latest_n_per_workflow must be non-negative"):
        plan_deletions([], policy, now=now)
