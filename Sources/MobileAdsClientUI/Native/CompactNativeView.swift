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
            // Skip re-bind when the same creative is already attached. SwiftUI
            // re-invokes updateUIView on every store change; without this guard,
            // every state mutation kicks NativeAdView back into asset re-registration
            // (and would re-measure/re-send the height in a loop).
            guard uiView.nativeAd !== nativeAd else { return }
            let isRebind = uiView.nativeAd != nil
            uiView.configure(with: nativeAd)
            // Measure the new content height off the laid-out width and push it to
            // state so `.frame(height:)` eases it (refresh) or sets it (first bind).
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
