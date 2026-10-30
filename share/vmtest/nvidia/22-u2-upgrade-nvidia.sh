# since: 2.14.3
# U2 (upgrade 2.14.2 -> 2.14.3, NVIDIA PC): a PC with the SteamOS conversion set up by Steamify 2.14.2 (released bundle) and the patched gamescope 3.16.31-3
# (what such a PC had before 3.17.0; GitHub unreachable for the old run, so it keeps that one), then this version applied over it: the conversion shows as an update,
# one run lists Steamify's repository (with its database) and brings the newest patched gamescope, the smoke test passes, a second run changes nothing.
fake_nvidia
old=/tmp/steamify-2.14.2.sh
curl -fsL --retry 2 --max-time 120 https://github.com/theupriser/steamify-cachyos/releases/download/v2.14.2/steamify.sh -o "$old" || { skip "U2 no download of the 2.14.2 bundle"; exit 0; }
oldsf() { bash "$old" "$@" < /dev/null 2>&1 | sed 's/\x1b\[[0-9;]*m//g'; return "${PIPESTATUS[0]}"; }
sudo pacman -S --needed --noconfirm vulkan-swrast > /tmp/swrast.log 2>&1   # gamescope's smoke test needs a Vulkan device (lavapipe)
v="$(gsn_cpu_variant)"; f="steamify-gamescope-nvidia-3.16.31-3-$v.pkg.tar.zst"
# Steamify's pacman repository keeps older versions (the sync archives every release); the source repo's release is the fallback.
for u in https://github.com/theupriser/steamify-pacman-repo/releases/download/repo https://github.com/theupriser/steamify-gamescope-nvidia/releases/download/3.16.31-3; do
    curl -fsL --retry 2 --max-time 300 "$u/$f" -o "/tmp/$f" && break
done
[[ -s "/tmp/$f" ]] || { skip "U2 no download of the 3.16.31-3 package"; exit 0; }
sudo pacman -U --noconfirm --ask 4 "/tmp/$f" > /tmp/u2-pre.log 2>&1 || { fail "U2 could not install the old patched gamescope: $(tail -n 3 /tmp/u2-pre.log | tr "\n" " ")"; exit 0; }
[[ "$(pacman -Q steamify-gamescope-nvidia | awk '{print $2}')" == 3.16.31-3 ]] && pass "U2 2.14.2 state: patched gamescope 3.16.31-3 ($v)" || fail "U2 old package not installed"

info "U2 the 2.14.2 conversion (GitHub unreachable: the installed package stays)..."
GSN_RELEASES=http://127.0.0.1:9 oldsf --defaults --options gaming >/tmp/u2-old.txt; rc=$?
[[ $rc -eq 0 ]] && pass "U2 2.14.2 conversion applied, exit 0" || { fail "U2 2.14.2 conversion: exit $rc: $(tail -n 4 /tmp/u2-old.txt | tr "\n" " ")"; exit 0; }
[[ "$(pacman -Q steamify-gamescope-nvidia | awk '{print $2}')" == 3.16.31-3 ]] && pass "U2 2.14.2 state: still 3.16.31-3" || fail "U2 version changed under 2.14.2"
! grep -q '^\[steamify-' /etc/pacman.conf && pass "U2 2.14.2 state: no Steamify repository in pacman.conf" || fail "U2 a repository section already there"

python3 -c 'import json,sys; d={i["id"]:i for i in json.load(sys.stdin)["items"]}; sys.exit(0 if d["gaming"].get("update") and d["gaming"]["on"] else 1)' <<< "$(sf --backend status | sed -n '/^[\[{]/,$p')" 2>/dev/null && pass "U2 this version shows the conversion as an update" || fail "U2 no update shown for the conversion"

info "U2 applying this version over it (downloads the newest patched gamescope)..."
sf --defaults --options gaming >/tmp/u2-new.txt; rc=$?
[[ $rc -eq 0 ]] && pass "U2 2.14.3 over 2.14.2: exit 0" || { fail "U2 upgrade exit $rc: $(tail -n 4 /tmp/u2-new.txt | tr "\n" " ")"; grep -iE "error|warn|fail" /tmp/u2-new.txt | head -n 8 | sed "s/^/INFO u2: /"; }
new="$(pacman -Q steamify-gamescope-nvidia | awk '{print $2}')"
[[ "$(printf '%s\n%s\n' 3.17.0-1 "$new" | sort -V | head -n 1)" == 3.17.0-1 ]] && pass "U2 the patched gamescope is $new (3.17.0-1 or newer)" || fail "U2 patched gamescope is $new"
gsn_smoke_test && pass "U2 the new gamescope starts (headless smoke test)" || fail "U2 the new gamescope does not start"
grep -q '^\[steamify-' /etc/pacman.conf && ls /var/lib/pacman/sync/steamify-*.db >/dev/null 2>&1 && pass "U2 the repository is listed with its database" || fail "U2 repository section or database missing"
sudo pacman -S --noconfirm --needed nano >/tmp/u2-s.log 2>&1 && pass "U2 pacman -S works afterwards" || fail "U2 pacman -S: $(tail -n 2 /tmp/u2-s.log | tr "\n" " ")"
python3 -c 'import json,sys; d={i["id"]:i for i in json.load(sys.stdin)["items"]}; sys.exit(1 if d["gaming"].get("update") else 0)' <<< "$(sf --backend status | sed -n '/^[\[{]/,$p')" 2>/dev/null && pass "U2 no update left on the conversion" || fail "U2 the update marker stays"
grep -qx gamescope_drm_gbm_scanout=1 ~/.config/gamescope-session/environment && pass "U2 the GBM setting is kept" || fail "U2 the GBM setting is gone"

out="$(sf --defaults --options gaming 2>&1)"
echo "$out" | grep -qiE 'Downloading|Installing|Building' && fail "U2 a second run installs again: $(echo "$out" | tail -n 3 | tr "\n" " ")" || pass "U2 a second run changes nothing"
