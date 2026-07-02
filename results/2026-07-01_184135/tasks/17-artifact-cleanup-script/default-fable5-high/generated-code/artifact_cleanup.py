"""Artifact retention/cleanup planner.

Given a list of CI artifacts (name, size, creation date, workflow run id)
and a retention policy (max age, keep-latest-N per workflow run, max total
size), this module decides which artifacts to delete and produces a
deletion plan with a summary. Deletion itself is pluggable (mockable) and
supports a dry-run mode.
"""

import argparse
import json
import sys
from dataclasses import dataclass, field
from datetime import datetime, timezone


class CleanupError(Exception):
    """Raised for any user-facing input/validation problem."""


@dataclass(frozen=True)
class Artifact:
    """One CI artifact as reported by the (mocked) artifact API."""

    name: str
    size_bytes: int
    created_at: datetime  # timezone-aware, UTC
    workflow_run_id: int


def _parse_timestamp(raw, context):
    """Parse an ISO-8601 timestamp into an aware UTC datetime.

    `context` names the field being parsed (e.g. "artifact #3: 'created_at'")
    so error messages point at the offending input.
    """
    if not isinstance(raw, str):
        raise CleanupError(f"{context} must be an ISO-8601 string, got {raw!r}")
    try:
        parsed = datetime.fromisoformat(raw.replace("Z", "+00:00"))
    except ValueError as exc:
        raise CleanupError(f"{context}: invalid ISO-8601 timestamp {raw!r}: {exc}") from exc
    if parsed.tzinfo is None:
        # Treat naive timestamps as UTC so comparisons are always well-defined.
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed.astimezone(timezone.utc)


def load_artifacts(path):
    """Load and validate the artifact inventory from a JSON file."""
    raw = _read_json(path, what="artifact inventory")
    if not isinstance(raw, list):
        raise CleanupError(f"artifact inventory {path!r} must be a JSON array of artifacts")

    artifacts = []
    for index, entry in enumerate(raw):
        context = f"artifact #{index}"
        if not isinstance(entry, dict):
            raise CleanupError(f"{context}: expected a JSON object, got {type(entry).__name__}")
        missing = [key for key in ("name", "size_bytes", "created_at", "workflow_run_id")
                   if key not in entry]
        if missing:
            raise CleanupError(f"{context}: missing required field(s): {', '.join(missing)}")
        size = entry["size_bytes"]
        if not isinstance(size, int) or isinstance(size, bool) or size < 0:
            raise CleanupError(
                f"{context}: 'size_bytes' must be a non-negative integer, got {size!r}")
        artifacts.append(Artifact(
            name=entry["name"],
            size_bytes=size,
            created_at=_parse_timestamp(entry["created_at"], f"{context}: 'created_at'"),
            workflow_run_id=entry["workflow_run_id"],
        ))
    return artifacts


@dataclass(frozen=True)
class Policy:
    """Retention policy. A rule set to None is disabled."""

    max_age_days: int | None = None
    keep_latest_n: int | None = None
    max_total_size_bytes: int | None = None


_POLICY_KEYS = ("max_age_days", "keep_latest_n", "max_total_size_bytes")


def load_policy(path):
    """Load and validate the retention policy from a JSON file."""
    raw = _read_json(path, what="retention policy")
    if not isinstance(raw, dict):
        raise CleanupError(f"retention policy {path!r} must be a JSON object")

    unknown = sorted(set(raw) - set(_POLICY_KEYS))
    if unknown:
        raise CleanupError(
            f"retention policy has unknown key(s): {', '.join(unknown)} "
            f"(expected any of: {', '.join(_POLICY_KEYS)})")

    values = {}
    for key in _POLICY_KEYS:
        value = raw.get(key)
        if value is not None and (
                not isinstance(value, int) or isinstance(value, bool) or value < 0):
            raise CleanupError(
                f"retention policy: '{key}' must be a non-negative integer or null, "
                f"got {value!r}")
        values[key] = value
    return Policy(**values)


