# GN6: gaming <-> GNOME on GDM with a stand-in gamescope session (gamescope doesn't render in the VM): boot into it, Switch to Desktop,
# the shortcut's command back, reboot persistence, "boot into the desktop". Needs the host's ssh without polling during a relogin
# (a logged-in ssh session keeps the old user manager alive).
standin() { guest 'f=/usr/share/wayland-sessions/gamescope-session.desktop; sudo cp -n $f $f.real; sudo sed -i "s|^Exec=.*|Exec=/usr/bin/sleep infinity|" $f; echo done' | tail -n 1 | grep -q done; }
in_gnome() { vm_ssh "pgrep -u $VM_USER -x gnome-shell" >/dev/null 2>&1; }
in_standin() { vm_ssh "pgrep -u $VM_USER -f 'sleep infinity'" >/dev/null 2>&1 && ! in_gnome; }
wait_for() { local what="$1" _; for _ in $(seq 40); do "$what" && return 0; sleep 3; done; return 1; }
info "applying the conversion (a few minutes)..."
guest 'sf --defaults --options gaming --boot gamescope >/dev/null; echo done' | tail -n 1 | grep -q done && pass "GN6 conversion applied" || { fail "GN6 apply"; return 0 2>/dev/null || exit 0; }
standin && pass "GN6 stand-in gamescope session in place" || fail "GN6 stand-in"
# 1. reboot: GDM logs in by itself, into gamescope (the stand-in)
reboot_guest && pass "GN6 the VM is back after the reboot" || { fail "GN6 no ssh after the reboot"; return 0 2>/dev/null || exit 0; }
wait_for in_standin && pass "GN6 boot: autologin into the gamescope session" || fail "GN6 boot: not in gamescope (gnome-shell: $(in_gnome && echo yes || echo no))"
# 2. Switch to Desktop (what Steam's button runs)
vm_ssh "XDG_RUNTIME_DIR=/run/user/\$(id -u) systemd-run --user --pipe --quiet /usr/bin/steamos-session-select desktop" >/dev/null 2>&1; sleep 45
wait_for in_gnome && pass "GN6 steamos-session-select desktop -> GNOME" || fail "GN6 switch to the desktop: no gnome-shell"
# 3. Return to Gaming Mode (the shortcut's command)
sc='~/.local/share/applications/steamify-return-to-gaming-mode.desktop'
cmd=$(vm_ssh "sed -n 's/^Exec=//p' $sc | head -n 1" 2>/dev/null)
[[ -n "$cmd" ]] && pass "GN6 shortcut Exec: $cmd" || fail "GN6 the shortcut has no Exec"
vm_ssh "XDG_RUNTIME_DIR=/run/user/\$(id -u) systemd-run --user --pipe --quiet $cmd" >/dev/null 2>&1; sleep 45
wait_for in_standin && pass "GN6 Return to Gaming Mode -> gamescope" || fail "GN6 back to gaming: not in the stand-in"
# 4. desktop again, then the GNOME session ends: the next login is gamescope (Deck behaviour)
vm_ssh "XDG_RUNTIME_DIR=/run/user/\$(id -u) systemd-run --user --pipe --quiet /usr/bin/steamos-session-select desktop" >/dev/null 2>&1; sleep 45
wait_for in_gnome && pass "GN6 desktop again" || fail "GN6 second switch to the desktop failed"
# 5. boot into the desktop: reboot lands in GNOME; then back to gamescope
guest 'sf --boot desktop >/dev/null; echo done' | tail -n 1 | grep -q done && pass "GN6 --boot desktop" || fail "GN6 --boot desktop"
guest 'systemctl is-enabled steamify-boot-desktop.service' | tail -n 1 | grep -q enabled && pass "GN6 boot-desktop unit enabled" || fail "GN6 boot-desktop unit not enabled"
guest 'grep ExecStart=/usr/lib/steamos /etc/systemd/system/steamify-boot-desktop.service' | grep -q 'steam-set-session desktop' && pass "GN6 the unit asks for the preferred desktop" || fail "GN6 unit: $(guest 'grep ExecStart= /etc/systemd/system/steamify-boot-desktop.service' | tr '\n' ' ')"
reboot_guest; wait_for in_gnome && pass "GN6 reboot with 'boot into desktop': GNOME" || fail "GN6 boot into desktop: no gnome-shell"
guest 'sf --boot gamescope >/dev/null; echo done' | tail -n 1 | grep -q done && pass "GN6 --boot gamescope" || fail "GN6 --boot gamescope"
reboot_guest; wait_for in_standin && pass "GN6 reboot with 'boot into gaming': gamescope" || fail "GN6 boot into gaming: not in the stand-in"
# 6. the GDM tools survive a package update of gamescope-session-cachyos (the pacman hook)
guest 'sudo pacman -S --noconfirm gamescope-session-cachyos >/dev/null 2>&1; grep -q steamify-gdm-relogin /usr/bin/steamos-session-select && echo ours' | tail -n 1 | grep -q ours && pass "GN6 pacman hook puts our tools back after a reinstall" || fail "GN6 the hook did not restore our session tools"
