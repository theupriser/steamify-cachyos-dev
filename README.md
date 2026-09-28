# Steamify CachyOS dev environment

A QEMU/KVM test VM running CachyOS (KDE Plasma 6) for developing and testing
[Steamify CachyOS](https://github.com/theupriser/steamify-cachyos),
plus helper scripts and a Claude Code skill that documents the test workflow.

Only scripts and docs live here. The ISO, disk image, UEFI variable stores,
logs and screenshots are generated locally. `.gitignore` is an allowlist: it
ignores everything and un-ignores only the tracked files, so add any new
tracked file to it explicitly.

## Requirements

- An x86_64 Linux host with KVM (not Windows or macOS: `run.sh` relies on KVM,
  memfd and GTK/virgl, and CachyOS only exists for x86_64),
  `qemu-system-x86_64` (GTK/OpenGL display, virtfs/9p) and `qemu-img`
  (Ubuntu: `sudo apt install qemu-system-x86 qemu-utils ovmf`).
- OVMF firmware at `/usr/share/OVMF/OVMF_CODE_4M.fd` and `OVMF_VARS_4M.fd`.
- `curl` and `sha256sum` for `get-iso.sh`.
- Optional: an NVIDIA dGPU for `--nvidia` (PRIME offload of the virgl renderer).

## Quick start: unattended install

```bash
./get-iso.sh                                             # latest CachyOS desktop ISO (verified)
VM_DIR=~/vms/steamify-vm scripts/vminstall.sh --fremont  # 15-30 min, watch the VM's window
```

Installs CachyOS from the ISO without any manual step, with CachyOS's own
headless installer (KDE Plasma, plasma-login-manager, btrfs, Limine,
`linux-cachyos` + `-lts`), and leaves the snapshots `clean` and `ssh-ready`:
sshd with your key, passwordless sudo, autologin into Plasma, English, the
host's timezone. Details: [`.claude/skills/vm-install`](.claude/skills/vm-install/SKILL.md).

- **Login by hand**: your host username, password **`steamify`** (root too).
- **SSH**: `~/.ssh/steamify-vm_ed25519`, made on the first install (it asks:
  that key, or one of your own `~/.ssh/*.pub`), then always used. Existing
  keys are never overwritten; the VM's host key lives in `$VM_DIR/known_hosts`,
  not in `~/.ssh/known_hosts`.
- `$VM_DIR` also records the user, key and Steamify checkout (`vm-user`,
  `ssh-key`, `repo-path`); pass the same `VM_DIR` to the other scripts.
- `--iso <file>` installs another archiso-based ISO the same way (the Steam
  Machine ISO, later); `--force` replaces an existing VM (asks first).

Snapshots (only while the VM is off; keep vars.fd with the disk):

```bash
qemu-img snapshot -a ssh-ready disk.qcow2 && cp vars.ssh-ready.fd vars.fd   # restore
```

### Manual install (fallback)

`./run.sh install` boots the ISO (a first run creates `disk.qcow2`, 60G, and
`vars.fd`). Install CachyOS with **KDE Plasma** and **plasma-login-manager**
through Calamares, power off, `qemu-img snapshot -c clean disk.qcow2 && cp
vars.fd vars.clean.fd`. Boot it (`./run.sh`) and, in the guest:

```bash
sudo mount -t 9p -o trans=virtio,version=9p2000.L vmtools /media && /media/guest-ssh-setup.sh
```

(sshd, the host's `~/.ssh/*.pub` from `share/host-keys.pub`, passwordless
sudo). Power off, `qemu-img snapshot -c ssh-ready disk.qcow2 && cp vars.fd
vars.ssh-ready.fd`.

### The same key on the Steam Machine

```bash
scripts/steammachine-addkey.sh [user@host]      # default: steammachine (~/.ssh/config)
```

authorizes `~/.ssh/steamify-vm_ed25519` on the Steam Machine too (asks its
password once), so one key reaches the VM and the real machine.

### run.sh options

```
[REPO=/path/to/steamify-cachyos] ./run.sh [install] [--nvidia] [--vulkan [--amd]] [--fremont]
```

- `install`: boot the installer ISO (`VM_ISO`, default `cachyos.iso`)
- `--nvidia`: render the guest's virtio-gpu (virgl) on the host NVIDIA dGPU
- `--vulkan`: expose Vulkan to the guest (venus; unstable)
- `--fremont`: fake the Valve Steam Machine (Fremont) DMI data via `-smbios`
- `REPO`: the Steamify checkout shared as 9p `repo` (in the guest: `sudo
  mount -t 9p -o trans=virtio,version=9p2000.L repo /mnt`); default
  `repo-path` next to the disk, else `$HOME/projects/cachyos-gamescope-boot`
- `VM_KERNEL`/`VM_INITRD`/`VM_APPEND` (boot a kernel directly) and
  `VM_SERIAL` (serial console log + socket): used by `vminstall.sh`

## Helper scripts

- `scripts/vminstall.sh [--force] [--iso <file>] [--fremont]`: unattended install (above)
- `scripts/vmreset.sh [--fremont]`: restore `ssh-ready`, boot, mount the repo, autologin into Plasma
  (and skip the broken krfoss mirror, install shellcheck)
- `scripts/vmrun.sh '<menu input>'`: run the wizard in the guest's Plasma session with scripted input
- `scripts/vmwatch.sh [--release] '<menu input>' [label]`: same, but in a visible Konsole window
  in the VM; `--release` runs the newest GitHub release instead of the mounted repo
- `scripts/vminstallsim.sh [--fresh] [--defaults options]`: Steamify's install-time mode for a
  user who never logged in (the Steam Machine ISO's installer step)
- `scripts/vmshot.sh [--clean] <out.png>`: screenshot the guest's desktop (`--clean` closes
  Steam, CachyOS Hello and Konsole first)
- `scripts/vmstate.sh`: print the state of every wizard component
- `scripts/vmcec.sh [--no-sleep]`: HDMI-CEC against a fake TV (vivid)
- `scripts/qmptype.py <qmp.sock> "<text>"` / `scripts/qmpkey.py <qmp.sock> <keys>`: type text / press
  keys in the VM (e.g. drive the Steamify app: `down right ctrl-ret ret`)
- `scripts/cmp.sh [save]`: save / diff the guest's KDE configs against a baseline
- `scripts/steammachine-addkey.sh [user@host]`: the VM key on the Steam Machine (above)

They use `VM_DIR` (default: this repo if it has `disk.qcow2`, else
`~/vms/cachyos-test`), and from it `VM_USER` (`vm-user`, else `theupriser`)
and `VM_SSH_KEY` (`ssh-key`); `VM_PORT` (`2222`), `VM_HOST` (`localhost`).

## Test plan

[`TESTPLAN.md`](TESTPLAN.md): what to test per release (regression, the app,
new features, Steam Machine hardware faked and real) and the results log.

## Claude Code skills

- [`cachyos-vm-testing`](.claude/skills/cachyos-vm-testing/SKILL.md): the test workflow in the VM
- [`vm-install`](.claude/skills/vm-install/SKILL.md): creating the VM unattended
- [`steam-machine-testing`](.claude/skills/steam-machine-testing/SKILL.md): on the real Steam Machine
- [`steam-machine-iso`](.claude/skills/steam-machine-iso/SKILL.md): the Steam Machine ISO

Claude Code picks them up when run from this repo.
