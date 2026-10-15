# Steamify on GNOME (GDM): prototype plan

## Test status 2026-10-15
Automated suite `gnome` (`scripts/vmsuite.sh gnome`, TESTPLAN F-GNOME, GN1-GN7): all pass, including session switching with the stand-in session, reboot persistence, boot into desktop, KDE+GNOME together. KDE regression (6 suites) passes on the branch. Open item (6) of the list below (GNOME regression run) is done; the rest stands.

## 2.13.0 release branch on the RTX 5080 PC (hardware session 2026-10-15 evening): results and what to test in the VM next
Setup: `release/2.13.0` (steamify-cachyos PRs #85-#93 merged) on a fresh CachyOS + GNOME install, 3440x1440 monitor. The test copy lives in
`~/steamify-cachyos` and the app was started **as a user unit inside the GNOME session** (`systemd-run --user --unit=... python3 ./steamify-ui
--windowed` with `XDG_RUNTIME_DIR` and `DBUS_SESSION_BUS_ADDRESS` set), NOT from a plain ssh command: that has no `XDG_CURRENT_DESKTOP`
(so no own window frame on GNOME: no minimize/close buttons) and no polkit session (`systemctl reboot` fails silently). The remote login
shell is fish (send scripts to `bash -s`). GNOME blocks screenshots from outside the session (`org.gnome.Shell.Screenshot` is not
allowed), only the portal works.

Confirmed on the hardware:
- The conversion + GNOME theme apply runs end to end. The NVIDIA gaming mode setup had failed on a working gamescope: the smoke test
  `timeout gamescope ... | grep -q` under `pipefail` (fixed, #84; check it stays fixed in the nvidia suite).
- The prebuilt GNOME Settings (release `settings` of steamify-gnome-theme, built by CI in an Arch container in ~3 min) downloads, passes its
  checksum and installs; the "GNOME Desktop" panel is there. Turning the theme off puts the stock `gnome-control-center` back.
- Restart GNOME (countdown at the end of a theme-only run, then `steamify-gdm-relogin <session>`): the relogin itself takes ~1 s; it first
  landed in gaming mode (the account's session after the conversion), now it logs into the session the app runs in and puts the account's
  session back afterwards (checked: Session=gamescope-session again). A run that also needs a reboot shows Restart now instead.
- App: desktop scale 1.0 (it was 2.0 on 3440x1440), a row click only selects, the switch itself toggles, the logo needs `qt6-svg` (pyside6
  doesn't pull it in), the dock icon needs a **PNG by name** in the user icon theme: an SVG, by path or by name, is blank in the dock on a
  fresh install (GNOME Shell: "Could not load a pixbuf from icon theme"; GTK: "Unrecognized image file format" for the same SVG).
- GNOME theme: dock at the bottom, desktop icons from the top right (Return to Gaming Mode, Steam, Steamify CachyOS), Desktop Icons NG and
  AppIndicator are installed by Steamify (they were not on the fresh install) and removed again when neither the conversion nor the theme is on.

Open, to build in the VM (rows GN8-GN13 in TESTPLAN F-GNOME):
1. **Roughed-up GNOME after several theme off/on cycles with relogins (NOT diagnosed).** After off/on/off cycles the user reported: no icons in the
   top bar and the overview search not working. What was checked and was fine: the shell ran with both extensions ACTIVE, no failed user units,
   all gsd units running, the user manager's environment complete (`XDG_CURRENT_DESKTOP=GNOME`, `WAYLAND_DISPLAY`), shell log with only benign
   messages (`CalendarServer` activation failed, parental controls, `XDG_SESSION_ID` unset, `gsd-power` backlight), icons (Adwaita symbolic,
   firefox) decode in a test session. Not yet looked at: the dash favorites and `gio list-apps`, the menu data, `~/.local/share/icons/hicolor`
   (Steamify writes a PNG there; the directory has an `icon-theme.cache` from `gtk-update-icon-cache -t` but no `index.theme`: a suspect),
   the icon theme caches, theme leftovers in gsettings (gtk-theme stayed `adw-gtk3-dark`), screenshots. Reproduce: apply theme, off, on, off, with a
   relogin after each, and take portal screenshots of the top bar and the search each time.
2. **Relogin**: a theme-only run ends in the countdown, Cancel keeps the button, the relogin lands in GNOME and AccountsService `Session` is back to
   what it was (stand-in gamescope session in the VM); without the helper (no conversion) it is a plain logout.
3. **Extension ownership**: `$STATE_DIR/gnomeextras.list` is written before the install and only for missing packages; both off removes exactly those
   and takes the two extensions out of `enabled-extensions`; theme off with the conversion on keeps them enabled; a package the user installed
   first stays. (Unit-tested with stubs only.)
4. **App on GNOME in a real session**: own window frame and buttons (minimize, maximize, close click-tested), Restart now, the scale at 100% and
   at a GNOME scale of 150%, TV mode unchanged (`--fullscreen`), one-click switch and select-only row, the logo (qt6-svg) and the dock icon
   after applying the **launcher** option (PNG by name in `hicolor/256x256/apps`, entry `io.github.theupriser.Steamify.desktop`).
5. **Settings package failure paths**: offline (stock Settings stays, a warning), wrong checksum, a pacman conflict; the weekly rebuild keeps
   matching Arch (the package links against current libraries).
6. **Desktop icons**: Steamify's three launchers placed from the top right in name order, the user's own files keep their positions, theme off
   puts `start-corner` back; Home and mounted drives still show.

Multi-OS Limine (real hardware only; the VM has one OS): on the user's PC (main CachyOS on nvme0n1p2, the GNOME test install on nvme0n1p3,
Windows on its own ESP) every reinstall of the GNOME test OS made the main CachyOS entry disappear from Limine (both installs share the ESP and the
generated `limine.conf` only knows its own machine id). Repaired by hand twice, same recipe: back up `limine.conf` and `/etc/default/limine`,
set `TARGET_OS_NAME` to the new install's name, `limine-update`, insert a `/+CachyOS` block pointing at the other install's
`boot():/<its machine id>/linux-cachyos{,-lts}/{vmlinuz,initramfs}` with its own root UUID and cmdline (no hashes), drop the stale block the
regenerate leaves, move the generated block before the Windows entry, `limine-snapper-sync`. Order wanted: CachyOS, CachyOS GNOME, Windows Boot
Manager. Open: Secure Boot (sbctl keys, signing, `limine enroll-config`) is NOT set up: the hand-written entry has no hashes and would not boot
with it on; the ESP was 84% full (three machine-id folders of ~1.2 GB; one is from a removed install and unused).

## Real hardware: the RTX 5080 PC with GNOME + CachyOS (checklist, written 2026-10-15)
The VM can't render gamescope, so these are still open. Also read `nvidia/` (the NVIDIA gamescope path doesn't exist in the VM: how it behaves under GDM is untested).
Setup: `steamify-cachyos` on `feature/gnome-prototype` and this repo checked out; run from the checkout (`bash steamify.sh`; the released app doesn't know GNOME: `python3 ui/steamify-ui` with `XDG_CURRENT_DESKTOP=GNOME`). Passwordless sudo, GDM autologin working, a second way in (ssh from another machine: the ssh session dies at every session switch, reconnect). Back up first: `/etc/gdm/custom.conf`, `/usr/lib/steamos/steam-set-session`, `/usr/bin/steamos-session-select` (turning the conversion off restores them: tested in the VM, suite GN3).

1. [ ] Menu: GNOME theme offered, Plasma theme and single user mode hidden (`bash steamify.sh`, read the ticks with `q`).
2. [ ] Apply: `bash steamify.sh --defaults --options gaming,launcher --boot gamescope`. No errors; check `/etc/gdm/custom.conf`, `/var/lib/AccountsService/users/$USER` (Session/XSession), our tools in place, hook, sudoers (as GN2).
3. [ ] Cold boot: GDM logs straight into gamescope; the picture, the controller, Steam in Big Picture. Note the time to the first frame.
4. [ ] Steam's own Switch to Desktop (power menu): lands on GNOME. Time the GDM restart (VM: ~10 s waiting for the user manager) and note what the screen shows meanwhile (black? login screen flash?).
5. [ ] Return to Gaming Mode (desktop icon and launcher entry): back in gamescope. Repeat 3 times; look for a login screen or a dead session.
6. [ ] `--boot desktop`, reboot: GNOME straight away; `--boot gamescope`, reboot: gamescope.
7. [ ] Failure case: break gamescope on purpose (rename its session file), reboot: where does GDM land (VM: the login screen)? Restore it.
8. [ ] GNOME theme (`--options gnometheme`): dock, wallpaper, dark style, extensions on the real GPU; turn off and check it is restored.
9. [ ] The app: dock icon after a clean login (open item 1), minimize/maximize in its own frame (open item 2), the update notifier tray icon.
10. [ ] Turn everything off: custom.conf and the two CachyOS tools back as they were, reboot into plain GNOME.
11. [ ] With NVIDIA: does the patched gamescope (`lib/gamescope-nvidia.sh`) come in with the conversion under GDM, and does the session start after a GDM restart (NVIDIA + GDM Wayland can differ from the VM)?
Record results in the Results log below as a dated line; add a row to TESTPLAN.md H-Real if it becomes a standing check.

## RESUME HERE (written 2026-10-14, end of the first session)
State: product branch `feature/gnome-prototype` in steamify-cachyos (pushed, not merged; main is the 2.12.0 release), the theme repo
`github.com/theupriser/steamify-gnome-theme` (main). Everything is committed; the VM image is NOT in git (it lived in ~/vms/gnome-vm on one laptop).

Rebuild the GNOME test VM on another machine (steamify-cachyos-dev tooling, see its vm-install skill; needs KVM, the Steamify ISO, ~30 min):
1. `CI=1 VM_DESKTOP=gnome VM_STEAMIFY=skip VM_BOOTLOADER=limine VM_DIR=~/vms/gnome-vm VM_SSH_KEY=<key> REPO=<steamify-cachyos checkout> scripts/vminstall.sh --iso <steamify iso>`
   (plain CachyOS + GNOME + GDM with autologin; the headless installer ignores "desktop":"gnome", so share/vminstall-post.sh installs cachyos-gnome-settings, gnome, gdm).
   Boot it with `run.sh` in that dir (add `--vulkan --amd` for venus; gamescope still can't render in the VM).
2. In the VM, mount the repo (`sudo mount -t 9p -o trans=virtio,version=9p2000.L repo /mnt`; lost at every reboot) and apply the whole set:
   `cd /mnt && bash steamify.sh --backend apply --reapply --boot desktop gaming glyphs silent launcher notify gnometheme`
   (`--backend apply <ids>` means EXACTLY that set: ids left out are turned off.)
3. GNOME Settings with the Desktop panel: copy `steamify-gnome-theme/settings/` into the VM and `makepkg -si` there (~15 min; replaces gnome-control-center).
4. Gamescope doesn't run in the VM, so to test session switching use a stand-in: `sudo cp -n /usr/share/wayland-sessions/gamescope-session.desktop{,.real}` and set its `Exec=/usr/bin/sleep infinity`. Switch from an ssh session with
   `systemd-run --user --pipe --quiet /usr/bin/steamos-session-select gamescope|desktop` (the ssh connection dies at every switch; reconnect after ~35 s).
5. Screenshots from inside the VM: `gdbus call --session --dest org.freedesktop.portal.Desktop --object-path /org/freedesktop/portal/desktop --method org.freedesktop.portal.Screenshot.Screenshot "" "{'interactive': <false>}"` (allow the permission prompt once; files land in ~/Pictures). Needs `XDG_RUNTIME_DIR=/run/user/1000 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus`. Simulated mouse input (ydotool) was unreliable: don't count on it.
6. The released Steamify app/shortcut doesn't know GNOME: run the branch's app with `python3 /mnt/ui/steamify-ui` (set `XDG_CURRENT_DESKTOP=GNOME` when starting it from ssh).

Open items, in order: (1) dock icon of the Steamify app after a clean login (id + full-path icon are in; unconfirmed after relogin), (2) click-test minimize/maximize in the app's own frame (close works), (3) the Settings panel: trim Ubuntu-specific strings, rebuild with the new icon, distribute the package as a release asset, (4) single user mode for GNOME (lock screen, keyring), (5) KDE+GNOME together: the "preferred desktop" menu row, (6) GNOME regression run in the VM; the KDE regression run is the user's (at home), (7) the app's light/dark: the Qt app is always dark, only its frame is ours.
Tips learned: `pkill -x` fails for names over 15 chars (use `pkill -f`); polling the VM over ssh during a relogin keeps the old user manager alive; never edit a launcher entry while the shell runs and judge the icon right away (relogin first).


Started 2026-10-14. Goal: Steamify's SteamOS conversion on a GNOME desktop
(GDM), detected automatically; KDE keeps working. First a prototype to see it
work, then something solid. Product branch: `feature/gnome-prototype` in
steamify-cachyos (from main = 2.12.0). Notes live here, never in the product repo.

## Why it needs work
CachyOS's `steam-set-session` only handles plasma-login-manager/SDDM (silent
no-op on GDM) and `steamos-session-select` ends the session with a KDE-only
`qdbus6 org.kde.Shutdown` call. GDM logs in by itself only when the daemon
starts, so a session switch needs a GDM restart. Prior art, unverified:
https://git.upriser.nl/theupriser/cachyos-gamescope-boot-gnome
(`setup-gamescope-boot-gnome.sh`: AccountsService `Session=`, replaced tools
plus pacman hook, relogin by restarting gdm).

## Prototype design (written, not yet run)
- `lib/desktop.sh`: `desktop_kind` (gnome|kde from XDG_CURRENT_DESKTOP, else GDM = gnome), `desktop_session_file`, `choose_login_manager` (gdm on GNOME).
- `lib/login-manager.sh`: gdm branch in gaming_status/enable/disable; `configure_gdm_autologin` (/etc/gdm/custom.conf), `gdm_fix_install` (our tools in /usr/local/share/steamify-gdm, copied over the real paths, pacman hook 95-steamify-gdm.hook, sudoers rule for `systemctl restart gdm.service`).
- `patches/steamify-gdm-{steam-set-session,session-select}.sh`, `patches/steamify-gdm.hook`: the GDM-aware tools. Session goes into `/var/lib/AccountsService/users/<user>` (`Session=` and `XSession=`: which one GDM honours is OPEN, check in the VM). select restarts GDM directly instead of the old repo's shutdown.target unit.
- Menu: `theme` and `single` hidden on GNOME (Plasma only). Packages: `kconfig` + `accountsservice` instead of `plasma-keyboard` on GNOME (kreadconfig6 is used by the undo journal). `KWIN_IM_SHOW_ALWAYS` only on KDE. Boot-into-desktop unit uses the detected session. Shortcut also goes to ~/.local/share/applications (GNOME shows no desktop icons).

## Test VM
`VM_DESKTOP=gnome` added to dev `scripts/vminstall.sh` + `share/vminstall-post.sh` (uncommitted):
`CI=1 VM_DESKTOP=gnome VM_STEAMIFY=skip VM_DIR=~/vms/gnome-vm VM_SSH_KEY=~/vms/steamify-vm/vmkey REPO=<steamify-cachyos> scripts/vminstall.sh --iso ~/vms/iso-dl/steamify-cachyos-2.12.0-dev-261014-x86_64.iso` (PATH with ~/vms/shim, `sg kvm -c`). Plain CachyOS GNOME, Steamify applied by hand afterwards.

## Steps
1. [x] GNOME VM installed (~/vms/gnome-vm; the headless installer ignores "desktop":"gnome", so vminstall-post.sh installs cachyos-gnome-settings + gnome + gdm).
2. [x] Run `steamify.sh --defaults --options gaming` in the VM (repo on 9p /mnt); fix what breaks (kconfig, packages, shellcheck).
3. [x] Check: custom.conf, AccountsService, hook, sudoers, our tools in place.
4. [x] (gamescope itself dies in the VM: Vulkan/DRM scanout errors, also without GNOME; GDM did start it) Reboot: GDM autologs into the gamescope session (loginctl session desktop/type; gamescope may not render in the VM, a running session is enough).
5. [~] (gamescope->GNOME and GNOME->gamescope verified with a stand-in gamescope session (Exec=sleep infinity in /usr/share/wayland-sessions/gamescope-session.desktop, original kept as .real); reboot persistence, `boot` option and the shortcut click not yet) `steamos-session-select desktop` -> GNOME session; Return to Gaming Mode shortcut -> gamescope again; reboot persistence; `boot` option.
6. [x] (suite gnome GN3, 2026-10-15) Turn off: everything restored (custom.conf backup, original tools).
7. [x] (2026-10-15, laptop: cli, menu, hw, installer, toggles, nvidia, 0 fail) KDE regression: existing suites still pass on the KDE VM.
8. [x] (with the gnome suite, 2026-10-15) Commit dev-repo changes (VM_DESKTOP) to main; product branch stays a prototype, no release without the user.

## Later (solid version)
- Tests: GNOME suite in the dev repo, TESTPLAN rows; ISO with a GNOME variant.
- GNOME theme based on the Vapor Plasma theme (user idea: colours, wallpaper, icons; shell/GTK parts new). Single user mode and the other KDE-only parts (powerdevil in steam-machine, first-login, update notifier) need GNOME versions or stay hidden.
- Decide: keep replacing CachyOS's two files, or get GDM support upstream into gamescope-session-cachyos.
- Real hardware: GDM restart behaviour, Steam's Switch to Desktop button.

## Findings so far (2026-10-14)
- GDM logs in by itself only when it starts. A switch = set the session in AccountsService, `loginctl terminate-user`, `systemctl restart gdm` (patches/steamify-gdm-relogin.sh, run through sudo from inside the session, as a transient unit because ending the user kills the caller). Without ending the user first, GNOME refuses: "A graphical session is already running!". Starting the new login at once fails (the session dies in 0.2 s), so the helper stops GDM first (no login screen), ends the user, waits for the user manager to go (about 10 s in the VM), then starts GDM. Shortcut click (gtk-launch) and `steamos-session-select desktop` verified both ways with the stand-in session. Open: the ~10 s (what keeps the user manager up? Steam?), and what the screen shows during it.
- Both `Session=` and `XSession=` are written to AccountsService; GDM picked the right session. (Which one is needed is untested: could drop one.)
- cachyos-gamescope-autologin.service resets the session to gamescope when a desktop session ends (Deck behaviour), so after GNOME the next login is gamescope again.
- A failed gamescope session (VM) lands on GDM's login screen; SDDM relogin loops instead. Real hardware untested.
- Menu: theme and single user mode hidden on GNOME.
- ssh into the VM dies at every switch (terminate-user): reconnect.

## Status 2026-10-14 (evening)
- Verified in the VM with screenshots (portal screenshot: permission granted once in the VM, `gdbus ... org.freedesktop.portal.Screenshot.Screenshot "" "{'interactive': <false>}"`, file in ~/Pictures): desktop icons (DING) show Home, Trash, Return to Gaming Mode, Steam; Steam tray icon shows in the top bar (AppIndicator); Steam starts and logs in. GNOME extras installed on GNOME: kconfig, accountsservice, gnome-shell-extension-desktop-icons-ng, gnome-shell-extension-appindicator, extension-manager.
- The relogin helper waits on /run/user/<uid>, not `loginctl show-user` (which lingers ~10 s).
- NOT done: the `launcher` option (Steamify shortcut/app in the launcher and Steamify Terminal): only `gaming` was applied in the VM, so no Steamify app is installed. On GNOME it still needs: Konsole -> GNOME terminal (Ptyxis/Console) for Steamify Terminal; it downloads the newest GitHub release (without GNOME support until released).
- Not done either: `silent` (Steam starts on the desktop), the other options (notify, glyphs, ...), boot option, turn-off, KDE regression.

## KDE and GNOME installed together (open, user asked 2026-10-14)
Gamescope is its own session and doesn't depend on either desktop. What does:
- `choose_login_manager` (lib/desktop.sh) uses the RUNNING desktop: from KDE it would switch a GDM system to plasma-login-manager/SDDM, from GNOME to GDM. With both installed it should keep the login manager that is active (`current_display_manager`), switching only when none of ours is.
- Which desktop "Switch to Desktop" / "Boot into the desktop" go to: now fixed when the conversion is applied (DESKTOP_SESSION in the GDM tools, plasma.desktop in CachyOS's own). Needs a "preferred desktop" state (menu choice), maybe the last used one.
- Both themes are offered (desktop_installed) and independent (kdeglobals vs gsettings), but ~/.config/gtk-4.0/gtk.css is shared: the GNOME theme's colors reach GTK4 apps under KDE too (consider only applying under GNOME, e.g. `@media`-less: write it from a GNOME-only login hook, or leave it to the user).
- Single user mode (SDDM + KDE) with GNOME also installed: untested.
- Test: install plasma-desktop on the GNOME VM (or GNOME on the KDE VM), run the conversion from each, switch both ways.

## Open: Steamify app icon in GNOME's dock (2026-10-14)
The running Steamify (Qt) window shows a blank grey icon in the dock. Facts: the window's app_id is `steamify-ui` (WAYLAND_DEBUG), GLib accepts `steamify-ui.desktop` (icon `steamify`, StartupWMClass `steamify-ui`), icon as SVG, as PNG and as absolute path all stay blank, StartupWMClass is in. A plain GTK test window with app id `steamify-ui`, and with a second launcher `probeapp.desktop` (also system-wide), gets GNOME's generic blue icon, also with the Ubuntu Dock extension off (stock dash): so GNOME Shell doesn't match these windows to their launchers here (system apps match). Not the icon file, not the dock. Ideas: launch through the desktop/DING click and gnome-shell's own launch (startup sequence) instead of systemd-run; check gnome-shell logs; try on real hardware; check Qt's app_id handling (xdg-toplevel-icon).
The tray icon is fine (single-color steamify-symbolic.svg), the notification too.

## Update (same day): dock icon and window frame
- Cause of the blank dock icon: GNOME Shell on Wayland matches a window to its launcher only by a reverse-DNS app id (`steamify-ui` never matched; a GTK probe with `io.github.theupriser.SteamifyProbe` did). Steamify's id is now `io.github.theupriser.Steamify` (app, launcher entry `io.github.theupriser.Steamify.desktop`, notifier); the old `steamify-ui.desktop` entries are removed when the shortcut is applied.
- The icon must be given as a full path (`Icon=/home/.../icons/hicolor/scalable/apps/steamify.svg`): a name from the user's icon folder, and a PNG path, stayed blank in the dock; the SVG path worked in one test. After the wizard rewrote the entry the dock stayed blank until a fresh login: NOT confirmed after a relogin yet.
- Qt's own frame on GNOME is light grey: on GNOME (Wayland, windowed) the app draws its own dark header with minimize/maximize/close, drag and resize edges. Close confirmed working by the user; minimize and maximize not click-tested.
