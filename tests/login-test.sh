#!/bin/bash
# Characterization tests for the login/session code of the SteamOS conversion (lib/login-manager.sh,
# lib/single-user.sh, lib/desktop-shortcut.sh, lib/boot-session.sh and the helper scripts in patches/):
# what gaming_enable does in which order, what single user mode on/off writes, the relogin helper, the
# greeter session, the shortcut name and the cleanup of older layouts. They pin today's behaviour so a
# refactor cannot change it silently. System folders (/etc, /usr/local, /usr/lib, /var/lib) are redirected
# into a temp dir while the libraries are sourced; systemctl, pacman and loginctl are stubs. No root needed:
#   bash tests/login-test.sh
# The Steamify checkout (REPO, default: the steamify-cachyos next to this repo)
REPO="${REPO:-$(cd "$(dirname "$0")/../../steamify-cachyos" && pwd)}"; cd "$REPO" || exit 1
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0
check() { if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; fail=1; fi; }

SCRIPT_DIR="$PWD"; HOME="$T/home"; mkdir -p "$HOME" "$T/etc" "$T/usr/local/libexec" "$T/usr/lib/steamos" "$T/var/lib" "$T/bin"
# A library with its system paths moved under $T.
mapped() { sed -e "s|/etc/|$T/etc/|g" -e "s|/usr/local/|$T/usr/local/|g" -e "s|/usr/lib/|$T/usr/lib/|g" -e "s|/var/lib/|$T/var/lib/|g" "$1"; }
VERSION=0.0.0
source lib/common.sh; source lib/state.sh; source lib/desktop.sh
for lib in login-manager single-user wizard-shortcut desktop-shortcut boot-session; do source <(mapped "lib/$lib.sh"); done
info() { :; }; ok() { :; }; warn() { :; }; err() { echo "ERR $*"; }
sudo() { "$@"; }
TARGET_USER=tester; USER=tester

# --- stubs: systemd, desktop, hardware
DM=plasmalogin; BOOT_ENABLED=0; SYSTEMCTL_LOG="$T/systemctl.log"; : > "$SYSTEMCTL_LOG"
systemctl() {
    echo "systemctl $*" >> "$SYSTEMCTL_LOG"
    case "$1" in
        show) echo "$DM.service" ;;
        is-enabled) [[ "$*" == *steamify-boot-desktop* ]] && [[ $BOOT_ENABLED == 1 ]] ;;
    esac
    return 0
}
user_session() { return 1; }
desktop_kind() { echo kde; }
desktop_installed() { [[ "$1" == kde ]]; }
is_wanted() { [[ "${WANTED[$1]:-0}" == 1 ]]; }   # lib/menu.sh
backup_file() { :; }
# steam-set-session as CachyOS ships it for plasma-login-manager: the session goes into one conf.d file.
cat > "$T/usr/lib/steamos/steam-set-session" << EOF
#!/bin/bash
mkdir -p $T/etc/plasmalogin.conf.d
printf '[Autologin]\nSession=%s\n' "\${1:-gamescope-session.desktop}" > $T/etc/plasmalogin.conf.d/zz-steamos-autologin.conf
EOF
chmod +x "$T/usr/lib/steamos/steam-set-session"

CONF="$T/etc/plasmalogin.conf.d"; DROPIN="$T/etc/systemd/system/plasmalogin.service.d/zz-steamify.conf"
declare -A WANTED

# --- gaming_enable: the order, and what stops it
CALLS=""
for f in install_required_packages remove_legacy_login_setup remove_autologin_conf switch_to_plasmalogin switch_to_gdm configure_autologin \
    configure_gdm_autologin session_tools_install single_login_release create_desktop_shortcut steam_enable os_name_enable; do
    eval "$f() { CALLS+=\" $f\"; return 0; }"
done
GSN_RC=0; gsn_enable() { CALLS+=" gsn_enable"; return $GSN_RC; }
LOGIN_MANAGER=plasmalogin; CALLS=""; gaming_enable
check "gaming_enable (plasma-login-manager): packages and the patched gamescope first, then the login setup, then the shortcut and Steam" \
    '[[ "$CALLS" == " install_required_packages gsn_enable switch_to_plasmalogin remove_legacy_login_setup configure_autologin single_login_release create_desktop_shortcut steam_enable os_name_enable" ]]'
GSN_RC=1; CALLS=""; gaming_enable; rc=$?
check "gaming_enable: a failing gsn_enable (NVIDIA's patched gamescope) stops it before any login change" '[[ $rc != 0 && "$CALLS" == " install_required_packages gsn_enable" ]]'
GSN_RC=0; LOGIN_MANAGER=gdm; CALLS=""; gaming_enable
check "gaming_enable (GDM): GDM autologin and the GNOME session tools, never plasma-login-manager" \
    '[[ "$CALLS" == *" switch_to_gdm configure_gdm_autologin session_tools_install single_login_release "* && "$CALLS" != *switch_to_plasmalogin* ]]'

