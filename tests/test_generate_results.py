"""Unit tests for generate_results.py — helper functions."""

import math
import re

import pytest

from generate_results import (
    _categorize_tool_time,
    _collapsible_table,
    _compute_ratio_bands,
    _detect_traps,
    _emit_sorted_variants,
    _find_discrepancies,
    _llm_tier,
    _rank,
    _ratio_tier,
    _spearman,
    _tier_num,
    update_readme,
)


# =========================================================================
# _rank
# =========================================================================

class TestRank:
    def test_basic_ranking(self):
        assert _rank([10, 20, 30]) == [1.0, 2.0, 3.0]

    def test_reverse_order(self):
        assert _rank([30, 20, 10]) == [3.0, 2.0, 1.0]

    def test_ties_get_average_rank(self):
        # Values: [10, 20, 20, 30] -> sorted positions 1,2,3,4
        # The two 20s share positions 2 and 3 -> avg rank 2.5
        assert _rank([10, 20, 20, 30]) == [1.0, 2.5, 2.5, 4.0]

    def test_all_same(self):
        assert _rank([5, 5, 5]) == [2.0, 2.0, 2.0]

    def test_single_element(self):
        assert _rank([42]) == [1.0]

    def test_empty(self):
        assert _rank([]) == []


# =========================================================================
# _spearman
# =========================================================================

class TestSpearman:
    def test_perfect_positive(self):
        assert _spearman([1, 2, 3, 4], [10, 20, 30, 40]) == 1.0

    def test_perfect_negative(self):
        assert _spearman([1, 2, 3, 4], [40, 30, 20, 10]) == -1.0

    def test_no_correlation(self):
        # Not perfectly 0 but should be close
        r = _spearman([1, 2, 3, 4, 5], [3, 1, 4, 2, 5])
        assert r is not None
        assert -1.0 <= r <= 1.0

    def test_too_few_values(self):
        assert _spearman([1, 2], [3, 4]) is None
        assert _spearman([1], [2]) is None
        assert _spearman([], []) is None

    def test_constant_values_returns_none(self):
        # All same values -> zero variance -> None
        assert _spearman([5, 5, 5], [1, 2, 3]) is None

    def test_known_value(self):
        # rank([1,2,3,4,5]) vs rank([2,1,4,3,5]): d^2=4, rs = 1 - 6*4/120 = 0.80
        assert _spearman([1, 2, 3, 4, 5], [2, 1, 4, 3, 5]) == 0.8

    def test_mismatched_lengths(self):
        # Implementation uses zip, so shorter list determines length.
        # With only 2 pairs, should return None (< 3 elements).
        result = _spearman([1, 2, 3], [1, 2])
        # Either None (too few after zip) or a valid correlation
        assert result is None or -1.0 <= result <= 1.0


# =========================================================================
# _collapsible_table
# =========================================================================

class TestCollapsibleTable:
    def test_basic_structure(self):
        lines = _collapsible_table(
            "Click to expand",
            "| A | B |",
            "|---|---|",
            ["| 1 | 2 |", "| 3 | 4 |"],
        )
        text = "\n".join(lines)
        assert "<details>" in text
        assert "<summary>Click to expand</summary>" in text
        assert "| A | B |" in text
        assert "| 1 | 2 |" in text
        assert "</details>" in text

    def test_output_structural_order(self):
        lines = _collapsible_table(
            "My Summary", "| H1 | H2 |", "|----|-----|",
            ["| r1 | r2 |", "| r3 | r4 |"],
        )
        text = "\n".join(lines)
        for tag in ["<details>", "<summary>My Summary</summary>",
                     "| H1 | H2 |", "|----|-----|",
                     "| r1 | r2 |", "| r3 | r4 |", "</details>"]:
            assert tag in text
        # Verify ordering
        assert text.index("<details>") < text.index("<summary>")
        assert text.index("<summary>") < text.index("| H1 | H2 |")
        assert text.index("| r1 | r2 |") < text.index("</details>")

    def test_empty_rows(self):
        lines = _collapsible_table("Empty", "| H |", "|---|", [])
        text = "\n".join(lines)
        assert "<details>" in text
        assert "| H |" in text


# =========================================================================
# _categorize_tool_time
# =========================================================================

