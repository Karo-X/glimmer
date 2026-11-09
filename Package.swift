// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Glimmer",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "GlimmerCore"),
        .executableTarget(
            name: "Glimmer",
            dependencies: ["GlimmerCore"],
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .testTarget(name: "GlimmerCoreTests", dependencies: ["GlimmerCore"]),
    ]
)
