// OmniAutomation backend script composed from shared utilities + OA-specific code.
// Source: Resources/omni_automation.js (embedded at build time via .embedInCode)
// The placeholder "// __SHARED_JS__" is replaced with shared.js contents at runtime.

let omniAutomationScript: String = {
    guard let s = String(bytes: PackageResources.omni_automation_js, encoding: .utf8) else {
        fatalError("omni_automation.js is not valid UTF-8 — rebuild required")
    }
    return s.replacingOccurrences(of: "// __SHARED_JS__", with: jsSharedUtilities)
}()
