# since: 2.14.0
# S1 (#109): "Start Steam silently in desktop mode" (`silent`) writes Steam's own autostart entry with
# `-steamdeck -silent` (the flag gaming mode starts Steam with; without it the two sessions disagree on the
# client branch and the Steam Beta choice is lost). Covers the entry from the system steam.desktop and from the
# built-in template, re-applying, status, the old systemd unit's migration, an outdated entry counting as an update,
# and disable. Runs in a throwaway HOME: nothing of the VM's own setup is touched.
T="$(mktemp -d)"; export HOME="$T/home" XDG_CONFIG_HOME="$T/home/.config" STATE_DIR="$T/home/.local/state/steamify"
mkdir -p "$HOME"
for lib in common state desktop steam-desktop menu; do . "$SCRIPT_DIR/lib/$lib.sh" 2>/dev/null; done
STEAM_AUTOSTART="$XDG_CONFIG_HOME/autostart/steam.desktop"
user_systemctl() { :; }
exec_line() { grep '^Exec=' "$STEAM_AUTOSTART"; }
want='Exec=/usr/bin/steam -steamdeck -silent %U'

# 1. from the system steam.desktop (the package's entry, with its other keys kept)
STEAM_SYSTEM_DESKTOP="$T/steam.desktop"
printf '%s\n' '[Desktop Entry]' 'Name=Steam' 'Comment=Application for managing and playing games on Steam' 'Exec=/usr/bin/steam %U' 'Icon=steam' 'Type=Application' > "$STEAM_SYSTEM_DESKTOP"
silent_enable >/dev/null 2>&1
[[ "$(exec_line)" == "$want" ]] && pass "silent on (system entry): $want" || fail "silent on (system entry): $(exec_line)"
grep -q '^Comment=Application for managing' "$STEAM_AUTOSTART" && pass "silent on: the package entry's other keys are kept" || fail "silent on: keys lost"
[[ "$(exec_line | grep -c .)" == 1 ]] && pass "silent on: one Exec line" || fail "silent on: $(exec_line | grep -c .) Exec lines"
silent_status && pass "silent_status: on" || fail "silent_status: off after enable"
grep -q -- '-gamepadui' "$STEAM_AUTOSTART" && fail "silent on: -gamepadui must not be there (desktop UI unchanged)" || pass "silent on: no -gamepadui"

# 2. re-applying changes nothing
before="$(md5sum < "$STEAM_AUTOSTART")"; silent_enable >/dev/null 2>&1
[[ "$(md5sum < "$STEAM_AUTOSTART")" == "$before" ]] && pass "silent re-applied: identical file" || fail "silent re-applied: file changed"

# 3. disable removes it
silent_disable >/dev/null 2>&1
[[ ! -e "$STEAM_AUTOSTART" ]] && ! silent_status && pass "silent off: entry gone, status off" || fail "silent off: still there"

# 4. no system steam.desktop: the built-in template
STEAM_SYSTEM_DESKTOP="$T/missing.desktop"
silent_enable >/dev/null 2>&1
[[ "$(exec_line)" == "$want" ]] && pass "silent on (template): $want" || fail "silent on (template): $(exec_line)"
silent_status && pass "silent_status (template): on" || fail "silent_status (template): off"
silent_disable >/dev/null 2>&1

# 5. an entry from before the fix (`-silent` only) counts as on, and a re-apply (the update) rewrites it
mkdir -p "$(dirname "$STEAM_AUTOSTART")"
printf '%s\n' '[Desktop Entry]' 'Name=Steam' 'Exec=/usr/bin/steam -silent %U' 'Type=Application' > "$STEAM_AUTOSTART"
silent_status && pass "old entry (-silent only): status on" || fail "old entry: status off"
STEAM_SYSTEM_DESKTOP="$T/steam.desktop"
silent_enable >/dev/null 2>&1
[[ "$(exec_line)" == "$want" ]] && pass "old entry re-applied: now $want" || fail "old entry re-applied: $(exec_line)"

# 6. the old systemd unit (before 2.11.0) is migrated away
mkdir -p "$HOME/.config/systemd/user"; touch "$HOME/.config/systemd/user/steam-desktop-autostart.service"
silent_enable >/dev/null 2>&1
[[ ! -e "$HOME/.config/systemd/user/steam-desktop-autostart.service" ]] && pass "old systemd unit removed" || fail "old systemd unit still there"
silent_disable >/dev/null 2>&1

# 7. an install recorded at the old feature version is offered as an update, one recorded now is not
[[ "$(printf '%s\n' 2.13.3 "${FEATURE_VERSION[silent]}" | sort -V | head -n 1)" == 2.13.3 ]] && pass "FEATURE_VERSION[silent] is 2.13.3 or newer (${FEATURE_VERSION[silent]})" || fail "FEATURE_VERSION[silent]=${FEATURE_VERSION[silent]} is older than the -steamdeck fix"
CURRENT[silent]=1
state_set features silent 2.11.0
feature_outdated silent && pass "silent recorded at 2.11.0: shown as an update" || fail "silent recorded at 2.11.0: no update offered"
state_set features silent "${FEATURE_VERSION[silent]}"
feature_outdated silent && fail "silent recorded at ${FEATURE_VERSION[silent]}: update offered again" || pass "silent up to date: no update"
rm -rf "$T"
