# Steamify cleanup plan (login / session code)

Written 2026-10-19 for the next session (it lives in this repo, like the notes of any feature: see AGENTS.md).
Code branch: the existing `feature/code-cleanup` of `steamify-cachyos` is the optimization branch (decided
2026-10-19); it is brought up to date with `release/2.14.0` (not main-ready) and the cleanup lands from there.
The `TECHNICAL.md` / `AGENTS.md` updates for the cleanup are made on that branch too, not on a release branch. Rules: `steamify-cachyos/AGENTS.md` (feature branch -> PR **into the release branch**, one changelog
line per commit with its hash, user merges into main), no `Co-Authored-By` / "Generated with" lines anywhere,
commit identity per command (`-c user.name="Rick Peters" -c user.email="rickpeters@upriser.nl"`), never
change git config.

## Goal
Make the login/session code simpler and safe to change: one place decides who logs in when, legacy cleanup
in one place, fewer hidden globals, consistent error handling, and tests that would have caught the
`gsn_enable` regression (2.12.1/2.13.0, fixed in 2.13.1).

## Morning decisions (before any code)
1. **`feature/code-cleanup` is the optimization branch** (decided): 15 commits and 46 files against v2.12.0
   (the first count of "313 commits, 95 files" came from a stale local `main` and was wrong), based on an
   unreleased 2.12.0, with `best_effort`, shared JSON helpers and dependency-rule tables. First merge
   `release/2.14.0` into it (the release branch is merged into the feature branch, AGENTS.md); expect heavy
   conflicts in `lib/login-manager.sh`, `lib/menu.sh`, `lib/backend.sh`, `lib/desktop-shortcut.sh`,
   `lib/single-user.sh`, `steamify.sh` and the docs. Resolve by keeping its helpers (`best_effort`,
   JSON head, tables) and 2.14's behaviour; diff every resolved function against `release/2.14.0`.
   Then split the work into smaller `feature/` branches off it, or work on it directly if the user prefers.
2. **Version:** the cleanup ships with 2.14.0 (it is not main-ready), as PRs into `release/2.14.0` from the
   optimization branch (or its sub-branches). `TECHNICAL.md` / `AGENTS.md` are updated on that branch.
3. **Scope of the risky items** (3 and 4 below): do them now or leave for a later release.

## Phase 0: green baseline (dev repo, `steamify-cachyos-dev`)
- Today 12 tests fail on `main` (NVIDIA, python helpers, golden from another tree) and 2 more on 2.14
  (`single` needs a KDE session in `component_available`). Sort each into: stale test, real bug, or
  environment (no KDE/GNOME session in the test box). Fix or stub; regenerate `menu-test.golden` against 2.14.
- Commit the two files already modified there (`tests/menu-test.golden`, `tests/nvidia-test.sh`).
- Exit criterion: `make test` passes on `release/2.14.0`.

## Phase 1: characterization tests (write before refactoring)
Pin down today's behaviour so the refactors cannot change it silently:
- `gaming_enable` call order per login manager (plasmalogin, gdm), incl. `gsn_enable` first and
  `single_login_release`; a failing `gsn_enable` aborts.
- `set_login_mode single|multi`: files written/removed, units installed/removed (stub `sudo`, `systemctl`).
- Relogin helper: stub `loginctl`; writes the file, empties it when the session id changes, times out.
- Greeter-session script: boot-into gamescope / desktop, keeps other users' entries (already hand-tested).
- Shortcut: name follows "Boot into", rename on change, icon update, removal (hand-tested with stubs).
- Legacy migration: from a fake SDDM + sync-bridge + sudoers layout to the current one leaves nothing behind.

## Phase 2: refactors (one `feature/` branch + PR each, smallest first)
Always diff a rewritten function against the last release before committing. Docs (`TECHNICAL.md`, `AGENTS.md`)
are updated together with each step, on the optimization branch.

