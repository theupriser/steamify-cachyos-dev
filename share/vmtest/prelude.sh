# Sent to the guest in front of every block (scripts/vmsuite.sh): helpers and Steamify's libs.
# ssh has no Plasma session: the theme item (Vapor layout) needs one (vmrun.sh does the same).
export XDG_RUNTIME_DIR=/run/user/$(id -u) WAYLAND_DISPLAY=wayland-0 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id -u)/bus
info() { echo "INFO $*"; }
pass() { echo "PASS $*"; }; fail() { echo "FAIL $*"; }; skip() { echo "SKIP $*"; }
sudo mountpoint -q /mnt || sudo mount -t 9p -o trans=virtio,version=9p2000.L repo /mnt
cd /mnt || exit 1
for lib in common state packages login-manager single-user steam-desktop steam-machine fremont-poweroff vram-booster hdmi-refresh cec boot-session vapor-theme steamos-extras bios desktop-shortcut wizard-shortcut steam-game update-notifier; do
    # shellcheck source=/dev/null
    . "lib/$lib.sh" 2>/dev/null
done
sf() { bash /mnt/steamify.sh "$@" < /dev/null 2>&1 | sed 's/\x1b\[[0-9;]*m//g'; return "${PIPESTATUS[0]}"; }
# is <item>: Steamify's own status function (what the menu ticks); isnt <item>
is()   { "${1}_status" 2>/dev/null; }
expect_on()  { local i; for i in "$@"; do is "$i" && pass "$i is on" || fail "$i is off"; done; }
expect_off() { local i; for i in "$@"; do is "$i" && fail "$i is on" || pass "$i is off"; done; }
ticks() { local i; for i in gaming theme glyphs single launcher notify vram cec machine poweroff boot; do is "$i" && printf '%s ' "$i"; done; echo; }
