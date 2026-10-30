# since: 2.15.0
# F1-F7: Fremont fan monitoring / control (the "fancontrol" item below Steam Machine support) with the faked Steam Machine:
# install, modules for every kernel, ownership (pacman's package, or the sources Steamify stages when the repository can't be
# used), autoload, jupiter-fan-control, re-apply, removal. The VM has no Valve EC: binding and RPM are the real machine's.
# base: applied
OPTS=gaming,theme,glyphs,single,launcher,notify,cec,machine,poweroff
info "applying Steamify with the fan item (builds kernel modules: a few minutes)..."
sf --defaults --options $OPTS,fancontrol >/dev/null; rc=$?
[[ $rc -eq 0 ]] && pass "F1 Steamify applied with fancontrol (exit 0)" || fail "F1 Steamify exit $rc"
is fancontrol && pass "F1 fancontrol is on" || fail "F1 fancontrol is off"
# F2
for k in $(ls /usr/lib/modules); do
    dkms status -k "$k" steamify-fancontrol 2>/dev/null | grep -q installed && pass "F2 DKMS installed for $k" || fail "F2 no DKMS install for $k"
    n=$(find /usr/lib/modules/$k -name 'steamdeck.ko*' -o -name 'steamdeck_hwmon.ko*' 2>/dev/null | wc -l)
    [[ $n -ge 2 ]] && pass "F2 steamdeck and steamdeck_hwmon exist for $k" || fail "F2 only $n fan modules for $k"
done
# F3: who owns /usr/src/steamify-fancontrol-1
if pacman -Q steamify-fancontrol-dkms >/dev/null 2>&1; then
    [[ "$(pacman -Qqo /usr/src/steamify-fancontrol-1/dkms.conf 2>/dev/null)" == steamify-fancontrol-dkms ]] && pass "F3 pacman owns the DKMS tree (the repository's package)" || fail "F3 the package is installed but does not own the tree"
else
    [[ -f /usr/src/steamify-fancontrol-1/.steamify-owner ]] && pass "F3 Steamify's staged tree carries its owner marker (the fallback; the package is not in the repository yet)" || fail "F3 no package and no owner marker"
fi
# F4
grep -qx steamdeck /etc/modules-load.d/steamify-fancontrol.conf && grep -qx steamdeck_hwmon /etc/modules-load.d/steamify-fancontrol.conf && pass "F4 autoload names both modules" || fail "F4 autoload file wrong"
pacman -Q jupiter-fan-control >/dev/null 2>&1 && pass "F4 jupiter-fan-control installed" || fail "F4 jupiter-fan-control missing"
pacman -Qi jupiter-fan-control 2>/dev/null | grep -qi 'cachyos' && pass "F4 jupiter-fan-control is CachyOS's" || info "F4 repository of jupiter-fan-control not shown"
# F5: a second run changes nothing and keeps it on
sf --defaults --options $OPTS,fancontrol >/dev/null; rc=$?
[[ $rc -eq 0 ]] && is fancontrol && pass "F5 re-apply: exit 0, still on" || fail "F5 re-apply exit $rc / not on"
# F6: pacman's DKMS hook reads dkms.conf without a kernel: it must not exclude every kernel (the hook then never builds it)
(
    unset kernel_config BUILD_EXCLUSIVE_KERNEL
    # shellcheck source=/dev/null
    source /usr/src/steamify-fancontrol-1/dkms.conf 2>/dev/null
    [[ -z "${BUILD_EXCLUSIVE_KERNEL[*]:-}" ]]
) && pass "F6 dkms.conf leaves BUILD_EXCLUSIVE_KERNEL unset when sourced without a kernel" || fail "F6 dkms.conf excludes kernels for pacman's hook"
# F7: removal
sf --defaults --options $OPTS >/dev/null; rc=$?
[[ $rc -eq 0 ]] && pass "F7 removal run exit 0" || fail "F7 removal exit $rc"
is fancontrol && fail "F7 fancontrol still on" || pass "F7 fancontrol is off"
pacman -Q jupiter-fan-control >/dev/null 2>&1 && fail "F7 jupiter-fan-control still installed" || pass "F7 jupiter-fan-control removed"
pacman -Q steamify-fancontrol-dkms >/dev/null 2>&1 && fail "F7 package still installed" || pass "F7 no fan package left"
[[ -e /usr/src/steamify-fancontrol-1 ]] && fail "F7 /usr/src/steamify-fancontrol-1 left" || pass "F7 DKMS tree removed"
[[ -n "$(dkms status 2>/dev/null | grep steamdeck)" ]] && fail "F7 DKMS still lists steamdeck" || pass "F7 DKMS lists no steamdeck"
[[ -e /etc/modules-load.d/steamify-fancontrol.conf ]] && fail "F7 autoload file left" || pass "F7 autoload removed"
is poweroff && is machine && pass "F7 the rest of Steam Machine support is untouched" || fail "F7 machine/poweroff changed"
