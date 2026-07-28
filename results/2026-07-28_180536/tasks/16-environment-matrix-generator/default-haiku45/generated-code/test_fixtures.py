"""Test fixtures for integration testing via GitHub Actions."""

import json


# Test fixture 1: Basic matrix
FIXTURE_BASIC = {
    "name": "basic",
    "config": {
        "os_options": ["ubuntu-latest"],
        "language_versions": {"python": ["3.11"]},
        "feature_flags": {},
    },
    "expected_matrix_size": 1,
    "expected_keys": ["os", "python"],
}

# Test fixture 2: Multiple OS and versions
FIXTURE_MULTI = {
    "name": "multi",
    "config": {
        "os_options": ["ubuntu-latest", "macos-latest"],
        "language_versions": {"python": ["3.11", "3.12"]},
        "feature_flags": {},
    },
    "expected_matrix_size": 4,
    "expected_keys": ["os", "python"],
}

# Test fixture 3: With exclude rules
FIXTURE_EXCLUDE = {
    "name": "exclude",
    "config": {
        "os_options": ["ubuntu-latest", "windows-latest"],
        "language_versions": {"python": ["3.11", "3.12"]},
        "feature_flags": {},
        "exclude": [{"os": "windows-latest", "python": "3.11"}],
    },
    "expected_matrix_size": 3,
    "expected_keys": ["os", "python"],
}

# Test fixture 4: With feature flags
FIXTURE_FLAGS = {
    "name": "flags",
    "config": {
        "os_options": ["ubuntu-latest"],
        "language_versions": {"python": ["3.11"]},
        "feature_flags": {"debug": [True, False]},
    },
    "expected_matrix_size": 2,
    "expected_keys": ["os", "python", "debug"],
}

# Test fixture 5: With strategy config
FIXTURE_STRATEGY = {
    "name": "strategy",
    "config": {
        "os_options": ["ubuntu-latest"],
        "language_versions": {"python": ["3.11"]},
        "feature_flags": {},
        "fail_fast": False,
        "max_parallel": 4,
    },
    "expected_matrix_size": 1,
    "expected_keys": ["os", "python"],
    "expected_strategy": {
        "fail-fast": False,
        "max-parallel": 4,
    },
}

# Test fixture 6: Realistic CI matrix
FIXTURE_REALISTIC = {
    "name": "realistic",
    "config": {
        "os_options": ["ubuntu-latest", "macos-latest"],
        "language_versions": {
            "python": ["3.9", "3.11", "3.12"],
            "node": ["18"],
        },
        "feature_flags": {"test_suite": ["unit", "integration"]},
        "exclude": [
            {"os": "macos-latest", "test_suite": "integration"},
        ],
        "fail_fast": False,
        "max_parallel": 12,
    },
    "expected_matrix_size": 9,
    "expected_keys": ["os", "python", "node", "test_suite"],
}

# Test fixture 7: Error case - no OS
FIXTURE_ERROR_NO_OS = {
    "name": "error_no_os",
    "config": {
        "os_options": [],
        "language_versions": {"python": ["3.11"]},
        "feature_flags": {},
    },
    "should_error": True,
    "error_pattern": "At least one OS",
}

# Test fixture 8: Error case - no language versions
FIXTURE_ERROR_NO_LANG = {
    "name": "error_no_lang",
    "config": {
        "os_options": ["ubuntu-latest"],
        "language_versions": {},
        "feature_flags": {},
    },
    "should_error": True,
    "error_pattern": "At least one language",
}

# Test fixture 9: Include rules only
FIXTURE_INCLUDE = {
    "name": "include",
    "config": {
        "os_options": ["ubuntu-latest", "macos-latest"],
        "language_versions": {"python": ["3.11", "3.12"]},
        "feature_flags": {},
        "include": [
            {"os": "ubuntu-latest", "python": "3.11"},
            {"os": "macos-latest", "python": "3.12"},
        ],
    },
    "expected_matrix_size": 2,
    "expected_keys": ["os", "python"],
}

# Test fixture 10: Complex with multiple feature flags
FIXTURE_COMPLEX = {
    "name": "complex",
    "config": {
        "os_options": ["ubuntu-latest"],
        "language_versions": {"python": ["3.11"]},
        "feature_flags": {
            "debug": [True, False],
            "optimize": ["none", "full"],
        },
    },
    "expected_matrix_size": 4,
    "expected_keys": ["os", "python", "debug", "optimize"],
}


ALL_FIXTURES = [
    FIXTURE_BASIC,
    FIXTURE_MULTI,
    FIXTURE_EXCLUDE,
    FIXTURE_FLAGS,
    FIXTURE_STRATEGY,
    FIXTURE_REALISTIC,
    FIXTURE_ERROR_NO_OS,
    FIXTURE_ERROR_NO_LANG,
    FIXTURE_INCLUDE,
    FIXTURE_COMPLEX,
]


def get_fixture(name: str) -> dict:
    """Get a fixture by name."""
    for fixture in ALL_FIXTURES:
        if fixture["name"] == name:
            return fixture
    raise ValueError(f"Unknown fixture: {name}")


def get_all_fixture_names() -> list:
    """Get all fixture names."""
    return [f["name"] for f in ALL_FIXTURES if not f.get("should_error")]


def get_error_fixture_names() -> list:
    """Get all error fixture names."""
    return [f["name"] for f in ALL_FIXTURES if f.get("should_error")]


if __name__ == "__main__":
    print("Test fixtures loaded successfully")
    print(f"Total fixtures: {len(ALL_FIXTURES)}")
    print(f"Success fixtures: {len(get_all_fixture_names())}")
    print(f"Error fixtures: {len(get_error_fixture_names())}")
