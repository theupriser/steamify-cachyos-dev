#!/bin/bash
# One suite of the automated test (TESTPLAN.md rows that need no person) on the plain CachyOS VM
# (Plasma, no Steamify: ~/vms/steamify-vm, from vminstall.sh --iso <CachyOS ISO> with VM_STEAMIFY=skip).
#   scripts/vmsuite.sh <suite> [--window]     suites: the folders in share/vmtest/ (cli, ...)
#   scripts/vmsuite.sh --prepare [gnome]      only make the base image (below)
# The suite "gnome" runs on the plain CachyOS + GNOME + GDM VM (~/vms/gnome-vm, from vminstall.sh with VM_DESKTOP=gnome) instead.
# Every block share/vmtest/<suite>/NN-name.sh starts from a fresh copy of the VM's `ssh-ready` state,
# runs in the guest as the VM user (repo on /mnt; NN-name.host.sh blocks run on the host instead: reboots,
# host scripts), and prints PASS/FAIL/SKIP lines; the first comment lines say which TESTPLAN rows it
# covers; `# env: VAR=value` there is set for the VM start (e.g. BIOS_VERSION=F7F0107).
# Fast and parallel: the `ssh-ready` snapshot is converted once into $SRC/base-ssh-ready.qcow2; each suite
# has its own directory ~/vms/run-<suite> and ssh port, where every block gets a new qcow2 overlay of the
# base (instant, no snapshot restore), and the host's package cache (VM_CACHE, ~/vms/pkg-cache) is bound
# over pacman's cache, so packages are downloaded once for all. Log: $VM_DIR.log. Exit status = FAILs.
# Progress: a "~~ ████░░░░ 45%  block 5/11  N passed, M failed" line before every block and at the end (share of blocks done).
# Version requirements: `# since: X.Y.Z` (and `# until: X.Y.Z`, the last version) in a block's first 8 lines, or a file `since` / `until` in the
# suite folder (the whole suite), limit a check to the Steamify versions it is for: the VERSION of $REPO/steamify.sh is compared with
# sort -V; a check that does not apply prints a SKIP line (the version in the line), so release branches can run the same test tree.
# TEST_VERSION=X.Y.Z (env) is used instead of the checkout's VERSION (to see what would run); NEW_ONLY=1 runs only what is new in this
# release: the blocks and suites whose `since` has the same major.minor as the version under test.
# Env: ONLY=<block name prefix> runs just that block; VMS (default ~/vms; ~/projects/vms on the Steam Machine); SRC (default $VMS/steamify-vm); REPO (default ../steamify-cachyos).
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/.." && pwd)"
desk=kde; [[ "${1:-}" == gnome* || "${2:-}" == gnome* ]] && desk=gnome
vms="${VMS:-$HOME/vms}"   # VMS: where the VMs, their overlays and the package cache live (on the Steam Machine: ~/projects/vms)
src="${SRC:-$vms/steamify-vm}"; [[ $desk == gnome ]] && src="${SRC:-$vms/gnome-vm}"
base="$src/base-ssh-ready.qcow2"

prepare_base() {   # once, under a lock (parallel suites): the ssh-ready snapshot as a stand-alone image
    ( flock 9
      if [[ ! -f "$base" || "$src/vars.ssh-ready.fd" -nt "$base" ]]; then
          echo "Making $base from the ssh-ready snapshot (once, a few minutes)..." >&2
          qemu-img convert -f qcow2 -O qcow2 -l snapshot.name=ssh-ready "$src/disk.qcow2" "$base.tmp" && mv "$base.tmp" "$base"
      fi ) 9>"$src/.base.lock"
    [[ -f "$base" ]]
}
if [[ "${1:-}" == --prepare ]]; then prepare_base; exit $?; fi

