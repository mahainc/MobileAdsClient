// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "MobileAdsClient",
    platforms: [
		.iOS(.v16), .macOS(.v13)
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
        .package(url: "https://DucManh98@bitbucket.org/innofyapp/ads-swift.git", branch: "feature/preload_ads"),
        .package(path: "../RemoteConfigClient"),
        .package(path: "../AdjustClient"),
        .package(path: "../AnalyticClient"),
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
                .product(name: "ads-swift", package: "ads-swift"),
                .product(name: "RemoteConfigClient", package: "RemoteConfigClient"),
                .product(name: "AdjustClient", package: "AdjustClient"),
                .product(name: "AnalyticClient", package: "AnalyticClient"),
                "MobileAdsClient",
            ]
        ),
        .target(
            name: "MobileAdsClientUI",
            dependencies: [
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
                .product(name: "GoogleMobileAds", package: "swift-package-manager-google-mobile-ads"),
				.product(name: "TCAInitializableReducer", package: "TCAInitializableReducer"),
                .product(name: "ads-swift", package: "ads-swift"),
                .product(name: "RemoteConfigClient", package: "RemoteConfigClient"),
                "NativeAdClient",
                "MobileAdsClient",
            ],
            resources: [
                .process("Resources/stars_3_5.png"),
                .process("Resources/stars_4.png"),
                .process("Resources/stars_4_5.png"),
                .process("Resources/stars_5.png"),
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

