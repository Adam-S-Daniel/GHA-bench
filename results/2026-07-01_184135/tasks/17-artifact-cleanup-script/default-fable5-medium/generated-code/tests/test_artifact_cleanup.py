"""Unit tests for the artifact cleanup planner.

Built test-first (red/green TDD). Each test class corresponds to one
increment of functionality that was added to make it pass.
"""

from datetime import datetime, timedelta, timezone

import pytest

from artifact_cleanup import Artifact, RetentionPolicy, build_plan


# A fixed "now" so age calculations are deterministic in tests.
NOW = datetime(2026, 7, 1, 0, 0, 0, tzinfo=timezone.utc)


def make_artifact(name, size=100, days_old=0, run_id=1):
    """Test fixture helper: build an Artifact created `days_old` days before NOW."""
    created = NOW - timedelta(days=days_old)
    return Artifact(name=name, size_bytes=size, created_at=created, workflow_run_id=run_id)


class TestMaxAgePolicy:
    def test_artifacts_older_than_max_age_are_deleted(self):
        artifacts = [
            make_artifact("fresh", days_old=1),
            make_artifact("stale", days_old=31),
        ]
        policy = RetentionPolicy(max_age_days=30)
        plan = build_plan(artifacts, policy, now=NOW)
        assert [a.name for a in plan.deleted] == ["stale"]
        assert [a.name for a in plan.retained] == ["fresh"]

    def test_no_max_age_keeps_everything(self):
        artifacts = [make_artifact("ancient", days_old=999)]
        plan = build_plan(artifacts, RetentionPolicy(), now=NOW)
        assert plan.deleted == []
        assert [a.name for a in plan.retained] == ["ancient"]


class TestKeepLatestNPolicy:
    def test_keeps_only_newest_n_per_workflow_run(self):
        artifacts = [
            make_artifact("run1-old", days_old=3, run_id=1),
            make_artifact("run1-mid", days_old=2, run_id=1),
            make_artifact("run1-new", days_old=1, run_id=1),
            make_artifact("run2-only", days_old=5, run_id=2),
        ]
        policy = RetentionPolicy(keep_latest_n=2)
        plan = build_plan(artifacts, policy, now=NOW)
        # run 1: keep the 2 newest, drop the oldest. run 2: under the limit.
        assert [a.name for a in plan.deleted] == ["run1-old"]
        assert sorted(a.name for a in plan.retained) == [
            "run1-mid",
            "run1-new",
            "run2-only",
        ]


class TestMaxTotalSizePolicy:
    def test_oldest_artifacts_evicted_until_under_budget(self):
        artifacts = [
            make_artifact("oldest", size=400, days_old=3),
            make_artifact("middle", size=400, days_old=2),
            make_artifact("newest", size=400, days_old=1),
        ]
        # Budget fits only two artifacts: the oldest must be evicted.
        policy = RetentionPolicy(max_total_bytes=800)
        plan = build_plan(artifacts, policy, now=NOW)
        assert [a.name for a in plan.deleted] == ["oldest"]
        assert sorted(a.name for a in plan.retained) == ["middle", "newest"]

    def test_within_budget_deletes_nothing(self):
        artifacts = [make_artifact("a", size=100), make_artifact("b", size=100)]
        plan = build_plan(artifacts, RetentionPolicy(max_total_bytes=200), now=NOW)
        assert plan.deleted == []


class TestDeletionReasons:
    def test_each_deletion_records_the_policy_that_caused_it(self):
        artifacts = [
            make_artifact("too-old", days_old=40, run_id=1),
            make_artifact("extra-old", days_old=5, run_id=2),
            make_artifact("extra-new", days_old=2, run_id=2),
            make_artifact("big-old", size=900, days_old=3, run_id=3),
            make_artifact("keeper", size=100, days_old=1, run_id=4),
        ]
        policy = RetentionPolicy(
            max_age_days=30, keep_latest_n=1, max_total_bytes=1000
        )
        plan = build_plan(artifacts, policy, now=NOW)
        assert plan.reasons["too-old"] == "exceeds max age of 30 days"
        assert plan.reasons["extra-old"] == "exceeds keep-latest-1 for workflow run 2"
        assert plan.reasons["big-old"] == "evicted to satisfy total size budget of 1000 bytes"
        assert "keeper" not in plan.reasons


class TestSummary:
    def test_summary_totals(self):
        artifacts = [
            make_artifact("kept-1", size=100, days_old=1),
            make_artifact("kept-2", size=200, days_old=2),
            make_artifact("gone-1", size=300, days_old=40),
            make_artifact("gone-2", size=400, days_old=50),
        ]
        plan = build_plan(artifacts, RetentionPolicy(max_age_days=30), now=NOW)
        summary = plan.summary()
        assert summary == {
            "retained_count": 2,
            "deleted_count": 2,
            "space_reclaimed_bytes": 700,
            "retained_bytes": 300,
        }


class TestParseArtifacts:
    def test_parses_valid_records(self):
        from artifact_cleanup import parse_artifacts

        records = [
            {
                "name": "build-logs",
                "size_bytes": 1024,
                "created_at": "2026-06-30T12:00:00Z",
                "workflow_run_id": 42,
            }
        ]
        (artifact,) = parse_artifacts(records)
        assert artifact.name == "build-logs"
        assert artifact.size_bytes == 1024
        assert artifact.workflow_run_id == 42
        assert artifact.created_at == datetime(2026, 6, 30, 12, 0, tzinfo=timezone.utc)

    def test_missing_field_raises_meaningful_error(self):
        from artifact_cleanup import CleanupError, parse_artifacts

        with pytest.raises(CleanupError, match="artifact #1 .*missing.*'size_bytes'"):
            parse_artifacts([{"name": "x", "created_at": "2026-01-01T00:00:00Z", "workflow_run_id": 1}])

    def test_bad_date_raises_meaningful_error(self):
        from artifact_cleanup import CleanupError, parse_artifacts

        with pytest.raises(CleanupError, match="invalid created_at"):
            parse_artifacts(
                [{"name": "x", "size_bytes": 1, "created_at": "yesterday", "workflow_run_id": 1}]
            )

    def test_negative_size_raises_meaningful_error(self):
        from artifact_cleanup import CleanupError, parse_artifacts

        with pytest.raises(CleanupError, match="size_bytes must be a non-negative integer"):
            parse_artifacts(
                [{"name": "x", "size_bytes": -5, "created_at": "2026-01-01T00:00:00Z", "workflow_run_id": 1}]
            )
