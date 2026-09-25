---
name: cachyos-vm-testing
description: Use when testing Steamify CachyOS (repo steamify-cachyos, steamify.sh) changes in the CachyOS QEMU test VM - starting/stopping the VM, restoring snapshots, running the wizard over SSH with scripted menu input, checking each component's state, reboot checks and screenshots.
---

# Testing Steamify CachyOS in the CachyOS VM

The wizard (`steamify.sh` + `lib/*.sh`) opens a menu that detects
which components are on and toggles them to match the user's choice. Menu order:

1. SteamOS conversion (boot into gaming mode via autologin, Return to Gaming Mode shortcut, Steam desktop autostart)
2. └ Boot into: gamescope / desktop (sub-option of 1, shown while 1 is ticked; Left/Right or the number switches it)
3. SteamOS theme (installs `cachyos-vapor` and applies the Vapor global theme with its desktop and window layout; needs a running Plasma session)
4. Steam Deck/Machine icons (`STEAM_GAMEPADUI_ARGS -steamos3`)
5. Single user mode (SDDM, no lock screen/user switching/log out, Valve's empty KDE wallet; enabling it enables 1, disabling 1 disables it)
6. Steamify shortcut (desktop icon + launcher entry that `curl | bash` the newest release; its gear icon is a release asset)
7. HDMI-CEC (any PC, opt-in, never pre-ticked: Valve's cecd from the holo repo; see "Fake HDMI-CEC")
8. Steam Machine support (only on DMI Valve/Fremont: leds-valve-dkms-git built for every kernel via `/etc/dkms/leds-valve-dkms.conf`, `ensure-kernel-headers.service`, udev rule, steamos-manager, powerdevilrc)
9. └ Pin the kernel to 7.1.6-1 (sub-option of 8, ticked along with it; packages in `/var/cache/steamify/kernel`)
10. Update BIOS (only on Fremont, an opt-in action, never pre-ticked; tickable only when Valve has a newer BIOS)

Without `--fremont` the menu has only 1-7. Numbers shift when a parent is
unticked (its sub-option is hidden), so read the ticks with `'q\n'` first.

Undo journals live in `~/.local/state/cachyos-gamescope-boot/` in the guest.

Run everything from the root of this repo on the host. Defaults: user
`theupriser`, SSH port `2222` (the scripts take `VM_USER` / `VM_PORT` / `VM_HOST`).

The VM's disk, `vars*.fd` and `run.sh` copy may live outside the repo
(`~/vms/cachyos-test` on the main dev machine). Find it with
`readlink /proc/$(pgrep -f '^qemu-system')/cwd` when the VM runs; the
snapshot commands below run in that directory. `scripts/vmreset.sh` takes
`VM_DIR` and defaults to the repo if it holds `disk.qcow2`, else `~/vms/cachyos-test`.

## Quick start (the usual loop)

```bash
scripts/vmreset.sh --fremont        # restore ssh-ready, boot, mount repo, autologin, wait for Plasma
                                    # (also skips the broken krfoss mirror, installs shellcheck)
scripts/cmp.sh save                 # baseline of the KDE configs
scripts/vmwatch.sh '1\n3\n\ny\n' "Theme only"   # wizard in a visible Konsole in the VM
scripts/vmwatch.sh --release '\ny\nm\nq\n' "Full run"   # the newest GitHub release instead of /mnt
scripts/vmstate.sh                  # component state
scripts/vmshot.sh --clean /path/shot.png    # screenshot (--clean: close Steam/Hello/Konsole first)
```

**Always finish on a fresh `ssh-ready` snapshot**, ideally with `--release`
once published. Re-applying or toggling on an already set-up VM hides
first-install bugs: the DKMS override silently failed on a fresh system
(`/etc/dkms` doesn't exist before `dkms` is installed), which no re-apply
showed because `dkms` was there already.

Long runs (full install: packages, yay, DKMS) take 10+ minutes: run them
with `run_in_background` and wait with an until-loop, not chained sleeps.

Prefer `vmwatch.sh` over `vmrun.sh` when the user is watching the QEMU
window: `vmrun.sh` runs invisibly over SSH, so they see nothing happen.

## VM lifecycle

Start in the background:

```bash
./run.sh --fremont > /tmp/vm.log 2>&1 &     # flags: [install] [--fremont] [--nvidia] [--vulkan]
```

Wait for SSH:

```bash
until ssh -p 2222 -o BatchMode=yes -o ConnectTimeout=3 theupriser@localhost true 2>/dev/null; do sleep 3; done
```

Shut down and wait until QEMU is gone. Use `'^qemu-system'`: a plain
`pgrep -f qemu-system` also matches the shell running it.

```bash
ssh -p 2222 -o BatchMode=yes theupriser@localhost sudo systemctl poweroff
while pgrep -f '^qemu-system' >/dev/null; do sleep 2; done
```

## Snapshots

Only while the VM is off. Keep vars.fd together with the disk.

```bash
qemu-img snapshot -l disk.qcow2                                               # list
qemu-img snapshot -a ssh-ready disk.qcow2 && cp vars.ssh-ready.fd vars.fd     # restore
qemu-img snapshot -c my-state disk.qcow2 && cp vars.fd vars.my-state.fd       # create
```

Existing snapshots: `clean` (fresh install) and `ssh-ready` (sshd + host key +
passwordless sudo). Reset to `ssh-ready` before each full test run.

## First-time guest setup

Only when building from `clean`. In the guest console:

```bash
sudo mount -t 9p -o trans=virtio,version=9p2000.L vmtools /media && /media/guest-ssh-setup.sh
```

This installs and enables sshd, opens the firewall (ufw/firewalld if active),
adds the host keys (`share/host-keys.pub`, written by `run.sh`) and a NOPASSWD
sudoers rule for the test user.

## Mounting the project repo

The mount is lost on every reboot (unless the fstab line below was added).
Without it the wizard fails with `/mnt/steamify.sh: No such file
or directory`, which is easy to miss in filtered output. Remount after each reboot.

The repo (`REPO`, default `~/projects/cachyos-gamescope-boot`) is shared
read-write as 9p tag `repo`. The `ssh-ready` snapshot does not mount it:

```bash
ssh -p 2222 -o BatchMode=yes theupriser@localhost bash -s << 'EOF'
sudo mount -t 9p -o trans=virtio,version=9p2000.L repo /mnt
# optional, survives reboots:
grep -q ' /mnt 9p ' /etc/fstab || echo 'repo /mnt 9p trans=virtio,version=9p2000.L,nofail 0 0' | sudo tee -a /etc/fstab
EOF
```

## Remote commands: the guest shell is fish

Pass remote commands as bash heredocs, never as inline strings containing `$`:

```bash
ssh -p 2222 -o BatchMode=yes theupriser@localhost bash -s << 'EOF'
echo "$HOME"
EOF
```

## Getting a Plasma session

On a fresh snapshot the plasmalogin greeter is shown. Enable test autologin:

```bash
ssh -p 2222 -o BatchMode=yes theupriser@localhost bash -s << 'EOF'
sudo mkdir -p /etc/plasmalogin.conf.d
printf '[Autologin]\nUser=theupriser\nSession=plasma.desktop\n' | sudo tee /etc/plasmalogin.conf.d/00-test-autologin.conf
sudo systemctl restart plasmalogin
EOF
```

Remove `/etc/plasmalogin.conf.d/00-test-autologin.conf` before testing the
"normal login screen" case.

## Running the wizard non-interactively

`scripts/vmrun.sh '<input>'` does this (log also at `/tmp/wizard.log` in the
guest). Manually, in the guest:

```bash
export XDG_RUNTIME_DIR=/run/user/1000 WAYLAND_DISPLAY=wayland-0 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus
printf '\ny\nm\nq\n' | /mnt/steamify.sh
```

Menu input: a number toggles a component, an empty line continues, `a`
re-applies what is on, `q` quits; then `y` answers "Go ahead?". The wizard
**loops**: after a run it asks for Enter (back to the menu), or `[m]`/`[r]`
(menu / restart now) when a restart is needed. On `q` with a restart pending
it asks "Restart now? [Y/n]" (default **yes**): `n` goes back to the menu and
the next `q` asks again. Input that runs out quits without restarting, so end
scripted input right after the last `q` (or with `n`), never with an empty
line at the restart question.

| Input | Meaning |
|---|---|
| `'\ny\nm\nq\n'` | first run, accept all (not the BIOS item), back to the menu, quit |
| `'2\n\ny\n'` | toggle the theme |
| `'a\ny\nm\nq\n'` | re-apply what is on (includes the conversion, so a restart is pending) |
| `'q\n'` | just show the menu |
| `'1\n3\n5\n\ny\n'` | from all-off: theme only (with `--fremont` also add `6\n` to drop Steam Machine support) |
| `'1\n\ny\n'` | from a state where 1 is off: turn the conversion on |

**Know the starting ticks before choosing input.** When *everything* is off
(fresh snapshot, or after turning the last component off), the menu treats it
as a first run and pre-ticks **all** components, so `2` means "theme off,
rest on". Otherwise the ticks show what is on now. Unticking 1 also unticks 4,
and ticking 4 ticks 1 again, so `'1\n3\n4\n...'` ends with the conversion on.
When unsure, run `'q\n'` first and read the ticks.

`a` only re-applies components that are already on: it does not retry one that
failed. Re-applying the conversion also resets the autologin session to
gamescope, so set it back to plasma before the next reboot (below).

## Gamescope does not render in this VM

(Also after any re-apply that includes the conversion.)

No suitable Vulkan (venus is unstable with the host NVIDIA driver). After
enabling the conversion, before rebooting:

```bash
sudo /usr/lib/steamos/steam-set-session plasma.desktop
```

so autologin lands in Plasma. Stuck in a gamescope relogin loop: over SSH set
the session to plasma and `sudo systemctl restart display-manager` (or stop the
DM, set the session, start it).

## Checking component state

`scripts/vmstate.sh` prints:

- display manager, SDDM autologin file, plasmalogin `[Autologin]` section
- session sync bridge units (`sync-steamos-session.path`) and sudoers rule (`gamescope-session-switch`)
- Return to Gaming Mode shortcut `Exec=` line
- `steam-desktop-autostart` user unit; glyphs env file (`99-gamescope-steam-glyphs.conf`)
- LookAndFeelPackage, ColorScheme, GTK theme, font
- KDE Action Restrictions (`lock_screen`), kscreenlockerrc Autolock, Lock Session shortcut
- panel floating/thickness in plasmashellrc
- kickoff `primaryActions` / `systemFavorites` / `icon`
- leds-valve-dkms-git package, udev rule, `leds_valve` module, `/sys/class/leds/valve-leds*` count and owner (user must be able to write)
- steamos-manager package and whether it is active
- undo journals present, and duplicate keys (`cut -f1-3 journal | sort | uniq -d`)

`scripts/cmp.sh save` stores a baseline of the KDE/GTK configs in the guest
(`~/.cache/vm-baseline`, not `/tmp`); `scripts/cmp.sh` diffs against it.

After changing the theme, `cmp.sh` should show only spectacle's
`kglobalshortcutsrc` entries (from screenshots) and keys whose value equals
`~/.config/kdedefaults` (e.g. `ColorScheme=BreezeDark`, `widgetStyle=Breeze`):
KDE drops or writes those on its own.

## Testing the newest release

`scripts/vmwatch.sh --release '<input>'` downloads
`releases/latest/download/steamify.sh` in the guest and runs it with the piped
input (`WIZARD_KEEP_STDIN=1`; the bundle otherwise reattaches the terminal).
Release assets only exist from the version that added them: before v0.9.0 was
published, `steamify.sh` and the shortcut's `steam-gaming-settings.svg` gave
404 and the shortcut fell back to Steam's icon. Check a release with
`curl -sIL -o /dev/null -w '%{http_code}' .../releases/latest/download/<asset>`.

## Reboot checks

- Single user mode on: SDDM autologin without greeter: `pgrep sddm-greeter` empty, `plasmashell` running.
- Everything off: plasmalogin greeter shown: `loginctl list-sessions` shows a greeter session, no user `plasmashell`.

## Full test matrix

Reset to `ssh-ready`, start with `--fremont`, mount the repo, enable test
autologin, then (all passed last run; `scripts/vmstate.sh` after every step):

1. Fresh run turning everything on (`'\ny\nm\nq\n'`), set session to plasma, reboot:
   SDDM logs straight in, Vapor desktop, three desktop icons (Return to Gaming
   Mode, Steam, Steamify CachyOS with the gear icon), LEDs loaded (17 nodes).
2. Rerun: all shown on, "Everything is already the way you want it".
3. `a` re-apply: no duplicate journal entries.
4. Theme on: Steam Deck wallpaper, full-width 46px panel, `distributor-logo-steamdeck` launcher icon, `dark-lnf=com.valve.vapor.desktop` (Brightness & Color's Dark Mode toggle is on, hint "Switch to Breeze"); with single user on, kickoff keeps `primaryActions=3`. Theme off: CachyOS wallpaper, floating 30px panel, CachyOS launcher icon, BreezeDark colors (not light), `cachyos-vapor` removed, `cmp.sh` clean.
5. Single user off: switches to plasmalogin + sync bridge + sudoers; shortcut Exec uses `sudo -n`.
6. Single user on: back to SDDM.
7. Icons + Steam Machine support off: driver, udev rule, modules-load, steamos-manager removed; yay kept.
7b. DKMS: `vmstate.sh` shows `installed` for every kernel. Headers at boot:
   `sudo pacman -R --noconfirm linux-cachyos-lts-headers` (DKMS drops the LTS
   build), set the session to plasma, reboot, then `journalctl -b -u
   ensure-kernel-headers` shows the install and DKMS lists LTS again.
8. Conversion off: single user auto-unticked, plasmalogin `[Autologin]` back to CachyOS's `Session=plasma`, journals empty.
9. Remove the test autologin file, reboot: normal login screen.

## BIOS update item

Only shown with `--fremont`, and only tickable when the guest's BIOS version
differs from Valve's newest. Fake an older one with
`BIOS_VERSION=F7F0107 ./run.sh --fremont` (SMBIOS type 0; `vmreset.sh` passes
the environment through). fwupd correctly refuses the firmware in the VM
("not for this machine's hardware"), so walk the whole flow with
`WIZARD_BIOS_DRY_RUN=1` (skips only that check, never flashes). Scripted:
`printf '10\n\ny\ny\nUPDATE\nm\nq\nn\n' | WIZARD_BIOS_DRY_RUN=1 /mnt/steamify.sh`
(BIOS is item 10 with `--fremont`; the final `n` answers the restart question).

A successful dry run counts as staged, so `[m]`/`[r]` and the restart question
on `q` show up too; in dry-run mode "restart" only prints.

## Fake HDMI-CEC (vivid): `scripts/vmcec.sh`

The VM has no CEC hardware; the kernel's `vivid` test driver emulates it: a
virtual HDMI input (`/dev/cec0`, plays the TV via `cec-ctl`/`cec-follower`)
and output (`/dev/cec1`, the PC, where cecd runs). Needs the HDMI-CEC item on;
the Steam-settings checks need Steam Machine support (steamos-manager).

```bash
scripts/vmcec.sh              # all checks + a real suspend/resume (~5 min)
scripts/vmcec.sh --no-sleep   # without suspending the VM
scripts/vmcec.sh --sleep-only # only the suspend/resume check
scripts/vmwake.sh             # wake a sleeping VM (QMP socket from run.sh)
```

It prints PASS/FAIL/SKIP for: identity (address 1.0.0.0, name "Steam
Machine", Valve vendor ID), every TV remote key and the key it becomes, the
Steam settings over D-Bus (remote control, WakeTv, SuspendTv, SuspendDevice
and cecd's config), PC to TV (make active, wake, volume, audio status,
standby), TV standby putting the PC to sleep (blocked by an inhibitor), and
sleep/wake turning the TV off and on.

Gotchas it handles, learned the hard way:
- The cecd service (`-e`) grabs every CEC device, the fake TV too: the test
  uses a temporary drop-in (`~/.config/systemd/user/cecd.service.d/vmcec.conf`)
  with `-d /dev/cec1`, removed at the end.
- The TV's power button (KEY_POWER) and TV standby with SuspendDevice on
  really suspend the VM (Steam Machine support makes the power button sleep):
  block with `sudo systemd-inhibit --what=sleep:handle-power-key` (as user it's
  refused). If the VM sleeps anyway: `scripts/vmwake.sh` (the QEMU window's
  keyboard doesn't wake it; a VM started before run.sh had `-qmp` needs a hard restart).
- `rtcwake` skips logind, so cecd never sees the sleep: suspend with
  `systemctl suspend` and wake over QMP.
- `steamosctl get/set-hdmi-cec-suspend-tv|suspend-device` don't work
  (steamos-manager 26.4.1); Steam uses the D-Bus properties of
  `com.steampowered.SteamOSManager1.HdmiCec2`, and so does the test.
- The kernel answers "give OSD name" itself, even without cecd: it's no proof
  cecd runs. cecd logs "Putting TV in standby" only at `RUST_LOG=debug`.
- CecDevice1 methods take arguments (`VolumeUp y 0`, Daemon1 `Standby b true`).
- After the test (or a hard restart) CachyOS may put autologin back on
  gamescope: set the session to plasma and restart the display manager.

The menu item is 7 (8 = Steam Machine support, 9 = kernel pin, 10 = BIOS with `--fremont`).

## Steamify shortcut

Test a double-click with `systemd-run --user kioclient exec
~/Desktop/cachyos-gamescope-boot-wizard.desktop`. If Plasma opens the file in
Kate instead, it saw the file before it was executable. After the wizard the
window counts down 10 seconds and closes; after an error (e.g. 404) it waits
for Enter.

## Visual checks

`scripts/vmshot.sh [--clean] <out.png>` does the below. After a reboot, Steam's
sign-in window and CachyOS Hello cover the desktop: `--clean` shuts Steam down
(closing only `steamwebhelper` leaves a black window) and closes Hello and the
wizard's Konsole. Steam comes back at the next login. Starting `spectacle` straight
from SSH core-dumps; it has to run as a user unit (`systemd-run --user --wait`).

```bash
ssh -p 2222 -o BatchMode=yes theupriser@localhost bash -s << 'EOF'
export XDG_RUNTIME_DIR=/run/user/1000 WAYLAND_DISPLAY=wayland-0 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus
qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.activateLauncherMenu   # optional, toggles
sleep 1; systemd-run --user --wait -q spectacle -b -n -f -o /tmp/x.png
EOF
scp -P 2222 theupriser@localhost:/tmp/x.png /tmp/x.png    # then view it
```

The launcher call toggles; retake if the screenshot misses it. Apps started
directly over SSH lack the session's Qt platform theme and look light; start
them with `systemd-run --user <app>`.

## Pitfalls

- Broken mirror: `mirror5.krfoss.org` served a bad `.sig` ("Maximum file size
  exceeded"), failing the conversion's package install. `vmreset.sh` comments
  it out; by hand: `sudo sed -i '/krfoss/s/^Server/#Server/' /etc/pacman.d/*mirrorlist*`.
- The snapshot has no shellcheck; `vmreset.sh` installs it. Check the bundle
  like CI: `.github/tools/bundle.sh` on the host, then in the guest
  `cd /mnt && shellcheck -S warning -e SC2034,SC2154 dist/steamify.sh`.
- The host shell is zsh: `$var` holding several file names isn't split
  (`sed -i ... $files` gets one "name"); use `xargs`.
- Windows open in the snapshot (System Settings, CachyOS Hello) show stale
  data (e.g. a theme list from before `cachyos-vapor`) and cover screenshots;
  `vmreset.sh` closes them.

- The guest's `/tmp` is cleared on reboot; keep baselines elsewhere.
- The fake Fremont DMI makes leds-valve load 17 LED nodes, but there is no real hardware.
- Per-file shellcheck (`shellcheck -S warning -x steamify.sh lib/*.sh` in
  `/mnt`) shows SC2154/SC2034 cross-file false positives; the bundle check
  above is the one CI runs.
- This repo's `.gitignore` is an allowlist: it ignores everything and
  un-ignores only the tracked scripts/docs. Add any new tracked file to it
  explicitly, or git will silently ignore it.
