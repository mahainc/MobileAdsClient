//
//  Extensions.swift
//  MobileAdsClient
//
//  Effect conveniences, no-keyword overloads, the `Either` reducer, and the
//  UIKit top-view-controller helper. Consolidated out of the per-client split so
//  the dependency surface (`Interface.swift`) stays free of glue.
//

import ComposableArchitecture
import Foundation
import TCAInitializableReducer

#if canImport(UIKit)
    import UIKit
#endif

// MARK: - Effect.runWithAdCheck

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
                        if await adManager.shouldShowFullScreenAd(adType, rules) {
                            try await adManager.showFullScreenAd(adType)
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

// MARK: - MobileAdsClient no-keyword overloads

extension MobileAdsClient {
    /// Convenience: gate `adType` with no contextual keywords.
    public func shouldShowFullScreenAd(
        _ adType: AdType,
        _ rules: [AdRule]
    ) async -> Bool {
        await shouldShowFullScreenAd(adType, rules, [])
    }

    /// Convenience: presents `adType` with no contextual keywords, no completion.
    @discardableResult
    public func showFullScreenAd(_ adType: AdType) async throws -> AdOutcome {
        try await showFullScreenAd(adType, [], nil)
    }

    /// Convenience: presents `adType` with a completion handler, no keywords.
    @discardableResult
    public func showFullScreenAd(
        _ adType: AdType,
        onComplete: CompletionHandler?
    ) async throws -> AdOutcome {
        try await showFullScreenAd(adType, [], onComplete)
    }

    /// Convenience: presents `adType` with keywords and an optional completion handler.
    @discardableResult
    public func showFullScreenAd(
        _ adType: AdType,
        _ keywords: [String],
        onComplete: CompletionHandler? = nil
    ) async throws -> AdOutcome {
        try await showFullScreenAd(adType, keywords, onComplete)
    }

    /// Convenience: warms `adType` with no contextual keywords.
    public func warmFullScreenAd(_ adType: AdType) async {
        await warmFullScreenAd(adType, [])
    }

    // TEMPORARILY DISABLED with the `registerPreloads` endpoint (see Interface.swift).
    // /// Convenience: registers units with a default buffer size of 2.
    // public func registerPreloads(_ adTypes: [AdType]) async {
    //     await registerPreloads(adTypes, 2)
    // }

    /// Presents a rewarded ad for `unitID` and returns whether the user earned the
    /// reward — `false` if they dismissed without earning or nothing could present.
    /// A convenience over `showFullScreenAd(.rewarded(unitID))` that swallows the
    /// not-ready throw as `false`, preserving grant-friendly ergonomics.
    public func showRewardedAd(
        _ unitID: String,
        _ keywords: [String] = []
    ) async -> Bool {
        (try? await showFullScreenAd(.rewarded(unitID), keywords, nil))?.earnedReward ?? false
    }

    /// As `showRewardedAd(_:_:)`, with a post-show completion handler.
    public func showRewardedAd(
        _ unitID: String,
        onComplete: CompletionHandler?
    ) async -> Bool {
        (try? await showFullScreenAd(.rewarded(unitID), [], onComplete))?.earnedReward ?? false
    }
}

// MARK: - Either

/// A reducer that is either content or an ad. Unrelated to the ad client
/// dependency surface; kept here as a reusable glue reducer.
@Reducer
public struct Either<Content: TCAInitializableReducer & Sendable, Ad: TCAInitializableReducer & Sendable>
where
    Content.State: Identifiable, Content.State: Sendable,
    Ad.State: Identifiable, Ad.State: Sendable,
    Content.State.ID: Sendable, Ad.State.ID: Sendable,
    Content.Action: Sendable, Ad.Action: Sendable
{

    @ObservableState
    public enum State: Identifiable, Sendable {
        case content(Content.State)
        case ad(Ad.State)

        /// A concrete, `Sendable` id. This was `AnyHashable`, which the standard
        /// library ships as an `@available(*, unavailable)` `Sendable`
        /// conformance — forcing every consumer that sends `.element(id:)`
        /// across an effect boundary to add an `@unchecked Sendable` shim.
        /// Distinguishing the two cases also stops a content id and an ad id
        /// that share an underlying value from colliding in an `IdentifiedArray`.
        public enum ID: Hashable, Sendable {
            case content(Content.State.ID)
            case ad(Ad.State.ID)
        }

        public var id: ID {
            switch self {
                case .content(let contentState):
                    return .content(contentState.id)

                case .ad(let adState):
                    return .ad(adState.id)
            }
        }
    }

    public enum Action: Sendable {
        case content(Content.Action)
        case ad(Ad.Action)
    }

    public var body: some ReducerOf<Self> {
        EmptyReducer()
            .ifCaseLet(\.content, action: \.content) {
                Content()
            }
            .ifCaseLet(\.ad, action: \.ad) {
                Ad()
            }
    }

    public init() {}
}

// MARK: - Either Equatable

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

// MARK: - Either Sendable

extension Either: Sendable where Content: Sendable, Ad: Sendable {}

// MARK: - UIApplication.topViewController

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
