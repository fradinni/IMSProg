---
name: release-custom
description: >-
  Build and publish a custom IMSProg release for the fradinni/IMSProg fork. Use
  when the user asks to build the AppImage, cut a custom release, publish a new
  GitHub release, upload an AppImage, or bump the custom release number. Covers
  versioning as <official>-custom.<N>, building with Docker/Podman, verifying
  the artifact, writing release notes and creating the GitHub release with the
  AppImage and checksum attached.
---

# Build and publish a custom IMSProg release

Announce at start: "I'm using the release-custom skill to build and publish the
release."

## Constants

| Item | Value |
|---|---|
| Fork repository | `fradinni/IMSProg` |
| Release branch / target | `custom` |
| Official version source | `rpm/imsprog.spec` (`Version:` line) |
| Tag / release format | `<official>-custom.<N>` |
| Build entry point | `./build_appimage.sh` |
| Artifact directory | `dist/` (git-ignored) |

Examples: `1.9.1-custom.1`, `1.9.1-custom.2`; after upstream bumps to `1.9.2`,
the next custom release is `1.9.2-custom.1`.

## 1. Preflight

```sh
git status --short
git branch --show-current
git fetch origin --prune
gh auth status
```

Requirements:

- the working tree is clean,
- the current branch is `custom`,
- `HEAD` matches `origin/custom` (or the user explicitly asks to push first),
- `gh` is authenticated for `github.com`,
- `podman info` or `docker info` succeeds.

If the tree is dirty, commits are unpushed, or `gh` is not authenticated, stop
and report what is missing. Do not publish a release from an unpushed commit.

Check that the version is consistent:

```sh
VERSION=$(awk '/^Version:/ {print $2; exit}' rpm/imsprog.spec)
echo "$VERSION"
grep -n "V$VERSION" IMSProg_programmer/dialogabout.cpp
```

The about dialog and the metainfo file should agree with the spec. If they do
not, report it; only bump the official version when the user asks.

## 2. Determine the custom release number

```sh
VERSION=$(awk '/^Version:/ {print $2; exit}' rpm/imsprog.spec)
LAST=$(gh release list -R fradinni/IMSProg --limit 100 --json tagName \
  --jq '.[].tagName' \
  | sed -n "s/^${VERSION}-custom\\.\\([0-9]\\+\\)$/\\1/p" \
  | sort -n | tail -1)
N=$(( ${LAST:-0} + 1 ))
TAG="${VERSION}-custom.${N}"
echo "$TAG"
```

This resets to `custom.1` automatically when the official version changes.

## 3. Build the AppImage

Use Podman explicitly when Docker's daemon is not running. `--no-build` reuses
the existing builder image; omit it when the image is missing.

```sh
CONTAINER_ENGINE=podman ./build_appimage.sh --no-build "$TAG"
```

Without Podman, let the script auto-detect Docker:

```sh
./build_appimage.sh --no-build "$TAG"
```

The version argument controls the embedded AppImage version and the file name.
Artifacts written to `dist/`:

- `IMSProg-${TAG}-x86_64.AppImage`
- `IMSProg-${TAG}-x86_64.AppImage.sha256`
- `imsprog`, `install-desktop-integration.sh`, `README-AppImage.md`

Builds can take several minutes. Do not edit files while the build is running.

## 4. Verify the artifact

```sh
cd dist
sha256sum -c "IMSProg-${TAG}-x86_64.AppImage.sha256"
cd ..
```

Check the embedded app version and the chip database:

```sh
CHECK_DIR=$(mktemp -d -p /tmp/opencode)
cd "$CHECK_DIR"
"/home/nicolas/Projects/Electronic/IMSProg/dist/IMSProg-${TAG}-x86_64.AppImage" \
  --appimage-extract >/dev/null
grep -n 'X-AppImage-Version' squashfs-root/imsprog.desktop
grep -a XM25RU256C squashfs-root/usr/share/imsprog/IMSProg.Dat
cd /
rm -rf "$CHECK_DIR"
```

`X-AppImage-Version` must equal `$TAG`. The database check should match the
chips added by this fork; if a different custom chip is the subject of this
release, grep for that chip instead. Optionally verify the launcher help:

```sh
APPIMAGE_EXTRACT_AND_RUN=1 \
  "./dist/IMSProg-${TAG}-x86_64.AppImage" --help
```

## 5. Write release notes

Create the notes outside the repository, for example in `/tmp/opencode`, so
they do not end up in a commit. Include:

- the upstream IMSProg version and custom release number,
- what changed since the previous custom release,
- the AppImage and checksum asset names,
- a short usage snippet.

You can generate the change list from the previous custom tag when it exists:

```sh
PREVIOUS=$(gh release list -R fradinni/IMSProg --limit 100 --json tagName \
  --jq '.[].tagName' | grep -- '-custom\.' | sort -V | tail -2 | head -1)
git log --oneline "${PREVIOUS}..HEAD" 2>/dev/null || true
```

Keep the notes factual and focused on the fork's additions.

## 6. Publish

```sh
gh release create "$TAG" \
  --repo fradinni/IMSProg \
  --target custom \
  --title "IMSProg $TAG" \
  --notes-file "/tmp/opencode/imsprog-release-${TAG}.md" \
  "dist/IMSProg-${TAG}-x86_64.AppImage" \
  "dist/IMSProg-${TAG}-x86_64.AppImage.sha256"
```

Use `--draft` or `--prerelease` only when the user asks for it. The default is
a public release. Never attach an artifact from a different version.

## 7. Verify the release

```sh
gh release view "$TAG" --repo fradinni/IMSProg \
  --json tagName,name,isDraft,isPrerelease,targetCommitish,url,assets
git ls-remote --tags origin "$TAG"
```

Confirm:

- the release is public unless requested otherwise,
- both assets are present and in the `uploaded` state,
- the tag points at the expected `custom` commit,
- the asset size matches the built AppImage.

## 8. Finish

- Do not commit `dist/`; it is build output and already ignored.
- Report the release URL, tag, commit, asset names and checksum.
- The next release for the same official version is `custom.N+1`; after an
  upstream version bump it starts again at `custom.1`.
