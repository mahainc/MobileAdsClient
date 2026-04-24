//
//  CompactNativeView.swift
//  MobileAdsClient
//

#if canImport(UIKit)
import ComposableArchitecture
import SwiftUI

public struct CompactNativeView: View {

    private let store: StoreOf<Native>

    public init(store: StoreOf<Native>) {
        self.store = store
    }

    public var body: some View {
        _CompactNativeRepresentable(store: store)
            .frame(height: 320)
    }
}

private struct _CompactNativeRepresentable: UIViewRepresentable {
    let store: StoreOf<Native>

    func makeUIView(context: Context) -> CompactNativeAdView {
        CompactNativeAdView(style: store.compactStyle)
    }

    func updateUIView(_ uiView: CompactNativeAdView, context: Context) {
        if uiView.style != store.compactStyle {
            uiView.style = store.compactStyle
        }
        guard let nativeAd = store.nativeAd else { return }
        uiView.configure(with: nativeAd)
    }
}
#endif
