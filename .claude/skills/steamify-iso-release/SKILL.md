---
name: steamify-iso-release
description: Use when releasing, debugging or changing how the Steamify ISO is built and published - the GitHub tag that names it, the Gitea mirror (git.upriser.nl) that builds and attaches the 3.2 GB ISO, the Steamify workflows that start it, and every trap met while setting it up (413, privileged runner, sudo dropping variables, mirror syncs deleting tags, upload-artifact@v3, GitHub 429). Also for the Gitea side of steamify-cachyos' own releases.
---

# Steamify ISO release pipeline (set up 2026-09-29, first ISO out the same night)

Tested end to end: release `v2.9.3-dev.2026.09.29-2044` -> `steamify-cachyos-2.9.3-dev.2026.09.29-2044-x86_64.iso`
on git.upriser.nl, GitHub's link to it answers 200.

## The flow (one tag names everything)

1. **GitHub, `iso-1-github-tag.yml`** (ISO repo `theupriser/steamify-cachyos-live-iso`, `workflow_dispatch` only):
   takes Steamify's newest release (`X.Y.Z`), the time **now in UTC** and makes an **annotated tag**
   `vX.Y.Z-[dev.]YYYY.MM.DD-HHMM` plus a GitHub release with the changelog notes and the *direct* download link
   on Gitea. `dev.` and a pre-release on `feat/steamify` (test build), none on `master` (a release).
   GitHub is the only place that reads a clock.
2. **The mirror syncs** (git.upriser.nl is a pull mirror of GitHub, every 10 minutes): the tag arrives.
3. **Gitea, `iso-2-gitea-build.yml`** (`on: push: tags: ['v*']`, skipped on GitHub by `github.server_url`): parses the
   tag, builds the ISO on the runner with exactly that Steamify (`STEAMIFY_VERSION`), the tag's time (label) and
   the tag without its `v` (`STEAMIFY_ISO_VERSION`: file name, boot menu, `/etc/steammachine-iso-build`), then
   attaches ISO + `.sha256` + `.sha1` + `.pkgs.txt` to the mirror's release for that tag
   (`akkuman/gitea-release-action`, the run's own token). Never overwrites a release that already has its ISO.
4. **Trigger:** by hand (*Actions -> ISO 1/2 · Tag and release (GitHub) -> Run workflow*, or
   `gh workflow run iso-1-github-tag.yml -R theupriser/steamify-cachyos-live-iso --ref feat/steamify`), or by a
   new Steamify release: `steamify-cachyos`' `bundle.yml` step "Start the Steamify ISO's release" (secret
   `ISO_DISPATCH_TOKEN` there: fine-grained token, only the ISO repo, *Actions: read and write*; without it the
   step is skipped). A push does **not** release (a build is 20 minutes and 3.2 GB).
5. Names, for tag `v2.9.3-dev.2026.09.29-2044`: file `steamify-cachyos-2.9.3-dev.2026.09.29-2044-x86_64.iso`,
   label `STEAMIFY_2_9_3_20260929_2044` (ISO 9660: 32 chars, `A-Z 0-9 _`). By hand, without a tag: `local`
   (`steamify-cachyos-local-x86_64.iso`, `STEAMIFY_<version>_LOCAL`). The build reads no clock.

Total from a Steamify release to the ISO on Gitea: about 30 minutes (release, tag, sync <=10 min, build 15-20).

## Why it is split like this (learned the hard way)

- **A release made only on the mirror disappears** at the next sync: the pull mirror removes tags GitHub doesn't
  have, and the release goes with it (one that has files may linger, tagless, and sorts oddly: delete it). A
  release on a tag that **comes from GitHub survives** every sync, files included (tested with a 0-byte asset).
  Hence: GitHub makes the tag, Gitea only attaches the file. You can't delete a tag on a mirror by hand either.
- GitHub releases take **2 GB per file**; the ISO is 3.2 GB. So GitHub gets notes and a link, Gitea the file.
- **Annotated tags**: a lightweight tag has only its commit's date, so tags on the same commit sort randomly
  on Gitea. UTC is fine (the release name says "UTC"; it is 2 h behind Dutch summer time, and nobody cared).
