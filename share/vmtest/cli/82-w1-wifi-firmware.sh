# W1 (#108): "Wi-Fi firmware from SteamOS" (`wifi`) puts Valve's amss.bin for the Steam Machine's QCA2066 adapter in
# /usr/lib/firmware/updates (nothing of linux-firmware is touched) and takes it out again. Valve's package is built here
# (fetch_holo_pkg stubbed, sudo passes through, the destination is a throwaway dir): covers install, a bad package,
# re-apply, status, disable, the menu registration (opt-in, child of machine) and the feature version.
T="$(mktemp -d)"; export HOME="$T/home" XDG_CONFIG_HOME="$T/home/.config" STATE_DIR="$T/home/.local/state/steamify"
mkdir -p "$HOME"
for lib in common state cec fremont-wifi menu; do . "$SCRIPT_DIR/lib/$lib.sh" 2>/dev/null; done
sudo() { "$@"; }
WIFI_FW_DEST="$T/root/$WIFI_FW_FILE"
mkdir -p "$T/pkgsrc/$(dirname "$WIFI_FW_FILE")"
printf 'firmware-from-valve' | zstd -q -o "$T/pkgsrc/$WIFI_FW_FILE"
tar -cf "$T/good.tar" -C "$T/pkgsrc" usr
mkdir -p "$T/emptysrc/usr/share"; tar -cf "$T/bad.tar" -C "$T/emptysrc" usr
fetch_holo_pkg() { echo "$T/$PKG.tar"; }   # args: <dir> <package> <repo>
PKG=good

# 1. install: the file lands in updates, readable as zstd, from the right package and repository
fetch_holo_pkg() { echo "$2 $3" > "$T/args"; echo "$T/$PKG.tar"; }   # runs in a subshell: the arguments go to a file
wifi_enable >/dev/null 2>&1
WIFI_ARGS="$(cat "$T/args" 2>/dev/null)"
[[ -f "$WIFI_FW_DEST" ]] && pass "wifi on: amss.bin.zst installed in updates" || fail "wifi on: no file"
[[ "$(zstd -dc "$WIFI_FW_DEST" 2>/dev/null)" == firmware-from-valve ]] && pass "wifi on: the file is the package's" || fail "wifi on: wrong content"
[[ "$WIFI_ARGS" == "linux-firmware-holo holo-main" ]] && pass "wifi on: linux-firmware-holo from holo-main" || fail "wifi on: fetched '$WIFI_ARGS'"
[[ "$WIFI_FW_DEST" == */usr/lib/firmware/updates/ath11k/QCA2066/hw2.1/amss.bin.zst ]] && pass "wifi on: path is updates/ath11k/QCA2066/hw2.1" || fail "wifi on: path $WIFI_FW_DEST"
wifi_status && pass "wifi_status: on" || fail "wifi_status: off after enable"

# 2. re-apply changes nothing
before="$(md5sum < "$WIFI_FW_DEST")"; wifi_enable >/dev/null 2>&1
[[ "$(md5sum < "$WIFI_FW_DEST")" == "$before" ]] && pass "wifi re-applied: identical file" || fail "wifi re-applied: file changed"

# 3. disable removes the file and the directories it made, never the root
wifi_disable >/dev/null 2>&1
[[ ! -e "$WIFI_FW_DEST" ]] && ! wifi_status && pass "wifi off: file gone, status off" || fail "wifi off: still there"
[[ ! -d "$T/root/usr/lib/firmware/updates" ]] && pass "wifi off: empty updates directories removed" || fail "wifi off: directories left"
wifi_disable >/dev/null 2>&1 && pass "wifi off twice: fine" || fail "wifi off twice: error"

# 4. a package without the file, or a failed download: nothing installed, error returned
PKG=bad; wifi_enable >/dev/null 2>&1 && fail "bad package: enable succeeded" || pass "bad package: enable fails"
[[ ! -e "$WIFI_FW_DEST" ]] && pass "bad package: nothing installed" || fail "bad package: file installed"
fetch_holo_pkg() { return 1; }
wifi_enable >/dev/null 2>&1 && fail "download failed: enable succeeded" || pass "download failed: enable fails"

# 5. menu: opt-in child of machine, offered only where wifi_available, versioned
[[ " ${COMPONENTS[*]} " == *" wifi "* && "${PARENT[wifi]}" == machine ]] && pass "menu: wifi is a sub-option of machine" || fail "menu: wifi not registered under machine"
[[ " ${NO_PRESELECT[*]} " == *" wifi "* ]] && pass "menu: wifi is never preselected" || fail "menu: wifi would be preselected"
[[ -n "${LABEL[wifi]:-}" ]] && pass "menu: wifi has a label" || fail "menu: no label"
[[ "$(printf '%s\n' 2.13.3 "${FEATURE_VERSION[wifi]:-0}" | sort -V | head -n 1)" == 2.13.3 ]] && pass "FEATURE_VERSION[wifi] is set (${FEATURE_VERSION[wifi]})" || fail "FEATURE_VERSION[wifi] missing"
detect_valve_fremont() { return 1; }
wifi_available && fail "not a Steam Machine: wifi offered" || pass "not a Steam Machine: wifi not offered"
rm -rf "$T"
