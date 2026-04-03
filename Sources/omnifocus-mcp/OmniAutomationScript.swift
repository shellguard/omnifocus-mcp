// OmniAutomation backend script composed from shared utilities + OA-specific code.
// Source: Resources/omni_automation.js (embedded at build time via .embedInCode)
// The placeholder "// __SHARED_JS__" is replaced with shared.js contents at runtime.

let omniAutomationScript: String = String(bytes: PackageResources.omni_automation_js, encoding: .utf8)!
    .replacingOccurrences(of: "// __SHARED_JS__", with: jsSharedUtilities)
