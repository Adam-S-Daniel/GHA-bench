"""TDD test suite for the artifact cleanup tool.

We build this up red/green: each test below was written first and watched fail
before the corresponding production code in ``artifact_cleanup.py`` was added.
The tests use small, hand-built fixtures so every expected number is obvious
and deterministic (we inject ``now`` rather than reading the wall clock).
"""

import json
from datetime import datetime, timezone

import pytest

import artifact_cleanup as ac


def dt(s: str) -> datetime:
    """Helper: parse an ISO-8601 string into a tz-aware UTC datetime."""
    return datetime.fromisoformat(s).astimezone(timezone.utc)


# ---------------------------------------------------------------------------
# Step 1: parse a single artifact from a dict (the unit of input data).
# ---------------------------------------------------------------------------
def test_artifact_from_dict_parses_fields():
    a = ac.Artifact.from_dict(
        {
            "name": "build-output",
            "size": 1024,
            "created_at": "2026-06-01T00:00:00+00:00",
            "workflow_run_id": "run-1",
        }
    )
    assert a.name == "build-output"
    assert a.size == 1024
    assert a.created_at == dt("2026-06-01T00:00:00+00:00")
    assert a.workflow_run_id == "run-1"


# ---------------------------------------------------------------------------
# Step 2: parse a retention policy. Every field is optional (None == disabled).
# ---------------------------------------------------------------------------
def test_policy_from_dict_defaults_to_disabled():
    p = ac.RetentionPolicy.from_dict({})
    assert p.max_age_days is None
    assert p.max_total_size is None
    assert p.keep_latest_n_per_workflow is None


def test_policy_from_dict_reads_all_fields():
    p = ac.RetentionPolicy.from_dict(
        {"max_age_days": 30, "max_total_size": 5000, "keep_latest_n_per_workflow": 2}
    )
    assert p.max_age_days == 30
    assert p.max_total_size == 5000
    assert p.keep_latest_n_per_workflow == 2


# ---------------------------------------------------------------------------
# Step 3: max-age policy. Artifacts strictly older than max_age_days go.
# ---------------------------------------------------------------------------
def _artifacts(*specs):
    """Build artifacts from (name, size, created_at, run_id) tuples."""
    return [
        ac.Artifact(name=n, size=s, created_at=dt(c), workflow_run_id=r)
        for (n, s, c, r) in specs
    ]


def test_max_age_deletes_only_older_than_threshold():
    now = dt("2026-06-30T00:00:00+00:00")
    arts = _artifacts(
        ("fresh", 100, "2026-06-29T00:00:00+00:00", "run-1"),   # 1 day old -> keep
        ("borderline", 100, "2026-05-31T00:00:00+00:00", "run-1"),  # exactly 30 -> keep
        ("stale", 100, "2026-05-01T00:00:00+00:00", "run-1"),   # 60 days -> delete
    )
    policy = ac.RetentionPolicy(max_age_days=30)
    plan = ac.plan_cleanup(arts, policy, now=now)

    deleted = {d.artifact.name: d.reason for d in plan.decisions if d.delete}
    assert deleted == {"stale": "max_age"}
    assert {d.artifact.name for d in plan.decisions if not d.delete} == {
        "fresh",
        "borderline",
    }


# ---------------------------------------------------------------------------
# Step 4: keep-latest-N per workflow. Per run id, keep the N newest, drop rest.
# ---------------------------------------------------------------------------
def test_keep_latest_n_per_workflow():
    now = dt("2026-07-01T00:00:00+00:00")
    arts = _artifacts(
        ("a-old", 100, "2026-06-01T00:00:00+00:00", "run-A"),
        ("a-mid", 100, "2026-06-10T00:00:00+00:00", "run-A"),
        ("a-new", 100, "2026-06-20T00:00:00+00:00", "run-A"),
        ("b-only", 100, "2026-06-05T00:00:00+00:00", "run-B"),
    )
    policy = ac.RetentionPolicy(keep_latest_n_per_workflow=2)
    plan = ac.plan_cleanup(arts, policy, now=now)

    deleted = {d.artifact.name: d.reason for d in plan.decisions if d.delete}
    # run-A keeps the 2 newest (a-new, a-mid); a-old is dropped.
    # run-B has only 1, under the limit, so it survives.
    assert deleted == {"a-old": "keep_latest_n"}


