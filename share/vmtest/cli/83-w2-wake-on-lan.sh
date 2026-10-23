# W2 (#108): "Wake-on-LAN" (`wol`) is a NetworkManager drop-in (ethernet.wake-on-lan=64 in a connection-* section),
# re-applied to the wired devices, removed again on off. "Wake-on-WLAN" (`wowlan`) is a systemd sleep hook that runs
# `iw phy ... wowlan enable magic-packet` before every suspend (NetworkManager ignores the setting with the iwd backend);
# it brings the SteamOS Wi-Fi firmware along in the menu. nmcli, systemctl, iw and sudo are stubbed, the files go to a
# throwaway dir: nothing real is touched. The wakes themselves (suspend, magic packet) are tried by hand on the hardware.
T="$(mktemp -d)"; export HOME="$T/home" XDG_CONFIG_HOME="$T/home/.config" STATE_DIR="$T/home/.local/state/steamify"
mkdir -p "$HOME"
for lib in common state cec fremont-wifi wake-on-lan menu; do . "$SCRIPT_DIR/lib/$lib.sh" 2>/dev/null; done
sudo() { "$@"; }
NM=up; CALLS="$T/calls"; : > "$CALLS"
systemctl() { [[ "$NM" == up ]]; }
nmcli() {
    echo "$*" >> "$CALLS"
    [[ "$1" == -t ]] && printf '%s\n' enp5s0:ethernet wlan0:wifi lo:loopback
    return 0
}
iw() { echo "iw $*" >> "$CALLS"; }
WOL_CONF="$T/nm/90-steamify-wake-on-lan.conf"; WOWLAN_OLD_CONF="$T/nm/90-steamify-wake-on-wlan.conf"
WOWLAN_HOOK="$T/sleep/steamify-wowlan"; WOWLAN_OLD_HOOK="$T/etcsleep/steamify-wowlan"
wifi_build() { echo "${BUILD:-valve}"; }

# 1. wired
wol_enable >/dev/null 2>&1
grep -qx 'ethernet.wake-on-lan=64' "$WOL_CONF" && pass "wol on: ethernet.wake-on-lan=64 (magic packet)" || fail "wol on: $(cat "$WOL_CONF" 2>&1)"
grep -q '^\[connection' "$WOL_CONF" && pass "wol on: in a connection-* section" || fail "wol on: no connection section"
grep -q 'general reload conf' "$CALLS" && grep -q 'device reapply enp5s0' "$CALLS" && ! grep -q 'reapply wlan0' "$CALLS" && pass "wol on: reload, re-apply of the wired device only" || fail "wol on: calls $(tr '\n' ';' < "$CALLS")"
wol_status && pass "wol_status: on" || fail "wol_status: off"
before="$(md5sum < "$WOL_CONF")"; wol_enable >/dev/null 2>&1
[[ "$(md5sum < "$WOL_CONF")" == "$before" ]] && pass "wol re-applied: identical file" || fail "wol re-applied: changed"
wol_disable >/dev/null 2>&1
[[ ! -e "$WOL_CONF" ]] && ! wol_status && pass "wol off: file gone, status off" || fail "wol off: still there"
wol_disable >/dev/null 2>&1 && pass "wol off twice: fine" || fail "wol off twice: error"

