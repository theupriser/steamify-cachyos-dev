#!/bin/bash
# Guest side ($LOADER = limine|systemd-boot|grub): Steamify's state as its own
# menu detects it (the same *_status functions), the OS name untouched, and
# the boot loader as expected.
pass() { echo "PASS $*"; }; fail() { echo "FAIL $*"; }
sudo mountpoint -q /mnt || sudo mount -t 9p -o trans=virtio,version=9p2000.L repo /mnt
cd /mnt || exit 1
for lib in $(grep -oP '^for lib in \K.*(?=; do$)' steamify.sh); do
    # shellcheck source=/dev/null
    . "lib/$lib.sh" 2>/dev/null
done
# Items this Steam Machine VM has on after `--options gaming,theme,glyphs,single,launcher,notify,cec,machine,poweroff`.
# HARDWARE=generic (a plain PC): the Steam Machine items (poweroff, cec) must stay off.
for item in gaming theme glyphs single launcher notify; do
    if "${item}_status" 2>/dev/null; then pass "$item is on (the menu shows it ticked)"; else fail "$item is off"; fi
done
for item in poweroff cec; do
    if [[ "${HARDWARE:-fremont}" == generic ]]; then
        if "${item}_status" 2>/dev/null; then fail "$item is on, but this is not a Steam Machine"; else pass "$item is off (not a Steam Machine)"; fi
    else
        if "${item}_status" 2>/dev/null; then pass "$item is on (the menu shows it ticked)"; else fail "$item is off"; fi
    fi
done
# Steamify never renames the OS (limine-snapper-sync / grub-btrfs read it).
grep -qx 'NAME="CachyOS Linux"' /etc/os-release && grep -qx 'PRETTY_NAME="CachyOS"' /etc/os-release && pass "os-release NAME and PRETTY_NAME are CachyOS's" || fail "os-release NAME/PRETTY_NAME changed"
grep -q 'with Steamify' /etc/lsb-release && fail "lsb-release still says 'with Steamify'" || pass "lsb-release name is CachyOS's"
# The boot loader is the one this VM was installed with.
case "$LOADER" in
    limine)       command -v limine-update >/dev/null && [[ -f /etc/default/limine ]] && pass "Limine is installed" || fail "no Limine"
                  grep -q '^TARGET_OS_NAME="CachyOS"' /etc/default/limine && pass "limine TARGET_OS_NAME is set" || fail "TARGET_OS_NAME missing in /etc/default/limine" ;;
    systemd-boot) sudo bootctl status --no-pager 2>/dev/null | grep -q 'Product: systemd-boot' && pass "systemd-boot is the boot loader" || fail "not systemd-boot" ;;
    grub)         sudo bootctl status --no-pager 2>/dev/null | grep -q 'Product: GRUB' && pass "GRUB is the boot loader" || fail "not GRUB" ;;
esac
# "BIOS" menu item: rebooting into the firmware setup must be possible (never trigger it here).
sudo bootctl status --no-pager 2>/dev/null | grep -q 'Boot into FW: supported' && pass "reboot into firmware setup is supported" || fail "firmware setup reboot not supported"
