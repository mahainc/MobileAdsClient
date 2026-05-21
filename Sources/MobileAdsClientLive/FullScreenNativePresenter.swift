//
//  FullScreenNativePresenter.swift
//  MobileAdsClient
//
//  Loads a native ad via `NativeAdClient`, attaches a `paidEventHandler` that
//  publishes through `AdRevenueClient`, and presents `FullScreenNativeView`
//  in a `UIHostingController` on the top view controller. Wiring lives here
//  so `Live.swift` only holds the closure that delegates in.
//

#if canImport(UIKit)
import ComposableArchitecture
import MobileAdsClient
import MobileAdsClientUI
import NativeAdClient
import SwiftUI
import UIKit
@preconcurrency import GoogleMobileAds

enum FullScreenNativePresenter {
    static func present(
        adUnitID: String,
        style: FullScreenNativeAdView.Style = .fullScreen
    ) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            Task { @MainActor in
                let resumeBox = ResumeOnce()

                @Dependency(\.nativeAdClient) var nativeAdClient

                guard let topVC = UIApplication.shared.topViewController() else {
                    resumeBox.resume(continuation)
                    return
                }

                // Load before presenting so the user never sees a blank screen
                // with a spinner. If the load fails, resume immediately.
                // `NativeAdManager.adLoader(_:didReceive:)` already attaches the
                // `paidEventHandler` so revenue flows without extra wiring.
                let nativeAd: NativeAd
                do {
                    nativeAd = try await nativeAdClient.loadAd(adUnitID, topVC, nil)
                } catch {
                    #if DEBUG
                    print("[FullScreenNativePresenter] load failed adUnit=\(adUnitID) error=\(error.localizedDescription)")
                    #endif
                    resumeBox.resume(continuation)
                    return
                }

                // Re-resolve the top VC — loading may have shuffled it (rare).
                guard let hostVC = UIApplication.shared.topViewController() else {
                    resumeBox.resume(continuation)
                    return
                }

                let content = FullScreenNativeView(
                    nativeAd: nativeAd,
                    style: style,
                    onClose: { [weak hostVC] in
                        hostVC?.presentedViewController?.dismiss(animated: true) {
                            resumeBox.resume(continuation)
                        }
                    }
                )

                let host = UIHostingController(rootView: content)
                host.modalPresentationStyle = .fullScreen
                host.loadViewIfNeeded()
                host.view.frame = hostVC.view.bounds
                host.view.applyBackgroundFill(style.backgrounds.card)
                hostVC.present(host, animated: true)
            }
        }
    }

    /// Guards against double-resume when the dismiss animation completion
    /// races with an unexpected early exit (e.g. a later failure branch).
    @MainActor
    private final class ResumeOnce {
        private var resumed = false
        func resume(_ continuation: CheckedContinuation<Void, Never>) {
            guard !resumed else { return }
            resumed = true
            continuation.resume()
        }
    }
}
#endif
