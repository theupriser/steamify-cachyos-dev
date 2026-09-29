# F3: every item and --boot desktop: all on, the boot-desktop unit enabled, VRAM left out with a warning.
info "applying Steamify (installs packages, builds kernel modules: a few minutes)..."
out=$(sf --defaults --options gaming,theme,glyphs,single,launcher,notify,vram,cec,machine,poweroff --boot desktop); rc=$?
[[ $rc -eq 0 ]] && pass "F3 exit 0" || fail "F3 exit $rc"
expect_on gaming theme glyphs single launcher notify machine poweroff cec
grep -qi "VRAM booster" <<< "$out" && pass "F3 VRAM booster left out with a warning" || fail "F3 no VRAM warning"
is vram && fail "F3 vram is on (the VM has no dmem region)" || pass "F3 vram stays off"
systemctl is-enabled steamify-boot-desktop.service >/dev/null 2>&1 && pass "F3 boot-desktop unit enabled" || fail "F3 boot-desktop unit not enabled"
