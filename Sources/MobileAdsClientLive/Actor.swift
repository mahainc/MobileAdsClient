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

        /// Presents `adType` and returns its `AdOutcome`. `.presented` for appOpen /
        /// interstitial / native; `.rewardEarned` / `.rewardNotEarned` for rewarded.
        /// Throws `AdError.adNotReady` uniformly when nothing could be presented.
        @MainActor
        internal func showAd(
            _ adType: MobileAdsClient.AdType,
            keywords: [String] = [],
            onComplete: MobileAdsClient.CompletionHandler? = nil
        ) async throws -> MobileAdsClient.AdOutcome {
            guard let rootViewController = UIApplication.shared.topViewController() else {
                throw MobileAdsClient.AdError.adNotReady
            }

            let onColdLoad = Self.makeColdLoadEmitter(for: adType)
            // A supplied handler takes over the post-dismiss preload decision, so the
            // managers skip their built-in auto-warm for this show.
            let suppress = onComplete != nil

            let outcome: MobileAdsClient.AdOutcome
            switch adType {
                case let .appOpen(adUnitID):
                    try await openAdManager.showAd(
                        adUnitID,
                        from: rootViewController,
                        keywords: keywords,
                        suppressAutoReload: suppress,
                        onColdLoad: onColdLoad
                    )
                    outcome = .presented

                case let .interstitial(adUnitID):
                    try await interstitialAdManager.showAd(
                        adUnitID,
                        from: rootViewController,
                        keywords: keywords,
                        suppressAutoReload: suppress,
                        onColdLoad: onColdLoad
                    )
                    outcome = .presented

                case let .rewarded(adUnitID):
                    // Route to the earn-capturing path (not the void showAd) so the
                    // outcome reflects whether the user earned the reward.
                    let earned = try await rewardedAdManager.showAndAwaitReward(
                        adUnitID,
                        from: rootViewController,
                        keywords: keywords,
                        suppressAutoReload: suppress,
                        onColdLoad: onColdLoad
                    )
                    outcome = earned ? .rewardEarned : .rewardNotEarned

                case let .nativeFullScreen(adUnitID):
                    // Native has its own pipeline (AdLoader + FullScreenNativeView), not
                    // BaseAdManager. `didShow` is false when the load / presentation
                    // failed — throw uniformly so native matches the other formats.
                    let didShow = await FullScreenNativePresenter.present(
                        adUnitID: adUnitID,
                        keywords: keywords,
                        onColdLoad: onColdLoad
                    )
                    guard didShow else {
                        throw MobileAdsClient.AdError.adNotReady
                    }
                    outcome = .presented
            }

            debugPrint("👉 The \(adType.description) ad has been closed, proceeding with the next action!")
            // Reached only after a real show + dismiss (a throw above skips this).
            await fireCompletion(onComplete, shown: adType)
            return outcome
        }

        /// Fires the caller's completion handler with a fresh preload snapshot, then
        /// returns immediately. No-op when no handler was supplied. The handler is a
        /// preload hook, so it runs in a detached task and does **not** block the
        /// `showFullScreenAd` caller — the snapshot is still captured now (at dismiss).
        private func fireCompletion(
            _ onComplete: MobileAdsClient.CompletionHandler?,
            shown adType: MobileAdsClient.AdType
        ) {
            guard let onComplete else { return }
            let context = MobileAdsClient.CompletionContext(shown: adType, status: preloadStatus())
            Task { await onComplete(context) }
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

        /// Point-in-time snapshot of available preloaded ads across both sources:
        /// Google Preloader bucket counts + keyword-aware pool variants, unioned over
        /// the three full-screen managers. Native has neither, so it never appears.
        internal func preloadStatus() -> MobileAdsClient.PreloadStatus {
            var google: [String: Int] = [:]
            var pool: [String: [MobileAdsClient.PreloadStatus.Variant]] = [:]

            for counts in [
                openAdManager.googleCountsByUnit(),
                interstitialAdManager.googleCountsByUnit(),
                rewardedAdManager.googleCountsByUnit(),
            ] {
                google.merge(counts) { _, new in new }
            }

            // `poolVariantsByUnit()` returns a differently-specialized
            // `AdPool<Ad>.VariantInfo` per manager, so these can't share an array —
            // fold each in turn. `foldPool` is generic over the info type; each call
            // site's concrete `VariantInfo` exposes `keywords` / `loadedAt`.
            func foldPool<Info>(
                _ variantsByUnit: [String: [Info]],
                _ toVariant: (Info) -> MobileAdsClient.PreloadStatus.Variant
            ) {
                for (unit, variants) in variantsByUnit where !variants.isEmpty {
                    pool[unit, default: []] += variants.map(toVariant)
                }
            }
            foldPool(openAdManager.poolVariantsByUnit()) {
                .init(keywords: $0.keywords, loadedAt: $0.loadedAt)
            }
            foldPool(interstitialAdManager.poolVariantsByUnit()) {
                .init(keywords: $0.keywords, loadedAt: $0.loadedAt)
            }
            foldPool(rewardedAdManager.poolVariantsByUnit()) {
                .init(keywords: $0.keywords, loadedAt: $0.loadedAt)
            }

            return MobileAdsClient.PreloadStatus(googleByUnit: google, poolByUnit: pool)
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
