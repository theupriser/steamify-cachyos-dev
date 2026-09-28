#!/bin/bash
# Authorize the test VM's SSH key (made by vminstall.sh) on the Steam Machine
# too, so the same key reaches both. Asks the Steam Machine user's password
# once (ssh-copy-id); adds the key only if it isn't there yet.
#   scripts/steammachine-addkey.sh [user@host]     default: steammachine (~/.ssh/config)
# Env: VM_SSH_KEY (default ~/.ssh/steamify-vm_ed25519).
set -euo pipefail
key="${VM_SSH_KEY:-$HOME/.ssh/steamify-vm_ed25519}"
target="${1:-steammachine}"
[[ -f "$key.pub" ]] || { echo "No $key.pub: run scripts/vminstall.sh first (it makes the key)." >&2; exit 1; }
ssh-copy-id -i "$key.pub" "$target"
ssh -i "$key" -o IdentitiesOnly=yes -o BatchMode=yes "$target" true &&
    echo "OK: ssh -i $key $target works without a password."
