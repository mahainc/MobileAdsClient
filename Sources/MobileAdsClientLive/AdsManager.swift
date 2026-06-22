//
//  AdManager.swift
//  MobileAdsClient
//
//  Created by Thanh Hai Khong on 4/2/25.
//

#if canImport(UIKit)
    import GoogleMobileAds
    import MobileAdsClient

    final internal actor AdsManager {
        internal static let shared = AdsManager()

        private let openAdManager = OpenAdManager()
        private let interstitialAdManager = InterstitialAdManager()
        private let rewardedAdManager = RewardedAdManager()

        private init() {
            #if DEBUG
                MobileAds.shared.requestConfiguration.testDeviceIdentifiers = [
                    "74A6AE8F-C95C-44AF-8DF6-0F6918E7360D"
                ]
            #endif
        }
    }

    // MARK: - Public Methods

    extension AdsManager {
        internal func shouldShowAd(
            _ adType: MobileAdsClient.AdType,
            rules: [MobileAdsClient.AdRule],
            keywords: [String] = []
        ) async -> Bool {
            switch adType {
                case let .appOpen(adUnitID):
                    return await openAdManager.shouldShowAd(adUnitID, rules: rules, keywords: keywords)

                case let .interstitial(adUnitID):
                    return await interstitialAdManager.shouldShowAd(adUnitID, rules: rules, keywords: keywords)

                case let .rewarded(adUnitID):
                    return await rewardedAdManager.shouldShowAd(adUnitID, rules: rules, keywords: keywords)
            }
        }

        @MainActor
        internal func showAd(
            _ adType: MobileAdsClient.AdType,
            keywords: [String] = []
        ) async throws {
            guard let rootViewController = UIApplication.shared.topViewController() else {
                return
            }

            switch adType {
                case let .appOpen(adUnitID):
                    try await openAdManager.showAd(adUnitID, from: rootViewController, keywords: keywords)

                case let .interstitial(adUnitID):
                    try await interstitialAdManager.showAd(adUnitID, from: rootViewController, keywords: keywords)

                case let .rewarded(adUnitID):
                    try await rewardedAdManager.showAd(adUnitID, from: rootViewController, keywords: keywords)
            }

            debugPrint("👉 The \(adType.description) ad has been closed, proceeding with the next action!")
        }

        /// Presents the rewarded ad and returns whether the user earned the reward.
        /// Distinct from `showAd(.rewarded(_:))` which returns Void — the reward
        /// result is captured via `userDidEarnRewardHandler` inside
        /// `RewardedAdManager.showAndAwaitReward`.
        @MainActor
        internal func showRewardAd(
            _ adUnitID: String,
            keywords: [String] = []
        ) async -> Bool {
            guard let rootViewController = UIApplication.shared.topViewController() else {
                return false
            }
            return
                (try? await rewardedAdManager.showAndAwaitReward(adUnitID, from: rootViewController, keywords: keywords))
                ?? false
        }
    }
#endif
