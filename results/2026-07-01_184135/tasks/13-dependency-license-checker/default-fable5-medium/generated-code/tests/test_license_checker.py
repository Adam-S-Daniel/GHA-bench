"""Tests for the dependency license checker.

Built with red/green TDD: each test (or small group) was written first,
observed to fail, then the minimum implementation was added to make it
pass, followed by refactoring. The test file grew cycle by cycle:

  Cycle 1: parse package.json manifests
  Cycle 2: parse requirements.txt manifests + format auto-detection
  Cycle 3: parse errors (missing file, invalid JSON, unparseable lines)
  Cycle 4: license classification against allow/deny config
  Cycle 5: report generation with a MOCKED license lookup
  Cycle 6: CLI end-to-end over the checked-in fixtures
"""

import json
import subprocess
import sys
from pathlib import Path
from unittest import mock

import pytest

# Make the project root importable regardless of pytest invocation dir.
PROJECT_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(PROJECT_ROOT))

from license_checker import (
    Dependency,
    LicenseCheckerError,
    MockLicenseSource,
    classify_license,
    generate_report,
    load_config,
    parse_manifest,
    render_report,
)

FIXTURES = PROJECT_ROOT / "fixtures"


# --------------------------------------------------------------------------
# Cycle 1: parsing package.json
# --------------------------------------------------------------------------

def test_parse_package_json_extracts_names_and_versions(tmp_path):
    manifest = tmp_path / "package.json"
    manifest.write_text(json.dumps({
        "name": "demo",
        "dependencies": {"express": "4.18.2", "lodash": "^4.17.21"},
        "devDependencies": {"jest": "29.0.0"},
    }))
    deps = parse_manifest(manifest)
    assert deps == [
        Dependency("express", "4.18.2"),
        Dependency("lodash", "4.17.21"),  # range prefixes are stripped
        Dependency("jest", "29.0.0"),
    ]


def test_parse_package_json_without_dependencies_is_empty(tmp_path):
    manifest = tmp_path / "package.json"
    manifest.write_text(json.dumps({"name": "empty-project"}))
    assert parse_manifest(manifest) == []


# --------------------------------------------------------------------------
# Cycle 2: parsing requirements.txt + auto-detection by content
# --------------------------------------------------------------------------

def test_parse_requirements_txt(tmp_path):
    manifest = tmp_path / "requirements.txt"
    manifest.write_text(
        "# comment lines and blanks are ignored\n"
        "\n"
        "requests==2.31.0\n"
        "flask>=3.0.0  # trailing comment\n"
        "pyyaml\n"
    )
    deps = parse_manifest(manifest)
    assert deps == [
        Dependency("requests", "2.31.0"),
        Dependency("flask", "3.0.0"),
        Dependency("pyyaml", "unspecified"),
    ]


def test_format_detected_by_content_not_extension(tmp_path):
    # The CI harness feeds an extensionless file; JSON content must be
    # treated as package.json, anything else as requirements-style.
    manifest = tmp_path / "manifest"
    manifest.write_text(json.dumps({"dependencies": {"react": "18.2.0"}}))
    assert parse_manifest(manifest) == [Dependency("react", "18.2.0")]


# --------------------------------------------------------------------------
# Cycle 3: graceful error handling with meaningful messages
# --------------------------------------------------------------------------

def test_missing_manifest_raises_clear_error(tmp_path):
    with pytest.raises(LicenseCheckerError, match="Manifest not found"):
        parse_manifest(tmp_path / "does-not-exist.json")


def test_malformed_package_json_raises_clear_error(tmp_path):
    manifest = tmp_path / "package.json"
    manifest.write_text("{ this is not valid json")
    with pytest.raises(LicenseCheckerError, match="Invalid JSON"):
        parse_manifest(manifest)


def test_invalid_requirement_line_raises_clear_error(tmp_path):
    manifest = tmp_path / "requirements.txt"
    manifest.write_text("???not a valid requirement???\n")
    with pytest.raises(LicenseCheckerError, match="Unparseable requirement"):
        parse_manifest(manifest)


def test_missing_config_raises_clear_error(tmp_path):
    with pytest.raises(LicenseCheckerError, match="Config not found"):
        load_config(tmp_path / "nope.json")


def test_config_missing_keys_raises_clear_error(tmp_path):
    cfg = tmp_path / "config.json"
    cfg.write_text(json.dumps({"allow": ["MIT"]}))  # 'deny' missing
    with pytest.raises(LicenseCheckerError, match="must contain 'allow' and 'deny'"):
        load_config(cfg)


