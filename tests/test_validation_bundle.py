"""Release validation stages a matching bundle without touching published bytes."""
import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
SPEC = importlib.util.spec_from_file_location("stage_bundle", ROOT / "scripts/stage_validation_bundle.py")
STAGE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(STAGE)


class ValidationBundleTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve() / "source"
        (self.root / "artifacts").mkdir(parents=True)
        self.retained = self.root / "artifacts/manifest.json"
        self.retained.write_text(json.dumps({"version": "0.2.0"}))
        self.destination = Path(self.temp.name).resolve() / "staged"

    def select(self, version):
        (self.root / "DESCRIPTION").write_text("Package: Gtheory4LLM\nVersion: " + version + "\n")
        return STAGE.select_manifest(self.root, self.destination)

    def test_unbundled_release_is_staged_and_both_guards_run(self):
        original = self.retained.read_bytes()
        with patch.object(STAGE.subprocess, "run") as run, \
                patch.object(STAGE, "verify_bundle") as bundle, \
                patch.object(STAGE, "verify_release_identity") as identity:
            selected = self.select("0.4.0")
        self.assertEqual(selected, self.destination / "manifest.json")
        command = run.call_args.args[0]
        self.assertEqual(command[-3:], ["--skip-validation", "--dry-run", str(self.destination)])
        self.assertTrue(run.call_args.kwargs["check"])
        bundle.assert_called_once_with(self.root, selected)
        identity.assert_called_once_with(self.root, selected)
        self.assertEqual(self.retained.read_bytes(), original)

    def test_existing_and_development_bundles_are_verified_not_rebuilt(self):
        for version in ("0.2.0", "0.4.0.9000"):
            with self.subTest(version=version), patch.object(STAGE.subprocess, "run") as run, \
                    patch.object(STAGE, "verify_bundle"), \
                    patch.object(STAGE, "verify_release_identity", side_effect=ValueError("invalid identity")):
                with self.assertRaisesRegex(ValueError, "invalid identity"):
                    self.select(version)
                run.assert_not_called()

    def test_in_checkout_and_stale_staging_are_rejected(self):
        self.destination = self.root / "staged"
        with self.assertRaisesRegex(ValueError, "outside"):
            self.select("0.4.0")
        self.destination = Path(self.temp.name).resolve() / "staged"
        self.destination.mkdir()
        (self.destination / "manifest.json").write_text("stale")
        with self.assertRaisesRegex(ValueError, "empty"):
            self.select("0.4.0")


if __name__ == "__main__":
    unittest.main()
