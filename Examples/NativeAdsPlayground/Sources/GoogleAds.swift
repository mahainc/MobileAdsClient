//
//  GoogleAds.swift
//  NativeAdsPlayground
//

import ComposableArchitecture
import MobileAdsClientUI
import MobileAdsClient
import NativeAdClient
import Foundation
import SwiftUI

@Reducer
public struct GoogleAds: Sendable {
    @ObservableState
    public struct State: Equatable {
        public var banners: IdentifiedArrayOf<Banner.State> = []
        public var anchoredBanner: Banner.State?
        public var items: IdentifiedArrayOf<ItemWithAdReducer<Article, Banner>.State> = []
        public var native: Native.State?
    }

    public enum Action: BindableAction, Equatable {
        case binding(BindingAction<State>)
        case banners(IdentifiedActionOf<Banner>)
        case items(IdentifiedActionOf<ItemWithAdReducer<Article, Banner>>)
        case anchoredBanner(Banner.Action)
        case native(Native.Action)
        case onTask
    }

    public var body: some ReducerOf<Self> {
        BindingReducer()

        Reduce { state, action in
            switch action {
            case .onTask:
                let staticSize: StandardSize = .banner
                let staticType = BannerType.static(staticSize)

                let inlineAdaptiveSize: InlineAdaptiveSize = .currentOrientationInlineAdaptiveBannerWidth(UIScreen.main.bounds.size.width - 40)
                let inlineType = BannerType.inlineAdaptive(inlineAdaptiveSize)
                var array: [Banner.State] = []

                for _ in 0..<5 {
                    let staticBanner = Banner.State(adUnitID: "ca-app-pub-3940256099942544/2435281174", type: inlineType, layer: .thick)
                    array.append(staticBanner)
                }

                state.banners = .init(uniqueElements: array.enumerated().map(\.element))

                let anchoredSize: AnchoredAdaptiveSize = .currentOrientationAnchoredAdaptiveBannerWidth(UIScreen.main.bounds.size.width - 40)
                let config: CollapsibleConfig = .init(isCollapsible: true, anchorPosition: .top)
                let anchoredType = BannerType.anchoredAdaptive(anchoredSize, collapsible: nil)
                let anchoredBanner = Banner.State(adUnitID: "ca-app-pub-3940256099942544/2435281174", type: anchoredType, layer: .thick)
                state.anchoredBanner = anchoredBanner

                var items: [ItemWithAdReducer<Article, Banner>.State] = []
                for index in 0..<15 {
                    let article: ItemWithAdReducer<Article, Banner>.State = .content(Article.State())
                    items.append(article)
                    if index.isMultiple(of: 3) {
                        let banner: ItemWithAdReducer<Article, Banner>.State = .ad(Banner.State(adUnitID: "ca-app-pub-3940256099942544/2435281174", type: inlineType, layer: .thick))
                        items.append(banner)
                    }
                }

                state.items = .init(uniqueElements: items.enumerated().map(\.element))

                let options: [NativeAdClient.AnyAdLoaderOption] = [
                    NativeAdClient.AnyAdLoaderOption(NativeAdClient.MediaAspectRatioOption(ratio: .landscape)),
                    NativeAdClient.AnyAdLoaderOption(NativeAdClient.AdChoicesPositionOption(corner: .topRight)),
                ]

                let native = Native.State.init(adUnitID: "ca-app-pub-3940256099942544/3986624511", options: options)
                state.native = native

                return .none

            case .anchoredBanner:
                return .none

            case .banners:
                return .none

            default:
                return .none
            }
        }
        .forEach(\.banners, action: \.banners) {
            Banner()
        }
        .forEach(\.items, action: \.items) {
            ItemWithAdReducer()
        }
        .ifLet(\.anchoredBanner, action: \.anchoredBanner) {
            Banner()
        }
        .ifLet(\.native, action: \.native) {
            Native()
        }
    }

    public init() { }
}
