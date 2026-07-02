"""Structure tests for the GitHub Actions workflow.

Written (RED) before the workflow file existed, per TDD. They verify:
  * the YAML parses and has the expected triggers / permissions / jobs / steps,
  * every file the workflow references actually exists in the repo,
  * actionlint passes with exit code 0.

PyYAML and actionlint are available on the dev machine / CI runner used for
harness runs; inside the minimal act container they may be absent, so those
specific tests skip gracefully there instead of failing.
"""

import shutil
import subprocess
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
WORKFLOW = ROOT / ".github" / "workflows" / "test-results-aggregator.yml"

try:
    import yaml
    HAVE_YAML = True
except ImportError:  # pragma: no cover - depends on environment
    HAVE_YAML = False


class TestWorkflowFileExists(unittest.TestCase):
    def test_workflow_file_exists(self):
        self.assertTrue(WORKFLOW.is_file(), f"missing workflow file: {WORKFLOW}")


@unittest.skipUnless(HAVE_YAML, "PyYAML not installed in this environment")
class TestWorkflowStructure(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.doc = yaml.safe_load(WORKFLOW.read_text(encoding="utf-8"))

    def test_triggers(self):
        # PyYAML parses the bare key `on` as boolean True.
        triggers = self.doc.get("on", self.doc.get(True))
        self.assertIsNotNone(triggers, "workflow has no 'on' triggers")
        self.assertIn("push", triggers)
        self.assertIn("pull_request", triggers)
        self.assertIn("workflow_dispatch", triggers)

    def test_permissions_are_least_privilege(self):
        self.assertEqual(self.doc.get("permissions"), {"contents": "read"})

    def test_jobs_and_dependencies(self):
        jobs = self.doc["jobs"]
        self.assertIn("unit-tests", jobs)
        self.assertIn("aggregate", jobs)
        # aggregate must wait for the unit tests to pass.
        self.assertEqual(jobs["aggregate"]["needs"], "unit-tests")

    def test_steps_use_checkout_and_reference_real_files(self):
        jobs = self.doc["jobs"]
        for job_name, job in jobs.items():
            uses = [s.get("uses", "") for s in job["steps"]]
            self.assertTrue(
                any(u.startswith("actions/checkout@v4") for u in uses),
                f"job {job_name} must check out the repo with actions/checkout@v4",
            )

        run_text = " ".join(
            s.get("run", "") for job in jobs.values() for s in job["steps"]
        )
        # The workflow must invoke the aggregator script and the unit tests,
        # and every referenced path must exist in the repo.
        self.assertIn("aggregator.py", run_text)
        self.assertIn("unittest", run_text)
        for referenced in ("aggregator.py", "tests", "fixtures/case1-matrix-flaky"):
            self.assertTrue((ROOT / referenced).exists(),
                            f"workflow references missing path: {referenced}")


@unittest.skipUnless(shutil.which("actionlint"), "actionlint not on PATH")
class TestActionlint(unittest.TestCase):
    def test_actionlint_passes(self):
        proc = subprocess.run(
            ["actionlint", str(WORKFLOW)],
            capture_output=True, text=True, cwd=ROOT,
        )
        self.assertEqual(proc.returncode, 0,
                         f"actionlint failed:\n{proc.stdout}\n{proc.stderr}")


if __name__ == "__main__":
    unittest.main()
