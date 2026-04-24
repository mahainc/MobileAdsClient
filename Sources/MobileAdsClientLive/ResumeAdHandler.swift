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
        log("backgroundedAt stamped; warming resume ad cache")
        @Dependency(\.remoteConfigClient) var remoteConfigClient
        guard
            let cfg = try? await remoteConfigClient.adConfigV2(),
            cfg.global.adsEnabled,
            cfg.global.appOpen.enabled,
            cfg.appOpens.resume.enabled
        else {
            log("preload skipped — gates off")
            return
        }
        let unitID = cfg.appOpens.resume.adUnitId
        guard !unitID.isEmpty else {
            log("preload skipped — empty adUnitId")
            return
        }
        // `shouldShowAd` auto-loads into the cache `showAd` reads from.
        let loaded = await AdsManager.shared.shouldShowAd(.appOpen(unitID), rules: [])
        log("preload finished adUnit=\(unitID) loaded=\(loaded)")
    }

    private func onForeground() async {
        // Cold-start guard. `willEnterForeground` fires on first scene
        // connection before any `didEnterBackground` stamps `backgroundedAt`.
        guard let backgroundedAt = self.backgroundedAt else {
            log("skip — cold start (no backgroundedAt stamp)")
            return
        }
        guard !showInFlight else {
            log("skip — show already in flight")
            return
        }
        guard !isPremiumProvider() else {
            log("skip — premium")
            return
        }
        showInFlight = true
        defer { showInFlight = false }

        @Dependency(\.remoteConfigClient) var remoteConfigClient
        guard let cfg = try? await remoteConfigClient.adConfigV2() else {
            log("skip — adConfigV2 load failed")
            return
        }
        guard cfg.global.adsEnabled else { log("skip — global.adsEnabled false"); return }
        guard cfg.global.appOpen.enabled else { log("skip — global.appOpen.enabled false"); return }
        guard cfg.appOpens.resume.enabled else { log("skip — appOpens.resume.enabled false"); return }
        let policy = cfg.global.appOpen

        // In DEBUG reduce the min-background gate to 2s so quick
        // background/foreground cycles during development still show the
        // ad. Release uses the Remote Config value verbatim.
        #if DEBUG
        let minBackground = min(2, policy.minBackgroundSeconds)
        #else
        let minBackground = policy.minBackgroundSeconds
        #endif

        let elapsed = Date.now.timeIntervalSince(backgroundedAt)
        if elapsed < TimeInterval(minBackground) {
            log("skip — minBackgroundSeconds=\(minBackground), elapsed=\(Int(elapsed))s")
            return
        }
        if let last = lastAdShownAt,
           Date.now.timeIntervalSince(last) < TimeInterval(policy.postAdSuppressionSeconds) {
            log("skip — postAdSuppression (cooldown from last show)")
            return
        }
        if policy.maxPerSession > 0, sessionShows >= policy.maxPerSession {
            log("skip — maxPerSession=\(policy.maxPerSession) reached")
            return
        }

        let unitID = cfg.appOpens.resume.adUnitId
        guard !unitID.isEmpty else {
            log("skip — appOpens.resume.adUnitId is empty")
            return
        }
        guard await AdsManager.shared.shouldShowAd(.appOpen(unitID), rules: []) else {
            log("skip — shouldShowAd returned false (load failed?)")
            return
        }

        log("showing resume app-open ad adUnit=\(unitID)")
        lastAdShownAt = .now
        sessionShows += 1
        try? await AdsManager.shared.showAd(.appOpen(unitID))
        // Refill the pool for the next resume cycle.
        _ = await AdsManager.shared.shouldShowAd(.appOpen(unitID), rules: [])
    }

    private func log(_ message: @autoclosure () -> String) {
        #if DEBUG
        print("[ResumeAdHandler] \(message())")
        #endif
    }
}
#endif
