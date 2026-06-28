# Shared catalogue of end-to-end test cases for the act workflow harness.
#
# Returned as an array of hashtables. This file is invoked (`& cases.ps1`) from
# BOTH Pester phases of Workflow.Tests.ps1 - discovery (to drive -ForEach) and
# run (to feed the act loop) - because data set in one phase does not flow into
# the other. Keeping the cases here means there is a single source of truth.
#
# Each fixture is self-contained (embeds referenceDate + warningDays) so the
# workflow output is fully deterministic. The Expected values were computed from
# the validator and are asserted EXACTLY by the harness.

@(
    @{
        Name     = 'mixed-urgency'
        Fixture  = @'
{
  "referenceDate": "2026-06-27",
  "warningDays": 14,
  "secrets": [
    { "name": "db-password",         "lastRotated": "2026-01-01", "rotationPolicyDays": 90,  "requiredBy": ["payments-api", "reporting-worker"] },
    { "name": "signing-key",         "lastRotated": "2025-06-01", "rotationPolicyDays": 180, "requiredBy": ["auth-service"] },
    { "name": "tls-cert",            "lastRotated": "2026-04-06", "rotationPolicyDays": 90,  "requiredBy": ["edge-gateway"] },
    { "name": "service-account-key", "lastRotated": "2026-01-01", "rotationPolicyDays": 365, "requiredBy": ["batch-pipeline"] },
    { "name": "oauth-client-secret", "lastRotated": "2026-06-20", "rotationPolicyDays": 30,  "requiredBy": ["mobile-app", "web-app"] }
  ]
}
'@
        Expected = @{
            Summary      = 'ROTATION_SUMMARY expired=2 warning=1 ok=2 total=5'
            ExpiredNames = 'EXPIRED_NAMES=signing-key,db-password'
            WarningNames = 'WARNING_NAMES=tls-cert'
        }
    },
    @{
        Name     = 'all-ok'
        Fixture  = @'
{
  "referenceDate": "2026-06-27",
  "warningDays": 14,
  "secrets": [
    { "name": "alpha", "lastRotated": "2026-06-01", "rotationPolicyDays": 365, "requiredBy": ["svc-a"] },
    { "name": "beta",  "lastRotated": "2026-05-01", "rotationPolicyDays": 200, "requiredBy": ["svc-b"] }
  ]
}
'@
        Expected = @{
            Summary      = 'ROTATION_SUMMARY expired=0 warning=0 ok=2 total=2'
            ExpiredNames = 'EXPIRED_NAMES='
            WarningNames = 'WARNING_NAMES='
        }
    },
    @{
        Name     = 'all-expired'
        Fixture  = @'
{
  "referenceDate": "2026-06-27",
  "warningDays": 14,
  "secrets": [
    { "name": "gamma",   "lastRotated": "2026-01-01", "rotationPolicyDays": 90, "requiredBy": ["svc-g"] },
    { "name": "delta",   "lastRotated": "2025-06-01", "rotationPolicyDays": 90, "requiredBy": ["svc-d"] },
    { "name": "epsilon", "lastRotated": "2026-03-01", "rotationPolicyDays": 30, "requiredBy": ["svc-e"] }
  ]
}
'@
        Expected = @{
            Summary      = 'ROTATION_SUMMARY expired=3 warning=0 ok=0 total=3'
            ExpiredNames = 'EXPIRED_NAMES=delta,epsilon,gamma'
            WarningNames = 'WARNING_NAMES='
        }
    }
)
