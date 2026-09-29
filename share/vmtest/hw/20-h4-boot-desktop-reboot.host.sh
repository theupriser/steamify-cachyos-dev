# H4: Boot into desktop, reboot: Plasma straight after boot; Boot into gaming: SDDM autologin into gamescope (session file).
conf=/etc/sddm.conf.d/10-gamescope-autologin.conf
info "applying Steamify (a few minutes)..."
guest 'sf --defaults --options gaming,theme,single,machine --boot gamescope >/dev/null; echo done' | tail -n 1 | grep -q done && pass "H4 conversion applied" || fail "H4 apply"
guest "grep -h '^Session=' $conf" | grep -qi gamescope && pass "H4 gaming: the SDDM autologin session is gamescope" || fail "H4 gaming session: $(guest "grep -h Session= $conf")"
guest 'sf --boot desktop >/dev/null; echo done' | tail -n 1 | grep -q done && pass "H4 --boot desktop" || fail "H4 --boot desktop"
reboot_guest && pass "H4 the VM is back after the reboot" || { fail "H4 no ssh after the reboot"; return 0 2>/dev/null || exit 0; }
up=""; for _ in $(seq 40); do vm_ssh "pgrep -u $VM_USER -x plasmashell" >/dev/null 2>&1 && { up=1; break; }; sleep 3; done
[[ -n "$up" ]] && pass "H4 Plasma straight after the boot (boot into desktop)" || fail "H4 no plasmashell after the reboot"
guest 'sf --boot gamescope >/dev/null; echo done' | tail -n 1 | grep -q done && pass "H4 --boot gamescope" || fail "H4 --boot gamescope"
