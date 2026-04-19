# Protocol And Compatibility

## MCP Behavior

Current server behavior in `MCPServer.swift`:

- Supported protocol versions: `2025-11-25`, `2025-06-18`, `2024-11-05`
- `initialize` negotiates version: uses requested version if supported, otherwise falls back to latest supported
- Accepts both lifecycle notifications:
  - `initialized`
  - `notifications/initialized`
- `tools/call` execution failures return `result.isError: true` with text content
- Protocol-level failures (bad method, unknown tool, malformed request) still use JSON-RPC error objects
- `tools/list` supports cursor pagination:
  - request: `params.cursor`
  - response: `result.nextCursor`

### Prompts

- `prompts/list` returns three built-in prompts: `capture`, `forecast`, `review`
- `prompts/get` returns prompt messages with `role: "user"` and `TextContent`
- `capture` prompt accepts an optional `task` argument; omitting it produces a prompt that asks the user for input
- Prompt content mirrors the cowork-plugin command definitions

### Logging

- `logging/setLevel` sets the minimum log level; valid levels: `debug`, `info`, `notice`, `warning`, `error`, `critical`, `alert`, `emergency`
- Default level: `warning`
- Log notifications sent via `notifications/message` with fields: `level`, `logger` (`"omnifocus-mcp"`), `data`
- Tool calls emit `info`-level log on entry, `debug` on success, `error` on failure

### Sampling

- Server detects client sampling capability from `initialize` params (`capabilities.sampling`)
- `createSamplingMessage` sends `sampling/createMessage` requests to the client and reads the response synchronously from stdin
- 60-second timeout on sampling responses; other messages arriving during the wait are handled inline

## MCP Pagination Defaults

- Page size default: `100`
- Override with env var: `OF_MCP_TOOLS_PAGE_SIZE=<positive-int>`

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
