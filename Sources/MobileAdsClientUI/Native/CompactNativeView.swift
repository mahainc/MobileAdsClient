//
//  CompactNativeView.swift
//  MobileAdsClient
//

#if canImport(UIKit)
import ComposableArchitecture
import NativeAdClient
import SwiftUI

public struct CompactNativeView: View {

    private let store: StoreOf<Native>

    public init(store: StoreOf<Native>) {
        self.store = store
    }

    private var compactConfig: NativeAdClient.Configuration.Compact {
        if let c = store.configuration.base as? NativeAdClient.Configuration.Compact {
            return c
        }
        assertionFailure("CompactNativeView requires Configuration.Compact, got \(type(of: store.configuration.base))")
        return .default
    }

    public var body: some View {
        _CompactNativeRepresentable(store: store, configuration: compactConfig)
            .id(compactConfig)
            .frame(height: 320)
    }
}

private struct _CompactNativeRepresentable: UIViewRepresentable {
    let store: StoreOf<Native>
    let configuration: NativeAdClient.Configuration.Compact

    func makeUIView(context: Context) -> CompactNativeAdView {
        CompactNativeAdView(style: configuration.style, metrics: configuration.metrics)
    }

    func updateUIView(_ uiView: CompactNativeAdView, context: Context) {
        if uiView.style != configuration.style {
            uiView.style = configuration.style
        }
        guard let nativeAd = store.nativeAd else { return }
        uiView.configure(with: nativeAd)
    }
}
#endif
