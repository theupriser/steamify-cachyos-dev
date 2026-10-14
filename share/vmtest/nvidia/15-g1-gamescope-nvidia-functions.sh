# G1: lib/gamescope-nvidia.sh's pieces without installing anything (the patched gamescope on NVIDIA): version compare, CPU variant, the
# pinned checksums, a damaged package and no GitHub, the update notice, the pre-flight, the failure reminder, the environment files
# and the display wrapper. Covers TESTPLAN G1.
fake_nvidia
T=/var/tmp/gsn-test; rm -rf "$T"; mkdir -p "$T/state" "$T/cache" "$T/backup"
export STATE_DIR="$T/state" XDG_CACHE_HOME="$T/cache" GSN_BACKUP_DIR="$T/backup" GSN_RELEASES=http://127.0.0.1:9

gsn_newer 3.16.32-1 3.16.31-3 && gsn_newer 3.17.0-1 3.16.31-3 && gsn_newer 3.16.31-4 3.16.31-3 && pass "G1 gsn_newer: later versions are newer" || fail "G1 gsn_newer later"
! gsn_newer 3.16.31-3 3.16.31-3 && ! gsn_newer 3.16.30-9 3.16.31-3 && pass "G1 gsn_newer: equal and older are not" || fail "G1 gsn_newer equal/older"
v="$(gsn_cpu_variant)"; [[ "$v" =~ ^(generic|v3|v4|znver4)$ ]] && pass "G1 gsn_cpu_variant: $v" || fail "G1 gsn_cpu_variant: '$v'"
bad=""; for v in generic v3 v4 znver4; do [[ "${GSN_SHA256[$v]}" =~ ^[0-9a-f]{64}$ ]] || bad+=" $v"; done
[[ -z "$bad" ]] && pass "G1 the pinned sha256 of every CPU level is a hash" || fail "G1 pinned sha256 broken for:$bad"
pk="$(sed -n 's/^pkgver=//p' patches/gamescope-nvidia.PKGBUILD)-$(sed -n 's/^pkgrel=//p' patches/gamescope-nvidia.PKGBUILD)"
[[ "$pk" == "$GSN_VERSION" ]] && pass "G1 the PKGBUILD in patches/ builds the pinned version ($GSN_VERSION)" || fail "G1 PKGBUILD $pk != pin $GSN_VERSION"
[[ "$(gsn_sha_of "$GSN_VERSION" x v3)" == "${GSN_SHA256[v3]}" ]] && pass "G1 gsn_sha_of: the pinned version needs no network" || fail "G1 gsn_sha_of pinned"

# No GitHub (port 9 refuses): no latest tag, and a damaged copy is never used.
gsn_latest_tag 2 >/dev/null && fail "G1 gsn_latest_tag answered without GitHub" || pass "G1 gsn_latest_tag: nothing when GitHub can't be reached"
f="$GSN_PKG-$GSN_VERSION-generic.pkg.tar.zst"
echo "not a package" > "$GSN_BACKUP_DIR/$f"
out="$(gsn_fetch_package generic 2>&1)"; rc=$?
[[ $rc -ne 0 ]] && pass "G1 offline with a damaged backup copy: no package (the checksum refuses it)" || fail "G1 damaged copy accepted: $out"
[[ "$out" == *"failed"* ]] && pass "G1 and says so" || fail "G1 no message: $out"
# A copy whose hash matches the table is used.
saved="${GSN_SHA256[generic]}"; GSN_SHA256[generic]="$(sha256sum "$GSN_BACKUP_DIR/$f" | awk '{print $1}')"
[[ "$(gsn_fetch_package generic 2>/dev/null)" == "$GSN_BACKUP_DIR/$f" ]] && pass "G1 offline: the copy that came with Steamify is used when its hash matches" || fail "G1 backup copy with a matching hash not used"
GSN_SHA256[generic]="$saved"; rm -f "$GSN_BACKUP_DIR/$f"

