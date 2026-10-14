# N1: an NVIDIA PC (fake GPU), 2.12.0: the menu is the SteamOS conversion's, as on any PC. "Gaming on NVIDIA" (nvidia, bigpicture,
# nvsilent) is not offered any more. Covers TESTPLAN N1.
fake_nvidia
out="$(sf --defaults --list)"
ids="$(python3 -c 'import json,sys; d=json.load(sys.stdin); print(" ".join(sorted(i["id"] for i in d)))' <<< "$out" 2>/dev/null)"
[[ -n "$ids" ]] && pass "N1 --defaults --list is valid JSON: $ids" || { fail "N1 --defaults --list is not JSON: $(echo "$out" | head -c 300)"; exit 0; }
for i in gaming boot glyphs single; do [[ " $ids " == *" $i "* ]] && pass "N1 $i is offered on an NVIDIA PC" || fail "N1 $i is missing on an NVIDIA PC"; done
for i in nvidia bigpicture nvsilent; do [[ " $ids " == *" $i "* ]] && fail "N1 $i (Gaming on NVIDIA) is still offered" || pass "N1 $i is hidden"; done
st="$(sf --backend status)"
python3 -c 'import json,sys; d=json.load(sys.stdin); ids=[i["id"] for i in d.get("items",d)]; sys.exit(0 if "gaming" in ids and "nvidia" not in ids else 1)' <<< "$st" 2>/dev/null && pass "N1 --backend status (the app) has the conversion row and no Gaming on NVIDIA row" || fail "N1 --backend status rows wrong"
# Without a NVIDIA GPU the menu is the same.
out2="$(NVIDIA_DRM_DIR=/nonexistent sf --defaults --list)"
ids2="$(python3 -c 'import json,sys; print(" ".join(sorted(i["id"] for i in json.load(sys.stdin))))' <<< "$out2" 2>/dev/null)"
[[ "$ids2" == "$ids" ]] && pass "N1 no NVIDIA GPU: the same menu" || fail "N1 menus differ: [$ids] vs [$ids2]"
