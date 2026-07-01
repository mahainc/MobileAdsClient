//
//  Live.swift
//  MobileAdsClient
//
//  Created by Thanh Hai Khong on 4/2/25.
//

#if canImport(UIKit)
    import AdRevenueClient
    import ComposableArchitecture
    import MobileAdsClient
    @preconcurrency import GoogleMobileAds

    extension MobileAdsClient: DependencyKey {
        public static let liveValue: Self = {
            return Self(
                installRevenueBridge: {
                    // No-op. Historically registered an ads_swift AdRevenueDelegate
                    // to mirror paid events into AdRevenueClient. With ads_swift
                    // removed, every format (appOpen / interstitial / rewarded /
                    // native) attaches its own `paidEventHandler` at load time via
                    // `BaseAdManager.attachPaidEventHandler` or
                    // `NativeAdManager.adLoader(_:didReceive:)` — there is no
                    // longer anything to bridge. Kept on the interface so
                    // `AdsBootstrap.installingRevenueBridge` still calls through
                    // without needing a phase rename.
                },
                shouldShowFullScreenAd: { adType, rules, keywords in
                    await AdsManager.shared.shouldShowAd(adType, rules: rules, keywords: keywords)
                },
                showFullScreenAd: { adType, keywords in
                    try await AdsManager.shared.showAd(adType, keywords: keywords)
                },
                warmFullScreenAd: { adType, keywords in
                    await AdsManager.shared.warm(adType, keywords: keywords)
                },
                registerPreloads: { adTypes, bufferSize in
                    await AdsManager.shared.registerPreloads(adTypes, bufferSize: bufferSize)
                },
                stopPreloading: { adTypes in
                    await AdsManager.shared.stopPreloading(adTypes)
                },
                showRewardedAd: { unitID, keywords in
                    await AdsManager.shared.showRewardAd(unitID, keywords: keywords)
                },
                loadStates: {
                    AdLoadStateRelay.shared.stream()
                }
            )
        }()
    }
#endif