- The GitHub release's link is built from the tag alone (`.../releases/download/<tag>/steamify-cachyos-<tag
  without v>-x86_64.iso`), so the Gitea file name must be that: check it with `curl -I -L` (the monitor in the
  session did: HTTP 200 = the whole chain is right).

## Gitea side: what the runner and the server need

- **Runner** (act_runner in Docker Compose, network `gitea_gitea`): `config.yaml` -> `container: privileged: true`
  (the workflow's `options: --privileged` is **ignored** otherwise; symptom: `mount: .../airootfs/proc: permission
  denied`, `failed to setup chroot`; the job log shows `Privileged:false`). ~20 GB free disk.
- **Upload limit: `[repository.release] FILE_MAX_SIZE = 10240`** in `app.ini` (MB; default 2048), restart Gitea.
  `[attachment] MAX_SIZE` is for issues, **not** releases: symptom `status: 413` on `.../releases/<id>/assets`.
  The release is created *before* the upload, so a failed run leaves an empty release: delete it.
- Logs of a public repo's run are readable without login: `.../actions/runs/<run>/jobs/<job>/logs` (job numbers
  count up; re-runs get a new job number). Good for a monitor; no `gh` for Gitea.
- Mirror sync is set to 10 min by the user with their own token; "Synchronize Now" or the API
  (`POST /api/v1/repos/<repo>/mirror-sync`) for now. `GIT_UPRISER_TOKEN` (secret in the ISO repo) would make GitHub
  trigger it; not needed.
- **Build traps in the container:** `sudo mkarchiso` in `util-iso.sh` **drops environment variables**:
  it needs `sudo --preserve-env=STEAMIFY_ISO_VERSION,STEAMIFY_BUILD_STAMP` (the first Gitea ISO came out as
  `-local-`). Step names are evaluated **before** earlier steps set env: don't put `${{ env.X }}` in a name.
  Lots of `error: command failed to execute correctly` (pacman hooks wanting systemd) are harmless.
  The bash test of the naming must go through `sudo` too, not only call `profiledef.sh` directly.
- Kernel: the ISO is built from the generic `x86_64` repo (must boot on any PC), which lags the `v3/v4/znver4`
  repos by a day or so: 7.2.7 on the ISO while installed systems get 7.2.8. Normal, not a bug: the installer
  switches to the CPU's optimised repo (znver4 on the 9800X3D) and the first update brings the newer kernel.

## Steamify's own workflow (`steamify-cachyos/.github/workflows/bundle.yml`), one file for both servers

- Build + check run everywhere. shellcheck through `ludeeus/action-shellcheck@2.0.0` (brings its own binary:
  act_runner's image has none; GitHub's has). The artifact: `actions/upload-artifact@v4` on GitHub,
  `christopherhx/gitea-upload-artifact@v4` elsewhere. **Never write `upload-artifact@v3`**: GitHub fails the
  whole workflow for merely mentioning a deprecated version, even in a skipped step.
- Publishing: GitHub release (`gh`, tag + `latest`) only on GitHub; on Gitea the release is `akkuman/gitea-release-action`
  with a Gitea-API version check (`RELEASE_TOKEN` secret optional, else the run's token). Steps are guarded by
  `github.server_url == 'https://github.com'` (or `!=`). YAML check without PyYAML on the Mac:
  `ruby -ryaml -e 'YAML.load_file(...)'`.
- Steamify releases still follow the AGENTS.md flow (`release/X.Y.Z`, `bugfix/`/`feature/` branch, PR into the
  release branch, merged and **deleted** by the agent, the release PR into `main` is the user's). Even a CI-only
  change is a release (2.9.2, 2.9.3).

## GitHub rate limit that started this (HTTP 429)

`raw.githubusercontent.com` refused Valve's CEC driver source after a day of test installs (each CEC turn-on
downloaded it again; the limit is per address, ~1 per 5 minutes seen). Fixed in Steamify 2.9.1: the driver is
cached in `/var/cache/steamify/cros-ec-cec-<sha256:12>.c` (named after its checksum: a new pin downloads once and
deletes the old file; a damaged file is fetched again). The test VMs share the host's `~/vms/pkg-cache/steamify`
(bound over `/var/cache/steamify` by `vmsuite.sh`, `vmbootloadertest.sh`, `vminstall-live.sh`); hw block 50 tests
the cache offline (`file://`). The source repo `evlaV/linux-integration` is an unofficial mirror without releases:
if it ever vanishes, ship the file with Steamify.

## Checklist for a release

1. Steamify released? (`gh release list -R theupriser/steamify-cachyos`). The ISO gets the newest.
2. `gh workflow run iso-1-github-tag.yml ... --ref feat/steamify` (test) or `--ref master` (release; master must have
   the workflows: it doesn't yet, `feat/steamify` is the ISO repo's working branch).
3. Watch: tag on Gitea (`.../api/v1/repos/theupriser/steamify-cachyos-live-iso/tags`), the run's log (above),
   then `curl -I -L` the GitHub link. Old test releases: delete on GitHub (`gh release delete <tag>
   --cleanup-tag -y`); the sync removes the tag on Gitea; delete a leftover tagless Gitea release by hand.
