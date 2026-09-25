#!/bin/bash
# Test HDMI-CEC in the guest against a fake TV: the kernel's vivid driver
# gives a virtual HDMI input (/dev/cec0, plays the TV, driven with cec-ctl)
# and output (/dev/cec1, the PC, where cecd runs). Needs the wizard's HDMI-CEC
# item on (cecd, cec-ctl from v4l-utils); steamos-manager (Steam Machine
# support) for the Steam settings tests. Prints PASS/FAIL/SKIP per check.
#
#   scripts/vmcec.sh            everything, including a real suspend/resume
#                               (needs the QMP socket from run.sh to wake up)
#   scripts/vmcec.sh --no-sleep everything except suspending the VM
#   scripts/vmcec.sh --sleep-only only the real sleep/wake check (after a full run)
#
# Afterwards the normal cecd service runs again; vivid stays loaded.
# Env: VM_USER (theupriser), VM_PORT (2222), VM_HOST (localhost).
set -euo pipefail
. "$(dirname "$0")/common.sh"
SLEEP_TEST=true SLEEP_ONLY=false
[[ "${1:-}" == --no-sleep ]] && SLEEP_TEST=false
[[ "${1:-}" == --sleep-only ]] && SLEEP_ONLY=true

# --- in the guest: helpers, setup and all checks except the real sleep ---
$SLEEP_ONLY || vm_ssh "SLEEP_TEST=$SLEEP_TEST bash -s" << 'REMOTE'
export XDG_RUNTIME_DIR=/run/user/1000 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus
W=~/.cache/vmcec; mkdir -p "$W"
pass=0 fail=0 skip=0
PASS() { echo "  PASS  $*"; pass=$((pass + 1)); }
FAIL() { echo "  FAIL  $*"; fail=$((fail + 1)); }
SKIP() { echo "  SKIP  $*"; skip=$((skip + 1)); }
check() { local d="$1"; shift; if "$@" >/dev/null 2>&1; then PASS "$d"; else FAIL "$d"; fi; }
TV() { cec-ctl -d /dev/cec0 "$@"; }
BUS=com.steampowered.CecDaemon1
has_smgr() { steamosctl get-hdmi-cec-state >/dev/null 2>&1; }

# Key reader for the cecd input device: prints key names while it runs.
cat > "$W/keys.py" << 'PY'
import re, select, struct, sys, time
names = {}
for line in open('/usr/include/linux/input-event-codes.h'):
    m = re.match(r'#define\s+(KEY_\w+|BTN_\w+)\s+(0x[0-9a-fA-F]+|\d+)\b', line)
    if m: names.setdefault(int(m.group(2), 0), m.group(1))
f = open(sys.argv[1], 'rb'); end = time.time() + float(sys.argv[2])
while time.time() < end:
    if select.select([f], [], [], 0.1)[0]:
        _, _, t, c, v = struct.unpack('llHHi', f.read(24))
        if t == 1 and v == 1: print(names.get(c, c), flush=True)
PY

# Monitor the TV side's CEC bus into $W/mon.txt (needs root).
mon_start() { sudo pkill -f 'cec-ctl -d /dev/cec0 -M' 2>/dev/null; : > "$W/mon.txt"
    sudo sh -c "exec cec-ctl -d /dev/cec0 -M > $W/mon.txt 2>&1" & sleep 1; }
mon_stop() { sleep 1; sudo pkill -f 'cec-ctl -d /dev/cec0 -M' 2>/dev/null; wait 2>/dev/null; }
seen() { grep -q "Received from.*): $1" "$W/mon.txt"; }

