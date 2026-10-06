"""Build prerequisites must preserve both numerical pins and source bytes."""
import os
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
WORKFLOW = ROOT / ".github/workflows/compatibility.yml"


class CompatibilityBuildEnvironmentTests(unittest.TestCase):
    def test_minimum_documentation_is_verified_and_restored_before_build(self):
        text = WORKFLOW.read_text()
        numerical = "scripts/dependency-locks/R-4.5.0.lock"
        documentation = "scripts/dependency-locks/minimum-documentation.lock"
        check = f"python scripts/check_documentation_lock.py --numerical {numerical} --documentation {documentation}"
        restore = f'Rscript --vanilla scripts/restore_validation.R "$RUNNER_TEMP/gtheory-minimum-library" {documentation}'
        self.assertIn(f"hashFiles('{numerical}', '{documentation}')", text)
        self.assertIn("libuv1-dev", text)
        self.assertLess(text.index(check), text.index(restore))
        self.assertLess(text.index(restore), text.index("python scripts/stage_validation_bundle.py"))

    @unittest.skipUnless(shutil.which("git"), "Git is needed to exercise checkout conversion")
    def test_windows_checkout_configuration_preserves_committed_lf_bytes(self):
        text = WORKFLOW.read_text()
        before_checkout = text.split("    steps:\n", 1)[1].split("      - uses: actions/checkout@", 1)[0]
        self.assertIn("if: runner.os == 'Windows'", before_checkout)
        commands = re.findall(r"(?m)^          (git config --global [^\n]+)$", before_checkout)
        self.assertEqual(len(commands), 2)
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            environment = {**os.environ, "GIT_CONFIG_GLOBAL": str(root / "gitconfig"),
                           "GIT_CONFIG_NOSYSTEM": "1"}
            repo = root / "source"
            repo.mkdir()

            def git(*args):
                return subprocess.check_output(["git", *args], cwd=repo, env=environment,
                                               stderr=subprocess.PIPE)

            git("config", "--global", "core.autocrlf", "true")
            git("init", "-q")
            source = repo / "NAMESPACE"
            source.write_bytes(b"export(gt_fit)\nexport(gt_preflight)\n")
            git("add", "NAMESPACE")
            git("-c", "user.name=Test", "-c", "user.email=test@example.invalid",
                "commit", "-qm", "source")
            committed = git("show", "HEAD:NAMESPACE")
            source.unlink()
            git("checkout", "--", "NAMESPACE")
            self.assertIn(b"\r\n", source.read_bytes(), "fixture must reproduce Windows checkout conversion")
            for command in commands:
                subprocess.check_call(shlex.split(command), cwd=repo, env=environment)
            source.unlink()
            git("checkout", "--", "NAMESPACE")
            self.assertEqual(source.read_bytes(), committed)
            self.assertNotIn(b"\r\n", source.read_bytes())


if __name__ == "__main__":
    unittest.main()
