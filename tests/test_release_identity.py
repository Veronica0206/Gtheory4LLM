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

    def neutral_summaries(self, version="0.0.1"):
        for name in ("README.md", "NEWS.md"):
            (self.root / name).write_text(
                "<!-- release-identity:start -->\n"
                f"Source version: **{version}**.\n"
                "See [manifest](https://example.invalid/artifacts/manifest.json) "
                "and [releases](https://example.invalid/releases).\n"
                "<!-- release-identity:end -->\n")

    def test_neutral_source_survives_publication_without_rebuild(self):
        self.neutral_summaries()
        # Reproduce Windows checkout translation even on Unix. The archive must
        # match committed LF bytes, while publication leaves working bytes alone.
        self.fixture.git("config", "core.autocrlf", "true")
        working_source = {}
        for name in ("README.md", "NEWS.md"):
            path = self.root / name
            path.write_bytes(path.read_bytes().replace(b"\r\n", b"\n").replace(b"\n", b"\r\n"))
            working_source[name] = path.read_bytes()
        # Build a real fixture archive from the committed neutral source.
        self.fixture.git("add", "README.md", "NEWS.md")
        self.fixture.git("commit", "-qm", "neutral source")
        self.fixture.commit = self.fixture.git("rev-parse", "HEAD").decode().strip()
        source = {name: self.fixture.git("show", f"HEAD:{name}") for name in working_source}
        self.fixture.members.update(source)
        self.fixture.write_archive()
        self.fixture.write_manifest()
        self.assertFalse(self.verify()["published"])
        CHECK.verify_bundle(self.root, self.manifest)
        archive_bytes = self.fixture.archive.read_bytes()
        self.fixture.write_manifest(release_state="published")
        self.fixture.git("add", "artifacts")
        self.fixture.git("commit", "-qm", "publication metadata only")
        self.fixture.git("tag", "v0.0.1")
        self.assertTrue(self.verify("v0.0.1")["published"])
        CHECK.verify_bundle(self.root, self.manifest)
        self.assertEqual(archive_bytes, self.fixture.archive.read_bytes())
        self.assertEqual(working_source, {name: (self.root / name).read_bytes() for name in working_source})
        # A rehashed archive with rewritten source still fails correspondence.
        self.fixture.members["README.md"] += b"unrecorded archive edit\n"
        self.fixture.write_archive()
        self.fixture.write_manifest(release_state="published")
        with self.assertRaisesRegex(ValueError, "source"):
            CHECK.verify_bundle(self.root, self.manifest)

    def test_neutral_development_and_source_version_checks(self):
        self.publish()
        path = self.root / "DESCRIPTION"
        path.write_text(path.read_text().replace("Version: 0.0.1", "Version: 0.0.1.9000"))
        self.neutral_summaries("0.0.1.9000")
        self.assertTrue(self.verify()["development_checkout"])
        self.neutral_summaries("0.0.2")
        with self.assertRaisesRegex(ValueError, "source version mismatch"):
            self.verify()

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

    def test_development_may_target_a_later_release_but_never_an_earlier_one(self):
        # A development checkout is labelled <target>.9000 for the release it
        # works towards. After 0.0.1 ships, continuing on 0.0.1.9000 and opening
        # 0.0.2.9000 are both ordinary; a target behind the published bundle is
        # not, because the bundle would then claim to precede its own source.
        self.publish()
        path = self.root / "DESCRIPTION"
        original = path.read_text()
        for target in ("0.0.1.9000", "0.0.2.9000", "0.1.0.9000", "0.10.0.9000", "1.0.0.9001"):
            with self.subTest(target=target):
                path.write_text(original.replace("Version: 0.0.1", "Version: " + target))
                self.write_summaries(source=target, state="published")
                self.assertTrue(self.verify()["development_checkout"])
        for behind in ("0.0.0.9000", "0.0.1", "0.0.2"):
            with self.subTest(behind=behind):
                path.write_text(original.replace("Version: 0.0.1", "Version: " + behind))
                self.write_summaries(source=behind, state="published")
                if behind == "0.0.1":
                    self.assertFalse(self.verify()["development_checkout"])
                else:
                    with self.assertRaisesRegex(ValueError, "version mismatch"):
                        self.verify()

    def test_release_versions_are_ordered_numerically_not_as_text(self):
        # "0.10.0" follows "0.9.0"; comparing as text would place it before and
        # reject a legitimate development line.
        self.assertGreater(CHECK.release_order("0.10.0"), CHECK.release_order("0.9.0"))
        self.assertGreater(CHECK.release_order("1.0.0"), CHECK.release_order("0.10.0"))
        self.assertEqual(CHECK.release_order("0.1.0"), CHECK.release_order("0.1.0"))
        # The accepted syntax allows a variable component count, so two
        # spellings of one release must compare equal rather than letting the
        # shorter tuple sort first.
        self.assertEqual(CHECK.release_order("0.2"), CHECK.release_order("0.2.0"))
        self.assertEqual(CHECK.release_order("1.0"), CHECK.release_order("1.0.0"))
        self.assertEqual(CHECK.release_order("0.2.0.0"), CHECK.release_order("0.2"))
        self.assertGreater(CHECK.release_order("0.2.1"), CHECK.release_order("0.2"))
        self.assertGreater(CHECK.release_order("0.2"), CHECK.release_order("0.1.9"))
        self.assertEqual(CHECK.release_order("0"), CHECK.release_order("0.0.0"))

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

    def test_stale_install_and_status_prose_fails_outside_identity_block(self):
        self.publish()
        cases = (
            ("README.md", "Until the `v0.0.1` release is\npublished, use the bundle."),
            ("README.md", "Once releases exist, download the archive."),
            ("docs/DEVELOPMENT_STATUS.md", "**No release is published.** No `v0.0.1` tag."),
            ("docs/DEVELOPMENT_STATUS.md", "No 0.0.1 release exists."),
            ("docs/DEVELOPMENT_STATUS.md", "v0.0.1 has not been published."),
        )
        for name, text in cases:
            with self.subTest(name=name, text=text):
                path = self.root / name
                path.parent.mkdir(exist_ok=True)
                original = path.read_text() if path.exists() else ""
                path.write_text(original + "\n" + text + "\n")
                with self.assertRaisesRegex(ValueError, "stale unpublished-release prose"):
                    self.verify()
                path.write_text(original)

    def test_prose_guard_preserves_history_examples_and_distinct_versions(self):
        self.publish()
        news = self.root / "NEWS.md"
        news.write_text(news.read_text() + "\n# Preparation history\nNo release is published.\n")
        readme = self.root / "README.md"
        readme.write_text(readme.read_text() +
                          "\nNo 0.0.1.9000 release exists.\nNo 0.0.2 release exists.\n" +
                          "> Historical quote: no release is published.\n" +
                          "```text\nOnce releases exist, use the archive.\n```\n")
        self.assertTrue(self.verify()["published"])


if __name__ == "__main__":
    unittest.main()
