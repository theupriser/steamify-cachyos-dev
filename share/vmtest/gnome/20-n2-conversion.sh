# GN2: the SteamOS conversion on GDM: autologin, session in AccountsService, GDM-aware session tools, hook, sudoers, GNOME extras.
info "applying the conversion on GNOME (installs gamescope, steam: a few minutes)..."
sf --defaults --options gaming,launcher --boot gamescope >/tmp/gn2.out; rc=$?
[[ $rc -eq 0 ]] && pass "GN2 exit 0" || { fail "GN2 exit $rc: $(grep -m1 ERROR /tmp/gn2.out)"; }
expect_on gaming launcher
conf=/etc/gdm/custom.conf
sed -n '/^\[daemon\]/,/^\[/p' $conf | grep -qx 'AutomaticLoginEnable=True' && pass "GN2 AutomaticLoginEnable=True in [daemon]" || fail "GN2 no AutomaticLoginEnable"
sed -n '/^\[daemon\]/,/^\[/p' $conf | grep -qx "AutomaticLogin=$USER" && pass "GN2 AutomaticLogin=$USER" || fail "GN2 no AutomaticLogin=$USER"
[[ $(grep -c '^AutomaticLogin=' $conf) -eq 1 ]] && pass "GN2 one AutomaticLogin line" || fail "GN2 AutomaticLogin lines: $(grep -c '^AutomaticLogin=' $conf)"
[[ -f $conf.bak-steamify ]] && pass "GN2 custom.conf backup kept" || fail "GN2 no custom.conf backup"
acc=/var/lib/AccountsService/users/$USER
sudo grep -qx 'Session=gamescope-session' $acc && pass "GN2 AccountsService Session=gamescope-session" || fail "GN2 Session: $(sudo grep Session= $acc)"
sudo grep -qx 'XSession=gamescope-session' $acc && pass "GN2 AccountsService XSession=gamescope-session" || fail "GN2 XSession: $(sudo grep XSession= $acc)"
grep -q 'steamify-gdm-relogin' /usr/bin/steamos-session-select && pass "GN2 steamos-session-select is the GDM-aware one" || fail "GN2 steamos-session-select is not ours"
grep -q 'AccountsService' /usr/lib/steamos/steam-set-session && pass "GN2 steam-set-session is the GDM-aware one" || fail "GN2 steam-set-session is not ours"
[[ -f /usr/bin/steamos-session-select.bak-steamify && -f /usr/lib/steamos/steam-set-session.bak-steamify ]] && pass "GN2 CachyOS's tools kept as .bak-steamify" || fail "GN2 no .bak-steamify copies"
[[ -f /etc/pacman.d/hooks/95-steamify-gdm.hook ]] && pass "GN2 pacman hook" || fail "GN2 no pacman hook"
sudo visudo -cf /etc/sudoers.d/steamify-gdm-relogin >/dev/null 2>&1 && pass "GN2 sudoers rule valid" || fail "GN2 sudoers rule missing or invalid"
[[ -x /usr/local/libexec/steamify-gdm-relogin ]] && pass "GN2 relogin helper" || fail "GN2 no relogin helper"
sudo -n -l /usr/local/libexec/steamify-gdm-relogin >/dev/null 2>&1 && pass "GN2 sudo allows the relogin helper without a password" || fail "GN2 sudo -l does not list the helper"
for p in kconfig accountsservice gnome-shell-extension-desktop-icons-ng gnome-shell-extension-appindicator extension-manager gamescope-session-cachyos steam; do
    pacman -Q $p >/dev/null 2>&1 && pass "GN2 $p installed" || fail "GN2 $p missing"
done
pacman -Q plasma-keyboard >/dev/null 2>&1 && fail "GN2 plasma-keyboard installed on GNOME" || pass "GN2 no plasma-keyboard"
pacman -Q plasma-desktop >/dev/null 2>&1 && fail "GN2 Plasma got installed" || pass "GN2 no Plasma pulled in"
sc="$HOME/.local/share/applications/steamify-return-to-gaming-mode.desktop"
[[ -f "$sc" ]] && grep -q 'steamos-session-select' "$sc" && pass "GN2 Return to Gaming Mode in the launcher" || fail "GN2 no Return to Gaming Mode launcher entry"
[[ "$(current_display_manager)" == gdm ]] && pass "GN2 GDM stays the login manager" || fail "GN2 login manager: $(current_display_manager)"
systemctl is-enabled gdm.service >/dev/null 2>&1 && pass "GN2 gdm.service enabled" || fail "GN2 gdm.service not enabled"
# shellcheck on our new tools, and a second apply changes nothing
command -v shellcheck >/dev/null && { shellcheck -S warning -e SC2034,SC2154 -x /mnt/patches/steamify-gdm-*.sh /mnt/lib/desktop.sh /mnt/lib/gnome-theme.sh >/tmp/gn2.sc 2>&1 && pass "GN2 shellcheck clean" || fail "GN2 shellcheck: $(head -3 /tmp/gn2.sc | tr '\n' ' ')"; } || skip "GN2 no shellcheck"
sf --defaults --options gaming,launcher --boot gamescope >/tmp/gn2b.out; [[ $? -eq 0 ]] && pass "GN2 second apply: exit 0" || fail "GN2 second apply failed"
[[ $(grep -c '^AutomaticLogin=' $conf) -eq 1 && $(grep -c 'AutomaticLoginEnable' $conf) -eq 1 ]] && pass "GN2 second apply: no duplicate lines in custom.conf" || fail "GN2 second apply duplicated lines"
dup=""; for f in ~/.local/state/steamify/*; do [ -f "$f" ] && d=$(cut -f1-3 "$f" | sort | uniq -d) && [ -n "$d" ] && dup+="$(basename "$f"): $d; "; done
[[ -z "$dup" ]] && pass "GN2 no duplicate journal entries" || fail "GN2 DUPLICATES: $dup"
