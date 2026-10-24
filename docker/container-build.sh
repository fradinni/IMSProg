#!/usr/bin/env bash
#
# Build IMSProg from source and package it as a Linux AppImage.
# This script runs *inside* the build container (see docker/Dockerfile) and is
# normally invoked through ./build_appimage.sh on the host.
#
# Inputs (environment variables):
#   SRC_DIR  source tree            (default: /src)
#   OUT_DIR  artifact directory     (default: /out)
#   VERSION  version string         (default: from rpm/imsprog.spec)
#   JOBS     parallel build jobs    (default: number of CPUs)
#   ARCH     AppImage architecture  (default: x86_64)
#
set -euo pipefail

SRC_DIR=${SRC_DIR:-/src}
OUT_DIR=${OUT_DIR:-/out}
JOBS=${JOBS:-$(nproc)}
ARCH=${ARCH:-x86_64}

log() { printf '\n==> %s\n' "$*" >&2; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

[[ -f "${SRC_DIR}/CMakeLists.txt" ]] || die "IMSProg sources not found in ${SRC_DIR}"
mkdir -p "${OUT_DIR}"
OUT_DIR=$(cd "${OUT_DIR}" && pwd)

if [[ -z "${VERSION:-}" ]]; then
    VERSION=$(awk '/^Version:/ {print $2; exit}' "${SRC_DIR}/rpm/imsprog.spec" 2>/dev/null || true)
fi
VERSION=${VERSION:-0.0.0}

WORK_DIR=$(mktemp -d)
trap 'rm -rf "${WORK_DIR}"' EXIT
BUILD_DIR="${WORK_DIR}/build"
APPDIR="${WORK_DIR}/AppDir"
mkdir -p "${APPDIR}"

# ---------------------------------------------------------------------------
# Compile (Qt5 - the most portable flavour for an AppImage)
# ---------------------------------------------------------------------------
log "Building IMSProg ${VERSION} (${JOBS} jobs, Qt5)"
cmake -S "${SRC_DIR}" -B "${BUILD_DIR}" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX=/usr \
    -DFORCE_QT5=ON
cmake --build "${BUILD_DIR}" --parallel "${JOBS}"

# ---------------------------------------------------------------------------
# Install into the AppDir
# ---------------------------------------------------------------------------
log "Installing into AppDir"
DESTDIR="${APPDIR}" cmake --install "${BUILD_DIR}"

# Udev rules must not live inside the AppImage's libdir - AppRun installs them
# into /etc/udev/rules.d on demand (--install-udev-rules).
install -Dm644 "${SRC_DIR}/IMSProg_programmer/other/71-CH341.rules" \
    "${APPDIR}/usr/share/imsprog/udev/71-CH341.rules"
rm -rf "${APPDIR}/usr/lib/udev" "${APPDIR}/lib/udev"

# ---------------------------------------------------------------------------
# AppImage metadata
# ---------------------------------------------------------------------------
# The binary looks for its data in "../share/imsprog" relative to itself, which
# is usr/share/imsprog inside the AppDir - no patching required.

# Desktop entry: rewrite the installed one so the translations are kept, but
# point Exec/Icon at the AppImage-relative names appimagetool expects.
sed -e 's#^Exec=/usr/bin/#Exec=#' \
    -e 's#^Icon=/usr/share/pixmaps/IMSProg64.png#Icon=imsprog#' \
    -e '/^Path=/d' \
    -e "s#^Name=IMSProg\$#Name=IMSProg\nX-AppImage-Version=${VERSION}#" \
    "${APPDIR}/usr/share/applications/IMSProg.desktop" > "${APPDIR}/imsprog.desktop"
install -m644 "${SRC_DIR}/IMSProg_programmer/img/IMSProg64.png" "${APPDIR}/imsprog.png"

# ---------------------------------------------------------------------------
# Bundle Qt, libusb, libftdi and friends
# ---------------------------------------------------------------------------
log "Deploying Qt and library dependencies"
export QMAKE="${QMAKE:-/usr/bin/qmake}"
# linuxdeploy-plugin-qt only bundles the xcb platform plugin by default; ship the
# Wayland plugins too so that the suite runs natively on Wayland sessions.
export EXTRA_PLATFORM_PLUGINS="${EXTRA_PLATFORM_PLUGINS:-libqwayland-egl.so;libqwayland-generic.so}"
linuxdeploy \
    --appdir "${APPDIR}" \
    --plugin qt \
    --executable "${APPDIR}/usr/bin/IMSProg" \
    --executable "${APPDIR}/usr/bin/IMSProg_editor" \
    --executable "${APPDIR}/usr/bin/IMSProg_database_update" \
    --desktop-file "${APPDIR}/imsprog.desktop" \
    --icon-file "${APPDIR}/imsprog.png"

# linuxdeploy-plugin-qt bundles the Wayland platform plugins but not their EGL
# buffer integration. Without it Qt falls back to slow shared-memory rendering
# on Wayland (and prints a warning), so deploy it manually.
QT_PLUGINS_DIR=$(qmake -query QT_INSTALL_PLUGINS)
WAYLAND_EGL_PLUGIN="${QT_PLUGINS_DIR}/wayland-graphics-integration-client/libqt-plugin-wayland-egl.so"
if [[ -f "${WAYLAND_EGL_PLUGIN}" ]]; then
    install -Dm755 "${WAYLAND_EGL_PLUGIN}" \
        "${APPDIR}/usr/plugins/wayland-graphics-integration-client/libqt-plugin-wayland-egl.so"
    patchelf --set-rpath '$ORIGIN/../../lib:$ORIGIN' \
        "${APPDIR}/usr/plugins/wayland-graphics-integration-client/libqt-plugin-wayland-egl.so"
fi

# linuxdeploy generates its own AppRun; we want one that can also start the
# editor/updater and install the udev rules. `rm` first: linuxdeploy might have
# left a symlink there.
rm -f "${APPDIR}/AppRun" "${APPDIR}/AppRun.wrapped"
rm -rf "${APPDIR}/apprun-hooks"
sed "s/@VERSION@/${VERSION}/g" "${SRC_DIR}/appimage/AppRun" > "${APPDIR}/AppRun"
chmod 755 "${APPDIR}/AppRun"

# ---------------------------------------------------------------------------
# Produce the AppImage
# ---------------------------------------------------------------------------
APPIMAGE_NAME="IMSProg-${VERSION}-${ARCH}.AppImage"
log "Creating ${APPIMAGE_NAME}"
rm -f "${OUT_DIR}/${APPIMAGE_NAME}"
appimagetool_args=(--no-appstream)
if [[ -n "${APPIMAGE_RUNTIME_FILE:-}" && -f "${APPIMAGE_RUNTIME_FILE}" ]]; then
    appimagetool_args+=(--runtime-file "${APPIMAGE_RUNTIME_FILE}")
fi
VERSION="${VERSION}" appimagetool "${appimagetool_args[@]}" "${APPDIR}" "${OUT_DIR}/${APPIMAGE_NAME}"
chmod +x "${OUT_DIR}/${APPIMAGE_NAME}"

# ---------------------------------------------------------------------------
# Assemble the distributable bundle
# ---------------------------------------------------------------------------
log "Collecting helper scripts"
install -m755 "${SRC_DIR}/appimage/run.sh" "${OUT_DIR}/imsprog"
install -m755 "${SRC_DIR}/appimage/install-desktop.sh" "${OUT_DIR}/install-desktop-integration.sh"
install -m644 "${SRC_DIR}/appimage/README.md" "${OUT_DIR}/README-AppImage.md"

(
    cd "${OUT_DIR}"
    sha256sum "${APPIMAGE_NAME}" > "${APPIMAGE_NAME}.sha256"
)

log "Done - artifacts in ${OUT_DIR}"
ls -lh "${OUT_DIR}" >&2
