#!/bin/bash
# Progress of test jobs, one line per change (for a monitor; see the progress-report skill).
#   scripts/vmprogress.sh [--once] [job...]   jobs: limine systemd-boot grub cli menu hw installer toggles (default all)
# Per job (only a new step, a finished job or a FAIL counts as a change): state (install NN% <stage> / <test step> / done / -), checks passed/expected, failed.
# Line: "HH:MM total P/E F failed ;; job | state | P/E | F failed ;; ...". Prints nothing while nothing
# changes (checked every 30 s), "ALLDONE" and exits once every started job has its summary line.
# Expected counts: the last complete run of each (AGENTS.md "State"); update them when checks are added.
set -uo pipefail
declare -A expect=([limine]=43 [systemd-boot]=42 [grub]=42 [cli]=55 [menu]=36 [hw]=77 [installer]=4 [toggles]=42)
once=false; jobs=()
for a in "$@"; do [[ "$a" == --once ]] && once=true || jobs+=("$a"); done
[[ ${#jobs[@]} -gt 0 ]] || jobs=(limine systemd-boot grub cli menu hw installer toggles)
vms="$HOME/vms"

status() {   # status <job>: "state|pass|fail|finished(0/1)|started(0/1)"
    local j="$1" log dir
    case "$j" in limine|systemd-boot|grub) log="$vms/bl-$j.test.log" dir="$vms/bl-$j" ;; *) log="$vms/run-$j.log" dir="$vms/run-$j" ;; esac
    [[ -f "$log" ]] || { echo "-|0|0|0|0"; return; }
    local p f st run
    # The logs are appended to: only the latest run counts (from its "===== vm..." header on).
    run="$(tac "$log" | sed '/^===== vm/q' | tac)"
    p=$(grep -ac '^PASS' <<< "$run"); f=$(grep -ac '^FAIL' <<< "$run")
    if grep -aq "^== $j: [0-9]* passed" <<< "$run"; then echo "done|$p|$f|1|1"; return; fi
    st=$(grep -aE '^##### ' <<< "$run" | tail -1 | sed 's/^##### [0-9:]* //' | cut -c1-40)
    if [[ "$st" == install* && -f "$dir/install-www/install.log" ]]; then
        st="install $(grep -aoE '^\[ *[0-9.]+%\] [^.(]*' "$dir/install-www/install.log" | tail -1 | sed 's/^\[ *\([0-9]*\)[0-9.]*%\] /\1% /; s/ *$//')"
        # The live installer's own failure (vminstall-live.sh: "== failed: ..."), or the host side giving up.
        local why; why=$(grep -ahE '^== failed: ' "$dir/install-www/install.log" "$log" 2>/dev/null | tail -1 | cut -c12-70)
        [[ -n "$why" ]] && { st="INSTALL FAILED: $why"; f=$((f + 1)); }
    fi
    echo "${st:-starting}|$p|$f|0|1"
}

prev=""
while true; do
    line="" tp=0 te=0 tf=0 running=0
    for j in "${jobs[@]}"; do
        IFS='|' read -r st p f fin started <<< "$(status "$j")"
        [[ "$started" == 1 && "$fin" == 0 ]] && running=$((running + 1))
        tp=$((tp + p)) tf=$((tf + f)) te=$((te + ${expect[$j]:-0}))
        line+=" ;; $j | $st | $p/${expect[$j]:-?} | $f failed"
    done
    cur="total $tp/$te $tf failed$line"
    # A change is a new stage/step, a job finishing or a FAIL: not a new install percentage or PASS count.
    key="$(sed -E 's/install [0-9]+% /install /g; s/\| [0-9]+\/[0-9?]+ \|/|/g; s/^total [0-9]+\/[0-9]+ //' <<< "$cur")"
    [[ "$key" != "$prev" ]] && { echo "$(date +%H:%M) $cur"; prev="$key"; }
    $once && exit 0
    [[ $running -eq 0 ]] && { echo ALLDONE; exit 0; }
    sleep 30
done
