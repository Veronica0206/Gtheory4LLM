"""Apple tool caches are isolated; actual package detritus still fails checks."""
import importlib.util
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location('toolchain_check_package', ROOT / 'scripts/check_package.py')
CHECK = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(CHECK)


class ToolchainEnvironmentTests(unittest.TestCase):
    def test_other_platforms_do_not_change_environment_or_touch_files(self):
        for platform in ('linux', 'win32'):
            with self.subTest(platform=platform), tempfile.TemporaryDirectory() as directory, \
                    patch.object(CHECK.sys, 'platform', platform), \
                    patch.object(CHECK.subprocess, 'run') as lookup:
                original = {'PATH': '/custom/bin', 'TMPDIR': '/package/tmp'}
                environment, report = CHECK.macos_toolchain_environment(original, Path(directory))
                self.assertEqual(environment, original)
                self.assertFalse(report['enabled'])
                self.assertEqual(list(Path(directory).iterdir()), [])
                lookup.assert_not_called()

    def test_custom_tools_are_preserved_and_cache_is_only_scoped_to_xcrun(self):
        with tempfile.TemporaryDirectory(prefix='toolchain space ') as directory:
            work = Path(directory)
            actual_nm = work / 'active developer tools' / 'nm'
            actual_nm.parent.mkdir()
            actual_nm.write_text('#!/bin/sh\nexit 0\n')
            actual_nm.chmod(0o755)
            selected = {'xcrun': '/usr/bin/xcrun', 'clang': '/custom/bin/clang', 'nm': '/usr/bin/nm'}
            original = {'PATH': '/custom/bin:/usr/bin', 'TMPDIR': '/package/tmp',
                        'DEVELOPER_DIR': '/selected/developer', 'SDKROOT': '/selected/sdk'}
            with patch.object(CHECK.sys, 'platform', 'darwin'), \
                    patch.object(CHECK.shutil, 'which', side_effect=lambda name, path=None: selected.get(name)), \
                    patch.object(CHECK.subprocess, 'run', return_value=subprocess.CompletedProcess(
                        [], 0, stdout=str(actual_nm) + '\n', stderr='')) as lookup:
                environment, report = CHECK.macos_toolchain_environment(original, work)
            self.assertEqual(environment['TMPDIR'], original['TMPDIR'])
            self.assertEqual(environment['DEVELOPER_DIR'], original['DEVELOPER_DIR'])
            self.assertEqual(environment['SDKROOT'], original['SDKROOT'])
            self.assertEqual(report['compiler_shims'], [])
            self.assertNotIn('_R_CHECK_THINGS_IN_TEMP_DIR_EXCLUDE_', environment)
            self.assertEqual(report['resolved_tools'], {'nm': str(actual_nm)})
            self.assertFalse((work / 'macos-toolchain/bin/clang').exists())
            self.assertEqual((work / 'macos-toolchain/bin/nm').resolve(), actual_nm.resolve())
            self.assertEqual(lookup.call_args.args[0], ['/usr/bin/xcrun', '--find', 'nm'])
            self.assertEqual(lookup.call_args.kwargs['env'],
                             {**original, 'TMPDIR': report['xcrun_cache_directory']})
            self.assertIn('exec /usr/bin/xcrun "$@"', (work / 'macos-toolchain/bin/xcrun').read_text())
            self.assertEqual(original['PATH'], '/custom/bin:/usr/bin')

    def test_apple_compiler_shim_preserves_sdk_selection_without_changing_parent(self):
        with tempfile.TemporaryDirectory() as directory:
            work = Path(directory)
            compiler = work / 'clang'
            compiler.write_text('#!/bin/sh\nexit 0\n')
            compiler.chmod(0o755)
            original = {'PATH': '/usr/bin', 'TMPDIR': '/package/tmp',
                        'DEVELOPER_DIR': '/selected/developer', 'SDKROOT': '/selected/sdk'}
            with patch.object(CHECK.sys, 'platform', 'darwin'), \
                    patch.object(CHECK.shutil, 'which', side_effect=lambda name, path=None:
                                 '/usr/bin/' + name if name in ('xcrun', 'clang') else None), \
                    patch.object(CHECK.subprocess, 'run', return_value=subprocess.CompletedProcess(
                        [], 0, stdout=str(compiler) + '\n', stderr='')):
                environment, report = CHECK.macos_toolchain_environment(original, work)
            for name in ('SDKROOT', 'DEVELOPER_DIR', 'TMPDIR'):
                self.assertEqual(environment[name], original[name])
            self.assertEqual(report['compiler_shims'], ['clang'])
            wrapper = work / 'macos-toolchain/bin/clang'
            self.assertFalse(wrapper.is_symlink())
            self.assertIn('exec /usr/bin/clang "$@"', wrapper.read_text())
            self.assertIn(report['xcrun_cache_directory'], wrapper.read_text())
            self.assertNotIn('SDKROOT=', wrapper.read_text())
            self.assertNotIn('DEVELOPER_DIR=', wrapper.read_text())

    def test_failed_tool_lookup_is_not_silently_ignored(self):
        with tempfile.TemporaryDirectory() as directory, patch.object(CHECK.sys, 'platform', 'darwin'), \
                patch.object(CHECK.shutil, 'which', side_effect=lambda name, path=None: '/usr/bin/' + name), \
                patch.object(CHECK.subprocess, 'run', return_value=subprocess.CompletedProcess(
                    [], 1, stdout='', stderr='developer tools unavailable')):
            with self.assertRaisesRegex(RuntimeError, 'Could not resolve'):
                CHECK.macos_toolchain_environment({'PATH': '/usr/bin', 'SDKROOT': '/selected/sdk'}, Path(directory))

    def test_detritus_notes_remain_substantive(self):
        for filename in ('xcrun_db', 'package-canary'):
            log = ('* checking for detritus in the temp directory ... NOTE\n'
                   f'Found the following files/directories:\n  {filename}\n'
                   '* DONE\nStatus: 1 NOTE\n')
            with self.subTest(filename=filename), self.assertRaisesRegex(RuntimeError, 'substantive NOTE'):
                CHECK.check_status(log, as_cran=True, version='1.0.0')


