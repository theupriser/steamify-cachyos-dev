# H3: BIOS update, the whole flow with WIZARD_BIOS_DRY_RUN=1 (never flashes). The VM reports an older BIOS.
# env: BIOS_VERSION=F7F0107
# The BIOS row's number by its name (a new menu item shifts the numbers).
n=$(printf 'q\n' | bash /mnt/steamify.sh 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | sed -n 's/^ *\([0-9][0-9]*\) .*Update BIOS.*/\1/p' | head -n 1)
[[ -n "$n" ]] && pass "H3 Update BIOS is menu row $n" || { fail "H3 no Update BIOS row in the menu"; exit 0; }
out=$(printf "$n\n\ny\ny\nUPDATE\nm\nq\nn\n" | WIZARD_BIOS_DRY_RUN=1 bash /mnt/steamify.sh 2>&1 | sed 's/\x1b\[[0-9;]*m//g')
grep -qi "dry run" <<< "$out" && pass "H3 the dry run went through" || fail "H3 no dry-run message: $(tail -n 3 <<< "$out" | tr '\n' ' ' | cut -c1-160)"
grep -q '^\[ERROR\]' <<< "$out" && fail "H3 errors: $(grep -B4 -m1 '^\[ERROR\]' <<< "$out" | tr '\n' '|' | cut -c1-400)" || pass "H3 no errors"
