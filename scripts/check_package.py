"""Build, audit, and check the installed R package in an isolated workspace."""
from __future__ import annotations
import argparse
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import subprocess
import tarfile
import tempfile

ROOT = Path(__file__).resolve().parents[1]

def sanitize(value, work):
    if isinstance(value, dict): return {key: sanitize(item, work) for key, item in value.items()}
    if isinstance(value, list): return [sanitize(item, work) for item in value]
    if isinstance(value, str):
        for path, label in ((ROOT, "<source>"), (work, "<validation>"), (Path.home(), "<home>")):
            value = value.replace(str(path), label).replace(str(path).replace("\\", "/"), label)
    return value


def vignette_toolchain(rscript, environment):
    """Report whether knitr, rmarkdown, and pandoc are all usable here.

    This decides only whether the gate can build and check vignettes. It is not
    a statement about the package's own dependencies, which never include them.
    """
    probe = ('cat(paste(c('
             'if (requireNamespace("knitr", quietly = TRUE)) "knitr", '
             'if (requireNamespace("rmarkdown", quietly = TRUE)) "rmarkdown", '
             'if (requireNamespace("rmarkdown", quietly = TRUE) && '
             'rmarkdown::pandoc_available()) "pandoc"), collapse = ","))')
    try:
        found = subprocess.run([rscript, '--vanilla', '-e', probe], env=environment,
                               capture_output=True, text=True, timeout=300)
    except (OSError, subprocess.SubprocessError) as failure:
        return {'available': False, 'present': [], 'reason': 'probe failed: ' + str(failure)}
    present = [name for name in found.stdout.strip().split(',') if name]
    missing = [name for name in ('knitr', 'rmarkdown', 'pandoc') if name not in present]
    return {'available': not missing, 'present': present,
            'reason': '' if not missing else 'missing ' + ', '.join(missing)}


NO_VIGNETTE_INDEX_NOTE = "Package has a VignetteBuilder field but no prebuilt vignette index."


