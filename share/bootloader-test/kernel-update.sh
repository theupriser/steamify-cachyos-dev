#!/bin/bash
# Guest side: reinstall both kernels + headers (what an update does: the
# DKMS hook rebuilds the modules, mkinitcpio and the boot loader's hook run).
pass() { echo "PASS $*"; }; fail() { echo "FAIL $*"; }
start=$(date +%s)
sudo pacman -S --noconfirm linux-cachyos linux-cachyos-lts linux-cachyos-headers linux-cachyos-lts-headers > /tmp/kernel-update.log 2>&1
rc=$?
sed 's/\x1b\[[0-9;]*m//g' /tmp/kernel-update.log | grep -E "^==> dkms|Building image|Generating grub|sdboot|limine|error" | cut -c1-140
[[ $rc -eq 0 ]] && pass "pacman kernel reinstall exit 0" || fail "pacman exit $rc"
for k in $(ls /usr/lib/modules); do
    for m in cros-ec-cec leds-valve steamify-fremont-poweroff; do
        compgen -G "/usr/lib/modules/$k/updates/dkms/$m.ko*" >/dev/null || fail "$m not rebuilt for $k"
    done
done
[[ $(dkms status | grep -c ': installed') -eq $((3 * $(ls /usr/lib/modules | wc -w))) ]] && pass "DKMS rebuilt 3 modules for each kernel" || fail "DKMS status after the update"
# The images: /boot/initramfs-*.img (GRUB, systemd-boot); Limine keeps them per kernel
# under /boot/<machine-id>/<kernel>/initramfs (limine-mkinitcpio) and rewrites limine.conf.
if [[ "$LOADER" == limine ]]; then
    # limine-entry-tool copies an image only when its content changed (same version = untouched):
    # the hook ran when both images were built and limine.conf was regenerated.
    n=$(sed 's/\x1b\[[0-9;]*m//g' /tmp/kernel-update.log | grep -c 'Creating zstd-compressed initcpio image')
    [[ $n -ge 2 ]] && pass "Limine's hook built the initramfs for both kernels" || fail "Limine's hook built $n initramfs image(s)"
    [[ $(sudo stat -c %Y /boot/limine.conf) -ge $start ]] && pass "limine.conf regenerated" || fail "limine.conf not regenerated"
else
    for img in /boot/initramfs-linux-cachyos.img /boot/initramfs-linux-cachyos-lts.img; do
        [[ $(sudo stat -c %Y "$img") -ge $start ]] && pass "$(basename "$img") rebuilt" || fail "$(basename "$img") not rebuilt"
    done
fi
