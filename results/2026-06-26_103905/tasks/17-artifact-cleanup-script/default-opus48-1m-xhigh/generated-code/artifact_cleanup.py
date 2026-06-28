#!/usr/bin/env python3
"""Artifact retention/cleanup planner (pure standard library, no dependencies).

Given a list of artifacts (name, size, creation date, workflow run id) and a
retention policy, decide which artifacts to delete and produce a deletion plan
plus a summary (space reclaimed, retained vs deleted). Supports a dry-run mode.

Three independent retention policies are supported; any combination may be
enabled (a ``None`` threshold disables that policy):

  * ``max_age_days``          - delete anything older than the cutoff.
  * ``keep_latest_n``         - per workflow, keep only the N newest artifacts.
  * ``max_total_size_bytes``  - if the survivors still exceed the byte budget,
                                evict the oldest survivors first until they fit.

Order matters only for the size policy, which is applied last because it acts on
whatever the other two policies leave behind. Deletion reasons accumulate, so an
artifact removed by several policies lists each reason. All ordering uses stable
tie-breaks (creation time, then run id, then name) so the plan is deterministic.

This module was built test-first (red/green TDD); see tests/test_artifact_cleanup.py.
"""

from __future__ import annotations

import argparse
import json
import sys
from dataclasses import dataclass, field
from datetime import datetime, timedelta, timezone


class CleanupError(Exception):
    """Raised for any user-facing problem (bad input file, bad data, …).

    The CLI catches this and prints ``str(exc)`` so messages must be human
    readable and point at the offending field/file.
    """


@dataclass
class Artifact:
    """One artifact and its metadata (mirrors the GitHub artifacts API shape)."""

    name: str
    size_bytes: int
    created_at: datetime  # timezone-aware UTC
    run_id: int
    workflow: str


@dataclass
class Policy:
    """Retention thresholds. ``None`` means "policy disabled"."""

    max_age_days: int | None = None
    keep_latest_n: int | None = None
    max_total_size_bytes: int | None = None


@dataclass
class Deletion:
    """A single artifact selected for deletion, plus why."""

    artifact: Artifact
    reasons: list[str] = field(default_factory=list)


@dataclass
class CleanupPlan:
    """The result of applying policies: what to delete vs keep."""

    deletions: list[Deletion] = field(default_factory=list)
    retained: list[Artifact] = field(default_factory=list)


def _sort_key_newest_first(item):
    """Order a (index, artifact) pair newest-first, with stable tie-breaks.

    Ties on creation time fall back to the (higher) run id, then name, so the
    plan is fully deterministic regardless of input ordering.
    """
    _, art = item
    return (art.created_at, art.run_id, art.name)


def plan_cleanup(artifacts: list[Artifact], policy: Policy, *, now: datetime) -> CleanupPlan:
    """Apply every enabled retention policy and return a deletion plan.

    Reasons accumulate: an artifact deleted by more than one policy lists each
    reason. Policies are applied independently here; the size policy (added in a
    later cycle) is the only one that depends on what the others leave behind.
    """
    # reasons[i] collects every policy violation for artifacts[i].
    reasons: list[list[str]] = [[] for _ in artifacts]

    # Policy: max age — drop anything older than the cutoff.
    if policy.max_age_days is not None:
        cutoff = now - timedelta(days=policy.max_age_days)
        for i, art in enumerate(artifacts):
            if art.created_at < cutoff:
                reasons[i].append("max_age")

    # Policy: keep latest N per workflow — within each workflow group keep only
    # the N newest artifacts; flag the older surplus.
    if policy.keep_latest_n is not None:
        groups: dict[str, list[tuple[int, Artifact]]] = {}
        for i, art in enumerate(artifacts):
            groups.setdefault(art.workflow, []).append((i, art))
        for members in groups.values():
            members.sort(key=_sort_key_newest_first, reverse=True)
            for i, _ in members[policy.keep_latest_n:]:
                reasons[i].append("keep_latest_n")

    # Policy: max total size — if the artifacts still surviving the policies
    # above exceed the byte budget, evict the oldest survivors first until the
    # retained total fits. Applied last because it depends on the survivors.
    if policy.max_total_size_bytes is not None:
        survivors = [(i, art) for i, art in enumerate(artifacts) if not reasons[i]]
        retained_bytes = sum(art.size_bytes for _, art in survivors)
        # Oldest first (then lower run id, then name) so eviction is deterministic.
        survivors.sort(key=lambda item: (item[1].created_at, item[1].run_id, item[1].name))
        for i, art in survivors:
            if retained_bytes <= policy.max_total_size_bytes:
                break
            reasons[i].append("max_total_size")
            retained_bytes -= art.size_bytes

    # Partition into deletions vs retained, preserving input order.
    deletions: list[Deletion] = []
    retained: list[Artifact] = []
    for i, art in enumerate(artifacts):
        if reasons[i]:
            deletions.append(Deletion(artifact=art, reasons=reasons[i]))
        else:
            retained.append(art)

    return CleanupPlan(deletions=deletions, retained=retained)


