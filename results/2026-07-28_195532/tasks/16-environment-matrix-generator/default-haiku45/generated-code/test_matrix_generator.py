#!/usr/bin/env python3
"""
Test suite for the GitHub Actions matrix generator.
Uses red/green TDD: write failing test first, then implement.
"""

import json
import pytest
from matrix_generator import (
    generate_matrix,
    MatrixConfig,
    MatrixGenerationError,
)


class TestBasicMatrixGeneration:
    """Test basic matrix generation from configuration."""

    def test_empty_config_raises_error(self):
        """Empty configuration should raise an error."""
        config = MatrixConfig(os_options=[], language_versions={}, feature_flags={})
        with pytest.raises(MatrixGenerationError):
            generate_matrix(config)

    def test_single_os_single_language(self):
        """Generate matrix with one OS and one language."""
        config = MatrixConfig(
            os_options=["ubuntu-latest"],
            language_versions={"python": ["3.11"]},
            feature_flags={},
        )
        matrix = generate_matrix(config)

        assert len(matrix["include"]) == 1
        assert matrix["include"][0]["os"] == "ubuntu-latest"
        assert matrix["include"][0]["python"] == "3.11"

    def test_multiple_os_multiple_languages(self):
        """Generate matrix with multiple OS and language versions."""
        config = MatrixConfig(
            os_options=["ubuntu-latest", "macos-latest"],
            language_versions={"python": ["3.11", "3.12"], "node": ["18", "20"]},
            feature_flags={},
        )
        matrix = generate_matrix(config)

        # Should have 2 OS × (2 Python + 2 Node) = 8 combinations
        assert len(matrix["include"]) == 8

        # Check that all combinations exist
        os_set = {item["os"] for item in matrix["include"]}
        assert os_set == {"ubuntu-latest", "macos-latest"}


class TestIncludeRules:
    """Test include rules for adding specific matrix combinations."""

    def test_include_specific_combination(self):
        """Include rules should add specific combinations."""
        config = MatrixConfig(
            os_options=["ubuntu-latest"],
            language_versions={"python": ["3.11"]},
            feature_flags={},
            include=[{"os": "ubuntu-latest", "python": "3.11", "special": "true"}],
        )
        matrix = generate_matrix(config)

        assert len(matrix["include"]) >= 1
        # The included item with special flag should exist
        assert any(item.get("special") == "true" for item in matrix["include"])


class TestExcludeRules:
    """Test exclude rules for removing specific matrix combinations."""

    def test_exclude_combination(self):
        """Exclude rules should remove specific combinations."""
        config = MatrixConfig(
            os_options=["ubuntu-latest", "macos-latest"],
            language_versions={"python": ["3.11", "3.12"]},
            feature_flags={},
            exclude=[{"os": "macos-latest", "python": "3.12"}],
        )
        matrix = generate_matrix(config)

        # Should have 4 combos - 1 excluded = 3
        assert len(matrix["include"]) == 3
        # The excluded combination should not exist
        assert not any(
            item["os"] == "macos-latest" and item["python"] == "3.12"
            for item in matrix["include"]
        )


class TestMaxParallel:
    """Test max-parallel limit enforcement."""

    def test_max_parallel_limits_matrix_size(self):
        """max_parallel should limit the matrix size."""
        config = MatrixConfig(
            os_options=["ubuntu-latest", "macos-latest", "windows-latest"],
            language_versions={"python": ["3.11", "3.12", "3.13"]},
            feature_flags={},
            max_parallel=5,
        )
        matrix = generate_matrix(config)

        # Original size would be 3 × 3 = 9, but max_parallel=5
        assert len(matrix["include"]) <= 5

    def test_max_parallel_disabled_with_zero(self):
        """max_parallel=0 should disable the limit."""
        config = MatrixConfig(
            os_options=["ubuntu-latest", "macos-latest"],
            language_versions={"python": ["3.11", "3.12"]},
            feature_flags={},
            max_parallel=0,
        )
        matrix = generate_matrix(config)

        # No limit: 2 × 2 = 4
        assert len(matrix["include"]) == 4


