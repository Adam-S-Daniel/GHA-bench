#!/usr/bin/env python3
"""
Artifact cleanup planner.

Given a list of build artifacts with metadata (name, size, creation date,
workflow run id) this module applies three retention policies and produces a
*deletion plan* plus a human/machine readable summary. Nothing is ever actually
deleted here -- the plan is the deliverable, which makes the logic pure and easy
to test and lets callers run in "dry-run" mode.

Retention policies (all optional):

  * ``keep_latest_per_workflow`` -- PROTECTIVE. Within each workflow group the N
    most-recent artifacts are always kept, regardless of the other policies.
    This models "never throw away the freshest build of a pipeline".

  * ``max_age_days`` -- delete (unprotected) artifacts older than N days.

  * ``max_total_size_bytes`` -- if the retained set still exceeds this budget,
    delete the oldest (unprotected) artifacts until it fits, smallest blast
    radius first by going oldest-to-newest.

Policy precedence: keep-latest is evaluated first and wins over everything; then
max-age; then max-total-size acts as a final squeeze on whatever survived.

The module is also a CLI -- see ``main()`` / ``--help``.
"""

from __future__ import annotations

import argparse
import json
import sys
from dataclasses import dataclass
from datetime import datetime, timezone


class ArtifactError(Exception):
    """Raised for any malformed input -- bad files, bad JSON, bad records.

    Carrying a single exception type lets the CLI present one clean, meaningful
    error message instead of leaking tracebacks at the user."""


# Required fields every artifact record must carry.
_REQUIRED_FIELDS = ("name", "size_bytes", "created_at", "run_id")


@dataclass
class Artifact:
    """A normalised artifact: ``created_at`` is a real timezone-aware datetime."""

    name: str
    size_bytes: int
    created_at: datetime
    run_id: object
    workflow: str
    raw: dict


def _parse_timestamp(value) -> datetime:
    """Accept ISO-8601 strings (with or without trailing 'Z') or epoch seconds."""
    if isinstance(value, (int, float)):
        return datetime.fromtimestamp(value, tz=timezone.utc)
    if isinstance(value, str):
        text = value.strip()
        # datetime.fromisoformat in 3.12 handles most ISO strings; normalise 'Z'.
        if text.endswith("Z"):
            text = text[:-1] + "+00:00"
        try:
            dt = datetime.fromisoformat(text)
        except ValueError as exc:
            raise ArtifactError(f"invalid created_at timestamp: {value!r}") from exc
        # Treat naive timestamps as UTC so comparisons never blow up.
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=timezone.utc)
        return dt
    raise ArtifactError(f"created_at must be a string or number, got {type(value).__name__}")


def parse_artifact(raw) -> Artifact:
    """Validate and normalise a single raw artifact dict into an Artifact."""
    if not isinstance(raw, dict):
        raise ArtifactError(f"artifact must be an object, got {type(raw).__name__}")

    missing = [f for f in _REQUIRED_FIELDS if f not in raw]
    if missing:
        raise ArtifactError(
            f"artifact {raw.get('name', '<unnamed>')!r} missing required field(s): "
            + ", ".join(missing)
        )

    size = raw["size_bytes"]
    if not isinstance(size, (int, float)) or isinstance(size, bool) or size < 0:
        raise ArtifactError(
            f"artifact {raw['name']!r} has invalid size_bytes: {size!r}"
        )

    created_at = _parse_timestamp(raw["created_at"])

    # "workflow" is the grouping key for keep-latest-N. Real GitHub artifacts are
    # produced by a named workflow across many runs; if the caller doesn't supply
    # one we fall back to the artifact name so the policy still has a sane group.
    workflow = raw.get("workflow") or raw["name"]

    return Artifact(
        name=raw["name"],
        size_bytes=int(size),
        created_at=created_at,
        run_id=raw["run_id"],
        workflow=str(workflow),
        raw=raw,
    )


