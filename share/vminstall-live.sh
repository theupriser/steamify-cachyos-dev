#!/bin/bash
# Runs in the live ISO as root (started by the systemd.run= boot parameter
# that scripts/vminstall.sh passes): installs CachyOS unattended with its
# headless installer (settings.json from the host), then makes the new
# system a test VM (SSH key, passwordless sudo, test autologin), and powers
# off. Everything it needs comes from the host's vminstall-server.py; the log
# and the result go back there (PUT log / status).
set -uo pipefail
H="http://@HOST_IP@:@PORT@"
LOG=/tmp/vminstall.log
exec > >(tee -a "$LOG") 2>&1
up() { curl -fsS -T "$LOG" "$H/install.log" >/dev/null 2>&1; }
finish() { echo "== $1"; up; curl -fsS -X PUT --data "$1" "$H/status" >/dev/null 2>&1; }
fail() { finish "failed: $*"; exit 1; }

echo "== Steamify test VM: unattended install ($(date))"
curl -fsS "$H/vminstall.env" -o /tmp/vminstall.env || fail "no vminstall.env from the host"
# shellcheck disable=SC1091
. /tmp/vminstall.env
curl -fsS "$H/settings.json" -o /tmp/settings.json || fail "no settings.json from the host"
curl -fsS "$H/vminstall-post.sh" -o /tmp/vminstall-post.sh || fail "no vminstall-post.sh from the host"

# Let whoever watches the VM's window follow along: a Konsole on the live
# desktop that shows this log.
(
    for _ in $(seq 100); do pgrep -u liveuser -x plasmashell >/dev/null && break; sleep 3; done
    sleep 5
    runuser -u liveuser -- env XDG_RUNTIME_DIR=/run/user/1000 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus \
        systemd-run --user -q konsole --hold -e tail -n +1 -f "$LOG"
) &
while sleep 20; do up; done &

systemctl is-system-running --wait >/dev/null 2>&1
nm-online -t 180 >/dev/null || fail "no network"
# The live ISO's mirror list and keys can be old; the installer's pacstrap needs current ones.
pacman -Sy --noconfirm archlinux-keyring cachyos-keyring || echo "(keyring update failed, going on)"

echo "== cachyos-installer"
cachyos-installer --config /tmp/settings.json || fail "cachyos-installer exited with $?"

# The installer leaves the new system mounted on /mnt, or not: mount it.
if ! mountpoint -q /mnt; then
    mount -o subvol=@ "${DEVICE}2" /mnt || fail "can't mount the new system"
    mount -o subvol=@home "${DEVICE}2" /mnt/home 2>/dev/null
    mount "${DEVICE}1" /mnt/boot 2>/dev/null
fi
[[ -d "/mnt/home/$VM_USER" ]] || fail "the installer created no /home/$VM_USER"

echo "== test VM setup"
cp /tmp/vminstall-post.sh /tmp/vminstall.env /mnt/root/
arch-chroot /mnt bash /root/vminstall-post.sh || fail "test VM setup exited with $?"
rm -f /mnt/root/vminstall-post.sh /mnt/root/vminstall.env
cp "$LOG" /mnt/var/log/vminstall.log
sync
finish ok
sleep 2
systemctl poweroff
