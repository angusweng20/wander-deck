// swift-tools-version:5.10
// 漫遊簡報 Mac App。用 swift build 編譯；打包成 .app 用 scripts/package_app.sh。
import PackageDescription

let package = Package(
    name: "WanderDeck",
    defaultLocalization: "zh-Hant",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "WanderDeck", targets: ["WanderDeckApp"]),
        .executable(name: "wander", targets: ["wander"]),
    ],
    targets: [
        .target(name: "WanderCore"),
        .executableTarget(name: "wander", dependencies: ["WanderCore"]),
        .executableTarget(name: "WanderDeckApp", dependencies: ["WanderCore"]),
        .testTarget(name: "WanderCoreTests", dependencies: ["WanderCore"]),
    ]
)
