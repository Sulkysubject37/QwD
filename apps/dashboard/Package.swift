// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "QwDDashboard",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "CQwD"),
        .executableTarget(
            name: "QwDDashboard",
            dependencies: ["CQwD"],
            linkerSettings: [.unsafeFlags(["-L../../zig-out/lib", "-lqwd", "-Xlinker", "-rpath", "-Xlinker", "../../zig-out/lib"])]
        ),
    ]
)