# ---------------------------------------------------------------------------
# Step 5: max total size. Drop oldest survivors until total <= cap.
# ---------------------------------------------------------------------------
def test_max_total_size_evicts_oldest_first():
    now = dt("2026-07-01T00:00:00+00:00")
    arts = _artifacts(
        ("oldest", 300, "2026-06-01T00:00:00+00:00", "run-1"),
        ("middle", 300, "2026-06-02T00:00:00+00:00", "run-1"),
        ("newest", 300, "2026-06-03T00:00:00+00:00", "run-1"),
    )
    # Total is 900, cap is 500. Evict oldest first: drop "oldest" -> 600 (still
    # over), drop "middle" -> 300 (under cap). "newest" stays.
    policy = ac.RetentionPolicy(max_total_size=500)
    plan = ac.plan_cleanup(arts, policy, now=now)

    deleted = {d.artifact.name: d.reason for d in plan.decisions if d.delete}
    assert deleted == {"oldest": "max_total_size", "middle": "max_total_size"}
    assert plan.space_reclaimed == 600


# ---------------------------------------------------------------------------
# Step 6: policies compose; reason precedence is age > keep_latest > size.
# ---------------------------------------------------------------------------
def test_policies_compose_with_precedence():
    now = dt("2026-07-01T00:00:00+00:00")
    arts = _artifacts(
        ("ancient", 100, "2026-01-01T00:00:00+00:00", "run-A"),  # age-deleted
        ("a1", 400, "2026-06-28T00:00:00+00:00", "run-A"),
        ("a2", 400, "2026-06-29T00:00:00+00:00", "run-A"),
        ("a3", 400, "2026-06-30T00:00:00+00:00", "run-A"),
    )
    policy = ac.RetentionPolicy(
        max_age_days=30, keep_latest_n_per_workflow=2, max_total_size=1000
    )
    plan = ac.plan_cleanup(arts, policy, now=now)
    deleted = {d.artifact.name: d.reason for d in plan.decisions if d.delete}
    # ancient -> max_age. Among survivors a1/a2/a3 (run-A, keep 2 newest):
    # a1 dropped by keep_latest_n. Remaining a2+a3 = 800 <= 1000, size OK.
    assert deleted == {"ancient": "max_age", "a1": "keep_latest_n"}
    assert plan.space_reclaimed == 500


# ---------------------------------------------------------------------------
# Step 7: load a config file (artifacts + policies + optional "now").
# ---------------------------------------------------------------------------
def test_load_config_from_file(tmp_path):
    cfg = {
        "now": "2026-07-01T00:00:00+00:00",
        "policies": {"max_age_days": 30},
        "artifacts": [
            {
                "name": "x",
                "size": 10,
                "created_at": "2026-06-30T00:00:00+00:00",
                "workflow_run_id": "r1",
            }
        ],
    }
    p = tmp_path / "case.json"
    p.write_text(json.dumps(cfg))
    artifacts, policy, now = ac.load_config(str(p))
    assert len(artifacts) == 1 and artifacts[0].name == "x"
    assert policy.max_age_days == 30
    assert now == dt("2026-07-01T00:00:00+00:00")


# ---------------------------------------------------------------------------
# Step 8: graceful, meaningful errors (raised as ac.CleanupError).
# ---------------------------------------------------------------------------
def test_load_config_missing_file_raises_cleanup_error():
    with pytest.raises(ac.CleanupError) as exc:
        ac.load_config("/no/such/file.json")
    assert "not found" in str(exc.value).lower()


