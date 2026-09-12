"""Release-bundle integrity failures are detected before archived code is run."""
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import subprocess
import tarfile
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("committed_artifact", ROOT / "scripts/check_committed_artifact.py")
CHECK = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(CHECK)


class CommittedArtifactTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.git("init", "-q")
        self.source = {
            ".Rbuildignore": b"^tests/test_.*$\n^artifacts$\n",
            "DESCRIPTION": b"Package: Example\nVersion: 0.0.1\nTitle: Example Package\n",
            "NAMESPACE": b"export(example)\n",
            "R/example.R": b"example <- function() 1\n",
            "inst/extdata/example.txt": b"Original data\n",
            "tests/package-smoke.R": b"stopifnot(Example::example() == 1)\n",
            "tests/test_development.R": b"# omitted from package\n",
        }
        for name, content in self.source.items():
            path = self.root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(content)
        self.git("add", ".")
        self.git("commit", "-qm", "source")
        self.commit = self.git("rev-parse", "HEAD").decode().strip()
        self.artifacts = self.root / "artifacts"
        self.artifacts.mkdir()
        self.archive = self.artifacts / "Example_0.0.1.tar.gz"
        self.manual = self.artifacts / "Example-manual.pdf"
        self.manual.write_bytes(b"%PDF-1.4\nfixture\n%%EOF\n")
        self.members = {name: content for name, content in self.source.items()
                        if name != ".Rbuildignore" and not name.startswith("tests/test_")}
        self.members["DESCRIPTION"] += b"NeedsCompilation: no\nPackaged: generated timestamp\n"
        self.members["build/partial.rdb"] = b"build-generated database"
        self.write_archive()
        self.write_manifest()
        self.git("add", ".")
        self.git("commit", "-qm", "release bundle")

    def git(self, *args):
        return subprocess.check_output(["git", "-C", str(self.root), "-c", "user.name=Test",
                                        "-c", "user.email=test@example.invalid", *args], stderr=subprocess.PIPE)

    def write_archive(self, extras=()):
        with tarfile.open(self.archive, "w:gz") as archive:
            for name, content in self.members.items():
                info = tarfile.TarInfo("Example/" + name)
                info.size = len(content)
                archive.addfile(info, io.BytesIO(content))
            for info, content in extras:
                archive.addfile(info, io.BytesIO(content) if content is not None else None)

    def write_manifest(self):
        self.manifest = self.artifacts / "manifest.json"
        content = {"package": "Example", "version": "0.0.1", "source_commit": self.commit,
                   "files": {path.name: {"bytes": path.stat().st_size,
                             "sha256": hashlib.sha256(path.read_bytes()).hexdigest()}
                             for path in [self.archive, self.manual]}}
        self.manifest.write_text(json.dumps(content))

    def verify(self):
        return CHECK.verify_bundle(self.root, self.manifest)

    def test_source_ancestor_and_later_source_only_commit_are_supported(self):
        report, files = self.verify()
        self.assertEqual(report["source_commit"], self.commit)
        self.assertIn("inst/extdata/example.txt", report["source_files_compared"])
        self.assertEqual(files["tests/package-smoke.R"], self.members["tests/package-smoke.R"])
        (self.root / "R/example.R").write_text("example <- function() 2\n")
        self.git("add", "R/example.R")
        self.git("commit", "-qm", "next source revision")
        self.assertEqual(self.verify()[0]["version"], "0.0.1")

    def test_checksum_and_size_fail_before_archive_or_code_execution(self):
        self.manual.write_bytes(self.manual.read_bytes() + b"x")
        with self.assertRaisesRegex(ValueError, "size mismatch"):
            self.verify()
        self.manual.write_bytes(b"%PDF-1.4\nchanged\n%%EOF\n")
        self.write_manifest()
        self.manual.write_bytes(self.manual.read_bytes().replace(b"changed", b"CHANGED"))
        with self.assertRaisesRegex(ValueError, "checksum mismatch"):
            self.verify()

    def test_updated_checksum_cannot_hide_changed_source_or_resource(self):
        for name in ("R/example.R", "inst/extdata/example.txt"):
            with self.subTest(name=name):
                original = self.members[name]
                self.members[name] = b"changed content\n"
                self.write_archive()
                self.write_manifest()
                with self.assertRaisesRegex(ValueError, "content differs from declared source"):
                    self.verify()
                self.members[name] = original

    def test_missing_or_extra_source_file_is_rejected(self):
        original = self.members.pop("R/example.R")
        self.write_archive()
        self.write_manifest()
        with self.assertRaisesRegex(ValueError, "inventory differs"):
            self.verify()
        self.members["R/example.R"] = original
        self.members["R/untracked.R"] = b"unexpected <- TRUE\n"
        self.write_archive()
        self.write_manifest()
        with self.assertRaisesRegex(ValueError, "inventory differs"):
            self.verify()

    def test_metadata_must_match_manifest_and_source_commit(self):
        self.members["DESCRIPTION"] = self.members["DESCRIPTION"].replace(b"Version: 0.0.1", b"Version: 0.0.2")
        self.write_archive()
        self.write_manifest()
        with self.assertRaisesRegex(ValueError, "package/version differs"):
            self.verify()
        self.members["DESCRIPTION"] = self.members["DESCRIPTION"].replace(b"Version: 0.0.2", b"Version: 0.0.1").replace(b"Title: Example Package", b"Title: Different Package")
        self.write_archive()
        self.write_manifest()
        with self.assertRaisesRegex(ValueError, "source metadata"):
            self.verify()

    def test_unsafe_paths_duplicates_and_links_are_rejected(self):
        for name, kind in (("../escape", tarfile.REGTYPE), ("/absolute", tarfile.REGTYPE),
                           ("Other/file", tarfile.REGTYPE), ("Example/../escape", tarfile.REGTYPE),
                           ("Example/./file", tarfile.REGTYPE), ("Example/a\\b", tarfile.REGTYPE),
                           ("Example/R/example.R", tarfile.REGTYPE),
                           ("Example/symlink", tarfile.SYMTYPE), ("Example/hardlink", tarfile.LNKTYPE)):
            with self.subTest(name=name):
                info = tarfile.TarInfo(name)
                info.type = kind
                info.linkname = "../../escape" if kind != tarfile.REGTYPE else ""
                self.write_archive([(info, b"" if kind == tarfile.REGTYPE else None)])
                self.write_manifest()
                with self.assertRaises(ValueError):
                    self.verify()
        self.assertFalse((self.root / "escape").exists())

    def test_oversized_member_is_rejected(self):
        with patch.object(CHECK, "MAX_FILE_BYTES", 5):
            with self.assertRaisesRegex(ValueError, "size limit"):
                self.verify()

    def test_source_commit_must_be_in_head_history(self):
        tree = self.git("rev-parse", self.commit + "^{tree}").decode().strip()
        unrelated = self.git("commit-tree", tree, "-m", "unrelated root").decode().strip()
        content = json.loads(self.manifest.read_text())
        content["source_commit"] = unrelated
        self.manifest.write_text(json.dumps(content))
        with self.assertRaisesRegex(ValueError, "not an ancestor"):
            self.verify()

    def test_install_uses_archive_and_smoke_from_that_archive_in_fresh_library(self):
        report, files = self.verify()
        work = self.root / "check"
        work.mkdir()
        environment = {"R_LIBS_USER": "/restored/dependencies"}
        with patch.object(CHECK.subprocess, "check_output", return_value="/selected/R"), \
             patch.object(CHECK.subprocess, "run") as run:
            run.return_value = subprocess.CompletedProcess([], 0, "passed\n", "")
            CHECK.install_and_smoke(report, files, work, "SelectedRscript", environment)
        install, smoke = run.call_args_list
        self.assertEqual(install.args[0], ["/selected/R", "CMD", "INSTALL", "--library=" + str(work / "library"), str(self.archive)])
        self.assertEqual(smoke.args[0][:2], ["SelectedRscript", "--vanilla"])
        wrapper = Path(smoke.args[0][2])
        self.assertNotIn("-e", smoke.args[0])
        self.assertIn("find.package", wrapper.read_text(encoding="utf-8"))
        self.assertIn("getNamespaceInfo", wrapper.read_text(encoding="utf-8"))
        self.assertIn('source_provenance$data_kind, "public_llm_annotations"', wrapper.read_text(encoding="utf-8"))
        self.assertNotIn('source_provenance$data_kind, "synthetic"', wrapper.read_text(encoding="utf-8"))
        self.assertEqual((work / "package-smoke.R").read_bytes(), files["tests/package-smoke.R"])
        self.assertEqual(smoke.kwargs["cwd"], work)
        self.assertEqual(smoke.kwargs["env"], environment)
        self.assertTrue(report["archived_smoke_test_run"])
        self.assertTrue((work / "archived_smoke.log").is_file())
        with self.assertRaises(FileExistsError):
            CHECK.install_and_smoke(report, files, work, "SelectedRscript", environment)

    def test_install_failure_is_logged_and_never_runs_smoke(self):
        report, files = self.verify()
        work = self.root / "failed-check"
        work.mkdir()
        with patch.object(CHECK.subprocess, "check_output", return_value="/selected/R"), \
             patch.object(CHECK.subprocess, "run") as run:
            run.return_value = subprocess.CompletedProcess([], 1, "", "install failed\n")
            with self.assertRaisesRegex(RuntimeError, "install failed"):
                CHECK.install_and_smoke(report, files, work, "Rscript", {})
        self.assertEqual(run.call_count, 1)
        self.assertIn("install failed", (work / "install.log").read_text())
        self.assertNotIn("archived_smoke_test_run", report)

    def test_workflow_keeps_distinct_archive_stage_and_detailed_logs(self):
        workflow = (ROOT / ".github/workflows/full-validation.yml").read_text()
        self.assertIn("fetch-depth: 0", workflow)
        self.assertIn("scripts/run_validation.py", workflow)
        self.assertIn("--scope all", workflow)
        self.assertIn("GTHEORY_ARTIFACT_CHECK_DIR:", workflow)
        self.assertIn("GTHEORY_PACKAGE_CHECK_DIR:", workflow)
        self.assertIn("gtheory-package-check/*.Rcheck", workflow)
        self.assertIn("gtheory-committed-artifact/*.log", workflow)
        self.assertIn("full-validation.json", workflow)


if __name__ == "__main__":
    unittest.main()
