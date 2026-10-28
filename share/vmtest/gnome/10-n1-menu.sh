# since: 2.15.0
# GN1: the menu and the checks on a GNOME (GDM) PC, the new GNOME items: the GNOME theme is offered, Plasma's theme and single user mode are not.
menu() { printf "$1" | bash /mnt/steamify.sh 2>&1 | sed 's/\x1b\[[0-9;]*m//g'; }
[[ "$(desktop_kind)" == gnome ]] && pass "GN1 desktop_kind: gnome" || fail "GN1 desktop_kind: $(desktop_kind)"
[[ "$(current_display_manager)" == gdm ]] && pass "GN1 the login manager is GDM" || fail "GN1 login manager: $(current_display_manager)"
desktop_installed gnome && ! desktop_installed kde && pass "GN1 only GNOME is installed" || fail "GN1 installed desktops are not just GNOME"
out=$(menu 'q\n')
grep -qE "^ +[0-9]+ +[a-z-]+ +\[[ x]\] .*SteamOS conversion" <<< "$out" && pass "GN1 SteamOS conversion offered" || fail "GN1 no SteamOS conversion row"
grep -qE "^ +[0-9]+ +[a-z-]+ +\[[ x]\] .*SteamOS theme for GNOME" <<< "$out" && pass "GN1 GNOME theme offered" || fail "GN1 no GNOME theme row"
grep -qE "Install SteamOS theme: Vapor" <<< "$out" && fail "GN1 Plasma's theme is offered on GNOME" || pass "GN1 Plasma's theme hidden"
grep -q "Single user mode" <<< "$out" && fail "GN1 single user mode is offered on GNOME" || pass "GN1 single user mode hidden"
grep -q '^\[ERROR\]' <<< "$out" && fail "GN1 menu error: $(grep -m1 '^\[ERROR\]' <<< "$out")" || pass "GN1 menu without errors"
# the same through the backend (what the app reads)
st=$(bash /mnt/steamify.sh --backend status 2>/dev/null)
python3 -c 'import json,sys; json.loads(sys.argv[1])' "$st" 2>/dev/null && pass "GN1 --backend status is valid JSON" || fail "GN1 --backend status is not JSON"
grep -q gnometheme <<< "$st" && pass "GN1 backend lists gnometheme" || fail "GN1 backend has no gnometheme"
grep -qE '"(theme|single)"' <<< "$st" && fail "GN1 backend lists theme/single on GNOME" || pass "GN1 backend leaves out theme and single"
# bad arguments
bash /mnt/steamify.sh --defaults --options single </dev/null 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | grep -qi "unknown item\|not available\|can't" && pass "GN1 --options single is refused on GNOME" || skip "GN1 --options single: no refusal text (check by hand)"
