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
            shouldShowFullScreenAd: { _, _, _ in true },
            showFullScreenAd: { adType, _, _, _ in
                if case .rewarded = adType { return .rewardEarned }
                return .presented
            },
            warmFullScreenAd: { _, _ in },
            loadStates: { AsyncStream { $0.finish() } },
            preloadStatus: { PreloadStatus() }
        )
    }()

    public static let previewValue: MobileAdsClient = {
        Self(
            shouldShowFullScreenAd: { _, _, _ in true },
            showFullScreenAd: { adType, _, _, _ in
                // Simulate ad display delay for previews
                try await Task.sleep(nanoseconds: 1_000_000_000)
                if case .rewarded = adType { return .rewardEarned }
                return .presented
            },
            warmFullScreenAd: { _, _ in },
            loadStates: { AsyncStream { $0.finish() } },
            preloadStatus: { PreloadStatus() }
        )
    }()
}

extension MobileAdsClient {
    /// All ads disabled — simulates premium user or Remote Config kill switch.
    public static let adsDisabled: MobileAdsClient = Self(
        shouldShowFullScreenAd: { _, _, _ in false },
        showFullScreenAd: { adType, _, _, _ in
            // Ads are off, but a rewarded ask still grants the reward so the user
            // isn't punished — mirror the old `showRewardedAd: true` behavior.
            if case .rewarded = adType { return .rewardEarned }
            return .presented
        },
        warmFullScreenAd: { _, _ in },
        loadStates: { AsyncStream { $0.finish() } },
        preloadStatus: { PreloadStatus() }
    )
}
