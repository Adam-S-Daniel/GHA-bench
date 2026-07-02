"""Render compliance results as human-readable text or machine-readable JSON."""
import json

from license_checker import LicenseStatus


def _summary_counts(results):
    counts = {LicenseStatus.APPROVED: 0, LicenseStatus.DENIED: 0, LicenseStatus.UNKNOWN: 0}
    for r in results:
        counts[r["status"]] += 1
    return counts


def generate_text_report(results):
    lines = ["Dependency License Compliance Report", "=" * 38, ""]
    for r in results:
        license_display = r["license"] or "UNKNOWN"
        lines.append(
            f"  {r['name']}@{r['version']}: {license_display} -> {r['status'].upper()}"
        )
        if r.get("error"):
            lines.append(f"    reason: {r['error']}")

    counts = _summary_counts(results)
    lines += [
        "",
        "Summary:",
        f"  Approved: {counts[LicenseStatus.APPROVED]}",
        f"  Denied: {counts[LicenseStatus.DENIED]}",
        f"  Unknown: {counts[LicenseStatus.UNKNOWN]}",
    ]
    return "\n".join(lines)


def generate_json_report(results):
    counts = _summary_counts(results)
    payload = {
        "summary": {
            "approved": counts[LicenseStatus.APPROVED],
            "denied": counts[LicenseStatus.DENIED],
            "unknown": counts[LicenseStatus.UNKNOWN],
        },
        "dependencies": results,
    }
    return json.dumps(payload, indent=2)


def compliance_exit_code(results):
    """Non-zero (CI-failing) exit code if any dependency has a denied license."""
    return 1 if any(r["status"] == LicenseStatus.DENIED for r in results) else 0
