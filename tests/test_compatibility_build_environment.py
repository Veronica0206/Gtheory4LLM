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
    def test_every_manual_environment_updates_tlmgr_and_installs_makeindex(self):
        checked = 0
        for filename in ("full-validation.yml", "compatibility.yml", "cran-readiness.yml"):
            text = (ROOT / ".github/workflows" / filename).read_text()
            for step in re.findall(r"(?ms)^      - name: .*?(?=^      - |\Z)", text):
                if "tlmgr" not in step:
                    continue
                with self.subTest(workflow=filename, step=step.splitlines()[0]):
                    if "shell: pwsh" in step:
                        self.assertIn("if: runner.os == 'Windows'", step)
                        self.assertIn("$ErrorActionPreference = 'Stop'", step)
                        self.assertEqual(len(re.findall(
                            r"& tlmgr\.bat [^\n]+\n\s+if \(\$LASTEXITCODE -ne 0\) \{ exit \$LASTEXITCODE \}", step)), 2)
                        for tool in ("pdflatex", "makeindex"):
                            self.assertIn(f"Get-Command {tool} -ErrorAction Stop", step)
                    else:
                        self.assertIn("shell: bash", step)
                        self.assertIn("set -euo pipefail", step)
                        self.assertTrue("command -v makeindex" in step or "for executable in pdflatex makeindex" in step)
                        if filename == "compatibility.yml":
                            self.assertIn("if: runner.os != 'Windows'", step)
                    self.assertLess(step.index("update --self"), step.index("install makeindex"))
                    self.assertNotIn("|| true", step)
                    checked += 1
        self.assertEqual(checked, 5, "locked, Unix/Windows compatibility, ordinary R-devel, and noLD need TeX")

    @unittest.skipUnless(os.name != "nt" and shutil.which("bash"),
                         "Unix Bash is needed to exercise the Unix-only setup step")
    def test_unix_manual_setup_stops_on_self_update_or_install_failure(self):
        text = WORKFLOW.read_text()
        step = next(step for step in re.findall(r"(?ms)^      - name: .*?(?=^      - |\Z)", text)
                    if "tlmgr" in step and "shell: bash" in step)
        script = "\n".join(line[10:] for line in step.split("        run: |\n", 1)[1].splitlines()
                           if line.startswith("          "))
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            tlmgr = root / "tlmgr"
            tlmgr.write_bytes(b'#!/usr/bin/env bash\n'
                              b'printf "%s\\n" "$*" >> "$TEX_TEST_LOG"\n'
                              b'if [[ "$1" == update ]]; then exit "$TEX_UPDATE_STATUS"; fi\n'
                              b'exit "$TEX_INSTALL_STATUS"\n')
            tlmgr.chmod(0o755)
            for update, install, calls in ((29, 0, 1), (0, 37, 2)):
                log = root / "calls"
                log.write_text("")
                environment = {**os.environ, "PATH": str(root) + os.pathsep + os.environ["PATH"],
                               "TEX_TEST_LOG": str(log), "TEX_UPDATE_STATUS": str(update),
                               "TEX_INSTALL_STATUS": str(install)}
                result = subprocess.run(["bash", "-c", script], env=environment,
                                        capture_output=True, text=True)
                self.assertEqual(result.returncode, update or install)
                self.assertEqual(len(log.read_text().splitlines()), calls)

    @unittest.skipUnless(os.name == "nt" and shutil.which("pwsh"), "Windows PowerShell is needed to execute tlmgr.bat")
    def test_windows_manual_setup_propagates_both_native_exit_codes(self):
        step = next(step for step in re.findall(r"(?ms)^      - name: .*?(?=^      - |\Z)", WORKFLOW.read_text())
                    if "tlmgr.bat" in step)
        script = "\n".join(line[10:] for line in step.split("        run: |\n", 1)[1].splitlines()
                           if line.startswith("          "))
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "tlmgr.bat").write_bytes(b'@echo off\r\n'
                b'echo %*>> "%TEX_TEST_LOG%"\r\n'
                b'if "%1"=="update" exit /b %TEX_UPDATE_STATUS%\r\n'
                b'exit /b %TEX_INSTALL_STATUS%\r\n')
            setup = root / "setup.ps1"
            setup.write_text(script)
            for update, install, calls in ((29, 0, 1), (0, 37, 2)):
                log = root / "calls"
                log.write_text("")
                environment = {**os.environ, "PATH": str(root) + os.pathsep + os.environ["PATH"],
                               "TEX_TEST_LOG": str(log), "TEX_UPDATE_STATUS": str(update),
                               "TEX_INSTALL_STATUS": str(install)}
                result = subprocess.run(["pwsh", "-NoProfile", "-File", str(setup)], env=environment,
                                        capture_output=True, text=True)
                self.assertEqual(result.returncode, update or install, result.stderr)
                self.assertEqual(len(log.read_text().splitlines()), calls)

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
