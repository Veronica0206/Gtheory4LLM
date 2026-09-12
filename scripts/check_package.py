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


def check_status(log, as_cran=False):
    errors = len(re.findall(r"^\* checking .*\.\.\. (?:\[[^]]+\] )?ERROR\s*$", log, re.M))
    warnings = len(re.findall(r"^\* checking .*\.\.\. (?:\[[^]]+\] )?WARNING\s*$", log, re.M))
    note_blocks = re.findall(r"^\* checking ([^\n]+)\.\.\. (?:\[[^]]+\] )?NOTE\s*\n(.*?)(?=^\* checking |^\* DONE|\Z)", log, re.M | re.S)
    allowed = []
    for title, body in note_blocks:
        lines = [line.strip() for line in body.splitlines() if line.strip()]
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
    def run(name, command, directory=work):
        result = subprocess.run(command, cwd=directory, env=environment, capture_output=True, text=True)
        (work / (name + '.log')).write_text(sanitize(result.stdout + result.stderr, work))
        report['steps'].append({'name': name, 'exit_code': result.returncode})
        print(sanitize(result.stdout + result.stderr, work), flush=True)
        if result.returncode:
            raise RuntimeError(name + ' failed')
    try:
        run('package_data', [args.rscript, '--vanilla', str(ROOT / 'scripts/build_package_data.R'), '--verify-only'], directory=ROOT)
        run('build', [r, 'CMD', 'build', '--no-build-vignettes', str(ROOT)])
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
            required = ['DESCRIPTION','NAMESPACE','R/fit.R','tests/package-smoke.R','inst/CITATION']
            for p in required:
                if package+'/'+p not in names: raise RuntimeError('Missing required package file: '+p)
        report['archive_audit'] = {'members': len(names), 'forbidden_content': [], 'required_files_present': True}
        check_command = [r, 'CMD', 'check', '--no-manual', '--library='+str(installed)]
        if args.as_cran: check_command.append('--as-cran')
        run('check', check_command + [str(archive)])
        log = (work/(package+'.Rcheck')/'00check.log').read_text()
        report['r_cmd_check'] = check_status(log, args.as_cran)
        report['r_cmd_check'].update({'as_cran':args.as_cran,'manual_built':False,'installed_tests_run':True})
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
