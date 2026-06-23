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
                .frame(height: store.adHeight)
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
            // NativeAdView back into asset re-registration (and would re-measure/
            // re-send the height in a loop).
            let isNewCreative = uiView.nativeAd !== nativeAd
            let isRebind = isNewCreative && uiView.nativeAd != nil
            if isNewCreative {
                uiView.configure(with: nativeAd)
            }
            // Re-measure off the CURRENT laid-out width on EVERY pass — not only
            // when the creative changes — so a creative that first binds at width 0
            // (e.g. mid navigation-push) isn't stuck at `adHeight == 0` forever; a
            // later layout pass corrects it. The `> 0.5` guard makes it a no-op once
            // stable, so there is no feedback loop.
            DispatchQueue.main.async {
                let width = uiView.bounds.width
                guard width > 0 else { return }
                let height = uiView.calculateTotalHeight(fittingWidth: width)
                guard abs(height - store.adHeight) > 0.5 else { return }
                store.send(.updateAdHeight(height), animation: isRebind ? .easeInOut(duration: 0.3) : nil)
            }
        }
    }
#endif