def summarize(plan: CleanupPlan) -> dict:
    """Roll a plan up into the headline numbers a maintainer cares about."""
    retained_size = sum(a.size_bytes for a in plan.retained)
    reclaimed = sum(d.artifact.size_bytes for d in plan.deletions)
    return {
        "total_artifacts": len(plan.retained) + len(plan.deletions),
        "retained_count": len(plan.retained),
        "deleted_count": len(plan.deletions),
        "total_size_bytes": retained_size + reclaimed,
        "retained_size_bytes": retained_size,
        "space_reclaimed_bytes": reclaimed,
    }


# --------------------------------------------------------------------------
# Loading & validation
# --------------------------------------------------------------------------

def _read_json(path: str):
    """Read and parse a JSON file, turning low-level errors into CleanupError."""
    try:
        with open(path, "r", encoding="utf-8") as fh:
            return json.load(fh)
    except FileNotFoundError:
        raise CleanupError(f"Input file not found: {path}")
    except IsADirectoryError:
        raise CleanupError(f"Expected a file but got a directory: {path}")
    except json.JSONDecodeError as exc:
        raise CleanupError(f"Invalid JSON in {path}: {exc}")
    except OSError as exc:
        raise CleanupError(f"Could not read {path}: {exc}")


def _parse_datetime(value, *, where: str) -> datetime:
    """Parse an ISO-8601 date/datetime into a timezone-aware UTC datetime.

    Accepts a trailing ``Z`` and bare dates (``2026-06-01``). Naive values are
    assumed to be UTC so comparisons are always well defined.
    """
    if not isinstance(value, str):
        raise CleanupError(f"{where}: created_at must be a string, got {type(value).__name__}")
    text = value.strip()
    if text.endswith("Z"):
        text = text[:-1] + "+00:00"
    try:
        dt = datetime.fromisoformat(text)
    except ValueError:
        raise CleanupError(f"{where}: created_at is not a valid ISO-8601 date: {value!r}")
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return dt.astimezone(timezone.utc)


def _require_int(obj: dict, key: str, *, where: str, allow_negative: bool = False) -> int:
    """Fetch a required non-negative integer field with a clear error."""
    if key not in obj:
        raise CleanupError(f"{where}: missing required field '{key}'")
    val = obj[key]
    # bool is a subclass of int; reject it so True/False can't masquerade as 1/0.
    if isinstance(val, bool) or not isinstance(val, int):
        raise CleanupError(f"{where}: field '{key}' must be an integer, got {val!r}")
    if not allow_negative and val < 0:
        raise CleanupError(f"{where}: field '{key}' must be >= 0, got {val}")
    return val


