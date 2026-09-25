# Steamify CachyOS dev environment

A QEMU/KVM test VM running CachyOS (KDE Plasma 6) for developing and testing
[Steamify CachyOS](https://github.com/theupriser/steamify-cachyos),
plus helper scripts and a Claude Code skill that documents the test workflow.

Only scripts and docs live here. The ISO, disk image, UEFI variable stores,
logs and screenshots are generated locally. `.gitignore` is an allowlist: it
ignores everything and un-ignores only the tracked files, so add any new
tracked file to it explicitly.

## Requirements

- Linux host with KVM, `qemu-system-x86_64` (GTK/OpenGL display, virtfs/9p) and `qemu-img`
  (Ubuntu: `sudo apt install qemu-system-x86 qemu-utils ovmf`).
- OVMF firmware at `/usr/share/OVMF/OVMF_CODE_4M.fd` and `OVMF_VARS_4M.fd`.
- `curl` and `sha256sum` for `get-iso.sh`.
- Optional: an NVIDIA dGPU for `--nvidia` (PRIME offload of the virgl renderer).

## Quick start

```bash
./get-iso.sh        # download and verify the latest CachyOS desktop ISO
./run.sh install    # first run creates disk.qcow2 (60G) and vars.fd, boots the ISO
```

Install CachyOS with the **KDE Plasma** desktop and **plasma-login-manager**
as login manager. Power off and snapshot (only while the VM is off):

```bash
qemu-img snapshot -c clean disk.qcow2 && cp vars.fd vars.clean.fd
```

Boot the installed system (`./run.sh`) and, in the guest, enable SSH with key
auth and passwordless sudo through the read-only `vmtools` share:

```bash
sudo mount -t 9p -o trans=virtio,version=9p2000.L vmtools /media && /media/guest-ssh-setup.sh
```

### Adding your SSH key

`guest-ssh-setup.sh` authorizes the host's public keys. `run.sh` copies them
at every start from `~/.ssh/*.pub` into `share/host-keys.pub` (git-ignored),
which the guest sees as `/media/host-keys.pub`. So:

1. Make sure you have a key on the host; create one if `ls ~/.ssh/*.pub`
   shows nothing:

   ```bash
   ssh-keygen -t ed25519
   ```

2. Start (or restart) the VM with `./run.sh`, so the key is copied into the
   share.
3. In the guest, run the setup script (above). It installs and starts
   `sshd`, opens port 22 if a firewall is active, adds every host key to
   `~/.ssh/authorized_keys` (without duplicates) and gives the guest user
   passwordless sudo.
4. Test from the host: `ssh -p 2222 <vm-user>@localhost true` should return
   without asking for a password.

If you ran the setup script before the key existed (it prints "No host keys
were shared"), or you want to add another key later, either restart the VM
and run the setup script again, or copy the key over SSH with the guest
user's password:

```bash
ssh-copy-id -p 2222 <vm-user>@localhost
```

If SSH hangs at "banner exchange", `sshd` isn't running in the
guest or a firewall blocks port 22; check with `systemctl is-active sshd` in
the guest.

Power off and snapshot again:

```bash
qemu-img snapshot -c ssh-ready disk.qcow2 && cp vars.fd vars.ssh-ready.fd
```

Connect with `ssh -p 2222 <user>@localhost`. The project repo is shared
read-write as 9p tag `repo`; in the guest:
`sudo mount -t 9p -o trans=virtio,version=9p2000.L repo /mnt`.

### run.sh options

```
[REPO=/path/to/cachyos-gamescope-boot] ./run.sh [install] [--nvidia] [--vulkan] [--fremont]
```

- `install`: boot the installer ISO
- `--nvidia`: render the guest's virtio-gpu (virgl) on the host NVIDIA dGPU
- `--vulkan`: expose Vulkan to the guest (venus; unstable)
- `--fremont`: fake the Valve Steam Machine (Fremont) DMI data via `-smbios`
- `REPO` defaults to `$HOME/projects/cachyos-gamescope-boot` (the local clone of
  [steamify-cachyos](https://github.com/theupriser/steamify-cachyos))

## Helper scripts

- `scripts/vmreset.sh [--fremont]`: restore `ssh-ready`, boot, mount the repo, autologin into Plasma
  (and skip the broken krfoss mirror, install shellcheck)
- `scripts/vmrun.sh '<menu input>'`: run the wizard in the guest's Plasma session with scripted input
- `scripts/vmwatch.sh [--release] '<menu input>' [label]`: same, but in a visible Konsole window
  in the VM; `--release` runs the newest GitHub release instead of the mounted repo
- `scripts/vmshot.sh [--clean] <out.png>`: screenshot the guest's desktop (`--clean` closes
  Steam, CachyOS Hello and Konsole first)
- `scripts/vmstate.sh`: print the state of every wizard component
- `scripts/cmp.sh [save]`: save / diff the guest's KDE configs against a baseline

They use `VM_USER` (default `theupriser`), `VM_PORT` (`2222`) and `VM_HOST` (`localhost`).

## Claude Code skill

The full test workflow is documented in
[`.claude/skills/cachyos-vm-testing/SKILL.md`](.claude/skills/cachyos-vm-testing/SKILL.md);
Claude Code picks it up when run from this repo.
