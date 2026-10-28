# since: 2.14.1
# C4 (#107): "HDMI-CEC volume" (cecaudio) swaps PipeWire and WirePlumber for Valve's builds (real pacman, Valve's real packages) through a
# local pacman repository listed before CachyOS's, keeps them through `pacman -Su`, refreshes it, and puts CachyOS's back (faked Steam Machine).
# base: applied
opts=gaming,theme,glyphs,single,launcher,notify,cec,machine,poweroff
RULE="$HOME/.config/wireplumber/wireplumber.conf.d/90-steamify-cec-volume.conf"
ver() { pacman -Q "$1" 2>/dev/null | cut -d' ' -f2; }
up() { local v="${1#*:}"; echo "${v%%-*}"; }   # 1:1.6.8-1.7 -> 1.6.8
cp /etc/pacman.conf /tmp/pacman.conf.before
# What "CachyOS's build comes back" means: the version the sync databases offer. The installed one can be newer than the VM's
# databases (the base image was updated after they were synced), and turning the option off installs from the databases.
cand() { pacman -Si "$1" 2>/dev/null | awk '/^Version/ { print $3; exit }'; }
cachy_pw="$(cand pipewire)"; cachy_wp="$(cand wireplumber)"; cachy_lp="$(cand libpipewire)"
info "before: pipewire $cachy_pw, wireplumber $cachy_wp"

# 1. on: Valve's builds come from the local repository, which is first in pacman.conf
info "turning HDMI-CEC volume on (downloads Valve's PipeWire and WirePlumber)..."
sf --defaults --options "$opts,cecaudio" >/tmp/c4-on.txt; rc=$?
[[ $rc -eq 0 ]] && pass "C4 on: Steamify exit 0" || { fail "C4 on: exit $rc: $(tail -n 3 /tmp/c4-on.txt | tr "\n" " ")"; grep -iE "error|fail|problem|could not|cannot" /tmp/c4-on.txt | head -n 12 | sed "s/^/INFO c4-on: /"; }
grep -q '^\[steamify-valve-audio\]' /etc/pacman.conf && pass "C4 on: the repository is in pacman.conf" || fail "C4 on: no repository section"
first="$(grep -E '^\[' /etc/pacman.conf | grep -v '^\[options\]' | head -n 1)"
[[ "$first" == "[steamify-valve-audio]" ]] && pass "C4 on: it is the first repository (before CachyOS's)" || fail "C4 on: first repository is $first"
[[ "$(grep -c '^\[steamify-valve-audio\]' /etc/pacman.conf)" == 1 ]] && pass "C4 on: listed once" || fail "C4 on: listed more than once"
repo_names="$(pacman -Sl steamify-valve-audio 2>/dev/null | awk '{ print $2 }' | tr '\n' ' ')"
[[ " $repo_names " == *" pipewire "* && " $repo_names " == *" wireplumber "* ]] && pass "C4 on: the repository holds pipewire and wireplumber ($repo_names)" || fail "C4 on: repository holds '$repo_names'"
for p in pipewire libpipewire wireplumber libwireplumber; do
    rv="$(pacman -Sl steamify-valve-audio 2>/dev/null | awk -v p="$p" '$2 == p { print $3 }')"
    [[ -n "$rv" && "$(ver "$p")" == "$rv" ]] && pass "C4 on: $p is the repository's build ($rv)" || fail "C4 on: $p installed $(ver "$p"), repository '$rv'"
done
for p in lib32-pipewire lib32-libpipewire; do
    pacman -Q "$p" >/dev/null 2>&1 || continue
    rv="$(pacman -Sl steamify-valve-audio 2>/dev/null | awk -v p="$p" '$2 == p { print $3 }')"
    [[ -n "$rv" && "$(ver "$p")" == "$rv" ]] && pass "C4 on: $p moved to Valve's version too ($rv)" || fail "C4 on: $p installed $(ver "$p"), repository '$rv'"
done
[[ "$(up "$(ver libpipewire)")" == "$(up "$(ver pipewire)")" ]] && pass "C4 on: pipewire and libpipewire are one version" || fail "C4 on: pipewire $(ver pipewire), libpipewire $(ver libpipewire)"
pipewire --version 2>/dev/null | grep -q "$(up "$(ver pipewire)")" && pass "C4 on: the pipewire binary is $(up "$(ver pipewire)")" || fail "C4 on: pipewire --version: $(pipewire --version 2>&1 | tr '\n' ' ')"
grep -qa 'external-volume' /usr/lib/spa-0.2/alsa/libspa-alsa.so && pass "C4 on: Valve's ALSA plugin has the external volume patch" || fail "C4 on: no external volume code in libspa-alsa.so"
[[ -f "$RULE" ]] && grep -q 'api.alsa.external-volume-control' "$RULE" && grep -q 'enable-external-volume-control = true' "$RULE" && pass "C4 on: the WirePlumber rule is in ~/.config/wireplumber" || fail "C4 on: no WirePlumber rule"
grep -q "unix:/run/user/$(id -u)/cec-audio-control/org.pipewire.ExternalVolume" "$RULE" 2>/dev/null && pass "C4 on: the rule points at this user's cec-audio-control socket" || fail "C4 on: wrong socket in the rule"
systemctl is-enabled steamify-valve-audio.timer >/dev/null 2>&1 && pass "C4 on: the weekly refresh timer is enabled" || fail "C4 on: timer not enabled"
[[ -x /usr/local/lib/steamify/steamify-valve-audio ]] && pass "C4 on: the refresh script is installed" || fail "C4 on: no refresh script"
grep -q '^pkgs=' "$HOME/.local/state/steamify/cecaudio.state" 2>/dev/null && pass "C4 on: the swapped packages are recorded" || fail "C4 on: no state"
[[ -L /etc/pipewire/client.conf.d || ! -e /etc/pipewire/client.conf.d ]] && pass "C4 on: /etc/pipewire/client.conf.d is Valve's symlink (or absent), not a leftover directory" || fail "C4 on: client.conf.d is a directory"

