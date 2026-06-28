"""Structure tests for the GitHub Actions workflow.

These run on the host (not through act): they statically validate that the
workflow has the expected triggers, jobs, dependencies, and step references,
that every path the workflow points at actually exists, and that actionlint is
happy. Run with:  python3 -m unittest test_workflow_structure -v
"""

import os
import shutil
import subprocess
import unittest

import yaml

HERE = os.path.dirname(os.path.abspath(__file__))
WORKFLOW = os.path.join(HERE, ".github", "workflows", "secret-rotation-validator.yml")


def load_workflow():
    with open(WORKFLOW, "r", encoding="utf-8") as fh:
        return yaml.safe_load(fh)


def get_triggers(data):
    # YAML 1.1 (PyYAML) parses the bare key ``on`` as the boolean True, so the
    # trigger map can live under either True or the string "on".
    return data[True] if True in data else data["on"]


class WorkflowFileTests(unittest.TestCase):
    def test_workflow_file_exists(self):
        self.assertTrue(os.path.isfile(WORKFLOW), f"missing workflow: {WORKFLOW}")

    def test_yaml_parses(self):
        self.assertIsInstance(load_workflow(), dict)


class TriggerTests(unittest.TestCase):
    def setUp(self):
        self.triggers = get_triggers(load_workflow())

    def test_has_expected_trigger_events(self):
        for event in ("push", "pull_request", "schedule", "workflow_dispatch"):
            self.assertIn(event, self.triggers, f"missing trigger: {event}")

    def test_schedule_has_cron(self):
        self.assertIn("cron", self.triggers["schedule"][0])

    def test_workflow_dispatch_exposes_warning_days_input(self):
        inputs = self.triggers["workflow_dispatch"]["inputs"]
        self.assertIn("warning_days", inputs)


class JobStructureTests(unittest.TestCase):
    def setUp(self):
        self.data = load_workflow()
        self.jobs = self.data["jobs"]

    def test_has_permissions_block(self):
        self.assertEqual(self.data["permissions"]["contents"], "read")

    def test_declares_env_vars(self):
        self.assertIn("CONFIG_FILE", self.data["env"])
        self.assertIn("REPORT_MARKER", self.data["env"])

    def test_expected_jobs_present(self):
        self.assertIn("test", self.jobs)
        self.assertIn("report", self.jobs)

    def test_report_depends_on_test(self):
        # job dependency
        self.assertEqual(self.jobs["report"]["needs"], "test")

    def test_jobs_run_on_ubuntu(self):
        for job in self.jobs.values():
            self.assertEqual(job["runs-on"], "ubuntu-latest")

    def test_steps_use_checkout_v4(self):
        for name, job in self.jobs.items():
            uses = [s.get("uses", "") for s in job["steps"]]
            self.assertIn(
                "actions/checkout@v4", uses, f"job {name} should checkout@v4"
            )


class ScriptReferenceTests(unittest.TestCase):
    """The workflow must reference real files that exist in the repo."""

    def setUp(self):
        self.data = load_workflow()

    def test_workflow_invokes_the_validator_script(self):
        run_steps = " ".join(
            s.get("run", "")
            for job in self.data["jobs"].values()
            for s in job["steps"]
        )
        self.assertIn("secret_rotation_validator.py", run_steps)
        self.assertIn("unittest", run_steps)

    def test_referenced_script_exists(self):
        self.assertTrue(
            os.path.isfile(os.path.join(HERE, "secret_rotation_validator.py"))
        )

    def test_tests_directory_exists(self):
        self.assertTrue(os.path.isdir(os.path.join(HERE, "tests")))

    def test_config_file_referenced_in_env_exists(self):
        config = self.data["env"]["CONFIG_FILE"]
        self.assertTrue(
            os.path.isfile(os.path.join(HERE, config)),
            f"CONFIG_FILE points at a missing path: {config}",
        )


class ActionlintTests(unittest.TestCase):
    @unittest.skipUnless(shutil.which("actionlint"), "actionlint not installed")
    def test_actionlint_passes(self):
        result = subprocess.run(
            ["actionlint", WORKFLOW],
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
        )
        self.assertEqual(
            result.returncode, 0,
            f"actionlint reported problems:\n{result.stdout}",
        )


if __name__ == "__main__":
    unittest.main()
