// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "2dle",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "2dle", targets: ["Spindle"])],
    targets: [
        .executableTarget(name: "Spindle", path: "Sources/Spindle")
    ]
)
