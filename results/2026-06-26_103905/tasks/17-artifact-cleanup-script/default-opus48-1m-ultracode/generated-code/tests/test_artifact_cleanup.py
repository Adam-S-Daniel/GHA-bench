"""
Unit tests for the artifact cleanup tool (red/green TDD).

Each test below was written *before* the corresponding implementation in
``artifact_cleanup.py`` and run to confirm it failed (red) prior to writing the
minimum code to make it pass (green). The history of cycles is documented in the
section comments.

The tests exercise the pure logic of the tool in isolation (no GitHub API, no
network) using small, hand-computed fixtures so every expected value is known.
Integration with the GitHub Actions pipeline (via ``act``) lives in
``tests/test_workflow_act.py``.
"""

from datetime import datetime, timezone

import pytest

# Import the module under test. On the first run this import fails (red) because
# the module does not yet exist.
import artifact_cleanup as ac


def _dt(s: str) -> datetime:
    """Helper: parse an ISO date into an aware UTC datetime for assertions."""
    return ac.parse_timestamp(s)


# ---------------------------------------------------------------------------
# Cycle 1: parse a raw artifact dict into a typed Artifact.
# ---------------------------------------------------------------------------
def test_parse_artifact_reads_all_fields():
    raw = {
        "name": "build-output",
        "size": 2048,
        "created_at": "2026-06-01T12:00:00Z",
        "workflow_run_id": "ci-100",
    }
    art = ac.parse_artifact(raw)
    assert art.name == "build-output"
    assert art.size == 2048
    assert art.workflow_run_id == "ci-100"
    assert art.created_at == datetime(2026, 6, 1, 12, 0, 0, tzinfo=timezone.utc)


# ---------------------------------------------------------------------------
# Cycle 2: graceful, meaningful errors on malformed input.
# ---------------------------------------------------------------------------
def test_parse_artifact_missing_field_reports_which():
    raw = {"name": "x", "size": 1, "created_at": "2026-06-01T00:00:00Z"}
    with pytest.raises(ac.CleanupError) as exc:
        ac.parse_artifact(raw)
    # The message must name the missing field so a user can fix the data.
    assert "workflow_run_id" in str(exc.value)


def test_parse_artifact_rejects_negative_size():
    raw = {
        "name": "x",
        "size": -5,
        "created_at": "2026-06-01T00:00:00Z",
        "workflow_run_id": "r1",
    }
    with pytest.raises(ac.CleanupError) as exc:
        ac.parse_artifact(raw)
    assert "size" in str(exc.value)


def test_parse_timestamp_rejects_garbage():
    with pytest.raises(ac.CleanupError):
        ac.parse_timestamp("not-a-date")


def test_load_artifacts_indexes_errors():
    raws = [
        {"name": "ok", "size": 1, "created_at": "2026-06-01T00:00:00Z", "workflow_run_id": "r"},
        {"name": "bad", "size": 1, "created_at": "nope", "workflow_run_id": "r"},
    ]
    with pytest.raises(ac.CleanupError) as exc:
        ac.load_artifacts(raws)
    # Errors are reported with the offending index for quick diagnosis.
    assert "index 1" in str(exc.value)


# ---------------------------------------------------------------------------
# Cycle 3: the retention-policy engine (build_plan).
#
# A reference "now" is fixed so age math is deterministic.
# ---------------------------------------------------------------------------
NOW = ac.parse_timestamp("2026-06-28T00:00:00Z")


def _art(name, size, created, run_id):
    return ac.Artifact(name, size, ac.parse_timestamp(created), str(run_id))


def _by_name(plan):
    """Map artifact name -> Decision for convenient assertions."""
    return {d.artifact.name: d for d in plan.decisions}


