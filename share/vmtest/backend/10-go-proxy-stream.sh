# Go core (REFACTOR-2.12 phase 0/1): `steamify --backend apply` through the Go binary must emit the
# same event stream as the bash backend: enable two small items, then turn them off again, once with
# each backend, in the same VM. Needs the binary built in the repo (make build -> bin/steamify).
GO=/mnt/bin/steamify
[[ -x $GO ]] || { fail "no $GO (run make build in steamify-cachyos)"; exit 0; }
export STEAMIFY_NO_DOWNLOAD=1
backend_run() {   # backend_run <label> <command...>: the event stream of one apply, log lines dropped
    # Only the structure (plan, start, done, finished): the log lines of the first run hold pacman's install output, which the
    # second run on the same machine does not repeat.
    "$@" 2>&1 < /dev/null | sed 's/\x1b\[[0-9;]*m//g' | grep -v '^{"event":"log"'
}
status_json() { "$@" --backend status 2>/dev/null; }

info "status through both backends"
bash_status=$(bash /mnt/steamify.sh --backend status 2>/dev/null); go_status=$($GO --backend status 2>/dev/null)
[[ -n $bash_status && "$bash_status" == "$go_status" ]] && pass "status identical" || fail "status differs"

for step in "launcher notify" ""; do
    # shellcheck disable=SC2086
    bash_events=$(backend_run bash /mnt/steamify.sh --backend apply $step)
    # put the machine back for the Go run
    # shellcheck disable=SC2086
    if [[ -n $step ]]; then backend_run bash /mnt/steamify.sh --backend apply >/dev/null; else backend_run bash /mnt/steamify.sh --backend apply launcher notify >/dev/null; fi
    # shellcheck disable=SC2086
    go_events=$(backend_run $GO --backend apply $step)
    label="apply ${step:-nothing (turn off)}"
    if [[ "$bash_events" == "$go_events" ]]; then pass "$label: same event stream ($(wc -l <<< "$bash_events") lines)"
    else fail "$label: streams differ: $(diff <(echo "$bash_events") <(echo "$go_events") | head -6 | tr '\n' '|')"; fi
done
grep -q '"finished"' <<< "$go_events" && pass "Go run finished" || fail "no finished event: $(tail -n 2 <<< "$go_events")"
