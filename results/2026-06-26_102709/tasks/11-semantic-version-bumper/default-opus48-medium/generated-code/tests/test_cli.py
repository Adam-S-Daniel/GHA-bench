"""Red/green TDD for the end-to-end CLI used by the GitHub Actions workflow."""
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCRIPT = os.path.join(ROOT, "bump_version.py")


def _run(args, cwd, env=None):
    full_env = dict(os.environ)
    if env:
        full_env.update(env)
    return subprocess.run(
        [sys.executable, SCRIPT, *args],
        cwd=cwd,
        env=full_env,
        capture_output=True,
        text=True,
    )


def test_cli_bumps_minor_and_writes_files(tmp_path):
    (tmp_path / "VERSION").write_text("1.1.0\n")
    (tmp_path / "commits.log").write_text("feat: shiny thing\x00fix: oops")
    result = _run(
        ["--version-file", "VERSION",
         "--commits", "commits.log",
         "--changelog", "CHANGELOG.md",
         "--date", "2026-06-26"],
        cwd=str(tmp_path),
    )
    assert result.returncode == 0, result.stderr
    # New version is computed and surfaced for humans + machines.
    assert "NEW_VERSION=1.2.0" in result.stdout
    assert (tmp_path / "VERSION").read_text().strip() == "1.2.0"
    changelog = (tmp_path / "CHANGELOG.md").read_text()
    assert "## 1.2.0 - 2026-06-26" in changelog
    assert "- shiny thing" in changelog


def test_cli_writes_github_output(tmp_path):
    (tmp_path / "VERSION").write_text("0.1.0\n")
    (tmp_path / "commits.log").write_text("feat!: big change")
    out_file = tmp_path / "gh_out"
    result = _run(
        ["--version-file", "VERSION", "--commits", "commits.log",
         "--changelog", "CHANGELOG.md", "--date", "2026-06-26"],
        cwd=str(tmp_path),
        env={"GITHUB_OUTPUT": str(out_file)},
    )
    assert result.returncode == 0, result.stderr
    assert "new_version=1.0.0" in out_file.read_text()


def test_cli_no_release_keeps_version(tmp_path):
    (tmp_path / "VERSION").write_text("3.2.1\n")
    (tmp_path / "commits.log").write_text("docs: tidy\x00chore: deps")
    result = _run(
        ["--version-file", "VERSION", "--commits", "commits.log",
         "--changelog", "CHANGELOG.md", "--date", "2026-06-26"],
        cwd=str(tmp_path),
    )
    assert result.returncode == 0, result.stderr
    assert "NEW_VERSION=3.2.1" in result.stdout
    assert "No release" in result.stdout
    # Version file is untouched when nothing warrants a bump.
    assert (tmp_path / "VERSION").read_text().strip() == "3.2.1"


def test_cli_missing_file_exits_nonzero_with_message(tmp_path):
    result = _run(
        ["--version-file", "VERSION", "--commits", "commits.log",
         "--changelog", "CHANGELOG.md"],
        cwd=str(tmp_path),
    )
    assert result.returncode != 0
    assert "Version file not found" in result.stderr
