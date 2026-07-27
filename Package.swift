// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "VTISOCreatorKit",
    platforms: [
        .iOS(.v15),
        .macOS(.v12),
        .tvOS(.v15),
        .watchOS(.v8)
    ],
    products: [
        .library(name: "VTISOCreatorKit", targets: ["VTISOCreatorKit"])
    ],
    dependencies: [
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", from: "0.9.19")
    ],
    targets: [
        .target(
            name: "VTISOCreatorKit",
            dependencies: ["ZIPFoundation"]
        ),
        .testTarget(
            name: "VTISOCreatorKitTests",
            dependencies: ["VTISOCreatorKit"]
        )
    ]
)
