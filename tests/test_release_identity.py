"""Release version and documentation drift must fail before publication."""
import json
import unittest

import test_committed_artifact as fixtures

CHECK = fixtures.CHECK


class ReleaseIdentityTests(unittest.TestCase):
    def setUp(self):
        self.fixture = fixtures.CommittedArtifactTests()
        self.fixture.setUp()
        self.addCleanup(self.fixture.doCleanups)
        self.root = self.fixture.root
        self.manifest = self.fixture.manifest
        self.write_summaries()

    def write_summaries(self, source="0.0.1", artifact="0.0.1", state="prepared"):
        for filename in ("README.md", "NEWS.md"):
            checkout = f"Checkout version: **{source}**.\n" if filename == "README.md" else ""
            (self.root / filename).write_text(
                "<!-- release-identity:start -->\n" + checkout +
                f"Current artifact bundle: **{artifact}**.\n" +
                f"Release state: **{state}**.\n" +
                "<!-- release-identity:end -->\n", encoding="utf-8")
        (self.root / "artifacts/README.md").write_text(f"# Example {artifact} release\n", encoding="utf-8")

    def publish(self):
        """Move the fixture into the state a real publication leaves behind.

        The order matters: the published state is committed and only then
        tagged, so the tag carries the manifest it claims to publish.
        """
        self.fixture.write_manifest(release_state="published")
        self.write_summaries(state="published")
        self.fixture.git("add", "-A")
        self.fixture.git("commit", "-qm", "publish")
        if CHECK.local_release_tag(self.root, "v0.0.1"):
            self.fixture.git("tag", "-d", "v0.0.1")
        self.fixture.git("tag", "v0.0.1")

    def verify(self, tag=None):
        return CHECK.verify_release_identity(self.root, self.manifest, tag)

    def test_current_release_and_tag_match_real_git_metadata(self):
        self.publish()
        result = self.verify("v0.0.1")
        self.assertTrue(result["release_tag_checked"])
        self.assertEqual(result["artifact_version"], "0.0.1")
        self.assertFalse(result["development_checkout"])
        with self.assertRaisesRegex(ValueError, "tag/version mismatch"):
            self.verify("v0.0.2")

    def test_a_prepared_bundle_is_not_a_published_release(self):
        # No tag exists yet, so nothing may call this bundle published, and a
        # published claim must be checked against git rather than prose.
        self.assertFalse(self.verify()["published"])
        self.fixture.write_manifest(release_state="published")
        with self.assertRaisesRegex(ValueError, "release state mismatch"):
            self.verify()
        self.write_summaries(state="published")
        with self.assertRaisesRegex(ValueError, "requires the v0.0.1 tag"):
            self.verify()

    def test_publication_makes_the_prepared_claim_stale(self):
        self.fixture.git("tag", "v0.0.1")
        with self.assertRaisesRegex(ValueError, "contradicts the existing v0.0.1 tag"):
            self.verify()
        self.publish()
        result = self.verify()
        self.assertTrue(result["published"])
        # A published release is tag-checked even when no tag was requested.
        self.assertTrue(result["release_tag_checked"])
        self.assertEqual(result["release_tag"], "v0.0.1")

    def test_release_state_must_be_declared_and_recognized(self):
        for state in (None, "", "released", "PUBLISHED"):
            with self.subTest(state=state):
                content = json.loads(self.manifest.read_text())
                if state is None:
                    content.pop("release_state")
                else:
                    content["release_state"] = state
                self.manifest.write_text(json.dumps(content))
                with self.assertRaisesRegex(ValueError, "must declare release_state"):
                    self.verify()

    def test_a_development_checkout_may_keep_a_published_release(self):
        self.publish()
        path = self.root / "DESCRIPTION"
        path.write_text(path.read_text().replace("Version: 0.0.1", "Version: 0.0.1.9000"))
        self.write_summaries(source="0.0.1.9000", state="published")
        self.assertTrue(self.verify()["development_checkout"])

    def test_each_declared_version_is_checked_independently(self):
        for filename, old, new, message in (
            ("DESCRIPTION", "Version: 0.0.1", "Version: 0.0.2", "DESCRIPTION"),
            ("README.md", "bundle: **0.0.1**", "bundle: **0.0.2**", "artifact version mismatch"),
            ("NEWS.md", "bundle: **0.0.1**", "bundle: **0.0.2**", "artifact version mismatch"),
            ("README.md", "Checkout version: **0.0.1**", "Checkout version: **0.0.2**", "checkout version mismatch"),
            ("artifacts/README.md", "0.0.1 release", "0.0.2 release", "release version mismatch"),
        ):
            with self.subTest(file=filename):
                path = self.root / filename
                original = path.read_text()
                path.write_text(original.replace(old, new))
                with self.assertRaisesRegex(ValueError, message):
                    self.verify()
                path.write_text(original)

    def test_manifest_version_and_archive_name_cannot_diverge(self):
        original = json.loads(self.manifest.read_text())
        changed = dict(original, version="0.0.2")
        self.manifest.write_text(json.dumps(changed))
        with self.assertRaisesRegex(ValueError, "version mismatch"):
            self.verify()
        original["files"]["Example_0.0.2.tar.gz"] = original["files"].pop("Example_0.0.1.tar.gz")
        self.manifest.write_text(json.dumps(original))
        with self.assertRaisesRegex(ValueError, "archive filename/version mismatch"):
            self.verify()

    def test_explicit_development_checkout_preserves_prior_release(self):
        path = self.root / "DESCRIPTION"
        path.write_text(path.read_text().replace("Version: 0.0.1", "Version: 0.0.1.9000"))
        self.write_summaries(source="0.0.1.9000")
        self.assertTrue(self.verify()["development_checkout"])
        with self.assertRaisesRegex(ValueError, "tag/version mismatch"):
            self.verify("v0.0.1")

    def test_historical_news_is_not_a_current_release_claim(self):
        path = self.root / "NEWS.md"
        path.write_text(path.read_text() + "\n# Example 0.0.0\nHistorical release retained.\n")
        self.assertEqual(self.verify()["artifact_version"], "0.0.1")
        path.write_text(path.read_text() + path.read_text())
        with self.assertRaisesRegex(ValueError, "one release-identity"):
            self.verify()

    def test_tag_manifest_drift_is_rejected_even_if_version_matches(self):
        self.publish()
        changed = json.loads(self.manifest.read_text())
        changed["files"]["Example-manual.pdf"]["sha256"] = "f" * 64
        self.manifest.write_text(json.dumps(changed))
        with self.assertRaisesRegex(ValueError, "tag manifest differs"):
            self.verify("v0.0.1")


if __name__ == "__main__":
    unittest.main()
