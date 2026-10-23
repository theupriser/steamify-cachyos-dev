# S2 (#109): "Add as non-Steam game" restarts Steam after editing shortcuts.vdf. With the SteamOS conversion on it must
# start `steam -steamdeck -silent` (gaming mode's flag: without it the client branch, and the Steam Beta choice, flip);
# without the conversion plain `steam -silent`. Steam, pgrep and systemd-run are stubbed: nothing real is started.
T="$(mktemp -d)"; export HOME="$T/home" XDG_CONFIG_HOME="$T/home/.config" STATE_DIR="$T/home/.local/state/steamify"
mkdir -p "$HOME"
for lib in common state desktop login-manager steam-game; do . "$SCRIPT_DIR/lib/$lib.sh" 2>/dev/null; done
unset SteamGameId
n=0
pgrep() { n=$((n + 1)); [[ $n -le 2 ]] && return 0; return 1; }   # Steam running when asked, gone after the shutdown request
steam() { :; }
steamgame_steam_busy() { return 1; }
systemd-run() { echo "$*" > "$T/run.txt"; }
edit_noop() { return 0; }
restart_args() { n=0; : > "$T/run.txt"; steamgame_edit edit_noop >/dev/null 2>&1; sed 's/.* steam //' "$T/run.txt"; }

gaming_status() { return 0; }
[[ "$(restart_args)" == "-steamdeck -silent" ]] && pass "restart with the conversion: steam -steamdeck -silent" || fail "restart with the conversion: '$(restart_args)'"
gaming_status() { return 1; }
[[ "$(restart_args)" == "-silent" ]] && pass "restart without the conversion: steam -silent (no -steamdeck)" || fail "restart without the conversion: '$(restart_args)'"
rm -rf "$T"