# The update notice (the installed package is faked).
gsn_package_installed() { return 0; }; gsn_installed_version() { echo 3.16.31-3; }
state_set gamescope_nvidia checked "$(date +%s)"
state_set gamescope_nvidia latest 3.16.32-1; gsn_update_pending && pass "G1 a newer release than the installed package: update pending" || fail "G1 update not pending"
state_set gamescope_nvidia latest 3.16.31-3; gsn_update_pending && fail "G1 update pending for the same version" || pass "G1 the same version: no update"
state_set gamescope_nvidia checked 1
gsn_update_pending; [[ "$(state_get gamescope_nvidia checked 0)" -gt 1 ]] && pass "G1 the look at GitHub is remembered, offline changes nothing" || fail "G1 check time not stored"
unset -f gsn_package_installed gsn_installed_version

# The pre-flight.
msg="$(gsn_preflight)" && pass "G1 gsn_preflight passes on a normal PC" || fail "G1 gsn_preflight: $msg"
sudo touch /var/lib/pacman/db.lck; msg="$(gsn_preflight)"; rc=$?; sudo rm -f /var/lib/pacman/db.lck
[[ $rc -ne 0 && "$msg" == *db.lck* ]] && pass "G1 gsn_preflight refuses while pacman is locked" || fail "G1 preflight with a lock: rc=$rc $msg"

# The failure reminder.
gsn_fail_mark "the test failure" >/dev/null 2>&1
[[ "$(gsn_fail_note 2>&1)" == *"the test failure"* ]] && pass "G1 a failed setup is remembered and reminded" || fail "G1 fail note: $(gsn_fail_note 2>&1)"
state_set gamescope_nvidia failed ""
[[ -z "$(gsn_fail_note 2>&1)" ]] && pass "G1 no reminder once it worked" || fail "G1 stale reminder"

# The environment files.
GSN_ENV_D="$T/env/99.conf"; GSN_SESSION_ENV="$T/sess/environment"
mkdir -p "$T/sess"; echo 'OTHER=1' > "$GSN_SESSION_ENV"
gsn_env_enable; gsn_env_enable
[[ "$(grep -c "^$GSN_ENV_LINE\$" "$GSN_SESSION_ENV")" == 1 ]] && grep -qx 'OTHER=1' "$GSN_SESSION_ENV" && grep -qx "$GSN_ENV_LINE" "$GSN_ENV_D" && pass "G1 env files: set once however often, other lines kept" || fail "G1 env enable: $(cat "$GSN_SESSION_ENV")"
gsn_env_disable
[[ ! -e "$GSN_ENV_D" ]] && ! grep -q gbm_scanout "$GSN_SESSION_ENV" && grep -qx 'OTHER=1' "$GSN_SESSION_ENV" && pass "G1 env files: turned off, other lines kept" || fail "G1 env disable"

# The display wrapper.
GSN_DISPLAY_WRAPPER="$T/bin/gamescope"; GSN_DISPLAY_DROPIN="$T/dropin/gamescope-session.service.d/steamify-display.conf"
gsn_display_enable
[[ -x "$GSN_DISPLAY_WRAPPER" && -f "$GSN_DISPLAY_DROPIN" ]] && gsn_display_status && pass "G1 display wrapper and drop-in installed" || fail "G1 display enable"
grep -q "^ExecStart=/usr/bin/bash -c 'PATH=\"$T/bin:" "$GSN_DISPLAY_DROPIN" && pass "G1 the drop-in puts the wrapper first in the session's PATH" || fail "G1 drop-in: $(cat "$GSN_DISPLAY_DROPIN")"
bash -n "$GSN_DISPLAY_WRAPPER" && pass "G1 the wrapper is valid bash" || fail "G1 wrapper syntax"
gsn_display_disable
[[ ! -e "$GSN_DISPLAY_WRAPPER" && ! -e "$GSN_DISPLAY_DROPIN" ]] && pass "G1 display wrapper and drop-in removed" || fail "G1 display disable"
echo '#!/bin/sh' > "$GSN_DISPLAY_WRAPPER"; gsn_display_disable
[[ -e "$GSN_DISPLAY_WRAPPER" ]] && pass "G1 a foreign file at the wrapper's path is left alone" || fail "G1 foreign file removed"
rm -rf "$T"
