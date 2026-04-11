# OmniFocus MCP — Quick Guide

This file is intentionally lean. Load deeper docs only when needed.

## Start Here

- Product/user overview: `README.md`
- Architecture map: `docs/architecture.md`
- MCP + CLI compatibility behavior: `docs/protocol-and-compat.md`
- Tool implementation workflow: `docs/tool-authoring.md`
- Tool catalog references: `docs/tool-catalog.md`

## Build And Test

```bash
swift build -c release
.build/release/omnifocus-mcp
.build/release/omnifocus-cli
./scripts/test.sh --no-build
```

Live tests (OmniFocus running):

```bash
./scripts/test_live.sh --no-build
```

## High-Signal Rules

- Keep JXA and Omni Automation behavior aligned unless an API difference requires divergence.
- When changing MCP-visible behavior, update `scripts/test.sh` and docs in the same PR.
- When changing live OmniFocus behavior, update `scripts/test_live.sh` when practical.
- Treat `Tools.swift` as the static schema source of truth.

## Where To Edit

- MCP protocol/transport: `Sources/omnifocus-mcp/MCPServer.swift`
- CLI/daemon/launchd: `Sources/omnifocus-cli/CLI.swift`
- Dispatch/runtime engine: `Sources/OmniFocusCore/OFEngine.swift`
- Tool metadata/schemas: `Sources/OmniFocusCore/Tools.swift`
- Backend implementations: `Sources/OmniFocusCore/Resources/jxa.js`, `Sources/OmniFocusCore/Resources/omni_automation.js`
- Shared JS helpers: `Sources/OmniFocusCore/Resources/shared.js`

## Documentation Policy

Keep `CLAUDE.md` as an index only. Put details in focused files under `docs/`.
