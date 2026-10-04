"""Keep the GitHub Actions cooldown within Dependabot's supported schema."""

from pathlib import Path

import yaml


def test_github_actions_uses_supported_cooldown_fields():
    config = yaml.safe_load(
        (Path(__file__).resolve().parents[1] / ".github" / "dependabot.yml").read_text()
    )
    actions = [
        update for update in config["updates"]
        if update["package-ecosystem"] == "github-actions"
    ]
    assert actions, "No GitHub Actions configuration was checked"
    for update in actions:
        cooldown = update["cooldown"]
        assert cooldown["default-days"] == 7
        assert not {"semver-major-days", "semver-minor-days", "semver-patch-days"} & cooldown.keys()
