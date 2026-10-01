#!/bin/bash
# One suite of the automated test (TESTPLAN.md rows that need no person) on the plain CachyOS VM
# (Plasma, no Steamify: ~/vms/steamify-vm, from vminstall.sh --iso <CachyOS ISO> with VM_STEAMIFY=skip).
#   scripts/vmsuite.sh <suite> [--window]     suites: the folders in share/vmtest/ (cli, ...)
#   scripts/vmsuite.sh --prepare              only make the base image (below)
# Every block share/vmtest/<suite>/NN-name.sh starts from a fresh copy of the VM's `ssh-ready` state,
# runs in the guest as the VM user (repo on /mnt; NN-name.host.sh blocks run on the host instead: reboots,
# host scripts), and prints PASS/FAIL/SKIP lines; the first comment lines say which TESTPLAN rows it
# covers; `# env: VAR=value` there is set for the VM start (e.g. BIOS_VERSION=F7F0107).
# Fast and parallel: the `ssh-ready` snapshot is converted once into $SRC/base-ssh-ready.qcow2; each suite
# has its own directory ~/vms/run-<suite> and ssh port, where every block gets a new qcow2 overlay of the
# base (instant, no snapshot restore), and the host's package cache (VM_CACHE, ~/vms/pkg-cache) is bound
# over pacman's cache, so packages are downloaded once for all. Log: $VM_DIR.log. Exit status = FAILs.
# Env: ONLY=<block name prefix> runs just that block; SRC (default ~/vms/steamify-vm); REPO (default ../steamify-cachyos).
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/.." && pwd)"
src="${SRC:-$HOME/vms/steamify-vm}"
base="$src/base-ssh-ready.qcow2"

prepare_base() {   # once, under a lock (parallel suites): the ssh-ready snapshot as a stand-alone image
    ( flock 9
      if [[ ! -f "$base" || "$src/vars.ssh-ready.fd" -nt "$base" ]]; then
          echo "Making $base from the ssh-ready snapshot (once, a few minutes)..." >&2
          qemu-img convert -f qcow2 -O qcow2 -l snapshot.name=ssh-ready "$src/disk.qcow2" "$base.tmp" && mv "$base.tmp" "$base"
      fi ) 9>"$src/.base.lock"
    [[ -f "$base" ]]
}
if [[ "${1:-}" == --prepare ]]; then prepare_base; exit $?; fi

suite="${1:?usage: $0 <suite> [--window] | --prepare}"
[[ "${2:-}" == --window ]] || export VM_HEADLESS=1
dir="$repo/share/vmtest/$suite"
[[ -d "$dir" ]] || { echo "No suite $suite (folders in share/vmtest/)" >&2; exit 2; }
case "$suite" in cli) port=2301 ;; menu) port=2302 ;; hw) port=2303 ;; installer) port=2304 ;; toggles) port=2305 ;; nvidia) port=2306 ;; *) port=2390 ;; esac
export VM_PORT="${VM_PORT:-$port}"
export VM_DIR="$HOME/vms/run-$suite"
export REPO="${REPO:-$repo/../steamify-cachyos}"
export VM_CACHE="${VM_CACHE-$HOME/vms/pkg-cache}"
export VM_MEM="${VM_MEM:-4G}"   # three VMs at once next to a desktop: 8G each pushed the host into swap
prepare_base || { echo "FAIL no base image" >&2; exit 1; }
mkdir -p "$VM_DIR"
for f in vm-user ssh-key; do cp "$src/$f" "$VM_DIR/$f"; done
echo "$REPO" > "$VM_DIR/repo-path"; [[ -e "$VM_DIR/share" ]] || ln -s "$repo/share" "$VM_DIR/share"
. "$here/common.sh"
log="$VM_DIR.log"
view_start   # one shared Konsole (common.sh), headless on a desktop

