"""Real Git LFS regression in disposable repositories; no network or ROM execution.

Usage: python3 tests/check_materialization.py /path/to/git-lfs
"""
import ast
import hashlib
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
recipe = (ROOT / 'scripts/prepare-pong.sh').read_text()
code = recipe.split("<<'PONG_WEBVIEW_MATERIALIZE'\n", 1)[1].split('\nPONG_WEBVIEW_MATERIALIZE', 1)[0]
data = ast.literal_eval(next(line[7:] for line in code.splitlines() if line.startswith('DATA = ')))
lfs = Path(sys.argv[1]).resolve(strict=True)
assert lfs.is_file() and os.access(lfs, os.X_OK)

with tempfile.TemporaryDirectory() as temporary:
    folder = Path(temporary).resolve()
    binary = folder / 'bin'
    binary.mkdir()
    (binary / 'git-lfs').symlink_to(lfs)
    global_config = folder / 'global-config'
    global_config.write_text('[filter "lfs"]\nclean = git-lfs clean -- %f\nsmudge = git-lfs smudge -- %f\nprocess = git-lfs filter-process\nrequired = true\n')
    env = dict(os.environ, PATH=str(binary) + os.pathsep + os.environ['PATH'],
               GIT_CONFIG_NOSYSTEM='1', GIT_CONFIG_GLOBAL=str(global_config),
               GIT_TERMINAL_PROMPT='0', GIT_NO_LAZY_FETCH='1')
    for key in list(env):
        if key.startswith('GIT_CONFIG_') and key not in ('GIT_CONFIG_NOSYSTEM', 'GIT_CONFIG_GLOBAL'):
            del env[key]
    def git(path, *args, isolated=False):
        run_env = dict(env, GIT_CONFIG_GLOBAL='/dev/null') if isolated else env
        return subprocess.run(['git', '-c', 'core.hooksPath=/dev/null', '-C', str(path), *args],
                              env=run_env, capture_output=True, check=True).stdout.strip()
    version = git(folder, 'lfs', 'version').decode()
    assert version.startswith('git-lfs/3.6.0 '), version
    content = b'disposable APK content\n'
    data.update(oid=hashlib.sha256(content).hexdigest(), bytes=len(content))
    original = folder / 'original'
    (original / '.repo').mkdir(parents=True)
    (original / '.repo/manifest.xml').write_text('<manifest/>\n')
    work = original / 'external/chromium-webview/prebuilt/arm64'
    manifest = original / '.repo/manifests'
    for path in (work, manifest):
        path.mkdir(parents=True)
        git(path, 'init', '-q')
        (path / 'fixture').write_text('fixture\n')
        git(path, 'add', '.')
        git(path, '-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid',
            '-c', 'commit.gpgsign=false', 'commit', '-qm', 'fixture')
    (work / '.gitattributes').write_text('webview.apk filter=lfs\n')
    pointer = ('version https://git-lfs.github.com/spec/v1\noid sha256:' + data['oid'] +
               '\nsize ' + str(data['bytes']) + '\n').encode()
    (work / 'webview.apk').write_bytes(pointer)
    git(work, '-c', 'filter.lfs.process=', '-c', 'filter.lfs.clean=cat',
        '-c', 'filter.lfs.required=false', 'add', '.')
    git(work, '-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid',
        '-c', 'commit.gpgsign=false', 'commit', '-qm', 'pointer')
    data.update(head=git(work, 'rev-parse', 'HEAD').decode(),
                blob=git(work, 'rev-parse', 'HEAD:webview.apk').decode(),
                manifest=git(manifest, 'rev-parse', 'HEAD').decode())
    (work / 'webview.apk').unlink()
    gitdir = original / '.repo/projects/external/chromium-webview/prebuilt/arm64.git'
    gitdir.parent.mkdir(parents=True)
    (work / '.git').rename(gitdir)
    (work / '.git').symlink_to(os.path.relpath(gitdir, work))
    media_relative = gitdir.relative_to(original) / 'lfs/objects' / data['oid'][:2] / data['oid'][2:4] / data['oid']
    media = original / media_relative
    media.parent.mkdir(parents=True)
    media.write_bytes(content)
    media.chmod(0o644)
    # Reproduce the real exit-zero skip without the isolated global filter.
    result = subprocess.run(['git', '-c', 'lfs.storage=' + str(gitdir / 'lfs'),
                             '-C', str(work), 'lfs', 'checkout', 'webview.apk'],
                            env=dict(env, GIT_CONFIG_GLOBAL='/dev/null'), capture_output=True)
    assert result.returncode == 0 and b'Git LFS is not installed' in result.stdout
    assert not (work / 'webview.apk').exists()
    print('Real LFS: isolated filter configuration reproduces exit-zero missing APK.')
    for case in ('missing', 'matching', 'different', 'symlink', 'bad-cache', 'index', 'checkout-noop', 'checkout-failure'):
        root = folder / case
        shutil.copytree(original, root, symlinks=True)
        work = root / 'external/chromium-webview/prebuilt/arm64'
        apk = work / 'webview.apk'
        local_gitdir = root / gitdir.relative_to(original)
        if case in ('matching', 'different'):
            apk.write_bytes(content if case == 'matching' else b'preserve user file')
            apk.chmod(0o644)
        if case == 'symlink': apk.symlink_to('fixture')
        if case == 'bad-cache': (root / media_relative).write_bytes(b'x' * len(content))
        if case == 'index': git(work, 'update-index', '--force-remove', 'webview.apk')
        if case in ('checkout-noop', 'checkout-failure'):
            wrapper = binary / 'git-lfs'
            wrapper.unlink()
            wrapper.write_text('#!' + sys.executable + '\nimport os,sys\nif sys.argv[1] == \"checkout\":\n    print(\"fixture-noop\" + \"X\" * 5000)\n    print(\"fixture-stderr\", file=sys.stderr)\n    sys.exit(' + ('23' if case == 'checkout-failure' else '0') + ')\nos.execv(' + repr(str(lfs)) + ', [' + repr(str(lfs)) + '] + sys.argv[1:])\n')
            wrapper.chmod(0o700)
        before_index = git(work, 'ls-files', '--stage', '-z')
        before_config = (local_gitdir / 'config').read_bytes()
        patched = re.sub(r'^DATA = .*$', lambda _: 'DATA = ' + repr(data), code, flags=re.M)
        patched = patched.replace("Path('/tmp/src/android')", 'Path(' + repr(str(root)) + ')')
        result = subprocess.run([sys.executable, '-I', '-c', patched], cwd=root,
                                env=env, capture_output=True, text=True, timeout=30)
        # Real LFS refreshes index stat data; staged modes/blobs must stay unchanged.
        assert git(work, 'ls-files', '--stage', '-z') == before_index, case
        assert (local_gitdir / 'config').read_bytes() == before_config, case
        if case in ('missing', 'matching'):
            assert result.returncode == 0, result.stdout + result.stderr
            assert apk.read_bytes() == content
        else:
            assert result.returncode != 0, case
            if case == 'different': assert apk.read_bytes() == b'preserve user file'
            if case == 'symlink': assert apk.is_symlink()
            if case in ('checkout-noop', 'checkout-failure'):
                assert 'fixture-stderr' in result.stdout
                assert 'X' * 4097 not in result.stdout
                assert 'fixture-noop' in result.stdout
                assert ('exit 23' if case == 'checkout-failure' else 'checkout left WebView APK absent') in result.stderr
                assert not apk.exists()
        print(case + ': passed')
    assert global_config.read_text().startswith('[filter "lfs"]')
print('Real-LFS restoration, preservation and no-op diagnostics checks passed.')
