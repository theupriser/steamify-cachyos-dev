# TODO

## Tests in CI: dropped 2026-09-30, the VM tests run locally

Decision: `scripts/vmtest.sh` runs on the PC before the release PR, not on GitHub or Gitea runners (too slow, too heavy, and
not reliable: some GitHub runners had no `/dev/kvm`, nested virtualization made installs slow, the 3 GB ISO had to come
from the mirror on every run; the Gitea machine has 8 threads). The attempt (steamify-cachyos PR #66, closed, branch
`feature/vmtest-ci`) left these behind: `vminstall.sh` reads the ISO with `bsdtar` (no loop devices), `CI=1` makes it
headless, the VM's ssh key is looked up at every call, an aborted test counts as a failure, progress lines while a test runs.

- [x] TESTPLAN.md: section B for the boot loader test (B1-B8), pointing at `scripts/vmtest.sh`
- [x] `vmbootloadertest.sh --quick [--generic]`: only what the ISO's install must get right (B1-B5) on a Steam Machine VM
      (`--fremont`) or a plain PC (`--generic`: the Steam Machine items and modules must be absent)
- [ ] A helper that fetches the newest ISO release of the mirror (git.upriser.nl) into
      `../steamify-cachyos-live-iso/out/desktop/`, for `vmtest.sh --install` (the ISO is no longer kept locally)
- [ ] Document `--quick` / `--generic` in the `vm-install` skill and TESTPLAN.md (which B rows it covers)
- [ ] Steamify `AGENTS.md`: "run `scripts/vmtest.sh` before the release PR into main" (decided 2026-09-30)

## Full automated test: everything in TESTPLAN.md that needs no person

One command, `scripts/vmtest.sh [suite...]` (suites: `boot`, `cli`, `menu`, `hw`, `installer`; default all),
each check prints `PASS`/`FAIL`, the summary counts them, exit status = failures. Each block starts from a
fresh `ssh-ready` (`scripts/vmreset.sh --fremont`), as TESTPLAN.md says. GitHub runs the same command.
Guest-side checks live in `share/vmtest/<suite>/`, one file per TESTPLAN block. Adding a row to
TESTPLAN.md means adding its check here (say which row each check covers in a comment: `# F4`).

Automatable (encode as checks): R1.1-R1.6, R1.7 (`vmcec.sh` already prints PASS/FAIL), R1.8 (toggle matrix),
R1.9, R1.10, R2.1, G1-G3, F1-F7, H1, H3, H4 (session file), H5, and the boot loader matrix (done).
Not automatable without a person (stay manual, listed in the summary as SKIP; no screenshot testing): U1-U9,
R2.2 (first desktop login look), H-Real (real Steam Machine).

- [x] S1. Framework (vmtest.sh runs boot + every suite, --screen, summary in ~/vms/last-test.txt): `scripts/vmtest.sh` takes suites, resets the VM per block, tallies PASS/FAIL/SKIP,
      prints the skipped manual rows; move the loader matrix under suite `boot`
- [x] S2. Suite `cli` (55 checks pass): G1-G3, F1-F7 (exit codes, `features.state`, boot-desktop unit)
- [x] S3. Suite `menu` (36 checks pass): R1.1-R1.6, R1.10 with scripted menu input (`vmrun.sh`) and `vmstate.sh` asserts
- [x] S4. Suite `hw` (70 checks pass incl. H3 BIOS dry-run): H1, H3 (`WIZARD_BIOS_DRY_RUN=1`), H4, H5, R1.7 (`vmcec.sh --no-sleep`)
- [x] S5. Suite `installer` (4 pass): R2.1 (`vminstallsim.sh`)
- [x] S6. R1.8 toggle matrix as suite `toggles` (42 pass, 1 expected skip); R1.9 reboot checks still to add
- [ ] S7. TESTPLAN.md: mark which rows are automated (a column or a tag), keep the results log automatic:
      the script appends a line to it (date, branch, suites, counts)
- [ ] S8. Update the `steam-machine-testing` and `cachyos-vm-testing` skills: "run `scripts/vmtest.sh`" first

## Speed: the full run takes about an hour (target 20-25 min)

Where the time goes: boot loader VMs ~3 min each, every suite block restores a snapshot and reboots
(~1 min), and every block that applies Steamify downloads Steam and the rest again from the mirrors.

