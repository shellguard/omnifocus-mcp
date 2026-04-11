# Architecture

## Components

- `OmniFocusCore`: shared engine, tool metadata, JS resources.
- `omnifocus-mcp`: MCP server over stdio JSON-RPC.
- `omnifocus-cli`: command-line interface + optional local daemon.

No external Swift dependencies (Foundation + stdlib only).

## Key Files

- `Sources/OmniFocusCore/OFEngine.swift`: tool dispatch, backend selection, script execution.
- `Sources/OmniFocusCore/Tools.swift`: static tool definitions (`allTools`).
- `Sources/OmniFocusCore/Resources/shared.js`: shared utility functions used by both JS backends.
- `Sources/OmniFocusCore/Resources/jxa.js`: JXA action implementations.
- `Sources/OmniFocusCore/Resources/omni_automation.js`: Omni Automation action implementations.
- `Sources/omnifocus-mcp/MCPServer.swift`: MCP protocol handlers.
- `Sources/omnifocus-cli/CLI.swift`: CLI parsing, daemon, launchd integration.

## JS Backend Composition

At runtime each backend script is assembled from:

1. Backend-specific JS file (`jxa.js` or `omni_automation.js`)
2. Shared utilities injected from `shared.js`

When adding/changing behavior, keep both backend action switches in sync unless explicitly backend-specific.

## Tool Dispatch

- Tool names use `omnifocus_<action>`.
- Swift dispatch strips `omnifocus_` and routes to backend action handlers.
- Tool metadata and schemas live in `Tools.swift`.
