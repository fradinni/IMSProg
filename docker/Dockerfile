# Build environment for the IMSProg Linux AppImage.
#
# The image contains everything needed to compile IMSProg against Qt5 and to
# package the result with linuxdeploy/appimagetool:
#
#   docker build -f docker/Dockerfile -t imsprog-appimage-builder .
#   ./build_appimage.sh            # does the above and runs the container
#
FROM ubuntu:22.04

LABEL org.opencontainers.image.title="IMSProg AppImage builder" \
      org.opencontainers.image.description="Builds the IMSProg Qt5 suite and packages it as an AppImage" \
      org.opencontainers.image.source="https://github.com/bigbigmdm/IMSProg"

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    # linuxdeploy/appimagetool are AppImages themselves: FUSE is not available
    # inside most containers, so always extract and run them.
    APPIMAGE_EXTRACT_AND_RUN=1

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
        build-essential \
        ca-certificates \
        cmake \
        curl \
        file \
        libftdi1-dev \
        libfuse2 \
        libudev-dev \
        libusb-1.0-0-dev \
        patchelf \
        pkg-config \
        qtbase5-dev \
        qtbase5-dev-tools \
        qttools5-dev \
        qttools5-dev-tools \
        qtwayland5 \
        udev \
 && rm -rf /var/lib/apt/lists/*

# Pre-fetch the AppImage tooling so that the build itself works offline.
ARG APPIMAGE_TOOLS_DIR=/opt/appimage-tools
RUN mkdir -p "${APPIMAGE_TOOLS_DIR}" \
 && curl -fsSL -o "${APPIMAGE_TOOLS_DIR}/linuxdeploy" \
        https://github.com/linuxdeploy/linuxdeploy/releases/download/continuous/linuxdeploy-x86_64.AppImage \
 && curl -fsSL -o "${APPIMAGE_TOOLS_DIR}/linuxdeploy-plugin-qt" \
        https://github.com/linuxdeploy/linuxdeploy-plugin-qt/releases/download/continuous/linuxdeploy-plugin-qt-x86_64.AppImage \
 && curl -fsSL -o "${APPIMAGE_TOOLS_DIR}/appimagetool" \
        https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-x86_64.AppImage \
 && curl -fsSL -o "${APPIMAGE_TOOLS_DIR}/runtime-x86_64" \
        https://github.com/AppImage/type2-runtime/releases/download/continuous/runtime-x86_64 \
 && chmod +x "${APPIMAGE_TOOLS_DIR}"/linuxdeploy \
              "${APPIMAGE_TOOLS_DIR}"/linuxdeploy-plugin-qt \
              "${APPIMAGE_TOOLS_DIR}"/appimagetool

# The AppImage runtime is normally downloaded by appimagetool on every build;
# ship it in the image so that builds are reproducible and can run offline.
ENV APPIMAGE_RUNTIME_FILE="${APPIMAGE_TOOLS_DIR}/runtime-x86_64"

ENV PATH="${APPIMAGE_TOOLS_DIR}:${PATH}"

COPY docker/container-build.sh /usr/local/bin/container-build
RUN chmod +x /usr/local/bin/container-build

WORKDIR /src

# The build script prints progress on stderr and writes the artifacts to $OUT_DIR
# (/out by default). Mount the sources read-only at /src and an output directory
# at /out; see build_appimage.sh.
ENTRYPOINT ["/usr/local/bin/container-build"]
