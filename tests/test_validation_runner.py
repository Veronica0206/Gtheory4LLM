"""Test orchestration contracts without rerunning numerical fits recursively."""
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("validation_runner", ROOT / "scripts/run_validation.py")
RUNNER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(RUNNER)


def external_temporary_base() -> Path:
    """A writable temporary base outside the checkout.

    The ambient base is used when it already lies outside the checkout. When
    TMPDIR points inside the checkout, a supported invocation environment, the
    system locations are tried instead, so a test that must allocate outside
    the checkout does so by choice rather than by assumption.
    """
    candidates = [Path(tempfile.gettempdir())]
    candidates += [Path(x) for x in ("/tmp", "/var/tmp")]
    candidates.append(Path.home())
    for candidate in candidates:
        resolved = candidate.resolve()
        if ROOT in resolved.parents or resolved == ROOT or not resolved.is_dir():
            continue
        try:
            with tempfile.TemporaryDirectory(dir=str(resolved)):
                return resolved
        except OSError:
            continue
    raise RuntimeError("No writable temporary base outside the checkout was found.")


class ValidationRunnerTests(unittest.TestCase):
    def test_existing_summary_is_refused_before_staging_or_running_checks(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "report.json"
            original = b'{"success": true, "historical": true}\n'
            output.write_bytes(original)
            with patch.object(RUNNER, "default_release_manifest") as stage, \
                    patch.object(RUNNER, "launch") as launch, \
                    self.assertRaises(SystemExit) as error:
                RUNNER.main(["--output", str(output)])
            self.assertEqual(error.exception.code, 2)
            stage.assert_not_called()
            launch.assert_not_called()
            self.assertEqual(output.read_bytes(), original)

    def test_the_entry_point_stages_a_manifest_only_when_none_is_supplied_and_a_run_needs_one(self):
        explicit = Path("/explicit/manifest.json")
        # The rehearsal staging below is synthetic, so this test chooses where
        # it is allocated: outside the checkout, whatever the ambient base is.
        self.addCleanup(setattr, tempfile, "tempdir", tempfile.tempdir)
        tempfile.tempdir = str(external_temporary_base())
        with patch.object(RUNNER, "select_release_manifest") as select, \
                patch.object(RUNNER, "retained_manifest_applies", return_value=False):
            self.assertEqual(RUNNER.default_release_manifest(explicit, ROOT, needed=True), (explicit, None))
            self.assertEqual(RUNNER.default_release_manifest(None, ROOT, needed=False), (None, None))
            select.assert_not_called()
            # A rehearsal bundle staged inside the destination keeps its directory alive.
            select.side_effect = lambda root, destination, **kwargs: destination / "manifest.json"
            manifest, staging = RUNNER.default_release_manifest(
                None, ROOT, needed=True, rscript="/resolved/Rscript", environment={"R_LIBS_USER": "/lib"}, timeout=9)
        self.assertIsNotNone(staging)
        self.assertEqual(manifest, Path(staging.name) / "manifest.json")
        select.assert_called_once()
        root, destination = select.call_args.args
        self.assertEqual(root, ROOT)
        self.assertEqual(destination, Path(staging.name))
        self.assertEqual(select.call_args.kwargs,
                         {"rscript": "/resolved/Rscript", "environment": {"R_LIBS_USER": "/lib"}, "timeout": 9})
        self.assertTrue(Path(staging.name).is_dir())
        self.assertNotIn(ROOT, Path(staging.name).parents)
        staging.cleanup()
        self.assertFalse(Path(staging.name).exists())

    def test_the_staging_test_passes_with_the_temporary_base_inside_the_checkout(self):
        # The real interpreter, the real test module and a temporary base that
        # lies inside the checkout: the environment under which the Python
        # stage of the source gate used to fail. The probe directory exists for
        # the duration of the run so that the nested base is genuinely used.
        probe = ROOT / ".gtheory-nested-temporary-base-probe"
        probe.mkdir(exist_ok=False)
        self.addCleanup(shutil.rmtree, probe, True)
        environment = {key: value for key, value in os.environ.items() if key not in ("TMPDIR", "TMP", "TEMP")}
        environment.update({"TMPDIR": str(probe), "TMP": str(probe), "TEMP": str(probe)})
        target = ("tests.test_validation_runner.ValidationRunnerTests."
                  "test_the_entry_point_stages_a_manifest_only_when_none_is_supplied_and_a_run_needs_one")
        completed = subprocess.run([sys.executable, "-m", "unittest", target], cwd=ROOT, env=environment,
                                   capture_output=True, text=True, timeout=300)
        self.assertEqual(completed.returncode, 0, completed.stderr)
        self.assertIn("OK", completed.stderr)
        self.assertFalse(list(probe.iterdir()), "nothing may be left behind inside the checkout")

    def test_a_retained_manifest_allocates_no_staging_directory(self):
        # Whether anything must be built is decided first, so a development or
        # matching version never creates a temporary directory it would then
        # have to reject when the temporary base lies inside the checkout.
        with patch.object(RUNNER, "retained_manifest_applies", return_value=True), \
                patch.object(RUNNER, "select_release_manifest",
                             return_value=ROOT / "artifacts/manifest.json") as select, \
                patch.object(RUNNER.tempfile, "TemporaryDirectory") as allocate:
            manifest, staging = RUNNER.default_release_manifest(None, ROOT, needed=True, rscript="/r")
        self.assertEqual(manifest, ROOT / "artifacts/manifest.json")
        self.assertIsNone(staging)
        allocate.assert_not_called()
        self.assertEqual(select.call_args.args, (ROOT, None))
        self.assertEqual(select.call_args.kwargs["rscript"], "/r")

    def test_a_development_run_succeeds_with_the_temporary_base_inside_the_checkout(self):
        # The entry point on this development checkout, unmodified apart from
        # the stage plan: the retained manifest is selected and verified for
        # real while every temporary directory would have to be created inside
        # the checkout. Nothing is staged, so nothing is rejected.
        base = tempfile.gettempdir()
        probe = ROOT / "gtheory-tmp-inside-checkout-probe"
        self.addCleanup(setattr, tempfile, "tempdir", tempfile.tempdir)
        tempfile.tempdir = str(probe)
        # The stage launcher is replaced, not subprocess.run: staging verifies
        # the retained bundle for real, with git.
        with tempfile.TemporaryDirectory(dir=base) as directory:
            output = Path(directory) / "report.json"
            with patch.object(RUNNER.shutil, "which", return_value="/resolved/Rscript"), \
                 patch.object(RUNNER, "commands", return_value=[("first", ["first"])]) as plan, \
                 patch.object(RUNNER, "launch", return_value=subprocess.CompletedProcess(["first"], 0)) as run:
                status = RUNNER.main(["--scope", "source", "--compatibility", "--output", str(output)])
            report = json.loads(output.read_text())
        self.assertEqual(status, 0)
        self.assertEqual(run.call_count, 1)
        self.assertFalse(probe.exists())
        self.assertEqual(report["release_manifest"], str(ROOT / "artifacts/manifest.json"))
        self.assertFalse(report["release_manifest_staged"])
        staging, first = report["stages"]
        self.assertEqual((staging["name"], staging["exit_code"]), ("release_manifest_staging", 0))
        self.assertIn("Retained manifest", staging["detail"])
        self.assertEqual(first["name"], "first")
        self.assertEqual(plan.call_args.args[7], ROOT / "artifacts/manifest.json")
        self.assertFalse(plan.call_args.args[9])

    def test_staging_runs_with_the_resolved_interpreter_library_and_timeout(self):
        captured = {}

        def select(root, destination, **kwargs):
            captured.update(kwargs)
            return destination / "manifest.json"

        with tempfile.TemporaryDirectory() as directory:
            library = Path(directory) / "library"
            library.mkdir()
            output = Path(directory) / "report.json"
            with patch.object(RUNNER.shutil, "which", return_value="/resolved/Rscript"), \
                 patch.object(RUNNER, "retained_manifest_applies", return_value=False), \
                 patch.object(RUNNER, "select_release_manifest", side_effect=select), \
                 patch.object(RUNNER, "commands", return_value=[("first", ["first"])]) as plan, \
                 patch.object(RUNNER.subprocess, "run") as run:
                run.return_value.returncode = 0
                status = RUNNER.main(["--scope", "source", "--library", str(library), "--timeout", "77",
                                      "--output", str(output)])
            report = json.loads(output.read_text())
        self.assertEqual(status, 0)
        self.assertEqual(captured["rscript"], "/resolved/Rscript")
        self.assertEqual(captured["environment"]["R_LIBS_USER"], str(library.resolve()))
        self.assertEqual(captured["environment"]["GTHEORY_FULL_VALIDATION"], "true")
        self.assertEqual(captured["timeout"], 77)
        self.assertTrue(report["release_manifest_staged"])
        self.assertTrue(plan.call_args.args[9])
        staging = report["stages"][0]
        self.assertEqual((staging["name"], staging["exit_code"]), ("release_manifest_staging", 0))
        self.assertIn("Rehearsal bundle", staging["detail"])
        self.assertFalse(Path(report["release_manifest"]).parent.exists())

    def test_a_failed_staging_is_a_failed_stage_of_the_report(self):
        for error, code in ((subprocess.CalledProcessError(3, ["prepare_release.py"]), 3),
                            (subprocess.TimeoutExpired(["prepare_release.py"], 77), 124),
                            (ValueError("Validation bundle must be outside the source checkout."), 1)):
            with self.subTest(code=code), tempfile.TemporaryDirectory() as directory:
                output = Path(directory) / "report.json"
                with patch.object(RUNNER.shutil, "which", return_value="/resolved/Rscript"), \
                     patch.object(RUNNER, "default_release_manifest", side_effect=error), \
                     patch.object(RUNNER, "commands") as plan, \
                     patch.object(RUNNER.subprocess, "run") as run:
                    status = RUNNER.main(["--scope", "source", "--timeout", "77", "--output", str(output)])
                report = json.loads(output.read_text())
                self.assertEqual(status, 1)
                run.assert_not_called()
                plan.assert_not_called()
                self.assertEqual([stage["name"] for stage in report["stages"]], ["release_manifest_staging"])
                self.assertEqual(report["stages"][0]["exit_code"], code)
                self.assertFalse(report["success"])
                self.assertFalse(report["source_validation_passed"])

    def test_the_artifact_scope_checks_the_retained_bundle_and_stages_nothing(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "report.json"
            with patch.object(RUNNER.shutil, "which", return_value="/resolved/Rscript"), \
                 patch.object(RUNNER, "retained_manifest_applies") as applies, \
                 patch.object(RUNNER, "select_release_manifest") as select, \
                 patch.object(RUNNER, "commands", return_value=[("first", ["first"])]), \
                 patch.object(RUNNER.subprocess, "run") as run:
                run.return_value.returncode = 0
                status = RUNNER.main(["--scope", "artifact", "--output", str(output)])
            report = json.loads(output.read_text())
        self.assertEqual(status, 0)
        applies.assert_not_called()
        select.assert_not_called()
        self.assertIsNone(report["release_manifest"])
        self.assertFalse(report["release_manifest_staged"])
        self.assertEqual(report["release_manifest_stages"], [])
        self.assertEqual([stage["name"] for stage in report["stages"]], ["first"])

    def test_a_failed_staging_releases_its_directory(self):
        with patch.object(RUNNER, "retained_manifest_applies", return_value=False), \
                patch.object(RUNNER, "select_release_manifest", side_effect=ValueError("no bundle")):
            with self.assertRaises(ValueError):
                RUNNER.default_release_manifest(None, ROOT, needed=True)

    def test_maintenance_request_is_explicitly_propagated_only_to_source_package_check(self):
        reason = "CRAN requested noLD correction before 2026-10-26"
        lock = {"R": {"Version": "4.5.3"}, "Packages": {}}
        plan = RUNNER.commands(ROOT, "Rscript", lock, False, as_cran=True,
                               cran_requested_maintenance=reason)
        matching = [(name, command) for name, command in plan if "--cran-requested-maintenance" in command]
        self.assertEqual(len(matching), 1)
        name, command = matching[0]
        self.assertEqual(name, "package_build_install_check")
        self.assertIn("--as-cran", command)
        self.assertEqual(command[command.index("--cran-requested-maintenance") + 1], reason)
        for kwargs in ({"as_cran": False}, {"as_cran": True, "scope": "artifact"},
                       {"as_cran": True, "cran_requested_maintenance": " "}):
            with self.subTest(kwargs=kwargs), self.assertRaises(ValueError):
                RUNNER.commands(ROOT, "Rscript", lock, False,
                                **{"cran_requested_maintenance": reason, **kwargs})

    def test_an_explicit_manifest_reaches_both_checks_and_a_staged_one_only_the_identity_check(self):
        lock = json.loads((ROOT / "renv.lock").read_text())
        manifest = ROOT / "scratch-manifest.json"
        plan = RUNNER.commands(ROOT, "Rscript", lock, False, release_manifest=manifest)
        checked = [command for name, command in plan if name in
                   {"release_identity", "committed_artifact_integrity_install_smoke"}]
        self.assertEqual(len(checked), 2)
        for command in checked:
            self.assertEqual(command[command.index("--manifest") + 1], str(manifest.resolve()))
            self.assertIn("--check-release-identity", command)
        self.assertEqual(RUNNER.manifest_stages(plan),
                         ["release_identity", "committed_artifact_integrity_install_smoke"])
        # A rehearsal the entry point staged is evidence about the sources, not
        # about the committed bundle: the artifact stage keeps the retained one.
        staged = RUNNER.commands(ROOT, "Rscript", lock, False, release_manifest=manifest,
                                 release_manifest_staged=True)
        self.assertEqual(RUNNER.manifest_stages(staged), ["release_identity"])
        artifact = dict(staged)["committed_artifact_integrity_install_smoke"]
        self.assertNotIn("--manifest", artifact)
        self.assertIn("--check-release-identity", artifact)

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
                 patch.object(RUNNER, "default_release_manifest", return_value=(None, None)), \
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
