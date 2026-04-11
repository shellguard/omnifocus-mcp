// JXA backend script composed from shared utilities + JXA-specific code.
// Source: Resources/jxa.js (embedded at build time via .embedInCode)
// The placeholder "// __SHARED_JS__" is replaced with shared.js contents at runtime.

let jxaScript: String = {
    guard let s = String(bytes: PackageResources.jxa_js, encoding: .utf8) else {
        fatalError("jxa.js is not valid UTF-8 — rebuild required")
    }
    return s.replacingOccurrences(of: "// __SHARED_JS__", with: jsSharedUtilities)
}()