class TestCategorizeToolTime:
    def test_install_commands(self):
        tool_uses = [
            {"tool_name": "Bash", "command": "pip install requests", "duration_ms": 5000},
            {"tool_name": "Bash", "command": "apt-get install curl", "duration_ms": 3000},
        ]
        r = _categorize_tool_time(tool_uses)
        assert r["install_duration_ms"] == 8000
        assert r["test_duration_ms"] == 0
        assert r["act_duration_ms"] == 0

    def test_test_commands(self):
        tool_uses = [
            {"tool_name": "Bash", "command": "pytest test_foo.py", "duration_ms": 2000},
            {"tool_name": "Bash", "command": "Invoke-Pester", "duration_ms": 5000},
            {"tool_name": "Bash", "command": "bun test", "duration_ms": 1500},
        ]
        r = _categorize_tool_time(tool_uses)
        assert r["test_duration_ms"] == 8500
        assert r["install_duration_ms"] == 0

    def test_act_commands(self):
        tool_uses = [
            {"tool_name": "Bash", "command": "act push --rm", "duration_ms": 60000},
        ]
        r = _categorize_tool_time(tool_uses)
        assert r["act_duration_ms"] == 60000

    def test_ignores_non_bash(self):
        tool_uses = [
            {"tool_name": "Write", "command": "test_foo.py", "duration_ms": 100},
        ]
        r = _categorize_tool_time(tool_uses)
        assert r["install_duration_ms"] == 0
        assert r["test_duration_ms"] == 0

    def test_empty_list(self):
        r = _categorize_tool_time([])
        assert r["install_duration_ms"] == 0
        assert r["test_duration_ms"] == 0
        assert r["act_duration_ms"] == 0

    def test_tool_use_without_command_key(self):
        tool_uses = [
            {"tool_name": "Read", "file_path": "foo.py", "duration_ms": 100},
            {"tool_name": "Write", "duration_ms": 200},
        ]
        r = _categorize_tool_time(tool_uses)
        assert r["install_duration_ms"] == 0
        assert r["test_duration_ms"] == 0
        assert r["act_duration_ms"] == 0

    def test_act_takes_precedence_over_test(self):
        # "act push" should be categorized as act, not test
        tool_uses = [
            {"tool_name": "Bash", "command": "act push --rm 2>&1 | tee result.txt", "duration_ms": 50000},
        ]
        r = _categorize_tool_time(tool_uses)
        assert r["act_duration_ms"] == 50000
        assert r["test_duration_ms"] == 0


# =========================================================================
# _detect_traps (basic smoke tests — full coverage requires event fixtures)
# =========================================================================

class TestDetectTraps:
    def test_no_traps_in_clean_run(self):
        events = [
            {"type": "assistant", "message": {"content": [
                {"type": "tool_use", "name": "Bash", "input": {"command": "python3 app.py"}},
                {"type": "text", "text": "Running the script."},
            ]}},
        ]
        metrics = {"language_mode": "default"}
        traps = _detect_traps(events, "", metrics)
        assert traps == []

    def test_repeated_test_reruns(self):
        # Same test command 5 times -> should trigger trap
        events = [
            {"type": "assistant", "message": {"content": [
                {"type": "tool_use", "name": "Bash", "input": {"command": "pytest test_app.py"}}
            ]}}
            for _ in range(5)
        ]
        metrics = {"language_mode": "default"}
        traps = _detect_traps(events, "", metrics)
        names = [t["name"] for t in traps]
        assert "repeated-test-reruns" in names

    def test_pester_wrong_assertions(self):
        events = [
            {"type": "assistant", "message": {"content": [
                {"type": "tool_use", "name": "Bash", "input": {"command": "Invoke-Pester"}},
                {"type": "text", "text": "Should -BeInRange doesn't exist, need to fix the wrong assertion"},
            ]}},
        ]
        metrics = {"language_mode": "powershell"}
        traps = _detect_traps(events, "", metrics)
        names = [t["name"] for t in traps]
        assert "pester-wrong-assertions" in names

    def test_repeated_reruns_boundary_below_threshold(self):
        # 3 reruns should NOT trigger (threshold is 4)
        events = [
            {"type": "assistant", "message": {"content": [
                {"type": "tool_use", "name": "Bash", "input": {"command": "pytest test_app.py"}}
            ]}}
            for _ in range(3)
        ]
        metrics = {"language_mode": "default"}
        traps = _detect_traps(events, "", metrics)
        assert "repeated-test-reruns" not in [t["name"] for t in traps]

    def test_trap_payload_has_required_keys(self):
        events = [
            {"type": "assistant", "message": {"content": [
                {"type": "tool_use", "name": "Bash", "input": {"command": "pytest test_app.py"}}
            ]}}
            for _ in range(5)
        ]
        traps = _detect_traps(events, "", {"language_mode": "default"})
        for trap in traps:
            assert "name" in trap and isinstance(trap["name"], str)
            assert "time_s" in trap and isinstance(trap["time_s"], (int, float))
            assert "desc" in trap and isinstance(trap["desc"], str)

    def test_empty_events(self):
        assert _detect_traps([], "", {"language_mode": "default"}) == []

    # ── #27 fix 1: cd-prefix dedup for repeated-test-reruns ──
    _CD = ("cd /home/user/repos/GHA-bench/workspaces/2026-01-01_000000/"
           "11-some-task-name/bash-opus48-1m-medium && ")

    def _bash_events(self, commands):
        return [
            {"type": "assistant", "message": {"content": [
                {"type": "tool_use", "name": "Bash", "input": {"command": c}}
            ]}}
            for c in commands
        ]

    def test_repeated_reruns_distinct_commands_behind_cd_not_collapsed(self):
        # 5 DISTINCT test files behind the same long absolute cd-prefix. The
        # 80-char dedup key is computed AFTER stripping the cd, so these stay
        # 5 keys (count 1 each) and do NOT trip the trap (issue #27, finding 1).
        events = self._bash_events([self._CD + f"pytest test_{i}.py" for i in range(5)])
        traps = _detect_traps(events, "", {"language_mode": "default"})
        assert "repeated-test-reruns" not in [t["name"] for t in traps]

    def test_repeated_reruns_same_command_behind_cd_still_fires(self):
        # The same test command 5x (behind a cd) is genuine reruns — must fire.
        events = self._bash_events([self._CD + "pytest test_app.py"] * 5)
        traps = _detect_traps(events, "", {"language_mode": "default"})
        assert "repeated-test-reruns" in [t["name"] for t in traps]

    # ── #27 fix 2: fixture rework counts redo cycles, not references ──
    def test_fixture_rework_distinct_fixtures_created_once_not_flagged(self):
        # Writing 4 DISTINCT fixtures once each is fixture design, not rework.
        events = self._bash_events(
            [f"cat > fixtures/case_{i}.json <<'EOF'\n{{}}\nEOF" for i in range(4)])
        traps = _detect_traps(events, "", {"language_mode": "default"})
        assert "fixture-rework" not in [t["name"] for t in traps]

    def test_fixture_rework_same_fixture_rewritten_fires(self):
        # Same fixture written 3x + removed once = genuine redo cycle.
        events = self._bash_events([
            "echo '{}' > fixtures/data.json",
            "echo '{\"a\":1}' > fixtures/data.json",
            "rm fixtures/data.json",
            "echo '{\"a\":2}' > fixtures/data.json",
        ])
        traps = _detect_traps(events, "", {"language_mode": "default"})
        assert "fixture-rework" in [t["name"] for t in traps]

    # ── #27 fix 3: act-fixture-paths ignores the agent's own test output ──
    def test_act_fixture_paths_ignores_agent_validator_probe(self):
        events = [{"type": "assistant", "message": {"content": [
            {"type": "tool_use", "name": "Bash", "input": {"command": "act push"}},
            {"type": "text", "text": "copy the fixtures to the fixture path"},
        ]}}]
        # The agent's validator deliberately tests a "config not found" branch
        # with a fake input — not an act-step path failure (issue #27, finding 3).
        console = ("secret-validator.sh: error: config file not found: nope.json\n"
                   "[build/test] ❌ Failure - Main test step\n")
        traps = _detect_traps(events, console, {"language_mode": "bash"})
        assert "act-fixture-paths" not in [t["name"] for t in traps]

    def test_act_fixture_paths_real_act_failure_fires(self):
        events = [{"type": "assistant", "message": {"content": [
            {"type": "tool_use", "name": "Bash", "input": {"command": "act push"}},
            {"type": "text", "text": "the workflow copies fixtures to the fixture path"},
        ]}}]
        console = ("[build/test] ❌ Failure - Run tests\n"
                   "Error: fixtures/config.json not found inside container\n")
        traps = _detect_traps(events, console, {"language_mode": "bash"})
        assert "act-fixture-paths" in [t["name"] for t in traps]


