//
//  Live.swift
//  MobileAdsClient
//
//  Created by Thanh Hai Khong on 4/2/25.
//

#if canImport(UIKit)
import AdRevenueClient
import AppTrackingTransparency
import ComposableArchitecture
import MobileAdsClient
import RemoteConfigClient
@preconcurrency import GoogleMobileAds

extension MobileAdsClient: DependencyKey {
    public static let liveValue: Self = {
        return Self(
            requestTrackingAuthorizationIfNeeded: {
                guard ATTrackingManager.trackingAuthorizationStatus == .notDetermined else {
                    return
                }

                await withCheckedContinuation { continuation in
                    ATTrackingManager.requestTrackingAuthorization { _ in
                        continuation.resume(returning: ())
                    }
                }
            },
            shouldShowAd: { adType, rules in
                await AdsManager.shared.shouldShowAd(adType, rules: rules)
            },
            showAd: { adType in
                try await AdsManager.shared.showAd(adType)
            },
            preloadAd: { adType in
                await PlacementBridge.preloadAd(adType)
            },
            showPlacement: { placement, rules in
                guard await rules.allRulesSatisfied() else { return }
                try await PlacementBridge.show(interPlacement: placement)
            },
            preloadPlacement: { placement in
                await PlacementBridge.preload(interPlacement: placement)
            },
            showRewardPlacement: { placement in
                await PlacementBridge.show(rewardPlacement: placement)
            },
            isNativeAllPlacementEnabled: { placement in
                await PlacementBridge.isNativeAllEnabled(placement)
            },
            nativeAllAdUnitID: {
                await PlacementBridge.nativeAllAdUnitID()
            },
            nativeAdUnitID: { placement in
                await PlacementBridge.nativeAdUnitID(for: placement)
            },
            installRevenueBridge: {
                // No-op. Historically registered an ads_swift AdRevenueDelegate
                // to mirror paid events into AdRevenueClient. With ads_swift
                // removed, every format (appOpen / interstitial / rewarded /
                // native) attaches its own `paidEventHandler` at load time via
                // `BaseAdManager.attachPaidEventHandler` or
                // `NativeAdManager.adLoader(_:didReceive:)` — there is no
                // longer anything to bridge. Kept on the interface so
                // `AdsBootstrap.installingRevenueBridge` still calls through
                // without needing a phase rename.
            },
            installResumeAdHandler: { isPremium in
                await ResumeAdHandler.shared.install(isPremium: isPremium)
            },
            showNativeFullScreen: { adUnitID in
                await FullScreenNativePresenter.present(adUnitID: adUnitID)
            }
        )
    }()
}

/// Bridges MobileAdsClient's placement-aware closures to the underlying
/// `AdsManager` actor + BaseAdManager cache, using Remote Config as the source
/// of truth for ad unit IDs and placement flags.
enum PlacementBridge {
    /// Reads the `RemoteConfigClient` dependency at call time so each closure body sees the
    /// current injected value (test/preview swaps work correctly without a static cache).
    private static var remoteConfigClient: RemoteConfigClient {
        @Dependency(\.remoteConfigClient) var rc
        return rc
    }

    static func preloadAd(_ adType: MobileAdsClient.AdType) async {
        // `shouldShowAd` auto-loads into `AdsManager`'s BaseAdManager cache
        // when nothing is resident, which is exactly the "warm the slot" we
        // want. The returned Bool doesn't matter at preload time.
        _ = await AdsManager.shared.shouldShowAd(adType, rules: [])
    }

    static func preload(interPlacement placement: MobileAdsClient.AdPlacement) async {
        guard let unitID = await resolveInterstitialUnitID(for: placement), !unitID.isEmpty else { return }
        _ = await AdsManager.shared.shouldShowAd(.interstitial(unitID), rules: [])
    }

    static func show(interPlacement placement: MobileAdsClient.AdPlacement) async throws {
        guard let unitID = await resolveInterstitialUnitID(for: placement), !unitID.isEmpty else { return }
        guard await AdsManager.shared.shouldShowAd(.interstitial(unitID), rules: []) else { return }
        try await AdsManager.shared.showAd(.interstitial(unitID))
    }

    static func show(rewardPlacement placement: MobileAdsClient.RewardPlacement) async -> Bool {
        guard let v2 = try? await remoteConfigClient.adConfigV2(),
              v2.global.adsEnabled,
              v2.global.reward.enabled else { return true } // ads off → grant reward

        let placementEnabled: Bool = {
            switch placement {
            case .watchAds: return v2.rewards.watchAds.enabled
            }
        }()
        guard placementEnabled else { return true }

        let adUnitId = v2.rewards.watchAds.adUnitId
        guard !adUnitId.isEmpty else { return true }

        // Warm the ad, then present. If loading fails, grant the reward
        // anyway — consistent with the prior behaviour when ads were off.
        guard await AdsManager.shared.shouldShowAd(.rewarded(adUnitId), rules: []) else { return true }
        return await AdsManager.shared.showRewardAd(adUnitId)
    }

