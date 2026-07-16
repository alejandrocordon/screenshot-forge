// swift-tools-version: 5.9
import PackageDescription

// ForgeCore — reusable, UI-free engine for cropping screenshots and app
// preview videos to the App Store sizes. The geometry is pure Swift (tested on
// any platform); the image/video croppers use CoreGraphics / AVFoundation and
// therefore only compile on Apple platforms.
let package = Package(
    name: "ForgeCore",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "ForgeCore", targets: ["ForgeCore"]),
    ],
    targets: [
        .target(name: "ForgeCore"),
        .testTarget(name: "ForgeCoreTests", dependencies: ["ForgeCore"]),
    ]
)
