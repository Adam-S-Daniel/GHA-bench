"""Tests for compliance report generation (text + JSON + exit code)."""
import json

from license_checker import LicenseStatus
from report import generate_text_report, generate_json_report, compliance_exit_code


SAMPLE_RESULTS = [
    {"name": "alpha", "version": "1.0.0", "license": "MIT", "status": LicenseStatus.APPROVED},
    {
        "name": "beta",
        "version": "2.0.0",
        "license": "GPL-3.0",
        "status": LicenseStatus.DENIED,
    },
    {"name": "gamma", "version": "3.0.0", "license": None, "status": LicenseStatus.UNKNOWN},
]


class TestTextReport:
    def test_includes_each_dependency_name_and_status(self):
        report = generate_text_report(SAMPLE_RESULTS)
        assert "alpha" in report and "APPROVED" in report
        assert "beta" in report and "DENIED" in report
        assert "gamma" in report and "UNKNOWN" in report

    def test_includes_summary_counts(self):
        report = generate_text_report(SAMPLE_RESULTS)
        assert "Approved: 1" in report
        assert "Denied: 1" in report
        assert "Unknown: 1" in report

    def test_empty_results_produces_zero_counts(self):
        report = generate_text_report([])
        assert "Approved: 0" in report
        assert "Denied: 0" in report
        assert "Unknown: 0" in report


class TestJsonReport:
    def test_produces_valid_json_with_summary_and_dependencies(self):
        report = generate_json_report(SAMPLE_RESULTS)
        data = json.loads(report)
        assert data["summary"] == {"approved": 1, "denied": 1, "unknown": 1}
        names = [d["name"] for d in data["dependencies"]]
        assert names == ["alpha", "beta", "gamma"]


class TestExitCode:
    def test_zero_when_no_denied_dependencies(self):
        results = [SAMPLE_RESULTS[0], SAMPLE_RESULTS[2]]
        assert compliance_exit_code(results) == 0

    def test_nonzero_when_any_dependency_denied(self):
        assert compliance_exit_code(SAMPLE_RESULTS) != 0
