#!/usr/bin/env python3
"""Artifact cleanup planner.

Given a list of CI artifacts and a set of retention policies, decide which
artifacts to delete and produce a deletion plan plus a summary (space
reclaimed, retained vs deleted counts). Supports a dry-run mode.
"""

from __future__ import annotations

import argparse
import json
import sys
from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Optional


class CleanupError(Exception):
    """Raised for user-facing, recoverable errors (bad input, missing file)."""


def _parse_dt(value) -> datetime:
    """Parse an ISO-8601 string (or pass through a datetime) into tz-aware UTC.

    Naive datetimes/strings are assumed to be UTC so comparisons are always
    well-defined regardless of the host's local timezone.
    """
    if isinstance(value, datetime):
        dt = value
    else:
        dt = datetime.fromisoformat(str(value))
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return dt.astimezone(timezone.utc)


@dataclass
class Artifact:
    """A single CI artifact with the metadata needed for retention decisions."""

    name: str
    size: int  # bytes
    created_at: datetime
    workflow_run_id: str

    @classmethod
    def from_dict(cls, d: dict) -> "Artifact":
        return cls(
            name=d["name"],
            size=int(d["size"]),
            created_at=_parse_dt(d["created_at"]),
            workflow_run_id=str(d["workflow_run_id"]),
        )


@dataclass
class RetentionPolicy:
    """Retention rules. Any field left at ``None`` disables that rule."""

    max_age_days: Optional[int] = None
    max_total_size: Optional[int] = None  # bytes; cap on total retained size
    keep_latest_n_per_workflow: Optional[int] = None

    @classmethod
    def from_dict(cls, d: dict) -> "RetentionPolicy":
        def _opt_int(key):
            v = d.get(key)
            return None if v is None else int(v)

        return cls(
            max_age_days=_opt_int("max_age_days"),
            max_total_size=_opt_int("max_total_size"),
            keep_latest_n_per_workflow=_opt_int("keep_latest_n_per_workflow"),
        )


@dataclass
class Decision:
    """The outcome for one artifact: keep, or delete with a recorded reason."""

    artifact: Artifact
    delete: bool = False
    reason: Optional[str] = None  # which policy triggered deletion


@dataclass
class CleanupPlan:
    """A full set of per-artifact decisions plus derived summary numbers."""

    decisions: list = field(default_factory=list)

    @property
    def deleted(self):
        return [d for d in self.decisions if d.delete]

    @property
    def retained(self):
        return [d for d in self.decisions if not d.delete]

    @property
    def space_reclaimed(self) -> int:
        return sum(d.artifact.size for d in self.deleted)


def _age_days(artifact: Artifact, now: datetime) -> float:
    return (now - artifact.created_at).total_seconds() / 86400.0


def plan_cleanup(
    artifacts: list, policy: RetentionPolicy, now: datetime
) -> CleanupPlan:
    """Apply each enabled retention rule in sequence and return a plan.

    Rules are applied in a fixed, documented order so the result is
    deterministic. Once an artifact is marked for deletion it keeps its first
    (highest-precedence) reason and is excluded from later rules' accounting:

      1. max_age            -- drop artifacts older than ``max_age_days``.
      2. keep_latest_n      -- per workflow run, keep the N newest survivors.
      3. max_total_size     -- if survivors still exceed the size cap, drop the
                               oldest survivors until the cap is satisfied.
    """
    decisions = {a.name: Decision(artifact=a) for a in artifacts}

    def _mark(name: str, reason: str):
        d = decisions[name]
        if not d.delete:  # keep the highest-precedence reason
            d.delete = True
            d.reason = reason

    def _survivors():
        return [decisions[a.name].artifact for a in artifacts if not decisions[a.name].delete]

    # Rule 1: max age.
    if policy.max_age_days is not None:
        for a in artifacts:
            if _age_days(a, now) > policy.max_age_days:
                _mark(a.name, "max_age")

    # Rule 2: keep latest N per workflow run id (over the surviving set).
    if policy.keep_latest_n_per_workflow is not None:
        n = policy.keep_latest_n_per_workflow
        by_run: dict = {}
        for a in _survivors():
            by_run.setdefault(a.workflow_run_id, []).append(a)
        for run_id, group in by_run.items():
            # Newest first; keep the first N, mark the rest for deletion.
            ordered = sorted(group, key=lambda a: a.created_at, reverse=True)
            for a in ordered[n:]:
                _mark(a.name, "keep_latest_n")

    # Rule 3: cap total retained size, evicting the oldest survivors first.
    if policy.max_total_size is not None:
        survivors = sorted(_survivors(), key=lambda a: a.created_at)  # oldest first
        total = sum(a.size for a in survivors)
        i = 0
        while total > policy.max_total_size and i < len(survivors):
            victim = survivors[i]
            _mark(victim.name, "max_total_size")
            total -= victim.size
            i += 1

    return CleanupPlan(decisions=list(decisions.values()))


