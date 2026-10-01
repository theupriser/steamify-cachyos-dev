# TODO: NVIDIA (status 2026-10-01, evening: READ THIS FIRST, the sections below are the older plan)

The kernel-parameter fix did not cure gamescope's picture; the cause is NVIDIA's own bug (see `HARDWARE-RESULTS.md`). The product now does this
instead (branch `feature/nvidia-gaming-fix`, 2.9.7, still behind `.no-release-yet`):
- On an NVIDIA PC the SteamOS conversion (`gaming`, `boot`, `glyphs`) is hidden (shown only while already on, so it can be turned off).
- `nvidia` "Gaming on NVIDIA": Steam installed when missing, started at login on the Plasma desktop (user unit); sub-option `bigpicture`
  (a checkbox, not yet the choice row "How should Steam start up: Normal / Big Picture"): `-gamepadui` + Plasma starts with an empty session.
  RTX 20+ also keeps the old kernel parameters and early-load initramfs (user asked for it: "it may need it").
- `single` (single user mode) also works there: its own SDDM autologin into the Plasma session (`zzz-steamify-autologin.conf`).
- Tested in VMs (QEMU/KVM, fake NVIDIA GPU through `NVIDIA_DRM_DIR`, fake modules): suite `nvidia`, TESTPLAN N1-N5, 43 pass; regression suites green.
- Tested by hand on the RTX 5080 (earlier prototypes): Big Picture in the normal Plasma session smooth and clean; autologin and the final component NOT yet run there.
Open: run the final wizard on the RTX 5080 PC (turn the conversion off, tick Gaming on NVIDIA + Single user mode, reboot); the real choice row
instead of the checkbox (the choice row is hard-wired to `boot` in the TUI, the app and `--boot`); games don't start fullscreen under Plasma
(idea: a KWin rule forcing fullscreen for `steam_app_*`, may bring the direct-scanout artifacts back: test on the PC); apps that start later
(CachyOS Hello) may still cover Big Picture; hint in the menu on why the item is missing while the conversion is on; changelog hashes;
screenshot retake and the ISO's installer page for the new rows before a release. Separate branch `feature/extended-controller-support`
(xone dongle + xpadneo, opt-in) is stacked on this one.

# TODO: NVIDIA fix for gaming mode

Product code: branch `feature/nvidia-gaming-fix` in steamify-cachyos (github.com/theupriser/steamify-cachyos). These notes live here, in
steamify-cachyos-dev, on purpose: they are not part of the product and must not be in its history. The branch only has
a `.no-release-yet` marker pointing here.

When the feature is released, move what is still useful to steamify-cachyos' `TECHNICAL.md` and delete this folder (`nvidia/`).
Written 2026-10-01 so a new session can pick this up.

## Problem
A PC with an NVIDIA RTX 5080 (Blackwell, open kernel modules) shows a corrupted
image when gaming mode (gamescope) starts. Cause not confirmed. Steamify had no
NVIDIA handling at all. Likely: `nvidia-drm.modeset=1` / `nvidia-drm.fbdev=1`
missing, or a gamescope/driver mismatch.

## What is built (all on the product branch, pushed)
- `lib/nvidia.sh`: part of the SteamOS conversion (`gaming_enable` / `gaming_disable`).
  With an NVIDIA GPU + driver it adds `nvidia-drm.modeset=1 nvidia-drm.fbdev=1` to the
  kernel command line (Limine, systemd-boot, GRUB; backup first) and, only when every
  installed kernel has `nvidia_drm`, `/etc/mkinitcpio.conf.d/90-steamify-nvidia.conf`.
  Rebuilds initramfs + boot entries, verifies the config and the generated entries
  have the parameters (error otherwise). Undone on disable. Description: `TECHNICAL.md`.
- `FEATURE_VERSION[gaming]=2.9.7` so installs that already have the conversion re-apply it.
- Test hooks `NVIDIA_DRM_DIR`, `NVIDIA_MODULES_DIR`, `NVIDIA_LIMINE_CONF`,
  `NVIDIA_SDBOOT_DIR`, `NVIDIA_GRUB_CFG`: only set by tests; defaults are the real paths.

