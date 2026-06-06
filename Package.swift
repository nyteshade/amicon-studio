// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "AmigaIconWriter",
    platforms: [.macOS(.v13)],
    products: [
        // Cross-platform core. Pure Foundation; builds & tests on macOS and Linux.
        .library(name: "AmigaIconKit", targets: ["AmigaIconKit"]),
        // Command-line writer. Image loading needs ImageIO, so effectively macOS.
        .executable(name: "amigaicon", targets: ["amigaicon"]),
        // SwiftUI front-end. macOS only.
        .executable(name: "AmigaIconWriterApp", targets: ["AmigaIconWriterApp"]),
    ],
    targets: [
        .target(name: "AmigaIconKit"),
        .executableTarget(name: "amigaicon", dependencies: ["AmigaIconKit"]),
        .executableTarget(name: "AmigaIconWriterApp", dependencies: ["AmigaIconKit"]),
        .testTarget(name: "AmigaIconKitTests", dependencies: ["AmigaIconKit"]),
    ]
)
