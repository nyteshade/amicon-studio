// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "AmigaIconWriter",
    platforms: [.macOS(.v13)],
    products: [
        // The reusable core: the entire Amiga .info create / encode / decode
        // pipeline. Pure Foundation, zero platform dependencies — builds and
        // tests on macOS and Linux, and is the library to depend on elsewhere.
        .library(name: "AmigaIconKit", targets: ["AmigaIconKit"]),
        // Optional Apple-only convenience layer: load/save RGBAImage via ImageIO
        // (PNG/JPEG/TIFF/HEIC…). Depend on this only if you want file loading.
        .library(name: "AmigaIconImageIO", targets: ["AmigaIconImageIO"]),
        // Command-line writer. Uses ImageIO loading, so effectively macOS.
        .executable(name: "amigaicon", targets: ["amigaicon"]),
        // SwiftUI front-end. macOS only.
        .executable(name: "AmigaIconWriterApp", targets: ["AmigaIconWriterApp"]),
    ],
    targets: [
        .target(name: "AmigaIconKit"),
        .target(name: "AmigaIconImageIO", dependencies: ["AmigaIconKit"]),
        .executableTarget(name: "amigaicon", dependencies: ["AmigaIconKit", "AmigaIconImageIO"]),
        .executableTarget(name: "AmigaIconWriterApp", dependencies: ["AmigaIconKit", "AmigaIconImageIO"]),
        .testTarget(name: "AmigaIconKitTests", dependencies: ["AmigaIconKit"]),
    ]
)
