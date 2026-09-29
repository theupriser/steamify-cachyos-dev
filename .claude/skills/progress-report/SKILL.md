---
name: progress-report
description: Use whenever a long VM job runs for the user (vminstall.sh, vmbootloadertest.sh, vmsuite.sh, vmtest.sh, an ISO build), locally or on the WSL PC, and the user wants to follow it - how to report progress (a table with a bar per VM and a total, only when something changes), show the log in the user's terminal and the VM's screen on their desktop, and look into a job that seems stuck.
---

# Progress report for VM jobs

What the user asked for (2026-09-29): see what is going on, without noise.

## The rules

- **Report only on a change**: an install stage, a test step, a job finishing, a FAIL. Never a
  timed "no change" message. One monitor, not polling from the conversation.
- **Every report is the same table**, one row per VM/job plus a total row:

  | VM | Step | Checks | Progress |
  |---|---|---|---|
  | grub | ✅ done | 40 / 40, 0 failed | `████████████████████` 100% |
  | systemd-boot | test: kernel update | 27 / 40, 0 failed | `█████████████░░░░░░░` 68% |
  | limine | install: desktop environment (40%) | 0 / 41 | `░░░░░░░░░░░░░░░░░░░░` 0% |
  | **Total** | | **67 / 121**, 0 failed | `███████████░░░░░░░░░` 55% |

  Bar: 20 cells, `█` per 5% of checks passed out of the expected count. Step in plain words
  ("install: base system (9%)", "test: reboot into the other kernel"), ✅ when done, ❌ with the
  failed check's name when something fails. Under the table at most two lines: what is odd or next.
- **A FAIL or a job that stops moving is reported at once**, with the cause looked up first (below),
  not only the numbers.

## The monitor

`scripts/vmprogress.sh [job...]` (jobs: limine systemd-boot grub cli menu hw installer toggles)
prints one line only when something changes and `ALLDONE` at the end; it reads the latest run in
`~/vms/bl-<loader>.test.log` / `~/vms/run-<suite>.log` and the install percentage from
`$VM_DIR/install-www/install.log`. Expected check counts live at its top: update them when a
suite gains checks. `--once` prints the current state.

On the WSL PC, from the laptop:

```
Monitor(command: "ssh wsl '~/projects/steamify-cachyos-dev/scripts/vmprogress.sh grub systemd-boot limine'",
        description: "boot loader tests: only on change", timeout_ms: 1800000)
```

Re-arm it when it expires while jobs still run. Turn each event into the table above.

Stopping a background command or monitor on the laptop (TaskStop) does not stop what it started on
the PC: its remote loop keeps running (`pkill -f` it there). A leftover `until vm_ssh ...` loop
against a VM that gets reinstalled saves the live ISO's host key in `$VM_DIR/known_hosts`, and the
install then hangs at its first-boot ssh check ("REMOTE HOST IDENTIFICATION HAS CHANGED"). Never
ssh to a VM with its `VM_DIR` settings while it installs; fix it with `ssh-keygen -R "[localhost]:<port>" -f $VM_DIR/known_hosts`.

Monitor rules learned on 2026-09-29: **one monitor per job, stop the old one** (`TaskStop`) when a new run
starts, or every run is reported twice; a job that ends by itself (the ISO build on Gitea, `vmtest.sh`) is
best watched with a loop that exits on its terminal states and prints only *changes* (a new step, a finished
job, a FAIL, a new HTTP status), never on a percentage or a PASS count alone. For a Gitea Actions run, poll its
public log (`.../actions/runs/<run>/jobs/<job>/logs`, see `steamify-iso-release`) and grep for the step names.
A chain across systems (Steamify release -> ISO tag -> mirror sync -> Gitea build -> download link) is one
monitor that says each link when it happens and ends on the real check (the download URL answers 200).
When the tool that runs commands stops answering (auto-mode classifier "no verdict"), retry once, then say so
and carry on with reading/local work: nothing running on the PC is affected.

## What the user sees on the PC

- **Their terminal**: stream the running job's log into it (the `showlog` unit, `wsl-build-host`
  skill); switch it when the job changes (install log, then the test log, then `~/vms/test.log`).
- **The VM's screen**: automated runs are headless. To show one: `scripts/vmview.py ~/vms/<vm>` in
  a unit with the WSLg env (a window refreshed every 2 s, view only). When the user wants to watch
  or step in, restart the job with a real window (`--window`, WSLg env) instead.
- One screenshot for yourself (`scripts/qmpshot.py <qmp.sock> out.png`, copied back and Read) only
  to diagnose a stuck boot, not as a test.

## A job that seems stuck

1. `--once` and the log's last `#####` step: how long has it been there, compared with the others?
2. Is the VM up: `pgrep -af '[q]emu'` (its `hostfwd` port), ssh to it with the test's own options
   (`. scripts/common.sh` with its `VM_DIR`/`VM_PORT`): a known_hosts mismatch or "Permission
   denied" is a test setup problem, not the guest.
3. No ssh banner: take one screenshot. Firmware PXE/HTTP boot means no usable boot entry: read the
   UEFI variables from a copy of `vars.fd` (`virt-fw-vars -i <copy> --print`, package
   virt-firmware) and compare with a loader that works.
