#!/bin/bash
# Wake the VM from sleep (suspend to RAM), e.g. after the TV's power button
# in the HDMI-CEC test. Uses the QMP socket run.sh opens in the VM directory.
# Env: VM_DIR (the repo if it holds disk.qcow2, else ~/vms/cachyos-test).
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
VM_DIR="${VM_DIR:-$([[ -f "$here/disk.qcow2" ]] && echo "$here" || echo "$HOME/vms/cachyos-test")}"
sock="$VM_DIR/qmp.sock"
[[ -S "$sock" ]] || { echo "No QMP socket at $sock (VM not running, or started before run.sh had -qmp)." >&2; exit 1; }
printf '%s\n' '{"execute":"qmp_capabilities"}' '{"execute":"system_wakeup"}' |
    socat -t 2 - UNIX-CONNECT:"$sock" 2>/dev/null | grep -c '"return"' >/dev/null && echo "Wake-up sent."
