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

### F2.9.7 Gaming on NVIDIA (`feature/nvidia-gaming-fix`; suite `nvidia`, fake NVIDIA PC)

gamescope's session is broken on NVIDIA (see `nvidia/HARDWARE-RESULTS.md`), so on an NVIDIA PC the conversion is replaced by
"Gaming on NVIDIA" (Steam on the Plasma desktop, started at login, optionally in Big Picture) and single user mode logs in to Plasma.
The VM has no NVIDIA GPU: `fake_nvidia` (`share/vmtest/prelude.sh`) fakes one through Steamify's `NVIDIA_DRM_DIR` test hook and installs
fake NVIDIA modules for every kernel. What no VM can show (real driver, the picture, Big Picture on a real GPU) is checked on the real PC.

| # | Step | Expect |
|---|---|---|
| N1 | `--defaults --list` and `--backend status` with the fake GPU (`nvidia/10-n1-menu.sh`) | `nvidia`, `bigpicture` (parent `nvidia`), `single` offered and preselected; `gaming`, `boot`, `glyphs` hidden; without the fake GPU the conversion is offered and `nvidia` is not |
| N2 | `--defaults --options nvidia,bigpicture,single` (`nvidia/20-n2-n5-lifecycle.host.sh`) | exit 0; Steam installed; unit with `-gamepadui` enabled; `loginMode=emptySession`; parameters in `/etc/default/limine` and `/boot/limine.conf`; early-load file, hook and script; modules in the initramfs; SDDM enabled and `zzz-steamify-autologin.conf` (Plasma session) |
| N3 | reboot | Plasma straight in (no greeter), parameters on `/proc/cmdline`, the Steam unit started, `loginMode` kept |
| N4 | `--defaults --options notify` | exit 0; Steam removed (Steamify installed it), unit and autologin file gone, `loginMode` back to not set, parameters/early-load/hook gone, plasma-login-manager the login manager again |
| N5 | reboot | Plasma up through the test autologin, no NVIDIA parameters |
| N6 | real RTX 5080 PC | **done by hand 2026-10-01** (earlier prototype): Big Picture on the Plasma desktop smooth and clean; the apply/boot of the final component is the user's next step |

### F2.9.7 Extended controller support (`feature/extended-controller-support`; suite `cli`, block `60-c1-controllers.sh`)

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
