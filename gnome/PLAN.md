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
1. [ ] GNOME VM installed (install running, log ~/vms/gnome-install.out); snapshots clean/ssh-ready.
2. [ ] Run `steamify.sh --defaults --options gaming` in the VM (repo on 9p /mnt); fix what breaks (kconfig, packages, shellcheck).
3. [ ] Check: custom.conf, AccountsService, hook, sudoers, our tools in place.
4. [ ] Reboot: GDM autologs into the gamescope session (loginctl session desktop/type; gamescope may not render in the VM, a running session is enough).
5. [ ] `steamos-session-select desktop` -> GNOME session; Return to Gaming Mode shortcut -> gamescope again; reboot persistence; `boot` option.
6. [ ] Turn off: everything restored (custom.conf backup, original tools).
7. [ ] KDE regression: existing suites still pass on the KDE VM.
8. [ ] Commit dev-repo changes (VM_DESKTOP) to main; product branch stays a prototype, no release without the user.

## Later (solid version)
- Tests: GNOME suite in the dev repo, TESTPLAN rows; ISO with a GNOME variant.
- GNOME theme based on the Vapor Plasma theme (user idea: colours, wallpaper, icons; shell/GTK parts new). Single user mode and the other KDE-only parts (powerdevil in steam-machine, first-login, update notifier) need GNOME versions or stay hidden.
- Decide: keep replacing CachyOS's two files, or get GDM support upstream into gamescope-session-cachyos.
- Real hardware: GDM restart behaviour, Steam's Switch to Desktop button.
