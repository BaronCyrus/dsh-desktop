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
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.9.6"),
    ],
    targets: [
        .target(name: "DSHDesktopCore"),
        .executableTarget(
            name: "DSHDesktopApp",
            dependencies: [
                "DSHDesktopCore",
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-rpath",
                    "-Xlinker", "@executable_path/../Frameworks",
                ]),
            ]
        ),
        .executableTarget(
            name: "DSHDesktopCoreChecks",
            dependencies: ["DSHDesktopCore"],
            path: "Checks/DSHDesktopCoreChecks"
        ),
    ],
    swiftLanguageVersions: [.v5]
)
