"""Unit tests for artifact_cleanup, written test-first (red/green TDD).

Each test class below corresponds to one TDD cycle. The tests were written
before the production code they exercise, watched fail, and then made green
with the minimum implementation.
"""

import json
import os
import tempfile
import unittest
from datetime import datetime, timezone

from artifact_cleanup import (
    Artifact,
    CleanupError,
    Policy,
    build_plan,
    format_size,
    load_artifacts,
    execute_plan,
    load_policy,
    main,
    render_report,
)


class RecordingDeleter:
    """Mock deleter: records deletions, optionally failing on one name."""

    def __init__(self, fail_on=None):
        self.deleted = []
        self.fail_on = fail_on

    def delete(self, artifact):
        if artifact.name == self.fail_on:
            raise RuntimeError("boom: API rate limit")
        self.deleted.append(artifact.name)

NOW = datetime(2026, 7, 1, tzinfo=timezone.utc)


def make_artifact(name, size_mb=1, created="2026-06-30T00:00:00Z", run_id=1):
    """Test helper: build an Artifact with compact defaults."""
    return Artifact(
        name=name,
        size_bytes=size_mb * 1024 * 1024,
        created_at=datetime.fromisoformat(created.replace("Z", "+00:00")),
        workflow_run_id=run_id,
    )


def deleted_names(plan):
    return [d.artifact.name for d in plan.decisions if d.action == "delete"]


def write_json(dirpath, name, payload):
    """Test helper: write a JSON fixture file and return its path."""
    path = os.path.join(dirpath, name)
    with open(path, "w", encoding="utf-8") as fh:
        json.dump(payload, fh)
    return path


class LoadArtifactsTest(unittest.TestCase):
    """Cycle 1: parse a JSON artifact list into Artifact records."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)

    def test_loads_valid_artifact_list(self):
        path = write_json(self.tmp.name, "artifacts.json", [
            {
                "name": "build-logs",
                "size_bytes": 2097152,
                "created_at": "2026-05-01T00:00:00Z",
                "workflow_run_id": 100,
            },
        ])
        artifacts = load_artifacts(path)
        self.assertEqual(len(artifacts), 1)
        art = artifacts[0]
        self.assertIsInstance(art, Artifact)
        self.assertEqual(art.name, "build-logs")
        self.assertEqual(art.size_bytes, 2097152)
        self.assertEqual(
            art.created_at,
            datetime(2026, 5, 1, tzinfo=timezone.utc),
        )
        self.assertEqual(art.workflow_run_id, 100)

    def test_empty_list_is_allowed(self):
        path = write_json(self.tmp.name, "artifacts.json", [])
        self.assertEqual(load_artifacts(path), [])


class LoadArtifactsErrorTest(unittest.TestCase):
    """Cycle 2: invalid inputs fail with meaningful CleanupError messages."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)

    def _assert_error(self, path, fragment):
        with self.assertRaises(CleanupError) as ctx:
            load_artifacts(path)
        self.assertIn(fragment, str(ctx.exception))

    def test_missing_file(self):
        self._assert_error(os.path.join(self.tmp.name, "nope.json"), "not found")

    def test_invalid_json(self):
        path = os.path.join(self.tmp.name, "broken.json")
        with open(path, "w", encoding="utf-8") as fh:
            fh.write("{not json")
        self._assert_error(path, "not valid JSON")

    def test_top_level_must_be_a_list(self):
        path = write_json(self.tmp.name, "obj.json", {"name": "x"})
        self._assert_error(path, "JSON array")

    def test_missing_required_field(self):
        path = write_json(self.tmp.name, "missing.json", [
            {"name": "x", "size_bytes": 1, "created_at": "2026-01-01T00:00:00Z"},
        ])
        self._assert_error(path, "workflow_run_id")

    def test_bad_timestamp(self):
        path = write_json(self.tmp.name, "badts.json", [
            {"name": "x", "size_bytes": 1, "created_at": "yesterday",
             "workflow_run_id": 1},
        ])
        self._assert_error(path, "created_at")

    def test_negative_size(self):
        path = write_json(self.tmp.name, "badsize.json", [
            {"name": "x", "size_bytes": -5, "created_at": "2026-01-01T00:00:00Z",
             "workflow_run_id": 1},
        ])
        self._assert_error(path, "size_bytes")


