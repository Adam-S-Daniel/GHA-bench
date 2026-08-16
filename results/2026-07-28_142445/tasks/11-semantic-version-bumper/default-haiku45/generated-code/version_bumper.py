#!/usr/bin/env python3
"""
Semantic version bumper: parse versions, determine next version based on
conventional commits, update files, and generate changelogs.
"""
import json
import re
from pathlib import Path
from typing import Dict, List, Any, Union


def parse_version(version_input: str) -> Dict[str, int]:
    """
    Parse a semantic version string or read from a file.

    Handles:
    - Version strings: "1.2.3" or "v1.2.3"
    - Files: "package.json" or "VERSION"

    Returns: {"major": int, "minor": int, "patch": int}
    """
    # If it looks like a file path that exists, read from file
    input_path = Path(version_input)

    if input_path.exists():
        if input_path.name == "package.json":
            # Read from package.json
            data = json.loads(input_path.read_text())
            version_string = data.get("version", "0.0.0")
        else:
            # Read from VERSION file
            version_string = input_path.read_text().strip()
    else:
        # It's a version string
        version_string = version_input

    # Remove 'v' prefix if present
    version_string = version_string.lstrip('v')

    # Parse semantic version
    match = re.match(r'(\d+)\.(\d+)\.(\d+)', version_string)
    if not match:
        raise ValueError(f"Invalid semantic version: {version_string}")

    return {
        "major": int(match.group(1)),
        "minor": int(match.group(2)),
        "patch": int(match.group(3)),
    }


def determine_next_version(
    current: Dict[str, int],
    commits: List[Dict[str, Any]]
) -> Dict[str, int]:
    """
    Determine next version based on conventional commit types.

    Priority (highest to lowest):
    - breaking: bump major, reset minor and patch
    - feat: bump minor, reset patch
    - fix: bump patch
    - other (docs, chore, etc): no change

    Args:
        current: Current version dict {"major": int, "minor": int, "patch": int}
        commits: List of commit dicts with "type" and optional "breaking" bool

    Returns: Next version dict with same structure
    """
    # Determine highest priority change needed
    has_breaking = any(commit.get("breaking", False) for commit in commits)
    has_feat = any(commit.get("type") == "feat" for commit in commits)
    has_fix = any(commit.get("type") == "fix" for commit in commits)

    if has_breaking:
        return {
            "major": current["major"] + 1,
            "minor": 0,
            "patch": 0,
        }
    elif has_feat:
        return {
            "major": current["major"],
            "minor": current["minor"] + 1,
            "patch": 0,
        }
    elif has_fix:
        return {
            "major": current["major"],
            "minor": current["minor"],
            "patch": current["patch"] + 1,
        }
    else:
        # No functional changes
        return current


def update_version_file(file_path: str, new_version: Dict[str, int]) -> None:
    """
    Update version in a file (package.json or VERSION).

    Args:
        file_path: Path to package.json or VERSION file
        new_version: New version dict
    """
    path = Path(file_path)
    version_string = f"{new_version['major']}.{new_version['minor']}.{new_version['patch']}"

    if path.name == "package.json":
        # Update package.json
        data = json.loads(path.read_text())
        data["version"] = version_string
        path.write_text(json.dumps(data, indent=2))
    else:
        # Update VERSION file
        path.write_text(version_string)


def generate_changelog(
    new_version: str,
    commits: List[Dict[str, Any]]
) -> str:
    """
    Generate changelog entry from commits.

    Groups commits by type (feat, fix, etc.) and formats them.
    Ignores docs, chore, and other non-functional types.

    Args:
        new_version: New version string (e.g., "1.1.0")
        commits: List of commit dicts with "type" and "message"

    Returns: Formatted changelog string
    """
    # Extract message text from full commit message
    def extract_message(commit_msg: str) -> str:
        # Remove type prefix if present (e.g., "feat: " -> "")
        return re.sub(r'^[a-z]+!?: ', '', commit_msg, flags=re.IGNORECASE).strip()

    # Group commits by type
    features = []
    fixes = []

    for commit in commits:
        commit_type = commit.get("type", "").lower()
        message = commit.get("message", "")
        clean_msg = extract_message(message)

        if commit_type == "feat":
            features.append(clean_msg)
        elif commit_type == "fix":
            fixes.append(clean_msg)
        # Ignore docs, chore, and other types

    # Format changelog
    lines = [f"## [{new_version}]"]

    if features:
        lines.append("\n### Features")
        for feat in features:
            lines.append(f"- {feat}")

    if fixes:
        lines.append("\n### Bug Fixes")
        for fix in fixes:
            lines.append(f"- {fix}")

    return "\n".join(lines)


def version_to_string(version: Dict[str, int]) -> str:
    """Convert version dict to string."""
    return f"{version['major']}.{version['minor']}.{version['patch']}"
