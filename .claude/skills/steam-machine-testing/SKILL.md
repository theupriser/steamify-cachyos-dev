---
name: steam-machine-testing
description: Use when testing or developing Steamify CachyOS (repo steamify-cachyos, steamify.sh) directly on the real Steam Machine (Valve Fremont running CachyOS) - either in a Claude Code session on the machine itself or over SSH - running the wizard with scripted menu input, checking each component's state, gaming mode, HDMI-CEC, LEDs, kernel pin, BIOS and reboot checks.
---

# Testing Steamify CachyOS on the real Steam Machine

This is the real-hardware twin of the `cachyos-vm-testing` skill. The big
difference: **there are no snapshots**. Every change is on the actual
machine, so undo what you turn on, never flash the BIOS without the user
saying so, and ask before anything that could leave it unbootable (kernel
pin, removing kernel headers, DKMS).

What the Steam Machine gives you that the VM can't: gaming mode that
actually renders (Steam's settings, HDMI-CEC section, refresh rates), real
LEDs, a real TV over HDMI-CEC, and the real BIOS version check.

## Keep everything in ~/projects

The machine is the user's own. Everything you put on it lives in
`~/projects` and nowhere else in the home folder: the repo copy
(`~/projects/steamify-cachyos`), the dev repo with the test VM
(`~/projects/steamify-cachyos-dev`), module builds, scratch checkouts
(`~/projects/<name>`). Temporary files go in `/tmp` and are removed again.
Never create folders like `~/steamify-test` or `~/s4mod`. What Steamify
itself installs (units, `~/.local/...`) is fine: that's the product. When
you're done, remove what you left in `~/projects` that isn't a repo.

## Test VM on the Steam Machine

The Mac can't run the VM (no KVM); the Steam Machine can (31 GB RAM, 12
threads, KVM). `qemu-desktop` and `edk2-ovmf` are installed; `run.sh` finds
Arch's OVMF in `/usr/share/edk2/x64`. Run it from
`~/projects/steamify-cachyos-dev` with
`REPO=~/projects/steamify-cachyos` (the synced branch) and follow the
`cachyos-vm-testing` skill, with `ssh steammachine` in front of its
commands where they run on the host.

## Two ways to work

**A. Claude Code on the Steam Machine itself** (preferred for development):
run commands directly, no SSH. Clone the repo there, e.g.
`~/projects/steamify-cachyos`, and run the wizard from it. Where this skill
says `sm bash -s << 'EOF'`, just run the body locally.

**B. From another machine over SSH.** Never guess the host: find the
candidates, then ask the user (next section). Once chosen, set per shell:

```bash
export SM_HOST=<chosen host> SM_USER=<chosen user>
sm() { ssh -o BatchMode=yes "$SM_USER@$SM_HOST" "$@"; }
```

### Finding the Steam Machine

Skip if the user already named a host, or `~/.ssh/config` has a
`Host steammachine` entry (use that). Otherwise scan the LAN for SSH hosts,
all read-only and quick:

```bash
# mDNS: hosts announcing SSH (macOS: dns-sd; Linux: avahi-browse)
if command -v dns-sd >/dev/null; then dns-sd -B _ssh._tcp local > /tmp/sm-mdns 2>&1 & p=$!; sleep 3; kill $p; awk 'NR>4{print $NF}' /tmp/sm-mdns | sort -u
elif command -v avahi-browse >/dev/null; then avahi-browse -rtp _ssh._tcp 2>/dev/null | awk -F';' '/^=/{print $7" "$8}' | sort -u; fi
# hosts with port 22 open on the local /24 (nmap if present, else nc; macOS has no `timeout`)
net=$( (ipconfig getifaddr en0 || ip -4 route get 1 | awk '{print $7;exit}') 2>/dev/null | cut -d. -f1-3)
if command -v nmap >/dev/null; then nmap -p22 --open -oG - "$net.0/24" | awk '/22\/open/{print $2" "$3}'
else for i in $(seq 1 254); do (nc -z -w1 -G1 "$net.$i" 22 2>/dev/null || nc -z -w1 "$net.$i" 22 2>/dev/null) && echo "$net.$i" & done; wait; fi
```

