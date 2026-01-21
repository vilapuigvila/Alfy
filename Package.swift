// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Alfy",
    platforms: [.iOS(.v17), .macOS(.v11)],
    products: [
        .library(name: "Alfy", targets: ["Alfy"])
    ],
    dependencies: [
        .package(url: "https://github.com/SDWebImage/SDWebImageSVGCoder.git", from: "1.8.0"),
        .package(url: "https://github.com/SDWebImage/SDWebImageSwiftUI.git", from: "3.1.0"),
        .package(url: "https://github.com/scinfu/SwiftSoup.git", from: "2.7.5"),
        .package(url: "https://github.com/onevcat/Kingfisher.git", from: "8.3.3"),
    ],
    targets: [
//        .target(name: "Alfy", path: "Sources"),
        .target(
            name: "Alfy",
            dependencies: [
                .product(name: "SDWebImageSVGCoder", package: "SDWebImageSVGCoder"),
                .product(name: "SDWebImageSwiftUI", package: "SDWebImageSwiftUI"),
                .product(name: "Kingfisher", package: "Kingfisher"),
                .product(name: "SwiftSoup", package: "SwiftSoup"),
            ]
        ),
        .testTarget(
            name: "Tests",
            dependencies: [
                "Alfy",
                "SDWebImageSVGCoder",
                "SDWebImageSwiftUI",
                "SwiftSoup",
                "Kingfisher",
            ],
            path: "Tests"
        )
    ]
)