suite="${1:?usage: $0 <suite> [--window] | --prepare}"
[[ "${2:-}" == --window ]] || export VM_HEADLESS=1
dir="$repo/share/vmtest/$suite"
[[ -d "$dir" ]] || { echo "No suite $suite (folders in share/vmtest/)" >&2; exit 2; }
case "$suite" in gnome*) port=2307 ;; cli) port=2301 ;; menu) port=2302 ;; hw) port=2303 ;; installer) port=2304 ;; toggles) port=2305 ;; nvidia) port=2306 ;; *) port=2390 ;; esac
export VM_PORT="${VM_PORT:-$port}"
export VM_DIR="$vms/run-$suite"
export REPO="${REPO:-$repo/../steamify-cachyos}"
# A whole suite for other versions (since / until files in its folder): nothing to start.
_sv="${TEST_VERSION:-$(sed -n 's/^VERSION=//p' "$REPO/steamify.sh" 2>/dev/null | head -n 1)}"
_sin="$(cat "$dir/since" 2>/dev/null)"; _unt="$(cat "$dir/until" 2>/dev/null)"
if [[ -n "$_sv" ]]; then
    _ge() { [[ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -n 1)" == "$2" ]]; }
    if [[ -n "${NEW_ONLY:-}" && -n "$_sin" && "${_sin%.*}" != "${_sv%.*}" ]]; then echo "== $suite: 0 passed, 0 failed, 1 skipped (not new in $_sv, NEW_ONLY)"; exit 0; fi
    if [[ -n "$_sin" ]] && ! _ge "$_sv" "$_sin"; then echo "== $suite: 0 passed, 0 failed, 1 skipped (needs Steamify >= $_sin, this is $_sv)"; exit 0; fi
    if [[ -n "$_unt" ]] && ! _ge "$_unt" "$_sv"; then echo "== $suite: 0 passed, 0 failed, 1 skipped (is for Steamify up to $_unt, this is $_sv)"; exit 0; fi
fi
export VM_CACHE="${VM_CACHE-$vms/pkg-cache}"
export VM_MEM="${VM_MEM:-4G}"   # three VMs at once next to a desktop: 8G each pushed the host into swap
prepare_base || { echo "FAIL no base image" >&2; exit 1; }
# Steamify downloads Valve's packages (CEC daemon, PipeWire, firmware) from their mirror. A network that blocks it (a DNS filter that
# answers with a block page, or no route) makes those checks FAIL like regressions: stop before a VM starts, exit 2 (not a check
# result). NET_CHECK=0 skips it. The package database is ~100 KB: a short answer is a block page.
if [[ "${NET_CHECK:-1}" != 0 ]]; then
    read -r _code _size < <(curl -s -m 20 -o /dev/null -w '%{http_code} %{size_download}\n' \
        "https://steamdeck-packages.steamos.cloud/archlinux-mirror/holo-main/os/x86_64/holo-main.db" 2>/dev/null || echo "000 0")
    if [[ "${_code:-000}" != 200 || "${_size:-0}" -lt 10000 ]]; then
        echo "ABORT $suite: Valve's package mirror (steamdeck-packages.steamos.cloud) is not reachable from this network (HTTP ${_code:-000}, ${_size:-0} bytes): the checks that download Valve's packages would fail. Switch networks, or NET_CHECK=0." >&2
        exit 2
    fi
fi
mkdir -p "$VM_DIR"
for f in vm-user ssh-key; do cp "$src/$f" "$VM_DIR/$f"; done
echo "$REPO" > "$VM_DIR/repo-path"; [[ -e "$VM_DIR/share" ]] || ln -s "$repo/share" "$VM_DIR/share"
. "$here/common.sh"
log="$VM_DIR.log"
view_start   # one shared Konsole (common.sh), headless on a desktop

# --- Version requirements (see the header): which Steamify versions a block or a whole suite is for.
steamify_version() { echo "${TEST_VERSION:-$(sed -n 's/^VERSION=//p' "$REPO/steamify.sh" | head -n 1)}"; }
same_minor() { [[ "${1%.*}" == "${2%.*}" ]]; }   # 2.15.0 and 2.15.1 are the same release line
ver_ge() { [[ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -n 1)" == "$2" ]]; }   # $1 is $2 or newer
version_why_not() {   # version_why_not <since> <until>: prints why this Steamify version doesn't fit, returns 0 if it doesn't
    local v; v="$(steamify_version)"; [[ -n "$v" ]] || return 1
    if [[ -n "${NEW_ONLY:-}" ]] && { [[ -z "$1" ]] || ! same_minor "$1" "$v"; }; then echo "not new in $v (NEW_ONLY)"; return 0; fi
    if [[ -n "$1" ]] && ! ver_ge "$v" "$1"; then echo "needs Steamify >= $1, this is $v"; return 0; fi
    if [[ -n "$2" ]] && ! ver_ge "$2" "$v"; then echo "is for Steamify up to $2, this is $v"; return 0; fi
    return 1
}
block_version_skip() {   # block_version_skip <block>
    version_why_not "$(head -n 8 "$1" | sed -n 's/^# since: *//p' | head -n 1)" "$(head -n 8 "$1" | sed -n 's/^# until: *//p' | head -n 1)"
}

vm_running() { pgrep -f "[h]ostfwd=tcp::$VM_PORT-" >/dev/null; }
vm_stop() {
    vm_running || return 0
    vm_ssh -o ConnectTimeout=4 'sudo systemctl poweroff' >/dev/null 2>&1
    local _; for _ in $(seq 20); do vm_running || return 0; sleep 1; done
    pkill -f "[h]ostfwd=tcp::$VM_PORT-"; sleep 2
}
# A fresh VM for a block: new overlay of the base, the snapshot's UEFI vars, Plasma up, repo mounted, package cache bound.
vm_fresh() {   # vm_fresh [VAR=value...]: extra environment for the VM start (BIOS_VERSION=...)
    vm_stop
    cp "$repo/run.sh" "$VM_DIR/run.sh"; cp "${cur_vars:-$src/vars.ssh-ready.fd}" "$VM_DIR/vars.fd"
    rm -f "$VM_DIR/disk.qcow2" "$VM_DIR/known_hosts"
    qemu-img create -q -f qcow2 -b "${cur_base:-$base}" -F qcow2 "$VM_DIR/disk.qcow2" || return 1
    local fremont=--fremont; [[ $desk == gnome ]] && fremont=   # GNOME: a plain PC
    (cd "$VM_DIR" && env "$@" nohup ./run.sh $fremont > vm.log 2>&1 &)
    local _; for _ in $(seq 100); do vm_ssh -o ConnectTimeout=3 true 2>/dev/null && break; sleep 3; done
    vm_ssh -o LogLevel=ERROR "DESK=$desk FORCE=${cur_base:+$([[ ${cur_base:-} == "${applied:-}" ]] && echo 1)} bash -s" <<'REMOTE'
sudo mount -t 9p -o trans=virtio,version=9p2000.L repo /mnt
if [[ $DESK == kde ]]; then
sudo mkdir -p /etc/plasmalogin.conf.d
printf '[Autologin]\nUser=%s\nSession=plasma.desktop\n' "$USER" | sudo tee /etc/plasmalogin.conf.d/00-test-autologin.conf >/dev/null
# an applied image logs in to gamescope (zz-steamos-autologin.conf wins over 00-): the harness needs Plasma, so a later file
[[ ${FORCE:-} == 1 ]] && { printf '[Autologin]\nUser=%s\nSession=plasma.desktop\n' "$USER" | sudo tee /etc/plasmalogin.conf.d/zzzzz-test-autologin.conf >/dev/null; sudo systemctl restart plasmalogin; }
for _ in $(seq 10); do pgrep -u "$USER" -x plasmashell >/dev/null && break; sleep 3; done
pgrep -u "$USER" -x plasmashell >/dev/null || { sudo systemctl reset-failed plasmalogin; sudo systemctl restart plasmalogin; }
for _ in $(seq 40); do pgrep -u "$USER" -x plasmashell >/dev/null && break; sleep 3; done
pkill -u "$USER" systemsettings; pkill -u "$USER" cachyos-hello
else
    # GNOME: the VM's GDM autologs in (vminstall.sh); wait for the shell.
    for _ in $(seq 60); do pgrep -u "$USER" -x gnome-shell >/dev/null && break; sleep 3; done
    pgrep -u "$USER" -x gnome-shell >/dev/null || { sudo systemctl restart gdm; for _ in $(seq 40); do pgrep -u "$USER" -x gnome-shell >/dev/null && break; sleep 3; done; }
fi
for f in /etc/pacman.d/*mirrorlist*; do sudo sed -i '/krfoss/s/^Server/#Server/' "$f"; done
# the host's package cache over pacman's
sudo mkdir -p /var/cache/steamify-pkg
if sudo mount -t 9p -o trans=virtio,version=9p2000.L cache /var/cache/steamify-pkg 2>/dev/null; then
    sudo mkdir -p /var/cache/steamify-pkg/pkg; sudo mount --bind /var/cache/steamify-pkg/pkg /var/cache/pacman/pkg
    # Steamify's own downloads (the CEC driver: GitHub rate-limits it) once for every VM
    sudo mkdir -p /var/cache/steamify-pkg/steamify /var/cache/steamify; sudo mount --bind /var/cache/steamify-pkg/steamify /var/cache/steamify
fi
if [[ $DESK == kde ]]; then
    pgrep -u "$USER" -x plasmashell >/dev/null && echo "Logged in to Plasma." || { echo "Plasma did not start." >&2; exit 1; }
else
    pgrep -u "$USER" -x gnome-shell >/dev/null && echo "Logged in to GNOME." || { echo "GNOME did not start." >&2; exit 1; }
fi
REMOTE
}

# A block with "# base: applied" in its header starts from a second base image where Steamify is already applied (everything on,
# packages and DKMS modules built): blocks that only check state need not repeat the apply. Rebuilt when Steamify's files change.
applied="$src/base-applied.qcow2"; applied_all=gaming,theme,glyphs,single,launcher,notify,cec,machine,poweroff
applied_stamp() { (cd "$REPO" && find steamify.sh lib patches services -type f | sort | xargs sha256sum | sha256sum | cut -c1-16); }
prepare_applied() {
    [[ -f "$applied" && "$(cat "$applied.stamp" 2>/dev/null)" == "$(applied_stamp)" ]] && return 0
    echo "Making $applied (Steamify applied once, a few minutes)..." >&2
    cur_base=$base; cur_vars=$src/vars.ssh-ready.fd
    vm_fresh > /tmp/vmsuite-$suite-reset.out 2>&1 || return 1
    cat "$repo/share/vmtest/prelude.sh" - <<EOT | vm_ssh -o ConnectTimeout=6 -o LogLevel=ERROR bash -s >/dev/null 2>&1
sf --defaults --options $applied_all >/dev/null || exit 1
EOT
    local rc=$?
    vm_stop
    [[ $rc -eq 0 ]] || return 1
    qemu-img convert -O qcow2 "$VM_DIR/disk.qcow2" "$applied.tmp" && mv "$applied.tmp" "$applied" &&
        cp "$VM_DIR/vars.fd" "$src/vars.applied.fd" && applied_stamp > "$applied.stamp"
}

# Progress: one "~~" line before every block (and one at the end) with a bar, the share of blocks done and the checks so far (blocks are known up front, so
# the percentage needs no list of expected check counts that goes stale). The line starts with "~~", which none of the parsers
# (vmprogress.sh, vmtest.sh) looks for.
blocks_total=0
for block in "$dir"/*.sh; do
    [[ -z "${ONLY:-}" || "$(basename "$block")" == "$ONLY"* ]] && blocks_total=$((blocks_total + 1))
done
blocks_done=0
progress() {   # progress <passed> <failed>: the blocks done so far
    local pct=$((blocks_done * 100 / (blocks_total > 0 ? blocks_total : 1))) cells=$((blocks_done * 20 / (blocks_total > 0 ? blocks_total : 1))) bar="" i
    for ((i = 0; i < 20; i++)); do (( i < cells )) && bar+="█" || bar+="░"; done
    printf '~~ %s %3d%%  block %d/%d  %d passed, %d failed\n' "$bar" "$pct" "$blocks_done" "$blocks_total" "$1" "$2"
}
count_checks() { grep -ac "^$1" "$log" 2>/dev/null || true; }
{
printf '\n===== vmsuite.sh %s (%s) =====\n' "$suite" "$(date +%T)"
for block in "$dir"/*.sh; do
    [[ -z "${ONLY:-}" || "$(basename "$block")" == "$ONLY"* ]] || continue   # ONLY=50: just that block
    progress "$(count_checks PASS)" "$(count_checks FAIL)"
    blocks_done=$((blocks_done + 1))
    printf '\n##### %s %s\n' "$(date +%T)" "$(basename "$block" .sh)"
    if ! head -n 8 "$block" | grep -q '^# since: '; then echo "FAIL $(basename "$block" .sh): no '# since: X.Y.Z' tag in its first 8 lines (every check says from which Steamify version it applies)"; continue; fi
    if why="$(block_version_skip "$block")"; then echo "SKIP $(basename "$block" .sh): $why"; continue; fi
    cur_base=$base; cur_vars=$src/vars.ssh-ready.fd
    if head -n 5 "$block" | grep -q '^# base: applied'; then
        ( flock 8; prepare_applied ) 8>"$src/.applied.lock" && cur_base=$applied && cur_vars=$src/vars.applied.fd || echo "INFO no applied base, using the clean one"
    fi
    vm_fresh $(sed -n 's/^# env: //p' "$block" | head -n 1) > /tmp/vmsuite-$suite-reset.out 2>&1 \
        || { echo "FAIL the VM did not come up: $(tail -n 1 /tmp/vmsuite-$suite-reset.out)"; continue; }
    if [[ "$block" == *.host.sh ]]; then   # runs on the host (reboots, host scripts); prelude-host.sh has the helpers
        ( . "$repo/share/vmtest/prelude-host.sh"; . "$block" ) 2>&1 | sed -u 's/\x1b\[[0-9;]*m//g'
        continue
    fi
    cat "$repo/share/vmtest/prelude.sh" "$block" | vm_ssh -o ConnectTimeout=6 -o LogLevel=ERROR bash -s 2>&1 | sed -u 's/\x1b\[[0-9;]*m//g'
done
progress "$(count_checks PASS)" "$(count_checks FAIL)"
vm_stop
} 2>&1 | tee "$log" | sed -u "s/^/[$suite] /" >> "$TEST_LOG"
rc=${PIPESTATUS[0]}   # an abort inside the braces must not pass as 0 failed checks
fails="$(grep -c '^FAIL' "$log")"
if [[ $rc -ne 0 && $fails -eq 0 ]]; then
    echo "FAIL $suite aborted (exit $rc): $(grep -v '^$' "$log" | tail -n 1)" | tee -a "$log"; fails=1
fi
echo "== $suite: $(grep -c '^PASS' "$log") passed, $fails failed, $(grep -c '^SKIP' "$log") skipped (log: $log)" | tee -a "$log"
# A whole run of the suite: its number of checks is what the progress viewer expects of the next one.
if [[ -z "${ONLY:-}" && ( $rc -eq 0 || $fails -gt 0 ) ]] && grep -aq '^PASS' "$log"; then
    mkdir -p "$(dirname "$TEST_LOG")/expected"; grep -acE '^(PASS|FAIL|SKIP) ' "$log" > "$(dirname "$TEST_LOG")/expected/$suite"
fi
grep '^FAIL' "$log"
exit "$fails"
