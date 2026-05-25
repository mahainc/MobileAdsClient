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
            // Always in the tree — acts as the container's height floor so the
            // ZStack stays stable across the skeleton → loaded transition.
            // Without this, the representable's `sizeThatFits` returns the
            // chrome's empty-label minimum on the very first layout pass (the
            // UIView is built before `updateUIView` binds the creative), and
            // `.animation` then re-targets mid-flight when the bound size
            // arrives — visible as a dip-and-spring on every load.
            RowNativeSkeletonView(configuration: rowConfig)
                .opacity(store.nativeAd == nil ? 1 : 0)
                .accessibilityHidden(store.nativeAd != nil)

            if store.nativeAd != nil {
                // Self-sizes through the representable's `sizeThatFits`. The
                // skeleton above keeps the ZStack from shrinking if the bound
                // creative measures slightly smaller than the placeholder.
                _RowNativeRepresentable(store: store, configuration: rowConfig)
                    .transition(.opacity)
            }
        }
        .id(rowConfig)
        .animation(.easeInOut(duration: 0.25), value: store.nativeAd != nil)
    }
}

private struct _RowNativeRepresentable: UIViewRepresentable {
    let store: StoreOf<Native>
    let configuration: NativeAdClient.Configuration.Row

    func makeUIView(context: Context) -> RowNativeAdView {
        RowNativeAdView(configuration: configuration)
    }

    func updateUIView(_ uiView: RowNativeAdView, context: Context) {
        if uiView.style != configuration.style {
            uiView.style = configuration.style
        }
        guard let nativeAd = store.nativeAd else { return }
        // Skip re-bind when the same creative is already attached. SwiftUI
        // re-invokes `updateUIView` on every store change, and an unguarded
        // `configure` re-triggers layout in a feedback loop.
        guard uiView.nativeAd !== nativeAd else { return }
        uiView.configure(with: nativeAd)
        // Tell SwiftUI to re-ask `sizeThatFits` now that the content has
        // changed — the bound row height tracks the new creative without a
        // deferred-async height jump.
        uiView.invalidateIntrinsicContentSize()
    }

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
