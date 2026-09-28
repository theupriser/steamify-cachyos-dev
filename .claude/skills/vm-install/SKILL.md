---
name: vm-install
description: Use when there is no Steamify test VM yet, the VM should be reinstalled from scratch, or an ISO (CachyOS, later the Steamify CachyOS ISO) should be installed unattended into a VM - scripts/vminstall.sh installs it without any manual step and leaves the snapshots clean and ssh-ready.
---

# Installing the test VM unattended

`scripts/vminstall.sh` turns an ISO into a ready test VM, no clicking:

```bash
VM_DIR=~/vms/steamify-vm scripts/vminstall.sh --fremont     # run.sh flags pass through
VM_DIR=~/vms/iso-vm scripts/vminstall.sh --iso ~/Downloads/steamify-cachyos-<date>-x86_64.iso
```

Result in `$VM_DIR`: `disk.qcow2` with the snapshots `clean` (just
installed) and `ssh-ready` (booted once, SSH/sudo/Plasma checked), their
`vars.*.fd`, `run.sh` (this repo's), `vm-user`, `ssh-key`, `repo-path`,
`known_hosts`, `install.log`. Every other script (`vmreset.sh`, `vmwatch.sh`,
...) reads the user, key and repo from there: pass the same `VM_DIR`.

## What gets installed

CachyOS with the ISO's own headless installer (`cachyos-installer`,
`"headless_mode": true`): KDE Plasma, plasma-login-manager, btrfs with the
default subvolumes, Limine, `linux-cachyos` + `linux-cachyos-lts`, fish.
Then `share/vminstall-post.sh` in the new system: hostname `steamify-vm`,
sshd with the chosen key, passwordless sudo, the test autologin into Plasma
(`/etc/plasmalogin.conf.d/00-test-autologin.conf`), `en_US.UTF-8`, the host's
timezone, tmux + shellcheck, Limine `default_entry: 2` (the installer's
config points at the folder, so the first boot would wait in the menu).

## Login (by hand)

- User: your host username (`id -un`), or `VM_USER=...`.
- Password: **`steamify`** (user and root), or `VM_PASSWORD=...`.
- SSH: `~/.ssh/steamify-vm_ed25519`. Made once, on the first install (the
  script asks: that new key, or one of your own `~/.ssh/*.pub`), then always
  used. An existing key is never overwritten. The VM's host key is kept in
  `$VM_DIR/known_hosts`, never in `~/.ssh/known_hosts`.

## How it works

1. The ISO's kernel and initramfs are copied out (`udisksctl loop-setup`, no
   root) and booted directly (`VM_KERNEL`/`VM_INITRD`/`VM_APPEND` in
   `run.sh`) with `systemd.run=` (+ `systemd.wants=kernel-command-line.service`,
   or the unit is only generated) running `curl http://10.0.2.2:<port>/vminstall-live.sh | bash` as root.
2. `scripts/vminstall-server.py` serves the live script, `settings.json`,
   `vminstall.env` and the post script on 127.0.0.1; the guest reaches the
   host at 10.0.2.2 (QEMU user networking, any host network;
   `VM_HOST_IP` for a bridged setup). The live system PUTs its log
   (`install-www/install.log`, every 20 s) and the status back.
3. The live desktop shows a Konsole following the install log; the serial
   console is logged to `$VM_DIR/serial.log`, and root logs in there
   without a password over `$VM_DIR/serial.log.sock` (for debugging).
4. After `== ok` the VM powers off, `clean` is taken, it boots once for the
   checks, powers off, `ssh-ready` is taken.

Takes 15-30 minutes (mirrors, packages). Run it with `run_in_background`
and wait with an until-loop on the log, e.g.
`until grep -qaE '^== (ok|failed)' $VM_DIR/install-www/install.log; do sleep 20; done`.

## Gotchas

- Refuses an existing `disk.qcow2` without `--force` (asks YES), and a
  running VM (port 2222).
- Never edit `vminstall.sh` while it runs: bash reads it as it goes.
- Don't match your own wait loop with `pgrep -f`/`pkill -f` on a pattern that
  is part of that loop's command line.
- Mirror 404s during the install are normal for an older ISO (pacman moves
  on); `fatal library error, lookup self` in the chroot is harmless.
- QMP screenshots don't work (virgl, "no surface"): watch the window, the
  serial log, or the install log.

## The Steamify CachyOS ISO (later)

`--iso <steamify iso>` installs it the same way if it's archiso-based with
`cachyos-installer`. The headless installer doesn't run Calamares, so the
ISO's Steamify step (`steamify-install`) doesn't run by itself: run it in the
live script after the install (`/usr/local/bin/steamify-install /mnt
$VM_USER <options>`) when testing the ISO, and check
`/var/log/steamify-install.log` in the installed system.