@unittest.skipUnless(sys.platform == 'darwin' and shutil.which('Rscript') and
                     shutil.which('xcrun') == '/usr/bin/xcrun', 'requires macOS, R and Apple developer tools')
class CompiledPackageIntegrationTests(unittest.TestCase):
    def test_strict_compiled_check_is_clean_but_package_canary_still_fails(self):
        with tempfile.TemporaryDirectory(prefix='gtheory-toolchain-integration-') as directory:
            root = Path(directory)
            package = root / 'TmpCacheProbe'
            for name in ('src', 'tests', 'man'):
                (package / name).mkdir(parents=True, exist_ok=True)
            (package / 'DESCRIPTION').write_text(
                'Package: TmpCacheProbe\nVersion: 0.0.1\nTitle: Probe Compiler Temporary Files\n'
                'Authors@R: person("Test", "Maintainer", email="test@example.org", role=c("aut", "cre"))\n'
                'Description: Compiles a small registered routine to check temporary file isolation.\n'
                'License: GPL-3\nEncoding: UTF-8\n')
            (package / 'NAMESPACE').write_text('useDynLib(TmpCacheProbe, .registration=TRUE, .fixes="C_")\n')
            (package / 'src/probe.c').write_text(
                '#include <R.h>\n#include <Rinternals.h>\n#include <R_ext/Rdynload.h>\n'
                'SEXP probe(void) { return Rf_ScalarInteger(1); }\n'
                'static const R_CallMethodDef calls[] = {{"probe", (DL_FUNC) &probe, 0}, {NULL, NULL, 0}};\n'
                'void R_init_TmpCacheProbe(DllInfo *dll) { R_registerRoutines(dll, NULL, calls, NULL, NULL); '
                'R_useDynamicSymbols(dll,FALSE); R_forceSymbols(dll,TRUE); }\n')
            (package / 'tests/check.R').write_text(
                'library(TmpCacheProbe)\nstopifnot(.Call(TmpCacheProbe:::C_probe) == 1L)\n'
                'if (identical(Sys.getenv("GTHEORY_CANARY"), "yes")) '
                'writeLines("intentional", file.path(Sys.getenv("TMPDIR"), "package-canary"))\n')
            (package / 'man/TmpCacheProbe.Rd').write_text(
                '\\name{TmpCacheProbe-package}\n\\alias{TmpCacheProbe-package}\n\\alias{TmpCacheProbe}\n'
                '\\docType{package}\n\\title{Probe Compiler Temporary Files}\n'
                '\\description{Compiles a small registered routine to check temporary file isolation.}\n')
            original = {**os.environ, 'R_PROFILE_USER': os.devnull, 'R_ENVIRON_USER': os.devnull,
                        '_R_CHECK_CRAN_INCOMING_REMOTE_': 'false', '_R_CHECK_SYSTEM_CLOCK_': 'false'}
            original.pop('SDKROOT', None)
            r = subprocess.check_output([shutil.which('Rscript'), '--vanilla', '-e',
                                         'cat(file.path(R.home("bin"), "R"))'], env=original, text=True).strip()
            environment, report = CHECK.macos_toolchain_environment(original, root)
            self.assertTrue(report['enabled'])
            # The source loader uses standalone SHLIB before R CMD check has
            # selected an SDK. Compile R.h here so missing SDK headers fail.
            standalone = root / 'standalone'
            standalone.mkdir()
            shutil.copyfile(package / 'src/probe.c', standalone / 'probe.c')
            compiled = subprocess.run([r, 'CMD', 'SHLIB', 'probe.c'], cwd=standalone,
                                      env=environment, capture_output=True, text=True, timeout=90)
            self.assertEqual(compiled.returncode, 0, compiled.stdout + compiled.stderr)
            self.assertTrue((standalone / 'probe.so').is_file())
            built = subprocess.run([r, 'CMD', 'build', str(package)], cwd=root, env=environment,
                                   capture_output=True, text=True, timeout=90)
            self.assertEqual(built.returncode, 0, built.stdout + built.stderr)
            for canary in (False, True):
                work = root / ('canary' if canary else 'clean')
                work.mkdir()
                temporary = work / 'temp'
                temporary.mkdir()
                check = subprocess.run([r, 'CMD', 'check', '--as-cran', '--no-manual',
                                        str(root / 'TmpCacheProbe_0.0.1.tar.gz')], cwd=work,
                                       env={**environment, 'TMPDIR': str(temporary),
                                            'GTHEORY_CANARY': 'yes' if canary else 'no'},
                                       capture_output=True, text=True, timeout=120)
                self.assertEqual(check.returncode, 0, check.stdout + check.stderr)
                log = (work / 'TmpCacheProbe.Rcheck/00check.log').read_text()
                self.assertNotIn('xcrun_db', log)
                if canary:
                    self.assertIn('package-canary', log)
                    with self.assertRaisesRegex(RuntimeError, 'substantive NOTE'):
                        CHECK.check_status(log, as_cran=True, version='0.0.1')
                else:
                    self.assertEqual(CHECK.check_status(log, as_cran=True, version='0.0.1')['notes'], 0)


if __name__ == '__main__':
    unittest.main()
