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
