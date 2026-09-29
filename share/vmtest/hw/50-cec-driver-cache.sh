# R1.7 (CEC driver cache): Valve's CEC driver is downloaded once and kept in /var/cache/steamify, named after
# its checksum; a new pin downloads its own file and removes the old one, a damaged file is replaced.
# Offline: a private cache folder, and the host's cached copy as the "download" (file://), so GitHub's rate
# limit can't fail this block. Needs the host cache (vmsuite.sh binds ~/vms/pkg-cache/steamify).
real="/var/cache/steamify/cros-ec-cec-${CEC_DRIVER_SHA256:0:12}.c"
[[ -f "$real" ]] || { skip "R1.7 cache: no cached CEC driver on the host (~/vms/pkg-cache/steamify)"; exit 0; }
dir=$(mktemp -d); sudo chown root: "$dir"; sudo chmod 755 "$dir"   # like /var/cache/steamify: the user checks the cache
export CEC_DRIVER_URL="file://$real" CEC_DRIVER_CACHE="$dir/cros-ec-cec-${CEC_DRIVER_SHA256:0:12}.c"
errs=""
run() { out=$(cec_driver_enable 2>&1 | sed 's/\x1b\[[0-9;]*m//g'); errs+=$(grep -B6 '^\[ERROR\]' <<< "$out" | tr '\n' '|'); }   # sets out

# 1. new pin: an older pin's file is there, this one isn't
sudo touch "$dir/cros-ec-cec-000000000000.c"
run
grep -q "Downloading Valve" <<< "$out" && pass "R1.7 cache: a new pin downloads its driver" || fail "R1.7 cache: no download for a new pin"
echo "$CEC_DRIVER_SHA256  $CEC_DRIVER_CACHE" | sha256sum -c --quiet - 2>/dev/null && pass "R1.7 cache: the driver is kept, checksum OK" || fail "R1.7 cache: not kept after the download"
[[ ! -e "$dir/cros-ec-cec-000000000000.c" ]] && pass "R1.7 cache: the older pin's file is removed" || fail "R1.7 cache: the older pin's file is still there"
[[ -d "$CEC_DKMS_SRC" ]] && pass "R1.7 cache: the driver is in DKMS" || fail "R1.7 cache: no DKMS source"

# 2. cache hit: no download
run
grep -q "Downloading Valve" <<< "$out" && fail "R1.7 cache: downloaded again although it's cached" || pass "R1.7 cache: the cached driver is used, no download"

# 3. a damaged file under the right name: downloaded again and replaced
echo broken | sudo tee "$CEC_DRIVER_CACHE" >/dev/null
run
grep -q "Downloading Valve" <<< "$out" && echo "$CEC_DRIVER_SHA256  $CEC_DRIVER_CACHE" | sha256sum -c --quiet - 2>/dev/null &&
    pass "R1.7 cache: a damaged cached driver is replaced" || fail "R1.7 cache: a damaged cached driver stays"
[[ -z "$errs" ]] && pass "R1.7 cache: no errors in the three runs" || fail "R1.7 cache: errors: $(cut -c1-600 <<< "$errs")"
sudo rm -rf "$dir"
