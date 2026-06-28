"""Red/green TDD test suite for the artifact cleanup engine.

These unit tests drive the design of ``artifact_cleanup.py``. They were written
one failing test at a time (red), followed by the minimum code to make them pass
(green), then refactored. Each test exercises a single, well-defined behaviour so
the retention policies stay independently verifiable.

A fixed ``NOW`` reference time is injected into the engine everywhere so the
"max age" policy is deterministic and never depends on the wall clock.
"""

import json
from datetime import datetime, timezone

import pytest

# The engine is pure-stdlib so this import has no third-party dependencies.
from artifact_cleanup import (
    Artifact,
    CleanupError,
    Policy,
    load_artifacts,
    load_policy,
    main,
    plan_cleanup,
    render_json,
    render_text,
    summarize,
)

# A frozen "current time" shared by every age-sensitive test.
NOW = datetime(2026, 6, 28, 12, 0, 0, tzinfo=timezone.utc)


def _artifact(name, *, days_old, size=100, run_id=1, workflow="ci"):
    """Build an Artifact created ``days_old`` days before the frozen NOW."""
    created = NOW.timestamp() - days_old * 86400
    return Artifact(
        name=name,
        size_bytes=size,
        created_at=datetime.fromtimestamp(created, tz=timezone.utc),
        run_id=run_id,
        workflow=workflow,
    )


# --- Cycle 1: max-age retention -------------------------------------------

def test_max_age_deletes_artifact_older_than_limit():
    """An artifact older than ``max_age_days`` must be marked for deletion."""
    artifacts = [_artifact("old", days_old=40)]
    policy = Policy(max_age_days=30)

    plan = plan_cleanup(artifacts, policy, now=NOW)

    deleted_names = [d.artifact.name for d in plan.deletions]
    assert deleted_names == ["old"]
    assert "max_age" in plan.deletions[0].reasons


def test_max_age_keeps_artifact_within_limit():
    """An artifact at/under the age limit must be retained."""
    artifacts = [_artifact("fresh", days_old=10)]
    policy = Policy(max_age_days=30)

    plan = plan_cleanup(artifacts, policy, now=NOW)

    assert plan.deletions == []
    assert [a.name for a in plan.retained] == ["fresh"]


# --- Cycle 2: keep-latest-N per workflow ----------------------------------

def test_keep_latest_n_per_workflow():
    """Within each workflow, only the newest N artifacts survive."""
    artifacts = [
        _artifact("ci-1", days_old=1, workflow="ci", run_id=101),
        _artifact("ci-2", days_old=2, workflow="ci", run_id=102),
        _artifact("ci-3", days_old=3, workflow="ci", run_id=103),
        _artifact("release-1", days_old=5, workflow="release", run_id=201),
    ]
    policy = Policy(keep_latest_n=2)

    plan = plan_cleanup(artifacts, policy, now=NOW)

    # ci keeps its 2 newest (ci-1, ci-2); ci-3 is dropped. release keeps its only one.
    assert sorted(a.name for a in plan.retained) == ["ci-1", "ci-2", "release-1"]
    deleted = {d.artifact.name: d.reasons for d in plan.deletions}
    assert list(deleted) == ["ci-3"]
    assert "keep_latest_n" in deleted["ci-3"]


def test_reasons_accumulate_across_policies():
    """An artifact violating two policies lists both reasons."""
    artifacts = [
        _artifact("new", days_old=1, workflow="ci", run_id=2),
        _artifact("old-and-extra", days_old=99, workflow="ci", run_id=1),
    ]
    policy = Policy(max_age_days=30, keep_latest_n=1)

    plan = plan_cleanup(artifacts, policy, now=NOW)

    deleted = {d.artifact.name: set(d.reasons) for d in plan.deletions}
    assert deleted == {"old-and-extra": {"max_age", "keep_latest_n"}}


# --- Cycle 3: max total size (evict oldest until under budget) -------------

def test_max_total_size_evicts_oldest_first():
    """When over the size budget, the oldest survivors are evicted first."""
    artifacts = [
        _artifact("a", days_old=1, size=100),
        _artifact("b", days_old=2, size=100),
        _artifact("c", days_old=3, size=100),
        _artifact("d", days_old=4, size=100),  # oldest
    ]
    policy = Policy(max_total_size_bytes=250)

    plan = plan_cleanup(artifacts, policy, now=NOW)

    # 400 total > 250 budget: evict d (->300), then c (->200) and stop.
    assert sorted(a.name for a in plan.retained) == ["a", "b"]
    deleted = {d.artifact.name: d.reasons for d in plan.deletions}
    assert set(deleted) == {"c", "d"}
    assert deleted["c"] == ["max_total_size"]


