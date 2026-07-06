"""Unit tests for recover_cost.py — report-time timeout-cost floor recovery."""
import json
from pathlib import Path

import pytest

import recover_cost
from recover_cost import (
    normalize_model_id,
    recover_timeout_cost,
    timeout_cost_contribution,
)
from models import COST_PER_MTOK

# claude-opus-4-7 rates (models.py): input 5.0, output 25.0, cache_read 0.50,
# cache_write 6.25 — used throughout as the "known model" for hand-computed
# expected costs.
_OPUS47 = "claude-opus-4-7"
_RATES = COST_PER_MTOK[_OPUS47]


def _assistant_event(mid, model, usage, content=None):
    return {
        "type": "assistant",
        "message": {"id": mid, "model": model, "usage": usage, "content": content or []},
    }


class TestNormalizeModelId:
    def test_exact_hit(self):
        assert normalize_model_id(_OPUS47) == _OPUS47

    def test_all_known_ids_pass_through(self):
        for k in COST_PER_MTOK:
            assert normalize_model_id(k) == k

    def test_dated_suffix_strips_to_base(self):
        assert normalize_model_id("claude-haiku-4-5-20251001") == "claude-haiku-4-5"

    def test_bracket_1m_suffix_strips_to_known_base(self, monkeypatch):
        # Every real `[1m]` id in COST_PER_MTOK is already an exact key
        # (e.g. `claude-opus-4-7[1m]`), so the strip-brackets fallback
        # needs a synthetic base entry to actually exercise it.
        monkeypatch.setitem(recover_cost.COST_PER_MTOK, "claude-widget-9",
                             {"input": 1.0, "output": 1.0, "cache_read": 1.0, "cache_write": 1.0})
        assert normalize_model_id("claude-widget-9[1m]") == "claude-widget-9"

    def test_unknown_model_returns_none(self):
        assert normalize_model_id("gpt-4") is None

    def test_unknown_bracket_model_returns_none(self):
        assert normalize_model_id("claude-unknown-9[1m]") is None


