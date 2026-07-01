//
//  AdPool.swift
//  MobileAdsClient
//
//  Lock-guarded, keyword-aware cache of ready full-screen ads, extracted from
//  `BaseAdManager` so the storage concern (keying, eviction, load-dedupe, TTL)
//  lives in one place. `BaseAdManager` orchestrates; `AdPool` just holds.
//

#if canImport(UIKit)
    import Foundation
    import GoogleMobileAds

    /// A thread-safe pool of loaded ads for a single format, keyed by
    /// `(unitID, normalized keywords)`. Holds multiple keyword variants per unit
    /// (capped by `maxVariantsPerUnit`), evicts oldest-first, and treats entries
    /// older than `maxAge` as absent (TTL) so a stale ad is never served — the
    /// gap that made the old cache hand back ads that failed at `present()`.
    ///
    /// Generic over the GMA full-screen ad type. `@unchecked Sendable` because all
    /// mutable state is guarded by `lock`; the SDK ad objects themselves are only
    /// read/stored, never mutated here.
    final class AdPool<Ad: FullScreenPresentingAd>: @unchecked Sendable {
        /// Composite cache key: the ad unit plus the **normalized** keyword set the
        /// ad was loaded with. Normalization (trim/lowercase/dedupe/sort) only
        /// affects matching identity — the original keywords ride on the request.
        struct CacheKey: Hashable {
            let unitID: String
            let keywords: [String]
        }

        /// A cached ad together with the **original** keywords it was loaded with
        /// (used verbatim when reloading the request), an insertion sequence used
        /// for oldest-first eviction, and the load time for TTL expiry.
        private struct Entry {
            let ad: Ad
            let keywords: [String]
            let seq: UInt64
            let loadedAt: Date
        }

        private let lock = NSLock()

        /// Multiple ready ads per unit, keyed by `(unit, normalized keywords)`.
        private var ads: [CacheKey: Entry] = [:]

        /// Keys currently being loaded, so concurrent loads of the same variant
        /// don't issue duplicate network requests.
        private var loadingKeys: Set<CacheKey> = []

        /// Monotonic counter stamped onto each `Entry` for oldest-first eviction.
        private var seqCounter: UInt64 = 0

        /// Upper bound on distinct keyword variants held per unit. Keeps the pool
        /// from growing unbounded if many keyword sets are requested over time.
        private let maxVariantsPerUnit: Int

        /// Max age before a cached ad is considered stale and evicted on access.
        /// GMA full-screen ads expire (~1h interstitial/rewarded, ~4h app-open);
        /// keep this comfortably under that so a served ad is always presentable.
        private let maxAge: TimeInterval

        /// Time source — injectable so tests can age entries deterministically.
        private let now: @Sendable () -> Date

        init(
            maxVariantsPerUnit: Int = 4,
            maxAge: TimeInterval,
            now: @escaping @Sendable () -> Date = { Date() }
        ) {
            self.maxVariantsPerUnit = maxVariantsPerUnit
            self.maxAge = maxAge
            self.now = now
        }

        // MARK: - Key construction

        /// Cache-identity normalization: trims, lowercases, drops empties, dedupes,
        /// and sorts. Used **only** to build `CacheKey`, so `["A","b"]` and
        /// `["b","a"]` map to the same slot. The request still carries the caller's
        /// original keywords (stored on `Entry`), so AdMob targeting is unchanged.
        static func normalize(_ keywords: [String]) -> [String] {
            var seen = Set<String>()
            var out: [String] = []
            for keyword in keywords {
                let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                guard !trimmed.isEmpty, seen.insert(trimmed).inserted else { continue }
                out.append(trimmed)
            }
            return out.sorted()
        }

        func key(
            _ adUnitID: String,
            _ keywords: [String]
        ) -> CacheKey {
            CacheKey(unitID: adUnitID, keywords: Self.normalize(keywords))
        }

        // MARK: - Accessors (all lock-guarded, TTL-aware)

        /// Returns (without consuming) the ad for an exact key, or nil if absent or
        /// expired. Expired entries are removed as a side effect.
        func cachedAd(forKey cacheKey: CacheKey) -> Ad? {
            lock.lock()
            defer { lock.unlock() }
            return liveEntry(forKey: cacheKey)?.ad
        }

        /// Removes and returns the ad for an exact key, skipping/removing expired.
        func take(_ cacheKey: CacheKey) -> (ad: Ad, keywords: [String])? {
            lock.lock()
            defer { lock.unlock() }
            guard let entry = liveEntry(forKey: cacheKey) else { return nil }
            ads.removeValue(forKey: cacheKey)
            return (entry.ad, entry.keywords)
        }

        /// Removes and returns the newest non-expired ad for `adUnitID`, regardless
        /// of keywords — the fallback served when no exact-keyword match exists.
        func takeAnyVariant(forUnit adUnitID: String) -> (ad: Ad, keywords: [String])? {
            lock.lock()
            defer { lock.unlock() }
            purgeExpired(forUnit: adUnitID)
            let newest =
                ads
                .filter { $0.key.unitID == adUnitID }
                .max { $0.value.seq < $1.value.seq }
            guard let newest, let entry = ads.removeValue(forKey: newest.key) else { return nil }
            return (entry.ad, entry.keywords)
        }

        /// Whether any non-expired ad exists for `adUnitID` (any keyword variant).
        func hasAnyVariant(forUnit adUnitID: String) -> Bool {
            lock.lock()
            defer { lock.unlock() }
            purgeExpired(forUnit: adUnitID)
            return ads.keys.contains { $0.unitID == adUnitID }
        }

        /// Stores a freshly loaded ad under `(unit, normalized keywords)`, then
        /// evicts this unit's oldest variant if it now exceeds `maxVariantsPerUnit`.
        /// Returns an eviction note for logging (nil if nothing was evicted).
        @discardableResult
        func store(
            _ ad: Ad,
            adUnitID: String,
            keywords: [String]
        ) -> StoreOutcome {
            lock.lock()
            defer { lock.unlock() }
            seqCounter += 1
            ads[key(adUnitID, keywords)] = Entry(
                ad: ad,
                keywords: keywords,
                seq: seqCounter,
                loadedAt: now()
            )

            let unitKeys = ads.keys.filter { $0.unitID == adUnitID }
            guard unitKeys.count > maxVariantsPerUnit else {
                return StoreOutcome(variantCount: unitKeys.count, evictedKeywords: nil)
            }
            guard
                let oldest = unitKeys.min(by: { (ads[$0]?.seq ?? 0) < (ads[$1]?.seq ?? 0) })
            else {
                return StoreOutcome(variantCount: unitKeys.count, evictedKeywords: nil)
            }
            ads.removeValue(forKey: oldest)
            return StoreOutcome(variantCount: maxVariantsPerUnit, evictedKeywords: oldest.keywords)
        }

        /// Marks `cacheKey` as loading; returns `false` if a load for it is already
        /// in flight (so the caller can skip a duplicate load).
        func beginLoading(_ cacheKey: CacheKey) -> Bool {
            lock.lock()
            defer { lock.unlock() }
            return loadingKeys.insert(cacheKey).inserted
        }

        func endLoading(_ cacheKey: CacheKey) {
            lock.lock()
            defer { lock.unlock() }
            loadingKeys.remove(cacheKey)
        }

        /// Result of a `store`, surfaced for the caller's `[AdPool]` log.
        struct StoreOutcome {
            let variantCount: Int
            let evictedKeywords: [String]?
        }

        // MARK: - Private (must hold `lock`)

        /// Returns the entry for a key only if present and not expired; removes it
        /// if expired. Caller must hold `lock`.
        private func liveEntry(forKey cacheKey: CacheKey) -> Entry? {
            guard let entry = ads[cacheKey] else { return nil }
            guard !isExpired(entry) else {
                ads.removeValue(forKey: cacheKey)
                return nil
            }
            return entry
        }

        /// Removes all expired entries for a unit. Caller must hold `lock`.
        private func purgeExpired(forUnit adUnitID: String) {
            for (cacheKey, entry) in ads where cacheKey.unitID == adUnitID && isExpired(entry) {
                ads.removeValue(forKey: cacheKey)
            }
        }

        private func isExpired(_ entry: Entry) -> Bool {
            now().timeIntervalSince(entry.loadedAt) >= maxAge
        }
    }
#endif
