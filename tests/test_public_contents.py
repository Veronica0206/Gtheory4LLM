"""Regression checks for the publication boundary, with disposable fixtures."""
import importlib.util
import io
from pathlib import Path
import shutil
import subprocess
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

    def check(self):
        audit = module.PublicAudit(self.root)
        audit.working_tree()
        return audit

    def test_scientific_prose_is_allowed_but_private_directory_is_not(self):
        self.assertFalse(self.check().findings)
        self.write(Path("companion") / "draft.tex")
        self.assertTrue(any("Private research" in item["reason"] for item in self.check().findings))

    def test_symlink_targets_are_never_read(self):
        outside = Path(self.temporary.name) / "not-part-of-package"
        outside.mkdir()
        (outside / "file").write_text("outside content")
        (self.root / "docs").symlink_to(outside, target_is_directory=True)
        audit = self.check()
        self.assertTrue(any("Symbolic links" in item["reason"] for item in audit.findings))
        self.assertEqual(audit.files_checked, 2)

    def test_old_archives_and_raw_csvs_are_rejected(self):
        self.write(Path("artifacts") / "Gtheory4LLM_0.0.5.tar.gz")
        self.write(Path("inst") / "extdata" / "patient_rows.csv")
        reasons = " ".join(item["reason"] for item in self.check().findings)
        self.assertIn("current public release", reasons)
        self.assertIn("manifest CSV", reasons)

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
        audit = module.PublicAudit(self.root)
        audit.inspect_archive(buffer.getvalue(), "fixture archive")
        self.assertEqual(audit.archives_checked, 1)
        self.assertEqual(len(audit.findings), 2)
        self.assertFalse((self.root / "companion").exists())

    @unittest.skipUnless(shutil.which("Rscript"), "Rscript is required for serialized-data fixtures")
    def test_rds_metadata_and_recursive_values(self):
        path = self.root / "inst" / "extdata" / "example.rds"
        path.parent.mkdir(parents=True)
        setup = 'x <- list(source_provenance=list(data_kind="synthetic"), codings=list(native=list(data=data.frame(y=1:3))))\n'
        for mutation, expected_pass in [
            ("", True),
            ('x$source_provenance$data_kind <- NULL', False),
            ('x$codings$native$hidden <- new.env()', False),
            ('attr(x$codings$native$data, "hidden") <- function() NULL', False),
            ('x$codings$native$note <- paste0("/", "Users", "/example/secret")', False),
        ]:
            with self.subTest(mutation=mutation):
                code = setup + mutation + '\nsaveRDS(x, commandArgs(trailingOnly=TRUE)[[1L]])'
                subprocess.run([shutil.which("Rscript"), "--vanilla", "-e", code, str(path)], check=True,
                               capture_output=True, text=True, timeout=30)
                audit = self.check()
                self.assertEqual(not audit.findings, expected_pass, audit.findings)
                self.assertEqual(audit.rds_checked, 1)

    @unittest.skipUnless(shutil.which("git"), "Git is required for history fixtures")
    def test_deleted_private_history_still_blocks_publication(self):
        def git(*args):
            return subprocess.run(["git", "-C", str(self.root), "-c", "user.name=Public Audit Test",
                "-c", "user.email=audit@example.invalid", "-c", "commit.gpgsign=false",
                "-c", "core.hooksPath=/dev/null", *args], check=True, capture_output=True, timeout=30)
        git("init", "--quiet")
        git("add", ".")
        git("commit", "--quiet", "-m", "Clean initial package")
        clean = module.PublicAudit(self.root)
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
        audit = module.PublicAudit(self.root)
        audit.history()
        reasons = " ".join(item["reason"] for item in audit.findings)
        self.assertIn("Private research", reasons)
        self.assertIn("home-directory", reasons)
        self.assertEqual(audit.commits_checked, 3)


if __name__ == "__main__":
    unittest.main()
