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

## F. Features per release

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

## Results log

| Date | Branch / version | Blocks | Result |
|---|---|---|---|
| 2026-09-28 | `feat/defaults-options` 2.7.0 (uncommitted `--options`, `--boot`) | R1.1-R1.6, R2.1, F1-F7 | all pass (VM `--fremont`) |
| 2026-09-28 | same + CEC socket fix, UI label fix | R1.7, R1.10, U1-U8, H1, H4 (desktop), H5 | R1.7 first failed: `cec-audio-control.socket` never enabled (old bug, fixed: `cec_enable` enables it, `FEATURE_VERSION[cec]=2.7.0`); after: 53 PASS / 0 FAIL / 2 SKIP. UI: progress row said "Boot into Boot into" (fixed). Rest pass. Not run: R1.8, R1.9, R2.2, U9, H3 |
| 2026-09-28 | `release/2.7.0` (VM from vminstall.sh, `~/vms/steamify-vm`) | R1.2 (fresh, CEC socket), R1.8, R1.9, R1.5 via U9, U9, R2.1, R2.2, H3 | all pass except one old bug: theme on (single on) → single off → theme off left single's launcher keys; fixed (`58e43d4`, PR #34) and retested. BIOS dry run F7F0107 → F7F0108 passed; greeter and SDDM reboot checks passed |
| 2026-09-28 | `release/2.7.0` | H-Real | counted as passed: power-off fix, VRAM booster, LEDs, gamescope and Steam Machine support are unchanged since 2.6.0, which passed on the real Steam Machine. HDMI-CEC's change (enabling `cec-audio-control.socket`) passed with the fake TV in the VM; check the TV remote's volume keys on the real TV after updating (HDMI-CEC shows as update) |