def load_artifacts(path: str) -> list[Artifact]:
    """Load and validate artifact metadata from a JSON file.

    Accepts either a top-level list or a ``{"artifacts": [...]}`` wrapper. Each
    entry needs name/size_bytes/created_at/run_id; ``workflow`` is optional and
    defaults to "default" (the core metadata named by the task is name, size,
    creation date and workflow run id).
    """
    data = _read_json(path)
    if isinstance(data, dict) and "artifacts" in data:
        data = data["artifacts"]
    if not isinstance(data, list):
        raise CleanupError(
            f"{path}: expected a JSON list of artifacts (or an object with an "
            f"'artifacts' list), got {type(data).__name__}"
        )

    artifacts: list[Artifact] = []
    for i, entry in enumerate(data):
        where = f"{path}: artifact at index {i}"
        if not isinstance(entry, dict):
            raise CleanupError(f"{where}: each artifact must be an object, got {type(entry).__name__}")
        if "name" not in entry:
            raise CleanupError(f"{where}: missing required field 'name'")
        if not isinstance(entry["name"], str) or not entry["name"]:
            raise CleanupError(f"{where}: field 'name' must be a non-empty string")
        if "created_at" not in entry:
            raise CleanupError(f"{where}: missing required field 'created_at'")

        artifacts.append(
            Artifact(
                name=entry["name"],
                size_bytes=_require_int(entry, "size_bytes", where=where),
                created_at=_parse_datetime(entry["created_at"], where=where),
                run_id=_require_int(entry, "run_id", where=where, allow_negative=True),
                workflow=str(entry.get("workflow", "default")),
            )
        )
    return artifacts


def load_policy(path: str) -> Policy:
    """Load and validate a retention policy from a JSON file."""
    data = _read_json(path)
    if not isinstance(data, dict):
        raise CleanupError(f"{path}: policy must be a JSON object, got {type(data).__name__}")

    def _optional_int(key: str) -> int | None:
        if data.get(key) is None:
            return None
        return _require_int(data, key, where=f"{path}: policy")

    policy = Policy(
        max_age_days=_optional_int("max_age_days"),
        keep_latest_n=_optional_int("keep_latest_n"),
        max_total_size_bytes=_optional_int("max_total_size_bytes"),
    )
    if policy.max_age_days is None and policy.keep_latest_n is None and policy.max_total_size_bytes is None:
        raise CleanupError(
            f"{path}: policy enables no retention rules; set at least one of "
            f"max_age_days, keep_latest_n, max_total_size_bytes"
        )
    return policy


# --------------------------------------------------------------------------
# Rendering
# --------------------------------------------------------------------------

def _policy_to_dict(policy: Policy) -> dict:
    return {
        "max_age_days": policy.max_age_days,
        "keep_latest_n": policy.keep_latest_n,
        "max_total_size_bytes": policy.max_total_size_bytes,
    }


def _artifact_to_dict(art: Artifact) -> dict:
    return {
        "name": art.name,
        "run_id": art.run_id,
        "workflow": art.workflow,
        "size_bytes": art.size_bytes,
        "created_at": art.created_at.isoformat(),
    }


