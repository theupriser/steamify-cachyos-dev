# N1: an NVIDIA PC (fake GPU): the menu hides the SteamOS conversion and its gamescope options, shows Gaming on NVIDIA, its
# Big Picture option and Single user mode. Covers TESTPLAN N1.
fake_nvidia
out="$(sf --defaults --list)"
ids="$(python3 -c 'import json,sys; d=json.load(sys.stdin); print(" ".join(sorted(i["id"] for i in d)))' <<< "$out" 2>/dev/null)"
[[ -n "$ids" ]] && pass "N1 --defaults --list is valid JSON: $ids" || { fail "N1 --defaults --list is not JSON: $(echo "$out" | head -c 300)"; exit 0; }
for i in nvidia bigpicture single; do [[ " $ids " == *" $i "* ]] && pass "N1 $i is offered" || fail "N1 $i is missing"; done
for i in gaming boot glyphs; do [[ " $ids " == *" $i "* ]] && fail "N1 $i is offered on an NVIDIA PC" || pass "N1 $i is hidden"; done
python3 -c '
import json,sys
d={i["id"]:i for i in json.load(sys.stdin)}
ok = d["bigpicture"]["parent"]=="nvidia" and d["nvidia"]["on"] and d["bigpicture"]["on"] and d["single"]["on"]
sys.exit(0 if ok else 1)' <<< "$out" && pass "N1 Big Picture is a sub-option of Gaming on NVIDIA, all three preselected" || fail "N1 parent or preselection wrong"
st="$(sf --backend status)"
python3 -c 'import json,sys; d=json.load(sys.stdin); ids=[i["id"] for i in d.get("items",d)]; sys.exit(1 if "gaming" in ids else 0)' <<< "$st" 2>/dev/null && pass "N1 --backend status (the app) has no conversion row" || fail "N1 --backend status lists the conversion"
# Without a NVIDIA GPU nothing changes: the conversion is offered, Gaming on NVIDIA is not.
out2="$(NVIDIA_DRM_DIR=/nonexistent sf --defaults --list)"
python3 -c 'import json,sys; ids=[i["id"] for i in json.load(sys.stdin)]; sys.exit(0 if "gaming" in ids and "nvidia" not in ids and "bigpicture" not in ids else 1)' <<< "$out2" && pass "N1 no NVIDIA GPU: the conversion is offered, Gaming on NVIDIA is not" || fail "N1 no-NVIDIA menu wrong"