# =========================================================================
# _disp_mode (#30: powershell + powershell-tool collapse into one display col)
# =========================================================================

def test_disp_mode_collapses_powershell_tool():
    from generate_results import _disp_mode
    assert _disp_mode("powershell-tool") == "powershell"
    assert _disp_mode("powershell") == "powershell"
    assert _disp_mode("bash") == "bash"
    assert _disp_mode("default") == "default"
    assert _disp_mode("typescript-bun") == "typescript-bun"


# =========================================================================
# _find_discrepancies
# =========================================================================

class TestFindDiscrepancies:
    def _llm(self, task="Task", mode="default", model="opus",
             cov=3, rig=3, des=3, ovr=3, summary="Good tests."):
        return {"task": task, "mode": mode, "model": model,
                "coverage": cov, "rigor": rig, "design": des,
                "overall": ovr, "summary": summary}

    def _sq(self, task="Task", mode="default", model="opus",
            tests=10, asserts=20, ratio=1.5):
        return {(task, mode, model): {
            "tests": tests, "asserts": asserts, "ratio": ratio,
        }}

    def test_no_discrepancies(self):
        llm = [self._llm(cov=3, rig=3, des=3, ovr=3)]
        sq = self._sq(tests=10, asserts=20)
        assert _find_discrepancies(llm, sq) == []

    def test_counter_gap_zero_tests_high_coverage(self):
        llm = [self._llm(cov=4)]
        sq = self._sq(tests=0, asserts=5)
        result = _find_discrepancies(llm, sq)
        gaps = [d for d in result if d["kind"] == "counter-gap"]
        assert len(gaps) >= 1
        assert any("0 tests" in d["flag"] for d in gaps)

    def test_counter_gap_zero_asserts_high_overall(self):
        llm = [self._llm(ovr=4)]
        sq = self._sq(tests=10, asserts=0)
        result = _find_discrepancies(llm, sq)
        gaps = [d for d in result if d["kind"] == "counter-gap"]
        assert len(gaps) >= 1
        assert any("0 assertions" in d["flag"] for d in gaps)

    def test_qualitative_low_rigor_many_asserts(self):
        llm = [self._llm(rig=2, summary="Tests lack edge cases.")]
        sq = self._sq(tests=15, asserts=50)
        result = _find_discrepancies(llm, sq)
        qual = [d for d in result if d["kind"] == "qualitative"]
        assert len(qual) == 1
        assert "low rigor" in qual[0]["flag"]
        assert qual[0]["justification"] == "Tests lack edge cases."

    def test_qualitative_has_justification(self):
        llm = [self._llm(rig=2, summary="No boundary tests.")]
        sq = self._sq(tests=20, asserts=45)
        result = _find_discrepancies(llm, sq)
        for d in result:
            if d["kind"] == "qualitative":
                assert d["justification"] != ""

    def test_counter_gap_has_no_justification(self):
        llm = [self._llm(ovr=4, summary="Great tests.")]
        sq = self._sq(tests=0, asserts=0)
        result = _find_discrepancies(llm, sq)
        for d in result:
            if d["kind"] == "counter-gap":
                assert d["justification"] == ""

    def test_missing_lookup_key_skipped(self):
        llm = [self._llm(task="Missing")]
        sq = self._sq(task="Other")
        assert _find_discrepancies(llm, sq) == []


