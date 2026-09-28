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
7. HDMI-CEC (any PC; pre-ticked on a first run only on Fremont: Valve's cecd/cec-audio-control/inputattach-cec-units from the holo repo, the steam-launcher drop-in that overrides `STEAM_ENABLE_CEC=0`; see "Fake HDMI-CEC")
8. Steam Machine support (only on DMI Valve/Fremont: leds-valve-dkms-git built for every kernel via `/etc/dkms/leds-valve-dkms.conf`, `ensure-kernel-headers.service`, udev rule, steamos-manager, powerdevilrc)
9. └ Power-off fix (sub-option of 8, ticked along with it, opt-out: DKMS module `steamify-fremont-poweroff` for every kernel; in the VM it loads but finds no real GPIO wake bit to clear)
10. └ Update BIOS (only on Fremont, an opt-in action, never pre-ticked; tickable only when Valve has a newer BIOS)

Since 2.2.0 "Pin the kernel" and "HDMI refresh boost" are only shown while
something of them is left, unticked, so a normal run removes them. The menu
marks components a normal run will update with "(update)" (feature versions
in `~/.local/state/cachyos-gamescope-boot/features.state`; set an entry to an
older version, e.g. `machine=2.1.0`, to test the update flow in the menu and
the app).

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

## Always let the user watch

The user follows the tests in the VM's window (on the Steam Machine, over
Moonlight). **Every run is visible**: run the wizard and every other test
command in the tmux-backed Konsole on the VM's desktop ("Visible terminal"
below), never hidden over SSH. When a run was started hidden anyway, open a
Konsole that follows its log (`tail -n +1 -f <log>`) right away. **Show the
app too**: start it on the VM's desktop (`systemd-run --user
/mnt/ui/steamify-ui`) for the screens you test, and screenshot it.

## The VM on the Steam Machine

The Mac has no KVM, so the VM runs on the Steam Machine
(`~/projects/steamify-cachyos-dev`, `REPO=~/projects/steamify-cachyos`; see
the steam-machine-testing skill). From the Mac:

- Connect with agent forwarding (`ssh -A steammachine`), then
  `ssh -p 2222 -o UserKnownHostsFile=~/projects/steamify-cachyos-dev/known_hosts theupriser@localhost`.
  The Steam Machine has no key of its own: `share/host-keys.pub` holds the
  Mac's key (`ssh-add -L`), and the VM's host key stays in `~/projects`, not
  `~/.ssh`.
- Inner `ssh` in a `bash -s` heredoc reads the rest of the heredoc as its
  stdin: use `ssh -n` for single commands, or the rest of the script silently
  never runs.
- Start the VM as a user unit so it survives the SSH session:
  `systemd-run --user --collect -u steamify-vm --working-directory=$PWD --setenv=REPO=$HOME/projects/steamify-cachyos ./run.sh --fremont`.
- A fresh install has no `/media`: the guest setup is
  `sudo mkdir -p /media && sudo mount -t 9p -o trans=virtio,version=9p2000.L vmtools /media && /media/guest-ssh-setup.sh`.

## No VM yet

Create one with `scripts/vminstall.sh` (the vm-install skill): unattended,
ends with the snapshots `clean` and `ssh-ready`. Pass its `VM_DIR` to every
script. Login by hand: your host username, password `steamify`.

## Test plan

`TESTPLAN.md` (repo root) lists what to test per release (regression,
features, Steam Machine only) and logs every run. Follow it, add a section
for every new feature, and add a line to its results log after each run.

## Start of every session: update the snapshot first

A snapshot's package databases age quickly: the mirrors drop the versions it
knows (404s, then "signature is invalid" on partial downloads) and the
conversion's package install fails, which looks like a wizard bug. So once
per session, before any test, bring `ssh-ready` up to date and overwrite it
(visibly, in a Konsole on the VM's desktop):

```bash
scripts/vmreset.sh --fremont
# in the guest (Konsole): keyrings first, then everything else
sudo pacman -Sy --noconfirm archlinux-keyring cachyos-keyring
sudo pacman -Su --noconfirm --needed tmux shellcheck
sudo pacman -Scc --noconfirm
sudo systemctl poweroff
# on the host, in the VM dir, once QEMU is gone:
qemu-img snapshot -d ssh-ready disk.qcow2
qemu-img snapshot -c ssh-ready disk.qcow2 && cp vars.fd vars.ssh-ready.fd
```

Keep `/etc/plasmalogin.conf.d/00-test-autologin.conf` in the snapshot: the
VM then logs in at boot. After a plasmalogin update, restarting it from a
booted greeter fails (`HELPER_TTY_ERROR`, start-limit-hit), so `vmreset.sh`
only restarts it when Plasma isn't up yet.

## Quick start (the usual loop)

```bash
scripts/vmreset.sh --fremont        # restore ssh-ready, boot, mount repo, autologin, wait for Plasma
                                    # (also skips the broken krfoss mirror, installs shellcheck)