def test_load_config_invalid_json_raises_cleanup_error(tmp_path):
    p = tmp_path / "bad.json"
    p.write_text("{ this is not json ")
    with pytest.raises(ac.CleanupError) as exc:
        ac.load_config(str(p))
    assert "invalid json" in str(exc.value).lower()


def test_load_config_missing_required_field_raises_cleanup_error(tmp_path):
    p = tmp_path / "missing.json"
    p.write_text(json.dumps({"artifacts": [{"name": "x", "size": 1}]}))
    with pytest.raises(ac.CleanupError) as exc:
        ac.load_config(str(p))
    assert "created_at" in str(exc.value)


# ---------------------------------------------------------------------------
# Step 9: rendered report carries the exact summary lines act will assert on.
# ---------------------------------------------------------------------------
def test_render_plan_contains_summary_and_mode():
    now = dt("2026-07-01T00:00:00+00:00")
    arts = _artifacts(
        ("keep-me", 100, "2026-06-30T00:00:00+00:00", "r1"),
        ("drop-me", 250, "2026-01-01T00:00:00+00:00", "r1"),
    )
    plan = ac.plan_cleanup(arts, ac.RetentionPolicy(max_age_days=30), now=now)
    text = ac.render_plan(plan, dry_run=True, now=now)

    assert "Mode: DRY-RUN" in text
    assert "Artifacts total: 2" in text
    assert "Artifacts retained: 1" in text
    assert "Artifacts deleted: 1" in text
    assert "Space reclaimed: 250 bytes" in text
    assert "DELETE  drop-me" in text
    assert "reason=max_age" in text
    assert "KEEP    keep-me" in text


def test_render_plan_live_mode_label():
    now = dt("2026-07-01T00:00:00+00:00")
    plan = ac.plan_cleanup([], ac.RetentionPolicy(), now=now)
    text = ac.render_plan(plan, dry_run=False, now=now)
    assert "Mode: LIVE" in text
    assert "Artifacts total: 0" in text


# ---------------------------------------------------------------------------
# Step 10: end-to-end CLI via main(). Exit 0 on success, prints the report.
# ---------------------------------------------------------------------------
def test_main_runs_end_to_end(tmp_path, capsys):
    cfg = {
        "now": "2026-07-01T00:00:00+00:00",
        "policies": {"max_age_days": 30},
        "artifacts": [
            {
                "name": "stale",
                "size": 999,
                "created_at": "2026-01-01T00:00:00+00:00",
                "workflow_run_id": "r1",
            }
        ],
    }
    p = tmp_path / "case.json"
    p.write_text(json.dumps(cfg))
    rc = ac.main(["--input", str(p), "--dry-run"])
    out = capsys.readouterr().out
    assert rc == 0
    assert "Artifacts deleted: 1" in out
    assert "Space reclaimed: 999 bytes" in out


def test_main_now_flag_overrides_config(tmp_path, capsys):
    cfg = {
        "now": "2026-07-01T00:00:00+00:00",
        "policies": {"max_age_days": 30},
        "artifacts": [
            {
                "name": "x",
                "size": 5,
                "created_at": "2026-06-15T00:00:00+00:00",
                "workflow_run_id": "r1",
            }
        ],
    }
    p = tmp_path / "case.json"
    p.write_text(json.dumps(cfg))
    # With now far in the future, the 2026-06-15 artifact becomes stale.
    rc = ac.main(["--input", str(p), "--now", "2027-01-01T00:00:00+00:00"])
    out = capsys.readouterr().out
    assert rc == 0
    assert "Artifacts deleted: 1" in out


def test_main_reports_error_and_nonzero_exit(tmp_path, capsys):
    rc = ac.main(["--input", "/no/such/file.json"])
    err = capsys.readouterr().err
    assert rc == 2
    assert "ERROR:" in err
    assert "not found" in err.lower()
