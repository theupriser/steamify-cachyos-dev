# R2.1: the ISO's installer step: a new user who never logged in gets plain `--defaults` (scripts/vminstallsim.sh).
info "installer simulation: a new user, --defaults (a few minutes)..."
out=$("$repo/scripts/vminstallsim.sh" --fresh 2>&1 | sed 's/\x1b\[[0-9;]*m//g')
grep -q '^exit: 0' <<< "$out" && pass "R2.1 exit 0" || fail "R2.1 $(grep -m1 '^exit' <<< "$out")"
grep -q '^\[ERROR\]' <<< "$out" && fail "R2.1 errors: $(grep -m1 '^\[ERROR\]' <<< "$out")" || pass "R2.1 no errors"
[[ $(grep -c '^Turning on' <<< "$out") -ge 5 ]] && pass "R2.1 every default item turned on ($(grep -c '^Turning on' <<< "$out"))" || fail "R2.1 only $(grep -c '^Turning on' <<< "$out") items turned on"
vm_ssh 'sudo ls /home/isotest/.config/autostart/ 2>/dev/null' | grep -qi steamify && pass "R2.1 the first-login autostart is in place" || fail "R2.1 no first-login autostart"
