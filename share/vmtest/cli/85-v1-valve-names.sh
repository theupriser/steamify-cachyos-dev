# since: 2.14.3
# V1-V4 (Valve's packages): nothing from Valve's repositories overrides a package that CachyOS's repositories have. Steamify is applied here (HDMI-CEC,
# Steam Machine support, power-off fix; HDMI-CEC volume is NOT on, the one option that replaces PipeWire on purpose): pacman.conf lists no Valve repository,
# the Valve fetch refuses names a system repository has, what was installed from Valve is not in a system repository, and the packages that both
# sides have (PipeWire, WirePlumber, Mesa, firmware) are not older than what the sync databases offer.
opts=gaming,theme,glyphs,single,launcher,notify,cec,machine,poweroff
info "applying Steamify (HDMI-CEC and Steam Machine support download Valve's packages)..."
sf --defaults --options "$opts" >/tmp/v1-apply.txt; rc=$?
[[ $rc -eq 0 ]] && pass "V1 Steamify applied, exit 0" || fail "V1 apply: exit $rc: $(tail -n 3 /tmp/v1-apply.txt | tr "\n" " ")"
ver() { pacman -Q "$1" 2>/dev/null | cut -d' ' -f2; }
cand() { pacman -Si "$1" 2>/dev/null | awk '/^Version/ { print $3; exit }'; }

# V1: no Valve repository anywhere in pacman's configuration
grep -rqE 'steamdeck-packages|steamos\.cloud' /etc/pacman.conf /etc/pacman.d 2>/dev/null && fail "V1 a Valve repository is in pacman's configuration" || pass "V1 pacman.conf and pacman.d list no Valve repository"
grep -qE '^\[(holo|jupiter|multilib-[0-9]|core-[0-9])' /etc/pacman.conf && fail "V1 a Valve repository section is in pacman.conf" || pass "V1 no Valve repository section"

# V2: the fetch refuses a name a system repository has
for p in mesa pipewire linux-firmware; do
    d=$(mktemp -d); out="$(fetch_holo_pkg "$d" "$p" holo-main 2>&1)"; rc=$?
    [[ $rc -ne 0 && "$out" == *"also in a CachyOS repository"* ]] && ! ls "$d"/valve/cache/"$p"-[0-9]* >/dev/null 2>&1 && pass "V2 $p (in CachyOS's repository) is refused, nothing downloaded" || fail "V2 $p: rc=$rc, $out"
done

# V3: what was installed from Valve (HDMI-CEC) is not a name a system repository has
for p in cecd cec-audio-control inputattach-cec-units; do
    pacman -Q "$p" >/dev/null 2>&1 || { fail "V3 $p is not installed (HDMI-CEC should have installed it)"; continue; }
    pacman -Si "$p" >/dev/null 2>&1 && fail "V3 $p is also in a system repository, yet it came from Valve" || pass "V3 $p came from Valve and no system repository has it"
done

# V4: packages both sides have are not older than the sync databases' version (Valve's builds are older: that would be a swap)
for p in pipewire wireplumber libpipewire libwireplumber mesa vulkan-radeon linux-firmware; do
    pacman -Q "$p" >/dev/null 2>&1 || continue
    c="$(cand "$p")"; i="$(ver "$p")"
    [[ -z "$c" || "$(vercmp "$i" "$c")" -ge 0 ]] && pass "V4 $p $i is not older than CachyOS's $c" || fail "V4 $p $i is older than CachyOS's $c (a Valve build took its place?)"
done
