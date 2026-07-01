"""
End-to-end CLI tests. The registry lookup is mocked (per the task's
mocking requirement) so tests never hit the network; only the CLI
wiring (arg parsing, manifest parsing, config loading, report output,
exit code) is under test here.
"""
import json

import pytest

import main as main_module


def write(path, content):
    path.write_text(content)
    return str(path)


@pytest.fixture
def manifest(tmp_path):
    return write(
        tmp_path / "package.json",
        json.dumps(
            {
                "dependencies": {"good-lib": "1.0.0", "bad-lib": "2.0.0", "mystery-lib": "3.0.0"}
            }
        ),
    )


@pytest.fixture
def config_file(tmp_path):
    return write(
        tmp_path / "license-config.json",
        json.dumps({"allow": ["MIT"], "deny": ["GPL-3.0"]}),
    )


@pytest.fixture
def mock_lookup(monkeypatch):
    licenses = {"good-lib": "MIT", "bad-lib": "GPL-3.0"}  # mystery-lib intentionally absent

    def fake_make_registry_lookup(ecosystem):
        def lookup(name, version):
            return licenses.get(name)

        return lookup

    monkeypatch.setattr(main_module, "make_registry_lookup", fake_make_registry_lookup)
    return licenses


class TestMainCli:
    def test_text_report_lists_all_statuses_and_exits_nonzero_on_denied(
        self, manifest, config_file, mock_lookup, capsys
    ):
        exit_code = main_module.run(
            ["--manifest", manifest, "--config", config_file, "--ecosystem", "npm"]
        )
        out = capsys.readouterr().out
        assert "good-lib" in out and "APPROVED" in out
        assert "bad-lib" in out and "DENIED" in out
        assert "mystery-lib" in out and "UNKNOWN" in out
        assert exit_code == 1

    def test_json_output_format(self, manifest, config_file, mock_lookup, capsys):
        main_module.run(
            [
                "--manifest",
                manifest,
                "--config",
                config_file,
                "--ecosystem",
                "npm",
                "--format",
                "json",
            ]
        )
        out = capsys.readouterr().out
        data = json.loads(out)
        assert data["summary"] == {"approved": 1, "denied": 1, "unknown": 1}

    def test_exits_zero_when_nothing_denied(self, tmp_path, config_file, mock_lookup, capsys):
        clean_manifest = write(
            tmp_path / "package.json",
            json.dumps({"dependencies": {"good-lib": "1.0.0"}}),
        )
        exit_code = main_module.run(
            ["--manifest", clean_manifest, "--config", config_file, "--ecosystem", "npm"]
        )
        assert exit_code == 0

    def test_fixture_ecosystem_reads_local_license_data_file(
        self, manifest, config_file, tmp_path, capsys
    ):
        license_data = write(
            tmp_path / "license-data.json",
            json.dumps({"good-lib": "MIT", "bad-lib": "GPL-3.0"}),
        )
        exit_code = main_module.run(
            [
                "--manifest",
                manifest,
                "--config",
                config_file,
                "--ecosystem",
                "fixture",
                "--license-data",
                license_data,
            ]
        )
        out = capsys.readouterr().out
        assert "good-lib" in out and "APPROVED" in out
        assert "bad-lib" in out and "DENIED" in out
        assert "mystery-lib" in out and "UNKNOWN" in out
        assert exit_code == 1

    def test_fixture_ecosystem_without_license_data_reports_error(
        self, manifest, config_file, capsys
    ):
        exit_code = main_module.run(
            ["--manifest", manifest, "--config", config_file, "--ecosystem", "fixture"]
        )
        assert exit_code == 2
        err = capsys.readouterr().err
        assert "--license-data" in err

    def test_missing_manifest_file_reports_error_and_exits_nonzero(
        self, tmp_path, config_file, mock_lookup, capsys
    ):
        exit_code = main_module.run(
            [
                "--manifest",
                str(tmp_path / "package.json"),
                "--config",
                config_file,
                "--ecosystem",
                "npm",
            ]
        )
        assert exit_code == 2
        err = capsys.readouterr().err
        assert "not found" in err
