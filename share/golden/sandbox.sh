#!/bin/bash
# Run a command in a throw-away copy of a machine described by a fixture folder (no VM, no root).
#   share/golden/sandbox.sh <fixture> <command>...
# <fixture>/etc/**, <fixture>/sys/**, <fixture>/usr/** : files shown at those places (the rest of /etc and /sys is empty)
# <fixture>/home/                                       : the user's home (fresh copy each run)
# <fixture>/packages, enabled-units, active-units       : answers of the fake pacman and systemctl (shims/)
# <fixture>/env                                         : optional VAR=value lines for the command
# Needs bubblewrap. $GOLDEN_LOG collects the writes the shims were asked to make.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
fixture="$(cd "${1:?usage: $0 <fixture> <command>...}" && pwd)"; shift
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
mkdir -p "$work/home" "$work/fixture"
cp -a "$fixture/." "$work/fixture/"
[[ -d "$fixture/home" ]] && cp -a "$fixture/home/." "$work/home/"
arguments=(--die-with-parent --unshare-pid --ro-bind / / --dev /dev --proc /proc --tmpfs /tmp --tmpfs /sys --tmpfs /etc
    --bind "$work/home" "$HOME" --bind "$work/fixture" /mnt --ro-bind "$here/shims" /media)
[[ -n "${REPO:-}" ]] && arguments+=(--ro-bind "$REPO" "$REPO")
for keep in passwd group nsswitch.conf ld.so.cache ld.so.conf ld.so.conf.d localtime alternatives resolv.conf hostname; do
    [[ -e "/etc/$keep" ]] && arguments+=(--ro-bind "/etc/$keep" "/etc/$keep")
done
for root in etc sys; do
    [[ -d "$fixture/$root" ]] || continue
    while IFS= read -r -d '' file; do
        arguments+=(--ro-bind "$work/fixture/${file#"$fixture/"}" "/${file#"$fixture/"}")
    done < <(find "$fixture/$root" -type f -print0)
done
environment=(--setenv FIXTURE /mnt --setenv PATH "/media:$PATH" --setenv GOLDEN_LOG "${GOLDEN_LOG:-/mnt/writes.log}")
[[ -f "$fixture/env" ]] && while IFS= read -r line; do
    [[ "$line" == *=* ]] && environment+=(--setenv "${line%%=*}" "${line#*=}")
done < "$fixture/env"
exec bwrap "${arguments[@]}" "${environment[@]}" "$@"
