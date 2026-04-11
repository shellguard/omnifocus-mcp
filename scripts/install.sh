#!/bin/sh
# install.sh — build and install omnifocus-mcp and omnifocus-cli
# Usage: ./scripts/install.sh [--prefix /usr/local]
set -eu

BINARIES="omnifocus-mcp omnifocus-cli"
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

echo "==> Building (release)"
cd "$ROOT_DIR"
swift build -c release

for bin in $BINARIES; do
  BIN_PATH="$ROOT_DIR/.build/release/$bin"
  if [ ! -x "$BIN_PATH" ]; then
    echo "Error: build succeeded but binary not found at $BIN_PATH" >&2
    exit 1
  fi
done

# ── Install ──────────────────────────────────────────────────────────────────

echo "==> Installing to $BIN_DIR"
if [ ! -d "$BIN_DIR" ]; then
  mkdir -p "$BIN_DIR"
fi

NEEDS_SUDO=false
if [ ! -w "$BIN_DIR" ]; then
  NEEDS_SUDO=true
  echo "  (requires sudo to write to $BIN_DIR)"
fi

for bin in $BINARIES; do
  BIN_PATH="$ROOT_DIR/.build/release/$bin"
  if [ "$NEEDS_SUDO" = true ]; then
    sudo cp "$BIN_PATH" "$BIN_DIR/$bin"
    sudo chmod 755 "$BIN_DIR/$bin"
  else
    cp "$BIN_PATH" "$BIN_DIR/$bin"
    chmod 755 "$BIN_DIR/$bin"
  fi
  echo "  Installed: $BIN_DIR/$bin"
done

# ── Post-install hints ───────────────────────────────────────────────────────

MCP_BIN="$BIN_DIR/omnifocus-mcp"
CLI_BIN="$BIN_DIR/omnifocus-cli"

cat <<EOF

Done! Next steps:

1. Grant Automation permission (first run will prompt):
     System Settings > Privacy & Security > Automation
     Allow Terminal (or your MCP client) to control OmniFocus.

2. In OmniFocus, enable:
     Automation > Accept scripts from external applications

3. MCP server config (Claude Desktop / Claude Code):

     {
       "mcpServers": {
         "omnifocus": {
           "command": "$MCP_BIN",
           "args": []
         }
       }
     }

4. CLI usage:

     $CLI_BIN --help
     $CLI_BIN list-tasks --flagged
     $CLI_BIN create-task --name "Buy milk"

5. Optional: start CLI daemon (faster repeated calls):

     $CLI_BIN --daemon        # start
     $CLI_BIN --install       # auto-start at login via launchd

   Environment overrides:
     OF_BACKEND=automation   # or: jxa
     OF_APP_PATH=/Applications/OmniFocus.app

EOF
