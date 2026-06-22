// The Swift Programming Language
// https://docs.swift.org/swift-book

import ComposableArchitecture
import Foundation
import TCAInitializableReducer

#if canImport(UIKit)
    import UIKit
#endif

@DependencyClient
public struct MobileAdsClient: Sendable {
    public var requestTrackingAuthorizationIfNeeded: @Sendable () async -> Void
    public var shouldShowAd:
        @Sendable (_ adType: MobileAdsClient.AdType, _ rules: [MobileAdsClient.AdRule], _ keywords: [String]) async ->
            Bool = { _, _, _ in false }
    public var showAd: @Sendable (_ adType: MobileAdsClient.AdType, _ keywords: [String]) async throws -> Void

    /// Warms the SDK cache for `adType` so a subsequent `showAd(adType)` can
    /// present without a load delay. Callers resolve the ad unit ID upstream
    /// (typically from their own Remote Config decode) and pass it in.
    /// `keywords` are contextual targeting terms set on the underlying
    /// `Request` at load time (see Google Mobile Ads keyword targeting).
    public var preloadAd: @Sendable (_ adType: MobileAdsClient.AdType, _ keywords: [String]) async -> Void

    /// Presents a rewarded ad for the given unit ID and resumes with `true` if
    /// the user earned the reward, `false` if they dismissed without earning
    /// or the show failed. Caller decides whether to grant the reward when ads
    /// are off or the load fails.
    public var showRewardedAd: @Sendable (_ unitID: String, _ keywords: [String]) async -> Bool = { _, _ in false }

    /// Historically registered a paid-event bridge for the legacy ads_swift
    /// `AdRevenueDelegate`. Now a no-op: every ad format attaches its own
    /// `paidEventHandler` at load time (see `BaseAdManager.attachPaidEventHandler`
    /// and `NativeAdManager.adLoader(_:didReceive:)`) and publishes directly to
    /// `AdRevenueClient` → `AdRevenueSyncer`. Kept on the interface so
    /// `AdsBootstrap.installingRevenueBridge` still calls through.
    public var installRevenueBridge: @Sendable () async -> Void

    /// Presents a native ad as a full-screen modal via an in-house renderer
    /// (`FullScreenNativeAdView` in `MobileAdsClientUI`). Loads via
    /// `NativeAdClient`, publishes paid events through `AdRevenueClient`
    /// (`format: .native`, `source: .googleMobileAds`). The `async` call
    /// resumes once the user taps the close button — or immediately if the
    /// load fails — so reducers can `await` before continuing their flow.
    public var showNativeFullScreen: @Sendable (_ adUnitID: String, _ keywords: [String]) async -> Void = { _, _ in }
}

// MARK: - Backward-compatible overloads (no keywords)

extension MobileAdsClient {
    /// Convenience: presents `adType` with no contextual keywords.
    public func shouldShowAd(
        _ adType: MobileAdsClient.AdType,
        _ rules: [MobileAdsClient.AdRule]
    ) async -> Bool {
        await shouldShowAd(adType, rules, [])
    }

    /// Convenience: presents `adType` with no contextual keywords.
    public func showAd(_ adType: MobileAdsClient.AdType) async throws {
        try await showAd(adType, [])
    }

    /// Convenience: preloads `adType` with no contextual keywords.
    public func preloadAd(_ adType: MobileAdsClient.AdType) async {
        await preloadAd(adType, [])
    }

    /// Convenience: presents a rewarded ad with no contextual keywords.
    public func showRewardedAd(_ unitID: String) async -> Bool {
        await showRewardedAd(unitID, [])
    }

    /// Convenience: presents a full-screen native ad with no contextual keywords.
    public func showNativeFullScreen(_ adUnitID: String) async {
        await showNativeFullScreen(adUnitID, [])
    }
}

extension Effect {
    public static func runWithAdCheck(
        adType: MobileAdsClient.AdType,
        rules: [MobileAdsClient.AdRule] = [],
        priority: TaskPriority? = nil,
        operation: @escaping @Sendable (_ send: Send<Action>) async throws -> Void,
        catch handler: (@Sendable (_ error: any Error, _ send: Send<Action>) async -> Void)? = nil,
        fileID: StaticString = #fileID,
        filePath: StaticString = #filePath,
        line: UInt = #line,
        column: UInt = #column
    ) -> Self {
        withEscapedDependencies { escaped in
            .run(priority: priority) { send in
                await escaped.yield {
                    do {
                        let adManager = DependencyValues._current.mobileAdsClient
                        if await adManager.shouldShowAd(adType, rules) {
                            await adManager.requestTrackingAuthorizationIfNeeded()
                            try await adManager.showAd(adType)
                        }
                        try await operation(send)
                    } catch is CancellationError {
                        return
                    } catch {
                        guard let handler else {
                            reportIssue(
                                """
                                An "Effect.runWithAdCheck" returned from "\(fileID):\(line)" threw an unhandled error. …

                                All non-cancellation errors must be explicitly handled via the "catch" parameter \
                                on "Effect.runWithAdCheck", or via a "do" block.
                                """,
                                fileID: fileID,
                                filePath: filePath,
                                line: line,
                                column: column
                            )
                            return
                        }
                        await handler(error, send)
                    }
                }
            }
        }
    }
}

