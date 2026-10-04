"""Guards on .github/dependabot.yml's suppression of benchmark output under results/.

results/ holds manifests the benchmark's agents wrote (AGENTS.md: "Never fix
agent-generated code"). Dependabot security updates opened PRs against them
anyway (GHA-bench#92 and #93), because security updates act on every alert the
dependency graph raises, configured or not. dependabot.yml now carries one
entry per ecosystem found under results/ that matches every directory there
and suppresses both update kinds:

- `open-pull-requests-limit: 0` stops version updates (security updates are
  exempt from that limit), and
- `ignore: [{dependency-name: "*"}]` stops security updates, which honor
  `ignore` for an entry whose `directories` match and that sets no
  `target-branch`.

https://docs.github.com/en/code-security/reference/supply-chain-security/dependabot-options-reference
https://docs.github.com/en/code-security/how-tos/secure-your-supply-chain/secure-your-dependencies/configure-security-updates

Parsed with PyYAML, never line-scanned, for the reason tests/test_ci_workflow.py
gives.
"""

import subprocess
from pathlib import Path

import pytest
import yaml

REPO_ROOT = Path(__file__).resolve().parent.parent
DEPENDABOT_PATH = REPO_ROOT / ".github" / "dependabot.yml"
RESULTS_GLOB = "/results/**/*"

# Manifest/lockfile name -> the Dependabot ecosystem that reads it. Applied to
# `git ls-files results/` to find which ecosystems actually have manifests
# under results/, so a future run that commits, say, a Cargo.toml fails here
# until it is suppressed too.
_EXACT_MANIFESTS = {
    "package.json": "npm",
    "package-lock.json": "npm",
    "npm-shrinkwrap.json": "npm",
    "yarn.lock": "npm",
    "pnpm-lock.yaml": "npm",
    "bun.lock": "bun",
    "bun.lockb": "bun",
    "uv.lock": "uv",
    "setup.py": "pip",
    "setup.cfg": "pip",
    "pyproject.toml": "pip",
    "Pipfile": "pip",
    "Pipfile.lock": "pip",
    "poetry.lock": "pip",
    "packages.config": "nuget",
    "global.json": "dotnet-sdk",
    "Gemfile": "bundler",
    "Gemfile.lock": "bundler",
    "go.mod": "gomod",
    "Cargo.toml": "cargo",
    "Cargo.lock": "cargo",
    "composer.json": "composer",
    "composer.lock": "composer",
    "pom.xml": "maven",
    "build.gradle": "gradle",
    "build.gradle.kts": "gradle",
}


def _ecosystem_for(name):
    if name in _EXACT_MANIFESTS:
        return _EXACT_MANIFESTS[name]
    if name.startswith("requirements") and name.endswith(".txt"):
        return "pip"
    if name.endswith((".csproj", ".fsproj", ".vbproj")):
        return "nuget"
    return None


def _load_updates():
    assert DEPENDABOT_PATH.is_file(), f"{DEPENDABOT_PATH} is missing."
    doc = yaml.safe_load(DEPENDABOT_PATH.read_text(encoding="utf-8"))
    assert isinstance(doc, dict) and doc.get("version") == 2, f"{DEPENDABOT_PATH} is not a v2 config."
    updates = doc.get("updates")
    assert isinstance(updates, list) and updates, f"{DEPENDABOT_PATH} declares no updates."
    for entry in updates:
        assert isinstance(entry, dict), f"non-mapping entry in updates: {entry!r}"
    return updates


def _dirs(entry):
    dirs = list(entry.get("directories") or [])
    if entry.get("directory") is not None:
        dirs.append(entry["directory"])
    return dirs


def _touches_results(entry):
    return any(str(d).lstrip("/").split("/", 1)[0] == "results" for d in _dirs(entry))


