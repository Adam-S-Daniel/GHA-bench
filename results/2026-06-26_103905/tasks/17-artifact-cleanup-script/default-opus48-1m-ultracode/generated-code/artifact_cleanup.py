#!/usr/bin/env python3
"""Artifact cleanup planner (GitHub Actions maintenance task).

Initial slice: timestamp parsing and Artifact construction. The rest of the
behaviour (retention policies, plan, summary, CLI) is added in later TDD cycles.
"""

from __future__ import annotations

import argparse
import json
import sys
from dataclasses import dataclass
from datetime import datetime, timezone


class CleanupError(Exception):
    """Raised for invalid input so the CLI can report a meaningful message."""


def parse_timestamp(value: str) -> datetime:
    """Parse an ISO-8601 timestamp into a timezone-aware UTC datetime.

    Accepts a trailing ``Z`` (Zulu/UTC) which ``datetime.fromisoformat`` did not
    accept before Python 3.11; naive timestamps are assumed to be UTC.
    """
    if not isinstance(value, str):
        raise CleanupError(f"timestamp must be a string, got {type(value).__name__}")
    text = value.strip()
    if text.endswith("Z"):
        text = text[:-1] + "+00:00"
    try:
        dt = datetime.fromisoformat(text)
    except ValueError as exc:
        raise CleanupError(f"invalid timestamp '{value}': {exc}") from exc
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return dt.astimezone(timezone.utc)


@dataclass(frozen=True)
class Artifact:
    """A single stored artifact with the metadata the policies operate on."""

    name: str
    size: int
    created_at: datetime
    workflow_run_id: str


def _require(raw: dict, key: str):
    """Return ``raw[key]`` or raise a :class:`CleanupError` naming the field."""
    if key not in raw:
        raise CleanupError(f"artifact is missing required field '{key}'")
    return raw[key]


def parse_artifact(raw: dict) -> Artifact:
    """Build an :class:`Artifact` from a raw mapping, validating each field."""
    if not isinstance(raw, dict):
        raise CleanupError(f"artifact must be an object, got {type(raw).__name__}")

    name = _require(raw, "name")
    size = _require(raw, "size")
    created_at = _require(raw, "created_at")
    run_id = _require(raw, "workflow_run_id")

    if not isinstance(size, int) or isinstance(size, bool):
        raise CleanupError(f"artifact '{name}' has non-integer size: {size!r}")
    if size < 0:
        raise CleanupError(f"artifact '{name}' has negative size: {size}")

    return Artifact(
        name=str(name),
        size=size,
        created_at=parse_timestamp(created_at),
        workflow_run_id=str(run_id),
    )


def load_artifacts(raws: list) -> list[Artifact]:
    """Parse a list of raw artifact dicts, annotating errors with the index."""
    if not isinstance(raws, list):
        raise CleanupError(f"'artifacts' must be a list, got {type(raws).__name__}")
    artifacts: list[Artifact] = []
    for i, raw in enumerate(raws):
        try:
            artifacts.append(parse_artifact(raw))
        except CleanupError as exc:
            raise CleanupError(f"artifact at index {i}: {exc}") from exc
    return artifacts


# ---------------------------------------------------------------------------
# Retention policies and the planning engine.
# ---------------------------------------------------------------------------

# Reason tags attached to a deletion decision. Centralised so the report and the
# tests refer to the same strings.
REASON_MAX_AGE = "max-age"
REASON_KEEP_LATEST_N = "keep-latest-n"
REASON_MAX_TOTAL_SIZE = "max-total-size"


@dataclass(frozen=True)
class RetentionPolicy:
    """Configuration for the three independent retention rules.

    Each is optional (``None`` disables it):

    * ``max_age_days`` — delete artifacts strictly older than this many days.
    * ``keep_latest_n`` — within each workflow run keep only the N newest.
    * ``max_total_size`` — cap the total bytes of *retained* artifacts, evicting
      the oldest survivors until the cap is met.
    """

    max_age_days: float | None = None
    keep_latest_n: int | None = None
    max_total_size: int | None = None

    def __post_init__(self) -> None:
        if self.max_age_days is not None and self.max_age_days < 0:
            raise CleanupError("max_age_days must be >= 0")
        if self.keep_latest_n is not None and self.keep_latest_n < 0:
            raise CleanupError("keep_latest_n must be >= 0")
        if self.max_total_size is not None and self.max_total_size < 0:
            raise CleanupError("max_total_size must be >= 0")


