"""The CRAN check consumes the exact candidate and rejects incomplete evidence."""
import hashlib
import importlib.util
import contextlib
import io
import json
from pathlib import Path
import sys
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
SPEC = importlib.util.spec_from_file_location("cran_readiness", ROOT / "scripts/cran_readiness.py")
CHECK = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(CHECK)


class CRANReadinessTests(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.root = Path(directory.name)
        self.archive = self.root / "Example_0.0.1.tar.gz"
        self.archive.write_bytes(b"archive fixture; never executed")
        self.commit = "a" * 40
        self.manifest = {"schema_version": 1, "package": "Example", "version": "0.0.1",
                         "archive": self.archive.name, "source_commit": self.commit,
                         "bytes": self.archive.stat().st_size,
                         "sha256": hashlib.sha256(self.archive.read_bytes()).hexdigest()}
        self.save_manifest()

    def save_manifest(self):
        (self.root / "candidate.json").write_text(json.dumps(self.manifest))

    def test_exact_candidate_is_verified_without_modification(self):
        before = {p.name: p.read_bytes() for p in self.root.iterdir()}
        manifest, path = CHECK.candidate_input(self.root, self.commit)
        self.assertEqual(manifest, self.manifest)
        self.assertEqual(path, self.archive)
        self.assertEqual(before, {p.name: p.read_bytes() for p in self.root.iterdir()})

    def test_tampering_wrong_commit_and_path_escape_are_rejected(self):
        with self.assertRaisesRegex(ValueError, "source commit"):
            CHECK.candidate_input(self.root, "b" * 40)
        original = self.archive.read_bytes()
        self.archive.write_bytes(original.replace(b"fixture", b"changed"))
        with self.assertRaisesRegex(ValueError, "SHA-256"):
            CHECK.candidate_input(self.root, self.commit)
        self.archive.write_bytes(original)
        self.manifest["archive"] = "../" + self.archive.name
        self.save_manifest()
        with self.assertRaisesRegex(ValueError, "basename"):
            CHECK.candidate_input(self.root, self.commit)

    def test_missing_or_linked_archive_is_rejected(self):
        actual = self.archive.with_suffix(".original")
        self.archive.rename(actual)
        with self.assertRaisesRegex(ValueError, "regular file"):
            CHECK.candidate_input(self.root, self.commit)
        try:
            self.archive.symlink_to(actual)
        except OSError:
            self.skipTest("This platform does not permit unprivileged symbolic links.")
        with self.assertRaisesRegex(ValueError, "regular file"):
            CHECK.candidate_input(self.root, self.commit)

    def test_success_requires_full_manual_check(self):
        self.assertTrue(CHECK.manual_checked("* checking PDF version of manual ... OK\n"))
        self.assertTrue(CHECK.manual_checked("* checking PDF version of manual ... [2s] OK\n"))
        for log in ("* checking PDF version of manual ... WARNING\n",
                    "* checking PDF version of manual without hyperrefs or index ... OK\n",
                    "* checking Rd files ... OK\n* DONE\nStatus: OK\n"):
            self.assertFalse(CHECK.manual_checked(log))

    def test_check_uses_downloaded_archive_and_never_rebuilds(self):
        self.manifest["expected_data_kind"] = "public_llm_annotations"
        self.save_manifest()
        output = self.root / "checked"
        commands = []

        def fake_run(command, **kwargs):
            commands.append(command)
            if "CMD" in command:
                self.assertEqual(command[1:3], ["CMD", "check"])
                self.assertIn("--as-cran", command)
                self.assertIn("--timings", command)
                self.assertNotIn("--no-manual", command)
                self.assertEqual(Path(command[-1]).read_bytes(), self.archive.read_bytes())
                check = output / "Example.Rcheck"
                check.mkdir()
                (check / "00check.log").write_text("* checking PDF version of manual ... OK\n* checking tests ... OK\n* DONE\nStatus: OK\n")
                stdout = "Check completed\n"
            elif Path(command[-1]).name == "runtime.R":
                self.assertIn("cat(R.home", Path(command[-1]).read_text(encoding="utf-8"))
                self.assertNotIn("-e", command)
                stdout = "/tmp/R-devel/bin\n4.7.0\nUnder development (unstable)\nR Under development\n"
            else:
                stdout = "Test session\n"
            return subprocess.CompletedProcess(command, 0, stdout=stdout, stderr="")

        argv = ["cran_readiness.py", "check", "--require-devel", "--candidate-dir", str(self.root), "--output-dir", str(output)]
        with patch.object(CHECK, "ROOT", self.root / "source"), patch.object(CHECK, "clean_commit", return_value=self.commit), \
                patch.object(CHECK, "PublicAudit") as audit, patch.object(CHECK.subprocess, "run", side_effect=fake_run), \
                patch.object(sys, "argv", argv), contextlib.redirect_stdout(io.StringIO()):
            audit.return_value.findings = []
            audit.return_value.report.return_value = {"passed": True}
            self.assertEqual(CHECK.main(), 0)
        self.assertEqual(sum("CMD" in command for command in commands), 1)
        report = json.loads((output / "check_validation.json").read_text())
        self.assertTrue(report["exact_archive_checked"])
        self.assertTrue(report["r_devel_checked"])
        self.assertTrue(report["pdf_manual_checked"])
        self.assertFalse(report["submission_performed"])
        self.assertEqual(CHECK.digest(output / self.archive.name), self.manifest["sha256"])


class IncomingNoteTests(unittest.TestCase):
    """The candidate check and the source check must classify notes alike.

    They share check_status(), but only if the candidate check passes the
    version. It did not, so a development candidate failed on a note the source
    gate excused: the same log, two verdicts.
    """

    LOG = ("* checking CRAN incoming feasibility ... NOTE\n"
           "Maintainer: 'Example <a@example.invalid>'\n\nNew submission\n\n"
           "Version contains large components (0.1.0.9000)\n"
           "* checking tests ... OK\n* DONE\nStatus: 1 NOTE\n")

    def test_the_candidate_check_passes_the_version_through(self):
        source = (ROOT / "scripts/cran_readiness.py").read_text(encoding="utf-8")
        self.assertIn("version=manifest.get(\"version\")", source,
                      "the candidate check must tell check_status which version it checked")

    def test_both_paths_agree_on_a_development_candidate(self):
        from check_package import check_status
        report = check_status(self.LOG, as_cran=True, version="0.1.0.9000")
        self.assertEqual(len(report["allowed_notes"]), 1)
        with self.assertRaises(RuntimeError):
            check_status(self.LOG, as_cran=True, version="0.1.0")

if __name__ == "__main__":
    unittest.main()