echo "== Setup: fake TV (vivid)"
lsmod | grep -q '^vivid' || sudo modprobe vivid n_devs=1 num_inputs=1 input_types=0x3 num_outputs=1 output_types=0x1
sleep 2
TV --tv --osd-name "Fake TV" >/dev/null 2>&1
v4l2-ctl -d /dev/video0 --set-ctrl hdmi_000_0_is_connected_to=2
# The cecd service (-e) takes every CEC device, the TV too: a temporary
# drop-in limits it to the PC side, so steamos-manager still controls it.
mkdir -p ~/.config/systemd/user/cecd.service.d
printf '[Service]\nExecStart=\nExecStart=/usr/bin/cecd -d /dev/cec1\n' > ~/.config/systemd/user/cecd.service.d/vmcec.conf
systemctl --user daemon-reload; systemctl --user restart cecd.service
sleep 4
systemctl --user is-active -q steamos-manager.service && { systemctl --user restart steamos-manager.service; sleep 3; }
LA=$(cec-ctl -d /dev/cec1 | awk '/Logical Address  /{print $4; exit}')
PA=$(cec-ctl -d /dev/cec1 | awk '/Physical Address/{print $4; exit}')
EV=$(grep -A4 'N: Name="cecd' /proc/bus/input/devices | grep -oE 'event[0-9]+' | head -1)
echo "  PC side: physical $PA, logical $LA, input /dev/input/${EV:-none}"

echo "== 1. Identity (TV asks the PC)"
[[ "$PA" == 1.0.0.0 ]] && PASS "physical address 1.0.0.0" || FAIL "physical address is $PA"
[[ "$LA" =~ ^(4|8|9|11)$ ]] && PASS "logical address $LA (playback device)" || FAIL "logical address is '$LA'"
name=$(TV -t "$LA" --give-osd-name 2>&1 | awk -F': ' '/name:/{print $2; exit}')
[[ "$name" == "Steam Machine" ]] && PASS "OSD name 'Steam Machine'" || FAIL "OSD name is '$name' (steamos-manager's config not applied?)"
vendor=$(TV -t "$LA" --give-device-vendor-id 2>&1 | awk '/vendor-id:/{print $2; exit}')
[[ "$vendor" == 0xe0319e* ]] && PASS "vendor ID Valve (0xe0319e)" || FAIL "vendor ID is '$vendor'"
check "answers a poll" TV -t "$LA" --poll

echo "== 2. TV remote -> PC (key presses)"
press() { TV -t "$LA" --user-control-pressed ui-cmd="$1" >/dev/null; sleep 0.15; TV -t "$LA" --user-control-released >/dev/null; sleep 0.25; }
keys_for() {  # keys_for <seconds> <ui-cmd>...: keys arriving while pressing
    EV=$(grep -A4 'N: Name="cecd' /proc/bus/input/devices | grep -oE 'event[0-9]+' | head -1)
    : > "$W/keys.txt"; local r=
    [[ -n "$EV" ]] && { sudo timeout "$1" python3 "$W/keys.py" "/dev/input/$EV" "$1" > "$W/keys.txt" & r=$!; }
    sleep 1; shift
    local k; for k in "$@"; do press "$k"; done; [[ -n "$r" ]] && wait "$r" 2>/dev/null; cat "$W/keys.txt"; }
if [[ -z "$EV" ]]; then FAIL "no cecd input device"
else
    for k in up down left right select exit back root-menu setup-menu contents-menu \
             play pause stop rewind fast-forward forward backward \
             volume-up volume-down mute number-entry-mode number-0-or-number-10 number-5 \
             channel-up channel-down display-information electronic-program-guide \
             f1-blue f2-red f3-green f4-yellow; do
        got=$(keys_for 2 "$k" | tr '\n' ' ')
        if [[ -n "$got" ]]; then PASS "$(printf '%-28s -> %s' "$k" "$got")"
        else SKIP "$(printf '%-28s -> nothing (not mapped by cecd)' "$k")"; fi
    done

    # The TV's power button arrives as KEY_POWER, and Steam Machine support
    # makes the power button sleep: with sleep blocked, check the key only.
    sudo systemd-inhibit --what=sleep:handle-power-key --mode=block --who=vmcec --why=test sleep 6 & inh=$!; sleep 1
    got=$(keys_for 2 power-toggle-function | tr '\n' ' ')
    wait $inh 2>/dev/null
    [[ "$got" == *KEY_POWER* ]] && PASS "$(printf '%-28s -> %s' power-toggle-function "$got") (sleeps the PC)" ||
        FAIL "power-toggle-function -> '$got'"
