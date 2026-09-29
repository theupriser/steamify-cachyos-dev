#!/bin/bash
# Guest side: Steamify's DKMS modules exist for every installed kernel.
# Prints PASS/FAIL lines (scripts/vmbootloadertest.sh counts the FAILs).
pass() { echo "PASS $*"; }; fail() { echo "FAIL $*"; }
kernels=$(ls /usr/lib/modules)
n=$(wc -w <<< "$kernels")
echo "kernels: $(tr '\n' ' ' <<< "$kernels")"
dkms status
[[ $(dkms status | grep -c ': installed') -eq $((3 * n)) ]] && pass "3 DKMS modules x $n kernels installed" || fail "dkms status is not 3 modules x $n kernels"
for k in $kernels; do
    for m in cros-ec-cec leds-valve steamify-fremont-poweroff; do
        compgen -G "/usr/lib/modules/$k/updates/dkms/$m.ko*" >/dev/null && pass "$m for $k" || fail "$m missing for $k"
    done
done
[[ -f /etc/modules-load.d/steamify-fremont-poweroff.conf ]] && pass "modules-load.d has the power-off fix" || fail "no modules-load.d entry"
