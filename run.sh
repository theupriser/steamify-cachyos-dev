#!/bin/bash
# CachyOS test VM for steamify.sh.
#   [REPO=/path/to/cachyos-gamescope-boot] ./run.sh [install] [--nvidia] [--vulkan] [--amd] [--fremont] [--headless]
#     install    boot the installer ISO
#     --nvidia   render the guest's virtio-gpu (virgl) on the host NVIDIA dGPU
#     --vulkan   expose Vulkan to the guest (venus; needed by gamescope, can be unstable)
#     --amd      with --vulkan: venus on the host AMD iGPU (RADV) instead of NVIDIA
#     --fremont  report the Valve Steam Machine's DMI data (for testing the wizard)
#     --headless no window (unattended tests, CI); a VM you start by hand has one. VM_HEADLESS=1 does the same
# REPO defaults to $HOME/projects/cachyos-gamescope-boot.
# VM_ISO=<path> boots that ISO for `install` instead of cachyos.iso; with
# VM_KERNEL/VM_INITRD/VM_APPEND its kernel is booted directly with those
# parameters (scripts/vminstall.sh, the unattended install).
# VM_MEM=<size>: guest RAM (8G; the automated tests use 4G so three VMs fit next to a desktop).
# VM_CPUS=<n>: guest CPUs (6); ISO builds use ~75% of host cores (nproc * 3 / 4), so the host stays usable.
# VM_PORT=<n>: the host port for the guest's SSH (2222), e.g. a second VM.
# BIOS_VERSION=F7F0107 makes the guest report that BIOS version (DMI), e.g.
# to test the wizard's BIOS update item; the firmware itself doesn't change.
# The repo is shared into the guest; mount it there with:
#   sudo mount -t 9p -o trans=virtio,version=9p2000.L repo /mnt
# First-time SSH setup, inside the guest:
#   sudo mount -t 9p -o trans=virtio,version=9p2000.L vmtools /media && /media/guest-ssh-setup.sh
# SSH from the host: ssh -p 2222 <user>@localhost
cd "$(dirname "$0")"
# REPO: from the environment, else what scripts/vminstall.sh recorded next
# to the disk (repo-path), else the old default.
[[ -z "${REPO:-}" && -f repo-path ]] && REPO="$(cat repo-path)"
repo="${REPO:-$HOME/projects/cachyos-gamescope-boot}"

cdrom=()
direct=()
[[ -n "${VM_KERNEL:-}" ]] && direct=(-kernel "$VM_KERNEL" -initrd "$VM_INITRD" -append "$VM_APPEND")
# VM_CACHE=<host dir>: shared read-write as 9p tag `cache` (the ISO build's
# package cache, scripts/vmisobuild.sh; one per VM, e.g. $VM_DIR/iso-cache),
# so snapshot resets don't lose it.
[[ -n "${VM_CACHE:-}" ]] && { mkdir -p "$VM_CACHE"; direct+=(-virtfs "local,path=$VM_CACHE,mount_tag=cache,security_model=mapped-xattr"); }
# VM_SERIAL=<file>: the guest's serial console (console=ttyS0) logged into
# that file, and reachable as a socket next to it (<file>.sock) to type into.
[[ -n "${VM_SERIAL:-}" ]] && direct+=(-chardev "socket,id=ser0,path=$VM_SERIAL.sock,server=on,wait=off,logfile=$VM_SERIAL" -serial chardev:ser0)
smbios=()
gpu=virtio-vga-gl,xres=1920,yres=1080 gl=on
# VM_NOGL=1: no virgl (software rendering in the guest), so QMP screendump
# works (scripts/qmpshot.py); for the live ISO and Calamares.
[[ -n "${VM_NOGL:-}" ]] && { gpu=virtio-vga,xres=1920,yres=1080; gl=off; }
[[ -n "${BIOS_VERSION:-}" ]] && smbios+=(-smbios "type=0,version=$BIOS_VERSION")
for arg in "$@"; do
    case "$arg" in
        install)  cdrom=(-cdrom "${VM_ISO:-cachyos.iso}" -boot d) ;;
        --nvidia) export __NV_PRIME_RENDER_OFFLOAD=1 __GLX_VENDOR_LIBRARY_NAME=nvidia \
                         __EGL_VENDOR_LIBRARY_FILENAMES=/usr/share/glvnd/egl_vendor.d/10_nvidia.json ;;
        --vulkan) gpu+=,hostmem=4G,blob=true,venus=true ;;
        --amd) export VK_DRIVER_FILES=/usr/share/vulkan/icd.d/radeon_icd.json ;;
        --headless) VM_HEADLESS=1 ;;
        --fremont) smbios+=(-smbios type=1,manufacturer=Valve,product=Fremont -smbios type=2,manufacturer=Valve,product=Fremont) ;;
        *) echo "unknown argument: $arg" >&2; exit 1 ;;
    esac
done

# VM_HEADLESS=1: no window (unattended tests, CI): plain virtio-vga and -display none;
# QMP screendump works then too. The guest and ssh don't notice.
display=(-display "gtk,gl=$gl,zoom-to-fit=off")
[[ -n "${VM_HEADLESS:-}" ]] && { gpu=virtio-vga,xres=1920,yres=1080; display=(-display none); }

# UEFI firmware: Ubuntu's path, or Arch's (edk2-ovmf).
ovmf=/usr/share/OVMF; ovmf_code=OVMF_CODE_4M.fd; ovmf_vars=OVMF_VARS_4M.fd
[[ -f "$ovmf/$ovmf_code" ]] || { ovmf=/usr/share/edk2/x64; ovmf_code=OVMF_CODE.4m.fd; ovmf_vars=OVMF_VARS.4m.fd; }

# First run: create the disk and the writable UEFI variable store.
[[ -f disk.qcow2 ]] || qemu-img create -f qcow2 disk.qcow2 60G
[[ -f vars.fd ]] || cp "$ovmf/$ovmf_vars" vars.fd

# Hand the host's public keys to the guest setup script.
cat ~/.ssh/*.pub > share/host-keys.pub

exec qemu-system-x86_64 \
    -enable-kvm -machine q35,memory-backend=mem -cpu host -smp "${VM_CPUS:-6}" -m "${VM_MEM:-8G}" \
    -object memory-backend-memfd,id=mem,size=${VM_MEM:-8G},share=on \
    -drive if=pflash,format=raw,readonly=on,file="$ovmf/$ovmf_code" \
    -drive if=pflash,format=raw,file=vars.fd \
    -drive file=disk.qcow2,if=virtio \
    -device "$gpu" "${display[@]}" \
    -device qemu-xhci -device usb-tablet \
    -nic user,model=virtio-net-pci,hostfwd=tcp::${VM_PORT:-2222}-:22 \
    -virtfs local,path="$repo",mount_tag=repo,security_model=mapped-xattr \
    -virtfs local,path="$PWD/share",mount_tag=vmtools,security_model=mapped-xattr,readonly=on \
    -qmp unix:"$PWD/qmp.sock",server=on,wait=off \
    "${smbios[@]}" "${cdrom[@]}" "${direct[@]}"
