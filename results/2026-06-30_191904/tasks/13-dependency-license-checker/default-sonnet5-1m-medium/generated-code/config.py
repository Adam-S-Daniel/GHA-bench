"""Load the license allow-list/deny-list configuration file (JSON)."""
import json
import os
from dataclasses import dataclass, field


class ConfigError(Exception):
    """Raised when the license config file is missing or malformed."""


@dataclass
class LicenseConfig:
    allow_list: list = field(default_factory=list)
    deny_list: list = field(default_factory=list)


def load_license_config(path):
    if not os.path.isfile(path):
        raise ConfigError(f"License config file not found: {path}")

    with open(path, "r", encoding="utf-8") as fh:
        raw = fh.read()

    try:
        data = json.loads(raw)
    except json.JSONDecodeError as exc:
        raise ConfigError(f"Invalid JSON in {path}: {exc}") from exc

    allow_list = data.get("allow", [])
    deny_list = data.get("deny", [])

    overlap = set(allow_list) & set(deny_list)
    if overlap:
        raise ConfigError(
            f"License(s) {sorted(overlap)} appear in both allow and deny lists in {path}"
        )

    return LicenseConfig(allow_list=allow_list, deny_list=deny_list)
