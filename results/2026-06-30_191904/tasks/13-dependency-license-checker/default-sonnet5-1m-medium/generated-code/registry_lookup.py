"""
Real license lookups against public package registries (npm, PyPI).

`_fetch_json` is the single network-touching seam; tests monkeypatch it
so the parsing logic in `npm_license_lookup`/`pypi_license_lookup` is
fully exercised without any real HTTP calls.
"""
import json
import os
import re
import urllib.request

from license_checker import LicenseLookupError

_CLASSIFIER_RE = re.compile(r"^License :: OSI Approved :: (.+?)(?: License)?$")


def _fetch_json(url):
    with urllib.request.urlopen(url, timeout=10) as resp:
        return json.loads(resp.read().decode("utf-8"))


def npm_license_lookup(name, version):
    """Look up a package's license on the npm registry."""
    url = f"https://registry.npmjs.org/{name}/{version}"
    try:
        data = _fetch_json(url)
    except Exception as exc:
        raise LicenseLookupError(f"npm lookup failed for {name}@{version}: {exc}") from exc

    license_field = data.get("license")
    if isinstance(license_field, dict):
        return license_field.get("type")
    return license_field


def pypi_license_lookup(name, version):
    """Look up a package's license on PyPI, preferring trove classifiers."""
    url = f"https://pypi.org/pypi/{name}/{version}/json"
    try:
        data = _fetch_json(url)
    except Exception as exc:
        raise LicenseLookupError(f"PyPI lookup failed for {name}@{version}: {exc}") from exc

    info = data.get("info", {})
    for classifier in info.get("classifiers", []):
        match = _CLASSIFIER_RE.match(classifier)
        if match:
            return match.group(1)

    return info.get("license") or None


def fixture_license_lookup(data_path):
    """Build a lookup backed by a local {name: license} JSON file.

    Useful for offline/CI runs (e.g. this project's own GitHub Actions
    workflow) where hitting real registries would be slow or flaky.
    """
    if not os.path.isfile(data_path):
        raise LicenseLookupError(f"License fixture data file not found: {data_path}")

    with open(data_path, "r", encoding="utf-8") as fh:
        licenses = json.load(fh)

    def lookup(name, version):
        return licenses.get(name)

    return lookup


_LOOKUPS_BY_ECOSYSTEM = {
    "npm": npm_license_lookup,
    "pypi": pypi_license_lookup,
}


def make_registry_lookup(ecosystem):
    """Return the license lookup callable for the given ecosystem."""
    lookup = _LOOKUPS_BY_ECOSYSTEM.get(ecosystem)
    if lookup is None:
        raise ValueError(
            f"Unsupported ecosystem: {ecosystem!r}. Supported: {sorted(_LOOKUPS_BY_ECOSYSTEM)}"
        )
    return lookup