def _age_days(art: Artifact, now: datetime) -> float:
    return (now - art.created_at).total_seconds() / 86400.0


def build_plan(artifacts, policy=None, now=None, dry_run=False) -> dict:
    """Compute the deletion plan.

    Returns a dict with keys ``delete`` (list of records w/ reason), ``retain``
    (list of records) and ``summary`` (counts + sizes). Pure function: it never
    touches the filesystem or a real API.
    """
    if not isinstance(artifacts, list):
        raise ArtifactError("artifacts must be a list of artifact objects")

    policy = policy or {}
    now = now or datetime.now(timezone.utc)

    parsed = [parse_artifact(a) for a in artifacts]

    keep_latest = policy.get("keep_latest_per_workflow")
    max_age_days = policy.get("max_age_days")
    max_total = policy.get("max_total_size_bytes")

    # ---- Step 1: figure out which artifacts are PROTECTED by keep-latest-N ----
    protected: set[int] = set()  # ids of Artifact objects we must keep
    if keep_latest is not None:
        if not isinstance(keep_latest, int) or keep_latest < 0:
            raise ArtifactError(
                f"keep_latest_per_workflow must be a non-negative integer, got {keep_latest!r}"
            )
        groups: dict[str, list[Artifact]] = {}
        for art in parsed:
            groups.setdefault(art.workflow, []).append(art)
        for group in groups.values():
            # newest first; the first N are protected, the surplus are deleted.
            newest_first = sorted(group, key=lambda a: a.created_at, reverse=True)
            for art in newest_first[:keep_latest]:
                protected.add(id(art))

    # reason-per-artifact; absence means "retain".
    reasons: dict[int, str] = {}

    # keep-latest is both protective (above) and active: anything beyond the
    # newest N in its workflow group is surplus and marked for deletion.
    if keep_latest is not None:
        for art in parsed:
            if id(art) not in protected:
                reasons[id(art)] = "keep_latest"

    # ---- Step 2: max age ----
    if max_age_days is not None:
        if not isinstance(max_age_days, (int, float)) or max_age_days < 0:
            raise ArtifactError(
                f"max_age_days must be a non-negative number, got {max_age_days!r}"
            )
        for art in parsed:
            if id(art) in protected or id(art) in reasons:
                continue
            if _age_days(art, now) > max_age_days:
                reasons[id(art)] = "max_age"

    # ---- Step 3: max total size (squeeze the survivors) ----
    if max_total is not None:
        if not isinstance(max_total, (int, float)) or max_total < 0:
            raise ArtifactError(
                f"max_total_size_bytes must be a non-negative number, got {max_total!r}"
            )
        retained_size = sum(a.size_bytes for a in parsed if id(a) not in reasons)
        if retained_size > max_total:
            # Delete oldest unprotected survivors first until we fit (or run out).
            candidates = [
                a for a in parsed if id(a) not in reasons and id(a) not in protected
            ]
            for art in sorted(candidates, key=lambda a: a.created_at):
                if retained_size <= max_total:
                    break
                reasons[id(art)] = "max_total_size"
                retained_size -= art.size_bytes

    # ---- Step 4: assemble plan ----
    delete, retain = [], []
    for art in parsed:
        record = {
            "name": art.name,
            "size_bytes": art.size_bytes,
            "created_at": art.created_at.isoformat(),
            "run_id": art.run_id,
            "workflow": art.workflow,
        }
        if id(art) in reasons:
            record["reason"] = reasons[id(art)]
            delete.append(record)
        else:
            retain.append(record)

    reclaimed = sum(r["size_bytes"] for r in delete)
    retained_size = sum(r["size_bytes"] for r in retain)
    summary = {
        "total_artifacts": len(parsed),
        "deleted_count": len(delete),
        "retained_count": len(retain),
        "reclaimed_size_bytes": reclaimed,
        "retained_size_bytes": retained_size,
        "dry_run": bool(dry_run),
    }
    return {"delete": delete, "retain": retain, "summary": summary}


