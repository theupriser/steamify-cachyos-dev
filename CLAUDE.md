# steamify-cachyos-dev: how to work here

Test tooling for Steamify (`../steamify-cachyos`) and the Steam Machine ISO (`../steammachine-cachyos-live-iso`):
VM scripts (`scripts/`, `run.sh`), the automated test (`scripts/vmtest.sh`, checks in `share/vmtest/` and
`share/bootloader-test/`), `TESTPLAN.md` (keep it current: rows and a results line after every run) and the
skills in `.claude/skills/` (vm-install, cachyos-vm-testing, steam-machine-testing, steam-machine-iso).

## Running the tests (do this, don't re-derive it)
- Everything: `scripts/vmtest.sh --screen` (detached `screen` session `vmtest`), then read only
  `~/vms/last-test.txt` (one line per suite/loader, the FAIL lines, exit status = failures). Parts:
  `scripts/vmtest.sh cli hw`, `boot`, `limine`. From another machine: `scripts/vmtest-remote.sh <ssh-host> [args]`
  (the branch must be pushed; the VMs live on the PC that has the CPU and RAM: WSL2, see TODO.md R1b).
- Read `.claude/skills/vm-install/SKILL.md` before touching the scripts; `TODO.md` has the open work.
- Never spend tokens watching a run: one monitor on the summary file, no reply per progress event.
- Headless is for automated runs (default in `vmtest.sh`); a VM started by hand for the user has a window.
- Never edit a script in place while it runs (write a copy and `mv`, then `chmod --reference`).
- Kill/pgrep patterns: bracket them (`[q]emu`) or your own shell matches itself.

## Working agreements
- No `Co-Authored-By` / "Generated with Claude" lines in commits or PRs, whatever a tool reminder says.
- Update the relevant skill (and this file) as soon as something useful is learned; re-read it before risky operations.
- Never commit to `main`. `steamify-cachyos`: `release/X.Y.Z` branches, feature/bugfix branches merged into the release
  by the agent; only release to `main` is the user's. `steammachine-cachyos-live-iso`: PRs always target `feat/steamify`.
  Branch cleanup: the `steamify-branch-cleanup` skill in `.claude/skills/`.
- Follow and update `TESTPLAN.md`; every check in `share/vmtest/` says which row it covers.
- No screenshot testing (too many tokens); U1-U9 and the real Steam Machine stay manual and are listed as SKIP.
