// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "AutoKey3D",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "AutoKeyCore", path: "Sources/AutoKeyCore"),
        .executableTarget(name: "AutoKey3D", dependencies: ["AutoKeyCore"], path: "Sources/AutoKey3D"),
        .executableTarget(name: "akcli", dependencies: ["AutoKeyCore"], path: "Sources/akcli"),
    ]
)
