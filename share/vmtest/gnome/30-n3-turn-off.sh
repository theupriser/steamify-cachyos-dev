# since: 2.15.0
# GN3: turning the conversion off restores GDM: custom.conf, CachyOS's own session tools, no hook, no sudoers rule.
conf=/etc/gdm/custom.conf
sudo cp -a $conf /tmp/custom.conf.orig
sum_sel=$(sudo sha256sum /usr/bin/steamos-session-select 2>/dev/null | cut -d' ' -f1); sum_set=$(sudo sha256sum /usr/lib/steamos/steam-set-session 2>/dev/null | cut -d' ' -f1)
info "applying, then turning everything off..."
sf --defaults --options gaming,launcher --boot gamescope >/dev/null; expect_on gaming
sf --defaults --options notify >/dev/null; rc=$?
[[ $rc -eq 0 ]] && pass "GN3 off: exit 0" || fail "GN3 off: exit $rc"
expect_off gaming launcher
# (the test VM's GDM already autologs in, from vminstall.sh: the file must be exactly what it was)
diff <(grep -v '^#' /tmp/custom.conf.orig) <(grep -v '^#' $conf) >/dev/null && pass "GN3 custom.conf is the original again" || fail "GN3 custom.conf differs from the original"
[[ ! -e $conf.bak-steamify ]] && pass "GN3 backup removed" || fail "GN3 backup left"
[[ ! -f /etc/pacman.d/hooks/95-steamify-gdm.hook && ! -f /etc/sudoers.d/steamify-gdm-relogin && ! -e /usr/local/libexec/steamify-gdm-relogin && ! -d /usr/local/share/steamify-gdm ]] && pass "GN3 hook, sudoers rule, helper and our tools are gone" || fail "GN3 leftovers: $(ls /etc/pacman.d/hooks/95-steamify-gdm.hook /etc/sudoers.d/steamify-gdm-relogin /usr/local/libexec/steamify-gdm-relogin /usr/local/share/steamify-gdm 2>&1 | grep -v 'No such' | tr '\n' ' ')"
! grep -q 'steamify-gdm-relogin' /usr/bin/steamos-session-select 2>/dev/null && pass "GN3 steamos-session-select is CachyOS's again" || fail "GN3 steamos-session-select is still ours"
! grep -q 'AccountsService' /usr/lib/steamos/steam-set-session 2>/dev/null && pass "GN3 steam-set-session is CachyOS's again" || fail "GN3 steam-set-session is still ours"
[[ "$(current_display_manager)" == gdm ]] && pass "GN3 GDM still the login manager (not switched to plasmalogin)" || fail "GN3 login manager: $(current_display_manager)"
[[ ! -f "$HOME/.local/share/applications/steamify-return-to-gaming-mode.desktop" ]] && pass "GN3 launcher entry gone" || fail "GN3 launcher entry left"
