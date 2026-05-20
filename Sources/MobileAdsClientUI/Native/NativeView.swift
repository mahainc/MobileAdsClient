//
//  NativeAdView.swift
//  MobileAdsClient
//
//  Created by Thanh Hai Khong on 6/2/25.
//

#if canImport(UIKit)
import ComposableArchitecture
import SwiftUI

public struct NativeView: UIViewRepresentable {
    
    private let store: StoreOf<Native>
    
    public init(store: StoreOf<Native>) {
        self.store = store
    }
    
    public func makeUIView(context: Context) -> CustomNativeAdView {
        return CustomNativeAdView(style: store.adStyle)
    }

    public func updateUIView(_ nativeAdView: CustomNativeAdView, context: Context) {
        if nativeAdView.style != store.adStyle {
            nativeAdView.style = store.adStyle
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
