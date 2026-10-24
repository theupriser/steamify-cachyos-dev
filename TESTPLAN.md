# Steamify test plan

What to test before a Steamify release, in the VM (`--fremont`) and on the
real Steam Machine. How to run each step: `.claude/skills/cachyos-vm-testing`.
**Keep this file up to date**: add a section when a feature is added, and a
line to the results log after every test run.

Every VM run starts with the session start of the skill (`ssh-ready` brought
up to date), and each numbered block below starts from a fresh `ssh-ready`
(`scripts/vmreset.sh --fremont`, `REPO=` the branch checkout). Runs are
visible in a Konsole on the VM's desktop.

## R. Regression (every release)

### R1. Menu on an existing desktop (user `theupriser`)

| # | Step | Expect |
|---|---|---|
| R1.1 | `'q\n'` | first-run ticks: everything but Boot into desktop, BIOS |
| R1.2 | `'\ny\nm\nq\nn\n'` | every item OK, back in the menu with all on |
| R1.3 | `scripts/vmstate.sh` | SDDM + autologin, Vapor, 17 LEDs owned by the user, DKMS `installed` for every kernel, steamos-manager active |
| R1.4 | rerun `'\nq\n'` | "Everything is already the way you want it" |
| R1.5 | re-apply `'a\ny\nm\nq\nn\n'`, `vmstate.sh` | no errors, no `DUPLICATES` |
| R1.6 | `steamify.sh --backend status` | valid JSON, current `VERSION`, states match R1.3 |
| R1.7 | close the app first, then `sudo modprobe vivid; scripts/vmcec.sh --no-sleep` | all PASS (2 SKIP in the VM: wake from TV, sleep). The fake remote's Select arrives as Enter: an open app on "All done" restarts the PC |
| R1.8 | toggles (theme, single user, CEC, Steam Machine support off/on) | full matrix in the skill; `cmp.sh` clean after theme off |
| R1.10 | set an item older in `~/.local/state/steamify/features.state` (e.g. `cec=2.1.0`), `'q\n'`, then `'\ny\nm\nq\nn\n'` | menu shows "HDMI-CEC (update)" ticked; the plan lists it as "update"; after the run the file has the current version |
| R1.9 | reboot checks | single user: SDDM logs straight in; everything off: greeter |

### U. The app (`/mnt/ui/steamify-ui`, on the VM's desktop)

Drive it with `scripts/qmpkey.py <vm dir>/qmp.sock <keys>` (QEMU qcodes:
`up down left right ret esc ctrl-ret ctrl-q r`; wait ~1 s between keys and
~12 s after starting the app) and check every screen with a screenshot
(`spectacle -b -n -a` for the active window; the progress screen of a quick
change only shows right after Enter).

| # | Step | Expect |
|---|---|---|
| U1 | start after R1.5 | header `v<VERSION>`, Steam Machine chip, every row with "now on", Kernel / LED bar (17) / HDMI-CEC / Version panel |
| U2 | Up/Down over the rows | detail panel follows: body text and "What it changes" per row |
| U3 | an updated feature (bump `FEATURE_VERSION`, or `features.state` older) | `UPDATE` badge, "1 change" |
| U4 | Boot into: Right / Left | Gaming / Desktop, detail panel `DESKTOP`, change count +1 |
| U5 | Enter on a toggle, Enter again | off, back on, count back |
| U6 | Ctrl+Enter | review lists exactly the changes, summary counts right; Esc goes back |
| U7 | Enter (apply) | progress per step ("Boot into desktop", update badge), details log, "All done, N changes applied", Restart now / Back to the menu |
| U8 | after U7 | the changes are on the system (e.g. boot-desktop unit, `features.state`) |
| U9 | `r` (re-apply), Ctrl+Q | re-apply review; the app quits |

### R2. Installer mode (`scripts/vminstallsim.sh`, user `isotest`, no session)

| # | Step | Expect |
|---|---|---|
| R2.1 | plain `--defaults` | every item OK, `exit: 0`, first-login autostart present |
| R2.2 | first desktop login (steam-machine-iso skill) | Vapor layout, `primaryActions=3`, autostart gone, app opens |

### F2.8.0 `--defaults --list`

| # | Step | Expect |
|---|---|---|
| G1 | `steamify.sh --defaults --list` | exit 0, valid JSON array, no stderr, no header text mixed in |
| G2 | items | actions (bios), retired (kpin, hdmi) excluded; unavailable here (vram, steamgame) excluded; poweroff has parent machine, boot has parent gaming and kind choice |
| G3 | menu / plain `--defaults` still work | unaffected (regression) |

## F. Features per release

### F-GNOME. Steamify on GNOME/GDM (`feature/gnome-prototype`; suite `gnome` on `~/vms/gnome-vm`, plain CachyOS + GNOME + GDM, no Steamify)

`scripts/vmsuite.sh gnome` (also part of `vmtest.sh`). KDE regression for it: cli block `70-k1-kde-unchanged.sh`.

