# L1: login modes of the SteamOS conversion on plasma-login-manager (2.14.0): single user mode = autologin at every start,
# single user mode off = multi-user (the login screen; only a session switch logs in again), the relogin helper, the greeter
# session script, the 2.13.x leftovers, and nothing left behind with the conversion off.
CD=/etc/plasmalogin.conf.d; AL=$CD/10-gamescope-autologin.conf; RC=$CD/zzt-steamify-relogin.conf
DROP=/etc/systemd/system/plasmalogin.service.d/zz-steamify.conf
RS=/usr/local/libexec/steamify-relogin; GS=/usr/local/libexec/steamify-greeter-session
SVC=/etc/systemd/system/steamify-relogin.service
t() { local n=$1; shift; if "$@"; then pass "L1 $n"; else fail "L1 $n"; fi; }
common_ok() {   # what both modes share
    t "$1: login manager is plasmalogin" [ "$(current_display_manager)" = plasmalogin ]
    t "$1: one drop-in, not the two of 2.13.x" bash -c "[ -f $DROP ] && [ ! -e ${DROP%/*}/zz-steamify-temp-login.conf ] && [ ! -e ${DROP%/*}/zz-steamify-greeter-session.conf ]"
    t "$1: relogin helper + units installed, path unit enabled" bash -c "[ -x $RS ] && [ -f $SVC ] && systemctl is-enabled -q steamify-relogin.path"
    t "$1: no [Autologin] in the base config" bash -c "! grep -q '^\[Autologin\]' /etc/plasmalogin.conf 2>/dev/null"
    t "$1: no SDDM / sync bridge / sudoers leftovers" bash -c "! ls /etc/sddm.conf.d/*steam* /etc/systemd/system/sync-steamos-session.* /etc/sudoers.d/gamescope-session-switch 2>/dev/null | grep -q ."
    t "$1: gamescope is the session steam-set-session picked" grep -q 'gamescope-session' $CD/zz-steamos-autologin.conf
}

# --- 2.13.x layout first, to be migrated
sudo mkdir -p /etc/sddm.conf.d /etc/systemd/system/plasmalogin.service.d
echo '[Autologin]' | sudo tee /etc/sddm.conf.d/zzz-steamify-autologin.conf >/dev/null
sudo touch /etc/systemd/system/sync-steamos-session.path /etc/systemd/system/sync-steamos-session.service /usr/local/bin/sync-steamos-session.sh
echo ok | sudo tee /etc/sudoers.d/gamescope-session-switch >/dev/null; sudo chmod 440 /etc/sudoers.d/gamescope-session-switch
printf '[Service]\n' | sudo tee /etc/systemd/system/plasmalogin.service.d/zz-steamify-temp-login.conf /etc/systemd/system/plasmalogin.service.d/zz-steamify-greeter-session.conf >/dev/null

# --- single user mode on: autologin at every start
info "applying the conversion + single user mode..."
sf --defaults --options gaming,single --boot gamescope >/tmp/l1a.out; rc=$?
[[ $rc -eq 0 ]] && pass "L1 single: exit 0" || fail "L1 single: exit $rc: $(grep -m1 ERROR /tmp/l1a.out)"
expect_on gaming single
common_ok "single"
t "single: autologin fragment: user, gamescope, Relogin=true" bash -c "grep -qx 'User=$USER' $AL && grep -qx 'Session=gamescope-session.desktop' $AL && grep -qx 'Relogin=true' $AL"
t "single: no greeter session script" [ ! -e $GS ]
t "single: service runs the helper without --relogin" bash -c "grep -Eq '^ExecStart=$RS *\$' $SVC"
t "single: drop-in has the touch lines, no greeter line" bash -c "grep -q 'zzt-holo-temp-login.conf' $DROP && ! grep -q greeter $DROP"
t "2.13.x leftovers gone" bash -c "[ ! -e /etc/sddm.conf.d/zzz-steamify-autologin.conf ] && [ ! -e /etc/systemd/system/sync-steamos-session.path ] && [ ! -e /usr/local/bin/sync-steamos-session.sh ] && [ ! -e /etc/sudoers.d/gamescope-session-switch ]"
sum1=$(sudo sh -c "cat $AL $DROP $SVC" | sha256sum)
sf --defaults --options gaming,single --boot gamescope >/dev/null
[[ "$(sudo sh -c "cat $AL $DROP $SVC" | sha256sum)" == "$sum1" ]] && pass "L1 single: second run changes nothing" || fail "L1 single: second run changed files"

