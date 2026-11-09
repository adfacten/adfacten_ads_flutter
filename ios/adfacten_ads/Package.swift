// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "adfacten_ads",
    platforms: [
        .iOS("15.0")
    ],
    products: [
        .library(name: "adfacten-ads", targets: ["adfacten_ads"])
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework"),
        .package(url: "https://github.com/adfacten/adfacten-ios-sdk.git", from: "1.0.0"),
    ],
    targets: [
        .target(
            name: "adfacten_ads",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework"),
                .product(name: "AdfactenAds", package: "adfacten-ios-sdk"),
            ]
        )
    ]
)
