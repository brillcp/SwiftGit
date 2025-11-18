// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SwiftGit",
    platforms: [
        .iOS(.v26),
        .macOS(.v10_15)
    ],
    products: [
        .library(
            name: "SwiftGit",
            targets: ["SwiftGit"]),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "SwiftGit",
            dependencies: [],
            path: "Sources"
        ),
        .testTarget(
            name: "SwiftGitTests",
            dependencies: ["SwiftGit"]),
    ],
    swiftLanguageModes: [.v6]
)
