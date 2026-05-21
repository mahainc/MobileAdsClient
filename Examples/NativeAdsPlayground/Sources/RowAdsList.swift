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
import UIKit

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
                var rectRowStyle = NativeAdClient.Configuration.Style.row
                rectRowStyle.actionButton.shape = .rect(cornerRadius: 10)

                // Rotate body display across all three modes so each renders
                // at least twice in the 6-ad fixture.
                let bodyDisplays: [NativeAdClient.Configuration.BodyDisplay] = [
                    .full,
                    .truncated(lines: 1),
                    .hidden,
                ]

                // Tighter insets to demonstrate the inset override at index 2
                // alongside default-padded neighbors.
                let tightInsets = UIEdgeInsets(top: 8, left: 10, bottom: 8, right: 10)
                let defaultInsets = UIEdgeInsets(top: 12, left: 14, bottom: 12, right: 14)

                // Oversized icon + taller CTA + roomier spacing to demonstrate
                // the `metrics` override at index 4. Other ads pass `nil` so
                // `Row.init` auto-resolves the layout-matched preset
                // (`Metrics.row` for inline, `Metrics.rowStacked` for stacked).
                let oversizedIcon = NativeAdClient.Configuration.Metrics(
                    iconSize: CGSize(width: 72, height: 72),
                    iconCornerRadius: 16,
                    ctaMinHeight: 48,
                    horizontalSpacing: 16,
                    verticalSpacing: 6
                )

                // Themed override at index 5 — exercises nested Style colors
                // (backgrounds / text / actionButton / attribution) AND the
                // new `containerCornerRadius` together so the wirings are
                // visibly proven in one ad.
                let themedStyle = NativeAdClient.Configuration.Style(
                    backgrounds: .init(
                        card: .gradient(
                            colors: [
                                UIColor.systemPurple.withAlphaComponent(0.30),
                                UIColor.systemPurple.withAlphaComponent(0.05)
                            ],
                            direction: .vertical
                        ),
                        content: .solid(.clear)
                    ),
                    text: .init(
                        headline: .systemPurple,
                        body: .label,
                        sponsor: .systemPurple.withAlphaComponent(0.7),
                        headlineFont: .system(size: 16, weight: .heavy, scaledFor: .headline),
                        bodyFont: .textStyle(.footnote),
                        sponsorFont: .textStyle(.caption1, weight: .semibold)
                    ),
                    actionButton: .init(
                        background: .systemPurple,
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

                // First half rect, second half capsule so both shapes are
                // visible in the initial viewport. Index 6 demos `.stackedFullCTA`
                // — same as `.stacked` but the CTA spans the full container width.
                let ads = (0..<7).map { index -> Native.State in
                    let row = NativeAdClient.Configuration.Row(
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
                        configuration: .init(row)
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