A CachyOS Steam Machine usually shows up by its hostname (e.g. `*.local`
with "steam", "fremont" or "cachyos" in it). Put the best matches first
and ask with AskUserQuestion: up to 3 candidates as options (label = host
name or IP, description = what was found), "Other" lets the user type one.
Ask the user name the same way (default: the local `$USER`).

Then check key login: `ssh -o BatchMode=yes -o ConnectTimeout=5 "$SM_USER@$SM_HOST" true`.
If it fails, tell the user to run `! ssh-copy-id $SM_USER@$SM_HOST` (it needs
their password; sshd must be on: `sudo systemctl enable --now sshd` on the
machine). Offer to add a `Host steammachine` entry to `~/.ssh/config` so the
next session skips the scan.

The dev repo's `scripts/*.sh` (vmstate, vmrun, cmp, vmshot, vmcec) all go
through `vm_ssh`, so they also work against the Steam Machine with
`VM_HOST=$SM_HOST VM_PORT=22 VM_USER=$SM_USER scripts/vmstate.sh`.
Don't use `vmreset.sh`, `vmwake.sh` or `run.sh`: those are QEMU-only.
`vmcec.sh` needs the `vivid` fake TV; on real hardware test CEC with the
real TV (below) instead.

The user's shell may be fish: pass remote commands as bash heredocs, never
as inline strings containing `$`.

Keep the repo in sync with the working copy on the machine (A: `git pull`;
B: `rsync -a --exclude .git ./ "$SM_USER@$SM_HOST:~/projects/steamify-cachyos/"`).
Below, `$REPO` is that checkout on the Steam Machine.

## Visible terminal (let the user watch)

When the user is watching the Steam Machine's screen (in person or through
Moonlight/Sunshine), run commands in a Konsole window on its desktop
instead of hidden over SSH: they see every command and its output. A tmux
session makes that window scriptable.

Set it up (Plasma desktop running; `sudo pacman -S --needed tmux` once):

```bash
sm bash -s << 'EOF'
export XDG_RUNTIME_DIR=/run/user/$(id -u) WAYLAND_DISPLAY=wayland-0 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id -u)/bus
tmux kill-session -t claude 2>/dev/null
# Plain bash, not the user's login shell: fish rejects bash syntax ($?) and
# swallows Enter keys sent while it's still drawing its prompt.
tmux new-session -d -s claude -x 200 -y 50 'bash --norc --noprofile -i'; sleep 1
tmux send-keys -t claude "PS1='[claude] \\w\\$ '; clear" Enter
systemd-run --user -q --setenv=XDG_CURRENT_DESKTOP=KDE konsole --separate -e tmux attach -t claude
EOF
```

Run a command and wait for it: end it with a marker, then poll the pane.

```bash
sm bash -s << 'EOF'
tmux send-keys -t claude 'clear; sudo pacman -S --needed --noconfirm foo; echo "== EXIT $?"' Enter
for i in $(seq 200); do tmux capture-pane -p -t claude -S -400 | grep -q '^== EXIT' && break; sleep 3; done
tmux capture-pane -p -t claude -S -400 | grep -v '^\s*$' | tail -30
EOF
```

- `clear` first, or an old marker still in the pane ends the wait at
  once; with several runs, count the markers (`grep -c`).
- Longer scripts: write them to `/tmp/<name>.sh` in the heredoc, then
  `tmux send-keys -t claude 'clear; bash /tmp/<name>.sh' Enter`.
- For runs of 10+ minutes, poll from a `run_in_background` Bash call and
  report when it finishes.
- A reboot ends the session (and the window): after every reboot, set it
  up again before sending anything, or `send-keys` fails
  (`error connecting to /tmp/tmux-1000/default`) while a wait loop spins.
- Watching remotely: Sunshine on the machine (`cachyos` repo, user unit
  `app-dev.lizardbyte.app.Sunshine.service`, `sunshine --creds` for the web
  UI, ufw: TCP 47984-47990 and 48010, UDP 47998-48010 from the LAN only) and
  Moonlight on the user's computer. Pairing: the user reads Moonlight's PIN,
  then `curl -k -u admin:<pw> https://<host>:47990/api/pin` (GET lists the
  pending `pairing_id`) and POST `{"pin","name","pairing_id"}` to it. The
  "Desktop" app streams any session; avoid "Low Res Desktop" (xrandr).

