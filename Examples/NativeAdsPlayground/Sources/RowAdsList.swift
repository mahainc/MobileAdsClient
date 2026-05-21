//
//  RowAdsList.swift
//  NativeAdsPlayground
//
//  Demo feature for `RowNativeAdView`. Builds 6 `Native.State` instances
//  with `adStyle: .row`, alternating `rowLayout` between `.inline` and
//  `.stacked` so the two layouts render back-to-back in one list.
//

import ComposableArchitecture
import Foundation
import MobileAdsClientUI
import NativeAdClient

@Reducer
public struct RowAdsList: Sendable {
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

                // Row template is icon-only — do NOT pass media-related
                // options (e.g. `MediaAspectRatioOption`) or AdMob's debug
                // validator will flag the unbound mediaView.
                let options: [NativeAdClient.AnyAdLoaderOption] = [
                    NativeAdClient.AnyAdLoaderOption(NativeAdClient.AdChoicesPositionOption(corner: .topRight)),
                ]

                // Variant of `.row` that uses a rounded-rectangle CTA instead
                // of the default capsule — used by the second half of the
                // list so both shapes render side by side.
                var rectRow = NativeAdClient.AdStyle.row
                rectRow.buttonShape = .rect(cornerRadius: 10)

                // First half rect, second half capsule so both shapes are
                // visible in the initial viewport.
                let ads = (0..<6).map { index in
                    Native.State(
                        adUnitID: "ca-app-pub-3940256099942544/3986624511",
                        options: options,
                        adStyle: index < 3 ? rectRow : .row,
                        rowLayout: index.isMultiple(of: 2) ? .inline : .stacked
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
