#if canImport(UIKit)
import FunnelClient
import MobileAdsClient
import UIKit

extension MobileAdsClient: FunnelClient.Ad.Providing {
    public static let funnelPresentationGuard = FunnelClient.Ad.PresentationGuard()

    public var presentationGuard: FunnelClient.Ad.PresentationGuard {
        Self.funnelPresentationGuard
    }

    public func preload(
        unitID: String,
        adType: FunnelClient.AdType
    ) {
        guard let mobileAdType = MobileAdsClient.AdType.funnelAdType(adType, unitID: unitID) else {
            return
        }
        Task {
            await warmFullScreenAd(mobileAdType, [])
        }
    }

    public func ensureLoaded(
        unitID: String,
        adType: FunnelClient.AdType
    ) async -> Bool {
        guard let mobileAdType = MobileAdsClient.AdType.funnelAdType(adType, unitID: unitID) else {
            return false
        }
        return await shouldShowFullScreenAd(mobileAdType, [], [])
    }

    public func present(
        _ invocation: FunnelClient.Ad.Invocation,
        onComplete: @escaping @Sendable (FunnelClient.Ad.PresentationOutcome) -> Void
    ) async {
        guard
            let mobileAdType = MobileAdsClient.AdType.funnelAdType(
                invocation.action,
                unitID: invocation.placement.unitID
            )
        else {
            onComplete(.failOpen("unsupported_action"))
            return
        }

        do {
            let requester = MobileAdsClient.AdRequester(
                featureID: invocation.placement.featureID,
                slotRef: invocation.placement.slotRef
            )
            let outcome = try await showFullScreenAd(mobileAdType, [], requester, nil)
            onComplete(.dismissed(proceeded: outcome != .rewardNotEarned))
        } catch {
            onComplete(
                invocation.action == .showRewarded
                    ? FunnelClient.Ad.PresentationOutcome(
                        proceeded: false,
                        didDismiss: false,
                        failureReason: "ad_not_ready"
                    )
                    : .failOpen("ad_not_ready")
            )
        }
    }

    public func awaitPresentable() async -> Bool {
        await MainActor.run {
            UIApplication.shared.topViewController() != nil
        }
    }
}

extension MobileAdsClient.AdType {
    fileprivate static func funnelAdType(
        _ type: FunnelClient.AdType,
        unitID: String
    ) -> Self? {
        switch type {
            case .interstitial: return .interstitial(unitID)
            case .rewarded: return .rewarded(unitID)
            case .native: return .nativeFullScreen(unitID)
            case .resume: return .appOpen(unitID)
            case .unspecified, .banner: return nil
        }
    }

    fileprivate static func funnelAdType(
        _ action: FunnelClient.Action,
        unitID: String
    ) -> Self? {
        switch action {
            case .showInterstitial: return .interstitial(unitID)
            case .showBanner: return nil
            case .showRewarded: return .rewarded(unitID)
            case .showNative: return .nativeFullScreen(unitID)
            case .showResume: return .appOpen(unitID)
            default: return nil
        }
    }
}
#endif
