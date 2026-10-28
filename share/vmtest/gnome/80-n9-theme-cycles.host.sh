# since: 2.15.0
# GN9: GNOME theme on/off/on/off with a real relogin after each (what roughed up GNOME on the RTX 5080 PC: no top bar icons, search broken).
# After every step: the dash favorites, gio list-apps, icon dirs, enabled extensions, shell errors, and the same checks as a fresh login.
clear_screen() { vm_ssh "pkill cachyos-hello; pkill -f 'cachyos-hello'" >/dev/null 2>&1; python3 "$repo/scripts/qmpkey.py" "$VM_DIR/qmp.sock" esc esc >/dev/null 2>&1; sleep 3; }
shot() { clear_screen; mkdir -p /tmp/gn9-shots; python3 "$repo/scripts/qmpshot.py" "$VM_DIR/qmp.sock" "/tmp/gn9-shots/$1.png" >/dev/null 2>&1 && info "screenshot /tmp/gn9-shots/$1.png"; }
in_gnome() { vm_ssh "pgrep -u $VM_USER -x gnome-shell" >/dev/null 2>&1; }
wait_for() { local what="$1" _; for _ in $(seq 40); do "$what" && return 0; sleep 3; done; return 1; }
relogin() {   # what the app does: the helper logs into GNOME and puts the account's session (gamescope) back. No polling while it runs.
    vm_ssh "sudo -n /usr/local/libexec/steamify-gdm-relogin gnome" >/dev/null 2>&1
    sleep 45; waitssh; wait_for in_gnome || return 1; sleep 15
}
snap() {   # snap <label>: what a healthy GNOME has, written to /tmp/gn9-<label>.txt on the guest and judged here
    guest "
l=$1; o=/tmp/gn9-\$l.txt
{ echo '== apps';       gio list-apps 2>&1 | wc -l
  echo '== favorites';  gsettings get org.gnome.shell favorite-apps
  echo '== extensions'; gsettings get org.gnome.shell enabled-extensions; gnome-extensions list --enabled 2>&1
  echo '== ext state'; for e in ubuntu-dock@ubuntu.com tiling-assistant@ubuntu.com steamify-vapor@steamify.github.io ding@rastersoft.com appindicatorsupport@rgcjonas.gmail.com; do printf '%s ' \$e; gnome-extensions info \$e 2>&1 | tr '\\n' ' ' | sed 's/  */ /g'; echo; done
  echo '== shell journal'; journalctl --user -b --no-pager | grep -i 'gnome-shell\|extension' | grep -vi 'Started\|Created slice\|Stopped\|Deactivated' | tail -45 | cut -c1-230
  echo '== ext list'; gnome-extensions list 2>&1 | head; busctl --user call org.gnome.Shell /org/gnome/Shell org.gnome.Shell.Extensions ListExtensions 2>&1 | cut -c1-300
  echo '== gtk-theme';  gsettings get org.gnome.desktop.interface gtk-theme; gsettings get org.gnome.desktop.interface icon-theme
  echo '== hicolor';    find ~/.local/share/icons /usr/local/share/icons -maxdepth 2 2>&1 | sort; ls ~/.local/share/icons/hicolor/index.theme /usr/local/share/icons/hicolor/index.theme 2>&1
  echo '== shell log';  journalctl --user -b -u 'gnome-shell*' --no-pager 2>/dev/null | grep -ci 'error\|could not\|failed'
  echo '== shell err';  journalctl --user -b --no-pager 2>/dev/null | grep -i 'gnome-shell' | grep -i 'could not load\|pixbuf\|JS ERROR\|TypeError' | sort | uniq -c | sort -rn | head -8
  echo '== icon lookup'
  python3 - <<'PY'
import gi; gi.require_version('Gtk','4.0'); from gi.repository import Gtk
t=Gtk.IconTheme.get_for_display(__import__('gi.repository.Gdk',fromlist=['Gdk']).Display.get_default())
for n in ('network-wireless-signal-good-symbolic','audio-volume-high-symbolic','system-search-symbolic','firefox','steamify'):
    print(n, t.has_icon(n))
PY
  echo '== dock';       gnome-extensions info ubuntu-dock@ubuntu.com 2>&1 | grep -i 'state\|enabled'; ls /usr/share/glib-2.0/schemas ~/.local/share/glib-2.0/schemas 2>/dev/null | grep -i 'dock\|tiling'
  gsettings get org.gnome.shell.extensions.dash-to-dock dock-position 2>&1 | head -1
  echo '== search';     gsettings get org.gnome.desktop.search-providers disabled; gsettings get org.gnome.desktop.search-providers disable-external; gsettings get org.gnome.desktop.search-providers sort-order
  ls /usr/share/gnome-shell/search-providers | wc -l
  busctl --user list 2>/dev/null | grep -ci 'org.gnome.Nautilus\|Settings\|Calculator\|Characters\|Contacts\|Software\|Terminal'
  gio list-apps 2>/dev/null | head -3
} > \$o 2>&1; cat \$o"
}
[[ $(guest 'sf --defaults --options gaming --boot gamescope >/dev/null; echo rc=$?' | tail -n 1) == rc=0 ]] && pass "GN9 conversion applied first (as on the hardware)" || fail "GN9 conversion"
guest 'sf --defaults --options gaming,launcher --boot gamescope >/dev/null; echo rc=$?' | tail -n 1 | grep -q rc=0 && pass "GN9 launcher option on" || fail "GN9 launcher option"
base_gtk=$(guest 'gsettings get org.gnome.desktop.interface gtk-theme' | tail -n 1)
info "GN9 baseline (before anything)"; snap base | sed 's/^/    /' > /tmp/gn9-base.host
grep -q 'network-wireless-signal-good-symbolic True' /tmp/gn9-base.host && pass "GN9 baseline: system icons resolve" || info "GN9 baseline icons: $(grep -c True /tmp/gn9-base.host) true"
apps0=$(grep -A1 '== apps' /tmp/gn9-base.host | tail -n 1 | tr -d ' ')
cycle=0
for step in on off on off; do
    cycle=$((cycle+1))
    if [[ $step == on ]]; then guest 'sf --defaults --options gaming,launcher,gnometheme --boot gamescope >/tmp/gn9.out; echo rc=$?' | tail -n 1 | grep -q rc=0 && pass "GN9.$cycle theme on" || fail "GN9.$cycle theme on failed"
    else guest 'sf --defaults --options gaming,launcher --boot gamescope >/tmp/gn9.out; echo rc=$?' | tail -n 1 | grep -q rc=0 && pass "GN9.$cycle theme off" || fail "GN9.$cycle theme off failed"; fi
    sleep 5; shot "$cycle$step-applied"
    relogin && pass "GN9.$cycle relogin into GNOME" || { fail "GN9.$cycle relogin: no gnome-shell"; continue; }
    shot "$cycle$step-relogin"
    snap "$cycle$step" | sed 's/^/    /' > "/tmp/gn9-$cycle$step.host"
    cat "/tmp/gn9-$cycle$step.host"
    apps=$(grep -A1 '== apps' "/tmp/gn9-$cycle$step.host" | tail -n 1 | tr -d ' ')
    [[ -n "$apps" && "$apps" -ge "${apps0:-1}" ]] 2>/dev/null && pass "GN9.$cycle gio list-apps: $apps (was $apps0)" || fail "GN9.$cycle gio list-apps: $apps (was $apps0)"
    grep -q 'network-wireless-signal-good-symbolic True' "/tmp/gn9-$cycle$step.host" && pass "GN9.$cycle system icons resolve" || fail "GN9.$cycle system icons do not resolve"
    if [[ $step == on ]]; then bad=$(grep -A5 '== ext state' "/tmp/gn9-$cycle$step.host" | grep -vi 'state: *active' | grep '@' ); [[ -z "$bad" ]] && pass "GN9.$cycle all five extensions ACTIVE" || fail "GN9.$cycle extensions not active: $bad"; fi
    guest 'pgrep -u $USER -x gnome-shell >/dev/null && echo up' | tail -n 1 | grep -q up && pass "GN9.$cycle shell running" || fail "GN9.$cycle no shell"
done
[[ "$(guest 'gsettings get org.gnome.desktop.interface gtk-theme' | tail -n 1)" == "$base_gtk" ]] && pass "GN9 gtk-theme as before ($base_gtk)" || fail "GN9 gtk-theme changed: was $base_gtk"
