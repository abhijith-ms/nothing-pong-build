"""Local fixtures and fake curl/Crave only; no network or actual ROM execution."""
import base64
import hashlib
import json
import os
from pathlib import Path
import re
import shlex
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
SHA = 'fbd740a923b706d51d348c087f997ead421313bfe75cf5bdbbcc6ff20dd9ba96'
recipe = (ROOT / 'scripts/prepare-pong.sh').read_bytes()
launcher = (ROOT / 'scripts/launch-preparation.sh').read_text()
assert len(recipe) == 21968 and hashlib.sha256(recipe).hexdigest() == SHA
xml = re.search(rb"pong_manifest=\$\(cat <<'PONG_MANIFEST'\n(.*?)\nPONG_MANIFEST\n\)", recipe, re.S)[1] + b'\n'
assert (ROOT / 'manifests/pong.xml').read_bytes() == xml
subprocess.run(['bash', '-n'], input=launcher, text=True, check=True)
subprocess.run(['bash', '-n', str(ROOT / 'scripts/prepare-pong.sh')], check=True)
payload = b'#!/usr/bin/env bash\nprintf "FIXTURE_PAYLOAD_STARTED\\n"\nexit "${FIXTURE_EXIT:-0}"\n'
fixture_sha = hashlib.sha256(payload).hexdigest()
commit = 'a' * 40

