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
            keywords: [String] = [],
            configuration: FullScreenNativeAdView.Configuration = .default,
            adChoicesCorner: NativeAdClient.AdChoicesPositionOption.Corner = .bottomLeft,
            mediaAspectRatio: NativeAdClient.MediaAspectRatioOption.Ratio? = nil,
            videoStartsMuted: Bool = true,
            onColdLoad: (@Sendable (AdLoadPhase) -> Void)? = nil
        ) async -> Bool {
            await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
                Task { @MainActor in
                    let resumeBox = ResumeOnce()

                    @Dependency(\.nativeAdClient) var nativeAdClient

                    guard let topVC = UIApplication.shared.topViewController() else {
                        resumeBox.resume(continuation, didShow: false)
                        return
                    }

                    // Loader options for the full-screen layout: pin AdChoices to the
                    // bottom-left. With full-bleed media a top corner puts AdChoices
                    // under the status bar / Dynamic Island (the AdMob validator flags
                    // it as obstructed), and the top-left also holds our close button
                    // / countdown. Bottom-left is clear of the chrome and validates
                    // clean. Start any video muted; media aspect ratio unrestricted.
                    var options: [NativeAdClient.AnyAdLoaderOption] = [
                        .init(NativeAdClient.AdChoicesPositionOption(corner: adChoicesCorner)),
                        .init(NativeAdClient.VideoPlaybackOption(shouldStartMuted: videoStartsMuted)),
                    ]
                    if let mediaAspectRatio {
                        options.append(.init(NativeAdClient.MediaAspectRatioOption(ratio: mediaAspectRatio)))
                    }

                    // Load before presenting so the user never sees a blank screen
                    // with a spinner. If the load fails, resume immediately.
                    // `NativeAdManager.adLoader(_:didReceive:)` already attaches the
                    // `paidEventHandler` so revenue flows without extra wiring.
                    let nativeAd: NativeAd
                    onColdLoad?(.started)
                    do {
                        nativeAd = try await nativeAdClient.loadAd(adUnitID, topVC, options, keywords)
                        onColdLoad?(.ready)
                    } catch {
                        onColdLoad?(.failed)
                        #if DEBUG
                            print(
                                "[FullScreenNativePresenter] load failed adUnit=\(adUnitID) error=\(error.localizedDescription)"
                            )
                        #endif
                        resumeBox.resume(continuation, didShow: false)
                        return
                    }

                    // Re-resolve the top VC — loading may have shuffled it (rare).
                    guard let hostVC = UIApplication.shared.topViewController() else {
                        resumeBox.resume(continuation, didShow: false)
                        return
                    }

                    let content = FullScreenNativeView(
                        nativeAd: nativeAd,
                        configuration: configuration,
                        onClose: { [weak hostVC] in
                            hostVC?.presentedViewController?.dismiss(animated: true) {
                                resumeBox.resume(continuation, didShow: true)
                            }
                        }
                    )

                    let host = UIHostingController(rootView: content)
                    host.modalPresentationStyle = .fullScreen
                    host.loadViewIfNeeded()
                    host.view.frame = hostVC.view.bounds
                    host.view.applyBackgroundFill(configuration.style.backgrounds.card)
                    hostVC.present(host, animated: true)
                }
            }
        }

        /// Guards against double-resume when the dismiss animation completion
        /// races with an unexpected early exit (e.g. a later failure branch).
        /// `didShow` is true only when the ad was actually presented and dismissed.
        @MainActor
        private final class ResumeOnce {
            private var resumed = false
            func resume(
                _ continuation: CheckedContinuation<Bool, Never>,
                didShow: Bool
            ) {
                guard !resumed else { return }
                resumed = true
                continuation.resume(returning: didShow)
            }
        }
    }
#endif
