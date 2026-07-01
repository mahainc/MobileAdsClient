//
//  AdSource.swift
//  MobileAdsClient
//
//  The two ways a full-screen ad can be acquired, each its own type:
//
//  • `PooledAdSource`        — our hand-rolled, keyword-aware pool (`AdPool`)
//                              + the subclass `loadAd` + bounded retry.
//  • `GooglePreloadSource`   — Google's per-format Preloader buffer (register
//                              once, SDK self-refills + auto-refreshes).
//
//  They are deliberately *not* unified behind one `associatedtype` protocol:
//  `BaseAdManager` calls different methods on each (pooled exposes `warm`;
//  Google exposes `register`/`stop`), so a shared protocol would only add
//  `any`-erasure with no polymorphic call site. Keeping them concrete keeps the
//  router in `BaseAdManager` a plain `if`.
//

#if canImport(UIKit)
    import Foundation
    @preconcurrency import GoogleMobileAds

    // MARK: - PooledAdSource

    /// Keyword-aware acquisition backed by `AdPool`. Owns the load + retry policy;
    /// `BaseAdManager` owns presentation/continuation bookkeeping on top.
    final class PooledAdSource<Ad: FullScreenPresentingAd>: @unchecked Sendable {
        let pool: AdPool<Ad>

        /// Loads one ad for `(unit, keywords)`. Bound by the owning manager to its
        /// `loadAd(adUnitID:keywords:)` override.
        private let load: @Sendable (_ unit: String, _ keywords: [String]) async throws -> Ad

        /// Greppable `[AdPool]` logger (the bound sink gates the actual print on
        /// DEBUG). Ad-pool log volume is low (once per load/show), so eager string
        /// building here is fine.
        private let log: @Sendable (_ message: String) -> Void

        /// Bounded retry: total attempts = `1 + retries`, sleeping `backoff[i]`
        /// between them before giving up and returning nil.
        private let retries: Int
        private let backoff: [UInt64]  // nanoseconds per retry gap

        init(
            pool: AdPool<Ad>,
            retries: Int = 2,
            backoffNanos: [UInt64] = [1_000_000_000, 2_000_000_000],
            load: @escaping @Sendable (_ unit: String, _ keywords: [String]) async throws -> Ad,
            log: @escaping @Sendable (_ message: String) -> Void
        ) {
            self.pool = pool
            self.retries = retries
            self.backoff = backoffNanos
            self.load = load
            self.log = log
        }

        /// Ensures the **exact** `(unit, keywords)` variant is cached, returning it.
        /// Cache hit → return; miss → load (deduped via `AdPool.beginLoading`) with
        /// bounded retry, store, return. Never evicts other variants. Returns nil
        /// only when all attempts fail.
        @discardableResult
        func warm(
            _ adUnitID: String,
            keywords: [String]
        ) async -> Ad? {
            let key = pool.key(adUnitID, keywords)
            if let ad = pool.cachedAd(forKey: key) {
                log("warm: already cached · unit=\(adUnitID) · keywords=\(keywords)")
                return ad
            }
            guard pool.beginLoading(key) else {
                log("warm: load already in flight · unit=\(adUnitID) · keywords=\(keywords) → skip duplicate")
                return pool.cachedAd(forKey: key)
            }
            defer { pool.endLoading(key) }

            var attempt = 0
            while true {
                log("warm: loading · unit=\(adUnitID) · keywords=\(keywords) · attempt=\(attempt + 1)")
                do {
                    let ad = try await load(adUnitID, keywords)
                    let outcome = pool.store(ad, adUnitID: adUnitID, keywords: keywords)
                    if let evicted = outcome.evictedKeywords {
                        log("evicted oldest variant · unit=\(adUnitID) · evicted=\(evicted)")
                    } else {
                        log("warm: loaded + stored · unit=\(adUnitID) · variants=\(outcome.variantCount)")
                    }
                    return ad
                } catch {
                    log(
                        "warm: FAILED · unit=\(adUnitID) · keywords=\(keywords) · attempt=\(attempt + 1) · error=\(error.localizedDescription)"
                    )
                    guard attempt < retries else { return nil }
                    let gap = backoff[min(attempt, backoff.count - 1)]
                    try? await Task.sleep(nanoseconds: gap)
                    attempt += 1
                }
            }
        }

        /// Ready when the exact keyword variant is cached OR any variant for the
        /// unit is cached (matches the serve-with-fallback behavior of `acquire`).
        func isAvailable(
            _ adUnitID: String,
            keywords: [String]
        ) -> Bool {
            if pool.cachedAd(forKey: pool.key(adUnitID, keywords)) != nil { return true }
            return pool.hasAnyVariant(forUnit: adUnitID)
        }

        /// Picks the ad to present for `(unit, keywords)`:
        /// 1. exact keyword match → consume + return it;
        /// 2. no match but a unit ad is ready → consume that as a fallback;
        /// 3. nothing cached → load fresh and return it.
        /// Returns nil only when nothing is cached and the fresh load fails.
        /// `onColdLoad` fires **only** on the tier-3 fresh-load branch (exact/fallback
        /// cache hits stay silent), so a host spinner reflects a genuine show-time
        /// wait and nothing else.
        func acquire(
            _ adUnitID: String,
            keywords: [String],
            onColdLoad: (@Sendable (AdLoadPhase) -> Void)? = nil
        ) async -> Ad? {
            let key = pool.key(adUnitID, keywords)

            if let taken = pool.take(key) {
                log("show: EXACT match · unit=\(adUnitID) · keywords=\(keywords)")
                return taken.ad
            }
            if let taken = pool.takeAnyVariant(forUnit: adUnitID) {
                log(
                    "show: FALLBACK · unit=\(adUnitID) · wanted=\(keywords) · served=\(taken.keywords) (reload on dismiss)"
                )
                return taken.ad
            }
            log("show: MISS · unit=\(adUnitID) · keywords=\(keywords) · pool empty → loading fresh")
            onColdLoad?(.started)
            do {
                let ad = try await load(adUnitID, keywords)
                onColdLoad?(.ready)
                return ad
            } catch {
                onColdLoad?(.failed)
                log(
                    "show: FAILED fresh load · unit=\(adUnitID) · keywords=\(keywords) · error=\(error.localizedDescription)"
                )
                return nil
            }
        }
    }

    // MARK: - GooglePreloadSource

    /// Bridges to one of Google's per-format Preloader singletons. The owning
    /// manager wires the closures to its concrete singleton (e.g.
    /// `InterstitialAdPreloader.shared`) and supplies `configure`, which re-attaches
    /// `fullScreenContentDelegate` + `paidEventHandler` on each dequeued ad (the
    /// Preloader doesn't pre-wire those — they weren't built by our `loadAd`).
    ///
    /// `preloadID` is the ad unit ID by convention. Keyword-less only: the
    /// `Request` is frozen at registration, so per-show keywords can't apply here.
    final class GooglePreloadSource<Ad: FullScreenPresentingAd>: @unchecked Sendable {
        private let registerImpl: @Sendable (_ preloadID: String, _ bufferSize: Int) -> Bool
        private let isAvailableImpl: @Sendable (_ preloadID: String) -> Bool
        private let countImpl: @Sendable (_ preloadID: String) -> Int
        private let dequeueImpl: @Sendable (_ preloadID: String) -> Ad?
        private let stopImpl: @Sendable (_ preloadID: String) -> Void
        private let configure: @Sendable (_ ad: Ad, _ preloadID: String) -> Void

        init(
            register: @escaping @Sendable (_ preloadID: String, _ bufferSize: Int) -> Bool,
            isAvailable: @escaping @Sendable (_ preloadID: String) -> Bool,
            count: @escaping @Sendable (_ preloadID: String) -> Int,
            dequeue: @escaping @Sendable (_ preloadID: String) -> Ad?,
            stop: @escaping @Sendable (_ preloadID: String) -> Void,
            configure: @escaping @Sendable (_ ad: Ad, _ preloadID: String) -> Void
        ) {
            self.registerImpl = register
            self.isAvailableImpl = isAvailable
            self.countImpl = count
            self.dequeueImpl = dequeue
            self.stopImpl = stop
            self.configure = configure
        }

        /// Starts the SDK buffer for `adUnitID`. Returns false if preload couldn't
        /// start (the manager records the unit only on success).
        @discardableResult
        func register(
            _ adUnitID: String,
            bufferSize: Int
        ) -> Bool {
            registerImpl(adUnitID, bufferSize)
        }

        func isAvailable(_ adUnitID: String) -> Bool {
            isAvailableImpl(adUnitID)
        }

        /// Number of ads currently available in the SDK buffer for `adUnitID`.
        func count(_ adUnitID: String) -> Int {
            countImpl(adUnitID)
        }

        /// Dequeues a preloaded ad (triggering the SDK's background refill) and
        /// re-wires it via `configure`. Returns nil if the buffer is empty.
        func acquire(_ adUnitID: String) -> Ad? {
            guard let ad = dequeueImpl(adUnitID) else { return nil }
            configure(ad, adUnitID)
            return ad
        }

        /// Stops preloading and drops the buffer for `adUnitID` (show-rate lever:
        /// shed buffers for premium users / flows that won't show ads).
        func stop(_ adUnitID: String) {
            stopImpl(adUnitID)
        }
    }
#endif