# --- single user mode off: multi-user
sf --defaults --options gaming --boot gamescope >/tmp/l1b.out; rc=$?
[[ $rc -eq 0 ]] && pass "L1 multi: exit 0" || fail "L1 multi: exit $rc: $(grep -m1 ERROR /tmp/l1b.out)"
expect_on gaming; expect_off single
common_ok "multi"
t "multi: no autologin fragment (the PC starts at the login screen)" [ ! -e $AL ]
t "multi: greeter session script installed, in the drop-in" bash -c "[ -x $GS ] && grep -q 'ExecStartPre=-$GS' $DROP"
t "multi: service runs the helper with --relogin" grep -q "^ExecStart=$RS --relogin" $SVC
t "multi: relogin file empty" bash -c "[ ! -s $RC ]"
st=/var/lib/plasmalogin/.local/state/plasma-login-greeterstaterc
if sudo test -f $st; then
    sudo grep -q "\"$USER\":\"gamescope-session.desktop\"" $st && pass "L1 multi: greeter preselects gamescope" || fail "L1 multi: greeter state: $(sudo grep LastLoggedIn $st)"
    sf --boot desktop >/dev/null; sudo $GS
    sudo grep -q "\"$USER\":\"plasma.desktop\"" $st && pass "L1 multi: Boot into desktop: greeter preselects plasma" || fail "L1 multi: after boot desktop: $(sudo grep LastLoggedIn $st)"
    sf --boot gamescope >/dev/null; sudo $GS
else skip "L1 multi: no greeter state dir in this VM"; fi
sum2=$(sudo sh -c "cat $DROP $SVC $GS" | sha256sum)
sf --defaults --options gaming --boot gamescope >/dev/null
[[ "$(sudo sh -c "cat $DROP $SVC $GS" | sha256sum)" == "$sum2" ]] && pass "L1 multi: second run changes nothing" || fail "L1 multi: second run changed files"

# --- the relogin helper, with a stand-in loginctl
fb=$(mktemp -d)
cat > $fb/loginctl << LC
#!/bin/bash
if [[ -e /tmp/l1-next ]]; then echo "2 1000 $USER seat0 - user"; else echo "1 1000 $USER seat0 - user"; fi
LC
chmod +x $fb/loginctl
rm -f /tmp/l1-next
( sleep 5; touch /tmp/l1-next ) &
sudo env PATH=$fb:$PATH $RS --relogin &
hp=$!; sleep 2
sudo grep -qx "User=$USER" $RC && sudo grep -qx 'Relogin=true' $RC && pass "L1 helper: --relogin writes User= and Relogin=true while the old session runs" || fail "L1 helper: no relogin file during the switch"
wait $hp
[[ ! -s $RC ]] && pass "L1 helper: file emptied once the new session is there" || fail "L1 helper: relogin file not emptied"
printf '[Autologin]\nSession=plasma.desktop\n' | sudo tee $CD/zzt-holo-temp-login.conf >/dev/null
sudo touch -d '1 minute ago' $CD/zzt-holo-temp-login.conf; sudo touch $CD/zz-steamos-autologin.conf
sudo env PATH=$fb:$PATH $RS
[[ ! -s $CD/zzt-holo-temp-login.conf ]] && pass "L1 helper: stale one-shot login emptied (last pick wins)" || fail "L1 helper: stale one-shot stays"
sleep 1; printf '[Autologin]\nSession=plasma.desktop\n' | sudo tee $CD/zzt-holo-temp-login.conf >/dev/null
sudo env PATH=$fb:$PATH $RS
[[ -s $CD/zzt-holo-temp-login.conf ]] && pass "L1 helper: a newer one-shot (Switch to Desktop) is kept" || fail "L1 helper: the new one-shot was emptied"
sudo sh -c ": > $CD/zzt-holo-temp-login.conf"
sudo /usr/lib/steamos/steam-set-session gamescope-session.desktop; sleep 4
[[ "$(systemctl show -p ExecMainStartTimestampMonotonic --value steamify-relogin.service)" != 0 ]] && pass "L1 path unit: steam-set-session triggered the helper" || fail "L1 path unit: service never ran"

# --- back to single, then off
sf --defaults --options gaming,single >/dev/null
[[ -f $AL && ! -e $GS ]] && pass "L1 multi -> single: fragment back, greeter script gone" || fail "L1 multi -> single: $(ls $AL $GS 2>&1 | tr '\n' ' ')"
sf --defaults --options notify >/dev/null
expect_off gaming single
t "off: no fragments, helper, units, drop-in, scripts" bash -c "! ls $AL $RC $DROP $RS $GS $SVC /etc/systemd/system/steamify-relogin.path $CD/zz-steamos-autologin.conf 2>/dev/null | grep -q ."
t "off: plasmalogin still the login manager" [ "$(current_display_manager)" = plasmalogin ]
