#!/usr/bin/env bash
# Preparation only: verified WebView restoration and six-project migration; no full sync or compilation.
# Run only inside a queued crave run job, from /tmp/src/android.
set -e -o pipefail

fail() { printf '%s\n' "$*" >&2; exit 1; }
[[ $# -eq 0 || ( $# -eq 1 && $1 == --diagnose-only ) ]] ||
    fail 'Usage: build-pong.sh [--diagnose-only]'
[[ "$PWD" == /tmp/src/android && -f .repo/manifest.xml ]] ||
    fail 'Worker source root required: /tmp/src/android. Do not run in Devspace or on the PC.'
command -v repo >/dev/null || fail 'Use the worker-provided repo tool; do not install it here.'
unset USE_CCACHE CCACHE_EXEC
export LINEAGE_BUILDTYPE=UNOFFICIAL

printf '%s\n' 'Stage: early worker environment'
date -u
pwd
id
repo --version
git --version
python3 --version
git -C .repo/manifests rev-parse HEAD
nproc
free -h
df -h .
pong_project_count=$(repo list -p | wc -l)
printf 'Manifest project count: %s\n' "$pong_project_count"

pong_manifest=$(cat <<'PONG_MANIFEST'
<?xml version="1.0" encoding="UTF-8"?>
<manifest>
  <remote name="pong-public" fetch="https://github.com/" />
  <project name="LineageOS/android_device_nothing_Pong" path="device/nothing/Pong" remote="pong-public" revision="4c8a91e95540b0d075a66f18b4fb61092d99d510" upstream="refs/heads/lineage-23.2" />
  <project name="LineageOS/android_kernel_nothing_sm8475" path="kernel/nothing/sm8475" remote="pong-public" revision="4ec5491f6b5fd8776207a2a453d6b98b1928de7a" upstream="refs/heads/lineage-23.2" />
  <project name="LineageOS/android_kernel_nothing_sm8475-devicetrees" path="kernel/nothing/sm8475-devicetrees" remote="pong-public" revision="4b06eb8d7c0bbc548a5f3336ac201e4fb29ccaf8" upstream="refs/heads/lineage-23.2" />
  <project name="LineageOS/android_kernel_nothing_sm8475-modules" path="kernel/nothing/sm8475-modules" remote="pong-public" revision="8bb924988b7a96ff5791a5c455588b22c211b58d" upstream="refs/heads/lineage-23.2" />
  <project name="TheMuppets/proprietary_vendor_nothing_Pong" path="vendor/nothing/Pong" remote="pong-public" revision="1dc6e7ff9f25c8e7028132e20536bc9e6de3d56d" upstream="refs/heads/lineage-23.2" />
</manifest>
PONG_MANIFEST
)

# PONG_WEBVIEW_REPAIR_BEGIN
if [[ ${1-} != --diagnose-only ]]; then
    printf '%s\n' 'Stage: verify and materialize one missing WebView APK'
    python3 -I - <<'PONG_WEBVIEW_MATERIALIZE'
"""Worker-only materialization of one verified APK from the existing LFS store."""
import hashlib
import os
from pathlib import Path
import shutil
import stat
import subprocess

DATA = {'manifest': '9776e518de506f610218c4caa6c1fddff46873af', 'head': '394b243c2796e36580dd8bae7822609e1c01b1ff', 'blob': '5607dc8dab8ac361a9e2776fb70f5bc4a9deae5a', 'oid': '3b98460ccd41b2a1851c5a46e6dec6f86f1d14302ff2fa4deeb1d781e32f89a4', 'bytes': 267260603}
root = Path('/tmp/src/android').resolve(strict=True)
worktree = root / 'external/chromium-webview/prebuilt/arm64'
gitdir = root / '.repo/projects/external/chromium-webview/prebuilt/arm64.git'
apk = worktree / 'webview.apk'
media = gitdir / 'lfs/objects' / DATA['oid'][:2] / DATA['oid'][2:4] / DATA['oid']
env = dict(os.environ, GIT_OPTIONAL_LOCKS='0', GIT_NO_LAZY_FETCH='1',
           GIT_TERMINAL_PROMPT='0', GIT_CONFIG_NOSYSTEM='1',
           GIT_CONFIG_GLOBAL='/dev/null', GIT_ATTR_SOURCE='HEAD')

def require(condition, message):
    if not condition:
        raise SystemExit(message)

def git(*args, cwd=worktree):
    result = subprocess.run(
        ['git', '--no-optional-locks', '-c', 'core.fsmonitor=false',
         '-c', 'core.hooksPath=/dev/null', '-c', 'protocol.allow=never',
         '-c', 'lfs.storage=' + str(gitdir / 'lfs'), '-C', str(cwd), *args],
        env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=120)
    require(result.returncode == 0, 'WebView Git/LFS command failed (exit %s); inspect worker evidence before retry.' % result.returncode)
    return result.stdout

def identities():
    require(git('rev-parse', 'HEAD', cwd=root / '.repo/manifests').strip().decode() == DATA['manifest'], 'Manifest changed; no APK restoration')
    require(git('rev-parse', 'HEAD').strip().decode() == DATA['head'], 'WebView HEAD changed; no APK restoration')
    expected = ('100644 blob ' + DATA['blob'] + '\twebview.apk\0').encode()
    require(git('ls-tree', '-z', 'HEAD', '--', 'webview.apk') == expected, 'WebView HEAD entry changed')
    expected = ('100644 ' + DATA['blob'] + ' 0\twebview.apk\0').encode()
    require(git('ls-files', '--stage', '-z', '--', 'webview.apk') == expected, 'WebView index changed; preserve staged work')
    require(git('check-attr', '--cached', '-z', 'filter', '--', 'webview.apk') == b'webview.apk\0filter\0lfs\0', 'Expected cached LFS attribute')
    pointer = ('version https://git-lfs.github.com/spec/v1\noid sha256:' + DATA['oid'] + '\nsize ' + str(DATA['bytes']) + '\n').encode()
    require(git('cat-file', 'blob', DATA['blob']) == pointer, 'LFS pointer changed')

def verified(path):
    require(path.resolve(strict=True) == path, 'Aliased APK/cache path; preserve and review')
    before = path.lstat()
    require(stat.S_ISREG(before.st_mode) and stat.S_IMODE(before.st_mode) == 0o644, 'Unexpected APK/cache type or mode')
    require(before.st_size == DATA['bytes'], 'APK/cache size differs; preserve and review')
    with os.fdopen(os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK), 'rb') as stream:
        opened = os.fstat(stream.fileno())
        require((opened.st_dev, opened.st_ino, opened.st_mode) == (before.st_dev, before.st_ino, before.st_mode), 'File changed before read')
        digest = hashlib.file_digest(stream, 'sha256').hexdigest()
    after = path.lstat()
    require(all(getattr(before, key) == getattr(after, key) for key in (
        'st_dev', 'st_ino', 'st_mode', 'st_size', 'st_mtime_ns', 'st_ctime_ns')), 'File changed during read')
    require(digest == DATA['oid'], 'APK/cache SHA-256 differs; preserve and review')

require(Path.cwd().resolve() == root and (root / '.repo/manifest.xml').is_file(), 'Worker source root required')
require(worktree.resolve(strict=True) == worktree and gitdir.resolve(strict=True) == gitdir, 'Aliased WebView repository')
require((worktree / '.git').is_symlink() and (worktree / '.git').resolve(strict=True) == gitdir, 'Unexpected WebView Git directory')
require(not os.path.lexists(gitdir / 'commondir'), 'Separate common directory requires review')
objects = (gitdir / 'objects').resolve(strict=True)
require(objects.is_relative_to(root), 'Object store outside checkout')
for name in ('alternates', 'http-alternates'):
    path = objects / 'info' / name
    require(not os.path.lexists(path) or (path.is_file() and not path.is_symlink() and path.stat().st_size == 0), 'Object alternates require review')
identities()
verified(media)
if os.path.lexists(apk):
    verified(apk)
    print('WebView APK already matches verified content; no restoration needed.')
else:
    require(shutil.disk_usage(worktree).free >= DATA['bytes'] + 1024 * 1024, 'Insufficient space for the missing APK')
    version = git('lfs', 'version').decode().strip()
    require(version.startswith('git-lfs/') and '\n' not in version, 'Unexpected Git LFS version response')
    print(version, flush=True)
    # checkout uses the existing local store; it does not download or overwrite modified files.
    git('lfs', 'checkout', 'webview.apk')
    verified(apk)
    print('Missing WebView APK materialized and size/SHA-256 verified.')
identities()
verified(media)
print('WebView identities and cached media remain verified; continuing to the unchanged source guards.')
PONG_WEBVIEW_MATERIALIZE
fi
# PONG_WEBVIEW_REPAIR_END
# Preserve existing work: reject unknown overlays and dirty source repositories.
printf '%s\n' 'Stage: pre-sync repository checks'
shopt -s nullglob dotglob
for pong_overlay in .repo/local_manifests/*; do
    [[ "$pong_overlay" == .repo/local_manifests/pong.xml && -f "$pong_overlay" && ! -L "$pong_overlay" ]] ||
        fail "Review existing overlay before continuing: $pong_overlay"
    cmp -s "$pong_overlay" <(printf '%s\n' "$pong_manifest") || fail 'Existing pong.xml differs; preserve and review it.'
done
shopt -u dotglob
git -C .repo/manifests diff --quiet
git -C .repo/manifests diff --cached --quiet
# Keep stderr and its project header when a repository check fails.
repo forall -p -v -e -c 'changes=$(git --no-optional-locks status --porcelain=v1 --untracked-files=all) || { result=$?; printf "git status failed (exit %s)\n" "$result" >&2; exit "$result"; }; test -z "$changes" || { echo "Review local changes in $REPO_PATH" >&2; printf "%s\n" "$changes" >&2; git --no-pager --no-optional-locks diff --no-ext-diff --no-textconv --summary >&2; git --no-pager --no-optional-locks diff --cached --no-ext-diff --no-textconv --summary >&2; exit 1; }'

if [[ ${1-} == --diagnose-only ]]; then
    printf '%s\n' 'Diagnostic preflight passed; no synchronization or compilation requested.'
    exit 0
fi

# Reuse the existing cache; pin the official manifest without deleting sources.
printf '%s\n' 'Stage: initialize pinned manifest'
pong_manifest_revision=9776e518de506f610218c4caa6c1fddff46873af
repo init -u https://github.com/LineageOS/android.git -b "$pong_manifest_revision" --git-lfs --depth 1
[[ "$(git -C .repo/manifests rev-parse HEAD)" == "$pong_manifest_revision" ]] || fail 'Unexpected manifest revision.'
mkdir -p .repo/local_manifests
printf '%s\n' "$pong_manifest" > .repo/local_manifests/pong.xml
printf '%s\n' 'Stage: verify preserved migration inputs'
python3 -I - <<'PONG_MIGRATION_PRECHECK'
"""Read the fixed migration backup scope; report counts/hashes, never file names/content."""
import hashlib
import json
import os
from pathlib import Path
import stat
import sys

SCOPE = (
    'external/conscrypt', 'system/ca-certificates', '.repo/repo/hooks',
    '.repo/projects/external/conscrypt.git',
    '.repo/projects/system/ca-certificates.git',
    '.repo/project-objects/platform/external/conscrypt.git',
    '.repo/project-objects/platform/system/ca-certificates.git',
)


def inventory(root):
    root = Path(root).resolve(strict=True)
    roots = [root / name for name in SCOPE]
    report = dict(files=0, directories=0, symlinks=0, bytes=0,
                  absolute_links=0, outside_scope_links=0, special_files=0,
                  nonempty_git_pointers=0, top_level_aliases=0)
    digest = hashlib.sha256()
    for base in roots:
        if base.resolve(strict=True) != base:
            report['top_level_aliases'] += 1
        pending = [base]
        while pending:
            path = pending.pop()
            before = path.lstat()
            mode = stat.S_IFMT(before.st_mode)
            digest.update(os.fsencode(str(path.relative_to(root))) + b'\0')
            digest.update(f'{mode}:{stat.S_IMODE(before.st_mode)}:'.encode())
            if stat.S_ISLNK(before.st_mode):
                report['symlinks'] += 1
                target = os.readlink(path)
                digest.update(os.fsencode(target))
                report['absolute_links'] += os.path.isabs(target)
                resolved = path.resolve(strict=False)
                report['outside_scope_links'] += not any(
                    resolved == item or item in resolved.parents for item in roots)
            elif stat.S_ISDIR(before.st_mode):
                report['directories'] += 1
                pending.extend(sorted(path.iterdir(), reverse=True))
            elif stat.S_ISREG(before.st_mode):
                report['files'] += 1
                report['bytes'] += before.st_size
                flags = os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK
                with os.fdopen(os.open(path, flags), 'rb') as stream:
                    opened = os.fstat(stream.fileno())
                    assert (opened.st_dev, opened.st_ino, opened.st_mode) == (
                        before.st_dev, before.st_ino, before.st_mode), 'File identity changed'
                    digest.update(hashlib.file_digest(stream, 'sha256').digest())
                if '.repo' in path.relative_to(root).parts and path.name in (
                        'alternates', 'http-alternates', 'commondir', 'gitdir'):
                    report['nonempty_git_pointers'] += before.st_size != 0
            else:
                report['special_files'] += 1
            after = path.lstat()
            fields = ('st_dev', 'st_ino', 'st_mode', 'st_size', 'st_mtime_ns', 'st_ctime_ns')
            assert all(getattr(before, key) == getattr(after, key) for key in fields), 'Entry changed during read'
            digest.update(b'\0')
    report['content_metadata_sha256'] = digest.hexdigest()
    report['scope_closed'] = not any(report[key] for key in (
        'absolute_links', 'outside_scope_links', 'special_files',
        'nonempty_git_pointers', 'top_level_aliases'))
    return report



import subprocess
import xml.etree.ElementTree as ET
DATA = {'manifest': '9776e518de506f610218c4caa6c1fddff46873af', 'repo_project_sha256': '27dc65a8f17489216cebda794e4d767207f41a54821e957da813f7d2f729611a', 'backups': [{'scope': ['external/conscrypt', 'system/ca-certificates', '.repo/repo/hooks', '.repo/projects/external/conscrypt.git', '.repo/projects/system/ca-certificates.git', '.repo/project-objects/platform/external/conscrypt.git', '.repo/project-objects/platform/system/ca-certificates.git'], 'fingerprint': '396a8e17afebff651dded142c9c33a912851fc89fe71bcccebdd5a560619bcc1', 'archive_sha256': '97d8c7c497fdc75ec17f2be880a609f89be7e18a51562f6d50e9090966bee620'}, {'scope': ['packages/apps/ManagedProvisioning', 'packages/services/BuiltInPrintService', 'system/libfmq', 'system/libufdt', '.repo/repo/hooks', '.repo/projects/packages/apps/ManagedProvisioning.git', '.repo/projects/packages/services/BuiltInPrintService.git', '.repo/projects/system/libfmq.git', '.repo/projects/system/libufdt.git', '.repo/project-objects/platform/packages/apps/ManagedProvisioning.git', '.repo/project-objects/platform/packages/services/BuiltInPrintService.git', '.repo/project-objects/platform/system/libfmq.git', '.repo/project-objects/platform/system/libufdt.git', 'build/soong/scripts/system-clang-format'], 'fingerprint': '9e47e4484cdc18553aa91a5f11362ad8294d607022a27303292b2bcfa9ab1ef8', 'archive_sha256': 'bac3dcc28c90086cf407990bf7358382d8f8d8ce0217cad3353269fec2ebe714'}], 'owners': {'external/conscrypt': [1000, 1000], 'system/ca-certificates': [1000, 1000], '.repo/repo/hooks': [1000, 1000], '.repo/projects/external/conscrypt.git': [1000, 1000], '.repo/projects/system/ca-certificates.git': [1000, 1000], '.repo/project-objects/platform/external/conscrypt.git': [1000, 1000], '.repo/project-objects/platform/system/ca-certificates.git': [1000, 1000], 'packages/apps/ManagedProvisioning': [1000, 1000], 'packages/services/BuiltInPrintService': [1000, 1000], 'system/libfmq': [1000, 1000], 'system/libufdt': [1000, 1000], '.repo/projects/packages/apps/ManagedProvisioning.git': [1000, 1000], '.repo/projects/packages/services/BuiltInPrintService.git': [1000, 1000], '.repo/projects/system/libfmq.git': [1000, 1000], '.repo/projects/system/libufdt.git': [1000, 1000], '.repo/project-objects/platform/packages/apps/ManagedProvisioning.git': [1000, 1000], '.repo/project-objects/platform/packages/services/BuiltInPrintService.git': [1000, 1000], '.repo/project-objects/platform/system/libfmq.git': [1000, 1000], '.repo/project-objects/platform/system/libufdt.git': [1000, 1000], 'build/soong/scripts/system-clang-format': [1000, 1000]}, 'projects': [{'path': 'external/conscrypt', 'head': '771401e90ac8728487b599e5b87e0628ed528ea0', 'old': 'platform/external/conscrypt', 'new': 'LineageOS/android_external_conscrypt'}, {'path': 'packages/apps/ManagedProvisioning', 'head': 'eb8b8a853a763580c03c0dd1fcd9da77ef8abd89', 'old': 'platform/packages/apps/ManagedProvisioning', 'new': 'LineageOS/android_packages_apps_ManagedProvisioning'}, {'path': 'packages/services/BuiltInPrintService', 'head': 'c66887ef3e9dd9308fbc09baab912162ec0d3035', 'old': 'platform/packages/services/BuiltInPrintService', 'new': 'LineageOS/android_packages_services_BuiltInPrintService'}, {'path': 'system/ca-certificates', 'head': '2a664186cce10593cd726fa682f6236becff1589', 'old': 'platform/system/ca-certificates', 'new': 'LineageOS/android_system_ca-certificates'}, {'path': 'system/libfmq', 'head': '99d47692bc5fb1a967a0e5345164ffd9b4cf0c5b', 'old': 'platform/system/libfmq', 'new': 'LineageOS/android_system_libfmq'}, {'path': 'system/libufdt', 'head': '10c6b5f81069d6d78c7ef3833458f4d51d02e2a6', 'old': 'platform/system/libufdt', 'new': 'LineageOS/android_system_libufdt'}]}

def require(condition, message):
    if not condition:
        raise SystemExit(message)

root = Path('/tmp/src/android').resolve(strict=True)
require(Path.cwd().resolve() == root, 'Worker root required; migration stopped')
require(sys.flags.optimize == 0, 'Unoptimized guard required; migration stopped')
require(hashlib.sha256((root / '.repo/repo/project.py').read_bytes()).hexdigest() == DATA['repo_project_sha256'], 'Repo implementation changed; review recovery before migration')
manifest_head = subprocess.check_output(['git', '--no-optional-locks', '-C', str(root / '.repo/manifests'), 'rev-parse', 'HEAD'], text=True).strip()
require(manifest_head == DATA['manifest'], 'Unexpected manifest; migration stopped')
entries = ET.parse(root / '.repo/manifests/default.xml').findall('project')
for project in DATA['projects']:
    matches = [entry for entry in entries if entry.get('path') == project['path']]
    require(len(matches) == 1 and matches[0].get('name') == project['new'], 'Manifest mapping changed: ' + project['path'])
for backup in DATA['backups']:
    SCOPE = tuple(backup['scope'])
    actual = inventory(root)
    require(actual['scope_closed'] and actual['content_metadata_sha256'] == backup['fingerprint'], 'Source differs from verified PC preservation; migration stopped')
for relative, owner in DATA['owners'].items():
    path = root / relative
    require(path.resolve(strict=True) == path, 'Aliased preservation root; migration stopped')
    info = path.lstat()
    require([info.st_uid, info.st_gid] == owner, 'Source ownership changed; migration stopped')
for project in DATA['projects']:
    relative = project['path']
    worktree = root / relative
    gitdir = root / '.repo/projects' / (relative + '.git')
    require((worktree / '.git').is_symlink() and (worktree / '.git').resolve(strict=True) == gitdir, 'Unexpected Git directory: ' + relative)
    head = subprocess.check_output(['git', '--no-optional-locks', '-c', 'core.fsmonitor=false', '-c', 'core.hooksPath=/dev/null', '-C', str(worktree), 'rev-parse', 'HEAD'], text=True).strip()
    require(head == project['head'], 'Source HEAD moved: ' + relative)
    for name in ('hooks', 'objects', 'rr-cache'):
        old = root / '.repo/project-objects' / (project['old'] + '.git') / name
        new = root / '.repo/project-objects' / (project['new'] + '.git') / name
        require((gitdir / name).is_symlink() and (gitdir / name).resolve(strict=True) == old and old.resolve(strict=True) == old, 'Unexpected old store: ' + relative)
        require(new.resolve(strict=False) == new, 'Aliased new store; migration stopped: ' + relative)
        require(not os.path.lexists(new), 'New store already exists; review current state: ' + relative)
print('Preservation fingerprints, manifest, repo implementation and six deletion boundaries verified.')
PONG_MIGRATION_PRECHECK
printf '%s\n' 'Stage: migrate six reviewed project mappings'
repo sync -c -j1 --fail-fast --force-sync --no-clone-bundle --no-tags external/conscrypt packages/apps/ManagedProvisioning packages/services/BuiltInPrintService system/ca-certificates system/libfmq system/libufdt
python3 -I - <<'PONG_MIGRATION_POSTCHECK'
from pathlib import Path
PROJECTS = [{'path': 'external/conscrypt', 'new': 'LineageOS/android_external_conscrypt'}, {'path': 'packages/apps/ManagedProvisioning', 'new': 'LineageOS/android_packages_apps_ManagedProvisioning'}, {'path': 'packages/services/BuiltInPrintService', 'new': 'LineageOS/android_packages_services_BuiltInPrintService'}, {'path': 'system/ca-certificates', 'new': 'LineageOS/android_system_ca-certificates'}, {'path': 'system/libfmq', 'new': 'LineageOS/android_system_libfmq'}, {'path': 'system/libufdt', 'new': 'LineageOS/android_system_libufdt'}]
root = Path('/tmp/src/android').resolve(strict=True)
if Path.cwd().resolve() != root:
    raise SystemExit('Worker root required; post-migration check stopped')
for project in PROJECTS:
    relative = project['path']
    gitdir = root / '.repo/projects' / (relative + '.git')
    if gitdir.resolve(strict=True) != gitdir or (root / relative / '.git').resolve(strict=True) != gitdir:
        raise SystemExit('Unexpected post-migration Git directory: ' + relative)
    for name in ('hooks', 'objects', 'rr-cache'):
        target = root / '.repo/project-objects' / (project['new'] + '.git') / name
        if target.resolve(strict=True) != target or (gitdir / name).resolve(strict=True) != target:
            raise SystemExit('Post-migration store mismatch: ' + relative)
print('All six project stores resolve to their selected LineageOS repositories.')

PONG_MIGRATION_POSTCHECK

printf '%s\n' 'Preparation completed; no full-tree sync or compilation requested.'
