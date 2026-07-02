"""
Core compliance logic: given dependencies + a license lookup + an
allow-list/deny-list, classify each dependency as approved, denied, or
unknown.

The license lookup is injected as a callable (name, version) -> license_name
or None, so it can be mocked in tests and swapped for a real registry
lookup (npm/PyPI) in production without touching this module.
"""


class LicenseLookupError(Exception):
    """Raised by a lookup callable when it cannot determine a license."""


class LicenseStatus:
    APPROVED = "approved"
    DENIED = "denied"
    UNKNOWN = "unknown"


def check_dependency(name, version, lookup, allow_list, deny_list):
    """Classify a single dependency's license against the allow/deny lists.

    Deny-list wins over allow-list on conflict (fail closed). A lookup
    miss (None) or a lookup error both result in UNKNOWN, since we can't
    prove compliance without knowing the license.
    """
    error = None
    try:
        license_name = lookup(name, version)
    except LicenseLookupError as exc:
        license_name = None
        error = str(exc)

    if license_name is not None and license_name in deny_list:
        status = LicenseStatus.DENIED
    elif license_name is not None and license_name in allow_list:
        status = LicenseStatus.APPROVED
    else:
        status = LicenseStatus.UNKNOWN

    result = {
        "name": name,
        "version": version,
        "license": license_name,
        "status": status,
    }
    if error:
        result["error"] = error
    return result


def check_compliance(dependencies, lookup, allow_list, deny_list):
    """Check every dependency, returning results sorted by name."""
    results = [
        check_dependency(name, version, lookup, allow_list, deny_list)
        for name, version in dependencies.items()
    ]
    return sorted(results, key=lambda r: r["name"])