# =========================================================================
# _ratio_tier — bin lower-is-better ratios (duration, cost) into A+..F
# =========================================================================

class TestRatioTier:
    def test_best_itself_is_top(self):
        # The best ratio (1.0) is always in the A+ band.
        assert _ratio_tier(1.0) == "A+"

    def test_fallback_bands_partition_into_13(self):
        # Without explicit bands, the boundary-12 anchor is 8.0: a ratio
        # of 8.0 hits the last non-F tier (D-); beyond it falls to F.
        assert _ratio_tier(1.0) == "A+"
        assert _ratio_tier(8.0) == "D-"
        assert _ratio_tier(10.0) == "F"

    def test_custom_bands_change_tiers(self):
        # 12 monotonically-increasing boundaries for 13 bands.
        bands = tuple(1.0 + 0.1 * i for i in range(1, 13))  # 1.1, 1.2, ..., 2.2
        assert _ratio_tier(1.0, bands) == "A+"
        assert _ratio_tier(1.1, bands) == "A+"   # ≤ b1
        assert _ratio_tier(1.2, bands) == "A"    # ≤ b2
        assert _ratio_tier(2.2, bands) == "D-"   # ≤ b12 (last boundary)
        assert _ratio_tier(2.3, bands) == "F"    # > b12

    def test_all_thirteen_letters_reachable(self):
        bands = tuple(1.0 + 0.5 * i for i in range(1, 13))  # 12 monotone
        seen = set()
        for r in [1.0, 1.2, 1.7, 2.2, 2.7, 3.2, 3.7, 4.2, 4.7, 5.2, 5.7, 6.2, 6.7, 100.0]:
            seen.add(_ratio_tier(r, bands))
        assert seen == {"A+", "A", "A-", "B+", "B", "B-",
                        "C+", "C", "C-", "D+", "D", "D-", "F"}


# =========================================================================
# _compute_ratio_bands — log-equal division of the best-to-worst spread
# =========================================================================

class TestComputeRatioBands:
    def test_empty_returns_unit_bands(self):
        # No data → degenerate but harmless; everything would classify as A+.
        b = _compute_ratio_bands([])
        assert len(b) == 12
        assert all(x == 1.0 for x in b)

    def test_all_equal_bands_collapse_to_one(self):
        b = _compute_ratio_bands([1.0, 1.0, 1.0])
        assert all(x == 1.0 for x in b)

    def test_wide_spread_distributes_across_A_plus_to_F(self):
        # Data matching the real campaign's cost spread: 1x -> ~7.2x.
        b = _compute_ratio_bands([1.0, 2.1, 3.1, 4.7, 7.22])
        tiers = [_ratio_tier(r, b) for r in [1.0, 2.1, 3.1, 4.7, 7.22]]
        assert tiers[0] == "A+"     # best pegged at the top
        assert tiers[-1] == "D-"    # worst lands just under the F line

    def test_returns_twelve_boundaries(self):
        b = _compute_ratio_bands([1.0, 3.0, 5.0])
        assert len(b) == 12

    def test_ordering_is_monotonic(self):
        b = _compute_ratio_bands([1.0, 3.0, 5.0])
        for i in range(len(b) - 1):
            assert b[i] < b[i + 1]

    def test_formula_matches_log_equal_anchored_at_max(self):
        # boundary_i = max_ratio^(i/12) for i in 1..12, so b12 = max_r
        # exactly — the worst observed value lands at D-, not F.
        max_r = 32.0
        b = _compute_ratio_bands([1.0, max_r])
        expected = tuple(max_r ** (i / 12) for i in range(1, 13))
        for actual, exp in zip(b, expected):
            assert abs(actual - exp) < 1e-9
        assert b[-1] == max_r


# =========================================================================
# _llm_tier — absolute 1-5 score bands split into 13 tiers
# =========================================================================

class TestLlmTier:
    def test_perfect_score_is_A_plus(self):
        assert _llm_tier(5.0) == "A+"

    def test_boundary_anchors(self):
        # Thresholds: 4.7, 4.4, 4.1, 3.8, 3.5, 3.2, 2.9, 2.6, 2.3, 2.0, 1.7, 1.4
        assert _llm_tier(4.7) == "A+"
        assert _llm_tier(4.69) == "A"
        assert _llm_tier(4.4) == "A"
        assert _llm_tier(4.1) == "A-"
        assert _llm_tier(3.8) == "B+"
        assert _llm_tier(3.5) == "B"
        assert _llm_tier(3.2) == "B-"
        assert _llm_tier(2.9) == "C+"
        assert _llm_tier(2.6) == "C"
        assert _llm_tier(2.3) == "C-"
        assert _llm_tier(2.0) == "D+"
        assert _llm_tier(1.7) == "D"
        assert _llm_tier(1.4) == "D-"
        assert _llm_tier(1.39) == "F"

    def test_minimum_is_F(self):
        assert _llm_tier(1.0) == "F"


# =========================================================================
# Display rename — `opus` / `sonnet` resolve to `opus46` / `sonnet46`
# in combined or multi-run reports so plain names aren't ambiguous
# now that 4.7 exists.
# =========================================================================

