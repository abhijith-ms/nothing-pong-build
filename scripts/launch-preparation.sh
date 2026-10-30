#!/usr/bin/env bash
# Embed in one queued Crave worker command; never run directly in Devspace.
set -e -o pipefail -o noclobber
fail() { printf '%s\n' "$*" >&2; exit 1; }
[[ $# -eq 2 && $1 =~ ^[A-Za-z0-9][A-Za-z0-9_.-]*/[A-Za-z0-9][A-Za-z0-9_.-]*$ && $2 =~ ^[0-9a-f]{40}$ ]] ||
    fail 'Usage: launch-preparation.sh OWNER/REPOSITORY FULL_COMMIT_SHA'
[[ "$(pwd -P)" == /tmp/src/android && -f .repo/manifest.xml ]] || fail 'Existing queued worker checkout required.'
readonly PONG_PREP_SHA=fbd740a923b706d51d348c087f997ead421313bfe75cf5bdbbcc6ff20dd9ba96
readonly PONG_PREP_BYTES=21968
umask 077
for path in out out/pong-launch-evidence; do
    [[ ! -L $path && ( ! -e $path || -d $path ) ]] || fail 'Unexpected evidence parent; preserve and review.'
    mkdir -p -- "$path"
done
[[ $(stat -c %u out/pong-launch-evidence) == "$(id -u)" && $(stat -c %a out/pong-launch-evidence) == 700 ]] ||
    fail 'Unexpected evidence-directory owner or permissions; preserve and review.'
pong_attempt=$(mktemp -d "$PWD/out/pong-launch-evidence/attempt-XXXXXXXX")
: > "$pong_attempt/worker.log"
set +e
(
    set -e -o pipefail -o noclobber
    trap 'pong_body_exit=$?; printf "PONG_LAUNCH_BODY_EXIT=%s\n" "$pong_body_exit"' EXIT
    printf '%s\n' PONG_LAUNCH_BEGIN
    date -u
    printf 'Repository: %s\nCommit: %s\nRecipe SHA-256: %s\nEvidence: %s\n' "$1" "$2" "$PONG_PREP_SHA" "$pong_attempt"
    curl -q --fail --silent --show-error --proto '=https' --connect-timeout 20 --max-time 120 --max-filesize "$PONG_PREP_BYTES" \
        -o "$pong_attempt/prepare.sh" -- "https://raw.githubusercontent.com/$1/$2/scripts/prepare-pong.sh"
    [[ $(wc -c < "$pong_attempt/prepare.sh") -eq $PONG_PREP_BYTES ]]
    printf '%s  %s\n' "$PONG_PREP_SHA" "$pong_attempt/prepare.sh" | sha256sum -c -
    bash -n "$pong_attempt/prepare.sh"
    printf '%s\n' PONG_PREPARATION_BEGIN
    bash "$pong_attempt/prepare.sh"
    printf '%s\n' PONG_PREPARATION_COMPLETE
) 2>&1 | tee -a "$pong_attempt/worker.log"
pong_pipeline=("${PIPESTATUS[@]}")
printf 'body_exit=%s\nlog_exit=%s\n' "${pong_pipeline[0]}" "${pong_pipeline[1]}" > "$pong_attempt/result.txt"
pong_receipt_exit=$?
printf 'PONG_LAUNCH_RESULT body_exit=%s log_exit=%s receipt_exit=%s\n' "${pong_pipeline[0]}" "${pong_pipeline[1]}" "$pong_receipt_exit"
[[ ${pong_pipeline[0]} -eq 0 ]] || exit "${pong_pipeline[0]}"
[[ ${pong_pipeline[1]} -eq 0 ]] || exit "${pong_pipeline[1]}"
exit "$pong_receipt_exit"