class TestFailFast:
    """Test fail-fast configuration."""

    def test_fail_fast_enabled(self):
        """fail_fast=True should be set in the matrix."""
        config = MatrixConfig(
            os_options=["ubuntu-latest"],
            language_versions={"python": ["3.11"]},
            feature_flags={},
            fail_fast=True,
        )
        matrix = generate_matrix(config)

        assert matrix.get("fail-fast") is True

    def test_fail_fast_disabled(self):
        """fail_fast=False should be set in the matrix."""
        config = MatrixConfig(
            os_options=["ubuntu-latest"],
            language_versions={"python": ["3.11"]},
            feature_flags={},
            fail_fast=False,
        )
        matrix = generate_matrix(config)

        assert matrix.get("fail-fast") is False


class TestFeatureFlags:
    """Test feature flags in matrix variables."""

    def test_feature_flags_included(self):
        """Feature flags should be included in each matrix item."""
        config = MatrixConfig(
            os_options=["ubuntu-latest"],
            language_versions={"python": ["3.11"]},
            feature_flags={"experimental": True, "debug": False},
        )
        matrix = generate_matrix(config)

        item = matrix["include"][0]
        assert item.get("experimental") is True
        assert item.get("debug") is False


class TestMatrixValidation:
    """Test matrix validation and size constraints."""

    def test_matrix_size_validation(self):
        """Matrix should validate max_size is positive."""
        config = MatrixConfig(
            os_options=["ubuntu-latest"],
            language_versions={"python": ["3.11"]},
            feature_flags={},
            max_size=-1,  # Negative max_size should fail
        )
        with pytest.raises(MatrixGenerationError):
            generate_matrix(config)

    def test_matrix_exceeds_max_size(self):
        """Matrix should raise error if it exceeds max_size."""
        config = MatrixConfig(
            os_options=["ubuntu-latest", "macos-latest", "windows-latest"],
            language_versions={"python": ["3.11", "3.12", "3.13", "3.14"]},
            feature_flags={},
            max_size=5,  # 3×4=12 exceeds this
        )
        with pytest.raises(MatrixGenerationError):
            generate_matrix(config)


class TestMatrixJsonOutput:
    """Test JSON serialization of the matrix."""

    def test_matrix_is_json_serializable(self):
        """Generated matrix should be JSON serializable."""
        config = MatrixConfig(
            os_options=["ubuntu-latest"],
            language_versions={"python": ["3.11"]},
            feature_flags={"debug": True},
        )
        matrix = generate_matrix(config)

        # Should not raise
        json_str = json.dumps(matrix)
        assert len(json_str) > 0

        # Should deserialize back
        deserialized = json.loads(json_str)
        assert deserialized == matrix


class TestComplexScenario:
    """Test a realistic complex scenario."""

    def test_realistic_github_actions_matrix(self):
        """Test a realistic GitHub Actions matrix configuration."""
        config = MatrixConfig(
            os_options=["ubuntu-latest", "macos-latest", "windows-latest"],
            language_versions={
                "python": ["3.11", "3.12"],
                "node": ["18", "20"],
                "rust": ["1.75"],
            },
            feature_flags={"experimental": False, "security": True},
            include=[{"os": "ubuntu-latest", "python": "3.11", "coverage": True}],
            exclude=[{"os": "windows-latest", "rust": "1.75"}],
            max_parallel=8,
            max_size=50,
            fail_fast=False,
        )

        matrix = generate_matrix(config)

        # Basic structure checks
        assert "include" in matrix
        assert isinstance(matrix["include"], list)
        assert len(matrix["include"]) > 0
        assert len(matrix["include"]) <= 50
        assert matrix.get("fail-fast") is False

        # All items should have required fields
        for item in matrix["include"]:
            assert "os" in item
            # At least one language version
            has_lang = any(lang in item for lang in ["python", "node", "rust"])
            assert has_lang
            # Feature flags should be present
            assert item.get("security") is True


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
