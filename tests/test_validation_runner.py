"""Test orchestration contracts without rerunning numerical fits recursively."""
import importlib.util
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("validation_runner", ROOT / "scripts/run_validation.py")
RUNNER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(RUNNER)


class ValidationRunnerTests(unittest.TestCase):
    def test_reference_manual_stage_runs_only_where_latex_exists(self):
        # The manual gate is the only check that rejects overfull boxes, so it
        # belongs in the source scope. It is omitted rather than faked where no
        # LaTeX engine exists, and the report distinguishes the two.
        lock = {"R": {"Version": "4.5.3"}, "Packages": {}}
        with patch.object(RUNNER, "tex_available", return_value=True):
            names = [name for name, _ in RUNNER.commands(RUNNER.ROOT, "Rscript", lock, False, "source")]
        self.assertIn("reference_manual", names)
        self.assertLess(names.index("reference_manual"), names.index("package_build_install_check"))
        with patch.object(RUNNER, "tex_available", return_value=False):
            without = [name for name, _ in RUNNER.commands(RUNNER.ROOT, "Rscript", lock, False, "source")]
        self.assertNotIn("reference_manual", without)
        # The artifact scope checks a built bundle and does not rebuild docs.
        with patch.object(RUNNER, "tex_available", return_value=True):
            artifact = [name for name, _ in RUNNER.commands(RUNNER.ROOT, "Rscript", lock, False, "artifact")]
        self.assertNotIn("reference_manual", artifact)

    def test_manual_stage_invokes_the_overfull_gate(self):
        stage, command = RUNNER.manual_stage(RUNNER.ROOT, "Rscript")
        self.assertEqual(stage, "reference_manual")
        self.assertTrue(command[-2].endswith("Gtheory4LLM-manual.pdf"))
        self.assertIn("build_manual.R", " ".join(command))

    def setUp(self):
        self.lock = json.loads((ROOT / "renv.lock").read_text())

    def test_every_r_test_and_example_gets_a_clean_process(self):
        plan = RUNNER.commands(ROOT, "Rscript", self.lock, False)
        r_commands = [command for _, command in plan if command[0] == "Rscript"]
        # Every R test file, plus the preflight, the standalone example, and the
        # reference-manual gate where a LaTeX engine exists to run it.
        expected = len(list((ROOT / "tests").glob("test_*.R"))) + 2 + int(RUNNER.tex_available())
        self.assertEqual(len(r_commands), expected)
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

    @unittest.skipUnless(shutil.which("Rscript"), "Rscript is required to exercise the version gate")
    def test_minimum_r_is_checked_before_loading_incompatible_dependencies(self):
        code = RUNNER.preflight_code(self.lock, True)
        for version, expected_pass in (("4.4.3", False), ("4.5.0", True)):
            with self.subTest(version=version), tempfile.TemporaryDirectory() as directory:
                stubs = 'getRversion <- function() numeric_version("' + version + '")\n'
                if expected_pass:
                    stubs += ('requireNamespace <- function(...) TRUE\n'
                              'packageDescription <- function(p, fields) expected[[p]]\n'
                              'sessionInfo <- function() list(fixture_runtime="4.5.0")\n')
                else:
                    stubs += 'requireNamespace <- function(...) stop("dependency loading was reached")\n'
                script = Path(directory) / "preflight.R"
                script.write_bytes((stubs + code).encode("utf-8"))
                result = subprocess.run([shutil.which("Rscript"), "--vanilla", str(script)],
                                        capture_output=True, text=True, timeout=30)
                self.assertEqual(result.returncode == 0, expected_pass, result.stderr)
                if not expected_pass:
                    self.assertIn("requires R >= 4.5.0", result.stderr)
                    self.assertNotIn("dependency loading was reached", result.stderr)

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

    def test_generated_preflight_uses_closed_script_file_and_preserves_arguments(self):
        code = 'cat("quoted value\\n")\nstopifnot(TRUE)\n'
        calls = []

        def observe(command, **kwargs):
            calls.append(command)
            self.assertNotIn("-e", command)
            self.assertEqual(command[:2], ["SelectedRscript", "--vanilla"])
            self.assertEqual(command[3:], ["argument with spaces"])
            self.assertEqual(Path(command[2]).read_text(encoding="utf-8"), code)
            self.assertEqual(kwargs["timeout"], 13)
            self.assertEqual(kwargs["env"], {"EXAMPLE": "1"})
            return type("Result", (), {"returncode": 0})()

        with patch.object(RUNNER.subprocess, "run", side_effect=observe):
            result = RUNNER.launch(["SelectedRscript", "--vanilla", "-e", code,
                                    "argument with spaces"], environment={"EXAMPLE": "1"}, timeout=13)
        self.assertEqual(result.returncode, 0)
        self.assertFalse(Path(calls[0][2]).exists())

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
