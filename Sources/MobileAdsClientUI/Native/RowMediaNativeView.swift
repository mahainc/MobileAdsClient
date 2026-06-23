//
//  RowMediaNativeView.swift
//  MobileAdsClient
//
//  SwiftUI wrapper around `RowMediaNativeAdView`. Extracts a
//  `Configuration.RowMedia` from the store's type-erased `AnyConfiguration`
//  and uses `.id` to recreate the UIKit view when any layout-affecting field
//  flips (constraints are built once in `setupViews()` and are not
//  re-flowable at runtime).
//

#if canImport(UIKit)
    import ComposableArchitecture
    import NativeAdClient
    import SwiftUI

    public struct RowMediaNativeView: View {

        private let store: StoreOf<Native>

        public init(store: StoreOf<Native>) {
            self.store = store
        }

        private var rowMediaConfig: NativeAdClient.Configuration.RowMedia {
            if let c = store.configuration.base as? NativeAdClient.Configuration.RowMedia {
                return c
            }
            assertionFailure(
                "RowMediaNativeView requires Configuration.RowMedia, got \(type(of: store.configuration.base))"
            )
            return .default
        }

        public var body: some View {
            ZStack {
                // Height floor during the skeleton → loaded swap. The `.animation`
                // is scoped to the skeleton's own opacity ONLY — a subtree-wide
                // `.animation(value: nativeAd != nil)` would suppress the eased
                // height change on a refresh (that value doesn't change on refresh).
                RowMediaNativeSkeletonView(configuration: rowMediaConfig)
                    .opacity(store.nativeAd == nil ? 1 : 0)
                    .accessibilityHidden(store.nativeAd != nil)
                    .animation(.easeInOut(duration: 0.25), value: store.nativeAd != nil)

                if store.nativeAd != nil {
                    // Height is state-driven (`store.adHeight`, measured in
                    // `updateUIView`) so a refresh EASES via the `.updateAdHeight`
                    // animation transaction instead of snapping.
                    _RowMediaNativeRepresentable(store: store, configuration: rowMediaConfig)
                        .frame(height: store.adHeight)
                        .transition(.opacity)
                }
            }
            .id(rowMediaConfig)
        }
    }

    private struct _RowMediaNativeRepresentable: UIViewRepresentable {
        let store: StoreOf<Native>
        let configuration: NativeAdClient.Configuration.RowMedia

        func makeUIView(context: Context) -> RowMediaNativeAdView {
            RowMediaNativeAdView(configuration: configuration)
        }

        func updateUIView(
            _ uiView: RowMediaNativeAdView,
            context: Context
        ) {
            if uiView.style != configuration.style {
                uiView.style = configuration.style
            }
            guard let nativeAd = store.nativeAd else { return }
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
