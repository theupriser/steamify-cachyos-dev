---
name: steamify-branch-cleanup
description: Clean up git branches in steamify-cachyos (and sibling steamify repos) following the release-branch flow. Use when the user asks to clean up / prune branches.
---

# Steamify branch cleanup

Rules:
- ALWAYS keep `main` and every `release/X.Y.Z` branch (local and remote). Never delete them.
- Delete `feature/*` and `bugfix/*` branches (local and remote) only when merged into `origin/main` or the current `origin/release/*` branch.
- Delete local branches whose remote is gone (`[origin/...: gone]`) only if they are `feature/*` or `bugfix/*`; local stale `release/*` branches are kept unless the user says otherwise.
- Never touch unmerged branches; list them and report instead.
- Never commit or merge to main.

Steps:
1. `git fetch --all --tags --prune`
2. `git checkout main && git merge --ff-only origin/main`
3. List candidates: `git branch -vv`, `git branch -r --merged origin/main`, and same for the current release branch.
4. Delete local (`git branch -d`) and remote (`git push origin --delete <b>`) feature/bugfix branches per the rules above.
5. Report what was deleted and what was kept.

Note: remote deletions may be blocked by the auto-mode classifier; if so, stop and let the user approve a permission rule or run it via `!`.
