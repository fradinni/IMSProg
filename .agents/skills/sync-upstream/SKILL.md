---
name: sync-upstream
description: >-
  Sync this IMSProg custom fork with upstream bigbigmdm/IMSProg. Use when the
  user asks to update the fork, pull upstream changes, refresh the custom branch,
  merge upstream/main, check how far behind the fork is, or resolve conflicts
  after an upstream update. Covers fetching, updating the fork's main mirror,
  merging into custom, resolving the binary chip database safely, verifying and
  pushing.
---

# Sync the IMSProg fork with upstream

Announce at start: "I'm using the sync-upstream skill to update the fork."

## Constants

| Item | Value |
|---|---|
| Upstream remote | `upstream` → `https://github.com/bigbigmdm/IMSProg.git` |
| Fork remote | `origin` → `git@github.com:fradinni/IMSProg.git` |
| Custom branch | `custom` |
| Upstream mirror branch | `main` |
| Chip database | `IMSProg_programmer/database/IMSProg.Dat` |

## 1. Preflight

Work from the repository root. Stop if the tree is not clean unless the user
explicitly asks to continue.

```sh
git status --short
git branch --show-current
git remote -v
git fetch origin --prune
git fetch upstream --prune --tags
```

Show what would come in:

```sh
git log --oneline --decorate -10 upstream/main
git log --oneline HEAD..upstream/main
git diff --stat HEAD...upstream/main
```

If there are no incoming commits, report that the fork is up to date and stop.

## 2. Update the fork's main mirror

`main` is a fast-forward mirror of `upstream/main`.

```sh
git checkout main
git merge --ff-only upstream/main
git push origin main
git checkout custom
```

If `main` cannot fast-forward, stop and report the divergence. Do not rewrite
or force-push `main` without explicit permission.

## 3. Merge upstream into custom

Use a merge, not a rebase, by default. `custom` is published and has release
tags; rebasing would rewrite public history and detach the tags.

```sh
git merge --no-ff upstream/main -m "Merge upstream/main into custom"
```

Only rebase when the user explicitly asks for a linear history and confirms
that force-pushing `custom` is acceptable.

## 4. Resolve conflicts

Common conflicts and the correct resolution:

### `IMSProg_programmer/database/IMSProg.Dat`

This is a binary fixed-size record database. **Never** hand-edit conflict
markers or merge it with a text merge.

1. Take the upstream version as the new base:
   ```sh
   git checkout --theirs -- IMSProg_programmer/database/IMSProg.Dat
   ```
   In a merge into `custom`, `--theirs` is the upstream branch.
2. Re-add the fork's custom chip records with the `add-chip` skill, unless
   upstream already added them:
   ```sh
   python3 .agents/skills/add-chip/scripts/chipdb.py find 204419
   ```
   The known custom entry is `XM25RU256C(1.8V)` / `204419`.
3. Validate:
   ```sh
   python3 .agents/skills/add-chip/scripts/chipdb.py check
   ```

### `README.md`

Keep the fork info header at the very top, keep upstream's body, and preserve
the fork's chip-list additions. Check the header:

```sh
head -15 README.md
```

### `IMSProg_programmer/other/index.html`

Merge both chip lists; keep upstream additions and the fork's custom chips.
Keep the XMC list consistent with `README.md`.

### Build files

Accept upstream changes to CMake and application code. Keep the fork's
AppImage/Docker files (`build_appimage.sh`, `appimage/`, `docker/`,
`.dockerignore`) unless the user asks to drop them.

After resolving:

```sh
git add -A
git commit --no-edit
```

If the merge becomes unrecoverable and nothing has been pushed yet:

```sh
git merge --abort
```

## 5. Verify the merge

```sh
git log --oneline upstream/main..HEAD
git diff --stat upstream/main..HEAD
python3 .agents/skills/add-chip/scripts/chipdb.py check
python3 .agents/skills/add-chip/scripts/chipdb.py find 204419
```

The diff should contain only the fork's intentional additions: the AppImage
build, the README header, the custom chip database entry and the documented
chip lists.

Optionally build to prove the merged tree still compiles:

```sh
CONTAINER_ENGINE=podman ./build_appimage.sh --no-build \
  "$(awk '/^Version:/ {print $2; exit}' rpm/imsprog.spec)-sync-check"
```

The artifact lands in `dist/`, which is ignored by git. If Podman is not
available, the script auto-detects Docker; omit `CONTAINER_ENGINE` and use
`--no-build` only when the builder image already exists.

## 6. Push

Push only after verification and only when the user asked for a sync:

```sh
git push origin custom
```

Never push to `upstream`.

## Report

Summarise:

- upstream commits merged (count and notable fixes/features),
- conflicts resolved, especially how the database was rebuilt,
- custom commits still present,
- verification/build result,
- what was pushed.
