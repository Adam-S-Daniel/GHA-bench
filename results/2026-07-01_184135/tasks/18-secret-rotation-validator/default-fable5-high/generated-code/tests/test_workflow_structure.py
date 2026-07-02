"""Structure tests for the GitHub Actions workflow.

These run on the host (not inside act) because they need actionlint and
the repository layout itself. They verify:
  - the YAML parses and declares the expected triggers, jobs and steps;
  - every file the workflow references actually exists in the repo;
  - actionlint passes with exit code 0.
"""

import pathlib
import re
import subprocess
import unittest

import yaml

REPO = pathlib.Path(__file__).resolve().parent.parent
WORKFLOW = REPO / ".github" / "workflows" / "secret-rotation-validator.yml"


class TestWorkflowStructure(unittest.TestCase):

    @classmethod
    def setUpClass(cls):
        with open(WORKFLOW, encoding="utf-8") as handle:
            cls.wf = yaml.safe_load(handle)
        # YAML 1.1 parses the bare key `on` as boolean True.
        cls.triggers = cls.wf.get("on", cls.wf.get(True))

    def test_workflow_file_exists(self):
        self.assertTrue(WORKFLOW.is_file())

    def test_has_expected_triggers(self):
        for event in ("push", "pull_request", "schedule", "workflow_dispatch"):
            self.assertIn(event, self.triggers)
        self.assertEqual(self.triggers["schedule"], [{"cron": "0 6 * * 1-5"}])
        self.assertIn("warn_days", self.triggers["workflow_dispatch"]["inputs"])

    def test_permissions_are_read_only(self):
        self.assertEqual(self.wf["permissions"], {"contents": "read"})

    def test_jobs_and_dependencies(self):
        jobs = self.wf["jobs"]
        self.assertEqual(set(jobs), {"test", "validate"})
        self.assertEqual(jobs["validate"]["needs"], "test")
        for job in jobs.values():
            self.assertEqual(job["runs-on"], "ubuntu-latest")

    def test_every_job_checks_out_with_checkout_v4(self):
        for name, job in self.wf["jobs"].items():
            uses = [s.get("uses") for s in job["steps"] if "uses" in s]
            self.assertIn("actions/checkout@v4", uses,
                          f"job {name!r} must use actions/checkout@v4")

    def test_test_job_runs_the_unit_suite(self):
        runs = "\n".join(
            s.get("run", "") for s in self.wf["jobs"]["test"]["steps"]
        )
        self.assertIn(
            "python3 -m unittest tests.test_secret_rotation_validator", runs
        )

    def test_referenced_paths_exist(self):
        """Every repo path mentioned in run commands must exist."""
        all_runs = "\n".join(
            step.get("run", "")
            for job in self.wf["jobs"].values()
            for step in job["steps"]
        )
        referenced = set(
            re.findall(r"\b(?:[\w.-]+/)*[\w.-]+\.(?:py|json|env)\b", all_runs)
        )
        # Sanity: the paths we care about are actually detected.
        for expected in ("secret_rotation_validator.py", "fixtures/secrets.json",
                         "fixtures/invalid.json", "fixtures/case.env"):
            self.assertIn(expected, referenced)
        for path in referenced:
            # Module path used by unittest, not a file reference.
            if path.startswith("tests.test_"):
                continue
            self.assertTrue((REPO / path).exists(),
                            f"workflow references missing file: {path}")

    def test_unittest_module_target_exists(self):
        self.assertTrue((REPO / "tests" / "test_secret_rotation_validator.py").is_file())

    def test_actionlint_passes(self):
        result = subprocess.run(
            ["actionlint", str(WORKFLOW)],
            capture_output=True, text=True, cwd=REPO,
        )
        self.assertEqual(
            result.returncode, 0,
            f"actionlint failed:\n{result.stdout}\n{result.stderr}",
        )


if __name__ == "__main__":
    unittest.main()