def test_max_age_deletes_only_older_than_cutoff():
    # Cutoff is strictly-greater-than: an artifact exactly max_age_days old is kept.
    arts = [
        _art("old", 1000, "2026-01-15T00:00:00Z", "r1"),    # ~5 months -> delete
        _art("boundary", 500, "2026-05-29T00:00:00Z", "r1"),  # exactly 30d -> keep
        _art("fresh", 4000, "2026-06-27T00:00:00Z", "r1"),   # 1d -> keep
    ]
    policy = ac.RetentionPolicy(max_age_days=30)
    plan = ac.build_plan(arts, policy, NOW)
    d = _by_name(plan)
    assert d["old"].keep is False
    assert "max-age" in d["old"].reasons
    assert d["boundary"].keep is True
    assert d["fresh"].keep is True
    assert plan.space_reclaimed == 1000


def test_keep_latest_n_per_workflow_run():
    # Group ci-100 has 3 artifacts (keep newest 2); ci-200 has 2 (keep both).
    arts = [
        _art("c100-a", 100, "2026-06-01T00:00:00Z", "ci-100"),  # oldest -> delete
        _art("c100-b", 200, "2026-06-10T00:00:00Z", "ci-100"),
        _art("c100-c", 300, "2026-06-20T00:00:00Z", "ci-100"),
        _art("c200-a", 400, "2026-05-01T00:00:00Z", "ci-200"),
        _art("c200-b", 500, "2026-06-25T00:00:00Z", "ci-200"),
    ]
    policy = ac.RetentionPolicy(keep_latest_n=2)
    plan = ac.build_plan(arts, policy, NOW)
    d = _by_name(plan)
    assert d["c100-a"].keep is False
    assert "keep-latest-n" in d["c100-a"].reasons
    assert d["c100-b"].keep is True
    assert d["c100-c"].keep is True
    assert d["c200-a"].keep is True  # only 2 in group -> both survive
    assert d["c200-b"].keep is True
    assert plan.space_reclaimed == 100
    assert len(plan.deleted) == 1
    assert len(plan.retained) == 4


def test_max_total_size_evicts_oldest_until_under_budget():
    arts = [
        _art("s1", 600, "2026-01-01T00:00:00Z", "r1"),  # oldest, evicted first
        _art("s2", 600, "2026-02-01T00:00:00Z", "r2"),
        _art("s3", 600, "2026-03-01T00:00:00Z", "r3"),
        _art("s4", 600, "2026-04-01T00:00:00Z", "r4"),  # newest, survives
    ]
    policy = ac.RetentionPolicy(max_total_size=1000)
    plan = ac.build_plan(arts, policy, NOW)
    d = _by_name(plan)
    assert [a.artifact.name for a in plan.deleted] == ["s1", "s2", "s3"]
    assert "max-total-size" in d["s1"].reasons
    assert d["s4"].keep is True
    assert plan.space_reclaimed == 1800
    assert plan.retained_size == 600


def test_combined_policies_accumulate_reasons():
    # build group: 3 artifacts; test group: 4 artifacts. keep_latest_n=2.
    # max_age_days=30 also flags build-old; max_total_size=1500 then evicts the
    # oldest still-retained artifact (build-mid).
    arts = [
        _art("build-old", 500, "2026-01-01T00:00:00Z", "build"),  # age + keep-n
        _art("build-mid", 500, "2026-06-10T00:00:00Z", "build"),  # evicted by size
        _art("build-new", 500, "2026-06-20T00:00:00Z", "build"),  # kept
        _art("test-1", 400, "2026-06-21T00:00:00Z", "test"),      # keep-n
        _art("test-2", 400, "2026-06-22T00:00:00Z", "test"),      # keep-n
        _art("test-3", 400, "2026-06-23T00:00:00Z", "test"),      # kept
        _art("test-4", 400, "2026-06-24T00:00:00Z", "test"),      # kept
    ]
    policy = ac.RetentionPolicy(max_age_days=30, max_total_size=1500, keep_latest_n=2)
    plan = ac.build_plan(arts, policy, NOW)
    d = _by_name(plan)
    # build-old is flagged by BOTH age and keep-latest-n.
    assert d["build-old"].keep is False
    assert set(d["build-old"].reasons) == {"max-age", "keep-latest-n"}
    assert d["build-mid"].reasons == ["max-total-size"]
    assert d["test-1"].reasons == ["keep-latest-n"]
    assert d["test-2"].reasons == ["keep-latest-n"]
    assert {a.artifact.name for a in plan.retained} == {"build-new", "test-3", "test-4"}
    assert plan.deleted_count == 4
    assert plan.retained_count == 3
    assert plan.space_reclaimed == 1800
    assert plan.retained_size == 1300


