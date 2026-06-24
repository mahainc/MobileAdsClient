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
            // Height is self-sized by the representable's `sizeThatFits`.
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
            // Bind the creative only when it changes. SwiftUI re-invokes
            // updateUIView on every store change; an unguarded `configure` kicks
            // NativeAdView back into asset re-registration (a layout feedback loop).
            guard uiView.nativeAd !== nativeAd else { return }
            uiView.configure(with: nativeAd)
            // New creative attached — invalidate so SwiftUI re-runs `sizeThatFits`
            // and the card resizes to the new content height.
            uiView.invalidateIntrinsicContentSize()
        }

        // SwiftUI drives the card height from the laid-out width on every layout
        // pass. Returning nil for a 0/invalid width lets a later pass (with a real
        // width) resolve the height, so a slot that first lays out at width 0 never
        // gets stuck blank.
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