def render_text(plan: CleanupPlan, summary: dict, *, dry_run: bool, policy: Policy | None = None) -> str:
    """Render a human-readable deletion plan + summary.

    Always ends with a single ``RESULT ...`` marker line carrying every headline
    number, so CI / downstream tooling can assert on exact values with one grep.
    """
    mode_tag = "[DRY RUN]" if dry_run else "[EXECUTE]"
    lines: list[str] = []
    lines.append(f"Artifact Cleanup Plan {mode_tag}")
    lines.append("=" * 50)
    if policy is not None:
        lines.append(
            "Policy: "
            f"max_age_days={policy.max_age_days}, "
            f"keep_latest_n={policy.keep_latest_n}, "
            f"max_total_size_bytes={policy.max_total_size_bytes}"
        )
    if dry_run:
        lines.append("Mode: DRY RUN - no artifacts will be deleted")
    else:
        lines.append(
            f"Mode: EXECUTE - {summary['deleted_count']} artifact(s) selected for "
            "deletion (mock data: no live GitHub API is called)"
        )
    lines.append("")

    lines.append(f"Deletions ({summary['deleted_count']}):")
    for d in plan.deletions:
        a = d.artifact
        lines.append(
            f"  - {a.name:<18} run={a.run_id} workflow={a.workflow} "
            f"size={a.size_bytes}B created={a.created_at.date()} "
            f"reasons={','.join(d.reasons)}"
        )
    lines.append("")

    lines.append(f"Retained ({summary['retained_count']}):")
    for a in plan.retained:
        lines.append(
            f"  - {a.name:<18} run={a.run_id} workflow={a.workflow} "
            f"size={a.size_bytes}B created={a.created_at.date()}"
        )
    lines.append("")

    # Summary block. Labels are padded to a fixed width for tidy alignment.
    lines.append("Summary:")
    for label, value in (
        ("Total artifacts:", summary["total_artifacts"]),
        ("Retained:", summary["retained_count"]),
        ("Deleted:", summary["deleted_count"]),
        ("Total size:", f"{summary['total_size_bytes']} bytes"),
        ("Retained size:", f"{summary['retained_size_bytes']} bytes"),
        ("Space reclaimed:", f"{summary['space_reclaimed_bytes']} bytes"),
    ):
        lines.append(f"  {label:<18}{value}")
    lines.append("")

    lines.append(
        "RESULT "
        f"total={summary['total_artifacts']} "
        f"retained={summary['retained_count']} "
        f"deleted={summary['deleted_count']} "
        f"reclaimed={summary['space_reclaimed_bytes']} "
        f"retained_bytes={summary['retained_size_bytes']} "
        f"total_bytes={summary['total_size_bytes']}"
    )
    return "\n".join(lines)


def render_json(plan: CleanupPlan, summary: dict, *, dry_run: bool, policy: Policy | None = None) -> str:
    """Render the plan as a stable, machine-readable JSON document."""
    payload = {
        "dry_run": dry_run,
        "summary": summary,
        "deletions": [
            {**_artifact_to_dict(d.artifact), "reasons": d.reasons} for d in plan.deletions
        ],
        "retained": [_artifact_to_dict(a) for a in plan.retained],
    }
    if policy is not None:
        payload["policy"] = _policy_to_dict(policy)
    return json.dumps(payload, indent=2, sort_keys=True)


# --------------------------------------------------------------------------
# Command-line interface
# --------------------------------------------------------------------------

def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="artifact_cleanup.py",
        description="Apply artifact retention policies and produce a deletion plan.",
    )
    parser.add_argument("--artifacts", required=True, help="Path to artifacts JSON file")
    parser.add_argument("--policy", required=True, help="Path to retention policy JSON file")
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Report the plan without 'executing' it (default is execute mode)",
    )
    parser.add_argument(
        "--format",
        choices=("text", "json"),
        default="text",
        help="Output format (default: text)",
    )
    parser.add_argument(
        "--now",
        default=None,
        help="Override the reference time (ISO-8601) used for the max-age policy. "
        "Defaults to the current UTC time. Useful for deterministic CI runs.",
    )
    parser.add_argument(
        "--output",
        default=None,
        help="Also write the rendered plan to this file",
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    """CLI entry point. Returns a process exit code (0 ok, 2 on user error)."""
    args = _build_parser().parse_args(argv)
    try:
        now = (
            _parse_datetime(args.now, where="--now")
            if args.now
            else datetime.now(timezone.utc)
        )
        artifacts = load_artifacts(args.artifacts)
        policy = load_policy(args.policy)
        plan = plan_cleanup(artifacts, policy, now=now)
        summary = summarize(plan)

        if args.format == "json":
            output = render_json(plan, summary, dry_run=args.dry_run, policy=policy)
        else:
            output = render_text(plan, summary, dry_run=args.dry_run, policy=policy)
    except CleanupError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2

    print(output)
    if args.output:
        try:
            with open(args.output, "w", encoding="utf-8") as fh:
                fh.write(output + "\n")
        except OSError as exc:
            print(f"error: could not write output file {args.output}: {exc}", file=sys.stderr)
            return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
