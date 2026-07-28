"""Test suite for environment matrix generator using TDD methodology."""

import json
import pytest
from matrix_generator import (
    generate_matrix,
    validate_matrix,
    MatrixValidationError,
    MatrixConfig,
)


class TestBasicMatrixGeneration:
    """Failing test: Generate basic matrix from simple config."""

    def test_empty_config(self):
        """Should handle empty config and raise error."""
        config = MatrixConfig(os_options=[], language_versions={}, feature_flags={})
        with pytest.raises(MatrixValidationError, match="At least one OS"):
            generate_matrix(config)

    def test_single_os_single_version(self):
        """Should generate matrix with one OS and one language version."""
        config = MatrixConfig(
            os_options=["ubuntu-latest"],
            language_versions={"python": ["3.11"]},
            feature_flags={},
        )
        matrix = generate_matrix(config)
        result = validate_matrix(matrix)

        assert len(matrix) == 1
        assert matrix[0]["os"] == "ubuntu-latest"
        assert matrix[0]["python"] == "3.11"
        assert result is True

    def test_multiple_os_multiple_versions(self):
        """Should generate cartesian product of OS and versions."""
        config = MatrixConfig(
            os_options=["ubuntu-latest", "macos-latest"],
            language_versions={"python": ["3.11", "3.12"], "node": ["18", "20"]},
            feature_flags={},
        )
        matrix = generate_matrix(config)

        # 2 OS × 2 Python × 2 Node = 8 combinations
        assert len(matrix) == 8
        os_versions = set((m["os"], m["python"], m["node"]) for m in matrix)
        assert len(os_versions) == 8  # All unique


class TestIncludeExcludeRules:
    """Test include/exclude filtering."""

    def test_exclude_specific_combination(self):
        """Should exclude specific OS/version combinations."""
        config = MatrixConfig(
            os_options=["ubuntu-latest", "windows-latest"],
            language_versions={"python": ["3.11", "3.12"]},
            feature_flags={},
            exclude=[{"os": "windows-latest", "python": "3.11"}],
        )
        matrix = generate_matrix(config)

        # 2 OS × 2 Python - 1 excluded = 3
        assert len(matrix) == 3
        for entry in matrix:
            assert not (entry["os"] == "windows-latest" and entry["python"] == "3.11")

    def test_include_only_specific_combinations(self):
        """Should respect include rules (override cartesian product)."""
        config = MatrixConfig(
            os_options=["ubuntu-latest", "macos-latest"],
            language_versions={"python": ["3.11", "3.12"]},
            feature_flags={},
            include=[
                {"os": "ubuntu-latest", "python": "3.11"},
                {"os": "macos-latest", "python": "3.12"},
            ],
        )
        matrix = generate_matrix(config)

        # Only 2 entries from include rule
        assert len(matrix) == 2
        combos = [(m["os"], m["python"]) for m in matrix]
        assert ("ubuntu-latest", "3.11") in combos
        assert ("macos-latest", "3.12") in combos

    def test_exclude_with_feature_flags(self):
        """Should support exclude rules with feature flags."""
        config = MatrixConfig(
            os_options=["ubuntu-latest"],
            language_versions={"python": ["3.11"]},
            feature_flags={"experimental": [True, False]},
            exclude=[{"experimental": True}],
        )
        matrix = generate_matrix(config)

        # Should have only 1 entry with experimental=False
        assert len(matrix) == 1
        assert matrix[0]["experimental"] is False


class TestFeatureFlags:
    """Test feature flag handling."""

    def test_boolean_feature_flags(self):
        """Should handle boolean feature flags."""
        config = MatrixConfig(
            os_options=["ubuntu-latest"],
            language_versions={"python": ["3.11"]},
            feature_flags={"debug": [True, False]},
        )
        matrix = generate_matrix(config)

        # 1 OS × 1 Python × 2 debug values = 2
        assert len(matrix) == 2
        debug_values = {m["debug"] for m in matrix}
        assert debug_values == {True, False}

    def test_string_feature_flags(self):
        """Should handle string feature flags."""
        config = MatrixConfig(
            os_options=["ubuntu-latest"],
            language_versions={"python": ["3.11"]},
            feature_flags={"optimization": ["none", "full"]},
        )
        matrix = generate_matrix(config)

        assert len(matrix) == 2
        opt_values = {m["optimization"] for m in matrix}
        assert opt_values == {"none", "full"}

    def test_multiple_feature_flags(self):
        """Should handle multiple feature flags."""
        config = MatrixConfig(
            os_options=["ubuntu-latest"],
            language_versions={"python": ["3.11"]},
            feature_flags={"debug": [True, False], "optimize": [True, False]},
        )
        matrix = generate_matrix(config)

        # 1 OS × 1 Python × 2 debug × 2 optimize = 4
        assert len(matrix) == 4