with tempfile.TemporaryDirectory() as temporary:
    folder = Path(temporary).resolve()
    binary = folder / 'bin'
    binary.mkdir()
    curl = binary / 'curl'
    curl.write_text('''#!/usr/bin/env python3
import json,os,pathlib,sys
args=sys.argv[1:]
assert args[0]=='-q' and args.index('-o') < args.index('--')
assert args[-1]=='https://raw.githubusercontent.com/example/pong/'+('a'*40)+'/scripts/prepare-pong.sh'
assert '--location' not in args and args[args.index('--proto')+1]=='=https'
pathlib.Path(os.environ['FETCH_ARGS']).write_text(json.dumps(args))
if os.environ.get('FETCH_FAIL'): sys.exit(22)
data=pathlib.Path(os.environ['PAYLOAD']).read_bytes()
pathlib.Path(args[args.index('-o')+1]).write_bytes(b'x'*len(data) if os.environ.get('WRONG_HASH') else data)
''')
    curl.chmod(0o755)
    payload_path = folder / 'payload'
    payload_path.write_bytes(payload)
    for case in ('success', 'recipe_failure', 'download_failure', 'wrong_hash', 'log_failure', 'receipt_failure', 'receipt_and_recipe_failure', 'aliased_out', 'unsafe_permissions', 'bad_repository', 'branch', 'wrong_root'):
        work = folder / case
        (work / '.repo').mkdir(parents=True)
        (work / '.repo/manifest.xml').write_text('<manifest/>\n')
        code = launcher.replace('/tmp/src/android', str(work)).replace(SHA, fixture_sha).replace('PONG_PREP_BYTES=21968', 'PONG_PREP_BYTES=' + str(len(payload)))
        fetch_args = work / 'fetch-args'
        env = dict(os.environ, PATH=str(binary) + os.pathsep + os.environ['PATH'], PAYLOAD=str(payload_path), FETCH_ARGS=str(fetch_args))
        args = ['example/pong', commit]
        if case in ('recipe_failure', 'receipt_and_recipe_failure'): env['FIXTURE_EXIT'] = '37'
        if case == 'download_failure': env['FETCH_FAIL'] = '1'
        if case == 'wrong_hash': env['WRONG_HASH'] = '1'
        if case == 'aliased_out': (work / 'out').symlink_to(folder / 'outside', target_is_directory=True)
        if case == 'unsafe_permissions': (work / 'out/pong-launch-evidence').mkdir(parents=True, mode=0o755)
        if case == 'bad_repository': args[0] = 'example/pong; touch injected'
        if case == 'branch': args[1] = 'main'
        if case == 'log_failure':
            tee = binary / 'tee'
            tee.write_text('#!/bin/sh\ncat >/dev/null\nexit 74\n')
            tee.chmod(0o755)
        if case in ('receipt_failure', 'receipt_and_recipe_failure'):
            tee = binary / 'tee'
            tee.write_text('#!/bin/sh\ncat >> "$2"\nmkdir "$(dirname "$2")/result.txt"\n')
            tee.chmod(0o755)
        result = subprocess.run(['bash', '-c', code, 'fixture', *args], cwd=folder if case == 'wrong_root' else work, env=env, capture_output=True, text=True)
        if case in ('log_failure', 'receipt_failure', 'receipt_and_recipe_failure'): tee.unlink()
        attempts = list((work / 'out/pong-launch-evidence').glob('attempt-*')) if (work / 'out/pong-launch-evidence').is_dir() else []
        if case in ('aliased_out', 'unsafe_permissions', 'bad_repository', 'branch', 'wrong_root'):
            assert result.returncode != 0 and not fetch_args.exists() and not attempts, (case, result)
            continue
        assert len(attempts) == 1 and fetch_args.exists(), (case, result)
        attempt = attempts[0]
        assert attempt.stat().st_mode & 0o777 == 0o700
        assert (attempt / 'worker.log').stat().st_mode & 0o777 == 0o600
        log = (attempt / 'worker.log').read_text()
        if case in ('receipt_failure', 'receipt_and_recipe_failure'):
            assert result.returncode == (37 if case == 'receipt_and_recipe_failure' else 1)
            assert 'receipt_exit=1' in result.stdout
            continue
        receipt = (attempt / 'result.txt').read_text()
        if case == 'success':
            assert result.returncode == 0 and 'PONG_PREPARATION_COMPLETE' in log
            assert log.index('PONG_LAUNCH_BEGIN') < log.index('FIXTURE_PAYLOAD_STARTED')
            before = (attempt / 'worker.log').read_bytes()
            again = subprocess.run(['bash', '-c', code, 'fixture', *args], cwd=work, env=env, capture_output=True)
            assert again.returncode == 0 and len(list(attempt.parent.glob('attempt-*'))) == 2
            assert (attempt / 'worker.log').read_bytes() == before
        if case == 'recipe_failure': assert result.returncode == 37 and 'body_exit=37' in receipt
        if case == 'download_failure': assert result.returncode == 22 and 'FIXTURE_PAYLOAD_STARTED' not in log
        if case == 'wrong_hash': assert result.returncode != 0 and 'FIXTURE_PAYLOAD_STARTED' not in log
        if case == 'log_failure': assert result.returncode == 74 and 'log_exit=74' in receipt

    render = ROOT / 'scripts/render-command.py'
    rendered = subprocess.run([sys.executable, str(render), 'example/pong', commit], capture_output=True, text=True, check=True).stdout.strip()
    assert '\n' not in rendered
    subprocess.run(['bash', '-n'], input=rendered, text=True, check=True)
    crave = binary / 'crave'
    crave.write_text('''#!/usr/bin/env python3
import json,os,pathlib,sys
args=sys.argv[1:]
if args==['-n','run','--help']:
 print('--disable-build-cache' if not os.environ.get('NO_HELP') else '--other')
elif args==['-n','list','--json']:
 print(os.environ['ACTIVE'])
else:
 pathlib.Path(os.environ['SUBMISSION']).write_text(json.dumps(args))
 sys.exit(39)
''')
    crave.chmod(0o755)
    call = folder / 'submission'
    command = rendered.replace('cd /crave-devspaces/lineage23.2-pong', 'cd ' + shlex.quote(str(folder)))
    env = dict(os.environ, PATH=str(binary) + os.pathsep + os.environ['PATH'], ACTIVE='{"jobs_active": []}', SUBMISSION=str(call))
    result = subprocess.run(['bash', '-c', command], env=env, capture_output=True, text=True)
    assert result.returncode == 39 and 'PONG_SHORT_SUBMISSION_CLIENT_EXIT=39' in result.stdout
    args = json.loads(call.read_text())
    assert args[:4] == ['-n', 'run', '--projectID', '99']
    assert all(flag in args for flag in ('--no-patch', '--no-artifacts', '--detached', '--disable-build-cache')) and '--clean' not in args
    worker = args[-1]
    encoded = re.search(r"printf '%s' ([A-Za-z0-9+/=]+) \| base64 --decode", worker)[1]
    assert base64.b64decode(encoded, validate=True) == launcher.encode()
    assert len(worker.encode()) < 8192
    work = folder / 'rendered-worker'
    (work / '.repo').mkdir(parents=True)
    (work / '.repo/manifest.xml').write_text('<manifest/>\n')
    code = launcher.replace('/tmp/src/android', str(work)).replace(SHA, fixture_sha).replace('PONG_PREP_BYTES=21968', 'PONG_PREP_BYTES=' + str(len(payload)))
    fixture_worker = worker.replace(encoded, base64.b64encode(code.encode()).decode())
    fixture_env = dict(env, PAYLOAD=str(payload_path), FETCH_ARGS=str(work / 'fetch-args'))
    result = subprocess.run(['bash', '-c', fixture_worker], cwd=work, env=fixture_env, capture_output=True, text=True)
    assert result.returncode == 0 and 'PONG_PREPARATION_COMPLETE' in result.stdout
    assert 'FIXTURE_PAYLOAD_STARTED' in result.stdout
    for extra in ({'ACTIVE':'{"jobs_active":[1]}'}, {'ACTIVE':'{}'}, {'NO_HELP':'1'}):
        call.unlink(missing_ok=True)
        result = subprocess.run(['bash', '-c', command], env=dict(env, **extra), capture_output=True, text=True)
        assert result.returncode != 0 and not call.exists()
    for repo, revision in [('example/pong;id', commit), ('example/pong', 'main')]:
        assert subprocess.run([sys.executable, str(render), repo, revision], capture_output=True).returncode != 0
print('Local launcher checks passed: pinned fetch/hash refusal, private retained logs, source-path refusal, exact recipe, exit propagation, short command and active-job/help gates.')
