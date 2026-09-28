#!/bin/bash
# Runs inside the freshly installed system (arch-chroot, from
# vminstall-live.sh): what guest-ssh-setup.sh and the old manual steps did,
# so the VM is ssh-ready without touching it: sshd with the host's key,
# passwordless sudo, the test autologin into Plasma, tmux and shellcheck.
set -euo pipefail
# shellcheck disable=SC1091
. /root/vminstall.env

echo "$VM_HOSTNAME" > /etc/hostname
pacman -S --needed --noconfirm openssh tmux shellcheck
systemctl enable sshd

home="/home/$VM_USER"
install -d -m 700 -o "$VM_USER" -g "$VM_USER" "$home/.ssh"
printf '%s\n' "$VM_PUBKEY" > "$home/.ssh/authorized_keys"
chown "$VM_USER:$VM_USER" "$home/.ssh/authorized_keys"
chmod 600 "$home/.ssh/authorized_keys"

# Test VM only: the host drives it without a password.
echo "$VM_USER ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/99-test-vm
chmod 440 /etc/sudoers.d/99-test-vm

# Log straight into Plasma (gamescope doesn't render in the VM). The
# scripts expect plasma-login-manager, like a CachyOS install from Calamares.
pacman -Q plasma-login-manager >/dev/null 2>&1 || pacman -S --needed --noconfirm plasma-login-manager
systemctl disable sddm.service 2>/dev/null || true
systemctl enable plasmalogin.service
mkdir -p /etc/plasmalogin.conf.d
printf '[Autologin]\nUser=%s\nSession=plasma.desktop\n' "$VM_USER" > /etc/plasmalogin.conf.d/00-test-autologin.conf

# cachyos-installer's limine.conf has no default_entry: entry 1 is the
# "CachyOS" folder, so the first boot waits in the menu. 2 is its first
# kernel (linux-cachyos); limine-update keeps the line.
if [[ -f /boot/limine.conf ]] && ! grep -q '^default_entry:' /boot/limine.conf; then
    sed -i 's/^timeout: .*/&\ndefault_entry: 2/' /boot/limine.conf
fi

# English everywhere, whatever the live ISO picked.
echo 'LANG=en_US.UTF-8' > /etc/locale.conf

# mirror5.krfoss.org served broken signatures; skip it (vmreset.sh does too).
for f in /etc/pacman.d/*mirrorlist*; do sed -i '/krfoss/s/^Server/#Server/' "$f"; done
echo "Test VM setup done: $VM_USER@$VM_HOSTNAME"