def test_max_total_size_only_counts_survivors():
    """The size budget is measured against what other policies already kept."""
    artifacts = [
        _artifact("old", days_old=99, size=1000),  # removed by max_age first
        _artifact("keep", days_old=1, size=100),
    ]
    policy = Policy(max_age_days=30, max_total_size_bytes=200)

    plan = plan_cleanup(artifacts, policy, now=NOW)

    # After max_age removes the 1000-byte artifact, survivors total 100 <= 200,
    # so the size policy evicts nothing more.
    assert [a.name for a in plan.retained] == ["keep"]
    deleted = {d.artifact.name: d.reasons for d in plan.deletions}
    assert deleted == {"old": ["max_age"]}


# --- Cycle 4: plan summary -------------------------------------------------

def test_summary_reports_counts_and_reclaimed_space():
    """The summary totals retained vs deleted counts and reclaimed bytes."""
    artifacts = [
        _artifact("a", days_old=1, size=100),
        _artifact("b", days_old=2, size=100),
        _artifact("c", days_old=3, size=100),
        _artifact("d", days_old=4, size=100),
    ]
    policy = Policy(max_total_size_bytes=250)

    plan = plan_cleanup(artifacts, policy, now=NOW)
    summary = summarize(plan)

    assert summary == {
        "total_artifacts": 4,
        "retained_count": 2,
        "deleted_count": 2,
        "total_size_bytes": 400,
        "retained_size_bytes": 200,
        "space_reclaimed_bytes": 200,
    }


def test_summary_handles_empty_plan():
    """An empty artifact list yields an all-zero summary (no crash)."""
    summary = summarize(plan_cleanup([], Policy(max_age_days=30), now=NOW))
    assert summary["total_artifacts"] == 0
    assert summary["space_reclaimed_bytes"] == 0


# --- Cycle 5: loading + error handling ------------------------------------

VALID_ARTIFACTS = [
    {
        "name": "build-output",
        "size_bytes": 1024,
        "created_at": "2026-06-01T10:00:00Z",
        "run_id": 101,
        "workflow": "ci",
    },
    {
        "name": "coverage",
        "size_bytes": 2048,
        "created_at": "2026-06-20T10:00:00Z",
        "run_id": 102,
        "workflow": "ci",
    },
]


def _write(tmp_path, name, data):
    p = tmp_path / name
    p.write_text(json.dumps(data))
    return str(p)


def test_load_artifacts_parses_metadata(tmp_path):
    arts = load_artifacts(_write(tmp_path, "a.json", VALID_ARTIFACTS))
    assert [a.name for a in arts] == ["build-output", "coverage"]
    assert arts[0].size_bytes == 1024
    assert arts[0].run_id == 101
    assert arts[0].workflow == "ci"
    # 'Z' suffix is parsed as UTC.
    assert arts[0].created_at == datetime(2026, 6, 1, 10, 0, tzinfo=timezone.utc)


def test_load_artifacts_accepts_wrapped_object(tmp_path):
    """A top-level {"artifacts": [...]} wrapper is also accepted."""
    arts = load_artifacts(_write(tmp_path, "a.json", {"artifacts": VALID_ARTIFACTS}))
    assert len(arts) == 2


def test_load_artifacts_defaults_missing_workflow(tmp_path):
    """workflow is optional (the core metadata is name/size/date/run id)."""
    data = [{"name": "x", "size_bytes": 1, "created_at": "2026-06-01", "run_id": 9}]
    arts = load_artifacts(_write(tmp_path, "a.json", data))
    assert arts[0].workflow == "default"


def test_load_artifacts_missing_required_field_raises(tmp_path):
    bad = [{"name": "x", "size_bytes": 1, "run_id": 9, "workflow": "ci"}]  # no created_at
    with pytest.raises(CleanupError) as exc:
        load_artifacts(_write(tmp_path, "bad.json", bad))
    assert "created_at" in str(exc.value)
    assert "index 0" in str(exc.value)


def test_load_artifacts_bad_date_raises(tmp_path):
    bad = [{"name": "x", "size_bytes": 1, "created_at": "not-a-date", "run_id": 9}]
    with pytest.raises(CleanupError) as exc:
        load_artifacts(_write(tmp_path, "bad.json", bad))
    assert "created_at" in str(exc.value)


def test_load_artifacts_negative_size_raises(tmp_path):
    bad = [{"name": "x", "size_bytes": -5, "created_at": "2026-06-01", "run_id": 9}]
    with pytest.raises(CleanupError) as exc:
        load_artifacts(_write(tmp_path, "bad.json", bad))
    assert "size_bytes" in str(exc.value)


def test_load_missing_file_raises_clear_error():
    with pytest.raises(CleanupError) as exc:
        load_artifacts("/no/such/file.json")
    assert "not found" in str(exc.value).lower()


def test_load_invalid_json_raises(tmp_path):
    p = tmp_path / "broken.json"
    p.write_text("{ this is not json")
    with pytest.raises(CleanupError) as exc:
        load_artifacts(str(p))
    assert "json" in str(exc.value).lower()


