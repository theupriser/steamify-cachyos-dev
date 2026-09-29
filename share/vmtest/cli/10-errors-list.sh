# G1-G3 (--defaults --list), F1, F2, F6 (bad arguments): read-only, nothing may change.
before=$(ls -R ~/.local/state/steamify 2>/dev/null | md5sum)
rejects() {   # rejects <expected message> <args...>: exit 1 and the message
    local want="$1"; shift
    out=$(bash steamify.sh "$@" 2>&1 < /dev/null); rc=$?
    [[ $rc -eq 1 ]] && grep -q "$want" <<< "$out" && pass "steamify.sh $* -> exit 1 ($want)" || fail "steamify.sh $* -> exit $rc: $(sed 's/\x1b\[[0-9;]*m//g' <<< "$out" | grep -m1 -E 'ERROR|rror')"
}
# F1
rejects "needs a value" --defaults --options
rejects "Unknown item" --defaults --options bogus
rejects "not an item" --defaults --options boot
rejects "can't be part of the install" --defaults --options bios
rejects "needs a value" --defaults --boot
rejects "gamescope or desktop" --defaults --boot sideways
rejects "Unknown option" --defaults --skip x
# F2
rejects "needs the SteamOS conversion" --defaults --options theme --boot desktop
rejects "needs the SteamOS conversion" --defaults --boot desktop --options theme
# F6
rejects "needs the SteamOS conversion" --boot desktop
# G1: valid JSON, exit 0, no stderr
out=$(bash steamify.sh --defaults --list 2>/tmp/list.err); rc=$?
[[ $rc -eq 0 ]] && pass "G1 --list exit 0" || fail "G1 --list exit $rc"
[[ ! -s /tmp/list.err ]] && pass "G1 --list prints nothing on stderr" || fail "G1 --list stderr: $(head -c 100 /tmp/list.err)"
python3 - "$out" <<'PY'
import json, sys
def r(ok, msg): print(("PASS " if ok else "FAIL ") + msg)
try:
    d = json.loads(sys.argv[1]); r(isinstance(d, list) and d, "G1 --list is a JSON array")
except Exception as e:
    r(False, f"G1 --list is not JSON: {e}"); sys.exit()
ids = {i.get("id"): i for i in d}
# G2: actions and retired items are not offered; poweroff needs machine, boot needs gaming
r(not ({"bios", "kpin", "hdmi"} & set(ids)), "G2 bios, kpin and hdmi (actions, retired) are left out")
r(not ({"vram", "steamgame"} & set(ids)), "G2 vram and steamgame (unavailable here) are left out")
r("machine" in str(ids.get("poweroff", {}).get("parent", "")), "G2 poweroff has the parent machine")
r("gaming" in str(ids.get("boot", {}).get("parent", "")), "G2 boot has the parent gaming")
PY
# G3 and nothing changed: the errors and --list must not touch the state
after=$(ls -R ~/.local/state/steamify 2>/dev/null | md5sum)
[[ "$before" == "$after" ]] && pass "F1/F2/F6/G1 changed nothing" || fail "the state directory changed"
