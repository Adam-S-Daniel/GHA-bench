"""
Artifact cleanup script: applies retention policies to a list of CI/CD
artifacts (e.g. GitHub Actions artifacts) and produces a deletion plan.

Policies supported:
  - max age: delete artifacts older than N days
  - keep-latest-N per workflow: within each workflow, keep only the N
    most recently created artifacts
  - max total size: evict oldest artifacts until total size is under budget

Usage:
    python3 artifact_cleanup.py --data artifacts.json --max-age-days 90 \
        --max-total-size-bytes 5000000000 --keep-latest-n 5 [--dry-run]
"""
from __future__ import annotations

import argparse
import json
import sys
from dataclasses import dataclass, field
from datetime import datetime
from typing import List, Optional


@dataclass
class Artifact:
    name: str
    size_bytes: int
    created_at: datetime
    workflow_run_id: int
    workflow_name: str = "default"


@dataclass
class DeletionPlan:
    to_delete: List[Artifact] = field(default_factory=list)
    to_retain: List[Artifact] = field(default_factory=list)
    dry_run: bool = False

    @property
    def total_bytes_reclaimed(self) -> int:
        return sum(a.size_bytes for a in self.to_delete)

    @property
    def deleted_count(self) -> int:
        return len(self.to_delete)

    @property
    def retained_count(self) -> int:
        return len(self.to_retain)

    def summary(self) -> str:
        mode = "DRY RUN" if self.dry_run else "APPLIED"
        lines = [
            f"Artifact Cleanup Plan ({mode})",
            f"  Retained: {self.retained_count}",
            f"  Deleted:  {self.deleted_count}",
            f"  Space reclaimed: {self.total_bytes_reclaimed} bytes",
        ]
        return "\n".join(lines)


def apply_max_age_policy(artifacts: List[Artifact], max_age_days: int,
                          now: Optional[datetime] = None) -> List[Artifact]:
    """Return artifacts older than max_age_days (candidates for deletion)."""
    now = now or datetime.now()
    return [a for a in artifacts if (now - a.created_at).days >= max_age_days]


def apply_keep_latest_n_policy(artifacts: List[Artifact],
                                keep_latest_n: int) -> List[Artifact]:
    """Within each workflow_name group, flag all but the N newest artifacts."""
    by_workflow = {}
    for a in artifacts:
        by_workflow.setdefault(a.workflow_name, []).append(a)

    to_delete = []
    for group in by_workflow.values():
        newest_first = sorted(group, key=lambda a: a.created_at, reverse=True)
        to_delete.extend(newest_first[keep_latest_n:])
    return to_delete


def apply_max_total_size_policy(artifacts: List[Artifact],
                                 max_total_size_bytes: int) -> List[Artifact]:
    """Evict oldest artifacts first until total size is under budget."""
    total = sum(a.size_bytes for a in artifacts)
    if total <= max_total_size_bytes:
        return []

    oldest_first = sorted(artifacts, key=lambda a: a.created_at)
    to_delete = []
    for a in oldest_first:
        if total <= max_total_size_bytes:
            break
        to_delete.append(a)
        total -= a.size_bytes
    return to_delete


def build_deletion_plan(artifacts: List[Artifact],
                         max_age_days: Optional[int] = None,
                         max_total_size_bytes: Optional[int] = None,
                         keep_latest_n: Optional[int] = None,
                         now: Optional[datetime] = None,
                         dry_run: bool = False) -> DeletionPlan:
    """Apply all configured policies and produce a combined deletion plan.

    An artifact is deleted if ANY policy flags it. Policies are evaluated
    independently against the full input list (not against each other's
    already-reduced sets), then unioned by artifact identity.
    """
    if max_age_days is not None and max_age_days <= 0:
        raise ValueError("max_age_days must be positive")
    if keep_latest_n is not None and keep_latest_n <= 0:
        raise ValueError("keep_latest_n must be positive")
    if max_total_size_bytes is not None and max_total_size_bytes <= 0:
        raise ValueError("max_total_size_bytes must be positive")

    now = now or datetime.now()
    flagged_ids = set()
    flagged = []

    def flag(candidates):
        for a in candidates:
            key = id(a)
            if key not in flagged_ids:
                flagged_ids.add(key)
                flagged.append(a)

    if max_age_days is not None:
        flag(apply_max_age_policy(artifacts, max_age_days, now=now))
    if keep_latest_n is not None:
        flag(apply_keep_latest_n_policy(artifacts, keep_latest_n))
    if max_total_size_bytes is not None:
        flag(apply_max_total_size_policy(artifacts, max_total_size_bytes))

    to_retain = [a for a in artifacts if id(a) not in flagged_ids]

    # Preserve original ordering for readability in the plan output.
    to_delete = [a for a in artifacts if id(a) in flagged_ids]

    return DeletionPlan(to_delete=to_delete, to_retain=to_retain, dry_run=dry_run)


def _load_artifacts(path: str) -> List[Artifact]:
    with open(path) as f:
        raw = json.load(f)
    artifacts = []
    for item in raw:
        try:
            artifacts.append(Artifact(
                name=item["name"],
                size_bytes=int(item["size_bytes"]),
                created_at=datetime.fromisoformat(item["created_at"]),
                workflow_run_id=int(item["workflow_run_id"]),
                workflow_name=item.get("workflow_name", "default"),
            ))
        except (KeyError, ValueError, TypeError) as e:
            raise ValueError(f"Invalid artifact record {item!r}: {e}") from e
    return artifacts


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description="Apply artifact retention policies.")
    parser.add_argument("--data", required=True, help="Path to JSON artifact list")
    parser.add_argument("--max-age-days", type=int, default=None)
    parser.add_argument("--max-total-size-bytes", type=int, default=None)
    parser.add_argument("--keep-latest-n", type=int, default=None)
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args(argv)

    try:
        artifacts = _load_artifacts(args.data)
        plan = build_deletion_plan(
            artifacts,
            max_age_days=args.max_age_days,
            max_total_size_bytes=args.max_total_size_bytes,
            keep_latest_n=args.keep_latest_n,
            dry_run=args.dry_run,
        )
    except (FileNotFoundError, ValueError, json.JSONDecodeError) as e:
        print(f"Error: {e}", file=sys.stderr)
        return 1

    print(plan.summary())
    print()
    action = "Would delete" if plan.dry_run else "Deleting"
    for a in plan.to_delete:
        print(f"  {action}: {a.name} ({a.size_bytes} bytes, workflow={a.workflow_name})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
