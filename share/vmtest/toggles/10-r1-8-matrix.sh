# R1.8 (and the matrix in the cachyos-vm-testing skill): switch items off and on and check the state each time.
A=gaming,theme,glyphs,single,launcher,notify,cec,machine,poweroff
apply() { info "apply: $1"; sf --defaults --options "$1" >/dev/null; [[ $? -eq 0 ]] && pass "options $1: exit 0" || fail "options $1: failed"; }
apply "$A"
expect_on gaming theme glyphs single launcher notify cec machine poweroff
[[ "$(current_display_manager)" == sddm ]] && pass "baseline: SDDM (single user)" || fail "baseline display manager: $(current_display_manager)"
# theme off
apply "${A/theme,/}"
expect_off theme; expect_on gaming single machine
# theme on again
apply "$A"; expect_on theme
# single user off: plasmalogin
apply "${A/single,/}"
expect_off single; expect_on gaming
[[ "$(current_display_manager)" == plasmalogin ]] && pass "single off: plasmalogin" || fail "single off: display manager $(current_display_manager)"
# single user on: SDDM again
apply "$A"; expect_on single
[[ "$(current_display_manager)" == sddm ]] && pass "single on: back to SDDM" || fail "single on: display manager $(current_display_manager)"
# Steam Machine support and power-off fix off: the driver goes, then comes back
apply gaming,theme,glyphs,single,launcher,notify,cec
expect_off machine poweroff
[[ ! -f /etc/modules-load.d/steamify-fremont-poweroff.conf ]] && pass "machine off: the power-off modules-load entry is gone" || fail "machine off: modules-load entry still there"
apply "$A"; expect_on machine poweroff
[[ $(dkms status | grep -c ': installed') -ge $((3 * $(ls /usr/lib/modules | wc -w))) ]] && pass "machine on: DKMS installed for every kernel" || fail "machine on: DKMS $(dkms status | tr '\n' ';')"
# HDMI-CEC off and on
apply "${A/cec,/}"; expect_off cec
apply "$A"; expect_on cec
# conversion off: single user goes with it, plasmalogin's autologin is CachyOS's again
apply launcher,notify
expect_off gaming single theme
[[ "$(current_display_manager)" == plasmalogin ]] && pass "conversion off: plasmalogin" || fail "conversion off: display manager $(current_display_manager)"
sed -n '/^\[Autologin\]/,/^\[/p' /etc/plasmalogin.conf 2>/dev/null | grep -q 'Session=plasma' && pass "conversion off: plasmalogin autologin is Session=plasma" || skip "conversion off: no plasmalogin Autologin section (a VM from vminstall.sh has no /etc/plasmalogin.conf, see TESTPLAN Known gaps)"
