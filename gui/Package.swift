// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "TokenDashboard",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "TokenDashboard", targets: ["TokenDashboard"]),
    ],
    dependencies: [
        .package(url: "https://github.com/scinfu/SwiftSoup.git", from: "2.6.0"),
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.1.0"),
    ],
    targets: [
        .executableTarget(
            name: "TokenDashboard",
            dependencies: [
                .product(name: "SwiftSoup", package: "SwiftSoup"),
                .product(name: "Yams", package: "Yams"),
            ],
            path: "TokenDashboard"
        ),
        .testTarget(
            name: "TokenDashboardTests",
            dependencies: ["TokenDashboard"],
            path: "TokenDashboardTests"
        ),
    ]
)
