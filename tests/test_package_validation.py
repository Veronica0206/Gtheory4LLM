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
    MAINTENANCE_REASON = "CRAN requested correction of the 0.2.0 noLD ERROR before 2026-10-26"

    @staticmethod
    def maintenance_log(days="1"):
        return ("* checking CRAN incoming feasibility ... NOTE\n"
                "Maintainer: 'Example <a@example.invalid>'\n\n"
                f"Days since last update: {days}\n"
                "* checking tests ... OK\n* DONE\nStatus: 1 NOTE\n")

    def test_maintenance_timing_note_requires_explicit_request_and_retains_disposition(self):
        log = self.maintenance_log()
        with self.assertRaisesRegex(RuntimeError, "substantive NOTE"):
            CHECK.check_status(log, as_cran=True, version="0.4.0")
        for days in ("0", "1", "27"):
            with self.subTest(days=days):
                report = CHECK.check_status(self.maintenance_log(days), as_cran=True, version="0.4.0",
                    cran_requested_maintenance=self.MAINTENANCE_REASON)
                self.assertEqual((report["errors"], report["warnings"], report["notes"]), (0, 0, 1))
                self.assertEqual(report["note_exceptions"], [{"policy": "cran_requested_maintenance",
                    "reason": self.MAINTENANCE_REASON, "check": "CRAN incoming feasibility",
                    "message": f"Days since last update: {days}", "days_since_last_update": int(days)}])
                self.assertIn(f"Days since last update: {days}", report["allowed_notes"][0])

    def test_maintenance_policy_requires_release_cran_context_and_nonempty_reason(self):
        for version, as_cran in ((None, True), ("0.4.0.9000", True), ("0.4.0", False), ("NA", True)):
            with self.subTest(version=version, as_cran=as_cran), self.assertRaisesRegex(RuntimeError, "non-development release"):
                CHECK.check_status(self.maintenance_log(), as_cran=as_cran, version=version,
                    cran_requested_maintenance=self.MAINTENANCE_REASON)
        for reason in ("", "  ", "request\nsecond line", 1, True):
            with self.subTest(reason=reason), self.assertRaises(CHECK.argparse.ArgumentTypeError):
                CHECK.check_status(self.maintenance_log(), as_cran=True, version="0.4.0",
                    cran_requested_maintenance=reason)

    def test_maintenance_allowance_rejects_other_or_duplicate_incoming_content(self):
        log = self.maintenance_log()
        invalid = [self.maintenance_log(days) for days in ("NA", "", "-1", "+1", "0.5", "１", "1 trailing")]
        invalid += [log.replace("CRAN incoming feasibility", "package metadata"),
                    log.replace("Maintainer: 'Example <a@example.invalid>'\n", ""),
                    log.replace("Days since last update: 1", "New submission")]
        for line in ("Days since last update: 1", "Days since last update: 2", "New submission",
                     "Version contains large components (0.4.0.9000)", "Invalid URL", CHECK.NO_VIGNETTE_INDEX_NOTE):
            invalid.append(log.replace("* checking tests", line + "\n* checking tests"))
        block = log.split("* checking tests")[0]
        invalid.append((block + log).replace("Status: 1 NOTE", "Status: 2 NOTEs"))
        for broken in invalid:
            with self.subTest(log=broken), self.assertRaisesRegex(RuntimeError, "substantive NOTE"):
                CHECK.check_status(broken, as_cran=True, version="0.4.0", vignettes_built=False,
                    cran_requested_maintenance=self.MAINTENANCE_REASON)

    def test_maintenance_allowance_preserves_completion_and_summary_gates(self):
        log = self.maintenance_log()
        for broken in (log.replace("* DONE", ""), log.replace("* DONE", "* DONE\n* DONE"),
                       log.replace("Status: 1 NOTE", "Status: OK"),
                       log.replace("Status: 1 NOTE", "Status: 2 NOTEs"),
                       log.replace("Status: 1 NOTE", "Status: NA"),
                       log.replace("Status: 1 NOTE", ""),
                       log + "Status: 1 NOTE\n",
                       log.replace("* checking tests ... OK", "* checking tests ... ERROR"),
                       log.replace("* checking tests ... OK", "* checking tests ... WARNING")):
            with self.subTest(log=broken), self.assertRaises(RuntimeError):
                CHECK.check_status(broken, as_cran=True, version="0.4.0",
                    cran_requested_maintenance=self.MAINTENANCE_REASON)

    def test_maintenance_request_does_not_invent_a_note_when_check_is_clean(self):
        report = CHECK.check_status("* checking tests ... OK\n* DONE\nStatus: OK\n",
            as_cran=True, version="0.4.0", cran_requested_maintenance=self.MAINTENANCE_REASON)
        self.assertEqual(report["notes"], 0)
        self.assertEqual(report["note_exceptions"], [])

    @staticmethod
    def development_update_log(days="0"):
        return ("* checking CRAN incoming feasibility ... [5s/20s] NOTE\n"
                "Maintainer: 'Example <a@example.invalid>'\n\n"
                "Version contains large components (0.3.0.9000)\n\n"
                f"Days since last update: {days}\n"
                "* checking tests ... OK\n* DONE\nStatus: 1 NOTE\n")

    def test_known_development_package_reports_actual_incoming_messages(self):
        for days in ("0", "1", "27"):
            with self.subTest(days=days):
                report = CHECK.check_status(self.development_update_log(days),
                                            as_cran=True, version="0.3.0.9000")
                self.assertEqual(report["notes"], 1)
                self.assertEqual(len(report["allowed_notes"]), 1)
                self.assertIn("Version contains large components (0.3.0.9000)",
                              report["allowed_notes"][0])
                self.assertIn(f"Days since last update: {days}", report["allowed_notes"][0])
                self.assertNotIn("New submission", report["allowed_notes"][0])

    def test_update_cadence_requires_exact_development_version_context(self):
        log = self.development_update_log()
        for version in (None, "0.3.0", "0.3.0.9001"):
            with self.subTest(version=version), self.assertRaisesRegex(RuntimeError, "substantive NOTE"):
                CHECK.check_status(log, as_cran=True, version=version)
        invalid_logs = (
            log.replace("CRAN incoming feasibility", "package metadata"),
            log.replace("Maintainer: 'Example <a@example.invalid>'\n", ""),
            log.replace("Maintainer: 'Example <a@example.invalid>'", "Maintainer:"),
            log.replace("Version contains large components (0.3.0.9000)\n", ""),
            log.replace("Version contains large components (0.3.0.9000)", "New submission"),
            log.replace("Days since last update: 0", "Days since last update: 0\nInvalid URL"),
        )
        for invalid in invalid_logs:
            with self.subTest(log=invalid), self.assertRaisesRegex(RuntimeError, "substantive NOTE"):
                CHECK.check_status(invalid, as_cran=True, version="0.3.0.9000")
        with self.assertRaisesRegex(RuntimeError, "substantive NOTE"):
            CHECK.check_status(log, as_cran=False, version="0.3.0.9000")

    def test_development_metadata_rejects_malformed_or_duplicate_lines(self):
        for days in ("-1", "+1", "0.5", "0 trailing", "", "０"):
            with self.subTest(days=days), self.assertRaisesRegex(RuntimeError, "substantive NOTE"):
                CHECK.check_status(self.development_update_log(days),
                                   as_cran=True, version="0.3.0.9000")
        log = self.development_update_log()
        for line in ("Version contains large components (0.3.0.9000)",
                     "Days since last update: 0", "Days since last update: 1",
                     "New submission\nNew submission"):
            duplicate = log.replace("* checking tests", line + "\n* checking tests")
            with self.subTest(line=line), self.assertRaisesRegex(RuntimeError, "substantive NOTE"):
                CHECK.check_status(duplicate, as_cran=True, version="0.3.0.9000")

    def test_development_metadata_preserves_vignette_and_completion_gates(self):
        log = self.development_update_log()
        skipped = log.replace("* checking tests", CHECK.NO_VIGNETTE_INDEX_NOTE + "\n* checking tests")
        CHECK.check_status(skipped, as_cran=True, version="0.3.0.9000", vignettes_built=False)
        with self.assertRaisesRegex(RuntimeError, "substantive NOTE"):
            CHECK.check_status(skipped, as_cran=True, version="0.3.0.9000", vignettes_built=True)
        for invalid in (log.replace("* DONE", ""),
                        log.replace("* checking tests ... OK", "* checking tests ... WARNING"),
                        log.replace("* checking tests ... OK", "* checking tests ... ERROR")):
            with self.subTest(log=invalid), self.assertRaises(RuntimeError):
                CHECK.check_status(invalid, as_cran=True, version="0.3.0.9000")

    def test_only_explicit_new_submission_note_is_expected_in_as_cran_mode(self):
        log = "* checking CRAN incoming feasibility ... NOTE\nMaintainer: 'Example <a@example.invalid>'\n\nNew submission\n* checking package namespace information ... OK\n* DONE\nStatus: 1 NOTE\n"
        report = CHECK.check_status(log, as_cran=True)
        self.assertEqual(report["notes"], 1)
        self.assertEqual(report["allowed_notes"], ["CRAN incoming feasibility: New submission"])
        self.assertEqual(CHECK.check_status(log, as_cran=True, version="0.3.0.9000")["allowed_notes"],
                         ["CRAN incoming feasibility: New submission"])
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
