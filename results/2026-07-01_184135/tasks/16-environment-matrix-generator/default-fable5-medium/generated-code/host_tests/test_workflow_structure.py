"""Workflow structure tests (run on the host, not inside act).

Written TDD-first alongside the workflow file: parse the YAML, assert
the expected triggers/jobs/steps exist, assert every file the workflow
references is present in the repo, and assert actionlint passes.
"""
import shutil
import subprocess
import unittest
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parent.parent
WORKFLOW = ROOT / ".github" / "workflows" / "environment-matrix-generator.yml"


class TestWorkflowStructure(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.doc = yaml.safe_load(WORKFLOW.read_text(encoding="utf-8"))

    def test_triggers(self):
        # PyYAML parses the bare `on:` key as boolean True.
        triggers = self.doc.get("on", self.doc.get(True))
        for event in ("push", "pull_request", "workflow_dispatch"):
            self.assertIn(event, triggers)

    def test_jobs_and_dependencies(self):
        jobs = self.doc["jobs"]
        self.assertEqual(
            set(jobs), {"unit-tests", "generate-matrix", "build", "summary"}
        )
        self.assertEqual(jobs["generate-matrix"]["needs"], "unit-tests")
        self.assertEqual(jobs["build"]["needs"], "generate-matrix")
        self.assertEqual(jobs["summary"]["needs"], ["generate-matrix", "build"])

    def test_permissions_are_least_privilege(self):
        self.assertEqual(self.doc["permissions"], {"contents": "read"})

    def test_build_consumes_generated_matrix(self):
        strategy = self.doc["jobs"]["build"]["strategy"]
        self.assertIn("needs.generate-matrix.outputs.matrix", strategy["matrix"])
        self.assertIn("needs.generate-matrix.outputs.fail_fast", str(strategy["fail-fast"]))

    def test_referenced_files_exist(self):
        text = WORKFLOW.read_text(encoding="utf-8")
        referenced = ["matrix_generator.py", "fixtures/oversized.json", "tests"]
        for path in referenced:
            self.assertIn(path, text, f"workflow should reference {path}")
            self.assertTrue((ROOT / path).exists(), f"{path} missing from repo")
        # The default config env var must point at an existing fixture.
        self.assertTrue((ROOT / "fixtures" / "config.json").exists())

    def test_uses_checkout_v4(self):
        steps = self.doc["jobs"]["unit-tests"]["steps"]
        self.assertEqual(steps[0]["uses"], "actions/checkout@v4")

    def test_actionlint_passes(self):
        self.assertIsNotNone(shutil.which("actionlint"), "actionlint not installed")
        proc = subprocess.run(
            ["actionlint", str(WORKFLOW)], capture_output=True, text=True
        )
        self.assertEqual(proc.returncode, 0, proc.stdout + proc.stderr)


if __name__ == "__main__":
    unittest.main()
