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
            shouldShowAd: { adType, rules in
                await AdsManager.shared.shouldShowAd(adType, rules: rules)
            },
            showAd: { adType in
                try await AdsManager.shared.showAd(adType)
            },
            preloadAd: { adType in
                // `shouldShowAd` auto-loads into the BaseAdManager cache when
                // nothing is resident — exactly the "warm the slot" we want.
                // The returned Bool is ignored at preload time.
                _ = await AdsManager.shared.shouldShowAd(adType, rules: [])
            },
            showRewardedAd: { unitID in
                await AdsManager.shared.showRewardAd(unitID)
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
            showNativeFullScreen: { adUnitID in
                await FullScreenNativePresenter.present(adUnitID: adUnitID)
            }
        )
    }()
}
#endif
