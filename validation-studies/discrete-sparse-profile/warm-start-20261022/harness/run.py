"""Run exactly one optimizer on a frozen synthetic 21,600-row ordinal panel."""
from pathlib import Path
import argparse
import hashlib
import json
import os
import shutil
import subprocess
from datetime import datetime, timezone

HERE = Path(__file__).resolve().parent
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--source', type=Path, required=True)
parser.add_argument('--output', type=Path, required=True)
parser.add_argument('--optimizer', choices=['L-BFGS-B', 'nlminb'], required=True)
args = parser.parse_args()
source = args.source.resolve(strict=True)
output = args.output.resolve()
output.mkdir(parents=True, exist_ok=False)
lock = HERE.parent / 'scale-qualification-20261021' / '.running.lock'
lock.mkdir()
(lock / 'owner.json').write_text(json.dumps({'pid': os.getpid(), 'output': str(output)}))
files = [source / x for x in ['DESCRIPTION', 'NAMESPACE', 'load_functions.R']]
files += sorted((source / 'R').glob('*.R'))
snapshot = output / 'source-snapshot'
hashes = {}
for file in files:
    relative = file.relative_to(source)
    target = snapshot / relative
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(file, target)
    hashes[str(relative)] = hashlib.sha256(target.read_bytes()).hexdigest()
shutil.copyfile(HERE / 'run.R', output / 'run.R')
threads = {name: '1' for name in ['OMP_NUM_THREADS', 'OPENBLAS_NUM_THREADS',
  'MKL_NUM_THREADS', 'VECLIB_MAXIMUM_THREADS', 'BLIS_NUM_THREADS', 'RCPP_PARALLEL_NUM_THREADS']}
record = {'started': datetime.now(timezone.utc).isoformat(), 'sources': hashes,
          'optimizer': args.optimizer, 'threads': threads,
          'runner_sha256': hashlib.sha256((output/'run.R').read_bytes()).hexdigest(),
          'timeout_seconds': 7200, 'scope': 'Synthetic characterization only'}
(output / 'started.json').write_text(json.dumps(record, indent=2)+'\n')
env = {**os.environ, **threads, 'GTHEORY_DISCRETE_SPECIMEN_DIR': str(output/'specimens')}
status = None
with (output / 'console.log').open('x') as log:
    try:
        status = subprocess.run(['Rscript', '--vanilla', str(output/'run.R'),
          str(snapshot), str(output), args.optimizer], env=env, stdout=log,
          stderr=subprocess.STDOUT, timeout=7200).returncode
    except subprocess.TimeoutExpired:
        status = 'timeout'
(output/'completed.json').write_text(json.dumps({'completed': datetime.now(timezone.utc).isoformat(),
  'process_exit_code': status, 'success_is_not_fit_acceptance': True}, indent=2)+'\n')
(lock/'owner.json').unlink()
lock.rmdir()
print(json.dumps({'output': str(output), 'status': status}), flush=True)
raise SystemExit(0 if status == 0 else 1)
