"""Artifact retention planner.

Given a list of CI artifacts (name, size, creation date, workflow run id),
apply retention policies and produce a deletion plan:

  1. max_age_days     - artifacts older than this are deleted.
  2. keep_latest_n    - within each workflow run, only the N newest
                        artifacts are kept (older siblings are deleted).
  3. max_total_bytes  - if the retained set still exceeds this budget,
                        the oldest retained artifacts are deleted until
                        the total fits.

Policies are applied in that order; every deletion records which policy
caused it. The planner never mutates anything itself - it only produces
a plan - so "dry run" vs "execute" is a concern of the caller (the CLI).
"""

import argparse
import json
import sys
from dataclasses import dataclass, field
from datetime import datetime, timezone


class CleanupError(Exception):
    """Raised for any invalid input; the message is user-facing."""


@dataclass(frozen=True)
class Artifact:
    """One CI artifact and the metadata the policies need."""

    name: str
    size_bytes: int
    created_at: datetime
    workflow_run_id: int


@dataclass(frozen=True)
class RetentionPolicy:
    """Knobs for the cleanup. Any policy left as None is not applied."""

    max_age_days: int | None = None
    keep_latest_n: int | None = None
    max_total_bytes: int | None = None


@dataclass
class Plan:
    """The outcome: which artifacts survive, which are deleted, and why."""

    retained: list = field(default_factory=list)
    deleted: list = field(default_factory=list)
    reasons: dict = field(default_factory=dict)  # artifact name -> reason string

    def delete(self, artifact, reason):
        self.deleted.append(artifact)
        self.reasons[artifact.name] = reason

    def summary(self):
        """Aggregate numbers for reporting: counts and byte totals."""
        return {
            "retained_count": len(self.retained),
            "deleted_count": len(self.deleted),
            "space_reclaimed_bytes": sum(a.size_bytes for a in self.deleted),
            "retained_bytes": sum(a.size_bytes for a in self.retained),
        }


def parse_artifacts(records):
    """Turn a list of raw dicts (mock API data) into validated Artifacts.

    Every problem is reported as a CleanupError naming the offending
    record by 1-based index, so users can find it in their input file.
    """
    if not isinstance(records, list):
        raise CleanupError("artifact data must be a JSON array of objects")

    artifacts = []
    for i, record in enumerate(records, start=1):
        if not isinstance(record, dict):
            raise CleanupError(f"artifact #{i} is not an object")
        for key in ("name", "size_bytes", "created_at", "workflow_run_id"):
            if key not in record:
                raise CleanupError(f"artifact #{i} is missing required field '{key}'")

        size = record["size_bytes"]
        if not isinstance(size, int) or isinstance(size, bool) or size < 0:
            raise CleanupError(
                f"artifact #{i} ('{record['name']}'): "
                "size_bytes must be a non-negative integer"
            )

        try:
            created = datetime.fromisoformat(str(record["created_at"]).replace("Z", "+00:00"))
        except ValueError:
            raise CleanupError(
                f"artifact #{i} ('{record['name']}'): "
                f"invalid created_at '{record['created_at']}' (expected ISO 8601)"
            ) from None

        artifacts.append(
            Artifact(
                name=str(record["name"]),
                size_bytes=size,
                created_at=created,
                workflow_run_id=record["workflow_run_id"],
            )
        )
    return artifacts


def build_plan(artifacts, policy, now):
    """Apply `policy` to `artifacts` and return a Plan (pure function).

    Policies run in order: max-age, then keep-latest-N per workflow run,
    then the total-size budget on whatever survived the first two.
    """
    plan = Plan()

    # Pass 1: keep-latest-N. Rank each artifact among its workflow-run
    # siblings, newest first; anything ranked past N is over the limit.
    over_latest_limit = set()
    if policy.keep_latest_n is not None:
        by_run = {}
        for artifact in artifacts:
            by_run.setdefault(artifact.workflow_run_id, []).append(artifact)
        for siblings in by_run.values():
            siblings.sort(key=lambda a: a.created_at, reverse=True)
            over_latest_limit.update(a.name for a in siblings[policy.keep_latest_n:])

    # Pass 2: classify by age and the latest-N limit (age wins as the reason).
    survivors = []
    for artifact in artifacts:
        age_days = (now - artifact.created_at).days
        if policy.max_age_days is not None and age_days > policy.max_age_days:
            plan.delete(artifact, f"exceeds max age of {policy.max_age_days} days")
        elif artifact.name in over_latest_limit:
            plan.delete(
                artifact,
                f"exceeds keep-latest-{policy.keep_latest_n} "
                f"for workflow run {artifact.workflow_run_id}",
            )
        else:
            survivors.append(artifact)

    # Pass 3: total-size budget. Evict the oldest survivors first until the
    # remaining total fits the budget.
    if policy.max_total_bytes is not None:
        total = sum(a.size_bytes for a in survivors)
        for artifact in sorted(survivors, key=lambda a: a.created_at):
            if total <= policy.max_total_bytes:
                break
            plan.delete(
                artifact,
                "evicted to satisfy total size budget of "
                f"{policy.max_total_bytes} bytes",
            )
            survivors.remove(artifact)
            total -= artifact.size_bytes

    plan.retained = survivors
    return plan


