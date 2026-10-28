# since: 2.15.0
# GN4: the SteamOS theme for GNOME: gsettings, GTK4 colors, extensions; off puts everything back.
get() { gsettings get "$@"; }
before_scheme=$(get org.gnome.desktop.interface color-scheme); before_bg=$(get org.gnome.desktop.background picture-uri)
before_layout=$(get org.gnome.desktop.wm.preferences button-layout)
info "applying the GNOME theme (installs cachyos-vapor, downloads the dock: a few minutes)..."
sf --defaults --options gnometheme >/tmp/gn4.out; rc=$?
[[ $rc -eq 0 ]] && pass "GN4 exit 0" || fail "GN4 exit $rc: $(grep -m1 ERROR /tmp/gn4.out)"
expect_on gnometheme
[[ "$(get org.gnome.desktop.interface color-scheme)" == "'prefer-dark'" ]] && pass "GN4 dark style" || fail "GN4 color-scheme: $(get org.gnome.desktop.interface color-scheme)"
[[ "$(get org.gnome.desktop.interface accent-color 2>/dev/null)" == "'blue'" ]] && pass "GN4 blue accent" || skip "GN4 accent-color: $(get org.gnome.desktop.interface accent-color 2>&1 | head -1)"
get org.gnome.desktop.background picture-uri | grep -q 'Steam%20Deck' && pass "GN4 Steam Deck wallpaper" || fail "GN4 wallpaper: $(get org.gnome.desktop.background picture-uri)"
get org.gnome.desktop.wm.preferences button-layout | grep -q minimize && pass "GN4 minimize/maximize buttons" || fail "GN4 button layout"
grep -qF "/* Steamify GNOME theme */" ~/.config/gtk-4.0/gtk.css && pass "GN4 GTK4 colors written" || fail "GN4 no gtk.css mark"
[[ -f ~/.local/share/gnome-shell/extensions/steamify-vapor@steamify.github.io/metadata.json ]] && pass "GN4 Steamify Vapor extension" || fail "GN4 no Steamify Vapor extension"
[[ -f ~/.local/share/gnome-shell/extensions/ubuntu-dock@ubuntu.com/metadata.json ]] && pass "GN4 Ubuntu Dock built" || fail "GN4 no Ubuntu Dock"
[[ -f ~/.local/share/gnome-shell/extensions/tiling-assistant@ubuntu.com/metadata.json ]] && pass "GN4 Tiling Assistant" || fail "GN4 no Tiling Assistant"
sf --defaults --options gnometheme >/dev/null; [[ $? -eq 0 ]] && pass "GN4 second apply: exit 0" || fail "GN4 second apply failed"
[[ $(grep -c "Steamify GNOME theme" ~/.config/gtk-4.0/gtk.css) -eq 1 ]] && pass "GN4 one theme block in gtk.css" || fail "GN4 gtk.css has $(grep -c 'Steamify GNOME theme' ~/.config/gtk-4.0/gtk.css) marks"
sf --defaults --options notify >/dev/null; rc=$?
[[ $rc -eq 0 ]] && pass "GN4 off: exit 0" || fail "GN4 off: exit $rc"
expect_off gnometheme
[[ "$(get org.gnome.desktop.interface color-scheme)" == "$before_scheme" ]] && pass "GN4 off: color-scheme restored" || fail "GN4 off: color-scheme $(get org.gnome.desktop.interface color-scheme), was $before_scheme"
[[ "$(get org.gnome.desktop.background picture-uri)" == "$before_bg" ]] && pass "GN4 off: wallpaper restored" || fail "GN4 off: wallpaper $(get org.gnome.desktop.background picture-uri)"
[[ "$(get org.gnome.desktop.wm.preferences button-layout)" == "$before_layout" ]] && pass "GN4 off: button layout restored" || fail "GN4 off: layout $(get org.gnome.desktop.wm.preferences button-layout)"
[[ ! -e ~/.config/gtk-4.0/gtk.css ]] || ! grep -qF "Steamify GNOME theme" ~/.config/gtk-4.0/gtk.css && pass "GN4 off: GTK4 colors gone" || fail "GN4 off: gtk.css still ours"
[[ ! -e ~/.local/share/gnome-shell/extensions/steamify-vapor@steamify.github.io ]] && pass "GN4 off: our extension removed" || fail "GN4 off: extension left"
