//
//  NativeAdView.swift
//  MobileAdsClient
//
//  Created by Thanh Hai Khong on 6/2/25.
//

#if canImport(UIKit)
    import ComposableArchitecture
    import NativeAdClient
    import SwiftUI

    public struct NativeView: View {

        private let store: StoreOf<Native>

        public init(store: StoreOf<Native>) {
            self.store = store
        }

        private var customConfig: NativeAdClient.Configuration.Custom {
            if let c = store.configuration.base as? NativeAdClient.Configuration.Custom {
                return c
            }
            assertionFailure("NativeView requires Configuration.Custom, got \(type(of: store.configuration.base))")
            return .default
        }

        public var body: some View {
            _CustomNativeRepresentable(store: store, configuration: customConfig)
                .id(customConfig)
        }
    }

    private struct _CustomNativeRepresentable: UIViewRepresentable {
        let store: StoreOf<Native>
        let configuration: NativeAdClient.Configuration.Custom

        func makeUIView(context: Context) -> CustomNativeAdView {
            CustomNativeAdView(style: configuration.style, metrics: configuration.metrics)
        }

        func updateUIView(
            _ nativeAdView: CustomNativeAdView,
            context: Context
        ) {
            if nativeAdView.style != configuration.style {
                nativeAdView.style = configuration.style
            }
            guard let nativeAd = store.nativeAd else { return }
            // Skip re-bind when the same creative is already attached — matches the
            // Row/RowMedia/Compact wrappers. Without this guard, SwiftUI re-invokes
            // `updateUIView` on every store mutation and `configure` re-runs the
            // content animation in a feedback loop.
            guard nativeAdView.nativeAd !== nativeAd else { return }
            nativeAdView.configure(with: nativeAd)
            nativeAdView.invalidateIntrinsicContentSize()
        }

        func sizeThatFits(
            _ proposal: ProposedViewSize,
            uiView: CustomNativeAdView,
            context: Context
        ) -> CGSize? {
            guard let width = proposal.width, width > 0, width.isFinite else { return nil }
            let height = uiView.calculateTotalHeight(fittingWidth: width)
            return CGSize(width: width, height: height)
        }
    }
#endif
