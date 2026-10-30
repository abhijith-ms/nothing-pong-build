"""Render a reviewed submission command locally; never contact Crave or GitHub."""
import argparse
import base64
import hashlib
from pathlib import Path
import re
import shlex

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('repository', help='Public GitHub OWNER/REPOSITORY')
parser.add_argument('commit', help='Full 40-character lowercase commit SHA')
args = parser.parse_args()
if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9_.-]*/[A-Za-z0-9][A-Za-z0-9_.-]*', args.repository) or not re.fullmatch(r'[0-9a-f]{40}', args.commit):
    parser.error('A repository slug and full commit SHA are required; branches and URLs are refused.')
folder = Path(__file__).resolve().parent
recipe = (folder / 'prepare-pong.sh').read_bytes()
if hashlib.sha256(recipe).hexdigest() != 'fbd740a923b706d51d348c087f997ead421313bfe75cf5bdbbcc6ff20dd9ba96':
    parser.error('Preparation recipe differs from the reviewed snapshot.')
launcher = base64.b64encode((folder / 'launch-preparation.sh').read_bytes()).decode()
worker = ("set -e -o pipefail; pong_launcher=$(printf '%s' " + shlex.quote(launcher) +
          " | base64 --decode); bash -c \"$pong_launcher\" pong-launch " +
          shlex.quote(args.repository) + ' ' + shlex.quote(args.commit))
help_gate = 'import sys; sys.exit(0 if "--disable-build-cache" in sys.stdin.read().split() else "Cache-disable option unavailable; no job submitted.")'
active_gate = 'import json,sys; jobs=json.load(sys.stdin).get("jobs_active"); isinstance(jobs,(list,dict)) or sys.exit("Unexpected active-job format; no job submitted."); print("Active personal jobs:",len(jobs)); sys.exit(bool(jobs))'
command = ('(set -e -o pipefail; cd /crave-devspaces/lineage23.2-pong; '
           'crave -n run --help | python3 -c ' + shlex.quote(help_gate) + '; '
           'crave -n list --json | python3 -c ' + shlex.quote(active_gate) + '; '
           'crave -n run --projectID 99 --no-patch --no-artifacts --detached --disable-build-cache '
           '--message ' + shlex.quote('Pinned public preparation recipe with retained worker log; no full sync or compilation') +
           ' -- ' + shlex.quote(worker) + '); pong_submission_exit=$?; '
           'printf "PONG_SHORT_SUBMISSION_CLIENT_EXIT=%s\\n" "$pong_submission_exit"; (exit "$pong_submission_exit")')
print(command)
