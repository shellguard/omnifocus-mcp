// JXA backend script composed from shared utilities + JXA-specific code.
// Source: Resources/jxa.js (embedded at build time via .embedInCode)
// The placeholder "// __SHARED_JS__" is replaced with shared.js contents at runtime.

let jxaScript: String = String(bytes: PackageResources.jxa_js, encoding: .utf8)!
    .replacingOccurrences(of: "// __SHARED_JS__", with: jsSharedUtilities)