# --- the real login setup: single user (autologin) and multi-user (login screen, relogin helper)
unset -f configure_autologin switch_to_plasmalogin remove_legacy_login_setup remove_autologin_conf
source <(mapped lib/login-manager.sh); source <(mapped lib/desktop-shortcut.sh)   # the real ones again, after the call-recording stubs
switch_to_plasmalogin() { :; }
LOGIN_MANAGER=plasmalogin
rm -rf "$CONF"; WANTED=([single]=1); configure_autologin
check "single user: autologin fragment for the user, into gamescope, with Relogin" \
    'grep -qx "User=tester" "$CONF/10-gamescope-autologin.conf" && grep -qx "Session=gamescope-session.desktop" "$CONF/10-gamescope-autologin.conf" && grep -qx "Relogin=true" "$CONF/10-gamescope-autologin.conf"'
check "single user: steam-set-session started it in gamescope, no relogin helper, no greeter session" \
    'grep -qx "Session=gamescope-session.desktop" "$CONF/zz-steamos-autologin.conf" && [[ ! -e "$T/etc/systemd/system/steamify-relogin.path" && ! -e "$T/usr/local/libexec/steamify-greeter-session" ]] && ! grep -q "steamify-greeter-session" "$DROPIN"'
check "both modes: the one drop-in creates the one-shot files for plasma-login-manager and empties the relogin file" \
    'grep -q "zzt-holo-temp-login.conf" "$DROPIN" && grep -q "zzt-steamos-temp-login.conf" "$DROPIN" && grep -q "zzt-steamify-relogin.conf" "$DROPIN" && [[ "$(ls "$T/etc/systemd/system/plasmalogin.service.d")" == "zz-steamify.conf" ]]'
rm -rf "$CONF"; WANTED=([single]=0); configure_autologin
check "multi-user: no autologin fragment (the login screen at start)" '[[ ! -e "$CONF/10-gamescope-autologin.conf" ]]'
check "multi-user: relogin helper (script, path unit, service) installed and enabled" \
    '[[ -x "$T/usr/local/libexec/steamify-relogin" && -f "$T/etc/systemd/system/steamify-relogin.path" && -f "$T/etc/systemd/system/steamify-relogin.service" ]] && grep -q "enable --now steamify-relogin.path" "$SYSTEMCTL_LOG"'
check "multi-user: the relogin path unit watches what a session switch writes" \
    'grep -q "zz-steamos-autologin.conf" "$T/etc/systemd/system/steamify-relogin.path" && grep -q "zzt-holo-temp-login.conf" "$T/etc/systemd/system/steamify-relogin.path" && grep -q "zzt-steamos-temp-login.conf" "$T/etc/systemd/system/steamify-relogin.path"'
check "multi-user: the login screen preselects the session of Boot into (script, run before the login manager starts)" \
    '[[ -x "$T/usr/local/libexec/steamify-greeter-session" ]] && grep -q "ExecStartPre=-.*steamify-greeter-session" "$DROPIN"'
set_login_mode single
check "multi-user to single user: autologin back, helper and greeter session removed" \
    'grep -qx "User=tester" "$CONF/10-gamescope-autologin.conf" && [[ ! -e "$T/etc/systemd/system/steamify-relogin.path" && ! -e "$T/usr/local/libexec/steamify-relogin" && ! -e "$T/usr/local/libexec/steamify-greeter-session" ]] && ! grep -q "steamify-greeter-session" "$DROPIN"'
set_login_mode multi
check "single user to multi-user: autologin fragment gone, helper installed again" '[[ ! -e "$CONF/10-gamescope-autologin.conf" && -x "$T/usr/local/libexec/steamify-relogin" ]]'
relogin_helper_remove; rm -rf "$T/etc/systemd/system/plasmalogin.service.d"; set_login_mode multi
check "without the conversion (no drop-in) set_login_mode changes nothing" '[[ ! -e "$T/etc/systemd/system/steamify-relogin.path" && ! -e "$CONF/10-gamescope-autologin.conf" ]]'

