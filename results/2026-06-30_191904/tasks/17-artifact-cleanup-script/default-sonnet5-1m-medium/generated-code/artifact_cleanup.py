"""
Artifact retention/cleanup planner for GitHub Actions build artifacts.

Given a list of Artifact records (mock metadata), apply retention policies:
  - max age (delete artifacts older than N days)
  - max total size (delete oldest artifacts until under a size budget)
  - keep-latest-N per workflow (never delete the N most recent per workflow,
    even if other policies would otherwise delete them)

Produces a DeletionPlan describing what would be kept/deleted and a summary.
Supports dry-run mode (plan only, no actual deletion side effects).
"""
from dataclasses import dataclass, field
from datetime import datetime, timedelta
from typing import Callable, List, Optional


@dataclass
class Artifact:
    name: str
    size_bytes: int
    created_at: datetime
    workflow_run_id: str


@dataclass
class RetentionPolicy:
    max_age_days: Optional[int] = None
    keep_latest_n_per_workflow: Optional[int] = None
    max_total_size_bytes: Optional[int] = None


@dataclass
class DeletionPlan:
    to_delete: List[Artifact] = field(default_factory=list)
    to_retain: List[Artifact] = field(default_factory=list)

    def summary(self) -> dict:
        return {
            "artifacts_deleted": len(self.to_delete),
            "artifacts_retained": len(self.to_retain),
            "space_reclaimed_bytes": sum(a.size_bytes for a in self.to_delete),
        }


def _protected_by_keep_latest_n(artifacts: List[Artifact], keep_latest_n: Optional[int]) -> set:
    """Return the set of artifact ids (by identity) protected because they are
    among the N most recent artifacts for their workflow."""
    if not keep_latest_n:
        return set()

    by_workflow = {}
    for art in artifacts:
        by_workflow.setdefault(art.workflow_run_id, []).append(art)

    protected = set()
    for group in by_workflow.values():
        newest_first = sorted(group, key=lambda a: a.created_at, reverse=True)
        for art in newest_first[:keep_latest_n]:
            protected.add(id(art))
    return protected


def _validate_policy(policy: RetentionPolicy) -> None:
    if policy.max_age_days is not None and policy.max_age_days < 0:
        raise ValueError("max_age_days must be non-negative")
    if policy.max_total_size_bytes is not None and policy.max_total_size_bytes < 0:
        raise ValueError("max_total_size_bytes must be non-negative")
    if policy.keep_latest_n_per_workflow is not None and policy.keep_latest_n_per_workflow < 0:
        raise ValueError("keep_latest_n_per_workflow must be non-negative")


def plan_deletions(artifacts: List[Artifact], policy: RetentionPolicy, now: datetime) -> DeletionPlan:
    _validate_policy(policy)
    protected = _protected_by_keep_latest_n(artifacts, policy.keep_latest_n_per_workflow)

    to_delete = []
    to_retain = []
    for art in artifacts:
        if id(art) in protected:
            to_retain.append(art)
            continue

        age_days = (now - art.created_at).total_seconds() / 86400
        if policy.max_age_days is not None and age_days > policy.max_age_days:
            to_delete.append(art)
        else:
            to_retain.append(art)

    if policy.max_total_size_bytes is not None:
        total_size = sum(a.size_bytes for a in to_retain)
        removable_oldest_first = sorted(
            (a for a in to_retain if id(a) not in protected),
            key=lambda a: a.created_at,
        )
        for art in removable_oldest_first:
            if total_size <= policy.max_total_size_bytes:
                break
            to_retain.remove(art)
            to_delete.append(art)
            total_size -= art.size_bytes

    return DeletionPlan(to_delete=to_delete, to_retain=to_retain)


@dataclass
class ExecutionResult:
    dry_run: bool
    deleted: List[Artifact] = field(default_factory=list)
    errors: List[str] = field(default_factory=list)


def execute_plan(plan: DeletionPlan, deleter: Callable[[Artifact], None], dry_run: bool) -> ExecutionResult:
    """Carry out (or simulate) a deletion plan.

    `deleter` is injected so tests can use a mock instead of hitting a real
    artifact-storage API. In dry-run mode the deleter is never called, but
    the result still reports which artifacts *would* be deleted so callers
    can preview the effect of a policy change safely.
    """
    result = ExecutionResult(dry_run=dry_run)

    if dry_run:
        result.deleted = list(plan.to_delete)
        return result

    for art in plan.to_delete:
        try:
            deleter(art)
            result.deleted.append(art)
        except Exception as exc:
            result.errors.append(f"Failed to delete artifact '{art.name}': {exc}")

    return result
