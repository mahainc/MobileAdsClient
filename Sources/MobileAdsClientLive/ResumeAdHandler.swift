//
//  ResumeAdHandler.swift
//  MobileAdsClient
//
//  Lifecycle observer for the background→foreground app-open ad. Replaces
//  the app-target `AppOpenResumeManager` singleton so the policy lives
//  behind the `MobileAdsClient` interface instead of in `SceneDelegate`.
//
//  Install once at app startup via `mobileAdsClient.installResumeAdHandler`.
//  Subscribes to `UIScene.didEnterBackgroundNotification` (stamps the
//  backgrounded time + warms the resume ad cache) and
//  `UIScene.willEnterForegroundNotification` (runs the full policy chain
//  then calls `AdsManager.shared.showAd(.appOpen(...))`).
//
//  Cold-start guard: `guard let backgroundedAt = ... else { return }` is
//  load-bearing. `willEnterForeground` fires on the very first scene
//  connection before any `didEnterBackground` has stamped a timestamp, so
//  without the guard the ad fires immediately on launch.
//

#if canImport(UIKit)
import ComposableArchitecture
import Foundation
import MobileAdsClient
import RemoteConfigClient
import UIKit

@MainActor
final class ResumeAdHandler {
    static let shared = ResumeAdHandler()

    private var isInstalled = false
    private var isPremiumProvider: @Sendable () -> Bool = { false }

    private var backgroundedAt: Date?
    private var lastAdShownAt: Date?
    private var sessionShows = 0
    private var showInFlight = false

    private init() {}

    func install(isPremium: @escaping @Sendable () -> Bool) {
        self.isPremiumProvider = isPremium
        guard !isInstalled else { return }
        isInstalled = true

        Task { @MainActor [weak self] in
            for await _ in NotificationCenter.default.notifications(
                named: UIScene.didEnterBackgroundNotification
            ) {
                await self?.onBackground()
            }
        }
        Task { @MainActor [weak self] in
            for await _ in NotificationCenter.default.notifications(
                named: UIScene.willEnterForegroundNotification
            ) {
                await self?.onForeground()
            }
        }
    }

    private func onBackground() async {
        backgroundedAt = .now
        @Dependency(\.remoteConfigClient) var remoteConfigClient
        guard
            let cfg = try? await remoteConfigClient.adConfigV2(),
            cfg.global.adsEnabled,
            cfg.global.appOpen.enabled,
            cfg.appOpens.resume.enabled
        else { return }
        let unitID = cfg.appOpens.resume.adUnitId
        guard !unitID.isEmpty else { return }
        // `shouldShowAd` auto-loads into the cache `showAd` reads from; a plain
        // `preloadAd` goes to the legacy ads_swift pool which `showAd` can't see.
        _ = await AdsManager.shared.shouldShowAd(.appOpen(unitID), rules: [])
    }

    private func onForeground() async {
        // Cold-start guard. `willEnterForeground` fires on first scene
        // connection before any `didEnterBackground` stamps `backgroundedAt`.
        guard let backgroundedAt = self.backgroundedAt else { return }
        guard !showInFlight, !isPremiumProvider() else { return }
        showInFlight = true
        defer { showInFlight = false }

        @Dependency(\.remoteConfigClient) var remoteConfigClient
        guard
            let cfg = try? await remoteConfigClient.adConfigV2(),
            cfg.global.adsEnabled,
            cfg.global.appOpen.enabled,
            cfg.appOpens.resume.enabled
        else { return }
        let policy = cfg.global.appOpen

        if Date.now.timeIntervalSince(backgroundedAt) < TimeInterval(policy.minBackgroundSeconds) { return }
        if let last = lastAdShownAt,
           Date.now.timeIntervalSince(last) < TimeInterval(policy.postAdSuppressionSeconds) {
            return
        }
        if policy.maxPerSession > 0, sessionShows >= policy.maxPerSession { return }

        let unitID = cfg.appOpens.resume.adUnitId
        guard !unitID.isEmpty,
              await AdsManager.shared.shouldShowAd(.appOpen(unitID), rules: [])
        else { return }

        lastAdShownAt = .now
        sessionShows += 1
        try? await AdsManager.shared.showAd(.appOpen(unitID))
        // Refill the pool for the next resume cycle.
        _ = await AdsManager.shared.shouldShowAd(.appOpen(unitID), rules: [])
    }
}
#endif