# 2. pacman -Su does not swap Valve's builds back for CachyOS's (no sync: the databases are what they are)
upg="$(sudo pacman -Sup 2>/dev/null | grep -E '(pipewire|wireplumber)' || true)"
[[ -z "$upg" ]] && pass "C4 pacman -Su: no PipeWire or WirePlumber upgrade planned" || fail "C4 pacman -Su plans: $upg"

# 3. re-apply: nothing changes
before="$(pacman -Q pipewire wireplumber libpipewire | md5sum)"
sf --defaults --options "$opts,cecaudio" >/tmp/c4-on2.txt; rc=$?
[[ $rc -eq 0 && "$(pacman -Q pipewire wireplumber libpipewire | md5sum)" == "$before" ]] && pass "C4 again: same versions, exit 0" || fail "C4 again: exit $rc or versions changed"
[[ "$(grep -c '^\[steamify-valve-audio\]' /etc/pacman.conf)" == 1 ]] && pass "C4 again: still listed once" || fail "C4 again: listed $(grep -c '^\[steamify-valve-audio\]' /etc/pacman.conf) times"

# 4. the refresh (what the timer runs): works, keeps the same builds, only fills the repository
out="$(sudo /usr/local/lib/steamify/steamify-valve-audio refresh 2>&1)"; rc=$?
[[ $rc -eq 0 && "$out" == *mirrored* ]] && pass "C4 refresh: ok ($(head -n 1 <<< "$out" | cut -c1-80))" || fail "C4 refresh: exit $rc: $out"
[[ "$(pacman -Q pipewire wireplumber libpipewire | md5sum)" == "$before" ]] && pass "C4 refresh: installs nothing itself" || fail "C4 refresh: versions changed"

# 5. off: CachyOS's builds come back, nothing is left
info "turning HDMI-CEC volume off (CachyOS's PipeWire and WirePlumber come back)..."
sf --defaults --options "$opts" >/tmp/c4-off.txt; rc=$?
[[ $rc -eq 0 ]] && pass "C4 off: Steamify exit 0" || fail "C4 off: exit $rc: $(tail -n 3 /tmp/c4-off.txt | tr '\n' ' ')"
[[ "$(ver pipewire)" == "$cachy_pw" && "$(ver wireplumber)" == "$cachy_wp" && "$(ver libpipewire)" == "$cachy_lp" ]] && pass "C4 off: pipewire $cachy_pw and wireplumber $cachy_wp are back" || fail "C4 off: pipewire $(ver pipewire) (was $cachy_pw), wireplumber $(ver wireplumber) (was $cachy_wp)"
grep -q 'steamify-valve-audio' /etc/pacman.conf && fail "C4 off: pacman.conf still lists the repository" || pass "C4 off: the repository is gone from pacman.conf"
# Steamify's own repository section (steamify-pacman-repo) stays while a package from it is installed (the Steam Machine's DKMS drivers): not part of this comparison.
nosteamify() { awk -v m="# Steamify: packages from steamify-pacman-repo, updated by pacman -Syu" '$0 == m { skip = 1; next } skip && /^\[steamify-/ { next } skip && /^(SigLevel|Server) *=/ { next } { skip = 0; print }' "$1" | grep -v '^$'; }
diff -q <(nosteamify /etc/pacman.conf) <(nosteamify /tmp/pacman.conf.before) >/dev/null && pass "C4 off: pacman.conf is the same as before" || fail "C4 off: pacman.conf differs from before: $(diff <(nosteamify /etc/pacman.conf) <(nosteamify /tmp/pacman.conf.before) | head -n 4 | tr '\n' ' ')"
[[ ! -e /var/lib/steamify/valve-audio && ! -e /var/lib/pacman/sync/steamify-valve-audio.db ]] && pass "C4 off: the repository and its database are removed" || fail "C4 off: repository files left"
[[ ! -e "$RULE" && ! -e /etc/systemd/system/steamify-valve-audio.timer && ! -e /usr/local/lib/steamify/steamify-valve-audio ]] && pass "C4 off: rule, timer and script removed" || fail "C4 off: rule, timer or script left"
pacman -Q steamdeck-dsp >/dev/null 2>&1 && fail "C4 off: steamdeck-dsp is still installed" || pass "C4 off: steamdeck-dsp (Valve's dependency) removed"
pacman -Q noisetorch >/dev/null 2>&1 && fail "C4 off: noisetorch is still installed" || pass "C4 off: noisetorch (Valve's dependency) removed"
sf --defaults --options "$opts" >/dev/null; rc=$?
[[ $rc -eq 0 ]] && pass "C4 off twice: fine" || fail "C4 off twice: exit $rc"
