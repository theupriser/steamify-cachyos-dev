#!/bin/bash
# Boot a live ISO (the Steam Machine ISO) in its own VM, the normal way, to go
# through Calamares by hand or driven with scripts/qmpkey.py / qmptype.py,
# with screenshots of every page (scripts/qmpshot.py; no virgl, so QMP
# screendump works). Unlike vminstall.sh nothing is automated: the wizard,
# its Steamify pages and the installer's Steamify step run as on real
# hardware. Starts in the background; the VM's window is where you watch.
#   scripts/vmisoboot.sh [--fresh] [--iso <file>] [run.sh flags...]   e.g. --fremont
#   --fresh      a new, empty disk (else the existing one: e.g. boot the
#                installed system with `./run.sh` in $VM_DIR afterwards)
#   --iso <file> default: the newest out/desktop/*.iso of the host's
#                steamify-cachyos-live-iso checkout
# Env: ISO_VM_DIR (~/vms/iso-vm), ISO_VM_PORT (2223: runs next to the test
#      VM on 2222).
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/.." && pwd)"
dir="${ISO_VM_DIR:-$HOME/vms/iso-vm}"
port="${ISO_VM_PORT:-2223}"
fresh=false iso="" flags=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --fresh) fresh=true; shift ;;
        --iso) iso="${2:?--iso needs a file}"; shift 2 ;;
        *) flags+=("$1"); shift ;;
    esac
done
if [[ -z "$iso" ]]; then
    iso="$(ls -t "$(dirname "$repo")"/steamify-cachyos-live-iso/out/desktop/*.iso 2>/dev/null | head -1)"
    [[ -n "$iso" ]] || { echo "No ISO in steamify-cachyos-live-iso/out/desktop: build one (vmisobuild.sh) or pass --iso." >&2; exit 1; }
fi
iso="$(cd "$(dirname "$iso")" && pwd)/$(basename "$iso")"
mkdir -p "$dir"
cd "$dir"
[[ -S qmp.sock ]] && python3 -c "import socket,sys; s=socket.socket(socket.AF_UNIX); s.connect(sys.argv[1])" qmp.sock 2>/dev/null &&
    { echo "The ISO VM in $dir is running already." >&2; exit 1; }
cp "$repo/run.sh" run.sh
[[ -e share ]] || ln -s "$repo/share" share
if [[ "$fresh" == true ]]; then rm -f disk.qcow2 vars.fd; fi
REPO="${REPO:-$(dirname "$repo")/steamify-cachyos}" VM_NOGL=1 VM_PORT="$port" VM_ISO="$iso" \
    nohup ./run.sh install "${flags[@]}" > vm.log 2>&1 &
echo "ISO VM: $iso in $dir (SSH port $port once installed)."
echo "Screenshot: python3 $here/qmpshot.py $dir/qmp.sock shot.png"
echo "Keys:       python3 $here/qmpkey.py $dir/qmp.sock down ret   /   qmptype.py $dir/qmp.sock \"text\""
