#!/usr/bin/env bash
#
# Install IMSProg desktop integration (menu entries, icons, udev rules) for the
# AppImage shipped in this bundle.
#
#   ./install-desktop-integration.sh             # current user only
#   sudo ./install-desktop-integration.sh --system   # all users
#   ./install-desktop-integration.sh --no-udev   # skip the USB rules
#
# The IMSProg AppImage is copied to a stable location (~/.local/bin or
# /opt/imsprog) so that the menu entries keep working after you move the bundle.
#
set -euo pipefail

SELF_DIR=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)

MODE="user"
INSTALL_UDEV=1
APPIMAGE_ARG=""

usage() {
    cat <<'EOF'
Usage: install-desktop-integration.sh [options] [IMSProg.AppImage]

Options:
  --system      install for every user (needs root):
                /opt/imsprog, /usr/local/bin, /usr/share/applications
  --no-udev     do not install the CH341/CH347/FT232H udev rules
  --no-desktop  only install the udev rules
  -h, --help    show this help

Without options the AppImage and the menu entries are installed for the
current user only.
EOF
}

info() { printf '%s\n' "$*" >&2; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
    case "$1" in
        --system)     MODE="system" ;;
        --no-udev)    INSTALL_UDEV=0 ;;
        --no-desktop) INSTALL_DESKTOP=0 ;;
        -h|--help)    usage; exit 0 ;;
        -*)           die "unknown option: $1 (try --help)" ;;
        *)            APPIMAGE_ARG="$1" ;;
    esac
    shift
done
INSTALL_DESKTOP=${INSTALL_DESKTOP:-1}

find_appimage() {
    local candidate
    if [[ -n "${IMSPROG_APPIMAGE:-}" ]]; then
        printf '%s\n' "${IMSPROG_APPIMAGE}"
        return 0
    fi
    for candidate in "${SELF_DIR}"/IMSProg-*.AppImage "${SELF_DIR}"/IMSProg.AppImage; do
        if [[ -f "${candidate}" ]]; then
            printf '%s\n' "${candidate}"
            return 0
        fi
    done
    return 1
}

if [[ -n "${APPIMAGE_ARG}" ]]; then
    SOURCE_APPIMAGE=$(readlink -f "${APPIMAGE_ARG}")
else
    SOURCE_APPIMAGE=$(find_appimage || true)
fi
[[ -n "${SOURCE_APPIMAGE}" && -f "${SOURCE_APPIMAGE}" ]] || \
    die "no IMSProg AppImage found - pass its path as an argument"

if [[ ! -x "${SOURCE_APPIMAGE}" ]]; then
    chmod +x "${SOURCE_APPIMAGE}" || die "cannot make ${SOURCE_APPIMAGE} executable"
fi

# AppImages need FUSE; fall back to the extraction mode when it is unavailable.
run_appimage() {
    if [[ -e /dev/fuse ]] && ldconfig -p 2>/dev/null | grep 'libfuse\.so\.2' >/dev/null; then
        "${SOURCE_APPIMAGE}" "$@"
    else
        APPIMAGE_EXTRACT_AND_RUN=1 "${SOURCE_APPIMAGE}" "$@"
    fi
}

# Root is only required to write outside of the user's home (--system); the
# udev step asks for privileges through the AppImage's own sudo handling.
SUDO=""
if [[ "${MODE}" == "system" ]]; then
    if [[ "$(id -u)" -ne 0 ]]; then
        command -v sudo >/dev/null 2>&1 || die "root privileges are required for --system"
        SUDO="sudo"
    fi
    APPIMAGE_DIR="/opt/imsprog"
    APPIMAGE="${APPIMAGE_DIR}/IMSProg.AppImage"
    ICON_DIR="/usr/local/share/icons/imsprog"
    APPLICATIONS_DIR="/usr/share/applications"
    BIN_DIR="/usr/local/bin"
else
    APPIMAGE_DIR="${HOME}/.local/bin"
    APPIMAGE="${APPIMAGE_DIR}/IMSProg.AppImage"
    ICON_DIR="${XDG_DATA_HOME:-${HOME}/.local/share}/icons/imsprog"
    APPLICATIONS_DIR="${XDG_DATA_HOME:-${HOME}/.local/share}/applications"
    BIN_DIR="${HOME}/.local/bin"
