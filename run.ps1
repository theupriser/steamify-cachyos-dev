# CachyOS test VM for steamify.sh -- Windows version.
#   .\run.ps1 [-Install]
# Needs QEMU for Windows (https://qemu.weilnetz.de/w64/) and the Windows
# feature "Windows Hypervisor Platform" (for -accel whpx).
# Windows QEMU has no 9p shared folders: copy the repo in over SSH instead:
#   scp -P 2222 -r ..\..\projects\cachyos-gamescope-boot <user>@localhost:
param([switch]$Install)
$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

$qemuDir = if ($env:QEMU_DIR) { $env:QEMU_DIR } else { 'C:\Program Files\qemu' }
$qemu = Join-Path $qemuDir 'qemu-system-x86_64.exe'
$code = Join-Path $qemuDir 'share\edk2-x86_64-code.fd'

if (-not (Test-Path vars.fd)) { Copy-Item (Join-Path $qemuDir 'share\edk2-i386-vars.fd') vars.fd }
if (-not (Test-Path disk.qcow2)) { & (Join-Path $qemuDir 'qemu-img.exe') create -f qcow2 disk.qcow2 60G | Out-Null }

$qargs = @(
    '-accel', 'whpx,kernel-irqchip=off', '-machine', 'q35', '-cpu', 'max', '-smp', '6', '-m', '8G',
    '-drive', "if=pflash,format=raw,readonly=on,file=$code",
    '-drive', 'if=pflash,format=raw,file=vars.fd',
    '-drive', 'file=disk.qcow2,if=virtio',
    '-device', 'virtio-vga,xres=1920,yres=1080', '-display', 'sdl',
    '-device', 'qemu-xhci', '-device', 'usb-tablet',
    '-nic', 'user,model=virtio-net-pci,hostfwd=tcp::2222-:22'
)
if ($Install) { $qargs += @('-cdrom', 'cachyos.iso', '-boot', 'd') }

& $qemu @qargs
