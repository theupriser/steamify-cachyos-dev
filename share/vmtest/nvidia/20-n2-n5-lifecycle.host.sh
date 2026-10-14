# N2-N5 (2.12.0): the SteamOS conversion on a fake NVIDIA PC, for real (pacman, the patched gamescope from GitHub, limine, initramfs).
# Covers TESTPLAN N2 (failure leaves the PC as it was), N3 (apply), N4 (the update path from "Gaming on NVIDIA"), N5 (offline reinstall
# from the cache, turn off).
unit='~/.config/systemd/user/steamify-steam-autostart.service'
g() { guest "$@"; }
yes_() { [[ "$(g "$1 && echo YES || echo NO" | tail -n 1)" == YES ]]; }   # a guest condition

# N2: a locked pacman database: the run fails, says why and changes nothing (the pre-flight's own messages are checked in G1).
g 'sudo touch /var/lib/pacman/db.lck'
rc="$(g 'fake_nvidia; sf --defaults --options gaming > /tmp/n2.log; echo "rc=$?"' | tail -n 1)"
g 'sudo rm -f /var/lib/pacman/db.lck'
[[ "$rc" != rc=0 ]] && pass "N2 a locked pacman database: the run fails ($rc)" || fail "N2 the run passed with pacman locked"
yes_ 'grep -q "db.lck" /tmp/n2.log' && pass "N2 and names the lock" || fail "N2 no reason in the log: $(g 'tail -n 8 /tmp/n2.log')"
yes_ '! pacman -Q steamify-gamescope-nvidia >/dev/null 2>&1 && ! grep -q nvidia-drm /etc/default/limine' && pass "N2 nothing was installed or changed" || fail "N2 the failed run changed the PC"

# The VM has no GPU: gamescope's smoke test needs a Vulkan device, so the software one (lavapipe) goes in first, as a real PC has its driver.
g 'sudo pacman -S --needed --noconfirm vulkan-swrast > /tmp/swrast.log 2>&1' >/dev/null

# N4 first state: "Gaming on NVIDIA" as 2.11 left it (Steam on the desktop, started at login).
info "N4 setting up the 2.11 state (Gaming on NVIDIA: Steam, autostart unit)..."
g 'sudo pacman -S --needed --noconfirm steam > /tmp/steam.log 2>&1; fake_nvidia; nvidia_write_unit -gamepadui && user_systemctl enable steamify-steam-autostart.service' >/dev/null
yes_ 'fake_nvidia; nvidia_status' && pass "N4 the old Gaming on NVIDIA state is on" || fail "N4 could not set the old state up"
python3 -c 'import json,sys; d={i["id"]:i for i in json.load(sys.stdin)["items"]}; sys.exit(0 if d["gaming"].get("update") and d["gaming"]["on"] else 1)' <<< "$(g 'fake_nvidia; sf --backend status' | sed -n '/^[\[{]/,$p')" 2>/dev/null && pass "N4 the menu shows the conversion as an update, ticked" || info "N4 menu: $(g 'fake_nvidia; sf --backend status' | head -c 400)"

