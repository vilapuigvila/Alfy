// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Alfy",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "Alfy", targets: ["Alfy"])
    ],
    targets: [
        .target(name: "Alfy", path: "Sources"),
        .testTarget(
            name: "Tests",
            dependencies: ["Alfy"],
            path: "Tests"
        )
    ]
)
