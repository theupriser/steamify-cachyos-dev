# Sourced by the other scripts: SSH target of the test VM.
VM_PORT="${VM_PORT:-2222}"
VM_HOST="${VM_HOST:-localhost}"
# Where disk.qcow2, vars*.fd and run.sh live: this repo if it has a disk,
# else ~/vms/cachyos-test.
_repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ -z "${VM_DIR:-}" ]]; then
    if [[ -f "$_repo/disk.qcow2" ]]; then VM_DIR="$_repo"; else VM_DIR="$HOME/vms/cachyos-test"; fi
fi
# The guest user: what scripts/vminstall.sh created ($VM_DIR/vm-user), else
# theupriser (VMs installed by hand).
if [[ -z "${VM_USER:-}" && -f "$VM_DIR/vm-user" ]]; then VM_USER="$(cat "$VM_DIR/vm-user")"; fi
VM_USER="${VM_USER:-theupriser}"
# scripts/vminstall.sh records the key it authorized in $VM_DIR/ssh-key.
# The VM's host key lives next to its disk, never in ~/.ssh/known_hosts: a
# reinstalled VM gets a new one on the same localhost port.
VM_SSH_OPTS=(-o BatchMode=yes -o "UserKnownHostsFile=$VM_DIR/known_hosts" -o StrictHostKeyChecking=accept-new)
if [[ -z "${VM_SSH_KEY:-}" && -f "$VM_DIR/ssh-key" ]]; then VM_SSH_KEY="$(cat "$VM_DIR/ssh-key")"; fi
[[ -n "${VM_SSH_KEY:-}" ]] && VM_SSH_OPTS+=(-i "$VM_SSH_KEY" -o IdentitiesOnly=yes)
vm_ssh() { ssh -p "$VM_PORT" "${VM_SSH_OPTS[@]}" "$VM_USER@$VM_HOST" "$@"; }
vm_scp() { scp -q -P "$VM_PORT" "${VM_SSH_OPTS[@]}" "$@"; }
