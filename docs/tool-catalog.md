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
- Input schema and annotations are emitted by `tools/list`.
- Catalog is paginated via `cursor` / `nextCursor`.