class TestDisplayRename:
    # Most `_label` calls carry a claude_code_version; keep these test
    # fixtures terse by pinning a representative value.
    CLI = "2.1.114"

    def test_combine_results_renames_legacy_opus(self):
        from combine_results import _label
        m = {"model_short": "opus", "effort_level": "medium",
             "claude_code_version": self.CLI}
        assert _label(m) == "opus46-200k-medium-cli2.1.114"

    def test_combine_results_renames_legacy_sonnet(self):
        from combine_results import _label
        # Legacy `sonnet` with null effort: the effort component is derived
        # from the CC version. 2.1.114 < 2.1.117 so the CLI default was
        # `medium` → `sonnet46-200k-medium`.
        m = {"model_short": "sonnet", "effort_level": None,
             "claude_code_version": self.CLI}
        assert _label(m) == "sonnet46-200k-medium-cli2.1.114"

    def test_combine_results_renames_haiku_adds_context(self):
        from combine_results import _label
        # Haiku 4.5 takes no effort parameter, so a null effort derives to
        # the sentinel `na` (effort-not-applicable), not a default effort.
        m = {"model_short": "haiku45", "effort_level": None,
             "claude_code_version": self.CLI}
        assert _label(m) == "haiku45-200k-na-cli2.1.114"

    def test_combine_results_leaves_explicit_names_untouched(self):
        from combine_results import _label
        # opus47-1m / sonnet46-1m / opus47-200k are already explicit about
        # model version and context — no rename should happen. CLI version
        # is still appended to all of them.
        m = {"model_short": "opus47-1m", "effort_level": "xhigh",
             "claude_code_version": self.CLI}
        assert _label(m) == "opus47-1m-xhigh-cli2.1.114"
        m = {"model_short": "sonnet46-1m", "effort_level": "medium",
             "claude_code_version": self.CLI}
        assert _label(m) == "sonnet46-1m-medium-cli2.1.114"
        m = {"model_short": "opus47-200k", "effort_level": "medium",
             "claude_code_version": self.CLI}
        assert _label(m) == "opus47-200k-medium-cli2.1.114"

    def test_combine_results_label_handles_missing_cli_version(self):
        # Old runs may lack `claude_code_version` entirely or have an empty
        # string. Both cases must produce a readable label — we don't want
        # silent merging of "unknown-version" runs into whatever CLI
        # happens to be current.
        from combine_results import _label
        # A missing/empty CC version can't be compared to 2.1.117, so the
        # legacy-effort derivation guards it as < 2.1.117 → `medium`.
        assert _label({"model_short": "sonnet", "effort_level": None}) \
            == "sonnet46-200k-medium-cliunk"
        assert _label({"model_short": "sonnet", "effort_level": None,
                       "claude_code_version": ""}) \
            == "sonnet46-200k-medium-cliunk"

    def test_combine_results_path_label_never_renames_or_appends_cli(self):
        # Filesystem subdirs keep their original plain names AND never
        # include CLI version — existing run directories were written
        # without either and migrating would rename every prior subdir.
        from combine_results import _path_label
        m = {"model_short": "opus", "effort_level": None,
             "claude_code_version": self.CLI}
        assert _path_label(m) == "opus"
        m = {"model_short": "opus47-1m", "effort_level": "medium",
             "claude_code_version": self.CLI}
        assert _path_label(m) == "opus47-1m-medium"


# =========================================================================
# _tier_num — map tier letter to numeric rank for compound sort keys
# =========================================================================

class TestTierNum:
    def test_letter_mapping(self):
        assert _tier_num("A+") == 1
        assert _tier_num("A") == 2
        assert _tier_num("A-") == 3
        assert _tier_num("B+") == 4
        assert _tier_num("B") == 5
        assert _tier_num("B-") == 6
        assert _tier_num("C+") == 7
        assert _tier_num("C") == 8
        assert _tier_num("C-") == 9
        assert _tier_num("D+") == 10
        assert _tier_num("D") == 11
        assert _tier_num("D-") == 12
        assert _tier_num("F") == 13

    def test_em_dash_sorts_last(self):
        # "—" (U+2014) is the "no data" marker and must always outrank F
        # so unranked rows sink to the bottom when sorting ascending.
        assert _tier_num("—") == 14
        assert _tier_num("—") > _tier_num("F")

    def test_unknown_defaults_to_last(self):
        # Unknown tier letters (e.g. legacy "E" from old caches) must
        # also sort last so they don't silently masquerade as a real
        # grade.
        assert _tier_num("Z") == 14
        assert _tier_num("E") == 14  # legacy letter no longer in scheme


# =========================================================================
# _emit_sorted_variants — callable sort key supports compound ordering
# =========================================================================

