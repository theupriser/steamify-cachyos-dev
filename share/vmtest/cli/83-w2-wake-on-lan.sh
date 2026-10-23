# W2 (#108): "Wake-on-LAN" (`wol`) and "Wake-on-WLAN" (`wowlan`) are one NetworkManager drop-in each
# (ethernet.wake-on-lan=64, wifi.wake-on-wlan=8 in a connection-* section), re-applied to the active devices of the
# type, removed again on off. Wake-on-WLAN brings the SteamOS Wi-Fi firmware along in the menu. nmcli, systemctl and
# sudo are stubbed, the drop-ins go to a throwaway dir: nothing real is touched. The wake itself (suspend, magic
# packet) is tried by hand on the hardware.
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
WOL_CONF="$T/nm/90-steamify-wake-on-lan.conf"; WOWLAN_CONF="$T/nm/90-steamify-wake-on-wlan.conf"
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

# 2. wireless
: > "$CALLS"; wowlan_enable >/dev/null 2>&1
grep -qx 'wifi.wake-on-wlan=8' "$WOWLAN_CONF" && pass "wowlan on: wifi.wake-on-wlan=8 (magic packet)" || fail "wowlan on: $(cat "$WOWLAN_CONF" 2>&1)"
grep -q 'device reapply wlan0' "$CALLS" && ! grep -q 'reapply enp5s0' "$CALLS" && pass "wowlan on: re-applied on the Wi-Fi device only" || fail "wowlan on: calls $(tr '\n' ';' < "$CALLS")"
wowlan_status && pass "wowlan_status: on" || fail "wowlan_status: off"
BUILD=cachyos; out="$(wowlan_enable 2>&1)"
[[ "$out" == *"isn't SteamOS's"* ]] && pass "wowlan on with CachyOS's firmware: warns" || fail "wowlan on with CachyOS's firmware: no warning"
BUILD=valve
wowlan_disable >/dev/null 2>&1
[[ ! -e "$WOWLAN_CONF" ]] && ! wowlan_status && pass "wowlan off: file gone, status off" || fail "wowlan off: still there"

# 3. no NetworkManager: error, nothing written
NM=down
wol_enable >/dev/null 2>&1 && fail "wol without NetworkManager: succeeded" || pass "wol without NetworkManager: fails"
wowlan_enable >/dev/null 2>&1 && fail "wowlan without NetworkManager: succeeded" || pass "wowlan without NetworkManager: fails"
[[ ! -e "$WOL_CONF" && ! -e "$WOWLAN_CONF" ]] && pass "without NetworkManager: nothing written" || fail "without NetworkManager: a file was written"
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
