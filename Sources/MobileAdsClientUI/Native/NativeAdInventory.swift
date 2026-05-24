//
//  NativeAdInventory.swift
//  MobileAdsClient
//
//  Per-consumer pool of pre-loaded `NativeAd` objects. Refills in batches via
//  `MultipleAdsAdLoaderOptions` (one AdMob auction returns N ads), decoupling
//  ad load latency from feed-scroll position. Consumers `pop()` an ad when
//  they need to slot one into a list; the inventory keeps itself topped up
//  in the background.
//

#if canImport(UIKit)
import ComposableArchitecture
import Foundation
@preconcurrency import GoogleMobileAds
import NativeAdClient
import UIKit

public actor NativeAdInventory {

    private struct PooledAd {
        let ad: NativeAd
        let addedAt: Date
    }

    private var pool: [PooledAd] = []
    private var refillTask: Task<Void, Never>?

    private let adUnitID: String
    private let options: [NativeAdClient.AnyAdLoaderOption]
    private let depthTarget: Int
    private let batchSize: Int
    private let maxAgeSeconds: TimeInterval

    @Dependency(\.nativeAdClient) private var client

    public init(
        adUnitID: String,
        options: [NativeAdClient.AnyAdLoaderOption] = [],
        depthTarget: Int = 5,
        batchSize: Int = 5,
        maxAgeSeconds: TimeInterval = 300
    ) {
        self.adUnitID = adUnitID
        self.options = options
        self.depthTarget = depthTarget
        self.batchSize = batchSize
        self.maxAgeSeconds = maxAgeSeconds
    }

    /// Drop expired entries, return the freshest in-pool ad (or nil if empty),
    /// then kick a refill task in the background if depth is now below target.
    /// The caller never blocks on a fresh fetch — pop is best-effort.
    public func pop() -> NativeAd? {
        evictExpired()
        let next = pool.isEmpty ? nil : pool.removeFirst().ad
        refillIfNeeded()
        return next
    }

    /// Convenience: try to pop up to `count` ads. Returns however many the
    /// pool had ready (could be 0). Triggers a single background refill at
    /// the end if depth fell below target.
    public func popMany(count: Int) -> [NativeAd] {
        guard count > 0 else { return [] }
        evictExpired()
        #if DEBUG
        print("🪺 INV popMany request=\(count) poolBefore=\(pool.count)")
        #endif
        let take = min(count, pool.count)
        let result = (0..<take).map { _ in pool.removeFirst().ad }
        refillIfNeeded()
        return result
    }

    /// Start a background refill task if one isn't already in flight and the
    /// pool has dropped below `depthTarget`. Idempotent — concurrent callers
    /// join the same task instead of stacking duplicate AdMob requests.
    public func refillIfNeeded() {
        #if DEBUG
        print("🪺 INV refillIfNeeded called pool=\(pool.count) task=\(refillTask != nil)")
        #endif
        guard refillTask == nil, pool.count < depthTarget else { return }
        let missing = max(1, depthTarget - pool.count)
        let request = min(missing, batchSize)
        let adUnitID = self.adUnitID
        let options = self.options
        let client = self.client
        refillTask = Task { [weak self] in
            let viewController = await Self.rootViewController()
            do {
                let ads = try await client.loadAds(adUnitID, viewController, options, request)
                await self?.finishRefill(ads: ads)
            } catch {
                #if DEBUG
                print("⚠️ NativeAdInventory refill failed unit=\(adUnitID) error=\(error.localizedDescription)")
                #endif
                await self?.finishRefill(ads: [])
            }
        }
    }

    /// Force a fresh refill regardless of depth. Useful right after launch to
    /// pre-warm the pool before the user scrolls.
    public func prewarm() {
        refillIfNeeded()
    }

    public func currentDepth() -> Int {
        evictExpired()
        return pool.count
    }

    // MARK: - Private

    /// Single atomic step that lands the refill result and clears the in-flight
    /// task marker. Keeps both writes inside the same actor hop so concurrent
    /// `refillIfNeeded` callers see a consistent state.
    private func finishRefill(ads: [NativeAd]) {
        let now = Date()
        pool.append(contentsOf: ads.map { PooledAd(ad: $0, addedAt: now) })
        refillTask = nil
        #if DEBUG
        print("🪺 INV finishRefill received=\(ads.count) newPool=\(pool.count)")
        #endif
    }

    private func evictExpired() {
        let cutoff = Date().addingTimeInterval(-maxAgeSeconds)
        pool.removeAll { $0.addedAt < cutoff }
    }

    @MainActor
    private static func rootViewController() -> UIViewController? {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else {
            return nil
        }
        return scene.windows.first?.rootViewController
    }
}
#endif
