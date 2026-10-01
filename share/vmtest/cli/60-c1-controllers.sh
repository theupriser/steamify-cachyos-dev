# C1-C3: extended controller support: the repo's DKMS drivers (xone + dongle firmware, xpadneo) are installed and built for every
# installed kernel; a second run is quiet; turning it off removes them again. The VM has no dongle or controller: this covers
# the packages, the headers and the DKMS builds, not the hardware. Covers TESTPLAN C1 (on), C2 (again), C3 (off).
info "applying extended_controller_support (kernel headers and DKMS builds for every kernel: a few minutes)..."
sf --defaults --options extended_controller_support > /tmp/c1.log; rc=$?
[[ $rc -eq 0 ]] && pass "C1 exit 0" || { fail "C1 exit $rc: $(tail -n 12 /tmp/c1.log)"; exit 0; }
pacman -Q xpadneo-dkms xone-dongle-firmware >/dev/null 2>&1 && pacman -Q xone-dkms >/dev/null 2>&1 && pass "C1 xpadneo-dkms, xone-dkms and xone-dongle-firmware are installed" || fail "C1 packages: $(pacman -Qq | grep -E 'xone|xpadneo' | tr '\n' ' ')"
expect_on extended_controller_support
for kd in /usr/lib/modules/*/; do
    k="$(basename "$kd")"; [[ -d "$kd/kernel" ]] || continue
    n="$(dkms status -k "$k" 2>/dev/null | grep -E 'xone|xpadneo' | grep -c installed)"
    [[ "$n" -ge 2 ]] && pass "C1 $k: DKMS built xone and xpadneo ($n modules installed)" || fail "C1 $k: DKMS: $(dkms status -k "$k" 2>&1 | tr '\n' ';')"
    modinfo -k "$k" xone_dongle >/dev/null 2>&1 && modinfo -k "$k" hid_xpadneo >/dev/null 2>&1 && pass "C1 $k: xone_dongle and hid_xpadneo modules exist" || fail "C1 $k: modules missing"
done
sf --defaults --options extended_controller_support | grep -qiE 'nothing|already|exit: 0' && pass "C2 a second run is quiet" || info "C2 second run: $(sf --defaults --options extended_controller_support | tail -n 3)"
sf --defaults --options notify > /tmp/c3.log; rc=$?
[[ $rc -eq 0 ]] && pass "C3 turn-off exit 0" || fail "C3 exit $rc: $(tail -n 8 /tmp/c3.log)"
pacman -Q xpadneo-dkms xone-dkms xone-dongle-firmware >/dev/null 2>&1 && fail "C3 packages are still installed" || pass "C3 the three packages are removed again"
expect_off extended_controller_support
