# TODO

## GitHub Actions: run the boot loader test in CI

Goal: every push/PR (and on demand) runs the whole automated test (`scripts/vmtest.sh`, see the next
section: boot loaders plus every suite) on runners, one job per suite or loader, and fails on any `FAIL` line.
Public repos, so the free Linux runners with KVM apply. Work on `feature/ci-bootloader-test`,
PR into the release branch. Tick items off as they're done.

- [x] 1. `run.sh`: headless mode (`VM_HEADLESS=1` -> `-display none`, plain virtio-vga); still to do: make `vmtest.sh` and `vmbootloadertest.sh` headless by default (`--window` opts out, a log Konsole opens on a desktop, CI opens none) and copy the repo's run.sh into `$VM_DIR` before starting
- [ ] 2. `vminstall.sh`: read the ISO's kernel/initramfs without `udisksctl` (bsdtar/7z when there is no session)
- [ ] 3. `vminstall.sh` / `vmbootloadertest.sh`: no `/dev/tty` prompts and no `pgrep` on the whole host in CI (`CI=1`)
- [ ] 4. Where the ISO comes from: newest artifact of `steammachine-cachyos-live-iso`'s `build.yml`
      (`gh run download -R theupriser/steammachine-cachyos-live-iso`), or a `workflow_dispatch` input (run id / URL)
- [ ] 5. `.github/workflows/bootloader-test.yml`: matrix over `limine, systemd-boot, grub`; steps: install
      qemu + ovmf, enable /dev/kvm, fetch the ISO, run the script, upload `~/vms/bl-<loader>.test.log` as an artifact
- [ ] 6. Runner limits: disk (sparse 60 GB qcow2, free space check), RAM (8 GB VM on a 16 GB runner), timeout (60 min)
- [ ] 7. Cache the pacman packages between runs (`actions/cache` on `~/vms/pkg-cache`, `VM_CACHE`)
- [ ] 8. Trigger it once on the branch, fix what the runner shows; note the run time in the skill
- [ ] 8b. Second job, `--fremont` hardware tests from TESTPLAN.md section H (LED driver, CEC with vivid,
      BIOS dry-run, boot into desktop/gaming and reboot, power-off module): guest-side, so they run on a runner too;
      needs a way to check without screenshots (gaming mode doesn't render)
- [ ] 9. `vm-install` skill + `vmtest.sh` header: mention the workflow, and that the advertised-loader check fails CI when a loader has no test
- [x] 10. TESTPLAN.md: section B for the boot loader test (B1-B8), pointing at `scripts/vmtest.sh`

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

- [~] P1 (implemented, one clean full run still to prove). Package cache for the suite VM: `VM_CACHE` shared as 9p and bound over `/var/cache/pacman/pkg`
      in `vmreset.sh`/the prelude (as vminstall-live.sh does); downloads only once
- [~] P2 (implemented: base image + overlays, own port per suite, MAX_PARALLEL=3, VM_MEM=4G; a whole parallel run has not finished yet). Parallel: each suite (and each boot loader) on its own copy of the VM (`cp --reflink` of the disk and vars),
      own `VM_PORT` and `VM_DIR`; `vmtest.sh` starts them together and waits; watch host CPU (16 cores, 6 vCPUs each)
- [ ] P3. Fewer resets: merge blocks that only read state (cli 10 + the menu R1.1)

## Run the tests on the PC (9800X3D, 64 GB) from a laptop

- [ ] R1. `scripts/vmtest-remote.sh <ssh-host>` written; try it once: the PC needs the three repos, qemu + OVMF + screen,
      KVM (on Windows: WSL2 with nested virtualization), the VMs in `~/vms` (`vmtest.sh --install` builds the boot loader
      VMs, `vminstall.sh --iso <CachyOS ISO>` with `VM_STEAMIFY=skip` the plain one), and the Steamify ISO
- [ ] R1b. The PC is WSL2 (Windows). To check there: `/dev/kvm` exists (Windows 11, virtualization on in the BIOS,
      nested virtualization on); `%UserProfile%\.wslconfig` `memory=` is raised (WSL2 defaults to half the RAM = 32 GB;
      3-4 VMs at 4-8 GB want ~48 GB) and `processors=16`; keep `~/vms` and the repos on WSL's own ext4, not under `/mnt/c`;
      `sudo apt install qemu-system-x86 ovmf screen`; no desktop there, so runs are headless with no Konsole (`view_start`
      returns early; watch with `screen -r vmtest` or `tail -f ~/vms/test.log`)
- [ ] R1c. `vminstall.sh` reads the ISO's kernel with `udisksctl`, which WSL doesn't have: use `bsdtar`/`7z` when there is no
      udisks (same as CI step 2), or copy the VM directories (`~/vms/steamify-vm`, `bl-*`, ~35 GB) from the laptop with rsync
- [ ] R2. With 64 GB and 8c/16t: try `MAX_PARALLEL=4` and 8 GB VMs (`VM_MEM=8G`)

## Boot loader test (local)

- [x] `scripts/vmtest.sh [--install] [loader...]` runs all advertised loaders, `vmbootloadertest.sh` one
- [x] guest checks in `share/bootloader-test/` (state, modules, legacy param, kernel update, boot check)
- [x] first full run of all three through `vmtest.sh`: Limine 41 / systemd-boot 40 / GRUB 40, 0 failed
- [ ] test the `VM_CACHE` speed-up with a second install
