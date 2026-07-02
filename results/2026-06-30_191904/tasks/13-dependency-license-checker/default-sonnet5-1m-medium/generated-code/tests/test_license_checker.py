"""
Tests for the license compliance checker.

The real license lookup would hit a registry (npm/PyPI) or a local
package cache. For testability we depend on an injected "lookup"
callable and mock it here, per the task's TDD + mocking requirement.
"""
import pytest

from license_checker import (
    check_dependency,
    check_compliance,
    LicenseStatus,
    LicenseLookupError,
)


def make_mock_lookup(licenses):
    """Return a lookup callable backed by a fixed {name: license} dict.

    Missing entries simulate a lookup miss (license unknown), and the
    special value "__error__" simulates the lookup service failing.
    """

    def lookup(name, version):
        if name not in licenses:
            return None
        license_name = licenses[name]
        if license_name == "__error__":
            raise LicenseLookupError(f"Lookup failed for {name}@{version}")
        return license_name

    return lookup


class TestCheckDependency:
    def test_approved_license_is_approved(self):
        lookup = make_mock_lookup({"left-pad": "MIT"})
        result = check_dependency(
            "left-pad", "1.3.0", lookup, allow_list=["MIT"], deny_list=["GPL-3.0"]
        )
        assert result["status"] == LicenseStatus.APPROVED
        assert result["license"] == "MIT"
        assert result["name"] == "left-pad"
        assert result["version"] == "1.3.0"

    def test_denied_license_is_denied(self):
        lookup = make_mock_lookup({"copyleft-lib": "GPL-3.0"})
        result = check_dependency(
            "copyleft-lib", "2.0.0", lookup, allow_list=["MIT"], deny_list=["GPL-3.0"]
        )
        assert result["status"] == LicenseStatus.DENIED
        assert result["license"] == "GPL-3.0"

    def test_license_not_in_either_list_is_unknown(self):
        lookup = make_mock_lookup({"obscure-lib": "WTFPL"})
        result = check_dependency(
            "obscure-lib", "1.0.0", lookup, allow_list=["MIT"], deny_list=["GPL-3.0"]
        )
        assert result["status"] == LicenseStatus.UNKNOWN

    def test_lookup_miss_is_unknown(self):
        lookup = make_mock_lookup({})
        result = check_dependency(
            "mystery-lib", "1.0.0", lookup, allow_list=["MIT"], deny_list=["GPL-3.0"]
        )
        assert result["status"] == LicenseStatus.UNKNOWN
        assert result["license"] is None

    def test_lookup_error_is_recorded_as_unknown_with_reason(self):
        lookup = make_mock_lookup({"flaky-lib": "__error__"})
        result = check_dependency(
            "flaky-lib", "1.0.0", lookup, allow_list=["MIT"], deny_list=["GPL-3.0"]
        )
        assert result["status"] == LicenseStatus.UNKNOWN
        assert "Lookup failed" in result["error"]

    def test_deny_list_takes_precedence_over_allow_list(self):
        # A license present in both lists (misconfiguration) should be denied,
        # since compliance checks must fail closed.
        lookup = make_mock_lookup({"weird-lib": "MIT"})
        result = check_dependency(
            "weird-lib", "1.0.0", lookup, allow_list=["MIT"], deny_list=["MIT"]
        )
        assert result["status"] == LicenseStatus.DENIED


class TestCheckCompliance:
    def test_checks_every_dependency(self):
        lookup = make_mock_lookup(
            {"left-pad": "MIT", "copyleft-lib": "GPL-3.0", "obscure-lib": "WTFPL"}
        )
        deps = {"left-pad": "1.3.0", "copyleft-lib": "2.0.0", "obscure-lib": "1.0.0"}
        results = check_compliance(deps, lookup, allow_list=["MIT"], deny_list=["GPL-3.0"])
        statuses = {r["name"]: r["status"] for r in results}
        assert statuses == {
            "left-pad": LicenseStatus.APPROVED,
            "copyleft-lib": LicenseStatus.DENIED,
            "obscure-lib": LicenseStatus.UNKNOWN,
        }

    def test_empty_dependencies_returns_empty_results(self):
        lookup = make_mock_lookup({})
        assert check_compliance({}, lookup, allow_list=[], deny_list=[]) == []

    def test_results_sorted_by_name_for_stable_output(self):
        lookup = make_mock_lookup({"zeta": "MIT", "alpha": "MIT"})
        deps = {"zeta": "1.0.0", "alpha": "1.0.0"}
        results = check_compliance(deps, lookup, allow_list=["MIT"], deny_list=[])
        assert [r["name"] for r in results] == ["alpha", "zeta"]
