//
//  NativeAdsList.swift
//  NativeAdsPlayground
//

import ComposableArchitecture
import Foundation
import MobileAdsClientUI
import NativeAdClient

@Reducer
public struct NativeAdsList: Sendable {
    @ObservableState
    public struct State: Equatable {
        public var ads: IdentifiedArrayOf<Native.State> = []
    }

    public enum Action: Equatable {
        case onTask
        case refreshAllTapped
        case ads(IdentifiedActionOf<Native>)
    }

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .onTask:
                guard state.ads.isEmpty else { return .none }

                let options: [NativeAdClient.AnyAdLoaderOption] = [
                    NativeAdClient.AnyAdLoaderOption(NativeAdClient.MediaAspectRatioOption(ratio: .landscape)),
                    NativeAdClient.AnyAdLoaderOption(NativeAdClient.AdChoicesPositionOption(corner: .topRight)),
                ]

                let ads = (0..<6).map { _ in
                    Native.State(
                        adUnitID: "ca-app-pub-3940256099942544/3986624511",
                        options: options
                    )
                }
                state.ads = IdentifiedArrayOf(uniqueElements: ads)
                return .none

            case .refreshAllTapped:
                let effects: [Effect<Action>] = state.ads.map { ad in
                    .send(.ads(.element(id: ad.id, action: .refreshAd(ad.adUnitID))))
                }
                return .merge(effects)

            case .ads:
                return .none
            }
        }
        .forEach(\.ads, action: \.ads) {
            Native()
        }
    }

    public init() { }
}
