# since: 2.12.0
# until: 2.14.2
# G1 (update notice, 2.12.0 to 2.14.2): a newer release than the installed package shows the conversion as an update (looked up at most every six hours, quiet offline).
fake_nvidia
T=/var/tmp/gsn-test; rm -rf "$T"; mkdir -p "$T/state" "$T/cache" "$T/backup"
export STATE_DIR="$T/state" XDG_CACHE_HOME="$T/cache" GSN_BACKUP_DIR="$T/backup" GSN_RELEASES=http://127.0.0.1:9
# The update notice (the installed package is faked).
gsn_package_installed() { return 0; }; gsn_installed_version() { echo 3.16.31-3; }
state_set gamescope_nvidia checked "$(date +%s)"
state_set gamescope_nvidia latest 3.16.32-1; gsn_update_pending && pass "G1 a newer release than the installed package: update pending" || fail "G1 update not pending"
state_set gamescope_nvidia latest 3.16.31-3; gsn_update_pending && fail "G1 update pending for the same version" || pass "G1 the same version: no update"
state_set gamescope_nvidia checked 1
gsn_update_pending; [[ "$(state_get gamescope_nvidia checked 0)" -gt 1 ]] && pass "G1 the look at GitHub is remembered, offline changes nothing" || fail "G1 check time not stored"
unset -f gsn_package_installed gsn_installed_version