class TestEmitSortedVariantsCallableKey:
    def test_callable_key_enables_secondary_sort(self):
        # Two rows tie on primary axis "a" but differ on "b"; the
        # compound callable sort key must break the tie on b.
        rows = [
            {"name": "X", "a": 1, "b": 2},
            {"name": "Y", "a": 1, "b": 1},
            {"name": "Z", "a": 2, "b": 0},
        ]
        out = _emit_sorted_variants(
            "| name |", "|------|", rows,
            [("primary a then b", lambda r: (r["a"], r["b"]), False)],
            lambda r: f"| {r['name']} |",
        )
        # Expected order: Y (a=1,b=1), X (a=1,b=2), Z (a=2,b=0)
        names = [line for line in out if line.startswith("| ") and "name" not in line and "---" not in line]
        assert names == ["| Y |", "| X |", "| Z |"]

    def test_string_key_still_works(self):
        # Regression: the pre-callable behavior (plain dict-key lookup)
        # must keep working for existing callers.
        rows = [{"k": 3}, {"k": 1}, {"k": 2}]
        out = _emit_sorted_variants(
            "| k |", "|---|", rows,
            [("asc", "k", False)],
            lambda r: f"| {r['k']} |",
        )
        ks = [line for line in out if line.startswith("| ") and "k |" not in line and "---" not in line]
        assert ks == ["| 1 |", "| 2 |", "| 3 |"]


class TestSingleRunSkipsConclusionsLLM:
    """Per-run results.md files must NOT render a `## Conclusions`
    section — that prose is only produced by the combined cross-run
    report (combine_results.py). The single-run generator should also
    avoid spending tokens on the Conclusions LLM even when panel data
    is present; the Judge Consistency Summary remains.

    A prior iteration piped the speed/cost aggregate table into the
    Conclusions LLM for every per-run regen, burning ~$1 of max-effort
    Opus per run-directory with panel data. The only reader for that
    prose was the combined report — so the per-run call was pure waste.
    """

    def _mk_metric(self, task_id, mode, model, cli="2.1.114"):
        return {
            "task_id": task_id,
            "task_name": f"Task {task_id}",
            "language_mode": mode,
            "model_short": model,
            "effort_level": None,
            "claude_code_version": cli,
            "language_chosen": mode,
            "timing": {"grand_total_duration_ms": 60000, "num_turns": 10,
                       "tool_use_time_ms": 0, "overall_tool_use_time_ms": 0,
                       "slowest_tool_uses": []},
            "code_metrics": {"total_lines": 100},
            "cost": {"total_cost_usd": 1.0},
            "quality": {"error_count": 0},
            "tool_use_timing": {"slowest_tool_uses": []},
            "bash_commands": [],
            "run_success": True,
            "exit_code": 0,
        }

    def test_per_run_report_has_no_conclusions_section_and_skips_llm(self, tmp_path, monkeypatch):
        import json
        import conclusions_report
        from generate_results import generate_results_md
        # Seed a panel-quality cache file to trigger the LLM-generation
        # code path (the `has_panel_data` gate).
        run = tmp_path / "2026-04-01_000000"
        mm = [
            self._mk_metric("11-stub", "bash", "opus"),
            self._mk_metric("12-stub", "bash", "opus"),
        ]
        for m in mm:
            d = run / "tasks" / m["task_id"] / "bash-opus"
            d.mkdir(parents=True, exist_ok=True)
            (d / "metrics.json").write_text(json.dumps(m))
            (d / "test-quality-haiku45.json").write_text("{}")

        # Record every speed_cost_input value the single-run generator
        # hands to the conclusions-report layer. A single-run regen must
        # always pass None — non-None would indicate the Conclusions LLM
        # is still being invoked.
        passed_inputs = []
        def _fake_gen(results_dir, speed_cost_input=None, repo_root=None):
            passed_inputs.append(speed_cost_input)
            return {
                "conclusions": None,
                "judge_consistency_summary": {
                    "text": "**🟢 Stub JCS.**",
                    "cost_usd": 0.0, "input_tokens": 0, "output_tokens": 0,
                    "model": "test", "effort": "test", "from_cache": True,
                },
            }
        monkeypatch.setattr(conclusions_report, "generate_conclusions", _fake_gen)

        generate_results_md(run, mm, total_runs=2, run_count=2)
        text = (run / "results.md").read_text()
        # 1. No Conclusions section in the per-run body.
        assert "## Conclusions" not in text, (
            "Per-run report must not render a top-level Conclusions section"
        )
        # 2. The conclusions-report layer was called with
        #    speed_cost_input=None (Conclusions LLM short-circuits).
        assert passed_inputs, "generate_conclusions should still be called for JCS"
        assert all(v is None for v in passed_inputs), (
            f"expected every speed_cost_input=None, got {passed_inputs}"
        )
        # 3. JCS still renders in Notes.
        assert "### Judge Consistency Summary" in text


