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
    /// `RewardedAd` all match this shape; used to attach a shared revenue publisher
    /// at load time (and on Google-dequeued ads) without subclass-specific glue.
    protocol PaidEventCapable: AnyObject {
        var paidEventHandler: ((AdValue) -> Void)? { get set }
    }

    extension InterstitialAd: PaidEventCapable {}
    extension AppOpenAd: PaidEventCapable {}
    extension RewardedAd: PaidEventCapable {}

    /// Thin router over the two ways a full-screen ad can be acquired:
    /// `PooledAdSource` (keyword-aware hand-rolled pool with TTL + retry) and
    /// `GooglePreloadSource` (Google's per-format Preloader buffer). The routing
    /// rule is one line — **empty keywords + a host-registered unit → Google;
    /// everything else → pool** — so the storage/retry/buffer details live in the
    /// source types, and this class keeps only what is genuinely its job:
    /// presentation/continuation bookkeeping, the `FullScreenContentDelegate`
    /// dismiss/fail handlers, revenue attachment, and post-dismiss reload.
    ///
    /// Subclasses override `loadAd`, `adTypeName`, `presentAd`, set `format`, and —
    /// to opt into Google preload — set `supportsGooglePreload` and the four
    /// `google*` singleton bridges.
    ///
    /// `@unchecked Sendable`: router state is guarded by `stateLock`; pool state is
    /// guarded inside `AdPool`.
    class BaseAdManager<AdType: FullScreenPresentingAd & Sendable>: NSObject, FullScreenContentDelegate,
        @unchecked Sendable
    {
        /// Set by each subclass; threaded through the paid-event publisher so Adjust
        /// + Analytics can distinguish app-open vs interstitial vs rewarded revenue.
        var format: AdRevenueEvent.AdFormat { .interstitial }

        /// Max age before a pooled ad is treated as stale (TTL). Overridable per
        /// format: full-screen interstitial/rewarded expire ~1h, app-open ~4h.
        var poolMaxAge: TimeInterval { 3300 }  // ~55 minutes

        /// Whether this format supports Google's Preloader (native does not; the
        /// three full-screen subclasses set this true). Base default keeps any
        /// non-preloadable subclass on the pool path.
        var supportsGooglePreload: Bool { false }

        // MARK: - Acquisition sources

        /// Lazy so the subclass's `poolMaxAge` / `google*` overrides are visible
        /// (dynamic dispatch is live only after `init`) and so the `[weak self]`
        /// closures can capture a fully-initialized `self`.
        private lazy var pool = AdPool<AdType>(maxAge: poolMaxAge)

        private lazy var pooledSource = PooledAdSource<AdType>(
            pool: pool,
            load: { [weak self] unit, keywords in
                guard let self else { throw MobileAdsClient.AdError.adNotReady }
                return try await self.loadAd(adUnitID: unit, keywords: keywords)
            },
            log: { [weak self] message in
                self?.logPool(message)
            }
        )

        private lazy var googleSource = GooglePreloadSource<AdType>(
            register: { [weak self] id, size in self?.googleRegister(id, bufferSize: size) ?? false },
            isAvailable: { [weak self] id in self?.googleIsAvailable(id) ?? false },
            count: { [weak self] id in self?.googleAdCount(id) ?? 0 },
            dequeue: { [weak self] id in self?.googleDequeue(id) },
            stop: { [weak self] id in self?.googleStop(id) },
            configure: { [weak self] ad, id in self?.configureDequeued(ad, adUnitID: id) }
        )

        // MARK: - Router state (guarded by `stateLock`)

        private let stateLock = NSLock()

        /// Units the host registered for the Google Preloader (always keyword-less).
        private var registeredPreloadUnits: Set<String> = []

        /// Keywords from the latest **show request** per unit, used by the
        /// post-dismiss reload so the pool reloads toward what was last asked for
        /// (not whatever a fallback ad happened to carry).
        private var requestedKeywordsByUnit: [String: [String]] = [:]

        /// In-flight `showAd` continuation for a presented ad, keyed by the
        /// presented ad object's identity (not the unit) so a concurrent
        /// pool/buffer change can't orphan it.
        private struct Presentation {
            let adUnitID: String
            let continuation: CheckedContinuation<Void, Error>
            /// When true, the post-dismiss auto-warm is skipped — the caller supplied
            /// an `onComplete` handler and owns the preload decision for this show.
            let suppressReload: Bool
        }

        private var presentations: [ObjectIdentifier: Presentation] = [:]

        // MARK: - Debug logging

        /// Greppable pool-activity log (DEBUG only). Filter the simulator console by
        /// `[AdPool]` (or `[AdPool] INTERSTITIAL` etc.).
        func logPool(_ message: @autoclosure () -> String) {
            #if DEBUG
                print("🎯 [AdPool] \(adTypeName()) — \(message())")
            #endif
        }

        // MARK: - Router state accessors

        private func isRegistered(_ adUnitID: String) -> Bool {
            stateLock.lock()
            defer { stateLock.unlock() }
            return registeredPreloadUnits.contains(adUnitID)
        }

        private func markRegistered(_ adUnitID: String) {
            stateLock.lock()
            defer { stateLock.unlock() }
            registeredPreloadUnits.insert(adUnitID)
        }

        private func unmarkRegistered(_ adUnitID: String) {
            stateLock.lock()
            defer { stateLock.unlock() }
            registeredPreloadUnits.remove(adUnitID)
        }

        private func rememberRequestedKeywords(
            _ adUnitID: String,
            _ keywords: [String]
        ) {
            stateLock.lock()
            defer { stateLock.unlock() }
            requestedKeywordsByUnit[adUnitID] = keywords
        }

        private func rememberedKeywords(for adUnitID: String) -> [String] {
            stateLock.lock()
            defer { stateLock.unlock() }
            return requestedKeywordsByUnit[adUnitID] ?? []
        }

        /// True when a request should be served by Google's preloader: the format
        /// supports it, the unit was registered, and the keywords are empty (the
        /// preloader's `Request` is frozen at registration — no per-show keywords).
        private func usesGoogle(
            _ adUnitID: String,
            keywords: [String]
        ) -> Bool {
            supportsGooglePreload
                && AdPool<AdType>.normalize(keywords).isEmpty
                && isRegistered(adUnitID)
        }

        // MARK: - Presentation bookkeeping

        /// Registers the `showAd` continuation against the exact ad object being
        /// presented. The ad's identity — not the unit string — is the key, so a
        /// later cache/buffer change can't orphan it.
        final func setContinuation(
            _ continuation: CheckedContinuation<Void, Error>,
            for ad: AdType,
            adUnitID: String,
            suppressReload: Bool
        ) {
            stateLock.lock()
            defer { stateLock.unlock() }
            presentations[ObjectIdentifier(ad)] = Presentation(
                adUnitID: adUnitID,
                continuation: continuation,
                suppressReload: suppressReload
            )
        }

        private func removePresentation(for ad: FullScreenPresentingAd) -> Presentation? {
            stateLock.lock()
            defer { stateLock.unlock() }
            return presentations.removeValue(forKey: ObjectIdentifier(ad))
        }

        // MARK: - Revenue attribution

        /// Attaches a paid-event handler that forwards every paid impression to
        /// `AdRevenueClient.publish` with this subclass's `format`. Used both by
        /// subclass `loadAd` overrides and by `configureDequeued` on Google ads.
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

        /// Re-wires a Google-dequeued ad: the Preloader does **not** set our
        /// delegate or paid-event handler (the ad wasn't built by our `loadAd`), so
        /// without this a preloaded show would lose its dismiss callback and revenue
        /// reporting.
        final func configureDequeued(
            _ ad: AdType,
            adUnitID: String
        ) {
            ad.fullScreenContentDelegate = self
            if let capable = ad as? PaidEventCapable {
                attachPaidEventHandler(capable, adUnitID: adUnitID)
            }
        }

        // MARK: - Abstract Methods (Override in subclass)

        /// Loads an ad for the pooled path. Subclasses must override.
        func loadAd(
            adUnitID: String,
            keywords: [String]
        ) async throws -> AdType {
            fatalError("Subclass must override loadAd(adUnitID:keywords:)")
        }

        /// Name of the ad type for logging (e.g. "INTERSTITIAL"). Subclasses must override.
        func adTypeName() -> String {
            fatalError("Subclass must override adTypeName()")
        }

        /// Presents the ad. Subclasses must override.
        @MainActor
        func presentAd(
            _ ad: AdType,
            from viewController: UIViewController
        ) {
            fatalError("Subclass must override presentAd(_:from:)")
        }

        // MARK: - Google preloader bridges (override when supportsGooglePreload)

        /// Starts the SDK buffer; returns false if preload couldn't start.
        func googleRegister(
            _ preloadID: String,
            bufferSize: Int
        ) -> Bool { false }

        func googleIsAvailable(_ preloadID: String) -> Bool { false }

        /// Number of ads currently buffered by the preloader for `preloadID`.
        /// Overridden by preload-capable subclasses; base returns 0.
        func googleAdCount(_ preloadID: String) -> Int { 0 }

        func googleDequeue(_ preloadID: String) -> AdType? { nil }

        func googleStop(_ preloadID: String) {}

        // MARK: - Public API (the router)

        /// Eagerly register a unit for Google's Preloader (keyword-less). On a
        /// format that doesn't support Google preload, falls back to warming the
        /// pool so registration is never a silent no-op.
        public final func register(
            _ adUnitID: String,
            bufferSize: Int
        ) async {
            guard supportsGooglePreload else {
                logPool("register: google unsupported → warming pool · unit=\(adUnitID)")
                await pooledSource.warm(adUnitID, keywords: [])
                return
            }
            if googleSource.register(adUnitID, bufferSize: bufferSize) {
                markRegistered(adUnitID)
                logPool("register: google preload ON · unit=\(adUnitID) · buffer=\(bufferSize)")
            } else {
                logPool("register: google preload FAILED to start · unit=\(adUnitID)")
            }
        }

        /// Stop preloading and drop the buffer for a registered unit (show-rate
        /// lever — shed buffers for premium users / flows that won't show ads).
        public final func stopPreloading(_ adUnitID: String) async {
            guard isRegistered(adUnitID) else { return }
            googleSource.stop(adUnitID)
            unmarkRegistered(adUnitID)
            logPool("stopPreloading · unit=\(adUnitID)")
        }

        /// Google Preloader bucket counts for this format's registered units, omitting
        /// units whose buffer is currently empty. Empty when the format doesn't
        /// support Google preload.
        public final func googleCountsByUnit() -> [String: Int] {
            guard supportsGooglePreload else { return [:] }
            stateLock.lock()
            let units = Array(registeredPreloadUnits)
            stateLock.unlock()

            var out: [String: Int] = [:]
            for unit in units {
                let count = googleSource.count(unit)
                if count > 0 {
                    out[unit] = count
                }
            }
            return out
        }

        /// Snapshot of the keyword-aware pool's live variants, grouped by unit id.
        public final func poolVariantsByUnit() -> [String: [AdPool<AdType>.VariantInfo]] {
            pool.variantsByUnit()
        }

        /// On-demand warm. Google-managed units are a no-op (the SDK owns the
        /// buffer); everything else warms the pool for the requested variant.
        public final func warm(
            _ adUnitID: String,
            keywords: [String] = []
        ) async {
            if usesGoogle(adUnitID, keywords: keywords) {
                logPool("warm: google-managed (no-op) · unit=\(adUnitID)")
                return
            }
            await pooledSource.warm(adUnitID, keywords: keywords)
        }

        /// Readiness reflecting `showAd`'s serve-with-fallback behavior.
        public final func shouldShowAd(
            _ adUnitID: String,
            rules: [MobileAdsClient.AdRule],
            keywords: [String] = []
        ) async -> Bool {
            let isSatisfied = await rules.allRulesSatisfied()

            let ready: Bool
            if usesGoogle(adUnitID, keywords: keywords) {
                ready = googleSource.isAvailable(adUnitID)
            } else {
                let exact = await pooledSource.warm(adUnitID, keywords: keywords) != nil
                ready = exact || pool.hasAnyVariant(forUnit: adUnitID)
            }

            guard ready else {
                logPool("shouldShowAd: NOT ready · unit=\(adUnitID) · keywords=\(keywords)")
                return false
            }
            logPool("shouldShowAd: ready · unit=\(adUnitID) · keywords=\(keywords) · rulesSatisfied=\(isSatisfied)")
            return isSatisfied
        }

        /// Picks the ad to present for `(unit, keywords)`, routing Google-managed
        /// keyword-less requests to the preloader buffer first (falling through to
        /// the pool if the buffer is momentarily empty). Returns nil only when
        /// neither source can produce an ad. Shared by `showAd` and rewarded's
        /// `showAndAwaitReward`.
        final func acquireForPresentation(
            _ adUnitID: String,
            keywords: [String],
            onColdLoad: (@Sendable (AdLoadPhase) -> Void)? = nil
        ) async -> AdType? {
            rememberRequestedKeywords(adUnitID, keywords)

            if usesGoogle(adUnitID, keywords: keywords), let ad = googleSource.acquire(adUnitID) {
                logPool("show: GOOGLE preloaded · unit=\(adUnitID)")
                return ad
            }
            return await pooledSource.acquire(adUnitID, keywords: keywords, onColdLoad: onColdLoad)
        }

        /// Shows an ad for `adUnitID`, preferring a Google-preloaded ad (keyword-less
        /// registered units) then the keyword-aware pool. `onColdLoad` reports a
        /// show-time fresh-load (spinner signal); nil for silent shows.
        @MainActor
        public final func showAd(
            _ adUnitID: String,
            from viewController: UIViewController,
            keywords: [String] = [],
            suppressAutoReload: Bool = false,
            onColdLoad: (@Sendable (AdLoadPhase) -> Void)? = nil
        ) async throws {
            guard let ad = await acquireForPresentation(adUnitID, keywords: keywords, onColdLoad: onColdLoad) else {
                throw MobileAdsClient.AdError.adNotReady
            }

            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                setContinuation(continuation, for: ad, adUnitID: adUnitID, suppressReload: suppressAutoReload)
                presentAd(ad, from: viewController)
            }
        }

        // MARK: - FullScreenContentDelegate

        @objc
        func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
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

        /// After an impression (or a failed present), reload the next ad. Google
        /// units self-refill in the SDK, so this only reloads the pool — using the
        /// unit's remembered request keywords so the pool reloads toward what was
        /// last asked for.
        private func reloadAfterPresentation(_ presentation: Presentation) {
            let adUnitID = presentation.adUnitID
            // Caller supplied an onComplete handler → it owns the post-show preload
            // decision for this show; skip the built-in auto-warm.
            if presentation.suppressReload {
                logPool("reload: suppressed (caller onComplete owns it) · unit=\(adUnitID)")
                return
            }
            let keywords = rememberedKeywords(for: adUnitID)
            if usesGoogle(adUnitID, keywords: keywords) {
                logPool("reload: google self-refills (no-op) · unit=\(adUnitID)")
                return
            }
            logPool("reload: pool · unit=\(adUnitID) · keywords=\(keywords) (after dismiss)")
            Task { [weak self] in
                _ = await self?.pooledSource.warm(adUnitID, keywords: keywords)
            }
        }
    }
#endif
