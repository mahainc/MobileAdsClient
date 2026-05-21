//
//  RowMediaAdsList.swift
//  NativeAdsPlayground
//
//  Demo feature for `RowMediaNativeAdView`. Mirrors `RowAdsList`'s
//  layout/style/inset coverage (inline / stacked / stackedFullCTA, rect
//  vs capsule CTA, default vs themed style, etc.) but swaps the template
//  to `Configuration.RowMedia` so each card carries a 16:9 `MediaView`
//  above the row content.
//

import ComposableArchitecture
import Foundation
import MobileAdsClientUI
import NativeAdClient
import UIKit

@Reducer
public struct RowMediaAdsList: Sendable {
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

                // Row+Media template DOES want media options — the `MediaView`
                // is bound and locked to 16:9. The loader hint asks Google for
                // landscape creatives; the video option starts video muted so
                // multiple ads on one screen don't trample each other.
                let options: [NativeAdClient.AnyAdLoaderOption] = [
                    NativeAdClient.AnyAdLoaderOption(NativeAdClient.MediaAspectRatioOption(ratio: .landscape)),
                    NativeAdClient.AnyAdLoaderOption(NativeAdClient.VideoPlaybackOption(shouldStartMuted: true)),
                    NativeAdClient.AnyAdLoaderOption(NativeAdClient.AdChoicesPositionOption(corner: .topRight)),
                ]

                var rectRowStyle = NativeAdClient.Configuration.Style.row
                rectRowStyle.actionButton.shape = .rect(cornerRadius: 10)

                let bodyDisplays: [NativeAdClient.Configuration.BodyDisplay] = [
                    .full,
                    .truncated(lines: 1),
                    .hidden,
                ]

                let tightInsets = UIEdgeInsets(top: 8, left: 10, bottom: 8, right: 10)
                let defaultInsets = UIEdgeInsets(top: 12, left: 14, bottom: 12, right: 14)

                let oversizedIcon = NativeAdClient.Configuration.Metrics(
                    iconSize: CGSize(width: 72, height: 72),
                    iconCornerRadius: 16,
                    ctaMinHeight: 48,
                    horizontalSpacing: 16,
                    verticalSpacing: 6
                )

                let themedStyle = NativeAdClient.Configuration.Style(
                    backgrounds: .init(
                        card: .gradient(
                            colors: [
                                UIColor.systemTeal.withAlphaComponent(0.30),
                                UIColor.systemTeal.withAlphaComponent(0.05)
                            ],
                            direction: .vertical
                        ),
                        content: .solid(.clear)
                    ),
                    text: .init(
                        headline: .systemTeal,
                        body: .label,
                        sponsor: .systemTeal.withAlphaComponent(0.7),
                        headlineFont: .system(size: 16, weight: .heavy, scaledFor: .headline),
                        bodyFont: .textStyle(.footnote),
                        sponsorFont: .textStyle(.caption1, weight: .semibold)
                    ),
                    actionButton: .init(
                        background: .systemTeal,
                        title: .white,
                        shape: .rect(cornerRadius: 5),
                        font: .system(size: 14, weight: .bold, scaledFor: .subheadline)
                    ),
                    attribution: .init(
                        background: .systemYellow,
                        text: .black,
                        font: .textStyle(.caption2, weight: .bold)
                    )
                )
                let themedMetrics = NativeAdClient.Configuration.Metrics(
                    containerCornerRadius: 5
                )

                let ads = (0..<7).map { index -> Native.State in
                    let rowMedia = NativeAdClient.Configuration.RowMedia(
                        style: index == 5 ? themedStyle : (index < 3 ? rectRowStyle : .row),
                        bodyDisplay: bodyDisplays[index % bodyDisplays.count],
                        layout: index == 6
                            ? .stackedFullCTA
                            : (index.isMultiple(of: 2) ? .inline : .stacked),
                        insets: index == 2 ? tightInsets : defaultInsets,
                        metrics: index == 4 ? oversizedIcon : (index == 5 ? themedMetrics : nil)
                    )
                    return Native.State(
                        adUnitID: "ca-app-pub-3940256099942544/3986624511",
                        options: options,
                        configuration: .init(rowMedia)
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