class TestMaxParallelValidation:
    """Test max parallel matrix size validation."""

    def test_matrix_within_max_parallel(self):
        """Should pass validation when under max parallel limit."""
        config = MatrixConfig(
            os_options=["ubuntu-latest"],
            language_versions={"python": ["3.11"]},
            feature_flags={},
            max_parallel=256,
        )
        matrix = generate_matrix(config)
        result = validate_matrix(matrix, max_size=256)

        assert result is True

    def test_matrix_exceeds_max_parallel(self):
        """Should raise error when matrix exceeds max parallel."""
        config = MatrixConfig(
            os_options=["ubuntu-latest", "macos-latest", "windows-latest"],
            language_versions={"python": ["3.9", "3.10", "3.11", "3.12"]},
            feature_flags={"debug": [True, False]},
        )
        matrix = generate_matrix(config)

        # 3 OS × 4 Python × 2 debug = 24 jobs
        assert len(matrix) == 24

        with pytest.raises(MatrixValidationError, match="exceeds max_size"):
            validate_matrix(matrix, max_size=10)

    def test_matrix_at_exact_max_parallel(self):
        """Should pass validation at exact max parallel boundary."""
        config = MatrixConfig(
            os_options=["ubuntu-latest", "macos-latest"],
            language_versions={"python": ["3.11", "3.12"]},
            feature_flags={},
        )
        matrix = generate_matrix(config)

        # 2 × 2 = 4 jobs
        result = validate_matrix(matrix, max_size=4)
        assert result is True


class TestMatrixSerialization:
    """Test JSON serialization for GitHub Actions."""

    def test_matrix_json_structure(self):
        """Should produce valid JSON suitable for GitHub Actions."""
        config = MatrixConfig(
            os_options=["ubuntu-latest"],
            language_versions={"python": ["3.11"]},
            feature_flags={},
        )
        matrix = generate_matrix(config)
        json_str = json.dumps(matrix)

        # Should be parseable JSON
        parsed = json.loads(json_str)
        assert isinstance(parsed, list)
        assert len(parsed) == 1

    def test_include_exclude_json_output(self):
        """Should include include/exclude rules in output if present."""
        config = MatrixConfig(
            os_options=["ubuntu-latest"],
            language_versions={"python": ["3.11", "3.12"]},
            feature_flags={},
            exclude=[{"python": "3.12"}],
        )
        matrix = generate_matrix(config)

        # All entries should exclude python 3.12
        assert all(m["python"] != "3.12" for m in matrix)


class TestFailFastConfiguration:
    """Test fail-fast configuration."""

    def test_fail_fast_true(self):
        """Should include fail-fast: true in output when set."""
        config = MatrixConfig(
            os_options=["ubuntu-latest"],
            language_versions={"python": ["3.11"]},
            feature_flags={},
            fail_fast=True,
        )
        output = generate_matrix(config, include_strategy_config=True)

        assert "strategy" in output
        assert output["strategy"]["fail-fast"] is True

    def test_fail_fast_false(self):
        """Should include fail-fast: false in output when set."""
        config = MatrixConfig(
            os_options=["ubuntu-latest"],
            language_versions={"python": ["3.11"]},
            feature_flags={},
            fail_fast=False,
        )
        output = generate_matrix(config, include_strategy_config=True)

        assert "strategy" in output
        assert output["strategy"]["fail-fast"] is False

    def test_max_parallel_in_strategy(self):
        """Should include max-parallel in strategy when set."""
        config = MatrixConfig(
            os_options=["ubuntu-latest"],
            language_versions={"python": ["3.11"]},
            feature_flags={},
            max_parallel=5,
        )
        output = generate_matrix(config, include_strategy_config=True)

        assert output["strategy"]["max-parallel"] == 5


class TestErrorHandling:
    """Test error handling and validation."""

    def test_duplicate_os_options(self):
        """Should handle duplicate OS options gracefully."""
        config = MatrixConfig(
            os_options=["ubuntu-latest", "ubuntu-latest"],
            language_versions={"python": ["3.11"]},
            feature_flags={},
        )
        matrix = generate_matrix(config)

        # Should deduplicate
        assert len(matrix) == 1

    def test_empty_language_versions(self):
        """Should require at least one language version."""
        config = MatrixConfig(
            os_options=["ubuntu-latest"],
            language_versions={},
            feature_flags={},
        )
        with pytest.raises(MatrixValidationError, match="At least one language"):
            generate_matrix(config)

    def test_invalid_exclude_rule(self):
        """Should validate exclude rules reference valid keys."""
        config = MatrixConfig(
            os_options=["ubuntu-latest"],
            language_versions={"python": ["3.11"]},
            feature_flags={},
            exclude=[{"nonexistent_key": "value"}],
        )

        # Should not crash, but key simply won't match anything
        matrix = generate_matrix(config)
        assert len(matrix) == 1


class TestComplexMatrix:
    """Test complex, realistic scenarios."""

    def test_realistic_ci_matrix(self):
        """Should generate realistic CI matrix."""
        config = MatrixConfig(
            os_options=["ubuntu-latest", "macos-latest"],
            language_versions={"python": ["3.9", "3.11", "3.12"], "node": ["18"]},
            feature_flags={"test_suite": ["unit", "integration"]},
            exclude=[
                {"os": "macos-latest", "test_suite": "integration"},
            ],
            fail_fast=False,
            max_parallel=12,
        )
        matrix = generate_matrix(config)

        # 2 OS × 3 Python × 1 Node × 2 test_suite - 3 excluded (macos+integration) = 9
        assert len(matrix) == 9
        validate_matrix(matrix, max_size=256)


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
