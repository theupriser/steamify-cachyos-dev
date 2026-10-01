#!/bin/bash
# Build the Steam Machine ISO (steamify-cachyos-live-iso) in the test VM
# (directly, no container: build-live-modules.sh and build-calamares-modules.sh with sudo, buildiso.sh as
# the user, it sudos itself),
# visibly (a Konsole on the VM's desktop follows the log), with the package
# downloads cached on the host, and copy the ISO back.
#   scripts/vmisobuild.sh [--steamify <guest path>]
#     --steamify  a Steamify checkout in the guest (e.g. /mnt, the mounted
#                 REPO) instead of the newest release
# The VM must run with its cache shared (one per VM, next to its disk), and
# gets all host cores but 2 for the build: start it with
#   VM_CACHE=$VM_DIR/iso-cache VM_CPUS=$(( $(nproc) * 3 / 4 )) scripts/vmreset.sh --fremont
# Env: VM_DIR (see common.sh), ISO_BRANCH (master), ISO_OUT (the host's
#      steamify-cachyos-live-iso/out/desktop).
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
. "$here/common.sh"
steamify=""
[[ "${1:-}" == --steamify ]] && steamify="${2:?--steamify needs a guest path}"
branch="${ISO_BRANCH:-master}"
# Where the ISO lands: out/desktop of the host's live-ISO checkout (next to
# this repo), where a local build would put it.
out="${ISO_OUT:-$(dirname "$(cd "$here/.." && pwd)")/steamify-cachyos-live-iso/out/desktop}"
mkdir -p "$out"

{ printf 'branch=%q steamify=%q\n' "$branch" "$steamify"; cat << 'REMOTE'
set -e
export XDG_RUNTIME_DIR=/run/user/$(id -u) DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id -u)/bus
# The package cache on the host (9p tag `cache`), kept across snapshot resets,
# is the VM's pacman cache: the build tools and mkarchiso (which installs the
# ISO's packages with the build system's cache) both use it. No container:
# the VM is CachyOS already, and a snapshot reset removes the build tools.
sudo mkdir -p /var/cache/steamify-iso
mountpoint -q /var/cache/steamify-iso || sudo mount -t 9p -o trans=virtio,version=9p2000.L cache /var/cache/steamify-iso ||
    { echo "No 9p share 'cache': start the VM with VM_CACHE=<host dir> (run.sh)." >&2; exit 1; }
sudo mkdir -p /var/cache/steamify-iso/pkg
mountpoint -q /var/cache/pacman/pkg || sudo mount --bind /var/cache/steamify-iso/pkg /var/cache/pacman/pkg
[ -z "$steamify" ] || mountpoint -q /mnt || sudo mount -t 9p -o trans=virtio,version=9p2000.L repo /mnt
# archlinux.cachyos.org serves packages without their .sig (404), and pacman
# doesn't try the next mirror for the signature of a cached package: the
# build fails. mkarchiso uses this mirrorlist, so skip it here.
sudo sed -i '/archlinux\.cachyos\.org/s/^Server/#Server/' /etc/pacman.d/mirrorlist
sudo pacman -Sy --needed --noconfirm archiso mkinitcpio-archiso git squashfs-tools grub >/dev/null
iso=~/projects/steamify-cachyos-live-iso
if [ -d "$iso/.git" ]; then git -C "$iso" fetch -q && git -C "$iso" checkout -q "$branch" && git -C "$iso" reset -q --hard "origin/$branch"
else mkdir -p ~/projects && git clone -q -b "$branch" https://github.com/theupriser/steamify-cachyos-live-iso "$iso"; fi
cd "$iso" && echo "ISO repo: $(git log --oneline -1)"
./steamify-prepare.sh $steamify | tail -1
sudo rm -rf build out
cat > ~/projects/iso-build.sh << S
#!/bin/bash
cd $iso
sudo ./build-live-modules.sh && sudo ./build-calamares-modules.sh && { ./buildiso.sh -p desktop -w || ./buildiso.sh -p desktop -c -w; }
echo "== BUILD EXIT \$?"
ls -la out/desktop/*.iso 2>/dev/null
S
chmod +x ~/projects/iso-build.sh; : > ~/projects/iso-build.log
systemd-run --user --collect -q -u "isobuild-$(date +%s)" bash -c "~/projects/iso-build.sh > ~/projects/iso-build.log 2>&1"
systemd-run --user -q --setenv=XDG_CURRENT_DESKTOP=KDE konsole --separate --hold -e bash -c "tail -n 50 -F ~/projects/iso-build.log"
REMOTE
} | vm_ssh bash -s
echo "Building in the VM (its Konsole shows the log)..."
until vm_ssh 'grep -q "^== BUILD EXIT" ~/projects/iso-build.log'; do sleep 30; done
iso="$(vm_ssh "bash -c 'ls -t ~/projects/steamify-cachyos-live-iso/out/desktop/*.iso 2>/dev/null | head -1'")"
[[ -n "$iso" ]] || { echo "No ISO was built; see ~/projects/iso-build.log in the VM." >&2; exit 1; }
vm_scp "$VM_USER@$VM_HOST:$iso" "$out/"
echo "ISO: $out/$(basename "$iso")  (cache: $VM_DIR/iso-cache)"
