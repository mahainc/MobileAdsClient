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
            // Bind the creative only when it actually changes. SwiftUI re-invokes
            // `updateUIView` on every store change, and an unguarded `configure`
            // re-triggers layout in a feedback loop.
            let isNewCreative = uiView.nativeAd !== nativeAd
            let isRebind = isNewCreative && uiView.nativeAd != nil
            if isNewCreative {
                uiView.configure(with: nativeAd)
            }
            // Re-measure off the CURRENT laid-out width on EVERY pass — not only
            // when the creative changes. A creative that first binds while the view
            // still has no width (e.g. mid navigation-push) would otherwise keep
            // `adHeight == 0` and render invisible permanently, since binding no
            // longer short-circuits the whole method. A later layout pass with a
            // real width then corrects the height; the `> 0.5` guard makes it a
            // no-op once the height is stable, so there is no feedback loop.
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
