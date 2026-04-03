// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LunaPad",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "LunaPad",
            path: "Sources",
            linkerSettings: [.linkedFramework("WebKit")]
        )
    ]
)
