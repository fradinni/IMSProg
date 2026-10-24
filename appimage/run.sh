#!/usr/bin/env bash
#
# Convenience launcher for the IMSProg AppImage.
#
# Keep this script next to the AppImage (it is shipped in the same bundle) and
# run it instead of the AppImage itself when you want the boring details to be
# handled for you:
#
#   ./imsprog                # chip programmer
#   ./imsprog editor         # chip database editor
#   ./imsprog updater        # chip database updater
#   ./imsprog --help         # all options
#
# It locates the AppImage, makes it executable if needed, falls back to the
# extract-and-run mode when FUSE is unavailable, and warns when the udev rules
# have not been installed yet.
#
set -euo pipefail

SELF_PATH=$(readlink -f "${BASH_SOURCE[0]}")
SELF_DIR=$(cd "$(dirname "$SELF_PATH")" && pwd)

info() { printf '%s\n' "$*" >&2; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

find_appimage() {
    local candidate
    if [[ -n "${IMSPROG_APPIMAGE:-}" ]]; then
        printf '%s\n' "${IMSPROG_APPIMAGE}"
        return 0
    fi
    for candidate in \
        "${SELF_DIR}"/IMSProg-*.AppImage \
        "${SELF_DIR}"/IMSProg.AppImage \
        "${HOME}/.local/bin/IMSProg.AppImage"; do
        if [[ -f "${candidate}" ]]; then
            printf '%s\n' "${candidate}"
            return 0
        fi
    done
    return 1
}

APPIMAGE=$(find_appimage) || die \
    "no IMSProg AppImage found next to this script (${SELF_DIR}).
Set IMSPROG_APPIMAGE=/path/to/IMSProg-*.AppImage to point at it explicitly."

[[ -f "${APPIMAGE}" ]] || die "${APPIMAGE} does not exist"

# AppImages cannot be executed unless the executable bit is set; this is lost
# when the file goes through some download tools, FAT partitions, zip archives...
if [[ ! -x "${APPIMAGE}" ]]; then
    if ! chmod +x "${APPIMAGE}" 2>/dev/null; then
        die "cannot make ${APPIMAGE} executable (read-only location?)
Copy it to your home directory and try again."
    fi
fi

# Translate the friendly names into the AppRun switches.
if [[ $# -gt 0 ]]; then
    case "$1" in
        editor|--editor)             set -- --editor "${@:2}" ;;
        updater|db|database|--updater)
                                     set -- --updater "${@:2}" ;;
    esac
fi

# AppImages need FUSE. Fall back to the (slower) self-extracting mode on systems
# without it, e.g. minimal distributions or containers.
fuse_available() {
    [[ -e /dev/fuse ]] || return 1
    # Not `grep -q`: it would close the pipe early, making ldconfig die of
    # SIGPIPE and trip `set -o pipefail`.
    ldconfig -p 2>/dev/null | grep 'libfuse\.so\.2' >/dev/null
}

if ! fuse_available; then
    info "FUSE is not available, extracting the AppImage to a temporary directory (slower)."
    export APPIMAGE_EXTRACT_AND_RUN=1
fi

# Friendly reminder about the USB access rules - only for the applications that
# talk to the programmer, not for --help/--version.
case "${1:-}" in
    ""|--editor|editor|--updater|--database-update|updater|update-database)
        if [[ ! -f /etc/udev/rules.d/71-CH341.rules ]]; then
            info "note: USB programmer udev rules are not installed yet."
            info "      run: $(basename "$SELF_PATH") --install-udev-rules"
        fi
        ;;
esac

exec "${APPIMAGE}" "$@"