@dataclass
class Decision:
    """The verdict for one artifact: kept, or deleted with one+ reasons."""

    artifact: Artifact
    reasons: list[str]

    @property
    def keep(self) -> bool:
        return not self.reasons


@dataclass
class DeletionPlan:
    """The full set of per-artifact decisions plus convenience aggregates."""

    decisions: list[Decision]
    now: datetime
    policy: RetentionPolicy

    @property
    def deleted(self) -> list[Decision]:
        return [d for d in self.decisions if not d.keep]

    @property
    def retained(self) -> list[Decision]:
        return [d for d in self.decisions if d.keep]

    @property
    def deleted_count(self) -> int:
        return len(self.deleted)

    @property
    def retained_count(self) -> int:
        return len(self.retained)

    @property
    def space_reclaimed(self) -> int:
        return sum(d.artifact.size for d in self.deleted)

    @property
    def retained_size(self) -> int:
        return sum(d.artifact.size for d in self.retained)

    @property
    def total_size(self) -> int:
        return sum(d.artifact.size for d in self.decisions)


def _sort_key_newest_first(art: Artifact) -> tuple:
    """Deterministic ordering: newest first, ties broken by name then run id."""
    return (-art.created_at.timestamp(), art.name, art.workflow_run_id)


def _sort_key_oldest_first(art: Artifact) -> tuple:
    """Deterministic ordering: oldest first, ties broken by name then run id."""
    return (art.created_at.timestamp(), art.name, art.workflow_run_id)


def build_plan(
    artifacts: list[Artifact],
    policy: RetentionPolicy,
    now: datetime,
) -> DeletionPlan:
    """Apply the retention policies and return a :class:`DeletionPlan`.

    The rules combine as a *union of deletion conditions*: an artifact is deleted
    if any rule flags it. Reasons accumulate, so a single artifact can be deleted
    for more than one reason. Order of application:

    1. ``max_age_days`` — flag anything strictly older than the cutoff.
    2. ``keep_latest_n`` — per workflow run, flag everything but the newest N.
    3. ``max_total_size`` — among the artifacts *still retained* after (1) and
       (2), evict the oldest until their combined size fits the budget.
    """
    reasons: dict[int, list[str]] = {id(a): [] for a in artifacts}

    # --- Rule 1: maximum age -------------------------------------------------
    if policy.max_age_days is not None:
        cutoff_seconds = policy.max_age_days * 86400
        for art in artifacts:
            age_seconds = (now - art.created_at).total_seconds()
            if age_seconds > cutoff_seconds:
                reasons[id(art)].append(REASON_MAX_AGE)

    # --- Rule 2: keep latest N per workflow run -----------------------------
    if policy.keep_latest_n is not None:
        groups: dict[str, list[Artifact]] = {}
        for art in artifacts:
            groups.setdefault(art.workflow_run_id, []).append(art)
        for group in groups.values():
            ordered = sorted(group, key=_sort_key_newest_first)
            for art in ordered[policy.keep_latest_n:]:
                reasons[id(art)].append(REASON_KEEP_LATEST_N)

    # --- Rule 3: maximum total retained size --------------------------------
    if policy.max_total_size is not None:
        retained = [a for a in artifacts if not reasons[id(a)]]
        running = sum(a.size for a in retained)
        if running > policy.max_total_size:
            # Evict oldest survivors first until we are within budget.
            for art in sorted(retained, key=_sort_key_oldest_first):
                if running <= policy.max_total_size:
                    break
                reasons[id(art)].append(REASON_MAX_TOTAL_SIZE)
                running -= art.size

    decisions = [Decision(artifact=a, reasons=reasons[id(a)]) for a in artifacts]
    return DeletionPlan(decisions=decisions, now=now, policy=policy)


# ---------------------------------------------------------------------------
# Summary, rendering and (mockable) execution.
# ---------------------------------------------------------------------------

def _human_size(num: int) -> str:
    """Format a byte count compactly (e.g. 5242880 -> '5.0 MB')."""
    value = float(num)
    for unit in ("B", "KB", "MB", "GB", "TB"):
        if value < 1024 or unit == "TB":
            return f"{value:.0f} {unit}" if unit == "B" else f"{value:.1f} {unit}"
        value /= 1024
    return f"{value:.1f} TB"


