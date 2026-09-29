# H3: BIOS update, the whole flow with WIZARD_BIOS_DRY_RUN=1 (never flashes). The VM reports an older BIOS.
# env: BIOS_VERSION=F7F0107
out=$(printf '11\n\ny\ny\nUPDATE\nm\nq\nn\n' | WIZARD_BIOS_DRY_RUN=1 bash /mnt/steamify.sh 2>&1 | sed 's/\x1b\[[0-9;]*m//g')
grep -qi "dry run" <<< "$out" && pass "H3 the dry run went through" || fail "H3 no dry-run message: $(tail -n 3 <<< "$out" | tr '\n' ' ' | cut -c1-160)"
grep -q '^\[ERROR\]' <<< "$out" && fail "H3 errors: $(grep -B4 -m1 '^\[ERROR\]' <<< "$out" | tr '\n' '|' | cut -c1-400)" || pass "H3 no errors"
