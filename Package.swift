// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MuniPreclassement",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "MuniPreclassementCore", targets: ["MuniPreclassementCore"]),
        .executable(name: "muni-preclassement-cli", targets: ["MuniPreclassementCLI"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-testing.git", from: "0.7.0")
    ],
    targets: [
        .target(name: "MuniPreclassementCore"),
        .executableTarget(name: "MuniPreclassementCLI", dependencies: ["MuniPreclassementCore"]),
        .testTarget(
            name: "MuniPreclassementTests",
            dependencies: [
                "MuniPreclassementCore",
                .product(name: "Testing", package: "swift-testing")
            ]
        )
    ]
)