fi

echo "== 3. Steam settings (steamos-manager, over D-Bus like Steam)"
# steamosctl's suspend-tv/suspend-device getters and setters don't work
# (steamos-manager 26.4.1); Steam uses these D-Bus properties.
SM=com.steampowered.SteamOSManager1; SMP=/com/steampowered/SteamOSManager1; CEC2=$SM.HdmiCec2
prop() { busctl --user get-property $SM $SMP $CEC2 "$1" 2>/dev/null | awk '{print $2}'; }
setp() { busctl --user set-property $SM $SMP $CEC2 "$1" b "$2" 2>/dev/null; sleep 2; }
cfg() { grep -h "^$1 *=" ~/.config/cecd/config.d/*.toml 2>/dev/null | tail -1 | awk -F'= *' '{print $2}'; }
if ! has_smgr; then SKIP "steamos-manager has no HDMI-CEC interface (no Steam Machine support?)"
else
    echo "  now: $(steamosctl get-hdmi-cec-state 2>&1); EnableControl=$(prop EnableControl) WakeTv=$(prop WakeTv) SuspendTv=$(prop SuspendTv) SuspendDevice=$(prop SuspendDevice) WakeDeviceSupported=$(prop WakeDeviceSupported)"
    setp EnableControl false
    got=$(keys_for 2 down | tr '\n' ' ')
    [[ -z "$got" && "$(cfg uinput)" == false ]] && PASS "remote control off: keys are ignored (uinput = false)" || FAIL "remote control off: keys '$got', uinput = $(cfg uinput)"
    setp EnableControl true
    got=$(keys_for 2 down | tr '\n' ' ')
    [[ -n "$got" ]] && PASS "remote control on again: $got" || FAIL "remote control on, but no keys"
    for pr in WakeTv:wake_tv SuspendTv:suspend_tv SuspendDevice:allow_standby; do
        for v in false true; do
            setp "${pr%%:*}" $v
            [[ "$(prop "${pr%%:*}")" == "$v" && "$(cfg "${pr#*:}")" == "$v" ]] &&
                PASS "${pr%%:*} $v (cecd config ${pr#*:} = $v)" || FAIL "${pr%%:*} $v: property $(prop "${pr%%:*}"), config ${pr#*:} = $(cfg "${pr#*:}")"
        done
    done
    [[ "$(prop WakeDeviceSupported)" == true ]] && PASS "waking the PC with the TV is supported" ||
        SKIP "waking the PC with the TV: not supported here (WakeDeviceSupported = false)"
    steamosctl set-hdmi-cec-state control-and-wake >/dev/null 2>&1; sleep 3
fi
systemctl --user is-active -q cecd.service && PASS "cecd still running" || FAIL "cecd stopped"

echo "== 4. PC -> TV"
# A plain TV (no soundbar): volume goes to the TV itself (address 0).
TV --tv --osd-name "Fake TV" >/dev/null 2>&1; sleep 2
echo "        fake TV: $(TV | awk '/Logical Address  /{printf "%s%s ", $4, $5}')"
DEV=$(busctl --user tree $BUS 2>/dev/null | grep -oE '/com/steampowered/CecDaemon1/Devices/Cec[0-9]+' | head -1)
mon_start
if has_smgr; then steamosctl hdmi-cec-make-active >/dev/null 2>&1; sleep 1; else busctl --user call $BUS "$DEV" $BUS.CecDevice1 SetActiveSource >/dev/null 2>&1; sleep 1; fi
busctl --user call $BUS /com/steampowered/CecDaemon1/Daemon $BUS.Daemon1 Wake >/dev/null 2>&1; sleep 1
mon_stop
{ seen ACTIVE_SOURCE || seen IMAGE_VIEW_ON || seen TEXT_VIEW_ON; } && PASS "make active: TV switches to the PC ($(grep -oE '\): [A-Z_]+' "$W/mon.txt" | sort -u | tr -d '):' | tr '\n' ' '))" || FAIL "make active: TV got nothing"
seen IMAGE_VIEW_ON || seen TEXT_VIEW_ON && PASS "wake: TV is turned on (IMAGE_VIEW_ON)" || FAIL "wake: no IMAGE_VIEW_ON"
mon_start
for m in VolumeUp VolumeDown Mute; do busctl --user call $BUS "$DEV" $BUS.CecDevice1 $m y 0 >/dev/null 2>&1; sleep 0.5; done
echo "        audio status: $(busctl --user --timeout=3 call $BUS "$DEV" $BUS.CecDevice1 GetAudioStatus y 0 2>&1)"; sleep 1
mon_stop
n=$(grep -cE 'USER_CONTROL_PRESSED' "$W/mon.txt"); ops=$(grep -A1 USER_CONTROL_PRESSED "$W/mon.txt" | grep -oiE 'volume-up|volume-down|mute' | sort -u | tr '\n' ' ')
[[ $n -ge 3 ]] && PASS "volume up/down/mute sent to the TV ($ops)" || FAIL "volume: $n key presses reached the TV ($ops)"
seen GIVE_AUDIO_STATUS && PASS "asks the TV's audio status" || FAIL "no GIVE_AUDIO_STATUS"
mon_start
busctl --user call $BUS /com/steampowered/CecDaemon1/Daemon $BUS.Daemon1 Standby b true >/dev/null 2>&1; sleep 1
mon_stop
seen STANDBY && PASS "standby: TV is turned off (STANDBY)" || FAIL "standby: no STANDBY"
systemctl --user is-active -q cec-audio-control.socket && PASS "cec-audio-control socket listening" || FAIL "cec-audio-control socket not active"

echo "== 5. TV off -> PC to sleep (sleep blocked, so the VM stays up)"
if ! has_smgr; then SKIP "needs steamos-manager"
else
    TV --tv >/dev/null 2>&1; sleep 2
    for want in true false; do
        setp SuspendDevice $want; sleep 1
        since=$(date '+%Y-%m-%d %H:%M:%S')
        sudo systemd-inhibit --what=sleep --mode=block --who=vmcec --why=test sleep 7 & inh=$!; sleep 1
        TV -t 15 --standby >/dev/null 2>&1; sleep 4
        wait $inh 2>/dev/null
        tried=$(journalctl --user -u cecd --since "$since" --no-pager | grep -c 'Failed to standby')
        if [[ $want == true ]]; then
            [[ $tried -gt 0 ]] && PASS "SuspendDevice on: TV standby makes the PC go to sleep (blocked here)" || FAIL "SuspendDevice on, but no sleep attempt"
        else
            [[ $tried -eq 0 ]] && PASS "SuspendDevice off: TV standby doesn't touch the PC" || FAIL "SuspendDevice off, but the PC tried to sleep"
        fi
    done
    setp SuspendDevice true
fi

if ! $SLEEP_TEST; then rm -f ~/.config/systemd/user/cecd.service.d/vmcec.conf; systemctl --user daemon-reload; systemctl --user restart cecd.service; fi
echo "== Result: $pass passed, $fail failed, $skip skipped (before the sleep test)"
echo "$LA" > "$W/la"
REMOTE

$SLEEP_TEST || { echo "(sleep test skipped)"; exit 0; }

# --- real suspend/resume: the TV should go off, and on again at wake ---
# Through logind (systemctl suspend), like Steam and the power button: cecd
# acts on logind's PrepareForSleep, which rtcwake skips. cec-follower plays a
# TV that answers power status; QMP (vmwake.sh) wakes the VM.
echo "== 6. Real sleep and wake (systemctl suspend, woken over QMP)"
vm_ssh bash -s << 'REMOTE'
export XDG_RUNTIME_DIR=/run/user/1000 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus
W=~/.cache/vmcec
# cecd on the PC side only, with debug logging (it logs what it does at sleep).
mkdir -p ~/.config/systemd/user/cecd.service.d
printf '[Service]\nExecStart=\nExecStart=/usr/bin/cecd -d /dev/cec1\nEnvironment=RUST_LOG=debug\n' > ~/.config/systemd/user/cecd.service.d/vmcec.conf
systemctl --user daemon-reload; systemctl --user restart cecd.service; sleep 4
SM=com.steampowered.SteamOSManager1; SMP=/com/steampowered/SteamOSManager1
busctl --user set-property $SM $SMP $SM.HdmiCec2 SuspendTv b true 2>/dev/null
busctl --user set-property $SM $SMP $SM.HdmiCec2 WakeTv b true 2>/dev/null
sudo systemctl stop vmcec-tv vmcec-mon 2>/dev/null; sudo systemctl reset-failed vmcec-tv vmcec-mon vmcec-sleep 2>/dev/null
cec-ctl -d /dev/cec0 --tv >/dev/null; sleep 1
sudo systemd-run -q --unit=vmcec-tv sh -c 'exec cec-follower -d /dev/cec0 > /dev/null 2>&1'; sleep 2
steamosctl hdmi-cec-make-active >/dev/null 2>&1; sleep 3
sudo systemd-run -q --unit=vmcec-mon sh -c "exec cec-ctl -d /dev/cec0 -M > $W/sleep-mon.txt 2>&1"; sleep 1
sudo systemd-run -q --unit=vmcec-sleep sh -c 'sleep 2; systemctl suspend'
echo "  suspending..."
REMOTE
sleep 15
"$(dirname "$0")/vmwake.sh" || true
until vm_ssh -o ConnectTimeout=4 true 2>/dev/null; do sleep 3; done
sleep 8
vm_ssh bash -s << 'REMOTE'
export XDG_RUNTIME_DIR=/run/user/1000 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus
W=~/.cache/vmcec
sudo systemctl stop vmcec-mon vmcec-tv 2>/dev/null
t=$(journalctl -b --no-pager -o short-iso | grep "PM: suspend entry" | tail -1 | awk '{print $1}')
[[ -n "$t" ]] && echo "  PASS  the VM really slept and woke (suspend at $t)" || echo "  FAIL  no suspend in the kernel log"
log=$(journalctl --user -u cecd --since "$(date -d "${t:-now} -10 sec" '+%F %T')" --no-pager)
grep -q 'Putting TV in standby' <<< "$log" && echo "  PASS  cecd: 'Putting TV in standby'" || echo "  FAIL  cecd didn't act on going to sleep"
grep -q 'Waking TV' <<< "$log" && echo "  PASS  cecd: 'Woke from standby. Waking TV.'" || echo "  FAIL  cecd didn't act on waking up"
grep -q 'Received from.*: STANDBY' "$W/sleep-mon.txt" && echo "  PASS  going to sleep: TV turned off (STANDBY)" || echo "  FAIL  going to sleep: no STANDBY to the TV"
grep -qE 'Received from.*: (IMAGE_VIEW_ON|TEXT_VIEW_ON)' "$W/sleep-mon.txt" && echo "  PASS  waking up: TV turned on (IMAGE_VIEW_ON)" || echo "  FAIL  waking up: no IMAGE_VIEW_ON"
grep -oE '^(Received|Transmitted)[^:]*: [A-Z_]+' "$W/sleep-mon.txt" | sed 's/^/        /'
# Back to the normal service.
rm -f ~/.config/systemd/user/cecd.service.d/vmcec.conf; systemctl --user daemon-reload; systemctl --user restart cecd.service
REMOTE