# N3: apply the conversion.
info "N3 applying gaming (Steam, gamescope-session, the patched gamescope from GitHub, initramfs: several minutes)..."
rc="$(g 'fake_nvidia; sf --defaults --options gaming > /tmp/n3.log; echo "rc=$?"' | tail -n 1)"
[[ "$rc" == rc=0 ]] && pass "N3 apply exit 0" || { fail "N3 apply: $rc: $(g 'tail -n 20 /tmp/n3.log')"; return 0 2>/dev/null || exit 0; }
yes_ '! test -e ~/.config/systemd/user/steamify-steam-autostart.service && ! systemctl --user is-enabled -q steamify-steam-autostart.service' && pass "N4 the old autostart unit is gone (Steam no longer starts on the desktop)" || fail "N4 the autostart unit is still there"
yes_ 'pacman -Q steam >/dev/null 2>&1' && pass "N4 Steam stays installed" || fail "N4 Steam was removed"
ver="$(g 'pacman -Q steamify-gamescope-nvidia' | tail -n 1 | awk '{print $2}')"
pin="$(g 'fake_nvidia; echo $GSN_VERSION' | tail -n 1)"
[[ -n "$ver" && "$(printf '%s\n%s\n' "$pin" "$ver" | sort -V | head -n 1)" == "$pin" ]] && pass "N3 the patched gamescope is installed: $ver (pinned $pin or newer)" || fail "N3 patched gamescope: '$ver' (pin $pin)"
yes_ 'gamescope --version 2>&1 | grep -qi gamescope; pacman -Qi steamify-gamescope-nvidia | grep -q "^Provides.*gamescope"' && pass "N3 it provides gamescope (the stock one is replaced)" || fail "N3 not providing gamescope"
yes_ 'fake_nvidia; gsn_smoke_test' && pass "N3 the smoke test: the installed gamescope starts headless and runs a program" || fail "N3 smoke test failed"
yes_ 'fake_nvidia; gsn_status && is gaming' && pass "N3 gaming and the patched gamescope report on" || fail "N3 status"
yes_ 'grep -qx gamescope_drm_gbm_scanout=1 ~/.config/environment.d/99-steamify-gamescope-nvidia.conf && grep -qx gamescope_drm_gbm_scanout=1 ~/.config/gamescope-session/environment' && pass "N3 the GBM scan-out setting is in the session's environment files" || fail "N3 env files"
yes_ 'fake_nvidia; gsn_display_status' && pass "N3 the display-mode wrapper and its drop-in are installed" || fail "N3 display wrapper"
yes_ 'systemctl --user cat gamescope-session.service 2>/dev/null | grep -q "steamify-display\|\.local/share/steamify/bin"' && pass "N3 the gaming session unit uses the wrapper (drop-in loaded)" || info "N3 gamescope-session.service not loadable here: $(g 'systemctl --user cat gamescope-session.service 2>&1 | tail -n 4')"
yes_ "grep -q 'nvidia-drm.modeset=1 nvidia-drm.fbdev=1' /etc/default/limine && sudo grep -q 'nvidia-drm.fbdev=1' /boot/limine.conf" && pass "N3 the DRM kernel parameters are in /etc/default/limine and /boot/limine.conf" || fail "N3 kernel parameters"
yes_ 'test -f /etc/mkinitcpio.conf.d/90-steamify-nvidia.conf && test -f /etc/pacman.d/hooks/85-steamify-nvidia-initramfs.hook' && pass "N3 early-load file and initramfs hook installed" || fail "N3 initramfs files"
yes_ 'sudo find /boot -name "initramfs*" -exec sh -c "lsinitcpio {} | grep -q nvidia" \; -print | grep -q .' && pass "N3 the NVIDIA modules are in the initramfs" || fail "N3 initramfs has no nvidia modules"
yes_ '! grep -q "failed" <<< "$(fake_nvidia; state_get gamescope_nvidia failed)" && [[ -z "$(fake_nvidia; state_get gamescope_nvidia failed)" ]]' && pass "N3 the earlier failure mark is cleared" || fail "N3 failure mark remains"
yes_ 'grep -q "Patched gamescope installed" /tmp/n3.log' && pass "N3 the log says the patched gamescope was installed" || info "N3 log: $(g 'grep -i gamescope /tmp/n3.log | tail -n 5')"
out="$(g 'fake_nvidia; sf --defaults --options gaming')"
echo "$out" | grep -qiE 'Downloading|Installing|Building' && fail "N3 a second run downloads or installs again: $(echo "$out" | tail -n 5)" || pass "N3 a second run changes nothing (no download, no install)"
# N5 (before the reboot: after a boot lavapipe in this VM fails vkAllocateMemory for gamescope, see TESTPLAN G-notes): the package is gone and GitHub can't be reached: the copy in the cache is installed again, and still starts.
info "N5 removing the patched gamescope, no GitHub: reinstall from the download cache..."
rc="$(g 'fake_nvidia; sudo pacman -Rdd --noconfirm steamify-gamescope-nvidia >/dev/null 2>&1; GSN_RELEASES=http://127.0.0.1:9 gsn_install_package > /tmp/n5.log 2>&1; echo "rc=$?"' | tail -n 1)"
[[ "$rc" == rc=0 ]] && yes_ 'pacman -Q steamify-gamescope-nvidia >/dev/null 2>&1' && pass "N5 offline: installed again from the cache" || fail "N5 offline reinstall ($rc): $(g 'tail -n 8 /tmp/n5.log')"
yes_ 'fake_nvidia; gsn_smoke_test' && pass "N5 and it starts" || fail "N5 smoke test after the reinstall"

reboot_guest && pass "N3 the VM boots with the DRM parameters and the NVIDIA initramfs" || { fail "N3 no ssh after the reboot"; return 0 2>/dev/null || exit 0; }
yes_ 'grep -q "nvidia-drm.modeset=1" /proc/cmdline && grep -q "nvidia-drm.fbdev=1" /proc/cmdline' && pass "N3 the parameters are on the running command line" || fail "N3 cmdline: $(g 'cat /proc/cmdline')"

# N5: turn off.
info "N5 turning the conversion off..."
rc="$(g 'fake_nvidia; sf --defaults --options notify > /tmp/n5off.log; echo "rc=$?"' | tail -n 1)"
[[ "$rc" == rc=0 ]] && pass "N5 turn-off exit 0" || { fail "N5 turn-off: $rc: $(g 'tail -n 15 /tmp/n5off.log')"; return 0 2>/dev/null || exit 0; }
yes_ '! test -e ~/.config/environment.d/99-steamify-gamescope-nvidia.conf && ! grep -qs gbm_scanout ~/.config/gamescope-session/environment' && pass "N5 the GBM setting is gone from both files" || fail "N5 env files remain"
yes_ '! test -e ~/.local/share/steamify/bin/gamescope && ! test -e ~/.config/systemd/user/gamescope-session.service.d/steamify-display.conf' && pass "N5 the display wrapper and drop-in are gone" || fail "N5 display files remain"
yes_ '! grep -q nvidia-drm /etc/default/limine' && pass "N5 the kernel parameters are gone from /etc/default/limine" || fail "N5 limine defaults"
yes_ "! sudo grep 'cmdline:' /boot/limine.conf | grep -v '\.snapshots/' | grep -q nvidia-drm" && pass "N5 and from the current entries of /boot/limine.conf" || fail "N5 limine.conf"
yes_ '! test -e /etc/mkinitcpio.conf.d/90-steamify-nvidia.conf && ! test -e /etc/pacman.d/hooks/85-steamify-nvidia-initramfs.hook' && pass "N5 early-load file and hook removed" || fail "N5 initramfs files remain"
yes_ 'pacman -Q steamify-gamescope-nvidia >/dev/null 2>&1' && pass "N5 the patched gamescope package stays (like the conversion's other packages)" || fail "N5 package removed"
yes_ '! is gaming' && pass "N5 gaming reports off" || fail "N5 gaming still on"