def format_size(size_bytes):
    """Render a byte count for humans: 512 B, 1.50 KB, 9.00 MB, 2.00 GB."""
    if size_bytes < 1024:
        return f"{size_bytes} B"
    value = float(size_bytes)
    for unit in ("KB", "MB", "GB"):
        value /= 1024.0
        if value < 1024 or unit == "GB":
            return f"{value:.2f} {unit}"
    raise AssertionError("unreachable")


@dataclass
class Decision:
    """The verdict for one artifact: keep it, or delete it (with a reason)."""

    artifact: Artifact
    action: str  # "keep" | "delete"
    reason: str | None = None


@dataclass
class Plan:
    """Full deletion plan: one Decision per artifact, oldest first."""

    decisions: list = field(default_factory=list)

    @property
    def deleted(self):
        return [d.artifact for d in self.decisions if d.action == "delete"]

    @property
    def retained(self):
        return [d.artifact for d in self.decisions if d.action == "keep"]

    @property
    def reclaimed_bytes(self):
        return sum(a.size_bytes for a in self.deleted)

    @property
    def retained_bytes(self):
        return sum(a.size_bytes for a in self.retained)


def build_plan(artifacts, policy, now):
    """Apply the retention policy and return the deletion Plan.

    Rules are applied in a fixed, documented order:
      1. max_age_days      -- anything older than the limit is deleted.
      2. keep_latest_n     -- per workflow run, only the N newest survive.
      3. max_total_size    -- evict the oldest artifacts still retained
                              until the retained total fits under the cap.
    Rules are independent (each ranks the full inventory); when several
    rules would delete the same artifact, the earliest rule's reason wins.
    Decisions are reported oldest-first (ties broken by name) so output is
    deterministic regardless of input order.
    """
    ordered = sorted(artifacts, key=lambda a: (a.created_at, a.name))
    reasons = {}  # id(artifact) -> deletion reason (first rule to fire wins)

    # Rule 1: max age.
    if policy.max_age_days is not None:
        for art in ordered:
            age_days = (now - art.created_at).days
            if age_days > policy.max_age_days:
                reasons[id(art)] = (
                    f"max-age: {age_days} days old exceeds limit of "
                    f"{policy.max_age_days} days")

    # Rule 2: keep only the newest N artifacts of each workflow run.
    if policy.keep_latest_n is not None:
        by_run = {}
        for art in ordered:
            by_run.setdefault(art.workflow_run_id, []).append(art)
        for run_id, group in by_run.items():
            newest_first = sorted(
                group, key=lambda a: (a.created_at, a.name), reverse=True)
            for rank, art in enumerate(newest_first, start=1):
                if rank > policy.keep_latest_n:
                    reasons.setdefault(id(art), (
                        f"keep-latest: rank {rank} of {len(group)} in "
                        f"workflow run {run_id} exceeds keep-latest limit "
                        f"of {policy.keep_latest_n}"))

    # Rule 3: cap the total size of what is left, evicting oldest first.
    if policy.max_total_size_bytes is not None:
        retained = [a for a in ordered if id(a) not in reasons]
        total = sum(a.size_bytes for a in retained)
        for art in retained:  # oldest first, thanks to `ordered`
            if total <= policy.max_total_size_bytes:
                break
            reasons[id(art)] = (
                f"max-total-size: retained total {format_size(total)} "
                f"exceeds limit of {format_size(policy.max_total_size_bytes)}")
            total -= art.size_bytes

    plan = Plan()
    for art in ordered:
        reason = reasons.get(id(art))
        if reason is None:
            plan.decisions.append(Decision(art, "keep"))
        else:
            plan.decisions.append(Decision(art, "delete", reason))
    return plan