def check_status(log, as_cran=False, vignettes_built=True):
    errors = len(re.findall(r"^\* checking .*\.\.\. (?:\[[^]]+\] )?ERROR\s*$", log, re.M))
    warnings = len(re.findall(r"^\* checking .*\.\.\. (?:\[[^]]+\] )?WARNING\s*$", log, re.M))
    note_blocks = re.findall(r"^\* checking ([^\n]+)\.\.\. (?:\[[^]]+\] )?NOTE\s*\n(.*?)(?=^\* checking |^\* DONE|\Z)", log, re.M | re.S)
    allowed = []
    for title, body in note_blocks:
        lines = [line.strip() for line in body.splitlines() if line.strip()]
        # An archive built without vignettes carries no vignette index, and
        # --as-cran says so. Accept that one extra line only when vignettes were
        # actually skipped, so it can never excuse a real missing index.
        if not vignettes_built and lines and lines[-1] == NO_VIGNETTE_INDEX_NOTE:
            lines = lines[:-1]
        if (as_cran and title.strip() == "CRAN incoming feasibility" and
                len(lines) == 2 and lines[0].startswith("Maintainer:") and lines[1] == "New submission"):
            allowed.append("CRAN incoming feasibility: New submission")
        else:
            raise RuntimeError("R CMD check reported a substantive NOTE: " + title.strip())
    if errors or warnings or "* DONE" not in log:
        raise RuntimeError("R CMD check reported errors/warnings or did not complete")
    # Fail closed on a summary that disagrees with the parsed check blocks.
    if re.search(r"[1-9][0-9]* (?:ERROR|WARNING)", log):
        raise RuntimeError("R CMD check failure summary")
    if re.search(r"[1-9][0-9]* NOTE", log) and not note_blocks:
        raise RuntimeError("Unrecognized R CMD check NOTE summary")
    return {"errors": errors, "warnings": warnings, "notes": len(note_blocks), "allowed_notes": allowed}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--rscript', default='Rscript')
    parser.add_argument('--as-cran', action='store_true', help='Run CRAN incoming checks; only the explicit new-submission NOTE is expected.')
    parser.add_argument('--output-dir', type=Path,
                        default=os.environ.get('GTHEORY_PACKAGE_CHECK_DIR'),
                        help='Keep build/check artifacts here (also settable with GTHEORY_PACKAGE_CHECK_DIR).')
    args = parser.parse_args()
    work = args.output_dir.resolve() if args.output_dir else Path(tempfile.mkdtemp(prefix='gtheory-package-check-'))
    work.mkdir(parents=True, exist_ok=True)
    installed = work / 'library'; installed.mkdir(exist_ok=True)
    environment = os.environ.copy()
    environment['R_PROFILE_USER'] = os.devnull
    environment['R_ENVIRON_USER'] = os.devnull
    runtime_script = work / 'runtime.R'
    runtime_script.write_bytes(
        'd <- read.dcf(commandArgs(TRUE)[1L]); cat(file.path(R.home("bin"), if (.Platform$OS.type == "windows") "R.exe" else "R"), d[1L, "Package"], d[1L, "Version"], sep="\\n")'.encode('utf-8'))
    r, package, version = subprocess.check_output([
        args.rscript, '--vanilla', str(runtime_script), str(ROOT / 'DESCRIPTION')],
        env=environment, text=True).strip().splitlines()
    report = {'package': package, 'version': version, 'workspace': str(work), 'steps': [], 'success': False}
    def run(name, command, directory=work, extra_env=None):
        step_environment = {**environment, **(extra_env or {})}
        result = subprocess.run(command, cwd=directory, env=step_environment, capture_output=True, text=True)
        (work / (name + '.log')).write_text(sanitize(result.stdout + result.stderr, work))
        report['steps'].append({'name': name, 'exit_code': result.returncode})
        print(sanitize(result.stdout + result.stderr, work), flush=True)
        if result.returncode:
            raise RuntimeError(name + ' failed')
    try:
        run('package_data', [args.rscript, '--vanilla', str(ROOT / 'scripts/build_package_data.R'), '--verify-only'], directory=ROOT)
        # The distributed archive contains built vignettes, and the installed
        # tutorial script and HTML are vignette build products. Build them here
        # whenever the toolchain is present so the gate checks the real archive.
        # knitr, rmarkdown, and pandoc are build-time tools, not runtime model
        # dependencies, so a restored library that pins only the numerical stack
        # may not carry them. Report which path ran instead of failing closed on
        # a missing documentation toolchain.
        toolchain = vignette_toolchain(args.rscript, environment)
        (work / 'vignette_toolchain.log').write_text(json.dumps(toolchain, indent=2))
        report['vignette_toolchain'] = toolchain
        build_command = [r, 'CMD', 'build', str(ROOT)]
        if not toolchain['available']:
            build_command.insert(3, '--no-build-vignettes')
            print('Vignette toolchain unavailable (' + toolchain['reason'] +
                  '); building and checking without vignettes.', flush=True)
        run('build', build_command)
        archive = work / f'{package}_{version}.tar.gz'
        if not archive.is_file(): raise RuntimeError('Expected package source archive: '+str(archive))
        with tarfile.open(archive) as stream:
            names = stream.getnames()
            paths = [PurePosixPath(p) for p in names]
            forbidden = {'reference','companion','review','provenance','planning','.git','.github','scripts','load_functions.R','artifacts'}
            violations = [str(p) for p in paths if len(p.parts)>1 and p.parts[1] in forbidden]
            violations += [str(p) for p in paths if len(p.parts)==2 and p.suffix.lower() in {'.zip','.patch'}]
            violations += [str(p) for p in paths if p.is_absolute() or '..' in p.parts]
            if violations: raise RuntimeError('Non-package content in build: '+str(violations))
            required = ['DESCRIPTION','NAMESPACE','R/fit.R','tests/package-smoke.R','inst/CITATION',
                        'vignettes/LLM-workflow.Rmd']
            if toolchain['available']:
                required += ['inst/doc/LLM-workflow.R', 'inst/doc/LLM-workflow.html']
            for p in required:
                if package+'/'+p not in names: raise RuntimeError('Missing required package file: '+p)
        report['archive_audit'] = {'members': len(names), 'forbidden_content': [], 'required_files_present': True}
        check_command = [r, 'CMD', 'check', '--no-manual', '--library='+str(installed)]
        check_environment = {}
        if not toolchain['available']:
            check_command.append('--ignore-vignettes')
            # knitr and rmarkdown are suggested only to build the vignette. When
            # they are absent R CMD check fails the dependency check outright,
            # which would report a missing documentation toolchain as a package
            # defect. Checking without them is the documented way to run in that
            # environment; the report records that it happened.
            check_environment['_R_CHECK_FORCE_SUGGESTS_'] = 'false'
        if args.as_cran: check_command.append('--as-cran')
        run('check', check_command + [str(archive)], extra_env=check_environment)
        log = (work/(package+'.Rcheck')/'00check.log').read_text()
        report['r_cmd_check'] = check_status(log, args.as_cran, toolchain['available'])
        report['r_cmd_check'].update({'as_cran':args.as_cran,'manual_built':False,'installed_tests_run':True,'vignettes_built':toolchain['available'],
                                     'suggests_forced':toolchain['available']})
        report['archive'] = str(archive)
        report['success'] = True
    except Exception as error:
        report['error'] = str(error)
    for pattern in ('*.log', '*.Rout', '*.Rout.fail'):
        for path in work.glob('*.Rcheck/**/' + pattern):
            path.write_text(sanitize(path.read_text(errors='replace'), work))
    report = sanitize(report, work)
    (work/'package_validation.json').write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps(report,indent=2),flush=True)
    return 0 if report['success'] else 1

if __name__ == '__main__':
    raise SystemExit(main())