# --- the relogin helper script: writes User=/Relogin for the user on seat0, empties it once the next session is up
cat > "$T/bin/loginctl" << 'EOF'
#!/bin/bash
n=$(cat "$FAKE_STATE" 2>/dev/null || echo 0); echo $((n + 1)) > "$FAKE_STATE"
# first two calls: session 3; afterwards session 4 (the next one)
if [[ $n -lt 2 ]]; then echo "3 1000 rick seat0 123 user tty1 no -"; else echo "4 1000 rick seat0 456 user tty1 no -"; fi
EOF
chmod +x "$T/bin/loginctl"
sed -e "s|/etc/plasmalogin.conf.d/zzt-steamify-relogin.conf|$T/relogin.conf|" -e 's|sleep 1|sleep 0|' patches/steamify-relogin.sh > "$T/relogin.sh"
FAKE_STATE="$T/fake-state" PATH="$T/bin:$PATH" bash "$T/relogin.sh"
check "relogin helper: the file is empty again once a different session is up" '[[ -f "$T/relogin.conf" && ! -s "$T/relogin.conf" ]]'
# while the same session is still there: it keeps the entry and ends emptied after the timeout, having written it
cat > "$T/bin/loginctl" << 'EOF'
#!/bin/bash
echo "3 1000 rick seat0 123 user tty1 no -"
echo "$(date +%s) called" >> "$FAKE_LOG"
EOF
sed -e "s|/etc/plasmalogin.conf.d/zzt-steamify-relogin.conf|$T/relogin2.conf|" -e 's|sleep 1|sleep 0|' -e 's|seq 40|seq 3|' -e "s|: > \"\$CONF\"|cp \"\$CONF\" $T/relogin2.seen; : > \"\$CONF\"|" patches/steamify-relogin.sh > "$T/relogin2.sh"
FAKE_LOG="$T/fake-log" PATH="$T/bin:$PATH" bash "$T/relogin2.sh"
check "relogin helper: wrote User= and Relogin=true for the logged-in user while waiting" 'grep -qx "User=rick" "$T/relogin2.seen" && grep -qx "Relogin=true" "$T/relogin2.seen" && grep -qx "\[Autologin\]" "$T/relogin2.seen"'
cat > "$T/bin/loginctl" << 'EOF'
#!/bin/bash
echo "c1 957 plasmalogin seat0 1 greeter tty1 no -"
EOF
sed -e "s|/etc/plasmalogin.conf.d/zzt-steamify-relogin.conf|$T/relogin3.conf|" patches/steamify-relogin.sh > "$T/relogin3.sh"
PATH="$T/bin:$PATH" bash "$T/relogin3.sh"
check "relogin helper: at the login screen (no user session) it writes nothing" '[[ ! -e "$T/relogin3.conf" ]]'

# --- the greeter session script
mkdir -p "$T/state-greeter"
printf '#!/bin/bash\n[[ "$1" == is-enabled && "${BOOT_UNIT:-0}" == 1 ]]\n' > "$T/bin/systemctl"; chmod +x "$T/bin/systemctl"
gs() { sed -e "s|@USER@|$1|" -e "s|^STATE=.*|STATE=$T/state-greeter/rc|" -e 's|^chown .*||' patches/steamify-greeter-session.sh > "$T/greeter.sh"; PATH="$T/bin:$PATH" BOOT_UNIT="$2" bash "$T/greeter.sh"; }
gs rick 0
check "greeter session: Boot into gamescope -> gamescope preselected (file created)" 'grep -qx "LastLoggedInSession={\"rick\":\"gamescope-session.desktop\"}" "$T/state-greeter/rc" && grep -qx "\[General\]" "$T/state-greeter/rc"'
gs rick 1
check "greeter session: Boot into desktop -> the desktop preselected" 'grep -qx "LastLoggedInSession={\"rick\":\"plasma.desktop\"}" "$T/state-greeter/rc"'
printf '[General]\nLastLoggedInSession={"anna":"plasma.desktop","rick":"plasma.desktop"}\nLastLoggedInUser=anna\n[Other]\nx=1\n' > "$T/state-greeter/rc"
gs rick 0
check "greeter session: other users' entries and other keys and groups are kept" \
    'grep -q "\"anna\":\"plasma.desktop\"" "$T/state-greeter/rc" && grep -q "\"rick\":\"gamescope-session.desktop\"" "$T/state-greeter/rc" && grep -qx "LastLoggedInUser=anna" "$T/state-greeter/rc" && grep -qx "x=1" "$T/state-greeter/rc"'

# --- the desktop shortcut: its name follows "Boot into"
mkdir -p "$HOME/Desktop"
getent() { echo "tester:x:1:1::$HOME:/bin/bash"; }
gaming_status() { return 0; }
boot_status() { [[ $BOOT_ENABLED == 1 ]]; }
BOOT_ENABLED=0; create_desktop_shortcut
check "shortcut: Boot into gamescope -> \"Return to Gaming Mode\", runs steamos-session-select gamescope (no restart, no sudo)" \
    '[[ -x "$HOME/Desktop/Return to Gaming Mode.desktop" && ! -e "$HOME/Desktop/Switch to Gaming Mode.desktop" ]] && grep -qx "Exec=steamos-session-select gamescope" "$HOME/Desktop/Return to Gaming Mode.desktop" && grep -qx "Name=Return to Gaming Mode" "$HOME/Desktop/Return to Gaming Mode.desktop"'
