//
//  Live.swift
//  MobileAdsClient
//
//  Created by Thanh Hai Khong on 4/2/25.
//

#if canImport(UIKit)
    import AdRevenueClient
    import AppTrackingTransparency
    import ComposableArchitecture
    import MobileAdsClient
    @preconcurrency import GoogleMobileAds

    extension MobileAdsClient: DependencyKey {
        public static let liveValue: Self = {
            return Self(
                requestTrackingAuthorizationIfNeeded: {
                    guard ATTrackingManager.trackingAuthorizationStatus == .notDetermined else {
                        return
                    }

                    await withCheckedContinuation { continuation in
                        ATTrackingManager.requestTrackingAuthorization { _ in
                            continuation.resume(returning: ())
                        }
                    }
                },
                shouldShowAd: { adType, rules, keywords in
                    await AdsManager.shared.shouldShowAd(adType, rules: rules, keywords: keywords)
                },
                showAd: { adType, keywords in
                    try await AdsManager.shared.showAd(adType, keywords: keywords)
                },
                preloadAd: { adType, keywords in
                    // `shouldShowAd` auto-loads into the BaseAdManager cache when
                    // nothing is resident (or re-loads when the keywords changed) —
                    // exactly the "warm the slot" we want. The Bool is ignored here.
                    _ = await AdsManager.shared.shouldShowAd(adType, rules: [], keywords: keywords)
                },
                showRewardedAd: { unitID, keywords in
                    await AdsManager.shared.showRewardAd(unitID, keywords: keywords)
                },
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
                showNativeFullScreen: { adUnitID, keywords in
                    await FullScreenNativePresenter.present(adUnitID: adUnitID, keywords: keywords)
                }
            )
        }()
    }
#endif
