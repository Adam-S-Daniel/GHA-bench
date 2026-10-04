#!/usr/bin/env python3
"""
Benchmark runner for comparing Claude Code agent scripting across languages.
Invokes Claude Code CLI subagents on scripting tasks under different language constraints.
"""

import argparse
import fcntl
import json
import os
import re
import shutil
import subprocess
import sys
import time
import threading
from datetime import datetime, timezone
from pathlib import Path

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

INSTRUCTIONS_FILE = "benchmark-instructions-v4.md"
INSTRUCTIONS_VERSION = "v4"

from models import COST_PER_MTOK, MODELS  # noqa: E402  (single source of truth)

LANGUAGE_EXTENSIONS = {
    ".py": "python", ".js": "javascript", ".ts": "typescript", ".sh": "bash",
    ".ps1": "powershell", ".psm1": "powershell", ".psd1": "powershell",
    ".cs": "csharp", ".rb": "ruby", ".go": "go", ".rs": "rust",
    ".java": "java", ".pl": "perl", ".lua": "lua", ".r": "r",
    ".yml": "yaml", ".yaml": "yaml",
}

INSTALL_PATTERNS = [
    r"apt[\s-]get\s+install", r"apt\s+install", r"pip\s+install", r"pip3\s+install",
    r"npm\s+install", r"yarn\s+add", r"dotnet\s+tool\s+install", r"Install-Module",
    r"Install-Package", r"brew\s+install", r"snap\s+install", r"cargo\s+install",
    r"gem\s+install", r"go\s+install",
]

# ---------------------------------------------------------------------------
# Task Definitions
# ---------------------------------------------------------------------------

TASKS = [
    {
        "id": "01-csv-report-generator",
        "name": "CSV Report Generator",
        "category": "Data Transformation",
        "description": (
            "Read a CSV file of employee records (name, department, salary, hire_date, status), "
            "filter to active employees only, compute aggregates (average salary by department, "
            "headcount by department, overall statistics), and output a formatted summary report "
            "to a text file. Create sample CSV test data as part of the test fixtures."
        ),
    },
    {
        "id": "02-log-file-analyzer",
        "name": "Log File Analyzer",
        "category": "Text Processing",
        "description": (
            "Parse a log file containing mixed formats (syslog-style lines and JSON-structured lines), "
            "extract all error and warning entries, produce a frequency table of error types with their "
            "first and last occurrence timestamps, and output the analysis as both a human-readable table "
            "and a JSON file. Create sample log data as test fixtures."
        ),
    },
    {
        "id": "03-directory-tree-sync",
        "name": "Directory Tree Sync",
        "category": "File Manipulation",
        "description": (
            "Compare two directory trees, identify files that differ (by content hash — SHA-256), "
            "files that exist in only one tree, and generate a sync plan. Implement both a dry-run "
            "mode (report only) and an execute mode (perform the sync). All file operations should "
            "be testable with mock directory structures."
        ),
    },
    {
        "id": "04-rest-api-client",
        "name": "REST API Client",
        "category": "API Interaction",
        "description": (
            "Build a script that queries a REST API (use JSONPlaceholder — https://jsonplaceholder.typicode.com), "
            "fetches posts and their comments, handles pagination, implements retry with exponential backoff "
            "on failure, and caches results locally in JSON files. Mock the HTTP calls for testing."
        ),
    },
    {
        "id": "05-process-monitor",
        "name": "Process Monitor",
        "category": "System Administration",
        "description": (
            "Create a script that reads process information (CPU%, memory, PID, name), filters by "
            "configurable resource usage thresholds, identifies the top N resource consumers, and "
            "generates an alert report. All process data must be mockable for testing — do not rely "
            "on live system state in tests."
        ),
    },
    {
        "id": "06-config-file-migrator",
        "name": "Config File Migrator",
        "category": "Data Transformation",
        "description": (
            "Read a configuration file in INI format, validate it against a simple schema (required keys, "
            "value types), and output equivalent configurations in JSON and YAML formats. Handle sections, "
            "comments, multi-line values, and type coercion (strings to numbers/booleans where appropriate). "
            "Create test fixtures with various edge cases."
        ),
    },
    {
        "id": "07-batch-file-renamer",
        "name": "Batch File Renamer",
        "category": "File Automation",
        "description": (
            "Rename files in a directory using regex-based patterns. Support: preview mode (show what would "
            "change without doing it), undo capability (generate an undo script that reverses the renames), "
            "and conflict detection (two files would get the same name). Test with mock file system structures."
        ),
    },
    {
        "id": "08-database-seed-script",
        "name": "Database Seed Script",
        "category": "Process Automation",
        "description": (
            "Create a SQLite database with a schema (users, orders, products tables with foreign keys), "
            "generate realistic mock data using deterministic randomization (seeded RNG), insert the data "
            "respecting referential integrity, and run verification queries that confirm data consistency. "
            "Tests should verify schema, data integrity, and query results."
        ),
    },
    {
        "id": "09-error-retry-pipeline",
        "name": "Error Retry Pipeline",
        "category": "Error Handling",
        "description": (
            "Build a pipeline that processes items from a queue (mocked), where processing can fail randomly. "
            "Implement: exponential backoff retry (configurable max retries), dead-letter queue for permanently "
            "failed items, progress reporting (items processed, failed, retrying), and a final summary. All "
            "queue and processing operations must be mockable."
        ),
    },
    {
        "id": "10-multi-file-search-replace",
        "name": "Multi-file Search and Replace",
        "category": "Text Processing",
        "description": (
            "Recursively search files matching a glob pattern for a regex pattern, perform search-and-replace "
            "with: preview mode (show matches with context without modifying), backup creation (copy originals "
            "before modifying), and a summary report of all changes made (file, line number, old text, new text). "
            "Test with mock directory structures and files."
        ),
    },
    {
        "id": "11-semantic-version-bumper",
        "name": "Semantic Version Bumper",
        "category": "GitHub Actions / Release Automation",
        "description": (
            "Parse a version file (or package.json) containing a semantic version string, determine the next "
            "version based on conventional commit messages (feat -> minor, fix -> patch, breaking -> major), "
            "update the version file, generate a changelog entry from the commits, and output the new version. "
            "Create mock commit logs as test fixtures."
        ),
    },
    {
        "id": "12-pr-label-assigner",
        "name": "PR Label Assigner",
        "category": "GitHub Actions / Triage",
        "description": (
            "Given a list of changed file paths (simulating a PR's changed files), apply labels based on "
            "configurable path-to-label mapping rules (e.g., docs/** -> documentation, src/api/** -> api, "
            "*.test.* -> tests). Support glob patterns, multiple labels per file, and priority ordering "
            "when rules conflict. Output the final label set. Mock the file list for testing."
        ),
    },
    {
        "id": "13-dependency-license-checker",
        "name": "Dependency License Checker",
        "category": "GitHub Actions / Compliance",
        "description": (
            "Parse a dependency manifest (package.json, requirements.txt, or similar), extract dependency "
            "names and versions, check each against an allow-list and deny-list of licenses (provided as "
            "config), and generate a compliance report listing each dependency's license status (approved, "
            "denied, unknown). Mock the license lookup for testing."
        ),
    },
    # Task 14 (Docker Image Tag Generator) archived — redundant with Task 16.
    # See archived-tasks/14-docker-image-tag-generator.md for definition and rationale.
    {
        "id": "15-test-results-aggregator",
        "name": "Test Results Aggregator",
        "category": "GitHub Actions / CI Reporting",
        "description": (
            "Parse test result files in multiple formats (JUnit XML, and JSON), aggregate results across "
            "multiple files (simulating a matrix build), compute totals (passed, failed, skipped, duration), "
            "identify flaky tests (passed in some runs, failed in others), and generate a markdown summary "
            "suitable for a GitHub Actions job summary. Create sample test result files as fixtures."
        ),
    },
    {
        "id": "16-environment-matrix-generator",
        "name": "Environment Matrix Generator",
        "category": "GitHub Actions / CI Configuration",
        "description": (
            "Given a configuration describing OS options, language versions, and feature flags, generate a "
            "build matrix (as JSON) suitable for GitHub Actions strategy.matrix. Support include/exclude "
            "rules, max-parallel limits, and fail-fast configuration. Validate that the matrix doesn't exceed "
            "a maximum size. Output the complete matrix JSON."
        ),
    },
    {
        "id": "17-artifact-cleanup-script",
        "name": "Artifact Cleanup Script",
        "category": "GitHub Actions / Maintenance",
        "description": (
            "Given a list of artifacts with metadata (name, size, creation date, workflow run ID — provided "
            "as mock data), apply retention policies (max age, max total size, keep-latest-N per workflow), "
            "determine which artifacts to delete, and generate a deletion plan with a summary (total space "
            "reclaimed, artifacts retained vs deleted). Support dry-run mode."
        ),
    },
    {
        "id": "18-secret-rotation-validator",
        "name": "Secret Rotation Validator",
        "category": "GitHub Actions / Security",
        "description": (
            "Given a configuration of secrets with metadata (name, last-rotated date, rotation policy in days, "
            "required-by services — all mock data), identify secrets that are expired or expiring within a "
            "configurable warning window, generate a rotation report, and output notifications grouped by "
            "urgency (expired, warning, ok). Support multiple output formats (markdown table, JSON)."
        ),
    },
]

