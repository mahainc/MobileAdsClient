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
@preconcurrency import ads_swift
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
                await RevenueBridge.shared.install()
            },
            installResumeAdHandler: { isPremium in
                await ResumeAdHandler.shared.install(isPremium: isPremium)
            }
        )
    }()
}

/// Bridges ads_swift's `AdRevenueDelegate` onto `AdRevenueClient`, which fans
/// events out to Adjust + Analytics via a long-lived TCA subscriber. Keeping
/// this thin ensures MobileAdsClientLive stays SDK-only and doesn't know about
/// Adjust or Firebase Analytics.
@MainActor
private final class RevenueBridge: NSObject, AdRevenueDelegate {
    static let shared = RevenueBridge()
    private var isInstalled = false

    func install() {
        guard !isInstalled else { return }
        AdRevenueTracker.shared.delegate = self
        isInstalled = true
    }

    nonisolated func didTrackAdRevenue(adValue: AdValue, adUnit: String, adType: ads_swift.AdType) {
        @Dependency(\.adRevenueClient) var adRevenueClient

        // Extract every Sendable primitive eagerly — the publish closure below
        // must not capture `AdValue` (not Sendable) or `adType` (from ads_swift,
        // `@preconcurrency` elided its Sendable conformance).
        adRevenueClient.publish(AdRevenueEvent(
            amount: Double(truncating: adValue.value),
            currency: adValue.currencyCode,
            adUnitId: adUnit,
            format: AdRevenueEvent.AdFormat(from: adType),
            source: .adsSwift,
            receivedAt: .now
        ))
    }
}

private extension AdRevenueEvent.AdFormat {
    init(from adType: ads_swift.AdType) {
        switch adType {
        case .openResume:           self = .appOpen
        case .interstitial,
             .rewardedInterstitial: self = .interstitial
        case .rewarded:             self = .rewarded
        case .banner:               self = .banner
        case .native,
             .nativeFullScreen:     self = .native
        }
    }
}

/// Bridges MobileAdsClient's placement-aware closures to the underlying ads_swift `AdsManager`
/// using Remote Config as the source of truth for ad unit IDs and placement flags.
/// Lives in this target so MobileAdsClient (the interface) stays SDK-free.
enum PlacementBridge {
    /// Reads the `RemoteConfigClient` dependency at call time so each closure body sees the
    /// current injected value (test/preview swaps work correctly without a static cache).
    private static var remoteConfigClient: RemoteConfigClient {
        @Dependency(\.remoteConfigClient) var rc
        return rc
    }

    static func preloadAd(_ adType: MobileAdsClient.AdType) async {
        switch adType {
        case let .interstitial(id):
            ads_swift.AdsManager.shared.preloadInterstitialAd(adUnitID: id, opacity: 1)
        case let .appOpen(id):
            ads_swift.AdsManager.shared.preloadAppOpenAd(adUnitID: id, opacity: 1)
        case let .rewarded(id):
            ads_swift.AdsManager.shared.preloadRewardedAd(adUnitID: id, opacity: 1)
        }
    }

    static func preload(interPlacement placement: MobileAdsClient.AdPlacement) async {
        guard let adConfig = try? await remoteConfigClient.adConfig() else { return }
        guard adConfig.showAllAds else { return }
        let interAll = adConfig.adUnitsConfig.interAll
        guard interAll.enable, interAll.opacity > 0 else { return }
        ads_swift.AdsManager.shared.preloadInterstitialAd(
            adUnitID: interAll.id,
            opacity: interAll.opacity
        )
    }

    static func show(interPlacement placement: MobileAdsClient.AdPlacement) async throws {
        guard let adConfig = try? await remoteConfigClient.adConfig(),
              adConfig.showAllAds else { return }

        let (unitConfig, useInterAll) = resolveInter(placement: placement, adConfig: adConfig)
        guard unitConfig.enable else { return }

        let interAll = adConfig.adUnitsConfig.interAll
        let chosen: RemoteConfigClient.AdUnitConfig = (useInterAll && interAll.opacity > 0) ? interAll : unitConfig

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            Task { @MainActor in
                let box = VoidResumeOnce()
                ads_swift.AdsManager.shared.showInterstitialAd(
                    adUnitID: chosen.id,
                    onDismissed: { box.resume(continuation) },
                    onFailed: { _ in box.resume(continuation) },
                    showLoading: false
                )
            }
        }
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

        return await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            Task { @MainActor in
                let box = ResumeOnceBox<Bool>()
                ads_swift.AdsManager.shared.showRewardedAd(
                    adUnitID: adUnitId,
                    onDismissed: { rewarded in box.resume(continuation, with: rewarded) },
                    onFailed: { _ in box.resume(continuation, with: true) }
                )
            }
        }
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

    /// Resolves an `AdPlacement` to its `AdUnitConfig`. Returns `useInterAll = true` when
    /// the placement should fall back to the pooled `interAll` unit instead of its own.
    /// The new recorder-app schema has no `interAll.extraKeys`, so fallback defaults to
    /// "use interAll when opacity > 0".
    private static func resolveInter(
        placement: MobileAdsClient.AdPlacement,
        adConfig: RemoteConfigClient.AdConfig
    ) -> (unit: RemoteConfigClient.AdUnitConfig, useInterAll: Bool) {
        let units = adConfig.adUnitsConfig
        let extras = units.interAll.extraKeys ?? [:]

        switch placement {
        case .interRecorder:
            return (units.interRecorder, extras["interRecorder"] ?? true)
        }
    }
}
#endif
