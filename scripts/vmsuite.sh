#!/bin/bash
# One suite of the automated test (TESTPLAN.md rows that need no person) on the plain
# CachyOS VM (Plasma, no Steamify: ~/vms/steamify-vm, from vminstall.sh --iso <CachyOS ISO> with VM_STEAMIFY=skip).
#   scripts/vmsuite.sh <suite> [--window]     suites: the folders in share/vmtest/ (cli, ...)
# Every block share/vmtest/<suite>/NN-name.sh starts from a fresh `ssh-ready` (vmreset.sh --fremont),
# runs in the guest as the VM user (repo on /mnt), and prints PASS/FAIL/SKIP lines; the first
# comment lines say which TESTPLAN rows it covers. Log: $VM_DIR.<suite>.log. Exit status = FAILs.
# Env: ONLY=<block name prefix> runs just that block; VM_DIR (default ~/vms/steamify-vm), REPO (default ../steamify-cachyos).
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/.." && pwd)"
suite="${1:?usage: $0 <suite> [--window]}"
[[ "${2:-}" == --window ]] || export VM_HEADLESS=1
export VM_DIR="${VM_DIR:-$HOME/vms/steamify-vm}"
export REPO="${REPO:-$repo/../steamify-cachyos}"
dir="$repo/share/vmtest/$suite"
[[ -d "$dir" ]] || { echo "No suite $suite (folders in share/vmtest/)" >&2; exit 2; }
. "$here/common.sh"
log="$VM_DIR.$suite.log"
# Headless on a desktop: a Konsole following the log (CI has no desktop; vmtest.sh opens its own).
if [[ -n "${VM_HEADLESS:-}" && -z "${CI:-}${VMTEST_NO_VIEW:-}" && -n "${WAYLAND_DISPLAY:-}${DISPLAY:-}" ]] && command -v konsole >/dev/null; then
    systemd-run --user -q --collect --unit="vmsuite-view-$suite-$$" konsole --hold -e tail -n +1 -F "$log" >/dev/null 2>&1 || true
fi
{
for block in "$dir"/*.sh; do
    [[ -z "${ONLY:-}" || "$(basename "$block")" == "$ONLY"* ]] || continue   # ONLY=50: just that block
    printf '\n##### %s %s\n' "$(date +%T)" "$(basename "$block" .sh)"
    "$here/vmreset.sh" --fremont > /tmp/vmsuite-reset.out 2>&1 || { echo "FAIL vmreset.sh failed: $(tail -n 1 /tmp/vmsuite-reset.out)"; continue; }
    cat "$repo/share/vmtest/prelude.sh" "$block" | vm_ssh -o ConnectTimeout=6 -o LogLevel=ERROR bash -s 2>&1 | sed 's/\x1b\[[0-9;]*m//g'
done
} 2>&1 | tee "$log"
fails="$(grep -c '^FAIL' "$log")"
echo; echo "== $suite: $(grep -c '^PASS' "$log") passed, $fails failed, $(grep -c '^SKIP' "$log") skipped (log: $log)"
grep '^FAIL' "$log"
exit "$fails"