def test_empty_artifact_list_is_a_noop_plan():
    plan = ac.build_plan([], ac.RetentionPolicy(max_age_days=30), NOW)
    assert plan.deleted == []
    assert plan.retained == []
    assert plan.space_reclaimed == 0


def test_no_policies_keeps_everything():
    arts = [_art("a", 10, "2020-01-01T00:00:00Z", "r1")]
    plan = ac.build_plan(arts, ac.RetentionPolicy(), NOW)
    assert plan.deleted == []
    assert plan.retained_count == 1


# ---------------------------------------------------------------------------
# Cycle 4: summary, rendering, dry-run and the (mockable) deleter.
# ---------------------------------------------------------------------------
def _combined_plan():
    arts = [
        _art("build-old", 500, "2026-01-01T00:00:00Z", "build"),
        _art("build-mid", 500, "2026-06-10T00:00:00Z", "build"),
        _art("build-new", 500, "2026-06-20T00:00:00Z", "build"),
        _art("test-1", 400, "2026-06-21T00:00:00Z", "test"),
        _art("test-2", 400, "2026-06-22T00:00:00Z", "test"),
        _art("test-3", 400, "2026-06-23T00:00:00Z", "test"),
        _art("test-4", 400, "2026-06-24T00:00:00Z", "test"),
    ]
    policy = ac.RetentionPolicy(max_age_days=30, max_total_size=1500, keep_latest_n=2)
    return ac.build_plan(arts, policy, NOW)


def test_summarize_reports_aggregates():
    summary = ac.summarize(_combined_plan(), dry_run=True)
    assert summary["dry_run"] is True
    assert summary["total_artifacts"] == 7
    assert summary["retained_count"] == 3
    assert summary["deleted_count"] == 4
    assert summary["space_reclaimed"] == 1800
    assert summary["retained_size"] == 1300
    # Each deletion entry carries its reasons for the report.
    names = {d["name"]: d["reasons"] for d in summary["deletions"]}
    assert set(names["build-old"]) == {"max-age", "keep-latest-n"}


def test_render_text_contains_machine_readable_lines():
    text = ac.render(_combined_plan(), dry_run=True, fmt="text")
    # The act harness greps for these exact KEY=value lines.
    assert "DELETED_COUNT=4" in text
    assert "RETAINED_COUNT=3" in text
    assert "SPACE_RECLAIMED=1800" in text
    assert "DRY_RUN=true" in text


def test_render_json_is_parseable_and_exact():
    import json

    out = ac.render(_combined_plan(), dry_run=False, fmt="json")
    data = json.loads(out)
    assert data["deleted_count"] == 4
    assert data["space_reclaimed"] == 1800
    assert data["dry_run"] is False


def test_execute_deletion_dry_run_does_not_call_deleter():
    calls = []
    plan = _combined_plan()
    deleted = ac.execute_deletion(plan, dry_run=True, deleter=lambda a: calls.append(a))
    assert calls == []  # nothing actually deleted in dry-run
    assert deleted == 0


def test_execute_deletion_calls_deleter_for_each_deleted():
    calls = []
    plan = _combined_plan()
    deleted = ac.execute_deletion(plan, dry_run=False, deleter=lambda a: calls.append(a.name))
    assert deleted == 4
    assert set(calls) == {"build-old", "build-mid", "test-1", "test-2"}


