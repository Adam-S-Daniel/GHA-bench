"""Tests for loading the allow-list/deny-list config file."""
import json

import pytest

from config import load_license_config, ConfigError


class TestLoadLicenseConfig:
    def test_loads_allow_and_deny_lists(self, tmp_path):
        path = tmp_path / "license-config.json"
        path.write_text(json.dumps({"allow": ["MIT", "Apache-2.0"], "deny": ["GPL-3.0"]}))
        config = load_license_config(str(path))
        assert config.allow_list == ["MIT", "Apache-2.0"]
        assert config.deny_list == ["GPL-3.0"]

    def test_missing_keys_default_to_empty_lists(self, tmp_path):
        path = tmp_path / "license-config.json"
        path.write_text(json.dumps({}))
        config = load_license_config(str(path))
        assert config.allow_list == []
        assert config.deny_list == []

    def test_missing_file_raises_meaningful_error(self, tmp_path):
        missing = str(tmp_path / "does-not-exist.json")
        with pytest.raises(ConfigError, match="not found"):
            load_license_config(missing)

    def test_invalid_json_raises_meaningful_error(self, tmp_path):
        path = tmp_path / "license-config.json"
        path.write_text("{not valid")
        with pytest.raises(ConfigError, match="Invalid JSON"):
            load_license_config(str(path))

    def test_overlapping_allow_and_deny_raises_meaningful_error(self, tmp_path):
        path = tmp_path / "license-config.json"
        path.write_text(json.dumps({"allow": ["MIT"], "deny": ["MIT"]}))
        with pytest.raises(ConfigError, match="both allow and deny"):
            load_license_config(str(path))
