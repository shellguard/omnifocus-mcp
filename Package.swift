// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "omnifocus-mcp",
    targets: [
        .executableTarget(
            name: "omnifocus-mcp",
            resources: [
                .embedInCode("Resources/shared.js"),
                .embedInCode("Resources/jxa.js"),
                .embedInCode("Resources/omni_automation.js")
            ]
        ),
    ]
)