def render_report(plan, dry_run):
    """Render the deletion plan and summary as printable text.

    The format is stable and asserted on verbatim by the tests (and by the
    CI harness that greps the workflow output), so change it deliberately.
    """
    lines = [
        "Artifact Cleanup Plan",
        "=====================",
        "Mode: DRY RUN (no artifacts will be deleted)" if dry_run else "Mode: APPLY",
        "",
    ]
    for decision in plan.decisions:
        size = format_size(decision.artifact.size_bytes)
        if decision.action == "delete":
            lines.append(f"DELETE {decision.artifact.name} ({size}) - {decision.reason}")
        else:
            lines.append(f"KEEP   {decision.artifact.name} ({size})")
    if plan.decisions:
        lines.append("")
    lines += [
        "Summary:",
        f"  Total artifacts: {len(plan.decisions)}",
        f"  Retained:        {len(plan.retained)}",
        f"  Deleted:         {len(plan.deleted)}",
        f"  Space reclaimed: {format_size(plan.reclaimed_bytes)}",
        f"  Space retained:  {format_size(plan.retained_bytes)}",
    ]
    return "\n".join(lines)


def execute_plan(plan, deleter, dry_run):
    """Carry out (or, in dry-run mode, only describe) the deletions.

    `deleter` is any object with a `delete(artifact)` method -- the real
    artifact API client in production, a recording mock in tests. Returns
    the progress lines to print.
    """
    to_delete = plan.deleted  # already oldest-first
    if dry_run:
        return [
            f"Dry run: {len(to_delete)} artifact(s) would be deleted, "
            f"reclaiming {format_size(plan.reclaimed_bytes)}"
        ]
    if not to_delete:
        return ["No artifacts to delete."]

    lines = []
    for artifact in to_delete:
        try:
            deleter.delete(artifact)
        except Exception as exc:
            raise CleanupError(
                f"failed to delete artifact {artifact.name!r} "
                f"(workflow run {artifact.workflow_run_id}): {exc}") from exc
        lines.append(
            f"Deleting artifact {artifact.name!r} "
            f"(workflow run {artifact.workflow_run_id})... deleted")
    lines.append(
        f"Deleted {len(to_delete)} artifact(s), "
        f"reclaimed {format_size(plan.reclaimed_bytes)}")
    return lines


def _read_json(path, what):
    """Read a JSON document with meaningful error messages."""
    try:
        with open(path, "r", encoding="utf-8") as fh:
            return json.load(fh)
    except FileNotFoundError as exc:
        raise CleanupError(f"{what} file not found: {path!r}") from exc
    except json.JSONDecodeError as exc:
        raise CleanupError(f"{what} file {path!r} is not valid JSON: {exc}") from exc


class NullDeleter:
    """Deleter for mock inventories: accepts every delete without side effects.

    Swap this for a real artifact-API client (same one-method interface)
    to delete artifacts for real.
    """

    def delete(self, artifact):
        return None


def main(argv=None, stdout=sys.stdout, stderr=sys.stderr):
    """CLI entry point. Returns a process exit code (0 ok, 2 input error)."""
    parser = argparse.ArgumentParser(
        prog="artifact_cleanup",
        description="Plan (and optionally apply) artifact retention cleanup.")
    parser.add_argument("--artifacts", required=True,
                        help="JSON file with the artifact inventory")
    parser.add_argument("--policy", required=True,
                        help="JSON file with the retention policy")
    parser.add_argument("--now", default=None,
                        help="ISO-8601 reference time (default: current UTC "
                             "time); pin it for reproducible runs")
    parser.add_argument("--apply", action="store_true",
                        help="actually delete; default is a dry run")
    args = parser.parse_args(argv)

    try:
        if args.now is not None:
            now = _parse_timestamp(args.now, context="--now")
        else:
            now = datetime.now(timezone.utc)
        artifacts = load_artifacts(args.artifacts)
        policy = load_policy(args.policy)
        plan = build_plan(artifacts, policy, now=now)
        dry_run = not args.apply
        print(render_report(plan, dry_run=dry_run), file=stdout)
        print("", file=stdout)
        for line in execute_plan(plan, NullDeleter(), dry_run=dry_run):
            print(line, file=stdout)
    except CleanupError as exc:
        print(f"error: {exc}", file=stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
