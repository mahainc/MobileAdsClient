//
//  NativeAdView.swift
//  MobileAdsClient
//
//  Created by Thanh Hai Khong on 6/2/25.
//

#if canImport(UIKit)
import ComposableArchitecture
import NativeAdClient
import SwiftUI

public struct NativeView: UIViewRepresentable {

    private let store: StoreOf<Native>

    public init(store: StoreOf<Native>) {
        self.store = store
    }

    private var customConfig: NativeAdClient.Configuration.Custom {
        if let c = store.configuration.base as? NativeAdClient.Configuration.Custom {
            return c
        }
        assertionFailure("NativeView requires Configuration.Custom, got \(type(of: store.configuration.base))")
        return .default
    }

    public func makeUIView(context: Context) -> CustomNativeAdView {
        return CustomNativeAdView(style: customConfig.style)
    }

    public func updateUIView(_ nativeAdView: CustomNativeAdView, context: Context) {
        if nativeAdView.style != customConfig.style {
            nativeAdView.style = customConfig.style
        }
        guard let nativeAd = store.nativeAd else {
            return
        }

        nativeAdView.configure(with: nativeAd)

        DispatchQueue.main.async {
            let totalHeight = nativeAdView.calculateTotalHeight()
            store.send(.updateAdHeight(totalHeight))
        }
    }
}
#endif
