#!/bin/bash
# Does a boot loader work with Steamify's kernel side (the Steam Machine's DKMS
# modules)? On a VM that reports Fremont hardware: applies Steamify's options,
# checks the modules for every kernel, Steamify's boot-loader code (removal of
# the old drm.edid_firmware parameter), a kernel update, and a reboot into
# each of the two kernels. Guest checks: share/bootloader-test/*.sh.
# All loaders in one go: scripts/vmtest.sh.
#   scripts/vmbootloadertest.sh <limine|systemd-boot|grub> [--install] [--window]
#   --install  first install the VM (scripts/vminstall.sh, from the Steamify ISO)
#   --window   show the VM's window (default: headless, with a Konsole on the log when there is a desktop)
# Env: VM_DIR (default ~/vms/bl-<loader>), VM_ISO (default: the newest ISO in
#      ../steammachine-cachyos-live-iso/out/desktop), REPO (steamify-cachyos, 9p `repo`).
# Exit status: the number of failed checks. Only one VM runs at a time (port 2222).
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/.." && pwd)"
loader="${1:?usage: $0 <limine|systemd-boot|grub> [--install]}"
install=false; window=false
for a in "${@:2}"; do
    case "$a" in --install) install=true ;; --window) window=true ;; *) echo "Unknown argument: $a" >&2; exit 2 ;; esac
done
# No human is needed: headless (no VM window) unless --window. On a desktop a Konsole follows the log.
$window || export VM_HEADLESS=1
case "$loader" in limine|systemd-boot|grub) ;; *) echo "Unknown boot loader: $loader" >&2; exit 2 ;; esac
export VM_DIR="${VM_DIR:-$HOME/vms/bl-$loader}"
# Own ssh port per loader, so the loaders can run side by side (vmtest.sh).
case "$loader" in limine) export VM_PORT="${VM_PORT:-2401}" ;; systemd-boot) export VM_PORT="${VM_PORT:-2402}" ;; grub) export VM_PORT="${VM_PORT:-2403}" ;; esac
. "$here/common.sh"
guest="$repo/share/bootloader-test"
log="$VM_DIR.test.log"

step() { printf '\n##### %s %s\n' "$(date +%T)" "$*"; }
gssh() { vm_ssh -o ConnectTimeout=6 -o LogLevel=ERROR "$@"; }
gscript() { gssh env "LOADER=$loader" bash -s < "$guest/$1"; }   # the guest's login shell is fish
waitssh() { local _; for _ in $(seq 60); do gssh 'uptime -p' 2>/dev/null | grep -q '^up' && return 0; sleep 5; done; echo "FAIL no SSH"; return 1; }
running() { pgrep -f "[h]ostfwd=tcp::$VM_PORT-" >/dev/null; }
stop_vm() {
    running || return 0
    # Whichever VM runs: its key and host key are not this VM's.
    ssh -p "$VM_PORT" -i "$VM_SSH_KEY" -o BatchMode=yes -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -o LogLevel=ERROR \
        "$VM_USER@$VM_HOST" 'sudo systemctl poweroff' >/dev/null 2>&1
    local _; for _ in $(seq 30); do running || return 0; sleep 2; done
    pkill -f "[h]ostfwd=tcp::$VM_PORT-"; sleep 2
}
start_vm() { stop_vm; cp "$repo/run.sh" "$VM_DIR/run.sh"; (cd "$VM_DIR" && VM_MEM="${VM_MEM:-4G}" REPO="${REPO:-$repo/../steamify-cachyos}" setsid nohup ./run.sh --fremont > vm.log 2>&1 &); }
reboot_vm() { gssh 'sudo systemctl reboot' >/dev/null 2>&1; sleep 25; waitssh; }
view_start   # one shared Konsole (common.sh)
# The guest checks print PASS/FAIL lines; the summary at the end counts them in the log.
check() { cat; }

