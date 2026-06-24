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
                    // Height is self-sized by the representable's `sizeThatFits` off
                    // the laid-out width, so a width-0 first pass self-heals on the
                    // next layout pass (no stuck/blank card).
                    _RowNativeRepresentable(store: store, configuration: rowConfig)
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
            uiView: RowNativeAdView,
            context: Context
        ) -> CGSize? {
            guard let width = proposal.width, width > 0, width.isFinite else { return nil }
            let height = uiView.calculateTotalHeight(fittingWidth: width)
            return CGSize(width: width, height: height)
        }
    }
#endif
