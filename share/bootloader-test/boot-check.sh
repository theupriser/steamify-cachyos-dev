#!/bin/bash
# Guest side: after a reboot, the running kernel has Steamify's modules.
pass() { echo "PASS $*"; }; fail() { echo "FAIL $*"; }
k=$(uname -r)
echo "kernel: $k"; echo "cmdline: $(cut -c1-140 /proc/cmdline)"
compgen -G "/usr/lib/modules/$k/updates/dkms/steamify-fremont-poweroff.ko*" >/dev/null && pass "power-off fix built for the running kernel" || fail "no power-off fix for $k"
sudo dmesg | grep -q "steamify_fremont_poweroff" && pass "power-off fix loaded at boot" || fail "power-off fix not loaded"
lsmod | grep -q '^leds_valve' && pass "leds_valve loaded" || fail "leds_valve not loaded"
[[ -z "$(systemctl --failed --no-legend)" ]] && pass "no failed units" || { fail "failed units:"; systemctl --failed --no-legend; }
