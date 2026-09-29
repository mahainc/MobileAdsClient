// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

/// The `Funnel` trait's name, shared by its declaration below and by every product
/// condition that gates on it. The matching `#if Funnel` in the conformer cannot
/// reference this — a compiler condition is not a Swift expression — but these two
/// manifest-level uses can, and a typo in either would silently stop gating.
let funnelTrait = "Funnel"

let package = Package(
    name: "MobileAdsClient",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .singleTargetLibrary("MobileAdsClient"),
        .singleTargetLibrary("MobileAdsClientLive"),
        .singleTargetLibrary("MobileAdsClientUI"),
        .singleTargetLibrary("NativeAdClient"),
        .singleTargetLibrary("NativeAdClientLive"),
    ],
    // The funnel conformer is opt-in. A consumer that never touches
    // `FunnelClient.Ad.Providing` should not pay for FunnelClient — and the
    // transitive flow-kit + LogClient graph behind it — just to show an ad.
    // `#if canImport(FunnelClient)` cannot do this: it is evaluated after
    // resolution, so the dependency is already fetched and built by the time the
    // compiler sees it. A trait gates the edge itself.
    //
    // Off by default, so adding this package never widens a graph by surprise:
    //   .package(url: "…/MobileAdsClient.git", from: "3.2.0")                  // no funnel
    //   .package(url: "…/MobileAdsClient.git", from: "3.2.0", traits: ["Funnel"])
    //
    // Note the trait does NOT remove FunnelClient from a consumer's graph on its
    // own while AdRevenueClient's published versions still depend on it
    // unconditionally — see the AdRevenueClient entry below.
    traits: [
        .default(enabledTraits: []),
        Trait(
            name: funnelTrait,
            description: "Conform MobileAdsClient to FunnelClient's Ad port."
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/pointfreeco/swift-composable-architecture.git", from: "1.25.5"),
        .package(url: "https://github.com/googleads/swift-package-manager-google-mobile-ads.git", from: "13.4.0"),
        .package(url: "https://github.com/mahainc/TCAInitializableReducer.git", from: "0.1.0"),
        // AdRevenueClient's published versions depend on FunnelClient unconditionally,
        // so FunnelClient still reaches the graph through here with the `Funnel` trait
        // off. Only its plain `publish` API is used — not `FunnelClient.AdRevenue.Providing`
        // — so once AdRevenueClient gates its own conformer behind a trait, this edge
        // does NOT need `traits: ["Funnel"]` propagated to it.
        .package(url: "https://github.com/mahainc/AdRevenueClient.git", from: "4.0.3"),
        .package(url: "https://github.com/mahainc/FunnelClient.git", from: "9.0.0"),
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
        // The only target that knows FunnelClient exists, and only when the
        // `Funnel` trait is on. Everything else here — ComposableArchitecture,
        // GoogleMobileAds, AdRevenueClient — is what this package is FOR, and stays
        // unconditional.
        .target(
            name: "MobileAdsClientLive",
            dependencies: [
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
                .product(name: "GoogleMobileAds", package: "swift-package-manager-google-mobile-ads"),
                .product(name: "AdRevenueClient", package: "AdRevenueClient"),
                .product(
                    name: "FunnelClient",
                    package: "FunnelClient",
                    condition: .when(traits: [funnelTrait])
                ),
                "MobileAdsClient",
                "MobileAdsClientUI",
                "NativeAdClient",
                "NativeAdClientLive",
            ],
            swiftSettings: [
                // Gates the Google Preloader path, which imports the Beta /
                // `GoogleMobileAds_Private` module (the Preloader `*_Beta.h`
                // headers are NOT in the stable public umbrella in SDK 13.5.0).
                // Flip this OFF (delete the define) if a future SDK drops or
                // changes that module — the hand-rolled pool (TTL + retry +
                // keyword variants) keeps working on stable public API alone, and
                // `BaseAdManager` falls through to it everywhere.
                .define("MOBILEADS_GOOGLE_PRELOAD")
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
                .process("Resources")
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
    ]
)

extension Product {
    static func singleTargetLibrary(_ name: String) -> Product {
        .library(name: name, targets: [name])
    }
}
