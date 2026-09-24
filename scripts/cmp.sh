#!/bin/bash
# Diff the guest's KDE/GTK configs against a saved baseline.
#   scripts/cmp.sh save   copy the current ~/.config files to the baseline
#   scripts/cmp.sh        show differences against the baseline
# Env: VM_USER (theupriser), VM_PORT (2222), VM_HOST (localhost),
#      BASELINE (guest dir, default ~/.cache/vm-baseline; not /tmp, which is cleared on reboot).
set -euo pipefail
. "$(dirname "$0")/common.sh"
mode="${1:-diff}"
# The guest login shell is fish, so pass values in through the bash script itself.
{ printf 'mode=%q base=%q\n' "$mode" "${BASELINE:-}"; cat << 'REMOTE'
base="${base:-$HOME/.cache/vm-baseline}"
files="kdeglobals kcminputrc ksplashrc plasmarc plasmashellrc kwinrc kwinrulesrc konsolerc kscreenlockerrc kglobalshortcutsrc gtk-3.0/settings.ini gtk-4.0/settings.ini plasma-org.kde.plasma.desktop-appletsrc"
if [ "$mode" = save ]; then
  for f in $files; do mkdir -p "$(dirname "$base/config/$f")"; cp -f ~/.config/"$f" "$base/config/$f" 2>/dev/null || true; done
  echo "baseline saved to $base"; exit 0
fi
noise='^(ColorSchemeHash|popupHeight|popupWidth|ItemGeometries|ItemGeometriesHorizontal|DialogHeight|DialogWidth|[0-9]+ screens: )'
for f in $files; do
  d=$(diff <(sort -u "$base/config/$f" 2>/dev/null | grep -vE "$noise") <(sort -u ~/.config/"$f" 2>/dev/null | grep -vE "$noise") | grep '^[<>]' || true)
  [ -n "$d" ] && { echo "== $f"; echo "$d" | head -25; }
done
echo "(end of diff)"
REMOTE
} | vm_ssh bash -s 2>&1
