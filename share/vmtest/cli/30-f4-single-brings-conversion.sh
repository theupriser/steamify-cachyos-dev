# F4: --options theme,single,machine --boot desktop: single brings the conversion; the rest stays off.
sf --defaults --options theme,single,machine --boot desktop >/dev/null; rc=$?
[[ $rc -eq 0 ]] && pass "F4 exit 0" || fail "F4 exit $rc"
expect_on gaming theme single machine
expect_off poweroff cec glyphs launcher notify
systemctl is-enabled steamify-boot-desktop.service >/dev/null 2>&1 && pass "F4 boot-desktop unit enabled" || fail "F4 boot-desktop unit not enabled"
