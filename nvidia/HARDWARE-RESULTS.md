# NVIDIA fix: results on the RTX 5080 PC (2026-10-01)

PC: RTX 5080 (GB203, 10de:2c02) + AMD Granite Ridge iGPU, MSI MAG 341C OLED on the NVIDIA DP-1 (3440x1440, 175 Hz),
CachyOS, Limine, kernel 7.2.8-1-cachyos, nvidia-open 615.71.09, gamescope 3.16.31-1, gamescope-session-cachyos 1.1.6-1.

## Result: the kernel-parameter fix does not cure the picture
- Baseline (before): gaming mode corrupted without HDR; with HDR it worked but not at 175 Hz and not full screen.
- After `apply` + reboot (`modeset = Y`, `fbdev = Y`, NVIDIA modules in the initramfs): flickers heavily, artifacts, still no 175 Hz.
  `modeset`/`fbdev` were already `Y` live before the fix (driver 615), so the fix changed little.
- Cause is not the parameters: NVIDIA's open bug "display modes above 2560x1440@120 with HDR cause flickering/corruption within
  gamescope-session" (internal bug 5240452, April 2025, no fix as of March 2026; 555 up to 595+, RTX 3070 Ti/4090/5090; corruption is
  display-side only):
  https://forums.developer.nvidia.com/t/display-modes-above-2560x1440p-120hz-with-hdr-enabled-cause-flickering-corruption-within-gamescope-session/295314

## Bugs found in the fix on this PC (fixed in commit a5e9015 on feature/nvidia-gaming-fix)
- CachyOS writes Limine's line as `KERNEL_CMDLINE[default]+="..."`; the sed only matched `=`, so apply stopped with "Couldn't add the NVIDIA parameters".
- The kernel treats `nvidia_drm.modeset=1` and `nvidia-drm.modeset=1` alike; the check only knew the hyphen.
- tests/nvidia-hardware-test.sh did not set `SCRIPT_DIR`, so patch_file read `/patches/...`.

## What gamescope did (journal, gaming mode)
- Picks the RTX 5080 (card1), DP-1, mode list has 3440x1440@175/144/100. It selected @60 by default; with
  `-W 3440 -H 1440 -r 175` added (a copy of /usr/lib/steamos/gamescope-session, whose last line is `-O ... \` so args need a copy)
  it selected @175 and did not crash, but the picture was the same. Steam then sets the Xwayland size to 1920x1080 (not full screen).
- `vkGetPhysicalDeviceFormatProperties2 returned zero modifiers` for 2 16-bit formats: harmless here.
- A gamescope SIGABRT (`double free or corruption`) at session exit, backtrace through libnvidia-eglcore and libvulkan_radeon.
- The PC froze once and was reset after a gaming-mode session (no kernel error logged).

## What works: nested gamescope inside KDE (Wayland), borderless
- `gamescope -W 3440 -H 1440 -r 175 -f ...`: artifacts once the window is focused and fullscreen (unfocused it is fine).
  Hypothesis, not proven: KWin's direct scanout of the fullscreen window.
- `gamescope -W 3440 -H 1440 -r 175 -b -e --hdr-enabled -- steam -gamepadui` (borderless): clean, full screen, about 175 Hz.
- So on NVIDIA the separate gamescope session (the SteamOS conversion) is blocked by the driver bug; a nested borderless gamescope works.
  Whether Steamify gets a nested option for NVIDIA is the user's decision.

## State of the PC after the test (to undo)
- The fix is applied (Limine file backup `/etc/default/limine.bak-gamescope-wizard`, early-load file, pacman hook): undo in INSTRUCTIONS.md.
- User override of the gaming session: `~/.config/systemd/user/gamescope-session.service.d/steamify-nvidia-test.conf` and
  `~/.local/share/steamify/nvidia-test/`.
