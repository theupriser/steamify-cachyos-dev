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
# The VM's key, looked up at every call: vminstall.sh and vmbootloadertest.sh source this file before the key
# exists or is chosen (a clean host has no other key the VM would accept).
vm_key() {
    if [[ -n "${VM_SSH_KEY:-}" ]]; then printf '%s\n' "$VM_SSH_KEY"
    elif [[ -f "$VM_DIR/ssh-key" ]]; then cat "$VM_DIR/ssh-key"; fi
}
_vm_key_opts() { local k; k="$(vm_key)"; [[ -n "$k" ]] && printf '%s\n' -i "$k" -o IdentitiesOnly=yes; }
vm_ssh() { local -a k; mapfile -t k < <(_vm_key_opts); ssh -p "$VM_PORT" "${VM_SSH_OPTS[@]}" "${k[@]}" "$VM_USER@$VM_HOST" "$@"; }
vm_scp() { local -a k; mapfile -t k < <(_vm_key_opts); scp -q -P "$VM_PORT" "${VM_SSH_OPTS[@]}" "${k[@]}" "$@"; }

# One Konsole for every test run: it follows $TEST_LOG, which the test scripts append to.
# Started only when there is a desktop, the run is headless and no such window exists.
TEST_LOG="${TEST_LOG:-$HOME/vms/test.log}"
view_start() {
    [[ -n "${VM_HEADLESS:-}" && -z "${CI:-}" && -n "${WAYLAND_DISPLAY:-}${DISPLAY:-}" ]] && command -v konsole >/dev/null || return 0
    systemctl --user is-active --quiet vmtest-view 2>/dev/null && return 0
    mkdir -p "$(dirname "$TEST_LOG")"; touch "$TEST_LOG"
    systemd-run --user -q --collect --unit=vmtest-view konsole --hold -e tail -n 60 -F "$TEST_LOG" >/dev/null 2>&1 || true
}
