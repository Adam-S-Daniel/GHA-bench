"""Red/green TDD — Step 3: config & file-list loading with error handling.

The rules live in a JSON config (stdlib-only, so the script has zero
third-party dependencies and runs anywhere). Loading must fail loudly with a
``ConfigError`` carrying a meaningful message rather than a raw traceback.
"""

import json

import pytest

import pr_label_assigner as pla


# ---- load_rules -----------------------------------------------------------

def _write(tmp_path, name, text):
    p = tmp_path / name
    p.write_text(text)
    return str(p)


def test_load_valid_rules(tmp_path):
    cfg = _write(tmp_path, "rules.json", json.dumps({
        "rules": [
            {"pattern": "docs/**", "labels": ["documentation"], "priority": 10},
            {"pattern": "*.test.*", "labels": ["tests"]},
        ]
    }))
    rules = pla.load_rules(cfg)
    assert rules[0]["pattern"] == "docs/**"
    assert rules[0]["labels"] == ["documentation"]
    assert rules[0]["priority"] == 10
    # Missing priority defaults to 0.
    assert rules[1]["priority"] == 0


def test_missing_config_file_raises_config_error(tmp_path):
    with pytest.raises(pla.ConfigError) as exc:
        pla.load_rules(str(tmp_path / "nope.json"))
    assert "not found" in str(exc.value).lower()


def test_invalid_json_raises_config_error(tmp_path):
    cfg = _write(tmp_path, "bad.json", "{ this is not json")
    with pytest.raises(pla.ConfigError) as exc:
        pla.load_rules(cfg)
    assert "invalid json" in str(exc.value).lower()


def test_rules_key_must_be_a_list(tmp_path):
    cfg = _write(tmp_path, "r.json", json.dumps({"rules": "oops"}))
    with pytest.raises(pla.ConfigError) as exc:
        pla.load_rules(cfg)
    assert "rules" in str(exc.value).lower()


def test_rule_missing_pattern_reports_index(tmp_path):
    cfg = _write(tmp_path, "r.json", json.dumps({
        "rules": [{"labels": ["x"]}]
    }))
    with pytest.raises(pla.ConfigError) as exc:
        pla.load_rules(cfg)
    msg = str(exc.value).lower()
    assert "pattern" in msg and "0" in msg  # index reported


def test_rule_labels_must_be_nonempty_list(tmp_path):
    cfg = _write(tmp_path, "r.json", json.dumps({
        "rules": [{"pattern": "docs/**", "labels": []}]
    }))
    with pytest.raises(pla.ConfigError) as exc:
        pla.load_rules(cfg)
    assert "labels" in str(exc.value).lower()


# ---- load_changed_files ---------------------------------------------------

def test_load_changed_files_skips_blanks_and_comments(tmp_path):
    f = _write(tmp_path, "changed.txt",
               "docs/a.md\n\n# a comment\nsrc/api/b.py\n   \n")
    files = pla.load_changed_files(f)
    assert files == ["docs/a.md", "src/api/b.py"]


def test_load_changed_files_missing_raises(tmp_path):
    with pytest.raises(pla.ConfigError) as exc:
        pla.load_changed_files(str(tmp_path / "nope.txt"))
    assert "not found" in str(exc.value).lower()
