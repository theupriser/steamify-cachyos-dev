#!/bin/bash
# Guest side: Steamify's boot-loader-specific code, hdmi_remove_boot_param
# (older versions put drm.edid_firmware= on the kernel command line): seed
# the parameter where this loader keeps it, run the removal, and check that
# it's gone and the boot entries are rebuilt.
pass() { echo "PASS $*"; }; fail() { echo "FAIL $*"; }
sudo mountpoint -q /mnt || sudo mount -t 9p -o trans=virtio,version=9p2000.L repo /mnt
cd /mnt || exit 1
. lib/common.sh; . lib/state.sh; . lib/hdmi-refresh.sh
f="$(hdmi_boot_file)"
echo "boot file: ${f:-none}"
[[ -n "$f" ]] && pass "hdmi_boot_file finds the loader's file" || { fail "hdmi_boot_file finds nothing"; exit 0; }
p='drm.edid_firmware=DP-1:edid/steamify-test.bin'
case "$f" in
  /etc/default/grub) sudo sed -i -E "s|^(GRUB_CMDLINE_LINUX_DEFAULT=\")|\1$p |" "$f" ;;
  /etc/sdboot-manage.conf) if grep -q '^LINUX_OPTIONS=' "$f"; then sudo sed -i -E "s|^(LINUX_OPTIONS=\")|\1$p |" "$f"; else echo "LINUX_OPTIONS=\"$p\"" | sudo tee -a "$f" >/dev/null; fi ;;
  /etc/default/limine) if grep -q '^KERNEL_CMDLINE\[default\]' "$f"; then sudo sed -i -E "s|^(KERNEL_CMDLINE\[default\]\+?=\")|\1$p |" "$f"; else echo "KERNEL_CMDLINE[default]+=\"$p\"" | sudo tee -a "$f" >/dev/null; fi ;;
esac
[[ -n "$(hdmi_cmdline_param)" ]] && pass "the seeded parameter is detected" || fail "seeded parameter not detected in $f"
hdmi_remove_boot_param > /tmp/legacy-param.log 2>&1; rc=$?
tail -3 /tmp/legacy-param.log | sed 's/\x1b\[[0-9;]*m//g' | cut -c1-120
[[ $rc -eq 0 ]] && pass "hdmi_remove_boot_param exit 0" || fail "hdmi_remove_boot_param exit $rc"
[[ -z "$(hdmi_cmdline_param)" ]] && pass "parameter removed from $f" || fail "parameter still in $f"
case "$f" in
  /etc/default/grub) sudo grep -q edid /boot/grub/grub.cfg && fail "edid still in grub.cfg" || pass "no edid in grub.cfg"; [[ $(sudo grep -c '^\s*linux\s' /boot/grub/grub.cfg) -ge 1 ]] && pass "grub.cfg has linux entries" || fail "grub.cfg has no linux entries" ;;
  /etc/sdboot-manage.conf) sudo sh -c 'grep -l edid /boot/loader/entries/* 2>/dev/null' | grep -q . && fail "edid still in the entries" || pass "no edid in the entries"; [[ $(sudo ls /boot/loader/entries | wc -l) -ge 1 ]] && pass "boot entries exist" || fail "no boot entries" ;;
  /etc/default/limine) sudo grep -q edid /boot/limine.conf && fail "edid still in limine.conf" || pass "no edid in limine.conf"; sudo grep -q 'linux-cachyos' /boot/limine.conf && pass "limine.conf lists the kernels" || fail "limine.conf lists no kernel" ;;
esac
