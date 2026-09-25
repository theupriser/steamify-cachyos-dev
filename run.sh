#!/bin/bash
# CachyOS test VM for steamify.sh.
#   [REPO=/path/to/cachyos-gamescope-boot] ./run.sh [install] [--nvidia] [--vulkan] [--fremont]
#     install    boot the installer ISO
#     --nvidia   render the guest's virtio-gpu (virgl) on the host NVIDIA dGPU
#     --vulkan   expose Vulkan to the guest (venus; needed by gamescope, can be unstable)
#     --fremont  report the Valve Steam Machine's DMI data (for testing the wizard)
# REPO defaults to $HOME/projects/cachyos-gamescope-boot.
# BIOS_VERSION=F7F0107 makes the guest report that BIOS version (DMI), e.g.
# to test the wizard's BIOS update item; the firmware itself doesn't change.
# The repo is shared into the guest; mount it there with:
#   sudo mount -t 9p -o trans=virtio,version=9p2000.L repo /mnt
# First-time SSH setup, inside the guest:
#   sudo mount -t 9p -o trans=virtio,version=9p2000.L vmtools /media && /media/guest-ssh-setup.sh
# SSH from the host: ssh -p 2222 <user>@localhost
cd "$(dirname "$0")"
repo="${REPO:-$HOME/projects/cachyos-gamescope-boot}"

cdrom=()
smbios=()
gpu=virtio-vga-gl,xres=1920,yres=1080
[[ -n "${BIOS_VERSION:-}" ]] && smbios+=(-smbios "type=0,version=$BIOS_VERSION")
for arg in "$@"; do
    case "$arg" in
        install)  cdrom=(-cdrom cachyos.iso -boot d) ;;
        --nvidia) export __NV_PRIME_RENDER_OFFLOAD=1 __GLX_VENDOR_LIBRARY_NAME=nvidia \
                         __EGL_VENDOR_LIBRARY_FILENAMES=/usr/share/glvnd/egl_vendor.d/10_nvidia.json ;;
        --vulkan) gpu+=,hostmem=4G,blob=true,venus=true ;;
        --fremont) smbios+=(-smbios type=1,manufacturer=Valve,product=Fremont -smbios type=2,manufacturer=Valve,product=Fremont) ;;
        *) echo "unknown argument: $arg" >&2; exit 1 ;;
    esac
done

# First run: create the disk and the writable UEFI variable store.
[[ -f disk.qcow2 ]] || qemu-img create -f qcow2 disk.qcow2 60G
[[ -f vars.fd ]] || cp /usr/share/OVMF/OVMF_VARS_4M.fd vars.fd

# Hand the host's public keys to the guest setup script.
cat ~/.ssh/*.pub > share/host-keys.pub

exec qemu-system-x86_64 \
    -enable-kvm -machine q35,memory-backend=mem -cpu host -smp 6 -m 8G \
    -object memory-backend-memfd,id=mem,size=8G,share=on \
    -drive if=pflash,format=raw,readonly=on,file=/usr/share/OVMF/OVMF_CODE_4M.fd \
    -drive if=pflash,format=raw,file=vars.fd \
    -drive file=disk.qcow2,if=virtio \
    -device "$gpu" -display gtk,gl=on,zoom-to-fit=off \
    -device qemu-xhci -device usb-tablet \
    -nic user,model=virtio-net-pci,hostfwd=tcp::2222-:22 \
    -virtfs local,path="$repo",mount_tag=repo,security_model=mapped-xattr \
    -virtfs local,path="$PWD/share",mount_tag=vmtools,security_model=mapped-xattr,readonly=on \
    -qmp unix:"$PWD/qmp.sock",server=on,wait=off \
    "${smbios[@]}" "${cdrom[@]}"
