// Shared JavaScript utility functions used by both JXA and OmniAutomation backends.
// Source: Resources/shared.js (embedded at build time via .embedInCode)

let jsSharedUtilities: String = {
    guard let s = String(bytes: PackageResources.shared_js, encoding: .utf8) else {
        fatalError("shared.js is not valid UTF-8 — rebuild required")
    }
    return s
}()