- [x] P1 (proven 2026-09-29: full run in 18 min on the PC). Package cache for the suite VM: `VM_CACHE` shared as 9p and bound over `/var/cache/pacman/pkg`
      in `vmreset.sh`/the prelude (as vminstall-live.sh does); downloads only once
- [x] P2 (base image + overlays, own port per suite, MAX_PARALLEL=3, VM_MEM=4G; first complete parallel run 2026-09-29: 328 pass, 18 min). Parallel: each suite (and each boot loader) on its own copy of the VM (`cp --reflink` of the disk and vars),
      own `VM_PORT` and `VM_DIR`; `vmtest.sh` starts them together and waits; watch host CPU (16 cores, 6 vCPUs each)
- [ ] P3. Fewer resets: merge blocks that only read state (cli 10 + the menu R1.1)

## Run the tests on the PC (9800X3D, 64 GB) from a laptop

- [ ] R1. `scripts/vmtest-remote.sh <ssh-host>` written; try it once: the PC needs the three repos, qemu + OVMF + screen,
      KVM (on Windows: WSL2 with nested virtualization), the VMs in `~/vms` (`vmtest.sh --install` builds the boot loader
      VMs, `vminstall.sh --iso <CachyOS ISO>` with `VM_STEAMIFY=skip` the plain one), and the Steamify ISO
- [x] R1b (done 2026-09-29: full vmtest.sh run there, 328 pass in 18 min; setup in the wsl-build-host skill). The PC is WSL2 (Windows). To check there: `/dev/kvm` exists (Windows 11, virtualization on in the BIOS,
      nested virtualization on); `%UserProfile%\.wslconfig` `memory=` is raised (WSL2 defaults to half the RAM = 32 GB;
      3-4 VMs at 4-8 GB want ~48 GB) and `processors=16`; keep `~/vms` and the repos on WSL's own ext4, not under `/mnt/c`;
      the distro is Arch (root): `pacman -S qemu-full edk2-ovmf screen`; automated runs are headless with no Konsole
      (`view_start` returns early; watch with `screen -r vmtest` or `tail -f ~/vms/test.log`), a VM for the user gets a
      window through WSLg (see the wsl-build-host skill). Still to do: a first full `vmtest.sh` run there
- [x] R1c. `vminstall.sh` without udisks (WSL): `losetup -P` + `mount` when `udisksctl` is missing and it runs as root
- [ ] R2. With 64 GB and 8c/16t: try `MAX_PARALLEL=4` and 8 GB VMs (`VM_MEM=8G`)

## Found 2026-09-29 (first full run on the PC)

- [x] B1 check (share/bootloader-test/boot-check.sh, after every reboot; passes on all three): the loader's own EFI boot entry exists, points to a real partition (not `HD(0,GPT,0000...)`)
      and was used (`efibootmgr` `BootCurrent`); systemd-boot booted through the fallback path unnoticed
- [x] ISO: mount `@log` at `$ROOT/var/log` before `steamify-install` writes its logs (PR #3 merged)
- [x] Steamify 2.9.1 (PR #53 into release/2.9.1; hw block 50 tests it): the CEC driver comes from one download (raw.githubusercontent.com, no retry, no fallback);
      a GitHub rate limit (HTTP 429, seen 2026-09-29 after a day of test installs) leaves CEC off. Ship the
      pinned source with Steamify instead (steamify-cachyos, via a release branch). Done as a cache in
      /var/cache/steamify (named after its checksum); the VMs share the host's (~/vms/pkg-cache/steamify).
      Later maybe: ship the file itself (the source repo is an unofficial mirror)
- [x] ISO: systemd-boot's EFI boot entry (efibootmgr from the live system), PR #2 merged
- [x] vminstall.sh: a poweroff that drops ssh is no failure, wait only for its own VM, ISO loop device under
      a lock, never root as the guest user

## Boot loader test (local)

- [x] `scripts/vmtest.sh [--install] [loader...]` runs all advertised loaders, `vmbootloadertest.sh` one
- [x] guest checks in `share/bootloader-test/` (state, modules, legacy param, kernel update, boot check)
- [x] first full run of all three through `vmtest.sh`: Limine 41 / systemd-boot 40 / GRUB 40, 0 failed
- [ ] test the `VM_CACHE` speed-up with a second install
