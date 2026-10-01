# N2-N5: Gaming on NVIDIA + Big Picture + Single user mode on a fake NVIDIA PC, for real: pacman installs Steam, the SDDM autologin,
# the boot loader files and the initramfs, then a reboot into Plasma, then everything off again and a second reboot.
# Covers TESTPLAN N2 (apply), N3 (after the reboot), N4 (turn off), N5 (after the second reboot).
unit='~/.config/systemd/user/steamify-steam-autostart.service'
g() { guest "$@"; }
yes_() { [[ "$(g "$1 && echo YES || echo NO" | tail -n 1)" == YES ]]; }   # a guest condition
info "N2 applying nvidia,bigpicture,single (Steam, SDDM, initramfs: several minutes)..."
rc="$(g 'fake_nvidia; sf --defaults --options nvidia,bigpicture,single > /tmp/n2.log; echo "rc=$?"' | tail -n 1)"
[[ "$rc" == rc=0 ]] && pass "N2 apply exit 0" || { fail "N2 apply: $rc: $(g 'tail -n 15 /tmp/n2.log')"; return 0 2>/dev/null || exit 0; }
yes_ 'pacman -Q steam >/dev/null 2>&1' && pass "N2 Steam is installed" || fail "N2 Steam missing"
yes_ "grep -qx 'ExecStart=/usr/bin/steam -gamepadui' $unit" && pass "N2 the autostart unit starts Steam with -gamepadui" || fail "N2 unit: $(g "cat $unit")"
yes_ 'systemctl --user is-enabled -q steamify-steam-autostart.service' && pass "N2 the unit is enabled" || fail "N2 unit not enabled"
[[ "$(g 'kreadconfig6 --file ksmserverrc --group General --key loginMode' | tail -n 1)" == emptySession ]] && pass "N2 Plasma starts with an empty session" || fail "N2 loginMode"
g 'is nvidia && is bigpicture && echo ON' | grep -qx ON && pass "N2 nvidia and bigpicture report on" || fail "N2 status functions"
yes_ "grep -q 'nvidia-drm.modeset=1 nvidia-drm.fbdev=1' /etc/default/limine" && pass "N2 the kernel parameters are in /etc/default/limine" || fail "N2 limine defaults"
yes_ "sudo grep -q 'nvidia-drm.fbdev=1' /boot/limine.conf" && pass "N2 and in the generated /boot/limine.conf" || fail "N2 limine.conf"
yes_ 'test -f /etc/mkinitcpio.conf.d/90-steamify-nvidia.conf && test -x /usr/local/libexec/steamify-nvidia-initramfs && test -f /etc/pacman.d/hooks/85-steamify-nvidia-initramfs.hook' && pass "N2 early-load file, hook and its script installed" || fail "N2 initramfs files"
yes_ 'sudo find /boot -name "initramfs*" -exec sh -c "lsinitcpio {} | grep -q nvidia" \; -print | grep -q .' && pass "N2 the NVIDIA modules are in the initramfs" || fail "N2 initramfs has no nvidia modules"
yes_ 'systemctl is-enabled -q sddm.service' && pass "N2 SDDM is the login manager" || fail "N2 sddm not enabled"
yes_ "grep -qx 'Session=plasma.desktop' /etc/sddm.conf.d/zzz-steamify-autologin.conf && grep -qx \"User=\$USER\" /etc/sddm.conf.d/zzz-steamify-autologin.conf" && pass "N2 SDDM autologin: the user into the Plasma session" || fail "N2 autologin file: $(g 'cat /etc/sddm.conf.d/zzz-steamify-autologin.conf')"
yes_ 'is single' && pass "N2 single user mode is on" || fail "N2 single not on"
g 'fake_nvidia; sf --defaults --options nvidia,bigpicture,single | tail -n 3' | grep -qiE 'nothing|already|exit: 0' && pass "N2 a second run is quiet" || info "N2 second run: $(g 'fake_nvidia; sf --defaults --options nvidia,bigpicture,single | tail -n 3')"

