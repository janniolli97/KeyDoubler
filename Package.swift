// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "KeyDoubler",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "KeyDoublerCore", path: "Sources/KeyDoublerCore"),
        .executableTarget(name: "KeyDoubler", dependencies: ["KeyDoublerCore"], path: "Sources/KeyDoubler"),
        .executableTarget(name: "akcli", dependencies: ["KeyDoublerCore"], path: "Sources/akcli"),
    ]
)
