#!/bin/bash
# Download the latest CachyOS desktop ISO to cachyos.iso and verify its checksum.
# Re-running resumes a partial download; an up-to-date ISO is left alone.
set -euo pipefail
cd "$(dirname "$0")"

# CachyOS's own mirror: nl.mirror.cx gave about 1 MB/s here, this one 80 MB/s (MIRROR=... to use another).
mirror="${MIRROR:-https://mirror.cachyos.org}"

# The download page embeds the current ISO URL; take the release from it.
release="$(curl -fsL https://cachyos.org/download/ |
    grep -oE 'ISO/desktop/[0-9]+/cachyos-desktop-linux-[0-9]+\.iso' | head -n 1)"
if [[ -z "$release" ]]; then
    echo "Could not find the current ISO on cachyos.org/download" >&2
    exit 1
fi
url="$mirror/$release"
name="$(basename "$release")"
echo "Latest release: $name"

if [[ -f cachyos.iso && "$(cat cachyos.iso.version 2>/dev/null)" != "$name" ]]; then
    echo "Existing cachyos.iso is an older release, replacing it."
    rm -f cachyos.iso
fi

# The version is written before the download: a partial file of this release is resumed, not deleted as "an older release".
echo "$name" > cachyos.iso.version
curl -fL -C - -o cachyos.iso "$url"

echo "Verifying checksum..."
curl -fsL "$url.sha256" | awk '{print $1"  cachyos.iso"}' | sha256sum -c
