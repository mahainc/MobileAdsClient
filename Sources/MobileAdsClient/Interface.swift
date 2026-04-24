// The Swift Programming Language
// https://docs.swift.org/swift-book

import ComposableArchitecture
import TCAInitializableReducer
import Foundation
#if canImport(UIKit)
import UIKit
#endif

@DependencyClient
public struct MobileAdsClient: Sendable {
    public var requestTrackingAuthorizationIfNeeded: @Sendable () async -> Void
	public var shouldShowAd: @Sendable (_ adType: MobileAdsClient.AdType, _ rules: [MobileAdsClient.AdRule]) async -> Bool = { _, _ in false }
    public var showAd: @Sendable (_ adType: MobileAdsClient.AdType) async throws -> Void

    // Placement-aware APIs — resolve the underlying ad unit ID from Remote Config and
    // include fallback logic (e.g. `.interRecorder` → `.interAll` when `extraKeys` allow it).
    public var preloadAd:          @Sendable (_ adType: MobileAdsClient.AdType) async -> Void
    public var showPlacement:      @Sendable (_ placement: MobileAdsClient.AdPlacement, _ rules: [MobileAdsClient.AdRule]) async throws -> Void
    public var preloadPlacement:   @Sendable (_ placement: MobileAdsClient.AdPlacement) async -> Void
    public var showRewardPlacement: @Sendable (_ placement: MobileAdsClient.RewardPlacement) async -> Bool = { _ in false }
    /// `true` when the `NativeAllPlacement` is enabled in Remote Config AND the global `nativeAll` ad unit is enabled.
    public var isNativeAllPlacementEnabled: @Sendable (_ placement: MobileAdsClient.NativeAllPlacement) async -> Bool = { _ in false }
    /// The current Remote-Config-resolved native-ad unit ID (empty string when unavailable or disabled).
    public var nativeAllAdUnitID: @Sendable () async -> String = { "" }
    /// Resolves the ad unit for a v2 native placement, honouring
    /// `global.adsEnabled` + `global.native.enabled` + the placement's own
    /// `.enabled` flag. Returns `""` when any gate is off or the placement is
    /// missing from Remote Config.
    public var nativeAdUnitID: @Sendable (_ placement: MobileAdsClient.NativeAdPlacement) async -> String = { _ in "" }

    /// Registers as the ads_swift `AdRevenueDelegate` and fans out each incoming revenue
    /// callback to `AdjustClient.trackRevenue` + `AnalyticClient.trackEvent("ad_revenue", …)`.
    /// Idempotent — call once at app startup (after `AdjustClient.initialize(_:)`).
    public var installRevenueBridge: @Sendable () async -> Void
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

// MARK: - Effect.showPlacement

extension Effect {
    /// Shows a placement-aware interstitial, then runs `operation`. Silently no-ops if
    /// Remote Config has the placement disabled or `enableAllAds` is false — callers always
    /// get their operation invoked.
    ///
    /// Parallel to `runWithAdCheck` but routes through `MobileAdsClient.showPlacement` so
    /// the ad unit ID + `interAll` fallback resolve from Remote Config.
    public static func showPlacement(
        _ placement: MobileAdsClient.AdPlacement,
        rules: [MobileAdsClient.AdRule] = [],
        priority: TaskPriority? = nil,
        then operation: @escaping @Sendable (_ send: Send<Action>) async throws -> Void = { _ in },
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
                        await adManager.requestTrackingAuthorizationIfNeeded()
                        try await adManager.showPlacement(placement, rules)
                        try await operation(send)
                    } catch is CancellationError {
                        return
                    } catch {
                        guard let handler else {
                            reportIssue(
                                """
                                An "Effect.showPlacement" returned from "\(fileID):\(line)" threw an unhandled error. …

                                All non-cancellation errors must be explicitly handled via the "catch" parameter \
                                on "Effect.showPlacement", or via a "do" block.
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

    /// Shows a rewarded-ad placement and dispatches to `onReward` when the user completes
    /// the ad (or ads are disabled — reward is granted). Dispatches to
    /// `onDismissWithoutReward` (if supplied) when the user dismissed without earning it.
    public static func reward(
        _ placement: MobileAdsClient.RewardPlacement,
        priority: TaskPriority? = nil,
        onReward: @escaping @Sendable (_ send: Send<Action>) async -> Void,
        onDismissWithoutReward: (@Sendable (_ send: Send<Action>) async -> Void)? = nil
    ) -> Self {
        withEscapedDependencies { escaped in
            .run(priority: priority) { send in
                await escaped.yield {
                    let adManager = DependencyValues._current.mobileAdsClient
                    await adManager.requestTrackingAuthorizationIfNeeded()
                    let rewarded = await adManager.showRewardPlacement(placement)
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

// MARK: - ItemWithAdReducer

@Reducer
public struct ItemWithAdReducer<Content: TCAInitializableReducer & Sendable, Ad: TCAInitializableReducer & Sendable>
where Content.State: Identifiable, Content.State: Sendable,
	  Ad.State: Identifiable, Ad.State: Sendable,
	  Content.Action: Sendable, Ad.Action: Sendable {
    
    @ObservableState
    public enum State: Identifiable {
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
    
    public enum Action {
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

extension ItemWithAdReducer.State: Equatable where Content.State: Equatable, Ad.State: Equatable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
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

extension ItemWithAdReducer.Action: Equatable where Content.Action: Equatable, Ad.Action: Equatable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
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

extension ItemWithAdReducer.State: Sendable where Content.State: Sendable, Ad.State: Sendable { }

extension ItemWithAdReducer.Action: Sendable where Content.Action: Sendable, Ad.Action: Sendable { }

extension ItemWithAdReducer: Sendable where Content: Sendable, Ad: Sendable { }

// MARK: - UI Helpers

#if canImport(UIKit)
@MainActor
extension UIApplication {
    public func topViewController(controller: UIViewController? = nil) -> UIViewController? {
        let controller = controller ?? keyWindow?.rootViewController
        if let navigationController = controller as? UINavigationController {
            return topViewController(controller: navigationController.visibleViewController)
        } else if let tabController = controller as? UITabBarController,
                  let selected = tabController.selectedViewController {
            return topViewController(controller: selected)
        } else if let presented = controller?.presentedViewController {
            return topViewController(controller: presented)
        }
        return controller
    }

    public var keyWindow: UIWindow? {
        return connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
    }
}
#endif
