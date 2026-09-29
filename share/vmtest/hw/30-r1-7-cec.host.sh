# R1.7 / H2: HDMI-CEC with vivid (fake TV and remote): scripts/vmcec.sh prints PASS/FAIL/SKIP (2 SKIP in the VM: wake from TV, sleep).
info "applying Steamify (a few minutes)..."
guest 'sf --defaults --options gaming,theme,glyphs,single,launcher,notify,cec,machine,poweroff >/dev/null; sudo modprobe vivid; echo done' | tail -n 1 | grep -q done && pass "CEC: Steamify applied, vivid loaded" || fail "CEC setup"
"$repo/scripts/vmcec.sh" --no-sleep 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | grep -E '^(PASS|FAIL|SKIP)|PASS|FAIL' | sed -E 's/^[^A-Z]*(PASS|FAIL|SKIP)/\1 CEC:/' | cut -c1-140