fi

run() { if [[ -n "${SUDO}" ]]; then "${SUDO}" "$@"; else "$@"; fi; }

# ---------------------------------------------------------------------------
# udev rules (USB programmers)
# ---------------------------------------------------------------------------
if [[ "${INSTALL_UDEV}" -eq 1 ]]; then
    info "Installing udev rules"
    run_appimage --install-udev-rules
fi

if [[ "${INSTALL_DESKTOP}" -eq 0 ]]; then
    info "Skipping desktop integration (--no-desktop)"
    exit 0
fi

# ---------------------------------------------------------------------------
# Install the AppImage itself in a stable location
# ---------------------------------------------------------------------------
if [[ "${SOURCE_APPIMAGE}" != "${APPIMAGE}" ]]; then
    info "Installing AppImage to ${APPIMAGE}"
    run mkdir -p "${APPIMAGE_DIR}"
    run install -m755 "${SOURCE_APPIMAGE}" "${APPIMAGE}"
fi

# ---------------------------------------------------------------------------
# Icons and desktop entries
# ---------------------------------------------------------------------------
TMP_DIR=$(mktemp -d)
trap 'rm -rf "${TMP_DIR}"' EXIT

extract() {
    local pattern="$1"
    mkdir -p "${TMP_DIR}"
    ( cd "${TMP_DIR}" && "${APPIMAGE}" --appimage-extract "${pattern}" >/dev/null 2>&1 )
}

extract 'usr/share/pixmaps/*.png'
extract 'usr/share/applications/*.desktop'

[[ -d "${TMP_DIR}/squashfs-root" ]] || die "could not extract the integration files from ${APPIMAGE}"

info "Installing icons to ${ICON_DIR}"
run mkdir -p "${ICON_DIR}"
for icon in IMSProg64.png chipEdit64.png IMSProg_database_update.png; do
    if [[ -f "${TMP_DIR}/squashfs-root/usr/share/pixmaps/${icon}" ]]; then
        run install -m644 "${TMP_DIR}/squashfs-root/usr/share/pixmaps/${icon}" "${ICON_DIR}/${icon}"
    fi
done

info "Installing menu entries to ${APPLICATIONS_DIR}"
run mkdir -p "${APPLICATIONS_DIR}"

ENTRY_DIR="${TMP_DIR}/entries"
mkdir -p "${ENTRY_DIR}"
for desktop in IMSProg.desktop IMSProg_editor.desktop IMSProg_database_update.desktop; do
    src="${TMP_DIR}/squashfs-root/usr/share/applications/${desktop}"
    [[ -f "${src}" ]] || continue
    sed -e '/^Path=/d' \
        -e "s|^Icon=/usr/share/pixmaps/|Icon=${ICON_DIR}/|" \
        -e "s|^Exec=/usr/bin/IMSProg_editor|Exec=\"${APPIMAGE}\" --editor|" \
        -e "s|^Exec=/usr/bin/IMSProg_database_update|Exec=\"${APPIMAGE}\" --updater|" \
        -e "s|^Exec=/usr/bin/IMSProg\$|Exec=\"${APPIMAGE}\"|" \
        "${src}" > "${ENTRY_DIR}/${desktop}"
    run install -m644 "${ENTRY_DIR}/${desktop}" "${APPLICATIONS_DIR}/${desktop}"
done

if command -v update-desktop-database >/dev/null 2>&1; then
    run update-desktop-database "${APPLICATIONS_DIR}" >/dev/null 2>&1 || true
fi

# ---------------------------------------------------------------------------
# Command line launcher
# ---------------------------------------------------------------------------
if [[ -d "${BIN_DIR}" ]]; then
    info "Linking ${BIN_DIR}/imsprog -> ${APPIMAGE}"
    run ln -sf "${APPIMAGE}" "${BIN_DIR}/imsprog"
else
    info "note: ${BIN_DIR} does not exist, skipping the 'imsprog' command."
    info "      Create it and run this script again to get a terminal launcher."
fi

info ""
info "IMSProg installed:"
info "  programmer  ${APPIMAGE}"
info "  editor      ${APPIMAGE} --editor"
info "  updater     ${APPIMAGE} --updater"
info "  menu entries in ${APPLICATIONS_DIR}"