def load_config(path: str):
    """Read a JSON config and return ``(artifacts, policy, now)``.

    The config has the shape::

        {"now": <iso8601?>, "policies": {...}, "artifacts": [{...}, ...]}

    ``now`` is optional; when absent we fall back to the real current time.
    All failure modes raise :class:`CleanupError` with an actionable message.
    """
    try:
        with open(path, "r", encoding="utf-8") as fh:
            raw = fh.read()
    except FileNotFoundError:
        raise CleanupError(f"Config file not found: {path}")
    except OSError as e:
        raise CleanupError(f"Could not read config file {path}: {e}")

    try:
        data = json.loads(raw)
    except json.JSONDecodeError as e:
        raise CleanupError(f"Invalid JSON in {path}: {e}")

    if not isinstance(data, dict):
        raise CleanupError(f"Config root must be a JSON object, got {type(data).__name__}")

    raw_artifacts = data.get("artifacts")
    if raw_artifacts is None:
        raise CleanupError("Config is missing the required 'artifacts' list")
    if not isinstance(raw_artifacts, list):
        raise CleanupError("'artifacts' must be a list")

    artifacts = []
    for i, item in enumerate(raw_artifacts):
        if not isinstance(item, dict):
            raise CleanupError(f"Artifact #{i} must be an object")
        try:
            artifacts.append(Artifact.from_dict(item))
        except KeyError as e:
            raise CleanupError(f"Artifact #{i} is missing required field {e}")
        except (ValueError, TypeError) as e:
            raise CleanupError(f"Artifact #{i} has an invalid field: {e}")

    policy = RetentionPolicy.from_dict(data.get("policies") or {})

    now_raw = data.get("now")
    now = _parse_dt(now_raw) if now_raw else datetime.now(timezone.utc)

    return artifacts, policy, now


def render_plan(plan: CleanupPlan, dry_run: bool, now: datetime) -> str:
    """Render a human-readable deletion plan + summary as a single string.

    The exact summary lines below are part of the tool's contract: the CI
    pipeline asserts on them, so keep them stable.
    """
    lines = []
    lines.append("=== Artifact Cleanup Plan ===")
    lines.append(f"Mode: {'DRY-RUN' if dry_run else 'LIVE'}")
    lines.append(f"Now: {now.isoformat()}")
    lines.append("")

    # Stable, name-sorted listing so output is deterministic across runs.
    for d in sorted(plan.decisions, key=lambda d: d.artifact.name):
        a = d.artifact
        if d.delete:
            lines.append(
                f"DELETE  {a.name:<20} reason={d.reason:<14} size={a.size}"
            )
        else:
            lines.append(f"KEEP    {a.name:<20} size={a.size}")

    verb = "Would delete" if dry_run else "Deleted"
    lines.append("")
    lines.append("=== Summary ===")
    lines.append(f"Artifacts total: {len(plan.decisions)}")
    lines.append(f"Artifacts retained: {len(plan.retained)}")
    lines.append(f"Artifacts deleted: {len(plan.deleted)}")
    lines.append(f"Space reclaimed: {plan.space_reclaimed} bytes")
    lines.append(f"{verb} {len(plan.deleted)} artifact(s).")
    if dry_run:
        lines.append("(dry-run: no artifacts were actually deleted)")
    return "\n".join(lines)


def main(argv=None) -> int:
    """CLI entry point. Returns a process exit code (0 ok, 2 on input error)."""
    parser = argparse.ArgumentParser(
        description="Plan CI artifact cleanup from retention policies."
    )
    parser.add_argument(
        "--input", "-i", required=True, help="Path to the JSON config file."
    )
    parser.add_argument(
        "--now",
        help="Override the reference time (ISO-8601). Defaults to config 'now' "
        "or the current time. Useful for deterministic runs.",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Report the plan without claiming any deletion happened.",
    )
    args = parser.parse_args(argv)

    try:
        artifacts, policy, now = load_config(args.input)
        if args.now:
            now = _parse_dt(args.now)
        plan = plan_cleanup(artifacts, policy, now)
        print(render_plan(plan, dry_run=args.dry_run, now=now))
    except CleanupError as e:
        # Graceful, meaningful error on stderr; non-zero exit for CI.
        print(f"ERROR: {e}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
