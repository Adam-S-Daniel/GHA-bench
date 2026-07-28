#!/usr/bin/env python3
"""
Test suite for the environment matrix generator.

Uses red/green TDD methodology:
1. Write a failing test first
2. Write minimum code to make it pass
3. Refactor if needed
4. Repeat for each piece of functionality
"""

import json
try:
    import pytest
    HAS_PYTEST = True
except ImportError:
    HAS_PYTEST = False

from matrix_generator import (
    generate_matrix,
    validate_matrix_size,
    apply_include_rules,
    apply_exclude_rules,
    MatrixError,
)


class TestBasicMatrixGeneration:
    """Test suite for basic matrix generation."""

    def test_simple_matrix_generation(self):
        """Test generating a matrix from basic OS and version configs."""
        config = {
            "os": ["ubuntu-latest", "windows-latest"],
            "python-version": ["3.9", "3.10"],
        }

        matrix = generate_matrix(config)

        # Should have 2 * 2 = 4 combinations
        assert len(matrix["include"]) == 4

        # Check that all combinations exist
        combinations = [
            {"os": "ubuntu-latest", "python-version": "3.9"},
            {"os": "ubuntu-latest", "python-version": "3.10"},
            {"os": "windows-latest", "python-version": "3.9"},
            {"os": "windows-latest", "python-version": "3.10"},
        ]

        for combo in combinations:
            assert combo in matrix["include"]

    def test_empty_config(self):
        """Test that empty config produces empty matrix."""
        config = {}
        matrix = generate_matrix(config)
        assert matrix["include"] == []

    def test_single_dimension(self):
        """Test matrix with single dimension."""
        config = {
            "python-version": ["3.8", "3.9", "3.10"],
        }

        matrix = generate_matrix(config)
        assert len(matrix["include"]) == 3
        assert {"python-version": "3.8"} in matrix["include"]


class TestMatrixValidation:
    """Test suite for matrix size validation."""

    def test_validate_under_limit(self):
        """Test that matrix under max size is valid."""
        config = {
            "os": ["ubuntu-latest"],
            "python-version": ["3.9"],
        }

        matrix = generate_matrix(config)
        # Should not raise
        validate_matrix_size(matrix, max_size=10)

    def test_validate_exceeds_limit(self):
        """Test that matrix exceeding max size raises error."""
        config = {
            "os": ["ubuntu-latest", "windows-latest", "macos-latest"],
            "python-version": ["3.8", "3.9", "3.10", "3.11"],
        }

        matrix = generate_matrix(config)
        # 3 * 4 = 12 combinations > 10 max
        try:
            validate_matrix_size(matrix, max_size=10)
            assert False, "Should have raised MatrixError"
        except MatrixError as e:
            assert "exceeds maximum" in str(e)


class TestIncludeRules:
    """Test suite for include rules."""

    def test_include_adds_custom_combination(self):
        """Test that include rules add custom combinations."""
        config = {
            "os": ["ubuntu-latest"],
            "python-version": ["3.9"],
        }

        include_rules = [
            {"os": "macos-latest", "python-version": "3.9", "extra": "value"}
        ]

        matrix = generate_matrix(config)
        matrix = apply_include_rules(matrix, include_rules)

        assert {"os": "macos-latest", "python-version": "3.9", "extra": "value"} in matrix["include"]

    def test_include_multiple_rules(self):
        """Test multiple include rules."""
        config = {
            "os": ["ubuntu-latest"],
            "python-version": ["3.9"],
        }

        include_rules = [
            {"os": "windows-latest", "python-version": "3.9"},
            {"os": "macos-latest", "python-version": "3.10"},
        ]

        matrix = generate_matrix(config)
        matrix = apply_include_rules(matrix, include_rules)

        assert len(matrix["include"]) >= 3  # At least original + 2 new


class TestExcludeRules:
    """Test suite for exclude rules."""

    def test_exclude_removes_combination(self):
        """Test that exclude rules remove combinations."""
        config = {
            "os": ["ubuntu-latest", "windows-latest"],
            "python-version": ["3.9", "3.10"],
        }

        exclude_rules = [
            {"os": "windows-latest", "python-version": "3.9"}
        ]

        matrix = generate_matrix(config)
        matrix = apply_exclude_rules(matrix, exclude_rules)

        # Should have 4 - 1 = 3 combinations
        assert len(matrix["include"]) == 3
        assert {"os": "windows-latest", "python-version": "3.9"} not in matrix["include"]

    def test_exclude_multiple_rules(self):
        """Test multiple exclude rules."""
        config = {
            "os": ["ubuntu-latest", "windows-latest", "macos-latest"],
            "python-version": ["3.9", "3.10"],
        }

        exclude_rules = [
            {"os": "windows-latest", "python-version": "3.9"},
            {"os": "macos-latest", "python-version": "3.10"},
        ]

        matrix = generate_matrix(config)
        matrix = apply_exclude_rules(matrix, exclude_rules)

        # Should have 6 - 2 = 4 combinations
        assert len(matrix["include"]) == 4


