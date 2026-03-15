// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MuniPreclassement",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "MuniPreclassementCore", targets: ["MuniPreclassementCore"]),
        .library(name: "MuniPreclassementInterop", targets: ["MuniPreclassementInterop"]),
        .executable(name: "muni-preclassement-cli", targets: ["MuniPreclassementCLI"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-testing.git", from: "0.7.0"),
        .package(url: "https://github.com/Macthieu/OrchivisteKit.git", exact: "0.2.0")
    ],
    targets: [
        .target(name: "MuniPreclassementCore"),
        .target(
            name: "MuniPreclassementInterop",
            dependencies: [
                "MuniPreclassementCore",
                .product(name: "OrchivisteKitContracts", package: "OrchivisteKit")
            ]
        ),
        .executableTarget(
            name: "MuniPreclassementCLI",
            dependencies: [
                "MuniPreclassementInterop",
                .product(name: "OrchivisteKitContracts", package: "OrchivisteKit"),
                .product(name: "OrchivisteKitInterop", package: "OrchivisteKit")
            ]
        ),
        .testTarget(
            name: "MuniPreclassementTests",
            dependencies: [
                "MuniPreclassementCore",
                "MuniPreclassementInterop",
                .product(name: "OrchivisteKitContracts", package: "OrchivisteKit"),
                .product(name: "Testing", package: "swift-testing")
            ]
        )
    ]
)