scripts/cmp.sh save                 # baseline of the KDE configs
scripts/vmwatch.sh 'q\n' "Menu"   # wizard in a visible Konsole in the VM (read the ticks first)
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
./run.sh --fremont > /tmp/vm.log 2>&1 &     # flags: [install] [--fremont] [--nvidia] [--vulkan [--amd]]
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
passwordless sudo, test autologin; brought up to date at the start of each
session, see above). Reset to `ssh-ready` before each full test run.

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

## Visible terminal (let the user watch)

When the user watches the VM's window, run commands in a Konsole window on
the guest's desktop instead of hidden over SSH: they see every command and
its output. A tmux session makes that window scriptable (needs a Plasma
session; `sudo pacman -S --needed tmux` once, or put it in the snapshot).

```bash
ssh -p 2222 -o BatchMode=yes theupriser@localhost bash -s << 'EOF'
export XDG_RUNTIME_DIR=/run/user/1000 WAYLAND_DISPLAY=wayland-0 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus
tmux kill-session -t claude 2>/dev/null
# Plain bash, not fish: fish rejects bash syntax ($?) and swallows Enter
# keys sent while it's still drawing its prompt.
tmux new-session -d -s claude -x 200 -y 50 'bash --norc --noprofile -i'; sleep 1
tmux send-keys -t claude "PS1='[claude] \\w\\$ '; clear" Enter
systemd-run --user -q --setenv=XDG_CURRENT_DESKTOP=KDE konsole --separate -e tmux attach -t claude
EOF
```

Run a command and wait for it: end it with a marker, then poll the pane.

```bash
ssh -p 2222 -o BatchMode=yes theupriser@localhost bash -s << 'EOF'
tmux send-keys -t claude "clear; cd /mnt; printf 'q\\n' | ./steamify.sh; echo '== EXIT'" Enter
for i in $(seq 200); do tmux capture-pane -p -t claude -S -400 | grep -q '^== EXIT' && break; sleep 3; done
tmux capture-pane -p -t claude -S -400 | grep -v '^\s*$' | tail -30
EOF
```

- `clear` first, or an old marker still in the pane ends the wait at once;
  with several runs, count the markers (`grep -c`).
- Longer scripts: write them to a file in the heredoc (not `/tmp` if a
  reboot comes in between), then `tmux send-keys -t claude 'clear; bash <file>' Enter`.
- For long runs (packages, yay, DKMS), poll from a `run_in_background` Bash
  call and report when it finishes.
- A reboot or snapshot restore ends the session and the window: set it up
  again before sending anything, or `send-keys` fails
  (`error connecting to /tmp/tmux-1000/default`) while a wait loop spins.
- `vmshot.sh --clean` closes Konsole windows, including this one.

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
| `'\ny\nm\nq\n'` | first run, accept what's pre-ticked (not Boot into desktop, not BIOS; HDMI-CEC only on Fremont), back to the menu, quit |
| `'3\n\ny\n'` | toggle the theme (while 1 is ticked) |
| `'7\n\ny\nm\nq\nn\n'` | toggle HDMI-CEC (while 1 is ticked) |
| `'a\ny\nm\nq\n'` | re-apply what is on (includes the conversion, so a restart is pending) |
| `'q\n'` | just show the menu |
| `'1\n\ny\n'` | from a state where 1 is off: turn the conversion on |

