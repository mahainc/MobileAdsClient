import Foundation
import Testing
import ComposableArchitecture
@testable import MobileAdsClient
@testable import MobileAdsClientUI

@Suite("NativeAdFeature reducer")
struct NativeAdFeatureTests {

    @Test("updateItemCount below threshold does not trigger load")
    @MainActor
    func belowThreshold() async {
        let store = TestStore(
            initialState: NativeAdFeature.State(placement: .nativeAppearance)
        ) {
            NativeAdFeature(minItemsToShowAd: 6)
        } withDependencies: {
            $0.mobileAdsClient = .testValue
        }

        await store.send(.updateItemCount(3)) {
            $0.itemCount = 3
        }
    }

    @Test("updateItemCount at/above threshold loads ad unit ID from Remote Config")
    @MainActor
    func aboveThresholdLoads() async {
        let store = TestStore(
            initialState: NativeAdFeature.State(placement: .nativeAppearance)
        ) {
            NativeAdFeature(minItemsToShowAd: 6)
        } withDependencies: {
            $0.mobileAdsClient = .testValue    // isNativeAllPlacementEnabled = true, nativeAllAdUnitID = "test-native-unit"
        }

        await store.send(.updateItemCount(6)) { $0.itemCount = 6 }
        await store.receive(\.loadIfReady) { $0.isLoading = true }
        await store.receive(\.loaded) {
            $0.isLoading = false
            $0.adUnitID = "test-native-unit"
            $0.hasLoadedViewModel = true
        }
    }

    @Test("disabled placement transitions to .disabled, no unit ID set")
    @MainActor
    func disabledPlacement() async {
        let store = TestStore(
            initialState: NativeAdFeature.State(placement: .nativeAppearance)
        ) {
            NativeAdFeature(minItemsToShowAd: 6)
        } withDependencies: {
            $0.mobileAdsClient = .adsDisabled   // isNativeAllPlacementEnabled = false
        }

        await store.send(.updateItemCount(6)) { $0.itemCount = 6 }
        await store.receive(\.loadIfReady) { $0.isLoading = true }
        await store.receive(\.disabled) { $0.isLoading = false }
    }

    @Test("empty ad unit ID (enabled but unit empty) transitions to .disabled")
    @MainActor
    func emptyUnitTreatedAsDisabled() async {
        let store = TestStore(
            initialState: NativeAdFeature.State(placement: .nativeAppearance)
        ) {
            NativeAdFeature(minItemsToShowAd: 6)
        } withDependencies: {
            $0.mobileAdsClient.isNativeAllPlacementEnabled = { _ in true }
            $0.mobileAdsClient.nativeAllAdUnitID = { "" }
        }

        await store.send(.updateItemCount(6)) { $0.itemCount = 6 }
        await store.receive(\.loadIfReady) { $0.isLoading = true }
        await store.receive(\.disabled) { $0.isLoading = false }
    }

    @Test("loadIfReady is idempotent once hasLoadedViewModel is true")
    @MainActor
    func idempotentLoad() async {
        var state = NativeAdFeature.State(placement: .nativeAppearance)
        state.hasLoadedViewModel = true

        let store = TestStore(initialState: state) {
            NativeAdFeature(minItemsToShowAd: 6)
        } withDependencies: {
            $0.mobileAdsClient = .testValue
        }

        // Second trigger after load: no state change, no effect.
        await store.send(.updateItemCount(10)) { $0.itemCount = 10 }
        await store.send(.loadIfReady)
    }
}