class LoadPolicyTest(unittest.TestCase):
    """Cycle 3a: parse and validate the retention policy file."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)

    def test_loads_full_policy(self):
        path = write_json(self.tmp.name, "policy.json", {
            "max_age_days": 30,
            "keep_latest_n": 2,
            "max_total_size_bytes": 10485760,
        })
        policy = load_policy(path)
        self.assertEqual(policy, Policy(max_age_days=30, keep_latest_n=2,
                                        max_total_size_bytes=10485760))

    def test_omitted_rules_default_to_disabled(self):
        path = write_json(self.tmp.name, "policy.json", {"max_age_days": 30})
        policy = load_policy(path)
        self.assertEqual(policy.max_age_days, 30)
        self.assertIsNone(policy.keep_latest_n)
        self.assertIsNone(policy.max_total_size_bytes)

    def test_negative_value_is_rejected(self):
        path = write_json(self.tmp.name, "policy.json", {"max_age_days": -1})
        with self.assertRaises(CleanupError) as ctx:
            load_policy(path)
        self.assertIn("max_age_days", str(ctx.exception))

    def test_unknown_key_is_rejected(self):
        path = write_json(self.tmp.name, "policy.json", {"max_age": 30})
        with self.assertRaises(CleanupError) as ctx:
            load_policy(path)
        self.assertIn("max_age", str(ctx.exception))


class MaxAgePolicyTest(unittest.TestCase):
    """Cycle 3b: artifacts older than max_age_days are deleted."""

    def test_old_artifact_deleted_fresh_kept(self):
        artifacts = [
            make_artifact("old", created="2026-05-01T00:00:00Z"),    # 61 days
            make_artifact("fresh", created="2026-06-20T00:00:00Z"),  # 11 days
        ]
        plan = build_plan(artifacts, Policy(max_age_days=30), now=NOW)
        self.assertEqual(deleted_names(plan), ["old"])
        delete = [d for d in plan.decisions if d.action == "delete"][0]
        self.assertEqual(
            delete.reason, "max-age: 61 days old exceeds limit of 30 days")

    def test_no_age_rule_keeps_everything(self):
        artifacts = [make_artifact("ancient", created="2020-01-01T00:00:00Z")]
        plan = build_plan(artifacts, Policy(), now=NOW)
        self.assertEqual(deleted_names(plan), [])

    def test_exactly_at_limit_is_kept(self):
        # 30 days old with a 30-day limit: only *older than* the limit goes.
        artifacts = [make_artifact("edge", created="2026-06-01T00:00:00Z")]
        plan = build_plan(artifacts, Policy(max_age_days=30), now=NOW)
        self.assertEqual(deleted_names(plan), [])


class KeepLatestPolicyTest(unittest.TestCase):
    """Cycle 4: keep only the newest N artifacts per workflow run."""

    def test_older_artifacts_beyond_n_are_deleted(self):
        artifacts = [
            make_artifact("a", created="2026-06-10T00:00:00Z", run_id=100),
            make_artifact("b", created="2026-06-15T00:00:00Z", run_id=100),
            make_artifact("c", created="2026-06-20T00:00:00Z", run_id=100),
            make_artifact("other", created="2026-06-01T00:00:00Z", run_id=200),
        ]
        plan = build_plan(artifacts, Policy(keep_latest_n=2), now=NOW)
        # Run 100 keeps its 2 newest (b, c); run 200 has only 1 artifact.
        self.assertEqual(deleted_names(plan), ["a"])
        delete = [d for d in plan.decisions if d.action == "delete"][0]
        self.assertEqual(
            delete.reason,
            "keep-latest: rank 3 of 3 in workflow run 100 exceeds "
            "keep-latest limit of 2")

    def test_max_age_reason_wins_when_both_rules_fire(self):
        # With keep_latest_n=1: "a" (rank 2, fresh) goes via keep-latest,
        # "c" (rank 3, also 91 days old) matches both rules -- the max-age
        # reason wins because rules are applied in a fixed order.
        artifacts = [
            make_artifact("a", created="2026-06-10T00:00:00Z", run_id=100),
            make_artifact("b", created="2026-06-15T00:00:00Z", run_id=100),
            make_artifact("c", created="2026-04-01T00:00:00Z", run_id=100),
        ]
        plan = build_plan(
            artifacts, Policy(max_age_days=30, keep_latest_n=1), now=NOW)
        self.assertEqual(deleted_names(plan), ["c", "a"])
        by_name = {d.artifact.name: d for d in plan.decisions}
        self.assertTrue(by_name["c"].reason.startswith("max-age:"))
        self.assertTrue(by_name["a"].reason.startswith("keep-latest:"))
        self.assertEqual(by_name["b"].action, "keep")

    def test_keep_latest_zero_deletes_all_in_run(self):
        artifacts = [make_artifact("only", run_id=5)]
        plan = build_plan(artifacts, Policy(keep_latest_n=0), now=NOW)
        self.assertEqual(deleted_names(plan), ["only"])


class MaxTotalSizePolicyTest(unittest.TestCase):
    """Cycle 5: evict oldest retained artifacts until under the size cap."""

    def test_oldest_retained_evicted_until_under_cap(self):
        artifacts = [
            make_artifact("jun15", size_mb=4, created="2026-06-15T00:00:00Z"),
            make_artifact("jun20", size_mb=1, created="2026-06-20T00:00:00Z"),
            make_artifact("jun25", size_mb=5, created="2026-06-25T00:00:00Z"),
            make_artifact("jun28", size_mb=4, created="2026-06-28T00:00:00Z"),
        ]
        # 14 MB total, 10 MB cap: evicting the oldest (jun15, 4 MB) is enough.
        cap = 10 * 1024 * 1024
        plan = build_plan(artifacts, Policy(max_total_size_bytes=cap), now=NOW)
        self.assertEqual(deleted_names(plan), ["jun15"])
        delete = [d for d in plan.decisions if d.action == "delete"][0]
        self.assertEqual(
            delete.reason,
            "max-total-size: retained total 14.00 MB exceeds limit of "
            "10.00 MB")
        self.assertEqual(plan.retained_bytes, cap)

    def test_size_rule_only_counts_artifacts_surviving_other_rules(self):
        # The huge-but-ancient artifact goes via max-age; what remains is
        # under the cap, so nothing is evicted for size.
        artifacts = [
            make_artifact("huge-old", size_mb=100, created="2026-01-01T00:00:00Z"),
            make_artifact("small-new", size_mb=1, created="2026-06-30T00:00:00Z"),
        ]
        plan = build_plan(
            artifacts,
            Policy(max_age_days=30, max_total_size_bytes=50 * 1024 * 1024),
            now=NOW)
        self.assertEqual(deleted_names(plan), ["huge-old"])
        by_name = {d.artifact.name: d for d in plan.decisions}
        self.assertTrue(by_name["huge-old"].reason.startswith("max-age:"))

    def test_under_cap_deletes_nothing(self):
        artifacts = [make_artifact("small", size_mb=1)]
        plan = build_plan(
            artifacts, Policy(max_total_size_bytes=10 * 1024 * 1024), now=NOW)
        self.assertEqual(deleted_names(plan), [])

    def test_zero_cap_deletes_everything(self):
        artifacts = [make_artifact("a"), make_artifact("b")]
        plan = build_plan(artifacts, Policy(max_total_size_bytes=0), now=NOW)
        self.assertEqual(sorted(deleted_names(plan)), ["a", "b"])


class FormatSizeTest(unittest.TestCase):
    """Cycle 6a: human-readable sizes used across the report."""

    def test_formats(self):
        self.assertEqual(format_size(0), "0 B")
        self.assertEqual(format_size(512), "512 B")
        self.assertEqual(format_size(1536), "1.50 KB")
        self.assertEqual(format_size(9 * 1024 * 1024), "9.00 MB")
        self.assertEqual(format_size(2 * 1024 ** 3), "2.00 GB")


class RenderReportTest(unittest.TestCase):
    """Cycle 6b: the deletion plan report, exactly as printed."""

    def build(self):
        artifacts = [
            make_artifact("old-logs", size_mb=2, created="2026-05-01T00:00:00Z",
                          run_id=99),
            make_artifact("fresh-build", size_mb=1, created="2026-06-20T00:00:00Z",
                          run_id=100),
        ]
        return build_plan(artifacts, Policy(max_age_days=30), now=NOW)

    def test_dry_run_report(self):
        report = render_report(self.build(), dry_run=True)
        self.assertEqual(report.splitlines(), [
            "Artifact Cleanup Plan",
            "=====================",
            "Mode: DRY RUN (no artifacts will be deleted)",
            "",
            "DELETE old-logs (2.00 MB) - max-age: 61 days old exceeds limit of 30 days",
            "KEEP   fresh-build (1.00 MB)",
            "",
            "Summary:",
            "  Total artifacts: 2",
            "  Retained:        1",
            "  Deleted:         1",
            "  Space reclaimed: 2.00 MB",
            "  Space retained:  1.00 MB",
        ])

    def test_apply_mode_header(self):
        report = render_report(self.build(), dry_run=False)
        self.assertIn("Mode: APPLY", report.splitlines())

    def test_empty_inventory_report(self):
        plan = build_plan([], Policy(max_age_days=30), now=NOW)
        report = render_report(plan, dry_run=True)
        self.assertIn("  Total artifacts: 0", report)
        self.assertIn("  Space reclaimed: 0 B", report)


class ExecutePlanTest(unittest.TestCase):
    """Cycle 7: dry-run never deletes; apply drives the deleter."""

    def build(self):
        artifacts = [
            make_artifact("stale-a", size_mb=2, created="2026-01-01T00:00:00Z"),
            make_artifact("stale-b", size_mb=3, created="2026-02-01T00:00:00Z"),
            make_artifact("fresh", size_mb=1, created="2026-06-30T00:00:00Z"),
        ]
        return build_plan(artifacts, Policy(max_age_days=30), now=NOW)

    def test_dry_run_calls_no_deleter(self):
        deleter = RecordingDeleter()
        lines = execute_plan(self.build(), deleter, dry_run=True)
        self.assertEqual(deleter.deleted, [])
        self.assertEqual(
            lines,
            ["Dry run: 2 artifact(s) would be deleted, reclaiming 5.00 MB"])

    def test_apply_deletes_oldest_first_and_summarises(self):
        deleter = RecordingDeleter()
        lines = execute_plan(self.build(), deleter, dry_run=False)
        self.assertEqual(deleter.deleted, ["stale-a", "stale-b"])
        self.assertEqual(lines, [
            "Deleting artifact 'stale-a' (workflow run 1)... deleted",
            "Deleting artifact 'stale-b' (workflow run 1)... deleted",
            "Deleted 2 artifact(s), reclaimed 5.00 MB",
        ])

    def test_apply_with_nothing_to_delete(self):
        plan = build_plan(
            [make_artifact("fresh", created="2026-06-30T00:00:00Z")],
            Policy(max_age_days=30), now=NOW)
        deleter = RecordingDeleter()
        self.assertEqual(execute_plan(plan, deleter, dry_run=False),
                         ["No artifacts to delete."])
        self.assertEqual(deleter.deleted, [])

    def test_deleter_failure_becomes_meaningful_error(self):
        deleter = RecordingDeleter(fail_on="stale-b")
        with self.assertRaises(CleanupError) as ctx:
            execute_plan(self.build(), deleter, dry_run=False)
        message = str(ctx.exception)
        self.assertIn("stale-b", message)
        self.assertIn("boom: API rate limit", message)
        # The failure happened after stale-a was already deleted.
        self.assertEqual(deleter.deleted, ["stale-a"])


class MainCliTest(unittest.TestCase):
    """Cycle 8: the command-line interface glues everything together."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.artifacts = write_json(self.tmp.name, "artifacts.json", [
            {"name": "stale-cache", "size_bytes": 5242880,
             "created_at": "2026-01-01T00:00:00Z", "workflow_run_id": 1},
            {"name": "fresh-build", "size_bytes": 1048576,
             "created_at": "2026-06-30T00:00:00Z", "workflow_run_id": 2},
        ])
        self.policy = write_json(self.tmp.name, "policy.json",
                                 {"max_age_days": 30})

    def run_main(self, *extra):
        import io
        out, err = io.StringIO(), io.StringIO()
        code = main([
            "--artifacts", self.artifacts,
            "--policy", self.policy,
            "--now", "2026-07-01T00:00:00Z",
            *extra,
        ], stdout=out, stderr=err)
        return code, out.getvalue(), err.getvalue()

    def test_dry_run_is_the_default(self):
        code, out, err = self.run_main()
        self.assertEqual(code, 0)
        self.assertEqual(err, "")
        self.assertIn("Mode: DRY RUN (no artifacts will be deleted)", out)
        self.assertIn(
            "DELETE stale-cache (5.00 MB) - max-age: 181 days old exceeds "
            "limit of 30 days", out)
        self.assertIn(
            "Dry run: 1 artifact(s) would be deleted, reclaiming 5.00 MB",
            out)

    def test_apply_mode_deletes(self):
        code, out, _ = self.run_main("--apply")
        self.assertEqual(code, 0)
        self.assertIn("Mode: APPLY", out)
        self.assertIn(
            "Deleting artifact 'stale-cache' (workflow run 1)... deleted",
            out)
        self.assertIn("Deleted 1 artifact(s), reclaimed 5.00 MB", out)

    def test_input_errors_exit_2_with_message(self):
        import io
        out, err = io.StringIO(), io.StringIO()
        code = main([
            "--artifacts", os.path.join(self.tmp.name, "missing.json"),
            "--policy", self.policy,
        ], stdout=out, stderr=err)
        self.assertEqual(code, 2)
        self.assertIn("error:", err.getvalue())
        self.assertIn("not found", err.getvalue())

    def test_invalid_now_exits_2(self):
        code, _, err = self.run_main("--now", "not-a-date")
        # run_main passed --now twice; the last one wins in argparse.
        self.assertEqual(code, 2)
        self.assertIn("--now", err)


if __name__ == "__main__":
    unittest.main()
