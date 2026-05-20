//
//  RowNativeView.swift
//  MobileAdsClient
//
//  SwiftUI wrapper around `RowNativeAdView`. Reads `store.rowLayout` and uses
//  `.id` to recreate the UIKit view when the layout flips (constraints are
//  built once in `setupViews()` and are not re-flowable at runtime).
//

#if canImport(UIKit)
import ComposableArchitecture
import SwiftUI

public struct RowNativeView: View {

    private let store: StoreOf<Native>

    public init(store: StoreOf<Native>) {
        self.store = store
    }

    public var body: some View {
        _RowNativeRepresentable(store: store, layout: store.rowLayout)
            .id(store.rowLayout)
    }
}

private struct _RowNativeRepresentable: UIViewRepresentable {
    let store: StoreOf<Native>
    let layout: RowNativeAdView.Layout

    func makeUIView(context: Context) -> RowNativeAdView {
        RowNativeAdView(style: store.adStyle, layout: layout)
    }

    func updateUIView(_ uiView: RowNativeAdView, context: Context) {
        if uiView.style != store.adStyle {
            uiView.style = store.adStyle
        }
        guard let nativeAd = store.nativeAd else { return }
        uiView.configure(with: nativeAd)
    }
}
#endif
