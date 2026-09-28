# Changelog

All notable changes, per version and per commit. Versions follow
[Semantic Versioning](https://semver.org/) and were numbered from the start
of the history.

## 0.4.0 - 2026-09-28

An unattended VM install, a test plan, and the lessons from testing
Steamify 2.7.0.

- **feat: scripts/vminstall.sh installs an ssh-ready test VM unattended; TESTPLAN.md; vm-install skill**
  - `scripts/vminstall.sh [--force] [--iso <file>] [--fremont]`: CachyOS from
    the ISO's headless `cachyos-installer` (kernel booted directly with
    `systemd.run=` + `systemd.wants=`, files and log over
    `scripts/vminstall-server.py`), then `share/vminstall-post.sh`: sshd,
    passwordless sudo, test autologin, Limine `default_entry`. Snapshots
    `clean` and `ssh-ready`. User: the host's username, password `steamify`;
    key `~/.ssh/steamify-vm_ed25519` (made once, never overwritten).
  - `scripts/common.sh`: `VM_DIR`, and the VM's user, key and known_hosts from
    it; `run.sh`: `VM_ISO`, `VM_KERNEL`/`VM_INITRD`/`VM_APPEND`, `VM_SERIAL`,
    `repo-path`.
  - `scripts/steammachine-addkey.sh`: the VM key on the Steam Machine too.
  - `TESTPLAN.md`: regression, the app, features per release, Steam Machine
    hardware (faked and real), results log. `scripts/qmpkey.py` presses keys
    in the VM (drives the app).
  - Fixes: `vmreset.sh` doesn't restart plasmalogin when the snapshot already
    logged in (HELPER_TTY_ERROR); `vmstate.sh` reads `~/.local/state/steamify`;
    `vminstallsim.sh` passes `LANG=C.UTF-8` like the ISO.
  - Skills: update `ssh-ready` at the start of every session; the ISO is built
    in the test VM.

## 0.3.0 - 2026-09-27

The Steam Machine ISO and Steamify's install-time mode.

- `f8e2473` **feat: steam-machine-iso skill (ISO build in podman on the Steam Machine, installer simulation, first-login test) and scripts/vminstallsim.sh**

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
