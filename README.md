# Pong preparation recipe

Repository: `abhijith-ms/nothing-pong-build`. This correction was tested locally
using disposable fixtures and Git LFS3.6.0. Job308157 confirmed the pinned launcher
download and execution, then failed during WebView preparation. This correction
has not run on Crave; no ROM release or banking compatibility is established.
Previous cancellations remain unexplained. Use an actual published commit SHA
when rendering a future worker invocation.

Only this directory is intended for a future public repository. Do not upload the
parent workspace, private backups, logs, credentials, phone data or signing keys.
The recipe contains public source revisions and preservation fingerprints, not
the preserved files. Review the publication list before publishing:

- `README.md`
- `manifests/pong.xml`
- `scripts/prepare-pong.sh`
- `scripts/launch-preparation.sh`
- `scripts/render-command.py`
- `tests/check_launcher.py`
- `tests/check_materialization.py`

## What can run

This is a fixed, existing-workspace Nothing Phone (2) / Pong preparation recipe,
not a generic Android build script. It targets Crave project99 and the existing
personal clone `/crave-devspaces/lineage23.2-pong`. It restores one absent WebView
APK from verified local LFS media, runs the original first source/overlay guard,
initializes the pinned manifest/overlay, verifies preservation/ownership and
replaces only six reviewed Git mappings, then checks them and stops. It can
replace those six backed-up working trees and per-project Git metadata.

`prepare-pong.sh` corrects the preparation recipe used by failed job308157.
Git LFS filters are supplied only for each command while global/system Git
configuration stays isolated. Checkout diagnostics are retained (first4096 bytes
per stream), and an absent output fails explicitly before content verification.
The recipe is now:
21,968 bytes, SHA-256
`fbd740a923b706d51d348c087f997ead421313bfe75cf5bdbbcc6ff20dd9ba96`.
Its source guards and machine-specific preservation requirements are unchanged.
The original failed recipe remains available at commit
`073f5e77ab505d447973bba7e7ff6f27613cb614`.
`manifests/pong.xml` is an exact copy of its embedded public overlay.
The canonical full-build script and its later post-sync guard are outside this
package and remain unchanged. No full-tree sync, compilation, banking workaround,
production signing or phone operation is requested here.

## Launcher and retained evidence

The renderer embeds only the small local launcher in a single-line worker
command. The launcher accepts a public GitHub repository slug and full40-character
commit SHA, downloads `scripts/prepare-pong.sh` from that exact commit over HTTPS,
does not follow redirects, rejects HTTP errors, checks length/SHA-256 and Bash syntax,
then runs the verified file. Branch names, URLs and extra arguments are refused.
There is no `curl | bash` execution or dynamic selection of a different recipe.

Before downloading or executing the recipe, the launcher creates a new private
`out/pong-launch-evidence/attempt-XXXXXXXX/` directory. `worker.log` records the
start marker, UTC time, public repository/commit, expected recipe hash, output and
body exit. `result.txt` records body/log exits. The launcher propagates a failed
body, logging failure or receipt-write failure, in that order. Existing evidence
is retained; unexpected parent aliases/types/permissions are refused. New files
use0600 and attempt directories0700. Existing `out` permissions are not changed.

Evidence retention is best effort: hard termination may prevent an exit receipt,
and service cleanup, rollback or loss of the workspace may remove these files.
An absent marker still cannot prove that no worker started. Worker output may
contain local paths or diagnostics; keep logs private until reviewed/redacted.

## Local review and future submission

Run `python3 tests/check_launcher.py` from this directory. It uses disposable
fixtures and fake curl/Crave clients; it never contacts either service or executes
the actual preparation recipe.

Run `python3 tests/check_materialization.py /path/to/git-lfs` with a verified
Git LFS3.6.0 executable. This test creates only disposable local repositories,
reproduces the exit-zero checkout skip with hidden global filters, then verifies
restoration with invocation-scoped filters and refusal/preservation cases. It
needs no network, system installation or Crave access. Real LFS may refresh index
stat data; staged modes and blob IDs must remain unchanged.

After a reviewed public commit exists, render an invocation locally:

```bash
python3 scripts/render-command.py abhijith-ms/nothing-pong-build FULL_COMMIT_SHA
```

Rendering prints a command; it does not run it. Do not execute placeholder values
or publish solely to obtain a test URL. The emitted command is for a separately
authorized own Devspace session and exactly one queued worker. Before dispatch:
refresh FOSS rules/admin maintenance, list clones as the first Crave CLI command,
verify the existing clone/client and first zero-personal-job gate, reverify the
preservation archives, and review current state. The command repeats installed
cache-option and zero-personal-job checks immediately before submission. It uses
project99, no patch/artifact pull, detached mode, per-job cache disabled and no
clean. Retain the actual client exit/job ID; never repeat a delayed submission.
Verify the stored worker command, owner/clone/settings and exact pinned payload,
then stop only the own idle Devspace. Do not change shared project settings.

Source synchronization and preparation run only in the queued worker, never
directly in Devspace or `crave ssh`. A partial migration requires state review
before retry. A successful preparation still would not establish a ROM build,
Google certification, bootability or banking compatibility.

References: [FOSS rules](https://fosson.top/crave/rules),
[build workflow](https://fosson.top/crave/getting-started/building-crave-run),
[Crave CLI](https://github.com/accupara/crave).