## Menu

1. SteamOS conversion (boot into gaming mode via autologin, Return to Gaming Mode shortcut, Steam desktop autostart)
2. └ Boot into: gamescope / desktop (sub-option of 1)
3. SteamOS theme (`cachyos-vapor` + Vapor global theme; needs a running Plasma session)
4. Steam Deck/Machine icons (`STEAM_GAMEPADUI_ARGS -steamos3`)
5. Single user mode (SDDM, no lock screen/user switching/log out, Valve's empty KDE wallet)
6. Steamify shortcut
7. HDMI-CEC (pre-ticked on a first run on Fremont)
8. Steam Machine support (leds-valve-dkms-git, `ensure-kernel-headers.service`, udev rule, steamos-manager, powerdevilrc)
9. └ Power-off fix (DKMS `steamify-fremont-poweroff`; ticked with 8, opt-out)
10. └ Update BIOS (opt-in, never pre-ticked; tickable only when Valve has a newer BIOS)

Since 2.2.0 "Pin the kernel" and "HDMI refresh boost" are only shown while
something of them is left, unticked, so a normal run removes them. The menu
marks components a normal run will update with "(update)" (feature versions
in `~/.local/state/cachyos-gamescope-boot/features.state`; set an entry to an
older version, e.g. `machine=2.1.0`, to test the update flow).

Numbers shift when a parent is unticked (its sub-option is hidden), so read
the ticks with `'q\n'` first. Undo journals: `~/.local/state/cachyos-gamescope-boot/`.

## Running the wizard

Visible, in the desktop session (best when the user is watching the screen):

```bash
sm bash -s << 'EOF'
export XDG_RUNTIME_DIR=/run/user/$(id -u) WAYLAND_DISPLAY=wayland-0 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id -u)/bus
printf 'q\n' | "$HOME/projects/steamify-cachyos/steamify.sh" 2>&1 | tee /tmp/wizard.log
EOF
```

Newest release instead of the checkout:
`curl -fsSL https://github.com/<owner>/steamify-cachyos/releases/latest/download/steamify.sh -o /tmp/steamify.sh`
then `printf '<input>' | WIZARD_KEEP_STDIN=1 bash /tmp/steamify.sh`.

Menu input: a number toggles, an empty line continues, `a` re-applies what is
on, `q` quits; `y` answers "Go ahead?". After a run: Enter (menu) or
`[m]`/`[r]` when a restart is needed. `q` with a restart pending asks
"Restart now? [Y/n]" (default **yes** - on real hardware that really
reboots). End scripted input right after the last `q`, or with `n`.

| Input | Meaning |
|---|---|
| `'q\n'` | just show the menu (always do this first) |
| `'\ny\nm\nq\nn\n'` | first run, accept the pre-ticked items, don't reboot |
| `'3\n\ny\n'` | toggle the theme (while 1 is ticked) |
| `'7\n\ny\nm\nq\nn\n'` | toggle HDMI-CEC (while 1 is ticked) |
| `'a\ny\nm\nq\nn\n'` | re-apply what is on |

When everything is off the menu treats it as a first run and pre-ticks.
`a` doesn't retry a component that failed.

Long runs (packages, yay, DKMS) take 10+ minutes: use `run_in_background`
and wait with an until-loop.

## Checking state

`scripts/vmstate.sh` (mode B with the env above), or in mode A run the body
of its heredoc locally: display manager and autologin, session sync bridge,
shortcut, Steam autostart, theme keys, lock restrictions, panel, kickoff,
LED driver/DKMS/`/sys/class/leds/valve-leds*` owner, steamos-manager,
journals and duplicate journal keys. `scripts/cmp.sh save` / `cmp.sh` diff
the KDE configs.

## Real-hardware checks (what the VM can't do)

- **Gaming mode**: reboot with Boot into gamescope; Steam starts in Big
  Picture/gamepad UI, Steam Deck icons with item 4, "Switch to Desktop"
  lands in Plasma and "Return to Gaming Mode" goes back.
- **HDMI-CEC with the real TV**: `cec-ctl -d /dev/cec0 --playback -S`
  (topology), TV remote keys reach Steam, Steam's settings > Display >
  HDMI-CEC toggles (remote, WakeTv, SuspendTv, SuspendDevice) change
  `com.steampowered.SteamOSManager1.HdmiCec2` properties, sleep turns the TV
  off, wake turns it on, TV standby suspends the machine when SuspendDevice is on.
  `steamosctl get/set-hdmi-cec-*` don't work (steamos-manager 26.4.1).
- **LEDs**: `leds_valve` loaded, `/sys/class/leds/valve-leds*` owned by the
  user, writing `brightness` visibly changes them.
- **Power-off fix**: `dmesg | grep 'GPIO 18'` shows the pin's register and
  whether the S4/S5 wake bit is set (recent kernels: set, "cleared at
  power-off"); `/sys/kernel/debug/gpio` has an S4/S5 column. The real test
  needs the user at the machine: shut down and check it stays off (30 s+),
  2-3 times; control run: `sudo rmmod steamify_fremont_poweroff`, shut down,
  it should boot again right away. Do this for every new major kernel.
  Install a test kernel next to the current one under another package name
  (e.g. `linux-cachyos-bore`) so the user can pick the old one in Limine.
- **BIOS**: item 10 is tickable only if Valve has a newer BIOS than
  `cat /sys/class/dmi/id/bios_version`. Walk the flow with
  `WIZARD_BIOS_DRY_RUN=1` (never flashes). **Never run a real flash unless
  the user explicitly asks in this session**, and only on AC power.

## Reboot checks

The session reboots; in mode A the Claude session ends. Tell the user
before rebooting and what to check afterwards.

- Single user mode on: SDDM autologin without greeter (`pgrep sddm-greeter` empty).
- Everything off: plasmalogin greeter shown.
- Stuck in a gamescope relogin loop: over SSH
  `sudo /usr/lib/steamos/steam-set-session plasma.desktop && sudo systemctl restart display-manager`.

## Restoring the machine

No snapshots, so before a test run note the starting state (`vmstate.sh`,
`cmp.sh save` into `~/.cache/vm-baseline`) and afterwards turn back off
what the test turned on through the menu (the undo journals do the rest).
Check `cmp.sh` is clean except KDE's own default-valued keys.

## Pitfalls

- To see the plan, answer "n" at "Go ahead?" (`'\nn\nq\n'`). Piping a "y"
  applies it, on real hardware; never wrap a run that may call pacman in
  `timeout`: killing pacman after its transaction but before its hooks
  leaves a stale boot entry and `db.lck` (fix: remove the lock, reinstall the
  same packages so the hooks run).
- The user's login shell is fish: inline `ssh host '...'` commands with `$`
  or `\$` break; always send bash heredocs (`sm bash -s << 'EOF'`).
- pacman 404 on a `.sig`: the local sync database is stale (the mirror moved
  on to a newer version). A full `pacman -Syu` fixes it; don't fetch
  signatures by hand.
- CachyOS's `linux-cachyos` is clang-built, `-bore` GCC-built: when building
  a module by hand, pass `LLVM=1` only for clang kernels (DKMS picks itself).

- `pkill -f '<pattern>'` also matches the shell running it; kill by PID.
- Apps started straight from SSH lack the session's Qt theme or core-dump
  (spectacle): start them with `systemd-run --user`.
- Screenshots: `systemd-run --user --wait -q spectacle -b -n -f -o /tmp/x.png`
  with the session env above; in gaming mode spectacle can't see gamescope,
  use Steam's own screenshot (Steam + R1) instead.
- `makepkg -i` runs `sudo -k` and always asks for the password again; the
  real machine has no NOPASSWD rule, so scripted runs that need sudo stop
  at the prompt. Run those in a terminal the user can type into, or have the
  user add a temporary sudoers rule and remove it afterwards.
- Check the bundle like CI: `.github/tools/bundle.sh`, then
  `shellcheck -S warning -e SC2034,SC2154 dist/steamify.sh`.
