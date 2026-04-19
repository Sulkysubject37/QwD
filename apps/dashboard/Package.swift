// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "QwDDashboard",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "QwDDashboard",
            dependencies: ["CQwD", "libqwd"],
            linkerSettings: [
                .linkedLibrary("deflate"),
                .unsafeFlags(["-L/opt/homebrew/lib"])
            ]
        ),
        .target(
            name: "CQwD",
            path: "Sources/CQwD",
            publicHeadersPath: "."
        ),
        .binaryTarget(
            name: "libqwd",
            path: "Frameworks/QwD.xcframework"
        )
    ]
)
