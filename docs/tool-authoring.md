# Tool Authoring Guide

## Add A New Tool

1. Add tool schema/metadata in `Sources/OmniFocusCore/Tools.swift`.
2. Implement action in `Resources/jxa.js` (or explicitly return unsupported behavior).
3. Implement action in `Resources/omni_automation.js` (or explicitly return unsupported behavior).
4. Ensure action naming matches tool dispatch (`omnifocus_<action>` -> `<action>`).
5. If shared logic is generic, put it in `Resources/shared.js`.
6. Build and run tests:
   - `swift build -c release`
   - `./scripts/test.sh --no-build`
   - `./scripts/test_live.sh --no-build` (when OmniFocus is running)

## Compatibility Rules

- Keep behavior parity across JXA and Omni Automation unless API limitations require divergence.
- Return consistent JSON shapes from both backends.
- Prefer non-destructive defaults for power/eval operations.

## Testing Expectations

- Add protocol-level assertions to `scripts/test.sh` for new MCP-visible behavior.
- Add live assertions to `scripts/test_live.sh` only when behavior requires OmniFocus runtime validation.
