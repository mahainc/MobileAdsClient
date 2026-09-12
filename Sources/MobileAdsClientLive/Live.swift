//
//  Live.swift
//  MobileAdsClient
//
//  Created by Thanh Hai Khong on 4/2/25.
//

#if canImport(UIKit)
import ComposableArchitecture
import MobileAdsClient
@preconcurrency import GoogleMobileAds

extension MobileAdsClient: DependencyKey {
    public static let liveValue: Self = {
        return Self(
            shouldShowFullScreenAd: { adType, rules, keywords in
                await AdsManager.shared.shouldShowAd(adType, rules: rules, keywords: keywords)
            },
            showFullScreenAd: { adType, keywords, requester, onComplete in
                try await AdsManager.shared.showAd(
                    adType,
                    keywords: keywords,
                    featureID: requester.featureID,
                    slotRef: requester.slotRef,
                    onComplete: onComplete
                )
            },
            warmFullScreenAd: { adType, keywords in
                await AdsManager.shared.warm(adType, keywords: keywords)
            },
            loadStates: {
                AdLoadStateRelay.shared.stream()
            },
            preloadStatus: {
                await AdsManager.shared.preloadStatus()
            }
        )
    }()
}
#endif
