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
                // Always in the tree — acts as the container's height floor so the
                // ZStack stays stable across the skeleton → loaded transition
                // (mirrors RowNativeView). Replaces the old hard if/else swap, which
                // had no shared floor and stepped when the loaded height differed.
                RowMediaNativeSkeletonView(configuration: rowMediaConfig)
                    .opacity(store.nativeAd == nil ? 1 : 0)
                    .accessibilityHidden(store.nativeAd != nil)

                if store.nativeAd != nil {
                    _RowMediaNativeRepresentable(store: store, configuration: rowMediaConfig)
                        .transition(.opacity)
                }
            }
            .id(rowMediaConfig)
            .animation(.easeInOut(duration: 0.25), value: store.nativeAd != nil)
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
            uiView.configure(with: nativeAd)
            uiView.invalidateIntrinsicContentSize()
        }

        func sizeThatFits(
            _ proposal: ProposedViewSize,
            uiView: RowMediaNativeAdView,
            context: Context
        ) -> CGSize? {
            guard let width = proposal.width, width > 0, width.isFinite else { return nil }
            let height = uiView.calculateTotalHeight(fittingWidth: width)
            return CGSize(width: width, height: height)
        }
    }
#endif
