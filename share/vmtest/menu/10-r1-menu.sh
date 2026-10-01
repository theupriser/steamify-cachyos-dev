# R1.1-R1.6, R1.10: the menu on an existing desktop, driven with scripted input (each row builds on the last).
menu() { printf "$1" | bash /mnt/steamify.sh 2>&1 | sed 's/\x1b\[[0-9;]*m//g'; }
# R1.1: first-run ticks: everything but Boot into desktop and BIOS
out=$(menu 'q\n')
# By name, not by row number (a new item shifts the numbers): the ticked ones, then the ones that are shown but never preselected.
for item in "SteamOS conversion" "SteamOS theme" "Steam Deck/Machine icons" "Single user mode" "Steamify shortcut" "Update notifications" "HDMI-CEC" "Steam Machine support" "Power-off fix"; do
    grep -qE "^ +[0-9]+ +[a-z-]+ +\[x\] .*$item" <<< "$out" && pass "R1.1 $item ticked" || fail "R1.1 $item not ticked"
done
for item in "Extended controller support" "Update BIOS"; do
    grep -qE "^ +[0-9]+ +[a-z-]+ +\[ \] .*$item" <<< "$out" && pass "R1.1 $item shown, not ticked" || fail "R1.1 $item missing or ticked"
done
grep -q "Boot into: \[gamescope\]" <<< "$out" && pass "R1.1 boots into gamescope by default" || fail "R1.1 boot default is not gamescope"
# R1.2: everything OK, back in the menu with all on
info "applying Steamify (installs packages, builds kernel modules: a few minutes)..."
out=$(menu '\ny\nm\nq\nn\n')
grep -q '^\[ERROR\]' <<< "$out" && fail "R1.2 errors: $(grep -m1 '^\[ERROR\]' <<< "$out")" || pass "R1.2 no errors"
grep -q "^\[OK\]" <<< "$out" && pass "R1.2 applied (the run printed [OK] lines)" || fail "R1.2 printed no [OK] line"
expect_on gaming theme glyphs single launcher notify cec machine poweroff
# R1.3: the state (what vmstate.sh prints)
[[ "$(current_display_manager)" == sddm ]] && [[ -f /etc/sddm.conf.d/10-gamescope-autologin.conf ]] && pass "R1.3 SDDM with autologin" || fail "R1.3 no SDDM autologin"
n=$(compgen -G "/sys/class/leds/valve-leds*" | wc -l); [[ $n -eq 17 ]] && pass "R1.3 17 LED nodes" || fail "R1.3 $n LED nodes"
own=$(stat -c %U /sys/class/leds/valve-leds*/brightness 2>/dev/null | sort -u | tr '\n' ' '); [[ "$own" == "$(id -un) " ]] && pass "R1.3 LEDs owned by the user" || fail "R1.3 LED owner: $own"
[[ $(dkms status | grep -c ': installed') -ge $((3 * $(ls /usr/lib/modules | wc -w))) ]] && pass "R1.3 DKMS installed for every kernel" || fail "R1.3 DKMS: $(dkms status | tr '\n' ';')"
systemctl is-active --quiet steamos-manager && pass "R1.3 steamos-manager active" || systemctl --user is-active --quiet steamos-manager && pass "R1.3 steamos-manager active (user)" || fail "R1.3 steamos-manager not active"
# R1.4: nothing to do
out=$(menu '\nq\n'); grep -qi "already the way you want it" <<< "$out" && pass "R1.4 already the way you want it" || fail "R1.4 message missing"
# R1.5: re-apply: no errors, no duplicates in the journals
out=$(menu 'a\ny\nm\nq\nn\n')
grep -q '^\[ERROR\]' <<< "$out" && fail "R1.5 errors: $(grep -m1 '^\[ERROR\]' <<< "$out")" || pass "R1.5 re-apply without errors"
dup=""; for f in ~/.local/state/steamify/*; do [ -f "$f" ] && d=$(cut -f1-3 "$f" | sort | uniq -d) && [ -n "$d" ] && dup+="$(basename "$f"): $d; "; done
[[ -z "$dup" ]] && pass "R1.5 no duplicates in the journals" || fail "R1.5 DUPLICATES $dup"
# R1.6: --backend status
ver=$(sed -n 's/^VERSION=//p' /mnt/steamify.sh | head -n 1)
js=$(bash /mnt/steamify.sh --backend status 2>/dev/null)
python3 - "$js" "$ver" <<'PY'
import json, sys
def r(ok, m): print(("PASS " if ok else "FAIL ") + m)
try:
    d = json.loads(sys.argv[1]); r(True, "R1.6 --backend status is valid JSON")
except Exception as e:
    r(False, f"R1.6 --backend status is not JSON: {e}"); sys.exit()
r(sys.argv[2] in json.dumps(d), f"R1.6 the JSON has the current version {sys.argv[2]}")
PY
# R1.10: an item older in features.state shows as an update, and the run brings it up to date
f=~/.local/state/steamify/features.state
[[ -f "$f" ]] && sed -i 's/^cec=.*/cec=2.1.0/' "$f" && grep -q '^cec=2.1.0' "$f" && pass "R1.10 cec set to 2.1.0" || fail "R1.10 cannot set cec older in $f"
out=$(menu 'q\n'); grep -q "HDMI-CEC.*(update)" <<< "$out" && pass "R1.10 the menu shows HDMI-CEC (update)" || fail "R1.10 no (update) on HDMI-CEC"
out=$(menu '\ny\nm\nq\nn\n'); grep -q '^cec=2.1.0' "$f" && fail "R1.10 cec still 2.1.0 after the run" || pass "R1.10 cec brought up to date"
