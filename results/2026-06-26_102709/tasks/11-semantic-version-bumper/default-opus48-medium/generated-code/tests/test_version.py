"""Red/green TDD test for reading the current version string.

We start with the smallest piece of behaviour: given a file, read out the
semantic version it contains. We support both a plain text VERSION file and a
package.json file (the two most common conventions).
"""
import json

import pytest

from bump_version import read_version


def test_read_version_from_plain_file(tmp_path):
    # A plain VERSION file just contains the bare version string.
    vfile = tmp_path / "VERSION"
    vfile.write_text("1.2.3\n")
    assert read_version(str(vfile)) == "1.2.3"


def test_read_version_from_package_json(tmp_path):
    pkg = tmp_path / "package.json"
    pkg.write_text(json.dumps({"name": "demo", "version": "0.4.1"}))
    assert read_version(str(pkg)) == "0.4.1"


def test_read_version_missing_file_raises_friendly_error(tmp_path):
    with pytest.raises(FileNotFoundError) as exc:
        read_version(str(tmp_path / "nope"))
    assert "Version file not found" in str(exc.value)
