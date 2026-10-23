# Sent to the guest in front of every block (scripts/vmsuite.sh): helpers and Steamify's libs.
# ssh has no Plasma session: the theme item (Vapor layout) needs one (vmrun.sh does the same).
export XDG_RUNTIME_DIR=/run/user/$(id -u) DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id -u)/bus
# Plasma's Wayland socket: wayland-0, or wayland-1 when the login had to be restarted (a restarted plasmalogin gets the next one)
WAYLAND_DISPLAY="$(cd "$XDG_RUNTIME_DIR" 2>/dev/null && ls -d wayland-[0-9]* 2>/dev/null | grep -v lock | head -n 1)"; export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-0}"
info() { echo "INFO $*"; }
pass() { echo "PASS $*"; }; fail() { echo "FAIL $*"; }; skip() { echo "SKIP $*"; }
sudo mountpoint -q /mnt || sudo mount -t 9p -o trans=virtio,version=9p2000.L repo /mnt
cd /mnt || exit 1
export SCRIPT_DIR=/mnt   # steamify.sh sets it; the libs alone read patches/ and services/ from it
# ssh has no desktop session variables: Steamify's desktop detection (lib/desktop.sh) reads the running one.
if [[ -z "${XDG_CURRENT_DESKTOP:-}" ]]; then
    if pgrep -u "$USER" -x gnome-shell >/dev/null; then export XDG_CURRENT_DESKTOP=GNOME; elif pgrep -u "$USER" -x plasmashell >/dev/null; then export XDG_CURRENT_DESKTOP=KDE; fi
fi
for lib in common state desktop packages login-manager single-user steam-desktop steam-machine fremont-poweroff vram-booster hdmi-refresh nvidia gamescope-nvidia controllers cec boot-session vapor-theme gnome-theme steamos-extras bios desktop-shortcut wizard-shortcut steam-game update-notifier; do
    # shellcheck source=/dev/null
    . "lib/$lib.sh" 2>/dev/null
done
sf() { bash /mnt/steamify.sh "$@" < /dev/null 2>&1 | sed 's/\x1b\[[0-9;]*m//g'; return "${PIPESTATUS[0]}"; }
# is <item>: Steamify's own status function (what the menu ticks); isnt <item>
is()   { "${1}_status" 2>/dev/null; }
expect_on()  { local i; for i in "$@"; do is "$i" && pass "$i is on" || fail "$i is off"; done; }
expect_off() { local i; for i in "$@"; do is "$i" && fail "$i is on" || pass "$i is off"; done; }
ticks() { local i; for i in gaming nvidia bigpicture theme gnometheme glyphs single launcher notify vram cec machine poweroff boot; do is "$i" && printf '%s ' "$i"; done; echo; }
# fake_nvidia: an NVIDIA PC for the nvidia suite. A fake RTX 5080 in a fake DRM tree (NVIDIA_DRM_DIR is Steamify's test hook, exported
# here: call it in every guest command that runs the wizard) and fake NVIDIA modules for every installed kernel (renamed copies of a
# tiny module, then depmod), so `modinfo nvidia_drm` finds one and the initramfs build has modules to put in.
fake_nvidia() {
    local d=/var/tmp/fake-drm k kd src ext m
    mkdir -p "$d/card1/device"
    echo 0x10de > "$d/card1/device/vendor"; echo 0x030000 > "$d/card1/device/class"; echo 0x2c02 > "$d/card1/device/device"
    for kd in /usr/lib/modules/*/; do
        k="$(basename "$kd")"
        [[ -d "$kd/kernel" ]] || continue
        src="$(find "$kd/kernel" -name 'dummy.ko*' | head -n 1)"
        [[ -n "$src" ]] || { echo "no dummy module for $k"; continue; }
        ext="${src##*dummy.ko}"
        for m in nvidia nvidia-modeset nvidia-uvm nvidia-drm; do
            [[ -e "$kd/kernel/drivers/video/$m.ko$ext" ]] || sudo install -Dm644 "$src" "$kd/kernel/drivers/video/$m.ko$ext"
        done
        sudo depmod -a "$k"
    done
    export NVIDIA_DRM_DIR="$d"
}
