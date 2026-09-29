#!/bin/bash
# Install a fresh, ssh-ready test VM unattended: CachyOS (KDE Plasma,
# plasma-login-manager, btrfs, Limine, linux-cachyos + -lts) from the ISO's
# headless installer, then sshd with your key, passwordless sudo and the test
# autologin into Plasma. Ends with the snapshots `clean` and `ssh-ready`.
#   scripts/vminstall.sh [--force] [--iso <file>] [run.sh flags...]   e.g. --fremont
#   --force      replace an existing disk.qcow2 in $VM_DIR (asks first)
#   --iso <file> the live ISO (default $VM_DIR/cachyos.iso, e.g. a
#                Steamify CachyOS build later; it must be archiso-based and
#                have cachyos-installer)
# Env: VM_DIR (see common.sh), VM_USER (default: your host username),
#      VM_PASSWORD (steamify), VM_SSH_KEY (private key to authorize; default
#      ~/.ssh/steamify-vm_ed25519, asked once when that doesn't exist), REPO (shared as 9p `repo`, default ../steamify-cachyos),
#      VM_CACHE (host dir for the packages, default ~/vms/pkg-cache; empty = none),
#      VM_STEAMIFY (a Steamify ISO also runs steamify-install: the Steamify page's ids,
#      empty = defaults, skip = plain CachyOS), VM_BOOTLOADER (limine; or systemd-boot, grub), VM_TIMEZONE (the host's), VM_HOST_IP (the host as the guest sees it,
#      10.0.2.2 with QEMU's user networking).
# The VM's user and key are recorded in $VM_DIR (vm-user, ssh-key) for the
# other scripts. Never touches your existing SSH keys or ~/.ssh/known_hosts.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/.." && pwd)"
[[ -n "${VM_USER:-}" ]] || VM_USER="$(id -un)"
export VM_USER
. "$here/common.sh"
# The pacman package cache, on the host and shared by every VM you install
# (9p tag `cache`, see run.sh): a second install downloads nothing. VM_CACHE= (empty) turns it off.
export VM_CACHE="${VM_CACHE-$HOME/vms/pkg-cache}"

force=false iso="" run_flags=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --force) force=true; shift ;;
        --iso) iso="${2:?--iso needs a file}"; shift 2 ;;
        *) run_flags+=("$1"); shift ;;
    esac
done
password="${VM_PASSWORD:-steamify}"
timezone="${VM_TIMEZONE:-$(timedatectl show -p Timezone --value 2>/dev/null || cat /etc/timezone 2>/dev/null || echo UTC)}"
hostname=steamify-vm
REPO="${REPO:-$(dirname "$repo")/steamify-cachyos}"
[[ -d "$REPO" ]] || { echo "REPO $REPO doesn't exist (the Steamify checkout shared into the VM); set REPO=." >&2; exit 1; }
export REPO

mkdir -p "$VM_DIR"
iso="${iso:-$VM_DIR/cachyos.iso}"
[[ -f "$iso" ]] || { echo "No ISO at $iso: run get-iso.sh (in $VM_DIR) or pass --iso <file>." >&2; exit 1; }
iso="$(cd "$(dirname "$iso")" && pwd)/$(basename "$iso")"
pgrep -f '^qemu-system' >/dev/null && { echo "A VM is running; power it off first (both use port $VM_PORT)." >&2; exit 1; }
if [[ -f "$VM_DIR/disk.qcow2" ]]; then
    [[ "$force" == true ]] || { echo "$VM_DIR already has a disk.qcow2; use --force to replace it, or another VM_DIR." >&2; exit 1; }
    read -r -p "Replace $VM_DIR/disk.qcow2 and all its snapshots? Type YES: " answer < /dev/tty
    [[ "$answer" == YES ]] || { echo "Nothing changed."; exit 1; }
fi

