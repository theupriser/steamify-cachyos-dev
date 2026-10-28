# since: 2.14.3
# R2 (safeguards for Steamify's pacman repository): a repository pacman can't use stops `pacman -Syu` and every `pacman -S` of the whole system. The keyring package comes
# with the repository (its install scriptlet imports the key), `steamify.sh --remove-repo` and `--add-repo` work as the way out and back, the documented sed one-liner works.
cp /etc/pacman.conf /tmp/pacman.conf.before
F=767F317AC4F06C54700EC832854F60918B8BC40C
sec() { grep -c '^\[steamify-' /etc/pacman.conf; }

sf --add-repo >/tmp/r2-add.txt; rc=$?
[[ $rc -eq 0 ]] && pass "R2 --add-repo: exit 0" || { fail "R2 --add-repo: exit $rc: $(tail -n 3 /tmp/r2-add.txt | tr "\n" " ")"; exit 0; }
[[ "$(sec)" == 1 ]] && pass "R2 one [steamify-*] section in pacman.conf" || fail "R2 sections: $(sec)"
pacman -Q steamify-keyring >/dev/null 2>&1 && pass "R2 the keyring package is installed" || fail "R2 steamify-keyring is missing"
[[ -f /usr/share/pacman/keyrings/steamify.gpg && -f /usr/share/pacman/keyrings/steamify-trusted ]] && pass "R2 the keyring files are in /usr/share/pacman/keyrings" || fail "R2 keyring files missing"
sudo pacman-key --list-keys "$F" 2>/dev/null | grep -q 'full\|ultimate' && pass "R2 the key is trusted (full) in pacman's keyring" || fail "R2 the key is not trusted"
sudo pacman -Sy >/tmp/r2-sy.txt 2>&1 < /dev/null && pass "R2 pacman -Sy works with the repository" || fail "R2 pacman -Sy: $(tail -n 2 /tmp/r2-sy.txt | tr "\n" " ")"

# the keyring's own scriptlet: delete the key, install the cached package file again (without the key the repository itself can't be used, which is the point),
# and the key is back without any lsign by Steamify
pkgf="$(ls /var/cache/pacman/pkg/steamify-keyring-*.pkg.tar.zst 2>/dev/null | head -n 1)"
if [[ -n "$pkgf" ]]; then
    sed -e '/^LocalFileSigLevel/d' -e '/^\[options\]/a LocalFileSigLevel = Never' -e '/^# Steamify: packages from steamify-pacman-repo/,+3d' /etc/pacman.conf > /tmp/r2-nosig.conf
    sudo pacman-key --delete "$F" >/dev/null 2>&1
    sudo pacman --config /tmp/r2-nosig.conf -U --noconfirm "$pkgf" >/tmp/r2-keyring.txt 2>&1 < /dev/null
    sudo pacman-key --list-keys "$F" 2>/dev/null | grep -q 'full\|ultimate' && pass "R2 installing steamify-keyring brings the key back (its scriptlet populates it)" || fail "R2 the keyring package did not restore the key: $(tail -n 3 /tmp/r2-keyring.txt | tr "\n" " ")"
else
    fail "R2 no cached steamify-keyring package file"
fi

# a PC that missed the key: pacman is blocked for everything
sudo pacman -Rdd --noconfirm steamify-keyring >/dev/null 2>&1 < /dev/null; sudo pacman-key --delete "$F" >/dev/null 2>&1
sudo pacman -Sy >/dev/null 2>&1 < /dev/null && fail "R2 pacman -Sy works although the key is unknown" || pass "R2 without the key pacman -Sy fails (the problem)"
sudo pacman -S --noconfirm --needed nano >/dev/null 2>&1 < /dev/null && fail "R2 pacman -S works although the key is unknown" || pass "R2 without the key pacman -S fails too"