# ---------------------------------------------------------------------------
# Prompt Templates
# ---------------------------------------------------------------------------

PROMPT_TEMPLATES = {
    "default": (
        "You are completing a scripting task. Choose whatever programming language you think is best for this task.\n\n"
        "TASK: {task_description}\n\n"
        "REQUIREMENTS:\n"
        "1. Use red/green TDD methodology: write a failing test FIRST, then write the minimum code to make it pass, then refactor. Repeat for each piece of functionality.\n"
        "2. Create mocks and test fixtures as necessary for testability.\n"
        "3. All tests must be runnable and must pass at the end.\n"
        "4. Include clear comments explaining your approach.\n"
        "5. Handle errors gracefully with meaningful error messages.\n\n"
        "Create your solution in the current working directory. Start by writing your first failing test."
    ),
    "powershell": (
        "You are completing a scripting task. You MUST use PowerShell as your implementation language.\n\n"
        "TASK: {task_description}\n\n"
        "REQUIREMENTS:\n"
        "1. Use red/green TDD methodology: write a failing test FIRST, then write the minimum code to make it pass, then refactor. Repeat for each piece of functionality.\n"
        "2. Create mocks and test fixtures as necessary for testability. Use Pester as the testing framework.\n"
        "3. All tests must be runnable with `Invoke-Pester` and must pass at the end.\n"
        "4. Include clear comments explaining your approach.\n"
        "5. Handle errors gracefully with meaningful error messages.\n\n"
        "Create your solution in the current working directory. Start by writing your first failing test."
    ),
    # Identical prompt to `powershell`; differs only in that the PowerShell tool
    # is enabled for this run (CLAUDE_CODE_USE_POWERSHELL_TOOL=1), so the agent
    # can invoke pwsh natively via the PowerShell tool instead of going through
    # the Bash tool. See https://code.claude.com/docs/en/tools-reference#powershell-tool
    "powershell-tool": (
        "You are completing a scripting task. You MUST use PowerShell as your implementation language.\n\n"
        "TASK: {task_description}\n\n"
        "REQUIREMENTS:\n"
        "1. Use red/green TDD methodology: write a failing test FIRST, then write the minimum code to make it pass, then refactor. Repeat for each piece of functionality.\n"
        "2. Create mocks and test fixtures as necessary for testability. Use Pester as the testing framework.\n"
        "3. All tests must be runnable with `Invoke-Pester` and must pass at the end.\n"
        "4. Include clear comments explaining your approach.\n"
        "5. Handle errors gracefully with meaningful error messages.\n\n"
        "Create your solution in the current working directory. Start by writing your first failing test."
    ),
    "bash": (
        "You are completing a scripting task. You MUST use Bash as your implementation language.\n\n"
        "TASK: {task_description}\n\n"
        "REQUIREMENTS:\n"
        "1. Use red/green TDD methodology: write a failing test FIRST, then write the minimum code to make it pass, then refactor. Repeat for each piece of functionality.\n"
        "2. Create mocks and test fixtures as necessary for testability. Use bats-core (bats) as the testing framework.\n"
        "3. All tests must be runnable with `bats` and must pass at the end.\n"
        "4. Include clear comments explaining your approach.\n"
        "5. Handle errors gracefully with meaningful error messages.\n"
        "6. Use `#!/usr/bin/env bash` shebang. Scripts must pass `shellcheck` and `bash -n` syntax validation.\n\n"
        "Create your solution in the current working directory. Start by writing your first failing test."
    ),
    "typescript-bun": (
        "You are completing a scripting task. You MUST use TypeScript with Bun as your implementation language and runtime.\n\n"
        "TASK: {task_description}\n\n"
        "REQUIREMENTS:\n"
        "1. Use red/green TDD methodology: write a failing test FIRST, then write the minimum code to make it pass, then refactor. Repeat for each piece of functionality.\n"
        "2. Create mocks and test fixtures as necessary for testability. Use Bun's built-in test runner (`bun test`).\n"
        "3. All tests must be runnable with `bun test` and must pass at the end.\n"
        "4. Include clear comments explaining your approach.\n"
        "5. Handle errors gracefully with meaningful error messages.\n"
        "6. Use TypeScript features: explicit types, interfaces, and type annotations. Run scripts with `bun run <file>.ts`.\n\n"
        "Create your solution in the current working directory. Start by writing your first failing test."
    ),
}

MODES = list(PROMPT_TEMPLATES.keys())

# GHA workflow requirement addendum — appended to prompts for tasks 11-18
GHA_TASK_IDS = {
    "11-semantic-version-bumper",
    "12-pr-label-assigner",
    "13-dependency-license-checker",
    # 14-docker-image-tag-generator archived — see archived-tasks/
    "15-test-results-aggregator",
    "16-environment-matrix-generator",
    "17-artifact-cleanup-script",
    "18-secret-rotation-validator",
}

GHA_WORKFLOW_ADDENDUM = """
GITHUB ACTIONS REQUIREMENT:
Create a GitHub Actions workflow file at .github/workflows/{task_slug}.yml that uses
your script in a real CI/CD pipeline. The workflow must:
- Use appropriate trigger events (push, pull_request, schedule, workflow_dispatch, etc.)
- Reference your script correctly
- Pass actionlint validation (valid YAML, valid action references, correct syntax)
- Include appropriate permissions, environment variables, and job dependencies
- Actually run successfully when executed locally with `act` (nektos/act)

Design your workflow so its steps work in an isolated Docker container — use
`actions/checkout@v4`, install dependencies your script needs, and run it.
Avoid steps requiring external services or secrets without sensible defaults.

IMPORTANT for PowerShell mode: Use `shell: pwsh` on your workflow run: steps instead
of invoking `pwsh -Command` or `pwsh -File` from bash. This avoids escaping issues
and works correctly in act containers. pwsh and Pester are pre-installed in the
container.

WORKFLOW VALIDATION:
Run `actionlint .github/workflows/{task_slug}.yml` and fix any errors. actionlint is
pre-installed. Iterate until it passes cleanly. Validate with actionlint BEFORE
running act — actionlint is instant, act takes 30-90 seconds per run.

ALL TESTS MUST RUN THROUGH ACT:
Every single test case must execute through the GitHub Actions workflow via `act`.
Do NOT test your script directly — all testing goes through the pipeline.

Structure your workflow to accept test fixture data and produce verifiable output.
Your test harness must:
1. For each test case: set up a temp git repo with your project files + that case's
   fixture data, run `act push --rm`, capture the output
2. Save all act output to `act-result.txt` in the current working directory (append
   each test case's output, clearly delimited)
3. Assert that act exited with code 0 for each case
4. Parse the act output and assert on EXACT EXPECTED VALUES — not just that output
   appeared, but that it matches the known-good result for that test case's input.
   For example: if your workflow bumps version 1.1.0 with a feat commit, assert
   the output contains exactly "1.2.0", not just "a version number"
5. Assert every job shows "Job succeeded"

The `act-result.txt` file MUST exist when done. It is a required artifact.
`act` and Docker are pre-installed. Limit yourself to at most 3 `act push` runs —
diagnose errors from the output rather than re-running blindly.

WORKFLOW STRUCTURE TESTS (also required):
- Parse the YAML and check expected structure (triggers, jobs, steps)
- Verify the workflow references your script files correctly (paths exist)
- Verify actionlint passes (assert exit code 0)
"""

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# The pusher thread wakes every PUSH_CHECK_INTERVAL seconds but only commits
# when at least one new cell has *completed* since the last commit. That makes
# the trigger "a cell finished" rather than a fixed wall-clock timer, so there
# is roughly one commit per result instead of a commit every minute that also
# captures in-progress workspace-before.txt noise. Each commit is still pushed
# immediately. (Was: commit + push unconditionally every 60s — an absurd number
# of near-empty commits, a holdover from when commits were the remote-monitoring
# channel; monitor.py now serves that purpose without touching git.)
PUSH_CHECK_INTERVAL = 90  # seconds between checks for newly-completed cells
INCREMENTAL_PREFIX = "Incremental benchmark results:"

# Directories to skip in workspace walkers (noise that inflates metrics)
SKIP_DIRS = {"node_modules", "__pycache__", ".pytest_cache", ".mypy_cache", "obj", "bin"}


# Environment variables a *parent* Claude Code session exports that would change
# how a benchmark cell behaves if the cell inherited them. They only exist when
# runner.py is launched from inside a Claude Code session — which is exactly the
# Claude-Code-on-the-web case (see run-benchmark-web.sh) — and each one is a
# silent confounder: CLAUDE_EFFORT/MAX_THINKING_TOKENS would override the cell's
# `--effort`, CLAUDE_CODE_SESSION_ID would stamp every cell with the parent's
# session id, CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH would cap the cell's
# subagents, and the nested-session markers change the CLI's own tool surface
# (an unscrubbed cell was measured at 40 tools vs 30 scrubbed). Scrubbed before
# the cell's own mode/effort variables are applied.
INHERITED_SESSION_ENV_VARS = (
    "CLAUDECODE",
    "CLAUDE_AFTER_LAST_COMPACT",
    "CLAUDE_AUTOCOMPACT_PCT_OVERRIDE",
    "CLAUDE_AUTO_BACKGROUND_TASKS",
    "CLAUDE_CODE_ADDITIONAL_DIRECTORIES_CLAUDE_MD",
    "CLAUDE_ADDITIONAL_DIRECTORIES",
    "CLAUDE_CODE_CHILD_SESSION",
    "CLAUDE_CODE_DEBUG",
    "CLAUDE_CODE_DIAGNOSTICS_FILE",
    "CLAUDE_CODE_EFFORT_LEVEL",
    "CLAUDE_CODE_ENTRYPOINT",
    "CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH",
    "CLAUDE_CODE_REMOTE",
    "CLAUDE_CODE_REMOTE_SESSION_ID",
    "CLAUDE_CODE_SESSION_ID",
    "CLAUDE_CODE_SYNC_SKILLS",
    "CLAUDE_CODE_TEE_SDK_STDOUT",
    "CLAUDE_CODE_USE_POWERSHELL_TOOL",
    "CLAUDE_CODE_WORKFLOWS",
    "CLAUDE_EFFORT",
    "CLAUDE_ENABLE_STREAM_WATCHDOG",
    "CLAUDE_PID",
    "MAX_THINKING_TOKENS",
)

