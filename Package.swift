// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "RightMenu",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "RightMenuCore", targets: ["RightMenuCore"]),
        .executable(name: "rightmenu-cli", targets: ["RightMenuCLI"]),
        .executable(name: "rightmenu-smoke-tests", targets: ["RightMenuSmokeTests"])
    ],
    targets: [
        .target(name: "RightMenuCore"),
        .executableTarget(
            name: "RightMenuCLI",
            dependencies: ["RightMenuCore"]
        ),
        .executableTarget(
            name: "RightMenuSmokeTests",
            dependencies: ["RightMenuCore"]
        )
    ]
)
