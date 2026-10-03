#!/bin/bash
# Golden-output test for the menu rules (lib/menu.sh, lib/backend.sh): what
# toggling does to WANTED, what plan_changes picks, and the JSON the app and
# the installer read. Hardware and package state are stubbed, so no root, VM
# or hardware is needed.
#   bash tests/menu-test.sh            compare with menu-test.golden
#   bash tests/menu-test.sh --update   rewrite the golden file (review the diff!)
# The Steamify checkout (REPO, default: the steamify-cachyos next to this repo)
REPO="${REPO:-$(cd "$(dirname "$0")/../../steamify-cachyos" && pwd)}"; HERE="$(cd "$(dirname "$0")" && pwd)"; cd "$REPO" || exit 1
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT

SCRIPT_DIR="$PWD"; HOME="$T/home"; mkdir -p "$HOME"
VERSION=0.0.0
for lib in common state packages login-manager single-user steam-desktop steam-machine fremont-poweroff vram-booster hdmi-refresh nvidia controllers cec boot-session vapor-theme steamos-extras bios desktop-shortcut wizard-shortcut steam-game update-notifier first-login menu backend; do
    source "lib/$lib.sh"
done
info() { :; }; ok() { :; }; warn() { :; }; err() { :; }
# From the entry point.
RESTART_FOR_LOGIN=false; restart_needed() { return 1; }

# Hardware profile and what is "on", set per scenario.
HW=""; ON=""
has() { [[ " $HW " == *" $1 "* ]]; }
nvidia_present() { has nvidia; }
nvidia_available() { has nvidia; }
bigpicture_available() { has nvidia; }
machine_available() { has fremont; }
detect_valve_fremont() { has fremont; }
vram_available() { has vram; }
vram_selectable() { return 0; }
steamgame_available() { has steam; }
kpin_available() { has fremont && [[ " $ON " == *" kpin "* ]]; }
hdmi_available() { return 1; }
bios_available() { return 1; }
bios_selectable() { return 1; }
cec_repair() { return 1; }
launcher_repair() { return 1; }
bios_lookup_newest() { :; }
kernel_overview() { :; }
os_version_refresh() { :; }
for c in "${COMPONENTS[@]}"; do
    eval "${c}_status() { [[ \" \$ON \" == *\" $c \"* ]]; }"
done

show() {
    # show <label>: WANTED as the ticked ids, then the plan.
    local c w=""
    for c in "${COMPONENTS[@]}"; do [[ "${WANTED[$c]:-0}" == 1 ]] && w+=" $c"; done
    echo "$1"
    echo "  wanted:$w"
    plan_changes
    echo "  disable: ${TO_DISABLE[*]:-}"
    echo "  enable:  ${TO_ENABLE[*]:-}"
}

scenario() {
    # scenario <name> <hardware> <on> [toggle...]
    local name="$1"; HW="$2"; ON="$3"; shift 3
    rm -rf "$STATE_DIR"; REAPPLY=false
    detect_components
    local t
    for t in "$@"; do toggle_component "$t"; done
    show "== $name"
}

run() {
    scenario "pc first run" "" ""
    scenario "pc first run, untick gaming" "" "" gaming
    scenario "pc single on" "" "" gaming single
    scenario "pc single then gaming off" "" "" single gaming
    scenario "pc boot desktop" "" "" boot
    scenario "pc boot desktop then gaming off" "" "" boot gaming
    scenario "pc silent only" "" "gaming" silent
    scenario "pc all on, theme off" "" "gaming boot silent theme glyphs single launcher steamgame notify" theme
    scenario "pc launcher off" "" "launcher steamgame" launcher
    scenario "pc steamgame on without launcher" "steam" "" gaming launcher steamgame
    scenario "machine first run" "fremont steam vram" ""
    scenario "machine silent hidden until boot desktop" "fremont steam vram" "gaming silent"
    scenario "machine boot desktop keeps silent" "fremont steam vram" "gaming silent" boot
    scenario "machine off" "fremont steam vram" "gaming machine poweroff" machine
    scenario "machine poweroff off" "fremont steam vram" "gaming machine poweroff" poweroff
    scenario "machine poweroff on brings machine" "fremont steam vram" "gaming" poweroff
    scenario "machine kpin removal" "fremont steam vram" "gaming machine poweroff kpin"
    scenario "nvidia first run" "nvidia steam" ""
    scenario "nvidia bigpicture off" "nvidia steam" "nvidia bigpicture" bigpicture
    scenario "nvidia nvsilent on" "nvidia steam" "nvidia bigpicture" nvsilent
    scenario "nvidia nvsilent then bigpicture" "nvidia steam" "nvidia" nvsilent bigpicture
    scenario "nvidia off" "nvidia steam" "nvidia bigpicture nvsilent" nvidia
    scenario "nvidia single" "nvidia steam" "" single
    scenario "nvidia gaming already on" "nvidia steam" "gaming" gaming

    # Feature versions: an old record is ticked and re-applied.
    HW=""; ON="gaming theme"; rm -rf "$STATE_DIR"; REAPPLY=false
    state_set features gaming 2.1.0; state_set features theme 2.1.0
    detect_components; show "== outdated features"
    REAPPLY=true; ON="gaming theme launcher"; detect_components; show "== reapply (a)"
    REAPPLY=false

    # The app's own rules (backend_apply's normalisation) go through the same plan.
    HW="fremont steam vram"; ON=""; rm -rf "$STATE_DIR"
    detect_components
    local sel
    for sel in "single" "boot" "poweroff" "silent" "kpin" "gaming boot" "launcher steamgame"; do
        echo "== backend_apply $sel"
        backend_sudo() { return 0; }
        backend_run_component() { return 0; }
        # shellcheck disable=SC2086
        backend_apply $sel | jq -c 'select(.event == "plan")'
    done
    HW="nvidia steam"; ON=""; detect_components
    for sel in "bigpicture" "nvsilent" "bigpicture nvsilent" "single" "boot"; do
        echo "== backend_apply nvidia $sel"
        # shellcheck disable=SC2086
        backend_apply $sel | jq -c 'select(.event == "plan")'
    done

    # JSON for the app and the installer page.
    local hw
    for hw in "" "fremont steam vram" "nvidia steam"; do
        HW="$hw"; ON=""; rm -rf "$STATE_DIR"; detect_components
        echo "== defaults_list [$hw]"
        defaults_list | jq -S -c '.[]'
        echo "== backend_status [$hw]"
        backend_status | jq -S -c 'del(.kernel, .cecDevices, .leds)'
    done
}

if [[ "${1:-}" == --update ]]; then
    run > "$HERE/menu-test.golden" 2>&1
    echo "wrote $HERE/menu-test.golden ($(wc -l < "$HERE/menu-test.golden") lines)"
elif diff -u "$HERE/menu-test.golden" <(run 2>&1); then
    echo "ok   menu rules, plan and JSON match the golden file"
else
    echo "FAIL menu rules changed (diff above; --update if intended)"; exit 1
fi
