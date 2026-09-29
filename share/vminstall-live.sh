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

# No `systemctl is-system-running --wait`: this script is itself the running
# kernel-command-line.service job, so the boot never finishes while it waits.
# The live keyring must exist before pacman-key can sign (the install failed with
# "no secret key available to sign with" when this ran first).
for _ in $(seq 120); do systemctl is-active --quiet pacman-init.service && break; sleep 2; done
nm-online -t 180 >/dev/null || fail "no network"
# The live ISO's mirror list and keys can be old; the installer's pacstrap needs current ones.
pacman -Sy --noconfirm archlinux-keyring cachyos-keyring || echo "(keyring update failed, going on)"

# The host's package cache (VM_CACHE, 9p tag `cache`) as pacman's cache: the
# installer's pacstrap -c uses the live system's, so a second install downloads nothing.
CACHE=/var/cache/steamify-pkg
if mkdir -p $CACHE && mount -t 9p -o trans=virtio,version=9p2000.L cache $CACHE 2>/dev/null; then
    mkdir -p $CACHE/pkg && mount --bind $CACHE/pkg /var/cache/pacman/pkg &&
        echo "== package cache: $(ls $CACHE/pkg | wc -l) files from the host"
else
    CACHE=""; echo "== no package cache (VM_CACHE off)"
fi

echo "== cachyos-installer"
cachyos-installer --config /tmp/settings.json || fail "cachyos-installer exited with $?"

# The installer leaves the new system mounted on /mnt, or not: mount it.
if ! mountpoint -q /mnt; then
    mount -o subvol=@ "${DEVICE}2" /mnt || fail "can't mount the new system"
    mount -o subvol=@home "${DEVICE}2" /mnt/home 2>/dev/null
    mount "${DEVICE}1" /mnt/boot 2>/dev/null
fi
[[ -d "/mnt/home/$VM_USER" ]] || fail "the installer created no /home/$VM_USER"

# Steamify's packages (Steam, ...) install inside the new system: same cache.
if [[ -n "$CACHE" ]]; then
    mkdir -p /mnt/var/cache/pacman/pkg && mount --bind $CACHE/pkg /mnt/var/cache/pacman/pkg || echo "(no cache in the new system)"
    # Steamify's own downloads (the CEC driver: GitHub rate-limits it)
    mkdir -p $CACHE/steamify /mnt/var/cache/steamify && mount --bind $CACHE/steamify /mnt/var/cache/steamify || true
fi

# What Calamares does after its users step (shellprocess_steamify): Steamify's
# setup for the new user. The headless installer skips it, so a Steamify ISO
# would otherwise leave plain CachyOS. VM_STEAMIFY: the page's choice (ids,
# comma-separated; empty = its default, everything on; none = skip).
if [[ -x /usr/local/bin/steamify-install && "${VM_STEAMIFY:-}" != skip ]]; then
    echo "== steamify-install (${VM_STEAMIFY:-defaults})"
    /usr/local/bin/steamify-install /mnt "$VM_USER" "${VM_STEAMIFY:-}"
    cat "/mnt/var/log/steamify-install.log" 2>/dev/null
    grep -q '^exit: 0' /mnt/var/log/steamify-install.log 2>/dev/null || fail "steamify-install did not finish cleanly"
else
    echo "== no steamify-install on this ISO (or VM_STEAMIFY=skip): plain CachyOS"
fi

mountpoint -q /mnt/var/cache/pacman/pkg && umount /mnt/var/cache/pacman/pkg

echo "== test VM setup"
cp /tmp/vminstall-post.sh /tmp/vminstall.env /mnt/root/
arch-chroot /mnt bash /root/vminstall-post.sh || fail "test VM setup exited with $?"
rm -f /mnt/root/vminstall-post.sh /mnt/root/vminstall.env
cp "$LOG" /mnt/var/log/vminstall.log
sync
finish ok
sleep 2
systemctl poweroff
