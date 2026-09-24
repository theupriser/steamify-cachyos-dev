#!/bin/bash
# Run the wizard inside the guest's Plasma session with scripted menu input.
#   scripts/vmrun.sh '<menu input>'      e.g. scripts/vmrun.sh '\ny\nn\n'
# Input is interpreted by printf: numbers toggle, empty line continues,
# a = re-apply, q = quit; then y for "Go ahead?" and n for the restart question.
# Env: VM_USER (theupriser), VM_PORT (2222), VM_HOST (localhost),
#      GUEST_REPO (/mnt, where the repo is mounted in the guest), GUEST_UID (1000).
set -euo pipefail
. "$(dirname "$0")/common.sh"
input="${1:?usage: $0 '<menu input>'}"
GUEST_REPO="${GUEST_REPO:-/mnt}"
GUEST_UID="${GUEST_UID:-1000}"
# The guest login shell is fish, so pass values in through the bash script itself.
{ printf 'input=%q repo=%q uid=%q\n' "$input" "$GUEST_REPO" "$GUEST_UID"; cat << 'REMOTE'
export XDG_RUNTIME_DIR=/run/user/$uid WAYLAND_DISPLAY=wayland-0 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$uid/bus
log=/tmp/wizard.log
# shellcheck disable=SC2059
printf "$input" | "$repo/steamify.sh" > "$log" 2>&1; echo "exit=$?" >> "$log"
cat "$log"
REMOTE
} | vm_ssh bash -s 2>&1 | sed 's/\x1b\[[0-9;]*m//g'
