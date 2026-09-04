//
//  PortraitAdsList.swift
//  NativeAdsPlayground
//
//  Demo feature for `PortraitNativeAdView`: a grid of portrait 9:16 "poster"
//  native cards. Uses Google's Native VIDEO test unit and requests portrait
//  creatives (a loader hint), starting video muted so a gridful of cards
//  doesn't play over each other. Two CTA treatments (capsule / rounded) are
//  alternated so both button shapes are exercised in the grid.
//

import ComposableArchitecture
import Foundation
import MobileAdsClientUI
import NativeAdClient
import UIKit

@Reducer
public struct PortraitAdsList: Sendable {
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
                        NativeAdClient.AnyAdLoaderOption(NativeAdClient.MediaAspectRatioOption(ratio: .portrait)),
                        NativeAdClient.AnyAdLoaderOption(NativeAdClient.VideoPlaybackOption(shouldStartMuted: true)),
                        NativeAdClient.AnyAdLoaderOption(NativeAdClient.AdChoicesPositionOption(corner: .topRight)),
                    ]

                    // No card background — only the media is rounded. The icon,
                    // title, advertiser + "Ad" and CTA are stacked below the media
                    // on the app background (dark text), CTA full-width. Two CTA
                    // shapes (capsule / rounded) exercise both button render paths.
                    let plainStyle = NativeAdClient.Configuration.Style(
                        backgrounds: .init(card: .solid(.clear), content: .solid(.clear)),
                        text: .init(
                            headline: .label,
                            body: .secondaryLabel,
                            sponsor: .secondaryLabel,
                            headlineFont: .system(size: 13, weight: .semibold, scaledFor: .subheadline),
                            sponsorFont: .system(size: 10, weight: .regular, scaledFor: .caption2)
                        ),
                        actionButton: .init(
                            background: .systemBlue,
                            title: .white,
                            shape: .capsule,
                            font: .system(size: 12, weight: .semibold, scaledFor: .subheadline),
                            contentInsets: .init(top: 6, left: 14, bottom: 6, right: 14)
                        ),
                        attribution: .init(
                            background: .tertiarySystemFill,
                            text: .secondaryLabel,
                            font: .textStyle(.caption2, weight: .bold)
                        )
                    )

                    let themedStyle = NativeAdClient.Configuration.Style(
                        backgrounds: .init(card: .solid(.clear), content: .solid(.clear)),
                        text: .init(
                            headline: .label,
                            body: .secondaryLabel,
                            sponsor: .systemIndigo,
                            headlineFont: .system(size: 13, weight: .bold, scaledFor: .subheadline),
                            sponsorFont: .system(size: 10, weight: .semibold, scaledFor: .caption2)
                        ),
                        actionButton: .init(
                            background: .systemIndigo,
                            title: .white,
                            shape: .rect(cornerRadius: 10),
                            font: .system(size: 12, weight: .bold, scaledFor: .subheadline),
                            contentInsets: .init(top: 6, left: 14, bottom: 6, right: 14)
                        ),
                        attribution: .init(
                            background: .systemYellow,
                            text: .black,
                            font: .textStyle(.caption2, weight: .bold)
                        )
                    )

                    let ads = (0..<6).map { index -> Native.State in
                        let portrait = NativeAdClient.Configuration.Portrait(
                            style: index.isMultiple(of: 2) ? plainStyle : themedStyle,
                            bodyDisplay: .hidden
                        )
                        return Native.State(
                            // Google's Native VIDEO test unit (the plain Native unit
                            // /3986624511 only ever serves images).
                            adUnitID: "ca-app-pub-3940256099942544/2521693316",
                            options: options,
                            configuration: .init(portrait)
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

    public init() {}
}