sf --remove-repo >/tmp/r2-rm.txt; rc=$?
[[ $rc -eq 0 ]] && pass "R2 --remove-repo: exit 0" || fail "R2 --remove-repo: exit $rc: $(tail -n 3 /tmp/r2-rm.txt | tr "\n" " ")"
sudo pacman -Sy >/dev/null 2>&1 < /dev/null && pass "R2 after --remove-repo pacman -Sy works" || fail "R2 pacman -Sy still fails"
sudo pacman -S --noconfirm --needed nano >/dev/null 2>&1 < /dev/null && pass "R2 after --remove-repo pacman -S works" || fail "R2 pacman -S still fails"
diff <(grep -v '^$' /tmp/pacman.conf.before) <(grep -v '^$' /etc/pacman.conf) >/dev/null && pass "R2 pacman.conf is as before" || fail "R2 pacman.conf differs: $(diff /tmp/pacman.conf.before /etc/pacman.conf | head -n 4 | tr "\n" " ")"
ls /var/lib/pacman/sync/steamify-* >/dev/null 2>&1 && fail "R2 database files left" || pass "R2 no Steamify database files left"

# the same without Steamify: the documented one-liner
sf --add-repo >/dev/null; sudo pacman -Rdd --noconfirm steamify-keyring >/dev/null 2>&1 < /dev/null; sudo pacman-key --delete "$F" >/dev/null 2>&1
sudo sed -i '/^# Steamify: packages from steamify-pacman-repo/,+3d' /etc/pacman.conf
sudo pacman -Sy >/dev/null 2>&1 < /dev/null && pass "R2 the documented sed one-liner gets pacman working again" || fail "R2 the sed one-liner did not help"
[[ "$(sec)" == 0 ]] && pass "R2 and no section is left" || fail "R2 section left after the sed"

# repair before removal: the key and the keyring are gone, the repository is listed and pacman is blocked
sf --add-repo >/dev/null
brk() { sudo pacman -Rdd --noconfirm steamify-keyring >/dev/null 2>&1 < /dev/null; sudo pacman-key --delete "$F" >/dev/null 2>&1; }
brk
sudo pacman -Sy >/dev/null 2>&1 < /dev/null && fail "R2 repair: pacman -Sy works although the key is gone" || pass "R2 repair: broken first (pacman -Sy fails)"
sf --repair-repo >/tmp/r2-repair.txt; rc=$?
[[ $rc -eq 0 ]] && pass "R2 --repair-repo: exit 0" || fail "R2 --repair-repo: exit $rc: $(tail -n 3 /tmp/r2-repair.txt | tr "\n" " ")"
sudo pacman -Sy >/dev/null 2>&1 < /dev/null && pass "R2 after --repair-repo pacman -Sy works" || fail "R2 pacman -Sy still fails after the repair"
pacman -Q steamify-keyring >/dev/null 2>&1 && [[ "$(sec)" == 1 ]] && pass "R2 keyring reinstalled, the repository stays listed" || fail "R2 after the repair: keyring $(pacman -Q steamify-keyring 2>&1 | head -n 1), sections $(sec)"
# the same by itself at the start of a run
brk; rm -f ~/.local/state/steamify/repo/checked 2>/dev/null
sf --defaults --options notify >/tmp/r2-heal.txt; rc=$?
grep -q 'works again' /tmp/r2-heal.txt && pass "R2 a normal run repairs the repository first" || fail "R2 no self-heal in the run: $(grep -iE 'steamify.s pacman|repair|taking it out' /tmp/r2-heal.txt | head -n 3 | tr "\n" " ")"
sudo pacman -Sy >/dev/null 2>&1 < /dev/null && [[ "$(sec)" == 1 ]] && pass "R2 pacman works and the repository is still listed (repaired, not removed)" || fail "R2 after the self-heal: sections $(sec)"

# a working repository is left alone: no repair, no removal (the check once reported a healthy one as broken)
rm -f ~/.local/state/steamify/repo/checked 2>/dev/null
sf --defaults --options notify >/tmp/r2-ok.txt; rc=$?
grep -qi "doesn.t work\|repairing\|taking it out" /tmp/r2-ok.txt && fail "R2 a working repository was touched: $(grep -iE "doesn.t work|repairing|taking it out" /tmp/r2-ok.txt | head -n 2 | tr "\n" " ")" || pass "R2 a working repository is left alone (no repair, no removal)"
[[ "$(sec)" == 1 ]] && pass "R2 and it stays listed" || fail "R2 the working repository was removed"

# and back
sf --add-repo >/dev/null; rc=$?
[[ "$(sec)" == 1 ]] && pacman -Q steamify-keyring >/dev/null 2>&1 && pass "R2 --add-repo lists it again, keyring included" || fail "R2 --add-repo again: sections $(sec)"
sf --remove-repo >/dev/null