vm_running() { pgrep -f "[h]ostfwd=tcp::$VM_PORT-" >/dev/null; }
vm_stop() {
    vm_running || return 0
    vm_ssh -o ConnectTimeout=4 'sudo systemctl poweroff' >/dev/null 2>&1
    local _; for _ in $(seq 20); do vm_running || return 0; sleep 1; done
    pkill -f "[h]ostfwd=tcp::$VM_PORT-"; sleep 2
}
# A fresh VM for a block: new overlay of the base, the snapshot's UEFI vars, Plasma up, repo mounted, package cache bound.
vm_fresh() {   # vm_fresh [VAR=value...]: extra environment for the VM start (BIOS_VERSION=...)
    vm_stop
    cp "$repo/run.sh" "$VM_DIR/run.sh"; cp "$src/vars.ssh-ready.fd" "$VM_DIR/vars.fd"
    rm -f "$VM_DIR/disk.qcow2" "$VM_DIR/known_hosts"
    qemu-img create -q -f qcow2 -b "$base" -F qcow2 "$VM_DIR/disk.qcow2" || return 1
    (cd "$VM_DIR" && env "$@" nohup ./run.sh --fremont > vm.log 2>&1 &)
    local _; for _ in $(seq 100); do vm_ssh -o ConnectTimeout=3 true 2>/dev/null && break; sleep 3; done
    vm_ssh -o LogLevel=ERROR bash -s <<'REMOTE'
sudo mount -t 9p -o trans=virtio,version=9p2000.L repo /mnt
sudo mkdir -p /etc/plasmalogin.conf.d
printf '[Autologin]\nUser=%s\nSession=plasma.desktop\n' "$USER" | sudo tee /etc/plasmalogin.conf.d/00-test-autologin.conf >/dev/null
for _ in $(seq 10); do pgrep -u "$USER" -x plasmashell >/dev/null && break; sleep 3; done
pgrep -u "$USER" -x plasmashell >/dev/null || { sudo systemctl reset-failed plasmalogin; sudo systemctl restart plasmalogin; }
for _ in $(seq 40); do pgrep -u "$USER" -x plasmashell >/dev/null && break; sleep 3; done
pkill -u "$USER" systemsettings; pkill -u "$USER" cachyos-hello
for f in /etc/pacman.d/*mirrorlist*; do sudo sed -i '/krfoss/s/^Server/#Server/' "$f"; done
# the host's package cache over pacman's
sudo mkdir -p /var/cache/steamify-pkg
if sudo mount -t 9p -o trans=virtio,version=9p2000.L cache /var/cache/steamify-pkg 2>/dev/null; then
    sudo mkdir -p /var/cache/steamify-pkg/pkg; sudo mount --bind /var/cache/steamify-pkg/pkg /var/cache/pacman/pkg
    # Steamify's own downloads (the CEC driver: GitHub rate-limits it) once for every VM
    sudo mkdir -p /var/cache/steamify-pkg/steamify /var/cache/steamify; sudo mount --bind /var/cache/steamify-pkg/steamify /var/cache/steamify
fi
pgrep -u "$USER" -x plasmashell >/dev/null && echo "Logged in to Plasma." || { echo "Plasma did not start." >&2; exit 1; }
REMOTE
}

{
printf '\n===== vmsuite.sh %s (%s) =====\n' "$suite" "$(date +%T)"
for block in "$dir"/*.sh; do
    [[ -z "${ONLY:-}" || "$(basename "$block")" == "$ONLY"* ]] || continue   # ONLY=50: just that block
    printf '\n##### %s %s\n' "$(date +%T)" "$(basename "$block" .sh)"
    vm_fresh $(sed -n 's/^# env: //p' "$block" | head -n 1) > /tmp/vmsuite-$suite-reset.out 2>&1 \
        || { echo "FAIL the VM did not come up: $(tail -n 1 /tmp/vmsuite-$suite-reset.out)"; continue; }
    if [[ "$block" == *.host.sh ]]; then   # runs on the host (reboots, host scripts); prelude-host.sh has the helpers
        ( . "$repo/share/vmtest/prelude-host.sh"; . "$block" ) 2>&1 | sed -u 's/\x1b\[[0-9;]*m//g'
        continue
    fi
    cat "$repo/share/vmtest/prelude.sh" "$block" | vm_ssh -o ConnectTimeout=6 -o LogLevel=ERROR bash -s 2>&1 | sed -u 's/\x1b\[[0-9;]*m//g'
done
vm_stop
} 2>&1 | tee "$log" | sed -u "s/^/[$suite] /" >> "$TEST_LOG"
rc=${PIPESTATUS[0]}   # an abort inside the braces must not pass as 0 failed checks
fails="$(grep -c '^FAIL' "$log")"
if [[ $rc -ne 0 && $fails -eq 0 ]]; then
    echo "FAIL $suite aborted (exit $rc): $(grep -v '^$' "$log" | tail -n 1)" | tee -a "$log"; fails=1
fi
echo "== $suite: $(grep -c '^PASS' "$log") passed, $fails failed, $(grep -c '^SKIP' "$log") skipped (log: $log)" | tee -a "$log"
grep '^FAIL' "$log"
exit "$fails"
