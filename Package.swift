// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Bulchimbeon",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "Bulchimbeon", targets: ["Bulchimbeon"]),
    ],
    targets: [
        .target(name: "BulchimbeonCore"),
        .executableTarget(
            name: "Bulchimbeon",
            dependencies: ["BulchimbeonCore"],
            linkerSettings: [.linkedFramework("IOKit"), .linkedFramework("ServiceManagement")]
        ),
        .executableTarget(name: "IconGen", dependencies: ["BulchimbeonCore"]),
        .testTarget(name: "BulchimbeonCoreTests", dependencies: ["BulchimbeonCore"]),
    ]
)
