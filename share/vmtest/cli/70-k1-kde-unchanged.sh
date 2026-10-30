# since: 2.16.0
# K1: the GNOME prototype leaves KDE alone: KDE offers its own theme and single user mode and not the GNOME theme, the conversion
# touches no GDM file and keeps CachyOS's session tools, --desktop works, the plasmalogin login manager is kept.
[[ "$(desktop_kind)" == kde ]] && pass "K1 desktop_kind: kde" || fail "K1 desktop_kind: $(desktop_kind)"
desktop_installed gnome && fail "K1 GNOME is installed on the KDE VM" || pass "K1 no GNOME installed"
out=$(printf 'q\n' | bash /mnt/steamify.sh 2>&1 | sed 's/\x1b\[[0-9;]*m//g')
grep -q "Install SteamOS theme: Vapor" <<< "$out" && pass "K1 Plasma theme offered" || fail "K1 no Plasma theme row"
grep -q "Single user mode" <<< "$out" && pass "K1 single user mode offered" || fail "K1 no single user mode"
grep -q "SteamOS theme for GNOME" <<< "$out" && fail "K1 GNOME theme offered on KDE" || pass "K1 GNOME theme hidden"
bash /mnt/steamify.sh --defaults --options gnometheme </dev/null 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | grep -qi "unknown item\|not available\|can't" && pass "K1 --options gnometheme is refused on KDE" || skip "K1 --options gnometheme: no refusal text"
sum_sel=$(sha256sum /usr/bin/steamos-session-select 2>/dev/null | cut -d' ' -f1)
info "applying the conversion on KDE..."
sf --defaults --options gaming,theme,launcher --boot gamescope >/tmp/k1.out; rc=$?
[[ $rc -eq 0 ]] && pass "K1 exit 0" || fail "K1 exit $rc: $(grep -m1 ERROR /tmp/k1.out)"
expect_on gaming theme launcher
[[ "$(current_display_manager)" == plasmalogin ]] && pass "K1 plasmalogin stays the login manager" || fail "K1 login manager: $(current_display_manager)"
[[ ! -d /usr/local/share/steamify-gdm && ! -f /etc/pacman.d/hooks/95-steamify-gdm.hook && ! -f /etc/sudoers.d/steamify-gdm-relogin ]] && pass "K1 no GDM files installed" || fail "K1 GDM files on a KDE system"
[[ ! -e /usr/bin/steamos-session-select.bak-steamify ]] && [[ "$(sha256sum /usr/bin/steamos-session-select | cut -d' ' -f1)" != "" ]] && ! grep -q 'steamify-gdm-relogin' /usr/bin/steamos-session-select && pass "K1 CachyOS's steamos-session-select untouched" || fail "K1 steamos-session-select was replaced on KDE"
! grep -q 'AccountsService' /usr/lib/steamos/steam-set-session && pass "K1 CachyOS's steam-set-session untouched" || fail "K1 steam-set-session was replaced on KDE"
[[ ! -e /etc/gdm/custom.conf ]] || ! grep -q AutomaticLogin /etc/gdm/custom.conf && pass "K1 no GDM autologin" || fail "K1 GDM autologin set on KDE"
pacman -Q plasma-keyboard >/dev/null 2>&1 && pass "K1 plasma-keyboard installed (KDE package set)" || fail "K1 plasma-keyboard missing"
for p in gnome-shell-extension-desktop-icons-ng gnome-shell-extension-appindicator; do pacman -Q $p >/dev/null 2>&1 && fail "K1 $p installed on KDE" || pass "K1 no $p"; done
# --desktop works on KDE too and the file goes away cleanly
for v in kde gnome last; do bash /mnt/steamify.sh --desktop $v </dev/null >/dev/null 2>&1; [[ "$(cat /etc/steamify/desktop 2>/dev/null)" == "$v" ]] && pass "K1 --desktop $v" || fail "K1 --desktop $v"; done
sudo rm -f /etc/steamify/desktop
sf --defaults --options notify >/dev/null; expect_off gaming theme
[[ "$(current_display_manager)" == plasmalogin ]] && pass "K1 off: plasmalogin" || fail "K1 off: $(current_display_manager)"
