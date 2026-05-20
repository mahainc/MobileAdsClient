//
//  FullScreenNativeView.swift
//  MobileAdsClient
//
//  SwiftUI wrapper around `FullScreenNativeAdView`. Plugs a loaded
//  `GoogleMobileAds.NativeAd` into the UIKit renderer and relays close-button
//  taps back via the `onClose` closure.
//

#if canImport(UIKit)
@preconcurrency import GoogleMobileAds
import NativeAdClient
import SwiftUI
import UIKit

public struct FullScreenNativeView: UIViewRepresentable {
    private let nativeAd: NativeAd
    private let style: FullScreenNativeAdView.Style
    private let onClose: () -> Void

    public init(
        nativeAd: NativeAd,
        style: FullScreenNativeAdView.Style = .fullScreen,
        onClose: @escaping () -> Void
    ) {
        self.nativeAd = nativeAd
        self.style = style
        self.onClose = onClose
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(onClose: onClose)
    }

    public func makeUIView(context: Context) -> FullScreenNativeAdView {
        let view = FullScreenNativeAdView(style: style)
        view.closeButton.addTarget(
            context.coordinator,
            action: #selector(Coordinator.handleClose),
            for: .touchUpInside
        )
        view.configure(with: nativeAd)
        return view
    }

    public func updateUIView(_ view: FullScreenNativeAdView, context: Context) {
        if view.style != style {
            view.style = style
        }
        context.coordinator.onClose = onClose
        // Avoid re-configuring on every layout pass — causes re-animations
        // inside NativeAdView when SwiftUI re-invokes updateUIView.
        if view.nativeAd !== nativeAd {
            view.configure(with: nativeAd)
        }
    }

    public final class Coordinator {
        var onClose: () -> Void

        init(onClose: @escaping () -> Void) {
            self.onClose = onClose
        }

        @objc func handleClose() {
            onClose()
        }
    }
}
#endif
