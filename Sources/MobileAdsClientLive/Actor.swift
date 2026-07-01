//
//  Actor.swift
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

                case .nativeFullScreen:
                    // Native loads on demand at show time — no pool/preload to gate
                    // readiness on, so readiness is just whether the rules pass.
                    return await rules.allRulesSatisfied()
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

            let onColdLoad = Self.makeColdLoadEmitter(for: adType)

            switch adType {
                case let .appOpen(adUnitID):
                    try await openAdManager.showAd(
                        adUnitID,
                        from: rootViewController,
                        keywords: keywords,
                        onColdLoad: onColdLoad
                    )

                case let .interstitial(adUnitID):
                    try await interstitialAdManager.showAd(
                        adUnitID,
                        from: rootViewController,
                        keywords: keywords,
                        onColdLoad: onColdLoad
                    )

                case let .rewarded(adUnitID):
                    try await rewardedAdManager.showAd(
                        adUnitID,
                        from: rootViewController,
                        keywords: keywords,
                        onColdLoad: onColdLoad
                    )

                case let .nativeFullScreen(adUnitID):
                    // Native has its own pipeline (AdLoader + FullScreenNativeView),
                    // not BaseAdManager — it always loads at show time, so it reports
                    // cold-load like any other fresh fetch.
                    await FullScreenNativePresenter.present(
                        adUnitID: adUnitID,
                        keywords: keywords,
                        onColdLoad: onColdLoad
                    )
            }

            debugPrint("👉 The \(adType.description) ad has been closed, proceeding with the next action!")
        }

        /// Builds the phase → `AdLoadState` bridge that broadcasts a show-time cold
        /// load for `adType` on the shared relay. Passed down the acquire chain;
        /// fires only on a fresh load, so cache/preload serves stay silent.
        nonisolated private static func makeColdLoadEmitter(
            for adType: MobileAdsClient.AdType
        ) -> @Sendable (AdLoadPhase) -> Void {
            { phase in
                switch phase {
                    case .started: AdLoadStateRelay.shared.emit(.loading(adType))
                    case .ready: AdLoadStateRelay.shared.emit(.ready(adType))
                    case .failed: AdLoadStateRelay.shared.emit(.failed(adType))
                }
            }
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
            let onColdLoad = Self.makeColdLoadEmitter(for: .rewarded(adUnitID))
            return
                (try? await rewardedAdManager.showAndAwaitReward(
                    adUnitID,
                    from: rootViewController,
                    keywords: keywords,
                    onColdLoad: onColdLoad
                )) ?? false
        }

        /// On-demand warm of the keyword-aware pool (Google-managed units no-op
        /// inside the manager). Replaces the old `preloadAd` → `shouldShowAd` warm.
        internal func warm(
            _ adType: MobileAdsClient.AdType,
            keywords: [String] = []
        ) async {
            switch adType {
                case let .appOpen(adUnitID):
                    await openAdManager.warm(adUnitID, keywords: keywords)

                case let .interstitial(adUnitID):
                    await interstitialAdManager.warm(adUnitID, keywords: keywords)

                case let .rewarded(adUnitID):
                    await rewardedAdManager.warm(adUnitID, keywords: keywords)

                case .nativeFullScreen:
                    // Native has no pool/preload buffer to warm — it loads on demand.
                    break
            }
        }

        /// Eagerly register units for Google's Preloader (keyword-less, SDK-buffered).
        /// The host calls this once after `MobileAdsBootstrap.start()`.
        internal func registerPreloads(
            _ adTypes: [MobileAdsClient.AdType],
            bufferSize: Int
        ) async {
            for adType in adTypes {
                switch adType {
                    case let .appOpen(adUnitID):
                        await openAdManager.register(adUnitID, bufferSize: bufferSize)

                    case let .interstitial(adUnitID):
                        await interstitialAdManager.register(adUnitID, bufferSize: bufferSize)

                    case let .rewarded(adUnitID):
                        await rewardedAdManager.register(adUnitID, bufferSize: bufferSize)

                    case .nativeFullScreen:
                        // Google's Preloader has no native support; skip.
                        break
                }
            }
        }

        /// Stop preloading and drop the buffer for the given units (show-rate lever).
        internal func stopPreloading(_ adTypes: [MobileAdsClient.AdType]) async {
            for adType in adTypes {
                switch adType {
                    case let .appOpen(adUnitID):
                        await openAdManager.stopPreloading(adUnitID)

                    case let .interstitial(adUnitID):
                        await interstitialAdManager.stopPreloading(adUnitID)

                    case let .rewarded(adUnitID):
                        await rewardedAdManager.stopPreloading(adUnitID)

                    case .nativeFullScreen:
                        // Nothing was preloaded for native; nothing to stop.
                        break
                }
            }
        }
    }
#endif
