# Changelog

All notable changes, per version and per commit. Versions follow
[Semantic Versioning](https://semver.org/) and were numbered from the start
of the history.

## 0.2.0 - 2026-09-24

Watchable test runs and the lessons from testing cachyos-gamescope-boot 0.7.0
(cachyos-vapor theme, LED driver on every kernel).

- `b4114a1` **feat: Visible wizard runs, one-step VM reset and screenshots; skill updates**
  - `scripts/vmreset.sh [--fremont]`: restore `ssh-ready`, boot, mount the repo,
    set up the test autologin and wait for Plasma.
  - `scripts/vmwatch.sh '<input>' [label]`: run the wizard in a visible Konsole
    in the VM, so someone at the QEMU window can follow along.
  - `scripts/vmshot.sh <out.png>`: screenshot via a user unit (spectacle
    crashes when started straight from SSH).
  - `scripts/vmstate.sh`: DKMS status per kernel, the DKMS override, the kernel
    headers service, the dark look-and-feel, the wallpaper and the theme's
    layout backup.
  - `scripts/cmp.sh`: also compares `kcminputrc` and `ksplashrc`.
  - Skill: VM directory outside the repo, the menu's first-run pre-ticks and
    the conversion/single-user coupling, the repo mount lost on reboot,
    re-applying the conversion resets the session to gamescope, the new
    theme and LED checks in the test matrix, and the broken mirror workaround.
- `3733f94` **docs: Changelog**
- `3cdf2e1` **feat: Fake BIOS version for testing the BIOS update item**
  - `BIOS_VERSION=F7F0107 ./run.sh ...` makes the guest report that BIOS
    version (SMBIOS type 0), so the wizard offers the update.
  - Skill: testing the BIOS item with `WIZARD_BIOS_DRY_RUN=1`, and the
    wizard's menu loop.
- `c6abfd2` **docs: Renamed to steamify-cachyos-dev, for Steamify CachyOS**
  - README and skill point to `github.com/theupriser/steamify-cachyos`; the
    local clone's default path (`REPO`) and the guest's state directory keep
    their old names.
- `8c48858` **chore: The wizard's script is now steamify.sh**
  - `vmrun.sh`, `vmwatch.sh`, the skill and the README run `/mnt/steamify.sh`.
- **feat: Release testing, cleaner resets and screenshots; skill updates**
  - `vmwatch.sh --release` runs the newest GitHub release in the VM.
  - `vmreset.sh` skips the broken krfoss mirror and installs shellcheck.
  - `vmshot.sh --clean` closes Steam, CachyOS Hello and Konsole first.
  - Skill: menu items 1-7 and the new menu loop/restart question, current
    scripted inputs, always finishing on a fresh snapshot (the DKMS bug only
    showed there), testing releases and their assets, the Steamify shortcut,
    and the zsh word-splitting pitfall.

## 0.1.1 - 2026-09-23

- `d2cf240` **fix: Document how to add the host SSH key to the VM**

## 0.1.0 - 2026-09-23

- `97c5c56` **fix: Add CachyOS test VM dev environment and VM testing skill**