**Know the starting ticks before choosing input.** When *everything* is off
(fresh snapshot, or after turning the last component off), the menu treats it
as a first run and pre-ticks the components (not Boot into desktop, BIOS, or
HDMI-CEC off Fremont). Otherwise the ticks show what is on now. Unticking 1
also unticks single user mode (5) and **hides** the Boot into row (2), so
every later number moves up one; the same for Steam Machine support (8) and
its kernel pin row (9). Ticking 5 ticks 1 again. The numbers apply to the
menu as it is when you type them, one line at a time. When unsure, run
`'q\n'` first and read the ticks.

`a` only re-applies components that are already on: it does not retry one that
failed. Re-applying the conversion also resets the autologin session to
gamescope, so set it back to plasma before the next reboot (below).

## Gamescope does not render in this VM


Everything was tried (2026-09-25); don't spend time on it again:
- virgl (default): no Vulkan, black.
- `--vulkan --amd` (venus on the host 780M, RADV): gamescope and Steam run,
  but virtio-gpu rejects every framebuffer gamescope makes ("Cannot import FB
  to DRM ... not supported for scan-out", AR24 and XR24, also with
  `--force-composition --disable-layers`): black. KWin crashes on venus
  ("Illegal command buffer"), so Plasma freezes too.
- nested gamescope with lavapipe (`vulkan-swrast`): refuses to start, lavapipe
  lacks VK_KHR_present_id/present_wait.
- Other hypervisors (VirtualBox, VMware) have no Vulkan at all.
Check gaming mode (Steam's settings, HDMI-CEC section, refresh rates) on the
real Steam Machine. The VM covers everything else.

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
   Mode, Steam, Steamify CachyOS with the gear icon), LEDs loaded (17 nodes),
   `uname -r` 7.1.6-1-cachyos and `pacman -Qu` shows linux-cachyos `[ignored]`,
   `~/.local/share/kwalletd/kdewallet.kwl.bak-steamify` next to Valve's empty wallet,
   `steamos-manager-configure-cecd` enabled and `~/.config/cecd/config.d/00-steamos-manager.toml` written.
2. Rerun: all shown on, "Everything is already the way you want it".
3. `a` re-apply: no duplicate journal entries.
4. Theme on: Steam Deck wallpaper, full-width 46px panel, `distributor-logo-steamdeck` launcher icon, `dark-lnf=com.valve.vapor.desktop` (Brightness & Color's Dark Mode toggle is on, hint "Switch to Breeze"); with single user on, kickoff keeps `primaryActions=3`. Theme off: CachyOS wallpaper, floating 30px panel, CachyOS launcher icon, BreezeDark colors (not light), `cachyos-vapor` removed, `cmp.sh` clean.
5. Single user off: switches to plasmalogin + sync bridge + sudoers; shortcut Exec uses `sudo -n`.
6. Single user on: back to SDDM.
7. Icons + Steam Machine support off: driver, udev rule, modules-load, steamos-manager removed; yay kept;
   kernel pin removed (`IgnorePkg` empty, `pacman -Syu` back to the current kernel), files kept in
   `/var/cache/steamify/kernel`. On again (even with the CachyOS servers blocked in
   `/etc/hosts`): installs 7.1.6 from that directory; DKMS builds the LED driver once per kernel.
7c. HDMI-CEC: load vivid, then `scripts/vmcec.sh` (all PASS), off/on via the menu.
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

- To see the plan without applying it, answer "n" at "Go ahead?"
  (`'\nn\nq\n'`); a "y" applies it. Never wrap a run that may call pacman in
  `timeout`: killing pacman after its transaction but before its hooks leaves
  a stale boot entry and `db.lck` (restore the snapshot, or remove the lock
  and reinstall the same packages so the hooks run).

- After a reboot or hard restart the autologin may be back on gamescope
  (black screen): `sudo /usr/lib/steamos/steam-set-session plasma.desktop &&
  sudo systemctl restart display-manager`.
- `vmreset.sh` sometimes stops at "Plasma did not start" (the greeter stays up
  although the test autologin file is there): restart the display manager.
- `pkill -f '<pattern>'` from the host shell also matches the command running
  it and kills it (exit 144): match something narrower, or kill by PID.
- Counting sudo password prompts (the VM has NOPASSWD): move
  `/etc/sudoers.d/99-test-vm` aside, give the user a password, run the wizard
  in a Python `pty` that answers `[sudo] password` and logs each prompt, then
  put the file back. `makepkg -i` runs `sudo -k` and always asks again.

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
