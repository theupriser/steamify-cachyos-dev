#!/bin/bash
# Record what the bash backend (steamify.sh in $REPO) prints, per fixture, into share/golden/expected/.
#   share/golden/record.sh            record all    |    share/golden/record.sh check   compare with the recorded files
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
export REPO="${REPO:-$here/../../../steamify-cachyos}"; REPO="$(cd "$REPO" && pwd)"
backend="${BACKEND:-bash $REPO/steamify.sh}"
mode="${1:-record}"; failures=0; work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
# case name -> backend arguments
# status: the whole output. plan-*: only the first line of the apply stream (the plan event, where the rules live);
# the steps after it need the real system (the VM suite), they are not stable with a fake sudo.
cases=("status:--backend status"
    "plan-gaming:--backend apply gaming"
    "plan-gaming-desktop:--backend apply --boot desktop gaming boot"
    "plan-single:--backend apply single"
    "plan-poweroff:--backend apply poweroff"
    "plan-nothing:--backend apply"
    "plan-nvidia:--backend apply nvidia bigpicture")
for fixture in "$here"/fixtures/*/; do
    name="$(basename "$fixture")"
    for entry in "${cases[@]}"; do
        label="${entry%%:*}"; arguments="${entry#*:}"
        expected="$here/expected/$name.$label.json"; mkdir -p "$here/expected"
        if [[ "$label" == plan-* ]]; then   # the plan event comes first; then the steps run for real, so stop after a moment
            timeout -s KILL 5 "$here/sandbox.sh" "$fixture" $backend $arguments > "$work/stream" 2>&1
            actual="$(head -n 1 "$work/stream")"
        else actual="$("$here/sandbox.sh" "$fixture" $backend $arguments 2>&1)"; fi
        if [[ "$mode" == record ]]; then printf '%s\n' "$actual" > "$expected"; echo "recorded $expected"
        elif ! diff -u "$expected" <(printf '%s\n' "$actual"); then echo "FAIL $name $label"; failures=$((failures+1))
        else echo "PASS $name $label"; fi
    done
done
exit $failures
