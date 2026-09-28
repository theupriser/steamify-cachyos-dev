---
name: steam-machine-iso
description: Use when working on the Steam Machine CachyOS ISO (repo steammachine-cachyos-live-iso) or Steamify's install-time mode (steamify.sh --defaults, --first-login) - building the ISO in podman (in the test VM, or on the Steam Machine), the Calamares Steamify step, simulating the installer in the test VM, and testing the first desktop login.
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
  - `archiso/airootfs/usr/local/bin/calamares-online.sh` (the installer
    launcher) copies CachyOS's `settings_online.conf` over
    `/etc/calamares/settings.conf` on every start, so a shipped settings.conf
    is lost: it `sed`s `shellprocess@steamify` (+ its instance) in before
    `cleanup_calamares` right after that copy.
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

## Adding a Calamares page/module for Steamify: check it's real first

Before writing any QML/config for a Calamares page, or building an ISO to
test one: confirm the module type is actually installed on this Calamares
build. A `.conf` file existing under
`archiso/airootfs/etc/calamares/modules/` does **not** mean the module
exists — CachyOS's branding ships some vestigial config files with no
matching `.so`. Check in a live session (boot the ISO,
`scripts/vmisoboot.sh`, no install needed):

```bash
ls /usr/lib/calamares/modules                    # real module types, e.g. packagechooser (not packagechooserq)
pacman -Ql cachyos-calamares-next | grep viewmodule
```

Found on this build (2026-09-28): `packagechooserq` (arbitrary custom QML,
`qmlFilename`) does **not exist** — only `packagechooser` does. Its
`mode: optionalmultiple` supports multi-select, but only with Shift/Ctrl-click (plain clicks
replace the selection; unusable for a real user) despite the misleading static label text
("Choose a product from the list. The selected product will be
installed." shows in both single- and multi-select modes — don't trust
it). Confirm real multi-select from the actual global-storage write in the
foregrounded debug log (`pkexec-wrapper calamares -D6`), not the label
text: `Config::updateGlobalStorage(const QStringList&)` logs
`"<instance>" selected "id1,id2,id3"` (comma-separated) when it works.

Test a page live, without any ISO rebuild: in the booted live session,
edit `/etc/calamares/modules/<module>_<instance>.conf` and the matching
module reference in `/etc/calamares/settings.conf`, then relaunch
(`pkexec-wrapper calamares -D6`). If Calamares is already running (e.g. an
earlier failed launch left its window open), a second launch just prints
"Calamares is already running." — close the first window
(Afbreken/Cancel, confirm) before relaunching. Only spend the 13+ minute
ISO build once the page's module and rendering are confirmed this way.

## Building the ISO in the test VM (preferred)

## Building the ISO in the test VM (preferred)

The build needs no real hardware: run it in the test VM (CachyOS; create it
with the vm-install skill), not on the Steam Machine. Not tried yet in the
VM: note what differs here. In the VM (`vm_ssh`, visibly in a Konsole there):

```bash
sudo pacman -S --needed --noconfirm podman git
git clone https://github.com/theupriser/steammachine-cachyos-live-iso ~/projects/steammachine-cachyos-live-iso
sudo mount -t 9p -o trans=virtio,version=9p2000.L repo /mnt     # the Steamify checkout (REPO)
cd ~/projects/steammachine-cachyos-live-iso && git checkout feat/steamify && ./steamify-prepare.sh /mnt
```

then the same `podman run` as below (paths in the VM; `~/projects/iso-build.log`).
The ISO (~3.2 GB) fits the 60G disk; copy it out with
`vm_scp "$VM_USER@$VM_HOST:~/projects/steammachine-cachyos-live-iso/out/desktop/*.iso" .`
(`scripts/common.sh`), then install it with `scripts/vminstall.sh --iso`.
Give the VM more room with a bigger disk if `out/`, `build/` and the package
cache grow over several builds (`sudo rm -rf build out` between builds).

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
     'pacman-key --init && pacman-key --populate && pacman -Syu --noconfirm --needed archiso mkinitcpio-archiso git squashfs-tools grub sudo && ./build-live-modules.sh && { ./buildiso.sh -p desktop -w || ./buildiso.sh -p desktop -c -w; }' \
   > $HOME/projects/iso-build.log 2>&1"
