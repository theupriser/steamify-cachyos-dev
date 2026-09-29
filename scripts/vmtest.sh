#!/bin/bash
# The whole boot loader test in one command: every boot loader the Steamify ISO
# advertises, each on its own VM (~/vms/bl-<loader>), one after the other.
#   scripts/vmtest.sh [--install] [--window] [loader...]     default: all advertised loaders
#   --install  install each VM first from the newest Steamify ISO (asks before replacing a disk)
#   --window   show the VMs' windows (default: headless; on a desktop one Konsole follows all the logs)
# Checks per loader (scripts/vmbootloadertest.sh + share/bootloader-test/):
#   Steamify's state as its menu sees it, OS name untouched, loader identity,
#   DKMS modules for every kernel, Steamify's loader-specific code, a kernel
#   update, a reboot into each kernel. Add a check there, and it runs here.
# Prints one line per loader and the failed checks; exit status = failures.
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/.." && pwd)"
iso_repo="$repo/../steammachine-cachyos-live-iso"
install=""; window=""; loaders=()
for a in "$@"; do
    case "$a" in --install) install=--install ;; --window) window=--window ;; *) loaders+=("$a") ;; esac
done
# What the ISO advertises: the boot loaders calamares-online.sh keeps.
advertised="$(sed -n 's/.*"bootloader:\([^"]*\)".*/\1/p' "$iso_repo/archiso/airootfs/usr/local/bin/calamares-online.sh" 2>/dev/null | head -n 1)"
[[ -n "$advertised" ]] || { echo "Can't read the advertised boot loaders from $iso_repo (calamares-online.sh)" >&2; exit 2; }
[[ ${#loaders[@]} -gt 0 ]] || read -r -a loaders <<< "$advertised"
tested="limine systemd-boot grub"   # the loaders vmbootloadertest.sh has a way to boot the other kernel for
missing=0
for l in $advertised; do
    [[ " $tested " == *" $l "* ]] || { echo "FAIL the ISO advertises $l, but there is no test for it (scripts/vmbootloadertest.sh)"; missing=$((missing + 1)); }
done
total=$missing
# No human is needed: headless; the scripts share one Konsole (common.sh, $TEST_LOG).
for l in "${loaders[@]}"; do
    "$here/vmbootloadertest.sh" "$l" $install $window > "/tmp/vmtest-$l.out" 2>&1; rc=$?
    sed -n '/^== /,$p' "/tmp/vmtest-$l.out"
    total=$((total + rc))
done
echo; echo "== total: $total failed check(s) for: ${loaders[*]} (advertised: $advertised)"
exit "$total"
