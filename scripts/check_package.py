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
# CRAN flags a development version's fourth component. It is right to: a
# `.9000` checkout is not a submission candidate. The line is excused only for
# a version that really is a development version, and only with that exact
# version in it, so a release candidate can never be excused by it.
DEVELOPMENT_VERSION = re.compile(r"^[0-9]+(?:\.[0-9]+)*\.9[0-9]{3,}$")


def large_version_note(version):
    return f"Version contains large components ({version})"


def maintenance_reason(value):
    """An exception must name the CRAN request; an empty flag is not authority."""
    if not isinstance(value, str) or not value.strip() or any(c in value for c in "\r\n\x00"):
        raise argparse.ArgumentTypeError("Provide a nonempty, single-line description of the CRAN maintenance request.")
    return value.strip()


def check_status(log, as_cran=False, vignettes_built=True, version=None,
                 cran_requested_maintenance=None):
    reason = None
    if cran_requested_maintenance is not None:
        reason = maintenance_reason(cran_requested_maintenance)
        if not as_cran or not isinstance(version, str) or not re.fullmatch(r"[0-9]+(?:[.-][0-9]+)+", version) or DEVELOPMENT_VERSION.fullmatch(version):
            raise RuntimeError("CRAN-requested maintenance requires --as-cran and a non-development release version.")
    errors = len(re.findall(r"^\* checking .*\.\.\. (?:\[[^]]+\] )?ERROR\s*$", log, re.M))
    warnings = len(re.findall(r"^\* checking .*\.\.\. (?:\[[^]]+\] )?WARNING\s*$", log, re.M))
    note_blocks = re.findall(r"^\* checking ([^\n]+)\.\.\. (?:\[[^]]+\] )?NOTE\s*\n(.*?)(?=^\* checking |^\* DONE|\Z)", log, re.M | re.S)
    allowed = []
    exceptions = []
    for title, body in note_blocks:
        lines = [line.strip() for line in body.splitlines() if line.strip()]
        # An archive built without vignettes carries no vignette index, and
        # --as-cran says so. Accept that one extra line only when vignettes were
        # actually skipped, so it can never excuse a real missing index.
        missing_index = not vignettes_built and lines and lines[-1] == NO_VIGNETTE_INDEX_NOTE
        if missing_index:
            lines = lines[:-1]
        development = bool(version and DEVELOPMENT_VERSION.fullmatch(version))
        maintainer = bool(lines and re.fullmatch(r"Maintainer:\s+\S.*", lines[0]))
        messages = lines[1:]
        version_message = large_version_note(version)
        cadence = [line for line in messages
                   if re.fullmatch(r"Days since last update: [0-9]+", line)]
        # A development checkout may already be known to CRAN. Its timing
        # metadata is expected only alongside this exact development-version
        # warning. A release needs the separate explicit maintenance policy.
        development_metadata = (development and version_message in messages and
                                len(messages) == len(set(messages)) and len(cadence) <= 1 and
                                all(line in ("New submission", version_message) or line in cadence
                                    for line in messages))
        maintenance_timing = (reason is not None and len(note_blocks) == 1 and not missing_index
                              and title.strip() == "CRAN incoming feasibility" and maintainer
                              and len(messages) == 1 and len(cadence) == 1)
        if maintenance_timing:
            allowed.append("CRAN incoming feasibility: " + cadence[0] +
                           "; explicitly requested CRAN maintenance")
            exceptions.append({"policy": "cran_requested_maintenance", "reason": reason,
                               "check": title.strip(), "message": cadence[0],
                               "days_since_last_update": int(cadence[0].rsplit(" ", 1)[1])})
        elif (reason is None and as_cran and title.strip() == "CRAN incoming feasibility" and maintainer and
                (messages == ["New submission"] or development_metadata)):
            allowed.append("CRAN incoming feasibility: " + "; ".join(messages) +
                           (f"; development version {version} flagged for its fourth component"
                            if development_metadata else ""))
        else:
            raise RuntimeError("R CMD check reported a substantive NOTE: " + title.strip())
    if errors or warnings or len(re.findall(r"^\* DONE\s*$", log, re.M)) != 1:
        raise RuntimeError("R CMD check reported errors/warnings or did not complete")
    # Fail closed on a summary that disagrees with the parsed check blocks.
    if re.search(r"[1-9][0-9]* (?:ERROR|WARNING)", log):
        raise RuntimeError("R CMD check failure summary")
    summaries = re.findall(r"^Status: ([^\n]+)\s*$", log, re.M)
    expected = "OK" if not note_blocks else f"{len(note_blocks)} NOTE" + ("s" if len(note_blocks) != 1 else "")
    if len(summaries) != 1 or summaries[0].strip() != expected:
        raise RuntimeError("Unrecognized or inconsistent R CMD check status summary")
    return {"errors": errors, "warnings": warnings, "notes": len(note_blocks),
            "allowed_notes": allowed, "note_exceptions": exceptions}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--rscript', default='Rscript')
    parser.add_argument('--as-cran', action='store_true',
                        help='Run CRAN incoming checks; accept only explicit submission/development metadata.')
    parser.add_argument('--cran-requested-maintenance', metavar='REASON', type=maintenance_reason,
                        help='Record a CRAN maintenance request and allow only its release timing NOTE; requires --as-cran.')
    parser.add_argument('--output-dir', type=Path,
                        default=os.environ.get('GTHEORY_PACKAGE_CHECK_DIR'),
                        help='Keep build/check artifacts here (also settable with GTHEORY_PACKAGE_CHECK_DIR).')
    args = parser.parse_args()
    if args.cran_requested_maintenance is not None and not args.as_cran:
        parser.error('--cran-requested-maintenance requires --as-cran.')
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
    if args.cran_requested_maintenance is not None:
        report['cran_requested_maintenance'] = args.cran_requested_maintenance
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
        report['r_cmd_check'] = check_status(log, args.as_cran, toolchain['available'], version,
                                             args.cran_requested_maintenance)
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
