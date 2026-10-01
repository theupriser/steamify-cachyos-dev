# NVIDIA and gamescope: research notes (for steamify-cachyos branch `feature/nvidia-gaming-fix`)

Written 2026-10-01 for the NVIDIA fix (`lib/nvidia.sh`). Delete the `nvidia/` folder when the feature is released, or move what is still useful to steamify-cachyos' `TECHNICAL.md`.
"Verified" means seen in this session (a VM run or a fetched page); the rest is from search results or memory.

## The user's PC
RTX 5080 (Blackwell). Blackwell only works with NVIDIA's open kernel modules (`nvidia-open`), driver 570+.
The corrupted picture at gaming mode start is not diagnosed yet: the fix adds kernel parameters, the real cause
may be the gamescope/driver combination. `tests/nvidia-hardware-test.sh` collects the facts.

## What the fix changes and why (reasoning, not proven for gamescope)
- gamescope runs the display itself through DRM/KMS. With NVIDIA that needs `nvidia-drm.modeset=1`; `nvidia-drm.fbdev=1`
  gives the console a framebuffer from `nvidia-drm`, so the hand-off from the console to gamescope is clean.
- Loading the NVIDIA modules in the initramfs (early KMS) only changes how early boot looks (native resolution,
  splash, passphrase prompt), not speed. It is not needed for gamescope, which starts after login (believed, not proven).
- No source found that mentions these parameters for gamescope; the fix is a standard NVIDIA/Wayland setup, applied
  automatically. Whether it cures the 5080's picture is only known after `tests/nvidia-hardware-test.sh`.

## Which cards (decision 2026-10-01: RTX 20 series or newer only, same check as the VRAM booster)
The code skips a card whose PCI id is on chwd's legacy lists (`vram_nvidia_legacy_id`); the notes below are why older
cards are not promised.
- Open kernel modules: Turing (RTX 20, GTX 16) and newer only; they need the GSP processor first built into Turing.
  Maxwell, Pascal and Volta (GTX 900/10 series, Titan V) only work with the proprietary driver, whose legacy branch
  is 580. Source: [NVIDIA README, open kernel modules](https://download.nvidia.com/XFree86/Linux-x86_64/560.35.03/README/kernel_open.html),
  [NVIDIA datacenter driver guide, kernel modules](https://docs.nvidia.com/datacenter/tesla/driver-installation-guide/kernel-modules.html).
- `nvidia-drm.modeset` and `fbdev` are options of the `nvidia-drm` module in both flavours, so the fix applies to
  any card whose driver provides `nvidia_drm` (what `nvidia_present` tests: GPU vendor 0x10de + `modinfo nvidia_drm`).
  Whether gamescope then works on an older card is a different question, and no source says the fix helps there.
- Not NVIDIA's proprietary driver: nouveau has no `nvidia_drm`, so the fix does nothing. The CachyOS handheld ISO boots
  GTX 10xx and older with nouveau until the NVIDIA driver is installed
  ([CachyOS forum](https://discuss.cachyos.org/t/information-experimental-cachyos-handheld-edition/203)).

## Known gamescope problems that are not this fix
- **GTX 1050 Ti (Pascal), driver 580.119.02, gamescope newer than 3.16.16:** the CachyOS handheld session fails to start when
  a display is on the GPU's HDMI port (back to the TTY, loop). Workarounds: downgrade `gamescope` and `lib32-gamescope`
  to 3.16.16, or use the motherboard's video port. Fixed upstream? unknown.
  [CachyOS forum](https://discuss.cachyos.org/t/no-display-on-cachyos-handheld-edition-on-nvidia-with-gamescope-3-16-16/20935)
- **VRS on PCs:** CachyOS' gamescope-session enables variable rate shading (`STEAM_USE_DYNAMIC_VRS=1`,
  `RADV_FORCE_VRS_CONFIG_FILE`, `echo 1x1 > ...` in `/usr/lib/steamos/gamescope-session`). It broke rendering (missing
  floors/lighting, bad post-processing) on a PC with an AMD RX 6800 XT. RADV is AMD's driver: not the NVIDIA corruption.
  Workaround: comment those three lines, or per game `env -u RADV_FORCE_VRS_CONFIG_FILE STEAM_USE_DYNAMIC_VRS=0 %command%`.
  [CachyOS forum](https://discuss.cachyos.org/t/cachyos-gamescope-session-asset-missing-vrs-fix/34971)
- gamescope's DRM backend needs Vulkan DRM format modifiers; with the open Mesa driver NVK that came in Mesa 24.1
  ([GamingOnLinux](https://www.gamingonlinux.com/2024/05/nvk-driver-gets-drm-format-modifiers-to-work-with-gamescope-in-mesa-24-1)).
  The proprietary driver had format-modifier trouble with gamescope too (GitHub issues
  [ValveSoftware/gamescope#1662](https://github.com/ValveSoftware/gamescope/issues/1662),
  [#1516](https://github.com/ValveSoftware/gamescope/issues/1516): titles seen only, not read).

## What was verified in VMs (QEMU/KVM, CachyOS ISO 260809)
- Kernel parameters land and survive a reboot on Limine, systemd-boot and GRUB; disable restores the original.
- Limine's tool is a compiled program: an appended `KERNEL_CMDLINE[default]+=" ..."` line was pasted into the kernel
  command line as text; the fix edits the existing `KERNEL_CMDLINE[default]="..."` line.
- `mkinitcpio` fails on a MODULES entry a kernel lacks; `limine-mkinitcpio` then skips that kernel's initramfs and boot
  entry (parameters included); systemd-boot/GRUB image: "may not be complete" (not run with failing modules).
- Real CachyOS/Limine pacman hooks: `10-limine-snapper-lock`, `60-limine-mkinitcpio-remove-pre`, `60-mkinitcpio-remove`,
  `80-limine-efi-deploy`, `90-limine-mkinitcpio-remove-post`, `90-mkinitcpio-install`; Steamify's hook is `85-`
  (DKMS's is `71-dkms-install`, not installed in the VM). A mirror older than the ISO "downgrades" kernels on reinstall.
- The hook keeps the early-load drop-in right across kernel changes (see `nvidia/TODO.md`).

## Still unknown (needs the hardware)
- Does the fix cure the 5080's corrupted picture? Which gamescope/driver versions does the PC have?
- Does it help, harm or do nothing on Maxwell/Pascal/Volta cards? No older card available yet.
- Real NVIDIA modules in the initramfs (VMs only had renamed fake modules); DKMS hook order on a PC with
  `nvidia-open-dkms`.
