# Steamify on GNOME (GDM): prototype plan

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
6. [ ] Turn off: everything restored (custom.conf backup, original tools).
7. [ ] KDE regression: existing suites still pass on the KDE VM.
8. [ ] Commit dev-repo changes (VM_DESKTOP) to main; product branch stays a prototype, no release without the user.

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
