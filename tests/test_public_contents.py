"""Regression checks for the publication boundary, with disposable fixtures."""
import importlib.util
import io
from pathlib import Path
import shutil
import subprocess
import sys
import tarfile
import tempfile
import unittest

MODULE = Path(__file__).resolve().parents[1] / "scripts" / "check_public_contents.py"
spec = importlib.util.spec_from_file_location("public_audit", MODULE)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class PublicContentsTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="gtheory-public-tests-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name) / "package"
        self.root.mkdir()
        (self.root / "DESCRIPTION").write_text("Package: Gtheory4LLM\nVersion: 0.0.6\n")
        (self.root / "README.md").write_text('The manuscript coding remains a Gaussian working score.\n')

    def write(self, relative, text="x"):
        path = self.root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)
        return path

    def check(self, expected_data_kind="synthetic"):
        audit = module.PublicAudit(self.root, expected_data_kind)
        audit.working_tree()
        return audit

    def git(self, *args):
        return subprocess.run(["git", "-C", str(self.root), "-c", "user.name=Public Audit Test",
            "-c", "user.email=audit@example.invalid", "-c", "commit.gpgsign=false",
            "-c", "core.hooksPath=/dev/null", *args], check=True, capture_output=True, timeout=30)

    def resource(self, mutation=""):
        path = self.root / "inst" / "extdata" / "example.rds"
        path.parent.mkdir(parents=True, exist_ok=True)
        setup = 'x <- list(source_provenance=list(data_kind="synthetic"), codings=list(native=list(data=data.frame(y=1:3))))\n'
        code = setup + mutation + '\nsaveRDS(x, commandArgs(trailingOnly=TRUE)[[1L]])'
        script = Path(self.temporary.name) / "create-resource.R"
        script.write_bytes(code.encode("utf-8"))
        subprocess.run([shutil.which("Rscript"), "--vanilla", str(script), str(path)], check=True,
                       capture_output=True, text=True, timeout=30)
        return path

    def release_archive(self, resource):
        buffer = io.BytesIO()
        with tarfile.open(fileobj=buffer, mode="w:gz") as archive:
            member = tarfile.TarInfo(module.PACKAGE + "/inst/extdata/example.rds")
            value = resource.read_bytes()
            member.size = len(value)
            archive.addfile(member, io.BytesIO(value))
        return buffer.getvalue()

    def test_the_fixed_parameter_reference_csvs_are_declared_not_incidental(self):
        # These carry synthetic fixtures and frozen numbers only, so declaring
        # them is deliberate. An undeclared CSV under the same directory must
        # still fail, so the allowlist stays a decision rather than a prefix.
        for name in ("reference.csv", "rejections.csv", "source-hashes.csv"):
            self.assertIn(f"validation-studies/discrete-sparse-reference/{name}",
                          module.STUDY_CSV_FILES)
        self.assertNotIn("validation-studies/discrete-sparse-reference/collected.csv",
                         module.STUDY_CSV_FILES)

    def test_the_fitted_smoke_csvs_are_declared_not_incidental(self):
        # The fitted smoke study is a separate contract from the fixed-parameter
        # reference, and it is declared the same way: by exact path. A new CSV
        # appearing under the directory must still fail the audit, so this
        # cannot decay into a prefix exemption.
        for name in ("panels.csv", "dense-baseline.csv", "source-hashes.csv"):
            self.assertIn(f"validation-studies/discrete-sparse-fitted-smoke/{name}",
                          module.STUDY_CSV_FILES)
        self.assertNotIn("validation-studies/discrete-sparse-fitted-smoke/sparse-results.csv",
                         module.STUDY_CSV_FILES)

    def test_release_kind_must_be_explicit_and_known(self):
        with self.assertRaises(ValueError):
            module.PublicAudit(self.root, "unreviewed")
        result = subprocess.run([sys.executable, str(MODULE), "--root", str(self.root),
                                 "--working-tree"], capture_output=True, text=True, timeout=30)
        self.assertEqual(result.returncode, 2)
        self.assertIn("--expected-data-kind", result.stderr)

    def test_scientific_prose_is_allowed_but_private_directory_is_not(self):
        self.assertFalse(self.check().findings)
        self.write(Path("companion") / "draft.tex")
        self.assertTrue(any("Private research" in item["reason"] for item in self.check().findings))

    def test_exact_release_checklist_sentence_is_prose_in_tree_and_history(self):
        prose = ("   The script builds into temporary staging, verifies archive"
                 "/source\n   correspondence and release identity, runs source validation, and audits\n"
                 "   public content before copying the bundle into `artifacts/`. Source validation\n")
        path = self.write("docs/RELEASE_CHECKLIST.md", prose)
        for ending in (b"\n", b"\r\n"):
            path.write_bytes(prose.encode().replace(b"\n", ending))
            self.assertFalse(self.check().findings)
            path.write_bytes(path.read_bytes() + b"archive" + b"/source.csv" + ending)
            self.assertTrue(any(x["reason"] == "private research-relative path"
                                for x in self.check().findings))
        path.write_text(prose)
        self.git("init", "--quiet")
        self.git("add", ".")
        self.git("commit", "--quiet", "-m", "Release preparation prose")
        path.write_text("Updated preparation prose.\n")
        self.git("add", ".")
        self.git("commit", "--quiet", "-m", "Clarify prose")
        historical = module.PublicAudit(self.root, "synthetic")
        historical.history()
        self.assertFalse(historical.findings)
        self.assertEqual(historical.commits_checked, 2)
        for value in ("archive" + "/source.csv", "archive" + "/source/private.tex"):
            path.write_text(prose + value + "\n")
            self.assertTrue(any(x["reason"] == "private research-relative path"
                                for x in self.check().findings))
        path.write_text("Updated preparation prose.\n")
        self.write("docs/OTHER.md", prose)
        self.assertTrue(any(x["reason"] == "private research-relative path"
                            for x in self.check().findings))

    def test_history_prose_exception_does_not_share_cache_with_other_documents(self):
        prose = ("   The script builds into temporary staging, verifies archive"
                 "/source\n   correspondence and release identity, runs source validation, and audits\n"
                 "   public content before copying the bundle into `artifacts/`.")
        self.write("docs/RELEASE_CHECKLIST.md", prose)
        self.write("docs/ZZ_OTHER.md", prose)
        self.git("init", "--quiet")
        self.git("add", ".")
        self.git("commit", "--quiet", "-m", "Identical text in different contexts")
        audit = module.PublicAudit(self.root, "synthetic")
        audit.history()
        self.assertTrue(any("ZZ_OTHER.md" in x["path"] and
                            x["reason"] == "private research-relative path" for x in audit.findings))

    def test_symlink_targets_are_never_read(self):
        outside = Path(self.temporary.name) / "not-part-of-package"
        outside.mkdir()
        (outside / "file").write_text("outside content")
        try:
            (self.root / "docs").symlink_to(outside, target_is_directory=True)
        except OSError as error:
            if getattr(error, "winerror", None) == 1314:
                self.skipTest("Windows does not grant this process symbolic-link creation privileges.")
            raise
        audit = self.check()
        self.assertTrue(any("Symbolic links" in item["reason"] for item in audit.findings))
        self.assertEqual(audit.files_checked, 2)

    def test_old_archives_and_raw_csvs_are_rejected(self):
        self.write(Path("artifacts") / "Gtheory4LLM_0.0.5.tar.gz")
        self.write(Path("inst") / "extdata" / "patient_rows.csv")
        reasons = " ".join(item["reason"] for item in self.check().findings)
        self.assertIn("current public release", reasons)
        self.assertIn("manifest CSV", reasons)

    def test_only_declared_synthetic_study_csvs_are_allowed(self):
        for name in sorted(module.STUDY_CSV_FILES):
            self.write(name, "scenario,estimate\nsynthetic,0.5\n")
        self.assertFalse(self.check().findings)
        self.write("validation-studies/discrete-laplace/raw_panel.csv", "unapproved rows")
        self.assertTrue(any("declared synthetic" in x["reason"] for x in self.check().findings))

    def test_study_csvs_still_undergo_private_content_scanning(self):
        self.write(sorted(module.STUDY_CSV_FILES)[0],
                   "/" + "Users" + "/private-person/source.csv")
        self.assertTrue(any("private home-directory" in x["reason"] for x in self.check().findings))

    def test_os_metadata_is_skipped_in_a_working_tree_but_never_in_an_archive(self):
        # A desktop environment recreates these files on sight and git ignores
        # them, so flagging them locally only teaches maintainers to ignore the
        # audit. They must still be refused inside anything published.
        self.write(Path(".DS_Store"))
        self.write(Path("R") / "Thumbs.db")
        audit = self.check()
        self.assertEqual(audit.findings, [])
        self.assertEqual(sorted(audit.skipped_os_metadata), [".DS_Store", "R/Thumbs.db"])

        buffer = io.BytesIO()
        with tarfile.open(fileobj=buffer, mode="w:gz") as archive:
            member = tarfile.TarInfo(module.PACKAGE + "/.DS_Store")
            member.size = 0
            archive.addfile(member, io.BytesIO(b""))
        packaged = module.PublicAudit(self.root, "synthetic")
        packaged.inspect_archive(buffer.getvalue(), "fixture archive")
        self.assertEqual(packaged.skipped_os_metadata, [])
        self.assertEqual(len(packaged.findings), 1)

    def test_built_vignette_products_are_accepted_but_stray_build_files_are_not(self):
        # R CMD build writes build/vignette.rds once a package has vignettes.
        # It is the build's own index, not a bundled example resource, so the
        # serialized-example rules must not be applied to it. Anything else
        # under build/ must still fail.
        def archive_with(*members):
            buffer = io.BytesIO()
            with tarfile.open(fileobj=buffer, mode="w:gz") as bundle:
                for name in members:
                    entry = tarfile.TarInfo("/".join([module.PACKAGE, name]))
                    payload = b"not a real rds"
                    entry.size = len(payload)
                    bundle.addfile(entry, io.BytesIO(payload))
            return buffer.getvalue()

        allowed = module.PublicAudit(self.root, "synthetic")
        allowed.inspect_archive(archive_with("build/partial.rdb", "build/vignette.rds",
                                             "vignettes/guide.Rmd", "inst/doc/guide.html"),
                                "fixture archive")
        self.assertEqual(allowed.findings, [])
        self.assertEqual(allowed.rds_checked, 0)

        stray = module.PublicAudit(self.root, "synthetic")
        stray.inspect_archive(archive_with("build/notes.rds"), "fixture archive")
        self.assertEqual(len(stray.findings), 1)
        self.assertIn("generated package-build file", stray.findings[0]["reason"])

    def test_a_superseded_release_archive_is_historical_only(self):
        # Bumping VERSION must not fail the audit on every commit made before
        # the bump: those commits legitimately contain the release that was
        # current then. The working tree stays pinned to the current one.
        previous = f"artifacts/{module.PACKAGE}_0.0.1.tar.gz"
        audit = module.PublicAudit(self.root, "synthetic")
        self.assertTrue(audit.allowed_path(previous, previous, historical=True))
        self.assertEqual(audit.findings, [])

        current = module.PublicAudit(self.root, "synthetic")
        self.assertFalse(current.allowed_path(previous, previous))
        self.assertEqual(len(current.findings), 1)

        # "Historical" excuses a superseded release, not arbitrary archives or
        # archives parked outside artifacts/.
        for rejected in (f"{module.PACKAGE}_0.0.1.tar.gz",
                         "artifacts/private-notes.tar.gz",
                         "artifacts/Something_0.0.1.tar.gz"):
            probe = module.PublicAudit(self.root, "synthetic")
            self.assertFalse(probe.allowed_path(rejected, rejected, historical=True), rejected)
            self.assertTrue(probe.findings, rejected)

    def test_archive_members_are_audited_without_extraction(self):
        buffer = io.BytesIO()
        with tarfile.open(fileobj=buffer, mode="w:gz") as archive:
            member = tarfile.TarInfo("/".join([module.PACKAGE, "companion", "draft.tex"]))
            value = b"private draft"
            member.size = len(value)
            archive.addfile(member, io.BytesIO(value))
            link = tarfile.TarInfo(module.PACKAGE + "/R/linked.R")
            link.type = tarfile.SYMTYPE
            link.linkname = "../../outside"
            archive.addfile(link)
        audit = module.PublicAudit(self.root, "synthetic")
        audit.inspect_archive(buffer.getvalue(), "fixture archive")
        self.assertEqual(audit.archives_checked, 1)
        self.assertEqual(len(audit.findings), 2)
        self.assertFalse((self.root / "companion").exists())

    @unittest.skipUnless(shutil.which("Rscript"), "Rscript is required for serialized-data fixtures")
    def test_rds_metadata_and_recursive_values(self):
        for mutation, expected_pass in [
            ("", True),
            ('x$source_provenance$data_kind <- NULL', False),
            ('x$source_provenance$data_kind <- "unknown"', False),
            ('x$source_provenance$data_kind <- c("synthetic", "public_llm_annotations")', False),
            ('x$codings$native$hidden <- new.env()', False),
            ('attr(x$codings$native$data, "hidden") <- function() NULL', False),
            ('x$codings$native$note <- paste0("/", "Users", "/example/secret")', False),
        ]:
            with self.subTest(mutation=mutation):
                path = self.resource(mutation)
                audit = self.check()
                self.assertEqual(not audit.findings, expected_pass, audit.findings)
                self.assertEqual(audit.rds_checked, 1)
                historical = module.PublicAudit(self.root, "public_llm_annotations")
                historical.inspect_rds(path.read_bytes(), "historical fixture", historical=True)
                self.assertEqual(not historical.findings, expected_pass, historical.findings)

    @unittest.skipUnless(shutil.which("Rscript"), "Rscript is required for serialized-data fixtures")
    def test_current_tree_and_archive_require_selected_kind(self):
        for actual_kind in module.PUBLIC_DATA_KINDS:
            with self.subTest(actual_kind=actual_kind):
                resource = self.resource('x$source_provenance$data_kind <- "' + actual_kind + '"')
                for expected_kind in module.PUBLIC_DATA_KINDS:
                    expected_pass = actual_kind == expected_kind
                    current = self.check(expected_kind)
                    self.assertEqual(not current.findings, expected_pass, current.findings)
                    archive = module.PublicAudit(self.root, expected_kind)
                    archive.inspect_archive(self.release_archive(resource), "current release")
                    self.assertEqual(not archive.findings, expected_pass, archive.findings)

    @unittest.skipUnless(shutil.which("Rscript") and shutil.which("git"),
                         "Rscript and Git are required for historical data fixtures")
    def test_history_accepts_both_public_kinds_but_rejects_unknown_archived_kind(self):
        self.git("init", "--quiet")
        artifact = self.root / "artifacts" / (module.PACKAGE + "_" + module.VERSION + ".tar.gz")
        artifact.parent.mkdir()
        for kind in module.PUBLIC_DATA_KINDS:
            resource = self.resource('x$source_provenance$data_kind <- "' + kind + '"')
            artifact.write_bytes(self.release_archive(resource))
            self.git("add", ".")
            self.git("commit", "--quiet", "-m", "Public example version: " + kind)
        audit = self.check("public_llm_annotations")
        audit.history()
        self.assertFalse(audit.findings, audit.findings)
        self.assertEqual(audit.commits_checked, 2)
        self.assertEqual(audit.archives_checked, 3)
        self.assertEqual(audit.rds_checked, 6)

        approved_archive = artifact.read_bytes()
        unknown = self.resource('x$source_provenance$data_kind <- "unknown"')
        artifact.write_bytes(self.release_archive(unknown))
        self.resource('x$source_provenance$data_kind <- "public_llm_annotations"')
        self.git("add", ".")
        self.git("commit", "--quiet", "-m", "Unapproved archived example version")
        artifact.write_bytes(approved_archive)
        self.git("add", ".")
        self.git("commit", "--quiet", "-m", "Restore approved archive")
        current = self.check("public_llm_annotations")
        self.assertFalse(current.findings, current.findings)
        current.history()
        self.assertTrue(any("data_kind" in item["reason"] and ".tar.gz!" in item["path"]
                            for item in current.findings), current.findings)
        self.assertEqual(current.commits_checked, 4)

    @unittest.skipUnless(shutil.which("git"), "Git is required for history fixtures")
    def test_deleted_private_history_still_blocks_publication(self):
        git = self.git
        git("init", "--quiet")
        git("add", ".")
        git("commit", "--quiet", "-m", "Clean initial package")
        clean = module.PublicAudit(self.root, "synthetic")
        clean.history()
        self.assertFalse(clean.findings)
        private = self.write(Path("companion") / "draft.tex")
        self.write("README.md", "/" + "Users" + "/example/private-project/\n")
        git("add", ".")
        git("commit", "--quiet", "-m", "Add temporary material")
        private.unlink()
        private.parent.rmdir()
        self.write("README.md", "Clean current package.\n")
        git("add", "-A")
        git("commit", "--quiet", "-m", "Remove temporary material")
        self.assertFalse(self.check().findings)
        audit = module.PublicAudit(self.root, "synthetic")
        audit.history()
        reasons = " ".join(item["reason"] for item in audit.findings)
        self.assertIn("Private research", reasons)
        self.assertIn("home-directory", reasons)
        self.assertEqual(audit.commits_checked, 3)


if __name__ == "__main__":
    unittest.main()
