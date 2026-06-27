"""
Red/green TDD — unit 1: urgency classification.

The heart of the validator is deciding, for a single secret, whether it is
`expired`, in the `warning` window, or `ok`. We test that pure function first
before building anything else around it.
"""
import datetime

from secret_rotation_validator import classify_secret


def test_expired_when_past_next_rotation():
    # last rotated 2026-01-01, policy 90 days -> due 2026-04-01, which is in the
    # past relative to "now" (2026-06-27), so the secret is expired.
    secret = {
        "name": "DB_PASSWORD",
        "last_rotated": "2026-01-01",
        "rotation_policy_days": 90,
        "required_by": ["api"],
    }
    result = classify_secret(secret, now=datetime.date(2026, 6, 27), warning_days=14)
    assert result["status"] == "expired"
    assert result["next_rotation"] == "2026-04-01"
    assert result["days_until_rotation"] == -87


def test_warning_when_inside_window():
    # due 2026-06-30, which is 3 days away -> inside the 14-day warning window.
    secret = {
        "name": "API_KEY",
        "last_rotated": "2026-04-01",
        "rotation_policy_days": 90,
        "required_by": ["worker"],
    }
    result = classify_secret(secret, now=datetime.date(2026, 6, 27), warning_days=14)
    assert result["status"] == "warning"
    assert result["days_until_rotation"] == 3


def test_ok_when_outside_window():
    secret = {
        "name": "TLS_CERT",
        "last_rotated": "2026-06-01",
        "rotation_policy_days": 90,
        "required_by": ["gateway"],
    }
    result = classify_secret(secret, now=datetime.date(2026, 6, 27), warning_days=14)
    assert result["status"] == "ok"
    assert result["days_until_rotation"] == 64
