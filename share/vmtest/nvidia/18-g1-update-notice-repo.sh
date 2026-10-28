# since: 2.14.3
# G1 (update notice, 2.14.3 on): only a PC that has the patched gamescope but no [steamify-*] section in pacman.conf shows the conversion as an update; new builds come with pacman -Syu.
fake_nvidia
T=/var/tmp/gsn-test; rm -rf "$T"; mkdir -p "$T/state" "$T/cache" "$T/backup"
export STATE_DIR="$T/state" XDG_CACHE_HOME="$T/cache" GSN_BACKUP_DIR="$T/backup" GSN_RELEASES=http://127.0.0.1:9
# The update notice (the installed package is faked): since 2.14.3 only "the patched gamescope is installed but pacman.conf does not
# list Steamify's repository yet" (a PC set up before); new builds come with pacman -Syu and show nothing.
gsn_package_installed() { return 0; }; gsn_installed_version() { echo "$GSN_VERSION"; }
export STEAMIFY_PACMAN_CONF="$T/pacman.conf"; cp /etc/pacman.conf "$STEAMIFY_PACMAN_CONF"
gsn_update_pending && pass "G1 the package without the repository in pacman.conf: update pending" || fail "G1 update not pending"
printf '\n[steamify-v3]\nSigLevel = Required DatabaseRequired\nServer = %s\n' "$STEAMIFY_REPO_URL" >> "$STEAMIFY_PACMAN_CONF"
gsn_update_pending && fail "G1 update pending although the repository is listed" || pass "G1 the repository is listed: no update (new builds come with pacman -Syu)"
sed -i '/^\[steamify-v3\]/,$d' "$STEAMIFY_PACMAN_CONF"; state_set gamescope_nvidia variant local
gsn_update_pending && fail "G1 update pending for a build made here" || pass "G1 a build made here stays out of the repository: no update"
state_set gamescope_nvidia variant ""
unset -f gsn_package_installed gsn_installed_version; unset STEAMIFY_PACMAN_CONF