def summarize(plan: DeletionPlan, dry_run: bool = False) -> dict:
    """Reduce a plan to a JSON-serialisable summary dict."""
    deletions = [
        {
            "name": d.artifact.name,
            "size": d.artifact.size,
            "workflow_run_id": d.artifact.workflow_run_id,
            "created_at": d.artifact.created_at.isoformat(),
            "reasons": list(d.reasons),
        }
        for d in plan.deleted
    ]
    retained = [
        {
            "name": d.artifact.name,
            "size": d.artifact.size,
            "workflow_run_id": d.artifact.workflow_run_id,
            "created_at": d.artifact.created_at.isoformat(),
        }
        for d in plan.retained
    ]
    return {
        "dry_run": dry_run,
        "now": plan.now.isoformat(),
        "total_artifacts": len(plan.decisions),
        "retained_count": plan.retained_count,
        "deleted_count": plan.deleted_count,
        "space_reclaimed": plan.space_reclaimed,
        "retained_size": plan.retained_size,
        "total_size": plan.total_size,
        "deletions": deletions,
        "retained": retained,
    }


def render(plan: DeletionPlan, dry_run: bool = False, fmt: str = "text") -> str:
    """Render the plan as either a human-readable report or JSON.

    The ``text`` form ends with a block of ``KEY=value`` lines that downstream
    automation (and the act-based test harness) can grep for exact values.
    """
    summary = summarize(plan, dry_run=dry_run)
    if fmt == "json":
        return json.dumps(summary, indent=2, sort_keys=True)
    if fmt != "text":
        raise CleanupError(f"unknown output format '{fmt}' (use 'text' or 'json')")

    p = plan.policy
    header = "Artifact Cleanup Plan" + (" (DRY RUN)" if dry_run else "")
    lines = [header, "=" * len(header), f"Reference time (now): {plan.now.isoformat()}"]
    lines.append(
        "Policies: "
        f"max_age_days={p.max_age_days}, "
        f"keep_latest_n={p.keep_latest_n}, "
        f"max_total_size={p.max_total_size}"
    )
    lines.append("")

    lines.append(f"DELETE ({plan.deleted_count}):")
    for d in plan.deleted:
        a = d.artifact
        lines.append(
            f"  - {a.name}  {a.size} B  run={a.workflow_run_id}  "
            f"created={a.created_at.date()}  reasons={','.join(d.reasons)}"
        )
    lines.append("")
    lines.append(f"RETAIN ({plan.retained_count}):")
    for d in plan.retained:
        a = d.artifact
        lines.append(
            f"  - {a.name}  {a.size} B  run={a.workflow_run_id}  "
            f"created={a.created_at.date()}"
        )
    lines.append("")

    verb = "Would reclaim" if dry_run else "Reclaimed"
    lines.append("Summary:")
    lines.append(f"  Total artifacts:  {summary['total_artifacts']}")
    lines.append(f"  Retained:         {summary['retained_count']}")
    lines.append(f"  Deleted:          {summary['deleted_count']}")
    lines.append(
        f"  {verb}:     {summary['space_reclaimed']} B "
        f"({_human_size(summary['space_reclaimed'])})"
    )
    lines.append(f"  Retained size:    {summary['retained_size']} B")
    lines.append("")

    # Machine-readable block (stable KEY=value lines for assertions / CI).
    lines.append("--- machine-readable ---")
    lines.append(f"DRY_RUN={'true' if dry_run else 'false'}")
    lines.append(f"TOTAL_ARTIFACTS={summary['total_artifacts']}")
    lines.append(f"RETAINED_COUNT={summary['retained_count']}")
    lines.append(f"DELETED_COUNT={summary['deleted_count']}")
    lines.append(f"SPACE_RECLAIMED={summary['space_reclaimed']}")
    lines.append(f"RETAINED_SIZE={summary['retained_size']}")
    return "\n".join(lines)