| # | Block | Expect |
|---|---|---|
| GN1 | `10-n1-menu.sh` | GDM and GNOME detected; GNOME theme offered; Plasma theme and single user mode hidden (menu and `--backend status`) |
| GN2 | `20-n2-conversion.sh` | `custom.conf` autologin, AccountsService `Session`/`XSession`, GDM-aware session tools (CachyOS's kept as `.bak-steamify`), pacman hook, sudoers rule, GNOME packages, launcher entry, shellcheck, second apply changes nothing |
| GN3 | `30-n3-turn-off.sh` | `custom.conf` and CachyOS's tools exactly as before; hook, sudoers rule, helper gone; GDM stays |
| GN4 | `40-n4-theme.sh` | dark style, accent, wallpaper, buttons, GTK4 colors, extensions; off restores every value |
| GN5 | `50-n5-desktop-pref.sh` | `--desktop kde\|gnome\|last` stored, bad values refused, the session tool resolves to what is installed |
| GN6 | `60-n6-switch-reboot.host.sh` | stand-in gamescope session: boot into it, Switch to Desktop, Return to Gaming Mode, boot into desktop and back across reboots, pacman hook restores our tools |
| GN7 | `70-n7-both-desktops.sh` | with Plasma installed too: GDM kept, both themes offered, preferred/last desktop picks the session |
| GN8 | to write (stand-in session) | 2.13.0: a theme-only run ends in the relogin countdown (Cancel keeps "Restart GNOME"), `steamify-gdm-relogin <session>` lands in the session the app runs in and puts AccountsService `Session`/`XSession` back; no helper = plain logout; a run that needs a reboot shows Restart now, no countdown |
| GN9 | to write (screenshots) | theme off/on/off with a relogin after each: top bar icons and overview search still work; dash favorites, `gio list-apps`, `~/.local/share/icons/hicolor` (PNG, no `index.theme`), gsettings leftovers (`gtk-theme`). **Reported broken on hardware, not diagnosed** (gnome/PLAN.md) |
| GN10 | to write | extension ownership: `gnomeextras.list` before install (missing packages only); both off removes those packages and the two extensions from `enabled-extensions`; theme off with the conversion on keeps them enabled; user-installed packages stay |
| GN11 | manual, real session | app window frame and buttons (minimize/maximize/close), Restart now, scale 100% and at a GNOME scale of 150%, `--fullscreen` unchanged, one click flips a switch and a row click only selects, header logo (needs `qt6-svg`), dock icon after the launcher option (PNG by name) |
| GN12 | to write | prebuilt Settings package (`settings` release): download + checksum + `pacman -U --ask 4` installs the "GNOME Desktop" panel, off puts stock back; offline / wrong checksum / pacman conflict keep stock with a warning |
| GN13 | manual | desktop icons from the top right in name order (Return to Gaming Mode, Steam, Steamify CachyOS), user's own files keep their positions, off restores `start-corner`; dock at the bottom |
| GN14 | manual, real PC with two OSes | Limine with a second Linux install on the same ESP: the other install's entry survives a reinstall of this one (it does not today: repaired by hand twice, recipe in gnome/PLAN.md); order CachyOS, CachyOS GNOME, Windows; Secure Boot (sbctl) with the hand-written entry NOT done |

Not automatable: gamescope itself (no rendering in the VM), the app's dock icon and window frame, the Settings panel, real hardware (GDM restart behaviour).

### F2.12.0 The SteamOS conversion on NVIDIA (`release/2.12.0`; suite `nvidia`, fake NVIDIA PC)

Since 2.12.0 "Gaming on NVIDIA" (Steam on the desktop) is replaced by the SteamOS conversion with a patched gamescope
(`lib/gamescope-nvidia.sh`, package from `steamify-gamescope-nvidia`: GBM scan-out cures the corrupted picture) and the DRM kernel
parameters / initramfs setup of `lib/nvidia.sh`. The VM has no NVIDIA GPU: `fake_nvidia` (`share/vmtest/prelude.sh`) fakes one
through Steamify's `NVIDIA_DRM_DIR` test hook and installs fake NVIDIA modules for every kernel; `vulkan-swrast` (lavapipe) gives
gamescope's smoke test a Vulkan device. What no VM can show (real driver, the picture, the display mode, suspend, Steam on a real GPU)
is checked on the real RTX 5080 PC (N6).

| # | Step | Expect |
|---|---|---|
| N1 | `--defaults --list` and `--backend status` with and without the fake GPU (`nvidia/10-n1-menu.sh`) | `gaming`, `boot`, `glyphs`, `single` offered; `nvidia`, `bigpicture`, `nvsilent` hidden; the same menu without the GPU |
| G1 | `nvidia/15-g1-gamescope-nvidia-functions.sh` (no install) | version compare; CPU level; every pinned sha256 is a hash and the PKGBUILD builds the pinned version; no GitHub: no latest tag, a damaged backup copy refused, one with a matching hash used; update notice (newer / same / offline); pre-flight refuses a pacman lock; failure reminder set and cleared; environment files idempotent and keep other lines; display wrapper + drop-in installed/removed, a foreign file at the wrapper's path kept |
| N2 | pacman locked, `--defaults --options gaming` (`nvidia/20-n2-n5-lifecycle.host.sh`) | exit not 0, names `db.lck`, no patched gamescope, no kernel parameters |
| N3 | 2.11 state ("Gaming on NVIDIA": Steam + autostart unit), then `--options gaming` | the menu shows the conversion as an update; exit 0; autostart unit gone, Steam stays; patched gamescope installed (pinned or newer) and provides `gamescope`; smoke test passes; environment files, display wrapper, kernel parameters (`/etc/default/limine`, `/boot/limine.conf`), early-load file, hook, modules in the initramfs; second run downloads and installs nothing; reboot: parameters on `/proc/cmdline` |
| N4 | (part of N3) | the old autostart unit is gone, Steam stays |
| N5 | package removed + no GitHub: `gsn_install_package`; then `--options notify` | installed again from the download cache and starts; turn-off: environment files, wrapper, drop-in, kernel parameters, early-load file, hook gone; patched gamescope package stays |
| N6 | real RTX 5080 PC | **by hand**: gaming mode picture clean (no corruption), display's own mode and refresh rate, Steam UI size, switching to the desktop and back, suspend/resume, newer-release update notice |

### F2.10.0 Extended controller support (`feature/extended-controller-support`; suite `cli`, block `60-c1-controllers.sh`)

Opt-in item: `xpadneo-dkms`, `xone-dkms` and `xone-dongle-firmware` from the CachyOS repo, DKMS-built for every kernel. The VM has no
dongle or controller: it covers the packages, the headers and the builds, not the hardware.

| # | Step | Expect |
|---|---|---|
| C1 | `--defaults --options extended_controller_support` | exit 0; the three packages installed; `dkms status` shows xone and xpadneo installed for every kernel; the modules (`xone_dongle`, `hid_xpadneo`) exist for each |
| C2 | the same again | quiet, nothing installed again |
| C3 | `--defaults --options notify` | exit 0; the three packages removed again |
| C4 | real PC with the Xbox dongle | **by hand, 2026-10-01 earlier**: the dongle works with the AUR `xone-dkms-git` (modules `xone_dongle`, `xone_gip_gamepad` loaded); status counts `xone-dkms-git` as on |

### F2.7.0 `--defaults --options` / `--boot`

| # | Step | Expect |
|---|---|---|
| F1 | `--options` (no value), `bogus`, `boot`, `bios`, `--boot` (no value), `--boot sideways`, `--skip x` | each `exit: 1` with a clear error, nothing changed |
| F2 | `--options theme --boot desktop` (either order) | `exit: 1`: desktop needs the conversion |
| F3 | `--options gaming,theme,glyphs,single,launcher,notify,vram,cec,machine,poweroff --boot desktop` | all on, boot-desktop unit enabled; VRAM left out with a warning in the VM |
| F4 | `--options theme,single,machine --boot desktop` | single brings the conversion; poweroff, CEC, glyphs, launcher, notify recorded `off` |
| F5 | `--options launcher,vram,poweroff` | poweroff brings Steam Machine support; conversion off, plasmalogin unchanged |
| F6 | `steamify.sh --boot desktop` without the conversion | `exit: 1` |
| F7 | on an install: `--boot desktop`, again, `--boot gamescope` | only Boot into changes; "Already starting in desktop"; menu ticks unchanged |
| S1 | "Start Steam silently in desktop mode" (`cli/80-s1-silent-autostart.sh`, #109) | the autostart entry is `Exec=/usr/bin/steam -steamdeck -silent %U` (from the system steam.desktop and from the template), no `-gamepadui`; re-applying changes nothing; an old `-silent` entry is rewritten; the old systemd unit goes; an install recorded at an older feature version shows an update; off removes the entry |
| W1 | "Wi-Fi firmware from SteamOS" (`cli/82-w1-wifi-firmware.sh`, #108) | `linux-firmware-holo` from `holo-main` (checksum verified); only `ath11k/QCA2066/hw2.1/amss.bin.zst` lands in `/usr/lib/firmware/updates` (nothing of linux-firmware touched); re-applying changes nothing; off removes the file and the empty directories; a package without the file or a failed download installs nothing; opt-in, child of `machine`, feature version set; not offered off a Steam Machine. On the hardware: after a restart the kernel logs `fw_build_timestamp 2025-07-16 10:46` (CachyOS's own is 10:33) |
| W2 | "Wake-on-LAN" and "Wake-on-WLAN" (`cli/83-w2-wake-on-lan.sh`, #108) | Wake-on-LAN is a NetworkManager drop-in (`ethernet.wake-on-lan=64`, reloaded and re-applied to the wired devices); Wake-on-WLAN is a systemd sleep hook in `/usr/lib/systemd/system-sleep` (NetworkManager ignores `wifi.wake-on-wlan` with the iwd backend); re-applying changes nothing; off removes the file or hook; without NetworkManager wired fails and writes nothing, wireless still works; Wake-on-WLAN warns when the Wi-Fi firmware isn't SteamOS's and removes the development builds' files; menu: opt-in children of `machine`, ticking wowlan ticks the firmware, unticking the firmware unticks wowlan, machine off clears all. **By hand, on the Steam Machine with someone at it:** (a) wired: `ethtool enp5s0` shows `Wake-on: g` after a restart; suspend, magic packet to the NIC wakes it (a wake from a power-off was tried and does not work on the Steam Machine, see the log); (b) Wi-Fi connected, firmware item on: `iw phy phyN wowlan show`, suspend, magic packet over Wi-Fi wakes it and it stays asleep until then; (c) off again: both back to `d` / disabled after a restart; since 2.14.2 also a **NetworkManager dispatcher script** (`/etc/NetworkManager/dispatcher.d/90-steamify-wowlan`, on `up` of a Wi-Fi interface) so WoWLAN is on before the first suspend of a boot (the hook alone enables it too late for that one, #108): by hand, after a fresh restart and with no earlier suspend, `iw phy phy0 wowlan show` says enabled and the first suspend wakes on a Wi-Fi magic packet |
| C4 | "HDMI-CEC volume" (`cli/84-c4-cec-audio.sh`, #107, `# base: applied`) | on: `[steamify-valve-audio]` is listed once and is the **first** repository in `pacman.conf`; pipewire, libpipewire, wireplumber and libwireplumber (and the 32-bit libraries when installed) are the repository's builds, pipewire and libpipewire one version, the binary reports that version, Valve's `libspa-alsa.so` contains the external-volume code; the WirePlumber rule is in `~/.config/wireplumber` with this user's socket; timer enabled; script installed; `pacman -Sup` plans no PipeWire/WirePlumber upgrade; applying again changes nothing; the refresh (what the timer runs) works and installs nothing itself; off: CachyOS's pipewire and wireplumber are back, the repository, its database, rule, timer and script are gone, `pacman.conf` is identical to before, `steamdeck-dsp` and `noisetorch` are removed; off twice is fine. By hand on the real Steam Machine: Steam's Audio page shows TV Volume (minus, plus, mute) and the CEC toggle with it on, the slider with it off |

## H. Steam Machine hardware

### H-VM. With the faked Steam Machine (`--fremont`)

| # | Step | Expect |
|---|---|---|
| H1 | LED driver | `leds_valve` loaded, 17 `valve-leds*` nodes owned by the user (no light to see) |
| H2 | HDMI-CEC | R1.7 (vivid: fake TV and remote) |
| H3 | BIOS update | `BIOS_VERSION=F7F0107 scripts/vmreset.sh --fremont`, `WIZARD_BIOS_DRY_RUN=1`: whole flow, never flashes |
| H4 | Boot into desktop, reboot | Plasma straight after boot; Boot into gaming: SDDM autologin into gamescope (black in the VM, see the skill; check the session file) |
| H5 | power-off module | DKMS built for every kernel, module loads, "No such device" (no GPIO wake bit in the VM) |

### H-Real. Only on the real Steam Machine

- Power-off fix: stays off after shutdown, for every new major kernel.
- VRAM booster (the VM has no `dmem` VRAM region).
- Gamescope itself: gaming mode, Switch to Desktop / Return to Gaming Mode.
- LED bar light, real TV over HDMI-CEC (remote, TV on/off, sleep/wake).

## B. Boot loaders (`scripts/vmtest.sh`, unattended)

Every loader the ISO advertises (Limine, systemd-boot, GRUB), each on a VM installed from the Steamify ISO
and started with `--fremont`. Automated: `scripts/vmtest.sh` (see the vm-install skill).

| # | Step | Expect |
|---|---|---|
| B1 | first boot after the unattended install, and every reboot | boots by itself through the loader's own EFI boot entry (`BootCurrent`, a real partition; checked after every reboot), no network boot first (systemd-boot: the entry comes from the ISO's `steamify-install` since PR #2; `timeout`/`default` set by the test setup), SSH answers |
| B2 | Steamify's state, as its own `*_status` functions | gaming, theme, glyphs, single, launcher, notify, poweroff, cec all on |
| B3 | OS name | `os-release` NAME/PRETTY_NAME are CachyOS's, `lsb-release` has no "with Steamify"; Limine has `TARGET_OS_NAME` |
| B4 | loader identity, firmware setup | the expected loader; `Boot into FW: supported` (BIOS item) |
| B5 | DKMS modules (`leds-valve`, `cros-ec-cec`, `steamify-fremont-poweroff`) | installed for every kernel, files present, `modules-load.d` entry |
| B6 | legacy `drm.edid_firmware` removal (`hdmi_remove_boot_param`) | detected, removed, initramfs and entries rebuilt, no edid left |
| B7 | kernel update (both kernels + headers) | DKMS rebuilds 3 modules per kernel, initramfs rebuilt, loader config regenerated |
| B8 | reboot into the default and the other kernel | both boot, no failed units, power-off fix and LED modules loaded on each |

## Known gaps

- "Add as non-Steam game" can't be set up at install time (no Steam account
  yet); not covered by any installer test.
- ISO: `steamify-install` and the packagechooser pages still pass `--skip`
  (removed in 2.7.0); to be replaced by the Steamify page.

- `/etc/plasmalogin.conf` missing before Steamify (a VM from vminstall.sh,
  not Calamares): turning the conversion off leaves an empty file instead of
  none (harmless; Calamares installs have one, restored from the backup).
- R2.2: the first login's app is the newest *release* (`run-app`), so before
  a release it shows the old version; start the branch's app by hand
  (steam-machine-iso skill).

- CEC: the driver source comes from an unofficial mirror of Valve's kernel on GitHub; since 2.9.1 it is
  downloaded once and cached (/var/cache/steamify; the VMs share the host's), so only a first download
  can hit GitHub's rate limit (HTTP 429).

## Results log

| Date | Branch / version | Blocks | Result |
|---|---|---|---|
| 2026-09-28 | `feat/defaults-options` 2.7.0 (uncommitted `--options`, `--boot`) | R1.1-R1.6, R2.1, F1-F7 | all pass (VM `--fremont`) |
| 2026-09-28 | same + CEC socket fix, UI label fix | R1.7, R1.10, U1-U8, H1, H4 (desktop), H5 | R1.7 first failed: `cec-audio-control.socket` never enabled (old bug, fixed: `cec_enable` enables it, `FEATURE_VERSION[cec]=2.7.0`); after: 53 PASS / 0 FAIL / 2 SKIP. UI: progress row said "Boot into Boot into" (fixed). Rest pass. Not run: R1.8, R1.9, R2.2, U9, H3 |
| 2026-09-28 | `release/2.7.0` (VM from vminstall.sh, `~/vms/steamify-vm`) | R1.2 (fresh, CEC socket), R1.8, R1.9, R1.5 via U9, U9, R2.1, R2.2, H3 | all pass except one old bug: theme on (single on) → single off → theme off left single's launcher keys; fixed (`58e43d4`, PR #34) and retested. BIOS dry run F7F0107 → F7F0108 passed; greeter and SDDM reboot checks passed |
| 2026-09-28 | `release/2.7.0` | H-Real | counted as passed: power-off fix, VRAM booster, LEDs, gamescope and Steam Machine support are unchanged since 2.6.0, which passed on the real Steam Machine. HDMI-CEC's change (enabling `cec-audio-control.socket`) passed with the fake TV in the VM; check the TV remote's volume keys on the real TV after updating (HDMI-CEC shows as update) |
| 2026-09-29 | `feature/vminstall-bootloader` (Steamify ISO 2026.09.28, `--fremont`) | B1-B8 | Limine 41 / systemd-boot 40 / GRUB 40 checks pass. Found on the way (test setup, not Steamify): ufw blocks ssh, systemd-boot has no timeout/default after cachyos-installer |
| 2026-09-28 | `release/2.8.0` (`feature/defaults-list`) | G1-G3, R1.1, R1.2 | all pass (VM `--fremont`, fake Steam Machine). Bundle shellcheck clean |
| 2026-09-29 | Steamify 2.9.0 (`steamify-cachyos` main), ISO `feat/steamify` with PR #2 (2026.09.29), dev `main` 5b867f8; on the PC (WSL2) | everything automated: B1-B8 (3 loaders), cli, menu, hw, installer, toggles (`scripts/vmtest.sh`, parallel, `MAX_PARALLEL=3`) | **328 pass, 0 fail** (toggles 42 +1 expected skip, hw 70, cli 55, menu 36, installer 4, Limine 41, systemd-boot 40, GRUB 40) in 18 minutes: the first complete parallel run. Found on the way: systemd-boot had no EFI boot entry (installer's `bootctl` in a chroot), fixed in the ISO (PR #2); `vminstall.sh` fixes for parallel installs and a root host user |
| 2026-09-29 | ISO `feat/steamify` + PR #3 (`/var/log`), dev `main` with the B1 boot entry check | B1-B8 | Limine 43 / GRUB 42 pass (boot entry check passes: `Limine`, `cachyos`). systemd-boot (reinstalled): 36 pass, 8 fail, all CEC: the driver download got HTTP 429 from GitHub (rate limit); boot entry check passes (`Linux Boot Manager`); `/var/log/steamify-install.log` and `steamify-bootentry.log` readable after boot |
| 2026-09-29 | Steamify `release/2.9.1` (CEC driver cache), ISO `feat/steamify` (PRs #2, #3), dev `main` | everything automated incl. hw block 50 (CEC cache) and the B1 boot entry check | **341 pass, 0 fail** in 19 minutes (toggles 42 +1 expected skip, hw 77, cli 55, menu 36, installer 4, Limine 43, systemd-boot 42, GRUB 42) |
| 2026-09-30 | Steamify 2.9.6 (`steamify-cachyos` main `d93f9ea`), the official ISO `steamify-cachyos-2.9.6-260930-x86_64.iso` from git.upriser.nl (sha256 `4a94f308…aec41`), dev `main`; on the PC, headless (`CI=1`/`VM_HEADLESS=1`), `MAX_PARALLEL=5` | everything automated: B1-B8 (3 loaders, `--install` from the new ISO), cli, menu, hw, installer, toggles (base VM from the same ISO with `VM_STEAMIFY=skip`) | **341 pass, 0 fail** (toggles 42 +1 expected skip, hw 77, cli 55, menu 36, installer 4, Limine 43, systemd-boot 42, GRUB 42). Found on the way (test setup, not Steamify or the ISO): with five VMs at once the loaders' first boot took longer than `waitssh` waited (5 min), so all three stopped with `FAIL no SSH` although the VMs were up; `waitssh` now waits up to 15 minutes and the loaders were run again (install kept) |
| 2026-10-01 | Steamify `feature/extended-controller-support` (7dae14c; on top of `feature/nvidia-gaming-fix` d0e4d8c, 2.9.7), plain CachyOS ISO 260809 (VM `~/vms/steamify-vm`, `vminstall.sh --iso`), dev `main` + the nvidia suite; on the PC (native CachyOS, KVM), headless | N1-N5 (new suite `nvidia`), C1-C3 (cli block 60), R1.1-R1.6/R1.10, H1-H5 and the CEC/CEC cache blocks, R2.1, toggles | **269 pass, 0 fail**: cli 65, nvidia 43, menu 37, hw 78, installer 4, toggles 42. Found on the way (test side, not Steamify): R1.1 and H3 pressed menu rows by number and the new Extended controller support row shifted them (now by name); the N4 check for the parameter in `/boot/limine.conf` must ignore snapper's snapshot entries, which keep the command line of their time. The kernel part (parameters, early-load file, hook, initramfs) behaves in a real Limine VM; the real driver and picture are only checked on the RTX 5080 PC |
| 2026-10-14 | Steamify `release/2.12.0` (dc189dc), plain CachyOS VM `~/vms/steamify-vm` (new ssh key: the old throwaway one was gone, authorized in the `ssh-ready` snapshot), dev `main` + the new nvidia suite; on the laptop (Ubuntu, KVM), headless | cli, menu, hw, installer, toggles, nvidia (N1, G1, N2-N5 rewritten for 2.12.0); boot loaders and the plain-PC install check not run (need the Steamify ISO) | **292 pass, 0 fail** (cli 65, menu 37, hw 78, installer 4, toggles 42, nvidia 66). Before the rewrite the old nvidia suite failed 8 checks, all because "Gaming on NVIDIA" is gone in 2.12.0. Test side: gamescope's smoke test needs a Vulkan device, so the VM gets `vulkan-swrast`; after a reboot the same gamescope fails with `vkAllocateMemory failed (-2)` on lavapipe in this VM (before the reboot it passes), so the offline-reinstall check runs before the reboot. Not seen on real hardware yet (N6) |
| 2026-10-14 | Steamify 2.12.0 on the ISO `steamify-cachyos-2.12.0-dev-261014-x86_64.iso` (sha256 `bd93fa6b…ed47c`, built from `release/2.12.0`), dev `main` (7dd1f37); on the laptop (Ubuntu, KVM), headless | B1-B5 for limine, systemd-boot and grub; the plain-PC install check (generic) for all three | boot loaders: **limine 43, systemd-boot 42, grub 42 pass, 0 fail**. Plain PC: 21-22 pass, **1 fail per loader: "cec is on, but this is not a Steam Machine"**. Cause: `steamify-install` falls back to "everything on" (`...,vram,cec,machine,poweroff`) when Calamares passes no selection (the headless test install), and `cec` is offered on every PC; `poweroff` stays off by itself (`machine_available`). The docs say HDMI-CEC is ticked by default only on a Steam Machine: either the ISO's fallback should only include `cec` on a Steam Machine, or this check should not expect it off. To decide; a real install through the chooser is not affected by the fallback. Test side: three parallel first installs corrupted the shared package cache (`could not rename ... .part`): install one VM first to fill `~/vms/pkg-cache`; a first retry also hit a transient "cachyos: signature ... is invalid" from a mirror. Laptop needs a `bsdtar` shim (pycdlib) and `VM_SSH_KEY` outside `~/.ssh` |
| 2026-10-14 | Steamify 2.12.0 on the rebuilt ISO `steamify-cachyos-2.12.0-dev-261014-x86_64.iso` (the ISO repo's PR #26 merged: the install fallback only turns HDMI-CEC on for a Steam Machine), dev `main` (7e11b94); laptop, headless | B1-B5 for limine, systemd-boot, grub; the plain-PC install check for all three | **boot loaders: limine 43, systemd-boot 42, grub 42; plain PC: limine 23, systemd-boot 22, grub 22: all pass, 0 fail.** The earlier "cec is on, but this is not a Steam Machine" is fixed. (The limine boot line in the summary says "aborted" only because its VM already existed from the first run of the same ISO; its 43 passed.) Test side: six parallel installs of a newly released kernel corrupted the shared package cache (`linux-cachyos ... corrupted (PGP signature)`): delete the new files from `~/vms/pkg-cache/pkg`, install one VM first, then the rest |
| 2026-10-15 | Steamify `feature/gnome-prototype` (dbaeaa1, from 2.12.0), plain CachyOS VM `~/vms/steamify-vm` and the new GNOME VM `~/vms/gnome-vm`, dev `main` + the `gnome` suite; laptop, headless | KDE regression: cli (+ new block 70-k1), menu, hw, installer, toggles, nvidia. GNOME: GN1-GN7 | **KDE: cli 89, hw 78, menu 37, installer 4, nvidia 66, toggles 42: 0 fail.** **GNOME: 0 fail** (first run 110 pass, 5 fail, all test bugs: shellcheck needs `-S warning -e SC2034,SC2154`, the VM's GDM already had autologin, a sed range cut the function out; GN2, GN3, GN5 re-run: 32, 11, 8 pass; GN1, GN4, GN6, GN7 passed first time). The Go-only `backend` suite and `share/golden` were removed (the Go refactor is scrapped). Not run: boot loaders, app screens U1-U9, real hardware |

| 2026-10-15 (evening) | Steamify `release/2.13.0` (PRs #85-#93 merged; app from `~/steamify-cachyos` on the RTX 5080 PC, fresh CachyOS + GNOME, `systemd-run --user`) | by hand on the hardware: conversion + GNOME theme apply, Settings package from the `settings` release, relogin countdown, theme off/on, dock/icons/scale/clicks, Limine repair | Apply, prebuilt Settings, relogin into GNOME (session restored), scale, clicks, dock icon (PNG), dock bottom, extension removal: fine. **After several theme off/on cycles GNOME was roughed up (no icons in the top bar, search broken): not diagnosed, GN9.** Limine lost the main CachyOS entry again after the reinstall: repaired by hand (GN14). Not run: Secure Boot, the VM suites, KDE regression, app screens on KDE |
| 2026-10-23 | `bugfix/steamdeck-autostart` (#109, #111) into `release/2.13.3`; the real Steam Machine, plain CachyOS libs from the branch | S1, S2 (blocks cli/80, cli/81, run on the Steam Machine in a throwaway HOME with the real system steam.desktop, and in a CachyOS container on the nuc: no qemu there) and by hand on the hardware: Steam Beta, reboot, Switch to Desktop, Return to Gaming Mode | S1 15 pass, S2 2 pass on the fix; the same blocks on `main` (2.13.2) fail 5 checks as expected. Bundle shellcheck 0 warnings, like `main`. **By hand: with the new autostart entry (`-steamdeck -silent`) Steam Beta (`steamdeck_publicbeta`) stayed selected over a reboot, the switch to the desktop (Steam started silently from the entry) and back to gaming mode; `package/beta` unchanged, no flip to `steamdeck_stable` in the bootstrap log.** Not run: the VM suites |
| 2026-10-23 | `bugfix/wifi-firmware` (#108) into `release/2.13.3`; the real Steam Machine | W1 (block cli/82, run on the Steam Machine in a throwaway dir) and by hand: install, restart, dmesg | W1 24 pass (incl. which build is in use: Valve's, CachyOS's, unknown; nothing installed when linux-firmware has Valve's). **On the hardware the installed file is Valve's (compressed `ce23f76f`, decompressed `a0c75e4c`, as in the ticket) and after the restart ath11k loads the 10:46 build instead of 10:33, no errors.** Not run yet: Wake-on-WLAN suspend and magic packet, wired Wake-on-LAN, wake from power-off (waiting until someone is at the machine) |
| 2026-10-23 | `feature/wake-on-lan` (#108) on top of `bugfix/wifi-firmware`; the real Steam Machine | W2 (block cli/83, run on the Steam Machine in a throwaway dir, nmcli stubbed) | W2 23 pass. **Not run: the wakes themselves (rows (a) to (c) of W2, by hand at the machine); the branch keeps `.no-release-yet` until they are**. |
| 2026-10-23 | `release/2.14.0` (60baf66: Wi-Fi firmware, Wake-on-LAN, Wake-on-WLAN) on the real Steam Machine, applied through the app | W2 by hand, over ssh, magic packets from another PC on the same /24 (`wol.py`, UDP broadcast) | **Wired, from sleep: pass.** After a restart `ethtool enp5s0` shows `Wake-on: g` (the NetworkManager drop-in works); s2idle suspend, a magic packet for the NIC's MAC wakes it 2 s later (3 runs; boot id unchanged, no network or Wi-Fi driver errors); 60 s asleep with no packet stays asleep; a packet for a wrong MAC (90 s) does not wake it, the right one does. The Wi-Fi firmware loads the 10:46 build. **Not tested yet:** Wake-on-WLAN (needs a Wi-Fi connection: the profile applies it), wired wake from power-off (BIOS wake-on-LAN), turning both off again. The `.no-release-yet` marker stays until they are |
| 2026-10-23 | `bugfix/wowlan-sleep-hook` (#117) on top of `release/2.14.0`; the real Steam Machine | W2 rewritten for the hook (31 pass on the machine), then by hand over ssh (`wol.py`, suspend by `systemctl suspend`, the journal read with `pm_debug_messages` on) | **Wake-on-WLAN through the sleep hook: pass.** The hook runs `pre suspend` and `iw` reports magic-packet enabled just before sleeping; 10 of 10 Wi-Fi magic packets (for the Wi-Fi MAC, broadcast) woke it within 3 to 4 s; a packet for a wrong MAC did not (earlier run). NetworkManager does not apply `wifi.wake-on-wlan` with iwd (profile value, reconnect and reapply tried). Self-wakes: about 60 suspends without a packet, one with the ticket's signature (IRQ 40, "unrelated to ACPI SCI"), and an earlier stretch with several keyboard-controller wakes (IRQ 1 + 9) that also happened with Wi-Fi wake off, the cause not found (not the Pucks' USB wake: 0 of 28 suspends with one or both enabled afterwards). **Still not tested:** wired wake from power-off (BIOS), both options off again after a restart |
| 2026-10-23 | `bugfix/wowlan-sleep-hook` (#117); the real Steam Machine with the BIOS's "S4/S5 WoL" and "S4 WoWiFi" both on | W2 (a), wired wake from a power-off, by hand over ssh (poweroff, 45 s control, a wrong-MAC packet, then a packet for the wired MAC `90:82:c3:6b:b5:9e`, broadcast) | **Fail: the machine did not start.** Off for 45 s with no packet: stayed off; wrong MAC: stayed off; right MAC: no answer for 2 minutes. Wake from sleep works (3 of 3), so both options are documented and described as wake from sleep only. Not checked: whether the port's link light stays on while off; hibernate (S4) is untested |
| 2026-10-23 | `bugfix/wowlan-sleep-hook` (#117); the real Steam Machine | W2 (c): `wol_disable` and `wowlan_disable` from the branch, then a restart | **Pass.** Both files and the sleep hook are gone right after; after the restart `ethtool enp5s0` says `Wake-on: d`, `iw phy phy0 wowlan show` says disabled, no Steamify file in `/etc/NetworkManager/conf.d` or `/usr/lib/systemd/system-sleep`; the Wi-Fi firmware option (separate) is still on, USB wake unchanged. All of W2 is done now except what cannot work on this machine (wake from a power-off) |
| 2026-10-23 | `release/2.14.1` (`feature/cec-audio-control` #121 and the screenshot #122 merged); the real Steam Machine (Sony TV, Plasma 6.8.1, kernel 7.3.0-4) | C4 by hand through the real installer (the single-file bundle, `--backend apply`, the same command the app uses), and Steam's Audio page by screenshot | **Pass.** Option on (plan: cec re-applied as an update, cecaudio): Valve's PipeWire 1.6.8-1.7 and WirePlumber 0.5.18-1.2 with the 32-bit libraries at 1.6.8-1; `pacman -Su` plans no PipeWire upgrade; the second run is a no-op; Steam shows TV Volume (minus, plus, mute) and "Enable HDMI CEC audio control" like the issue's screenshot (with only Valve's WirePlumber: the toggle with "The connected device does not support HDMI CEC for volume and mute settings", still a slider: Valve's PipeWire is needed too; nothing ever connected to the cec-audio-control socket before). Off through the installer: CachyOS's 1.6.10 and 0.5.18-1.1 back, `steamdeck-dsp`/`noisetorch` removed, nothing left, `pacman.conf` identical to its backup. PipeWire's graph timing on the HDMI output (quantum 1024 at 48 kHz, 0 dropouts, busy 12-16 us against 13 us) is the same with either build. Found on the way: a live restart of PipeWire and Sunshine hit Sunshine's start limit (5 per 500 s) and left Moonlight without a host: the option now asks for a restart instead. Not checked: that minus and plus change a TV's volume (the Sony TV answers Feature Abort to the audio-status queries), Moonlight audio with Valve's PipeWire after the restart, the app's restart prompt |
| 2026-10-23 | `release/2.14.1` (8551f58), the VM `~/projects/vms/steamify-vm` (plain CachyOS, Plasma 6.8.1, kernel 7.3.0-5; the September image brought up to date), dev `main` (`daad4cc`) with the new block C4; on the real Steam Machine (QEMU/KVM, 31 GB, headless, everything under `~/projects`; `VMS=~/projects/vms`), a terminal following the log on its desktop | everything automated that applies: cli, hw, menu, installer, toggles, nvidia (the boot loaders need the Steamify ISO; the gnome suite is for 2.15.0) | **toggles 43, hw 77, menu 37, installer 4, nvidia 66: 0 fail. cli 228 pass, 8 fail, and the same 8 fail on the released `main` (2.14.0) in the baseline run (`70-k1` 4, `80-l1` 4): both blocks are for the unreleased GNOME release 2.15.0 (K1 needs `desktop_kind` from lib/desktop.sh; L1 expects the 2.15.0 login drop-ins and still says "2.14.0" from before the renumbering), not for 2.14.1. New block C4: 34 pass.** Test side, found on the way: the shared prelude assumed Plasma's socket is `wayland-0`, but a login that had to be restarted gets `wayland-1` (the freshly updated VM needed that), so `lookandfeeltool` aborted (exit 134) and every theme step failed (hw, toggles and cli blocks): the prelude and `vmrun.sh` look the socket up now. `vmsuite.sh`, `common.sh` and `vminstall.sh` take `VMS` (default `~/vms`) so the VMs can live in `~/projects/vms` as the Steam Machine rule wants; the VM user needs the Steam Machine's own key (`$SRC/id_vm`), added through the Mac's forwarded agent once |
| 2026-10-23 (evening) | `release/2.14.1` (8551f58); the real Steam Machine, HDMI-CEC and HDMI-CEC volume turned on through the installer (`--backend apply`: plan cec, cecaudio; it asked for a restart), then a real restart | C4 by hand after the restart | **Pass.** It boots into gaming mode on Valve's PipeWire 1.6.8 and WirePlumber 0.5.18-1.2 (32-bit libraries 1.6.8); the HDMI sink has `api.alsa.external-volume-control` and `steamos.supports-hdmi-cec`; cecd, cec-audio-control and Sunshine (listening) are up; Steam runs with `STEAM_ENABLE_CEC=1` and its Audio page shows TV Volume (minus, plus, mute) and the CEC toggle. **Reported by the user: "it works perfectly"** (the buttons and a Moonlight stream after the restart, not itemized). No new failed units (gamescope-xbindkeys, ibus-gamescope and steam-notif-daemon already failed before the change) |
| 2026-10-24 | `release/2.14.1` (hook only), the real Steam Machine; the report by a user on #108: the first suspend after a boot does not wake on a Wi-Fi magic packet | W2 by hand, over ssh and magic packets from the Mac (`wol.py`): this boot (3 h, no suspend yet), WoWLAN disabled before, `systemctl suspend`, a packet for the Wi-Fi MAC; then a second suspend in the same boot | **Reproduced.** First suspend of the boot: the hook enabled WoWLAN (`iw` says enabled afterwards) but the Wi-Fi packet got no wake in 33 s; a wired packet woke it (the machine recovers by itself this way, no button). Second suspend (WoWLAN already on): the Wi-Fi packet woke it in 4 s. My earlier 10 of 10 wakes were all in a boot that had suspended before, so they did not cover this case (no entry of the log said "first suspend after a boot"). Test side: ping still answers for up to a minute after `PM: suspend entry` (s2idle takes ~30-60 s to take the links down): wait for both addresses to go down before sending the packet |
| 2026-10-24 | `release/2.14.2` (`bugfix/wowlan-dispatcher`, #124: the NetworkManager dispatcher script); the real Steam Machine, applied through the installer (`--backend apply`: wowlan shown as an update) | W2 by hand: after each fresh restart (no earlier suspend in the boot), `iw` before the suspend, the first suspend, a Wi-Fi magic packet; three restarts, the last with the final code | **Pass, 3 of 3:** WoWLAN already enabled before the first suspend (the dispatcher runs when the Wi-Fi connects at boot); the Wi-Fi packet woke it in 3 s, 3 s and 5 s, boot id unchanged. Without the dispatcher (above): no wake. Applying through the installer enabled WoWLAN right away, without a restart. Not tested: wpa_supplicant as the NetworkManager backend (the reporter tried it with iwd and wpa_supplicant, both fine), a Wi-Fi reconnect or a network switch (the reporter's tests) |
| 2026-10-24 | `release/2.14.2` (85c95b7), the VM `~/projects/vms/steamify-vm` (Plasma 6.8.1), dev `main` (33e8339: W2 block extended for the dispatcher); on the real Steam Machine, headless, everything under `~/projects` | everything automated that applies: cli, hw, menu, installer, toggles, nvidia | **toggles 43, hw 78, menu 37, installer 4, nvidia 66: 0 fail. cli 233 pass, 8 fail: the same 8 as on released main (`70-k1` 4, `80-l1` 4, for the unreleased GNOME release).** W2 (block 83): 36 pass, 0 fail, including 6 new checks for the dispatcher (installed and executable, the real path in `dispatcher.d`, `wlan0 up` enables magic-packet on its phy, any other event or a cable or the loopback or no arguments does nothing and exits 0, re-applying changes nothing, off removes it). Not run: the boot loaders (need the Steamify ISO) |
| 2026-10-24 | `release/2.14.2` (85c95b7); the real Steam Machine, by hand over ssh (magic packets from the Mac with `wol.py`, `systemctl suspend`, the journal for `PM: suspend entry/exit`), then every VM suite again | W2 dispatcher: Wi-Fi reconnect, the wpa_supplicant backend and a **cold boot** (the reporter's case on #108); regression | **Pass.** Reconnect: WoWLAN cleared with `iw`, `nmcli dev disconnect wlan0`, still disabled; `nmcli con up`: enabled again (iwd and wpa_supplicant). wpa_supplicant (`wifi.backend=wpa_supplicant`, NetworkManager restarted, then a restart): WoWLAN on before any suspend, the first suspend of the boot woke ~10 s after the Wi-Fi packet. **Cold boot** (`poweroff`, power button, iwd): WoWLAN on before any suspend, no suspend in the journal; first suspend, a Wi-Fi packet woke it ~6 s later (entry 13:13:28, exit 13:13:54). Regression, same code: toggles 43, hw 78, menu 37, installer 4, nvidia 66: 0 fail; cli 233 pass, 8 fail (the same K1/L1 as on released main). Test side: something rewrites `99-valve-wifi-backend.conf` back to `wifi.backend=iwd` at boot, so a cold boot on wpa_supplicant wasn't tried (original backed up as `/root/99-valve-wifi-backend.conf.orig`); `run-suite.sh` on the machine isn't executable (run it with `bash`). Network switch (two profiles, `doofen-iot` on 192.168.179.0/24 and the home network): with WoWLAN cleared, `nmcli con up` of the other profile enabled it again in both directions. Not tested: a wake on the `doofen-iot` network (the Mac isn't on that subnet) |
