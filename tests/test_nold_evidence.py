"""Exercise noLD evidence gates without a container or a numerical model fit."""
from __future__ import annotations

import csv
import contextlib
import hashlib
import importlib.util
import io
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tarfile
import tempfile
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[1]
WORKFLOW = ROOT / ".github/workflows/cran-readiness.yml"
RSCRIPT = shutil.which("Rscript")
BASH = shutil.which("bash")
SPEC = importlib.util.spec_from_file_location("nold_verify_candidate", ROOT / ".github/nold/verify_candidate.py")
VERIFY = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(VERIFY)


class NoLDCandidateIdentityTests(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory(prefix="gtheory-nold-identity-")
        self.addCleanup(directory.cleanup)
        self.root = Path(directory.name).resolve()
        self.candidate = self.root / "candidate"
        self.candidate.mkdir()
        self.archive = self.candidate / "Example_0.4.0.tar.gz"
        self.commit = "a" * 40

    def candidate_with(self, description=b"Package: Example\nVersion: 0.4.0\n",
                       member="Example/DESCRIPTION"):
        with tarfile.open(self.archive, "w:gz") as archive:
            if description is not None:
                info = tarfile.TarInfo(member)
                info.size = len(description)
                archive.addfile(info, io.BytesIO(description))
        manifest = {"schema_version": 1, "package": "Example", "version": "0.4.0",
                    "archive": self.archive.name, "source_commit": self.commit,
                    "bytes": self.archive.stat().st_size,
                    "sha256": hashlib.sha256(self.archive.read_bytes()).hexdigest()}
        (self.candidate / "candidate.json").write_text(json.dumps(manifest))
        return manifest

    def test_internal_package_version_is_verified_without_changing_the_archive(self):
        manifest = self.candidate_with()
        before = self.archive.read_bytes()
        actual, archive = VERIFY.verify_candidate(self.candidate, self.commit)
        self.assertEqual(actual, manifest)
        self.assertEqual(archive, self.archive)
        self.assertEqual(archive.read_bytes(), before)

    def test_invalid_internal_metadata_is_rejected_despite_matching_checksum(self):
        descriptions = (
            b"Package: Other\nVersion: 0.4.0\n",
            b"Package: Example\nVersion: 0.2.0\n",
            b"Package: Example\n",
            b"Version: 0.4.0\n",
            b"Package: Example\nPackage: Other\nVersion: 0.4.0\n",
            b"this is not a DESCRIPTION record\n",
            None,
        )
        env_file = self.root / "github-env"
        env_file.write_text("EXISTING=value\n")
        for description in descriptions:
            with self.subTest(description=description):
                self.candidate_with(description)
                with patch.object(VERIFY, "ROOT", self.root), \
                        patch.object(VERIFY.subprocess, "check_output", return_value=self.commit), \
                        patch.dict(os.environ, GITHUB_RUN_ID="123", GITHUB_ENV=str(env_file)), \
                        self.assertRaises(ValueError):
                    VERIFY.main([str(self.candidate)])
                self.assertFalse((self.root / "nold-evidence").exists())
                self.assertEqual(env_file.read_text(), "EXISTING=value\n")

    def test_unsafe_tar_member_is_rejected_before_any_extraction(self):
        self.candidate_with(member="Example/../DESCRIPTION")
        with self.assertRaisesRegex(ValueError, "Unsafe archive member"):
            VERIFY.verify_candidate(self.candidate, self.commit)
        self.assertFalse((self.root / "DESCRIPTION").exists())

    def test_success_records_checked_identity_and_exports_specimen_location(self):
        manifest = self.candidate_with()
        env_file = self.root / "github-env"
        with patch.object(VERIFY, "ROOT", self.root), \
                patch.object(VERIFY.subprocess, "check_output", return_value=self.commit) as git_read, \
                patch.dict(os.environ, GITHUB_RUN_ID="123", GITHUB_ENV=str(env_file)), \
                contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(VERIFY.main([str(self.candidate)]), 0)
        self.assertEqual(git_read.call_args.args[0],
                         ["git", "-c", "safe.directory=" + str(self.root),
                          "-C", str(self.root), "rev-parse", "HEAD"])
        evidence = self.root / "nold-evidence"
        identity = json.loads((evidence / "archive-identity.json").read_text())
        self.assertTrue(identity["verified"])
        for key in ("package", "version", "source_commit", "bytes", "sha256"):
            self.assertEqual(identity[key], manifest[key])
        self.assertEqual(json.loads((evidence / "candidate.json").read_text()), manifest)
        self.assertIn("ARCHIVE=" + str(self.archive) + "\n", env_file.read_text())
        self.assertIn("GTHEORY_DISCRETE_SPECIMEN_DIR=" + str(evidence / "specimens") + "\n",
                      env_file.read_text())


def nold_job() -> str:
    text = WORKFLOW.read_text(encoding="utf-8")
    match = re.search(r"(?ms)^  nold:\n(.*?)(?=^  [A-Za-z][\w-]*:\n|\Z)", text)
    if match is None:
        raise AssertionError("The exact-candidate noLD job is missing")
    return match[1]


def step_run(job: str, name: str) -> str:
    match = re.search(rf"(?ms)^      - name: {re.escape(name)}\n(.*?)(?=^      - |\Z)", job)
    if match is None:
        raise AssertionError(f"Missing evidence step: {name}")
    step = match[1]
    run = re.search(r"(?m)^        run: (.*)$", step)
    if run is None:
        raise AssertionError(f"Missing run command: {name}")
    if run[1] != "|":
        return run[1]
    lines = []
    for line in step[run.end():].splitlines():
        if line.startswith("          "):
            lines.append(line[10:])
        elif line.strip():
            break
    return "\n".join(lines)


def normalized_shell_path(path: str | Path) -> str:
    """Bash may append forward slashes to a native Windows environment path."""
    return os.path.normcase(os.path.normpath(str(path).replace("\\", "/")))


class NoLDEvidenceWorkflowTests(unittest.TestCase):
    def test_mixed_windows_shell_separators_preserve_path_identity(self):
        root = r"C:\Users\RUNNER~1\AppData\Local\Temp\directory with spaces"
        for suffix in ("lib", "nold-evidence/reference-setup"):
            mixed = root + "/" + suffix
            native = root + "\\" + suffix.replace("/", "\\")
            self.assertEqual(normalized_shell_path(mixed), normalized_shell_path(native))
            self.assertNotEqual(normalized_shell_path(mixed), normalized_shell_path(native + "-other"))

    def test_candidate_and_evidence_paths_are_shared_with_the_gate(self):
        job = nold_job()
        self.assertIn("needs: build-release", job)
        self.assertIn("name: cran-candidate-built-${{ github.sha }}", job)
        self.assertIn('python3 .github/nold/verify_candidate.py "$RUNNER_TEMP/candidate"', job)
        self.assertRegex(job, r"image: ghcr\.io/r-hub/containers/nold@sha256:[0-9a-f]{64}")
        self.assertNotIn("actions/setup-python@", job)
        self.assertIn("apt-get install -y -qq python3", job)
        check = step_run(job, "Check the exact archive")
        self.assertIn('R CMD check --no-stop-on-test-error "$ARCHIVE"', check)
        self.assertIn('"$GITHUB_WORKSPACE/nold-evidence/check"', check)
        evidence = job.split("      - name: Keep the evidence\n", 1)[1]
        self.assertIn("if: always()", evidence)
        self.assertIn("nold-evidence/check/**/tests/*.Rout.fail", evidence)
        self.assertIn("nold-evidence/installed-tests/", evidence)
        for directory in ("reference-setup", "reference-loaded", "reference-final"):
            self.assertIn(f"nold-evidence/{directory}/", evidence)
        # Container-visible shell paths differ from runner.temp expressions
        # consumed by a host-side action. The upload must use checkout paths.
        self.assertNotIn("${{ runner.temp }}", evidence)

    def test_reference_backend_is_verified_before_and_after_package_checks(self):
        job = nold_job()
        steps = (
            "Select and verify reference BLAS for noLD",
            "Install TeX for the PDF manual",
            "Install the dependencies",
            "Install the exact archive",
            "Verify reference BLAS with installed numerical dependencies",
            "Show how the fit CRAN reported ends on this build",
            "Check the exact archive",
            "Run every installed test of the exact archive",
            "Recheck reference BLAS after the complete test run",
        )
        offsets = [job.index("      - name: " + name + "\n") for name in steps]
        self.assertEqual(offsets, sorted(offsets))
        setup = step_run(job, steps[0])
        self.assertIn('bash .github/nold/select_reference_blas.sh ', setup)
        self.assertIn('"$GITHUB_WORKSPACE/nold-evidence/reference-setup"', setup)
        for name in (steps[4], steps[-1]):
            command = step_run(job, name)
            self.assertIn('R_LIBS="$RUNNER_TEMP/lib" Rscript --vanilla ', command)
            self.assertIn('.github/nold/check_reference_blas.R reference ', command)
            self.assertIn('Matrix OpenMx lme4 ordinal Gtheory4LLM', command)
        self.assertNotIn("continue-on-error:", job)

    @unittest.skipUnless(BASH, "Bash is required to exercise the workflow pipelines")
    def test_all_pipelines_preserve_upstream_failure_and_captured_output(self):
        job = nold_job()
        self.assertRegex(job, r"defaults:\n      run:\n        shell: bash\n")
        commands = (
            ("Show how the fit CRAN reported ends on this build", "boundary-fit-diagnosis.txt"),
            ("Run every installed test of the exact archive", "installed-tests-summary.txt"),
            ("Verify reference BLAS with installed numerical dependencies", "reference-loaded.txt"),
            ("Recheck reference BLAS after the complete test run", "reference-final.txt"),
        )
        with tempfile.TemporaryDirectory(prefix="gtheory-nold-pipeline-") as temporary:
            root = Path(temporary)
            bin_dir = root / "bin"
            bin_dir.mkdir()
            fake = bin_dir / "Rscript"
            fake.write_text("#!/bin/sh\nprintf 'captured stdout\\n'\n"
                            "printf 'captured stderr\\n' >&2\n"
                            "printf 'library: %s\\n' \"$R_LIBS\"\n"
                            "exit \"$TEST_R_EXIT\"\n")
            fake.chmod(0o755)
            (root / "nold-evidence").mkdir()
            baseline = root / "reference-runtime.rds"
            baseline.write_text("The fake Rscript does not read this fixture.\n")
            env = dict(os.environ, PATH=str(bin_dir) + os.pathsep + os.environ.get("PATH", ""),
                       RUNNER_TEMP=str(root), GITHUB_WORKSPACE=str(root),
                       GTHEORY_REFERENCE_BASELINE=str(baseline))
            for name, filename in commands:
                command = step_run(job, name)
                for exit_code in (0, 7):
                    with self.subTest(step=name, upstream_exit=exit_code):
                        # GitHub's explicit Bash shell invokes -e -o pipefail.
                        result = subprocess.run(
                            [BASH, "--noprofile", "--norc", "-e", "-o", "pipefail", "-c", command],
                            cwd=ROOT, env=dict(env, TEST_R_EXIT=str(exit_code)),
                            capture_output=True, text=True, timeout=20)
                        self.assertEqual(result.returncode, exit_code, result.stderr)
                        captured = (root / "nold-evidence" / filename).read_text()
                        self.assertIn("captured stdout", captured)
                        self.assertIn("captured stderr", captured)
                        if filename.startswith("reference-"):
                            libraries = [normalized_shell_path(line.removeprefix("library: "))
                                         for line in captured.splitlines() if line.startswith("library: ")]
                            self.assertEqual(libraries, [normalized_shell_path(root / "lib")])

    @unittest.skipUnless(BASH, "Bash is required to exercise missing-baseline refusal")
    def test_later_reference_probes_require_the_exported_baseline_file(self):
        names = ("Verify reference BLAS with installed numerical dependencies",
                 "Recheck reference BLAS after the complete test run")
        with tempfile.TemporaryDirectory(prefix="gtheory-nold-baseline-") as temporary:
            root = Path(temporary)
            bin_dir = root / "bin"
            bin_dir.mkdir()
            fake = bin_dir / "Rscript"
            fake.write_text('#!/bin/sh\nprintf "Rscript must not execute without a baseline\\n"\n')
            fake.chmod(0o755)
            (root / "nold-evidence").mkdir()
            env = dict(os.environ, PATH=str(bin_dir) + os.pathsep + os.environ.get("PATH", ""),
                       RUNNER_TEMP=str(root), GITHUB_WORKSPACE=str(root))
            env.pop("GTHEORY_REFERENCE_BASELINE", None)
            for name in names:
                command = step_run(nold_job(), name)
                for value in (None, "", str(root / "missing-runtime.rds")):
                    with self.subTest(step=name, baseline=value):
                        scenario = dict(env)
                        if value is not None:
                            scenario["GTHEORY_REFERENCE_BASELINE"] = value
                        result = subprocess.run(
                            [BASH, "--noprofile", "--norc", "-e", "-o", "pipefail", "-c", command],
                            cwd=root, env=scenario, capture_output=True, text=True, timeout=20)
                        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
                        self.assertNotIn("Rscript must not execute", result.stdout + result.stderr)
                        if not value:
                            self.assertIn("missing reference backend baseline", result.stderr)

    @unittest.skipUnless(BASH, "Bash is required to exercise setup failure propagation")
    def test_reference_selection_failure_stops_the_workflow_step(self):
        command = step_run(nold_job(), "Select and verify reference BLAS for noLD")
        with tempfile.TemporaryDirectory(prefix="gtheory-nold-select-") as temporary:
            root = Path(temporary)
            helper = root / ".github/nold/select_reference_blas.sh"
            helper.parent.mkdir(parents=True)
            helper.write_text('printf "output: %s\\n" "$1"\nexit "$TEST_SELECT_EXIT"\n')
            for status in (0, 19):
                with self.subTest(helper_exit=status):
                    result = subprocess.run(
                        [BASH, "--noprofile", "--norc", "-e", "-o", "pipefail", "-c", command],
                        cwd=root, env=dict(os.environ, GITHUB_WORKSPACE=str(root),
                                           TEST_SELECT_EXIT=str(status)),
                        capture_output=True, text=True, timeout=20)
                    self.assertEqual(result.returncode, status, result.stderr)
                    outputs = [normalized_shell_path(line.removeprefix("output: "))
                               for line in result.stdout.splitlines() if line.startswith("output: ")]
                    self.assertEqual(outputs, [normalized_shell_path(root / "nold-evidence/reference-setup")])

    @unittest.skipUnless(BASH, "Bash is required to exercise the package-check gate")
    def test_full_check_requires_both_successful_exit_and_status_ok(self):
        command = step_run(nold_job(), "Check the exact archive")
        with tempfile.TemporaryDirectory(prefix="gtheory-nold-check-") as temporary:
            root = Path(temporary)
            bin_dir = root / "bin"
            bin_dir.mkdir()
            for name, script in {
                "pdflatex": "#!/bin/sh\nexit 0\n",
                "R": ('#!/bin/sh\nmkdir -p Gtheory4LLM.Rcheck\n'
                      'printf "%s\\n" "$TEST_CHECK_STATUS" > Gtheory4LLM.Rcheck/00check.log\n'
                      'exit "$TEST_CHECK_EXIT"\n'),
            }.items():
                executable = bin_dir / name
                executable.write_text(script)
                executable.chmod(0o755)
            env = dict(os.environ, PATH=str(bin_dir) + os.pathsep + os.environ.get("PATH", ""),
                       GITHUB_WORKSPACE=str(root), ARCHIVE=str(root / "candidate.tar.gz"))
            for status, code, accepted in (("Status: OK", 0, True), ("Status: OK", 7, False),
                                          ("Status: 1 ERROR", 0, False),
                                          ("Status: 1 WARNING", 0, False),
                                          ("Status: 1 NOTE", 0, False),
                                          ("check did not finish", 0, False)):
                with self.subTest(status=status, check_exit=code):
                    result = subprocess.run(
                        [BASH, "--noprofile", "--norc", "-e", "-o", "pipefail", "-c", command],
                        cwd=root, env=dict(env, TEST_CHECK_STATUS=status, TEST_CHECK_EXIT=str(code)),
                        capture_output=True, text=True, timeout=20)
                    self.assertEqual(result.returncode == 0, accepted, result.stdout + result.stderr)


@unittest.skipUnless(RSCRIPT, "Rscript is required to exercise installed-test evidence")
class InstalledTestEvidenceTests(unittest.TestCase):
    def run_tests(self, root: Path) -> subprocess.CompletedProcess:
        library = root / "library with spaces"
        return subprocess.run(
            [RSCRIPT, "--vanilla", str(ROOT / ".github/nold/run_tests.R"),
             str(library), str(root / "tests"), str(root / "evidence")],
            cwd=ROOT, capture_output=True, text=True, timeout=60,
            env=dict(os.environ, R_LIBS="must-be-replaced-by-the-runner",
                     GTHEORY_TEST_EXPECTED_R_LIBS=str(library)))

    def failure_details(self, root: Path, result: subprocess.CompletedProcess) -> str:
        sections = ["Runner stdout:\n" + result.stdout, "Runner stderr:\n" + result.stderr]
        for path in sorted((root / "evidence").glob("*.Rout")):
            sections.append(path.name + ":\n" + path.read_text(errors="replace"))
        return "\n".join(sections)

    def test_failed_test_preserves_both_streams_and_remaining_tests_run(self):
        with tempfile.TemporaryDirectory(prefix="gtheory-nold-tests-") as temporary:
            root = Path(temporary)
            (root / "tests").mkdir()
            (root / "library with spaces").mkdir()
            for name, code in (("package-a.R", 0), ("package-b.R", 7), ("package-c.R", 0)):
                (root / "tests" / name).write_text(
                    f'cat("stdout {name}\\n"); message("stderr {name}"); '
                    'stopifnot(identical(Sys.getenv("R_LIBS"), '
                    'Sys.getenv("GTHEORY_TEST_EXPECTED_R_LIBS"))); '
                    f'quit(save = "no", status = {code}, runLast = FALSE)\n')
            result = self.run_tests(root)
            details = self.failure_details(root, result)
            self.assertEqual(result.returncode, 1, details)
            status_file = root / "evidence/test-status.csv"
            self.assertTrue(status_file.is_file(), details)
            with status_file.open(newline="") as stream:
                rows = list(csv.DictReader(stream))
            self.assertEqual([(row["test"], row["exit_code"]) for row in rows],
                             [("package-a.R", "0"), ("package-b.R", "7"), ("package-c.R", "0")],
                             details)
            for name in ("package-a.R", "package-b.R", "package-c.R"):
                output_file = root / "evidence" / (name + "out")
                self.assertTrue(output_file.is_file(), details)
                output = output_file.read_text()
                self.assertIn("stdout " + name, output, details)
                self.assertIn("stderr " + name, output, details)
            self.assertIn("1 of 3 failed", result.stdout, details)

    def test_no_installed_test_files_cannot_pass(self):
        with tempfile.TemporaryDirectory(prefix="gtheory-nold-empty-") as temporary:
            root = Path(temporary)
            (root / "tests").mkdir()
            (root / "library with spaces").mkdir()
            result = self.run_tests(root)
            details = self.failure_details(root, result)
            self.assertNotEqual(result.returncode, 0, details)
            self.assertIn("No package test files were found", result.stdout + result.stderr, details)


if __name__ == "__main__":
    unittest.main()
