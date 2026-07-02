"""
Parsers for dependency manifests (package.json, requirements.txt).

Each parser returns a plain dict of {dependency_name: version_spec}.
Version specs are kept as-is from the manifest (e.g. "^1.3.0", "==2.31.0"
is normalized to "2.31.0") so downstream consumers decide how to interpret
range operators.
"""
import json
import os
import re


class ManifestParseError(Exception):
    """Raised when a manifest file cannot be read or parsed."""


def _read_file(path):
    if not os.path.isfile(path):
        raise ManifestParseError(f"Manifest file not found: {path}")
    with open(path, "r", encoding="utf-8") as fh:
        return fh.read()


def parse_package_json(path):
    """Parse an npm package.json, merging dependencies + devDependencies."""
    raw = _read_file(path)
    try:
        data = json.loads(raw)
    except json.JSONDecodeError as exc:
        raise ManifestParseError(f"Invalid JSON in {path}: {exc}") from exc

    deps = {}
    deps.update(data.get("dependencies", {}) or {})
    deps.update(data.get("devDependencies", {}) or {})
    return deps


# Matches "name==1.2.3", "name>=1.2.3", "name~=1.2.3", or bare "name"
_REQ_LINE_RE = re.compile(
    r"^\s*([A-Za-z0-9._-]+)\s*(==|>=|<=|~=|!=|>|<)?\s*([A-Za-z0-9._-]*)\s*$"
)


def parse_requirements_txt(path):
    """Parse a pip requirements.txt into {name: version}. Unpinned -> '*'."""
    raw = _read_file(path)
    deps = {}
    for line in raw.splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("#") or stripped.startswith("-"):
            continue
        match = _REQ_LINE_RE.match(stripped)
        if not match:
            continue
        name, _op, version = match.groups()
        deps[name] = version if version else "*"
    return deps


_PARSERS_BY_FILENAME = {
    "package.json": parse_package_json,
    "requirements.txt": parse_requirements_txt,
}


def parse_manifest(path):
    """Dispatch to the right parser based on the manifest's filename."""
    basename = os.path.basename(path)
    parser = _PARSERS_BY_FILENAME.get(basename)
    if parser is None:
        raise ManifestParseError(
            f"Unsupported manifest type: {basename!r}. "
            f"Supported types: {sorted(_PARSERS_BY_FILENAME)}"
        )
    return parser(path)
