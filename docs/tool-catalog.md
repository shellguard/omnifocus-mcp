# Tool Catalog Reference

## Source Of Truth

- Runtime list: MCP `tools/list`
- Static definitions: `Sources/OmniFocusCore/Tools.swift`
- User-facing grouped list: `README.md` (Tool Catalog section)

## Quick Inspection

- Build server: `swift build -c release`
- Query list from a client, or inspect static definitions directly.

## Notes

- Tool names are `omnifocus_*`.
- Catalog size: **90 tools**.
- `tools/list` emits `name`, `title`, `description`, `inputSchema` (JSON Schema 2020-12 `$schema`), `outputSchema`, and `annotations`.
- Catalog is paginated via `cursor` / `nextCursor` and is returned in deterministic `allTools` order.
- `tools/call` returns serialized JSON in `content[0].text` plus `structuredContent`.
