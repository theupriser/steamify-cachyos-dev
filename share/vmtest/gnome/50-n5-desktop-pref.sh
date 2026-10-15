# GN5: --desktop kde|gnome|last: the desktop "Switch to Desktop" goes to; the session tool resolves it.
for v in kde gnome last; do
    bash /mnt/steamify.sh --desktop $v </dev/null >/dev/null 2>&1; rc=$?
    [[ $rc -eq 0 && "$(cat /etc/steamify/desktop)" == "$v" ]] && pass "GN5 --desktop $v stored" || fail "GN5 --desktop $v: exit $rc, file: $(cat /etc/steamify/desktop 2>&1)"
done
out=$(bash /mnt/steamify.sh --desktop sideways </dev/null 2>&1); rc=$?
[[ $rc -eq 1 ]] && grep -q "kde, gnome or last" <<< "$out" && pass "GN5 --desktop sideways refused" || fail "GN5 --desktop sideways: exit $rc"
out=$(bash /mnt/steamify.sh --desktop </dev/null 2>&1); [[ $? -eq 1 ]] && pass "GN5 --desktop without a value refused" || fail "GN5 --desktop without a value was accepted"
# the session tool: "desktop" resolves to what is installed (only GNOME here), whatever the preference says
tool=/tmp/gn5-set-session; cp /mnt/patches/steamify-gdm-steam-set-session.sh $tool
for v in kde gnome last; do
    sudo bash -c "echo $v > /etc/steamify/desktop"
    got=$(bash -c "source <(sed -n '/^have_session()/p;/^resolve_desktop()/,/^}/p' $tool); resolve_desktop")
    [[ "$got" == gnome.desktop ]] && pass "GN5 pref $v with only GNOME installed -> gnome.desktop" || fail "GN5 pref $v -> $got"
done
sudo rm -f /etc/steamify/desktop
