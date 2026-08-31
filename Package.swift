// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "DSHDesktop",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(name: "DSH", targets: ["DSHDesktopApp"]),
    ],
    targets: [
        .target(name: "DSHDesktopCore"),
        .executableTarget(
            name: "DSHDesktopApp",
            dependencies: ["DSHDesktopCore"]
        ),
        .executableTarget(
            name: "DSHDesktopCoreChecks",
            dependencies: ["DSHDesktopCore"],
            path: "Checks/DSHDesktopCoreChecks"
        ),
    ],
    swiftLanguageVersions: [.v5]
)