def test_execute_deletion_reports_deleter_failures():
    plan = _combined_plan()

    def boom(_artifact):
        raise RuntimeError("API down")

    with pytest.raises(ac.CleanupError) as exc:
        ac.execute_deletion(plan, dry_run=False, deleter=boom)
    assert "API down" in str(exc.value)


# ---------------------------------------------------------------------------
# Cycle 5: config-file loading and the CLI entry point.
# ---------------------------------------------------------------------------
import json as _json


def _write_config(tmp_path, **overrides):
    cfg = {
        "now": "2026-06-28T00:00:00Z",
        "dry_run": True,
        "policies": {"max_age_days": 30, "keep_latest_n": 2, "max_total_size": 1500},
        "artifacts": [
            {"name": "build-old", "size": 500, "created_at": "2026-01-01T00:00:00Z", "workflow_run_id": "build"},
            {"name": "build-mid", "size": 500, "created_at": "2026-06-10T00:00:00Z", "workflow_run_id": "build"},
            {"name": "build-new", "size": 500, "created_at": "2026-06-20T00:00:00Z", "workflow_run_id": "build"},
            {"name": "test-1", "size": 400, "created_at": "2026-06-21T00:00:00Z", "workflow_run_id": "test"},
            {"name": "test-2", "size": 400, "created_at": "2026-06-22T00:00:00Z", "workflow_run_id": "test"},
            {"name": "test-3", "size": 400, "created_at": "2026-06-23T00:00:00Z", "workflow_run_id": "test"},
            {"name": "test-4", "size": 400, "created_at": "2026-06-24T00:00:00Z", "workflow_run_id": "test"},
        ],
    }
    cfg.update(overrides)
    path = tmp_path / "config.json"
    path.write_text(_json.dumps(cfg))
    return path


def test_load_input_parses_config(tmp_path):
    cfg = ac.load_input(str(_write_config(tmp_path)))
    assert cfg.dry_run is True
    assert cfg.policy.max_age_days == 30
    assert cfg.policy.keep_latest_n == 2
    assert cfg.policy.max_total_size == 1500
    assert cfg.now == NOW
    assert len(cfg.artifacts) == 7


def test_load_input_missing_file_is_meaningful():
    with pytest.raises(ac.CleanupError) as exc:
        ac.load_input("/no/such/config.json")
    assert "config.json" in str(exc.value)


def test_load_input_invalid_json(tmp_path):
    path = tmp_path / "bad.json"
    path.write_text("{not valid json")
    with pytest.raises(ac.CleanupError) as exc:
        ac.load_input(str(path))
    assert "JSON" in str(exc.value)


def test_main_prints_text_summary(tmp_path, capsys):
    rc = ac.main(["--input", str(_write_config(tmp_path)), "--format", "text"])
    out = capsys.readouterr().out
    assert rc == 0
    assert "DELETED_COUNT=4" in out
    assert "RETAINED_COUNT=3" in out
    assert "SPACE_RECLAIMED=1800" in out
    assert "DRY_RUN=true" in out


def test_main_json_format(tmp_path, capsys):
    rc = ac.main(["--input", str(_write_config(tmp_path)), "--format", "json"])
    out = capsys.readouterr().out
    assert rc == 0
    data = _json.loads(out)
    assert data["deleted_count"] == 4
    assert data["space_reclaimed"] == 1800


def test_main_missing_file_returns_nonzero(tmp_path, capsys):
    rc = ac.main(["--input", "/no/such/file.json"])
    err = capsys.readouterr().err
    assert rc != 0
    assert "Error" in err


def test_main_dry_run_can_be_disabled(tmp_path, capsys):
    # --no-dry-run flips DRY_RUN to false even though the config says true.
    rc = ac.main(["--input", str(_write_config(tmp_path)), "--no-dry-run"])
    out = capsys.readouterr().out
    assert rc == 0
    assert "DRY_RUN=false" in out
