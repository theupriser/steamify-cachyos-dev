# Testing the NVIDIA fix on a real PC

For the PC with an RTX 5080 (or any RTX 20 series or newer card) that shows a corrupted picture when
gaming mode (gamescope) starts. Product branch: `feature/nvidia-gaming-fix` in steamify-cachyos, not released.
This file lives in steamify-cachyos-dev (`nvidia/INSTRUCTIONS.md`); background and open work: `nvidia/TODO.md`; research
with sources: `nvidia/RESEARCH.md` (github.com/theupriser/steamify-cachyos-dev).

## What the fix does
With a supported NVIDIA GPU (RTX 20 series or newer, same check as the VRAM booster) and its driver installed it
- adds `nvidia-drm.modeset=1 nvidia-drm.fbdev=1` to the kernel command line (Limine, systemd-boot or GRUB;
  the file is backed up as `<file>.bak-gamescope-wizard`),
- loads the NVIDIA modules in the initramfs, but only while every installed kernel has them (a pacman hook,
  `/etc/pacman.d/hooks/85-steamify-nvidia-initramfs.hook`, decides again at every kernel change),
- rebuilds the initramfs and boot entries and checks that the parameters really are in them.
It takes effect after a reboot. Older cards (GTX 10 series and older) are left alone.

## Before you start
- CachyOS with the NVIDIA driver installed (`nvidia-open`), a user with sudo, `git`.
- Be at the PC and able to see the screen: the last step needs your eyes.
- Know the way back (below) in case the PC doesn't boot to a picture: a TTY (Ctrl+Alt+F3) or the boot menu's
  other kernel entry.

## Steps
1. Get the code:
   ```
   git clone -b feature/nvidia-gaming-fix https://github.com/theupriser/steamify-cachyos
   cd steamify-cachyos
   ```
   (An existing checkout: `git fetch && git checkout feature/nvidia-gaming-fix && git pull`.)
2. Look first, change nothing:
   ```
   bash tests/nvidia-hardware-test.sh check
   ```
3. Apply the fix (asks for your sudo password), then **reboot**:
   ```
   bash tests/nvidia-hardware-test.sh apply
   ```
4. After the reboot, check again:
   ```
   bash tests/nvidia-hardware-test.sh check
   ```
5. Start gaming mode, look at the screen, then (from the desktop or a TTY):
   ```
   bash tests/nvidia-hardware-test.sh visual
   ```
   It asks whether the picture was clean and for one line on what you saw.
6. Send back `~/steamify-nvidia-report.txt` (every run adds to it), or start a new session in the checkout and
   say "read nvidia/TODO.md in steamify-cachyos-dev and the report".

(`./steamify.sh` from the same checkout also applies the fix, automatically, as part of the SteamOS conversion:
there is no menu option for it yet. The script above shows more.)

## Reading `check`
| Line | Good result | If not |
|---|---|---|
| `PASS a supported NVIDIA GPU ... is detected` | your 5080 | `FAIL ... older than RTX 20`: the card is skipped on purpose. `FAIL no NVIDIA GPU with its driver`: driver not installed (nouveau?) |
| `NVIDIA PCI device id 0x... (not on a legacy list ...)` | RTX 20 or newer | on a legacy list: older card |
| `no chwd legacy lists found` | (note only) | the check cannot tell old from new cards; every card counts as supported. Tell me, it's open item 4 in `nvidia/TODO.md` |
| `PASS nvidia-drm.modeset=1 is on the running kernel's command line` (and `fbdev=1`) | after step 3 and the reboot | "in the boot loader's file but not booted yet": reboot, or the boot entry used is another one |
| `PASS nvidia_drm modeset = Y` (and `fbdev = Y`) | after the reboot | `unreadable`: it needs sudo, enter the password |
| `... early-load drop-in is used / skipped` | note only: skipped means a kernel without the NVIDIA modules is installed | nothing to do |

## Reading the result
- Parameters on, `modeset = Y`, `fbdev = Y`, picture clean: the fix works.
- Parameters on and `Y`, picture still corrupted: not this fix. The report has the gamescope and NVIDIA log lines and
  the versions of `nvidia-open`, `nvidia-utils`, `gamescope` and `gamescope-session-cachyos`: the cause is probably the
  gamescope/driver combination for Blackwell (see `nvidia/RESEARCH.md`).
- No picture at all after the reboot: undo it (next section) from a TTY or the other kernel entry, and send the report.

## Undo
Turning the SteamOS conversion off in the wizard removes the fix too. On its own, from the checkout:
```
SCRIPT_DIR=$PWD bash -c 'source lib/common.sh; source lib/hdmi-refresh.sh; source lib/vram-booster.sh; source lib/nvidia.sh; nvidia_disable'
```
It removes the parameters, the early-load file, the pacman hook and its script, and rebuilds the boot entries (reboot after).
By hand: delete ` nvidia-drm.modeset=1 nvidia-drm.fbdev=1` from `/etc/default/limine` (`KERNEL_CMDLINE[default]`),
`/etc/sdboot-manage.conf` (`LINUX_OPTIONS`) or `/etc/default/grub` (`GRUB_CMDLINE_LINUX_DEFAULT`), or restore the
`.bak-gamescope-wizard` copy next to it; remove `/etc/mkinitcpio.conf.d/90-steamify-nvidia.conf`,
`/etc/pacman.d/hooks/85-steamify-nvidia-initramfs.hook` and `/usr/local/libexec/steamify-nvidia-initramfs`; then
`sudo limine-mkinitcpio` (Limine) or `sudo mkinitcpio -P` and `sudo sdboot-manage gen` / `sudo grub-mkconfig -o /boot/grub/grub.cfg`.

## What is and isn't proven
Proven in VMs (QEMU/KVM, CachyOS ISO 260809): the parameters land and survive a reboot on Limine, systemd-boot and GRUB;
disabling restores the original; on Limine the pacman hook keeps the early-load file right across kernel reinstalls
(with fake NVIDIA modules). Not proven: that the fix cures the 5080's picture, the real NVIDIA modules in the
initramfs, DKMS hook order, systemd-boot/GRUB with a pacman transaction, and the RTX 20+ check against a real chwd list.
Unit test (no hardware): `bash tests/nvidia-test.sh`.
