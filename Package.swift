// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "CodexIsland",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "CodexIslandApp", targets: ["CodexIslandApp"])
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-testing.git", exact: "6.2.4")
    ],
    targets: [
        .target(
            name: "CodexIslandCore",
            path: "Sources/CodexIslandCore",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("UserNotifications"),
                .linkedLibrary("sqlite3"),
            ]
        ),
        .executableTarget(
            name: "CodexIslandApp",
            dependencies: ["CodexIslandCore"],
            path: "Sources/CodexIslandApp",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("UserNotifications"),
            ]
        ),
        .testTarget(
            name: "CodexIslandAppTests",
            dependencies: [
                "CodexIslandCore",
                .product(name: "Testing", package: "swift-testing"),
            ],
            path: "Tests/CodexIslandAppTests"
        ),
    ]
)