BOOT_ENABLED=1; refresh_desktop_shortcut
check "shortcut: Boot into desktop -> renamed to \"Switch to Gaming Mode\"" '[[ -x "$HOME/Desktop/Switch to Gaming Mode.desktop" && ! -e "$HOME/Desktop/Return to Gaming Mode.desktop" ]] && grep -qx "Name=Switch to Gaming Mode" "$HOME/Desktop/Switch to Gaming Mode.desktop"'
set_shortcut_icon gaming-return
check "shortcut: the icon is updated under either name" 'grep -qx "Icon=gaming-return" "$HOME/Desktop/Switch to Gaming Mode.desktop"'
BOOT_ENABLED=0; refresh_desktop_shortcut
check "shortcut: back to \"Return to Gaming Mode\"" '[[ -e "$HOME/Desktop/Return to Gaming Mode.desktop" && ! -e "$HOME/Desktop/Switch to Gaming Mode.desktop" ]]'
remove_desktop_shortcut
check "shortcut: removed under either name" '[[ -z "$(ls "$HOME/Desktop")" ]]'

# --- an older layout (SDDM, sync bridge, sudoers rule) leaves nothing behind
mkdir -p "$T/etc/sddm.conf.d" "$T/etc/systemd/system" "$T/etc/sudoers.d" "$T/usr/local/bin" "$T/etc/systemd/system/plasmalogin.service.d"
: > "$T/etc/systemd/system/plasmalogin.service.d/zz-steamify-temp-login.conf"; : > "$T/etc/systemd/system/plasmalogin.service.d/zz-steamify-greeter-session.conf"   # the two drop-ins of 2.13.x
: > "$T/etc/sddm.conf.d/10-gamescope-autologin.conf"; : > "$T/etc/sddm.conf.d/zzz-steamify-autologin.conf"; : > "$T/etc/sddm.conf.d/zz-steamos-autologin.conf"
: > "$T/etc/systemd/system/sync-steamos-session.path"; : > "$T/etc/systemd/system/sync-steamos-session.service"; : > "$T/usr/local/bin/sync-steamos-session.sh"
: > "$T/etc/sudoers.d/gamescope-session-switch"
DM=plasmalogin; remove_legacy_login_setup
check "older layout: SDDM files and their folder are gone (plasma-login-manager is the login manager)" '[[ ! -e "$T/etc/sddm.conf.d" ]]'
check "older layout: the sync bridge is gone" '[[ ! -e "$T/etc/systemd/system/sync-steamos-session.path" && ! -e "$T/etc/systemd/system/sync-steamos-session.service" && ! -e "$T/usr/local/bin/sync-steamos-session.sh" ]]'
check "older layout: the shortcut's sudoers rule is gone" '[[ ! -e "$T/etc/sudoers.d/gamescope-session-switch" ]]'
check "older layout: the two drop-ins of 2.13.x are gone" '[[ -z "$(ls "$T/etc/systemd/system/plasmalogin.service.d")" ]]'
mkdir -p "$T/etc/sddm.conf.d"; : > "$T/etc/sddm.conf.d/zz-steamos-autologin.conf"; DM=sddm; remove_legacy_login_setup
check "SDDM still the login manager: steam-set-session's file for it stays (it is in use)" '[[ -e "$T/etc/sddm.conf.d/zz-steamos-autologin.conf" ]]'

# --- an install of 2.13.x (two drop-ins) still counts as the conversion being on
DM=plasmalogin; mkdir -p "$T/etc/systemd/system/plasmalogin.service.d"; : > "$T/etc/systemd/system/plasmalogin.service.d/zz-steamify-temp-login.conf"; unset -f gaming_status; source <(mapped lib/login-manager.sh)
check "gaming_status: the layout of 2.13.x counts as on (the update moves it to the one drop-in)" 'gaming_status'
rm -rf "$T/etc/systemd/system/plasmalogin.service.d"
check "gaming_status: no drop-in, no fragment: off" '! gaming_status'

# --- turning the conversion off removes our login files and the session fragments
DM=plasmalogin; rm -rf "$CONF"; WANTED=([single]=0); configure_autologin
remove_autologin_conf
check "conversion off: our fragment, the session fragments, the helpers and the drop-in are gone" \
    '[[ -z "$(ls "$CONF" 2>/dev/null)" && ! -e "$T/etc/systemd/system/steamify-relogin.path" && ! -e "$DROPIN" && ! -e "$T/usr/local/libexec/steamify-greeter-session" ]]'

exit $fail
