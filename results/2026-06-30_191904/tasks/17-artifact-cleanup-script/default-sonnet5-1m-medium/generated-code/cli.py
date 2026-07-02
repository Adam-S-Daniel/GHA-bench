"""
Command-line entry point for the artifact-cleanup planner.

Loads artifact metadata from a JSON fixture file, builds a RetentionPolicy
from CLI flags, computes a deletion plan, and prints a human-readable report
plus a machine-parseable "SUMMARY: ..." line that CI can grep/assert on.

Usage:
    python3 cli.py --fixture artifacts.json --max-age-days 30 --dry-run
"""
import argparse
import json
import sys
from datetime import datetime, timezone

from artifact_cleanup import (
    Artifact,
    RetentionPolicy,
    execute_plan,
    plan_deletions,
)


def _load_artifacts(fixture_path: str) -> list:
    try:
        with open(fixture_path, "r", encoding="utf-8") as f:
            raw = json.load(f)
    except FileNotFoundError as exc:
        raise ValueError(f"Fixture file not found: {fixture_path}") from exc
    except json.JSONDecodeError as exc:
        raise ValueError(f"Fixture file '{fixture_path}' is not valid JSON: {exc}") from exc

    artifacts = []
    for i, entry in enumerate(raw):
        try:
            artifacts.append(
                Artifact(
                    name=entry["name"],
                    size_bytes=entry["size_bytes"],
                    created_at=datetime.fromisoformat(entry["created_at"]),
                    workflow_run_id=entry["workflow_run_id"],
                )
            )
        except KeyError as exc:
            raise ValueError(f"Fixture entry #{i} is missing required field: {exc}") from exc
    return artifacts


def _mock_deleter(artifact: Artifact) -> None:
    """Stand-in for a real artifact-storage delete API call."""
    print(f"  deleted: {artifact.name}")


def build_arg_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Plan and (optionally) execute artifact retention cleanup.")
    parser.add_argument("--fixture", required=True, help="Path to a JSON file with artifact metadata.")
    parser.add_argument("--now", help="ISO-8601 timestamp to treat as 'now' (defaults to current UTC time).")
    parser.add_argument("--max-age-days", type=int, default=None)
    parser.add_argument("--max-total-size-bytes", type=int, default=None)
    parser.add_argument("--keep-latest-n-per-workflow", type=int, default=None)
    parser.add_argument("--dry-run", action="store_true", help="Report the plan without deleting anything.")
    return parser


def main(argv=None) -> int:
    parser = build_arg_parser()
    args = parser.parse_args(argv)

    try:
        artifacts = _load_artifacts(args.fixture)
        now = datetime.fromisoformat(args.now) if args.now else datetime.now(timezone.utc)
        policy = RetentionPolicy(
            max_age_days=args.max_age_days,
            max_total_size_bytes=args.max_total_size_bytes,
            keep_latest_n_per_workflow=args.keep_latest_n_per_workflow,
        )
        plan = plan_deletions(artifacts, policy, now=now)
    except ValueError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1

    print("DRY RUN" if args.dry_run else "LIVE RUN")
    print(f"Artifacts to delete ({len(plan.to_delete)}):")
    for art in plan.to_delete:
        print(f"  - {art.name} ({art.size_bytes} bytes, workflow={art.workflow_run_id})")
    print(f"Artifacts to retain ({len(plan.to_retain)}):")
    for art in plan.to_retain:
        print(f"  - {art.name} ({art.size_bytes} bytes, workflow={art.workflow_run_id})")

    result = execute_plan(plan, deleter=_mock_deleter, dry_run=args.dry_run)
    for error in result.errors:
        print(f"ERROR: {error}", file=sys.stderr)

    summary = plan.summary()
    print(
        "SUMMARY: "
        f"artifacts_deleted={summary['artifacts_deleted']} "
        f"artifacts_retained={summary['artifacts_retained']} "
        f"space_reclaimed_bytes={summary['space_reclaimed_bytes']}"
    )

    return 1 if result.errors else 0


if __name__ == "__main__":
    sys.exit(main())
