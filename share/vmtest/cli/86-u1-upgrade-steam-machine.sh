# since: 2.14.3
# U1 (upgrade 2.14.2 -> 2.14.3, Steam Machine items): a PC set up by Steamify 2.14.2 (released bundle) with HDMI-CEC, Steam Machine support and the
# power-off fix, then this version applied over it. The drivers 2.14.2 copied (CEC, power-off) or built from the AUR (LED bar) become packages from
# Steamify's repository, nothing breaks, a second run changes nothing, turning it all off removes the packages.
old=/tmp/steamify-2.14.2.sh
curl -fsL --retry 2 --max-time 120 https://github.com/theupriser/steamify-cachyos/releases/download/v2.14.2/steamify.sh -o "$old" || { skip "U1 no download of the 2.14.2 bundle"; exit 0; }
oldsf() { bash "$old" "$@" < /dev/null 2>&1 | sed 's/\x1b\[[0-9;]*m//g'; return "${PIPESTATUS[0]}"; }
opts=gaming,theme,glyphs,single,launcher,notify,cec,machine,poweroff
mods() { dkms status 2>/dev/null | grep -cE '(steamify-cros-ec-cec|steamify-fremont-poweroff|leds-valve-dkms).*installed'; }

info "U1 setting up the 2.14.2 state (the released bundle)..."
oldsf --defaults --options "$opts" >/tmp/u1-old.txt; rc=$?
[[ $rc -eq 0 ]] && pass "U1 2.14.2 applied, exit 0" || { fail "U1 2.14.2 apply: exit $rc: $(tail -n 3 /tmp/u1-old.txt | tr "\n" " ")"; exit 0; }
pacman -Q leds-valve-dkms-git >/dev/null 2>&1 && ! pacman -Q steamify-leds-valve-dkms >/dev/null 2>&1 && pass "U1 2.14.2 state: LED driver from the AUR, no Steamify package" || fail "U1 2.14.2 state: LED driver is not the AUR one"
[[ -d /usr/src/steamify-cros-ec-cec-1 && -d /usr/src/steamify-fremont-poweroff-1 ]] && ! pacman -Q steamify-cros-ec-cec-dkms >/dev/null 2>&1 && pass "U1 2.14.2 state: CEC and power-off drivers are copied sources" || fail "U1 2.14.2 state: unexpected"
before="$(mods)"; [[ "$before" -ge 3 ]] && pass "U1 2.14.2 state: DKMS modules installed ($before)" || fail "U1 2.14.2 state: DKMS modules: $before"

for it in cec machine poweroff; do
    python3 -c 'import json,sys; d={i["id"]:i for i in json.load(sys.stdin)["items"]}; sys.exit(0 if d[sys.argv[1]].get("update") and d[sys.argv[1]]["on"] else 1)' "$it" <<< "$(sf --backend status | sed -n '/^[\[{]/,$p')" 2>/dev/null && pass "U1 this version shows $it as an update" || fail "U1 no update shown for $it (a run would change nothing)"
done
info "U1 applying this version over it..."
sf --defaults --options "$opts" >/tmp/u1-new.txt; rc=$?
[[ $rc -eq 0 ]] && pass "U1 2.14.3 over 2.14.2: exit 0" || { fail "U1 upgrade exit $rc: $(tail -n 4 /tmp/u1-new.txt | tr "\n" " ")"; grep -iE "error|warn|fail" /tmp/u1-new.txt | head -n 8 | sed "s/^/INFO u1: /"; }
for p in steamify-cros-ec-cec-dkms steamify-fremont-poweroff-dkms steamify-leds-valve-dkms; do
    pacman -Q "$p" >/dev/null 2>&1 && pass "U1 $p is installed (pacman owns it)" || fail "U1 $p is not installed"
done
pacman -Q leds-valve-dkms-git >/dev/null 2>&1 && fail "U1 the AUR package is still there" || pass "U1 the AUR leds-valve-dkms-git was replaced"
after="$(mods)"; [[ "$after" -ge "$before" ]] && pass "U1 DKMS modules still installed for every kernel ($after, were $before)" || fail "U1 DKMS modules: $after, were $before"
grep -q '^\[steamify-' /etc/pacman.conf && [[ -f "$(ls /var/lib/pacman/sync/steamify-*.db 2>/dev/null | head -n 1)" ]] && pass "U1 the repository is listed and its database is there" || fail "U1 repository section or database missing"
sudo modprobe steamify-fremont-poweroff 2>/dev/null; sudo modprobe leds-valve 2>/dev/null
qk="$(pacman -Qk steamify-cros-ec-cec-dkms steamify-fremont-poweroff-dkms steamify-leds-valve-dkms 2>&1 | grep -ivE ' 0 missing files$')"
[[ -z "$qk" ]] && pass "U1 the packages' files are all there" || fail "U1 package files: $(echo "$qk" | head -n 4 | tr "\n" ";")"

