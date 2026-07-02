"""
TDD test suite for the dependency license checker.

Tests are written in red/green style: each test was authored before the
corresponding implementation existed. Run with:

    python3 -m pytest tests/ -v

License lookups are mocked via a small in-memory "license database" (a dict
mapping "name==version" -> license string) so tests never hit the network.
"""
import json
import os
import sys

import pytest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from license_checker import (
    parse_package_json,
    parse_requirements_txt,
    load_config,
    classify_license,
    check_dependencies,
    generate_report,
    LicenseCheckerError,
)


FIXTURES = os.path.join(os.path.dirname(__file__), "..", "fixtures")


# ---------------------------------------------------------------------------
# Step 1: parsing manifests
# ---------------------------------------------------------------------------

def test_parse_package_json_extracts_name_and_version():
    path = os.path.join(FIXTURES, "package.json")
    deps = parse_package_json(path)
    assert deps["left-pad"] == "1.3.0"
    assert deps["express"] == "4.18.2"


def test_parse_package_json_includes_dev_dependencies():
    path = os.path.join(FIXTURES, "package.json")
    deps = parse_package_json(path)
    assert deps["jest"] == "29.0.0"


def test_parse_package_json_missing_file_raises_clear_error():
    with pytest.raises(LicenseCheckerError) as exc:
        parse_package_json(os.path.join(FIXTURES, "does-not-exist.json"))
    assert "not found" in str(exc.value).lower()


def test_parse_requirements_txt_extracts_name_and_version():
    path = os.path.join(FIXTURES, "requirements.txt")
    deps = parse_requirements_txt(path)
    assert deps["requests"] == "2.31.0"
    assert deps["flask"] == "2.3.2"


def test_parse_requirements_txt_ignores_comments_and_blank_lines():
    path = os.path.join(FIXTURES, "requirements.txt")
    deps = parse_requirements_txt(path)
    assert "# a comment" not in deps
    assert len(deps) == 3


# ---------------------------------------------------------------------------
# Step 2: config (allow-list / deny-list)
# ---------------------------------------------------------------------------

def test_load_config_reads_allow_and_deny_lists():
    path = os.path.join(FIXTURES, "license-policy.json")
    config = load_config(path)
    assert "MIT" in config["allow"]
    assert "GPL-3.0" in config["deny"]


def test_load_config_missing_file_raises_clear_error():
    with pytest.raises(LicenseCheckerError) as exc:
        load_config(os.path.join(FIXTURES, "no-such-config.json"))
    assert "not found" in str(exc.value).lower()


# ---------------------------------------------------------------------------
# Step 3: classification
# ---------------------------------------------------------------------------

def test_classify_license_approved():
    config = {"allow": ["MIT", "Apache-2.0"], "deny": ["GPL-3.0"]}
    assert classify_license("MIT", config) == "approved"


def test_classify_license_denied():
    config = {"allow": ["MIT"], "deny": ["GPL-3.0"]}
    assert classify_license("GPL-3.0", config) == "denied"


def test_classify_license_unknown_when_not_listed():
    config = {"allow": ["MIT"], "deny": ["GPL-3.0"]}
    assert classify_license("BSD-3-Clause", config) == "unknown"


def test_classify_license_unknown_when_license_is_none():
    config = {"allow": ["MIT"], "deny": ["GPL-3.0"]}
    assert classify_license(None, config) == "unknown"


# ---------------------------------------------------------------------------
# Step 4: end-to-end check with a mocked license lookup
# ---------------------------------------------------------------------------

def mock_license_lookup(name, version):
    """Fake 'license database' used in place of a real registry call."""
    db = {
        ("left-pad", "1.3.0"): "MIT",
        ("express", "4.18.2"): "MIT",
        ("jest", "29.0.0"): "MIT",
        ("requests", "2.31.0"): "Apache-2.0",
        ("flask", "2.3.2"): "BSD-3-Clause",
        ("gpl-lib", "1.0.0"): "GPL-3.0",
    }
    return db.get((name, version))


def test_check_dependencies_classifies_each_dependency():
    deps = {"left-pad": "1.3.0", "gpl-lib": "1.0.0", "flask": "2.3.2"}
    config = {"allow": ["MIT"], "deny": ["GPL-3.0"]}
    results = check_dependencies(deps, mock_license_lookup, config)

    by_name = {r["name"]: r for r in results}
    assert by_name["left-pad"]["status"] == "approved"
    assert by_name["left-pad"]["license"] == "MIT"
    assert by_name["gpl-lib"]["status"] == "denied"
    assert by_name["flask"]["status"] == "unknown"


def test_check_dependencies_handles_lookup_returning_none():
    deps = {"totally-unknown-pkg": "9.9.9"}
    config = {"allow": ["MIT"], "deny": ["GPL-3.0"]}
    results = check_dependencies(deps, mock_license_lookup, config)
    assert results[0]["status"] == "unknown"
    assert results[0]["license"] is None


def test_check_dependencies_lookup_error_is_caught_and_marked_unknown():
    def broken_lookup(name, version):
        raise RuntimeError("registry unreachable")

    deps = {"left-pad": "1.3.0"}
    config = {"allow": ["MIT"], "deny": ["GPL-3.0"]}
    results = check_dependencies(deps, broken_lookup, config)
    assert results[0]["status"] == "unknown"
    assert results[0]["license"] is None


# ---------------------------------------------------------------------------
# Step 5: report generation
# ---------------------------------------------------------------------------

def test_generate_report_lists_all_dependencies_and_counts():
    results = [
        {"name": "left-pad", "version": "1.3.0", "license": "MIT", "status": "approved"},
        {"name": "gpl-lib", "version": "1.0.0", "license": "GPL-3.0", "status": "denied"},
        {"name": "flask", "version": "2.3.2", "license": "BSD-3-Clause", "status": "unknown"},
    ]
    report = generate_report(results)
    assert "left-pad" in report
    assert "gpl-lib" in report
    assert "flask" in report
    assert "Approved: 1" in report
    assert "Denied: 1" in report
    assert "Unknown: 1" in report


def test_generate_report_empty_dependency_list():
    report = generate_report([])
    assert "Approved: 0" in report
    assert "Denied: 0" in report
    assert "Unknown: 0" in report


# ---------------------------------------------------------------------------
# Step 6: CLI entrypoint (uses fixtures/license-db.json as the "mocked" lookup)
# ---------------------------------------------------------------------------

from license_checker import main


def test_main_exits_zero_when_no_denied_licenses(capsys):
    manifest = os.path.join(FIXTURES, "package.json")
    policy = os.path.join(FIXTURES, "license-policy.json")
    db = os.path.join(FIXTURES, "license-db.json")
    rc = main([manifest, policy, db])
    out = capsys.readouterr().out
    assert rc == 0
    assert "left-pad==1.3.0 -> MIT" in out
    assert "Denied: 0" in out


def test_main_exits_nonzero_when_a_dependency_is_denied(tmp_path, capsys):
    manifest = tmp_path / "requirements.txt"
    manifest.write_text("gpl-lib==1.0.0\n")
    policy = os.path.join(FIXTURES, "license-policy.json")
    db = os.path.join(FIXTURES, "license-db.json")
    rc = main([str(manifest), policy, db])
    out = capsys.readouterr().out
    assert rc == 1
    assert "DENIED" in out
    assert "Denied: 1" in out


def test_main_missing_manifest_prints_error_and_exits_nonzero(capsys):
    policy = os.path.join(FIXTURES, "license-policy.json")
    rc = main(["/no/such/manifest.txt", policy])
    err = capsys.readouterr().err
    assert rc == 1
    assert "Error:" in err