class TestSingleRunNoDuplicateRows:
    """Regression: a single run dir that used multiple CLI versions
    for the same (language, model, effort) produced apparent-duplicate
    Comparison/Tiers rows whose visible Language + Model cells were
    identical. Consolidation now pools per-CLI cmp_rows sharing the
    same display label."""

    def _mk_metric(self, task_id, mode, model, cli, cost=1.0, dur_ms=60000):
        return {
            "task_id": task_id,
            "task_name": f"Task {task_id}",
            "language_mode": mode,
            "model_short": model,
            "effort_level": None,
            "claude_code_version": cli,
            "language_chosen": mode,
            "timing": {"grand_total_duration_ms": dur_ms, "num_turns": 10,
                       "tool_use_time_ms": 0, "overall_tool_use_time_ms": 0,
                       "slowest_tool_uses": []},
            "code_metrics": {"total_lines": 100},
            "cost": {"total_cost_usd": cost},
            "quality": {"error_count": 0},
            "tool_use_timing": {"slowest_tool_uses": []},
            "bash_commands": [],
            "run_success": True,
            "exit_code": 0,
        }

    def test_multi_cli_rows_collapse_into_one(self, tmp_path):
        import json
        from generate_results import generate_results_md
        # Scaffold a run dir with two tasks, both bash/opus, two CLI versions.
        run = tmp_path / "2026-04-01_000000"
        mm = [
            self._mk_metric("11-stub", "bash", "opus", "2.1.97"),
            self._mk_metric("12-stub", "bash", "opus", "2.1.98"),
        ]
        for m in mm:
            d = run / "tasks" / m["task_id"] / "bash-opus"
            d.mkdir(parents=True, exist_ok=True)
            (d / "metrics.json").write_text(json.dumps(m))
        generate_results_md(run, mm, total_runs=2, run_count=2)
        text = (run / "results.md").read_text()
        comparison_block = text.split("## Comparison by Language/Model/Effort", 1)
        assert len(comparison_block) == 2, "Comparison section missing"
        # Grab just the primary (non-collapsible) sub-table — stop at the
        # first `<details>` block so alternate sort orders don't inflate
        # the row count.
        primary_table = comparison_block[1].split("<details>", 1)[0]
        bash_opus_rows = [
            ln for ln in primary_table.splitlines()
            if ln.startswith("| bash ") and "opus46-200k" in ln
        ]
        assert len(bash_opus_rows) == 1, (
            f"expected one consolidated row in primary Comparison table, "
            f"got {len(bash_opus_rows)}:\n" + "\n".join(bash_opus_rows)
        )


class TestConsolidateCmpRowsGeomean:
    """`_consolidate_cmp_rows` is a nested function (not exported), so it
    isn't independently testable — these tests exercise its geomean-merge
    behavior indirectly through the public `generate_results_md` entrypoint,
    the same way TestSingleRunNoDuplicateRows does (issue #33)."""

    def _mk_metric(self, task_id, mode, model, cli, cost=1.0, dur_ms=60000):
        return {
            "task_id": task_id,
            "task_name": f"Task {task_id}",
            "language_mode": mode,
            "model_short": model,
            "effort_level": None,
            "claude_code_version": cli,
            "language_chosen": mode,
            "timing": {"grand_total_duration_ms": dur_ms, "num_turns": 10,
                       "tool_use_time_ms": 0, "overall_tool_use_time_ms": 0,
                       "slowest_tool_uses": []},
            "code_metrics": {"total_lines": 100},
            "cost": {"total_cost_usd": cost},
            "quality": {"error_count": 0},
            "tool_use_timing": {"slowest_tool_uses": []},
            "bash_commands": [],
            "run_success": True,
            "exit_code": 0,
        }

    def _row_cols(self, text, mode_prefix, model_substr):
        comparison_block = text.split("## Comparison by Language/Model/Effort", 1)
        assert len(comparison_block) == 2, "Comparison section missing"
        primary_table = comparison_block[1].split("<details>", 1)[0]
        matches = [
            ln for ln in primary_table.splitlines()
            if ln.startswith(f"| {mode_prefix} ") and model_substr in ln
        ]
        assert matches, f"no row found for {mode_prefix}/{model_substr}"
        return [c.strip() for c in matches[0].strip().strip("|").split("|")]

    def test_geo_dur_and_geo_cost_are_weighted_log_pooled(self, tmp_path):
        import json
        from generate_results import generate_results_md
        # Two CLI-bucket cells sharing the display label `opus46-200k`
        # (both bash/opus), distinct durations + costs, distinct CLI
        # versions so they land in separate cmp_rows buckets pre-merge.
        run = tmp_path / "2026-04-01_000000"
        mm = [
            self._mk_metric("11-stub", "bash", "opus", "2.1.97", cost=2.0, dur_ms=30_000),
            self._mk_metric("12-stub", "bash", "opus", "2.1.98", cost=8.0, dur_ms=120_000),
        ]
        for m in mm:
            d = run / "tasks" / m["task_id"] / "bash-opus"
            d.mkdir(parents=True, exist_ok=True)
            (d / "metrics.json").write_text(json.dumps(m))
        generate_results_md(run, mm, total_runs=2, run_count=2)
        text = (run / "results.md").read_text()
        cols = self._row_cols(text, "bash", "opus46-200k")
        # Columns: Language, Model, Runs, Geo Duration, Max Duration,
        # Geo Duration Net of Traps, Avg Errors, Geo Turns, Geo Cost,
        # Total Cost, Avg Tests Quality, Avg Workflow Craft.
        assert cols[2] == "2"
        # Each CLI bucket has n=1, so its "geomean" is just its own value;
        # the pooled geomean across both buckets (weights = each bucket's
        # n) is the plain two-point geomean here.
        expected_geo_dur_s = math.exp((math.log(30.0) + math.log(120.0)) / 2)
        expected_geo_cost = math.exp((math.log(2.0) + math.log(8.0)) / 2)
        got_geo_dur_min = float(cols[3].replace("min", ""))
        assert got_geo_dur_min == pytest.approx(expected_geo_dur_s / 60, abs=0.05)
        got_geo_cost = float(cols[8].lstrip("$"))
        assert got_geo_cost == pytest.approx(expected_geo_cost, abs=0.005)

    def test_max_dur_and_n_timeout_merge_across_cli_buckets(self, tmp_path):
        import json
        from generate_results import generate_results_md
        # CLI 2.1.97 bucket: one success. CLI 2.1.98 bucket: one success
        # plus a timeout. Both buckets share the display label
        # `opus46-200k`, so consolidation must merge `max_dur` (the
        # timeout's 1800s wins), `max_dur_censored` (True — the timeout
        # holds the max), and `n_timeout` (sums to 1) across the two parts.
        run = tmp_path / "2026-04-01_000000"
        good_97 = self._mk_metric("11-stub", "bash", "opus", "2.1.97", cost=2.0, dur_ms=30_000)
        good_98 = self._mk_metric("12-stub", "bash", "opus", "2.1.98", cost=4.0, dur_ms=60_000)
        timeout_98 = dict(self._mk_metric("13-stub", "bash", "opus", "2.1.98",
                                          cost=0.0, dur_ms=1_800_000))
        timeout_98["timing"] = {**timeout_98["timing"], "num_turns": 0}
        timeout_98["run_success"] = False
        timeout_98["exit_code"] = -9
        timeout_98["failure_reason"] = "timeout"
        mm = [good_97, good_98, timeout_98]
        for m in mm:
            d = run / "tasks" / m["task_id"] / "bash-opus"
            d.mkdir(parents=True, exist_ok=True)
            (d / "metrics.json").write_text(json.dumps(m))
        generate_results_md(run, mm, total_runs=3, run_count=3)
        text = (run / "results.md").read_text()
        cols = self._row_cols(text, "bash", "opus46-200k")
        # Runs column counts only successful cells (2), not the timeout.
        assert cols[2] == "2"
        # Max Duration is the timeout's 1800s = 30.0min, `≥`-prefixed
        # since that cell is censored.
        assert cols[4] == "≥30.0min", f"expected censored max duration; row cols: {cols}"
        # Geo Duration merges with DURATION-POOL weights (n + n_timeout =
        # 1 vs 2), i.e. exp((1·ln g97 + 2·ln g98)/3) = geomean(30, 60,
        # 1800) ≈ 2.5min. Successful-only weights (1 vs 1) would give
        # ≈ 1.7min instead, so this discriminates the weight choice.
        expected_geo_dur_s = math.exp(
            (math.log(30.0) + math.log(60.0) + math.log(1800.0)) / 3
        )
        got_geo_dur_min = float(cols[3].replace("min", ""))
        assert got_geo_dur_min == pytest.approx(expected_geo_dur_s / 60, abs=0.05)