class TestRecoverTimeoutCost:
    def test_missing_file_returns_none(self, tmp_path):
        assert recover_timeout_cost(tmp_path) is None

    def test_invalid_json_returns_none(self, tmp_path):
        (tmp_path / "cli-output.json").write_text("{not valid json")
        assert recover_timeout_cost(tmp_path) is None

    def test_json_object_not_list_returns_none(self, tmp_path):
        (tmp_path / "cli-output.json").write_text(json.dumps({"foo": "bar"}))
        assert recover_timeout_cost(tmp_path) is None

    def test_no_assistant_usage_returns_none(self, tmp_path):
        events = [{"type": "system"}, {"type": "user", "message": {}}]
        (tmp_path / "cli-output.json").write_text(json.dumps(events))
        assert recover_timeout_cost(tmp_path) is None

    def test_dedup_last_event_per_id_wins(self, tmp_path):
        # Two usage snapshots for the same message id: only the LAST one
        # should count, not the sum of both.
        small = {"input_tokens": 10, "cache_read_input_tokens": 0,
                  "cache_creation_input_tokens": 0, "output_tokens": 5}
        big = {"input_tokens": 1000, "cache_read_input_tokens": 200,
               "cache_creation_input_tokens": 50, "output_tokens": 300}
        events = [
            _assistant_event("m1", _OPUS47, small),
            _assistant_event("m1", _OPUS47, big),
        ]
        (tmp_path / "cli-output.json").write_text(json.dumps(events))
        expected = (1000 * _RATES["input"] + 200 * _RATES["cache_read"]
                    + 50 * _RATES["cache_write"] + 300 * _RATES["output"]) / 1e6
        assert recover_timeout_cost(tmp_path) == pytest.approx(expected)

    def test_exact_components_priced_correctly(self, tmp_path):
        usage = {"input_tokens": 1000, "cache_read_input_tokens": 2000,
                  "cache_creation_input_tokens": 500, "output_tokens": 300}
        events = [_assistant_event("m1", _OPUS47, usage)]
        (tmp_path / "cli-output.json").write_text(json.dumps(events))
        expected = (1000 * _RATES["input"] + 2000 * _RATES["cache_read"]
                    + 500 * _RATES["cache_write"] + 300 * _RATES["output"]) / 1e6
        assert recover_timeout_cost(tmp_path) == pytest.approx(expected)

    def test_output_floor_uses_chars_over_snapshot_when_larger(self, tmp_path):
        # Snapshot output_tokens is small (10); visible text is 100 chars
        # (100/4 = 25 tokens), so the chars-derived floor must win.
        usage = {"input_tokens": 0, "cache_read_input_tokens": 0,
                  "cache_creation_input_tokens": 0, "output_tokens": 10}
        text = "x" * 100
        events = [_assistant_event("m1", _OPUS47, usage, [{"type": "text", "text": text}])]
        (tmp_path / "cli-output.json").write_text(json.dumps(events))
        expected = 25 * _RATES["output"] / 1e6
        assert recover_timeout_cost(tmp_path) == pytest.approx(expected)

    def test_thinking_tokens_added_when_no_thinking_content(self, tmp_path):
        usage = {"input_tokens": 0, "cache_read_input_tokens": 0,
                  "cache_creation_input_tokens": 0, "output_tokens": 10}
        events = [
            _assistant_event("m1", _OPUS47, usage),
            {"type": "assistant", "subtype": "thinking_tokens", "estimated_tokens_delta": 1000},
        ]
        (tmp_path / "cli-output.json").write_text(json.dumps(events))
        expected = (10 + 1000) * _RATES["output"] / 1e6
        assert recover_timeout_cost(tmp_path) == pytest.approx(expected)

    def test_thinking_tokens_not_added_when_thinking_content_present(self, tmp_path):
        usage = {"input_tokens": 0, "cache_read_input_tokens": 0,
                  "cache_creation_input_tokens": 0, "output_tokens": 10}
        events = [
            _assistant_event("m1", _OPUS47, usage, [{"type": "thinking", "thinking": "hmm"}]),
            {"type": "assistant", "subtype": "thinking_tokens", "estimated_tokens_delta": 1000},
        ]
        (tmp_path / "cli-output.json").write_text(json.dumps(events))
        # "hmm" is 3 chars -> 3/4 = 0.75 tokens, still below the 10-token
        # snapshot, so out == 10 and the 1000-token thinking_est must NOT
        # be added (a thinking content block was already seen).
        expected = 10 * _RATES["output"] / 1e6
        assert recover_timeout_cost(tmp_path) == pytest.approx(expected)

    def test_unknown_model_skipped_without_crashing(self, tmp_path):
        known_usage = {"input_tokens": 100, "cache_read_input_tokens": 0,
                       "cache_creation_input_tokens": 0, "output_tokens": 500}
        unknown_usage = {"input_tokens": 999999, "cache_read_input_tokens": 0,
                         "cache_creation_input_tokens": 0, "output_tokens": 1}
        events = [
            _assistant_event("m1", _OPUS47, known_usage),
            _assistant_event("m2", "some-unreleased-model", unknown_usage),
        ]
        (tmp_path / "cli-output.json").write_text(json.dumps(events))
        expected = (100 * _RATES["input"] + 500 * _RATES["output"]) / 1e6
        assert recover_timeout_cost(tmp_path) == pytest.approx(expected)

    def test_result_event_with_positive_cost_is_a_floor_on_the_return(self, tmp_path):
        usage = {"input_tokens": 10, "cache_read_input_tokens": 0,
                  "cache_creation_input_tokens": 0, "output_tokens": 10}
        events = [
            _assistant_event("m1", _OPUS47, usage),
            {"type": "result", "total_cost_usd": 500.0},
        ]
        (tmp_path / "cli-output.json").write_text(json.dumps(events))
        assert recover_timeout_cost(tmp_path) >= 500.0


class TestTimeoutCostContribution:
    def test_recorded_cost_returned_exact_without_touching_disk(self):
        m = {"cost": {"total_cost_usd": 3.21}}
        cost, exact = timeout_cost_contribution(m, Path("/nonexistent/cell/dir"))
        assert cost == pytest.approx(3.21)
        assert exact is True

    def test_zero_recorded_and_no_stream_is_zero_and_not_exact(self, tmp_path):
        m = {"cost": {"total_cost_usd": 0.0}}
        cost, exact = timeout_cost_contribution(m, tmp_path)
        assert cost == 0.0
        assert exact is False


class TestRealArchiveRegressionGuard:
    """Locks the floor property in against the CLI's own recorded figures
    for the 3 known-cost timeout cells in the committed archive (timeouts
    whose streams happened to finish in time to emit a `result` record)."""

    _CASES = [
        ("results/2026-04-17_004319/tasks/16-environment-matrix-generator/bash-haiku45", 0.7467310000000003),
        ("results/2026-05-06_173435/tasks/12-pr-label-assigner/powershell-haiku45", 0.5113781000000001),
        ("results/2026-05-06_173435/tasks/12-pr-label-assigner/powershell-tool-opus47-1m-xhigh", 9.307997499999999),
    ]

    @pytest.mark.parametrize("rel_path,recorded", _CASES)
    def test_floor_within_range_of_recorded_cost(self, rel_path, recorded):
        repo_root = Path(__file__).parent.parent
        cell_dir = repo_root / rel_path
        if not (cell_dir / "cli-output.json").exists():
            pytest.skip(f"{cell_dir} not present in this checkout")
        floor = recover_timeout_cost(cell_dir)
        assert floor is not None
        assert 0.5 * recorded <= floor <= recorded