| # | Change | Why | Risk |
|---|---|---|---|
| 2a | `remove_legacy_login_setup`: SDDM files, sync bridge, sudoers rule, old shortcut names in one function, called once from `gaming_enable`/`gaming_disable` | removed from 5 places today; `remove_sddm_autologin` runs twice in a branch | low |
| 2b | `login_reconcile`: the single writer for autologin fragment, relogin helper, greeter session; replaces `set_login_mode` + `single_wanted` + the NVIDIA-only `single_login_*` writer | the mode is decided in 3 places and reads `WANTED` | medium |
| 2c | systemd helpers `install_unit` / `install_dropin` + one deferred `daemon-reload` | 7 reloads, 10 `sudo tee` unit writes in `login-manager.sh`; the two PLM drop-ins become one generated file | low |
| 2d | error handling: adopt `best_effort` (logged) where failure does not matter; no silent `|| true`; real errors `return 1` | inconsistent today | low |
| 2e | shortcut ownership: break the `boot-session` <-> `desktop-shortcut` cycle; split `create_desktop_shortcut` (69 lines: KDE, GNOME, name, icon) | circular calls | medium |
| 2f | `choose_login_manager` returns a value instead of setting `LOGIN_MANAGER`; limit `WANTED` reads to menu/backend | hidden parameters | medium |
| 2g | (optional) `gaming_status` from a recorded layout version in the state files instead of probing files; legacy detection becomes a migration | robustness | higher: needs migration tests |

Order: 2a, 2c, 2d (mechanical) -> 2b -> 2e, 2f -> 2g only if time. After each PR: `make test`, then the
hardware pass below. Update `TECHNICAL.md` / `AGENTS.md` / changelog in the same PR.

## Hardware pass after each merge into `release/2.14.0`
- Steam Machine (`steammachine`, AMD): multi-user and single user; reboot; login screen preselects
  gamescope; Switch to Desktop and Return to Gaming Mode (both directions, no login screen); manual Log Out
  shows the login screen; Sunshine at the login screen.
- This PC (RTX 5080, NVIDIA): apply 2.13.1+ from the app; `gsn_enable` runs (patched gamescope check);
  Boot into desktop: shortcut reads "Switch to Gaming Mode".
- GNOME/GDM: no hardware; keep the GDM code paths untouched and covered by the characterization tests only.

## Definition of done
- `make test` green on `release/2.14.0`; new tests cover items 2a-2d at least.
- No behaviour change on KDE (verified on both machines) and a changelog line + hash per commit.
- Docs (`TECHNICAL.md`, `AGENTS.md`) describe the new structure; no `best_effort`-style helper is used
  before it exists in the branch (that bit me once).

## Known open items (not part of the cleanup)
- Multi-user mode on GDM: not implemented (GDM has no login-screen mode in Steamify).
- Before 2.14.0 can go to main: README screenshot retake, `TESTPLAN.md` (R1.3, R1.9, H4 still say SDDM),
  GNOME hardware test, decide `feature/gnome-prototype` branch.

## Status (2026-10-19, end of the first session)

Done, in `steamify-cachyos` on `feature/code-cleanup` (nothing is on `main`; PRs #99, #100, #101, #102 merged into it):
- `release/2.14.0` merged into it; the rule tables replace the inline rules (checked equal on 9000 random
  selections over six hardware profiles, the one difference is the documented steamgame -> launcher rule).
- Phase 0: all suites green here (`feature/menu-test`): controllers 26, login 37, menu golden, nvidia 72, python.
- Phase 1: `tests/login-test.sh` (37 checks), written against the unchanged code first.
- Phase 2: 2a, 2b, 2c, 2d (login code: one legacy cleanup, `set_login_mode`, systemd helpers, one drop-in, `best_effort`),
  2e, 2f (no `LOGIN_MANAGER` global, shortcut refresh after a run). Not done: 2g (state-based `gaming_status`).
- Also fixed: the Lint workflow (it had never run on a runner: qmllint options, an unused import); `qml` stays non-blocking
  (the runner's qmllint is 6.4). A real bug found on hardware: `plasmalogin_dropin_write` returned 1 in single user mode under
  `pipefail`; the tests now run with `pipefail`.
- Hardware, `steammachine` (AMD, single user -> multi-user -> single user): the update from the 2.13.x layout works, files as expected.

Still to do before `feature/code-cleanup` goes into `release/2.14.0`:
- Reboot `steammachine` and check: login screen / autologin as the mode says, Switch to Desktop and Return to Gaming Mode
  both ways, manual Log Out in multi-user mode, Sunshine at the login screen.
- This PC (RTX 5080, boots into the desktop, needs sudo): apply the update from the app; `gsn_enable` runs; the shortcut reads
  "Switch to Gaming Mode".
- GNOME/GDM has no hardware here: covered by the characterization tests only.
- The dev repo's `main` has a different history than `feature/menu-test` (110 ahead, 121 behind): how these tests reach
  `main` is for the user to decide.