# --- The SSH key to authorize: a new one just for the VM, or one of yours.
# The VM's own key is made once and then always used: asked only when it
# doesn't exist yet.
dedicated="$HOME/.ssh/steamify-vm_ed25519"
[[ -z "${VM_SSH_KEY:-}" && -f "$dedicated" ]] && VM_SSH_KEY="$dedicated"
if [[ -z "${VM_SSH_KEY:-}" ]]; then
    mapfile -t pubs < <(ls "$HOME"/.ssh/*.pub 2>/dev/null | grep -vxF "$dedicated.pub")
    echo "Which SSH key should log in to the VM?"
    echo "  1) a new key just for the VM, used from now on: $dedicated (no passphrase)"
    for i in "${!pubs[@]}"; do echo "  $((i + 2))) your key ${pubs[$i]%.pub}"; done
    read -r -p "Choice [1]: " choice < /dev/tty
    choice="${choice:-1}"
    if [[ "$choice" == 1 ]]; then
        VM_SSH_KEY="$dedicated"
        # Never overwrite a key: it doesn't exist here.
        ssh-keygen -q -t ed25519 -N "" -C "steamify-vm" -f "$dedicated"
    elif [[ "$choice" =~ ^[0-9]+$ && -n "${pubs[$((choice - 2))]:-}" ]]; then
        VM_SSH_KEY="${pubs[$((choice - 2))]%.pub}"
    else
        echo "Unknown choice: $choice" >&2; exit 1
    fi
fi
[[ -f "$VM_SSH_KEY.pub" ]] || { echo "No public key $VM_SSH_KEY.pub." >&2; exit 1; }
pubkey="$(cat "$VM_SSH_KEY.pub")"

echo "VM: $VM_DIR  user: $VM_USER  password: $password  hostname: $hostname  timezone: $timezone"
echo "ISO: $iso  key: $VM_SSH_KEY"

# --- The ISO's kernel and initramfs, to boot it with our parameters.
boot="$VM_DIR/iso-boot"
mkdir -p "$boot"
loop="$(udisksctl loop-setup --no-user-interaction -r -f "$iso" | grep -o '/dev/loop[0-9]*')"
cleanup_loop() { udisksctl unmount --no-user-interaction -b "${loop}p1" >/dev/null 2>&1 || true; udisksctl loop-delete --no-user-interaction -b "$loop" >/dev/null 2>&1 || true; }
trap cleanup_loop EXIT
mnt=""
for _ in $(seq 10); do
    mnt="$(findmnt -nro TARGET "${loop}p1" 2>/dev/null || true)"
    [[ -n "$mnt" ]] && break
    udisksctl mount --no-user-interaction -b "${loop}p1" >/dev/null 2>&1 || true; sleep 1
done
[[ -n "$mnt" ]] || { echo "Couldn't mount the ISO." >&2; exit 1; }
rm -f "$boot"/*   # copied read-only from the ISO
install -m 644 "$mnt/arch/boot/x86_64/vmlinuz-linux-cachyos" "$mnt/arch/boot/x86_64/initramfs-linux-cachyos.img" "$boot/"
search="$(grep -rhoE 'archisosearchuuid=[^ ]+' "$mnt/boot" "$mnt/EFI" 2>/dev/null | head -1)"
[[ -n "$search" ]] || { echo "No archisosearchuuid in the ISO's boot menu." >&2; exit 1; }
cleanup_loop; trap - EXIT

# --- What the live system fetches from the host.
www="$VM_DIR/install-www"
rm -rf "$www"; mkdir -p "$www"
# QEMU's user networking (-nic user in run.sh) always shows the host to the
# guest at 10.0.2.2, whatever network the host is on; only a bridged/tap
# setup would need another address.
host_ip="${VM_HOST_IP:-10.0.2.2}"
port="$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1])')"
sed -e "s/@PORT@/$port/" -e "s/@HOST_IP@/$host_ip/" "$repo/share/vminstall-live.sh" > "$www/vminstall-live.sh"
cp "$repo/share/vminstall-post.sh" "$www/"
{
    printf 'VM_USER=%q\nVM_HOSTNAME=%q\nVM_PUBKEY=%q\nDEVICE=/dev/vda\nVM_STEAMIFY=%q\n' "$VM_USER" "$hostname" "$pubkey" "${VM_STEAMIFY:-}"
} > "$www/vminstall.env"
python3 - "$www/settings.json" "$VM_USER" "$password" "$timezone" "$hostname" "${VM_BOOTLOADER:-limine}" << 'PY'
import json, sys
out, user, pw, tz, host, bootloader = sys.argv[1:]
json.dump({
    "install_type": "simple", "headless_mode": True,
    "device": "/dev/vda", "fs_name": "btrfs", "subvolumes": "default",
    "partitions": [
        {"name": "/dev/vda1", "mountpoint": "/boot", "size": "2G", "fs_name": "vfat", "type": "boot"},
        {"name": "/dev/vda2", "mountpoint": "/", "size": "100%", "type": "root"},
    ],
    "hostname": host, "locale": "en_US.UTF-8", "xkbmap": "us", "timezone": tz,
    "user_name": user, "user_pass": pw, "user_shell": "/bin/fish", "root_pass": pw,
    "kernel": "linux-cachyos linux-cachyos-lts", "desktop": "kde", "bootloader": bootloader,
}, open(out, "w"), indent=2)
PY
python3 "$here/vminstall-server.py" "$www" "$port" &
server=$!
trap 'kill $server 2>/dev/null || true' EXIT

# --- Install.
cd "$VM_DIR"
cp "$repo/run.sh" run.sh   # always this repo's: the install needs its kernel/serial options
[[ -e share ]] || ln -s "$repo/share" share
rm -f disk.qcow2 vars.fd vars.clean.fd vars.ssh-ready.fd known_hosts
qemu-img create -q -f qcow2 disk.qcow2 60G
echo "$VM_USER" > vm-user
echo "$REPO" > repo-path
echo "$VM_SSH_KEY" > ssh-key
# systemd.run= only generates kernel-command-line.service; systemd.wants=
# starts it next to the normal boot (desktop, network). It fetches and runs
# the live script. (Root logs in on the serial console without a password:
# VM_SERIAL.sock, for debugging.)
append="$search archisobasedir=arch cow_spacesize=10G module_blacklist=pcspkr console=ttyS0,115200 console=tty0"
append+=" systemd.run=\"/usr/bin/bash -c 'curl -fsS --retry 150 --retry-all-errors --retry-delay 2 http://$host_ip:$port/vminstall-live.sh | bash'\""
append+=" systemd.run_success_action=none systemd.run_failure_action=none systemd.wants=kernel-command-line.service"
echo "Installing: watch the VM's window, or follow the console with tail -f $VM_DIR/serial.log (install log: $www/install.log)..."
VM_SERIAL="$VM_DIR/serial.log" VM_ISO="$iso" VM_KERNEL="$boot/vmlinuz-linux-cachyos" VM_INITRD="$boot/initramfs-linux-cachyos.img" VM_APPEND="$append" \
    ./run.sh install "${run_flags[@]}" > vm-install.log 2>&1 &
qemu=$!
for _ in $(seq 1080); do kill -0 $qemu 2>/dev/null || break; sleep 5; done   # 90 minutes
kill -0 $qemu 2>/dev/null && { echo "The install didn't finish in 90 minutes; see $www/install.log." >&2; kill $qemu; exit 1; }
status="$(cat "$www/status" 2>/dev/null || echo "no status (the live system never reported back)")"
cp "$www/install.log" install.log 2>/dev/null || true
[[ "$status" == ok ]] || { echo "Install failed: $status. Log: $VM_DIR/install.log" >&2; exit 1; }
qemu-img snapshot -c clean disk.qcow2 && cp vars.fd vars.clean.fd
echo "Installed; snapshot 'clean' taken."

# --- First boot: check it's ssh-ready, then snapshot.
nohup ./run.sh "${run_flags[@]}" > vm.log 2>&1 &
for _ in $(seq 100); do vm_ssh -o ConnectTimeout=3 true 2>/dev/null && break; sleep 3; done
vm_ssh true || { echo "No SSH after the first boot; see $VM_DIR/vm.log." >&2; exit 1; }
vm_ssh bash -s << 'REMOTE'
set -e
if [[ -f /etc/sddm.conf.d/10-gamescope-autologin.conf ]]; then
    # Steamify's gaming mode (gamescope, no Plasma, and it doesn't render in the VM): the login manager has to be up.
    for _ in $(seq 60); do systemctl is-active --quiet display-manager && break; sleep 3; done
    systemctl is-active --quiet display-manager || { echo "The login manager didn't start." >&2; exit 1; }
else
    for _ in $(seq 60); do pgrep -u "$USER" -x plasmashell >/dev/null && break; sleep 3; done
    pgrep -u "$USER" -x plasmashell >/dev/null || { echo "Plasma didn't start." >&2; exit 1; }
fi
sudo -n true
echo "ssh-ready: $(id -un)@$(hostname), $(uname -r), $(localectl status | sed -n 's/.*LANG=//p'), $(timedatectl show -p Timezone --value)"
sudo systemctl poweroff
REMOTE
while pgrep -f '^qemu-system' >/dev/null; do sleep 2; done
qemu-img snapshot -c ssh-ready disk.qcow2 && cp vars.fd vars.ssh-ready.fd
rm -rf "$www"
echo "Done: snapshots 'clean' and 'ssh-ready' in $VM_DIR."
echo "Log in by hand as $VM_USER / $password (root: $password)."
