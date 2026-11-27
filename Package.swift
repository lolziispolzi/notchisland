// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "NotchIsland",
    platforms: [.macOS(.v10_15)],
    targets: [
        .executableTarget(
            name: "NotchIsland",
            path: "Sources/NotchIsland",
            linkerSettings: [
                // ScreenCaptureKit only exists on macOS 12.3 and newer. Weak-link it so the
                // app still launches on older systems, where audio metering is turned off.
                .unsafeFlags(["-Xlinker", "-weak_framework", "-Xlinker", "ScreenCaptureKit"]),
            ]
        ),
        .testTarget(
            name: "NotchIslandTests",
            dependencies: ["NotchIsland"],
            path: "Tests/NotchIslandTests"
        ),
    ]
)