class TestUpdateReadmeIgnoresNonRunDirs:
    """update_readme scans results/ for subdirs to list in the Benchmark
    Runs table. Ancillary folders like results/analysis/ hold follow-up
    markdown, not a benchmark run, and previously slipped into the
    table as a row with `0/?` metrics and no link. Guard against that."""

    def _scaffold_repo(self, tmp_path):
        (tmp_path / "results").mkdir()
        # A plausible run dir (has tasks/ and run-manifest.json).
        run_dir = tmp_path / "results" / "2026-04-01_000000"
        (run_dir / "tasks" / "11-stub" / "bash-opus").mkdir(parents=True)
        (run_dir / "run-manifest.json").write_text(
            '{"total_runs": 1, "instructions_version": "v4", '
            '"total_cost_usd": 1.0, "started_at": "2026-04-01T00:00:00"}'
        )
        (run_dir / "tasks" / "11-stub" / "bash-opus" / "metrics.json").write_text("{}")
        (run_dir / "results.md").write_text("# stub\n")
        # A non-run ancillary dir that must NOT be listed.
        (tmp_path / "results" / "analysis").mkdir()
        (tmp_path / "results" / "analysis" / "some-writeup.md").write_text("# writeup\n")
        # Seed README.md so update_readme can splice the table in.
        (tmp_path / "README.md").write_text(
            "# Repo\n\n## Benchmark Runs\n\n"
            "<!-- BEGIN BENCHMARK RUNS -->\n"
            "<!-- END BENCHMARK RUNS -->\n"
        )

    def test_analysis_dir_excluded_from_benchmark_runs_table(self, tmp_path):
        self._scaffold_repo(tmp_path)
        update_readme(tmp_path)
        text = (tmp_path / "README.md").read_text()
        # Legitimate run is listed.
        assert "2026-04-01_000000" in text
        # Ancillary dir must not leak into the table.
        assert "analysis" not in text.split("<!-- BEGIN BENCHMARK RUNS -->", 1)[1].split("<!-- END")[0]

    def test_analysis_only_directory_produces_no_table_rows(self, tmp_path):
        # If the only subdir under results/ is ancillary, the table
        # must stay empty rather than inventing a garbage row.
        (tmp_path / "results").mkdir()
        (tmp_path / "results" / "analysis").mkdir()
        (tmp_path / "results" / "analysis" / "note.md").write_text("hi")
        (tmp_path / "README.md").write_text(
            "# Repo\n\n## Benchmark Runs\n\n"
            "<!-- BEGIN BENCHMARK RUNS -->\n"
            "<!-- END BENCHMARK RUNS -->\n"
        )
        update_readme(tmp_path)
        text = (tmp_path / "README.md").read_text()
        table_body = text.split("<!-- BEGIN BENCHMARK RUNS -->", 1)[1].split("<!-- END")[0]
        # No data row (data rows start with `| ` followed by a non-sep char).
        data_rows = [ln for ln in table_body.splitlines()
                     if ln.startswith("| ") and "---" not in ln
                     and "Run |" not in ln]
        assert data_rows == [], f"expected no data rows, got: {data_rows}"