    /// Guards against double-resume when ads_swift fires both `onDismissed` and `onFailed`
    /// in pathological paths. MainActor-isolated — same context as the show call.
    @MainActor
    private final class ResumeOnceBox<T: Sendable> {
        private var resumed = false
        func resume(_ continuation: CheckedContinuation<T, Never>, with value: T) {
            guard !resumed else { return }
            resumed = true
            continuation.resume(returning: value)
        }
    }

    @MainActor
    private final class VoidResumeOnce {
        private var resumed = false
        func resume(_ continuation: CheckedContinuation<Void, Never>) {
            guard !resumed else { return }
            resumed = true
            continuation.resume()
        }
    }

    static func isNativeAllEnabled(_ placement: MobileAdsClient.NativeAllPlacement) async -> Bool {
        // Previously fanned out to `v2.placementGates.native.<placement>` for
        // per-screen render gates. That layer was dropped in the v2 schema —
        // the feature is gated by `natives.fallback.enabled` alone now.
        _ = placement
        guard let v2 = try? await remoteConfigClient.adConfigV2(),
              v2.global.adsEnabled,
              v2.global.native.enabled,
              v2.natives.fallback.enabled else {
            return false
        }
        return true
    }

    static func nativeAllAdUnitID() async -> String {
        guard let v2 = try? await remoteConfigClient.adConfigV2(),
              v2.global.adsEnabled,
              v2.global.native.enabled,
              v2.natives.fallback.enabled else {
            return ""
        }
        return resolvedNativeUnitId(configured: v2.natives.fallback.adUnitId)
    }

    /// Resolves a v2 native-ad placement against the current `AdConfigV2`. Honours
    /// `global.adsEnabled` + `global.native.enabled` + the slot's own `.enabled`
    /// flag. Returns `""` when any gate is off or the slot is missing.
    static func nativeAdUnitID(for placement: MobileAdsClient.NativeAdPlacement) async -> String {
        guard let v2 = try? await remoteConfigClient.adConfigV2(),
              v2.global.adsEnabled,
              v2.global.native.enabled else { return "" }

        let slot: RemoteConfigClient.AdConfigV2.NativePlacement = {
            switch placement {
            case .language:          return v2.natives.language
            case .languageSelected:  return v2.natives.languageSelected
            case let .introStep(n):  return v2.natives.intro["\(n)"] ?? .init()
            case .fallback:          return v2.natives.fallback
            }
        }()
        guard slot.enabled else { return "" }
        return resolvedNativeUnitId(configured: slot.adUnitId)
    }

    /// Swaps the configured production native unit for Google's universal test
    /// unit in DEBUG so simulator / TestFlight runs never generate invalid
    /// impressions against the real unit. Release keeps the Remote-Config value.
    /// Empty configured IDs still short-circuit to `""` so the gate matrix is
    /// identical across build configurations.
    private static func resolvedNativeUnitId(configured: String) -> String {
        guard !configured.isEmpty else { return "" }
        #if DEBUG
        return "ca-app-pub-3940256099942544/3986624511"
        #else
        return configured
        #endif
    }

    // MARK: - Placement resolution

    /// Resolves an interstitial `AdPlacement` to a unit ID by reading the v2
    /// `interstitials.<placement>` slot. Returns `nil` when any gate is off
    /// — including when the slot itself has `enabled: false`. Falls back to
    /// `global.interstitial.fallbackAdUnitId` only for the "enabled but unit
    /// ID missing" case, NOT for "user explicitly disabled this placement".
    /// Applies the DEBUG test-ID swap so simulator / TestFlight builds don't
    /// fire production units.
    private static func resolveInterstitialUnitID(
        for placement: MobileAdsClient.AdPlacement
    ) async -> String? {
        guard let v2 = try? await remoteConfigClient.adConfigV2(),
              v2.global.adsEnabled,
              v2.global.interstitial.enabled else { return nil }

        let slot: RemoteConfigClient.AdConfigV2.InterstitialPlacement = {
            switch placement {
            case .back:          return v2.interstitials.back
            case .home:          return v2.interstitials.home
            case .tab:           return v2.interstitials.tab
            case .paywallClose:  return v2.interstitials.paywallClose
            }
        }()

        // Placement kill-switch comes first — a disabled slot never shows,
        // with or without a configured unit ID. The fallback only rescues
        // "enabled but unit ID missing" payloads.
        guard slot.enabled else { return nil }
        let configured = slot.adUnitId.isEmpty
            ? v2.global.interstitial.fallbackAdUnitId
            : slot.adUnitId
        return resolvedInterstitialUnitId(configured: configured)
    }

    /// Mirror of `resolvedNativeUnitId(configured:)`: swap production IDs for
    /// Google's test interstitial unit in DEBUG so simulator traffic never
    /// fires a real impression.
    private static func resolvedInterstitialUnitId(configured: String) -> String {
        guard !configured.isEmpty else { return "" }
        #if DEBUG
        return "ca-app-pub-3940256099942544/4411468910"
        #else
        return configured
        #endif
    }
}
#endif