def execute_deletion(plan: DeletionPlan, dry_run: bool, deleter) -> int:
    """Carry out the plan.

    In dry-run mode nothing is deleted and ``deleter`` is never invoked. Otherwise
    ``deleter`` is called once per artifact slated for deletion. Any exception
    raised by ``deleter`` is wrapped in a :class:`CleanupError` that identifies the
    artifact, so a failing backend produces a meaningful message rather than a
    bare traceback.

    Returns the number of artifacts actually deleted (0 in dry-run).
    """
    if dry_run:
        return 0
    count = 0
    for d in plan.deleted:
        try:
            deleter(d.artifact)
        except Exception as exc:  # surface backend failures meaningfully
            raise CleanupError(
                f"failed to delete artifact '{d.artifact.name}' "
                f"(run {d.artifact.workflow_run_id}): {exc}"
            ) from exc
        count += 1
    return count


# ---------------------------------------------------------------------------
# Config-file loading and the CLI.
# ---------------------------------------------------------------------------

@dataclass
class InputConfig:
    """Everything the planner needs, loaded from a single JSON config file."""

    artifacts: list[Artifact]
    policy: RetentionPolicy
    now: datetime
    dry_run: bool


def load_input(path: str) -> InputConfig:
    """Load and validate the JSON config at ``path``.

    Expected shape::

        {
          "now": "2026-06-28T00:00:00Z",   # optional; defaults to current UTC
          "dry_run": true,                  # optional; defaults to true (safe)
          "policies": {"max_age_days": 30, "keep_latest_n": 2, "max_total_size": 1500},
          "artifacts": [{"name", "size", "created_at", "workflow_run_id"}, ...]
        }
    """
    try:
        with open(path, "r", encoding="utf-8") as fh:
            raw = json.load(fh)
    except FileNotFoundError as exc:
        raise CleanupError(f"input config not found: {path}") from exc
    except OSError as exc:
        raise CleanupError(f"could not read input config {path}: {exc}") from exc
    except json.JSONDecodeError as exc:
        raise CleanupError(f"invalid JSON in {path}: {exc}") from exc

    if not isinstance(raw, dict):
        raise CleanupError(f"input config {path} must be a JSON object")

    artifacts = load_artifacts(raw.get("artifacts", []))

    policies = raw.get("policies", {})
    if not isinstance(policies, dict):
        raise CleanupError("'policies' must be an object")
    policy = RetentionPolicy(
        max_age_days=policies.get("max_age_days"),
        keep_latest_n=policies.get("keep_latest_n"),
        max_total_size=policies.get("max_total_size"),
    )

    now = parse_timestamp(raw["now"]) if raw.get("now") else datetime.now(timezone.utc)
    dry_run = bool(raw.get("dry_run", True))

    return InputConfig(artifacts=artifacts, policy=policy, now=now, dry_run=dry_run)


def _log_deleter(artifact: Artifact) -> None:
    """Default deleter for non-dry-run CLI use.

    There is no real GitHub API in this exercise (the data is mock), so the
    default simply records the intended deletion on stderr. A real deployment
    would replace this with a call to the artifacts REST API.
    """
    print(
        f"[delete] {artifact.name} (run {artifact.workflow_run_id}, "
        f"{artifact.size} B)",
        file=sys.stderr,
    )


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="artifact_cleanup",
        description="Apply retention policies to a list of artifacts and emit a "
        "deletion plan with a summary.",
    )
    parser.add_argument(
        "--input", "-i", required=True,
        help="Path to the JSON config (artifacts + policies + options).",
    )
    parser.add_argument(
        "--format", "-f", choices=("text", "json"), default="text",
        help="Output format (default: text).",
    )
    parser.add_argument(
        "--now", help="Override the reference 'now' (ISO-8601) for age checks.",
    )
    dr = parser.add_mutually_exclusive_group()
    dr.add_argument(
        "--dry-run", dest="dry_run", action="store_true", default=None,
        help="Plan only; do not invoke the deleter (overrides the config).",
    )
    dr.add_argument(
        "--no-dry-run", dest="dry_run", action="store_false",
        help="Actually execute deletions (overrides the config).",
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    """CLI entry point. Returns a process exit code (0 = success)."""
    parser = _build_parser()
    args = parser.parse_args(argv)

    try:
        config = load_input(args.input)

        # CLI flags override the config file when provided.
        now = parse_timestamp(args.now) if args.now else config.now
        dry_run = config.dry_run if args.dry_run is None else args.dry_run

        plan = build_plan(config.artifacts, config.policy, now)
        execute_deletion(plan, dry_run=dry_run, deleter=_log_deleter)
        print(render(plan, dry_run=dry_run, fmt=args.format))
        return 0
    except CleanupError as exc:
        print(f"Error: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