# 2. wireless: the sleep hook
mkdir -p "$(dirname "$WOWLAN_OLD_CONF")" "$(dirname "$WOWLAN_OLD_HOOK")"; echo old > "$WOWLAN_OLD_CONF"; echo old > "$WOWLAN_OLD_HOOK"
: > "$CALLS"; wowlan_enable >/dev/null 2>&1
[[ -x "$WOWLAN_HOOK" ]] && pass "wowlan on: the sleep hook is installed and executable" || fail "wowlan on: no hook"
grep -q 'wowlan enable magic-packet' "$WOWLAN_HOOK" && grep -q '"pre"\|== pre' "$WOWLAN_HOOK" && pass "wowlan on: the hook enables magic-packet wake, on pre only" || fail "wowlan on: hook content"
[[ "$WOWLAN_HOOK" == /usr/lib/systemd/system-sleep/* || "$WOWLAN_HOOK" == "$T"/* ]] && pass "wowlan on: the hook path is one systemd reads" || fail "wowlan on: path"
grep -q '^WOWLAN_HOOK=/usr/lib/systemd/system-sleep/' "$SCRIPT_DIR/lib/wake-on-lan.sh" && pass "wowlan: the real hook path is /usr/lib/systemd/system-sleep (systemd 262 reads nothing from /etc)" || fail "wowlan: real hook path is not /usr/lib/systemd/system-sleep"
[[ ! -e "$WOWLAN_OLD_CONF" && ! -e "$WOWLAN_OLD_HOOK" ]] && pass "wowlan on: the development builds' NetworkManager file and /etc hook are removed" || fail "wowlan on: old files left"
wowlan_status && pass "wowlan_status: on" || fail "wowlan_status: off"
! grep -q 'reapply wlan0' "$CALLS" && pass "wowlan on: NetworkManager is not asked to change the Wi-Fi device" || fail "wowlan on: nmcli used for Wi-Fi"
# The hook, run as systemd does: "pre suspend" sets it for every Wi-Fi phy there is, "post suspend" does nothing.
: > "$CALLS"; PATH="$T/bin:$PATH"; mkdir -p "$T/bin"; printf '#!/bin/bash\necho "iw $*" >> "%s"\n' "$CALLS" > "$T/bin/iw"; chmod +x "$T/bin/iw"
unset -f iw
"$WOWLAN_HOOK" pre suspend; pre_rc=$?
"$WOWLAN_HOOK" post suspend; post_rc=$?
phys="$(ls /sys/class/ieee80211 2>/dev/null | wc -l)"
[[ "$pre_rc" == 0 && "$post_rc" == 0 ]] && pass "hook: pre and post both exit 0 (never blocks a suspend)" || fail "hook: exit codes $pre_rc $post_rc"
[[ "$(grep -c 'wowlan enable magic-packet' "$CALLS")" == "$phys" ]] && pass "hook: enables magic-packet on each of the $phys Wi-Fi phys on pre, nothing on post" || fail "hook: $(grep -c 'wowlan enable' "$CALLS") calls for $phys phys"
iw() { echo "iw $*" >> "$CALLS"; }
BUILD=cachyos; out="$(wowlan_enable 2>&1)"
[[ "$out" == *"isn't SteamOS's"* ]] && pass "wowlan on with CachyOS's firmware: warns" || fail "wowlan on with CachyOS's firmware: no warning"
BUILD=valve
before="$(md5sum < "$WOWLAN_HOOK")"; wowlan_enable >/dev/null 2>&1
[[ "$(md5sum < "$WOWLAN_HOOK")" == "$before" ]] && pass "wowlan re-applied: identical hook" || fail "wowlan re-applied: changed"
wowlan_disable >/dev/null 2>&1
[[ ! -e "$WOWLAN_HOOK" ]] && ! wowlan_status && pass "wowlan off: hook gone, status off" || fail "wowlan off: still there"
wowlan_disable >/dev/null 2>&1 && pass "wowlan off twice: fine" || fail "wowlan off twice: error"

# 3. no NetworkManager: wired fails and writes nothing; wireless doesn't need it
NM=down
wol_enable >/dev/null 2>&1 && fail "wol without NetworkManager: succeeded" || pass "wol without NetworkManager: fails"
[[ ! -e "$WOL_CONF" ]] && pass "wol without NetworkManager: nothing written" || fail "wol without NetworkManager: a file was written"
wowlan_enable >/dev/null 2>&1 && pass "wowlan without NetworkManager: works (a sleep hook)" || fail "wowlan without NetworkManager: fails"
wowlan_disable >/dev/null 2>&1
NM=up

# 4. menu: opt-in children of machine, versioned; wowlan brings the firmware, machine off clears all
for c in wol wowlan; do
    [[ " ${COMPONENTS[*]} " == *" $c "* && "${PARENT[$c]}" == machine && " ${NO_PRESELECT[*]} " == *" $c "* && -n "${LABEL[$c]:-}" ]] &&
        pass "menu: $c is an opt-in sub-option of machine, with a label" || fail "menu: $c not registered right"
    [[ "$(printf '%s\n' 2.13.3 "${FEATURE_VERSION[$c]:-0}" | sort -V | head -n 1)" == 2.13.3 ]] && pass "FEATURE_VERSION[$c] set (${FEATURE_VERSION[$c]})" || fail "FEATURE_VERSION[$c] missing"
done
declare -A WANTED=([machine]=0 [wifi]=0 [wol]=0 [wowlan]=0 [kpin]=0 [bios]=0 [poweroff]=0)
toggle_component wowlan
[[ "${WANTED[wowlan]}" == 1 && "${WANTED[wifi]}" == 1 && "${WANTED[machine]}" == 1 ]] && pass "menu: ticking wowlan ticks the Wi-Fi firmware and Steam Machine support" || fail "menu: wowlan -> wifi=${WANTED[wifi]} machine=${WANTED[machine]}"
toggle_component wifi
[[ "${WANTED[wifi]}" == 0 && "${WANTED[wowlan]}" == 0 ]] && pass "menu: unticking the firmware unticks wowlan" || fail "menu: wifi off, wowlan=${WANTED[wowlan]}"
toggle_component wol
[[ "${WANTED[wol]}" == 1 && "${WANTED[machine]}" == 1 ]] && pass "menu: ticking wol ticks Steam Machine support" || fail "menu: wol -> machine=${WANTED[machine]}"
toggle_component wowlan; toggle_component machine
[[ "${WANTED[machine]}" == 0 && "${WANTED[wol]}" == 0 && "${WANTED[wowlan]}" == 0 && "${WANTED[wifi]}" == 0 ]] && pass "menu: Steam Machine support off clears wol, wowlan and wifi" || fail "menu: machine off left wol=${WANTED[wol]} wowlan=${WANTED[wowlan]} wifi=${WANTED[wifi]}"
rm -rf "$T"
