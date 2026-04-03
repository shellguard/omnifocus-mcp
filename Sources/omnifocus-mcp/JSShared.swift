// Shared JavaScript utility functions used by both JXA and OmniAutomation backends.
// Source: Resources/shared.js (embedded at build time via .embedInCode)

let jsSharedUtilities: String = String(bytes: PackageResources.shared_js, encoding: .utf8)!
