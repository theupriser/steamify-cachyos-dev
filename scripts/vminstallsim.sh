#!/bin/bash
# Simulate the Steam Machine ISO's installer step in the test VM: a new user
# who never logged in (no session bus, user systemd or plasmashell) gets
# `steamify.sh --defaults` from /mnt, visibly in a Konsole on the VM's
# desktop. Prints the per-component result lines.
#   scripts/vminstallsim.sh [--fresh] [--defaults options...]
#       --fresh: delete and recreate the user first; the rest goes to
#       --defaults (e.g. --options gaming,theme --boot desktop)
# Env: VM_USER / VM_PORT / VM_HOST, SIM_USER (isotest), GUEST_UID (1000).
set -euo pipefail
. "$(dirname "$0")/common.sh"
fresh=""; [[ "${1:-}" == --fresh ]] && { fresh=1; shift; }
{ printf 'u=%q fresh=%q uid=%q opts=%q\n' "${SIM_USER:-isotest}" "$fresh" "${GUEST_UID:-1000}" "$*"; cat << 'REMOTE'
mountpoint -q /mnt || sudo mount -t 9p -o trans=virtio,version=9p2000.L repo /mnt
[ -n "$fresh" ] && sudo userdel -r "$u" 2>/dev/null
cat > /tmp/install-sim.sh << SIM
#!/bin/bash
id $u >/dev/null 2>&1 || { sudo useradd -m -G wheel -s /bin/bash $u; echo "$u:$u" | sudo chpasswd; }
echo "$u ALL=(ALL) NOPASSWD: ALL" | sudo tee /etc/sudoers.d/10-steamify-install-sim >/dev/null
sudo -u $u env -i HOME=/home/$u USER=$u LOGNAME=$u PATH=/usr/local/bin:/usr/bin TERM=xterm LANG=C.UTF-8 \
    bash -c 'cd ~ && /mnt/steamify.sh --defaults $opts < /dev/null' 2>&1 | tee /tmp/install-sim.log
echo "exit: \${PIPESTATUS[0]}" | tee -a /tmp/install-sim.log
sudo rm -f /etc/sudoers.d/10-steamify-install-sim
touch /tmp/install-sim.done
SIM
chmod +x /tmp/install-sim.sh; rm -f /tmp/install-sim.done
XDG_RUNTIME_DIR=/run/user/$uid DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$uid/bus \
    systemd-run --user -q konsole --hold -e /tmp/install-sim.sh
while [ ! -f /tmp/install-sim.done ]; do sleep 3; done
sed 's/\x1b\[[0-9;]*m//g' /tmp/install-sim.log | grep -E '^Turning|^\[(WARN|ERROR|OK)\]|^exit'
REMOTE
} | vm_ssh bash -s 2>&1