# Markers a Claude Code cloud sandbox sets and a laptop does not.
CLOUD_ENV_MARKERS = ("CLAUDE_CODE_REMOTE", "CLAUDE_CODE_CONTAINER_ID",
                     "CLAUDE_CODE_REMOTE_SESSION_ID")


def log(msg: str) -> None:
    """Print progress to stderr."""
    print(f"[{datetime.now().strftime('%H:%M:%S')}] {msg}", file=sys.stderr, flush=True)


def detect_execution_environment(env: dict | None = None) -> str:
    """Where this runner is executing: 'claude-code-web' or 'local'.

    Recorded in system_info so a cloud run is never silently pooled with laptop
    runs — the two have different CPU/IO budgets and a different CLI tool
    surface, which is a real comparability caveat (see AGENTS.md).
    """
    env = os.environ if env is None else env
    return "claude-code-web" if any(env.get(k) for k in CLOUD_ENV_MARKERS) else "local"


def cell_env(base_env: dict, *, is_root: bool | None = None) -> dict:
    """Environment for one benchmark cell's `claude -p` subprocess.

    Drops the parent session's variables (see INHERITED_SESSION_ENV_VARS) and,
    when running as root, sets IS_SANDBOX=1 — `--dangerously-skip-permissions`
    refuses to start as root without it, and a cloud sandbox is always root.
    The value is forced rather than defaulted: the sandbox already exports
    IS_SANDBOX=yes, which the CLI does not accept (only "1" is honoured), so a
    setdefault here would leave every cell failing to start.
    Callers layer their own mode/effort variables on top of the result.
    """
    if is_root is None:
        is_root = getattr(os, "geteuid", lambda: 1)() == 0
    env = {k: v for k, v in base_env.items() if k not in INHERITED_SESSION_ENV_VARS}
    if is_root:
        env["IS_SANDBOX"] = "1"
    return env


def effort_capable_models(selected_models: list[tuple[str, str]]) -> list[str]:
    """Short names of the selected (short, model_id) pairs that take an
    `--effort` parameter — i.e. everything except Haiku 4.5 (model ids
    starting with `claude-haiku`). Used by main() to warn when `--effort`
    is unset but an effort-capable model is selected (issue #32): the
    CLI-default effort is version-dependent and unrecorded, so those cells
    can't be labeled with certainty afterwards."""
    return [short for short, model_id in selected_models
            if not model_id.startswith("claude-haiku")]


def _metrics_valid(path: Path) -> bool:
    """True only if `path` is a non-empty, parseable metrics.json.

    `--resume` treats a completed cell as one whose metrics.json exists. A bare
    existence check is unsafe: a write interrupted mid-flush (e.g. a session
    teardown killing the runner) leaves a 0-byte/corrupt metrics.json that would
    then be SKIPPED forever, silently leaving a hole in the matrix. Requiring a
    valid file means such a cell is re-run instead.
    """
    try:
        if not path.exists() or path.stat().st_size == 0:
            return False
        json.loads(path.read_text())
        return True
    except Exception:
        return False


# Held for the process lifetime so the advisory lock is released automatically
# on exit (even on SIGKILL) — no stale-lock cleanup needed.
_RUNNER_LOCK_FD = None


