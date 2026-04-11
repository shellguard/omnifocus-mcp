// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "omnifocus-mcp",
    targets: [
        .target(
            name: "OmniFocusCore",
            resources: [
                .embedInCode("Resources/shared.js"),
                .embedInCode("Resources/jxa.js"),
                .embedInCode("Resources/omni_automation.js")
            ]
        ),
        .executableTarget(
            name: "omnifocus-mcp",
            dependencies: ["OmniFocusCore"]
        ),
        .executableTarget(
            name: "omnifocus-cli",
            dependencies: ["OmniFocusCore"]
        ),
    ]
)
