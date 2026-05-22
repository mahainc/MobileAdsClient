// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "MobileAdsClient",
    defaultLocalization: "en",
    platforms: [
		.iOS(.v16),
		.macOS(.v13),
    ],
    products: [
        .singleTargetLibrary("MobileAdsClient"),
        .singleTargetLibrary("MobileAdsClientLive"),
        .singleTargetLibrary("MobileAdsClientUI"),
        .singleTargetLibrary("NativeAdClient"),
        .singleTargetLibrary("NativeAdClientLive"),
    ],
    dependencies: [
        .package(url: "https://github.com/pointfreeco/swift-composable-architecture.git", branch: "main"),
        .package(url: "https://github.com/googleads/swift-package-manager-google-mobile-ads.git", branch: "main"),
        .package(url: "https://github.com/ThanhHaiKhong/TCAInitializableReducer.git", branch: "master"),
        .package(url: "https://github.com/mahainc/AdRevenueClient.git", branch: "master"),
    ],
    targets: [
        .target(
            name: "MobileAdsClient",
            dependencies: [
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
                .product(name: "GoogleMobileAds", package: "swift-package-manager-google-mobile-ads"),
				.product(name: "TCAInitializableReducer", package: "TCAInitializableReducer"),
            ]
        ),
        .target(
            name: "MobileAdsClientLive",
            dependencies: [
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
                .product(name: "GoogleMobileAds", package: "swift-package-manager-google-mobile-ads"),
                .product(name: "AdRevenueClient", package: "AdRevenueClient"),
                "MobileAdsClient",
                "MobileAdsClientUI",
                "NativeAdClient",
            ]
        ),
        .target(
            name: "MobileAdsClientUI",
            dependencies: [
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
                .product(name: "GoogleMobileAds", package: "swift-package-manager-google-mobile-ads"),
				.product(name: "TCAInitializableReducer", package: "TCAInitializableReducer"),
                "NativeAdClient",
                "MobileAdsClient",
            ],
            resources: [
                .process("Resources"),
            ]
        ),
        .target(
            name: "NativeAdClient",
            dependencies: [
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
                .product(name: "GoogleMobileAds", package: "swift-package-manager-google-mobile-ads"),
				.product(name: "TCAInitializableReducer", package: "TCAInitializableReducer"),
            ]
        ),
        .target(
            name: "NativeAdClientLive",
            dependencies: [
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
                .product(name: "GoogleMobileAds", package: "swift-package-manager-google-mobile-ads"),
                .product(name: "AdRevenueClient", package: "AdRevenueClient"),
                "NativeAdClient",
            ]
        ),
        .testTarget(
            name: "MobileAdsClientTests",
            dependencies: ["MobileAdsClient", "MobileAdsClientUI"]
        ),
    ]
)

extension Product {
    static func singleTargetLibrary(_ name: String) -> Product {
        .library(name: name, targets: [name])
    }
}