# ---------------------------------------------------------------------------
# IO helpers / CLI
# ---------------------------------------------------------------------------

def load_artifacts(path: str) -> list:
    """Load the artifacts JSON file, raising ArtifactError on any problem."""
    try:
        with open(path, "r", encoding="utf-8") as fh:
            data = json.load(fh)
    except FileNotFoundError as exc:
        raise ArtifactError(f"artifacts file not found: {path}") from exc
    except json.JSONDecodeError as exc:
        raise ArtifactError(f"artifacts file is not valid JSON ({path}): {exc}") from exc
    except OSError as exc:
        raise ArtifactError(f"could not read artifacts file {path}: {exc}") from exc

    # Allow either a bare list or {"artifacts": [...]}.
    if isinstance(data, dict) and "artifacts" in data:
        data = data["artifacts"]
    if not isinstance(data, list):
        raise ArtifactError(f"artifacts file {path} must contain a JSON array")
    return data


def load_policy(path: str | None) -> dict:
    """Load the policy config JSON, or return an empty policy if no path given."""
    if not path:
        return {}
    try:
        with open(path, "r", encoding="utf-8") as fh:
            data = json.load(fh)
    except FileNotFoundError as exc:
        raise ArtifactError(f"policy file not found: {path}") from exc
    except json.JSONDecodeError as exc:
        raise ArtifactError(f"policy file is not valid JSON ({path}): {exc}") from exc
    except OSError as exc:
        raise ArtifactError(f"could not read policy file {path}: {exc}") from exc
    if not isinstance(data, dict):
        raise ArtifactError(f"policy file {path} must contain a JSON object")
    return data


def render_summary(plan: dict) -> str:
    """Render a stable, human-readable summary used by the CLI / CI workflow."""
    s = plan["summary"]
    mode = "DRY RUN" if s["dry_run"] else "EXECUTE"
    lines = [
        f"=== Artifact Cleanup Plan ({mode}) ===",
        f"Total artifacts: {s['total_artifacts']}",
        f"To delete: {s['deleted_count']}",
        f"To retain: {s['retained_count']}",
        f"Space reclaimed: {s['reclaimed_size_bytes']} bytes",
        f"Space retained: {s['retained_size_bytes']} bytes",
        "Deletions:",
    ]
    if plan["delete"]:
        for d in sorted(plan["delete"], key=lambda r: r["name"]):
            verb = "WOULD DELETE" if s["dry_run"] else "DELETE"
            lines.append(
                f"  - {verb} {d['name']} ({d['size_bytes']} bytes) reason={d['reason']}"
            )
    else:
        lines.append("  (none)")
    return "\n".join(lines)


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description="Plan artifact retention cleanup.")
    parser.add_argument("--artifacts", required=True, help="Path to artifacts JSON.")
    parser.add_argument("--config", help="Path to policy config JSON.")
    parser.add_argument("--output", help="Write the full plan JSON to this path.")
    parser.add_argument("--dry-run", action="store_true", help="Plan only; mark as dry-run.")
    parser.add_argument(
        "--now",
        help="Reference time (ISO-8601) for age calculations; defaults to current UTC.",
    )
    args = parser.parse_args(argv)

    try:
        artifacts = load_artifacts(args.artifacts)
        policy = load_policy(args.config)
        now = _parse_timestamp(args.now) if args.now else None
        plan = build_plan(artifacts, policy=policy, now=now, dry_run=args.dry_run)
    except ArtifactError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1

    if args.output:
        try:
            with open(args.output, "w", encoding="utf-8") as fh:
                json.dump(plan, fh, indent=2)
        except OSError as exc:
            print(f"ERROR: could not write output {args.output}: {exc}", file=sys.stderr)
            return 1

    print(render_summary(plan))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