# The migration itself: what the old install left behind is gone or owned by pacman, and the modules are really there for every kernel.
for d in steamify-cros-ec-cec-1 steamify-fremont-poweroff-1 leds-valve-dkms-0.1; do
    pacman -Qo "/usr/src/$d" >/dev/null 2>&1 && pass "U1 /usr/src/$d is owned by a package now (not a leftover copy)" || fail "U1 /usr/src/$d is not owned by any package"
done
kernels=$(ls -d /usr/lib/modules/*/build 2>/dev/null | sed 's|/usr/lib/modules/||; s|/build||')
for k in $kernels; do
    for m in cros-ec-cec steamify-fremont-poweroff leds-valve; do
        modinfo -k "$k" "$m" >/dev/null 2>&1 && pass "U1 $m resolves for kernel $k" || fail "U1 $m has no module for kernel $k"
    done
done
dup="$(dkms status 2>/dev/null | grep -E 'steamify-cros-ec-cec|steamify-fremont-poweroff|leds-valve-dkms' | sed 's/:.*//' | sort | uniq -d)"
[[ -z "$dup" ]] && pass "U1 DKMS lists each module once per kernel (no duplicate entries)" || fail "U1 duplicate DKMS entries: $dup"
dkms status 2>/dev/null | grep -E 'steamify-cros-ec-cec|steamify-fremont-poweroff|leds-valve-dkms' | grep -vq 'installed' && fail "U1 a DKMS module is not in the installed state: $(dkms status | grep -v installed | tr "\n" ";")" || pass "U1 every DKMS module is in the installed state"
ls /usr/src | grep -E '\.bak|\.pacnew|\.old' >/dev/null && fail "U1 leftover files in /usr/src: $(ls /usr/src | grep -E '\.bak|\.pacnew|\.old' | tr "\n" " ")" || pass "U1 nothing left over in /usr/src"
[[ -f /etc/modules-load.d/leds-valve.conf ]] && pass "U1 the LED driver still loads at boot" || fail "U1 /etc/modules-load.d/leds-valve.conf is gone"
info "U1 /etc/dkms/leds-valve-dkms.conf after the migration: $(cat /etc/dkms/leds-valve-dkms.conf 2>/dev/null | grep -v '^#' | tr "\n" " " | cut -c1-120)"

info "U1 a second run..."
sf --defaults --options "$opts" >/tmp/u1-again.txt; rc=$?
[[ $rc -eq 0 ]] && pass "U1 second run: exit 0" || fail "U1 second run: exit $rc"
[[ "$(mods)" == "$after" ]] && pass "U1 second run: same DKMS modules" || fail "U1 second run changed the modules"

info "U1 turning the Steam Machine items off..."
sf --defaults --options gaming,theme,glyphs,single,launcher,notify >/tmp/u1-off.txt; rc=$?
[[ $rc -eq 0 ]] && pass "U1 off: exit 0" || fail "U1 off: exit $rc: $(tail -n 3 /tmp/u1-off.txt | tr "\n" " ")"
for p in steamify-cros-ec-cec-dkms steamify-fremont-poweroff-dkms steamify-leds-valve-dkms; do
    pacman -Q "$p" >/dev/null 2>&1 && fail "U1 off: $p is still installed" || pass "U1 off: $p removed"
done
dkms status 2>/dev/null | grep -qE 'steamify-cros-ec-cec|steamify-fremont-poweroff|leds-valve-dkms' && fail "U1 off: DKMS still lists a module: $(dkms status | grep -E 'steamify|leds-valve' | tr "\n" ";")" || pass "U1 off: DKMS lists none of the modules"
ls -d /usr/src/steamify-cros-ec-cec-1 /usr/src/steamify-fremont-poweroff-1 /usr/src/leds-valve-dkms-0.1 >/dev/null 2>&1 && fail "U1 off: a driver source is still in /usr/src" || pass "U1 off: the sources are gone from /usr/src"
! grep -q '^\[steamify-' /etc/pacman.conf && pass "U1 off: the repository section is gone with its last package" || info "U1 off: the repository section stays (a package from it is still installed)"
