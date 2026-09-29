---
name: wsl-build-host
description: Use when building or testing the Steam Machine ISO, or running the VM tests (vmtest.sh), on the user's Windows PC - Arch Linux in WSL2 (`ssh wsl`), with podman, QEMU + KVM and WSLg windows on the Windows desktop. Covers access, syncing working trees from the laptop, the podman ISO build as root, VM windows vs headless, showing output in the user's WSL terminal, and the WSL pitfalls (closing the window kills it, no udisks, no GPU passthrough).
---

# WSL build host (Arch on WSL2, the Windows PC)

The laptop is an arm64 Mac: x86_64 QEMU or containers there run emulated,
far too slow for Plasma/Calamares or an ISO build. The PC is the x86 host:
same workflows as `steam-machine-iso`, `vm-install` and `vmtest.sh`, with
the differences below. Found and tried on 2026-09-28 (ISO build, ISO VM with
a window, the loop-mount fallback). 2026-09-29: the whole `vmtest.sh` ran here, 328 checks pass in
18 minutes (3 VMs at a time).

## Access

- `ssh wsl` = `root@10.0.0.36`, port 22 (alias in the laptop's
  `~/.ssh/config`). That's Arch's own sshd inside WSL, not Windows' OpenSSH.
- `%UserProfile%\.wslconfig`: `networkingMode=mirrored` (WSL shares the PC's
  LAN IP), `nestedVirtualization=true` (`/dev/kvm`), `memory=` (WSL2 defaults
  to half the RAM: 30 GB seen). `/etc/wsl.conf`: `[boot] systemd=true`.
- Installed: podman, qemu-full, edk2-ovmf (`/usr/share/edk2/x64/OVMF*.4m.fd`,
  run.sh finds it), git, rsync, python, python-pillow (`qmpshot.py` writes a
  .ppm without it). vmtest.sh also wants `screen`.
- **The Arch window must stay open.** Closing the last WSL terminal shuts
  the distro down a little later, with every build, VM and sshd in it: SSH
  times out while the PC still pings. Ask the user to keep it open during
  runs and to reopen it after a Windows reboot. After such a restart, delete
  half-written VM disks before rerunning (`vminstall.sh` refuses an
  existing `disk.qcow2`, and `--force` asks).

## Differences from a normal Linux host

- User is **root**: no `sudo`, `systemd-run` without `--user`, paths under
  `/root/projects/` and `/root/vms/`. Units have no `$HOME`: set `HOME=/root`
  for scripts started with `systemd-run` (vminstall.sh needs it).
- udisks: `vminstall.sh` uses `udisksctl` when it's there (udisks2 is
  installed on this box now, and works) and falls back to `losetup -P` +
  `mount` as root without it. The ISO's loop device is set up under a lock
  (parallel installs collided: "Device or resource busy").
- Root is the host user: `vminstall.sh` then makes `theupriser` the guest
  user (never root).
- `pkill -x qemu-system-x86_64` never matches (names over 15 characters):
  `pkill -f '^[q]emu-system'`.

## Getting the code there

The WSL clones have no GitHub key: sync the laptop's working trees
(uncommitted changes included) instead of pulling. `vmtest-remote.sh`
pulls the pushed branch on the remote, so it needs a GitHub key there first
(and `REMOTE_REPO=/root/projects/steamify-cachyos-dev`).

```bash
cd ~/Projects && rsync -az --exclude out --exclude build \
  steammachine-cachyos-live-iso steamify-cachyos steamify-cachyos-dev wsl:projects/
ssh wsl 'find ~/projects -name __pycache__ -prune -exec rm -rf {} +; chown -R root: ~/projects'
```

Both fixups are needed: rsync keeps the laptop's uid (git then refuses with
"dubious ownership"), and a synced `patches/__pycache__` breaks
`steamify-prepare.sh` ("Is a directory").

## Building the ISO (~8 minutes)

