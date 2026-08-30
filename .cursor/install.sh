#!/usr/bin/env bash
# Cloud Agent bootstrap for the OmniFocus MCP + CLI Swift package.
#
# Installs the Swift toolchain (not present in the base image) plus its runtime
# system dependencies, then builds the release binaries. Designed to be
# idempotent: re-running skips work that is already done, so it is safe to use
# as an environment `install` step (including for build snapshots).
set -euo pipefail

SWIFT_VERSION="6.2"
SWIFT_RELEASE="swift-${SWIFT_VERSION}-RELEASE"
UBUNTU_TARGET="ubuntu24.04"
UBUNTU_DIR="ubuntu2404"
SWIFT_PREFIX="/opt/swift"
SWIFT_BIN="${SWIFT_PREFIX}/usr/bin"
TARBALL_URL="https://download.swift.org/swift-${SWIFT_VERSION}-release/${UBUNTU_DIR}/${SWIFT_RELEASE}/${SWIFT_RELEASE}-${UBUNTU_TARGET}.tar.gz"

log() { printf '==> %s\n' "$*"; }

# 1. Runtime/build system dependencies for the Swift toolchain on Ubuntu 24.04.
log "Installing system dependencies (apt)"
sudo apt-get update -qq
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
  binutils \
  gnupg2 \
  libc6-dev \
  libcurl4-openssl-dev \
  libedit2 \
  libgcc-13-dev \
  libncurses6 \
  libncursesw6 \
  libpython3-dev \
  libstdc++-13-dev \
  libxml2-dev \
  libz3-dev \
  pkg-config \
  tzdata \
  unzip \
  zlib1g-dev

# 2. Swift toolchain (skip download if already present).
if [ ! -x "${SWIFT_BIN}/swift" ]; then
  log "Downloading Swift ${SWIFT_VERSION} toolchain"
  tmp_tarball="$(mktemp --suffix=.tar.gz)"
  curl -fL --retry 4 --retry-delay 4 -o "${tmp_tarball}" "${TARBALL_URL}"
  log "Extracting Swift toolchain to ${SWIFT_PREFIX}"
  sudo mkdir -p "${SWIFT_PREFIX}"
  sudo tar xzf "${tmp_tarball}" -C "${SWIFT_PREFIX}" --strip-components=1
  rm -f "${tmp_tarball}"
else
  log "Swift toolchain already present at ${SWIFT_PREFIX} — skipping download"
fi

# 3. Expose the toolchain on PATH. Symlinks in /usr/local/bin (already on PATH)
#    work because Swift resolves its runtime resources via the resolved binary
#    path. Also drop a profile.d entry so login shells pick up the full bin dir.
log "Linking Swift binaries into /usr/local/bin"
sudo ln -sf "${SWIFT_BIN}"/* /usr/local/bin/
echo "export PATH=\"${SWIFT_BIN}:\$PATH\"" | sudo tee /etc/profile.d/swift.sh >/dev/null
sudo chmod 0644 /etc/profile.d/swift.sh

export PATH="${SWIFT_BIN}:${PATH}"
log "Swift version: $(swift --version 2>&1 | head -1)"

# 4. Build the release binaries so the workspace is ready to run and test.
log "Building release binaries (swift build -c release)"
swift build -c release

log "Setup complete. Binaries:"
ls -la .build/release/omnifocus-mcp .build/release/omnifocus-cli
