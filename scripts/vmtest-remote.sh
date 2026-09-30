#!/bin/bash
# Run the whole automated test on another machine (the PC with the VMs) from this one (e.g. a laptop):
# update the repo there, start scripts/vmtest.sh in a detached `screen`, wait for the summary, print it.
#   scripts/vmtest-remote.sh <ssh-host> [--no-wait] [vmtest.sh args...]     e.g. scripts/vmtest-remote.sh pc cli hw
# The branch you are on must be pushed (the remote pulls it). The remote needs this repo, ../steamify-cachyos,
# ../steamify-cachyos-live-iso (for the loader list and the ISO), qemu + OVMF + screen, KVM, and the VMs in
# ~/vms (see the vm-install skill). Env: REMOTE_REPO (default ~/projects/steamify/steamify-cachyos-dev).
set -uo pipefail
host="${1:?usage: $0 <ssh-host> [--no-wait] [vmtest.sh args...]}"; shift
wait=true; args=()
for a in "$@"; do [[ "$a" == --no-wait ]] && wait=false || args+=("$a"); done
repo="$(cd "$(dirname "$0")/.." && pwd)"
branch="$(git -C "$repo" branch --show-current)"
rr="${REMOTE_REPO:-~/projects/steamify/steamify-cachyos-dev}"
git -C "$repo" ls-remote --exit-code --heads origin "$branch" >/dev/null 2>&1 || { echo "Push $branch first: the remote pulls it." >&2; exit 1; }
[[ -z "$(git -C "$repo" status --porcelain)" ]] || echo "Note: uncommitted changes here are NOT tested; the remote runs what is pushed." >&2
ssh "$host" "rm -f ~/vms/last-test.txt; cd $rr && git fetch -q origin && git checkout -q $branch && git pull -q --ff-only && scripts/vmtest.sh --screen ${args[*]:-}" || exit 1
$wait || { echo "Started on $host; the summary lands in ~/vms/last-test.txt there (screen -r vmtest to watch)."; exit 0; }
until ssh "$host" 'grep -q "^== total" ~/vms/last-test.txt 2>/dev/null'; do sleep 30; done
ssh "$host" 'cat ~/vms/last-test.txt'
ssh "$host" 'test "$(grep -c "^FAIL" ~/vms/last-test.txt)" -eq 0'