// MARK: - Effect.reward

extension Effect {
    /// Presents a rewarded ad for `unitID` and dispatches to `onReward` when the
    /// user earns the reward. Dispatches to `onDismissWithoutReward` (if
    /// supplied) when they dismiss without earning. Caller resolves the unit ID
    /// upstream from its own config.
    public static func reward(
        unitID: String,
        priority: TaskPriority? = nil,
        onReward: @escaping @Sendable (_ send: Send<Action>) async -> Void,
        onDismissWithoutReward: (@Sendable (_ send: Send<Action>) async -> Void)? = nil
    ) -> Self {
        withEscapedDependencies { escaped in
            .run(priority: priority) { send in
                await escaped.yield {
                    let adManager = DependencyValues._current.mobileAdsClient
                    await adManager.requestTrackingAuthorizationIfNeeded()
                    let rewarded = await adManager.showRewardedAd(unitID)
                    if rewarded {
                        await onReward(send)
                    } else {
                        await (onDismissWithoutReward ?? { _ in })(send)
                    }
                }
            }
        }
    }
}

// MARK: - Either

@Reducer
public struct Either<Content: TCAInitializableReducer & Sendable, Ad: TCAInitializableReducer & Sendable>
where
    Content.State: Identifiable, Content.State: Sendable,
    Ad.State: Identifiable, Ad.State: Sendable,
    Content.Action: Sendable, Ad.Action: Sendable
{

    @ObservableState
    public enum State: Identifiable, Sendable {
        case content(Content.State)
        case ad(Ad.State)

        public var id: AnyHashable {
            switch self {
                case .content(let contentState):
                    return contentState.id

                case .ad(let adState):
                    return adState.id
            }
        }
    }

    public enum Action: Sendable {
        case content(Content.Action)
        case ad(Ad.Action)
    }

    public var body: some ReducerOf<Self> {
        Scope(state: \.content, action: \.content) {
            Content()
        }

        Scope(state: \.ad, action: \.ad) {
            Ad()
        }
    }

    public init() {}
}

// MARK: - Equatable

extension Either.State: Equatable where Content.State: Equatable, Ad.State: Equatable {
    public static func == (
        lhs: Self,
        rhs: Self
    ) -> Bool {
        switch (lhs, rhs) {
            case (.content(let lhsContent), .content(let rhsContent)):
                return lhsContent == rhsContent
            case (.ad(let lhsAd), .ad(let rhsAd)):
                return lhsAd == rhsAd
            default:
                return false
        }
    }
}

extension Either.Action: Equatable where Content.Action: Equatable, Ad.Action: Equatable {
    public static func == (
        lhs: Self,
        rhs: Self
    ) -> Bool {
        switch (lhs, rhs) {
            case (.content(let lhsContent), .content(let rhsContent)):
                return lhsContent == rhsContent
            case (.ad(let lhsAd), .ad(let rhsAd)):
                return lhsAd == rhsAd
            default:
                return false
        }
    }
}

// MARK: - Sendable

extension Either: Sendable where Content: Sendable, Ad: Sendable {}

// MARK: - UI Helpers

#if canImport(UIKit)
    @MainActor
    extension UIApplication {
        public func topViewController(controller: UIViewController? = nil) -> UIViewController? {
            let controller = controller ?? keyWindow?.rootViewController
            if let navigationController = controller as? UINavigationController {
                return topViewController(controller: navigationController.visibleViewController)
            } else if let tabController = controller as? UITabBarController,
                let selected = tabController.selectedViewController
            {
                return topViewController(controller: selected)
            } else if let presented = controller?.presentedViewController {
                return topViewController(controller: presented)
            }
            return controller
        }

        public var keyWindow: UIWindow? {
            return
                connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap { $0.windows }
                .first { $0.isKeyWindow }
        }
    }
#endif
