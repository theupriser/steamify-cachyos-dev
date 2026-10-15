# GN7: KDE and GNOME installed together: the login manager stays, both themes are offered, the preferred desktop decides.
info "installing Plasma next to GNOME (a few minutes)..."
sudo pacman -S --needed --noconfirm plasma-desktop >/tmp/gn7.pac 2>&1; rc=$?
[[ $rc -eq 0 ]] && pass "GN7 plasma-desktop installed" || { fail "GN7 plasma-desktop: $(tail -n 2 /tmp/gn7.pac | tr '\n' ' ')"; exit 0; }
desktop_installed kde && desktop_installed gnome && pass "GN7 both desktops installed" || fail "GN7 desktop_installed"
menu() { printf "$1" | bash /mnt/steamify.sh 2>&1 | sed 's/\x1b\[[0-9;]*m//g'; }
out=$(menu 'q\n')
grep -q "SteamOS theme for GNOME" <<< "$out" && pass "GN7 GNOME theme offered" || fail "GN7 no GNOME theme row"
grep -q "Install SteamOS theme: Vapor" <<< "$out" && pass "GN7 Plasma theme offered too" || fail "GN7 no Plasma theme row"
grep -q "Single user mode" <<< "$out" && pass "GN7 single user mode offered" || fail "GN7 no single user mode"
[[ "$(current_display_manager)" == gdm ]] && pass "GN7 still GDM" || fail "GN7 display manager: $(current_display_manager)"
choose_login_manager; [[ "$LOGIN_MANAGER" == gdm ]] && pass "GN7 choose_login_manager keeps GDM" || fail "GN7 choose_login_manager: $LOGIN_MANAGER"
info "applying the conversion with both desktops..."
sf --defaults --options gaming --boot gamescope >/tmp/gn7.out; [[ $? -eq 0 ]] && pass "GN7 conversion applied" || fail "GN7 apply: $(grep -m1 ERROR /tmp/gn7.out)"
[[ "$(current_display_manager)" == gdm ]] && pass "GN7 GDM is still the login manager after the conversion" || fail "GN7 login manager changed to $(current_display_manager)"
grep -q 'AccountsService' /usr/lib/steamos/steam-set-session && pass "GN7 our session tools are in (Plasma is installed too)" || fail "GN7 session tools not ours"
tool=/usr/lib/steamos/steam-set-session
res() { bash -c "source <(sed -n '/^have_session()/p;/^resolve_desktop()/,/^}/p' $tool); resolve_desktop"; }
sudo mkdir -p /etc/steamify /var/lib/steamify
for pair in "kde plasma.desktop" "gnome gnome.desktop"; do
    set -- $pair; echo $1 | sudo tee /etc/steamify/desktop >/dev/null
    got=$(res); [[ "$got" == "$2" ]] && pass "GN7 preferred $1 -> $2" || fail "GN7 preferred $1 -> $got"
done
echo last | sudo tee /etc/steamify/desktop >/dev/null
echo gnome | sudo tee /var/lib/steamify/last-desktop >/dev/null; [[ "$(res)" == gnome.desktop ]] && pass "GN7 last used gnome -> gnome.desktop" || fail "GN7 last=gnome -> $(res)"
echo kde | sudo tee /var/lib/steamify/last-desktop >/dev/null; [[ "$(res)" == plasma.desktop ]] && pass "GN7 last used kde -> plasma.desktop" || fail "GN7 last=kde -> $(res)"
# the GNOME theme and the KDE theme are independent
sf --defaults --options gaming,gnometheme >/dev/null; [[ $? -eq 0 ]] && pass "GN7 GNOME theme with both desktops" || fail "GN7 GNOME theme failed"
expect_on gnometheme; expect_off theme