# --------------------------------------------------------------------------
# CLI layer
# --------------------------------------------------------------------------

def _parse_args(argv):
    parser = argparse.ArgumentParser(
        prog="artifact_cleanup",
        description="Plan (and mock-execute) CI artifact deletion under retention policies.",
    )
    parser.add_argument("--input", required=True, help="JSON file with the artifact list")
    parser.add_argument("--max-age-days", type=int, default=None,
                        help="delete artifacts older than this many days")
    parser.add_argument("--keep-latest", type=int, default=None,
                        help="keep only the N newest artifacts per workflow run")
    parser.add_argument("--max-total-size", type=int, default=None,
                        help="total retained size budget in bytes")
    parser.add_argument("--now", default=None,
                        help="ISO 8601 reference time (defaults to current UTC time)")
    parser.add_argument("--dry-run", action="store_true",
                        help="print the plan without performing deletions")
    parser.add_argument("--output", default=None,
                        help="also write the full plan as JSON to this file")
    return parser.parse_args(argv)


def _load_records(path):
    """Read and JSON-decode the input file, with user-friendly errors."""
    try:
        with open(path, encoding="utf-8") as fh:
            raw = fh.read()
    except OSError as exc:
        raise CleanupError(f"cannot read input file '{path}': {exc.strerror}") from None
    try:
        return json.loads(raw)
    except json.JSONDecodeError as exc:
        raise CleanupError(f"input file '{path}' is not valid JSON: {exc}") from None


def _delete_artifact(artifact):
    """Mock deletion: the data is synthetic, so 'deleting' just reports.

    In a real integration this is the single seam to swap for a call to
    the GitHub API (DELETE /repos/{o}/{r}/actions/artifacts/{id}).
    """
    print(f"Deleted artifact '{artifact.name}'")


def run_cli(argv=None):
    """Entry point. Returns a process exit code (0 ok, 2 bad input)."""
    args = _parse_args(argv)
    try:
        if args.now is not None:
            try:
                now = datetime.fromisoformat(args.now.replace("Z", "+00:00"))
            except ValueError:
                raise CleanupError(
                    f"invalid --now value '{args.now}' (expected ISO 8601)"
                ) from None
        else:
            now = datetime.now(timezone.utc)

        artifacts = parse_artifacts(_load_records(args.input))
        policy = RetentionPolicy(
            max_age_days=args.max_age_days,
            keep_latest_n=args.keep_latest,
            max_total_bytes=args.max_total_size,
        )
        plan = build_plan(artifacts, policy, now=now)
    except CleanupError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2

    mode = "DRY RUN - nothing will be deleted" if args.dry_run else "EXECUTE"
    print(f"Artifact cleanup plan ({mode})")
    for artifact in plan.deleted:
        print(f"DELETE {artifact.name} ({artifact.size_bytes} bytes) "
              f"- {plan.reasons[artifact.name]}")
    for artifact in plan.retained:
        print(f"KEEP   {artifact.name} ({artifact.size_bytes} bytes)")

    if not args.dry_run:
        for artifact in plan.deleted:
            _delete_artifact(artifact)

    # Machine-parseable summary block (asserted on by the CI pipeline tests).
    summary = plan.summary()
    print(f"RETAINED_COUNT={summary['retained_count']}")
    print(f"DELETED_COUNT={summary['deleted_count']}")
    print(f"SPACE_RECLAIMED_BYTES={summary['space_reclaimed_bytes']}")
    print(f"RETAINED_BYTES={summary['retained_bytes']}")
    print(f"DRY_RUN={'true' if args.dry_run else 'false'}")

    if args.output:
        plan_json = {
            "dry_run": args.dry_run,
            "summary": summary,
            "delete": [
                {"name": a.name, "size_bytes": a.size_bytes,
                 "workflow_run_id": a.workflow_run_id,
                 "reason": plan.reasons[a.name]}
                for a in plan.deleted
            ],
            "retain": [
                {"name": a.name, "size_bytes": a.size_bytes,
                 "workflow_run_id": a.workflow_run_id}
                for a in plan.retained
            ],
        }
        with open(args.output, "w", encoding="utf-8") as fh:
            json.dump(plan_json, fh, indent=2)

    return 0


if __name__ == "__main__":
    sys.exit(run_cli())
