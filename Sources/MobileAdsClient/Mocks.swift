//
//  Mocks.swift
//  MobileAdsClient
//
//  Created by Thanh Hai Khong on 4/2/25.
//

import ComposableArchitecture

extension DependencyValues {
	public var mobileAdsClient: MobileAdsClient {
		get { self[MobileAdsClient.self] }
		set { self[MobileAdsClient.self] = newValue }
	}
}

extension MobileAdsClient: TestDependencyKey {
    public static let testValue: MobileAdsClient = {
        return Self(
            requestTrackingAuthorizationIfNeeded: { },
            shouldShowAd: { _, _ in true },
            showAd: { _ in },
            preloadAd: { _ in },
            showRewardedAd: { _ in true },
            installRevenueBridge: { },
            showNativeFullScreen: { _ in }
        )
    }()

    public static let previewValue: MobileAdsClient = {
        return Self(
            requestTrackingAuthorizationIfNeeded: { },
            shouldShowAd: { _, _ in true },
            showAd: { _ in
                // Simulate ad display delay for previews
                try await Task.sleep(nanoseconds: 1_000_000_000)
            },
            preloadAd: { _ in },
            showRewardedAd: { _ in true },
            installRevenueBridge: { },
            showNativeFullScreen: { _ in
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        )
    }()
}

extension MobileAdsClient {
    /// All ads disabled — simulates premium user or Remote Config kill switch.
    public static let adsDisabled: MobileAdsClient = Self(
        requestTrackingAuthorizationIfNeeded: { },
        shouldShowAd: { _, _ in false },
        showAd: { _ in },
        preloadAd: { _ in },
        showRewardedAd: { _ in true }, // user still gets the reward
        installRevenueBridge: { },
        showNativeFullScreen: { _ in }
    )
}
