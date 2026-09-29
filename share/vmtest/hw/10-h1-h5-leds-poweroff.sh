# H1 (LED driver) and H5 (power-off module) with the faked Steam Machine.
info "applying Steamify (installs packages, builds kernel modules: a few minutes)..."
sf --defaults --options gaming,theme,glyphs,single,launcher,notify,cec,machine,poweroff >/dev/null; rc=$?
[[ $rc -eq 0 ]] && pass "Steamify applied (exit 0)" || fail "Steamify exit $rc"
# H1
lsmod | grep -q '^leds_valve' && pass "H1 leds_valve loaded" || fail "H1 leds_valve not loaded"
n=$(compgen -G "/sys/class/leds/valve-leds*" | wc -l); [[ $n -eq 17 ]] && pass "H1 17 valve-leds nodes" || fail "H1 $n valve-leds nodes"
own=$(stat -c %U /sys/class/leds/valve-leds*/brightness 2>/dev/null | sort -u | tr '\n' ' '); [[ "$own" == "$(id -un) " ]] && pass "H1 the nodes belong to the user" || fail "H1 node owner: $own"
# H5
for k in $(ls /usr/lib/modules); do
    compgen -G "/usr/lib/modules/$k/updates/dkms/steamify-fremont-poweroff.ko*" >/dev/null && pass "H5 power-off module built for $k" || fail "H5 no power-off module for $k"
done
sudo modprobe -r steamify_fremont_poweroff 2>/dev/null
out=$(sudo modprobe steamify_fremont_poweroff 2>&1); rc=$?
# in the VM there is no GPIO wake bit: it loads, or answers "No such device"
[[ $rc -eq 0 ]] || grep -q "No such device" <<< "$out" && pass "H5 the module loads (or: No such device, no GPIO wake bit)" || fail "H5 modprobe: $out"
