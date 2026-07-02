"""Workflow structure tests (TDD cycle 7).

Written before the workflow file existed (red), then the workflow was
authored to make them pass (green). They parse the YAML and assert on the
expected triggers, jobs, step wiring, and that every file the workflow
references actually exists. The actionlint check runs wherever the binary is
available (the dev host); inside the act container it is skipped.
"""
import os
import shutil
import subprocess
import unittest

import yaml

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WORKFLOW_PATH = os.path.join(
    REPO_ROOT, ".github", "workflows", "environment-matrix-generator.yml"
)


def load_workflow():
    with open(WORKFLOW_PATH, encoding="utf-8") as handle:
        return yaml.safe_load(handle)


class TestWorkflowStructure(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.doc = load_workflow()
        # PyYAML parses the bare `on:` key as boolean True.
        cls.triggers = cls.doc.get("on", cls.doc.get(True))
        cls.jobs = cls.doc["jobs"]

    def test_expected_triggers(self):
        self.assertIn("push", self.triggers)
        self.assertIn("workflow_dispatch", self.triggers)

    def test_permissions_are_read_only(self):
        self.assertEqual(self.doc["permissions"], {"contents": "read"})

    def test_expected_jobs_and_dependencies(self):
        self.assertEqual(
            set(self.jobs),
            {"unit-tests", "generate-matrix", "consume-case1", "consume-case2"},
        )
        self.assertEqual(self.jobs["generate-matrix"]["needs"], "unit-tests")
        self.assertEqual(self.jobs["consume-case1"]["needs"], "generate-matrix")
        self.assertEqual(self.jobs["consume-case2"]["needs"], "generate-matrix")

    def test_jobs_use_checkout_v4_where_needed(self):
        for job in ("unit-tests", "generate-matrix"):
            uses = [s.get("uses") for s in self.jobs[job]["steps"]]
            self.assertIn("actions/checkout@v4", uses)

    def test_matrix_config_env_var_points_to_existing_fixture(self):
        config = self.doc["env"]["MATRIX_CONFIG"]
        self.assertEqual(config, "fixtures/config.json")
        self.assertTrue(os.path.exists(os.path.join(REPO_ROOT, config)))

    def test_workflow_references_existing_script_files(self):
        with open(WORKFLOW_PATH, encoding="utf-8") as handle:
            text = handle.read()
        for path in (
            "matrix_generator.py",
            "fixtures/case2_include_exclude.json",
            "fixtures/invalid_too_large.json",
            "tests",
        ):
            self.assertIn(path, text)
            self.assertTrue(
                os.path.exists(os.path.join(REPO_ROOT, path)),
                f"workflow references missing path: {path}",
            )

    def test_consume_jobs_use_generated_matrices(self):
        for job, output in (
            ("consume-case1", "strategy1"),
            ("consume-case2", "strategy2"),
        ):
            strategy = self.jobs[job]["strategy"]
            self.assertIn(
                f"fromJSON(needs.generate-matrix.outputs.{output}).matrix",
                strategy["matrix"],
            )

    def test_generate_job_exposes_strategy_outputs(self):
        outputs = self.jobs["generate-matrix"]["outputs"]
        self.assertEqual(
            outputs["strategy1"], "${{ steps.gen1.outputs.strategy }}"
        )
        self.assertEqual(
            outputs["strategy2"], "${{ steps.gen2.outputs.strategy }}"
        )

    @unittest.skipUnless(
        shutil.which("actionlint"), "actionlint not installed here"
    )
    def test_actionlint_passes(self):
        proc = subprocess.run(
            ["actionlint", WORKFLOW_PATH], capture_output=True, text=True
        )
        self.assertEqual(proc.returncode, 0, proc.stdout + proc.stderr)


if __name__ == "__main__":
    unittest.main()
