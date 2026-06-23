//
//  RowNativeView.swift
//  MobileAdsClient
//
//  SwiftUI wrapper around `RowNativeAdView`. Extracts a `Configuration.Row`
//  from the store's type-erased `AnyConfiguration` and uses `.id` to recreate
//  the UIKit view when any layout-affecting field flips (constraints are
//  built once in `setupViews()` and are not re-flowable at runtime).
//

#if canImport(UIKit)
    import ComposableArchitecture
    import NativeAdClient
    import SwiftUI

    public struct RowNativeView: View {

        private let store: StoreOf<Native>

        public init(store: StoreOf<Native>) {
            self.store = store
        }

        private var rowConfig: NativeAdClient.Configuration.Row {
            if let c = store.configuration.base as? NativeAdClient.Configuration.Row {
                return c
            }
            assertionFailure("RowNativeView requires Configuration.Row, got \(type(of: store.configuration.base))")
            return .default
        }

        public var body: some View {
            ZStack {
                // Height floor during the skeleton → loaded swap. The `.animation`
                // is scoped to the skeleton's own opacity ONLY — a subtree-wide
                // `.animation(value: nativeAd != nil)` would suppress the eased
                // height change on a refresh (that value doesn't change on refresh).
                RowNativeSkeletonView(configuration: rowConfig)
                    .opacity(store.nativeAd == nil ? 1 : 0)
                    .accessibilityHidden(store.nativeAd != nil)
                    .animation(.easeInOut(duration: 0.25), value: store.nativeAd != nil)

                if store.nativeAd != nil {
                    // Height is state-driven (`store.adHeight`, measured in
                    // `updateUIView`) so a refresh EASES via the `.updateAdHeight`
                    // animation transaction instead of snapping.
                    _RowNativeRepresentable(store: store, configuration: rowConfig)
                        .frame(height: store.adHeight)
                        .transition(.opacity)
                }
            }
            .id(rowConfig)
        }
    }

    private struct _RowNativeRepresentable: UIViewRepresentable {
        let store: StoreOf<Native>
        let configuration: NativeAdClient.Configuration.Row

        func makeUIView(context: Context) -> RowNativeAdView {
            RowNativeAdView(configuration: configuration)
        }

        func updateUIView(
            _ uiView: RowNativeAdView,
            context: Context
        ) {
            if uiView.style != configuration.style {
                uiView.style = configuration.style
            }
            guard let nativeAd = store.nativeAd else { return }
            // Skip re-bind when the same creative is already attached. SwiftUI
            // re-invokes `updateUIView` on every store change, and an unguarded
            // `configure` re-triggers layout in a feedback loop.
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
