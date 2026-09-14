"""The environment-restoration bootstrap must be pinned and verifiable.

A pinned version says which renv is used. A recorded digest is what makes
retrieving that exact file checkable, and a cache is what makes retrieving it
possible at all when the archive is unreachable. This checks that the descriptor
and the restore script agree about all three, without downloading anything.
"""
from __future__ import annotations

import json
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]
DESCRIPTOR = ROOT / "scripts/dependency-locks/renv-bootstrap.json"
RESTORE = ROOT / "scripts/restore_validation.R"
WORKFLOWS = ROOT / ".github/workflows"


class BootstrapDescriptorTests(unittest.TestCase):
    def setUp(self):
        self.descriptor = json.loads(DESCRIPTOR.read_text(encoding="utf-8"))
        self.restore = RESTORE.read_text(encoding="utf-8")

    def test_the_descriptor_records_version_url_and_digest_slot(self):
        self.assertEqual(self.descriptor["tool"], "renv")
        self.assertRegex(self.descriptor["version"], r"^\d+\.\d+\.\d+$")
        self.assertTrue(self.descriptor["url"].startswith("https://"))
        self.assertIn(self.descriptor["version"], self.descriptor["url"])
        digest = self.descriptor.get("sha256")
        self.assertIsNotNone(digest, "the bootstrap digest must be recorded, not left null")
        self.assertRegex(digest, r"^[0-9a-f]{64}$",
                         "a recorded digest must be a SHA-256 hex string")

    def test_the_restore_script_reads_the_descriptor_instead_of_hard_coding(self):
        self.assertIn("renv-bootstrap.json", self.restore)
        self.assertNotIn(self.descriptor["url"], self.restore,
                         "the URL must come from the descriptor, not from the script")
        self.assertNotIn(f'"{self.descriptor["version"]}"', self.restore,
                         "the version must come from the descriptor, not from the script")

    def test_a_recorded_digest_makes_a_mismatch_fatal(self):
        # A digest that is recorded but not enforced is decoration. The restore
        # script must stop, and must show both digests when it does.
        self.assertIn("checksum mismatch", self.restore)
        self.assertIn("expected: ", self.restore)
        self.assertIn("observed: ", self.restore)
        self.assertIn("stop(", self.restore[self.restore.index("checksum mismatch") - 200:
                                            self.restore.index("checksum mismatch")])

    def test_the_digest_is_verified_before_installation(self):
        verify = self.restore.index("sha256sum")
        install = self.restore.index("install.packages(tarball")
        self.assertLess(verify, install, "the digest must be checked before installing")
        self.assertIn("checksum mismatch", self.restore)
        self.assertIn("Refusing to install", self.restore)

    def test_the_cache_is_written_only_after_the_digest_is_checked(self):
        # A corrupted download that reaches the cache would be re-read by every
        # later run on that machine. It cannot pass the digest check, but it
        # should never be written there in the first place.
        verify = self.restore.index("sha256sum")
        cache_write = self.restore.index("file.copy(tarball, cached")
        self.assertLess(verify, cache_write,
                        "the cache must be populated after verification, not before")
        self.assertIn("downloaded && !is.na(cached) && !is.na(renv_sha256)", self.restore,
                      "only a verified download should be cached")

    def test_a_local_copy_is_preferred_over_the_network(self):
        for variable in ("GTHEORY_RENV_BOOTSTRAP", "GTHEORY_RENV_BOOTSTRAP_CACHE"):
            self.assertIn(variable, self.restore)
        supplied = self.restore.index("GTHEORY_RENV_BOOTSTRAP\"")
        download = self.restore.index("utils::download.file")
        self.assertLess(supplied, download, "a supplied file must be tried before downloading")

    def test_every_locked_restore_uses_the_cache(self):
        for name in ("full-validation.yml", "compatibility.yml"):
            text = (WORKFLOWS / name).read_text(encoding="utf-8")
            with self.subTest(workflow=name):
                self.assertIn("restore_validation.R", text)
                self.assertIn("GTHEORY_RENV_BOOTSTRAP_CACHE", text,
                              "a locked restore must use the cached bootstrap")
                self.assertIn("renv-bootstrap.json", text,
                              "the cache key must follow the descriptor")


if __name__ == "__main__":
    unittest.main()