reboot_guest && pass "N3 the VM is back after the reboot" || { fail "N3 no ssh after the reboot"; return 0 2>/dev/null || exit 0; }
up=""; for _ in $(seq 40); do vm_ssh "pgrep -u $VM_USER -x plasmashell" >/dev/null 2>&1 && { up=1; break; }; sleep 3; done
[[ -n "$up" ]] && pass "N3 Plasma straight after the boot (SDDM autologin, no greeter)" || fail "N3 no plasmashell after the reboot"
yes_ '! pgrep -x sddm-greeter >/dev/null' && pass "N3 no greeter running" || fail "N3 sddm-greeter is running"
yes_ 'grep -q "nvidia-drm.modeset=1" /proc/cmdline && grep -q "nvidia-drm.fbdev=1" /proc/cmdline' && pass "N3 the kernel parameters are on the running command line" || fail "N3 cmdline: $(g 'cat /proc/cmdline')"
yes_ 'systemctl is-active -q sddm.service' && pass "N3 sddm is the running display manager" || fail "N3 sddm not active"
yes_ 'journalctl --user -b --no-pager -u steamify-steam-autostart.service | grep -qiE "Started|Starting"' && pass "N3 the Steam autostart unit was started at login" || fail "N3 unit never started: $(g 'systemctl --user status steamify-steam-autostart.service 2>&1 | head -n 8')"
[[ "$(g 'kreadconfig6 --file ksmserverrc --group General --key loginMode' | tail -n 1)" == emptySession ]] && pass "N3 the empty session setting survived" || fail "N3 loginMode after the reboot"

info "N4 turning everything off (only notify stays)..."
rc="$(g 'fake_nvidia; sf --defaults --options notify > /tmp/n4.log; echo "rc=$?"' | tail -n 1)"
[[ "$rc" == rc=0 ]] && pass "N4 turn-off exit 0" || { fail "N4 turn-off: $rc: $(g 'tail -n 15 /tmp/n4.log')"; return 0 2>/dev/null || exit 0; }
yes_ '! pacman -Q steam >/dev/null 2>&1' && pass "N4 Steam is removed again (Steamify installed it)" || fail "N4 Steam is still installed"
yes_ "! test -e $unit" && pass "N4 the autostart unit is gone" || fail "N4 unit still there"
[[ -z "$(g 'kreadconfig6 --file ksmserverrc --group General --key loginMode' | tail -n 1)" ]] && pass "N4 loginMode is back to not set" || fail "N4 loginMode: $(g 'kreadconfig6 --file ksmserverrc --group General --key loginMode')"
yes_ '! grep -q nvidia-drm /etc/default/limine' && pass "N4 the kernel parameters are gone from /etc/default/limine" || fail "N4 limine defaults still have them"
# Snapshot entries (snapper's, rootflags=.../.snapshots/N/snapshot) keep the command line of their time: a snapshot of the state with the
# parameters is meant to boot that state. Only the current boot entries count.
yes_ "! sudo grep 'cmdline:' /boot/limine.conf | grep -v '\.snapshots/' | grep -q nvidia-drm" && pass "N4 and from the current entries in /boot/limine.conf (snapshot entries keep their old command line)" || fail "N4 limine.conf still has them: $(g "sudo grep 'cmdline:' /boot/limine.conf | grep -v '\.snapshots/' | cut -c1-150" | tr '\n' '|')"
yes_ '! test -e /etc/mkinitcpio.conf.d/90-steamify-nvidia.conf && ! test -e /usr/local/libexec/steamify-nvidia-initramfs && ! test -e /etc/pacman.d/hooks/85-steamify-nvidia-initramfs.hook' && pass "N4 early-load file, hook and script removed" || fail "N4 initramfs files remain"
yes_ '! test -e /etc/sddm.conf.d/zzz-steamify-autologin.conf' && pass "N4 the SDDM autologin file is gone" || fail "N4 autologin file remains"
yes_ 'systemctl is-enabled -q plasmalogin.service && ! systemctl is-enabled -q sddm.service' && pass "N4 plasma-login-manager is the login manager again" || fail "N4 login manager: $(g 'systemctl show -p Id --value display-manager')"
yes_ '! is nvidia && ! is bigpicture && ! is single' && pass "N4 nvidia, bigpicture and single report off" || fail "N4 status still on"

reboot_guest && pass "N5 the VM is back after the second reboot" || { fail "N5 no ssh after the second reboot"; return 0 2>/dev/null || exit 0; }
up=""; for _ in $(seq 40); do vm_ssh "pgrep -u $VM_USER -x plasmashell" >/dev/null 2>&1 && { up=1; break; }; sleep 3; done
[[ -n "$up" ]] && pass "N5 Plasma comes up (the test autologin of plasma-login-manager)" || fail "N5 no plasmashell after the second reboot"
yes_ '! grep -q "nvidia-drm" /proc/cmdline' && pass "N5 the kernel parameters are off the command line" || fail "N5 cmdline still has them"
