#!/bin/sh
# build_universal.sh — build universal (arm64 + x86_64) binaries
# Usage: ./scripts/build_universal.sh
# Output: dist/omnifocus-mcp, dist/omnifocus-cli, dist/omnifocus-mcp-<version>.tar.gz
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
BINARIES="omnifocus-mcp omnifocus-cli"
OUT_DIR="$ROOT_DIR/dist"
VERSION="${VERSION:-$(grep 'serverVersion\|"version"' "$ROOT_DIR/Sources/omnifocus-mcp/MCPServer.swift" 2>/dev/null | head -1 | sed 's/.*"\(.*\)".*/\1/' || echo "0.2.0")}"

echo "==> Building universal binaries (version $VERSION)"

# ── arm64 ────────────────────────────────────────────────────────────────────
echo "  Building arm64..."
swift build -c release --arch arm64

# ── x86_64 ───────────────────────────────────────────────────────────────────
echo "  Building x86_64..."
swift build -c release --arch x86_64

# ── Lipo ─────────────────────────────────────────────────────────────────────
rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"

for bin in $BINARIES; do
  ARM64_BIN="$ROOT_DIR/.build/arm64-apple-macosx/release/$bin"
  X86_BIN="$ROOT_DIR/.build/x86_64-apple-macosx/release/$bin"

  if [ ! -x "$ARM64_BIN" ]; then
    echo "Error: arm64 binary not found: $ARM64_BIN" >&2
    exit 1
  fi
  if [ ! -x "$X86_BIN" ]; then
    echo "Error: x86_64 binary not found: $X86_BIN" >&2
    exit 1
  fi

  echo "  Lipo: $bin"
  lipo -create "$ARM64_BIN" "$X86_BIN" -output "$OUT_DIR/$bin"
  chmod 755 "$OUT_DIR/$bin"
done

# ── Verify ───────────────────────────────────────────────────────────────────
for bin in $BINARIES; do
  ARCHS=$(lipo -archs "$OUT_DIR/$bin")
  echo "  $bin: $ARCHS"
done

# ── Tarball ──────────────────────────────────────────────────────────────────
TARBALL="omnifocus-mcp-${VERSION}-macos-universal.tar.gz"
(cd "$OUT_DIR" && tar czf "$TARBALL" $BINARIES)
SHA256=$(shasum -a 256 "$OUT_DIR/$TARBALL" | cut -d' ' -f1)

echo ""
echo "==> Output"
echo "  Binaries: $OUT_DIR/omnifocus-mcp, $OUT_DIR/omnifocus-cli"
echo "  Tarball:  $OUT_DIR/$TARBALL"
echo "  SHA256:   $SHA256"
echo ""
echo "  VERSION=$VERSION"
echo "  SHA256=$SHA256"
