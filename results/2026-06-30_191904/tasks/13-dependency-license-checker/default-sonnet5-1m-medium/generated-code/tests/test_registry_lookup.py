"""
Tests for the real license lookup against package registries (npm/PyPI).

The task requires mocking the license lookup for testing, since hitting
real network registries in a test suite is slow and flaky. We patch the
low-level `_fetch_json` function so `npm_license_lookup`/`pypi_license_lookup`
exercise all of their real parsing logic against canned registry responses.
"""
import pytest

import json

from license_checker import LicenseLookupError
from registry_lookup import (
    npm_license_lookup,
    pypi_license_lookup,
    make_registry_lookup,
    fixture_license_lookup,
)


class TestNpmLicenseLookup:
    def test_extracts_license_string_field(self, monkeypatch):
        monkeypatch.setattr(
            "registry_lookup._fetch_json",
            lambda url: {"license": "MIT"},
        )
        assert npm_license_lookup("left-pad", "1.3.0") == "MIT"

    def test_extracts_license_object_type_field(self, monkeypatch):
        # Older npm packages report license as {"type": "...", "url": "..."}
        monkeypatch.setattr(
            "registry_lookup._fetch_json",
            lambda url: {"license": {"type": "Apache-2.0", "url": "http://example.com"}},
        )
        assert npm_license_lookup("old-pkg", "0.1.0") == "Apache-2.0"

    def test_missing_license_field_returns_none(self, monkeypatch):
        monkeypatch.setattr("registry_lookup._fetch_json", lambda url: {})
        assert npm_license_lookup("no-license-pkg", "1.0.0") is None

    def test_network_failure_raises_license_lookup_error(self, monkeypatch):
        def boom(url):
            raise OSError("connection refused")

        monkeypatch.setattr("registry_lookup._fetch_json", boom)
        with pytest.raises(LicenseLookupError, match="left-pad"):
            npm_license_lookup("left-pad", "1.3.0")


class TestPypiLicenseLookup:
    def test_prefers_license_classifier_over_free_text_field(self, monkeypatch):
        # PyPI's free-text "license" field is unreliable/inconsistent; a
        # trove classifier like "License :: OSI Approved :: MIT License"
        # is the more trustworthy signal, so it should win when present.
        monkeypatch.setattr(
            "registry_lookup._fetch_json",
            lambda url: {
                "info": {
                    "license": "Copyright Foo Corp",
                    "classifiers": [
                        "Programming Language :: Python :: 3",
                        "License :: OSI Approved :: MIT License",
                    ],
                }
            },
        )
        assert pypi_license_lookup("requests", "2.31.0") == "MIT"

    def test_falls_back_to_free_text_license_field(self, monkeypatch):
        monkeypatch.setattr(
            "registry_lookup._fetch_json",
            lambda url: {"info": {"license": "BSD-3-Clause", "classifiers": []}},
        )
        assert pypi_license_lookup("numpy", "1.26.0") == "BSD-3-Clause"

    def test_no_license_information_returns_none(self, monkeypatch):
        monkeypatch.setattr(
            "registry_lookup._fetch_json",
            lambda url: {"info": {"license": "", "classifiers": []}},
        )
        assert pypi_license_lookup("mystery", "1.0.0") is None

    def test_network_failure_raises_license_lookup_error(self, monkeypatch):
        def boom(url):
            raise OSError("timeout")

        monkeypatch.setattr("registry_lookup._fetch_json", boom)
        with pytest.raises(LicenseLookupError, match="numpy"):
            pypi_license_lookup("numpy", "1.26.0")


class TestMakeRegistryLookup:
    def test_npm_ecosystem_uses_npm_lookup(self, monkeypatch):
        monkeypatch.setattr("registry_lookup._fetch_json", lambda url: {"license": "ISC"})
        lookup = make_registry_lookup("npm")
        assert lookup("some-pkg", "1.0.0") == "ISC"

    def test_pypi_ecosystem_uses_pypi_lookup(self, monkeypatch):
        monkeypatch.setattr(
            "registry_lookup._fetch_json",
            lambda url: {"info": {"license": "MIT", "classifiers": []}},
        )
        lookup = make_registry_lookup("pypi")
        assert lookup("some-pkg", "1.0.0") == "MIT"

    def test_unknown_ecosystem_raises_value_error(self):
        with pytest.raises(ValueError, match="Unsupported ecosystem"):
            make_registry_lookup("cargo")


class TestFixtureLicenseLookup:
    """A local-file-backed lookup for offline/CI use (no network required)."""

    def test_returns_license_for_known_dependency(self, tmp_path):
        data_path = tmp_path / "license-data.json"
        data_path.write_text(json.dumps({"left-pad": "MIT"}))
        lookup = fixture_license_lookup(str(data_path))
        assert lookup("left-pad", "1.3.0") == "MIT"

    def test_returns_none_for_unlisted_dependency(self, tmp_path):
        data_path = tmp_path / "license-data.json"
        data_path.write_text(json.dumps({"left-pad": "MIT"}))
        lookup = fixture_license_lookup(str(data_path))
        assert lookup("unknown-pkg", "1.0.0") is None

    def test_missing_data_file_raises_meaningful_error(self, tmp_path):
        with pytest.raises(LicenseLookupError, match="not found"):
            fixture_license_lookup(str(tmp_path / "missing.json"))
