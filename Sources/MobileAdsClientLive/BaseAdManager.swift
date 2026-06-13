//
//  BaseAdManager.swift
//  MobileAdsClient
//
//  Created by Thanh Hai Khong on 11/6/25.
//

#if canImport(UIKit)
    import AdRevenueClient
    import ComposableArchitecture
    import GoogleMobileAds
    import MobileAdsClient

    /// Ad types that expose `paidEventHandler`. `InterstitialAd`, `AppOpenAd`, and
    /// `RewardedAd` all match this shape; used by `BaseAdManager` to attach a shared
    /// revenue publisher at load time without subclass-specific glue.
    protocol PaidEventCapable: AnyObject {
        var paidEventHandler: ((AdValue) -> Void)? { get set }
    }

    extension InterstitialAd: PaidEventCapable {}
    extension AppOpenAd: PaidEventCapable {}
    extension RewardedAd: PaidEventCapable {}

    /// Generic base class for managing full-screen ads with thread-safe operations.
    /// Subclasses must override `loadAd(adUnitID:)`, `adTypeName()`, and set `format`
    /// to the matching `AdRevenueEvent.AdFormat` so paid-event revenue is published
    /// with the correct classification.
    class BaseAdManager<AdType: FullScreenPresentingAd>: NSObject, FullScreenContentDelegate, @unchecked Sendable {
        private let lock = NSLock()
        private var ads: [String: AdType] = [:]

        /// In-flight `showAd` continuation for a presented ad, plus the unit it was
        /// shown for (so dismiss can reload that unit). Keyed by the **presented ad
        /// object's identity** — see `presentations`.
        private struct Presentation {
            let adUnitID: String
            let continuation: CheckedContinuation<Void, Error>
        }

        /// Active presentations keyed by `ObjectIdentifier(ad)`, captured at show
        /// time. Dismiss / fail-to-present resolve the continuation by the live ad
        /// object's identity rather than re-deriving the unit from the mutable
        /// `ads` cache: a concurrent preload/reload (or two placements that resolve
        /// to the same unit — e.g. the splash + back interstitials both mapping to
        /// the Google test unit in DEBUG) can overwrite `ads[unit]` while an ad is
        /// on screen, which made the old reverse identity lookup miss and leak the
        /// continuation, hanging `showAd` forever (launch screen stuck after the ad
        /// dismissed).
        private var presentations: [ObjectIdentifier: Presentation] = [:]

        /// Set by each subclass; threaded through the paid-event publisher so Adjust
        /// + Analytics can distinguish app-open vs interstitial vs rewarded revenue.
        var format: AdRevenueEvent.AdFormat { .interstitial }

        // MARK: - Thread-Safe Accessors

        final func getAd(for adUnitID: String) -> AdType? {
            lock.lock()
            defer { lock.unlock() }
            return ads[adUnitID]
        }

        final func setAd(
            _ ad: AdType,
            for adUnitID: String
        ) {
            lock.lock()
            defer { lock.unlock() }
            ads[adUnitID] = ad
        }

        final func removeAd(for adUnitID: String) {
            lock.lock()
            defer { lock.unlock() }
            ads.removeValue(forKey: adUnitID)
        }

        /// Registers the `showAd` continuation against the exact ad object being
        /// presented. The ad's identity — not the unit string — is the key, so a
        /// later cache overwrite of `ads[adUnitID]` can't orphan it.
        final func setContinuation(
            _ continuation: CheckedContinuation<Void, Error>,
            for ad: AdType,
            adUnitID: String
        ) {
            lock.lock()
            defer { lock.unlock() }
            presentations[ObjectIdentifier(ad)] = Presentation(adUnitID: adUnitID, continuation: continuation)
        }

        /// Removes and returns the presentation for a dismissed/failed ad, resolved
        /// by the live object's identity. Returns the unit too so the caller can
        /// reload it.
        private final func removePresentation(for ad: FullScreenPresentingAd) -> Presentation? {
            lock.lock()
            defer { lock.unlock() }
            return presentations.removeValue(forKey: ObjectIdentifier(ad))
        }

        // MARK: - Revenue attribution

        /// Attaches a paid-event handler to a freshly loaded ad. The handler forwards
        /// every paid impression to `AdRevenueClient.publish` with the subclass's
        /// `format`. Subclasses call this in `loadAd(adUnitID:)` right before handing
        /// the loaded ad back to the continuation.
        final func attachPaidEventHandler(
            _ ad: PaidEventCapable,
            adUnitID: String
        ) {
            let format = self.format
            ad.paidEventHandler = { adValue in
                @Dependency(\.adRevenueClient) var adRevenueClient
                adRevenueClient.publish(
                    AdRevenueEvent(
                        amount: Double(truncating: adValue.value),
                        currency: adValue.currencyCode,
                        adUnitId: adUnitID,
                        format: format,
                        source: .googleMobileAds,
                        receivedAt: .now
                    )
                )
            }
        }

        // MARK: - Abstract Methods (Override in subclass)

        /// Loads an ad for the specified ad unit ID. Subclasses must override this method.
        /// - Parameter adUnitID: The ad unit ID to load
        /// - Returns: The loaded ad instance
        /// - Throws: Error if ad loading fails
        func loadAd(adUnitID: String) async throws -> AdType {
            fatalError("Subclass must override loadAd(adUnitID:)")
        }

        /// Returns the name of the ad type for logging purposes. Subclasses must override this method.
        /// - Returns: A string representing the ad type (e.g., "APP_OPEN", "INTERSTITIAL", "REWARDED")
        func adTypeName() -> String {
            fatalError("Subclass must override adTypeName()")
        }

        /// Presents the ad. Subclasses must override this method to call the appropriate present method for their ad type.
        /// - Parameters:
        ///   - ad: The ad to present
        ///   - viewController: The view controller to present from
        @MainActor
        func presentAd(
            _ ad: AdType,
            from viewController: UIViewController
        ) {
            fatalError("Subclass must override presentAd(_:from:)")
        }

        // MARK: - Public Methods

        /// Checks if an ad should be shown based on rules, loading if necessary.
        /// - Parameters:
        ///   - adUnitID: The ad unit ID
        ///   - rules: Rules to evaluate before showing the ad
        /// - Returns: True if the ad should be shown, false otherwise
        public final func shouldShowAd(
            _ adUnitID: String,
            rules: [MobileAdsClient.AdRule]
        ) async -> Bool {
            let isSatisfied = await rules.allRulesSatisfied()

            if getAd(for: adUnitID) == nil {
                do {
                    let ad = try await loadAd(adUnitID: adUnitID)
                    setAd(ad, for: adUnitID)
                    #if DEBUG
                        print("🍺 \(adTypeName()) ad loaded successfully")
                    #endif
                    return isSatisfied
                } catch {
                    #if DEBUG
                        print("🌶️ Failed to load \(adTypeName()) ad: \(error.localizedDescription)")
                    #endif
                    return false
                }
            }

            return isSatisfied
        }

        /// Shows the ad for the specified ad unit ID.
        /// - Parameters:
        ///   - adUnitID: The ad unit ID
        ///   - viewController: The view controller to present from
        /// - Throws: `MobileAdsClient.AdError.adNotReady` if the ad is not loaded
        @MainActor
        public final func showAd(
            _ adUnitID: String,
            from viewController: UIViewController
        ) async throws {
            guard let ad = getAd(for: adUnitID) else {
                throw MobileAdsClient.AdError.adNotReady
            }

            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                setContinuation(continuation, for: ad, adUnitID: adUnitID)
                presentAd(ad, from: viewController)
            }
        }

        // MARK: - FullScreenContentDelegate

        @objc
        func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
            // Resolve by the presented ad's identity, not by reverse-looking-up the
            // unit in the mutable `ads` cache — the cache may already hold a newer
            // ad object for this unit (concurrent preload, or another placement on
            // the same unit), which would make a unit lookup miss and leak the
            // continuation, hanging `showAd`.
            guard let presentation = removePresentation(for: ad) else { return }

            presentation.continuation.resume(returning: ())

            let adUnitID = presentation.adUnitID
            Task {
                do {
                    let loadedAd = try await loadAd(adUnitID: adUnitID)
                    setAd(loadedAd, for: adUnitID)
                } catch {
                    // Silently fail - ad will be reloaded on next shouldShowAd call
                }
            }
        }

        @objc
        func ad(
            _ ad: FullScreenPresentingAd,
            didFailToPresentFullScreenContentWithError error: Error
        ) {
            guard let presentation = removePresentation(for: ad) else { return }

            presentation.continuation.resume(throwing: error)
        }
    }
#endif
