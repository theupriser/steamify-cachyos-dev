#!/bin/bash
# The whole automated test, one command: the boot loader test for every loader the Steamify ISO
# advertises, plus every suite in share/vmtest/ (TESTPLAN.md rows that need no person).
#   scripts/vmtest.sh [--install] [--window] [--screen] [boot | <loader>... | <suite>...]
#   no argument   everything: boot (all advertised loaders) and all suites
#   boot          the boot loader test (limine, systemd-boot, grub), or name loaders
#   <suite>       cli, menu, hw, installer, toggles (folders in share/vmtest/)
#   --install     install the boot loader VMs first from the newest Steamify ISO (asks before replacing a disk)
#   --window      show the VMs' windows (default: headless; one shared Konsole follows ~/vms/test.log)
#   MAX_PARALLEL=3 (env) VMs at once; the slowest suites start first
#   --screen      run in a detached `screen` session named vmtest: `screen -r vmtest` to watch, Ctrl-a d to leave
# The suites run on the plain CachyOS VM ~/vms/steamify-vm (Plasma, from vminstall.sh --iso <CachyOS ISO>
# with VM_STEAMIFY=skip); the boot loader test on ~/vms/bl-<loader> (Steamify ISO).
# Output: one line per loader/suite and the failed checks; the same in ~/vms/last-test.txt. Exit status = failures.
# Rows that need a person (screenshots, the real Steam Machine) are listed at the end, never silently dropped.
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/.." && pwd)"
iso_repo="$repo/../steammachine-cachyos-live-iso"
args=("$@")
install=""; window=""; screen=false; loaders=(); suites=(); want_boot=false
for a in "$@"; do
    case "$a" in
        --install) install=--install ;;
        --window) window=--window ;;
        --screen) screen=true ;;
        boot) want_boot=true ;;
        limine|systemd-boot|grub) loaders+=("$a"); want_boot=true ;;
        *) [[ -d "$repo/share/vmtest/$a" ]] && suites+=("$a") || { echo "Unknown argument: $a" >&2; exit 2; } ;;
    esac
done
if $screen; then
    command -v screen >/dev/null || { echo "screen is not installed" >&2; exit 2; }
    screen -ls | grep -q '\.vmtest\s' && { echo "A vmtest screen session is already running: screen -r vmtest" >&2; exit 1; }
    rest=(); for a in "${args[@]}"; do [[ "$a" == --screen ]] || rest+=("$a"); done
    screen -dmS vmtest bash -c "$(printf '%q ' "$0" "${rest[@]}"); echo; echo 'Done (summary: ~/vms/last-test.txt). Press Enter to close.'; read -r _"
    echo "Running in the screen session vmtest: screen -r vmtest (Ctrl-a d to leave it running); the summary lands in ~/vms/last-test.txt"
    exit 0
fi
if [[ ${#loaders[@]} -eq 0 && ${#suites[@]} -eq 0 ]] && ! $want_boot; then
    want_boot=true
    for d in cli menu hw installer toggles; do [[ -d "$repo/share/vmtest/$d" ]] && suites+=("$d"); done
fi
# What the ISO advertises: the boot loaders calamares-online.sh keeps.
advertised="$(sed -n 's/.*"bootloader:\([^"]*\)".*/\1/p' "$iso_repo/archiso/airootfs/usr/local/bin/calamares-online.sh" 2>/dev/null | head -n 1)"
[[ -n "$advertised" ]] || { echo "Can't read the advertised boot loaders from $iso_repo (calamares-online.sh)" >&2; exit 2; }
$want_boot && [[ ${#loaders[@]} -eq 0 ]] && read -r -a loaders <<< "$advertised"
tested="limine systemd-boot grub"   # the loaders vmbootloadertest.sh has a way to boot the other kernel for
summary="$HOME/vms/last-test.txt"
maxp="${MAX_PARALLEL:-3}"   # VMs at once: 8 GB RAM each, 6 vCPUs each
# Jobs, the slowest first so the last ones are short: suites, then the boot loaders.
jobs_list=()
for s in toggles hw cli menu installer; do [[ " ${suites[*]} " == *" $s "* ]] && jobs_list+=("suite:$s"); done
for s in "${suites[@]}"; do [[ " toggles hw cli menu installer " == *" $s "* ]] || jobs_list+=("suite:$s"); done
for l in "${loaders[@]}"; do jobs_list+=("loader:$l"); done
run_job() {   # run_job <kind:name>: output in /tmp/vmtest-<name>.out, exit status in /tmp/vmtest-<name>.rc
    local kind="${1%%:*}" name="${1#*:}"
    if [[ "$kind" == loader ]]; then bash "$here/vmbootloadertest.sh" "$name" $install $window > "/tmp/vmtest-$name.out" 2>&1
    else bash "$here/vmsuite.sh" "$name" $window > "/tmp/vmtest-$name.out" 2>&1; fi
    echo $? > "/tmp/vmtest-$name.rc"
}
{
echo "vmtest.sh $(date '+%F %T') branch $(git -C "$repo" branch --show-current) $(git -C "$repo" rev-parse --short HEAD)"
total=0
for l in $advertised; do
    [[ " $tested " == *" $l "* ]] || { echo "FAIL the ISO advertises $l, but there is no test for it (scripts/vmbootloadertest.sh)"; total=$((total + 1)); }
done
[[ ${#suites[@]} -gt 0 ]] && { bash "$here/vmsuite.sh" --prepare || { echo "FAIL no base image for the suites"; total=$((total + 1)); }; }
rm -f /tmp/vmtest-*.rc
for job in "${jobs_list[@]}"; do
    run_job "$job" &
    while [[ $(jobs -rp | wc -l) -ge $maxp ]]; do wait -n; done
done
wait
for job in "${jobs_list[@]}"; do
    name="${job#*:}"
    sed -n '/^== /,$p' "/tmp/vmtest-$name.out"
    total=$((total + $(cat "/tmp/vmtest-$name.rc" 2>/dev/null || echo 1)))
done
echo
echo "SKIP (needs a person, TESTPLAN.md): U1-U9 the app's screens, R2.2 the first desktop login, H-Real the real Steam Machine"
echo "== total: $total failed check(s); boot loaders: ${loaders[*]:-none}; suites: ${suites[*]:-none}"
} 2>&1 | tee "$summary"
exit "$(grep -c '^FAIL' "$summary")"
