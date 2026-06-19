// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Archer",
    defaultLocalization: "zh-Hans",
    platforms: [
        // .v14 floor — `@Observable` macro requires Sonoma+. Dropping further
        // would mean reverting all session models to ObservableObject + @Published.
        .macOS(.v14)
    ],
    dependencies: [],
    targets: [
        // Thin executable: main.swift only. Everything else lives in ArcherKit so
        // tests can `@testable import` it (SPM doesn't allow importing executables).
        .executableTarget(
            name: "Archer",
            dependencies: ["ArcherKit"],
            path: "Sources/Archer"
        ),
        // Tiny stand-alone CLI invoked from Claude Code / Codex hooks. Reads
        // $ARCHER_SURFACE_ID from env, opens the unix socket the running app
        // owns, writes one JSON line, exits. Doesn't link ArcherKit on purpose
        // — keeps the binary fast and dependency-free.
        .executableTarget(
            name: "ArcherHook",
            dependencies: ["ArcherHookKit"],
            path: "Sources/ArcherHook"
        ),
        // Payload builders + stdin parsing extracted out of `main.swift` so
        // they're unit-testable without spawning a subprocess. Foundation /
        // Darwin only — must not depend on ArcherKit (would bloat the CLI).
        .target(
            name: "ArcherHookKit",
            path: "Sources/ArcherHookKit"
        ),
        .target(
            name: "ArcherKit",
            dependencies: [
                "GhosttyKit",
            ],
            path: "Sources/ArcherKit",
            resources: [
                .process("Resources"),
            ],
            linkerSettings: [
                // libghostty bundles C++ deps (glslang, spirv-cross, imgui)
                // and uses Metal for rendering; link the system frameworks.
                .linkedLibrary("c++"),
                .linkedFramework("Metal"),
                .linkedFramework("MetalKit"),
                .linkedFramework("CoreText"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("CoreVideo"),
                .linkedFramework("QuartzCore"),
                .linkedFramework("IOSurface"),
                // Text Input Services — libghostty uses TIS to read the active
                // keyboard layout. Pulled in implicitly by SwiftTerm before;
                // now declared directly.
                .linkedFramework("Carbon"),
            ]
        ),
        .binaryTarget(
            name: "GhosttyKit",
            // Run scripts/setup-libghostty.sh to populate this; not committed.
            path: "Vendor/GhosttyKit.xcframework"
        ),
        .testTarget(
            name: "ArcherKitTests",
            dependencies: ["ArcherKit"],
            path: "Tests/ArcherKitTests"
        ),
        .testTarget(
            name: "ArcherHookKitTests",
            dependencies: ["ArcherHookKit"],
            path: "Tests/ArcherHookKitTests"
        ),
    ]
)