```bash
ssh wsl 'cd ~/projects/steammachine-cachyos-live-iso && ./steamify-prepare.sh ~/projects/steamify-cachyos'
ssh wsl 'cd ~/projects/steammachine-cachyos-live-iso && rm -rf build out && systemd-run --collect -q -u isobuild-$(date +%s) --working-directory=$PWD bash -c "podman run --rm -t --pids-limit=-1 --ulimit nofile=65536:65536 --privileged --network=host -v /root/projects/iso-cache:/var/cache/pacman/pkg -v $PWD:/iso -w /iso docker.io/cachyos/cachyos:latest bash -c '\''pacman-key --init && pacman-key --populate && pacman -Syu --noconfirm --needed archiso mkinitcpio-archiso git squashfs-tools grub sudo && ./build-live-modules.sh && ./build-calamares-modules.sh && { ./buildiso.sh -p desktop -w || ./buildiso.sh -p desktop -c -w; }'\'' > /root/projects/iso-build.log 2>&1"'
```

Wait in one background command, not a polling loop:
`ssh wsl 'until ! podman ps -q | grep -q .; do sleep 20; done; tail -c 1500 ~/projects/iso-build.log; ls -la ~/projects/steammachine-cachyos-live-iso/out/desktop/'`.
Never start a build while `podman ps` shows one. Output:
`/root/projects/steammachine-cachyos-live-iso/out/desktop/steamify-cachyos-local-x86_64.iso` (a build by hand
has no release tag, so it's named `local`, label `STEAMIFY_<version>_LOCAL`; releases are built on the Gitea
mirror from a GitHub tag, see the ISO repo's `iso-release.yml`) (from
Windows Explorer: `\\wsl$\<distro>\root\projects\...`). The trailing
`chown: missing operand` / "unknown error" is harmless. mksquashfs shows no
progress in the log; the growing `build/iso/arch/x86_64/airootfs.sfs`
(~3.1 GB when done) is the measure.

## VM windows on the Windows desktop (WSLg)

There is a desktop after all: WSLg (`/tmp/.X11-unix/X0`,
`/mnt/wslg/runtime-dir/wayland-0`) puts QEMU's GTK window on the user's
Windows desktop. SSH sessions and units lack the variables, so set them:
`DISPLAY=:0 WAYLAND_DISPLAY=wayland-0 XDG_RUNTIME_DIR=/mnt/wslg/runtime-dir`.

- A VM for the user to watch or drive: that env plus e.g.
  `VM_SERIAL=/root/vms/iso-vm/serial ISO_VM_DIR=/root/vms/iso-vm scripts/vmisoboot.sh --fresh --iso <iso>`.
  The user may click through it themselves: check the disk size / serial
  log before assuming it still sits at the live session.
- Automated runs stay headless (`--headless` / `VM_HEADLESS=1`, vmtest.sh's
  default); `qmpshot.py` works then.
- GPU: no passthrough of the NVIDIA card. WSL2 only has the paravirtual
  `/dev/dxg`, no PCI device for VFIO, and Windows keeps driving the card.
  run.sh's default virgl (`virtio-vga-gl`, `gl=on`) renders through WSLg's
  d3d12 Mesa on it, but QMP screenshots then give "no surface".

## Running the tests here

`scripts/vmtest.sh --screen` from `~/projects/steamify-cachyos-dev` (as root,
`HOME=/root`), then read `~/vms/last-test.txt`; follow it as the
`progress-report` skill says. Needs `~/vms/steamify-vm` (`VM_STEAMIFY=skip
VM_DIR=/root/vms/steamify-vm scripts/vminstall.sh --iso <CachyOS ISO>`, the
user keeps one in `/root/`) and `~/vms/bl-<loader>` (`vmbootloadertest.sh
<loader> --install`, or `vmtest.sh --install`). Memory: WSL sees 30 GB, fine
for 3 VMs at 4 GB (and the 8 GB install VMs); raise `memory=` in
`.wslconfig` before `MAX_PARALLEL=4` or `VM_MEM=8G`.

## Showing output in the user's WSL terminal

Their visible terminal is the `-bash` whose parent is WSL's `/init`
(`ps -eo pid,ppid,tty,args --forest`), usually `/dev/pts/0`. Not the
`login -- root` one: a hidden console getty. Stream a log into it as a unit
so it can be stopped:
`systemd-run --collect -q -u showlog bash -c "tail -n 20 -F <log> > /dev/pts/0 2>&1"`;
stop with `systemctl stop showlog` (Ctrl+C there doesn't). Tell the user
not to type there while it runs. A header printed before a busy log scrolls
away at once.

Reporting progress (the table, only on a change), a headless VM's screen in a
window (`scripts/vmview.py`) and looking into a stuck job: the
`progress-report` skill.