def acquire_single_runner_lock(repo_root: Path) -> None:
    """Guarantee only ONE runner.py runs at a time on this machine/repo.

    Two concurrent runners would execute benchmark cells simultaneously, and
    cells competing for CPU/Docker/PowerShell inflate each other's timing and
    cost — silently confounding the results. This happened once when a watchdog
    and a manual launch both started a runner. We take an exclusive, non-blocking
    advisory lock (flock) on a repo-level lockfile; a second runner refuses to
    start rather than corrupt the timing data. The lock auto-releases when the
    holder exits.
    """
    global _RUNNER_LOCK_FD
    lock_path = repo_root / ".runner.lock"
    _RUNNER_LOCK_FD = open(lock_path, "w")
    try:
        fcntl.flock(_RUNNER_LOCK_FD, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        print(
            f"ERROR: another runner.py already holds {lock_path}. Refusing to "
            "start a second concurrent runner — concurrent cells would confound "
            "timing/cost. Exiting.",
            file=sys.stderr,
        )
        sys.exit(2)
    _RUNNER_LOCK_FD.write(f"{os.getpid()}\n")
    _RUNNER_LOCK_FD.flush()


# Lock protects all git operations so the PeriodicPusher background thread
# and any foreground git work never overlap.
_git_lock = threading.Lock()


def git_push_results(
    repo_root: Path,
    branch: str,
    run_count: int,
    total_runs: int,
    *,
    final: bool = False,
) -> None:
    """Commit and push results (append-only, no history rewriting).

    Earlier versions squashed incremental commits via ``git reset --soft``,
    which corrupted the repo when concurrent git operations occurred (e.g.
    manual rebase while the background pusher was running).  Now we simply
    append commits — safe for concurrency, easy to squash later if desired.
    """
    with _git_lock:
        try:
            status = subprocess.run(
                ["git", "status", "--porcelain", "results/"],
                cwd=str(repo_root), capture_output=True, text=True, timeout=10,
            )
            if not status.stdout.strip():
                return  # nothing new to commit

            # Stage results
            subprocess.run(
                ["git", "add", "results/"],
                cwd=str(repo_root), capture_output=True, timeout=10,
            )

            if final:
                msg = f"Benchmark results: {run_count}/{total_runs} runs completed"
            else:
                msg = f"{INCREMENTAL_PREFIX} {run_count}/{total_runs} runs completed"

            subprocess.run(
                ["git", "commit", "-m", msg],
                cwd=str(repo_root), capture_output=True, timeout=30,
            )

            push_args = ["git", "push", "-u", "origin", branch]
            push = subprocess.run(push_args, capture_output=True, text=True,
                                  timeout=60, cwd=str(repo_root))
            tag = f"{run_count}/{total_runs} done{', FINAL' if final else ''}"
            if push.returncode == 0:
                log(f"  [push] Pushed results ({tag})")
            else:
                # Do NOT claim success on a failed push — a silently-failing
                # push (e.g. a broken pre-push hook) once hid 8h of un-backed-up
                # commits. Commits are local and safe; surface the failure.
                err = (push.stderr or push.stdout or "(no output)").strip().splitlines()
                log(f"  [push] WARNING: push FAILED ({tag}); committed locally only. "
                    f"git push exit {push.returncode}: {err[-1] if err else '?'}")
        except Exception as e:
            log(f"  [push] Warning: commit/push failed: {e}")


class PeriodicPusher:
    """Background thread that periodically pushes results to git."""

    def __init__(self, repo_root: Path, branch: str, total_runs: int, run_dir: Path):
        self.repo_root = repo_root
        self.branch = branch
        self.total_runs = total_runs
        self.run_dir = run_dir
        self.run_count = 0
        self.all_metrics: list[dict] = []
        self._stop = threading.Event()
        self._thread = threading.Thread(target=self._run, daemon=True)

    def start(self):
        self._thread.start()

    def update(self, count: int, all_metrics: list[dict]):
        self.run_count = count
        self.all_metrics = list(all_metrics)

    def stop(self):
        self._stop.set()
        self._thread.join(timeout=120)

    def _run(self):
        last_pushed = 0
        while not self._stop.wait(PUSH_CHECK_INTERVAL):
            if self.run_count <= last_pushed:
                continue  # no new completed cell since last commit — don't churn git
            try:
                generate_results_md(self.run_dir, self.all_metrics, self.total_runs, self.run_count)
            except Exception as e:
                log(f"  [push] Warning: results.md generation failed: {e}")
            git_push_results(self.repo_root, self.branch, self.run_count, self.total_runs)
            last_pushed = self.run_count


def capture_workspace_listing(workspace: Path) -> str:
    """Return a recursive file listing of the workspace directory."""
    lines = []
    for root, dirs, files in os.walk(workspace):
        # skip hidden dirs, but allow .github/
        dirs[:] = [d for d in dirs if (not d.startswith(".") or d == ".github") and d not in SKIP_DIRS]
        level = len(Path(root).relative_to(workspace).parts)
        indent = "  " * level
        lines.append(f"{indent}{Path(root).name}/")
        for f in sorted(files):
            if not f.startswith("."):
                fpath = Path(root) / f
                try:
                    size = fpath.stat().st_size
                except OSError:
                    size = 0
                lines.append(f"{indent}  {f} ({size} bytes)")
    return "\n".join(lines) if lines else "(empty)"


def copy_generated_files(workspace: Path, dest: Path) -> list[str]:
    """Copy non-instruction, non-hidden files from workspace to dest. Return list of relative paths."""
    dest.mkdir(parents=True, exist_ok=True)
    copied = []
    for root, dirs, files in os.walk(workspace):
        dirs[:] = [d for d in dirs if (not d.startswith(".") or d == ".github") and d not in SKIP_DIRS]
        for f in sorted(files):
            if f.startswith(".") or f == INSTRUCTIONS_FILE:
                continue
            src = Path(root) / f
            rel = src.relative_to(workspace)
            dst = dest / rel
            dst.parent.mkdir(parents=True, exist_ok=True)
            try:
                shutil.copy2(src, dst)
                copied.append(str(rel))
            except Exception as e:
                log(f"  Warning: could not copy {rel}: {e}")
    return copied


def estimate_tokens(text: str) -> int:
    """Rough token estimate: chars / 4."""
    return len(text) // 4


def compute_language_breakdown(directory: Path) -> dict:
    """Compute language breakdown by lines of code from file extensions."""
    lang_lines: dict[str, int] = {}
    total = 0
    for root, dirs, files in os.walk(directory):
        dirs[:] = [d for d in dirs if not d.startswith(".") and d not in SKIP_DIRS]
        for f in files:
            if f.startswith("."):
                continue
            ext = Path(f).suffix.lower()
            lang = LANGUAGE_EXTENSIONS.get(ext)
            if lang:
                try:
                    lines = len((Path(root) / f).read_text(errors="replace").splitlines())
                    lang_lines[lang] = lang_lines.get(lang, 0) + lines
                    total += lines
                except Exception:
                    pass
    if total == 0:
        return {}
    return {lang: round(100 * count / total, 1) for lang, count in sorted(lang_lines.items(), key=lambda x: -x[1])}


def get_all_code_text(directory: Path) -> str:
    """Get all code text from files in directory for token counting."""
    texts = []
    for root, dirs, files in os.walk(directory):
        dirs[:] = [d for d in dirs if not d.startswith(".") and d not in SKIP_DIRS]
        for f in files:
            if f.startswith(".") or f == INSTRUCTIONS_FILE:
                continue
            try:
                texts.append((Path(root) / f).read_text(errors="replace"))
            except Exception:
                pass
    return "\n".join(texts)


# Import results generation from the standalone module.
# These were previously defined here; they now live in generate_results.py
# so they can be run independently.
from generate_results import (  # noqa: E402
    generate_results_md,
    _detect_traps,
    _categorize_tool_time,
    _geomean,
)


# ---------------------------------------------------------------------------
# Stream Parsing
# ---------------------------------------------------------------------------

def parse_stream_output(timestamped_lines: list[tuple[int, str]]) -> dict:
    """Parse timestamped JSON stream lines from claude CLI and extract metrics.

    Each entry is (timestamp_ms, json_line) where timestamp_ms is wall-clock
    milliseconds since epoch, captured in real-time as lines arrived from the
    CLI subprocess.
    """
    events = []  # (timestamp_ms, parsed_obj)
    console_lines = []
    claude_code_version = ""
    model_used = ""
    result_data = {}
    init_data = {}
    compaction_count = 0
    error_count = 0
    error_details = []
    install_commands = []
    tools_installed = []
    interpreter_versions = {}

    # Track pending tool_use events by ID for duration calculation
    pending_tool_uses: dict[str, tuple[int, str, str]] = {}  # id -> (timestamp_ms, tool_name, command)
    tool_use_durations: list[dict] = []  # completed tool uses with duration
    install_duration_ms = 0

    for ts_ms, line in timestamped_lines:
        line = line.strip()
        if not line:
            continue
        try:
            obj = json.loads(line)
            events.append((ts_ms, obj))
        except json.JSONDecodeError:
            continue

        event_type = obj.get("type", "")
        msg = obj.get("message", {}) if isinstance(obj.get("message"), dict) else {}
        content = msg.get("content", []) if isinstance(msg.get("content"), list) else []

        # Init event — capture all metadata about the session
        if event_type == "system" and obj.get("subtype") == "init":
            claude_code_version = obj.get("claude_code_version", "")
            model_used = obj.get("model", "")
            init_data = {
                "session_id": obj.get("session_id", ""),
                "model": model_used,
                "claude_code_version": claude_code_version,
                "permission_mode": obj.get("permissionMode", ""),
                "output_style": obj.get("output_style", ""),
                "fast_mode_state": obj.get("fast_mode_state", ""),
                "tools_available": obj.get("tools", []),
                "mcp_servers": obj.get("mcp_servers", []),
                "agents_available": obj.get("agents", []),
                "skills_available": obj.get("skills", []),
                "plugins": obj.get("plugins", []),
                "cwd": obj.get("cwd", ""),
            }

        # Assistant text
        if event_type == "assistant":
            for c in content:
                if isinstance(c, dict) and c.get("type") == "text":
                    text = c.get("text", "")
                    console_lines.append(f"[Assistant] {text}")

        # Tool use and results
        if event_type == "assistant":
            for c in content:
                if isinstance(c, dict) and c.get("type") == "tool_use":
                    tool_name = c.get("name", "")
                    tool_id = c.get("id", "")
                    tool_input = c.get("input", {})
                    is_install = False
                    cmd = ""
                    if tool_name == "Bash":
                        cmd = tool_input.get("command", "")
                        console_lines.append(f"[Tool: {tool_name}] {cmd}")
                        # Check for install commands
                        for pattern in INSTALL_PATTERNS:
                            if re.search(pattern, cmd, re.IGNORECASE):
                                install_commands.append(cmd)
                                tools_installed.append(cmd.strip())
                                is_install = True
                                break
                    else:
                        detail = json.dumps(tool_input)[:200] if tool_input else ""
                        console_lines.append(f"[Tool: {tool_name}] {detail}")
                    # Track this tool_use for duration measurement
                    if tool_id:
                        pending_tool_uses[tool_id] = (ts_ms, tool_name, cmd if tool_name == "Bash" else "", is_install)

        # Tool results
        if event_type == "user":
            for c in content:
                if isinstance(c, dict) and c.get("type") == "tool_result":
                    tool_use_id = c.get("tool_use_id", "")
                    result_content = c.get("content", "")
                    is_error = c.get("is_error", False)

                    # Compute duration if we have the matching tool_use
                    if tool_use_id and tool_use_id in pending_tool_uses:
                        start_ms, t_name, t_cmd, t_is_install = pending_tool_uses.pop(tool_use_id)
                        dur = ts_ms - start_ms
                        tool_use_durations.append({
                            "tool_name": t_name,
                            "command": t_cmd[:200],
                            "duration_ms": dur,
                            "is_error": is_error,
                            "is_install": t_is_install,
                        })
                        if t_is_install:
                            install_duration_ms += dur

                    if isinstance(result_content, str):
                        console_lines.append(f"[Result{' ERROR' if is_error else ''}] {result_content[:1000]}")
                        if is_error:
                            error_count += 1
                            error_details.append(result_content[:200])
                        # Look for version strings
                        for vline in result_content.splitlines():
                            if "PSVersion" in vline:
                                parts = vline.split()
                                if len(parts) >= 2:
                                    interpreter_versions["powershell"] = parts[-1]
                            if re.match(r"^\d+\.\d+\.\d+", vline.strip()) and "dotnet" not in interpreter_versions:
                                pass
                    elif isinstance(result_content, list):
                        for rc in result_content:
                            if isinstance(rc, dict):
                                text = rc.get("text", str(rc))[:500]
                                console_lines.append(f"[Result] {text}")

        # Compaction events
        if "compact" in event_type.lower() or "compact" in str(obj.get("subtype", "")).lower():
            compaction_count += 1

        # Result event — keep the first one (background task notifications
        # can emit a second init+result pair that would overwrite the real data)
        if event_type == "result" and not result_data:
            result_data = obj

    # Extract timing and usage from result
    duration_ms = result_data.get("duration_ms", 0)
    duration_api_ms = result_data.get("duration_api_ms", 0)
    num_turns = result_data.get("num_turns", 0)
    total_cost = result_data.get("total_cost_usd", 0.0)
    usage = result_data.get("usage", {})
    input_tokens = usage.get("input_tokens", 0)
    output_tokens = usage.get("output_tokens", 0)
    cache_read = usage.get("cache_read_input_tokens", usage.get("cache_read_tokens", 0))
    cache_creation = usage.get("cache_creation_input_tokens", usage.get("cache_creation_tokens", 0))

    # Estimate install duration from the stream: count bash tool uses that match install patterns
    # This is approximate — we track the commands but duration per command isn't in the stream
    # We'll use a heuristic: count install commands and note them
    # A more precise approach would require correlating tool_use IDs with their results

    # Extract detailed metadata from result event
    model_usage = result_data.get("modelUsage", {})
    result_meta = {
        "session_id": result_data.get("session_id", ""),
        "stop_reason": result_data.get("stop_reason", ""),
        "terminal_reason": result_data.get("terminal_reason", ""),
        "fast_mode_state": result_data.get("fast_mode_state", ""),
        "service_tier": usage.get("service_tier", ""),
        "speed": usage.get("speed", ""),
        "inference_geo": usage.get("inference_geo", ""),
        "model_usage": model_usage,
        "permission_denials": result_data.get("permission_denials", []),
        "context_window": None,
        "max_output_tokens": None,
    }
    # Extract context_window and max_output_tokens from modelUsage
    for model_key, model_info in model_usage.items():
        result_meta["context_window"] = model_info.get("contextWindow")
        result_meta["max_output_tokens"] = model_info.get("maxOutputTokens")
        break  # just take the first (should be only one)

    return {
        "events": [obj for _, obj in events],
        "timestamped_events": events,  # (ts_ms, obj) for analysis
        "console_log": "\n".join(console_lines),
        "claude_code_version": claude_code_version,
        "model_used": model_used,
        "init_data": init_data,
        "result_meta": result_meta,
        "duration_ms": duration_ms,
        "duration_api_ms": duration_api_ms,
        "num_turns": num_turns,
        "total_cost_usd": total_cost,
        "input_tokens": input_tokens,
        "output_tokens": output_tokens,
        "cache_read_tokens": cache_read,
        "cache_creation_tokens": cache_creation,
        "total_context_consumed": input_tokens + cache_read + cache_creation,
        "compaction_count": compaction_count,
        "error_count": error_count,
        "error_details": error_details,
        "install_commands": install_commands,
        "install_duration_ms": install_duration_ms,
        "tools_installed": tools_installed,
        "interpreter_versions": interpreter_versions,
        "tool_use_durations": tool_use_durations,
        "result_data": result_data,
    }

# ---------------------------------------------------------------------------
# Main Run Logic
# ---------------------------------------------------------------------------

def run_single_task(
    task: dict,
    mode: str,
    model_id: str,
    model_short: str,
    run_dir: Path,
    repo_root: Path,
    effort: str | None = None,
    timeout_minutes: int = 30,
) -> dict:
    """Run a single task/mode/model combination and return metrics."""
    task_id = task["id"]
    task_name = task["name"]
    prompt = PROMPT_TEMPLATES[mode].format(task_description=task["description"])

    # Append GHA workflow requirement for tasks 11-18
    if task_id in GHA_TASK_IDS:
        task_slug = task_id.split("-", 1)[1] if "-" in task_id else task_id
        prompt += "\n" + GHA_WORKFLOW_ADDENDUM.format(task_slug=task_slug)

    # The "variant" qualifies model_short with effort when effort is set. This
    # lets a single results dir hold runs of the same (task, mode, model) at
    # different effort levels without collision — e.g. `default-opus47-1m-xhigh`
    # vs `default-opus47-1m-medium`. When effort is None (the historical default)
    # we omit the suffix so v1-v4 results keep their existing layout.
    variant = f"{model_short}-{effort}" if effort else model_short

    # Create workspace
    workspace = repo_root / "workspaces" / run_dir.name / task_id / f"{mode}-{variant}"
    workspace.mkdir(parents=True, exist_ok=True)

    # Initialize workspace as a git repo (act requires one)
    if not (workspace / ".git").exists():
        subprocess.run(["git", "init", "-q"], cwd=str(workspace), capture_output=True, timeout=10)
        subprocess.run(["git", "config", "user.email", "benchmark@test"], cwd=str(workspace), capture_output=True, timeout=5)
        subprocess.run(["git", "config", "user.name", "benchmark"], cwd=str(workspace), capture_output=True, timeout=5)

    # Copy instructions file
    shutil.copy2(repo_root / INSTRUCTIONS_FILE, workspace / INSTRUCTIONS_FILE)

    # Inject .actrc so act uses a custom image with pwsh/Pester pre-installed
    # (if the image exists). This eliminates ~24s/job install overhead that
    # wouldn't exist on real GitHub runners where pwsh is pre-installed.
    ACT_CUSTOM_IMAGE = "act-ubuntu-pwsh:latest"
    try:
        probe = subprocess.run(
            ["docker", "image", "inspect", ACT_CUSTOM_IMAGE],
            capture_output=True, timeout=10)
        if probe.returncode == 0:
            (workspace / ".actrc").write_text(
                f"-P ubuntu-latest={ACT_CUSTOM_IMAGE}\n")
    except Exception:
        pass  # docker not available or image not built — use act default

    # Create results directory
    result_dir = run_dir / "tasks" / task_id / f"{mode}-{variant}"
    result_dir.mkdir(parents=True, exist_ok=True)

    # Capture workspace before
    workspace_before = capture_workspace_listing(workspace)
    (result_dir / "workspace-before.txt").write_text(workspace_before)

    log(f"  Starting: {task_id} | {mode} | {model_short}")
    log(f"  Workspace: {workspace}")

    # Build command
    cmd = [
        "claude",
        "-p", prompt,
        "--model", model_id,
        "--output-format", "stream-json",
        "--dangerously-skip-permissions",
        "--verbose",
        "--mcp-config", '{"mcpServers":{}}',
        "--strict-mcp-config",
    ]
    # `ultracode` is not a valid value for the `--effort` CLI flag (the flag
    # rejects it with a warning and falls back to the default). It is a
    # session-level effort setting (xhigh + standing dynamic-workflow
    # orchestration) enabled via the CLAUDE_CODE_EFFORT_LEVEL env var below.
    # The 5 standard levels (low/medium/high/xhigh/max) go through the flag.
    if effort and effort != "ultracode":
        cmd.extend(["--effort", effort])

    # Record timing
    timestamp_start = datetime.now(timezone.utc).isoformat()
    wall_start = time.time()

    # Ensure tools are on PATH for the agent subprocess. cell_env() also strips
    # the parent Claude Code session's variables (a no-op on a laptop shell,
    # load-bearing when the runner is launched from a cloud session) and enables
    # the root sandbox escape hatch that --dangerously-skip-permissions needs.
    env = cell_env(os.environ)
    local_bin = Path.home() / ".local" / "bin"
    if local_bin.exists():
        env["PATH"] = f"{local_bin}:{env.get('PATH', '')}"
    dotnet_root = Path.home() / ".dotnet"
    if dotnet_root.exists():
        env["DOTNET_ROOT"] = str(dotnet_root)
        env["PATH"] = f"{dotnet_root}:{env.get('PATH', '')}"

    # Enable / disable the native PowerShell tool per mode. Without this, the
    # agent always routes pwsh invocations through the Bash tool on Linux/WSL.
    # The `powershell-tool` mode opts in to the PowerShell tool; `powershell`
    # explicitly opts out so both variants have a clean baseline regardless
    # of the user's ambient settings.
    if mode == "powershell-tool":
        env["CLAUDE_CODE_USE_POWERSHELL_TOOL"] = "1"
    elif mode == "powershell":
        env["CLAUDE_CODE_USE_POWERSHELL_TOOL"] = "0"

    # The `ultracode` effort level is a session feature, not a `--effort` flag
    # value: it pins the session to xhigh effort plus standing dynamic-workflow
    # orchestration (requires a workflow-capable model). Enable it the same way
    # the interactive `/effort ultracode` command does — via the session effort
    # env var — and make sure the Workflow tool is available so the agent can
    # actually orchestrate.
    if effort == "ultracode":
        env["CLAUDE_CODE_EFFORT_LEVEL"] = "ultracode"
        env["CLAUDE_CODE_WORKFLOWS"] = "1"

    # Execute with real-time line timestamping
    timestamped_lines: list[tuple[int, str]] = []  # (epoch_ms, line)
    raw_stderr = ""
    exit_code = -1
    # A threading.Timer enforces the timeout independently of whether the
    # subprocess is producing output. The older inline deadline check only
    # ran between stdout lines — a truly silent subprocess (e.g. claude CLI
    # hung waiting on a stalled `act push`) bypassed it entirely, letting
    # runs burn hours of wall clock. The timer fires once, kills the
    # process group, and lets the read loop exit when stdout closes.
    timeout_fired = threading.Event()
    timer: threading.Timer | None = None
    try:
        proc = subprocess.Popen(
            cmd,
            cwd=str(workspace),
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            env=env,
        )

        def _on_timeout():
            if proc.poll() is None:
                try:
                    proc.kill()
                    timeout_fired.set()
                except Exception:
                    pass

        if timeout_minutes > 0:
            timer = threading.Timer(timeout_minutes * 60, _on_timeout)
            timer.daemon = True
            timer.start()

        # Read stdout line-by-line, stamping each with current time.
        # No inline deadline check — the Timer above enforces the bound.
        for line in proc.stdout:
            ts_ms = int(time.time() * 1000)
            timestamped_lines.append((ts_ms, line.rstrip("\n")))
        proc.wait(timeout=30)
        exit_code = proc.returncode
        if timeout_fired.is_set():
            raw_stderr = f"TIMEOUT: Process exceeded {timeout_minutes} minute limit"
            log(f"  TIMEOUT: {task_id} | {mode} | {model_short}")
        else:
            raw_stderr = proc.stderr.read() if proc.stderr else ""
    except Exception as e:
        raw_stderr = f"ERROR: {str(e)}"
        exit_code = -2
        log(f"  ERROR: {task_id} | {mode} | {model_short}: {e}")
        try:
            proc.kill()
        except Exception:
            pass
    finally:
        if timer is not None:
            timer.cancel()

    wall_end = time.time()
    timestamp_end = datetime.now(timezone.utc).isoformat()
    grand_total_duration_ms = int((wall_end - wall_start) * 1000)

    # Parse stream output (now with per-line timestamps)
    parsed = parse_stream_output(timestamped_lines)

    # Capture workspace after
    workspace_after = capture_workspace_listing(workspace)
    (result_dir / "workspace-after.txt").write_text(workspace_after)

    # Copy generated files
    gen_dir = result_dir / "generated-code"
    generated_files = copy_generated_files(workspace, gen_dir)

    # Post-run actionlint validation on any workflow files
    actionlint_results = []
    workflow_dir = workspace / ".github" / "workflows"
    if workflow_dir.exists():
        for wf in sorted(workflow_dir.glob("*.yml")) + sorted(workflow_dir.glob("*.yaml")):
            try:
                r = subprocess.run(
                    ["actionlint", str(wf)],
                    capture_output=True, text=True, timeout=15,
                )
                actionlint_results.append({
                    "file": str(wf.relative_to(workspace)),
                    "passed": r.returncode == 0,
                    "errors": (r.stdout.strip() or r.stderr.strip()) if r.returncode != 0 else "",
                })
            except FileNotFoundError:
                actionlint_results.append({
                    "file": str(wf.relative_to(workspace)),
                    "passed": None,
                    "errors": "actionlint not found",
                })
            except Exception as e:
                actionlint_results.append({
                    "file": str(wf.relative_to(workspace)),
                    "passed": None,
                    "errors": str(e),
                })

    actionlint_pass = all(r["passed"] for r in actionlint_results) if actionlint_results else None
    actionlint_error_count = sum(1 for r in actionlint_results if r["passed"] is False)

    # Check for agent-produced act-result.txt (proof the agent ran act in its tests)
    act_result_path = workspace / "act-result.txt"
    act_result_txt_exists = act_result_path.exists()
    act_result_txt_size = act_result_path.stat().st_size if act_result_txt_exists else 0

    # Code metrics. "code_lines" = authored code (impl + tests + workflow) via
    # compute_structural_metrics — NOT a whole-dir count (which would also tally
    # fixtures, README, helper scripts, and the captured act-result.txt log).
    from test_quality import compute_structural_metrics
    code_lines = compute_structural_metrics(gen_dir).get("code_lines", 0) if gen_dir.exists() else 0
    all_code = get_all_code_text(gen_dir) if gen_dir.exists() else ""
    total_tokens_est = estimate_tokens(all_code)
    language_breakdown = compute_language_breakdown(gen_dir) if gen_dir.exists() else {}

    # Determine language chosen (primary language by %)
    language_chosen = ""
    if language_breakdown:
        language_chosen = max(language_breakdown, key=language_breakdown.get)
    elif mode in ("powershell",):
        language_chosen = "powershell"
    elif mode == "bash":
        language_chosen = "bash"
    elif mode == "typescript-bun":
        language_chosen = "typescript"

    # Get runtime versions
    powershell_version = parsed["interpreter_versions"].get("powershell", "")
    dotnet_version = parsed["interpreter_versions"].get("dotnet", "")

    # Use parsed duration if available, fall back to wall clock
    duration_ms = parsed["duration_ms"] or grand_total_duration_ms
    api_duration_ms = parsed["duration_api_ms"] or 0
    exec_duration_ms = duration_ms - api_duration_ms if api_duration_ms else 0

    # Build metrics
    cost_rates = COST_PER_MTOK.get(model_id, {})
    metrics = {
        "task_id": task_id,
        "task_name": task_name,
        "task_category": task["category"],
        "language_mode": mode,
        "language_chosen": language_chosen,
        "language_breakdown": language_breakdown,
        "interpreter_versions": parsed["interpreter_versions"],
        "powershell_version": powershell_version,
        "dotnet_version": dotnet_version,
        "model": model_id,
        "model_short": model_short,
        "variant": variant,
        "claude_code_version": parsed["claude_code_version"],
        "instructions_version": INSTRUCTIONS_VERSION,
        "timestamp_start": timestamp_start,
        "timestamp_end": timestamp_end,
        "prompt_text": prompt,
        "exit_code": exit_code,
        "run_success": exit_code == 0 and parsed["num_turns"] > 0,
        "failure_reason": (
            "timeout" if exit_code == -9 else
            "killed" if exit_code < 0 else
            "cli_error" if exit_code != 0 else
            "no_result" if parsed["num_turns"] == 0 else
            None
        ),
        # Session & environment metadata — everything the CLI exposes
        "session": {
            "session_id": parsed.get("result_meta", {}).get("session_id", ""),
            "stop_reason": parsed.get("result_meta", {}).get("stop_reason", ""),
            "terminal_reason": parsed.get("result_meta", {}).get("terminal_reason", ""),
            "fast_mode_state": parsed.get("result_meta", {}).get("fast_mode_state", ""),
            "service_tier": parsed.get("result_meta", {}).get("service_tier", ""),
            "speed": parsed.get("result_meta", {}).get("speed", ""),
            "inference_geo": parsed.get("result_meta", {}).get("inference_geo", ""),
            "context_window": parsed.get("result_meta", {}).get("context_window"),
            "max_output_tokens": parsed.get("result_meta", {}).get("max_output_tokens"),
            "permission_mode": parsed.get("init_data", {}).get("permission_mode", ""),
            "output_style": parsed.get("init_data", {}).get("output_style", ""),
            "tools_available_count": len(parsed.get("init_data", {}).get("tools_available", [])),
            # Names, not just the count: the CLI tool surface differs between a
            # laptop and a Claude-Code-on-the-web sandbox (deferred tools behind
            # ToolSearch, cloud-only tools), which is the main comparability
            # caveat for cloud runs. Recording it makes that auditable per cell.
            "tools_available": parsed.get("init_data", {}).get("tools_available", []),
            "skills_available_count": len(parsed.get("init_data", {}).get("skills_available", [])),
            "mcp_servers": parsed.get("init_data", {}).get("mcp_servers", []),
            "permission_denials": parsed.get("result_meta", {}).get("permission_denials", []),
        },
        "model_usage_detail": parsed.get("result_meta", {}).get("model_usage", {}),
        "effort_level": effort,
        "timing": {
            "grand_total_duration_ms": grand_total_duration_ms,
            "total_api_duration_ms": api_duration_ms,
            "total_execution_duration_ms": exec_duration_ms,
            "num_turns": parsed["num_turns"],
        },
        "tokens": {
            "input_tokens": parsed["input_tokens"],
            "output_tokens": parsed["output_tokens"],
            "cache_read_tokens": parsed["cache_read_tokens"],
            "cache_creation_tokens": parsed["cache_creation_tokens"],
            "total_context_consumed": parsed["total_context_consumed"],
            "compaction_count": parsed["compaction_count"],
        },
        "cost": {
            "total_cost_usd": parsed["total_cost_usd"],
            "assumed_input_cost_per_mtok": cost_rates.get("input", 0),
            "assumed_output_cost_per_mtok": cost_rates.get("output", 0),
            "assumed_cache_read_cost_per_mtok": cost_rates.get("cache_read", 0),
            "assumed_cache_write_cost_per_mtok": cost_rates.get("cache_write", 0),
        },
        "code_metrics": {
            "code_lines": code_lines,
            "total_tokens_estimate": total_tokens_est,
            "file_count": len(generated_files),
            "files": generated_files,
        },
        "quality": {
            "tests_pass": None,  # Would need to actually run tests to determine
            "error_count": parsed["error_count"],
            "error_details": parsed["error_details"][:20],  # Cap at 20
            "actionlint_pass": actionlint_pass,
            "actionlint_errors": actionlint_error_count,
            "actionlint_results": actionlint_results,
            "act_result_txt_exists": act_result_txt_exists,
            "act_result_txt_size": act_result_txt_size,
            "areas_of_difficulty": [],
            "observations": "",
        },
        "tool_install": {
            "tool_install_duration_ms": parsed["install_duration_ms"],
            "tools_installed": parsed["tools_installed"][:20],
            "install_commands_count": len(parsed["install_commands"]),
        },
        "tool_use_timing": {
            "total_tool_uses": len(parsed["tool_use_durations"]),
            "total_tool_duration_ms": sum(d["duration_ms"] for d in parsed["tool_use_durations"]),
            "bash_tool_uses": len([d for d in parsed["tool_use_durations"] if d["tool_name"] == "Bash"]),
            "bash_total_ms": sum(d["duration_ms"] for d in parsed["tool_use_durations"] if d["tool_name"] == "Bash"),
            "slowest_tool_uses": sorted(parsed["tool_use_durations"], key=lambda d: -d["duration_ms"])[:10],
            "all_tool_uses": parsed["tool_use_durations"],  # full list for post-analysis
            **_categorize_tool_time(parsed["tool_use_durations"]),
        },
    }

    # Save outputs
    (result_dir / "cli-output.json").write_text(json.dumps(parsed["events"], indent=2, default=str))
    (result_dir / "console-log.txt").write_text(parsed["console_log"])
    (result_dir / "metrics.json").write_text(json.dumps(metrics, indent=2, default=str))

    if raw_stderr:
        (result_dir / "stderr.txt").write_text(raw_stderr)

    log(f"  Finished: {task_id} | {mode} | {model_short} | {grand_total_duration_ms/1000:.1f}s | ${parsed['total_cost_usd']:.4f}")
    return metrics

# ---------------------------------------------------------------------------
# CLI & Main
# ---------------------------------------------------------------------------


def select_tasks(task_arg: str) -> list[dict]:
    """Resolve the --tasks argument to a list of task dicts.

    Numbers are interpreted as task IDs (the "NN-..." prefix), not positions
    in TASKS. This keeps IDs stable across archival (e.g. task 14 archived;
    `--tasks 15` must still pick id "15-test-results-aggregator"). Unknown IDs
    are silently skipped.
    """
    if task_arg == "all":
        return list(TASKS)
    task_by_id = {int(t["id"].split("-", 1)[0]): t for t in TASKS}
    task_nums = [int(t.strip()) for t in task_arg.split(",") if t.strip()]
    return [task_by_id[n] for n in task_nums if n in task_by_id]


def _group_summary(group: list[dict]) -> dict:
    """Aggregate a mode/model group with the same semantics as results.md:
    geometric-mean duration over successful + timed-out cells (timeouts are
    right-censored, counted at recorded wall clock), arithmetic errors over
    successful cells only, cost as the plain recorded sum."""
    successful = [m for m in group if m.get("run_success", m.get("exit_code", 0) == 0 and m.get("timing", {}).get("num_turns", 0) > 0)]
    timeouts = [m for m in group if m not in successful and m.get("failure_reason") == "timeout"]
    dur_pool = successful + timeouts
    geo_duration_s = _geomean(m["timing"]["grand_total_duration_ms"] / 1000 for m in dur_pool)
    avg_errors = (sum(m["quality"]["error_count"] for m in successful) / len(successful)
                  if successful else 0.0)
    # total_cost_usd is the plain recorded sum, unchanged — timed-out cells
    # recorded 0 (SIGKILL'd before the CLI's final cost record). The runner
    # observes/records; it never estimates. Report-time recovery of a
    # timeout's spend from its partial event stream happens later, in
    # generate_results.py / combine_results.py (see recover_cost.py), never
    # here.
    total_cost_usd = sum(m["cost"]["total_cost_usd"] for m in group)
    return {
        "n": len(group),
        "n_success": len(successful),
        "n_timeout": len(timeouts),
        "geo_duration_s": geo_duration_s,
        "avg_errors": avg_errors,
        "total_cost_usd": total_cost_usd,
    }


def print_summary_table(all_metrics: list[dict]) -> None:
    """Print a summary table of all runs."""
    print("\n" + "=" * 130)
    print("BENCHMARK RESULTS SUMMARY")
    print("=" * 130)
    print(f"{'Task':<35} {'Mode':<18} {'Model':<8} {'Duration':>10} {'Turns':>6} {'Lines':>6} {'Errors':>7} {'Cost':>10} {'Lang':<12} {'Status':<8}")
    print("-" * 130)

    total_cost = 0
    total_duration = 0
    failed_count = 0

    for m in all_metrics:
        duration_s = m["timing"]["grand_total_duration_ms"] / 1000
        total_cost += m["cost"]["total_cost_usd"]
        total_duration += duration_s
        is_ok = m.get("run_success", m["exit_code"] == 0 and m["timing"]["num_turns"] > 0)
        status = "ok" if is_ok else m.get("failure_reason", "failed")
        if not is_ok:
            failed_count += 1

        print(
            f"{m['task_name'][:34]:<35} "
            f"{m['language_mode']:<18} "
            f"{m['model_short']:<8} "
            f"{duration_s:>9.1f}s "
            f"{m['timing']['num_turns']:>6} "
            f"{m['code_metrics'].get('code_lines', m['code_metrics'].get('total_lines', 0)):>6} "
            f"{m['quality']['error_count']:>7} "
            f"${m['cost']['total_cost_usd']:>9.4f} "
            f"{m['language_chosen'][:11]:<12}"
            f"{status:<8}"
        )

    print("-" * 130)
    print(f"{'TOTALS':<63} {total_duration:>9.1f}s {'':>6} {'':>6} {'':>7} ${total_cost:>9.4f}")
    if failed_count:
        print(f"  ({failed_count} run(s) failed/timed-out — excluded from averages)")
    print("=" * 130)


def probe_model_metadata(model_id: str) -> dict:
    """Probe the Claude CLI to capture full model/environment metadata before the benchmark run.

    Runs a minimal `claude -p "say ok"` call and extracts every available field
    from the init and result events.  This lets us log the exact resolved model,
    service tier, context window, CLI version, etc. once at the start.
    """
    try:
        result = subprocess.run(
            ["claude", "-p", "say ok", "--model", model_id,
             "--output-format", "stream-json", "--dangerously-skip-permissions"],
            capture_output=True, text=True, timeout=60, env=cell_env(os.environ),
        )
        init_event = {}
        result_event = {}
        for line in result.stdout.splitlines():
            line = line.strip()
            if not line:
                continue
            try:
                obj = json.loads(line)
            except json.JSONDecodeError:
                continue
            if obj.get("type") == "system" and obj.get("subtype") == "init":
                init_event = obj
            elif obj.get("type") == "result":
                result_event = obj
        model_usage = result_event.get("modelUsage", {})
        model_info = model_usage.get(model_id, {})
        return {
            "model_id_requested": model_id,
            "model_id_init": init_event.get("model", ""),
            "claude_code_version": init_event.get("claude_code_version", ""),
            "service_tier": result_event.get("usage", {}).get("service_tier", ""),
            "speed": result_event.get("usage", {}).get("speed", ""),
            "inference_geo": result_event.get("usage", {}).get("inference_geo", ""),
            "context_window": model_info.get("contextWindow"),
            "max_output_tokens": model_info.get("maxOutputTokens"),
            "fast_mode_state": result_event.get("fast_mode_state", ""),
            "permission_mode": init_event.get("permissionMode", ""),
            "tools_count": len(init_event.get("tools", [])),
            "mcp_servers": init_event.get("mcp_servers", []),
            "agents": init_event.get("agents", []),
            "plugins": init_event.get("plugins", []),
        }
    except Exception as e:
        log(f"  Warning: model probe for {model_id} failed: {e}")
        return {"model_id_requested": model_id, "error": str(e)}


def get_system_info() -> dict:
    """Capture system environment info for reproducibility."""
    info = {
        "platform": sys.platform,
        "execution_environment": detect_execution_environment(),
        "python_version": sys.version,
        "hostname": "",
        "uname": "",
    }
    try:
        import platform as plat
        info["hostname"] = plat.node()
        info["uname"] = str(plat.uname())
    except Exception:
        pass
    # Tool versions
    for tool, cmd in [
        ("claude", ["claude", "--version"]),
        ("python", ["python3", "--version"]),
        ("node", ["node", "--version"]),
        ("bun", ["bun", "--version"]),
        ("pwsh", ["pwsh", "--version"]),
        ("dotnet", ["dotnet", "--version"]),
        ("actionlint", ["actionlint", "--version"]),
        ("shellcheck", ["shellcheck", "--version"]),
        ("bash", ["bash", "--version"]),
        ("act", ["act", "--version"]),
        ("docker", ["docker", "--version"]),
    ]:
        try:
            r = subprocess.run(cmd, capture_output=True, text=True, timeout=10)
            info[f"{tool}_version"] = r.stdout.strip().split("\n")[0]
        except Exception:
            info[f"{tool}_version"] = "not found"
    # `docker --version` reports the client even when no daemon is listening —
    # the default state of a cloud sandbox, where act (and every v3+ task) then
    # fails. Record whether the daemon actually answered.
    try:
        r = subprocess.run(["docker", "info", "--format", "{{.ServerVersion}}"],
                           capture_output=True, text=True, timeout=20)
        info["docker_daemon"] = r.stdout.strip() if r.returncode == 0 else "not running"
    except Exception:
        info["docker_daemon"] = "not running"
    return info


def main():
    parser = argparse.ArgumentParser(description="Benchmark Claude Code agents on scripting tasks")
    parser.add_argument(
        "--tasks", default="all",
        help="Comma-separated task IDs (e.g. 11,12,13,15,16,17,18) or 'all' (default: all). "
             "Unknown IDs are silently skipped."
    )
    parser.add_argument(
        "--models", default="opus,sonnet",
        help="Comma-separated model short names: opus,sonnet (default: opus,sonnet)"
    )
    parser.add_argument(
        "--modes", default="default,powershell,bash,typescript-bun",
        help="Comma-separated language modes (default: default,powershell,bash,typescript-bun)"
    )
    parser.add_argument(
        "--resume", default=None,
        help="Resume a previous run by providing its timestamp directory name (e.g., 2026-04-02_181500). Skips runs that already have metrics.json."
    )
    parser.add_argument(
        "--effort", default=None, choices=["low", "medium", "high", "xhigh", "max", "ultracode"],
        help="Reasoning effort level (default: not set, uses CLI default). low/medium/high/xhigh/max are passed via the --effort CLI flag; ultracode (xhigh + dynamic-workflow orchestration) is enabled via CLAUDE_CODE_EFFORT_LEVEL since the flag does not accept it."
    )
    parser.add_argument(
        "--timeout", default=30, type=int,
        help="Per-run timeout in minutes (default: 30). Use 0 for unlimited."
    )
    args = parser.parse_args()

    selected_tasks = select_tasks(args.tasks)

    # Parse models
    selected_models = [(short, MODELS[short]) for short in args.models.split(",") if short in MODELS]

    # Parse modes
    selected_modes = [m.strip() for m in args.modes.split(",") if m.strip() in PROMPT_TEMPLATES]

    if not selected_tasks or not selected_models or not selected_modes:
        print("Error: No valid tasks, models, or modes selected.", file=sys.stderr)
        sys.exit(1)

    # Issue #32 prospective guard: when --effort is unset, the CLI applies
    # its version-dependent DEFAULT effort but does NOT record it in
    # metrics.json, so those cells can't be labeled with certainty by the
    # reporting layer (see combine_results.derive_effort / AGENTS.md).
    # Warn — don't hard-refuse — for any effort-capable model (i.e. anything
    # but Haiku 4.5, which takes no effort parameter). A warning, not a
    # refusal, so legitimate edge cases aren't broken.
    if args.effort is None:
        effort_capable = effort_capable_models(selected_models)
        if effort_capable:
            log("WARNING: --effort not set for an effort-capable model "
                f"({', '.join(effort_capable)}); the effective CLI-default "
                "effort is version-dependent and is NOT recorded, so cells "
                "cannot be labeled with certainty. Pass --effort explicitly "
                "(see AGENTS.md).")

    # Create or resume run directory
    repo_root = Path(__file__).parent.resolve()
    # Single-runner guard: never let two runners execute cells concurrently
    # (concurrent cells confound timing/cost). Released automatically on exit.
    acquire_single_runner_lock(repo_root)
    if args.resume:
        run_timestamp = args.resume
        run_dir = repo_root / "results" / run_timestamp
        if not run_dir.exists():
            print(f"Error: Resume directory {run_dir} does not exist.", file=sys.stderr)
            sys.exit(1)
        log(f"Resuming run from {run_dir}")
    else:
        run_timestamp = datetime.now().strftime("%Y-%m-%d_%H%M%S")
        run_dir = repo_root / "results" / run_timestamp
    run_dir.mkdir(parents=True, exist_ok=True)

    total_runs = len(selected_tasks) * len(selected_models) * len(selected_modes)

    log(f"Benchmark starting: {len(selected_tasks)} tasks x {len(selected_models)} models x {len(selected_modes)} modes = {total_runs} runs")
    log(f"Tasks: {[t['id'] for t in selected_tasks]}")
    log(f"Models: {[m[0] for m in selected_models]}")
    log(f"Modes: {selected_modes}")
    log(f"Results: {run_dir}")
    log("")

    # Pre-flight: capture system info and probe each model
    log("Pre-flight: capturing system info...")
    system_info = get_system_info()
    log(f"  Claude CLI: {system_info.get('claude_version', 'unknown')}")
    log(f"  Python: {system_info.get('python_version', 'unknown')}")

    model_probes = {}
    for model_short, model_id in selected_models:
        log(f"Pre-flight: probing model {model_short} ({model_id})...")
        probe = probe_model_metadata(model_id)
        model_probes[model_short] = probe
        log(f"  Service tier: {probe.get('service_tier', '?')}, "
            f"Speed: {probe.get('speed', '?')}, "
            f"Context window: {probe.get('context_window', '?')}, "
            f"Max output: {probe.get('max_output_tokens', '?')}")

    # Run manifest
    manifest = {
        "run_id": run_timestamp,
        "instructions_version": INSTRUCTIONS_VERSION,
        "models_tested": [m[1] for m in selected_models],
        "modes_tested": selected_modes,
        "tasks_tested": [t["id"] for t in selected_tasks],
        "total_runs": total_runs,
        "started_at": datetime.now(timezone.utc).isoformat(),
        "completed_at": None,
        "cost_assumptions": COST_PER_MTOK,
        "total_cost_usd": 0,
        "system_info": system_info,
        "model_probes": model_probes,
        "effort_level": args.effort,
    }

    all_metrics = []
    run_count = 0

    # When resuming, load ALL existing metrics (not just ones matching current filters)
    # so that results.md reflects the full picture
    total_runs_for_report = total_runs
    if args.resume:
        for mf in sorted((run_dir / "tasks").rglob("metrics.json")):
            try:
                all_metrics.append(json.loads(mf.read_text()))
            except Exception:
                pass
        if all_metrics:
            log(f"Loaded {len(all_metrics)} previously completed run(s) from {run_dir}")
        # Cumulative total = already-completed metrics + runs this invocation
        # will actually execute (i.e. combos whose variant subdir doesn't yet
        # have a metrics.json). Prior logic read total_runs from the old
        # manifest, which undercounts when this invocation adds a new effort
        # variant that won't be skipped, producing "36/35 completed".
        runs_to_do = 0
        for task in selected_tasks:
            for model_short, _ in selected_models:
                for mode in selected_modes:
                    variant = f"{model_short}-{args.effort}" if args.effort else model_short
                    existing = run_dir / "tasks" / task["id"] / f"{mode}-{variant}" / "metrics.json"
                    if not _metrics_valid(existing):
                        runs_to_do += 1
        total_runs_for_report = len(all_metrics) + runs_to_do

    # Detect git branch for periodic pushing
    try:
        branch_result = subprocess.run(
            ["git", "rev-parse", "--abbrev-ref", "HEAD"],
            cwd=str(repo_root), capture_output=True, text=True, timeout=5,
        )
        git_branch = branch_result.stdout.strip() or "main"
    except Exception:
        git_branch = "main"

    # Start periodic pusher — seed with already-loaded metrics
    pusher = PeriodicPusher(repo_root, git_branch, total_runs_for_report, run_dir)
    pusher.update(len(all_metrics), all_metrics)
    pusher.start()
    log(f"Git commit+push on each newly-completed cell (checked every {PUSH_CHECK_INTERVAL}s) to branch {git_branch}")

    for task in selected_tasks:
        for model_short, model_id in selected_models:
            for mode in selected_modes:
                run_count += 1
                # Check if already completed (for --resume) — same variant logic
                # as run_single_task's result_dir construction.
                variant = f"{model_short}-{args.effort}" if args.effort else model_short
                existing_metrics = run_dir / "tasks" / task["id"] / f"{mode}-{variant}" / "metrics.json"
                if _metrics_valid(existing_metrics):
                    log(f"Run {run_count}/{total_runs} — SKIPPED (already completed): {task['id']} | {mode} | {model_short}")
                    pusher.update(run_count, all_metrics)
                    continue
                log(f"Run {run_count}/{total_runs}")
                try:
                    metrics = run_single_task(
                        task=task,
                        mode=mode,
                        model_id=model_id,
                        model_short=model_short,
                        run_dir=run_dir,
                        repo_root=repo_root,
                        effort=args.effort,
                        timeout_minutes=args.timeout,
                    )
                    all_metrics.append(metrics)
                except Exception as e:
                    log(f"  FATAL ERROR in {task['id']} | {mode} | {model_short}: {e}")
                    import traceback
                    traceback.print_exc(file=sys.stderr)
                pusher.update(run_count, all_metrics)
                log("")

    # Finalize manifest
    manifest["completed_at"] = datetime.now(timezone.utc).isoformat()
    manifest["total_cost_usd"] = sum(m["cost"]["total_cost_usd"] for m in all_metrics)
    (run_dir / "run-manifest.json").write_text(json.dumps(manifest, indent=2, default=str))

    # Summary
    summary = {
        "run_id": run_timestamp,
        "total_runs": len(all_metrics),
        "total_cost_usd": manifest["total_cost_usd"],
        "total_duration_s": sum(m["timing"]["grand_total_duration_ms"] for m in all_metrics) / 1000,
        "by_mode": {},
        "by_model": {},
        "tasks": [{
            "task_id": m["task_id"],
            "mode": m["language_mode"],
            "model": m["model_short"],
            "duration_s": m["timing"]["grand_total_duration_ms"] / 1000,
            "cost_usd": m["cost"]["total_cost_usd"],
            # tolerate both new (code_lines) and resumed old (total_lines) cells
            "lines": m["code_metrics"].get("code_lines", m["code_metrics"].get("total_lines", 0)),
            "errors": m["quality"]["error_count"],
            "language": m["language_chosen"],
            "turns": m["timing"]["num_turns"],
        } for m in all_metrics],
    }

    # Aggregate by mode. `avg_duration_s` is RENAMED to `geo_duration_s` here
    # (grep shows no consumers outside runner.py; archived summary.json
    # files keep the old key, which is fine) to match results.md semantics
    # — see `_group_summary`.
    for mode in selected_modes:
        mode_metrics = [m for m in all_metrics if m["language_mode"] == mode]
        if mode_metrics:
            summary["by_mode"][mode] = _group_summary(mode_metrics)

    # Aggregate by model
    for model_short, _ in selected_models:
        model_metrics = [m for m in all_metrics if m["model_short"] == model_short]
        if model_metrics:
            summary["by_model"][model_short] = _group_summary(model_metrics)

    (run_dir / "summary.json").write_text(json.dumps(summary, indent=2, default=str))

    # Print summary
    print_summary_table(all_metrics)

    # Final results.md and push — squashes any remaining incremental commits
    pusher.stop()
    generate_results_md(run_dir, all_metrics, total_runs_for_report, run_count)
    git_push_results(repo_root, git_branch, run_count, total_runs_for_report, final=True)
    log(f"Final results pushed to {git_branch}")

    log(f"\nResults saved to: {run_dir}")
    log(f"Total cost: ${manifest['total_cost_usd']:.4f}")


if __name__ == "__main__":
    main()
