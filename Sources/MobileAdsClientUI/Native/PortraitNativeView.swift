//
//  PortraitNativeView.swift
//  MobileAdsClient
//
//  SwiftUI wrapper around `PortraitNativeAdView`. Extracts a
//  `Configuration.Portrait` from the store's type-erased `AnyConfiguration`
//  and uses `.id` to recreate the UIKit view when any layout-affecting field
//  flips (constraints are built once in `setupViews()` and are not
//  re-flowable at runtime). Designed to drop into a grid cell — the card
//  self-sizes its height from the cell width via `sizeThatFits`.
//

#if canImport(UIKit)
import ComposableArchitecture
import NativeAdClient
import SwiftUI

public struct PortraitNativeView: View {

    private let store: StoreOf<Native>

    public init(store: StoreOf<Native>) {
        self.store = store
    }

    private var portraitConfig: NativeAdClient.Configuration.Portrait {
        if let c = store.configuration.base as? NativeAdClient.Configuration.Portrait {
            return c
        }
        assertionFailure(
            "PortraitNativeView requires Configuration.Portrait, got \(type(of: store.configuration.base))"
        )
        return .default
    }

    public var body: some View {
        ZStack {
            // Height floor during the skeleton → loaded swap. The `.animation`
            // is scoped to the skeleton's own opacity ONLY (see RowMedia).
            PortraitNativeSkeletonView(configuration: portraitConfig)
                .opacity(store.nativeAd == nil ? 1 : 0)
                .accessibilityHidden(store.nativeAd != nil)
                .animation(.easeInOut(duration: 0.25), value: store.nativeAd != nil)

            if store.nativeAd != nil {
                _PortraitNativeRepresentable(store: store, configuration: portraitConfig)
                    .transition(.opacity)
            }
        }
        .id(portraitConfig)
    }
}

private struct _PortraitNativeRepresentable: UIViewRepresentable {
    let store: StoreOf<Native>
    let configuration: NativeAdClient.Configuration.Portrait

    func makeUIView(context: Context) -> PortraitNativeAdView {
        PortraitNativeAdView(configuration: configuration)
    }

    func updateUIView(
        _ uiView: PortraitNativeAdView,
        context: Context
    ) {
        if uiView.style != configuration.style {
            uiView.style = configuration.style
        }
        guard let nativeAd = store.nativeAd else { return }
        // Bind the creative only when it changes (an unguarded `configure`
        // re-triggers layout in a feedback loop on every store change).
        guard uiView.nativeAd !== nativeAd else { return }
        uiView.configure(with: nativeAd)
        uiView.invalidateIntrinsicContentSize()
    }

    // SwiftUI drives the card height from the laid-out width on every layout
    // pass. Returning nil for a 0/invalid width lets a later pass resolve the
    // height, so a cell that first lays out at width 0 never gets stuck blank.
    func sizeThatFits(
        _ proposal: ProposedViewSize,
        uiView: PortraitNativeAdView,
        context: Context
    ) -> CGSize? {
        guard let width = proposal.width, width > 0, width.isFinite else { return nil }
        let height = uiView.calculateTotalHeight(fittingWidth: width)
        return CGSize(width: width, height: height)
    }
}
#endif
