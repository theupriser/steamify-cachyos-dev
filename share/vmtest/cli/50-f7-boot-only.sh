# F7: on an install, --boot desktop, again, --boot gamescope: only Boot into changes; the menu ticks stay.
sf --defaults --options gaming,theme,single,launcher,notify,machine,poweroff >/dev/null
base=$(ticks | sed 's/boot //')
sf --boot desktop >/dev/null; rc=$?
[[ $rc -eq 0 ]] && pass "F7 --boot desktop exit 0" || fail "F7 --boot desktop exit $rc"
systemctl is-enabled steamify-boot-desktop.service >/dev/null 2>&1 && pass "F7 boot-desktop unit enabled" || fail "F7 unit not enabled after --boot desktop"
[[ "$(ticks | sed 's/boot //')" == "$base" ]] && pass "F7 the menu ticks are unchanged" || fail "F7 ticks changed: [$base] -> [$(ticks)]"
out=$(sf --boot desktop); grep -qi "already" <<< "$out" && pass "F7 second --boot desktop says already" || fail "F7 no 'Already starting in desktop': $(tail -n 2 <<< "$out" | tr '\n' ' ')"
sf --boot gamescope >/dev/null; rc=$?
[[ $rc -eq 0 ]] && pass "F7 --boot gamescope exit 0" || fail "F7 --boot gamescope exit $rc"
systemctl is-enabled steamify-boot-desktop.service >/dev/null 2>&1 && fail "F7 unit still enabled after --boot gamescope" || pass "F7 boot-desktop unit disabled again"
[[ "$(ticks | sed 's/boot //')" == "$base" ]] && pass "F7 ticks unchanged after --boot gamescope" || fail "F7 ticks changed after gamescope"
