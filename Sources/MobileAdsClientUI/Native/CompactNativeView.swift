//
//  CompactNativeView.swift
//  MobileAdsClient
//

#if canImport(UIKit)
import ComposableArchitecture
import SwiftUI

public struct CompactNativeView: View {

    private let store: StoreOf<Native>
    private let style: CompactNativeAdView.Style

    public init(store: StoreOf<Native>, style: CompactNativeAdView.Style = .default) {
        self.store = store
        self.style = style
    }

    public var body: some View {
        _CompactNativeRepresentable(store: store, style: style)
            .frame(height: 300)
    }
}

private struct _CompactNativeRepresentable: UIViewRepresentable {
    let store: StoreOf<Native>
    let style: CompactNativeAdView.Style

    func makeUIView(context: Context) -> CompactNativeAdView {
        CompactNativeAdView(style: style)
    }

    func updateUIView(_ uiView: CompactNativeAdView, context: Context) {
        if uiView.style != style {
            uiView.style = style
        }
        guard let nativeAd = store.nativeAd else { return }
        uiView.configure(with: nativeAd)
    }
}
#endif
