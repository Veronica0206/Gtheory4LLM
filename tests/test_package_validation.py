"""Package check notes are classified narrowly and reports omit local paths."""
import importlib.util
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("package_validation", ROOT / "scripts/check_package.py")
CHECK = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(CHECK)


class PackageValidationTests(unittest.TestCase):
    def test_only_explicit_new_submission_note_is_expected_in_as_cran_mode(self):
        log = "* checking CRAN incoming feasibility ... NOTE\nMaintainer: 'Example <a@example.invalid>'\n\nNew submission\n* checking package namespace information ... OK\n* DONE\nStatus: 1 NOTE\n"
        report = CHECK.check_status(log, as_cran=True)
        self.assertEqual(report["notes"], 1)
        self.assertEqual(report["allowed_notes"], ["CRAN incoming feasibility: New submission"])
        with self.assertRaisesRegex(RuntimeError, "substantive NOTE"):
            CHECK.check_status(log, as_cran=False)
        with self.assertRaisesRegex(RuntimeError, "substantive NOTE"):
            CHECK.check_status(log.replace("New submission", "New submission\nInvalid URL"), as_cran=True)

    def test_missing_vignette_index_is_excused_only_when_vignettes_were_skipped(self):
        # An archive built without vignettes carries no vignette index and
        # --as-cran says so. That extra line is expected there and nowhere else:
        # in a run that did build vignettes it means the index is really absent.
        log = ("* checking CRAN incoming feasibility ... NOTE\n"
               "Maintainer: 'Example <a@example.invalid>'\n\nNew submission\n\n"
               "Package has a VignetteBuilder field but no prebuilt vignette index.\n"
               "* checking package namespace information ... OK\n* DONE\nStatus: 1 NOTE\n")
        report = CHECK.check_status(log, as_cran=True, vignettes_built=False)
        self.assertEqual(report["allowed_notes"], ["CRAN incoming feasibility: New submission"])
        with self.assertRaises(RuntimeError):
            CHECK.check_status(log, as_cran=True, vignettes_built=True)
        # The exemption removes exactly that line and nothing else.
        with_extra = log.replace("* checking package namespace information",
                                 "Unexpected additional finding.\n* checking package namespace information")
        with self.assertRaises(RuntimeError):
            CHECK.check_status(with_extra, as_cran=True, vignettes_built=False)

    def test_a_development_version_note_is_excused_only_for_a_development_version(self):
        # CRAN flags a .9000 fourth component, correctly: such a checkout is not
        # a submission candidate. The excuse is keyed to the exact version, so a
        # release candidate cannot inherit it.
        log = ("* checking CRAN incoming feasibility ... NOTE\n"
               "Maintainer: 'Example <a@example.invalid>'\n\nNew submission\n\n"
               "Version contains large components (0.1.0.9000)\n"
               "* checking package namespace information ... OK\n* DONE\nStatus: 1 NOTE\n")
        report = CHECK.check_status(log, as_cran=True, version="0.1.0.9000")
        self.assertEqual(len(report["allowed_notes"]), 1)
        self.assertIn("development version 0.1.0.9000", report["allowed_notes"][0])
        # Not a development version: the note stands and the check fails.
        with self.assertRaisesRegex(RuntimeError, "substantive NOTE"):
            CHECK.check_status(log, as_cran=True, version="0.1.0")
        with self.assertRaisesRegex(RuntimeError, "substantive NOTE"):
            CHECK.check_status(log, as_cran=True)
        # A different version in the line is not this version's excuse.
        with self.assertRaisesRegex(RuntimeError, "substantive NOTE"):
            CHECK.check_status(log.replace("(0.1.0.9000)", "(0.2.0.9000)"),
                               as_cran=True, version="0.1.0.9000")
        # The excuse removes exactly that line and nothing else.
        with_extra = log.replace("* checking package namespace information",
                                 "Invalid URL found.\n* checking package namespace information")
        with self.assertRaises(RuntimeError):
            CHECK.check_status(with_extra, as_cran=True, version="0.1.0.9000")

    def test_a_release_version_never_matches_the_development_pattern(self):
        for version in ("0.1.0", "1.0", "0.1.0.1", "0.1.0.900", "0.1.09000"):
            with self.subTest(version=version):
                self.assertIsNone(CHECK.DEVELOPMENT_VERSION.fullmatch(version))
        for version in ("0.1.0.9000", "1.2.3.9001", "0.1.0.90000"):
            with self.subTest(version=version):
                self.assertIsNotNone(CHECK.DEVELOPMENT_VERSION.fullmatch(version))

    def test_toolchain_probe_reports_what_is_missing(self):
        import subprocess
        from unittest.mock import patch
        completed = subprocess.CompletedProcess([], 0, stdout="knitr\n", stderr="")
        with patch.object(CHECK.subprocess, "run", return_value=completed):
            found = CHECK.vignette_toolchain("Rscript", {})
        self.assertFalse(found["available"])
        self.assertEqual(found["present"], ["knitr"])
        self.assertIn("rmarkdown", found["reason"])
        full = subprocess.CompletedProcess([], 0, stdout="knitr,rmarkdown,pandoc", stderr="")
        with patch.object(CHECK.subprocess, "run", return_value=full):
            found = CHECK.vignette_toolchain("Rscript", {})
        self.assertTrue(found["available"])
        self.assertEqual(found["reason"], "")

    def test_substantive_notes_warnings_and_incomplete_checks_fail(self):
        for log in (
            "* checking R code ... NOTE\nUnused import\n* DONE\nStatus: 1 NOTE\n",
            "* checking dependencies ... WARNING\nMissing dependency\n* DONE\nStatus: 1 WARNING\n",
            "* checking dependencies ... ERROR\nMissing dependency\n* DONE\nStatus: 1 ERROR\n",
            "* checking dependencies ... OK\n",
        ):
            with self.subTest(log=log), self.assertRaises(RuntimeError):
                CHECK.check_status(log, as_cran=True)

    def test_clean_complete_check_and_portable_summary(self):
        self.assertEqual(CHECK.check_status("* checking tests ... OK\n* DONE\nStatus: OK\n")["notes"], 0)
        with tempfile.TemporaryDirectory() as path:
            work = Path(path)
            report = CHECK.sanitize({"source": str(ROOT / "DESCRIPTION"), "workspace": str(work), "nested": [str(Path.home() / "local-file")]}, work)
        text = str(report)
        self.assertNotIn(str(ROOT), text)
        self.assertNotIn(str(work), text)
        self.assertNotIn(str(Path.home()), text)
        self.assertEqual(report["workspace"], "<validation>")


if __name__ == "__main__":
    unittest.main()
