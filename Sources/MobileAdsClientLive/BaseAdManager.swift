//
//  BaseAdManager.swift
//  MobileAdsClient
//
//  Created by Thanh Hai Khong on 11/6/25.
//

#if canImport(UIKit)
    import AdRevenueClient
    import ComposableArchitecture
    import Foundation
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
    /// Subclasses must override `loadAd(adUnitID:keywords:)`, `adTypeName()`, and set
    /// `format` to the matching `AdRevenueEvent.AdFormat` so paid-event revenue is
    /// published with the correct classification.
    ///
    /// Caching is **keyword-aware**: instead of one ad per unit, the pool holds
    /// multiple ads per unit keyed by `(unitID, normalizedKeywords)`. A show for a
    /// given keyword set serves the matching cached ad when present; otherwise it
    /// serves any available ad for that unit immediately and background-loads the
    /// requested keyword variant so it's ready next time (see
    /// `acquireForPresentation`). Keywords are baked into the `Request` at load
    /// time and can't be changed on an already-loaded ad, so the keywords are part
    /// of the cache key rather than a single mutable side-table.
    class BaseAdManager<AdType: FullScreenPresentingAd>: NSObject, FullScreenContentDelegate, @unchecked Sendable {
        private let lock = NSLock()

        /// Composite cache key: the ad unit plus the **normalized** keyword set the
        /// ad was loaded with. Normalization (trim/lowercase/dedupe/sort) only
        /// affects matching identity — the original keywords are sent on the request.
        private struct CacheKey: Hashable {
            let unitID: String
            let keywords: [String]
        }

        /// A cached ad together with the **original** keywords it was loaded with
        /// (used verbatim when reloading the request) and an insertion sequence used
        /// for oldest-first eviction.
        private struct Entry {
            let ad: AdType
            let keywords: [String]
            let seq: UInt64
        }

        /// Multiple ready ads per unit, keyed by `(unit, normalized keywords)`.
        private var ads: [CacheKey: Entry] = [:]

        /// Keys currently being loaded, so concurrent `warm` calls for the same
        /// variant don't issue duplicate network loads.
        private var loadingKeys: Set<CacheKey> = []

        /// Monotonic counter stamped onto each `Entry` for oldest-first eviction.
        private var seqCounter: UInt64 = 0

        /// Upper bound on distinct keyword variants held per unit. Keeps the pool
        /// from growing unbounded if many keyword sets are requested over time;
        /// keywords are per-gate and stable, so a small cap is plenty.
        private let maxVariantsPerUnit = 4

        /// The keywords from the most recent **show request** per unit. The client
        /// remembers these on every request — hit or miss — and reloads the next ad
        /// with them after the current ad dismisses, so a unit always reloads toward
        /// the keywords it was last asked to present (not whatever a fallback ad
        /// happened to carry). Lock-guarded.
        private var requestedKeywordsByUnit: [String: [String]] = [:]

        /// In-flight `showAd` continuation for a presented ad, plus the unit it was
        /// shown for. Keyed by the **presented ad object's identity** — see
        /// `presentations`. The post-dismiss reload looks up the unit's remembered
        /// request keywords (`requestedKeywordsByUnit`), so the continuation only
        /// needs to carry the unit.
        private struct Presentation {
            let adUnitID: String
            let continuation: CheckedContinuation<Void, Error>
        }

        /// Active presentations keyed by `ObjectIdentifier(ad)`, captured at show
        /// time. Dismiss / fail-to-present resolve the continuation by the live ad
        /// object's identity rather than re-deriving the unit from the mutable
        /// `ads` cache: a concurrent preload/reload (or two placements that resolve
        /// to the same unit — e.g. the splash + back interstitials both mapping to
        /// the Google test unit in DEBUG) can overwrite the pool while an ad is on
        /// screen, which made the old reverse identity lookup miss and leak the
        /// continuation, hanging `showAd` forever (launch screen stuck after the ad
        /// dismissed).
        private var presentations: [ObjectIdentifier: Presentation] = [:]

        /// Set by each subclass; threaded through the paid-event publisher so Adjust
        /// + Analytics can distinguish app-open vs interstitial vs rewarded revenue.
        var format: AdRevenueEvent.AdFormat { .interstitial }

        // MARK: - Keyword normalization

        /// Cache-identity normalization: trims, lowercases, drops empties, dedupes,
        /// and sorts. Used **only** to build `CacheKey`, so `["A","b"]` and
        /// `["b","a"]` map to the same slot. The request still carries the caller's
        /// original keywords (stored on `Entry`), so AdMob targeting is unchanged.
        private static func normalize(_ keywords: [String]) -> [String] {
            var seen = Set<String>()
            var out: [String] = []
            for keyword in keywords {
                let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                guard !trimmed.isEmpty, seen.insert(trimmed).inserted else { continue }
                out.append(trimmed)
            }
            return out.sorted()
        }

        private func cacheKey(
            _ adUnitID: String,
            _ keywords: [String]
        ) -> CacheKey {
            CacheKey(unitID: adUnitID, keywords: Self.normalize(keywords))
        }

        // MARK: - Debug logging

        /// Greppable pool-activity log (DEBUG only). Filter the simulator console by
        /// `[AdPool]` (or `[AdPool] INTERSTITIAL` etc.) to watch keyword matching,
        /// fallback serves, background reloads, and eviction as you build & run.
        /// The message is an `@autoclosure`, so nothing is built in release.
        private func logPool(_ message: @autoclosure () -> String) {
            #if DEBUG
                print("🎯 [AdPool] \(adTypeName()) — \(message())")
            #endif
        }

        // MARK: - Thread-Safe Pool Accessors

        /// Returns (without consuming) the ad for an exact `(unit, keywords)` key.
        private func cachedAd(forKey key: CacheKey) -> Entry? {
            lock.lock()
            defer { lock.unlock() }
            return ads[key]
        }

        /// Removes and returns the ad for an exact `(unit, keywords)` key.
        private func take(_ key: CacheKey) -> Entry? {
            lock.lock()
            defer { lock.unlock() }
            return ads.removeValue(forKey: key)
        }

        /// Removes and returns the newest ready ad for `adUnitID`, regardless of
        /// keywords — the fallback served when no exact-keyword match exists.
        private func takeAnyVariant(forUnit adUnitID: String) -> Entry? {
            lock.lock()
            defer { lock.unlock() }
            let newest =
                ads
                .filter { $0.key.unitID == adUnitID }
                .max { $0.value.seq < $1.value.seq }
            guard let newest else { return nil }
            return ads.removeValue(forKey: newest.key)
        }

        /// Whether any ready ad exists for `adUnitID` (any keyword variant).
        private func hasAnyVariant(forUnit adUnitID: String) -> Bool {
            lock.lock()
            defer { lock.unlock() }
            return ads.keys.contains { $0.unitID == adUnitID }
        }

        /// Stores a freshly loaded ad under `(unit, normalized keywords)`, then
        /// evicts this unit's oldest variant if it now exceeds `maxVariantsPerUnit`.
        private func store(
            _ ad: AdType,
            adUnitID: String,
            keywords: [String]
        ) {
            lock.lock()
            defer { lock.unlock() }
            seqCounter += 1
            ads[cacheKey(adUnitID, keywords)] = Entry(ad: ad, keywords: keywords, seq: seqCounter)

            let unitKeys = ads.keys.filter { $0.unitID == adUnitID }
            guard unitKeys.count > maxVariantsPerUnit else {
                logPool("pool holds \(unitKeys.count) variant(s) · unit=\(adUnitID)")
                return
            }
            if let oldest = unitKeys.min(by: { (ads[$0]?.seq ?? 0) < (ads[$1]?.seq ?? 0) }) {
                ads.removeValue(forKey: oldest)
                logPool(
                    "evicted oldest variant (cap \(maxVariantsPerUnit)) · unit=\(adUnitID) · evicted=\(oldest.keywords)"
                )
            }
        }

        /// Marks `key` as loading; returns `false` if a load for it is already in
        /// flight (so the caller can skip a duplicate load).
        private func beginLoading(_ key: CacheKey) -> Bool {
            lock.lock()
            defer { lock.unlock() }
            return loadingKeys.insert(key).inserted
        }

        private func endLoading(_ key: CacheKey) {
            lock.lock()
            defer { lock.unlock() }
            loadingKeys.remove(key)
        }

        /// Records the keywords from the latest show request for `adUnitID`.
        private func rememberRequestedKeywords(
            _ adUnitID: String,
            _ keywords: [String]
        ) {
            lock.lock()
            defer { lock.unlock() }
            requestedKeywordsByUnit[adUnitID] = keywords
        }

        /// The keywords from the latest show request for `adUnitID` (empty if none).
        private func rememberedKeywords(for adUnitID: String) -> [String] {
            lock.lock()
            defer { lock.unlock() }
            return requestedKeywordsByUnit[adUnitID] ?? []
        }

        /// Registers the `showAd` continuation against the exact ad object being
        /// presented. The ad's identity — not the unit string — is the key, so a
        /// later cache change can't orphan it. The dismiss reload sources its
        /// keywords from the unit's remembered request (`requestedKeywordsByUnit`).
        final func setContinuation(
            _ continuation: CheckedContinuation<Void, Error>,
            for ad: AdType,
            adUnitID: String
        ) {
            lock.lock()
            defer { lock.unlock() }
            presentations[ObjectIdentifier(ad)] = Presentation(
                adUnitID: adUnitID,
                continuation: continuation
            )
        }

        /// Removes and returns the presentation for a dismissed/failed ad, resolved
        /// by the live object's identity.
        private final func removePresentation(for ad: FullScreenPresentingAd) -> Presentation? {
            lock.lock()
            defer { lock.unlock() }
            return presentations.removeValue(forKey: ObjectIdentifier(ad))
        }

        // MARK: - Loading / Acquisition

        /// Ensures the **exact** `(unit, keywords)` variant is cached, returning it.
        /// Returns the cached ad on a hit; otherwise loads it (deduping concurrent
        /// loads of the same variant via `loadingKeys`), stores it, and returns it.
        /// Never evicts other variants. Used by `shouldShowAd`/`preloadAd` and as the
        /// background loader after a fallback serve / dismiss.
        @discardableResult
        final func warm(
            _ adUnitID: String,
            keywords: [String]
        ) async -> AdType? {
            let key = cacheKey(adUnitID, keywords)
            if let entry = cachedAd(forKey: key) {
                logPool("warm: already cached · unit=\(adUnitID) · keywords=\(keywords)")
                return entry.ad
            }
            guard beginLoading(key) else {
                // Another task is already loading this exact variant; don't
                // duplicate. Whatever it produced (if it finished) is reported here.
                logPool("warm: load already in flight · unit=\(adUnitID) · keywords=\(keywords) → skip duplicate")
                return cachedAd(forKey: key)?.ad
            }
            defer { endLoading(key) }
            logPool("warm: loading · unit=\(adUnitID) · keywords=\(keywords)")
            do {
                let ad = try await loadAd(adUnitID: adUnitID, keywords: keywords)
                store(ad, adUnitID: adUnitID, keywords: keywords)
                logPool("warm: loaded + stored · unit=\(adUnitID) · keywords=\(keywords)")
                return ad
            } catch {
                logPool(
                    "warm: FAILED to load · unit=\(adUnitID) · keywords=\(keywords) · error=\(error.localizedDescription)"
                )
                return nil
            }
        }

        /// Picks the ad to present for `(unit, keywords)`. On every call — hit or
        /// miss — it remembers the requested keywords for this unit
        /// (`requestedKeywordsByUnit`), which the post-dismiss reload then uses:
        /// 1. **Exact keyword match** — consume and present it.
        /// 2. **No match but a unit ad is ready** — consume that ad as a fallback and
        ///    present it now. The requested variant is NOT loaded here; it loads on
        ///    dismiss from the remembered keywords.
        /// 3. **Nothing cached** — load the requested variant and present it.
        /// Returns `nil` only when nothing is cached and the fresh load fails.
        final func acquireForPresentation(
            _ adUnitID: String,
            keywords: [String]
        ) async -> AdType? {
            // Remember the request's keywords regardless of availability — the
            // dismiss reload uses these to load the next ad for this unit.
            rememberRequestedKeywords(adUnitID, keywords)

            let key = cacheKey(adUnitID, keywords)

            if let entry = take(key) {
                logPool("show: EXACT keyword match · unit=\(adUnitID) · keywords=\(keywords) → serving matched ad")
                return entry.ad
            }

            if let entry = takeAnyVariant(forUnit: adUnitID) {
                logPool(
                    "show: FALLBACK · unit=\(adUnitID) · wanted=\(keywords) · serving variant loaded with \(entry.keywords) · remembered=\(keywords) (loads on dismiss)"
                )
                return entry.ad
            }

            logPool("show: MISS · unit=\(adUnitID) · keywords=\(keywords) · pool empty → loading fresh to present")
            do {
                let ad = try await loadAd(adUnitID: adUnitID, keywords: keywords)
                return ad
            } catch {
                logPool(
                    "show: FAILED fresh load · unit=\(adUnitID) · keywords=\(keywords) · error=\(error.localizedDescription)"
                )
                return nil
            }
        }

        // MARK: - Revenue attribution

        /// Attaches a paid-event handler to a freshly loaded ad. The handler forwards
        /// every paid impression to `AdRevenueClient.publish` with the subclass's
        /// `format`. Subclasses call this in `loadAd(adUnitID:keywords:)` right before
        /// handing the loaded ad back to the continuation.
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
        /// - Parameters:
        ///   - adUnitID: The ad unit ID to load
        ///   - keywords: Contextual keywords to set on the `Request` (`request.keywords`)
        /// - Returns: The loaded ad instance
        /// - Throws: Error if ad loading fails
        func loadAd(
            adUnitID: String,
            keywords: [String]
        ) async throws -> AdType {
            fatalError("Subclass must override loadAd(adUnitID:keywords:)")
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
        /// Readiness reflects `showAd`'s serve-with-fallback behavior: ready when
        /// the exact keyword variant warmed OR any variant for this unit is cached.
        /// - Parameters:
        ///   - adUnitID: The ad unit ID
        ///   - rules: Rules to evaluate before showing the ad
        ///   - keywords: Contextual keywords for the variant to warm
        /// - Returns: True if the ad should be shown, false otherwise
        public final func shouldShowAd(
            _ adUnitID: String,
            rules: [MobileAdsClient.AdRule],
            keywords: [String] = []
        ) async -> Bool {
            let isSatisfied = await rules.allRulesSatisfied()

            let exactReady = await warm(adUnitID, keywords: keywords) != nil
            guard exactReady || hasAnyVariant(forUnit: adUnitID) else {
                logPool("shouldShowAd: NOT ready · unit=\(adUnitID) · keywords=\(keywords)")
                return false
            }
            logPool(
                "shouldShowAd: ready (\(exactReady ? "exact" : "fallback")) · unit=\(adUnitID) · keywords=\(keywords) · rulesSatisfied=\(isSatisfied)"
            )
            return isSatisfied
        }

        /// Shows an ad for the specified ad unit ID, preferring a cached ad that
        /// matches `keywords` and falling back to any available ad for the unit
        /// while the keyword variant loads in the background.
        /// - Parameters:
        ///   - adUnitID: The ad unit ID
        ///   - viewController: The view controller to present from
        ///   - keywords: Contextual keywords for the preferred variant
        /// - Throws: `MobileAdsClient.AdError.adNotReady` if nothing is cached and the load fails
        @MainActor
        public final func showAd(
            _ adUnitID: String,
            from viewController: UIViewController,
            keywords: [String] = []
        ) async throws {
            guard let ad = await acquireForPresentation(adUnitID, keywords: keywords) else {
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
            // unit in the mutable pool — a concurrent reload (or another placement on
            // the same unit) could otherwise make the lookup miss and leak the
            // continuation, hanging `showAd`.
            guard let presentation = removePresentation(for: ad) else { return }
            presentation.continuation.resume(returning: ())
            reloadAfterPresentation(presentation)
        }

        @objc
        func ad(
            _ ad: FullScreenPresentingAd,
            didFailToPresentFullScreenContentWithError error: Error
        ) {
            guard let presentation = removePresentation(for: ad) else { return }
            presentation.continuation.resume(throwing: error)
            reloadAfterPresentation(presentation)
        }

        /// After an impression (or a failed present), loads the next ad for the unit
        /// using the keywords remembered from the unit's latest show request — so the
        /// pool reloads toward what was last asked for, even if a fallback ad (with
        /// different keywords) was the one just shown.
        private func reloadAfterPresentation(_ presentation: Presentation) {
            let adUnitID = presentation.adUnitID
            let keywords = rememberedKeywords(for: adUnitID)
            logPool("reload remembered keywords=\(keywords) · unit=\(adUnitID) (after dismiss)")
            Task { [weak self] in
                _ = await self?.warm(adUnitID, keywords: keywords)
            }
        }
    }
#endif
