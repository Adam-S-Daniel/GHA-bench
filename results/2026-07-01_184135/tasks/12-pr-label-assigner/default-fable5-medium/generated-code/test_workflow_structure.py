"""Structure tests for the GitHub Actions workflow.

Verifies (without running act):
  - the YAML parses and has the expected triggers, jobs and steps
  - every file the workflow references actually exists in the repo
  - actionlint passes with exit code 0
"""

import os
import subprocess
import unittest

import yaml

HERE = os.path.dirname(os.path.abspath(__file__))
WORKFLOW = os.path.join(HERE, ".github", "workflows", "pr-label-assigner.yml")


class TestWorkflowStructure(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        with open(WORKFLOW, encoding="utf-8") as f:
            cls.wf = yaml.safe_load(f)

    def test_triggers(self):
        # PyYAML parses the bare key `on:` as boolean True.
        triggers = self.wf.get("on", self.wf.get(True))
        self.assertIsNotNone(triggers, "workflow has no trigger section")
        for event in ("push", "pull_request", "workflow_dispatch"):
            self.assertIn(event, triggers)

    def test_permissions_are_read_only(self):
        self.assertEqual(self.wf["permissions"], {"contents": "read"})

    def test_label_job_exists_with_checkout_first(self):
        job = self.wf["jobs"]["label"]
        self.assertEqual(job["runs-on"], "ubuntu-latest")
        self.assertEqual(job["steps"][0]["uses"], "actions/checkout@v4")

    def test_steps_run_unit_tests_and_labeler(self):
        runs = "\n".join(
            s.get("run", "") for s in self.wf["jobs"]["label"]["steps"]
        )
        self.assertIn("unittest test_labeler", runs)
        self.assertIn("labeler.py", runs)

    def test_referenced_files_exist(self):
        # env vars name the data files the labeler step consumes.
        env = self.wf["env"]
        for key in ("RULES_FILE", "CHANGED_FILES"):
            path = os.path.join(HERE, env[key])
            self.assertTrue(os.path.isfile(path), f"{env[key]} missing")
        for script in ("labeler.py", "test_labeler.py"):
            self.assertTrue(os.path.isfile(os.path.join(HERE, script)))

    def test_actionlint_passes(self):
        result = subprocess.run(
            ["actionlint", WORKFLOW], capture_output=True, text=True
        )
        self.assertEqual(
            result.returncode, 0, f"actionlint failed:\n{result.stdout}{result.stderr}"
        )


if __name__ == "__main__":
    unittest.main()
