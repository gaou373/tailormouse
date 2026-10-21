// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TailorMouse",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "TailorMouse", targets: ["TailorMouse"])],
    dependencies: [.package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.9.6")],
    targets: [
        .target(name: "TailorMouseCore"),
        .target(name: "NativeHIDBridge", linkerSettings: [.linkedFramework("IOKit")]),
        .executableTarget(name: "TailorMouse", dependencies: ["TailorMouseCore", "NativeHIDBridge", .product(name: "Sparkle", package: "Sparkle")], linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]),
        .testTarget(name: "TailorMouseCoreTests", dependencies: ["TailorMouseCore"])
    ]
)
