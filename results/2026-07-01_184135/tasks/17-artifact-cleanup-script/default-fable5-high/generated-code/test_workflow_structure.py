"""Structure tests for .github/workflows/artifact-cleanup-script.yml.

These run on the host (not inside the act container, which has no PyYAML):
they parse the workflow YAML, check triggers/jobs/steps, verify every file
the workflow references actually exists, and assert actionlint passes.
The act harness (run_act_tests.py) runs this module before spending any
act invocations.
"""

import os
import re
import subprocess
import unittest

import yaml

WORKFLOW_PATH = os.path.join(".github", "workflows", "artifact-cleanup-script.yml")


class WorkflowStructureTest(unittest.TestCase):

    @classmethod
    def setUpClass(cls):
        with open(WORKFLOW_PATH, "r", encoding="utf-8") as fh:
            cls.doc = yaml.safe_load(fh)
        # PyYAML parses the bare key `on:` as boolean True.
        cls.triggers = cls.doc.get("on", cls.doc.get(True))
        cls.jobs = cls.doc["jobs"]

    def all_run_lines(self):
        for job in self.jobs.values():
            for step in job["steps"]:
                if "run" in step:
                    yield step["run"]

    def test_workflow_file_exists_and_parses(self):
        self.assertIsInstance(self.doc, dict)
        self.assertEqual(self.doc["name"], "Artifact Cleanup")

    def test_triggers(self):
        self.assertIn("push", self.triggers)
        self.assertIn("workflow_dispatch", self.triggers)
        self.assertIn("schedule", self.triggers)
        crons = [entry["cron"] for entry in self.triggers["schedule"]]
        self.assertEqual(crons, ["30 3 * * *"])

    def test_permissions_are_least_privilege(self):
        self.assertEqual(self.doc["permissions"], {"contents": "read"})

    def test_jobs_and_dependencies(self):
        self.assertEqual(set(self.jobs), {"unit-tests", "cleanup-plan"})
        self.assertEqual(self.jobs["cleanup-plan"]["needs"], "unit-tests")
        for job in self.jobs.values():
            self.assertEqual(job["runs-on"], "ubuntu-latest")

    def test_every_job_checks_out_the_repo_first(self):
        for name, job in self.jobs.items():
            first = job["steps"][0]
            self.assertEqual(first.get("uses"), "actions/checkout@v4",
                             f"job {name!r} must start with checkout")

    def test_unit_test_job_runs_the_suite(self):
        runs = [s.get("run", "") for s in self.jobs["unit-tests"]["steps"]]
        self.assertTrue(
            any("unittest discover -s tests" in r for r in runs),
            "unit-tests job must run the unittest suite")

    def test_cleanup_job_runs_dry_run_then_apply(self):
        runs = [s.get("run", "") for s in self.jobs["cleanup-plan"]["steps"]
                if "run" in s and "artifact_cleanup.py" in s["run"]]
        self.assertEqual(len(runs), 2, "expected a dry-run step and an apply step")
        self.assertNotIn("--apply", runs[0])
        self.assertIn("--apply", runs[1])

    def test_referenced_files_exist(self):
        # Every path mentioned in run steps or job env must exist in the repo.
        expected = {
            "artifact_cleanup.py",
            "tests",
            "fixtures/artifacts.json",
            "fixtures/policy.json",
            "fixtures/now.txt",
        }
        for path in expected:
            self.assertTrue(os.path.exists(path), f"{path} referenced but missing")
        # And the script name mentioned in the workflow matches the real file.
        with open(WORKFLOW_PATH, encoding="utf-8") as fh:
            text = fh.read()
        for script in set(re.findall(r"[\w./-]+\.py", text)):
            self.assertTrue(os.path.exists(script),
                            f"workflow references {script} which does not exist")
        for env_path in self.jobs["cleanup-plan"]["env"].values():
            if "/" in env_path:
                self.assertTrue(os.path.exists(env_path),
                                f"workflow env references missing {env_path}")

    def test_actionlint_passes(self):
        result = subprocess.run(
            ["actionlint", WORKFLOW_PATH],
            capture_output=True, text=True)
        self.assertEqual(
            result.returncode, 0,
            f"actionlint failed:\n{result.stdout}\n{result.stderr}")


if __name__ == "__main__":
    unittest.main()