```

`build-live-modules.sh` builds the power-off fix for the ISO's kernels
(live session; needs the source steamify-prepare.sh puts on the ISO).
Output: `out/desktop/steamify-cachyos-*.iso` (~3.2 GB, ~10 min). The build ends with
`chown: missing operand` + `ERROR: An unknown error`: harmless, buildiso.sh
chowns to `$SUDO_USER`, unset as root; the ISO is already written. Each flag fixes a failure seen before:

- `--network=host`: the default network has no DNS here (every mirror
  "Resolving timed out").
- `--pids-limit=-1`: otherwise the last ~9 packages alphabetically fail with
  `GPGME error: Inappropriate ioctl for device` / "missing required signature".
- `pacman-key --init/--populate`: the image's keyring isn't initialised.
- The retry with `-c` keeps the work dir and cache for a flaky pass.

Never start a build while one runs (`sudo podman ps`): both use `build/`
and `out/`, and `rm -rf build out` breaks the running one. Don't stop a running build to try something else without checking its log
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

1. The first-login step (`~/.local/share/steamify/bin/first-login`, removes
   itself) starts the app through `run-app`, which always downloads the
   newest *release* (`releases/latest/download/steamify-app.sh`): before a
   release that shows the old version. For the branch's app, start it by
   hand afterwards as that user: copy `/mnt` to `/opt/steamify-test`
   (`chmod -R a+rX`), then `sudo -u isotest XDG_RUNTIME_DIR=/run/user/1001
   DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1001/bus systemd-run --user
   /opt/steamify-test/ui/steamify-ui`.
2. Gamescope doesn't run in the VM: `Session=plasma.desktop` in
   `/etc/sddm.conf.d/zz-steamos-autologin.conf`, remove
   `/etc/plasmalogin.conf.d/00-test-autologin.conf`, reboot.
3. Expect: Steam Deck wallpaper (Vapor layout), `primaryActions=3` in
   isotest's `plasma-org.kde.plasma.desktop-appletsrc`, the autostart entry
   gone, `steamify-ui` running next to `cachyos-hello`.
4. Screenshot: QMP `screendump` gives "no surface" with virgl; use
   `sudo -u isotest env XDG_RUNTIME_DIR=/run/user/1001 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1001/bus WAYLAND_DISPLAY=wayland-0 spectacle -b -n -f -o /tmp/shot.png`.

## Testing the ISO itself

Unattended: `VM_DIR=~/projects/iso-vm scripts/vminstall.sh --iso <built iso> --fremont`
(vm-install skill) installs it with the ISO's headless `cachyos-installer`;
Calamares and its Steamify step don't run then, so run `steamify-install`
from the live script for that part. Through Calamares by hand, as below.

Install the built ISO in a **new** VM (`~/projects/iso-vm`: copy of run.sh,
`share` symlink, `cachyos.iso` symlink to the build, own disk/vars; power the
test VM off first, both use port 2222; `run.sh install --fremont` as a user
unit), through Calamares, then check
`/var/log/steamify-install.log` in the installed system. In the chroot
`uname -r` is the live kernel: module loads and checks against the running
kernel may fail even when DKMS built for the installed kernels. Real
hardware (Steam Machine, USB stick) is the final test: gamescope, LEDs, CEC,
power-off.

## Live-session quirks

- Copy/paste doesn't reach QEMU over Moonlight: type commands with
  `python3 scripts/qmptype.py <vm dir>/qmp.sock "<command>"` (US layout, adds
  Enter; the VM window's terminal must have focus). QMP `screendump` gives "no
  surface" with virgl: screenshot the Steam Machine's desktop instead
  (`spectacle -b -n -f -o /tmp/host.png` in its session).
- CachyOS Hello refuses to start the installer on a self-built ISO ("testing
  ISO"): run `calamares-online.sh` in Konsole.
- `cachyos-calamares-next 3.4.2-13` needs `libboost_*.so.1.91.0` while the
  repos ship Boost 1.92: steamify-prepare.sh puts 1.91's libraries on the ISO
  (from archive.archlinux.org) until CachyOS rebuilds it.
- Driving the ISO VM's Calamares with `scripts/qmpkey.py`/`qmpclick.py`/
  `qmptype.py` (`scripts/vmisoboot.sh` for a VM without virgl, so
  `qmpshot.py` screendumps work): `qmptype.py`'s character map has no `>`
  or `&` — a typed command using either raises "no key for" and, worse,
  can leave an **unterminated quote** in the shell's input buffer (a
  stray `"` from a half-typed command), after which every later command
  you type gets silently absorbed into that one open string instead of
  running. Symptom: the prompt shows a bare `>` continuation instead of
  `[user@host ~]$`. Fix: send Ctrl+C first (`send-key` with `ctrl`+`c`),
  then retype. Prefer `| tee` over `> file`, and multiple `head`/`tail`
  calls over one long redirected command. Calamares page buttons
  (Volgende/Terug) move vertically as page content grows/shrinks: re-shot
  and re-locate the button after every page change, don't reuse a fixed
  y-coordinate. A second `pkexec-wrapper calamares -D6` while an earlier
  failed instance's window is still open just prints "Calamares is already
  running.": close that window first (its Cancel/Afbreken button, then
  confirm the "really cancel?" dialog).
- Run `pkexec-wrapper calamares -D6` in its **own Konsole tab**: it stays
  in the foreground and blocks that tab's shell. Typing into the same
  tab afterwards just echoes the text inertly into Calamares' stdin
  (no error, nothing runs). Open "New Tab" in Konsole for commands.
- Calamares' Welcome page applies its keyboard layout to the live session
  immediately (a live typing preview). If it's not US (e.g. Dutch after
  picking Nederlands), `qmptype.py`'s US-layout key map silently sends
  the wrong characters afterwards: `/` becomes `-`, `(`/`)` get garbled,
  with no "no key for" error. `setxkbmap us` does nothing on Wayland.
  Probe with a symbol-free command (`echo test123`) after any
  language/keyboard step, and fix the layout from the live session's own
  settings before typing paths or shell syntax again.
