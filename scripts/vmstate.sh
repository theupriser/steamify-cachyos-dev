#!/bin/bash
# Print the state of every wizard component in the guest.
# Env: VM_USER (theupriser), VM_PORT (2222), VM_HOST (localhost).
set -euo pipefail
. "$(dirname "$0")/common.sh"
vm_ssh bash -s << 'REMOTE' 2>&1
yn() { [ -e "$1" ] && echo y || echo n; }
echo "DM=$(systemctl show -p Id --value display-manager) sddm-autologin=$(yn /etc/sddm.conf.d/10-gamescope-autologin.conf) sync=$(yn /etc/systemd/system/sync-steamos-session.path) sudoers=$(sudo test -f /etc/sudoers.d/gamescope-session-switch && echo y || echo n)"
echo "plasmalogin [Autologin]: $(sed -n '/^\[Autologin\]/,/^\[/p' /etc/plasmalogin.conf | grep -v '^\[' | tr '\n' ' ')"
echo "shortcut=$(grep -h Exec= ~/Desktop/*Gaming*.desktop 2>/dev/null || echo none)"
echo "steam-unit=$([ -f ~/.config/systemd/user/steam-desktop-autostart.service ] && systemctl --user is-enabled steam-desktop-autostart.service || echo none) glyphs=$(yn ~/.config/environment.d/99-gamescope-steam-glyphs.conf)"
echo "lnf=$(kreadconfig6 --file kdeglobals --group KDE --key LookAndFeelPackage) dark-lnf=$(kreadconfig6 --file kdeglobals --group KDE --key DefaultDarkLookAndFeel) scheme=$(kreadconfig6 --file kdeglobals --group General --key ColorScheme) cursor=$(kreadconfig6 --file kcminputrc --group Mouse --key cursorTheme) vapor-pkg=$(pacman -Q cachyos-vapor 2>/dev/null || echo none) layout-backup=$(yn ~/.local/state/cachyos-gamescope-boot/theme-layout)"
echo "wallpaper: $(grep -h '^Image=' ~/.config/plasma-org.kde.plasma.desktop-appletsrc | sort -u | tr '\n' ' ')"
echo "lock_screen=$(kreadconfig6 --file kdeglobals --group 'KDE Action Restrictions' --key action/lock_screen) autolock=$(kreadconfig6 --file kscreenlockerrc --group Daemon --key Autolock) metaL=$(kreadconfig6 --file kglobalshortcutsrc --group ksmserver --key 'Lock Session' | cut -c1-12)"
echo "panel: $(grep -A1 '^\[PlasmaViews\]\[Panel [0-9]*\]$' ~/.config/plasmashellrc | grep floating | tr '\n' ' ') $(grep -h 'thickness' ~/.config/plasmashellrc | tr '\n' ' ')"
echo "kickoff: $(grep -E '^(primaryActions|systemFavorites|icon)=' ~/.config/plasma-org.kde.plasma.desktop-appletsrc | tr '\n' ' ')"
echo "leds-pkg=$(pacman -Q leds-valve-dkms-git 2>/dev/null || echo none) steamos-manager=$(pacman -Q steamos-manager 2>/dev/null || echo none)/$(systemctl is-active steamos-manager 2>/dev/null) udev=$(yn /etc/udev/rules.d/70-valve-leds-user.rules) module=$(lsmod | grep -c leds_valve) leds=$(ls /sys/class/leds | grep -c valve)"
echo "dkms: $(dkms status leds-valve-dkms 2>/dev/null | cut -d, -f2- | sed 's/, x86_64//' | tr '\n' ';') kernels: $(ls /usr/lib/modules | tr '\n' ' ')"
echo "dkms-override=$(yn /etc/dkms/leds-valve-dkms.conf) headers-check=$(systemctl is-enabled ensure-kernel-headers.service 2>/dev/null || echo none)"
echo "leds-owner=$(stat -c %U /sys/class/leds/valve-leds*/brightness 2>/dev/null | sort -u | tr '\n' ' ')"
j=~/.local/state/cachyos-gamescope-boot
echo "journals: $(ls "$j" 2>/dev/null | tr '\n' ' ')"
for f in "$j"/*; do [ -f "$f" ] || continue; d=$(cut -f1-3 "$f" | sort | uniq -d); [ -n "$d" ] && echo "DUPLICATES in $(basename "$f"): $d"; done
true
REMOTE
