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
- Never edit a script in place while it runs (bash reads it as it goes; Python `open(p,"w")` and editors that rewrite do this). `sed -i` or writing a copy and `mv` swaps the file: the running one keeps its old copy.
- Don't match your own wait loop with `pgrep -f`/`pkill -f` on a pattern that
  is part of that loop's command line.
- Mirror 404s during the install are normal for an older ISO (pacman moves
  on); `fatal library error, lookup self` in the chroot is harmless.
- QMP screenshots don't work (virgl, "no surface"): watch the window, the
  serial log, or the install log.
- `pkill -f`/`pgrep -f` with a pattern that also appears in your own command
  line kills or matches your own shell (exit 144). Use `[q]emu` bracket
  patterns, or kill by PID from `ps -eo pid,args`, in a separate command.
- A wait loop that runs `pgrep -f "x"` over ssh matches its own ssh command:
  write `"[x]"`. And `systemctl --wait start` on a unit that already
  finished waits for ever; poll `systemctl is-active` instead.
- The live script must not wait for `systemctl is-system-running --wait`: it
  is itself the running `kernel-command-line.service` job (deadlock). It waits
  for `pacman-init.service` to be active instead (else "no secret key
  available to sign with").
- Only one VM at a time (port 2222); a second `vminstall.sh` refuses while
  qemu runs. Run several installs one after the other from a script, and
  give `--force` runs a terminal or delete `disk.qcow2` first (the YES
  prompt reads /dev/tty).
- The guest's login shell is fish: send bash through stdin
  (`ssh ... 'bash -s' < script.sh`), not loops on the command line.
- `/boot` is root-only: use `sudo` for `ls`/`cat` there, or checks report
  "no entries" for nothing.
- `ssh` "timed out during banner exchange" only means QEMU accepted the
  forwarded port: the guest's sshd isn't answering (still booting, waiting in
  a boot menu, or a firewall). It says nothing more.
- Never run `systemctl reboot --firmware-setup --dry-run` to "check": it
  still sets the EFI flag and the next boot lands in the UEFI setup menu.
  `bootctl status` shows `Boot into FW: supported` normally, `active` = set.

## The Steamify CachyOS ISO

`--iso <steamify iso>` (archiso with `cachyos-installer`). The headless
installer doesn't run Calamares, so `vminstall-live.sh` runs the ISO's
`steamify-install /mnt $VM_USER "$VM_STEAMIFY"` itself after the install
(empty `VM_STEAMIFY` = the Steamify page's default, everything on; ids to
narrow; `skip` = plain CachyOS) and fails the install if its log doesn't end
`exit: 0`. The log ends up in `/var/log/steamify-install.log`. The post script
keeps Steamify's gaming-mode login (SDDM,
`/etc/sddm.conf.d/10-gamescope-autologin.conf`) instead of forcing the Plasma
autologin, and the first-boot check then wants the display manager, not
plasmashell (gamescope doesn't render in the VM: a black window is normal).

## Other options

- `VM_BOOTLOADER=limine|systemd-boot|grub` (default limine) goes into the
  installer's settings. Use one `VM_DIR` per loader (`~/vms/bl-grub`, ...).
  cachyos-installer leaves systemd-boot with `#timeout 3` and no default (it
  waits in the menu for ever): the post script writes `timeout 3` and
  `default linux-cachyos.conf`, like it sets Limine's `default_entry`.
- The installer enables **ufw**, which drops the host's ssh
  (`[UFW BLOCK] DPT=22` in the kernel log): the post script runs
  `ufw allow 22/tcp`.
- `VM_CACHE=<dir>` (default `~/vms/pkg-cache`, empty = off) is a host package
  cache shared as 9p tag `cache`, bound over pacman's cache in the live system
  and in the new one (Steamify's packages): the first install fills it.

## The whole automated test: `scripts/vmtest.sh`

`scripts/vmtest.sh [--install] [--window] [--screen] [boot | <loader>... | <suite>...]`: no argument runs
everything: the boot loader test (below) and every suite in `share/vmtest/` (`cli`, `menu`, `hw`, `installer`,
`toggles`: the TESTPLAN.md rows that need no person, run by `scripts/vmsuite.sh` on the plain VM
`~/vms/steamify-vm`, each block from a fresh `ssh-ready`). `--screen` runs it in a detached `screen`
session (`screen -r vmtest`); output goes to `~/vms/test.log` (one shared Konsole follows it when headless
on a desktop), the summary to `~/vms/last-test.txt`, exit status = failed checks. Adding a check: a block file
in `share/vmtest/<suite>/NN-name.sh` (guest side, prelude helpers `pass/fail/skip/info/sf/is/expect_on`) or
`NN-name.host.sh` (host side, for reboots and host scripts); `# env: VAR=x` in a block sets it for the VM
start; `ONLY=<prefix> scripts/vmsuite.sh <suite>` runs one block. Rows that need a person (U1-U9, R2.2,
H-Real) are printed as SKIP at the end. Pitfalls met while building it: atomic file swaps (`os.replace`)
lose the executable bit (`chmod --reference` or call scripts with `bash`); a suite block that reboots must
be a `.host.sh` block; ssh has no Plasma session, the prelude exports one; a one-off network failure can fail
an install step (LED driver from the AUR), rerun the block before suspecting Steamify.

Gotchas found on 2026-09-29: never ssh to a VM with its `VM_DIR` settings while it installs (a leftover loop, also
one started from a laptop command that was stopped, saves the *live ISO's* host key in `$VM_DIR/known_hosts` and
the install then hangs at its first-boot ssh check: `ssh-keygen -R "[localhost]:<port>" -f $VM_DIR/known_hosts`);
`vminstall.sh` now never uses root as the guest user (WSL runs as root: `theupriser`), takes the ISO's loop
device under a lock (parallel installs collided), tolerates the poweroff dropping ssh, waits only for its own
qemu and stops at once when the live system reports `== failed: ...`. A failed install used to look like
"still installing" for 90 minutes: `vmprogress.sh` shows `INSTALL FAILED: <why>`.

Following a run for the user (a table per VM with a bar and a total, only on a change; their terminal and
the VM's screen): the `progress-report` skill, with `scripts/vmprogress.sh` as the monitor.

## Testing a boot loader: `scripts/vmtest.sh boot`

Run this instead of doing the steps below by hand: `scripts/vmtest.sh [--install] [--window] [loader...]`
(default: every loader the ISO advertises, read from `calamares-online.sh`; it fails when an advertised
loader has no test). One VM per loader in `~/vms/bl-<loader>` (`--install` builds them from the newest
Steamify ISO, ~8 min each, ~3 min per test), headless with a Konsole on the logs (`--window` shows the VMs),
one summary line per loader, `~/vms/bl-<loader>.test.log`, exit status = failed checks. Checks live in
`share/bootloader-test/*.sh` (one PASS/FAIL line each); the driver is `scripts/vmbootloadertest.sh`.
Last result (2026-09-29, ISO with Steamify 2.9.1): Limine 43, systemd-boot 42, GRUB 42 checks, 0 failed.
The boot entry check (B1, `boot-check.sh`, after every reboot): the system booted through the loader's **own**
EFI entry (`BootCurrent`, not `auto_created_boot_option`, a real partition GUID not `HD(0,GPT,0000...)`). It
found that the installer never registered systemd-boot (bootctl skips the EFI variables in a chroot): OVMF then
tried PXE/HTTP boot/EFI shell first, 4-5 minutes per boot, or "no bootable device". The ISO's `steamify-install`
now runs `efibootmgr` from the live system (a real partition, first in the order) and mounts the new system's
`/var/log` (`@log` subvolume) first so its logs (`steamify-install.log`, `steamify-bootentry.log`) survive.
To read a VM's boot entries without booting it: copy `vars.fd`, `virt-fw-vars -i <copy> --print` (package
`virt-firmware`). The power-off check accepts "loaded" or "tried at boot: No such device" (journal, not dmesg:
the VM has no AMD GPIO controller, the module refuses on purpose).
What only shows up per loader: Limine keeps its images under `/boot/<machine-id>/<kernel>/` and copies one
only when its content changed (same version = untouched), and `remember_last_entry: yes` overrides
`default_entry` (the test turns it off and restores it); GRUB's other kernel is picked with
`GRUB_DEFAULT="1>N"` + `grub-mkconfig` (key presses miss its 5 s menu); systemd-boot with
`bootctl set-oneshot <entry>.conf`. The "kernel update" reinstalls what the installed system's database lists,
which can be older than what the installer got (mirror skew: 7.2.8 installed, 7.2.7 in the database): a
downgrade, but still a version change through the same hooks.

Manual version of the same, for one loader:

Steamify's kernel-side parts (`steamify-fremont-poweroff`, `steamify-cros-ec-cec`,
`leds-valve-dkms`) are DKMS modules for every installed kernel, only installed
when the VM reports Fremont: start the VM with `./run.sh --fremont`, then run
`steamify.sh --defaults --options gaming,theme,glyphs,single,launcher,notify,vram,cec,machine,poweroff`
from the shared repo (`sudo mount -t 9p -o trans=virtio,version=9p2000.L repo /mnt`).
Then per loader: `dkms status` (3 modules x each kernel), reinstall both kernels
+ headers (`pacman -S linux-cachyos linux-cachyos-lts` + headers: rebuilds
DKMS, initramfs, and for GRUB the config), reboot into the default kernel and
into the other one (systemd-boot: `bootctl set-oneshot <entry>.conf`; GRUB or
Limine: send keys with `scripts/qmpkey.py <vm>/qmp.sock down ret ...`, or
change `default_entry`), and check `uname -r`, `lsmod`, and `dmesg | grep steamify`.
The legacy `drm.edid_firmware` removal (`hdmi_remove_boot_param`) is the code
that differs per loader: seed the parameter in `/etc/default/grub`,
`/etc/sdboot-manage.conf` or `/etc/default/limine`, source `lib/common.sh`,
`state.sh`, `hdmi-refresh.sh` from `/mnt`, and run it. To see why a VM won't
boot without a console, stop it, `qemu-img dd` the first 2 GB to a raw file,
`dd skip=1M` to cut the ESP, `udisksctl loop-setup` + `mount` it (no root),
and read `loader/loader.conf` and the entries; or boot the kernel directly with
`VM_KERNEL/VM_INITRD/VM_APPEND=... console=ttyS0` and `VM_SERIAL=` for a log.
