#!/bin/bash
# Guest side: after a reboot, the running kernel has Steamify's modules.
pass() { echo "PASS $*"; }; fail() { echo "FAIL $*"; }
k=$(uname -r)
echo "kernel: $k"; echo "cmdline: $(cut -c1-140 /proc/cmdline)"
if [[ "${HARDWARE:-fremont}" == generic ]]; then
    lsmod | grep -qE "^(steamify_fremont_poweroff|leds_valve)" && fail "Steam Machine modules loaded on a plain PC" || pass "no Steam Machine modules loaded (not a Steam Machine)"
else
compgen -G "/usr/lib/modules/$k/updates/dkms/steamify-fremont-poweroff.ko*" >/dev/null && pass "power-off fix built for the running kernel" || fail "no power-off fix for $k"
# Loaded (a real Steam Machine), or tried at boot and refused with "No such device" (the VM has no AMD GPIO
# controller, so the module returns -ENODEV silently). The refusal is in the journal; it only sometimes
# reaches dmesg, which is what this used to grep.
if lsmod | grep -q '^steamify_fremont_poweroff'; then pass "power-off fix loaded at boot"
elif sudo journalctl -b -q --no-pager -u systemd-modules-load | grep -q "steamify_fremont_poweroff.*No such device"; then
    pass "power-off fix tried at boot (No such device: no AMD GPIO controller in the VM)"
else fail "power-off fix not loaded, and not tried at boot"; fi
lsmod | grep -q '^leds_valve' && pass "leds_valve loaded" || fail "leds_valve not loaded"
fi
[[ -z "$(systemctl --failed --no-legend)" ]] && pass "no failed units" || { fail "failed units:"; systemctl --failed --no-legend; }
# B1: booted through the loader's own EFI boot entry, not the firmware's automatic disk entry (the
# fallback path \EFI\BOOT\BOOTX64.EFI) and not an entry without a partition (HD(0,GPT,0000...)).
cur=$(sudo efibootmgr | sed -n 's/^BootCurrent: //p')
entry=$(sudo efibootmgr -v | grep -a "^Boot$cur")
if [[ -n "$cur" && "$entry" != *auto_created_boot_option* && "$entry" =~ HD\(([0-9]+),GPT,([0-9a-fA-F-]+) \
      && "${BASH_REMATCH[1]}" != 0 && "${BASH_REMATCH[2]}" != 00000000-0000-* ]]; then
    pass "booted through its own EFI entry: $(cut -f1 <<< "$entry" | cut -c1-60)"
else
    fail "not booted through its own EFI entry (BootCurrent $cur: $(cut -c1-120 <<< "$entry"))"
fi
