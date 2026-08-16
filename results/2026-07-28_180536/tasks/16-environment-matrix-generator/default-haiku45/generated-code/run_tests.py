#!/usr/bin/env python3
"""Standalone test runner that doesn't require pytest.

This module provides basic test execution without external dependencies,
suitable for running in constrained environments like Docker containers.
"""

import sys
import json
import traceback
from matrix_generator import (
    generate_matrix,
    validate_matrix,
    load_config_from_json,
    MatrixValidationError,
    MatrixConfig,
)


class TestRunner:
    """Simple test runner without pytest dependency."""

    def __init__(self):
        self.passed = 0
        self.failed = 0
        self.errors = []

    def assert_equal(self, actual, expected, message=""):
        """Assert that actual equals expected."""
        if actual != expected:
            self.failed += 1
            self.errors.append(
                f"AssertionError: {message}\nExpected: {expected}\nActual: {actual}"
            )
            return False
        self.passed += 1
        return True

    def assert_true(self, condition, message=""):
        """Assert that condition is True."""
        if not condition:
            self.failed += 1
            self.errors.append(f"AssertionError: {message}")
            return False
        self.passed += 1
        return True

    def assert_raises(self, func, exception_type, message=""):
        """Assert that func raises exception_type."""
        try:
            func()
            self.failed += 1
            self.errors.append(f"AssertionError: Expected {exception_type.__name__} but no exception was raised. {message}")
            return False
        except exception_type:
            self.passed += 1
            return True
        except Exception as e:
            self.failed += 1
            self.errors.append(
                f"AssertionError: Expected {exception_type.__name__} but got {type(e).__name__}: {e}. {message}"
            )
            return False

    def test_basic_matrix(self):
        """Test basic matrix generation."""
        config = MatrixConfig(
            os_options=["ubuntu-latest"],
            language_versions={"python": ["3.11"]},
            feature_flags={},
        )
        matrix = generate_matrix(config)
        self.assert_equal(len(matrix), 1, "Single OS, single version should create 1 entry")

    def test_cartesian_product(self):
        """Test cartesian product generation."""
        config = MatrixConfig(
            os_options=["ubuntu-latest", "macos-latest"],
            language_versions={"python": ["3.11", "3.12"]},
            feature_flags={},
        )
        matrix = generate_matrix(config)
        self.assert_equal(len(matrix), 4, "2 OS × 2 Python should create 4 entries")

    def test_exclude_rules(self):
        """Test exclude rule filtering."""
        config = MatrixConfig(
            os_options=["ubuntu-latest", "windows-latest"],
            language_versions={"python": ["3.11", "3.12"]},
            feature_flags={},
            exclude=[{"os": "windows-latest", "python": "3.11"}],
        )
        matrix = generate_matrix(config)
        self.assert_equal(len(matrix), 3, "2 OS × 2 Python - 1 excluded should create 3 entries")

        # Verify the excluded combo is not present
        has_excluded = any(m["os"] == "windows-latest" and m["python"] == "3.11" for m in matrix)
        self.assert_true(not has_excluded, "Excluded combination should not be in matrix")

    def test_feature_flags(self):
        """Test feature flag handling."""
        config = MatrixConfig(
            os_options=["ubuntu-latest"],
            language_versions={"python": ["3.11"]},
            feature_flags={"debug": [True, False]},
        )
        matrix = generate_matrix(config)
        self.assert_equal(len(matrix), 2, "1 OS × 1 Python × 2 flags should create 2 entries")

    def test_include_rules(self):
        """Test include rule generation."""
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
        self.assert_equal(len(matrix), 2, "Include rules should create exactly 2 entries")

    def test_validation_max_size(self):
        """Test matrix size validation."""
        config = MatrixConfig(
            os_options=["ubuntu-latest", "macos-latest"],
            language_versions={"python": ["3.11", "3.12"]},
            feature_flags={},
        )
        matrix = generate_matrix(config)

        # Should pass with large max_size
        try:
            validate_matrix(matrix, max_size=256)
            self.passed += 1
        except MatrixValidationError:
            self.failed += 1
            self.errors.append("Matrix validation failed for valid size")

        # Should fail with small max_size
        try:
            validate_matrix(matrix, max_size=1)
            self.failed += 1
            self.errors.append("Matrix validation should fail for exceeding max size")
        except MatrixValidationError:
            self.passed += 1

    def test_error_no_os(self):
        """Test error handling for empty OS options."""
        def create_empty_config():
            config = MatrixConfig(
                os_options=[],
                language_versions={"python": ["3.11"]},
                feature_flags={},
            )
            generate_matrix(config)

        self.assert_raises(create_empty_config, MatrixValidationError, "Should raise error for no OS options")

    def test_error_no_language(self):
        """Test error handling for empty language versions."""
        def create_no_lang_config():
            config = MatrixConfig(
                os_options=["ubuntu-latest"],
                language_versions={},
                feature_flags={},
            )
            generate_matrix(config)

        self.assert_raises(create_no_lang_config, MatrixValidationError, "Should raise error for no language versions")

    def test_strategy_config(self):
        """Test strategy configuration output."""
        config = MatrixConfig(
            os_options=["ubuntu-latest"],
            language_versions={"python": ["3.11"]},
            feature_flags={},
            fail_fast=False,
            max_parallel=4,
        )
        output = generate_matrix(config, include_strategy_config=True)

        self.assert_true("strategy" in output, "Output should include 'strategy' key")
        self.assert_true("matrix" in output, "Output should include 'matrix' key")
        self.assert_equal(output["strategy"]["fail-fast"], False, "fail-fast should be False")
        self.assert_equal(output["strategy"]["max-parallel"], 4, "max-parallel should be 4")

    def test_json_serialization(self):
        """Test JSON serialization."""
        config = MatrixConfig(
            os_options=["ubuntu-latest"],
            language_versions={"python": ["3.11"]},
            feature_flags={},
        )
        matrix = generate_matrix(config)

        try:
            json_str = json.dumps(matrix)
            parsed = json.loads(json_str)
            self.assert_equal(len(parsed), 1, "JSON serialization should preserve matrix size")
            self.passed += 1
        except Exception as e:
            self.failed += 1
            self.errors.append(f"JSON serialization failed: {e}")

    def test_cli_fixture_basic(self):
        """Test CLI with basic fixture."""
        config_json = json.dumps({
            "os_options": ["ubuntu-latest"],
            "language_versions": {"python": ["3.11"]},
            "feature_flags": {},
        })

        try:
            config = load_config_from_json(config_json)
            matrix = generate_matrix(config)
            self.assert_equal(len(matrix), 1, "Basic fixture should create 1 entry")
        except Exception as e:
            self.failed += 1
            self.errors.append(f"CLI fixture basic failed: {e}")

    def test_cli_fixture_realistic(self):
        """Test CLI with realistic fixture."""
        config_json = json.dumps({
            "os_options": ["ubuntu-latest", "macos-latest"],
            "language_versions": {
                "python": ["3.9", "3.11", "3.12"],
                "node": ["18"],
            },
            "feature_flags": {"test_suite": ["unit", "integration"]},
            "exclude": [{"os": "macos-latest", "test_suite": "integration"}],
            "fail_fast": False,
            "max_parallel": 12,
        })

        try:
            config = load_config_from_json(config_json)
            matrix = generate_matrix(config)
            # 2 OS × 3 Python × 1 Node × 2 test_suite - 3 excluded = 9
            self.assert_equal(len(matrix), 9, "Realistic fixture should create 9 entries")
        except Exception as e:
            self.failed += 1
            self.errors.append(f"CLI fixture realistic failed: {e}")

    def run_all(self):
        """Run all tests."""
        tests = [
            self.test_basic_matrix,
            self.test_cartesian_product,
            self.test_exclude_rules,
            self.test_feature_flags,
            self.test_include_rules,
            self.test_validation_max_size,
            self.test_error_no_os,
            self.test_error_no_language,
            self.test_strategy_config,
            self.test_json_serialization,
            self.test_cli_fixture_basic,
            self.test_cli_fixture_realistic,
        ]

        for test in tests:
            try:
                test()
            except Exception as e:
                self.failed += 1
                self.errors.append(f"Test {test.__name__} raised unexpected exception:\n{traceback.format_exc()}")

    def print_results(self):
        """Print test results."""
        print(f"\n{'='*70}")
        print(f"Test Results: {self.passed} passed, {self.failed} failed")
        print(f"{'='*70}\n")

        if self.errors:
            print("FAILURES:\n")
            for i, error in enumerate(self.errors, 1):
                print(f"{i}. {error}\n")

        return self.failed == 0


if __name__ == "__main__":
    runner = TestRunner()
    runner.run_all()
    success = runner.print_results()
    sys.exit(0 if success else 1)