## Tested
- `bash tests/nvidia-test.sh`: 22 checks against a fake RTX 5080 beside an iGPU, a stub
  `modinfo`, temp boot loader files. All pass.
- Real VMs (QEMU/KVM, Limine, systemd-boot, GRUB): enable, reboot, kernel command line
  has the parameters; disable, reboot, original command line. All pass. Found and fixed:
  Limine pasted an appended `+=` line as text into the cmdline; a kernel without the
  NVIDIA modules made limine-mkinitcpio skip its boot entry.

## Kernel changes (done, VM-tested 2026-10-01, Limine)
The early-load drop-in is kept right by a pacman hook (`patches/steamify-nvidia-initramfs.{sh,hook}`,
installed by `nvidia_enable`, `/etc/pacman.d/hooks/85-steamify-nvidia-initramfs.hook`). Real pacman
transactions in a Limine VM: the hook runs between "Updating module dependencies" and "Updating
linux initcpios" (real hook names there: 60-*-remove, 80-limine-efi-deploy, 90-limine-mkinitcpio-remove-post,
90-mkinitcpio-install; DKMS would be 71-): the drop-in is present while every kernel has the modules, removed
when the LTS kernel loses them, back when they return; initramfs nvidia files 1 -> 5 -> 1 -> 5 -> 1
(1 = baseline, 4 modules added); no ERROR/skipping in any rebuild; cmdline kept the parameters after a reboot;
disable removes hook, script and drop-in. Found on the way: an empty hook/script was installed when
`patch_file` failed (now an error). Only tested with fake modules (renamed copies of a small module), on
Limine; systemd-boot and GRUB use the same hook but were not run with pacman transactions.

## Opt-out toggle (new request, 2026-10-01: not built yet)
When a compatible NVIDIA card is listed there should be a menu option, on by default (opt-out), named
"NVIDIA compatibility", as a sub-option of the SteamOS conversion, directly under "Boot into" (`boot`).
Today the fix runs unconditionally inside `gaming_enable`/`gaming_disable`.
- [ ] New component `nvidia` in `lib/menu.sh`: `COMPONENTS` right after `boot`, `PARENT[nvidia]=gaming`, `LABEL`,
      `FEATURE_VERSION[nvidia]`, `component_available` -> `nvidia_available` (= `nvidia_present`); not in
      `NO_PRESELECT` (ticked by default, `feature_new` ticks it for installs that already have the conversion).
      `nvidia_status` from the system (hook + parameters present), `nvidia_enable`/`nvidia_disable` = the code now
      called from `gaming_enable`/`gaming_disable` (remove those calls). Check `toggle_component` dependencies,
      `feature_record_unticked`, the plan texts ("This will: ...").
