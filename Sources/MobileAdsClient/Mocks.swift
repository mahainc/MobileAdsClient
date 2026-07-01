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
        Self(
            installRevenueBridge: {},
            shouldShowFullScreenAd: { _, _, _ in true },
            showFullScreenAd: { _, _ in },
            warmFullScreenAd: { _, _ in },
            registerPreloads: { _, _ in },
            stopPreloading: { _ in },
            showRewardedAd: { _, _ in true },
            showNativeFullScreen: { _, _ in }
        )
    }()

    public static let previewValue: MobileAdsClient = {
        Self(
            installRevenueBridge: {},
            shouldShowFullScreenAd: { _, _, _ in true },
            showFullScreenAd: { _, _ in
                // Simulate ad display delay for previews
                try await Task.sleep(nanoseconds: 1_000_000_000)
            },
            warmFullScreenAd: { _, _ in },
            registerPreloads: { _, _ in },
            stopPreloading: { _ in },
            showRewardedAd: { _, _ in true },
            showNativeFullScreen: { _, _ in
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        )
    }()
}

extension MobileAdsClient {
    /// All ads disabled — simulates premium user or Remote Config kill switch.
    public static let adsDisabled: MobileAdsClient = Self(
        installRevenueBridge: {},
        shouldShowFullScreenAd: { _, _, _ in false },
        showFullScreenAd: { _, _ in },
        warmFullScreenAd: { _, _ in },
        registerPreloads: { _, _ in },
        stopPreloading: { _ in },
        showRewardedAd: { _, _ in true },  // user still gets the reward
        showNativeFullScreen: { _, _ in }
    )
}
