"""Structure tests for the GitHub Actions workflow.

Parses the workflow YAML and asserts on triggers, jobs, step wiring, and
that every file the workflow references actually exists. Also asserts
actionlint passes (exit code 0). Run on the host: these tests need the
repo layout and the actionlint binary, so they are not part of the
in-container unit suite.
"""
import shutil
import subprocess
import unittest
from pathlib import Path

import yaml

REPO = Path(__file__).parent
WORKFLOW = REPO / ".github" / "workflows" / "secret-rotation-validator.yml"


class TestWorkflowStructure(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        with open(WORKFLOW, encoding="utf-8") as f:
            cls.wf = yaml.safe_load(f)

    def test_workflow_file_exists_and_parses(self):
        self.assertTrue(WORKFLOW.exists())
        self.assertIsInstance(self.wf, dict)
        self.assertEqual(self.wf["name"], "Secret Rotation Validator")

    def test_triggers(self):
        # PyYAML parses the bare `on:` key as boolean True.
        triggers = self.wf.get("on", self.wf.get(True))
        for event in ("push", "pull_request", "workflow_dispatch", "schedule"):
            self.assertIn(event, triggers)
        self.assertEqual(triggers["schedule"][0]["cron"], "0 6 * * 1")

    def test_permissions_are_least_privilege(self):
        self.assertEqual(self.wf["permissions"], {"contents": "read"})

    def test_jobs_and_dependencies(self):
        jobs = self.wf["jobs"]
        self.assertEqual(set(jobs), {"test", "report"})
        self.assertEqual(jobs["report"]["needs"], "test")
        for job in jobs.values():
            self.assertEqual(job["runs-on"], "ubuntu-latest")
            self.assertEqual(job["steps"][0]["uses"], "actions/checkout@v4")

    def test_referenced_files_exist(self):
        # Every file the workflow run: steps mention must exist in the repo.
        run_text = "\n".join(
            step.get("run", "")
            for job in self.wf["jobs"].values()
            for step in job["steps"]
        )
        self.assertIn("secret_rotation_validator.py", run_text)
        self.assertIn("test_secret_rotation_validator", run_text)
        self.assertTrue((REPO / "secret_rotation_validator.py").exists())
        self.assertTrue((REPO / "test_secret_rotation_validator.py").exists())
        config_file = self.wf["env"]["CONFIG_FILE"]
        self.assertTrue((REPO / config_file).exists())

    def test_test_job_runs_unit_suite(self):
        runs = [s.get("run", "") for s in self.wf["jobs"]["test"]["steps"]]
        self.assertTrue(
            any("unittest" in r and "test_secret_rotation_validator" in r
                for r in runs)
        )

    def test_actionlint_passes(self):
        self.assertIsNotNone(shutil.which("actionlint"), "actionlint not on PATH")
        proc = subprocess.run(
            ["actionlint", str(WORKFLOW)], capture_output=True, text=True
        )
        self.assertEqual(proc.returncode, 0, proc.stdout + proc.stderr)


if __name__ == "__main__":
    unittest.main()
