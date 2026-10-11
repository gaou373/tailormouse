// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TailorMouse",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "TailorMouse", targets: ["TailorMouse"])],
    targets: [
        .target(name: "TailorMouseCore"),
        .executableTarget(name: "TailorMouse", dependencies: ["TailorMouseCore"]),
        .testTarget(name: "TailorMouseCoreTests", dependencies: ["TailorMouseCore"])
    ]
)
