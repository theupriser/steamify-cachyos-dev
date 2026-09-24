#!/bin/bash
# Screenshot the guest's Plasma session to a file on the host.
#   scripts/vmshot.sh [--clean] <out.png>
#   --clean  first close what starts with the session and covers the desktop
#            (Steam, CachyOS Hello) and the wizard's Konsole.
# spectacle started straight from SSH crashes; run it as a user unit so it
# gets the session's environment.
# Env: VM_USER (theupriser), VM_PORT (2222), VM_HOST (localhost), GUEST_UID (1000).
set -euo pipefail
. "$(dirname "$0")/common.sh"
clean=""
[[ "${1:-}" == --clean ]] && { clean=1; shift; }
out="${1:?usage: $0 [--clean] <out.png>}"
{ printf 'uid=%q clean=%q\n' "${GUEST_UID:-1000}" "$clean"; cat << 'REMOTE'
export XDG_RUNTIME_DIR=/run/user/$uid DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$uid/bus
rm -f /tmp/vmshot.png
if [ -n "$clean" ]; then
    # Steam as a whole: closing only its web helper leaves a black window.
    # It comes back at the next login (steam-desktop-autostart).
    steam -shutdown >/dev/null 2>&1 & sleep 5; pkill -u "$USER" -x steam; pkill -u "$USER" -x steamwebhelper
    pkill -u "$USER" cachyos-hello; pkill -u "$USER" -x konsole
    sleep 2
fi
sleep 2
systemd-run --user --wait -q spectacle -b -n -f -o /tmp/vmshot.png
REMOTE
} | vm_ssh bash -s
scp -q -P "$VM_PORT" "$VM_USER@$VM_HOST:/tmp/vmshot.png" "$out"
echo "$out"