# --------------------------------------------------------------------------
# Cycle 4: classifying a license against the allow/deny lists
# --------------------------------------------------------------------------

CONFIG = {"allow": ["MIT", "Apache-2.0", "BSD-3-Clause"], "deny": ["GPL-3.0", "AGPL-3.0"]}


@pytest.mark.parametrize("license_id,expected", [
    ("MIT", "approved"),
    ("mit", "approved"),          # case-insensitive matching
    ("GPL-3.0", "denied"),
    ("WTFPL", "unknown"),         # not on either list
    (None, "unknown"),            # lookup found nothing
])
def test_classify_license(license_id, expected):
    assert classify_license(license_id, CONFIG) == expected


def test_deny_wins_over_allow_when_listed_on_both():
    conflicted = {"allow": ["MIT"], "deny": ["MIT"]}
    assert classify_license("MIT", conflicted) == "denied"


# --------------------------------------------------------------------------
# Cycle 5: report generation with a mocked license lookup
# --------------------------------------------------------------------------

def test_generate_report_with_mock_source():
    # The mock stands in for a real registry/API lookup so tests are
    # deterministic and offline.
    source = MockLicenseSource({"express": "MIT", "copyleft-lib": "GPL-3.0"})
    deps = [
        Dependency("express", "4.18.2"),
        Dependency("copyleft-lib", "1.0.0"),
        Dependency("mystery-lib", "0.1.0"),  # not in the mock -> unknown
    ]
    report = generate_report(deps, source, CONFIG)
    assert report == [
        {"name": "express", "version": "4.18.2", "license": "MIT", "status": "approved"},
        {"name": "copyleft-lib", "version": "1.0.0", "license": "GPL-3.0", "status": "denied"},
        {"name": "mystery-lib", "version": "0.1.0", "license": "UNKNOWN", "status": "unknown"},
    ]


def test_generate_report_with_unittest_mock_patch():
    # Alternative mocking style: patch the source object entirely.
    source = mock.Mock()
    source.lookup.return_value = "Apache-2.0"
    report = generate_report([Dependency("httpx", "0.27.0")], source, CONFIG)
    source.lookup.assert_called_once_with("httpx")
    assert report[0]["status"] == "approved"


def test_render_report_text_format():
    report = [
        {"name": "express", "version": "4.18.2", "license": "MIT", "status": "approved"},
        {"name": "copyleft-lib", "version": "1.0.0", "license": "GPL-3.0", "status": "denied"},
        {"name": "jest", "version": "29.0.0", "license": "MIT", "status": "approved"},
        {"name": "mystery-lib", "version": "0.1.0", "license": "UNKNOWN", "status": "unknown"},
    ]
    text = render_report(report)
    assert "express | 4.18.2 | MIT | approved" in text
    assert "copyleft-lib | 1.0.0 | GPL-3.0 | denied" in text
    assert "mystery-lib | 0.1.0 | UNKNOWN | unknown" in text
    assert "Summary: 2 approved, 1 denied, 1 unknown" in text


# --------------------------------------------------------------------------
# Cycle 6: CLI end-to-end using the checked-in fixtures
# --------------------------------------------------------------------------

def run_cli(*args):
    return subprocess.run(
        [sys.executable, str(PROJECT_ROOT / "license_checker.py"), *args],
        capture_output=True, text=True,
    )


def test_cli_reports_on_package_json_fixture():
    result = run_cli(
        "--manifest", str(FIXTURES / "package.json"),
        "--config", str(FIXTURES / "config.json"),
        "--licenses", str(FIXTURES / "mock_licenses.json"),
    )
    assert result.returncode == 0, result.stderr
    assert "express | 4.18.2 | MIT | approved" in result.stdout
    assert "copyleft-lib | 1.0.0 | GPL-3.0 | denied" in result.stdout
    assert "mystery-lib | 0.1.0 | UNKNOWN | unknown" in result.stdout
    assert "Summary: 2 approved, 1 denied, 1 unknown" in result.stdout


def test_cli_fail_on_denied_flag_sets_exit_code():
    result = run_cli(
        "--manifest", str(FIXTURES / "package.json"),
        "--config", str(FIXTURES / "config.json"),
        "--licenses", str(FIXTURES / "mock_licenses.json"),
        "--fail-on-denied",
    )
    assert result.returncode == 2


def test_cli_missing_manifest_prints_meaningful_error():
    result = run_cli(
        "--manifest", "no-such-file",
        "--config", str(FIXTURES / "config.json"),
        "--licenses", str(FIXTURES / "mock_licenses.json"),
    )
    assert result.returncode == 1
    assert "Manifest not found" in result.stderr
