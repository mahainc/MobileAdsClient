//
//  FullScreenAd.swift
//  NativeAdsPlayground
//
//  Demo feature for `FullScreenNativeAdView` — the full-screen native modal.
//  Loads a (video-capable) test native ad with the same loader options the
//  live `FullScreenNativePresenter` uses, then hands it to `FullScreenNativeView`
//  via a `.fullScreenCover`. Exercises the container-wrapped asset layout and
//  the click-during-video attribution fix end-to-end.
//

import ComposableArchitecture
import Foundation
import GoogleMobileAds
import NativeAdClient
import UIKit

@Reducer
public struct FullScreenAd: Sendable {
    // Google's test native ad unit — serves video creatives, which are required
    // to validate that taps on the CTA / headline / body during playback land on
    // the ad asset (not the media view).
    static let testAdUnitID = "ca-app-pub-3940256099942544/3986624511"

    @ObservableState
    public struct State: Equatable {
        public var nativeAd: NativeAd?
        public var isPresented: Bool = false
        public var isLoading: Bool = false
        public var errorText: String?
        // Auto-present once on first appearance so the modal is visible without a
        // tap (handy for simulator/UI-automation runs). Tapping the button again
        // after dismiss still works.
        public var didAutoPresent: Bool = false

        public init() {}
    }

    public enum Action: Equatable {
        case autoPresentIfNeeded
        case showTapped
        case loaded(NativeAd)
        case loadFailed(String)
        case dismissTapped
        case setPresented(Bool)

        public static func == (
            lhs: Action,
            rhs: Action
        ) -> Bool {
            switch (lhs, rhs) {
                case (.showTapped, .showTapped),
                    (.dismissTapped, .dismissTapped):
                    return true
                case let (.loaded(l), .loaded(r)):
                    return l === r
                case let (.loadFailed(l), .loadFailed(r)):
                    return l == r
                case let (.setPresented(l), .setPresented(r)):
                    return l == r
                default:
                    return false
            }
        }
    }

    @Dependency(\.nativeAdClient) var nativeAdClient

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
                case .autoPresentIfNeeded:
                    guard !state.didAutoPresent else { return .none }
                    state.didAutoPresent = true
                    return .send(.showTapped)

                case .showTapped:
                    guard !state.isLoading else { return .none }
                    state.isLoading = true
                    state.errorText = nil

                    // Mirror `FullScreenNativePresenter`'s options: AdChoices
                    // bottom-left (clear of the status bar and the bottom-right CTA)
                    // and video muted. Request portrait media — it fills the
                    // full-bleed screen edge-to-edge under `scaleAspectFill`.
                    let options: [NativeAdClient.AnyAdLoaderOption] = [
                        .init(NativeAdClient.AdChoicesPositionOption(corner: .bottomLeft)),
                        .init(NativeAdClient.VideoPlaybackOption(shouldStartMuted: true)),
                        .init(NativeAdClient.MediaAspectRatioOption(ratio: .portrait)),
                    ]

                    return .run { send in
                        let rootVC = await Self.rootViewController()
                        do {
                            let ad = try await nativeAdClient.loadAd(Self.testAdUnitID, rootVC, options, [])
                            await send(.loaded(ad))
                        } catch {
                            await send(.loadFailed(error.localizedDescription))
                        }
                    }

                case let .loaded(ad):
                    state.isLoading = false
                    state.nativeAd = ad
                    state.isPresented = true
                    return .none

                case let .loadFailed(message):
                    state.isLoading = false
                    state.errorText = message
                    return .none

                case .dismissTapped:
                    state.isPresented = false
                    state.nativeAd = nil
                    return .none

                case let .setPresented(isPresented):
                    // The `.fullScreenCover` binding writes `false` on interactive
                    // dismiss; funnel it through the same teardown as the close button.
                    if !isPresented {
                        state.isPresented = false
                        state.nativeAd = nil
                    }
                    return .none
            }
        }
    }

    @MainActor
    private static func rootViewController() -> UIViewController? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .rootViewController
    }

    public init() {}
}
