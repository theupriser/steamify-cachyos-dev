# since: 2.15.0
# Not a check: the README screenshot (assets/screenshot-menu-steam-machine.png) of the app from the checkout, every option on, on the faked
# Steam Machine (BIOS up to date). A big virtual screen, the app at Qt scale 1.75 (what the Steam Machine runs at), a KWin script that makes its
# window 1600 x SHOT_H without a frame and hides the panel; the full-screen capture lands in SHOT_OUT, crop it to 1600 x SHOT_H.
#   VMS=... REPO=<steamify-cachyos checkout> SHOT_H=1943 scripts/vmsuite.sh shot      (never part of vmtest.sh)
# env: BIOS_VERSION=F7F0108 VM_XRES=2560 VM_YRES=2300
H="${SHOT_H:-1943}"; out="${SHOT_OUT:-${VMS:-$HOME/vms}/shot-out}"; mkdir -p "$out"
OPTS=gaming,silent,glyphs,theme,single,launcher,steamgame,notify,extended_controller_support,vram,cec,cecaudio,machine,fancontrol,poweroff,wifi,wol,wowlan
info "applying Steamify with every option (several minutes)..."
guest "mkdir -p ~/.local/share/Steam/userdata/12345678/config; echo 'drm/card0/vram0 17179869184' > /var/tmp/dmem.capacity
export WIZARD_VRAM_CAPACITY=/var/tmp/dmem.capacity
sf --defaults --options $OPTS | tail -n 6; echo applied-rc=\${PIPESTATUS[0]}" | tail -n 8
guest 'sudo modprobe vivid 2>&1 | head -n 1; ls /dev/cec0 2>&1; pacman -Q pyside6 qt6-svg >/dev/null 2>&1 || sudo pacman -S --needed --noconfirm pyside6 qt6-svg >/dev/null 2>&1; echo ready'| tail -n 3
info "starting the app and sizing its window to 1600 x $H..."
guest "export WIZARD_VRAM_CAPACITY=/var/tmp/dmem.capacity QT_SCALE_FACTOR=1.75
pkill -u \$USER -f steamify-ui 2>/dev/null; (setsid /mnt/ui/steamify-ui >/tmp/ui.log 2>&1 &)
sleep 15
cat > /tmp/shot.js <<'JS'
for (const w of workspace.windowList()) {
    if (String(w.resourceClass).toLowerCase() === 'steamify-ui') { w.noBorder = true; w.frameGeometry = {x: 0, y: 0, width: 1600, height: $H}; }
    else if (w.dock) { w.opacity = 0; }
}
JS
id=\$(qdbus6 org.kde.KWin /Scripting org.kde.kwin.Scripting.loadScript /tmp/shot.js shot)
qdbus6 org.kde.KWin /Scripting/Script\$id org.kde.kwin.Script.run
sleep 4; echo kwin-script=\$id; pgrep -af steamify-ui | head -n 2 | cut -c1-80; tail -n 3 /tmp/ui.log"
guest 'rm -f /tmp/shot.png; systemd-run --user --wait -q spectacle -b -n -f -o /tmp/shot.png; ls -l /tmp/shot.png' | tail -n 2
vm_scp "$VM_USER@$VM_HOST:/tmp/shot.png" "$out/readme-full.png" && pass "screenshot: $out/readme-full.png ($(stat -c %s "$out/readme-full.png") bytes, crop to 1600 x $H)" || fail "no screenshot copied"
