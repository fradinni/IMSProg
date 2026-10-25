# IMSProg custom fork — agent skills

Project-local skills for maintaining this fork of
[bigbigmdm/IMSProg](https://github.com/bigbigmdm/IMSProg).

| Skill | Use when |
|---|---|
| [`sync-upstream`](skills/sync-upstream/SKILL.md) | Pull upstream changes into the fork, update the `main` mirror and merge them into `custom`. |
| [`add-chip`](skills/add-chip/SKILL.md) | Add or update a chip in `IMSProg_programmer/database/IMSProg.Dat`, port a flashrom entry, or fix a JEDEC/size/4-byte/security field. |
| [`release-custom`](skills/release-custom/SKILL.md) | Build the AppImage and publish a `X.Y.Z-custom.N` GitHub release with the artifact attached. |

## Fork facts

- **Upstream:** `https://github.com/bigbigmdm/IMSProg.git` (remote `upstream`)
- **Fork:** `git@github.com:fradinni/IMSProg.git` (remote `origin`)
- **Working branch:** `custom`
- **Upstream mirror branch:** `main`
- **Official version source:** `rpm/imsprog.spec` (`Version:` line)
- **Custom release format:** `<official-version>-custom.<N>`, for example `1.9.1-custom.1`
- **Chip database:** `IMSProg_programmer/database/IMSProg.Dat`
- **AppImage build:** `build_appimage.sh` (Docker or Podman)
- **Documented chip lists:** `README.md` and `IMSProg_programmer/other/index.html`

## Typical order

1. `sync-upstream` — stay current with upstream.
2. `add-chip` — add the custom database entry and docs.
3. `release-custom` — build, verify and publish.

## Safety rules

- Never push to `upstream`; it is read-only for this fork.
- Do not hand-merge the binary `IMSProg.Dat` during a conflict; take the
  upstream file and re-add custom records with the `add-chip` skill.
- `dist/` is build output and is git-ignored. Keep it out of commits.
- Ask before committing or pushing unless the user explicitly requested it.
