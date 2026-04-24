import Foundation
import Testing
import ComposableArchitecture
@testable import MobileAdsClient

// MARK: - Dummy reducer for Effect helpers

@Reducer
fileprivate struct Demo {
    @ObservableState
    struct State: Equatable {
        var showedPlacement = false
        var rewarded: Bool?
        var afterShow = false
    }

    enum Action: Equatable {
        case tapShowPlacement
        case afterShow
        case tapReward
        case rewardEarned
        case rewardDismissed
    }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .tapShowPlacement:
                return .showPlacement(.interRecorder, rules: []) { send in
                    await send(.afterShow)
                }

            case .afterShow:
                state.afterShow = true
                return .none

            case .tapReward:
                return .reward(.watchAds,
                    onReward: { send in await send(.rewardEarned) },
                    onDismissWithoutReward: { send in await send(.rewardDismissed) }
                )

            case .rewardEarned:
                state.rewarded = true
                return .none

            case .rewardDismissed:
                state.rewarded = false
                return .none
            }
        }
    }
}

@Suite("Effect.showPlacement + Effect.reward helpers")
struct EffectHelperTests {

    @Test("showPlacement invokes ATT + showPlacement then runs operation")
    @MainActor
    func showPlacementHappyPath() async {
        let attInvoked = LockIsolated(false)
        let showInvoked = LockIsolated<(MobileAdsClient.AdPlacement, [MobileAdsClient.AdRule])?>(nil)

        let store = TestStore(initialState: Demo.State()) {
            Demo()
        } withDependencies: {
            $0.mobileAdsClient = MobileAdsClient(
                requestTrackingAuthorizationIfNeeded: { attInvoked.setValue(true) },
                shouldShowAd: { _, _ in true },
                showAd: { _ in },
                preloadAd: { _ in },
                showPlacement: { placement, rules in
                    showInvoked.setValue((placement, rules))
                },
                preloadPlacement: { _ in },
                showRewardPlacement: { _ in true },
                isNativeAllPlacementEnabled: { _ in true },
                nativeAllAdUnitID: { "" },
                installRevenueBridge: { }
            )
        }

        await store.send(.tapShowPlacement)
        await store.receive(\.afterShow) { $0.afterShow = true }

        #expect(attInvoked.value == true)
        #expect(showInvoked.value?.0 == .interRecorder)
    }

    @Test("reward dispatches onReward when rewardedPlacement returns true")
    @MainActor
    func rewardEarned() async {
        let store = TestStore(initialState: Demo.State()) {
            Demo()
        } withDependencies: {
            $0.mobileAdsClient.requestTrackingAuthorizationIfNeeded = { }
            $0.mobileAdsClient.showRewardPlacement = { _ in true }
        }

        await store.send(.tapReward)
        await store.receive(\.rewardEarned) { $0.rewarded = true }
    }

    @Test("reward dispatches onDismissWithoutReward when placement returns false")
    @MainActor
    func rewardDismissed() async {
        let store = TestStore(initialState: Demo.State()) {
            Demo()
        } withDependencies: {
            $0.mobileAdsClient.requestTrackingAuthorizationIfNeeded = { }
            $0.mobileAdsClient.showRewardPlacement = { _ in false }
        }

        await store.send(.tapReward)
        await store.receive(\.rewardDismissed) { $0.rewarded = false }
    }
}