def test_load_policy_parses_fields(tmp_path):
    data = {"max_age_days": 30, "keep_latest_n": 3, "max_total_size_bytes": 5000}
    policy = load_policy(_write(tmp_path, "p.json", data))
    assert policy.max_age_days == 30
    assert policy.keep_latest_n == 3
    assert policy.max_total_size_bytes == 5000


def test_load_policy_negative_value_raises(tmp_path):
    with pytest.raises(CleanupError) as exc:
        load_policy(_write(tmp_path, "p.json", {"max_age_days": -1}))
    assert "max_age_days" in str(exc.value)


# --- Cycle 6: rendering, dry-run, and the CLI -----------------------------

def _sample_plan():
    artifacts = [
        _artifact("a", days_old=1, size=100),
        _artifact("b", days_old=2, size=100),
        _artifact("c", days_old=3, size=100),
        _artifact("d", days_old=4, size=100),
    ]
    return artifacts, Policy(max_total_size_bytes=250)


def _has_summary_line(text, label, value):
    """True if a line reads `<label> <value>` (any internal/edge whitespace)."""
    import re
    pat = re.compile(rf"^\s*{re.escape(label)}\s+{re.escape(str(value))}\s*$")
    return any(pat.match(line) for line in text.splitlines())


def test_render_text_has_exact_summary_and_marker():
    artifacts, policy = _sample_plan()
    plan = plan_cleanup(artifacts, policy, now=NOW)
    text = render_text(plan, summarize(plan), dry_run=True)

    assert "[DRY RUN]" in text
    assert _has_summary_line(text, "Total artifacts:", 4)
    assert _has_summary_line(text, "Retained:", 2)
    assert _has_summary_line(text, "Deleted:", 2)
    assert _has_summary_line(text, "Space reclaimed:", "200 bytes")
    # Single machine-parseable line for downstream tooling / CI assertions.
    assert "RESULT total=4 retained=2 deleted=2 reclaimed=200 retained_bytes=200 total_bytes=400" in text


def test_render_text_execute_mode_label():
    artifacts, policy = _sample_plan()
    plan = plan_cleanup(artifacts, policy, now=NOW)
    text = render_text(plan, summarize(plan), dry_run=False)
    assert "[DRY RUN]" not in text
    assert "EXECUTE" in text


def test_render_json_is_valid_and_complete():
    artifacts, policy = _sample_plan()
    plan = plan_cleanup(artifacts, policy, now=NOW)
    payload = json.loads(render_json(plan, summarize(plan), dry_run=True))

    assert payload["dry_run"] is True
    assert payload["summary"]["deleted_count"] == 2
    assert payload["summary"]["space_reclaimed_bytes"] == 200
    deleted = {d["name"]: d["reasons"] for d in payload["deletions"]}
    assert set(deleted) == {"c", "d"}
    assert deleted["c"] == ["max_total_size"]
    assert {a["name"] for a in payload["retained"]} == {"a", "b"}


def test_main_text_run_exits_zero(tmp_path, capsys):
    arts = _write(tmp_path, "arts.json", VALID_ARTIFACTS)
    pol = _write(tmp_path, "pol.json", {"keep_latest_n": 1})
    rc = main(["--artifacts", arts, "--policy", pol, "--dry-run", "--now", "2026-06-28T12:00:00Z"])
    out = capsys.readouterr().out
    assert rc == 0
    # ci keeps newest (coverage), deletes build-output -> reclaim 1024 bytes.
    assert "RESULT total=2 retained=1 deleted=1 reclaimed=1024 retained_bytes=2048 total_bytes=3072" in out
    assert "[DRY RUN]" in out


def test_main_json_format(tmp_path, capsys):
    arts = _write(tmp_path, "arts.json", VALID_ARTIFACTS)
    pol = _write(tmp_path, "pol.json", {"keep_latest_n": 1})
    rc = main(["--artifacts", arts, "--policy", pol, "--format", "json",
               "--now", "2026-06-28T12:00:00Z"])
    payload = json.loads(capsys.readouterr().out)
    assert rc == 0
    assert payload["dry_run"] is False
    assert payload["summary"]["space_reclaimed_bytes"] == 1024


def test_main_missing_file_exits_two(tmp_path, capsys):
    pol = _write(tmp_path, "pol.json", {"max_age_days": 30})
    rc = main(["--artifacts", "/nope.json", "--policy", pol])
    err = capsys.readouterr().err
    assert rc == 2
    assert "not found" in err.lower()


def test_main_writes_output_file(tmp_path, capsys):
    arts = _write(tmp_path, "arts.json", VALID_ARTIFACTS)
    pol = _write(tmp_path, "pol.json", {"keep_latest_n": 1})
    out_file = tmp_path / "plan.json"
    rc = main(["--artifacts", arts, "--policy", pol, "--format", "json",
               "--output", str(out_file), "--now", "2026-06-28T12:00:00Z"])
    assert rc == 0
    assert json.loads(out_file.read_text())["summary"]["deleted_count"] == 1
