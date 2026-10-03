#!/bin/bash
# Unit tests of the Python helpers in steamify-cachyos/patches (steam-shortcuts.py,
# steamify-notifier.py). No root, VM or hardware needed: bash tests/python-test.sh
# The Steamify checkout (REPO, default: the steamify-cachyos next to this repo)
REPO="${REPO:-$(cd "$(dirname "$0")/../../steamify-cachyos" && pwd)}"
export REPO
cd "$(dirname "$0")/.." || exit 1
if python3 -B -m unittest tests/patches_test.py 2>&1 | tail -n 25 | tee /dev/stderr | grep -q '^OK'; then
    echo "ok   Python helpers"
else
    echo "FAIL Python helpers"; exit 1
fi
