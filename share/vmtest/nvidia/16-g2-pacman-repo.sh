# since: 2.14.3
# G2/G3: Steamify's pacman repository (theupriser/steamify-pacman-repo). G2: the key and the [steamify-<variant>] section in a copy of
# pacman.conf (enable, again, another variant, a build made here, disable; the real pacman.conf is never touched), then the real signed
# database and a signature-checked download of a package from GitHub (a private database path, no partial update of the VM).
# G3: the python-hid placeholder comes from the repository. Covers TESTPLAN G2 and G3.
fake_nvidia
T=/var/tmp/gsn-repo-test; sudo rm -rf "$T"; mkdir -p "$T/state" "$T/db" "$T/cache"
export STATE_DIR="$T/state" STEAMIFY_PACMAN_CONF="$T/pacman.conf"
cp /etc/pacman.conf "$STEAMIFY_PACMAN_CONF"
sections() { grep -c '^\[steamify-' "$STEAMIFY_PACMAN_CONF"; }
same_as_orig() { diff <(grep -v '^$' /etc/pacman.conf) <(grep -v '^$' "$STEAMIFY_PACMAN_CONF") >/dev/null; }

# Offline: no database to fetch, so no section either (pacman -S would stop with "could not find database"); the next online run adds it.
STEAMIFY_REPO_URL=http://127.0.0.1:9 steamify_repo_enable v3 >/dev/null 2>&1 && fail "G2 offline: steamify_repo_enable succeeded" || pass "G2 offline: steamify_repo_enable fails"
[[ -z "$(steamify_repo_section)" ]] && same_as_orig && pass "G2 offline: no section left, pacman.conf as it was" || fail "G2 offline: a section without a database was left"

steamify_repo_enable v3 && pass "G2 steamify_repo_enable v3" || fail "G2 steamify_repo_enable v3"
[[ "$(steamify_repo_section)" == steamify-v3 ]] && pass "G2 the section [steamify-v3] is in pacman.conf" || fail "G2 section: $(steamify_repo_section)"
sudo pacman-key --list-keys "$STEAMIFY_REPO_KEY" >/dev/null 2>&1 && pass "G2 pacman trusts the repository's key" || fail "G2 key not in the keyring"
tail -n 3 "$STEAMIFY_PACMAN_CONF" | grep -qx 'SigLevel = Required DatabaseRequired' && tail -n 3 "$STEAMIFY_PACMAN_CONF" | grep -qxF "Server = $STEAMIFY_REPO_URL" && pass "G2 signatures are required, the server is the repository" || fail "G2 section content: $(tail -n 4 "$STEAMIFY_PACMAN_CONF")"
[[ "$(awk '/^\[/ {last=$0} END {print last}' "$STEAMIFY_PACMAN_CONF")" == "[steamify-v3]" ]] && pass "G2 it is the last repository: CachyOS's come first" || fail "G2 not last"
steamify_repo_enable v3; [[ "$(sections)" == 1 ]] && pass "G2 enabling again changes nothing (one section)" || fail "G2 not idempotent: $(sections)"
steamify_repo_enable generic; [[ "$(steamify_repo_section)" == steamify-generic && "$(sections)" == 1 ]] && pass "G2 another CPU level replaces the section" || fail "G2 switch: $(steamify_repo_section) x$(sections)"
steamify_repo_enable local; [[ -z "$(steamify_repo_section)" ]] && same_as_orig && pass "G2 a build made here: no section, pacman.conf as it was" || fail "G2 local"
steamify_repo_enable v3

# The real, signed database and a verified download (private dbpath/cachedir; the local database is linked, nothing is installed).
ln -sfn /var/lib/pacman/local "$T/db/local"
P="sudo pacman --config $STEAMIFY_PACMAN_CONF --dbpath $T/db --cachedir $T/cache --noconfirm"
$P -Sy >"$T/sy.log" 2>&1 && pass "G2 the signed database downloads and verifies" || fail "G2 pacman -Sy: $(tail -n 4 "$T/sy.log")"
v="$(pacman --config "$STEAMIFY_PACMAN_CONF" --dbpath "$T/db" -Si steamify-v3/steamify-gamescope-nvidia 2>/dev/null | awk '/^Version/ {print $3}')"
[[ -n "$v" && "$(printf '%s\n%s\n' "$GSN_VERSION" "$v" | sort -V | head -n 1)" == "$GSN_VERSION" ]] && pass "G2 the repository has the patched gamescope: $v (pinned $GSN_VERSION or newer)" || fail "G2 no gamescope package in the database: '$v'"
for p in steamify-python-hid-shim steamify-cros-ec-cec-dkms steamify-fremont-poweroff-dkms; do
    pacman --config "$STEAMIFY_PACMAN_CONF" --dbpath "$T/db" -Si "steamify-v3/$p" >/dev/null 2>&1 && pass "G2 the repository has $p" || fail "G2 $p missing from the database"
done
$P -Sw steamify-v3/steamify-python-hid-shim >"$T/sw.log" 2>&1 && ls "$T/cache"/steamify-python-hid-shim-*.pkg.tar.zst.sig >/dev/null 2>&1 && pass "G2 a package downloads with its signature and passes the check" || fail "G2 download: $(tail -n 4 "$T/sw.log")"
# A package signed by nobody we trust is refused: remove the key, the same download must fail.
sudo rm -f "$T"/cache/steamify-python-hid-shim-*; sudo pacman-key --delete "$STEAMIFY_REPO_KEY" >/dev/null 2>&1
$P -Sw steamify-v3/steamify-python-hid-shim >"$T/sw2.log" 2>&1 && fail "G2 a package from an untrusted key was accepted" || pass "G2 without the key the download is refused"

steamify_repo_disable; same_as_orig && pass "G2 steamify_repo_disable: pacman.conf as it was" || fail "G2 disable left: $(diff /etc/pacman.conf "$STEAMIFY_PACMAN_CONF" | head -n 5)"
sudo pacman-key --list-keys "$STEAMIFY_REPO_KEY" >/dev/null 2>&1 && fail "G2 key still trusted after disable" || pass "G2 and the key is gone"
unset STEAMIFY_PACMAN_CONF

# G3: python-hidapi stays, the placeholder comes from the repository (no local build).
sudo pacman -S --needed --noconfirm python-hidapi >"$T/hidapi.log" 2>&1
sudo pacman -Rdd --noconfirm steamify-python-hid-shim >/dev/null 2>&1
python_hid_shim_ensure >"$T/shim.log" 2>&1 && pacman -Q steamify-python-hid-shim >/dev/null 2>&1 && pass "G3 the placeholder is installed" || fail "G3 shim: $(tail -n 4 "$T/shim.log")"
grep -q 'building it here' "$T/shim.log" && fail "G3 it was built here, not downloaded" || pass "G3 it came from the repository (no local build)"
pacman -T python-hid >/dev/null 2>&1 && pass "G3 python-hid is satisfied while python-hidapi stays" || fail "G3 python-hid not satisfied"
sudo rm -rf "$T"
