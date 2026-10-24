# IMSProg AppImage

A self-contained Linux build of the whole IMSProg suite: the chip programmer,
the chip database editor and the chip database updater. Nothing needs to be
installed on the target machine - the AppImage bundles Qt5, libusb and libftdi.

## Contents of the bundle

| File | Purpose |
| --- | --- |
| `IMSProg-<version>-x86_64.AppImage` | the application |
| `imsprog` | launcher that finds the AppImage and handles the details |
| `install-desktop-integration.sh` | menu entries, icons and udev rules |
| `IMSProg-<version>-x86_64.AppImage.sha256` | checksum |

## Running

```sh
./imsprog                # chip programmer (IMSProg)
./imsprog editor         # chip database editor (IMSProg_editor)
./imsprog updater        # chip database updater (IMSProg_database_update)
```

The AppImage can also be started directly:

```sh
./IMSProg-1.9.1-x86_64.AppImage              # programmer
./IMSProg-1.9.1-x86_64.AppImage --editor     # editor
./IMSProg-1.9.1-x86_64.AppImage --updater    # updater
./IMSProg-1.9.1-x86_64.AppImage --help
```

If the file is not executable (`chmod +x`), the `imsprog` launcher fixes that
for you. On systems without FUSE (or inside containers) it automatically falls
back to the slower extract-and-run mode.

### USB access (udev rules)

The CH341A/CH347T/FT232H programmers need udev rules so that a normal user can
access them:

```sh
./imsprog --install-udev-rules     # or: sudo ./imsprog --install-udev-rules
```

Then re-plug the programmer. The rules are also installed by
`install-desktop-integration.sh`.

### Desktop integration

```sh
./install-desktop-integration.sh                  # current user
sudo ./install-desktop-integration.sh --system    # all users
```

This copies the AppImage to a stable location (`~/.local/bin` or `/opt/imsprog`),
installs the udev rules, adds icons and three menu entries (programmer, editor,
updater) and links `imsprog` into your `PATH`.

## Building the AppImage

The build runs in a container so that the resulting binary is linked against a
reasonably old glibc (Ubuntu 22.04 / glibc 2.35) and therefore runs on Ubuntu
22.04+, Debian 12+, Fedora 36+ and their derivatives.

Requirements on the build host: Docker or Podman and network access (to build
the image once and download the AppImage tooling).

```sh
./build_appimage.sh                 # build, artifacts end up in ./dist
./build_appimage.sh 1.9.2           # override the version string
CONTAINER_ENGINE=podman ./build_appimage.sh
```

Useful environment variables:

| Variable | Effect |
| --- | --- |
| `IMAGE` | builder image name (default `imsprog-appimage-builder:latest`) |
| `VERSION` | version embedded in the file name |
| `JOBS` | number of parallel compile jobs |
| `DIST_DIR` | output directory (default `./dist`) |
| `CONTAINER_ENGINE` | `docker` or `podman` |
| `QMAKE` | qmake to use inside the container (Qt5 by default) |

The build is reproducible and works offline once the builder image exists:
`docker/Dockerfile` pre-downloads linuxdeploy, appimagetool and the AppImage
runtime, and `./build_appimage.sh --no-build` skips rebuilding the image.

### How it works

1. `docker/Dockerfile` - Ubuntu 22.04 with the Qt5/libusb/libftdi development
   packages and the AppImage tooling.
2. `docker/container-build.sh` - configures CMake (`FORCE_QT5=ON`), compiles,
   installs everything into an AppDir, bundles the Qt/libftdi/libusb libraries
   with `linuxdeploy`, then packs the AppDir with `appimagetool`.
3. `appimage/AppRun` - the AppImage entry point; selects the programmer, editor
   or updater, sets up the bundled Qt paths and installs the udev rules.
4. `build_appimage.sh` - host script that builds the image and runs the build
   with the source tree mounted read-only.

The applications find their data through `<binary>/../share/imsprog`, so the
chip database (`IMSProg.Dat`) and the translations are picked up from inside the
AppImage without patching. The user database and the configuration file still
live in `~/.local/share/imsprog`.

## Troubleshooting

**`dlopen(): error loading libfuse.so.2`** - install FUSE 2
(`sudo apt install libfuse2`, `sudo dnf install fuse-libs`) or use the `imsprog`
launcher, which falls back to the extraction mode.

**`Cannot mount AppImage`** - same cause; `APPIMAGE_EXTRACT_AND_RUN=1` can be
exported manually.

**The programmer does not see the chip** - the udev rules are missing:
`./imsprog --install-udev-rules`, then re-plug the device and check with
`lsusb`.

**Old distribution** - the AppImage requires glibc 2.35 or newer (Ubuntu 22.04,
Debian 12, Fedora 36 and newer). On older systems build from source instead, or
run `./build_appimage.sh` from an even older base image.

**No native Wayland support** - the Qt5 Wayland plugin is bundled, but the
AppImage falls back to XWayland when no Wayland compositor is available.