def _tracked_results_files():
    out = subprocess.run(
        ["git", "-C", str(REPO_ROOT), "ls-files", "-z", "--", "results/"],
        check=True,
        capture_output=True,
        text=True,
    ).stdout
    return [p for p in out.split("\0") if p]


def _ecosystems_under_results():
    found = set()
    for path in _tracked_results_files():
        eco = _ecosystem_for(path.rsplit("/", 1)[-1])
        if eco:
            found.add(eco)
    return found


@pytest.mark.parametrize(
    "name, ecosystem",
    [
        ("package.json", "npm"),
        ("bun.lock", "bun"),
        ("uv.lock", "uv"),
        ("requirements-dev.txt", "pip"),
        ("pyproject.toml", "pip"),
        ("Cargo.toml", "cargo"),
        ("go.mod", "gomod"),
        ("composer.json", "composer"),
        ("Gemfile.lock", "bundler"),
        ("pom.xml", "maven"),
        ("build.gradle.kts", "gradle"),
        ("App.csproj", "nuget"),
        ("global.json", "dotnet-sdk"),
        ("README.md", None),
    ],
)
def test_manifest_name_maps_to_ecosystem(name, ecosystem):
    assert _ecosystem_for(name) == ecosystem


def test_results_holds_manifests_at_all():
    """Vacuity floor: if this ever finds nothing, the coverage test proves nothing."""
    assert _ecosystems_under_results() >= {"npm", "pip"}


def _assert_suppression_shape(entry):
    eco = entry.get("package-ecosystem")
    assert _dirs(entry) == [RESULTS_GLOB], (
        f"{eco}: a suppression entry must use exactly directories: [{RESULTS_GLOB!r}] "
        f"(`directory:` takes no glob); got {_dirs(entry)!r}."
    )
    assert entry.get("open-pull-requests-limit") == 0, (
        f"{eco}: open-pull-requests-limit must be 0, or version updates open PRs "
        "against benchmark output."
    )
    assert entry.get("ignore") == [{"dependency-name": "*"}], (
        f"{eco}: ignore must be exactly [{{dependency-name: '*'}}]; a `versions:` or "
        f"`update-types:` key narrows it and lets updates through. Got {entry.get('ignore')!r}."
    )
    assert "target-branch" not in entry, f"{eco}: security updates disregard an entry that sets target-branch."
    assert "allow" not in entry, f"{eco}: a suppression entry has no business allowing anything."


def test_every_ecosystem_under_results_has_a_suppression_entry():
    """Each ecosystem found by `git ls-files results/` has exactly one entry of the exact shape."""
    entries = [e for e in _load_updates() if _touches_results(e)]
    for eco in sorted(_ecosystems_under_results()):
        mine = [e for e in entries if e.get("package-ecosystem") == eco]
        assert len(mine) == 1, (
            f"results/ holds {eco} manifests but .github/dependabot.yml has {len(mine)} "
            f"suppression entries for it (want 1); shape it like the npm entry ({RESULTS_GLOB!r}, "
            "open-pull-requests-limit: 0, ignore dependency-name '*')."
        )
        _assert_suppression_shape(mine[0])


def test_every_entry_naming_results_suppresses_both_update_kinds():
    entries = [e for e in _load_updates() if _touches_results(e)]
    assert entries, "no dependabot.yml entry covers results/ at all."
    seen = []
    for entry in entries:
        seen.append(entry.get("package-ecosystem"))
        _assert_suppression_shape(entry)
    assert len(seen) == len(set(seen)), f"duplicate results/ suppression entries: {seen}"


def test_no_other_entry_reaches_into_results():
    """Only suppression entries may name results/; everything else stays at the root."""
    for entry in _load_updates():
        if _touches_results(entry):
            continue
        for d in _dirs(entry):
            assert "results" not in str(d).split("/"), f"{entry.get('package-ecosystem')}: {d!r}"
            assert "*" not in str(d), (
                f"{entry.get('package-ecosystem')}: glob {d!r} could reach results/."
            )
