# Sourced in front of a *.host.sh block (scripts/vmsuite.sh): the block runs on the host with the VM's ssh helpers.
. "$repo/scripts/common.sh"
info() { echo "INFO $*"; }
pass() { echo "PASS $*"; }; fail() { echo "FAIL $*"; }; skip() { echo "SKIP $*"; }
# guest <cmd...>: a command in the guest with the Plasma session environment and Steamify's libs
guest() { { cat "$repo/share/vmtest/prelude.sh"; echo "$*"; } | vm_ssh -o ConnectTimeout=6 -o LogLevel=ERROR bash -s 2>&1 | sed 's/\x1b\[[0-9;]*m//g'; }
waitssh() { local _; for _ in $(seq 60); do vm_ssh -o ConnectTimeout=4 'uptime -p' >/dev/null 2>&1 && return 0; sleep 5; done; return 1; }
reboot_guest() { vm_ssh 'sudo systemctl reboot' >/dev/null 2>&1; sleep 25; waitssh; }
