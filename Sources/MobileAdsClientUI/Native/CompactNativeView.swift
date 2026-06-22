//
//  CompactNativeView.swift
//  MobileAdsClient
//

#if canImport(UIKit)
    import ComposableArchitecture
    import NativeAdClient
    import SwiftUI

    public struct CompactNativeView: View {

        private let store: StoreOf<Native>

        public init(store: StoreOf<Native>) {
            self.store = store
        }

        private var compactConfig: NativeAdClient.Configuration.Compact {
            if let c = store.configuration.base as? NativeAdClient.Configuration.Compact {
                return c
            }
            assertionFailure(
                "CompactNativeView requires Configuration.Compact, got \(type(of: store.configuration.base))"
            )
            return .default
        }

        public var body: some View {
            _CompactNativeRepresentable(store: store, configuration: compactConfig)
                .id(compactConfig)
        }
    }

    private struct _CompactNativeRepresentable: UIViewRepresentable {
        let store: StoreOf<Native>
        let configuration: NativeAdClient.Configuration.Compact

        func makeUIView(context: Context) -> CompactNativeAdView {
            CompactNativeAdView(style: configuration.style, metrics: configuration.metrics)
        }

        func updateUIView(
            _ uiView: CompactNativeAdView,
            context: Context
        ) {
            if uiView.style != configuration.style {
                uiView.style = configuration.style
            }
            guard let nativeAd = store.nativeAd else { return }
            // Skip re-bind when the same creative is already attached. SwiftUI
            // re-invokes updateUIView on every store change; without this guard,
            // every state mutation kicks NativeAdView back into asset re-registration.
            guard uiView.nativeAd !== nativeAd else { return }
            uiView.configure(with: nativeAd)
            // Re-ask `sizeThatFits` now that the content (and thus the card height)
            // has changed for the newly bound creative.
            uiView.invalidateIntrinsicContentSize()
        }

        func sizeThatFits(
            _ proposal: ProposedViewSize,
            uiView: CompactNativeAdView,
            context: Context
        ) -> CGSize? {
            guard let width = proposal.width, width > 0, width.isFinite else { return nil }
            let height = uiView.calculateTotalHeight(fittingWidth: width)
            return CGSize(width: width, height: height)
        }
    }
#endif
