// swift-tools-version:5.9
import Foundation
import PackageDescription

// The Rust core is built by scripts/build-macos.sh into core/target/release.
// Resolve it relative to this manifest so the package stays relocatable.
let packageDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().path
let coreLibDir = packageDir + "/../../../core/target/release"

let package = Package(
    name: "SonyCompanion",
    // Liquid Glass is available from macOS 26; the UI is built on it directly,
    // so there is no reason to carry a fallback path for older systems.
    platforms: [.macOS("26.0")],
    products: [
        .executable(name: "sonyctl", targets: ["sonyctl"]),
        .executable(name: "SonyCompanionApp", targets: ["SonyCompanionApp"]),
        .library(name: "MDRKit", targets: ["MDRKit"]),
    ],
    targets: [
        // C shim that exposes the Rust engine's header to Swift.
        .target(
            name: "CSonyMDR",
            path: "Sources/CSonyMDR",
            linkerSettings: [
                .unsafeFlags(["-L", coreLibDir, "-lmdr_ffi"])
            ]
        ),
        // Shared transport + engine wrapper used by both the CLI and the app.
        .target(
            name: "MDRKit",
            dependencies: ["CSonyMDR"],
            path: "Sources/MDRKit",
            linkerSettings: [
                .linkedFramework("IOBluetooth"),
                .linkedFramework("Foundation"),
            ]
        ),
        // Scriptable harness: the thing you can run in CI and diff.
        .executableTarget(
            name: "sonyctl",
            dependencies: ["MDRKit"],
            path: "Sources/sonyctl",
            linkerSettings: [
                .linkedFramework("IOBluetooth"),
                .linkedFramework("Foundation"),
            ]
        ),
        // The native app.
        .executableTarget(
            name: "SonyCompanionApp",
            dependencies: ["MDRKit"],
            path: "Sources/SonyCompanionApp",
            linkerSettings: [
                .linkedFramework("IOBluetooth"),
            ]
        ),
    ]
)
