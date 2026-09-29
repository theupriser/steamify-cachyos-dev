# F5: --options launcher,vram,poweroff: poweroff brings Steam Machine support; conversion off, plasmalogin unchanged.
dm_before=$(current_display_manager)
info "applying Steamify (installs packages, builds kernel modules: a few minutes)..."
sf --defaults --options launcher,vram,poweroff >/dev/null; rc=$?
[[ $rc -eq 0 ]] && pass "F5 exit 0" || fail "F5 exit $rc"
expect_on machine poweroff launcher
expect_off gaming
[[ "$(current_display_manager)" == "$dm_before" ]] && pass "F5 display manager unchanged ($dm_before)" || fail "F5 display manager changed: $dm_before -> $(current_display_manager)"
