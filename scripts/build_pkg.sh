#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
BIN_NAME="omnifocus-mcp"
BUILD_CONFIG="${BUILD_CONFIG:-release}"
VERSION="${PKG_VERSION:-0.1.0}"
IDENTIFIER="${PKG_IDENTIFIER:-com.omnifocus-mcp.cli}"
INSTALL_LOCATION="${PKG_INSTALL_LOCATION:-/usr/local/bin}"
PKG_ROOT="$ROOT_DIR/.pkgroot"
OUT_DIR="$ROOT_DIR/dist"

echo "Building $BIN_NAME ($BUILD_CONFIG)"
swift build -c "$BUILD_CONFIG"

BIN_PATH="$ROOT_DIR/.build/$BUILD_CONFIG/$BIN_NAME"
if [ ! -x "$BIN_PATH" ]; then
  echo "Built binary not found: $BIN_PATH" >&2
  exit 1
fi

rm -rf "$PKG_ROOT"
mkdir -p "$PKG_ROOT$INSTALL_LOCATION" "$OUT_DIR"
cp "$BIN_PATH" "$PKG_ROOT$INSTALL_LOCATION/$BIN_NAME"
chmod 755 "$PKG_ROOT$INSTALL_LOCATION/$BIN_NAME"

PKG_PATH="$OUT_DIR/$BIN_NAME-$VERSION.pkg"
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
