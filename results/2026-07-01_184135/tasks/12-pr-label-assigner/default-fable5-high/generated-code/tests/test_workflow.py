"""Workflow structure tests (run on the host, not inside the act container).

Verifies the GitHub Actions workflow file:
  * parses as YAML with the expected triggers, jobs, and steps
  * references script/fixture paths that actually exist in the repo
  * passes actionlint (exit code 0)
"""
import os
import re
import subprocess
import unittest

import yaml

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WORKFLOW = os.path.join(ROOT, ".github", "workflows", "pr-label-assigner.yml")


class TestWorkflowStructure(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        with open(WORKFLOW, encoding="utf-8") as fh:
            cls.doc = yaml.safe_load(fh)

    def test_triggers(self):
        # PyYAML parses the bare key 'on' as boolean True
        triggers = self.doc.get("on", self.doc.get(True))
        self.assertIsNotNone(triggers, "workflow must declare triggers")
        for event in ("push", "pull_request", "workflow_dispatch"):
            self.assertIn(event, triggers)

    def test_permissions_are_declared(self):
        self.assertEqual(self.doc["permissions"]["contents"], "read")
        self.assertEqual(self.doc["permissions"]["pull-requests"], "write")

    def test_jobs_and_dependency_ordering(self):
        jobs = self.doc["jobs"]
        self.assertIn("test", jobs)
        self.assertIn("label", jobs)
        # labeling must only run after the unit suite passes
        self.assertEqual(jobs["label"]["needs"], "test")

    def test_jobs_check_out_the_repo_first(self):
        for job in self.doc["jobs"].values():
            first = job["steps"][0]
            self.assertEqual(first["uses"], "actions/checkout@v4")

    def test_referenced_paths_exist(self):
        # every repo path mentioned in run commands / env must exist
        for rel in ("labeler.py", "tests/test_labeler.py",
                    "fixtures/rules.json", "fixtures/changed_files.txt"):
            self.assertTrue(
                os.path.exists(os.path.join(ROOT, rel)),
                f"workflow references missing path: {rel}",
            )

    def test_workflow_invokes_the_script_and_tests(self):
        runs = [
            step.get("run", "")
            for job in self.doc["jobs"].values()
            for step in job["steps"]
        ]
        joined = "\n".join(runs)
        self.assertIn("labeler.py", joined)
        self.assertTrue(re.search(r"unittest\s+tests\.test_labeler", joined))

    def test_actionlint_passes(self):
        result = subprocess.run(
            ["actionlint", WORKFLOW], capture_output=True, text=True
        )
        self.assertEqual(
            result.returncode, 0,
            f"actionlint failed:\n{result.stdout}{result.stderr}",
        )


if __name__ == "__main__":
    unittest.main()
