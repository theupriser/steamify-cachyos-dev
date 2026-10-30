# since: 2.15.0
# FC1-FC7: Fremont fan monitoring / control (the "fancontrol" item below Steam Machine support) with the faked Steam Machine:
# install, modules for every kernel, ownership (pacman's package, or the sources Steamify stages when the repository can't be
# used), autoload, jupiter-fan-control, re-apply, removal. The VM has no Valve EC: binding and RPM are the real machine's.
# base: applied
OPTS=gaming,theme,glyphs,single,launcher,notify,cec,machine,poweroff
info "applying Steamify with the fan item (builds kernel modules: a few minutes)..."
sf --defaults --options $OPTS,fancontrol >/dev/null; rc=$?
[[ $rc -eq 0 ]] && pass "FC1 Steamify applied with fancontrol (exit 0)" || fail "FC1 Steamify exit $rc"
is fancontrol && pass "FC1 fancontrol is on" || fail "FC1 fancontrol is off"
# FC2
for k in $(ls /usr/lib/modules); do
    dkms status -k "$k" steamify-fancontrol 2>/dev/null | grep -q installed && pass "FC2 DKMS installed for $k" || fail "FC2 no DKMS install for $k"
    n=$(find /usr/lib/modules/$k -name 'steamdeck.ko*' -o -name 'steamdeck_hwmon.ko*' 2>/dev/null | wc -l)
    [[ $n -ge 2 ]] && pass "FC2 steamdeck and steamdeck_hwmon exist for $k" || fail "FC2 only $n fan modules for $k"
done
# FC3: who owns /usr/src/steamify-fancontrol-1
if pacman -Q steamify-fancontrol-dkms >/dev/null 2>&1; then
    [[ "$(pacman -Qqo /usr/src/steamify-fancontrol-1/dkms.conf 2>/dev/null)" == steamify-fancontrol-dkms ]] && pass "FC3 pacman owns the DKMS tree (the repository's package)" || fail "FC3 the package is installed but does not own the tree"
else
    [[ -f /usr/src/steamify-fancontrol-1/.steamify-owner ]] && pass "FC3 Steamify's staged tree carries its owner marker (the fallback; the package is not in the repository yet)" || fail "FC3 no package and no owner marker"
fi
# FC4
grep -qx steamdeck /etc/modules-load.d/steamify-fancontrol.conf && grep -qx steamdeck_hwmon /etc/modules-load.d/steamify-fancontrol.conf && pass "FC4 autoload names both modules" || fail "FC4 autoload file wrong"
pacman -Q jupiter-fan-control >/dev/null 2>&1 && pass "FC4 jupiter-fan-control installed" || fail "FC4 jupiter-fan-control missing"
pacman -Qi jupiter-fan-control 2>/dev/null | grep -qi 'cachyos' && pass "FC4 jupiter-fan-control is CachyOS's" || info "FC4 repository of jupiter-fan-control not shown"
# FC5: a second run changes nothing and keeps it on
sf --defaults --options $OPTS,fancontrol >/dev/null; rc=$?
[[ $rc -eq 0 ]] && is fancontrol && pass "FC5 re-apply: exit 0, still on" || fail "FC5 re-apply exit $rc / not on"
# FC6: pacman's DKMS hook reads dkms.conf without a kernel: it must not exclude every kernel (the hook then never builds it)
(
    unset kernel_config BUILD_EXCLUSIVE_KERNEL
    # shellcheck source=/dev/null
    source /usr/src/steamify-fancontrol-1/dkms.conf 2>/dev/null
    [[ -z "${BUILD_EXCLUSIVE_KERNEL[*]:-}" ]]
) && pass "FC6 dkms.conf leaves BUILD_EXCLUSIVE_KERNEL unset when sourced without a kernel" || fail "FC6 dkms.conf excludes kernels for pacman's hook"
# FC7: removal
sf --defaults --options $OPTS >/dev/null; rc=$?
[[ $rc -eq 0 ]] && pass "FC7 removal run exit 0" || fail "FC7 removal exit $rc"
is fancontrol && fail "FC7 fancontrol still on" || pass "FC7 fancontrol is off"
pacman -Q jupiter-fan-control >/dev/null 2>&1 && fail "FC7 jupiter-fan-control still installed" || pass "FC7 jupiter-fan-control removed"
pacman -Q steamify-fancontrol-dkms >/dev/null 2>&1 && fail "FC7 package still installed" || pass "FC7 no fan package left"
[[ -e /usr/src/steamify-fancontrol-1 ]] && fail "FC7 /usr/src/steamify-fancontrol-1 left" || pass "FC7 DKMS tree removed"
[[ -n "$(dkms status 2>/dev/null | grep steamdeck)" ]] && fail "FC7 DKMS still lists steamdeck" || pass "FC7 DKMS lists no steamdeck"
[[ -e /etc/modules-load.d/steamify-fancontrol.conf ]] && fail "FC7 autoload file left" || pass "FC7 autoload removed"
is poweroff && is machine && pass "FC7 the rest of Steam Machine support is untouched" || fail "FC7 machine/poweroff changed"
