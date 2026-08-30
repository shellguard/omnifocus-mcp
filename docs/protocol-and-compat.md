# Protocol And Compatibility

## MCP Behavior

Current server behavior in `MCPServer.swift` is dual-era:

### Legacy handshake (`2025-11-25`, `2025-06-18`, `2024-11-05`)

- `initialize` negotiates version: uses requested version if supported, otherwise falls back to `2025-11-25`
- Accepts both lifecycle notifications:
  - `initialized`
  - `notifications/initialized`
- `logging/setLevel` is session-scoped (deprecated in `2026-07-28`; kept on this path)
- Sampling remains available when the client advertises `capabilities.sampling` at initialize

### Modern per-request metadata (`2026-07-28`)

- `server/discover` is always implemented (stdio compatibility probe; no `_meta` required)
- Every other modern request carries `_meta.io.modelcontextprotocol/protocolVersion`
- Unknown `_meta` versions return JSON-RPC `-32022` (`UnsupportedProtocolVersionError`) with `data.supported` / `data.requested`
- Results include `resultType: "complete"` and `_meta.io.modelcontextprotocol/serverInfo`
- `tools/list`, `prompts/list`, and `server/discover` also include `ttlMs` and `cacheScope`
- Log level is per-request via `_meta.io.modelcontextprotocol/logLevel`; `logging/setLevel` is rejected
- Sampling / Logging / Roots are not advertised on this path

### Shared

- `tools/call` execution failures return `result.isError: true` with text content and `structuredContent`
- Protocol-level failures (bad method, unknown tool, malformed request) still use JSON-RPC error objects
- `tools/list` supports cursor pagination:
  - request: `params.cursor`
  - response: `result.nextCursor`
- Tool entries include `title`, `$schema` (JSON Schema 2020-12) on `inputSchema`, and `outputSchema`
- Successful `tools/call` results include both `content[0].text` (serialized JSON) and `structuredContent`

### Prompts

- `prompts/list` returns three built-in prompts: `capture`, `forecast`, `review`
- Each prompt has a `title`; `capture.task` is marked `required: false`
- `prompts/get` returns prompt messages with `role: "user"` and `TextContent`
- `capture` prompt accepts an optional `task` argument; omitting it produces a prompt that asks the user for input
- Prompt content mirrors the cowork-plugin command definitions

### Logging

- Legacy: `logging/setLevel` sets the minimum log level; valid levels: `debug`, `info`, `notice`, `warning`, `error`, `critical`, `alert`, `emergency`
- Default session level: `warning`
- Log notifications sent via `notifications/message` with fields: `level`, `logger` (`"omnifocus-mcp"`), `data`
- Tool calls emit `info`-level log on entry, `debug` on success, `error` on failure — only when a level is in effect

### Sampling

- Server detects client sampling capability from `initialize` params (`capabilities.sampling`)
- `createSamplingMessage` sends `sampling/createMessage` requests to the client and reads the response synchronously from stdin
- 60-second timeout on sampling responses; other messages arriving during the wait are handled inline
- Deprecated in `2026-07-28`; not expanded on the modern path

## MCP Pagination Defaults

- Page size default: `100`
- Override with env var: `OF_MCP_TOOLS_PAGE_SIZE=<positive-int>`
- `tools/list` order is deterministic (`Tools.swift` `allTools` insertion order)

## CLI / launchd Compatibility

Current `omnifocus-cli` behavior:

- Install: `launchctl bootstrap gui/<uid> <plist>`
- Uninstall: `launchctl bootout gui/<uid>/<label>`
- Legacy fallback remains (`load` / `unload`) for older environments
- Socket path length is validated before bind/connect to avoid silent AF_UNIX truncation failures

## Runtime Environment Variables

- `OF_BACKEND=automation|jxa`
- `OF_APP_PATH=/Applications/OmniFocus.app`
- `OF_MCP_TOOLS_PAGE_SIZE=<int>`

## OmniFocus Compatibility

- Requires OmniFocus 4. Target current line: **4.8.13**.
- 4.7+ features: planned dates, mutually exclusive tags, repeat limits, `effectivePlannedDate` (4.7.1), URL `planned=` query (4.7.1).
- 4.8+: on-device `LanguageModel` (macOS 26 + Apple Intelligence). 4.8.4+ resolves Promises from `evaluate javascript`.
- Catch-up repeats are applied on `Task.RepetitionRule`, not as a task-level property.