- [ ] The app: `ui/qml/Texts.qml` item texts, `AppState.qml`, the screen rows, `lib/backend.sh` if it lists ids;
      `--defaults [--options <ids>]` (the Steam Machine ISO's installer pages: it names the ids) and `--skip`.
- [ ] README rows/screenshot rule (a release that adds a menu row retakes `assets/screenshot-menu.png`), TECHNICAL.md,
      CHANGELOG, `tests/nvidia-test.sh` (status/enable/disable through the component), VM menu test in
      steamify-cachyos-dev (`share/vmtest/menu`, TESTPLAN.md row).
- [x] What "compatible" means (decided 2026-10-01): RTX 20 series or newer, the same check as the VRAM booster
      (`vram_nvidia_legacy_id`: a card on chwd's legacy lists `/var/lib/chwd/ids/nvidia-*.ids` is older; without the
      lists every card counts). `nvidia_present` = such a card + `nvidia_drm` available; the toggle's `nvidia_available`
      is the same function. Older cards (GTX 10/9 series) are left alone: no promise they work with gamescope.

## Older cards and other research
Decision 2026-10-01: support RTX 20 series or newer only, with the VRAM booster's check (done in `lib/nvidia.sh`).
The user had hoped older GPUs would work too; not promised. Full notes with sources: **`nvidia/RESEARCH.md`**.
Short version: open kernel modules need Turing+, Maxwell/Pascal/Volta need the proprietary driver (580 legacy branch);
`nvidia-drm.modeset/fbdev` exist in both, so the fix applies to any card with `nvidia_drm`, but nothing found says gamescope
works better or worse there (a GTX 1050 Ti has a known gamescope>3.16.16 start problem on HDMI, not ours). Cannot be promised:
needs a test on a real older card. Design for the toggle: on by default for any card with `nvidia_drm`, the label says
what it does, `tests/nvidia-hardware-test.sh` reports GPU and driver so results can be compared.

## Still to do
1. [ ] **On the NVIDIA PC** (only place the real fix can be judged; the full steps, how to read the results and the undo
   are in `nvidia/INSTRUCTIONS.md`), from the steamify-cachyos checkout on that branch:
   `bash tests/nvidia-hardware-test.sh check` (before), `... apply` (asks sudo), reboot,
   `... check` (after: `nvidia_drm modeset/fbdev = Y`), boot gaming mode, then
   `... visual` (was the picture clean?). Everything goes to `~/steamify-nvidia-report.txt`:
   paste it into the session.
2. [ ] If the parameters apply but the picture is still corrupted: look at the report's
   gamescope/NVIDIA log lines and the versions (`nvidia-open`, `nvidia-utils`, `gamescope`,
   `gamescope-session-cachyos`); the cause is then probably a gamescope/driver mismatch
   for Blackwell, not this fix.
3. [ ] Not covered by any test: the early-load drop-in with the REAL NVIDIA modules (the VMs only have renamed
   fake ones), and systemd-boot/GRUB with a pacman transaction (only Limine was run).
4. [ ] **Verify the RTX 20+ check on the PC** (decided 2026-10-01, only unit-tested with a fake chwd list; this laptop and the VMs
   have no `/var/lib/chwd/ids`): `bash tests/nvidia-hardware-test.sh check` prints the NVIDIA PCI id, whether it is on a chwd legacy
   list, and whether the lists exist at all. Expect for the RTX 5080: "supported", "not on a legacy list". If it says "no chwd
   legacy lists found" the check cannot tell old from new there (every card then counts as supported, like the VRAM booster):
   look at what `chwd`/`/var/lib/chwd/ids` provide on CachyOS and whether another source (the open-driver device list, the
   `nvidia-open` package) would be better for both the VRAM booster and this fix. Also try `check` on any older NVIDIA card
   that turns up (GTX 10/9 series): it must say "older than RTX 20 ... not applied" and `apply` must change nothing.
5. [ ] Changelog: fill in the commit hashes of this feature's lines (next commit, per AGENTS.md).
6. [ ] Build the opt-out toggle (section above) before release.
7. [ ] When complete and tested: ask the user whether it may be released. On a yes delete
   `.no-release-yet` (and this folder in the dev repo), open the PR into `release/2.9.7` (local branch only so
   far, one commit `chore: Version 2.9.7`; push it then) and merge it. The user merges
   `release/2.9.7` into `main`.

## Working rules (steamify-cachyos `AGENTS.md` and this repo's `AGENTS.md`)
- Never work on `main` or a `release/*` branch; no `Co-Authored-By` / "Generated with
  Claude" lines in commits or PRs. No git identity on the dev laptop: use
  `git -c user.name="Rick Peters" -c user.email="rickpeters@upriser.nl" commit`.
- Don't push `release/2.9.7` before the PR (a push can start a dev ISO build).

## If the VM tests need repeating (dev laptop, Ubuntu)
- `scripts/vminstall.sh` (steamify-cachyos-dev) with `VM_BOOTLOADER=limine|systemd-boot|grub`,
  `CI=1`, a short `VM_DIR` (`~/vms/...`: socket paths over 108 bytes fail) and `VM_SSH_KEY`.
- This session's shell lacked the `kvm` group: run QEMU steps as `sg kvm -c "..."`.
- `/tmp/vminstall-iso.lock` belongs to another user and there is no `bsdtar`: use a copy of
  `vminstall.sh` with another lock path and a `bsdtar` shim (Python `pycdlib` in a venv).
- Delete everything afterwards (`~/vms` incl. `pkg-cache`, the 3 GB ISO, keys).
