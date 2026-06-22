// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Quick_Drop",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "Quick_Drop",
            path: "Sources/Quick_Drop",
            resources: [
                .copy("AppIcon.icns"),
                .copy("AppIcon.png")
            ]
        )
    ]
)
