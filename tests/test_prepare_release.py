"""The release orchestrator must derive every version from DESCRIPTION.

No R process, no TeX, and no network access: the archive and manual builds are
replaced by stand-ins so that what is tested is the orchestration — where the
version comes from, what gets written, what refuses, and above all that nothing
publishes.
"""
from __future__ import annotations

import importlib.util
import io
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch
from contextlib import redirect_stdout

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("prepare_release", ROOT / "scripts/prepare_release.py")
RELEASE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(RELEASE)

DESCRIPTION = """Package: Example
Version: 1.2.3
Title: An Example
Description: A description that continues
    onto a second line.
License: GPL-3
"""

README = """# Example

<!-- release-identity:start -->
Source version: **1.2.3**.
See [manifest](https://example.invalid/artifacts/manifest.json)
and [releases](https://example.invalid/releases).
<!-- release-identity:end -->

More prose.
"""
NEWS = README.replace("# Example", "# Example 1.2.3")


class PrepareReleaseTests(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.root = Path(directory.name)
        self.artifacts = self.root / "artifacts"
        self.artifacts.mkdir()
        (self.root / "DESCRIPTION").write_text(DESCRIPTION, encoding="utf-8")
        (self.root / "README.md").write_text(README, encoding="utf-8")
        (self.root / "NEWS.md").write_text(NEWS, encoding="utf-8")
        (self.artifacts / "README.md").write_text(
            "# Example 0.0.9 release\n\nRelease state: **prepared**, not published.\n",
            encoding="utf-8")
        self.git("init", "-q")
        self.git("add", "-A")
        self.git("commit", "-qm", "initial")
        self.commit = self.git("rev-parse", "HEAD")
        for name, value in (("ROOT", self.root), ("ARTIFACTS", self.artifacts)):
            patcher = patch.object(RELEASE, name, value)
            patcher.start()
            self.addCleanup(patcher.stop)

    def git(self, *arguments):
        return subprocess.check_output(
            ["git", "-C", str(self.root), "-c", "user.name=Test",
             "-c", "user.email=test@example.invalid", *arguments],
            text=True, stderr=subprocess.PIPE).strip()

    def stub_builds(self):
        def archive(package, version, work):
            path = work / f"{package}_{version}.tar.gz"
            path.write_bytes(b"archive bytes")
            return path

        def manual(package, work):
            path = work / f"{package}-manual.pdf"
            path.write_bytes(b"%PDF-1.4\nmanual\n")
            return path

        return (patch.object(RELEASE, "build_archive", archive),
                patch.object(RELEASE, "build_manual", manual))

    def run_main(self, argv):
        archive, manual = self.stub_builds()
        buffer = io.StringIO()
        with archive, manual, redirect_stdout(buffer):
            status = RELEASE.main(argv)
        return status, buffer.getvalue()

    # --- version is read, never written by hand -----------------------------
    def test_every_name_comes_from_description(self):
        with patch.object(RELEASE, "run"):
            status, output = self.run_main(["--skip-validation"])
        self.assertEqual(status, 0)
        manifest = json.loads((self.artifacts / "manifest.json").read_text())
        self.assertEqual(manifest["version"], "1.2.3")
        self.assertEqual(manifest["package"], "Example")
        self.assertEqual(manifest["source_commit"], self.commit)
        self.assertEqual(manifest["release_state"], "prepared")
        self.assertEqual(sorted(manifest["files"]),
                         ["Example-manual.pdf", "Example_1.2.3.tar.gz"])
        self.assertTrue((self.artifacts / "Example_1.2.3.tar.gz").is_file())
        self.assertIn("v1.2.3", output)

    def test_source_prose_is_identical_before_and_after_preparation(self):
        before = {name: (self.root / name).read_bytes() for name in ("README.md", "NEWS.md")}
        with patch.object(RELEASE, "run"):
            self.run_main(["--skip-validation"])
        self.assertEqual(before, {name: (self.root / name).read_bytes() for name in before})
        self.assertEqual((self.artifacts / "README.md").read_text().splitlines()[0],
                         "# Example 1.2.3 release")

    def test_stale_or_mutable_source_summary_is_refused_before_build(self):
        for bad in (README.replace("1.2.3", "0.0.9"), README.replace(
                "Source version: **1.2.3**.", "Release state: **prepared**.")):
            (self.root / "README.md").write_text(bad)
            with patch.object(RELEASE, "build_archive") as build, self.assertRaisesRegex(
                    SystemExit, "publication-neutral Source version|stale unpublished-release prose"):
                RELEASE.main(["--skip-validation", "--allow-dirty"])
            build.assert_not_called()

    def test_neutral_block_cannot_hide_stale_install_or_current_news_prose(self):
        for name in ("README.md", "NEWS.md"):
            path = self.root / name
            original = path.read_text()
            path.write_text(original + "\nUntil the `v1.2.3` release is published, use the bundle.\n")
            with patch.object(RELEASE, "build_archive") as build, self.assertRaisesRegex(
                    SystemExit, "stale unpublished-release prose"):
                RELEASE.main(["--skip-validation", "--allow-dirty"])
            build.assert_not_called()
            path.write_text(original)
        news = self.root / "NEWS.md"
        news.write_text(news.read_text() + "\n# Example 0.0.9\nOnce releases exist, use the archive.\n")
        RELEASE.require_neutral_source_prose("1.2.3")

    def test_published_targets_are_refused_without_modifying_files(self):
        cases = (("--state", "published"), ("tag",), ("manifest",))
        for case in cases:
            with self.subTest(case=case):
                if case == ("tag",):
                    self.git("tag", "v1.2.3")
                if case == ("manifest",):
                    self.git("tag", "-d", "v1.2.3")
                    (self.artifacts / "manifest.json").write_text(json.dumps(
                        {"version": "1.2.3", "release_state": "published"}))
                before = {p: p.read_bytes() for p in self.artifacts.iterdir()}
                args = list(case) if case[0] == "--state" else []
                with patch.object(RELEASE, "build_archive") as build, self.assertRaisesRegex(
                        SystemExit, "published|tagged"):
                    RELEASE.main(["--skip-validation", "--allow-dirty", *args])
                build.assert_not_called()
                self.assertEqual(before, {p: p.read_bytes() for p in self.artifacts.iterdir()})

    def test_a_superseded_archive_is_removed(self):
        stale = self.artifacts / "Example_0.0.9.tar.gz"
        stale.write_bytes(b"old")
        self.git("add", "-A")
        self.git("commit", "-qm", "previous bundle")
        self.commit = self.git("rev-parse", "HEAD")
        with patch.object(RELEASE, "run"):
            self.run_main(["--skip-validation"])
        self.assertFalse(stale.exists(), "the previous archive must not linger next to the new one")
        self.assertTrue((self.artifacts / "Example_1.2.3.tar.gz").is_file())

    def test_checksums_describe_the_files_that_were_written(self):
        import hashlib
        with patch.object(RELEASE, "run"):
            self.run_main(["--skip-validation"])
        manifest = json.loads((self.artifacts / "manifest.json").read_text())
        for name, recorded in manifest["files"].items():
            path = self.artifacts / name
            self.assertEqual(recorded["bytes"], path.stat().st_size)
            self.assertEqual(recorded["sha256"], hashlib.sha256(path.read_bytes()).hexdigest())

    # --- refusals ------------------------------------------------------------
    def test_a_dirty_tree_is_refused_unless_rehearsing(self):
        (self.root / "README.md").write_text(README + "uncommitted\n", encoding="utf-8")
        with patch.object(RELEASE, "run"), self.assertRaises(SystemExit) as raised:
            self.run_main(["--skip-validation"])
        self.assertIn("uncommitted changes", str(raised.exception))
        with patch.object(RELEASE, "run"):
            status, output = self.run_main(["--skip-validation", "--allow-dirty"])
        self.assertEqual(status, 0)
        self.assertIn("must not be published", output)
        self.assertEqual(self.git("tag", "-l"), "", "a rehearsal still tags nothing")

    def test_a_development_version_cannot_bundle_itself(self):
        (self.root / "DESCRIPTION").write_text(
            DESCRIPTION.replace("Version: 1.2.3", "Version: 1.2.3.9000"), encoding="utf-8")
        self.git("commit", "-qam", "development")
        with patch.object(RELEASE, "run"), self.assertRaises(SystemExit) as raised:
            self.run_main(["--skip-validation"])
        self.assertIn("development version", str(raised.exception))

    def test_a_failing_step_stops_before_anything_is_published(self):
        def failing(step, command, cwd=None):
            raise SystemExit(f"{step} failed (exit 1); nothing was published")
        with patch.object(RELEASE, "run", failing), self.assertRaises(SystemExit) as raised:
            self.run_main([])
        self.assertIn("nothing was published", str(raised.exception))

    # --- nothing publishes ---------------------------------------------------
    def test_nothing_is_tagged_pushed_or_uploaded(self):
        with patch.object(RELEASE, "run"):
            status, output = self.run_main(["--skip-validation"])
        self.assertEqual(status, 0)
        self.assertEqual(self.git("tag", "-l"), "", "preparing a release must not create a tag")
        self.assertIn("Prepared, not published", output)
        self.assertIn("git tag v1.2.3", output)
        source = (ROOT / "scripts/prepare_release.py").read_text()
        for forbidden in ("git\", \"push", "gh release", "devtools::submit"):
            self.assertNotIn(forbidden, source,
                             "the orchestrator must not contain a publishing step")

    def test_a_dry_run_changes_no_tracked_file(self):
        scratch = tempfile.TemporaryDirectory()
        self.addCleanup(scratch.cleanup)
        target = Path(scratch.name) / "rehearsal"
        before = {path: path.read_text() for path in
                  (self.root / "README.md", self.root / "NEWS.md", self.artifacts / "README.md")}
        with patch.object(RELEASE, "run"):
            status, output = self.run_main(["--skip-validation", "--dry-run", str(target)])
        self.assertEqual(status, 0)
        self.assertIn("Dry run", output)
        for path, text in before.items():
            self.assertEqual(path.read_text(), text, f"{path.name} must be untouched by a dry run")
        self.assertFalse((self.artifacts / "manifest.json").exists())
        self.assertTrue((target / "manifest.json").is_file())
        self.assertEqual(json.loads((target / "manifest.json").read_text())["version"], "1.2.3")

    def test_dry_run_rejects_checkout_destinations(self):
        for target in (self.root, self.artifacts):
            with self.assertRaisesRegex(SystemExit, "outside the checkout"):
                self.run_main(["--skip-validation", "--dry-run", str(target)])

    def test_failed_verification_preserves_previous_bundle(self):
        previous = self.artifacts / "Example_0.0.9.tar.gz"
        previous.write_bytes(b"previous bundle")
        self.git("add", "-A")
        self.git("commit", "-qm", "previous")
        def fail(*args, **kwargs):
            raise SystemExit("verification failed")
        with patch.object(RELEASE, "run", fail), self.assertRaisesRegex(SystemExit, "verification failed"):
            self.run_main(["--skip-validation"])
        self.assertEqual(previous.read_bytes(), b"previous bundle")
        self.assertFalse((self.artifacts / "Example_1.2.3.tar.gz").exists())

    # --- the checked candidate can be adopted, never rebuilt ------------------
    def candidate_directory(self, report=None, **overrides):
        import hashlib
        directory = Path(tempfile.mkdtemp())
        self.addCleanup(lambda: __import__("shutil").rmtree(directory, ignore_errors=True))
        archive = directory / "Example_1.2.3.tar.gz"
        archive.write_bytes(b"checked archive bytes")
        manifest = {"schema_version": 1, "package": "Example", "version": "1.2.3",
                    "source_commit": self.commit, "archive": archive.name,
                    "sha256": hashlib.sha256(archive.read_bytes()).hexdigest(),
                    "bytes": archive.stat().st_size, "build_r_version": "4.6.1",
                    "expected_data_kind": "public_llm_annotations"}
        manifest.update(overrides)
        (directory / "candidate.json").write_text(json.dumps(manifest), encoding="utf-8")
        if report is None:
            report = {"success": True, "r_devel_checked": True, "exact_archive_checked": True,
                      "pdf_manual_checked": True, "r_version": "4.7.0",
                      "r_cmd_check": {"errors": 0, "warnings": 0, "notes": 1},
                      "candidate": {"sha256": manifest["sha256"]}}
        if report is not False:
            (directory / "check_validation.json").write_text(json.dumps(report), encoding="utf-8")
        return directory

    def test_a_checked_candidate_is_adopted_unchanged(self):
        directory = self.candidate_directory()
        archive, manual = self.stub_builds()
        buffer = io.StringIO()
        with patch.object(RELEASE, "run"), patch.object(RELEASE, "build_archive") as build, manual, \
                redirect_stdout(buffer):
            status = RELEASE.main(["--skip-validation", "--from-checked-candidate", str(directory)])
        self.assertEqual(status, 0)
        build.assert_not_called()
        self.assertEqual((self.artifacts / "Example_1.2.3.tar.gz").read_bytes(), b"checked archive bytes")
        manifest = json.loads((self.artifacts / "manifest.json").read_text())
        self.assertEqual(manifest["source_commit"], self.commit)
        self.assertEqual(manifest["archive_provenance"]["origin"], "checked_candidate")
        self.assertEqual(manifest["archive_provenance"]["build_r_version"], "4.6.1")
        self.assertEqual(manifest["archive_provenance"]["checked_r_version"], "4.7.0")
        self.assertEqual(manifest["files"]["Example_1.2.3.tar.gz"]["sha256"],
                         json.loads((directory / "candidate.json").read_text())["sha256"])
        self.assertIn("Adopt the checked candidate archive unchanged", buffer.getvalue())
        del archive

    def test_a_candidate_from_another_commit_or_with_other_bytes_is_refused(self):
        cases = {"different source commit": {"source_commit": "0" * 40},
                 "SHA-256": {"sha256": "0" * 64},
                 "not this package version": {"version": "1.2.4", "archive": "Example_1.2.4.tar.gz"}}
        for expected, overrides in cases.items():
            with self.subTest(case=expected):
                directory = self.candidate_directory(**overrides)
                before = {p: p.read_bytes() for p in self.artifacts.iterdir()}
                with patch.object(RELEASE, "run"), patch.object(RELEASE, "build_archive") as build, \
                        self.assertRaisesRegex(SystemExit, expected):
                    RELEASE.main(["--skip-validation", "--from-checked-candidate", str(directory)])
                build.assert_not_called()
                self.assertEqual(before, {p: p.read_bytes() for p in self.artifacts.iterdir()})

    def test_a_candidate_without_a_successful_check_report_is_refused(self):
        passing = {"success": True, "r_devel_checked": True, "exact_archive_checked": True,
                   "pdf_manual_checked": True, "r_version": "4.7.0",
                   "r_cmd_check": {"errors": 0, "warnings": 0, "notes": 1}}
        cases = {"no check_validation.json": False,
                 "does not record a successful": {**passing, "success": False},
                 "zero errors and warnings": {**passing, "r_cmd_check": {"errors": 1, "warnings": 0}},
                 "R-devel": {**passing, "r_devel_checked": False},
                 "different archive": {**passing, "candidate": {"sha256": "0" * 64}}}
        for expected, report in cases.items():
            with self.subTest(case=expected):
                if isinstance(report, dict) and "candidate" not in report:
                    directory = self.candidate_directory(report=report)
                    manifest = json.loads((directory / "candidate.json").read_text())
                    report["candidate"] = {"sha256": manifest["sha256"]}
                    (directory / "check_validation.json").write_text(json.dumps(report), encoding="utf-8")
                else:
                    directory = self.candidate_directory(report=report)
                before = {p: p.read_bytes() for p in self.artifacts.iterdir()}
                with patch.object(RELEASE, "run"), patch.object(RELEASE, "build_archive") as build, \
                        self.assertRaisesRegex(SystemExit, expected):
                    RELEASE.main(["--skip-validation", "--from-checked-candidate", str(directory)])
                build.assert_not_called()
                self.assertEqual(before, {p: p.read_bytes() for p in self.artifacts.iterdir()})

    def test_a_locally_built_archive_records_its_origin(self):
        with patch.object(RELEASE, "run"):
            self.run_main(["--skip-validation"])
        manifest = json.loads((self.artifacts / "manifest.json").read_text())
        self.assertEqual(manifest["archive_provenance"], {"origin": "built_here"})

    # --- validation is run unless explicitly skipped --------------------------
    def test_source_validation_runs_by_default(self):
        with patch.object(RELEASE, "run") as runner:
            self.run_main([])
        steps = [call.args[0] for call in runner.call_args_list]
        self.assertIn("Validate public sources", steps)
        # Preparing a bundle writes files, so start the second run from a clean
        # tree rather than from the first run's output.
        self.git("add", "-A")
        self.git("commit", "-qm", "prepared bundle")
        with patch.object(RELEASE, "run") as runner:
            self.run_main(["--skip-validation"])
        self.assertNotIn("Validate public sources", [call.args[0] for call in runner.call_args_list])

    def test_the_bundle_is_verified_after_it_is_written(self):
        with patch.object(RELEASE, "run") as runner:
            self.run_main(["--skip-validation"])
        steps = [call.args[0] for call in runner.call_args_list]
        self.assertIn("Verify the bundle against its source commit and the release identity", steps)
        self.assertIn("Audit public content", steps)


class DescriptionFieldTests(unittest.TestCase):
    def test_continuation_lines_are_folded(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "DESCRIPTION").write_text(DESCRIPTION, encoding="utf-8")
            with patch.object(RELEASE, "ROOT", root):
                self.assertEqual(RELEASE.description_field("Version"), "1.2.3")
                self.assertEqual(RELEASE.description_field("Description"),
                                 "A description that continues onto a second line.")
                with self.assertRaises(SystemExit):
                    RELEASE.description_field("Absent")

    def test_the_real_description_is_the_only_version_source(self):
        source = (ROOT / "scripts/prepare_release.py").read_text()
        version = RELEASE.description_field("Version")
        self.assertNotIn(version, source,
                         "the released version must not appear literally in the orchestrator")


if __name__ == "__main__":
    unittest.main()
