---
name: steam-machine-iso
description: Use when working on the Steam Machine CachyOS ISO (repo steammachine-cachyos-live-iso) or Steamify's install-time mode (steamify.sh --defaults, --first-login) - building the ISO in podman on the Steam Machine, the Calamares Steamify step, simulating the installer in the test VM, and testing the first desktop login.
---

# Steam Machine ISO and Steamify's install-time mode

A CachyOS live ISO for the Steam Machine that installs Steamify's default
setup during the install. Two repos:

- `steamify-cachyos` (Steamify): `steamify.sh --defaults` applies what the
  menu would preselect, no prompts, passwordless sudo required. Without a
  session (installer) `user_systemctl` only changes unit files, the theme
  replaces an untouched `/etc/skel` Plasma layout so Plasma builds Vapor's at
  first login, and `lib/first-login.sh` leaves a one-time autostart
  (`--first-login`: single user's launcher on the new layout, then the app,
  next to CachyOS Hello). See AGENTS.md there.
- `steammachine-cachyos-live-iso` (fork of CachyOS-Live-ISO), branch work
  never on master:
  - `archiso/airootfs/etc/calamares/settings.conf`: CachyOS's own (from the
    `cachyos-calamares-next` package, `/usr/share/calamares/settings.conf`;
    `/etc/calamares` wins) with `shellprocess@steamify` before
    `cleanup_calamares`. Refresh it from the package when CachyOS changes
    theirs.
  - `modules/shellprocess_steamify.conf` runs
    `/usr/local/bin/steamify-install ${ROOT} ${USER}` outside the chroot; that
    gives the user a temporary NOPASSWD rule, runs the bundle with
    `arch-chroot ... runuser -u <user> -- env -i ... --defaults`, logs to
    `/var/log/steamify-install.log` in the target, never fails the install.
  - `steamify-prepare.sh [steamify checkout]` puts the bundle on the ISO
    (`archiso/airootfs/usr/local/share/steamify/steamify.sh`, git-ignored):
    from a checkout, else the newest release; refuses one without `--defaults`.

## Everything visible

The user watches the Steam Machine over Moonlight: run builds and tests in a
Konsole on its desktop (or open one that follows the log), never hidden.

```bash
ssh steammachine bash -c "'export XDG_RUNTIME_DIR=/run/user/1000 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus; systemd-run --user -q konsole --hold -e bash -c \"tail -n 50 -F ~/projects/iso-build.log\"'"
```

## Steam Machine gotchas

- Login shells there and in the VM are **fish**: wrap loops in
  `bash -c '...'` or pipe a script to `bash -s`.
- Never `pkill -f <pattern>` from a remote command containing that pattern:
  it kills its own shell (exit 255).
- The VM's host key lives in `~/projects/steamify-cachyos-dev/known_hosts`.
  Scripts calling plain `ssh` (vmreset.sh) need a wrapper first in `PATH`:
  `/tmp/steamify-sshwrap/ssh` =
  `exec /usr/bin/ssh -o UserKnownHostsFile=$HOME/projects/steamify-cachyos-dev/known_hosts -o StrictHostKeyChecking=accept-new "$@"`
  (recreate after a reboot).
- Run vmreset.sh as a systemd user unit with `-p KillMode=process`, a unique
  unit name, `--setenv=REPO=$HOME/projects/steamify-cachyos`, the wrapper
  `PATH` and `SSH_AUTH_SOCK` (connect with `ssh -A`, keep the session open with
  `--wait`). Without KillMode=process QEMU dies with the unit; without REPO
  QEMU fails on the old repo path and the script waits 5 minutes for SSH.

## Building the ISO (podman on the Steam Machine)

Only podman is installed on the Steam Machine itself; the build tools live in
the container. Rootful (loop devices, mounts), so `sudo podman ps` shows it,
not a rootless podman GUI. Clone: `~/projects/steammachine-cachyos-live-iso`.

```bash
cd ~/projects/steammachine-cachyos-live-iso
git checkout feat/steamify && ./steamify-prepare.sh ~/projects/steamify-cachyos
sudo rm -rf build out
systemd-run --user --collect -q -u isobuild-$(date +%s) --working-directory=$PWD bash -c \
  "sudo podman run --rm -t --pids-limit=-1 --ulimit nofile=65536:65536 --privileged --network=host \
     -v $PWD:/iso -w /iso docker.io/cachyos/cachyos:latest bash -c \
     'pacman-key --init && pacman-key --populate && pacman -Syu --noconfirm --needed archiso mkinitcpio-archiso git squashfs-tools grub sudo && { ./buildiso.sh -p desktop -w || ./buildiso.sh -p desktop -c -w; }' \
   > $HOME/projects/iso-build.log 2>&1"
```

Output: `out/desktop/*.iso`. Each flag fixes a failure seen before:

- `--network=host`: the default network has no DNS here (every mirror
  "Resolving timed out").
- `--pids-limit=-1`: otherwise the last ~9 packages alphabetically fail with
  `GPGME error: Inappropriate ioctl for device` / "missing required signature".
- `pacman-key --init/--populate`: the image's keyring isn't initialised.
- The retry with `-c` keeps the work dir and cache for a flaky pass.

Don't stop a running build to try something else without checking its log
first (`grep -ac GPGME ~/projects/iso-build.log`). The repo's CI recipe
(`archlinux:base-devel`, `.github/workflows/build.yml`) works too but pulls
from one slow mirror.

## Testing Steamify's install-time mode in the VM

`scripts/vminstallsim.sh [--fresh]` (VM up via vmreset.sh `--fremont`, branch
rsynced to `~/projects/steamify-cachyos`): creates `isotest` (never logged
in), runs `/mnt/steamify.sh --defaults` for it without any session, visibly.
Every component should print OK and `exit: 0`. Use `--fresh` after changes:
an earlier run's single user mode edits the skel layout, and the theme then
(rightly) refuses.

First desktop login as that user:

1. Point the first-login script at the test copy (it runs the newest
   release otherwise): copy `/mnt` to `/opt/steamify-test` (`chmod -R a+rX`),
   `sed -i 's#^curl .*#bash /opt/steamify-test/steamify.sh --first-login#'`
   `/home/isotest/.local/share/steamify/bin/first-login`.
2. Gamescope doesn't run in the VM: `Session=plasma.desktop` in
   `/etc/sddm.conf.d/zz-steamos-autologin.conf`, remove
   `/etc/plasmalogin.conf.d/00-test-autologin.conf`, reboot.
3. Expect: Steam Deck wallpaper (Vapor layout), `primaryActions=3` in
   isotest's `plasma-org.kde.plasma.desktop-appletsrc`, the autostart entry
   gone, `steamify-ui` running next to `cachyos-hello`.
4. Screenshot: QMP `screendump` gives "no surface" with virgl; use
   `sudo -u isotest env XDG_RUNTIME_DIR=/run/user/1001 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1001/bus WAYLAND_DISPLAY=wayland-0 spectacle -b -n -f -o /tmp/shot.png`.

## Testing the ISO itself

Install the built ISO in a **new** VM disk (never over the ssh-ready one),
with `--fremont`, through Calamares, then check
`/var/log/steamify-install.log` in the installed system. In the chroot
`uname -r` is the live kernel: module loads and checks against the running
kernel may fail even when DKMS built for the installed kernels. Real
hardware (Steam Machine, USB stick) is the final test: gamescope, LEDs, CEC,
power-off.
