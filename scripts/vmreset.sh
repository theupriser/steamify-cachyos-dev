#!/bin/bash
# Reset the test VM to a snapshot and bring it up logged in to Plasma:
# power off, restore the snapshot (disk + vars.fd), start it, mount the repo
# on /mnt, set up the test autologin and wait for plasmashell; also skips
# the broken krfoss mirror and installs shellcheck.
#   scripts/vmreset.sh [run.sh flags...]      e.g. scripts/vmreset.sh --fremont
# Env: VM_USER / VM_PORT / VM_HOST, SNAPSHOT (ssh-ready),
#      VM_DIR (where disk.qcow2 lives: this repo if it has one, else ~/vms/cachyos-test),
#      VM_LOG (QEMU output, default $VM_DIR/vm.log).
set -euo pipefail
. "$(dirname "$0")/common.sh"
repo="$(cd "$(dirname "$0")/.." && pwd)"
if [[ -z "${VM_DIR:-}" ]]; then
    if [[ -f "$repo/disk.qcow2" ]]; then VM_DIR="$repo"; else VM_DIR="$HOME/vms/cachyos-test"; fi
fi
SNAPSHOT="${SNAPSHOT:-ssh-ready}"
VM_LOG="${VM_LOG:-$VM_DIR/vm.log}"

if pgrep -f '^qemu-system' >/dev/null; then
    echo "Powering off the running VM..."
    vm_ssh sudo systemctl poweroff 2>/dev/null || true
    for _ in $(seq 60); do pgrep -f '^qemu-system' >/dev/null || break; sleep 2; done
    pgrep -f '^qemu-system' >/dev/null && { echo "VM didn't shut down; stop it first." >&2; exit 1; }
fi

echo "Restoring snapshot '$SNAPSHOT' in $VM_DIR..."
cd "$VM_DIR"
qemu-img snapshot -a "$SNAPSHOT" disk.qcow2
cp "vars.$SNAPSHOT.fd" vars.fd

echo "Starting the VM ($*)..."
nohup ./run.sh "$@" > "$VM_LOG" 2>&1 &
for _ in $(seq 100); do vm_ssh -o ConnectTimeout=3 true 2>/dev/null && break; sleep 3; done
vm_ssh true || { echo "No SSH after 5 minutes; see $VM_LOG" >&2; exit 1; }

vm_ssh bash -s << 'REMOTE'
sudo mount -t 9p -o trans=virtio,version=9p2000.L repo /mnt
sudo mkdir -p /etc/plasmalogin.conf.d
printf '[Autologin]\nUser=%s\nSession=plasma.desktop\n' "$USER" | sudo tee /etc/plasmalogin.conf.d/00-test-autologin.conf >/dev/null
sudo systemctl restart plasmalogin
for _ in $(seq 40); do pgrep -u "$USER" -x plasmashell >/dev/null && break; sleep 3; done
sleep 10
# Windows the snapshot opens at login would cover the screenshots.
pkill -u "$USER" systemsettings; pkill -u "$USER" cachyos-hello
# mirror5.krfoss.org served a broken .sig ("Maximum file size exceeded"),
# which fails the conversion's package install; skip it.
for f in /etc/pacman.d/*mirrorlist*; do sudo sed -i '/krfoss/s/^Server/#Server/' "$f"; done
# shellcheck, for checking the bundle like CI does (not in the snapshot).
sudo pacman -S --needed --noconfirm shellcheck >/dev/null 2>&1 || echo "Couldn't install shellcheck." >&2
pgrep -u "$USER" -x plasmashell >/dev/null && echo "Logged in to Plasma." || { echo "Plasma did not start." >&2; exit 1; }
REMOTE