{
printf '\n===== vmbootloadertest.sh %s (%s) =====\n' "$loader" "$(date +%T)"
if $install; then
    step "install $loader VM in $VM_DIR"
    stop_vm
    iso="${VM_ISO:-$(ls -t "$repo"/../steammachine-cachyos-live-iso/out/desktop/*.iso 2>/dev/null | head -n 1)}"
    [[ -f "$iso" ]] || { echo "No ISO: set VM_ISO"; exit 2; }
    if [[ -f "$VM_DIR/disk.qcow2" ]]; then
        [[ -t 0 ]] || { echo "$VM_DIR has a disk; run this from a terminal to replace it"; exit 2; }
        read -r -p "Replace $VM_DIR/disk.qcow2? Type YES: " a
        [[ "$a" == YES ]] || exit 1
        rm -f "$VM_DIR/disk.qcow2"
    fi
    VM_BOOTLOADER="$loader" "$here/vminstall.sh" --iso "$iso" < /dev/null || exit 1
fi

step "start $loader as a Steam Machine"
start_vm; waitssh || exit 1
gssh 'sudo cat /sys/class/dmi/id/product_name' 2>/dev/null

step "Steamify's Steam Machine options"
gssh 'sudo mountpoint -q /mnt || sudo mount -t 9p -o trans=virtio,version=9p2000.L repo /mnt; cd /mnt && nohup bash steamify.sh --defaults --options gaming,theme,glyphs,single,launcher,notify,vram,cec,machine,poweroff --boot gamescope > /tmp/steamify.log 2>&1 < /dev/null &'
sleep 20
# [s]: the pattern must not match this ssh command itself.
for _ in $(seq 90); do gssh 'pgrep -f "[s]teamify.sh --defaults" >/dev/null && echo R || echo D' 2>/dev/null | grep -q D && break; sleep 10; done
gssh 'sed "s/\x1b\[[0-9;]*m//g" /tmp/steamify.log | grep -E "^\[(WARN|ERROR)\]" | cut -c1-140'
gssh 'tail -n 1 /tmp/steamify.log | sed "s/\x1b\[[0-9;]*m//g"' | grep -q '^\[OK\] Done' && echo "PASS Steamify finished" || { echo "FAIL Steamify did not finish"; }

step "Steamify's state, OS name, boot loader"; gscript steamify-state.sh | check
step "Steamify's modules"; gscript modules.sh | check
step "boot loader code (legacy kernel parameter removal)"; gscript legacy-param.sh | check
step "kernel update"; gscript kernel-update.sh | check

step "reboot into the default kernel"
if [[ "$loader" == limine ]]; then
    # remember_last_entry: yes boots whatever ran last, not default_entry: pin the default for this test, restore it at the end.
    cur="$(gssh "sudo sed -n 's/^default_entry: *//p' /boot/limine.conf")"
    rem="$(gssh "sudo sed -n 's/^remember_last_entry: *//p' /boot/limine.conf")"
    gssh "sudo sed -i -e 's/^default_entry: .*/default_entry: $cur/' -e 's/^remember_last_entry: .*/remember_last_entry: no/' /boot/limine.conf"
fi
reboot_vm && gscript boot-check.sh | check
a="$(gssh uname -r)"

step "reboot into the other kernel"
case "$loader" in
    systemd-boot)   # the default entry is linux-cachyos.conf (vminstall-post.sh)
        gssh 'sudo bootctl set-oneshot linux-cachyos-lts.conf'; gssh 'sudo systemctl reboot' >/dev/null 2>&1; sleep 25; waitssh ;;
    grub)           # GRUB_DEFAULT = the other kernel in the "Advanced options" submenu (0 = lts, 1 = linux-cachyos), no key presses
        sub=$([[ "$a" == *lts* ]] && echo 1 || echo 0)
        gg="$(gssh "sudo sed -n 's/^GRUB_DEFAULT=//p' /etc/default/grub")"
        gssh "sudo sed -i 's/^GRUB_DEFAULT=.*/GRUB_DEFAULT=\"1>$sub\"/' /etc/default/grub && sudo grub-mkconfig -o /boot/grub/grub.cfg >/dev/null 2>&1"
        reboot_vm ;;
    limine)         # the next entry in limine.conf; remember_last_entry would override default_entry
        gssh "sudo sed -i -e 's/^default_entry: .*/default_entry: $((cur + 1))/' /boot/limine.conf"
        reboot_vm ;;
esac
gscript boot-check.sh | check
b="$(gssh uname -r)"
[[ -n "$a" && -n "$b" && "$a" != "$b" ]] && echo "PASS booted both kernels ($a, $b)" || echo "FAIL both boots ran the same kernel ($a, $b)"
[[ "$loader" == grub ]] && gssh "sudo sed -i 's/^GRUB_DEFAULT=.*/GRUB_DEFAULT=$gg/' /etc/default/grub && sudo grub-mkconfig -o /boot/grub/grub.cfg >/dev/null 2>&1"
[[ "$loader" == limine ]] && gssh "sudo sed -i -e 's/^default_entry: .*/default_entry: $cur/' -e 's/^remember_last_entry: .*/remember_last_entry: ${rem:-yes}/' /boot/limine.conf"

step "DONE"
stop_vm
} 2>&1 | tee "$log" | tee >(sed -u "s/^/[$loader] /" >> "$TEST_LOG") | sed 's/\x1b\[[0-9;]*m//g'
fails="$(grep -c '^FAIL' "$log")"
echo; echo "== $loader: $(grep -c '^PASS' "$log") passed, $fails failed (log: $log)"
grep '^FAIL' "$log"
exit "$fails"
