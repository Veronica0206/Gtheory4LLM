"""Test orchestration contracts without rerunning numerical fits recursively."""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("validation_runner", ROOT / "scripts/run_validation.py")
RUNNER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(RUNNER)


class ValidationRunnerTests(unittest.TestCase):
    def setUp(self):
        self.lock = json.loads((ROOT / "renv.lock").read_text())

    def test_every_r_test_and_example_gets_a_clean_process(self):
        plan = RUNNER.commands(ROOT, "Rscript", self.lock, False)
        r_commands = [command for _, command in plan if command[0] == "Rscript"]
        self.assertEqual(len(r_commands), len(list((ROOT / "tests").glob("test_*.R"))) + 2)
        self.assertTrue(all(command[1] == "--vanilla" for command in r_commands))
        self.assertIn("standalone_example", [name for name, _ in plan])
        if (ROOT / "DESCRIPTION").exists():
            self.assertEqual(plan[-1][0], "committed_artifact_integrity_install_smoke")
            self.assertIn("package_build_install_check", [name for name, _ in plan])
        self.assertIn("python_regressions", [name for name, _ in plan])
        self.assertNotIn("archive_integrity", [name for name, _ in plan])
        source = RUNNER.commands(ROOT, "Rscript", self.lock, False, scope="source")
        artifact = RUNNER.commands(ROOT, "Rscript", self.lock, False, scope="artifact")
        self.assertNotIn("committed_artifact_integrity_install_smoke", [name for name, _ in source])
        self.assertEqual([name for name, _ in artifact], ["dependency_preflight", "committed_artifact_integrity_install_smoke"])

    def test_required_comparisons_and_exact_versions_are_in_preflight(self):
        code = RUNNER.preflight_code(self.lock, False)
        for name in ("OpenMx", "lme4", "ordinal"):
            self.assertIn(json.dumps(name), code)
            self.assertIn(self.lock["Packages"][name]["Version"], code)
        self.assertIn("strict <- TRUE", code)
        self.assertIn("stop(\"Full validation requires:", code)
        self.assertIn("strict <- FALSE", RUNNER.preflight_code(self.lock, True))

    def test_failure_stops_gate_and_is_recorded(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "report.json"
            with patch.object(RUNNER.shutil, "which", return_value="Rscript"), \
                 patch.object(RUNNER, "commands", return_value=[("first", ["first"]), ("second", ["second"])]), \
                 patch.object(RUNNER.subprocess, "run") as run:
                run.return_value.returncode = 9
                status = RUNNER.main(["--output", str(output)])
            self.assertEqual(status, 1)
            self.assertEqual(run.call_count, 1)
            report = json.loads(output.read_text())
            self.assertFalse(report["full_locked_validation_passed"])
            self.assertEqual(report["stages"][0]["exit_code"], 9)

    def test_preflight_pass_is_not_reported_as_full_validation(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "report.json"
            with patch.object(RUNNER.shutil, "which", return_value="Rscript"), \
                 patch.object(RUNNER.subprocess, "run") as run:
                run.return_value.returncode = 0
                status = RUNNER.main(["--preflight-only", "--library", directory, "--output", str(output)])
            self.assertEqual(status, 0)
            self.assertFalse(json.loads(output.read_text())["full_locked_validation_passed"])
            self.assertEqual(run.call_args.kwargs["env"]["R_LIBS_USER"], str(Path(directory).resolve()))


if __name__ == "__main__":
    unittest.main()
