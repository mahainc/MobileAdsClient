//
//  NativeAdFeature.swift
//  MobileAdsClientUI
//
//  TCA reducer replacing the legacy `NativeAllAdManager` ObservableObject.
//  State holds the viewModel + loading flag; the double-load race that was
//  present in the check-then-act pattern is now closed by reducer dispatch.
//

import ComposableArchitecture
import MobileAdsClient
import SwiftUI
@preconcurrency import ads_swift

@Reducer
public struct NativeAdFeature: Sendable {

    @ObservableState
    public struct State: Equatable, Identifiable, Sendable {
        public let id: MobileAdsClient.NativeAllPlacement
        public var itemCount: Int
        public var isLoading: Bool
        public var adUnitID: String
        /// `true` once the reducer has resolved the Remote-Config ad unit ID and the
        /// view should create the `NativeAdViewModel` in its `.task`. Set by the reducer
        /// via `.loaded` and tested via `TestStore.receive`.
        public var hasLoadedViewModel: Bool

        public init(
            placement: MobileAdsClient.NativeAllPlacement,
            itemCount: Int = 0
        ) {
            self.id = placement
            self.itemCount = itemCount
            self.isLoading = false
            self.adUnitID = ""
            self.hasLoadedViewModel = false
        }
    }

    public enum Action: Sendable {
        /// Call from the list's `onChange(of: items.count)` — reducer decides whether
        /// to kick a load based on the density threshold.
        case updateItemCount(Int)
        /// Driven by `.updateItemCount` when the threshold is crossed. Also exposed
        /// publicly so callers can force-load (e.g. `.task` at first render).
        case loadIfReady
        /// Delegate-style completion once SDK lookup resolves.
        case loaded(adUnitID: String)
        /// Emitted when the placement is disabled in Remote Config (terminal).
        case disabled
    }

    /// Minimum items in the host list before a native ad is inserted. Matches the
    /// legacy `NativeAllAdManager.minItemsToShowAd` value.
    public let minItemsToShowAd: Int

    public init(minItemsToShowAd: Int = 6) {
        self.minItemsToShowAd = minItemsToShowAd
    }

    @Dependency(\.mobileAdsClient) var mobileAdsClient

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case let .updateItemCount(count):
                state.itemCount = count
                guard count >= minItemsToShowAd,
                      !state.hasLoadedViewModel,
                      !state.isLoading
                else { return .none }
                return .send(.loadIfReady)

            case .loadIfReady:
                guard !state.hasLoadedViewModel, !state.isLoading else { return .none }
                state.isLoading = true
                let placement = state.id
                return .run { send in
                    guard await mobileAdsClient.isNativeAllPlacementEnabled(placement) else {
                        await send(.disabled)
                        return
                    }
                    let unitID = await mobileAdsClient.nativeAllAdUnitID()
                    guard !unitID.isEmpty else {
                        await send(.disabled)
                        return
                    }
                    await send(.loaded(adUnitID: unitID))
                }

            case let .loaded(unitID):
                state.isLoading = false
                state.adUnitID = unitID
                state.hasLoadedViewModel = true
                // The actual NativeAdViewModel lives in state but is created lazily on
                // main by `NativeAdView` below so we don't need MainActor hopping here.
                return .none

            case .disabled:
                state.isLoading = false
                return .none
            }
        }
    }
}

// MARK: - View

/// SwiftUI view that renders a `NativeContentView` when the reducer reports a
/// loaded ad unit. Creates the `NativeAdViewModel` lazily on `.task` — keeps the
/// reducer free of reference-type state. Named `NativePlacementView` to avoid
/// collision with GoogleMobileAds' `NativeAdView` UIKit class.
public struct NativePlacementView: View {
    @Perception.Bindable var store: StoreOf<NativeAdFeature>
    let style: NativeAdViewStyle

    public init(store: StoreOf<NativeAdFeature>, style: NativeAdViewStyle = .homeAd) {
        self.store = store
        self.style = style
    }

    @State private var viewModel: NativeAdViewModel?

    public var body: some View {
        Group {
            if store.hasLoadedViewModel, let vm = viewModel {
                NativeContentView(nativeViewModel: vm, style: style)
            } else {
                EmptyView()
            }
        }
        .task(id: store.adUnitID) {
            guard store.hasLoadedViewModel, !store.adUnitID.isEmpty else { return }
            let vm = NativeAdViewModel(adUnitID: store.adUnitID)
            vm.refreshAd()
            self.viewModel = vm
        }
    }
}
