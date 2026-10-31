"""Build prerequisites must preserve both numerical pins and source bytes."""
import hashlib
import json
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
    @unittest.skipUnless(os.name != "nt" and shutil.which("bash") and shutil.which("shasum"),
                         "Unix Bash and shasum are needed for the macOS setup")
    def test_native_gettext_install_requires_verified_download(self):
        digest = "bdc3356cfb2c8dd69618fd76975474f4ec793cbe8f4894389d0426da8f4facc3"
        for filename in ("compatibility.yml", "cran-readiness.yml"):
            text = (ROOT / ".github/workflows" / filename).read_text()
            if filename == "cran-readiness.yml":
                text = text.split("  check-platforms:", 1)[1].split("  nold:", 1)[0]
            step = next(step for step in re.findall(r"(?ms)^      - name: .*?(?=^      - |\Z)", text)
                        if "name: Install native gettext headers on macOS" in step)
            self.assertIn("if: runner.os == 'macOS'", step)
            self.assertNotIn("continue-on-error:", step)
            self.assertLess(text.index(step), text.index("uses: r-lib/actions/setup-r-dependencies@"))
            script = "\n".join(line[10:] for line in step.split("        run: |\n", 1)[1].splitlines()
                               if line.startswith("          "))
            self.assertIn(digest, script)
            self.assertIn("https://mac.r-project.org/bin/darwin23/arm64/gettext-0.22.5-darwin.23-arm64.tar.xz", script)
            self.assertIn("-C / opt/R/arm64/include/libintl.h opt/R/arm64/lib/libintl.a", script)
            with tempfile.TemporaryDirectory(prefix="gettext setup ") as directory:
                root = Path(directory)
                binaries = root / "bin"
                binaries.mkdir()
                source = root / "download"
                source.write_bytes(b"verified fixture bytes")
                fixture_digest = hashlib.sha256(source.read_bytes()).hexdigest()
                script = script.replace(digest, fixture_digest)
                commands = {
                    "uname": '#!/bin/sh\nprintf "%s\n" "$GETTEXT_TEST_ARCH"\n',
                    "curl": '#!/bin/sh\nif [ "$GETTEXT_TEST_DOWNLOAD_STATUS" != 0 ]; then exit "$GETTEXT_TEST_DOWNLOAD_STATUS"; fi\n'
                            'for arg in "$@"; do destination="$arg"; done\ncp "$GETTEXT_TEST_DOWNLOAD" "$destination"\n',
                    "sudo": '#!/bin/sh\nprintf "%s\n" "$*" >> "$GETTEXT_TEST_INSTALL_LOG"\n',
                }
                for name, content in commands.items():
                    command = binaries / name
                    command.write_text(content)
                    command.chmod(0o755)
                for arch, download, corrupt, success in (
                    ("arm64", 0, False, True),
                    ("arm64", 22, False, False),
                    ("arm64", 0, True, False),
                    ("x86_64", 0, False, False),
                ):
                    with self.subTest(workflow=filename, arch=arch, download=download, corrupt=corrupt):
                        log = root / "install-log"
                        log.write_text("")
                        source.write_bytes(b"wrong bytes" if corrupt else b"verified fixture bytes")
                        environment = {**os.environ, "PATH": str(binaries) + os.pathsep + os.environ["PATH"],
                                       "RUNNER_TEMP": str(root), "GETTEXT_TEST_ARCH": arch,
                                       "GETTEXT_TEST_DOWNLOAD_STATUS": str(download),
                                       "GETTEXT_TEST_DOWNLOAD": str(source), "GETTEXT_TEST_INSTALL_LOG": str(log)}
                        result = subprocess.run(["bash", "-c", script], env=environment,
                                                capture_output=True, text=True)
                        self.assertEqual(result.returncode == 0, success, result.stdout + result.stderr)
                        self.assertEqual(bool(log.read_text()), success)

    def test_windows_uses_prebuilt_manual_tools_without_changing_unix_bundle(self):
        selected = "TINYTEX_INSTALLER: ${{ runner.os == 'Windows' && 'TinyTeX' || 'TinyTeX-1' }}"
        for filename in ("compatibility.yml", "cran-readiness.yml"):
            with self.subTest(workflow=filename):
                text = (ROOT / ".github/workflows" / filename).read_text()
                if filename == "cran-readiness.yml":
                    text = re.search(r"(?ms)^  check-platforms:\n(.*?)(?=^  [A-Za-z][\w-]*:\n|\Z)", text).group(1)
                setup = re.search(r"(?ms)^      - uses: r-lib/actions/setup-tinytex@[^\n]+\n(.*?)(?=^      - |\Z)", text)
                self.assertIsNotNone(setup)
                self.assertIn(selected, setup.group(1))
                self.assertIn("timeout-minutes: 15", setup.group(1))
                self.assertNotIn("continue-on-error:", setup.group(1))

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
                        # Each tlmgr command runs under its own time limit with a
                        # bounded number of attempts, a stalled process tree is
                        # stopped, exhaustion fails the step, and the step itself
                        # has a limit, so a stalled mirror cannot hold the job.
                        self.assertIn("timeout-minutes:", step)
                        if filename == "compatibility.yml":
                            # Source compatibility may report its manual skipped
                            # after removing an incomplete TinyTeX installation.
                            self.assertIn("continue-on-error: true", step)
                            self.assertIn("Remove-TinyTeX", step)
                            self.assertIn("Remove-Item -LiteralPath $root -Recurse -Force", step)
                            self.assertRegex(step, r"catch \{[^}]*Remove-TinyTeX[^}]*exit \$script:TexExitCode")
                            self.assertIn("$script:TexExitCode = $process.ExitCode", step)
                        else:
                            # The exact candidate requires a manual on every OS;
                            # failure must stop its job instead of skipping it.
                            self.assertNotIn("continue-on-error:", step)
                            self.assertNotIn("Remove-TinyTeX", step)
                            self.assertIn('throw "tlmgr $Command exited with code $($process.ExitCode)"', step)
                        # Windows runners enable tlmgr's aria2c container prefetch,
                        # which stalled on every attempt; the step turns it off.
                        self.assertIn("TEXLIVE_PREFETCH: '0'", step)
                        self.assertIn("function Invoke-Tlmgr", step)
                        self.assertIn("WaitForExit(300000)", step)
                        self.assertIn("taskkill.exe /PID", step)
                        self.assertIn("-le 2", step)
                        self.assertRegex(step, r"throw \"tlmgr ")
                        mirror = "Invoke-Tlmgr 'option repository https://ctan.math.illinois.edu/systems/texlive/tlnet'"
                        self.assertIn(mirror, step)
                        self.assertLess(step.index(mirror), step.index("Invoke-Tlmgr 'update --self'"))
                        self.assertIn("Invoke-Tlmgr 'install makeindex inconsolata helvetic times courier'", step)
                        self.assertNotIn("collection-latexrecommended", step)
                        self.assertEqual(len(re.findall(r"^\s+Invoke-Tlmgr '[^']+'\s*$", step, re.M)), 3)
                        for tool in ("pdflatex", "makeindex"):
                            self.assertIn(f"Get-Command {tool} -ErrorAction Stop", step)
                    else:
                        self.assertIn("shell: bash", step)
                        self.assertIn("set -euo pipefail", step)
                        self.assertIn("install makeindex inconsolata helvetic times courier collection-latexrecommended", step)
                        self.assertTrue("command -v makeindex" in step or "for executable in pdflatex makeindex" in step)
                        if filename == "compatibility.yml":
                            self.assertIn("if: runner.os != 'Windows'", step)
                    self.assertLess(step.index("update --self"), step.index("install makeindex"))
                    self.assertNotIn("|| true", step)
                    checked += 1
        self.assertEqual(checked, 7, "locked, Unix/Windows compatibility, R-devel, macOS/Windows candidates, and noLD need TeX")

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
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "tlmgr.bat").write_bytes(b'@echo off\r\n'
                b'echo %*>> "%TEX_TEST_LOG%"\r\n'
                b'if "%1"=="option" exit /b %TEX_REPO_STATUS%\r\n'
                b'if "%1"=="update" exit /b %TEX_UPDATE_STATUS%\r\n'
                b'exit /b %TEX_INSTALL_STATUS%\r\n')
            setup = root / "setup.ps1"
            for filename in ("compatibility.yml", "cran-readiness.yml"):
                workflow = ROOT / ".github/workflows" / filename
                step = next(step for step in re.findall(r"(?ms)^      - name: .*?(?=^      - |\Z)", workflow.read_text())
                            if "tlmgr.bat" in step)
                script = "\n".join(line[10:] for line in step.split("        run: |\n", 1)[1].splitlines()
                                   if line.startswith("          "))
                setup.write_text(script)
                for repository, update, install, calls in ((23, 0, 0, 1), (0, 29, 0, 2), (0, 0, 37, 3)):
                    with self.subTest(workflow=filename, repository=repository, update=update, install=install):
                        log = root / "calls"
                        log.write_text("")
                        environment = {**os.environ, "PATH": str(root) + os.pathsep + os.environ["PATH"],
                                       "TEX_TEST_LOG": str(log), "TEX_UPDATE_STATUS": str(update),
                                       "TEX_INSTALL_STATUS": str(install), "TEX_REPO_STATUS": str(repository)}
                        result = subprocess.run(["pwsh", "-NoProfile", "-File", str(setup)], env=environment,
                                                capture_output=True, text=True)
                        if filename == "compatibility.yml":
                            self.assertEqual(result.returncode, repository or update or install, result.stderr)
                        else:
                            self.assertNotEqual(result.returncode, 0, result.stderr)
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

    def test_minimum_r_selects_reference_libraries_before_restoration(self):
        text = WORKFLOW.read_text()
        step = next(step for step in re.findall(r"(?ms)^      - name: .*?(?=^      - |\Z)", text)
                    if "name: Select and verify reference BLAS for minimum R" in step)
        self.assertIn("if: matrix.minimum", step)
        self.assertIn("shell: bash", step)
        self.assertIn("set -euo pipefail", step)
        self.assertNotIn("|| true", step)
        for library in ("blas", "lapack"):
            self.assertIn(f"reference_{library}=/usr/lib/x86_64-linux-gnu/{library}/lib{library}.so.3", step)
            self.assertIn(f'update-alternatives --set lib{library}.so.3-x86_64-linux-gnu "$reference_{library}"', step)
            self.assertIn(f"update-alternatives --query lib{library}.so.3-x86_64-linux-gnu", step)
            self.assertIn(f"update-alternatives --set lib{library}.so-x86_64-linux-gnu /usr/lib/x86_64-linux-gnu/{library}/lib{library}.so", step)
            self.assertIn(f"update-alternatives --query lib{library}.so-x86_64-linux-gnu", step)
        self.assertIn("libblas3 liblapack3 libblas-dev liblapack-dev", text)
        self.assertIn("dpkg-query -W libblas3 liblapack3 libblas-dev liblapack-dev", step)
        self.assertIn("print(sessionInfo())", step)
        self.assertIn("minimum-r-reference-blas.txt", step)
        self.assertIn("${{ runner.temp }}/minimum-r-reference-blas.txt", text)
        self.assertIn("ubuntu-22.04-reference-blas-source-R-4.5.0-docs-", text)
        self.assertLess(text.index(step), text.index("Rscript --vanilla scripts/restore_validation.R"))

    @unittest.skipUnless(shutil.which("Rscript"), "R is needed to exercise the loaded-library preflight")
    def test_reference_blas_preflight_rejects_wrong_or_missing_libraries(self):
        step = next(step for step in re.findall(r"(?ms)^      - name: .*?(?=^      - |\Z)", WORKFLOW.read_text())
                    if "name: Select and verify reference BLAS for minimum R" in step)
        script = re.search(r"<<'RSCRIPT'\n(.*?)^          RSCRIPT$", step, re.MULTILINE | re.DOTALL).group(1)
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            expected = [root / "reference-blas", root / "reference-lapack"]
            wrong = root / "other-blas"
            for path in [*expected, wrong]:
                path.write_bytes(b"fixture")
            cases = ((expected, True), ([wrong, expected[1]], False),
                     ([expected[0], wrong], False), ([root / "missing", expected[1]], False))
            for loaded, succeeds in cases:
                with self.subTest(loaded=loaded):
                    # Mock only the runtime identities; normalization and the
                    # workflow's actual refusal logic execute inside R.
                    prelude = (f'extSoftVersion <- function() c(BLAS = {json.dumps(str(loaded[0]))})\n'
                               f'La_library <- function() {json.dumps(str(loaded[1]))}\n')
                    result = subprocess.run(["Rscript", "--vanilla", "-", *map(str, expected)],
                                            input=prelude + script, capture_output=True, text=True)
                    self.assertEqual(result.returncode == 0, succeeds, result.stdout + result.stderr)
                    if succeeds:
                        self.assertIn("Verified loaded reference BLAS and LAPACK.", result.stdout)
                    else:
                        self.assertNotIn("Verified loaded reference BLAS and LAPACK.", result.stdout)

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