class TestFailFastAndMaxParallel:
    """Test suite for fail-fast and max-parallel configuration."""

    def test_fail_fast_configuration(self):
        """Test that fail-fast setting is applied to matrix."""
        config = {
            "os": ["ubuntu-latest"],
            "python-version": ["3.9"],
        }

        matrix = generate_matrix(config, fail_fast=True)
        assert matrix.get("fail-fast") is True

    def test_max_parallel_configuration(self):
        """Test that max-parallel setting is applied to matrix."""
        config = {
            "os": ["ubuntu-latest"],
            "python-version": ["3.9"],
        }

        matrix = generate_matrix(config, max_parallel=2)
        assert matrix.get("max-parallel") == 2


class TestJSONOutput:
    """Test suite for JSON output format."""

    def test_output_is_valid_json(self):
        """Test that generated matrix is valid JSON-serializable."""
        config = {
            "os": ["ubuntu-latest"],
            "python-version": ["3.9"],
        }

        matrix = generate_matrix(config)

        # Should not raise
        json_str = json.dumps(matrix)
        assert isinstance(json_str, str)

        # Should be re-parseable
        parsed = json.loads(json_str)
        assert parsed == matrix

    def test_matrix_structure(self):
        """Test that matrix has expected GitHub Actions structure."""
        config = {
            "os": ["ubuntu-latest"],
            "python-version": ["3.9"],
        }

        matrix = generate_matrix(config)

        # Must have 'include' key
        assert "include" in matrix
        assert isinstance(matrix["include"], list)

        # Include entries must be dicts
        for entry in matrix["include"]:
            assert isinstance(entry, dict)


class TestErrorHandling:
    """Test suite for error handling."""

    def test_invalid_config_raises_error(self):
        """Test that invalid config raises meaningful error."""
        config = "not a dict"

        try:
            generate_matrix(config)
            assert False, "Should have raised MatrixError or TypeError"
        except (MatrixError, TypeError):
            pass  # Expected

    def test_duplicate_entries_handled(self):
        """Test that duplicate matrix entries are deduplicated."""
        config = {
            "os": ["ubuntu-latest"],
            "python-version": ["3.9"],
        }

        include_rules = [
            {"os": "ubuntu-latest", "python-version": "3.9"}
        ]

        matrix = generate_matrix(config)
        matrix = apply_include_rules(matrix, include_rules)

        # Should not have duplicates
        include_set = [json.dumps(entry, sort_keys=True) for entry in matrix["include"]]
        assert len(include_set) == len(set(include_set))


class TestComplexScenarios:
    """Test suite for complex real-world scenarios."""

    def test_github_actions_matrix_scenario(self):
        """Test a realistic GitHub Actions matrix scenario."""
        config = {
            "os": ["ubuntu-latest", "windows-latest"],
            "node-version": ["16", "18", "20"],
            "include-experimental": [False],
        }

        include_rules = [
            {"os": "macos-latest", "node-version": "18", "include-experimental": True}
        ]

        exclude_rules = [
            {"os": "windows-latest", "node-version": "16"}
        ]

        matrix = generate_matrix(config, max_parallel=4, fail_fast=False)
        matrix = apply_include_rules(matrix, include_rules)
        matrix = apply_exclude_rules(matrix, exclude_rules)

        # 2 * 3 - 1 + 1 = 6 combinations
        assert len(matrix["include"]) == 6
        assert matrix.get("max-parallel") == 4
        assert matrix.get("fail-fast") is False


def run_tests_directly():
    """Run tests without pytest framework - basic test runner."""
    import sys

    test_classes = [
        TestBasicMatrixGeneration,
        TestMatrixValidation,
        TestIncludeRules,
        TestExcludeRules,
        TestFailFastAndMaxParallel,
        TestJSONOutput,
        TestErrorHandling,
        TestComplexScenarios,
    ]

    passed = 0
    failed = 0

    for test_class in test_classes:
        instance = test_class()
        for method_name in dir(instance):
            if method_name.startswith('test_'):
                try:
                    method = getattr(instance, method_name)
                    method()
                    print(f"✓ {test_class.__name__}::{method_name}")
                    passed += 1
                except Exception as e:
                    print(f"✗ {test_class.__name__}::{method_name}")
                    print(f"  Error: {e}")
                    failed += 1

    print(f"\n{passed} passed, {failed} failed")
    return failed == 0


if __name__ == "__main__":
    import sys

    # Try pytest first, fall back to direct execution
    if HAS_PYTEST:
        pytest.main([__file__, "-v"])
    else:
        success = run_tests_directly()
        sys.exit(0 if success else 1)
