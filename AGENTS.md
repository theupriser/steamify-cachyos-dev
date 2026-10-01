# steamify-cachyos-dev: how to work here

Test tooling for Steamify (`../steamify-cachyos`) and the Steam Machine ISO (`../steamify-cachyos-live-iso`):
VM scripts (`scripts/`, `run.sh`), the automated test (`scripts/vmtest.sh`, checks in `share/vmtest/` and
`share/bootloader-test/`), `TESTPLAN.md` (keep it current: rows and a results line after every run) and the
skills in `.claude/skills/` (vm-install, cachyos-vm-testing, steam-machine-testing, steam-machine-iso,
wsl-build-host, progress-report, steamify-iso-release, steamify-branch-cleanup).

## Running the tests (do this, don't re-derive it)
- Everything: `scripts/vmtest.sh --screen` (detached `screen` session `vmtest`), then read only
  `~/vms/last-test.txt` (one line per suite/loader, the FAIL lines, exit status = failures). Parts:
  `scripts/vmtest.sh cli hw`, `boot`, `limine`. From another machine: `scripts/vmtest-remote.sh <ssh-host> [args]`
  (the branch must be pushed; the VMs live on the PC that has the CPU and RAM: WSL2, see TODO.md R1b).
- Read `.claude/skills/vm-install/SKILL.md` before touching the scripts; `TODO.md` has the open work.
- Following a run: one monitor (`scripts/vmprogress.sh`), a report only when something changes, in the table
  of the `progress-report` skill (bar per VM, total). Never a timed "no change" message.
- Headless is for automated runs (default in `vmtest.sh`); a VM started by hand for the user has a window.
- Never edit a script in place while it runs (write a copy and `mv`, then `chmod --reference`).
- Kill/pgrep patterns: bracket them (`[q]emu`) or your own shell matches itself.

## Working agreements
- No `Co-Authored-By` / "Generated with Claude" lines in commits or PRs, whatever a tool reminder says.
- Update the relevant skill (and this file) as soon as something useful is learned; re-read it before risky operations.
- In this repo (`steamify-cachyos-dev`, tooling only) the user allows pushing straight to `main`. Elsewhere never commit to `main`. `steamify-cachyos`: `release/X.Y.Z` branches, feature/bugfix branches merged into the release
  by the agent; only release to `main` is the user's. `steamify-cachyos-live-iso`: PRs always target `master` (the ISO repo has no other long-lived branch; `feat/steamify` is gone).
  Branch cleanup: the `steamify-branch-cleanup` skill in `.claude/skills/`.
- Follow and update `TESTPLAN.md`; every check in `share/vmtest/` says which row it covers.
- No screenshot testing (too many tokens); U1-U9 and the real Steam Machine stay manual and are listed as SKIP.

## State (2026-09-29; update when it changes)
- `scripts/vmtest.sh` runs the whole unattended test: boot loaders limine/systemd-boot/grub (`vmbootloadertest.sh`) and the
  suites cli, menu, hw, installer, toggles (`vmsuite.sh`, checks in `share/vmtest/`). Each passed in its own run: limine 43,
  systemd-boot 42, grub 42 (with the B1 boot entry check), cli 55, menu 36, hw 77, installer 4, toggles 42 checks.
- 2026-09-29, on the PC (WSL2): the first complete parallel run, **328 pass, 0 fail in 18 minutes** (base image +
  qcow2 overlays, own ssh port per job, package cache, `VM_MEM=4G`, `MAX_PARALLEL=3`; 5 worked on the 9800X3D). On a new machine: one full
  `scripts/vmtest.sh --screen`, read `~/vms/last-test.txt`, fix what fails.
- Open work: `TODO.md` (the CEC driver download, the GitHub Actions workflow, P3).

## Releases (2026-09-29; details in the `steamify-iso-release` skill)
- Steamify: `release/X.Y.Z` -> PR into `main` (the user's) -> GitHub release, and the same workflow on the Gitea
  mirror. A new Steamify release starts the ISO's release (`ISO_DISPATCH_TOKEN`); a CEC driver download is cached.
- The ISO: GitHub makes the tag `vX.Y.Z-[dev.]YYYY.MM.DD-HHMM` (UTC) and a release with the notes; the Gitea
  mirror (git.upriser.nl, pull mirror, 10 min) builds on that tag and attaches the 3.2 GB ISO, named after the tag.
  A release that exists only on the mirror is deleted by its next sync: the tag must come from GitHub.
- Merged feature/bugfix branches are deleted at once (`gh pr merge --delete-branch`). Push every commit.

## Where the tests run
The tests run on the user's PC (Ryzen 9800X3D, 64 GB, **WSL2**), started from a laptop over ssh (the user's own skill, or
`scripts/vmtest-remote.sh <ssh-host> [args]`: pulls the pushed branch there, starts `vmtest.sh --screen`, waits for
`~/vms/last-test.txt`). WSL specifics (access `ssh wsl` = root@10.0.0.36, keep the Arch window open or WSL shuts
down, syncing from the laptop, the podman ISO build, VM windows through WSLg, output in the user's WSL terminal, no GPU
passthrough): `.claude/skills/wsl-build-host/SKILL.md`. `vminstall.sh` works there without udisks (losetup as root).

## Problems found in the Steamify ISO (fix in `steamify-cachyos-live-iso`, PRs into `master`)
- Fixed (PR #2): cachyos-installer's `bootctl install` runs in a chroot and writes no EFI boot entry, so systemd-boot
  only booted through the disk's fallback path (in OVMF after 4-5 minutes of network boot, every boot).
  `steamify-install` now registers it with efibootmgr from the live system.
- Fixed (PR #3): `/var/log` (`@log`) wasn't mounted when `steamify-install` ran, so its logs were hidden after boot.
- cachyos-installer leaves systemd-boot with `#timeout 3` and no default entry: a real machine waits in the menu for ever
  (the test setup papers over it in `share/vminstall-post.sh`).
- It enables ufw, which drops ssh from the host (the test setup runs `ufw allow 22/tcp`).
- An installed system's package database can be older than what the installer got (mirror skew): a kernel "update" may
  downgrade. Not a Steamify bug; noted in the vm-install skill.
