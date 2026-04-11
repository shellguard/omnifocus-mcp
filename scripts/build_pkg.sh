#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
BINARIES="omnifocus-mcp omnifocus-cli"
BUILD_CONFIG="${BUILD_CONFIG:-release}"
VERSION="${PKG_VERSION:-0.2.0}"
IDENTIFIER="${PKG_IDENTIFIER:-com.omnifocus-mcp.cli}"
INSTALL_LOCATION="${PKG_INSTALL_LOCATION:-/usr/local/bin}"
PKG_ROOT="$ROOT_DIR/.pkgroot"
OUT_DIR="$ROOT_DIR/dist"

echo "Building (${BUILD_CONFIG})"
swift build -c "$BUILD_CONFIG"

for bin in $BINARIES; do
  BIN_PATH="$ROOT_DIR/.build/$BUILD_CONFIG/$bin"
  if [ ! -x "$BIN_PATH" ]; then
    echo "Built binary not found: $BIN_PATH" >&2
    exit 1
  fi
done

rm -rf "$PKG_ROOT"
mkdir -p "$PKG_ROOT$INSTALL_LOCATION" "$OUT_DIR"

for bin in $BINARIES; do
  cp "$ROOT_DIR/.build/$BUILD_CONFIG/$bin" "$PKG_ROOT$INSTALL_LOCATION/$bin"
  chmod 755 "$PKG_ROOT$INSTALL_LOCATION/$bin"
done

PKG_PATH="$OUT_DIR/omnifocus-mcp-$VERSION.pkg"
if [ -n "${PKG_SIGN_ID:-}" ]; then
  pkgbuild \
    --root "$PKG_ROOT" \
    --identifier "$IDENTIFIER" \
    --version "$VERSION" \
    --install-location "/" \
    --sign "$PKG_SIGN_ID" \
    "$PKG_PATH"
else
  pkgbuild \
    --root "$PKG_ROOT" \
    --identifier "$IDENTIFIER" \
    --version "$VERSION" \
    --install-location "/" \
    "$PKG_PATH"
fi

echo "Built package: $PKG_PATH"
echo "  Contains: $BINARIES"
echo "  Install location: $INSTALL_LOCATION"
