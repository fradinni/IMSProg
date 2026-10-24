#!/usr/bin/env bash
#
# Build an IMSProg AppImage inside a Docker/Podman container.
#
#   ./build_appimage.sh                 # auto-detects docker or podman
#   ./build_appimage.sh 1.9.2           # override the version string
#   CONTAINER_ENGINE=podman ./build_appimage.sh
#   IMAGE=my/imsprog-builder ./build_appimage.sh --no-build
#
# Deliverables are written to ./dist:
#   IMSProg-<version>-x86_64.AppImage
#   IMSProg-<version>-x86_64.AppImage.sha256
#   imsprog                            (small launcher script)
#   install-desktop-integration.sh     (menu entries + udev rules)
#   README-AppImage.md
#
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)
IMAGE=${IMAGE:-imsprog-appimage-builder:latest}
DIST_DIR=${DIST_DIR:-"${ROOT_DIR}/dist"}
JOBS=${JOBS:-}

BUILD_IMAGE=1
for arg in "$@"; do
    case "$arg" in
        --no-build) BUILD_IMAGE=0 ;;
        -h|--help)
            awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$0"
            exit 0
            ;;
        -*) echo "error: unknown option: $arg" >&2; exit 1 ;;
        *) VERSION_ARG="$arg" ;;
    esac
done

detect_engine() {
    if [[ -n "${CONTAINER_ENGINE:-}" ]]; then
        printf '%s\n' "${CONTAINER_ENGINE}"
        return
    fi
    if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
        printf 'docker\n'
    elif command -v podman >/dev/null 2>&1; then
        printf 'podman\n'
    elif command -v docker >/dev/null 2>&1; then
        printf 'docker\n'
    else
        echo "error: neither docker nor podman is available" >&2
        exit 1
    fi
}

ENGINE=$(detect_engine)
ENGINE_NAME=$(basename "${ENGINE}")

if [[ -n "${VERSION_ARG:-}" ]]; then
    VERSION="${VERSION_ARG}"
elif [[ -z "${VERSION:-}" ]]; then
    VERSION=$(awk '/^Version:/ {print $2; exit}' "${ROOT_DIR}/rpm/imsprog.spec")
fi
[[ -n "${VERSION}" ]] || { echo "error: cannot determine the version" >&2; exit 1; }

mkdir -p "${DIST_DIR}"

if [[ "${BUILD_IMAGE}" -eq 1 ]]; then
    echo "==> Building container image ${IMAGE} with ${ENGINE_NAME}"
    "${ENGINE}" build -f "${ROOT_DIR}/docker/Dockerfile" -t "${IMAGE}" "${ROOT_DIR}"
fi

# Rootless podman on an SELinux system needs the label confinement disabled for
# the bind mounts (relabelling the project tree would be intrusive).
RUN_OPTS=()
if [[ "${ENGINE_NAME}" == "podman" ]] && command -v getenforce >/dev/null 2>&1 \
   && [[ "$(getenforce)" == "Enforcing" ]]; then
    RUN_OPTS+=(--security-opt label=disable)
fi

# With a rootful docker daemon the build would otherwise leave root-owned files
# in ./dist; run as the invoking user instead (podman rootless already does, and
# bind mounts behave differently under Docker Desktop).
if [[ "${ENGINE_NAME}" == "docker" && "$(uname -s)" == "Linux" ]]; then
    docker_security=$(docker info --format '{{.SecurityOptions}}' 2>/dev/null || true)
    case "${docker_security}" in
        *rootless*) ;;
        *) RUN_OPTS+=(--user "$(id -u):$(id -g)") ;;
    esac
fi

echo "==> Building IMSProg ${VERSION} AppImage"
"${ENGINE}" run --rm \
    ${RUN_OPTS[@]+"${RUN_OPTS[@]}"} \
    -v "${ROOT_DIR}:/src:ro" \
    -v "${DIST_DIR}:/out" \
    -e "VERSION=${VERSION}" \
    ${JOBS:+-e "JOBS=${JOBS}"} \
    "${IMAGE}"

echo
echo "==> Artifacts in ${DIST_DIR}"
ls -lh "${DIST_DIR}"
