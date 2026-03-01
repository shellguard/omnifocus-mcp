#!/bin/sh
# install.sh — build and install omnifocus-mcp
# Usage: ./scripts/install.sh [--prefix /usr/local]
set -eu

BINARY="omnifocus-mcp"
PREFIX="${INSTALL_PREFIX:-/usr/local}"

# Parse --prefix flag
while [ $# -gt 0 ]; do
  case "$1" in
    --prefix)
      PREFIX="$2"; shift 2 ;;
    --prefix=*)
      PREFIX="${1#--prefix=}"; shift ;;
    *)
      echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

BIN_DIR="$PREFIX/bin"
ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

# ── Prerequisites ────────────────────────────────────────────────────────────

check_swift() {
  if ! command -v swift > /dev/null 2>&1; then
    echo "Error: swift not found. Install the Swift toolchain from https://swift.org/download/" >&2
    exit 1
  fi
  version=$(swift --version 2>&1 | head -1)
  echo "  Swift: $version"
}

check_omnifocus() {
  if [ ! -d "/Applications/OmniFocus.app" ] && [ ! -d "$HOME/Applications/OmniFocus.app" ]; then
    echo "Warning: OmniFocus.app not found in /Applications or ~/Applications." >&2
    echo "         The server requires OmniFocus 4 to be installed and running." >&2
  else
    echo "  OmniFocus: found"
  fi
}

echo "==> Checking prerequisites"
check_swift
check_omnifocus

# ── Build ────────────────────────────────────────────────────────────────────

echo "==> Building $BINARY (release)"
cd "$ROOT_DIR"
swift build -c release

BIN_PATH="$ROOT_DIR/.build/release/$BINARY"
if [ ! -x "$BIN_PATH" ]; then
  echo "Error: build succeeded but binary not found at $BIN_PATH" >&2
  exit 1
fi

# ── Install ──────────────────────────────────────────────────────────────────

echo "==> Installing to $BIN_DIR"
if [ ! -d "$BIN_DIR" ]; then
  mkdir -p "$BIN_DIR"
fi

# Use sudo only if we can't write to the target directory
if [ -w "$BIN_DIR" ]; then
  cp "$BIN_PATH" "$BIN_DIR/$BINARY"
  chmod 755 "$BIN_DIR/$BINARY"
else
  echo "  (requires sudo to write to $BIN_DIR)"
  sudo cp "$BIN_PATH" "$BIN_DIR/$BINARY"
  sudo chmod 755 "$BIN_DIR/$BINARY"
fi

INSTALLED="$BIN_DIR/$BINARY"
echo "==> Installed: $INSTALLED"

# ── Post-install hints ───────────────────────────────────────────────────────

cat <<EOF

Done! Next steps:

1. Grant Automation permission (first run will prompt):
     System Settings > Privacy & Security > Automation
     Allow Terminal (or your MCP client) to control OmniFocus.

2. In OmniFocus, enable:
     Settings > Automation > Allow JavaScript from Apple Events

3. Add to your MCP client config:

   Claude Desktop (~/.claude/claude_desktop_config.json):
     {
       "mcpServers": {
         "omnifocus": {
           "command": "$INSTALLED",
           "args": []
         }
       }
     }

   Claude Code (~/.claude/settings.json):
     {
       "mcpServers": {
         "omnifocus": {
           "command": "$INSTALLED",
           "args": []
         }
       }
     }

   Environment overrides (optional):
     OF_BACKEND=automation   # or: jxa
     OF_APP_PATH=/Applications/OmniFocus.app

EOF
