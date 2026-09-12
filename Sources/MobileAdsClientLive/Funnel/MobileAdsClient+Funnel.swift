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
                slotRef: invocation.placement.slotRef,
                nativeStyle: invocation.nativeStyle.map { MobileAdsClient.NativeFullScreenStyle($0) }
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

extension MobileAdsClient.NativeFullScreenStyle {
    /// The longest close gate the funnel is allowed to impose. A guest that asks
    /// for more has almost certainly sent a wrong unit, and a user stuck behind an
    /// unclosable ad is worse than a short gate.
    fileprivate static let maximumCountdownSeconds = 30

    private static let millisecondsPerSecond = 1000
    /// Half a second, added before the integer divide so the result rounds to the
    /// nearest second instead of always truncating down.
    private static let roundingOffsetMilliseconds = millisecondsPerSecond / 2

    /// The funnel measures the close gate in milliseconds; the renderer counts whole
    /// seconds, because what it shows is "closes in Ns". Rounding to nearest keeps
    /// 2 999 ms reading as the 3 s the guest meant, and `0` stays `0` — the one value
    /// that means "no gate at all" rather than "a very short one".
    fileprivate init(_ funnelStyle: FunnelClient.Ad.NativeStyle) {
        let milliseconds = Int(funnelStyle.closeDelayMs)
        let seconds = (milliseconds + Self.roundingOffsetMilliseconds) / Self.millisecondsPerSecond
        self.init(
            closeCountdownSeconds: min(seconds, Self.maximumCountdownSeconds),
            closeHitSlop: CGFloat(max(0, funnelStyle.closeHitSlop))
        )
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
