"""Workflow *structure* tests (host-side).

These verify the GitHub Actions workflow YAML itself: its triggers, jobs, job
dependencies, permissions, that it references the script/test paths that
actually exist, and that it passes ``actionlint``.

They depend on PyYAML and ``actionlint``, which are present on the host but NOT
inside the minimal ``act`` container.  The imports/tools are therefore guarded
so that when this module is discovered by the *in-container* ``unittest`` run it
cleanly **skips** instead of erroring -- the functional scenarios are what run
through ``act`` (see ``run_act_tests.py``); structure checks run on the host.
"""

import os
import shutil
import subprocess
import unittest

try:
    import yaml  # PyYAML -- host only
    HAVE_YAML = True
except ImportError:  # pragma: no cover - exercised only inside the act container
    HAVE_YAML = False

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WORKFLOW = os.path.join(REPO_ROOT, ".github", "workflows", "dependency-license-checker.yml")


def _load_workflow():
    with open(WORKFLOW, encoding="utf-8") as fh:
        return yaml.safe_load(fh)


def _on_section(data):
    # YAML 1.1 parses the bare key ``on`` as the boolean True, so accept either.
    return data.get("on", data.get(True))


@unittest.skipUnless(HAVE_YAML, "PyYAML not available (in-container run)")
class WorkflowStructureTests(unittest.TestCase):
    def setUp(self):
        self.assertTrue(os.path.isfile(WORKFLOW), f"workflow missing: {WORKFLOW}")
        self.data = _load_workflow()

    def test_has_expected_triggers(self):
        triggers = _on_section(self.data)
        self.assertIsInstance(triggers, dict)
        for trig in ("push", "pull_request", "workflow_dispatch", "schedule"):
            self.assertIn(trig, triggers)
        # schedule must carry a valid-looking cron entry
        self.assertEqual(triggers["schedule"][0]["cron"], "0 6 * * 1")

    def test_permissions_are_read_only(self):
        self.assertEqual(self.data["permissions"]["contents"], "read")

    def test_jobs_and_dependency_order(self):
        jobs = self.data["jobs"]
        self.assertIn("unit-tests", jobs)
        self.assertIn("license-check", jobs)
        # license-check must run only after unit-tests (job dependency).
        self.assertEqual(jobs["license-check"]["needs"], "unit-tests")

    def test_both_jobs_checkout_at_v4(self):
        for job_name in ("unit-tests", "license-check"):
            uses = [s.get("uses") for s in self.data["jobs"][job_name]["steps"]]
            self.assertIn("actions/checkout@v4", uses)

    def test_env_paths_point_at_existing_files(self):
        env = self.data["env"]
        for key in ("MANIFEST_PATH", "POLICY_PATH", "LICENSE_DB_PATH"):
            rel = env[key]
            self.assertTrue(
                os.path.isfile(os.path.join(REPO_ROOT, rel)),
                f"env {key} -> '{rel}' does not exist",
            )

    def test_workflow_references_real_script_and_tests(self):
        with open(WORKFLOW, encoding="utf-8") as fh:
            raw = fh.read()
        self.assertIn("license_checker.py", raw)
        self.assertTrue(os.path.isfile(os.path.join(REPO_ROOT, "license_checker.py")))
        # the unit-test job discovers tests/ -- that directory must exist
        self.assertIn("unittest discover -s tests", raw)
        self.assertTrue(os.path.isdir(os.path.join(REPO_ROOT, "tests")))


@unittest.skipUnless(shutil.which("actionlint"), "actionlint not installed")
class ActionlintTests(unittest.TestCase):
    def test_workflow_passes_actionlint(self):
        proc = subprocess.run(
            ["actionlint", WORKFLOW],
            capture_output=True,
            text=True,
        )
        self.assertEqual(
            proc.returncode,
            0,
            msg=f"actionlint failed:\n{proc.stdout}\n{proc.stderr}",
        )


if __name__ == "__main__":  # pragma: no cover
    unittest.main()
